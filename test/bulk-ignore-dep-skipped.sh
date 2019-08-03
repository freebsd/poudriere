#! /bin/sh

LISTPORTS="ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-dep-IGNORED"
# ports-mgmt/poudriere-devel-dep-IGNORED depends on ports-mgmt/poudriere-devel-IGNORED
# which is IGNORED.
# ports-mgmt/poudriere-devel-dep-IGNORED should be skipped.
# ports-mgmt/poudriere-devel-IGNORED depends on misc/foo but it should
# not show up at all.
. common.bulk.sh

${SUDO} ${POUDRIEREPATH} -e ${POUDRIERE_ETC} bulk -n -CNt \
    -B "${BUILDNAME}" \
    -j "${JAILNAME}" -p "${PTNAME}" ${SETNAME:+-z "${SETNAME}"} \
    ${LISTPORTS}
assert 0 $? "Bulk should pass"

# Assert the non-ignored ports list is right
assert "ports-mgmt/poudriere-devel" "${LISTPORTS_NOIGNORED}" "LISTPORTS_NOIGNORED should match"

# Assert that IGNOREDPORTS was populated by the framework right.
assert "ports-mgmt/poudriere-devel-IGNORED" \
    "${IGNOREDPORTS-null}" "IGNOREDPORTS should match"

# Assert that skipped ports are right
assert "ports-mgmt/poudriere-devel-dep-IGNORED" "${SKIPPEDPORTS-null}" "SKIPPEDPORTS should match"

# Assert that only listed packages are in poudriere.ports.queued as 'listed'
assert_queued "listed" "${LISTPORTS}"

# Assert the IGNOREd ports are tracked in .poudriere.ports.ignored
assert_ignored "${IGNOREDPORTS}"

# Assert that SKIPPED ports are right
assert_skipped "${SKIPPEDPORTS}"

# Assert that all expected dependencies are in poudriere.ports.queued (since
# they do not exist yet)
expand_origin_flavors "${LISTPORTS_NOIGNORED}" expanded_LISTPORTS_NOIGNORED
list_all_deps "${expanded_LISTPORTS_NOIGNORED}" ALL_EXPECTED
assert_queued "" "${ALL_EXPECTED}"

# Assert stats counts are right
assert_counts
