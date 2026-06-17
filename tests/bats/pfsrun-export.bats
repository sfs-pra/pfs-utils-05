#!/usr/bin/env bats

load "helpers.bash"

setup() {
    if [[ ! -x "${PFSUTILS_BIN}/pfsrun" ]]; then
        skip "pfsrun not found in ${PFSUTILS_BIN}"
    fi

    if [[ ! -x "${PFSUTILS_BIN}/pfsexec" ]]; then
        skip "pfsexec not found in ${PFSUTILS_BIN}"
    fi

    REAL_HOME="${HOME:-}"
    PFSRUN_CMD="${PFSUTILS_BIN}/pfsrun"
    TEST_COMMAND_PATH="${PFSUTILS_BIN}:${PATH}"
    SESSION_PID=""
    SESSION_TWO_PID=""
}

teardown() {
    terminate_background_session "${SESSION_PID:-}"
    terminate_background_session "${SESSION_TWO_PID:-}"
}

prepare_temp_xdg_env() {
    TEST_ROOT="${BATS_TEST_TMPDIR}/pfsrun-export-${BATS_TEST_NUMBER}-$$"
    TEST_HOME="${TEST_ROOT}/home"
    TEST_XDG_DATA_HOME="${TEST_ROOT}/xdg-data"
    TEST_XDG_CACHE_HOME="${TEST_ROOT}/xdg-cache"
    TEST_XDG_CONFIG_HOME="${TEST_ROOT}/xdg-config"
    TEST_APPLICATIONS_DIR="${TEST_XDG_DATA_HOME}/applications"
    TEST_ICONS_BASE_DIR="${TEST_XDG_DATA_HOME}/icons"
    TEST_ICON_APPS_DIR="${TEST_ICONS_BASE_DIR}/hicolor/48x48/apps"
    TEST_PIXMAPS_DIR="${TEST_XDG_DATA_HOME}/pixmaps"
    TEST_EXPORTS_DIR="${TEST_XDG_CACHE_HOME}/pfsrun/exports"

    mkdir -p \
        "${TEST_HOME}" \
        "${TEST_APPLICATIONS_DIR}" \
        "${TEST_ICON_APPS_DIR}" \
        "${TEST_PIXMAPS_DIR}" \
        "${TEST_EXPORTS_DIR}" \
        "${TEST_XDG_CONFIG_HOME}" \
        || skip "cannot create temp HOME/XDG roots"
}

require_pfsrun_export_runtime_or_skip() {
    if [[ "$(id -u)" -ne 0 ]]; then
        skip "must run as root"
    fi

    if ! grep -q '[[:space:]]overlay$' /proc/filesystems; then
        skip "no overlay support"
    fi

    command -v mksquashfs >/dev/null 2>&1 || skip "mksquashfs missing"
    command -v unshare >/dev/null 2>&1 || skip "unshare missing"

    if ! unshare --help 2>&1 | grep -q -- '--propagation'; then
        skip "unshare missing --propagation support"
    fi
}

prepare_fake_root_parser_wrapper_or_skip() {
    PARSER_BIN_DIR="${TEST_ROOT}/parser-bin"
    mkdir -p "${PARSER_BIN_DIR}" || skip "cannot create parser wrapper dir"

    cp "${PFSUTILS_BIN}/pfsrun" "${PARSER_BIN_DIR}/pfsrun" || skip "cannot copy pfsrun parser wrapper"
    chmod +x "${PARSER_BIN_DIR}/pfsrun" || skip "cannot chmod parser wrapper"

    cat >"${PARSER_BIN_DIR}/id" <<'EOF' || skip "cannot create fake id"
#!/usr/bin/env bash
if [[ "${1:-}" == "-u" ]]; then
    printf '0\n'
    exit 0
fi
exec /usr/bin/id "$@"
EOF
    chmod +x "${PARSER_BIN_DIR}/id" || skip "cannot chmod fake id"

    PFSRUN_CMD="${PARSER_BIN_DIR}/pfsrun"
    TEST_COMMAND_PATH="${PARSER_BIN_DIR}:${PATH}"
}

prepare_fake_pfsexec_capture_or_skip() {
    PFSRUN_CAPTURE_PATH="${TEST_ROOT}/pfsexec-capture.log"
    : >"${PFSRUN_CAPTURE_PATH}" || skip "cannot create pfsexec capture log"

    cat >"${PARSER_BIN_DIR}/pfsexec" <<'EOF' || skip "cannot create fake pfsexec"
#!/usr/bin/env bash
set -eu

capture_path="${PFSRUN_CAPTURE_PATH:?missing capture path}"
for arg in "$@"; do
    case "${arg}" in
        PFSRUN_EXPORT_XDG_DATA_HOME=*|PFSRUN_EXPORT_XDG_CACHE_HOME=*|PFSRUN_EXPORT_CACHE_ROOT=*)
            printf '%s\n' "${arg}" >>"${capture_path}"
            ;;
    esac
