# FAQ

### Which servers can I connect to?

Any server `openconnect` speaks to: ocserv / Cisco AnyConnect (default), and via `PROTOCOL` also GlobalProtect, Pulse/Ivanti, Fortinet, Juniper NC and Array — see [[Protocols]]. The first-class documented pairing is [ocserv-server](https://github.com/azinchen/ocserv-server).

### Is traffic really blocked when the VPN is down?

Yes — that is the core design. The firewall is installed before the VPN client is allowed to start, drops both IPv4 and IPv6 by default, and is never removed on disconnect. Only the VPN endpoint itself, bootstrap DNS (pre-connect), and subnets you whitelist can ever use eth0. See [[Security Model]] — including commands to verify it yourself.

### How do I route another container through the VPN?

`network_mode: "service:vpn"` — see [[Shared Network Mode]]. For containers that must keep their own network (or for LAN devices), use [[Gateway Mode]].

### Where do the app's `ports:` go?

On the **vpn** service. Containers in shared-netns mode have no network of their own. And list your LAN in `NETWORK` so replies don't get pulled into the tunnel — [[Local Network Access]].

### How do I use the ocserv camouflage secret?

Append it to the URL: `URL=https://vpn.example.com:8443/?mysecret`. It is redacted in all logs. See [[Connection URL]].

### Can I connect over IPv6? Get IPv6 inside the tunnel?

Both, independently: `CONNECT_FAMILY` for the control channel, `IPV6_MODE` + a server-side IPv6 pool for the data plane. See [[IPv6 Configuration]].

### Does the container auto-reconnect?

Yes, forever, with exponential backoff and optional multi-URL failover — the container itself never exits on connection failure. See [[Automatic Reconnection]].

### Why is there no DNS server in the image?

Deliberate: forwarding is done by the kernel (nftables DNAT), and full-featured DNS (filtering, caching, UI) belongs in a purpose-built container like AdGuard Home co-located in the VPN namespace. Best of both, nothing extra to patch. See [[Gateway DNS]].

### Why does the container run as root / need NET_ADMIN?

It configures tun interfaces, routes and nftables — that is what `NET_ADMIN` grants. Every process in the image needs those privileges; there is no meaningful unprivileged user to drop to.

### `docker inspect` shows my URL secret. Is that a leak?

It shows environment variables, like for any container — the same exposure a dedicated secret variable would have. Use `PASS_FILE` for the password; treat host access as root-equivalent anyway. See [[Security Model]].

### DTLS says "handshake failed" but everything works?

The tunnel is running over TCP/TLS; DTLS is the UDP fast path (and it normally *does* establish against ocserv — the image builds openconnect with GnuTLS for exactly that). Persistent failures mean UDP is blocked on the path; set `DTLS=off` if you can't unblock it and the retries bother you. See [[Troubleshooting]].

### Which architectures are published?

`386, amd64, arm/v6, arm/v7, arm64, riscv64` — see [[Building and CI]] for tags and registries.

### How is this different from a generic "VPN client + iptables script" container?

Structurally fail-closed (the firewall is a hard dependency of the VPN service, not a step in a script), dual-family in one table, atomic firewall updates on reconnect, endpoint pinning against DNS races, and no daemons beyond openconnect itself. The details: [[Architecture and Internals]] and [[Security Model]].
