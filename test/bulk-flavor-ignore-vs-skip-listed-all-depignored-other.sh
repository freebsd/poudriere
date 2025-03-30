FLAVOR_DEFAULT_ALL=no
FLAVOR_DEFAULT=-

LISTPORTS="misc/foo-all-DEPIGNORED@flav"
OVERLAYS="overlay omnibus"
. ./common.bulk.sh

do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_IGNORED="misc/foo-dep-FLAVORS-unsorted@depignored"
EXPECTED_SKIPPED="misc/foo-all-DEPIGNORED@flav"
EXPECTED_TOBUILD="ports-mgmt/pkg"
EXPECTED_QUEUED="${EXPECTED_TOBUILD} ${EXPECTED_IGNORED} ${EXPECTED_SKIPPED}"
EXPECTED_LISTED="misc/foo-all-DEPIGNORED@flav"

assert_bulk_queue_and_stats
assert_bulk_dry_run
