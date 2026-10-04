--!strict
--[[
	The wrong plausibility checks VIEW-004's controls are aimed at, and the
	reference each of them is a single defect away from.

	A FACTORY OVER A TABLE OF DEFECTS, as `TurnCuesStubs.luau` is: `defects`
	is empty for the reference and has exactly ONE field set for every
	control, so a control that fires is attributable to that one thing. The
	deferred verifications name their shapes: D-1 (a tolerance a hundred times
	too wide), D-2 (an exclusive bound), D-5 (an inclusive resync). The rest
	are the one-defect modules the Contract's other sentences would otherwise
	have no control for: `y` counted, `dt` from the last OFFERED sample, a
	negative or absolute `dt`, a first sample trusted or counted, a placement
	that forgets or keeps the wrong thing, a refusal run that restarts on every
	refusal, and the two purity defects.

	THE CONSTANTS HERE ARE THE STUB'S OWN. The real tests read `TOLERANCE`,
	`SLACK_STUDS` and `RESYNC_SECONDS` from whatever module they are handed and
	never restate them; the reference carries the Contract's values so that
	its controls are measured against the same bound the real module will
	carry. GREEN writes `src/server/session/Positions.luau` from the Contract
	against the failing tests in `tests/server/positions_test.luau`; nothing
	here is to be copied.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE, so every number the
	controls file asserts is a measurement taken in RED, not a claim left for
	GREEN.
]]

local PositionsStubs = {}

export type Vec = { x: number, y: number, z: number }
export type Track = {
	accepted: Vec?,
	acceptedAt: number?,
	refusedSince: number?,
	refusals: number,
	-- Exactly the Contract's four fields; `dtFromLastOffer` keeps its own side table.
}

type Defects = {
	tolerance100: boolean?, -- D-1's shape: TOLERANCE x 100
	exclusiveBound: boolean?, -- D-2's shape: `<` rather than `<=`
	countsY: boolean?, -- a 3-D distance
	dtFromLastOffer: boolean?, -- dt measured from the last offered sample, accepted or not
	negativeDt: boolean?, -- no clamp: dt = now - acceptedAt, negative included
	absoluteDt: boolean?, -- dt = |now - acceptedAt|
	acceptsWithoutBaseline: boolean?, -- a first sample is trusted
	countsNoBaselineAsRefusal: boolean?, -- a first sample counts as a refusal and starts refusedSince
	placedKeepsRefusedSince: boolean?, -- a placement does not end the refusal run
	placedDropsRefusals: boolean?, -- a placement resets the refusal count
	refusedSinceRestartsEachRefusal: boolean?, -- refusedSince = now on every refusal
	acceptanceKeepsRefusedSince: boolean?, -- an accepted sample does not end the run
	resyncInclusive: boolean?, -- D-5's shape: `>=` rather than `>`
	resyncWithoutRefusals: boolean?, -- needsResync ignores refusedSince
	mutatesTrack: boolean?, -- writes into the track handed in
	aliasesCandidate: boolean?, -- stores the candidate table itself
}

local function copy(v: Vec): Vec
	return { x = v.x, y = v.y, z = v.z }
end

