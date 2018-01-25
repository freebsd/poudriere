# Copyright (c) 2018 Bryan Drewery <bdrewery@FreeBSD.org>
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

function update_forwards(src, ref) {
	dst = forward[ref]
	if (src in backrefs) {
		#printf("--- SREF %s backrefs: %s\n", src, backrefs[src])
		n = split(backrefs[src], a, " ")
		for (i in a) {
			pref = a[i]
			forward[pref] = dst
			if (dst == "")
				reason[pref] = reason[ref]
		}
	}
	if (dst == "")
		return
	# Add my ref into the list of backrefs for the dst name
	if (dst in backrefs)
		backrefs[dst] = backrefs[dst] " " ref
	else
		backrefs[dst] = ref
	if (src in backrefs) {
		#printf("--- ?REF %s backrefs: %s\n", src, backrefs[src])
		# Nothing refers to me by name anymore.
		backrefs[dst] = backrefs[dst] " " backrefs[src]
		delete backrefs[src]
	}
	#printf("--- DREF %s backrefs: %s\n", dst, backrefs[dst])
}

BEGIN {
	FS="|"
}

/^#/ { next }

{
	src = $1
	dst = $2
	ref = NR
	if (src in srcs) {
		{ printf("MOVED error: %s has duplicate entries\n", src) > "/dev/stderr" }
		next
	}
	refname[ref] = src
	forward[ref] = dst
	srcs[src] = ref
	if (dst == "")
		reason[ref] = $3 " " $4
	#printf("READ %s %s -> %s\n", src, ref, dst)

	# Update fowards to me to now point to my dst and
	# update my own backrefs
	update_forwards(src, ref)
}

END {
	for (ref in forward) {
		src = refname[ref]
		dst = forward[ref]
		if (dst != "")
			printf("%s %s\n", src, dst)
		else
			printf("%s EXPIRED %s\n", src, reason[ref])
	}
}

# vim: set sts=8 sw=8 ts=8 noet:
