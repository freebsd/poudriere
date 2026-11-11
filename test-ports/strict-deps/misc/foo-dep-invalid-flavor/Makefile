PORTNAME=	foo-dep-invalid-flavor
DISTVERSION=	20161010
PORTREVISION=	0
CATEGORIES=	misc
MASTER_SITES=	#
DISTFILES=	#

MAINTAINER=	bdrewery@FreeBSD.org
COMMENT=	Depends on a FLAVOR that does not exist for an existing origin, for STRICT_DEPS tests

LICENSE=	BSD2CLAUSE

USES=		metaport

NO_BUILD=	yes
NO_ARCH=	yes

RUN_DEPENDS+=	foo:misc/bar@bogus

do-install:
	@${DO_NADA}

.include <bsd.port.mk>
