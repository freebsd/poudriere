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

# shellcheck shell=ksh

# Taken from bin/sh/mksyntax.sh is_in_name()
: "${HASH_VAR_NAME_SUB_GLOB:="[!a-zA-Z0-9_]"}"
: "${HASH_VAR_NAME_PREFIX:="_HASH_"}"
: "${STACK_SEP:="$'\002'"}"

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
	[ "$#" -eq 3 ] || [ "$#" -eq 4 ] ||
	    eargs _gsub string pattern replacement '[var_return]'
	local gsub_str="$1"
	local gsub_pat="$2"
	local gsub_repl="$3"
	local gsub_out_var="${4:-_gsub}"
	local gsub_res_l gsub_res_r

	gsub_res_l=
	gsub_res_r="${gsub_str}"

	# Trying to match everything really means any char.
	# Without this we get into an infinite loop on this case.
	case "${gsub_pat}" in
	"*") gsub_pat="?" ;;
	esac

	case "${gsub_pat:+set}" in
	set)
		while :; do
			case ${gsub_res_r} in
			*${gsub_pat}*)
				# shellcheck disable=SC2295
				gsub_res_l=${gsub_res_l}${gsub_res_r%%${gsub_pat}*}${gsub_repl}
				# shellcheck disable=SC2295
				gsub_res_r=${gsub_res_r#*${gsub_pat}}
				;;
			*)
				break
				;;
		esac
		done
		;;
	esac

	setvar "${gsub_out_var}" "${gsub_res_l}${gsub_res_r}"
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
	*-*)
		_gsub "${badchars}" "-" "" badchars
		badchars="${badchars}-"
		;;
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

hash_vars() {
	local -; set +x
	[ "$#" -eq 3 ] || [ "$#" -eq 2 ] ||
	    eargs hash_vars var_return 'var|*' 'key|*'
	local _hash_vars_return="$1"
	local _hash_vars_var="$2"
	local _hash_vars_key="${3:-*}"
	local _hash_vars_list hv_line hv_lkey

	_hash_vars_list=
	while read -r hv_line; do
		# shellcheck disable=SC2027
		case "${hv_line}" in
		"${HASH_VAR_NAME_PREFIX:?}B"${_hash_vars_var:?}"_K"${_hash_vars_key:?}"="*)
			# shellcheck disable=SC2295
			hv_line="${hv_line#"${HASH_VAR_NAME_PREFIX:?}"B}"
			hv_line="${hv_line%%=*}"
			hv_lkey="${hv_line}"
			hv_lkey="${hv_line##*_K}"
			hv_line="${hv_line%%_K*}"
			_hash_vars_list="${_hash_vars_list:+${_hash_vars_list} }${hv_line:?}:${hv_lkey:?}"
			;;
		esac
	done <<-EOF
	$(set)
	EOF
	case "${_hash_vars_return:?}" in
	""|"-")
		case "${_hash_vars_list?}" in
		"") ;;
		*)
			echo "${_hash_vars_list?}"
			;;
		esac
		;;
	*)
		setvar "${_hash_vars_return:?}" "${_hash_vars_list?}" ||
		    return
		;;
	esac
	case "${_hash_vars_list?}" in
	"")
		return 1
		;;
	esac
	return 0
}

hash_assert_no_vars() {
       local -; set +x
       [ "$#" -eq 1 ] || [ "$#" -eq 2 ] ||
           eargs hash_assert_no_vars 'var|*' 'key|*'
       local hanv_var="$1"
       local hanv_key="${2-}"
       local hanv_vars

       if ! hash_vars hanv_vars "${hanv_var:?}" "${hanv_key}"; then
               return 0
       fi
       for hanv_var in ${hanv_vars}; do
	       msg_warn "Leaked hash var: ${hanv_var}"
       done
       return 1
}

