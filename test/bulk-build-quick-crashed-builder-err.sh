LISTPORTS="ports-mgmt/pkg misc/foo"
OVERLAYS="omnibus"
. ./common.bulk.sh

# Let pkg build or we get unrelated failures in build_repo.
set_poudriere_conf <<-EOF
FP_BUILD_PKG_ERR_PKGNAMES=foo
# Disable crashed build collection as we want to ensure the token is returned.
# If the token is NOT returned (assuming err() worked) then the test will
# timeout. err() working is checked with EXPECTED_CRASHED+bulk $? later.
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
EXPECTED_FAILED="${EXPECTED_CRASHED}:crashed"
do_bulk -c ${LISTPORTS}
assert 1 $? "Bulk should fail due to crashed build"
assert_bulk_queue_and_stats
assert_bulk_build_results

_log_path log || err 99 "Unable to determine logdir"
assert_ret 0 [ -r "${log:?}/.poudriere.status.01.journal%" ]
assert_ret 0 \
    grep "crashed:err:build_pkg: FP_BUILD_PKG_ERR_PKGNAME match on foo-" \
    "${log:?}/.poudriere.status.01.journal%"
