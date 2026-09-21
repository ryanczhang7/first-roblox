--!strict
--[[
	The wrong net modules NET-001's controls are aimed at, and the one baseline
	each of them is a single defect away from.

	TWO CRITERIA NAME THEIR CONTROL IN THE CRITERION. AC-5: "a wrapper that
	rejects everything passes AC-2, AC-3 and AC-4 and must fail this". AC-6:
	"an implementation returning a single boolean false must fail this". The
	rest are the mutations the story's `## Notes` asks the orchestrator to run
	at acceptance (a permissive shape, every reason collapsed to `shape`,
	identity moved after shape) and the one-defect modules the remaining
	checks would otherwise have no control for.

	It is a FACTORY over a table of defects, as `TelemetryStubs.luau` and
	`ProjectionStubs.luau` are, so that `defects` is empty for the baseline and
	has exactly ONE field set for every control: a control that fires is then
	attributable to that one field. Every call to `build` makes a fresh
	registry, so the same check can declare the same-labelled remote against
	every stub.

	WHAT THIS IS NOT, and it matters because the next agent to read it is the
	one who has to write the real thing: it is NOT `src/net/` and not a sketch
	of it. The baseline is the Contract only as far as the checks can see -
	every type is `any`, and its failure strings are whatever fell out. GREEN
	writes the modules from the story's `## Contract`, against the failing
	tests in `tests/net/*_test.luau`; nothing here is to be copied. One thing
	here IS a consequence GREEN must meet by some means: the baseline
	validates in two passes - every structural check over the whole payload,
	then every domain check - because AC-6 pins shape-before-range INSIDE one
	payload and a single-pass validator answers that in hash-iteration order.

	NOTHING HERE REQUIRES UNMERGED PRODUCTION CODE, so these controls are
	EXECUTED in RED, and `tests/net/net_controls_test.luau` records what each
	one actually did.
]]

local NetStubs = {}

