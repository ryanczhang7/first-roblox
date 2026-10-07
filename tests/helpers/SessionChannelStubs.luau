--!strict
--[[
	The stand-in sessions SLICE-006's controls are aimed at, and the
	reference each of them is a single defect away from.

	`standIn(defects)` WRAPS SLICE-005's reference (`SessionRoundStubs.reference`,
	which already composes PhaseMachine, Ring, Generator, Procedure,
	TurnRequests and the Positions rule) with the layer this story adds: the
	required `ports`, the `channel` (`Pings`, `PresetSends`), the per-player
	views (`Projection.lensFor`, `turnCuesFor`) with change detection, the
	`FacilityView`, and the RoundView's contents-changed trigger. The pure
	modules it calls are DONE and frozen; nothing here re-implements them. With
	no defects it is the REFERENCE, the positive control: every check in
	`SessionChannelContract.luau` must ACCEPT it - and so must every SLICE-005
	and SLICE-003 check, which is where C-3's narrowings are seen to tolerate
	the new effects. Each control is the reference with EXACTLY ONE defect and
	pins the set of checks that fire EXACTLY.

	THE STORY NAMES ITS CONTROLS: a session that BROADCASTS lens views (AC-1),
	and the shapes of its deferred verifications - `Pings.shown` empty (D-1),
	a lens of the player's own class (D-2, the direction error), a diff that
	always says "changed" (D-3). The AC-2 control (helpers never ping) is a
	script option, not a stand-in. D-1..D-3 THEMSELVES mutate the real module
	and stay with GATES.

	WHAT THE REFERENCE IS NOT: `src/server/session/Session.luau`, or a sketch
	of one. GREEN writes the module from the story's Contract; nothing here is
	to be copied.
]]

local Deep = require("./Deep")
local Pings = require("../../src/server/channel/Pings")
local PresetSends = require("../../src/server/channel/PresetSends")
local Procedure = require("../../src/server/procedure/Procedure")
local Projection = require("../../src/server/seats/Projection")
local RoundView = require("../../src/server/round/RoundView")
local SessionRoundStubs = require("./SessionRoundStubs")

local SessionChannelStubs = {}

export type Defects = {
	-- C-2
	acceptsMissingPorts: boolean?, -- never raises; reads a nil port lazily
	-- AC-1 / C-6: the private views
	broadcastsLensViews: boolean?, -- the story's control: LensView as a Broadcast
	sendsLensToEveryone: boolean?, -- each player's lens to every seated player
	alwaysSendsLens: boolean?, -- D-3's shape: the diff always says "changed"
	lensOfOwnClass: boolean?, -- D-2's shape: the lens reads the player's own key class
	sentKeptAcrossRounds: boolean?, -- sent.lens/cues reset neither on the deal nor on entering Lobby: round 2's first view, equal to round 1's last, is not sent
	sendsWithdrawnPlayers: boolean?, -- a player no longer seated still gets their last lens
	-- AC-3 / C-4: pings
	pingsNeverShown: boolean?, -- D-1's shape: RoundView.pings always {}
	pingsNeverExpire: boolean?, -- Pings.tick never called
	pingsSurviveCommit: boolean?, -- Pings.onCommitted never called
	broadcastsPingRefused: boolean?, -- the refusal goes to everyone
	declinesAcceptedPing: boolean?, -- call.decline() on acceptance too
	pingsJudgedOutsideRound: boolean?, -- the held procedure is handed to Pings.request in Resolution/Post
	pingsShownOutsideRound: boolean?, -- RoundView.pings from the channel in every phase
	roundViewOnlyOnOldTriggers: boolean?, -- no broadcast when only the contents changed
	-- AC-4 / C-5: presets
	presetAtTheOrigin: boolean?, -- PresetShown.position is { 0, 0, 0 }, not the stored one
	presetIgnoresFilter: boolean?, -- shows the table's word whatever `filtered` says
	broadcastsPresetFailed: boolean?, -- the failure goes to everyone
	presetInventsAPosition: boolean?, -- a player with no stored position is shown at the origin
	presetWithoutPositionNotDeclined: boolean?, -- ... or the call is left undeclined
	-- AC-5 / C-7, C-9
	noFacilityView: boolean?,
	facilityViewOnEveryTick: boolean?,
	facilityViewOnFailedGeneration: boolean?, -- an empty FacilityView on a failed deal
	facilityViewAfterRoundView: boolean?, -- emitted last, after the RoundView
	-- C-8
	channelKeptInLobby: boolean?,
	channelResetInPost: boolean?,
}

local function sendTo(playerId: string, payloadKind: string, payload: any): any
	return { kind = "SendTo", playerId = playerId, payloadKind = payloadKind, payload = payload }
end

local function broadcast(payloadKind: string, payload: any): any
	return { kind = "Broadcast", payloadKind = payloadKind, payload = payload }
end

local function machineRoom(procedure: any, id: number): number?
	for _, m in procedure.facility.placement.machines do
		if m.id == id then
			return m.room
		end
	end
	return nil
end

