#!/bin/sh
# 
# Copyright (c) 2011-2013 Baptiste Daroussin <bapt@FreeBSD.org>
# Copyright (c) 2012-2013 Bryan Drewery <bdrewery@FreeBSD.org>
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

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

# test if there is any args
usage() {
	cat << EOF
poudriere ports [parameters] [options]

Parameters:
    -c            -- Create a portstree
    -d            -- Delete a portstree
    -u            -- Update a portstree
    -l            -- List all available portstrees
    -v            -- Be verbose; show more information.

Options:
    -F            -- when used with -c, only create the needed ZFS
                     filesystems and directories, but do not populate
                     them.
    -k            -- when used with -d, only unregister the directory from
                     the ports tree list, but keep the files.
    -p name       -- specifies the name of the portstree we workon . If not
                     specified, work on a portstree called "default".
    -f fs         -- FS name (tank/jails/myjail) if fs is "none" then do not
                     create on zfs
    -M mountpoint -- mountpoint
    -m method     -- when used with -c, specify the method used to create the
		     tree. By default it is portsnap, possible alternatives are
		     "portsnap", "svn", "svn+http", "svn+https",
		     "svn+file", "svn+ssh", "git"
    -B branch     -- Which branch to use for SVN method (default: head)
    -q            -- Quiet (Remove the header in the list view)
EOF
	exit 1
}

CREATE=0
FAKE=0
UPDATE=0
DELETE=0
LIST=0
QUIET=0
VERBOSE=0
KEEP=0
BRANCH=head
while getopts "B:cFudklp:qf:M:m:v" FLAG; do
	case "${FLAG}" in
		B)
			BRANCH="${OPTARG}"
			;;
		c)
			CREATE=1
			;;
		F)
			FAKE=1
			;;
		u)
			UPDATE=1
			;;
		p)
			PTNAME=${OPTARG}
			;;
		d)
			DELETE=1
			;;
		k)
			KEEP=1
			;;
		l)
			LIST=1
			;;
		q)
			QUIET=1
			;;
		f)
			PTFS=${OPTARG}
			;;
		M)
			PTMNT=${OPTARG}
			;;
		m)
			METHOD=${OPTARG}
			;;
		v)
			VERBOSE=$((${VERBOSE} + 1))
			;;
		*)
			usage
		;;
	esac
done

[ $(( CREATE + UPDATE + DELETE + LIST )) -lt 1 ] && usage

METHOD=${METHOD:-portsnap}
PTNAME=${PTNAME:-default}

case ${METHOD} in
portsnap);;
svn+http);;
svn+https);;
svn+ssh);;
svn+file);;
svn);;
git);;
*) usage;;
esac

if [ ${LIST} -eq 1 ]; then
	format='%-20s %-10s %s\n'
	[ $QUIET -eq 0 ] &&
		printf "${format}" "PORTSTREE" "METHOD" "PATH"
	porttree_list | while read ptname ptmethod ptpath; do
		printf "${format}" ${ptname} ${ptmethod} ${ptpath}
	done
else
	[ -z "${PTNAME}" ] && usage
fi

cleanup_new_ports() {
	msg "Error while creating ports tree, cleaning up." >&2
	destroyfs ${PTMNT} ports
	rm -rf ${POUDRIERED}/ports/${PTNAME} || :
}

