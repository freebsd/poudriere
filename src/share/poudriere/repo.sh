#!/bin/sh
# 
# Copyright (c) 2013-2025 Bryan Drewery <bdrewery@FreeBSD.org>
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
poudriere repo [options]

Options:
    -j jail     -- Which jail to use for packages
    -NN         -- Do not commit/publish package repository
    -p tree     -- Which ports tree to use for packages
    -z set      -- Specify which SET to use for packages
EOF
	exit ${EX_USAGE}
}

PTNAME=default
SETNAME=""
BUILD_REPO=1
FORCE_BUILD_REPO=0
COMMIT=1

[ $# -eq 0 ] && usage

while getopts "j:Np:vz:" FLAG; do
	case "${FLAG}" in
		j)
			jail_exists ${OPTARG} || err 1 "No such jail: ${OPTARG}"
			JAILNAME=${OPTARG}
			;;
		N)
			# -NN is the functional flag here.
			# -N is provided for compat for bulk/testport.
			: ${NFLAG:=0}
			NFLAG=$((NFLAG + 1))
			BUILD_REPO=0
			if [ "${NFLAG}" -eq 2 ]; then
				COMMIT=0
			fi
			;;
		p)
			porttree_exists ${OPTARG} ||
			    err 2 "No such ports tree: ${OPTARG}"
			PTNAME=${OPTARG}
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

MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
_mastermnt MASTERMNT

export MASTERNAME
export MASTERMNT

: "${PACKAGES:=${POUDRIERE_DATA:?}/packages/${MASTERNAME:?}}"
PACKAGES_ROOT="${PACKAGES:?}"
PACKAGES_PKG_CACHE="${PACKAGES_ROOT:?}/.pkg-cache"
case "${ATOMIC_PACKAGE_REPOSITORY}" in
yes)
	# if [ -d "${PACKAGES:?}/.building" ]; then
	# 	msg "Building repository in previously failed build directory"
	# 	PACKAGES="${PACKAGES:?}/.building"
	# else
		PACKAGES="${PACKAGES:?}/.latest"
	# fi
	;;
esac

PKG_EXT='*' package_dir_exists_and_has_packages ||
    err 0 "No packages exist for ${MASTERNAME}"

maybe_run_queued "${saved_argv}"

jail_start "${JAILNAME}" "${PTNAME}" "${SETNAME}"
fetch_global_port_vars ||
    err 1 "Failed to lookup global ports metadata"
if ! ensure_pkg_installed; then
	err 1 "pkg must be built before this command can be used"
fi

build_repo
case "${COMMIT}" in
1)
	# This assumes that COMMIT_PACKAGES_ON_FAILURE
	# has been handled by the build.
	run_hook -v pkgrepo publish "${PACKAGES:?}"
	;;
*)
	msg "(-NN) Skipping repository publish"
	;;
esac
