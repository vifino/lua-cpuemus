-- OP template table.
-- This is the actual logic.
-- It gets generated into actual usable ops by the generator.
-- Missing:
-- HLT, EI, DI.
--
-- Not a lot!
return {

	-- Misc.

	["NOP"] = "",

	["LXI RBB"] = "s.R = b3 s.P = b2",
	["LXI SPbb"] = "s.R = pair(b3, b2)", -- unsure if correct

	["MVI RB"] = "s.R = b",
	["MVI MB"] = "s:setb(RP, b)",

	["MOV RR"] = "s.R1 = s.R2",
	["MOV MR"] = "s:setb(pair(s.H, s.L), s.R2)",
	["MOV RM"] = "s.R1 = s:getb(pair(s.H, s.L))",
	-- "MOV MM" is HLT

	["CMA"] = "s.A = bxor(s.A, 0xFF)",

	["STC"] = "s.cy = true",
	["CMC"] = "s.cy = not s.cy",

	["LDA X"] = "s.A = s:getb(addr)",
	["STA X"] = "s:setb(addr, s.A)",
	["LDAX R"] = "s.A = s:getb(RP)",
	["STAX R"] = "s:setb(RP, s.A)",
	["LHLD X"] = "s.L = s:getb(addr) s.H = s:getb(a8(addr + 1))",
	["SHLD X"] = "s:setb(addr, s.L) s:setb(a8(addr + 1), s.H)",

	["SPHL"] = "s.SP = pair(s.H, s.L)",

	["DAA"] =
		"if band(s.A, 0x0F) > 9 or s.ac then " ..
		" s.A, s.ac = addcda(s.A, 6) " ..
		"else s.ac = false end " ..
		"if band(s.A, 0xF0) > 0x90 or s.cy then " ..
		" local na, ncy = addcdn(s.A, 0x60) " ..
		" s.A = na s.cy = s.cy or ncy " ..
		"end " .. -- CY is not affected otherwise for whatever reason
		"s.A = flaghandle(s, s.A)", -- clean up remaining flags

	-- Increment/decrement (all forms). These don't do anything with carry/aux.carry flags.
	["INR R"] = "s.R = flaghandle(s, s.R + 1)",
	["INR M"] = "local loc = RP s:setb(loc, flaghandle(s, s:getb(loc) + 1))",
	["INX R"] = "local t = a8(s.P + 1) if t == 0 then s.R = a8(s.R + 1) end s.P = t",

	["DCR R"] = "s.R = flaghandle(s, s.R - 1)",
	["DCR M"] = "local loc = RP s:setb(loc, flaghandle(s, s:getb(loc) - 1))",
	["DCX R"] = "local t = a8(s.P - 1) if t == 0xFF then s.R = a8(s.R - 1) end s.P = t",

	-- Addition and stuff.
	["ADD R"] = "s.A = flaghandle(s, applyb(s, addcdb(s.A, s.R)))",
	["ADD M"] = "s.A = flaghandle(s, applyb(s, addcdb(s.A, s:getb(RP))))",

	["ADC R"] = "s.A = flaghandle(s, applyb(s, addcdb(s.A, s.R, s.cy)))",
	["ADC M"] = "s.A = flaghandle(s, applyb(s, addcdb(s.A, s:getb(RP), s.cy)))",

	["ADI B"] = "s.A = flaghandle(s, applyb(s, addcdb(s.A, b)))",
	["ACI B"] = "s.A = flaghandle(s, applyb(s, addcdb(s.A, b, s.cy)))",

	["DAD R"] = "spair(s, 'H', 'L', pair(s.H, s.L) + RP)",

	-- Subtraction and stuff.
	["SUB R"] = "s.A = flaghandle(s, applyb(s, subcdb(s.A, s.R)))",
	["SBB R"] = "s.A = flaghandle(s, applyb(s, subcdb(s.A, s.R, s.cy)))",
	["SUB M"] = "s.A = flaghandle(s, applyb(s, subcdb(s.A, s:getb(RP))))",
	["SBB M"] = "s.A = flaghandle(s, applyb(s, subcdb(s.A, s:getb(RP), s.cy)))",

	["SUI B"] = "s.A = flaghandle(s, applyb(s, subcdb(s.A, b)))",
	["SBI B"] = "s.A = flaghandle(s, applyb(s, subcdb(s.A, b, s.cy)))",

	-- Comparisons
	["CPI B"] = "flaghandle(s, applyb(s, subcdb(s.A, b)))",
	["CMP R"] = "flaghandle(s, applyb(s, subcdb(s.A, s.R)))",
	["CMP M"] = "flaghandle(s, applyb(s, subcdb(s.A, s:getb(RP))))",

	-- Bitops

	["ANA R"] = "s.A = flaghandle(s, band(s.A, s.R)) s.cy = false",
	["ANA M"] = "s.A = flaghandle(s, band(s.A, s:getb(RP))) s.cy = false",

	["ORA R"] = "s.A = flaghandle(s, bor(s.A, s.R)) s.cy = false",
	["ORA M"] = "s.A = flaghandle(s, bor(s.A, s:getb(RP))) s.cy = false",

	["XRA R"] = "s.A = flaghandle(s, bxor(s.A, s.R)) s.cy = false",
	["XRA M"] = "s.A = flaghandle(s, bxor(s.A, s:getb(RP))) s.cy = false",

	["ANI B"] = "s.A = flaghandle(s, band(s.A, b)) s.cy = false",
	["ORI B"] = "s.A = flaghandle(s, bor(s.A, b)) s.cy = false",
	["XRI B"] = "s.A = flaghandle(s, bxor(s.A, b)) s.cy = false",

	-- Rotation bitops

	["RLC"] = "s.A, s.cy = b_lsft(s.A) if s.cy then s.A = bor(s.A, 1) end",
	["RRC"] = "s.A, s.cy = b_rsft(s.A) if s.cy then s.A = bor(s.A, 128) end",

	["RAL"] = "local na, nc = b_lsft(s.A) if s.cy then s.A = bor(na, 1) else s.A = na end s.cy = nc",
	["RAR"] = "local na, nc = b_rsft(s.A) if s.cy then s.A = bor(na, 128) else s.A = na end s.cy = nc",

	-- Jumps / Calls

	["PCHL"] = "s.PC = pair(s.H, s.L) return true",
	["JMP X"] = "s.PC = addr return true",
	["JMP FX"] = "if F then s.PC = addr return true end",

	["CALL X"] = "s_call(s, addr) return true",
	["CALL FX"] = "if F then s_call(s, addr) return true end",

	["RET"] = "s.PC = s_pop16(s) return true",
	["RET F"] = "if F then s.PC = s_pop16(s) return true end",

	-- RSTs

	["RST 0"] = "s_call(s, 0x00) return true",
	["RST 1"] = "s_call(s, 0x08) return true",
	["RST 2"] = "s_call(s, 0x10) return true",
	["RST 3"] = "s_call(s, 0x18) return true",
	["RST 4"] = "s_call(s, 0x20) return true",
	["RST 5"] = "s_call(s, 0x28) return true",
	["RST 6"] = "s_call(s, 0x30) return true",
	["RST 7"] = "s_call(s, 0x38) return true",

	-- PUSH/POP

	["PUSH R"] = "s_push8(s, s.R) s_push8(s, s.P)",
	["POP R"] = "s.P = s_pop8(s) s.R = s_pop8(s)",

	["PUSH PSW"] = "s_push8(s, encode_psw(s)) s_push8(s, s.A)",
	["POP PSW"] = "s.A = s_pop8(s) decode_psw(s, s_pop8(s))",

	-- Exchangers

	["XCHG"] = "local oh, ol = s.H, s.L s.H = s.D s.D = oh s.L = s.E s.E = ol",
	["XTHL"] = "local oh, ol, a2 = s.H, s.L, band(s.SP + 1, 0xFFFF) s.L = s:getb(s.SP) s:setb(s.SP, ol) s.H = s:getb(a2) s:setb(a2, oh)",

	-- IO
	
	["IN B"] = "s.A = s:iogb(bor(s.B * 256, b))",
	["OUT B"] = "s:iosb(bor(s.B * 256, b), s.A)",

	-- Interrupts

	["HLT"] = "s.halted = true",
	["EI"] = "s.int_enable = true",
	["DI"] = "s.int_enable = false",
}
