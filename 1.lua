--!strict
-- PocketSandbox
-- A tool that hands you a floating stud baseplate. Click to warp into a
-- matching pocket world 512 studs up. Whatever you do there plays back live
-- on the mini baseplate in your hand — pose, props, everything — via a
-- per-frame CFrame mirror, not animations. No Animator plumbing, no IDs.
--
-- The mini baseplate has no walls. It's just studs floating in the sky.
-- The pocket world has invisible collision walls so you can't walk off.
--
-- Chat:   !sandbox  to receive the tool
-- Click:  warp in / warp out
-- F:      warp out (or walk onto the red pad)

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local PhysicsService= game:GetService("PhysicsService")
local TweenService  = game:GetService("TweenService")
local Debris        = game:GetService("Debris")

--------------------------------------------------------------------------------
-- Tuning
--------------------------------------------------------------------------------
local SCALE             = 1 / 12.5
local SLAB_SIZE         = 32
local SLAB_THICKNESS    = 3
local MINI_SIZE         = SLAB_SIZE * SCALE          -- ~2.56 studs
local POCKET_ALT        = 512
local POCKET_SPACING    = 200
local WALL_HEIGHT       = 24                          -- pocket walls
local PROP_SCAN_PERIOD  = 0.15
local PROP_SCAN_VOLUME  = Vector3.new(SLAB_SIZE + 20, 200, SLAB_SIZE + 20)

local PALETTE = {
    slab     = Color3.fromRGB(102, 106, 114),
    rim      = Color3.fromRGB(196, 202, 218),
    accent   = Color3.fromRGB(120, 190, 255),
    exit     = Color3.fromRGB(255, 90, 90),
}

--------------------------------------------------------------------------------
-- Held parts don't shove the holder. Registering a group is a one-shot.
--------------------------------------------------------------------------------
do
    local ok = pcall(function()
        PhysicsService:RegisterCollisionGroup("HeldProp")
        PhysicsService:CollisionGroupSetCollidable("HeldProp", "Default", false)
    end)
    -- Silently tolerate re-registration if the script reloads.
end

local sandboxes = {}   -- [Tool] = Sandbox

--------------------------------------------------------------------------------
-- Small stuff
--------------------------------------------------------------------------------
local function part(props)
    local p = Instance.new("Part")
    p.Anchored, p.CanCollide = true, true
    p.TopSurface    = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    for k, v in pairs(props) do p[k] = v end
    return p
end

local function weld(a, b)
    local w = Instance.new("WeldConstraint")
    w.Part0, w.Part1, w.Parent = a, b, a
    return w
end

local function sfx(parent, vol, pitch)
    local s = Instance.new("Sound")
    s.SoundId       = "rbxassetid://6042053626"
    s.Volume        = vol or 0.4
    s.PlaybackSpeed = pitch or 1
    s.Parent = parent
    s:Play()
    Debris:AddItem(s, 2)
end

-- A single expanding (or collapsing) neon ring. Used for warp in/out.
local function warpRing(position, fromSize, toSize, duration)
    local ring = part{
        Name = "WarpRing",
        Shape = Enum.PartType.Cylinder,
        Size = Vector3.new(0.08, fromSize, fromSize),
        CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
        Material = Enum.Material.Neon,
        Color = PALETTE.accent,
        Transparency = 0.15,
        CanCollide = false,
        CanQuery = false,
    }
    ring.Parent = workspace

    local t = TweenService:Create(
        ring,
        TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        { Size = Vector3.new(0.08, toSize, toSize), Transparency = 1 }
    )
    t:Play()
    t.Completed:Connect(function() ring:Destroy() end)
end

-- Sparkle column attached to a part. Rate can be dialed per-context.
local function sparkles(anchor, rate)
    local att = Instance.new("Attachment")
    att.Name = "SparkAnchor"
    att.Parent = anchor

    local e = Instance.new("ParticleEmitter")
    e.Texture        = "rbxasset://textures/particles/sparkles_main.dds"
    e.Rate           = rate
    e.Lifetime       = NumberRange.new(1.4, 2.6)
    e.Speed          = NumberRange.new(0.4, 1.2)
    e.Drag           = 1
    e.Rotation       = NumberRange.new(0, 360)
    e.RotSpeed       = NumberRange.new(-25, 25)
    e.SpreadAngle    = Vector2.new(180, 180)
    e.LightEmission  = 1
    e.LightInfluence = 0
    e.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   0),
        NumberSequenceKeypoint.new(0.3, 0.14),
        NumberSequenceKeypoint.new(1,   0),
    })
    e.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   1),
        NumberSequenceKeypoint.new(0.25, 0.35),
        NumberSequenceKeypoint.new(1,   1),
    })
    e.Color = ColorSequence.new(PALETTE.accent)
    e.Parent = att

    return e
