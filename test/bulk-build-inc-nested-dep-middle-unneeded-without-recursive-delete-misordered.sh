# See also pkgqueue_trimmed_misordered.sh
LISTPORTS="ports-mgmt/poudriere-devel-dep-FOO misc/foo@default"
# ports-mgmt/poudriere-devel-dep-FOO depends on misc/freebsd-release-manifests@foo
# misc/freebsd-release-manifests@foo depends on misc/foo@default
#
# What happens if we are missing a package for ports-mgmt/poudriere-devel-dep-FOO?
# What happens if we are missing a package for misc/freebsd-release-manifests@foo?
# What happens if we are missing a pacakge for misc/foo@default?
#
# The tests here likely rely on the "missing" package to be removed by delete_old_pkg()
OVERLAYS="omnibus"
. ./common.bulk.sh

: ${ASSERT_CONTINUE:=0}
set_test_contexts - '' '' <<-EOF
JFLAG 1:4 4:4
SKIP_RECURSIVE_REBUILD 0 1
TRIM_ORPHANED_BUILD_DEPS no yes
EOF
while get_test_context; do
	# Build pkg only once as this is a long test otherwise.
	do_bulk ports-mgmt/pkg
	assert 0 "$?" "bulk for pkg should pass"

	set_poudriere_conf <<-EOF
	# Mimic bulk -S - don't recursively delete packages when deps are missing.
	SKIP_RECURSIVE_REBUILD=${SKIP_RECURSIVE_REBUILD:?}
	EOF

	do_pkgclean -y ports-mgmt/pkg
	assert 0 "$?" "Pkgclean should pass"

	EXPECTED_IGNORED=""
	EXPECTED_SKIPPED=
	EXPECTED_TOBUILD="ports-mgmt/poudriere-devel-dep-FOO misc/freebsd-release-manifests@foo misc/foo@default"
	EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
	EXPECTED_LISTED="${LISTPORTS}"
	EXPECTED_BUILT=
	do_bulk -n ${LISTPORTS}
	assert 0 $? "Bulk should pass"
	assert_bulk_queue_and_stats
	assert_bulk_dry_run
	echo "------" | tee /dev/stderr

	EXPECTED_BUILT="${EXPECTED_TOBUILD}"
	do_bulk ${LISTPORTS}
	assert 0 $? "Bulk should pass"
	assert_bulk_queue_and_stats
	assert_bulk_build_results
	allpackages="$(/bin/ls ${PACKAGES:?}/All)"
	assert 0 "$?"
	echo "------" | tee /dev/stderr


	LISTPORTS="ports-mgmt/poudriere-devel-dep-FOO misc/foo@default"
	do_pkgclean -y -C ${LISTPORTS}
	assert 0 "$?" "Pkgclean should pass"
	nowpackages="$(/bin/ls ${PACKAGES:?}/All)"
	assert 0 "$?"
	assert_not "${allpackages}" "${nowpackages}"
	assert_not [ -e "${PACKAGES:?}/All/foo-20161010.${PKG_EXT:?}" ]
	assert_not [ -e "${PACKAGES:?}/All/poudriere-devel-dep-FOO-3.1.99.20170601_1.${PKG_EXT:?}" ]
	EXPECTED_IGNORED=""
	EXPECTED_SKIPPED=
	EXPECTED_TOBUILD="ports-mgmt/poudriere-devel-dep-FOO misc/foo@default"
	case "${PKG_NO_VERSION_FOR_DEPS-}.${SKIP_RECURSIVE_REBUILD}" in
	yes.*) ;;
	*.0)
		# Incremental build deletes rdeps when deps are missing.
		EXPECTED_TOBUILD="${EXPECTED_TOBUILD} misc/freebsd-release-manifests@foo"
		;;
	esac
	EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
	EXPECTED_LISTED="${LISTPORTS}"
	EXPECTED_BUILT=
	# We only need a sleep if JFLAG>1
	case "${JFLAG}" in
	1|1:*)
		set_make_conf <<-EOF
		EOF
		;;
	*)
		set_make_conf <<-EOF
		# Ensure misc/foo sleeps so that the ports-mgmt/poudriere-devel-dep-FOO
		# build fails to find the package since it is concurrently building.
		misc_foo_SET=	SLEEP
		EOF
		;;
	esac
	do_bulk -n ${LISTPORTS}
	assert 0 $? "Bulk should pass"
	assert_bulk_queue_and_stats
	assert_bulk_dry_run
	echo "------" | tee /dev/stderr

	EXPECTED_BUILT="${EXPECTED_TOBUILD}"
	do_bulk ${LISTPORTS}
	assert 0 $? "Bulk should pass"
	assert_bulk_queue_and_stats
	assert_bulk_build_results
	echo "------" | tee /dev/stderr

	# This error indicates the queue was misordered.
	# [00:00:53] (00:00:03) [00:00:11] [02] [00:00:07] Finished ports-mgmt/poudriere-devel-dep-FOO | poudriere-devel-dep-FOO-3.1.99.20170601_1: Failed: run-depends
done
