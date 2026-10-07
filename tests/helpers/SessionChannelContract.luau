--!strict
--[[
	SLICE-006 AC-1..AC-6 and the story's Contract pins (C-2, C-4..C-9),
	written once as checks over a SESSION MODULE handed in as a parameter -
	the `SessionRoundContract` arrangement, for the same reason: in RED the
	real module lacks every behaviour below (no ports, no channel, no lens
	sends, no FacilityView), so `tests/server/session_channel_test.luau`
	fails before any assertion here has been seen to accept or reject
	anything, and `tests/server/session_channel_controls_test.luau` is where
	each check is EXECUTED against a reference stand-in and stand-ins wrong
	in exactly one way.

	THE ORACLE IS THE PURE MODULES THEMSELVES, CALLED HERE, INDEPENDENTLY.
	The expected lens view after a step is `Projection.lensFor` on the END
	state, the expected cues `Projection.turnCuesFor`, the expected ping
	state `Pings.accept` / `Pings.shown`, the expected preset log
	`PresetSends.send`, the expected facility view `RoundView.facility`; a
	send is expected exactly when the view differs from the last one this
	file saw expected (C-6). Nothing below reads an expected value off the
	session's own output.

	THE ORACLE PARTITION (story `## Contract`). MECHANICAL, pinned exactly:
	AC-1, AC-3, AC-4, AC-5, AC-6 (per payload kind, from an allowlist - never
	"a number equal to a required setting"), C-2 and C-9. SETTLED with a
	control: AC-2 - `ShownRound.play` wins every round over SEEDS seeds at
	each n, and with `pings = false` loses every one to the clock without a
	single turn. Every constant is READ from `MechanicsTuning` and
	`RoundConfig.fromTuning(Tuning)`; the literals below are seeds, player
	names, preset ids from `Presets.ALL` and a filtered text.

	Every message names its criterion, because the controls assert on the text.
]]

local Contract = require("./Contract")
local Deep = require("./Deep")
local MechanicsTuning = require("../../src/shared/MechanicsTuning")
local Pings = require("../../src/server/channel/Pings")
local PresetSends = require("../../src/server/channel/PresetSends")
local Presets = require("../../src/shared/channel/Presets")
local Projection = require("../../src/server/seats/Projection")
local Ring = require("../../src/server/seats/Ring")
local RoundView = require("../../src/server/round/RoundView")
local ScriptedRound = require("./ScriptedRound")
local SessionRoundContract = require("./SessionRoundContract")
local ShownRound = require("./ShownRound")

local SessionChannelContract = {}

export type Session = any
type Vec = ScriptedRound.Vec

SessionChannelContract.SEEDS = SessionRoundContract.SEEDS -- 50
SessionChannelContract.PLAYER_COUNTS = SessionRoundContract.PLAYER_COUNTS -- { 4, 5, 6 }
-- The control clocks out a whole round per seed (420 simulated seconds), so
-- it runs fewer: three seeds at each n, as the story's partition allows.
SessionChannelContract.CONTROL_SEEDS = { 1, 2, 3 }
-- AC-6 reads every effect of a full round; three seeds at each n.
SessionChannelContract.SECRET_SEEDS = { 1, 2, 3 }
SessionChannelContract.N = 4

SessionChannelContract.PORTS = ScriptedRound.PORTS
SessionChannelContract.SEND_TO_KEYS = { "kind", "payload", "payloadKind", "playerId" }
SessionChannelContract.BROADCAST_KEYS = { "kind", "payload", "payloadKind" }
SessionChannelContract.PRIVATE_KINDS = { "LensView", "TurnCues" }
SessionChannelContract.PUBLIC_BROADCAST_KINDS = { "RoundView", "FacilityView", "PresetShown" }
-- AC-6's allowlist: the key set each private payload kind may carry.
SessionChannelContract.PRIVATE_PAYLOAD_KEYS = {
	SeatView = { "dependentId", "keyClasses", "lensClass", "playerId", "seatOrder", "supplierId" },
	LensView = { "readings" },
	TurnCues = { "live", "next" },
	TurnResult = { "kind", "machineId", "reason" }, -- reason optional
	PingRefused = { "reason" },
	PresetFailed = { "presetId", "reason" },
}

local SEAT_VIEW_KEYS = SessionChannelContract.PRIVATE_PAYLOAD_KEYS.SeatView

-- Preset ids by key, read from the frozen table rather than restated.
local function presetId(key: string): number
	for _, preset in Presets.ALL do
		if preset.key == key then
			return preset.id
		end
	end
	error(`no preset has key {key}`, 0)
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
SessionChannelContract.keysOf = keysOf

local function contains(list: { string }, item: string): boolean
	return table.find(list, item) ~= nil
end

local function ofKind(effects: { any }, kind: string, payloadKind: string?): { any }
	local out: { any } = {}
	for _, e in effects do
		if
			typeof(e) == "table"
			and e.kind == kind
			and (payloadKind == nil or e.payloadKind == payloadKind)
		then
			table.insert(out, e)
		end
	end
	return out
end
SessionChannelContract.ofKind = ofKind

local function fewProblems(criterion: string, headline: string, problems: { string })
	if #problems > 0 then
		Contract.fail(`{criterion}: {headline}:\n{Contract.firstFew(problems, 10)}`)
	end
end

local function requireModule(criterion: string, S: any)
	if typeof(S) ~= "table" then
		Contract.fail(`{criterion}: Session is {Deep.show(S)}, not a module table`)
	end
	for _, name in { "new", "step" } do
		if typeof(S[name]) ~= "function" then
			Contract.fail(`{criterion}: Session.{name} is {typeof(S[name])}, expected a function`)
		end
	end
end

-- The labels of a step's effects, by `SessionRoundContract.rankOf` (C-9).
local function labelsOf(effects: { any }): { string }
	local out: { string } = {}
	for _, e in effects do
		local _, label = SessionRoundContract.rankOf(e)
		table.insert(out, label)
	end
	return out
end
SessionChannelContract.labelsOf = labelsOf

-- C-9 on one step: every effect a named kind, ranks non-decreasing, at most
-- one RoundView and it last.
local function expectOrdered(
	criterion: string,
	problems: { string },
	label: string,
	effects: { any }
)
	local last = 0
	local roundViews = 0
	for i, e in effects do
		local rank, name = SessionRoundContract.rankOf(e)
		if rank == nil then
			table.insert(
				problems,
				`{criterion}: "{label}": effect #{i} is {name}, not a kind the Contract names (C-9)`
			)
			continue
		end
		if rank < last then
			table.insert(
				problems,
				`{criterion}: "{label}": {name} at #{i} comes after a later-ordered effect ({Deep.show(
					labelsOf(effects)
				)}); C-9's order is pass-through, Placed, SeatView, FacilityView, the reply, PresetShown, LensView/TurnCues, RoundView`
			)
		end
		last = math.max(last, rank)
		if name == "RoundView" then
			roundViews += 1
			if i ~= #effects then
				table.insert(
					problems,
					`{criterion}: "{label}": the RoundView at #{i} of {#effects} is not last (C-9)`
				)
			end
		end
	end
	if roundViews > 1 then
		table.insert(problems, `{criterion}: "{label}": {roundViews} RoundViews, at most one (C-6)`)
	end
end
SessionChannelContract.expectOrdered = expectOrdered

-- Does `value` carry a private view, by shape, at any depth up to `depth`?
-- A `readings` key is a LensView's; `live` and `next` together are TurnCues'.
local function looksLikePrivateView(value: any, depth: number?): boolean
	local remaining = if depth == nil then 4 else depth
	if typeof(value) ~= "table" or remaining < 0 then
		return false
	end
	if value.readings ~= nil or (value.live ~= nil and value["next"] ~= nil) then
		return true
	end
	for _, item in pairs(value :: { [any]: any }) do
		if looksLikePrivateView(item, remaining - 1) then
			return true
		end
	end
	return false
end
SessionChannelContract.looksLikePrivateView = looksLikePrivateView

-- AC-1's last clause on one step: no Broadcast carries a LensView or
-- TurnCues, by kind or by shape.
local function expectNoPrivateBroadcast(
	criterion: string,
	problems: { string },
	label: string,
	effects: { any }
)
	for _, e in ofKind(effects, "Broadcast") do
		if contains(SessionChannelContract.PRIVATE_KINDS, tostring(e.payloadKind)) then
			table.insert(
				problems,
				`{criterion}: "{label}": a Broadcast has payloadKind {Deep.show(e.payloadKind)}; a lens view or turn cues go by SendTo only`
			)
		elseif looksLikePrivateView(e.payload) then
			table.insert(
				problems,
				`{criterion}: "{label}": a Broadcast ({Deep.show(e.payloadKind)}) carries a private view by shape (a readings key, or live and next): {Deep.show(
					e.payload
				)}`
			)
		end
	end
end

-- A driver through the deal, raising through Contract.fail on the criterion.
local function start(
	criterion: string,
	S: Session,
	seed: number,
	n: number,
	options: ScriptedRound.Options?
): (ScriptedRound.Driver, { any })
	requireModule(criterion, S)
	local ok, d, effects = pcall(ScriptedRound.start, S, seed, n, options)
	if not ok then
		Contract.fail(
			`{criterion}: the session could not be dealt (seed {seed}, n = {n}): {tostring(d)}`
		)
	end
	return d, effects
end

-- A fresh, joined driver still in Lobby.
local function lobby(criterion: string, S: Session, seed: number, n: number): ScriptedRound.Driver
	requireModule(criterion, S)
	local ok, d = pcall(function()
		local driver = ScriptedRound.new(S, seed, n)
		ScriptedRound.join(driver)
		return driver
	end)
	if not ok then
		Contract.fail(`{criterion}: the session could not be joined (seed {seed}): {tostring(d)}`)
	end
	return d
end

-- The machine `tracks[track][index]`, its turner and its helper.
local function unit(d: ScriptedRound.Driver, track: number, index: number): (any, string, string)
	local facility = d.state.facility
	local id = facility.steps.tracks[track][index]
	local m = ScriptedRound.machineOf(facility, id)
	local turner = ScriptedRound.turnerOf(d.state.assignment, m)
	return m, turner, ScriptedRound.helperOf(d.state.assignment, turner)
end

local function horizontal(a: Vec, b: Vec): number
	local dx = b.x - a.x
	local dz = b.z - a.z
	return math.sqrt(dx * dx + dz * dz)
end

-- `ScriptedRound.walk`, with every step (Tick and PositionsSampled) handed
-- to `onStep` as it happens, so a check can judge each one.
local function walkRecording(
	d: ScriptedRound.Driver,
	targets: { [string]: Vec },
	onStep: (label: string, effects: { any }) -> ()
)
	local speed = d.tuning.instance.walk_speed_studs_per_second
	local pending = 0
	for p, goal in targets do
		if horizontal(d.positions[p], goal) > 0 then
			pending += 1
		end
	end
	if pending == 0 then
		onStep("a sample with nobody moving", ScriptedRound.sample(d))
		return
	end
	local second = 0
	while pending > 0 do
		second += 1
		onStep(`walk tick {second}`, ScriptedRound.tick(d, 1))
		d.walkSeconds += 1
		pending = 0
		for p, goal in targets do
			local at = d.positions[p]
			local left = horizontal(at, goal)
			if left <= speed then
				d.positions[p] = { x = goal.x, y = goal.y, z = goal.z }
			else
				local f = speed / left
				d.positions[p] = {
					x = at.x + (goal.x - at.x) * f,
					y = goal.y,
					z = at.z + (goal.z - at.z) * f,
				}
				pending += 1
			end
		end
		onStep(`walk sample {second}`, ScriptedRound.sample(d))
	end
end

-- End the round quickly: two leaves at `playersMin` drop it below quorum
-- (`min_players_to_continue`), resolving it in the second step. `keep` are
-- the players who must stay; the leavers are the others, in seat order.
local function dropQuorum(
	d: ScriptedRound.Driver,
	keep: { string },
	onStep: ((label: string, effects: { any }) -> ())?
): { string }
	local leavers: { string } = {}
	for _, p in d.state.assignment.players do
		if not contains(keep, p) and #leavers < 2 then
			table.insert(leavers, p)
		end
	end
	if #leavers ~= 2 then
		error(`dropQuorum: {#leavers} player(s) can leave, need 2`, 0)
	end
	for i, p in leavers do
		d.now += 1
		local effects = ScriptedRound.step(d, { kind = "PlayerLeft", playerId = p })
		if onStep ~= nil then
			onStep(`{p} leaves ({i} of 2)`, effects)
		end
	end
	return leavers
end

-- The private sends of a step, in order: { playerId, payloadKind, payload }.
local function privateViewsOf(
	effects: { any }
): { { playerId: string, payloadKind: string, payload: any } }
	local out = {}
	for _, e in effects do
		if
			typeof(e) == "table"
			and e.kind == "SendTo"
			and contains(SessionChannelContract.PRIVATE_KINDS, tostring(e.payloadKind))
		then
			table.insert(
				out,
				{ playerId = e.playerId, payloadKind = e.payloadKind, payload = e.payload }
			)
		end
	end
	return out
end

--[[ ------------------------------------------------------------------------
     C-2: the signature and the initial state.
     --------------------------------------------------------------------- ]]

function SessionChannelContract.newRequiresPortsAndHoldsAFreshChannelSentAndPorts(S: Session)
	requireModule("C-2", S)
	local config = ScriptedRound.config()
	local problems: { string } = {}
	local without = {
		{ "no fifth argument", nil },
		{ "an empty table", {} },
		{ "a lineOfSight that is not a function", { lineOfSight = true } },
	}
	for _, case in without do
		local ok, result = pcall(S.new, config, 1, "r", "s", case[2])
		if ok then
			table.insert(
				problems,
				`Session.new with {case[1]} as ports returned {if typeof(result) == "table"
					then "a state"
					else Deep.show(result)}; C-2 says it RAISES (a defaulted sight would read through walls)`
			)
		end
	end
	local ok, state = pcall(S.new, config, 1, "r", "s", SessionChannelContract.PORTS)
	if not ok then
		Contract.fail(`C-2: Session.new with ports RAISED: {tostring(state)}`)
	end
	local wantChannel = { presets = PresetSends.new(), pings = Pings.new() }
	if not Deep.equal(state.channel, wantChannel) then
		table.insert(
			problems,
			`state.channel from new is {Deep.show(state.channel)}, expected \{ presets = PresetSends.new(), pings = Pings.new() } = {Deep.show(
				wantChannel
			)}`
		)
	end
	if typeof(state.sent) ~= "table" then
		table.insert(problems, `state.sent from new is {Deep.show(state.sent)}, expected a table`)
	else
		if state.sent.roundView ~= nil then
			table.insert(
				problems,
				`state.sent.roundView from new is {Deep.show(state.sent.roundView)}, expected nil`
			)
		end
		if not Deep.equal(state.sent.lens, {}) or not Deep.equal(state.sent.cues, {}) then
			table.insert(
				problems,
				`state.sent from new holds lens {Deep.show(state.sent.lens)} and cues {Deep.show(
					state.sent.cues
				)}, expected \{} and \{}`
			)
		end
		if not Deep.equal(keysOf(state.sent), { "cues", "lens" }) then
			table.insert(
				problems,
				`state.sent from new has keys {Deep.show(keysOf(state.sent))}, expected exactly cues and lens (roundView absent while nil)`
			)
		end
	end
	if
		typeof(state.ports) ~= "table"
		or state.ports.lineOfSight ~= SessionChannelContract.PORTS.lineOfSight
	then
		table.insert(
			problems,
			`state.ports from new is {Deep.show(state.ports)}, expected the ports as given (the same lineOfSight function)`
		)
	end
	-- options sixth: the predicate still reaches the generator.
	local okRun, d = pcall(function()
		local driver = ScriptedRound.new(S, 1, SessionChannelContract.N, {
			generatorPredicate = SessionRoundContract.refuseAll,
		})
		ScriptedRound.join(driver)
		ScriptedRound.tickAt(driver, driver.config.lobbySeconds)
		return driver
	end)
	if not okRun then
		table.insert(
			problems,
			`a session built with options sixth could not be driven to the deal: {tostring(d)}`
		)
	elseif d.state.round.phase ~= "Resolution" or d.state.facility ~= nil then
		table.insert(
			problems,
			`with options.generatorPredicate refusing every attempt (sixth argument) the deal left the phase at {Deep.show(
				d.state.round.phase
			)} with facility {if d.state.facility then "held" else "nil"}, expected Resolution with none - the options are not being read from the sixth argument`
		)
	end
	fewProblems(
		"C-2",
		"Session.new(config, seed, roundId, sessionId, ports, options?) must raise without ports.lineOfSight and hold a fresh channel, an empty sent and the ports",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     AC-1, C-6: the private views, exactly when they change.
     --------------------------------------------------------------------- ]]

--[[
	Over a scripted sequence (deal; ticks; the helper of T1[1] walking to it,
	sample by sample; the turner walking; the commit; a leave; a sample with
	nobody moving): after EVERY step the private sends are exactly those the
	oracle expects - for each seated player in seat order, a LensView iff
	`Projection.lensFor` on the end state differs from the last one expected,
	then TurnCues iff `turnCuesFor` differs - payload for payload. The first
	view after the deal is always sent, even empty (C-6). A player whose
	views did not change gets nothing. The leaver gets nothing, on the leave
	or after, and loses their `sent` entries. No Broadcast ever carries a
	private view, by kind or by shape.
]]
function SessionChannelContract.sendsEachPlayerTheirOwnLensAndCuesExactlyWhenTheyChange(S: Session)
	local d, dealEffects = start("AC-1", S, 1, SessionChannelContract.N)
	local problems: { string } = {}
	local lastLens: { [string]: any } = {}
	local lastCues: { [string]: any } = {}
	local lensSends, cueSends, silent, aloneSteps = 0, 0, 0, 0
	local leaver: string? = nil

	local function judge(label: string, effects: { any })
		local state = d.state
		local expected = {}
		if state.round.phase == "Round" and state.procedure ~= nil and state.assignment ~= nil then
			local lens: { [string]: any } = {}
			local cues: { [string]: any } = {}
			for _, p in state.assignment.players do
				local lv = Projection.lensFor(
					state.assignment,
					state.procedure,
					p,
					state.positions[p],
					ScriptedRound.sightAlwaysTrue
				)
				local cv = Projection.turnCuesFor(state.assignment, state.procedure, p)
				if not Deep.equal(lv, lastLens[p]) then
					table.insert(expected, { playerId = p, payloadKind = "LensView", payload = lv })
				end
				if not Deep.equal(cv, lastCues[p]) then
					table.insert(expected, { playerId = p, payloadKind = "TurnCues", payload = cv })
				end
				lens[p] = lv
				cues[p] = cv
			end
			lastLens = lens
			lastCues = cues
		end
		local got = privateViewsOf(effects)
		local recipients: { [string]: boolean } = {}
		for _, e in expected do
			if e.payloadKind == "LensView" then
				lensSends += 1
			else
				cueSends += 1
			end
			recipients[e.playerId] = true
		end
		local distinct = 0
		for _ in recipients do
			distinct += 1
		end
		if #expected == 0 then
			silent += 1
		elseif distinct == 1 and #state.assignment.players > 1 then
			aloneSteps += 1
		end
		if #got ~= #expected then
			local gotTo: { string } = {}
			for _, g in got do
				table.insert(gotTo, `{g.payloadKind} -> {g.playerId}`)
			end
			local wantTo: { string } = {}
			for _, e in expected do
				table.insert(wantTo, `{e.payloadKind} -> {e.playerId}`)
			end
			table.insert(
				problems,
				`"{label}": {#got} private send(s) {Deep.show(gotTo)}, expected exactly {#expected} {Deep.show(
					wantTo
				)} - a view goes to its player alone, iff it differs from the last one sent (C-6)`
			)
		else
			for i, e in expected do
				local g = got[i]
				if g.playerId ~= e.playerId or g.payloadKind ~= e.payloadKind then
					table.insert(
						problems,
						`"{label}": private send #{i} is {g.payloadKind} -> {g.playerId}, expected {e.payloadKind} -> {e.playerId} (seat order, lens before cues)`
					)
				elseif not Deep.equal(g.payload, e.payload) then
					table.insert(
						problems,
						`"{label}": the {e.payloadKind} sent to {e.playerId} is not Projection's on the end state:\n{Contract.firstFew(
							string.split(Deep.diff(e.payload, g.payload), "\n"),
							4
						)}`
					)
				end
			end
		end
		for _, e in ofKind(effects, "SendTo") do
			local keys = keysOf(e)
			if not Deep.equal(keys, SessionChannelContract.SEND_TO_KEYS) then
				table.insert(
					problems,
					`"{label}": a SendTo's key set is {Deep.show(keys)}, expected {Deep.show(
						SessionChannelContract.SEND_TO_KEYS
					)}`
				)
			end
			if leaver ~= nil and e.playerId == leaver then
				table.insert(
					problems,
					`"{label}": a {e.payloadKind} was sent to {leaver}, who withdrew; a player no longer seated is never sent another view (C-6)`
				)
			end
		end
		expectNoPrivateBroadcast("AC-1", problems, label, effects)
	end

	judge("DEAL", dealEffects)
	judge("tick after the deal", ScriptedRound.tick(d, 1))
	local m, turner, helper = unit(d, 1, 1)
	local at = ScriptedRound.machinePosition(d, m)
	walkRecording(d, { [helper] = at }, judge)
	judge("tick with the helper at the machine", ScriptedRound.tick(d, 1))
	judge("a sample with nobody moving", ScriptedRound.sample(d))
	walkRecording(d, { [turner] = at }, judge)
	judge("tick with both at the machine", ScriptedRound.tick(d, 1))
	local turn = ScriptedRound.turn(d, turner, m.id, m.requiredSetting)
	if typeof(turn.reply) ~= "table" or turn.reply.kind ~= "committed" then
		Contract.fail(
			`AC-1 precondition: the turn on T1[1] by {turner} replied {Deep.show(turn.reply)}, expected committed`
		)
	end
	judge("the turn that commits T1[1]", turn.effects)
	judge("tick after the commit", ScriptedRound.tick(d, 1))
	for _, p in d.state.assignment.players do
		if p ~= turner and p ~= helper then
			leaver = p
			break
		end
	end
	d.now += 1
	local leaveEffects = ScriptedRound.step(d, { kind = "PlayerLeft", playerId = leaver :: string })
	if d.state.round.phase ~= "Round" then
		Contract.fail(
			`AC-1 precondition: the leave by {leaver} left the phase at {d.state.round.phase}`
		)
	end
	judge(`{leaver} leaves the Round`, leaveEffects)
	if d.state.sent ~= nil and typeof(d.state.sent) == "table" then
		if d.state.sent.lens[leaver] ~= nil or d.state.sent.cues[leaver] ~= nil then
			table.insert(
				problems,
				`after the leave state.sent still holds entries for {leaver}: lens {Deep.show(
					d.state.sent.lens[leaver]
				)}, cues {Deep.show(d.state.sent.cues[leaver])}; a player no longer in assignment.players loses them (C-6)`
			)
		end
	else
		table.insert(
			problems,
			`state.sent is {Deep.show(d.state.sent)} after the leave, expected a table (C-1)`
		)
	end
	judge("tick after the leave", ScriptedRound.tick(d, 1))
	judge("a sample after the leave", ScriptedRound.sample(d))

	print(
		`        [measured] AC-1: {lensSends} LensView and {cueSends} TurnCues sends expected over the sequence; {silent} silent steps; {aloneSteps} steps where one player alone was sent`
	)
	if
		lensSends < SessionChannelContract.N + 1
		or cueSends < SessionChannelContract.N + 1
		or silent < 3
		or aloneSteps < 1
	then
		Contract.fail(
			`AC-1 precondition: {lensSends} lens sends, {cueSends} cue sends, {silent} silent steps, {aloneSteps} single-recipient steps expected; too few to discriminate`
		)
	end
	fewProblems(
		"AC-1",
		"each player alone receives their LensView and TurnCues exactly when they change (the first after the deal always), the leaver never again, and no Broadcast carries either",
		problems
	)
end

--[[
	C-6's reset: on the second deal every seated player is sent a LensView
	and TurnCues again, although at the spawn centre the lens is the same
	empty view round 1 ended with; on entering Lobby `sent.lens` and
	`sent.cues` are `{}`.
]]
function SessionChannelContract.resetsTheSentViewsOnTheDealAndInLobby(S: Session)
	local d = start("C-6", S, 2, SessionChannelContract.N)
	local problems: { string } = {}
	local c = d.config
	local first = d.state.assignment.players
	local leavers = dropQuorum(d, { first[1], first[2] })
	if d.state.round.phase ~= "Resolution" then
		Contract.fail(
			`C-6 precondition: after two leaves the phase is {d.state.round.phase}, not Resolution`
		)
	end
	ScriptedRound.tick(d, 1)
	ScriptedRound.tickAt(d, d.now + c.postRoundSeconds)
	if d.state.round.phase ~= "Lobby" then
		Contract.fail(`C-6 precondition: after Post the phase is {d.state.round.phase}, not Lobby`)
	end
	local sent = d.state.sent
	if typeof(sent) ~= "table" then
		table.insert(
			problems,
			`state.sent is {Deep.show(sent)} in the next Lobby, expected a table`
		)
	elseif not Deep.equal(sent.lens, {}) or not Deep.equal(sent.cues, {}) then
		table.insert(
			problems,
			`on entering Lobby state.sent.lens is {Deep.show(sent.lens)} and sent.cues {Deep.show(
				sent.cues
			)}, expected \{} and \{} (reset with the ring)`
		)
	end
	for _, p in leavers do
		ScriptedRound.step(d, { kind = "PlayerJoined", playerId = p })
	end
	local effects = ScriptedRound.deal(d)
	if d.state.facility == nil then
		Contract.fail("C-6 precondition: the second deal produced no facility")
	end
	local seated = d.state.assignment.players
	local lensTo: { string } = {}
	local cuesTo: { string } = {}
	for _, v in privateViewsOf(effects) do
		if v.payloadKind == "LensView" then
			table.insert(lensTo, v.playerId)
		else
			table.insert(cuesTo, v.playerId)
		end
	end
	if not Deep.equal(lensTo, seated) then
		table.insert(
			problems,
			`on the second deal LensViews went to {Deep.show(lensTo)}, expected every seated player {Deep.show(
				seated
			)} in seat order - the first view of a round is always sent, even one equal to the last round's (sent is reset on the deal)`
		)
	end
	if not Deep.equal(cuesTo, seated) then
		table.insert(
			problems,
			`on the second deal TurnCues went to {Deep.show(cuesTo)}, expected every seated player {Deep.show(
				seated
			)}`
		)
	end
	fewProblems(
		"C-6",
		"sent.lens and sent.cues are reset on the deal and on entering Lobby, so the first view of every round is sent",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     AC-3, C-4, C-8: pings.
     --------------------------------------------------------------------- ]]

--[[
	The helper of T1[1], standing at it, pings its setting: accepted (no
	refusal, no decline, no SendTo), `channel.pings` is `Pings.accept` of the
	previous state with `Pings.targetPosition`, `now` and a lit room, and the
	SAME step broadcasts a RoundView whose `pings` is `Pings.shown` of it (the
	view changed, C-6). It is still shown on the tick one second before
	`ping_display_seconds` and gone on the one at it (`Pings.tick` runs
	before the view). A fresh ping is cleared by the turn that commits the
	machine, in that step's RoundView. A machine ping shows without a
	setting. The round over (quorum dropped), the Resolution, Post and Lobby
	views show `{}` while the channel is KEPT through Resolution and Post (its
	log intact) and RESET on entering Lobby (C-8).
]]
function SessionChannelContract.showsAnAcceptedPingInTheRoundViewUntilExpiryOrCommit(S: Session)
	local d = start("AC-3", S, 1, SessionChannelContract.N)
	local t = MechanicsTuning
	local D = t.channel.ping_display_seconds
	local problems: { string } = {}
	local m, turner, helper = unit(d, 1, 1)
	local at = ScriptedRound.machinePosition(d, m)
	ScriptedRound.walk(d, { [helper] = at })
	ScriptedRound.tick(d, 1)
	local reading = Projection.lensFor(
		d.state.assignment,
		d.state.procedure,
		helper,
		d.state.positions[helper],
		ScriptedRound.sightAlwaysTrue
	)
	if #reading.readings == 0 then
		Contract.fail(`AC-3 precondition: {helper}'s lens reads nothing at machine {m.id}`)
	end

	local function roundViewPings(label: string, effects: { any }): any?
		local views = ofKind(effects, "Broadcast", "RoundView")
		if #views ~= 1 then
			table.insert(problems, `"{label}": {#views} RoundView broadcast(s), expected exactly 1`)
			return nil
		end
		return views[1].payload.pings
	end

	local target = { kind = "setting", target = m.id, setting = m.requiredSetting }
	local before = Deep.copy(d.state.channel)
	local r = ScriptedRound.ping(d, helper, target)
	local pingedAt = d.now
	if r.refused ~= nil then
		table.insert(
			problems,
			`the helper's setting ping at machine {m.id} was refused {Deep.show(r.refused)}`
		)
	end
	if r.call.declines ~= 0 then
		table.insert(
			problems,
			`an accepted ping declined the call {r.call.declines} time(s), expected 0`
		)
	end
	if #ofKind(r.effects, "SendTo") ~= 0 then
		table.insert(
			problems,
			`an accepted ping sent {Deep.show(labelsOf(r.effects))}; expected no SendTo`
		)
	end
	local wantPings = Pings.accept(
		before.pings,
		helper,
		target,
		Pings.targetPosition(d.state.procedure, target) :: any,
		pingedAt,
		true
	)
	if not Deep.equal(d.state.channel.pings, wantPings) then
		table.insert(
			problems,
			`after the accepted ping state.channel.pings is not Pings.accept(previous, "{helper}", target, Pings.targetPosition(procedure, target), {pingedAt}, roomLit = true):\n{Contract.firstFew(
				string.split(Deep.diff(wantPings, d.state.channel.pings), "\n"),
				4
			)}`
		)
	end
	local shown = Pings.shown(wantPings)
	local got = roundViewPings("the accepting ping step", r.effects)
	if got ~= nil and not Deep.equal(got, shown) then
		table.insert(
			problems,
			`the RoundView broadcast in the ping's own step has pings {Deep.show(got)}, expected Pings.shown = {Deep.show(
				shown
			)} (the view changed, C-6)`
		)
	end
	local stillThere =
		roundViewPings(`tick at {D - 1} s`, ScriptedRound.tickAt(d, pingedAt + D - 1))
	if stillThere ~= nil and not Deep.equal(stillThere, shown) then
		table.insert(
			problems,
			`{D - 1} s after the ping the RoundView has pings {Deep.show(stillThere)}, expected it still shown {Deep.show(
				shown
			)}`
		)
	end
	local gone = roundViewPings(`tick at {D} s`, ScriptedRound.tickAt(d, pingedAt + D))
	if gone ~= nil and not Deep.equal(gone, {}) then
		table.insert(
			problems,
			`{D} s after the ping (ping_display_seconds) the RoundView has pings {Deep.show(gone)}, expected \{} - Pings.tick runs before the view is built`
		)
	end
	if not Deep.equal(d.state.channel.pings.active, {}) then
		table.insert(
			problems,
			`after expiry state.channel.pings.active is {Deep.show(d.state.channel.pings.active)}, expected \{}`
		)
	end

	local r2 = ScriptedRound.ping(d, helper, target)
	if r2.refused ~= nil then
		table.insert(problems, `the second setting ping was refused {Deep.show(r2.refused)}`)
	end
	ScriptedRound.walk(d, { [turner] = at })
	ScriptedRound.tick(d, 1)
	local shownBefore = roundViewPings("tick before the commit", ScriptedRound.tick(d, 1))
	if shownBefore ~= nil and #shownBefore ~= 1 then
		table.insert(
			problems,
			`before the commit the RoundView shows {Deep.show(shownBefore)}, expected the second ping`
		)
	end
	local turn = ScriptedRound.turn(d, turner, m.id, m.requiredSetting)
	if typeof(turn.reply) ~= "table" or turn.reply.kind ~= "committed" then
		Contract.fail(`AC-3 precondition: the commit turn replied {Deep.show(turn.reply)}`)
	end
	local afterCommit = roundViewPings("the committing turn", turn.effects)
	if afterCommit ~= nil and not Deep.equal(afterCommit, {}) then
		table.insert(
			problems,
			`the RoundView in the step that committed machine {m.id} has pings {Deep.show(
				afterCommit
			)}, expected \{} (Pings.onCommitted)`
		)
	end
	if not Deep.equal(d.state.channel.pings.active, {}) then
		table.insert(
			problems,
			`after the commit state.channel.pings.active is {Deep.show(d.state.channel.pings.active)}, expected \{}`
		)
	end
	if #d.state.channel.pings.log ~= 2 then
		table.insert(
			problems,
			`after two accepted pings the log has {#d.state.channel.pings.log} entries, expected 2 (expiry and commit leave it alone)`
		)
	end

	-- A machine ping on an uncommitted machine of another track, shown without a setting.
	local m2 = unit(d, 2, 1)
	local at2 = ScriptedRound.machinePosition(d, m2)
	ScriptedRound.walk(d, { [helper] = at2 })
	local r3 = ScriptedRound.ping(d, helper, { kind = "machine", target = m2.id })
	if r3.refused ~= nil then
		table.insert(
			problems,
			`a machine ping at machine {m2.id} was refused {Deep.show(r3.refused)}`
		)
	end
	local machineShown = roundViewPings("the machine ping step", r3.effects)
	local wantMachine = { { senderId = helper, kind = "machine", target = m2.id } }
	if machineShown ~= nil and not Deep.equal(machineShown, wantMachine) then
		table.insert(
			problems,
			`the RoundView after a machine ping has pings {Deep.show(machineShown)}, expected {Deep.show(
				wantMachine
			)} (no setting key)`
		)
	end

	-- C-8 and C-4 outside Round.
	local kept = Deep.copy(d.state.channel)
	local leaveViews: { any? } = {}
	dropQuorum(d, { helper, turner }, function(label: string, effects: { any })
		table.insert(leaveViews, roundViewPings(label, effects))
	end)
	if d.state.round.phase ~= "Resolution" then
		Contract.fail(
			`AC-3 precondition: after two leaves the phase is {d.state.round.phase}, not Resolution`
		)
	end
	if leaveViews[1] ~= nil and not Deep.equal(leaveViews[1], wantMachine) then
		table.insert(
			problems,
			`the RoundView on the first leave (still Round) has pings {Deep.show(leaveViews[1])}, expected the machine ping still shown`
		)
	end
	if leaveViews[2] ~= nil and not Deep.equal(leaveViews[2], {}) then
		table.insert(
			problems,
			`the RoundView on entering Resolution has pings {Deep.show(leaveViews[2])}, expected \{} (C-4: outside Round)`
		)
	end
	if not Deep.equal(d.state.channel, kept) then
		table.insert(
			problems,
			`state.channel changed on entering Resolution:\n{Contract.firstFew(
				string.split(Deep.diff(kept, d.state.channel), "\n"),
				4
			)}\n(C-8: kept through Resolution and Post)`
		)
	end
	local postPings = roundViewPings("Resolution -> Post", ScriptedRound.tick(d, 1))
	if postPings ~= nil and not Deep.equal(postPings, {}) then
		table.insert(
			problems,
			`the RoundView in Post has pings {Deep.show(postPings)}, expected \{}`
		)
	end
	if not Deep.equal(d.state.channel, kept) then
		table.insert(problems, "state.channel changed on entering Post (C-8: kept)")
	end
	local lobbyPings =
		roundViewPings("Post -> Lobby", ScriptedRound.tickAt(d, d.now + d.config.postRoundSeconds))
	if d.state.round.phase ~= "Lobby" then
		Contract.fail(`AC-3 precondition: after Post the phase is {d.state.round.phase}, not Lobby`)
	end
	if lobbyPings ~= nil and not Deep.equal(lobbyPings, {}) then
		table.insert(
			problems,
			`the RoundView in the next Lobby has pings {Deep.show(lobbyPings)}, expected \{}`
		)
	end
	local fresh = { presets = PresetSends.new(), pings = Pings.new() }
	if not Deep.equal(d.state.channel, fresh) then
		table.insert(
			problems,
			`on entering Lobby state.channel is {Deep.show(d.state.channel)}, expected a fresh channel {Deep.show(
				fresh
			)} (C-8)`
		)
	end
	fewProblems(
		"AC-3",
		"an accepted ping is Pings.accept'ed and shown in the RoundView until ping_display_seconds or its machine's commit; the channel is kept through Resolution and Post and reset in Lobby",
		problems
	)
