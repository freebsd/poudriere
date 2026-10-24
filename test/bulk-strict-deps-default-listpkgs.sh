LISTPORTS="misc/foo-dep-invalid-flavor"
OVERLAYS="strict-deps"
. ./common.bulk.sh

LISTPKGSFILE="$(mktemp -t strict_deps_listpkgs)"
echo "${LISTPORTS}" | tr ' ' '\n' > "${LISTPKGSFILE}"

# With -f file, STRICT_DEPS defaults to 0 (lenient), same as -a: a
# dependency on a FLAVOR that does not exist for an otherwise valid origin
# should only ignore the affected port instead of aborting the whole
# build.
do_bulk -c -n -f "${LISTPKGSFILE}"
assert 0 $? "Bulk -f should not fail by default (STRICT_DEPS defaults to 0)"

EXPECTED_TOBUILD="ports-mgmt/pkg"
EXPECTED_QUEUED="${EXPECTED_TOBUILD} ${LISTPORTS}"
EXPECTED_IGNORED="${LISTPORTS}"
EXPECTED_SKIPPED=

assert_bulk_queue_and_stats
assert_bulk_dry_run

# -D forces STRICT_DEPS=1 even with -f: the same list must now fail.
do_bulk -c -n -D -f "${LISTPKGSFILE}"
assert 1 $? "Bulk -f -D should fail due to invalid FLAVOR dependency"

unlink "${LISTPKGSFILE}"
