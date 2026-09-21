--!strict
--[[
	NET-001: the structural validators behind every declared remote, per
	`docs/backlog/stories/NET-001.md` `## Contract`.

	A validator answers `(true, nil)` or `(false, "<kind>: <detail>")`, where
	`<kind>` is exactly `shape` or `range`. The kind LEADS the string because
	the `Schema` type is structural - a hand-written `{ validate = ... }` is a
	legal `args` - so `Wrapper` reads the kind out of the string rather than
	out of a field only this module would populate.

	WHAT THE TWO KINDS MEAN, and it is not the instinctive split:
	  * `shape` is "this is not a number, a boolean, one of the literals or a
	    table at all", a missing key, or an unexpected one. A TYPE error.
	  * `range` is a DOMAIN violation by a value of the right type: below the
	    minimum, above it, NaN, either infinity, and a non-integer where
	    `integer()` is declared. `3.5` IS a number; the integers in [1, 16] are
	    a domain of which it is not a member, exactly as 17 is not.

	TWO PASSES, NOT ONE, and that is a requirement rather than a style: the
	Contract check order makes `shape` and `range` pipeline STAGES, so a
	structural failure ANYWHERE in a payload beats a domain failure ANYWHERE in
	it. A single-pass validator answers `{ token = 99, flag = "no" }` in hash
	iteration order, which would make the rejection reason - and TEL-003 per
	reason metrics - depend on where a key happened to land. So every node
	exposes `checkShape` and `checkRange` separately, `validate` runs the
	structural pass over the whole value before the domain pass over any of it,
	and a `shape()` node recurses into its fields within each pass.

	`shape` IS EXACT. An unexpected key is a rejection, not an ignored field: a
	permissive validator is how an exploiter smuggles a field that a later
	refactor starts reading.

	`validate` NEVER RAISES, whatever it is handed - a function, a thread, a
	table where a number belongs, a table-valued key, a 100 KB string. Every
	branch tests `typeof` before it indexes, and nothing here indexes a value
	it has not already established is a table.
]]

local Schema = {}

-- The Contract structural type: what `Remotes` and `Wrapper` require of an
-- `args`, and all they require. A hand-written table with a `validate` field
-- satisfies it, which is what lets the wrapper tests inject a spy schema.
export type Schema = { validate: (value: any) -> (boolean, string?) }

-- What the constructors here return: a `Schema` plus the two halves `validate`
-- is built from, so that `shape()` can run each pass over a whole payload
-- before starting the next.
export type Validator = {
	validate: (value: any) -> (boolean, string?),
	checkShape: (value: any) -> string?,
	checkRange: (value: any) -> string?,
}

-- A long string in a failure detail is an attacker choice, not ours: a 100 KB
-- payload must not become a 100 KB rejection.
local MAX_SHOWN = 32

local function describe(value: any): string
	local kind = typeof(value)
	if kind == "string" then
		local text = value :: string
		if #text > MAX_SHOWN then
			return `a string of {#text} characters`
		end
		return `"{text}"`
	elseif kind == "number" or kind == "boolean" or kind == "nil" then
		return tostring(value)
	end
	return `a {kind}`
end

local function describeKey(key: any): string
	if typeof(key) == "string" then
		return `"{key}"`
	end
	return `[{describe(key)}]`
end

--[[
	Builds a node from its two passes. `validate` is the single entry point and
	the one place the kind prefix is written, so no constructor can forget it
	and none can invent a third kind.
]]
local function validator(
	checkShape: (value: any) -> string?,
	checkRange: (value: any) -> string?
): Validator
	return {
		checkShape = checkShape,
		checkRange = checkRange,
		validate = function(value: any): (boolean, string?)
			local structural = checkShape(value)
			if structural ~= nil then
				return false, `shape: {structural}`
			end
			local domain = checkRange(value)
			if domain ~= nil then
				return false, `range: {domain}`
			end
			return true, nil
		end,
	}
end