end

--[[
	A refused ping: exactly one effect, a SendTo/PingRefused to the sender
	with the module's reason, the call declined exactly once, the state
	unchanged. In Lobby (no procedure) and in Resolution (procedure held,
	wrong phase) the reason is `no_such_target`; in Round from the spawn
	centre the farthest machine is `out_of_range`, and a machine ping with a
	setting is `setting_mismatch`.
]]
function SessionChannelContract.refusesAPingToTheSenderAloneDecliningOnce(S: Session)
	local problems: { string } = {}
	local cases = 0

	local function expectRefusal(
		label: string,
		d: ScriptedRound.Driver,
		who: string,
		target: any,
		reason: string
	)
		cases += 1
		local before = Deep.copy(d.state)
		local r = ScriptedRound.ping(d, who, target)
		if r.refused == nil then
			table.insert(
				problems,
				`{label}: the ping was ACCEPTED (effects {Deep.show(labelsOf(r.effects))}), expected refused / {reason}`
			)
			return
		end
		if not Deep.equal(r.refused, { reason = reason }) then
			table.insert(
				problems,
				`{label}: PingRefused is {Deep.show(r.refused)}, expected exactly \{ reason = "{reason}" }`
			)
		end
		if r.call.declines ~= 1 then
			table.insert(
				problems,
				`{label}: the call was declined {r.call.declines} time(s), expected exactly 1`
			)
		end
		if #r.effects ~= 1 then
			table.insert(
				problems,
				`{label}: effects were {Deep.show(labelsOf(r.effects))}, expected exactly the one SendTo/PingRefused (no other effect from a refused ping)`
			)
		end
		for _, e in ofKind(r.effects, "SendTo") do
			if e.playerId ~= who then
				table.insert(
					problems,
					`{label}: a PingRefused went to {Deep.show(e.playerId)}, not the sender {who}`
				)
			end
			if not Deep.equal(keysOf(e), SessionChannelContract.SEND_TO_KEYS) then
				table.insert(problems, `{label}: the SendTo's key set is {Deep.show(keysOf(e))}`)
			end
		end
		if not Deep.equal(d.state, before) then
			table.insert(
				problems,
				`{label}: the state changed on a refused ping:\n{Contract.firstFew(
					string.split(Deep.diff(before, d.state), "\n"),
					4
				)}`
			)
		end
	end

	local inLobby = lobby("AC-3", S, 1, SessionChannelContract.N)
	expectRefusal(
		"in Lobby, before any deal",
		inLobby,
		inLobby.players[1],
		{ kind = "setting", target = 1, setting = 1 },
		"no_such_target"
	)

	local d = start("AC-3", S, 1, SessionChannelContract.N)
	local centre = ScriptedRound.spawnCentre(d.state.facility, d.tuning)
	local far: any = nil
	local farDistance = 0
	for _, machine in d.state.facility.placement.machines do
		local distance = horizontal(centre, ScriptedRound.machinePosition(d, machine))
		if distance > farDistance then
			far, farDistance = machine, distance
		end
	end
	if farDistance <= MechanicsTuning.channel.ping_range_studs then
		Contract.fail(
			`AC-3 precondition: the farthest machine is {farDistance} studs from the spawn centre, inside ping range`
		)
	end
	ScriptedRound.tick(d, 1)
	local who = d.state.assignment.players[1]
	expectRefusal(
		"in Round, out of range from the spawn centre",
		d,
		who,
		{ kind = "setting", target = far.id, setting = far.requiredSetting },
		"out_of_range"
	)
	expectRefusal(
		"in Round, a machine ping carrying a setting",
		d,
		who,
		{ kind = "machine", target = far.id, setting = 1 },
		"setting_mismatch"
	)

	local seated = d.state.assignment.players
	dropQuorum(d, { seated[1], seated[2] })
	if d.state.round.phase ~= "Resolution" or d.state.procedure == nil then
		Contract.fail(
			`AC-3 precondition: after two leaves the phase is {d.state.round.phase} with procedure {if d.state.procedure
				then "held"
				else "nil"}`
		)
	end
	expectRefusal(
		"in Resolution, with the procedure still held",
		d,
		seated[1],
		{ kind = "setting", target = far.id, setting = far.requiredSetting },
		"no_such_target"
	)

	if cases < 4 then
		Contract.fail(`AC-3 precondition: only {cases} refusal cases`)
	end
	fewProblems(
		"AC-3",
		"a refused ping sends one PingRefused to its sender alone, declines the call exactly once, changes nothing, and is no_such_target outside Round",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     AC-4, C-5: presets.
     --------------------------------------------------------------------- ]]

