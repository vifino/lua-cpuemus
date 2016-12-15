-- ZPU Emulator: EMULATE implementations.
-- Quite nice speed up. Used to avoid needing crt0.5 and co.
-- Original by gamemanj, heavily tweaked/rewritten by vifino.
--
-- require this and pass the result in to the ZPU library's apply.
-- Example:
-- zpu:apply(require("zpu_emus")) -- now globally loaded.

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


-- Debug config
-- For figuring out if there's something horribly wrong with the testcase.
local usage_trace = false

-- Place holders for bit functions
local band, bor, bxor, lshift, rshift

-- Localized functions
local mceil, mfloor = math.ceil, math.floor

-- Utils
local function a32(v)
	return band(v, 0xFFFFFFFF)
end
local function sflip(v)
	v = a32(v)
	if band(v, 0x80000000) ~= 0 then
		return v - 0x100000000
	end
	return v
end
local function mkbool(v)
	return v and 1 or 0
end
local function advip(zpu_emu)
	zpu_emu.rIP = a32(zpu_emu.rIP + 1)
end

-- getb and setb are the internal implementation of LOADB and STOREB
-- and are thus heavily endianess dependant
local function getb(zpu_emu, a)
	local s = (24 - lshift(band(a, 3), 3))
	local av = zpu_emu:get32(band(a, 0xFFFFFFFC))
	return band(rshift(av, s), 0xFF)
end
local function setb(zpu_emu, a, v)
	local s = (24 - lshift(band(a, 3), 3))
	local b = bxor(lshift(0xFF, s), 0xFFFFFFFF)
	local av = band(zpu_emu:get32(band(a, 0xFFFFFFFC)), b)
	zpu_emu:set32(band( a, 0xFFFFFFFC), bor(av, lshift(band(v, 0xFF), s)))
end

-- geth and seth are the same but for halfwords.
-- This implementation will just mess up if it gets a certain kind of misalignment.
-- (I have no better ideas. There is no reliable way to error-escape.)

local function geth(zpu_emu, a)
	local s = (24 - lshift(band(a, 3), 3))
	local av = zpu_emu:get32(band(a, 0xFFFFFFFC))
	return band(rshift(av, s), 0xFFFF)
end

local function seth(zpu_emu, a, v)
	local s = (24 - lshift(band(a, 3), 3))
	local b = bxor(lshift(0xFFFF, s), 0xFFFFFFFF)
	local av = band(zpu_emu:get32(band(a, 0xFFFFFFFC)), b)
	zpu_emu:set32(band(a, 0xFFFFFFFC), bor(av, lshift(band(v, 0xFFFF), s)))
end

local function eqbranch(zpu_emu, bcf)
	local br = zpu_emu.rIP + zpu_emu:v_pop()
	if bcf(zpu_emu:v_pop()) then
		zpu_emu.rIP = br
	else
		advip(zpu_emu)
	end
end

-- Generic L/R shifter, logical-only.
local function gpi_shift(v, lShift)
	if (lShift >= 32) or (lShift <= -32) then return 0 end
	if lShift > 0 then return lshift(v, lShift) end
	if lShift < 0 then return rshift(v, -lShift) end
end
-- Generic multifunction shifter. Should handle any case with ease.
local function gp_shift(v, lShift, arithmetic)
	arithmetic = arithmetica and band(v, 0x80000000) ~= 0
	v = gpi_shift(v, lShift)
	if arithmetic and (lShift < 0) then
		return bor(v, bxor(gpi_shift(0xFFFFFFFF, lShift), 0xFFFFFFFF))
	end
	return v
end

-- EMULATE building
local emulates = {}
local unused_emulates = 0

local function make_emu(id, name, code)
	local unused = true
	if usage_trace then
		emulates[id] = {name, function(...)
			if unused then
				unused = false
				io.stderr:write(name .. " used, " .. unused_emulates .. " to go\n")
				unused_emulates = unused_emulates - 1
			end
			return code(...)
		end}
	else
		emulates[id] = {name, code}
	end
	unused_emulates = unused_emulates + 1
end
local function make_pair(id, name, code)
	make_emu(id, name, function(zpu_emu)
		local a = zpu_emu:v_pop()
		local b = zpu_emu:get32(zpu_emu.rSP)
		zpu_emu:set32(zpu_emu.rSP, code(a, b))
		advip(zpu_emu)
	end)
end

-- Actual emulates!
-- Yay!

make_emu(19, "LOADH", function(zpu_emu) zpu_emu:set32(zpu_emu.rSP, geth(zpu_emu, zpu_emu:get32(zpu_emu.rSP))) end)
make_emu(20, "STOREH", function(zpu_emu) seth(zpu_emu, zpu_emu:v_pop(), zpu_emu:v_pop()) end)

