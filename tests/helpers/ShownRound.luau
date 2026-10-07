--!strict
--[[
	SLICE-006 C-10: the scripted round played AS PLAYERS. The oracle for AC-2.

	THIS SCRIPT NEVER READS THE SECRET. `ScriptedRound.luau`'s header says its
	scripts "may read the secret - the steps, the helpers and turners through
	`state.facility`, `state.assignment` and `Ring`"; that is NOT true of this
	one. Every decision below is a function of an INBOX built only from the
	session's effects - the `SendTo`s addressed to that player and every
	`Broadcast` - plus the player's own position (the script moved it), the
	tuning, and `Machines.positionOf` applied to `FacilityView` rooms and
	slots. The decision functions (`goalOf`, `pingOf`, `turnOf`) take exactly
	`(inbox, position, tuning)`: no driver, no state, no facility, no
	assignment, no `requiredSetting` is in scope, which a reader can check
	from the signatures. So a broken lens, a broken ping or broken routing
	leaves the script UNABLE TO ACT, never able to cheat, and the round ends
	`lost / clock`.

	WHAT EACH PLAYER MAY READ (C-10's table):
	  everyone   its own SeatView (`lensClass`, `supplierId`, `dependentId`),
	             the FacilityView, the latest RoundView, its own position.
	  helper q   its own latest LensView.
	  turner t   its own TurnCues; `PingShown` entries FROM `t`'s supplierId
	             in the latest RoundView.

	THE RULES. Every simulated second: a Tick; every player picks a machine
	to stand at and walks up to `walk_speed_studs_per_second` towards it; one
	PositionsSampled for everyone; then, in seat order, each player pings if
	it can and then each turns if it can. A player's goal is, in order: an
	OWN live machine whose supplier's ping is shown (turn first); its
	DEPENDENT's live, uncommitted machine (go and read it - a helper stays
	there while the machine is live, re-pinging when its ping expires); an
	own live machine to wait at. A helper pings `{ setting, target = m,
	setting = s }` only for a reading `{ machineId = m, setting = s }` in its
	own latest LensView and only when no ping of its own naming `m` is shown.
	A turner turns `m` to `s` only when it stands within `turn_range_studs` of
	`m`, `m` is in its TurnCues' `live` list, and its supplier's PingShown
	names `m` and `s`; a machine carrying a `partnerLamp` (the finale's two,
	public in the RoundView) is turned only when the lamp is lit, so the two
	finale turners turn at the SAME `now` (the lamp means the partner is in
	place). No ping, no turn: the turner never guesses. With `pings = false`
	the helper never pings - the control - and nothing else changes.

	THE OUTCOME IS READ FROM `state.round` BY THE TEST. The loop below reads
	`state.round.phase` to know when to stop, as `ScriptedRound.clockOut`
	does; no player decision sees it. The `observe` hook hands the test every
	step's effects with the assignment and facility (for AC-6's class check,
	which the TEST may read); players never see it.

	THE SIGHT PORT IS A CONSTANT TRUE (`ScriptedRound.PORTS`): headlessly
	there is no geometry, so range, class, darkness and commitment are the
	clauses in play.

	SIMULATED-TIME BUDGET. One walk is at most `maxMoveSeconds` (15 s at the
	shipped values); a ping lasts `ping_display_seconds` (15 s) and a helper
	re-pings on expiry while it stands at the machine, so a turner that
	starts walking the second a ping is shown always arrives inside a shown
	ping. Two tracks progress in parallel; the measured figures are in the
	story's handoff.
]]

local Deep = require("./Deep")
local Machines = require("../../src/server/facility/Machines")
local ScriptedRound = require("./ScriptedRound")

local ShownRound = {}

export type Vec = ScriptedRound.Vec

