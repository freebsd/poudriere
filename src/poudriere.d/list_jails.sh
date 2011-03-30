#!/bin/sh

usage() {

	echo "poudriere lsjail [-q] [-n JAIL]"
	echo "-q don't print header."
	echo "-n JAIL print infos about JAIL"
	exit 1

}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

JAILSPATH=/usr/local/poudriere/jails

[ -d ${JAILSPATH} ] || err 1 "No jails directory found in /usr/local/poudriere."

while getopts "n:q" FLAG; do
        case "${FLAG}" in
	  n)
	  NAME=${OPTARG}
	  ;;
	  q)
	  NOHEADER=1
	  ;;
	  *)
	  usage
	  ;; 
	esac
done

[ "${NOHEADER}X" = "1X" ] || printf '%-20s %-13s %s\n' "JAILNAME" "VERSION" "ARCH"

JAILLIST=`ls ${JAILSPATH}`
[ "${NAME}X" = "X" ] || JAILLIST=${NAME}

for DIR in ${JAILLIST};do

	if [ -d ${JAILSPATH}/${DIR} -a -d ${JAILSPATH}/${DIR}/boot/kernel ];then
		JAILNAME=${DIR}
		VERSION=`jail -c path=${JAILSPATH}/${JAILNAME} host.hostname=${JAILNAME} command=uname -v | awk '{print $2}'`
		ARCH=`jail -c path=${JAILSPATH}/${JAILNAME} host.hostname=${JAILNAME} command=uname -p`
		
		printf '%-20s %-13s %s\n' ${JAILNAME} ${VERSION} ${ARCH}
	fi

done
