--!strict
--[[
	SLICE-004 AC-3 applied to the real `src/client/models/PhaseClockModel.luau`
	and `src/client/Words.luau`.

	THE TWO MODULES DO NOT EXIST IN RED, so both requires below fail and
	every test here FAILS naming the module that did not load. That is the
	right failure: they are the first thing AC-3 requires. The checks live in
	`tests/helpers/PhaseClockContract.luau`, and every one of them has been
	OBSERVED to fire in `tests/client/phase_clock_controls_test.luau` against
	the model it exists to catch - floor for ceil, no clamp, padded minutes,
	a receive time ignored, a word drifted from voice.md.

	The export shape pinned here (nothing below is a suggestion; a wrong name
	is a nil call):

	    PhaseClockModel.describe(view: { phase: string, secondsLeft: number? }, receivedAt: number, now: number)
	        -> { phaseKey: string, countdown: string? }
	    Words.phase: { [string]: string }   -- voice.md §2.1, by internal phase name

	No `phaseKey` assertion here compares to a literal: the oracle for the
	words is `Words.phase[...]`, and the oracle for `Words.phase` is
	`docs/wiki/design/voice.md` §2.1, read off disk by `VoiceSpec`.
]]

local Contract = require("../helpers/PhaseClockContract")

local MODEL = "src/client/models/PhaseClockModel.luau"
local WORDS = "src/client/Words.luau"

local modelLoaded, modelResult = pcall(require, "@game/client/models/PhaseClockModel")
local wordsLoaded, wordsResult = pcall(require, "@game/client/Words")

local function bundle(): Contract.Bundle
	assert(modelLoaded, `{MODEL} did not load: {tostring(modelResult)}`)
	assert(wordsLoaded, `{WORDS} did not load: {tostring(wordsResult)}`)
	local model = modelResult :: any
	assert(
		typeof(model) == "table" and typeof(model.describe) == "function",
		`{MODEL} must export describe as a function; it exports {typeof(model)}`
	)
	return { describe = model.describe, Words = wordsResult }
end

return {
	--[[ AC-3, the words: settled by voice.md §2.1 ]]

	["AC-3: Words.phase is exactly voice.md §2.1's table, read from the file, and names every phase in PhaseMachine's union"] = function()
		Contract.wordsMatchTheVoiceTable(bundle())
	end,

	["AC-3: describe(view).phaseKey is Words.phase[view.phase] for every phase in PhaseMachine's union, with and without secondsLeft"] = function()
		Contract.phaseKeyIsWordsPhaseForEveryPhase(bundle())
	end,

	['AC-3: a phase Words.phase does not name ("Limbo") raises naming it rather than echoing it'] = function()
		Contract.aPhaseWithNoWordRaisesNamingIt(bundle())
	end,

	--[[ AC-3, the countdown: mechanical ]]

	["AC-3: countdown is %d:%02d of ceil(max(0, secondsLeft - (now - receivedAt))): 420 -> 7:00, 0.2 -> 0:01, 59.5 -> 1:00, 9 -> 0:09, past the end -> 0:00, received at 100 and read at 130.5 -> 6:30"] = function()
		Contract.countdownIsCeilOfRemainingAsMinutesAndTwoDigitSeconds(bundle())
	end,

	["AC-3: with secondsLeft nil the countdown is nil"] = function()
		Contract.nilSecondsLeftGivesNoCountdown(bundle())
	end,
}
