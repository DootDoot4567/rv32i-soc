#include "uart.h"

#define IO_BASE 0x200
#define IO_DEVICE(x) (IO_BASE + x * 0x40)

//Define memory mapping at 0x240, 0x241, 0x242, and leave 0x243 unused
#define UART_RX(x) (* (volatile uint8_t *) (IO_DEVICE(x) + 0x0))
#define UART_TX(x) (* (volatile uint8_t *) (IO_DEVICE(x) + 0x1))
#define UART_STATUS(x) (* (volatile uint8_t *) (IO_DEVICE(x) + 0x2))

//Define status signals for the uart receiver and transmitter
//Fits within one integer register 
#define STATUS_WAIT_RX (1u << 1)
#define UART_FIFO_RX_EMPTY (1u << 2)
#define UART_FIFO_RX_FULL (1u << 3)

#define STATUS_WAIT_TX (1u << 4)
#define UART_FIFO_TX_EMPTY (1u << 5)
#define UART_FIFO_TX_FULL (1u << 6)

#define STATUS_INTERRUPT (1u << 7)

#define DEFAULT_DEVICE 1

int _write(int fd, const void *buf, size_t n) {
    if(fd != STDOUT_FILENO && fd != STDERR_FILENO) {
        #ifdef LIBC
            errno = EBADF;
        #endif 

        return -1;
    }

    uint8_t device = DEFAULT_DEVICE;
    const uint8_t *device_ptr = buf;

    for(size_t i = 0; i < n; i++) {
        while (UART_STATUS(device) & STATUS_WAIT_TX) {
            //Do nothing!
        }

        UART_TX(device) = device_ptr[i];
    }

    return (int) n;
}

int _read(int fd, void *buf, size_t n) {
    if(fd != STDIN_FILENO) {
        #ifdef LIBC
            errno = EBADF;
        #endif 

        return -1;
    }

    if (n == 0) {
        return 0;
    }

    uint8_t device = DEFAULT_DEVICE;
    uint8_t *device_ptr = buf;
    size_t i = 0;

    while(i < n) {
        if (UART_STATUS(device) & STATUS_WAIT_RX) {
            if(i == 0) {
                continue;
            }

            break;
        }

        device_ptr[i++] = (uint8_t) UART_RX(device);
    }

    return (int) i;
}