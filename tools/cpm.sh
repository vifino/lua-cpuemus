#!/bin/sh
stty -echo -icanon
luajit emu_8080_cpm.lua "$@"
stty echo icanon
