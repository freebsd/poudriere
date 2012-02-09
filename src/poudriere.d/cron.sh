#!/bin/sh
set -e

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh
QUEUEPATH="/tmp/poudriere-data"
OLD=`date +%s`

if [ $(find /tmp/poudriere-data/ -name poudriere-* | wc -l) -ne 0 ]; then
	for i in `ls ${QUEUEPATH}/poudriere-*`; do
		AGE=`echo $i | awk -F - '{ print $3 }'`;
		if [ $AGE -lt $OLD ]; then
			OLD=$AGE	
		fi 
	done

	COMMAND=`cat ${QUEUEPATH}/poudriere-${OLD}`
	poudriere ${COMMAND} && rm ${QUEUEPATH}/poudriere-${OLD}
fi