--[[
	In Round, a player who has walked off the centre sends "go" with a
	succeeding filter: one Broadcast/PresetShown carrying their STORED
	position (a copy) and the FILTERED text, no SendTo, no decline, and the
	presets log is `PresetSends.send`'s. A failing filter: one
	SendTo/PresetFailed to the sender alone, declined once, log unchanged. A
	preset illegal in the phase fails `phase_for_preset` before the filter.
	In Lobby with no stored position: declined once, no effect, state
	unchanged. In Post, "well played" is shown at the kept position.
]]
function SessionChannelContract.broadcastsAShownPresetAtTheStoredPositionAndFailsToTheSenderAlone(
	S: Session
)
	local problems: { string } = {}
	local GO, READY, WELL_PLAYED = presetId("go"), presetId("ready"), presetId("well_played")

	-- No stored position (Lobby, before any sample).
	local inLobby = lobby("AC-4", S, 1, SessionChannelContract.N)
	local before = Deep.copy(inLobby.state)
	local none =
		ScriptedRound.preset(inLobby, inLobby.players[1], READY, { ok = true, text = "Ready" })
	if none.call.declines ~= 1 then
		table.insert(
			problems,
			`with no stored position the call was declined {none.call.declines} time(s), expected exactly 1 (C-5)`
		)
	end
	if #none.effects ~= 0 then
		table.insert(
			problems,
			`with no stored position the step emitted {Deep.show(labelsOf(none.effects))}, expected nothing (C-5)`
		)
	end
	if not Deep.equal(inLobby.state, before) then
		table.insert(problems, "with no stored position the state changed (C-5: unchanged)")
	end

	-- Round: a sender off the centre.
	local d = start("AC-4", S, 1, SessionChannelContract.N)
	local sender = d.state.assignment.players[2]
	local centre = ScriptedRound.spawnCentre(d.state.facility, d.tuning)
	ScriptedRound.walk(d, { [sender] = { x = centre.x + 10, y = 0, z = centre.z } })
	local stored = d.state.positions[sender]
	if stored == nil or Deep.equal(stored, centre) then
		Contract.fail(
			`AC-4 precondition: {sender}'s stored position is {Deep.show(stored)}, expected one off the centre`
		)
	end
	local presetsBefore = Deep.copy(d.state.channel.presets)
	local shown = ScriptedRound.preset(d, sender, GO, { ok = true, text = "Go (filtered)" })
	local wantShown =
		{ senderId = sender, presetId = GO, position = Deep.copy(stored), text = "Go (filtered)" }
	if shown.shown == nil then
		table.insert(
			problems,
			`a succeeding "go" in Round broadcast no PresetShown (effects {Deep.show(
				labelsOf(shown.effects)
			)})`
		)
	else
		if not Deep.equal(shown.shown, wantShown) then
			table.insert(
				problems,
				`PresetShown is {Deep.show(shown.shown)}, expected {Deep.show(wantShown)} - the sender's STORED position and the FILTERED text`
			)
		end
		if rawequal(shown.shown.position, d.state.positions[sender]) then
			table.insert(
				problems,
				"PresetShown.position IS state.positions[sender] (the same table); C-5 wants a copy"
			)
		end
	end
	if shown.call.declines ~= 0 then
		table.insert(problems, `a shown preset declined the call {shown.call.declines} time(s)`)
	end
	if #ofKind(shown.effects, "SendTo") ~= 0 or #ofKind(shown.effects, "Broadcast") ~= 1 then
		table.insert(
			problems,
			`a shown preset's effects were {Deep.show(labelsOf(shown.effects))}, expected exactly one Broadcast/PresetShown and no SendTo`
		)
	end
	local okFilter = function(_s: string, _w: string): (boolean, string?)
		return true, "Go (filtered)"
	end
	local wantLog = PresetSends.send(
		presetsBefore,
		sender,
		GO,
		"Round",
		stored,
		shown.now,
		okFilter,
		ScriptedRound.call()
	)
	if not Deep.equal(d.state.channel.presets, wantLog) then
		table.insert(
			problems,
			`state.channel.presets after the shown preset is not PresetSends.send's state:\n{Contract.firstFew(
				string.split(Deep.diff(wantLog, d.state.channel.presets), "\n"),
				4
			)}`
		)
	end

	-- A failing filter.
	local logBefore = Deep.copy(d.state.channel.presets)
	local failed = ScriptedRound.preset(d, sender, GO, { ok = false })
	if not Deep.equal(failed.failed, { presetId = GO, reason = "filter" }) then
		table.insert(
			problems,
			`with a failing filter PresetFailed is {Deep.show(failed.failed)}, expected \{ presetId = {GO}, reason = "filter" }`
		)
	end
	if failed.shown ~= nil or #ofKind(failed.effects, "Broadcast") ~= 0 then
		table.insert(
			problems,
			`with a failing filter the step broadcast {Deep.show(labelsOf(failed.effects))}; nothing is shown`
		)
	end
	for _, e in ofKind(failed.effects, "SendTo") do
		if e.playerId ~= sender then
			table.insert(
				problems,
				`a PresetFailed went to {Deep.show(e.playerId)}, not the sender {sender}`
			)
		end
		if not Deep.equal(keysOf(e), SessionChannelContract.SEND_TO_KEYS) then
			table.insert(problems, `the PresetFailed SendTo's key set is {Deep.show(keysOf(e))}`)
		end
	end
	if #ofKind(failed.effects, "SendTo") ~= 1 then
		table.insert(
			problems,
			`with a failing filter {#ofKind(failed.effects, "SendTo")} SendTo(s), expected exactly one to the sender`
		)
	end
	if failed.call.declines ~= 1 then
		table.insert(
			problems,
			`a failed preset declined the call {failed.call.declines} time(s), expected exactly 1`
		)
	end
	if not Deep.equal(d.state.channel.presets, logBefore) then
		table.insert(problems, "a failed preset changed the presets log")
	end

	-- Phase first: "well played" is Post-only, so a succeeding filter is never asked.
	local phase = ScriptedRound.preset(d, sender, WELL_PLAYED, { ok = true, text = "Well played" })
	if not Deep.equal(phase.failed, { presetId = WELL_PLAYED, reason = "phase_for_preset" }) then
		table.insert(
			problems,
			`"well played" in Round gave {Deep.show(phase.failed)} / shown {Deep.show(phase.shown)}, expected PresetFailed phase_for_preset`
		)
	end
	if phase.call.declines ~= 1 then
		table.insert(
			problems,
			`the phase refusal declined the call {phase.call.declines} time(s), expected 1`
		)
	end

	-- Post: shown at the kept position.
	local seated = d.state.assignment.players
	dropQuorum(d, { sender, seated[1] })
	ScriptedRound.tick(d, 1)
	if d.state.round.phase ~= "Post" then
		Contract.fail(`AC-4 precondition: the phase is {d.state.round.phase}, not Post`)
	end
	local inPost =
		ScriptedRound.preset(d, sender, WELL_PLAYED, { ok = true, text = "Well played!" })
	local wantPost = {
		senderId = sender,
		presetId = WELL_PLAYED,
		position = Deep.copy(stored),
		text = "Well played!",
	}
	if not Deep.equal(inPost.shown, wantPost) then
		table.insert(
			problems,
			`"well played" in Post gave shown {Deep.show(inPost.shown)} / failed {Deep.show(
				inPost.failed
			)}, expected {Deep.show(wantPost)} (the phase handed to PresetSends is round.phase; positions are kept)`
		)
	end
	fewProblems(
		"AC-4",
		"a shown preset is one Broadcast/PresetShown at the sender's stored position with the filtered text; a failure is one PresetFailed to the sender alone, declined once; no stored position means a decline and no effect",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     AC-5, C-7: the FacilityView.
     --------------------------------------------------------------------- ]]

--[[
	On each successful deal: exactly one Broadcast/FacilityView, deep-equal
	`RoundView.facility(state.facility)`, after the last SeatView and before
	the first private view and the RoundView (which, on that step, carries
	machines). On no other step of the round, nor in Resolution, Post or
	Lobby; none at all when generation fails.
]]
function SessionChannelContract.broadcastsOneFacilityViewOnTheDealBeforeTheRoundViewAndNeverOtherwise(
	S: Session
)
	local problems: { string } = {}
	local others = 0

	local function expectNone(label: string, effects: { any })
		others += 1
		local n = #ofKind(effects, "Broadcast", "FacilityView")
		if n ~= 0 then
			table.insert(
				problems,
				`"{label}": {n} FacilityView broadcast(s) on a step that dealt nothing`
			)
		end
	end

	local function expectOne(label: string, d: ScriptedRound.Driver, effects: { any })
		local views = ofKind(effects, "Broadcast", "FacilityView")
		if #views ~= 1 then
			table.insert(
				problems,
				`"{label}": {#views} FacilityView broadcast(s), expected exactly 1 ({Deep.show(
					labelsOf(effects)
				)})`
			)
			return
		end
		local view = views[1]
		if not Deep.equal(keysOf(view), SessionChannelContract.BROADCAST_KEYS) then
			table.insert(
				problems,
				`"{label}": the FacilityView effect's key set is {Deep.show(keysOf(view))}`
			)
		end
		local want = RoundView.facility(d.state.facility)
		if not Deep.equal(view.payload, want) then
			table.insert(
				problems,
				`"{label}": the FacilityView is not RoundView.facility(state.facility):\n{Contract.firstFew(
					string.split(Deep.diff(want, view.payload), "\n"),
					4
				)}`
			)
		end
		local index, lastSeat, firstPrivate, roundViewAt = 0, 0, nil, nil
		for i, e in effects do
			if rawequal(e, view) then
				index = i
			elseif typeof(e) == "table" and e.kind == "SendTo" and e.payloadKind == "SeatView" then
				lastSeat = i
			elseif
				typeof(e) == "table"
				and e.kind == "SendTo"
				and contains(SessionChannelContract.PRIVATE_KINDS, tostring(e.payloadKind))
			then
				firstPrivate = firstPrivate or i
			elseif
				typeof(e) == "table"
				and e.kind == "Broadcast"
				and e.payloadKind == "RoundView"
			then
				roundViewAt = i
			end
		end
		if index < lastSeat then
			table.insert(
				problems,
				`"{label}": the FacilityView at #{index} comes before a SeatView at #{lastSeat} (C-9)`
			)
		end
		if firstPrivate ~= nil and index > firstPrivate then
			table.insert(
				problems,
				`"{label}": the FacilityView at #{index} comes after a private view at #{firstPrivate} (C-9)`
			)
		end
		if roundViewAt == nil then
			table.insert(problems, `"{label}": no RoundView on the dealing step`)
		else
			if index > roundViewAt then
				table.insert(
					problems,
					`"{label}": the FacilityView at #{index} comes after the RoundView at #{roundViewAt}; it precedes any RoundView with machines`
				)
			end
			if #effects[roundViewAt].payload.machines == 0 then
				table.insert(
					problems,
					`"{label}": the dealing step's RoundView carries no machines`
				)
			end
		end
	end

	local d, deal1 = start("AC-5", S, 3, SessionChannelContract.N)
	expectOne("DEAL 1", d, deal1)
	expectNone("tick in Round", ScriptedRound.tick(d, 1))
	local m, turner = unit(d, 1, 1)
	walkRecording(d, { [turner] = ScriptedRound.machinePosition(d, m) }, expectNone)
	ScriptedRound.tick(d, 1)
	expectNone("the commit turn", ScriptedRound.turn(d, turner, m.id, m.requiredSetting).effects)
	local leavers = dropQuorum(d, { turner, d.state.assignment.players[1] }, expectNone)
	expectNone("Resolution -> Post", ScriptedRound.tick(d, 1))
	expectNone("Post -> Lobby", ScriptedRound.tickAt(d, d.now + d.config.postRoundSeconds))
	for _, p in leavers do
		expectNone(`{p} rejoins`, ScriptedRound.step(d, { kind = "PlayerJoined", playerId = p }))
	end
	local deal2 = ScriptedRound.deal(d)
	if d.state.facility == nil then
		Contract.fail("AC-5 precondition: the second deal produced no facility")
	end
	expectOne("DEAL 2", d, deal2)

	local failing = ScriptedRound.new(
		S,
		3,
		SessionChannelContract.N,
		{ generatorPredicate = SessionRoundContract.refuseAll }
	)
	ScriptedRound.join(failing)
	local failedDeal = ScriptedRound.tickAt(failing, failing.config.lobbySeconds)
	if failing.state.round.phase ~= "Resolution" then
		Contract.fail(
			`AC-5 precondition: the refused deal left the phase at {failing.state.round.phase}`
		)
	end
	if #ofKind(failedDeal, "Broadcast", "FacilityView") ~= 0 then
		table.insert(
			problems,
			`a deal whose generation FAILED broadcast a FacilityView ({Deep.show(
				labelsOf(failedDeal)
			)})`
		)
	end
	if others < 8 then
		Contract.fail(`AC-5 precondition: only {others} non-dealing steps`)
	end
	fewProblems(
		"AC-5",
		"exactly one Broadcast/FacilityView = RoundView.facility(facility) on each successful deal, after the SeatViews and before the private views and the RoundView; never otherwise",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     C-9: the order within a step.
     --------------------------------------------------------------------- ]]

