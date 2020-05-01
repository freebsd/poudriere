LISTPORTS="ports-mgmt/poudriere-devel-dep-INVALID"
OVERLAYS="omnibus"
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 1 $? "Bulk should fail due to nonexistent FLAVOR"
