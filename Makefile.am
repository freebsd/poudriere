CLEANFILES=	$(dist_rc_SCRIPTS)
MOSTLYCLEANFILES=

ACLOCAL_AMFLAGS=	-I m4
AM_CFLAGS=	-Wall -pipe -O2 @AM_CFLAGS@
if MAINTAINER_MODE
AM_CFLAGS+=	-Wextra -Werror
endif

awkdir=	$(pkgdatadir)/awk
htmldir= $(pkgdatadir)/html
includedir= $(pkgdatadir)/include
assetsdir= $(htmldir)/assets
bootstrapdir= $(assetsdir)/bootstrap-3.1.1
btcssdir= $(bootstrapdir)/css
btjsdir= $(bootstrapdir)/js
btfontsdir= $(bootstrapdir)/fonts
datatablesdir= $(assetsdir)/DataTables-1.10.0
dtcssdir= $(datatablesdir)/css
dtimagesdir= $(datatablesdir)/images
dtjsdir= $(datatablesdir)/js
rcdir= $(sysconfdir)/rc.d
hookdir= $(sysconfdir)/poudriere.d/hooks
mandir= $(prefix)/man
examplesdir= $(datadir)/examples/$(PACKAGE_NAME)

EXTRA_DIST=	\
		src/bin/poudriere.in \
		test-ports/

dist_bin_SCRIPTS=	poudriere

dist_man_MANS=	src/bin/poudriere.8 \
		src/bin/poudriere-bulk.8 \
		src/bin/poudriere-distclean.8 \
		src/bin/poudriere-image.8 \
		src/bin/poudriere-jail.8 \
		src/bin/poudriere-logclean.8 \
		src/bin/poudriere-options.8 \
		src/bin/poudriere-pkgclean.8 \
		src/bin/poudriere-ports.8 \
		src/bin/poudriere-queue.8 \
		src/bin/poudriere-status.8 \
		src/bin/poudriere-testport.8 \
		src/bin/poudriere-version.8

dist_sysconf_DATA=	\
		src/etc/poudriere.conf.sample \
		src/etc/poudriered.conf.sample
dist_examples_DATA=	\
		src/share/examples/poudriere/nginx.conf.sample \
		src/share/examples/poudriere/httpd.conf.sample

dist_hook_DATA=	src/etc/poudriere.d/hooks/bulk.sh.sample \
		src/etc/poudriere.d/hooks/pkgbuild.sh.sample

dist_pkgdata_DATA=	\
			src/share/poudriere/api.sh \
			src/share/poudriere/bulk.sh \
			src/share/poudriere/common.sh \
			src/share/poudriere/daemon.sh \
			src/share/poudriere/distclean.sh \
			src/share/poudriere/foreachport.sh \
			src/share/poudriere/image.sh \
			src/share/poudriere/image_dump.sh \
			src/share/poudriere/image_firmware.sh \
			src/share/poudriere/image_iso.sh \
			src/share/poudriere/image_mfs.sh \
			src/share/poudriere/image_rawdisk.sh \
			src/share/poudriere/image_tar.sh \
			src/share/poudriere/image_usb.sh \
			src/share/poudriere/image_zsnapshot.sh \
			src/share/poudriere/jail.sh \
			src/share/poudriere/logclean.sh \
			src/share/poudriere/options.sh \
			src/share/poudriere/pkgclean.sh \
			src/share/poudriere/ports.sh \
			src/share/poudriere/processonelog.sh \
			src/share/poudriere/queue.sh \
			src/share/poudriere/status.sh \
			src/share/poudriere/testport.sh

dist_include_HEADERS= \
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
			src/share/poudriere/include/shared_hash.sh \
			src/share/poudriere/include/util.sh

dist_awk_DATA= src/share/poudriere/awk/dependency_loop.awk \
		src/share/poudriere/awk/humanize.awk \
		src/share/poudriere/awk/json.awk \
		src/share/poudriere/awk/json_jail.awk \
		src/share/poudriere/awk/json_top.awk \
		src/share/poudriere/awk/parse_MOVED.awk \
		src/share/poudriere/awk/processonelog2.awk \
		src/share/poudriere/awk/siginfo_buildtime.awk \
		src/share/poudriere/awk/unique_pkgnames_from_flavored_origins.awk

