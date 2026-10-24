PORTNAME=	bar
DISTVERSION=	20161010
PORTREVISION=	0
FLAVORS=	default flav
CATEGORIES=	misc
MASTER_SITES=	#
DISTFILES=	#

MAINTAINER=	bdrewery@FreeBSD.org
COMMENT=	Simple multi-FLAVOR port, for STRICT_DEPS tests

LICENSE=	BSD2CLAUSE

USES=		metaport

NO_BUILD=	yes
NO_ARCH=	yes

.include <bsd.port.options.mk>

.if empty(FLAVOR)
FLAVOR=	default
.endif

.if ${FLAVOR} != default && !empty(FLAVORS:M${FLAVOR})
PKGNAMESUFFIX=	-${FLAVOR:tu}
.endif

do-install:
	@${DO_NADA}

.include <bsd.port.mk>
