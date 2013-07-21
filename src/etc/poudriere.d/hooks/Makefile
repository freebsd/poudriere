NO_OBJ=		yes

PREFIX?=	/usr/local

FILESDIR?=	${PREFIX}/etc/poudriere.d/hooks/
FILES=		pkgbuild.sh.sample \
		bulk.sh.sample

beforeinstall:
	mkdir -p ${DESTDIR}${FILESDIR}

.include <bsd.prog.mk>
