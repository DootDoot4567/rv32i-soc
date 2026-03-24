#include "uart.h"

#define IO_BASE 0x200
#define IO_DEVICE(x) (IO_BASE + x * 0x40)

//Define memory mapping at 0x240, 0x241, 0x242, and leave 0x243 unused
#define UART_RX(x) (*(volatile * uint8_t) (IO_DEVICE(x) + 0x0))
#define UART_TX(x) (*(volatile * uint8_t) (IO_DEVICE(x) + 0x1))
#define UART_STATUS (*(volatile * uint8_t) (IO_DEVICE(x) + 0x2))

//#define UA