dist_html_DATA= 	src/share/poudriere/html/build.html \
			src/share/poudriere/html/index.html \
			src/share/poudriere/html/jail.html \
			src/share/poudriere/html/robots.txt
dist_assets_DATA=	src/share/poudriere/html/assets/poudriere.js \
			src/share/poudriere/html/assets/logo.svg \
			src/share/poudriere/html/assets/favicon.ico \
			src/share/poudriere/html/assets/poudriere.css \
			src/share/poudriere/html/assets/jquery-1.11.1.js \
			src/share/poudriere/html/assets/jquery-1.11.1.min.js \
			src/share/poudriere/html/assets/jquery-1.11.1.min.map \
			src/share/poudriere/html/assets/jquery.dataTables.rowGrouping-1.2.9.js
dist_btjs_DATA=		src/share/poudriere/html/assets/bootstrap-3.1.1/js/bootstrap.min.js
dist_btfonts_DATA=	src/share/poudriere/html/assets/bootstrap-3.1.1/fonts/glyphicons-halflings-regular.eot \
			src/share/poudriere/html/assets/bootstrap-3.1.1/fonts/glyphicons-halflings-regular.svg \
			src/share/poudriere/html/assets/bootstrap-3.1.1/fonts/glyphicons-halflings-regular.ttf \
			src/share/poudriere/html/assets/bootstrap-3.1.1/fonts/glyphicons-halflings-regular.woff
dist_btcss_DATA=	src/share/poudriere/html/assets/bootstrap-3.1.1/css/bootstrap-theme.min.css \
			src/share/poudriere/html/assets/bootstrap-3.1.1/css/bootstrap.min.css
dist_dtcss_DATA=	src/share/poudriere/html/assets/DataTables-1.10.0/css/jquery.dataTables.min.css \
			src/share/poudriere/html/assets/DataTables-1.10.0/css/jquery.dataTables_themeroller.min.css
dist_dtjs_DATA=		src/share/poudriere/html/assets/DataTables-1.10.0/js/jquery.dataTables.min.js
dist_dtimages_DATA=	src/share/poudriere/html/assets/DataTables-1.10.0/images/back_disabled.png \
			src/share/poudriere/html/assets/DataTables-1.10.0/images/back_enabled.png \
			src/share/poudriere/html/assets/DataTables-1.10.0/images/back_enabled_hover.png \
			src/share/poudriere/html/assets/DataTables-1.10.0/images/forward_disabled.png \
			src/share/poudriere/html/assets/DataTables-1.10.0/images/forward_enabled.png \
			src/share/poudriere/html/assets/DataTables-1.10.0/images/forward_enabled_hover.png \
			src/share/poudriere/html/assets/DataTables-1.10.0/images/sort_asc.png \
			src/share/poudriere/html/assets/DataTables-1.10.0/images/sort_asc_disabled.png \
			src/share/poudriere/html/assets/DataTables-1.10.0/images/sort_both.png \
			src/share/poudriere/html/assets/DataTables-1.10.0/images/sort_desc.png \
			src/share/poudriere/html/assets/DataTables-1.10.0/images/sort_desc_disabled.png

dist_rc_SCRIPTS=	src/etc/rc.d/poudriered

pkglibexec_PROGRAMS= \
		     cachec \
		     cached \
		     clock \
		     cpdup \
		     dirempty \
		     dirwatch \
		     jexecd \
		     locked_mkdir \
		     nc \
		     poudriered \
		     ptsort \
		     pwait \
		     rename \
		     rexec \
		     @USE_RM@ \
		     timeout \
		     timestamp \
		     @SH@
EXTRA_PROGRAMS= \
		rm \
		sh

noinst_LTLIBRARIES=	libucl.la libnv.la libptsort.la
CLEANFILES+=		libucl.a libnv.a libptsort.a

AUTOMAKE_OPTIONS=	subdir-objects

