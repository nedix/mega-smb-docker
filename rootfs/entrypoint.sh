#!/usr/bin/env sh

: ${MEGA_DIRECTORY:=/}
: ${MEGA_EMAIL}
: ${MEGA_PASSWORD}
: ${MEGA_SCALE:=1}
: ${MEGA_STREAM_LIMIT:=8}
: ${MEGA_TRANSFER_LIMIT:=6}
: ${RCLONE_BUFFER_SIZE:=64}
: ${RCLONE_CHUNK_SIZE:=64}
: ${RCLONE_STREAM_LIMIT:="$(( $MEGA_STREAM_LIMIT * $MEGA_SCALE ))"}
: ${RCLONE_TRANSFER_LIMIT:="$(( $MEGA_TRANSFER_LIMIT * $MEGA_SCALE ))"}
: ${RCLONE_VFS_CACHE_MAX_SIZE:="$(( $MEGA_STREAM_LIMIT * $RCLONE_CHUNK_SIZE * 2 + $MEGA_TRANSFER_LIMIT * $RCLONE_CHUNK_SIZE ))"}
: ${RCLONE_VFS_READ_AHEAD:="$(( $RCLONE_CHUNK_SIZE * 2 ))"}
: ${RCLONE_VFS_READ_CHUNK_SIZE:=1}
: ${RCLONE_VFS_READ_CHUNK_SIZE_LIMIT:=8}
: ${SMB_PASSWORD}
: ${SMB_USERNAME}

iptables-save | iptables-restore-translate -f /dev/stdin > /etc/nftables.d/iptables.nft
iptables -F; iptables -X; iptables -P INPUT ACCEPT; iptables -P OUTPUT ACCEPT; iptables -P FORWARD ACCEPT
apk del iptables

mkdir -p \
    /etc/mega \
    /etc/rclone \
    /etc/samba \
    /run/openrc

chmod +x \
    /entrypoint.sh \
    /etc/init.d/mega \
    /etc/init.d/squid \
    /etc/init.d/rclone

cat << EOF >> /etc/mega/.env
DIRECTORY="$MEGA_DIRECTORY"
EMAIL="$MEGA_EMAIL"
PASSWORD="$MEGA_PASSWORD"
STREAM_LIMIT="$MEGA_STREAM_LIMIT"
TRANSFER_LIMIT="$MEGA_TRANSFER_LIMIT"
EOF

cat << EOF >> /etc/rclone/.env
BUFFER_SIZE="$RCLONE_BUFFER_SIZE"
CHUNK_SIZE="$RCLONE_CHUNK_SIZE"
STREAM_LIMIT="$RCLONE_STREAM_LIMIT"
TRANSFER_LIMIT="$RCLONE_TRANSFER_LIMIT"
VFS_CACHE_MAX_SIZE="$RCLONE_VFS_CACHE_MAX_SIZE"
VFS_READ_AHEAD="$RCLONE_VFS_READ_AHEAD"
VFS_READ_CHUNK_SIZE="$RCLONE_VFS_READ_CHUNK_SIZE"
VFS_READ_CHUNK_SIZE_LIMIT="$RCLONE_VFS_READ_CHUNK_SIZE_LIMIT"
EOF

cat << EOF >> /etc/samba/.env
USERNAME="$SMB_USERNAME"
PASSWORD="$SMB_PASSWORD"
EOF

chmod 400 \
    /etc/mega/.env \
    /etc/rclone/.env \
    /etc/samba/.env

ID=0
REMOTES=""
while [ "$ID" -lt "$MEGA_SCALE" ] && [ "$ID" -lt 8 ]; do
cat << EOF >> /etc/rclone/rclone.conf
[mega-${ID}]
type = webdav
vendor = other
url = #mega-${ID}-url
EOF
    cp "/etc/init.d/mega" "/etc/init.d/mega-${ID}"
    cp "/etc/init.d/squid" "/etc/init.d/squid-${ID}"

    rc-update add "mega-${ID}"
    rc-update add "squid-${ID}"

    REMOTES="${REMOTES}mega-${ID}: "
    ID=$(($ID + 1))
done
rm /etc/init.d/mega
rm /etc/init.d/squid

if [ "$MEGA_SCALE" -gt 1 ]; then
cat << EOF >> /etc/rclone/rclone.conf
[remote]
type = union
upstreams = ${REMOTES}
action_policy = eprand
create_policy = eprand
search_policy = epff
EOF
else
    sed -i "s|\[mega-0\]|\[remote\]|" /etc/rclone/rclone.conf
fi

if [ "$RCLONE_CHUNKER_ENABLED" = true ]; then
cat << EOF >> /etc/rclone/rclone.conf
[default]
type = chunker
remote = remote:
chunk_size = ${RCLONE_CHUNK_SIZE}M
hash_type = sha1all
name_format = *.chunk.#
EOF
else
    sed -i "s|\[remote\]|\[default\]|" /etc/rclone/rclone.conf
fi

rc-update add nftables
rc-update add rclone
rc-update add samba

sed -i 's/^tty/#&/' /etc/inittab
touch /run/openrc/softlevel

exec /sbin/init
