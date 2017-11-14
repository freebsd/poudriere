#!/bin/sh
# 
# Copyright (c) 2013 Baptiste Daroussin <bapt@FreeBSD.org>
# Copyright (c) 2013 Bryan Drewery <bdrewery@FreeBSD.org>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

usage() {
	cat << EOF
poudriere daemon [options]

Options:
    -n        -- Do not daemonise
    -p        -- Override the pidfile location
    -k        -- Kill the running daemon
EOF
	exit 1
}

queue_reader_main() {
	# Read from the socket and then write the command
	# to the watchdir. This is done so non-privileged users
	# do not need write access to the real queue dir
	umask 0111 # Create rw-rw-rw
	trap exit TERM
	trap queue_reader_cleanup EXIT
	nc -klU ${QUEUE_SOCKET} | while read name command; do
		echo "${command}" > ${WATCHDIR}/${name}
	done
}

queue_reader_cleanup() {
	rm -f ${QUEUE_SOCKET}
}


PTNAME="default"
NODAEMONIZE=0
KILL=0

. ${SCRIPTPREFIX}/common.sh

if [ ! -d ${WATCHDIR} ]; then
	mkdir -p ${WATCHDIR} || err 1 "Unable to create needed directory ${WATCHDIR}"
fi

if [ -z "${DAEMON_ARGS_PARSED}" ]; then
	while getopts "knp:" FLAG; do
		case "${FLAG}" in
		n)
			NODAEMONIZE=1
			;;
		p)
			PIDFILE=${OPTARG}
			;;
		k)
			KILL=1
			;;
		esac
	done
	if [ ${KILL} -eq 1 ]; then
		pkill -15 -F ${PIDFILE} >/dev/null 2>&1 || exit 1
		if [ -f ${PIDFILE} ]; then
			rm ${PIDFILE}
		fi
		exit 0
	fi

	if [ ${NODAEMONIZE} -eq 0 ]; then
		daemon -f -p ${PIDFILE} env -i PATH=${PATH} DAEMON_ARGS_PARSED=1 $0 || exit 1
		exit 0
	else
		pgrep -F ${PIDFILE} >/dev/null 2>&1 && err 1 "poudriere daemon is already running"
		echo "$$" > ${PIDFILE}
	fi
fi

# Start the queue reader
coprocess_start queue_reader

CLEANUP_HOOK=daemon_cleanup
daemon_cleanup() {
	coprocess_stop queue_reader
}

while :; do
	next=$(find ${WATCHDIR} -type f -depth 1 -print -quit 2>/dev/null)
	if [ -z "${next}" ]; then
		dirwatch ${WATCHDIR}
		if [ $? -ne 0 ]; then
			err 1 "dirwatch terminated unsuccessfully"
		fi
		continue
	fi
	POUDRIERE_ARGS=$(sed -n "s/^POUDRIERE_ARGS: //p" ${next})
	mkdir -p ${POUDRIERE_DATA}/logs/daemon
	poudriere ${POUDRIERE_ARGS} > ${POUDRIERE_DATA}/logs/daemon/${next##*/}.log
	rm -f ${next}
done