clock_SOURCES=	src/libexec/poudriere/clock/clock.c
cpdup_SOURCES=	src/libexec/poudriere/cpdup/cpdup.c \
		src/libexec/poudriere/cpdup/compat_sun.h \
		src/libexec/poudriere/cpdup/cpdup.h \
		src/libexec/poudriere/cpdup/fsmid.c \
		src/libexec/poudriere/cpdup/hclink.c \
		src/libexec/poudriere/cpdup/hclink.h \
		src/libexec/poudriere/cpdup/hcproto.c \
		src/libexec/poudriere/cpdup/hcproto.h \
		src/libexec/poudriere/cpdup/md5.c \
		src/libexec/poudriere/cpdup/misc.c
cpdup_LDADD=	-lmd
cpdup_CFLAGS=	$(AM_CFLAGS) -D_ST_FLAGS_PRESENT_=1
dirempty_SOURCES=	src/libexec/poudriere/dirempty/dirempty.c
dirwatch_SOURCES=	src/libexec/poudriere/dirwatch/dirwatch.c
locked_mkdir_SOURCES=	src/libexec/poudriere/locked_mkdir/locked_mkdir.c
nc_SOURCES=		src/libexec/poudriere/nc/nc.c
pwait_SOURCES=		src/libexec/poudriere/pwait/pwait.c
rename_SOURCES=		src/libexec/poudriere/rename/rename.c
rm_SOURCES=		src/libexec/poudriere/rm/rm.c
timeout_SOURCES=	src/libexec/poudriere/timeout/timeout.c
timestamp_SOURCES=	src/libexec/poudriere/timestamp/timestamp.c
timestamp_LDADD=	-lpthread

sh_CFLAGS=		$(AM_CFLAGS) -Wno-extra \
			-DSHELL -std=gnu99 -DVTABSIZE=1000 ${sh_hist_CFLAGS} \
			-Wno-unused-const-variable \
			-include $(top_srcdir)/external/sh_compat/compat.h \
			-I$(top_srcdir)/src \
			-I$(top_srcdir)/external/sh
sh_LDADD=		${sh_hist_LDADD} -lsbuf
if MAINTAINER_MODE
sh_hist_LDADD=		-ledit
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
			src/libexec/poudriere/clock/clock.c \
			src/libexec/poudriere/dirempty/dirempty.c \
			src/libexec/poudriere/locked_mkdir/locked_mkdir.c \
			src/libexec/poudriere/pwait/pwait.c \
			src/libexec/poudriere/rename/rename.c \
			src/libexec/poudriere/rm/rm.c \
			src/poudriere-sh/builtins-poudriere.def \
			src/poudriere-sh/helpers.c \
			src/poudriere-sh/helpers.h \
			src/poudriere-sh/mapfile.c \
			src/poudriere-sh/mkdir.c \
			src/poudriere-sh/mkfifo.c \
			src/poudriere-sh/mktemp.c \
			src/poudriere-sh/realpath.c \
			src/poudriere-sh/rmdir.c \
			src/poudriere-sh/setproctitle.c \
			src/poudriere-sh/sleep.c \
			src/poudriere-sh/touch.c \
			src/poudriere-sh/traps.c \
			src/poudriere-sh/unlink.c

sh_CFLAGS+=		-I$(top_srcdir)/src/poudriere-sh \
			-I$(top_builddir)/src/poudriere-sh
# cachec
#sh_SOURCES+=		src/libexec/poudriere/cachec/cachec.c
#sh_LDADD+=		-lrt
src/poudriere-sh/builtins.def: external/sh/builtins.def \
    src/poudriere-sh/builtins-poudriere.def
	cat $^${.ALLSRC} > $@
src/poudriere-sh/shell.h:
	@ln -fs $(abs_top_srcdir)/external/sh/shell.h $@
src/poudriere-sh/builtins.h: src/poudriere-sh/builtins.def \
      src/poudriere-sh/shell.h external/sh/mkbuiltins
	cd src/poudriere-sh && \
	    sh $(abs_top_srcdir)/external/sh/mkbuiltins .
src/poudriere-sh/builtins.c: src/poudriere-sh/builtins.h
sh_SOURCES+=		src/poudriere-sh/builtins.c
${sh_OBJECTS}:		src/poudriere-sh/builtins.h

