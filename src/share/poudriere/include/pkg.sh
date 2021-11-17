# Copyright (c) 2010-2013 Baptiste Daroussin <bapt@FreeBSD.org>
# Copyright (c) 2012-2021 Bryan Drewery <bdrewery@FreeBSD.org>
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

pkg_get_originspec() {
	[ $# -eq 2 ] || eargs pkg_get_originspec var_return pkg
	local pgo_originspec_var="$1"
	local pkg="$2"
	local origin flavor subpkg

	pkg_get_origin origin "${pkg}" || return
	if have_ports_feature FLAVORS; then
		pkg_get_flavor flavor "${pkg}" || return
	else
		flavor=
	fi
	if have_ports_feature SUBPACKAGES; then
		pkg_get_subpkg subpkg "${pkg}" || return
	else
		subpkg=
	fi
	originspec_encode "${pgo_originspec_var}" "${origin}" "${flavor}" \
	    "${subpkg}"
}

pkg_get_origin() {
	[ $# -ge 2 ] || eargs pkg_get_origin var_return pkg [origin]
	local var_return="$1"
	local pkg="$2"
	local _origin="${3-}"
	local SHASH_VAR_PATH SHASH_VAR_PREFIX=

	get_pkg_cache_dir SHASH_VAR_PATH "${pkg}"
	case "${_origin}" in
	"")
		if ! shash_get 'pkg' 'origin' _origin; then
			_origin=$(injail "${PKG_BIN:?}" query -F \
			    "/packages/All/${pkg##*/}" "%o") || return
		fi
		;& # FALLTHROUGH
	*)
		shash_set 'pkg' 'origin' "${_origin}"
		;;
	esac
	case "${var_return}" in
	"") ;;
	-) echo "${_origin}" ;;
	*) setvar "${var_return}" "${_origin}" ;;
	esac
}

pkg_get_generic_list() {
	[ $# -eq 4 ] || eargs pkg_get_generic_list name flags mapfile_handle_var pkg
	local name="$1"
	local flags="$2"
	local _pggl_mapfile_var="$3"
	local _pkg="$4"
	local SHASH_VAR_PATH SHASH_VAR_PREFIX=

	get_pkg_cache_dir SHASH_VAR_PATH "${_pkg}"
	if ! shash_exists 'pkg' "${name}"; then
		local -; set_pipefail
		local ret

		ret=0
		injail "${PKG_BIN:?}" query -F "/packages/All/${_pkg##*/}" \
		    "${flags}" | sort |
		    shash_write 'pkg' "${name}" || ret="$?"
		if [ "${ret}" -ne 0 ]; then
			shash_unset 'pkg' "${name}"
			return "${ret}"
		fi
	fi
	case "${_pggl_mapfile_var}" in
	"") ;;
	-)
		shash_read 'pkg' "${name}"
		;;
	*)
		shash_read_mapfile 'pkg' "${name}" "${_pggl_mapfile_var}"
		;;
	esac ||
	    err "${EX_SOFTWARE}" "pkg_get_generic_list: Failed to read cache just written"
}

pkg_get_shlib_required_count() {
	[ $# -ge 2 ] || eargs pkg_get_shlib_required_count var_return pkg [count]
	local var_return="$1"
	local pkg="$2"
	local _count=$3
	local SHASH_VAR_PATH SHASH_VAR_PREFIX=

	get_pkg_cache_dir SHASH_VAR_PATH "${pkg}"
	case "${_count}" in
	"")
		if ! shash_get 'pkg' 'shlib_required_count' _count; then
			_count=$(injail "${PKG_BIN:?}" query -F \
			    "/packages/All/${pkg##*/}" "%#B") || return
		fi
		;& # FALLTHROUGH
	*)
		shash_set 'pkg' 'shlib_required_count' "${_count}"
		;;
	esac
	case "${var_return}" in
	"") ;;
	-) echo "${_count}" ;;
	*) setvar "${var_return}" "${_count}" ;;
	esac
}

