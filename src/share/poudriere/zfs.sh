#!/bin/sh
#-
# Copyright (c) 2020 Klara Inc
# Copyright (c) 2013-2016 Allan Jude
# Copyright (c) 2013-2018 Devin Teske
# All rights reserved.
#
# Portions of this software were developed by Edward Tomasz Napierala
# under sponsorship from Klara Inc.
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
#
# $FreeBSD$
#

#
# Please keep in sync with release/tools/zfs.conf.
#

: ${ZFSBOOT_POOL_NAME:=zroot}
: ${ZFSBOOT_BEROOT_NAME:=ROOT}
: ${ZFSBOOT_BOOTFS_NAME:=default}

# Stolen from bsdconfig
# str_replaceall $string $find $replace [$var_to_set]
#
# Replace all occurrences of $find in $string with $replace. If $var_to_set is
# either missing or NULL, the variable name is produced on standard out for
# capturing in a sub-shell (which is less recommended due to performance
# degradation).
#
str_replaceall()
{
	local __left="" __right="$1"
	local __find="$2" __replace="$3" __var_to_set="$4"
	while :; do
		case "$__right" in *$__find*)
			__left="$__left${__right%%$__find*}$__replace"
			__right="${__right#*$__find}"
			continue
		esac
		break
	done
	__left="$__left${__right#*$__find}"
	if [ "$__var_to_set" ]; then
		setvar "$__var_to_set" "$__left"
	else
		echo "$__left"
	fi
}

create_zfs_be_datasets() {
	local OPT OPTSTR

	: ${ZFSBOOT_DATASETS:="
		# DATASET	OPTIONS (space separated)

		# Boot Environment [BE] root and default boot dataset
		/$ZFSBOOT_BEROOT_NAME				mountpoint=none
		/$ZFSBOOT_BEROOT_NAME/$ZFSBOOT_BOOTFS_NAME	mountpoint=/

		# Compress /tmp, allow exec but not setuid
		/tmp		mountpoint=/tmp exec=on setuid=off

		# Don't mount /usr so that 'base' files go to the BEROOT
		/usr		mountpoint=/usr canmount=off

		# Home directories separated so they are common to all BEs
		/usr/home	# NB: /home is a symlink to /usr/home

		# Ports tree
		/usr/ports	setuid=off

		# Source tree (compressed)
		/usr/src

		# Create /var and friends
		/var		mountpoint=/var canmount=off
		/var/audit	exec=off setuid=off
		/var/crash	exec=off setuid=off
		/var/log	exec=off setuid=off
		/var/mail	atime=on
		/var/tmp	setuid=off
	"}

	echo "$ZFSBOOT_DATASETS" | while read dataset options; do
		# Skip blank lines and comments
		case "$dataset" in "#"*|"") continue; esac
		# Remove potential inline comments in options
		options="${options%%#*}"
		# Replace tabs with spaces
		str_replaceall "$options" "	" " " options
		# Reduce contiguous runs of space to one single space
		oldoptions=
		while [ "$oldoptions" != "$options" ]; do
			oldoptions="$options"
			str_replaceall "$options" "  " " " options
		done
		# Replace both commas and spaces with ` -o '
		str_replaceall "$options" "[ ,]" " -o " options
		# Create the dataset with desired options
		zfs create ${options:+-o $options} "${ZFSBOOT_POOL_NAME}$dataset" ||
		    err 1 "Dataset creation failed"
	done
}

