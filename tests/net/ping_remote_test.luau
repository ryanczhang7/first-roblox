--!strict
--[[
	CHAN-005: the `Ping` remote is declared, validated, and its refusals
	decline. AC-1, AC-2 and AC-4, applied to the real `src/ReplicatedStorage/Net/GameRemotes.luau`
	through the real `src/ReplicatedStorage/Net/Wrapper.luau`, `Remotes.luau` and `Schema.luau`,
	and - for AC-4 - to the real `src/server/channel/Pings.luau`.

	`GameRemotes` and `Pings` are required through a `pcall` at the top and
	re-checked inside every test, as every suite here does. In RED
	`GameRemotes.Ping` is not declared and `Pings.luau` does not exist, and a
	bare top-level `require` would make this whole file a single LOAD FAIL -
	one line of red covering three criteria. Per-criterion failures say which
	behaviours are missing. It is not a skip: every test below still FAILS,
	loudly, naming the module or export that did not load.

	THE CHECKS LIVE IN `tests/helpers/PingRemoteContract.luau` (AC-1, AC-2)
	and `tests/helpers/PingsContract.luau` (AC-4), and are exercised in
	`tests/net/ping_remote_controls_test.luau` against a reference declaration
	and declarations with exactly one defect each. That file is where each
	check is OBSERVED to fire - which matters in RED, because the pcall above
	means not one assertion in THIS file executes until GREEN writes the
	module.

	THE DEFINITION UNDER TEST IS READ OUT OF `Remotes.all()` BY NAME, as AC-1
	says, and then asserted to be the same table as `GameRemotes.Ping`. The
	registry is process-wide and `Remotes.define` refuses a duplicate, so
	nothing here declares `"Ping"`: the module does, once, at require time.

	WHAT THIS FILE DOES NOT PIN: how `GameRemotes` is laid out beyond
	exporting `Ping` beside `Turn`, the text of any rejection detail other than
	the two rate details and the `declined` detail CHAN-003 fixed, whether
	other remotes are declared beside it, or the order of `Remotes.all()`.
]]

local Contract = require("../helpers/PingRemoteContract")
local Deep = require("../helpers/Deep")
local PingsContract = require("../helpers/PingsContract")

local schemaLoaded, schemaResult = pcall(require, "../../src/ReplicatedStorage/Net/Schema")
local remotesLoaded, remotesResult = pcall(require, "../../src/ReplicatedStorage/Net/Remotes")
local wrapperLoaded, wrapperResult = pcall(require, "../../src/ReplicatedStorage/Net/Wrapper")
local gameRemotesLoaded, gameRemotesResult =
	pcall(require, "../../src/ReplicatedStorage/Net/GameRemotes")
local pingsLoaded, pingsResult = pcall(require, "../../src/server/channel/Pings")

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

-- The `Ping` definition as `Remotes.all()` lists it, found by name.
local function ping(): any
	assert(
		gameRemotesLoaded,
		`src/ReplicatedStorage/Net/GameRemotes.luau did not load: {tostring(gameRemotesResult)}`
	)
	local found: any = nil
	for _, entry in net().Remotes.all() do
		if typeof(entry) == "table" and entry.name == "Ping" then
			found = entry
		end
	end
	assert(found ~= nil, 'AC-1: Remotes.all() lists no definition named "Ping"')
	return found
end

local function pings(): any
	assert(pingsLoaded, `src/server/channel/Pings.luau did not load: {tostring(pingsResult)}`)
	return pingsResult
end

