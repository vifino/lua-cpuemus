#!/usr/bin/env lua
-- 8080 disassembler.

local arg = arg or {...}

local fname = arg[1]
if not fname then
	error("Need filename")
end
local f, err = io.open(fname, "rb")
if err then error(err) end

-- Load bitops
local bitops = require("bitops")
-- Load 8080
local l8080 = require("8080")
-- Install bitops
l8080.set_bit32(bitops)

local memlib = require("memlib")

-- Memory: ROM, RAM and peripherals.
local s = f:read("*a")
local memsz = #s
local rom = memlib.backend.rostring(s, memsz)
f:close()

local function getb(inst, i, v)
	return rom:get(i)
end
local function setb(inst, i, v)
	return rom:set(i, v)
end

-- Get 8080 instance and set up.
local inst = l8080.new(getb, setb)

local pc = 0
local name
while pc < memsz do
	pc, name = inst:disasm(pc)
	print(name)
end
