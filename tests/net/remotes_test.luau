--!strict
--[[
	NET-001: the declaration registry. AC-8 and the Contract's `Remotes`
	block, applied to the real `src/net/Remotes.luau` with the real
	`src/net/Schema.luau` for the schemas it registers.

	Both modules are required through a `pcall` at the top and re-checked
	inside every test, so that in RED every test below FAILS naming the module
	that did not load.

	THE CHECKS LIVE IN `tests/helpers/NetContract.luau`;
	`tests/net/net_controls_test.luau` is where the AC-8 check is OBSERVED to
	fire against a registry that silently replaces, and the `all()` check
	against one that hands out its live table.

	Names are unique per declaration (`NetContract.uniqueName`) because the
	registry is module-level and this file shares one process - and one
	`Remotes` module instance - with `wrapper_test.luau`.
]]

local Contract = require("../helpers/NetContract")

local schemaLoaded, schemaResult = pcall(require, "../../src/net/Schema")
local remotesLoaded, remotesResult = pcall(require, "../../src/net/Remotes")

local function net(): Contract.Net
	assert(schemaLoaded, `src/net/Schema.luau did not load: {tostring(schemaResult)}`)
	assert(remotesLoaded, `src/net/Remotes.luau did not load: {tostring(remotesResult)}`)
	return { Schema = schemaResult, Remotes = remotesResult, Wrapper = nil }
end

return {
	["Contract: Remotes exports define and all as plain field functions"] = function()
		local Remotes = net().Remotes
		assert(typeof(Remotes.define) == "function", `Remotes.define is {typeof(Remotes.define)}`)
		assert(typeof(Remotes.all) == "function", `Remotes.all is {typeof(Remotes.all)}`)
	end,

	["Contract: define returns the declaration with name, args, legalPhases and optional rateLimit as given, all() lists it, and all() is a copy"] = function()
		Contract.defineReturnsTheDeclarationAndAllListsIt(net())
	end,

	["AC-8: declaring a name a second time fails naming the name, the first declaration is still registered and unreplaced, and a fresh name still declares"] = function()
		Contract.redeclaringANameFails(net())
	end,
}