-- C-6 as amended in RED: the RoundView comparison ignores `secondsLeft`,
-- which the clock moves on its own and the per-second Tick already covers.
local function sameRoundView(a: any, b: any): boolean
	if a == nil or b == nil then
		return false
	end
	local x = table.clone(a)
	local y = table.clone(b)
	x.secondsLeft = nil
	y.secondsLeft = nil
	return Deep.equal(x, y)
end

local function freshChannel(): any
	return { presets = PresetSends.new(), pings = Pings.new() }
end

function SessionChannelStubs.standIn(defects: Defects): any
	local inner = SessionRoundStubs.reference
	local S = {}

	function S.new(
		config: any,
		seed: number,
		roundId: string,
		sessionId: string,
		ports: any,
		options: any?
	): any
		if not defects.acceptsMissingPorts then
			if typeof(ports) ~= "table" or typeof(ports.lineOfSight) ~= "function" then
				error("Session.new: ports.lineOfSight must be a function (SLICE-006 C-2)", 2)
			end
		end
		local state = inner.new(config, seed, roundId, sessionId, ports, options)
		state.channel = freshChannel()
		state.sent = { roundView = nil, lens = {}, cues = {} }
		state.ports = ports
		return state
	end

	local function sight(state: any): any
		local ports = state.ports
		if ports == nil then
			return function(): boolean
				return true
			end
		end
		return ports.lineOfSight
	end

	-- D-2's shape: a lens built for the player's own first key class.
	local function lensOf(state: any, after: any, p: string): any
		local assignment = after.assignment
		if defects.lensOfOwnClass then
			local wrong = table.clone(assignment)
			wrong.lens = table.clone(assignment.lens)
			wrong.lens[p] = assignment.keyClasses[p][1]
			assignment = wrong
		end
		return Projection.lensFor(assignment, after.procedure, p, after.positions[p], sight(state))
	end

	function S.step(state: any, event: any, now: number): (any, { any })
		if event.kind == "SeatsAssigned" then
			return state, {}
		end

		local channel = state.channel
		local after: any
		local innerEffects: { any }
		local reply: any = nil
		local shown: any = nil

		if event.kind == "PingRequested" then
			after = table.clone(state)
			innerEffects = {}
			local procedure = if state.round.phase == "Round"
					or defects.pingsJudgedOutsideRound
				then state.procedure
				else nil
			local refused = Pings.request(
				procedure,
				state.positions,
				event.playerId,
				event.target,
				event.call,
				sight(state)
			)
			if refused ~= nil then
				reply = if defects.broadcastsPingRefused
					then broadcast("PingRefused", refused)
					else sendTo(event.playerId, "PingRefused", refused)
			else
				if defects.declinesAcceptedPing then
					event.call.decline()
				end
				local at = Pings.targetPosition(procedure, event.target) :: any
				local roomLit = true
				if event.target.kind ~= "doorway" then
					local room = machineRoom(procedure, event.target.target) :: number
					roomLit = not Procedure.isDark(procedure, room)
				end
				channel = {
					presets = channel.presets,
					pings = Pings.accept(
						channel.pings,
						event.playerId,
						event.target,
						at,
						now,
						roomLit
					),
				}
			end
		elseif event.kind == "PresetSent" then
			after = table.clone(state)
			innerEffects = {}
			local position = state.positions[event.playerId]
			if position == nil and defects.presetInventsAPosition then
				position = { x = 0, y = 0, z = 0 }
			end
			if position == nil then
				if not defects.presetWithoutPositionNotDeclined then
					event.call.decline()
				end
				return state, {}
			end
			if defects.presetAtTheOrigin then
				position = { x = 0, y = 0, z = 0 }
			end
			local function filter(_senderId: string, word: string): (boolean, string?)
				if defects.presetIgnoresFilter then
					return true, word
				end
				return event.filtered.ok, event.filtered.text
			end
			local presets, result = PresetSends.send(
				channel.presets,
				event.playerId,
				event.presetId,
				state.round.phase,
				position,
				now,
				filter,
				event.call
			)
			channel = { presets = presets, pings = channel.pings }
			if result.kind == "shown" then
				shown = broadcast("PresetShown", result.shown)
			else
				reply = if defects.broadcastsPresetFailed
					then broadcast("PresetFailed", result.failed)
					else sendTo(event.playerId, "PresetFailed", result.failed)
			end
		else
			local stepped, effects = inner.step(state, event, now)
			after = table.clone(stepped)
			innerEffects = effects
		end

		-- The inner's RoundView carries SLICE-003's trigger; it is rebuilt here.
		local innerWanted = false
		local kept: { any } = {}
		for _, e in innerEffects do
			if typeof(e) == "table" and e.kind == "Broadcast" and e.payloadKind == "RoundView" then
				innerWanted = true
			else
				table.insert(kept, e)
			end
		end

		-- C-4: every Tick ticks the pings, before the views are built.
		if event.kind == "Tick" and not defects.pingsNeverExpire then
			channel =
				{ presets = channel.presets, pings = Pings.tick(channel.pings, now, state.tuning) }
		end
		-- C-4: a machine committed in this step clears its pings.
		if not defects.pingsSurviveCommit and after.procedure ~= nil and state.procedure ~= nil then
			for id, flag in after.procedure.committed do
				if flag == true and state.procedure.committed[id] ~= true then
					channel =
						{ presets = channel.presets, pings = Pings.onCommitted(channel.pings, id) }
				end
			end
		end

		local enteredLobby = after.round.phase == "Lobby" and state.round.phase ~= "Lobby"
		local enteredPost = after.round.phase == "Post" and state.round.phase ~= "Post"
		if
			(enteredLobby and not defects.channelKeptInLobby)
			or (enteredPost and defects.channelResetInPost)
		then
			channel = freshChannel()
		end

		-- C-7: the FacilityView on a successful deal.
		local dealt = after.round.phase == "Round"
			and state.round.phase ~= "Round"
			and after.facility ~= nil
		local facilityView: any = nil
		local onEveryTick = defects.facilityViewOnEveryTick
			and event.kind == "Tick"
			and after.facility ~= nil
		if (dealt and not defects.noFacilityView) or onEveryTick then
			facilityView = broadcast("FacilityView", RoundView.facility(after.facility))
		elseif
			defects.facilityViewOnFailedGeneration
			and state.assignment == nil
			and after.assignment ~= nil
			and after.facility == nil
		then
			facilityView =
				broadcast("FacilityView", { rooms = {}, doors = {}, spawnRoom = 0, machines = {} })
		end

		-- C-6: the private views, change-detected.
		local sent = {
			roundView = state.sent.roundView,
			lens = table.clone(state.sent.lens),
			cues = table.clone(state.sent.cues),
		}
		if (dealt or enteredLobby) and not defects.sentKeptAcrossRounds then
			sent.lens = {}
			sent.cues = {}
		end
		local views: { any } = {}
		if after.round.phase == "Round" and after.procedure ~= nil and after.assignment ~= nil then
			local lens: { [string]: any } = {}
			local cues: { [string]: any } = {}
			for _, p in after.assignment.players do
				local lv = lensOf(state, after, p)
				local cv = Projection.turnCuesFor(after.assignment, after.procedure, p)
				if defects.alwaysSendsLens or not Deep.equal(lv, sent.lens[p]) then
					if defects.broadcastsLensViews then
						table.insert(views, broadcast("LensView", lv))
					elseif defects.sendsLensToEveryone then
						for _, q in after.assignment.players do
							table.insert(views, sendTo(q, "LensView", lv))
						end
					else
						table.insert(views, sendTo(p, "LensView", lv))
					end
				end
				if not Deep.equal(cv, sent.cues[p]) then
					table.insert(views, sendTo(p, "TurnCues", cv))
				end
				lens[p] = lv
				cues[p] = cv
			end
			if defects.sendsWithdrawnPlayers then
				for p, old in sent.lens do
					if lens[p] == nil then
						table.insert(views, sendTo(p, "LensView", old))
						lens[p] = old
					end
				end
			end
			sent.lens = lens
			sent.cues = cues
		end

		-- C-4, C-6: the RoundView, from the END state, with the shown pings.
		local pings: { any } = {}
		if after.round.phase == "Round" or defects.pingsShownOutsideRound then
			pings = Pings.shown(channel.pings)
		end
		if defects.pingsNeverShown then
			pings = {}
		end
		local view = RoundView.public({
			round = after.round,
			procedure = after.procedure,
			assignment = after.assignment,
			positions = after.positions,
			pings = pings,
			tuning = after.tuning,
		}, now)
		local roundView: any = nil
		local changed = not sameRoundView(view, sent.roundView)
		if innerWanted or (changed and not defects.roundViewOnlyOnOldTriggers) then
			sent.roundView = view
			roundView = broadcast("RoundView", view)
		end

		-- C-9: assemble in the Contract's order.
		local out: { any } = {}
		local lastSeat = 0
		for i, e in kept do
			if typeof(e) == "table" and e.kind == "SendTo" and e.payloadKind == "SeatView" then
				lastSeat = i
			end
		end
		local placeFacilityAt = if lastSeat > 0 then lastSeat else #kept
		for i, e in kept do
			table.insert(out, e)
			if
				i == placeFacilityAt
				and facilityView ~= nil
				and not defects.facilityViewAfterRoundView
			then
				table.insert(out, facilityView)
			end
		end
		if #kept == 0 and facilityView ~= nil and not defects.facilityViewAfterRoundView then
			table.insert(out, facilityView)
		end
		if reply ~= nil then
			table.insert(out, reply)
		end
		if shown ~= nil then
			table.insert(out, shown)
		end
		for _, v in views do
			table.insert(out, v)
		end
		if roundView ~= nil then
			table.insert(out, roundView)
		end
		if facilityView ~= nil and defects.facilityViewAfterRoundView then
			table.insert(out, facilityView)
		end

		after.channel = channel
		after.sent = sent
		after.ports = state.ports
		return after, out
	end

	return S
end

SessionChannelStubs.reference = SessionChannelStubs.standIn({})

return SessionChannelStubs
