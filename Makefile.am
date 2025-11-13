CLEANFILES=	$(dist_rc_SCRIPTS)
MOSTLYCLEANFILES=
noinst_PROGRAMS=

.ALLSRC	?= $^

ACLOCAL_AMFLAGS=	-I m4
AM_CFLAGS=	-Wall -pipe -O2 @AM_CFLAGS@
if MAINTAINER_MODE
AM_CFLAGS+=	-Wextra -Werror
endif
if ADDRESS_SANITIZER
ASAN_CFLAGS=	-fsanitize=address -DADDRESS_SANITIZER -fno-omit-frame-pointer -O1
UBSAN_CFLAGS=	-fsanitize=undefined -fno-sanitize-recover=undefined
endif
SAN_CFLAGS=	$(ASAN_CFLAGS) $(UBSAN_CFLAGS)

awkdir=	$(pkgdatadir)/awk
htmldir= $(pkgdatadir)/html
shincludedir= $(pkgdatadir)/include
assetsdir= $(htmldir)/assets
bootstrapdir= $(assetsdir)/bootstrap-5.3.2
btcssdir= $(bootstrapdir)/css
btjsdir= $(bootstrapdir)/js
datatablesdir= $(assetsdir)/DataTables-1.13.8
dtcssdir= $(datatablesdir)/css
dtimagesdir= $(datatablesdir)/images
dtjsdir= $(datatablesdir)/js
jquerydir= $(assetsdir)/jquery-3.7.1
rcdir= $(sysconfdir)/rc.d
hookdir= $(sysconfdir)/poudriere.d/hooks
examplesdir= $(datadir)/examples/$(PACKAGE_NAME)

EXTRA_DIST=	\
		src/bin/poudriere.in \
		test-ports/

dist_bin_SCRIPTS=	poudriere

dist_man_MANS=	src/man/poudriere.8 \
		src/man/poudriere-audit.8 \
		src/man/poudriere-bulk.8 \
		src/man/poudriere-distclean.8 \
		src/man/poudriere-image.8 \
		src/man/poudriere-jail.8 \
		src/man/poudriere-logclean.8 \
		src/man/poudriere-options.8 \
		src/man/poudriere-pkgclean.8 \
		src/man/poudriere-ports.8 \
		src/man/poudriere-queue.8 \
		src/man/poudriere-repo.8 \
		src/man/poudriere-status.8 \
		src/man/poudriere-testport.8 \
		src/man/poudriere-version.8

dist_sysconf_DATA=	\
		src/etc/poudriere.conf.sample \
		src/etc/poudriered.conf.sample
dist_examples_DATA=	\
		src/share/examples/poudriere/Caddyfile.sample \
		src/share/examples/poudriere/nginx.conf.sample \
		src/share/examples/poudriere/httpd.conf.sample

dist_hook_DATA=	src/etc/poudriere.d/hooks/bulk.sh.sample \
		src/etc/poudriere.d/hooks/pkgbuild.sh.sample

dist_pkgdata_DATA=	\
			src/share/poudriere/api.sh \
			src/share/poudriere/audit.sh \
			src/share/poudriere/bulk.sh \
			src/share/poudriere/common.sh \
			src/share/poudriere/daemon.sh \
			src/share/poudriere/distclean.sh \
			src/share/poudriere/foreachport.sh \
			src/share/poudriere/image.sh \
			src/share/poudriere/image_dump.sh \
			src/share/poudriere/image_firmware.sh \
			src/share/poudriere/image_hybridiso.sh \
			src/share/poudriere/image_iso.sh \
			src/share/poudriere/image_mfs.sh \
			src/share/poudriere/image_rawdisk.sh \
			src/share/poudriere/image_tar.sh \
			src/share/poudriere/image_usb.sh \
			src/share/poudriere/image_zfs.sh \
			src/share/poudriere/image_zsnapshot.sh \
			src/share/poudriere/jail.sh \
			src/share/poudriere/logclean.sh \
			src/share/poudriere/options.sh \
			src/share/poudriere/pkgclean.sh \
			src/share/poudriere/ports.sh \
			src/share/poudriere/processonelog.sh \
			src/share/poudriere/queue.sh \
			src/share/poudriere/repo.sh \
			src/share/poudriere/status.sh \
			src/share/poudriere/testport.sh

