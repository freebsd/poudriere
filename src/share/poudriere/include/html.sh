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

start_html_json() {
	json_main &
	JSON_PID=$!
}

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

json_main() {
	while :; do
		stress_snapshot
		update_stats || :
		build_all_json
		sleep 2
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

stop_html_json() {
	local log have_lock

	_log_path log
	if [ -n "${JSON_PID}" ]; then
		# First acquire the update_stats lock to ensure the process
		# doesn't get killed while holding it
		have_lock=0
		lock_acquire update_stats && have_lock=1

		kill ${JSON_PID} 2>/dev/null || :
		_wait ${JSON_PID} 2>/dev/null 1>&2 || :
		unset JSON_PID

		if [ ${have_lock} -eq 1 ]; then
			lock_release update_stats || :
		fi
	fi
	build_all_json 2>/dev/null || :
	rm -f ${log}/.data.json.tmp ${log}/.data.mini.json.tmp 2>/dev/null || :
}
