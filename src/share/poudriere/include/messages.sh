#!/bin/sh
# 
# Copyright (c) 2010-2013 Baptiste Daroussin <bapt@FreeBSD.org>
# Copyright (c) 2012-2014 Bryan Drewery <bdrewery@FreeBSD.org>
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

msg_n() {
	local now elapsed

	now=$(date +%s)
	elapsed="$(date -j -u -r $((${now} - ${TIME_START})) "+${DURATION_FORMAT}")"
	echo -n "[${elapsed}] ${DRY_MODE}====>> $1";
}
msg() { msg_n "$@"; echo; }
msg_verbose() {
	[ ${VERBOSE} -gt 0 ] || return 0
	msg "$1"
}

msg_debug() {
	[ ${VERBOSE} -gt 1 ] || return 0
	msg "DEBUG: $1" >&2
}

warn() {
	msg "WARNING: $@" >&2
}

job_msg() {
	local now elapsed

	if [ -n "${MY_JOBID}" ]; then
		now=$(date +%s)
		elapsed="$(date -j -u -r $((${now} - ${TIME_START_JOB})) "+${DURATION_FORMAT}")"
		msg "[${MY_JOBID}][${elapsed}] $1" >&5
	else
		msg "$1"
	fi
}

job_msg_verbose() {
	[ ${VERBOSE} -gt 0 ] || return 0
	job_msg "$@"
}