if [ ${CREATE} -eq 1 ]; then
	# test if it already exists
	porttree_exists ${PTNAME} && err 2 "The ports tree, ${PTNAME}, already exists"
	: ${PTMNT="${BASEFS:=/usr/local${ZROOTFS}}/ports/${PTNAME}"}
	: ${PTFS="${ZPOOL}${ZROOTFS}/ports/${PTNAME}"}

	# Wrap the ports creation in a special cleanup hook that will remove it
	# if any error is encountered
	CLEANUP_HOOK=cleanup_new_ports

	createfs ${PTNAME} ${PTMNT} ${PTFS}
	pset ${PTNAME} mnt ${PTMNT}
	if [ $FAKE -eq 0 ]; then
		case ${METHOD} in
		portsnap)
			mkdir ${PTMNT}/.snap
			msg "Extracting portstree \"${PTNAME}\"..."
			/usr/sbin/portsnap -d ${PTMNT}/.snap -p ${PTMNT} fetch extract ||
			/usr/sbin/portsnap -d ${PTMNT}/.snap -p ${PTMNT} fetch extract ||
			    err 1 " fail"
			;;
		svn*)
			case ${METHOD} in
			svn+http) proto="http" ;;
			svn+https) proto="https" ;;
			svn+ssh) proto="svn+ssh" ;;
			svn+file) proto="file" ;;
			svn) proto="svn" ;;
			esac

			msg_n "Checking out the ports tree..."
			[ ${VERBOSE} -gt 0 ] || quiet="-q"
			${SVN_CMD} ${quiet} co \
				${SVN_PRESERVE_TIMESTAMP} \
				${proto}://${SVN_HOST}/ports/${BRANCH} \
				${PTMNT} || err 1 " fail"
			echo " done"
			;;
		git)
			msg_n "Cloning the ports tree..."
			[ ${VERBOSE} -gt 0 ] || quiet="-q"
			git clone --depth=1 ${quiet} ${GIT_URL} ${PTMNT} || err 1 " fail"
			echo " done"
			;;
		esac
		pset ${PTNAME} method ${METHOD}
	else
		pset ${PTNAME} method "-"
	fi

	unset CLEANUP_HOOK
fi

if [ ${DELETE} -eq 1 ]; then
	porttree_exists ${PTNAME} || err 2 "No such ports tree ${PTNAME}"
	PTMNT=$(pget ${PTNAME} mnt)
	[ -d "${PTMNT}/ports" ] && PORTSMNT="${PTMNT}/ports"
	${NULLMOUNT} | /usr/bin/grep -q "${PORTSMNT:-${PTMNT}} on" \
		&& err 1 "Ports tree \"${PTNAME}\" is currently mounted and being used."
	msg_n "Deleting portstree \"${PTNAME}\""
	[ ${KEEP} -eq 0 ] && destroyfs ${PTMNT} ports
	rm -rf ${POUDRIERED}/ports/${PTNAME} || :
	echo " done"
fi

if [ ${UPDATE} -eq 1 ]; then
	porttree_exists ${PTNAME} || err 2 "No such ports tree ${PTNAME}"
	METHOD=$(pget ${PTNAME} method)
	PTMNT=$(pget ${PTNAME} mnt)
	[ -d "${PTMNT}/ports" ] && PORTSMNT="${PTMNT}/ports"
	${NULLMOUNT} | /usr/bin/grep -q "${PORTSMNT:-${PTMNT}} on" \
		&& err 1 "Ports tree \"${PTNAME}\" is currently mounted and being used."
	msg "Updating portstree \"${PTNAME}\""
	if [ -z "${METHOD}" -o ${METHOD} = "-" ]; then
		METHOD=portsnap
		pset ${PTNAME} method ${METHOD}
	fi
	case ${METHOD} in
	portsnap|"")
		if [ -d "${PTMNT}/snap" ]; then
			SNAPDIR=${PTMNT}/snap
		else
			SNAPDIR=${PTMNT}/.snap
		fi
		/usr/sbin/portsnap -d ${SNAPDIR} -p ${PORTSMNT:-${PTMNT}} ${PSCOMMAND} alfred
		;;
	svn*)
		msg_n "Updating the ports tree..."
		[ ${VERBOSE} -gt 0 ] || quiet="-q"
		${SVN_CMD} upgrade ${PORTSMNT:-${PTMNT}} 2>/dev/null || :
		${SVN_CMD} ${quiet} update \
			${SVN_PRESERVE_TIMESTAMP} \
			${PORTSMNT:-${PTMNT}}
		echo " done"
		;;
	git)
		msg "Pulling from ${GIT_URL}"
		[ ${VERBOSE} -gt 0 ] |- quiet="-q"
		cd ${PORTSMNT:-${PTMNT}} && git pull ${quiet}
		echo " done"
		;;
	*)
		err 1 "Undefined upgrade method"
		;;
	esac

	date +%s > ${PORTSMNT:-${PTMNT}}/.poudriere.stamp
fi