function PositionsStubs.make(defects: Defects): any
	local P: any = {}
	P.TOLERANCE = if defects.tolerance100 then 150 else 1.5
	P.SLACK_STUDS = 2
	P.RESYNC_SECONDS = 3
	-- When each track was last offered to, for `dtFromLastOffer`; a side
	-- table, so the Track itself carries exactly the Contract's fields.
	local offered: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any

	function P.placed(track: Track?, at: Vec, now: number): Track
		local next_: Track = if defects.mutatesTrack and track ~= nil
			then track
			else {
				accepted = nil,
				acceptedAt = nil,
				refusedSince = nil,
				refusals = 0,
			}
		next_.accepted = if defects.aliasesCandidate then at else copy(at)
		next_.acceptedAt = now
		offered[next_] = now
		next_.refusedSince = if defects.placedKeepsRefusedSince and track ~= nil
			then track.refusedSince
			else nil
		next_.refusals = if defects.placedDropsRefusals or track == nil then 0 else track.refusals
		return next_
	end

	function P.offer(
		track: Track?,
		candidate: Vec,
		now: number,
		walkSpeed: number
	): (Track, boolean)
		local base: Track = if track ~= nil
			then (if defects.mutatesTrack then track else table.clone(track))
			else {
				accepted = nil,
				acceptedAt = nil,
				refusedSince = nil,
				refusals = 0,
			}
		local accepted = base.accepted
		if accepted == nil or base.acceptedAt == nil then
			if defects.acceptsWithoutBaseline then
				base.accepted = if defects.aliasesCandidate then candidate else copy(candidate)
				base.acceptedAt = now
				offered[base] = now
				return base, true
			end
			if defects.countsNoBaselineAsRefusal then
				base.refusals += 1
				base.refusedSince = base.refusedSince or now
			end
			offered[base] = now
			return base, false
		end
		local since = if defects.dtFromLastOffer
				and track ~= nil
				and offered[track] ~= nil
			then offered[track]
			else base.acceptedAt :: number
		local dt = now - since
		if defects.absoluteDt then
			dt = math.abs(dt)
		elseif not defects.negativeDt then
			dt = math.max(0, dt)
		end
		local dx = candidate.x - accepted.x
		local dz = candidate.z - accepted.z
		local dy = if defects.countsY then candidate.y - accepted.y else 0
		local d = math.sqrt(dx * dx + dz * dz + dy * dy)
		local bound = walkSpeed * P.TOLERANCE * dt + P.SLACK_STUDS
		local ok = if defects.exclusiveBound then d < bound else d <= bound
		offered[base] = now
		if ok then
			base.accepted = if defects.aliasesCandidate then candidate else copy(candidate)
			base.acceptedAt = now
			if not defects.acceptanceKeepsRefusedSince then
				base.refusedSince = nil
			end
			return base, true
		end
		base.refusals += 1
		if defects.refusedSinceRestartsEachRefusal then
			base.refusedSince = now
		else
			base.refusedSince = base.refusedSince or now
		end
		return base, false
	end

	function P.needsResync(track: Track?, now: number): boolean
		if track == nil or track.accepted == nil then
			return false
		end
		if defects.resyncWithoutRefusals then
			return true
		end
		if track.refusedSince == nil then
			return false
		end
		local run = now - track.refusedSince
		return if defects.resyncInclusive then run >= P.RESYNC_SECONDS else run > P.RESYNC_SECONDS
	end

	return P
end

PositionsStubs.reference = PositionsStubs.make({})
PositionsStubs.tolerance100 = PositionsStubs.make({ tolerance100 = true })
PositionsStubs.exclusiveBound = PositionsStubs.make({ exclusiveBound = true })
PositionsStubs.countsY = PositionsStubs.make({ countsY = true })
PositionsStubs.dtFromLastOffer = PositionsStubs.make({ dtFromLastOffer = true })
PositionsStubs.negativeDt = PositionsStubs.make({ negativeDt = true })
PositionsStubs.absoluteDt = PositionsStubs.make({ absoluteDt = true })
PositionsStubs.acceptsWithoutBaseline = PositionsStubs.make({ acceptsWithoutBaseline = true })
PositionsStubs.countsNoBaselineAsRefusal = PositionsStubs.make({ countsNoBaselineAsRefusal = true })
PositionsStubs.placedKeepsRefusedSince = PositionsStubs.make({ placedKeepsRefusedSince = true })
PositionsStubs.placedDropsRefusals = PositionsStubs.make({ placedDropsRefusals = true })
PositionsStubs.refusedSinceRestartsEachRefusal =
	PositionsStubs.make({ refusedSinceRestartsEachRefusal = true })
PositionsStubs.acceptanceKeepsRefusedSince =
	PositionsStubs.make({ acceptanceKeepsRefusedSince = true })
PositionsStubs.resyncInclusive = PositionsStubs.make({ resyncInclusive = true })
PositionsStubs.resyncWithoutRefusals = PositionsStubs.make({ resyncWithoutRefusals = true })
PositionsStubs.mutatesTrack = PositionsStubs.make({ mutatesTrack = true })
PositionsStubs.aliasesCandidate = PositionsStubs.make({ aliasesCandidate = true })

-- A module that refuses every candidate: D-4's shape, for the scripted rounds.
PositionsStubs.refusesEverything = (function(): any
	local P: any = table.clone(PositionsStubs.reference)
	function P.offer(
		track: Track?,
		_candidate: Vec,
		now: number,
		_walkSpeed: number
	): (Track, boolean)
		local base: Track = if track ~= nil
			then table.clone(track)
			else {
				accepted = nil,
				acceptedAt = nil,
				refusedSince = nil,
				refusals = 0,
			}
		if base.accepted ~= nil then
			base.refusals += 1
			base.refusedSince = base.refusedSince or now
		end
		return base, false
	end
	return P
end)()

return PositionsStubs
