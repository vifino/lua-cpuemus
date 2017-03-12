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

local function get(inst, i)
	return mem:get(i)
end
local function set(inst, i, v)
	return mem:set(i, v)
end
-- Stubs for now - eeek.
local shiftreg = 0
local shiftregofs = 0
local function iog(inst, i)
	i = bitops.band(i, 255)
	if i == 1 then return 1 end
	if i == 3 then
		return bitops.rshift(bitops.band(bitops.lshift(shiftreg, shiftregofs), 0xFF00), 8)
	end
	return 0
end
local function ios(inst, i, v)
	i = bitops.band(i, 255)
	if i == 4 then
		shiftreg = math.floor(shiftreg / 256)
		shiftreg = shiftreg + (v * 256)
	end
	if i == 2 then
		shiftregofs = v % 8
	end
end

-- Get ZPU instance and set up.
local inst = l8080.new(get, set, iog, ios)

while true do
	local pc = inst.PC
	local n, c = inst:run()
	print(string.format("0x%04x: %s -> 0x%04x (%i cycles)", pc, n, inst.PC, c))
end