done
exit 0
EOF
    chmod +x "${PARSER_BIN_DIR}/pfsexec" || skip "cannot chmod fake pfsexec"
}

prepare_failing_realpath_wrapper_or_skip() {
    cat >"${PARSER_BIN_DIR}/realpath" <<'EOF' || skip "cannot create fake realpath"
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "${PARSER_BIN_DIR}/realpath" || skip "cannot chmod fake realpath"
}

prepare_runtime_wrapper_with_fake_refresh_tools_or_skip() {
    WRAPPED_BIN_DIR="${TEST_ROOT}/wrapped-bin"
    REFRESH_LOG_PATH="${TEST_ROOT}/refresh-tools.log"

    mkdir -p "${WRAPPED_BIN_DIR}" || skip "cannot create wrapped bin dir"

    local tool
    for tool in pfsrun pfsexec pfs; do
        cp "${PFSUTILS_BIN}/${tool}" "${WRAPPED_BIN_DIR}/${tool}" || skip "cannot copy ${tool}"
        chmod +x "${WRAPPED_BIN_DIR}/${tool}" || skip "cannot chmod ${tool}"
    done

    : >"${REFRESH_LOG_PATH}" || skip "cannot create refresh log"

    for tool in update-desktop-database gtk-update-icon-cache gtk4-update-icon-cache killall; do
        create_fake_refresh_tool_or_skip "${tool}"
    done

    PFSRUN_CMD="${WRAPPED_BIN_DIR}/pfsrun"
    TEST_COMMAND_PATH="${WRAPPED_BIN_DIR}:${PATH}"
}

create_fake_refresh_tool_or_skip() {
    local tool_name="$1"
    local tool_path="${WRAPPED_BIN_DIR}/${tool_name}"

    cat >"${tool_path}" <<'EOF' || skip "cannot create fake refresh tool"
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -n "${PFSRUN_EXPORT_TEST_LOG:-}" ]]; then
    printf '%s' "${0##*/}" >>"${PFSRUN_EXPORT_TEST_LOG}"
    for arg in "$@"; do
        printf ' %s' "${arg}" >>"${PFSRUN_EXPORT_TEST_LOG}"
    done
    printf '\n' >>"${PFSRUN_EXPORT_TEST_LOG}"
fi

if [[ "${0##*/}" == "${PFSRUN_EXPORT_FAIL_TOOL:-}" ]]; then
    exit 42
fi

exit 0
EOF

    chmod +x "${tool_path}" || skip "cannot chmod fake refresh tool ${tool_name}"
}

create_module_fixture_or_skip() {
    local module_id="$1"
    local module_root="${TEST_ROOT}/module-${module_id}"
    local payload_dir="${module_root}/payload"
    local module_path="${module_root}/${module_id}.pfs"
    local desktop_path="${payload_dir}/usr/share/applications/${module_id}.desktop"
    local icon_path="${payload_dir}/usr/share/icons/hicolor/48x48/apps/${module_id}.png"
    local scalable_icon_path="${payload_dir}/usr/share/icons/hicolor/scalable/apps/${module_id}.svg"
    local status_icon_path="${payload_dir}/usr/share/icons/hicolor/24x24/status/${module_id}-status.svg"
    local app_path="${payload_dir}/usr/bin/${module_id}"

    mkdir -p \
        "${payload_dir}/usr/share/applications" \
        "${payload_dir}/usr/share/icons/hicolor/48x48/apps" \
        "${payload_dir}/usr/share/icons/hicolor/scalable/apps" \
        "${payload_dir}/usr/share/icons/hicolor/24x24/status" \
        "${payload_dir}/usr/bin" \
        || skip "cannot create payload tree"

    cat >"${desktop_path}" <<EOF || skip "cannot write desktop fixture"
[Desktop Entry]
Type=Application
Name=${module_id}
Comment=PFS export test fixture
Exec=/usr/bin/${module_id} --demo
TryExec=/usr/bin/${module_id}
Icon=${module_id}
Terminal=false
Categories=Utility;
DBusActivatable=true
EOF

    printf 'icon-%s\n' "${module_id}" >"${icon_path}" || skip "cannot write icon fixture"
    printf '<svg><!-- scalable %s --></svg>\n' "${module_id}" >"${scalable_icon_path}" || skip "cannot write scalable icon fixture"
    printf '<svg><!-- status %s --></svg>\n' "${module_id}" >"${status_icon_path}" || skip "cannot write status icon fixture"

    cat >"${app_path}" <<'EOF' || skip "cannot write app fixture"
#!/usr/bin/env sh
exec /bin/true
EOF
    chmod +x "${app_path}" || skip "cannot chmod app fixture"

    mksquashfs "${payload_dir}" "${module_path}" -noappend >/dev/null 2>&1 || skip "mksquashfs failed"
    printf '%s\n' "${module_path}"
}

