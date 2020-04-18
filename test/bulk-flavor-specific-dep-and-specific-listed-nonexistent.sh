#! /bin/sh

LISTPORTS="misc/freebsd-release-manifests@FOO ports-mgmt/poudriere-devel-dep-FOO misc/freebsd-release-manifests@nonexistent"
. common.bulk.sh

${SUDO} ${POUDRIEREPATH} -e ${POUDRIERE_ETC} bulk -n -CNt \
    -B "${BUILDNAME}" \
    -j "${JAILNAME}" -p "${PTNAME}" ${SETNAME:+-z "${SETNAME}"} \
    ${LISTPORTS}
assert 1 $? "Bulk should fail due to bad nonexistent flavor"
