-- Pocket sandbox. Say !sandbox to toggle. Each player gets a floating
-- baseplate with a tiny glass box on it that holds a scaled-down copy of
-- them. Press E near the box to physically grab it — it'll spring into
-- your hand and follow the arm animation. Press E again to drop or throw.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Physics    = game:GetService("PhysicsService")

local SCALE     = 0.08
local BASE_SIZE = 32
local CUBE_SIZE = BASE_SIZE * SCALE
local POCKET_Y  = 512

-- Cube's resting pose in the hand. Tweak if you want it held differently.
local GRIP = CFrame.new(0, -0.6, -0.8) * CFrame.Angles(math.rad(-30), 0, 0)

local HOLD_FORCE = 15000
local HOLD_RESP  = 40

do
    local ok = pcall(function()
        Physics:RegisterCollisionGroup("SandboxHeld")
    end)
    if ok then
        Physics:CollisionGroupSetCollidable("SandboxHeld", "Default", false)
    end
end

local sandboxes = {}
local held = {}   -- [Model] -> state

-- ── construction helpers ────────────────────────────────────────────────────

local function part(props)
    local p = Instance.new("Part")
    p.Anchored, p.CanCollide = true, true
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    for k, v in pairs(props) do p[k] = v end
    return p
end

local function weld(a, b)
    local w = Instance.new("WeldConstraint")
    w.Part0, w.Part1 = a, b
    w.Parent = a
end

local function prompt(anchor, action, object, hold)
    local p = Instance.new("ProximityPrompt")
    p.ActionText = action
    p.ObjectText = object
    p.HoldDuration = hold or 0.15
    p.MaxActivationDistance = 10
    p.RequiresLineOfSight = false
    p.Parent = anchor
    return p
end

local function ping(parent, id, vol, pitch)
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://" .. id
    s.Volume = vol or 0.4
    s.PlaybackSpeed = pitch or 1
    s.Parent = parent
    s:Play()
    task.delay(2, function()
        if s.Parent then s:Destroy() end
    end)
end

-- ── pocket dimension ────────────────────────────────────────────────────────

local function buildPocket(plr)
    local origin = Vector3.new((plr.UserId % 8) * 120, POCKET_Y, 0)

    local model = Instance.new("Model")
    model.Name = "Pocket_" .. plr.Name

    local floor = part{
        Name = "Floor",
        Size = Vector3.new(BASE_SIZE, 1, BASE_SIZE),
        Position = origin,
        Material = Enum.Material.Concrete,
        Color = Color3.fromRGB(36, 38, 46),
    }
    floor.Parent = model

    local tile = Instance.new("Texture")
    tile.Face = Enum.NormalId.Top
    tile.Texture = "rbxassetid://6372755229"
    tile.StudsPerTileU = 4
    tile.StudsPerTileV = 4
    tile.Transparency = 0.2
    tile.Parent = floor

    local half = BASE_SIZE / 2
    local rimDefs = {
        { Vector3.new(BASE_SIZE + 0.8, 1.5, 0.8), Vector3.new(0, 0.25,  half) },
        { Vector3.new(BASE_SIZE + 0.8, 1.5, 0.8), Vector3.new(0, 0.25, -half) },
        { Vector3.new(0.8, 1.5, BASE_SIZE + 0.8), Vector3.new( half, 0.25, 0) },
        { Vector3.new(0.8, 1.5, BASE_SIZE + 0.8), Vector3.new(-half, 0.25, 0) },
    }
    for _, r in ipairs(rimDefs) do
        local b = part{
            Size = r[1],
            CFrame = floor.CFrame * CFrame.new(r[2]),
            Material = Enum.Material.Metal,
            Color = Color3.fromRGB(58, 62, 74),
        }
        b.Parent = model
    end

    local glow = Instance.new("PointLight")
    glow.Brightness = 2
    glow.Range = BASE_SIZE
    glow.Color = Color3.fromRGB(140, 180, 255)
    glow.Parent = floor

    local sign = Instance.new("BillboardGui")
    sign.Size = UDim2.fromOffset(220, 40)
    sign.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
    sign.AlwaysOnTop = true
    sign.Parent = floor

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.Text = plr.DisplayName .. "'s Sandbox"
    label.TextColor3 = Color3.fromRGB(230, 235, 255)
    label.TextStrokeTransparency = 0.5
    label.TextScaled = true
    label.Parent = sign

    model.PrimaryPart = floor
    model.Parent = workspace
    return model, floor
end

-- ── glass cube ──────────────────────────────────────────────────────────────

