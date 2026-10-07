--!strict
--[[
	VIEW-004 AC-1 through AC-5 and the story's Contract, written once as
	checks over a POSITIONS MODULE and a SESSION MODULE handed in as
	parameters - the `TurnCuesContract` / `SessionRoundContract` arrangement,
	for the same reason: in RED `src/server/session/Positions.luau` does not
	exist and `Session` stores samples unfiltered, so every test in
	`tests/server/positions_test.luau` and `session_positions_test.luau` fails
	before any assertion here has been seen to accept or reject anything, and
	`tests/server/positions_controls_test.luau` is where each check is
	EXECUTED against a reference stand-in and stand-ins wrong in exactly one
	way (`PositionsStubs.luau`, `SessionRoundStubs.luau`).

	TWO BATTERIES. `MODULE_CHECKS` take a Positions module `P` and pin AC-1 to
	AC-4's clauses on `placed`, `offer` and `needsResync` directly - the pure
	logic lives there, so that is the cheapest level that can falsify it.
	`SESSION_CHECKS` take a Session module `S` and a Positions module `P` (for
	its constants only) and pin what the Contract says `Session.step` does
	with the rule: the deal's placement as the baseline (AC-2), an unplaced
	player absent from `positions` and out of reach (AC-3), the resync
	placement in `Round` only (AC-4), a turn judged against the accepted
	position (AC-5), `tracks` from `new` and the deal, samples merged into
	fresh accepted copies, and the walk speed read from `state.tuning`.

	THE ORACLE PARTITION (story `## Contract`). Everything here is MECHANICAL
	against the module's own constants: `TOLERANCE`, `SLACK_STUDS` and
	`RESYNC_SECONDS` are READ from `P` and never restated; the walk speed is
	read from the `MechanicsTuning` in use. The only literal distances are
	AC-1's settled controls (200 studs in 0.1 s refused, 1.5 studs in 0.1 s
	accepted) and jumps sized to be implausible under any constants a
	precondition has just read (a 1,000-stud jump against a bound the check
	computes from `P`). Every boundary - exactly `bound`, a hair past it,
	exactly `RESYNC_SECONDS`, a hair more - is computed from those constants.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local MechanicsTuning = require("../../src/shared/MechanicsTuning")
local ScriptedRound = require("./ScriptedRound")

local PositionsContract = {}

export type Vec = { x: number, y: number, z: number }
export type Positions = any
export type Session = any

PositionsContract.TRACK_KEYS = { "accepted", "acceptedAt", "refusals" } -- refusedSince absent when nil
PositionsContract.VEC_KEYS = { "x", "y", "z" }
PositionsContract.EXPORTS = { "TOLERANCE", "SLACK_STUDS", "RESYNC_SECONDS" }
PositionsContract.FUNCTIONS = { "placed", "offer", "needsResync" }

-- A hair: far above any rounding in the arithmetic below, far below a stud.
PositionsContract.HAIR = 1e-6

function PositionsContract.walkSpeed(): number
	return MechanicsTuning.instance.walk_speed_studs_per_second
end

--[[ ------------------------------------------------------------------------
     Small instruments.
     --------------------------------------------------------------------- ]]

local function keysOf(value: any): { string }
	local keys: { string } = {}
	for key in pairs(value :: { [any]: any }) do
		table.insert(keys, tostring(key))
	end
	table.sort(keys)
	return keys
end

local function vec(x: number, y: number, z: number): Vec
	return { x = x, y = y, z = z }
end

local function fewProblems(criterion: string, headline: string, problems: { string })
	if #problems > 0 then
		Contract.fail(`{criterion}: {headline}:\n{Contract.firstFew(problems, 10)}`)
	end
end

-- The module's exports, or the failure that names what is missing.
local function requireModule(criterion: string, P: any)
	if typeof(P) ~= "table" then
		Contract.fail(
			`{criterion}: Positions is {Deep.show(P)}, not a module table - VIEW-004's Contract exports src/server/session/Positions.luau`
		)
	end
	for _, name in PositionsContract.EXPORTS do
		if typeof(P[name]) ~= "number" then
			Contract.fail(
				`{criterion}: Positions.{name} is {typeof(P[name])}, expected a number - VIEW-004's Contract exports TOLERANCE, SLACK_STUDS and RESYNC_SECONDS`
			)
		end
	end
	for _, name in PositionsContract.FUNCTIONS do
		if typeof(P[name]) ~= "function" then
			Contract.fail(
				`{criterion}: Positions.{name} is {typeof(P[name])}, expected a function - VIEW-004's Contract exports placed(track, at, now), offer(track, candidate, now, walkSpeed) and needsResync(track, now)`
			)
		end
	end
end
PositionsContract.requireModule = requireModule

local function requireSession(criterion: string, S: any)
	if typeof(S) ~= "table" then
		Contract.fail(`{criterion}: Session is {Deep.show(S)}, not a module table`)
	end
	for _, name in { "new", "step" } do
		if typeof(S[name]) ~= "function" then
			Contract.fail(`{criterion}: Session.{name} is {typeof(S[name])}, expected a function`)
		end
	end
end

-- The bound the Contract pins, from the module's own constants.
function PositionsContract.bound(P: Positions, walkSpeed: number, dt: number): number
	return walkSpeed * P.TOLERANCE * dt + P.SLACK_STUDS
end

local function horizontal(a: Vec, b: Vec): number
	local dx = b.x - a.x
	local dz = b.z - a.z
	return math.sqrt(dx * dx + dz * dz)
end

-- `offer` through a pcall, so a raising module fails on the criterion.
local function offer(
	criterion: string,
	P: Positions,
	track: any,
	candidate: Vec,
	now: number,
	walkSpeed: number
): (any, boolean)
	local ok, next_, accepted = pcall(P.offer, track, candidate, now, walkSpeed)
	if not ok then
		Contract.fail(
			`{criterion}: Positions.offer({Deep.show(track)}, {Deep.show(candidate)}, {now}, {walkSpeed}) RAISED: {tostring(
				next_
			)}`
		)
	end
	if typeof(next_) ~= "table" then
		Contract.fail(
			`{criterion}: Positions.offer returned {Deep.show(next_)} as the track, expected a Track table`
		)
	end
	if typeof(accepted) ~= "boolean" then
		Contract.fail(
			`{criterion}: Positions.offer returned {Deep.show(accepted)} as accepted?, expected a boolean`
		)
	end
	return next_, accepted
end

local function placed(criterion: string, P: Positions, track: any, at: Vec, now: number): any
	local ok, next_ = pcall(P.placed, track, at, now)
	if not ok then
		Contract.fail(
			`{criterion}: Positions.placed({Deep.show(track)}, {Deep.show(at)}, {now}) RAISED: {tostring(
				next_
			)}`
		)
	end
	if typeof(next_) ~= "table" then
		Contract.fail(
			`{criterion}: Positions.placed returned {Deep.show(next_)}, expected a Track table`
		)
	end
	return next_
end

local function needsResync(criterion: string, P: Positions, track: any, now: number): boolean
	local ok, result = pcall(P.needsResync, track, now)
	if not ok then
		Contract.fail(
			`{criterion}: Positions.needsResync({Deep.show(track)}, {now}) RAISED: {tostring(result)}`
		)
	end
	if typeof(result) ~= "boolean" then
		Contract.fail(
			`{criterion}: Positions.needsResync returned {Deep.show(result)}, expected a boolean`
		)
	end
	return result
end

-- A track deep-equals the Contract's Track with these fields (refusedSince
-- absent when nil); the comparison is exact because the type is.
local function expectTrack(
	problems: { string },
	label: string,
	got: any,
	accepted: Vec?,
	acceptedAt: number?,
	refusedSince: number?,
	refusals: number
)
	local want: any = { refusals = refusals }
	if accepted ~= nil then
		want.accepted = { x = accepted.x, y = accepted.y, z = accepted.z }
	end
	want.acceptedAt = acceptedAt
	want.refusedSince = refusedSince
	if not Deep.equal(got, want) then
		table.insert(
			problems,
			`{label}: the track is {Deep.show(got)}, expected {Deep.show(want)}:\n{Contract.firstFew(
				string.split(Deep.diff(want, got), "\n"),
				4
			)}`
		)
	end
