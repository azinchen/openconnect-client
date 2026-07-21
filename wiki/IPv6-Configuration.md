# IPv6 Configuration

The image is fully dual-stack, and — just as important — **fail-closed for both families**: IPv4 and IPv6 are dropped by default in one nftables `inet` table, so an IPv6-enabled Docker network can never leak around an IPv4-only firewall.

There are two independent IPv6 dimensions:

## 1. Control channel — reaching the server over IPv6

Governed by `CONNECT_FAMILY` (see [[Connection URL]]). For `auto`/`ipv6` to actually use IPv6, the **Docker network** must provide it:

```yaml
networks:
  default:
    enable_ipv6: true
```

or daemon-wide `ipv6: true` + `ip6tables: true`. Without a global IPv6 route on eth0, `auto` quietly prefers IPv4.

If the runtime has no IPv6 at all (`/proc/net/if_inet6` missing or `disable_ipv6` locked to 1), the image logs it and degrades to IPv4; `CONNECT_FAMILY=ipv6` or `IPV6_MODE=require` then fail fast with a clear error.

## 2. Data plane — IPv6 *inside* the tunnel

Independent of the control channel: the tunnel's IPv6 works even when the session runs over IPv4.

The server must assign an IPv6 address. For [ocserv-server](https://github.com/azinchen/ocserv-server) that means its IPv6 pool options (`ipv6-network` / `ipv6-subnet-prefix`, i.e. its `IPV6_*` settings). When the server pushes an address, the client configures it on `tun0` and installs `::/1` + `8000::/1` half-default routes.

`IPV6_MODE` decides what happens when the server pushes **no** IPv6 address:

| Value | Behavior |
|---|---|
| `auto` (default) | Run IPv4-only. IPv6 egress via eth0 stays **dropped** — no leak, no broken half-configured state |
| `require` | Treat a v4-only tunnel as a connection failure: kill the session and reconnect (with backoff) until dual-stack. The health check also requires a working IPv6 path |
| `off` | Never request IPv6 (`--disable-ipv6`); v6 handling is skipped everywhere, and gateway DNS interception installs no v6 rules |

## Gateway mode and IPv6

- Forwarded client IPv6 is masqueraded (**NAT66**) by default — ocserv assigns a single client address, so routed v6 from a whole subnet would otherwise be dropped by the server. If your server routes the client subnet, set `GATEWAY_NAT6=false` for pure routing.
- The forwarding sysctl `net.ipv6.conf.all.forwarding=1` is required (verified at startup with an actionable error).
- If the tunnel comes up v4-only, forwarded client IPv6 has no route out and is dropped by the forward chain — fail-closed, clients fall back to IPv4 themselves.

## Neighbor discovery

ICMPv6 neighbor discovery is stateless and required for any IPv6 on eth0; the kill switch explicitly permits the ND message types both ways while still dropping everything else. No configuration needed — mentioned here so a packet capture doesn't surprise you.

## Quick checks

```bash
# Tunnel got an IPv6 address?
docker exec vpn ip -6 addr show dev tun0 scope global

# IPv6 default-ish routes present?
docker exec vpn ip -6 route show | grep -E '^(::/1|8000::/1)'

# IPv6 egress through the tunnel?
docker exec vpn curl -6 -s --max-time 10 https://api64.ipify.org
```
