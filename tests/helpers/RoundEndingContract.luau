--!strict
--[[
	ROUND-005 AC-1 to AC-7 written once, as checks over a MACHINE rather than
	over a module - the same arrangement as `PhaseMachineContract.luau` and
	`LobbyGateContract.luau`, and for the same reason.

	`tests/server/round_ending_test.luau` applies these to the real
	`src/server/round/PhaseMachine.luau`.
	`tests/server/round_ending_controls_test.luau` applies them to the
	deliberately wrong machines in `RoundEndingStubs.luau`, so that every control
	a criterion NAMES - AC-3's machine that records a quorum failure as `lost`,
	AC-6's machine that keeps ticking a finished round - has been OBSERVED
	failing the check it is aimed at, and observed ACCEPTING a machine that ends
	a round correctly. A check nobody has seen refuse anything is not a check.

	THE PRECEDENCE LIST IS THE CONTRACT AND IT IS PINNED EXACTLY
	(`docs/wiki/architecture.md` section 3, the story's `## Contract`):

	    1. RoundResolved  - an event carrying an outcome; recorded verbatim
	    2. below_quorum   - `#players < minPlayersToContinue`; no_contest
	    3. clock          - `now - phaseEnteredAt >= roundSeconds`; lost

	Nothing below invents a tie-break and nothing below re-derives one. AC-4 and
	AC-5 are checked on a SINGLE step in which two (or three) conditions hold at
	once, constructed directly: `step` is pure and takes `now` as an argument, so
	"advance the clock, then send the event" - which is two steps and asserts
	nothing about precedence - is never used here.

	EVERY THRESHOLD IS READ OUT OF THE CONFIG IT IS HANDED. `round_seconds` and
	`min_players_to_continue` are settled and derived (`ROUND-002`,
	`docs/wiki/game/tuning.md` section 1) and there is nothing here to calibrate.
	No assertion below writes one of those numbers: the two places that need a
	SHAPE rather than a value - AC-7 needs `playersMin > minPlayersToContinue` so
	a departure can land exactly ON the threshold, AC-2 needs the count to be
	able to fall below it - say so in an explicit precondition assert that names
	what to do if the design ever stops supplying it.

	Every message names its criterion, because the controls assert on the text.
	Messages are kept under about 480 characters: Luau truncates an `assert`
	message at roughly 500, position prefix included, and a truncated message
	takes the evidence with it (measured on this suite in ROUND-004's RED).
]]

local Contract = require("./PhaseMachineContract")
local Deep = require("./Deep")

local RoundEndingContract = {}

RoundEndingContract.SEED = 20260917
RoundEndingContract.ROUND_ID = "round-ROUND-005-a"
-- TEL-002: `initial` takes the driver's session id as its 4th argument.
RoundEndingContract.SESSION_ID = "session-ROUND-005-a"

--[[
	The two outcomes THIS story owns, and the one it does not.

	Each is a FUNCTION returning a fresh table, never a shared constant: the
	event outcome is handed to the machine, and a shared table would let an
	implementation that mutates what it was given pass a comparison against the
	very table it mutated.

	`eventOutcome`'s reason is a string no implementation would invent, and its
	result is `won` - which neither the clock (`lost`) nor quorum (`no_contest`)
	can produce. A machine that decided the outcome itself cannot accidentally
	agree with it.
]]
function RoundEndingContract.clockOutcome(): any
	return { result = "lost", reason = "clock" }
end

function RoundEndingContract.quorumOutcome(): any
	return { result = "no_contest", reason = "below_quorum" }
end

function RoundEndingContract.eventOutcome(): any
	return { result = "won", reason = "reason-k8qz-carried-by-the-event-not-invented-here" }
end

function RoundEndingContract.joined(playerId: string): any
	return { kind = "PlayerJoined", playerId = playerId }
end

function RoundEndingContract.left(playerId: string): any
	return { kind = "PlayerLeft", playerId = playerId }
end

function RoundEndingContract.tick(): any
	return { kind = "Tick" }
end

function RoundEndingContract.seatsAssigned(): any
	return { kind = "SeatsAssigned" }
end

function RoundEndingContract.resolved(outcome: any): any
	return { kind = "RoundResolved", outcome = outcome }
end

-- `p1` .. `pN`, which is also the seat order every check below expects back.
function RoundEndingContract.roster(count: number): { string }
	local ids: { string } = {}
	for index = 1, count do
		table.insert(ids, `p{index}`)
	end
	return ids
end

--[[
	A `Round` with `count` players seated, reached by DRIVING the machine.

	The Round is entered at `lobbySeconds * 2` rather than at 0 on purpose: a
	machine that measures `roundSeconds` from zero instead of from
	`phaseEnteredAt` ends the round early, and AC-1's "not before" assertion is
	what sees it. A state written down by hand would test my idea of the machine.
]]
function RoundEndingContract.roundOf(machine: any, config: any, count: number): any
	assert(
		count >= config.playersMin and count <= config.playersMax,
		`fixture: a round of {count} cannot be started - playersMin is {config.playersMin} and `
			.. `playersMax is {config.playersMax}`
	)

	local state = machine.initial(
		config,
		RoundEndingContract.SEED,
		RoundEndingContract.ROUND_ID,
		RoundEndingContract.SESSION_ID
	)
	for _, id in RoundEndingContract.roster(count) do
		state = machine.step(state, RoundEndingContract.joined(id), 0)
	end

	local assignment = machine.step(state, RoundEndingContract.tick(), config.lobbySeconds * 1.5)
	assert(
		assignment.phase == "Assignment",
		`fixture: a lobby of {count} ticked at {config.lobbySeconds * 1.5} is in `
			.. `{tostring(assignment.phase)}, not Assignment (ROUND-003 AC-1, ROUND-004 AC-2)`
	)

	local enteredAt = config.lobbySeconds * 2
	local round = machine.step(assignment, RoundEndingContract.seatsAssigned(), enteredAt)
	assert(
		round.phase == "Round" and #round.players == count,
		`fixture: SeatsAssigned at {enteredAt} produced phase {tostring(round.phase)} with `
			.. `{Deep.show(round.players)} seated, wanted a Round of {count}`
	)
	return round
end

--[[
	A `Round` whose seated count is ALREADY below `minPlayersToContinue`, which
	AC-5 and the third precedence pair both need as a single-step starting point.

	It cannot be reached by driving the machine, and that is not a gap: the
	`PlayerLeft` that takes the count below the threshold ENDS the round on that
	same step (AC-2), so no event leaves the machine sitting in `Round` below
	quorum. The state is therefore the machine's OWN Round state - its phase,
	`phaseEnteredAt`, `roundId`, `seed` and `config` all produced by driving it -
	with the seated list shortened by the fixture and nothing else touched.

	Contract pin 2 depends on this state existing: a `RematchAccepted` arriving
	at a `Round` sitting below quorum is still ignored, and the next `Tick` ends
	the round.
]]
function RoundEndingContract.belowQuorumRound(machine: any, config: any): any
	assert(
		config.minPlayersToContinue >= 1,
		`fixture: minPlayersToContinue is {config.minPlayersToContinue}; no seated count can be `
			.. `below it, and AC-5 has nothing to stand on. That is an Amendments question`
	)

	local round = RoundEndingContract.roundOf(machine, config, config.playersMin)
	local state = Deep.copy(round)
	local short: { string } = {}
	for index = 1, config.minPlayersToContinue - 1 do
		table.insert(short, round.players[index])
	end
	state.players = short

	assert(
		state.phase == "Round"
			and #state.players < config.minPlayersToContinue
			and state.outcome == nil,
		`fixture: the below-quorum Round is {Deep.show(state.phase)} with `
			.. `{Deep.show(state.players)} seated against minPlayersToContinue `
			.. `{config.minPlayersToContinue}`
	)
	return state
end

--[[
	The three endings, each returning the ending state and the effects the ending
	step emitted.

	`criterion` is written into the fixture failure, so a machine that does not
	end a round at all fails under the criterion being checked rather than under
	a helper nobody can place.
]]
function RoundEndingContract.endByClock(
	machine: any,
	config: any,
	criterion: string
): (any, { any })
	assert(
		config.playersMin >= config.minPlayersToContinue,
		`fixture: a round of playersMin ({config.playersMin}) is already below `
			.. `minPlayersToContinue ({config.minPlayersToContinue}), so the clock is not the `
			.. `only terminal condition in play and this ending is not the clock's`
	)

	local round = RoundEndingContract.roundOf(machine, config, config.playersMin)
	local due = round.phaseEnteredAt + config.roundSeconds
	local after, effects = machine.step(round, RoundEndingContract.tick(), due)
	assert(
		after.phase == "Resolution",
		`{criterion}: a Tick at now = {due} - exactly roundSeconds ({config.roundSeconds}) after `
			.. `the Round was entered at {round.phaseEnteredAt} - left the machine in `
			.. `{tostring(after.phase)}. round_seconds elapsed ends the round`
	)
	return after, effects
end

function RoundEndingContract.endByQuorum(
	machine: any,
	config: any,
	criterion: string
): (any, { any })
	local round = RoundEndingContract.roundOf(machine, config, config.playersMin)
	local leaves = config.playersMin - config.minPlayersToContinue + 1
	assert(
		leaves < config.roundSeconds,
		`fixture: the {leaves} departure(s) span {leaves} second(s) against a roundSeconds of `
			.. `{config.roundSeconds}; the clock must not be due, or this ending could be the `
			.. `clock's`
	)

	local state = round
	local effects: { any } = {}
	for index = 1, leaves do
		local at = round.phaseEnteredAt + index
		state, effects = machine.step(state, RoundEndingContract.left(`p{index + 1}`), at)
	end

	assert(
		state.phase == "Resolution",
		`{criterion}: {leaves} player(s) left a round of {config.playersMin}, taking the seated `
			.. `count below minPlayersToContinue ({config.minPlayersToContinue}), and the machine `
			.. `is in {tostring(state.phase)} with {Deep.show(state.players)} seated`
	)
	return state, effects
end

function RoundEndingContract.endByEvent(
	machine: any,
	config: any,
	criterion: string
): (any, { any })
	local round = RoundEndingContract.roundOf(machine, config, config.playersMin)
	local at = round.phaseEnteredAt + 1
	local event = RoundEndingContract.resolved(RoundEndingContract.eventOutcome())
	local after, effects = machine.step(round, event, at)
	assert(
		after.phase == "Resolution",
		`{criterion}: a RoundResolved at now = {at} left the machine in {tostring(after.phase)} `
			.. `(ROUND-003 AC-3)`
	)
	return after, effects
end

--[[
	AC-1: the clock ends the round at exactly `roundSeconds` elapsed, as
	`{ result = "lost", reason = "clock" }`, AND NOT BEFORE.

	The "not before" half is a tenth of a second short, which is also what
	catches a machine measuring the round from 0 rather than from the step that
	entered `Round` - the fixture enters it at `lobbySeconds * 2`, so the two
	readings are `lobbySeconds * 2` apart, not a rounding error apart.

	The comparison at the boundary is INCLUSIVE, read out of
	`architecture.md` section 3 (`now - phaseEnteredAt >= round_seconds`) and
	ROUND-003 AC-1's identical treatment of `lobbySeconds`. It is not a choice
	made here.
]]
function RoundEndingContract.roundEndsOnTheClock(machine: any, config: any)
	local round = RoundEndingContract.roundOf(machine, config, config.playersMin)
	local enteredAt = round.phaseEnteredAt
	local expected = RoundEndingContract.clockOutcome()

	local justShort = enteredAt + config.roundSeconds - 0.1
	local running, runningEffects = machine.step(round, RoundEndingContract.tick(), justShort)
	assert(
		running.phase == "Round",
		`AC-1: at now = {justShort}, a tenth of a second short of roundSeconds `
			.. `({config.roundSeconds}) since the Round was entered at {enteredAt}, the phase is `
			.. `{tostring(running.phase)}. The round ends when the clock elapses and NOT BEFORE`
	)
	assert(
		running.outcome == nil,
		`AC-1: an outcome ({Deep.show(running.outcome)}) was recorded at now = {justShort}, `
			.. `before roundSeconds ({config.roundSeconds}) elapsed`
	)
	assert(
		#runningEffects == 0,
		`AC-1: a round still running emitted {Deep.show(Deep.kinds(runningEffects))} at `
			.. `now = {justShort}`
	)

	local due = enteredAt + config.roundSeconds
	local ended = machine.step(round, RoundEndingContract.tick(), due)
	assert(
		ended.phase == "Resolution",
		`AC-1: at now = {due} - exactly roundSeconds ({config.roundSeconds}) after the Round was `
			.. `entered at {enteredAt} - the phase is {tostring(ended.phase)}. The comparison is `
			.. `inclusive at the boundary (architecture.md section 3)`
	)
	assert(
		Deep.equal(ended.outcome, expected),
		`AC-1: the clock ended the round and the outcome recorded is `
			.. `{Deep.show(ended.outcome)}:\n{Deep.diff(expected, ended.outcome)}`
	)
	assert(
		#ended.players == config.playersMin,
		`AC-1: the clock ending changed the seated list to {Deep.show(ended.players)}; it ends `
			.. `the round, it does not unseat anybody`
	)

	local wellPast = enteredAt + config.roundSeconds * 3
	local late = machine.step(round, RoundEndingContract.tick(), wellPast)
	assert(
		late.phase == "Resolution" and Deep.equal(late.outcome, expected),
		`AC-1: a Tick well past the clock (now = {wellPast}) left the machine in `
			.. `{tostring(late.phase)} with outcome {Deep.show(late.outcome)}. A driver that `
			.. `ticks irregularly cannot stretch a round`
	)

	Contract.stepDoesNotMutateItsInput(machine, {
		label = "the Tick that ends a round on the clock",
		state = round,
		event = RoundEndingContract.tick(),
		now = due,
	})
end

--[[
	AC-7: a departure that reduces the count to EXACTLY `minPlayersToContinue`
	leaves the round running.

	Three is a ring (`roles.md` section 6) and the threshold is "below", not "at
	or below" - `tuning.md` section 1's derivation, not a choice. `<=` here ends
	every three-player round silently, which is mutation 1 of the story's
	`## Notes` and `RoundEndingStubs.atOrBelow`.

	The trailing `Tick` matters as much as the leaves: quorum is consulted on
	`Tick` as well as on `PlayerLeft`, so a machine comparing with `<=` has two
	chances to end the round and this check takes both away.
]]
function RoundEndingContract.roundContinuesAtExactlyTheThreshold(machine: any, config: any)
	assert(
		config.playersMin > config.minPlayersToContinue,
		`fixture: playersMin ({config.playersMin}) is not above minPlayersToContinue `
			.. `({config.minPlayersToContinue}), so no departure from a round that could start `
			.. `lands exactly ON the threshold and AC-7's boundary is unreachable. That is an `
			.. `Amendments question about AC-7, not a number to edit here`
	)

	local round = RoundEndingContract.roundOf(machine, config, config.playersMin)
	local state = round
	local now = round.phaseEnteredAt

	for index = 1, config.playersMin - config.minPlayersToContinue do
		local id = `p{index + 1}`
		now = round.phaseEnteredAt + index
		local after, effects = machine.step(state, RoundEndingContract.left(id), now)
		local remaining = config.playersMin - index

		assert(
			#after.players == remaining,
			`AC-7: {id} left a round of {#state.players} at now = {now} and `
				.. `{Deep.show(after.players)} are seated, wanted {remaining}. A mid-round `
				.. `departure unseats (Contract pin 1)`
		)
		assert(
			after.phase == "Round",
			`AC-7: {remaining} seated is not below minPlayersToContinue `
				.. `({config.minPlayersToContinue}) and the phase is {tostring(after.phase)}. `
				.. `The threshold is "below", not "at or below"`
		)
		assert(
			after.outcome == nil,
			`AC-7: an outcome ({Deep.show(after.outcome)}) was recorded with {remaining} seated `
				.. `against minPlayersToContinue {config.minPlayersToContinue}`
		)
		-- TEL-002 Contract §5: the departure itself carries a
		-- `bounce_before_resolution` Emit, which TelemetryEmitContract pins.
		-- This assertion is about CONTROL effects and excludes telemetry.
		local control = Deep.controlKinds(effects)
		assert(
			#control == 0,
			`AC-7: a continuing round emitted control effect(s) {Deep.show(control)} `
				.. `(telemetry Emit effects excluded)`
		)
		state = after
	end

	assert(
		#state.players == config.minPlayersToContinue,
		`AC-7: the departures left {Deep.show(state.players)} seated, wanted exactly `
			.. `minPlayersToContinue ({config.minPlayersToContinue})`
	)

	local tickAt = now + 1
	assert(
		tickAt - round.phaseEnteredAt < config.roundSeconds,
		`fixture: the tick at {tickAt} is roundSeconds ({config.roundSeconds}) or more after the `
			.. `Round was entered at {round.phaseEnteredAt}; the clock would end the round and `
			.. `AC-7 would pass for the wrong reason`
	)
	local ticked, tickEffects = machine.step(state, RoundEndingContract.tick(), tickAt)
	assert(
		ticked.phase == "Round",
		`AC-7: with exactly minPlayersToContinue ({config.minPlayersToContinue}) seated, a Tick `
			.. `at now = {tickAt} moved the machine to {tostring(ticked.phase)}. Three is a ring `
			.. `(roles.md section 6): the comparison is #players < minPlayersToContinue, strict`
	)
	assert(
		ticked.outcome == nil and #tickEffects == 0,
		`AC-7: the Tick at {tickAt} recorded {Deep.show(ticked.outcome)} and emitted `
			.. `{Deep.show(Deep.kinds(tickEffects))} on a round that is still running`
	)

	Contract.stepDoesNotMutateItsInput(machine, {
		label = "a PlayerLeft unseating a player in Round, above the quorum threshold",
		state = round,
		event = RoundEndingContract.left("p2"),
		now = round.phaseEnteredAt + 1,
	})
end

--[[
	AC-2: when a departure takes the seated count BELOW `minPlayersToContinue`,
	the round ends on that same step as
	`{ result = "no_contest", reason = "below_quorum" }`.

	The whole descent is asserted, not only the last step: the count falls by one
	per departure (Contract pin 1 - the leave unseats), the round survives every
	count at or above the threshold (AC-7), and the step that crosses it is the
	one that resolves. The clock is never due while this runs, so the ending
	cannot be the clock's.
]]
function RoundEndingContract.roundEndsNoContestWhenTheCountFallsBelowTheThreshold(
	machine: any,
	config: any
)
	local leaves = config.playersMin - config.minPlayersToContinue + 1
	assert(
		leaves >= 1 and config.playersMin >= leaves,
		`fixture: playersMin ({config.playersMin}) and minPlayersToContinue `
			.. `({config.minPlayersToContinue}) leave no room for the count to fall below the `
			.. `threshold from a round that could start. That is an Amendments question about `
			.. `AC-2, not a number to edit here`
	)

	local round = RoundEndingContract.roundOf(machine, config, config.playersMin)
	local state = round
	local ending: any = nil
	local before: any = round
	local lastId, lastNow = "", round.phaseEnteredAt

	for index = 1, leaves do
		local id = `p{index + 1}`
		local now = round.phaseEnteredAt + index
		local after = machine.step(state, RoundEndingContract.left(id), now)
		local remaining = config.playersMin - index

		assert(
			#after.players == remaining,
			`AC-2: {id} left a round of {#state.players} at now = {now} and `
				.. `{Deep.show(after.players)} are seated, wanted {remaining}. A mid-round `
				.. `departure unseats (Contract pin 1)`
		)
		if remaining >= config.minPlayersToContinue then
			assert(
				after.phase == "Round",
				`AC-2: {remaining} seated is not below minPlayersToContinue `
					.. `({config.minPlayersToContinue}) and the phase is already `
					.. `{tostring(after.phase)}`
			)
		else
			before, lastId, lastNow = state, id, now
			ending = after
		end
		state = after
	end

	assert(
		lastNow - round.phaseEnteredAt < config.roundSeconds,
		`fixture: the last departure is at {lastNow}, roundSeconds ({config.roundSeconds}) or `
			.. `more after the Round was entered at {round.phaseEnteredAt}; the ending could be `
			.. `the clock's`
	)
	assert(
		ending ~= nil and ending.phase == "Resolution",
		`AC-2: {lastId} left at now = {lastNow}, taking the count below minPlayersToContinue `
			.. `({config.minPlayersToContinue}), and the phase is `
			.. `{tostring(if ending == nil then "Round" else ending.phase)}. The round ends on `
			.. `THAT step`
	)

	local expected = RoundEndingContract.quorumOutcome()
	assert(
		Deep.equal(ending.outcome, expected),
		`AC-2: the round ended below quorum and the outcome recorded is `
			.. `{Deep.show(ending.outcome)}:\n{Deep.diff(expected, ending.outcome)}`
	)
	assert(
		#ending.players == config.minPlayersToContinue - 1,
		`AC-2: the ending state holds {Deep.show(ending.players)}, wanted the `
			.. `{config.minPlayersToContinue - 1} player(s) left after {lastId} departed`
	)
	--[[
		The effects of the ending step are NOT asserted here, and that is
		deliberate: `endingSequenceEmitsExactlyOneComputeTrace` owns Contract
		pin 3 for all three endings at once. Asserting it here as well would make
		AC-6's own control - a machine that emits a `ComputeTrace` on the way out
		of `Round` - fail four checks instead of the one it is aimed at, and a
		control that fails everything is indistinguishable from a broken stub.
	]]
	Contract.stepDoesNotMutateItsInput(machine, {
		label = `the PlayerLeft ({lastId}) that took the count below minPlayersToContinue`,
		state = before,
		event = RoundEndingContract.left(lastId),
		now = lastNow,
	})
end

--[[
	AC-3: a round that ended below quorum is DISTINGUISHABLE FROM A LOSS.

	Both endings are driven and compared, because that is the difference the
	criterion is about: "a test asserting only 'the round ended' cannot tell them
	apart, and the difference is whether a group's season progress is harmed by
	somebody else's connection" (`mechanics.md` section 8, amendment 9). The
	control is `RoundEndingStubs.losing`, which ends the round, reaches
	Resolution, and records `lost`.
]]
function RoundEndingContract.quorumEndingIsDistinguishableFromALoss(machine: any, config: any)
	local quorum = RoundEndingContract.endByQuorum(machine, config, "AC-3")
	local clock = RoundEndingContract.endByClock(machine, config, "AC-3")

	assert(
		typeof(quorum.outcome) == "table",
		`AC-3: the round ended below quorum and recorded {Deep.show(quorum.outcome)} as its `
			.. `outcome; there is nothing to distinguish`
	)
	assert(
		quorum.outcome.result ~= "lost",
		`AC-3: the round ended because the lobby fell below minPlayersToContinue and the result `
			.. `recorded is "lost". No loss is recorded and season progress is unaffected: the `
			.. `group did not fail, the lobby did (mechanics.md section 8)`
	)
	assert(
		quorum.outcome.result == "no_contest",
		`AC-3: the quorum ending recorded result "{tostring(quorum.outcome.result)}", wanted `
			.. `"no_contest". Recording it as anything else punishes three players for a fourth `
			.. `person's connection`
	)
	assert(
		quorum.outcome.reason == "below_quorum",
		`AC-3: the quorum ending recorded reason "{tostring(quorum.outcome.reason)}", wanted `
			.. `"below_quorum"`
	)

	assert(
		typeof(clock.outcome) == "table" and clock.outcome.result == "lost",
		`AC-3: the CLOCK ending recorded {Deep.show(clock.outcome)}, wanted result "lost". If `
			.. `both endings record the same result there is nothing for AC-3 to tell apart`
	)
	assert(
		not Deep.equal(quorum.outcome, clock.outcome),
		`AC-3: the quorum ending and the clock ending both recorded {Deep.show(quorum.outcome)}`
	)
end

--[[
	AC-4: in ONE step in which the clock has expired AND a `RoundResolved`
	arrives, the outcome recorded is the one the EVENT carried.

	Constructed directly rather than by advancing the clock and then sending the
	event, which is two steps and asserts nothing about precedence: `step` is
	pure and takes `now` as an argument, so the simultaneous state is just a
	`now` past `phaseEnteredAt + roundSeconds` handed to the event's own step.

	Quorum is deliberately INTACT here, so exactly two conditions are in play and
	a failure is attributable to the event-versus-clock ordering alone.
]]
function RoundEndingContract.resolvingEventOutranksTheClock(machine: any, config: any)
	local round = RoundEndingContract.roundOf(machine, config, config.playersMin)
	assert(
		#round.players >= config.minPlayersToContinue,
		`fixture: a round of {#round.players} is already below minPlayersToContinue `
			.. `({config.minPlayersToContinue}); AC-4 needs quorum to HOLD so that only the `
			.. `event and the clock are in play`
	)

	local expired = round.phaseEnteredAt + config.roundSeconds + 5
	assert(
		expired - round.phaseEnteredAt >= config.roundSeconds,
		`fixture: now = {expired} is not past roundSeconds ({config.roundSeconds}) since the `
			.. `Round was entered at {round.phaseEnteredAt}; the clock is not expired and there `
			.. `is no simultaneity to resolve`
	)

	local carried = RoundEndingContract.eventOutcome()
	local event = RoundEndingContract.resolved(carried)
	local after = machine.step(round, event, expired)

	assert(
		after.phase == "Resolution",
		`AC-4: a RoundResolved at now = {expired}, with the clock expired, left the machine in `
			.. `{tostring(after.phase)}`
	)
	assert(
		Deep.equal(after.outcome, carried),
		`AC-4: the clock had expired and the event arrived on the SAME step; the outcome `
			.. `recorded is {Deep.show(after.outcome)}, not the one the event carried. The event `
			.. `describes something that happened inside the round; the clock describes the `
			.. `round running out around it. The event wins`
	)
	assert(
		#after.players == config.playersMin,
		`AC-4: the count was intact ({config.playersMin} seated) and the ending changed it to `
			.. `{Deep.show(after.players)}`
	)

	Contract.stepIsDeterministic(machine, {
		label = "a RoundResolved arriving on a step whose clock has already expired",
		state = round,
		event = event,
		now = expired,
	})
	Contract.stepDoesNotMutateItsInput(machine, {
		label = "a RoundResolved arriving on a step whose clock has already expired",
		state = round,
		event = event,
		now = expired,
	})
end

--[[
	The third precedence pair, and the only step on which ALL THREE terminal
	conditions hold at once: the event outranks both.

	It is producible because `belowQuorumRound` is producible - see that helper
	for why the machine cannot be driven into this state and why the state is
	still the machine's own.
]]
function RoundEndingContract.resolvingEventOutranksQuorumAndTheClock(machine: any, config: any)
	local round = RoundEndingContract.belowQuorumRound(machine, config)
	local expired = round.phaseEnteredAt + config.roundSeconds + 5

	local carried = RoundEndingContract.eventOutcome()
	local after = machine.step(round, RoundEndingContract.resolved(carried), expired)

	assert(
		after.phase == "Resolution",
		`AC-4: a RoundResolved at now = {expired}, below quorum and with the clock expired, left `
			.. `the machine in {tostring(after.phase)}`
	)
	assert(
		Deep.equal(after.outcome, carried),
		`AC-4: all three terminal conditions held on one step and the outcome recorded is `
			.. `{Deep.show(after.outcome)}, not the event's. RoundResolved is first in the `
			.. `precedence list (architecture.md section 3)`
	)
end

--[[
	AC-5: in ONE step in which the clock has expired AND the count is below
	quorum, the reason recorded is `below_quorum` - and it is the same on every
	run.

	"A round nobody can play did not run out of time." The determinism half is
	asserted rather than described: "the same on every run" is a claim about
	repeated identical calls, and `Contract.stepIsDeterministic` is what checks
	it. The control is `RoundEndingStubs.clockFirst`, which is this machine with
	the two entries of the precedence list swapped and nothing else changed.
]]
function RoundEndingContract.quorumOutranksTheClockInOneStep(machine: any, config: any)
	local round = RoundEndingContract.belowQuorumRound(machine, config)
	local expired = round.phaseEnteredAt + config.roundSeconds + 5
	local event = RoundEndingContract.tick()

	local after = machine.step(round, event, expired)

	assert(
		after.phase == "Resolution",
		`AC-5: a Tick at now = {expired}, below quorum ({#round.players} seated against `
			.. `minPlayersToContinue {config.minPlayersToContinue}) and past roundSeconds `
			.. `({config.roundSeconds}), left the machine in {tostring(after.phase)}`
	)
	assert(
		typeof(after.outcome) == "table",
		`AC-5: the round ended and recorded {Deep.show(after.outcome)} as its outcome`
	)
	assert(
		after.outcome.reason == "below_quorum",
		`AC-5: the clock had expired AND the count was below minPlayersToContinue on the same `
			.. `step, and the reason recorded is "{tostring(after.outcome.reason)}". A round `
			.. `nobody can play did not run out of time: the precedence is RoundResolved > `
			.. `below_quorum > clock (architecture.md section 3)`
	)
	assert(
		after.outcome.result == "no_contest",
		`AC-5: the quorum ending recorded result "{tostring(after.outcome.result)}", wanted `
			.. `"no_contest" (AC-3)`
	)

	Contract.stepIsDeterministic(machine, {
		label = "a Tick on a round that is below quorum AND past roundSeconds",
		state = round,
		event = event,
		now = expired,
	})

	local repeated = machine.step(round, event, expired)
	local repeatedReason = if typeof(repeated.outcome) == "table"
		then tostring(repeated.outcome.reason)
		else Deep.show(repeated.outcome)
	assert(
		repeatedReason == tostring(after.outcome.reason),
		`AC-5: two identical steps recorded reasons "{tostring(after.outcome.reason)}" and `
			.. `"{repeatedReason}". The reason is the same on every run, because the trace `
			.. `reports it and a reason that depends on evaluation order is a bug report nobody `
			.. `can reproduce`
	)
end

--[[
	AC-2 again, by the other event that consults quorum: a `Tick` on a round
	already below the threshold ends it.

	Contract pin 2 says quorum is consulted on `Tick` and on `PlayerLeft`, and
	only those. AC-2's own check exercises the `PlayerLeft` half; this is the
	`Tick` half, and it is the step that makes Contract pin 2's "the next Tick
	ends the round" true.
]]
function RoundEndingContract.quorumIsConsultedOnATick(machine: any, config: any)
	local round = RoundEndingContract.belowQuorumRound(machine, config)
	local at = round.phaseEnteredAt + 1
	assert(
		at - round.phaseEnteredAt < config.roundSeconds,
		`fixture: the tick at {at} is roundSeconds ({config.roundSeconds}) or more after the `
			.. `Round was entered at {round.phaseEnteredAt}; the ending could be the clock's`
	)

	local after = machine.step(round, RoundEndingContract.tick(), at)
	local expected = RoundEndingContract.quorumOutcome()

	assert(
		after.phase == "Resolution",
		`AC-2: a Tick at now = {at} on a round holding {Deep.show(round.players)} against `
			.. `minPlayersToContinue {config.minPlayersToContinue} left the machine in `
			.. `{tostring(after.phase)}. Quorum is consulted on Tick as well as on PlayerLeft`
	)
	assert(
		Deep.equal(after.outcome, expected),
		`AC-2: the Tick ended the round below quorum and recorded `
			.. `{Deep.show(after.outcome)}:\n{Deep.diff(expected, after.outcome)}`
	)
end

--[[
	AC-6, read over the ENDING SEQUENCE and not over the ending step alone.

	ROUND-003 AC-4 and AC-8 are frozen and green: `Resolution -> Post` emits
	exactly one `ComputeTrace` carrying the round id, and a full lifecycle emits
	exactly `AssignSeats, ComputeTrace, PromptRematch`. So the ending step itself
	emits NOTHING (Contract pin 3), and across the ending step plus every step
	from it through `Post` and back to `Lobby` there is exactly ONE
	`ComputeTrace`.

	That is exactly the reading AC-6's named control fails:
	`RoundEndingStubs.doubleTracing` emits a `ComputeTrace` from the `Round`
	branch on the way out and a second one on the `Resolution -> Post` tick. The
	count assertion comes FIRST so that control fails with the criterion's own
	words rather than on the pin-3 assertion beneath it.

	The extra tick inside `Post` is not padding: it is a step on a finished round
	that must emit nothing at all.
]]
function RoundEndingContract.endingSequenceEmitsExactlyOneComputeTrace(machine: any, config: any)
	local clockState, clockEffects = RoundEndingContract.endByClock(machine, config, "AC-6")
	local quorumState, quorumEffects = RoundEndingContract.endByQuorum(machine, config, "AC-6")
	local eventState, eventEffects = RoundEndingContract.endByEvent(machine, config, "AC-6")

	local endings: { { label: string, ended: any, effects: { any } } } = {
		{ label = "the clock", ended = clockState, effects = clockEffects },
		{ label = "quorum", ended = quorumState, effects = quorumEffects },
		{ label = "a RoundResolved event", ended = eventState, effects = eventEffects },
	}

	for _, ending in endings do
		local collected: { any } = {}
		for _, effect in ending.effects do
			table.insert(collected, effect)
		end

		local state = ending.ended
		local at = state.phaseEnteredAt
		for _, now in { at, at + config.postRoundSeconds / 2, at + config.postRoundSeconds } do
			local after, effects = machine.step(state, RoundEndingContract.tick(), now)
			for _, effect in effects do
				table.insert(collected, effect)
			end
			state = after
		end

		assert(
			state.phase == "Lobby",
			`AC-6: the round ended by {ending.label}; stepping from the ending through Post `
				.. `(postRoundSeconds {config.postRoundSeconds}) reached `
				.. `{tostring(state.phase)}, not Lobby, so the sequence AC-6 counts over is not `
				.. `complete`
		)

		local traces: { any } = {}
		for _, effect in collected do
			if effect.kind == "ComputeTrace" then
				table.insert(traces, effect)
			end
		end

		assert(
			#traces == 1,
			`AC-6: the round ended by {ending.label} and the sequence from the ending step back `
				.. `to Lobby emitted {#traces} ComputeTrace effect(s): `
				.. `{Deep.show(Deep.kinds(collected))}. Exactly one - and a machine that keeps `
				.. `ticking a finished round emits a second`
		)
		assert(
			traces[1].roundId == ending.ended.roundId,
			`AC-6: the ComputeTrace for the {ending.label} ending carries roundId `
				.. `{Deep.show(traces[1].roundId)}, and the round is `
				.. `{Deep.show(ending.ended.roundId)}`
		)
		--[[
			TEL-002 Contract §5: the step that enters Resolution carries
			`round_complete` and `first_round_complete` Emits, pinned by
			TelemetryEmitContract. Pin 3 is about CONTROL effects - the one
			ComputeTrace belongs to Resolution -> Post - so both assertions below
			exclude telemetry through the one shared filter.
		]]
		local endingControl = Deep.controlKinds(ending.effects)
		assert(
			#endingControl == 0,
			`AC-6 (Contract pin 3): the step that ended the round by {ending.label} emitted `
				.. `control effect(s) {Deep.show(endingControl)} (telemetry Emit effects `
				.. `excluded). The ending step emits no control effect; the single ComputeTrace `
				.. `is emitted by Resolution -> Post (ROUND-003 AC-4)`
		)

		local wanted = { "ComputeTrace", "PromptRematch" }
		local collectedControl = Deep.controlKinds(collected)
		assert(
			Deep.equal(collectedControl, wanted),
			`AC-6: the {ending.label} ending sequence emitted control effects `
				.. `{Deep.show(collectedControl)}, wanted {Deep.show(wanted)} (ROUND-003 `
				.. `AC-8, minus the AssignSeats that started the round; telemetry Emit effects `
				.. `excluded)`
		)
	end
end

--[[
	Contract pin 5: a resolved round is not re-resolved.

	Once the machine is in `Resolution` or `Post` neither quorum nor the clock is
	consulted again - the round that ended below quorum is STILL below quorum,
	and the clock it did not run out of goes on running. `outcome` is written
	once, by the step that ended the round, and ROUND-004's Contract pin 2 still
	holds in both phases: a `PlayerLeft` there is ignored in full.
]]
function RoundEndingContract.aResolvedRoundIsNotReResolved(machine: any, config: any)
	local resolution = RoundEndingContract.endByQuorum(machine, config, "Contract pin 5")
	local expected = RoundEndingContract.quorumOutcome()

	local wellPast = resolution.phaseEnteredAt + config.roundSeconds * 3
	local post = machine.step(resolution, RoundEndingContract.tick(), wellPast)
	assert(
		post.phase == "Post",
		`Contract pin 5: Resolution moved to {tostring(post.phase)} on the next Tick `
			.. `(ROUND-003 AC-4)`
	)
	assert(
		Deep.equal(post.outcome, expected),
		`Contract pin 5: the outcome was rewritten on the way to Post - a clock that expired `
			.. `long ago was consulted again:\n{Deep.diff(expected, post.outcome)}`
	)

	local seated = post.players[1]
	assert(
		seated ~= nil,
		`fixture: the round ended below quorum with nobody seated, so there is no departure to `
			.. `ignore in Post`
	)
	-- TEL-002 Contract §5 / P2, P3: this departure now emits a `session_end`
	-- and records itself in `departed`; the seated list, the outcome and the
	-- control effects are still exactly what pin 5 says. See the helper.
	Contract.eventIsIgnoredExceptTelemetry(machine, {
		label = `a PlayerLeft naming the seated player {seated}, in Post`,
		state = post,
		event = RoundEndingContract.left(seated),
		now = wellPast + 1,
	})
end

--[[
	Contract pin 2: quorum is consulted for the events the phase RECOGNISES and
	for nothing else.

	ROUND-003 AC-7 is frozen and says an unrecognised event returns the state
	unchanged with an empty effect list, with no exception for a terminal
	condition that already holds. A `RematchAccepted` arriving at a `Round`
	sitting below quorum is therefore still ignored - and so is a `PlayerLeft`
	naming somebody who is not seated, which is an ignored event rather than a
	departure (Contract pin 1). The next `Tick` ends the round, which is the half
	that stops this being a licence to do nothing.
]]
function RoundEndingContract.unrecognisedEventsAreIgnoredBelowQuorum(machine: any, config: any)
	local round = RoundEndingContract.belowQuorumRound(machine, config)
	local at = round.phaseEnteredAt + 1

	local ignorable: { { label: string, event: any } } = {
		{
			label = "a RematchAccepted in a Round sitting below quorum",
			event = { kind = "RematchAccepted", playerId = "p1" },
		},
		{
			label = "an event whose kind is not in the union, in a Round below quorum",
			event = { kind = "DetonateTheReactor" },
		},
		{
			label = "a PlayerLeft naming a player who is not seated, in a Round below quorum",
			event = RoundEndingContract.left("never-seated-p99"),
		},
	}
	for _, case in ignorable do
		Contract.eventIsIgnored(machine, {
			label = case.label,
			state = round,
			event = case.event,
			now = at,
		})
	end

	local ended = machine.step(round, RoundEndingContract.tick(), at)
	local expected = RoundEndingContract.quorumOutcome()
	assert(
		ended.phase == "Resolution" and Deep.equal(ended.outcome, expected),
		`Contract pin 2: the events above are ignored, and the NEXT Tick ends the round - it `
			.. `left the machine in {tostring(ended.phase)} with {Deep.show(ended.outcome)}. `
			.. `Without this half, ignoring everything would satisfy the check`
	)
end

--[[
	Contract pin 1, the half AC-7 does not reach: a `PlayerLeft` in `Round`
	naming somebody who is NOT seated is an ordinary ignored event.

	GREEN ON ARRIVAL against the real machine, which ignores every mid-round
	departure today, so it is earned by a reverted `scripts/mutate.sh` probe -
	see the story's `## Regressions`, probe 2, which makes the `PlayerLeft`
	branch unseat seat 1 outside the Lobby and watches this go red.
]]
function RoundEndingContract.aLeaveNamingSomebodyNotSeatedIsIgnoredInRound(
	machine: any,
	config: any
)
	local round = RoundEndingContract.roundOf(machine, config, config.playersMin)
	local at = round.phaseEnteredAt + 1
	assert(
		at - round.phaseEnteredAt < config.roundSeconds,
		`fixture: the leave at {at} is roundSeconds ({config.roundSeconds}) or more after the `
			.. `Round was entered at {round.phaseEnteredAt}`
	)

	Contract.eventIsIgnored(machine, {
		label = "a PlayerLeft naming never-seated-p99, in Round",
		state = round,
		event = RoundEndingContract.left("never-seated-p99"),
		now = at,
	})
end

return RoundEndingContract