--[[
	The integers in [min, max], both ends inclusive. NaN, the infinities and a
	non-integer are `range`: each of them IS a number, and none of them is a
	member of the declared domain.
]]
function Schema.integer(min: number, max: number): Validator
	local expected = `an integer in [{min}, {max}]`
	return validator(function(value: any): string?
		if typeof(value) ~= "number" then
			return `expected {expected}, got {describe(value)}`
		end
		return nil
	end, function(value: any): string?
		if typeof(value) ~= "number" then
			return nil -- unreachable: the structural pass ran first and passed
		end
		local n = value :: number
		if n ~= n then
			return `expected {expected}, got NaN`
		end
		if n == math.huge or n == -math.huge then
			return `expected {expected}, got {tostring(n)}`
		end
		if n < min or n > max then
			return `{n} is outside [{min}, {max}]`
		end
		if math.floor(n) ~= n then
			return `{n} is not an integer, and {expected} was declared`
		end
		return nil
	end)
end

--[[
	The numbers in [min, max], both ends inclusive and finite only. NaN and the
	infinities are `range` here for the same reason they are for `integer`.
]]
function Schema.number(min: number, max: number): Validator
	local expected = `a number in [{min}, {max}]`
	return validator(function(value: any): string?
		if typeof(value) ~= "number" then
			return `expected {expected}, got {describe(value)}`
		end
		return nil
	end, function(value: any): string?
		if typeof(value) ~= "number" then
			return nil -- unreachable: the structural pass ran first and passed
		end
		local n = value :: number
		if n ~= n then
			return `expected {expected}, got NaN`
		end
		if n == math.huge or n == -math.huge then
			return `expected {expected}, got {tostring(n)}`
		end
		if n < min or n > max then
			return `{n} is outside [{min}, {max}]`
		end
		return nil
	end)
end

-- Exactly `true` or `false`. 1 and 0 are numbers and "true" is a string.
function Schema.boolean(): Validator
	return validator(function(value: any): string?
		if typeof(value) ~= "boolean" then
			return `expected a boolean, got {describe(value)}`
		end
		return nil
	end, function(_value: any): string?
		return nil
	end)
end

--[[
	Exactly one of the given strings - byte for byte, so case, a prefix and a
	trailing space are all rejections. Membership of a fixed set is a
	structural question, not a domain one, so every failure here is `shape`.
]]
function Schema.literal(...: string): Validator
	local allowed: { string } = { ... }
	local permitted: { [string]: boolean } = {}
	local labels: { string } = {}
	for _, text in allowed do
		permitted[text] = true
		table.insert(labels, `"{text}"`)
	end
	local expected = `one of {table.concat(labels, ", ")}`

	return validator(function(value: any): string?
		if typeof(value) ~= "string" then
			return `expected {expected}, got {describe(value)}`
		end
		if not permitted[value :: string] then
			return `expected {expected}, got {describe(value)}`
		end
		return nil
	end, function(_value: any): string?
		return nil
	end)
end

--[[
	A table with EXACTLY the declared keys. Both directions are checked: a
	declared key whose value fails its field schema, and any key that was not
	declared at all - including an array key and a table-valued one, which is
	why the extra-key scan tests `typeof(key)` before it looks the key up.

	A missing required key needs no case of its own: `payload[key]` is nil, and
	nil fails every field schema structurally except `optional`, which is the
	one that declares nil to be legal.
]]
function Schema.shape(fields: { [string]: Validator }): Validator
	return validator(function(value: any): string?
		if typeof(value) ~= "table" then
			return `expected a table, got {describe(value)}`
		end
		local payload = value :: { [any]: any }
		for key, field in fields do
			local failure = field.checkShape(payload[key])
			if failure ~= nil then
				return `field "{key}": {failure}`
			end
		end
		for key in payload do
			if typeof(key) ~= "string" or fields[key :: string] == nil then
				return `unexpected field {describeKey(key)}`
			end
		end
		return nil
	end, function(value: any): string?
		if typeof(value) ~= "table" then
			return nil -- unreachable: the structural pass ran first and passed
		end
		local payload = value :: { [any]: any }
		for key, field in fields do
			local failure = field.checkRange(payload[key])
			if failure ~= nil then
				return `field "{key}": {failure}`
			end
		end
		return nil
	end)
end

--[[
	nil passes; anything else is answered by the inner schema, kind and all.
	`false` is not nil, so `optional(integer(...))` files it as `shape` exactly
	as the bare integer would.
]]
function Schema.optional(inner: Validator): Validator
	return validator(function(value: any): string?
		if value == nil then
			return nil
		end
		return inner.checkShape(value)
	end, function(value: any): string?
		if value == nil then
			return nil
		end
		return inner.checkRange(value)
	end)
end

return Schema
