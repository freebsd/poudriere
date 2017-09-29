#!/bin/sh
# 
# Copyright (c) 2014 Bryan Drewery <bdrewery@FreeBSD.org>
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
poudriere status [options]

Options:
    -a          -- Show all builds, not just latest. This implies -f.
    -f          -- Show finished builds as well. This is default
                   if -a, -B or -r are specified.
    -b          -- Display status of each builder for the matched build.
    -B name     -- What buildname to use (must be unique, defaults to
                   "latest"). This implies -f.
    -c          -- Compact output (shorter headers and no logs/url)
    -H          -- Script mode. Do not print headers and separate fields by a
                   single tab instead of arbitrary white space.
    -j name     -- Run on the given jail
    -p tree     -- Specify on which ports tree to match for the build.
    -l          -- Show logs instead of URL.
    -r          -- Show results. This implies -f.
    -z set      -- Specify which SET to match for the build. Use '0' to only
                   match on empty sets.
EOF
	exit 1
}

PTNAME=
SETNAME=
SCRIPT_MODE=0
ALL=0
SHOW_FINISHED=0
COMPACT=0
URL=1
BUILDER_INFO=0
BUILDNAME=
RESULTS=0
SUMMARY=0

. ${SCRIPTPREFIX}/common.sh

while getopts "abB:cfHj:lp:rz:" FLAG; do
	case "${FLAG}" in
		a)
			ALL=1
			SHOW_FINISHED=1
			BUILDNAME_GLOB="*"
			;;
		b)
			BUILDER_INFO=1
			;;
		B)
			BUILDNAME_GLOB="${OPTARG}"
			SHOW_FINISHED=1
			;;
		c)
			COMPACT=1
			;;
		f)
			SHOW_FINISHED=1
			;;
		j)
			JAILNAME=${OPTARG}
			;;
		l)
			URL=0
			;;
		p)
			PTNAME=${OPTARG}
			;;
		H)
			SCRIPT_MODE=1
			;;
		r)
			RESULTS=1
			SHOW_FINISHED=1
			;;
		z)
			SETNAME="${OPTARG}"
			;;
		*)
			usage
			;;
	esac
done

shift $((OPTIND-1))
post_getopts

[ ${BUILDER_INFO} -eq 0 -a ${RESULTS} -eq 0 ] && \
    SUMMARY=1

# Default to "latest" if not using -a and no -B specified
[ ${ALL} -eq 0 ] && : ${BUILDNAME_GLOB:=latest}

POUDRIERE_BUILD_TYPE=bulk
now="$(clock -epoch)"

output_builder_info() {
	local builders

	_bget builders builders 2>/dev/null || :

	_mastermnt MASTERMNT
	JOBS="${builders}" siginfo_handler
}

add_summary_build() {
	local status nbqueued nbfailed nbignored nbskipped nbbuilt nbtobuild
	local elapsed time url save_status

	_bget status status 2>/dev/null || :
	_bget nbqueued stats_queued 2>/dev/null || :
	_bget nbbuilt stats_built 2>/dev/null || :
	_bget nbfailed stats_failed 2>/dev/null || :
	_bget nbignored stats_ignored 2>/dev/null || :
	_bget nbskipped stats_skipped 2>/dev/null || :
	nbtobuild=$((nbqueued - (nbbuilt + nbfailed + nbskipped + nbignored)))

	calculate_elapsed_from_log ${now} ${log}
	elapsed=${_elapsed_time}
	calculate_duration time "${elapsed}"

	url=
	if [ ${COMPACT} -eq 0 ]; then
		if [ ${URL} -eq 0 ] || ! build_url url; then
			url="${PWD}/${log}"
		fi
	fi
	status="${status#stopped:}"
	# This mess is to pull the first 2 fields: and remove trailing
	# ':'
	save_status="${status%%:*}"
	status="${status#*:}"
	status="${save_status}:${status%%:*}"
	status="${status%:}"

	display_add "${setname:--}" "${ptname}" "${jailname}" \
	    "${BUILDNAME}" "${status:-?}" "${nbqueued:-?}" \
	    "${nbbuilt:-?}" "${nbfailed:-?}" "${nbskipped:-?}" \
	    "${nbignored:-?}" "${nbtobuild:-?}" "${time:-?}" ${url}
}

status_for_each_build() {
	[ ${SCRIPT_MODE} -eq 0 -a -n "${BUILDNAME_GLOB}" -a \
	    "${BUILDNAME_GLOB}" != "latest" -a \
	    "${BUILDNAME_GLOB}" != "latest-done" ] && \
	    msg_warn "Looking up all matching builds. This may take a while."
	for_each_build "$@"
}

show_summary() {
	if [ ${COMPACT} -eq 0 ]; then
		columns=13
	else
		columns=12
	fi
	if [ ${SCRIPT_MODE} -eq 0 ]; then
		format="%%-%ds %%-%ds %%-%ds %%-%ds %%-%ds %%%ds %%%ds %%%ds %%%ds %%%ds %%%ds %%-%ds"
		[ ${COMPACT} -eq 0 ] && format="${format} %%s"
	else
		#format="%%s\t%%s\t%%s\t%%s\t%%s\t%%s\t%%s\t%%s\t%%s\t%%s\t%%s\t%%s"
		#[ ${COMPACT} -eq 0 ] && format="${format}\t%%s"
		format="%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s"
		[ ${COMPACT} -eq 0 ] && format="${format}\t%s"
	fi

	display_setup "${format}" "${columns}" "-d -k1,1 -k2,2 -k3,3n -k4,4n"

	if [ ${COMPACT} -eq 0 ]; then
		if [ -n "${URL_BASE}" ] && [ ${URL} -eq 1 ]; then
			url_logs="URL"
		else
			url_logs="LOGS"
		fi
		display_add "SET" "PORTS" "JAIL" "BUILD" "STATUS" \
		    "QUEUE" "BUILT" "FAIL" "SKIP" "IGNORE" "REMAIN" \
		    "TIME" "${url_logs}"
	else
		display_add "SET" "PORTS" "JAIL" "BUILD" "STATUS" \
		    "Q" "B" "F" "S" "I" "R" "TIME"
	fi

	status_for_each_build add_summary_build

	if [ ${SCRIPT_MODE} -eq 0 ]; then
		if [ ${found_jobs} -eq 0 ]; then
			if [ ${SHOW_FINISHED} -eq 0 ]; then
				msg "No running builds. Use -a or -f to show finished builds."
			else
				msg "No matching builds found."
			fi
			exit 0
		fi

		display_output

		[ -t 0 ] && [ -n "${JAILNAME}" ] && \
		    msg "Use -b to show detailed builder output."
	else
		display_output -q
	fi

	return 0
}

show_builder_info() {
	status_for_each_build output_builder_info

	return 0
}

show_results() {
	status_for_each_build show_build_results

	return 0
}

case "${SUMMARY}${BUILDER_INFO}${RESULTS}" in
	100)
		show_summary
		;;
	010)
		show_builder_info
		;;
	001)
		show_results
		;;
	*)
		usage
		;;
esac
