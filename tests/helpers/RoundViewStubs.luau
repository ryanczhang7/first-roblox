--!strict
--[[
	The wrong view builders VIEW-003's controls are aimed at, and the
	reference each of them is a single defect away from.

	A FACTORY OVER A TABLE OF DEFECTS, as `LensViewStubs.luau` is: `defects`
	is empty for the reference and has exactly ONE field set for every
	control, so a control that fires is attributable to that one thing. The
	story's C-12 names its controls: a bar with `track`, `next` or `byTrack`
	(AC-1), `dial.setting` from `requiredSetting` (AC-2), a facility machine
	carrying `requiredSetting` (AC-3), an unclamped `secondsLeft` and one from
	the unpenalised clock (AC-4), an extra top-level `outcome`, `par` or
	`seats` (AC-5), `committed` counted from `#log` (C-4), `partnerLamp` on a
	non-finale machine (C-5), a view sharing a table with the input (C-9).
	The rest are the one-defect builders the other pins would otherwise have
	no control for.

	WHAT THIS IS NOT: it is not `src/server/round/RoundView.luau` and not a
	sketch of one. Every type is `any` and it uses whatever is shortest.
	GREEN writes the module from the story's Contract against the failing
	tests in `tests/server/round_view_test.luau`; nothing here is to be
	copied.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE. `Procedure` is merged, so
	every number the controls file asserts is a measurement taken in RED, not
	a claim left for GREEN.
]]

local Procedure = require("../../src/server/procedure/Procedure")

local RoundViewStubs = {}

export type Defects = {
	-- AC-1 / C-4
	progressTrack: boolean?, -- progress.track = the track of the last commit
	progressNext: boolean?, -- progress.next = the next live machine id
	progressByTrack: boolean?, -- progress.byTrack = per-track counts
	committedFromLog: boolean?, -- progress.committed = #procedure.log
	totalFromSteps: boolean?, -- progress.total = #steps rather than procedure_length
	-- AC-2 / C-5
	settingFromRequired: boolean?, -- a live rejected or armed machine shows requiredSetting
	settingFromRequiredWhenUnset: boolean?, -- a live unset machine shows requiredSetting
	armedReadAsUnset: boolean?, -- state from Procedure.dial alone, so armed reads unset
	settingIgnoresNotLiveTurns: boolean?, -- a not_live turn does not count as "turned"
	settingFromDials: boolean?, -- setting from procedure.dials[id].setting, state as the Contract
	partnerLampEverywhere: boolean?, -- partnerLamp on every machine
	partnerLampIgnoresPositions: boolean?, -- partnerLamp = finale live, positions unread
	partnerLampWithoutAssignmentIsNil: boolean?, -- absent rather than false when assignment is nil
	machinesDescending: boolean?, -- machines in descending id
	liveFromPosition: boolean?, -- live = first uncommitted of its track (finale rule ignored)
	-- AC-3 / C-8
	facilityWithRequiredSetting: boolean?,
	facilityWithPar: boolean?,
	facilityDoorsAsGiven: boolean?, -- doors copied in the layout's order and orientation
	facilityAliasesRooms: boolean?, -- rooms IS layout.rooms
	-- AC-4 / C-7
	unclampedSecondsLeft: boolean?,
	secondsLeftIgnoresPenalties: boolean?, -- startedAt + roundSeconds - now
	secondsLeftFromConfigDuration: boolean?, -- SLICE-003's rule in Round too
	-- AC-5
	extraOutcome: boolean?,
	extraPar: boolean?,
	extraSeats: boolean?,
	-- C-3
	readsProcedureOutsideRound: boolean?, -- procedure fields whenever a Procedure is held
	pingsOnlyInRound: boolean?, -- pings = {} outside Round
	-- C-6
	darkDescending: boolean?, -- dark sorted descending
	-- C-9
	sharesPlayers: boolean?, -- players IS round.players
	sharesPings: boolean?, -- pings IS input.pings
	sharesPingEntries: boolean?, -- a new list of the same entry tables
}

local function machineById(facility: any, id: number): any
	for _, m in facility.placement.machines do
		if m.id == id then
			return m
		end
	end
	return nil
end

local function sortedIds(facility: any, descending: boolean?): { number }
	local ids: { number } = {}
	for _, m in facility.placement.machines do
		table.insert(ids, m.id)
	end
	table.sort(ids, function(a: number, b: number): boolean
		if descending then
			return a > b
		end
		return a < b
	end)
	return ids
end

local function copyPing(p: any): any
	local out: any = { senderId = p.senderId, kind = p.kind, target = p.target }
	if p.setting ~= nil then
		out.setting = p.setting
	end
	return out
end

