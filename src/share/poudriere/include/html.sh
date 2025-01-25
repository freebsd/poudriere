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
	local loadavg swapinfo elapsed duration now min_load loadpct ncpu

	loadavg=$(/sbin/sysctl -n vm.loadavg|/usr/bin/awk '{print $2,$3,$4}')
	min_load="${loadavg%% *}"
	# Use minimum of JOBS and hw.ncpu to determine load%. Exceeding total
	# of either is 100%.
	ncpu=${PARALLEL_JOBS}
	if [ "${ncpu:?}" -gt "${NCPU:?}" ]; then
		ncpu="${NCPU}"
	fi
	loadpct="$(printf "%2.0f%%" $(echo "scale=20; 100 * (${min_load} / ${ncpu})" | bc))"
	swapinfo=$(/usr/sbin/swapinfo -k|/usr/bin/awk '/\// {sum+=$2; X+=$3} END {if (sum) {printf "%1.2f%%\n", X*100/sum}}')
	now=$(clock -monotonic)
	elapsed=$((now - TIME_START))

	bset snap_loadavg "(${loadpct}) ${loadavg}"
	bset snap_swapinfo "${swapinfo}"
	bset snap_elapsed "${elapsed}"
	bset snap_now "${now}"
}

html_json_main() {
	# This is too noisy and hurts reading debug output.
	local -; set +x
	local _relpath

	set +e +u

	setup_traps html_json_cleanup
	# Ensure we are not sitting in the MASTER_DATADIR directory and
	# move into the logdir for relative operations.
	_log_path_top log_path_top
	cd "${log_path_top:?}"
	log_path_top="."

	# Determine relative paths
	_log_path_jail log_path_jail
	_relpath "${log_path_jail:?}" "${log_path_top:?}"
	log_path_jail="${_relpath:?}"

	_log_path log_path
	_relpath "${log_path:?}" "${log_path_top:?}"
	log_path="${_relpath:?}"

	while :; do
		stress_snapshot
		update_stats || :
		build_all_json
		sleep "${HTML_JSON_UPDATE_INTERVAL}" 2>/dev/null
	done
}

build_all_json() {
	build_json
	if slock_acquire -q "json_jail_${MASTERNAME:?}" 2; then
		build_jail_json
		slock_release "json_jail_${MASTERNAME:?}"
	fi
	if slock_acquire -q "json_top" 5; then
		build_top_json
		slock_release "json_top"
	fi
}

build_json() {
	required_env build_json log_path! ''
	local ret

	ret=0
	critical_start
	/usr/bin/awk \
		-f "${AWKPREFIX:?}/json.awk" "${log_path:?}"/.poudriere.*[!%] | \
		/usr/bin/awk 'ORS=""; {print} END {print "\n"}' | \
		/usr/bin/sed  -e 's/,\([]}]\)/\1/g' | \
		write_atomic_cmp "${log_path:?}/.data.json"

	# Build mini json for stats
	/usr/bin/awk -v mini=yes \
		-f "${AWKPREFIX:?}/json.awk" "${log_path:?}"/.poudriere.*[!%] | \
		/usr/bin/awk 'ORS=""; {print} END {print "\n"}' | \
		/usr/bin/sed  -e 's/,\([]}]\)/\1/g' | \
		write_atomic_cmp "${log_path:?}/.data.mini.json" || ret="$?"
	critical_end
	return "${ret}"
}

build_jail_json() {
	required_env build_jail_json log_path_jail! ''
	local empty ret

	lock_have "json_jail_${MASTERNAME:?}" ||
		err 1 "build_jail_json requires slock json_jail_${MASTERNAME}"
	for empty in "${log_path_jail:?}"/*/.data.mini.json; do
		case "${empty}" in
		# Empty
		"${log_path_jail}/*/.data.mini.json") return 0 ;;
		esac
		break
	done
	ret=0
	critical_start
	{
		echo "{\"builds\":{"
		echo "${log_path_jail:?}"/*/.data.mini.json | \
		    /usr/bin/xargs /usr/bin/awk -f "${AWKPREFIX:?}/json_jail.awk" |
		    /usr/bin/sed -e '/^$/d' | \
		    /usr/bin/paste -s -d , -
		echo "}}"
	} | write_atomic_cmp "${log_path_jail:?}/.data.json" || ret="$?"
	critical_end
	return "${ret}"
}

build_top_json() {
	required_env build_top_json log_path_top! ''
	local empty ret

	lock_have "json_top" ||
		err 1 "build_top_json requires slock json_top"
	ret=0
	critical_start
	(
		cd "${log_path_top:?}"
		for empty in */latest/.data.mini.json; do
			case "${empty}" in
			# Empty
			"*/latest/.data.mini.json") return 0 ;;
			esac
			break
		done
		echo "{\"masternames\":{"
		echo */latest/.data.mini.json | \
		    /usr/bin/xargs /usr/bin/awk -f "${AWKPREFIX:?}/json_top.awk" 2>/dev/null | \
		    /usr/bin/sed -e '/^$/d' | \
		    /usr/bin/paste -s -d , -
		echo "}}"
	) | write_atomic_cmp "${log_path_top:?}/.data.json" || ret="$?"
	critical_end
	return "${ret}"
}

# This is called at the end
html_json_cleanup() {
	local log

	_log_path log
	bset ended "$(clock -epoch)" || :
	critical_start
	build_all_json || :
	critical_end
}

# Create/Update a base dir and then hardlink-copy the files into the
# dest dir. This is used for HTML copying to keep space usage efficient.
install_html_files() {
	[ $# -eq 3 ] || eargs install_html_files src base dest
	local src="$1"
	local base="$2"
	local dest="$3"

	# Only 1 process needs to install the base files at a time. This is
	# mostly a problem in tests.
	if slock_acquire -q html_base 0; then
		# Update the base copy
		do_clone_del -r "${src:?}" "${base:?}"

		# Mark this HTML as inline rather than hosted. This means
		# it will support Indexes and file://, rather than the
		# aliased /data dir. This can easily be auto-detected via JS
		# but due to FF file:// restrictions requires a hack which
		# results in a 404 for every page load.
		case "${HTML_TYPE}" in
		inline)
		    if grep -q 'server_style = "hosted"' \
			"${base:?}/index.html"; then
			    sed -i '' -e \
			    's/server_style = "hosted"/server_style = "inline"/' \
			    "${base:?}"/*.html
		    fi
		    ;;
		esac

		slock_release html_base
	fi

	# All processes need to make a copy of the base files.
	if slock_acquire -q html_base 5; then
		mkdir -p "${dest:?}"
		# Hardlink-copy the base into the destination dir.
		cp -xal "${base:?}/" "${dest:?}/"

		# Symlink the build
		ln -fs build.html "${dest:?}/index.html"
		unlink "${dest:?}/jail.html"

		slock_release html_base
	fi

	return 0
}
