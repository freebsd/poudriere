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

EX_DATAERR=65
EX_SOFTWARE=70

DISPLAY_SEP=$'\002'
DISPLAY_USE_COLUMN=0
DISPLAY_DYNAMIC_FORMAT_DEFAULT="%%-%ds"
DISPLAY_TRIM_TRAILING_FIELD=1

display_setup() {
	[ $# -eq 1 ] || [ $# -eq 2 ] || eargs display_setup format [column_sort]
	local IFS
	local -; set -f
	set +x

	_DISPLAY_FORMAT="${1:-dynamic}"
	_DISPLAY_HEADER=
	_DISPLAY_COLUMN_SORT="${2-}"
	_DISPLAY_FOOTER=
	_DISPLAY_LINES=0
	_DISPLAY_COLS=0
	_DISPLAY_MAPFILE=
	_DISPLAY_TMP=$(mktemp -t data)

	mapfile _DISPLAY_MAPFILE "${_DISPLAY_TMP}" "w" ||
	    err ${EX_SOFTWARE} "mapfile"

	# encode
	set -- ${_DISPLAY_FORMAT}
	IFS="${DISPLAY_SEP}"
	_DISPLAY_FORMAT="$*"
	unset IFS
}

_display_cleanup() {
	rm -f "${_DISPLAY_TMP}" "${_DISPLAY_TMP}.filtered"
	unset _DISPLAY_FORMAT \
	    _DISPLAY_COLUMN_SORT \
	    _DISPLAY_LINES _DISPLAY_COLS \
	    _DISPLAY_FOOTER _DISPLAY_HEADER \
	    _DISPLAY_MAPFILE _DISPLAY_TMP
}

display_add() {
	[ $# -gt 0 ] || eargs display_add col [col...]
	local IFS
	local -
	set +x

	if [ -z "${_DISPLAY_HEADER}" ]; then
		local arg argi line argformat format

		argi=1
		unset line
		format=
		for arg do
			# Collect header custom formats if using dynamic
			if [ "${_DISPLAY_FORMAT}" == "dynamic" ]; then
				case "${arg}" in
				*:*%%*)
					argformat="${arg#*:}"
					arg="${arg%%:*}"
					;;
				*)
					argformat="${DISPLAY_DYNAMIC_FORMAT_DEFAULT}"
					;;
				esac
				format="${format:+${format}${DISPLAY_SEP}}${argformat}"
			fi
			line="${line:+${line}${DISPLAY_SEP}}${arg}"
			hash_set _display_header "${arg}" "${argi}"
			argi=$((argi + 1))
		done
		_DISPLAY_COLS=$((argi - 1))
		_DISPLAY_HEADER="${line}"
		if [ "${_DISPLAY_FORMAT}" == "dynamic" ]; then
			_DISPLAY_FORMAT="${format}"
		fi

		return
	fi

	# Add in newline
	_DISPLAY_LINES=$((_DISPLAY_LINES + 1))
	# encode
	IFS="${DISPLAY_SEP}"
	line="$*"
	unset IFS
	mapfile_write "${_DISPLAY_MAPFILE}" -- "${line}" ||
	    err ${EX_SOFTWARE} "mapfile_write"
}

display_footer() {
	local IFS

	# encode
	IFS="${DISPLAY_SEP}"
	_DISPLAY_FOOTER="$*"
	unset IFS
}

_display_check_lengths() {
	local cnt arg max_length
	local IFS
	local -; set -f
	set +x

	# decode
	IFS="${DISPLAY_SEP}"
	set -- $@
	unset IFS

	cnt=0
	for arg in "$@"; do
		cnt=$((cnt + 1))
		if [ -z "${arg}" ]; then
			continue
		fi
		stripansi "${arg}" arg
		hash_get _display_lengths "${cnt}" max_length || max_length=0
		if [ "${#arg}" -gt "${max_length}" ]; then
			hash_set _display_lengths "${cnt}" "${#arg}"
		fi
	done
}

