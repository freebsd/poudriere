#!/bin/sh
#
# Copyright (c) 2023 Brad Davis <brd@FreeBSD.org>
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
poudriere audit [-z <set>] [-p <ports tree>] -j <jail>

Options:
    -j name     -- Run on the given jail
    -p tree     -- Specify which ports tree to use for comparing to distfiles.
                   Can be specified multiple times. (Defaults to the 'default'
                   tree)
    -z set      -- Specify which SET to use
EOF
	exit ${EX_USAGE}
}

[ $# -eq 0 ] && usage

: ${PTNAME:=default}
SETNAME=""


while getopts "j:p:z:" FLAG; do
	case "${FLAG}" in
		j)
			jail_exists ${OPTARG} || err 1 "No such jail: ${OPTARG}"
			JAILNAME=${OPTARG}
			;;
		p)
			porttree_exists ${OPTARG} || \
				err 1 "No such ports tree: ${OPTARG}"
			PTNAME="${OPTARG}"
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

[ -z "${JAILNAME}" ] && \
	err 1 "Don't know on which jail to run please specify -j"

MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
: "${PACKAGES:=${POUDRIERE_DATA:?}/packages/${MASTERNAME:?}}"
_mastermnt MASTERMNT

PKG_EXT='*' package_dir_exists_and_has_packages || \
	err 0 "No packages exist for ${MASTERNAME}"

msg "Auditing for jail '${MASTERNAME}'"
if ! pkg audit -d "${PACKAGES}"; then
	exit 1
fi
