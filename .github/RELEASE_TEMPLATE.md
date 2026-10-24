<!--
Release description format for openconnect-client.

Versioning: releases are tagged <openconnect_version>-<n> (no "v" prefix),
where <openconnect_version> is the OPENCONNECT_VERSION built into the image
and <n> is the image revision for that openconnect version - starting at 0
and incrementing with each release, resetting to 0 when openconnect is
bumped. Examples: 9.21-0, 9.21-1, then after an upstream bump 9.22-0.
The tag must match the Dockerfile's OPENCONNECT_VERSION - CI enforces this.

Usage: create the GitHub release for the tag, copy this template into the
description and fill it in. "Generate release notes" (.github/release.yml)
can be used to seed the categorized sections with the merged PR list -
rewrite the entries in user-facing wording, as in past releases. Delete any
section that has no content. The release process is documented in the wiki
(Building and CI page).

The release.yml categories use the same section titles as this template.
Two have no section of their own: "Security" items go under Package Updates
(or Fixes) and make the summary lead with the security sentence; "Breaking
changes" are described in Upgrade notes.
-->

One or two sentences: what this release is about and why to upgrade.
Security updates lead with **Security update — upgrading is recommended.**

### 📥 Pull this release

```bash
docker pull azinchen/openconnect-client:X.YY-N
docker pull ghcr.io/azinchen/openconnect-client:X.YY-N
```

Multi-arch: `386`, `amd64`, `arm/v6`, `arm/v7`, `arm64`, `riscv64`. `latest` follows this release.

### ⬆️ Upgrade notes

<!-- Only when action is required or behavior changes: renamed/removed
variables, changed defaults, new variables that are off unless set.
Otherwise: "No action required — no variables, defaults or behavior
changed." -->

### ✨ Features

<!-- One entry per feature, bold lead naming the feature and its variable,
then what it does and how it fails, ending with a wiki link, e.g.:
- **TTL / hop-limit normalization (`TTL_SET`).** What it does, defaults, failure
  behavior. See [Gateway Mode — TTL normalization](https://github.com/azinchen/openconnect-client/wiki/Gateway-Mode#ttl-normalization). (#PR)
-->

- ... (#PR)

### 🐛 Fixes

- ... (#PR)

### 📦 Package Updates

<!-- openconnect / Alpine / s6-overlay / APK pin bumps. Security bumps link
their CVEs or advisories and say what the package does in this image (and
whether it is build-stage only). Plain bumps are one line, e.g.:
- Bump openconnect 9.21 → 9.22 ([upstream changelog](https://www.infradead.org/openconnect/changelog.html)) (#PR)
- Bump Alpine Linux 3.24.2 → 3.24.3 — security release: fixes [CVE-XXXX-YYYY](https://avd.aquasec.com/nvd/cve-xxxx-yyyy) in musl ([announcement](https://alpinelinux.org/posts/...)) (#PR)
- Bump curl 8.21.0-r0 → 8.22.0-r0 — fixes [nine CVEs](https://curl.se/docs/vuln-8.21.0.html); curl runs the health-check probe (#PR)
- Bump s6-overlay 3.2.3.0 → 3.2.3.2 (#PR)
-->

### 📖 Documentation

- ... (#PR)

### 🔧 CI/CD Updates

<!-- GitHub Actions bumps, one line per action, collapsing the Dependabot
PRs for the same action into one entry, e.g.:
- Bump `github/codeql-action` from 4.38.2 to 4.39.0 (#PR, #PR)
-->

### 🧩 Component versions

| Component | Version |
|---|---|
| OpenConnect | X.YY (GnuTLS build) |
| Alpine Linux | A.B.C |
| s6-overlay | D.E.F.G |

### Contributors

<!-- Add @dependabot when the release includes its PRs. -->

@azinchen

**Full Changelog**: https://github.com/azinchen/openconnect-client/compare/PREV_TAG...X.YY-N
