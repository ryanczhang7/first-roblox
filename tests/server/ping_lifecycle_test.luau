--!strict
--[[
	CHAN-006: each player has at most one live ping and it clears when it
	should. AC-1 .. AC-6, and the Contract's C-2 (purity) and C-3 (`new`),
	applied to the real `src/server/channel/Pings.luau`.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as every suite here does. CHAN-005's module EXISTS and loads;
	what RED is missing is the five functions this story adds - `new`,
	`accept`, `tick`, `onCommitted`, `shown` - so each test below fails at the
	contract's `need()` with "Pings.<name> is nil, expected a function". That
	is the right failure: the export is absent. Per-criterion rather than one
	LOAD FAIL, so each missing behaviour is named separately.

	THE CHECKS LIVE IN `tests/helpers/PingLifecycleContract.luau` and are
	exercised in `tests/server/ping_lifecycle_controls_test.luau` against
	`PingLifecycleStubs.luau`'s reference and implementations with exactly one
	defect each. That file is where each check is OBSERVED to fire - which
	matters in RED, because `need()` above means not one assertion past it in
	THIS file executes until GREEN writes the functions.

	THE ORACLE PARTITION (story `## Contract`): AC-2 is settled by
	`tuning.channel.ping_display_seconds` (15; a substituted tuning says 4, to
	prove the value is read rather than hard-coded). Everything else is
	mechanical: exact active maps keyed by senderId, exact log lists in order,
	exact public-payload keys and order, deep-compared.

	WHAT THIS FILE DOES NOT PIN: how the module stores the state internally
	beyond the two keys `active` and `log`; whether `accept` copies or aliases
	the `target` and `position` tables it is given (only that it never
	mutates them, and that the logged position is value-equal); the sort of
	`shown` beyond byte order of lowercase senderIds; what `tick` and
	`onCommitted` share with the input state when they change nothing (only
	that the returned table is a new one and the input is unchanged); and
	how `Session` wires any of this (`SLICE-006`).
]]

local Contract = require("../helpers/PingLifecycleContract")

local pingsLoaded, pingsResult = pcall(require, "../../src/server/channel/Pings")

local function pings(): any
	assert(pingsLoaded, `src/server/channel/Pings.luau did not load: {tostring(pingsResult)}`)
	return pingsResult
end

return {
	["C-3: Pings.new() returns exactly { active = {}, log = {} }, a fresh table with fresh maps on every call"] = function()
		Contract.newReturnsAnEmptyStateFreshEachCall(pings())
	end,

	["AC-1: a second accepted ping by the same sender replaces the first at once - the active set holds exactly one entry for that sender, the newest, as { senderId, kind, target, setting?, at }, and a tick before the first ping's own expiry still shows only the newest"] = function()
		Contract.aSecondPingBySameSenderReplacesTheFirstAtOnce(pings())
	end,

	["AC-2: a ping made at 10 is active at 10 + ping_display_seconds - 1e-6 and gone at exactly 10 + ping_display_seconds, for the module's 15 and for a substituted tuning of 4; pings expire independently; tick leaves the log alone"] = function()
		Contract.aPingIsActiveUntilExactlyPingDisplaySecondsAfterItWasMade(pings())
	end,

	["AC-3: onCommitted(state, m) clears the setting and machine pings on m and nothing else - a doorway ping numbered m survives, pings on other machines survive, a machine nobody pinged clears nothing, the log is untouched"] = function()
		Contract.aCommitClearsSettingAndMachinePingsOnThatMachineOnly(pings())
	end,

	["AC-4: two senders pinging one target - a machine, and a setting on it - both stay active, each under its own senderId, and both are shown"] = function()
		Contract.twoSendersPingingOneTargetBothStayActiveWithTheirOwnSender(pings())
	end,

	["AC-5: over accepts, a replacement, an expiry and a commit the log holds exactly one { senderId, kind, target, setting?, position, at, roomLit } per accepted ping, in order, and nothing is ever removed; shown leaves it alone"] = function()
		Contract.theLogHoldsOneEntryPerAcceptedPingInOrderAndNothingIsEverRemoved(pings())
	end,

	["AC-5: a doorway ping always logs roomLit = true whatever was passed; a machine or setting ping logs the roomLit it was given"] = function()
		Contract.aDoorwayPingAlwaysLogsRoomLitTrue(pings())
	end,

	["AC-5: a refused request leaves the state unchanged, and in a mixed sequence only the accepted pings reach the log, each with the target's position"] = function()
		Contract.aRefusedRequestIsNeverLoggedAndOnlyAcceptedPingsReachTheLog(pings())
	end,

	["AC-6: shown(state) is exactly { senderId, kind, target, setting? } per active ping, setting only for a setting ping, sorted ascending by senderId, a fresh list each call; an empty state shows {}"] = function()
		Contract.shownIsExactlySenderKindTargetAndSettingSortedBySender(pings())
	end,

	["C-2: accept, tick and onCommitted each return a new state and never mutate the state, active map, log, target or position they were given - whether or not the call changes anything"] = function()
		Contract.acceptTickAndOnCommittedReturnANewStateAndNeverMutateTheirInput(pings())
	end,
}
