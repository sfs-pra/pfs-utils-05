#!/usr/bin/env bash

if [[ -z "${PFSUTILS_BIN:-}" ]]; then
    PFSUTILS_BIN="${BATS_TEST_DIRNAME}/../../usr/bin"
fi

export PFSUTILS_BIN
