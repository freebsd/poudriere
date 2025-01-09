LISTPORTS="devel/libtrue devel/true-buildrun-deps"
# Same as bulk-build-inc-shlibs-lib-deps.sh but relies on
# BUILD_DEPENDS/RUN_DEPENDS *assuming* a LIB_DEPENDS. This
# happens with stuff like p5 ports with USES=perl5.
#
# We use true and libtrue for this test.
#
OVERLAYS="omnibus misc"
. common.bulk.sh

set_test_contexts - '' '' <<-EOF
# XXX: Add other combos in
TRIM_ORPHANED_BUILD_DEPS no
PKG_NO_VERSION_FOR_DEPS yes
SKIP_RECURSIVE_REBUILD 1
EOF

while get_test_context; do
	set_poudriere_conf <<-EOF
	TRIM_ORPHANED_BUILD_DEPS=${TRIM_ORPHANED_BUILD_DEPS}
	# Mimic bulk -S - don't recursively delete packages when deps are missing.
	SKIP_RECURSIVE_REBUILD=${SKIP_RECURSIVE_REBUILD:?}
	PKG_NO_VERSION_FOR_DEPS=${PKG_NO_VERSION_FOR_DEPS:?}
	EOF
	set_make_conf <<-EOF
	EOF

	do_pkgclean -y ports-mgmt/pkg
	assert 0 "$?" "Pkgclean should pass"

	# Build pkg only once as this is a long test otherwise.
	do_bulk ports-mgmt/pkg
	assert 0 "$?" "bulk for pkg should pass"

	EXPECTED_IGNORED=
	EXPECTED_SKIPPED=
	EXPECTED_INSPECTED=
	EXPECTED_TOBUILD="${LISTPORTS}"
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

	# Update shlib ver for libtrue

	set_make_conf <<-EOF
	devel_libtrue_SET=	SHLIB_BUMP
	EOF

	EXPECTED_IGNORED=
	EXPECTED_INSPECTED=
	EXPECTED_TOBUILD="devel/libtrue devel/true-buildrun-deps"
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

	# Building again nothing should happen.
	EXPECTED_TOBUILD=
	# XXX: These are "listed to build" even though all we intend to do is
	# check if shlib is satisified.
	# It's a bug to fix.
	EXPECTED_TOBUILD="devel/true-buildrun-deps"
	EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
	EXPECTED_BUILT=
	do_bulk -n ${LISTPORTS}
	assert 0 $? "Bulk should pass"
	assert_bulk_queue_and_stats
	assert_bulk_dry_run
	echo "------" | tee /dev/stderr

	EXPECTED_IGNORED=
	EXPECTED_INSPECTED="devel/true-buildrun-deps"
	#EXPECTED_TOBUILD=
	EXPECTED_BUILT=" "
	do_bulk ${LISTPORTS}
	assert 0 $? "Bulk should pass"
	assert_bulk_queue_and_stats
	assert_bulk_build_results
	echo "------" | tee /dev/stderr
done
