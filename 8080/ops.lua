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

local function flaghandle(inst, res)
	res = band(res, 0xFF)
	inst.z = (res == 0) -- is zero
	inst.s = (band(res, 0x80) ~= 0) -- sign flag, if bit 7 set
	inst.p = parity(res, 7)
	return res
end

local function addcda(a, b)
	local b1 = (a % 16) + (b % 16)
	return band(a + b, 0xFF), b1 > 0x0F
end
local function addcdn(a, b)
	return band(a + b, 0xFF), (a + b) > 0xFF
end
local function addcdb(a, b)
	local b1 = (a % 16) + (b % 16)
	return band(a + b, 0xFF), b1 > 0x0F, (a + b) > 0xFF
end

local function subcda(a, b)
	local b1 = (a % 16) - (b % 16)
	return band(a - b, 0xFF), b1 > 0x0F
end
local function subcdn(a, b)
	return band(a - b, 0xFF), (a - b) < 0
end
local function subcdb(a, b)
	local b1 = (a % 16) + (b % 16)
	return band(a - b, 0xFF), b1 > 0x0F, (a - b) < 0
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

local function s_call(s, t, l)
	s_push16(s, band(s.PC + l, 0xFFFF))
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

local function decode_psw(s)
	s.cy = band(s, 1) ~= 0
	s.p = band(s, 4) ~= 0
	s.ac = band(s, 16) ~= 0
	s.z = band(s, 64) ~= 0
	s.s = band(s, 128) ~= 0
end

local function b_lsft(a)
	local n = band(a * 2, 0xFF)
	return n, band(a, 0x80)
end

local function b_rsft(a)
	local n = band(math.floor(a / 2), 0x7F)
	return n, band(a, 1)
end

