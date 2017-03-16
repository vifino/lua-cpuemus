-- Lua 8080 library.
-- Hopefully, one day, it'll work.

local _M = {}
_M.__index = _M

-- Local function cache.
local fmt = string.format
local bnot, band, bor, bxor, lshift, rshift
local pcall = pcall

-- Lookup tables. Hallelujah.
-- Big as hell, so not stored here.
local opbs = require("8080.opbs")
_M.opbs = opbs
local opnames = require("8080.opnames")
_M.opnames = opnames

-- Actual OP implementations, also in a table.
local opslib = require("8080.ops")
local ops = opslib.ops
_M.ops = ops

local function assert_bitfn(bit, name)
	assert(bit[name], "8080: Did not find function "..name.." in bitlib. We need it.")
end
function _M.set_bit32(bitlib)
	assert_bitfn(bitlib, "bnot") bnot = bitlib.bnot
	assert_bitfn(bitlib, "band") band = bitlib.band
	assert_bitfn(bitlib, "bor") bor = bitlib.bor
	assert_bitfn(bitlib, "bxor") bxor = bitlib.bxor
	assert_bitfn(bitlib, "lshift") lshift = bitlib.lshift
	assert_bitfn(bitlib, "rshift") rshift = bitlib.rshift
	opslib.inst_bitops(bitlib)
	_M.bit32 = bitlib
end

-- Helpers
local function fmtaddr(a, b)
	return fmt("$%02x%02X", a, b)
end

function _M.disasm(inst, pco)
	local pc = pco
	local b = inst:getb(pc)
	local l = opbs[b][1]
	local name = opnames[b]
	if name == nil then
		return pco+1, fmt("%04x ???", pco)
	end
	local name = name:gsub("adr", function()
		local addr = fmtaddr(inst:getb(pc+2), inst:getb(pc+1))
		pc = pc + 2
		return addr
	end):gsub("D8", function()
		pc = pc + 1
		return fmt("0x%02x", inst:getb(pc))
	end):gsub("D16", function()
		local res = fmt("0x%02x%02x", inst:getb(pc+2), inst:getb(pc+1))
		pc = pc + 2
		return res
	end)
	return pco+l, fmt("%04x %s", pco, name)
end

local function callop(inst, op, p1, p2)
	local opfn = ops[op]
	if opfn == nil then
		error(fmt("NYI OP: 0x%02x (PC after exec would be 0x%02x): %s", op, inst.PC, opnames[op]))
	end
	local r, r2 = pcall(opfn, inst, p1, p2)
	if r then
		return r2
	end
	error(fmt("Error in op 0x%02x (%s) @ (PC after exec would be 0x%02x): %s", op, opnames[op], inst.PC, tostring(r2)))
end

function _M.interrupt(inst, ...)
	if inst.int_enable then
		-- The interrupt occurs.
		inst.int_enable = false
		callop(inst, ...)
		return true
	else
		-- 'Try again later'.
		return false
	end
end

-- Run
function _M.run(inst)
	if inst.halted then
		error("The machine halted. You're supposed to stop executing now, or run time forward to the next interrupt.")
	end

	local pc = inst.PC
	local getb = inst.getb
	local op = getb(inst, pc)
	local opl = opbs[op]
	if opl == nil then
		error(fmt("l8080: Unknown OP 0x%02x", op))
	end
	pc = band(pc + 1, 0xFFFF)
	local p1, p2
	if opl[1] == 2 then
		p1 = getb(inst, pc)
		pc = band(pc + 1, 0xFFFF)
	elseif opl[1] == 3 then
		p1 = getb(inst, pc)
		pc = band(pc + 1, 0xFFFF)
		p2 = getb(inst, pc)
		pc = band(pc + 1, 0xFFFF)
	end
	inst.PC = pc
	if not callop(inst, op, p1, p2) then
		return opnames[op], opl[2]
	end
	return opnames[op], opl[3]
end

local function dumpflag(inst, f)
	if inst[f] then
		io.stderr:write(f .. ":Y ")
	else
		io.stderr:write(f .. ":N ")
	end
end

function _M.dump(inst)
	io.stderr:write(fmt("PC %04x SP %04x A %02x\n", inst.PC, inst.SP, inst.A))
	io.stderr:write(fmt("BC %02x%02x DE %02x%02x HL %02x%02x\n", inst.B, inst.C, inst.D, inst.E, inst.H, inst.L))
	dumpflag(inst, "s")
	dumpflag(inst, "p")
	dumpflag(inst, "z")
	dumpflag(inst, "cy")
	dumpflag(inst, "ac")
	io.stderr:write("\n")
end

-- Create a new 8080 instance
function _M.new(getb, setb, iogb, iosb)
	assert(_M.bit32, "8080: Did not set bit32 library. Bailing out.")

	local l8080 = {}
	setmetatable(l8080, _M)

	-- Memory
	l8080.setb = setb
	l8080.getb = getb

	l8080.iosb = iosb
	l8080.iogb = iogb

	-- Registers
	l8080.A = 0
	l8080.B = 0
	l8080.C = 0
	l8080.D = 0
	l8080.E = 0
	l8080.H = 0
	l8080.L = 0

	l8080.SP = 0
	l8080.PC = 0

	-- Internal flags
	l8080.halted = false
	l8080.int_enable = false

	-- Flags

	l8080.z = true
	l8080.s = true
	l8080.p = true
	l8080.cy = false
	l8080.ac = true

	return l8080
end

return _M