libucl_la_SOURCES=	\
			external/libucl/include/lua_ucl.h \
			external/libucl/include/ucl.h \
			external/libucl/klib/khash.h \
			external/libucl/klib/kvec.h \
			external/libucl/src/tree.h \
			external/libucl/src/ucl_chartable.h \
			external/libucl/src/ucl_emitter.c \
			external/libucl/src/ucl_emitter_streamline.c \
			external/libucl/src/ucl_emitter_utils.c \
			external/libucl/src/ucl_hash.c \
			external/libucl/src/ucl_hash.h \
			external/libucl/src/ucl_internal.h \
			external/libucl/src/ucl_parser.c \
			external/libucl/src/ucl_util.c \
			external/libucl/src/xxhash.c \
			external/libucl/src/xxhash.h \
			external/libucl/uthash/uthash.h \
			external/libucl/uthash/utlist.h \
			external/libucl/uthash/utstring.h

libucl_la_CFLAGS=	$(AM_CFLAGS) -Wno-extra \
			-I$(top_srcdir)/external/libucl/uthash \
			-I$(top_srcdir)/external/libucl/klib  \
			-I$(top_srcdir)/external/libucl/include  \
			-I$(top_srcdir)/external/libucl/src \
			-Wno-unused-parameter -Wno-pointer-sign \
			-Wno-unused-variable

libptsort_la_SOURCES=	external/ptsort/lib/aa_tree.c \
			external/ptsort/lib/aa_tree.h \
			external/ptsort/lib/fline.c \
			external/ptsort/lib/fline.h

libptsort_la_CPPFLAGS=	-I$(top_srcdir)/external/ptsort/lib
ptsort_SOURCES=		external/ptsort/bin/ptsort.c
ptsort_LDADD=		libptsort.la
ptsort_CPPFLAGS=	-I$(top_srcdir)/external/ptsort/lib

libnv_la_CFLAGS=	$(AM_CFLAGS) \
			-isystem $(top_srcdir)/external/libnv/ -std=gnu99
libnv_la_SOURCES=	\
			external/libnv/common_impl.h \
			external/libnv/msgio.c \
			external/libnv/msgio.h \
			external/libnv/sys/dnv.h \
			external/libnv/sys/dnvlist.c \
			external/libnv/sys/nv.h \
			external/libnv/sys/nv_impl.h \
			external/libnv/sys/nvlist.c \
			external/libnv/sys/nvlist_impl.h \
			external/libnv/sys/nvpair.c \
			external/libnv/sys/nvpair_impl.h

poudriered_SOURCES=	src/poudriered/poudriered.c
poudriered_CFLAGS=	$(AM_CFLAGS) \
			-DPREFIX=\"$(prefix)\" \
			-I$(top_srcdir)/external/libucl/include
poudriered_LDADD=	libucl.la \
			-lsbuf \
			-lutil

jexecd_SOURCES=	src/libexec/poudriere/jexecd/jexecd.c
jexecd_CFLAGS=	$(AM_CFLAGS) -I$(top_srcdir)/external/libnv/sys
jexecd_LDADD=	libnv.la \
		-lsbuf \
		-lutil \
		-ljail

rexec_SOURCES=	src/libexec/poudriere/rexec/rexec.c
rexec_CFLAGS=	$(AM_CFLAGS) -I$(top_srcdir)/external/libnv/sys
rexec_LDADD=	libnv.la

cached_SOURCES=	src/libexec/poudriere/cached/cached.c \
		external/klib/khash.h
cached_CFLAGS=	$(AM_CFLAGS) -I$(top_srcdir)/external/klib
cached_LDADD=	-lutil -lrt

cachec_SOURCES=	src/libexec/poudriere/cachec/cachec.c
cachec_LDADD=	-lrt

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
	    gitver=$$(git -C "$(top_srcdir)" describe --tags HEAD); \
	    sed -e "s,^\(POUDRIERE_VERSION\)=.*,\1='$${gitver}'," \
	      $^${.ALLSRC} > $@; \
	else \
	    cp -f $^${.ALLSRC} $@; \
	fi; \
	chmod +x $@

SUBDIRS= . test

installcheck-local:
	$(MAKE) $(AM_MAKEFLAGS) check am_installcheck=1
