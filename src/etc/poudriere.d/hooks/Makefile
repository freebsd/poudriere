NO_OBJ=		yes

PREFIX?=	/usr/local

FILESDIR?=	${PREFIX}/etc/poudriere.d/hooks/
FILES=		pkgbuild.sh.sample \
		bulk.sh.sample

beforeinstall:
	mkdir -p ${FILESDIR}

.include <bsd.prog.mk>
