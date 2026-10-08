--!strict
--[[
	PROC-005: the `Turn` remote is declared and validated. AC-1 through AC-3,
	applied to the real `src/ReplicatedStorage/Net/GameRemotes.luau` through the real
	`src/ReplicatedStorage/Net/Wrapper.luau`, `Remotes.luau` and `Schema.luau`.

	`GameRemotes` is required through a `pcall` at the top and re-checked
	inside every test, as every suite here does. In RED it does not exist, and
	a bare top-level `require` would make this whole file a single LOAD FAIL -
	one line of red covering three criteria. Per-criterion failures say which
	behaviours are missing. It is not a skip: every test below still FAILS,
	loudly, naming the module that did not load.

	THE CHECKS LIVE IN `tests/helpers/TurnRemoteContract.luau` and are
	exercised in `tests/net/turn_remote_controls_test.luau` against a
	reference declaration and declarations with exactly one defect each. That
	file is where each check is OBSERVED to fire - which matters in RED,
	because the pcall above means not one assertion in THIS file executes
	until GREEN writes the module.

	THE DEFINITION UNDER TEST IS READ OUT OF `Remotes.all()` BY NAME, as AC-1
	says, and then asserted to be the same table as `GameRemotes.Turn`. The
	registry is process-wide and `Remotes.define` refuses a duplicate, so
	nothing here declares `"Turn"`: the module does, once, at require time.

	WHAT THIS FILE DOES NOT PIN: how `GameRemotes` is laid out beyond
	exporting `Turn`, the text of any rejection detail, whether other remotes
	(CHAN-004's) are declared beside it, or the order of `Remotes.all()`.
]]

local Contract = require("../helpers/TurnRemoteContract")
local Deep = require("../helpers/Deep")

local schemaLoaded, schemaResult = pcall(require, "../../src/ReplicatedStorage/Net/Schema")
local remotesLoaded, remotesResult = pcall(require, "../../src/ReplicatedStorage/Net/Remotes")
local wrapperLoaded, wrapperResult = pcall(require, "../../src/ReplicatedStorage/Net/Wrapper")
local gameRemotesLoaded, gameRemotesResult =
	pcall(require, "../../src/ReplicatedStorage/Net/GameRemotes")

local function net(): Contract.Net
	assert(
		schemaLoaded,
		`src/ReplicatedStorage/Net/Schema.luau did not load: {tostring(schemaResult)}`
	)
	assert(
		remotesLoaded,
		`src/ReplicatedStorage/Net/Remotes.luau did not load: {tostring(remotesResult)}`
	)
	assert(
		wrapperLoaded,
		`src/ReplicatedStorage/Net/Wrapper.luau did not load: {tostring(wrapperResult)}`
	)
	return { Schema = schemaResult, Remotes = remotesResult, Wrapper = wrapperResult }
end

-- The `Turn` definition as `Remotes.all()` lists it, found by name.
local function turn(): any
	assert(
		gameRemotesLoaded,
		`src/ReplicatedStorage/Net/GameRemotes.luau did not load: {tostring(gameRemotesResult)}`
	)
	local found: any = nil
	for _, entry in net().Remotes.all() do
		if typeof(entry) == "table" and entry.name == "Turn" then
			found = entry
		end
	end
	assert(found ~= nil, 'AC-1: Remotes.all() lists no definition named "Turn"')
	return found
end

return {
	["Contract: GameRemotes exports Turn, and it is the same table Remotes.all() lists under the name Turn"] = function()
		local listed = turn()
		local GameRemotes: any = gameRemotesResult
		assert(
			typeof(GameRemotes) == "table" and typeof(GameRemotes.Turn) == "table",
			`GameRemotes.Turn is {if typeof(GameRemotes) == "table"
				then Deep.show(GameRemotes.Turn)
				else typeof(GameRemotes)}, expected the Turn definition`
		)
		assert(
			rawequal(GameRemotes.Turn, listed),
			'GameRemotes.Turn is not the same table as the definition Remotes.all() lists as "Turn"'
		)
	end,

	--[[ AC-1, settled: read from MechanicsTuning, never a literal. ]]

	["AC-1: Turn's schema answers as { machine = integer(1, actuator_count), setting = integer(1, dial_settings) } at 0, 1, max and max + 1 for each field, files a non-integer as range, and a missing, extra or non-table payload as shape"] = function()
		Contract.schemaIsIntegerMachineAndSettingAtTheTuningBounds(net(), turn())
	end,

	["AC-1: Turn's legalPhases is exactly { Round }"] = function()
		Contract.legalPhasesAreExactlyRound(net(), turn())
	end,

	["AC-1: Turn's rateLimit.minIntervalSeconds equals MechanicsTuning.actuation.turn_rate_limit_seconds"] = function()
		Contract.rateLimitIsTheTurnRateLimitFromTuning(net(), turn())
	end,

	["AC-1: Turn declares no attempt limit - attemptLimit is nil (PO decision 1)"] = function()
		Contract.declaresNoAttemptLimit(net(), turn())
	end,

	["AC-1: Remotes.all() lists exactly one definition named Turn, and it is the registered table itself"] = function()
		Contract.isTheDefinitionRemotesAllLists(net(), turn())
	end,

	--[[ AC-2, mechanical: B4's malformed calls through the real Wrapper.guard. ]]

	["AC-2: a seated caller in Round sending a missing setting, machine = 0, setting = dial_settings + 1, setting = 1.5, an extra player key, or a string is rejected for shape, range, range, range, shape, shape respectively, and the handler never runs"] = function()
		Contract.malformedCallsAreRejectedBeforeTheHandler(net(), turn())
	end,

	--[[ AC-3, mechanical: out of phase, and flooded. ]]

	["AC-3: a well-formed Turn by a seated caller in Lobby, Assignment, Resolution or Post is rejected for phase and the handler never runs"] = function()
		Contract.wellFormedCallOutOfRoundIsRejectedForPhase(net(), turn())
	end,

	["AC-3: two well-formed in-Round Turns at t and t + turn_rate_limit_seconds - 0.1 - the second is rejected for rate and the handler count stays 1; a third at exactly t + turn_rate_limit_seconds runs it (count 2)"] = function()
		Contract.secondCallInsideTheTurnRateLimitIsRejectedForRate(net(), turn())
	end,

	["AC-2/AC-3 positive control: a well-formed in-Round Turn by the seated caller - mid-range and at both maxima - reaches the handler exactly once with the caller's id and exactly { machine, setting }"] = function()
		Contract.wellFormedCallInRoundReachesTheHandlerWithExactlyMachineAndSetting(net(), turn())
	end,
}
