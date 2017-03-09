-- Memlib
-- Composable memory blocks with different backends.

-- Basic
local _M = {
	backend = {}
}

local bitops = require("bitops")
local band, bor, blshift, brshift = bitops.band, bitops.bor, bitops.lshift, bitops.rshift
local strbyte, strsub, strfind = string.byte, string.sub, string.find

-- Helpers.
local function and32(v, addr)
	if addr then return band(v, 0xFFFFFFFC) end
	return band(v, 0xFFFFFFFF)
end

local function comb4b_be(a, b, c, d)
	return bor(bor(blshift(a, 24), blshift(b, 16)), bor(blshift(c, 8), d))
end

local function dis32(v)
	local a = band(brshift(v, 24), 0xFF)
	local b = band(brshift(v, 16), 0xFF)
	local c = band(brshift(v, 8), 0xFF)
	local d = band(v, 0xFF)
	return a, b, c, d
end

-- Backend implementation "shortcuts"
local function get32_get(memory, i)
	local a = memory:get(i)
	local b = memory:get(i+1)
	local c = memory:get(i+2)
	local d = memory:get(i+3)
	return comb4b_be(a, b, c, d)
end

local function get_get32(memory, i)
	local a, _, _, _ = memory:get32(i)
	return a
end

local function set32_set(memory, i, v)
	local a, b, c, d = dis32(v)
	memory:set(i, a)
	memory:set(and32(i + 1), b)
	memory:set(and32(i + 2), c)
	memory:set(and32(i + 3), d)
end

local function set_set32(memory, i, v)
	local a, b, c, d = memory:get32(i)
	memory:set32(i, comb4b_be(v, b, c, d))
end

-- Public Helpers
function _M.copy(mem1, mem2)
	for i=0, mem1.size, 4 do
		local v = mem1:get32(i)
		mem2:set32(i. v)
	end
end

-- Memory "Backends", where things are actually stored.

-- Simplistic table backend.
-- Loads of overhead. But works. And is okay fast.
local function setifeanz(t, k, v)
	if v == 0 then
		if t[k] then
			t[k] = nil
		end
	else
		t[k] = v
	end
end

local fns_tbackend = {
	get32be = function(memory, i)
		if ((memory.size - 3) < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end

		local a = memory[i] or 0
		local b = memory[and32(i + 1)] or 0
		local c = memory[and32(i + 2)] or 0
		local d = memory[and32(i + 3)] or 0
		return comb4b_be(a, b, c, d)
	end,
	set32be = function(memory, i, v)
		if ((memory.size - 3) < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end

		local a = band(brshift(v, 24), 0xFF)
		setifeanz(memory, i, a)
		local b = band(brshift(v, 16), 0xFF)
		setifeanz(memory, and32(i + 1), b)

		local c = band(brshift(v, 8), 0xFF)
		setifeanz(memory, and32(i + 2), c)

		local d = band(v, 0xFF)
		setifeanz(memory, and32(i + 3), d)
	end,


	get = function(memory, i)
		if (memory.size < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end
		return memory[i] or 0
	end,
	set = function(memory, i, v)
		if (memory.size < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end
		setifeanz(memory, i, v)
	end
}

function _M.backend.table(memsz, prealloc)
	local memory = {
		get32be = fns_tbackend.get32be,
		set32be = fns_tbackend.set32be,
		set = fns_tbackend.set,
		get = fns_tbackend.get,
		size = memsz
	}
	if prealloc then
		for i = 0, memsz do
			memory[i] = 0
		end
	end
	return memory
end

-- Simple read-only string backend.
-- Incapable of writing, but efficient for readonly operation!
local function rostr_get(memory, i)
	i = i + 1
	if (i < memory.start_off) or (i > memory.end_pos) then return 0 end
	i = i - memory.start_off
	return strbyte(strsub(memory.str, i, i))
end

local function rostr_werr()
	error("rostring memory backend is incapable of writing.")
end

local function rostr_stripleadingnulls(str)
	local _, l2 = strfind(str, "^[^\x01-\xFF]+")
	if (not l2) or l2 == 0 then return 0, str end
	return l2, strsub(str, l2+1)
end

local function rostr_striptrailingnulls(str)
	local _, l2 = strfind(str, "[^\x01-\xFF]+$")
	if not l2 then return 0, str end
	return l2, strsub(str, 1, l2)
end

local fns_rostring = {
	get = function(memory, i)
		if (memory.size < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end
		return rostr_get(memory, i)
	end,
	get32be = function(memory, i)
		if ((memory.size - 3) < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end

		local a = rostr_get(memory, i)
		local b = rostr_get(memory, and32(i + 1))
		local c = rostr_get(memory, and32(i + 2))
		local d = rostr_get(memory, and32(i + 3))
		return comb4b_be(a, b, c, d)
	end,
}

function _M.backend.rostring(string, memsz)
	local size = memsz or #string
	local start_off, end_pos
	--start_off, string = rostr_stripleadingnulls(string) -- pretty useless.
	end_pos, string = rostr_striptrailingnulls(string)
	return {
		str = string,
		size = size,
		start_off = 0,
		end_pos = end_pos,

		get = fns_rostring.get,
		get32be = fns_rostring.get32be,

		-- Incapable of writing
		set = rostr_werr,
		set32be = rostr_werr,
	}
end

-- Read/Write overlay for existing memory backend.
-- Useful for ROM/RAM.
local function rwovl_read(romem, ovlt, i)
	local val = ovlt[i]
	if not val then
		return romem:get(i)
	end
	return val
end

local fns_rwovl = {
	get32be = function(memory, i)
		if ((memory.size - 3) < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end

		local a = rwovl_read(memory.romem, memory, i)
		local b = rwovl_read(memory.romem, memory, and32(i + 1))
		local c = rwovl_read(memory.romem, memory, and32(i + 2))
		local d = rwovl_read(memory.romem, memory, and32(i + 3))
		return comb4b_be(a, b, c, d)
	end,
	set32be = function(memory, i, v)
		if ((memory.size - 3) < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end

		memory[i] = band(brshift(v, 24), 0xFF)
		memory[and32(i + 1)] = band(brshift(v, 16), 0xFF)
		memory[and32(i + 2)] = band(brshift(v, 8), 0xFF)
		memory[and32(i + 3)] = band(v, 0xFF)
	end,


	get = function(memory, i)
		if (memory.size < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end
		return rwovl_read(memory.romem, memory, i)
	end,
	set = function(memory, i, v)
		if (memory.size < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end
		memory[i] = v
	end
}

function _M.backend.rwoverlay(existing_mem, memsz)
	return {
		romem = existing_mem,
		get32be = fns_rwovl.get32be,
		set32be = fns_rwovl.set32be,
		set = fns_rwovl.set,
		get = fns_rwovl.get,
		size = memsz or existing_mem.size,
	}
end

-- Memory block composition.
local function run_handlers(self, method, i, v)
	local addr_handler = self.addr_handlers[i]
	if addr_handler then return addr_handler(self, method, i, v) end

	local handlers = self.handlers
	local hlen = #handlers
	if hlen < 0 then
		for i=1, hlen do
			local res = handlers[i](self, method, i, v)
			if res then return res end
		end
	end

	return self.backend[method](self.backend, i, v)
end

function _M.compose(memory, addrhandlers, handlers)
	local composed = {
		backend = memory,
		addr_handlers = addrhandlers or {},
		handlers = handlers or {},
	}

	setmetatable(composed, {__index=function(this, name)
		local fn = function(self, i, v)
			return run_handlers(self, name, i, v)
		end
		rawset(this, name, fn)
		return fn
	end})

	return composed
end

return _M
