ARG ALPINE_VERSION=3.24.1
ARG OPENCONNECT_VERSION=9.21

############################
# 1) Build openconnect
############################
FROM alpine:${ALPINE_VERSION} AS openconnect-build

ARG OPENCONNECT_VERSION

# Built from source with GnuTLS: openconnect's first-class backend and the
# only one that speaks ocserv's PSK-NEGOTIATE DTLS. Feature trim: no libproxy
# (explicit --proxy still works), no stoken (RSA SecurID), no PC/SC (Yubikey
# OATH applet), no GSSAPI (Kerberos proxy auth) - none usable in a container,
# and dropping them removes their whole dependency tail from the image.
RUN set -eux && \
    apk --no-cache --no-progress add \
        build-base=0.5-r4 \
        gnutls-dev=3.8.13-r0 \
        libxml2-dev=2.13.9-r2 \
        lz4-dev=1.10.0-r1 \
        zlib-dev=1.3.2-r0 \
        linux-headers=7.0.0-r1 \
        pkgconf=2.5.1-r0 \
        curl=8.21.0-r0 \
        && \
    curl -fsSL "https://www.infradead.org/openconnect/download/openconnect-${OPENCONNECT_VERSION}.tar.gz" -o /tmp/openconnect.tar.gz && \
    tar -C /tmp -xf /tmp/openconnect.tar.gz && \
    cd /tmp/openconnect-* && \
    ./configure \
        --prefix=/usr \
        --with-gnutls \
        --without-openssl \
        --without-libproxy \
        --without-stoken \
        --without-libpcsclite \
        --without-libpskc \
        --without-gssapi \
        --with-vpnc-script=/usr/local/bin/vpnc-script \
        --disable-nls \
        --disable-static && \
    make -j"$(nproc)" && \
    make DESTDIR=/pkg install && \
    strip /pkg/usr/sbin/openconnect /pkg/usr/lib/libopenconnect.so.*.* && \
    rm -rf /pkg/usr/share /pkg/usr/include /pkg/usr/lib/pkgconfig /pkg/usr/lib/*.la /pkg/usr/libexec

############################
# 2) Fetch s6-overlay (arch-aware)
############################
FROM alpine:${ALPINE_VERSION} AS s6-fetch

ARG TARGETARCH
ARG TARGETVARIANT

ARG PACKAGE="just-containers/s6-overlay"
ARG PACKAGEVERSION="3.2.3.0"

RUN echo "**** install security fix packages ****" && \
    echo "**** install mandatory packages ****" && \
    apk --no-cache --no-progress add \
        tar=1.35-r5 \
        xz=5.8.3-r0 \
        wget=1.25.0-r3 \
        && \
    echo "**** create folders ****" && \
    mkdir -p /s6root && \
    echo "**** download ${PACKAGE} ****" && \
    echo "Target arch: ${TARGETARCH}${TARGETVARIANT}" && \
    # Map Docker TARGETARCH to s6-overlay architecture names
    case "${TARGETARCH}${TARGETVARIANT}" in \
        amd64)      s6_arch="x86_64" ;; \
        arm64)      s6_arch="aarch64" ;; \
        armv7)      s6_arch="arm" ;; \
        armv6)      s6_arch="armhf" ;; \
        386)        s6_arch="i686" ;; \
        ppc64)      s6_arch="powerpc64" ;; \
        ppc64le)    s6_arch="powerpc64le" ;; \
        riscv64)    s6_arch="riscv64" ;; \
        s390x)      s6_arch="s390x" ;; \
        *)          s6_arch="x86_64" ;; \
    esac && \
    echo "Package ${PACKAGE} version ${PACKAGEVERSION}" && \
    s6_url_base="https://github.com/${PACKAGE}/releases/download/v${PACKAGEVERSION}" && \
    wget -q "${s6_url_base}/s6-overlay-noarch.tar.xz" -qO /tmp/s6-overlay-noarch.tar.xz && \
    wget -q "${s6_url_base}/s6-overlay-${s6_arch}.tar.xz" -qO /tmp/s6-overlay-binaries.tar.xz && \
    wget -q "${s6_url_base}/s6-overlay-symlinks-noarch.tar.xz" -qO /tmp/s6-overlay-symlinks-noarch.tar.xz && \
    wget -q "${s6_url_base}/s6-overlay-symlinks-arch.tar.xz" -qO /tmp/s6-overlay-symlinks-arch.tar.xz && \
    tar -C /s6root/ -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    tar -C /s6root/ -Jxpf /tmp/s6-overlay-binaries.tar.xz && \
    tar -C /s6root/ -Jxpf /tmp/s6-overlay-symlinks-noarch.tar.xz && \
    tar -C /s6root/ -Jxpf /tmp/s6-overlay-symlinks-arch.tar.xz

############################
# 3) Assemble rootfs (apply perms here)
############################
FROM alpine:${ALPINE_VERSION} AS rootfs

RUN mkdir -p /rootfs

ADD root/ /rootfs/

# Normalize permissions once (no chmods in final image)
RUN chmod +x /rootfs/usr/local/bin/* || true && \
    chmod +x /rootfs/etc/s6-overlay/s6-rc.d/*/run || true && \
    chmod +x /rootfs/etc/s6-overlay/s6-rc.d/*/finish || true

COPY --from=s6-fetch         /s6root/ /rootfs/
COPY --from=openconnect-build /pkg/   /rootfs/

############################
# 4) Final runtime (minimal layers)
############################
FROM alpine:${ALPINE_VERSION}

ARG IMAGE_VERSION=N/A \
    BUILD_DATE=N/A \
    OPENCONNECT_VERSION

LABEL org.opencontainers.image.title="OpenConnect VPN Client Docker container" \
      org.opencontainers.image.description="OpenConnect VPN client in a Docker container that routes other containers' traffic through an ocserv/AnyConnect-compatible server, with a dual-stack fail-closed kill switch" \
      org.opencontainers.image.authors="Alexander Zinchenko <alexander@zinchenko.com>" \
      org.opencontainers.image.url="https://github.com/azinchen/openconnect-client" \
      org.opencontainers.image.source="https://github.com/azinchen/openconnect-client" \
      org.opencontainers.image.vendor="Alexander Zinchenko <alexander@zinchenko.com>" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      com.openconnect.version="${OPENCONNECT_VERSION}" \
      com.openconnect.url="https://www.infradead.org/openconnect/" \
      com.openconnect.documentation="https://www.infradead.org/openconnect/manual.html"

RUN apk --no-cache --no-progress add \
    gnutls=3.8.13-r0 \
    libxml2=2.13.9-r2 \
    lz4-libs=1.10.0-r1 \
    zlib=1.3.2-r0 \
    iproute2-minimal=7.0.0-r0 \
    nftables=1.1.6-r1 \
    curl=8.21.0-r0 \
    bind-tools=9.20.24-r0 \
    openssl=3.5.7-r0 \
    ca-certificates=20260611-r0 \
    tzdata=2026c-r0

# One COPY to bring everything in
COPY --from=rootfs /rootfs/ /

# Runtime knobs: never wait on longruns at boot; abort container start if an
# init oneshot (env validation, firewall install) fails -> fail-closed
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2

VOLUME ["/openconnect-client"]

# Report container health from the VPN tunnel state. start-period covers
# initial tunnel bring-up; retries absorb transient blips and reconnects.
# Opt-in: the probe reports healthy unless HEALTH_CHECK_ENABLED=true is set.
HEALTHCHECK --interval=60s --timeout=15s --start-period=60s --retries=3 \
    CMD ["/usr/local/bin/healthcheck"]

ENTRYPOINT ["/init"]
