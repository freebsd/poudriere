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

dump_check()
{

	[ -n "${IMAGESIZE}" ] || err 1 "Please specify the imagesize"
}

dump_prepare()
{

	truncate -s ${IMAGESIZE} ${WRKDIR}/raw.img
	md=$(/sbin/mdconfig ${WRKDIR}/raw.img)
	newfs -j -L ${IMAGENAME} /dev/${md}
	mount /dev/${md} ${WRKDIR}/world
}

dump_build()
{

	cat >> ${WRKDIR}/world/etc/fstab <<-EOF
	/dev/ufs/${IMAGENAME} / ufs rw 1 1
	EOF
}

dump_generate()
{

	FINALIMAGE=${IMAGENAME}.dump
	umount ${WRKDIR}/world
	dump -0Raf ${WRKDIR}/raw.dump /dev/${md}
	/sbin/mdconfig -d -u ${md#md}
	md=
	mv ${WRKDIR}/raw.dump "${OUTPUTDIR}/${FINALIMAGE}"
}
