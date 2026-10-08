--!strict
--[[
	CHAN-005: whether a ping lands. Pure: no clock, no transport, no state of
	its own. The `Ping` remote's guard (`net/GameRemotes`) has already checked
	identity, shape, the schema's bounds, phase and both rate limits by the
	time a call gets here; what is left is the TARGET, which is a claim (B4).

	WHAT A PING TARGETS (`mechanics.md` §4.1, G9). Exactly one of a dial
	`setting` on a machine, a `machine`, or a `doorway`. There are no
	free-position pings, so the payload carries no position and nothing here
	would read one if it did: range is measured from the server's ACCEPTED
	position for the sender (`architecture.md` §9.8), never from the client.

	ONE SOURCE OF FACILITY AND TUNING (PO-1). Both are read from
	`procedure.facility` and `procedure.tuning`, as `Projection.lensFor` does,
	so no parameter can disagree with the procedure the round is playing.

	THE CHECK ORDER IS THE CONTRACT'S, FIRST FAILURE WINS (PO-2):

	  1. `setting_mismatch`  a `setting` ping without a setting, or a setting
	                         given for a `machine` or `doorway` ping;
	  2. `no_such_target`    no machine has that `id` (ids are not dense), or
	                         the doorway id is outside `1..#layout.doors`;
	  3. `committed_machine` the machine - or the machine the setting is on -
	                         is committed;
	  4. `no_position`       the sender has no accepted position sample;
	  5. `out_of_range`      horizontal (x, z) distance GREATER than
	                         `channel.ping_range_studs`. Inclusive, as
	                         `Procedure`'s `within` is: exactly the range lands;
	  6. `out_of_sight`      the line-of-sight port says no. Asked once, last,
	                         and only for a target that passed 1-5 (AC-5): a
	                         raycast is the expensive check, and a port asked
	                         for a target that does not exist is asked a
	                         question with no answer.

	NOT CHECKED, DELIBERATELY (PO-5). A dark room - a helper may ping a
	setting in a blacked-out room (`mechanics.md` §4.1) - and whether the
	machine is live (`ping_settings_live_only = false`, T20). `lensFor`'s dark
	check is not borrowed. `setting`'s own range is the schema's.

	POSITIONS. A machine or a setting is at `Machines.positionOf`. A doorway
	is the index of its `Door` in `layout.doors` (sorted by `(a, b)`, which
	`GEN-001` guarantees) and sits at the midpoint of its two rooms' centres,
	a centre being `((column - 1) x pitch, 0, (row - 1) x pitch)` - the formula
	`Machines.positionOf` and `Session`'s spawn centre use.

	`request` IS THE HANDLER'S CORE (PO-3). A refusal is not a send: it
	declines the call, so the guard refunds the send limit and only the
	attempt floor applies (G9, `CHAN-003`), and it returns a fresh
	`PingRefused` for the caller to send to the sender alone (`SLICE-006`).
	An accepted ping returns nil and leaves the call alone.

	CHAN-006: WHAT HAPPENS TO A PING THAT LANDS (`mechanics.md` §4.1, §8).
	`accept` records it in a `PingState`: the ACTIVE set, keyed by sender so
	each player has at most one live ping and a new one replaces the old at
	once, and the LOG, one entry per accepted ping, append-only, with the
	target's position and whether its room was lit (a doorway always is) for
	the trace's "read helper ping" (§7, G12). A ping leaves the active set
	when `tick` reaches `at + ping_display_seconds` (half-open) or when
	`onCommitted` clears the setting and machine pings on its machine;
	neither touches the log. `shown` is the public payload: sender, kind,
	target and setting, never a position or a time. All of it is pure and
	returns a new state; `SLICE-006` holds the state and wires the calls.
]]

local Machines = require("../facility/Machines")
local MechanicsTuning = require("@game/ReplicatedStorage/Shared/MechanicsTuning")
local Procedure = require("../procedure/Procedure")

local Pings = {}

