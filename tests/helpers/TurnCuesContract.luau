--!strict
--[[
	VIEW-002 AC-1 through AC-6 written once, as checks over a TURN CUES
	FUNCTION rather than over `src/server/seats/Projection.luau` by name - the
	`LensViewContract.luau` arrangement, for the same reason.

	`tests/server/turn_cues_test.luau` applies these to the real
	`Projection.turnCuesFor`. `tests/server/turn_cues_controls_test.luau`
	applies them to a reference view and to the deliberately wrong views in
	`TurnCuesStubs.luau`, so that in RED - where `turnCuesFor` does not exist,
	the real file fails at the export check, and not one assertion in it has
	executed against the module - every check here has still been EXECUTED and
	observed to reject the view it exists to catch.

	A `view` here is one plain function, called with a dot exactly as the
	story's Contract writes it:

	    view(assignment, procedure, playerId) -> TurnCues
	    TurnCues = { live: { number }, next: { number } }   -- machine ids, ascending

	THE ORACLE PARTITION (story `## Contract`). AC-1, AC-2 and AC-6 are
	mechanical: ownership is read from `assignment.keyClasses[playerId]` (the
	list - never `Ring.lensOf`, which is the class the player READS, D-1), and
	liveness is `Procedure.isLive` itself, called here and never reimplemented.
	AC-3 to AC-5 are settled by `mechanics.md` §3.2 (G12): a step's POSITION is
	its index among the uncommitted steps of its track, from 0, and `expected`
	below computes it from `facility.steps.tracks` and `state.committed` with
	no reference to the view under test. `next` is the player's uncommitted,
	not-live step machines at position <= `tuning.instance.turn_cue_lookahead`,
	INCLUSIVE (D-2), read from `procedure.tuning` and never from the shipped
	constant.

	THE SAMPLE IS GENERATED, AND EVERY STATE IS REACHABLE. `Generator.generate`
	deals 200 real facilities at each n in { 4, 5, 6 }. For each, three
	scripted commit orders start from the real `Procedure.start` and commit
	one ordinary step at a time - always a step `Procedure.isLive` says is live
	NOW, which is asserted before each commit - until only the finale pair
	remains: track 1's ordinary steps first, track 2's first, and a seeded
	draw among the live steps. The track-first orders are what reach AC-4's
	states (one track's ordinary steps done while the other's are not); the
	drawn order is the variety. Committing is a write to `committed` on a
	fresh shallow copy of the plain-data state, which is what a Procedure in
	play would have done, and the finale-only state is visited once more with
	`armed` set on finale machine 1, so "an armed finale machine is still
	live" is exercised. `audit` counts what the sample reached and every check
	refuses a sample that reached nothing.

	WHAT THE SAMPLE CANNOT SEE, measured in RED: the shipped lookahead is 1,
	so a view that read `MechanicsTuning` instead of `procedure.tuning` agrees
	with the oracle on every generated state. The hand-built fixture below is
	run under a tuning whose `turn_cue_lookahead` is 2 and expects the extra
	cue (story Contract, AC-3's second control); it is also where the ORDER of
	a two-cue list is pinned exactly, with ids chosen so that track order and
	ascending order differ.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local Generator = require("../../src/server/facility/Generator")
local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local Procedure = require("../../src/server/procedure/Procedure")
local Ring = require("../../src/server/seats/Ring")
local Rng = require("../../src/ReplicatedStorage/Shared/Rng")

local TurnCuesContract = {}

export type View = any
export type Assignment = Ring.Assignment
export type Tuning = typeof(MechanicsTuning)

--[[ ------------------------------------------------------------------------
     The sample. AC-1's numbers verbatim: n in { 4, 5, 6 }, 200 facilities per
     n; every player at every scripted state.

     A check takes an optional `cases` list. The real module is held to the
     full sample; the controls file hands in `sample(CONTROL_FACILITIES_PER_N)`
     - the same generator, the same seeds, the first facilities of each n.
     --------------------------------------------------------------------- ]]

TurnCuesContract.COUNTS = { 4, 5, 6 }
TurnCuesContract.FACILITIES_PER_N = 200
TurnCuesContract.CONTROL_FACILITIES_PER_N = 12
TurnCuesContract.WITHDRAWN_FACILITIES_PER_N = 12
TurnCuesContract.WITHDRAWN_LEAVER = 2
TurnCuesContract.ORDERS = { "track1-first", "track2-first", "drawn" }

-- `Procedure.start`'s instant and round length. Nothing here reads a clock.
TurnCuesContract.NOW = 100
TurnCuesContract.ROUND_SECONDS = 1000

export type Snapshot = {
	label: string,
	state: any,
	-- The finale machine `armed` names in this snapshot, when it does.
	armedId: number?,
}

export type Case = {
	n: number,
	seed: number,
	assignment: Assignment,
	facility: any,
	states: { Snapshot },
}

function TurnCuesContract.playersFor(n: number): { string }
	local out: { string } = {}
	for i = 1, n do
		out[i] = `p{i}`
	end
	return out
end

local function machineById(facility: any, id: number): any
	for _, m in facility.placement.machines do
		if m.id == id then
			return m
		end
	end
	return nil
end
TurnCuesContract.machineById = machineById

-- A state sharing `base`'s facility and tuning, with its own `committed` and
-- `armed`. Test code: SEAT-002's flat ban is on the module, not on this file.
local function withCommitted(base: any, committed: { [number]: boolean }, armed: any?): any
	local state = table.clone(base)
	state.committed = table.clone(committed)
	state.armed = armed
	return state
end

-- The live ORDINARY step of each track, as `Procedure.isLive` reports it on
-- `state`: the first uncommitted entry that is not the track's last.
local function liveOrdinary(state: any): { { track: number, id: number } }
	local out: { { track: number, id: number } } = {}
	for t, track in state.facility.steps.tracks do
		for k = 1, #track - 1 do
			if state.committed[track[k]] ~= true then
				if not Procedure.isLive(state, track[k]) then
					Contract.fail(
						`the sample's script picked machine {track[k]} as track {t}'s first `
							.. `uncommitted ordinary step, but Procedure.isLive says it is not live`
					)
				end
				table.insert(out, { track = t, id = track[k] })
				break
			end
		end
	end
	return out
end

--[[
	One scripted commit order from `base`, as snapshots: the state after each
	ordinary commit, ending at the finale-only state. `includeStart` adds the
	untouched start state in front (once per facility, not once per order).
]]
local function script(base: any, seed: number, order: string, includeStart: boolean): { Snapshot }
	local out: { Snapshot } = {}
	local committed: { [number]: boolean } = {}
	local draw = Rng.fromSeed(seed):derive(`turn-cues-{order}`)
	local current = withCommitted(base, committed)
	if includeStart then
		table.insert(out, { label = "start", state = current })
	end
	local total = 0
	for _, track in base.facility.steps.tracks do
		total += #track - 1
	end
	for step = 1, total do
		local candidates = liveOrdinary(current)
		local pick = candidates[1]
		if order == "track2-first" then
			pick = candidates[#candidates]
		elseif order == "drawn" then
			pick = candidates[draw:nextInteger(1, #candidates)]
		end
		committed[pick.id] = true
		current = withCommitted(base, committed)
		table.insert(out, { label = `{order} commit {step}: machine {pick.id}`, state = current })
	end
	return out
end

local function buildCase(n: number, seed: number): Case
	local assignment = Ring.assign(TurnCuesContract.playersFor(n), Rng.fromSeed(seed))
	local result = Generator.generate(assignment, seed, MechanicsTuning)
	if result.kind ~= "facility" then
		Contract.fail(`the sample needs a facility at n = {n}, seed {seed}: {Deep.show(result)}`)
	end
	local facility = (result :: any).facility
	local base = Procedure.start(
		facility,
		TurnCuesContract.NOW,
		MechanicsTuning,
		seed,
		TurnCuesContract.ROUND_SECONDS
	)
	local states: { Snapshot } = {}
	for i, order in TurnCuesContract.ORDERS do
		for _, snapshot in script(base, seed, order, i == 1) do
			table.insert(states, snapshot)
		end
	end
	-- The finale-only state once more, with finale machine 1 armed: the
	-- window is open and the other finale machine is still to be turned.
	local finaleOnly = states[#states].state
	local armedId = facility.steps.finale[1]
	table.insert(states, {
		label = "finale-only, machine 1 armed",
		state = withCommitted(base, finaleOnly.committed, {
			machineId = armedId,
			closesAt = TurnCuesContract.NOW + MechanicsTuning.instance.simultaneous_window_seconds,
		}),
		armedId = armedId,
	})
	return { n = n, seed = seed, assignment = assignment, facility = facility, states = states }
end

local sampleCache: { [number]: { Case } } = {}

-- The first `perN` facilities of each n (default: the full sample), built once
-- per process per size and SHARED: no check may mutate a case.
function TurnCuesContract.sample(perN: number?): { Case }
	local size = perN or TurnCuesContract.FACILITIES_PER_N
	local cached = sampleCache[size]
	if cached ~= nil then
		return cached
	end
	local full = sampleCache[TurnCuesContract.FACILITIES_PER_N]
	local cases: { Case } = {}
	for _, n in TurnCuesContract.COUNTS do
		for seed = 1, size do
			local reused: Case? = nil
			if full ~= nil then
				for _, case in full do
					if case.n == n and case.seed == seed then
						reused = case
						break
					end
				end
			end
			table.insert(cases, reused or buildCase(n, seed))
		end
	end
	sampleCache[size] = cases
	return cases
end

--[[ ------------------------------------------------------------------------
     The oracle.
     --------------------------------------------------------------------- ]]

-- Ownership: the class is in p's `keyClasses` LIST. Never `Ring.lensOf`.
local function owns(assignment: Assignment, playerId: string, keyClass: number): boolean
	local classes = assignment.keyClasses[playerId]
	return classes ~= nil and table.find(classes, keyClass) ~= nil
end
TurnCuesContract.owns = owns

local function isFinale(facility: any, id: number): boolean
	return table.find(facility.steps.finale, id) ~= nil
end

local function isStep(facility: any, id: number): boolean
	for _, track in facility.steps.tracks do
		if table.find(track, id) ~= nil then
			return true
		end
	end
	return false
end

-- Every ordinary step of track `t` committed - the test's own reading of
-- `committed`, for AC-4's "whose track is done".
local function ordinaryDone(state: any, t: number): boolean
	local track = state.facility.steps.tracks[t]
	for k = 1, #track - 1 do
		if state.committed[track[k]] ~= true then
			return false
		end
	end
	return true
end

export type Expected = {
	live: { number },
	nextIds: { number },
	-- cues (live or next) per track index
	byTrack: { number },
	-- p's uncommitted not-live steps at position lookahead + 1: what the
	-- window excludes by exactly one
	excludedByOne: number,
	-- finale machines in `next` because their track is done and the other is not
	waitingFinale: { number },
}

--[[
	The expected cues for `playerId` on `state`, read out independently of any
	view: position counted from `committed` per track, liveness from
	`Procedure.isLive`, ownership from `keyClasses`, lookahead from
	`state.tuning`. Decoys are in no track and so never appear.
]]
function TurnCuesContract.expected(assignment: Assignment, state: any, playerId: string): Expected
	local lookahead = state.tuning.instance.turn_cue_lookahead
	local expected: Expected = {
		live = {},
		nextIds = {},
		byTrack = {},
		excludedByOne = 0,
		waitingFinale = {},
	}
	for t, track in state.facility.steps.tracks do
		expected.byTrack[t] = 0
		local position = 0
		for _, id in track do
			if state.committed[id] ~= true then
				local m = machineById(state.facility, id)
				if m ~= nil and owns(assignment, playerId, m.keyClass) then
					if Procedure.isLive(state, id) then
						table.insert(expected.live, id)
						expected.byTrack[t] += 1
					elseif position <= lookahead then
						table.insert(expected.nextIds, id)
						expected.byTrack[t] += 1
						if isFinale(state.facility, id) then
							table.insert(expected.waitingFinale, id)
						end
					elseif position == lookahead + 1 then
						expected.excludedByOne += 1
					end
				end
				position += 1
			end
		end
	end
	table.sort(expected.live)
	table.sort(expected.nextIds)
	return expected
end

--[[ ------------------------------------------------------------------------
     Reading a view's answer defensively: a wrong shape is reported, never
     crashed on. The membership checks (AC-1..AC-5) read the two lists as
     SETS; order, uniqueness and keys are AC-6's.
     --------------------------------------------------------------------- ]]

local function idList(result: any, key: string): ({ number }?, string?)
	if typeof(result) ~= "table" then
		return nil, `the view is {typeof(result)} {Deep.show(result)}`
	end
	local list = result[key]
	if typeof(list) ~= "table" then
		return nil, `view.{key} is {typeof(list)}`
	end
	local ids: { number } = {}
	for i, id in ipairs(list) do
		if typeof(id) ~= "number" then
			return nil, `{key}[{i}] is {Deep.show(id)}, not a machine id`
		end
		table.insert(ids, id)
	end
	return ids, nil
end

local function asSet(ids: { number }): { [number]: boolean }
	local set: { [number]: boolean } = {}
	for _, id in ids do
		set[id] = true
	end
	return set
end

local function sortedCopy(ids: { number }): { number }
	local out = table.clone(ids)
	table.sort(out)
	return out
end

local function joinIds(ids: { number }): string
	local parts: { string } = {}
	for _, id in ids do
		table.insert(parts, tostring(id))
	end
	return `[{table.concat(parts, ", ")}]`
end

--[[ ------------------------------------------------------------------------
     The audit: every (case, state, player) compared with the oracle, every
     disagreement attributed to the criterion it breaks, and the sample's
     reach counted so the checks can refuse a vacuous one.
     --------------------------------------------------------------------- ]]

export type Audit = {
	cases: number,
	calls: number,
	nonEmpty: number, -- calls expecting any cue
	nonEmptyLive: number,
	nonEmptyNext: number,
	bothTracks: number, -- calls where p holds a cue in each track
	excludedByOne: number, -- owned steps at position lookahead + 1, summed
	ownedDecoyCalls: number, -- calls where p owns at least one decoy
	-- calls where a finale step is expected in next: its track's ordinary steps
	-- are done, or one remains (position 1 at the shipped lookahead)
	waitingFinale: number,
	ac4States: number, -- (state, holder) pairs where exactly one track is done
	armedStates: number, -- (state, holder) pairs with the holder's finale armed
	malformed: number,
	ownership: { string }, -- AC-1
	live: { string }, -- AC-2
	nextIds: { string }, -- AC-3
	decoy: { string }, -- AC-3: a decoy named as a cue
	ac4: { string }, -- AC-4
	armed: { string }, -- AC-2: an armed finale machine not live
	malformedList: { string },
}

local function label(case: Case, snapshot: Snapshot, playerId: string): string
	return `n = {case.n}, seed {case.seed}, "{snapshot.label}", {playerId}`
end

local function classesOf(assignment: Assignment, playerId: string): string
	return joinIds(assignment.keyClasses[playerId] or {})
end

function TurnCuesContract.audit(view: View, cases: { Case }?): Audit
	local sample = cases or TurnCuesContract.sample()
	local audit: Audit = {
		cases = #sample,
		calls = 0,
		nonEmpty = 0,
		nonEmptyLive = 0,
		nonEmptyNext = 0,
		bothTracks = 0,
		excludedByOne = 0,
		ownedDecoyCalls = 0,
		waitingFinale = 0,
		ac4States = 0,
		armedStates = 0,
		malformed = 0,
		ownership = {},
		live = {},
		nextIds = {},
		decoy = {},
		ac4 = {},
		armed = {},
		malformedList = {},
	}

	for _, case in sample do
		local facility = case.facility
		-- Which players own a decoy, once per case.
		local ownsDecoy: { [string]: boolean } = {}
		for _, m in facility.placement.machines do
			if not isStep(facility, m.id) then
				for _, playerId in case.assignment.players do
					if owns(case.assignment, playerId, m.keyClass) then
						ownsDecoy[playerId] = true
					end
				end
			end
		end

		for _, snapshot in case.states do
			local state = snapshot.state
			local done1 = ordinaryDone(state, 1)
			local done2 = ordinaryDone(state, 2)
			for _, playerId in case.assignment.players do
				audit.calls += 1
				local expected = TurnCuesContract.expected(case.assignment, state, playerId)
				if #expected.live > 0 then
					audit.nonEmptyLive += 1
				end
				if #expected.nextIds > 0 then
					audit.nonEmptyNext += 1
				end
				if #expected.live > 0 or #expected.nextIds > 0 then
					audit.nonEmpty += 1
				end
				if expected.byTrack[1] > 0 and expected.byTrack[2] > 0 then
					audit.bothTracks += 1
				end
				audit.excludedByOne += expected.excludedByOne
				if ownsDecoy[playerId] then
					audit.ownedDecoyCalls += 1
				end
				if #expected.waitingFinale > 0 then
					audit.waitingFinale += 1
				end

				local result = view(case.assignment, state, playerId)
				local liveIds, problem = idList(result, "live")
				local nextIds, problem2 = idList(result, "next")
				if liveIds == nil or nextIds == nil then
					audit.malformed += 1
					table.insert(
						audit.malformedList,
						`  {label(case, snapshot, playerId)}: {problem or problem2 :: string}`
					)
					continue
				end
				local gotLive = asSet(liveIds :: { number })
				local gotNext = asSet(nextIds :: { number })
				local here = label(case, snapshot, playerId)

				-- AC-1: every cue is a machine of one of p's key classes.
				for _, listName in { "live", "next" } do
					local ids = if listName == "live" then liveIds else nextIds
					for _, id in ids :: { number } do
						local m = machineById(facility, id)
						if m == nil then
							table.insert(
								audit.ownership,
								`  {here}: {listName} names unknown machine {id}`
							)
						elseif not owns(case.assignment, playerId, m.keyClass) then
							table.insert(
								audit.ownership,
								`  {here}: {listName} cue {id} is of class {m.keyClass}, not one of `
									.. `{playerId}'s key classes {classesOf(
										case.assignment,
										playerId
									)}`
							)
						end
					end
				end

				-- AC-2: live is exactly { owned machines with Procedure.isLive }.
				local expectedLive = asSet(expected.live)
				local liveProblems: { string } = {}
				for _, id in expected.live do
					if not gotLive[id] then
						table.insert(
							liveProblems,
							`missing live cue {id} (Procedure.isLive is true)`
						)
					end
				end
				for id in gotLive do
					if not expectedLive[id] then
						local why = if owns(
								case.assignment,
								playerId,
								(machineById(facility, id) or {}).keyClass or -1
							)
							then `Procedure.isLive is false`
							else `not {playerId}'s`
						table.insert(liveProblems, `extra live cue {id} ({why})`)
					end
				end
				if #liveProblems > 0 then
					table.insert(
						audit.live,
						`  {here}: expected live {joinIds(expected.live)}, got `
							.. `{joinIds(sortedCopy(liveIds :: { number }))}: {table.concat(
								liveProblems,
								"; "
							)}`
					)
				end

				-- AC-3: next is exactly the owned, not-live steps within the window.
				local expectedNext = asSet(expected.nextIds)
				local nextProblems: { string } = {}
				for _, id in expected.nextIds do
					if not gotNext[id] then
						table.insert(nextProblems, `missing next cue {id}`)
					end
				end
				for id in gotNext do
					if not expectedNext[id] then
						local m = machineById(facility, id)
						if m ~= nil and not isStep(facility, id) then
							table.insert(nextProblems, `extra next cue {id}, which is a decoy`)
							table.insert(audit.decoy, `  {here}: next names decoy {id}`)
						elseif expectedLive[id] then
							table.insert(nextProblems, `extra next cue {id}, which is live`)
						else
							table.insert(nextProblems, `extra next cue {id}`)
						end
					end
				end
				if #nextProblems > 0 then
					table.insert(
						audit.nextIds,
						`  {here}: expected next {joinIds(expected.nextIds)} at lookahead `
							.. `{state.tuning.instance.turn_cue_lookahead}, got `
							.. `{joinIds(sortedCopy(nextIds :: { number }))}: {table.concat(
								nextProblems,
								"; "
							)}`
					)
				end

				-- AC-4: a finale step whose track is done while the other is not
				-- is next, never live; once both are done it is live, never next.
				for t = 1, 2 do
					local fid = facility.steps.finale[t]
					local fm = machineById(facility, fid)
					if fm ~= nil and owns(case.assignment, playerId, fm.keyClass) then
						local thisDone = if t == 1 then done1 else done2
						local otherDone = if t == 1 then done2 else done1
						if thisDone and not otherDone then
							audit.ac4States += 1
							if not gotNext[fid] or gotLive[fid] then
								table.insert(
									audit.ac4,
									`  {here}: finale machine {fid}'s track {t} is done and the other `
										.. `is not, so it must be in next and not live; live `
										.. `{joinIds(sortedCopy(liveIds :: { number }))}, next `
										.. joinIds(sortedCopy(nextIds :: { number }))
								)
							end
						elseif thisDone and otherDone and state.committed[fid] ~= true then
							if not gotLive[fid] or gotNext[fid] then
								table.insert(
									audit.ac4,
									`  {here}: every ordinary step is done, so finale machine {fid} `
										.. `must be live and not next; live `
										.. `{joinIds(sortedCopy(liveIds :: { number }))}, next `
										.. joinIds(sortedCopy(nextIds :: { number }))
								)
							end
						end
					end
				end

				-- AC-2's armed clause: an armed finale machine is still live.
				local armedId = snapshot.armedId
				if armedId ~= nil then
					local am = machineById(facility, armedId)
					if am ~= nil and owns(case.assignment, playerId, am.keyClass) then
						audit.armedStates += 1
						if not gotLive[armedId] then
							table.insert(
								audit.armed,
								`  {here}: finale machine {armedId} is armed and Procedure.isLive is `
									.. `{tostring(Procedure.isLive(state, armedId))}, but live is `
									.. joinIds(sortedCopy(liveIds :: { number }))
							)
						end
					end
				end
			end
		end
	end
	return audit
end

-- The vacuity floors, per facility in the sample, so that they scale with the
-- sub-sample the controls hand in. Measured in RED against the reference view
-- over the full seeded sample (see the story's handoff) and set well under
-- the smallest measured value, so the floors say "exercised", not "exactly
-- this many".
TurnCuesContract.NON_EMPTY_PER_FACILITY = 20
TurnCuesContract.NON_EMPTY_LIVE_PER_FACILITY = 15
TurnCuesContract.NON_EMPTY_NEXT_PER_FACILITY = 10
TurnCuesContract.BOTH_TRACKS_PER_FACILITY = 1
TurnCuesContract.EXCLUDED_BY_ONE_PER_FACILITY = 3
TurnCuesContract.OWNED_DECOY_CALLS_PER_FACILITY = 10
TurnCuesContract.WAITING_FINALE_PER_FACILITY = 2
TurnCuesContract.AC4_STATES_PER_FACILITY = 2
TurnCuesContract.ARMED_STATES_PER_FACILITY = 1
-- Lists holding two or more cues, for AC-6's ascending-unique clause.
-- Measured against the reference: 76 over 36 facilities, 1514 over 600 - about
-- two per facility, so the floor is one per two facilities.
TurnCuesContract.MULTI_LISTS_PER_FACILITY = 0.5

function TurnCuesContract.describeAudit(audit: Audit): string
	return `{audit.cases} facilities, {audit.calls} calls; expected non-empty {audit.nonEmpty} `
		.. `(live {audit.nonEmptyLive}, next {audit.nonEmptyNext}), both tracks {audit.bothTracks}, `
		.. `excluded by one {audit.excludedByOne}, owned-decoy calls {audit.ownedDecoyCalls}, `
		.. `waiting finale {audit.waitingFinale}, AC-4 states {audit.ac4States}, armed states `
		.. `{audit.armedStates}; violations: ownership {#audit.ownership}, live {#audit.live}, `
		.. `next {#audit.nextIds}, decoy {#audit.decoy}, AC-4 {#audit.ac4}, armed {#audit.armed}, `
		.. `malformed {audit.malformed}`
end

local function refuseVacuous(criterion: string, audit: Audit, floors: { { string } })
	local short: { string } = {}
	for _, entry in floors do
		local field, perFacility = entry[1], entry[2]
		local floor = (TurnCuesContract :: any)[perFacility] * audit.cases
		local measured = (audit :: any)[field]
		if measured < floor then
			table.insert(short, `{field} {measured} < {floor}`)
		end
	end
	if #short > 0 then
		Contract.fail(
			`{criterion}'s sample is vacuous: {table.concat(short, ", ")} - the sample needs `
				.. `changing, not the check. {TurnCuesContract.describeAudit(audit)}`
		)
	end
end

local function failOn(criterion: string, what: string, audit: Audit, lists: { { string } })
	local violations: { string } = {}
	for _, list in lists do
		for _, line in list do
			table.insert(violations, line)
		end
	end
	if #violations > 0 then
		Contract.fail(
			`{criterion}: {what} - {#violations} violation(s) over {audit.calls} calls. `
				.. `{TurnCuesContract.describeAudit(audit)}\n{Contract.firstFew(violations, 6)}`
		)
	end
end

-- AC-1.
function TurnCuesContract.cuesNameOnlyTheirOwnMachines(view: View, cases: { Case }?)
	local audit = TurnCuesContract.audit(view, cases)
	refuseVacuous("AC-1", audit, { { "nonEmpty", "NON_EMPTY_PER_FACILITY" } })
	failOn(
		"AC-1",
		"a cue names a machine whose key class is not in the player's keyClasses",
		audit,
		{ audit.malformedList, audit.ownership }
	)
end

-- AC-2.
function TurnCuesContract.liveIsExactlyProcedureIsLive(view: View, cases: { Case }?)
	local audit = TurnCuesContract.audit(view, cases)
	refuseVacuous("AC-2", audit, {
		{ "nonEmptyLive", "NON_EMPTY_LIVE_PER_FACILITY" },
		{ "armedStates", "ARMED_STATES_PER_FACILITY" },
	})
	failOn(
		"AC-2",
		"live is not exactly the player's machines for which Procedure.isLive is true",
		audit,
		{ audit.malformedList, audit.live, audit.armed }
	)
end

-- AC-3.
function TurnCuesContract.nextIsExactlyTheLookaheadWindow(view: View, cases: { Case }?)
	local audit = TurnCuesContract.audit(view, cases)
	refuseVacuous("AC-3", audit, {
		{ "nonEmptyNext", "NON_EMPTY_NEXT_PER_FACILITY" },
		{ "excludedByOne", "EXCLUDED_BY_ONE_PER_FACILITY" },
		{ "ownedDecoyCalls", "OWNED_DECOY_CALLS_PER_FACILITY" },
		{ "bothTracks", "BOTH_TRACKS_PER_FACILITY" },
	})
	failOn(
		"AC-3",
		"next is not exactly the player's uncommitted, not-live step machines at position "
			.. "<= turn_cue_lookahead (inclusive, from procedure.tuning), decoys never",
		audit,
		{ audit.malformedList, audit.nextIds, audit.decoy }
	)
end

-- AC-4.
function TurnCuesContract.waitingFinaleIsNextNotLive(view: View, cases: { Case }?)
	local audit = TurnCuesContract.audit(view, cases)
	refuseVacuous("AC-4", audit, {
		{ "ac4States", "AC4_STATES_PER_FACILITY" },
		{ "waitingFinale", "WAITING_FINALE_PER_FACILITY" },
	})
	failOn(
		"AC-4",
		"a finale step whose track is done while the other is not is not in next and out of "
			.. "live (or, with both done, not live and out of next)",
		audit,
		{ audit.malformedList, audit.ac4 }
	)
end

--[[ ------------------------------------------------------------------------
     AC-5: after the real `Ring.withdraw`, the supplier's cues include the
     transferred class's machines - and every remaining player's cues are
     still exactly the oracle's, on the withdrawn ring.
     --------------------------------------------------------------------- ]]

-- σ⁻¹(q) by a scan over σ: the oracle's own, not `Ring.supplierOf`.
local function supplierIn(assignment: Assignment, playerId: string): string
	for _, candidate in assignment.players do
		if assignment.sigma[candidate] == playerId then
			return candidate
		end
	end
	return Contract.fail(`{playerId} has no supplier in the dealt ring`)
end

export type WithdrawnCase = {
	case: Case,
	withdrawn: Assignment,
	leaver: string,
	supplier: string,
	transferred: { number },
}

function TurnCuesContract.withdrawnSample(cases: { Case }?): { WithdrawnCase }
	local sample = cases or TurnCuesContract.sample(TurnCuesContract.WITHDRAWN_FACILITIES_PER_N)
	local out: { WithdrawnCase } = {}
	for _, case in sample do
		local leaver = case.assignment.players[TurnCuesContract.WITHDRAWN_LEAVER]
		local withdrawn = Ring.withdraw(case.assignment, leaver)
		table.insert(out, {
			case = {
				n = case.n,
				seed = case.seed,
				assignment = withdrawn,
				facility = case.facility,
				states = case.states,
			},
			withdrawn = withdrawn,
			leaver = leaver,
			supplier = supplierIn(case.assignment, leaver),
			transferred = table.clone(case.assignment.keyClasses[leaver]),
		})
	end
	return out
end

function TurnCuesContract.supplierCuesIncludeTheTransferredClass(view: View, cases: { Case }?)
	local withdrawnCases = TurnCuesContract.withdrawnSample(cases)
	local violations: { string } = {}
	local calls, transferredCues = 0, 0
	local auditCases: { Case } = {}

	for _, wc in withdrawnCases do
		table.insert(auditCases, wc.case)
		local transferred = asSet(wc.transferred)
		for _, snapshot in wc.case.states do
			calls += 1
			local state = snapshot.state
			local expected = TurnCuesContract.expected(wc.withdrawn, state, wc.supplier)
			local result = view(wc.withdrawn, state, wc.supplier)
			local liveIds = idList(result, "live")
			local nextIds = idList(result, "next")
			local gotLive = asSet(liveIds or {})
			local gotNext = asSet(nextIds or {})
			local missing: { string } = {}
			for _, listName in { "live", "next" } do
				local ids = if listName == "live" then expected.live else expected.nextIds
				local got = if listName == "live" then gotLive else gotNext
				for _, id in ids do
					local m = machineById(wc.case.facility, id)
					if m ~= nil and transferred[m.keyClass] then
						transferredCues += 1
						if not got[id] then
							table.insert(missing, `{listName} cue {id} (class {m.keyClass})`)
						end
					end
				end
			end
			if #missing > 0 then
				table.insert(
					violations,
					`  n = {wc.case.n}, seed {wc.case.seed}, "{snapshot.label}": supplier {wc.supplier} `
						.. `inherited class {joinIds(wc.transferred)} from {wc.leaver} but lacks `
						.. table.concat(missing, ", ")
				)
			end
		end
	end

	local floor = TurnCuesContract.NON_EMPTY_NEXT_PER_FACILITY * #withdrawnCases
	if transferredCues < floor then
		Contract.fail(
			`AC-5's sample is vacuous: only {transferredCues} cues of a transferred class were `
				.. `expected across {calls} supplier calls (floor {floor})`
		)
	end
	if #violations > 0 then
		Contract.fail(
			`AC-5: after Ring.withdraw the supplier's cues do not include the transferred class's `
				.. `machines in {#violations} of {calls} calls:\n{Contract.firstFew(violations, 6)}`
		)
	end
	-- And exactness for everyone still seated, on the withdrawn ring.
	local audit = TurnCuesContract.audit(view, auditCases)
	failOn(
		"AC-5",
		"on the withdrawn ring a remaining player's cues are not exactly the oracle's",
		audit,
		{ audit.malformedList, audit.ownership, audit.live, audit.nextIds }
	)
end

--[[ ------------------------------------------------------------------------
     AC-6: the shape. Exactly the keys `live` and `next`; each a list of
     numbers, strictly ascending (so unique), with no stray keys; and a fresh
     view table and fresh lists on every call.
     --------------------------------------------------------------------- ]]

local function keysOf(t: any): { string }
	local keys: { string } = {}
	for k in pairs(t :: { [any]: any }) do
		table.insert(keys, tostring(k))
	end
	table.sort(keys)
	return keys
end

local function listProblems(name: string, list: any, problems: { string }): number
	if typeof(list) ~= "table" then
		table.insert(problems, `{name} is {typeof(list)}`)
		return 0
	end
	local count = 0
	for _ in pairs(list :: { [any]: any }) do
		count += 1
	end
	local length = #list
	if count ~= length then
		table.insert(problems, `{name} has {count} entries but a list length of {length}`)
	end
	local previous: number? = nil
	for i = 1, length do
		local id = list[i]
		if typeof(id) ~= "number" then
			table.insert(problems, `{name}[{i}] is {Deep.show(id)}, not a number`)
		elseif previous ~= nil and id <= previous then
			table.insert(
				problems,
				`{name}[{i}] {id} does not ascend past {previous} (ascending, unique)`
			)
		end
		if typeof(id) == "number" then
			previous = id
		end
	end
	return length
end

TurnCuesContract.FRESHNESS_STRIDE = 4

function TurnCuesContract.cuesHaveExactlyTheContractShape(view: View, cases: { Case }?)
	local sample = cases or TurnCuesContract.sample()
	local violations: { string } = {}
	local calls, multi = 0, 0

	for _, case in sample do
		for i, snapshot in case.states do
			for _, playerId in case.assignment.players do
				calls += 1
				local result = view(case.assignment, snapshot.state, playerId)
				local problems: { string } = {}
				if typeof(result) ~= "table" then
					table.insert(problems, `the view is {typeof(result)} {Deep.show(result)}`)
				else
					local keys = table.concat(keysOf(result), ",")
					if keys ~= "live,next" then
						table.insert(
							problems,
							`the view's keys are [{keys}], not exactly [live, next]`
						)
					end
					if listProblems("live", result.live, problems) >= 2 then
						multi += 1
					end
					if listProblems("next", result.next, problems) >= 2 then
						multi += 1
					end
					if i % TurnCuesContract.FRESHNESS_STRIDE == 1 then
						local again = view(case.assignment, snapshot.state, playerId)
						if again == result then
							table.insert(problems, "the same view table was returned twice")
						elseif typeof(again) == "table" then
							if again.live == result.live and typeof(result.live) == "table" then
								table.insert(problems, "the same live list was returned twice")
							end
							if again.next == result.next and typeof(result.next) == "table" then
								table.insert(problems, "the same next list was returned twice")
							end
						end
					end
				end
				if #problems > 0 then
					table.insert(
						violations,
						`  {label(case, snapshot, playerId)}: {table.concat(problems, "; ")}`
					)
				end
			end
		end
	end

	local floor = TurnCuesContract.MULTI_LISTS_PER_FACILITY * #sample
	if multi < floor then
		Contract.fail(
			`AC-6's sample is vacuous: only {multi} lists with two or more cues across {calls} `
				.. `calls (floor {floor}), so the ascending-unique clause was barely inspected`
		)
	end
	if #violations > 0 then
		Contract.fail(
			`AC-6: a cue set is not exactly \{ live, next } with each a fresh list of machine ids `
				.. `ascending and unique, in {#violations} of {calls} calls:\n`
				.. Contract.firstFew(violations, 6)
		)
	end
end

--[[ ------------------------------------------------------------------------
     The hand-built fixture.

     Ring p1 -> p2 -> p3 -> p4 -> p1, class i at seat i. Two tracks of four:

         track 1:  6 (c2)   8 (c4)   5 (c2)   9 (c1, finale)
         track 2:  1 (c3)   4 (c1)   7 (c4)   3 (c3, finale)
         decoys:   2 (c1)   10 (c2)

     Chosen so that at the start p2 holds a step at position 2 (machine 5) and
     p4 one at position 1 and one at position 2 (8, 7) - a lookahead of 2 sees
     5 and 7 where 1 does not - and so that a two-cue list's TRACK order
     differs from its ascending order (p1 next [9, 4] by track, [4, 9]
     ascending; p4 next [8, 7] by track at lookahead 2). The finale holders p1
     and p3 are not ring neighbours; the decoys are of classes p1 and p2 hold,
     so a view that counted decoys would show.

     Six states, by what is committed:

         S0  nothing
         S1  track 1's ordinary steps (6, 8, 5): finale 9 waits at position 0
         S2  track 2's ordinary steps (1, 4, 7): finale 3 waits
         S3  every ordinary step: both finale machines live
         S4  S3 with machine 9 armed
         S5  6 and 1: p4 is live in track 1 and next in track 2
     --------------------------------------------------------------------- ]]

local FIXTURE_MACHINES = {
	{ id = 1, room = 1, slot = 1, keyClass = 3, tag = 1, requiredSetting = 1 },
	{ id = 2, room = 1, slot = 2, keyClass = 1, tag = 1, requiredSetting = 3 },
	{ id = 3, room = 2, slot = 1, keyClass = 3, tag = 2, requiredSetting = 2 },
	{ id = 4, room = 2, slot = 2, keyClass = 1, tag = 2, requiredSetting = 4 },
	{ id = 5, room = 3, slot = 1, keyClass = 2, tag = 1, requiredSetting = 2 },
	{ id = 6, room = 3, slot = 2, keyClass = 2, tag = 2, requiredSetting = 1 },
	{ id = 7, room = 4, slot = 1, keyClass = 4, tag = 1, requiredSetting = 4 },
	{ id = 8, room = 4, slot = 2, keyClass = 4, tag = 2, requiredSetting = 2 },
	{ id = 9, room = 1, slot = 3, keyClass = 1, tag = 3, requiredSetting = 1 },
	{ id = 10, room = 2, slot = 3, keyClass = 2, tag = 3, requiredSetting = 3 },
}

TurnCuesContract.FIXTURE_TRACKS = { { 6, 8, 5, 9 }, { 1, 4, 7, 3 } }
TurnCuesContract.FIXTURE_FINALE = { 9, 3 }
TurnCuesContract.FIXTURE_DECOYS = { 2, 10 }

function TurnCuesContract.fixtureAssignment(): Assignment
	return {
		players = { "p1", "p2", "p3", "p4" },
		sigma = { p1 = "p2", p2 = "p3", p3 = "p4", p4 = "p1" },
		keyClasses = { p1 = { 1 }, p2 = { 2 }, p3 = { 3 }, p4 = { 4 } },
		lens = { p1 = 2, p2 = 3, p3 = 4, p4 = 1 },
	}
end

function TurnCuesContract.fixtureFacility(): any
	return {
		layout = {
			rooms = {
				{ id = 1, column = 1, row = 1 },
				{ id = 2, column = 2, row = 1 },
				{ id = 3, column = 1, row = 2 },
				{ id = 4, column = 2, row = 2 },
			},
			doors = { { a = 1, b = 2 }, { a = 1, b = 3 }, { a = 2, b = 4 }, { a = 3, b = 4 } },
			spawnRoom = 1,
		},
		placement = {
			machines = Deep.copy(FIXTURE_MACHINES),
			stepsPerClass = { [1] = 2, [2] = 2, [3] = 2, [4] = 2 },
		},
		steps = {
			tracks = Deep.copy(TurnCuesContract.FIXTURE_TRACKS),
			finale = Deep.copy(TurnCuesContract.FIXTURE_FINALE),
		},
		spawnRoom = 1,
		par = 60,
		attempt = 1,
	}
end

local function tuningWith(overrides: { [string]: any }): Tuning
	local fake: any = Deep.copy(MechanicsTuning)
	for key, value in pairs(overrides) do
		fake.instance[key] = value
	end
	fake.instance = table.freeze(fake.instance)
	fake.channel = table.freeze(fake.channel)
	fake.actuation = table.freeze(fake.actuation)
	return table.freeze(fake) :: Tuning
end

function TurnCuesContract.fixtureTuning(lookahead: number): Tuning
	return tuningWith({ turn_cue_lookahead = lookahead })
end

export type FixtureState = { label: string, committed: { number }, armed: number? }

local FIXTURE_STATES: { FixtureState } = {
	{ label = "S0 nothing committed", committed = {} },
	{ label = "S1 track 1's ordinary steps committed (6, 8, 5)", committed = { 6, 8, 5 } },
	{ label = "S2 track 2's ordinary steps committed (1, 4, 7)", committed = { 1, 4, 7 } },
	{ label = "S3 every ordinary step committed", committed = { 6, 8, 5, 1, 4, 7 } },
	{
		label = "S4 every ordinary step committed, machine 9 armed",
		committed = { 6, 8, 5, 1, 4, 7 },
		armed = 9,
	},
	{ label = "S5 machines 6 and 1 committed", committed = { 6, 1 } },
}

-- The exact cue sets, by lookahead, state label and player. Written by hand
-- from the table above - not computed - so that the oracle and the fixture
-- are two independent readings of G12.
local E = function(live: { number }, nextIds: { number }): any
	return { live = live, ["next"] = nextIds }
end

local FIXTURE_EXPECTED: { [number]: { [string]: { [string]: any } } } = {
	[1] = {
		["S0 nothing committed"] = {
			p1 = E({}, { 4 }),
			p2 = E({ 6 }, {}),
			p3 = E({ 1 }, {}),
			p4 = E({}, { 8 }),
		},
		["S1 track 1's ordinary steps committed (6, 8, 5)"] = {
			p1 = E({}, { 4, 9 }),
			p2 = E({}, {}),
			p3 = E({ 1 }, {}),
			p4 = E({}, {}),
		},
		["S2 track 2's ordinary steps committed (1, 4, 7)"] = {
			p1 = E({}, {}),
			p2 = E({ 6 }, {}),
			p3 = E({}, { 3 }),
			p4 = E({}, { 8 }),
		},
		["S3 every ordinary step committed"] = {
			p1 = E({ 9 }, {}),
			p2 = E({}, {}),
			p3 = E({ 3 }, {}),
			p4 = E({}, {}),
		},
		["S4 every ordinary step committed, machine 9 armed"] = {
			p1 = E({ 9 }, {}),
			p2 = E({}, {}),
			p3 = E({ 3 }, {}),
			p4 = E({}, {}),
		},
		["S5 machines 6 and 1 committed"] = {
			p1 = E({ 4 }, {}),
			p2 = E({}, { 5 }),
			p3 = E({}, {}),
			p4 = E({ 8 }, { 7 }),
		},
	},
	[2] = {
		["S0 nothing committed"] = {
			p1 = E({}, { 4 }),
			p2 = E({ 6 }, { 5 }),
			p3 = E({ 1 }, {}),
			p4 = E({}, { 7, 8 }),
		},
		["S1 track 1's ordinary steps committed (6, 8, 5)"] = {
			p1 = E({}, { 4, 9 }),
			p2 = E({}, {}),
			p3 = E({ 1 }, {}),
			p4 = E({}, { 7 }),
		},
		["S2 track 2's ordinary steps committed (1, 4, 7)"] = {
			p1 = E({}, {}),
			p2 = E({ 6 }, { 5 }),
			p3 = E({}, { 3 }),
			p4 = E({}, { 8 }),
		},
		["S3 every ordinary step committed"] = {
			p1 = E({ 9 }, {}),
			p2 = E({}, {}),
			p3 = E({ 3 }, {}),
			p4 = E({}, {}),
		},
		["S4 every ordinary step committed, machine 9 armed"] = {
			p1 = E({ 9 }, {}),
			p2 = E({}, {}),
			p3 = E({ 3 }, {}),
			p4 = E({}, {}),
		},
		["S5 machines 6 and 1 committed"] = {
			p1 = E({ 4 }, { 9 }),
			p2 = E({}, { 5 }),
			p3 = E({}, { 3 }),
			p4 = E({ 8 }, { 7 }),
		},
	},
}

export type Fixture = { assignment: Assignment, state: any, tuning: Tuning }

-- A fresh fixture state for `fixtureState`, under `tuning`.
function TurnCuesContract.fixture(fixtureState: FixtureState, tuning: Tuning): Fixture
	local base = Procedure.start(
		TurnCuesContract.fixtureFacility(),
		TurnCuesContract.NOW,
		tuning,
		TurnCuesContract.NOW,
		TurnCuesContract.ROUND_SECONDS
	)
	local committed: { [number]: boolean } = {}
	for _, id in fixtureState.committed do
		committed[id] = true
	end
	local armed = if fixtureState.armed ~= nil
		then {
			machineId = fixtureState.armed,
			closesAt = TurnCuesContract.NOW + tuning.instance.simultaneous_window_seconds,
		}
		else nil
	return {
		assignment = TurnCuesContract.fixtureAssignment(),
		state = withCommitted(base, committed, armed),
		tuning = tuning,
	}
end

--[[
	The fixture, exactly, under a tuning with `turn_cue_lookahead` =
	`lookahead`: every player at every one of the six states, compared by
	`Deep.diff` against the hand-written table - so order, an extra key, a
	missing cue and an extra one are all one diff. The fixture's premise is
	checked rather than assumed: the oracle must agree with the table, so a
	table written wrongly is reported as the fixture's error, not the view's.
]]
local function fixtureCuesAreExact(view: View, lookahead: number, criterion: string)
	local tuning = TurnCuesContract.fixtureTuning(lookahead)
	if tuning.instance.turn_cue_lookahead ~= lookahead then
		Contract.fail(`the fixture tuning did not take turn_cue_lookahead = {lookahead}`)
	end
	local table_ = FIXTURE_EXPECTED[lookahead]
	if table_ == nil then
		Contract.fail(
			`the fixture has no expectation table for turn_cue_lookahead = {lookahead}; `
				.. `if the shipped value moved, write the table for it`
		)
	end
	local violations: { string } = {}
	local count = 0
	for _, fs in FIXTURE_STATES do
		local f = TurnCuesContract.fixture(fs, tuning)
		for _, playerId in f.assignment.players do
			count += 1
			local want = table_[fs.label][playerId]
			local oracle = TurnCuesContract.expected(f.assignment, f.state, playerId)
			local premise = Deep.diff(want, { live = oracle.live, ["next"] = oracle.nextIds })
			if premise ~= "" then
				Contract.fail(
					`the fixture's table disagrees with the oracle at lookahead {lookahead}, `
						.. `{fs.label}, {playerId}:\n{premise}`
				)
			end
			local result = view(f.assignment, f.state, playerId)
			local diff = Deep.diff(want, result)
			if diff ~= "" then
				table.insert(
					violations,
					`  {fs.label}, {playerId}: expected {Deep.show(want)}, got {Deep.show(result)}`
				)
			end
		end
	end
	if #violations > 0 then
		Contract.fail(
			`{criterion}: on the hand-built fixture at turn_cue_lookahead = {lookahead} (from `
				.. `procedure.tuning) the cues are not exactly the table's in {#violations} of `
				.. `{count} cases:\n{table.concat(violations, "\n")}`
		)
	end
end

-- AC-3's second control, made a test of the real view: lookahead 2 sees
-- machines 5 and 7 at S0 and 9 and 3 at S5, which lookahead 1 does not.
function TurnCuesContract.lookaheadTwoSeesTheExtraCue(view: View)
	if MechanicsTuning.instance.turn_cue_lookahead == 2 then
		Contract.fail(
			"the shipped turn_cue_lookahead is 2, so a view reading MechanicsTuning directly "
				.. "could not be told apart from one reading procedure.tuning"
		)
	end
	fixtureCuesAreExact(view, 2, "AC-3")
end

-- AC-4 and AC-6 on the fixture at the shipped lookahead: the waiting finale
-- in next at S1 and S2, and the two-cue list [4, 9] ascending, not [9, 4].
function TurnCuesContract.fixtureCuesAtShippedLookahead(view: View)
	fixtureCuesAreExact(view, MechanicsTuning.instance.turn_cue_lookahead, "AC-4/AC-6")
end

return TurnCuesContract
