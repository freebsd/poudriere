NO_OBJ=		yes
PREFIX?=	/usr/local
FILESDIR=	${PREFIX}/share/poudriere/html/assets/bootstrap/img
FILES=		glyphicons-halflings.png \
		glyphicons-halflings-white.png

beforeinstall:
	mkdir -p ${DESTDIR}${FILESDIR}

.include <bsd.prog.mk>
