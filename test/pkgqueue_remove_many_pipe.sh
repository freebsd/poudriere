. ./common.sh

set_pipefail

MASTER_DATADIR=$(mktemp -dt datadir)
assert_true cd "${MASTER_DATADIR}"
assert_true add_relpath_var MASTER_DATADIR

assert_true pkgqueue_init
assert_true pkgqueue_add "build" pkg
assert_true pkgqueue_add "build" bash
assert_true pkgqueue_add_dep "build" bash "build" pkg
assert_true pkgqueue_add "build" patchutils
assert_true pkgqueue_add_dep "build" patchutils "build" bash
assert_true pkgqueue_add_dep "build" patchutils "build" pkg
assert_true pkgqueue_add "build" devtools
assert_true pkgqueue_add_dep "build" devtools "build" patchutils
assert_true pkgqueue_add_dep "build" devtools "build" bash
assert_true pkgqueue_add_dep "build" devtools "build" pkg
assert_true pkgqueue_add "build" ash
assert_true pkgqueue_add_dep "build" ash "build" pkg
assert_true pkgqueue_add "build" zsh
assert_true pkgqueue_add_dep "build" zsh "build" pkg
assert_true pkgqueue_compute_rdeps
pkgqueue_list="$(pkgqueue_list "build" | LC_ALL=C sort | paste -d ' ' -s -)"
assert 0 "$?"
assert "$(sorted "ash bash devtools zsh patchutils pkg")" "${pkgqueue_list}"
assert_out 0 "" pkgqueue_find_dead_packages
assert_true pkgqueue_prioritize "build" bash 50
assert_true pkgqueue_prioritize "build" zsh 49
assert_true pkgqueue_prioritize "build" devtools 48 # depends on patchutils so this won't do much
assert_true pkgqueue_prioritize "build" ash 47
assert_true pkgqueue_prioritize "build" patchutils 46
assert_true pkgqueue_move_ready_to_pool

assert_true cd "${MASTER_DATADIR:?}/pool"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next job_type pkgname
assert "pkg" "${pkgname}"
assert "build" "${job_type}"

{
	echo "bash"
	echo "zsh"
} | assert_true pkgqueue_remove_many_pipe "build"
# patchutils and devtools will remain
assert 0 "$?"

assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${job_type}" "${pkgname}"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next job_type pkgname
assert "ash" "${pkgname}"
assert "build" "${job_type}"
assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${job_type}" "${pkgname}"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next job_type pkgname
assert "patchutils" "${pkgname}"
assert "build" "${job_type}"
assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${job_type}" "${pkgname}"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next job_type pkgname
assert "devtools" "${pkgname}"
assert "build" "${job_type}"
assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${job_type}" "${pkgname}"

assert_true pkgqueue_empty
assert_true pkgqueue_sanity_check 0
assert_true pkgqueue_get_next job_type pkgname
assert "" "${pkgname}"
assert "" "${job_type}"

assert_true cd "${POUDRIERE_TMPDIR:?}"
rm -rf "${MASTER_DATADIR:?}"
