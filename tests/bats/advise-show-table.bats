#!/usr/bin/env bats

load "helpers.bash"

setup() {
    PATH="${PFSUTILS_BIN}:${PATH}"
}

resolve_tool_or_skip() {
    tool_name="$1"

    if [ -x "${PFSUTILS_BIN}/${tool_name}" ]; then
        RESOLVED_TOOL="${PFSUTILS_BIN}/${tool_name}"
        return 0
    fi

    if command -v "${tool_name}" >/dev/null 2>&1; then
        RESOLVED_TOOL="$(command -v "${tool_name}")"
        return 0
    fi

    skip "${tool_name} not in PATH"
}

require_root_or_skip() {
    [ "$(id -u)" -eq 0 ] || skip "must run as root"
}

require_bench_toolchain_or_skip() {
    command -v mksquashfs >/dev/null 2>&1 || skip "mksquashfs missing"
    resolve_tool_or_skip pfsload
    resolve_tool_or_skip pfsunload
}

require_aufs_benchmark_runtime_or_skip() {
    if [ "${PFS_LAYERING:-}" = "overlay" ]; then
        skip "AUFS-only benchmark on overlay"
    fi

    if command -v pfs >/dev/null 2>&1; then
        layering_mode="$(pfs --layering-mode 2>/dev/null || true)"
        if [ "${layering_mode}" = "overlay" ]; then
            skip "AUFS-only benchmark on overlay"
        fi
    fi
}

find_fixture_or_skip() {
    for fixture_dir in /mnt/live/memory/changes /tmp /var/tmp; do
        [ -d "${fixture_dir}" ] || continue

        for candidate in "${fixture_dir}"/*.pfs; do
            [ -e "${candidate}" ] || continue
            FIXTURE_PATH="${candidate}"
            return 0
        done
    done

    skip "no .pfs fixture found"
}

pfsbench_help_contains_machine_flag() { #@test
    resolve_tool_or_skip pfsbench

    run "${RESOLVED_TOOL}" --help
    [ "${status}" -eq 0 ]
    printf '%s\n' "${output}" | grep -q -- '--machine'
}

pfsbench_machine_header_has_seven_columns() { #@test
    resolve_tool_or_skip pfsbench
    pfsbench_cmd="${RESOLVED_TOOL}"
    require_aufs_benchmark_runtime_or_skip
    require_root_or_skip
    require_bench_toolchain_or_skip

    run "${pfsbench_cmd}" --size small --runs 1 --machine
    [ "${status}" -eq 0 ]

    header="$(printf '%s\n' "${output}" | awk 'NR == 1 { print; exit }')"
    [ -n "${header}" ]
    [ "$(printf '%s' "${header}" | awk -F '\t' '{ print NF }')" -eq 7 ]
}

pfsbench_machine_stdout_has_no_trailer_keywords() { #@test
    resolve_tool_or_skip pfsbench
    pfsbench_cmd="${RESOLVED_TOOL}"
    require_aufs_benchmark_runtime_or_skip
    require_root_or_skip
    require_bench_toolchain_or_skip

    run "${pfsbench_cmd}" --size small --runs 1 --machine
    [ "${status}" -eq 0 ]
    ! printf '%s\n' "${output}" | grep -qE '^(Winners:|Recommendation:|Raw data:)'
}

pfsinfo_advise_human_mode_streams_table_before_verdict() { #@test
    resolve_tool_or_skip pfsinfo
    pfsinfo_cmd="${RESOLVED_TOOL}"
    resolve_tool_or_skip pfsbench
    require_aufs_benchmark_runtime_or_skip
    require_root_or_skip
    find_fixture_or_skip

    run "${pfsinfo_cmd}" --advise "${FIXTURE_PATH}"
    [ "${status}" -eq 0 ]

    printf '%s\n' "${output}" | grep -q '^variant' || skip "pfsbench table not shown (toolchain missing?)"

    table_line="$(printf '%s\n' "${output}" | awk '/^variant/ { print NR; exit }')"
    verdict_line="$(printf '%s\n' "${output}" | awk '/optimal/ { print NR; exit }')"

    [ -n "${table_line}" ]
    [ -n "${verdict_line}" ]
    [ "${table_line}" -lt "${verdict_line}" ]
}

pfsinfo_machine_advise_outputs_five_tsv_lines() { #@test
    resolve_tool_or_skip pfsinfo
    pfsinfo_cmd="${RESOLVED_TOOL}"
    resolve_tool_or_skip pfsbench
    require_aufs_benchmark_runtime_or_skip
    require_root_or_skip
    find_fixture_or_skip

    run "${pfsinfo_cmd}" --machine --advise "${FIXTURE_PATH}"
    [ "${status}" -eq 0 ]

    line_count="$(printf '%s\n' "${output}" | awk 'END { print NR }')"
    first_label="$(printf '%s\n' "${output}" | awk 'NR == 1 { print $1; exit }')"

    [ "${line_count}" -eq 5 ]
    [ "${first_label}" = "current" ]
}
