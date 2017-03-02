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
poudriere distclean [options]

Options:
    -J n        -- Run n jobs in parallel (Defaults to the number of CPUs)
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
ALL=1

. ${SCRIPTPREFIX}/common.sh

while getopts "J:np:vy" FLAG; do
	case "${FLAG}" in
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

: ${PREPARE_PARALLEL_JOBS:=${PARALLEL_JOBS}}
PARALLEL_JOBS=${PREPARE_PARALLEL_JOBS}

distfiles_cleanup() {
	rm -f ${DISTFILES_LIST} ${DISTFILES_LIST}.expected \
		${DISTFILES_LIST}.actual ${DISTFILES_LIST}.unexpected \
		2>/dev/null
}

get_distinfo() {
	local port="$1"

	prefix_stderr_quick "(${COLOR_PORT}$1${COLOR_RESET})${COLOR_WARN}" \
	    make -C "${PORTSDIR}/${port}" -V DISTINFO_FILE
}

gather_distfiles() {
	local origin="$1"
	local distinfo_file="$(get_distinfo ${origin})"

	[ -f "${distinfo_file}" ] || return 0

	msg_verbose "Gathering distfiles for: ${origin}"

	awk -v distdir="${DISTFILES_CACHE%/}" '/SIZE/ {print distdir "/" substr($2, 2, length($2) - 2)}' \
		"${distinfo_file}" >> ${DISTFILES_LIST}
}

[ -d ${DISTFILES_CACHE:-/nonexistent} ] ||
    err 1 "The DISTFILES_CACHE directory does not exist (c.f. poudriere.conf)"

DISTFILES_LIST=$(mktemp -t poudriere_distfiles)
CLEANUP_HOOK=distfiles_cleanup

parallel_start
for PTNAME in ${PTNAMES}; do
	export PORTSDIR=$(pget ${PTNAME} mnt)
	[ -d "${PORTSDIR}/ports" ] && PORTSDIR="${PORTSDIR}/ports"
	[ -z "${PORTSDIR}" ] && err 1 "No such ports tree: ${PTNAME}"

	msg "Gathering all expected distfiles for ports tree '${PTNAME}'"

	for origin in $(listed_ports); do
		parallel_run gather_distfiles ${origin}
	done
done
parallel_stop

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

file_cnt=$(wc -l ${DISTFILES_LIST}.unexpected | awk '{print $1}')

if [ ${file_cnt} -eq 0 ]; then
	msg "No stale distfiles to cleanup"
	exit 0
fi

[ -s "${DISTFILES_LIST}.expected" ] || \
	err 1 "Something went wrong. All distfiles would have been removed."

hsize=$(cat ${DISTFILES_LIST}.unexpected | xargs stat -f '%i %z' | sort -u | \
	awk '{total += $2} END {print total}' | \
	awk -f ${AWKPREFIX}/humanize.awk
)

msg "Files to be deleted:"
cat ${DISTFILES_LIST}.unexpected
msg "Cleaning these will free: ${hsize}"

if [ ${DRY_RUN} -eq 1 ];  then
	msg "Dry run: not cleaning anything."
	exit 0
fi

if [ -z "${answer}" ]; then
	prompt "Proceed?" && answer="yes"
fi

if [ "${answer}" = "yes" ]; then
	msg "Cleaning files"
	cat ${DISTFILES_LIST}.unexpected | xargs rm -f
fi
