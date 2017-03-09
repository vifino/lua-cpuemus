#!/bin/sh
LUA=lua5.3
cat tests/test_input.bas | time $LUA tests/emu_bench.lua
