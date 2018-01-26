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

if [ -z "${FORCE_COLORS}" ]; then
	if ! [ -t 1 ] || ! [ -t 2 ]; then
		USE_COLORS="no"
	fi
fi

# The number of hardcoded color sets supported for colorize_job_id
MAXCOLORS=126

# Reset colors to be blank if colors are not being used.
# Actual definitions are in colors.pre.sh to allow user to override
# them and the below : {} lines in poudriere.conf.
if [ ${USE_COLORS} = "no" ]; then
	COLOR_RESET=
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
	COLOR_BG_BLACK=
	COLOR_BG_RED=
	COLOR_BG_GREEN=
	COLOR_BG_BROWN=
	COLOR_BG_BLUE=
	COLOR_BG_MAGENTA=
	COLOR_BG_CYAN=
	COLOR_BG_LIGHT_GRAY=
	COLOR_WHITE=
	D_LEFT=
	D_RIGHT=
	COLOR_PORT=
	COLOR_WARN=
	COLOR_DEBUG=
	COLOR_DEV=
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
	: ${COLOR_DEBUG:=${COLOR_LIGHT_BLUE}}
	: ${COLOR_DEV:=${COLOR_LIGHT_RED}}
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
	local color color_bg useinverse usebold id

	id=${job_id#0}
	usebold=
	useinverse=
	color_bg=

	# Effectively support 2 * MAXCOLORS
	if [ ${id} -gt ${MAXCOLORS} ]; then
		useinverse="${COLOR_INVERSE}${COLOR_UNDER}"
	fi

	# Writing this list was painful
	case $(((${id} - 1) % ${MAXCOLORS})) in
	0)   color="${COLOR_RED}" ;;
	1)   color="${COLOR_GREEN}" ;;
	2)   color="${COLOR_BROWN}" ;;
	3)   color="${COLOR_BLUE}" ;;
	4)   color="${COLOR_MAGENTA}" ;;
	5)   color="${COLOR_CYAN}" ;;
	6)   color="${COLOR_LIGHT_GRAY}" ;;
	7)   color="${COLOR_DARK_GRAY}" ;;
	8)   color="${COLOR_LIGHT_RED}" ;;
	9)   color="${COLOR_LIGHT_GREEN}" ;;
	10)  color="${COLOR_YELLOW}" ;;
	11)  color="${COLOR_LIGHT_BLUE}" ;;
	12)  color="${COLOR_LIGHT_MAGENTA}" ;;
	13)  color="${COLOR_LIGHT_CYAN}" ;;

	14) color="${COLOR_RED}"; usebold="${COLOR_BOLD}" ;;
	15) color="${COLOR_GREEN}"; usebold="${COLOR_BOLD}" ;;
	16) color="${COLOR_BROWN}"; usebold="${COLOR_BOLD}" ;;
	17) color="${COLOR_BLUE}"; usebold="${COLOR_BOLD}" ;;
	18) color="${COLOR_MAGENTA}"; usebold="${COLOR_BOLD}" ;;
	19) color="${COLOR_CYAN}"; usebold="${COLOR_BOLD}" ;;
	20) color="${COLOR_LIGHT_GRAY}"; usebold="${COLOR_BOLD}" ;;
	21) color="${COLOR_DARK_GRAY}"; usebold="${COLOR_BOLD}" ;;
	22) color="${COLOR_LIGHT_RED}"; usebold="${COLOR_BOLD}" ;;
	23) color="${COLOR_LIGHT_GREEN}"; usebold="${COLOR_BOLD}" ;;
	24) color="${COLOR_YELLOW}"; usebold="${COLOR_BOLD}" ;;
	25) color="${COLOR_LIGHT_BLUE}"; usebold="${COLOR_BOLD}" ;;
	26) color="${COLOR_LIGHT_MAGENTA}"; usebold="${COLOR_BOLD}" ;;
	27) color="${COLOR_LIGHT_CYAN}"; usebold="${COLOR_BOLD}" ;;

	28)  color="${COLOR_BLACK}"; color_bg="${COLOR_BG_RED}" ;;
	29)  color="${COLOR_RED}"; color_bg="${COLOR_BG_RED}"; usebold="${COLOR_BOLD}" ;;
	30)  color="${COLOR_GREEN}"; color_bg="${COLOR_BG_RED}" ;;
	31)  color="${COLOR_BROWN}"; color_bg="${COLOR_BG_RED}" ;;
	32)  color="${COLOR_YELLOW}"; color_bg="${COLOR_BG_RED}" ;;
	33)  color="${COLOR_BLUE}"; color_bg="${COLOR_BG_RED}" ;;
	34)  color="${COLOR_MAGENTA}"; color_bg="${COLOR_BG_RED}"; usebold="${COLOR_BOLD}" ;;
	35)  color="${COLOR_CYAN}"; color_bg="${COLOR_BG_RED}" ;;
	36)  color="${COLOR_WHITE}"; color_bg="${COLOR_BG_RED}" ;;

	37)  color="${COLOR_BLACK}"; color_bg="${COLOR_BG_GREEN}" ;;
	38)  color="${COLOR_RED}"; color_bg="${COLOR_BG_GREEN}" ;;
	39)  color="${COLOR_GREEN}"; color_bg="${COLOR_BG_GREEN}"; usebold="${COLOR_BOLD}" ;;
	40)  color="${COLOR_BROWN}"; color_bg="${COLOR_BG_GREEN}" ;;
	41)  color="${COLOR_YELLOW}"; color_bg="${COLOR_BG_GREEN}" ;;
	42)  color="${COLOR_BLUE}"; color_bg="${COLOR_BG_GREEN}" ;;
	43)  color="${COLOR_MAGENTA}"; color_bg="${COLOR_BG_GREEN}" ;;
	44)  color="${COLOR_CYAN}"; color_bg="${COLOR_BG_GREEN}"; usebold="${COLOR_BOLD}" ;;
	45)  color="${COLOR_WHITE}"; color_bg="${COLOR_BG_GREEN}" ;;

	46)  color="${COLOR_BLACK}"; color_bg="${COLOR_BG_BROWN}" ;;
	47)  color="${COLOR_RED}"; color_bg="${COLOR_BG_BROWN}" ;;
	48)  color="${COLOR_GREEN}"; color_bg="${COLOR_BG_BROWN}" ;;
	49)  color="${COLOR_BROWN}"; color_bg="${COLOR_BG_BROWN}"; usebold="${COLOR_BOLD}" ;;
	50)  color="${COLOR_BLUE}"; color_bg="${COLOR_BG_BROWN}" ;;
	51)  color="${COLOR_MAGENTA}"; color_bg="${COLOR_BG_BROWN}" ;;
	52)  color="${COLOR_CYAN}"; color_bg="${COLOR_BG_BROWN}" ;;
	53)  color="${COLOR_WHITE}"; color_bg="${COLOR_BG_BROWN}"; usebold="${COLOR_BOLD}" ;;

	54)  color="${COLOR_RED}"; color_bg="${COLOR_BG_BLUE}" ;;
	55)  color="${COLOR_DARK_GRAY}"; color_bg="${COLOR_BG_BLUE}" ;;
	56)  color="${COLOR_GREEN}"; color_bg="${COLOR_BG_BLUE}" ;;
	57)  color="${COLOR_BROWN}"; color_bg="${COLOR_BG_BLUE}" ;;
	58)  color="${COLOR_BLUE}"; color_bg="${COLOR_BG_BLUE}"; usebold="${COLOR_BOLD}" ;;
	59)  color="${COLOR_MAGENTA}"; color_bg="${COLOR_BG_BLUE}" ;;
	60)  color="${COLOR_CYAN}"; color_bg="${COLOR_BG_BLUE}" ;;
	61)  color="${COLOR_WHITE}"; color_bg="${COLOR_BG_BLUE}" ;;

	62)  color="${COLOR_BLACK}"; color_bg="${COLOR_BG_MAGENTA}" ;;
	63)  color="${COLOR_RED}"; color_bg="${COLOR_BG_MAGENTA}"; usebold="${COLOR_BOLD}" ;;
	64)  color="${COLOR_GREEN}"; color_bg="${COLOR_BG_MAGENTA}" ;;
	65)  color="${COLOR_BROWN}"; color_bg="${COLOR_BG_MAGENTA}" ;;
	66)  color="${COLOR_BLUE}"; color_bg="${COLOR_BG_MAGENTA}" ;;
	67)  color="${COLOR_MAGENTA}"; color_bg="${COLOR_BG_MAGENTA}"; usebold="${COLOR_BOLD}" ;;
	68)  color="${COLOR_CYAN}"; color_bg="${COLOR_BG_MAGENTA}" ;;
	69)  color="${COLOR_WHITE}"; color_bg="${COLOR_BG_MAGENTA}" ;;

	70)  color="${COLOR_BLACK}"; color_bg="${COLOR_BG_CYAN}" ;;
	71)  color="${COLOR_RED}"; color_bg="${COLOR_BG_CYAN}" ;;
	72)  color="${COLOR_GREEN}"; color_bg="${COLOR_BG_CYAN}"; usebold="${COLOR_BOLD}" ;;
	73)  color="${COLOR_BROWN}"; color_bg="${COLOR_BG_CYAN}" ;;
	74)  color="${COLOR_BLUE}"; color_bg="${COLOR_BG_CYAN}" ;;
	75)  color="${COLOR_MAGENTA}"; color_bg="${COLOR_BG_CYAN}" ;;
	76)  color="${COLOR_DARK_GRAY}"; color_bg="${COLOR_BG_CYAN}" ;;
	77)  color="${COLOR_CYAN}"; color_bg="${COLOR_BG_CYAN}"; usebold="${COLOR_BOLD}" ;;
	78)  color="${COLOR_WHITE}"; color_bg="${COLOR_BG_CYAN}" ;;

	79)  color="${COLOR_BLACK}"; color_bg="${COLOR_BG_LIGHT_GRAY}" ;;
	80)  color="${COLOR_RED}"; color_bg="${COLOR_BG_LIGHT_GRAY}" ;;
	81)  color="${COLOR_GREEN}"; color_bg="${COLOR_BG_LIGHT_GRAY}" ;;
	82)  color="${COLOR_BROWN}"; color_bg="${COLOR_BG_LIGHT_GRAY}"; usebold="${COLOR_BOLD}" ;;
	83)  color="${COLOR_BLUE}"; color_bg="${COLOR_BG_LIGHT_GRAY}" ;;
	84)  color="${COLOR_MAGENTA}"; color_bg="${COLOR_BG_LIGHT_GRAY}" ;;
	85)  color="${COLOR_CYAN}"; color_bg="${COLOR_BG_LIGHT_GRAY}" ;;
	86)  color="${COLOR_WHITE}"; color_bg="${COLOR_BG_LIGHT_GRAY}"; usebold="${COLOR_BOLD}" ;;

	87)  color="${COLOR_GREEN}"; color_bg="${COLOR_BG_RED}"; usebold="${COLOR_BOLD}" ;;
	88)  color="${COLOR_BROWN}"; color_bg="${COLOR_BG_RED}"; usebold="${COLOR_BOLD}" ;;
	89)  color="${COLOR_CYAN}"; color_bg="${COLOR_BG_RED}"; usebold="${COLOR_BOLD}" ;;
	90)  color="${COLOR_WHITE}"; color_bg="${COLOR_BG_RED}"; usebold="${COLOR_BOLD}" ;;

	91)  color="${COLOR_RED}"; color_bg="${COLOR_BG_GREEN}"; usebold="${COLOR_BOLD}" ;;
	92)  color="${COLOR_BROWN}"; color_bg="${COLOR_BG_GREEN}"; usebold="${COLOR_BOLD}" ;;
	93)  color="${COLOR_MAGENTA}"; color_bg="${COLOR_BG_GREEN}"; usebold="${COLOR_BOLD}" ;;
	94)  color="${COLOR_WHITE}"; color_bg="${COLOR_BG_GREEN}"; usebold="${COLOR_BOLD}" ;;

	95)  color="${COLOR_BLACK}"; color_bg="${COLOR_BG_BROWN}"; usebold="${COLOR_BOLD}" ;;
	96)  color="${COLOR_RED}"; color_bg="${COLOR_BG_BROWN}"; usebold="${COLOR_BOLD}" ;;
	97)  color="${COLOR_GREEN}"; color_bg="${COLOR_BG_BROWN}"; usebold="${COLOR_BOLD}" ;;
	98)  color="${COLOR_MAGENTA}"; color_bg="${COLOR_BG_BROWN}"; usebold="${COLOR_BOLD}" ;;
	99)  color="${COLOR_CYAN}"; color_bg="${COLOR_BG_BROWN}"; usebold="${COLOR_BOLD}" ;;

	100)  color="${COLOR_BLACK}"; color_bg="${COLOR_BG_BLUE}"; usebold="${COLOR_BOLD}" ;;
	101)  color="${COLOR_RED}"; color_bg="${COLOR_BG_BLUE}"; usebold="${COLOR_BOLD}" ;;
	102)  color="${COLOR_GREEN}"; color_bg="${COLOR_BG_BLUE}"; usebold="${COLOR_BOLD}" ;;
	103)  color="${COLOR_BROWN}"; color_bg="${COLOR_BG_BLUE}"; usebold="${COLOR_BOLD}" ;;
	104)  color="${COLOR_MAGENTA}"; color_bg="${COLOR_BG_BLUE}"; usebold="${COLOR_BOLD}" ;;
	105)  color="${COLOR_CYAN}"; color_bg="${COLOR_BG_BLUE}"; usebold="${COLOR_BOLD}" ;;
	106)  color="${COLOR_WHITE}"; color_bg="${COLOR_BG_BLUE}"; usebold="${COLOR_BOLD}" ;;

	107)  color="${COLOR_BLACK}"; color_bg="${COLOR_BG_MAGENTA}"; usebold="${COLOR_BOLD}" ;;
	108)  color="${COLOR_GREEN}"; color_bg="${COLOR_BG_MAGENTA}"; usebold="${COLOR_BOLD}" ;;
	109)  color="${COLOR_BROWN}"; color_bg="${COLOR_BG_MAGENTA}"; usebold="${COLOR_BOLD}" ;;
	110)  color="${COLOR_BLUE}"; color_bg="${COLOR_BG_MAGENTA}"; usebold="${COLOR_BOLD}" ;;
	111)  color="${COLOR_CYAN}"; color_bg="${COLOR_BG_MAGENTA}"; usebold="${COLOR_BOLD}" ;;
	112)  color="${COLOR_WHITE}"; color_bg="${COLOR_BG_MAGENTA}"; usebold="${COLOR_BOLD}" ;;

	113)  color="${COLOR_BLACK}"; color_bg="${COLOR_BG_CYAN}"; usebold="${COLOR_BOLD}" ;;
	114) color="${COLOR_RED}"; color_bg="${COLOR_BG_CYAN}"; usebold="${COLOR_BOLD}" ;;
	115) color="${COLOR_GREEN}"; color_bg="${COLOR_BG_CYAN}"; usebold="${COLOR_BOLD}" ;;
	116) color="${COLOR_BROWN}"; color_bg="${COLOR_BG_CYAN}"; usebold="${COLOR_BOLD}" ;;
	117) color="${COLOR_BLUE}"; color_bg="${COLOR_BG_CYAN}"; usebold="${COLOR_BOLD}" ;;
	118) color="${COLOR_MAGENTA}"; color_bg="${COLOR_BG_CYAN}"; usebold="${COLOR_BOLD}" ;;
	119) color="${COLOR_WHITE}"; color_bg="${COLOR_BG_CYAN}"; usebold="${COLOR_BOLD}" ;;

	120) color="${COLOR_BLACK}"; color_bg="${COLOR_BG_LIGHT_GRAY}"; usebold="${COLOR_BOLD}" ;;
	121) color="${COLOR_RED}"; color_bg="${COLOR_BG_LIGHT_GRAY}"; usebold="${COLOR_BOLD}" ;;
	122) color="${COLOR_GREEN}"; color_bg="${COLOR_BG_LIGHT_GRAY}"; usebold="${COLOR_BOLD}" ;;
	123) color="${COLOR_BLUE}"; color_bg="${COLOR_BG_LIGHT_GRAY}"; usebold="${COLOR_BOLD}" ;;
	124) color="${COLOR_MAGENTA}"; color_bg="${COLOR_BG_LIGHT_GRAY}"; usebold="${COLOR_BOLD}" ;;
	125) color="${COLOR_CYAN}"; color_bg="${COLOR_BG_LIGHT_GRAY}"; usebold="${COLOR_BOLD}" ;;

	*)  color="${COLOR_RESET}" ;;
	esac

	setvar "${var_return}" "${color}${color_bg}${usebold}${useinverse}"
}

test_colors() {
	local i job_color

	i=1

	while [ $i -le $((${MAXCOLORS} * 2)) ]; do
		colorize_job_id job_color "$i"
		printf -- "--- [${job_color}%03d${COLOR_RESET}] ---\n" "${i}"
		i=$((${i} + 1))
	done
}
