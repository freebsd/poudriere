.SUFFIXES:	.in

PREFIX?=	/usr/local
FILESDIR=	${PREFIX}/etc/rc.d
FILES=		poudriere
FILESMODE=	${BINMODE}
CLEANFILES=	${FILES}

.in:
	sed -e 's,__PREFIX__,${PREFIX},g' \
		${.IMPSRC} > ${.TARGET}

.include <bsd.prog.mk>
