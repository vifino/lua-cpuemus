-- ZPU Emulator: Example usage.

local arg = arg or {...}

local fname = arg[1]
if not fname then
	error("Need filename")
end
local f, err = io.open(fname, "rb")
if err then error(err) end

local memory = {}
local memsz = 0x80000
for i = 0, (memsz + 3) do
	memory[i] = 0
end

local t = f:read(memsz)
for i = 1, t:len() do
	memory[i - 1] = string.byte(t, i)
end
f:close()

-- Load bitops
local bitops = loadfile("bitops.lua")(false, true)
-- Load ZPU
local zpu = dofile("zpu.lua")
-- Install bitops
zpu.set_bit32(bitops)
-- Load ZPU emulates and apply them
local zpu_emulates = dofile("zpu_emus.lua")
zpu:apply(zpu_emulates)

-- Memory
local function and32(v, addr)
	if addr then return bitops.band(v, 0xFFFFFFFC) end
	return bitops.band(v, 0xFFFFFFFF)
end

local function rawget32(i)
	local a = memory[i]
	local b = memory[and32(i + 1)]
	local c = memory[and32(i + 2)]
	local d = memory[and32(i + 3)]
	if (not a) or (not b) or (not c) or (not d) then
		error("Bad Access (" .. string.format("%08x", i) .. ")")
	end
	return a, b, c, d
end
local function get32(zpu_inst, i)
	if i == 0x80000024 then
		-- UART(0) - there is always space, which means 0x100 must be set.
		return 0x100
	elseif i == 0x80000028 then
		-- UART(I)
		local inp = io.read(1)
		local ret = inp and string.byte(inp) or 0
		return bitops.bor(ret, 0x100)
	end

	-- big endian referred to as the "native format" in docs.
	i = bitops.band(i, 0xFFFFFFFC)
	local a, b, c, d = rawget32(i)
	return bitops.bor(bitops.bor(bitops.lshift(a, 24), bitops.lshift(b, 16)), bitops.bor(bitops.lshift(c, 8), d))
end

local function set32(zpu_inst, i, v)
	if i == 0x80000024 then
		-- UART(O)
		io.write(string.char(bitops.band(v, 0xFF)))
		io.flush()
		return
	end
	rawget32(i)
	memory[i] = bitops.band(bitops.rshift(v, 24), 0xFF)
	memory[and32(i + 1)] = bitops.band(bitops.rshift(v, 16), 0xFF)
	memory[and32(i + 2)] = bitops.band(bitops.rshift(v, 8), 0xFF)
	memory[and32(i + 3)] = bitops.band(v, 0xFF)
end

-- Get ZPU instance and set up.
local zpu_inst = zpu.new(get32, set32)
zpu_inst.rSP = memsz

while zpu_inst:run() do
end
