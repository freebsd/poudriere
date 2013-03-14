#!/bin/sh
set -e

usage() {
	echo "poudriere bulk [options] [-f file|cat/port ...]

Parameters:
    -f file     -- Get the list of ports to build from a file
    [ports...]  -- List of ports to build on the command line

Options:
    -c          -- Clean all the previously built binary packages
    -C          -- Clean previously built packages from the given list to build
    -R          -- Clean RESTRICTED packages after building
    -t          -- Add some tests to the package build
    -s          -- Skip sanity checks
    -J n        -- Run n jobs in parallel (Default: to 8)
    -j name     -- Run only on the given jail
    -p tree     -- Specify on which ports tree the bulk build will be done
    -v          -- Be verbose; show more information. Use twice to enable debug output
    -w          -- Save WRKDIR on failed builds
    -z set      -- Specify which SET to use
    -a          -- Build the whole ports tree"

	exit 1
}

clean_restricted() {
	if [ -n "${NO_RESTRICTED}" ]; then
		msg "Cleaning restricted packages"
		# Remount rw
		# mount_nullfs does not support mount -u
		umount ${MASTERMNT}/packages
		mount_packages
		injail make -C /usr/ports -j ${PARALLEL_JOBS} clean-restricted
		# Remount ro
		umount ${MASTERMNT}/packages
		mount_packages -o ro
	fi
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
PTNAME="default"
SKIPSANITY=0
SETNAME=""
CLEAN=0
CLEAN_LISTED=0
ALL=0
. ${SCRIPTPREFIX}/common.sh

[ $# -eq 0 ] && usage

while getopts "f:j:J:Ccn:p:Rtsvwz:a" FLAG; do
	case "${FLAG}" in
		t)
			export PORTTESTING=1
			export DEVELOPER_MODE=yes
			;;
		c)
			CLEAN=1
			;;
		C)
			CLEAN_LISTED=1
			;;
		f)
			LISTPKGS=${OPTARG}
			;;
		j)
			jail_exists ${OPTARG} || err 1 "No such jail: ${OPTARG}"
			JAILNAME=${OPTARG}
			;;
		J)
			PARALLEL_JOBS=${OPTARG}
			;;
		p)
			PTNAME=${OPTARG}
			;;
		R)
			NO_RESTRICTED=1
			;;
		s)
			SKIPSANITY=1
			;;
		w)
			SAVE_WRKDIR=1
			;;
		z)
			[ -n "${OPTARG}" ] || err 1 "Empty set name"
			SETNAME="${OPTARG}"
			;;
		a)
			ALL=1
			;;
		v)
			VERBOSE=$((${VERBOSE:-0} + 1))
			;;
		*)
			usage
			;;
	esac
done

shift $((OPTIND-1))

export SKIPSANITY

STATUS=0 # out of jail #

test -z "${JAILNAME}" && err 1 "Don't know on which jail to run please specify -j"

MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
MASTERMNT=${POUDRIERE_DATA}/build/${MASTERNAME}/ref

