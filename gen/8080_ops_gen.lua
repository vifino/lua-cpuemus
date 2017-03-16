-- We have already generated the op inst len and op names.
local opnames = require("8080.opnames")

local smatch, fmt = string.match, string.format
local tinsert = table.insert

-- Prelude
io.write([[
-- Actual implementation of OPs.
-- Good god, this is... huge.
-- Luckily, it is generated.

local band, bor, bxor, rshift, lshift

-- Helpers
local function a8(x)
	return band(x, 0xFF)
end

local function pair(X, Y)
	return bor(lshift(X, 8), Y)
end

local function spair(s, Xn, Yn, res)
	s[Xn] = rshift(band(res, 0xFF00), 8)
	s[Yn] = band(res, 0xFF)
	s.cy = (band(res, 0xFFFF0000) > 0)
end

-- Parity is counting the number of set bits.
-- If the number of set bits is odd, it will return true.
-- If the number bits is even, it will return false.
-- Notably, size should be the amount of bits *minus 1*. So parity(res, 7) for the common 8-bit case.
local function parity_r(x, size)
	local p = 0
	x = band(x, lshift(1, size) - 1)
	for i=0, size do
		if band(x, 1) ~= 0 then
			p = p + 1
		end
		x = rshift(x, 1)
	end
	return band(p, 1) == 0
end

-- Because bitops are rather slow,
-- caching them could be a good advantage.
local paritycache = {}
local function parity(x)
	local cx = paritycache[x]
	if cx then
		return cx
	end
	local r = parity_r(x, 7)
	paritycache[x] = r
	return r
end

local function flaghandle(inst, res)
	res = band(res, 0xFF)
	inst.z = (res == 0) -- is zero
	inst.s = (band(res, 0x80) ~= 0) -- sign flag, if bit 7 set
	inst.p = parity(res)
	return res
end

local function mdc(b, c)
	if c then
		return b + 1
	end
	return b
end

local function addcda(a, b, c)
	b = mdc(b, c)
	local b1 = (a % 16) + (b % 16)
	return band(a + b, 0xFF), b1 > 0x0F
end
local function addcdn(a, b, c)
	b = mdc(b, c)
	return band(a + b, 0xFF), (a + b) > 0xFF
end
local function addcdb(a, b, c)
	b = mdc(b, c)
	local b1 = (a % 16) + (b % 16)
	return band(a + b, 0xFF), b1 > 0x0F, (a + b) > 0xFF
end

local function subcda(a, b, c)
	b = mdc(b, c)
	local b1 = (a % 16) + (b % 16)
	return band(a - b, 0xFF), b1 > 0xF
end
local function subcdn(a, b, c)
	b = mdc(b, c)
	return band(a - b, 0xFF), (a - b) < 0
end
local function subcdb(a, b, c)
	b = mdc(b, c)
	local b1 = (a % 16) + (b % 16)
	return band(a - b, 0xFF), b1 > 0xF, (a - b) < 0
end
local function applyb(s, r, a, c)
	s.ac = a
	s.cy = c
	return r
end

local function s_push16(s, res)
	local high, low = rshift(band(res, 0xFF00), 8), band(res, 0xFF)
	s.SP = band(s.SP - 1, 0xFFFF)
	s:setb(s.SP, high)
	s.SP = band(s.SP - 1, 0xFFFF)
	s:setb(s.SP, low)
end

local function s_pop16(s)
	local low = s:getb(s.SP)
	s.SP = band(s.SP + 1, 0xFFFF)
	local high = s:getb(s.SP)
	s.SP = band(s.SP + 1, 0xFFFF)
	return pair(high, low)
end

local function s_push8(s, res)
	s.SP = band(s.SP - 1, 0xFFFF)
	s:setb(s.SP, res)
end

local function s_pop8(s)
	local res = s:getb(s.SP)
	s.SP = band(s.SP + 1, 0xFFFF)
	return res
end

local function s_call(s, t)
	s_push16(s, band(s.PC, 0xFFFF))
	s.PC = t
end

local function encode_psw(s)
	-- SZ0A0P1C
	local n = 2
	if s.cy then n = n + 1 end
	if s.p then n = n + 4 end
	if s.ac then n = n + 16 end
	if s.z then n = n + 64 end
	if s.s then n = n + 128 end
	return n
end

local function decode_psw(s, n)
	s.cy = band(n, 1) ~= 0
	s.p = band(n, 4) ~= 0
	s.ac = band(n, 16) ~= 0
	s.z = band(n, 64) ~= 0
	s.s = band(n, 128) ~= 0
end

local function b_lsft(a)
	local n = band(a * 2, 0xFF)
	return n, band(a, 0x80) ~= 0
end

local function b_rsft(a)
	local n = band(math.floor(a / 2), 0x7F)
	return n, band(a, 1) ~= 0
end

-- OPS
local ops = {
]])

-- Helpers
local T_ADDR = 1
local T_BYTE = 2

-- Used to identify and translate flags
local flags = {
	["!FZ"] = "s.z == false",
	["FZ"] = "s.z == true",
	["!FC"] = "s.cy == false",
	["FC"] = "s.cy == true",
	["!FPE"] = "s.p == false",
	["FPE"] = "s.p == true",
	["!FS"] = "s.s == false",
	["FS"] = "s.s == true"
	-- The "aux. carry" flag is unreadable directly.
}

local function arg_types(argstr)
	local tstr, rstr = "", ""
	local real = {}
	for T in string.gmatch(argstr, '([^, ]+)') do
		if T == "adr" then
			tstr = tstr .. "X"
			rstr = rstr .. "x"
			tinsert(real, "X")
		elseif T == "D8" then
			tstr = tstr .. "B"
			rstr = rstr .. "b"
			tinsert(real, "B")
		elseif T == "D16" then
			tstr = tstr .. "BB"
			rstr = rstr .. "bb"
			tinsert(real, "BB")
		elseif T == "M" then
			tstr = tstr .. T
			rstr = rstr .. T
			tinsert(real, T)
		elseif flags[T] then
			tstr = tstr .. "F"
			rstr = rstr .. "f"
			tinsert(real, T)
		else
			tstr = tstr .. "R"
			rstr = rstr .. T
			tinsert(real, T)
		end
	end
	return tstr, rstr, real
end

local function splitop(opn)
	local n, arg = smatch(opn, "^(.-) (.*)$")
	if arg then
		return n, arg_types(arg)
	else
		return opn
	end
end

-- function arg lookup table
local opfnargs = {
	R = ")",
	RR = ")",
	RM = ")",
	RB = ", b)",
	RBB = ", b2, b3)",
	M = ")",
	MR = ")",
	MB = ", b)",
	B = ", b)",
	X = ", b2, b3) local addr = pair(b3, b2)",
	F = ")",
	FX = ", b2, b3) local addr = pair(b3, b2)"
}

local opfnregs = {
	R = 1,
	RR = 2,
	RM = 2,
	RB = 1,
	RBB = 1,
	M = 1,
	MR = 2,
	MB = 1,
}

local regpartner = {
	B = "C",
	C = "B",
	D = "E",
	E = "D",
	H = "L",
	L = "H",
	M = "pair(s.H, s.L)",
	SP = "SP"
}
local regpair = {
	B = "pair(s.B, s.C)",
	D = "pair(s.D, s.E)",
	H = "pair(s.H, s.L)",
	M = "pair(s.H, s.L)", -- hax.
	SP = "s.SP",
}

local function genop(list, op, args, rargs, real)
	if not args then
		local opf = list[op]
		if not opf then return nil end
		return "function(s) "..opf.." end"
	end

	local opf = list[op .. " " .. rargs]
	if opf == false then
		return nil
	end
	if opf == nil then
		opf = list[op .. " " .. args]
	end

	if not opf then
		return nil
	end

	local str = "function(s"..opfnargs[args].." "
	local noregs = opfnregs[args]
	if noregs == 1 then
		local R = real[1]
		str = str .. opf:gsub("RP", tostring(regpair[R])):gsub("R", R)
		--str = str:gsub("PS(", fmt("spair(s, '%s', %s, ", ))
		str = str:gsub("([^S])P", "%1" .. tostring(regpartner[R]))
	elseif noregs == 2 then
		str = str .. opf:gsub("RP1", tostring(regpair[real[1]])):gsub("R1", real[1])
		str = str:gsub("RP2", tostring(regpair[real[2]])):gsub("R2", real[2])
	else
		str = str .. opf
	end
	if real[1] and flags[real[1]] then
		str = str:gsub("F", flags[real[1]])
	end
	return str .. " end"
end

-- Load our Op table
local optbl = dofile("gen/8080_ops.lua") -- file location is... questionable at best.

-- Parsing loop
for opb=0x00, 0xFF do
	local opn = opnames[opb]
	if opn then
		local n, args, rargs, real = splitop(opn)
		local gen = genop(optbl, n, args, rargs, real)
		if gen then
			print(fmt("\t[0x%02x] = %s, -- %s", opb, gen, opn))
		else
			print(fmt("\t-- Missing 0x%02x: %s (%s)", opb, opn, args))
		end
	else
		--print(fmt("\t-- Missing 0x%02x", opb))
	end
end

-- Post generation
io.write([[
}

return {
	inst_bitops = function(bit32)
		band, bor, bxor = bit32.band, bit32.bor, bit32.bxor
		rshift, lshift = bit32.rshift, bit32.lshift
	end,
	ops = ops
}
]])
