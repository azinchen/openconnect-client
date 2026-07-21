# Architecture and Internals

## Process model

The image is supervised by **s6-overlay**. Startup is a dependency graph, not a script — fail-closed ordering is enforced structurally:

```
init-env        (oneshot)  parse/validate env, parse URL list
init-sysctl     (oneshot)  IPv6 availability, forwarding sysctls      ← after init-env
init-firewall   (oneshot)  install nft table + sets, gateway rules    ← after init-sysctl
init-routes     (oneshot)  NETWORK/NETWORK6 return routes             ← after init-firewall
svc-openconnect (longrun)  resolve → update endpoint sets → connect   ← after init-routes
```

- A failed oneshot **aborts container start** (`S6_BEHAVIOUR_IF_STAGE2_FAILS=2`) — a config typo or an uninstallable firewall never yields a running-but-unprotected container.
- `svc-openconnect` is the **only long-running process**; the image is otherwise daemon-free (gateway DNS is pure nftables — see [[Gateway DNS]]).
- The service's `finish` script implements the exponential backoff (s6 restarts immediately by design, so the delay lives in the service) and never touches the firewall.

## Scripts

| Path | Role |
|---|---|
| `/usr/local/bin/backend-functions` | env parsing, URL grammar, logging, shared helpers — sourced by everything |
| `/usr/local/bin/firewall` | `install` / `bootstrap-dns` / `set-endpoints` / `post-connect` — all set changes are single-transaction (atomic) |
| `/usr/local/bin/gateway` | `setup` (forward/NAT/DNS-interception rules) and `dns-update` (re-point the redirect DNAT on reconnect) |
| `/usr/local/bin/vpnc-script` | custom, container-aware vpnc-script (below) |
| `/usr/local/bin/healthcheck` | Docker HEALTHCHECK probe — see [[Automatic Reconnection]] |

## The custom vpnc-script

The stock vpnc-script assumes resolvconf/systemd-ish hosts and misbehaves when Docker bind-mounts `/etc/resolv.conf` (the file can only be rewritten in place, never replaced). The custom script is ~100 lines of `ip`/`printf`, driven by the `reason` openconnect passes:

- **connect / reconnect**: bring up `tun0` with the assigned IPv4/IPv6 addresses and MTU (`MTU` env > server value > 1406); install `0.0.0.0/1`+`128.0.0.0/1` and `::/1`+`8000::/1` half-default routes (they beat the existing defaults without touching them — rollback is "interface disappears"), or the server's split routes when `SPLIT_TUNNEL=true`; rewrite `/etc/resolv.conf` in place with the pushed (or `DNS`-overridden) resolvers; close the bootstrap DNS hole; re-point gateway DNS interception; record connect state and reset the failure counter. One structured log line per phase: `[vpnc] connect dev=tun0 mtu=... ip4=... ip6=... routes=... dns=...`.
- **disconnect**: restore the original resolv.conf content, reopen the bootstrap DNS hole, drop the connect-state file. Routes and addresses vanish with the tun interface; the firewall is never touched.

There is no RA/SLAAC on the tun interface — all IPv6 config is static from the environment openconnect provides (`INTERNAL_IP6_ADDRESS`/`INTERNAL_IP6_NETMASK`).

## Runtime state

`/run/openconnect-client/` (tmpfs, rebuilt each start):

| File | Content |
|---|---|
| `urls` | parsed failover list, one `host port url` per line — mode 0600 (contains the camouflage secret) |
| `url-index` | index of the active URL entry |
| `failures` | consecutive-failure counter (drives backoff, candidate rotation, failover) |
| `connected` | `ip4=...` / `ip6=...` of the current session; existence = connected |
| `resolv.conf.orig` | pristine Docker resolv.conf, restored on disconnect |
| `has-ipv6` | IPv6 availability verdict from init-sysctl |

## Connection lifecycle (one attempt)

1. Restore bootstrap resolv.conf if the previous session died uncleanly.
2. Pick the active URL; advance after 3 consecutive failures.
3. Resolve (hosts-file first, then DNS) per `CONNECT_FAMILY`; abort attempt if nothing resolves.
4. Atomically swap **all** resolved `ip@port` pairs into the endpoint sets.
5. Build the openconnect command (protocol, trust, auth, DTLS, `--resolve host:ip` pinning); pipe the password via stdin; filter all output through the secret redactor.
6. Wait up to 60 s for the vpnc-script to signal connect; enforce `IPV6_MODE=require`; optionally dump diagnostics.
7. On exit: `finish` computes the backoff and s6 restarts the cycle.

## Image build

Multi-stage Dockerfile: an openconnect build stage (upstream source, **GnuTLS** backend, trimmed features — see [[Building and CI]] for the why), an s6-overlay fetch stage (arch-mapped release tarballs), a rootfs-assembly stage (permissions normalized once), and a minimal Alpine runtime with pinned APK packages (`gnutls`, `libxml2`, `lz4-libs`, `zlib`, `iproute2-minimal`, `nftables`, `curl`, `bind-tools`, `openssl`, `ca-certificates`, `tzdata`).
