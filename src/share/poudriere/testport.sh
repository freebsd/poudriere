#!/bin/sh
set -e

usage() {
	echo "poudriere testport [parameters] [options]

Parameters:
    -o origin   -- Specify an origin in the portstree

Options:
    -c          -- Run make config for the given port
    -J n        -- Run n jobs in parallel for dependencies
    -j name     -- Run inside the given jail
    -i          -- Interactive mode. Enter jail for interactive testing and automatically cleanup when done.
    -I          -- Advanced Interactive mode. Leaves jail running with port installed after test.
    -n          -- No custom prefix
    -p tree     -- Specify the path to the portstree
    -s          -- Skip sanity checks
    -v          -- Be verbose; show more information. Use twice to enable debug output"
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
CONFIGSTR=0
. ${SCRIPTPREFIX}/common.sh
NOPREFIX=0
SETNAME=""
SKIPSANITY=0
INTERACTIVE_MODE=0
PTNAME="default"

while getopts "o:cnj:J:iIp:svz:" FLAG; do
	case "${FLAG}" in
		c)
			CONFIGSTR=1
			;;
		o)
			ORIGIN=${OPTARG}
			;;
		n)
			NOPREFIX=1
			;;
		j)
			jail_exists ${OPTARG} || err 1 "No such jail: ${OPTARG}"
			JAILNAME="${OPTARG}"
			;;
		J)
			PARALLEL_JOBS=${OPTARG}
			;;
		i)
			INTERACTIVE_MODE=1
			;;
		I)
			INTERACTIVE_MODE=2
			;;
		p)
			PTNAME=${OPTARG}
			;;
		s)
			SKIPSANITY=1
			;;
		z)
			[ -n "${OPTARG}" ] || err 1 "Empty set name"
			SETNAME="${OPTARG}"
			;;
		v)
			VERBOSE=$((${VERBOSE:-0} + 1))
			;;
		*)
			usage
			;;
	esac
done

test -z ${ORIGIN} && usage

export SKIPSANITY

test -z "${JAILNAME}" && err 1 "Don't know on which jail to run please specify -j"

MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
MASTERMNT=${POUDRIERE_DATA}/build/${MASTERNAME}/ref
export MASTERNAME
export MASTERMNT
export POUDRIERE_BUILD_TYPE=testport

jail_start ${JAILNAME} ${PTNAME} ${SETNAME}

LISTPORTS=$(list_deps ${ORIGIN} )
prepare_ports

markfs prepkg ${MASTERMNT}
log=$(log_path)

if ! POUDRIERE_BUILD_TYPE=bulk parallel_build ${JAILNAME} ${PTNAME} ${SETNAME} ; then
	failed=$(bget ports.failed | awk '{print $1 ":" $2 }' | xargs echo)
	skipped=$(bget ports.skipped | awk '{print $1}' | sort -u | xargs echo)
	nbignored=$(bget stats_failed)
	nbskipped=$(bget stats_skipped)

	cleanup

	msg "Depends failed to build"
	msg "Failed ports: ${failed}"
	[ -n "${skipped}" ] && 	msg "Skipped ports: ${skipped}"

	exit 1
fi

bset status "depends:"

unmarkfs prepkg ${MASTERMNT}

jail -c path=${MASTERMNT} command=make -C /usr/ports/${ORIGIN} pkg-depends extract-depends \
	fetch-depends patch-depends build-depends lib-depends

bset status "testing:"

[ -n "${mnt}" ] || err 1 "mnt not set"

PKGNAME=`jail -c path=${MASTERMNT} command=make -C /usr/ports/${ORIGIN} -VPKGNAME`
LOCALBASE=`jail -c path=${MASTERMNT} command=make -C /usr/ports/${ORIGIN} -VLOCALBASE`
PREFIX=${LOCALBASE}
if [ "${USE_PORTLINT}" = "yes" ]; then
	[ ! -x `which portlint` ] && err 2 "First install portlint if you want USE_PORTLINT to work as expected"
	msg "Portlint check"
	set +e
	cd ${mnt}//usr/ports/${ORIGIN} && PORTSDIR="${PORTSDIR}" portlint -C | tee $(log_path)/${PKGNAME}.portlint.log
	set -e
fi
[ ${NOPREFIX} -ne 1 ] && PREFIX="${BUILDROOT:-/prefix}/`echo ${PKGNAME} | tr '[,+]' _`"
PORT_FLAGS="NO_DEPENDS=yes PREFIX=${PREFIX}"
msg "Building with flags: ${PORT_FLAGS}"
[ $CONFIGSTR -eq 1 ] && jail -c path=${MASTERNAME} command=env TERM=${SAVED_TERM} make -C /usr/ports/${ORIGIN} config

if [ -d ${mnt}${PREFIX} ]; then
	msg "Removing existing ${PREFIX}"
	[ "${PREFIX}" != "${LOCALBASE}" ] && rm -rf ${mnt}${PREFIX}
fi

msg "Populating PREFIX"
mkdir -p ${mnt}${PREFIX}
jail -c path=${MASTERMNT} command=mtree -q -U -f /usr/ports/Templates/BSD.local.dist -d -e -p ${PREFIX} >/dev/null

PKGENV="PACKAGES=/tmp/pkgs PKGREPOSITORY=/tmp/pkgs"
mkdir -p ${mnt}/tmp/pkgs
PORTTESTING=yes
export DEVELOPER_MODE=yes
log_start $(log_path)/${PKGNAME}.log
buildlog_start /usr/ports/${ORIGIN}
if ! build_port /usr/ports/${ORIGIN}; then
	failed_status=$(jget ${MASTERNAME} status)
	failed_phase=${failed_status%:*}

	save_wrkdir "${PKGNAME}" "/usr/ports/${ORIGIN}" "${failed_phase}" || :
	exit 1
fi

msg "Installing from package"
jail -c path=${MASTERMNT} command=${PKG_ADD} /tmp/pkgs/${PKGNAME}.${PKG_EXT}

msg "Cleaning up"
jail -c path=${MASTERMNT} command=make -C /usr/ports/${ORIGIN} clean

if [ $INTERACTIVE_MODE -eq 1 ]; then
	msg "Entering interactive test mode. Type 'exit' when done."
	jail -c path=${MASTERMNT} command=env -i TERM=${SAVED_TERM} PACKAGESITE="file:///usr/ports/packages" /usr/bin/login -fp root
elif [ $INTERACTIVE_MODE -eq 2 ]; then
	msg "Leaving jail ${MASTERNAME} running, mounted at ${mnt} for interactive run testing"
	msg "To enter jail: jexec ${MASTERNAME} /bin/sh"
	msg "To stop jail: poudriere jail -k -j ${MASTERNAME}"
	CLEANING_UP=1
	exit 0
fi

msg "Deinstalling package"
jail -c path=${MASTERMNT} command=${PKG_DELETE} ${PKGNAME}

msg "Removing existing ${PREFIX} dir"
buildlog_stop /usr/ports/${ORIGIN}
log_stop $(log_path)/${PKGNAME}.log

cleanup
set +e

exit 0
