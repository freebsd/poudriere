#!/bin/sh
set -e

usage() {
	echo "poudriere testport parameters [options]

Parameters:
    -d path     -- Specify on which port we work
    -o origin   -- Specify an origin in the portstree

Options:
    -c          -- Run make config for the given port
    -D          -- Debug mode, dislay more information
    -J n        -- Run n jobs in parallel for dependencies
    -j name     -- Run only inside the given jail
    -n          -- No custom prefix
    -p tree     -- Specify on which portstree we work"
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
CONFIGSTR=0
. ${SCRIPTPREFIX}/common.sh
NOPREFIX=0
SETNAME=""
SKIPSANITY=0
PTNAME="default"

while getopts "Dd:o:cnj:J:p:sz:" FLAG; do
	case "${FLAG}" in
		c)
			CONFIGSTR=1
			;;
		d)
			HOST_PORTDIRECTORY=`realpath ${OPTARG}`
			;;
		D)
			DEBUG_MODE=1
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
	HOST_PORTDIRECTORY=`porttree_get_base ${PTNAME}`/ports/${ORIGIN}
	PORTDIRECTORY="/usr/ports/${ORIGIN}"
fi

test -z "${JAILNAME}" && err 1 "Don't know on which jail to run please specify -j"

PKGDIR=${POUDRIERE_DATA}/packages/${JAILNAME}-${PTNAME}${SETNAME}

JAILFS=`jail_get_fs ${JAILNAME}`
JAILMNT=`jail_get_base ${JAILNAME}`

export POUDRIERE_BUILD_TYPE=testport

jail_start

prepare_jail

if [ -z ${ORIGIN} ]; then
	mkdir -p ${JAILMNT}/${PORTDIRECTORY}
	mount -t nullfs ${HOST_PORTDIRECTORY} ${JAILMNT}/${PORTDIRECTORY}
fi

LISTPORTS=$(list_deps ${PORTDIRECTORY} )
prepare_ports

zfs snapshot ${JAILFS}@prepkg

if ! POUDRIERE_BUILD_TYPE=bulk parallel_build; then
	failed=$(cat ${JAILMNT}/poudriere/ports.failed | awk '{print $1 ":" $2 }' | xargs echo)
	skipped=$(cat ${JAILMNT}/poudriere/ports.skipped | awk '{print $1}' | xargs echo)
	nbfailed=$(zget stats_failed)
	nbskipped=$(zget stats_skipped)

	cleanup

	msg "Depends failed to build"
	msg "Failed ports: ${failed}"
	[ -n "${skipped}" ] && 	msg "Skipped ports: ${skipped}"

	exit 1
fi

zset status "depends:"

zfs destroy -r ${JAILFS}@prepkg

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
msg "Cleaning workspace"
injail make -C ${PORTDIRECTORY} clean
[ $CONFIGSTR -eq 1 ] && injail make -C ${PORTDIRECTORY} config

if [ -d ${JAILMNT}${PREFIX} ]; then
	msg "Removing existing ${PREFIX}"
	[ "${PREFIX}" != "${LOCALBASE}" ] && rm -rf ${JAILMNT}${PREFIX}
fi

msg "Populating PREFIX"
mkdir -p ${JAILMNT}${PREFIX}
injail /usr/sbin/mtree -q -U -f /usr/ports/Templates/BSD.local.dist -d -e -p ${PREFIX} >/dev/null

[ $ZVERSION -lt 28 ] && \
	find ${JAILMNT}${LOCALBASE}/ -type d | sed "s,^${JAILMNT}${LOCALBASE}/,," | sort > ${JAILMNT}${PREFIX}.PLIST_DIRS.before

PKGENV="PACKAGES=/tmp/pkgs PKGREPOSITORY=/tmp/pkgs"
mkdir -p ${JAILMNT}/tmp/pkgs
PORTTESTING=yes
export DEVELOPER_MODE=yes
log_start $(log_path)/${PKGNAME}.log
buildlog_start ${PORTDIRECTORY}
build_port ${PORTDIRECTORY}

msg "Installing from package"
injail ${PKG_ADD} /tmp/pkgs/${PKGNAME}.${PKG_EXT}
msg "Deinstalling package"
injail ${PKG_DELETE} ${PKGNAME}

msg "Cleaning up"
injail make -C ${PORTDIRECTORY} clean

msg "Removing existing ${PREFIX} dir"
[ "${PREFIX}" != "${LOCALBASE}" ] && rm -rf ${JAILMNT}${PREFIX} ${JAILMNT}${PREFIX}.PLIST_DIRS.before ${JAILMNT}${PREFIX}.PLIST_DIRS.after
buildlog_stop ${PORTDIRECTORY}
log_stop $(log_path)/${PKGNAME}.log

cleanup
set +e

exit 0
