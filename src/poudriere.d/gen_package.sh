#!/bin/sh
set -e

usage() {
	echo "poudriere genpkg parameters [options]"
cat <<EOF

Parameters:
    -d port     -- Relative path of the port we want to build
    -o origin   -- Specify an origin in the portstree

Options:
    -j name     -- Run only inside the given jail
    -p tree     -- Use portstree "tree"
EOF

	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
PTNAME="default"
. ${SCRIPTPREFIX}/common.sh

LOGS="${POUDRIERE_DATA}/logs"

while getopts "d:nj:o:p:" FLAG; do
	case "${FLAG}" in
		d)
			HOST_PORTDIRECTORY=`realpath ${OPTARG}`
			;;
		j)
			jail_exists ${OPTARG} || err 1 "No such jail: ${OPTARG}"
			JAILNAMES="${JAILNAMES} ${OPTARG}"
			;;
		o)
			ORIGIN=${OPTARG}
			;;
		p)
			PTNAME=${OPTARG}
			;;
		*)
			usage
			;;
	esac
done

test -z ${HOST_PORTDIRECTORY} && test -z ${ORIGIN} && usage

if [ -z "${ORIGIN}" ]; then
	PORTDIRECTORY=`basename ${HOST_PORTDIRECTORY}`
else
	HOST_PORTDIRECTORY=`port_get_base ${PTNAME}`/${ORIGIN}
	PORTDIRECTORY="/usr/ports/${ORIGIN}"
fi

PKGNAME=`make -C ${HOST_PORTDIRECTORY} -VPKGNAME`

test -z "${JAILNAMES}" && JAILNAMES=`jail_ls`

for JAILNAME in ${JAILNAMES}; do
	EXT=tbz
	JAILBASE=`jail_get_base ${JAILNAME}`
	JAILFS=`jail_get_fs ${JAILNAME}`
	PKGDIR=${POUDRIERE_DATA}/packages/${JAILNAME}
	jail_start ${JAILNAME}

	STATUS=1 #injail

	prepare_jail

	exec 3>&1 4>&2
	[ ! -e ${PIPE} ] && mkfifo ${PIPE}
	tee ${LOGS}/${PKGNAME}-${JAILNAME}.depends.log < ${PIPE} >&3 &
	tpid=$!
	exec > ${PIPE} 2>&1
	if [ -z ${ORIGIN} ]; then
		mkdir -p ${JAILBASE}/${PORTDIRECTORY}
		mount -t nullfs ${HOST_PORTDIRECTORY} ${JAILBASE}/${PORTDIRECTORY}
	fi

	LISTPORTS=$(injail make -C ${PORTDIRECTORY} missing)
	zfs snapshot ${JAILFS}@prepkg
	msg "Calculating ports order and dependencies"
	for port in `prepare_ports`; do
		build_pkg ${port}
		zfs rollback ${JAILFS}@prepkg
	done
	zfs destroy ${JAILFS}@prepkg
	injail make -C ${PORTDIRECTORY} extract-depends fetch-depends patch-depends build-depends lib-depends
	exec 1>&3 3>&- 2>&4 4>&-
	wait $tpid

	exec 3>&1 4>&2
	tee ${LOGS}/${PKGNAME}-${JAILNAME}.build.log < ${PIPE} >&3 &
	tpid=$!
	exec > ${PIPE} 2>&1
	PKGNAME=`injail make -C ${PORTDIRECTORY} -VPKGNAME`

	msg "Cleaning workspace"
	injail ${JAILNAME} make -C ${PORTDIRECTORY} clean

	injail make -C ${PORTDIRECTORY} package

	msg "Cleaning up"
	injail ${JAILNAME} make -C ${PORTDIRECTORY} clean

	exec 1>&3 3>&- 2>&4 4>&-
	wait $tpid


	cleanup
	STATUS=0 #injail
done
