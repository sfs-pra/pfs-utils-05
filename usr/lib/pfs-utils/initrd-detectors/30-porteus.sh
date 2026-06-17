#!/bin/sh
# pfs-utils initrd detector: Porteus

detect_porteus() {
    local cmdline filesystems sysmnt
    local has_aufs_fs=0 has_aufs_sys=0

    cmdline="$(cat /proc/cmdline 2>/dev/null)"
    filesystems="$(cat /proc/filesystems 2>/dev/null)"

    echo "$filesystems" | grep -q '[[:space:]]aufs$' && has_aufs_fs=1
    [ -d /sys/fs/aufs ] && has_aufs_sys=1

    echo "$cmdline" | grep -Eq '(^| )(psubdir=|from=/[^ ]*porteus[^ ]*|changes=/[^ ]*porteus[^ ]*|porteus(\.cfg|/| ))' || return 1
    [ "$has_aufs_fs" -eq 1 ] || [ "$has_aufs_sys" -eq 1 ] || return 1

    INITRD_NAME=porteus
    INITRD_LAYERING=aufs
    sysmnt="${SYSMNT:-/mnt/live/memory}"
    INITRD_AUFS_PREFIX="${sysmnt%/}/bundles"
    INITRD_DOWNLOAD_DIR=""
    INITRD_SOURCE_PREFIX=""
    return 0
}
