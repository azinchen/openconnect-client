# openconnect-client Wiki

**OpenConnect VPN client in a Docker container, with a dual-stack fail-closed kill switch.**

`openconnect-client` packages the [OpenConnect](https://www.infradead.org/openconnect/) client into a small Alpine-based container image that routes other containers' traffic — or a whole LAN — through an ocserv / Cisco AnyConnect-compatible VPN server. It is the companion client for [ocserv-server](https://github.com/azinchen/ocserv-server), and because it runs the plain `openconnect` binary it also connects to GlobalProtect, Pulse/Ivanti, Fortinet and other SSL-VPN servers.

---

## What you get

- **Shared-netns forwarding** — `network_mode: service:vpn` puts a container behind the tunnel ([[Shared Network Mode]])
- **Gateway mode** — NAT gateway for other containers and LAN hosts (macvlan / routed) ([[Gateway Mode]])
- **Daemon-free gateway DNS** — client DNS intercepted by nftables DNAT, no resolver process ([[Gateway DNS]])
- **Full dual-stack** — IPv4 and IPv6 for the connection, the tunnel and the firewall ([[IPv6 Configuration]])
- **Fail-closed kill switch** — one nftables table, up before openconnect starts, never removed ([[Security Model]])
- **Ordered failover** — `;`-separated server list in `URL`, next entry after repeated failures ([Connection URL](Connection-URL#failover-list))
- **Camouflage support** — ocserv camouflage secret in the URL, redacted from logs ([Connection URL](Connection-URL#camouflage))
- **Multi-protocol** — AnyConnect, GlobalProtect, Pulse, Fortinet, NC and Array via `PROTOCOL` ([[Protocols]])
- **Flexible auth** — password, secret file or client cert; trust by CA file or pin ([[Authentication]])
- **Supervised reconnect** — restarts with exponential backoff on top of openconnect's own ([[Automatic Reconnection]])
- **Opt-in health check** — Docker `HEALTHCHECK` probes real egress through the tunnel ([Automatic Reconnection](Automatic-Reconnection#health-check))
- **LAN access** — `NETWORK` / `NETWORK6` add return routes and firewall holes ([[Local Network Access]])
- **TTL normalization** — `TTL_SET` hides the hops behind the container from traceroutes ([Gateway Mode](Gateway-Mode#ttl-normalization))
- **Network diagnostics** — dump addresses, routes and the nftables ruleset ([[Network Diagnostics]])
- **Small multi-arch Alpine image** — 386, amd64, arm/v6, arm/v7, arm64, riscv64 ([[Building and CI]])

---

## Start here

| If you want to… | Go to |
|---|---|
| Get connected in 5 minutes | **[[Getting Started]]** |
| Copy a complete compose stack for either mode | **[[Docker Compose Examples]]** |
| Understand every env var | **[[Configuration Reference]]** |
| Learn the URL syntax, camouflage, failover | **[[Connection URL]]** |
| Set up passwords, certificates, server trust | **[[Authentication]]** |
| Route app containers through the tunnel | **[[Shared Network Mode]]** |
| Route a LAN or other-netns containers | **[[Gateway Mode]]** |
| Intercept gateway-client DNS / run AdGuard | **[[Gateway DNS]]** |
| Enable IPv6 end to end | **[[IPv6 Configuration]]** |
| Reach published ports from your LAN | **[[Local Network Access]]** |
| Understand the kill switch | **[[Security Model]]** |
| Tune reconnects and the health check | **[[Automatic Reconnection]]** |
| Use GlobalProtect / Pulse / Fortinet servers | **[[Protocols]]** |
| Debug a connection | **[[Network Diagnostics]]**, **[[Troubleshooting]]** |
| See how the image works inside | **[[Architecture and Internals]]** |
| Build it yourself / understand image tags | **[[Building and CI]]** |
| Quick answers | **[[FAQ]]** |

---

## At a glance

```bash
docker run -d --name vpn \
  --cap-add=NET_ADMIN \
  --device /dev/net/tun \
  --sysctl net.ipv6.conf.all.disable_ipv6=0 \
  -e URL='https://vpn.example.com:8443/?mysecret' \
  -e USER=alex \
  -e PASS=secret \
  -v ./config:/openconnect-client:ro \
  azinchen/openconnect-client:latest
```

Then route an app container through it:

```bash
docker run -d --network container:vpn my-app
```

Everything the app sends now goes through the tunnel — or nowhere. See **[[Getting Started]]**.

> **Project:** https://github.com/azinchen/openconnect-client
> **License:** MIT