--[[
	Every effect on every step of a sequence holding a deal, samples, an
	accepted and a refused ping, a shown and a failed preset and a commit is
	a named kind in C-9's order with the RoundView last; and the steps whose
	content C-9 fixes show it exactly: the deal's labels are Placed x n,
	SeatView x n, FacilityView, (LensView, TurnCues) x n, RoundView after the
	machine's pass-through; the commit's are TurnResult, then only private
	views, then the RoundView.
]]
function SessionChannelContract.ordersEffectsWithinAStepAsTheContractLists(S: Session)
	local problems: { string } = {}
	local steps = 0
	local function judge(label: string, effects: { any })
		steps += 1
		expectOrdered("C-9", problems, label, effects)
	end
	local d, deal = start("C-9", S, 1, SessionChannelContract.N)
	judge("DEAL", deal)
	local n = #d.state.assignment.players
	local want: { string } = {}
	for _ = 1, n do
		table.insert(want, "Placed")
	end
	for _ = 1, n do
		table.insert(want, "SeatView")
	end
	table.insert(want, "FacilityView")
	for _ = 1, n do
		table.insert(want, "LensView")
		table.insert(want, "TurnCues")
	end
	table.insert(want, "RoundView")
	local dealLabels: { string } = {}
	for _, label in labelsOf(deal) do
		if SessionRoundContract.RANK[label] ~= 1 then
			table.insert(dealLabels, label)
		end
	end
	if not Deep.equal(dealLabels, want) then
		table.insert(
			problems,
			`the deal's effects after the pass-through are {Deep.show(dealLabels)}, expected {Deep.show(
				want
			)}`
		)
	end

	judge("tick", ScriptedRound.tick(d, 1))
	local m, turner, helper = unit(d, 1, 1)
	local at = ScriptedRound.machinePosition(d, m)
	walkRecording(d, { [helper] = at, [turner] = at }, judge)
	judge("tick at the machine", ScriptedRound.tick(d, 1))
	local accepted = ScriptedRound.ping(
		d,
		helper,
		{ kind = "setting", target = m.id, setting = m.requiredSetting }
	)
	judge("accepted ping", accepted.effects)
	if not Deep.equal(labelsOf(accepted.effects), { "RoundView" }) then
		table.insert(
			problems,
			`an accepted ping's effects are {Deep.show(labelsOf(accepted.effects))}, expected exactly the RoundView`
		)
	end
	local refused = ScriptedRound.ping(d, turner, { kind = "machine", target = m.id, setting = 1 })
	judge("refused ping", refused.effects)
	if not Deep.equal(labelsOf(refused.effects), { "PingRefused" }) then
		table.insert(
			problems,
			`a refused ping's effects are {Deep.show(labelsOf(refused.effects))}, expected exactly the PingRefused`
		)
	end
	local shown = ScriptedRound.preset(d, helper, presetId("go"), { ok = true, text = "Go" })
	judge("shown preset", shown.effects)
	if not Deep.equal(labelsOf(shown.effects), { "PresetShown" }) then
		table.insert(
			problems,
			`a shown preset's effects are {Deep.show(labelsOf(shown.effects))}, expected exactly the PresetShown`
		)
	end
	local failed = ScriptedRound.preset(d, helper, presetId("go"), { ok = false })
	judge("failed preset", failed.effects)
	if not Deep.equal(labelsOf(failed.effects), { "PresetFailed" }) then
		table.insert(
			problems,
			`a failed preset's effects are {Deep.show(labelsOf(failed.effects))}, expected exactly the PresetFailed`
		)
	end
	local turn = ScriptedRound.turn(d, turner, m.id, m.requiredSetting)
	judge("the commit turn", turn.effects)
	local labels = labelsOf(turn.effects)
	local okShape = #labels >= 3 and labels[1] == "TurnResult" and labels[#labels] == "RoundView"
	for i = 2, #labels - 1 do
		if labels[i] ~= "LensView" and labels[i] ~= "TurnCues" then
			okShape = false
		end
	end
	if not okShape then
		table.insert(
			problems,
			`the commit turn's effects are {Deep.show(labels)}, expected the TurnResult, then only LensView/TurnCues (the helper's reading is gone, the cues moved), then the RoundView`
		)
	end
	judge("tick after the commit", ScriptedRound.tick(d, 1))
	if steps < 8 then
		Contract.fail(`C-9 precondition: only {steps} steps judged`)
	end
	fewProblems(
		"C-9",
		"within a step the effects are pass-through, Placed, SeatView, FacilityView, the reply, PresetShown, LensView/TurnCues per player, then at most one RoundView last, and nothing of another kind",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     AC-6: no private payload carries a setting outside the lens.
     --------------------------------------------------------------------- ]]

-- AC-6's per-kind allowlist on one step. `world` is the TEST's reading of
-- the assignment (for `Ring.lensOf`) and the facility (for each machine's
-- class); a player never sees it.
local function secretProblems(
	problems: { string },
	tag: string,
	now: number,
	effects: { any },
	world: any,
	counts: { lensViews: number, readings: number }
)
	local classOf: { [number]: number } = {}
	for _, machine in world.facility.placement.machines do
		classOf[machine.id] = machine.keyClass
	end
	for _, e in effects do
		if typeof(e) ~= "table" then
			table.insert(problems, `{tag} at {now}: an effect is {Deep.show(e)}, not a table`)
			continue
		end
		if e.kind == "SendTo" then
			local kind = tostring(e.payloadKind)
			local allowed = SessionChannelContract.PRIVATE_PAYLOAD_KEYS[kind]
			if allowed == nil then
				table.insert(
					problems,
					`{tag} at {now}: a SendTo to {Deep.show(e.playerId)} of kind {kind} is not on AC-6's allowlist`
				)
				continue
			end
			local payload = e.payload
			if typeof(payload) ~= "table" then
				table.insert(
					problems,
					`{tag} at {now}: the {kind} payload to {Deep.show(e.playerId)} is {Deep.show(
						payload
					)}`
				)
				continue
			end
			for _, key in keysOf(payload) do
				if not contains(allowed, key) then
					table.insert(
						problems,
						`{tag} at {now}: the {kind} sent to {e.playerId} carries a key {key} the allowlist does not name ({Deep.show(
							allowed
						)})`
					)
				end
			end
			if kind == "LensView" then
				counts.lensViews += 1
				local lens = Ring.lensOf(world.assignment, e.playerId)
				for _, reading in payload.readings or {} do
					counts.readings += 1
					if not Deep.equal(keysOf(reading), { "machineId", "setting" }) then
						table.insert(
							problems,
							`{tag} at {now}: a reading sent to {e.playerId} has keys {Deep.show(
								keysOf(reading)
							)}`
						)
					end
					if classOf[reading.machineId] ~= lens then
						table.insert(
							problems,
							`{tag} at {now}: {e.playerId} (lens class {lens}) was sent the setting of machine {reading.machineId}, whose class is {Deep.show(
								classOf[reading.machineId]
							)} - outside their lens`
						)
					end
				end
			elseif kind == "TurnCues" then
				for _, list in { payload.live, payload["next"] } do
					if typeof(list) ~= "table" then
						table.insert(
							problems,
							`{tag} at {now}: TurnCues to {e.playerId} holds {Deep.show(list)} where a list of ids was expected`
						)
						continue
					end
					for _, id in list do
						if typeof(id) ~= "number" or classOf[id] == nil then
							table.insert(
								problems,
								`{tag} at {now}: TurnCues to {e.playerId} holds {Deep.show(id)}, not a machine id`
							)
						end
					end
				end
			elseif kind == "SeatView" then
				if not Deep.equal(keysOf(payload), SEAT_VIEW_KEYS) then
					table.insert(
						problems,
						`{tag} at {now}: a SeatView to {e.playerId} has keys {Deep.show(
							keysOf(payload)
						)}`
					)
				end
			end
		elseif e.kind == "Broadcast" then
			local kind = tostring(e.payloadKind)
			if not contains(SessionChannelContract.PUBLIC_BROADCAST_KINDS, kind) then
				table.insert(
					problems,
					`{tag} at {now}: a Broadcast of kind {kind} is not a public kind ({Deep.show(
						SessionChannelContract.PUBLIC_BROADCAST_KINDS
					)})`
				)
			elseif looksLikePrivateView(e.payload) then
				table.insert(
					problems,
					`{tag} at {now}: a {kind} Broadcast carries a private view by shape`
				)
			elseif kind == "FacilityView" then
				for _, machine in e.payload.machines do
					if
						not Deep.equal(keysOf(machine), { "id", "keyClass", "room", "slot", "tag" })
					then
						table.insert(
							problems,
							`{tag} at {now}: a FacilityView machine has keys {Deep.show(
								keysOf(machine)
							)}`
						)
					end
				end
			end
		end
	end
