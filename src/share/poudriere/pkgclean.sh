#!/bin/sh
# 
# Copyright (c) 2013 Bryan Drewery <bdrewery@FreeBSD.org>
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

. ${SCRIPTPREFIX}/common.sh

usage() {
	cat <<EOF
poudriere pkgclean [options] [-f file|cat/port ...]

Parameters:
    -A          -- Remove all packages
    -a          -- Keep all known ports
    -f file     -- Get the list of ports to keep from a file
    [ports...]  -- List of ports to keep on the command line

Options:
    -C          -- Delete packages listed on command line rather than keep
    -j jail     -- Which jail to use for packages
    -J n        -- Run n jobs in parallel (Defaults to the number of
                   CPUs times 1.25)
    -n          -- Do not actually remove anything, just show what would be
                   removed
    -N          -- Do not build the package repository when clean completed
    -O overlays -- Specify extra ports trees to overlay
    -p tree     -- Which ports tree to use for packages
    -r          -- With -C delete reverse dependencies too
    -R          -- Clean RESTRICTED packages after building
    -u          -- Force rebuilding and signing the repo
    -v          -- Be verbose; show more information. Use twice to enable
                   debug output
    -y          -- Assume yes when deleting and do not confirm
    -z set      -- Specify which SET to use for packages
EOF
	exit ${EX_USAGE}
}

PTNAME=default
SETNAME=""
DRY_RUN=0
DO_ALL=0
BUILD_REPO=1
FORCE_BUILD_REPO=0
OVERLAYS=""
CLEAN_LISTED=0
CLEAN_RDEPS=0

[ $# -eq 0 ] && usage

while getopts "AaCj:J:f:nNO:p:rRuvyz:" FLAG; do
	case "${FLAG}" in
		A)
			DO_ALL=1
			;;
		a)
			ALL=1
			;;
		C)
			CLEAN_LISTED=1
			;;
		j)
			jail_exists ${OPTARG} || err 1 "No such jail: ${OPTARG}"
			JAILNAME=${OPTARG}
			;;
		J)
			PREPARE_PARALLEL_JOBS=${OPTARG#*:}
			;;
		f)
			# If this is a relative path, add in ${PWD} as
			# a cd / was done.
			[ "${OPTARG#/}" = "${OPTARG}" ] && \
			    OPTARG="${SAVED_PWD}/${OPTARG}"
			LISTPKGS="${LISTPKGS:+${LISTPKGS} }${OPTARG}"
			;;
		n)
			DRY_RUN=1
			;;
		N)
			BUILD_REPO=0
			;;
		O)
			porttree_exists ${OPTARG} ||
			    err 2 "No such overlay ${OPTARG}"
			OVERLAYS="${OVERLAYS} ${OPTARG}"
			;;
		p)
			porttree_exists ${OPTARG} ||
			    err 2 "No such ports tree: ${OPTARG}"
			PTNAME=${OPTARG}
			;;
		r)
			CLEAN_RDEPS=1
			;;
		R)
			NO_RESTRICTED=1
			;;
		u)
			FORCE_BUILD_REPO=1
			;;
		v)
			VERBOSE=$((VERBOSE + 1))
			;;
		y)
			answer=yes
			;;
		z)
			[ -n "${OPTARG}" ] || err 1 "Empty set name"
			SETNAME="${OPTARG}"
			;;
		*)
			usage
			;;
	esac
done

encode_args saved_argv "$@"
shift $((OPTIND-1))
post_getopts

[ -z "${JAILNAME}" ] && \
    err 1 "Don't know on which jail to run please specify -j"

if [ "${CLEAN_LISTED}" -eq 1 -a -n "${LISTPKGS}" ]; then
	err ${EX_USAGE} "-C and -f should not be used together"
fi
if [ "${CLEAN_LISTED}" -eq 0 -a "${CLEAN_RDEPS}" -eq 1 ]; then
	err ${EX_USAGE} "-r only works with -C"
fi

MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
_mastermnt MASTERMNT

export MASTERNAME
export MASTERMNT

: ${PREPARE_PARALLEL_JOBS:=$(echo "scale=0; ${PARALLEL_JOBS} * 1.25 / 1" | bc)}
PARALLEL_JOBS=${PREPARE_PARALLEL_JOBS}

if [ ${DO_ALL} -eq 1 ]; then
	LISTPORTS=
else
	read_packages_from_params "$@"
fi

PACKAGES="${POUDRIERE_DATA:?}/packages/${MASTERNAME:?}"
case "${ATOMIC_PACKAGE_REPOSITORY}" in
yes)
	if [ -d "${PACKAGES:?}/.building" ]; then
		msg "Cleaning in previously failed build directory"
		PACKAGES="${PACKAGES:?}/.building"
	else
		PACKAGES="${PACKAGES:?}/.latest"
	fi
	;;
esac

