#!/bin/sh
set -e

usage() {
	echo "poudriere bulk parameters [options]

Parameters:
    -f file     -- Give the list of ports to build

Options:
    -c          -- Clean the previous built binary packages
    -t          -- Add some testings to package building
    -s          -- Skip sanity
    -J n        -- Run n jobs in parallel
    -j name     -- Run only on the given jail
    -p tree     -- Specify on which ports tree the bulk will be done"

	exit 1
}

run_build() {
	local activity cnt mnt fs name arch version
	PORTSDIR=`port_get_base ${PTNAME}`/ports
	arch=$(zget arch)
	version=$(zget version)
	for j in $(jot -w %02d ${PARALLEL_JOBS}); do
		mnt="${JAILMNT}/build/${j}"
		mkdir -p "${mnt}"
		fs="${JAILFS}/job-${j}"
		name="${JAILNAME}-job-${j}"
		zfs clone -o mountpoint=${mnt} \
			-o ${NS}:name=${name} \
			-o ${NS}:type=rootfs \
			-o ${NS}:arch=${arch} \
			-o ${NS}:version=${version} \
			${JAILFS}@prepkg ${fs}
		zfs snapshot ${fs}@prepkg
		mount -t devfs devfs ${mnt}/dev
		mount -t procfs proc ${mnt}/proc
		mount -t linprocfs linprocfs ${mnt}/compat/linux/proc
		mount -t linsysfs linsysfs ${mnt}/compat/linux/sys
		mount -t nullfs ${PORTSDIR} ${mnt}/usr/ports
		mount -t nullfs ${PKGDIR} ${mnt}/usr/ports/packages
		if [ -n "${DISTFILES_CACHE}" -a -d "${DISTFILES_CACHE}" ]; then
			mount -t nullfs ${DISTFILES_CACHE} ${mnt}/usr/ports/distfiles || err 1 "Failed to mount the distfile directory"
		fi
		[ -n "${MFSSIZE}" ] && mdmfs -M -S -o async -s ${MFSSIZE} md ${mnt}/wrkdirs
		[ -n "${USE_TMPFS}" ] && mount -t tmpfs tmpfs ${mnt}/wrkdirs
		if [ -d ${POUDRIERED}/${ORIGNAME:-${JAILNAME}}-options ]; then
			mount -t nullfs ${POUDRIERED}/${JAILNAME}-options ${mnt}/var/db/ports || err 1 "Failed to mount OPTIONS directory"
		elif [ -d ${POUDRIERED}/options ]; then
			mount -t nullfs ${POUDRIERED}/options ${mnt}/var/db/ports || err 1 "Failed to mount OPTIONS directory"
		fi
		if [ -n "${CCACHE_DIR}" -a -d "${CCACHE_DIR}" ]; then
			# Mount user supplied CCACHE_DIR into /var/cache/ccache
			mount -t nullfs ${CCACHE_DIR} ${mnt}${CCACHE_DIR} || err 1 "Failed to mount the ccache directory "
			export CCACHE_DIR
		fi
		JAILNAME=${name} JAILMNT=${mnt} JAILFS=${fs} jrun 0
		JAILFS=${fs} zset status "idle:"
	done
	while :; do
		activity=0
		for j in $(jot -w %02d ${PARALLEL_JOBS}); do
			mnt="${JAILMNT}/build/${j}"
			fs="${JAILFS}/job-${j}"
			name="${JAILNAME}-job-${j}"
			if [ -f  "${JAILMNT}/${j}.pid" ]; then
				if pgrep -qF "${JAILMNT}/${j}.pid" >/dev/null 2>&1; then
					continue
				fi
				rm -f "${JAILMNT}/${j}.pid"
				cnt=$(wc -l ${JAILMNT}/ignored | awk '{ print $1 }')
				zset stats_ignored $cnt
				cnt=$(wc -l ${JAILMNT}/built | awk '{ print $1 }')
				zset stats_built $cnt
				cnt=$(wc -l ${JAILMNT}/failed | awk '{ print $1 }')
				zset stats_failed $cnt
			fi
			port=$(next_in_queue)
			if [ -z "${port}" ]; then
				# pool empty ?
				[ $(stat -f '%z' ${JAILMNT}/pool) -eq 2 ] && return
				break
			fi
			msg "Starting build of ${port}"
			JAILFS=${fs} zset status "starting:${port}"
			activity=1
			zfs rollback -r ${fs}@prepkg
			MASTERMNT=${JAILMNT} JAILNAME="${name}" JAILMNT="${mnt}" JAILFS="${fs}" \
				build_pkg ${port} >/dev/null 2>&1 &
			echo "$!" > ${JAILMNT}/${j}.pid
		done
		# Sleep briefly if still waiting on builds, to save CPU
		[ $activity -eq 0 ] && sleep 0.1
	done
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
PTNAME="default"
SKIPSANITY=0
CLEAN=0
. ${SCRIPTPREFIX}/common.sh

while getopts "f:j:cn:p:ts" FLAG; do
	case "${FLAG}" in
		t)
			export PORTTESTING=1
			;;
		c)
			CLEAN=1
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
		s)
			SKIPSANITY=1
			;;
		*)
			usage
			;;
	esac
