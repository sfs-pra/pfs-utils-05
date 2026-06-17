#!/bin/sh
#
# pfsbench-add-decompress.sh
# -------------------------------------------------------------------------
# Extend /usr/local/bin/pfsbench with a --decompress/--read flag that
# measures cold-cache read throughput (the actual decompression cost after
# pfsload). Idempotent: reruns are a no-op.
#
# Usage (must run as root, pfsbench needs drop_caches):
#   sudo sh pfsbench-add-decompress.sh
#
# Then benchmark a real module with the new column:
#   sudo pfsbench /path/to/module.pfs --decompress --runs 2
#
# Rationale: pfsbench roundtrip = mount + unmount (superblock read only).
# The big cost for real programs is lazy file decompression on first access.
# xz-compressed squashfs shows a ~4 s first-use pause on 500 MB of data on
# aarch64; zstd/lz4 finish in ~0.8-1.4 s. `--decompress` exposes that gap.
#
# Author: sfs (modman refactor, 2026-04-23)
# -------------------------------------------------------------------------

set -eu

: "${EXT:=pfs}"

usage() {
    cat <<EOF
pfsbench-add-decompress: patch /usr/local/bin/pfsbench to add --decompress.

Usage:
    sudo sh $(basename "$0")            # patch the default /usr/local/bin/pfsbench
    sudo sh $(basename "$0") PATH       # patch pfsbench at custom PATH
    sudo sh $(basename "$0") -h         # this help

After patching, run the benchmark itself like this:
    sudo pfsbench <module.${EXT}> --decompress --runs 2

This script does NOT take a .${EXT} module as an argument — it only modifies
the pfsbench tool.  Passing a binary .${EXT} here will trigger a UTF-8 decode
error.  See "Usage" above.
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac

TARGET="${1:-/usr/local/bin/pfsbench}"

[ -f "${TARGET}" ] || {
    echo "pfsbench-add-decompress: ${TARGET} not found" >&2
    echo "                        (expected a path to the pfsbench script)" >&2
    exit 1
}

# Refuse binary files early with a clear message.
_peek=$(head -c 2 "${TARGET}" 2>/dev/null || true)
case "${_peek}" in
    "#!") : ;;  # looks like a shell script — proceed
    *)
        echo "pfsbench-add-decompress: ${TARGET} is not a shell script." >&2
        echo "                        Probably you passed a .${EXT} module by mistake." >&2
        echo "                        Run without arguments to patch the installed pfsbench," >&2
        echo "                        then:  sudo pfsbench ${TARGET} --decompress" >&2
        exit 2
        ;;
esac

# Cheap sanity-check: the file should at least mention pfsbench.
if ! grep -q 'pfsbench' "${TARGET}" 2>/dev/null ; then
    echo "pfsbench-add-decompress: ${TARGET} does not look like pfsbench." >&2
    echo "                        Refusing to modify it." >&2
    exit 3
fi

if grep -q 'cold_read_ms ()' "${TARGET}" || grep -q 'cold_read_ms()' "${TARGET}"; then
    echo "pfsbench already patched (cold_read_ms present) — nothing to do."
    exit 0
fi

python3 - "${TARGET}" <<'PYEOF'
import sys, re

p = sys.argv[1]
with open(p) as f: s = f.read()

# 1) Add --decompress flag to argparse
old_opts = '''        --full|--all) FULL=1; shift ;;'''
new_opts = '''        --full|--all) FULL=1; shift ;;
        --decompress|--read) DECOMPRESS=1; shift ;;'''
assert old_opts in s, "arg-parser anchor missing"
s = s.replace(old_opts, new_opts, 1)

# 2) Default for DECOMPRESS near FULL init
old_init = 'FULL=""'
new_init = 'FULL=""\nDECOMPRESS=""'
assert old_init in s, "FULL init anchor missing"
s = s.replace(old_init, new_init, 1)

# 3) Help text
old_help = (
    '    --full, --all               run the full sweep (include variants that\n'
    '                                lose to the curated ones — use for audits)'
)
new_help = old_help + '''
    --decompress, --read        also measure COLD decompression throughput:
                                drop_caches + cat every file in the mounted
                                module. This is the "time until the program
                                actually starts" for image-type modules.'''
