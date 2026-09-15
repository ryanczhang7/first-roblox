--!strict
--[[
	Scaffold smoke module.

	This module exists for one reason: to give BOOT-001's `unit`, `lint`,
	`format` and `typecheck` gates something real to chew on, so that each of
	them can be observed passing over non-zero input and failing over none.

	It has deliberately NO domain meaning. It is not the start of the
	architecture, ROUND-001 does not build on it, and the first story that needs
	this file's name is free to delete it.

	It is pure: no clock, no random source, no Roblox globals, no I/O. That is
	not incidental - `docs/wiki/architecture.md` section 2 makes the injected
	clock and RNG a hard requirement, so nothing in `src/` may reach for
	`os.clock`, `tick`, `task.wait`, `math.random` or `Random.new` outside the
	two adapters ROUND-001 builds test-first.
]]

local Scaffold = {}

--[[
	Concatenates `parts` in order, placing `separator` between adjacent parts.

	An empty list yields the empty string; a single part yields that part with
	no separator attached.
]]
function Scaffold.join(parts: { string }, separator: string): string
	local out = ""
	for index, part in parts do
		if index > 1 then
			out ..= separator
		end
		out ..= part
	end
	return out
end

return Scaffold
