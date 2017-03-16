#!/usr/bin/env lua
-- 8080 Emulator: Example usage.

local arg = arg or {...}

local fname = arg[1]
if not fname then
	error("Need filename")
end
local f, err = io.open(fname, "rb")
if err then error(err) end

local memsz = 0x10000

-- Load bitops
local bitops = loadfile("bitops.lua")(false, true)
-- Load ZPU
local l8080 = dofile("8080/init.lua")
-- Install bitops
l8080.set_bit32(bitops)

local memlib = require("memlib")

-- Memory: ROM, RAM and peripherals.
local t = f:read(memsz)
local rom = memlib.new("rostrring", t, memsz)
f:close()

local mem = memlib.new("rwoverlay", rom, memsz)

-- Address handlers/Peripherals
--local addr_handlers = {}
--local comp = memlib.compose(mem, addr_handlers)

local function get(inst, i)
	return mem:get(i)
end
local function set(inst, i, v)
	return mem:set(i, v)
end

local function iog(inst, i)
	if i == 0 then return string.byte(io.read(1)) end
	return 0
end
local function ios(inst, i, v)
	if i == 0 then
		print(string.char(v))
	end
end

local inst = l8080.new(get, set, iog, ios)

local fmt = string.format
while true do
	local pc = inst.PC
	local n, c = inst:run()
	print(fmt("0x%04x: %s -> 0x%04x (%i cycles)", pc, n, inst.PC, c))
end
