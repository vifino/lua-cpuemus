-- ZPU Emulator V3
-- Based on ZPU Emulator V2.1 by gamemanj.
-- Thank you.

-- To get a zpu instance, call zpu.new(f:memget32, f:memset32) -> t
-- You need to provide memget32, memset32 and a bit32 compatible bit library.
-- To set the bit32 compatible library: zpu.set_bit32(<your bit32)
-- memget32(t:zpu_inst, i:addr) -> i:val: Memory reader.
-- memset32(t:zpu_inst, i:addr, i:val): Memory setter.
--
-- You can also apply changes, like EMULATE implementations, globally like this:
-- zpu:apply(f:changee)
-- Or locally:
-- zpu_inst:apply(f:changee)
-- The 'changee' is a function that takes the zpu library/instance and modifies it.
-- See emu.lua and zpu_emus.lua, too.
--
-- All further calls/elements are on the returned zpu instance, not the library.

-- Other things:
-- zpu.rSP: Stack pointer. Set this to the top of the memory.
-- zpu.rIP: Instruction Pointer.
-- zpu:op_emulate(i:op) -> s:disassembly: Run one EMULATE opcode, can be overridden.
-- zpu:run() -> s:disassembly: Run one opcode. Returns nil if unknown.
-- zpu:run_trace(f:file, i:stackdump) -> s:disassembly: Run one opcode, giving an instruction and stack trace to the file.
-- zpu:v_pop/zpu:v_push: helper functions

--[[
	The MIT License (MIT)

	Copyright (c) 2016 Adrian Pistol

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.
--]]


local zpu = {}
zpu.__index = zpu

-- Local cache of some functions.
-- Many may be set at runtime.
local bnot, band, bor, bxor, lshift, rshift -- set at runtime.

-- sets local cache of bit functions
local function assert_bitfn(bit, name)
	assert(bit[name], "zpuemu: Did not find function "..name.." in bitlib. We need it.")
end
function zpu.set_bit32(bitlib)
	assert_bitfn(bitlib, "bnot") bnot = bitlib.bnot
	assert_bitfn(bitlib, "band") band = bitlib.band
	assert_bitfn(bitlib, "bor") bor = bitlib.bor
	assert_bitfn(bitlib, "bxor") bxor = bitlib.bxor
	assert_bitfn(bitlib, "lshift") lshift = bitlib.lshift
	assert_bitfn(bitlib, "rshift") rshift = bitlib.rshift
	zpu.bit32 = bitlib
end

-- Used for byte extraction by the opcode getter.
-- This ZPU implementation does not yet implement any instruction cache.
local function split32(v)
	return {
		band(rshift(v, 24), 0xFF),
		band(rshift(v, 16), 0xFF),
		band(rshift(v, 8), 0xFF),
		band(v, 0xFF)
	}
end

-- helpers
local function v_push(self, v)
	self.rSP = band(self.rSP - 4, 0xFFFFFFFF)
	self:set32(self.rSP, v)
end
zpu.v_push = v_push
local function v_pop(self)
	local v = self:get32(self.rSP)
	self.rSP = band(self.rSP + 4, 0xFFFFFFFC)
	return v
end
zpu.v_pop = v_pop

-- OPs!
local function op_im(self, i, last)
	if last then
		v_push(self, bor(lshift(band(v_pop(self), 0x1FFFFFFF), 7), i))
	else
		if band(i, 0x40) ~= 0 then i = bor(i, 0xFFFFFF80) end
		v_push(self, i)
	end
end
local function op_loadsp(self, i)
	local addr = band(self.rSP + lshift(bxor(i, 0x10), 2), 0xFFFFFFFC)
	v_push(self, self:get32(addr))
end
local function op_storesp(self, i)
	-- Careful with the ordering! Documentation suggests the OPPOSITE of what it should be!
	-- https://github.com/zylin/zpugcc/blob/master/toolchain/gcc/libgloss/zpu/crt0.S#L836
	-- This is a good testpoint:
	-- 0x81 0x3F
	-- This should leave zpuinst.rSP + 4 on stack.
	-- You can work it out from the sources linked.
	local bsp = band(self.rSP + lshift(bxor(i, 0x10), 2), 0xFFFFFFFC)
	self:set32(bsp, v_pop(self))
end
local function op_addsp(self, i)
	local addr = band(self.rSP + lshift(i, 2), 0xFFFFFFFC)
	v_push(self, band(self:get32(addr) + v_pop(self), 0xFFFFFFFF))
end
local function op_load(self)
	self:set32(self.rSP, self:get32(band(self:get32(self.rSP), 0xFFFFFFFC)))
end
local function op_store(self)
	self:set32(band(v_pop(self), 0xFFFFFFFC), v_pop(self))
end
local function op_add(self)
	local a = v_pop(self)
	self:set32(self.rSP, band(a + self:get32(self.rSP), 0xFFFFFFFF))
end
local function op_and(self)
	v_push(self, band(v_pop(self), v_pop(self)))
end
local function op_or(self)
	v_push(self, bor(v_pop(self), v_pop(self)))
end
local function op_not(self)
	v_push(self, bnot(v_pop(self)))
end

