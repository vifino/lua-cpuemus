#!/bin/sh
[ -f tools/spcvid ] || cc -o tools/spcvid -lSDL tools/spcvid.c
rm -f /tmp/si_8080_input_fifo
mkfifo /tmp/si_8080_input_fifo
cat /tmp/si_8080_input_fifo | luajit emu_8080_si.lua roms/8080/invaders.rom | ./tools/spcvid > /tmp/si_8080_input_fifo
