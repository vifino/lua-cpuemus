-- Lua 8080 library.
-- Hopefully, one day, it'll work.

local _M = {}
_M.__index = _M

-- Local function cache.
local fmt = string.format
local bnot, band, bor, bxor, lshift, rshift

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
	local l = opbs[b]
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

local function callop(instance, op, pc)
	local inst = instance
	local getb = inst.getb
	local op = getb(inst, pc or 0)
	local l = opbs[op]
	local opfn = ops[op]
	if opfn == nil then
		error(fmt("NYI OP: 0x%02x %s", op, opnames[op]))
	end

	-- We could do dynamic arg calling here, but overhead.
	if l == 1 then
		return opfn(inst)
	elseif l == 2 then
		return opfn(inst, getb(inst, pc+1))
	else
		return opfn(inst, getb(inst, pc+1), getb(inst, pc+2))
	end
end

-- Run
function _M.run(instance)
	print("RUN")
	local inst = instance

	local pc = inst.PC
	local op = inst:getb(pc)
	local opl = opbs[op]
	if not opl then
		error(fmt("l8080: Unknown OP 0x%02x", op))
	end
	callop(inst, op, pc)
	inst.PC = pc + opl
	return opnames[op]
end

-- Create a new 8080 instance
function _M.new(getb, setb)
	assert(_M.bit32, "8080: Did not set bit32 library. Bailing out.")

	local l8080 = {}
	setmetatable(l8080, _M)

	-- Memory
	l8080.setb = setb
	l8080.getb = getb

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
	l8080.int_enable = 0

	l8080.z = true
	l8080.s = true
	l8080.p = true
	l8080.cy = false
	l8080.ac = true

	return l8080
end

return _M