local op_flip_tb = {
	[0] = 0,
	[1] = 2,
	[2] = 1,
	[3] = 3
}
local function op_flip_byte(i)
	local a = op_flip_tb[rshift(band(i, 0xC0), 6)]
	local b = op_flip_tb[rshift(band(i, 0x30), 4)]
	local c = op_flip_tb[rshift(band(i, 0x0C), 2)]
	local d = op_flip_tb[band(i, 0x03)]
	return bor(bor(a, lshift(b, 2)), bor(lshift(c, 4), lshift(d, 6)))
end
local function op_flip(self)
	local v = v_pop(self)
	local a = op_flip_byte(band(rshift(v, 24), 0xFF))
	local b = op_flip_byte(band(rshift(v, 16), 0xFF))
	local c = op_flip_byte(band(rshift(v, 8), 0xFF))
	local d = op_flip_byte(band(v, 0xFF))
	v_push(self, bor(bor(lshift(d, 24), lshift(c, 16)), bor(lshift(b, 8), a)))
end
function zpu.op_emulate(self, op)
	v_push(self, band(self.rIP + 1, 0xFFFFFFFF))
	self.rIP = lshift(op, 5)
	return "EMULATE ".. op .. "/" .. bor(op, 0x20)
end

local function ip_adv(self)
	self.rIP = band(self.rIP + 1, 0xFFFFFFFF)
end

-- OP lookup tables
local op_table_basic = {
	-- basic ops
	[0x04] = function(self) self.rIP = v_pop(self) return "POPPC" end,
	[0x08] = function(self) op_load(self) ip_adv(self) return "LOAD" end,
	[0x0C] = function(self) op_store(self) ip_adv(self) return "STORE" end,
	[0x02] = function(self) v_push(self, self.rSP) ip_adv(self) return "PUSHSP" end,
	[0x0D] = function(self) self.rSP = band(v_pop(self), 0xFFFFFFFC) ip_adv(self) return "POPSP" end,
	[0x05] = function(self) op_add(self) ip_adv(self) return "ADD" end,
	[0x06] = function(self) op_and(self) ip_adv(self) return "AND" end,
	[0x07] = function(self) op_or(self) ip_adv(self) return "OR" end,
	[0x09] = function(self) op_not(self) ip_adv(self) return "NOT" end,
	[0x0A] = function(self) op_flip(self) ip_adv(self) return "FLIP" end,
	[0x0B] = function(self) ip_adv(self) return "NOP" end
}
local op_table_advanced = {
	-- "advanced" ops, their lookup is more... involved
	[0x80] = function(self, op, lim) local tmp = band(op, 0x7F) op_im(self, tmp, lim) self.fLastIM = true ip_adv(self) return "IM "..tmp end,
	[0x60] = function(self, op) local tmp = band(op, 0x1F) op_loadsp(self, tmp) ip_adv(self) return "LOADSP " .. (bxor(0x10, tmp) * 4) end,
	[0x40] = function(self, op) local tmp = band(op, 0x1F) op_storesp(self, tmp) ip_adv(self) return "STORESP " .. (bxor(0x10, tmp) * 4) end,
	[0x20] = function(self, op) return self:op_emulate(band(op, 0x1F)) end, -- EMULATE
	[0x10] = function(self, op) local tmp = band(op, 0xF) op_addsp(self, tmp) ip_adv(self) return "ADDSP " .. tmp end,
}

-- Run a single instruction
function zpu.run(self)
	-- NOTE: The ZPU porbably can't be trusted to have a consistent memory
	-- access pattern, *unless* it is accessing memory in the IO range.
	-- In the case of the IO range, it is specifically
	-- assumed MMIO will happen there, so the processor bypasses caches.
	-- For now, we're just using the behavior that would be used for
	-- a naive processor, which is exactly what this is.
	local op = split32(self:get32(band(self.rIP, 0xFFFFFFFC)))[band(self.rIP, 3) + 1]
	local lim = self.fLastIM
	self.fLastIM = false

	-- check if OP is found in lookup tables
	-- By the amount of ops we have, a lookup table is a good thing.
	-- For a few ifs, it would probably be slower. But for many, it is faster on average.
	local opimpl = op_table_basic[op]
	if opimpl then
		return opimpl(self), op
	end

	opimpl = op_table_advanced[band(op, 0x80)] or op_table_advanced[band(op, 0xE0)] or op_table_advanced[(band(op, 0xF0))]
	if opimpl then -- "advanced" op
		return opimpl(self, op, lim), op
	end
	return nil, op
end

function zpu.run_trace(self, fh, tracestack)
	fh:write(self.rIP .. " (" .. string.format("%x", self.rSP))
	fh:flush()
	local cSP = self.rSP
	for i=1, tracestack do
		fh:write(string.format("/%x", self:get32(cSP)))
		cSP = cSP + 4
	end
	fh:write(") :")
	local op, opb = self:run()
	if op == nil then
		fh:write("UNKNOWN\n")
	else
		fh:write(op .. "\n")
	end
	return op, opb
end

-- Create a new ZPU instance
function zpu.new(memget32, memset32)
	assert(zpu.bit32, "zpuemu: Did not set bit32 library. Bailing out.")

	local zpu_instance = {}
	setmetatable(zpu_instance, zpu)
	zpu_instance.get32 = memget32
	zpu_instance.set32 = memset32

	zpu_instance.rSP = 0
	zpu_instance.rIP = 0
	zpu.fLastIM = false

	return zpu_instance
end

-- Apply changes
function zpu.apply(self, changee)
	self = changee(self)
	return self
end

-- Hooray! We're done!
return zpu
