--!strict
--[[
	The negative controls for SLICE-006, and the proof that each check in
	`tests/helpers/SessionChannelContract.luau` - and the AC-2 script in
	`tests/helpers/ShownRound.luau` - means what it says.

	NOTHING HERE REQUIRES THIS STORY'S PRODUCTION CODE. In RED
	`src/server/session/Session.luau` holds none of the channel behaviour, so
	every test in `tests/server/session_channel_test.luau` fails before most of
	its assertions run, and not one of that file's checks has been observed to
	accept or reject anything. The stand-ins below need only the merged pure
	modules, so what is asserted here is MEASURED in RED rather than claimed
	for GREEN. The story's handoff carries the table.

	THE STAND-INS live in `tests/helpers/SessionChannelStubs.luau`.
	`standIn(defects)` wraps SLICE-005's reference session with the layer this
	story adds. With no defects it is the REFERENCE, the positive control:
	every check must ACCEPT it - and so must SLICE-005's, SLICE-003's and
	VIEW-004's session batteries, which is where C-3's narrowings are seen to
	tolerate the new effects (a LensView on a sample, a RoundView on a turn
	whose view changed, a FacilityView on the deal) and where C-6 as amended
	(the RoundView comparison ignores `secondsLeft`) is seen to leave every
	case SLICE-003 named untouched. Each control is the reference with EXACTLY
	ONE defect, and pins the set of checks that fire EXACTLY.

	THE STORY NAMES ITS CONTROLS: a session that BROADCASTS lens views (AC-1's
	control, which also starves the AC-2 script of every lens), and the shapes
	of its deferred verifications - `Pings.shown` always empty (D-1), a lens of
	the player's own class (D-2, the direction error), a diff that always says
	"changed" (D-3, under which the AC-2 win MUST still pass). The AC-2 control
	itself - helpers never ping - is a script option, measured in the baseline
	through `losesToTheClockWhenHelpersNeverPing`. D-1..D-3 THEMSELVES mutate
	the real module and stay with GATES.

	COST. A control that breaks the AC-2 sweep clocks out 150 rounds (420
	simulated seconds each) and costs 10-25 s here; the five that do run the
	full channel battery. Every other control's measured set lies inside
	`SessionChannelContract.FAST`, so it runs that subset (about 0.1 s) and
	the handoff records that the full battery measured the same set in RED.
	SLICE-003's and VIEW-004's batteries (0.1 s) run on every control; SLICE-
	005's (about 3 s, its own 150-round sweep) runs on the baseline and on the
	one control that crosses into it.
]]

local ChannelContract = require("../helpers/SessionChannelContract")
local Deep = require("../helpers/Deep")
local PositionsContract = require("../helpers/PositionsContract")
local PositionsStubs = require("../helpers/PositionsStubs")
local RoundContract = require("../helpers/SessionRoundContract")
local SessionContract = require("../helpers/SessionContract")
local Stubs = require("../helpers/SessionChannelStubs")

local standIn = Stubs.standIn
local reference = Stubs.reference

local function sortedNames(
	failures: { { name: string, message: string } }
): ({ string }, { [string]: string })
	local names: { string } = {}
	local messages: { [string]: string } = {}
	for _, f in failures do
		table.insert(names, f.name)
		messages[f.name] = f.message
	end
	table.sort(names)
	return names, messages
end

local function shown(names: { string }, messages: { [string]: string }): string
	local out: { string } = {}
	for _, name in names do
		table.insert(out, `{name}: {messages[name]}`)
	end
	return table.concat(out, "\n")
end

-- The battery a control is judged by. `channel` is nil for the full channel
-- battery or the subset to run; `slice5` runs SLICE-005's battery too.
type Scope = { channel: { string }?, slice5: boolean? }

