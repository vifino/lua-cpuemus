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
	return band(a, 0xFF)
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
local function parity(x, size)
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

local function flaghandle(inst, res, nocy)
	if not nocy then inst.cy = (res > 0xFF) end
	res = band(res, 0xFF)
	inst.z = (res == 0) -- is zero
	inst.s = (band(res, 0x80) ~= 0) -- sign flag, if bit 7 set
	inst.p = parity(res)
	return res
end

local function flaghandlency(inst, res)
	res = band(res, 0xFF)
	inst.z = (res == 0) -- is zero
	inst.s = (band(res, 0x80) ~= 0) -- sign flag, if bit 7 set
	inst.p = parity(res)
	return res
end

-- OPS
local ops = {
]])

-- Helpers
local T_ADDR = 1
local T_BYTE = 2
local function arg_types(argstr)
	local tstr, rstr = "", ""
	local real = {}
	for T in string.gmatch(argstr, '([^, ]+)') do
			if T == "adr" then
				tstr = tstr .. "X"
				rstr = rstr .. "x"
				tinsert(real, X)
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
	X = ", b2, b3) local addr = pair(b2, b3)"
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
	return str .. " end"
end

-- Load our Op table
local optbl = dofile("gen/8080_ops.lua") -- file location is... questionable at best.

-- Parsing loop
for opb=0x00, 0xFF do
	local opn = opnames[opb]
	if opn then
		local gen = genop(optbl, splitop(opn))
		if gen then
			print(fmt("\t[0x%02x] = %s, -- %s", opb, gen, opn))
		else
			print(fmt("\t-- Missing 0x%02x: %s", opb, opn))
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