pkg_get_shlib_requires() {
	[ $# -eq 2 ] || eargs pkg_get_shlib_requires mapfile_handle_var pkg

	pkg_get_generic_list 'shlib_requires' '%B' "$@"
}

pkg_get_shlib_provides() {
	[ $# -eq 2 ] || eargs pkg_get_shlib_provides mapfile_handle_var pkg

	pkg_get_generic_list 'shlib_provides' '%b' "$@"
}

pkg_get_annotations() {
	[ $# -eq 2 ] || eargs pkg_get_annotations mapfile_handle_var pkg

	pkg_get_generic_list 'annotations' '%At %Av' "$@"
}

pkg_get_annotation() {
	[ $# -eq 3 ] || eargs pkg_get_annotation var_return pkg key
	local pga_var_return="$1"
	local pkg="$2"
	local key="$3"
	local mapfile_handle fkey fvalue value

	pkg_get_annotations mapfile_handle "${pkg}" ||
	    err "${EX_SOFTWARE}" "pkg_get_annotation: Failed to lookup annotations for ${pkg}"
	value=
	while mapfile_read "${mapfile_handle}" fkey fvalue; do
		case "${fkey}" in
		"${key}")
			value="${fvalue}"
			break
			;;
		esac
	done
	mapfile_close "${mapfile_handle}" || :
	case "${pga_var_return}" in
	"") ;;
	-) echo "${value}" ;;
	*) setvar "${pga_var_return}" "${value}" ;;
	esac
}

pkg_get_flavor() {
	[ $# -eq 2 ] || eargs pkg_get_flavor var_return pkg
	local var_return="$1"
	local pkg="$2"

	pkg_get_annotation "${var_return}" "${pkg}" 'flavor'
}

pkg_get_subpkg() {
	[ $# -eq 2 ] || eargs pkg_get_subpkg var_return pkg
	local var_return="$1"
	local pkg="$2"

	pkg_get_annotation "${var_return}" "${pkg}" 'subpackage'
}
pkg_get_arch() {
	[ $# -ge 2 ] || eargs pkg_get_arch var_return pkg [arch]
	local var_return="$1"
	local pkg="$2"
	local _arch=$3
	local SHASH_VAR_PATH SHASH_VAR_PREFIX=

	get_pkg_cache_dir SHASH_VAR_PATH "${pkg}"
	case "${_arch}" in
	"")
		if ! shash_get 'pkg' 'arch' _arch; then
			_arch=$(injail "${PKG_BIN:?}" query -F \
			    "/packages/All/${pkg##*/}" "%q") || return
		fi
		;& # FALLTHROUGH
	*)
		shash_set 'pkg' 'arch' "${_arch}"
		;;
	esac
	case "${var_return}" in
	"") ;;
	-) echo "${_arch}" ;;
	*) setvar "${var_return}" "${_arch}" ;;
	esac
}

