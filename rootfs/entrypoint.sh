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

adduser -s /sbin/nologin -D -h /home/mega-smb mega-smb

mkdir -p \
    /etc/mega \
    /etc/rclone \
    /etc/samba \
    /home/mega-smb/dbus \
    /run/openrc

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

su mega-smb -s /bin/sh -c dbus-launch > /home/mega-smb/dbus/.env

I=0
while [ "$I" -lt "$MEGA_SCALE" ] && [ "$I" -lt 8 ]; do
    cp "/etc/init.d/mega" "/etc/init.d/mega-${I}"
    rc-update add "mega-${I}"
    I=$(($I + 1))
done
rm /etc/init.d/mega

chown -R mega-smb:mega-smb \
    /home/mega-smb

chmod 400 \
    /etc/mega/.env \
    /etc/rclone/.env \
    /etc/samba/.env \
    /home/mega-smb/dbus/.env

rc-update add nftables
rc-update add rclone
rc-update add samba

sed -i 's/^tty/#&/' /etc/inittab
touch /run/openrc/softlevel

exec /sbin/init
