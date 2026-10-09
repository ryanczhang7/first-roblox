--!strict
--[[
	SLICE-004 AC-3 written once, as checks over a bundle
	`{ describe, Words }`, so that `tests/client/phase_clock_model_test.luau`
	can apply them to the real `src/client/models/PhaseClockModel.luau` and
	`src/client/Words.luau`, and `tests/client/phase_clock_controls_test.luau`
	can apply them to the wrong models in `PhaseClockStubs.luau` - executed in
	RED, before the real modules exist.

	    describe(view: { phase: string, secondsLeft: number? }, receivedAt: number, now: number)
	        -> { phaseKey: string, countdown: string? }
	    Words.phase: { [string]: string }

	THE ORACLE IS PARTITIONED, as the story's `## Contract` partitions it:
	  * the WORDS are SETTLED by `voice.md` §2.1. `wordsMatchTheVoiceTable`
	    reads that table through `VoiceSpec` and compares `Words.phase` to it
	    row by row, both directions. `phaseKeyIsWordsPhaseForEveryPhase`
	    compares `describe(...).phaseKey` to `Words.phase[phase]` - never to
	    a literal - for every phase the machine's own `Phase` union names,
	    read out of `PhaseMachine.luau` by `PhaseUnion`.
	  * the ARITHMETIC is MECHANICAL and pinned exactly: `whole = ceil(max(0,
	    secondsLeft - (now - receivedAt)))`, text `%d:%02d` of `whole // 60`
	    and `whole % 60`. The boundary table below is the Contract's examples
	    plus the ones that separate ceil from floor and from round, the clamp
	    from no clamp, and `receivedAt` from being ignored. The controls test
	    says which row kills which mutant.

	The checks accumulate violations and raise once, through `Contract.fail`,
	so a message carries every wrong row rather than the first.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local GatedFs = require("./GatedFs")
local PhaseUnion = require("./PhaseUnion")
local VoiceSpec = require("./VoiceSpec")

local PhaseClockContract = {}

export type Bundle = { describe: any, Words: any }

PhaseClockContract.PHASE_MACHINE = "src/server/round/PhaseMachine.luau"

-- The machine's phases, read from its `Phase` union, never listed here.
function PhaseClockContract.machinePhases(): { string }
	local path = PhaseClockContract.PHASE_MACHINE
	local side = PhaseUnion.read(path, GatedFs.readFile(path))
	if #side.phases == 0 then
		Contract.fail(
			`{path}: PhaseUnion read no phases out of it; the guard would be over nothing`
		)
	end
	return side.phases
end

-- voice.md §2.1's rows, with the reader's own vacuity reported.
function PhaseClockContract.voiceRows(): { VoiceSpec.PhaseRow }
	local rows = VoiceSpec.parsePhaseTable(VoiceSpec.read())
	local vacuity = VoiceSpec.vacuity(rows)
	if #vacuity > 0 then
		Contract.fail(`voice.md §2.1 is not a usable table:\n` .. Contract.firstFew(vacuity, 8))
	end
	return rows
end

--[[ AC-3, the words ]]

-- `Words.phase` is exactly voice.md §2.1: every row is in it with that
-- word, nothing is in it that the table does not name, and the table names
-- every phase the machine has.
function PhaseClockContract.wordsMatchTheVoiceTable(bundle: Bundle)
	local phase = bundle.Words.phase
	if typeof(phase) ~= "table" then
		Contract.fail(`AC-3 words: Words.phase is {typeof(phase)}, wanted a table`)
	end
	local rows = PhaseClockContract.voiceRows()
	local violations: { string } = {}
	local named: { [string]: boolean } = {}
	for _, row in rows do
		named[row.internal] = true
		local got = phase[row.internal]
		if got ~= row.facing then
			table.insert(
				violations,
				`Words.phase.{row.internal} is {Deep.show(got)}; voice.md line {row.line} says "{row.facing}"`
			)
		end
	end
	for key, value in phase do
		if not named[key] then
			table.insert(
				violations,
				`Words.phase.{tostring(key)} = {Deep.show(value)} is in the module, but no voice.md §2.1 row names it`
			)
		end
	end
	for _, machinePhase in PhaseClockContract.machinePhases() do
		if not named[machinePhase] then
			table.insert(violations, `the machine's phase {machinePhase} has no voice.md §2.1 row`)
		end
	end
	if #violations > 0 then
		Contract.fail(
			`AC-3 words: {#violations} drift(s) between Words.phase and voice.md §2.1:\n`
				.. Contract.firstFew(violations, 10)
		)
	end
end

-- For every machine phase, `describe` answers `Words.phase[phase]` as the
-- key, with and without a countdown. Compared to the module's own table,
-- never to a literal.
function PhaseClockContract.phaseKeyIsWordsPhaseForEveryPhase(bundle: Bundle)
	local violations: { string } = {}
	local phases = PhaseClockContract.machinePhases()
	for _, phase in phases do
		local want = bundle.Words.phase[phase]
		if typeof(want) ~= "string" then
			table.insert(violations, `Words.phase.{phase} is {Deep.show(want)}, not a string`)
		else
			for _, secondsLeft in { 30, nil } do
				local ok, result =
					pcall(bundle.describe, { phase = phase, secondsLeft = secondsLeft }, 10, 12)
				if not ok then
					table.insert(
						violations,
						`describe({phase}, secondsLeft {Deep.show(secondsLeft)}) raised: {tostring(
							result
						)}`
					)
				elseif typeof(result) ~= "table" or result.phaseKey ~= want then
					table.insert(
						violations,
						`describe({phase}, secondsLeft {Deep.show(secondsLeft)}).phaseKey is {Deep.show(
							if typeof(result) == "table" then result.phaseKey else result
						)}, wanted Words.phase.{phase} = "{want}"`
					)
				end
			end
		end
	end
	if #violations > 0 then
		Contract.fail(
			`AC-3 phaseKey: {#violations} fault(s) over {#phases} phase(s):\n`
				.. Contract.firstFew(violations, 10)
		)
	end
end

-- A phase with no word raises, naming the phase; it does not echo it.
function PhaseClockContract.aPhaseWithNoWordRaisesNamingIt(bundle: Bundle)
	local ok, result = pcall(bundle.describe, { phase = "Limbo", secondsLeft = 5 }, 0, 0)
	if ok then
		Contract.fail(
			`AC-3: describe for the phase "Limbo", which Words.phase does not name, returned {Deep.show(
				result
			)} instead of raising`
		)
	end
	if string.find(tostring(result), "Limbo", 1, true) == nil then
		Contract.fail(
			`AC-3: the raise for an unknown phase does not name "Limbo"; it said: {tostring(result)}`
		)
	end
end

--[[ AC-3, the countdown ]]

export type Row =
	{ secondsLeft: number, receivedAt: number, now: number, want: string, why: string }

-- The boundary table. `why` says what the row separates.
PhaseClockContract.ROWS = {
	{
		secondsLeft = 420,
		receivedAt = 0,
		now = 0,
		want = "7:00",
		why = "the Contract's 420 example; minutes unpadded",
	},
	{
		secondsLeft = 0.2,
		receivedAt = 0,
		now = 0,
		want = "0:01",
		why = "the Contract's 0.2 example; ceil, not floor or round",
	},
	{
		secondsLeft = 60,
		receivedAt = 0,
		now = 0,
		want = "1:00",
		why = "exactly one minute: 60 // 60 = 1, 60 % 60 = 0",
	},
	{
		secondsLeft = 59.5,
		receivedAt = 0,
		now = 0,
		want = "1:00",
		why = "ceil crosses the minute; floor would say 0:59",
	},
	{
		secondsLeft = 61,
		receivedAt = 0,
		now = 0.5,
		want = "1:01",
		why = "60.5 rounds up; floor would say 1:00",
	},
	{
		secondsLeft = 9,
		receivedAt = 0,
		now = 0,
		want = "0:09",
		why = "seconds two digits; minutes one",
	},
	{
		secondsLeft = 600,
		receivedAt = 0,
		now = 0,
		want = "10:00",
		why = "two-digit minutes are not truncated",
	},
	{
		secondsLeft = 420,
		receivedAt = 0,
		now = 500,
		want = "0:00",
		why = "elapsed beyond secondsLeft clamps to zero",
	},
	{ secondsLeft = 0, receivedAt = 0, now = 0, want = "0:00", why = "the Contract's 0 example" },
	{
		secondsLeft = 420,
		receivedAt = 100,
		now = 130.5,
		want = "6:30",
		why = "elapsed is now - receivedAt: 389.5 -> 390",
	},
	{
		secondsLeft = 420,
		receivedAt = 100,
		now = 100,
		want = "7:00",
		why = "received this instant: nothing elapsed",
	},
} :: { Row }

function PhaseClockContract.countdownIsCeilOfRemainingAsMinutesAndTwoDigitSeconds(bundle: Bundle)
	local violations: { string } = {}
	for index, row in PhaseClockContract.ROWS do
		local view = { phase = "Round", secondsLeft = row.secondsLeft }
		local ok, result = pcall(bundle.describe, view, row.receivedAt, row.now)
		if not ok then
			table.insert(violations, `row {index} ({row.why}): raised {tostring(result)}`)
		else
			local got = if typeof(result) == "table" then result.countdown else result
			if got ~= row.want then
				table.insert(
					violations,
					`row {index}: secondsLeft {row.secondsLeft}, receivedAt {row.receivedAt}, now {row.now} -> {Deep.show(
						got
					)}, wanted "{row.want}" ({row.why})`
				)
			end
		end
		if view.secondsLeft ~= row.secondsLeft or view.phase ~= "Round" then
			table.insert(violations, `row {index}: describe mutated the view it was handed`)
		end
	end
	if #violations > 0 then
		Contract.fail(
			`AC-3 countdown: {#violations} wrong row(s) of {#PhaseClockContract.ROWS}:\n`
				.. Contract.firstFew(violations, 12)
		)
	end
end

-- No `secondsLeft`, no countdown: nil, not "0:00" and not "".
function PhaseClockContract.nilSecondsLeftGivesNoCountdown(bundle: Bundle)
	local result = bundle.describe({ phase = "Lobby" }, 50, 60)
	if typeof(result) ~= "table" then
		Contract.fail(`AC-3: describe returned {typeof(result)}, wanted a table`)
	end
	if result.countdown ~= nil then
		Contract.fail(
			`AC-3: with secondsLeft nil the countdown is {Deep.show(result.countdown)}, wanted nil`
		)
	end
end

return PhaseClockContract
