--!strict
--[[
	SLICE-004: the effect interpreter. `Session.step` returns effects that
	DESCRIBE what to send to whom; this module turns each one into exactly one
	port call, in list order (`architecture.md` §9.1, §9.6). It is the one
	place a routing mistake could send a secret to everyone, which is why it
	is pure over its ports and why it does nothing else.

	    SendTo         ports.transport:sendTo(playerId, payloadKind, payload)
	    Broadcast      ports.transport:broadcast(payloadKind, payload)
	    Emit           ports.emit({ event })   - a fresh one-element list each
	    PromptRematch  ports.promptRematch()
	    ComputeTrace   ports.computeTrace(roundId)
	    Placed         ports.place(playerId, position)

	ANY OTHER KIND RAISES, naming it, AT THAT EFFECT (AC-2): the effects before
	it have been performed and the ones after it have not. There is no
	pre-validation pass. `AssignSeats` is among them - `Session` consumes it,
	and one reaching here is a bug. A silently dropped effect is a lost
	replication.

	Payloads, positions and events are passed BY IDENTITY: nothing here copies
	or inspects them. `Transport` is what refuses a private kind on
	`broadcast`, so a `SendTo` routed as a broadcast fails loudly there.
]]

local Event = require("@game/ReplicatedStorage/Shared/telemetry/Event")
local Session = require("./Session")
local Transport = require("@game/ReplicatedStorage/Net/Transport")

local Interpreter = {}

export type Ports = {
	transport: Transport.Bound,
	emit: ({ Event.TelemetryEvent }) -> (), -- Sink.dispatch(sink, events), bound by the driver
	promptRematch: () -> (), -- M3: no-op port; the card is driven by RoundView (§9.5)
	computeTrace: (roundId: string) -> (), -- M3 until TRACE-001: no-op port
	place: (playerId: string, position: { x: number, y: number, z: number }) -> (), -- no-op until SLICE-007
}

function Interpreter.perform(effects: { Session.SessionEffect }, ports: Ports)
	for _, effect in effects do
		-- Read through `any`: the union is narrowed by `kind` at run time, and
		-- an effect of a kind outside it is exactly the case AC-2 is about.
		local e: any = effect
		local kind = e.kind
		if kind == "SendTo" then
			ports.transport:sendTo(e.playerId, e.payloadKind, e.payload)
		elseif kind == "Broadcast" then
			ports.transport:broadcast(e.payloadKind, e.payload)
		elseif kind == "Emit" then
			ports.emit({ e.event })
		elseif kind == "PromptRematch" then
			ports.promptRematch()
		elseif kind == "ComputeTrace" then
			ports.computeTrace(e.roundId)
		elseif kind == "Placed" then
			ports.place(e.playerId, e.position)
		else
			error(`Interpreter.perform: no port for an effect of kind "{tostring(kind)}"`, 2)
		end
	end
end

return Interpreter
