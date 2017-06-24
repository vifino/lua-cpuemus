-- Memlib
-- Composable memory blocks with different backends.

-- Basic
local _M = {
	backend = {}
}

local bitops = require("bitops")
local band, bor, blshift, brshift = bitops.band, bitops.bor, bitops.lshift, bitops.rshift
local strbyte, strsub, strfind, strchar = string.byte, string.sub, string.find, string.char

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

function strreplace(str, pos, r)
	local n = #r
	return strsub(str, 1, pos-n) .. r .. strsub(str, pos+n)
end

-- Public Helpers
function _M.new(driver, ...)
	local drv = _M.backend[driver]
	if drv then
		return drv(...)
	end
	error("No such driver: "..tostring(driver), 1)
end

function _M.copy(mem1, mem2)
	for i=0, mem1.size do
		mem2:set(i, mem1:get(i))
	end
end

function _M.copyto(memsrc, addroff, memdst)
	for i=0, memsrc.size do
		local v = memsrc:get(i)
		memdst:set(addroff + i, v)
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

local function rostr_werr()
	error("rostring memory backend is incapable of writing.")
end

-- Returns two values:
-- 1. The last non-NULL memory index, or -1 if the memory is empty.
-- 2. The stripped string.
local function rostr_striptrailingnulls(str)
	local l2, _ = strfind(str, "%z+$")
	if not l2 then return str end
	return strsub(str, 1, l2 - 1)
end

local fns_rostring = {
	get = function(memory, i)
		if (memory.size < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end
		return strbyte(memory.str, i + 1) or 0
	end,
	get32be = function(memory, i)
		if ((memory.size - 3) < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end

		local a, b, c, d = strbyte(memory.str, i + 1, i + 4)
		return comb4b_be(a or 0, b or 0, c or 0, d or 0)
	end,
}

function _M.backend.rostring(string, memsz)
	local size = memsz or #string
	string = rostr_striptrailingnulls(string)
	return {
		-- Don't go changing any ofthese.
		str = string,
		size = size,

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
	local oval = ovlt[i]
	if oval then return oval end
	if romem.size >= i then return romem:get(i) end
	return 0
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
		-- Don't go changing any of these.
		romem = existing_mem,
		get32be = fns_rwovl.get32be,
		set32be = fns_rwovl.set32be,
		set = fns_rwovl.set,
		get = fns_rwovl.get,
		size = memsz or existing_mem.size,
	}
end

-- Read/Write overlay for existing memory backend. 32bit read version.
-- Useful for ROM/RAM.
local function rwovl_read32be(romem, ovlt, i)

end

local fns_rwovl32 = {
	get32be = function(memory, i)
		if ((memory.size - 3) < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end

    local romem = memory.romem
	  local oval = memory[i / 4]
	  if oval then return oval end
	  if romem.size >= i then return romem:get32be(i) end
	  return 0
	end,
	set32be = function(memory, i, v)
		if ((memory.size - 3) < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end

		memory[i / 4] = v
	end,

  errorout = function()
    error("memlib: rwoverlay32 doesn't support byte accesses.")
  end
}

function _M.backend.rwoverlay32(existing_mem, memsz)
	return {
		-- Don't go changing any of these.
		romem = existing_mem,
		get32be = fns_rwovl32.get32be,
		set32be = fns_rwovl32.set32be,
		set = fns_rwovl32.errorout,
		get = fns_rwovl32.errorout,
		size = memsz or existing_mem.size,
	}
end

-- Rather simple cached file backend.
-- Little fancy, not much.
-- Warning: May not write back data unless one reads data after it.

local function file_getcached(s, i, n)
	local blksz = s.blksz
	local ind = i % blksz
	local iblk = i - ind
	local cblk = s.cblk
	local cached = s.cached
	local fh = s.fh

	if s.didmod then
		fh:seek("set", cblk)
		fh:write(cached)
		fh:flush()
		s.didmod = false
	end

	if cblk == iblk then -- current page is the cached one
		if not cached then
			fh:seek("set", iblk)
			cached = fh:read(blksz)
			s.cached = cached
		end
	else -- current cache is for another block.
		fh:seek("set", iblk)
		cached = fh:read(blksz)
		s.cached = cached
		s.cblk = iblk
	end
	return strbyte(cached, ind+1)
end

local function file_setcached(s, i, v)
	local blksz = s.blksz
	local ind = i % blksz
	local iblk = i - ind
	local cblk = s.cblk
	local cached = s.cached
	local fh = s.fh
	if cblk == iblk then -- current page is the cached one
		fh:seek("set", iblk)
		if not cached then
			cached = fh:read(blksz)
			s.cached = cached
		end
	else -- current cache is for another block.
		if s.didmod then
			fh:seek("set", cblk)
			fh:write(cached)
			fh:flush()
			s.didmod = false
		end
		fh:seek("set", iblk)
		cached = fh:read(blksz)
		s.cached = cached
		s.cblk = iblk
	end
	s.didmod = true
	s.cached = strreplace(s.cached, ind+1, strchar(v))
end

local fns_file = {
	get = function(self, i)
		if (self.size < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end
		return file_getcached(self, i)
	end,
	get32be = function(self, i)
		if ((self.size - 3) < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end
		return comb4b_be(file_getcached(self, i), file_getcached(self, i+1), file_getcached(self, i+2), file_getcached(self, i+3))
	end,

	set = function(self, i, v)
		if (self.size < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end
		file_setcached(self, i, v)
	end,
	set32be = function(self, i, v)
		if (self.size < i) or (0 > i) then
			error("Bad Access (" .. string.format("%08x", i) .. ")")
		end
		fh_setcached(self, i, strchar(band(brshift(v, 24), 0xFF), band(brshift(v, 16), 0xFF), band(brshift(v, 8), 0xFF), band(v, 0xFF)))
	end,
}

local function fh_size(fh)
	local current = fh:seek()
	local size = fh:seek("end")
	fh:seek("set", current)
	return size
end

function _M.backend.file(file, blksz)
	local fh = file
	if type(file) == "string" then
		fh = assert(io.open(file, "r+b"))
	end

	local realsize = fh_size(fh)

	return {
		fh = fh,
		size = realsize,
		blksz = blksz or 128,
		cblk = 0,
		cached = nil,
		didmod = false,

		get = fns_file.get,
		get32be = fns_file.get32be,

		set = fns_file.set,
		set32be = fns_file.set32be,
	}
end

local function rofile_werr()
	error("rofile memory backend is incapable of writing.")
end

function _M.backend.rofile(file, blksz)
	local fh = file
	if type(file) == "string" then
		fh = assert(io.open(file, "rb"))
	end

	local realsize = fh_size(fh)

	return {
		fh = fh,
		size = realsize,
		blksz = blksz or 128,
		cblk = 0,
		cached = nil,
		didmod = false,


		get = fns_file.get,
		get32be = fns_file.get32be,

		set = rofile_werr,
		set32be = rofile_werr,
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
