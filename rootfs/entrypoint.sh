#!/usr/bin/env sh

set -ex

: ${MEGA_DIRECTORY:=/}
: ${MEGA_EMAIL}
: ${MEGA_PASSWORD}
: ${MEGA_SCALE:=1}
: ${MEGA_STREAM_LIMIT:=8}
: ${MEGA_TRANSFER_LIMIT:=6}
: ${SMB_PASSWORD}
: ${SMB_USERNAME}

iptables-save | iptables-restore-translate -f /dev/stdin > /etc/nftables.d/iptables.nft
iptables -F; iptables -X; iptables -P INPUT ACCEPT; iptables -P OUTPUT ACCEPT; iptables -P FORWARD ACCEPT
apk del iptables

mkdir -p \
    /etc/mega \
    /etc/samba \
    /run/openrc

cat << EOF >> /etc/mega/.env
DIRECTORY="$MEGA_DIRECTORY"
EMAIL="$MEGA_EMAIL"
PASSWORD="$MEGA_PASSWORD"
STREAM_LIMIT="$MEGA_STREAM_LIMIT"
TRANSFER_LIMIT="$MEGA_TRANSFER_LIMIT"
EOF

cat << EOF >> /etc/samba/.env
USERNAME="$SMB_USERNAME"
PASSWORD="$SMB_PASSWORD"
EOF

chmod 700 \
    /etc/mega/.env \
    /etc/samba/.env

ID=0
REMOTES=""
while [ "$ID" -lt "$MEGA_SCALE" ] && [ "$ID" -lt 8 ]; do
    cp "/etc/init.d/mega" "/etc/init.d/mega-${ID}"
    rc-update add "mega-${ID}"
    REMOTES="${REMOTES}/chroot/mega-${ID}/mnt:"
    ID=$(($ID + 1))
done
rm /etc/init.d/mega
sed -i "s|branches=|branches=${REMOTES%:*}|" /etc/mergerfs/mergerfs.conf

rc-update add mergerfs
rc-update add nftables
rc-update add samba

sed -i 's/^tty/#&/' /etc/inittab
touch /run/openrc/softlevel

exec /sbin/init
