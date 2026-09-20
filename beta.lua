--!nonstrict
--==================================================================================
--  CJ CHARACTER CONTROLLER
--  ServerScriptService  ·  Roblox Luau
--
--  Replaces every player's character with a fully custom CJ (GTA: San Andreas) rig.
--  This rig is NOT R6 and NOT R15. It uses its own part hierarchy, its own Motor6D
--  joint layout and its own animation set driven by a server-authoritative state
--  machine.
--
--  Server-authoritative. No client input is trusted except strictly validated
--  RemoteEvent requests for Sprint / Crouch / Aim.
--
--  ▸ Fill in every value marked <<< EDIT >>> in the CONFIG block before shipping.
--==================================================================================

--==================================================================================
-- SERVICES
--==================================================================================
local Players           = game:GetService("Players")
local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local Debris            = game:GetService("Debris")

--==================================================================================
-- CONFIG
--==================================================================================
local CONFIG = {

	--================================================================================
	-- 1. RIG SOURCE
	--================================================================================
	RigTemplateName = "CJ_Rig",        -- <<< EDIT >>> exact name of your imported model
	RigContainer    = ServerStorage,   -- <<< EDIT >>> container holding that model

	-- If true, the script stops the engine from spawning a default R6/R15 character.
	-- Set to false ONLY if another system is spawning characters for you.
	DisableDefaultCharacterLoading = true,

	--================================================================================
	-- 2. LIFECYCLE / TIMING
	--================================================================================
	RespawnDelay  = 5,     -- seconds between death and the next CJ spawn
	CorpseLifetime = 5,    -- seconds the dead CJ stays in the world
	Debug         = true,  -- verbose [CJ] logging

	-- If true, a rig that fails validation is still used (warnings only).
	-- If false, a broken rig aborts the spawn instead of producing a glitched body.
	AllowPartialRig = false,

	--================================================================================
	-- 3. CUSTOM RIG LAYOUT  (<<< EDIT >>> to match your imported model EXACTLY)
	--================================================================================
	-- Logical name -> actual Instance name inside the model.
	Parts = {
		Root     = "HumanoidRootPart",
		Pelvis   = "Pelvis",
		Torso    = "Torso",
		Head     = "Head",

		LThigh   = "LeftThigh",
		LShin    = "LeftShin",
		LFoot    = "LeftFoot",

		RThigh   = "RightThigh",
		RShin    = "RightShin",
		RFoot    = "RightFoot",

		LUpperArm = "LeftUpperArm",
		LForearm  = "LeftForearm",
		LHand     = "LeftHand",

		RUpperArm = "RightUpperArm",
		RForearm  = "RightForearm",
		RHand     = "RightHand",
	},

	-- Joint layout. Each entry is { Motor6DName, ParentPartKey, ChildPartKey }.
	-- The Motor6D must live INSIDE the child part with Part0 = parent, Part1 = child.
	-- This table is used for validation and documents the rig for future maintainers.
	Joints = {
		{ "RootJoint",  "Root",      "Pelvis"     },
		{ "Waist",      "Pelvis",    "Torso"      },
		{ "Neck",       "Torso",     "Head"       },

		{ "LeftHip",    "Pelvis",    "LThigh"     },
		{ "LeftKnee",   "LThigh",    "LShin"      },
		{ "LeftAnkle",  "LShin",     "LFoot"      },

		{ "RightHip",   "Pelvis",    "RThigh"     },
		{ "RightKnee",  "RThigh",    "RShin"      },
		{ "RightAnkle", "RShin",     "RFoot"      },

		{ "LeftShoulder",  "Torso",  "LUpperArm"  },
		{ "LeftElbow",     "LUpperArm", "LForearm" },
		{ "LeftWrist",     "LForearm",  "LHand"   },

		{ "RightShoulder", "Torso",  "RUpperArm"  },
		{ "RightElbow",    "RUpperArm", "RForearm"},
		{ "RightWrist",    "RForearm",  "RHand"   },
	},

	--================================================================================
	-- 4. HUMANOID TUNING
	--================================================================================
	Humanoid = {
		-- R15 is used purely so the engine exposes attachment/scaling helpers.
		-- The rig itself is neither R6 nor R15 — it is driven by our own joints.
		RigType             = Enum.HumanoidRigType.R15,

		WalkSpeed           = 16,
		RunSpeed            = 24,
		SprintSpeed         = 32,
		CrouchSpeed         = 8,

		JumpPower           = 50,
		UseJumpPower        = true,

		HipHeight           = 2.0,
		CrouchHipHeight     = 1.0,

		MaxSlopeAngle       = 60,
		AutoRotate          = true,
		BreakJointsOnDeath  = false,  -- keep the rig intact; we play a death animation
		RequiresNeck        = false,  -- custom rig has no engine "Neck" requirement
		AutomaticScaling    = false,
		Health              = 100,
		MaxHealth           = 100,

		DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer,
		NameDisplayDistance = 100,
		HealthDisplayDistance = 100,
	},

	--================================================================================
	-- 5. LOCOMOTION THRESHOLDS (studs/second, horizontal)
	--================================================================================
	Locomotion = {
		MoveEpsilon     = 0.05,  -- MoveDirection magnitude required to leave Idle
		WalkThreshold   = 0.5,   -- above this we are "walking"
		RunThreshold    = 14,    -- above this we swap to Run
		SprintThreshold = 22,    -- above this we swap to Sprint
		SwimThreshold   = 0.5,   -- above this we use Swim instead of SwimIdle
		UpdateRate      = 1 / 15,-- state machine tick rate (seconds)
		DefaultFade     = 0.2,   -- default crossfade time
		LandFallback    = 0.45,  -- fallback Land clip length if Length is unknown
	},

	--================================================================================
	-- 6. APPEARANCE  (applied manually — HumanoidDescription does not map to this rig)
	--================================================================================
	Appearance = {
		-- "Manual" always. "HumanoidDescription" is attempted first if you set it.
		Mode = "Manual",

		-- Optional: Roblox user id to pull a HumanoidDescription from.
		-- Only works if your rig happens to match the R15 body schema. Usually it does not.
		SourceUserId = 0,

		-- Direct part colours, keyed by CONFIG.Parts key.
		PartColors = {
			Head      = Color3.fromRGB(122, 84, 60),
			Torso     = Color3.fromRGB(255, 255, 255), -- white tank top
			Pelvis    = Color3.fromRGB(40, 40, 45),    -- dark jeans
			LThigh    = Color3.fromRGB(40, 40, 45),
			RThigh    = Color3.fromRGB(40, 40, 45),
			LShin     = Color3.fromRGB(40, 40, 45),
			RShin     = Color3.fromRGB(40, 40, 45),
			LFoot     = Color3.fromRGB(20, 20, 20),
			RFoot     = Color3.fromRGB(20, 20, 20),
			LUpperArm = Color3.fromRGB(122, 84, 60),
			RUpperArm = Color3.fromRGB(122, 84, 60),
			LForearm  = Color3.fromRGB(122, 84, 60),
			RForearm  = Color3.fromRGB(122, 84, 60),
			LHand     = Color3.fromRGB(122, 84, 60),
			RHand     = Color3.fromRGB(122, 84, 60),
		},

		-- Texture instances applied to a part (keyed by CONFIG.Parts key).
		Textures = {
			-- Torso = "rbxassetid://0",
		},

		-- SurfaceAppearance definitions (keyed by CONFIG.Parts key).
		SurfaceAppearances = {
			-- Torso = {
			--     ColorMap     = "rbxassetid://0",
			--     NormalMap    = "rbxassetid://0",
			--     RoughnessMap = "rbxassetid://0",
			--     MetalnessMap = "rbxassetid://0",
			-- },
		},

		FaceDecalId   = "rbxassetid://0",  -- <<< EDIT >>> CJ's face texture
		HairModelName = "",                -- <<< EDIT >>> optional model in RigContainer
		HairAttachmentName = "HairAttachment",

		-- Uniform scale applied to the whole rig. Strongly prefer authoring the
		-- template at final size and leaving this at 1.0.
		Scale = 1.0,
	},

	--================================================================================
	-- 7. ANIMATIONS  (<<< EDIT >>> every single one of these)
	--    Id       : rbxassetid:// of your exported CJ animation
	--    Priority : AnimationPriority — keep Idle/Movement/Action separated
	--    Looped   : false for one-shots (Jump, Land, Death)
	--    Fade     : crossfade time in seconds
	--================================================================================
	Animations = {
		Idle       = { Id = "rbxassetid://0", Priority = Enum.AnimationPriority.Idle,     Looped = true,  Fade = 0.25 },
		Walk       = { Id = "rbxassetid://0", Priority = Enum.AnimationPriority.Movement, Looped = true,  Fade = 0.20 },
		Run        = { Id = "rbxassetid://0", Priority = Enum.AnimationPriority.Movement, Looped = true,  Fade = 0.20 },
		Sprint     = { Id = "rbxassetid://0", Priority = Enum.AnimationPriority.Movement, Looped = true,  Fade = 0.20 },

		Jump       = { Id = "rbxassetid://0", Priority = Enum.AnimationPriority.Action,   Looped = false, Fade = 0.10 },
		Fall       = { Id = "rbxassetid://0", Priority = Enum.AnimationPriority.Action,   Looped = true,  Fade = 0.20 },
		Land       = { Id = "rbxassetid://0", Priority = Enum.AnimationPriority.Action,   Looped = false, Fade = 0.10 },

		Climb      = { Id = "rbxassetid://0", Priority = Enum.AnimationPriority.Movement, Looped = true,  Fade = 0.20 },
		Swim       = { Id = "rbxassetid://0", Priority = Enum.AnimationPriority.Movement, Looped = true,  Fade = 0.25 },
		SwimIdle   = { Id = "rbxassetid://0", Priority = Enum.AnimationPriority.Idle,     Looped = true,  Fade = 0.25 },

		Sit        = { Id = "rbxassetid://0", Priority = Enum.AnimationPriority.Action,   Looped = true,  Fade = 0.25 },

		ToolHold   = { Id = "rbxassetid://0", Priority = Enum.AnimationPriority.Action,   Looped = true,  Fade = 0.20 },
		Aim        = { Id = "rbxassetid://0", Priority = Enum.AnimationPriority.Action2,  Looped = true,  Fade = 0.15 },

		CrouchIdle = { Id = "rbxassetid://0", Priority = Enum.AnimationPriority.Idle,     Looped = true,  Fade = 0.25 },
		CrouchWalk = { Id = "rbxassetid://0", Priority = Enum.AnimationPriority.Movement, Looped = true,  Fade = 0.20 },

		Death      = { Id = "rbxassetid://0", Priority = Enum.AnimationPriority.Action4,  Looped = false, Fade = 0.10 },
	},

	--================================================================================
	-- 8. SECURITY
	--================================================================================
	Security = {
		RemoteName          = "CJStateRequest",
		MinRequestInterval  = 0.08,  -- seconds; hard rate limit per player
	},

	--================================================================================
	-- 9. CUSTOM MOVEMENT CONTROLLER
	--    The custom rig still uses Humanoid physics (Humanoid applies force to the
	--    RootPart and drives MoveDirection). If your rig misbehaves (sinking,
	--    spinning, refusing to walk), set this to true and implement your own
	--    controller inside `stepCustomMovement` further down.
	--================================================================================
	UseCustomMovementController = false,
}

