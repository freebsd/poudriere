#!/bin/sh
# 
# Copyright (c) 2012, Natacha Porté
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
poudriere options [options] [-f file|cat/port ...]

Parameters:
    -f file     -- Give the list of ports to set options
    [ports...]  -- List of ports to set options on

Options:
    -c          -- Use 'make config' target
    -C          -- Use 'make config-conditional' target (default)
    -j name     -- Run on the given jail
    -p tree     -- Specify on which ports tree the configuration will be done
    -n          -- Don't configure/show/remove options of dependencies
    -r          -- Remove port options instead of configuring them
    -s          -- Show port options instead of configuring them
    -z set      -- Specify which SET to use
EOF
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`

PTNAME=default
SETNAME=""
DO_RECURSE=y
COMMAND=config-conditional
RECURSE_COMMAND=config-recursive

. ${SCRIPTPREFIX}/common.sh

[ $# -eq 0 ] && usage

while getopts "cCj:f:p:nrsz:" FLAG; do
	case "${FLAG}" in
		c)
			COMMAND=config
			;;
		C)
			COMMAND=config-conditional
			;;
		j)
			jail_exists ${OPTARG} || err 1 "No such jail"
			JAILNAME=${OPTARG}
			;;
		f)
			BULK_LIST=${OPTARG}
			;;
		p)
			porttree_exists ${OPTARG} ||
			    err 2 "No such ports tree ${OPTARG}"
			PTNAME=${OPTARG}
			;;
		n)
			DO_RECURSE=
			;;
		r)
			COMMAND=rmconfig
			RECURSE_COMMAND=rmconfig-recursive
			;;
		s)
			COMMAND=showconfig
			RECURSE_COMMAND=showconfig-recursive
			;;
		z)
			[ -n "${OPTARG}" ] || err 1 "Empty set name"
			SETNAME="${OPTARG}"
			;;
		*)
			usage
			;;
	esac
done

shift $((OPTIND-1))

export PORTSDIR=`pget ${PTNAME} mnt`
[ -d "${PORTSDIR}/ports" ] && PORTSDIR="${PORTSDIR}/ports"
[ -z "${PORTSDIR}" ] && err 1 "No such ports tree: ${PTNAME}"

if [ $# -eq 0 ]; then
	[ -n "${BULK_LIST}" ] || err 1 "No packages specified"
	[ -f ${BULK_LIST} ] || err 1 "No such list of packages: ${BULK_LIST}"
LISTPORTS=`grep -v -E '(^[[:space:]]*#|^[[:space:]]*$)' ${BULK_LIST}`
else
	[ -z "${BULK_LIST}" ] ||
		err 1 "command line arguments and list of ports cannot be used at the same time"
	LISTPORTS="$@"
fi

PORT_DBDIR=${POUDRIERED}/${JAILNAME}${JAILNAME:+-}${SETNAME}${SETNAME:+-}options

mkdir -p ${PORT_DBDIR}

__MAKE_CONF=$(mktemp -t poudriere-make.conf)
export __MAKE_CONF
CLEANUP_HOOK=options_cleanup
options_cleanup() {
	rm -f ${__MAKE_CONF}
}
setup_makeconf ${__MAKE_CONF} "${JAILNAME}" "${PTNAME}" "${SETNAME}"

export TERM=${SAVED_TERM}
for origin in ${LISTPORTS}; do
	[ -d ${PORTSDIR}/${origin} ] || err 1 "No such ports ${origin}"
	make PORT_DBDIR=${PORT_DBDIR} \
		-C ${PORTSDIR}/${origin} \
		${COMMAND}

	if [ -n "${DO_RECURSE}" ]; then
		make PORT_DBDIR=${PORT_DBDIR} \
			-C ${PORTSDIR}/${origin} \
			${RECURSE_COMMAND}
	fi
done
