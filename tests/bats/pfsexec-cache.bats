#!/usr/bin/env bats

load "helpers.bash"

setup() {
    if [[ ! -x "${PFSUTILS_BIN}/pfsexec" ]]; then
        skip "pfsexec not found in ${PFSUTILS_BIN}"
    fi

    PATH="${PFSUTILS_BIN}:${PATH}"
}

require_pfsexec_cache_runtime_or_skip() {
    if [[ "$(id -u)" -ne 0 ]]; then
        skip "must run as root"
    fi

    if ! grep -q '[[:space:]]overlay$' /proc/filesystems; then
        skip "no overlay support"
    fi

    command -v mksquashfs >/dev/null 2>&1 || skip "mksquashfs missing"
}

write_fake_cache_command_or_skip() {
    local payload_dir="$1"
    local command_name="$2"
    local command_path="${payload_dir}/usr/bin/${command_name}"

    cat >"${command_path}" <<'EOF' || skip "cannot create fake cache command ${command_name}"
#!/bin/sh
if [ -n "${PFS_CACHE_TEST_LOG:-}" ]; then
    printf '%s' "${0##*/}" >>"${PFS_CACHE_TEST_LOG}"
    for arg in "$@"; do
        printf ' %s' "${arg}" >>"${PFS_CACHE_TEST_LOG}"
    done
    printf '\n' >>"${PFS_CACHE_TEST_LOG}"
fi
exit 0
EOF

    chmod +x "${command_path}" || skip "cannot chmod fake cache command ${command_name}"
}

create_fake_cache_commands_or_skip() {
    local payload_dir="$1"
    local command_name

    mkdir -p "${payload_dir}/usr/bin" || skip "cannot create fake cache command dir"

    for command_name in \
        ldconfig \
        glib-compile-schemas \
        gio-querymodules \
        gtk-update-icon-cache \
        update-mime-database \
        gdk-pixbuf-query-loaders \
        update-desktop-database \
        fc-cache; do
        write_fake_cache_command_or_skip "${payload_dir}" "${command_name}"
    done
}

prepare_module_workspace_or_skip() {
    local module_name="$1"
    local module_root="${BATS_TEST_TMPDIR}/${module_name}"

    MODULE_PAYLOAD_DIR="${module_root}/payload"
    MODULE_PATH="${module_root}/${module_name}.pfs"

    mkdir -p "${MODULE_PAYLOAD_DIR}" || skip "cannot create payload dir"
    create_fake_cache_commands_or_skip "${MODULE_PAYLOAD_DIR}"
}

build_module_or_skip() {
    local payload_dir="$1"
    local module_path="$2"

    mksquashfs "${payload_dir}" "${module_path}" -noappend >/dev/null 2>&1 ||
        skip "mksquashfs failed"
}

cache_log_count_for() {
    local log_path="$1"
    local command_name="$2"

    if [[ ! -s "${log_path}" ]]; then
        printf '0\n'
        return
    fi

    awk -v cmd="${command_name}" '$1 == cmd { count++ } END { print count + 0 }' "${log_path}"
}

cache_log_total_lines() {
    local log_path="$1"

    if [[ ! -s "${log_path}" ]]; then
        printf '0\n'
        return
    fi

    awk 'END { print NR + 0 }' "${log_path}"
}

run_pfsexec_with_log() {
    CACHE_LOG_PATH="${BATS_TEST_TMPDIR}/cache.log"
    rm -f -- "${CACHE_LOG_PATH}"

    run env "PFS_CACHE_TEST_LOG=${CACHE_LOG_PATH}" \
        "${PFSUTILS_BIN}/pfsexec" --bind "${BATS_TEST_TMPDIR}" "$@" \
        /bin/true
}

pfsexec_no_cache_module_does_not_invoke_cache_commands() { #@test
    require_pfsexec_cache_runtime_or_skip
    prepare_module_workspace_or_skip "no-cache-module"
    printf 'ok\n' >"${MODULE_PAYLOAD_DIR}/ok.txt"
    build_module_or_skip "${MODULE_PAYLOAD_DIR}" "${MODULE_PATH}"

    run_pfsexec_with_log -m "${MODULE_PATH}"

    [ "${status}" -eq 0 ]
    [ ! -s "${CACHE_LOG_PATH}" ]
}

