#!/bin/sh
# 
# Copyright (c) 2014-2017 Bryan Drewery <bdrewery@FreeBSD.org>
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
poudriere logclean [options] <days | -a | -N count>

Parameters:
    -a          -- Remove all logfiles matching the filter
    days        -- How many days old of logfiles to keep matching the filter
    -N count    -- How many logfiles to keep matching the filter per
                   jail/tree/set combination.

Options:
    -B name     -- Build name glob to match on (defaults to *)
    -j jail     -- Which jail to use for log directories
    -p tree     -- Specify which ports tree to use for log directories
                   (Defaults to the 'default' tree)
    -n          -- Do not actually remove anything, just show what would be
                   removed
    -v          -- Be verbose; show more information. Use twice to enable
                   debug output
    -y          -- Assume yes when deleting and do not prompt for confirmation
    -z set      -- Specify which SET to match for logs. Use '0' to only
                   match on empty sets.
EOF
	exit ${EX_USAGE}
}

BUILDNAME_GLOB="*"
PTNAME=
SETNAME=
DRY_RUN=0
DAYS=
ALL=0
MAX_COUNT=

while getopts "aB:j:p:nN:vyz:" FLAG; do
	case "${FLAG}" in
		a)
			DAYS=0
			ALL=1
			;;
		B)
			BUILDNAME_GLOB="${OPTARG}"
			;;
		j)
			JAILNAME=${OPTARG}
			;;
		n)
			DRY_RUN=1
			;;
		N)
			MAX_COUNT=${OPTARG}
			;;
		p)
			PTNAME=${OPTARG}
			;;
		v)
			VERBOSE=$((VERBOSE + 1))
			;;
		y)
			answer=yes
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

