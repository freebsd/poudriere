#!/bin/sh
set -e

usage() {
	echo "poudriere queue your command"
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh
QUEUEPATH="/tmp/poudriere-data"

for ARG in $@
do
	echo -n "$ARG " >> ${QUEUEPATH}/poudriere-`date +%s`
done