PKG_EXT='*' package_dir_exists_and_has_packages ||
    err 0 "No packages exist for ${MASTERNAME}"

maybe_run_queued "${saved_argv}"

msg "Gathering all expected packages"
if [ "${CLEAN_LISTED}" -eq 0 ]; then
	msg_warn "Will delete anything not listed. To delete listed use -C."
else
	msg_warn "Will delete anything listed. To keep listed do not use -C."
fi
jail_start "${JAILNAME}" "${PTNAME}" "${SETNAME}"
prepare_ports
if ! ensure_pkg_installed; then
	err 1 "pkg must be built before this command can be used"
fi
msg "Looking for unneeded packages"
bset status "pkgclean:"

# Some packages may exist that are stale, but are still the latest version
# built. Don't delete those, bulk will incrementally delete them. We only
# want to delete packages that are duplicated and old, non-packages, and
# packages that are not in the cmdline-specified port list or in their
# dependencies and finally packages in the wrong format.

CLEANUP_HOOK=pkgclean_cleanup
pkgclean_cleanup() {
	rm -f "${BADFILES_LIST:?}" "${FOUND_ORIGINS:?}" 2>/dev/null
}
BADFILES_LIST="$(mktemp -t poudriere_pkgclean)"
FOUND_ORIGINS="$(mktemp -t poudriere_pkgclean)"

should_delete() {
	[ $# -eq 1 ] || eargs should_delete pkgfile
	local pkgfile="$1"
	local pkgname originspec ret

	pkgname="${pkgfile##*/}"
	pkgname="${pkgname%.*}"
	ret=0

	originspec=
	if ! pkg_get_originspec originspec "${pkgfile}"; then
		msg_verbose "Found corrupt package: ${pkgfile}"
		return 0 # delete
	fi

	if [ "${CLEAN_LISTED}" -eq 0 ]; then
		should_delete_unlisted "${pkgfile}" "${originspec}" \
		    "${pkgname}" ||
		    ret="$?"
	elif [ "${CLEAN_LISTED}" -eq 1 ]; then
		should_delete_listed "${pkgfile}" "${originspec}" \
		    "${pkgname}" ||
		    ret="$?"
	fi
	echo "${pkgfile} ${originspec}" >> "${FOUND_ORIGINS:?}"
	return "${ret}"
}

# Handle NO -C
should_delete_unlisted() {
	[ $# -eq 3 ] || eargs should_delete_unlisted pkgfile originspec pkgname
	local pkgfile="$1"
	local originspec="$2"
	local pkgname="$3"
	local forbidden

	if shash_remove pkgname-forbidden "${pkgname}" forbidden; then
		msg_verbose "Found forbidden package (${COLOR_PORT}${originspec}${COLOR_RESET}) (${forbidden}): ${pkgfile}"
		return 0 # delete
	elif ! pkgbase_is_needed "${pkgname}"; then
		msg_verbose "Found unwanted package (${COLOR_PORT}${originspec}${COLOR_RESET}): ${pkgfile}"
		return 0 # delete
	fi
	return 1 # keep
}

# Handle -C and -r
should_delete_listed() {
	[ $# -eq 3 ] || eargs should_delete_listed pkgfile originspec pkgname
	local pkgfile="$1"
	local originspec="$2"
	local pkgname="$3"
	local dep_origin compiled_deps

	compiled_deps=
	if originspec_is_listed "${originspec}"; then
		msg_verbose "Found specified package (${COLOR_PORT}${originspec}${COLOR_RESET}): ${pkgfile}"
		return 0 # delete
	elif ! pkg_get_dep_origin_pkgnames compiled_deps '' "${pkgfile}"; then
		msg_verbose "Found corrupt package (${COLOR_PORT}${originspec}${COLOR_RESET}) (deps): ${pkgfile}"
		return 0 # delete
	fi
	if [ "${CLEAN_RDEPS}" -eq 1 ]; then
		for dep_origin in ${compiled_deps}; do
			if originspec_is_listed "${dep_origin}"; then
				msg_verbose "Found specified package (${COLOR_PORT}${dep_origin}${COLOR_RESET}) rdep: ${pkgfile}"
				return 0 # delete
			fi
		done
	fi
	return 1 # keep
}

check_should_delete_pkg() {
	[ "$#" -eq 1 ] || eargs check_should_delete_pkg file
	local file="$1"

	case "${file}" in
	*"/Hashed")
		if [ -d "${file}" ]; then
			return 0
		fi
		;;
	*".${PKG_EXT}")
		if should_delete "${file}"; then
			echo "${file}" >> "${BADFILES_LIST:?}"
			# If the pkg is a symlink to a hashed package, remove the hashed version as well
			if [ -L "${file}" ]; then
				echo "$(realpath "${file}")" >> "${BADFILES_LIST:?}"
			fi
		fi
		;;
	*.txz)
		if [ -L "${file}" ]; then
			# Ignore txz symlinks as they otherwise
			# cause spam and confusion.  If we delete
			# a package it points to then it will be
			# removed later by
			# delete_stale_symlinks_and_empty_dirs().
			continue
		fi
		# FALLTHROUGH
		;&
	*)
		msg_verbose "Found incorrect format file: ${file}"
		echo "${file}" >> "${BADFILES_LIST:?}"
		# If the pkg is a symlink to a hashed package, remove the hashed version as well
		if [ -L "${file}" ]; then
			echo "$(realpath "${file}")" >> "${BADFILES_LIST:?}"
		fi
		;;
	esac
}

