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

pkg_get_origin() {
	[ $# -lt 2 ] && eargs pkg_get_origin var_return pkg [origin]
	local var_return="$1"
	local pkg="$2"
	local _origin=$3
	local SHASH_VAR_PATH SHASH_VAR_PREFIX=

	get_pkg_cache_dir SHASH_VAR_PATH "${pkg}"
	if ! shash_get 'pkg' 'origin' _origin ||
	    [ -z "${_origin}" ]; then
		if [ -z "${_origin}" ]; then
			_origin=$(injail ${PKG_BIN} query -F \
			    "/packages/All/${pkg##*/}" "%o")
		fi
		shash_set 'pkg' 'origin' "${_origin}"
	fi
	if [ -n "${var_return}" ]; then
		setvar "${var_return}" "${_origin}"
	fi
	if [ -z "${_origin}" ]; then
		return 1
	fi
}

pkg_get_annotations() {
	[ $# -eq 2 ] || eargs pkg_get_annotations mapfile_handle_var pkg
	local mapfile_handle_var="$1"
	local pkg="$2"
	local SHASH_VAR_PATH SHASH_VAR_PREFIX=

	get_pkg_cache_dir SHASH_VAR_PATH "${pkg}"
	if ! shash_exists 'pkg' 'annotations'; then
		injail ${PKG_BIN} query -F "/packages/All/${pkg##*/}" \
		    '%At %Av' | sort |
		    shash_write 'pkg' 'annotations'
	fi
	if [ -n "${mapfile_handle_var}" ]; then
		shash_read_mapfile 'pkg' 'annotations' "${mapfile_handle_var}"
	fi
}

pkg_get_annotation() {
	[ $# -eq 3 ] || eargs pkg_get_annotation var_return pkg key
	local pga_var_return="$1"
	local pkg="$2"
	local key="$3"
	local mapfile_handle fkey fvalue value

	pkg_get_annotations mapfile_handle "${pkg}"
	while mapfile_read "${mapfile_handle}" fkey fvalue; do
		case "${fkey}" in
		${key})
			value="${fvalue}"
			break
			;;
		esac
	done
	mapfile_close "${mapfile_handle}" || :
	if [ -n "${pga_var_return}" ]; then
		setvar "${pga_var_return}" "${value}"
	fi
}

pkg_get_flavor() {
	[ $# -eq 2 ] || eargs pkg_get_flavor var_return pkg
	local var_return="$1"
	local pkg="$2"

	pkg_get_annotation "${var_return}" "${pkg}" 'flavor'
}

pkg_get_dep_args() {
	[ $# -eq 2 ] || eargs pkg_get_dep_args var_return pkg
	local var_return="$1"
	local pkg="$2"

	pkg_get_annotation "${var_return}" "${pkg}" 'dep_args'
}

pkg_get_arch() {
	[ $# -lt 2 ] && eargs pkg_get_arch var_return pkg [arch]
	local var_return="$1"
	local pkg="$2"
	local _arch=$3
	local SHASH_VAR_PATH SHASH_VAR_PREFIX=

	get_pkg_cache_dir SHASH_VAR_PATH "${pkg}"
	if ! shash_get 'pkg' 'arch' _arch ||
	    [ -z "${_arch}" ]; then
		if [ -z "${_arch}" ]; then
			_arch=$(injail ${PKG_BIN} query -F \
			    "/packages/All/${pkg##*/}" "%q")
		fi
		shash_set 'pkg' 'arch' "${_arch}"
	fi
	if [ -n "${var_return}" ]; then
		setvar "${var_return}" "${_arch}"
	fi
	if [ -z "${_arch}" ]; then
		return 1
	fi
}

pkg_get_dep_origin_pkgnames() {
	local -; set -f
	[ $# -ne 3 ] && eargs pkg_get_dep_origin_pkgnames var_return_origins \
	    var_return_pkgnames pkg
	local var_return_origins="$1"
	local var_return_pkgnames="$2"
	local pkg="$3"
	local SHASH_VAR_PATH SHASH_VAR_PREFIX=
	local fetched_data compiled_dep_origins compiled_dep_pkgnames
	local origin pkgname

	get_pkg_cache_dir SHASH_VAR_PATH "${pkg}"
	if ! shash_get 'pkg' 'deps' fetched_data; then
		fetched_data=$(injail ${PKG_BIN} query -F \
			"/packages/All/${pkg##*/}" '%do %dn-%dv' | tr '\n' ' ')
		shash_set 'pkg' 'deps' "${fetched_data}"
	fi
	[ -n "${var_return_origins}" -o -n "${var_return_pkgnames}" ] || \
	    return 0
	# Split the data
	set -- ${fetched_data}
	while [ $# -ne 0 ]; do
		origin="$1"
		pkgname="$2"
		compiled_dep_origins="${compiled_dep_origins}${compiled_dep_origins:+ }${origin}"
		compiled_dep_pkgnames="${compiled_dep_pkgnames}${compiled_dep_pkgnames:+ }${pkgname}"
		shift 2
	done
	if [ -n "${var_return_origins}" ]; then
		setvar "${var_return_origins}" "${compiled_dep_origins}"
	fi
	if [ -n "${var_return_pkgnames}" ]; then
		setvar "${var_return_pkgnames}" "${compiled_dep_pkgnames}"
	fi
}

pkg_get_options() {
	[ $# -ne 2 ] && eargs pkg_get_options var_return pkg
	local var_return="$1"
	local pkg="$2"
	local SHASH_VAR_PATH SHASH_VAR_PREFIX=
	local _compiled_options

	get_pkg_cache_dir SHASH_VAR_PATH "${pkg}"
	if ! shash_get 'pkg' 'options2' _compiled_options; then
		_compiled_options=
		while mapfile_read_loop_redir key value; do
			case "${value}" in
				off|false) key="-${key}" ;;
				on|true) key="+${key}" ;;
			esac
			_compiled_options="${_compiled_options}${_compiled_options:+ }${key}"
		done <<-EOF
		$(injail ${PKG_BIN} query -F "/packages/All/${pkg##*/}" '%Ok %Ov' | sort)
		EOF
		shash_set 'pkg' 'options2' "${_compiled_options}"
	fi
	if [ -n "${var_return}" ]; then
		setvar "${var_return}" "${_compiled_options}"
	fi
}

pkg_cache_data() {
	[ $# -eq 4 ] || eargs pkg_cache_data pkg origin dep_args flavor
	local pkg="$1"
	local origin="$2"
	local dep_args="$3"
	local flavor="$4"
	local _ignored

	ensure_pkg_installed || return 1
	{
		pkg_get_options '' "${pkg}"
		pkg_get_origin '' "${pkg}" "${origin}" || :
		pkg_get_arch '' "${pkg}" || :
		pkg_get_annotations '' "${pkg}"
		pkg_get_dep_origin_pkgnames '' '' "${pkg}"
	} >/dev/null
}

pkg_cacher_queue() {
	[ $# -eq 4 ] || eargs pkg_cacher_queue origin pkgname dep_args flavor
	local encoded_data

	encode_args encoded_data "$@"

	echo "${encoded_data}" > ${MASTER_DATADIR}/pkg_cacher.pipe
}

pkg_cacher_main() {
	local pkg work pkgname origin dep_args flavor
	local IFS

	mkfifo ${MASTER_DATADIR}/pkg_cacher.pipe
	exec 6<> ${MASTER_DATADIR}/pkg_cacher.pipe

	trap exit TERM
	trap pkg_cacher_cleanup EXIT

	# Wait for packages to process.
	while :; do
		IFS= read -r work <&6
		decode_args_vars "${work}" \
			origin pkgname dep_args flavor
		pkg="${PACKAGES}/All/${pkgname}.${PKG_EXT}"
		if [ -f "${pkg}" ]; then
			pkg_cache_data "${pkg}" "${origin}" "${dep_args}" \
			    "${flavor}"
		fi
	done
}

pkg_cacher_cleanup() {
	local IFS; unset IFS;

	unlink ${MASTER_DATADIR}/pkg_cacher.pipe
}

get_cache_dir() {
	setvar "${1}" ${POUDRIERE_DATA}/cache/${MASTERNAME}
}

# Return the cache dir for the given pkg
# @param var_return The variable to set the result in
# @param string pkg $PKGDIR/All/PKGNAME.PKG_EXT
get_pkg_cache_dir() {
	[ $# -lt 2 ] && eargs get_pkg_cache_dir var_return pkg
	local var_return="$1"
	local pkg="$2"
	local use_mtime="${3:-1}"
	local pkg_file="${pkg##*/}"
	local pkg_dir
	local cache_dir
	local pkg_mtime=

	get_cache_dir cache_dir

	[ ${use_mtime} -eq 1 ] && pkg_mtime=$(stat -f %m "${pkg}")

	pkg_dir="${cache_dir}/${pkg_file}/${pkg_mtime}"

	if [ ${use_mtime} -eq 1 ]; then
		[ -d "${pkg_dir}" ] || mkdir -p "${pkg_dir}"
	fi

	setvar "${var_return}" "${pkg_dir}"
}

clear_pkg_cache() {
	[ $# -ne 1 ] && eargs clear_pkg_cache pkg
	local pkg="$1"
	local pkg_cache_dir

	get_pkg_cache_dir pkg_cache_dir "${pkg}" 0

	rm -fr "${pkg_cache_dir}"
	# XXX: Need shash_unset with glob
}

# Deleted cached information for stale packages (manually removed)
delete_stale_pkg_cache() {
	local pkgname
	local cache_dir

	get_cache_dir cache_dir

	msg_verbose "Checking for stale cache files"

	[ ! -d ${cache_dir} ] && return 0
	dirempty ${cache_dir} && return 0
	for pkg in ${cache_dir}/*; do
		pkg_file="${pkg##*/}"
		# If this package no longer exists in the PKGDIR, delete the cache.
		[ ! -e "${PACKAGES}/All/${pkg_file}" ] &&
			clear_pkg_cache "${pkg}"
	done

	return 0
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
	[ $# -ne 1 ] && eargs delete_pkg pkg
	local pkg="$1"

	# Delete the package and the depsfile since this package is being deleted,
	# which will force it to be recreated
	unlink "${pkg}"
	clear_pkg_cache "${pkg}"
}

# Keep in sync with delete_pkg
delete_pkg_xargs() {
	[ $# -ne 2 ] && eargs delete_pkg listfile pkg
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
