# Packages built for PKG_NO_VERSION_FOR_DEPS=='yes' should be deleted
# if PKG_NO_VERSION_FOR_DEPS changes to 'no'.
#  - Only packages with *dependencies* follow this.
# Changing from 'no' to 'yes' should not do anything.
LISTPORTS="ports-mgmt/poudriere-devel-dep-FOO"
OVERLAYS="omnibus"
. common.bulk.sh

: ${ASSERT_CONTINUE:=0}
set_test_contexts - '' '' <<-EOF
PKG_NO_VERSION_FOR_DEPS_ORIG no yes
EOF

while get_test_context; do
	# Build pkg only once as this is a long test otherwise.
	do_bulk ports-mgmt/pkg
	assert 0 "$?" "bulk for pkg should pass"

	PKG_NO_VERSION_FOR_DEPS="${PKG_NO_VERSION_FOR_DEPS_ORIG}"
	set_poudriere_conf <<-EOF
	PKG_NO_VERSION_FOR_DEPS=${PKG_NO_VERSION_FOR_DEPS}
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

	# Check again - nothing should change.
	EXPECTED_BUILT=
	EXPECTED_TOBUILD=
	EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
	do_bulk -n ${LISTPORTS}
	assert 0 $? "Bulk should pass"
	assert_bulk_queue_and_stats
	assert_bulk_dry_run

	case "${PKG_NO_VERSION_FOR_DEPS_ORIG}" in
	no)
		# Flip PKG_NO_VERSION_FOR_DEPS no->yes: Nothing should happen
		# as the packages are compatible for this case.
		PKG_NO_VERSION_FOR_DEPS=yes
		EXPECTED_TOBUILD=
		;;
	yes)
		# Flip PKG_NO_VERSION_FOR_DEPS yes->no:
		# All with *deps* should rebuild. I.e., not misc/foo or pkg.
		PKG_NO_VERSION_FOR_DEPS=no
		EXPECTED_TOBUILD="ports-mgmt/poudriere-devel-dep-FOO misc/freebsd-release-manifests@foo"
		;;
	esac
	EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
	set_poudriere_conf <<-EOF
	PKG_NO_VERSION_FOR_DEPS=${PKG_NO_VERSION_FOR_DEPS}
	EOF

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
done
