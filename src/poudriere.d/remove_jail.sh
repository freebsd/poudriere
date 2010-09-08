#!/bin/sh

usage() {
	echo "poudriere removejail [-clp] -n name"
	echo "-l: clean logs"
	echo "-p: clean packages"
	echo "-c: clean all"
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

CLEANLOGS=0
CLEANPKGS=0

while getopts "n:clp" FLAG; do
	case "${FLAG}" in 
		n)
		NAME=${OPTARG}
		;;
		p)
		CLEANPKGS=1
		;;
		l)
		CLEANLOGS=1
		;;
		c)
		CLEANLOGS=1
		CLEANPKGS=1
		;;
		*)
		usage
		;;
	esac
done

test -z ${NAME} && usage

zfs list ${ZPOOL}/poudriere/${NAME} >/dev/null 2>&1 || err 1 "No such jail: ${NAME}"
JAILBASE=`zfs list -H ${ZPOOL}/poudriere/${NAME} | awk '{ print $NF}'`

echo -n "====> Removing ${NAME} jail..."
zfs destroy -r ${ZPOOL}/poudriere/${NAME}
rmdir ${JAILBASE}

[ ${CLEANPKGS} -eq 1 ] && rm -rf ${POUDRIERE_DATA}/packages/${NAME}
[ ${CLEANLOGS} -eq 1 ] && rm -f ${POUDRIERE_DATA}/logs/*-${NAME}*.log

echo " done"