-- What one player knows: the last payload of each kind sent to it or
-- broadcast, and nothing else.
export type Inbox = {
	playerId: string,
	seatView: any?,
	facilityView: any?,
	roundView: any?,
	lensView: any?,
	turnCues: any?,
	-- Counts, for the record only.
	lensViews: number,
	turnCuesSent: number,
	turnResults: { any },
	pingRefusals: { any },
}

export type Options = {
	pings: boolean?, -- default true; false is AC-2's control
	-- Every step's effects, with the world the TEST may read (never a player).
	observe: ((now: number, effects: { any }, world: { assignment: any, facility: any }) -> ())?,
	tuning: any?,
}

export type Run = {
	seed: number,
	n: number,
	won: boolean,
	outcome: { phase: string, outcome: any? },
	startedAt: number,
	resolvedAt: number?,
	elapsed: number,
	steps: number,
	turns: { ScriptedRound.TurnRecord },
	pings: { ScriptedRound.PingRecord },
	declines: number,
	refusedPings: number,
	inboxes: { [string]: Inbox },
	-- The TEST's view of the world, for AC-6; never handed to a player.
	assignment: any,
	facility: any,
}

local function newInbox(playerId: string): Inbox
	return {
		playerId = playerId,
		seatView = nil,
		facilityView = nil,
		roundView = nil,
		lensView = nil,
		turnCues = nil,
		lensViews = 0,
		turnCuesSent = 0,
		turnResults = {},
		pingRefusals = {},
	}
end

local function horizontal(a: Vec, b: Vec): number
	local dx = b.x - a.x
	local dz = b.z - a.z
	return math.sqrt(dx * dx + dz * dz)
end

--[[ ------------------------------------------------------------------------
     Reading the inbox. Nothing below takes a driver or a state.
     --------------------------------------------------------------------- ]]

-- The FacilityView entry for machine `id`, or nil.
local function facilityMachine(inbox: Inbox, id: number): any?
	local fv = inbox.facilityView
	if fv == nil then
		return nil
	end
	for _, m in fv.machines do
		if m.id == id then
			return m
		end
	end
	return nil
end

-- Where machine `id` is, from PUBLIC data: FacilityView rooms and the
-- machine's room and slot, through `Machines.positionOf`.
function ShownRound.machinePosition(inbox: Inbox, id: number, tuning: any): Vec?
	local fv = inbox.facilityView
	local m = facilityMachine(inbox, id)
	if fv == nil or m == nil then
		return nil
	end
	local layout = { rooms = fv.rooms, doors = fv.doors, spawnRoom = fv.spawnRoom }
	return Machines.positionOf(layout :: any, { room = m.room, slot = m.slot } :: any, tuning)
end

-- The RoundView's public record for machine `id`, or nil.
local function publicMachine(inbox: Inbox, id: number): any?
	local rv = inbox.roundView
	if rv == nil then
		return nil
	end
	for _, m in rv.machines do
		if m.id == id then
			return m
		end
	end
	return nil
end

-- The dependent's machines - those of my lens class - that are live and not
-- committed, ascending by id. Both facts are public.
local function dependentsLiveMachines(inbox: Inbox): { number }
	local out: { number } = {}
	local sv = inbox.seatView
	local fv = inbox.facilityView
	if sv == nil or fv == nil then
		return out
	end
	for _, m in fv.machines do
		if m.keyClass == sv.lensClass then
			local pub = publicMachine(inbox, m.id)
			if pub ~= nil and pub.live == true and pub.dial.state ~= "committed" then
				table.insert(out, m.id)
			end
		end
	end
	table.sort(out)
	return out
end

-- My own live machines: the TurnCues' `live` list, as sent.
local function ownLiveMachines(inbox: Inbox): { number }
	local cues = inbox.turnCues
	if cues == nil then
		return {}
	end
	local out = table.clone(cues.live)
	table.sort(out)
	return out
end

-- A shown setting ping from `senderId` naming machine `id`, or nil.
local function shownSettingPing(inbox: Inbox, senderId: string, id: number): any?
	local rv = inbox.roundView
	if rv == nil then
		return nil
	end
	for _, ping in rv.pings do
		if ping.senderId == senderId and ping.kind == "setting" and ping.target == id then
			return ping
		end
	end
	return nil
