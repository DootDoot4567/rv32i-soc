#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "uart.h"

#include "utils.h"

int main() {
   char buffer[128];

   while(1) {
      fgets(buffer, 128, STDIN_FILENO);
      printf(buffer);
   }
}