PREFIX?=	/usr/local

all: dirwatch make_index dirempty

dirempty: dirempty.c
	${CC} -Wall -Werror ${CFLAGS} ${.CURDIR}/dirempty.c -o ${.OBJDIR}/dirempty

dirwatch: dirwatch.c
	${CC} -Wall -Werror ${CFLAGS} ${.CURDIR}/dirwatch.c -o ${.OBJDIR}/dirwatch

make_index: make_index.c
	${CC} -Wall -Werror ${CFLAGS} -ljail ${.CURDIR}/make_index.c -o ${.OBJDIR}/make_index -lsbuf

install: dirwatch make_index dirempty
	mkdir -p ${PREFIX}/libexec/poudriere
	install -m 755 -o root -g wheel ${.OBJDIR}/dirwatch ${PREFIX}/libexec/poudriere
	install -m 755 -o root -g wheel ${.OBJDIR}/make_index ${PREFIX}/libexec/poudriere
	install -m 755 -o root -g wheel ${.OBJDIR}/dirempty ${PREFIX}/libexec/poudriere

clean:
	rm -f ${.OBJDIR}/dirwatch ${.OBJDIR}/make_index ${.OBJDIR}/dirempty
