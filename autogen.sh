#!/bin/sh

if ! autoreconf -if -Wall; then
	echo "autogen.sh failed" >&2
	exit 1
fi

# Fix wrong signal handling
patch -p0 <<'EOF'
diff --git build-aux/test-driver build-aux/test-driver
index be73b80ad..52695a1d1 100755
--- build-aux/test-driver
+++ build-aux/test-driver
@@ -99,7 +99,7 @@ else
   red= grn= lgn= blu= mgn= std=
 fi
 
-do_exit='rm -f $log_file $trs_file; (exit $st); exit $st'
+do_exit='rm -f $log_file $trs_file; trap - $((st - 128)); kill -$((st - 128)) $$'
 trap "st=129; $do_exit" 1
 trap "st=130; $do_exit" 2
 trap "st=141; $do_exit" 13
EOF
