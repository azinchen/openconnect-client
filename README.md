# OpenConnect VPN Client Docker container

[![GitHub release][github-release]][github-releases]
[![GitHub release date][github-releasedate]][github-releases]
[![GitHub build][github-build]][github-actions]<br>
[![GitHub stars][github-stars]][github-link]
[![GitHub forks][github-forks]][github-link]
[![Open issues][github-issues]][github-issues-link]
[![GitHub last commit][github-lastcommit]][github-link]<br>
[![Docker pulls][dockerhub-pulls]][dockerhub-link]
[![Docker stars][dockerhub-stars]][dockerhub-link]
[![Docker image size][dockerhub-size]][dockerhub-link]<br>
[![Multi-arch][multiarch-badge]][dockerhub-link]

OpenConnect VPN client in a Docker container that routes other containers'
traffic through an ocserv / Cisco AnyConnect-compatible server, with a
dual-stack fail-closed kill switch. Built as the companion client for
[azinchen/ocserv-server](https://github.com/azinchen/ocserv-server): same
configuration style, and a "route other containers through
`network_mode: service:vpn`" workflow. Since it runs the plain `openconnect`
client it also connects to GlobalProtect, Pulse/Ivanti, Fortinet and other
servers via `PROTOCOL`.

Full documentation lives in the [project wiki][wiki-home].

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
nowhere. See the wiki's [Docker Compose Examples][wiki-compose] for complete
compositions of both modes.

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

Grouped by feature; every variable is one line here — the
**[Configuration Reference][wiki-config]** has the full descriptions.

### Connection — [details][wiki-url]

| Variable | Default | Description |
|---|---|---|
| `URL` | — (required) | `https://host[:port][/][?camouflage_secret]`; bare host accepted; `;`-list for ordered failover. |
| `CONNECT_FAMILY` | `auto` | Control-channel address family: `auto` \| `ipv4` \| `ipv6`. `auto` prefers IPv6 when eth0 has a global IPv6 route. |
| `PROTOCOL` | `anyconnect` | openconnect protocol: `anyconnect` \| `gp` \| `pulse` \| `fortinet` \| `nc` \| `array` ([details][wiki-protocols]). |
| `DTLS` | `on` | `off` disables the UDP data channel (it uses the URL's port). |
| `SPLIT_TUNNEL` | `false` | Honor server-pushed split routes instead of forcing full-tunnel. |
| `OPENCONNECT_OPTS` | — | Extra raw `openconnect` arguments, appended verbatim. |

### Authentication and server trust — [details][wiki-auth]

| Variable | Default | Description |
|---|---|---|
| `USER` | — | Username for password auth. |
| `PASS` | — | Password; piped to openconnect on stdin, never on the command line. |
| `PASS_FILE` | — | Read the password from a file (Docker secret); `PASS` wins if both are set. |
| `CERT_FILE` | — | Client certificate: a `.p12`/`.pfx` bundle, or a PEM certificate with `KEY_FILE`. |
| `KEY_FILE` | — | PEM private key when `CERT_FILE` is a PEM certificate. |
| `CERT_PASS` | — | Passphrase for the key or bundle. |
| `CA_FILE` | — | CA certificate to trust (preferred for self-hosted servers). |
| `SERVERCERT` | — | `pin-sha256:...` server certificate pin — no CA file needed. |
| `INSECURE` | `false` | Skip server certificate verification (loudly logged, unsafe). |

### Tunnel tuning

| Variable | Default | Description |
|---|---|---|
| `MTU` | _(auto)_ | Override the tun MTU; otherwise the server-provided value is used ([details][wiki-protocols]). |
| `MSS` | _(unset)_ | Hard-cap the TCP MSS of the control connection to the server (e.g. `1300`) when the path MTU is small and PMTUD is broken; unset clamps to the path MTU. |
| `TTL_SET` | _(unset)_ | Rewrite the TTL/hop-limit of traffic leaving through the tunnel (e.g. `64`); hides every hop behind this container from client traceroutes ([details][wiki-ttl]). |

### IPv6 — [details][wiki-ipv6]

| Variable | Default | Description |
|---|---|---|
| `IPV6_MODE` | `auto` | Tunnel IPv6 data plane: `auto` (use if pushed, never leak) \| `require` (reconnect until dual-stack) \| `off`. |

### Local network access — [details][wiki-lan]

| Variable | Default | Description |
|---|---|---|
| `NETWORK` | — | `;`-list of IPv4 LAN CIDRs allowed to reach the container via eth0 (return routes + firewall). |
| `NETWORK6` | — | Same for IPv6 CIDRs. |

### Gateway mode — [details][wiki-gateway]

| Variable | Default | Description |
|---|---|---|
| `GATEWAY_MODE` | `false` | Act as a forwarding/NAT gateway for other-netns containers and LAN hosts. |
| `FORWARD_FROM` | eth0 subnets | `;`-list of IPv4 source CIDRs allowed to use the gateway. |
| `FORWARD_FROM6` | eth0 subnets | Same for IPv6. |
| `GATEWAY_NAT6` | `true` | Masquerade IPv6 (NAT66); `false` for pure routing when the server routes the client subnet. |
| `GATEWAY_DNS` | `redirect` | Gateway-client DNS interception: `redirect` \| `local` \| `forward` \| `off` ([details][wiki-gateway-dns]). |
| `GATEWAY_DNS_SERVER` | — | External resolver IP(s) for `GATEWAY_DNS=forward` (one IPv4 and/or one IPv6); reached directly, **not** through the tunnel. |

### DNS

| Variable | Default | Description |
|---|---|---|
| `DNS` | server-pushed | Override the DNS servers (`;`-list, IPv4/IPv6 mixed); `127.0.0.1` uses a co-located resolver. |

### Reconnection and health — [details][wiki-reconnect]

| Variable | Default | Description |
|---|---|---|
| `RECONNECT_DELAY` | `5` | Base delay in seconds between reconnect attempts (exponential backoff, capped at 300 s). |
| `HEALTH_CHECK_ENABLED` | `false` | `true` = the Docker `HEALTHCHECK` probes the tunnel instead of always reporting healthy. |
| `CHECK_CONNECTION_URL` | `https://www.google.com` | Probe URL(s), `;`-separated, requested through the tunnel. |

### Diagnostics and miscellaneous — [details][wiki-diagnostics]

| Variable | Default | Description |
|---|---|---|
| `NETWORK_DIAGNOSTIC_ENABLED` | `false` | Dump addresses, routes and the nftables ruleset after firewall install and connect. |
| `TZ` | UTC | Container time zone (e.g. `Europe/Amsterdam`); affects log timestamps. |

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
  [Docker Compose Examples][wiki-compose].
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

<!-- Links: GitHub -->
[github-release]: https://img.shields.io/github/v/release/azinchen/openconnect-client?logo=github&logoColor=white
[github-releasedate]: https://img.shields.io/github/release-date/azinchen/openconnect-client?logo=github&logoColor=white
[github-releases]: https://github.com/azinchen/openconnect-client/releases
[github-build]: https://img.shields.io/github/actions/workflow/status/azinchen/openconnect-client/ci-build-deploy.yml?branch=main&label=build&logo=github&logoColor=white
[github-actions]: https://github.com/azinchen/openconnect-client/actions/workflows/ci-build-deploy.yml
[github-stars]: https://img.shields.io/github/stars/azinchen/openconnect-client?style=flat-square&logo=github&logoColor=white
[github-forks]: https://img.shields.io/github/forks/azinchen/openconnect-client?style=flat-square&logo=github&logoColor=white
[github-issues]: https://img.shields.io/github/issues/azinchen/openconnect-client?logo=github&logoColor=white
[github-issues-link]: https://github.com/azinchen/openconnect-client/issues
[github-lastcommit]: https://img.shields.io/github/last-commit/azinchen/openconnect-client?logo=github&logoColor=white
[github-link]: https://github.com/azinchen/openconnect-client

<!-- Links: Docker Hub -->
[dockerhub-pulls]: https://img.shields.io/docker/pulls/azinchen/openconnect-client?logo=docker&logoColor=white
[dockerhub-stars]: https://img.shields.io/docker/stars/azinchen/openconnect-client?logo=docker&logoColor=white
[dockerhub-size]: https://img.shields.io/docker/image-size/azinchen/openconnect-client/latest?logo=docker&logoColor=white
[dockerhub-link]: https://hub.docker.com/r/azinchen/openconnect-client
[multiarch-badge]: https://img.shields.io/badge/multi--arch-386%20%7C%20amd64%20%7C%20arm%2Fv6%20%7C%20arm%2Fv7%20%7C%20arm64%20%7C%20riscv64-blue?logo=docker&logoColor=white

<!-- Links: Wiki -->
[wiki-home]: https://github.com/azinchen/openconnect-client/wiki
[wiki-config]: https://github.com/azinchen/openconnect-client/wiki/Configuration-Reference
[wiki-url]: https://github.com/azinchen/openconnect-client/wiki/Connection-URL
[wiki-protocols]: https://github.com/azinchen/openconnect-client/wiki/Protocols
[wiki-auth]: https://github.com/azinchen/openconnect-client/wiki/Authentication
[wiki-ipv6]: https://github.com/azinchen/openconnect-client/wiki/IPv6-Configuration
[wiki-lan]: https://github.com/azinchen/openconnect-client/wiki/Local-Network-Access
[wiki-gateway]: https://github.com/azinchen/openconnect-client/wiki/Gateway-Mode
[wiki-gateway-dns]: https://github.com/azinchen/openconnect-client/wiki/Gateway-DNS
[wiki-ttl]: https://github.com/azinchen/openconnect-client/wiki/Gateway-Mode#ttl-normalization
[wiki-reconnect]: https://github.com/azinchen/openconnect-client/wiki/Automatic-Reconnection
[wiki-diagnostics]: https://github.com/azinchen/openconnect-client/wiki/Network-Diagnostics
[wiki-compose]: https://github.com/azinchen/openconnect-client/wiki/Docker-Compose-Examples