--==================================================================================
-- LOGGING HELPERS
--==================================================================================
local function log(...)
	if CONFIG.Debug then
		print("[CJ]", ...)
	end
end

local function warnLog(...)
	warn("[CJ]", ...)
end

--==================================================================================
-- RUNTIME STATE
--==================================================================================
local playerStates: { [Player]: any } = {}

--==================================================================================
-- TEMPLATE LOOKUP + VALIDATION
--==================================================================================
local function getRigTemplate(): Model?
	local container = CONFIG.RigContainer
	if not container then
		warnLog("CONFIG.RigContainer is nil.")
		return nil
	end

	local template = container:FindFirstChild(CONFIG.RigTemplateName)
	if not template then
		warnLog(("Rig template '%s' not found inside %s."):format(
			CONFIG.RigTemplateName, container:GetFullName()))
		return nil
	end

	if not template:IsA("Model") then
		warnLog(("Rig template '%s' is a %s, expected a Model."):format(
			template.Name, template.ClassName))
		return nil
	end

	return template
end

-- Maps CONFIG.Parts keys -> actual BasePart instances inside the model.
local function collectParts(model: Model): { [string]: BasePart }
	local map = {}
	for key, partName in pairs(CONFIG.Parts) do
		local inst = model:FindFirstChild(partName, true)
		if inst and inst:IsA("BasePart") then
			map[key] = inst
		end
	end
	return map