end

--[[ ------------------------------------------------------------------------
     MODULE_CHECKS: the pure rule.
     --------------------------------------------------------------------- ]]

--[[
	Contract: the three constants are numbers with the floors the Contract's
	reasoning implies (a tolerance below 1 refuses an honest walk; negative
	slack refuses a standing player; a resync of 0 would place on the first
	refusal), and the three functions exist.
]]
function PositionsContract.exportsTheContractShape(P: Positions)
	requireModule("Contract", P)
	local problems: { string } = {}
	if P.TOLERANCE < 1 then
		table.insert(
			problems,
			`TOLERANCE is {P.TOLERANCE}; below 1 a sample at walk speed is refused`
		)
	end
	if P.SLACK_STUDS < 0 then
		table.insert(
			problems,
			`SLACK_STUDS is {P.SLACK_STUDS}; negative slack refuses standing still`
		)
	end
	if P.RESYNC_SECONDS <= 0 then
		table.insert(
			problems,
			`RESYNC_SECONDS is {P.RESYNC_SECONDS}; it must be a positive run of refusals`
		)
	end
	fewProblems(
		"Contract",
		"Positions must export TOLERANCE >= 1, SLACK_STUDS >= 0, RESYNC_SECONDS > 0, placed, offer and needsResync",
		problems
	)
end

--[[
	AC-1's settled controls: from a placement at the origin at t = 0, a
	candidate 200 studs away at t = 0.1 is refused (the previous sample kept,
	one rejection counted, the refusal run started at 0.1) and one 1.5 studs
	away at t = 0.1 is accepted (stored, no run, no rejection).
]]
function PositionsContract.settledControlsRefuse200AndAccept1_5(P: Positions)
	requireModule("AC-1", P)
	local w = PositionsContract.walkSpeed()
	local problems: { string } = {}
	local origin = vec(0, 0, 0)
	local base = placed("AC-1", P, nil, origin, 0)

	local far, farOk = offer("AC-1", P, base, vec(200, 0, 0), 0.1, w)
	if farOk then
		table.insert(
			problems,
			`a candidate 200 studs away 0.1 s later was ACCEPTED (bound {PositionsContract.bound(
				P,
				w,
				0.1
			)})`
		)
	end
	expectTrack(problems, "after the 200-stud candidate", far, origin, 0, 0.1, 1)

	local near, nearOk = offer("AC-1", P, base, vec(1.5, 0, 0), 0.1, w)
	if not nearOk then
		table.insert(
			problems,
			`a candidate 1.5 studs away 0.1 s later was REFUSED (bound {PositionsContract.bound(
				P,
				w,
				0.1
			)})`
		)
	end
	expectTrack(problems, "after the 1.5-stud candidate", near, vec(1.5, 0, 0), 0.1, nil, 0)
	fewProblems(
		"AC-1",
		"200 studs in 0.1 s must be refused with the previous sample kept and a rejection counted; 1.5 studs in 0.1 s must be accepted",
		problems
	)
end

--[[
	AC-1, the boundary: with dt = 1 the bound is `walkSpeed x TOLERANCE +
	SLACK_STUDS`; a candidate at EXACTLY that horizontal distance is accepted
	(inclusive), one a hair past it is refused. Along x only, so the distance
	is exact. D-2 (`<` for `<=`) must turn the first half red.
]]
function PositionsContract.boundIsInclusive(P: Positions)
	requireModule("AC-1", P)
	local w = PositionsContract.walkSpeed()
	local problems: { string } = {}
	local base = placed("AC-1", P, nil, vec(0, 0, 0), 0)
	local bound = PositionsContract.bound(P, w, 1)

	local at, atOk = offer("AC-1", P, base, vec(bound, 0, 0), 1, w)
	if not atOk then
		table.insert(
			problems,
			`a candidate at EXACTLY the bound ({bound} studs in 1 s) was refused; the bound is inclusive`
		)
	end
	expectTrack(problems, "at exactly the bound", at, vec(bound, 0, 0), 1, nil, 0)

	local past, pastOk = offer("AC-1", P, base, vec(bound + PositionsContract.HAIR, 0, 0), 1, w)
	if pastOk then
		table.insert(
			problems,
			`a candidate a hair past the bound ({bound} + {PositionsContract.HAIR} studs in 1 s) was accepted`
		)
	end
	expectTrack(problems, "a hair past the bound", past, vec(0, 0, 0), 0, 1, 1)
	fewProblems(
		"AC-1",
		"a candidate at exactly walkSpeed x TOLERANCE x dt + SLACK_STUDS must be accepted and one a hair past it refused",
		problems
	)
end

--[[
	AC-1, `y` ignored (architecture.md 9.8): a candidate straight up by 500
	studs with no horizontal move is accepted, and one a stud inside the
	horizontal bound with a 500-stud `y` offset is still accepted.
]]
function PositionsContract.yIsIgnored(P: Positions)
	requireModule("AC-1", P)
	local w = PositionsContract.walkSpeed()
	local problems: { string } = {}
	local base = placed("AC-1", P, nil, vec(0, 0, 0), 0)
	local up, upOk = offer("AC-1", P, base, vec(0, 500, 0), 0.1, w)
	if not upOk then
		table.insert(problems, "a candidate 500 studs straight up, 0.1 s later, was refused")
	end
	expectTrack(problems, "straight up", up, vec(0, 500, 0), 0.1, nil, 0)
	local inside = PositionsContract.bound(P, w, 1) - 1
	local _, diagOk = offer("AC-1", P, base, vec(inside, 500, 0), 1, w)
	if not diagOk then
		table.insert(
			problems,
			`a candidate a stud inside the horizontal bound ({inside}) with a 500-stud y offset was refused; y is not a distance`
		)
	end
	fewProblems("AC-1", "the vertical component must not count towards the bound", problems)
end

