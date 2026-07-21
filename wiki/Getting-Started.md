# Getting Started

## Requirements

| Requirement | Why |
|---|---|
| `--cap-add=NET_ADMIN` | configure the tun interface, routes and nftables |
| `--device /dev/net/tun` | create the tunnel device |
| `--sysctl net.ipv6.conf.all.disable_ipv6=0` | IPv6 support (optional; the image degrades to IPv4 without it) |
| a modern host kernel with nftables support | the kill switch is nftables-based |

[[Gateway Mode]] additionally needs the forwarding sysctls — see that page.

## Minimal docker run

```bash
docker run -d --name vpn \
  --cap-add=NET_ADMIN \
  --device /dev/net/tun \
  --sysctl net.ipv6.conf.all.disable_ipv6=0 \
  -e URL='https://vpn.example.com:8443/?mysecret' \
  -e USER=alex \
  -e PASS=secret \
  -e CA_FILE=/openconnect-client/ca.pem \
  -v ./config:/openconnect-client:ro \
  azinchen/openconnect-client:latest
```

- `URL` carries host, port and the ocserv camouflage secret in one value — see [[Connection URL]].
- `CA_FILE` points at the server's CA certificate mounted into `/openconnect-client` — see [[Authentication]] for the other trust options.

## Compose: route an app through the tunnel

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
      - "8080:80"            # the app's UI, published on the vpn service
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

Key points:

- The app publishes **its ports on the `vpn` service** (they share one network namespace) — see [[Shared Network Mode]].
- `NETWORK` lists the LAN subnets that may reach those published ports — see [[Local Network Access]].
- `PASS_FILE` + a compose secret keeps the password out of `docker inspect` output.

## Pairing with ocserv-server

This image is the first-class client for [ocserv-server](https://github.com/azinchen/ocserv-server). A typical pairing:

- server: `azinchen/ocserv-server` with camouflage enabled and a CA it issued;
- client: `URL=https://your-server/?<camouflage-secret>`, `CA_FILE` pointing at that CA, `USER`/`PASS` created with `ocpasswd` on the server.

For the server's IPv6 address pool (`IPV6_*` variables server-side) and the client's `IPV6_MODE`, see [[IPv6 Configuration]].

## Verify it works

```bash
# Watch the startup sequence
docker logs -f vpn

# Expect, in order:
#   [INIT-ENV]        Environment validated
#   [INIT-FIREWALL]   Kill switch installed
#   [SVC-OPENCONNECT] Resolved ... connecting via ...
#   [vpnc] connect    ip4=... ip6=... routes=full-tunnel
#   [SVC-OPENCONNECT] VPN connection established

# Confirm the egress IP is the VPN server's
docker exec vpn curl -s https://api.ipify.org

# Confirm nothing can bypass the tunnel
docker exec vpn curl --interface eth0 -s --max-time 3 https://1.1.1.1 ; echo $?
# -> non-zero exit: direct eth0 traffic is dropped by the kill switch
```

If the container exits immediately, a configuration value failed validation — the log names the exact variable. See [[Troubleshooting]].

## Next steps

- Enable the Docker health check: `HEALTH_CHECK_ENABLED=true` — see [[Automatic Reconnection]].
- Route a whole LAN: [[Gateway Mode]].
- Every variable in detail: [[Configuration Reference]].
