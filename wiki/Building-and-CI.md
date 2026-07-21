# Building and CI

## Building locally

```bash
git clone https://github.com/azinchen/openconnect-client.git
cd openconnect-client
docker build -t openconnect-client:local .
```

The build needs network access (it downloads the openconnect source tarball, s6-overlay release tarballs and Alpine packages). Build arguments:

| ARG | Default | Purpose |
|---|---|---|
| `ALPINE_VERSION` | pinned in Dockerfile | Base image for every stage |
| `OPENCONNECT_VERSION` | pinned in Dockerfile | openconnect release built from source |
| `PACKAGEVERSION` | pinned in Dockerfile | s6-overlay release |
| `IMAGE_VERSION` / `BUILD_DATE` | `N/A` | Baked into OCI labels by CI |

Multi-arch:

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t openconnect-client:local .
```

## openconnect: built from source, with GnuTLS

The image does **not** use the Alpine `openconnect` package. It builds openconnect from the upstream source tarball, against **GnuTLS**, because:

- GnuTLS is openconnect's first-class crypto backend, and the only one that supports ocserv's modern `PSK-NEGOTIATE` DTLS — with the distro's OpenSSL build, DTLS against ocserv fails and the tunnel permanently falls back to TCP;
- the distro package lags upstream releases;
- the package hard-depends on a long tail (vpnc, full iproute2, stoken, libproxy, krb5, pcsc-lite, glib, …) that a container never uses — dropping it makes the image ~30 % smaller and shrinks the CVE surface.

Features are trimmed at configure time: no libproxy (automatic proxy *discovery* — explicit `--proxy`/`--proxy-auth` via `OPENCONNECT_OPTS` still work), no stoken (RSA SecurID soft-tokens; HOTP/TOTP remain built in), no PC/SC (Yubikey OATH applet — would need a pcscd daemon and USB passthrough anyway), no GSSAPI (Kerberos proxy auth). PKCS#11 support comes with GnuTLS.

## Version pinning

Every APK package in the Dockerfile is pinned to an exact version — builds are reproducible and upgrades are explicit, reviewable diffs. `scripts/update-apk-versions.sh` refreshes the pins from the Alpine package repositories:

```bash
./scripts/update-apk-versions.sh Dockerfile
```

The openconnect version is pinned via the `OPENCONNECT_VERSION` ARG and bumped by CI (below).

## CI workflows

| Workflow | Trigger | What it does |
|---|---|---|
| `ci-build-deploy` | every push / PR | Build and push. Branches: amd64 only → GHCR (branch-name tag). `main`: full platform matrix → GHCR `:dev`. Release tags: full matrix → Docker Hub + GHCR, `:<version>` and `:latest`, after verifying the tag matches the Dockerfile's `OPENCONNECT_VERSION`. Then runs the image security scan |
| `security-docker` | called by CI | Trivy scan of the built image, SARIF upload |
| `security-comprehensive` | schedule + `main` | Repo-wide security scanning |
| `maintenance-updates` | daily schedule | Bot PRs: APK pin refresh, **openconnect release bump** (from the upstream GitLab tags), s6-overlay bump, Alpine base bump |
| `maintenance-cleanup` | schedule | Prune stale GHCR/Docker Hub tags |
| `wiki-publish` | tag push / manual | Syncs the repository's `wiki/` folder to the GitHub wiki |

Platform matrix for releases: `linux/386, linux/amd64, linux/arm/v6, linux/arm/v7, linux/arm64, linux/riscv64`.

## Image tags

| Tag | Meaning |
|---|---|
| `latest` | Latest release (Docker Hub + GHCR) |
| `9.21-0` | A specific release: `<openconnect_version>-<n>` |
| `dev` | Current `main` branch (GHCR only) |
| `<branch>` | Development branch build, amd64 only (GHCR only) |

## Releases

### Version scheme

Releases are versioned **`<openconnect_version>-<n>`**, with no `v` prefix:

- `<openconnect_version>` is the `OPENCONNECT_VERSION` built into the image (CI refuses a release tag that doesn't match the Dockerfile);
- `<n>` is the image revision for that openconnect version — **starting at 0**, incremented with every release, and reset to 0 when openconnect is bumped.

Example sequence: `9.21-0`, `9.21-1`, `9.21-2`, then after the bot bumps openconnect to 9.22: `9.22-0`.

### Cutting a release

1. Make sure `main` is green and the bot PRs you want included are merged.
2. Tag: `git tag 9.21-1 && git push origin 9.21-1` — CI validates the tag against the Dockerfile, builds the full platform matrix, pushes `:9.21-1` and `:latest` to Docker Hub and GHCR, runs the security scan, and publishes the wiki.
3. Create the GitHub release for the tag using the release description format below.

### Release description format

The format lives at [`.github/RELEASE_TEMPLATE.md`](https://github.com/azinchen/openconnect-client/blob/main/.github/RELEASE_TEMPLATE.md). Structure (matching the ocserv-server releases):

- a one-or-two-sentence summary of why to upgrade — security updates lead with **"Security update — upgrading is recommended."**;
- **📥 Pull this release** — the two `docker pull` lines;
- **⬆️ Upgrade notes** — required actions or behavior changes, or "No action required";
- **✨ Features / 🐛 Fixes / 📦 Package Updates / 📖 Documentation / 🔧 CI/CD Updates** — hand-written, user-facing entries with PR references; package security bumps link their CVEs;
- **🧩 Component versions** — OpenConnect (GnuTLS build), Alpine Linux, s6-overlay;
- **Contributors** and the **Full Changelog** compare link.

**Generate release notes** ([`.github/release.yml`](https://github.com/azinchen/openconnect-client/blob/main/.github/release.yml) categorizes merged PRs by label) can seed the section contents — rewrite the entries in user-facing wording rather than shipping raw PR titles.
