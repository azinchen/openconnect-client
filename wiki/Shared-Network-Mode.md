# Shared Network Mode

**Mode A** — the recommended way to route application containers through the VPN. Co-located containers join the VPN container's network namespace, so the tunnel routes and the kill switch protect them with zero per-app configuration.

## How it works

A container started with `network_mode: service:vpn` (compose) or `--network container:vpn` (docker run) shares the VPN container's network stack: same interfaces, same routes, same firewall. The half-default routes via `tun0` capture all its traffic, and the fail-closed OUTPUT policy guarantees that when the tunnel is down, nothing leaves.

There is no NAT and no forwarding involved — it is all one network namespace.

## Compose example

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
      - PASS_FILE=/run/secrets/vpn_pass
      - CA_FILE=/openconnect-client/ca.pem
      - NETWORK=192.168.1.0/24
    volumes:
      - ./config:/openconnect-client:ro
    secrets:
      - vpn_pass
    ports:
      - "8080:80"          # app UI published on the vpn service
    restart: unless-stopped

  app:
    image: nginx:alpine
    network_mode: "service:vpn"
    depends_on:
      - vpn

secrets:
  vpn_pass:
    file: ./vpn_pass.txt
```

## The two rules to remember

1. **Publish the app's ports on the `vpn` service.** The app has no network of its own, so `ports:` on the app service would be ignored — they belong on `vpn`.
2. **List your LAN in `NETWORK`/`NETWORK6`.** Published ports are reachable through eth0 only from subnets the kill switch allows and that have a return route — see [[Local Network Access]].

## Caveats

- **Recreating the vpn container breaks the app's namespace reference.** If you `docker compose up -d --force-recreate vpn` (or the image updates), restart the app containers too so they re-join the new namespace. `restart: unless-stopped` on both plus `depends_on` handles the common cases.
- **DNS**: the app resolves through the namespace's `/etc/resolv.conf`… which is the VPN container's. While connected that means the tunnel's resolvers (or your `DNS` override); while disconnected, the original Docker-provided resolver is restored, but actual lookups will fail-closed because nothing may leave eth0 except the whitelisted destinations. That is by design.
- **Multiple apps** can share one vpn service; they also share `localhost` with each other (and with a co-located resolver, if you run one — see [[Gateway DNS]]).
- A container in someone else's netns cannot be attached to other networks at the same time; if the app needs to talk to non-tunneled services, use [[Gateway Mode]] instead and route selectively.