--[[
	AC-1, dt from the last ACCEPTED sample: a candidate just past the 3.5 s
	bound is refused at t = 3, refused again at t = 3.5 (the run and the
	count grow; the baseline does not move), and accepted at t = 4 when the
	bound, still measured from t = 0, has grown past it. After acceptance the
	run is cleared and the count kept.
]]
function PositionsContract.dtIsMeasuredFromTheLastAcceptedSample(P: Positions)
	requireModule("AC-1", P)
	local w = PositionsContract.walkSpeed()
	local problems: { string } = {}
	local base = placed("AC-1", P, nil, vec(0, 0, 0), 0)
	-- Just past the 3.5 s bound: refused at 3 and 3.5, inside the 4 s bound
	-- (it grows by walkSpeed x TOLERANCE / 2 >= 1 over that half second).
	local d = PositionsContract.bound(P, w, 3.5) + 1
	local candidate = vec(d, 0, 0)

	local t3, ok3 = offer("AC-1", P, base, candidate, 3, w)
	if ok3 then
		table.insert(
			problems,
			`{d} studs at t = 3 was accepted; the bound is {PositionsContract.bound(P, w, 3)}`
		)
	end
	expectTrack(problems, "after the refusal at t = 3", t3, vec(0, 0, 0), 0, 3, 1)

	local t35, ok35 = offer("AC-1", P, t3, candidate, 3.5, w)
	if ok35 then
		table.insert(
			problems,
			`{d} studs at t = 3.5 was accepted; the bound from the last accepted sample (t = 0) is {PositionsContract.bound(
				P,
				w,
				3.5
			)}`
		)
	end
	expectTrack(problems, "after the refusal at t = 3.5", t35, vec(0, 0, 0), 0, 3, 2)

	local t4, ok4 = offer("AC-1", P, t35, candidate, 4, w)
	if not ok4 then
		table.insert(
			problems,
			`{d} studs at t = 4 was refused; measured from the last ACCEPTED sample (t = 0) the bound is {PositionsContract.bound(
				P,
				w,
				4
			)}, so a module measuring from the last offered sample (t = 3.5) is wrong`
		)
	end
	expectTrack(problems, "after the acceptance at t = 4", t4, candidate, 4, nil, 2)
	fewProblems(
		"AC-1",
		"dt is measured from the last accepted sample: after refusals the bound keeps growing and the count and run persist until an acceptance",
		problems
	)
end

--[[
	AC-1, `dt = max(0, now - acceptedAt)`: with `now` before `acceptedAt` the
	bound is SLACK_STUDS alone - a candidate exactly SLACK_STUDS away is
	accepted, one half a stud further is refused. A negative dt would refuse
	the first; an absolute dt would accept the second.
]]
function PositionsContract.nowBeforeAcceptedAtClampsDtToZero(P: Positions)
	requireModule("AC-1", P)
	local w = PositionsContract.walkSpeed()
	local problems: { string } = {}
	local base = placed("AC-1", P, nil, vec(0, 0, 0), 10)
	local slack = P.SLACK_STUDS
	local _, slackOk = offer("AC-1", P, base, vec(slack, 0, 0), 5, w)
	if not slackOk then
		table.insert(
			problems,
			`with now = 5 before acceptedAt = 10, a candidate SLACK_STUDS ({slack}) away was refused; dt clamps to 0, so the bound is SLACK_STUDS`
		)
	end
	local _, pastOk = offer("AC-1", P, base, vec(slack + 0.5, 0, 0), 5, w)
	if pastOk then
		table.insert(
			problems,
			`with now = 5 before acceptedAt = 10, a candidate SLACK_STUDS + 0.5 away was accepted; dt clamps to 0, never |now - acceptedAt|`
		)
	end
	fewProblems(
		"AC-1",
		"a now before acceptedAt must clamp dt to 0, leaving a bound of SLACK_STUDS",
		problems
	)
end

--[[
	AC-2: a placement is the new baseline. A track placed at A and then
	placed at B 300 studs away accepts a sample at B right after; the same
	track without the second placement refuses it. `placed` copies `at`, sets
	`acceptedAt = now`, clears the run and carries the refusal count (0 from
	nil).
]]
function PositionsContract.placedResetsTheBaseline(P: Positions)
	requireModule("AC-2", P)
	local w = PositionsContract.walkSpeed()
	local problems: { string } = {}
	local a = vec(0, 0, 0)
	local b = vec(300, 0, 0)
	local atA = placed("AC-2", P, nil, a, 0)
	expectTrack(problems, "placed from nil", atA, a, 0, nil, 0)

	local atB = placed("AC-2", P, atA, b, 1)
	expectTrack(problems, "placed again at B", atB, b, 1, nil, 0)
	local _, okB = offer("AC-2", P, atB, vec(300, 0, 0), 1.1, w)
	if not okB then
		table.insert(problems, "a sample at B 0.1 s after a placement at B was refused")
	end

	local _, okJump = offer("AC-2", P, atA, vec(300, 0, 0), 1.1, w)
	if okJump then
		table.insert(
			problems,
			`the control: the same 300-stud sample WITHOUT the placement at B was accepted (bound {PositionsContract.bound(
				P,
				w,
				1.1
			)})`
		)
	end

	-- The count survives a placement; the run does not; `at` is copied.
	local refused = atA
	for i = 1, 3 do
		refused = offer("AC-2", P, refused, vec(1000, 0, 0), 0.1 * i, w)
	end
	expectTrack(problems, "after three refusals", refused, a, 0, 0.1, 3)
	local at = vec(7, 0, 7)
	local replaced = placed("AC-2", P, refused, at, 5)
	expectTrack(problems, "placed after three refusals", replaced, at, 5, nil, 3)
	if rawequal(replaced.accepted, at) then
		table.insert(problems, "placed stored the `at` table itself; the Contract wants a copy")
	end
	fewProblems(
		"AC-2",
		"a placement must become the baseline (a sample there is accepted; without it the jump is refused), clear the run and carry the count",
		problems
	)
end

--[[
	AC-3: with no baseline a first sample is NOT accepted, not stored, not
	counted as a refusal and starts no run - from a nil track and from a
	track with no accepted sample alike; a placement then makes the next
	sample acceptable.
]]
function PositionsContract.noBaselineMeansNoAcceptanceAndNoRefusal(P: Positions)
	requireModule("AC-3", P)
	local w = PositionsContract.walkSpeed()
	local problems: { string } = {}
	local first, firstOk = offer("AC-3", P, nil, vec(5, 0, 5), 0, w)
	if firstOk then
		table.insert(problems, "a first sample with no baseline (nil track) was accepted")
	end
	expectTrack(problems, "after a first sample on a nil track", first, nil, nil, nil, 0)

	local second, secondOk = offer("AC-3", P, first, vec(5, 0, 5), 1, w)
	if secondOk then
		table.insert(problems, "a second sample with still no baseline was accepted")
	end
	expectTrack(problems, "after a second sample with no baseline", second, nil, nil, nil, 0)

	local base = placed("AC-3", P, second, vec(5, 0, 5), 2)
	local _, okAfter = offer("AC-3", P, base, vec(5, 0, 5), 2.1, w)
	if not okAfter then
		table.insert(problems, "after a placement the sample at the placement was refused")
	end
	fewProblems(
		"AC-3",
		"with no baseline a sample must be neither accepted nor counted as a refusal, and a placement must then make the next sample acceptable",
		problems
	)
