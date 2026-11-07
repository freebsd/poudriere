LISTPORTS="misc/dup-a misc/dup-b"
OVERLAYS="strict-deps"
# Force sequential (non-parallel) gathering so which of the two
# same-PKGNAME ports is "first encountered" is deterministic.
JFLAG="1:1"
. ./common.bulk.sh

LISTPKGSFILE="$(mktemp -t strict_deps_dup_listpkgs)"
echo "${LISTPORTS}" | tr ' ' '\n' > "${LISTPKGSFILE}"

# misc/dup-a and misc/dup-b both have the same PKGNAME.
# With -f file, STRICT_DEPS defaults to 0 (lenient): the first one
# encountered is kept, the other is dropped instead of aborting the whole
# build.
do_bulk -c -n -f "${LISTPKGSFILE}"
assert 0 $? "Bulk -f should not fail by default on a duplicate PKGNAME (STRICT_DEPS defaults to 0)"

EXPECTED_TOBUILD="misc/dup-a ports-mgmt/pkg"
EXPECTED_QUEUED="${EXPECTED_TOBUILD}"
EXPECTED_IGNORED=
EXPECTED_SKIPPED=
EXPECTED_LISTED="misc/dup-a"

assert_bulk_queue_and_stats
assert_bulk_dry_run

# -D forces STRICT_DEPS=1 even with -f: the same list must now fail.
do_bulk -c -n -D -f "${LISTPKGSFILE}"
assert 1 $? "Bulk -f -D should fail due to the duplicate PKGNAME"

unlink "${LISTPKGSFILE}"
