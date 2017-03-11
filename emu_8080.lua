#!/usr/bin/env lua
-- ZPU Emulator: Example usage.

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
local rom = memlib.backend.rostring(t, memsz)
f:close()

local mem = memlib.backend.rwoverlay(rom, memsz)

-- Address handlers/Peripherals
--local addr_handlers = {}
--local comp = memlib.compose(mem, addr_handlers)

local function get(zpu_inst, i, v)
	return mem:get(i)
end
local function set(zpu_inst, i, v)
	return mem:set(i, v)
end

-- Get ZPU instance and set up.
local inst = l8080.new(get, set)

while true do
	print(inst:run())
end
