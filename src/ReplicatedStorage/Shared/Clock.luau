--!strict
--[[
	The injected clock, per ROUND-001 and `docs/wiki/architecture.md` section 2.

	`now()` returns SECONDS as a floating-point number: monotonic, with no defined
	epoch. It is a duration since an arbitrary start and never a wall-clock date.

	`Clock.manual(start)` is what tests and the phase machine's own tests inject:
	time moves only when something advances it. `Clock.real()` is the single
	adapter in `src/` permitted to read a real time source, and it has no logic -
	everything that needs the time takes a `Clock` instead of reaching for one.

	`advance(d)` requires `d >= 0`. A negative delta raises rather than clamping,
	because time going backwards in the phase machine is a defect and a silent
	clamp hides it. `set` exists for test setup only and may move backwards.
]]

local Clock = {}

export type Clock = { now: () -> number }

export type ManualClock = Clock & {
	advance: (self: ManualClock, deltaSeconds: number) -> (),
	set: (self: ManualClock, seconds: number) -> (),
}

--[[
	A clock that moves only when it is told to.

	`now` is a plain field function - `clock.now()`, no `self` - while `advance`
	and `set` are methods. That mix is the Contract's, and it is what lets a
	`ManualClock` be passed anywhere a bare `Clock` is wanted.
]]
function Clock.manual(startSeconds: number): ManualClock
	local seconds = startSeconds

	local manual: ManualClock = {
		now = function(): number
			return seconds
		end,

		advance = function(_self: ManualClock, deltaSeconds: number)
			if not (deltaSeconds >= 0) then
				error(`Clock.advance: delta must be >= 0, got {deltaSeconds}`, 2)
			end
			seconds += deltaSeconds
		end,

		set = function(_self: ManualClock, value: number)
			seconds = value
		end,
	}

	return manual
end

--[[
	The real time source, and the only place in `src/` that may read one.

	Nothing calls this yet: ROUND-001's `## Out of scope` says it is written and
	then left alone until a driver exists to inject it.
]]
function Clock.real(): Clock
	return {
		now = function(): number
			return os.clock()
		end,
	}
end

return Clock
