--!strict
--[[
	The negative controls for VIEW-003, and the proof that each check in
	`tests/helpers/RoundViewContract.luau` refuses the builder it exists to
	catch.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. In RED
	`src/server/round/RoundView.luau` does not exist, every test in
	`tests/server/round_view_test.luau` fails at the load check, and so not
	one of that file's checks has been observed to accept or reject anything.
	The builders in `RoundViewStubs.luau` need only the merged `Procedure`,
	`Generator`, `PhaseMachine` and `RoundConfig`, so what is asserted here is
	MEASURED in RED rather than claimed for GREEN. The story's handoff carries
	the table.

	THE STORY NAMES ITS CONTROLS (C-12): a bar with `track`, `next` or
	`byTrack` (AC-1, naming the key), `dial.setting` from `requiredSetting`
	on the fixture whose last rejected turn differs from it (AC-2), a facility
	machine carrying `requiredSetting` (AC-3), an unclamped `secondsLeft` and
	one from the unpenalised clock (AC-4), an extra top-level `outcome`, `par`
	or `seats` (AC-5), `committed` counted from `#log` (C-4), `partnerLamp`
	on a non-finale machine (C-5), a view sharing a table with the input
	(C-9). D-1..D-4 THEMSELVES mutate the real module and stay with GATES.

	EVERY CONTROL IS ASSERTED TO PASS THE CHECKS IT SHOULD PASS, and that half
	is the one that is easy to leave out and worth the most: a builder that
	fails EVERY check proves only that the checks reject something. Each
	control pins the set of checks that fire EXACTLY. `viewDeepEqualsTheOracle`
	fires on every public-view defect by construction (it is the one-line
	summary of the others), so it is in nearly every set; the sharper pin is
	the named check beside it.

	ONE DEFECT IS INDISTINGUISHABLE TODAY AND SAID SO: `settingFromDials`
	reads `procedure.dials[id].setting` instead of the actuation log. The two
	agree on every state `Procedure` can reach, so the suite accepts it. It is
	listed here as a measurement, not hidden.
]]

local Contract = require("../helpers/RoundViewContract")
local Deep = require("../helpers/Deep")
local Stubs = require("../helpers/RoundViewStubs")

local ORACLE = "viewDeepEqualsTheOracleOnEverySnapshot"
local AC1 = "progressIsExactlyCommittedStepsOverProcedureLength"
local AC2 = "dialIsTheLastTurnedSettingNeverTheRequiredOne"
local AC3 = "facilityViewIsExactlyTheLayoutAndEachMachinesStaticPublicFacts"
local AC4 = "secondsLeftIsTheCeilingOfTheDeadlineMinusNowClampedAtZero"
local AC5 = "topLevelKeysAreExactlyTheTen"
local C3 = "procedureFieldsExistOnlyInRoundWithAProcedure"
local C5 = "machineRecordsAreAscendingWithExactKeysLiveAndPartnerLampOnlyOnTheFinale"
local C6 = "darkIsTheAscendingListOfDarkRoomIds"
local C9 = "everyTableInTheViewIsFreshAndNeitherSideMutatesTheOther"
local PINGS = "pingsAreTheGivenListCopiedInEveryPhase"

-- defect -> the checks it must fire, exactly. MEASURED in RED.
local EXPECTED: { [string]: { string } } = {
	progressTrack = { AC1, ORACLE },
	progressNext = { AC1, ORACLE },
	progressByTrack = { AC1, ORACLE },
	committedFromLog = { AC1, ORACLE },
	totalFromSteps = { AC1, C3, ORACLE },
	settingFromRequired = { AC2, ORACLE },
	settingFromRequiredWhenUnset = { AC2, ORACLE },
	armedReadAsUnset = { AC2, ORACLE },
	settingIgnoresNotLiveTurns = { AC2, ORACLE },
	settingFromDials = {},
	partnerLampEverywhere = { C5, ORACLE },
	partnerLampIgnoresPositions = { C5, ORACLE },
	partnerLampWithoutAssignmentIsNil = { C5, ORACLE },
	machinesDescending = { C5, ORACLE },
	liveFromPosition = { C5, ORACLE },
	facilityWithRequiredSetting = { AC3 },
	facilityWithPar = { AC3 },
	facilityDoorsAsGiven = { AC3 },
	facilityAliasesRooms = { AC3, C9 },
	unclampedSecondsLeft = { AC4, ORACLE },
	secondsLeftIgnoresPenalties = { AC4, ORACLE },
	secondsLeftFromConfigDuration = { AC4, ORACLE },
	extraOutcome = { AC5, ORACLE },
	extraPar = { AC5, ORACLE },
	extraSeats = { AC5, ORACLE },
	readsProcedureOutsideRound = { AC1, C3, ORACLE },
	pingsOnlyInRound = { PINGS, ORACLE },
	darkDescending = { C6, ORACLE },
	sharesPlayers = { C9 },
	sharesPings = { PINGS, C9 },
	sharesPingEntries = { PINGS, C9 },
}