hash_isset() {
	local -; set +x
	[ $# -eq 2 ] || eargs hash_isset var key
	local hi_var="$1"
	local hi_key="$2"
	local _hash_var_name

	_hash_var_name "${hi_var}" "${hi_key}"
	isset "${_hash_var_name}"
}

hash_isset_var() {
	local -; set +x
	[ $# -eq 1 ] || eargs hash_isset_var var
	local hiv_var="$1"
	local hiv_line _hash_var_name IFS
	local -

	set -o noglob
	_hash_var_name "${hiv_var}" ""
	while IFS= mapfile_read_loop_redir hiv_line; do
		case "${hiv_line}" in
		${_hash_var_name}*=*)
			return 0
			;;
		esac
	done <<-EOF
	$(set)
	EOF
	return 1
}

hash_get() {
	local -; set +x
	[ $# -eq 3 ] || eargs hash_get var key var_return EARGS: "$@"
	local hg_var="$1"
	local hg_key="$2"
	local _hash_var_name

	_hash_var_name "${hg_var}" "${hg_key}"
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
	stack_push "${_hash_var_name}" "${hpf_value}"
}

hash_push_back() {
	local -; set +x
	[ $# -eq 3 ] || eargs hash_push_back var key value
	local hp_var="$1"
	local hp_key="$2"
	local hp_value="$3"
	local _hash_var_name

	_hash_var_name "${hp_var}" "${hp_key}"
	stack_push_back "${_hash_var_name}" "${hp_value}"
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
	stack_pop "${_hash_var_name}" "${hpf_var_return}"
}

hash_pop_back() {
	local -; set +x
	[ $# -eq 3 ] || eargs hash_pop_back var key var_return
	local hp_var="$1"
	local hp_key="$2"
	local hp_var_return="$3"
	local _hash_var_name

	_hash_var_name "${hp_var}" "${hp_key}"
	stack_pop_back "${_hash_var_name}" "${hp_var_return}"
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
	stack_foreach "${_hash_var_name}" "${hff_var_return}" "${hff_tmp_var}"
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
	    "${hfb_tmp_var}"
}

hash_set() {
	local -; set +x -u
	[ $# -eq 3 ] || eargs hash_set var key value
	local hash_set_var="$1"
	local hash_set_key="$2"
	local hash_set_val="$3"
	local _hash_var_name

	_hash_var_name "${hash_set_var}" "${hash_set_key}"
	case "$-" in
	*C*)
		# noclobber is set.
		# - Only set the value if it was not already set.
		# - Return error if already set.
		if isset "${_hash_var_name}"; then
			return 1
		fi
	esac
	setvar "${_hash_var_name}" "${hash_set_val}"
}

# Similar to hash_unset but returns the value or error if not set.
hash_remove() {
	local -; set +x -u
	[ "$#" -eq 3 ] || [ "$#" -eq 2 ] ||
	    eargs hash_remove var key '[var_return]'
	local hr_var="$1"
	local hr_key="$2"
	local hr_var_return="${3-}"
	local _hash_var_name hr_val hr_ret

	_hash_var_name "${hr_var}" "${hr_key}"
	hr_ret=0
	getvar "${_hash_var_name}" hr_val || hr_ret="$?"
	unset "${_hash_var_name}"
	case "${hr_ret}" in
	0) ;;
	*)
		return "${hr_ret}"
		;;
	esac
	case "${hr_var_return}" in
	"") ;;
	*) setvar "${hr_var_return}" "${hr_val}" || return ;;
	esac
	return "${hr_ret}"
}

hash_unset() {
	local -; set +x
	[ $# -eq 2 ] || eargs hash_unset var key
	local hu_var="$1"
	local hu_key="$2"
	local _hash_var_name

	_hash_var_name "${hu_var}" "${hu_key}"
	unset "${_hash_var_name}"
}

hash_unset_var() {
	local -; set +x
	[ $# -eq 1 ] || eargs hash_unset_var var
	local huv_var="$1"
	local huv_key huv_line _hash_var_name

	_hash_var_name "${huv_var}" ""
	while IFS= mapfile_read_loop_redir huv_line; do
		case "${huv_line}" in
		"${_hash_var_name}"*=*) ;;
		*) continue ;;
		esac
		huv_key="${huv_line%%=*}"
		unset "${huv_key}"
	done <<-EOF
	$(set)
	EOF
}

list_contains() {
	local -; set +x
	[ $# -eq 2 ] || eargs list_contains var item
	local lc_var="$1"
	local lc_item="$2"
	local lc_val

	getvar "${lc_var}" lc_val || lc_val=
	case " ${lc_val} " in *" ${lc_item} "*) ;; *) return 1 ;; esac
	return 0
}

