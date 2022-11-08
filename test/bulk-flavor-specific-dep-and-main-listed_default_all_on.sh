FLAVOR_DEFAULT_ALL=yes
# Incidentally this is a good test of include_poudriere_confs too

LISTPORTS="misc/freebsd-release-manifests ports-mgmt/poudriere-devel-dep-FOO"
OVERLAYS="omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

EXPECTED_QUEUED="misc/foo@- misc/freebsd-release-manifests misc/freebsd-release-manifests@BAR misc/freebsd-release-manifests@FOO ports-mgmt/pkg ports-mgmt/poudriere-devel-dep-FOO"
EXPECTED_LISTED="misc/freebsd-release-manifests misc/freebsd-release-manifests@BAR misc/freebsd-release-manifests@FOO ports-mgmt/poudriere-devel-dep-FOO"

assert_bulk_queue_and_stats