local function buildCube(plr, cf)
    local model = Instance.new("Model")
    model.Name = "Cube_" .. plr.Name

    local base = part{
        Name = "Base",
        Size = Vector3.new(CUBE_SIZE, 0.15, CUBE_SIZE),
        CFrame = cf,
        Material = Enum.Material.SmoothPlastic,
        Color = Color3.fromRGB(52, 56, 68),
    }
    base.Parent = model
    model.PrimaryPart = base

    local h = CUBE_SIZE / 2
    local tint = Color3.fromRGB(170, 215, 255)
    local panels = {
        { Vector3.new(CUBE_SIZE, CUBE_SIZE, 0.06), Vector3.new(0, h,  h) },
        { Vector3.new(CUBE_SIZE, CUBE_SIZE, 0.06), Vector3.new(0, h, -h) },
        { Vector3.new(0.06, CUBE_SIZE, CUBE_SIZE), Vector3.new( h, h, 0) },
        { Vector3.new(0.06, CUBE_SIZE, CUBE_SIZE), Vector3.new(-h, h, 0) },
        { Vector3.new(CUBE_SIZE, 0.06, CUBE_SIZE), Vector3.new(0, CUBE_SIZE, 0) },
    }
    for _, p in ipairs(panels) do
        local g = part{
            Size = p[1],
            CFrame = base.CFrame * CFrame.new(p[2]),
            Material = Enum.Material.Glass,
            Color = tint,
            Transparency = 0.82,
            Reflectance = 0.35,
            CanCollide = true,
        }
        g.Parent = model
        weld(base, g)
    end

    for _, x in ipairs({-1, 1}) do
        for _, z in ipairs({-1, 1}) do
            local post = part{
                Size = Vector3.new(0.05, CUBE_SIZE, 0.05),
                CFrame = base.CFrame * CFrame.new(x * h, h, z * h),
                Material = Enum.Material.Neon,
                Color = tint,
                Transparency = 0.25,
                CanCollide = false,
            }
            post.Parent = model
            weld(base, post)
        end
    end

    local glow = Instance.new("PointLight")
    glow.Brightness = 1.2
    glow.Range = 8
    glow.Color = tint
    glow.Parent = base

    model.Parent = workspace
    return model, base
end

-- ── scaled replica ──────────────────────────────────────────────────────────

