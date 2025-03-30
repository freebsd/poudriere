LISTPORTS="misc/freebsd-release-manifests@foo ports-mgmt/poudriere-devel-dep-FOO misc/freebsd-release-manifests@nonexistent"
OVERLAYS="omnibus"
. ./common.bulk.sh

do_bulk -c -n ${LISTPORTS}
assert 1 $? "Bulk should fail due to bad nonexistent flavor"

EXPECTED_TOBUILD=
EXPECTED_QUEUED=
EXPECETD_IGNORED=
EXPECTED_SKIPPED=
EXPECTED_LISTED=

assert_bulk_queue_and_stats
assert_bulk_dry_run
