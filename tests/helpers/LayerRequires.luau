--!strict
--[[
	The layer-require rule behind SLICE-008 AC-1 and AC-3, as a function of a
	path and a text, so that `tests/shared/layer_requires_test.luau` can apply
	it to the real tree and `layer_requires_controls_test.luau` can apply it to
	in-memory modules written to break it.

	THE FILE LIST IS NOT DECIDED HERE. The guard asks `SourceScan.sourceFiles()`
	and `SourceScan.nonSourceFilesUnderSrc()`, which ask `scripts/classify.sh`;
	this module only reads the files it is handed. `.claude/harness/rules.md`
	says why there is exactly one answer to "which files are source" and why a
	private walk here would be the defect it describes. The lexing is
	`SourceScan.codeOnly`, the same one every other guard uses, so a require
	quoted in a comment or a string is not a require here either.

	THE RULE (story `## Contract` C-4), read from the require string alone:
	  - `./…` and `../…` stay inside the layer: permitted.
	  - `@self` and `@self/…`: permitted.
	  - `@game/ReplicatedStorage/Shared/…` and `@game/ReplicatedStorage/Net/…`
	    are the only permitted crossings - except from `shared`, which requires
	    nothing outside itself, so `@game/ReplicatedStorage/Net/…` from a shared
	    module is a violation.
	  - any other `@…` (`@shared/X`, `@net/X`, `@game/ServerScriptService/…`,
	    `@game/StarterPlayer/…`, `@game/ReplicatedStorage/Other/…`, `@lune/…`)
	    is a violation.
	  - a string that is neither relative nor an alias (`Foo`, `src/x`) is a
	    violation: no reader of this tree resolves it the same way.

	The layer is read from the path: `src/ReplicatedStorage/Shared/` is
	`shared`, `src/ReplicatedStorage/Net/` is `net`, `src/server/` is `server`,
	`src/client/` is `client`. A source file in none of them is reported as a
	violation of its own kind, because a file the rule cannot place is a file
	the rule is not checking.

	WHAT THIS CANNOT SEE: a require whose argument is not a string literal
	(`require(path)`, `require(prefix .. "/X")`). Those do not resolve in a
	place either, and the typecheck gate is the instrument for them.
]]

local SourceScan = require("./SourceScan")

local LayerRequires = {}

export type Layer = "shared" | "net" | "server" | "client"

export type Require = {
	line: number,
	target: string,
}

export type Violation = {
	path: string,
	line: number,
	target: string,
	layer: string,
	reason: string,
}

local LAYERS: { { prefix: string, layer: Layer } } = {
	{ prefix = "src/ReplicatedStorage/Shared/", layer = "shared" },
	{ prefix = "src/ReplicatedStorage/Net/", layer = "net" },
	{ prefix = "src/server/", layer = "server" },
	{ prefix = "src/client/", layer = "client" },
}

LayerRequires.SHARED_PREFIX = "@game/ReplicatedStorage/Shared/"
LayerRequires.NET_PREFIX = "@game/ReplicatedStorage/Net/"

local function startsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

-- The layer a path belongs to, or nil for a path outside every layer.
function LayerRequires.layerOf(path: string): Layer?
	for _, entry in LAYERS do
		if startsWith(path, entry.prefix) then
			return entry.layer
		end
	end
	return nil
end

--[[
	Every string require in `text`, with its line. `require` is located in the
	code-only view so a mention in a comment or a string is not a call; the
	literal is then read from the raw line at the same column, because the
	code-only view has blanked it. `require "x"` without parentheses is a call
	too, and is read.
]]
function LayerRequires.requiresIn(text: string): { Require }
	local out: { Require } = {}
	local codeLines = string.split(SourceScan.codeOnly(text), "\n")
	local rawLines = string.split(text, "\n")

	for lineNumber, codeLine in codeLines do
		local raw = rawLines[lineNumber] or ""
		local from = 1
		while true do
			local s, e = string.find(codeLine, "require", from, true)
			if s == nil then
				break
			end
			local start = s :: number
			local finish = e :: number
			local before = string.sub(codeLine, start - 1, start - 1)
			local after = string.sub(codeLine, finish + 1, finish + 1)
			local isWord = (start == 1 or not string.match(before, "[%w_%.:]"))
				and not string.match(after, "[%w_]")
			if isWord then
				local target = string.match(raw, "^%s*%(?%s*[\"']([^\"']*)[\"']", finish + 1)
				if target ~= nil then
					table.insert(out, { line = lineNumber, target = target :: string })
				end
			end
			from = finish + 1
		end
	end

	return out
