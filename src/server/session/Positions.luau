--!strict
--[[
	VIEW-004: an implausible position is not trusted for any range check
	(`architecture.md` §9.8, B4). On Roblox a character's position is
	simulated by its own client, so a sample is a CLAIM. The server accepts a
	sample only if it could have been walked to from the last ACCEPTED one at
	the server-set walk speed, with a tolerance; every range rule reads the
	accepted positions only.

	THE BOUND. `d` is the horizontal (x, z) distance from the last accepted
	position to the candidate - `y` is ignored, as every M3 range is
	horizontal. `dt = max(0, now - acceptedAt)`. The candidate is accepted iff
	`d <= walkSpeed * TOLERANCE * dt + SLACK_STUDS` (inclusive). The bound is
	measured from the last accepted sample, not the last offered one, so after
	refusals it keeps growing and a player who really walked is accepted once
	the walk is plausible from the last trusted point.

	NO BASELINE IS NOT A REFUSAL. With no accepted position there is nothing
	to be implausible against and nothing to resync to: the candidate is not
	stored, not counted, and does not open a run (AC-3). A baseline comes only
	from `placed` - a server placement.

	THE THREE CONSTANTS ARE ENGINEERING CONSTANTS, NOT GAME TUNING. They bound
	a trust check and do not change how the game plays for an honest client,
	so they live here with this justification and are not in `tuning.md`.
	`TOLERANCE` absorbs physics jitter and network batching; `SLACK_STUDS` is
	one sample's worth of rounding; `RESYNC_SECONDS` is how long an unbroken
	run of refusals lasts before `Session` pulls the player back to their last
	accepted position. If playtesting shows honest players refused (a jumping
	or falling character exceeding the bound), raise `TOLERANCE` here and
	record the observation. Walk speed is passed in from the session's own
	tuning; this module never reads `MechanicsTuning`.

	PURE: no module state, no argument mutated, every returned table fresh,
	and a returned `accepted` is never the table handed in.
]]

local Positions = {}

export type Vec = { x: number, y: number, z: number }

export type Track = {
	accepted: Vec?, -- the last accepted sample (or placement); nil = never accepted
	acceptedAt: number?, -- when it was accepted
	refusedSince: number?, -- start of the current unbroken run of refusals; nil when none
	refusals: number, -- every refusal ever counted for this player (AC-1)
}

Positions.TOLERANCE = 1.5
Positions.SLACK_STUDS = 2
Positions.RESYNC_SECONDS = 3

local function copy(v: Vec): Vec
	return { x = v.x, y = v.y, z = v.z }
end

local function refusalsOf(track: Track?): number
	return if track ~= nil then track.refusals else 0
end

function Positions.placed(track: Track?, at: Vec, now: number): Track
	return { accepted = copy(at), acceptedAt = now, refusals = refusalsOf(track) }
end

function Positions.offer(
	track: Track?,
	candidate: Vec,
	now: number,
	walkSpeed: number
): (Track, boolean)
	if track == nil or track.accepted == nil then
		return { refusals = refusalsOf(track) }, false
	end
	local accepted = track.accepted :: Vec
	local acceptedAt = track.acceptedAt or now
	local dx = candidate.x - accepted.x
	local dz = candidate.z - accepted.z
	local d = math.sqrt(dx * dx + dz * dz)
	local dt = math.max(0, now - acceptedAt)
	local bound = walkSpeed * Positions.TOLERANCE * dt + Positions.SLACK_STUDS
	if d <= bound then
		return { accepted = copy(candidate), acceptedAt = now, refusals = track.refusals }, true
	end
	return {
		accepted = copy(accepted),
		acceptedAt = track.acceptedAt,
		refusedSince = track.refusedSince or now,
		refusals = track.refusals + 1,
	},
		false
end

function Positions.needsResync(track: Track?, now: number): boolean
	return track ~= nil
		and track.accepted ~= nil
		and track.refusedSince ~= nil
		and now - track.refusedSince > Positions.RESYNC_SECONDS
end

return Positions
