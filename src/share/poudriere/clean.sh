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
	local deps_to_check deps_to_clean
	local rdep_dir

	rdep_dir="${JAILMNT}/poudriere/cleaning/rdeps/${pkgname}"

	# Exclusively claim the rdeps dir or return, another clean.sh owns it
	# or there were no reverse deps for this package.
	mv "${JAILMNT}/poudriere/rdeps/${pkgname}" "${rdep_dir}" 2>/dev/null ||
	    return 0

	# Cleanup everything that depends on my package
	# Note 2 loops here to avoid rechecking clean_rdepends every loop.
	if [ ${clean_rdepends} -eq 1 ]; then
		# Recursively cleanup anything that depends on my package.
		for dep_dir in ${rdep_dir}/*; do
			# May be empty if all my reverse deps are now skipped.
			case "${dep_dir}" in "${rdep_dir}/*") break ;; esac
			dep_pkgname=${dep_dir##*/}

			# clean_pool() in common.sh will pick this up and add to SKIPPED
			echo "${dep_pkgname}"

			clean_pool ${dep_pkgname} ${clean_rdepends}
		done
	else
		for dep_dir in ${rdep_dir}/*; do
			dep_pkgname=${dep_dir##*/}

			deps_to_check="${deps_to_check} ${JAILMNT}/poudriere/deps/${dep_pkgname}"
			deps_to_clean="${deps_to_clean} ${JAILMNT}/poudriere/deps/${dep_pkgname}/${pkgname}"
		done

		# Remove this package from every package depending on this.
		# This is removing: deps/<dep_pkgname>/<this pkg>.
		# Note that this is not needed when recursively cleaning as
		# the entire /deps/<pkgname> for all my rdeps will be removed.
		echo ${deps_to_clean} | xargs rm -f || :

		# Look for packages that are now ready to build. They have no
		# remaining dependencies. Move them to /unbalanced for later
		# processing.
		echo ${deps_to_check} | \
		    xargs -J % \
		    find % -type d -maxdepth 0 -empty 2>/dev/null | \
		    xargs -J % mv % "${JAILMNT}/poudriere/pool/unbalanced" \
		    2>/dev/null || :
	fi

	rm -rf "${rdep_dir}" &

	return 0
}

# Remove my /deps/<pkgname> dir and any references to this dir in /rdeps/
clean_deps() {
	local pkgname=$1
	local clean_rdepends=$2
	local dep_dir rdep_pkgname
	local deps_to_check rdeps_to_clean
	local dir

	dep_dir="${JAILMNT}/poudriere/cleaning/deps/${pkgname}"

	# Exclusively claim the deps dir or return, another clean.sh owns it
	mv "${JAILMNT}/poudriere/deps/${pkgname}" "${dep_dir}" 2>/dev/null ||
	    return 0

	# Remove myself from all my dependency rdeps to prevent them from
	# trying to skip me later

	for dir in ${dep_dir}/*; do
		rdep_pkgname=${dir##*/}

		rdeps_to_clean="${rdeps_to_clean} ${JAILMNT}/poudriere/rdeps/${rdep_pkgname}/${pkgname}"
	done

	echo ${rdeps_to_clean} | xargs rm -f || :

	rm -rf "${dep_dir}" &

	return 0
}

clean_pool() {
	local pkgname=$1
	local clean_rdepends=$2

	clean_rdeps "${pkgname}" ${clean_rdepends}

	# Remove this pkg from the needs-to-build list. It will not exist
	# if this build was sucessful. It only exists if clean_pool is
	# being called recursively to skip items and in that case it will
	# not be empty.
	[ ${clean_rdepends} -eq 1 ] &&
	    clean_deps "${pkgname}" ${clean_rdepends}

	return 0
}

clean_pool "${PKGNAME}" ${CLEAN_RDEPENDS}
