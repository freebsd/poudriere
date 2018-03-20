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
    -a arch     -- Indicates the TARGET_ARCH if no jail is specified. Such as i386
                   or amd64. Format of TARGET.TARGET_ARCH is also supported.
    -c          -- Use 'make config' target
    -C          -- Use 'make config-conditional' target (default)
    -j name     -- Run on the given jail
    -p tree     -- Specify on which ports tree the configuration will be done
    -n          -- Do not configure/show/remove options of dependencies
    -r          -- Remove port options instead of configuring them
    -s          -- Show port options instead of configuring them
    -z set      -- Specify which SET to use
EOF
	exit 1
}

ARCH=
PTNAME=default
SETNAME=""
PTNAME_TMP=""
DO_RECURSE=y
COMMAND=config-conditional
RECURSE_COMMAND=config-recursive

. ${SCRIPTPREFIX}/common.sh

[ $# -eq 0 ] && usage

while getopts "a:cCj:f:p:nrsz:" FLAG; do
	case "${FLAG}" in
		a)
			ARCH=${OPTARG}
			# If TARGET=TARGET_ARCH trim it away and just use
			# TARGET_ARCH
			[ "${ARCH%.*}" = "${ARCH#*.}" ] && ARCH="${ARCH#*.}"
			;;
		c)
			COMMAND=config
			;;
		C)
			COMMAND=config-conditional
			;;
		j)
			jail_exists ${OPTARG} || err 1 "No such jail: ${OPTARG}"
			JAILNAME=${OPTARG}
			;;
		f)
			# If this is a relative path, add in ${PWD} as
			# a cd / was done.
			[ "${OPTARG#/}" = "${OPTARG}" ] && \
			    OPTARG="${SAVED_PWD}/${OPTARG}"
			BULK_LIST="${OPTARG}"
			;;
		p)
			porttree_exists ${OPTARG} ||
			    err 2 "No such ports tree: ${OPTARG}"
			PTNAME=${OPTARG}
			PTNAME_TMP=${OPTARG}
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
post_getopts

# checking jail and architecture consistency
if [ -n "${JAILNAME}" -a -n "${ARCH}" ]; then
	_jget _arch "${JAILNAME}" arch
	if need_cross_build "${_arch}" "${ARCH}" ; then
		err 1 "jail ${JAILNAME} and architecture ${ARCH} not compatible"
	fi
fi

export PORTSDIR=`pget ${PTNAME} mnt`
[ -d "${PORTSDIR}/ports" ] && PORTSDIR="${PORTSDIR}/ports"
[ -z "${PORTSDIR}" ] && err 1 "No such ports tree: ${PTNAME}"
command -v dialog4ports >/dev/null 2>&1 || err 1 "You must have ports-mgmt/dialog4ports installed on the host to use this command."

if [ $# -eq 0 ]; then
	[ -n "${BULK_LIST}" ] || err 1 "No packages specified"
	[ -f ${BULK_LIST} ] || err 1 "No such list of packages: ${BULK_LIST}"
LISTPORTS=`grep -v -E '(^[[:space:]]*#|^[[:space:]]*$)' ${BULK_LIST}`
else
	[ -z "${BULK_LIST}" ] ||
		err 1 "Command line arguments and a list of ports cannot be used at the same time"
	LISTPORTS="$@"
fi

OLD_PORT_DBDIR=${POUDRIERED}/${JAILNAME}${JAILNAME:+-}${SETNAME}${SETNAME:+-}options
PORT_DBDIR=${POUDRIERED}/${JAILNAME}${JAILNAME:+-}${PTNAME_TMP}${PTNAME_TMP:+-}${SETNAME}${SETNAME:+-}options

if [ -d "${OLD_PORT_DBDIR}" ] && [ ! -d "${PORT_DBDIR}" ]; then
	msg_warn "You already have options configured without '-p ${PTNAME_TMP}' that will no longer be used."
	msg_warn "Drop the '-p ${PTNAME_TMP}' option to avoid this problem."
	if [ -t 0 ]; then
		confirm_if_tty "Are you sure you want to continue?" || exit 0
	else
		msg_warn "Will create ${PORT_DBDIR} which overrides existing ${OLD_PORT_DBDIR}"
	fi
fi

mkdir -p ${PORT_DBDIR}

__MAKE_CONF=$(mktemp -t poudriere-make.conf)
export __MAKE_CONF
CLEANUP_HOOK=options_cleanup
options_cleanup() {
	rm -f ${__MAKE_CONF}
}
setup_makeconf ${__MAKE_CONF} "${JAILNAME}" "${PTNAME}" "${SETNAME}"

export TERM=${SAVED_TERM}
for originspec in ${LISTPORTS}; do
	originspec_decode "${originspec}" origin '' flavor
	[ -d ${PORTSDIR}/${origin} ] || err 1 "No such port: ${origin}"
	env ${flavor:+FLAVOR=${flavor}} \
	make PORT_DBDIR=${PORT_DBDIR} \
		-C ${PORTSDIR}/${origin} \
		${COMMAND}

	if [ -n "${DO_RECURSE}" ]; then
		env ${flavor:+FLAVOR=${flavor}} \
		make PORT_DBDIR=${PORT_DBDIR} \
			PKG_BIN=`which pkg-static` \
			DIALOG4PORTS=`which dialog4ports` \
			LOCALBASE=/nonexistent \
			-C ${PORTSDIR}/${origin} \
			${RECURSE_COMMAND}
	fi
done
