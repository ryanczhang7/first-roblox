--!strict
--[[
	NET-001: the structural validators. The unit level of AC-2 and AC-3,
	applied to the real `src/net/Schema.luau` - where the logic lives, so
	where the cheapest falsification is.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as `telemetry_event_test.luau` does: in RED every test below
	FAILS naming the module that did not load, rather than the file being one
	LOAD FAIL line.

	THE CHECKS LIVE IN `tests/helpers/NetContract.luau`, and
	`tests/net/net_controls_test.luau` is where each one is OBSERVED to fire
	against a deliberately wrong validator. What the checks pin, per the
	Contract: inclusive bounds; NaN, the infinities and a non-integer where an
	integer is declared are `range`; a non-number is `shape`; `shape` is
	exact in both directions; a structural failure anywhere in a payload beats
	a domain failure anywhere in it; `validate` never raises and leads its
	failure string with the kind.
]]

local Contract = require("../helpers/NetContract")

local loaded, loadResult = pcall(require, "../../src/net/Schema")

local function net(): Contract.Net
	assert(loaded, `src/net/Schema.luau did not load: {tostring(loadResult)}`)
	return { Schema = loadResult, Remotes = nil, Wrapper = nil }
end

return {
	["Contract: Schema exports integer, number, boolean, literal, shape and optional as plain field functions"] = function()
		local Schema = net().Schema
		for _, name in { "integer", "number", "boolean", "literal", "shape", "optional" } do
			assert(typeof(Schema[name]) == "function", `Schema.{name} is {typeof(Schema[name])}`)
		end
		local schema = Schema.integer(1, 2)
		assert(typeof(schema) == "table", `Schema.integer(1, 2) returned {typeof(schema)}`)
		assert(
			typeof(schema.validate) == "function",
			`schema.validate is {typeof(schema.validate)}`
		)
	end,

	["AC-3 (unit): Schema.integer accepts both inclusive ends and files below, above, NaN, the infinities and a non-integer as range, a non-number as shape"] = function()
		Contract.integerSchemaAcceptsTheInclusiveDomainAndRejectsByKind(net())
	end,

	["AC-3 (unit): Schema.number accepts both inclusive ends and files out-of-range, NaN and the infinities as range, a non-number as shape"] = function()
		Contract.numberSchemaAcceptsTheInclusiveDomainAndRejectsByKind(net())
	end,

	['AC-2 (unit): Schema.boolean accepts true and false and files 1, 0, "true", nil and {} as shape'] = function()
		Contract.booleanSchemaAcceptsOnlyBooleans(net())
	end,

	["AC-2 (unit): Schema.literal accepts exactly the given strings and files case, prefix, whitespace, non-string and nil as shape"] = function()
		Contract.literalSchemaAcceptsOnlyTheGivenStrings(net())
	end,

	["AC-2 (unit): Schema.shape is exact - zero keys, a missing key, an extra key, a wrong type, nil and a non-table are shape; a domain failure is range; a shape failure anywhere beats a range failure anywhere; nested shapes hold"] = function()
		Contract.shapeSchemaIsExact(net())
	end,

	["Contract: Schema.optional accepts nil and otherwise answers exactly as its inner schema, inside and outside a shape"] = function()
		Contract.optionalSchemaAcceptsNilAndDefersToTheInner(net())
	end,

	["Contract: validate never raises on a function, a thread, a 40-deep table, a table key, a 100 KB string, -0, 2^63, NaN or nil, and every failure string leads with shape or range"] = function()
		Contract.validateNeverRaisesOnHostileInput(net())
	end,
}
