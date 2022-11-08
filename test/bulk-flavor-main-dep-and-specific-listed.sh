LISTPORTS="misc/freebsd-release-manifests@FOO ports-mgmt/poudriere-devel-dep-DEFAULT"
OVERLAYS="omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_QUEUED="misc/foo misc/freebsd-release-manifests misc/freebsd-release-manifests@FOO ports-mgmt/pkg ports-mgmt/poudriere-devel-dep-DEFAULT"
EXPECTED_LISTED="misc/freebsd-release-manifests@FOO ports-mgmt/poudriere-devel-dep-DEFAULT"

assert_bulk_queue_and_stats