end

-- Verifies every declared Motor6D exists with the correct Part0/Part1 wiring.
local function validateJoints(model: Model, partMap: { [string]: BasePart }): { string }
	local issues = {}

	for _, joint in ipairs(CONFIG.Joints) do
		local jointName = joint[1]
		local parentKey = joint[2]
		local childKey  = joint[3]

		local parentPart = partMap[parentKey]
		local childPart  = partMap[childKey]

		if not parentPart then
			table.insert(issues, ("Joint '%s': parent part '%s' is missing."):format(jointName, parentKey))
		elseif not childPart then
			table.insert(issues, ("Joint '%s': child part '%s' is missing."):format(jointName, childKey))
		else
			local motor = childPart:FindFirstChild(jointName)
			if not motor then
				table.insert(issues, ("Motor6D '%s' not found inside '%s'."):format(jointName, childPart.Name))
			elseif not motor:IsA("Motor6D") then
				table.insert(issues, ("'%s.%s' is a %s, expected Motor6D."):format(
					childPart.Name, jointName, motor.ClassName))
			elseif motor.Part0 ~= parentPart or motor.Part1 ~= childPart then
				table.insert(issues, ("Motor6D '%s' has wrong Part0/Part1 wiring."):format(jointName))
			end
		end
	end

	return issues
