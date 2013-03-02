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

	if [ -d "${JAILMNT}/poudriere/rdeps/${pkgname}" ]; then
		# Determine which packages are ready-to-build and
		# handle "impact"/skipping support
		if [ -z "$(find "${JAILMNT}/poudriere/rdeps/${pkgname}" -type d -maxdepth 0 -empty)" ]; then
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
					rm -f "${JAILMNT}/poudriere/deps/${dep_pkgname}/${pkgname}"
					# If that packages was just waiting on my package, and
					# is now ready-to-build, move it to pool/
					find "${JAILMNT}/poudriere/deps/${dep_pkgname}" \
						-type d -maxdepth 0 -empty \
						-exec mv {} "${JAILMNT}/poudriere/pool/unbalanced" \;
				fi
			done
		fi
	fi

	rm -rf "${JAILMNT}/poudriere/deps/${pkgname}" \
		"${JAILMNT}/poudriere/rdeps/${pkgname}" 2>/dev/null || :
}

clean_pool "${PKGNAME}" ${CLEAN_RDEPENDS}
