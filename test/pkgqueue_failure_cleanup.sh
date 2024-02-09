# Depends on pkgqueue_basic.sh passing
# Depends on pkgqueue_prioritize.sh passing
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
assert_true pkgqueue_add devtools
assert_true pkgqueue_add_dep devtools patchutils
assert_true pkgqueue_add_dep devtools bash
assert_true pkgqueue_add_dep devtools pkg
assert_true pkgqueue_add zsh
assert_true pkgqueue_add_dep zsh pkg
assert_true pkgqueue_compute_rdeps
pkgqueue_list="$(pkgqueue_list | LC_ALL=C sort | paste -d ' ' -s -)"
assert 0 "$?"
assert "$(sorted "bash devtools zsh patchutils pkg")" "${pkgqueue_list}"
assert_out "" pkgqueue_find_dead_packages
assert_true pkgqueue_prioritize bash 50
assert_true pkgqueue_prioritize zsh 49
assert_true pkgqueue_move_ready_to_pool

assert_true cd "${MASTER_DATADIR:?}/pool"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next pkgname porttesting
assert "pkg" "${pkgname}"
assert_true pkgqueue_clean_queue "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${pkgname}"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next pkgname porttesting
assert "bash" "${pkgname}"
# Consider it a failure: Clean all rdeps out of the queue.
skipped="$(pkgqueue_clean_queue "${pkgname}" "1")"
assert 0 "$?"
assert "$(sorted "devtools patchutils")" "$(sorted "${skipped}")"
assert_true pkgqueue_job_done "${pkgname}"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next pkgname porttesting
assert "zsh" "${pkgname}"
assert_true pkgqueue_clean_queue "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${pkgname}"

assert_true pkgqueue_empty
assert_true pkgqueue_sanity_check 0
assert_true pkgqueue_get_next pkgname porttesting
assert "" "${pkgname}"

assert_true cd "${POUDRIERE_TMPDIR:?}"
rm -rf "${MASTER_DATADIR:?}"
