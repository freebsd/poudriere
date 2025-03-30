# This is dealing with an obscure error in origin_has_pkgbase() where
# a dependency is added to the flavorqueue but not any of the other
# FLAVORS. When an existing package is found with delete_old_pkg()
# it finds that it does not know the PKGNAME of every FLAVOR for
# the port.
LISTPORTS="ports-mgmt/poudriere-devel-dep-FOO"
OVERLAYS="omnibus"
. ./common.bulk.sh

# Build pkg only once as this is a long test otherwise.
do_bulk ports-mgmt/pkg
assert 0 "$?" "bulk for pkg should pass"

set_poudriere_conf <<-EOF
EOF

do_pkgclean -y ports-mgmt/pkg
assert 0 "$?" "Pkgclean should pass"

LISTPORTS="ports-mgmt/poudriere-devel-dep-FOO"
EXPECTED_IGNORED=""
EXPECTED_SKIPPED=
EXPECTED_TOBUILD="${LISTPORTS} misc/freebsd-release-manifests@foo misc/foo@default"
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
allpackages="$(/bin/ls ${PACKAGES:?}/All/)"
assert 0 "$?"
echo "------" | tee /dev/stderr

# Do the same again. 'BAR' being before 'FOO' in the
# misc/freebsd-release-manifests FLAVORS list and us only
# needing the FOO FLAVOR means we did not lookup the BAR PKGNAME.
# We likely did lookup the DEFAULT PKGNAME though.
# A proper fix means we looked up everything or origin_has_pkgbase()
# does not care about the missing BAR PKGNAME.

EXPECTED_BUILT=
EXPECTED_IGNORED=""
EXPECTED_SKIPPED=
EXPECTED_TOBUILD=
EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
EXPECTED_LISTED="${LISTPORTS}"
EXPECTED_BUILT=
do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_dry_run
echo "------" | tee /dev/stderr

do_bulk ${LISTPORTS}
assert 0 $? "Bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
echo "------" | tee /dev/stderr

# All packages should still exist. Nothing changed. We just may have
# tried looking up an unused FLAVOR-PKGNAME.
nowpackages="$(/bin/ls ${PACKAGES:?}/All/)"
assert 0 "$?"
assert "${allpackages}" "${nowpackages}"
