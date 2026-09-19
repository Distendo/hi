-- ServerScriptService/SandboxManager.server.lua
-- Sandbox Manager: creates a pocket baseplate + miniature glass cube per player.
-- Player teleports into the pocket baseplate; a scaled replica moves inside the cube.

local Workspace      = game:GetService("Workspace")
local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local Debris         = game:GetService("Debris")
local TweenService   = game:GetService("TweenService")

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------
local SANDBOX_SIZE   = 30                -- studs, pocket baseplate
local SCALE_FACTOR   = 0.08              -- 1:12.5
local CUBE_SIZE      = SANDBOX_SIZE * SCALE_FACTOR -- 2.4 studs
local POCKET_HEIGHT  = 200               -- studs above origin
local POCKET_SPACING = 100               -- horizontal spacing per player
local HOLD_OFFSET    = CFrame.new(0, -0.35, -0.9) -- where cube sits in hand
local PICKUP_COOLDOWN = 0.4

local activeSandboxes = {}

--------------------------------------------------------------------------------
-- PALETTE / MATERIALS
--------------------------------------------------------------------------------
local COLOR_BASE      = Color3.fromRGB(58, 62, 74)
local COLOR_BASE_EDGE = Color3.fromRGB(96, 104, 122)
local COLOR_GRID      = Color3.fromRGB(80, 86, 100)
local COLOR_GLASS     = Color3.fromRGB(150, 210, 255)
local COLOR_FRAME     = Color3.fromRGB(230, 240, 255)
local COLOR_EXIT      = Color3.fromRGB(255, 90, 90)
local COLOR_ENTER     = Color3.fromRGB(90, 220, 160)

--------------------------------------------------------------------------------
-- ASSET HELPERS
--------------------------------------------------------------------------------
local function makePart(props)
	local p = Instance.new("Part")
	p.Anchored    = true
	p.CanCollide  = true
	p.TopSurface  = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	return p
end

local function weldTo(part0, part1)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = part0, part1
	w.Parent = part0
	return w
end

local function makePrompt(parent, action, object, hold)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText   = action
	pp.ObjectText   = object
	pp.HoldDuration = hold or 0.2
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight   = false
	pp.Parent = parent
	return pp
end

local function makeSurfaceGui(part, face, size)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50
	sg.LightInfluence = 0
	sg.Parent = part
	return sg
end

--------------------------------------------------------------------------------
-- 1a. POCKET BASEPLATE
--------------------------------------------------------------------------------
local function buildPocketBaseplate(player)
	local origin = Vector3.new((player.UserId % 10) * POCKET_SPACING, POCKET_HEIGHT, 0)

	local model = Instance.new("Model")
	model.Name = "PocketBaseplate_" .. player.Name

	-- Main floor
	local floor = makePart({
		Name = "Floor",
		Size = Vector3.new(SANDBOX_SIZE, 1, SANDBOX_SIZE),
		Position = origin,
		Material = Enum.Material.SmoothPlastic,
		Color = COLOR_BASE,
	})
	floor.Parent = model

	-- Grid texture on top of the floor
	local grid = Instance.new("Texture")
	grid.Texture = "rbxassetid://6372755229" -- generic grid
	grid.Face = Enum.NormalId.Top
	grid.StudsPerTileU = 2
	grid.StudsPerTileV = 2
	grid.Transparency = 0.35
	grid.Color3 = COLOR_GRID
	grid.Parent = floor

	-- Edge trim (4 thin bars around the baseplate)
	local trimSize = 0.5
	local half = SANDBOX_SIZE / 2
	local trims = {
		{ Size = Vector3.new(SANDBOX_SIZE + trimSize, 1.2, trimSize), Offset = Vector3.new(0, 0.1,  half) },
		{ Size = Vector3.new(SANDBOX_SIZE + trimSize, 1.2, trimSize), Offset = Vector3.new(0, 0.1, -half) },
		{ Size = Vector3.new(trimSize, 1.2, SANDBOX_SIZE + trimSize), Offset = Vector3.new( half, 0.1, 0) },
		{ Size = Vector3.new(trimSize, 1.2, SANDBOX_SIZE + trimSize), Offset = Vector3.new(-half, 0.1, 0) },
	}
	for _, cfg in ipairs(trims) do
		local t = makePart({
			Size = cfg.Size,
			CFrame = floor.CFrame * CFrame.new(cfg.Offset),
			Material = Enum.Material.Metal,
			Color = COLOR_BASE_EDGE,
			CanCollide = true,
		})
		t.Parent = model
	end

	-- Corner pillars (short, decorative)
	local pillarH = 1.6
	for _, sx in ipairs({-1, 1}) do
		for _, sz in ipairs({-1, 1}) do
			local p = makePart({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(pillarH, 1.2, 1.2),
				CFrame = floor.CFrame * CFrame.new(sx * half, pillarH/2, sz * half) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Metal,
				Color = COLOR_BASE_EDGE,
			})
			p.Parent = model
		end
	end

	-- Spawn pad (glowing ring) in the middle-ish
	local pad = makePart({
		Name = "SpawnPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 6, 6),
		CFrame = floor.CFrame * CFrame.new(0, 0.6, -8) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon,
		Color = COLOR_ENTER,
		CanCollide = false,
		Transparency = 0.15,
	})
	pad.Parent = model

	-- Floating name tag
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 220, 0, 44)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = floor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = player.DisplayName .. "'s Sandbox"
	label.TextColor3 = Color3.fromRGB(235, 240, 255)
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.Parent = billboard

	model.PrimaryPart = floor
	model.Parent = Workspace
	return model, floor
