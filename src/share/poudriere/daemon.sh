#!/bin/sh

usage() {
	echo "poudriere daemon [options]

Options:
    -n        -- No daemonise
    -p        -- pidfile
    -k        -- kill the running daemon"

    exit 1
}


SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
LIBEXECPREFIX=`realpath ${SCRIPTPREFIX}/../../libexec/poudriere`
PTNAME="default"
NODAEMONIZE=0
KILL=0

. ${SCRIPTPREFIX}/common.sh

if [ -z "${DAEMON_ARGS_PARSED}" ]; then
	[ $# -eq 0 ] && usage

	while getopts "np:d:" FLAG; do
		case "${FLAG}" in
		n) NODAEMONIZE=1 ;;
		p) PIDFILE=${OPTARG} ;;
		k) KILL=1 ;;
		esac
	done
	if [ ${KILL} -eq 1 ]; then
		pkill -15 -F ${PIDFILE} >/dev/null 2>&1 || exit 1
		exit 0
	fi

	if [ ${NODAEMONIZE} -eq 0 ]; then
		exit 1
		daemon -f -p ${PIDFILE} env -i PATH=${PATH} DAEMON_ARGS_PARSED=1 $0 || exit 1
		exit 0
	else
		pgrep -F ${PIDFILE} >/dev/null 2>&1 && err 1 "poudriere daemon is already running"
		echo "$$" > ${PIDFILE}
	fi
fi

while :; do
	next=$(find ${WATCHDIR} -type f -depth 1 -print -quit 2>/dev/null)
	if [ -z "${next}" ]; then
		${LIBEXECPREFIX}/dirwatch ${WATCHDIR}
		continue
	fi
	POUDRIERE_ARGS=$(sed -n "s/^POUDRIERE_ARGS: //p" ${next})
	mkdir -p ${POUDRIERE_DATA}/logs/daemon
	poudriere ${POUDRIERE_ARGS} > ${POUDRIERE_DATA}/logs/daemon/${next##*/}.log
	rm -f ${next}
done