list_add() {
	local -; set +x
	[ $# -eq 2 ] || eargs list_add var item
	local la_var="$1"
	local la_item="$2"
	local la_value

	getvar "${la_var}" la_value || la_value=
	case " ${la_value} " in *" ${la_item} "*) return 0 ;; esac
	setvar "${la_var}" "${la_value:+${la_value} }${la_item}"
}

list_remove() {
	local -; set +x
	[ $# -eq 2 ] || eargs list_remove var item
	local lr_var="$1"
	local lr_item="$2"
	local lr_val lr_newval

	getvar "${lr_var}" lr_val || lr_val=
	lr_val=" ${lr_val} "
	case "${lr_val}" in *" ${lr_item} "*) ;; *) return 1 ;; esac
	lr_newval="${lr_val% "${lr_item}" *} ${lr_val##* "${lr_item}" }"
	lr_newval="${lr_newval# }"
	lr_newval="${lr_newval% }"
	setvar "${lr_var}" "${lr_newval}"
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
	setvar "${spf_var}" \
	    "${spf_item}${spf_value:+${STACK_SEP}${spf_value}}" || return
	incrvar "${spf_var}_count"
}

stack_push_back() {
	local -; set +x
	[ $# -eq 2 ] || eargs stack_push_back var item
	local spb_var="$1"
	local spb_item="$2"
	local spb_value

	getvar "${spb_var}" spb_value || spb_value=
	setvar "${spb_var}" \
	    "${spb_value:+${spb_value}${STACK_SEP}}${spb_item}" || return
	incrvar "${spb_var}_count"
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
		setvar "${spf_item_var_return}" "" || return
		unset "${spf_var}" "${spf_var}_count"
		return 1
		;;
	esac
	spf_item="${spf_value%%"${STACK_SEP}"*}"
	case "${spf_item}" in
	"${spf_value}" )
		# Last pop
		spf_value=""
		;;
	*)
		spf_value="${spf_value#*"${STACK_SEP}"}"
		;;
	esac
	setvar "${spf_var}" "${spf_value}" || return
	decrvar "${spf_var}_count" || return
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
		unset "${spb_var}" "${spb_var}_count"
		return 1
		;;
	esac
	spb_item="${spb_value##*"${STACK_SEP}"}"
	case "${spb_item}" in
	"${spb_value}" )
		# Last pop
		spb_value=""
		;;
	*)
		spb_value="${spb_value%"${STACK_SEP}"*}"
		;;
	esac
	setvar "${spb_var}" "${spb_value}" || return
	decrvar "${spb_var}_count" || return
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
	local sff_tmp_stack sff_tmp_stack_count

	if ! getvar "${sff_tmp_var}" sff_tmp_stack; then
		getvar "${sff_var}" sff_tmp_stack || return 1
	fi
	if ! getvar "${sff_tmp_var}_count" sff_tmp_stack_count; then
		getvar "${sff_var}_count" sff_tmp_stack_count || return 1
	fi
	if stack_pop sff_tmp_stack "${sff_item_var_return}"; then
		setvar "${sff_tmp_var}" "${sff_tmp_stack-}" || return
		setvar "${sff_tmp_var}_count" "${sff_tmp_stack_count-}" ||
		    return
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
	local sf_tmp_stack sf_tmp_stack_count

	if ! getvar "${sf_tmp_var}" sf_tmp_stack; then
		getvar "${sf_var}" sf_tmp_stack || return 1
	fi
	if ! getvar "${sf_tmp_var}_count" sf_tmp_stack_count; then
		getvar "${sf_var}_count" sf_tmp_stack_count || return 1
	fi
	if stack_pop_back sf_tmp_stack "${sf_item_var_return}"; then
		setvar "${sf_tmp_var}" "${sf_tmp_stack-}" || return
		setvar "${sf_tmp_var}_count" "${sf_tmp_stack_count-}" ||
		    return
		return 0
	else
		unset "${sf_tmp_var}"
		return 1
	fi
}

stack_isset() {
	local -; set +x
	[ "$#" -eq 1 ] || eargs stack_isset stack_var
	local si_var="$1"

	isset "${si_var}_count"
}

