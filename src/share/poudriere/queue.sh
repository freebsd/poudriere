#!/bin/sh
set -e

usage() {
        echo "poudriere queue name poudriere_command"
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

[ $# -le 2 ] && usage()
name=$1
shift
[ -f ${WATCHDIR}/${name} ] && err 1 "A jobs named ${name} is already in queue"

case $1 in
bulk|testport) ;;
*) err 1 "$2 command cannot be queued" ;;
esac

echo "POUDRIERE_ARGS: $@" > ${WATCHDIR}/${name}
