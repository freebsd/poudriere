LISTPORTS="misc/freebsd-release-manifests@foo ports-mgmt/poudriere-devel-dep-FOO misc/freebsd-release-manifests@nonexistent"
OVERLAYS="omnibus"
. ./common.bulk.sh

do_bulk -c -n -d ${LISTPORTS}
assert 0 $? "Bulk should not fail due to bad nonexistent flavor with -d"

EXPECTED_TOBUILD="ports-mgmt/pkg misc/foo@default misc/freebsd-release-manifests@foo ports-mgmt/poudriere-devel-dep-FOO"
EXPECTED_QUEUED="ports-mgmt/pkg misc/foo@default misc/freebsd-release-manifests@foo ports-mgmt/poudriere-devel-dep-FOO"
EXPECETD_IGNORED=
EXPECTED_SKIPPED=
EXPECTED_LISTED="misc/freebsd-release-manifests@foo ports-mgmt/poudriere-devel-dep-FOO"

assert_bulk_queue_and_stats
assert_bulk_dry_run

do_bulk -c -n -D ${LISTPORTS}
assert 1 $? "Bulk should fail due to bad nonexistent flavor with -D"

EXPECTED_TOBUILD=
EXPECTED_QUEUED=
EXPECETD_IGNORED=
EXPECTED_SKIPPED=
EXPECTED_LISTED=

assert_bulk_queue_and_stats
assert_bulk_dry_run
