--!strict
--[[
	The wrong rate-limiting bundles NET-003's controls are aimed at, and the
	one baseline each of them is a single defect away from.

	FOUR CRITERIA NAME THEIR CONTROL IN THE CRITERION OR THE CONTRACT. AC-2:
	"an implementation with one shared last-call timestamp passes AC-1 and
	must fail this" - `sharedTimestamp`. AC-3: "an implementation that updates
	the timestamp on rejection must fail this" - `recordsOnReject`. AC-1's
	boundary: `>` instead of `>=` - `strictlyGreater`. AC-6's pinned shape:
	`size()` counting `(player, key)` pairs - `sizeCountsKeys`, and a `forget`
	that is a no-op - `neverForgets`. The rest are the mutations `## Notes`
	asks the orchestrator to run at acceptance and the one-defect bundles the
	remaining checks would otherwise have no control for.

	IT IS A LAYER OVER `PhaseStubs.correct()`, which is itself a layer over
	`NetStubs.correct()` - not a third copy. The baseline here takes NET-002's
	correct phase-enforcing bundle and wraps ONE export, `Wrapper.guard`,
	which gains the rate check at position 5 - after identity, shape, range
	and phase, which the inner guard performs, and before the handler, which
	the outer guard withholds until the limiter allows - and ADDS one export,
	`RateLimiter`, the stub limiter the outer guard constructs. That is what
	lets one field of `defects` be the whole difference between the baseline
	and a control, and what keeps NET-001's 12 and NET-002's 8 checks
	satisfiable by every bundle here that is not built to break one.

	WHAT THIS IS NOT: `src/net/` or a sketch of it. GREEN writes the real
	limiter into `RateLimiter.luau` and the real check into `Wrapper.luau`
	from the story's `## Contract`. Nothing here is to be copied.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE, so these controls are
	EXECUTED in RED, and `tests/net/rate_controls_test.luau` records what each
	one actually did.
]]

local PhaseStubs = require("./PhaseStubs")

local RateStubs = {}

