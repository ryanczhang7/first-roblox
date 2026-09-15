--!strict
--[[
	The wrong implementations ROUND-001's negative controls are aimed at.

	AC-2 and AC-3 each name one: an `Rng` that ignores its seed, and a `derive`
	that returns its parent. Both pass the obvious half of their criterion, and
	the story says so out loud - so the suite has to demonstrate that the other
	half rejects them. A control that is described and never run proves nothing,
	and in RED that is the normal state of affairs: the module under test does not
	exist, the file fails at `require`, and no assertion in it has executed.

	These fakes exist so that the AC-2, AC-3 and AC-4 checks in
	`tests/helpers/RngContract.luau` ARE executed in RED, against implementations
	whose defects are known, before any production code exists.

	`Fakes.correct` is the baseline and it is the part that makes the controls
	mean something. Each wrong implementation below is `correct` with ONE thing
	broken, and the control asserts that exactly the matching check goes red while
	the others stay green. Without the baseline, "the control failed" could as
	easily mean the fake is broken in six ways.

	IT IS NOT A SPECIFICATION OF THE ALGORITHM. Nothing in this story pins a
	particular number stream - no golden values, no named generator - and the
	Feature Developer is free to implement `Rng` any way that satisfies the
	criteria. A Lehmer generator is used here only because a control needs SOME
	reproducible stream and this one is four lines.
]]

local Fakes = {}

-- MINSTD. 16807 * (2^31 - 2) is about 3.6e13, comfortably inside the 2^53 of a
-- double, so the modular arithmetic below is exact.
local MODULUS = 2147483647
local MULTIPLIER = 16807

local function normalise(identity: number): number
	local n = math.floor(math.abs(identity)) % (MODULUS - 1)
	return n + 1
end

local function hashLabel(identity: number, label: string): number
	local h = normalise(identity)
	for i = 1, #label do
		h = (h * 31 + string.byte(label, i)) % MODULUS
	end
	return h
end

local function newStream(identity: number): any
	local state = normalise(identity)
	local rng: any = {}

	function rng.nextNumber(_self: any): number
		state = (MULTIPLIER * state) % MODULUS
		return state / MODULUS
	end

	function rng.nextInteger(self: any, min: number, max: number): number
		assert(min <= max, `nextInteger: min {min} is greater than max {max}`)
		local span = max - min + 1
		return math.min(min + math.floor(self:nextNumber() * span), max)
	end

	function rng.shuffle(self: any, list: { any }): { any }
		local out = table.clone(list)
		for i = #out, 2, -1 do
			local j = self:nextInteger(1, i)
			out[i], out[j] = out[j], out[i]
		end
		return out
	end

	function rng.derive(_self: any, label: string): any
		return newStream(hashLabel(identity, label))
	end

	return rng
end

-- The baseline: seeded, independent sub-streams, non-mutating shuffle.
function Fakes.correct(seed: number): any
	return newStream(seed)
end

--[[
	AC-2's control. Every instance is the same stream whatever seed it is handed.

	It is reproducible - gloriously so - and that is the trap: a test that only
	asserts "two instances from the same seed agree" is satisfied by a constant.
]]
function Fakes.seedIgnoring(_seed: number): any
	return newStream(20260915)
end

--[[
	AC-3's control. Seeding works; `derive` hands back the parent.

	Two same-seeded parents still produce identical `derive("seats")` streams,
	because both parents are identical and untouched - so the same-label half of
	AC-3 passes. Only independence catches it: drawing from one sub-stream now
	advances every other.
]]
function Fakes.selfDeriving(seed: number): any
	local rng = newStream(seed)
	function rng.derive(self: any, _label: string): any
		return self
	end
	return rng
end

--[[
	AC-4's control, and the mutation the story's `## Notes` predicts third:
	`shuffle` permutes the caller's list in place and returns it.

	The result is still a permutation of the input, so the permutation half
	passes. Only "the input list is not mutated" catches it.
]]
function Fakes.mutatingShuffle(seed: number): any
	local rng = newStream(seed)
	function rng.shuffle(self: any, list: { any }): { any }
		for i = #list, 2, -1 do
			local j = self:nextInteger(1, i)
			list[i], list[j] = list[j], list[i]
		end
		return list
	end
	return rng
end

--[[
	AC-3's second control: `derive` is deterministic in the parent seed and
	ignores the label, so `derive("seats")` and `derive("instance")` are the same
	stream.

	Independence still holds - each call makes a fresh, untouched stream - and so
	does the same-label test. What breaks is that two consumers asking for
	different things get the same numbers, which is the whole reason the Contract
	says "deterministic in (parent seed, label)".
]]
function Fakes.labelIgnoringDerive(seed: number): any
	local rng = newStream(seed)
	function rng.derive(_self: any, _label: string): any
		return newStream(seed)
	end
	return rng
end

--[[
	A correct manual clock, and the baseline for the AC-1 controls.

	`now` is a plain function and `advance`/`set` are methods, exactly as the
	story's Contract writes them.
]]
function Fakes.manualClock(startSeconds: number): any
	local seconds = startSeconds
	local clock: any = {}
	function clock.now(): number
		return seconds
	end
	function clock.advance(_self: any, deltaSeconds: number)
		assert(deltaSeconds >= 0, `advance: negative delta {deltaSeconds}`)
		seconds += deltaSeconds
	end
	function clock.set(_self: any, value: number)
		seconds = value
	end
	return clock
end

-- AC-1's control: `advance` accepts the delta and ignores it. The story's
-- `## Notes` predicts this mutation second.
function Fakes.frozenClock(startSeconds: number): any
	local clock = Fakes.manualClock(startSeconds)
	function clock.advance(_self: any, _deltaSeconds: number) end
	return clock
end

-- The Contract's control: a negative delta is an error, not a clamp. "Silently
-- clamping it hides the defect" is the story's phrasing; this is the defect.
function Fakes.clampingClock(startSeconds: number): any
	local clock = Fakes.manualClock(startSeconds)
	local inner = clock.advance
	function clock.advance(self: any, deltaSeconds: number)
		inner(self, math.max(deltaSeconds, 0))
	end
	return clock
end

return Fakes
