--!strict
--[[
	The negative controls for SLICE-004 AC-3, and the proof that each check
	in `tests/helpers/PhaseClockContract.luau` refuses the model it exists to
	catch - plus the `VoiceSpec` reader's own discrimination, since a reader
	that found rows under the wrong heading would make the words check
	vacuous.

	EVERY CONTROL IS ASSERTED TO FAIL EXACTLY THE CHECKS IT SHOULD, and the
	baseline to pass every check. The sets were MEASURED under
	`lune run test` in RED and pinned here; the story's `## Handoff` carries
	the table and says which boundary row kills which mutant.

	ONE CONTROL IS PINNED AS NOT CAUGHT. `phaseKeyBypassesWords` returns
	`view.phase` instead of `Words.phase[view.phase]`, and because voice.md
	§2.1 maps every phase to its own name today, no observation can tell the
	two apart. It is listed with an empty set so that the day the table stops
	being the identity - a HUD story replacing the label - this file goes red
	and the blind spot is closed on purpose.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE: the models are
	`PhaseClockStubs.luau`, and the reader runs over the real voice.md and
	over fixtures.
]]

local Contract = require("../helpers/PhaseClockContract")
local Stubs = require("../helpers/PhaseClockStubs")
local VoiceSpec = require("../helpers/VoiceSpec")

type Check = (any) -> ()
type Named = { label: string, check: Check }

local CHECKS: { Named } = {
	{ label = "words", check = Contract.wordsMatchTheVoiceTable },
	{ label = "phaseKey", check = Contract.phaseKeyIsWordsPhaseForEveryPhase },
	{ label = "unknown phase", check = Contract.aPhaseWithNoWordRaisesNamingIt },
	{ label = "countdown", check = Contract.countdownIsCeilOfRemainingAsMinutesAndTwoDigitSeconds },
	{ label = "nil seconds", check = Contract.nilSecondsLeftGivesNoCountdown },
}

local EXPECTED: { [string]: { string } } = {
	floorsInsteadOfCeil = { "countdown" },
	roundsInsteadOfCeil = { "countdown" },
	noClamp = { "countdown" },
	paddedMinutes = { "countdown" },
	unpaddedSeconds = { "countdown" },
	ignoresReceivedAt = { "countdown" },
	ignoresElapsed = { "countdown" },
	nilSecondsLeftReadsZero = { "nil seconds" },
	mutatesTheView = { "countdown" },
	echoesUnknownPhase = { "unknown phase" },
	wordDrift = { "words" },
	extraWord = { "words" },
	missingWord = { "words", "phaseKey" },
	phaseKeyBypassesWords = {},
}

local function failing(bundle: any): ({ string }, { [string]: string })
	local labels: { string } = {}
	local messages: { [string]: string } = {}
	for _, named in CHECKS do
		local ok, err = pcall(named.check, bundle)
		if not ok then
			table.insert(labels, named.label)
			messages[named.label] = tostring(err)
		end
	end
	return labels, messages
end

local function same(a: { string }, b: { string }): boolean
	if #a ~= #b then
		return false
	end
	local x, y = table.clone(a), table.clone(b)
	table.sort(x)
	table.sort(y)
	for i, v in x do
		if y[i] ~= v then
			return false
		end
	end
	return true
end

local function has(message: string, needle: string): boolean
	return string.find(message, needle, 1, true) ~= nil
end

local tests: { [string]: () -> () } = {}