-- A control fires EXACTLY the checks named in each battery, each channel
-- failure naming the criterion it belongs to. The measured sets are printed
-- for the handoff.
local function expectFires(
	who: string,
	S: any,
	expected: {
		channel: { string },
		slice5: { string }?,
		slice3: { string }?,
		view4: { string }?,
	},
	scope: Scope?
)
	local only = if scope ~= nil then scope.channel else nil
	local names, messages = sortedNames(ChannelContract.failures(S, only))
	local want = table.clone(expected.channel)
	table.sort(want)
	print(`        [measured] {who} fires: {Deep.show(names)}`)
	if not Deep.equal(names, want) then
		error(
			`{who} fires {Deep.show(names)}, expected exactly {Deep.show(want)}:\n{shown(
				names,
				messages
			)}`,
			0
		)
	end
	local byName: { [string]: ChannelContract.Check } = {}
	for _, check in ChannelContract.CHECKS do
		byName[check.name] = check
	end
	for _, name in names do
		local ac = byName[name].ac
		assert(
			string.find(messages[name], ac, 1, true) ~= nil,
			`{who}: the failure of {name} does not name {ac}:\n{messages[name]}`
		)
	end

	local others: { { any } } = {
		{ "SLICE-003", SessionContract.failures(S), expected.slice3 or {} },
		{
			"VIEW-004",
			PositionsContract.sessionFailures(S, PositionsStubs.reference),
			expected.view4 or {},
		},
	}
	if scope ~= nil and scope.slice5 then
		table.insert(others, { "SLICE-005", RoundContract.failures(S), expected.slice5 or {} })
	end
	for _, battery in others do
		local label, failures, wantOld = battery[1], battery[2], battery[3]
		local old, oldMessages = sortedNames(failures)
		local wantSorted = table.clone(wantOld)
		table.sort(wantSorted)
		if #old > 0 or #wantSorted > 0 then
			print(`        [measured] {who} fires in {label}: {Deep.show(old)}`)
		end
		if not Deep.equal(old, wantSorted) then
			error(
				`{who} fires {Deep.show(old)} in {label}'s battery, expected exactly {Deep.show(
					wantSorted
				)}:\n{shown(old, oldMessages)}`,
				0
			)
		end
	end
end

local NEW = "newRequiresPortsAndHoldsAFreshChannelSentAndPorts"
local OWN_VIEWS = "sendsEachPlayerTheirOwnLensAndCuesExactlyWhenTheyChange"
local RESET = "resetsTheSentViewsOnTheDealAndInLobby"
local PING_SHOWN = "showsAnAcceptedPingInTheRoundViewUntilExpiryOrCommit"
local PING_REFUSED = "refusesAPingToTheSenderAloneDecliningOnce"
local PRESET = "broadcastsAShownPresetAtTheStoredPositionAndFailsToTheSenderAlone"
local FACILITY = "broadcastsOneFacilityViewOnTheDealBeforeTheRoundViewAndNeverOtherwise"
local ORDER = "ordersEffectsWithinAStepAsTheContractLists"
local SECRET = "neverSendsAPlayerASettingOfAMachineOutsideTheirLens"
local WIN = "winsEveryRoundWhenTurnersActOnlyOnShownPings"

local SLICE3_OWN_SEAT = "sendsEachSeatedPlayerExactlyTheirOwnSeatViewAndBroadcastsNone"
local SLICE3_NOOP = "ignoresASeatsAssignedEventFromOutsideAndEveryNoOp"
local SLICE3_NO_SEAT = "sendsNoSeatViewAndKeepsTheRingWhenNobodyIsUnseated"
local SLICE3_QUORUM = "withdrawsOnTheLeaveThatDropsBelowQuorumToo"
local SLICE3_WITHDRAW = "withdrawsTheLeaverAndSendsViewsToExactlyThoseWhoseViewChanged"
local SLICE3_ORDER = "ordersPassThroughThenSeatViewsThenRoundViewLast"
local SLICE5_ORDER = "ordersPassThroughPlacedSeatViewsTurnResultThenRoundViewLast"
local VIEW4_NO_EFFECTS = {
	"dealPlacementIsTheBaseline",
	"implausibleSampleDoesNotReachATurn",
	"resyncPlacesBackInRoundOnly",
	"samplesMergeIntoFreshAcceptedCopies",
	"unplacedPlayerIsAbsentAndOutOfReach",
}