export type PingTarget = {
	kind: "setting" | "machine" | "doorway",
	target: number,
	setting: number?,
}
export type Refusal =
	"no_such_target"
	| "committed_machine"
	| "out_of_range"
	| "out_of_sight"
	| "setting_mismatch"
	| "no_position"
export type PingRefused = { reason: Refusal }
-- Structural: `Wrapper.CallControl` satisfies it, and nothing else is read.
export type CallControl = { decline: () -> () }

type Vec = Procedure.Vec
type LineOfSight = (from: Vec, to: Vec) -> boolean

-- The machine whose `id` FIELD is `id`. Ids are not list indices.
local function machineById(procedure: Procedure.ProcedureState, id: number): Machines.Machine?
	for _, machine in procedure.facility.placement.machines do
		if machine.id == id then
			return machine
		end
	end
	return nil
end

local function roomCentre(procedure: Procedure.ProcedureState, roomId: number): Vec?
	local pitch = procedure.tuning.instance.room_pitch_studs
	for _, room in procedure.facility.layout.rooms do
		if room.id == roomId then
			return { x = (room.column - 1) * pitch, y = 0, z = (room.row - 1) * pitch }
		end
	end
	return nil
end

--[[
	Where `target` is, or nil when it does not exist (check 2). Does not look
	at `setting`. A doorway id outside `1..#layout.doors` - 0 included - finds
	no door, because `layout.doors` is a list and is indexed, never searched.
]]
function Pings.targetPosition(procedure: Procedure.ProcedureState, target: PingTarget): Vec?
	if target.kind == "doorway" then
		local door = procedure.facility.layout.doors[target.target]
		if door == nil then
			return nil
		end
		local a = roomCentre(procedure, door.a)
		local b = roomCentre(procedure, door.b)
		if a == nil or b == nil then
			return nil
		end
		return { x = (a.x + b.x) / 2, y = 0, z = (a.z + b.z) / 2 }
	end
	local machine = machineById(procedure, target.target)
	if machine == nil then
		return nil
	end
	return Machines.positionOf(procedure.facility.layout, machine, procedure.tuning)
end

local function settingMismatch(target: PingTarget): boolean
	if target.kind == "setting" then
		return target.setting == nil
	end
	return target.setting ~= nil
end

-- Horizontal (x, z) distance; height never matters to a ping.
local function horizontalDistance(from: Vec, to: Vec): number
	local dx = from.x - to.x
	local dz = from.z - to.z
	return math.sqrt(dx * dx + dz * dz)
end

-- `(true, nil)` when the ping lands, `(false, reason)` for the first check
-- that fails, in the order this module's header gives.
function Pings.validate(
	procedure: Procedure.ProcedureState,
	senderPosition: Vec?,
	target: PingTarget,
	lineOfSight: LineOfSight
): (boolean, Refusal?)
	if settingMismatch(target) then
		return false, "setting_mismatch"
	end
	local at = Pings.targetPosition(procedure, target)
	if at == nil then
		return false, "no_such_target"
	end
	if target.kind ~= "doorway" and procedure.committed[target.target] == true then
		return false, "committed_machine"
	end
	if senderPosition == nil then
		return false, "no_position"
	end
	local range = procedure.tuning.channel.ping_range_studs
	if horizontalDistance(senderPosition, at) > range then
		return false, "out_of_range"
	end
	local inSight = lineOfSight(senderPosition, at)
	if not inSight then
		return false, "out_of_sight"
	end
	return true, nil
end

local function refuse(call: CallControl, reason: Refusal): PingRefused
	call.decline()
	return { reason = reason }
end

--[[
	The guarded handler's core. Judges `target` from `positions[senderId]`, the
	server's accepted sample. A refusal declines `call` exactly once and
	returns a fresh `{ reason = reason }`, nothing else in it; acceptance
	returns nil and never touches `call`. A missing procedure (no round in
	progress) has no target to find.
]]
function Pings.request(
	procedure: Procedure.ProcedureState?,
	positions: { [string]: Vec },
	senderId: string,
	target: PingTarget,
	call: CallControl,
	lineOfSight: LineOfSight
): PingRefused?
	if procedure == nil then
		return refuse(call, "no_such_target")
	end
	local ok, reason = Pings.validate(procedure, positions[senderId], target, lineOfSight)
	if not ok then
		return refuse(call, reason :: Refusal)
	end
	return nil
