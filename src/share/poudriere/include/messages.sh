#!/bin/sh
# 
# Copyright (c) 2010-2013 Baptiste Daroussin <bapt@FreeBSD.org>
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

if ! [ -t 1 ] && ! [ -t 2 ]; then
	USE_COLORS="no"
fi

if [ ${USE_COLORS} = "yes" ]; then
	COLOR_RESET="\033[0;0m"
	COLOR_RESET_REAL="${COLOR_RESET}"
	COLOR_BOLD="\033[1m"
	COLOR_UNDER="\033[4m"
	COLOR_BLINK="\033[5m"
	COLOR_BLACK="\033[0;30m"
	COLOR_RED="\033[0;31m"
	COLOR_GREEN="\033[0;32m"
	COLOR_BROWN="\033[0;33m"
	COLOR_BLUE="\033[0;34m"
	COLOR_MAGENTA="\033[0;35m"
	COLOR_CYAN="\033[0;36m"
	COLOR_LIGHT_GRAY="\033[0;37m"
	COLOR_DARK_GRAY="\033[1;30m"
	COLOR_LIGHT_RED="\033[1;31m"
	COLOR_LIGHT_GREEN="\033[1;32m"
	COLOR_YELLOW="\033[1;33m"
	COLOR_LIGHT_BLUE="\033[1;34m"
	COLOR_LIGHT_MAGENTA="\033[1;35m"
	COLOR_LIGHT_CYAN="\033[1;36m"
	COLOR_WHITE="\033[1;37m"
fi

D_LEFT="${COLOR_BOLD}[${COLOR_RESET}"
D_RIGHT="${COLOR_BOLD}]${COLOR_RESET}"

: ${COLOR_PORT:=${COLOR_CYAN}}
: ${COLOR_WARN:=${COLOR_YELLOW}}
: ${COLOR_DEBUG:=${COLOR_BLUE}}
: ${COLOR_ERROR:=${COLOR_RED}}
: ${COLOR_SUCCESS:=${COLOR_GREEN}}
: ${COLOR_IGNORE:=${COLOR_DARK_GRAY}}
: ${COLOR_SKIP:=${COLOR_YELLOW}}
: ${COLOR_FAIL:=${COLOR_RED}}
: ${COLOR_PHASE:=${COLOR_LIGHT_MAGENTA}}
: ${COLOR_DRY_MODE:=${COLOR_GREEN}}

colorize_job_id() {
	[ $# -eq 2 ] || eargs colorize_job_id var_return job_id
	local var_return="$1"
	local job_id="$2"
	local color usebold id

	id=${job_id#0}

	# Use bold if going over 14, supporting 28 builder colors.
	if [ ${id} -gt 14 ]; then
		id=$((${id} - 14))
		usebold="${COLOR_BOLD}"
	fi

	case ${id} in
	1)  color="${COLOR_RED}" ;;
	2)  color="${COLOR_GREEN}" ;;
	3)  color="${COLOR_BROWN}" ;;
	4)  color="${COLOR_BLUE}" ;;
	5)  color="${COLOR_MAGENTA}" ;;
	6)  color="${COLOR_CYAN}" ;;
	7)  color="${COLOR_LIGHT_GRAY}" ;;
	8)  color="${COLOR_DARK_GRAY}" ;;
	9)  color="${COLOR_LIGHT_RED}" ;;
	10) color="${COLOR_LIGHT_GREEN}" ;;
	11) color="${COLOR_YELLOW}" ;;
	12) color="${COLOR_LIGHT_BLUE}" ;;
	13) color="${COLOR_LIGHT_MAGENTA}" ;;
	14) color="${COLOR_LIGHT_CYAN}" ;;
	*)  color="${COLOR_RESET}" ;;
	esac

	setvar "${var_return}" "${color}${usebold}"
}

msg_n() {
	local now elapsed

	elapsed=
	if should_show_elapsed; then
		now=$(date +%s)
		elapsed="[$(date -j -u -r $((${now} - ${TIME_START})) "+${DURATION_FORMAT}")] "
	fi
	printf "${elapsed}${DRY_MODE}${COLOR_ARROW}====>>${COLOR_RESET} ${1}${COLOR_RESET_REAL}"
}
msg() { msg_n "$@"; echo; }
msg_verbose() {
	[ ${VERBOSE} -gt 0 ] || return 0
	msg "$1"
}

msg_error() {
	COLOR_ARROW="${COLOR_ERROR}" \
	    msg "${COLOR_ERROR}Error: $1" >&2
	[ -n "${MY_JOBID}" ] && COLOR_ARROW="${COLOR_ERROR}" \
	    job_msg "${COLOR_ERROR}Error: $1"
}

msg_debug() {
	[ ${VERBOSE} -gt 1 ] || return 0
	COLOR_ARROW="${COLOR_DEBUG}" \
	    msg "${COLOR_DEBUG}Debug: $@" >&2
}

msg_warn() {
	COLOR_ARROW="${COLOR_WARN}" \
	    msg "${COLOR_WARN}Warning: $@" >&2
}

job_msg() {
	local now elapsed

	if [ -n "${MY_JOBID}" ]; then
		now=$(date +%s)
		elapsed="$(date -j -u -r $((${now} - ${TIME_START_JOB})) "+${DURATION_FORMAT}")"
		msg "[${COLOR_JOBID}${MY_JOBID}${COLOR_RESET}][${elapsed}] $1" >&5
	else
		msg "$1"
	fi
}

job_msg_verbose() {
	[ ${VERBOSE} -gt 0 ] || return 0
	job_msg "$@"
}
