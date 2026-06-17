#!/usr/bin/env bats

load "helpers.bash"

setup() {
    if [[ ! -x "${PFSUTILS_BIN}/chroot2pfs" ]]; then
        skip "chroot2pfs not found in ${PFSUTILS_BIN}"
    fi
}

chroot2pfs_overlay_help_mentions_backend_flags() { #@test
    run "${PFSUTILS_BIN}/chroot2pfs" --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"--overlay"* ]]
    [[ "$output" == *"--aufs"* ]]
}

chroot2pfs_overlay_script_passes_bash_n() { #@test
    run bash -n "${PFSUTILS_BIN}/chroot2pfs"

    [ "$status" -eq 0 ]
}

chroot2pfs_overlay_live_smoke_requires_root() { #@test
    if [[ "$(id -u)" -ne 0 ]]; then
        skip "must run as root"
    fi

    if ! grep -qw overlay /proc/filesystems; then
        skip "overlayfs not available"
    fi

    run env PATH="${PFSUTILS_BIN}:$PATH" bash -c '
        set -Eeuo pipefail
        help_text="$($1 --overlay --help 2>&1)"
        [[ "$help_text" == *"--overlay"* ]]
        [[ "$help_text" == *"--aufs"* ]]
    ' _ "${PFSUTILS_BIN}/chroot2pfs"

    [ "$status" -eq 0 ]
}

mkoverlay_chroot_loops_pfs_files_via_squashfs_mount() { #@test
    # Smoke regression for the bug where mkoverlay_chroot passed raw .pfs
    # paths into overlay lowerdir. Fix loop-mounts each .pfs at /mnt/.<bn>
    # before composing lowerdir.
    run grep -E 'mount -t squashfs.*-o loop' "${PFSUTILS_BIN}/pfs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"squashfs"* ]]
}

mkoverlay_cleanup_has_lazy_unmount_fallback() { #@test
    run grep -A8 '^pfs_unmount_path' "${PFSUTILS_BIN}/pfs"
    [ "$status" -eq 0 ]
    [[ "$output" == *'umount -l "$_mp"'* ]]
}

mkaufs_rolls_back_lock_and_tmpfs_on_failed_aufs_mount() { #@test
    run grep -A12 '^mkaufs_rollback' "${PFSUTILS_BIN}/pfs"
    [ "$status" -eq 0 ]
    [[ "$output" == *'rm -f "$SYSMNT/aufs${_N}.lock"'* ]]
    [[ "$output" == *'rm -rf "$SYSMNT/changes${_N}"'* ]]

    run grep -A12 '^mkaufs ()' "${PFSUTILS_BIN}/pfs"
    [ "$status" -eq 0 ]
    [[ "$output" == *'mount -t tmpfs tmpfs /$SYSMNT/changes$N || { mkaufs_rollback "$N" ; return 1 ; }'* ]]
    [[ "$output" == *'mkaufs_rollback "$N"'* ]]
}

delaufs_cleans_overlay_session_residue() { #@test
    run grep -A42 '^delaufs ()' "${PFSUTILS_BIN}/pfs"
    [ "$status" -eq 0 ]
    [[ "$output" == *'pfs_cleanup_mount_tree "$SYSMNT/bundles$N/$D"'* ]]
    [[ "$output" == *'rm -rf $SYSMNT/bundles$N'* ]]
    [[ "$output" == *'$SYSMNT/overlay${N}.lock'* ]]
}