stack_size() {
	local -; set +x
	[ "$#" -eq 1 ] || eargs [ "$#" -eq 2 ] || eargs stack_size stack_var \
	    count_var_return
	local ss_var="$1"
	local ss_var_return="${2-}"
	local ss_count

	getvar "${ss_var}_count" ss_count || ss_count=0
	case "${ss_var_return}" in
	""|-) echo "${ss_count}" ;;
	*) setvar "${ss_var_return}" "${ss_count}" || return ;;
	esac
}

stack_unset() {
	[ "$#" -eq 1 ] || eargs stack_unset stack_var
	local su_stack_var="$1"

	unset "${su_stack_var}" "${su_stack_var}_count"
}

stack_set() {
	local -; set +x
	[ "$#" -eq 3 ] ||
	    eargs stack_set stack_var separator data
	local si_stack_var="$1"
	local si_separator="$2"
	local si_data="${3-}"
	local IFS -

	IFS="${si_separator:?}"
	set -o noglob
	# shellcheck disable=SC2086
	set -- ${si_data}
	set +o noglob
	unset IFS
	stack_set_args "${si_stack_var}" "$@"
}

stack_set_args() {
	local -; set +x
	[ "$#" -ge 2 ] ||
	    eargs stack_set_args stack_var data '[...]'
	local si_stack_var="$1"
	local si_output IFS

	shift 1
	IFS="${STACK_SEP}"
	si_output="$*"
	unset IFS
	setvar "${si_stack_var}_count" "$#" || return
	setvar "${si_stack_var}" "${si_output}"
}

stack_expand_front() {
	local -; set +x
	[ "$#" -eq 2 ] || [ "$#" -eq 3 ] ||
	    eargs stack_expand_front stack_var separator '[var_return_output]'
	local sef_stack_var="$1"
	local sef_separator="$2"
	local sef_var_return="${3-}"
	local sef_stack IFS -

	getvar "${sef_stack_var}" sef_stack || return
	IFS="${STACK_SEP}"
	set -o noglob
	# shellcheck disable=SC2086
	set -- ${sef_stack}
	set +o noglob
	case "${sef_separator}" in
	?)
		IFS="${sef_separator}"
		case "${sef_var_return}" in
		""|-) echo "$*" ;;
		*) setvar "${sef_var_return}" "$*" || return ;;
		esac
		unset IFS
		;;
	*)
		local sef_output

		unset IFS
		_gsub "${sef_stack}" "${STACK_SEP}" "${sef_separator}" \
		    sef_output || return
		case "${sef_var_return}" in
		""|-) echo "${sef_output}" ;;
		*) setvar "${sef_var_return}" "${sef_output}" || return ;;
		esac
		;;
	esac
}

stack_expand() {
	stack_expand_front "$@"
}

stack_expand_back() {
	local -; set +x
	[ "$#" -eq 2 ] || [ "$#" -eq 3 ] ||
	    eargs stack_expand_back stack_var separator '[var_return_output]'
	local seb_stack_var="$1"
	local seb_separator="$2"
	local seb_var_return="${3-}"
	local seb_stack seb_output
	local IFS seb_item

	getvar "${seb_stack_var}" seb_stack || return
	IFS="${STACK_SEP}"
	set -o noglob
	# shellcheck disable=SC2086
	set -- ${seb_stack}
	set +o noglob
	unset IFS
	seb_output=
	for seb_item in "$@"; do
		seb_output="${seb_item}${seb_output:+${seb_separator}${seb_output}}"
	done
	case "${seb_var_return}" in
	""|-) echo "${seb_output}" ;;
	*) setvar "${seb_var_return}" "${seb_output}" || return ;;
	esac
}

array_isset() {
	local -; set +x
	[ "$#" -eq 1 ] || [ "$#" -eq 2 ] ||
	    eargs array_isset array_var '[idx]'
	local as_array_var="$1"
	local as_idx="${2-}"

	case "${as_idx:+set}" in
	set)
		hash_isset "_array_${as_array_var}" "${as_idx}" || return
		;;
	*)
		isset "_array_length_${as_array_var}" || return
		;;
	esac
}

