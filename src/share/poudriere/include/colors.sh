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

if ! [ -t 1 ] || ! [ -t 2 ]; then
	USE_COLORS="no"
fi

# Reset colors to be blank if colors are not being used.
# Actual definitions are in colors.pre.sh to allow user to override
# them and the below : {} lines in poudriere.conf.
if [ ${USE_COLORS} = "no" ]; then
	COLOR_RESET=
	COLOR_RESET_REAL=
	COLOR_BOLD=
	COLOR_UNDER=
	COLOR_BLINK=
	COLOR_BLACK=
	COLOR_RED=
	COLOR_GREEN=
	COLOR_BROWN=
	COLOR_BLUE=
	COLOR_MAGENTA=
	COLOR_CYAN=
	COLOR_LIGHT_GRAY=
	COLOR_DARK_GRAY=
	COLOR_LIGHT_RED=
	COLOR_LIGHT_GREEN=
	COLOR_YELLOW=
	COLOR_LIGHT_BLUE=
	COLOR_LIGHT_MAGENTA=
	COLOR_LIGHT_CYAN=
	COLOR_WHITE=
	D_LEFT=
	D_RIGHT=
	COLOR_PORT=
	COLOR_WARN=
	COLOR_DEBUG=
	COLOR_ERROR=
	COLOR_SUCCESS=
	COLOR_IGNORE=
	COLOR_SKIP=
	COLOR_FAIL=
	COLOR_PHASE=
	COLOR_DRY_MODE=
else

	: ${D_LEFT:="${COLOR_BOLD}[${COLOR_RESET}"}
	: ${D_RIGHT:="${COLOR_BOLD}]${COLOR_RESET}"}

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
fi

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
