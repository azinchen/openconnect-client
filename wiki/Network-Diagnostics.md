# Network Diagnostics

## Built-in diagnostics

Set `NETWORK_DIAGNOSTIC_ENABLED=true` to get verbose dumps in the container log:

- after the firewall is installed: the full `inet vpn` ruleset;
- after every successful connect: all addresses, IPv4/IPv6 routes, and the ruleset again.

```bash
docker logs vpn | less
```

## Reading the startup log

A healthy start looks like this (interleaved s6 lines omitted):

```
[INIT-ENV]        openconnect-client starting
[INIT-ENV]        Server 1: https://vpn.example.com:8443/?<redacted> (host=vpn.example.com port=8443)
[INIT-ENV]        protocol=anyconnect auth=password trust=CA_FILE dtls=on ...
[INIT-SYSCTL]     IPv6 is available
[FIREWALL]        Bootstrap DNS resolvers allowed: 127.0.0.11
[FIREWALL]        Kill switch installed (table inet vpn, policy drop for IPv4 and IPv6)
[INIT-ROUTES]     Route initialization completed
[SVC-OPENCONNECT] Resolved vpn.example.com -> [203.0.113.5]; connecting via 203.0.113.5:8443
[FIREWALL]        Endpoint pinholes set: 203.0.113.5@8443
[vpnc] connect dev=tun0 mtu=1434 ip4=10.99.0.121 ip6=... routes=full-tunnel dns=8.8.8.8
[SVC-OPENCONNECT] VPN connection established (ip4=... ip6=...)
```

Every phase logs its outcome; the first line that deviates tells you which subsystem to look at.

## Manual toolbox

All of these run inside the container (`docker exec vpn ...`):

```bash
# Interfaces and addresses
ip addr show tun0
ip -s link show tun0            # byte counters - is traffic actually flowing?

# Routing (expect half-defaults via tun0)
ip route
ip -6 route

# The complete firewall state
nft list table inet vpn
nft list set inet vpn endpoint4
nft list set inet vpn lan4

# DNS as the namespace sees it
cat /etc/resolv.conf

# Egress checks
curl -s https://api.ipify.org                  # via tunnel (default routes)
curl -6 -s https://api64.ipify.org             # IPv6 via tunnel
curl --interface eth0 -s --max-time 3 https://1.1.1.1   # MUST fail (kill switch)

# Runtime state
cat /run/openconnect-client/connected          # ip4=... ip6=...
cat /run/openconnect-client/failures           # consecutive failure count
```

## Interpreting common patterns

| Observation | Meaning |
|---|---|
| `tun0` missing | Not connected — check the log for auth/TLS errors ([[Troubleshooting]]) |
| `tun0` up, no traffic counters moving | Routes or server-side NAT — verify half-defaults exist and the server masquerades your tunnel subnet |
| resolv.conf shows tunnel DNS while disconnected | Only transiently, during openconnect's internal reconnect window; a full service restart restores bootstrap DNS |
| `curl --interface eth0` succeeds | Kill switch not active — the container was started without `NET_ADMIN`, or the table was flushed manually |
| Big transfers stall, small requests fine | MTU — try `MTU=1300`, see [[Troubleshooting]] |
| Authenticates, then no data at all, dies on DPD timeout | Path MTU to the server below eth0's with PMTUD broken — try `MSS=1300`, see [[Troubleshooting]] |

## Capturing traffic

The image has no tcpdump (by design — small attack surface). Capture from the host against the container's veth, or run a throwaway sidecar in the same netns:

```bash
docker run --rm -it --network container:vpn nicolaka/netshoot tcpdump -i tun0 -n
```
