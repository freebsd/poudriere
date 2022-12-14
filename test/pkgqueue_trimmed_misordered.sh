# See also bulk-build-inc-nested-dep-middle-unneeded-without-recursive-delete-misordered.sh
#	This test is only proving the setup for the bulk test as it was an
#	odd case that came up with incremental rebuild changes.
#	For the bulk test the ports map as so:
#	  bash = misc/foo
#	  patchutils = misc/freebsd-release-manifests@foo
#	  patchutils-meta = ports-mgmt/poudriere-devel-dep-FOO
#	bash and patchutils-meta must be "listed"
# Depends on pkgqueue_basic.sh passing
# Depends on pkgqueue_prioritize.sh passing
# Depends on pkgqueue_remove_many_pipe.sh passing
. common.sh

set_pipefail

set_test_contexts - '' '' <<-EOF
# TRIM_ORPHANED_BUILD_DEPS is not the root problem here. It is
# pkgqueue_unqueue_existing_packages. But because it is a secondary
# trim of the queue it is also checked.
TRIM_ORPHANED_BUILD_DEPS no yes
EOF

while get_test_context; do
	MASTER_DATADIR=$(mktemp -dt datadir)
	assert_true cd "${MASTER_DATADIR}"
	assert_true add_relpath_var MASTER_DATADIR

	assert_true pkgqueue_init
	assert_true pkgqueue_add bash
	assert_true pkgqueue_add patchutils
	assert_true pkgqueue_add_dep patchutils bash
	assert_true pkgqueue_add patchutils-meta
	assert_true pkgqueue_add_dep patchutils-meta patchutils
	assert_true pkgqueue_compute_rdeps

	# Simulate patchutils having an existing package so being trimmed from
	# the queue by pkgqueue_unqueue_existing_packages().
	echo patchutils | assert_true pkgqueue_remove_many_pipe
	assert 0 "$?"
	case "${TRIM_ORPHANED_BUILD_DEPS-}" in
	yes)
		if ! type pkgqueue_trim_orphaned_build_deps >/dev/null 2>&1; then
			assert_true cd "${POUDRIERE_TMPDIR:?}"
			rm -rf "${MASTER_DATADIR:?}"
			continue
		fi
		# pkgqueue_trim_orphaned_build_deps is removed later but if present we need
		# to have bash and patchutils-meta as listed.
		listed_pkgnames() {
			echo "bash"
			echo "patchutils-meta"
		}
		assert_true pkgqueue_trim_orphaned_build_deps
		;;
	esac
	pkgqueue_list="$(pkgqueue_list | LC_ALL=C sort | paste -d ' ' -s -)"
	assert 0 "$?"
	assert "$(sorted "bash patchutils-meta")" "${pkgqueue_list}"

	assert_true pkgqueue_prioritize patchutils-meta 50
	assert_true pkgqueue_prioritize bash 49

	assert_true pkgqueue_move_ready_to_pool

	# Now patchutils-meta and bash are eligible to build.
	# patchutils-meta will install the "existing" package for patchtutils which will
	# try to install bash. But bash is building concurrently and has no package
	# to install.

	assert_true cd "${MASTER_DATADIR:?}/pool"

	# patchutils-meta and bash should be eligible concurrently.
	# Note that in a real build this is a fatal condition. It is only
	# asserted here as proof of a possible queue issue that is tested
	# fully in bulk-build-inc-nested-dep-middle-unneeded-without-recursive-delete-misordered.sh
	assert_false pkgqueue_empty
	assert_true pkgqueue_get_next pkgname porttesting
	assert "patchutils-meta" "${pkgname}"

	assert_false pkgqueue_empty
	assert_true pkgqueue_get_next pkgname porttesting
	assert "bash" "${pkgname}"


	assert_true pkgqueue_clean_queue "patchutils-meta" "${clean_rdepends-}"
	assert_true pkgqueue_job_done "patchutils-meta"
	assert_true pkgqueue_clean_queue "bash" "${clean_rdepends-}"
	assert_true pkgqueue_job_done "bash"

	assert_true pkgqueue_empty
	assert_true pkgqueue_sanity_check 0
	assert_true pkgqueue_get_next pkgname porttesting
	assert "" "${pkgname}"


	assert_true cd "${POUDRIERE_TMPDIR:?}"
	rm -rf "${MASTER_DATADIR:?}"
done
