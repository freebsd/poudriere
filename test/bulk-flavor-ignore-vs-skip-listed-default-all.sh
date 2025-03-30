FLAVOR_DEFAULT_ALL=yes

LISTPORTS="misc/foo-FLAVORS-unsorted"
OVERLAYS="overlay omnibus"
. ./common.bulk.sh

do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

# With misc/foo-FLAVORS-unsorted@all nothing should be skipped.
# Everything should just be ignored.
EXPECTED_IGNORED="misc/foo-FLAVORS-unsorted@ignored misc/foo-FLAVORS-unsorted@depignored misc/foo-dep-FLAVORS-unsorted@depignored"
EXPECTED_SKIPPED=
EXPECTED_TOBUILD="misc/foo-FLAVORS-unsorted@- misc/foo-FLAVORS-unsorted@flav misc/foo-dep-FLAVORS-unsorted@- misc/foo-dep-FLAVORS-unsorted@flav ports-mgmt/pkg"
EXPECTED_QUEUED="${EXPECTED_TOBUILD} ${EXPECTED_IGNORED} ${EXPECTED_SKIPPED}"
EXPECTED_LISTED="misc/foo-FLAVORS-unsorted@default misc/foo-FLAVORS-unsorted@depignored misc/foo-FLAVORS-unsorted@flav misc/foo-FLAVORS-unsorted@ignored"

assert_bulk_queue_and_stats
assert_bulk_dry_run