assert old_help in s, "--full help anchor missing"
s = s.replace(old_help, new_help, 1)

# 4) Add cold_read_ms() helper
old_helper = 'roundtrip_ms() {'
new_helper = '''cold_read_ms() {
    # $1 = image path. Returns time in ms to read every file inside the module
    # after dropping page caches — i.e. the real decompression cost per fs.
    img="$1"
    pfsload "${img}" >/dev/null 2>&1 || { echo "-1"; return; }
    mp="/mnt/.$(basename "${img}")"
    if [ ! -d "${mp}" ]; then
        pfsunload "${img}" >/dev/null 2>&1
        echo "-1"; return
    fi
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    t0=$(ms_now)
    find "${mp}" -type f -print0 2>/dev/null \\
        | xargs -0 -r cat >/dev/null 2>&1
    t1=$(ms_now)
    pfsunload "${img}" >/dev/null 2>&1
    echo $((t1 - t0))
}

roundtrip_ms() {'''
assert old_helper in s, "roundtrip_ms anchor missing"
s = s.replace(old_helper, new_helper, 1)

# 5) Extended table header when --decompress
old_hdr = '''printf '\\n== pfsbench (payload=%s KB, runs=%s) ==\\n\\n' "${SRC_KB:-?}" "${RUNS}"
printf '%-18s | %9s | %10s | %14s\\n' "variant" "size KB" "build ms" "roundtrip ms"
printf -- '-------------------+-----------+------------+----------------\\n\''''
new_hdr = '''printf '\\n== pfsbench (payload=%s KB, runs=%s%s) ==\\n\\n' \\
    "${SRC_KB:-?}" "${RUNS}" "${DECOMPRESS:+ +decompress}"
if [ -n "${DECOMPRESS}" ]; then
    printf '%-18s | %9s | %10s | %12s | %12s\\n' "variant" "size KB" "build ms" "roundtrip ms" "cold read ms"
    printf -- '-------------------+-----------+------------+--------------+--------------\\n'
else
    printf '%-18s | %9s | %10s | %14s\\n' "variant" "size KB" "build ms" "roundtrip ms"
    printf -- '-------------------+-----------+------------+----------------\\n'
fi'''
assert old_hdr in s, "table header anchor missing"
s = s.replace(old_hdr, new_hdr, 1)

# 6) Extend row() with cold-read column
old_row = '''row() {
    label="$1"; img="$2"; build_ms="$3"
    sz=$(size_kb "${img}")
    rt=$(roundtrip_ms "${img}")
    printf '%-18s | %9s | %10s | %14s\\n' "${label}" "${sz}" "${build_ms}" "${rt}"
    [ -n "${CSV}" ] && printf '%s,%s,%s,%s,%s,%s\\n' "${label}" "${sz}" "${build_ms}" "${rt}" "${RUNS}" "${SRC_KB}" >> "${CSV}"
    if [ "${rt}" -lt "${BEST_LOAD_MS}" ]; then
        BEST_LOAD_MS="${rt}"; BEST_LOAD_VARIANT="${label}"
    fi
    if [ "${sz}" -lt "${BEST_SIZE_KB}" ] && [ "${sz}" -gt 0 ]; then
        BEST_SIZE_KB="${sz}"; BEST_SIZE_VARIANT="${label}"
    fi
    if [ "${build_ms}" -lt "${BEST_BUILD_MS}" ]; then
        BEST_BUILD_MS="${build_ms}"; BEST_BUILD_VARIANT="${label}"
    fi
}'''

