#!/bin/sh
# 
# Copyright (c) 2012-2013 Baptiste Daroussin <bapt@FreeBSD.org>
# Copyright (c) 2012-2013 Bryan Drewery <bdrewery@FreeBSD.org>
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
	cat <<EOF
poudriere distclean [options] [-a|-f file|cat/port ...]

Parameters:
    -a          -- Clean the whole ports tree
    -f file     -- Get the list of ports to clean from a file
    [ports...]  -- List of ports to clean on the command line

Options:
    -J n        -- Run n jobs in parallel (Defaults to the number of CPUs
                   times 1.25)
    -p tree     -- Specify which ports tree to use for comparing to distfiles.
                   Can be specified multiple times. (Defaults to the 'default'
                   tree)
    -n          -- Do not actually remove anything, just show what would be
                   removed
    -v          -- Be verbose; show more information. Use twice to enable
                   debug output
    -y          -- Assume yes when deleting and do not prompt for confirmation
EOF
	exit 1
}

DRY_RUN=0
ALL=0

. ${SCRIPTPREFIX}/common.sh

[ $# -eq 0 ] && usage

while getopts "af:J:np:vy" FLAG; do
	case "${FLAG}" in
		a)
			ALL=1
			;;
		f)
			# If this is a relative path, add in ${PWD} as
			# a cd / was done.
			[ "${OPTARG#/}" = "${OPTARG}" ] && \
			    OPTARG="${SAVED_PWD}/${OPTARG}"
			LISTPKGS="${LISTPKGS} ${OPTARG}"
			;;
		J)
			PREPARE_PARALLEL_JOBS=${OPTARG}
			;;
		n)
			DRY_RUN=1
			;;
		p)
			porttree_exists ${OPTARG} ||
			    err 1 "No such ports tree: ${OPTARG}"
			PTNAMES="${PTNAMES} ${OPTARG}"
			;;
		v)
			VERBOSE=$((${VERBOSE} + 1))
			;;
		y)
			answer=yes
			;;
		*)
			usage
			;;
	esac
done

: ${PTNAMES:=default}

shift $((OPTIND-1))
post_getopts

: ${PREPARE_PARALLEL_JOBS:=$(echo "scale=0; ${PARALLEL_JOBS} * 1.25 / 1" | bc)}
PARALLEL_JOBS=${PREPARE_PARALLEL_JOBS}

distfiles_cleanup() {
	rm -f ${DISTFILES_LIST} ${DISTFILES_LIST}.expected \
		${DISTFILES_LIST}.actual ${DISTFILES_LIST}.unexpected \
		2>/dev/null
	if [ -n "${__MAKE_CONF}" ]; then
		rm -f "${__MAKE_CONF}"
	fi
}

injail() {
	"$@"
}
gather_distfiles() {
	local originspec="$1"
	local distinfo_file

	port_var_fetch_originspec "${originspec}" \
	    DISTINFO_FILE distinfo_file || :

	[ -f "${distinfo_file}" ] || return 0

	msg_verbose "Gathering distfiles for: ${originspec}"

	awk -v distdir="${DISTFILES_CACHE%/}" '/SIZE/ {print distdir "/" substr($2, 2, length($2) - 2)}' \
		"${distinfo_file}" >> ${DISTFILES_LIST}
}

[ -d ${DISTFILES_CACHE:-/nonexistent} ] ||
    err 1 "The DISTFILES_CACHE directory does not exist (c.f. poudriere.conf)"

DISTFILES_LIST=$(mktemp -t poudriere_distfiles)
CLEANUP_HOOK=distfiles_cleanup

read_packages_from_params "$@"

: ${DEP_FATAL_ERROR_FILE:=dep_fatal_error-$$}
clear_dep_fatal_error
parallel_start
for PTNAME in ${PTNAMES}; do
	export PORTSDIR=$(pget ${PTNAME} mnt)
	[ -d "${PORTSDIR}/ports" ] && PORTSDIR="${PORTSDIR}/ports"
	[ -z "${PORTSDIR}" ] && err 1 "No such ports tree: ${PTNAME}"

	__MAKE_CONF=$(mktemp -t poudriere-make.conf)
	export __MAKE_CONF
	setup_ports_env "/" "${__MAKE_CONF}"
	if [ -z "${NO_PACKAGE_BUILDING}" ]; then
		echo "BATCH=yes"
		echo "PACKAGE_BUILDING=yes"
		export PACKAGE_BUILDING=yes
		echo "PACKAGE_BUILDING_FLAVORS=yes"
	fi >> "${__MAKE_CONF}"

	MASTERMNT= load_moved
	msg "Gathering all expected distfiles for ports tree '${PTNAME}'"

	for originspec in $(listed_ports show_moved); do
		parallel_run \
		    prefix_stderr_quick \
		    "(${COLOR_PORT}${originspec}${COLOR_RESET})${COLOR_WARN}" \
		    gather_distfiles "${originspec}"
	done
done
if ! parallel_stop || check_dep_fatal_error; then
	err 1 "Fatal errors encountered gathering distfiles metadata"
fi

# Remove duplicates
sort -u ${DISTFILES_LIST} > ${DISTFILES_LIST}.expected

# Gather list of actual files
msg "Gathering list of actual distfiles"
# This is redundant but here for paranoia.
[ -n "${DISTFILES_CACHE}" ] ||
    err 1 "DISTFILES_CACHE must be set (c.f. poudriere.conf)"
find -x ${DISTFILES_CACHE}/ -type f | sort > ${DISTFILES_LIST}.actual

comm -1 -3 ${DISTFILES_LIST}.expected ${DISTFILES_LIST}.actual \
	> ${DISTFILES_LIST}.unexpected

[ -s "${DISTFILES_LIST}.expected" ] || \
	err 1 "Something went wrong. All distfiles would have been removed."

ret=0
do_confirm_delete "${DISTFILES_LIST}.unexpected" "stale distfiles" \
    "${answer}" "${DRY_RUN}" || ret=$?
if [ ${ret} -eq 2 ]; then
	exit 0
fi
