LISTPORTS="misc/freebsd-release-manifests@default ports-mgmt/poudriere-devel-dep-FOO"
OVERLAYS="omnibus"
. ./common.bulk.sh

do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_QUEUED="misc/foo@default misc/freebsd-release-manifests@default misc/freebsd-release-manifests@foo ports-mgmt/pkg ports-mgmt/poudriere-devel-dep-FOO"
EXPECTED_LISTED="misc/freebsd-release-manifests@default ports-mgmt/poudriere-devel-dep-FOO"

assert_bulk_queue_and_stats
assert_bulk_dry_run
