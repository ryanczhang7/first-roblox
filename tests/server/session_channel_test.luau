--!strict
--[[
	SLICE-006: the session carries pings, presets and every view, and a
	scripted round is won by showing. AC-1 through AC-6 and the story's
	Contract pins (C-2, C-4..C-9), applied to the real
	`src/server/session/Session.luau` over the real `Pings`, `PresetSends`,
	`Projection`, `RoundView` and SLICE-005's modules.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as `session_round_test.luau` does. In RED it exists but holds
	none of this story's behaviour - `Session.new` takes the options where
	the ports now go, there is no channel, no lens or cue is ever sent, no
	FacilityView, and a ping or a preset is an unknown event - so every test
	below FAILS on its own assertion, naming what is missing. It is not a skip.

	THE CHECKS, THE ORACLE AND THE SCRIPT LIVE IN
	`tests/helpers/SessionChannelContract.luau` and `ShownRound.luau`; both
	are exercised against a reference stand-in and deliberately wrong
	stand-ins in `tests/server/session_channel_controls_test.luau`, where
	each check is OBSERVED to fire and the AC-2 script is OBSERVED to win 150
	rounds and to lose every control round. That matters in RED, because
	today's Session fails every check here before most assertions in them
	have run.

	THE ORACLE PARTITION (story `## Contract`): AC-1, AC-3, AC-4, AC-5, AC-6,
	C-2 and C-9 are mechanical; AC-2 is settled, a scripted outcome with a
	control that must fail.

	WHAT THIS FILE DOES NOT PIN: where `channel`, `sent` and `ports` sit
	beyond being fields of the state; the wording of any error; whether the
	views are built in this module or a helper; the RoundView's `secondsLeft`
	on a non-Tick step (C-6 as amended compares the view without it).
]]

local Contract = require("../helpers/SessionChannelContract")

local loaded, loadResult = pcall(require, "../../src/server/session/Session")

local function Session(): any
	assert(loaded, `src/server/session/Session.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

return {
	--[[ C-2 ]]

	["Contract (C-2): Session.new(config, seed, roundId, sessionId, ports, options?) raises without ports.lineOfSight as a function, holds channel = { presets = PresetSends.new(), pings = Pings.new() }, sent = { lens = {}, cues = {} } and the ports as given, and still reads generatorPredicate from the sixth argument"] = function()
		Contract.newRequiresPortsAndHoldsAFreshChannelSentAndPorts(Session())
	end,

	--[[ AC-1 ]]

	["AC-1: after every step of a scripted sequence each seated player alone receives a SendTo/LensView iff Projection.lensFor on the end state differs from the last one sent and a SendTo/TurnCues iff turnCuesFor differs (seat order, lens before cues; the first after the deal always, even empty; PositionsSampled steps included); a player whose views did not change receives nothing; the leaver is never sent another and loses their sent entries; no Broadcast carries a LensView or TurnCues by kind or by shape"] = function()
		Contract.sendsEachPlayerTheirOwnLensAndCuesExactlyWhenTheyChange(Session())
	end,

	["Contract (C-6): sent.lens and sent.cues are {} on entering Lobby and reset on the deal, so on a second deal every seated player is sent a LensView and TurnCues again although the lens equals the last one of round 1"] = function()
		Contract.resetsTheSentViewsOnTheDealAndInLobby(Session())
	end,

	--[[ AC-3 ]]

	["AC-3: an accepted setting ping (helper at the machine) is Pings.accept(previous, sender, target, Pings.targetPosition, now, roomLit) with no SendTo and no decline, and that step's RoundView broadcast shows Pings.shown of it; it is still shown ping_display_seconds - 1 later and gone at ping_display_seconds; a fresh ping is cleared in the step that commits its machine; a machine ping shows without a setting; outside Round the view's pings are {} while the channel is kept through Resolution and Post and reset on entering Lobby (C-8)"] = function()
		Contract.showsAnAcceptedPingInTheRoundViewUntilExpiryOrCommit(Session())
	end,

	["AC-3: a refused ping emits exactly one SendTo/PingRefused { reason } to its sender, declines the call exactly once and changes nothing - no_such_target in Lobby and in Resolution (procedure held), out_of_range from the spawn centre, setting_mismatch for a machine ping with a setting"] = function()
		Contract.refusesAPingToTheSenderAloneDecliningOnce(Session())
	end,

	--[[ AC-4 ]]

	["AC-4: a PresetSent whose filter result succeeded broadcasts exactly one PresetShown { senderId, presetId, position = the sender's STORED position (a copy), text = the filtered text } with no SendTo and no decline, and the presets log is PresetSends.send's; a failing filter sends one PresetFailed { presetId, reason = filter } to the sender alone, declined once, log unchanged; an illegal phase fails phase_for_preset before the filter; with no stored position the call is declined once and nothing happens; in Post the preset shows at the kept position"] = function()
		Contract.broadcastsAShownPresetAtTheStoredPositionAndFailsToTheSenderAlone(Session())
	end,

	--[[ AC-5 ]]

	["AC-5: on each successful deal exactly one Broadcast/FacilityView = RoundView.facility(state.facility), after the SeatViews and before the private views and the RoundView with machines; none on any other step through Resolution, Post, Lobby and the rejoins, and none when generation fails"] = function()
		Contract.broadcastsOneFacilityViewOnTheDealBeforeTheRoundViewAndNeverOtherwise(Session())
	end,

	--[[ C-9 ]]

	["Contract (C-9): every effect of every step is a named kind in the order pass-through, Placed, SeatView, FacilityView, the reply, PresetShown, LensView/TurnCues, at most one RoundView last; the deal reads Placed x n, SeatView x n, FacilityView, (LensView, TurnCues) x n, RoundView; an accepted ping emits only the RoundView, a refused one only the PingRefused, a preset only its PresetShown or PresetFailed, and a commit the TurnResult, private views, RoundView"] = function()
		Contract.ordersEffectsWithinAStepAsTheContractLists(Session())
	end,

	--[[ AC-6 ]]

	["AC-6: over full shown rounds (3 seeds at each n) every SendTo is on the allowlist - a LensView reads only machines whose keyClass is Ring.lensOf(assignment, p), TurnCues carry only machine ids, SeatView/TurnResult/PingRefused/PresetFailed carry no setting field, any other private kind fails - and every Broadcast is a public kind carrying no private view by shape"] = function()
		Contract.neverSendsAPlayerASettingOfAMachineOutsideTheirLens(Session())
	end,

	--[[ AC-2 ]]

	["AC-2: over 50 seeds at each n in {4, 5, 6} the shown script - each turner turns only to a setting its supplier's PingShown names, each helper pings only a reading in its own LensView, the finale gated on the partner lamp - wins every round (won / procedure_complete)"] = function()
		Contract.winsEveryRoundWhenTurnersActOnlyOnShownPings(Session())
	end,

	["AC-2 (control): the same script with the helper's ping suppressed never wins - no ping, no turn, lost / clock on the unpenalised deadline - over 3 seeds at each n"] = function()
		Contract.losesToTheClockWhenHelpersNeverPing(Session())
	end,
}
