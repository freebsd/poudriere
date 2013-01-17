#!/bin/sh
set -e

usage() {
	echo "poudriere testport [parameters] [options]

Parameters:
    -d path     -- Specify the port to test
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

while getopts "d:o:cnj:J:iIp:svz:" FLAG; do
	case "${FLAG}" in
		c)
			CONFIGSTR=1
			;;
		d)
			HOST_PORTDIRECTORY=`realpath ${OPTARG}`
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
			SETNAME="-${OPTARG}"
			;;
		v)
			VERBOSE=$((${VERBOSE:-0} + 1))
			;;
		*)
			usage
			;;
	esac
done

test -z ${HOST_PORTDIRECTORY} && test -z ${ORIGIN} && usage

export SKIPSANITY

if [ -z ${ORIGIN} ]; then
	PORTDIRECTORY=`basename ${HOST_PORTDIRECTORY}`
else
	HOST_PORTDIRECTORY=$(pget ${PTNAME} mnt)/ports/${ORIGIN}
	PORTDIRECTORY="/usr/ports/${ORIGIN}"
fi

test -z "${JAILNAME}" && err 1 "Don't know on which jail to run please specify -j"

PKGDIR=${POUDRIERE_DATA}/packages/${JAILNAME}-${PTNAME}${SETNAME}

JAILFS=$(jget ${JAILNAME} fs)
JAILMNT=$(jget ${JAILNAME} mnt)

export POUDRIERE_BUILD_TYPE=testport

jail_start

prepare_jail

if [ -z ${ORIGIN} ]; then
	mkdir -p ${JAILMNT}/${PORTDIRECTORY}
	mount -t nullfs ${HOST_PORTDIRECTORY} ${JAILMNT}/${PORTDIRECTORY}
fi

LISTPORTS=$(list_deps ${PORTDIRECTORY} )
prepare_ports

markfs prepkg ${JAILMNT}

if ! POUDRIERE_BUILD_TYPE=bulk parallel_build; then
	failed=$(cat ${JAILMNT}/poudriere/ports.failed | awk '{print $1 ":" $2 }' | xargs echo)
	skipped=$(cat ${JAILMNT}/poudriere/ports.skipped | awk '{print $1}' | sort -u | xargs echo)
	nbfailed=$(zget stats_failed)
	nbskipped=$(zget stats_skipped)

	cleanup

	msg "Depends failed to build"
	msg "Failed ports: ${failed}"
	[ -n "${skipped}" ] && 	msg "Skipped ports: ${skipped}"

	exit 1
fi

zset status "depends:"

unmaekfs prepkg ${JAILMNT}

injail make -C ${PORTDIRECTORY} pkg-depends extract-depends \
	fetch-depends patch-depends build-depends lib-depends

zset status "testing:"

PKGNAME=`injail make -C ${PORTDIRECTORY} -VPKGNAME`
LOCALBASE=`injail make -C ${PORTDIRECTORY} -VLOCALBASE`
PREFIX=${LOCALBASE}
if [ "${USE_PORTLINT}" = "yes" ]; then
	[ ! -x `which portlint` ] && err 2 "First install portlint if you want USE_PORTLINT to work as expected"
	msg "Portlint check"
	set +e
	cd ${JAILMNT}/${PORTDIRECTORY} && PORTSDIR="${PORTSDIR}" portlint -C | tee $(log_path)/${PKGNAME}.portlint.log
	set -e
fi
[ ${NOPREFIX} -ne 1 ] && PREFIX="${BUILDROOT:-/prefix}/`echo ${PKGNAME} | tr '[,+]' _`"
PORT_FLAGS="NO_DEPENDS=yes PREFIX=${PREFIX}"
msg "Building with flags: ${PORT_FLAGS}"
[ $CONFIGSTR -eq 1 ] && injail env TERM=${SAVED_TERM} make -C ${PORTDIRECTORY} config

if [ -d ${JAILMNT}${PREFIX} ]; then
	msg "Removing existing ${PREFIX}"
	[ "${PREFIX}" != "${LOCALBASE}" ] && rm -rf ${JAILMNT}${PREFIX}
fi

msg "Populating PREFIX"
mkdir -p ${JAILMNT}${PREFIX}
injail /usr/sbin/mtree -q -U -f /usr/ports/Templates/BSD.local.dist -d -e -p ${PREFIX} >/dev/null

PKGENV="PACKAGES=/tmp/pkgs PKGREPOSITORY=/tmp/pkgs"
mkdir -p ${JAILMNT}/tmp/pkgs
PORTTESTING=yes
export DEVELOPER_MODE=yes
log_start $(log_path)/${PKGNAME}.log
buildlog_start ${PORTDIRECTORY}
if ! build_port ${PORTDIRECTORY}; then
	failed_status=$(zget status)
	failed_phase=${failed_status%:*}

	save_wrkdir "${PKGNAME}" "${PORTDIRECTORY}" "${failed_phase}" || :
	exit 1
fi

msg "Installing from package"
injail ${PKG_ADD} /tmp/pkgs/${PKGNAME}.${PKG_EXT}

msg "Cleaning up"
injail make -C ${PORTDIRECTORY} clean

if [ $INTERACTIVE_MODE -eq 1 ]; then
	msg "Entering interactive test mode. Type 'exit' when done."
	injail env -i TERM=${SAVED_TERM} PACKAGESITE="file:///usr/ports/packages" /usr/bin/login -fp root
elif [ $INTERACTIVE_MODE -eq 2 ]; then
	msg "Leaving jail ${JAILNAME} running, mounted at ${JAILMNT} for interactive run testing"
	msg "To enter jail: jexec ${JAILNAME} /bin/sh"
	msg "To stop jail: poudriere jail -k -j ${JAILNAME}"
	CLEANING_UP=1
	exit 0
fi

msg "Deinstalling package"
injail ${PKG_DELETE} ${PKGNAME}

msg "Removing existing ${PREFIX} dir"
[ "${PREFIX}" != "${LOCALBASE}" ] && rm -rf ${JAILMNT}${PREFIX} ${JAILMNT}${PREFIX}.PLIST_DIRS.before ${JAILMNT}${PREFIX}.PLIST_DIRS.after
buildlog_stop ${PORTDIRECTORY}
log_stop $(log_path)/${PKGNAME}.log

cleanup
set +e

exit 0
