# $FreeBSD: head/Mk/bsd.port.post.mk 340713 2014-01-22 15:12:27Z mat $

AFTERPORTMK=	yes

.include "bsd.port.mk"

.undef AFTERPORTMK