pkg_get_dep_origin_pkgnames() {
	local -; set -f
	[ $# -eq 3 ] || eargs pkg_get_dep_origin_pkgnames var_return_origins \
	    var_return_pkgnames pkg
	local var_return_origins="$1"
	local var_return_pkgnames="$2"
	local pkg="$3"
	local SHASH_VAR_PATH SHASH_VAR_PREFIX=
	local fetched_data compiled_dep_origins compiled_dep_pkgnames
	local origin pkgname

	compiled_dep_origins=
	compiled_dep_pkgnames=
	get_pkg_cache_dir SHASH_VAR_PATH "${pkg}"
	if ! shash_get 'pkg' 'deps' fetched_data; then
		fetched_data=$(set_pipefail; \
		    injail "${PKG_BIN:?}" query -F \
		    "/packages/All/${pkg##*/}" '%do %dn-%dv' |
		    tr '\n' ' ') || return
		shash_set 'pkg' 'deps' "${fetched_data}"
	fi
	case "${var_return_origins}${var_return_pkgnames}" in
	"") return 0 ;;
	esac
	# Split the data
	set -- ${fetched_data}
	while [ $# -ne 0 ]; do
		origin="$1"
		pkgname="$2"
		case "${var_return_origins:+set}" in
		set)
			compiled_dep_origins="${compiled_dep_origins:+${compiled_dep_origins} }${origin}"
			;;
		esac
		case "${var_return_pkgnames:+set}" in
		set)
			compiled_dep_pkgnames="${compiled_dep_pkgnames:+${compiled_dep_pkgnames} }${pkgname}"
			;;
		esac
		shift 2
	done
	case "${var_return_origins}" in
	"") ;;
	-) echo "${compiled_dep_origins-}" ;;
	*) setvar "${var_return_origins}" "${compiled_dep_origins-}" ;;
	esac
	case "${var_return_pkgnames}" in
	"") ;;
	-) echo "${compiled_dep_pkgnames-}" ;;
	*) setvar "${var_return_pkgnames}" "${compiled_dep_pkgnames-}" ;;
	esac
}

pkg_get_options() {
	[ $# -eq 2 ] || eargs pkg_get_options var_return pkg
	local var_return="$1"
	local pkg="$2"
	local SHASH_VAR_PATH SHASH_VAR_PREFIX=
	local _compiled_options

	_compiled_options=
	get_pkg_cache_dir SHASH_VAR_PATH "${pkg}"
	if ! shash_get 'pkg' 'options2' _compiled_options; then
		_compiled_options=
		while mapfile_read_loop_redir key value; do
			case "${key}" in
			"!ERR! "*) return "${key#!ERR! }" ;;
			esac
			case "${value}" in
				off|false) key="-${key}" ;;
				on|true) key="+${key}" ;;
			esac
			_compiled_options="${_compiled_options:+${_compiled_options} }${key}"
		done <<-EOF
		$(set_pipefail; \
		    injail "${PKG_BIN:?}" \
		    query -F "/packages/All/${pkg##*/}" '%Ok %Ov' | sort ||
		    echo "!ERR! $?")
		EOF
		shash_set 'pkg' 'options2' "${_compiled_options-}"
	fi
	case "${var_return}" in
	"") ;;
	-) echo "${_compiled_options-}" ;;
	*) setvar "${var_return}" "${_compiled_options-}" ;;
	esac
}

