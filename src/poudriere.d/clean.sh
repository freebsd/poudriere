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

	# Determine everything that depends on the given package
	# Recursively cleanup anything that depends on this port.
	if [ ${clean_rdepends} -eq 1 ]; then
		if [ -d "${JAILMNT}/poudriere/rpool/${pkgname}" ]; then
			for dep_pkgname in $(ls "${JAILMNT}/poudriere/rpool/${pkgname}/"); do

				# clean_pool() in common.sh will pick this up and add to SKIPPED
				echo "${dep_pkgname}"

				clean_pool ${dep_pkgname} ${clean_rdepends}
			done
		fi
	fi

	# Determine which packages are ready-to-build,
	# and move from deps/ to pool/
	if [ -d "${JAILMNT}/poudriere/rpool/${pkgname}" ] && \
		[ -z "$(find "${JAILMNT}/poudriere/rpool/${pkgname}" -type d -maxdepth 0 -empty)" ]; then
		for dep_dir in ${JAILMNT}/poudriere/rpool/${pkgname}/*; do
			dep_pkgname=${dep_dir##*/}
			rm -f "${JAILMNT}/poudriere/deps/${dep_pkgname}/${pkgname}"
			# If that packages was just waiting on my package, and
			# is now ready-to-build, move it to pool/
			find "${JAILMNT}/poudriere/deps/${dep_pkgname}" \
				-type d -maxdepth 0 -empty \
				-exec mv {} "${JAILMNT}/poudriere/pool" \;
		done
	fi
	rm -rf "${JAILMNT}/poudriere/pool/${pkgname}" \
		"${JAILMNT}/poudriere/rpool/${pkgname}" 2>/dev/null || :
}

clean_pool "${PKGNAME}" ${CLEAN_RDEPENDS}
