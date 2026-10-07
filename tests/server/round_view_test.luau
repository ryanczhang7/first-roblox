--!strict
--[[
	VIEW-003: the public round view carries public facts and a progress bar
	of exactly two numbers. AC-1 through AC-6 and the story's Contract pins
	(C-1..C-10), applied to the real `src/server/round/RoundView.luau` and,
	for AC-6, to the real `src/server/session/Session.luau` wired to it.

	The module is required through a `pcall` at the top and re-checked inside
	every test, as every suite here does. In RED the file does not exist, so
	every behavioural test below fails at the load check, naming the module -
	a counted failure per criterion rather than one LOAD FAIL. It is not a
	skip: every test FAILS, loudly, until GREEN writes it.

	THE CHECKS LIVE IN `tests/helpers/RoundViewContract.luau` and are
	exercised against a reference builder and deliberately wrong builders in
	`tests/server/round_view_controls_test.luau`. That file is where each
	check is OBSERVED to fire - which matters in RED, because the load check
	above means not one assertion in THIS file executes against the module
	until GREEN writes it.

	THE ORACLE PARTITION (story `## Contract`): AC-1 and AC-5 are SETTLED by
	`mechanics.md` section 3.2's "must never show" table - the checks are
	named after its rows. AC-2, AC-3, AC-4 and AC-6 are MECHANICAL: C-5's
	precedence, C-8's shape and C-7's clock are written in the helper over
	`Procedure.dial`, `Procedure.isLive`, `Procedure.partnerLamps`,
	`Procedure.deadline` and `RoundConfig`, never read off the view; AC-6
	deep-compares Session's broadcast to `RoundView.public` of the END state.

	WHAT THIS FILE DOES NOT PIN: how the module iterates, whether it reads a
	machine's setting from the actuation log or from `procedure.dials` (they
	agree on every reachable state - the controls file measures that), the
	text of any error, anything about `FacilityView`'s emission (SLICE-006),
	and the internal layout of `Session`'s edit beyond "requires
	../round/RoundView and declares no RoundView type of its own".
]]

local Contract = require("../helpers/RoundViewContract")
local Deep = require("../helpers/Deep")
local ScriptedRound = require("../helpers/ScriptedRound")
local SourceScan = require("../helpers/SourceScan")
local fs = require("../helpers/GatedFs")

local ROUND_VIEW = "src/server/round/RoundView.luau"
local SESSION = "src/server/session/Session.luau"

local loaded, loadResult = pcall(require, "../../src/server/round/RoundView")
local sessionLoaded, sessionResult = pcall(require, "../../src/server/session/Session")

local function RoundView(): any
	assert(loaded, `{ROUND_VIEW} did not load: {tostring(loadResult)}`)
	for _, name in { "public", "facility" } do
		assert(
			typeof(loadResult[name]) == "function",
			`RoundView.{name} is {typeof(loadResult[name])} - VIEW-003's Contract (C-2) exports `
				.. `public(input, now) -> RoundView and facility(facility) -> FacilityView`
		)
	end
	return loadResult
end

local function Session(): any
	assert(sessionLoaded, `{SESSION} did not load: {tostring(sessionResult)}`)
	return sessionResult
end

