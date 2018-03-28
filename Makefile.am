CLEANFILES=	$(dist_rc_SCRIPTS)
MOSTLYCLEANFILES=

AM_CFLAGS=	-Wall -pipe -O2

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

dist_bin_SCRIPTS=	poudriere

dist_man_MANS=	src/bin/poudriere.8

sysconf_DATA=	src/etc/poudriere.conf.sample \
		src/etc/poudriered.conf.sample
examples_DATA=	src/share/examples/poudriere/nginx.conf.sample \
		src/share/examples/poudriere/httpd.conf.sample

hook_DATA=	src/etc/poudriere.d/hooks/bulk.sh.sample \
		src/etc/poudriere.d/hooks/pkgbuild.sh.sample

dist_pkgdata_DATA=	\
			src/share/poudriere/api.sh \
			src/share/poudriere/bulk.sh \
			src/share/poudriere/common.sh \
			src/share/poudriere/daemon.sh \
			src/share/poudriere/distclean.sh \
			src/share/poudriere/image.sh \
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
		src/share/poudriere/awk/siginfo_buildtime.awk

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
		     @RM@ \
		     timeout \
		     timestamp \
		     tsort \
		     @SH@
EXTRA_PROGRAMS= \
		rm \
		sh

noinst_LIBRARIES=	libucl.a libnv.a libptsort.a

AUTOMAKE_OPTIONS=	subdir-objects

clock_SOURCES=	src/libexec/poudriere/clock/clock.c
cpdup_SOURCES=	src/libexec/poudriere/cpdup/cpdup.c \
		src/libexec/poudriere/cpdup/hcproto.c \
		src/libexec/poudriere/cpdup/hclink.c \
		src/libexec/poudriere/cpdup/misc.c \
		src/libexec/poudriere/cpdup/fsmid.c \
		src/libexec/poudriere/cpdup/md5.c
cpdup_LDADD=	-lmd
cpdup_CFLAGS=	-D_ST_FLAGS_PRESENT_=1
dirempty_SOURCES=	src/libexec/poudriere/dirempty/dirempty.c
dirwatch_SOURCES=	src/libexec/poudriere/dirwatch/dirwatch.c
locked_mkdir_SOURCES=	src/libexec/poudriere/locked_mkdir/locked_mkdir.c
nc_SOURCES=		src/libexec/poudriere/nc/nc.c
pwait_SOURCES=		src/libexec/poudriere/pwait/pwait.c
rename_SOURCES=		src/libexec/poudriere/rename/rename.c
rm_SOURCES=		src/libexec/poudriere/rm/rm.c
timeout_SOURCES=	src/libexec/poudriere/timeout/timeout.c
timestamp_SOURCES=	src/libexec/poudriere/timestamp/timestamp.c
tsort_SOURCES=		src/libexec/poudriere/tsort/tsort.c

sh_CFLAGS=		-DSHELL -std=gnu99 -DVTABSIZE=1000 ${sh_hist_CFLAGS} \
			-include $(top_srcdir)/external/sh_compat/compat.h \
			-I$(top_srcdir)/src \
			-I$(top_srcdir)/external/sh
sh_LDADD=		${sh_hist_LDADD}
sh_hist_LDADD=		@MAINTAINER_MODE_TRUE@ -ledit
sh_hist_CFLAGS=		@MAINTAINER_MODE_FALSE@ -DNO_HISTORY
sh_SOURCES=		external/sh_compat/strchrnul.c \
			external/sh_compat/utimensat.c \
			external/sh/alias.c \
			external/sh/arith_yacc.c \
			external/sh/arith_yylex.c \
			external/sh/bltin/echo.c \
			external/sh/cd.c \
			external/sh/error.c \
			external/sh/eval.c \
			external/sh/exec.c \
			external/sh/expand.c \
			external/sh/histedit.c \
			external/sh/input.c \
			external/sh/jobs.c \
			external/sh/kill.c \
			external/sh/mail.c \
			external/sh/main.c \
			external/sh/memalloc.c \
			external/sh/miscbltin.c \
			external/sh/mystring.c \
			external/sh/nodes.c \
			external/sh/options.c \
			external/sh/output.c \
			external/sh/parser.c \
			external/sh/printf.c \
			external/sh/redir.c \
			external/sh/show.c \
			external/sh/syntax.c \
			external/sh/test.c \
			external/sh/trap.c \
			external/sh/var.c
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
			src/poudriere-sh/helpers.c \
			src/poudriere-sh/mkdir.c \
			src/poudriere-sh/mkfifo.c \
			src/poudriere-sh/mktemp.c \
			src/poudriere-sh/realpath.c \
			src/poudriere-sh/rmdir.c \
			src/poudriere-sh/setproctitle.c \
			src/poudriere-sh/sleep.c \
			src/poudriere-sh/touch.c \
			src/poudriere-sh/unlink.c
