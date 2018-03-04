#!/bin/sh
# 
# Copyright (c) 2012-2017 Bryan Drewery <bdrewery@FreeBSD.org>
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

stress_snapshot() {
	local loadvg swapinfo elapsed duration now min_load loadpct ncpu

	loadavg=$(/sbin/sysctl -n vm.loadavg|/usr/bin/awk '{print $2,$3,$4}')
	min_load="${loadavg%% *}"
	# Use minimum of JOBS and hw.ncpu to determine load%. Exceeding total
	# of either is 100%.
	ncpu=${PARALLEL_JOBS}
	[ ${ncpu} -gt ${NCPU} ] && ncpu=${NCPU}
	loadpct="$(printf "%2.0f%%" $(echo "scale=20; 100 * (${min_load} / ${ncpu})" | bc))"
	swapinfo=$(/usr/sbin/swapinfo -k|/usr/bin/awk '/\// {sum+=$2; X+=$3} END {if (sum) {printf "%1.2f%%\n", X*100/sum}}')
	now=$(clock -monotonic)
	elapsed=$((${now} - ${TIME_START}))

	bset snap_loadavg "(${loadpct}) ${loadavg}"
	bset snap_swapinfo "${swapinfo}"
	bset snap_elapsed "${elapsed}"
	bset snap_now "${now}"
}

html_json_main() {
	# This is too noisy and hurts reading debug output.
	local -; set +x
	local _relpath

	# Ensure we are not sitting in the MASTERMNT/.p directory and
	# move into the logdir for relative operations.
	_log_path_top log_path_top
	cd "${log_path_top}"
	log_path_top="."

	# Determine relative paths
	_log_path_jail log_path_jail
	_relpath "${log_path_jail}" "${log_path_top}"
	log_path_jail="${_relpath}"

	_log_path log_path
	_relpath "${log_path}" "${log_path_top}"
	log_path="${_relpath}"

	trap exit TERM
	trap html_json_cleanup EXIT

	while :; do
		stress_snapshot
		update_stats || :
		build_all_json
		sleep ${HTML_JSON_UPDATE_INTERVAL} 2>/dev/null
	done
}

build_all_json() {
	critical_start
	build_json
	if slock_acquire "json_jail_${MASTERNAME}" 2 2>/dev/null; then
		build_jail_json
		slock_release "json_jail_${MASTERNAME}"
	fi
	if slock_acquire "json_top" 2 2>/dev/null; then
		build_top_json
		slock_release "json_top"
	fi
	critical_end
}

build_json() {
	[ -n "${log_path}" ] || \
	    err 1 "build_jail_json requires log_path set"
	/usr/bin/awk \
		-f ${AWKPREFIX}/json.awk ${log_path}/.poudriere.*[!%] | \
		/usr/bin/awk 'ORS=""; {print}' | \
		/usr/bin/sed  -e 's/,\([]}]\)/\1/g' \
		> ${log_path}/.data.json.tmp
	rename ${log_path}/.data.json.tmp ${log_path}/.data.json

	# Build mini json for stats
	/usr/bin/awk -v mini=yes \
		-f ${AWKPREFIX}/json.awk ${log_path}/.poudriere.*[!%] | \
		/usr/bin/awk 'ORS=""; {print}' | \
		/usr/bin/sed  -e 's/,\([]}]\)/\1/g' \
		> ${log_path}/.data.mini.json.tmp
	rename ${log_path}/.data.mini.json.tmp ${log_path}/.data.mini.json
}

build_jail_json() {
	[ -n "${log_path_jail}" ] || \
	    err 1 "build_jail_json requires log_path_jail set"
	local empty
	for empty in ${log_path_jail}/*/.data.mini.json; do
		case "${empty}" in
		# Empty
		"${log_path_jail}/*/.data.mini.json") return 0 ;;
		esac
		break
	done
	tmpfile=$(TMPDIR="${log_path_jail}" mktemp -ut json)
	{
		echo "{\"builds\":{"
		echo ${log_path_jail}/*/.data.mini.json | \
		    xargs /usr/bin/awk -f ${AWKPREFIX}/json_jail.awk | \
		    /usr/bin/sed -e '/^$/d' | \
		    paste -s -d , -
		echo "}}"
	} > ${tmpfile}
	rename ${tmpfile} ${log_path_jail}/.data.json
}

build_top_json() {
	[ -n "${log_path_top}" ] || \
	    err 1 "build_top_json requires log_path_top set"
	local empty
	for empty in */latest/.data.mini.json; do
		case "${empty}" in
		# Empty
		"*/latest/.data.mini.json") return 0 ;;
		esac
		break
	done
	tmpfile=$(TMPDIR="${log_path_top}" mktemp -ut json)
	(
		cd "${log_path_top}"
		echo "{\"masternames\":{"
		echo */latest/.data.mini.json | \
		    xargs /usr/bin/awk -f ${AWKPREFIX}/json_top.awk | \
		    /usr/bin/sed -e '/^$/d' | \
		    paste -s -d , -
		echo "}}"
	) > ${tmpfile}
	rename ${tmpfile} ${log_path_top}/.data.json
}

# This is called at the end
html_json_cleanup() {
	local log

	_log_path log
	bset ended "$(clock -epoch)" || :
	build_all_json || :
	rm -f ${log}/.data.json.tmp ${log}/.data.mini.json.tmp 2>/dev/null || :
}

# Create/Update a base dir and then hardlink-copy the files into the
# dest dir. This is used for HTML copying to keep space usage efficient.
install_html_files() {
	[ $# -eq 3 ] || eargs install_html_files src base dest
	local src="$1"
	local base="$2"
	local dest="$3"

	slock_acquire html_base 2 2>/dev/null || return 0

	# Update the base copy
	mkdir -p "${base}"
	cpdup -i0 -x "${src}" "${base}"

	# Mark this HTML as inline rather than hosted. This means
	# it will support Indexes and file://, rather than the
	# aliased /data dir. This can easily be auto-detected via JS
	# but due to FF file:// restrictions requires a hack which
	# results in a 404 for every page load.
	if [ "${HTML_TYPE}" = "inline" ]; then
	    if grep -q 'server_style = "hosted"' \
		"${log_top}/.html/index.html"; then
		    sed -i '' -e \
		    's/server_style = "hosted"/server_style = "inline"/' \
		    ${log_top}/.html/*.html
	    fi
	fi

	mkdir -p "${dest}"
	# Hardlink-copy the base into the destination dir.
	cp -xal "${base}/" "${dest}/"

	slock_release html_base

	# Symlink the build properly
	ln -fs build.html "${dest}/index.html"
	unlink "${dest}/jail.html"

	return 0
}
