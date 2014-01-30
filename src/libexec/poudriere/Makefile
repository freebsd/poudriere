SUBDIR= dirempty dirwatch rename

.if !defined(DRAGONFLY)
SUBDIR+= make_index cpdup
.endif

PREFIX?=	/usr/local
BINDIR=		${PREFIX}/libexec/poudriere

beforeinstall:
	mkdir -p ${DESTDIR}${BINDIR}

.include <bsd.subdir.mk>
