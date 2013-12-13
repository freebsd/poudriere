SUBDIR=		awk \
		html

NO_OBJ=		yes

PREFIX?=	/usr/local

FILESDIR=	${PREFIX}/share/poudriere
FILES=		bulk.sh \
		clean.sh \
		common.sh \
		common.sh.freebsd \
		common.sh.dragonfly \
		daemon.sh \
		distclean.sh \
		jail.sh \
		options.sh \
		ports.sh \
		pkgclean.sh \
		processonelog.sh \
		processonelog2.sh \
		queue.sh \
		status.sh \
		testport.sh
FILESMODE=	${BINMODE}

beforeinstall:
	mkdir -p ${DESTDIR}${FILESDIR}

.include <bsd.prog.mk>
