#! /bin/sh

THISDIR=$(realpath $(dirname $0))
PORTSDIR="${THISDIR}/ports-dep-args"

LISTPORTS="ports-mgmt/poudriere-devel-bad-dep_args"
. common.bulk.sh

${SUDO} ${POUDRIEREPATH} -e ${POUDRIERE_ETC} bulk -n -CNt \
    -B "${BUILDNAME}" \
    -j "${JAILNAME}" -p "${PTNAME}" ${SETNAME:+-z "${SETNAME}"} \
    ${LISTPORTS}
assert 1 $? "Invalid DEPENDS_ARGS should be detected"

# Nothing should be queued
[ -f "${log}/.poudriere.ports.queued" ] && \
    [ -s "${log}/.poudriere.ports.queued" ]
assert 1 $? "Nothing should be queued for this bad DEPENDS_ARGS"
