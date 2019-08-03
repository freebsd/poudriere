#! /bin/sh

LISTPORTS="ports-mgmt/poudriere-devel ports-mgmt/poudriere-devel-IGNORED misc/foo"
# ports-mgmt/poudriere-devel-dep-IGNORED should be IGNORED.
# misc/foo should show up.

. common.bulk.sh

${SUDO} ${POUDRIEREPATH} -e ${POUDRIERE_ETC} bulk -n -CNt \
    -B "${BUILDNAME}" \
    -j "${JAILNAME}" -p "${PTNAME}" ${SETNAME:+-z "${SETNAME}"} \
    ${LISTPORTS}
assert 0 $? "Bulk should pass"

# Assert the non-ignored ports list is right
assert "ports-mgmt/poudriere-devel misc/foo" "${LISTPORTS_NOIGNORED}" "LISTPORTS_NOIGNORED should match"

# Assert that IGNOREDPORTS was populated by the framework right.
assert "ports-mgmt/poudriere-devel-IGNORED" \
    "${IGNOREDPORTS-null}" "IGNOREDPORTS should match"

# Assert that skipped ports are right
assert "" "${SKIPPEDPORTS-null}" "SKIPPEDPORTS should match"

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
