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
		echo "Bad arguments, ${badcmd}: $*" >&2
		exit 1
	}
fi

if ! type mapfile_read_loop_redir 2>/dev/null >&2; then
	mapfile_read_loop_redir() {
		read -r "$@"
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

	case "${pattern:+set}" in
	set)
		while :; do
			# shellcheck disable=SC2295
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
		;;
	esac

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
	while :; do
		case "${badchars}" in
		"!^") break ;;
		"!"*) badchars="${badchars#!}!" ;;
		"^"*) badchars="${badchars#^}^" ;;
		*) break ;;
		esac
	done
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
	case "${4-}" in
	"") echo "${_gsub}" ;;
	esac
}
fi

_hash_var_name() {
	# Replace anything not HASH_VAR_NAME_SUB_GLOB with _
	_gsub_var_name "${HASH_VAR_NAME_PREFIX}B${1}_K${2}" _hash_var_name
}

hash_isset() {
	local -; set +x
	[ $# -eq 2 ] || eargs hash_isset var key
	local _var="$1"
	local _key="$2"
	local _hash_var_name

	_hash_var_name "${_var}" "${_key}"
	issetvar "${_hash_var_name}"
}

hash_isset_var() {
	local -; set +x
	[ $# -eq 1 ] || eargs hash_isset_var var
	local _var="$1"
	local _line _hash_var_name ret IFS

	_hash_var_name "${_var}" ""
	ret=1
	while IFS= mapfile_read_loop_redir _line; do
		# XXX: mapfile_read_loop can't safely return/break
		if [ "${ret}" -eq 0 ]; then
			continue
		fi
		case "${_line}" in
		${_hash_var_name}*=*)
			ret=0
			;;
		*) continue ;;
		esac
	done <<-EOF
	$(set)
	EOF
	return "${ret}"
}

