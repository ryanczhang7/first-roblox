--!strict
--[[
	ROUND-001's AC-1 written once, as checks over a FACTORY rather than over a
	module - same arrangement as `RngContract.luau`, and for the same reason.

	`tests/shared/clock_test.luau` applies these to `Clock.manual`.
	`tests/shared/clock_controls_test.luau` applies them to the wrong clocks in
	`Fakes.luau`, so that in RED - where `src/shared/Clock.luau` does not exist
	and the real file cannot even load - the assertions themselves have still been
	executed and observed to reject a clock that does not advance.

	A factory is `(startSeconds: number) -> ManualClock`.
]]

local ClockContract = {}

export type Factory = (number) -> any

--[[
	AC-1 verbatim: created at t = 100, advanced by 5 and then by 2.5, `now()`
	returns 100, 105 and 107.5 in turn, and the same value on repeated calls
	between advances.

	`now` is a plain function and `advance` is a method, per the Contract. The
	repeated call is not padding: a `now` that returns a counter passes the three
	values above while being no kind of clock at all.
]]
function ClockContract.advanceMovesNowByTheDelta(factory: Factory)
	local clock = factory(100)

	assert(clock.now() == 100, `AC-1: a clock made at 100 reported {clock.now()}`)
	assert(clock.now() == 100, `AC-1: now() changed without an advance: {clock.now()}`)

	clock:advance(5)
	assert(
		clock.now() == 105,
		`AC-1: after advance(5) from 100, now() is {clock.now()}, wanted 105`
	)
	assert(clock.now() == 105, `AC-1: now() drifted between advances: {clock.now()}`)

	clock:advance(2.5)
	assert(
		clock.now() == 107.5,
		`AC-1: after advance(2.5) from 105, now() is {clock.now()}, wanted 107.5`
	)
	assert(clock.now() == 107.5, `AC-1: now() drifted after the final advance: {clock.now()}`)
end

-- The zero edge. An advance of nothing is not an error and moves nothing.
function ClockContract.zeroAdvanceChangesNothing(factory: Factory)
	local clock = factory(3.25)
	clock:advance(0)
	assert(clock.now() == 3.25, `AC-1: advance(0) moved the clock to {clock.now()}`)
end

--[[
	The Contract: `advance(d)` requires `d >= 0`, and a negative delta is an
	error. Silently clamping it hides a defect in the phase machine, which is the
	reason the Contract says "error" rather than "clamp".
]]
function ClockContract.negativeAdvanceIsAnError(factory: Factory)
	local clock = factory(10)
	local ok = pcall(function()
		clock:advance(-1)
	end)
	assert(ok == false, `Contract: advance(-1) was accepted; now() is {clock.now()}`)
	assert(
		clock.now() == 10,
		`Contract: a refused advance(-1) still moved the clock to {clock.now()}`
	)
end

-- The Contract: `set` is for test setup and may move backwards.
function ClockContract.setMayMoveBackwards(factory: Factory)
	local clock = factory(100)
	clock:advance(10)
	clock:set(4)
	assert(clock.now() == 4, `Contract: set(4) left now() at {clock.now()}`)
	clock:advance(1)
	assert(clock.now() == 5, `Contract: advance(1) after set(4) gave {clock.now()}, wanted 5`)
end

return ClockContract
