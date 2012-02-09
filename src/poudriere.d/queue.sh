#!/bin/sh
set -e

usage() {
	echo "poudriere queue your command"
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh
QUEUEPATH="/tmp/poudriere-data"

if [ ! -d ${QUEUEPATH} ]; then
	mkdir -p ${QUEUEPATH}
	chmod 777 ${QUEUEPATH}
fi

for ARG in $@
do
	echo -n "$ARG " >> ${QUEUEPATH}/poudriere-`date +%s`
done
