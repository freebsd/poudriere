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

# Taken from bin/sh/mksyntax.sh is_in_name()
: ${HASH_VAR_NAME_SUB_GLOB:="[!a-zA-Z0-9_]"}
: ${HASH_VAR_NAME_PREFIX:="_HASH_"}

if ! type eargs 2>/dev/null >&2; then
	eargs() {
		local badcmd="$1"
		shift
		echo "Bad arguments, ${badcmd}: ""$@" >&2
		exit 1
	}
fi

if ! type _gsub 2>/dev/null >&2; then
# Based on Shell Scripting Recipes - Chris F.A. Johnson (c) 2005
# Replace a pattern without needing a subshell/exec
_gsub() {
	[ $# -eq 3 -o $# -eq 4 ] || eargs _gsub string pattern replacement \
	    [var_return]
	local string="$1"
	local pattern="$2"
	local replacement="$3"
	local var_return="${4:-_gsub}"
	local result_l= result_r="${string}"

	if [ -n "${pattern}" ]; then
		while :; do
			case ${result_r} in
			*${pattern}*)
				result_l=${result_l}${result_r%%${pattern}*}${replacement}
				result_r=${result_r#*${pattern}}
				;;
			*)
				break
				;;
		esac
		done
	fi

	setvar "${var_return}" "${result_l}${result_r}"
}
fi

if ! type _gsub_var_name 2>/dev/null >&2; then
_gsub_var_name() {
	[ $# -eq 2 ] || eargs _gsub_var_name string var_return
	_gsub "$1" "${HASH_VAR_NAME_SUB_GLOB}" _ "$2"
}
fi

if ! type _gsub_badchars 2>/dev/null >&2; then
_gsub_badchars() {
	[ $# -eq 3 ] || eargs _gsub_badchars string badchars var_return
	local string="$1"
	local badchars="$2"
	local var_return="$3"

	# Avoid !^- processing as this is just filtering bad characters
	# not a pattern.
	if [ "${badchars#!}" != "${badchars}" ]; then
		badchars="${badchars#!}!"
	elif [ "${badchars#^}" != "${badchars}" ]; then
		badchars="${badchars#^}^"
	fi
	case "${badchars}" in
	*-*) _gsub "${badchars}" "-" "" badchars ;;
	esac

	_gsub "${string}" "[${badchars}]" _ "${var_return}"
}
fi

if ! type gsub 2>/dev/null >&2; then
gsub() {
	local _gsub

	_gsub "$@"
	if [ -z "$4" ]; then
		echo "${_gsub}"
	fi
}
fi

_hash_var_name() {
	# Replace anything not HASH_VAR_NAME_SUB_GLOB with _
	_gsub_var_name "${HASH_VAR_NAME_PREFIX}${1}_${2}" \
	    _hash_var_name
}

hash_isset() {
	local -; set +x
	[ $# -ne 2 ] && eargs hash_isset var key
	local var="$1"
	local key="$2"
	local _hash_var_name _value

	_hash_var_name "${var}" "${key}"

	issetvar "${_hash_var_name}"
}

hash_get() {
	[ $# -ne 3 ] && eargs hash_get var key var_return
	local _hash_var_name

	_gsub_var_name "${HASH_VAR_NAME_PREFIX}${1}_${2}" _hash_var_name
	getvar "${_hash_var_name}" "${3}"
}

hash_set() {
	local -; set +x
	[ $# -eq 3 ] || eargs hash_set var key value
	local var="$1"
	local key="$2"
	local value="$3"
	local _hash_var_name

	_hash_var_name "${var}" "${key}"

	# Set value in cache
	setvar "${_hash_var_name}" "${value}"
}

hash_remove() {
	local -; set +x
	[ $# -ne 3 ] && eargs hash_remove var key var_return
	local var="$1"
	local key="$2"
	local var_return="$3"
	local _hash_var_name ret

	_hash_var_name "${var}" "${key}"
	ret=0
	getvar "${_hash_var_name}" "${var_return}" || ret=$?
	if [ ${ret} -eq 0 ]; then
		unset "${_hash_var_name}"
	fi
	return ${ret}
}

hash_unset() {
	local -; set +x
	[ $# -eq 2 ] || eargs hash_unset var key
	local var="$1"
	local key="$2"
	local _hash_var_name

	_hash_var_name "${var}" "${key}"
	unset "${_hash_var_name}"
}

list_contains() {
	[ $# -eq 2 ] || eargs list_contains var item
	local var="$1"
	local item="$2"
	local value

	getvar "${var}" value
	case " ${value} " in *" ${item} "*) ;; *) return 1 ;; esac
	return 0
}

list_add() {
	[ $# -eq 2 ] || eargs list_add var item
	local var="$1"
	local item="$2"
	local value

	getvar "${var}" value
	case " ${value} " in *" ${item} "*) return 0 ;; esac
	setvar "${var}" "${value:+${value} }${item}"
}

list_remove() {
	[ $# -eq 2 ] || eargs list_remove var item
	local var="$1"
	local item="$2"
	local value newvalue

	getvar "${var}" value
	value=" ${value} "
	case "${value}" in *" ${item} "*) ;; *) return 1 ;; esac
	newvalue="${value% "${item}" *} ${value##* "${item}" }"
	newvalue="${newvalue# }"
	newvalue="${newvalue% }"
	setvar "${var}" "${newvalue}"
}
