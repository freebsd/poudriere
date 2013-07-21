SUBDIR=	src \
	conf

.if !defined(NO_ZSH)
SUBDIR+=	completions/zsh
.endif

.include <bsd.subdir.mk>
