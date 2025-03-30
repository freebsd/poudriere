LISTPORTS="misc/foo-FLAVORS-unsorted@default"
# misc/foo-FLAVORS-unsorted@default build depends on misc/foo-dep-FLAVORS-unsorted@default
OVERLAYS="omnibus"
. ./common.bulk.sh

set_test_contexts - '' '' <<-EOF
TRIM_ORPHANED_BUILD_DEPS no yes
EOF

while get_test_context; do
	set_poudriere_conf <<-EOF
	TRIM_ORPHANED_BUILD_DEPS=${TRIM_ORPHANED_BUILD_DEPS}
	EOF
	# Tell misc/foo-dep-FLAVORS-unsorted that we want it to have
	# another dependency to test trimming nested deps.
	set_make_conf <<-EOF
	misc_foo-dep-FLAVORS-unsorted_SET=	NESTEDDEP
	EOF

	do_pkgclean -y ports-mgmt/pkg
	assert 0 "$?" "Pkgclean should pass"

	# Build pkg only once as this is a long test otherwise.
	do_bulk ports-mgmt/pkg
	assert 0 "$?" "bulk for pkg should pass"

	EXPECTED_IGNORED=
	EXPECTED_SKIPPED=
	EXPECTED_TOBUILD="misc/foo-FLAVORS-unsorted@default misc/foo-dep-FLAVORS-unsorted@default misc/foo@default"
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

	# Now delete the *build* depend.
	do_pkgclean -y -C misc/foo-dep-FLAVORS-unsorted@default misc/foo@default
	assert 0 "$?" "Pkgclean should pass"

	case "${TRIM_ORPHANED_BUILD_DEPS}" in
	yes)
		# Nothing should be built after this. We are missing
		# misc/foo-dep-FLAVORS-unsorted@default in the dependency graph
		# but only for *build*. For running the listed ports we do not
		# need it. TRIM_ORPHANED_BUILD_DEPS should remove it.
		EXPECTED_TOBUILD=
		;;
	no)
		# Without trimming we do end up building all deps.
		EXPECTED_TOBUILD="misc/foo-dep-FLAVORS-unsorted@default misc/foo@default"
		;;
	esac
	EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
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
