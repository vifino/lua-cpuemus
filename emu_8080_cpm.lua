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
-- Load CPU
local l8080 = dofile("8080/init.lua")
-- Install bitops
l8080.set_bit32(bitops)

local memlib = require("memlib")

-- Memory: ROM, RAM and peripherals.
local rom_data = f:read("*a")
local rom = memlib.new("rostring", rom_data:sub(1, 128), memsz)
f:close()

local drive_data = {}
drive_data[0] = rom_data
for i = 1, 3 do
	if arg[i + 1] then
		local f = io.open(arg[i + 1], "rb")
		if not f then error("Failed to open drive " .. (i + 1)) end
		drive_data[i] = f:read("*a")
		f:close()
	end
end

local mem = memlib.new("rwoverlay",rom, memsz)

-- Address handlers/Peripherals

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
	local dd = drive_data[fdcDrive]
	if not dd then return nil, 1 end
	local sp, ns2 = getAbsoluteSectorAddress()
	if not sp then return nil, ns2 end
	return dd:sub(sp + 1, sp + 128), 0
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

-- Fake available/unavailable counter. Dirty hack, but it works.
-- Because we have no way to check if there are actually bytes available,
-- we set it to only be available once every availevery read checks.
local availevery = 10000 -- fake having a data byte every 10k calls.
local availn = 1

local consoleIB = nil
local function iog(inst, i)
	if i == 0 then -- Console input status
		if availn == (availevery - 1) then -- counter reached
			availn = 1
			return 0xFF -- available
		end
		availn = availn + 1
		return 0x00 -- fake unavailable
	elseif i == 1 then
		if consoleIB then
			local cb = consoleIB
			consoleIB = nil
			return cb
		end
		-- Console data.
		local c = io.read(1)
		if c == "\n" then consoleIB = 10 return 13 end
		return string.byte(c)
	elseif i == 10 then return fdcDrive
	elseif i == 11 then return fdcTrack
	elseif i == 12 then return fdcSector

	elseif i == 13 then return 0xFF -- FDC-CMD-COMPLETE
	elseif i == 14 then return fdcStatus -- FDC-STATUS

	elseif i == 15 then return dmaLow
	elseif i == 16 then return dmaHigh end
	return 0
end

local consoleLastCR, consoleLastNL = false, false
local function ios(inst, i, v)
	if i == 1 then
		if consoleLastCR and v ~= 10 then -- not \r\n
			io.write('\r')
		end
		consoleLastCR = false
		if v == 13 then consoleLastCR = true return end -- \r
		io.write(string.char(v))
		io.flush()
	elseif i == 10 then fdcDrive = v
	elseif i == 11 then fdcTrack = v
	elseif i == 12 then fdcSector = v
	elseif i == 13 then
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
	elseif i == 15 then dmaLow = v
	elseif i == 16 then dmaHigh = v end
end

local inst = l8080.new(get, set, iog, ios)

local fmt = string.format
while true do
	local pc = inst.PC
	local n, c = inst:run()
	--print(fmt("0x%04x: %s -> 0x%04x (%i cycles)", pc, n, inst.PC, c))
	--inst:dump()
end
