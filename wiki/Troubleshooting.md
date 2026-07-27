# Troubleshooting

Start with `docker logs vpn` — every subsystem logs its outcome, and validation errors name the exact variable. [[Network Diagnostics]] has the inspection toolbox.

## Container exits immediately

The init oneshots fail fast on purpose:

| Log line | Fix |
|---|---|
| `URL is required ...` / `Cannot parse URL entry` | Set `URL`; check the grammar in [[Connection URL]] (only `https`, brackets for IPv6 literals with ports) |
| `No authentication configured` | Set `USER` + `PASS`/`PASS_FILE`, and/or `CERT_FILE` |
| `PASS_FILE/CERT_FILE/... is not readable` | Fix the mount path/permissions of `/openconnect-client` |
| `GATEWAY_MODE=true needs net.ipv4.ip_forward=1 ...` | Add the printed `sysctls:` block — see [[Gateway Mode]] |
| `IPV6_MODE=require but the runtime has no usable IPv6` | Add `net.ipv6.conf.all.disable_ipv6=0`, enable IPv6 on the Docker network, or relax to `auto` |
| `nftables is not usable on this host kernel` | The host needs nf_tables support (any modern kernel); on old NAS/embedded hosts check for the `nf_tables` module |

## Authentication / TLS failures

| Symptom | Cause and fix |
|---|---|
| `Failed to complete authentication` right after connect, server responds like a web site (`405`, HTML) | **Wrong or missing camouflage secret** — it rides in the URL query string: `URL=https://host/?secret` |
| `Server certificate verify failed` | Trust not configured: mount and set `CA_FILE`, or use `SERVERCERT` pin — see [[Authentication]] |
| `Got HTTP response: ... 401` repeatedly | Bad credentials, or the server requires a client certificate too |
| `401 Cookie is not acceptable` after successful auth | Server-side session limit (`max-same-clients` in ocserv) — another session for this user is still open |
| Password prompt in the log / `--non-inter` failure | The server asks for a second auth factor the environment doesn't provide; check server config, or pass protocol-specific flags via `OPENCONNECT_OPTS` |

## Connected but no traffic

1. `docker exec vpn ip route` — expect `0.0.0.0/1` and `128.0.0.0/1` via `tun0`. Missing → check the log for `[vpnc]` errors.
2. `docker exec vpn curl -s https://api.ipify.org` — works? Then the tunnel is fine and the problem is app wiring ([[Shared Network Mode]] / [[Gateway Mode]]).
3. Works for small requests but big transfers stall → MTU. Try `MTU=1300`; gateway clients additionally rely on the built-in MSS clamp.
4. Authenticates fine but **nothing** flows at all — not even small requests — and the session dies on DPD timeout. First run `docker exec vpn ip route get <server-ip>`: if it answers `dev tun0`, the connection to the server was captured by its own tunnel routes — a bug in older images (the vpnc-script now pins the server route to the real uplink), upgrade. If it resolves via `eth0`, the path to the *server* has a smaller MTU than eth0 (VPS with a PMTUD black hole, PPPoE, tunnelled uplink) and the server's full-size TLS segments are dropped before they reach the container. Set `MSS=1300` to hard-cap the control connection's segment size (`MTU` won't help here — it only affects the tun interface, not the TCP session that carries it).
5. Tunnel works but a *forwarded* client doesn't → on the server side, the VPN subnet must be NATed/routed. For ocserv-server: its `VPN_SUBNET` must match the pool in `ocserv.conf`.

## DTLS

`DTLS handshake failed` with the session staying on TLS is non-fatal — the tunnel keeps running over TCP, just without the UDP fast path. The image builds openconnect with GnuTLS precisely so DTLS works against ocserv (`PSK-NEGOTIATE`); a healthy connect logs `Established DTLS connection ... (DTLS1.2)-(PSK)-...`. If the handshake fails persistently, UDP on the URL's port is blocked somewhere between client and server (NAT, firewall, provider) — fix the path, or set `DTLS=off` to silence the retries and accept TCP-only.

## DNS issues

| Symptom | Explanation |
|---|---|
| Can't resolve after a crash-restart of the tunnel | Should self-heal: the service restores the original resolv.conf before reconnecting. If you see it stuck, check for a `[FIREWALL] Bootstrap DNS` line |
| Gateway clients can't resolve | See [[Gateway DNS]] — and remember Docker's embedded DNS (`127.0.0.11`) bypasses interception; set an explicit `dns:` on the client |
| Want your own resolvers | `DNS=1.1.1.1;2606:4700:4700::1111` — they are used through the tunnel |

## Health check

`HEALTH_CHECK_ENABLED=true` and the container flaps unhealthy: the probe needs the probe URL reachable **through the tunnel** with `curl -4` (and `-6` under `IPV6_MODE=require`). Test manually:

```bash
docker exec vpn /usr/local/bin/healthcheck; echo $?
docker exec vpn curl -4 --interface tun0 -sI --max-time 5 https://www.google.com
```

## Reconnect loops

The log tells you which layer is failing — see [[Automatic Reconnection]]:

- `Could not resolve '<host>'` → bootstrap DNS / `CONNECT_FAMILY` mismatch;
- repeating auth errors → credentials/secret (reconnecting won't fix — the backoff caps at 5 min for a reason);
- `advancing to server N/M` cycling forever → all URLs in the list are down.

## Still stuck?

Enable `NETWORK_DIAGNOSTIC_ENABLED=true`, reproduce, and open an issue with the log (secrets are already redacted, but skim before posting): https://github.com/azinchen/openconnect-client/issues
