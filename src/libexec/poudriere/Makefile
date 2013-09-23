PREFIX?=	/usr/local

all: dirwatch make_index dirempty

dirempty: dirempty.c
	${CC} -Wall -Werror ${CFLAGS} dirempty.c -o dirempty

dirwatch: dirwatch.c
	${CC} -Wall -Werror ${CFLAGS} dirwatch.c -o dirwatch

make_index: make_index.c
	${CC} -Wall -Werror ${CFLAGS} make_index.c -o make_index -lsbuf

install: dirwatch make_index dirempty
	mkdir -p ${DESTDIR}${PREFIX}/libexec/poudriere
	install -m 755 -o root -g wheel dirwatch \
	    ${DESTDIR}${PREFIX}/libexec/poudriere
	install -m 755 -o root -g wheel make_index \
	    ${DESTDIR}${PREFIX}/libexec/poudriere
	install -m 755 -o root -g wheel dirempty \
	    ${DESTDIR}${PREFIX}/libexec/poudriere

clean:
	rm -f dirwatch make_index dirempty
