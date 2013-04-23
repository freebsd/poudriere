#!/bin/sh
# 
# Copyright (c) 2012-2013 Baptiste Daroussin <bapt@FreeBSD.org>
# Copyright (c) 2012-2013 Bryan Drewery <bdrewery@FreeBSD.org>
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

JAILMNT=$1
PKGNAME=$2
CLEAN_RDEPENDS=${3:-0}

case "${JAILMNT}" in
	/?*)
		;;
	*)
		echo "Invalid JAILMNT passed when cleaning pool" >&2
		exit 1
		;;
esac

if [ -z "${PKGNAME}" ]; then
	echo "Invalid PKGNAME passed when cleaning pool" >&2
	exit 1
fi

clean_pool() {
	local pkgname=$1
	local clean_rdepends=$2
	local dep_dir dep_pkgname
	local deps_to_check

	if [ -d "${JAILMNT}/poudriere/rdeps/${pkgname}" ]; then
		# Determine which packages are ready-to-build and
		# handle "impact"/skipping support
		if [ -z "$(find "${JAILMNT}/poudriere/rdeps/${pkgname}" -type d -maxdepth 0 -empty)" ]; then

			# Remove this package from every package depending on this
			# This follows the symlink in rdeps which references
			# deps/<pkgname>/<this pkg>
			find ${JAILMNT}/poudriere/rdeps/${pkgname} -type l | \
				xargs realpath -q | \
				xargs rm -f || :

			for dep_dir in ${JAILMNT}/poudriere/rdeps/${pkgname}/*; do
				[ "${dep_dir}" = "${JAILMNT}/poudriere/rdeps/${pkgname}/*" ] &&
					break
				dep_pkgname=${dep_dir##*/}

				# Determine everything that depends on the given package
				# Recursively cleanup anything that depends on this port.
				if [ ${clean_rdepends} -eq 1 ]; then
					# clean_pool() in common.sh will pick this up and add to SKIPPED
					echo "${dep_pkgname}"

					clean_pool ${dep_pkgname} ${clean_rdepends}
					#clean_pool deletes deps/${dep_pkgname} already
					# no need for below code
				else
					# If that packages was just waiting on my package, and
					# is now ready-to-build, move it to pool/
					deps_to_check="${deps_to_check} ${JAILMNT}/poudriere/deps/${dep_pkgname}"
				fi
			done

			echo ${deps_to_check} | \
				xargs -J % \
				find % -type d -maxdepth 0 -empty 2>/dev/null | \
				xargs -J % mv % "${JAILMNT}/poudriere/pool/unbalanced" \
				2>/dev/null || :
		fi
	fi

	rm -rf "${JAILMNT}/poudriere/deps/${pkgname}" \
		"${JAILMNT}/poudriere/rdeps/${pkgname}" 2>/dev/null || :
}

clean_pool "${PKGNAME}" ${CLEAN_RDEPENDS}
