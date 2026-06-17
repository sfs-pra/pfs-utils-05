#!/bin/sh
# pfs-utils initrd detector: Slax / LiveKit

detect_livekit() {
    local cmdline sysmnt

    cmdline="$(cat /proc/cmdline 2>/dev/null)"

    # If uird markers are present, uird detector should win — we are a
    # weaker fallback for plain from=/changes= cmdline.
    echo "$cmdline" | grep -Eq '(^| )(uird\.|uird=)' && return 1

    echo "$cmdline" | grep -Eq '(^| )(from|changes)=[^ ]+' || return 1

    INITRD_NAME=livekit
    INITRD_LAYERING=overlay
    sysmnt="${SYSMNT:-/mnt/live/memory}"
    INITRD_AUFS_PREFIX="${sysmnt%/}/bundles"
    INITRD_DOWNLOAD_DIR=""
    INITRD_SOURCE_PREFIX=""
    return 0
}
