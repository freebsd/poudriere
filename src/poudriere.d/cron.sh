#!/bin/sh
set -e

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh
OLD=`date +%s`

[ -z ${CRONDIR} ] && err 1 "Please provide a CRONDIR variable in your poudriere.conf"
perms=`stat ${CRONDIR} | awk '{print $3}'`
[ $perms != "drwxrwxrwt" ] && err 1 "Please fix permissions on ${CRONDIR} (see poudriere.conf)"


if [ $(find /tmp/poudriere-data/ -name poudriere-* | wc -l) -ne 0 ]; then
	for i in `ls ${CRONDIR}/poudriere-*`; do
		AGE=`echo $i | awk -F - '{ print $3 }'`;
		if [ $AGE -lt $OLD ]; then
			OLD=$AGE	
		fi 
	done

	COMMAND=`cat ${CRONDIR}/poudriere-${OLD}`
	poudriere ${COMMAND} && rm ${CRONDIR}/poudriere-${OLD}
fi