--[[
	One field per control, each a single edit to the baseline below.

	  Wrapper
	  * `rejectEverything`     - a call that passes every check is rejected
	                             anyway, as `shape` (AC-5's control)
	  * `booleanFalse`         - every rejection is the value `false`
	                             (AC-6's control)
	  * `collapseToShape`      - every rejection's reason is `shape`
	                             (mutation 2 of `## Notes`)
	  * `identityAfterShape`   - the schema runs before the seat check
	                             (mutation 3 of `## Notes`)
	  * `skipsIdentity`        - the seat check never fires
	  * `runsHandlerTwice`     - an accepted call runs the handler twice
	  * `dropsArgs`            - the handler is called with nil arguments
	  * `runsHandlerOnReject`  - the handler runs before the verdict
	  * `raisesOnNonTable`     - the schema step indexes rawArgs unguarded
	  * `consultsSchemaFirst`  - identity still wins, but the schema is
	                             consulted before it is checked
	  Schema
	  * `permissiveShape`      - an unexpected key is ignored
	                             (mutation 1 of `## Notes`)
	  * `nonIntegerIsShape`    - 3.5 against integer() fails as `shape`
	  * `nanIsShape`           - NaN and the infinities fail as `shape`
	  * `rangeBeforeShape`     - the domain pass runs before the structural one
	  * `exclusiveMaximum`     - integer/number treat the maximum as exclusive
	  Remotes
	  * `silentRedeclare`      - a duplicate name replaces the first (AC-8)
	  * `leaksRegistry`        - `all()` returns the live registry
]]
export type Defects = {
	rejectEverything: boolean?,
	booleanFalse: boolean?,
	collapseToShape: boolean?,
	identityAfterShape: boolean?,
	skipsIdentity: boolean?,
	runsHandlerTwice: boolean?,
	dropsArgs: boolean?,
	runsHandlerOnReject: boolean?,
	raisesOnNonTable: boolean?,
	consultsSchemaFirst: boolean?,
	permissiveShape: boolean?,
	nonIntegerIsShape: boolean?,
	nanIsShape: boolean?,
	rangeBeforeShape: boolean?,
	exclusiveMaximum: boolean?,
	silentRedeclare: boolean?,
	leaksRegistry: boolean?,
}

export type Net = { Schema: any, Remotes: any, Wrapper: any }

-- A node is two passes. `structure(value)` answers "is this the right kind of
-- thing", `domain(value)` answers "is it inside the declared domain" and is
-- only meaningful after `structure` passed; both return a detail or nil.
type Node = {
	structure: (value: any) -> string?,
	domain: (value: any) -> string?,
}

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

function NetStubs.build(defects: Defects): Net
	--[[ Schema ]]

	local Schema = {}

	local function finish(node: Node): any
		return {
			validate = function(value: any): (boolean, string?)
				local first, second = node.structure, node.domain
				local firstKind, secondKind = "shape", "range"
				if defects.rangeBeforeShape then
					first, second = node.domain, node.structure
					firstKind, secondKind = "range", "shape"
				end
				local detail = first(value)
				if detail ~= nil then
					return false, `{firstKind}: {detail}`
				end
				detail = second(value)
				if detail ~= nil then
					return false, `{secondKind}: {detail}`
				end
				return true, nil
			end,
			_node = node,
		}
	end

	local function numeric(min: number, max: number, integer: boolean): any
		local aboveMax = function(n: number): boolean
			if defects.exclusiveMaximum then
				return n >= max
			end
			return n > max
		end
		return finish({
			structure = function(value: any): string?
				if typeof(value) ~= "number" then
					return `expected a number, got {typeof(value)}`
				end
				if defects.nanIsShape and not isFinite(value) then
					return `not a finite number: {value}`
				end
				if defects.nonIntegerIsShape and integer and math.floor(value) ~= value then
					return `expected an integer, got {value}`
				end
				return nil
			end,
			domain = function(value: any): string?
				if typeof(value) ~= "number" then
					return nil
				end
				local n = value :: number
				if not isFinite(n) then
					return `{n} is not a finite number`
				end
				if n < min then
					return `{n} is below the minimum {min}`
				end
				if aboveMax(n) then
					return `{n} is above the maximum {max}`
				end
				if integer and math.floor(n) ~= n then
					return `{n} is not an integer`
				end
				return nil
			end,
		})
	end

	function Schema.integer(min: number, max: number): any
		return numeric(min, max, true)
	end

	function Schema.number(min: number, max: number): any
		return numeric(min, max, false)
	end

	function Schema.boolean(): any
		return finish({
			structure = function(value: any): string?
				if typeof(value) ~= "boolean" then
					return `expected a boolean, got {typeof(value)}`
				end
				return nil
			end,
			domain = function(_value: any): string?
				return nil
			end,
		})
	end

	function Schema.literal(...: string): any
		local allowed: { [string]: boolean } = {}
		for _, option in { ... } do
			allowed[option] = true
		end
		return finish({
			structure = function(value: any): string?
				if typeof(value) ~= "string" or not allowed[value] then
					return `expected one of the declared literals, got {typeof(value)}`
				end
				return nil
			end,
			domain = function(_value: any): string?
				return nil
			end,
		})
	end

	function Schema.optional(inner: any): any
		local node = inner._node :: Node
		return finish({
			structure = function(value: any): string?
				if value == nil then
					return nil
				end
				return node.structure(value)
			end,
			domain = function(value: any): string?
				if value == nil then
					return nil
				end
				return node.domain(value)
			end,
		})
	end

	function Schema.shape(fields: { [string]: any }): any
		return finish({
			structure = function(value: any): string?
				if typeof(value) ~= "table" then
					return `expected a table, got {typeof(value)}`
				end
				local payload = value :: { [any]: any }
				if not defects.permissiveShape then
					for key in pairs(payload) do
						if typeof(key) ~= "string" or fields[key] == nil then
							return `unexpected key {tostring(key)}`
						end
					end
				end
				for key, field in pairs(fields) do
					local detail = (field._node :: Node).structure(payload[key])
					if detail ~= nil then
						return `{key}: {detail}`
					end
				end
				return nil
			end,
			domain = function(value: any): string?
				if typeof(value) ~= "table" then
					return nil
				end
				local payload = value :: { [any]: any }
				for key, field in pairs(fields) do
					local detail = (field._node :: Node).domain(payload[key])
					if detail ~= nil then
						return `{key}: {detail}`
					end
				end
				return nil
			end,
		})
	end

	--[[ Remotes ]]

	local Remotes = {}
	local registry: { any } = {}
	local byName: { [string]: any } = {}

	function Remotes.define(name: string, spec: any): any
		if byName[name] ~= nil and not defects.silentRedeclare then
			error(`Remotes.define: "{name}" is already declared`, 2)
		end
		local definition = {
			name = name,
			args = spec.args,
			legalPhases = spec.legalPhases,
			rateLimit = spec.rateLimit,
		}
		if byName[name] ~= nil then
			for i, entry in registry do
				if entry.name == name then
					registry[i] = definition
				end
			end
		else
			table.insert(registry, definition)
		end
		byName[name] = definition
		return definition
	end

	function Remotes.all(): { any }
		if defects.leaksRegistry then
			return registry
		end
		return table.clone(registry)
	end

	--[[ Wrapper ]]

	local Wrapper = {}

	function Wrapper.guard(definition: any, context: any, handler: any): any
		return function(playerId: any, rawArgs: any): any
			local function identity(): any
				if defects.skipsIdentity then
					return nil
				end
				if not context.isSeated(playerId) then
					return { reason = "identity", detail = `{tostring(playerId)} is not seated` }
				end
				return nil
			end

			local function schema(): any
				if defects.raisesOnNonTable then
					-- The unguarded index an exploiter is counting on.
					local _ = (rawArgs :: any).token
				end
				local ok, failure = definition.args.validate(rawArgs)
				if ok then
					return nil
				end
				local kind, detail = string.match(failure :: string, "^(%l+): (.*)$")
				return { reason = kind, detail = detail }
			end

			local function verdict(rejection: any): any
				if defects.runsHandlerOnReject then
					handler(playerId, rawArgs)
				end
				if defects.booleanFalse then
					return false
				end
				if defects.collapseToShape then
					rejection.reason = "shape"
				end
				return rejection
			end

			if defects.consultsSchemaFirst then
				local early = schema()
				local seat = identity()
				if seat ~= nil then
					return verdict(seat)
				end
				if early ~= nil then
					return verdict(early)
				end
			else
				local steps = if defects.identityAfterShape
					then { schema, identity }
					else { identity, schema }
				for _, step in steps do
					local rejection = step()
					if rejection ~= nil then
						return verdict(rejection)
					end
				end
			end

			if defects.rejectEverything then
				return verdict({ reason = "shape", detail = "rejected" })
			end

			local args = if defects.dropsArgs then nil else rawArgs
			handler(playerId, args)
			if defects.runsHandlerTwice then
				handler(playerId, args)
			end
			return nil
		end
	end

	return { Schema = Schema, Remotes = Remotes, Wrapper = Wrapper }
end

-- The baseline, and every control, as ready-made bundles. Each is built fresh
-- on access so that a check's declarations never collide across controls.
function NetStubs.correct(): Net
	return NetStubs.build({})
end

function NetStubs.with(defect: string): Net
	local defects: { [string]: boolean } = {}
	defects[defect] = true
	return NetStubs.build(defects :: any)
end

NetStubs.DEFECTS = {
	"rejectEverything",
	"booleanFalse",
	"collapseToShape",
	"identityAfterShape",
	"skipsIdentity",
	"runsHandlerTwice",
	"dropsArgs",
	"runsHandlerOnReject",
	"raisesOnNonTable",
	"consultsSchemaFirst",
	"permissiveShape",
	"nonIntegerIsShape",
	"nanIsShape",
	"rangeBeforeShape",
	"exclusiveMaximum",
	"silentRedeclare",
	"leaksRegistry",
}

return NetStubs