end

--==================================================================================
-- SPAWN POINT RESOLUTION
--==================================================================================
local function getSpawnCFrame(player: Player): CFrame
	-- NOTE: if your place has thousands of descendants, tag your spawns with
	-- CollectionService and iterate that instead.
	local candidates = {}

	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("SpawnLocation") and inst.Enabled then
			local team = player.Team
			if inst.Neutral or (team and team.TeamColor == inst.TeamColor) then
				table.insert(candidates, inst)
			end
		end
	end

	if #candidates == 0 then
		for _, inst in ipairs(Workspace:GetDescendants()) do
			if inst:IsA("SpawnLocation") and inst.Enabled then
				table.insert(candidates, inst)
			end
		end
	end

	if #candidates > 0 then
		local spawn = candidates[math.random(1, #candidates)]
		return spawn.CFrame * CFrame.new(0, spawn.Size.Y * 0.5 + 3, 0)
	end

	warnLog(("No enabled SpawnLocation found; using fallback spawn for %s."):format(player.Name))
	return CFrame.new(0, 10, 0)
end

--==================================================================================
-- SCALE (best-effort uniform scale of parts + joints + attachments)
--==================================================================================
local function applyScale(model: Model, scale: number)
	if scale == 1 or scale <= 0 then
		return
	end

	local function scaleCFrame(cf: CFrame): CFrame
		return CFrame.new(cf.Position * scale) * (cf - cf.Position)
	end

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Size = d.Size * scale
		elseif d:IsA("Motor6D") or d:IsA("Weld") or d:IsA("Snap") or d:IsA("ManualWeld") then
			d.C0 = scaleCFrame(d.C0)
			d.C1 = scaleCFrame(d.C1)
		elseif d:IsA("Attachment") then
			d.Position = d.Position * scale
		end
	end
end

--==================================================================================
-- APPEARANCE
--==================================================================================
local function applyAppearance(character: Model, humanoid: Humanoid, partMap: { [string]: BasePart })
	local app = CONFIG.Appearance

	-- Optional HumanoidDescription path (rarely maps to a custom rig).
	if app.Mode == "HumanoidDescription" and app.SourceUserId and app.SourceUserId > 0 then
		local ok, err = pcall(function()
			local desc = Players:GetHumanoidDescriptionFromUserId(app.SourceUserId)
			humanoid:ApplyDescription(desc)
		end)
		if not ok then
			warnLog(("ApplyDescription failed for %s: %s"):format(character.Name, tostring(err)))
		end
	end

	-- 1) Part colours
	for key, color in pairs(app.PartColors or {}) do
		local part = partMap[key]
		if part then
			part.Color = color
		end
	end

	-- 2) Textures
	for key, textureId in pairs(app.Textures or {}) do
		local part = partMap[key]
		if part and typeof(textureId) == "string" and textureId ~= "" and textureId ~= "rbxassetid://0" then
			local existing = part:FindFirstChildOfClass("Texture")
			local tex = existing or Instance.new("Texture")
			tex.Name = "CJTexture"
			tex.Texture = textureId
			tex.Face = Enum.NormalId.Front
			tex.Parent = part
		end
	end

	-- 3) SurfaceAppearances
	for key, sa in pairs(app.SurfaceAppearances or {}) do
		local part = partMap[key]
		if part then
			local instance = part:FindFirstChildOfClass("SurfaceAppearance") or Instance.new("SurfaceAppearance")
			instance.Name = "CJSurface"
			instance.ColorMap     = sa.ColorMap or ""
			instance.NormalMap    = sa.NormalMap or ""
			instance.RoughnessMap = sa.RoughnessMap or ""
			instance.MetalnessMap = sa.MetalnessMap or ""
			instance.Parent = part
		end
	end

	-- 4) Face decal
	local head = partMap.Head
	if head and app.FaceDecalId and app.FaceDecalId ~= "" and app.FaceDecalId ~= "rbxassetid://0" then
		local decal = head:FindFirstChildOfClass("Decal") or Instance.new("Decal")
		decal.Name = "CJFace"
		decal.Texture = app.FaceDecalId
		decal.Face = Enum.NormalId.Front
		decal.Parent = head
	end

	-- 5) Hair / accessory welded to the head
	if head and app.HairModelName and app.HairModelName ~= "" then
		local hairTemplate = CONFIG.RigContainer:FindFirstChild(app.HairModelName)
		if hairTemplate and hairTemplate:IsA("Model") then
			local hair = hairTemplate:Clone()
			hair.Name = "CJHair"

			local attachment = head:FindFirstChild(app.HairAttachmentName)
			if not attachment then
				attachment = Instance.new("Attachment")
				attachment.Name = app.HairAttachmentName
				attachment.Parent = head
			end

			for _, d in ipairs(hair:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Massless = true
					d.CanCollide = false
					d.Anchored = false
				end
			end

			local hairPart = hair:FindFirstChildWhichIsA("BasePart")
			if hairPart then
				hair.PrimaryPart = hairPart
				hair.Parent = character

				local weld = Instance.new("WeldConstraint")
				weld.Part0 = head
				weld.Part1 = hairPart
				weld.Parent = hairPart

				hairPart.CFrame = head.CFrame * (hairPart.CFrame - hairPart.CFrame.Position)
			else
				hair:Destroy()
			end
		else
			warnLog(("Hair model '%s' not found in %s."):format(app.HairModelName, CONFIG.RigContainer:GetFullName()))
		end
	end
end

--==================================================================================
-- CHARACTER CONSTRUCTION
--==================================================================================
local function buildCharacter(player: Player): Model?
	local template = getRigTemplate()
	if not template then
		return nil
	end

	local ok, character = pcall(function()
		return template:Clone()
	end)
	if not ok or not character then
		warnLog(("Failed to clone rig template: %s"):format(tostring(character)))
		return nil
	end

	character.Name = player.Name
	character:SetAttribute("CJCharacter", true)

	-- Strip anything the template shipped with (default Animate LocalScript, etc).
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BaseScript") then
			d:Destroy()
		end
	end

	-- ---- Humanoid ------------------------------------------------------------
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warnLog(("Rig template '%s' has no Humanoid."):format(template.Name))
		character:Destroy()
		return nil
	end

	-- Remove duplicate Animators so LoadAnimation targets a single one.
	local animators = humanoid:GetChildren()
	local keptAnimator = nil
	for _, child in ipairs(animators) do
		if child:IsA("Animator") then
			if keptAnimator then
				child:Destroy()
			else
				keptAnimator = child
			end
		end
	end
	if not keptAnimator then
		local animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- ---- Part map + joint validation -----------------------------------------
	local partMap = collectParts(character)
	local issues = validateJoints(character, partMap)
	for _, issue in ipairs(issues) do
		warnLog(("Rig issue (%s): %s"):format(player.Name, issue))
	end
	if #issues > 0 and not CONFIG.AllowPartialRig then
		warnLog(("Aborting spawn for %s — rig failed validation."):format(player.Name))
		character:Destroy()
		return nil
	end

	local root = partMap.Root
	if not root then
		warnLog(("Rig is missing the root part '%s'."):format(CONFIG.Parts.Root))
		character:Destroy()
		return nil
	end
	character.PrimaryPart = root

	-- ---- Humanoid configuration ----------------------------------------------
	local hcfg = CONFIG.Humanoid
	humanoid.RigType                = hcfg.RigType
	humanoid.WalkSpeed              = hcfg.WalkSpeed
	humanoid.UseJumpPower           = hcfg.UseJumpPower
	humanoid.JumpPower              = hcfg.JumpPower
	humanoid.HipHeight              = hcfg.HipHeight
	humanoid.MaxSlopeAngle          = hcfg.MaxSlopeAngle
	humanoid.AutoRotate             = hcfg.AutoRotate
	humanoid.BreakJointsOnDeath     = hcfg.BreakJointsOnDeath
	humanoid.RequiresNeck           = hcfg.RequiresNeck
	humanoid.AutomaticScalingEnabled = hcfg.AutomaticScaling
	humanoid.DisplayDistanceType    = hcfg.DisplayDistanceType
	humanoid.NameDisplayDistance    = hcfg.NameDisplayDistance
	humanoid.HealthDisplayDistance  = hcfg.HealthDisplayDistance

	humanoid.MaxHealth = hcfg.MaxHealth
	humanoid.Health    = hcfg.Health

	-- ---- Appearance ----------------------------------------------------------
	applyAppearance(character, humanoid, partMap)

	-- ---- Scale ---------------------------------------------------------------
	pcall(applyScale, character, CONFIG.Appearance.Scale or 1)

	-- ---- Position ------------------------------------------------------------
	local ok2, err2 = pcall(function()
		character:PivotTo(getSpawnCFrame(player))
	end)
	if not ok2 then
		warnLog(("PivotTo failed for %s: %s"):format(player.Name, tostring(err2)))
	end

	return character
end

--==================================================================================
-- ANIMATION CONTROLLER + STATE MACHINE
--==================================================================================
local function createAnimationController(character: Model, humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- ---- Load every configured clip -----------------------------------------
	local tracks: { [string]: AnimationTrack } = {}
	local missing: { string } = {}

	for name, data in pairs(CONFIG.Animations) do
		local id = data.Id
		if typeof(id) == "string" and id ~= "" and id ~= "rbxassetid://0" then
			local anim = Instance.new("Animation")
			anim.Name = "CJ_" .. name
			anim.AnimationId = id

			local ok, track = pcall(function()
				return animator:LoadAnimation(anim)
			end)

			if ok and track then
				track.Priority = data.Priority or Enum.AnimationPriority.Movement
				track.Looped   = (data.Looped ~= false)
				tracks[name]   = track
			else
				table.insert(missing, ("%s (%s)"):format(name, id))
			end
		else
			table.insert(missing, ("%s (no asset id)"):format(name))
		end
	end

	if #missing > 0 then
		warnLog(("Animations not loaded for %s: %s"):format(character.Name, table.concat(missing, ", ")))
	end

	-- ---- Local state ---------------------------------------------------------
	local currentTrack: AnimationTrack? = nil
	local currentName: string? = nil
	local dead = false
	local landUntil = 0
	local landDuration = (tracks.Land and tracks.Land.Length > 0) and tracks.Land.Length or CONFIG.Locomotion.LandFallback
	local connections: { RBXScriptConnection } = {}
	local destroyed = false

	local function track_conn(conn: RBXScriptConnection)
		table.insert(connections, conn)
	end

	-- ---- Play ----------------------------------------------------------------
	local function play(name: string, fadeOverride: number?)
		local track = tracks[name]
		if not track then
			return
		end
		if currentTrack == track and track.IsPlaying then
			return
		end

		local data = CONFIG.Animations[name]
		local fade = fadeOverride or (data and data.Fade) or CONFIG.Locomotion.DefaultFade

		if currentTrack and currentTrack.IsPlaying then
			currentTrack:Stop(fade)
		end

		currentTrack = track
		currentName = name

		local ok, err = pcall(function()
			track:Play(fade)
		end)
		if not ok then
			warnLog(("Failed to play '%s': %s"):format(name, tostring(err)))
		end
	end

	-- ---- Speed helpers -------------------------------------------------------
	local function getRoot(): BasePart?
		return humanoid.RootPart
	end

	local function getHorizontalSpeed(): number
		local root = getRoot()
		if not root then
			return 0
		end
		local v = root.AssemblyLinearVelocity
		return Vector3.new(v.X, 0, v.Z).Magnitude
	end

	-- ---- Desired state -------------------------------------------------------
	local function computeDesiredState(): string
		if dead or humanoid.Health <= 0 then
			return "Death"
		end

		local state = humanoid:GetState()

		if state == Enum.HumanoidStateType.Dead then
			return "Death"
		end

		if state == Enum.HumanoidStateType.Swimming then
			local speed = getHorizontalSpeed()
			return speed > CONFIG.Locomotion.SwimThreshold and "Swim" or "SwimIdle"
		end

		if state == Enum.HumanoidStateType.Climbing then
			return "Climb"
		end

		if state == Enum.HumanoidStateType.Seated then
			return "Sit"
		end

		if state == Enum.HumanoidStateType.Jumping then
			return "Jump"
		end

		if state == Enum.HumanoidStateType.Freefall
			or state == Enum.HumanoidStateType.Ragdoll
			or state == Enum.HumanoidStateType.FallingDown
			or state == Enum.HumanoidStateType.GettingUp then
			return "Fall"
		end

		if os.clock() < landUntil then
			return "Land"
		end

		-- ---- Grounded locomotion --------------------------------------------
		local moveMag = humanoid.MoveDirection.Magnitude
		local speed = getHorizontalSpeed()

		local crouching = character:GetAttribute("Crouching") == true
		local aiming    = character:GetAttribute("Aiming") == true
		local sprinting = character:GetAttribute("Sprinting") == true

		if moveMag <= CONFIG.Locomotion.MoveEpsilon and speed < CONFIG.Locomotion.WalkThreshold then
			if crouching then
				return "CrouchIdle"
			end
			if aiming then
				return "Aim"
			end
			if character:FindFirstChildOfClass("Tool") then
				return "ToolHold"
			end
			return "Idle"
		end

		if crouching then
			return "CrouchWalk"
		end

		if sprinting or speed >= CONFIG.Locomotion.SprintThreshold then
			return "Sprint"
		end
		if speed >= CONFIG.Locomotion.RunThreshold then
			return "Run"
		end
		return "Walk"
	end

	-- ---- Update --------------------------------------------------------------
	local function update()
		if destroyed then
			return
		end
		if not character.Parent then
			return
		end

		local desired = computeDesiredState()
		if desired ~= currentName then
			play(desired)
		end
	end

	-- ---- Connections ---------------------------------------------------------
	local accumulator = 0
	track_conn(RunService.Heartbeat:Connect(function(dt)
		if destroyed then
			return
		end
		accumulator += dt
		if accumulator < CONFIG.Locomotion.UpdateRate then
			return
		end
		accumulator = 0
		update()
	end))

	track_conn(humanoid.StateChanged:Connect(function(_old, new)
		if destroyed then
			return
		end

		if new == Enum.HumanoidStateType.Landed then
			landUntil = os.clock() + landDuration
		elseif new == Enum.HumanoidStateType.Jumping
			or new == Enum.HumanoidStateType.Freefall
			or new == Enum.HumanoidStateType.Swimming
			or new == Enum.HumanoidStateType.Climbing then
			landUntil = 0
		end

		task.defer(update)
	end))

	track_conn(humanoid.Died:Connect(function()
		dead = true
		landUntil = 0
		play("Death", 0.05)
	end))

	track_conn(character.Destroying:Connect(function()
		destroyed = true
	end))

	local function destroy()
		destroyed = true
		for _, conn in ipairs(connections) do
			pcall(function()
				conn:Disconnect()
			end)
		end
		table.clear(connections)
	end

	-- Kick off the initial state.
	play(computeDesiredState(), 0)

	return {
		destroy = destroy,
		play = play,
		update = update,
		tracks = tracks,
	}
end

--==================================================================================
-- OPTIONAL CUSTOM MOVEMENT CONTROLLER HOOK
--==================================================================================
-- Called every Heartbeat when CONFIG.UseCustomMovementController is true.
-- The Humanoid is still present; use it for MoveDirection, WalkSpeed, etc.
-- Implement your own velocity integration here if Humanoid physics is not
-- sufficient for your rig topology.
local function stepCustomMovement(_character: Model, _humanoid: Humanoid, _dt: number)
	-- Example skeleton:
	--   local root = humanoid.RootPart
	--   local wish = humanoid.MoveDirection * humanoid.WalkSpeed
	--   local current = root.AssemblyLinearVelocity
	--   local delta = Vector3.new(wish.X - current.X, 0, wish.Z - current.Z)
	--   root.AssemblyLinearVelocity = current + delta * math.min(1, dt * 20)
end

--==================================================================================
-- CHARACTER SETUP / TEARDOWN
--==================================================================================
local spawnPlayerCharacter -- forward declaration

local function setupCharacter(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warnLog(("Character for %s lost its Humanoid."):format(player.Name))
		character:Destroy()
		return
	end

	local controller = createAnimationController(character, humanoid)

	-- Optional custom movement loop.
	local movementConn: RBXScriptConnection? = nil
	if CONFIG.UseCustomMovementController then
		movementConn = RunService.Heartbeat:Connect(function(dt)
			if character.Parent and humanoid.Health > 0 then
				pcall(stepCustomMovement, character, humanoid, dt)
			end
		end)
	end

	local diedConn: RBXScriptConnection? = nil
	diedConn = humanoid.Died:Connect(function()
		if diedConn then
			diedConn:Disconnect()
			diedConn = nil
		end
		if movementConn then
			movementConn:Disconnect()
			movementConn = nil
		end

		controller.destroy()

		-- Keep the corpse briefly, then remove it.
		Debris:AddItem(character, CONFIG.CorpseLifetime)

		local state = playerStates[player]
		if not state then
			return
		end

		local myToken = state.spawnToken
		task.delay(CONFIG.RespawnDelay, function()
			if not player.Parent then
				return
			end
			if playerStates[player] ~= state then
				return
			end
			if state.spawnToken ~= myToken then
				return
			end
			spawnPlayerCharacter(player)
		end)
	end)
end

--==================================================================================
-- SPAWN PIPELINE
--==================================================================================
spawnPlayerCharacter = function(player: Player)
	local state = playerStates[player]
	if not state then
		return
	end

	state.spawnToken += 1
	local myToken = state.spawnToken

	-- Tear down any previous body cleanly.
	local previous = player.Character
	if previous then
		pcall(function()
			previous:Destroy()
		end)
		player.Character = nil
	end

	local character = buildCharacter(player)
	if not character then
		warnLog(("Could not build a CJ rig for %s."):format(player.Name))
		return
	end

	-- Abort if the world changed while we were building.
	if not player.Parent or state.spawnToken ~= myToken then
		character:Destroy()
		return
	end

	character.Parent = Workspace
	player.Character = character

	setupCharacter(player, character)
	log(("Spawned CJ rig for %s."):format(player.Name))
end

--==================================================================================
-- REMOTE: STRICTLY VALIDATED STATE REQUESTS
--==================================================================================
local function getOrCreateStateRemote(): RemoteEvent
	local remote = ReplicatedStorage:FindFirstChild(CONFIG.Security.RemoteName)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	local newRemote = Instance.new("RemoteEvent")
	newRemote.Name = CONFIG.Security.RemoteName
	newRemote.Parent = ReplicatedStorage
	return newRemote
end

local stateRemote = getOrCreateStateRemote()

local function applySprint(player: Player, character: Model, humanoid: Humanoid, value: boolean)
	character:SetAttribute("Sprinting", value)

	local crouching = character:GetAttribute("Crouching") == true
	if crouching then
		return
	end

	humanoid.WalkSpeed = value and CONFIG.Humanoid.SprintSpeed or CONFIG.Humanoid.WalkSpeed
end

local function applyCrouch(player: Player, character: Model, humanoid: Humanoid, value: boolean)
	character:SetAttribute("Crouching", value)

	if value then
		humanoid.WalkSpeed = CONFIG.Humanoid.CrouchSpeed
		humanoid.HipHeight = CONFIG.Humanoid.CrouchHipHeight
	else
		local sprinting = character:GetAttribute("Sprinting") == true
		humanoid.WalkSpeed = sprinting and CONFIG.Humanoid.SprintSpeed or CONFIG.Humanoid.WalkSpeed
		humanoid.HipHeight = CONFIG.Humanoid.HipHeight
	end
end

local function applyAim(player: Player, character: Model, humanoid: Humanoid, value: boolean)
	character:SetAttribute("Aiming", value)
end

stateRemote.OnServerEvent:Connect(function(player, action, value)
	-- 1) Type validation
	if typeof(action) ~= "string" then
		return
	end
	if typeof(value) ~= "boolean" then
		return
	end
	if #action > 32 then
		return
	end

	-- 2) Player state + rate limit
	local state = playerStates[player]
	if not state then
		return
	end
	local now = os.clock()
	if now - state.lastRequest < CONFIG.Security.MinRequestInterval then
		return
	end
	state.lastRequest = now

	-- 3) Live character + Humanoid
	local character = player.Character
	if not character or not character.Parent then
		return
	end
	if not character:GetAttribute("CJCharacter") then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- 4) Whitelist dispatch
	if action == "Sprint" then
		applySprint(player, character, humanoid, value)
	elseif action == "Crouch" then
		applyCrouch(player, character, humanoid, value)
	elseif action == "Aim" then
		applyAim(player, character, humanoid, value)
	else
		return
	end
