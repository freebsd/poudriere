LISTPORTS="misc/foop-IGNORED ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-IGNORED-and-skipped"
# IGNORE should take precedence over skipped.
OVERLAYS="omnibus"
JFLAG=1:1
. common.bulk.sh

do_bulk -n ${LISTPORTS}
assert 0 $? "Bulk should pass"

# ports-mgmt/poudriere-devel-IGNORED is a dependency which is also ignored but
# because we are ignoring ports-mgmt/poudriere-devel-IGNORED-and-skipped we
# should not bother processing ports-mgmt/poudriere-devel-IGNORED at all.
# Meaning poudriere-devel-IGNORED should not appear in the IGNORE list.
# misc/foop-IGNORED should not cause a skip here either.
EXPECTED_IGNORED="misc/foop-IGNORED ports-mgmt/poudriere-devel-IGNORED-and-skipped"
EXPECTED_SKIPPED=
EXPECTED_QUEUED="misc/freebsd-release-manifests@default ports-mgmt/pkg ports-mgmt/poudriere-devel"
EXPECTED_LISTED="misc/foop-IGNORED ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-IGNORED-and-skipped"

assert_bulk_queue_and_stats
