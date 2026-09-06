#!/bin/sh
# /opt/stack/scripts/mount-stack-volume.sh
# 起動時に root で実行され、暗号化 APFS ボリューム "Stack" を /opt/stack/data にマウントする。
# パスフレーズは FileVault で守られた /opt/stack/secrets/stack-volume.key から読み、標準入力で渡す。
set -eu

KEY_FILE=/opt/stack/secrets/stack-volume.key
UUID_FILE=/opt/stack/secrets/stack-volume.uuid
MOUNT_POINT=/opt/stack/data

if mount | grep -q " on ${MOUNT_POINT} "; then
    echo "already mounted: ${MOUNT_POINT}"
    exit 0
fi

VOLUME_UUID=$(cat "${UUID_FILE}")

# 既に別の場所（/Volumes/Stack など）にマウントされていたら外す
if diskutil info "${VOLUME_UUID}" | grep -q "Mounted: *Yes"; then
    diskutil unmount "${VOLUME_UUID}"
fi

cat "${KEY_FILE}" | diskutil apfs unlockVolume "${VOLUME_UUID}" \
    -stdinpassphrase -mountpoint "${MOUNT_POINT}" -nobrowse

mount | grep -q " on ${MOUNT_POINT} " && echo "mounted: ${MOUNT_POINT}"