end

--[[
	AC-4's clause: `needsResync` is true only for a track with an accepted
	sample whose refusal run is STRICTLY longer than RESYNC_SECONDS: false at
	exactly RESYNC_SECONDS after the run began, true a hair later, false for
	nil, for no baseline, for no run, and again after an acceptance. D-5
	(`>=` for `>`) must turn the exact case red.
]]
function PositionsContract.needsResyncIsStrictlyAfterResyncSeconds(P: Positions)
	requireModule("AC-4", P)
	local w = PositionsContract.walkSpeed()
	local problems: { string } = {}
	local R = P.RESYNC_SECONDS
	local base = placed("AC-4", P, nil, vec(0, 0, 0), 0)
	local refused = offer("AC-4", P, base, vec(1000, 0, 0), 1, w)
	expectTrack(problems, "after the first refusal at t = 1", refused, vec(0, 0, 0), 0, 1, 1)

	if needsResync("AC-4", P, refused, 1 + R) then
		table.insert(
			problems,
			`needsResync is true at exactly RESYNC_SECONDS ({R} s) after the run began; the Contract says strictly longer`
		)
	end
	if needsResync("AC-4", P, refused, 1 + R - 0.5) then
		table.insert(problems, `needsResync is true {R - 0.5} s into the run`)
	end
	if not needsResync("AC-4", P, refused, 1 + R + PositionsContract.HAIR) then
		table.insert(
			problems,
			`needsResync is false a hair more than RESYNC_SECONDS ({R} s) after the run began`
		)
	end
	if needsResync("AC-4", P, nil, 100) then
		table.insert(problems, "needsResync(nil) is true")
	end
	local unplaced = offer("AC-4", P, nil, vec(1, 0, 1), 0, w)
	if needsResync("AC-4", P, unplaced, 100) then
		table.insert(problems, "needsResync is true for a track with no accepted sample")
	end
	if needsResync("AC-4", P, base, 100) then
		table.insert(problems, "needsResync is true for a track with no refusal run")
	end
	local recovered = offer("AC-4", P, refused, vec(0, 0, 0), 1 + R + 1, w)
	if needsResync("AC-4", P, recovered, 1 + R + 2) then
		table.insert(problems, "needsResync is still true after an acceptance ended the run")
	end
	fewProblems(
		"AC-4",
		"needsResync must be true only when an accepted track's refusal run is strictly longer than RESYNC_SECONDS",
		problems
	)
end

--[[
	Contract: pure. No argument is mutated by any of the three functions, the
	returned track is never the one handed in, and the stored vector is never
	the candidate or `at` table.
]]
function PositionsContract.isPureAndReturnsFreshTables(P: Positions)
	requireModule("Contract", P)
	local w = PositionsContract.walkSpeed()
	local problems: { string } = {}
	local at = vec(1, 2, 3)
	local atSnapshot = Deep.copy(at)
	local base = placed("Contract", P, nil, at, 0)
	if rawequal(base.accepted, at) then
		table.insert(problems, "placed stored the `at` table itself")
	end
	if not Deep.equal(at, atSnapshot) then
		table.insert(problems, "placed mutated `at`")
	end
	local baseSnapshot = Deep.copy(base)
	local candidate = vec(2, 2, 3)
	local candidateSnapshot = Deep.copy(candidate)
	local accepted = offer("Contract", P, base, candidate, 1, w)
	if rawequal(accepted, base) then
		table.insert(problems, "offer returned the track it was handed (accepted case)")
	end
	if rawequal(accepted.accepted, candidate) then
		table.insert(problems, "offer stored the candidate table itself")
	end
	local refusedTrack = offer("Contract", P, base, vec(1000, 0, 0), 1.1, w)
	if rawequal(refusedTrack, base) then
		table.insert(problems, "offer returned the track it was handed (refused case)")
	end
	if not Deep.equal(base, baseSnapshot) then
		table.insert(problems, `offer mutated its track argument:\n{Deep.diff(baseSnapshot, base)}`)
	end
	if not Deep.equal(candidate, candidateSnapshot) then
		table.insert(problems, "offer mutated its candidate argument")
	end
	local replaced = placed("Contract", P, accepted, vec(9, 9, 9), 2)
	if rawequal(replaced, accepted) then
		table.insert(problems, "placed returned the track it was handed")
	end
	local acceptedSnapshot = Deep.copy(accepted)
	needsResync("Contract", P, accepted, 50)
	if not Deep.equal(accepted, acceptedSnapshot) then
		table.insert(problems, "placed or needsResync mutated the track handed in")
	end
	fewProblems(
		"Contract",
		"placed, offer and needsResync must mutate no argument and return fresh tables",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     SESSION_CHECKS: the rule wired into Session.step.
     --------------------------------------------------------------------- ]]

PositionsContract.N = 4

-- A driver through the deal; `players` overrides the join (and so seat) order.
local function startRound(
	criterion: string,
	S: Session,
	seed: number,
	players: { string }?,
	options: any?
): ScriptedRound.Driver
	requireSession(criterion, S)
	local ok, d = pcall(function()
		local driver = ScriptedRound.new(S, seed, PositionsContract.N, options)
		if players ~= nil then
			driver.players = table.clone(players)
		end
		ScriptedRound.join(driver)
		ScriptedRound.deal(driver)
		if driver.state.facility == nil or driver.state.assignment == nil then
			error("no facility or assignment after the deal", 0)
		end
		return driver
	end)
	if not ok then
		Contract.fail(`{criterion}: the session could not be dealt (seed {seed}): {tostring(d)}`)
	end
	return d
end

local function sampleAt(d: ScriptedRound.Driver, samples: { [string]: Vec }, now: number): { any }
	if now < d.now then
		error(`a sample at {now} would move the clock backwards from {d.now}`, 0)
	end
	d.now = now
	return ScriptedRound.step(d, { kind = "PositionsSampled", samples = Deep.copy(samples) })
end

local function centreOf(d: ScriptedRound.Driver): Vec
	return ScriptedRound.spawnCentre(d.state.facility, d.tuning)
end

local function plus(v: Vec, dx: number, dy: number, dz: number): Vec
	return vec(v.x + dx, v.y + dy, v.z + dz)
end

-- `state.positions` deep-equals `want`; absent players are absent.
local function expectPositions(problems: { string }, label: string, state: any, want: any)
	if not Deep.equal(state.positions, want) then
		table.insert(
			problems,
			`{label}: state.positions is {Deep.show(state.positions)}, expected {Deep.show(want)}`
		)
	end
end

local function expectNoEffects(problems: { string }, label: string, effects: { any })
	if #effects ~= 0 then
		table.insert(
			problems,
			`{label}: {Deep.show(Deep.kinds(effects))} emitted on a PositionsSampled, expected \{}`
		)
	end