end)

--==================================================================================
-- PLAYER LIFECYCLE
--==================================================================================
local function onPlayerAdded(player: Player)
	local state = {
		spawnToken = 0,
		lastRequest = 0,
	}
	playerStates[player] = state

	-- Safety net: if anything else spawns a default character, replace it.
	state.characterAddedConn = player.CharacterAdded:Connect(function(character)
		if character:GetAttribute("CJCharacter") then
			return -- our own rig, nothing to do
		end
		warnLog(("Non-CJ character detected for %s; replacing."):format(player.Name))
		task.defer(function()
			if player.Parent and playerStates[player] == state then
				spawnPlayerCharacter(player)
			end
		end)
	end)

	-- CharacterAutoLoads is off, so we spawn manually.
	task.defer(function()
		if player.Parent and playerStates[player] == state then
			spawnPlayerCharacter(player)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	local state = playerStates[player]
	if state then
		if state.characterAddedConn then
			pcall(function()
				state.characterAddedConn:Disconnect()
			end)
		end
		playerStates[player] = nil
	end
end

--==================================================================================
-- INIT
--==================================================================================
local function init()
	if CONFIG.DisableDefaultCharacterLoading then
		Players.CharacterAutoLoads = false
		log("Default character loading disabled.")
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Handle players already in the game (script reloaded in Studio, etc).
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	log("CJ Character Controller initialised.")
end

-- Validate the template up-front so problems surface immediately.
do
	local template = getRigTemplate()
	if template then
		local probe = template:Clone()
		local partMap = collectParts(probe)
		local issues = validateJoints(probe, partMap)
		for _, issue in ipairs(issues) do
			warnLog(("Template validation: %s"):format(issue))
		end
		if #issues == 0 then
			log("Rig template validated successfully.")
		end
		probe:Destroy()
	end
end

init()