make_pair(4, "LESSTHAN", function(a, b) return mkbool(sflip(a) < sflip(b)) end)
make_pair(5, "LESSTHANEQUAL", function(a, b) return mkbool(sflip(a) <= sflip(b)) end)
make_pair(6, "ULESSTHAN", function(a, b) return mkbool(a < b) end)
make_pair(7, "ULESSTHANEQUAL", function(a, b) return mkbool(a <= b) end)

make_pair(9, "SLOWMULT", function(a, b) return band(a * b, 0xFFFFFFFF) end)

make_pair(10, "LSHIFTRIGHT", function(a, b)
	return gp_shift(b, -sflip(a), false)
end)
make_pair(11, "ASHIFTLEFT", function(a, b)
	return gp_shift(b, sflip(a), true)
end)
make_pair(12, "ASHIFTRIGHT", function(a, b)
	return gp_shift(b, -sflip(a), true)
end)

make_pair(14, "EQ", function(a, b) return mkbool(a == b) end)
make_pair(15, "NEQ", function(a, b) return mkbool(a ~= b) end)

make_emu(16, "NEQ", function(zpu_emu)
	zpu_emu:set32(zpu_emu.rSP, a32(-sflip(zpu_emu:get32(zpu_emu.rSP))))
	advip(zpu_emu)
end)

make_pair(17, "SUB", function(b, a) return band(a - b, 0xFFFFFFFF) end)
make_pair(18, "XOR", function(b, a) return band(bxor(a, b), 0xFFFFFFFF) end)

make_emu(19, "LOADB", function(zpu_emu) zpu_emu:set32(zpu_emu.rSP, getb(zpu_emu, zpu_emu:get32(zpu_emu.rSP))) advip(zpu_emu) end)
make_emu(20, "STOREB", function(zpu_emu)
	setb(zpu_emu, zpu_emu:v_pop(), zpu_emu:v_pop())
	advip(zpu_emu)
end)

local function rtz(v)
	if v < 0 then return mceil(v) end
	return mfloor(v)
end
local function cmod(a, b)
	return a - (rtz(a / b) * b)
end
make_pair(21, "DIV", function (a, b) return a32(rtz(sflip(a) / sflip(b))) end)
make_pair(22, "MOD", function (a, b) return a32(cmod(sflip(a), sflip(b))) end)

make_emu(23, "EQBRANCH", function(zpu_emu) return eqbranch(zpu_emu, function(b) return b == 0 end) end)
make_emu(24, "NEQBRANCH", function(zpu_emu) return eqbranch(zpu_emu, function(b) return b ~= 0 end) end)

make_emu(25, "POPPCREL", function(zpu_emu) zpu_emu.rIP = band(zpu_emu.rIP + zpu_emu:v_pop(), 0xFFFFFFFF) end)

make_emu(29, "PUSHSPADD", function(zpu_emu)
	zpu_emu:set32(zpu_emu.rSP, band(band(lshift(zpu_emu:get32(zpu_emu.rSP), 2), 0xFFFFFFFF) + zpu_emu.rSP, 0xFFFFFFFC))
	advip(zpu_emu)
end)

make_emu(31, "CALLPCREL", function(zpu_emu)
	local routine = band(zpu_emu.rIP + zpu_emu:get32(zpu_emu.rSP), 0xFFFFFFFF)
	zpu_emu:set32(zpu_emu.rSP, band(zpu_emu.rIP + 1, 0xFFFFFFFF))
	zpu_emu.rIP = routine
end)

-- Installation helper
local function assert_bitfn(bit, name)
	assert(bit[name], "zpu_emus: Did not find function "..name.." in bitlib. We need it.")
end
local function install_bit(bl)
	assert_bitfn(bl, "band") band = bl.band
	assert_bitfn(bl, "bor") bor = bl.bor
	assert_bitfn(bl, "bxor") bxor = bl.bxor
	assert_bitfn(bl, "lshift") lshift = bl.lshift
	assert_bitfn(bl, "rshift") rshift = bl.rshift
end

return function(zpu)
	-- check bitlib, we need it too.
	install_bit(zpu.bit32)
	local old_emu = zpu.op_emulate
	zpu.op_emulate = function(zpu_emu, op)
		local emulate = emulates[op]
		if emulate then
			emulate[2](zpu_emu)
			return emulate[1]
		end
		if usage_trace then io.stderr:write("zpu_emus: usage trace found "..op.." hasn't been written yet.") end
		return old_emu(zpu_emu, op)
	end
	return true
end

