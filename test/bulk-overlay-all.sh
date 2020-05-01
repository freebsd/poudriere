ALL=1
OVERLAYS="overlay omnibus"
. common.bulk.sh

do_bulk -n -a
assert 0 $? "Bulk should pass"

# Assert that we found the right misc/foo
ret=0
hash_get originspec-pkgname "misc/foo" pkgname || ret=$?
assert 0 "${ret}" "Cannot find pkgname for misc/foo"
assert "foo-OVERLAY-20161010" "${pkgname}" "misc/foo didn't find the overlay version"

EXPECTED_IGNORED="misc/foo@IGNORED_OVERLAY ports-mgmt/poudriere-devel-IGNORED ports-mgmt/poudriere-devel-IGNORED-and-skipped"
EXPECTED_SKIPPED="ports-mgmt/poudriere-devel-dep-IGNORED ports-mgmt/poudriere-devel-dep2-IGNORED"
assert_bulk_queue_and_stats