hash_get() {
	local -; set +x
	[ $# -eq 3 ] || eargs hash_get var key var_return
	local _var="$1"
	local _key="$2"
	local _hash_var_name

	_hash_var_name "${_var}" "${_key}"
	getvar "${_hash_var_name}" "${3}"
}

hash_push() {
	hash_push_front "$@"
}

hash_push_front() {
	local -; set +x
	[ $# -eq 3 ] || eargs hash_push_front var key value
	local hpf_var="$1"
	local hpf_key="$2"
	local hpf_value="$3"
	local _hash_var_name

	_hash_var_name "${hpf_var}" "${hpf_key}"
	stack_push "${_hash_var_name}" "${hpf_value}" || return "$?"
}

hash_push_back() {
	local -; set +x
	[ $# -eq 3 ] || eargs hash_push_back var key value
	local hp_var="$1"
	local hp_key="$2"
	local hp_value="$3"
	local _hash_var_name

	_hash_var_name "${hp_var}" "${hp_key}"
	stack_push_back "${_hash_var_name}" "${hp_value}" || return "$?"
}

hash_pop() {
	hash_pop_front "$@"
}

hash_pop_front() {
	local -; set +x
	[ $# -eq 3 ] || eargs hash_pop_front var key var_return
	local hpf_var="$1"
	local hpf_key="$2"
	local hpf_var_return="$3"
	local _hash_var_name

	_hash_var_name "${hpf_var}" "${hpf_key}"
	stack_pop "${_hash_var_name}" "${hpf_var_return}" || return "$?"
}

hash_pop_back() {
	local -; set +x
	[ $# -eq 3 ] || eargs hash_pop_back var key var_return
	local hp_var="$1"
	local hp_key="$2"
	local hp_var_return="$3"
	local _hash_var_name

	_hash_var_name "${hp_var}" "${hp_key}"
	stack_pop_back "${_hash_var_name}" "${hp_var_return}" || return "$?"
}

hash_foreach() {
	hash_foreach_front "$@"
}

hash_foreach_front() {
	local -; set +x
	[ $# -eq 4 ] || eargs hash_foreach_front var key var_return tmp_var
	local hff_var="$1"
	local hff_key="$2"
	local hff_var_return="$3"
	local hff_tmp_var="$4"
	local _hash_var_name

	_hash_var_name "${hff_var}" "${hff_key}"
	stack_foreach "${_hash_var_name}" "${hff_var_return}" "${hff_tmp_var}" ||
	    return "$?"
}

hash_foreach_back() {
	local -; set +x
	[ $# -eq 4 ] || eargs hash_foreach_back var key var_return tmp_var
	local hfb_var="$1"
	local hfb_key="$2"
	local hfb_var_return="$3"
	local hfb_tmp_var="$4"
	local _hash_var_name

	_hash_var_name "${hfb_var}" "${hfb_key}"
	stack_foreach_back "${_hash_var_name}" "${hfb_var_return}" \
	    "${hfb_tmp_var}" || return "$?"
}

hash_set() {
	local -; set +x
	[ $# -eq 3 ] || eargs hash_set var key value
	local _var="$1"
	local _key="$2"
	local _value="$3"
	local _hash_var_name

	_hash_var_name "${_var}" "${_key}"
	setvar "${_hash_var_name}" "${_value}"
}

hash_remove() {
	local -; set +x
	[ $# -eq 3 ] || eargs hash_remove var key var_return
	local _var="$1"
	local _key="$2"
	local var_return="$3"
	local _hash_var_name ret

	_hash_var_name "${_var}" "${_key}"
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
	local _var="$1"
	local _key="$2"
	local _hash_var_name

	_hash_var_name "${_var}" "${_key}"
	unset "${_hash_var_name}"
}

hash_unset_var() {
	local -; set +x
	[ $# -eq 1 ] || eargs hash_unset_var var
	local _var="$1"
	local _key _line _hash_var_name

	_hash_var_name "${_var}" ""
	while IFS= mapfile_read_loop_redir _line; do
		case "${_line}" in
		"${_hash_var_name}"*=*) ;;
		*) continue ;;
		esac
		_key="${_line%%=*}"
		unset "${_key}"
	done <<-EOF
	$(set)
	EOF
}

list_contains() {
	local -; set +x
	[ $# -eq 2 ] || eargs list_contains var item
	local _var="$1"
	local item="$2"
	local _value

	getvar "${_var}" _value || _value=
	case " ${_value} " in *" ${item} "*) ;; *) return 1 ;; esac
	return 0
}

list_add() {
	local -; set +x
	[ $# -eq 2 ] || eargs list_add var item
	local _var="$1"
	local item="$2"
	local _value

	getvar "${_var}" _value || _value=
	case " ${_value} " in *" ${item} "*) return 0 ;; esac
	setvar "${_var}" "${_value:+${_value} }${item}"
}

list_remove() {
	local -; set +x
	[ $# -eq 2 ] || eargs list_remove var item
	local _var="$1"
	local item="$2"
	local _value newvalue

	getvar "${_var}" _value || _value=
	_value=" ${_value} "
	case "${_value}" in *" ${item} "*) ;; *) return 1 ;; esac
	newvalue="${_value% "${item}" *} ${_value##* "${item}" }"
	newvalue="${newvalue# }"
	newvalue="${newvalue% }"
	setvar "${_var}" "${newvalue}"
}

stack_push() {
	stack_push_front "$@"
}

stack_push_front() {
	local -; set +x
	[ $# -eq 2 ] || eargs stack_push_front var item
	local spf_var="$1"
	local spf_item="$2"
	local spf_value

	getvar "${spf_var}" spf_value || spf_value=
	setvar "${spf_var}" "${spf_item}${spf_value:+ ${spf_value}}"
}

stack_push_back() {
	local -; set +x
	[ $# -eq 2 ] || eargs stack_push_back var item
	local spb_var="$1"
	local spb_item="$2"
	local spb_value

	getvar "${spb_var}" spb_value || spb_value=
	setvar "${spb_var}" "${spb_value:+${spb_value} }${spb_item}"
}

stack_pop() {
	stack_pop_front "$@"
}

stack_pop_front() {
	local -; set +x
	[ $# -eq 2 ] || eargs stack_pop_front var item_var_return
	local spf_var="$1"
	local spf_item_var_return="$2"
	local spf_value spf_item

	getvar "${spf_var}" spf_value || spf_value=
	case "${spf_value}" in
	"")
		# In a for loop
		setvar "${spf_item_var_return}" ""
		unset "${spf_var}"
		return 1
		;;
	esac
	spf_item="${spf_value%% *}"
	case "${spf_item}" in
	"${spf_value}" )
		# Last pop
		spf_value=""
		;;
	*)
		spf_value="${spf_value#* }"
		;;
	esac
	setvar "${spf_var}" "${spf_value}"
	setvar "${spf_item_var_return}" "${spf_item}"
}

stack_pop_back() {
	local -; set +x
	[ $# -eq 2 ] || eargs stack_pop_back var item_var_return
	local spb_var="$1"
	local spb_item_var_return="$2"
	local spb_value spb_item

	getvar "${spb_var}" spb_value || spb_value=
	case "${spb_value}" in
	"")
		# In a for loop
		setvar "${spb_item_var_return}" ""
		unset "${spb_var}"
		return 1
		;;
	esac
	spb_item="${spb_value##* }"
	case "${spb_item}" in
	"${spb_value}" )
		# Last pop
		spb_value=""
		;;
	*)
		spb_value="${spb_value% *}"
		;;
	esac
	setvar "${spb_var}" "${spb_value}"
	setvar "${spb_item_var_return}" "${spb_item}"
}

stack_foreach() {
	stack_foreach_front "$@"
}

stack_foreach_front() {
	local -; set +x
	[ "$#" -eq 3 ] || eargs stack_foreach_front var item_var_return tmp_var
	local sff_var="$1"
	local sff_item_var_return="$2"
	local sff_tmp_var="$3"
	local sff_tmp_stack

	if ! getvar "${sff_tmp_var}" sff_tmp_stack; then
		getvar "${sff_var}" sff_tmp_stack || return 1
	fi
	if stack_pop sff_tmp_stack "${sff_item_var_return}"; then
		setvar "${sff_tmp_var}" "${sff_tmp_stack-}"
		return 0
	else
		unset "${sff_tmp_var}"
		return 1
	fi
}

stack_foreach_back() {
	local -; set +x
	[ "$#" -eq 3 ] || eargs stack_foreach_back var item_var_return tmp_var
	local sf_var="$1"
	local sf_item_var_return="$2"
	local sf_tmp_var="$3"
	local sf_tmp_stack

	if ! getvar "${sf_tmp_var}" sf_tmp_stack; then
		getvar "${sf_var}" sf_tmp_stack || return 1
	fi
	if stack_pop_back sf_tmp_stack "${sf_item_var_return}"; then
		setvar "${sf_tmp_var}" "${sf_tmp_stack-}"
		return 0
	else
		unset "${sf_tmp_var}"
		return 1
	fi
}