sh_CFLAGS+=		-I$(top_srcdir)/src/poudriere-sh \
			-I$(top_builddir)/src/poudriere-sh
# cachec
#sh_SOURCES+=		src/libexec/poudriere/cachec/cachec.c
#sh_LDADD+=		-lrt
src/poudriere-sh/builtins.def: $(top_srcdir)/external/sh/builtins.def \
    $(top_srcdir)/src/poudriere-sh/builtins-poudriere.def
	cat $^${.ALLSRC} > $@
src/poudriere-sh/shell.h:
	@ln -fs ../../$(top_srcdir)/external/sh/shell.h $@
src/poudriere-sh/builtins.h: src/poudriere-sh/builtins.def \
      src/poudriere-sh/shell.h $(top_srcdir)/external/sh/mkbuiltins
	cd $(top_builddir)/src/poudriere-sh && \
	    sh ../../$(top_srcdir)/external/sh/mkbuiltins .
src/poudriere-sh/builtins.c: src/poudriere-sh/builtins.h
sh_SOURCES+=		src/poudriere-sh/builtins.c
${sh_OBJECTS}:		src/poudriere-sh/builtins.h

libucl_a_SOURCES=	external/libucl/src/ucl_emitter.c \
			external/libucl/src/ucl_emitter_streamline.c \
			external/libucl/src/ucl_emitter_utils.c \
			external/libucl/src/ucl_hash.c \
			external/libucl/src/ucl_parser.c \
			external/libucl/src/ucl_util.c \
			external/libucl/src/xxhash.c
libucl_a_CFLAGS=	-I$(top_srcdir)/external/libucl/uthash \
			-I$(top_srcdir)/external/libucl/klib  \
			-I$(top_srcdir)/external/libucl/include  \
			-I$(top_srcdir)/external/libucl/src \
			-Wno-unused-parameter -Wno-pointer-sign

libptsort_a_SOURCES=	external/ptsort/lib/aa_tree.c \
			external/ptsort/lib/fline.c
libptsort_a_CPPFLAGS=	-I$(top_srcdir)/external/ptsort/lib
ptsort_SOURCES=		external/ptsort/bin/ptsort.c
ptsort_LDADD=		libptsort.a
ptsort_CPPFLAGS=	-I$(top_srcdir)/external/ptsort/lib

libnv_a_CFLAGS=		-isystem $(top_srcdir)/external/libnv/ -std=gnu99
libnv_a_SOURCES=	external/libnv/sys/dnvlist.c \
			external/libnv/msgio.c \
			external/libnv/sys/nvlist.c \
			external/libnv/sys/nvpair.c
poudriered_SOURCES=	src/poudriered/poudriered.c
poudriered_CFLAGS=	-DPREFIX=\"$(prefix)\" \
			-I$(top_srcdir)/external/libucl/include
poudriered_LDADD=	libucl.a \
			-lsbuf \
			-lutil

jexecd_SOURCES=	src/libexec/poudriere/jexecd/jexecd.c
jexecd_CFLAGS=	-I$(top_srcdir)/external/libnv/sys
jexecd_LDADD=	libnv.a \
		-lsbuf \
		-lutil \
		-ljail

rexec_SOURCES=	src/libexec/poudriere/rexec/rexec.c
rexec_CFLAGS=	-I$(top_srcdir)/external/libnv/sys
rexec_LDADD=	libnv.a

cached_SOURCES=	src/libexec/poudriere/cached/cached.c
cached_CFLAGS=	-I$(top_srcdir)/external/klib
cached_LDADD=	-lutil -lrt

cachec_SOURCES=	src/libexec/poudriere/cachec/cachec.c
cachec_LDADD=	-lrt

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
	  echo "MANDOC wiki/$${man##*/}.md"; \
	  ( \
	    echo "### This page is auto-generated from $(dist_man_MANS)"; \
	    (mandoc -Thtml $${man} | awk \
	    '$$1 == "<body>" { seenbody=1; next; }; \
	     $$1 == "</body>" { seenbody=0; }; \
	     seenbody == 1 { print };'\
	    ); \
	  ) > wiki/$${man##*/}.md; \
	done

MOSTLYCLEANFILES+=	poudriere
.PHONY: poudriere
poudriere: $(top_srcdir)/src/bin/poudriere
	@if which git >/dev/null 2>&1 && \
	    [ -d "$$(git -C "$(top_srcdir)" rev-parse --git-dir)" ]; then \
	    gitver=$$(git -C "$(top_srcdir)" describe --tags HEAD); \
	    echo "POUDRIERE_VERSION=$${gitver} > $@"; \
	    sed -e "s,^\(POUDRIERE_VERSION\)=.*,\1='$${gitver}'," \
	      $^${.ALLSRC} > $@; \
	    chmod +x $@; \
	else \
	    cp -f $^${.ALLSRC} $@; \
	fi;
