FLAVOR_DEFAULT_ALL=yes
# Incidentally this is a good test of include_poudriere_confs too

LISTPORTS="misc/freebsd-release-manifests ports-mgmt/poudriere-devel-dep-FOO"
OVERLAYS="omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

assert_bulk_queue_and_stats
