#!/bin/sh
stty -echo -icanon
lua emu_8080_cpm.lua "$@"
stty echo icanon