-- OPS
local ops = {
	[0x00] = function(s)  end, -- NOP
	[0x01] = function(s, b2, b3) s.B = b3 s.C = b2 end, -- LXI B,D16
	[0x02] = function(s) s:setb(pair(s.B, s.C), s.A) end, -- STAX B
	[0x03] = function(s) local t = a8(s.C + 1) if t == 0 then s.B = a8(s.B + 1) end s.C = t end, -- INX B
	[0x04] = function(s) s.B = flaghandle(s, s.B + 1) end, -- INR B
	[0x05] = function(s) s.B = flaghandle(s, s.B - 1) end, -- DCR B
	[0x06] = function(s, b) s.B = b end, -- MVI B, D8
	[0x07] = function(s) s.A, s.cy = b_lsft(s.A) if s.cy then s.A = bor(s.A, 1) end end, -- RLC
	[0x08] = function(s)  end, -- NOP
	[0x09] = function(s) spair(s, 'H', 'L', pair(s.H, s.L) + pair(s.B, s.C)) end, -- DAD B
	[0x0a] = function(s) s.A = s:getb(pair(s.B, s.C)) end, -- LDAX B
	[0x0b] = function(s) local t = a8(s.C - 1) if t == 0xFF then s.B = a8(s.B - 1) end s.C = t end, -- DCX B
	[0x0c] = function(s) s.C = flaghandle(s, s.C + 1) end, -- INR C
	[0x0d] = function(s) s.C = flaghandle(s, s.C - 1) end, -- DCR C
	[0x0e] = function(s, b) s.C = b end, -- MVI C,D8
	[0x0f] = function(s) s.A, s.cy = b_rsft(s.A) if s.cy then s.A = bor(s.A, 128) end end, -- RRC
	[0x10] = function(s)  end, -- NOP
	[0x11] = function(s, b2, b3) s.D = b3 s.E = b2 end, -- LXI D,D16
	[0x12] = function(s) s:setb(pair(s.D, s.E), s.A) end, -- STAX D
	[0x13] = function(s) local t = a8(s.E + 1) if t == 0 then s.D = a8(s.D + 1) end s.E = t end, -- INX D
	[0x14] = function(s) s.D = flaghandle(s, s.D + 1) end, -- INR D
	[0x15] = function(s) s.D = flaghandle(s, s.D - 1) end, -- DCR D
	[0x16] = function(s, b) s.D = b end, -- MVI D, D8
	[0x17] = function(s) local na, nc = b_lsft(s.A) if s.cy then s.A = bor(na, 1) else s.A = na end s.cy = nc end, -- RAL
	[0x18] = function(s)  end, -- NOP
	[0x19] = function(s) spair(s, 'H', 'L', pair(s.H, s.L) + pair(s.D, s.E)) end, -- DAD D
	[0x1a] = function(s) s.A = s:getb(pair(s.D, s.E)) end, -- LDAX D
	[0x1b] = function(s) local t = a8(s.E - 1) if t == 0xFF then s.D = a8(s.D - 1) end s.E = t end, -- DCX D
	[0x1c] = function(s) s.E = flaghandle(s, s.E + 1) end, -- INR E
	[0x1d] = function(s) s.E = flaghandle(s, s.E - 1) end, -- DCR E
	[0x1e] = function(s, b) s.E = b end, -- MVI E,D8
	[0x1f] = function(s) local na, nc = b_rsft(s.A) if s.cy then s.A = bor(na, 128) else s.A = na end s.cy = nc end, -- RAR
	[0x20] = function(s)  end, -- NOP
	[0x21] = function(s, b2, b3) s.H = b3 s.L = b2 end, -- LXI H,D16
	[0x22] = function(s, b2, b3) local addr = pair(b3, b2) s:setb(addr, s.L) s:setb(a8(addr + 1), s.H) end, -- SHLD adr
	[0x23] = function(s) local t = a8(s.L + 1) if t == 0 then s.H = a8(s.H + 1) end s.L = t end, -- INX H
	[0x24] = function(s) s.H = flaghandle(s, s.H + 1) end, -- INR H
	[0x25] = function(s) s.H = flaghandle(s, s.H - 1) end, -- DCR H
	[0x26] = function(s, b) s.H = b end, -- MVI H,D8
	[0x27] = function(s) if band(s.A, 0x0F) > 9 or s.ac then  s.A, s.ac = addcda(s.A, 6) else s.ac = false end if band(s.A, 0xF0) > 0x90 or s.cy then  local na, ncy = addcdn(s.A, 0x60)  s.A = na s.cy = s.cy or ncy end s.A = flaghandle(s, s.A) end, -- DAA
	[0x28] = function(s)  end, -- NOP
	[0x29] = function(s) spair(s, 'H', 'L', pair(s.H, s.L) + pair(s.H, s.L)) end, -- DAD H
	[0x2a] = function(s, b2, b3) local addr = pair(b3, b2) s.L = s:getb(addr) s.H = s:getb(a8(addr + 1)) end, -- LHLD adr
	[0x2b] = function(s) local t = a8(s.L - 1) if t == 0xFF then s.H = a8(s.H - 1) end s.L = t end, -- DCX H
	[0x2c] = function(s) s.L = flaghandle(s, s.L + 1) end, -- INR L
	[0x2d] = function(s) s.L = flaghandle(s, s.L - 1) end, -- DCR L
	[0x2e] = function(s, b) s.L = b end, -- MVI L, D8
	[0x2f] = function(s) s.A = bxor(s.A, 0xFF) end, -- CMA
	[0x30] = function(s)  end, -- NOP
	[0x31] = function(s, b2, b3) s.SP = pair(b3, b2) end, -- LXI SP, D16
	[0x32] = function(s, b2, b3) local addr = pair(b3, b2) s:setb(addr, s.A) end, -- STA adr
	[0x33] = function(s) local t = a8(s.SP + 1) if t == 0 then s.SP = a8(s.SP + 1) end s.SP = t end, -- INX SP
	[0x34] = function(s) local loc = pair(s.H, s.L) s:setb(loc, flaghandle(s, s:getb(loc) + 1)) end, -- INR M
	[0x35] = function(s) local loc = pair(s.H, s.L) s:setb(loc, flaghandle(s, s:getb(loc) - 1)) end, -- DCR M
	[0x36] = function(s, b) s:setb(pair(s.H, s.L), b) end, -- MVI M,D8
	[0x37] = function(s) s.cy = true end, -- STC
	[0x38] = function(s)  end, -- NOP
	[0x39] = function(s) spair(s, 'H', 'L', pair(s.H, s.L) + s.SP) end, -- DAD SP
	[0x3a] = function(s, b2, b3) local addr = pair(b3, b2) s.A = s:getb(addr) end, -- LDA adr
	[0x3b] = function(s) local t = a8(s.SP - 1) if t == 0xFF then s.SP = a8(s.SP - 1) end s.SP = t end, -- DCX SP
	[0x3c] = function(s) s.A = flaghandle(s, s.A + 1) end, -- INR A
	[0x3d] = function(s) s.A = flaghandle(s, s.A - 1) end, -- DCR A
	[0x3e] = function(s, b) s.A = b end, -- MVI A,D8
	[0x3f] = function(s) s.cy = not s.cy end, -- CMC
	[0x40] = function(s) s.B = s.B end, -- MOV B,B
	[0x41] = function(s) s.B = s.C end, -- MOV B,C
	[0x42] = function(s) s.B = s.D end, -- MOV B,D
	[0x43] = function(s) s.B = s.E end, -- MOV B,E
	[0x44] = function(s) s.B = s.H end, -- MOV B,H
	[0x45] = function(s) s.B = s.L end, -- MOV B,L
	[0x46] = function(s) s.B = s:getb(pair(s.H, s.L)) end, -- MOV B,M
	[0x47] = function(s) s.B = s.A end, -- MOV B,A
	[0x48] = function(s) s.C = s.B end, -- MOV C,B
	[0x49] = function(s) s.C = s.C end, -- MOV C,C
	[0x4a] = function(s) s.C = s.D end, -- MOV C,D
	[0x4b] = function(s) s.C = s.E end, -- MOV C,E
	[0x4c] = function(s) s.C = s.H end, -- MOV C,H
	[0x4d] = function(s) s.C = s.L end, -- MOV C,L
	[0x4e] = function(s) s.C = s:getb(pair(s.H, s.L)) end, -- MOV C,M
	[0x4f] = function(s) s.C = s.A end, -- MOV C,A
	[0x50] = function(s) s.D = s.B end, -- MOV D,B
	[0x51] = function(s) s.D = s.C end, -- MOV D,C
	[0x52] = function(s) s.D = s.D end, -- MOV D,D
	[0x53] = function(s) s.D = s.E end, -- MOV D,E
	[0x54] = function(s) s.D = s.H end, -- MOV D,H
	[0x55] = function(s) s.D = s.L end, -- MOV D,L
	[0x56] = function(s) s.D = s:getb(pair(s.H, s.L)) end, -- MOV D,M
	[0x57] = function(s) s.D = s.A end, -- MOV D,A
	[0x58] = function(s) s.E = s.B end, -- MOV E,B
	[0x59] = function(s) s.E = s.C end, -- MOV E,C
	[0x5a] = function(s) s.E = s.D end, -- MOV E,D
	[0x5b] = function(s) s.E = s.E end, -- MOV E,E
	[0x5c] = function(s) s.E = s.H end, -- MOV E,H
	[0x5d] = function(s) s.E = s.L end, -- MOV E,L
	[0x5e] = function(s) s.E = s:getb(pair(s.H, s.L)) end, -- MOV E,M
	[0x5f] = function(s) s.E = s.A end, -- MOV E,A
	[0x60] = function(s) s.H = s.B end, -- MOV H,B
	[0x61] = function(s) s.H = s.C end, -- MOV H,C
	[0x62] = function(s) s.H = s.D end, -- MOV H,D
	[0x63] = function(s) s.H = s.E end, -- MOV H,E
	[0x64] = function(s) s.H = s.H end, -- MOV H,H
	[0x65] = function(s) s.H = s.L end, -- MOV H,L
	[0x66] = function(s) s.H = s:getb(pair(s.H, s.L)) end, -- MOV H,M
	[0x67] = function(s) s.H = s.A end, -- MOV H,A
	[0x68] = function(s) s.L = s.B end, -- MOV L,B
	[0x69] = function(s) s.L = s.C end, -- MOV L,C
	[0x6a] = function(s) s.L = s.D end, -- MOV L,D
	[0x6b] = function(s) s.L = s.E end, -- MOV L,E
	[0x6c] = function(s) s.L = s.H end, -- MOV L,H
	[0x6d] = function(s) s.L = s.L end, -- MOV L,L
	[0x6e] = function(s) s.L = s:getb(pair(s.H, s.L)) end, -- MOV L,M
	[0x6f] = function(s) s.L = s.A end, -- MOV L,A
	[0x70] = function(s) s:setb(pair(s.H, s.L), s.B) end, -- MOV M,B
	[0x71] = function(s) s:setb(pair(s.H, s.L), s.C) end, -- MOV M,C
	[0x72] = function(s) s:setb(pair(s.H, s.L), s.D) end, -- MOV M,D
	[0x73] = function(s) s:setb(pair(s.H, s.L), s.E) end, -- MOV M,E
	[0x74] = function(s) s:setb(pair(s.H, s.L), s.H) end, -- MOV M,H
	[0x75] = function(s) s:setb(pair(s.H, s.L), s.L) end, -- MOV M,L
	-- Missing 0x76: HLT (nil)
	[0x77] = function(s) s:setb(pair(s.H, s.L), s.A) end, -- MOV M,A
	[0x78] = function(s) s.A = s.B end, -- MOV A,B
	[0x79] = function(s) s.A = s.C end, -- MOV A,C
	[0x7a] = function(s) s.A = s.D end, -- MOV A,D
	[0x7b] = function(s) s.A = s.E end, -- MOV A,E
	[0x7c] = function(s) s.A = s.H end, -- MOV A,H
	[0x7d] = function(s) s.A = s.L end, -- MOV A,L
	[0x7e] = function(s) s.A = s:getb(pair(s.H, s.L)) end, -- MOV A,M
	[0x7f] = function(s) s.A = s.A end, -- MOV A,A
	[0x80] = function(s) s.A = flaghandle(s, applyb(s, addcdb(s.A, s.B))) end, -- ADD B
	[0x81] = function(s) s.A = flaghandle(s, applyb(s, addcdb(s.A, s.C))) end, -- ADD C
	[0x82] = function(s) s.A = flaghandle(s, applyb(s, addcdb(s.A, s.D))) end, -- ADD D
	[0x83] = function(s) s.A = flaghandle(s, applyb(s, addcdb(s.A, s.E))) end, -- ADD E
	[0x84] = function(s) s.A = flaghandle(s, applyb(s, addcdb(s.A, s.H))) end, -- ADD H
	[0x85] = function(s) s.A = flaghandle(s, applyb(s, addcdb(s.A, s.L))) end, -- ADD L
	[0x86] = function(s) s.A = flaghandle(s, applyb(s, addcdb(s.A, s:getb(pair(s.H, s.L))))) end, -- ADD M
	[0x87] = function(s) s.A = flaghandle(s, applyb(s, addcdb(s.A, s.A))) end, -- ADD A
	[0x88] = function(s) s.A = flaghandle(s, applyb(s, addcdb(s.A, s.B, s.cy))) end, -- ADC B
	[0x89] = function(s) s.A = flaghandle(s, applyb(s, addcdb(s.A, s.C, s.cy))) end, -- ADC C
	[0x8a] = function(s) s.A = flaghandle(s, applyb(s, addcdb(s.A, s.D, s.cy))) end, -- ADC D
	[0x8b] = function(s) s.A = flaghandle(s, applyb(s, addcdb(s.A, s.E, s.cy))) end, -- ADC E
	[0x8c] = function(s) s.A = flaghandle(s, applyb(s, addcdb(s.A, s.H, s.cy))) end, -- ADC H
	[0x8d] = function(s) s.A = flaghandle(s, applyb(s, addcdb(s.A, s.L, s.cy))) end, -- ADC L
	[0x8e] = function(s) s.A = flaghandle(s, applyb(s, addcdb(s.A, s:getb(pair(s.H, s.L)), s.cy))) end, -- ADC M
	[0x8f] = function(s) s.A = flaghandle(s, applyb(s, addcdb(s.A, s.A, s.cy))) end, -- ADC A
	[0x90] = function(s) s.A = flaghandle(s, applyb(s, subcdb(s.A, s.B))) end, -- SUB B
	[0x91] = function(s) s.A = flaghandle(s, applyb(s, subcdb(s.A, s.C))) end, -- SUB C
	[0x92] = function(s) s.A = flaghandle(s, applyb(s, subcdb(s.A, s.D))) end, -- SUB D
	[0x93] = function(s) s.A = flaghandle(s, applyb(s, subcdb(s.A, s.E))) end, -- SUB E
	[0x94] = function(s) s.A = flaghandle(s, applyb(s, subcdb(s.A, s.H))) end, -- SUB H
	[0x95] = function(s) s.A = flaghandle(s, applyb(s, subcdb(s.A, s.L))) end, -- SUB L
	[0x96] = function(s) s.A = flaghandle(s, applyb(s, subcdb(s.A, s:getb(pair(s.H, s.L))))) end, -- SUB M
	[0x97] = function(s) s.A = flaghandle(s, applyb(s, subcdb(s.A, s.A))) end, -- SUB A
	[0x98] = function(s) s.A = flaghandle(s, applyb(s, subcdb(s.A, s.B, s.cy))) end, -- SBB B
	[0x99] = function(s) s.A = flaghandle(s, applyb(s, subcdb(s.A, s.C, s.cy))) end, -- SBB C
	[0x9a] = function(s) s.A = flaghandle(s, applyb(s, subcdb(s.A, s.D, s.cy))) end, -- SBB D
	[0x9b] = function(s) s.A = flaghandle(s, applyb(s, subcdb(s.A, s.E, s.cy))) end, -- SBB E
	[0x9c] = function(s) s.A = flaghandle(s, applyb(s, subcdb(s.A, s.H, s.cy))) end, -- SBB H
	[0x9d] = function(s) s.A = flaghandle(s, applyb(s, subcdb(s.A, s.L, s.cy))) end, -- SBB L
	[0x9e] = function(s) s.A = flaghandle(s, applyb(s, subcdb(s.A, s:getb(pair(s.H, s.L)), s.cy))) end, -- SBB M
	[0x9f] = function(s) s.A = flaghandle(s, applyb(s, subcdb(s.A, s.A, s.cy))) end, -- SBB A
	[0xa0] = function(s) s.A = flaghandle(s, band(s.A, s.B)) s.cy = false end, -- ANA B
	[0xa1] = function(s) s.A = flaghandle(s, band(s.A, s.C)) s.cy = false end, -- ANA C
	[0xa2] = function(s) s.A = flaghandle(s, band(s.A, s.D)) s.cy = false end, -- ANA D
	[0xa3] = function(s) s.A = flaghandle(s, band(s.A, s.E)) s.cy = false end, -- ANA E
	[0xa4] = function(s) s.A = flaghandle(s, band(s.A, s.H)) s.cy = false end, -- ANA H
	[0xa5] = function(s) s.A = flaghandle(s, band(s.A, s.L)) s.cy = false end, -- ANA L
	[0xa6] = function(s) s.A = flaghandle(s, band(s.A, s:getb(pair(s.H, s.L)))) s.cy = false end, -- ANA M
	[0xa7] = function(s) s.A = flaghandle(s, band(s.A, s.A)) s.cy = false end, -- ANA A
	[0xa8] = function(s) s.A = flaghandle(s, bxor(s.A, s.B)) s.cy = false end, -- XRA B
	[0xa9] = function(s) s.A = flaghandle(s, bxor(s.A, s.C)) s.cy = false end, -- XRA C
	[0xaa] = function(s) s.A = flaghandle(s, bxor(s.A, s.D)) s.cy = false end, -- XRA D
	[0xab] = function(s) s.A = flaghandle(s, bxor(s.A, s.E)) s.cy = false end, -- XRA E
	[0xac] = function(s) s.A = flaghandle(s, bxor(s.A, s.H)) s.cy = false end, -- XRA H
	[0xad] = function(s) s.A = flaghandle(s, bxor(s.A, s.L)) s.cy = false end, -- XRA L
	[0xae] = function(s) s.A = flaghandle(s, bxor(s.A, s:getb(pair(s.H, s.L)))) s.cy = false end, -- XRA M
	[0xaf] = function(s) s.A = flaghandle(s, bxor(s.A, s.A)) s.cy = false end, -- XRA A
	[0xb0] = function(s) s.A = flaghandle(s, bor(s.A, s.B)) s.cy = false end, -- ORA B
	[0xb1] = function(s) s.A = flaghandle(s, bor(s.A, s.C)) s.cy = false end, -- ORA C
	[0xb2] = function(s) s.A = flaghandle(s, bor(s.A, s.D)) s.cy = false end, -- ORA D
	[0xb3] = function(s) s.A = flaghandle(s, bor(s.A, s.E)) s.cy = false end, -- ORA E
	[0xb4] = function(s) s.A = flaghandle(s, bor(s.A, s.H)) s.cy = false end, -- ORA H
	[0xb5] = function(s) s.A = flaghandle(s, bor(s.A, s.L)) s.cy = false end, -- ORA L
	[0xb6] = function(s) s.A = flaghandle(s, bor(s.A, s:getb(pair(s.H, s.L)))) s.cy = false end, -- ORA M
	[0xb7] = function(s) s.A = flaghandle(s, bor(s.A, s.A)) s.cy = false end, -- ORA A
	[0xb8] = function(s) flaghandle(s, applyb(s, subcdb(s.A, s.B))) end, -- CMP B
	[0xb9] = function(s) flaghandle(s, applyb(s, subcdb(s.A, s.C))) end, -- CMP C
	[0xba] = function(s) flaghandle(s, applyb(s, subcdb(s.A, s.D))) end, -- CMP D
	[0xbb] = function(s) flaghandle(s, applyb(s, subcdb(s.A, s.E))) end, -- CMP E
	[0xbc] = function(s) flaghandle(s, applyb(s, subcdb(s.A, s.H))) end, -- CMP H
	[0xbd] = function(s) flaghandle(s, applyb(s, subcdb(s.A, s.L))) end, -- CMP L
	[0xbe] = function(s) flaghandle(s, applyb(s, subcdb(s.A, s:getb(pair(s.H, s.L))))) end, -- CMP M
	[0xbf] = function(s) flaghandle(s, applyb(s, subcdb(s.A, s.A))) end, -- CMP A
	[0xc0] = function(s) if s.z == false then s.PC = s_pop16(s) return true end end, -- RET !FZ
	[0xc1] = function(s) s.C = s_pop8(s) s.B = s_pop8(s) end, -- POP B
	[0xc2] = function(s, b2, b3) local addr = pair(b3, b2) if s.z == false then s.PC = addr return true end end, -- JMP !FZ adr
	[0xc3] = function(s, b2, b3) local addr = pair(b3, b2) s.PC = addr return true end, -- JMP adr
	[0xc4] = function(s, b2, b3) local addr = pair(b3, b2) if s.z == false then s_call(s, addr, 3) return true end end, -- CALL !FZ adr
	[0xc5] = function(s) s_push8(s, s.B) s_push8(s, s.C) end, -- PUSH B
	[0xc6] = function(s, b) s.A = flaghandle(s, applyb(s, addcdb(s.A, b))) end, -- ADI D8
	[0xc7] = function(s) s_call(s, 0x00, 1) return true end, -- RST 0
	[0xc8] = function(s) if s.z == true then s.PC = s_pop16(s) return true end end, -- RET FZ
	[0xc9] = function(s) s.PC = s_pop16(s) return true end, -- RET
	[0xca] = function(s, b2, b3) local addr = pair(b3, b2) if s.z == true then s.PC = addr return true end end, -- JMP FZ adr
	[0xcb] = function(s, b2, b3) local addr = pair(b3, b2) s.PC = addr return true end, -- JMP adr
	[0xcc] = function(s, b2, b3) local addr = pair(b3, b2) if s.z == true then s_call(s, addr, 3) return true end end, -- CALL FZ adr
	[0xcd] = function(s, b2, b3) local addr = pair(b3, b2) s_call(s, addr, 3) return true end, -- CALL adr
	[0xce] = function(s, b) s.A = flaghandle(s, applyb(s, addcdb(s.A, b, s.cy))) end, -- ACI D8
	[0xcf] = function(s) s_call(s, 0x08, 1) return true end, -- RST 1
	[0xd0] = function(s) if s.cy == false then s.PC = s_pop16(s) return true end end, -- RET !FC
	[0xd1] = function(s) s.E = s_pop8(s) s.D = s_pop8(s) end, -- POP D
	[0xd2] = function(s, b2, b3) local addr = pair(b3, b2) if s.cy == false then s.PC = addr return true end end, -- JMP !FC adr
	[0xd3] = function(s, b) s:iosb(bor(s.B * 256, b), s.A) end, -- OUT D8
	[0xd4] = function(s, b2, b3) local addr = pair(b3, b2) if s.cy == false then s_call(s, addr, 3) return true end end, -- CALL !FC adr
	[0xd5] = function(s) s_push8(s, s.D) s_push8(s, s.E) end, -- PUSH D
	[0xd6] = function(s, b) s.A = flaghandle(s, applyb(s, subcdb(s.A, b))) end, -- SUI D8
	[0xd7] = function(s) s_call(s, 0x10, 1) return true end, -- RST 2
	[0xd8] = function(s) if s.cy == true then s.PC = s_pop16(s) return true end end, -- RET FC
	[0xd9] = function(s) s.PC = s_pop16(s) return true end, -- RET
	[0xda] = function(s, b2, b3) local addr = pair(b3, b2) if s.cy == true then s.PC = addr return true end end, -- JMP FC adr
	[0xdb] = function(s, b) s.A = s:iogb(bor(s.B * 256, b)) end, -- IN D8
	[0xdc] = function(s, b2, b3) local addr = pair(b3, b2) if s.cy == true then s_call(s, addr, 3) return true end end, -- CALL FC adr
	[0xdd] = function(s, b2, b3) local addr = pair(b3, b2) s_call(s, addr, 3) return true end, -- CALL adr
	[0xde] = function(s, b) s.A = flaghandle(s, applyb(s, subcdb(s.A, b, s.cy))) end, -- SBI D8
	[0xdf] = function(s) s_call(s, 0x18, 1) return true end, -- RST 3
	[0xe0] = function(s) if s.p == false then s.PC = s_pop16(s) return true end end, -- RET !FPE
	[0xe1] = function(s) s.L = s_pop8(s) s.H = s_pop8(s) end, -- POP H
	[0xe2] = function(s, b2, b3) local addr = pair(b3, b2) if s.p == false then s.PC = addr return true end end, -- JMP !FPE adr
	[0xe3] = function(s) local oh, ol, a2 = s.H, s.L, band(s.SP + 1, 0xFFFF) s.L = s:getb(s.SP) s:setb(s.SP, ol) s.H = s:getb(a2) s:setb(a2, oh) end, -- XTHL
	[0xe4] = function(s, b2, b3) local addr = pair(b3, b2) if s.p == false then s_call(s, addr, 3) return true end end, -- CALL !FPE adr
	[0xe5] = function(s) s_push8(s, s.H) s_push8(s, s.L) end, -- PUSH H
	[0xe6] = function(s, b) s.A = flaghandle(s, band(s.A, b)) s.cy = false end, -- ANI D8
	[0xe7] = function(s) s_call(s, 0x20, 1) return true end, -- RST 4
	[0xe8] = function(s) if s.p == true then s.PC = s_pop16(s) return true end end, -- RET FPE
	[0xe9] = function(s) s.PC = pair(s.H, s.L) return true end, -- PCHL
	[0xea] = function(s, b2, b3) local addr = pair(b3, b2) if s.p == true then s.PC = addr return true end end, -- JMP FPE adr
	[0xeb] = function(s) local oh, ol = s.H, s.L s.H = s.D s.D = oh s.L = s.E s.E = ol end, -- XCHG
	[0xec] = function(s, b2, b3) local addr = pair(b3, b2) if s.p == true then s_call(s, addr, 3) return true end end, -- CALL FPE adr
	[0xed] = function(s, b2, b3) local addr = pair(b3, b2) s_call(s, addr, 3) return true end, -- CALL adr
	[0xee] = function(s, b) s.A = flaghandle(s, bxor(s.A, b)) s.cy = false end, -- XRI D8
	[0xef] = function(s) s_call(s, 0x28, 1) return true end, -- RST 5
	[0xf0] = function(s) if s.s == false then s.PC = s_pop16(s) return true end end, -- RET !FS
	[0xf1] = function(s) s.A = s_pop8(s) decode_psw(s, s_pop8(s)) end, -- POP PSW
	[0xf2] = function(s, b2, b3) local addr = pair(b3, b2) if s.s == false then s.PC = addr return true end end, -- JMP !FS adr
	-- Missing 0xf3: DI (nil)
	[0xf4] = function(s, b2, b3) local addr = pair(b3, b2) if s.s == false then s_call(s, addr, 3) return true end end, -- CALL !FS adr
	[0xf5] = function(s) s_push8(s, encode_psw(s)) s_push8(s, s.A) end, -- PUSH PSW
	[0xf6] = function(s, b) s.A = flaghandle(s, bor(s.A, b)) s.cy = false end, -- ORI D8
	[0xf7] = function(s) s_call(s, 0x30, 1) return true end, -- RST 6
	[0xf8] = function(s) if s.s == true then s.PC = s_pop16(s) return true end end, -- RET FS
	[0xf9] = function(s) s.SP = pair(s.H, s.L) end, -- SPHL
	[0xfa] = function(s, b2, b3) local addr = pair(b3, b2) if s.s == true then s.PC = addr return true end end, -- JMP FS adr
	-- Missing 0xfb: EI (nil)
	[0xfc] = function(s, b2, b3) local addr = pair(b3, b2) if s.s == true then s_call(s, addr, 3) return true end end, -- CALL FS adr
	[0xfd] = function(s, b2, b3) local addr = pair(b3, b2) s_call(s, addr, 3) return true end, -- CALL adr
	[0xfe] = function(s, b) flaghandle(s, applyb(s, subcdb(s.A, b))) end, -- CPI D8
	[0xff] = function(s) s_call(s, 0x38, 1) return true end, -- RST 7
}
	
return {
	inst_bitops = function(bit32)
		band, bor, bxor = bit32.band, bit32.bor, bit32.bxor
		rshift, lshift = bit32.rshift, bit32.lshift
	end,
	ops = ops
}
