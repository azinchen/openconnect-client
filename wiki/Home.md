# openconnect-client Wiki

**OpenConnect VPN client in a Docker container, with a dual-stack fail-closed kill switch.**

`openconnect-client` packages the [OpenConnect](https://www.infradead.org/openconnect/) client into a small Alpine-based container image that routes other containers' traffic — or a whole LAN — through an ocserv / Cisco AnyConnect-compatible VPN server. It is the companion client for [ocserv-server](https://github.com/azinchen/ocserv-server), and because it runs the plain `openconnect` binary it also connects to GlobalProtect, Pulse/Ivanti, Fortinet and other SSL-VPN servers.

---

## What you get

- **Fail-closed kill switch** — a single dual-family **nftables** table drops everything by default; the firewall is installed *before* the VPN client may start and is never removed on disconnect
- **Shared-netns forwarding** — containers started with `network_mode: service:vpn` transparently send all traffic through the tunnel
- **Gateway mode** — NAT gateway for containers with their own network namespace and for LAN hosts (macvlan/routed setups), with daemon-free DNS interception
- **Full dual-stack IPv4 + IPv6** — connect over either family, tunnel both, firewall both
- **Ordered failover** — a `;`-separated server list with automatic advance after repeated failures
- **Camouflage support** — the ocserv camouflage secret rides in the URL and is redacted in all log output
- **Supervised reconnect** — exponential backoff, DNS re-resolution and atomic firewall updates on every reconnect
- **Multi-arch images** published to GHCR (and Docker Hub for releases)

---

## Start here

| If you want to… | Go to |
|---|---|
| Get connected in 5 minutes | **[[Getting Started]]** |
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
