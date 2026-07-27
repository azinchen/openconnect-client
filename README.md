# OpenConnect VPN Client Docker container

[![CI - Build and Deploy](https://github.com/azinchen/openconnect-client/actions/workflows/ci-build-deploy.yml/badge.svg)](https://github.com/azinchen/openconnect-client/actions/workflows/ci-build-deploy.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/azinchen/openconnect-client)](https://hub.docker.com/r/azinchen/openconnect-client)

OpenConnect VPN client in a Docker container that routes other containers'
traffic through an ocserv / Cisco AnyConnect-compatible server, with a
dual-stack fail-closed kill switch. Built as the companion client for
[azinchen/ocserv-server](https://github.com/azinchen/ocserv-server): same
configuration style, and a "route other containers through
`network_mode: service:vpn`" workflow. Since it runs the plain `openconnect`
client it also connects to GlobalProtect, Pulse/Ivanti, Fortinet and other
servers via `PROTOCOL`.

Full documentation lives in the
[project wiki](https://github.com/azinchen/openconnect-client/wiki).

## ✨ Features

- 🔗 **Shared-netns forwarding** — containers started with
  `network_mode: service:vpn` transparently send all traffic through the
  tunnel.
- 🌍 **Gateway mode** — the container can act as a NAT gateway for other
  containers on the same Docker network and for LAN hosts (macvlan/routed
  setups), with daemon-free DNS interception for the clients (pure
  nftables DNAT — no resolver process in the image).
- 🌐 **Full dual-stack IPv4 + IPv6** — connect to the server over IPv4 or IPv6,
  accept both an IPv4 and an IPv6 address from the server, route and firewall
  both families.
- 🔒 **Fail-closed kill switch** — a single nftables `inet` table drops both
  address families by default; only the VPN endpoint itself and explicitly
  whitelisted local networks may leave via `eth0`. The firewall is installed
  before openconnect is allowed to start and is never removed on disconnect.
- 🔁 **Ordered failover** — `URL` accepts a `;`-separated server list; the
  client advances to the next entry after repeated failures.
- 🕵️ **Camouflage support** — append the ocserv camouflage secret to the URL
  (`https://host:port/?secret`); it is redacted in all log output.
- 🛠️ **Operational conveniences** — supervised reconnect with backoff, optional
  Docker HEALTHCHECK, LAN return routes, small multi-arch Alpine image.

## 🚀 Quick start

```yaml
services:
  vpn:
    image: azinchen/openconnect-client:latest
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    sysctls:
      - net.ipv6.conf.all.disable_ipv6=0
    environment:
      - URL=https://vpn.example.com:8443/?mysecret
      - USER=alex
      - PASS=secret
      - CA_FILE=/openconnect-client/ca.pem
      - NETWORK=192.168.1.0/24
    volumes:
      - ./config:/openconnect-client:ro
    ports:
      - "8080:80"          # app UI published on the vpn service
  app:
    image: nginx:alpine
    network_mode: "service:vpn"
    depends_on:
      - vpn
```

Everything the `app` container sends now goes through the tunnel — or
nowhere. See the wiki's
[Docker Compose Examples](https://github.com/azinchen/openconnect-client/wiki/Docker-Compose-Examples)
for complete compositions of both modes.

## 🔗 Connection URL

A single `URL` variable carries host, port and camouflage secret, matching
openconnect's own positional argument and ocserv's camouflage semantics:

```
URL=https://vpn.example.com                    # port 443, no camouflage
URL=https://vpn.example.com:8443/?mysecret     # custom port + camouflage
URL=vpn.example.com                            # bare host, https:// implied
URL=https://[2001:db8::1]:8443                 # IPv6 literal
URL=https://a.example.com;https://b.example.com:8443/?s2   # ordered failover
```

Only `https` is accepted; the port (default 443) applies to both TCP and
DTLS; each list entry is a complete URL with its own port and secret. The
query string is passed to openconnect verbatim and redacted in logs (note:
like any environment variable it remains visible in `docker inspect`).

## ⚙️ Environment variables

| Variable | Default | Description |
|---|---|---|
| `URL` | — (required) | `https://host[:port][/][?camouflage_secret]`; bare host accepted; `;`-list for ordered failover |
| `CONNECT_FAMILY` | `auto` | Control-channel address family: `auto` \| `ipv4` \| `ipv6`. `auto` prefers IPv6 when eth0 has a global IPv6 route |
| `PROTOCOL` | `anyconnect` | openconnect protocol: `anyconnect` \| `gp` \| `pulse` \| `fortinet` \| `nc` \| `array` |
| `USER` / `PASS` / `PASS_FILE` | — | Password auth (`PASS_FILE` for Docker secrets) |
| `CERT_FILE` / `KEY_FILE` / `CERT_PASS` | — | Certificate auth (`.p12`/`.pfx`, or PEM cert+key pair) |
| `CA_FILE` | — | CA certificate to trust (preferred for self-hosted servers) |
| `SERVERCERT` | — | `pin-sha256:...` server certificate pin |
| `INSECURE` | `false` | Skip server verification (loudly logged, unsafe) |
| `DTLS` | `on` | UDP data channel toggle (uses the URL's port) |
| `MTU` | auto | Override tun MTU |
| `MSS` | _(unset)_ | Clamp the MSS of the control connection to the VPN server. Unset clamps to the path MTU (a no-op on plain 1500 links). Set a number (e.g. `1300`) to force a hard cap when the path to the server has a smaller MTU than `eth0` and PMTUD is broken - a remote black hole (VPS), PPPoE, tunnelled uplinks - where full-size segments would otherwise be silently dropped and the tunnel would carry no data. (Forwarded LAN traffic is always clamped to the tunnel MTU.) |
| `SPLIT_TUNNEL` | `false` | Honor server-pushed split routes instead of forcing full-tunnel |
| `IPV6_MODE` | `auto` | Tunnel IPv6 data plane: `auto` (use if pushed, never leak) \| `require` (reconnect until dual-stack) \| `off` |
| `NETWORK` / `NETWORK6` | — | `;`-list of LAN CIDRs allowed to reach the container via eth0 (return routes + firewall) |
| `GATEWAY_MODE` | `false` | Enable forwarding/NAT gateway for other-netns clients |
| `FORWARD_FROM` / `FORWARD_FROM6` | eth0 subnets | Source CIDRs allowed to use the gateway |
| `GATEWAY_NAT6` | `true` | NAT66 masquerade (default) vs pure IPv6 routing |
| `GATEWAY_DNS` | `redirect` | Gateway-client DNS interception: `redirect` (DNAT port 53 to the tunnel-pushed resolvers) \| `local` (DNAT port 53 to this container, for a co-located resolver) \| `forward` (DNAT port 53 to an external resolver reached directly over eth0, e.g. a LAN AdGuard — set `GATEWAY_DNS_SERVER`) \| `off` |
| `GATEWAY_DNS_SERVER` | — | External resolver IP(s) for `GATEWAY_DNS=forward` (`;`-list, one IPv4 and/or one IPv6). Reached directly, **not** through the tunnel |
| `DNS` | pushed | Override DNS servers (`;`-list, IPv4/IPv6 mixed; `127.0.0.1` to use a co-located resolver for the netns itself) |
| `RECONNECT_DELAY` | `5` | Base delay between reconnect attempts (exponential backoff, capped at 300s) |
| `HEALTH_CHECK_ENABLED` | `false` | Enable the Docker HEALTHCHECK probe |
| `CHECK_CONNECTION_URL` | `https://www.google.com` | Probe URL(s), probed through the tunnel |
| `OPENCONNECT_OPTS` | — | Extra raw openconnect arguments |
| `TZ` | — | Container time zone |
| `NETWORK_DIAGNOSTIC_ENABLED` | `false` | Verbose route/nft dumps after connect |

## 🔐 Authentication and server trust

Mirrors ocserv's auth modes: password (`USER` + `PASS`/`PASS_FILE`, piped via
`--passwd-on-stdin`), certificate (`CERT_FILE` as `.p12`/`.pfx` with optional
`CERT_PASS`, or PEM `CERT_FILE` + `KEY_FILE`), or both simultaneously
(ocserv `auth = certificate` + `enable-auth = plain`). Mount cert material
into `/openconnect-client`.

Server trust, in order of preference: `CA_FILE` (mount the ocserv-server CA),
`SERVERCERT` (`pin-sha256:` pin for self-signed setups), a publicly valid
certificate, or the `INSECURE=true` escape hatch.

## 🔀 Traffic modes

### Mode A — shared network namespace

Co-located containers (`network_mode: service:vpn`) share the VPN
container's network stack, so tunnel routes and the kill switch protect them
identically. Publish the app's ports on the **vpn** service and list the LAN
subnets that need to reach those ports in `NETWORK`/`NETWORK6`. This is the
recommended mode for compose stacks.

### Mode B — gateway mode

`GATEWAY_MODE=true` turns the container into a NAT gateway for clients that
keep their own network namespace: containers on the same Docker network and
LAN hosts with a route (or macvlan default gateway) pointing at the
container. Requires forwarding sysctls from the runtime:

```yaml
sysctls:
  - net.ipv4.ip_forward=1
  - net.ipv6.conf.all.forwarding=1
  - net.ipv6.conf.all.disable_ipv6=0
```

`FORWARD_FROM`/`FORWARD_FROM6` limit which sources may use the gateway
(default: the container's own eth0 subnets). IPv6 is masqueraded (NAT66) by
default because ocserv assigns a single client address; set
`GATEWAY_NAT6=false` if your server routes the client subnet.

**Gateway-client DNS** is handled without any daemon in the image, chosen by
`GATEWAY_DNS`:

- `redirect` (default) — client port-53 traffic is DNAT-ed to the
  tunnel-pushed resolvers (updated atomically on every reconnect). Queries
  deliberately aimed at an address inside this netns pass untouched.
- `local` — **all** client port-53 traffic (including hardcoded public DNS
  on smart TVs and the like) is DNAT-ed to the container itself, for a
  full-featured resolver (AdGuard Home, Pi-hole, unbound) running
  co-located in `network_mode: service:vpn`. The resolver's upstream
  traffic follows the tunnel and the kill switch automatically. This is the
  recommended setup for full-time gateway use — see the wiki's
  [Docker Compose Examples](https://github.com/azinchen/openconnect-client/wiki/Docker-Compose-Examples).
- `forward` — **all** client port-53 traffic is DNAT-ed to an external
  resolver (`GATEWAY_DNS_SERVER`, e.g. an AdGuard Home on the LAN) reached
  directly over eth0, **not** through the tunnel.
- `off` — no interception; clients use whatever resolver they are
  configured with, routed through the tunnel like ordinary traffic.

Caveat (all modes): compose containers using Docker's embedded DNS
(`127.0.0.11`) resolve via the *host*, bypassing the gateway; give such
clients an explicit `dns:` pointing at a routable IP.

## 🌐 IPv6

Both families are dropped by default in one nftables table, so an
IPv6-enabled Docker network cannot leak around an IPv4-only firewall. The
tunnel's IPv6 data plane requires the server to push an IPv6 address (the
`IPV6_*` variables of azinchen/ocserv-server); `IPV6_MODE` controls what
happens when it doesn't: `auto` runs IPv4-only and keeps IPv6 dropped,
`require` treats it as a connection failure, `off` never asks for IPv6.
Connectivity *to* the server over IPv6 additionally needs an IPv6-enabled
Docker network (`enable_ipv6: true`); the tunnel's IPv6 works regardless
once the session is up over IPv4.

## 🩺 Health check

The image ships a Docker HEALTHCHECK (60s interval) that is neutral until
`HEALTH_CHECK_ENABLED=true`. When enabled it verifies the tun interface and
its addresses, then probes `CHECK_CONNECTION_URL` through the tunnel
(IPv4, plus IPv6 when `IPV6_MODE=require`). Combine with an
autoheal-style restarter to recycle an unhealthy container.

## 📋 Runtime requirements

- `--cap-add=NET_ADMIN` and `/dev/net/tun`
- a kernel with nftables support (any modern host)
- for gateway mode: the forwarding sysctls shown above

## 📄 License

[MIT](LICENSE)
