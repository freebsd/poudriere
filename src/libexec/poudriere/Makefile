SUBDIR=	make_index \
	dirempty \
	dirwatch \
	cpdup

PREFIX?=	/usr/local
BINDIR=		${PREFIX}/libexec/poudriere

beforeinstall:
	mkdir -p ${DESTDIR}${BINDIR}

.include <bsd.subdir.mk>