pkg_cache_data() {
	[ $# -eq 3 ] || eargs pkg_cache_data pkg origin flavor
	local pkg="$1"
	local origin="$2"
	local flavor="$3"
	local _ignored

	ensure_pkg_installed || return 0
	{
		pkg_get_options '' "${pkg}"
		pkg_get_origin '' "${pkg}" "${origin}"
		pkg_get_arch '' "${pkg}"
		pkg_get_annotations '' "${pkg}"
		pkg_get_dep_origin_pkgnames '' '' "${pkg}"
		pkg_get_shlib_required_count '' "${pkg}"
		pkg_get_shlib_requires '' "${pkg}"
		pkg_get_shlib_provides '' "${pkg}"
	} >/dev/null
}

pkg_cacher_queue() {
	[ $# -eq 3 ] || eargs pkg_cacher_queue origin pkgname flavor
	local encoded_data

	encode_args encoded_data "$@"

	echo "${encoded_data}" > ${MASTER_DATADIR:?}/pkg_cacher.pipe
}

pkg_cacher_main() {
	local pkg work pkgname origin flavor
	local IFS -

	set +e +u

	setup_traps pkg_cacher_cleanup

	mkfifo ${MASTER_DATADIR:?}/pkg_cacher.pipe
	exec 6<> ${MASTER_DATADIR:?}/pkg_cacher.pipe

	# Wait for packages to process.
	while :; do
		IFS= read -r work <&6
		decode_args_vars "${work}" \
			origin pkgname flavor
		pkg="${PACKAGES}/All/${pkgname}.${PKG_EXT}"
		if [ -f "${pkg}" ]; then
			pkg_cache_data "${pkg}" "${origin}" "${flavor}"
		fi
	done
}

pkg_cacher_cleanup() {
	local IFS; unset IFS;

	unlink ${MASTER_DATADIR:?}/pkg_cacher.pipe
}

get_cache_dir() {
	setvar "${1}" "${POUDRIERE_DATA:?}/cache/${MASTERNAME:?}"
}

# Return the cache dir for the given pkg
# @param var_return The variable to set the result in
# @param string pkg $PKGDIR/All/PKGNAME.PKG_EXT
get_pkg_cache_dir() {
	[ $# -ge 2 ] || eargs get_pkg_cache_dir var_return pkg [use_mtime]
	local var_return="$1"
	local pkg="$2"
	local use_mtime="${3:-1}"
	local pkg_file="${pkg##*/}"
	local pkg_dir
	local cache_dir
	local pkg_mtime=

	get_cache_dir cache_dir

	if [ ! -e "${pkg}" ] && [ ! -L "${pkg}" ]; then
		err "${EX_SOFTWARE}" "get_pkg_cache_dir: ${pkg} does not exist"
	fi

	if [ "${use_mtime}" -eq 1 ]; then
		pkg_mtime=$(stat -f %m "${pkg}")
	fi

	pkg_dir="${cache_dir:?}/${pkg_file:?}/${pkg_mtime}"

	if [ "${use_mtime}" -eq 1 ]; then
		[ -d "${pkg_dir}" ] || mkdir -p "${pkg_dir}"
	fi

	setvar "${var_return}" "${pkg_dir}"
}

clear_pkg_cache() {
	[ $# -eq 1 ] || eargs clear_pkg_cache pkg
	local pkg="$1"
	local pkg_cache_dir

	get_pkg_cache_dir pkg_cache_dir "${pkg}" 0

	rm -rf "${pkg_cache_dir}"
	# XXX: Need shash_unset with glob
}

# Deleted cached information for stale packages (manually removed)
delete_stale_pkg_cache() {
	local pkgname
	local cache_dir

	get_cache_dir cache_dir

	msg_verbose "Checking for stale cache files"

	[ -d "${cache_dir}" ] || return 0
	! dirempty "${cache_dir}" || return 0
	for pkg in ${cache_dir}/*; do
		pkg_file="${pkg##*/}"
		# If this package no longer exists in the PKGDIR, delete the cache.
		if [ ! -e "${PACKAGES}/All/${pkg_file}" ]; then
			clear_pkg_cache "${pkg}"
		fi
	done

	return 0
}

# If the user ran pkg-repo in the wrong directory we need to undo that.
delete_bad_pkg_repo_files() {
	local ext file

	for ext in "${PKG_EXT:?}" "txz"; do
		for file in \
		    meta \
		    digests \
		    filesite \
		    packagesite; do
			pkg="${PACKAGES:?}/All/${file}.${ext}"
			if [ ! -f "${pkg}" ]; then
				continue
			fi
			msg "Removing invalid pkg repo file: ${pkg}"
			unlink "${pkg}"
		done
	done
}

delete_all_pkgs() {
	[ $# -eq 1 ] || eargs delete_all_pkgs reason
	local reason="$1"
	local cache_dir

	get_cache_dir cache_dir
	msg_n "${reason}, cleaning all packages..."
	rm -rf ${PACKAGES:?}/* ${cache_dir}
	echo " done"
}

delete_pkg() {
	[ $# -eq 1 ] || eargs delete_pkg pkg
	local pkg="$1"

	clear_pkg_cache "${pkg}"
	# Delete the package and the depsfile since this package is being deleted,
	# which will force it to be recreated
	unlink "${pkg}"
}

# Keep in sync with delete_pkg
delete_pkg_xargs() {
	[ $# -eq 2 ] || eargs delete_pkg listfile pkg
	local listfile="$1"
	local pkg="$2"
	local pkg_cache_dir

	get_pkg_cache_dir pkg_cache_dir "${pkg}" 0

	# Delete the package and the depsfile since this package is being deleted,
	# which will force it to be recreated
	{
		echo "${pkg}"
		echo "${pkg_cache_dir}"
	} >> "${listfile}"
	# XXX: May need clear_pkg_cache here if shash changes from file.
}

_pkg_version_expanded() {
	local -; set -f
	[ $# -eq 1 ] || eargs pkg_ver_expanded version
	local ver="$1"
	local epoch revision ver_sub IFS

	case "${ver}" in
	*,*)
		epoch="${ver##*,}"
		ver="${ver%,*}"
		;;
	*)
		epoch="0"
		;;
	esac
	case "${ver}" in
	*_*)
		revision="${ver##*_}"
		ver="${ver%_*}"
		;;
	*)
		revision="0"
		;;
	esac
	_gsub "${ver}" "[_.]" " " ver_sub
	set -- ${ver_sub}

	printf "%02d" "${epoch}"
	while [ $# -gt 0 ]; do
		printf "%02d" "$1"
		shift
	done
	printf "%04d" "${revision}"
	printf "\n"
}

pkg_version() {
	if [ $# -ne 3 ] || [ "$1" != "-t" ]; then
		eargs pkg_version -t version1 version2
	fi
	shift
	local ver1="$1"
	local ver2="$2"
	local ver1_expanded ver2_expanded

	ver1_expanded="$(_pkg_version_expanded "${ver1}")"
	ver2_expanded="$(_pkg_version_expanded "${ver2}")"
	if [ "${ver1_expanded}" -gt "${ver2_expanded}" ]; then
		echo ">"
	elif [ "${ver1_expanded}" -eq "${ver2_expanded}" ]; then
		echo "="
	else
		echo "<"
	fi
}

pkg_note_add() {
	[ $# -eq 3 ] || eargs pkg_note_add pkgname key value
	local pkgname="$1"
	local key="$2"
	local value="$3"
	local notes

	hash_set "pkgname-notes-${key}" "${pkgname}"  "${value}"
	hash_get pkgname-notes "${pkgname}" notes || notes=
	notes="${notes:+${notes} }${key}"
	hash_set pkgname-notes "${pkgname}" "${notes}"
}

pkg_notes_get() {
	[ $# -eq 3 ] || eargs pkg_notes_get pkgname PKGENV PKGENV_var
	local pkgname="$1"
	local _pkgenv="$2"
	local _pkgenv_var="$3"
	local notes key value

	hash_remove pkgname-notes "${pkgname}" notes || return 0
	_pkgenv="${_pkgenv:+${_pkgenv} }'PKG_NOTES=${notes}'"
	for key in ${notes}; do
		hash_remove "pkgname-notes-${key}" "${pkgname}" value || value=
		_pkgenv="${_pkgenv} 'PKG_NOTE_${key}=${value}'"
	done
	setvar "${_pkgenv_var}" "${_pkgenv}"
}

sign_pkg() {
	[ $# -eq 2 ] || eargs sign_pkg sigtype pkgfile
	local sigtype="$1"
	local pkgfile="$2"

	msg "Signing pkg bootstrap with method: ${sigtype}"
	case "${sigtype}" in
	"fingerprint")
		unlink "${pkgfile}.sig"
		sha256 -q "${pkgfile}" | ${SIGNING_COMMAND} > "${pkgfile}.sig"
		;;
	"pubkey")
		unlink "${pkgfile}.pubkeysig"
		echo -n $(sha256 -q "${pkgfile}") | \
		    openssl dgst -sha256 -sign "${PKG_REPO_SIGNING_KEY}" \
		    -binary -out "${pkgfile}.pubkeysig"
		;;
	esac
}