dist_shinclude_DATA= \
			src/share/poudriere/include/asserts.sh \
			src/share/poudriere/include/cache.sh \
			src/share/poudriere/include/colors.sh \
			src/share/poudriere/include/colors.pre.sh \
			src/share/poudriere/include/common.sh.dragonfly \
			src/share/poudriere/include/common.sh.freebsd \
			src/share/poudriere/include/display.sh \
			src/share/poudriere/include/html.sh \
			src/share/poudriere/include/hash.sh \
			src/share/poudriere/include/fs.sh \
			src/share/poudriere/include/parallel.sh \
			src/share/poudriere/include/pkg.sh \
			src/share/poudriere/include/pkgqueue.sh \
			src/share/poudriere/include/shared_hash.sh \
			src/share/poudriere/include/util.sh

dist_awk_DATA= src/share/poudriere/awk/dependency_loop.awk \
		src/share/poudriere/awk/humanize.awk \
		src/share/poudriere/awk/file_cmp_reg.awk \
		src/share/poudriere/awk/git_dirty.awk \
		src/share/poudriere/awk/json.awk \
		src/share/poudriere/awk/json_jail.awk \
		src/share/poudriere/awk/json_top.awk \
		src/share/poudriere/awk/parse_MOVED.awk \
		src/share/poudriere/awk/processonelog.awk \
		src/share/poudriere/awk/processonelog2.awk \
		src/share/poudriere/awk/siginfo_buildtime.awk \
		src/share/poudriere/awk/unique_pkgnames_from_flavored_origins.awk

dist_html_DATA= 	src/share/poudriere/html/build.html \
			src/share/poudriere/html/index.html \
			src/share/poudriere/html/jail.html \
			src/share/poudriere/html/robots.txt
dist_assets_DATA=	src/share/poudriere/html/assets/poudriere.js \
			src/share/poudriere/html/assets/logo-light.png \
			src/share/poudriere/html/assets/logo-dark.png \
			src/share/poudriere/html/assets/favicon.png \
			src/share/poudriere/html/assets/jquery.dataTables.rowGrouping-1.2.9.js
dist_btjs_DATA=		src/share/poudriere/html/assets/bootstrap-5.3.2/js/bootstrap.bundle.min.js
dist_btcss_DATA=	src/share/poudriere/html/assets/bootstrap-5.3.2/css/bootstrap.min.css
dist_dtcss_DATA=	src/share/poudriere/html/assets/DataTables-1.13.8/css/dataTables.bootstrap5.min.css
dist_dtjs_DATA=		src/share/poudriere/html/assets/DataTables-1.13.8/js/jquery.dataTables.min.js \
			src/share/poudriere/html/assets/DataTables-1.13.8/js/dataTables.bootstrap5.min.js
dist_dtimages_DATA=	src/share/poudriere/html/assets/DataTables-1.13.8/images/sort_asc.png \
			src/share/poudriere/html/assets/DataTables-1.13.8/images/sort_asc_disabled.png \
			src/share/poudriere/html/assets/DataTables-1.13.8/images/sort_both.png \
			src/share/poudriere/html/assets/DataTables-1.13.8/images/sort_desc.png \
			src/share/poudriere/html/assets/DataTables-1.13.8/images/sort_desc_disabled.png
dist_jquery_DATA=	src/share/poudriere/html/assets/jquery-3.7.1/jquery-3.7.1.js \
			src/share/poudriere/html/assets/jquery-3.7.1/jquery-3.7.1.min.js \
			src/share/poudriere/html/assets/jquery-3.7.1/jquery-3.7.1.min.map

dist_rc_SCRIPTS=	src/etc/rc.d/poudriered

pkglibexec_PROGRAMS= \
		     clock \
		     cpdup \
		     dirempty \
		     dirwatch \
		     getpid \
		     locked_mkdir \
		     lockf \
		     nc \
		     poudriered \
		     ptsort \
		     pwait \
		     rename \
		     @USE_RM@ \
		     setsid \
		     timeout \
		     timestamp \
		     @BUILD_SH@
EXTRA_PROGRAMS= \
		rm \
		sh

noinst_LTLIBRARIES=	libucl.la libptsort.la
CLEANFILES+=		libucl.a libptsort.a

AUTOMAKE_OPTIONS=	subdir-objects

