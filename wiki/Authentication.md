# Authentication

The image mirrors ocserv's auth modes: password, certificate, or both simultaneously (ocserv `auth = certificate` + `enable-auth = plain`).

## Password

```yaml
environment:
  - USER=alex
  - PASS=secret            # or better:
  - PASS_FILE=/run/secrets/vpn_pass
secrets:
  - vpn_pass
```

- The password is piped to `openconnect --passwd-on-stdin` — it never appears on a command line.
- `PASS_FILE` reads the first line of the file; combine with Docker secrets to keep the password out of `docker inspect`.
- `PASS` takes precedence when both are set.

On the ocserv-server side, users are created with `ocpasswd`.

## Certificate

```yaml
environment:
  # Option A: PKCS#12 bundle
  - CERT_FILE=/openconnect-client/client.p12
  - CERT_PASS=bundlepass          # if the bundle is encrypted

  # Option B: PEM pair
  - CERT_FILE=/openconnect-client/client-cert.pem
  - KEY_FILE=/openconnect-client/client-key.pem
volumes:
  - ./config:/openconnect-client:ro
```

`.p12`/`.pfx` files are detected by extension and passed as a bundle; anything else is treated as PEM with an optional separate `KEY_FILE`. `CERT_PASS` maps to `--key-password`.

Certificate and password auth can be combined — set both groups of variables.

## Server trust

Pick exactly one strategy (checked in this order):

### 1. `CA_FILE` — your own CA (recommended for self-hosted)

```yaml
- CA_FILE=/openconnect-client/ca.pem
```

Mount the CA that signed the server certificate (for ocserv-server, the CA it was configured with). The TLS handshake validates both the chain and the hostname from the `URL`.

### 2. `SERVERCERT` — public-key pin

```yaml
- SERVERCERT=pin-sha256:0ELmVLNyxCAgFlBFsjGxOKmYcUWlnZzhV2gcqxEpRPo=
```

Pins the server's SPKI hash — convenient for a self-signed server certificate without shipping the CA. To obtain the pin, connect once with `openconnect` interactively (it prints the pin on mismatch), or:

```bash
openssl s_client -connect vpn.example.com:8443 -servername vpn.example.com 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary | base64
```

### 3. Neither — public CA

With no `CA_FILE`/`SERVERCERT`, the server must present a publicly valid certificate (e.g. Let's Encrypt on the server side).

### 4. `INSECURE=true` — escape hatch

`openconnect` has no blanket "skip verification" switch, so the image fetches the server's SPKI pin over an unverified TLS handshake at connect time and pins that for the session. This protects the session ciphertext but **not** against an active on-path attacker at connect time — anyone who can intercept the first handshake can impersonate the server. Every connect logs a loud warning. Use only for testing.
