#!/usr/bin/env lua
-- ZPU Emulator, providing the zpu-sinkrn environment

local arg = arg or {...}

local fname = arg[1]
if not fname then
	error("Need filename")
end
local f, err = io.open(fname, "rb")
if err then error(err) end

local memsz = 0x80000

-- Load bitops
local bitops = require("bitops")
-- Load ZPU
local zpu = require("zpu")
-- Install bitops
zpu.set_bit32(bitops)
-- Load ZPU emulates and apply them
local zpu_emulates = require("zpu_emus")
zpu:apply(zpu_emulates)

local memlib = require("memlib")

-- Memory: ROM, RAM and peripherals.
local t = f:read(memsz)
local rom = memlib.new("rostring", t)
f:close()

local mem = memlib.new("rwoverlay32", rom, memsz)

-- Address handlers/Peripherals
local addr_handlers = {}
addr_handlers[0x80000024] = function(comp, method, i, v)
	-- UART(O)
	if method == "get32be" then return 0x100 end
	if method == "set32be" then
		io.write(string.char(bitops.band(v, 0xFF)))
		io.flush()
		return
	end
end

addr_handlers[0x80000028] = function(comp, method, i, v)
	-- UART(I)
	if method == "get32be" then
		local inp = io.read(1)
		local ret = (inp and string.byte(inp)) or 0
		return bitops.bor(ret, 0x100)
	end
end

local comp = memlib.compose(mem, addr_handlers)

-- MMU Emulation goes here.

local mmu_debug = false

-- This is nil in kernelmode, otherwise it is the amount of instructions to go.
-- <= 0 means "quit ASAP".
local mmu_usermode = nil
local mmu_usermode_quitmode = -1
-- Flag to enter usermode at EOI
local mmu_entering_usermode = false

local mmu_km_bst = 0
local mmu_km_bip = 0
local mmu_km_bsp = 0

-- "Next" p1 through p4 registers to be used next time usermode is enabled.
local mmu_km_np1 = 0
local mmu_km_np2 = 0
local mmu_km_np3 = 0
local mmu_km_np4 = 0

local mmu_st = 0
local mmu_p1 = 0
local mmu_p2 = 0
local mmu_p3 = 0
local mmu_p4 = 0

-- real start addr, virtual start addr, size in words
local mmu_segs = {{0, 0, 0}, {0, 0, 0}}

local function mmu_map(i)
	for _, v in ipairs(mmu_segs) do
		if i >= v[2] then
			if i < (v[2] + (v[3] * 4)) then
				return v[1] + (i - v[2])
			end
		end
	end
end

local function mmu_err()
	-- M.A.E. (memory access error, unrelated to any other MAE)
	mmu_usermode = -1
	mmu_usermode_quitmode = 0xFFFFFFFD
end

local function get32_um(k)
	local map = mmu_map(k)
	if not map then mmu_err() return 0 end
	return comp:get32be(map)
end
local function set32_um(k, v)
	local map = mmu_map(k)
	if not map then mmu_err() return end
	comp:set32be(map, v)
end

local function mmu_cmd(c)
	-- This is never correct
	if c >= 0x80000000 then return end
	if mmu_usermode then
		mmu_usermode = -1
		mmu_usermode_quitmode = c
	else
		-- Kernel commands
		if c == 0 then
			mmu_entering_usermode = true
		end
		if c == 1 then
			if mmu_debug then print("S1 ", mmu_p1, mmu_p2, mmu_p3) end
			mmu_segs[1] = {mmu_p1, mmu_p2, mmu_p3}
		end
		if c == 2 then
			if mmu_debug then print("S2 ", mmu_p1, mmu_p2, mmu_p3) end
			mmu_segs[2] = {mmu_p1, mmu_p2, mmu_p3}
		end
		if c == 3 then
			mmu_km_np1 = mmu_p1
			mmu_km_np2 = mmu_p2
			mmu_km_np3 = mmu_p3
			mmu_km_np4 = mmu_p4
		end
	end
