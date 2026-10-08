--!strict
--[[
	CHAN-004: whether a preset is shown. Pure: no clock, no transport, no
	state of its own. The `SendPreset` remote's guard (`net/GameRemotes`) has
	already checked identity, shape, the schema's bound on the id, that the
	phase is in the union of every preset's phases, and both rate limits by
	the time a call gets here. What is left is the preset's OWN phase list and
	the text filter (`mechanics.md` §4.2).

	THE ORDER IS THE CONTRACT'S (C-4), FIRST FAILURE WINS:

	  1. `phase_for_preset`  `phase` is not in the preset's `phases`. The
	                         filter is not called: the refusal comes first.
	  2. `filter`            the filter, called EXACTLY ONCE under `pcall`
	                         with the sender's id and the table's `word`,
	                         raised, answered anything but `true`, or returned
	                         a text that is not a string. FAILS CLOSED (C5):
	                         nothing is shown and nothing is logged.

	A failure declines `call` exactly once - it is not a send, so the guard
	refunds the send limit and only the attempt floor applies (G9,
	`CHAN-003`) - and is returned for the caller to send to the sender alone
	(C-6, `SLICE-006`). A preset that is shown never touches `call`.

	`text` IS WHAT THE FILTER RETURNED (`architecture.md` §9.5.1), which may
	differ from the table's word; this module never substitutes the word.

	`position` IS THE SERVER'S ACCEPTED SAMPLE (`architecture.md` §9.8),
	passed in by the session. It is copied into the result and the log, so a
	later write to the caller's table moves neither (C-5).

	STATE IS IMMUTABLE (C-5), as in `Pings`: `send` returns a new state whose
	log is the old one plus one entry, and never writes into the one it was
	given. A failure returns the given state unchanged.
]]

local Presets = require("@game/ReplicatedStorage/Shared/channel/Presets")

local PresetSends = {}

export type Position = { x: number, y: number, z: number }
export type PresetShown = {
	senderId: string,
	presetId: number,
	position: Position,
	text: string,
}
export type FailReason = "phase_for_preset" | "filter"
export type PresetFailed = { presetId: number, reason: FailReason }
export type PresetLogEntry = {
	senderId: string,
	presetId: number,
	position: Position,
	at: number,
}
export type PresetState = { log: { PresetLogEntry } }
export type Filter = (senderId: string, text: string) -> (boolean, string?)
export type SendResult =
	{ kind: "shown", shown: PresetShown }
	| { kind: "failed", failed: PresetFailed }
-- Structural: `Wrapper.CallControl` satisfies it, and nothing else is read (C-3).
export type CallControl = { decline: () -> () }

function PresetSends.new(): PresetState
	return { log = {} }
end

local function copy(position: Position): Position
	return { x = position.x, y = position.y, z = position.z }
end

local function failure(presetId: number, reason: FailReason): SendResult
	return { kind = "failed", failed = { presetId = presetId, reason = reason } }
end

local function accept(
	state: PresetState,
	senderId: string,
	presetId: number,
	position: Position,
	now: number,
	text: string
): (PresetState, SendResult)
	local log = table.clone(state.log)
	local entry: PresetLogEntry =
		{ senderId = senderId, presetId = presetId, position = copy(position), at = now }
	table.insert(log, entry)
	local shown: PresetShown =
		{ senderId = senderId, presetId = presetId, position = copy(position), text = text }
	return { log = log }, { kind = "shown", shown = shown }
end

--[[
	Judges one preset send, in the order this module's header gives. An
	unknown `presetId` is a precondition violation (the schema bounds it to
	`1..preset_count`) and raises.
]]
function PresetSends.send(
	state: PresetState,
	senderId: string,
	presetId: number,
	phase: string,
	position: Position,
	now: number,
	filter: Filter,
	call: CallControl
): (PresetState, SendResult)
	local preset = Presets.byId(presetId)
	assert(preset ~= nil, `PresetSends.send: no preset has id {presetId}`)

	local legal = table.find(preset.phases, phase) ~= nil
	if not legal then
		call.decline() -- refused by its own phase list
		return state, failure(presetId, "phase_for_preset")
	end

	local ok, okFiltered, text = pcall(filter, senderId, preset.word)
	if not ok or okFiltered ~= true or type(text) ~= "string" then
		call.decline() -- the filter failed: fail closed (C5)
		return state, failure(presetId, "filter")
	end

	return accept(state, senderId, presetId, position, now, text)
end

return table.freeze(PresetSends)
