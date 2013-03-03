#!/bin/sh

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
				find % -type d -maxdepth 0 -empty | \
				xargs -J % mv % "${JAILMNT}/poudriere/pool/unbalanced" \
				2>/dev/null || :
		fi
	fi

	rm -rf "${JAILMNT}/poudriere/deps/${pkgname}" \
		"${JAILMNT}/poudriere/rdeps/${pkgname}" 2>/dev/null || :
}

clean_pool "${PKGNAME}" ${CLEAN_RDEPENDS}
