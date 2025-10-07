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

. ${SCRIPTPREFIX}/common.sh

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
    -o name     -- Specify name of options directory to write to
    -p tree     -- Specify on which ports tree the configuration will be done
    -n          -- Do not configure/show/remove options of dependencies
    -r          -- Remove port options instead of configuring them
    -s          -- Show port options instead of configuring them
    -z set      -- Specify which SET to use
EOF
	exit ${EX_USAGE}
}
injail() {
	"$@"
}

ARCH=
PTNAME=default
SETNAME=""
PTNAME_TMP=""
DO_RECURSE=y
DEFAULT_COMMAND=config-conditional
RECURSE_COMMAND=config-recursive
OFLAG=0
NEED_D4P=1

[ $# -eq 0 ] && usage

while getopts "a:cCj:f:o:p:nrsz:" FLAG; do
	case "${FLAG}" in
		a)
			ARCH=${OPTARG}
			# If TARGET=TARGET_ARCH trim it away and just use
			# TARGET_ARCH
			[ "${ARCH%.*}" = "${ARCH#*.}" ] && ARCH="${ARCH#*.}"
			;;
		c)
			if [ -n "${COMMAND}" ]; then
				msg_error "-${FLAG} is mutually exclusive with flag: -${COMMAND_FLAG}"
				usage
			fi
			COMMAND=config
			COMMAND_FLAG="${FLAG}"
			;;
		C)
			if [ -n "${COMMAND}" ]; then
				msg_error "-${FLAG} is mutually exclusive with flag: -${COMMAND_FLAG}"
				usage
			fi
			COMMAND=config-conditional
			COMMAND_FLAG="${FLAG}"
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
			LISTPKGS="${LISTPKGS:+${LISTPKGS} }${OPTARG}"
			;;
		o)
			PORT_DBDIRNAME="${OPTARG}"
			OFLAG=1
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
			if [ -n "${COMMAND}" ]; then
				msg_error "-${FLAG} is mutually exclusive with flag: -${COMMAND_FLAG}"
				usage
			fi
			COMMAND=rmconfig
			COMMAND_FLAG="${FLAG}"
			RECURSE_COMMAND=rmconfig-recursive
			NEED_D4P=0
			;;
		s)
			if [ -n "${COMMAND}" ]; then
				msg_error "-${FLAG} is mutually exclusive with flag: -${COMMAND_FLAG}"
				usage
			fi
			COMMAND=showconfig
			COMMAND_FLAG="${FLAG}"
			RECURSE_COMMAND=showconfig-recursive
			NEED_D4P=0
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

: ${COMMAND:=${DEFAULT_COMMAND}}

# checking jail and architecture consistency
if [ -n "${JAILNAME}" -a -n "${ARCH}" ]; then
	_jget _arch "${JAILNAME}" arch || err 1 "Missing arch metadata for jail"
	if need_cross_build "${_arch}" "${ARCH}" ; then
		err 1 "jail ${JAILNAME} and architecture ${ARCH} not compatible"
	fi
fi

export PORTSDIR=`pget ${PTNAME} mnt`
[ -d "${PORTSDIR:?}/ports" ] && PORTSDIR="${PORTSDIR:?}/ports"
[ -z "${PORTSDIR}" ] && err 1 "No such ports tree: ${PTNAME}"
if [ "${NEED_D4P}" -eq 1 ]; then
	if command -v portconfig >/dev/null 2>&1; then
		d4p=portconfig
	elif command -v dialog4ports >/dev/null 2>&1; then
		d4p=dialog4ports
	else
		err 1 "You must have ports-mgmt/dialog4ports or ports-mgmt/portconfig installed on the host to use this command."
	fi
fi

read_packages_from_params "$@"

OLD_PORT_DBDIR=${POUDRIERED}/${JAILNAME}${JAILNAME:+-}${SETNAME}${SETNAME:+-}options
: ${PORT_DBDIRNAME:="${JAILNAME}${JAILNAME:+-}${PTNAME_TMP}${PTNAME_TMP:+-}${SETNAME}${SETNAME:+-}options"}
PORT_DBDIR="${POUDRIERED}/${PORT_DBDIRNAME}"

if [ "${OFLAG}" -eq 0 ] &&
    [ -d "${OLD_PORT_DBDIR}" ] && [ ! -d "${PORT_DBDIR}" ]; then
	msg_warn "You already have options configured without '-p ${PTNAME_TMP}' that will no longer be used."
	msg_warn "Drop the '-p ${PTNAME_TMP}' option to avoid this problem."
	msg_warn "Alternatively use '-o dirname' to write to a different directory than -jpz specify."
	if [ -t 0 ]; then
		confirm_if_tty "Are you sure you want to continue?" || exit 0
	else
		msg_warn "Will create ${PORT_DBDIR} which overrides existing ${OLD_PORT_DBDIR}"
	fi
fi

mkdir -p "${PORT_DBDIR}"
msg "Working on options directory: ${PORT_DBDIR}"
msg "Using ports from: ${PORTSDIR}"

__MAKE_CONF=$(mktemp -t poudriere-make.conf)
export __MAKE_CONF
CLEANUP_HOOK=options_cleanup
options_cleanup() {
	rm -f ${__MAKE_CONF}
}
setup_makeconf ${__MAKE_CONF} "${JAILNAME}" "${PTNAME}" "${SETNAME}"
MASTERMNT= fetch_global_port_vars

export TERM=${SAVED_TERM}
ports="$(MASTERMNTREL= listed_ports show_moved)" ||
    err "$?" "Failed to list ports"
for originspec in ${ports}; do
	originspec_decode "${originspec}" origin flavor ''
	[ -d "${MASTERMNT}${PORTSDIR:?}/${origin}" ] || err 1 "No such port: ${origin}"
	env ${flavor:+FLAVOR=${flavor}} \
	make PORT_DBDIR=${PORT_DBDIR} \
		PORTSDIR=${MASTERMNT}${PORTSDIR} \
		-C ${MASTERMNT}${PORTSDIR}/${origin} \
		${COMMAND}
	case "${COMMAND}" in
	showconfig|config-conditional)
		msg "Re-run 'poudriere options' with the -c flag to modify the options."
		;;
	esac

	if [ -n "${DO_RECURSE}" ]; then
		env ${flavor:+FLAVOR=${flavor}} \
		make PORT_DBDIR=${PORT_DBDIR} \
			PORTSDIR=${MASTERMNT}${PORTSDIR} \
			PKG_BIN=`which pkg-static` \
			DIALOG4PORTS=`which $d4p` \
			LOCALBASE=/nonexistent \
			-C ${MASTERMNT}${PORTSDIR}/${origin} \
			${RECURSE_COMMAND}
	fi
done