end

--------------------------------------------------------------------------------
-- Pocket world: a thick stud slab 512 studs up with a red exit pad and
-- invisible collision walls.
--------------------------------------------------------------------------------
local function buildPocket(origin)
    local model = Instance.new("Model")
    model.Name = "PocketWorld"

    local slab = part{
        Name = "Slab",
        Size = Vector3.new(SLAB_SIZE, SLAB_THICKNESS, SLAB_SIZE),
        Position = origin,
        Material = Enum.Material.Plastic,
        Color = PALETTE.slab,
        TopSurface    = Enum.SurfaceType.Studs,
        BottomSurface = Enum.SurfaceType.Inlet,
    }
    slab.Parent = model

    -- Metal trim around the top edge. Sells it as a designed place, not a tile.
    local half = SLAB_SIZE / 2
    for _, def in ipairs({
        { Vector3.new(SLAB_SIZE, 0.4, 0.5), Vector3.new(0, SLAB_THICKNESS/2 + 0.2,  half - 0.25) },
        { Vector3.new(SLAB_SIZE, 0.4, 0.5), Vector3.new(0, SLAB_THICKNESS/2 + 0.2, -half + 0.25) },
        { Vector3.new(0.5, 0.4, SLAB_SIZE), Vector3.new( half - 0.25, SLAB_THICKNESS/2 + 0.2, 0) },
        { Vector3.new(0.5, 0.4, SLAB_SIZE), Vector3.new(-half + 0.25, SLAB_THICKNESS/2 + 0.2, 0) },
    }) do
        local m = part{
            Size = def[1],
            CFrame = slab.CFrame * CFrame.new(def[2]),
            Material = Enum.Material.Metal,
            Color = PALETTE.rim,
            CanCollide = false,
            CanQuery = false,
        }
        m.Parent = model
    end

    -- Invisible walls. Tall enough that no jump clears them, not so tall they
    -- are noticeable if you fall down into the void below.
    local wallDefs = {
        { Vector3.new(SLAB_SIZE, WALL_HEIGHT, 0.5), Vector3.new(0, WALL_HEIGHT/2,  half) },
        { Vector3.new(SLAB_SIZE, WALL_HEIGHT, 0.5), Vector3.new(0, WALL_HEIGHT/2, -half) },
        { Vector3.new(0.5, WALL_HEIGHT, SLAB_SIZE), Vector3.new( half, WALL_HEIGHT/2, 0) },
        { Vector3.new(0.5, WALL_HEIGHT, SLAB_SIZE), Vector3.new(-half, WALL_HEIGHT/2, 0) },
    }
    for _, def in ipairs(wallDefs) do
        local w = part{
            Name = "InvisibleWall",
            Size = def[1],
            CFrame = slab.CFrame * CFrame.new(def[2]),
            Material = Enum.Material.ForceField,
            Color = Color3.new(0, 0, 0),
            Transparency = 1,
            Reflectance = 0,
            CanCollide = true,
            CanQuery = false,
            CanTouch = true,
            CastShadow = false,
        }
        w.Parent = model
    end

    -- Exit pad, tucked at the back edge.
    local exit = part{
        Name = "ExitPad",
        Shape = Enum.PartType.Cylinder,
        Size = Vector3.new(0.25, 5, 5),
        CFrame = slab.CFrame
            * CFrame.new(0, SLAB_THICKNESS/2 + 0.35, -half + 5)
            * CFrame.Angles(0, 0, math.rad(90)),
        Material = Enum.Material.Neon,
        Color = PALETTE.exit,
        Transparency = 0.15,
        CanCollide = false,
    }
    exit.Parent = model

    local p = Instance.new("ProximityPrompt")
    p.ActionText = "Leave"
    p.ObjectText = "Back to the world"
    p.HoldDuration = 0.2
    p.MaxActivationDistance = 12
    p.RequiresLineOfSight = false
    p.KeyboardKeyCode = Enum.KeyCode.F
    p.GamepadKeyCode  = Enum.KeyCode.ButtonY
    p.Parent = exit

    local light = Instance.new("PointLight")
    light.Brightness, light.Range, light.Color =
        2.2, SLAB_SIZE * 1.2, Color3.fromRGB(180, 210, 255)
    light.Parent = slab

    model.PrimaryPart = slab
    model.Parent = workspace
    return model, slab, exit, p