_display_output() {
	[ $# -eq 2 ] || eargs _display_output format data
	local -; set -f
	set +x
	local format="$1"
	local data="$2"
	local IFS

	# decode
	IFS="${DISPLAY_SEP}"
	set -- ${data}
	unset IFS
	printf "${format}\n" "$@"
}

# display_output [col ...]
display_output() {
	local lengths format arg flag quiet line n
	local cols header_format
	local OPTIND=1
	local IFS
	local -

	set +x
	set -f

	quiet=0

	while getopts "q" flag; do
		case "${flag}" in
			q)
				quiet=1
				;;
			*)
				err 1 "display_output: Invalid flag"
				;;
		esac
	done

	shift $((OPTIND-1))

	mapfile_close "${_DISPLAY_MAPFILE}" ||
	    err ${EX_SOFTWARE} "mapfile_close"

	# cols to filter/reorder on
	cols=
	if [ "$#" -gt 0 ]; then
		local col awktmp

		if [ "$#" -gt 0 ]; then
			_DISPLAY_COLS=0
		fi
		for arg in "$@"; do
			if ! hash_remove _display_header "${arg}" col; then
				err ${EX_DATAERR:?} "No column named '${arg}'"
			fi
			# cols="$3,$2,$1" for awk printing
			cols="${cols:+${cols},}\$${col}"
			_DISPLAY_COLS=$((_DISPLAY_COLS + 1))
		done

		# Re-order and filter using awk(1) back into our internal vars.
		awktmp=$(mktemp -t display_output)
		{
			echo "${_DISPLAY_FORMAT}"
			echo "${_DISPLAY_HEADER}"
			sort -t "${DISPLAY_SEP}" ${_DISPLAY_COLUMN_SORT} \
			    "${_DISPLAY_TMP}"
			echo "${_DISPLAY_FOOTER}"
		} > "${awktmp}.in"
		awk -F"${DISPLAY_SEP}" -vOFS="${DISPLAY_SEP}" \
		    "{print ${cols}}" "${awktmp}.in" > "${awktmp}"
		n=-1
		while IFS= mapfile_read_loop "${awktmp}" line; do
			case "${n}" in
			-1)
				_DISPLAY_FORMAT="${line}"
				;;
			0)
				_DISPLAY_HEADER="${line}"
				;;
			"$((_DISPLAY_LINES + 1))")
				if [ -n "${_DISPLAY_FOOTER}" ]; then
					_DISPLAY_FOOTER="${line}"
				fi
				;;
			*)
				echo "${line}"
				if [ "${DISPLAY_USE_COLUMN}" -eq 0 ]; then
					_display_check_lengths "${line}"
				fi
				;;
			esac
			n=$((n + 1))
		done > "${_DISPLAY_TMP}.filtered"
		rm -f "${awktmp}" "${awktmp}.in"
	else
		# using > rather than -o skips vfork which can't handle
		# redirects
		sort -t "${DISPLAY_SEP}" ${_DISPLAY_COLUMN_SORT} \
		    -o "${_DISPLAY_TMP}.filtered" "${_DISPLAY_TMP}"
	fi

	if [ "${DISPLAY_USE_COLUMN}" -eq 1 ]; then
		{
			if [ "${quiet}" -eq 0 ]; then
				echo "${_DISPLAY_HEADER}"
			fi
			mapfile_cat_file "${_DISPLAY_TMP}.filtered"
			if [ -n "${_DISPLAY_FOOTER}" ]; then
				echo "${_DISPLAY_FOOTER}"
			fi
		} | column -t -s "${DISPLAY_SEP}"
		_display_cleanup
		return
	fi

	# Determine optimal format from filtered data
	_display_check_lengths "${_DISPLAY_HEADER}"
	_display_check_lengths "${_DISPLAY_FOOTER}"
	if [ -z "${cols}" ]; then
		while IFS= mapfile_read_loop "${_DISPLAY_TMP}.filtered" line; do
			_display_check_lengths "${line}"
		done
	fi

	# Set format lengths if format is dynamic width
	# decode
	IFS="${DISPLAY_SEP}"
	set -- ${_DISPLAY_FORMAT}
	unset IFS
	format="$*"
	case "${format}" in
	*%%*)
		local length

		set -- ${format}
		lengths=
		n=1
		for arg in "$@"; do
			# Check if this is a format argument
			case "${arg}" in
			*%*) ;;
			*) continue ;;
			esac
			case ${arg} in
			*%d*)
				hash_remove _display_lengths "${n}" length
				if [ "${DISPLAY_TRIM_TRAILING_FIELD}" -eq 1 ] &&
				    [ "${n}" -eq "${_DISPLAY_COLS}" ]; then
					case "${arg}" in
					*-*) length=0 ;;
					esac
				fi
				lengths="${lengths:+${lengths} }${length}"
				;;
			*)
				hash_unset _display_lengths "${n}" || :
				;;
			esac
			n=$((n + 1))
		done
		format=$(printf "${format}" ${lengths})
		;;
	esac

	# Header
	if [ "${quiet}" -eq 0 ]; then
		stripansi "${_DISPLAY_HEADER}" _DISPLAY_HEADER
		stripansi "${format}" header_format
		_display_output "${header_format}" "${_DISPLAY_HEADER}"
	fi

	# Data
	while IFS= mapfile_read_loop "${_DISPLAY_TMP}.filtered" line; do
		_display_output "${format}" "${line}"
	done

	# Footer
	if [ -n "${_DISPLAY_FOOTER}" ]; then
		_display_output "${format}" "${_DISPLAY_FOOTER}"
	fi
	_display_cleanup
}
