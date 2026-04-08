#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "uart.h"

#include "utils.h"

int main() {
   //works without printf:
   //*(volatile uint8_t *)0x241 = 'A';
   //*(volatile uint8_t *)0x241 = '\n';

   //breaks with printf:
   // puts("Hello");
   // printf("Hello world!\n");
   // printf("Type a character:\n");
   //char buffer[128];

   while(1) {
      // fgets(buffer, 128, STDIN_FILENO);
      // printf(buffer);

      // char c = getchar();
      // printf("You typed: %c\n", c);
   }
}