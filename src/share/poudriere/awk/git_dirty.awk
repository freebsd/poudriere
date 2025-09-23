# Copyright (c) 2025 Bryan Drewery <bdrewery@FreeBSD.org>
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

# git status --ignored --porcelain | awk
function get_dir(path) {
        n = split(path, a, "/");
        if (n < 3)
                return "."
        return a[1] "/" a[2]
}

function set_dirty_dir(dir, path) {
        if (DEBUG) {
                dirty_dirs[dir] = path
        } else {
                dirty_dirs[dir] = 1
        }
}

/(\.sw[p-z]|\.orig|\.rej|~|,v)$/ { next }
$1 ~ "[MTADRCU]" {
        # Modified
        dir = get_dir($2)
        set_dirty_dir(dir, $2)
        next
}
$1 == "??" || $1 == "!!" {
        # Unknown
        unknown = 1
}
unknown && /\/work\// { next }
unknown {
        dir = get_dir($2)
        if (dir == ".") {
                # Top-level / Framework
                top_dir = 1
        } else {
                # Port
                port_dir = 1
        }
}
unknown && top_dir && /Makefile\.local/ {
        set_dirty_dir(dir, $2)
        next
}
unknown && port_dir && /\/files\/|Makefile\.local/ {
        set_dirty_dir(dir, $2)
        # Always set top dirty if a port is dirty
        set_dirty_dir(".", $2)
        next
}
END {
        # Print out all dirty port dirs (Use . for top-level)
        for (dir in dirty_dirs) {
                if (DEBUG) {
                        print(dir " " dirty_dirs[dir])
                } else {
                        print(dir)
                }
        }
}