array_size() {
	local -; set +x
	[ "$#" -eq 1 ] || [ "$#" -eq 2 ] ||
	    eargs array_size array_var '[var_return]'
	local as_array_var="$1"
	local as_var_return="${2-}"
	local as_count

	getvar "_array_length_${as_array_var}" as_count || as_count=0
	case "${as_var_return}" in
	""|-) echo "${as_count}" ;;
	*) setvar "${as_var_return}" "${as_count}" || return ;;
	esac
}

array_get() {
	local -; set +x
	[ "$#" -eq 2 ] || [ "$#" -eq 3 ] ||
	    eargs array_get array_var idx '[var_return]'
	local ag_array_var="$1"
	local ag_idx="$2"
	local ag_var_return="${3-}"

	hash_get "_array_${ag_array_var}" "${ag_idx}" "${ag_var_return}"
}

array_set() {
	local -; set +x
	[ "$#" -eq 3 ] || eargs array_set array_var idx value
	local as_array_var="$1"
	local as_idx="$2"
	shift 2

	if ! array_isset "${as_array_var}" "${as_idx}"; then
		incrvar "_array_length_${as_array_var}" || return
	fi
	hash_set "_array_${as_array_var}" "${as_idx}" "$*"
}

array_unset() {
	local -; set +x
	[ "$#" -eq 1 ] || [ "$#" -eq 2 ] ||
	    eargs array_unset array_var '[idx]'
	local au_array_var="$1"
	local au_idx="$2"

	case "${au_idx:+set}" in
	set)
		array_unset_idx "${au_array_var}" "${au_idx}" || return
		return
		;;
	esac

	hash_unset_var "_array_${au_array_var}"
	unset "_array_length_${au_array_var}"
}

array_unset_idx() {
	local -; set +x
	[ "$#" -eq 2 ] || eargs array_unset_idx array_var idx
	local aui_array_var="$1"
	local aui_idx="$2"
	local aui_count

	if ! array_isset "${aui_array_var}" "${aui_idx}"; then
		return 1
	fi
	decrvar "_array_length_${aui_array_var}" || return
	hash_unset "_array_${aui_array_var}" "${aui_idx}"
	if getvar "_array_length_${aui_array_var}" aui_count; then
		case "${aui_count}" in
		0)
			unset "_array_length_${aui_array_var}"
			;;
		esac
	fi
}

array_push() {
	array_push_back "$@"
}

array_push_back() {
	local -; set +x
	[ "$#" -eq 2 ] || eargs array_push_back array_var value
	local apb_array_var="$1"
	local apb_value="$2"
	local apb_size

	array_size "${apb_array_var}" apb_size || return 1
	array_set "${apb_array_var}" "${apb_size}" "${apb_value}"
}

array_pop() {
	array_pop_back "$@"
}

array_pop_back() {
	local -; set +x
	[ "$#" -eq 2 ] || eargs array_pop_back array_var item_var_return
	local apb_array_var="$1"
	local apb_item_var_return="$2"
	local apb_size

	array_size "${apb_array_var}" apb_size || return 1
	array_get "${apb_array_var}" "$((apb_size - 1))" \
	    "${apb_item_var_return}" || return
	array_unset "${apb_array_var}" "$((apb_size - 1))"
}

array_foreach_front() {
	local -; set +x
	[ "$#" -eq 3 ] || eargs array_foreach_front var item_var_return tmp_var
	local aff_var="$1"
	local aff_item_var_return="$2"
	local aff_tmp_var="$3"
	local aff_tmp_idx aff_size

	array_size "${aff_var}" aff_size || return 1
	if ! getvar "${aff_tmp_var}" aff_tmp_idx; then
		aff_tmp_idx=0
	fi
	while [ "${aff_tmp_idx}" -lt "${aff_size}" ]; do
		if array_get "${aff_var}" "${aff_tmp_idx}" \
		    "${aff_item_var_return}"; then
			setvar "${aff_tmp_var}" "$((aff_tmp_idx + 1))" ||
			    return
			return
		fi
		aff_tmp_idx="$((aff_tmp_idx + 1))"
	done
	unset "${aff_tmp_var}"
	return 1
}

array_foreach() {
	array_foreach_front "$@"
}
