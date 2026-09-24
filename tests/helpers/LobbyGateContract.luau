--!strict
--[[
	ROUND-004 AC-1 to AC-6 written once, as checks over a MACHINE rather than
	over a module - the same arrangement as `PhaseMachineContract.luau`, and for
	the same reason.

	`tests/server/lobby_gate_test.luau` applies these to the real
	`src/server/round/PhaseMachine.luau`.
	`tests/server/lobby_gate_controls_test.luau` applies them to the deliberately
	wrong lobbies in `LobbyGateStubs.luau`, so that every check here has been
	OBSERVED rejecting the implementation the criterion names - AC-2's control is
	written into the criterion itself - and observed ACCEPTING a lobby that holds.
	A check nobody has seen refuse anything is not a check.

	EVERY THRESHOLD IS READ OUT OF THE CONFIG IT IS HANDED. `players_min` 4 and
	`players_max` 6 are derived and ratified (`docs/wiki/game/tuning.md` section 1,
	product-brief section 0c R1) and there is nothing here to calibrate; but
	`players_max` is soft (the story's `## Game design`, M3 / playtest P-N), so a
	literal 6 in an assertion is a test that breaks the day a playtest moves the
	number in `tuning.md`. Nothing below writes 4 or 6, and the two places that
	need a SHAPE rather than a value - AC-5 needs a seat count strictly between
	the two thresholds, AC-6 needs five seats for a middle removal to be
	distinguishable from a swap - say so in an explicit precondition assert that
	names what to do if the design ever stops supplying it.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./PhaseMachineContract")
local Deep = require("./Deep")

local LobbyGateContract = {}

LobbyGateContract.SEED = 20260916
LobbyGateContract.ROUND_ID = "round-ROUND-004-a"
-- TEL-002: `initial` takes the driver's session id as its 4th argument.
LobbyGateContract.SESSION_ID = "session-ROUND-004-a"

function LobbyGateContract.joined(playerId: string): any
	return { kind = "PlayerJoined", playerId = playerId }
end

function LobbyGateContract.left(playerId: string): any
	return { kind = "PlayerLeft", playerId = playerId }
end

function LobbyGateContract.tick(): any
	return { kind = "Tick" }
end

-- `p1` .. `pN`, which is also the join order every check below expects back.
function LobbyGateContract.roster(count: number): { string }
	local ids: { string } = {}
	for index = 1, count do
		table.insert(ids, `p{index}`)
	end
	return ids
end

--[[
	A fresh Lobby with `count` players seated, entered at 0 and built by DRIVING
	the machine rather than by writing a state down: a state written down is a
	test of my idea of the machine, and a machine that refuses these joins should
	fail on the count assert here rather than mysteriously four lines later.
]]
function LobbyGateContract.lobbyOf(machine: any, config: any, count: number): any
	local state = machine.initial(
		config,
		LobbyGateContract.SEED,
		LobbyGateContract.ROUND_ID,
		LobbyGateContract.SESSION_ID
	)
	for _, id in LobbyGateContract.roster(count) do
		state = machine.step(state, LobbyGateContract.joined(id), 0)
	end
	assert(
		typeof(state) == "table" and #state.players == count,
		`fixture: seating {count} player(s) into a fresh Lobby produced `
			.. `{Deep.show(if typeof(state) == "table" then state.players else state)}`
	)
	return state
end

local function occurrences(players: { string }, playerId: string): number
	local seen = 0
	for _, id in players do
		if id == playerId then
			seen += 1
		end
	end
	return seen
end

--[[
	Is `candidate` a subsequence of `order` - the same members in the same
	relative order, with anything at all removed?

	This is AC-6 stated exactly. A membership test or a length test is satisfied
	by `LobbyGateStubs.swapping`, which is a correct SET removal; only relative
	order sees it.
]]
local function isSubsequenceOf(candidate: { string }, order: { string }): boolean
	local wanted = 1
	for _, id in order do
		if wanted <= #candidate and candidate[wanted] == id then
			wanted += 1
		end
	end
	return wanted > #candidate
end

--[[
	AC-1: a lobby one short of `playersMin`, with the clock run well past
	`lobbySeconds`, is still in Lobby and has emitted nothing.

	The effect half matters on its own: a machine that emits `AssignSeats` for a
	round it did not start hands the driver a ring of three.
]]
function LobbyGateContract.lobbyHoldsBelowMinimum(machine: any, config: any)
	local short = config.playersMin - 1
	local state = LobbyGateContract.lobbyOf(machine, config, short)

	local wellPast = config.lobbySeconds * 5
	local after, effects = machine.step(state, LobbyGateContract.tick(), wellPast)

	assert(
		after.phase == "Lobby",
		`AC-1: {short} player(s) is one short of playersMin ({config.playersMin}), and at `
			.. `now = {wellPast} - {wellPast / config.lobbySeconds} times lobbySeconds `
			.. `({config.lobbySeconds}) since the Lobby was entered at 0 - the phase is `
			.. `{tostring(after.phase)}. The clock is a FLOOR on lobby dwell time, not the `
			.. `only condition for starting a round`
	)
	assert(
		#effects == 0,
		`AC-1: a lobby of {short}, below playersMin ({config.playersMin}), emitted `
			.. `{Deep.show(Deep.kinds(effects))} at now = {wellPast}. A round that did not `
			.. `start emits nothing`
	)
end

--[[
	AC-2, and the one criterion in this story a wrong implementation passes half
	of: the lobby timer HOLDS.

	The lobby is held short of `playersMin` until well past `lobbySeconds`, the
	missing player joins, and the round starts on the NEXT TICK - a quarter of a
	lobbySeconds later, which is the whole point. The `now` at which it starts is
	asserted, not merely that it starts: an implementation that stamps
	`phaseEnteredAt` on every join also starts a round eventually, one full
	`lobbySeconds` after the join, and "it eventually starts" cannot tell the two
	apart. See `LobbyGateStubs.resetting`, which is that implementation.
]]
function LobbyGateContract.roundStartsOnTheTickAfterReachingMinimum(machine: any, config: any)
	local state = LobbyGateContract.lobbyOf(machine, config, config.playersMin - 1)
	local enteredAt = state.phaseEnteredAt

	local joinAt = config.lobbySeconds * 3
	local gap = config.lobbySeconds / 4
	local nextTick = joinAt + gap
	assert(
		nextTick < joinAt + config.lobbySeconds,
		`fixture: the tick after the join is {nextTick}, which is not inside the `
			.. `{config.lobbySeconds} seconds a resetting implementation would make the lobby `
			.. `serve again. The test cannot distinguish hold from reset`
	)

	local held = machine.step(state, LobbyGateContract.tick(), joinAt)
	assert(
		held.phase == "Lobby",
		`AC-2 (precondition, AC-1): at now = {joinAt} with {config.playersMin - 1} player(s) `
			.. `the phase is {tostring(held.phase)}; the lobby must still be holding when the `
			.. `last player arrives or there is no held time to discard`
	)

	local last = `p{config.playersMin}`
	local afterJoin = machine.step(held, LobbyGateContract.joined(last), joinAt)
	assert(
		#afterJoin.players == config.playersMin,
		`AC-2: after {last} joined, {#afterJoin.players} player(s) are seated and playersMin is `
			.. `{config.playersMin}: {Deep.show(afterJoin.players)}`
	)

	local started, effects = machine.step(afterJoin, LobbyGateContract.tick(), nextTick)

	assert(
		started.phase == "Assignment",
		`AC-2: the lobby was entered at {enteredAt}, held past lobbySeconds `
			.. `({config.lobbySeconds}) with {config.playersMin - 1} player(s), reached `
			.. `playersMin ({config.playersMin}) at now = {joinAt}, and at the next tick `
			.. `(now = {nextTick}) the phase is {tostring(started.phase)}. The {joinAt} seconds `
			.. `already served are not discarded by a join: a machine still waiting here is one `
			.. `that restamped phaseEnteredAt and is serving another {config.lobbySeconds}`
	)
	assert(
		started.phaseEnteredAt == nextTick,
		`AC-2: the round started, but Assignment records phaseEnteredAt = `
			.. `{tostring(started.phaseEnteredAt)} and the tick that started it was at `
			.. `{nextTick}. AC-2 asserts the TIME the round starts, because "it eventually `
			.. `starts" is true of a resetting lobby too`
	)
	assert(
		afterJoin.phaseEnteredAt == enteredAt,
		`AC-2: the join rewrote phaseEnteredAt from {enteredAt} to `
			.. `{tostring(afterJoin.phaseEnteredAt)}. phaseEnteredAt is never rewritten by a `
			.. `join - that one line is the hold`
	)
	assert(
		#effects == 1 and effects[1].kind == "AssignSeats",
		`AC-2: starting the round emitted {Deep.show(Deep.kinds(effects))}, wanted exactly one `
			.. `AssignSeats`
	)
end

--[[
	AC-3: a departure below `playersMin` holds the lobby, and restoring the count
	starts the round on the next tick.

	Both halves are load-bearing and they fail for different reasons. The first
	needs `PlayerLeft` to unseat at all - today it is ignored in every phase. The
	second needs the HOLD again: the restored lobby must not be made to serve
	another `lobbySeconds`, which is the same defect AC-2 names arriving by a
	different route.
]]
function LobbyGateContract.lobbyHoldsWhenTheCountFallsAndStartsWhenRestored(
	machine: any,
	config: any
)
	local full = LobbyGateContract.lobbyOf(machine, config, config.playersMin)
	local enteredAt = full.phaseEnteredAt

	local leaveAt = config.lobbySeconds / 2
	assert(
		leaveAt < config.lobbySeconds,
		`fixture: the departure at {leaveAt} is not before lobbySeconds ({config.lobbySeconds})`
	)
	local short = machine.step(full, LobbyGateContract.left("p2"), leaveAt)
	assert(
		#short.players == config.playersMin - 1,
		`AC-3: p2 left a lobby of {config.playersMin} at now = {leaveAt} and `
			.. `{#short.players} player(s) are seated: {Deep.show(short.players)}. A player who `
			.. `leaves the LOBBY is unseated (Contract pin 2; a departure in any other phase is `
			.. `ROUND-005 and stays ignored)`
	)

	local wellPast = config.lobbySeconds * 5
	local stillLobby, heldEffects = machine.step(short, LobbyGateContract.tick(), wellPast)
	assert(
		stillLobby.phase == "Lobby",
		`AC-3: the count fell to {config.playersMin - 1}, one short of playersMin `
			.. `({config.playersMin}), and at now = {wellPast} the phase is `
			.. `{tostring(stillLobby.phase)}. A lobby that dropped below the minimum does not `
			.. `start a round just because the clock is past lobbySeconds`
	)
	assert(
		#heldEffects == 0,
		`AC-3: the held lobby emitted {Deep.show(Deep.kinds(heldEffects))} at now = {wellPast}`
	)

	local replacement = `p{config.playersMin + 1}`
	local restored = machine.step(stillLobby, LobbyGateContract.joined(replacement), wellPast)
	assert(
		#restored.players == config.playersMin,
		`AC-3: {replacement} joined to restore the count and {#restored.players} player(s) are `
			.. `seated: {Deep.show(restored.players)}`
	)
	assert(
		restored.phaseEnteredAt == enteredAt,
		`AC-3: restoring the count rewrote phaseEnteredAt from {enteredAt} to `
			.. `{tostring(restored.phaseEnteredAt)}; neither a join nor a leave touches it`
	)

	local nextTick = wellPast + config.lobbySeconds / 4
	local started = machine.step(restored, LobbyGateContract.tick(), nextTick)
	assert(
		started.phase == "Assignment",
		`AC-3: the count was restored at now = {wellPast} and at the next tick `
			.. `(now = {nextTick}) the phase is {tostring(started.phase)}. The restored lobby `
			.. `has served {nextTick} seconds against a lobbySeconds of {config.lobbySeconds} `
			.. `and must not be made to serve another one`
	)
	assert(
		started.phaseEnteredAt == nextTick,
		`AC-3: Assignment records phaseEnteredAt = {tostring(started.phaseEnteredAt)}, and the `
			.. `tick that started the round was at {nextTick}`
	)
end

--[[
	AC-4: a join into a lobby already holding `playersMax` leaves exactly
	`playersMax` seated and the surplus player unseated.

	Three assertions, in this order, because each catches an implementation the
	one before it lets through: the LENGTH catches an unconditional append; WHO
	catches `LobbyGateStubs.evicting`, which throws the longest-seated player out
	to make room and is exactly `playersMax` long afterwards; the whole LIST
	catches a reordering. Then `eventIsIgnored` pins Contract pin 3 - a refusal is
	indistinguishable from any other ignored event, with nothing raised, nothing
	emitted and nothing mutated.
]]
function LobbyGateContract.fullLobbyRefusesTheSurplusJoin(machine: any, config: any)
	local expected = LobbyGateContract.roster(config.playersMax)
	local full = LobbyGateContract.lobbyOf(machine, config, config.playersMax)
	assert(
		Deep.equal(full.players, expected),
		`fixture: a lobby seated with playersMax ({config.playersMax}) players holds `
			.. `{Deep.show(full.players)}, wanted {Deep.show(expected)}`
	)

	local surplus = `p{config.playersMax + 1}`
	local after, effects = machine.step(full, LobbyGateContract.joined(surplus), 1)

	assert(
		#after.players == config.playersMax,
		`AC-4: {surplus} joined a lobby already holding playersMax ({config.playersMax}) and `
			.. `{#after.players} player(s) are now seated: {Deep.show(after.players)}. Rejecting `
			.. `the surplus join at the door is the machine's job, not the driver's`
	)
	assert(
		occurrences(after.players, surplus) == 0,
		`AC-4: the lobby is still {config.playersMax} long but {surplus} is among them: `
			.. `{Deep.show(after.players)}. Somebody already seated was evicted to make room, `
			.. `which a length check alone cannot see`
	)
	assert(
		Deep.equal(after.players, expected),
		`AC-4: the refused join changed the seated list:\n{Deep.diff(expected, after.players)}`
	)
	assert(#effects == 0, `AC-4: a refused join emitted {Deep.show(Deep.kinds(effects))}`)

	Contract.eventIsIgnored(machine, {
		label = `a PlayerJoined into a lobby already holding playersMax ({config.playersMax})`,
		state = full,
		event = LobbyGateContract.joined(surplus),
		now = 1,
	})
end

--[[
	AC-5: the same `PlayerJoined` applied twice seats that player once, in a
	lobby at NEITHER threshold.

	ROUND-003 already pins this for a lobby of exactly `playersMin`
	("AC-7: a duplicate PlayerJoined does not seat the same player twice"). The
	value this adds is the seat count: strictly between `playersMin` and
	`playersMax`, so neither the count gate nor the cap can be what refused the
	second join, and only the duplicate guard can.
]]
function LobbyGateContract.duplicateJoinSeatsOnce(machine: any, config: any)
	local seats = config.playersMin + 1
	assert(
		seats < config.playersMax,
		`fixture: this check needs a seat count strictly between playersMin `
			.. `({config.playersMin}) and playersMax ({config.playersMax}), so that neither `
			.. `threshold can be what refuses the duplicate. There is none. If a playtest has `
			.. `narrowed the band to adjacent values, AC-5 needs an Amendments decision about `
			.. `what "not at a boundary" now means - it is not a number to edit here`
	)

	local base = LobbyGateContract.lobbyOf(machine, config, config.playersMin)
	local newcomer = `p{seats}`

	local once = machine.step(base, LobbyGateContract.joined(newcomer), 1)
	assert(
		#once.players == seats
			and #once.players > config.playersMin
			and #once.players < config.playersMax,
		`AC-5: the fixture must be at neither threshold before the duplicate arrives; `
			.. `{#once.players} player(s) are seated against playersMin {config.playersMin} and `
			.. `playersMax {config.playersMax}: {Deep.show(once.players)}`
	)

	local twice, effects = machine.step(once, LobbyGateContract.joined(newcomer), 2)

	assert(
		occurrences(twice.players, newcomer) == 1,
		`AC-5: the same PlayerJoined for {newcomer} was applied twice and {newcomer} appears `
			.. `{occurrences(twice.players, newcomer)} time(s): {Deep.show(twice.players)}. `
			.. `Seating one player twice puts them in two seats of the same ring`
	)
	assert(
		Deep.equal(twice.players, once.players),
		`AC-5: the duplicate join changed the seated list:\n`
			.. Deep.diff(once.players, twice.players)
	)
	assert(#effects == 0, `AC-5: a duplicate join emitted {Deep.show(Deep.kinds(effects))}`)

	Contract.eventIsIgnored(machine, {
		label = `a duplicate PlayerJoined for {newcomer}, in a lobby of {#once.players} `
			.. `(playersMin {config.playersMin}, playersMax {config.playersMax})`,
		state = once,
		event = LobbyGateContract.joined(newcomer),
		now = 2,
	})
end

--[[
	AC-6: joins and leaves in any order leave the seated list a SUBSEQUENCE of
	the join order.

	The sequence is built to catch the one wrong implementation the story names
	(Contract pin 4): copy the last element over the hole and shorten. That is a
	correct set removal and scrambles the ring SEAT-001 deals, so it is invisible
	to a length check, invisible to a membership check, and invisible to a
	removal from the END of the list. The sequence therefore removes from the
	MIDDLE of five (p3 out of p1..p5), then from the FRONT of five, and only then
	from the back - the last one distinguishes nothing and is here to say so.

	The sequence never seats more than five, so AC-4's cap is never what shapes
	the outcome and a failure here is about ORDER. No `Tick` is applied either,
	so no clock semantics are in play and the `now` values are step indices.
]]
function LobbyGateContract.removalPreservesJoinOrder(machine: any, config: any)
	assert(
		config.playersMax >= 5,
		`fixture: this check seats five players so that a removal from the MIDDLE of five is `
			.. `distinguishable from a swap-with-the-last, and playersMax is `
			.. `{config.playersMax}. A band that cannot hold five needs an Amendments decision `
			.. `about how AC-6 is falsified, not a shorter sequence here`
	)

	local joinOrder = LobbyGateContract.roster(8)
	local script: { { any } } = {
		{ "join", "p1" },
		{ "join", "p2" },
		{ "join", "p3" },
		{ "join", "p4" },
		{ "join", "p5" }, -- five seated: {p1, p2, p3, p4, p5}
		{ "leave", "p3" }, -- from the MIDDLE: a swap would leave {p1, p2, p5, p4}
		{ "join", "p6" },
		{ "leave", "p1" }, -- from the FRONT: a swap would leave {p6, p2, p4, p5}
		{ "join", "p7" },
		{ "leave", "p7" }, -- from the BACK: a swap is indistinguishable here
		{ "join", "p8" },
	}
	local expected = { "p2", "p4", "p5", "p6", "p8" }

	local state = machine.initial(
		config,
		LobbyGateContract.SEED,
		LobbyGateContract.ROUND_ID,
		LobbyGateContract.SESSION_ID
	)
	local trail: { string } = {}
	for index, entry in script do
		local action, playerId = entry[1] :: string, entry[2] :: string
		local event = if action == "join"
			then LobbyGateContract.joined(playerId)
			else LobbyGateContract.left(playerId)
		state = machine.step(state, event, index)
		table.insert(trail, `{action} {playerId} -> [{table.concat(state.players, " ")}]`)
	end

	--[[
		Both messages are kept under about 480 characters ON PURPOSE. Luau
		truncates an `assert` message at roughly 500, position prefix included -
		measured on this suite in RED, where the first draft of the message below
		was cut off mid-trail and took the evidence with it. Hence the compact
		`[p1 p2]` rendering rather than `Deep.show`, and the explanation living in
		the second assert rather than being repeated in the first.
	]]
	assert(
		Deep.equal(state.players, expected),
		`AC-6: the seated list is [{table.concat(state.players, " ")}], wanted `
			.. `[{table.concat(expected, " ")}]; removal preserves join order (Contract pin 4).\n`
			.. `The sequence was:\n{table.concat(trail, "\n")}`
	)
	assert(
		isSubsequenceOf(state.players, joinOrder),
		`AC-6: [{table.concat(state.players, " ")}] is not a subsequence of the join order `
			.. `[{table.concat(joinOrder, " ")}] - the same members in the same relative order. `
			.. `Seat order is join order and SEAT-001 deals the ring from this list; a removal `
			.. `that copies the last element over the hole is a correct SET removal, and relative `
			.. `order is the only thing that sees it`
	)
end

--[[
	ROUND-003 AC-6 applied to the path this story adds: a `PlayerLeft` that
	unseats a player must not mutate the state it was handed.

	The non-mutation check comes first so that `LobbyGateStubs.mutatingRemover` -
	which removes the right player, preserves the order of the rest, and returns
	a list correct in every respect, in place - fails with the message the
	criterion names rather than with a downstream confusion.
]]
function LobbyGateContract.leaveDoesNotMutateItsInput(machine: any, config: any)
	local state = LobbyGateContract.lobbyOf(machine, config, config.playersMin)
	local case: Contract.Case = {
		label = "a PlayerLeft unseating a seated player in Lobby",
		state = state,
		event = LobbyGateContract.left("p2"),
		now = 1,
	}

	Contract.stepDoesNotMutateItsInput(machine, case)

	local after = machine.step(state, case.event, case.now)
	assert(
		occurrences(after.players, "p2") == 0 and #after.players == config.playersMin - 1,
		`AC-3/AC-6: the leave returned {Deep.show(after.players)} from a lobby of `
			.. `{config.playersMin}; p2 was seated and must be gone. A step that does not `
			.. `mutate its input because it does nothing at all satisfies the check above `
			.. `vacuously, and this is the assertion that stops it`
	)
end

return LobbyGateContract
