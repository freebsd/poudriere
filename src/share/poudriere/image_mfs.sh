#!/bin/sh

#
# Copyright (c) 2015 Baptiste Daroussin <bapt@FreeBSD.org>
# All rights reserved.
# Copyright (c) 2021 Emmanuel Vadot <manu@FreeBSD.org>
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

_mfs_create()
{

	cat >> ${WRKDIR}/world/etc/fstab <<-EOF
	/dev/ufs/${IMAGENAME} / ufs rw 0 0
	tmpfs /tmp tmpfs rw,mode=1777 0 0
	EOF
	makefs -B little ${IMAGESIZE:+-s ${IMAGESIZE}} -o label=${IMAGENAME} ${WRKDIR}/out/mfsroot ${WRKDIR}/world
}

_zmfs_create()
{

	_mfs_create
	if command -v pigz >/dev/null; then
		GZCMD=pigz
	fi
	${GZCMD:-gzip} -9 ${WRKDIR}/out/mfsroot
}

_mfs_configure_boot()
{

	MFSROOTSIZE=$(ls -l ${WRKDIR}/out/mfsroot* | head -n 1 | awk '{print $5}')
	if [ ${MFSROOTSIZE} -ge 268435456 ]; then
		echo "WARNING: MFSROOT too large, boot failure likely"
	fi
	do_clone -r ${WRKDIR}/world/boot ${WRKDIR}/out/boot
	cat >> ${WRKDIR}/out/boot/loader.conf <<-EOF
	tmpfs_load="YES"
	mfs_load="YES"
	mfs_type="mfs_root"
	mfs_name="/mfsroot"
	vfs.root.mountfrom="ufs:/dev/ufs/${IMAGENAME}"
	EOF
}

mfs_build()
{

	_mfs_create
	_mfs_configure_boot
}

zmfs_build()
{

	_zmfs_create
	echo "_zmfs_create done"
	_mfs_configure_boot
	echo "zmfs_build done"
}
