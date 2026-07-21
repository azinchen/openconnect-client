# Gateway DNS

Gateway clients need DNS that (a) travels through the tunnel and (b) can use the tunnel-pushed resolvers. The image handles this **without any DNS daemon** — interception is pure nftables NAT, chosen by `GATEWAY_DNS`. (Only relevant with `GATEWAY_MODE=true`; see [[Gateway Mode]].)

## `redirect` (default)

Client port-53 traffic (UDP and TCP, both families) is DNAT-ed to the tunnel-pushed resolvers — or your `DNS` override. The target is refreshed **atomically on every (re)connect**, the same pattern as the kill switch's endpoint sets, so resolver changes never leave a stale rule.

Queries deliberately aimed at an address **inside this network namespace** (`fib daddr type local`) pass untouched, so `redirect` composes with a co-located resolver: clients that opt in to it reach it, everyone else gets the tunnel resolvers.

Zero daemons, zero configuration — DNS "just works" for gateway clients even if they have some unrelated resolver configured.

## `local`

**All** client port-53 traffic is DNAT-ed to the container's own address — including clients with hardcoded public DNS (smart TVs and friends). Use this to run a real resolver co-located in the VPN namespace:

```yaml
  vpn:
    # ... gateway mode config ...
    environment:
      - GATEWAY_DNS=local
      - DNS=127.0.0.1        # the netns itself also resolves via AdGuard
      - NETWORK=192.168.1.0/24   # LAN may reach the AdGuard admin UI

  adguard:
    image: adguard/adguardhome:latest
    network_mode: "service:vpn"
    depends_on: [vpn]
    volumes:
      - ./adguard/work:/opt/adguardhome/work
      - ./adguard/conf:/opt/adguardhome/conf
    restart: unless-stopped
```

Why this composition is the recommended full-featured path:

- The resolver's upstream traffic (DoH/DoT/plain) follows the namespace's tun0 default route — **tunneled and kill-switch-protected automatically**, no extra rules.
- Filtering, caching, per-client stats and a UI live where they belong: in a purpose-built container you pick and upgrade independently.
- In `local` mode the firewall input chain accepts port 53 from the gateway client sets *and* from `NETWORK`/`NETWORK6`, so LAN hosts can also use the resolver directly.

**Bootstrap caveat:** the resolver starts behind the fail-closed firewall *before* the tunnel is up, so it cannot resolve its own upstream hostnames at that point. Configure its upstreams as plain IPs, or set its bootstrap DNS to IPs (AdGuard: *Settings → DNS → Bootstrap DNS*).

## `forward`

**All** client port-53 traffic is DNAT-ed to an external resolver named by `GATEWAY_DNS_SERVER`, reached **directly over eth0** — a resolver on your LAN or another container that is *not* in this VPN's network namespace (e.g. an existing AdGuard Home you already run elsewhere):

```yaml
  vpn:
    # ... gateway mode config ...
    environment:
      - GATEWAY_DNS=forward
      - GATEWAY_DNS_SERVER=192.168.1.50        # LAN AdGuard; ;-list may add one IPv6
```

Like `local`, this forces capture of clients with hardcoded public DNS. Unlike `local`, the resolver is a separate host, so the gateway:

- DNATs the query to `GATEWAY_DNS_SERVER` and **masquerades** it, so the resolver replies to the gateway (which un-NATs back to the client);
- **pins a host route** to the resolver over eth0 when it is off-subnet, so the tunnel's default routes can't hijack the query. A resolver on a connected subnet (same LAN/Docker network) needs no pin.

> **⚠️ This resolver's upstream queries are outside the tunnel and the kill switch.** The gateway delivers the client's query to `GATEWAY_DNS_SERVER` over eth0 in the clear, and that resolver then does its *own* upstream resolution wherever its host routes it — not through this VPN. Use `forward` when the external resolver is trusted LAN infrastructure; if you need the resolver's upstream tunneled too, run it co-located instead (`local`).

`GATEWAY_DNS_SERVER` accepts one IPv4 and/or one IPv6 (`;`- or `,`-separated); each family's clients are forwarded to the matching address.

## `off`

No interception. Clients use whatever resolver they are configured with; their queries are routed through the tunnel like any other traffic.

## Caveat: Docker's embedded DNS

Compose containers that resolve via Docker's embedded DNS (`127.0.0.11`) have their lookups forwarded **by the Docker host**, not through the gateway — interception cannot see them. This applies to every mode. Give such clients an explicit resolver:

```yaml
  some-client:
    dns:
      - 192.168.1.2      # the gateway's address
```

## Verifying interception

Point a routed client's resolver at an address that is definitely *not* a DNS server (e.g. `192.0.2.1`, TEST-NET). If names still resolve, interception is doing its job:

```bash
echo 'nameserver 192.0.2.1' > /etc/resolv.conf
nslookup example.com        # works in redirect/local/forward mode, times out in off mode
```
