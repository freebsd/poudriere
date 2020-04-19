# $FreeBSD: head/Mk/Uses/readline.mk 498476 2019-04-09 14:04:49Z sunpoet $
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
LIB_DEPENDS+=		libreadline.so.8:devel/readline
CPPFLAGS+=		-I${LOCALBASE}/include
LDFLAGS+=		-L${LOCALBASE}/lib
.endif

.endif
