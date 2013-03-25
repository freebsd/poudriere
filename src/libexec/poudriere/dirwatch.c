#include <sys/types.h>
#include <sys/event.h>
#include <sys/time.h>
#include <sys/stat.h>

#include <unistd.h>
#include <fcntl.h>
#include <err.h>

int
main(int argc, char **argv)
{
	struct kevent event, change;
	struct stat st;
	int kq, fd;

	if (argc != 2)
		errx(1, "Missing the directory argument");

	if (!(stat(argv[1], &st) == 0 && S_ISDIR(st.st_mode)))
		errx(1, "%s: not a directory", argv[1]);

	if ((kq = kqueue()) == -1)
		err(1, "kqueue()");

	fd = open(argv[1], O_RDONLY);

	EV_SET(&change, fd, EVFILT_VNODE, EV_ADD | EV_ENABLE | EV_ONESHOT, NOTE_WRITE, 0, 0);

	if (kevent(kq, &change, 1, &event, 1, NULL) < 0)
		err(1, "kevent()");

	close(fd);

	return (0);
}