if [ -z "${DAYS}" -a -z "${MAX_COUNT}" -a $# -eq 0 ]; then
	usage
	# <days> mutually exclusive with -N and -a
elif [ $# -ne 0 ] && [ -n "${MAX_COUNT}" -o "${ALL}" -eq 1 ]; then
	usage
	# -N mutually exclusive with <days> and -a
elif [ -n "${MAX_COUNT}" ] && [ $# -ne 0 -o "${ALL}" -eq 1 ]; then
	usage
	# -a mutually exclusive with -N and <days>
elif [ "${ALL}" -eq 1 ] && [ -n "${MAX_COUNT}" -o $# -ne 0 ]; then
	usage
fi
: ${DAYS:=$1}
unset ALL

POUDRIERE_BUILD_TYPE="bulk"
_log_path_top log_top

CLEANUP_HOOK=logclean_cleanup
logclean_cleanup() {
	rm -f ${OLDLOGS} 2>/dev/null
}
OLDLOGS=$(mktemp -t poudriere_logclean)

slock_acquire logclean 30 || err 1 "Another logclean is busy"
[ -d "${log_top}" ] || err 0 "No logs present"

cd ${log_top}

# Logfiles in latest-per-pkg should have 3 links total.
#  1 = itself
#  2 = jail-specific latest-per-pkg
#  3 = build-specific log
# Find logs that are missing their jail-specific or build-specific links.
find_broken_latest_per_pkg_links() {
	required_env find_broken_latest_per_pkg_links PWD "${log_top}"

	log_links=3
	# -Btime is to avoid racing with bulk logfile()
	find -x latest-per-pkg -type f -Btime +1m ! -links ${log_links}
	# Each MASTERNAME/latest-per-pkg
	find -x . -mindepth 2 -maxdepth 2 -name latest-per-pkg -print0 | \
	    xargs -0 -J {} find -x {} -type f -Btime +1m \
	    ! -links ${log_links} | sed -e 's,^\./,,'
}

# Very old style symlinks.  Find broken links.
delete_broken_latest_per_pkg_old_symlinks() {
	required_env delete_broken_latest_per_pkg_old_symlinks PWD "${log_top}"

	find -x -L latest-per-pkg -type l -exec rm -f {} +
	# Each MASTERNAME/latest-per-pkg
	find -x . -mindepth 2 -maxdepth 2 -name latest-per-pkg -print0 | \
	    xargs -0 -J {} find -x -L {} -type l -exec rm -f {} +
}

# Find now-empty latest-per-pkg directories.  This will take 3 runs
# to actually clear out a package.
delete_empty_latest_per_pkg() {
	required_env delete_empty_latest_per_pkg PWD "${log_top}"

	# -Btime is to avoid racing with bulk logfile()
	find -x latest-per-pkg -mindepth 1 -type d -Btime +1m -empty -delete
}

echo_logdir() {
	if [ -n "${MAX_COUNT}" ]; then
		echo "${log}"
	else
		printf "${log}\000"
	fi
}

if [ -n "${MAX_COUNT}" ]; then
	reason="builds over max of ${MAX_COUNT} in ${log_top} (filtered)"
elif [ ${DAYS} -eq 0 ]; then
	reason="all builds in ${log_top} (filtered)"
else
	reason="builds older than ${DAYS} days in ${log_top} (filtered)"
fi
msg_n "Looking for ${reason}..."
if [ -n "${MAX_COUNT}" ]; then
	# Find build directories up to limit MAX_COUNT per mastername
	BUILDNAME_GLOB="${BUILDNAME_GLOB}" SHOW_FINISHED=1 \
	    for_each_build echo_logdir | sort -d | \
	    awk -vMAX_COUNT="${MAX_COUNT}" -F / '
	{
		if (out[$1])
			out[$1] = out[$1] "\t" $0
		else
			out[$1] = $0
	}
	END {
		for (mastername in out) {
			total = split(out[mastername], a, "\t")
			if (MAX_COUNT > total)
				total = 0
			else
				total -= MAX_COUNT
			for (n = 1; n <= total; n++)
				print a[n]
		}
	}
	' > "${OLDLOGS}"
else
	# Find build directories older than DAYS
	BUILDNAME_GLOB="${BUILDNAME_GLOB}" SHOW_FINISHED=1 \
	    for_each_build echo_logdir | \
	    xargs -0 -J {} \
	    find -x {} -type d -mindepth 0 -maxdepth 0 -Btime +${DAYS}d \
	    > "${OLDLOGS}"
fi
echo " done"
# Confirm these logs are safe to delete.
ret=0
do_confirm_delete "${OLDLOGS}" \
    "${reason}" \
    "${answer}" "${DRY_RUN}" "0" || ret=$?
# ret = 2 means no files were deleted, but let's still
# cleanup other broken/stale files and links.
logs_deleted=0
if [ ${ret} -eq 1 ]; then
	logs_deleted=1
fi

# Save which builds were modified for later html_json rewriting
MASTERNAMES_TOUCHED="$(cat "${OLDLOGS}" | cut -d / -f 1 | sort -u)"

# Once that is done, we have a latest-per-pkg links to cleanup.
reason="detached latest-per-pkg logfiles in ${log_top} (no filter)"
msg_n "Looking for ${reason}..."
{
	find_broken_latest_per_pkg_links
} > "${OLDLOGS}"
echo " done"
# Confirm latest-per-pkg links are OK to cleanup
ret=0
do_confirm_delete "${OLDLOGS}" \
    "${reason}" \
    "${answer}" "${DRY_RUN}" "0" || ret=$?

if [ ${DRY_RUN} -eq 0 ]; then
	msg_n "Removing broken legacy latest-per-pkg symlinks (no filter)..."
	# Now we can cleanup dead links and empty directories.  Empty
	# directories will take 2 passes to complete.
	delete_broken_latest_per_pkg_old_symlinks
	echo " done"
	msg_n "Removing empty latest-per-pkg directories (no filter)..."
	delete_empty_latest_per_pkg
	echo " done"
else
	msg "[Dry Run] Would remove broken legacy latest-per-pkg symlinks (no filter)..."
	msg "[Dry Run] Would remove empty latest-per-pkg directories (no filter)..."
fi

if [ ${logs_deleted} -eq 1 ]; then
	[ "${DRY_RUN}" -eq 0 ] || err 1 "Would delete files with dry-run"

	msg_n "Fixing latest symlinks..."
	for MASTERNAME in ${MASTERNAMES_TOUCHED}; do
		echo -n "${MASTERNAME}..."
		latest=$(find -x "${MASTERNAME}" -mindepth 2 -maxdepth 2 \
		    \( -type d -name 'latest*' -prune \) -o \
		    -type f -name .poudriere.status \
		    -print | sort -u -d | tail -n 1 | \
		    awk -F / '{print $(NF - 1)}')
		rm -f "${MASTERNAME}/latest"
		[ -z "${latest}" ] && continue
		ln -s "${latest}" "${MASTERNAME}/latest"
	done
	echo " done"

	msg_n "Fixing latest-done symlinks..."
	for MASTERNAME in ${MASTERNAMES_TOUCHED}; do
		echo -n "${MASTERNAME}..."
		latest_done=$(find -x "${MASTERNAME}" -mindepth 2 -maxdepth 2 \
		    \( -type d -name 'latest*' -prune \) -o \
		    -type f -name .poudriere.status \
		    -exec grep -l done: {} + | sort -u -d | tail -n 1 | \
		    awk -F / '{print $(NF - 1)}')
		rm -f "${MASTERNAME}/latest-done"
		[ -z "${latest_done}" ] && continue
		ln -s "${latest_done}" "${MASTERNAME}/latest-done"
	done
	echo " done"

	msg_n "Updating latest-per-pkg links..."
	for MASTERNAME in ${MASTERNAMES_TOUCHED}; do
		echo -n " ${MASTERNAME}..."
		find -x "${MASTERNAME}" -maxdepth 2 -mindepth 2 -name logs -print0 | \
		    xargs -0 -J % find -x % -mindepth 1 -maxdepth 1 -type f | \
		    sort -d | \
		    awk -F/ '{if (!printed[$4]){print $0; printed[$4]=1;}}' | \
		    while read log; do
			filename="${log##*/}"
			dst="${MASTERNAME}/latest-per-pkg/${filename}"
			[ -f "${dst}" ] && continue
			ln "${log}" "${dst}"
			pkgname="${filename%.log}"
			pkgbase="${pkgname%-*}"
			pkgver="${pkgname##*-}"
			latest_dst="latest-per-pkg/${pkgbase}/${pkgver}/${MASTERNAME}.log"
			mkdir -p "${latest_dst%/*}"
			ln "${log}" "${latest_dst}"
		done
	done
	echo " done"

	msg_n "Removing empty build log directories..."
	echo "${MASTERNAMES_TOUCHED}" | sed -e 's,$,/latest-per-pkg,' | \
	    tr '\n' '\000' | \
	    xargs -0 -J % find -x % -mindepth 0 -maxdepth 0 -empty | \
	    sed -e 's,$,/..,' | xargs realpath | tr '\n' '\000' | \
	    xargs -0 rm -rf
	echo " done"

	msg "Rebuilding HTML JSON files..."
	for MASTERNAME in ${MASTERNAMES_TOUCHED}; do
		# Was this build eliminated?
		[ -d "${MASTERNAME}" ] || continue
		msg_n "Rebuilding HTML JSON for: ${MASTERNAME}..."
		_log_path_jail log_path_jail
		if slock_acquire "json_jail_${MASTERNAME}" 60 2>/dev/null; then
			build_jail_json || :
			slock_release "json_jail_${MASTERNAME}"
		fi
		echo " done"
	done
	msg_n "Rebuilding HTML JSON for top-level..."
	log_path_top="${log_top}"
	if slock_acquire "json_top" 60 2>/dev/null; then
		build_top_json || :
		slock_release "json_top"
	fi
	echo " done"
elif [ "${DRY_RUN}" -eq 1 ]; then
	msg "[Dry Run] Would fix latest symlinks..."
	msg "[Dry Run] Would fix latest-done symlinks..."
	msg "[Dry Run] Would fix latest-per-pkg links..."
	msg "[Dry Run] Would remove builds with no logs..."
	msg "[Dry Run] Would rebuild HTML JSON files..."
fi

exit 0
