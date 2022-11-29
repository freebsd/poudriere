PROG=		cpdup
MAN=		cpdup.1
SRCS=		$(wildcard src/*.c)
OBJS=		$(SRCS:.c=.o)
DISTFILES=	GNUmakefile LICENSE README.md src $(MAN)
DISTFILES+=	BACKUPS PORTING

CFLAGS=		-O -pipe -std=c99 -pedantic
CFLAGS+=	-Wall -Wextra -Wlogical-op -Wshadow -Wformat=2 \
		-Wwrite-strings -Wcast-qual -Wcast-align
#CFLAGS+=	-Wduplicated-cond -Wduplicated-branches \
		-Wrestrict -Wnull-dereference \
#CFLAGS+=	-Wconversion

CFLAGS+=	$(shell pkg-config --cflags openssl)
LIBS+=		$(shell pkg-config --libs   openssl)

OS?=		$(shell uname -s)
ifeq ($(OS),FreeBSD)
CFLAGS+=	-D_ST_FLAGS_PRESENT_
else ifeq ($(OS),Linux)
CFLAGS+=	-D_GNU_SOURCE -D_FILE_OFFSET_BITS=64
CFLAGS+=	$(shell pkg-config --cflags libbsd-overlay)
LIBS+=		$(shell pkg-config --libs   libbsd-overlay)
endif

PREFIX?=	/usr/local
MAN_DIR?=	$(PREFIX)/share/man

TMPDIR?=	/tmp
RPMBUILD_DIR?=	$(TMPDIR)/$(PROG)-rpmbuild
ARCHBUILD_DIR?=	$(TMPDIR)/$(PROG)-archbuild

all: $(PROG)

$(PROG): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $(OBJS) $(LIBS)

install:
	install -s -Dm 0755 $(PROG) $(PREFIX)/bin/$(PROG)
	install -Dm 0644 $(MAN) $(MAN_DIR)/man1/$(MAN)
	gzip -9 $(MAN_DIR)/man1/$(MAN)

rpm:
	mkdir -p $(RPMBUILD_DIR)/BUILD
	cp -Rp $(DISTFILES) $(RPMBUILD_DIR)/BUILD/
	rpmbuild -bb -v \
		--define="_topdir $(RPMBUILD_DIR)" \
		linux/$(PROG).spec
	@arch=`uname -m` ; \
		pkg=`( cd $(RPMBUILD_DIR)/RPMS/$${arch}; ls $(PROG)-*.rpm )` ; \
		cp -v $(RPMBUILD_DIR)/RPMS/$${arch}/$${pkg} . ; \
		rm -rf $(RPMBUILD_DIR) ; \
		echo "Install with: 'sudo yum localinstall $${pkg}'"

archpkg:
	mkdir -p $(ARCHBUILD_DIR)/src
	cp linux/PKGBUILD $(ARCHBUILD_DIR)/
	cp -Rp $(DISTFILES) $(ARCHBUILD_DIR)/src/
	( cd $(ARCHBUILD_DIR) && makepkg )
	@pkg=`( cd $(ARCHBUILD_DIR); ls $(PROG)-*.pkg.* )` ; \
		cp -v $(ARCHBUILD_DIR)/$${pkg} . ; \
		rm -rf $(ARCHBUILD_DIR) ; \
		echo "Install with: 'sudo pacman -U $${pkg}'"

clean:
	rm -f $(PROG) $(OBJS)

.PHONY: all install clean rpm archpkg
