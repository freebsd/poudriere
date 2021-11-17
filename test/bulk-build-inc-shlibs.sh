LISTPORTS="converters/libiconv devel/libtextstyle devel/gettext-runtime"
#LISTPORTS="${LISTPORTS} devel/gettext-tools"
# The point of this test is to update a library port and ensure that
# *without incremental recursive delete* that if the shlib version
# is bumped then anything depending on that lib will rebuild still
# even without a PORTREVISION bump. It's a hack to help produce working
# packages for when committers forget to do a PORTREVISION chase.
#
# gettext-runtime depends on indexinfo libiconv
# libtextstyle depends on libiconv
OVERLAYS="omnibus"
. common.bulk.sh

set_test_contexts - '' '' <<-EOF
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
	EXPECTED_TOBUILD="${LISTPORTS} print/indexinfo"
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

	# Bump the shlib version in converters/libiconv.
	# It is expected that gettext-runtime and libtextstyle will rebuild.
	# This rebuild should only happen once: until the package's shlib
	# requirements match what port provides.

	# Use the overlay version of libiconv which has a bumped version.
	OVERLAYS="${OVERLAYS} shlibs-libiconv"

	# The default overlay version simply has a new PORTVERSION
	# and MINOR shlib version. libiconv.so.2.*
	# Neither should cause a rebuild.
	# Test that first.
	EXPECTED_TOBUILD="converters/libiconv"
	# XXX: Current implementation is funky.
	# gettext-runtime and libtextstyle are both "tobuild" and "queued"
	# for dry-run but will be "ignored" in the real build.
	EXPECTED_TOBUILD="${EXPECTED_TOBUILD} devel/gettext-runtime devel/libtextstyle"
	EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
	EXPECTED_BUILT=
	do_bulk -n ${LISTPORTS}
	assert 0 $? "Bulk should pass"
	assert_bulk_queue_and_stats
	assert_bulk_dry_run
	echo "------" | tee /dev/stderr

	# XXX: shlib checks cause ignores right now
	EXPECTED_IGNORED="devel/gettext-runtime devel/libtextstyle"
	#EXPECTED_BUILT="${EXPECTED_TOBUILD}"
	EXPECTED_BUILT="converters/libiconv"
	do_bulk ${LISTPORTS}
	assert 0 $? "Bulk should pass"
	assert_bulk_queue_and_stats
	assert_bulk_build_results
	echo "------" | tee /dev/stderr

	# Now enable the option to update from libiconv.so.2.* to libiconv.so.9
	set_make_conf <<-EOF
	converters_libiconv_SET=	SHLIB_BUMP
	EOF

	EXPECTED_IGNORED=
	EXPECTED_TOBUILD="converters/libiconv devel/gettext-runtime devel/libtextstyle"
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
	EXPECTED_TOBUILD="devel/gettext-runtime devel/libtextstyle"
	EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
	EXPECTED_BUILT=
	do_bulk -n ${LISTPORTS}
	assert 0 $? "Bulk should pass"
	assert_bulk_queue_and_stats
	assert_bulk_dry_run
	echo "------" | tee /dev/stderr

	# XXX: shlib checks cause ignores right now
	EXPECTED_IGNORED="devel/gettext-runtime devel/libtextstyle"
	#EXPECTED_TOBUILD=
	EXPECTED_BUILT=" "
	do_bulk ${LISTPORTS}
	assert 0 $? "Bulk should pass"
	assert_bulk_queue_and_stats
	assert_bulk_build_results
	echo "------" | tee /dev/stderr
done
