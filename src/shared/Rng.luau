--!strict
--[[
	The injected random source, per ROUND-001 and `docs/wiki/architecture.md`
	section 2. This is the only module in `src/` permitted to touch a real random
	source, and in practice it touches none: the generator is arithmetic, so a
	seed fully determines a stream on every machine and in every runtime.

	WHAT IS PROMISED: reproducibility (same seed, same stream), independence of
	derived sub-streams, and a `shuffle` that never mutates its caller's list.
	WHAT IS NOT: unpredictability. This is a game seed, not a security primitive.

	The generator is a 32-bit xorshift. It was chosen for one property the story
	needs and nothing else: its state transition is a bijection over a single
	cycle, so two distinct seeds never converge and a derived sub-stream is a
	different sequence rather than a shifted copy of a shared one.

	`derive(label)` mixes the label into a FRESH stream identity and leaves the
	parent's state alone. That is what makes adding a consumer of randomness an
	additive change: inserting a draw in one sub-stream shifts nothing in any
	other, so a recorded round seed keeps reproducing its instance.
]]

local Rng = {}

export type Rng = {
	nextInteger: (self: Rng, min: number, max: number) -> number,
	nextNumber: (self: Rng) -> number,
	shuffle: <T>(self: Rng, list: { T }) -> { T },
	derive: (self: Rng, label: string) -> Rng,
}

local TWO_POW_32 = 4294967296

-- One xorshift32 step. Bijective on the 2^32 - 1 non-zero states, so a stream
-- never reaches zero and never repeats before 2^32 - 1 draws.
local function step(state: number): number
	local x = state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	return x
end

--[[
	An arbitrary number to a non-zero 32-bit state.

	The `%` before any `bit32` call is deliberate: a seed is just a number and
	may be far outside 32 bits, and reducing it with ordinary arithmetic is exact
	for everything a double holds. Distinct seeds stay distinct through the xor
	and the two stirring steps, which is why two seeds cannot share a stream.
]]
local function stateFor(identity: number): number
	local reduced = math.floor(math.abs(identity)) % TWO_POW_32
	local x = bit32.bxor(reduced, 0x9E3779B9)
	if x == 0 then
		x = 0x6C078965
	end
	return step(step(x))
end

--[[
	A stream identity from a parent identity and a label.

	Both halves matter and the Contract names both: ignore the parent and every
	seed shares its sub-streams; ignore the label and `derive("seats")` and
	`derive("instance")` hand two consumers the same numbers.
]]
local function identityFor(parentIdentity: number, label: string): number
	local h = stateFor(parentIdentity)
	h = step(bit32.bxor(h, #label))
	for i = 1, #label do
		h = step(bit32.bxor(h, string.byte(label, i) :: number))
	end
	return h
end

local function newStream(identity: number): Rng
	local state = stateFor(identity)

	local stream: Rng = {
		-- Uniform in [0, 1). Strictly below 1 because `state` is at most
		-- 2^32 - 1, which is what makes the inclusive `nextInteger` below exact
		-- at its top end.
		nextNumber = function(_self: Rng): number
			state = step(state)
			return state / TWO_POW_32
		end,

		-- Inclusive at BOTH ends. `min > max` is an error rather than an empty
		-- range: an empty draw has no sensible value and returning nil would
		-- move the failure somewhere else.
		nextInteger = function(self: Rng, min: number, max: number): number
			if min > max then
				error(`Rng.nextInteger: min {min} is greater than max {max}`, 2)
			end
			local span = max - min + 1
			return math.min(min + math.floor(self:nextNumber() * span), max)
		end,

		-- Returns a NEW list, always - including for an empty one. A shuffle
		-- that permutes in place turns a pure function into one that corrupts
		-- its caller's state.
		shuffle = function<T>(self: Rng, list: { T }): { T }
			local out = table.clone(list)
			for i = #out, 2, -1 do
				local j = self:nextInteger(1, i)
				out[i], out[j] = out[j], out[i]
			end
			return out
		end,

		-- A sub-stream, deterministic in (parent identity, label) and touching
		-- no state the parent or any sibling can see.
		derive = function(_self: Rng, label: string): Rng
			return newStream(identityFor(identity, label))
		end,
	}

	return stream
end

function Rng.fromSeed(seed: number): Rng
	return newStream(seed)
end

return Rng
