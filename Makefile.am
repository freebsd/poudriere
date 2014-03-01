CLEANFILES=	$(dist_rc_SCRIPTS)

awkdir=	$(pkgdatadir)/awk
htmldir= $(pkgdatadir)/html
assetsdir= $(htmldir)/assets
bootstrapdir= $(assetsdir)/bootstrap
btcssdir= $(bootstrapdir)/css
btjsdir= $(bootstrapdir)/js
btimgdir= $(bootstrapdir)/img
datatablesdir= $(assetsdir)/dataTables
dtcssdir= $(datatablesdir)/css
dtimagesdir= $(datatablesdir)/images
dtjsdir= $(datatablesdir)/js
rcdir= $(sysconfdir)/rc.d

dist_bin_SCRIPTS=	src/bin/poudriere

dist_man_MANS=	src/bin/poudriere.8

sysconf_DATA=	src/etc/poudriere.conf.sample \
		src/etc/poudriered.conf.sample

dist_pkgdata_DATA=	src/share/poudriere/bulk.sh \
			src/share/poudriere/clean.sh \
			src/share/poudriere/common.sh \
			src/share/poudriere/daemon.sh \
			src/share/poudriere/common.sh.dragonfly \
			src/share/poudriere/common.sh.freebsd \
			src/share/poudriere/distclean.sh \
			src/share/poudriere/jail.sh \
			src/share/poudriere/options.sh \
			src/share/poudriere/pkgclean.sh \
			src/share/poudriere/ports.sh \
			src/share/poudriere/processonelog.sh \
			src/share/poudriere/processonelog2.sh \
			src/share/poudriere/queue.sh \
			src/share/poudriere/status.sh \
			src/share/poudriere/testport.sh

dist_awk_DATA= src/share/poudriere/awk/dependency_loop.awk \
		src/share/poudriere/awk/humanize.awk \
		src/share/poudriere/awk/json.awk \
		src/share/poudriere/awk/siginfo_buildtime.awk

dist_html_DATA= src/share/poudriere/html/index.html
dist_assets_DATA=	src/share/poudriere/html/assets/poudriere.js \
			src/share/poudriere/html/assets/logo.jpg \
			src/share/poudriere/html/assets/poudriere.css \
			src/share/poudriere/html/assets/jquery-1.9.1.min.js
dist_btjs_DATA=	src/share/poudriere/html/assets/bootstrap/js/bootstrap.min.js
dist_btimg_DATA=	src/share/poudriere/html/assets/bootstrap/img/glyphicons-halflings-white.png \
			src/share/poudriere/html/assets/bootstrap/img/glyphicons-halflings.png
dist_btcss_DATA=	src/share/poudriere/html/assets/bootstrap/css/bootstrap-responsive.min.css \
			src/share/poudriere/html/assets/bootstrap/css/bootstrap.min.css
dist_dtcss_DATA=	src/share/poudriere/html/assets/dataTables/css/jquery.dataTables.css
dist_dtjs_DATA=		src/share/poudriere/html/assets/dataTables/js/jquery.dataTables.min.js
dist_dtimages_DATA=	src/share/poudriere/html/assets/dataTables/images/back_disabled.png \
			src/share/poudriere/html/assets/dataTables/images/back_enabled.png \
			src/share/poudriere/html/assets/dataTables/images/back_enabled_hover.png \
			src/share/poudriere/html/assets/dataTables/images/forward_disabled.png \
			src/share/poudriere/html/assets/dataTables/images/forward_enabled.png \
			src/share/poudriere/html/assets/dataTables/images/forward_enabled_hover.png \
			src/share/poudriere/html/assets/dataTables/images/sort_asc.png \
			src/share/poudriere/html/assets/dataTables/images/sort_asc_disabled.png \
			src/share/poudriere/html/assets/dataTables/images/sort_both.png \
			src/share/poudriere/html/assets/dataTables/images/sort_desc.png \
			src/share/poudriere/html/assets/dataTables/images/sort_desc_disabled.png

src/etc/rc.d/poudriered: src/etc/rc.d/poudriered.in
	@echo "  SED     " $@;
	@sed -e 's,/usr/local,$(prefix),g' src/etc/rc.d/poudriered.in > $@

dist_rc_SCRIPTS=	src/etc/rc.d/poudriered

pkglibexec_PROGRAMS= \
		     cpdup \
		     dirempty \
		     dirwatch \
		     make_index \
		     nc \
		     rename

sbin_PROGRAMS=	poudriered
noinst_LIBRARIES=	libucl.a

AUTOMAKE_OPTIONS=	subdir-objects

rename_SOURCES=	src/libexec/poudriere/rename/rename.c
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
nc_SOURCES=		src/libexec/poudriere/nc/nc.c
make_index_SOURCES=	src/libexec/poudriere/make_index/make_index.c
make_index_LDADD=	-ljail -lsbuf
libucl_a_SOURCES=	external/libucl/src/ucl_emitter.c \
			external/libucl/src/ucl_hash.c \
			external/libucl/src/ucl_parser.c \
			external/libucl/src/ucl_util.c \
			external/libucl/src/xxhash.c
libucl_a_CFLAGS=	-I$(top_srcdir)/external/libucl/uthash \
			-I$(top_srcdir)/external/libucl/include  \
			-I$(top_srcdir)/external/libucl/src \
			-Wno-unused-parameter -Wno-pointer-sign
poudriered_SOURCES=	src/poudriered/poudriered.c
poudriered_CFLAGS=	-DPREFIX=\"$(prefix)\" \
			-I$(top_srcdir)/external/libucl/include
poudriered_LDADD=	libucl.a \
			-lsbuf \
			-lutil

.PHONY:	gen-make-wiki
gen-man-wiki:
	@if ! which mandoc 2>&1 >/dev/null; then \
	  echo "Mandoc required, install textproc/mdocml"; \
	  exit 1; \
	fi
	@for man in $(dist_man_MANS); do \
	  echo "MANDOC doc/$${man##*/}.wiki"; \
	  ( \
	    echo "<nowiki>"; \
	    (mandoc -Thtml $${man} | awk \
	    '$$1 == "<body>" { seenbody=1; next; }; \
	     $$1 == "</body>" { seenbody=0; }; \
	     seenbody == 1 { print };'\
	    ); \
	    echo "</nowiki>"; \
	  ) > doc/$${man##*/}.wiki; \
	done