end

local function everyoneAt(d: ScriptedRound.Driver, at: Vec): { [string]: Vec }
	local out: { [string]: Vec } = {}
	for _, p in d.state.assignment.players do
		out[p] = vec(at.x, at.y, at.z)
	end
	return out
end

-- A jump the check has just shown to be implausible under `P` for any dt up
-- to `maxDt`; the precondition keeps the literal honest.
local function implausibleOffset(criterion: string, P: Positions, maxDt: number): number
	local far = 1000
	local bound = PositionsContract.bound(P, PositionsContract.walkSpeed(), maxDt)
	if far <= bound then
		Contract.fail(
			`{criterion} precondition: a {far}-stud jump is within the bound {bound} for dt = {maxDt}; the constants are not what the Contract says`
		)
	end
	return far
end

--[[
	AC-2 in Session: the deal's placement is the baseline. Right after the
	deal a sample of everyone at the spawn centre is accepted (positions
	unchanged, tracks moved to that `now`, nothing emitted) and a far jump
	right after is refused (positions kept, one refusal counted, the run
	started). The control: the same jump in a Lobby with no deal is not
	accepted either, and there it is not a refusal (AC-3).
]]
function PositionsContract.dealPlacementIsTheBaseline(S: Session, P: Positions)
	requireModule("AC-2", P)
	local d = startRound("AC-2", S, 101)
	local T = d.now
	local centre = centreOf(d)
	local problems: { string } = {}
	local far = implausibleOffset("AC-2", P, 1)

	local effects = sampleAt(d, everyoneAt(d, centre), T + 0.1)
	expectNoEffects(problems, "everyone sampled at the centre 0.1 s after the deal", effects)
	expectPositions(
		problems,
		"everyone sampled at the centre 0.1 s after the deal",
		d.state,
		everyoneAt(d, centre)
	)
	for _, p in d.state.assignment.players do
		expectTrack(
			problems,
			`track of {p} after the centre sample`,
			(d.state.tracks or {})[p],
			centre,
			T + 0.1,
			nil,
			0
		)
	end

	local jumper = d.state.assignment.players[1]
	effects = sampleAt(d, { [jumper] = plus(centre, far, 0, 0) }, T + 0.2)
	expectNoEffects(problems, "the far jump", effects)
	expectPositions(problems, "the far jump", d.state, everyoneAt(d, centre))
	expectTrack(
		problems,
		`track of {jumper} after the far jump`,
		(d.state.tracks or {})[jumper],
		centre,
		T + 0.1,
		T + 0.2,
		1
	)

	-- The control: no deal, no baseline.
	local lobby = ScriptedRound.new(S, 102, PositionsContract.N)
	ScriptedRound.join(lobby)
	local who = lobby.players[1]
	effects = sampleAt(lobby, { [who] = plus(centre, far, 0, 0) }, 0.2)
	expectNoEffects(problems, "the control jump in a Lobby with no deal", effects)
	if lobby.state.positions[who] ~= nil then
		table.insert(
			problems,
			`the control: the same jump in a Lobby with no deal was stored as {Deep.show(
				lobby.state.positions[who]
			)}; with no placement there is no baseline`
		)
	end
	local track = (lobby.state.tracks or {})[who]
	if
		track ~= nil and (track.accepted ~= nil or track.refusals ~= 0 or track.refusedSince ~= nil)
	then
		table.insert(
			problems,
			`the control: the Lobby track of {who} is {Deep.show(track)}; with no baseline a sample is neither accepted nor a refusal`
		)
	end
	fewProblems(
		"AC-2",
		"the deal's placement must be the baseline: a sample at the centre right after is accepted, a far jump right after is refused, and the same jump with no deal is not stored",
		problems
	)
end

--[[
	AC-3 in Session: a player with no accepted sample is ABSENT from
	`state.positions`, so a turn by them is refused out_of_reach even with a
	sample AT the machine. Driven on a post-deal state whose track for the
	turner of T1[1] has been removed (a join is Lobby-only and the deal
	places everyone, so no event reaches this state; the Contract's rule is
	what is pinned).
]]
function PositionsContract.unplacedPlayerIsAbsentAndOutOfReach(S: Session, P: Positions)
	requireModule("AC-3", P)
	local d = startRound("AC-3", S, 103)
	local T = d.now
	local problems: { string } = {}
	local facility = d.state.facility
	local id = facility.steps.tracks[1][1]
	local m = ScriptedRound.machineOf(facility, id)
	local turner = ScriptedRound.turnerOf(d.state.assignment, m)
	local at = ScriptedRound.machinePosition(d, m)

	local stripped = Deep.copy(d.state)
	if typeof(stripped.tracks) ~= "table" then
		Contract.fail(
			`AC-3: state.tracks is {Deep.show(stripped.tracks)} after the deal; the Contract's SessionState carries tracks`
		)
	end
	stripped.tracks[turner] = nil
	stripped.positions[turner] = nil
	d.state = stripped

	local effects = sampleAt(d, { [turner] = at }, T + 0.1)
	expectNoEffects(problems, "the unplaced turner's sample at the machine", effects)
	if d.state.positions[turner] ~= nil then
		table.insert(
			problems,
			`{turner} has no accepted sample, yet state.positions[{turner}] is {Deep.show(
				d.state.positions[turner]
			)} after a sample at machine {id}`
		)
	end
	local track = (d.state.tracks or {})[turner]
	if
		track ~= nil and (track.accepted ~= nil or track.refusals ~= 0 or track.refusedSince ~= nil)
	then
		table.insert(
			problems,
			`the track of {turner} is {Deep.show(track)}; a sample with no baseline is neither accepted nor a refusal`
		)
	end
	d.now = T + 0.2
	local turn = ScriptedRound.turn(d, turner, id, m.requiredSetting)
	local r = turn.reply
	if not (typeof(r) == "table" and r.kind == "refused" and r.reason == "out_of_reach") then
		table.insert(
			problems,
			`{turner}'s turn on machine {id} after an unaccepted sample AT it replied {Deep.show(r)}, expected refused / out_of_reach - no range rule may treat an unplaced player as in range`
		)
	end
	fewProblems(
		"AC-3",
		"a player with no accepted sample must be absent from state.positions and out of reach of every machine",
		problems
	)
end