end

-- My lens's reading of machine `id`, or nil.
local function readingOf(inbox: Inbox, id: number): number?
	local lv = inbox.lensView
	if lv == nil then
		return nil
	end
	for _, r in lv.readings do
		if r.machineId == id then
			return r.setting
		end
	end
	return nil
end

--[[ ------------------------------------------------------------------------
     The decisions. Exactly (inbox, position, tuning); see the header.
     --------------------------------------------------------------------- ]]

-- The machine to stand at, or nil to stay put.
function ShownRound.goalOf(inbox: Inbox, _position: Vec, _tuning: any): number?
	local sv = inbox.seatView
	if sv == nil then
		return nil
	end
	for _, id in ownLiveMachines(inbox) do
		if shownSettingPing(inbox, sv.supplierId, id) ~= nil then
			return id -- turn first: my supplier has told me
		end
	end
	local help = dependentsLiveMachines(inbox)
	if #help > 0 then
		return help[1] -- read it for my dependent
	end
	local own = ownLiveMachines(inbox)
	if #own > 0 then
		return own[1] -- wait at my own machine
	end
	return nil
end

-- A setting ping to make now, or nil. Only for a reading in MY lens.
function ShownRound.pingOf(inbox: Inbox, position: Vec, tuning: any): any?
	local sv = inbox.seatView
	if sv == nil then
		return nil
	end
	local range = tuning.channel.ping_range_studs
	for _, id in dependentsLiveMachines(inbox) do
		local at = ShownRound.machinePosition(inbox, id, tuning)
		if at ~= nil and horizontal(position, at) <= range then
			local setting = readingOf(inbox, id)
			if setting ~= nil and shownSettingPing(inbox, sv.playerId, id) == nil then
				return { kind = "setting", target = id, setting = setting }
			end
		end
	end
	return nil
end

-- A turn to make now, or nil. Only to a setting MY SUPPLIER has pinged.
function ShownRound.turnOf(
	inbox: Inbox,
	position: Vec,
	tuning: any
): { machine: number, setting: number }?
	local sv = inbox.seatView
	if sv == nil then
		return nil
	end
	local range = tuning.instance.turn_range_studs
	for _, id in ownLiveMachines(inbox) do
		local at = ShownRound.machinePosition(inbox, id, tuning)
		if at ~= nil and horizontal(position, at) <= range then
			local ping = shownSettingPing(inbox, sv.supplierId, id)
			if ping ~= nil and ping.setting ~= nil then
				local pub = publicMachine(inbox, id)
				-- A finale machine (it carries a partner lamp) is turned only
				-- when the lamp says the partner's turner is in place.
				if pub ~= nil and pub.partnerLamp ~= nil and pub.partnerLamp ~= true then
					continue
				end
				return { machine = id, setting = ping.setting }
			end
		end
	end
	return nil
end

--[[ ------------------------------------------------------------------------
     The driver: routes effects to inboxes and runs the seconds.
     --------------------------------------------------------------------- ]]

-- Route one step's effects: a SendTo to its addressee's inbox, a Broadcast
-- to every inbox. Unknown kinds are kept out of every inbox.
local function deliver(inboxes: { [string]: Inbox }, effects: { any })
	for _, e in effects do
		if typeof(e) ~= "table" then
			continue
		end
		if e.kind == "SendTo" then
			local inbox = inboxes[e.playerId]
			if inbox == nil then
				continue
			end
			if e.payloadKind == "SeatView" then
				inbox.seatView = e.payload
			elseif e.payloadKind == "LensView" then
				inbox.lensView = e.payload
				inbox.lensViews += 1
			elseif e.payloadKind == "TurnCues" then
				inbox.turnCues = e.payload
				inbox.turnCuesSent += 1
			elseif e.payloadKind == "TurnResult" then
				table.insert(inbox.turnResults, e.payload)
			elseif e.payloadKind == "PingRefused" then
				table.insert(inbox.pingRefusals, e.payload)
			end
		elseif e.kind == "Broadcast" then
			for _, inbox in inboxes do
				if e.payloadKind == "RoundView" then
					inbox.roundView = e.payload
				elseif e.payloadKind == "FacilityView" then
					inbox.facilityView = e.payload
				end
			end
		end
	end
