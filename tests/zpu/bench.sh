#!/bin/sh
LUA=lua5.3
cat tests/zpu/test_input.bas | time $LUA tests/zpu/emu_bench.lua
