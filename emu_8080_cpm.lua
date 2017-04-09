#!/usr/bin/env lua
-- 8080 Emulator: CP/M specific example.

-- Optional debug stuff.
local debugf
-- debugf = io.open("debug", "w")
local debug = function (s)
	if debugf then debugf:write(s .. "\n") end
end

local arg = arg or {...}

local fname = arg[1]
if not fname then
	error("Need filename")
end
local f, err = io.open(fname, "rb")
if err then error(err) end

local memsz = 0x10000

-- Load bitops
local bitops = require("bitops")
-- Load CPU
local l8080 = require("8080")
-- Install bitops
l8080.set_bit32(bitops)

local memlib = require("memlib")

-- Memory: ROM, RAM and peripherals.
local rom_data = f:read(128)
f:close()

local mem = memlib.new("table", memsz)
for i=1, 128 do
	mem:set(i-1, rom_data:byte(i))
end

local drive_data = {}
drive_data[0] = memlib.new("file", fname)
for i = 1, 3 do
	if arg[i + 1] then
		drive_data[i] = memlib.new("file", arg[i + 1])
	end
end

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

local function get_absolute_sector_address()
	--print(fdcTrack, fdcSector)
	if fdcSector < 1 then return nil, 3 end
	if fdcSector > 26 then return nil, 3 end
	local p = (fdcTrack * 26) + (fdcSector - 1)
	return p * 128
end

function membatch_read(mem, addr, n)
	local t = {}
	addr = addr - 1
	for i=1, n do
		t[i] = mem:get(addr+i)
	end
	t.n = n
	return t
end

function membatch_write(mem, addr, data)
	addr = addr - 1
	for i=1, (data.n or #data) do
		mem:set(addr+i, data[i])
	end
	return true
end

local function get_sector()
	local dd = drive_data[fdcDrive]
	if not dd then return nil, 1 end
	local sp, ns2 = get_absolute_sector_address()
	if not sp then return nil, ns2 end
	return membatch_read(dd, sp, 128), 0
end
local function put_sector(data)
	local dd = drive_data[fdcDrive]
	if not dd then return 1 end
	local sp, ns2 = get_absolute_sector_address()
	if not sp then return ns2 end
	membatch_write(dd, sp, data)
	return 0
end

local function dma_write(buf)
	local target = dmaLow + (dmaHigh * 256)
	--print(string.format("DMA: %04x %i: %x %x %x %x", target, #buf, buf[1], buf[2], buf[3], buf[4]))
	for i = 1, (buf.n or #buf)  do
		mem:set(target, buf[i])
		target = target + 1
	end
end

local function dma_read(len)
	local target = dmaLow + (dmaHigh * 256) - 1
	--print(string.format("DMA: %04x %i: %x %x %x %x", target, #buf, buf[1], buf[2], buf[3], buf[4]))
	local tmp = {n = len}
	for i = 1, len  do
		tmp[i] = mem:get(target + i)
	end
	return tmp
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
		debug("WR: " .. string.char(v))
		io.write(string.char(v))
		io.flush()
	elseif i == 10 then fdcDrive = v
	elseif i == 11 then fdcTrack = v
	elseif i == 12 then fdcSector = v
	elseif i == 13 then
		if v == 0 then
			local b, ns = get_sector()
			if b then
				dma_write(b)
			--else
				--print("Failed Read", fdcDrive, fdcTrack, fdcSector)
			end
			fdcStatus = ns
		elseif v == 1 then
			local s, ns = pcall(put_sector, dma_read(128))
			if not s then
				--io.stderr:write("ERR: "..tostring(ns).."\n")
				fdcStatus = 6
			else
				fdcStatus = ns
			end
		else
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
		if debugf then
			local n2, txt = inst:disasm(inst.PC)
			debug(txt)
		end
		inst:run()
		if debugf then
			inst:dump(debugf)
		end
	end
else
	while true do -- Fallback.
		if debugf then
			local n2, txt = inst:disasm(inst.PC)
			debug(txt)
		end
		inst:run()
		if debugf then
			inst:dump(debugf)
		end
	end
end
