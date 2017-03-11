-- OP template table.
-- This is the actual logic.
-- It gets generated into actual usable ops by the generator.
-- Missing:
--  RLC, RRC, RAL, RAR, RIM
--  SHLD adr, LHLD adr
--  DAA, CMA, SIM
--  STA adr, STC, LDA adr
--  CMC, HLT, CMP R
--  RNZ, POP B,
--  CNZ adr, PUSH R
--  RST 0, RZ, RET
--  CZ adr, CALL adr, ACI D8
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
	["NOP"] = "",
	["LXI RBB"] = "s.R = b3 s.P = b2",
	["LXI SPbb"] = "s.R = pair(b3, b2)",
	["MVI RB"] = "s.R = b",
	["MOV RR"] = "s.R1 = s.R2",

	-- Addition and stuff.
	["INR R"] = "s.R = flaghandle(s, s.R + 1)",
	["INX R"] = "local t = s.P + 1 if a8(t) == 0 then R = a8(R + 1) end s.P = t",
	["ADD R"] = "s.A = flaghandle(s, s.A + s.R)",
	["ADI B"] = "s.A = flaghandle(s, s.A + b)",
	["ADC R"] = "s.A = flaghandle(s, s.A + s.R + (s.cy and 1 or 0))",
	["DAD R"] = "spair(s, 'H', 'L', pair(s.H, s.L) + RP)",

	-- Substraction and stuff.
	["SUB R"] = "s.A = flaghandle(s, s.A - s.R)",
	["SBB R"] = "s.A = flaghandle(s, s.A - s.R - (s.cy and 1 or 0))",
	["SBI B"] = "s.A = flaghandle(s, s.A - b)",
	["SUI B"] = "s.A = flaghandle(s, s.A - b - (s.cy and 1 or 0))",
	["DCR R"] = "s.R = flaghandle(s, s.R - 1)",
	["DCX R"] = "local t = s.P - 1 if a8(t) == 0xFF then R = a8(R - 1) end s.P = t",

	-- Bitops
	["ANA R"] = "s.A = flaghandle(s, band(s.A, s.R))",
	["ORA R"] = "s.A = flaghandle(s, bor(s.A, s.R))",
	["XRA R"] = "s.A = flaghandle(s, bxor(s.A, s.R))",
	["ANI B"] = "s.A = flaghandle(s, band(s.A, b))",
	["ORI B"] = "s.A = flaghandle(s, bor(s.A, b))",
	["XRI B"] = "s.A = flaghandle(s, bxor(s.A, b))",

	-- Jumps
	-- Probably something wrong here.
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
	
	-- Memory stuff.
	-- Special cases for the above.
	["STAX R"] = "s:setb(RP, s.A)",
	["LDAX R"] = "s.A = s:getb(RP)",

	["INR M"] = "local loc = RP s:setb(loc, flaghandlency(s, s:getb(loc) + 1))",
	["ADD M"] = "s.A = flaghandle(s, s.A + s:getb(RP))",
	["ADC M"] = "s.A = flaghandle(s, s.A + s:getb(RP) + (s.cy and 1 or 0))",
	["DCR M"] = "local loc = RP s:setb(loc, flaghandlency(s, s:getb(loc) - 1))",
	["SUB M"] = "s.A = flaghandle(s, s.A - s:getb(RP))",
	["SBB M"] = "s.A = flaghandle(s, s.A - s:getb(RP) - (s.cy and 1 or 0))",

	["ANA M"] = "s.A = flaghandle(s, band(s.A, s:getb(RP)))",
	["ORA M"] = "s.A = flaghandle(s, bor(s.A, s:getb(RP)))",
	["XRA M"] = "s.A = flaghandle(s, bxor(s.A, s:getb(RP)))",

	["MVI MB"] = "s:setb(RP, b)",
	["MOV MR"] = "s:setb(pair(s.H, s.L), s.R2)",
	["MOV RM"] = "s.R1 = s:getb(pair(s.H, s.L))",
}