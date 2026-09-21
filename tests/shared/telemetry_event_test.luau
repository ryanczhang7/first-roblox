--!strict
--[[
	TEL-001: the telemetry envelope. AC-1, AC-2, AC-3 and AC-6, applied to the
	real `src/shared/telemetry/Event.luau`.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as `projection_test.luau` does. In RED it does not exist, and a
	bare top-level `require` would make this whole file a single LOAD FAIL -
	one line of red covering four criteria. Per-criterion failures say which
	behaviours are missing, which is what GREEN needs. It is not a skip: every
	test below still FAILS, loudly, naming the module that did not load.

	THE CHECKS LIVE IN `tests/helpers/TelemetryContract.luau` and are
	exercised against deliberately wrong modules in
	`tests/shared/telemetry_controls_test.luau`. That file is where each check
	is OBSERVED to fire - which matters in RED, because the pcall above means
	not one assertion in THIS file executes until GREEN writes the module.

	WHAT IS NOT HERE, deliberately: no test that every name in `BUCKETS` has
	an emitter (three are declared for M5 and have none, by design), and no
	private scan for a clock or a random source inside the module -
	`tests/shared/source_guard_test.luau` scans every source module the
	harness classifies, so the two telemetry files are covered the moment they
	exist, and a second copy of that guard is how scanners drift.
]]

local Contract = require("../helpers/TelemetryContract")

local loaded, loadResult = pcall(require, "../../src/shared/telemetry/Event")

local function Event(): any
	assert(loaded, `src/shared/telemetry/Event.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

return {
	--[[ The export shape. Pinned first because everything below depends on it
	     and a wrong guess here is a compile error rather than a puzzle. ]]

	["Contract: Event exports BUCKETS as a table and new as a plain field function"] = function()
		local module = Event()
		assert(typeof(module.BUCKETS) == "table", `Event.BUCKETS is {typeof(module.BUCKETS)}`)
		assert(typeof(module.new) == "function", `Event.new is {typeof(module.new)}`)
	end,

	--[[ AC-1 ]]

	["AC-1: an event built with the injected clock's t carries at = t and exactly the supplied name, bucket, sessionId, playerId and fields"] = function()
		Contract.eventCarriesTheSuppliedValuesAndTheClocksTime(Event())
	end,

	--[[ AC-2 ]]

	["AC-2: BUCKETS names all nine B6 events with their settled buckets, nothing else, and is frozen"] = function()
		Contract.bucketsNameExactlyTheNineB6Events(Event())
	end,

	--[[ AC-3 ]]

	["AC-3: an event name not in BUCKETS is refused at construction, by name, and every B6 name still constructs"] = function()
		Contract.unknownNameIsRefused(Event())
	end,

	--[[ AC-6 ]]

	["AC-6: a fields value that is not a string, number or boolean is refused naming the offending key, and every scalar is carried intact"] = function()
		Contract.nonScalarFieldIsRefusedNamingTheKey(Event())
	end,
}