end

local function mmu_getreg(k)
	if k == 0 then
		return mmu_st
	end
	if k == 1 then
		return mmu_p1
	end
	if k == 2 then
		return mmu_p2
	end
	if k == 3 then
		return mmu_p3
	end
	if k == 4 then
		return mmu_p4
	end
	if not mmu_usermode then
		if k == 5 then
			return mmu_km_bst
		end
		if k == 6 then
			return mmu_km_bip
		end
		if k == 7 then
			return mmu_km_bsp
		end
	end
	return 0
end
local function mmu_setreg(k, v)
	if k == 0 then
		mmu_cmd(v)
	end
	if k == 1 then
		mmu_p1 = v
	end
	if k == 2 then
		mmu_p2 = v
	end
	if k == 3 then
		mmu_p3 = v
	end
	if k == 4 then
		mmu_p4 = v
	end
end

local function get32(zpu_inst, i)
	if i == 0x80000000 then
		return mmu_getreg(0)
	end
	if i == 0x80000004 then
		return mmu_getreg(1)
	end
	if i == 0x80000008 then
		return mmu_getreg(2)
	end
	if i == 0x8000000C then
		return mmu_getreg(3)
	end
	if i == 0x80000010 then
		return mmu_getreg(4)
	end
	if i == 0x80000014 then
		return mmu_getreg(5)
	end
	if i == 0x80000018 then
		return mmu_getreg(6)
	end
	if i == 0x8000001C then
		return mmu_getreg(7)
	end
	if mmu_usermode then
		return get32_um(i)
	end
	return comp:get32be(i)
end
local function set32(zpu_inst, i, v)
	if i == 0x80000000 then
		mmu_setreg(0, v)
		return
	end
	if i == 0x80000004 then
		mmu_setreg(1, v)
		return
	end
	if i == 0x80000008 then
		mmu_setreg(2, v)
		return
	end
	if i == 0x8000000C then
		mmu_setreg(3, v)
		return
	end
	if i == 0x80000010 then
		mmu_setreg(4, v)
		return
	end
	if mmu_usermode then
		set32_um(i, v)
		return
	end
	comp:set32be(i, v)
end

-- Get ZPU instance and set up.
local zpu_inst = zpu.new(get32, set32)
zpu_inst.rSP = memsz

while true do
	if not zpu_inst:run() then
		-- Breakpoint. Quit if in kernel mode, else M.A.E
		if mmu_usermode then
			mmu_err()
		else
			error("Kernelmode breakpoint occurred, rIP dec " .. zpu_inst.rIP)
		end
	end
	if mmu_usermode then
		if mmu_usermode > 0 then
			mmu_usermode = mmu_usermode - 1
		end
		-- It can't keep executing IMs forever - it WILL run out of code sooner or later.
		if (mmu_usermode <= 0) and (not zpu_inst.fLastIM) then
			if mmu_debug then print("Leaving usermode...") end
			mmu_km_bst = mmu_st
			mmu_km_bip = zpu_inst.rIP
			mmu_km_bsp = zpu_inst.rSP
			zpu_inst.rIP = 0x20
			zpu_inst.rSP = memsz
			mmu_usermode = nil
			mmu_st = mmu_usermode_quitmode
		end
	else
		if mmu_entering_usermode then
			mmu_entering_usermode = false
			mmu_usermode = 1024
			mmu_usermode_quitmode = 0xFFFFFFFF
			zpu_inst.rIP = mmu_p2
			zpu_inst.rSP = mmu_p3
			mmu_st = mmu_p1
			mmu_p1 = mmu_km_np1
			mmu_p2 = mmu_km_np2
			mmu_p3 = mmu_km_np3
			mmu_p4 = mmu_km_np4
			if mmu_debug then print("entering usermode @ IP" .. zpu_inst.rIP .. "SP" .. zpu_inst.rSP) end
		end
	end
end