done

test -z ${LISTPKGS} && usage
test -f ${LISTPKGS} || err 1 "No such list of packages: ${LISTPKGS}"
export SKIPSANITY

STATUS=0 # out of jail #

test -z "${JAILNAME}" && err 1 "Don't know on which jail to run please specify -j"

PKGDIR=${POUDRIERE_DATA}/packages/${JAILNAME}-${PTNAME}
if [ ${CLEAN} -eq 1 ]; then
	msg_n "Cleaning previous bulks if any..."
	rm -rf ${PKGDIR}/*
	echo " done"
fi

JAILFS=`jail_get_fs ${JAILNAME}`
JAILMNT=`jail_get_base ${JAILNAME}`

jail_start

prepare_jail

prepare_ports

zset status "building:"

test -z ${PORTTESTING} && echo "DISABLE_MAKE_JOBS=yes" >> ${JAILMNT}/etc/make.conf
zfs snapshot ${JAILFS}@prepkg
msg "Starting using ${PARALLEL_JOBS} builders"
DONE=0
run_build
# wait for the last running processes
cat ${JAILMNT}/*.pid 2>/dev/null | xargs pwait 2>/dev/null
cnt=$(wc -l ${JAILMNT}/ignored | awk '{ print $1 }')
zset stats_ignored $cnt
cnt=$(wc -l ${JAILMNT}/built | awk '{ print $1 }')
zset stats_built $cnt
cnt=$(wc -l ${JAILMNT}/failed | awk '{ print $1 }')
zset stats_failed $cnt

failed=$(cat ${JAILMNT}/failed | xargs echo)
built=$(cat ${JAILMNT}/built | xargs echo)
ignored=$(cat ${JAILMNT}/ignored | xargs echo)
nbfailed=$(zget stats_failed)
nbignored=$(zget stats_ignored)
nbbuilt=$(zget stats_built)
[ "$nbfailed" = "-" ] && nbfailed=0
[ "$nbignored" = "-" ] && nbignored=0
[ "$nbbuilt" = "-" ] && nbbuilt=0
# Package all newly build ports
if [ $nbbuilt -eq 0 ]; then
	if [ $PKGNG -eq 1 ]; then
		msg "No package built, no need to update the repository"
	else
		msg "No package built, no need to update INDEX"
	fi
elif [ $PKGNG -eq 1 ]; then
	msg "Creating pkgng repository"
	zset status "pkgrepo:"
	injail tar xf /usr/ports/packages/Latest/pkg.txz -C /
	injail rm -f /usr/ports/packages/repo.txz /usr/ports/packages/repo.sqlite
	if [ -n "${PKG_REPO_SIGNING_KEY}" -a -f "${PKG_REPO_SIGNING_KEY}" ]; then
		install -m 0400 ${PKG_REPO_SIGNING_KEY} ${JAILMNT}/tmp/repo.key
		injail pkg-static repo /usr/ports/packages/ /tmp/repo.key
		rm -f ${JAILMNT}/tmp/repo.key
	else
		injail pkg-static repo /usr/ports/packages/
	fi
else
	msg "Preparing index"
	zset status "index:"
	OSMAJ=`injail uname -r | awk -F. '{ print $1 }'`
	INDEXF=${PKGDIR}/INDEX-${OSMAJ}
	for pkg_file in `ls ${PKGDIR}/All/*.tbz`; do
		msg_n "extracting description from `basename ${pkg_file}`"
		ORIGIN=`/usr/sbin/pkg_info -qo ${pkg_file}`
		[ -d ${PORTSDIR}/${ORIGIN} ] && injail make -C /usr/ports/${ORIGIN} describe >> ${INDEXF}.1
		echo " done"
	done

	awk -v indf=${INDEXF}.1 -F\| 'BEGIN {
	nblines=0
	while ((getline < indf) > 0) {
	sub(/\//, "\/", $2);
	patterns[nblines] = "^"$2"$";
	subst[nblines] = $1;
	a_edep[nblines] = $8;
	a_pdep[nblines] = $9;
	a_fdep[nblines] = $10;
	a_bdep[nblines] = $11;
	a_rdep[nblines] = $12;
	nblines++;
	}
	OFS="|"}
	{

	edep = $8;
	pdep = $9;
	fdep = $10;
	bdep = $11;
	rdep = $12;

	split($8, sedep, " ") ;
	split($9, sfdep, " ") ;
	split($10, spdep, " ") ;
	split($11, sbdep, " ") ;
	split($12, srdep, " ") ;

	for (i = 0; i < nblines; i++) {
		for (s in sedep)
			if ( sedep[s] ~ patterns[i] )
				edep = edep" "a_rdep[i];

		for (s in sfdep)
			if ( sfdep[s] ~ patterns[i] )
				fdep = fdep" "a_rdep[i];

		for (s in spdep)
			if ( spdep[s] ~ patterns[i] )
				pdep = pdep" "a_rdep[i];

		for (s in sbdep)
			if ( sbdep[s] ~ patterns[i] )
				bdep = bdep" "a_rdep[i];

		for (s in srdep)
			if ( srdep[s] ~ patterns[i] )
				rdep = rdep" "a_rdep[i];
	}

	edep = uniq(edep, patterns, subst);
	fdep = uniq(fdep, patterns, subst);
	pdep = uniq(pdep, patterns, subst);
	bdep = uniq(bdep, patterns, subst);
	rdep = uniq(rdep, patterns, subst);

	sub(/^ /, "", edep);
	sub(/^ /, "", fdep);
	sub(/^ /, "", pdep);
	sub(/^ /, "", bdep);
	sub(/^ /, "", rdep);
	print $1"|"$2"|"$3"|"$4"|"$5"|"$6"|"$7"|"bdep"|"rdep"|"$13"|"edep"|"pdep"|"fdep
	}

	function array_s(array, str, i) {
		for (i in array)
			if (array[i] == str)
				return 0;

		return -1;
	}

	function uniq(as, pat, subst, B) {
		split(as, A, " ");
		as = "";

		for (a in A) {
			if (array_s(B, A[a]) != 0) {
				str = A[a];
				for (j in subst)
					sub(pat[j], subst[j], str);
					
				as = as" "str
				B[i] = A[a];
				i++;
			}
		}

		return as;
	}
	' ${INDEXF}.1 > ${INDEXF}

	rm ${INDEXF}.1
	[ -f ${INDEXF}.bz2 ] && rm ${INDEXF}.bz2
	msg_n "compressing INDEX-${OSMAJ} ..."
	bzip2 -9 ${INDEXF}
	echo " done"
fi

cleanup
msg "$nbbuilt packages built, $nbfailed failures, $nbignored ignored"
if [ $nbbuilt -gt 0 ]; then
	msg_n "Built ports: "
	echo ${built}
fi
if [ $nbfailed -gt 0 ]; then
	msg_n "Failed ports: "
	echo ${failed}
fi
if [ $nbignored -gt 0 ]; then
	msg_n "Ignored ports: "
	echo ${ignored}
fi

set +e

exit $nbfailed
