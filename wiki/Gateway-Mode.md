# Gateway Mode

**Mode B** — `GATEWAY_MODE=true` turns the container into a NAT gateway for clients that keep their **own** network namespace: containers on the same Docker network, and LAN hosts that route through it (macvlan or a static route). Compose users routing app containers are usually better served by [[Shared Network Mode]]; reserve gateway mode for LAN/macvlan setups and for clients that need selective routing.

## Requirements

Forwarding sysctls must come from the runtime (`/proc/sys` is often read-only in-container). The container first tries to set them itself (covers `--privileged`), then verifies and exits with the exact block to add:

```yaml
sysctls:
  - net.ipv4.ip_forward=1
  - net.ipv6.conf.all.forwarding=1
  - net.ipv6.conf.all.disable_ipv6=0
```

## What gets set up

When enabled, the gateway machinery is added to the same fail-closed nftables table as the kill switch:

- **Forward chain** (policy drop): traffic from `@gw_clients4/6` may go `eth0 → tun0`; only established/related may return. With the tunnel down there is no `tun0`, so nothing can leak — same fail-closed property as the OUTPUT chain.
- **MSS clamp** for both families (`tcp option maxseg size set rt mtu`), so LAN clients don't stall on the tunnel MTU.
- **NAT**: IPv4 masquerade to the tunnel address. IPv6 is masqueraded too by default (**NAT66**), because ocserv assigns a single client address and won't route a delegated prefix; set `GATEWAY_NAT6=false` if your server does route the client subnet.
- **DNS interception** per `GATEWAY_DNS` — see [[Gateway DNS]].

`FORWARD_FROM`/`FORWARD_FROM6` define which **source** CIDRs may use the gateway. Unset, they default to the container's own eth0 subnets — sensible zero-config for "route my compose network".

## Client-side wiring

The gateway does not configure its clients; point them at it:

**Other containers (same Docker network):**

```bash
# inside the client container (requires NET_ADMIN)
ip route replace default via <vpn-container-ip>
```

or set the compose network's default gateway. If a container should send *all* its traffic through the VPN unconditionally, prefer [[Shared Network Mode]].

**LAN hosts** — two options:

1. **macvlan (recommended):** the container owns a real LAN IP; hosts (or your router's DHCP) use it as their default gateway. Full composition in [[Docker Compose Examples]].
2. **Routed:** keep the container on a bridge and add a static route on your router: `10.x.x.0/24 → docker-host`, plus the appropriate DNAT — workable, but macvlan is simpler.

## macvlan example (abridged)

```yaml
services:
  vpn:
    image: azinchen/openconnect-client:latest
    cap_add: [NET_ADMIN]
    devices: ["/dev/net/tun"]
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
      - FORWARD_FROM=192.168.1.0/24
      - FORWARD_FROM6=fd00:home::/64
      - NETWORK=192.168.1.0/24        # LAN may reach services in this netns
    networks:
      lan:
        ipv4_address: 192.168.1.2
        ipv6_address: fd00:home::2

networks:
  lan:
    driver: macvlan
    driver_opts:
      parent: eth0          # host NIC attached to the LAN
    enable_ipv6: true
    ipam:
      config:
        - subnet: 192.168.1.0/24
          gateway: 192.168.1.1
        - subnet: fd00:home::/64
```

LAN hosts then use `192.168.1.2` (and `fd00:home::2`) as their gateway — and as their DNS server if you enable interception ([[Gateway DNS]]).

The full example, including a co-located AdGuard Home, is in [[Docker Compose Examples]].

> **macvlan note:** the Docker host itself cannot reach a macvlan container over the parent interface — that's a macvlan property. Test from another LAN device.

## Verifying

```bash
# On a routed client: default route via the gateway, then
curl https://api.ipify.org        # -> the VPN egress IP

# On the gateway: watch the tunnel carry the forwarded traffic
docker exec vpn ip -s link show tun0
```
