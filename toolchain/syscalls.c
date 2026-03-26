//The purpose of this file is to contain the stubs needed to shrink newlib
//to fit within an FPGA with our processor design

#include <stdint.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include <reent.h>

#include "uart.h"

extern char _heap_start;
extern char _heap_end;

caddr_t _sbrk(int incr) {
    static char *heap = &_heap_start;

    char *prev = heap;
    char *next = heap + incr;

    if (next < &_heap_start || next > &_heap_end ) {
        errno = ENONEM;

        return (caddr_t) -1;
    }

    heap = next;

    return (caddr_t) prev;
};

int _close(int) {
    errno = EBADF;
    
    return -1;
};

off_t _lseek(int, off_t, int) {
    errno = ESPIPE;

    return -1;
};

int _fstat(int, struct stat *st) {
    st->st_mode = S_IFCHR;

    return 0;
};

int _isatty(int) {
    return 1;
}

void _exit(int) {
    while(1) {
        //Do nothing...
    };
};

//Reentrant versions of syscalls stubs needed for our processor

caddr_t _sbrk_r(struct _reent *ptr, ptrdiff_t incr) {
    return _sbrk((int) incr);
};

int _write_r(struct _reent *ptr, int fd, const void *buf, size_t n) {
    return _write(fd, buf, n);
}; 

int _read_r(struct _reent *ptr, int fd, void *buf, size_t n) {
    return _read(fd, buf, n);
};

int _close_r(struct _reent *ptr, int fd) {
    return _close(fd);
};

off_t _lseek_r(struct _reent *ptr, int fd, off_t offset, int whence) {
    return _lseek(fd, offset, whence);
};

int _fstat_r(struct _reent *ptr, int fd, struct stat *st) {
    return _fstat(fd, st);
};

int _isatty_r(struct _reent *ptr, int fd) {
    return _isatty(fd);
}
