#!/bin/sh
set -e
exit 1

# Copyright (c) 2012, Bryan Drewery <bdrewery@FreeBSD.org>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

usage() {
	echo "poudriere distclean [options]

Options:
    -J n        -- Run n jobs in parallel
    -p tree     -- Specify which ports tree to use for comparing to the distfiles
    -n          -- Don't actually remove anything, just show what would be removed
    -v          -- Be verbose; show more information. Use twice to enable debug output
    -y          -- Assume yes when deleting and do not confirm"

	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
PTNAME=default
DRY_RUN=0
ALL=1

. ${SCRIPTPREFIX}/common.sh

[ $# -eq 0 ] && usage

while getopts "J:np:vy" FLAG; do
	case "${FLAG}" in
		J)
			PARALLEL_JOBS=${OPTARG}
			;;
		n)
			DRY_RUN=1
			;;
		p)
			PTNAME=${OPTARG}
			;;
		v)
			VERBOSE=$((${VERBOSE:-0} + 1))
			;;
		y)
			answer=yes
			;;
		*)
			usage
			;;
	esac
done

shift $((OPTIND-1))

_REAL_PARALLEL_JOBS=${PARALLEL_JOBS}
export PORTSDIR=`porttree_get_base ${PTNAME}`
[ -d "${PORTSDIR}/ports" ] && PORTSDIR="${PORTSDIR}/ports"
[ -z "${PORTSDIR}" ] && err 1 "No such ports tree: ${PTNAME}"
[ ! -d ${DISTFILES_CACHE} ] && err 1 "DISTFILES_CACHE directory	does not exists. (c.f. poudriere.conf)"

DISTFILES_LIST=$(mktemp -t poudriere_distfiles)
trap "rm -f ${DISTFILES_LIST} ${DISTFILES_LIST}.expected \
	${DISTFILES_LIST}.actual ${DISTFILES_LIST}.unexpected \
	2>/dev/null" EXIT INT

gather_distfiles() {
	local origin="$1"
	local distinfo_file="$(make -C ${PORTSDIR}/${origin} -V DISTINFO_FILE)"

	[ -f "${distinfo_file}" ] || return 0

	msg_verbose "Gathering distfiles for: ${origin}"

	awk -v distdir="${DISTFILES_CACHE%/}" '/SIZE/ {print distdir "/" substr($2, 2, length($2) - 2)}' \
		"${distinfo_file}" >> ${DISTFILES_LIST}
}

msg "Gathering all expected disfiles"
for origin in $(listed_ports); do
	parallel_run "gather_distfiles ${origin}"
done
parallel_stop

# Remove duplicates
sort -u ${DISTFILES_LIST} > ${DISTFILES_LIST}.expected

# Gather list of actual files
msg "Gathering list of actual distfiles"
find -s ${DISTFILES_CACHE}/ -type f >> ${DISTFILES_LIST}.actual

comm -1 -3 ${DISTFILES_LIST}.expected ${DISTFILES_LIST}.actual \
	> ${DISTILES_LIST}.unexpected

file_cnt=$(wc -l ${DISTILES_LIST}.unexpected)

if [ ${file_cnt} -eq 0 ]; then
	msg "No stale distfiles to cleanup"
	exit 0
fi

hsize=$(cat ${DISTILES_LIST}.unexpected | xargs stat -f %z | \
	awk '{total += $1} END {print total}' | \
	awk '{
		hum[1024**4]="TB";
		hum[1024**3]="GB";
		hum[1024**2]="MB";
		hum[1024]="KB";
		hum[0]="B";
		for (x=1024**4; x>=1024; x/=1024) {
			if ($1 >= x) {
				printf "%.2f %s\t%s\n", $1/x, hum[x], $2;
				break
			}
		}
	}'
)

msg "Files to be deleted:"
cat ${DISTILES_LIST}.unexpected
msg "Cleaning these will free: ${hsize}"

if [ ${DRY_RUN} -eq 1 ];  then
	msg "Dry run: not cleaning anything."
	exit 0
fi

if [ -z "${answer}" ]; then
	msg_n "Proceed? [Y/N] "
	read answer
	case $answer in
		[Yy][Ee][Ss]|[Yy][Ee]|[Yy])
			answer=yes
			;;
		*)
			answer=no
			;;
	esac
fi

if [ "${answer}" = "yes" ]; then
	msg "Cleaning files"
	cat ${DISTILES_LIST}.unexpected | xargs rm -f
fi
