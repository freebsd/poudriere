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

usage() {
	cat <<EOF
poudriere pkgclean [options] [-f file|cat/port ...]

Parameters:
    -A          -- Remove all packages
    -a          -- Keep all known ports
    -f file     -- Get the list of ports to keep from a file
    [ports...]  -- List of ports to keep on the command line

Options:
    -j jail     -- Which jail to use for packages
    -J n        -- Run n jobs in parallel (Defaults to the number of
                   CPUs times 1.25)
    -n          -- Do not actually remove anything, just show what would be
                   removed
    -N          -- Do not build the package repository when clean completed
    -p tree     -- Which ports tree to use for packages
    -R          -- Clean RESTRICTED packages after building
    -v          -- Be verbose; show more information. Use twice to enable
                   debug output
    -y          -- Assume yes when deleting and do not confirm
    -z set      -- Specify which SET to use for packages
EOF
	exit 1
}

PTNAME=default
SETNAME=""
DRY_RUN=0
DO_ALL=0
BUILD_REPO=1

. ${SCRIPTPREFIX}/common.sh

[ $# -eq 0 ] && usage

while getopts "Aaj:J:f:nNp:Rvyz:" FLAG; do
	case "${FLAG}" in
		A)
			DO_ALL=1
			;;
		a)
			ALL=1
			;;
		j)
			jail_exists ${OPTARG} || err 1 "No such jail: ${OPTARG}"
			JAILNAME=${OPTARG}
			;;
		J)
			PREPARE_PARALLEL_JOBS=${OPTARG}
			;;
		f)
			# If this is a relative path, add in ${PWD} as
			# a cd / was done.
			[ "${OPTARG#/}" = "${OPTARG}" ] && \
			    OPTARG="${SAVED_PWD}/${OPTARG}"
			LISTPKGS="${LISTPKGS} ${OPTARG}"
			;;
		n)
			DRY_RUN=1
			;;
		N)
			BUILD_REPO=0
			;;
		p)
			porttree_exists ${OPTARG} ||
			    err 2 "No such ports tree: ${OPTARG}"
			PTNAME=${OPTARG}
			;;
		R)
			NO_RESTRICTED=1
			;;
		v)
			VERBOSE=$((${VERBOSE} + 1))
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

saved_argv="$@"
shift $((OPTIND-1))
post_getopts

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

PACKAGES=${POUDRIERE_DATA}/packages/${MASTERNAME}
if [ "${ATOMIC_PACKAGE_REPOSITORY}" = "yes" ]; then
	if [ -d "${PACKAGES}/.building" ]; then
		msg "Cleaning in previously failed build directory"
		PACKAGES="${PACKAGES}/.building"
	else
		PACKAGES="${PACKAGES}/.latest"
	fi
fi

PKG_EXT='*' package_dir_exists_and_has_packages ||
    err 0 "No packages exist for ${MASTERNAME}"

maybe_run_queued "${saved_argv}"

msg "Gathering all expected packages"
jail_start ${JAILNAME} ${PTNAME} ${SETNAME}
prepare_ports
msg "Looking for unneeded packages"
bset status "pkgclean:"

# Some packages may exist that are stale, but are still the latest version
# built. Don't delete those, bulk will incrementally delete them. We only
# want to delete packages that are duplicated and old, non-packages, and
# packages that are not in the cmdline-specified port list or in their
# dependencies and finally packages in the wrong format.

CLEANUP_HOOK=pkgclean_cleanup
pkgclean_cleanup() {
	rm -f ${BADFILES_LIST} ${FOUND_ORIGINS} 2>/dev/null
}
BADFILES_LIST=$(mktemp -t poudriere_pkgclean)
FOUND_ORIGINS=$(mktemp -t poudriere_pkgclean)

for file in ${PACKAGES}/All/*; do
	case ${file} in
		*.${PKG_EXT})
			pkgname="${file##*/}"
			pkgname="${pkgname%.*}"
			if ! pkg_get_origin origin "${file}"; then
				msg_verbose "Found corrupt package: ${file}"
				echo "${file}" >> ${BADFILES_LIST}
			elif ! pkgbase_is_needed "${pkgname}"; then
				msg_verbose "Found unwanted package: ${file}"
				echo "${file}" >> ${BADFILES_LIST}
			else
				echo "${file} ${origin}" >> ${FOUND_ORIGINS}
			fi
			;;
		*)
			msg_verbose "Found incorrect format file: ${file}"
			echo "${file}" >> ${BADFILES_LIST}
			;;
	esac
done

pkg_compare() {
	[ $# -eq 2 ] || eargs pkg_compare oldversion newversion
	local oldversion="$1"
	local newversion="$2"

	ensure_pkg_installed ||
	    err 1 \
	    "ports-mgmt/pkg is missing. First build it with bulk, then rerun pkgclean"

	injail ${PKG_VERSION} -t "${oldversion}" "${newversion}"
}

# Check for duplicated origins (older packages) and keep only newer ones
# This also groups by pkgbase to respect DEPENDS_ARGS / PKGNAME uniqueness
sort ${FOUND_ORIGINS} | awk '
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
' | while read origin packages; do
	lastpkg=
	lastver=0
	for pkg in $packages; do
		pkgversion="${pkg##*-}"
		pkgversion="${pkgversion%.*}"

		if [ -z "${lastpkg}" ]; then
			lastpkg="${pkg}"
			lastver="${pkgversion}"
			continue
		fi

		pkg_compare="$(pkg_compare "${pkgversion}" "${lastver}")"
		case ${pkg_compare} in
			'>')
				msg_verbose "Found old package: ${lastpkg}"
				echo "${lastpkg}" >> ${BADFILES_LIST}
				lastpkg="${pkg}"
				lastver="${pkgversion}"
				;;
			'<')
				msg_verbose "Found old package: ${pkg}"
				echo "${pkg}" >> ${BADFILES_LIST}
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
done

ret=0
do_confirm_delete "${BADFILES_LIST}" "stale packages" \
    "${answer}" "${DRY_RUN}" || ret=$?
if [ ${ret} -eq 2 ]; then
	exit 0
fi

# After deleting stale files, need to remake repo.

if [ $ret -eq 1 ]; then
	[ "${NO_RESTRICTED}" != "no" ] && clean_restricted
	delete_stale_symlinks_and_empty_dirs
	delete_stale_pkg_cache
	if [ ${BUILD_REPO} -eq 1 ]; then
		if [ ${DO_ALL} -eq 1 ]; then
			msg "Removing pkg repository files"
			rm -f "${PACKAGES}/meta.txz" \
				"${PACKAGES}/digests.txz" \
				"${PACKAGES}/packagesite.txz"
		else
			build_repo
		fi
	fi
	if [ ${DO_ALL} -eq 1 ]; then
		msg "Cleaned all packages but ${PACKAGES} may need to be removed manually."
	fi
fi
run_hook pkgclean done ${ret} ${BUILD_REPO}
