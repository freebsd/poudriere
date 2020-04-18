#! /bin/sh

LISTPORTS="ports-mgmt/poudriere-devel-dep-INVALID"
. common.bulk.sh

${SUDO} ${POUDRIEREPATH} -e ${POUDRIERE_ETC} bulk -n -CNt \
    -B "${BUILDNAME}" \
    -j "${JAILNAME}" -p "${PTNAME}" ${SETNAME:+-z "${SETNAME}"} \
    ${LISTPORTS}
assert 1 $? "Bulk should fail due to nonexistent FLAVOR"