parallel_start
for file in "${PACKAGES:?}"/All/*; do
	parallel_run check_should_delete_pkg "${file}"
done
if ! parallel_stop; then
	err 1 "Fatal errors processing packages"
fi

check_duplicated_packages() {
	[ "$#" -eq 2 ] || eargs check_duplicated_packages origin packages
	local origin="$1"
	local packages="$2"
	local lastpkg lastver pkgversion pkg

	lastpkg=
	lastver=0
	for pkg in ${packages}; do
		pkgversion="${pkg##*-}"
		pkgversion="${pkgversion%.*}"

		case "${lastpkg}" in
		"")
			lastpkg="${pkg}"
			lastver="${pkgversion}"
			continue
			;;
		esac

		case "$(pkg_version -t "${pkgversion}" "${lastver}")" in
			'>')
				msg_verbose "Found old package: ${lastpkg}"
				echo "${lastpkg}" >> "${BADFILES_LIST:?}"
				lastpkg="${pkg}"
				lastver="${pkgversion}"
				;;
			'<')
				msg_verbose "Found old package: ${pkg}"
				echo "${pkg}" >> "${BADFILES_LIST:?}"
				;;
			'=')
				# This should be impossible now due to the
				# earlier pkgbase_is_needed() comparison
				# (by PKGBASE) and that this check is grouped
				# by PKGBASE.  Any renamed package is trimmed
				# out by the failed pkgbase_is_needed() check.
				err 1 "Found duplicated packages ${pkg} vs ${lastpkg} with origin ${origin}"
				;;
		esac
	done
	msg_verbose "Keeping latest package: ${lastpkg##*/}"
}

parallel_start
# Check for duplicated origins (older packages) and keep only newer ones
# This also grouped by pkgbase to respect PKGNAME uniqueness
sort "${FOUND_ORIGINS:?}" | awk '
{
	pkg = $1
	origin = $2
	# Determine pkgbase to group by
	n = split(pkg, a, "/")
	pkgbase = a[n]
	sub(/-[^-]*$/, "", pkgbase)

	origins[pkgbase] = origin

	if (!origin_count[pkgbase])
		origin_count[pkgbase] = 0
	if (packages[pkgbase])
		packages[pkgbase] = packages[pkgbase] " " pkg
	else
		packages[pkgbase] = pkg
	origin_count[pkgbase] += 1
}
END {
	for (pkgbase in origin_count)
		if (origin_count[pkgbase] > 1)
			print origins[pkgbase],packages[pkgbase]
}
' | while mapfile_read_loop_redir origin packages; do
	parallel_run check_duplicated_packages "${origin}" "${packages}"
done
if ! parallel_stop; then
	err 1 "Fatal errors processing packages"
fi

ret=0
do_confirm_delete "${BADFILES_LIST}" "stale packages" \
    "${answer}" "${DRY_RUN}" || ret=$?
case "${ret}.${FORCE_BUILD_REPO}" in
# No files found and not forced, or dry-run, then exit.
2.0|3)
	exit 0
	;;
esac

# After deleting stale files, need to remake repo.

if [ "${ret}" -eq 1 ] || [ "${FORCE_BUILD_REPO}" -eq 1 ]; then
	[ "${NO_RESTRICTED}" != "no" ] && clean_restricted
	if [ ${BUILD_REPO} -eq 1 ]; then
		if [ ${DO_ALL} -eq 1 ]; then
			msg "Removing pkg repository files"
			rm -f "${PACKAGES:?}/meta.txz" \
				"${PACKAGES:?}/meta.${PKG_EXT}" \
				"${PACKAGES:?}/digests.txz" \
				"${PACKAGES:?}/digests.${PKG_EXT}" \
				"${PACKAGES:?}/filesite.txz" \
				"${PACKAGES:?}/filesite.${PKG_EXT}" \
				"${PACKAGES:?}/packagesite.txz" \
				"${PACKAGES:?}/packagesite.${PKG_EXT}"
		else
			build_repo
		fi
	fi
	delete_stale_symlinks_and_empty_dirs
	delete_stale_pkg_cache
	if [ ${DO_ALL} -eq 1 ]; then
		msg "Cleaned all packages but ${PACKAGES} may need to be removed manually."
	fi
fi
run_hook pkgclean done ${ret} ${BUILD_REPO}