export MASTERNAME
export MASTERMNT
if [ ${CLEAN} -eq 1 ]; then
	msg_n "Cleaning previous bulks if any..."
	rm -rf ${POUDRIERE_DATA}/packages/${MASTERNAME}/*
	rm -rf ${POUDRIERE_DATA}/cache/${JAILNAME}
	echo " done"
fi

if [ $# -eq 0 ]; then
	[ -n "${LISTPKGS}" -o ${ALL} -eq 1 ] || err 1 "No packages specified"
	[ ${ALL} -eq 1 -o -f "${LISTPKGS}" ] || err 1 "No such list of packages: ${LISTPKGS}"
else
	[ ${ALL} -eq 0 ] || err 1 "command line arguments and -a cannot be used at the same time"
	[ -z "${LISTPKGS}" ] || err 1 "command line arguments and list of ports cannot be used at the same time"
	LISTPORTS="$@"
fi

export POUDRIERE_BUILD_TYPE=bulk

jail_start ${JAILNAME} ${PTNAME} ${SETNAME}

LOGD=`log_path`
msg "Saving logs to ${LOGD}"
if [ -d ${LOGD} -a ${CLEAN} -eq 1 ]; then
	msg "Cleaning up old logs"
	rm -f ${LOGD}/*.log 2>/dev/null
fi

prepare_ports

bset status "building:"

if [ -z "${PORTTESTING}" -a -z "${ALLOW_MAKE_JOBS}" ]; then
	echo "DISABLE_MAKE_JOBS=yes" >> ${MASTERMNT}/etc/make.conf
fi

markfs prepkg ${MASTERMNT}

parallel_build ${JAILNAME} ${PTNAME} ${SETNAME} || : # Ignore errors as they are handled below

bset status "done:"

failed=$(bget ports.failed | awk '{print $1 ":" $3 }' | xargs echo)
built=$(bget ports.built | xargs echo)
ignored=$(bget ports.ignored | awk '{print $1}' | xargs echo)
skipped=$(bget ports.skipped | awk '{print $1}' | sort -u | xargs echo)
nbfailed=$(bget stats_failed)
nbignored=$(bget stats_ignored)
nbskipped=$(bget stats_skipped)
nbbuilt=$(bget stats_built)
[ "$nbfailed" = "-" ] && nbfailed=0
[ "$nbignored" = "-" ] && nbignored=0
[ "$nbskipped" = "-" ] && nbskipped=0
[ "$nbbuilt" = "-" ] && nbbuilt=0
# Package all newly build ports
if [ $nbbuilt -eq 0 ]; then
	if [ $PKGNG -eq 1 ]; then
		msg "No package built, no need to update the repository"
	else
		msg "No package built, no need to update INDEX"
	fi
elif [ $PKGNG -eq 1 ]; then
	clean_restricted
	msg "Creating pkgng repository"
	bset status "pkgrepo:"
	tar xf ${MASTERMNT}/packages/Latest/pkg.txz -C ${MASTERMNT} \
		-s ",/.*/,poudriere/,g" "*/pkg-static"
	rm -f ${POUDRIERE_DATA}/packages/${MASTERNAME}/repo.txz ${POUDRIERE_DATA}/packages/${MASTERNAME}/repo.sqlite
	if [ -n "${PKG_REPO_SIGNING_KEY}" -a -f "${PKG_REPO_SIGNING_KEY}" ]; then
		${MASTERMNT}/poudriere/pkg-static repo ${POUDRIERE_DATA}/packages/${MASTERNAME}/ ${PKG_REPO_SIGNING_KEY}
	else
		${MASTERMNT}/poudriere/pkg-static repo ${POUDRIERE_DATA}/packages/${MASTERNAME}/
	fi
else
	clean_restricted
	msg "Preparing INDEX"
	bset status "index:"
	OSMAJ=`injail uname -r | awk -F. '{ print $1 }'`
	INDEXF=${POUDRIERE_DATA}/packages/${MASTERNAME}/INDEX-${OSMAJ}
	rm -f ${INDEXF}.1 2>/dev/null || :
	for pkg_file in ${POUDRIERE_DATA}/packages/${MASTERNAME}/All/*.tbz; do
		# Check for non-empty directory with no packages in it
		[ "${pkg}" = "${POUDRIERE_DATA}/packages/${MASTERNAME}/All/*.tbz" ] && break
		msg_verbose "Extracting description for ${ORIGIN} ..."
		ORIGIN=$(pkg_get_origin ${pkg_file})
		[ -d ${MASTERMNT}/usr/ports/${ORIGIN} ] && injail make -C /usr/ports/${ORIGIN} describe >> ${INDEXF}.1
	done

	msg_n "Generating INDEX..."
	awk -v indf=${INDEXF}.1 -F\| -f ${AWKPREFIX}/make_index.awk ${INDEXF}.1 \
	    > ${INDEXF}
	echo " done"

	rm ${INDEXF}.1
	[ -f ${INDEXF}.bz2 ] && rm ${INDEXF}.bz2
	msg_n "Compressing INDEX-${OSMAJ}..."
	bzip2 -9 ${INDEXF}
	echo " done"
fi

cleanup
if [ $nbbuilt -gt 0 ]; then
	msg_n "Built ports: "
	echo ${built}
	echo ""
fi
if [ $nbfailed -gt 0 ]; then
	msg_n "Failed ports: "
	echo ${failed}
	echo ""
fi
if [ $nbignored -gt 0 ]; then
	msg_n "Ignored ports: "
	echo ${ignored}
	echo ""
fi
if [ $nbskipped -gt 0 ]; then
	msg_n "Skipped ports: "
	echo ${skipped}
	echo ""
fi
msg "[${MASTERNAME}] $nbbuilt packages built, $nbfailed failures, $nbignored ignored, $nbskipped skipped"

set +e

exit $((nbfailed + nbskipped))
