#!/bin/sh

usage() {
	echo "poudriere removejail -n name"
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

while getopts "n:" FLAG; do
	case "${FLAG}" in 
		n)
		NAME=${OPTARG}
		;;
		*)
		usage
		;;
	esac
done

test -z ${NAME} && usage

zfs list ${ZPOOL}/poudriere/${NAME} >/dev/null 2>&1 || err 1 "No such jail"

zfs destroy -r ${ZPOOL}/poudriere/${NAME}
rm -rf ${POUDRIERE_DATA}/packages/${NAME}
rm -f ${POUDRIERE_DATA}/logs/*-${NAME}*.log
