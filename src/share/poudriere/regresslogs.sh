#!/bin/sh
#
# regression test harness for processonelog.sh (cf. ports-mgmt/poudriere)
# not part of poudriere's mainline code path.
# Author: Mark Linimon. Lonesome Dove Computing Services.
# License: BSD license.
#

# example invocation for downloaded errorlog files:
#ERRORLOGDIR=~/Downloads/errorlogs/beefy18.nyi.FreeBSD.org/head-amd64-default/p535343_s361095/logs/errors
#ERRORLOGDRIVER=~/regresslogs/regresslogs.sh
#time ${ERRORLOGDRIVER} ${ERRORLOGDIR}

if [ -z "$1" ]; then
  ERRORLOGDIR="."
else
  ERRORLOGDIR=$1
fi

# as currently committed
#ERRORLOGSCRIPT=/usr/local/share/poudriere/processonelog.sh
# experimental
ERRORLOGSCRIPT=~/regresslogs/processonelog.sh

ERRORLOG_SUMMARY=${ERRORLOGDIR}/regresslogs.out
ERRORLOG_SUMMARY_WANTED=${ERRORLOG_SUMMARY}.wanted

echo "$0: begin processing errorlogs in ${ERRORLOGDIR} ..."

cp /dev/null ${ERRORLOG_SUMMARY} || exit 1
errorlogs=`cd ${ERRORLOGDIR} && ls -1 *.log` || exit 1
for errorlog in ${errorlogs}; do
  echo -n "${errorlog}: " >> ${ERRORLOG_SUMMARY}
  (cd ${ERRORLOGDIR} && sh ${ERRORLOGSCRIPT} ${errorlog}) >> ${ERRORLOG_SUMMARY}
done

echo "$0: finished.  Output is in ${ERRORLOG_SUMMARY}."

if [ ! -f ${ERRORLOG_SUMMARY_WANTED} ]; then
  echo "$0: if you wish, create ${ERRORLOG_SUMMARY_WANTED} and it will be diffed for you."
else
  diff ${ERRORLOG_SUMMARY} ${ERRORLOG_SUMMARY_WANTED} > ${ERRORLOGDIR}/diff.out
  wc -l ${ERRORLOGDIR}/diff.out
fi
