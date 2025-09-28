FLAVOR_DEFAULT_ALL=no
FLAVOR_ALL=all
LISTPORTS="\
	ports-mgmt/poudriere-devel \
	misc/freebsd-release-manifests@${FLAVOR_ALL} \
	misc/foo@${FLAVOR_ALL} \
	misc/foo-FLAVORS-unsorted@${FLAVOR_ALL} \
"
JFLAG=4
OVERLAYS="omnibus"
. ./common.bulk.sh

# This is the same as bulk-build-multiple-eligible-in-queue.sh except that
# misc/foo will fail to build and cause rdeps to skip.
set_make_conf <<-EOF
misc_foo_SET=	FAILURE
EOF

do_pkgclean -y -A
assert 0 "$?" "Pkgclean should pass"

EXPECTED_IGNORED="misc/foo-FLAVORS-unsorted@ignored misc/foo-FLAVORS-unsorted@depignored misc/foo@ignored misc/foo-dep-FLAVORS-unsorted@depignored"
EXPECTED_SKIPPED=""
EXPECTED_TOBUILD="misc/foo@default misc/foo-FLAVORS-unsorted@default misc/foo-FLAVORS-unsorted@flav misc/foo@flav misc/freebsd-release-manifests@default misc/freebsd-release-manifests@bar misc/freebsd-release-manifests@foo ports-mgmt/pkg ports-mgmt/poudriere-devel misc/foo-dep-FLAVORS-unsorted@default misc/foo-dep-FLAVORS-unsorted@flav"
EXPECTED_QUEUED="${EXPECTED_TOBUILD} ${EXPECTED_IGNORED}"
EXPECTED_LISTED="${LISTPORTS}"
EXPECTED_BUILT=
do_bulk -c -n "${LISTPORTS}"
assert 0 "$?" "Bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_dry_run
echo "------" | tee /dev/stderr

# Cause foo's builder to crash rather than port failure.

set_poudriere_conf <<-EOF
FP_BUILD_PKG_EXIT_PKGNAMES="foo"
EOF

# Remove misc/foo@* and misc/freebsd-release-manifests@foo
EXPECTED_BUILT="misc/foo-FLAVORS-unsorted@default misc/foo-FLAVORS-unsorted@flav misc/freebsd-release-manifests@default misc/freebsd-release-manifests@bar ports-mgmt/pkg ports-mgmt/poudriere-devel misc/foo-dep-FLAVORS-unsorted@default misc/foo-dep-FLAVORS-unsorted@flav"
EXPECTED_FAILED="misc/foo@default:stage misc/foo@flav"
EXPECTED_SKIPPED="misc/freebsd-release-manifests@foo:foo-20161010"

do_bulk -c "${LISTPORTS}"
# The return status is poorly defined. 2 failed + 1 skipped
assert 3 "$?" "Bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results

do_pkgclean_smoke
