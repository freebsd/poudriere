# See also pkgqueue_trimmed_misordered.sh
LISTPORTS="ports-mgmt/poudriere-devel-dep-FOO"
OVERLAYS="omnibus"
. ./common.bulk.sh

: ${ASSERT_CONTINUE:=0}
set_test_contexts - '' '' <<-EOF
SKIP_RECURSIVE_REBUILD 0 1
PKG_NO_VERSION_FOR_DEPS no yes
DELETE_UNQUEUED_PACKAGES no yes
WITH_MANUAL_FOO_DELETE 0 1
EOF
while get_test_context; do
	# Build pkg only once as this is a long test otherwise.
	do_bulk ports-mgmt/pkg
	assert 0 "$?" "bulk for pkg should pass"

	set_poudriere_conf <<-EOF
	# Mimic bulk -S - don't recursively delete packages when deps are missing.
	SKIP_RECURSIVE_REBUILD=${SKIP_RECURSIVE_REBUILD:?}
	PKG_NO_VERSION_FOR_DEPS=${PKG_NO_VERSION_FOR_DEPS:?}
	DELETE_UNQUEUED_PACKAGES=${DELETE_UNQUEUED_PACKAGES:?}
	EOF
	set_make_conf <<-EOF
	misc_foo_UNSET=	RENAME
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

	case "${WITH_MANUAL_FOO_DELETE}" in
	1)
		# Ensure misc/foo is deleted before changing its PKGBASE.
		# Normally delete_old_pkg() handles new PKGNAME fine but in the case
		# of a new PKGBASE it tends to ignore the package.  We need the package
		# gone for the run-depends test later.
		do_pkgclean -yC misc/foo
		;;
	esac

	set_make_conf <<-EOF
	misc_foo_SET=	RENAME
	EOF
	# misc/foo should now have a -renamed at the end of it.
	# misc/freebsd-release-manifests@foo should be deleted to fix wrong
	# dep_pkgname and misc/foo@default will be rebuilt.

	# Force ports-mgmt/poudriere-devel-dep-FOO to rebuild as it needs to go through
	# run-depends to check for the changed PKGNAME bug.
	do_pkgclean -yC ports-mgmt/poudriere-devel-dep-FOO

	EXPECTED_IGNORED=""
	EXPECTED_SKIPPED=
	EXPECTED_TOBUILD="misc/foo@default ports-mgmt/poudriere-devel-dep-FOO"
	# Case statement is just saying these values don't matter.
	case "${PKG_NO_VERSION_FOR_DEPS-}.${SKIP_RECURSIVE_REBUILD}" in
	*)
		# The dep_pkgbase check forces a rebuild
		EXPECTED_TOBUILD="${EXPECTED_TOBUILD} misc/freebsd-release-manifests@foo"
		;;
	esac
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
	echo "------" | tee /dev/stderr
done
