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

. ${SCRIPTPREFIX}/common.sh

# test if there is any args
usage() {
	cat << EOF
poudriere ports [parameters] [options]

Parameters:
    -c            -- Create a ports tree.
    -d            -- Delete a ports tree.
    -l            -- List all available ports trees.
    -u            -- Update a ports tree.

Options:
    -U url        -- URL where to fetch the ports tree from.
    -B branch     -- Which branch to use for the svn or git methods.  Defaults
                     to 'head/master'.
    -F            -- When used with -c, only create the needed filesystems
                     (for ZFS) and directories, but do not populate them.
    -M path       -- The path to the source of a ports tree.
    -f filesystem -- The name of the filesystem to create for the ports tree.
                     If 'none' then do not create the filesystem.  The default
                     is: 'poudriere/ports/default'.
    -k            -- When used with -d, only unregister the ports tree without
                     removing the files.
    -m method     -- When used with -c, specify the method used to create the
                     ports tree. Possible methods are 'git', 'null', 'portsnap',
                     'svn', 'svn+http', 'svn+https', 'svn+file', or 'svn+ssh'.
                     The default is 'portsnap'.
    -n            -- When used with -l, only print the name of the ports tree
    -p name       -- Specifies the name of the ports tree to work on.  The
                     default is 'default'.
    -q            -- When used with -l, remove the header in the list view.
    -v            -- Show more verbose output.
EOF
	exit 1
}

CREATE=0
FAKE=0
UPDATE=0
DELETE=0
LIST=0
NAMEONLY=0
QUIET=0
VERBOSE=0
KEEP=0
CREATED_FS=0
while getopts "B:cFuU:dklp:qf:nM:m:v" FLAG; do
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
		U)
			SOURCES_URL=${OPTARG}
			;;
		n)
			NAMEONLY=1
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

saved_argv="$@"
shift $((OPTIND-1))
post_getopts

[ ${FAKE} -eq 0 ] && METHOD=${METHOD:-portsnap}
PTNAME=${PTNAME:-default}

[ "${METHOD}" = "none" ] && METHOD=null

if [ -n "${SOURCES_URL}" ]; then
	case "${METHOD}" in
	svn*)
		case "${SOURCES_URL}" in
		http://*) METHOD="svn+http" ;;
		https://*) METHOD="svn+https" ;;
		file://*) METHOD="svn+file" ;;
		svn+ssh://*) METHOD="svn+ssh" ;;
		svn://*) METHOD="svn" ;;
		*) err 1 "Invalid svn url" ;;
		esac
		;;
	git*)
		case "${SOURCES_URL}" in
		ssh://*) METHOD="git+ssh" ;;
		http://*) METHOD="git+http" ;;
		https://*) METHOD="git+https" ;;
		git://*) METHOD="git" ;;
		file:///*) METHOD="git" ;;
		*) err 1 "Invalid git url" ;;
		esac
		;;
	*)
		err 1 "-U only valid with git and svn methods"
	esac
	SVN_FULLURL=${SOURCES_URL}
	GIT_FULLURL=${SOURCES_URL}
else
	case ${METHOD} in
	portsnap);;
	svn+http) proto="http" ;;
	svn+https) proto="https" ;;
	svn+ssh) proto="svn+ssh" ;;
	svn+file) proto="file" ;;
	svn) proto="svn" ;;
	git+https) proto="https" ;;
	git+ssh) proto="ssh" ;;
	git) proto="git";;
	null) ;;
	*) [ ${FAKE} -eq 0 ] && usage ;;
	esac
	SVN_FULLURL=${proto}://${SVN_HOST}/ports
	if [ -n "${GIT_URL}" ]; then
		GIT_FULLURL=${GIT_URL}
	else
		GIT_FULLURL=${proto}://${GIT_PORTSURL}
	fi
fi

case ${METHOD} in
svn*) : ${BRANCH:=head} ;;
git*)  : ${BRANCH:=master} ;;
*)
	[ -n "${BRANCH}" ] && \
	    err 1 "Branch (-B) only supported for SVN and git."
esac