end

-- Move `p` up to `speed` studs along the straight line to `goal`.
local function advance(d: ScriptedRound.Driver, p: string, goal: Vec, speed: number)
	local at = d.positions[p]
	if at == nil then
		return
	end
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
	end
end

function ShownRound.play(S: ScriptedRound.Session, seed: number, n: number, options: Options?): Run
	local pingsOn = options == nil or options.pings ~= false
	local observe = if options ~= nil then options.observe else nil
	local driverOptions: ScriptedRound.Options? = if options ~= nil
			and options.tuning ~= nil
		then { tuning = options.tuning }
		else nil
	local d, dealEffects = ScriptedRound.start(S, seed, n, driverOptions)
	local tuning = d.tuning
	local speed = tuning.instance.walk_speed_studs_per_second
	local world = { assignment = d.state.assignment, facility = d.state.facility }

	local inboxes: { [string]: Inbox } = {}
	for _, p in d.players do
		inboxes[p] = newInbox(p)
	end
	local function take(effects: { any })
		deliver(inboxes, effects)
		if observe ~= nil then
			observe(d.now, effects, world)
		end
	end
	take(dealEffects)

	local startedAt = d.startedAt :: number
	local budget = startedAt + d.config.roundSeconds + 2
	local turns: { ScriptedRound.TurnRecord } = {}
	local pings: { ScriptedRound.PingRecord } = {}
	local declines, refusedPings = 0, 0

	while d.state.round.phase == "Round" and d.now < budget do
		take(ScriptedRound.tick(d, 1))
		if d.state.round.phase ~= "Round" then
			break
		end
		for _, p in d.players do
			local goal = ShownRound.goalOf(inboxes[p], d.positions[p], tuning)
			if goal ~= nil then
				local at = ShownRound.machinePosition(inboxes[p], goal, tuning)
				if at ~= nil then
					advance(d, p, at, speed)
				end
			end
		end
		take(ScriptedRound.sample(d))
		if pingsOn then
			for _, p in d.players do
				local target = ShownRound.pingOf(inboxes[p], d.positions[p], tuning)
				if target ~= nil then
					local record = ScriptedRound.ping(d, p, target)
					take(record.effects)
					table.insert(pings, record)
					declines += record.call.declines
					if record.refused ~= nil then
						refusedPings += 1
					end
				end
			end
		end
		for _, p in d.players do
			if d.state.round.phase ~= "Round" then
				break
			end
			local turn = ShownRound.turnOf(inboxes[p], d.positions[p], tuning)
			if turn ~= nil then
				local record = ScriptedRound.turn(d, p, turn.machine, turn.setting)
				take(record.effects)
				table.insert(turns, record)
			end
		end
	end

	local outcome = ScriptedRound.outcome(d)
	local won = outcome.phase ~= "Round"
		and typeof(outcome.outcome) == "table"
		and outcome.outcome.result == "won"
		and outcome.outcome.reason == "procedure_complete"
	return {
		seed = seed,
		n = n,
		won = won,
		outcome = outcome,
		startedAt = startedAt,
		resolvedAt = if outcome.phase ~= "Round" then d.now else nil,
		elapsed = d.now - startedAt,
		steps = d.steps,
		turns = turns,
		pings = pings,
		declines = declines,
		refusedPings = refusedPings,
		inboxes = inboxes,
		assignment = Deep.copy(world.assignment),
		facility = world.facility,
	}
end

return ShownRound