end

--[[
	CHAN-006: an accepted ping's lifecycle. `PingState` holds the ACTIVE set,
	at most one ping per sender (`active_pings_per_player` = 1 is derived, so
	it is the map's key rather than a number read), and the LOG the trace
	reads. Every function returns a new state and never writes into the one
	it was given (the `Procedure` copy idiom).
]]
export type ActivePing = {
	senderId: string,
	kind: string,
	target: number,
	setting: number?,
	at: number,
}
export type PingLogEntry = {
	senderId: string,
	kind: string,
	target: number,
	setting: number?,
	position: Vec,
	at: number,
	roomLit: boolean,
}
export type PingState = { active: { [string]: ActivePing }, log: { PingLogEntry } }
export type PingShown = { senderId: string, kind: string, target: number, setting: number? }

-- A new outer table and a new active map; the log is shared until written.
local function withActive(state: PingState, active: { [string]: ActivePing }): PingState
	return { active = active, log = state.log }
end

function Pings.new(): PingState
	return { active = {}, log = {} }
end

--[[
	Records an accepted ping. Does not validate: `request` has. Replaces the
	sender's active ping at once and appends one log entry. `position` is the
	TARGET's (`targetPosition`), never the sender's; `roomLit` is the caller's
	`Procedure.isDark` answer for the target's room, and a doorway is always
	logged lit.
]]
function Pings.accept(
	state: PingState,
	senderId: string,
	target: PingTarget,
	position: Vec,
	now: number,
	roomLit: boolean
): PingState
	-- Widened to the Contract's `string`: table fields are invariant.
	local kind: string = target.kind
	local setting = if kind == "setting" then target.setting else nil
	local active = table.clone(state.active)
	active[senderId] = {
		senderId = senderId,
		kind = kind,
		target = target.target,
		setting = setting,
		at = now,
	}
	local log = table.clone(state.log)
	local entry: PingLogEntry = {
		senderId = senderId,
		kind = kind,
		target = target.target,
		setting = setting,
		position = { x = position.x, y = position.y, z = position.z },
		at = now,
		roomLit = kind == "doorway" or roomLit,
	}
	table.insert(log, entry)
	return { active = active, log = log }
end

-- Expiry is half-open: a ping made at `at` is gone at `now >= at + d`,
-- `d` being `channel.ping_display_seconds`. The log is untouched.
function Pings.tick(
	state: PingState,
	now: number,
	tuning: MechanicsTuning.MechanicsTuning
): PingState
	local duration = tuning.channel.ping_display_seconds
	local active: { [string]: ActivePing } = {}
	for senderId, ping in state.active do
		local expired = now >= ping.at + duration
		if not expired then
			active[senderId] = ping
		end
	end
	return withActive(state, active)
end

-- Machine `machineId` committed: its setting and machine pings clear. A
-- doorway with the same number is a different thing (doorway ids index
-- `layout.doors`) and stays. The log is untouched.
function Pings.onCommitted(state: PingState, machineId: number): PingState
	local active: { [string]: ActivePing } = {}
	for senderId, ping in state.active do
		local onMachine = ping.kind == "setting" or ping.kind == "machine"
		if not (onMachine and ping.target == machineId) then
			active[senderId] = ping
		end
	end
	return withActive(state, active)
end

-- The public payload: who pinged what, sorted by sender. No position, no
-- time, no expiry; `setting` only on a setting ping.
function Pings.shown(state: PingState): { PingShown }
	local shown: { PingShown } = {}
	for _, ping in state.active do
		local entry: PingShown =
			{ senderId = ping.senderId, kind = ping.kind, target = ping.target }
		if ping.kind == "setting" then
			entry.setting = ping.setting
		end
		table.insert(shown, entry)
	end
	table.sort(shown, function(a: PingShown, b: PingShown): boolean
		return a.senderId < b.senderId
	end)
	return shown
end

return table.freeze(Pings)
