#!/bin/sh
stty raw -echo
luajit emu_8080_cpm.lua "$@"
stty cooked sane
