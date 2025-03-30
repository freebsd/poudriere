LISTPORTS="ports-mgmt/poudriere-devel-porttesting"
OVERLAYS="omnibus porttesting"
. ./common.bulk.sh

do_pkgclean -y -A
assert 0 "$?" "Pkgclean should pass"

EXPECTED_IGNORED=""
EXPECTED_SKIPPED=
EXPECTED_TOBUILD="ports-mgmt/pkg ports-mgmt/poudriere-devel-porttesting"
EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
EXPECTED_LISTED="${LISTPORTS}"
EXPECTED_BUILT=
do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_dry_run
echo "------" | tee /dev/stderr

EXPECTED_BUILT="${EXPECTED_TOBUILD}"
do_bulk -c ${LISTPORTS}
assert 0 $? "Bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_build_results
allpackages="$(/bin/ls ${PACKAGES:?}/All/)"
assert 0 "$?"
echo "------" | tee /dev/stderr

# Now test with -t which should fail due to bad plist.
EXPECTED_TOBUILD="ports-mgmt/poudriere-devel-porttesting"
EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
EXPECTED_BUILT=""
EXPECTED_FAILED="ports-mgmt/poudriere-devel-porttesting"
do_bulk -C -t ${LISTPORTS}
assert 1 $? "Bulk should fail"
assert_bulk_queue_and_stats
assert_bulk_build_results
allpackages="$(/bin/ls ${PACKAGES:?}/All/)"
assert 0 "$?"
echo "------" | tee /dev/stderr
