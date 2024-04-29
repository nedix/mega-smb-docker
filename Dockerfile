ARG ALPINE_VERSION=3.19
ARG CRYPTOPP_VERSION=8_9_0
ARG FUSEDAV_VERSION=3.0.0
ARG GO_VERSION=1.22.2
ARG MEGA_CMD_VERSION=1.6.3
ARG MEGA_SDK_VERSION=4.17.1d
ARG RCLONE_VERSION=1.66.0

FROM alpine:${ALPINE_VERSION} as mega

ARG CRYPTOPP_VERSION
ARG MEGA_CMD_VERSION
ARG MEGA_SDK_VERSION

RUN apk add \
        autoconf \
        automake \
        c-ares-dev \
        c-ares-static \
        crypto++-dev \
        curl \
        curl-dev \
        curl-static \
        freeimage-dev \
        g++ \
        icu-dev \
        icu-static \
        libsodium-dev \
        libsodium-static \
        libtool \
        libuv-dev \
        libuv-static \
        linux-headers \
        make \
        openssl-dev \
        openssl-libs-static \
        readline-dev \
        readline-static \
        sqlite-dev \
        sqlite-static \
        zlib-dev \
        zlib-static

WORKDIR /build/cryptopp

RUN curl -fsSL "https://github.com/weidai11/cryptopp/archive/refs/tags/CRYPTOPP_${CRYPTOPP_VERSION}/cryptopp${CRYPTOPP_VERSION//_/}.tar.gz" \
    | tar -xz --strip-components=1 \
    && g++ -DNDEBUG -g3 -O2 -march=native -pipe -c cryptlib.cpp \
    ; ar rcs libcryptopp.a *.o \
    && mv libcryptopp.a /usr/local/lib/

WORKDIR /build/mega

RUN curl -fsSL "https://github.com/meganz/MEGAcmd/archive/refs/tags/${MEGA_CMD_VERSION}_Linux/MEGAcmd-${MEGA_CMD_VERSION}.tar.gz" \
    | tar -xz --strip-components=1 \
    && curl -fsSL "https://github.com/meganz/sdk/archive/refs/tags/v${MEGA_SDK_VERSION}/sdk-v${MEGA_SDK_VERSION}.tar.gz" \
    | tar -xzC ./sdk --strip-components=1 \
    && sed -i 's|/bin/bash|/bin/sh|' ./src/client/mega-* \
    && ./autogen.sh \
    && ./configure \
        CXXFLAGS="-flto=auto -fpermissive -static-libgcc -static-libstdc++" \
        --build=$CBUILD \
        --host=$CHOST \
        --localstatedir=/var \
        --mandir=/usr/share/man \
        --prefix=/usr \
        --sysconfdir=/etc \
        --disable-examples \
        --disable-shared \
    && make -j $(nproc) \
    && make install

FROM alpine:${ALPINE_VERSION} as fusedav

ARG FUSEDAV_VERSION

WORKDIR /build/fusedav

RUN apk add \
        attr-dev \
        autoconf \
        automake \
        build-base \
        curl \
        curl-dev \
        dbus-dev \
        elogind-dev \
        fuse-dev \
        glib-dev \
        jemalloc-dev \
        leveldb-dev \
        neon-dev \
        uriparser-dev \
        yaml-dev \
    && curl -fsSL "https://github.com/pantheon-systems/fusedav/archive/refs/tags/v${FUSEDAV_VERSION}/v${FUSEDAV_VERSION}.tar.gz" \
    | tar -xz --strip-components=1 \
    && autoupdate \
    && automake --add-missing || true \
    && autoconf || true \
    && ./autogen.sh \
    && echo "#define PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP {{PTHREAD_MUTEX_RECURSIVE}}" > musl.h \
    && export CFLAGS="-g -O0 -include musl.h" \
    && export LEVELDB_CFLAGS="-I/usr/include" \
    && export LEVELDB_LIBS="-L/usr/lib -lleveldb" \
    && ./configure --prefix=/usr \
    && make -j $(nproc) \
    && mv ./src/fusedav /usr/bin/fusedav

FROM rclone/rclone:${RCLONE_VERSION} as rclone

FROM alpine:${ALPINE_VERSION}

RUN echo https://dl-cdn.alpinelinux.org/alpine/edge/community >> /etc/apk/repositories \
    && echo https://dl-cdn.alpinelinux.org/alpine/edge/testing >> /etc/apk/repositories \
    && apk add \
        c-ares \
        conntrack-tools \
        crypto++ \
        dbus-x11 \
        freeimage \
        fuse \
        fuse3 \
        iproute2 \
        iptables \
        jemalloc \
        leveldb \
        libcurl \
        libelogind \
        libgcc \
        libsodium \
        libstdc++ \
        libuv \
        nftables \
        nftables-openrc \
        openrc \
        samba \
        sqlite-libs \
        tracker \
        uriparser

COPY --from=mega /usr/bin/mega-cmd-server /usr/bin/
COPY --from=mega /usr/bin/mega-exec /usr/bin/
COPY --from=mega /usr/bin/mega-login /usr/bin/
COPY --from=mega /usr/bin/mega-webdav /usr/bin/
COPY --from=fusedav /usr/bin/fusedav /usr/bin/
COPY --from=rclone /usr/local/bin/rclone /usr/bin/

ADD rootfs /

ENTRYPOINT ["/entrypoint.sh"]

EXPOSE 445/tcp

HEALTHCHECK CMD rc-status -C sysinit | awk 'NR>1 && !(/started/) {exit 1}'
