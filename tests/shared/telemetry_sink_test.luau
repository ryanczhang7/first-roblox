--!strict
--[[
	TEL-001: the sink interface. AC-4 and AC-5, applied to the real
	`src/shared/telemetry/Sink.luau`.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as `telemetry_event_test.luau` and `projection_test.luau` do:
	in RED every test below FAILS naming the module that did not load, rather
	than the file being one LOAD FAIL line.

	THE CHECKS LIVE IN `tests/helpers/TelemetryContract.luau`, and the events
	they hand the sink are built by hand there in the Contract's
	`TelemetryEvent` shape, so nothing in this file depends on `Event.luau`
	loading. `tests/shared/telemetry_controls_test.luau` is where each check is
	OBSERVED to fire against a deliberately wrong sink.

	AC-5 IS TWO TESTS, because the criterion has two halves and its two
	controls are one half each: a dispatch that propagates fails the first, a
	dispatch that swallows a raise and counts it as delivered fails the second
	and only the second.
]]

local Contract = require("../helpers/TelemetryContract")

local loaded, loadResult = pcall(require, "../../src/shared/telemetry/Sink")

local function Sink(): any
	assert(loaded, `src/shared/telemetry/Sink.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

return {
	--[[ The export shape. ]]

	["Contract: Sink exports noop, recording and dispatch as plain field functions"] = function()
		local module = Sink()
		assert(typeof(module.noop) == "function", `Sink.noop is {typeof(module.noop)}`)
		assert(
			typeof(module.recording) == "function",
			`Sink.recording is {typeof(module.recording)}`
		)
		assert(typeof(module.dispatch) == "function", `Sink.dispatch is {typeof(module.dispatch)}`)
	end,

	--[[ AC-4 ]]

	["AC-4: a recording sink holds exactly the three events emitted to it, in order, with fields intact, and clear() empties it"] = function()
		Contract.recordingSinkHoldsExactlyWhatWasEmittedInOrder(Sink())
	end,

	["AC-4: dispatch through a working sink delivers zero, one and three events with none dropped, and the recording sink holds them in order"] = function()
		Contract.dispatchDeliversEveryEventToAWorkingSink(Sink())
	end,

	--[[ AC-5, one test per half ]]

	["AC-5 (no propagation): a sink whose emit raises does not raise through Sink.dispatch to the caller"] = function()
		Contract.raisingEmitDoesNotPropagate(Sink())
	end,

	["AC-5 (counted drop): a raising emit is recorded as exactly one drop, the other events are still delivered, and delivered + dropped is the batch"] = function()
		Contract.raisingEmitIsACountedDrop(Sink())
	end,
}