end

-- Does `target` begin with one of the two spellings AC-1 retires?
function LayerRequires.isRetiredAlias(target: string): boolean
	return startsWith(target, "@shared") or startsWith(target, "@net")
end

--[[
	The C-4 rule on one require from one layer. Returns nil when the require
	is permitted, otherwise the reason it is not - which is the text the
	failure message carries, so it names the rule rather than the symptom.
]]
function LayerRequires.reasonFor(layer: Layer, target: string): string?
	if startsWith(target, "./") or startsWith(target, "../") then
		return nil
	end
	if target == "@self" or startsWith(target, "@self/") then
		return nil
	end
	if startsWith(target, LayerRequires.SHARED_PREFIX) then
		return nil
	end
	if startsWith(target, LayerRequires.NET_PREFIX) then
		if layer == "shared" then
			return "shared requires nothing outside itself"
		end
		return nil
	end
	if startsWith(target, "@") then
		return "a require that leaves its layer must begin @game/ReplicatedStorage/Shared/ "
			.. "or @game/ReplicatedStorage/Net/"
	end
	return "neither a relative path nor an alias"
end

-- Every violation in `text`, attributed to `path`.
function LayerRequires.violationsIn(path: string, text: string): { Violation }
	local violations: { Violation } = {}
	local layer = LayerRequires.layerOf(path)
	local requires = LayerRequires.requiresIn(text)

	if layer == nil then
		for _, req in requires do
			table.insert(violations, {
				path = path,
				line = req.line,
				target = req.target,
				layer = "(none)",
				reason = "the file is in no layer the rule knows",
			})
		end
		return violations
	end

	for _, req in requires do
		local reason = LayerRequires.reasonFor(layer :: Layer, req.target)
		if reason ~= nil then
			table.insert(violations, {
				path = path,
				line = req.line,
				target = req.target,
				layer = layer :: string,
				reason = reason :: string,
			})
		end
	end
	return violations
end

-- Every violation across `paths`, read through the gated filesystem via
-- `SourceScan`'s reader, accumulated and asserted once by the caller.
function LayerRequires.scan(paths: { string }, readFile: (string) -> string): { Violation }
	local violations: { Violation } = {}
	for _, path in paths do
		for _, violation in LayerRequires.violationsIn(path, readFile(path)) do
			table.insert(violations, violation)
		end
	end
	return violations
end

-- Every require across `paths` that begins `@shared` or `@net` (AC-1).
function LayerRequires.retiredAliasesIn(
	paths: { string },
	readFile: (string) -> string
): { Violation }
	local hits: { Violation } = {}
	for _, path in paths do
		for _, req in LayerRequires.requiresIn(readFile(path)) do
			if LayerRequires.isRetiredAlias(req.target) then
				table.insert(hits, {
					path = path,
					line = req.line,
					target = req.target,
					layer = (LayerRequires.layerOf(path) or "(none)") :: string,
					reason = "the @shared and @net aliases are retired; spell it @game/ReplicatedStorage/…",
				})
			end
		end
	end
	return hits
end

-- The failure message. AC-3 requires the refusal to name the file AND the
-- require, so both lead every line.
function LayerRequires.describe(violations: { Violation }): string
	if #violations == 0 then
		return "(no violations)"
	end
	local lines: { string } = {}
	for _, v in violations do
		table.insert(lines, `{v.path}:{v.line} requires "{v.target}" from {v.layer}: {v.reason}`)
	end
	return table.concat(lines, "\n")
end

return LayerRequires