end

--------------------------------------------------------------------------------
-- Tool: a mini stud baseplate on a grip. Handle is unanchored from birth —
-- the Tool weld system requires it or the handle falls off on equip.
--------------------------------------------------------------------------------
local function buildTool()
    local tool = Instance.new("Tool")
    tool.Name           = "PocketSandbox"
    tool.RequiresHandle = true
    tool.CanBeDropped   = true
    tool.ToolTip        = "Pocket Sandbox"

    local handle = part{
        Name = "Handle",
        Size = Vector3.new(MINI_SIZE, MINI_SIZE * 0.35, MINI_SIZE),
        Material = Enum.Material.Plastic,
        Color = PALETTE.slab,
        TopSurface = Enum.SurfaceType.Studs,
        Anchored = false,
        Massless = true,
        CanCollide = false,
    }
    handle.Parent = tool

    -- Metal rim.
    local h = MINI_SIZE / 2
    local rimT = 0.05
    for _, def in ipairs({
        { Vector3.new(MINI_SIZE, 0.06, rimT), Vector3.new(0, MINI_SIZE*0.175,  h) },
        { Vector3.new(MINI_SIZE, 0.06, rimT), Vector3.new(0, MINI_SIZE*0.175, -h) },
        { Vector3.new(rimT, 0.06, MINI_SIZE), Vector3.new( h, MINI_SIZE*0.175, 0) },
        { Vector3.new(rimT, 0.06, MINI_SIZE), Vector3.new(-h, MINI_SIZE*0.175, 0) },
    }) do
        local m = part{
            Size = def[1],
            CFrame = handle.CFrame * CFrame.new(def[2]),
            Material = Enum.Material.Metal,
            Color = PALETTE.rim,
            CanCollide = false,
            CanQuery = false,
            Massless = true,
            Anchored = false,
        }
        m.Parent = tool
        weld(handle, m)
    end

    -- Neon accent ring on the underside — reads as the "power" of the thing.
    local ring = part{
        Name = "AccentRing",
        Shape = Enum.PartType.Cylinder,
        Size = Vector3.new(0.06, MINI_SIZE * 1.35, MINI_SIZE * 1.35),
        CFrame = handle.CFrame * CFrame.new(0, -MINI_SIZE * 0.18, 0)
            * CFrame.Angles(0, 0, math.rad(90)),
        Material = Enum.Material.Neon,
        Color = PALETTE.accent,
        Transparency = 0.25,
        CanCollide = false,
        CanQuery = false,
        Massless = true,
        Anchored = false,
    }
    ring.Parent = tool
    weld(handle, ring)

    -- Name plate floating above the baseplate.
    local bill = Instance.new("BillboardGui")
    bill.Name = "NameTag"
    bill.Size = UDim2.fromOffset(180, 32)
    bill.StudsOffsetWorldSpace = Vector3.new(0, MINI_SIZE * 0.75, 0)
    bill.AlwaysOnTop = true
    bill.MaxDistance = 60
    bill.Parent = handle

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.Text = ""
    label.TextColor3 = Color3.fromRGB(232, 238, 255)
    label.TextStrokeTransparency = 0.5
    label.TextScaled = true
    label.Parent = bill

    -- Sparkles rising off the baseplate.
    local emit = sparkles(handle, 10)
    emit.Name = "AmbientSparkles"

    -- Grip: the baseplate sits flat in the hand, resting on the palm.
    tool.Grip = CFrame.new(0, 0, 0)
        * CFrame.Angles(math.rad(-15), 0, 0)
        * CFrame.new(0, -MINI_SIZE * 0.2, -MINI_SIZE * 0.4)

    return tool, handle, emit
end

