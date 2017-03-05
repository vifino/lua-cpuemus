-- ZPU Emulator: Example usage.

local arg = arg or {...}

local fname = arg[1]
if not fname then
	error("Need filename")
end
local f, err = io.open(fname, "rb")
if err then error(err) end

local memsz = 0x80000

-- Load bitops
local bitops = loadfile("bitops.lua")(false, true)
-- Load ZPU
local zpu = dofile("zpu.lua")
-- Install bitops
zpu.set_bit32(bitops)
-- Load ZPU emulates and apply them
local zpu_emulates = dofile("zpu_emus.lua")
zpu:apply(zpu_emulates)

local memlib = require("memlib")

-- Memory: ROM, RAM and peripherals.
local t = f:read(memsz)
local rom = memlib.backend.rostring(t, memsz)
f:close()

local mem = memlib.backend.rwoverlay(rom, memsz)

-- Address handlers/Peripherals
local addr_handlers = {}
addr_handlers[0x80000024] = function(comp, method, i, v)
	-- UART(O)
	if method == "get32be" then return 0x100 end
	if method == "set32be" then
		io.write(string.char(bitops.band(v, 0xFF)))
		io.flush()
		return
	end
end

addr_handlers[0x80000028] = function(comp, method, i, v)
	-- UART(I)
	if method == "get32be" then
		local inp = io.read(1)
		local ret = (inp and string.byte(inp)) or 0
		return bitops.bor(ret, 0x100)
	end
end

local comp = memlib.compose(mem, addr_handlers)

local function get32(zpu_inst, i, v)
	return comp:get32be(i)
end
local function set32(zpu_inst, i, v)
	return comp:set32be(i, v)
end

-- Get ZPU instance and set up.
local zpu_inst = zpu.new(get32, set32)
zpu_inst.rSP = memsz

while zpu_inst:run() do
end
