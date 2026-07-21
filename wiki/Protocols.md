# Protocols

The image runs the stock `openconnect` client, so every protocol it supports is available via `PROTOCOL`:

| `PROTOCOL` | Server type |
|---|---|
| `anyconnect` (default) | ocserv, Cisco AnyConnect (SSL/DTLS) |
| `gp` | Palo Alto GlobalProtect |
| `pulse` | Pulse/Ivanti Connect Secure |
| `fortinet` | Fortinet FortiGate SSL-VPN |
| `nc` | Juniper Network Connect (older Junos) |
| `array` | Array Networks SSL-VPN |

The value is passed straight to `openconnect --protocol=...`.

## Notes per protocol

- **Camouflage** (the `?secret` query in the [[Connection URL]]) is an ocserv/AnyConnect-specific mechanism; other protocols ignore or reject a query string.
- **DTLS** (`DTLS=on`, the default) applies to the AnyConnect family; other protocols use their own transports (GlobalProtect uses ESP, controlled by openconnect itself). `DTLS=off` maps to `--no-dtls`.
- Protocol-specific flags (`--usergroup`, `--authgroup`, ESP options, …) can be passed through `OPENCONNECT_OPTS`:

```yaml
environment:
  - PROTOCOL=gp
  - OPENCONNECT_OPTS=--usergroup=portal:prelogin
```

`OPENCONNECT_OPTS` is appended verbatim to the command line — it is the escape hatch that keeps this image from growing one environment variable per openconnect flag.

## Build features

openconnect is built from source with GnuTLS and a trimmed feature set (rationale in [[Building and CI]]). Present: DTLS, ESP, PKCS#11, HOTP/TOTP software tokens. Absent: RSA SecurID soft-tokens (stoken), Yubikey OATH applet (PC/SC), Kerberos proxy auth (GSSAPI), and libproxy auto-discovery — explicit `--proxy`/`--proxy-auth` still work via `OPENCONNECT_OPTS`.

## MTU

`MTU` overrides the tun interface MTU. Without it, the server-provided value is used (falling back to 1406). Lower it if you see stalls on large transfers — see [[Troubleshooting]].

## Fixed behavior

A few openconnect flags are set by the image and not configurable, because the surrounding machinery depends on them:

- `--interface tun0` — the firewall and health check key on this name;
- `--script /usr/local/bin/vpnc-script` — the custom, container-aware script (see [[Architecture and Internals]]);
- `--non-inter` — no interactive prompts; auth must come from the environment;
- `--reconnect-timeout 60` — after 60 s of failed internal reconnects the process exits and supervision takes over (fresh auth, DNS re-resolution, URL failover — see [[Automatic Reconnection]]).