run_pfsrun_in_test_env() {
    run env \
        "HOME=${TEST_HOME}" \
        "XDG_DATA_HOME=${TEST_XDG_DATA_HOME}" \
        "XDG_CACHE_HOME=${TEST_XDG_CACHE_HOME}" \
        "XDG_CONFIG_HOME=${TEST_XDG_CONFIG_HOME}" \
        "PATH=${TEST_COMMAND_PATH}" \
        "$@"
}

start_registered_sleep_session() {
    local module_path="$1"
    local seconds="$2"
    local pid_var_name="$3"

    local log_path="${TEST_ROOT}/session-${pid_var_name}.log"
    : >"${log_path}" || skip "cannot create session log"

    env \
        "HOME=${TEST_HOME}" \
        "XDG_DATA_HOME=${TEST_XDG_DATA_HOME}" \
        "XDG_CACHE_HOME=${TEST_XDG_CACHE_HOME}" \
        "XDG_CONFIG_HOME=${TEST_XDG_CONFIG_HOME}" \
        "PATH=${TEST_COMMAND_PATH}" \
        "PFSRUN_EXPORT_TEST_LOG=${REFRESH_LOG_PATH:-}" \
        "${PFSRUN_CMD}" --register --no-gui --root --exec /bin/sleep "${module_path}" "${seconds}" \
        >"${log_path}" 2>&1 &

    printf -v "${pid_var_name}" '%s' "$!"
}

start_registered_non_root_sleep_session() {
    local module_path="$1"
    local seconds="$2"
    local pid_var_name="$3"

    if [[ -z "${SUDO_USER:-}" ]]; then
        skip "SUDO_USER required for non-root register path"
    fi

    local log_path="${TEST_ROOT}/session-${pid_var_name}.log"
    : >"${log_path}" || skip "cannot create session log"

    env \
        "HOME=${TEST_HOME}" \
        "XDG_DATA_HOME=${TEST_XDG_DATA_HOME}" \
        "XDG_CACHE_HOME=${TEST_XDG_CACHE_HOME}" \
        "XDG_CONFIG_HOME=${TEST_XDG_CONFIG_HOME}" \
        "PATH=${TEST_COMMAND_PATH}" \
        "PFSRUN_EXPORT_TEST_LOG=${REFRESH_LOG_PATH:-}" \
        "SUDO_USER=${SUDO_USER}" \
        "SUDO_UID=${SUDO_UID:-}" \
        "SUDO_GID=${SUDO_GID:-}" \
        "${PFSRUN_CMD}" --register --no-gui --exec /bin/sleep "${module_path}" "${seconds}" \
        >"${log_path}" 2>&1 &

    printf -v "${pid_var_name}" '%s' "$!"
}

process_is_running() {
    local pid="$1"
    kill -0 "${pid}" 2>/dev/null
}

process_is_not_running() {
    local pid="$1"
    ! process_is_running "${pid}"
}

wait_for_condition() {
    local max_attempts="$1"
    shift

    local attempt
    for ((attempt = 0; attempt < max_attempts; attempt++)); do
        if "$@"; then
            return 0
        fi
        sleep 0.1
    done

    return 1
}

wait_for_process_exit() {
    local pid="$1"
    wait_for_condition 120 process_is_not_running "${pid}"
}

terminate_background_session() {
    local pid="$1"

    if [[ -z "${pid}" ]]; then
        return 0
    fi

    if process_is_running "${pid}"; then
        kill -TERM "${pid}" 2>/dev/null || true
        wait_for_process_exit "${pid}" || kill -KILL "${pid}" 2>/dev/null || true
    fi

    wait "${pid}" 2>/dev/null || true
}

count_export_artifact_files() {
    find \
        "${TEST_APPLICATIONS_DIR}" \
        "${TEST_ICONS_BASE_DIR}" \
        "${TEST_PIXMAPS_DIR}" \
        "${TEST_EXPORTS_DIR}" \
        -type f 2>/dev/null | awk 'END { print NR + 0 }'
}

has_any_export_desktop_file() {
    find "${TEST_APPLICATIONS_DIR}" -maxdepth 1 -type f -name '*.desktop' -print -quit | grep -q .
}

has_any_export_icon_file() {
    find "${TEST_ICONS_BASE_DIR}" "${TEST_PIXMAPS_DIR}" -type f -print -quit 2>/dev/null | grep -q .
}

count_export_icon_files() {
    find "${TEST_ICONS_BASE_DIR}" "${TEST_PIXMAPS_DIR}" -type f 2>/dev/null | awk 'END { print NR + 0 }'
}

