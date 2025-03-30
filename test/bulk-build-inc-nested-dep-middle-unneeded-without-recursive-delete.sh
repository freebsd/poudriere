LISTPORTS="ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-dep-FOO misc/freebsd-release-manifests@foo"
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

set_poudriere_conf <<-EOF
# Mimic bulk -S - don't recursively delete packages when deps are missing.
SKIP_RECURSIVE_REBUILD=1
EOF

do_pkgclean -y ports-mgmt/pkg
assert 0 "$?" "Pkgclean should pass"

# Build pkg only once as this is a long test otherwise.
do_bulk ports-mgmt/pkg
assert 0 "$?" "bulk for pkg should pass"

EXPECTED_IGNORED=""
EXPECTED_SKIPPED=
EXPECTED_TOBUILD="ports-mgmt/poudriere-devel-dep-FOO misc/freebsd-release-manifests@default ports-mgmt/poudriere-devel misc/freebsd-release-manifests@foo misc/foo@default:misc/freebsd-release-manifests@foo"
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

do_pkgclean -y -C ports-mgmt/poudriere-devel-dep-FOO
assert 0 "$?" "Pkgclean should pass"
nowpackages="$(/bin/ls ${PACKAGES:?}/All)"
assert 0 "$?"
assert_not "${allpackages}" "${nowpackages}"
EXPECTED_IGNORED=""
EXPECTED_SKIPPED=
EXPECTED_TOBUILD="ports-mgmt/poudriere-devel-dep-FOO"
EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
EXPECTED_LISTED="${LISTPORTS}"
EXPECTED_BUILT="${EXPECTED_TOBUILD}"
do_bulk ${LISTPORTS}
assert 0 $? "Bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
nowpackages="$(/bin/ls ${PACKAGES:?}/All)"
assert 0 "$?"
assert "${allpackages}" "${nowpackages}"
echo "------" | tee /dev/stderr

do_pkgclean -y -C misc/freebsd-release-manifests@foo
assert 0 "$?" "Pkgclean should pass"
nowpackages="$(/bin/ls ${PACKAGES:?}/All)"
assert 0 "$?"
assert_not "${allpackages}" "${nowpackages}"
EXPECTED_IGNORED=""
EXPECTED_SKIPPED=
EXPECTED_TOBUILD="misc/freebsd-release-manifests@foo"
EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
EXPECTED_LISTED="${LISTPORTS}"
EXPECTED_BUILT="${EXPECTED_TOBUILD}"
do_bulk ${LISTPORTS}
assert 0 $? "Bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
nowpackages="$(/bin/ls ${PACKAGES:?}/All)"
assert 0 "$?"
assert "${allpackages}" "${nowpackages}"
echo "------" | tee /dev/stderr

do_pkgclean -y -C misc/foo@default
assert 0 "$?" "Pkgclean should pass"
nowpackages="$(/bin/ls ${PACKAGES:?}/All)"
assert 0 "$?"
assert_not "${allpackages}" "${nowpackages}"
EXPECTED_IGNORED=""
EXPECTED_SKIPPED=
EXPECTED_TOBUILD="misc/foo@default"
EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
EXPECTED_LISTED="${LISTPORTS}"
EXPECTED_BUILT="${EXPECTED_TOBUILD}"
do_bulk ${LISTPORTS}
assert 0 $? "Bulk should pass"
# XXX: misc/foo@default fails to be queued here due to trimming packages. This is what pkg-incremental queue ordering solves.
assert_bulk_queue_and_stats
assert_bulk_build_results
nowpackages="$(/bin/ls ${PACKAGES:?}/All)"
assert 0 "$?"
assert "${allpackages}" "${nowpackages}"
echo "------" | tee /dev/stderr
