--!strict
--[[
	The wrong clock models SLICE-004's AC-3 controls are aimed at, and the
	one baseline each of them is a single defect away from.

	AC-3 is MECHANICAL for the arithmetic and SETTLED for the words, so the
	story names no control; these exist because in RED the real modules do
	not exist, `phase_clock_model_test.luau` is red at `require`, and not one
	of its assertions has run. Applying the same checks to a model that
	floors instead of ceiling is how those assertions get observed rejecting
	something before GREEN starts.

	IT IS A FACTORY OVER A TABLE OF DEFECTS: `defects` is empty for the
	baseline and has exactly ONE field set for every control. The baseline's
	`Words.phase` restates voice.md §2.1 - a stub may, the real module's test
	may not - and that restatement is what lets the controls test show the
	`VoiceSpec` reader agrees with a table it did not parse.

	WHAT THIS IS NOT: `src/client/models/PhaseClockModel.luau` or
	`src/client/Words.luau`, or a sketch of either. GREEN writes them from
	the story's `## Contract`; nothing here is to be copied.
]]

local PhaseClockStubs = {}

--[[
	One field per control, each a single edit to the baseline below.

	  countdown
	  * `floorsInsteadOfCeil`     - `math.floor(remaining)`
	  * `roundsInsteadOfCeil`     - `math.floor(remaining + 0.5)`
	  * `noClamp`                 - no `max(0, …)`; a negative remainder is
	                                formatted
	  * `paddedMinutes`           - `"%02d:%02d"`
	  * `unpaddedSeconds`         - `"%d:%d"`
	  * `ignoresReceivedAt`       - `remaining = secondsLeft - now`
	  * `ignoresElapsed`          - `remaining = secondsLeft`
	  * `nilSecondsLeftReadsZero` - a nil `secondsLeft` becomes "0:00"
	  * `mutatesTheView`          - `view.secondsLeft` is overwritten with
	                                the remainder
	  words
	  * `echoesUnknownPhase`      - a phase not in `Words.phase` is returned
	                                as its own key
	  * `wordDrift`               - `Words.phase.Post` is "Done"
	  * `extraWord`               - `Words.phase.Intermission` exists
	  * `missingWord`             - `Words.phase.Resolution` is absent
	  * `phaseKeyBypassesWords`   - `phaseKey` is `view.phase`, not
	                                `Words.phase[view.phase]`. Because §2.1
	                                is the identity map today, NO check can
	                                tell this apart from the baseline; the
	                                controls test pins that it is NOT caught,
	                                so the blind spot is on record rather
	                                than discovered.
]]
PhaseClockStubs.DEFECTS = {
	"floorsInsteadOfCeil",
	"roundsInsteadOfCeil",
	"noClamp",
	"paddedMinutes",
	"unpaddedSeconds",
	"ignoresReceivedAt",
	"ignoresElapsed",
	"nilSecondsLeftReadsZero",
	"mutatesTheView",
	"echoesUnknownPhase",
	"wordDrift",
	"extraWord",
	"missingWord",
	"phaseKeyBypassesWords",
}

function PhaseClockStubs.build(defects: { [string]: boolean }): { describe: any, Words: any }
	local phase: { [string]: string } = {
		Lobby = "Lobby",
		Assignment = "Assignment",
		Round = "Round",
		Resolution = "Resolution",
		Post = "Post",
	}
	if defects.wordDrift then
		phase.Post = "Done"
	end
	-- Not "Limbo": that is the phase the unknown-phase check probes with,
	-- and an extra word under that name would make this defect trip two
	-- checks for one cause.
	if defects.extraWord then
		phase.Intermission = "Intermission"
	end
	if defects.missingWord then
		phase.Resolution = nil
	end
	local Words = { phase = phase }

	local format = "%d:%02d"
	if defects.paddedMinutes then
		format = "%02d:%02d"
	elseif defects.unpaddedSeconds then
		format = "%d:%d"
	end

	local function describe(view: any, receivedAt: number, now: number): any
		local key: any = Words.phase[view.phase]
		if key == nil then
			if defects.echoesUnknownPhase then
				key = view.phase
			else
				error(`PhaseClockModel.describe: no word for the phase "{tostring(view.phase)}"`, 0)
			end
		elseif defects.phaseKeyBypassesWords then
			-- Validated through Words, but the INTERNAL name is returned.
			key = view.phase
		end

		local secondsLeft = view.secondsLeft
		if secondsLeft == nil and defects.nilSecondsLeftReadsZero then
			secondsLeft = 0
		end
		local countdown: string? = nil
		if secondsLeft ~= nil then
			local elapsed = now - receivedAt
			if defects.ignoresReceivedAt then
				elapsed = now
			elseif defects.ignoresElapsed then
				elapsed = 0
			end
			local remaining = secondsLeft - elapsed
			if not defects.noClamp then
				remaining = math.max(0, remaining)
			end
			local whole
			if defects.floorsInsteadOfCeil then
				whole = math.floor(remaining)
			elseif defects.roundsInsteadOfCeil then
				whole = math.floor(remaining + 0.5)
			else
				whole = math.ceil(remaining)
			end
			if defects.mutatesTheView then
				view.secondsLeft = remaining
			end
			countdown = string.format(format, whole // 60, whole % 60)
		end
		return { phaseKey = key, countdown = countdown }
	end

	return { describe = describe, Words = Words }
end

return PhaseClockStubs
