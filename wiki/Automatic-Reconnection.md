# Automatic Reconnection

Reconnection has three layers, from fastest to most drastic. The firewall stays fail-closed through all of them.

## Layer 1 — openconnect's internal reconnect

Short blips (a dropped TCP session, a roamed network) are handled inside `openconnect` itself: it reconnects with its session cookie, and the tun interface stays up. The image caps this at **60 seconds** (`--reconnect-timeout 60`): past that, a full restart with fresh authentication, DNS re-resolution and URL failover is the better recovery — notably, a restarted camouflaged server rejects cookie-only reconnects anyway.

## Layer 2 — supervised restart with backoff

If the process exits, s6 restarts the service. Each restart:

1. restores the original `resolv.conf` if the previous session died uncleanly (so the server hostname is resolvable again — the bootstrap DNS hole is reopened to exactly those resolvers);
2. re-resolves the server and atomically swaps the firewall endpoint sets;
3. rotates through the resolved addresses (both families in `CONNECT_FAMILY=auto`) across consecutive attempts;
4. reconnects with full authentication.

The delay between attempts is exponential: `RECONNECT_DELAY × 2^(failures−1)`, capped at 300 s. With the default `RECONNECT_DELAY=5`: 5, 10, 20, 40, … 300 s. A successful connect resets the counter. The container itself stays up — no restart storms, no `docker restart` loops.

## Layer 3 — URL failover

With a `;`-separated `URL` list, **3 consecutive failures** on the current entry advance to the next (wrapping around). Each entry keeps its own port and camouflage secret, and the endpoint pinholes follow the switch atomically. See [[Connection URL]].

## Health check

The image bakes in a Docker HEALTHCHECK (60 s interval, 15 s timeout, 3 retries, 60 s start period) that is **neutral by default** — it reports healthy until you opt in:

```yaml
environment:
  - HEALTH_CHECK_ENABLED=true
  - CHECK_CONNECTION_URL=https://www.google.com   # default; ;-list allowed
```

When enabled, the probe (side-effect-free, no retries of its own):

1. verifies `tun0` exists and has its IPv4 address (and a global IPv6 address when `IPV6_MODE=require`);
2. issues one short HTTP request per configured URL **forced through the tunnel** (`curl --interface tun0`), IPv4 first; with `IPV6_MODE=require` an IPv6 probe must also succeed.

Docker's own interval/retries absorb transient blips — by the time the container is marked unhealthy, layers 1–3 have been failing for several minutes.

### Acting on unhealthy

Docker does not restart unhealthy containers by itself. Combine with an autoheal-style supervisor:

```yaml
  vpn:
    labels:
      - autoheal=true
  autoheal:
    image: willfarrell/autoheal
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped
```

Since the supervised reconnect (layer 2) already retries forever, an unhealthy state usually means something reconnecting can't fix (revoked credentials, changed server certificate) — check `docker logs vpn` before assuming a restart will help.

## Observing reconnection

```bash
docker logs -f vpn
# [SVC-OPENCONNECT] openconnect exited (code 1, failure 2); reconnecting in 10s
# [SVC-OPENCONNECT] 3 consecutive failures; advancing to server 2/2
# [SVC-OPENCONNECT] Resolved vpn2.example.com -> [...]; connecting via ...
```

The failure counter and the active URL index live in `/run/openconnect-client/` if you need them programmatically.
