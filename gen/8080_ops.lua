-- OP template table.
-- This is the actual logic.
-- It gets generated into actual usable ops by the generator.
-- Missing:
-- (maybe out of date??)
--  RLC, RRC, RAL, RAR
--  SHLD adr, LHLD adr
--  STA adr, STC, LDA adr
--  CMC, HLT, CMP R
--  RNZ, POP B,
--  CNZ adr, PUSH R
--  RST 0, RZ, RET
--  CZ adr, CALL adr
--  RST 1, RNC, POP R
--  RST 2, RC, IN D8,
--  CC adr, RST 3, RPO
--  XTHL, CPO adr
--  RST 4, RPE, RCHL
--  XCHG, CPE adr, RST 5
--  RP, POP PSW, DI
--  CP adr, PUSH PSW, RST 6
--  RM, SPHL
--  EI, CM adr, CPI D8, RST 7
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

	["STAX R"] = "s:setb(RP, s.A)",
	["LDAX R"] = "s.A = s:getb(RP)",

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
	["INX R"] = "local t = s.P + 1 if a8(t) == 0 then R = a8(R + 1) end s.P = t",

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

	-- Jumps
	-- Probably something wrong here.
	-- (No, it should be fine. Just remember to return true if
	--  a call occurs in the conditional calls. -20kdc)
	["JMP X"] = "s.PC = addr - 3",
	["JNZ X"] = "if s.z == false then s.PC = addr - 3 end",
	["JZ X"] = "if s.z == true then s.PC = addr - 3 end",
	["JNC X"] = "if s.cy == false then s.PC = addr - 3 end",
	["JC X"] = "if s.cy == true then s.PC = addr - 3 end",	
	["JPO X"] = "if s.p == true then s.PC = addr - 3 end",	
	["JPE X"] = "if s.p == false then s.PC = addr - 3 end",	
	["JP X"] = "if s.s == true then s.PC = addr - 3 end",
	["JM X"] = "if s.s == false then s.PC = addr - 3 end",
	["PCHL"] = "s.PC = pair(s.H, s.L) - 1",
}