local FAST: Scope = { channel = ChannelContract.FAST }
local FULL: Scope = {}
local FAST_WITH_SLICE5: Scope = { channel = ChannelContract.FAST, slice5 = true }

return {
	--[[ ================================================================
	     The reference. Everything below is this stand-in with one defect.
	     ================================================================ ]]

	["baseline: the reference stand-in passes every SLICE-006 check - the AC-2 script wins all 150 rounds on it and loses all 9 control rounds to the clock - AND every SLICE-005, SLICE-003 and VIEW-004 session check, so C-3's narrowings tolerate the new effects and C-6's secondsLeft-free comparison leaves SLICE-003's named cases untouched"] = function()
		local batteries = {
			{ "SLICE-006", ChannelContract.failures(reference), #ChannelContract.CHECKS },
			{ "SLICE-005", RoundContract.failures(reference), #RoundContract.CHECKS },
			{ "SLICE-003", SessionContract.failures(reference), #SessionContract.CHECKS },
			{
				"VIEW-004",
				PositionsContract.sessionFailures(reference, PositionsStubs.reference),
				#PositionsContract.SESSION_CHECKS,
			},
		}
		local summary: { string } = {}
		for _, battery in batteries do
			local label, failures, total = battery[1], battery[2], battery[3]
			local names, messages = sortedNames(failures)
			if #names > 0 then
				error(
					`the reference fails {#names} {label} check(s), so the check or the plan is wrong:\n{shown(
						names,
						messages
					)}`,
					0
				)
			end
			table.insert(summary, `0 of {total} {label}`)
		end
		print(`        [measured] reference fails {table.concat(summary, ", ")} checks`)
	end,

	--[[ ================================================================
	     C-2.
	     ================================================================ ]]

	["control (C-2): a session that accepts a missing or malformed ports argument fails exactly the C-2 check"] = function()
		expectFires(
			"acceptsMissingPorts",
			standIn({ acceptsMissingPorts = true }),
			{ channel = { NEW } },
			FAST
		)
	end,

	--[[ ================================================================
	     AC-1 and C-6: the private views.
	     ================================================================ ]]

	["control (AC-1, the story's): a session that BROADCASTS lens views fails AC-1 (by kind), C-6's reset check, AC-6 (a Broadcast of a private kind) and SLICE-003's own-view check - and the AC-2 script, which never reads a lens off a Broadcast, cannot act and loses every round"] = function()
		expectFires("broadcastsLensViews", standIn({ broadcastsLensViews = true }), {
			channel = { OWN_VIEWS, RESET, SECRET, WIN },
			slice3 = { SLICE3_OWN_SEAT },
		}, FULL)
	end,

	["control (AC-1): a session that sends each player's lens to EVERY seated player fails AC-1, C-6's reset check, C-9 (the deal's shape), AC-6 (a reading outside the recipient's lens) and the AC-2 win (the script's helpers read a lens that is not theirs and ping what they cannot see)"] = function()
		expectFires("sendsLensToEveryone", standIn({ sendsLensToEveryone = true }), {
			channel = { OWN_VIEWS, RESET, ORDER, SECRET, WIN },
		}, FULL)
	end,

	["control (D-3's shape): a session whose lens diff always says 'changed' fails AC-1's no-change clause, C-9, AC-3 and AC-4 (a lens rides on a ping or preset that changed nothing) and the no-effect pins of SLICE-003 and VIEW-004 - while the AC-2 win and AC-6 STILL PASS, so the script is not reading 'a lens arrived' as a signal"] = function()
		expectFires("alwaysSendsLens", standIn({ alwaysSendsLens = true }), {
			channel = { OWN_VIEWS, ORDER, PING_SHOWN, PING_REFUSED, PRESET },
			slice3 = { SLICE3_NOOP, SLICE3_NO_SEAT },
			view4 = VIEW4_NO_EFFECTS,
		}, FULL)
	end,

	["control (D-2's shape): a session whose lens reads the player's OWN key class (the direction error) fails AC-1 (not Projection's view), AC-6 (a setting outside the lens) and the AC-2 win (the helper pings what its dependent cannot use)"] = function()
		expectFires("lensOfOwnClass", standIn({ lensOfOwnClass = true }), {
			channel = { OWN_VIEWS, SECRET, WIN },
		}, FULL)
	end,

	["control (C-6): a session that keeps sent.lens and sent.cues across rounds - reset neither on the deal nor on entering Lobby - fails exactly the reset check (round 2's first view, equal to round 1's last, is never sent)"] = function()
		expectFires(
			"sentKeptAcrossRounds",
			standIn({ sentKeptAcrossRounds = true }),
			{ channel = { RESET } },
			FAST
		)
	end,

	["control (C-6): a session that still sends a withdrawn player their lens fails AC-1 (the leaver clause) and SLICE-003's leave checks (a SendTo to the leaver, an effect on a no-op)"] = function()
		expectFires("sendsWithdrawnPlayers", standIn({ sendsWithdrawnPlayers = true }), {
			channel = { OWN_VIEWS },
			slice3 = { SLICE3_NOOP, SLICE3_NO_SEAT, SLICE3_QUORUM, SLICE3_WITHDRAW },
		}, FAST)
	end,

	--[[ ================================================================
	     AC-3, C-4, C-8: pings.
	     ================================================================ ]]

	["control (D-1's shape): a session whose RoundView never shows a ping fails AC-3's shown check, C-9 (an accepted ping emits no RoundView: the view did not change) and the AC-2 win (no ping shown, no turn: every round is lost to the clock)"] = function()
		expectFires("pingsNeverShown", standIn({ pingsNeverShown = true }), {
			channel = { PING_SHOWN, ORDER, WIN },
		}, FULL)
	end,

	["control (C-4): a session that never ticks the pings (no expiry) fails exactly AC-3's shown check"] = function()
		expectFires(
			"pingsNeverExpire",
			standIn({ pingsNeverExpire = true }),
			{ channel = { PING_SHOWN } },
			FAST
		)
	end,

	["control (C-4): a session whose pings survive their machine's commit fails exactly AC-3's shown check"] = function()
		expectFires(
			"pingsSurviveCommit",
			standIn({ pingsSurviveCommit = true }),
			{ channel = { PING_SHOWN } },
			FAST
		)
	end,

	["control (AC-3): a session that BROADCASTS the refusal fails exactly AC-3's refusal check"] = function()
		expectFires(
			"broadcastsPingRefused",
			standIn({ broadcastsPingRefused = true }),
			{ channel = { PING_REFUSED } },
			FAST
		)
	end,

	["control (C-4): a session that declines the call on an ACCEPTED ping fails exactly AC-3's shown check"] = function()
		expectFires(
			"declinesAcceptedPing",
			standIn({ declinesAcceptedPing = true }),
			{ channel = { PING_SHOWN } },
			FAST
		)
	end,

	["control (C-4): a session that hands the held procedure to Pings.request outside Round (a ping judged in Resolution) fails exactly AC-3's refusal check (no_such_target expected)"] = function()
		expectFires(
			"pingsJudgedOutsideRound",
			standIn({ pingsJudgedOutsideRound = true }),
			{ channel = { PING_REFUSED } },
			FAST
		)
	end,

	["control (C-4): a session whose RoundView shows the channel's pings outside Round fails exactly AC-3's shown check"] = function()
		expectFires(
			"pingsShownOutsideRound",
			standIn({ pingsShownOutsideRound = true }),
			{ channel = { PING_SHOWN } },
			FAST
		)
	end,

	["control (C-6): a session that broadcasts the RoundView only on SLICE-003's triggers, never because its contents changed, fails AC-3's shown check (no RoundView in the ping's own step) and C-9 (an accepted ping emits nothing)"] = function()
		expectFires("roundViewOnlyOnOldTriggers", standIn({ roundViewOnlyOnOldTriggers = true }), {
			channel = { PING_SHOWN, ORDER },
		}, FAST)
	end,

	["control (C-8): a session that keeps the channel into the next Lobby fails exactly AC-3's shown check (its C-8 clause)"] = function()
		expectFires(
			"channelKeptInLobby",
			standIn({ channelKeptInLobby = true }),
			{ channel = { PING_SHOWN } },
			FAST
		)
	end,

	["control (C-8): a session that resets the channel on entering Post fails exactly AC-3's shown check (its C-8 clause)"] = function()
		expectFires(
			"channelResetInPost",
			standIn({ channelResetInPost = true }),
			{ channel = { PING_SHOWN } },
			FAST
		)
	end,

	--[[ ================================================================
	     AC-4, C-5: presets.
	     ================================================================ ]]

	["control (AC-4): a session that shows every preset at the origin instead of the sender's stored position fails exactly the AC-4 check"] = function()
		expectFires(
			"presetAtTheOrigin",
			standIn({ presetAtTheOrigin = true }),
			{ channel = { PRESET } },
			FAST
		)
	end,

	["control (C-5): a session that shows the table's word whatever `filtered` says fails the AC-4 check (the text, and a failing filter still shown) and C-9 (a failed preset's effects are a PresetShown)"] = function()
		expectFires(
			"presetIgnoresFilter",
			standIn({ presetIgnoresFilter = true }),
			{ channel = { PRESET, ORDER } },
			FAST
		)
	end,

	["control (AC-4): a session that BROADCASTS the failure fails exactly the AC-4 check"] = function()
		expectFires(
			"broadcastsPresetFailed",
			standIn({ broadcastsPresetFailed = true }),
			{ channel = { PRESET } },
			FAST
		)
	end,

	["control (C-5, PO-4): a session that invents a position for a player with none fails exactly the AC-4 check"] = function()
		expectFires(
			"presetInventsAPosition",
			standIn({ presetInventsAPosition = true }),
			{ channel = { PRESET } },
			FAST
		)
	end,

	["control (C-5, PO-4): a session that leaves the call undeclined when the sender has no stored position fails exactly the AC-4 check"] = function()
		expectFires(
			"presetWithoutPositionNotDeclined",
			standIn({ presetWithoutPositionNotDeclined = true }),
			{ channel = { PRESET } },
			FAST
		)
	end,

	--[[ ================================================================
	     AC-5, C-7, C-9: the FacilityView and the order.
	     ================================================================ ]]

	["control (AC-5): a session that never broadcasts a FacilityView fails AC-5, C-9 (the deal's shape) and - the script cannot locate a machine without it - the AC-2 win and AC-6's precondition (no lens ever reads anything)"] = function()
		expectFires("noFacilityView", standIn({ noFacilityView = true }), {
			channel = { FACILITY, ORDER, SECRET, WIN },
		}, FULL)
	end,

	["control (C-7): a session that broadcasts a FacilityView on every Tick fails exactly the AC-5 check"] = function()
		expectFires(
			"facilityViewOnEveryTick",
			standIn({ facilityViewOnEveryTick = true }),
			{ channel = { FACILITY } },
			FAST
		)
	end,

	["control (C-7): a session that broadcasts an (empty) FacilityView when generation FAILED fails exactly the AC-5 check"] = function()
		expectFires(
			"facilityViewOnFailedGeneration",
			standIn({ facilityViewOnFailedGeneration = true }),
			{ channel = { FACILITY } },
			FAST
		)
	end,

	["control (C-9): a session that emits the FacilityView LAST, after the RoundView, fails AC-5 (its order clause), C-9, and the order checks of SLICE-005 and SLICE-003 (the RoundView is no longer last)"] = function()
		expectFires("facilityViewAfterRoundView", standIn({ facilityViewAfterRoundView = true }), {
			channel = { FACILITY, ORDER },
			slice5 = { SLICE5_ORDER },
			slice3 = { SLICE3_ORDER },
		}, FAST_WITH_SLICE5)
	end,
}