clock_SOURCES=	src/libexec/poudriere/clock/clock.c
cpdup_SOURCES=	external/cpdup/src/cpdup.c \
		external/cpdup/src/cpdup.h \
		external/cpdup/src/hclink.c \
		external/cpdup/src/hclink.h \
		external/cpdup/src/hcproto.c \
		external/cpdup/src/hcproto.h \
		external/cpdup/src/md5.c \
		external/cpdup/src/misc.c
cpdup_LDADD=	-lcrypto
cpdup_CFLAGS=	$(AM_CFLAGS) -D_ST_FLAGS_PRESENT_=1 -Wno-deprecated-declarations
dirempty_SOURCES=	src/libexec/poudriere/dirempty/dirempty.c
dirwatch_SOURCES=	src/libexec/poudriere/dirwatch/dirwatch.c
getpid_SOURCES=		src/libexec/poudriere/getpid/getpid.c
getpid_CFLAGS=		--static
locked_mkdir_SOURCES=	src/libexec/poudriere/locked_mkdir/locked_mkdir.c
locked_mkdir_CFLAGS=	$(AM_CFLAGS) $(SAN_CFLAGS)
lockf_SOURCES=		external/freebsd/usr.bin/lockf/lockf.c
nc_SOURCES=		src/libexec/poudriere/nc/nc.c
pwait_SOURCES=		external/freebsd/bin/pwait/pwait.c
rename_SOURCES=		src/libexec/poudriere/rename/rename.c
rm_SOURCES=		external/freebsd/bin/rm/rm.c
setsid_SOURCES=		external/setsid/setsid.c \
			external/setsid/c.h
setsid_CFLAGS=		$(AM_CFLAGS) -DHAVE_ERR_H -DHAVE_NANOSLEEP
timeout_SOURCES=	external/freebsd/bin/timeout/timeout.c
timestamp_SOURCES=	src/libexec/poudriere/timestamp/timestamp.c
timestamp_CFLAGS=	$(AM_CFLAGS) $(SAN_CFLAGS)
timestamp_LDADD=	-lpthread

sh_CFLAGS=		$(AM_CFLAGS) -Wno-extra \
			-DSHELL -std=gnu99 -DVTABSIZE=1000 ${sh_hist_CFLAGS} \
			-Wno-unused-const-variable \
			-include $(top_srcdir)/external/sh_compat/compat.h \
			-I$(top_srcdir)/src \
			-I$(top_srcdir)/external/sh
sh_CFLAGS+=		$(SAN_CFLAGS)
sh_LDADD=		${sh_hist_LDADD} -lsbuf
if MAINTAINER_MODE
sh_hist_LDADD=		-ledit
sh_hist_CFLAGS=		-Wno-pointer-sign
else
sh_hist_CFLAGS=		-DNO_HISTORY
endif
include $(top_srcdir)/external/sh/Makefile.sources
# Extra builtins
CLEANFILES+=		\
			src/poudriere-sh/builtins.c \
			src/poudriere-sh/builtins.def \
			src/poudriere-sh/builtins.h \
			src/poudriere-sh/shell.h
sh_SOURCES+=		\
			src/poudriere-sh/alarm.c \
			src/poudriere-sh/builtins-poudriere.def \
			src/poudriere-sh/helpers.c \
			src/poudriere-sh/helpers.h \
			src/poudriere-sh/mapfile.c \
			src/poudriere-sh/traps.c