local function buildReplica(character, parent)
    character.Archivable = true
    local rep = character:Clone()
    rep.Name = "Replica"

    for _, d in ipairs(rep:GetDescendants()) do
        if d:IsA("BaseScript") or d:IsA("Tool") then
            d:Destroy()
        end
    end

    rep:ScaleTo(SCALE)

    for _, d in ipairs(rep:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored  = true
            d.CanCollide = false
            d.CanQuery  = false
            d.CanTouch  = false
            d.Massless  = true
        end
    end

    rep.Parent = parent
    return rep
end

-- ── grab / release ──────────────────────────────────────────────────────────

local function findHand(char)
    return char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
end

local function setPhysics(cube, anchored, massless, collide, group)
    for _, d in ipairs(cube:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored  = anchored
            d.Massless  = massless
            d.CollisionGroup = group
            if d.Name == "Base" or d.Material == Enum.Material.Glass then
                d.CanCollide = collide
            else
                d.CanCollide = false
            end
        end
    end
end

local function grab(plr, cube)
    if held[cube] then return end

    local char = plr.Character
    if not char then return end
    local hand = findHand(char)
    if not hand then return end

    setPhysics(cube, false, true, false, "SandboxHeld")

    local handGrip = Instance.new("Attachment")
    handGrip.Name = "Grip"
    handGrip.CFrame = GRIP
    handGrip.Parent = hand

    local cubeGrip = Instance.new("Attachment")
    cubeGrip.Name = "Grip"
    cubeGrip.Parent = cube.PrimaryPart

    local ap = Instance.new("AlignPosition")
    ap.Attachment0 = cubeGrip
    ap.Attachment1 = handGrip
    ap.Mode = Enum.PositionAlignmentMode.TwoAttachment
    ap.Responsiveness = HOLD_RESP
    ap.MaxForce = HOLD_FORCE
    ap.Parent = cube.PrimaryPart

    local ao = Instance.new("AlignOrientation")
    ao.Attachment0 = cubeGrip
    ao.Attachment1 = handGrip
    ao.Mode = Enum.OrientationAlignmentMode.TwoAttachment
    ao.Responsiveness = HOLD_RESP
    ao.MaxTorque = HOLD_FORCE * 3
    ao.Parent = cube.PrimaryPart

    local hi = Instance.new("Highlight")
    hi.FillColor = Color3.fromRGB(170, 215, 255)
    hi.FillTransparency = 0.85
    hi.OutlineTransparency = 1
    hi.Parent = cube

    held[cube] = {
        ap = ap, ao = ao,
        handGrip = handGrip, cubeGrip = cubeGrip,
        highlight = hi, hand = hand, holder = plr,
    }

    ping(cube.PrimaryPart, "6042053626", 0.35, 1)
end

local function release(cube)
    local state = held[cube]
    if not state then return end

    local base = cube.PrimaryPart
    local handVel = state.hand.AssemblyLinearVelocity

    state.ap:Destroy()
    state.ao:Destroy()
    state.handGrip:Destroy()
    state.cubeGrip:Destroy()
    state.highlight:Destroy()

    setPhysics(cube, false, false, true, "Default")

    base.AssemblyLinearVelocity = handVel * 1.2
    base.AssemblyAngularVelocity = Vector3.new(
        (math.random() - 0.5) * 6,
        (math.random() - 0.5) * 6,
        (math.random() - 0.5) * 6
    )

    held[cube] = nil
    ping(base, "6042053626", 0.3, 0.85)
end

-- ── create / destroy ────────────────────────────────────────────────────────

local function destroy(plr)
    local s = sandboxes[plr]
    if not s then return end

    if held[s.cube] then
        local st = held[s.cube]
        st.ap:Destroy()
        st.ao:Destroy()
        st.handGrip:Destroy()
        st.cubeGrip:Destroy()
        st.highlight:Destroy()
        held[s.cube] = nil
    end

    s.pocket:Destroy()
    s.cube:Destroy()
    s.exit:Destroy()
    sandboxes[plr] = nil
end

local function create(plr)
    if sandboxes[plr] then
        destroy(plr)
        return
    end

    local char = plr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local pocket, pocketFloor = buildPocket(plr)
    local cube, cubeBase = buildCube(plr, hrp.CFrame * CFrame.new(0, 3, 0))
    local replica = buildReplica(char, cube)

    local exit = part{
        Name = "Exit",
        Shape = Enum.PartType.Cylinder,
        Size = Vector3.new(0.25, 5, 5),
        CFrame = pocketFloor.CFrame * CFrame.new(0, 0.65, -10) * CFrame.Angles(0, 0, math.rad(90)),
        Material = Enum.Material.Neon,
        Color = Color3.fromRGB(255, 90, 90),
        Transparency = 0.2,
        CanCollide = false,
    }
    exit.Parent = workspace

    local exitPrompt  = prompt(exit, "Leave", "Back to the world", 0.2)
    local grabPrompt  = prompt(cubeBase, "Grab",  plr.DisplayName .. "'s Box", 0.15)
    local enterPrompt = prompt(cubeBase, "Enter", plr.DisplayName .. "'s Sandbox", 0.3)

    grabPrompt.KeyboardKeyCode  = Enum.KeyCode.E
    grabPrompt.GamepadKeyCode   = Enum.KeyCode.ButtonX
    enterPrompt.KeyboardKeyCode = Enum.KeyCode.F
    enterPrompt.GamepadKeyCode  = Enum.KeyCode.ButtonY

    sandboxes[plr] = {
        pocket = pocket, pocketFloor = pocketFloor,
        cube = cube, cubeBase = cubeBase,
        replica = replica, exit = exit,
    }

    grabPrompt.Triggered:Connect(function(actor)
        if held[cube] then
            if held[cube].holder == actor then release(cube) end
        else
            grab(actor, cube)
        end
    end)

    enterPrompt.Triggered:Connect(function(actor)
        local c = actor.Character
        local root = c and c:FindFirstChild("HumanoidRootPart")
        if root then
            root.CFrame = pocketFloor.CFrame * CFrame.new(0, 4, 0)
            ping(pocketFloor, "6042053626", 0.3, 1.3)
        end
    end)

    exitPrompt.Triggered:Connect(function(actor)
        local c = actor.Character
        local root = c and c:FindFirstChild("HumanoidRootPart")
        if root then
            root.CFrame = cubeBase.CFrame * CFrame.new(0, 3, 0)
            ping(cubeBase, "6042053626", 0.3, 0.8)
        end
    end)

    hrp.CFrame = pocketFloor.CFrame * CFrame.new(0, 4, 0)
end

-- ── replica mirroring ───────────────────────────────────────────────────────

RunService.Heartbeat:Connect(function()
    for plr, s in pairs(sandboxes) do
        local char = plr.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        if not s.replica.Parent then continue end

        local rel = s.pocketFloor.CFrame:ToObjectSpace(hrp.CFrame)
        local scaledPos = rel.Position * SCALE
        local rotation = rel - rel.Position
        local _, size = s.replica:GetBoundingBox()

        s.replica:PivotTo(
            s.cubeBase.CFrame
            * CFrame.new(scaledPos.X, scaledPos.Y + size.Y * 0.5, scaledPos.Z)
            * rotation
        )
    end
end)

-- ── wiring ──────────────────────────────────────────────────────────────────

local function hook(plr)
    plr.Chatted:Connect(function(msg)
        local m = msg:lower():gsub("%s+", "")
        if m == "!sandbox" or m == "/sandbox" then
            create(plr)
        end
    end)

    plr.CharacterRemoving:Connect(function()
        destroy(plr)
    end)
end

Players.PlayerAdded:Connect(hook)
for _, p in ipairs(Players:GetPlayers()) do hook(p) end
Players.PlayerRemoving:Connect(destroy)