-- The one Broadcast/RoundView in a step's effects, or a failure naming the count.
local function broadcastView(effects: { any }, label: string): any
	local views: { any } = {}
	for _, e in effects do
		if typeof(e) == "table" and e.kind == "Broadcast" and e.payloadKind == "RoundView" then
			table.insert(views, e.payload)
		end
	end
	assert(#views == 1, `AC-6: {label}: {#views} Broadcast/RoundView effect(s), expected exactly 1`)
	return views[1]
end

-- C-2's Input, built from the driver's END state.
local function inputOf(d: any): any
	return {
		round = d.state.round,
		procedure = d.state.procedure,
		assignment = d.state.assignment,
		positions = d.state.positions,
		pings = {},
		tuning = d.tuning,
	}
end

return {
	--[[ The export shape. Pinned first because everything below depends on it
	     and a wrong guess here is a compile error rather than a puzzle. ]]

	["Contract (C-2): src/server/round/RoundView.luau loads and exports public and facility as plain field functions"] = function()
		RoundView()
	end,

	["Contract (C-2): RoundView.luau requires neither Session nor anything under session/ - its string literals name no session module"] = function()
		assert(fs.isFile(ROUND_VIEW), `{ROUND_VIEW} does not exist`)
		local text = fs.readFile(ROUND_VIEW)
		assert(#text > 0, `{ROUND_VIEW} read as an empty file`)
		local offenders: { string } = {}
		for _, literal in SourceScan.stringLiteralsIn(text) do
			if
				string.find(literal, "session/", 1, true) ~= nil
				or string.find(literal, "/Session", 1, true) ~= nil
			then
				table.insert(offenders, literal)
			end
		end
		assert(
			#offenders == 0,
			`C-2: {ROUND_VIEW} names a session module in a string literal (a require cycle): {table.concat(
				offenders,
				", "
			)}`
		)
	end,

	--[[ AC-5 (settled): the ten keys. ]]

	["AC-5 (mechanics.md 3.2, 'must never show'): a RoundView's top-level keys are exactly phase, secondsLeft (absent when nil), players, playersMin, playersMax, progress, instability, dark, pings, machines - no live/next step, no per-track field, no machine identity, no armed or partner-lamp state on the bar, no time/pace/par/forecast, no outcome, no seat relation, no lens reading"] = function()
		Contract.topLevelKeysAreExactlyTheTen(RoundView())
	end,

	--[[ AC-1 (settled): the bar. ]]

	["AC-1 (mechanics.md 3.2, 'steps committed, out of procedure_length'): progress has exactly the keys committed and total; total is tuning.instance.procedure_length (8, where the fixture has 7 steps); committed is the number of true entries of procedure.committed (0 at start, 7 when won, never #log, never per track)"] = function()
		Contract.progressIsExactlyCommittedStepsOverProcedureLength(RoundView())
	end,

	--[[ AC-2 (mechanical): the dial. ]]

	["AC-2: for a machine that is unset, rejected or armed dial.setting is nil or the setting last turned onto it from the actuation log (a wrong turn, a decoy's not_live turn, an arming turn), never requiredSetting - on the fixture whose rejected head of track 1 was turned to a setting that differs from its required one; for a committed machine it is the committed setting"] = function()
		Contract.dialIsTheLastTurnedSettingNeverTheRequiredOne(RoundView())
	end,

	["Contract (C-5): machines is one { id, dial, live[, partnerLamp] } per placement machine in ascending id (9 in the fixture, 16 generated), dial has exactly setting-when-non-nil and state, live is Procedure.isLive (a finale step waiting at position 0 is not live), and partnerLamp is present only on the two finale machines as Procedure.partnerLamps with the given positions - both lit, one lit, none lit, and false with no assignment"] = function()
		Contract.machineRecordsAreAscendingWithExactKeysLiveAndPartnerLampOnlyOnTheFinale(
			RoundView()
		)
	end,

	--[[ AC-3 (mechanical): the facility view. ]]

	["AC-3: FacilityView.machines records have exactly id, room, slot, tag, keyClass and no requiredSetting; the layout is rooms { id, column, row } ascending, doors { a < b } sorted by a then b (a fixture with doors listed out of order and one reversed is normalised), spawnRoom, and nothing else - no steps, tracks, finale, par or attempt; every table fresh"] = function()
		Contract.facilityViewIsExactlyTheLayoutAndEachMachinesStaticPublicFacts(RoundView())
	end,

	--[[ AC-4 (mechanical): the clock. ]]

	["AC-4: in Round with a Procedure secondsLeft = ceil(Procedure.deadline - now), which on every penalised snapshot is penaltySeconds below the unpenalised clock; 90 s past the deadline it is 0, not -90 (C-7's clamp); elsewhere SLICE-003's config rule clamped at 0, and nil in Assignment, Resolution and a short Lobby"] = function()
		Contract.secondsLeftIsTheCeilingOfTheDeadlineMinusNowClampedAtZero(RoundView())
	end,

	--[[ C-3, C-6, pings, C-9. ]]

	["Contract (C-3): instability, dark, machines and progress.committed come from the Procedure only in Round with a Procedure; in Resolution and Post with the won Procedure still held, and in Round without one, they are 0, {}, {} and 0 with total still procedure_length"] = function()
		Contract.procedureFieldsExistOnlyInRoundWithAProcedure(RoundView())
	end,

	["Contract (C-6): dark is the ascending list of room ids with procedure.dark[r] == true - two rooms after two blackout crossings, and 1, 3, 4 for a dark table written 4, 1, 3 (and 2 = false)"] = function()
		Contract.darkIsTheAscendingListOfDarkRoomIds(RoundView())
	end,

	["Contract (C-1, C-3): pings is input.pings copied - list and entries - in every phase, and {} for {}"] = function()
		Contract.pingsAreTheGivenListCopiedInEveryPhase(RoundView())
	end,

	["Contract (C-9): no table in a view is a table of the input; mutating the view leaves the input unchanged and mutating the input leaves a view built before it unchanged; the same for FacilityView and the facility"] = function()
		Contract.everyTableInTheViewIsFreshAndNeitherSideMutatesTheOther(RoundView())
	end,

	["Contract: public(input, now) deep-equals the Contract's composition of C-3..C-7 on every snapshot - the played scenario, the generated starts and every phase"] = function()
		Contract.viewDeepEqualsTheOracleOnEverySnapshot(RoundView())
	end,

	--[[ AC-6 (C-1, C-10): Session is wired to the module. ]]

	["AC-6 (C-1): every RoundView Session broadcasts - on each Lobby join, the deal, Ticks in Round, the Tick after a rejected wrong turn (a rejected dial, instability 1, a shorter clock) and after its reset - deep-equals RoundView.public of the END state with pings = {}, and at least one carries machines, a rejected dial and a penalty"] = function()
		local V = RoundView()
		local S = Session()
		local compared = 0
		local sawRejected, sawPenalty, sawMachines = false, false, false
		local problems: { string } = {}
		local function compare(effects: { any }, d: any, label: string)
			local got = broadcastView(effects, label)
			local want = V.public(inputOf(d), d.now)
			local diff = Deep.diff(want, got)
			compared += 1
			if diff ~= "" then
				table.insert(problems, `{label} (now {d.now}, {d.state.round.phase}):\n  {diff}`)
				return
			end
			if typeof(got.machines) == "table" and #got.machines > 0 then
				sawMachines = true
				for _, m in got.machines do
					if typeof(m.dial) == "table" and m.dial.state == "rejected" then
						sawRejected = true
					end
				end
			end
			if typeof(got.instability) == "number" and got.instability > 0 then
				sawPenalty = true
			end
		end

		local d = ScriptedRound.new(S, 11, 4)
		for _, p in d.players do
			compare(ScriptedRound.step(d, { kind = "PlayerJoined", playerId = p }), d, `join {p}`)
		end
		compare(ScriptedRound.deal(d), d, "the deal")
		assert(
			d.state.facility ~= nil and d.state.procedure ~= nil,
			"the deal must leave a facility and a Procedure"
		)
		for i = 1, 2 do
			compare(ScriptedRound.tick(d, 1), d, `Tick {i} in Round`)
		end
		local id = d.state.facility.steps.tracks[1][1]
		local m = ScriptedRound.machineOf(d.state.facility, id)
		local turner = ScriptedRound.turnerOf(d.state.assignment, m)
		-- `walk` returns the effects of its PositionsSampled steps, which never
		-- broadcast (SLICE-003's cadence, C-1); its Ticks are not returned. So
		-- the Tick compared here is an explicit one, stepped after the walk with
		-- the turner standing at the machine (R-1).
		ScriptedRound.walk(d, { [turner] = ScriptedRound.machinePosition(d, m) })
		compare(ScriptedRound.tick(d, 1), d, "the Tick after the walk")
		local turn =
			ScriptedRound.turn(d, turner, id, ScriptedRound.wrongSetting(d, m.requiredSetting))
		assert(
			typeof(turn.reply) == "table" and turn.reply.kind == "rejected",
			`the wrong turn replied {Deep.show(turn.reply)}, expected rejected`
		)
		compare(ScriptedRound.tick(d, 1), d, "the Tick after the wrong turn")
		local reset = d.tuning.actuation.actuation_reset_seconds
		for i = 1, reset do
			compare(ScriptedRound.tick(d, 1), d, `Tick {i} of the reset window`)
		end
		if #problems > 0 then
			error(
				`AC-6: Session's RoundView broadcast must be RoundView.public(input from the END state, now):\n{table.concat(
					problems,
					"\n"
				)}`,
				0
			)
		end
		-- Every scheduled comparison, counted from what drives it: one per join,
		-- the deal, two Ticks in Round, the Tick after the walk, the Tick after
		-- the wrong turn, and one Tick per second of the reset window. With 4
		-- players and actuation_reset_seconds = 3 that is 12 (R-1).
		local scheduled = #d.players + 1 + 2 + 1 + 1 + reset
		assert(
			compared == scheduled,
			`{compared} broadcasts compared, expected {scheduled} (every scheduled step must broadcast exactly once)`
		)
		assert(
			sawMachines,
			"no compared view carried machines; the check proves nothing about the wiring in Round"
		)
		assert(sawRejected, "no compared view carried a rejected dial")
		assert(sawPenalty, "no compared view carried instability > 0")
		print(
			`        [measured] AC-6: {compared} broadcasts deep-equal RoundView.public of the END state`
		)
	end,

	["AC-6 (C-10): Session.luau declares no RoundView type of its own - no `export type RoundView` in its code - and requires ../round/RoundView"] = function()
		local text = fs.readFile(SESSION)
		assert(#text > 0, `{SESSION} read as an empty file; a guard over nothing passes`)
		local code = SourceScan.codeOnly(text)
		local problems: { string } = {}
		local lineNumber = 0
		for line in string.gmatch(code .. "\n", "([^\n]*)\n") do
			lineNumber += 1
			if string.find(line, "export%s+type%s+RoundView%f[^%w_]") ~= nil then
				table.insert(problems, `line {lineNumber} declares a RoundView type: {line}`)
			end
		end
		local requires = false
		for _, literal in SourceScan.stringLiteralsIn(text) do
			if literal == "../round/RoundView" or literal == "./RoundView" then
				requires = true
			end
		end
		if not requires then
			table.insert(problems, `no require of "../round/RoundView" among the string literals`)
		end
		assert(
			#problems == 0,
			`AC-6: {SESSION} must take RoundView from src/server/round/RoundView.luau and keep no stale alias:\n  {table.concat(
				problems,
				"\n  "
			)}`
		)
	end,

	["AC-6 (C-10): the guard above has its subject - the harness classifies Session.luau as source under src/server/session and the file reads non-empty"] = function()
		local files = SourceScan.sourceFilesIn("src/server/session")
		assert(
			SourceScan.contains(files, SESSION),
			`{SESSION} is not in the scanned set; a guard over nothing passes. classify.sh said: {table.concat(
				files,
				", "
			)}`
		)
		assert(#fs.readFile(SESSION) > 0, `{SESSION} read as an empty file`)
	end,
}
