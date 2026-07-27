# Security Model

The core guarantee: **no packet leaves via eth0 except the VPN endpoint itself and explicitly whitelisted local networks — for both address families — even while the tunnel is down, connecting, or crashed.**

## Fail-closed by construction

The startup sequence is a dependency graph, not a script: the s6-rc service graph makes the firewall oneshot a hard prerequisite of the VPN service. `openconnect` **cannot start** before the kill switch is installed, and a firewall failure aborts the container instead of running unprotected. On disconnect or crash, the firewall is deliberately left untouched — routes die with the tun interface, the drop policy stays.

## The kill switch

One dual-family nftables table, `inet vpn`, with `policy drop` on input, output and forward:

```
table inet vpn {
    set endpoint4 { type ipv4_addr . inet_service; }   # VPN server pinholes
    set endpoint6 { type ipv6_addr . inet_service; }
    set lan4 { type ipv4_addr; flags interval; }        # NETWORK
    set lan6 { type ipv6_addr; flags interval; }        # NETWORK6
    set bootstrap_dns4 { type ipv4_addr; }              # resolv.conf resolvers, pre-connect only
    set bootstrap_dns6 { type ipv6_addr; }
    set gw_clients4 { type ipv4_addr; flags interval; } # gateway source CIDRs
    set gw_clients6 { type ipv6_addr; flags interval; }

    chain output {  # policy drop
        oifname "lo" accept
        ct state established,related accept
        oifname "tun0" accept                            # tunneled traffic
        icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit } accept
        ip  daddr . tcp dport @endpoint4 accept          # the VPN server, TCP
        ip6 daddr . tcp dport @endpoint6 accept
        ip  daddr . udp dport @endpoint4 accept          # DTLS (absent when DTLS=off)
        ip6 daddr . udp dport @endpoint6 accept
        oifname "eth0" ip  daddr @lan4 accept            # whitelisted LAN
        oifname "eth0" ip6 daddr @lan6 accept
        oifname "eth0" daddr @bootstrap_dns* {udp,tcp} dport 53 accept   # until first connect
    }
    chain input {   # policy drop
        iifname "lo" accept
        ct state established,related accept
        icmpv6 ND accepts
        iifname "eth0" saddr @lan4/@lan6 accept          # published-port access
        (+ port 53 from clients in GATEWAY_DNS=local mode)
    }
    chain forward { # policy drop — see Gateway Mode
        MSS clamp; @gw_clients* eth0→tun0 accept; established tun0→eth0 accept
    }
}
```

Details that matter:

- **Endpoint sets concatenate address and port**, so each entry of a failover URL list keeps its own port, and only the exact `ip:port` of your server(s) is reachable.
- **Named sets are swapped atomically** (single nft transaction) on every reconnect — there is no instant where the table is half-updated or wide open.
- **`oifname tun0 accept` is installed from the start**: the interface doesn't exist until openconnect connects, so the rule cannot match early; traffic via tun0 is by definition inside the tunnel.
- **ICMPv6 neighbor discovery** is stateless and required for IPv6 on eth0; only the specific ND types are allowed.
- The `oifname "tun0"` accept combined with dropped eth0 means **a v4-only firewall bypass via IPv6 is impossible** — both families share one table and one policy.
- A second, separate table `inet vpn_mss` (mangle priority, `policy accept`) clamps the TCP MSS of the container's own eth0 traffic — path MTU by default, a hard cap with the `MSS` variable. It only rewrites the MSS option of SYN packets and **cannot accept traffic the kill switch drops**: acceptance is decided solely by `inet vpn`, which is why the clamp lives outside it.

## The bootstrap DNS hole — lifecycle

Before the first connect, the server hostname must be resolvable, so the resolvers currently in `/etc/resolv.conf` (Docker's, typically) are allowed on port 53 via the `@bootstrap_dns*` sets. The hole is:

1. **opened** at firewall install,
2. **closed** on connect (sets flushed — DNS then flows through the tunnel),
3. **reopened** only after a disconnect restores the original `resolv.conf`, so a reconnect can resolve again.

At no point are arbitrary port-53 destinations allowed — only the specific resolver addresses.

## DNS re-resolution and endpoint pinning

On every (re)connect the hostname is re-resolved, all resolved addresses are swapped into the endpoint sets, and the connection is made to a pinned IP via `--resolve` (TLS keeps the hostname for SNI/verification). This closes the race where a post-lockdown DNS answer points somewhere the firewall doesn't allow — the firewall and the dialed address always agree.

## Secrets handling

- The camouflage secret is redacted (`?<redacted>`) in all log output, including openconnect's own (filtered through a literal-substring redactor).
- The password goes to openconnect via stdin, never argv; `PASS_FILE`/Docker secrets keep it out of `docker inspect`.
- The parsed URL list on tmpfs is mode 0600.

## What is *not* protected

- **`docker inspect`** shows environment variables — `URL` (with secret) and `PASS` if you use it directly. Use `PASS_FILE`; accept that the camouflage secret in `URL` has the same exposure any env var would.
- **The Docker host itself** — root on the host owns the container.
- **Whitelisted subnets** (`NETWORK`/`NETWORK6`) are reachable in the clear by design.
- **INSECURE=true** removes server authentication at connect time — see [[Authentication]].

## Verifying the kill switch

```bash
# While connected: direct eth0 egress must fail
docker exec vpn curl --interface eth0 -s --max-time 3 https://1.1.1.1 || echo BLOCKED

# While the server is down: nothing leaves at all
docker stop ocserv-server
docker exec vpn curl -s --max-time 3 https://1.1.1.1 || echo BLOCKED

# Inspect the live ruleset
docker exec vpn nft list table inet vpn
```
