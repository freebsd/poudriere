#!/bin/sh
set -e

usage() {
        echo "poudriere queue poudriere_command"
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

[ -z ${CRONDIR} ] && err 1 "Please provide a CRONDIR variable in your poudriere.conf"
if [ ! -d ${CRONDIR} ];then
	mkdir ${CRONDIR}
	chmod 1777 ${CRONDIR}
fi
perms=`stat ${CRONDIR} | awk '{print $3}'`
[ `stat -f '%Sp' ${CRONDIR}` != "drwxrwxrwt" ] && err 1 "Please fix permissions on ${CRONDIR} (see poudriere.conf)"

QUEUEFILE=${CRONDIR}/poudriere-`date +%s`

if [ $# -lt 1]; then
	usage();
fi

for ARG in $@; do
	echo -n "$ARG " >> ${QUEUEFILE}
done
echo "" >> ${QUEUEFILE}
