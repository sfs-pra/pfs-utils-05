#!/usr/bin/env bats

load "helpers.bash"

setup() {
    if [[ ! -x "${PFSUTILS_BIN}/pfsrun" ]]; then
        skip "pfsrun not found in ${PFSUTILS_BIN}"
    fi

    if [[ ! -x "${PFSUTILS_BIN}/pfsexec" ]]; then
        skip "pfsexec not found in ${PFSUTILS_BIN}"
    fi

    PATH="${PFSUTILS_BIN}:${PATH}"
}

create_temp_module_or_skip() {
    command -v mksquashfs >/dev/null 2>&1 || skip "mksquashfs missing"

    work_dir="${BATS_TEST_TMPDIR}/pfsrun-overlay"
    payload_dir="${work_dir}/payload"
    module_path="${work_dir}/tiny-module.pfs"

    mkdir -p "${payload_dir}" || skip "cannot create payload dir"
    printf 'ok\n' >"${payload_dir}/ok.txt"

    mksquashfs "${payload_dir}" "${module_path}" -noappend >/dev/null 2>&1 \
        || skip "mksquashfs failed"

    TEST_MODULE_PATH="${module_path}"
}

pfsrun_help_prints_usage() { #@test
    if [[ "$(id -u)" -ne 0 ]]; then
        skip "must run as root"
    fi

    run "${PFSUTILS_BIN}/pfsrun" --help

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Usage: pfsrun"* || "${output}" == *"Использование: pfsrun"* ]]
}

pfsrun_root_gated_no_gui_exec_smoke() { #@test
    if [[ "$(id -u)" -ne 0 ]]; then
        skip "must run as root"
    fi

    create_temp_module_or_skip

    run "${PFSUTILS_BIN}/pfsrun" --no-gui --root --exec /bin/true "${TEST_MODULE_PATH}"

    [ "${status}" -eq 0 ]
}

pfsexec_private_namespace_root_smoke() { #@test
    if [[ "$(id -u)" -ne 0 ]]; then
        skip "must run as root"
    fi

    create_temp_module_or_skip

    run "${PFSUTILS_BIN}/pfsexec" "${TEST_MODULE_PATH}" /bin/true

    [ "${status}" -eq 0 ]
}

pfsrun_waits_for_glib_schema_cache_before_exec() { #@test
    if [[ "$(id -u)" -ne 0 ]]; then
        skip "must run as root"
    fi

    if ! grep -q '[[:space:]]overlay$' /proc/filesystems; then
        skip "no overlay support"
    fi

    command -v mksquashfs >/dev/null 2>&1 || skip "mksquashfs missing"
    command -v gsettings >/dev/null 2>&1 || skip "gsettings missing"
    command -v glib-compile-schemas >/dev/null 2>&1 || skip "glib-compile-schemas missing"

    work_dir="${BATS_TEST_TMPDIR}/pfsrun-glib-schema"
    payload_dir="${work_dir}/payload"
    schema_dir="${payload_dir}/usr/share/glib-2.0/schemas"
    module_path="${work_dir}/glib-schema-test.pfs"

    mkdir -p "${schema_dir}" || skip "cannot create schema payload"
    cat >"${schema_dir}/org.pfsutils.test.gschema.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<schemalist>
  <schema id="org.pfsutils.test" path="/org/pfsutils/test/">
    <key name="message" type="s">
      <default>'hello-from-module'</default>
      <summary>test key</summary>
      <description>test key description</description>
    </key>
  </schema>
</schemalist>
EOF

    mksquashfs "${payload_dir}" "${module_path}" -noappend >/dev/null 2>&1 \
        || skip "mksquashfs failed"

    run "${PFSUTILS_BIN}/pfsrun" --no-gui --root --exec /usr/bin/gsettings \
        "${module_path}" get org.pfsutils.test message

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"hello-from-module"* ]]
}
