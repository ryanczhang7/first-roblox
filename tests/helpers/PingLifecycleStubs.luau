--!strict
--[[
	The wrong lifecycles CHAN-006's negative controls are aimed at, and the one
	reference every check in `PingLifecycleContract.luau` must ACCEPT.

	THE CRITERIA AND THE DEFERRED VERIFICATIONS NAME THEIR CONTROLS. AC-1: "an
	implementation that appends must fail, holding 2" - `appendsUnderDistinctKey`,
	which is also D-1's shape. D-2's shape is `strictExpiry` (`>=` turned to
	`>` at the boundary); D-3's is `commitIgnoresKind` (the kind check dropped,
	so a doorway numbered like the machine is cleared too); D-4's is
	`shownLeaksAt` (`at` copied into the public payload). Each is here as an
	implementation, so that what GATES will mutate into the real module has
	already been seen to be caught by the checks that will judge it.

	THE POSITIVE CONTROL is `reference`: the Contract's C-2 .. C-8 written out.
	It exists so that every check is shown to ACCEPT a correct implementation
	in RED: a check that refuses everything is indistinguishable from a broken
	one. Each wrong implementation is the reference with EXACTLY ONE thing
	changed, so the set of checks that fire is attributable to that one
	change, and `ping_lifecycle_controls_test.luau` pins that set EXACTLY.

	`request` and `targetPosition` are CHAN-005's and are not under test
	here; the one check that drives them (AC-5's refusal clause) borrows
	`PingsStubs.reference`'s, which `pings_controls_test.luau` has already
	shown to accept and refuse correctly.

	WHAT THIS IS NOT: `src/server/channel/Pings.luau`, or a sketch of one. It
	exports no types, freezes nothing, and its defects are parameters. GREEN
	writes the module from the story's Contract; nothing here is to be copied.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE - `MechanicsTuning` and
	CHAN-005's `Pings` are merged - so these controls are EXECUTED in RED, and
	the controls test records what each measured.
]]

local MechanicsTuning = require("../../src/ReplicatedStorage/Shared/MechanicsTuning")
local PingsStubs = require("./PingsStubs")

local PingLifecycleStubs = {}

export type Defect =
	"appendsUnderDistinctKey" -- AC-1's control, D-1: a second ping by one sender is stored beside the first
	| "keyedByTarget" -- the active set is keyed by target, not sender
	| "strictExpiry" -- D-2: a ping is gone only when now > at + d (still there at exactly at + d)
	| "hardCodedDuration" -- the duration is MechanicsTuning's, not the tuning handed to tick
	| "tickTrimsTheLog" -- tick drops the log entries of expired pings
	| "commitIgnoresKind" -- D-3: a commit clears every ping whose target number is m, doorways included
	| "commitClearsOnlySettings" -- a machine ping on the committed machine survives
	| "commitTrimsTheLog" -- onCommitted drops the log entries it cleared
	| "replacementTrimsTheLog" -- a replacement drops the sender's earlier log entries
	| "logsEveryAcceptTwice" -- two log entries per accept
	| "logOmitsRoomLit" -- the log entry has no roomLit
	| "doorwayLogsRoomLitAsGiven" -- a doorway ping logs the roomLit it was passed
	| "shownLeaksAt" -- D-4: the public payload carries `at`
	| "shownReturnsActiveEntries" -- the public payload IS the active entries
	| "shownUnsorted" -- the public payload is sorted descending by sender
	| "shownDropsSetting" -- the public payload never carries `setting`
	| "acceptMutatesInPlace" -- accept writes into the state it was given and returns it
	| "tickMutatesInput" -- tick removes from the state it was given
	| "commitMutatesInput" -- onCommitted removes from the state it was given
	| "newIsASingleton" -- new() returns one shared state
	| "newCarriesACounter" -- new() has a third key

PingLifecycleStubs.DEFECTS = {
	"appendsUnderDistinctKey",
	"keyedByTarget",
	"strictExpiry",
	"hardCodedDuration",
	"tickTrimsTheLog",
	"commitIgnoresKind",
	"commitClearsOnlySettings",
	"commitTrimsTheLog",
	"replacementTrimsTheLog",
	"logsEveryAcceptTwice",
	"logOmitsRoomLit",
	"doorwayLogsRoomLitAsGiven",
	"shownLeaksAt",
	"shownReturnsActiveEntries",
	"shownUnsorted",
	"shownDropsSetting",
	"acceptMutatesInPlace",
	"tickMutatesInput",
	"commitMutatesInput",
	"newIsASingleton",
	"newCarriesACounter",
} :: { Defect }

type Vec = { x: number, y: number, z: number }

-- The copy idiom: a new outer table, a new active map, a new log list.
local function fresh(state: any): any
	return { active = table.clone(state.active), log = table.clone(state.log) }
