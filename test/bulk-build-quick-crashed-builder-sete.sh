LISTPORTS="ports-mgmt/pkg misc/foo"
OVERLAYS="omnibus"
. ./common.bulk.sh

# Let pkg build or we get unrelated failures in build_repo.
set_poudriere_conf <<-EOF
FP_BUILD_PKG_SETE_PKGNAMES=foo
# Disable crashed build collection as we want to ensure the token is returned.
# If the token is NOT returned (assuming set -e worked) then the test will
# timeout. set -e working is checked with EXPECTED_CRASHED+bulk $? later.
FP_BUILD_QUEUE_NO_CRASHED_COLLECTION=1
EOF

EXPECTED_IGNORED=
EXPECTED_INSPECTED=
EXPECTED_SKIPPED=
EXPECTED_TOBUILD="${LISTPORTS}"
EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
EXPECTED_LISTED="${LISTPORTS}"
EXPECTED_BUILT=
do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"
assert_bulk_queue_and_stats
assert_bulk_dry_run
echo "------" | tee /dev/stderr

EXPECTED_BUILT="ports-mgmt/pkg"
EXPECTED_CRASHED="misc/foo"
EXPECTED_FAILED="${EXPECTED_CRASHED}:starting"
do_bulk -c ${LISTPORTS}
assert 1 $? "Bulk should fail due to crashed build"
assert_bulk_queue_and_stats
assert_bulk_build_results
