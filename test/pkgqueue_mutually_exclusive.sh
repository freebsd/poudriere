# Depends on pkgqueue_basic.sh
# Depends on pkgqueue_prioritize.sh
. ./common.sh

set_pipefail

set_test_contexts - '' '' <<-EOF
MUTUALLY_EXCLUSIVE_BUILD_PACKAGES "" "rust* llvm*"
EOF

MASTER_DATADIR=$(mktemp -udt datadir)
assert_true add_relpath_var MASTER_DATADIR
while get_test_context; do
	assert_true mkdir -p "${MASTER_DATADIR_ABS:?}"
	assert_true cd "${MASTER_DATADIR_ABS:?}"

	assert_true pkgqueue_init
	assert_true pkgqueue_add "build" pkg
	assert_true pkgqueue_add "build" rust
	assert_true pkgqueue_add_dep "build" rust "build" pkg
	assert_true pkgqueue_add "build" llvm
	assert_true pkgqueue_add_dep "build" llvm "build" pkg
	assert_true pkgqueue_add "build" bash
	assert_true pkgqueue_add_dep "build" bash "build" pkg
	assert_true pkgqueue_add "build" zsh
	assert_true pkgqueue_add_dep "build" zsh "build" pkg
	assert_true pkgqueue_compute_rdeps
	pkgqueue_list="$(pkgqueue_list "build" | LC_ALL=C sort | paste -d ' ' -s -)"
	assert 0 "$?"
	assert "$(sorted "bash llvm pkg rust zsh")" "${pkgqueue_list}"
	assert_out 0 "" pkgqueue_find_dead_packages
	assert_true pkgqueue_prioritize "build" rust 60
	assert_true pkgqueue_prioritize "build" llvm 59
	assert_true pkgqueue_prioritize "build" zsh 50
	assert_true pkgqueue_prioritize "build" bash 49
	assert_true pkgqueue_move_ready_to_pool

	assert_true cd "${MASTER_DATADIR:?}/pool"

	assert_false pkgqueue_empty
	assert_true pkgqueue_get_next job_type pkgname
	assert "pkg" "${pkgname}"
	assert "build" "${job_type}"
	assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
	assert_true pkgqueue_job_done "${job_type}" "${pkgname}"

	assert_false pkgqueue_empty
	assert_true pkgqueue_get_next job_type pkgname
	assert "rust" "${pkgname}"
	assert "build" "${job_type}"

	# Grab next eligible to "build". According to the priorities it should be
	# llvm. But with MUTUALLY_EXCLUSIVE_BUILD_PACKAGES=llvm it will be
	# zsh.
	case "${MUTUALLY_EXCLUSIVE_BUILD_PACKAGES?}" in
	*rust*)
		# llvm should not be returned next. Others should continue
		# to be returned fine until rust is done.
		assert_false pkgqueue_empty
		assert_true pkgqueue_get_next job_type pkgname
		assert "zsh" "${pkgname}"
		assert "build" "${job_type}"
		assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
		assert_true pkgqueue_job_done "${job_type}" "${pkgname}"

		assert_false pkgqueue_empty
		assert_true pkgqueue_get_next job_type pkgname
		assert "bash" "${pkgname}"
		assert "build" "${job_type}"
		assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
		assert_true pkgqueue_job_done "${job_type}" "${pkgname}"

		# Finish off rust and then llvm should show up.
		assert_true pkgqueue_clean_queue "build" "rust" "${clean_rdepends-}"
		assert_true pkgqueue_job_done "build" "rust"

		assert_false pkgqueue_empty
		assert_true pkgqueue_get_next job_type pkgname
		assert "llvm" "${pkgname}"
		assert "build" "${job_type}"
		assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
		assert_true pkgqueue_job_done "${job_type}" "${pkgname}"
		;;
	"")
		# llvm *should* be returned next.
		assert_false pkgqueue_empty
		assert_true pkgqueue_get_next job_type pkgname
		assert "llvm" "${pkgname}"
		assert "build" "${job_type}"
		assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
		assert_true pkgqueue_job_done "${job_type}" "${pkgname}"
		# Finish rust
		assert_true pkgqueue_clean_queue "build" "rust" "${clean_rdepends-}"
		assert_true pkgqueue_job_done "build" "rust"

		assert_false pkgqueue_empty
		assert_true pkgqueue_get_next job_type pkgname
		assert "zsh" "${pkgname}"
		assert "build" "${job_type}"
		assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
		assert_true pkgqueue_job_done "${job_type}" "${pkgname}"

		assert_false pkgqueue_empty
		assert_true pkgqueue_get_next job_type pkgname
		assert "bash" "${pkgname}"
		assert "build" "${job_type}"
		assert_true pkgqueue_clean_queue "${job_type}" "${pkgname}" "${clean_rdepends-}"
		assert_true pkgqueue_job_done "${job_type}" "${pkgname}"
	esac

	assert_true pkgqueue_empty
	assert_true pkgqueue_sanity_check 0
	assert_true pkgqueue_get_next job_type pkgname
	assert "" "${pkgname}"
	assert "" "${job_type}"

	assert_true cd "${POUDRIERE_TMPDIR:?}"
	rm -rf "${MASTER_DATADIR:?}"
done
