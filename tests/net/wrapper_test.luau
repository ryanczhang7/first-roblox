--!strict
--[[
	NET-001: the validation pipeline. AC-1 through AC-6 applied to the real
	`src/net/Wrapper.luau`, driving real `Schema` and `Remotes` modules - this
	is the level at which the CONTRACT between the three lives, so it is where
	the adversarial cases are asserted.

	The three modules are required through a `pcall` at the top and re-checked
	inside every test, so that in RED every test below FAILS naming the module
	that did not load.

	THE CHECKS LIVE IN `tests/helpers/NetContract.luau`, and every one of them
	has been OBSERVED to fire in `tests/net/net_controls_test.luau` against the
	wrapper it exists to catch - including the two the criteria name: AC-5
	against a wrapper that rejects everything, AC-6 against one that returns a
	single boolean false. This is the adversarial story of the backlog: the
	valuable tests here are the ones where a call from a player who is not
	seated, with a table where a number belongs, with one key too many, is
	rejected AND rejected for the right reason.

	NO ROBLOX, NO `Players` SERVICE, NO ROUND. `GuardContext` is injected, and
	`NetContract.context` builds one from a list of seated player ids, a fixed
	phase and `Clock.manual(0)`. Nothing here requires a module from
	`src/server/`: `architecture.md` §1 forbids `net` -> `server`, and a test
	that reached across would pin the wrong architecture.
]]

local Contract = require("../helpers/NetContract")

local schemaLoaded, schemaResult = pcall(require, "../../src/net/Schema")
local remotesLoaded, remotesResult = pcall(require, "../../src/net/Remotes")
local wrapperLoaded, wrapperResult = pcall(require, "../../src/net/Wrapper")

local function net(): Contract.Net
	assert(schemaLoaded, `src/net/Schema.luau did not load: {tostring(schemaResult)}`)
	assert(remotesLoaded, `src/net/Remotes.luau did not load: {tostring(remotesResult)}`)
	assert(wrapperLoaded, `src/net/Wrapper.luau did not load: {tostring(wrapperResult)}`)
	return { Schema = schemaResult, Remotes = remotesResult, Wrapper = wrapperResult }
end

return {
	["Contract: Wrapper exports guard as a plain field function returning a function"] = function()
		local bundle = net()
		assert(
			typeof(bundle.Wrapper.guard) == "function",
			`Wrapper.guard is {typeof(bundle.Wrapper.guard)}`
		)
		local definition = Contract.tokenRemote(bundle, "export")
		local guarded = bundle.Wrapper.guard(definition, Contract.context({ "p1" }), function() end)
		assert(typeof(guarded) == "function", `Wrapper.guard returned {typeof(guarded)}`)
	end,

	--[[ AC-1 ]]

	["AC-1: a valid call by a seated player runs the handler exactly once per call, with the caller's id and arguments structurally equal to the payload"] = function()
		Contract.handlerRunsExactlyOnceWithTheValidatedArguments(net())
	end,

	--[[ AC-2 ]]

	["AC-2: zero keys, one key too many, a wrong type, a table where a number belongs, a missing field, an extra field, nil and a non-table payload are each rejected for shape and the handler never runs"] = function()
		Contract.malformedPayloadIsRejectedForShape(net())
	end,

	--[[ AC-3 ]]

	["AC-3: below the minimum, above the maximum, NaN, math.huge, -math.huge and a non-integer where an integer is declared are each rejected for range, not shape, and the handler never runs"] = function()
		Contract.outOfRangeNumberIsRejectedForRange(net())
	end,

	--[[ AC-4 ]]

	["AC-4: a player who is not seated is rejected for identity on a valid payload, the handler never runs, and isSeated was asked about the caller"] = function()
		Contract.unseatedPlayerIsRejectedForIdentity(net())
	end,

	--[[ AC-5 ]]

	["AC-5: a valid call at the minimum, at the maximum and in between, with either boolean, is accepted (returns nil) - a wrapper that rejects everything fails here"] = function()
		Contract.validCallIsAccepted(net())
	end,

	--[[ AC-6, one test per half ]]

	["AC-6 (names the check): every rejection is a table whose reason is identity, shape or range and whose detail is a non-empty string - a single boolean false fails here"] = function()
		Contract.rejectionNamesTheCheckThatFired(net())
	end,

	["AC-6 (order): an unseated player sending a malformed or out-of-range payload is rejected for identity; a seated player sending a range failure in one field and a shape failure in the other is rejected for shape"] = function()
		Contract.checksRunIdentityThenShapeThenRange(net())
	end,

	--[[ The Contract's own promises ]]

	["Contract: the guarded function never raises - a function, a thread, a 40-deep table, a table key, a 100 KB string, -0, 2^63, and a numeric, nil or table playerId all yield nil or a Rejection"] = function()
		Contract.guardedCallNeverRaises(net())
	end,

	["Contract: identity fails first and short-circuits - the schema is not consulted for an unseated caller and is consulted once for a seated one"] = function()
		Contract.identityFailureShortCircuitsBeforeTheSchema(net())
	end,

	['Contract: the wrapper reads the kind off the schema\'s failure string - "range: ..." becomes a range Rejection carrying the detail, "shape: ..." a shape one, true is acceptance'] = function()
		Contract.wrapperReadsTheKindFromTheSchemasFailureString(net())
	end,
}
