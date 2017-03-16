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
local rom_data = f:read("*a")
local rom = memlib.new("rostring", rom_data:sub(1, 128), memsz)
f:close()

local mem = memlib.new()"rwoverlay",rom, memsz)

-- Address handlers/Peripherals
--local addr_handlers = {}
--local comp = memlib.compose(mem, addr_handlers)

local function get(inst, i)
	return mem:get(i)
end
local function set(inst, i, v)
	return mem:set(i, v)
end

local fdcDrive, fdcTrack, fdcSector = 0, 0, 1
local fdcStatus = 1
local dmaHigh, dmaLow = 0, 0

local function getAbsoluteSectorAddress()
	--print(fdcTrack, fdcSector)
	if fdcSector < 1 then return nil, 3 end
	if fdcSector > 26 then return nil, 3 end
	local p = (fdcTrack * 26) + (fdcSector - 1)
	return p * 128
end
local function getSector()
	if fdcDrive ~= 0 then return nil, 1 end
	local sp, ns2 = getAbsoluteSectorAddress()
	if not sp then return nil, ns2 end
	return rom_data:sub(sp + 1, sp + 128), 0
end
local function putSector()
	error("Not yet.")
end

local function dmaInject(buf)
	local target = dmaLow + (dmaHigh * 256)
	--print(string.format("%04x\n", target))
	for i = 1, buf:len() do
		mem:set(target, buf:byte(i))
		target = target + 1
	end
end

local function iog(inst, i)
	if i == 0 then return 0xFF end -- Console input ready
	if i == 1 then return string.byte(io.read(1)) end -- Console data

	if i == 10 then return fdcDrive end
	if i == 11 then return fdcTrack end
	if i == 12 then return fdcSector end

	if i == 13 then return 0xFF end -- FDC-CMD-COMPLETE
	if i == 14 then return fdcStatus end -- FDC-STATUS

	if i == 15 then return dmaLow end
	if i == 16 then return dmaHigh end
	return 0
end
local function ios(inst, i, v)
	if i == 1 then io.write(string.char(v)) end

	if i == 10 then fdcDrive = v end
	if i == 11 then fdcTrack = v end
	if i == 12 then fdcSector = v end
	if i == 13 then
		if v == 0 then
			local b, ns = getSector()
			if b then
				dmaInject(b)
			else
				print("Failed Read", fdcDrive, fdcTrack, fdcSector)
			end
			fdcStatus = ns
		else
			print("Failed Write")
			fdcStatus = 7
		end
	end
	if i == 15 then dmaLow = v end
	if i == 16 then dmaHigh = v end
end

local inst = l8080.new(get, set, iog, ios)

local fmt = string.format
while true do
	local pc = inst.PC
	local n, c = inst:run()
	--print(fmt("0x%04x: %s -> 0x%04x (%i cycles)", pc, n, inst.PC, c))
	--inst:dump()
end
