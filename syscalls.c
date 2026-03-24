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

    char *prev = *heap;
    char *next = *heap + incr;

    &heap_start = next;



    return (caddr_t) prev;
};

ssize_t _write(int fd, const void buf[.count], size_t count) {

}; 

ssize_t _read(int fd, void buf[.count], size_t count) {

};

int _close(int fd) {

};

off_t _lseek(int fd, off_t offset, int whence) {

};

int _fstat(int fd, struct stat *statbuf) {

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

ssize_t _sbrk_r(int fd, const void buf[.count], size_t count);

ssize_t _write_r(int fd, const void buf[.count], size_t count); 

ssize_t _read_r(int fd, void buf[.count], size_t count);

int _close_r(int fd);

off_t _lseek_r(int fd, off_t offset, int whence);

int _fstat_r(int fd, struct stat *statbuf);

int _isatty_r(int) {
    return 1;
}