if [ ${LIST} -eq 1 ]; then
	format='%%-%ds %%-%ds %%-%ds %%s\n'
	display_setup "${format}" 4 "-d"
	if [ ${NAMEONLY} -eq 0 ]; then
		display_add "PORTSTREE" "METHOD" "TIMESTAMP" "PATH"
	else
		display_add "PORTSTREE"
	fi
	while read ptname ptmethod ptpath; do
		if [ ${NAMEONLY} -eq 0 ]; then
			_pget timestamp ${ptname} timestamp 2>/dev/null || :
			time=
			[ -n "${timestamp}" ] && \
			    time="$(date -j -r ${timestamp} "+%Y-%m-%d %H:%M:%S")"
			display_add ${ptname} ${ptmethod} "${time}" ${ptpath}
		else
			display_add ${ptname}
		fi
	done <<- EOF
	$(porttree_list)
	EOF
	[ ${QUIET} -eq 1 ] && quiet="-q"
	display_output ${quiet}
else
	[ -z "${PTNAME}" ] && usage
fi

cleanup_new_ports() {
	msg "Error while creating ports tree, cleaning up." >&2
	if [ "${CREATED_FS}" -eq 1 ] && [ "${METHOD}" != "null" ]; then
		TMPFS_ALL=0 destroyfs ${PTMNT} ports || :
	fi
	rm -rf ${POUDRIERED}/ports/${PTNAME} || :
}

check_portsnap_interactive() {
	if /usr/sbin/portsnap --help | grep -q -- '--interactive'; then
		echo "--interactive "
	fi
}

if [ ${CREATE} -eq 1 ]; then
	# test if it already exists
	porttree_exists ${PTNAME} && err 2 "The ports tree, ${PTNAME}, already exists"
	maybe_run_queued "${saved_argv}"
	: ${PTMNT="${BASEFS:=/usr/local${ZROOTFS}}/ports/${PTNAME}"}
	: ${PTFS="${ZPOOL}${ZROOTFS}/ports/${PTNAME}"}

	[ "${PTNAME#*.*}" = "${PTNAME}" ] ||
		err 1 "The ports name cannot contain a period (.). See jail(8)"

	if [ "${METHOD}" = "null" ]; then
		[ -z "${PTMNT}" ] && \
		    err 1 "Must set -M to path of ports tree to use"
		[ "${PTMNT}" = "/" ] && \
		    err 1 "Cannot use / for -M"
		PTFS="none"
		[ ${FAKE} -eq 1 ] && err 1 "Cannot use -F with -m null"
	fi

	[ "${PTFS}" != "none" ] && [ -d "${PTMNT}" ] && \
	    err 1 "Directory ${PTMNT} already exists"

	if [ "${METHOD}" != "null" ]; then
		# This will exit if it fails to zfs create...
		createfs ${PTNAME} ${PTMNT} ${PTFS:-none}
		# Ports runs without -e, but even if it did let's not
		# short-circuit all of -e support in createfs.  It
		# should have exited on error with err(), but be sure.
		if [ $? -eq 0 ]; then
			CREATED_FS=1
		fi
	fi

	# Wrap the ports creation in a special cleanup hook that will remove it
	# if any error is encountered
	CLEANUP_HOOK=cleanup_new_ports

	pset ${PTNAME} mnt ${PTMNT}
	pset ${PTNAME} created_fs ${CREATED_FS}
	if [ $FAKE -eq 0 ]; then
		case ${METHOD} in
		portsnap)
			# additional portsnap arguments
			PTARGS=$(check_portsnap_interactive)
			mkdir ${PTMNT}/.snap
			msg "Extracting portstree \"${PTNAME}\"..."
			/usr/sbin/portsnap ${PTARGS} -d ${PTMNT}/.snap -p ${PTMNT} fetch extract ||
			/usr/sbin/portsnap ${PTARGS} -d ${PTMNT}/.snap -p ${PTMNT} fetch extract ||
			    err 1 " fail"
			;;
		svn*)
			if [ ! -x "${SVN_CMD}" ]; then
				err 1 "svn or svnlite not installed. Perhaps you need to 'pkg install subversion'"
			fi

			msg_n "Checking out the ports tree..."
			[ ${VERBOSE} -gt 0 ] || quiet="-q"
			${SVN_CMD} ${quiet} co \
				${SVN_PRESERVE_TIMESTAMP} \
				${SVN_FULLURL}/${BRANCH} \
				${PTMNT} || err 1 " fail"
			echo " done"
			;;
		git*)
			msg_n "Cloning the ports tree..."
			[ ${VERBOSE} -gt 0 ] || quiet="-q"
			${GIT_CMD} clone --depth=1 --single-branch ${quiet} -b ${BRANCH} ${GIT_FULLURL} ${PTMNT} || err 1 " fail"
			echo " done"
			;;
		esac
		pset ${PTNAME} method ${METHOD}
		pset ${PTNAME} timestamp $(clock -epoch)
	else
		pset ${PTNAME} method ${METHOD:--}
	fi
	if [ "${METHOD}" = "null" ]; then
		msg "Imported ports tree \"${PTNAME}\" from ${PTMNT}"
	fi

	unset CLEANUP_HOOK