--[[
	AC-4 in Session: refused continuously for longer than RESYNC_SECONDS in
	Round, the next sample places the player back at their last accepted
	position - exactly one Placed { playerId, position } per such player,
	ascending by playerId, each position a fresh table, nothing else emitted
	- and resets the baseline there (the run cleared, a following sample at
	that position accepted, the refusal count kept). Refused for exactly
	RESYNC_SECONDS, nothing is placed. Outside Round (the next Lobby, tracks
	kept) nothing is placed however long the run.
]]
function PositionsContract.resyncPlacesBackInRoundOnly(S: Session, P: Positions)
	requireModule("AC-4", P)
	local R = P.RESYNC_SECONDS
	local problems: { string } = {}
	local far = implausibleOffset("AC-4", P, R + 2)

	-- Seat order dan, cat, bob, ann: ascending playerId is the reverse.
	local d = startRound("AC-4", S, 104, { "dan", "cat", "bob", "ann" })
	local T = d.now
	local centre = centreOf(d)
	local away = plus(centre, far, 0, 0)

	local effects = sampleAt(d, { dan = away }, T + 1)
	expectNoEffects(problems, "dan's first refused sample", effects)
	effects = sampleAt(d, { dan = away }, T + 1 + R)
	expectNoEffects(problems, `dan refused for exactly RESYNC_SECONDS ({R} s)`, effects)
	expectPositions(
		problems,
		"dan refused for exactly RESYNC_SECONDS",
		d.state,
		everyoneAt(d, centre)
	)
	expectTrack(
		problems,
		"dan's track at exactly RESYNC_SECONDS",
		(d.state.tracks or {})[`dan`],
		centre,
		T,
		T + 1,
		2
	)

	local resyncAt = T + 1 + R + 0.5
	effects = sampleAt(d, { dan = away, ann = away }, resyncAt)
	local wantPlaced = { { kind = "Placed", playerId = "dan", position = centre } }
	if not Deep.equal(effects, wantPlaced) then
		table.insert(
			problems,
			`dan refused for {R + 0.5} s: the sample emitted {Deep.show(effects)}, expected exactly {Deep.show(
				wantPlaced
			)} (ann's first refusal is not a resync)`
		)
	end
	local placedEffect = effects[1]
	if
		typeof(placedEffect) == "table"
		and typeof(placedEffect.position) == "table"
		and rawequal(placedEffect.position, d.state.positions.dan)
	then
		table.insert(
			problems,
			"the Placed position IS state.positions.dan (aliased); the Contract wants a fresh table"
		)
	end
	expectPositions(problems, "after the resync", d.state, everyoneAt(d, centre))
	expectTrack(
		problems,
		"dan's track after the resync",
		(d.state.tracks or {})[`dan`],
		centre,
		resyncAt,
		nil,
		3
	)
	expectTrack(
		problems,
		"ann's track after her first refusal",
		(d.state.tracks or {})[`ann`],
		centre,
		T,
		resyncAt,
		1
	)

	effects = sampleAt(d, { dan = centre }, resyncAt + 0.1)
	expectNoEffects(problems, "dan sampled at the placement after the resync", effects)
	expectTrack(
		problems,
		"dan's track after the sample at the placement",
		(d.state.tracks or {})[`dan`],
		centre,
		resyncAt + 0.1,
		nil,
		3
	)

	-- Two players past the threshold in one step: ascending playerId, not seat order.
	local both = startRound("AC-4", S, 105, { "dan", "cat", "bob", "ann" })
	local T2 = both.now
	local centre2 = centreOf(both)
	local away2 = plus(centre2, 0, 0, far)
	sampleAt(both, { dan = away2, ann = away2 }, T2 + 1)
	effects = sampleAt(both, { dan = away2, ann = away2 }, T2 + 1 + R + 0.5)
	local wantBoth = {
		{ kind = "Placed", playerId = "ann", position = centre2 },
		{ kind = "Placed", playerId = "dan", position = centre2 },
	}
	if not Deep.equal(effects, wantBoth) then
		table.insert(
			problems,
			`two players past RESYNC_SECONDS in one step emitted {Deep.show(effects)}, expected {Deep.show(
				wantBoth
			)} - ascending playerId, seat order was dan, cat, bob, ann`
		)
	end
	if #effects == 2 and rawequal(effects[1].position, effects[2].position) then
		table.insert(problems, "the two Placed effects share one position table")
	end

	-- Outside Round: the next Lobby keeps the tracks and never resyncs.
	local lobby = startRound("AC-4", S, 106)
	local T3 = lobby.now
	local centre3 = centreOf(lobby)
	local c = lobby.config
	ScriptedRound.tickAt(lobby, T3 + c.roundSeconds)
	ScriptedRound.tick(lobby, 1)
	ScriptedRound.tickAt(lobby, lobby.now + c.postRoundSeconds)
	if lobby.state.round.phase ~= "Lobby" then
		Contract.fail(
			`AC-4 precondition: after the round, Post and its timer the phase is {lobby.state.round.phase}, not Lobby`
		)
	end
	local L = lobby.now
	local who = lobby.state.round.players[1]
	local away3 = plus(centre3, far, 0, 0)
	-- A whole round has passed since the deal placed them, so any jump would
	-- be plausible from it: a sample at the kept centre first, so the run
	-- below is measured from now.
	effects = sampleAt(lobby, { [who] = centre3 }, L)
	expectNoEffects(problems, `{who} sampled at the kept centre in the next Lobby`, effects)
	expectTrack(
		problems,
		`{who}'s Lobby track after the centre sample`,
		(lobby.state.tracks or {})[who],
		centre3,
		L,
		nil,
		0
	)
	effects = sampleAt(lobby, { [who] = away3 }, L + 1)
	expectNoEffects(problems, `{who}'s first refused sample in the next Lobby`, effects)
	effects = sampleAt(lobby, { [who] = away3 }, L + 1 + R + 0.5)
	expectNoEffects(
		problems,
		`{who} refused for {R + 0.5} s in the next Lobby (no resync outside Round)`,
		effects
	)
	if not Deep.equal(lobby.state.positions[who], centre3) then
		table.insert(
			problems,
			`in the next Lobby state.positions[{who}] is {Deep.show(lobby.state.positions[who])}, expected the kept centre {Deep.show(
				centre3
			)}`
		)
	end
	expectTrack(
		problems,
		`{who}'s Lobby track after {R + 0.5} s of refusals`,
		(lobby.state.tracks or {})[who],
		centre3,
		L,
		L + 1,
		2
	)
	fewProblems(
		"AC-4",
		"in Round a run of refusals longer than RESYNC_SECONDS must place the player back at the last accepted position (one Placed per player, ascending, fresh, nothing else) and reset the baseline; exactly RESYNC_SECONDS or outside Round, nothing",
		problems
	)
end

