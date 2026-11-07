# A port gets a new RUN_DEPENDS on a FLAVOR that does not exist.  This is
# the same class of problem as bulk-strict-deps-default-all.sh, but seen
# via the incremental "did dependencies change" check in _delete_old_pkg()
# against an *already-built* package, rather than during the initial
# queue computation.
LISTPORTS="misc/inc-dep-flavor-consumer"
OVERLAYS="strict-deps"
. ./common.bulk.sh

do_bulk -d ${LISTPORTS}
assert 0 $? "Initial bulk build should pass"

set_make_conf <<-EOF
ADD_BOGUS_FLAVOR_DEP=yes
EOF

# With STRICT_DEPS=0 (-d, lenient), the new dependency on a nonexistent
# FLAVOR should only cause the existing package to be deleted (as an
# unresolvable "new dependency") and the port ignored, not abort the
# whole run.
do_bulk -d ${LISTPORTS}
assert 0 $? "Bulk should pass: unresolvable new dependency should only be ignored (STRICT_DEPS=0)"

EXPECTED_IGNORED="${LISTPORTS}"
EXPECTED_SKIPPED=
EXPECTED_TOBUILD=
EXPECTED_QUEUED="${EXPECTED_TOBUILD} ${EXPECTED_IGNORED} ${EXPECTED_SKIPPED}"
EXPECTED_LISTED="${LISTPORTS}"

assert_bulk_queue_and_stats

# -D forces STRICT_DEPS=1: the same tree must now fail outright.
do_bulk -D ${LISTPORTS}
assert 1 $? "Bulk -D should fail due to the nonexistent FLAVOR dependency"
