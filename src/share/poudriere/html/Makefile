SUBDIR=		assets
NO_OBJ=		yes
PREFIX?=	/usr/local
FILESDIR=	${PREFIX}/share/poudriere/html
FILES=		index.html

beforeinstall:
	mkdir -p ${DESTDIR}${FILESDIR}

.include <bsd.prog.mk>
