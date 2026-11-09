#!/bin/sh

if ! autoreconf -if -Wall; then
	echo "autogen.sh failed" >&2
	exit 1
fi

# Fix wrong signal handling
patch -p0 <<'EOF'
--- build-aux/test-driver.orig	2026-11-09 15:15:44.039521000 -0800
+++ build-aux/test-driver	2026-11-09 15:18:51.379987000 -0800
@@ -106,7 +106,7 @@ fi
   red= grn= lgn= blu= mgn= std=
 fi
 
-do_exit='rm -f "$log_file" "$trs_file"; (exit $st); exit $st'
+do_exit='rm -f "$log_file" "$trs_file"; trap - $((st - 128)); kill -$((st - 128)) $$'
 trap "st=129; $do_exit" 1
 trap "st=130; $do_exit" 2
 trap "st=141; $do_exit" 13
EOF
