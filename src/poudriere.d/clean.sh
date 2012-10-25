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

	rm -rf "${JAILMNT}/poudriere/pool/${pkgname}"
	if [ -d "${JAILMNT}/poudriere/rpool/${pkgname}" ]; then
		echo ${JAILMNT}/poudriere/pool/*/${pkgname} 2>/dev/null | xargs rm -f
		rm -rf "${JAILMNT}/poudriere/rpool/${pkgname}"
	fi
}

clean_pool "${PKGNAME}" ${CLEAN_RDEPENDS}