local function make(defects: Defects): any
	local V = {}

	local function secondsLeft(input: any, now: number): number?
		local round = input.round
		local c = round.config
		local raw: number
		if
			round.phase == "Round"
			and input.procedure ~= nil
			and not defects.secondsLeftFromConfigDuration
		then
			local p = input.procedure
			if defects.secondsLeftIgnoresPenalties then
				raw = math.ceil(p.startedAt + p.roundSeconds - now)
			else
				raw = math.ceil(Procedure.deadline(p) - now)
			end
		else
			local duration: number? = nil
			if round.phase == "Lobby" and #round.players >= c.playersMin then
				duration = c.lobbySeconds
			elseif round.phase == "Round" then
				duration = c.roundSeconds
			elseif round.phase == "Post" then
				duration = c.postRoundSeconds
			end
			if duration == nil then
				return nil
			end
			raw = math.ceil(duration - (now - round.phaseEnteredAt))
		end
		if defects.unclampedSecondsLeft then
			return raw
		end
		return math.max(0, raw)
	end

	local function lastTurned(procedure: any, id: number): number?
		if defects.settingFromDials then
			local d = procedure.dials[id]
			return if d then d.setting else nil
		end
		for i = #procedure.log, 1, -1 do
			local e = procedure.log[i]
			if
				e.machineId == id
				and not (defects.settingIgnoresNotLiveTurns and e.result == "not_live")
			then
				return e.setting
			end
		end
		return nil
	end

	local function dialOf(procedure: any, id: number, now: number): any
		local state: string
		if procedure.committed[id] then
			state = "committed"
		elseif
			not defects.armedReadAsUnset
			and procedure.armed ~= nil
			and procedure.armed.machineId == id
		then
			state = "armed"
		elseif Procedure.dial(procedure, id, now).state == "rejected" then
			state = "rejected"
		else
			state = "unset"
		end
		local dial: any = { state = state }
		if state ~= "unset" then
			dial.setting = lastTurned(procedure, id)
		end
		local live = Procedure.isLive(procedure, id)
		if defects.settingFromRequired and live and (state == "rejected" or state == "armed") then
			-- The story's control: a live machine's turned dial reads the secret.
			dial.setting = machineById(procedure.facility, id).requiredSetting
		end
		if defects.settingFromRequiredWhenUnset and live and state == "unset" then
			dial.setting = machineById(procedure.facility, id).requiredSetting
		end
		return dial
	end

	local function liveOf(procedure: any, id: number): boolean
		if defects.liveFromPosition then
			for _, track in procedure.facility.steps.tracks do
				for _, step in track do
					if not procedure.committed[step] then
						if step == id then
							return true
						end
						break
					end
				end
			end
			return false
		end
		return Procedure.isLive(procedure, id)
	end

	local function machinesOf(input: any, now: number): { any }
		local procedure = input.procedure
		local facility = procedure.facility
		local finale = facility.steps.finale
		local lamps: { [number]: boolean } = {}
		if input.assignment ~= nil then
			if defects.partnerLampIgnoresPositions then
				local live = Procedure.isLive(procedure, finale[1])
					and Procedure.isLive(procedure, finale[2])
				lamps = { [finale[1]] = live, [finale[2]] = live }
			else
				lamps = Procedure.partnerLamps(procedure, input.assignment, input.positions)
			end
		end
		local out: { any } = {}
		for _, id in sortedIds(facility, defects.machinesDescending) do
			local record: any =
				{ id = id, dial = dialOf(procedure, id, now), live = liveOf(procedure, id) }
			if table.find(finale, id) ~= nil or defects.partnerLampEverywhere then
				if defects.partnerLampWithoutAssignmentIsNil and input.assignment == nil then
					record.partnerLamp = nil
				else
					record.partnerLamp = lamps[id] == true
				end
			end
			table.insert(out, record)
		end
		return out
	end

	local function darkOf(procedure: any): { number }
		local out: { number } = {}
		for _, room in procedure.facility.layout.rooms do
			if procedure.dark[room.id] == true then
				table.insert(out, room.id)
			end
		end
		table.sort(out, function(a: number, b: number): boolean
			if defects.darkDescending then
				return a > b
			end
			return a < b
		end)
		return out
	end

	local function committedOf(procedure: any): number
		if defects.committedFromLog then
			return #procedure.log
		end
		local n = 0
		for _, flag in pairs(procedure.committed) do
			if flag == true then
				n += 1
			end
		end
		return n
	end

	function V.public(input: any, now: number): any
		local round = input.round
		local total = input.tuning.instance.procedure_length
		if defects.totalFromSteps and input.procedure ~= nil then
			total = 0
			for _, track in input.procedure.facility.steps.tracks do
				total += #track
			end
		end
		local pings: any
		if defects.sharesPings then
			pings = input.pings
		elseif defects.pingsOnlyInRound and round.phase ~= "Round" then
			pings = {}
		else
			pings = {}
			for _, p in input.pings do
				table.insert(pings, if defects.sharesPingEntries then p else copyPing(p))
			end
		end
		local view: any = {
			phase = round.phase,
			secondsLeft = secondsLeft(input, now),
			players = if defects.sharesPlayers then round.players else table.clone(round.players),
			playersMin = round.config.playersMin,
			playersMax = round.config.playersMax,
			progress = { committed = 0, total = total },
			instability = 0,
			dark = {},
			pings = pings,
			machines = {},
		}
		local inRound = round.phase == "Round" and input.procedure ~= nil
		if defects.readsProcedureOutsideRound then
			inRound = input.procedure ~= nil
		end
		if inRound then
			local procedure = input.procedure
			view.instability = procedure.instability
			view.dark = darkOf(procedure)
			view.progress.committed = committedOf(procedure)
			view.machines = machinesOf(input, now)
			if defects.progressTrack then
				view.progress.track = 1
			end
			if defects.progressNext then
				for _, id in sortedIds(procedure.facility) do
					if Procedure.isLive(procedure, id) then
						view.progress.next = id
						break
					end
				end
			end
			if defects.progressByTrack then
				local byTrack: { number } = {}
				for t, track in procedure.facility.steps.tracks do
					byTrack[t] = 0
					for _, id in track do
						if procedure.committed[id] then
							byTrack[t] += 1
						end
					end
				end
				view.progress.byTrack = byTrack
			end
		end
		if defects.extraOutcome then
			local outcome = if input.procedure then input.procedure.outcome else nil
			view.outcome = if outcome then table.clone(outcome) else false
		end
		if defects.extraPar then
			view.par = if input.procedure then input.procedure.facility.par else 0
		end
		if defects.extraSeats then
			view.seats = if input.assignment then table.clone(input.assignment.sigma) else {}
		end
		return view
	end

	function V.facility(facility: any): any
		local rooms: { any }
		if defects.facilityAliasesRooms then
			rooms = facility.layout.rooms
		else
			rooms = {}
			for _, room in facility.layout.rooms do
				table.insert(rooms, { id = room.id, column = room.column, row = room.row })
			end
			table.sort(rooms, function(a: any, b: any): boolean
				return a.id < b.id
			end)
		end
		local doors: { any } = {}
		for _, door in facility.layout.doors do
			if defects.facilityDoorsAsGiven then
				table.insert(doors, { a = door.a, b = door.b })
			else
				table.insert(doors, { a = math.min(door.a, door.b), b = math.max(door.a, door.b) })
			end
		end
		if not defects.facilityDoorsAsGiven then
			table.sort(doors, function(x: any, y: any): boolean
				if x.a ~= y.a then
					return x.a < y.a
				end
				return x.b < y.b
			end)
		end
		local machines: { any } = {}
		for _, id in sortedIds(facility) do
			local m = machineById(facility, id)
			local record: any =
				{ id = m.id, room = m.room, slot = m.slot, tag = m.tag, keyClass = m.keyClass }
			if defects.facilityWithRequiredSetting then
				record.requiredSetting = m.requiredSetting
			end
			table.insert(machines, record)
		end
		local view: any = {
			rooms = rooms,
			doors = doors,
			spawnRoom = facility.layout.spawnRoom,
			machines = machines,
		}
		if defects.facilityWithPar then
			view.par = facility.par
		end
		return view
	end

	return V
