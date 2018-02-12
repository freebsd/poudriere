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

if ! type eargs 2>/dev/null >&2; then
	eargs() {
		local badcmd="$1"
		shift
		echo "Bad arguments, ${badcmd}: ""$@" >&2
		exit 1
	}
fi

# Based on Shell Scripting Recipes - Chris F.A. Johnson (c) 2005
# Replace a pattern without needing a subshell/exec
_gsub() {
	[ $# -ne 3 ] && eargs _gsub string pattern replacement
	local string="$1"
	local pattern="$2"
	local replacement="$3"
	local result_l= result_r="${string}"

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

	_gsub="${result_l}${result_r}"
}


gsub() {
	local _gsub

	_gsub "$@"
	echo "${_gsub}"
}

_hash_var_name() {
	local _gsub

	# Replace anything not HASH_VAR_NAME_SUB_GLOB with _
	_gsub "_HASH_${1}_${2}" "${HASH_VAR_NAME_SUB_GLOB}" _
	_hash_var_name=${_gsub}
}

hash_isset() {
	local -; set +x
	[ $# -ne 2 ] && eargs hash_isset var key
	local var="$1"
	local key="$2"
	local _hash_var_name _value

	_hash_var_name "${var}" "${key}"

	# Lookup value from cache
	eval "_value=\${${_hash_var_name}-__null}"

	[ "${_value}" != "__null" ]
}

_hash_get() {
	[ $# -eq 2 ] || eargs _hash_get _hash_var_name var_return
	local _hash_var_name="$1"
	local var_return="$2"
	local _value ret

	# Lookup value from cache
	eval "_value=\${${_hash_var_name}-__null}"

	if [ "${_value}" = "__null" ]; then
		_value=
		ret=1
	else
		ret=0
	fi

	setvar "${var_return}" "${_value}"

	return ${ret}
}

hash_get() {
	local -; set +x
	[ $# -ne 3 ] && eargs hash_get var key var_return
	local var="$1"
	local key="$2"
	local var_return="$3"
	local _hash_var_name

	_hash_var_name "${var}" "${key}"

	_hash_get "${_hash_var_name}" "${var_return}"
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
	_hash_get "${_hash_var_name}" "${var_return}" || ret=$?
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

list_add() {
	[ $# -eq 2 ] || eargs list_add var item
	local var="$1"
	local item="$2"
	local value

	eval "value=\"\${${var}}\""
	case "${value}" in *" ${item} "*) return 0 ;; esac
	setvar "${var}" "${value} ${item} "
}

list_remove() {
	[ $# -eq 2 ] || eargs list_remove var item
	local var="$1"
	local item="$2"
	local value

	eval "value=\"\${${var}}\""
	case "${value}" in *" ${item} "*) ;; *) return 0 ;; esac
	setvar "${var}" "${value% "${item}" *}${value##* "${item}" }"
}
