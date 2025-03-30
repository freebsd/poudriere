FLAVOR_DEFAULT_ALL=no

LISTPORTS="misc/foo-FLAVORS-unsorted@depignored"
OVERLAYS="overlay omnibus"
. ./common.bulk.sh

do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

# With misc/foo-FLAVORS-unsorted@depignored we should get a skip
# on the listed port since we explicitly requested it. The dependency
# will be ignored and cause the listed to skip.
EXPECTED_IGNORED="misc/foo-dep-FLAVORS-unsorted@depignored"
EXPECTED_SKIPPED="misc/foo-FLAVORS-unsorted@depignored"
EXPECTED_TOBUILD="ports-mgmt/pkg"
EXPECTED_QUEUED="${EXPECTED_TOBUILD} ${EXPECTED_IGNORED} ${EXPECTED_SKIPPED}"
EXPECTED_LISTED="misc/foo-FLAVORS-unsorted@depignored"

assert_bulk_queue_and_stats
assert_bulk_dry_run
