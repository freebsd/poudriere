#! /bin/sh

# first depends on a specific flavor
# second depends on the default flavor
# The order matters here since listed_ports does a sort -u. The specific
# FLAVOR dependency MUST come first to hit the bug.
#
#
# bulk-flavor-metadata-queue-ordering.sh Not enough, consider:
# + firefox depends on databases/py-sqlite3
#  -> gqueue
# + zenmap depends on databases/py-sqlite3@py27
#  -> mqueue
#  -> fqueue
# + devel/foo depends on devel/bar@flavor
#  -> mqueue
#  -> gqueue
# Now we find that py-sqlite3 depends on devel/bar (default)
#  -> gqueue
#   -> ERROR: Already looked up
#
# devel-dep-FOO depends on freebsd-release-manifests@FOO
# zzzz depends on freebsd-release-manifests (DEFAULT)
# yyyy depends on devel/foo@FLAV
# 2nd pass:
# freebsd-release-manifests@FOO depends on devel/foo (DEFAULT)
LISTPORTS="ports-mgmt/poudriere-devel-dep-FOO ports-mgmt/zzzz ports-mgmt/yyyy"
. common.bulk.sh

${SUDO} ${POUDRIEREPATH} -e ${POUDRIERE_ETC} bulk -n -CNt \
    -B "${BUILDNAME}" \
    -j "${JAILNAME}" -p "${PTNAME}" ${SETNAME:+-z "${SETNAME}"} \
    ${LISTPORTS}
assert 0 $? "Bulk should pass"

# Assert that only listed packages are in poudriere.ports.queued as 'listed'
assert_queued "listed" "${LISTPORTS}"

# Assert that all expected dependencies are in poudriere.ports.queued (since
# they do not exist yet)
expand_origin_flavors "${LISTPORTS}" expanded_LISTPORTS
list_all_deps "${expanded_LISTPORTS}" ALL_EXPECTED
assert_queued "" "${ALL_EXPECTED}"