--[[
	AC-5 in Session: the turner of T1[1], last accepted at the spawn centre
	(out of reach of every machine), sends an implausible sample AT the
	machine; a turn on it is refused out_of_reach and state.positions still
	holds the centre. The positive control: after walking there plausibly the
	same turn commits.
]]
function PositionsContract.implausibleSampleDoesNotReachATurn(S: Session, P: Positions)
	requireModule("AC-5", P)
	local w = PositionsContract.walkSpeed()
	local problems: { string } = {}
	local d = startRound("AC-5", S, 107)
	local T = d.now
	local centre = centreOf(d)
	local facility = d.state.facility
	local id = facility.steps.tracks[1][1]
	local m = ScriptedRound.machineOf(facility, id)
	local turner = ScriptedRound.turnerOf(d.state.assignment, m)
	local at = ScriptedRound.machinePosition(d, m)
	local distance = horizontal(centre, at)
	local range = d.tuning.instance.turn_range_studs
	local bound = PositionsContract.bound(P, w, 0.1)
	if distance <= range or distance <= bound then
		Contract.fail(
			`AC-5 precondition: machine {id} is {distance} studs from the spawn centre (turn range {range}, bound at 0.1 s {bound}); the fixture must be out of reach and implausible`
		)
	end

	local effects = sampleAt(d, { [turner] = at }, T + 0.1)
	expectNoEffects(problems, "the implausible sample at the machine", effects)
	if not Deep.equal(d.state.positions[turner], centre) then
		table.insert(
			problems,
			`after the implausible sample state.positions[{turner}] is {Deep.show(
				d.state.positions[turner]
			)}, expected the accepted centre {Deep.show(centre)}`
		)
	end
	d.now = T + 0.2
	local turn = ScriptedRound.turn(d, turner, id, m.requiredSetting)
	local r = turn.reply
	if not (typeof(r) == "table" and r.kind == "refused" and r.reason == "out_of_reach") then
		table.insert(
			problems,
			`{turner}'s turn on machine {id} after an implausible sample AT it replied {Deep.show(r)}, expected refused / out_of_reach (the turn rule must read the last ACCEPTED position)`
		)
	end

	local walked = startRound("AC-5", S, 107)
	ScriptedRound.walk(walked, { [turner] = at })
	ScriptedRound.tick(walked, 1)
	local control = ScriptedRound.turn(walked, turner, id, m.requiredSetting)
	local cr = control.reply
	if not (typeof(cr) == "table" and cr.kind == "committed") then
		table.insert(
			problems,
			`the positive control: after walking to machine {id} at walk speed ({walked.walkSeconds} s) the same turn replied {Deep.show(
				cr
			)}, expected committed`
		)
	end
	fewProblems(
		"AC-5",
		"a turn must be judged against the last accepted position: implausibly sampled at the machine it is out_of_reach, walked there it commits",
		problems
	)
end

--[[
	Contract: `tracks` is `{}` from `new`; the deal replaces it with exactly
	the dealt players, each placed at the centre at the deal's `now` with
	their refusal count carried from the previous round; a player who left is
	absent, a newcomer starts at 0; `positions` is exactly the centre for the
	dealt players.
]]
function PositionsContract.tracksFromNewAndTheDeal(S: Session, P: Positions)
	requireModule("Contract", P)
	requireSession("Contract", S)
	local problems: { string } = {}
	local fresh = S.new(ScriptedRound.config(), 108, "r", "s", ScriptedRound.PORTS)
	if not Deep.equal(fresh.tracks, {}) then
		table.insert(problems, `state.tracks is {Deep.show(fresh.tracks)} from new, expected \{}`)
	end
	local far = implausibleOffset("Contract", P, 2)
	local d = startRound("Contract", S, 108)
	local T = d.now
	local centre = centreOf(d)
	local seated = d.state.assignment.players
	if not Deep.equal(keysOf(d.state.tracks or {}), keysOf(everyoneAt(d, centre))) then
		table.insert(
			problems,
			`after the deal state.tracks has keys {Deep.show(keysOf(d.state.tracks or {}))}, expected exactly the dealt players {Deep.show(
				keysOf(everyoneAt(d, centre))
			)}`
		)
	end
	for _, p in seated do
		expectTrack(
			problems,
			`track of {p} after deal 1`,
			(d.state.tracks or {})[p],
			centre,
			T,
			nil,
			0
		)
	end
	-- Two refusals for the first seat, then a departure, a newcomer and deal 2.
	local jumper = seated[1]
	local leaver = seated[3]
	sampleAt(d, { [jumper] = plus(centre, far, 0, 0) }, T + 1)
	sampleAt(d, { [jumper] = plus(centre, far, 0, 0) }, T + 2)
	expectTrack(
		problems,
		`track of {jumper} after two refusals`,
		(d.state.tracks or {})[jumper],
		centre,
		T,
		T + 1,
		2
	)
	d.now = T + 3
	ScriptedRound.step(d, { kind = "PlayerLeft", playerId = leaver })
	local c = d.config
	ScriptedRound.tickAt(d, T + c.roundSeconds)
	ScriptedRound.tick(d, 1)
	ScriptedRound.tickAt(d, d.now + c.postRoundSeconds)
	if d.state.round.phase ~= "Lobby" then
		Contract.fail(`Contract precondition: the phase is {d.state.round.phase}, not Lobby`)
	end
	local newcomer = "eve"
	ScriptedRound.step(d, { kind = "PlayerJoined", playerId = newcomer })
	local L = d.now
	ScriptedRound.deal(d)
	local T2 = d.now
	if d.state.facility == nil then
		Contract.fail(
			`Contract precondition: deal 2 at {T2} (lobby entered {L}) produced no facility`
		)
	end
	local centre2 = centreOf(d)
	local want: { [string]: Vec } = {}
	for _, p in d.state.assignment.players do
		want[p] = vec(centre2.x, centre2.y, centre2.z)
	end
	expectPositions(problems, "after deal 2", d.state, want)
	if not Deep.equal(keysOf(d.state.tracks or {}), keysOf(want)) then
		table.insert(
			problems,
			`after deal 2 state.tracks has keys {Deep.show(keysOf(d.state.tracks or {}))}, expected exactly the dealt players {Deep.show(
				keysOf(want)
			)} ({leaver} left, {newcomer} joined)`
		)
	end
	for _, p in d.state.assignment.players do
		expectTrack(
			problems,
			`track of {p} after deal 2`,
			(d.state.tracks or {})[p],
			centre2,
			T2,
			nil,
			if p == jumper then 2 else 0
		)
	end
	fewProblems(
		"Contract",
		"tracks must be {} from new and, on a deal, exactly the dealt players placed at the centre with their refusal counts carried",
		problems
	)
end

--[[
	Contract: a sample MERGES - a batch naming one player moves that player
	(plausibly) and leaves every other accepted position and track as it was
	- and `state.positions` holds fresh copies, never the event's tables;
	neither the state nor the event is mutated.
]]
function PositionsContract.samplesMergeIntoFreshAcceptedCopies(S: Session, P: Positions)
	requireModule("Contract", P)
	local w = PositionsContract.walkSpeed()
	local problems: { string } = {}
	local d = startRound("Contract", S, 109)
	local T = d.now
	local centre = centreOf(d)
	local seated = d.state.assignment.players
	local mover = seated[2]
	local to = plus(centre, w * 0.5, 0, 0)
	local before = d.state
	local beforeSnapshot = Deep.copy(before)
	local event = { kind = "PositionsSampled", samples = { [mover] = to } }
	local eventSnapshot = Deep.copy(event)
	d.now = T + 0.5
	local effects = ScriptedRound.step(d, event)
	expectNoEffects(problems, "the one-player batch", effects)
	local want = everyoneAt(d, centre)
	want[mover] = vec(to.x, to.y, to.z)
	expectPositions(problems, "after a batch naming one player", d.state, want)
	if rawequal(d.state.positions[mover], event.samples[mover]) then
		table.insert(
			problems,
			`state.positions[{mover}] IS event.samples[{mover}] (the same table); the Contract wants a copy`
		)
	end
	for _, p in seated do
		if p ~= mover then
			expectTrack(
				problems,
				`track of {p}, absent from the batch`,
				(d.state.tracks or {})[p],
				centre,
				T,
				nil,
				0
			)
		end
	end
	expectTrack(problems, `track of {mover}`, (d.state.tracks or {})[mover], to, T + 0.5, nil, 0)
	if not Deep.equal(before, beforeSnapshot) then
		table.insert(
			problems,
			`step mutated its state argument:\n{Contract.firstFew(
				string.split(Deep.diff(beforeSnapshot, before), "\n"),
				4
			)}`
		)
	end
	if not Deep.equal(event, eventSnapshot) then
		table.insert(
			problems,
			`step mutated its event argument:\n{Deep.diff(eventSnapshot, event)}`
		)
	end
	fewProblems(
		"Contract",
		"a sample must merge into the accepted positions as fresh copies, leaving players absent from the batch untouched and mutating nothing",
		problems
	)
