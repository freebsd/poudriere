#!/bin/sh
# 
# Copyright (c) 2014 Bryan Drewery <bdrewery@FreeBSD.org>
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

display_setup() {
	[ $# -ge 2 ] || eargs display_setup format columns [column_sort]
	_DISPLAY_DATA=
	_DISPLAY_FORMAT="$1"
	_DISPLAY_COLUMNS="$2"
	_DISPLAY_COLUMN_SORT="$3"
}

display_add() {
	if [ -z "${_DISPLAY_DATA}" ]; then
		_DISPLAY_DATA="$@"
	else
		_DISPLAY_DATA="${_DISPLAY_DATA}
$@"
	fi
}

display_output() {
	local cnt lengths format

	format="${_DISPLAY_FORMAT}"

	# Determine optimal format
	while read line; do
		cnt=0
		for word in ${line}; do
			hash_get lengths ${cnt} max_length || max_length=0
			if [ ${#word} -gt ${max_length} ]; then
				hash_set lengths ${cnt} ${#word}
			fi
			cnt=$((${cnt} + 1))
		done
	done <<-EOF
	${_DISPLAY_DATA}
	EOF

	# Set format lengths
	lengths=
	for n in $(jot $((${_DISPLAY_COLUMNS} - 1)) 0); do
		hash_get lengths ${n} length
		lengths="${lengths} ${length}"
	done
	format=$(printf "${format}" ${lengths})

	# Show header separately so it is not sorted
	echo "${_DISPLAY_DATA}"| head -n 1| while read line; do
		printf "${format}\n" ${line}
	done

	# Sort by SET,PTNAME,JAIL,BUILD
	echo "${_DISPLAY_DATA}" | tail -n +2 | \
	    sort ${_DISPLAY_COLUMN_SORT} | while read line; do
		printf "${format}\n" ${line}
	done

	unset _DISPLAY_DATA _DISPLAY_FORMAT _DISPLAY_COLUMNS \
	    _DISPLAY_COLUMN_SORT
}
