LISTPORTS="misc/freebsd-release-manifests@default ports-mgmt/poudriere-devel-dep-FOO"
OVERLAYS="omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_QUEUED="misc/foo misc/freebsd-release-manifests misc/freebsd-release-manifests@foo ports-mgmt/pkg ports-mgmt/poudriere-devel-dep-FOO"
EXPECTED_LISTED="misc/freebsd-release-manifests ports-mgmt/poudriere-devel-dep-FOO"

assert_bulk_queue_and_stats