end

RoundViewStubs.make = make
RoundViewStubs.reference = make({})

-- Every one-defect builder, by the defect's name.
RoundViewStubs.DEFECTS = {
	"progressTrack",
	"progressNext",
	"progressByTrack",
	"committedFromLog",
	"totalFromSteps",
	"settingFromRequired",
	"settingFromRequiredWhenUnset",
	"armedReadAsUnset",
	"settingIgnoresNotLiveTurns",
	"settingFromDials",
	"partnerLampEverywhere",
	"partnerLampIgnoresPositions",
	"partnerLampWithoutAssignmentIsNil",
	"machinesDescending",
	"liveFromPosition",
	"facilityWithRequiredSetting",
	"facilityWithPar",
	"facilityDoorsAsGiven",
	"facilityAliasesRooms",
	"unclampedSecondsLeft",
	"secondsLeftIgnoresPenalties",
	"secondsLeftFromConfigDuration",
	"extraOutcome",
	"extraPar",
	"extraSeats",
	"readsProcedureOutsideRound",
	"pingsOnlyInRound",
	"darkDescending",
	"sharesPlayers",
	"sharesPings",
	"sharesPingEntries",
}

function RoundViewStubs.with(defect: string): any
	local defects: any = {}
	defects[defect] = true
	return make(defects)
end

return RoundViewStubs
