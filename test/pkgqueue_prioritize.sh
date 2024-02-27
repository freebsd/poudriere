# Depends on pkgqueue_basic.sh passing
. common.sh

set_pipefail

MASTER_DATADIR=$(mktemp -dt datadir)
assert_true cd "${MASTER_DATADIR}"
assert_true add_relpath_var MASTER_DATADIR

assert_true pkgqueue_init
assert_true pkgqueue_add pkg
assert_true pkgqueue_add zsh
assert_true pkgqueue_add_dep zsh pkg
assert_true pkgqueue_add ash
assert_true pkgqueue_add_dep ash pkg
assert_true pkgqueue_add ksh
assert_true pkgqueue_add_dep ksh pkg
assert_true pkgqueue_add bash
assert_true pkgqueue_add_dep bash pkg
assert_true pkgqueue_add patchutils
assert_true pkgqueue_add_dep patchutils bash
assert_true pkgqueue_add_dep patchutils pkg
assert_true pkgqueue_compute_rdeps
pkgqueue_list="$(pkgqueue_list | LC_ALL=C sort | paste -d ' ' -s -)"
assert 0 "$?"
assert "$(sorted "ash bash ksh patchutils pkg zsh")" "${pkgqueue_list}"
assert_out "" pkgqueue_find_dead_packages

assert_true pkgqueue_prioritize ksh 50
assert_true pkgqueue_prioritize ash 49
assert_true pkgqueue_prioritize bash 48
assert_true pkgqueue_prioritize zsh 47
assert_true pkgqueue_prioritize patchutils 46
assert_true pkgqueue_move_ready_to_pool

assert_true cd "${MASTER_DATADIR:?}/pool"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next pkgname
assert "pkg" "${pkgname}"
assert_true pkgqueue_clean_queue "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${pkgname}"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next pkgname
assert "ksh" "${pkgname}"
assert_true pkgqueue_clean_queue "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${pkgname}"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next pkgname
assert "ash" "${pkgname}"
assert_true pkgqueue_clean_queue "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${pkgname}"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next pkgname
assert "bash" "${pkgname}"
assert_true pkgqueue_clean_queue "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${pkgname}"

assert_false pkgqueue_empty
assert_true pkgqueue_get_next pkgname
assert "zsh" "${pkgname}"
assert_true pkgqueue_clean_queue "${pkgname}" "${clean_rdepends-}"
assert_true pkgqueue_job_done "${pkgname}"

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
