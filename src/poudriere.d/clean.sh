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
	local dep_dir dep_pkgname fulldep

	# Determine everything that depends on the given package
	# Recursively cleanup anything that depends on this port.
	if [ ${clean_rdepends} -eq 1 ]; then
		find ${JAILMNT}/poudriere/pool -name "${pkgname}" -type f | while read fulldep; do
			dep_dir=${fulldep%/*}
			dep_pkgname=${dep_dir##*/}
			clean_pool ${dep_pkgname} ${clean_rdepends}
		done

		# clean_pool() in common.sh will pick this up and add to SKIPPED
		echo "${pkgname}"
	fi

	rm -rf "${JAILMNT}/poudriere/pool/${pkgname}"
	find ${JAILMNT}/poudriere/pool -name "${pkgname}" -type f -delete
}

clean_pool "${PKGNAME}" ${CLEAN_RDEPENDS}
