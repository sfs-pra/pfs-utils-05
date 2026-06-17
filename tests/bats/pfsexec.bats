#!/usr/bin/env bats

load "helpers.bash"

setup() {
    if [[ ! -x "${PFSUTILS_BIN}/pfsexec" ]]; then
        skip "pfsexec not found in ${PFSUTILS_BIN}"
    fi
}

pfsexec_help_prints_usage() { #@test
    run "${PFSUTILS_BIN}/pfsexec" --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* || "$output" == *"Использование"* ]]
}

pfsexec_without_module_returns_2_and_prefixed_error() { #@test
    run "${PFSUTILS_BIN}/pfsexec"

    [ "$status" -eq 2 ]
    [[ "$output" == *"pfsexec:"* ]]
}

pfsexec_rejects_non_module_files_with_exit_5() { #@test
    run "${PFSUTILS_BIN}/pfsexec" /etc/os-release

    [ "$status" -eq 5 ]
    [[ "$output" == *"pfsexec:"* ]]
}

pfsexec_root_gated_smoke() { #@test
    if [[ "$(id -u)" -ne 0 ]]; then
        skip "must run as root"
    fi

    run "${PFSUTILS_BIN}/pfsexec" --help

    [ "$status" -eq 0 ]
}

pfsexec_overlay_support_gated_smoke() { #@test
    if ! grep -q '[[:space:]]overlay$' /proc/filesystems; then
        skip "no overlay support"
    fi

    run "${PFSUTILS_BIN}/pfsexec" --help

    [ "$status" -eq 0 ]
}
