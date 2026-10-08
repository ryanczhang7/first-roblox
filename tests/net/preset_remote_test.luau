--!strict
--[[
	CHAN-004: the `SendPreset` remote is declared, validated, and its
	refusals decline. AC-1, AC-2, AC-3, AC-4's guarded half and AC-7, applied
	to the real `src/ReplicatedStorage/Net/GameRemotes.luau` through the real
	`src/ReplicatedStorage/Net/Wrapper.luau`, `Remotes.luau` and `Schema.luau`, and - for AC-4
	and AC-7 - to the real `src/server/channel/PresetSends.luau`.

	`GameRemotes` and `PresetSends` are required through a `pcall` at the top
	and re-checked inside every test, as every suite here does. In RED
	`GameRemotes.SendPreset` is not declared and `PresetSends.luau` does not
	exist, and a bare top-level `require` would make this whole file a single
	LOAD FAIL - one line of red covering five criteria. Per-criterion failures
	say which behaviours are missing. It is not a skip: every test below still
	FAILS, loudly, naming the module or export that did not load.

	THE CHECKS LIVE IN `tests/helpers/PresetRemoteContract.luau` and are
	exercised in `tests/net/preset_remote_controls_test.luau` against a
	reference declaration and declarations with exactly one defect each. That
	file is where each check is OBSERVED to fire - which matters in RED,
	because the pcall above means not one assertion in THIS file executes
	until GREEN writes the module.

	THE DEFINITION UNDER TEST IS READ OUT OF `Remotes.all()` BY NAME, as AC-1
	says, and then asserted to be the same table as `GameRemotes.SendPreset`.
	The registry is process-wide and `Remotes.define` refuses a duplicate, so
	nothing here declares `"SendPreset"`: the module does, once, at require
	time.

	WHAT THIS FILE DOES NOT PIN: how `GameRemotes` is laid out beyond
	exporting `SendPreset` beside `Turn` and `Ping`, whether `legalPhases` is
	computed from `Presets` or written as a literal (C-2: either), the text of
	any rejection detail other than the two rate details and the `declined`
	detail CHAN-003 fixed, or the order of `Remotes.all()`.
]]

local Contract = require("../helpers/PresetRemoteContract")
local Deep = require("../helpers/Deep")

local schemaLoaded, schemaResult = pcall(require, "../../src/ReplicatedStorage/Net/Schema")
local remotesLoaded, remotesResult = pcall(require, "../../src/ReplicatedStorage/Net/Remotes")
local wrapperLoaded, wrapperResult = pcall(require, "../../src/ReplicatedStorage/Net/Wrapper")
local gameRemotesLoaded, gameRemotesResult =
	pcall(require, "../../src/ReplicatedStorage/Net/GameRemotes")
local sendsLoaded, sendsResult = pcall(require, "../../src/server/channel/PresetSends")

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

-- The `SendPreset` definition as `Remotes.all()` lists it, found by name.
local function sendPreset(): any
	assert(
		gameRemotesLoaded,
		`src/ReplicatedStorage/Net/GameRemotes.luau did not load: {tostring(gameRemotesResult)}`
	)
	local found: any = nil
	for _, entry in net().Remotes.all() do
		if typeof(entry) == "table" and entry.name == "SendPreset" then
			found = entry
		end
	end
	assert(found ~= nil, 'AC-1: Remotes.all() lists no definition named "SendPreset"')
	return found
end

local function presetSends(): any
	assert(sendsLoaded, `src/server/channel/PresetSends.luau did not load: {tostring(sendsResult)}`)
	return sendsResult
end

