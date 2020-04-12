# $FreeBSD: head/Mk/Uses/readline.mk 411970 2016-03-27 01:23:25Z bapt $
#
# handle dependency on the readline port
#
# Feature:	readline
# Usage:	USES=readline
# Valid ARGS:	port
#
# MAINTAINER: portmgr@FreeBSD.org

.if !defined(_INCLUDE_USES_READLINE_MK)
_INCLUDE_USES_READLINE_MK=	yes

.if !exists(/usr/lib/libreadline.so)
readline_ARGS=	port
.endif

.if ${readline_ARGS} == port
LIB_DEPENDS+=		libreadline.so.6:devel/readline
CPPFLAGS+=		-I${LOCALBASE}/include
LDFLAGS+=		-L${LOCALBASE}/lib
.endif

.endif
