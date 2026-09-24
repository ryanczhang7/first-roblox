--!strict
--[[
	TEL-002 AC-1 to AC-9 written once, as checks over a MACHINE rather than over
	a module - the same arrangement as `RoundEndingContract.luau`, and for the
	same reason.

	`tests/server/telemetry_emit_test.luau` applies these to the real
	`src/server/round/PhaseMachine.luau`.
	`tests/server/telemetry_emit_controls_test.luau` applies them to the
	deliberately wrong machines in `TelemetryEmitStubs.luau`, so that every
	control the story names - a machine that bounces on every `PlayerLeft`, one
	with no `departed` guard, one reading a real clock, one emitting `join` on
	every `PlayerJoined`, one emitting `first_round_complete` for everybody -
	has been OBSERVED failing the check it is aimed at, in RED, against a
	machine that emits nothing and so passes every "at most once" half
	vacuously. A check nobody has seen refuse anything is not a check.

	THE CENTRAL RISK IS EXACTLY-ONCE, so every mechanical check below asserts
	the WHOLE list of `Emit` effects a step produced - never "the list contains
	a join" - and the lifecycle checks count. A double emission is invisible to
	a membership test and visible to nothing else.

	THE ORACLE PARTITION (the story's Contract §6) IS HONOURED HERE:

	  * AC-1, AC-2, AC-3, AC-7, AC-8 are MECHANICAL and pinned exactly against
	    Contract §3's table - event name, bucket, playerId, sessionId, fields -
	    and §3 P5's effect-order table.
	  * AC-4, AC-5, AC-6 are SETTLED WITH A CONTROL. "Bounce" is A5's and the
	    Contract's: a seated player leaving in Lobby, Assignment or Round, once
	    per departure. Nothing here redefines it.
	  * AC-9 is MECHANICAL WITH A CONTROL: `at` is the `now` of the step, driven
	    by a manual clock through non-integer values no real clock produces.

	`at` IS AC-9's AND NOBODY ELSE's. The shape every other check compares
	(`Contract.shape`) drops `at`, so a machine stamping events from a real
	clock fails AC-9 and only AC-9 - which is what makes AC-9's control
	attributable, and what makes AC-9 the check that reads `at` for every one
	of the six emitters over a whole lifecycle.

	Every message names its criterion, because the controls assert on the text.
	Messages are kept under about 480 characters: Luau truncates an `assert`
	message at roughly 500, position prefix included (measured in ROUND-004's
	RED). Hence the compact `name<player>{k=v}` rendering and "first difference
	at index N" rather than two whole lists.
]]

local Clock = require("../../src/shared/Clock")
local Event = require("../../src/shared/telemetry/Event")
local Contract = require("./PhaseMachineContract")
local Deep = require("./Deep")

local TelemetryEmitContract = {}

TelemetryEmitContract.SEED = 20260924
TelemetryEmitContract.ROUND_ID = "round-TEL-002-a"
TelemetryEmitContract.SESSION_ID = "session-TEL-002-a"

-- The six names this story emits. The other three B6 names are M5's.
TelemetryEmitContract.EMITTED_NAMES = {
	"join",
	"bounce_before_resolution",
	"session_end",
	"round_complete",
	"first_round_complete",
	"rematch_accepted",
}

--[[ Event constructors. ]]

function TelemetryEmitContract.joined(playerId: string): any
	return { kind = "PlayerJoined", playerId = playerId }
end

function TelemetryEmitContract.left(playerId: string): any
	return { kind = "PlayerLeft", playerId = playerId }
end

function TelemetryEmitContract.tick(): any
	return { kind = "Tick" }
end

function TelemetryEmitContract.seatsAssigned(): any
	return { kind = "SeatsAssigned" }
end

function TelemetryEmitContract.resolved(outcome: any): any
	return { kind = "RoundResolved", outcome = outcome }
end

function TelemetryEmitContract.rematch(playerId: string): any
	return { kind = "RematchAccepted", playerId = playerId }
end

--[[
	The outcome a `RoundResolved` carries here: `won`, which neither the clock
	(`lost`) nor quorum (`no_contest`) can produce, and a reason no machine would
	invent. `round_complete` must carry both back verbatim.
]]
function TelemetryEmitContract.eventOutcome(): any
	return { result = "won", reason = "reason-t3l2-carried-by-the-event-not-invented-here" }
end

--[[ Extracting and rendering telemetry. ]]

-- The events carried by the `Emit` effects of a step, in order.
function TelemetryEmitContract.emitted(effects: { any }): { any }
	local out: { any } = {}
	for _, effect in effects do
		if typeof(effect) == "table" and effect.kind == "Emit" then
			table.insert(out, effect.event)
		end
	end
	return out
end

--[[
	An event WITHOUT its `at`, for the mechanical checks. See the header: `at`
	is AC-9's alone, so that a real-clock machine fails exactly one check.
]]
function TelemetryEmitContract.shape(event: any): any
	if typeof(event) ~= "table" then
		return { malformed = Deep.show(event) }
	end
	return {
		name = event.name,
		bucket = event.bucket,
		playerId = event.playerId,
		sessionId = event.sessionId,
		fields = event.fields,
	}
end

function TelemetryEmitContract.shapes(effects: { any }): { any }
	local out: { any } = {}
	for _, event in TelemetryEmitContract.emitted(effects) do
		table.insert(out, TelemetryEmitContract.shape(event))
	end
	return out
end

--[[
	The shape Contract §3 says a step emits. The bucket is written by the
	CALLER, out of the criterion's own words ("bucket D1"), not read from
	`Event.BUCKETS` - a check that read the bucket from the module under test
	would agree with any bucket the module chose.
]]
function TelemetryEmitContract.expect(
	name: string,
	bucket: string,
	playerId: string?,
	fields: any
): any
	return {
		name = name,
		bucket = bucket,
		playerId = playerId,
		sessionId = TelemetryEmitContract.SESSION_ID,
		fields = fields,
	}
end

local function showFields(fields: any): string
	if typeof(fields) ~= "table" then
		return tostring(fields)
	end
	local keys: { string } = {}
	for key in pairs(fields :: { [string]: any }) do
		table.insert(keys, tostring(key))
	end
	table.sort(keys)
	local parts: { string } = {}
	for _, key in keys do
		table.insert(parts, `{key}={tostring((fields :: any)[key])}`)
	end
	return `\{{table.concat(parts, ",")}}`
end

-- `join<p1>{}`; `bounce_before_resolution<p5>{phase=Lobby}`; `round_complete<->{...}`.
function TelemetryEmitContract.describeOne(shape: any): string
	if typeof(shape) ~= "table" then
		return tostring(shape)
	end
	local who = if shape.playerId == nil then "-" else tostring(shape.playerId)
	return `{tostring(shape.name)}<{who}>{showFields(shape.fields)}`
end

function TelemetryEmitContract.describe(shapes: { any }): string
	local parts: { string } = {}
	for _, shape in shapes do
		table.insert(parts, TelemetryEmitContract.describeOne(shape))
	end
	return `[{table.concat(parts, ", ")}]`
end

--[[
	THE assertion of this file: the WHOLE list of telemetry a step produced
	equals the whole list the Contract says, in order.

	Length first, then the first index that differs with a field-level diff,
	because two 30-item lists rendered side by side are truncated at 500
	characters and a truncated message takes the evidence with it.
]]
function TelemetryEmitContract.assertEmits(
	criterion: string,
	label: string,
	effects: { any },
	expected: { any }
)
	local actual = TelemetryEmitContract.shapes(effects)
	local firstDifference: number? = nil
	for index = 1, math.max(#actual, #expected) do
		if not Deep.equal(expected[index], actual[index]) then
			firstDifference = index
			break
		end
	end
	if firstDifference == nil then
		return
	end
	local index = firstDifference :: number
	assert(
		false,
		`{criterion}: {label} emitted {#actual} telemetry event(s), wanted {#expected}. `
			.. `First difference at index {index}: got `
			.. `{TelemetryEmitContract.describeOne(actual[index])}, wanted `
			.. `{TelemetryEmitContract.describeOne(expected[index])}. Whole list: `
			.. `{TelemetryEmitContract.describe(actual)}`
	)
end

-- How many emitted events are named `name` (and, if given, name `playerId`).
function TelemetryEmitContract.count(effects: { any }, name: string, playerId: string?): number
	local seen = 0
	for _, event in TelemetryEmitContract.emitted(effects) do
		if typeof(event) == "table" and event.name == name then
			if playerId == nil or event.playerId == playerId then
				seen += 1
			end
		end
	end
	return seen
end

--[[
	A SESSION: one machine, one state, driven step by step, with every step's
	`now`, event and effects logged so a check can count over the whole run.

	`all()` returns every effect the session has produced in order, which is
	what the "exactly once per session" assertions count over.
]]
function TelemetryEmitContract.session(machine: any, config: any): any
	local s: any = {}
	s.machine = machine
	s.config = config
	s.state = machine.initial(
		config,
		TelemetryEmitContract.SEED,
		TelemetryEmitContract.ROUND_ID,
		TelemetryEmitContract.SESSION_ID
	)
	s.log = {}
	s.last = 0

	function s.apply(event: any, now: number): { any }
		local after, effects = machine.step(s.state, event, now)
		assert(
			typeof(effects) == "table",
			`fixture: step returned {typeof(effects)} for its effect list at now = {now}`
		)
		table.insert(s.log, { now = now, event = event, effects = effects })
		s.state = after
		s.last = now
		return effects
	end

	function s.all(): { any }
		local out: { any } = {}
		for _, entry in s.log do
			for _, effect in entry.effects do
				table.insert(out, effect)
			end
		end
		return out
	end

	return s
end

-- Every `now` below is a dyadic fraction, so `==` on it is exact.
local STEP = 0.125

--[[
	A Lobby with p1..pN seated, entered at 0, built by DRIVING the machine. The
	join effects are returned per player so AC-1 can assert them; other checks
	ignore them.
]]
function TelemetryEmitContract.lobbyOf(machine: any, config: any, count: number): any
	assert(
		count >= config.playersMin and count <= config.playersMax,
		`fixture: a round of {count} cannot be started - playersMin is {config.playersMin} and `
			.. `playersMax is {config.playersMax}`
	)
	local s = TelemetryEmitContract.session(machine, config)
	for index = 1, count do
		s.apply(TelemetryEmitContract.joined(`p{index}`), s.last + STEP)
	end
	assert(
		#s.state.players == count,
		`fixture: seating {count} player(s) produced {Deep.show(s.state.players)}`
	)
	return s
end

-- Lobby -> Assignment (the Tick past lobbySeconds). Returns that step's effects.
function TelemetryEmitContract.toAssignment(s: any): { any }
	local due = math.max(s.last, s.state.phaseEnteredAt + s.config.lobbySeconds) + STEP
	local effects = s.apply(TelemetryEmitContract.tick(), due)
	assert(
		s.state.phase == "Assignment",
		`fixture: a Tick at now = {due} on a Lobby of {#s.state.players} entered at `
			.. `{s.state.phaseEnteredAt} left the machine in {tostring(s.state.phase)}, not `
			.. `Assignment (ROUND-003 AC-1, ROUND-004 AC-2)`
	)
	return effects
end

-- Assignment -> Round. Returns that step's effects.
function TelemetryEmitContract.toRound(s: any): { any }
	local effects = s.apply(TelemetryEmitContract.seatsAssigned(), s.last + STEP)
	assert(
		s.state.phase == "Round",
		`fixture: SeatsAssigned left the machine in {tostring(s.state.phase)}, not Round`
	)
	return effects
end

-- Round -> Resolution by a `RoundResolved`. Returns that step's effects.
function TelemetryEmitContract.resolveByEvent(s: any, criterion: string): { any }
	local effects =
		s.apply(TelemetryEmitContract.resolved(TelemetryEmitContract.eventOutcome()), s.last + STEP)
	assert(
		s.state.phase == "Resolution",
		`{criterion}: a RoundResolved left the machine in {tostring(s.state.phase)}, not `
			.. `Resolution (ROUND-003 AC-3)`
	)
	return effects
end

-- Resolution -> Post. Returns that step's effects.
function TelemetryEmitContract.toPost(s: any): { any }
	local effects = s.apply(TelemetryEmitContract.tick(), s.last + STEP)
	assert(
		s.state.phase == "Post",
		`fixture: the Tick after Resolution left the machine in {tostring(s.state.phase)}, not Post`
	)
	return effects
end

-- Post -> Lobby (the Tick past postRoundSeconds). Returns that step's effects.
function TelemetryEmitContract.toLobby(s: any): { any }
	local due = math.max(s.last, s.state.phaseEnteredAt + s.config.postRoundSeconds) + STEP
	local effects = s.apply(TelemetryEmitContract.tick(), due)
	assert(
		s.state.phase == "Lobby",
		`fixture: a Tick at now = {due} on a Post entered at {s.state.phaseEnteredAt} left the `
			.. `machine in {tostring(s.state.phase)}, not Lobby (ROUND-003 AC-5)`
	)
	return effects
end

-- A Round of `playersMin` players, entered by driving the machine.
function TelemetryEmitContract.roundOf(machine: any, config: any, count: number): any
	local s = TelemetryEmitContract.lobbyOf(machine, config, count)
	TelemetryEmitContract.toAssignment(s)
	TelemetryEmitContract.toRound(s)
	return s
end

local E = TelemetryEmitContract.expect
local ROUND_ID = TelemetryEmitContract.ROUND_ID

local function frc(playerId: string): any
	return E("first_round_complete", "D1", playerId, { roundId = ROUND_ID, scope = "session" })
end

local function roundComplete(result: string, reason: string): any
	return E(
		"round_complete",
		"D2_7",
		nil,
		{ roundId = ROUND_ID, result = result, reason = reason }
	)
end

local function bounce(playerId: string, phase: string): any
	return E("bounce_before_resolution", "D1", playerId, { phase = phase })
end

local function sessionEnd(playerId: string, phase: string): any
	return E("session_end", "D1", playerId, { phase = phase })
end

local function join(playerId: string): any
	return E("join", "D1", playerId, {})
end

--[[
	Contract §1/§2: `initial` takes the driver's session id as its 4th argument
	and every state carries it unchanged, `Post -> Lobby` included.
]]
function TelemetryEmitContract.initialCarriesTheSessionId(machine: any, config: any)
	local s = TelemetryEmitContract.session(machine, config)
	assert(
		s.state.sessionId == TelemetryEmitContract.SESSION_ID,
		`Contract §2: initial(config, seed, roundId, "{TelemetryEmitContract.SESSION_ID}") produced `
			.. `a state whose sessionId is {Deep.show(s.state.sessionId)}. The driver generates it `
			.. `and the machine carries it; it is the sessionId of every event this state emits`
	)

	local run = TelemetryEmitContract.roundOf(machine, config, config.playersMin)
	TelemetryEmitContract.resolveByEvent(run, "Contract §2")
	TelemetryEmitContract.toPost(run)
	TelemetryEmitContract.toLobby(run)
	assert(
		run.state.sessionId == TelemetryEmitContract.SESSION_ID,
		`Contract §2: after a whole round and Post -> Lobby the sessionId is `
			.. `{Deep.show(run.state.sessionId)}, wanted "{TelemetryEmitContract.SESSION_ID}". It `
			.. `identifies the server instance's run, not a round, and is carried across every `
			.. `transition`
	)
end

--[[
	AC-1: an accepted `PlayerJoined` emits exactly one `join`, bucket D1,
	carrying that player's id; a duplicate emits no second one.

	Whole lists per step. The three ways a join is refused (duplicate, over
	`playersMax`, outside the Lobby) each emit NOTHING, and - Contract §3 - a
	player who leaves the Lobby and rejoins it emits no second `join`: "once
	per player per session", guarded by `roundsSeated[p] == nil`.
]]
function TelemetryEmitContract.joinIsEmittedOncePerPlayerPerSession(machine: any, config: any)
	local s = TelemetryEmitContract.session(machine, config)

	local first = s.apply(TelemetryEmitContract.joined("p1"), STEP)
	TelemetryEmitContract.assertEmits("AC-1", "p1's first PlayerJoined", first, { join("p1") })

	local second = s.apply(TelemetryEmitContract.joined("p2"), 2 * STEP)
	TelemetryEmitContract.assertEmits("AC-1", "p2's first PlayerJoined", second, { join("p2") })

	local duplicate = s.apply(TelemetryEmitContract.joined("p1"), 3 * STEP)
	TelemetryEmitContract.assertEmits(
		"AC-1",
		"a duplicate PlayerJoined for p1, already seated",
		duplicate,
		{}
	)

	-- Leave the Lobby and come back: still one join for the session (Contract
	-- §3, "player per session"; P2a clears `departed`, not `roundsSeated`).
	s.apply(TelemetryEmitContract.left("p1"), 4 * STEP)
	local rejoin = s.apply(TelemetryEmitContract.joined("p1"), 5 * STEP)
	TelemetryEmitContract.assertEmits(
		"AC-1",
		"p1 rejoining the Lobby after leaving it (no second join in a session)",
		rejoin,
		{}
	)

	for index = 3, config.playersMax do
		s.apply(TelemetryEmitContract.joined(`p{index}`), (3 + index) * STEP)
	end
	assert(
		#s.state.players == config.playersMax,
		`fixture: the lobby holds {Deep.show(s.state.players)}, wanted playersMax `
			.. `({config.playersMax}) seated before the surplus join`
	)
	local surplus = `p{config.playersMax + 1}`
	local refused = s.apply(TelemetryEmitContract.joined(surplus), (5 + config.playersMax) * STEP)
	TelemetryEmitContract.assertEmits(
		"AC-1",
		`{surplus} joining a lobby already holding playersMax ({config.playersMax}) - refused`,
		refused,
		{}
	)

	TelemetryEmitContract.toAssignment(s)
	local outsideLobby = s.apply(TelemetryEmitContract.joined("p9"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-1",
		"a PlayerJoined in Assignment - refused",
		outsideLobby,
		{}
	)

	assert(
		TelemetryEmitContract.count(s.all(), "join", "p1") == 1,
		`AC-1: over the whole session p1 produced `
			.. `{TelemetryEmitContract.count(s.all(), "join", "p1")} join event(s), wanted exactly 1`
	)
	assert(
		TelemetryEmitContract.count(s.all(), "join") == config.playersMax,
		`AC-1: {config.playersMax} distinct players were seated and the session produced `
			.. `{TelemetryEmitContract.count(s.all(), "join")} join event(s)`
	)
end

--[[
	AC-2: the step that ENTERS `Resolution` - by any of the three paths - emits
	exactly one `round_complete`, bucket D2_7, carrying the outcome's `result`
	and `reason` and the round id. And no later step emits another.

	Whole lists, in Contract §3 P5's order: [the leaver's bounce, if this is a
	quorum-ending PlayerLeft], `round_complete`, then `first_round_complete` for
	every seated first-rounder in seat order. In a first round everybody seated
	is a first-rounder, so the FRC tail here is the same for a machine that
	emits it for everyone - AC-7 is where that machine is told apart.
]]
function TelemetryEmitContract.roundCompleteIsEmittedOnceOnEnteringResolution(
	machine: any,
	config: any
)
	local count = config.playersMin
	local roster: { string } = {}
	for index = 1, count do
		table.insert(roster, `p{index}`)
	end

	-- Path 1: RoundResolved.
	local byEvent = TelemetryEmitContract.roundOf(machine, config, count)
	local eventEffects = TelemetryEmitContract.resolveByEvent(byEvent, "AC-2")
	local carried = TelemetryEmitContract.eventOutcome()
	local expectedByEvent: { any } = { roundComplete(carried.result, carried.reason) }
	for _, id in roster do
		table.insert(expectedByEvent, frc(id))
	end
	TelemetryEmitContract.assertEmits(
		"AC-2",
		"the RoundResolved that entered Resolution",
		eventEffects,
		expectedByEvent
	)

	-- Path 2: the clock.
	local byClock = TelemetryEmitContract.roundOf(machine, config, count)
	local due = byClock.state.phaseEnteredAt + config.roundSeconds
	local clockEffects = byClock.apply(TelemetryEmitContract.tick(), due)
	assert(
		byClock.state.phase == "Resolution",
		`AC-2: a Tick at now = {due}, exactly roundSeconds ({config.roundSeconds}) after the Round `
			.. `was entered, left the machine in {tostring(byClock.state.phase)} (ROUND-005 AC-1)`
	)
	local expectedByClock: { any } = { roundComplete("lost", "clock") }
	for _, id in roster do
		table.insert(expectedByClock, frc(id))
	end
	TelemetryEmitContract.assertEmits(
		"AC-2",
		"the Tick that entered Resolution on the clock",
		clockEffects,
		expectedByClock
	)

	-- Path 3: quorum, on the PlayerLeft that crossed the threshold.
	local leaves = config.playersMin - config.minPlayersToContinue + 1
	assert(
		leaves >= 1 and leaves < config.roundSeconds,
		`fixture: {leaves} departure(s) cannot take a round of {config.playersMin} below `
			.. `minPlayersToContinue ({config.minPlayersToContinue}) before the clock is due`
	)
	local byQuorum = TelemetryEmitContract.roundOf(machine, config, count)
	local quorumEffects: { any } = {}
	local leaver = ""
	for index = 1, leaves do
		leaver = `p{index + 1}`
		quorumEffects = byQuorum.apply(TelemetryEmitContract.left(leaver), byQuorum.last + STEP)
	end
	assert(
		byQuorum.state.phase == "Resolution",
		`AC-2: {leaves} departure(s) took the count below minPlayersToContinue `
			.. `({config.minPlayersToContinue}) and the machine is in {tostring(
				byQuorum.state.phase
			)} `
			.. `(ROUND-005 AC-2)`
	)
	local expectedByQuorum: { any } = {
		bounce(leaver, "Round"),
		roundComplete("no_contest", "below_quorum"),
	}
	for _, id in byQuorum.state.players do
		table.insert(expectedByQuorum, frc(id))
	end
	TelemetryEmitContract.assertEmits(
		"AC-2",
		`the PlayerLeft ({leaver}) that entered Resolution below quorum`,
		quorumEffects,
		expectedByQuorum
	)

	-- Exactly once: the steps from Resolution through Post and back to Lobby add
	-- no second round_complete.
	for _, run in { byEvent, byClock, byQuorum } do
		local postEffects = TelemetryEmitContract.toPost(run)
		TelemetryEmitContract.assertEmits("AC-2", "the Tick Resolution -> Post", postEffects, {})
		local lobbyEffects = TelemetryEmitContract.toLobby(run)
		TelemetryEmitContract.assertEmits("AC-2", "the Tick Post -> Lobby", lobbyEffects, {})
		local total = TelemetryEmitContract.count(run.all(), "round_complete")
		assert(
			total == 1,
			`AC-2: one round, from Lobby back to Lobby, produced {total} round_complete event(s); `
				.. `exactly one, on the step that entered Resolution`
		)
	end
end

--[[
	AC-3: a `no_contest` round's `round_complete` carries `result = "no_contest"`
	and is distinguishable from a loss by that field ALONE.

	The clock ending is driven too, because that is the difference the criterion
	is about: a lobby collapse counted as a played-and-lost round misreports
	retention AND, under amendment 9, the group's record.
]]
function TelemetryEmitContract.noContestIsDistinguishableFromALoss(machine: any, config: any)
	local leaves = config.playersMin - config.minPlayersToContinue + 1
	local byQuorum = TelemetryEmitContract.roundOf(machine, config, config.playersMin)
	local quorumEffects: { any } = {}
	for index = 1, leaves do
		quorumEffects =
			byQuorum.apply(TelemetryEmitContract.left(`p{index + 1}`), byQuorum.last + STEP)
	end
	local quorumEvents = TelemetryEmitContract.emitted(quorumEffects)
	local quorum: any = nil
	for _, event in quorumEvents do
		if event.name == "round_complete" then
			quorum = event
		end
	end
	assert(
		quorum ~= nil,
		`AC-3: the quorum ending emitted no round_complete at all: `
			.. `{TelemetryEmitContract.describe(TelemetryEmitContract.shapes(quorumEffects))}`
	)
	assert(
		quorum.fields.result ~= "lost",
		`AC-3: the round ended because the lobby fell below minPlayersToContinue and round_complete `
			.. `carries result "lost". The group did not fail, the lobby did (mechanics.md §8); a `
			.. `no_contest counted as a loss misreports retention and the group's record`
	)
	assert(
		quorum.fields.result == "no_contest" and quorum.fields.reason == "below_quorum",
		`AC-3: the quorum ending's round_complete carries result `
			.. `{Deep.show(quorum.fields.result)}, reason {Deep.show(quorum.fields.reason)}; wanted `
			.. `"no_contest" / "below_quorum"`
	)

	local byClock = TelemetryEmitContract.roundOf(machine, config, config.playersMin)
	local clockEffects = byClock.apply(
		TelemetryEmitContract.tick(),
		byClock.state.phaseEnteredAt + config.roundSeconds
	)
	local clock: any = nil
	for _, event in TelemetryEmitContract.emitted(clockEffects) do
		if event.name == "round_complete" then
			clock = event
		end
	end
	assert(
		clock ~= nil and clock.fields.result == "lost",
		`AC-3: the CLOCK ending's round_complete is `
			.. `{if clock == nil
				then "absent"
				else TelemetryEmitContract.describeOne(TelemetryEmitContract.shape(clock))}, `
			.. `wanted result "lost". If both endings carry the same result there is nothing to tell apart`
	)
	assert(
		quorum.fields.result ~= clock.fields.result,
		`AC-3: the quorum ending and the clock ending both carry result `
			.. `{Deep.show(quorum.fields.result)}; the result field alone must distinguish them`
	)
end

--[[
	AC-4: a SEATED player leaving in Lobby, Assignment or Round emits exactly
	one `bounce_before_resolution`, bucket D1, carrying the phase they left in.

	P1 pins the gate: a `PlayerLeft` naming somebody not seated - including a
	player the lobby REFUSED - emits nothing. P3: the Assignment leaver stays
	seated, and that is not this story's to change.
]]
function TelemetryEmitContract.bounceIsEmittedOnceForALeaverBeforeResolution(
	machine: any,
	config: any
)
	local s = TelemetryEmitContract.lobbyOf(machine, config, config.playersMax)
	local surplus = `p{config.playersMax + 1}`
	s.apply(TelemetryEmitContract.joined(surplus), s.last + STEP)

	local refusedLeaving = s.apply(TelemetryEmitContract.left(surplus), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-4",
		`{surplus}, whose join the full lobby refused, leaving (P1: never joined, never bounces)`,
		refusedLeaving,
		{}
	)

	local lobbyLeaver = `p{config.playersMax}`
	local inLobby = s.apply(TelemetryEmitContract.left(lobbyLeaver), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-4",
		`{lobbyLeaver} leaving in Lobby`,
		inLobby,
		{ bounce(lobbyLeaver, "Lobby") }
	)

	TelemetryEmitContract.toAssignment(s)
	local seatedBefore = #s.state.players
	local assignmentLeaver = `p{config.playersMax - 1}`
	local inAssignment = s.apply(TelemetryEmitContract.left(assignmentLeaver), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-4",
		`{assignmentLeaver} leaving in Assignment`,
		inAssignment,
		{ bounce(assignmentLeaver, "Assignment") }
	)
	assert(
		#s.state.players == seatedBefore,
		`AC-4 (P3): a departure in Assignment changed the seated list to `
			.. `{Deep.show(s.state.players)}; only Lobby and Round unseat (ROUND-004 pin 2), and `
			.. `that is not this story's to change`
	)

	TelemetryEmitContract.toRound(s)
	local roundLeaver = `p{config.playersMax - 2}`
	local inRound = s.apply(TelemetryEmitContract.left(roundLeaver), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-4",
		`{roundLeaver} leaving in Round`,
		inRound,
		{ bounce(roundLeaver, "Round") }
	)
	assert(
		s.state.phase == "Round",
		`fixture: the Round of {seatedBefore} ended on {roundLeaver}'s departure; AC-4 needs the `
			.. `round to continue so the bounce is the only event on the step`
	)

	local notSeated = s.apply(TelemetryEmitContract.left("never-seated-p99"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-4",
		"a PlayerLeft naming never-seated-p99, in Round (P1)",
		notSeated,
		{}
	)

	for _, who in { lobbyLeaver, assignmentLeaver, roundLeaver } do
		local total = TelemetryEmitContract.count(s.all(), "bounce_before_resolution", who)
		assert(
			total == 1,
			`AC-4: {who} left once before resolution and the session produced {total} `
				.. `bounce_before_resolution event(s) for them, wanted exactly 1`
		)
	end
end

--[[
	AC-5: a player leaving while the phase is `Resolution` or `Post` emits NO
	`bounce_before_resolution`.

	The control named in the criterion is the implementation that ships if
	nobody writes it: bounce on every `PlayerLeft`. Over-reporting a bounce is
	self-harm under A5, so this is asserted as a COUNT of zero over the whole
	post-resolution sequence, not as the absence of one event on one step.
	What those departures DO emit (`session_end`) is AC-8's.
]]
function TelemetryEmitContract.noBounceIsEmittedInResolutionOrPost(machine: any, config: any)
	local s = TelemetryEmitContract.roundOf(machine, config, config.playersMin)
	TelemetryEmitContract.resolveByEvent(s, "AC-5")
	local before = #s.log

	local inResolution = s.apply(TelemetryEmitContract.left("p1"), s.last + STEP)
	assert(
		TelemetryEmitContract.count(inResolution, "bounce_before_resolution") == 0,
		`AC-5: p1 left in Resolution and the step emitted `
			.. `{TelemetryEmitContract.describe(TelemetryEmitContract.shapes(inResolution))}. A player `
			.. `leaving AFTER the round resolved did not bounce; emitting `
			.. `bounce_before_resolution here over-reports A5's ranking penalty against ourselves`
	)

	TelemetryEmitContract.toPost(s)
	local inPost = s.apply(TelemetryEmitContract.left("p2"), s.last + STEP)
	assert(
		TelemetryEmitContract.count(inPost, "bounce_before_resolution") == 0,
		`AC-5: p2 left in Post and the step emitted `
			.. `{TelemetryEmitContract.describe(TelemetryEmitContract.shapes(inPost))}. No `
			.. `bounce_before_resolution after resolution`
	)

	s.apply(TelemetryEmitContract.left("p2"), s.last + STEP) -- duplicate, in Post
	TelemetryEmitContract.toLobby(s)

	local after: { any } = {}
	for index = before + 1, #s.log do
		for _, effect in s.log[index].effects do
			table.insert(after, effect)
		end
	end
	local total = TelemetryEmitContract.count(after, "bounce_before_resolution")
	assert(
		total == 0,
		`AC-5: from entering Resolution through Post and back to Lobby, with two players leaving `
			.. `and one duplicate departure, {total} bounce_before_resolution event(s) were emitted; `
			.. `wanted none`
	)
end

--[[
	AC-6: exactly one bounce per departure per round.

	Three shapes, whole lists at every step:

	  (i)   the criterion's own: leave in Round, then a duplicate `PlayerLeft`.
	        The Round leaver is UNSEATED, so P1's seated gate refuses the
	        duplicate before any guard is consulted;
	  (ii)  leave in Assignment, then a duplicate. The Assignment leaver STAYS
	        seated (P3), so this is the case only the `departed` guard refuses -
	        and the case the story's control (b) is told apart by;
	  (iii) across rounds: both players are back in the next round (p3 rejoins
	        the Lobby; p4 was never unseated) and each bounces again, once.
	        `departed` resets on entering Lobby, so "once per round" is what
	        the guard means and not "once per session".
]]
function TelemetryEmitContract.bounceIsEmittedOncePerDeparturePerRound(machine: any, config: any)
	assert(
		config.playersMin - 1 >= config.minPlayersToContinue,
		`fixture: a round of playersMin ({config.playersMin}) cannot lose one player and continue `
			.. `against minPlayersToContinue ({config.minPlayersToContinue}); AC-6 needs the round `
			.. `to survive the departure`
	)
	local s = TelemetryEmitContract.lobbyOf(machine, config, config.playersMin)
	TelemetryEmitContract.toAssignment(s)

	-- (ii) Assignment: the leaver stays seated, and the guard is all there is.
	local inAssignment = s.apply(TelemetryEmitContract.left("p4"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-6",
		"p4 leaving in Assignment",
		inAssignment,
		{ bounce("p4", "Assignment") }
	)
	local duplicateInAssignment = s.apply(TelemetryEmitContract.left("p4"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-6",
		"a duplicate PlayerLeft for p4, still seated in Assignment (the departed guard)",
		duplicateInAssignment,
		{}
	)

	-- (i) Round: the criterion's own case.
	TelemetryEmitContract.toRound(s)
	local inRound = s.apply(TelemetryEmitContract.left("p3"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-6",
		"p3 leaving in Round",
		inRound,
		{ bounce("p3", "Round") }
	)
	assert(
		s.state.phase == "Round",
		`fixture: p3's departure ended the round; AC-6 needs it to continue`
	)
	local duplicateInRound = s.apply(TelemetryEmitContract.left("p3"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-6",
		"a duplicate PlayerLeft for p3, unseated in Round",
		duplicateInRound,
		{}
	)

	local firstRoundEffects = s.all()
	for _, who in { "p3", "p4" } do
		local total =
			TelemetryEmitContract.count(firstRoundEffects, "bounce_before_resolution", who)
		assert(
			total == 1,
			`AC-6: {who} left once (and once more by duplicate) in the first round and `
				.. `{total} bounce_before_resolution event(s) were emitted for them; wanted exactly 1`
		)
	end

	-- (iii) The next round: one more each.
	TelemetryEmitContract.resolveByEvent(s, "AC-6")
	TelemetryEmitContract.toPost(s)
	TelemetryEmitContract.toLobby(s)
	s.apply(TelemetryEmitContract.joined("p3"), s.last + STEP)
	assert(
		#s.state.players == config.playersMin,
		`fixture: the second Lobby holds {Deep.show(s.state.players)}, wanted playersMin `
			.. `({config.playersMin}) - p1, p2, p4 carried from Post and p3 rejoined`
	)
	TelemetryEmitContract.toAssignment(s)
	local againInAssignment = s.apply(TelemetryEmitContract.left("p4"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-6",
		"p4 leaving in the NEXT round's Assignment (departed resets on entering Lobby)",
		againInAssignment,
		{ bounce("p4", "Assignment") }
	)
	TelemetryEmitContract.toRound(s)
	local againInRound = s.apply(TelemetryEmitContract.left("p3"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-6",
		"p3 leaving in the NEXT round",
		againInRound,
		{ bounce("p3", "Round") }
	)

	for _, who in { "p3", "p4" } do
		local total = TelemetryEmitContract.count(s.all(), "bounce_before_resolution", who)
		assert(
			total == 2,
			`AC-6: {who} left in two consecutive rounds and {total} bounce_before_resolution `
				.. `event(s) were emitted for them over the session; wanted exactly 2, one per round`
		)
	end
end

--[[
	AC-7: the step that enters `Resolution` emits exactly one
	`first_round_complete`, bucket D1, `fields = { roundId, scope = "session" }`,
	for each seated player on their FIRST round of the session - and none for a
	player on a later round.

	Whole lists. Round 1 seats p1..p5 with two wrinkles: p5 leaves the Lobby and
	rejoins (P2a - present at resolution, so they earn it), and p4 leaves in
	Assignment (P3 - still seated, `departed` set, so they do NOT). Round 2 adds
	p6, who is the only first-rounder: every carried player - p4 included, who
	has now been seated for two rounds - earns nothing.

	`scope = "session"` is asserted as part of the whole shape: it is what
	stops an M5 story silently changing what the metric means.
]]
function TelemetryEmitContract.firstRoundCompleteIsEmittedOncePerPlayerPerSession(
	machine: any,
	config: any
)
	assert(
		config.playersMax >= config.playersMin + 2,
		`fixture: this check seats playersMin + 1 in round one and one more in round two, and `
			.. `playersMax ({config.playersMax}) cannot hold playersMin + 2 ({config.playersMin + 2})`
	)
	local count = config.playersMin + 1
	local s = TelemetryEmitContract.lobbyOf(machine, config, count)
	local rejoiner = `p{count}`
	local assignmentLeaver = `p{count - 1}`

	-- P2a: leave the Lobby, come back.
	s.apply(TelemetryEmitContract.left(rejoiner), s.last + STEP)
	s.apply(TelemetryEmitContract.joined(rejoiner), s.last + STEP)
	assert(
		#s.state.players == count,
		`fixture: after {rejoiner} left and rejoined the Lobby holds {Deep.show(s.state.players)}`
	)

	TelemetryEmitContract.toAssignment(s)
	-- P3: leaves, stays seated, is marked departed.
	s.apply(TelemetryEmitContract.left(assignmentLeaver), s.last + STEP)
	TelemetryEmitContract.toRound(s)

	local firstEnding = TelemetryEmitContract.resolveByEvent(s, "AC-7")
	local carried = TelemetryEmitContract.eventOutcome()
	local expectedFirst: { any } = { roundComplete(carried.result, carried.reason) }
	for _, id in s.state.players do
		if id ~= assignmentLeaver then
			table.insert(expectedFirst, frc(id))
		end
	end
	TelemetryEmitContract.assertEmits(
		"AC-7",
		`round one's resolving step ({rejoiner} left the Lobby and rejoined; {assignmentLeaver} `
			.. `left in Assignment and stayed seated)`,
		firstEnding,
		expectedFirst
	)

	TelemetryEmitContract.toPost(s)
	TelemetryEmitContract.toLobby(s)
	local newcomer = `p{count + 1}`
	s.apply(TelemetryEmitContract.joined(newcomer), s.last + STEP)
	TelemetryEmitContract.toAssignment(s)
	TelemetryEmitContract.toRound(s)
	local secondEnding = TelemetryEmitContract.resolveByEvent(s, "AC-7")
	TelemetryEmitContract.assertEmits(
		"AC-7",
		`round two's resolving step ({newcomer} is the only player on a first round)`,
		secondEnding,
		{ roundComplete(carried.result, carried.reason), frc(newcomer) }
	)

	local all = s.all()
	for _, who in { "p1", rejoiner, newcomer } do
		local total = TelemetryEmitContract.count(all, "first_round_complete", who)
		assert(
			total == 1,
			`AC-7: {who} completed their first round once and {total} first_round_complete `
				.. `event(s) were emitted for them over two rounds; wanted exactly 1`
		)
	end
	local leaverTotal = TelemetryEmitContract.count(all, "first_round_complete", assignmentLeaver)
	assert(
		leaverTotal == 0,
		`AC-7 (P3): {assignmentLeaver} left in Assignment before their first round and `
			.. `{leaverTotal} first_round_complete event(s) were emitted for them; wanted none`
	)
end

--[[
	AC-8: a `RematchAccepted` in `Post` emits exactly one `rematch_accepted`,
	bucket D2_7; a player leaving in `Post` emits one `session_end`, bucket D1
	(and so does one leaving in `Resolution`, Contract §3).

	Whole lists. Both guards are exercised: a duplicate `RematchAccepted`, a
	`RematchAccepted` from a player who has departed, one from somebody not
	seated (P1), a duplicate `PlayerLeft` in Post, and - after `Post -> Lobby`
	resets `rematched` - a second round's `RematchAccepted` from the same
	player, which is once per ROUND (P4).
]]
function TelemetryEmitContract.rematchAndSessionEndAreEmittedOnceInPost(machine: any, config: any)
	local s = TelemetryEmitContract.roundOf(machine, config, config.playersMin)

	local inRound = s.apply(TelemetryEmitContract.rematch("p1"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-8",
		"a RematchAccepted in Round (ignored, ROUND-003 AC-7)",
		inRound,
		{}
	)

	TelemetryEmitContract.resolveByEvent(s, "AC-8")
	local inResolution = s.apply(TelemetryEmitContract.left("p4"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-8",
		"p4 leaving in Resolution",
		inResolution,
		{ sessionEnd("p4", "Resolution") }
	)

	local postEffects = TelemetryEmitContract.toPost(s)
	TelemetryEmitContract.assertEmits("AC-8", "the Tick Resolution -> Post", postEffects, {})

	local first = s.apply(TelemetryEmitContract.rematch("p1"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-8",
		"p1's RematchAccepted in Post",
		first,
		{ E("rematch_accepted", "D2_7", "p1", { roundId = ROUND_ID }) }
	)
	local duplicate = s.apply(TelemetryEmitContract.rematch("p1"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-8",
		"a duplicate RematchAccepted from p1 (P4)",
		duplicate,
		{}
	)
	local second = s.apply(TelemetryEmitContract.rematch("p2"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-8",
		"p2's RematchAccepted in Post",
		second,
		{ E("rematch_accepted", "D2_7", "p2", { roundId = ROUND_ID }) }
	)

	local leftInPost = s.apply(TelemetryEmitContract.left("p3"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-8",
		"p3 leaving in Post",
		leftInPost,
		{ sessionEnd("p3", "Post") }
	)
	local leftAgain = s.apply(TelemetryEmitContract.left("p3"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-8",
		"a duplicate PlayerLeft for p3 in Post (P2)",
		leftAgain,
		{}
	)
	local departedRematch = s.apply(TelemetryEmitContract.rematch("p3"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-8",
		"a RematchAccepted from p3, who has departed (P3)",
		departedRematch,
		{}
	)
	local departedInResolutionLeavesAgain = s.apply(TelemetryEmitContract.left("p4"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-8",
		"a duplicate PlayerLeft for p4 in Post, who departed in Resolution (departed persists to Post)",
		departedInResolutionLeavesAgain,
		{}
	)
	local strangerRematch =
		s.apply(TelemetryEmitContract.rematch("never-seated-p99"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-8",
		"a RematchAccepted from never-seated-p99 (P1)",
		strangerRematch,
		{}
	)

	assert(
		TelemetryEmitContract.count(s.all(), "rematch_accepted") == 2,
		`AC-8: two players accepted a rematch (one of them twice) and the session produced `
			.. `{TelemetryEmitContract.count(s.all(), "rematch_accepted")} rematch_accepted event(s)`
	)
	assert(
		TelemetryEmitContract.count(s.all(), "session_end") == 2,
		`AC-8: two players left after resolution (each twice) and the session produced `
			.. `{TelemetryEmitContract.count(s.all(), "session_end")} session_end event(s)`
	)

	-- P4: once per ROUND. The second round's Post accepts p1's rematch again.
	TelemetryEmitContract.toLobby(s)
	TelemetryEmitContract.toAssignment(s)
	TelemetryEmitContract.toRound(s)
	TelemetryEmitContract.resolveByEvent(s, "AC-8")
	TelemetryEmitContract.toPost(s)
	local nextRound = s.apply(TelemetryEmitContract.rematch("p1"), s.last + STEP)
	TelemetryEmitContract.assertEmits(
		"AC-8",
		"p1's RematchAccepted in the NEXT round's Post (rematched resets on entering Lobby)",
		nextRound,
		{ E("rematch_accepted", "D2_7", "p1", { roundId = ROUND_ID }) }
	)
end

--[[
	THE LIFECYCLE every check below shares, driven by a MANUAL CLOCK through
	non-integer, strictly increasing values no real clock would produce, and
	exercising all six emitters over two rounds. Returns the session and, for
	every step, its `now`.

	Round 1: five join (one twice), p5 leaves the Lobby and rejoins, p4 leaves
	in Assignment, p3 leaves in Round (and again), RoundResolved, p1 leaves in
	Resolution, p2 accepts a rematch (twice), p1 tries to, p5 leaves in Post
	(twice). Round 2: p3 rejoins, p6 joins, four leave in Round and the last
	departure ends it below quorum.
]]
function TelemetryEmitContract.lifecycle(machine: any, config: any): any
	local s = TelemetryEmitContract.session(machine, config)
	local clock = Clock.manual(0)
	local nows: { number } = {}

	local function step(event: any, advance: number)
		clock:advance(advance)
		table.insert(nows, clock.now())
		s.apply(event, clock.now())
	end

	local T = TelemetryEmitContract

	-- Round 1. The first advance is 1/16 and every later one a multiple of 1/8,
	-- so every `now` is 0.0625 + k/8: exact in binary and never an integer.
	step(T.joined("p1"), 0.0625)
	step(T.joined("p2"), 0.25)
	step(T.joined("p3"), 0.25)
	step(T.joined("p4"), 0.25)
	step(T.joined("p2"), 0.25) -- duplicate
	step(T.joined("p5"), 0.25)
	step(T.left("p5"), 0.25) -- leaves the Lobby
	step(T.joined("p5"), 0.25) -- and rejoins (P2a)
	step(T.tick(), config.lobbySeconds - 0.625) -- past lobbySeconds -> Assignment
	step(T.left("p4"), 0.25) -- Assignment: bounces, stays seated (P3)
	step(T.seatsAssigned(), 0.25) -- -> Round
	step(T.left("p3"), 0.5) -- Round: bounces, unseated
	step(T.left("p3"), 0.25) -- duplicate
	step(T.resolved(T.eventOutcome()), 0.75) -- -> Resolution
	step(T.left("p1"), 0.25) -- Resolution: session_end
	step(T.tick(), 0.25) -- -> Post
	step(T.rematch("p2"), 0.25)
	step(T.rematch("p2"), 0.25) -- duplicate
	step(T.rematch("p1"), 0.25) -- departed
	step(T.left("p5"), 0.25) -- Post: session_end
	step(T.left("p5"), 0.25) -- duplicate
	step(T.tick(), config.postRoundSeconds - 0.75) -- past postRoundSeconds -> Lobby

	-- Round 2.
	step(T.joined("p3"), 0.25) -- rejoins: no second join
	step(T.joined("p6"), 0.25) -- new to the session
	step(T.tick(), config.lobbySeconds + 0.25) -- -> Assignment
	step(T.seatsAssigned(), 0.25) -- -> Round
	step(T.left("p3"), 0.25)
	step(T.left("p2"), 0.25)
	step(T.left("p4"), 0.25)
	step(T.left("p5"), 0.25) -- below quorum: ends the round
	step(T.tick(), 0.25) -- -> Post
	step(T.tick(), config.postRoundSeconds + 0.25) -- -> Lobby

	return s, nows
end

--[[
	AC-9: over the lifecycle above, every `Emit`'s `at` equals the `now` of the
	step that produced it, and no event's name is absent from `Event.BUCKETS`.

	The control is a machine stamping `at` from a real clock, which can never
	equal a dyadic fraction handed in by a manual clock. Violations are
	accumulated and asserted once. Two vacuity guards: the lifecycle must have
	produced telemetry at all, and all six of this story's emitters must have
	fired, or `at` has not been read for every emitter.
]]
function TelemetryEmitContract.everyEmitCarriesTheStepsNowAndAKnownName(machine: any, config: any)
	local s, nows = TelemetryEmitContract.lifecycle(machine, config)
	assert(
		s.state.phase == "Lobby",
		`fixture: the lifecycle ended in {tostring(s.state.phase)}, not back in Lobby`
	)
	for index = 2, #nows do
		assert(
			nows[index] > nows[index - 1] and nows[index] ~= math.floor(nows[index]),
			`fixture: the manual clock must be strictly increasing and non-integer; step {index} `
				.. `is at {nows[index]} after {nows[index - 1]}`
		)
	end

	local wrongAt: { string } = {}
	local unknownName: { string } = {}
	local wrongBucket: { string } = {}
	local wrongSession: { string } = {}
	local seen: { [string]: number } = {}
	local total = 0

	for index, entry in s.log do
		for _, event in TelemetryEmitContract.emitted(entry.effects) do
			total += 1
			local shape = TelemetryEmitContract.describeOne(TelemetryEmitContract.shape(event))
			if event.at ~= entry.now then
				table.insert(
					wrongAt,
					`step {index} at now = {entry.now}: {shape} carries at = {tostring(event.at)}`
				)
			end
			local bucket = Event.BUCKETS[event.name]
			if bucket == nil then
				table.insert(unknownName, `step {index}: {shape}`)
			elseif event.bucket ~= bucket then
				table.insert(
					wrongBucket,
					`step {index}: {shape} is filed under {tostring(event.bucket)}, BUCKETS says {bucket}`
				)
			end
			if event.sessionId ~= TelemetryEmitContract.SESSION_ID then
				table.insert(
					wrongSession,
					`step {index}: {shape} carries sessionId {Deep.show(event.sessionId)}`
				)
			end
			seen[tostring(event.name)] = (seen[tostring(event.name)] or 0) + 1
		end
	end

	assert(
		total > 0,
		`AC-9: a full lifecycle of {#s.log} steps emitted no telemetry at all; there is nothing `
			.. `whose at could be checked`
	)
	local missing: { string } = {}
	for _, name in TelemetryEmitContract.EMITTED_NAMES do
		if (seen[name] or 0) == 0 then
			table.insert(missing, name)
		end
	end
	assert(
		#missing == 0,
		`AC-9: the lifecycle emitted {total} event(s) but never {table.concat(missing, ", ")}; `
			.. `at has to be checked for every one of this story's six emitters`
	)
	assert(
		#wrongAt == 0,
		`AC-9: {#wrongAt} of {total} event(s) carry an at that is not the now of the step that `
			.. `produced them. The step never uses another time source. The first: {wrongAt[1]}`
	)
	assert(
		#unknownName == 0,
		`AC-9: {#unknownName} event(s) carry a name absent from Event.BUCKETS. The first: `
			.. `{unknownName[1]}`
	)
	assert(
		#wrongBucket == 0,
		`AC-9: {#wrongBucket} event(s) are filed under a bucket other than Event.BUCKETS'. The `
			.. `first: {wrongBucket[1]}`
	)
	assert(
		#wrongSession == 0,
		`AC-9: {#wrongSession} event(s) carry a sessionId other than the one initial was given. `
			.. `The first: {wrongSession[1]}`
	)
end

--[[
	Contract §3 P5, read over the WHOLE lifecycle: the telemetry it produces is
	exactly this sequence, in this order.

	This is the exactly-once assertion in its strongest form - one extra or
	missing event anywhere in two rounds is a different list - and it is what
	the story's `## Handoff` calls the golden sequence. It jointly covers
	AC-1..AC-8, so every wrong machine in `TelemetryEmitStubs.luau` except the
	real-clock one fails it; the per-criterion checks above are what make each
	failure attributable.
]]
function TelemetryEmitContract.lifecycleEmitsExactlyTheContractsSequence(machine: any, config: any)
	local s = TelemetryEmitContract.lifecycle(machine, config)
	local carried = TelemetryEmitContract.eventOutcome()
	local expected: { any } = {
		-- Round 1, Lobby.
		join("p1"),
		join("p2"),
		join("p3"),
		join("p4"),
		join("p5"),
		bounce("p5", "Lobby"),
		-- Assignment.
		bounce("p4", "Assignment"),
		-- Round.
		bounce("p3", "Round"),
		-- Resolution entered by RoundResolved: seated p1, p2, p4, p5; p4 departed.
		roundComplete(carried.result, carried.reason),
		frc("p1"),
		frc("p2"),
		frc("p5"),
		sessionEnd("p1", "Resolution"),
		-- Post.
		E("rematch_accepted", "D2_7", "p2", { roundId = ROUND_ID }),
		sessionEnd("p5", "Post"),
		-- Round 2, Lobby: p1, p2, p4, p5 carried; p3 rejoins; p6 joins.
		join("p6"),
		-- Round: p3, p2, p4 leave; p5's departure ends it below quorum.
		bounce("p3", "Round"),
		bounce("p2", "Round"),
		bounce("p4", "Round"),
		bounce("p5", "Round"),
		roundComplete("no_contest", "below_quorum"),
		frc("p6"),
	}
	TelemetryEmitContract.assertEmits("P5", "the two-round lifecycle", s.all(), expected)
end

--[[
	ROUND-003 AC-6 on the steps this story makes emit: an emitting step is still
	pure and deterministic. `Emit` effects are values, and a machine that stamped
	them from anything but `(state, event, now)` would return different effects
	for the same call.
]]
function TelemetryEmitContract.emittingStepsArePureAndDeterministic(machine: any, config: any)
	local s = TelemetryEmitContract.lobbyOf(machine, config, config.playersMin)
	local lobby = s.state
	TelemetryEmitContract.toAssignment(s)
	TelemetryEmitContract.toRound(s)
	local round = s.state
	TelemetryEmitContract.resolveByEvent(s, "ROUND-003 AC-6")
	local resolution = s.state
	TelemetryEmitContract.toPost(s)
	local post = s.state

	local cases: { Contract.Case } = {
		{
			label = "a first PlayerJoined in Lobby (emits join)",
			state = lobby,
			event = TelemetryEmitContract.joined("p9"),
			now = 1.5,
		},
		{
			label = "a PlayerLeft in Lobby (emits bounce)",
			state = lobby,
			event = TelemetryEmitContract.left("p1"),
			now = 1.5,
		},
		{
			label = "a PlayerLeft in Round (emits bounce)",
			state = round,
			event = TelemetryEmitContract.left("p1"),
			now = round.phaseEnteredAt + 0.5,
		},
		{
			label = "the RoundResolved entering Resolution (emits round_complete, first_round_complete)",
			state = round,
			event = TelemetryEmitContract.resolved(TelemetryEmitContract.eventOutcome()),
			now = round.phaseEnteredAt + 0.5,
		},
		{
			label = "a PlayerLeft in Resolution (emits session_end)",
			state = resolution,
			event = TelemetryEmitContract.left("p1"),
			now = resolution.phaseEnteredAt + 0.5,
		},
		{
			label = "a RematchAccepted in Post (emits rematch_accepted)",
			state = post,
			event = TelemetryEmitContract.rematch("p1"),
			now = post.phaseEnteredAt + 0.5,
		},
	}

	local violations: { string } = {}
	for _, case in cases do
		local ok, err = pcall(Contract.stepDoesNotMutateItsInput, machine, case)
		if not ok then
			table.insert(violations, tostring(err))
		end
		ok, err = pcall(Contract.stepIsDeterministic, machine, case)
		if not ok then
			table.insert(violations, tostring(err))
		end
	end
	if #violations > 0 then
		error(
			`ROUND-003 AC-6 on TEL-002's emitting steps: {#violations} violation(s). The first:\n`
				.. violations[1],
			2
		)
	end
end

return TelemetryEmitContract