return {
	["Contract: GameRemotes exports SendPreset, and it is the same table Remotes.all() lists under the name SendPreset"] = function()
		local listed = sendPreset()
		local GameRemotes: any = gameRemotesResult
		assert(
			typeof(GameRemotes) == "table" and typeof(GameRemotes.SendPreset) == "table",
			`GameRemotes.SendPreset is {if typeof(GameRemotes) == "table"
				then Deep.show(GameRemotes.SendPreset)
				else typeof(GameRemotes)}, expected the SendPreset definition`
		)
		assert(
			rawequal(GameRemotes.SendPreset, listed),
			'GameRemotes.SendPreset is not the same table as the definition Remotes.all() lists as "SendPreset"'
		)
	end,

	--[[ AC-1, settled: read from tuning.md through RateLimitSpec and from MechanicsTuning, never a literal. ]]

	["AC-1: SendPreset's rateLimit.minIntervalSeconds equals the value RateLimitSpec reads for preset_rate_limit_seconds from tuning.md, equals MechanicsTuning.channel.preset_rate_limit_seconds, and is at least FLOOR_SECONDS"] = function()
		Contract.rateLimitIsThePresetRateLimitTheDocumentFixes(net(), sendPreset())
	end,

	["AC-1: SendPreset's attemptLimit.minIntervalSeconds equals MechanicsTuning.channel.channel_attempt_min_interval_seconds"] = function()
		Contract.attemptLimitIsTheChannelAttemptFloorFromTuning(net(), sendPreset())
	end,

	["AC-1: Remotes.all() lists exactly one definition named SendPreset, and it is the registered table itself"] = function()
		Contract.isTheDefinitionRemotesAllLists(net(), sendPreset())
	end,

	["AC-1: a second well-formed SendPreset inside channel_attempt_min_interval_seconds is rejected for rate with the attempt detail; one at exactly the floor is rejected for rate with the send detail"] = function()
		Contract.secondCallInsideTheAttemptFloorIsRejectedForRate(net(), sendPreset())
	end,

	--[[ AC-2, mechanical: the schema is exactly { preset = integer(1, preset_count) }. ]]

	["AC-2: SendPreset's schema accepts exactly { preset = n } for integer n in 1..preset_count; 0, preset_count + 1 and 1.5 are range; a string, a missing field, a non-table and any other key - to, target, player, position - are shape"] = function()
		Contract.schemaIsExactlyPresetIntegerOneToPresetCount(net(), sendPreset())
	end,

	["AC-2: a seated caller in Round sending a missing preset, a string preset, 0, preset_count + 1, 1.5, a to, a target, a player, a position, a string payload or nil is rejected before the handler, for shape or range as the schema files it, and the handler never runs"] = function()
		Contract.malformedCallsAreRejectedBeforeTheHandler(net(), sendPreset())
	end,

	--[[ AC-3, mechanical: the union of the preset table's phases, derived in the test. ]]

	["AC-3: SendPreset's legalPhases is exactly the union of Presets.ALL[*].phases in phase-machine order"] = function()
		Contract.legalPhasesAreTheUnionOfThePresetTablesPhases(net(), sendPreset())
	end,

	["AC-3: a well-formed SendPreset by a seated caller in a phase outside the union (Assignment, Resolution) is rejected for phase and the handler never runs"] = function()
		Contract.wellFormedCallOutsideTheUnionIsRejectedForPhase(net(), sendPreset())
	end,

	["AC-3 positive control: a well-formed SendPreset in each phase of the union, at 1 and at preset_count, reaches the handler exactly once with the caller's id, exactly the payload and a CallControl"] = function()
		Contract.wellFormedCallInEachLegalPhaseReachesTheHandler(net(), sendPreset())
	end,

	--[[ AC-4 and AC-7, mechanical: the real SendPreset guarded over the real PresetSends.send (C-7). ]]

	["AC-4: through the guarded SendPreset in Round, a preset whose row excludes Round is declined with send returning failed / phase_for_preset and the filter uncalled; the same player's legal preset at exactly t + channel_attempt_min_interval_seconds reaches the handler and is shown"] = function()
		Contract.outOfPhasePresetIsDeclinedAndTheNextLegalPresetAtTheAttemptFloorIsShown(
			net(),
			sendPreset(),
			presetSends()
		)
	end,

	["AC-7: through the guarded SendPreset in Round, two players sending at the same instant are both shown; one player's second, different preset 5 s later is rejected for rate with the send detail, the handler count stays 2 and the log holds the two first sends"] = function()
		Contract.twoPlayersAreBothShownAndOnePlayersSecondPresetInsideTheLimitIsRate(
			net(),
			sendPreset(),
			presetSends()
		)
	end,
}