end

function SessionChannelContract.neverSendsAPlayerASettingOfAMachineOutsideTheirLens(S: Session)
	requireModule("AC-6", S)
	local problems: { string } = {}
	local counts = { lensViews = 0, readings = 0 }
	local rounds, stepsSeen = 0, 0
	for _, n in SessionChannelContract.PLAYER_COUNTS do
		for _, seed in SessionChannelContract.SECRET_SEEDS do
			rounds += 1
			local tag = `seed {seed}, n = {n}`
			local ok, err = pcall(ShownRound.play, S, seed, n, {
				observe = function(now: number, effects: { any }, world: any)
					stepsSeen += 1
					if #problems < 200 then
						secretProblems(problems, tag, now, effects, world, counts)
					end
				end,
			})
			if not ok then
				Contract.fail(`AC-6: the shown script could not run ({tag}): {tostring(err)}`)
			end
		end
	end
	print(
		`        [measured] AC-6: {stepsSeen} steps over {rounds} rounds; {counts.lensViews} LensViews carrying {counts.readings} readings inspected`
	)
	if counts.readings < rounds then
		Contract.fail(
			`AC-6 precondition: only {counts.readings} readings in {counts.lensViews} LensViews over {rounds} rounds; a round in which no lens is ever read proves nothing about what a lens may carry`
		)
	end
	fewProblems(
		"AC-6",
		"no SendTo may carry a required setting outside the recipient's lens: a LensView reads only machines of Ring.lensOf, every other private kind carries no setting field, and every kind is on the allowlist",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     AC-2: the round is won by showing, and its control.
     --------------------------------------------------------------------- ]]

function SessionChannelContract.winsEveryRoundWhenTurnersActOnlyOnShownPings(S: Session)
	requireModule("AC-2", S)
	local problems: { string } = {}
	local rounds, won = 0, 0
	local maxElapsed, maxSteps, totalPings, totalTurns, declines, refusals = 0, 0, 0, 0, 0, 0
	for _, n in SessionChannelContract.PLAYER_COUNTS do
		for seed = 1, SessionChannelContract.SEEDS do
			rounds += 1
			local tag = `seed {seed}, n = {n}`
			local ok, run = pcall(ShownRound.play, S, seed, n)
			if not ok then
				Contract.fail(`AC-2: the shown script could not run ({tag}): {tostring(run)}`)
			end
			maxElapsed = math.max(maxElapsed, run.elapsed)
			maxSteps = math.max(maxSteps, run.steps)
			totalPings += #run.pings
			totalTurns += #run.turns
			declines += run.declines
			refusals += run.refusedPings
			if run.won then
				won += 1
			else
				table.insert(
					problems,
					`{tag}: after {run.elapsed} s the round is {run.outcome.phase} / {Deep.show(
						run.outcome.outcome
					)} with {#run.pings} pings and {#run.turns} turns, expected won / procedure_complete`
				)
			end
		end
	end
	print(
		`        [measured] AC-2: {won}/{rounds} rounds won by showing; max {maxElapsed} s deal-to-resolution, max {maxSteps} steps; {totalPings} pings ({refusals} refused, {declines} declines), {totalTurns} turns`
	)
	fewProblems(
		"AC-2",
		`every scripted round ({rounds}) must be won with each turner acting only on its helper's shown ping, and each helper only on its own lens`,
		problems
	)
end

function SessionChannelContract.losesToTheClockWhenHelpersNeverPing(S: Session)
	requireModule("AC-2", S)
	local c = ScriptedRound.config()
	local problems: { string } = {}
	local rounds, lost = 0, 0
	for _, n in SessionChannelContract.PLAYER_COUNTS do
		for _, seed in SessionChannelContract.CONTROL_SEEDS do
			rounds += 1
			local tag = `control seed {seed}, n = {n}`
			local ok, run = pcall(ShownRound.play, S, seed, n, { pings = false })
			if not ok then
				Contract.fail(`AC-2: the control script could not run ({tag}): {tostring(run)}`)
			end
			local outcome = run.outcome.outcome
			local clock = run.outcome.phase == "Resolution"
				and typeof(outcome) == "table"
				and outcome.result == "lost"
				and outcome.reason == "clock"
			if clock and #run.turns == 0 and #run.pings == 0 then
				lost += 1
			else
				table.insert(
					problems,
					`{tag}: {run.outcome.phase} / {Deep.show(outcome)} after {run.elapsed} s with {#run.pings} pings and {#run.turns} turns; with pings suppressed the turner has no setting, never guesses, and the round must end lost / clock with no turn at all`
				)
			end
			if run.resolvedAt ~= nil and run.resolvedAt ~= run.startedAt + c.roundSeconds then
				table.insert(
					problems,
					`{tag}: resolved at {run.resolvedAt}, expected the unpenalised deadline {run.startedAt + c.roundSeconds}`
				)
			end
		end
	end
	print(
		`        [measured] AC-2 control: {lost}/{rounds} rounds lost / clock with no turn and no ping`
	)
	fewProblems(
		"AC-2",
		"with the helper's ping suppressed the script must not win: no turn, lost / clock",
		problems
	)
end

--[[ ------------------------------------------------------------------------
     The battery, named.
     --------------------------------------------------------------------- ]]

export type Check = { name: string, ac: string, run: (Session) -> () }

SessionChannelContract.CHECKS = {
	{
		name = "newRequiresPortsAndHoldsAFreshChannelSentAndPorts",
		ac = "C-2",
		run = SessionChannelContract.newRequiresPortsAndHoldsAFreshChannelSentAndPorts,
	},
	{
		name = "sendsEachPlayerTheirOwnLensAndCuesExactlyWhenTheyChange",
		ac = "AC-1",
		run = SessionChannelContract.sendsEachPlayerTheirOwnLensAndCuesExactlyWhenTheyChange,
	},
	{
		name = "resetsTheSentViewsOnTheDealAndInLobby",
		ac = "C-6",
		run = SessionChannelContract.resetsTheSentViewsOnTheDealAndInLobby,
	},
	{
		name = "showsAnAcceptedPingInTheRoundViewUntilExpiryOrCommit",
		ac = "AC-3",
		run = SessionChannelContract.showsAnAcceptedPingInTheRoundViewUntilExpiryOrCommit,
	},
	{
		name = "refusesAPingToTheSenderAloneDecliningOnce",
		ac = "AC-3",
		run = SessionChannelContract.refusesAPingToTheSenderAloneDecliningOnce,
	},
	{
		name = "broadcastsAShownPresetAtTheStoredPositionAndFailsToTheSenderAlone",
		ac = "AC-4",
		run = SessionChannelContract.broadcastsAShownPresetAtTheStoredPositionAndFailsToTheSenderAlone,
	},
	{
		name = "broadcastsOneFacilityViewOnTheDealBeforeTheRoundViewAndNeverOtherwise",
		ac = "AC-5",
		run = SessionChannelContract.broadcastsOneFacilityViewOnTheDealBeforeTheRoundViewAndNeverOtherwise,
	},
	{
		name = "ordersEffectsWithinAStepAsTheContractLists",
		ac = "C-9",
		run = SessionChannelContract.ordersEffectsWithinAStepAsTheContractLists,
	},
	{
		name = "neverSendsAPlayerASettingOfAMachineOutsideTheirLens",
		ac = "AC-6",
		run = SessionChannelContract.neverSendsAPlayerASettingOfAMachineOutsideTheirLens,
	},
	{
		name = "winsEveryRoundWhenTurnersActOnlyOnShownPings",
		ac = "AC-2",
		run = SessionChannelContract.winsEveryRoundWhenTurnersActOnlyOnShownPings,
	},
	{
		name = "losesToTheClockWhenHelpersNeverPing",
		ac = "AC-2",
		run = SessionChannelContract.losesToTheClockWhenHelpersNeverPing,
	},
} :: { Check }

-- The cheap checks: everything but the three scripted sweeps.
SessionChannelContract.FAST = {
	"newRequiresPortsAndHoldsAFreshChannelSentAndPorts",
	"sendsEachPlayerTheirOwnLensAndCuesExactlyWhenTheyChange",
	"resetsTheSentViewsOnTheDealAndInLobby",
	"showsAnAcceptedPingInTheRoundViewUntilExpiryOrCommit",
	"refusesAPingToTheSenderAloneDecliningOnce",
	"broadcastsAShownPresetAtTheStoredPositionAndFailsToTheSenderAlone",
	"broadcastsOneFacilityViewOnTheDealBeforeTheRoundViewAndNeverOtherwise",
	"ordersEffectsWithinAStepAsTheContractLists",
}

function SessionChannelContract.failures(
	S: Session,
	only: { string }?
): { { name: string, message: string } }
	local out: { { name: string, message: string } } = {}
	for _, check in SessionChannelContract.CHECKS do
		if only ~= nil and not contains(only, check.name) then
			continue
		end
		local ok, err = pcall(check.run, S)
		if not ok then
			table.insert(out, { name = check.name, message = tostring(err) })
		end
	end
	return out
end

return SessionChannelContract
