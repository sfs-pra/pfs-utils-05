#!/usr/bin/env bats

load "helpers.bash"

setup() {
    if [[ ! -x "${PFSUTILS_BIN}/pfsactivate" ]]; then
        skip "pfsactivate not found in ${PFSUTILS_BIN}"
    fi

    PATH="${PFSUTILS_BIN}:${PATH}"
}

@test "pfsactivate --help prints experimental warning" {
    run "${PFSUTILS_BIN}/pfsactivate" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"EXPERIMENTAL"* ]]
}

@test "pfsactivate rejects nonexistent module path" {
    run "${PFSUTILS_BIN}/pfsactivate" /nonexistent.pfs
    [ "$status" -ne 0 ]
}

@test "pfsactivate root-only smoke path" {
    if [[ "$(id -u)" -ne 0 ]]; then
        skip "must run as root"
    fi

    run "${PFSUTILS_BIN}/pfsactivate" --list
    [ "$status" -eq 0 ]
}
