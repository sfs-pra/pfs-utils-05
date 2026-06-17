#!/bin/sh
# pfs-utils initrd detector: UIRD (Universal Initrd)

detect_uird() {
    local cmdline sysmnt
    cmdline="$(cat /proc/cmdline 2>/dev/null)"

    echo "$cmdline" | grep -Eq '(^| )(uird\.(from|load|mode|changes|config|ro|rw|union|cache|homes|home|mounts)=|uird\.)' || return 1

    INITRD_NAME=uird
    INITRD_LAYERING=overlay
    sysmnt="${SYSMNT:-/memory}"
    INITRD_AUFS_PREFIX="${sysmnt%/}/bundles"
    INITRD_DOWNLOAD_DIR=""
    INITRD_SOURCE_PREFIX=""
    return 0
}
