LISTPORTS="misc/freebsd-release-manifests@FOO ports-mgmt/poudriere-devel-dep-FOO misc/freebsd-release-manifests@nonexistent"
OVERLAYS="omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 1 $? "Bulk should fail due to bad nonexistent flavor"