end

local function dropFromLog(log: { any }, keep: (any) -> boolean)
	local i = 1
	while i <= #log do
		if keep(log[i]) then
			i += 1
		else
			table.remove(log, i)
		end
	end
end

-- The module table for `defect` (nil: the reference).
function PingLifecycleStubs.with(defect: Defect?): any
	local singleton: any = { active = {}, log = {} }

	local function new(): any
		if defect == "newIsASingleton" then
			return singleton
		end
		local state: any = { active = {}, log = {} }
		if defect == "newCarriesACounter" then
			state.count = 0
		end
		return state
	end

	local function accept(
		state: any,
		senderId: string,
		target: any,
		position: Vec,
		now: number,
		roomLit: boolean
	): any
		local next_ = if defect == "acceptMutatesInPlace" then state else fresh(state)
		local entry = {
			senderId = senderId,
			kind = target.kind,
			target = target.target,
			setting = target.setting,
			at = now,
		}
		local key = senderId
		if defect == "appendsUnderDistinctKey" then
			key = `{senderId}#{#next_.log + 1}`
		elseif defect == "keyedByTarget" then
			key = `{target.kind}{target.target}`
		end
		if defect == "replacementTrimsTheLog" then
			dropFromLog(next_.log, function(e: any): boolean
				return e.senderId ~= senderId
			end)
		end
		next_.active[key] = entry
		local lit = roomLit
		if target.kind == "doorway" and defect ~= "doorwayLogsRoomLitAsGiven" then
			lit = true
		end
		local logged: any = {
			senderId = senderId,
			kind = target.kind,
			target = target.target,
			setting = target.setting,
			position = { x = position.x, y = position.y, z = position.z },
			at = now,
			roomLit = lit,
		}
		if defect == "logOmitsRoomLit" then
			logged.roomLit = nil
		end
		table.insert(next_.log, logged)
		if defect == "logsEveryAcceptTwice" then
			table.insert(next_.log, table.clone(logged))
		end
		return next_
	end

	local function tick(state: any, now: number, tuning: any): any
		local d = if defect == "hardCodedDuration"
			then MechanicsTuning.channel.ping_display_seconds
			else tuning.channel.ping_display_seconds
		local next_ = if defect == "tickMutatesInput" then state else fresh(state)
		for key, entry in pairs(table.clone(next_.active)) do
			local expired = if defect == "strictExpiry"
				then now > entry.at + d
				else now >= entry.at + d
			if expired then
				next_.active[key] = nil
			end
		end
		if defect == "tickTrimsTheLog" then
			dropFromLog(next_.log, function(e: any): boolean
				return now < e.at + d
			end)
		end
		return next_
	end

	local function clearedByCommit(entry: any, machineId: number): boolean
		if entry.target ~= machineId then
			return false
		end
		if defect == "commitIgnoresKind" then
			return true
		end
		if defect == "commitClearsOnlySettings" then
			return entry.kind == "setting"
		end
		return entry.kind == "setting" or entry.kind == "machine"
	end

	local function onCommitted(state: any, machineId: number): any
		local next_ = if defect == "commitMutatesInput" then state else fresh(state)
		for key, entry in pairs(table.clone(next_.active)) do
			if clearedByCommit(entry, machineId) then
				next_.active[key] = nil
			end
		end
		if defect == "commitTrimsTheLog" then
			dropFromLog(next_.log, function(e: any): boolean
				return not clearedByCommit(e, machineId)
			end)
		end
		return next_
	end

	local function shown(state: any): { any }
		local out: { any } = {}
		for _, entry in pairs(state.active) do
			if defect == "shownReturnsActiveEntries" then
				table.insert(out, entry)
			else
				local public: any = {
					senderId = entry.senderId,
					kind = entry.kind,
					target = entry.target,
					setting = if defect == "shownDropsSetting" then nil else entry.setting,
				}
				if defect == "shownLeaksAt" then
					public.at = entry.at
				end
				table.insert(out, public)
			end
		end
		local descending = defect == "shownUnsorted"
		table.sort(out, function(a: any, b: any): boolean
			if descending then
				return a.senderId > b.senderId
			end
			return a.senderId < b.senderId
		end)
		return out
	end

	return {
		new = new,
		accept = accept,
		tick = tick,
		onCommitted = onCommitted,
		shown = shown,
		-- CHAN-005's, borrowed; not under test here.
		request = PingsStubs.reference.request,
		targetPosition = PingsStubs.reference.targetPosition,
		validate = PingsStubs.reference.validate,
	}
end

-- The positive control.
PingLifecycleStubs.reference = PingLifecycleStubs.with(nil)

return PingLifecycleStubs
