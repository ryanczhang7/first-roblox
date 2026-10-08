--!strict
--[[
	The wrong senders CHAN-004's negative controls are aimed at, and the one
	reference every check in `PresetSendsContract.luau` must ACCEPT.

	THE CRITERIA AND THE DEFERRED VERIFICATIONS NAME THEIR CONTROLS. C-10's
	five: a send that shows the unfiltered word on failure
	(`showsWordOnFilterFailure`, D-2's shape), one that does not decline on a
	filter failure (`noDeclineOnFilterFailure`, D-3's shape), one that calls
	the filter for an out-of-phase preset (`filtersOutOfPhase`), one that
	consumes nothing and shows nothing (`showsNothing`: every send is declined
	and failed, so no filter result is ever broadcast), and one that mutates
	the given state (`mutatesState`). D-4's shape is `skipsPhaseCheck`. The
	rest are the Contract's C-4 and C-5 clauses, one defect each, so that what
	GATES will mutate into the real module has already been seen to be caught
	by the checks that will judge it.

	THE POSITIVE CONTROL is `reference`: C-4's four steps and C-5's copy rules
	written out. It exists so that every check is shown to ACCEPT a correct
	implementation in RED: a check that refuses everything is
	indistinguishable from a broken one. Each wrong implementation is the
	reference with EXACTLY ONE thing changed, so the set of checks that fire
	is attributable to that one change, and `preset_sends_controls_test.luau`
	pins that set EXACTLY.

	WHAT THIS IS NOT: `src/server/channel/PresetSends.luau`, or a sketch of
	one. It exports no types, freezes nothing, and its defects are parameters.
	GREEN writes the module from the story's Contract; nothing here is to be
	copied.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE - `Presets` (CHAN-002) is
	merged - so these controls are EXECUTED in RED, and the controls tests
	record what each measured.
]]

local Presets = require("../../src/ReplicatedStorage/Shared/channel/Presets")

local PresetSendsStubs = {}

export type Defect =
	"showsWordOnFilterFailure" -- D-2: a failed filter shows (and logs) the table's word
	| "noDeclineOnFilterFailure" -- D-3: a filter failure is `failed` but the call is not declined
	| "filtersOutOfPhase" -- the filter is called for an out-of-phase preset before it is refused
	| "skipsPhaseCheck" -- D-4: the per-preset phase list is never consulted
	| "mutatesState" -- a shown send appends into the state it was given and returns it
	| "showsNothing" -- every send is declined and `failed` for `filter`: consumes nothing, shows nothing
	| "showsWordNotFilterText" -- `shown.text` is the table's word, not the string the filter returned
	| "sharesPosition" -- `shown.position` and the log entry alias the caller's table
	| "declinesOnShown" -- a shown send declines the call too
	| "declinesTwiceOnFailure" -- a failure declines the call twice
	| "noDeclineOnPhase" -- an out-of-phase preset is `failed` but not declined
	| "logsOnFailure" -- a failed send is appended to the log as if shown
	| "filterTwice" -- the filter is called twice per send that reaches it
	| "acceptsTrueNil" -- `(true, nil)` from the filter is shown as the word
	| "raiseEscapes" -- no pcall: a raising filter raises out of `send`
	| "logOmitsAt" -- the log entry has no `at`
	| "failedCarriesWord" -- `PresetFailed` carries a third key, the word
	| "sharesLog" -- the returned state's log IS the given state's table (unmodified, but aliased)

PresetSendsStubs.DEFECTS = {
	"showsWordOnFilterFailure",
	"noDeclineOnFilterFailure",
	"filtersOutOfPhase",
	"skipsPhaseCheck",
	"mutatesState",
	"showsNothing",
	"showsWordNotFilterText",
	"sharesPosition",
	"declinesOnShown",
	"declinesTwiceOnFailure",
	"noDeclineOnPhase",
	"logsOnFailure",
	"filterTwice",
	"acceptsTrueNil",
	"raiseEscapes",
	"logOmitsAt",
	"failedCarriesWord",
	"sharesLog",
} :: { Defect }

type Position = { x: number, y: number, z: number }

-- The module table for `defect` (nil: the reference).
function PresetSendsStubs.with(defect: Defect?): any
	local function copyOf(position: Position): Position
		if defect == "sharesPosition" then
			return position
		end
		return { x = position.x, y = position.y, z = position.z }
	end

	local function appended(
		state: any,
		senderId: string,
		presetId: number,
		position: Position,
		now: number
	): any
		local entry: { [string]: any } =
			{ senderId = senderId, presetId = presetId, position = copyOf(position), at = now }
		if defect == "logOmitsAt" then
			entry.at = nil
		end
		if defect == "mutatesState" then
			table.insert(state.log, entry)
			return state
		end
		local log = table.clone(state.log)
		table.insert(log, entry)
		return { log = log }
	end

	local function failed(presetId: number, reason: string, word: string): any
		local payload: { [string]: any } = { presetId = presetId, reason = reason }
		if defect == "failedCarriesWord" then
			payload.word = word
		end
		return { kind = "failed", failed = payload }
	end

	local function unchanged(state: any): any
		if defect == "sharesLog" then
			return state
		end
		return { log = table.clone(state.log) }
	end

	local function new(): any
		return { log = {} }
	end

	local function send(
		state: any,
		senderId: string,
		presetId: number,
		phase: string,
		position: Position,
		now: number,
		filter: any,
		call: any
	): (any, any)
		local preset = Presets.byId(presetId)
		if preset == nil then
			error(`PresetSendsStubs: no preset {tostring(presetId)}`)
		end
		local inPhase = table.find(preset.phases, phase) ~= nil
		-- Decided up front: the analyser narrows `defect` through a branch
		-- condition and then refuses a second comparison inside it.
		local filtersOutOfPhase = defect == "filtersOutOfPhase"
		local skipsPhaseCheck = defect == "skipsPhaseCheck"
		local declinesOnPhase = defect ~= "noDeclineOnPhase"
		local showsNothing = defect == "showsNothing"
		local raiseEscapes = defect == "raiseEscapes"
		local filterTwice = defect == "filterTwice"
		local acceptsTrueNil = defect == "acceptsTrueNil"
		local showsWordOnFilterFailure = defect == "showsWordOnFilterFailure"
		local declinesOnFilterFailure = defect ~= "noDeclineOnFilterFailure"
		local declinesTwiceOnFailure = defect == "declinesTwiceOnFailure"
		local logsOnFailure = defect == "logsOnFailure"
		local showsWordNotFilterText = defect == "showsWordNotFilterText"
		local declinesOnShown = defect == "declinesOnShown"

		if not inPhase and filtersOutOfPhase then
			pcall(filter, senderId, preset.word)
		end
		if not inPhase and not skipsPhaseCheck then
			if declinesOnPhase then
				call.decline()
			end
			return unchanged(state), failed(presetId, "phase_for_preset", preset.word)
		end

		if showsNothing then
			call.decline()
			return unchanged(state), failed(presetId, "filter", preset.word)
		end

		local ok: boolean, okFiltered: any, text: any
		if raiseEscapes then
			ok = true
			okFiltered, text = filter(senderId, preset.word)
		else
			ok, okFiltered, text = pcall(filter, senderId, preset.word)
		end
		if filterTwice then
			pcall(filter, senderId, preset.word)
		end

		local passed = ok and okFiltered == true and typeof(text) == "string"
		if acceptsTrueNil and ok and okFiltered == true and text == nil then
			passed = true
			text = preset.word
		end

		if not passed then
			if showsWordOnFilterFailure then
				return appended(state, senderId, presetId, position, now),
					{
						kind = "shown",
						shown = {
							senderId = senderId,
							presetId = presetId,
							position = copyOf(position),
							text = preset.word,
						},
					}
			end
			if declinesOnFilterFailure then
				call.decline()
			end
			if declinesTwiceOnFailure then
				call.decline()
			end
			if logsOnFailure then
				return appended(state, senderId, presetId, position, now),
					failed(presetId, "filter", preset.word)
			end
			return unchanged(state), failed(presetId, "filter", preset.word)
		end

		local shownText = if showsWordNotFilterText then preset.word else text
		if declinesOnShown then
			call.decline()
		end
		return appended(state, senderId, presetId, position, now),
			{
				kind = "shown",
				shown = {
					senderId = senderId,
					presetId = presetId,
					position = copyOf(position),
					text = shownText,
				},
			}
	end

	return { new = new, send = send }
end

-- The positive control.
PresetSendsStubs.reference = PresetSendsStubs.with(nil)

return PresetSendsStubs
