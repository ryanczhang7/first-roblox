--!strict
--[[
	TEL-001: the telemetry envelope every emitter agrees on.

	Brief B6 wants telemetry in M2 rather than later, and A5 wants the three
	discovery buckets - D1, days 2-7, days 8-28 - instrumented SEPARATELY from
	day one, because Roblox's Recommended For You measures them separately and
	first-play bounce is a direct ranking penalty. This module emits nothing.
	It fixes the vocabulary: the nine names, the bucket each belongs to, and
	the shape of the record that carries one.

	THE CLOCK IS NOT READ HERE. `at` is a parameter, supplied by the caller
	from an injected `Clock` (`architecture.md` §2, and `Clock.luau`'s own
	header). A module that read a time source for itself would make every
	event's timestamp untestable and would put a second real-time reader in
	`src/`; `tests/shared/source_guard_test.luau` scans every source module the
	harness classifies and would find it.

	AN UNKNOWN NAME IS REFUSED, NOT DEFAULTED (AC-3). The tempting alternative
	is `BUCKETS[name] or "D1"`, and it is exactly the defect the criterion
	names: a typo at one of nine future call sites would then file real events
	under a bucket nobody chose, and the metric would go on reporting a number
	- the wrong one - with nothing anywhere to notice. A raise at construction
	is a stack trace on the first run instead.

	`fields` IS A FLAT MAP OF SCALARS (AC-6). A nested table is a payload
	nobody downstream can index, and an Instance under a `playerId` key is a
	memory leak and a replication hazard. The refusal names the offending key,
	because a call site with five fields needs to know which one.

	THREE OF THE NINE NAMES HAVE NO EMITTER and will not until M5:
	`day_n_return`, `co_play_with_known_player` and `purchase` all need
	persistence. They are in the mapping anyway so that M5 adds an emitter
	rather than a vocabulary, and so that the gap is visible in the table
	rather than discovered later. Nothing asserts that a name has an emitter.
]]

local Event = {}

export type Bucket = "D1" | "D2_7" | "D8_28"

-- The only value types an event may carry. Anything else is refused by `new`.
export type FieldValue = string | number | boolean

export type Fields = { [string]: FieldValue }

export type TelemetryEvent = {
	name: string,
	at: number, -- seconds, from the injected Clock; never read here
	bucket: Bucket,
	sessionId: string,
	playerId: string?, -- a Roblox user id as a string, and nothing else
	fields: Fields,
}

--[[
	AC-2, SETTLED. Brief B6's nine events with A5's three buckets, exactly as
	`docs/wiki/architecture.md` §6 tabulates them. This table is a
	transcription, not a design: adding an event here invents a metric, and
	dropping one silently stops collecting it.

	FROZEN, with `table.freeze` rather than a `__newindex` metatable. The
	difference matters: a metatable's `__newindex` fires only for keys that are
	absent, so `BUCKETS.join = "D8_28"` - re-filing an existing event under the
	wrong bucket, which is the more damaging of the two mistakes - would write
	straight through it.

	THE `:: Bucket` CASTS ARE LOAD-BEARING and not noise: a bare `join = "D1"`
	in a table literal widens to `string`, and the whole table then fails to be
	a `{ [string]: Bucket }`. Measured with luau-lsp; strip them and the
	`typecheck` gate says so.
]]
local BUCKETS: { [string]: Bucket } = table.freeze({
	join = "D1" :: Bucket,
	first_round_complete = "D1" :: Bucket,
	bounce_before_resolution = "D1" :: Bucket,
	session_end = "D1" :: Bucket,
	round_complete = "D2_7" :: Bucket,
	rematch_accepted = "D2_7" :: Bucket,
	day_n_return = "D8_28" :: Bucket,
	co_play_with_known_player = "D8_28" :: Bucket,
	purchase = "D8_28" :: Bucket,
})

Event.BUCKETS = BUCKETS

--[[
	A flat copy of the supplied fields, validated on the way through.

	The copy is deliberate: the caller's table is theirs to go on mutating, and
	an envelope that aliased it would let a record change after the sink held
	it. The validation happens in the same pass, so a refused table is never
	half-copied into an event that is then thrown away.
]]
local function validatedFields(name: string, fields: Fields?): Fields
	local copy: { [string]: FieldValue } = {}
	if fields == nil then
		return copy
	end

	for key, value in pairs(fields :: { [string]: any }) do
		local kind = typeof(value)
		if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then
			error(
				`Event.new("{name}"): fields.{tostring(key)} is a {kind}; `
					.. `an event's fields are a flat map of string, number or boolean values`,
				3
			)
		end
		copy[key] = value
	end

	return copy
end

--[[
	Build one event.

	`at` is the caller's number, carried unchanged - it is not rounded, not
	clamped and not compared to anything. `bucket` is looked up, never guessed.
	The error messages quote the offending name and the offending key verbatim,
	because the thing a caller needs from a refusal is which of its arguments
	was wrong.
]]
function Event.new(
	name: string,
	at: number,
	sessionId: string,
	playerId: string?,
	fields: Fields?
): TelemetryEvent
	local bucket: Bucket? = BUCKETS[name]
	if bucket == nil then
		error(
			`Event.new: "{name}" is not a B6 event name, so it has no bucket; `
				.. `add it to Event.BUCKETS with the bucket A5 files it under, or fix the name`,
			2
		)
	end

	return {
		name = name,
		at = at,
		bucket = bucket,
		sessionId = sessionId,
		playerId = playerId,
		fields = validatedFields(name, fields),
	}
end

return Event