--[[
	One field per control, each a single edit to the baseline below.

	  Wrapper
	  * `ignoresRateLimit`        - no rate check at all: the pre-NET-003
	                                wrapper, and what the real suite fails on
	                                arrival
	  * `sharedTimestamp`         - the guard passes ONE player id to the
	                                limiter for everybody, so all callers
	                                share a last-accepted timestamp (AC-2's
	                                control; mutation 2 of `## Notes`)
	  * `limitsWithoutRateLimit`  - a remote that declared no rateLimit is
	                                limited anyway, at 1.5 (AC-4's control)
	  * `rateBeforePhase`         - check 5 runs ahead of check 4: the clock
	                                is read and the limiter consulted at the
	                                moment the phase is read, and a rate
	                                rejection wins over a phase one (AC-5's
	                                control)
	  * `rejectsEverything`       - every call that reaches check 5 is
	                                rejected for rate, rateLimit or not (the
	                                positive control: fails AC-1's first call
	                                and AC-4)
	  * `capturesClockAtGuard`    - reads context.clock.now() once, when
	                                guard() is called, and compares that
	  * `prefixedDetail`          - detail leads with "rate: "
	  * `detailOmitsInterval`     - detail names the remote only
	  * `detailOmitsName`         - detail names the interval only
	  RateLimiter
	  * `recordsOnReject`         - allow records the timestamp whether or
	                                not it permits (AC-3's control; mutation 1)
	  * `strictlyGreater`         - `>` instead of `>=` (AC-1's boundary;
	                                mutation 3)
	  * `neverForgets`            - forget is a no-op (AC-6)
	  * `sizeCountsKeys`          - size counts (player, key) pairs (AC-6's
	                                pinned shape)
]]
export type Defects = {
	ignoresRateLimit: boolean?,
	sharedTimestamp: boolean?,
	limitsWithoutRateLimit: boolean?,
	rateBeforePhase: boolean?,
	rejectsEverything: boolean?,
	capturesClockAtGuard: boolean?,
	prefixedDetail: boolean?,
	detailOmitsInterval: boolean?,
	detailOmitsName: boolean?,
	recordsOnReject: boolean?,
	strictlyGreater: boolean?,
	neverForgets: boolean?,
	sizeCountsKeys: boolean?,
}

export type Net = { Schema: any, Remotes: any, Wrapper: any, RateLimiter: any }

-- The interval the `limitsWithoutRateLimit` wrapper applies to a remote that
-- declared none: the one every declaring remote in the suite uses.
local DEFAULT_INTERVAL = 1.5

function RateStubs.build(defects: Defects): Net
	local base = PhaseStubs.correct()

	--[[ RateLimiter ]]

	local RateLimiter = {}

	function RateLimiter.new(minIntervalSeconds: number): any
		-- One entry per player, a timestamp per key.
		local entries: { [any]: { [string]: number } } = {}
		local limiter = {}

		function limiter.allow(_self: any, playerId: any, key: string, now: number): boolean
			local byKey = entries[playerId]
			if byKey == nil then
				byKey = {}
				entries[playerId] = byKey
			end
			local last = (byKey :: { [string]: number })[key]
			local ok: boolean
			if last == nil then
				ok = true
			elseif defects.strictlyGreater then
				ok = now - last > minIntervalSeconds
			else
				ok = now - last >= minIntervalSeconds
			end
			if ok or defects.recordsOnReject then
				(byKey :: { [string]: number })[key] = now
			end
			return ok
		end

		function limiter.forget(_self: any, playerId: any)
			if not defects.neverForgets then
				entries[playerId] = nil
			end
		end

		function limiter.size(_self: any): number
			local n = 0
			for _, byKey in entries do
				if defects.sizeCountsKeys then
					for _ in byKey do
						n += 1
					end
				else
					n += 1
				end
			end
			return n
		end

		return limiter
	end

	--[[ Wrapper ]]

	local Wrapper = {}

	function Wrapper.guard(definition: any, context: any, handler: any): any
		local declared = definition.rateLimit ~= nil
		local interval: number = if declared
			then definition.rateLimit.minIntervalSeconds
			else DEFAULT_INTERVAL
		local limiter: any = nil
		if declared or defects.limitsWithoutRateLimit then
			limiter = RateLimiter.new(interval)
		end

		local captured: number? = nil
		if defects.capturesClockAtGuard and limiter ~= nil then
			captured = context.clock.now()
		end

		local function describe(): string
			local detail: string
			if defects.detailOmitsInterval then
				detail = `"{definition.name}" is rate-limited`
			elseif defects.detailOmitsName then
				detail = `limited to one call per {interval} s`
			else
				detail = `"{definition.name}" is limited to one call per {interval} s`
			end
			if defects.prefixedDetail then
				detail = `rate: {detail}`
			end
			return detail
		end

		-- The rate check itself: nil when allowed, a Rejection otherwise.
		local function rateCheck(playerId: any): any
			if defects.ignoresRateLimit then
				return nil
			end
			local ok = true
			if limiter ~= nil then
				local now = if captured ~= nil then captured :: number else context.clock.now()
				local id = if defects.sharedTimestamp then "everyone" else playerId
				ok = limiter:allow(id, definition.name, now)
			end
			if defects.rejectsEverything then
				ok = false
			end
			if ok then
				return nil
			end
			return { reason = "rate", detail = describe() }
		end

		-- `pending` carries a rate rejection out of the inner pipeline, which
		-- has no return path for one: the inner guard's handler is where the
		-- check runs in the baseline, and its `phase()` read is where it runs
		-- under `rateBeforePhase`.
		local pending: any = nil
		local currentPlayer: any = nil
		local checkedEarly = false

		local innerContext = context
		if defects.rateBeforePhase then
			innerContext = {
				isSeated = function(playerId: any): boolean
					return context.isSeated(playerId)
				end,
				phase = function(): any
					-- Identity, shape and range have passed (the inner guard
					-- reads the phase only then); the misplaced check runs
					-- now, ahead of the comparison the read is for, and it
					-- is the ONLY time this call consults the limiter.
					checkedEarly = true
					pending = rateCheck(currentPlayer)
					return context.phase()
				end,
				clock = context.clock,
			}
		end

		local inner = base.Wrapper.guard(
			definition,
			innerContext,
			function(playerId: any, args: any)
				if not checkedEarly then
					pending = rateCheck(playerId)
				end
				if pending ~= nil then
					return
				end
				handler(playerId, args)
			end
		)

		return function(playerId: any, rawArgs: any): any
			pending = nil
			checkedEarly = false
			currentPlayer = playerId
			local result = inner(playerId, rawArgs)
			if pending ~= nil then
				return pending
			end
			return result
		end
	end

	return {
		Schema = base.Schema,
		Remotes = base.Remotes,
		Wrapper = Wrapper,
		RateLimiter = RateLimiter,
	}
end

-- The baseline, and every control, as ready-made bundles. Each is built fresh
-- on access so that a check's declarations never collide across controls.
function RateStubs.correct(): Net
	return RateStubs.build({})
end

function RateStubs.with(defect: string): Net
	local defects: { [string]: boolean } = {}
	defects[defect] = true
	return RateStubs.build(defects :: any)
end

RateStubs.DEFECTS = {
	"ignoresRateLimit",
	"sharedTimestamp",
	"limitsWithoutRateLimit",
	"rateBeforePhase",
	"rejectsEverything",
	"capturesClockAtGuard",
	"prefixedDetail",
	"detailOmitsInterval",
	"detailOmitsName",
	"recordsOnReject",
	"strictlyGreater",
	"neverForgets",
	"sizeCountsKeys",
}

return RateStubs
