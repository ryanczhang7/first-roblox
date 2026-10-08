--!strict
--[[
	THE NEGATIVE CONTROL FOR SLICE-008 AC-3. NOT A MODULE ANYTHING MAY USE.

	It exists to break the layer-require guard on purpose. The one require
	below reaches from the client layer into the server layer through `@game`,
	which is the crossing `@shared` could never spell and `@game` can:
	`@game` is a path from the DataModel root, so in Studio and `luau-lsp` it
	names `ServerScriptService` from a client module without complaint.
	Lune would refuse it only because no `src/ServerScriptService` directory
	exists, which is incidental and not a guard.

	It lives at the real path - `src/client/`, deliberately - because
	`.claude/harness/rules.md` says a probe scanned from a temp directory is
	scanned under the wrong path rules, and then the guard silently stops
	testing anything while still passing. The rule is "a string require that
	leaves its own layer begins `@game/ReplicatedStorage/`", and the layer is
	read from the path, so the path is the point.

	`.claude/harness/paths.conf` classifies `**/__probe_*.*` as `test`, which
	does two jobs with one rule: RED may write this file, and every
	tree-scanning guard skips it - because `scripts/classify.sh --list source
	src` does not return it, not because any guard checks its name.

	Owned by `tests/shared/layer_requires_test.luau`, which is the only thing
	that may read it. That test scans `source + test` files together and
	asserts this file is reported BY NAME against the require below; delete
	this probe and that test fails, which is the point. See `rules.md`: "no
	probe-named file sits under `src/` without a guard that owns it".

	Nothing here runs. The require is the whole offence; the module exports
	only what it was handed, so it needs no `game`, no `Instance.new` and no
	Roblox runtime.
]]

local PhaseMachine = require("@game/ServerScriptService/Server/round/PhaseMachine")

local CrossLayerProbe = {}

CrossLayerProbe.PhaseMachine = PhaseMachine

return CrossLayerProbe
