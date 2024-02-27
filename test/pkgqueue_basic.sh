. common.sh

set_pipefail

MASTER_DATADIR=$(mktemp -dt datadir)
assert_true cd "${MASTER_DATADIR}"
assert_true add_relpath_var MASTER_DATADIR

assert_true pkgqueue_init
assert_true pkgqueue_add pkg
assert_true pkgqueue_add bash
assert_true pkgqueue_add_dep bash pkg
assert_true pkgqueue_add patchutils
assert_true pkgqueue_add_dep patchutils bash
assert_true pkgqueue_add_dep patchutils pkg
assert_true pkgqueue_compute_rdeps
pkgqueue_list="$(pkgqueue_list | LC_ALL=C sort | paste -d ' ' -s -)"
assert 0 "$?"
assert "$(sorted "bash patchutils pkg")" "${pkgqueue_list}"
assert_out "" pkgqueue_find_dead_packages
assert_true pkgqueue_move_ready_to_pool

assert_out - pkgqueue_remaining <<EOF
pkg ready-to-build
bash waiting-on-dependency
patchutils waiting-on-dependency
EOF

assert_true cd "${MASTER_DATADIR:?}/pool"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next pkgname
assert "pkg" "${pkgname}"
assert_true pkgqueue_clean_queue "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${pkgname}"

assert_out - pkgqueue_remaining <<EOF
bash ready-to-build
patchutils waiting-on-dependency
EOF

assert_false pkgqueue_empty
assert_true pkgqueue_get_next pkgname
assert "bash" "${pkgname}"
assert_true pkgqueue_clean_queue "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${pkgname}"

assert_out - pkgqueue_remaining <<EOF
patchutils ready-to-build
EOF

assert_false pkgqueue_empty
assert_true pkgqueue_get_next pkgname
assert "patchutils" "${pkgname}"
assert_true pkgqueue_clean_queue "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${pkgname}"

assert_true pkgqueue_empty
assert_true pkgqueue_sanity_check 0
assert_true pkgqueue_get_next pkgname
assert "" "${pkgname}"

assert_true cd "${POUDRIERE_TMPDIR:?}"
rm -rf "${MASTER_DATADIR:?}"
