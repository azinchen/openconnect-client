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
-->

One or two sentences: what this release is about and why to upgrade.
Security updates lead with **Security update — upgrading is recommended.**

### 📥 Pull this release

```bash
docker pull azinchen/openconnect-client:X.YY-N
docker pull ghcr.io/azinchen/openconnect-client:X.YY-N
```

### ⬆️ Upgrade notes

<!-- Only when action is required or behavior changes: renamed/removed
variables, changed defaults. "No action required - ..." otherwise. -->

### ✨ Features

- ... (#PR)

### 🐛 Fixes

- ... (#PR)

### 📦 Package Updates

<!-- openconnect / Alpine / APK pin bumps, with CVE links for security
fixes, e.g.:
- Bump openconnect 9.21 → 9.22 ([upstream changelog](https://www.infradead.org/openconnect/changelog.html)) (#PR)
- Bump gnutls 3.8.13-r0 → 3.8.14-r0, fixing [CVE-XXXX-YYYY](https://avd.aquasec.com/nvd/cve-xxxx-yyyy) (#PR)
-->

### 📖 Documentation

- ... (#PR)

### 🔧 CI/CD Updates

- ... (#PR)

### 🧩 Component versions

| Component | Version |
|---|---|
| OpenConnect | X.YY (GnuTLS build) |
| Alpine Linux | A.B.C |
| s6-overlay | D.E.F.G |

### Contributors

@azinchen

**Full Changelog**: https://github.com/azinchen/openconnect-client/compare/PREV_TAG...X.YY-N