# external builtins
sh_SOURCES+=		external/freebsd/bin/chmod/chmod.c
sh_SOURCES+=		$(clock_SOURCES)
sh_SOURCES+=		$(dirempty_SOURCES)
sh_SOURCES+=		$(dirwatch_SOURCES)
sh_SOURCES+=		$(locked_mkdir_SOURCES)
sh_SOURCES+=		external/freebsd/bin/mkdir/mkdir.c
sh_SOURCES+=		external/freebsd/usr.bin/mkfifo/mkfifo.c
sh_SOURCES+=		external/freebsd/usr.bin/mktemp/mktemp.c
sh_SOURCES+=		$(pwait_SOURCES)
sh_SOURCES+=		external/freebsd/bin/realpath/realpath.c
sh_SOURCES+=		$(rename_SOURCES)
sh_SOURCES+=		$(rm_SOURCES)
sh_SOURCES+=		external/freebsd/bin/rmdir/rmdir.c
sh_SOURCES+=		src/poudriere-sh/setproctitle.c
sh_SOURCES+=		external/freebsd/bin/sleep/sleep.c
sh_SOURCES+=		external/freebsd/usr.bin/stat/stat.c
sh_SOURCES+=		external/freebsd/usr.bin/touch/touch.c
sh_SOURCES+=		src/poudriere-sh/unlink.c
sh_SOURCES+=		external/freebsd/usr.bin/wc/wc.c
noinst_PROGRAMS+=	external/sh/mknodes
external_sh_mknodes_SOURCES= external/sh/mknodes.c
external/sh/nodes.c: external/sh/mknodes \
    $(abs_top_srcdir)/external/sh/nodetypes \
    $(abs_top_srcdir)/external/sh/nodes.c.pat
	$(AM_V_GEN)cd external/sh && \
	    $(abs_top_builddir)/external/sh/mknodes \
	    $(abs_top_srcdir)/external/sh/nodetypes \
	    $(abs_top_srcdir)/external/sh/nodes.c.pat
external/sh/nodes.h: external/sh/nodes.c
EXTRA_DIST+=	\
		external/sh/nodetypes \
		external/sh/nodes.c.pat
CLEANFILES+=	\
		external/sh/nodes.c \
		external/sh/nodes.h
$(sh_OBJECTS):	external/sh/nodes.h

external_sh_mksyntax_SOURCES= external/sh/mksyntax.c
noinst_PROGRAMS+=	external/sh/mksyntax
external/sh/syntax.c: external/sh/mksyntax
	$(AM_V_GEN)cd external/sh && \
	    $(abs_top_builddir)/external/sh/mksyntax
external/sh/syntax.h: external/sh/syntax.c
CLEANFILES+=	\
		external/sh/syntax.c \
		external/sh/syntax.h
$(sh_OBJECTS):	external/sh/syntax.h

external/sh/token.h: $(abs_top_srcdir)/external/sh/mktokens
	$(AM_V_GEN)cd external/sh && \
	    sh $(abs_top_srcdir)/external/sh/mktokens
CLEANFILES+=	external/sh/token.h
EXTRA_DIST+=	external/sh/mktokens
external/sh/sh-parser.$(OBJEXT):	external/sh/token.h

sh_CFLAGS+=		-I$(top_srcdir)/src/poudriere-sh \
			-I$(top_builddir)/src/poudriere-sh
src/poudriere-sh/builtins.def: external/sh/builtins.def \
    src/poudriere-sh/builtins-poudriere.def
	$(AM_V_GEN)cat ${.ALLSRC} > $@
src/poudriere-sh/shell.h:
	@ln -fs $(abs_top_srcdir)/external/sh/shell.h $@
src/poudriere-sh/builtins.h: src/poudriere-sh/builtins.def \
      src/poudriere-sh/shell.h \
      $(abs_top_srcdir)/external/sh/mkbuiltins
	$(AM_V_GEN)cd src/poudriere-sh && \
	    sh $(abs_top_srcdir)/external/sh/mkbuiltins .
src/poudriere-sh/builtins.c: src/poudriere-sh/builtins.h
sh_SOURCES+=		src/poudriere-sh/builtins.c
${sh_OBJECTS}:		src/poudriere-sh/builtins.h

libucl_la_SOURCES=	\
			external/libucl/include/lua_ucl.h \
			external/libucl/include/ucl++.h \
			external/libucl/include/ucl.h \
			external/libucl/klib/khash.h \
			external/libucl/klib/kvec.h \
			external/libucl/src/mum.h \
			external/libucl/src/tree.h \
			external/libucl/src/ucl_chartable.h \
			external/libucl/src/ucl_emitter.c \
			external/libucl/src/ucl_emitter_streamline.c \
			external/libucl/src/ucl_emitter_utils.c \
			external/libucl/src/ucl_hash.c \
			external/libucl/src/ucl_hash.h \
			external/libucl/src/ucl_internal.h \
			external/libucl/src/ucl_msgpack.c \
			external/libucl/src/ucl_parser.c \
			external/libucl/src/ucl_schema.c \
			external/libucl/src/ucl_sexp.c \
			external/libucl/src/ucl_util.c \
			external/libucl/uthash/uthash.h \
			external/libucl/uthash/utlist.h \
			external/libucl/uthash/utstring.h

