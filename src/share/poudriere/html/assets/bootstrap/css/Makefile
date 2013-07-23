NO_OBJ=		yes
PREFIX?=	/usr/local
FILESDIR=	${PREFIX}/share/poudriere/html/assets/bootstrap/css
FILES=		bootstrap-responsive.min.css \
		bootstrap.min.css

beforeinstall:
	mkdir -p ${DESTDIR}${FILESDIR}

.include <bsd.prog.mk>
