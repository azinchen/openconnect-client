# Local Network Access

With the tunnel up, half-default routes send everything through `tun0` — including, without help, the *replies* to your LAN devices hitting a published port. `NETWORK`/`NETWORK6` fix that.

## What they do

```yaml
environment:
  - NETWORK=192.168.1.0/24;10.0.0.0/24
  - NETWORK6=fd00:home::/64
```

For each listed CIDR the image installs, at startup (before the VPN starts):

1. a **return route** via the Docker-assigned eth0 gateway, so replies to those subnets bypass the tunnel routes;
2. **firewall accepts** in both directions: inbound from the subnet on eth0 (reach published ports), outbound to the subnet on eth0 (reach LAN services).

Both live in named nftables sets (`@lan4`/`@lan6`), listed in [[Security Model]].

## When you need it

- **Published ports in [[Shared Network Mode]]**: your workstation on `192.168.1.0/24` opens `http://docker-host:8080` → the DNAT-ed request reaches the vpn netns, but the reply would head into the tunnel. `NETWORK=192.168.1.0/24` keeps that flow on eth0.
- **Reaching LAN services from the vpn netns** (a NAS, a printer): outbound eth0 traffic is dropped by the kill switch unless the destination subnet is whitelisted.
- **Gateway mode admin access**: LAN hosts reaching services running in the gateway's netns (e.g. the AdGuard admin UI in the [[Gateway DNS]] composition).

Traffic **from the same Docker bridge subnet** usually works without configuration — it is link-local to eth0 (covered by the kernel's connected route) and conntrack passes the established flow. `NETWORK` matters for subnets *behind* a router: your real LAN.

## Semantics and caveats

- Lists are `;` (or `,`) separated CIDRs.
- These subnets are **excluded from the VPN** by definition — traffic to them goes via eth0 in the clear. List only what needs direct reachability.
- `NETWORK6` entries are skipped (with a log line) when the runtime has no usable IPv6.
- If the Docker network has no default gateway for a family, the return route can't be installed — the log shows an error naming the subnets affected.
- Don't list `0.0.0.0/0` — you would whitelist the world and defeat the kill switch.

## Verifying

```bash
docker exec vpn ip route            # expect: 192.168.1.0/24 via 172.x.0.1 dev eth0
docker exec vpn nft list set inet vpn lan4
# From a LAN machine:
curl http://docker-host:8080/       # published port answers
```