has_no_export_artifacts() {
    [[ "$(count_export_artifact_files)" -eq 0 ]]
}

module_path_is_present_in_exported_desktop() {
    local module_path="$1"
    local desktop_path

    shopt -s nullglob
    for desktop_path in "${TEST_APPLICATIONS_DIR}"/*.desktop; do
        if grep -Fq -- "${module_path}" "${desktop_path}"; then
            return 0
        fi
    done
    shopt -u nullglob

    return 1
}

assert_all_export_files_under_temp_xdg_roots() {
    local artifact_path
    while IFS= read -r artifact_path; do
        [[ "${artifact_path}" == "${TEST_XDG_DATA_HOME}/"* || "${artifact_path}" == "${TEST_XDG_CACHE_HOME}/"* ]] || return 1
    done < <(find "${TEST_XDG_DATA_HOME}" "${TEST_XDG_CACHE_HOME}" -type f 2>/dev/null)

    return 0
}

assert_real_home_not_touched_for_module() {
    local module_id="$1"

    [ ! -e "${REAL_HOME}/.local/share/applications/${module_id}.desktop" ]
    [ ! -e "${REAL_HOME}/.local/share/icons/hicolor/48x48/apps/${module_id}.png" ]
}

count_refresh_log_lines() {
    local line="$1"
    grep -cFx -- "${line}" "${REFRESH_LOG_PATH}" 2>/dev/null || true
}

assert_refresh_user_scope_calls_present() {
    local expected_desktop_call="update-desktop-database -q ${TEST_APPLICATIONS_DIR}"
    local expected_hicolor_call="gtk4-update-icon-cache -f -t -q ${TEST_ICONS_BASE_DIR}/hicolor"

    grep -qFx -- "${expected_desktop_call}" "${REFRESH_LOG_PATH}"
    grep -qFx -- "${expected_hicolor_call}" "${REFRESH_LOG_PATH}"
    grep -qFx -- 'killall -1 sfwbar' "${REFRESH_LOG_PATH}"
}

assert_refresh_never_targets_system_scope() {
    ! grep -qE -- '^update-desktop-database -q /usr/share/applications$' "${REFRESH_LOG_PATH}"
    ! grep -qE -- '^gtk4-update-icon-cache -f -t -q /usr/share/icons/hicolor$' "${REFRESH_LOG_PATH}"
    ! grep -qE -- '^gtk-update-icon-cache -f -t -q /usr/share/icons/hicolor$' "${REFRESH_LOG_PATH}"
}

assert_refresh_post_export_and_cleanup() {
    local desktop_calls
    local hicolor_calls
    local sfwbar_calls

    desktop_calls="$(count_refresh_log_lines "update-desktop-database -q ${TEST_APPLICATIONS_DIR}")"
    hicolor_calls="$(count_refresh_log_lines "gtk4-update-icon-cache -f -t -q ${TEST_ICONS_BASE_DIR}/hicolor")"
    sfwbar_calls="$(count_refresh_log_lines 'killall -1 sfwbar')"

    [ "${desktop_calls}" -ge 2 ]
    [ "${hicolor_calls}" -ge 2 ]
    [ "${sfwbar_calls}" -ge 2 ]
}

assert_exported_desktop_sanitized() {
    local desktop_path
    shopt -s nullglob
    for desktop_path in "${TEST_APPLICATIONS_DIR}"/*.desktop; do
        [ -f "${desktop_path}" ] || continue
        ! grep -q '^TryExec=' "${desktop_path}"
        ! grep -q '^DBusActivatable=true$' "${desktop_path}"
        grep -q '^DBusActivatable=false$' "${desktop_path}"
    done
    shopt -u nullglob
}

assert_captured_forwarded_xdg_paths_are_not_system_scope() {
    local captured_data_home
    local captured_cache_home
    local captured_cache_root

    captured_data_home="$(grep '^PFSRUN_EXPORT_XDG_DATA_HOME=' "${PFSRUN_CAPTURE_PATH}" | tail -n1 | sed 's/^PFSRUN_EXPORT_XDG_DATA_HOME=//')"
    captured_cache_home="$(grep '^PFSRUN_EXPORT_XDG_CACHE_HOME=' "${PFSRUN_CAPTURE_PATH}" | tail -n1 | sed 's/^PFSRUN_EXPORT_XDG_CACHE_HOME=//')"
    captured_cache_root="$(grep '^PFSRUN_EXPORT_CACHE_ROOT=' "${PFSRUN_CAPTURE_PATH}" | tail -n1 | sed 's/^PFSRUN_EXPORT_CACHE_ROOT=//')"

    [ -n "${captured_data_home}" ]
    [ -n "${captured_cache_home}" ]
    [ -n "${captured_cache_root}" ]

    [[ "${captured_data_home}" != /usr/* ]]
    [[ "${captured_data_home}" != /etc* ]]
    [[ "${captured_data_home}" != /var* ]]
    [[ "${captured_data_home}" != /opt* ]]
    [[ "${captured_data_home}" != / ]]

    [[ "${captured_cache_home}" != /usr/* ]]
    [[ "${captured_cache_home}" != /etc* ]]
    [[ "${captured_cache_home}" != /var* ]]
    [[ "${captured_cache_home}" != /opt* ]]
    [[ "${captured_cache_home}" != / ]]

    [[ "${captured_cache_root}" != /usr/* ]]
    [[ "${captured_cache_root}" != /etc* ]]
    [[ "${captured_cache_root}" != /var* ]]
    [[ "${captured_cache_root}" != /opt* ]]
    [[ "${captured_cache_root}" != / ]]
    [[ "${captured_data_home}" != *"/../"* ]]
    [[ "${captured_cache_home}" != *"/../"* ]]
    [[ "${captured_cache_root}" != *"/../"* ]]
    [[ "${captured_cache_root}" == "${captured_cache_home%/}/pfsrun/exports" ]]
}

pfsrun_help_lists_register_and_unregister_options() { #@test
    prepare_temp_xdg_env
    prepare_fake_root_parser_wrapper_or_skip

    run_pfsrun_in_test_env "${PFSRUN_CMD}" --help

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"--register"* ]]
    [[ "${output}" == *"--unregister"* ]]
}

pfsrun_unregister_all_is_idempotent() { #@test
    prepare_temp_xdg_env
    prepare_fake_root_parser_wrapper_or_skip

    run_pfsrun_in_test_env "${PFSRUN_CMD}" --unregister --all
    [ "${status}" -eq 0 ]

    run_pfsrun_in_test_env "${PFSRUN_CMD}" --unregister --all
    [ "${status}" -eq 0 ]
}

pfsrun_unregister_module_is_idempotent() { #@test
    prepare_temp_xdg_env
    prepare_fake_root_parser_wrapper_or_skip

    local module_path="${TEST_ROOT}/missing-module.pfs"

    run_pfsrun_in_test_env "${PFSRUN_CMD}" --unregister "${module_path}"
    [ "${status}" -eq 0 ]

    run_pfsrun_in_test_env "${PFSRUN_CMD}" --unregister "${module_path}"
    [ "${status}" -eq 0 ]
}

pfsrun_unregister_module_removes_stale_exports_without_manifest() { #@test
    require_pfsrun_export_runtime_or_skip
    prepare_temp_xdg_env
    prepare_runtime_wrapper_with_fake_refresh_tools_or_skip

    cat >"${WRAPPED_BIN_DIR}/getent" <<EOF || skip "cannot create fake getent"
#!/usr/bin/env bash
if [[ "\${1:-}" == "passwd" && "\${2:-}" == "testuser" ]]; then
    printf 'testuser:x:1000:1000::%s:/bin/sh\n' '${TEST_HOME}'
    exit 0
fi
exec /usr/bin/getent "\$@"
EOF
    chmod +x "${WRAPPED_BIN_DIR}/getent" || skip "cannot chmod fake getent"

    local module_id="pfsrun-export-stale-${BATS_TEST_NUMBER}"
    local module_path
    module_path="$(create_module_fixture_or_skip "${module_id}")"

    local desktop_export="${TEST_APPLICATIONS_DIR}/${module_id}.desktop"
    local icon_export="${TEST_ICONS_BASE_DIR}/hicolor/48x48/apps/${module_id}.png"
    local scalable_export="${TEST_ICONS_BASE_DIR}/hicolor/scalable/apps/${module_id}.svg"
    local status_export="${TEST_ICONS_BASE_DIR}/hicolor/24x24/status/${module_id}-status.svg"
    local unrelated_action="${TEST_ICONS_BASE_DIR}/hicolor/scalable/actions/${module_id}-camera-photo-symbolic.svg"

    mkdir -p \
        "$(dirname "${desktop_export}")" \
        "$(dirname "${icon_export}")" \
        "$(dirname "${scalable_export}")" \
        "$(dirname "${status_export}")" \
        "$(dirname "${unrelated_action}")" \
        || skip "cannot create stale export tree"

    {
        printf '[Desktop Entry]\n'
        printf 'Type=Application\n'
        printf 'Name=%s\n' "${module_id}"
        printf 'Exec=pfsrun %s /usr/bin/%s\n' "${module_path}" "${module_id}"
        printf 'Icon=%s\n' "${module_id}"
    } >"${desktop_export}" || skip "cannot write stale desktop export"
    printf 'icon\n' >"${icon_export}" || skip "cannot write stale icon export"
    printf '<svg/>\n' >"${scalable_export}" || skip "cannot write stale scalable export"
    printf '<svg/>\n' >"${status_export}" || skip "cannot write stale status export"
    printf '<svg/>\n' >"${unrelated_action}" || skip "cannot write unrelated action icon"

    run env \
        "HOME=${TEST_HOME}" \
        "SUDO_USER=" \
        "USER=testuser" \
        "XDG_DATA_HOME=${TEST_XDG_DATA_HOME}" \
        "XDG_CACHE_HOME=${TEST_XDG_CACHE_HOME}" \
        "XDG_CONFIG_HOME=${TEST_XDG_CONFIG_HOME}" \
        "PATH=${TEST_COMMAND_PATH}" \
        "PFSRUN_EXPORT_TEST_LOG=${REFRESH_LOG_PATH}" \
        "${PFSRUN_CMD}" --unregister "${module_path}"

    [ "${status}" -eq 0 ]
    [ ! -e "${desktop_export}" ]
    [ ! -e "${icon_export}" ]
    [ ! -e "${scalable_export}" ]
    [ ! -e "${status_export}" ]
    [ -f "${unrelated_action}" ]
}

pfsrun_unregister_all_ignores_malicious_manifest_paths() { #@test
    prepare_temp_xdg_env
    prepare_fake_root_parser_wrapper_or_skip

    local outside_sentinel="${BATS_TEST_TMPDIR}/outside-sentinel"
    local sibling_victim="${TEST_XDG_DATA_HOME}/victim"
    printf 'keep-me\n' >"${outside_sentinel}"
    printf 'keep-me-too\n' >"${sibling_victim}"

    {
        printf 'session\t%s\n' 'fake-session'
        printf 'module\t%s\n' "${TEST_ROOT}/fake-module.pfs"
        printf 'file\t%s\n' "${outside_sentinel}"
        printf 'file\t%s\n' "${TEST_APPLICATIONS_DIR}/../victim"
        printf 'created\t%s\n' '0'
    } >"${TEST_EXPORTS_DIR}/malicious.manifest"

    run_pfsrun_in_test_env "${PFSRUN_CMD}" --unregister --all

    [ "${status}" -eq 0 ]
    [ -f "${outside_sentinel}" ]
    [ -f "${sibling_victim}" ]
}

pfsrun_register_does_not_forward_system_scoped_xdg_roots() { #@test
    prepare_temp_xdg_env
    prepare_fake_root_parser_wrapper_or_skip
    prepare_fake_pfsexec_capture_or_skip
    prepare_failing_realpath_wrapper_or_skip

    local module_path="${TEST_ROOT}/parser-module.pfs"
    : >"${module_path}" || skip "cannot create parser module path"

    run env \
        "HOME=${TEST_HOME}" \
        "XDG_DATA_HOME=/tmp/../usr/share" \
        "XDG_CACHE_HOME=/tmp/../var/cache" \
        "XDG_CONFIG_HOME=${TEST_XDG_CONFIG_HOME}" \
        "PFSRUN_CAPTURE_PATH=${PFSRUN_CAPTURE_PATH}" \
        "PATH=${TEST_COMMAND_PATH}" \
        "${PFSRUN_CMD}" --register --no-gui --root --exec /bin/true "${module_path}"

    [ "${status}" -eq 0 ]
    assert_captured_forwarded_xdg_paths_are_not_system_scope

    run env \
        "HOME=${TEST_HOME}" \
        "XDG_DATA_HOME=usr/share" \
        "XDG_CACHE_HOME=var/cache" \
        "XDG_CONFIG_HOME=${TEST_XDG_CONFIG_HOME}" \
        "PFSRUN_CAPTURE_PATH=${PFSRUN_CAPTURE_PATH}" \
        "PATH=${TEST_COMMAND_PATH}" \
        "${PFSRUN_CMD}" --register --no-gui --root --exec /bin/true "${module_path}"

    [ "${status}" -eq 0 ]
    assert_captured_forwarded_xdg_paths_are_not_system_scope
}

pfsrun_register_exports_during_child_run() { #@test
    require_pfsrun_export_runtime_or_skip
    prepare_temp_xdg_env
    prepare_runtime_wrapper_with_fake_refresh_tools_or_skip

    local module_id="pfsrun-export-live-${BATS_TEST_NUMBER}"
    local module_path
    module_path="$(create_module_fixture_or_skip "${module_id}")"

    start_registered_sleep_session "${module_path}" "30" "SESSION_PID"

    wait_for_condition 120 has_any_export_desktop_file
    wait_for_condition 120 has_any_export_icon_file
    [ "$(count_export_icon_files)" -ge 3 ]
    process_is_running "${SESSION_PID}"
    module_path_is_present_in_exported_desktop "${module_path}"
    assert_all_export_files_under_temp_xdg_roots
    assert_real_home_not_touched_for_module "${module_id}"
}

pfsrun_register_exports_with_non_root_runuser_wrapper() { #@test
    require_pfsrun_export_runtime_or_skip
    prepare_temp_xdg_env
    prepare_runtime_wrapper_with_fake_refresh_tools_or_skip

    local module_id="org.example.pfsrun.export.runuser.${BATS_TEST_NUMBER}"
    local module_path
    module_path="$(create_module_fixture_or_skip "${module_id}")"

    start_registered_non_root_sleep_session "${module_path}" "30" "SESSION_PID"

    wait_for_condition 120 has_any_export_desktop_file
    wait_for_condition 120 has_any_export_icon_file
    process_is_running "${SESSION_PID}"
    module_path_is_present_in_exported_desktop "${module_path}"
    assert_all_export_files_under_temp_xdg_roots

    kill -TERM "${SESSION_PID}"
    wait_for_process_exit "${SESSION_PID}"
    wait "${SESSION_PID}" || true
    wait_for_condition 120 has_no_export_artifacts
}

pfsrun_register_cleans_export_on_normal_exit() { #@test
    require_pfsrun_export_runtime_or_skip
    prepare_temp_xdg_env
    prepare_runtime_wrapper_with_fake_refresh_tools_or_skip

    local module_id="pfsrun-export-normal-${BATS_TEST_NUMBER}"
    local module_path
    module_path="$(create_module_fixture_or_skip "${module_id}")"

    run_pfsrun_in_test_env "${PFSRUN_CMD}" --register --no-gui --root --exec /bin/sleep "${module_path}" 1

    [ "${status}" -eq 0 ]
    wait_for_condition 120 has_no_export_artifacts
    assert_real_home_not_touched_for_module "${module_id}"
    assert_refresh_user_scope_calls_present
    assert_refresh_never_targets_system_scope
    assert_refresh_post_export_and_cleanup
    assert_exported_desktop_sanitized
}

pfsrun_register_cleans_export_on_term() { #@test
    require_pfsrun_export_runtime_or_skip
    prepare_temp_xdg_env
    prepare_runtime_wrapper_with_fake_refresh_tools_or_skip

    local module_id="pfsrun-export-term-${BATS_TEST_NUMBER}"
    local module_path
    module_path="$(create_module_fixture_or_skip "${module_id}")"

    start_registered_sleep_session "${module_path}" "60" "SESSION_PID"

    wait_for_condition 120 has_any_export_desktop_file
    kill -TERM "${SESSION_PID}"
    wait_for_process_exit "${SESSION_PID}"
    wait "${SESSION_PID}" || true
    wait_for_condition 120 has_no_export_artifacts
    assert_real_home_not_touched_for_module "${module_id}"
}

pfsrun_register_cleans_export_on_int() { #@test
    require_pfsrun_export_runtime_or_skip
    prepare_temp_xdg_env
    prepare_runtime_wrapper_with_fake_refresh_tools_or_skip

    local module_id="pfsrun-export-int-${BATS_TEST_NUMBER}"
    local module_path
    module_path="$(create_module_fixture_or_skip "${module_id}")"

    start_registered_sleep_session "${module_path}" "60" "SESSION_PID"

    wait_for_condition 120 has_any_export_desktop_file
    kill -INT "${SESSION_PID}"
    wait_for_process_exit "${SESSION_PID}"
    wait "${SESSION_PID}" || true
    wait_for_condition 120 has_no_export_artifacts
    assert_real_home_not_touched_for_module "${module_id}"
}

pfsrun_register_does_not_overwrite_or_delete_preexisting_files() { #@test
    require_pfsrun_export_runtime_or_skip
    prepare_temp_xdg_env
    prepare_runtime_wrapper_with_fake_refresh_tools_or_skip

    local module_id="pfsrun-export-preexisting-${BATS_TEST_NUMBER}"
    local module_path
    module_path="$(create_module_fixture_or_skip "${module_id}")"

    local existing_desktop="${TEST_APPLICATIONS_DIR}/${module_id}.desktop"
    local existing_icon="${TEST_ICON_APPS_DIR}/${module_id}.png"

    printf 'preexisting-desktop\n' >"${existing_desktop}"
    printf 'preexisting-icon\n' >"${existing_icon}"

    start_registered_sleep_session "${module_path}" "20" "SESSION_PID"

    wait_for_condition 120 module_path_is_present_in_exported_desktop "${module_path}"
    grep -Fxq 'preexisting-desktop' "${existing_desktop}"
    grep -Fxq 'preexisting-icon' "${existing_icon}"

    kill -TERM "${SESSION_PID}"
    wait_for_process_exit "${SESSION_PID}"
    wait "${SESSION_PID}" || true

    [ -f "${existing_desktop}" ]
    [ -f "${existing_icon}" ]
    grep -Fxq 'preexisting-desktop' "${existing_desktop}"
    grep -Fxq 'preexisting-icon' "${existing_icon}"
}

pfsrun_register_simultaneous_sessions_stay_isolated() { #@test
    require_pfsrun_export_runtime_or_skip
    prepare_temp_xdg_env
    prepare_runtime_wrapper_with_fake_refresh_tools_or_skip

    local module_one_id="pfsrun-export-s1-${BATS_TEST_NUMBER}"
    local module_two_id="pfsrun-export-s2-${BATS_TEST_NUMBER}"
    local module_one_path
    local module_two_path

    module_one_path="$(create_module_fixture_or_skip "${module_one_id}")"
    module_two_path="$(create_module_fixture_or_skip "${module_two_id}")"

    start_registered_sleep_session "${module_one_path}" "60" "SESSION_PID"
    start_registered_sleep_session "${module_two_path}" "60" "SESSION_TWO_PID"

    wait_for_condition 120 module_path_is_present_in_exported_desktop "${module_one_path}"
    wait_for_condition 120 module_path_is_present_in_exported_desktop "${module_two_path}"

    kill -TERM "${SESSION_PID}"
    wait_for_process_exit "${SESSION_PID}"
    wait "${SESSION_PID}" || true

    process_is_running "${SESSION_TWO_PID}"
    module_path_is_present_in_exported_desktop "${module_two_path}"

    kill -TERM "${SESSION_TWO_PID}"
    wait_for_process_exit "${SESSION_TWO_PID}"
    wait "${SESSION_TWO_PID}" || true
    wait_for_condition 120 has_no_export_artifacts
}

pfsrun_register_refresh_tool_failure_is_non_fatal() { #@test
    require_pfsrun_export_runtime_or_skip
    prepare_temp_xdg_env
    prepare_runtime_wrapper_with_fake_refresh_tools_or_skip

    local module_id="pfsrun-export-refresh-${BATS_TEST_NUMBER}"
    local module_path
    module_path="$(create_module_fixture_or_skip "${module_id}")"

    run env \
        "HOME=${TEST_HOME}" \
        "XDG_DATA_HOME=${TEST_XDG_DATA_HOME}" \
        "XDG_CACHE_HOME=${TEST_XDG_CACHE_HOME}" \
        "XDG_CONFIG_HOME=${TEST_XDG_CONFIG_HOME}" \
        "PATH=${TEST_COMMAND_PATH}" \
        "PFSRUN_EXPORT_TEST_LOG=${REFRESH_LOG_PATH}" \
        "PFSRUN_EXPORT_FAIL_TOOL=update-desktop-database" \
        "${PFSRUN_CMD}" --register --no-gui --root --exec /bin/true "${module_path}"

    [ "${status}" -eq 0 ]
    wait_for_condition 120 has_no_export_artifacts
    assert_refresh_user_scope_calls_present
    assert_refresh_never_targets_system_scope
    assert_refresh_post_export_and_cleanup

    : >"${REFRESH_LOG_PATH}" || skip "cannot reset refresh log"

    run env \
        "HOME=${TEST_HOME}" \
        "XDG_DATA_HOME=${TEST_XDG_DATA_HOME}" \
        "XDG_CACHE_HOME=${TEST_XDG_CACHE_HOME}" \
        "XDG_CONFIG_HOME=${TEST_XDG_CONFIG_HOME}" \
        "PATH=${TEST_COMMAND_PATH}" \
        "PFSRUN_EXPORT_TEST_LOG=${REFRESH_LOG_PATH}" \
        "PFSRUN_EXPORT_FAIL_TOOL=update-desktop-database" \
        "${PFSRUN_CMD}" --register --no-gui --root --exec /bin/false "${module_path}"

    [ "${status}" -eq 1 ]
    wait_for_condition 120 has_no_export_artifacts
    assert_refresh_user_scope_calls_present
    assert_refresh_never_targets_system_scope
    assert_refresh_post_export_and_cleanup
}

pfsrun_without_register_leaves_no_export_artifacts() { #@test
    require_pfsrun_export_runtime_or_skip
    prepare_temp_xdg_env
    prepare_runtime_wrapper_with_fake_refresh_tools_or_skip

    local module_id="pfsrun-export-none-${BATS_TEST_NUMBER}"
    local module_path
    module_path="$(create_module_fixture_or_skip "${module_id}")"

    run_pfsrun_in_test_env "${PFSRUN_CMD}" --no-gui --root --exec /bin/true "${module_path}"

    [ "${status}" -eq 0 ]
    has_no_export_artifacts
    assert_real_home_not_touched_for_module "${module_id}"
}