pfsexec_glib_schema_module_only_invokes_glib_compile_schemas() { #@test
    require_pfsexec_cache_runtime_or_skip
    prepare_module_workspace_or_skip "glib-only-module"

    local schema_dir
    schema_dir="${MODULE_PAYLOAD_DIR}/usr/share/glib-2.0/schemas"
    mkdir -p "${schema_dir}" || skip "cannot create schema dir"
    printf '<schemalist/>\n' >"${schema_dir}/org.pfsutils.test.gschema.xml"
    build_module_or_skip "${MODULE_PAYLOAD_DIR}" "${MODULE_PATH}"

    run_pfsexec_with_log -m "${MODULE_PATH}"

    [ "${status}" -eq 0 ]
    [ "$(cache_log_count_for "${CACHE_LOG_PATH}" "glib-compile-schemas")" -eq 1 ]
    [ "$(cache_log_count_for "${CACHE_LOG_PATH}" "fc-cache")" -eq 0 ]
    [ "$(cache_log_count_for "${CACHE_LOG_PATH}" "update-mime-database")" -eq 0 ]
    [ "$(cache_log_count_for "${CACHE_LOG_PATH}" "gtk-update-icon-cache")" -eq 0 ]
}

pfsexec_icon_only_module_invokes_icon_cache_without_ldconfig() { #@test
    require_pfsexec_cache_runtime_or_skip
    prepare_module_workspace_or_skip "icon-only-module"

    mkdir -p "${MODULE_PAYLOAD_DIR}/usr/share/icons/hicolor" || skip "cannot create icon dir"
    build_module_or_skip "${MODULE_PAYLOAD_DIR}" "${MODULE_PATH}"

    run_pfsexec_with_log -m "${MODULE_PATH}"

    [ "${status}" -eq 0 ]
    [ "$(cache_log_count_for "${CACHE_LOG_PATH}" "gtk-update-icon-cache")" -eq 1 ]
    [ "$(cache_log_count_for "${CACHE_LOG_PATH}" "ldconfig")" -eq 0 ]
}

pfsexec_shared_library_module_invokes_ldconfig_without_fc_cache() { #@test
    require_pfsexec_cache_runtime_or_skip
    prepare_module_workspace_or_skip "shared-library-module"

    mkdir -p "${MODULE_PAYLOAD_DIR}/usr/lib" || skip "cannot create usr/lib"
    : >"${MODULE_PAYLOAD_DIR}/usr/lib/libpfs-cache-test.so"
    build_module_or_skip "${MODULE_PAYLOAD_DIR}" "${MODULE_PATH}"

    run_pfsexec_with_log -m "${MODULE_PATH}"

    [ "${status}" -eq 0 ]
    [ "$(cache_log_count_for "${CACHE_LOG_PATH}" "ldconfig")" -eq 1 ]
    [ "$(cache_log_count_for "${CACHE_LOG_PATH}" "fc-cache")" -eq 0 ]
}

pfsexec_dedupes_same_cache_category_across_multiple_modules() { #@test
    require_pfsexec_cache_runtime_or_skip

    local schema_dir_a
    local schema_dir_b
    local module_a_path
    local module_b_path

    prepare_module_workspace_or_skip "glib-dedupe-a"
    schema_dir_a="${MODULE_PAYLOAD_DIR}/usr/share/glib-2.0/schemas"
    mkdir -p "${schema_dir_a}" || skip "cannot create schema dir"
    printf '<schemalist/>\n' >"${schema_dir_a}/org.pfsutils.test.a.gschema.xml"
    module_a_path="${MODULE_PATH}"
    build_module_or_skip "${MODULE_PAYLOAD_DIR}" "${module_a_path}"

    prepare_module_workspace_or_skip "glib-dedupe-b"
    schema_dir_b="${MODULE_PAYLOAD_DIR}/usr/share/glib-2.0/schemas"
    mkdir -p "${schema_dir_b}" || skip "cannot create schema dir"
    printf '<schemalist/>\n' >"${schema_dir_b}/org.pfsutils.test.b.gschema.xml"
    module_b_path="${MODULE_PATH}"
    build_module_or_skip "${MODULE_PAYLOAD_DIR}" "${module_b_path}"

    run_pfsexec_with_log -m "${module_a_path}" -m "${module_b_path}"

    [ "${status}" -eq 0 ]
    [ "$(cache_log_count_for "${CACHE_LOG_PATH}" "glib-compile-schemas")" -eq 1 ]
    [ "$(cache_log_total_lines "${CACHE_LOG_PATH}")" -eq 1 ]
}
