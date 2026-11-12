PORTNAME=	foo-CIRCULAR
DISTVERSION=	20260928
CATEGORIES=     misc

FLAVORS=        itself a b c d
.for f in ${FLAVORS}
${f}_PKGNAMESUFFIX=      -${f}
.endfor

# FAIL: itself depends on itself
itself_RUN_DEPENDS=	${PORTNAME}-itself>0:misc/${PORTNAME}@itself

# FAIL: a and b circularly depend on each other
a_RUN_DEPENDS=	${PORTNAME}-b>0:misc/${PORTNAME}@b
b_RUN_DEPENDS=	${PORTNAME}-a>0:misc/${PORTNAME}@a

# PASS: c depends on d, and d has no deps
c_RUN_DEPENDS=	${PORTNAME}-d>0:misc/${PORTNAME}@d

USES=           metaport

.include <bsd.port.mk>
