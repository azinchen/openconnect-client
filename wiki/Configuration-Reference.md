# Configuration Reference

All configuration is via environment variables. Boolean flags accept `true`/`1`; anything else is `false`. Invalid values fail fast: the container logs the offending variable and exits before the VPN client is allowed to start.

## Connection

| Variable | Default | Description |
|---|---|---|
| `URL` | — (required) | `https://host[:port][/][?camouflage_secret]`. Bare host accepted (`https://` implied), bracketed IPv6 literals accepted, `;`-separated list for ordered failover. Full grammar: [[Connection URL]] |
| `CONNECT_FAMILY` | `auto` | Control-channel address family. `auto` resolves A + AAAA and prefers IPv6 when eth0 has a global IPv6 route; `ipv4` / `ipv6` restrict resolution to one family |
| `PROTOCOL` | `anyconnect` | `anyconnect` \| `gp` \| `pulse` \| `fortinet` \| `nc` \| `array` — see [[Protocols]] |
| `DTLS` | `on` | `off` disables the UDP data channel (`--no-dtls`). DTLS uses the URL's port |
| `MTU` | auto | Override the tun MTU (otherwise the server-provided value, falling back to 1406) |
| `SPLIT_TUNNEL` | `false` | Honor server-pushed split routes instead of forcing full-tunnel |
| `OPENCONNECT_OPTS` | — | Extra raw `openconnect` arguments, appended verbatim — the escape hatch for niche flags |

## Authentication and trust

| Variable | Default | Description |
|---|---|---|
| `USER` / `PASS` | — | Password auth. The password is piped via `--passwd-on-stdin`, never on the command line |
| `PASS_FILE` | — | Read the password from a file (Docker secret at `/run/secrets/...`). First line wins; `PASS` takes precedence if both are set |
| `CERT_FILE` | — | Client certificate: a `.p12`/`.pfx` bundle, or a PEM certificate (with `KEY_FILE`) |
| `KEY_FILE` | — | PEM private key when `CERT_FILE` is a PEM certificate |
| `CERT_PASS` | — | Passphrase for the key/bundle (`--key-password`) |
| `CA_FILE` | — | CA certificate to trust (`--cafile`). Preferred for self-hosted servers |
| `SERVERCERT` | — | `pin-sha256:...` public-key pin (`--servercert`) — no CA file needed |
| `INSECURE` | `false` | Accept whatever certificate the server presents. Loudly logged; see [[Authentication]] for how it works and why it is unsafe |

At least one auth method is required: `USER` + `PASS`/`PASS_FILE`, and/or `CERT_FILE`. Both together match ocserv's `auth = certificate` + `enable-auth = plain`.

## IPv6

| Variable | Default | Description |
|---|---|---|
| `IPV6_MODE` | `auto` | Tunnel IPv6 data plane. `auto`: use the server-pushed IPv6 address if any, otherwise run IPv4-only with IPv6 egress still dropped (no leak). `require`: treat a v4-only tunnel as a connection failure and reconnect. `off`: never request IPv6 (`--disable-ipv6`) |

See [[IPv6 Configuration]] for the full picture, including what the server must provide.

## Local network access

| Variable | Default | Description |
|---|---|---|
| `NETWORK` | — | `;`-list of IPv4 LAN CIDRs that may reach the container via eth0. Adds return routes via the Docker gateway *and* firewall accepts, both directions |
| `NETWORK6` | — | Same for IPv6 CIDRs |

See [[Local Network Access]].

## Gateway mode

| Variable | Default | Description |
|---|---|---|
| `GATEWAY_MODE` | `false` | Act as a NAT gateway for other-netns containers and LAN hosts. Requires forwarding sysctls — the container verifies them and prints the exact `sysctls:` block if missing |
| `FORWARD_FROM` | eth0 subnets | `;`-list of IPv4 source CIDRs allowed to use the gateway |
| `FORWARD_FROM6` | eth0 subnets | Same for IPv6 |
| `GATEWAY_NAT6` | `true` | Masquerade IPv6 (NAT66). Set `false` when the server routes the client subnet |
| `GATEWAY_DNS` | `redirect` | Gateway-client DNS interception: `redirect` \| `local` \| `forward` \| `off` — see [[Gateway DNS]] |
| `GATEWAY_DNS_SERVER` | — | External resolver IP(s) for `GATEWAY_DNS=forward`; `;`-list of one IPv4 and/or one IPv6, reached directly over eth0 (not the tunnel) |

See [[Gateway Mode]].

## DNS

| Variable | Default | Description |
|---|---|---|
| `DNS` | server-pushed | Override the resolvers written to `/etc/resolv.conf` on connect. `;`-list, IPv4/IPv6 mixed. Set `127.0.0.1` to use a co-located resolver (e.g. AdGuard Home in `network_mode: service:vpn`) for this network namespace itself |

While the tunnel is **down**, the original (Docker-provided) `resolv.conf` is always restored so the server hostname can be resolved for the next connect.

## Supervision and health

| Variable | Default | Description |
|---|---|---|
| `RECONNECT_DELAY` | `5` | Base delay in seconds between reconnect attempts; doubles per consecutive failure, capped at 300 s |
| `HEALTH_CHECK_ENABLED` | `false` | Turn the built-in Docker HEALTHCHECK from a no-op into a real probe |
| `CHECK_CONNECTION_URL` | `https://www.google.com` | `;`-list of probe URLs, requested through the tunnel (`--interface tun0`) |
| `NETWORK_DIAGNOSTIC_ENABLED` | `false` | Dump addresses, routes and the full nftables ruleset after connect and firewall install |
| `TZ` | UTC | Container time zone (e.g. `Europe/Amsterdam`) — affects log timestamps |

See [[Automatic Reconnection]] and [[Network Diagnostics]].

## Volume

| Path | Purpose |
|---|---|
| `/openconnect-client` | Mount point for certificate material: `CA_FILE`, `CERT_FILE`, `KEY_FILE`. Mount read-only |

## Runtime state (informational)

`/run/openconnect-client/` holds the parsed URL list (mode 0600 — it contains the camouflage secret), the current failover index and failure counter, the connect state (`connected` with the tunnel addresses), and the backed-up original `resolv.conf`. It is tmpfs and rebuilt on every container start.