new_row = '''row() {
    label="$1"; img="$2"; build_ms="$3"
    sz=$(size_kb "${img}")
    rt=$(roundtrip_ms "${img}")
    cr="-"
    if [ -n "${DECOMPRESS}" ]; then
        cr=$(cold_read_ms "${img}")
    fi
    if [ -n "${DECOMPRESS}" ]; then
        printf '%-18s | %9s | %10s | %12s | %12s\\n' "${label}" "${sz}" "${build_ms}" "${rt}" "${cr}"
    else
        printf '%-18s | %9s | %10s | %14s\\n' "${label}" "${sz}" "${build_ms}" "${rt}"
    fi
    [ -n "${CSV}" ] && printf '%s,%s,%s,%s,%s,%s,%s\\n' "${label}" "${sz}" "${build_ms}" "${rt}" "${cr}" "${RUNS}" "${SRC_KB}" >> "${CSV}"
    if [ "${rt}" -lt "${BEST_LOAD_MS}" ]; then
        BEST_LOAD_MS="${rt}"; BEST_LOAD_VARIANT="${label}"
    fi
    if [ "${sz}" -lt "${BEST_SIZE_KB}" ] && [ "${sz}" -gt 0 ]; then
        BEST_SIZE_KB="${sz}"; BEST_SIZE_VARIANT="${label}"
    fi
    if [ "${build_ms}" -lt "${BEST_BUILD_MS}" ]; then
        BEST_BUILD_MS="${build_ms}"; BEST_BUILD_VARIANT="${label}"
    fi
    if [ -n "${DECOMPRESS}" ] && [ "${cr}" != "-" ]; then
        case "${cr}" in ''|-*|*[!0-9]*) ;;
            *)
                if [ -z "${BEST_READ_MS:-}" ] || [ "${cr}" -lt "${BEST_READ_MS}" ]; then
                    BEST_READ_MS="${cr}"
                    BEST_READ_VARIANT="${label}"
                fi
                ;;
        esac
    fi
}'''
assert old_row in s, "row() anchor missing"
s = s.replace(old_row, new_row, 1)

# 7) Extended Winners block
old_win = '''printf -- '-------------------+-----------+------------+----------------\\n'
printf '\\nWinners:\\n'
printf '  smallest image       : %-20s (%s KB)\\n' "${BEST_SIZE_VARIANT:-n/a}" "${BEST_SIZE_KB}"
printf '  fastest load+unload  : %-20s (%s ms)\\n' "${BEST_LOAD_VARIANT:-n/a}" "${BEST_LOAD_MS}"
printf '  fastest build        : %-20s (%s ms)\\n' "${BEST_BUILD_VARIANT:-n/a}" "${BEST_BUILD_MS}"'''

new_win = '''if [ -n "${DECOMPRESS}" ]; then
    printf -- '-------------------+-----------+------------+--------------+--------------\\n'
else
    printf -- '-------------------+-----------+------------+----------------\\n'
fi
printf '\\nWinners:\\n'
printf '  smallest image       : %-20s (%s KB)\\n' "${BEST_SIZE_VARIANT:-n/a}" "${BEST_SIZE_KB}"
printf '  fastest load+unload  : %-20s (%s ms)\\n' "${BEST_LOAD_VARIANT:-n/a}" "${BEST_LOAD_MS}"
printf '  fastest build        : %-20s (%s ms)\\n' "${BEST_BUILD_VARIANT:-n/a}" "${BEST_BUILD_MS}"
[ -n "${DECOMPRESS}" ] && printf '  fastest cold read    : %-20s (%s ms)\\n' "${BEST_READ_VARIANT:-n/a}" "${BEST_READ_MS:-n/a}"'''
assert old_win in s, "Winners anchor missing"
s = s.replace(old_win, new_win, 1)

with open(p, "w") as f: f.write(s)
print("pfsbench patched with --decompress/--read")
PYEOF

# Syntax check the result
if sh -n "${TARGET}" 2>/dev/null; then
    echo "syntax: OK"
else
    echo "syntax: FAIL — restoring is up to you (bash -n ${TARGET} for details)" >&2
    exit 2
fi

# Optional: shellcheck if present
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -S error "${TARGET}" >/dev/null 2>&1 \
        && echo "shellcheck: OK" \
        || echo "shellcheck: warnings (non-fatal)"
fi

echo
echo "Done. Try:"
echo "  sudo pfsbench --size medium --runs 1 --decompress"
echo "  sudo pfsbench /path/to/module.${EXT} --decompress --runs 2"