local function failingNames(V: any): ({ string }, { [string]: string })
	local names: { string } = {}
	local messages: { [string]: string } = {}
	for _, f in Contract.failures(V) do
		table.insert(names, f.name)
		messages[f.name] = f.message
	end
	table.sort(names)
	return names, messages
end

local byName: { [string]: Contract.Check } = {}
for _, check in Contract.CHECKS do
	byName[check.name] = check
end

-- A control fires EXACTLY the checks named, each with a message naming the
-- criterion it belongs to. The measured set is printed for the handoff.
local function expectFires(defect: string, expected: { string }): { [string]: string }
	local names, messages = failingNames(Stubs.with(defect))
	local want = table.clone(expected)
	table.sort(want)
	print(`        [measured] {defect} fires: {Deep.show(names)}`)
	if not Deep.equal(names, want) then
		local shown: { string } = {}
		for _, name in names do
			table.insert(shown, `{name}: {messages[name]}`)
		end
		error(
			`{defect} fires {Deep.show(names)}, expected exactly {Deep.show(want)}:\n{table.concat(
				shown,
				"\n"
			)}`,
			0
		)
	end
	for _, name in names do
		local ac = byName[name].ac
		assert(
			string.find(messages[name], ac, 1, true) ~= nil,
			`{defect}: the failure of {name} does not name {ac}:\n{messages[name]}`
		)
	end
	return messages
end

local function names(message: string, fragment: string, what: string)
	assert(
		string.find(message, fragment, 1, true) ~= nil,
		`{what}, but the failure message does not mention "{fragment}":\n{message}`
	)
end

local tests: { [string]: () -> () } = {}

--[[ The reference. ]]

tests["baseline: the reference builder passes every VIEW-003 check, and the scenario reached every state the checks need (rejected, reset, decoy, dark, one track done, finale live, armed, disarmed, two dark, won)"] = function()
	local failing, messages = failingNames(Stubs.reference)
	if #failing > 0 then
		local shown: { string } = {}
		for _, name in failing do
			table.insert(shown, `{name}: {messages[name]}`)
		end
		error(
			`the reference fails {#failing} check(s), so the check or the scenario is wrong:\n{table.concat(
				shown,
				"\n"
			)}`,
			0
		)
	end
	local tags: { [string]: boolean } = {}
	for _, s in Contract.snapshots() do
		for tag in pairs(s.tags) do
			tags[tag] = true
		end
	end
	for _, tag in
		{
			"rejected",
			"resetUnset",
			"decoyRejected",
			"dark",
			"oneTrackDone",
			"finaleLive",
			"lampsBoth",
			"lampsOne",
			"lampsNone",
			"noAssignment",
			"armed",
			"disarmed",
			"twoDark",
			"won",
			"generated",
			"darkUnordered",
			"phase",
			"pastDeadline",
			"clamped",
			"procedureHeld",
		}
	do
		assert(tags[tag], `no snapshot is tagged "{tag}"`)
	end
	print(
		`        [measured] reference fails 0 of {#Contract.CHECKS} checks over {#Contract.snapshots()} snapshots`
	)
end

