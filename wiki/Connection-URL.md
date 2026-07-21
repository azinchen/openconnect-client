# Connection URL

A single `URL` variable carries host, port and the camouflage secret — matching `openconnect`'s own positional argument and ocserv's camouflage semantics 1:1.

## Grammar

```
URL=https://vpn.example.com                    # port 443, no camouflage
URL=https://vpn.example.com:8443/?mysecret     # custom port + camouflage secret
URL=vpn.example.com                            # bare host accepted, https:// implied
URL=https://192.0.2.10:8443                    # IPv4 literal
URL=https://[2001:db8::1]:8443                 # IPv6 literal (brackets required with a port)
URL=https://a.example.com;https://b.example.com:8443/?s2   # ordered failover list
```

Rules:

- Only `https` is accepted; any other scheme fails validation at startup.
- The port (default **443**) applies to both the TCP control channel and DTLS.
- Each entry in a `;`-separated list is a **complete URL** with its own port and secret.
- The query string is treated as opaque and passed to `openconnect` verbatim.

## Camouflage

When the server runs ocserv with camouflage enabled, the shared secret is simply the URL query string: `https://host/?mysecret`. A wrong or missing secret makes the server answer like an ordinary HTTPS site, so `openconnect` fails authentication — see [[Troubleshooting]].

**Redaction:** the query string is redacted (`?<redacted>`) in every log line this image produces, *including* `openconnect`'s own output, which is filtered through a literal-substring redactor. Note that like any environment variable the full `URL` remains visible in `docker inspect` — the same exposure a separate secret variable would have.

## Failover list

With multiple `;`-separated entries:

1. The client always starts with the first entry.
2. After **3 consecutive connection failures** on the current entry it advances to the next (wrapping around).
3. A successful connect resets the failure counter, so the current server stays active until it actually fails.

Failure counting, backoff timing and how this interacts with `openconnect`'s internal reconnect are described in [[Automatic Reconnection]].

## Name resolution and address family

The host part may be a DNS name, an IPv4 literal, or an IPv6 literal.

For DNS names, resolution happens **on every (re)connect** — never once-and-cached — and the resolved literal IP is what gets punched through the firewall and passed to `openconnect` via `--resolve` (the TLS handshake still uses the hostname for SNI and certificate validation). This closes the classic race where DNS re-resolution after firewall lockdown fails or returns an IP the firewall doesn't allow.

Entries in `/etc/hosts` (e.g. from `--add-host`) take precedence over DNS — useful for LAN setups without a resolver.

`CONNECT_FAMILY` selects the control-channel family:

| Value | Behavior |
|---|---|
| `auto` (default) | Resolve A + AAAA. Prefer IPv6 when eth0 has a global IPv6 route, otherwise IPv4; on repeated failures the client rotates through all resolved addresses of both families |
| `ipv4` | A records only |
| `ipv6` | AAAA records only |

All resolved addresses (both families) are added to the firewall's endpoint sets in one atomic update, so a mid-session family switch never races the kill switch.