libucl_la_CFLAGS=	$(AM_CFLAGS) -Wno-extra \
			-I$(top_srcdir)/external/libucl/uthash \
			-I$(top_srcdir)/external/libucl/klib  \
			-I$(top_srcdir)/external/libucl/include  \
			-I$(top_srcdir)/external/libucl/src \
			-Wno-unused-parameter -Wno-pointer-sign \
			-Wno-unused-function

libptsort_la_SOURCES=	external/ptsort/lib/aa_tree.c \
			external/ptsort/lib/aa_tree.h \
			external/ptsort/lib/fline.c \
			external/ptsort/lib/fline.h

libptsort_la_CPPFLAGS=	-I$(top_srcdir)/external/ptsort/lib
ptsort_SOURCES=		external/ptsort/bin/ptsort.c
ptsort_LDADD=		libptsort.la
ptsort_CPPFLAGS=	-I$(top_srcdir)/external/ptsort/lib

poudriered_SOURCES=	src/poudriered/poudriered.c \
			external/pkg/xstring.h \
			external/pkg/xmalloc.h
poudriered_CFLAGS=	$(AM_CFLAGS) \
			$(SAN_CFLAGS) \
			-DPREFIX=\"$(prefix)\" \
			-I$(top_srcdir)/external/libucl/include \
			-I$(top_srcdir)/external/pkg
poudriered_LDADD=	libucl.la \
			-lutil

DEVEL_SFX=	-devel

.PHONY:	gen-make-wiki
gen-man-wiki:
	@if [ ! -e wiki/poudriere.8.md ]; then \
	  echo "You must clone https://github.com/freebsd/poudriere.wiki.git to wiki/"; \
	  exit 1; \
	fi
	@if ! which mandoc 2>&1 >/dev/null; then \
	  echo "Mandoc required, install textproc/mdocml"; \
	  exit 1; \
	fi
	@for man in $(dist_man_MANS); do \
	  echo "MANDOC wiki/$${man##*/}${DEVEL_SFX}.md"; \
	  ( \
	    echo "### This page is auto-generated from $${man}"; \
	    (mandoc -Thtml -O man=%N.%S${DEVEL_SFX} $${man} | awk \
	    '$$1 == "<body>" { seenbody=1; next; }; \
	     $$1 == "</body>" { seenbody=0; }; \
	     seenbody == 1 { print };'\
	    ); \
	  ) > wiki/$${man##*/}${DEVEL_SFX}.md; \
	done

MOSTLYCLEANFILES+=	poudriere
.PHONY: poudriere
poudriere: src/bin/poudriere.in
	$(AM_V_GEN)if test -e $(top_srcdir)/.git && \
	    which git >/dev/null 2>&1 && \
	    [ -d "$$(git -C "$(top_srcdir)" rev-parse --git-dir)" ]; then \
	    gitver=$$(git -C "$(top_srcdir)" describe --always --tags HEAD); \
	    sed \
	      -e "s,^\(POUDRIERE_VERSION\)=.*,\1='$${gitver}'," \
	      -e "s,^\(USE_DEBUG\)=.*,\1='@USE_DEBUG@'," \
	      ${.ALLSRC} > $@.tmp && mv -f $@.tmp $@; \
	else \
	    cp -f ${.ALLSRC} $@; \
	fi; \
	chmod +x $@

SUBDIRS= . test

checkquick:
	$(MAKE) $(AM_MAKEFLAGS) check TESTS_SKIP_BUILD=1 TESTS_SKIP_LONG=1

distcheckquick:
	$(MAKE) $(AM_MAKEFLAGS) distcheck TESTS_SKIP_BUILD=1 TESTS_SKIP_LONG=1

checkdryrun:
	$(MAKE) $(AM_MAKEFLAGS) check TESTS_SKIP_BUILD=1 TESTS_SKIP_LONG=1

distcheckdryrun:
	$(MAKE) $(AM_MAKEFLAGS) distcheck TESTS_SKIP_BUILD=1 TESTS_SKIP_LONG=1

installcheck-local:
	$(MAKE) $(AM_MAKEFLAGS) check am_installcheck=1

# Rebuild if configure options change
$(SOURCES):		src/config.h

SH ?= $(BUILD_SH)
