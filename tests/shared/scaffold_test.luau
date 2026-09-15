--!strict
--[[
	Covers src/shared/Scaffold.luau.

	This suite exists to prove the runner runs and the `unit` gate is real. The
	module under test has no domain meaning, and neither does this file.
]]

local Scaffold = require("../../src/shared/Scaffold")

return {
	["join places the separator between adjacent parts"] = function()
		local actual = Scaffold.join({ "a", "b", "c" }, "-")
		assert(actual == "a-b-c", `expected "a-b-c", got "{actual}"`)
	end,

	["join of a single part adds no separator"] = function()
		local actual = Scaffold.join({ "solo" }, "-")
		assert(actual == "solo", `expected "solo", got "{actual}"`)
	end,

	["join of an empty list is the empty string"] = function()
		local actual = Scaffold.join({}, "-")
		assert(actual == "", `expected "", got "{actual}"`)
	end,

	["join uses a multi-character separator verbatim"] = function()
		local actual = Scaffold.join({ "x", "y" }, " <> ")
		assert(actual == "x <> y", `expected "x <> y", got "{actual}"`)
	end,
}