tests["baseline: a correct model passes every AC-3 check, which also shows VoiceSpec read the live voice.md"] = function()
	local labels, messages = failing(Stubs.build({}))
	local detail: { string } = {}
	for _, label in labels do
		table.insert(detail, `{label}: {messages[label]}`)
	end
	assert(#labels == 0, `the baseline failed {#labels} check(s):\n` .. table.concat(detail, "\n"))
end

tests["every defect in PhaseClockStubs.DEFECTS has an expected set here, and the reverse"] = function()
	local missing: { string } = {}
	for _, defect in Stubs.DEFECTS do
		if EXPECTED[defect] == nil then
			table.insert(missing, defect)
		end
	end
	assert(#missing == 0, `no expected set for: {table.concat(missing, ", ")}`)
	local stray: { string } = {}
	for defect in EXPECTED do
		if table.find(Stubs.DEFECTS, defect) == nil then
			table.insert(stray, defect)
		end
	end
	assert(
		#stray == 0,
		`expected sets for defects the stubs do not build: {table.concat(stray, ", ")}`
	)
end

for _, defect in Stubs.DEFECTS do
	tests[`control {defect}: fails exactly [{table.concat(EXPECTED[defect] or {}, ", ")}]`] = function()
		local want = EXPECTED[defect]
		assert(want ~= nil, `no expected set for {defect}`)
		local labels, messages = failing(Stubs.build({ [defect] = true }))
		if not same(labels, want :: { string }) then
			local detail: { string } = {}
			for _, label in labels do
				table.insert(detail, `  {label}: {messages[label]}`)
			end
			error(
				`{defect} failed [{table.concat(labels, ", ")}], expected [{table.concat(
					want :: { string },
					", "
				)}]\n` .. table.concat(detail, "\n"),
				0
			)
		end
	end
end

--[[ Which row kills which mutant. The message names the rows, so these
     pin that each mutant dies on the boundary it was written for. ]]

local function countdownFailure(defect: string): string
	local ok, err = pcall(
		Contract.countdownIsCeilOfRemainingAsMinutesAndTwoDigitSeconds,
		Stubs.build({ [defect] = true })
	)
	assert(ok == false, `{defect} passed the countdown check`)
	return tostring(err)
end

tests["AC-3 rows: floor is killed by 0.2 -> 0:00 and 59.5 -> 0:59, and passes the whole-second rows"] = function()
	local message = countdownFailure("floorsInsteadOfCeil")
	assert(has(message, '-> "0:00", wanted "0:01"'), message)
	assert(has(message, '-> "0:59", wanted "1:00"'), message)
	assert(has(message, "4 wrong row(s)"), message)
end

tests["AC-3 rows: round-half-up is killed by 0.2 -> 0:00 alone; 59.5 and 60.5 round up correctly"] = function()
	local message = countdownFailure("roundsInsteadOfCeil")
	assert(has(message, '-> "0:00", wanted "0:01"'), message)
	assert(has(message, "1 wrong row(s)"), message)
end

tests["AC-3 rows: no clamp is killed by the past-the-end row, which formats a negative remainder"] = function()
	local message = countdownFailure("noClamp")
	assert(has(message, 'now 500 -> "-2:40", wanted "0:00"'), message)
	assert(has(message, "1 wrong row(s)"), message)
end

tests["AC-3 rows: %02d:%02d is killed by every row with single-digit minutes, and 10:00 survives"] = function()
	local message = countdownFailure("paddedMinutes")
	assert(has(message, '-> "07:00", wanted "7:00"'), message)
	assert(not has(message, 'wanted "10:00"'), message)
	assert(has(message, "10 wrong row(s)"), message)
end

tests["AC-3 rows: ignoring receivedAt is killed only by the rows received at 100"] = function()
	local message = countdownFailure("ignoresReceivedAt")
	assert(has(message, 'receivedAt 100, now 130.5 -> "4:50", wanted "6:30"'), message)
	assert(has(message, 'receivedAt 100, now 100 -> "5:20", wanted "7:00"'), message)
	assert(has(message, "2 wrong row(s)"), message)
end

tests["AC-3 rows: ignoring elapsed time is killed by the past-the-end row and the 130.5 row"] = function()
	local message = countdownFailure("ignoresElapsed")
	assert(has(message, 'now 500 -> "7:00", wanted "0:00"'), message)
	assert(has(message, 'now 130.5 -> "7:00", wanted "6:30"'), message)
	assert(has(message, "2 wrong row(s)"), message)
end

--[[ The words check names the drift. ]]

tests["AC-3 words control: a drifted word is reported against the voice.md line that fixes it"] = function()
	local ok, err = pcall(Contract.wordsMatchTheVoiceTable, Stubs.build({ wordDrift = true }))
	assert(ok == false, "a drifted word passed")
	assert(has(tostring(err), 'Words.phase.Post is "Done"; voice.md line'), tostring(err))
end

tests["AC-3 words control: a word voice.md does not name is reported as extra"] = function()
	local ok, err = pcall(Contract.wordsMatchTheVoiceTable, Stubs.build({ extraWord = true }))
	assert(ok == false, "an extra word passed")
	assert(
		has(
			tostring(err),
			'Words.phase.Intermission = "Intermission" is in the module, but no voice.md §2.1 row names it'
		),
		tostring(err)
	)
end

--[[ The reader's discrimination, over fixtures. ]]

local FIXTURE = table.concat({
	"# Voice",
	"",
	"## 2. The words",
	"",
	"| Concept (internal) | Player-facing | Glyph |",
	"|---|---|---|",
	"| rematch | Again | `glyph.again` |",
	"",
	"### 2.1 The phase label",
	"",
	"| Phase (internal) | Player-facing |",
	"|---|---|",
	"| `Lobby` | Lobby |",
	"| `Round` |   Go time   |",
	"| no backticks | skipped |",
	"",
	"The countdown beside it reads `m:ss`.",
	"",
	"## 3. The trace headline",
	"",
	"| `Post` | Not this one |",
}, "\n")

tests["VoiceSpec: reads the backticked rows under ### 2.1, trimmed, and nothing under another heading"] = function()
	local rows = VoiceSpec.parsePhaseTable(FIXTURE)
	assert(#rows == 2, `read {#rows} rows, wanted 2`)
	assert(
		rows[1].internal == "Lobby" and rows[1].facing == "Lobby",
		`row 1: {rows[1].internal} -> {rows[1].facing}`
	)
	assert(
		rows[2].internal == "Round" and rows[2].facing == "Go time",
		`row 2: {rows[2].internal} -> {rows[2].facing}`
	)
	assert(rows[1].line == 13 and rows[2].line == 14, `lines {rows[1].line}, {rows[2].line}`)
end

tests["VoiceSpec: a renamed heading reads zero rows, and vacuity says so"] = function()
	local rows = VoiceSpec.parsePhaseTable(FIXTURE, "2.2")
	assert(#rows == 0, `read {#rows} rows under a heading that is not there`)
	local vacuity = VoiceSpec.vacuity(rows)
	assert(#vacuity == 1 and has(vacuity[1], "read 0 phase rows"), table.concat(vacuity, "\n"))
end

tests["VoiceSpec: a phase named twice and an empty word are both reported"] = function()
	local rows = VoiceSpec.parsePhaseTable(
		"### 2.1 x\n| `Lobby` | Lobby |\n| `Lobby` | Foyer |\n| `Post` |  |\n"
	)
	assert(#rows == 3, `read {#rows} rows, wanted 3`)
	local vacuity = VoiceSpec.vacuity(rows)
	assert(
		#vacuity == 2,
		`wanted 2 vacuity findings, got {#vacuity}: {table.concat(vacuity, "; ")}`
	)
	assert(has(vacuity[1], "already a row at line 2"), vacuity[1])
	assert(has(vacuity[2], "empty player-facing word"), vacuity[2])
end

tests["VoiceSpec: the live voice.md §2.1 names exactly the machine's phases, read through the gate hash"] = function()
	local rows = Contract.voiceRows()
	local phases = Contract.machinePhases()
	assert(
		#rows == #phases,
		`voice.md §2.1 has {#rows} rows; PhaseMachine's union has {#phases} phases`
	)
	for _, phase in phases do
		local found = false
		for _, row in rows do
			if row.internal == phase then
				found = true
			end
		end
		assert(found, `the machine's phase {phase} has no §2.1 row`)
	end
end

return tests