end

--[[
	Contract: the walk speed is `state.tuning.instance.walk_speed_studs_per_second`,
	not the shipped module's. Under a tuning ten times faster a jump just past
	the shipped bound is accepted; under the shipped tuning it is refused.
]]
function PositionsContract.walkSpeedIsReadFromTheSessionsTuning(S: Session, P: Positions)
	requireModule("Contract", P)
	local w = PositionsContract.walkSpeed()
	local problems: { string } = {}
	local fast = Deep.copy(MechanicsTuning)
	fast.instance.walk_speed_studs_per_second = w * 10
	local jump = PositionsContract.bound(P, w, 1) + w
	if jump > PositionsContract.bound(P, w * 10, 1) then
		Contract.fail("Contract precondition: the jump is outside the fast bound too")
	end

	local quick = startRound("Contract", S, 110, nil, { tuning = fast })
	local T = quick.now
	local centre = centreOf(quick)
	local who = quick.state.assignment.players[1]
	local to = plus(centre, jump, 0, 0)
	sampleAt(quick, { [who] = to }, T + 1)
	if not Deep.equal(quick.state.positions[who], to) then
		table.insert(
			problems,
			`under a tuning with walk speed {w * 10}, a {jump}-stud move in 1 s was not accepted: state.positions[{who}] is {Deep.show(
				quick.state.positions[who]
			)}`
		)
	end

	local shipped = startRound("Contract", S, 110)
	local T2 = shipped.now
	local centre2 = centreOf(shipped)
	local who2 = shipped.state.assignment.players[1]
	sampleAt(shipped, { [who2] = plus(centre2, jump, 0, 0) }, T2 + 1)
	if not Deep.equal(shipped.state.positions[who2], centre2) then
		table.insert(
			problems,
			`the control: under the shipped tuning (walk speed {w}) the same {jump}-stud move in 1 s was accepted`
		)
	end
	fewProblems(
		"Contract",
		"the walk speed must be read from state.tuning, not from the shipped MechanicsTuning",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     The batteries, named.
     --------------------------------------------------------------------- ]]

export type ModuleCheck = { name: string, ac: string, run: (Positions) -> () }
export type SessionCheck = { name: string, ac: string, run: (Session, Positions) -> () }

PositionsContract.MODULE_CHECKS = {
	{
		name = "exportsTheContractShape",
		ac = "Contract",
		run = PositionsContract.exportsTheContractShape,
	},
	{
		name = "settledControlsRefuse200AndAccept1_5",
		ac = "AC-1",
		run = PositionsContract.settledControlsRefuse200AndAccept1_5,
	},
	{ name = "boundIsInclusive", ac = "AC-1", run = PositionsContract.boundIsInclusive },
	{ name = "yIsIgnored", ac = "AC-1", run = PositionsContract.yIsIgnored },
	{
		name = "dtIsMeasuredFromTheLastAcceptedSample",
		ac = "AC-1",
		run = PositionsContract.dtIsMeasuredFromTheLastAcceptedSample,
	},
	{
		name = "nowBeforeAcceptedAtClampsDtToZero",
		ac = "AC-1",
		run = PositionsContract.nowBeforeAcceptedAtClampsDtToZero,
	},
	{
		name = "placedResetsTheBaseline",
		ac = "AC-2",
		run = PositionsContract.placedResetsTheBaseline,
	},
	{
		name = "noBaselineMeansNoAcceptanceAndNoRefusal",
		ac = "AC-3",
		run = PositionsContract.noBaselineMeansNoAcceptanceAndNoRefusal,
	},
	{
		name = "needsResyncIsStrictlyAfterResyncSeconds",
		ac = "AC-4",
		run = PositionsContract.needsResyncIsStrictlyAfterResyncSeconds,
	},
	{
		name = "isPureAndReturnsFreshTables",
		ac = "Contract",
		run = PositionsContract.isPureAndReturnsFreshTables,
	},
} :: { ModuleCheck }

PositionsContract.SESSION_CHECKS = {
	{
		name = "dealPlacementIsTheBaseline",
		ac = "AC-2",
		run = PositionsContract.dealPlacementIsTheBaseline,
	},
	{
		name = "unplacedPlayerIsAbsentAndOutOfReach",
		ac = "AC-3",
		run = PositionsContract.unplacedPlayerIsAbsentAndOutOfReach,
	},
	{
		name = "resyncPlacesBackInRoundOnly",
		ac = "AC-4",
		run = PositionsContract.resyncPlacesBackInRoundOnly,
	},
	{
		name = "implausibleSampleDoesNotReachATurn",
		ac = "AC-5",
		run = PositionsContract.implausibleSampleDoesNotReachATurn,
	},
	{
		name = "tracksFromNewAndTheDeal",
		ac = "Contract",
		run = PositionsContract.tracksFromNewAndTheDeal,
	},
	{
		name = "samplesMergeIntoFreshAcceptedCopies",
		ac = "Contract",
		run = PositionsContract.samplesMergeIntoFreshAcceptedCopies,
	},
	{
		name = "walkSpeedIsReadFromTheSessionsTuning",
		ac = "Contract",
		run = PositionsContract.walkSpeedIsReadFromTheSessionsTuning,
	},
} :: { SessionCheck }

function PositionsContract.moduleFailures(P: Positions): { { name: string, message: string } }
	local out: { { name: string, message: string } } = {}
	for _, check in PositionsContract.MODULE_CHECKS do
		local ok, err = pcall(check.run, P)
		if not ok then
			table.insert(out, { name = check.name, message = tostring(err) })
		end
	end
	return out
end

function PositionsContract.sessionFailures(
	S: Session,
	P: Positions
): { { name: string, message: string } }
	local out: { { name: string, message: string } } = {}
	for _, check in PositionsContract.SESSION_CHECKS do
		local ok, err = pcall(check.run, S, P)
		if not ok then
			table.insert(out, { name = check.name, message = tostring(err) })
		end
	end
	return out
end

return PositionsContract
