# Common setup for bulk test runs

# Need to trim environment of anything that may taint our top-level port var
# fetching.
while read var; do
	unset ${var}
done <<-EOF
$(env | egrep '^(WITH_|PORT)')
EOF
export __MAKE_CONF=/dev/null
export SRCCONF=/dev/null
export SRC_ENV_CONF=/dev/null

. common.sh

assert_not "" "${LISTPORTS}" "LISTPORTS empty"
echo "Building: $(echo ${LISTPORTS})"

: ${BUILDNAME:=${0%.sh}}
POUDRIERE="${POUDRIEREPATH} -e /usr/local/etc"
ARCH=$(uname -p)
JAILNAME="poudriere-10${ARCH}"
JAIL_VERSION="10.3-RELEASE"
JAILMNT=$(${POUDRIERE} api "jget ${JAILNAME} mnt" 2>/dev/null || echo)
if [ -z "${JAILMNT}" ]; then
	echo "Setting up jail for testing..." >&2
	if ! ${POUDRIERE} jail -c -j "${JAILNAME}" \
	    -v "${JAIL_VERSION}" -a ${ARCH}; then
		echo "SKIP: Cannot setup jail with Poudriere" >&2
		exit 0
	fi
	JAILMNT=$(${POUDRIERE} api "jget ${JAILNAME} mnt" 2>/dev/null || echo)
	if [ -z "${JAILMNT}" ]; then
		echo "SKIP: Failed fetching mnt for new jail in Poudriere" >&2
		exit 0
	fi
	echo "Done setting up test jail" >&2
	echo >&2
fi

. ${SCRIPTPREFIX}/common.sh

PORTSDIR=${THISDIR}/ports
PTMNT="${PORTSDIR}"
: ${JAILNAME:=bulk}
: ${PTNAME:=test}
: ${SETNAME:=}
export PORT_DBDIR=/dev/null

set -e

# Import local ports tree
pset "${PTNAME}" mnt "${PTMNT}"
pset "${PTNAME}" method "-"

# Import jail
jset "${JAILNAME}" version "${JAIL_VERSION}"
jset "${JAILNAME}" timestamp $(clock -epoch)
jset "${JAILNAME}" arch "${ARCH}"
jset "${JAILNAME}" mnt "${JAILMNT}"
jset "${JAILNAME}" method "null"

MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
_mastermnt MASTERMNT
export POUDRIERE_BUILD_TYPE=bulk
_log_path log

echo -n "Pruning previous logs..."
${POUDRIEREPATH} -e ${POUDRIERE_ETC} logclean -B "${BUILDNAME}" -ay >/dev/null
echo " done"
set +e
