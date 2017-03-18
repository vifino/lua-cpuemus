#!/usr/bin/env lua
-- 8080 Emulator: CP/M specific example.

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

local availfn
if jit then -- LuaJIT alternative check.
	-- UNIX-only, I believe. Possibly Linux only.
	-- But hey, who cares?
	local ffi = require("ffi")
	ffi.cdef [[
		struct pollfd {
			int	 fd;
			short events;
			short revents;
		};

		int poll(struct pollfd *fds, unsigned long int nfds, int timeout);
	]]
	local C = ffi.C
	local pollfds = ffi.new("struct pollfd[1]")
	pollfds[0].fd = 0
	pollfds[0].events = 1
	availfn = function()
		local hasdata = C.poll(pollfds, 1, 1) == 1
		if hasdata then return 0xFF else return 0x00 end
	end
else
	-- Fake available/unavailable counter. Dirty hack, but it works.
	-- Because we have no way to check if there are actually bytes available,
	-- we set it to only be available once every availevery read checks.
	local availevery = 10000 -- fake having a data byte every 10k calls.
	local availn = 1

	availfn = function()
		if availn == (availevery - 1) then
			availn = 1
			return 0xFF -- available
		end
		availn = availn + 1
		return 0x00
	end
end

local function iog(inst, i)
	if i == 0 then -- Console input status
		return availfn()
	elseif i == 1 then
		-- Console data.
		local c = io.read(1)
		if c == "\n" then return 13 end -- CP/M and Zork seem to prefer \r to \n, \r\n or \n\r.
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

local function ios(inst, i, v)
	if i == 1 then
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
				--print("Failed Read", fdcDrive, fdcTrack, fdcSector)
			end
			fdcStatus = ns
		else
			--print("Failed Write")
			fdcStatus = 7
		end
	elseif i == 15 then dmaLow = v
	elseif i == 16 then dmaHigh = v end
end

local inst = l8080.new(get, set, iog, ios)

-- Sleep
local sleep
if os.sleep then
	sleep = os.sleep
elseif jit then
	local ffi = require("ffi")
	ffi.cdef [[
		void Sleep(int ms);
		// int poll(struct pollfd *fds, unsigned long nfds, int timeout); // already defined above.
	]]
	local C = ffi.C
	if ffi.os == "Windows" then
		sleep = function(s)
			C.Sleep(s*1000)
		end
	else
		sleep = function(s)
			C.poll(nil, 0, s*1000)
		end
	end
end

-- Clock speed limiting
local clockspeed = 2 * 1000 * 1000 -- 2MHz
local sleepdur = 0.05

-- Probably fucked up the math.
local cps = clockspeed/(1/sleepdur)

local fmt = string.format

if sleep then -- has a sleep function, which allows us to limit execution speed.
	local i=0
	while true do
		i = i + 1
		if i == cps then sleep(sleepdur) i = 0 end
		inst:run()
	end
else
	while true do -- Fallback.
		inst:run()
	end
end
