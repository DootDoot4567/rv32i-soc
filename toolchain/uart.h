#ifndef UART_H
    #define UART_H 
    #include <stdint.h>
    #include <sys/types.h>

    #ifdef LIBC
        #include <errno.h>
    #endif

    #define STDIN_FILENO 0
    #define STDOUT_FILENO 1
    #define STDERR_FILENO 2

    //fd = file descriptor, buf = buffer
    extern int _write(int fd, const void *buf, size_t n);

    extern int _read(int fd, void *buf, size_t n);
#endif