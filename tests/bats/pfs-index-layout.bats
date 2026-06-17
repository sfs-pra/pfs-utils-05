#!/usr/bin/env bats

load "helpers.bash"

setup() {
    prepare_mount_index_fixture_root_or_skip
}

prepare_mount_index_fixture_root_or_skip() {
    TEST_FIXTURE_ROOT="${BATS_TEST_TMPDIR}/pfs-index-layout-${BATS_TEST_NUMBER}-$$"
    TEST_PFSDIR_MOUNT_NEW="${TEST_FIXTURE_ROOT}/var/lib/pfs/mount"
    TEST_PFSDIR_MOUNT_LEGACY="${TEST_FIXTURE_ROOT}/etc/packages/mount"

    mkdir -p "${TEST_PFSDIR_MOUNT_NEW}" "${TEST_PFSDIR_MOUNT_LEGACY}" || skip "cannot create fixture roots"
}

assert_fixture_paths_are_temp_root_namespaced() {
    [[ "${TEST_PFSDIR_MOUNT_NEW}" != "/var/lib/pfs/mount" ]]
    [[ "${TEST_PFSDIR_MOUNT_LEGACY}" != "/etc/packages/mount" ]]
    [[ "${TEST_PFSDIR_MOUNT_NEW}" == "${TEST_FIXTURE_ROOT}"/* ]]
    [[ "${TEST_PFSDIR_MOUNT_LEGACY}" == "${TEST_FIXTURE_ROOT}"/* ]]
}

write_mount_index_files_or_skip() {
    local index_dir="$1"
    local marker="$2"

    mkdir -p "${index_dir}" || skip "cannot create mount-index dir"
    printf '/usr/lib/%s.so\n' "${marker}" >"${index_dir}/pfs.files" || skip "cannot write pfs.files"
    printf '/var/empty/%s\n' "${marker}" >"${index_dir}/pfs.dirs.empty" || skip "cannot write pfs.dirs.empty"
    printf 'spec:%s\n' "${marker}" >"${index_dir}/pfs.specs" || skip "cannot write pfs.specs"
}

create_canonical_mount_index_fixture_or_skip() {
    TEST_CANONICAL_INDEX_DIR="${TEST_PFSDIR_MOUNT_NEW}/container-a/common"
    write_mount_index_files_or_skip "${TEST_CANONICAL_INDEX_DIR}" "container-a-common"
}

create_legacy_mount_index_fixture_or_skip() {
    TEST_LEGACY_INDEX_DIR="${TEST_PFSDIR_MOUNT_LEGACY}/common"
    write_mount_index_files_or_skip "${TEST_LEGACY_INDEX_DIR}" "legacy-common"
}

create_mixed_mount_index_fixture_or_skip() {
    TEST_MIXED_CANONICAL_INDEX_DIR="${TEST_PFSDIR_MOUNT_NEW}/container-a/common"
    TEST_MIXED_LEGACY_INDEX_DIR="${TEST_PFSDIR_MOUNT_LEGACY}/common"

    write_mount_index_files_or_skip "${TEST_MIXED_CANONICAL_INDEX_DIR}" "mixed-container-a-common"
    write_mount_index_files_or_skip "${TEST_MIXED_LEGACY_INDEX_DIR}" "mixed-legacy-common"
}

create_duplicate_mount_index_fixture_or_skip() {
    TEST_DUPLICATE_INDEX_DIR_A="${TEST_PFSDIR_MOUNT_NEW}/container-a/common"
    TEST_DUPLICATE_INDEX_DIR_B="${TEST_PFSDIR_MOUNT_NEW}/container-b/common"

    write_mount_index_files_or_skip "${TEST_DUPLICATE_INDEX_DIR_A}" "container-a-common"
    write_mount_index_files_or_skip "${TEST_DUPLICATE_INDEX_DIR_B}" "container-b-common"
}

create_executable_stub_or_skip() {
    local target="$1"
    local body="$2"

    mkdir -p "$(dirname "${target}")" || skip "cannot create stub dir"
    printf '%s\n' "${body}" >"${target}" || skip "cannot write stub ${target}"
    chmod +x "${target}" || skip "cannot chmod stub ${target}"
}

canonical_mount_index_fixture_creates_container_a_common_tree() { #@test
    assert_fixture_paths_are_temp_root_namespaced

    create_canonical_mount_index_fixture_or_skip

    [ -f "${TEST_CANONICAL_INDEX_DIR}/pfs.files" ]
    [ -f "${TEST_CANONICAL_INDEX_DIR}/pfs.dirs.empty" ]
    [ -f "${TEST_CANONICAL_INDEX_DIR}/pfs.specs" ]
}

legacy_mount_index_fixture_creates_common_tree() { #@test
    assert_fixture_paths_are_temp_root_namespaced

    create_legacy_mount_index_fixture_or_skip

    [ -f "${TEST_LEGACY_INDEX_DIR}/pfs.files" ]
    [ -f "${TEST_LEGACY_INDEX_DIR}/pfs.dirs.empty" ]
    [ -f "${TEST_LEGACY_INDEX_DIR}/pfs.specs" ]
}

mixed_mount_index_fixture_creates_canonical_and_legacy_common() { #@test
    assert_fixture_paths_are_temp_root_namespaced

    create_mixed_mount_index_fixture_or_skip

    [ -f "${TEST_MIXED_CANONICAL_INDEX_DIR}/pfs.files" ]
    [ -f "${TEST_MIXED_CANONICAL_INDEX_DIR}/pfs.dirs.empty" ]
    [ -f "${TEST_MIXED_CANONICAL_INDEX_DIR}/pfs.specs" ]
    [ -f "${TEST_MIXED_LEGACY_INDEX_DIR}/pfs.files" ]
    [ -f "${TEST_MIXED_LEGACY_INDEX_DIR}/pfs.dirs.empty" ]
    [ -f "${TEST_MIXED_LEGACY_INDEX_DIR}/pfs.specs" ]
}

duplicate_mount_index_fixture_creates_distinct_canonical_identities() { #@test
    assert_fixture_paths_are_temp_root_namespaced

    create_duplicate_mount_index_fixture_or_skip

    [ -f "${TEST_DUPLICATE_INDEX_DIR_A}/pfs.files" ]
    [ -f "${TEST_DUPLICATE_INDEX_DIR_A}/pfs.dirs.empty" ]
    [ -f "${TEST_DUPLICATE_INDEX_DIR_A}/pfs.specs" ]
    [ -f "${TEST_DUPLICATE_INDEX_DIR_B}/pfs.files" ]
    [ -f "${TEST_DUPLICATE_INDEX_DIR_B}/pfs.dirs.empty" ]
    [ -f "${TEST_DUPLICATE_INDEX_DIR_B}/pfs.specs" ]

    run cat "${TEST_DUPLICATE_INDEX_DIR_A}/pfs.files"
    [ "${status}" -eq 0 ]
    [ "${output}" = "/usr/lib/container-a-common.so" ]

    run cat "${TEST_DUPLICATE_INDEX_DIR_B}/pfs.files"
    [ "${status}" -eq 0 ]
    [ "${output}" = "/usr/lib/container-b-common.so" ]
}

fixture_helpers_never_write_to_host_roots() { #@test
    assert_fixture_paths_are_temp_root_namespaced

    create_canonical_mount_index_fixture_or_skip
    create_legacy_mount_index_fixture_or_skip

    [ "${TEST_CANONICAL_INDEX_DIR}" != "/var/lib/pfs/mount/container-a/common" ]
    [ "${TEST_LEGACY_INDEX_DIR}" != "/etc/packages/mount/common" ]
    [[ "${TEST_CANONICAL_INDEX_DIR}" == "${TEST_FIXTURE_ROOT}"/* ]]
    [[ "${TEST_LEGACY_INDEX_DIR}" == "${TEST_FIXTURE_ROOT}"/* ]]
}

helper_component_encode_rejects_invalid_names() { #@test
    assert_fixture_paths_are_temp_root_namespaced

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" bash -c '. "$1"; pfsdir_mount_component_encode "module-1.2_3+4"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    [ "${status}" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "module-1.2_3+4" ]

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" bash -c '. "$1"; pfsdir_mount_component_encode ""' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    [ "${status}" -ne 0 ]

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" bash -c '. "$1"; pfsdir_mount_component_encode "a/b"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    [ "${status}" -ne 0 ]

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" bash -c '. "$1"; pfsdir_mount_component_encode "bad:name"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    [ "${status}" -ne 0 ]

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" bash -c '. "$1"; pfsdir_mount_component_encode "bad name"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    [ "${status}" -ne 0 ]

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" bash -c '. "$1"; pfsdir_mount_component_encode "bad,name"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    [ "${status}" -ne 0 ]
}

helper_mount_paths_and_container_from_output() { #@test
    assert_fixture_paths_are_temp_root_namespaced

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" bash -c '. "$1"; pfsdir_mount_new_dir "container-a" "common"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    [ "${status}" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "${TEST_PFSDIR_MOUNT_NEW}/container-a/common" ]

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" bash -c '. "$1"; pfsdir_mount_legacy_dir "common"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    [ "${status}" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "${TEST_PFSDIR_MOUNT_LEGACY}/common" ]

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" bash -c '. "$1"; pfsdir_mount_container_from_output "/tmp/container-a.pfs"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    [ "${status}" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "container-a" ]
}

helper_iter_indexes_emits_expected_rows() { #@test
    assert_fixture_paths_are_temp_root_namespaced
    create_mixed_mount_index_fixture_or_skip

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" bash -c '. "$1"; pfsdir_mount_iter_indexes' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"container-a	common	${TEST_MIXED_CANONICAL_INDEX_DIR}	new"* ]]
    [[ "${output}" == *"	common	${TEST_MIXED_LEGACY_INDEX_DIR}	legacy"* ]]
}

qualified_lookup_returns_only_matching_canonical_directory() { #@test
    assert_fixture_paths_are_temp_root_namespaced
    create_duplicate_mount_index_fixture_or_skip

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" bash -c '. "$1"; pfsdir_mount_find "container-a:common"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    [ "${status}" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "${TEST_DUPLICATE_INDEX_DIR_A}" ]
}

conflict_lookup_unqualified_duplicate_is_deterministic() { #@test
    assert_fixture_paths_are_temp_root_namespaced
    create_duplicate_mount_index_fixture_or_skip

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" bash -c '. "$1"; pfsdir_mount_find "common"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"ambiguous submodule \"common\""* ]]
}

mklist_writes_canonical_namespaced_indexes_without_legacy_mirror_by_default() { #@test
    local source_dir dest_dir canonical_dir legacy_dir flat_dir

    source_dir="${TEST_FIXTURE_ROOT}/src"
    dest_dir="${TEST_FIXTURE_ROOT}/dest"
    canonical_dir="${dest_dir}/var/lib/pfs/mount/container-a/common"
    legacy_dir="${dest_dir}/etc/packages/mount/common"
    flat_dir="${dest_dir}/var/lib/pfs/mount/common"

    mkdir -p "${source_dir}/usr/bin" "${source_dir}/opt/empty-dir" "${dest_dir}"
    printf 'payload\n' > "${source_dir}/usr/bin/demo"

    run env PFSDIR_MOUNT_NEW="/var/lib/pfs/mount" PFSDIR_MOUNT_LEGACY="/etc/packages/mount" EXT="pfs" bash -c '. "$1"; mklist "$2" "$3" "$4" "$5"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs" "${source_dir}" "${dest_dir}" "common" "container-a"
    [ "${status}" -eq 0 ]

    [ -f "${canonical_dir}/pfs.files" ]
    [ -f "${canonical_dir}/pfs.dirs.empty" ]
    [ -f "${canonical_dir}/pfs.specs" ]
    [ ! -e "${legacy_dir}/pfs.files" ]
    [ ! -e "${legacy_dir}/pfs.dirs.empty" ]
    [ ! -e "${legacy_dir}/pfs.specs" ]
    [ ! -e "${flat_dir}/pfs.files" ]
}

mklist_can_write_legacy_mirror_when_explicitly_requested() { #@test
    local source_dir dest_dir canonical_dir legacy_dir

    source_dir="${TEST_FIXTURE_ROOT}/src-mirror"
    dest_dir="${TEST_FIXTURE_ROOT}/dest-mirror"
    canonical_dir="${dest_dir}/var/lib/pfs/mount/container-a/common"
    legacy_dir="${dest_dir}/etc/packages/mount/common"

    mkdir -p "${source_dir}/usr/bin" "${dest_dir}"
    printf 'payload\n' > "${source_dir}/usr/bin/demo"

    run env PFS_MKLIST_WRITE_LEGACY_MIRROR="1" PFSDIR_MOUNT_NEW="/var/lib/pfs/mount" PFSDIR_MOUNT_LEGACY="/etc/packages/mount" EXT="pfs" bash -c '. "$1"; mklist "$2" "$3" "$4" "$5"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs" "${source_dir}" "${dest_dir}" "common" "container-a"
    [ "${status}" -eq 0 ]

    [ -f "${canonical_dir}/pfs.files" ]
    [ -f "${legacy_dir}/pfs.files" ]

    run cmp "${canonical_dir}/pfs.files" "${legacy_dir}/pfs.files"
    [ "${status}" -eq 0 ]
}

mklist_defaults_container_name_to_pack_name_for_old_call_shape() { #@test
    local source_dir dest_dir

    source_dir="${TEST_FIXTURE_ROOT}/src-default"
    dest_dir="${TEST_FIXTURE_ROOT}/dest-default"

    mkdir -p "${source_dir}/usr/share" "${dest_dir}"
    printf 'readme\n' > "${source_dir}/usr/share/readme.txt"

    run env PFSDIR_MOUNT_NEW="/var/lib/pfs/mount" PFSDIR_MOUNT_LEGACY="/etc/packages/mount" EXT="pfs" bash -c '. "$1"; mklist "$2" "$3" "$4"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs" "${source_dir}" "${dest_dir}" "compat-pack"
    [ "${status}" -eq 0 ]

    [ -f "${dest_dir}/var/lib/pfs/mount/compat-pack/compat-pack/pfs.files" ]
    [ ! -e "${dest_dir}/etc/packages/mount/compat-pack/pfs.files" ]
}

mkpfs_d_single_submodule_writes_container_scoped_canonical_index() { #@test
    local parent_dir submodule_dir output_dir test_bin canonical_dir legacy_dir

    parent_dir="${TEST_FIXTURE_ROOT}/mkpfs-d-src"
    submodule_dir="${parent_dir}/common"
    output_dir="${TEST_FIXTURE_ROOT}/container-a.pfs"
    test_bin="${TEST_FIXTURE_ROOT}/bin"
    canonical_dir="${output_dir}/var/lib/pfs/mount/container-a/common"
    legacy_dir="${output_dir}/etc/packages/mount/common"

    mkdir -p "${submodule_dir}/usr/bin" "${test_bin}" || skip "cannot create mkpfs -d fixture"
    printf 'payload\n' > "${submodule_dir}/usr/bin/demo" || skip "cannot write mkpfs -d payload"
    cat > "${test_bin}/mksquashfs" <<'STUB'
#!/bin/sh
src="$1"
dst="$2"
rm -rf "$dst" || exit 1
mkdir -p "$dst" || exit 1
cp -a "$src"/. "$dst"/ || exit 1
STUB
    chmod +x "${test_bin}/mksquashfs" || skip "cannot create mksquashfs stub"

    run env PATH="${test_bin}:${PFSUTILS_BIN}:$PATH" PFSDIR_MOUNT_NEW="/var/lib/pfs/mount" PFSDIR_MOUNT_LEGACY="/etc/packages/mount" EXT="pfs" sh "${PFSUTILS_BIN}/mkpfs" -l --mklist -d "${parent_dir}" -o "${output_dir}"
    [ "${status}" -eq 0 ]

    [ -f "${canonical_dir}/pfs.files" ]
    [ -f "${canonical_dir}/pfs.dirs.empty" ]
    [ -f "${canonical_dir}/pfs.specs" ]
    [ ! -e "${output_dir}/var/lib/pfs/mount/common/pfs.files" ]
    [ ! -e "${legacy_dir}/pfs.files" ]
    run grep -Fx "/usr/bin/demo" "${canonical_dir}/pfs.files"
    [ "${status}" -eq 0 ]
}

mklist_excludes_legacy_and_canonical_metadata_from_payload() { #@test
    local source_dir dest_dir canonical_dir

    source_dir="${TEST_FIXTURE_ROOT}/src-exclude"
    dest_dir="${TEST_FIXTURE_ROOT}/dest-exclude"
    canonical_dir="${dest_dir}/var/lib/pfs/mount/container-a/common"

    mkdir -p \
        "${source_dir}/usr/lib" \
        "${source_dir}/etc/packages/mount/legacy/internal" \
        "${source_dir}/var/lib/pfs/mount/container/internal" \
        "${dest_dir}"

    printf 'payload\n' > "${source_dir}/usr/lib/libdemo.so"
    printf 'legacy-meta\n' > "${source_dir}/etc/packages/mount/legacy/internal/pfs.files"
    printf 'canonical-meta\n' > "${source_dir}/var/lib/pfs/mount/container/internal/pfs.files"

    run env PFSDIR_MOUNT_NEW="/var/lib/pfs/mount" PFSDIR_MOUNT_LEGACY="/etc/packages/mount" EXT="pfs" bash -c '. "$1"; mklist "$2" "$3" "$4" "$5"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs" "${source_dir}" "${dest_dir}" "common" "container-a"
    [ "${status}" -eq 0 ]

    run grep -Fx '/usr/lib/libdemo.so' "${canonical_dir}/pfs.files"
    [ "${status}" -eq 0 ]

    run grep -E '^/etc/packages|^/var/lib/pfs/mount' "${canonical_dir}/pfs.files"
    [ "${status}" -eq 1 ]
}

mklist_failure_before_rename_keeps_existing_canonical_index_consistent() { #@test
    local source_dir dest_dir canonical_dir legacy_dir before_specs before_files before_dirs after_specs after_files after_dirs

    source_dir="${TEST_FIXTURE_ROOT}/src-atomic-existing"
    dest_dir="${TEST_FIXTURE_ROOT}/dest-atomic-existing"
    canonical_dir="${dest_dir}/var/lib/pfs/mount/container-a/common"
    legacy_dir="${dest_dir}/etc/packages/mount/common"

    mkdir -p "${source_dir}/usr/bin" "${canonical_dir}" "${legacy_dir}" "${dest_dir}" || skip "cannot create atomic-existing fixture"
    printf 'payload\n' > "${source_dir}/usr/bin/demo"

    printf 'name="old"\n' > "${canonical_dir}/pfs.specs" || skip "cannot seed canonical specs"
    printf '/usr/lib/old.so\n' > "${canonical_dir}/pfs.files" || skip "cannot seed canonical files"
    printf '/opt/old-empty\n' > "${canonical_dir}/pfs.dirs.empty" || skip "cannot seed canonical dirs"

    before_specs="$(cat "${canonical_dir}/pfs.specs")"
    before_files="$(cat "${canonical_dir}/pfs.files")"
    before_dirs="$(cat "${canonical_dir}/pfs.dirs.empty")"

    run env PFS_MKLIST_TEST_FAIL_BEFORE_RENAME="1" PFSDIR_MOUNT_NEW="/var/lib/pfs/mount" PFSDIR_MOUNT_LEGACY="/etc/packages/mount" EXT="pfs" bash -c '. "$1"; mklist "$2" "$3" "$4" "$5"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs" "${source_dir}" "${dest_dir}" "common" "container-a"
    [ "${status}" -ne 0 ]

    after_specs="$(cat "${canonical_dir}/pfs.specs")"
    after_files="$(cat "${canonical_dir}/pfs.files")"
    after_dirs="$(cat "${canonical_dir}/pfs.dirs.empty")"

    [ "${after_specs}" = "${before_specs}" ]
    [ "${after_files}" = "${before_files}" ]
    [ "${after_dirs}" = "${before_dirs}" ]
}

mklist_failure_before_rename_does_not_publish_partial_canonical_or_legacy_indexes() { #@test
    local source_dir dest_dir canonical_dir legacy_dir

    source_dir="${TEST_FIXTURE_ROOT}/src-atomic-new"
    dest_dir="${TEST_FIXTURE_ROOT}/dest-atomic-new"
    canonical_dir="${dest_dir}/var/lib/pfs/mount/container-a/common"
    legacy_dir="${dest_dir}/etc/packages/mount/common"

    mkdir -p "${source_dir}/usr/bin" "${source_dir}/opt/empty-dir" "${dest_dir}" || skip "cannot create atomic-new fixture"
    printf 'payload\n' > "${source_dir}/usr/bin/demo"

    run env PFS_MKLIST_TEST_FAIL_BEFORE_RENAME="1" PFSDIR_MOUNT_NEW="/var/lib/pfs/mount" PFSDIR_MOUNT_LEGACY="/etc/packages/mount" EXT="pfs" bash -c '. "$1"; mklist "$2" "$3" "$4" "$5"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs" "${source_dir}" "${dest_dir}" "common" "container-a"
    [ "${status}" -ne 0 ]

    [ ! -e "${canonical_dir}/pfs.files" ]
    [ ! -e "${canonical_dir}/pfs.specs" ]
    [ ! -e "${legacy_dir}/pfs.files" ]
    [ ! -e "${legacy_dir}/pfs.specs" ]
    [ ! -d "${legacy_dir}" ]

    run env PFSDIR_MOUNT_NEW="/var/lib/pfs/mount" PFSDIR_MOUNT_LEGACY="/etc/packages/mount" EXT="pfs" bash -c '. "$1"; pfsdir_mount_find "common"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    [ "${status}" -ne 0 ]

    run find "${dest_dir}/var/lib/pfs/mount/container-a" -maxdepth 1 -type d -name '.common.tmp.*'
    [ "${status}" -eq 0 ]
    [ "${output}" = "" ]
}

pfsfind_reports_duplicate_canonical_submodules_as_qualified_identities() { #@test
    local test_bin bundle_root bundle_path pfs_script pfsfind_script

    assert_fixture_paths_are_temp_root_namespaced

    test_bin="${TEST_FIXTURE_ROOT}/bin"
    bundle_root="${TEST_FIXTURE_ROOT}/bundles"
    bundle_path="${bundle_root}/bundle-id"
    pfs_script="${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    pfsfind_script="${BATS_TEST_DIRNAME}/../../usr/bin/pfsfind"

    mkdir -p "${test_bin}" "${bundle_path}/usr/lib" "${bundle_path}/var/lib/pfs/mount/container-a/common" "${bundle_path}/var/lib/pfs/mount/container-b/common" "${bundle_path}/etc/packages/mount/common" || skip "cannot create pfsfind fixture"
    printf 'payload\n' >"${bundle_path}/usr/lib/libdup.so"
    printf '/usr/lib/libdup.so\n' >"${bundle_path}/var/lib/pfs/mount/container-a/common/pfs.files"
    printf '/usr/lib/libdup.so\n' >"${bundle_path}/var/lib/pfs/mount/container-b/common/pfs.files"
    printf '/usr/lib/libdup.so\n' >"${bundle_path}/etc/packages/mount/common/pfs.files"

    ln -sf "${pfs_script}" "${test_bin}/pfs" || skip "cannot link pfs helper"

    run env PATH="${test_bin}:$PATH" PFSDIR_MOUNT_NEW="/var/lib/pfs/mount" PFSDIR_MOUNT_LEGACY="/etc/packages/mount" PFSFIND_SOURCE_ONLY="1" sh -c '. "$1"; submodules_for_bundle_path "$2" "/usr/lib/libdup.so"' -- "${pfsfind_script}" "${bundle_path}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"container-a:common"* ]]
    [[ "${output}" == *"container-b:common"* ]]
    [[ "${output}" == *"common"* ]]
}

pfsfindlibs_reports_qualified_canonical_and_unqualified_legacy_providers() { #@test
    local test_bin rootdir pfs_script pfsfindlibs_script

    assert_fixture_paths_are_temp_root_namespaced

    test_bin="${TEST_FIXTURE_ROOT}/bin"
    rootdir="${TEST_FIXTURE_ROOT}/root"
    pfs_script="${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    pfsfindlibs_script="${BATS_TEST_DIRNAME}/../../usr/bin/pfsfindlibs"

    mkdir -p "${test_bin}" "${rootdir}" "${TEST_PFSDIR_MOUNT_NEW}/container-a/common" "${TEST_PFSDIR_MOUNT_NEW}/container-b/common" "${TEST_PFSDIR_MOUNT_LEGACY}/common" || skip "cannot create pfsfindlibs fixture"
    mkdir -p "${rootdir}/usr/lib" || skip "cannot create lib fixture dir"
    printf 'payload\n' >"${rootdir}/usr/lib/libdup.so" || skip "cannot create direct so fixture"
    printf '%s\n' "${rootdir}/usr/lib/libdup.so" >"${TEST_PFSDIR_MOUNT_NEW}/container-a/common/pfs.files"
    printf '%s\n' "${rootdir}/usr/lib/libdup.so" >"${TEST_PFSDIR_MOUNT_NEW}/container-b/common/pfs.files"
    printf '%s\n' "${rootdir}/usr/lib/libdup.so" >"${TEST_PFSDIR_MOUNT_LEGACY}/common/pfs.files"

    ln -sf "${pfs_script}" "${test_bin}/pfs" || skip "cannot link pfs helper"

    run env PATH="${test_bin}:$PATH" PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" PFSFINDLIBS_SOURCE_ONLY="1" sh -c '. "$1"; providers_for_library "$2" | tr "\n" ";" | sed "s/;$//"' -- "${pfsfindlibs_script}" "${rootdir}/usr/lib/libdup.so"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"container-a:common"* ]]
    [[ "${output}" == *"container-b:common"* ]]
    [[ "${output}" == *"common"* ]]
}

unqualified_lookup_falls_back_to_legacy_when_no_canonical_exists() { #@test
    assert_fixture_paths_are_temp_root_namespaced
    create_legacy_mount_index_fixture_or_skip

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" bash -c '. "$1"; pfsdir_mount_find "common"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    [ "${status}" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "${TEST_LEGACY_INDEX_DIR}" ]
}

iter_indexes_keeps_duplicate_canonical_identities_distinct() { #@test
    local identities

    assert_fixture_paths_are_temp_root_namespaced
    create_duplicate_mount_index_fixture_or_skip

    identities="$(env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" bash -c 'pfs_script="$1"; . "$pfs_script"; pfsdir_mount_iter_indexes | while IFS= read -r line; do c="$(printf "%s\n" "$line" | cut -f1)"; s="$(printf "%s\n" "$line" | cut -f2)"; if [ -n "$c" ] && [ "$s" = "common" ]; then printf "%s:%s\n" "$c" "$s"; fi; done | sort -u | tr "\n" ";" | sed "s/;$//"' _ "${BATS_TEST_DIRNAME}/../../usr/bin/pfs")"

    [ "${identities}" = "container-a:common;container-b:common" ]
}

pfsinfo_helper_emits_qualified_canonical_and_unqualified_legacy_names() { #@test
    local helper_output pfsinfo_script

    assert_fixture_paths_are_temp_root_namespaced
    create_duplicate_mount_index_fixture_or_skip
    mkdir -p "${TEST_PFSDIR_MOUNT_LEGACY}/legacy" || skip "cannot create legacy helper fixture"
    printf '/usr/lib/legacy.so\n' >"${TEST_PFSDIR_MOUNT_LEGACY}/legacy/pfs.files" || skip "cannot write legacy helper pfs.files"

    pfsinfo_script="${BATS_TEST_DIRNAME}/../../usr/bin/pfsinfo"
    helper_output="$(env PFSINFO_SOURCE_ONLY="1" PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" sh -c '. "$1"; pfsinfo_emit_mount_index_names "" ":" | sort -u | tr "\n" ";" | sed "s/;$//"' _ "${pfsinfo_script}")"

    [ "${helper_output}" = "container-a:common;container-b:common;legacy" ]
}

pfsuninstall_helper_enumerates_install_and_mount_indexes() { #@test
    local install_new install_legacy pfsuninstall_script out

    assert_fixture_paths_are_temp_root_namespaced
    create_mixed_mount_index_fixture_or_skip

    install_new="${TEST_FIXTURE_ROOT}/var/lib/pfs-utils/install"
    install_legacy="${TEST_FIXTURE_ROOT}/etc/packages/install"
    mkdir -p "${install_new}/pkg-new" "${install_legacy}/pkg-legacy" || skip "cannot create install fixture"
    printf '/usr/bin/new\n' >"${install_new}/pkg-new/pfs.files" || skip "cannot write install new pfs.files"
    printf '/usr/bin/legacy\n' >"${install_legacy}/pkg-legacy/pfs.files" || skip "cannot write install legacy pfs.files"

    pfsuninstall_script="${BATS_TEST_DIRNAME}/../../usr/bin/pfsuninstall"
    out="$(env PATH="${PFSUTILS_BIN}:$PATH" PFSUNINSTALL_SOURCE_ONLY="1" PFSUNINSTALL_INSTALL_ROOTS="${install_new}
${install_legacy}" PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" sh -c '. "$1"; pfsuninstall_index_files | sort -u | tr "\n" ";" | sed "s/;$//"' _ "${pfsuninstall_script}")"

    [[ "${out}" == *"${install_new}/pkg-new/pfs.files"* ]]
    [[ "${out}" == *"${install_legacy}/pkg-legacy/pfs.files"* ]]
    [[ "${out}" == *"${TEST_MIXED_CANONICAL_INDEX_DIR}/pfs.files"* ]]
    [[ "${out}" == *"${TEST_MIXED_LEGACY_INDEX_DIR}/pfs.files"* ]]
}

pfsrebuild_helper_resolves_qualified_identity_to_canonical_only() { #@test
    local pfsrebuild_script install_new install_legacy

    assert_fixture_paths_are_temp_root_namespaced
    create_duplicate_mount_index_fixture_or_skip
    install_new="${TEST_FIXTURE_ROOT}/var/lib/pfs-utils/install"
    install_legacy="${TEST_FIXTURE_ROOT}/etc/packages/install"
    mkdir -p "${install_new}/common" "${install_legacy}/common" || skip "cannot create install shadow fixture"
    printf '/usr/lib/install-shadow.so\n' >"${install_new}/common/pfs.files" || skip "cannot write install-shadow file"
    printf '/usr/lib/install-shadow-legacy.so\n' >"${install_legacy}/common/pfs.files" || skip "cannot write legacy install-shadow file"

    pfsrebuild_script="${BATS_TEST_DIRNAME}/../../usr/bin/pfsrebuild"
    run env PATH="${PFSUTILS_BIN}:$PATH" PFSREBUILD_SOURCE_ONLY="1" PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" sh -c '. "$1"; PFSDIR_INSTALL_NEW="$2"; PFSDIR_INSTALL_LEGACY="$3"; pfsrebuild_resolve_fileslist "container-a:common"' _ "${pfsrebuild_script}" "${install_new}" "${install_legacy}"
    [ "${status}" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "${TEST_DUPLICATE_INDEX_DIR_A}/pfs.files" ]
}

pfsrebuild_helper_lists_canonical_container_submodules_as_qualified_identities() { #@test
    local pfsrebuild_script container_root out

    assert_fixture_paths_are_temp_root_namespaced
    pfsrebuild_script="${BATS_TEST_DIRNAME}/../../usr/bin/pfsrebuild"
    container_root="${TEST_FIXTURE_ROOT}/mnt/.testmodule.pfs"
    mkdir -p \
        "${container_root}/var/lib/pfs/mount/testmodule/first" \
        "${container_root}/var/lib/pfs/mount/testmodule/second" || skip "cannot create container index fixture"
    printf '/usr/bin/first\n' >"${container_root}/var/lib/pfs/mount/testmodule/first/pfs.files" || skip "cannot write first index"
    printf '/usr/bin/second\n' >"${container_root}/var/lib/pfs/mount/testmodule/second/pfs.files" || skip "cannot write second index"

    out="$(env PATH="${PFSUTILS_BIN}:$PATH" PFSREBUILD_SOURCE_ONLY="1" PFSDIR_MOUNT_NEW="/var/lib/pfs/mount" PFSDIR_MOUNT_LEGACY="/etc/packages/mount" EXT="pfs" sh -c '. "$1"; prefixmp="$2"; pfsrebuild_container_identities "testmodule" | sort | tr "\n" ";" | sed "s/;$//"' _ "${pfsrebuild_script}" "${TEST_FIXTURE_ROOT}/mnt/.")"

    [ "${out}" = "testmodule:first;testmodule:second" ]
}

pfsextract_helper_uses_unqualified_output_names_for_canonical_identities() { #@test
    local pfsextract_script out

    assert_fixture_paths_are_temp_root_namespaced
    pfsextract_script="${BATS_TEST_DIRNAME}/../../usr/bin/pfsextract"

    out="$(env PATH="${PFSUTILS_BIN}:$PATH" PFSEXTRACT_SOURCE_ONLY="1" EXT="pfs" sh -c '. "$1"; pfsextract_submodule_output_name "testmodule:first"; pfsextract_submodule_output_name "testmodule/second"; pfsextract_submodule_output_name "legacy"' _ "${pfsextract_script}" | tr "\n" ";" | sed "s/;$//")"

    [ "${out}" = "first;second;legacy" ]
}

pfsextract_helper_normalizes_pfsinfo_default_slash_identities() { #@test
    local pfsextract_script out

    assert_fixture_paths_are_temp_root_namespaced
    pfsextract_script="${BATS_TEST_DIRNAME}/../../usr/bin/pfsextract"

    out="$(env PATH="${PFSUTILS_BIN}:$PATH" PFSEXTRACT_SOURCE_ONLY="1" EXT="pfs" sh -c '. "$1"; pfsextract_normalize_identity "testmodule/first"; pfsextract_normalize_identity "testmodule:second"; pfsextract_normalize_identity "legacy"' _ "${pfsextract_script}" | tr "\n" ";" | sed "s/;$//")"

    [ "${out}" = "testmodule:first;testmodule:second;legacy" ]
}

pfsdepends_helper_reads_canonical_depends_for_qualified_identity() { #@test
    local pfsdepends_script

    assert_fixture_paths_are_temp_root_namespaced
    create_duplicate_mount_index_fixture_or_skip
    printf 'dep-alpha\n' >"${TEST_DUPLICATE_INDEX_DIR_A}/pfs.depends" || skip "cannot write canonical depends A"
    printf 'dep-bravo\n' >"${TEST_DUPLICATE_INDEX_DIR_B}/pfs.depends" || skip "cannot write canonical depends B"

    pfsdepends_script="${BATS_TEST_DIRNAME}/../../usr/bin/pfsdepends"
    run env PATH="${PFSUTILS_BIN}:$PATH" PFSDEPENDS_SOURCE_ONLY="1" PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" sh -c '. "$1"; pfsdepends_mount_depends_for "container-a:common"' _ "${pfsdepends_script}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "dep-alpha" ]
}

legacy_mount_migrates_idempotently_into_canonical_legacy_namespace() { #@test
    local migrate_script first_dump second_dump

    assert_fixture_paths_are_temp_root_namespaced
    create_legacy_mount_index_fixture_or_skip
    printf 'dep-legacy\n' >"${TEST_LEGACY_INDEX_DIR}/pfs.depends" || skip "cannot write legacy depends"

    migrate_script="${BATS_TEST_DIRNAME}/../../usr/bin/pfsmigrate-mount"

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" sh "${migrate_script}"
    [ "${status}" -eq 0 ]

    [ -f "${TEST_PFSDIR_MOUNT_NEW}/legacy/common/pfs.files" ]
    [ -f "${TEST_PFSDIR_MOUNT_NEW}/legacy/common/pfs.dirs.empty" ]
    [ -f "${TEST_PFSDIR_MOUNT_NEW}/legacy/common/pfs.specs" ]
    [ -f "${TEST_PFSDIR_MOUNT_NEW}/legacy/common/pfs.depends" ]

    first_dump="$(find "${TEST_PFSDIR_MOUNT_NEW}/legacy/common" -type f -exec sh -c 'for f in "$@"; do printf "%s\\n" "$f"; sha256sum "$f"; done' _ {} + | sort)"

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" sh "${migrate_script}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"skip common (already migrated)"* ]]

    second_dump="$(find "${TEST_PFSDIR_MOUNT_NEW}/legacy/common" -type f -exec sh -c 'for f in "$@"; do printf "%s\\n" "$f"; sha256sum "$f"; done' _ {} + | sort)"
    [ "${first_dump}" = "${second_dump}" ]
}

legacy_index_remains_readable_before_and_after_migration() { #@test
    local migrate_script

    assert_fixture_paths_are_temp_root_namespaced
    create_legacy_mount_index_fixture_or_skip
    migrate_script="${BATS_TEST_DIRNAME}/../../usr/bin/pfsmigrate-mount"

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" bash -c '. "$1"; pfsdir_mount_find "common"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    [ "${status}" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "${TEST_LEGACY_INDEX_DIR}" ]

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" sh "${migrate_script}"
    [ "${status}" -eq 0 ]

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" bash -c '. "$1"; pfsdir_mount_find "legacy:common"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    [ "${status}" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "${TEST_PFSDIR_MOUNT_NEW}/legacy/common" ]

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" EXT="pfs" bash -c '. "$1"; pfsdir_mount_find "common"' -- "${BATS_TEST_DIRNAME}/../../usr/bin/pfs"
    [ "${status}" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "${TEST_PFSDIR_MOUNT_NEW}/legacy/common" ]
}

dry_run_migration_makes_no_filesystem_writes() { #@test
    local migrate_script dry_dst_root

    assert_fixture_paths_are_temp_root_namespaced
    create_legacy_mount_index_fixture_or_skip
    migrate_script="${BATS_TEST_DIRNAME}/../../usr/bin/pfsmigrate-mount"
    dry_dst_root="${TEST_FIXTURE_ROOT}/dry-run-canonical-root"

    [ ! -e "${dry_dst_root}" ]

    run env PFSDIR_MOUNT_NEW="${dry_dst_root}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" sh "${migrate_script}" --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"would copy"* ]]
    [[ "${output}" == *"(dry-run; no filesystem changes made)"* ]]

    [ ! -e "${dry_dst_root}" ]
    [ ! -e "${dry_dst_root}/legacy/common" ]
}

mixed_migration_conflict_is_explicit_and_non_overwriting() { #@test
    local migrate_script before after

    assert_fixture_paths_are_temp_root_namespaced
    create_legacy_mount_index_fixture_or_skip
    mkdir -p "${TEST_PFSDIR_MOUNT_NEW}/legacy/common" || skip "cannot create canonical legacy target"
    printf '/usr/lib/conflict.so\n' >"${TEST_PFSDIR_MOUNT_NEW}/legacy/common/pfs.files" || skip "cannot write conflicting canonical file"

    before="$(cat "${TEST_PFSDIR_MOUNT_NEW}/legacy/common/pfs.files")"
    migrate_script="${BATS_TEST_DIRNAME}/../../usr/bin/pfsmigrate-mount"

    run env PFSDIR_MOUNT_NEW="${TEST_PFSDIR_MOUNT_NEW}" PFSDIR_MOUNT_LEGACY="${TEST_PFSDIR_MOUNT_LEGACY}" sh "${migrate_script}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"conflict legacy:common destination exists with different content"* ]]

    after="$(cat "${TEST_PFSDIR_MOUNT_NEW}/legacy/common/pfs.files")"
    [ "${before}" = "${after}" ]
}