tests["baseline: every defect in RoundViewStubs.DEFECTS has an expected set here, and every expected set names a defect"] = function()
	for _, defect in Stubs.DEFECTS do
		assert(EXPECTED[defect] ~= nil, `no expected set for defect "{defect}"`)
	end
	for defect in pairs(EXPECTED) do
		assert(
			table.find(Stubs.DEFECTS, defect) ~= nil,
			`EXPECTED names "{defect}", which is not a stub defect`
		)
	end
end

tests["fixture: the AC-2 fixture is real - on the rejected snapshot the head of track 1 was turned to a setting that differs from its requiredSetting, Procedure.dial says rejected, and on the armed snapshot the finale machine's last turned setting IS its required one"] = function()
	local scenario = Contract.scenario()
	local head = scenario.rejectedId
	local facility = scenario.world.facility
	local required = Contract.machineById(facility, head).requiredSetting
	local found = false
	for _, s in scenario.snapshots do
		if s.tags.rejected then
			found = true
			local dial = Contract.expectedDial(s.input.procedure, head, s.now)
			assert(dial.state == "rejected", `expected rejected, got {Deep.show(dial)}`)
			assert(
				dial.setting ~= required,
				`the turned setting {dial.setting} equals the required {required}; the fixture cannot distinguish`
			)
			local log = s.input.procedure.log
			assert(
				#log == 1 and log[1].result == "wrong_setting" and log[1].setting == dial.setting,
				Deep.show(log)
			)
		end
		if s.tags.resetUnset then
			local dial = Contract.expectedDial(s.input.procedure, head, s.now)
			assert(
				Deep.equal(dial, { state = "unset" }),
				`expected unset with no setting, got {Deep.show(dial)}`
			)
		end
		if s.tags.armed then
			local A = scenario.finale[1]
			local dial = Contract.expectedDial(s.input.procedure, A, s.now)
			assert(
				dial.state == "armed"
					and dial.setting == Contract.machineById(facility, A).requiredSetting,
				Deep.show(dial)
			)
		end
		if s.tags.decoyRejected then
			local dial = Contract.expectedDial(s.input.procedure, scenario.decoyId, s.now)
			assert(
				Deep.equal(dial, { state = "rejected", setting = 2 }),
				`the decoy's dial is {Deep.show(dial)}, expected rejected at the turned 2 (C-5 as amended: a not_live turn moved the dial)`
			)
		end
	end
	assert(found, "no rejected snapshot")
end

tests["fixture: the played scenario's clock penalty is real - every penalised snapshot has penaltySeconds = instability x instability_clock_penalty_seconds > 0 and a deadline below startedAt + roundSeconds"] = function()
	local scenario = Contract.scenario()
	local penalty = scenario.world.tuning.actuation.instability_clock_penalty_seconds
	local seen = 0
	for _, s in scenario.snapshots do
		local p = s.input.procedure
		if s.tags.penalised then
			seen += 1
			assert(
				p.penaltySeconds == p.instability * penalty and p.penaltySeconds > 0,
				`"{s.label}": penaltySeconds {p.penaltySeconds}, instability {p.instability}`
			)
		else
			assert(
				p.penaltySeconds == 0,
				`"{s.label}" is tagged unpenalised but carries {p.penaltySeconds} s`
			)
		end
	end
	assert(seen >= 8, `{seen} penalised snapshots`)
end

--[[ One test per defect: the exact set, measured. ]]

for _, defect in Stubs.DEFECTS do
	local expected = EXPECTED[defect] or {}
	local what = if #expected == 0
		then "passes every check (indistinguishable from the reference today)"
		else `fails exactly {Deep.show(expected)}`
	tests[`control: a builder with the single defect {defect} {what}`] = function()
		expectFires(defect, expected)
	end
end

