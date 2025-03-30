LISTPORTS="misc/foo"
OVERLAYS="omnibus"
. ./common.bulk.sh

do_bulk -c -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

# Assert that we found the right misc/foo (not the overlay version)
ret=0
hash_get originspec-pkgname "misc/foo" pkgname || ret=$?
assert 0 "${ret}" "Cannot find pkgname for misc/foo"
assert "foo-20161010" "${pkgname}" "misc/foo found the overlay version maybe?"

EXPECTED_QUEUED="misc/foo@default ports-mgmt/pkg"
EXPECTED_LISTED="misc/foo@default"

assert_bulk_queue_and_stats
assert_bulk_dry_run
