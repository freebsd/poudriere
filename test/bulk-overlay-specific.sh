#! /bin/sh

LISTPORTS="misc/foo"
OVERLAYS="overlay"
. common.bulk.sh

${SUDO} ${POUDRIEREPATH} -e ${POUDRIERE_ETC} bulk -n -CNt \
    -O "${OVERLAYS}" \
    -B "${BUILDNAME}" \
    -j "${JAILNAME}" -p "${PTNAME}" ${SETNAME:+-z "${SETNAME}"} \
    ${LISTPORTS}
assert 0 $? "Bulk should pass"

# Assert that only listed packages are in poudriere.ports.queued as 'listed'
assert_queued "listed" "${LISTPORTS}"

# Assert that we found the right misc/foo
ret=0
hash_get originspec-pkgname "misc/foo" pkgname || ret=$?
assert 0 "${ret}" "Cannot find pkgname for misc/foo"
assert "foo-OVERLAY-20161010" "${pkgname}" "misc/foo didn't find the overlay version"

# Assert that all expected dependencies are in poudriere.ports.queued (since
# they do not exist yet)
expand_origin_flavors "${LISTPORTS}" expanded_LISTPORTS
list_all_deps "${expanded_LISTPORTS}" ALL_EXPECTED
assert_queued "" "${ALL_EXPECTED}"

# Assert stats counts are right
assert_counts
exit 0
