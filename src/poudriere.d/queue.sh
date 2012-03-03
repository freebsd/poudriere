#!/bin/sh
set -e

usage() {
	echo "poudriere queue your command"
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

[ -z ${CRONDIR} ] && err 1 "Please provide a CRONDIR variable in your poudriere.conf"
perms=`stat ${CRONDIR} | awk '{print $3}'`
[ `stat -f '%Sp' ${CRONDIR}` != "drwxrwxrwt" ] && err 1 "Please fix permissions on ${CRONDIR} (see poudriere.conf)"

for ARG in $@; do
	echo -n "$ARG " >> ${CRONDIR}/poudriere-`date +%s`
done