fi

if [ ${DELETE} -eq 1 ]; then
	porttree_exists ${PTNAME} || err 2 "No such ports tree ${PTNAME}"
	PTMETHOD=$(pget ${PTNAME} method)
	PTMNT=$(pget ${PTNAME} mnt)
	CREATED_FS=$(pget ${PTNAME} created_fs 2>/dev/null || echo 0)
	[ -d "${PTMNT}/ports" ] && PORTSMNT="${PTMNT}/ports"
	${NULLMOUNT} | /usr/bin/grep -q "${PORTSMNT:-${PTMNT}} on" \
		&& err 1 "Ports tree \"${PTNAME}\" is currently mounted and being used."
	confirm_if_tty "Are you sure you want to delete the ports tree ${PTNAME} at ${PTMNT}?" || \
	    err 1 "Not deleting ports tree"
	maybe_run_queued "${saved_argv}"
	msg_n "Deleting portstree \"${PTNAME}\"..."
	# Regarding -F, older system ports trees will have method=- and
	# created_fs=0 so we never delete them (#250).
	# Newer imports with -F will have method=- and could have
	# created_fs=1 if they did not use -m null.  It is fine to
	# delete in that case (#469)
	if [ ${KEEP} -eq 0 -a "${PTMETHOD}" != "null" -a \
	    "${PTMETHOD}" != "none" ]; then
		can_delete=1

		# Deal with method=-
		[ "${PTMETHOD}" = "-" ] && can_delete=${CREATED_FS}
		if [ ${can_delete} -eq 1 ]; then
			TMPFS_ALL=0 destroyfs ${PTMNT} ports || :
		fi
	fi
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
	maybe_run_queued "${saved_argv}"
	if [ -z "${METHOD}" -o ${METHOD} = "-" ]; then
		METHOD=portsnap
		pset ${PTNAME} method ${METHOD}
	fi
	case ${METHOD} in
	portsnap|"")
		msg_n "Updating portstree \"${PTNAME}\" with ${METHOD}..."
		# additional portsnap arguments
		PTARGS=$(check_portsnap_interactive)
		if [ -d "${PTMNT}/snap" ]; then
			SNAPDIR=${PTMNT}/snap
		else
			SNAPDIR=${PTMNT}/.snap
		fi
		/usr/sbin/portsnap ${PTARGS} -d ${SNAPDIR} -p ${PORTSMNT:-${PTMNT}} ${PSCOMMAND} alfred
		echo " done"
		;;
	svn*)
		msg_n "Updating portstree \"${PTNAME}\" with ${METHOD}..."
		[ ${VERBOSE} -gt 0 ] || quiet="-q"
		${SVN_CMD} upgrade ${PORTSMNT:-${PTMNT}} 2>/dev/null || :
		${SVN_CMD} ${quiet} update \
			${SVN_PRESERVE_TIMESTAMP} \
			${PORTSMNT:-${PTMNT}}
		echo " done"
		;;
	git*)
		msg_n "Updating portstree \"${PTNAME}\" with ${METHOD}..."
		[ ${VERBOSE} -gt 0 ] || quiet="-q"
		${GIT_CMD} -C ${PORTSMNT:-${PTMNT}} pull --rebase ${quiet}
		echo " done"
		;;
	null|none) msg "Not updating portstree \"${PTNAME}\" with method ${METHOD}" ;;
	*)
		err 1 "Undefined upgrade method"
		;;
	esac

	pset ${PTNAME} timestamp $(clock -epoch)
fi
