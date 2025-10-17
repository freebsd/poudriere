#!/bin/sh
# 
# Copyright (c) 2018 Bryan Drewery <bdrewery@FreeBSD.org>
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
	cat <<EOF
poudriere foreachport [options] [-f file] /patch/to/script [args]

Parameters:
    -a          -- Run on all ports (default)
    -f file     -- Get the list of ports to keep from a file
    [ports...]  -- List of ports to keep on the command line

Options:
    -j jail     -- Which jail to use
    -J n        -- Run n jobs in parallel (Defaults to the number of
                   CPUs times 1.25)
    -n          -- Dry run
    -p tree     -- Which ports tree to use for packages
    -v          -- Be verbose; show more information. Use twice to enable
                   debug output
    -z set      -- Specify which SET to use for packages
EOF
	exit ${EX_USAGE}
}

PTNAME=default
SETNAME=""
DRY_RUN=0
ALL=1

[ $# -eq 0 ] && usage

while getopts "af:j:J:p:vz:" FLAG; do
	case "${FLAG}" in
		a)
			ALL=1
			;;
		j)
			jail_exists ${OPTARG} || err 1 "No such jail: ${OPTARG}"
			JAILNAME=${OPTARG}
			;;
		J)
			PREPARE_PARALLEL_JOBS=${OPTARG#*:}
			;;
		f)
			# If this is a relative path, add in ${PWD} as
			# a cd / was done.
			[ "${OPTARG#/}" = "${OPTARG}" ] && \
			    OPTARG="${SAVED_PWD}/${OPTARG}"
			LISTPKGS="${LISTPKGS:+${LISTPKGS} }${OPTARG}"
			ALL=0
			;;
		n)
			DRY_RUN=1
			;;
		p)
			porttree_exists ${OPTARG} ||
			    err 2 "No such ports tree: ${OPTARG}"
			PTNAME=${OPTARG}
			;;
		v)
			VERBOSE=$((VERBOSE + 1))
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

encode_args saved_argv "$@"
shift $((OPTIND-1))
post_getopts

[ $# -lt 1 ] && usage
CMD="${1}"
shift 1
if [ "${CMD#/}" = "${CMD}" ]; then
	CMD="${SAVED_PWD}/${CMD}"
fi
if ! [ -r "${CMD}" ]; then
	msg_error "${CMD} must be a readable file to run per port."
	usage
fi

MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
_mastermnt MASTERMNT

export MASTERNAME
export MASTERMNT

: ${PREPARE_PARALLEL_JOBS:=$(echo "scale=0; ${PARALLEL_JOBS} * 1.25 / 1" | bc)}
PARALLEL_JOBS=${PREPARE_PARALLEL_JOBS}

# Send all normal output to stderr so the port script can have stdout.
exec 3>&1
exec >&2
msg "Gathering all expected packages"
jail_start "${JAILNAME}" "${PTNAME}" "${SETNAME}"
#prepare_ports
bset status "foreachport:"

install -m 0555 "${CMD}" "${MASTERMNT}/tmp/script"
cat > "${MASTERMNT}/tmp/cmd" <<'EOF'
#! /bin/sh
ORIGIN="${1}"
FLAVOR="${2}"
SUBPKG="${3}"
shift 3
if [ -n "${FLAVOR}" ]; then
	export FLAVOR
fi
if [ -n "${SUBPKG}" ]; then
	export SUBPKG
fi
cd "${PORTSDIR}/${ORIGIN}"
exec /tmp/script "$@"
EOF
chmod 0555 "${MASTERMNT}/tmp/cmd"

JNETNAME="n"

run_hook foreachport start

exec >&3

export PORTSDIR
fetch_global_port_vars
parallel_start || err 1 "parallel_start"
ports="$(listed_ports show_moved)" ||
    err "$?" "Failed to list ports"
for originspec in ${ports}; do
	originspec_decode "${originspec}" origin flavor subpkg
	parallel_run \
	    prefix_stderr_quick \
	    "(${COLOR_PORT}${originspec}${COLOR_RESET})${COLOR_WARN}" \
	    injail "/tmp/cmd" "${origin}" "${flavor}" "${subpkg}" "$@" || \
	    set_pipe_fatal_error
done
if ! parallel_stop; then
	err 1 "Fatal errors encountered processing ports"
fi

exec >&2

run_hook foreachport stop