end

--------------------------------------------------------------------------------
-- 1b. GLASS CUBE
--------------------------------------------------------------------------------
local function buildGlassCube(player, spawnCFrame, baseColor)
	local model = Instance.new("Model")
	model.Name = "MiniCube_" .. player.Name

	-- Bottom floor of the cube (this is the "carry" part)
	local cubeFloor = makePart({
		Name = "CubeFloor",
		Size = Vector3.new(CUBE_SIZE, 0.15, CUBE_SIZE),
		CFrame = spawnCFrame * CFrame.new(0, 3, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = baseColor,
		CanCollide = true,
	})
	cubeFloor.Parent = model
	model.PrimaryPart = cubeFloor

	-- Glass shell (5 panels)
	local half = CUBE_SIZE / 2
	local glass = Enum.Material.Glass
	local wallConfigs = {
		{ Size = Vector3.new(CUBE_SIZE, CUBE_SIZE, 0.08), Offset = Vector3.new(0, half,  half) },
		{ Size = Vector3.new(CUBE_SIZE, CUBE_SIZE, 0.08), Offset = Vector3.new(0, half, -half) },
		{ Size = Vector3.new(0.08, CUBE_SIZE, CUBE_SIZE), Offset = Vector3.new( half, half, 0) },
		{ Size = Vector3.new(0.08, CUBE_SIZE, CUBE_SIZE), Offset = Vector3.new(-half, half, 0) },
		{ Size = Vector3.new(CUBE_SIZE, 0.08, CUBE_SIZE), Offset = Vector3.new(0, CUBE_SIZE, 0) },
	}
	for _, cfg in ipairs(wallConfigs) do
		local wall = makePart({
			Size = cfg.Size,
			CFrame = cubeFloor.CFrame * CFrame.new(cfg.Offset),
			Material = glass,
			Color = COLOR_GLASS,
			Transparency = 0.75,
			Reflectance = 0.35,
			CanCollide = true,
		})
		wall.Parent = model
		weldTo(cubeFloor, wall)
	end

	-- Glowing edge frame (thin neon bars along the 12 edges)
	local frame = Enum.Material.Neon
	local frameT = 0.7
	local bar = 0.06
	local edges = {
		-- vertical (4)
		{ Size = Vector3.new(bar, CUBE_SIZE, bar), Offset = Vector3.new( half, half,  half) },
		{ Size = Vector3.new(bar, CUBE_SIZE, bar), Offset = Vector3.new( half, half, -half) },
		{ Size = Vector3.new(bar, CUBE_SIZE, bar), Offset = Vector3.new(-half, half,  half) },
		{ Size = Vector3.new(bar, CUBE_SIZE, bar), Offset = Vector3.new(-half, half, -half) },
		-- horizontal top (4)
		{ Size = Vector3.new(CUBE_SIZE, bar, bar), Offset = Vector3.new(0, CUBE_SIZE,  half) },
		{ Size = Vector3.new(CUBE_SIZE, bar, bar), Offset = Vector3.new(0, CUBE_SIZE, -half) },
		{ Size = Vector3.new(bar, bar, CUBE_SIZE), Offset = Vector3.new( half, CUBE_SIZE, 0) },
		{ Size = Vector3.new(bar, bar, CUBE_SIZE), Offset = Vector3.new(-half, CUBE_SIZE, 0) },
		-- horizontal bottom (4)
		{ Size = Vector3.new(CUBE_SIZE, bar, bar), Offset = Vector3.new(0, 0,  half) },
		{ Size = Vector3.new(CUBE_SIZE, bar, bar), Offset = Vector3.new(0, 0, -half) },
		{ Size = Vector3.new(bar, bar, CUBE_SIZE), Offset = Vector3.new( half, 0, 0) },
		{ Size = Vector3.new(bar, bar, CUBE_SIZE), Offset = Vector3.new(-half, 0, 0) },
	}
	for _, cfg in ipairs(edges) do
		local e = makePart({
			Size = cfg.Size,
			CFrame = cubeFloor.CFrame * CFrame.new(cfg.Offset),
			Material = frame,
			Color = COLOR_FRAME,
			Transparency = frameT,
			CanCollide = false,
		})
		e.Parent = model
		weldTo(cubeFloor, e)
	end

	model.Parent = Workspace
	return model, cubeFloor
end

--------------------------------------------------------------------------------
-- 1c. MINI REPLICA
--------------------------------------------------------------------------------
local function buildMiniReplica(character, cubeModel)
	character.Archivable = true
	local replica = character:Clone()
	replica.Name = "MiniReplica_" .. character.Name

	-- Strip scripts/tools, keep animator (needed for animation passthrough)
	for _, v in ipairs(replica:GetDescendants()) do
		if v:IsA("LuaSourceContainer") or v:IsA("Tool") then
			v:Destroy()
		end
	end

	replica:ScaleTo(SCALE_FACTOR)

	for _, v in ipairs(replica:GetDescendants()) do
		if v:IsA("BasePart") then
			v.Anchored  = true
			v.CanCollide = false
			v.CanQuery  = false
			v.CanTouch  = false
			v.Massless  = true
		elseif v:IsA("Decal") or v:IsA("Texture") then
			-- keep face textures
		end
	end

	replica.Parent = cubeModel
	return replica
end

--------------------------------------------------------------------------------
-- 2. HOLD / DROP SYSTEM
--------------------------------------------------------------------------------
-- We attach the cube to the character's hand using a Motor6D on a temporary
-- "carry" attachment. This makes the cube follow animations naturally and
-- survives physics. The cube is unanchored, massless, and CanCollide=false
-- while held so it doesn't fight the character.

local function getHand(character)
	-- R15 hands
	local right = character:FindFirstChild("RightHand")
	if right then return right end
	-- R6 fallback
	return character:FindFirstChild("Right Arm")
end

local function setCubeAnchored(cubeModel, anchored)
	for _, d in ipairs(cubeModel:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = anchored
			if anchored then
				d.CanCollide = d.Name == "CubeFloor"
			end
		end
	end
end

local function holdCube(player, interactor, data, cubeFloor)
	local char = interactor.Character
	if not char then return end
	local hand = getHand(char)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not hand or not humanoid then return end

	-- Cooldown
	if data.LastPickup and os.clock() - data.LastPickup < PICKUP_COOLDOWN then return end
	data.LastPickup = os.clock()

	-- Create a carry attachment on the hand
	local attach = Instance.new("Attachment")
	attach.Name = "SandboxCarry"
	attach.CFrame = HOLD_OFFSET
	attach.Parent = hand

	-- Motor6D will move the cube with the hand
	local motor = Instance.new("Motor6D")
	motor.Name = "CarryMotor"
	motor.Part0 = hand
	motor.Part1 = cubeFloor
	motor.C0 = attach.CFrame
	motor.C1 = CFrame.new()
	motor.Parent = hand

	-- Unanchor all cube parts, disable collision
	for _, d in ipairs(data.CubeModel:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.Massless = true
		end
	end
	cubeFloor.CanCollide = false

	-- Snap cube to hand immediately
	cubeFloor.CFrame = hand.CFrame * HOLD_OFFSET

	-- Store refs for cleanup
	data.CarryMotor = motor
	data.CarryAttachment = attach
	data.Holder = interactor

	-- Sound
	local sfx = Instance.new("Sound")
	sfx.SoundId = "rbxassetid://6042053626"
	sfx.Volume = 0.4
	sfx.Parent = cubeFloor
	sfx:Play()
	Debris:AddItem(sfx, 2)
end

local function dropCube(data)
	local cubeFloor = data.CubeFloor
	local model = data.CubeModel
	if not cubeFloor or not model then return end

	local motor = data.CarryMotor
	local attach = data.CarryAttachment

	if motor then motor:Destroy() end
	if attach then attach:Destroy() end
	data.CarryMotor = nil
	data.CarryAttachment = nil
	data.Holder = nil

	-- Re-anchor and re-enable collision, drop with a tiny settle
	local hitCFrame = cubeFloor.CFrame
	-- Nudge above ground so it lands cleanly
	local ray = Ray.new(hitCFrame.Position, Vector3.new(0, -20, 0))
	local hitPart, hitPos = Workspace:FindPartOnRayWithIgnoreList(ray, {model})
	if hitPos then
		hitCFrame = CFrame.new(hitPos + Vector3.new(0, CUBE_SIZE * 0.5 + 0.2, 0)) * (hitCFrame - hitCFrame.Position)
	end

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = d.Name == "CubeFloor"
			d.Massless = false
		end
	end
	model:PivotTo(hitCFrame)
end

--------------------------------------------------------------------------------
-- 3. CREATE / CLEANUP
--------------------------------------------------------------------------------
local function cleanupSandbox(data)
	if not data then return end
	if data.CarryMotor then data.CarryMotor:Destroy() end
	if data.CarryAttachment then data.CarryAttachment:Destroy() end
	if data.SandboxBase  then data.SandboxBase:Destroy() end
	if data.CubeModel    then data.CubeModel:Destroy() end
	if data.ExitPart     then data.ExitPart:Destroy() end
end

local function createSandbox(player)
	-- Toggle off
	if activeSandboxes[player] then
		cleanupSandbox(activeSandboxes[player])
		activeSandboxes[player] = nil
		return
	end

	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return end

	local spawnCFrame = character.HumanoidRootPart.CFrame

	-- Pocket baseplate
	local baseModel, baseFloor = buildPocketBaseplate(player)

	-- Exit pad
	local exitPart = makePart({
		Name = "ExitPortal",
		Size = Vector3.new(4, 0.4, 4),
		CFrame = baseFloor.CFrame * CFrame.new(0, 0.7, 10),
		Material = Enum.Material.Neon,
		Color = COLOR_EXIT,
		CanCollide = false,
	})
	exitPart.Parent = Workspace

	local exitPrompt = makePrompt(exitPart, "Exit Sandbox", "Return to Main World", 0.2)

	-- Glass cube in the main world
	local cubeModel, cubeFloor = buildGlassCube(player, spawnCFrame, COLOR_BASE)

	-- Mini replica
	local miniReplica = buildMiniReplica(character, cubeModel)

	-- Prompts
	local liftPrompt  = makePrompt(cubeFloor, "Pick Up / Drop", player.DisplayName .. "'s Cube", 0.15)
	local enterPrompt = makePrompt(cubeFloor, "Jump In",       player.DisplayName .. "'s Sandbox", 0.3)

	local data = {
		SandboxBase = baseModel,
		BaseFloor   = baseFloor,
		CubeFloor   = cubeFloor,
		CubeModel   = cubeModel,
		MiniReplica = miniReplica,
		ExitPart    = exitPart,
	}

	liftPrompt.Triggered:Connect(function(interactor)
		if data.CarryMotor then
			dropCube(data)
		else
			holdCube(player, interactor, data, cubeFloor)
		end
	end)

	enterPrompt.Triggered:Connect(function(interactor)
		local char = interactor.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			char.HumanoidRootPart.CFrame = baseFloor.CFrame * CFrame.new(0, 4, -8)
		end
	end)

	exitPrompt.Triggered:Connect(function(interactor)
		local char = interactor.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			char.HumanoidRootPart.CFrame = cubeFloor.CFrame * CFrame.new(0, 3, 0)
		end
	end)

	-- Teleport creator in
	character.HumanoidRootPart.CFrame = baseFloor.CFrame * CFrame.new(0, 4, -8)

	activeSandboxes[player] = data
end

local function removeSandbox(player)
	if activeSandboxes[player] then
		cleanupSandbox(activeSandboxes[player])
		activeSandboxes[player] = nil
	end
end

--------------------------------------------------------------------------------
-- 4. MOVEMENT MIRRORING
--------------------------------------------------------------------------------
RunService.Heartbeat:Connect(function()
	for player, data in pairs(activeSandboxes) do
		local character = player.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			local hrp     = character.HumanoidRootPart
			local base    = data.BaseFloor
			local floor   = data.CubeFloor
			local replica = data.MiniReplica

			if base and floor and replica and replica.Parent then
				local relCFrame   = base.CFrame:ToObjectSpace(hrp.CFrame)
				local scaledPos   = relCFrame.Position * SCALE_FACTOR
				local rotationOnly = relCFrame - relCFrame.Position

				local _, repSize = replica:GetBoundingBox()
				local liftY = repSize.Y / 2

				local targetCFrame = floor.CFrame
					* CFrame.new(scaledPos.X, scaledPos.Y + liftY, scaledPos.Z)
					* rotationOnly

				replica:PivotTo(targetCFrame)
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- 5. CHAT + CONNECTIONS
--------------------------------------------------------------------------------
local function hookPlayer(player)
	player.Chatted:Connect(function(msg)
		local clean = msg:lower():gsub("%s+", "")
		if clean == "!sandbox" or clean == "/sandbox" then
			createSandbox(player)
		end
	end)

	player.CharacterRemoving:Connect(function()
		removeSandbox(player)
	end)
end

Players.PlayerAdded:Connect(hookPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	hookPlayer(p)
end

Players.PlayerRemoving:Connect(removeSandbox)