--[[ The story's named controls, and what their messages say. ]]

tests["AC-1 control: a bar with a track, next or byTrack field fails AC-1 naming the key and the mechanics.md row it breaks"] = function()
	names(
		expectFires("progressTrack", EXPECTED.progressTrack)[AC1],
		`extra key "track" breaks the row "per-track progress`,
		"the AC-1 failure names track"
	)
	names(
		expectFires("progressNext", EXPECTED.progressNext)[AC1],
		`extra key "next" breaks the row "which step is live or next`,
		"the AC-1 failure names next"
	)
	names(
		expectFires("progressByTrack", EXPECTED.progressByTrack)[AC1],
		`extra key "byTrack" breaks the row "per-track progress`,
		"the AC-1 failure names byTrack"
	)
end

tests["C-4 control: committed counted from #procedure.log fails AC-1, and the message says that is the log, which counts rejected turns"] = function()
	local message = expectFires("committedFromLog", EXPECTED.committedFromLog)[AC1]
	names(
		message,
		"that is #procedure.log, which counts rejected turns (C-4)",
		"the AC-1 failure attributes the count to the log"
	)
end

tests["AC-1 control: total = #steps (7 in the fixture) fails AC-1 naming procedure_length (8)"] = function()
	local messages = expectFires("totalFromSteps", EXPECTED.totalFromSteps)
	names(
		messages[AC1],
		"progress.total is 7, expected procedure_length = 8 (never #steps)",
		"the AC-1 failure names both numbers"
	)
	names(
		messages[C3],
		"value.total: expected 8, got 7",
		"C-3 keeps total at procedure_length with the Procedure held outside Round"
	)
end

tests["AC-2 control: dial.setting read from requiredSetting for live machines fails AC-2 on the rejected fixture, naming the machine, its required setting and the setting last turned"] = function()
	local scenario = Contract.scenario()
	local head = scenario.rejectedId
	local required = Contract.machineById(scenario.world.facility, head).requiredSetting
	local message = expectFires("settingFromRequired", EXPECTED.settingFromRequired)[AC2]
	names(
		message,
		`machine {head}'s dial.setting is {required}, which is its requiredSetting; the setting last turned onto it was`,
		"the AC-2 failure names the fixture"
	)
	names(message, "(state rejected)", "the AC-2 failure names the rejected state")
	names(
		message,
		`"rejected: machine {head} turned to`,
		"the AC-2 failure names the rejected snapshot"
	)
	assert(
		string.find(message, "start: nothing turned", 1, true) == nil,
		`the start snapshot (every dial unset) must pass this control:\n{message}`
	)
	assert(
		string.find(message, `"armed: machine`, 1, true) == nil,
		`the armed snapshot must pass: an armed machine's last turned setting IS its required one:\n{message}`
	)
	local unset =
		expectFires("settingFromRequiredWhenUnset", EXPECTED.settingFromRequiredWhenUnset)[AC2]
	names(unset, "start: nothing turned", "the unset variant fails on the start snapshot")
	names(
		unset,
		"the setting last turned onto it was nil (state unset)",
		"the AC-2 failure says the dial was never turned"
	)
end

tests["AC-2 control: an armed machine read through Procedure.dial alone (unset) fails AC-2 naming armed"] = function()
	local message = expectFires("armedReadAsUnset", EXPECTED.armedReadAsUnset)[AC2]
	names(message, `expected \{ setting = `, "the AC-2 failure shows the expected dial")
	names(message, `state = "armed" }`, "the AC-2 failure names the armed state it wanted")
end

tests["AC-2 control (C-5 as amended): a builder that ignores not_live turns shows the decoy's rejected dial with no setting and fails AC-2"] = function()
	local scenario = Contract.scenario()
	local message =
		expectFires("settingIgnoresNotLiveTurns", EXPECTED.settingIgnoresNotLiveTurns)[AC2]
	names(
		message,
		`machine {scenario.decoyId}'s dial is \{ state = "rejected" }, expected \{ setting = 2, state = "rejected" }`,
		"the AC-2 failure names the decoy"
	)
end

tests["AC-3 control: a facility machine carrying requiredSetting fails AC-3 alone, naming the key and the secret"] = function()
	local message =
		expectFires("facilityWithRequiredSetting", EXPECTED.facilityWithRequiredSetting)[AC3]
	names(
		message,
		`carries an extra key "requiredSetting" - the required setting is the game's central secret`,
		"the AC-3 failure names the secret"
	)
end

tests["AC-3 control: doors copied as given (unsorted, one reversed) fail AC-3 on the shuffled fixture only, with the diff showing the first door"] = function()
	local message = expectFires("facilityDoorsAsGiven", EXPECTED.facilityDoorsAsGiven)[AC3]
	names(
		message,
		"the fixture with doors listed 3-4, 4-2, 1-3, 1-2",
		"the AC-3 failure names the shuffled fixture"
	)
	names(message, "doors.1.a: expected 1, got 3", "the diff shows the unsorted first door")
	assert(
		string.find(message, "the fixture facility:", 1, true) == nil,
		`the sorted fixture must pass:\n{message}`
	)
end

tests["AC-3 control: a view whose rooms IS layout.rooms fails AC-3 as shared tables and C-9 as a mutation that crosses; an extra par fails AC-3 naming it"] = function()
	local aliased = expectFires("facilityAliasesRooms", EXPECTED.facilityAliasesRooms)
	names(
		aliased[AC3],
		"table(s) in the facility view are the facility's own",
		"the AC-3 failure names the aliasing"
	)
	names(
		aliased[C9],
		"mutating the facility view changed the facility",
		"C-9 sees the mutation cross"
	)
	names(
		expectFires("facilityWithPar", EXPECTED.facilityWithPar)[AC3],
		`extra key "par"`,
		"the AC-3 failure names par"
	)
end

tests["AC-4 control: an unclamped secondsLeft passes every Round snapshot and fails AC-4 on the past-deadline and past-duration cases, naming the clamp"] = function()
	local message = expectFires("unclampedSecondsLeft", EXPECTED.unclampedSecondsLeft)[AC4]
	names(
		message,
		"Round with a Procedure 90 s past its deadline",
		"the AC-4 failure names the past-deadline case"
	)
	names(
		message,
		"secondsLeft is -90, expected 0 - a negative secondsLeft is unclamped (C-7: math.max(0, ...))",
		"the AC-4 failure names the clamp"
	)
	names(message, "Lobby past lobbySeconds", "the AC-4 failure names the Lobby clamp case too")
end

tests["AC-4 control: secondsLeft from the unpenalised clock (startedAt + roundSeconds - now) fails AC-4 on every penalised snapshot, saying the view ignores the penalty"] = function()
	local message =
		expectFires("secondsLeftIgnoresPenalties", EXPECTED.secondsLeftIgnoresPenalties)[AC4]
	names(message, "s of clock penalty below the unpenalised", "the AC-4 failure names the penalty")
	names(message, "- the view ignores the penalty", "the AC-4 failure says so")
	assert(
		string.find(message, "start: nothing turned", 1, true) == nil,
		`the unpenalised start must pass:\n{message}`
	)
end

tests["AC-4 control: SLICE-003's config-duration rule applied in Round fails AC-4 (D-3's shape for this story)"] = function()
	names(
		expectFires("secondsLeftFromConfigDuration", EXPECTED.secondsLeftFromConfigDuration)[AC4],
		"expected ceil(Procedure.deadline -",
		"the AC-4 failure names the deadline"
	)
end

tests["AC-5 control: an extra top-level outcome, par or seats fails AC-5 naming the key and the row it breaks"] = function()
	names(
		expectFires("extraOutcome", EXPECTED.extraOutcome)[AC5],
		`extra top-level key "outcome" breaks the row "the outcome travels in TraceView`,
		"AC-5 names outcome"
	)
	names(
		expectFires("extraPar", EXPECTED.extraPar)[AC5],
		`extra top-level key "par" breaks the row "time, pace, par, or a forecast"`,
		"AC-5 names par"
	)
	names(
		expectFires("extraSeats", EXPECTED.extraSeats)[AC5],
		`extra top-level key "seats" breaks the row "the seat relation is a per-player secret`,
		"AC-5 names seats"
	)
end

tests["C-5 control: partnerLamp on every machine fails C-5 naming a non-finale machine's keys; one ignoring positions fails on the one-holder snapshot; one absent with no assignment fails on that snapshot"] = function()
	names(
		expectFires("partnerLampEverywhere", EXPECTED.partnerLampEverywhere)[C5],
		"not a finale machine, so no partnerLamp",
		"C-5 names the non-finale machine"
	)
	local ignoring =
		expectFires("partnerLampIgnoresPositions", EXPECTED.partnerLampIgnoresPositions)[C5]
	names(ignoring, "finale live: only", "C-5 names the one-holder snapshot")
	names(ignoring, "Procedure.partnerLamps with the given positions", "C-5 names the mechanism")
	local absent = expectFires(
		"partnerLampWithoutAssignmentIsNil",
		EXPECTED.partnerLampWithoutAssignmentIsNil
	)[C5]
	names(absent, "finale live: no assignment", "C-5 names the no-assignment snapshot")
	names(absent, "a finale machine carries partnerLamp", "C-5 says the key must be present")
end

tests["C-5 control: live = first uncommitted of its track fails C-5 only where a finale step waits at position 0 (one track done), naming Procedure.isLive"] = function()
	local message = expectFires("liveFromPosition", EXPECTED.liveFromPosition)[C5]
	names(message, "one track done", "C-5 names the one-track-done snapshot")
	names(message, "live is true, Procedure.isLive says false", "C-5 names the mechanism")
	assert(
		string.find(message, "finale live: both", 1, true) == nil,
		`the live-finale snapshot must pass:\n{message}`
	)
end

tests["C-5 control: machines in descending id fail C-5 on the first record"] = function()
	names(
		expectFires("machinesDescending", EXPECTED.machinesDescending)[C5],
		"machines[1].id is 19, expected 11 (ascending id)",
		"C-5 names the order"
	)
end

tests["C-3 control: reading the Procedure whenever one is held fails C-3 on Resolution and Post with the won Procedure still held, and AC-1 (committed 7 where 0 is expected)"] = function()
	local messages = expectFires("readsProcedureOutsideRound", EXPECTED.readsProcedureOutsideRound)
	names(messages[C3], "Resolution, the won Procedure still held", "C-3 names the Resolution case")
	names(messages[C3], "Post, the won Procedure still held", "C-3 names the Post case")
	names(messages[AC1], "progress.committed is 7, expected 0", "AC-1 names the count")
end

tests["C-6 control: dark in descending order fails C-6 on the two-dark and the unordered snapshots"] = function()
	local message = expectFires("darkDescending", EXPECTED.darkDescending)[C6]
	names(message, "dark written as 4, 1, 3", "C-6 names the unordered snapshot")
	names(
		message,
		"expected the ascending room ids { 1 = 1, 2 = 3, 3 = 4 }",
		"C-6 shows the ascending list"
	)
end

tests["pings control: pings dropped outside Round fails the pings check on the Lobby and Post snapshots"] = function()
	names(
		expectFires("pingsOnlyInRound", EXPECTED.pingsOnlyInRound)[PINGS],
		"Lobby at playersMin",
		"the pings check names a Lobby snapshot"
	)
end

tests["C-9 control: a view whose players IS round.players, or whose pings IS input.pings, or whose ping entries are the input's, fails C-9 naming the shared field"] = function()
	names(
		expectFires("sharesPlayers", EXPECTED.sharesPlayers)[C9],
		"table(s) in the view are the input's own (players)",
		"C-9 names players"
	)
	names(
		expectFires("sharesPings", EXPECTED.sharesPings)[C9],
		"table(s) in the view are the input's own (pings)",
		"C-9 names pings"
	)
	names(
		expectFires("sharesPingEntries", EXPECTED.sharesPingEntries)[C9],
		"table(s) in the view are the input's own",
		"C-9 catches the entries"
	)
end

--[[ The instrument: the row table and the key diff, probed. ]]

tests["instrument: keysOf sorts and stringifies, and the ROUND_VIEW_KEYS, PROGRESS_KEYS and FACILITY keys are sorted so a key-set comparison is order-free"] = function()
	for _, list in
		{
			Contract.ROUND_VIEW_KEYS,
			Contract.PROGRESS_KEYS,
			Contract.FACILITY_KEYS,
			Contract.FACILITY_MACHINE_KEYS,
		}
	do
		local sorted = table.clone(list)
		table.sort(sorted)
		assert(Deep.equal(sorted, list), `not sorted: {Deep.show(list)}`)
	end
	assert(
		Deep.equal(Contract.keysOf({ b = 1, a = 2, [3] = 3 }), { "3", "a", "b" }),
		Deep.show(Contract.keysOf({ b = 1, a = 2, [3] = 3 }))
	)
end

return tests
