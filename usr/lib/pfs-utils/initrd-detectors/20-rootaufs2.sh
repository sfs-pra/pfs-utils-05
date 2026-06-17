#!/bin/sh
# pfs-utils initrd detector: mkinitcpio-rootaufs2

detect_rootaufs2() {
    local cmdline filesystems dir has_diro=0 has_dir=0
    local has_aufs_fs=0 has_aufs_sys=0 has_overlay_fs=0

    cmdline="$(cat /proc/cmdline 2>/dev/null)"
    filesystems="$(cat /proc/filesystems 2>/dev/null)"

    echo "$filesystems" | grep -q '[[:space:]]aufs$'    && has_aufs_fs=1
    echo "$filesystems" | grep -q '[[:space:]]overlay$' && has_overlay_fs=1
    [ -d /sys/fs/aufs ] && has_aufs_sys=1

    echo "$cmdline" | grep -Eq '(^| )diro=[^ ]+' && has_diro=1
    echo "$cmdline" | grep -Eq '(^| )dir=[^ ]+'  && has_dir=1

    if [ "$has_diro" -eq 1 ]; then
        [ "$has_overlay_fs" -eq 1 ] || return 1
        INITRD_LAYERING=overlay
        dir="$(echo "$cmdline" | awk '{
            for (i = 1; i <= NF; i++)
                if ($i ~ /^diro=/) { sub(/^diro=/, "", $i); print $i; exit }
        }')"
    elif [ "$has_dir" -eq 1 ]; then
        [ "$has_aufs_fs" -eq 1 ] || [ "$has_aufs_sys" -eq 1 ] || return 1
        INITRD_LAYERING=aufs
        dir="$(echo "$cmdline" | awk '{
            for (i = 1; i <= NF; i++)
                if ($i ~ /^dir=/) { sub(/^dir=/, "", $i); print $i; exit }
        }')"
    else
        return 1
    fi

    INITRD_NAME=rootaufs2
    INITRD_AUFS_PREFIX=/run/archroot/live/memory/images
    INITRD_DOWNLOAD_DIR="${dir:+/mnt/home/${dir}/optional}"
    INITRD_SOURCE_PREFIX=/run/archroot/root_ro
    return 0
}
