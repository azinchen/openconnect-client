# Docker Compose Examples

Two complete, working compositions — one per traffic mode. Copy, adjust the environment, and `docker compose up -d`.

## Mode A — shared network namespace

Containers started with `network_mode: service:vpn` send **all** their traffic through the tunnel and are protected by the same fail-closed kill switch. Publish the app's ports on the vpn service and list the LAN subnets that need to reach them in `NETWORK`/`NETWORK6`. Background: [[Shared Network Mode]].

```yaml
services:
  vpn:
    image: azinchen/openconnect-client:latest
    container_name: vpn
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
      - NETWORK6=fd00:home::/64
    volumes:
      - ./config:/openconnect-client:ro
    secrets:
      - vpn_pass
    ports:
      - "8080:80"            # app UI published on the vpn service
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

> For IPv6 connectivity **to** the server the compose network itself needs `enable_ipv6: true` (or daemon `ipv6` + `ip6tables`); the tunnel's IPv6 data plane works regardless once the session is up over IPv4 — see [[IPv6 Configuration]].

## Mode B — NAT gateway on macvlan, with AdGuard Home

The container owns a LAN IP; LAN hosts point their default route (and DNS) at it. This example runs AdGuard Home co-located in the VPN namespace: `GATEWAY_DNS=local` intercepts **all** client port-53 traffic and hands it to AdGuard, whose upstream queries follow the tunnel automatically. Background: [[Gateway Mode]] and [[Gateway DNS]].

For a daemon-free setup instead, drop the `adguard` service and use `GATEWAY_DNS=redirect` (the default): client DNS is then DNAT-ed straight to the tunnel-pushed resolvers.

```yaml
services:
  vpn:
    image: azinchen/openconnect-client:latest
    container_name: vpn-gateway
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv6.conf.all.forwarding=1
      - net.ipv6.conf.all.disable_ipv6=0
    environment:
      - URL=https://vpn.example.com:8443/?mysecret
      - USER=alex
      - PASS_FILE=/run/secrets/vpn_pass
      - CA_FILE=/openconnect-client/ca.pem
      - GATEWAY_MODE=true
      # LAN sources allowed to route through the tunnel
      - GATEWAY_NETWORK=192.168.1.0/24
      - GATEWAY_NETWORK6=fd00:home::/64
      # Hand intercepted client DNS to the co-located AdGuard below
      - GATEWAY_DNS=local
      # The netns itself (and Mode-A style co-located containers) also
      # resolves via AdGuard once the tunnel is up
      - DNS=127.0.0.1
      # LAN may reach services in this netns (e.g. the AdGuard admin UI)
      - NETWORK=192.168.1.0/24
      - NETWORK6=fd00:home::/64
    volumes:
      - ./config:/openconnect-client:ro
    secrets:
      - vpn_pass
    networks:
      lan:
        ipv4_address: 192.168.1.2
        ipv6_address: fd00:home::2
    restart: unless-stopped

  # Shares the VPN netns: listens on the gateway's LAN address, upstream
  # queries ride the tunnel. Configure AdGuard's upstreams as plain IPs (or
  # set its bootstrap DNS to IPs): it starts behind the fail-closed firewall
  # before the tunnel is up, so it cannot resolve upstream hostnames itself.
  adguard:
    image: adguard/adguardhome:latest
    network_mode: "service:vpn"
    depends_on:
      - vpn
    volumes:
      - ./adguard/work:/opt/adguardhome/work
      - ./adguard/conf:/opt/adguardhome/conf
    restart: unless-stopped

networks:
  lan:
    driver: macvlan
    driver_opts:
      parent: eth0             # host interface attached to the LAN
    enable_ipv6: true
    ipam:
      config:
        - subnet: 192.168.1.0/24
          gateway: 192.168.1.1
        - subnet: fd00:home::/64

secrets:
  vpn_pass:
    file: ./vpn_pass.txt
```

LAN hosts then use `192.168.1.2` / `fd00:home::2` as their default gateway and DNS server (via your router's DHCP options, or per host).

> **macvlan note:** the Docker host itself cannot reach a macvlan container over the parent interface — that's a macvlan property. Test from another LAN device.

## Useful additions

Health check + automatic restart of an unhealthy vpn container ([[Automatic Reconnection]]):

```yaml
  vpn:
    environment:
      - HEALTH_CHECK_ENABLED=true
    labels:
      - autoheal=true

  autoheal:
    image: willfarrell/autoheal
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped
```