--------------------------------------------------------------------------------
-- Replica of a character. Anchored, unqueryable, no Humanoid. We key parts by
-- name for O(1) mirroring — every R6/R15 part has a unique name.
--------------------------------------------------------------------------------
local function buildReplica(char)
    char.Archivable = true
    local rep = char:Clone()
    rep.Name = "Replica"

    for _, d in ipairs(rep:GetDescendants()) do
        if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript")
        or d:IsA("Humanoid") or d:IsA("Animator") or d:IsA("Tool") then
            d:Destroy()
        end
    end

    rep:ScaleTo(SCALE)

    local map = {}
    for _, d in ipairs(rep:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored   = true
            d.CanCollide = false
            d.CanQuery   = false
            d.CanTouch   = false
            d.Massless   = true
            d.CastShadow = false
            map[d.Name] = d
        end
    end

    return rep, map
end

local function pairReplica(char, replicaMap)
    local pairs_ = {}
    for _, src in ipairs(char:GetDescendants()) do
        if src:IsA("BasePart") then
            local dst = replicaMap[src.Name]
            if dst then
                pairs_[#pairs_ + 1] = { src = src, dst = dst }
            end
        end
    end
    return pairs_
end

local function mirrorPose(pairs_, slab, handle)
    local slabCF = slab.CFrame
    local handleCF = handle.CFrame
    local inv = slabCF:Inverse()

    for i = 1, #pairs_ do
        local pr = pairs_[i]
        local src, dst = pr.src, pr.dst
        if src.Parent and dst.Parent then
            local rel = inv * src.CFrame
            dst.CFrame = handleCF
                * CFrame.new(rel.Position * SCALE)
                * (rel - rel.Position)
        end
    end
end

--------------------------------------------------------------------------------
-- Props: anything unanchored that ends up in the pocket volume mirrors onto
-- the mini baseplate. Cloned once, scaled once, then just repositioned.
--------------------------------------------------------------------------------
local function scanProps(data, char)
    local slabCF = data.slab.CFrame
    local boxCF  = CFrame.new(slabCF.Position + Vector3.new(0, 80, 0))

    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {
        data.model,
        data.replicaFolder,
        char,
    }

    local hits = workspace:GetPartBoundsInBox(boxCF, PROP_SCAN_VOLUME, params)
    local live = {}

    for _, src in ipairs(hits) do
        if src.Anchored then continue end
        if src.CollisionGroup == "HeldProp" then continue end

        live[src] = true
        local mirror = data.mirrors[src]
        if not mirror or not mirror.Parent then
            local ok, clone = pcall(function() return src:Clone() end)
            if not ok or not clone then continue end

            local wrap = Instance.new("Model")
            clone.Name = "Prop"
            clone.Anchored = true
            clone.CanCollide = false
            clone.CanQuery = false
            clone.CanTouch = false
            clone.Massless = true
            clone.CastShadow = false
            clone.CollisionGroup = "Default"
            clone.Parent = wrap

            -- Scale the model so multi-part props keep their proportions.
            pcall(function() wrap:ScaleTo(SCALE) end)

            wrap.Parent = data.replicaFolder
            data.mirrors[src] = wrap
            mirror = wrap
        end

        local rel = slabCF:ToObjectSpace(src.CFrame)
        mirror:PivotTo(
            data.handle.CFrame
            * CFrame.new(rel.Position * SCALE)
            * (rel - rel.Position)
        )
    end

    for src, m in pairs(data.mirrors) do
        if not live[src] or not src.Parent then
            m:Destroy()
            data.mirrors[src] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- Sandbox lifecycle
--------------------------------------------------------------------------------
local function destroySandbox(tool)
    local data = sandboxes[tool]
    if not data then return end
    sandboxes[tool] = nil

    if data.replicaFolder then data.replicaFolder:Destroy() end
    if data.model         then data.model:Destroy()         end
    -- Handle is owned by the tool; it goes with the tool.
end

local function createSandbox(player)
    -- One tool per player.
    for _, c in ipairs(player.Backpack:GetChildren()) do
        if c:IsA("Tool") and c.Name == "PocketSandbox" then return end
    end
    if player.Character then
        for _, c in ipairs(player.Character:GetChildren()) do
            if c:IsA("Tool") and c.Name == "PocketSandbox" then return end
        end
    end

    local slot   = (player.UserId % 8)
    local origin = Vector3.new(slot * POCKET_SPACING, POCKET_ALT, 0)

    local model, slab, exit, exitPrompt = buildPocket(origin)
    local tool, handle, ambient = buildTool()

    handle:FindFirstChild("NameTag").Label.Text = player.DisplayName .. "'s Sandbox"

    local replicaFolder = Instance.new("Folder")
    replicaFolder.Name = "Mirror_" .. player.Name

    local data = {
        model         = model,
        slab          = slab,
        exit          = exit,
        exitPrompt    = exitPrompt,
        handle        = handle,
        ambient       = ambient,
        replicaFolder = replicaFolder,
        replica       = nil,
        replicaMap    = nil,
        replicaPairs  = nil,
        replicaChar   = nil,
        mirrors       = {},
        lastScan      = 0,
        returnCFrame  = nil,
    }
    sandboxes[tool] = data

    -- ── Equip / unequip ─────────────────────────────────────────────────────
    tool.Equipped:Connect(function()
        local char = tool.Parent
        if not char or not char:IsA("Model") then return end
        if not Players:GetPlayerFromCharacter(char) then return end

        if data.replica then data.replica:Destroy() end
        data.replicaFolder:ClearAllChildren()
        data.mirrors = {}

        local rep, map = buildReplica(char)
        rep.Parent = replicaFolder
        data.replica      = rep
        data.replicaMap   = map
        data.replicaPairs = pairReplica(char, map)
        data.replicaChar  = char

        replicaFolder.Parent = workspace
        ambient.Rate = 10
    end)

    tool.Unequipped:Connect(function()
        replicaFolder.Parent = nil
        ambient.Rate = 0
        data.replicaPairs = nil
        data.replicaChar = nil
    end)

    -- ── Click: warp in / warp out ───────────────────────────────────────────
    tool.Activated:Connect(function()
        local holder = Players:GetPlayerFromCharacter(tool.Parent)
        if not holder then return end

        local char = holder.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local inside = hrp.Position.Y > POCKET_ALT - 120

        if inside then
            local back = data.returnCFrame or (slab.CFrame * CFrame.new(0, 5, 0) - slab.CFrame.Position)
            warpRing(hrp.Position, 3, 14, 0.5)
            sfx(handle, 0.4, 0.75)
            hrp.CFrame = back
            task.delay(0.05, function()
                warpRing(hrp.Position, 14, 3, 0.5)
            end)
        else
            data.returnCFrame = hrp.CFrame
            warpRing(hrp.Position, 3, 14, 0.5)
            sfx(handle, 0.4, 1.3)
            hrp.CFrame = slab.CFrame * CFrame.new(0, 5, 0)
            task.delay(0.05, function()
                warpRing(hrp.Position, 14, 3, 0.5)
            end)
        end
    end)

    exitPrompt.Triggered:Connect(function(actor)
        local char = actor.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        warpRing(hrp.Position, 3, 14, 0.5)
        hrp.CFrame = data.returnCFrame or CFrame.new(0, 12, 0)
        sfx(slab, 0.3, 0.8)
    end)

    tool.Destroying:Connect(function()
        destroySandbox(tool)
    end)

    tool.Parent = player.Backpack
end

--------------------------------------------------------------------------------
-- Per-frame mirror loop
--------------------------------------------------------------------------------
RunService.Heartbeat:Connect(function()
    local now = os.clock()

    for tool, data in pairs(sandboxes) do
        local char = tool.Parent
        local equipped = char and char:IsA("Model")
            and Players:GetPlayerFromCharacter(char) ~= nil

        if not equipped or not data.replicaPairs then
            continue
        end

        mirrorPose(data.replicaPairs, data.slab, data.handle)

        if now - data.lastScan > PROP_SCAN_PERIOD then
            data.lastScan = now
            local ok, err = pcall(scanProps, data, char)
            if not ok then warn("[PocketSandbox] scanProps:", err) end
        end
    end
end)

--------------------------------------------------------------------------------
-- Chat hook
--------------------------------------------------------------------------------
local function onChatted(player, msg)
    local m = msg:lower():gsub("%s+", "")
    if m == "!sandbox" or m == "/sandbox" then
        createSandbox(player)
    end
end

Players.PlayerAdded:Connect(function(plr)
    plr.Chatted:Connect(function(m) onChatted(plr, m) end)
end)
for _, plr in ipairs(Players:GetPlayers()) do
    plr.Chatted:Connect(function(m) onChatted(plr, m) end)
end
