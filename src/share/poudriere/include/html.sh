#!/bin/sh
# 
# Copyright (c) 2012-2014 Bryan Drewery <bdrewery@FreeBSD.org>
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

	loadavg=$(sysctl -n vm.loadavg|awk '{print $2,$3,$4}')
	min_load="${loadavg%% *}"
	# Use minimum of JOBS and hw.ncpu to determine load%. Exceeding total
	# of either is 100%.
	ncpu=${PARALLEL_JOBS}
	[ ${ncpu} -gt ${NCPU} ] && ncpu=${NCPU}
	loadpct="$(printf "%2.0f%%" $(echo "scale=20; 100 * (${min_load} / ${ncpu})" | bc))"
	swapinfo=$(swapinfo -k|awk '/\// {sum+=$2; X+=$3} END {if (sum) {printf "%1.2f%%\n", X*100/sum}}')
	now=$(date +%s)
	elapsed=$((${now} - ${TIME_START}))

	bset snap_loadavg "(${loadpct}) ${loadavg}"
	bset snap_swapinfo "${swapinfo}"
	bset snap_elapsed "${elapsed}"
	bset snap_now "${now}"
}

html_json_main() {
	# This is too noisy and hurts reading debug output.
	local -; set +x
	while :; do
		stress_snapshot
		update_stats || :
		build_all_json
		sleep 2 2>/dev/null
	done
}

build_all_json() {
	build_json
	build_jail_json
	build_top_json
}

build_json() {
	local log

	_log_path log
	awk \
		-f ${AWKPREFIX}/json.awk ${log}/.poudriere.*[!%] | \
		awk 'ORS=""; {print}' | \
		sed  -e 's/,\([]}]\)/\1/g' \
		> ${log}/.data.json.tmp
	mv -f ${log}/.data.json.tmp ${log}/.data.json

	# Build mini json for stats
	awk -v mini=yes \
		-f ${AWKPREFIX}/json.awk ${log}/.poudriere.*[!%] | \
		awk 'ORS=""; {print}' | \
		sed  -e 's/,\([]}]\)/\1/g' \
		> ${log}/.data.mini.json.tmp
	mv -f ${log}/.data.mini.json.tmp ${log}/.data.mini.json
}

build_jail_json() {
	local log_path_jail tmpfile

	_log_path_jail log_path_jail
	tmpfile=$(TMPDIR="${log_path_jail}" mktemp -ut json)

	{
		echo "{\"builds\":{"
		echo ${log_path_jail}/*/.data.mini.json | \
		    xargs awk -f ${AWKPREFIX}/json_jail.awk | \
		    sed -e '/^$/d' | \
		    paste -s -d , -
		echo "}}"
	} > ${tmpfile}
	mv -f ${tmpfile} ${log_path_jail}/.data.json
}

build_top_json() {
	local log_path_top tmpfile

	_log_path_top log_path_top
	tmpfile=$(TMPDIR="${log_path_top}" mktemp -ut json)

	(
		cd "${log_path_top}"
		echo "{\"masternames\":{"
		echo */latest/.data.mini.json | \
		    xargs awk -f ${AWKPREFIX}/json_top.awk | \
		    sed -e '/^$/d' | \
		    paste -s -d , -
		echo "}}"
	) > ${tmpfile}
	mv -f ${tmpfile} ${log_path_top}/.data.json
}

html_json_cleanup() {
	local log

	_log_path log
	build_all_json 2>/dev/null || :
	rm -f ${log}/.data.json.tmp ${log}/.data.mini.json.tmp 2>/dev/null || :
}

# Create/Update a base dir and then hardlink-copy the files into the
# dest dir. This is used for HTML copying to keep space usage efficient.
install_html_files() {
	[ $# -eq 3 ] || eargs install_html_files src base dest
	local src="$1"
	local base="$2"
	local dest="$3"

	# Update the base copy
	mkdir -p "${base}"
	cpdup -i0 -x "${src}" "${base}"

	# Mark this HTML as inline rather than hosted. This means
	# it will support Indexes and file://, rather than the
	# aliased /data dir. This can easily be auto-detected via JS
	# but due to FF file:// restrictions requires a hack which
	# results in a 404 for every page load.
	if grep -q 'server_style = "hosted"' \
	    "${log_top}/.html/index.html"; then
		sed -i '' -e \
		's/server_style = "hosted"/server_style = "inline"/' \
		${log_top}/.html/*.html
	fi

	mkdir -p "${dest}"
	# Hardlink-copy the base into the destination dir.
	cp -xal "${base}/" "${dest}/"

	# Symlink the build properly
	ln -fs build.html "${dest}/index.html"
	rm -f "${dest}/jail.html"

	return 0
}
