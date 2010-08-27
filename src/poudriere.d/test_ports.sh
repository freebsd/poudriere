#!/bin/sh

usage() {
	echo "poudriere testport -d directory [-c]"
	echo "-c run make config for the given port"
	exit 1
}

outside_portsdir() {
	PORTROOT=`dirname $1`
	PORTROOT=`dirname ${PORTROOT}`
	test "${PORTROOT}" = `realpath ${PORTSDIR}` && return 1
	return 0
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

LOGS="${POUDRIERE_DATA}/logs"
mkdir -p ${LOGS}

while getopts "d:c" FLAG; do
	case "${FLAG}" in
		c)
		CONFIGSTR="make config"
		;;
		d)
		PORTDIRECTORY=`realpath ${OPTARG}`
		;;
		*)
		usage
		;;
	esac
done

test -z ${PORTDIRECTORY} && usage
PORTNAME=`make -C ${PORTDIRECTORY} -VPKGNAME`
for jailname in `zfs list -rH ${ZPOOL}/poudriere | awk '/^'${ZPOOL}'\/poudriere\// { sub(/^'${ZPOOL}'\/poudriere\//, "", $1); print $1 }'`; do
	MNT=`zfs list -H ${ZPOOL}/poudriere/${jailname} | awk '{ print $NF}'`
	/bin/sh ${SCRIPTPREFIX}/start_jail.sh -n ${jailname}
	mkdir -p ${MNT}/usr/ports
	mount -t nullfs ${PORTSDIR} ${MNT}/usr/ports
	mkdir -p ${POUDRIERE_DATA}/packages/${jailname}
	mount -t nullfs ${POUDRIERE_DATA}/packages/${jailname} ${MNT}/usr/ports/packages

	if outside_portsdir ${PORTDIRECTORY}; then
		mkdir -p ${MNT}/${PORTDIRECTORY}
		mount -t nullfs ${PORTDIRECTORY} ${MNT}/${PORTDIRECTORY}
	fi

	mkdir -p ${MNT}/usr/local/etc/
cat << EOF >> ${MNT}/usr/local/etc/portmaster.rc
LOCAL_PACKAGEDIR=/usr/ports/packages
NO_BACKUP=Bopt
NO_RECURSIVE_CONFIG=Gopt
RECURSE_THOROUGH=topt
ALWAYS_SCRUB_DISTFILES=dopt
PM_PACKAGES=first
PM_NO_CONFIRM=pm_no_confirm
PM_DEL_BUILD_ONLY=pm_dbo
EOF

	jexec -U root ${jailname} /usr/bin/env BATCH=yes make -C /usr/ports/ports-mgmt/portmaster install clean
	jexec -U root ${jailname} make -C ${PORTDIRECTORY} clean
	for pkg in `jexec -U root ${jailname} make -C ${PORTDIRECTORY} build-depends-list run-depends-list`; do
		PKGS="${PKGS} ${pkg}"
	done
	jexec -U root ${jailname} /usr/local/sbin/portmaster -Gg ${PKGS} 2>&1 | tee ${LOGS}/${PORTNAME}-${jailname}.depends.log

cat << EOF >> ${MNT}/testports.sh
#!/bin/sh

export BATCH=yes
cd ${PORTDIRECTORY}

PKGNAME=\`make -V PKGNAME\` 
PKG_DBDIR=\`mktemp -d -t pkg_db\` || exit 1

LOCALBASE=\`make -VLOCALBASE\`
PREFIX="\${BUILDROOT:-/tmp}/\`echo \${PKGNAME} | tr  '[,+]' _\`"

PORT_FLAGS="PREFIX=\${PREFIX} PKG_DBDIR=\${PKG_DBDIR} NO_DEPENDS=yes\$*"

echo "===> Building with flags: \${PORT_FLAGS}"
echo "===> Cleaning workspace"
make clean

$CONFIGSTR

if [ -d \${PREFIX} ]; then
	echo "===> Removing existing \${PREFIX}"
	[ "\${PREFIX}" != "\${LOCALBASE}" ] && rm -rf \${PREFIX}
fi

echo "===> Building \${PKGNAME}"
for PHASE in build install package deinstall
do
	if [ "\${PHASE}" = "deinstall" ]; then
		echo "===> Checking pkg_info"
		PKG_DBDIR=\${PKG_DBDIR} pkg_info | grep \${PKGNAME}
		PLIST="\${PKG_DBDIR}/\${PKGNAME}/+CONTENTS"
		if [ -r \${PLIST} ]; then
			echo "===> Checking shared library dependencies"
			grep -v "^@" \${PLIST} | \
			sed -e "s,^,\${PREFIX}/," | \
			xargs ldd 2>&1 | \
			grep -v "not a dynamic executable" | \
			grep '=>' | awk '{print \$3;}' | sort -u
		fi
	fi
	make \${PORT_FLAGS} \${PHASE}
	if [ \$? -gt 0 ]; then
		echo "===> Error running make \${PHASE}"
		if [ "\${PHASE}" = "package" ]; then
			echo "===> Files currently installd in PREFIX"
			test -d \${PREFIX} && find \${PREFIX} ! -type d | \
			egrep -v "\${PREFIX}/share/nls/(POSIX|en_US.US-ASCII)"  | \
			sed -e "s,^\${PREFIX}/,,"
		fi
		echo "===> Cleaning up"
		[ "\${PREFIX}" != "\${LOCALBASE}" ] && rm -rf \${PREFIX}
		rm -rf \${PKG_DBDIR}
		exit 1
	fi
done

echo "===> Extra files and directories check"
find \${PREFIX} ! -type d | \
egrep -v "\${PREFIX}/share/nls/(POSIX|en_US.US-ASCII)"  | \
sed -e "s,^\${PREFIX}/,,"
find \${LOCALBASE}/ -type d | sed "s,^\${LOCALBASE}/,," | sort > \${PREFIX}.PLIST_DIRS.before
find \${PREFIX}/ -type d | sed "s,^\${PREFIX}/,," | sort > \${PREFIX}.PLIST_DIRS.after
comm -13 \${PREFIX}.PLIST_DIRS.before \${PREFIX}.PLIST_DIRS.after | sort -r | awk '{print "@dirrmtry "\$1}'

echo "===> Cleaning up"
make clean

echo "===>  Removing existing \${PREFIX} dir"
 [ "\${PREFIX}" != "\${LOCALBASE}" ] && rm -rf \${PREFIX} \${PREFIX}.PLIST_DIRS.before \${PREFIX}.PLIST_DIRS.after
 rm -rf \${PKG_DBDIR}
echo "===> Done."
exit 0
EOF

	jexec -U root ${jailname} /bin/sh /testports.sh 2>&1 | tee ${LOGS}/${PORTNAME}-${jailname}.build.log

	outside_portsdir ${PORTDIRECTORY} && umount ${PORTDIRECTORY}
	umount ${MNT}/usr/ports/packages
	umount ${MNT}/usr/ports
	/bin/sh ${SCRIPTPREFIX}/stop_jail.sh -n ${jailname}
done

