ARG ALPINE_VERSION=3.20
ARG CRYPTOPP_VERSION=8_9_0
ARG MEGA_CMD_VERSION=1.6.3
ARG MEGA_ECAP_ADAPTER_VERSION=development
ARG MEGA_SDK_VERSION=4.17.1d
ARG RCLONE_VERSION=1.67.0

FROM alpine:${ALPINE_VERSION} AS mega

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

FROM alpine:${ALPINE_VERSION} AS mega-ecap-adapter

ARG MEGA_ECAP_ADAPTER_VERSION

WORKDIR /build/mega-ecap-adapter

RUN apk add \
        autoconf \
        automake \
        g++ \
        git \
        libtool \
        make \
    && echo "http://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories \
    && echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories \
    && echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories \
    && apk add \
        libecap \
    && git init . \
    && git remote add -t \* -f origin https://github.com/nedix/mega-ecap-adapter.git \
    && git checkout "$MEGA_ECAP_ADAPTER_VERSION" \
    && ./bootstrap.sh \
    && ./configure \
    && make -j $(nproc) \
    && make install

FROM rclone/rclone:${RCLONE_VERSION} AS rclone

FROM alpine:${ALPINE_VERSION}

RUN apk add \
        c-ares \
        conntrack-tools \
        crypto++ \
        freeimage \
        fuse3 \
        iproute2 \
        iptables \
        libcurl \
        libgcc \
        libsodium \
        libstdc++ \
        libuv \
        nftables \
        nftables-openrc \
        openrc \
        samba \
        sqlite-libs \
        squid \
        tracker

COPY --from=mega /usr/bin/mega-cmd-server /usr/bin/
COPY --from=mega /usr/bin/mega-exec /usr/bin/
COPY --from=mega /usr/bin/mega-login /usr/bin/
COPY --from=mega /usr/bin/mega-webdav /usr/bin/
COPY --from=mega-ecap-adapter /usr/local/lib/mega_ecap_adapter.so /usr/local/lib/
COPY --from=rclone /usr/local/bin/rclone /usr/bin/

ADD rootfs /

ENTRYPOINT ["/entrypoint.sh"]

EXPOSE 445/tcp

VOLUME /var/rclone

HEALTHCHECK CMD rc-status -C sysinit | awk 'NR>1 && !(/started/) {exit 1}'
