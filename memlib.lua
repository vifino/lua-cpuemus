-- Memlib
-- Composable memory blocks with different backends.

-- Basic
local _M = {
	backend = {}
}

local bitops = require("bitops")
local band, bor, blshift, brshift = bitops.band, bitops.bor, bitops.lshift, bitops.rshift

-- Helpers.
local function and32(v, addr)
	if addr then return band(v, 0xFFFFFFFC) end
	return band(v, 0xFFFFFFFF)
end

local function comb4b(a, b, c, d)
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
	return comb4b(a, b, c, d)
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
	memory:set32(i, comb4b(v, b, c, d))
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
local fns_tbackend = {
	get32be = function(memory, i)
		i = band(i, 0xFFFFFFFC)
		if ((memory.size - 3) < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end
	
		local a = memory[i] or 0
		local b = memory[and32(i + 1)] or 0
		local c = memory[and32(i + 2)] or 0
		local d = memory[and32(i + 3)] or 0
		return comb4b(a, b, c, d)
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
		return memory[i] or 0
	end,
	set = function(memory, i, v)
		if (memory.size < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end
		memory[i] = v
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
	setmetatable(memory, mt_tbackend)
	return memory
end

-- Memory block composition.
local function run_handlers(self, method, i, v)
	local addr_handler = self.addr_handlers[i]
	if addr_handler then return addr_handler(self, method, i, v) end

	local hlen = #self.handlers
	if hlen < 0 then
		for i=1, hlen do
			local res = self.handlers[i](self, method, i, v)
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