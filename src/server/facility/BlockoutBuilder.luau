--!strict
--[[
	Builds `Blockout.parts`' specs into the place, per MAP-001 C-7. IMPURE and
	Studio-verified (the story's D-1); it has no unit test.

	`build` destroys any existing child of `parent` named `Facility`, then
	creates a `Folder` named `Facility` under `parent` holding one anchored
	`Part` per spec, named, sized and positioned from it (no rotation). Floors,
	ceilings and walls collide; machine anchors do not, and are half
	transparent. It touches no Roblox global at module load.

	Calling it on round entry is SLICE-007's.
]]

local Blockout = require("./Blockout")

local BlockoutBuilder = {}

local FOLDER_NAME = "Facility"
local ANCHOR_TRANSPARENCY = 0.5

function BlockoutBuilder.build(specs: { Blockout.PartSpec }, parent: Instance): Folder
	local existing = parent:FindFirstChild(FOLDER_NAME)
	while existing ~= nil do
		existing:Destroy()
		existing = parent:FindFirstChild(FOLDER_NAME)
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, s in specs do
		local part = Instance.new("Part")
		part.Name = s.name
		part.Anchored = true
		part.Size = Vector3.new(s.size.x, s.size.y, s.size.z)
		part.CFrame = CFrame.new(s.cframe.x, s.cframe.y, s.cframe.z)
		if s.kind == "machine" then
			part.CanCollide = false
			part.Transparency = ANCHOR_TRANSPARENCY
		else
			part.CanCollide = true
		end
		part.Parent = folder
	end
	folder.Parent = parent
	return folder
end

return table.freeze(BlockoutBuilder)
