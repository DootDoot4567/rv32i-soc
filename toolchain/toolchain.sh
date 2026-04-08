#!/bin/bash

cd ~/
git clone https://github.com/riscv/riscv-gnu-toolchain
cd riscv-gnu-toolchain 
./configure --prefix=$HOME/riscv --enable-multilib
make -j1