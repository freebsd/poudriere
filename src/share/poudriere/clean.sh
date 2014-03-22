#!/bin/sh
# 
# Copyright (c) 2012-2013 Baptiste Daroussin <bapt@FreeBSD.org>
# Copyright (c) 2012-2014 Bryan Drewery <bdrewery@FreeBSD.org>
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

# Remove myself from the remaining list of dependencies for anything
# depending on this package. If clean_rdepends is set, instead cleanup
# anything depending on me and skip them.
clean_rdeps() {
	local pkgname=$1
	local clean_rdepends=$2
	local dep_dir dep_pkgname
	local deps_to_check
	local rdep_dir

	rdep_dir="${JAILMNT}/poudriere/cleaning/rdeps/${pkgname}"

	# Exclusively claim the rdeps dir or return, another clean.sh owns it
	mv "${JAILMNT}/poudriere/rdeps/${pkgname}" "${rdep_dir}" 2>/dev/null ||
	    return 0

	# Note that following code must be safe for an empty rdep_dir.

	for dep_dir in ${rdep_dir}/*; do
		# Handle empty dir
		[ "${dep_dir}" = "${rdep_dir}/*" ] && break
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

	# Remove this package from every package depending on this
	# This follows the symlink in rdeps which references
	# deps/<pkgname>/<this pkg>
	find "${rdep_dir}" -type l 2>/dev/null |
	    xargs realpath -q | xargs rm -f || :

	# Move ready-to-build packages into unbalanced
	echo ${deps_to_check} | \
	    xargs -J % \
	    find % -type d -maxdepth 0 -empty 2>/dev/null | \
	    xargs -J % mv % "${JAILMNT}/poudriere/pool/unbalanced" \
	    2>/dev/null || :

	rm -rf "${rdep_dir}"

	return 0
}

clean_pool() {
	local pkgname=$1
	local clean_rdepends=$2

	clean_rdeps "${pkgname}" ${clean_rdepends}

	rm -rf "${JAILMNT}/poudriere/deps/${pkgname}" 2>/dev/null || :

	return 0
}

clean_pool "${PKGNAME}" ${CLEAN_RDEPENDS}
