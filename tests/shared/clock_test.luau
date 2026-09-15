--!strict
--[[
	ROUND-001 AC-1 and the `src/shared/Clock.luau` Contract.

	The module is required through a `pcall` at the top and re-checked inside each
	test. That is not defensive dressing: in RED `src/shared/Clock.luau` does not
	exist, and a bare top-level `require` would make the whole file a single LOAD
	FAIL - one line of red covering four criteria. Per-criterion failures say
	which behaviours are missing, which is what the next phase needs.

	It is not a skip either. Every test below still FAILS, loudly, naming the
	module that did not load.
]]

local ClockContract = require("../helpers/ClockContract")

local loaded, loadResult = pcall(require, "../../src/shared/Clock")

local function Clock(): any
	assert(loaded, `src/shared/Clock.luau did not load: {tostring(loadResult)}`)
	return loadResult
end

local function manual(startSeconds: number): any
	return Clock().manual(startSeconds)
end

return {
	["AC-1: a manual clock advances by exactly the deltas it is given"] = function()
		ClockContract.advanceMovesNowByTheDelta(manual)
	end,

	["AC-1: advancing a manual clock by zero changes nothing"] = function()
		ClockContract.zeroAdvanceChangesNothing(manual)
	end,

	["Contract: a manual clock refuses a negative advance"] = function()
		ClockContract.negativeAdvanceIsAnError(manual)
	end,

	["Contract: set moves a manual clock backwards"] = function()
		ClockContract.setMayMoveBackwards(manual)
	end,

	["Contract: Clock.manual and Clock.real are both exported functions"] = function()
		local module = Clock()
		assert(
			typeof(module.manual) == "function",
			`Clock.manual is {typeof(module.manual)}, wanted a function`
		)
		assert(
			typeof(module.real) == "function",
			`Clock.real is {typeof(module.real)}, wanted a function`
		)
	end,

	--[[
		`Clock.real()` is the one function in src/ allowed to read a real time
		source, and the story's `## Out of scope` says nothing may USE it until a
		driver exists. This asserts it is a Clock and that its `now` behaves like
		one - two reads, both numbers, never going backwards. It is the adapter's
		only test and it stops `Clock.real` shipping as an untested export.
	]]
	["Contract: Clock.real returns a clock whose now is a number that never goes backwards"] = function()
		local real = Clock().real()
		assert(typeof(real) == "table", `Clock.real() returned {typeof(real)}, wanted a table`)
		assert(typeof(real.now) == "function", `Clock.real().now is {typeof(real.now)}`)

		local first = real.now()
		local second = real.now()
		assert(typeof(first) == "number", `Clock.real().now() returned {typeof(first)}`)
		assert(typeof(second) == "number", `Clock.real().now() returned {typeof(second)}`)
		assert(second >= first, `Clock.real() went backwards: {first} then {second}`)
	end,

	--[[
		A manual clock is a `Clock`, so anything that takes a `Clock` takes it.
		The Contract types `now` as a plain field function - `clock.now()`, not
		`clock:now()` - and this pins that call shape, because a story that
		injects a clock somewhere else will write it one way and only one.
	]]
	["Contract: a manual clock satisfies the plain Clock interface"] = function()
		local clock = manual(0)
		assert(typeof(clock.now) == "function", `ManualClock.now is {typeof(clock.now)}`)
		assert(
			typeof(clock.advance) == "function",
			`ManualClock.advance is {typeof(clock.advance)}`
		)
		assert(typeof(clock.set) == "function", `ManualClock.set is {typeof(clock.set)}`)
		assert(clock.now() == 0, `a clock made at 0 reported {clock.now()} when called as now()`)
	end,
}