return {
	["Contract: GameRemotes exports Ping, and it is the same table Remotes.all() lists under the name Ping"] = function()
		local listed = ping()
		local GameRemotes: any = gameRemotesResult
		assert(
			typeof(GameRemotes) == "table" and typeof(GameRemotes.Ping) == "table",
			`GameRemotes.Ping is {if typeof(GameRemotes) == "table"
				then Deep.show(GameRemotes.Ping)
				else typeof(GameRemotes)}, expected the Ping definition`
		)
		assert(
			rawequal(GameRemotes.Ping, listed),
			'GameRemotes.Ping is not the same table as the definition Remotes.all() lists as "Ping"'
		)
	end,

	--[[ AC-1, settled: read from tuning.md through RateLimitSpec and from MechanicsTuning, never a literal. ]]

	["AC-1: Ping's schema answers as { kind = literal(setting, machine, doorway), target = integer(1, actuator_count), setting = optional(integer(1, dial_settings)) } at each bound, files a fourth kind, a missing field, an extra field and a non-table as shape"] = function()
		Contract.schemaIsKindTargetAndOptionalSettingAtTheTuningBounds(net(), ping())
	end,

	["AC-1: Ping's legalPhases is exactly { Round }"] = function()
		Contract.legalPhasesAreExactlyRound(net(), ping())
	end,

	["AC-1: Ping's rateLimit.minIntervalSeconds equals the value RateLimitSpec reads for ping_rate_limit_seconds from tuning.md, equals MechanicsTuning.channel.ping_rate_limit_seconds, and is at least FLOOR_SECONDS"] = function()
		Contract.rateLimitIsThePingRateLimitTheDocumentFixes(net(), ping())
	end,

	["AC-1: Ping's attemptLimit.minIntervalSeconds equals MechanicsTuning.channel.channel_attempt_min_interval_seconds"] = function()
		Contract.attemptLimitIsTheChannelAttemptFloorFromTuning(net(), ping())
	end,

	["AC-1: Remotes.all() lists exactly one definition named Ping, and it is the registered table itself"] = function()
		Contract.isTheDefinitionRemotesAllLists(net(), ping())
	end,

	--[[ AC-2, mechanical: B4's triple through the real Wrapper.guard. ]]

	["AC-2: a seated caller in Round sending kind = floor, a missing target, target = 0, target = 17, setting = 5, target = 1.5, an extra position field, or the string ping is rejected for shape, shape, range, range, range, range, shape, shape respectively, and the handler never runs"] = function()
		Contract.malformedCallsAreRejectedBeforeTheHandler(net(), ping())
	end,

	["AC-2: a well-formed Ping by a seated caller in Lobby, Assignment, Resolution or Post is rejected for phase and the handler never runs"] = function()
		Contract.wellFormedCallOutOfRoundIsRejectedForPhase(net(), ping())
	end,

	["AC-2: a second well-formed Ping inside channel_attempt_min_interval_seconds is rejected for rate with the attempt detail; one at exactly the floor is rejected for rate with the send detail"] = function()
		Contract.secondCallInsideTheAttemptFloorIsRejectedForRate(net(), ping())
	end,

	["AC-2: after an accepted Ping, a second past the attempt floor and a third inside ping_rate_limit_seconds are rejected for rate with the send detail and the handler count stays 1; a fourth at exactly t + ping_rate_limit_seconds runs it"] = function()
		Contract.secondAcceptedCallInsideTheSendLimitIsRejectedForRate(net(), ping())
	end,

	["AC-2 positive control: a well-formed in-Round Ping of each kind, and at both maxima, reaches the handler exactly once with the caller's id, exactly the payload and a CallControl"] = function()
		Contract.wellFormedCallInRoundReachesTheHandlerWithTheValidatedArgs(net(), ping())
	end,

	--[[ AC-4, mechanical: the real Ping guarded with the two-line adapter over the real Pings.request. ]]

	["AC-4: through the guarded Ping, a refused target at t is declined and Pings.request returned exactly { reason = no_such_target }; a valid target at t + attempt + 0.1, inside ping_rate_limit_seconds, is accepted and request returned nil"] = function()
		PingsContract.refusedPingIsDeclinedAndTheNextValidPingInsideTheSendLimitIsAccepted(
			net(),
			ping(),
			pings()
		)
	end,
}
