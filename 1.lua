-- Pocket Sandbox — solid grounded baseplate, invisible "sky" walls on the
-- mini cube, physical grab. !sandbox to toggle. E to grab, F to enter.
--
-- The mini cube has no visible glass. Its walls are collision-only, so from
-- outside you just see a floating solid baseplate with a tiny you standing
-- on it against the open sky. The walls are only there to keep the replica
-- (and anything you throw in) from falling off the edge.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting   = game:GetService("Lighting")
local Physics    = game:GetService("PhysicsService")

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------
local SCALE      = 0.08
local BASE_SIZE  = 32
local CUBE_SIZE  = BASE_SIZE * SCALE    -- ~2.56 studs
local POCKET_Y   = 512
local POCKET_GAP = 120

local GRIP = CFrame.new(0, -0.6, -0.8) * CFrame.Angles(math.rad(-30), 0, 0)
local HOLD_FORCE, HOLD_RESP = 15000, 40

--------------------------------------------------------------------------------
-- COLLISION GROUP
--------------------------------------------------------------------------------
do
    pcall(function()
        Physics:RegisterCollisionGroup("SandboxHeld")
        Physics:CollisionGroupSetCollidable("SandboxHeld", "Default", false)
    end)
end

local sandboxes = {}
local held = {}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
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

local function prompt(anchor, action, object, hold, key, padKey)
    local p = Instance.new("ProximityPrompt")
    p.ActionText = action
    p.ObjectText = object
    p.HoldDuration = hold or 0.15
    p.MaxActivationDistance = 12
    p.RequiresLineOfSight = false
    if key    then p.KeyboardKeyCode = key    end
    if padKey then p.GamepadKeyCode  = padKey end
    p.Parent = anchor
    return p
end

local function ping(parent, vol, pitch)
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://6042053626"
    s.Volume = vol or 0.4
    s.PlaybackSpeed = pitch or 1
    s.Parent = parent
    s:Play()
    task.delay(2, function()
        if s.Parent then s:Destroy() end
    end)
end

--------------------------------------------------------------------------------
-- POCKET BASEPLATE — solid, grounded slab with a rim, corner posts and a
-- subtle inner inlay so it reads as a real place, not a floating tile.
--------------------------------------------------------------------------------
local function buildPocket(plr)
    local origin = Vector3.new((plr.UserId % 8) * POCKET_GAP, POCKET_Y, 0)

    local model = Instance.new("Model")
    model.Name = "Pocket_" .. plr.Name

    -- Solid slab. 3 studs thick so it reads as a real baseplate edge-on.
    local slab = part{
        Name = "Slab",
        Size = Vector3.new(BASE_SIZE, 3, BASE_SIZE),
        Position = origin,
        Material = Enum.Material.Concrete,
        Color = Color3.fromRGB(28, 30, 36),
    }
    slab.Parent = model

    -- Inner "inlay" surface, slightly inset, in a lighter tone.
    local inlaySize = BASE_SIZE - 3
    local inlay = part{
        Name = "Inlay",
        Size = Vector3.new(inlaySize, 0.4, inlaySize),
        CFrame = slab.CFrame * CFrame.new(0, 1.5, 0),
        Material = Enum.Material.Slate,
        Color = Color3.fromRGB(52, 56, 66),
        CanCollide = false,
    }
    inlay.Parent = model

    -- Grid detail on the inlay.
    local grid = Instance.new("Texture")
    grid.Face = Enum.NormalId.Top
    grid.Texture = "rbxassetid://6372755229"
    grid.StudsPerTileU, grid.StudsPerTileV = 3, 3
    grid.Transparency = 0.35
    grid.Color3 = Color3.fromRGB(80, 88, 104)
    grid.Parent = inlay

    -- Metal trim running along all four edges of the inlay.
    local trimT = 0.6
    local t = inlaySize / 2
    for _, def in ipairs({
        { Vector3.new(inlaySize + trimT, 0.5, trimT), Vector3.new(0, 0.2,  t) },
        { Vector3.new(inlaySize + trimT, 0.5, trimT), Vector3.new(0, 0.2, -t) },
        { Vector3.new(trimT, 0.5, inlaySize + trimT), Vector3.new( t, 0.2, 0) },
        { Vector3.new(trimT, 0.5, inlaySize + trimT), Vector3.new(-t, 0.2, 0) },
    }) do
        local m = part{
            Size = def[1],
            CFrame = inlay.CFrame * CFrame.new(def[2]),
            Material = Enum.Material.Metal,
            Color = Color3.fromRGB(140, 148, 168),
            CanCollide = false,
        }
        m.Parent = model
    end

    -- Corner posts rising up from the slab's corners.
    local half = BASE_SIZE / 2 - 0.6
    for _, sx in ipairs({-1, 1}) do
        for _, sz in ipairs({-1, 1}) do
            local post = part{
                Shape = Enum.PartType.Cylinder,
                Size = Vector3.new(3.5, 0.7, 0.7),
                CFrame = slab.CFrame * CFrame.new(sx * half, 2.75, sz * half)
                    * CFrame.Angles(0, 0, math.rad(90)),
                Material = Enum.Material.Metal,
                Color = Color3.fromRGB(90, 96, 112),
                CanCollide = false,
            }
            post.Parent = model

            local cap = part{
                Shape = Enum.PartType.Ball,
                Size = Vector3.new(0.55, 0.55, 0.55),
                CFrame = post.CFrame * CFrame.new(0, 2, 0),
                Material = Enum.Material.Neon,
                Color = Color3.fromRGB(150, 200, 255),
                CanCollide = false,
            }
            cap.Parent = model
        end
    end

    -- Soft fill light so the slab isn't flat grey.
    local light = Instance.new("PointLight")
    light.Brightness = 2.5
    light.Range = BASE_SIZE
    light.Color = Color3.fromRGB(170, 200, 255)
    light.Parent = slab

    -- Name tag floating above.
    local bill = Instance.new("BillboardGui")
    bill.Size = UDim2.fromOffset(240, 44)
    bill.StudsOffsetWorldSpace = Vector3.new(0, 8, 0)
    bill.AlwaysOnTop = true
    bill.Parent = slab

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.Text = plr.DisplayName .. "'s Sandbox"
    label.TextColor3 = Color3.fromRGB(232, 238, 255)
    label.TextStrokeTransparency = 0.55
    label.TextScaled = true
    label.Parent = bill

    model.PrimaryPart = slab
    model.Parent = workspace
    return model, slab
end

--------------------------------------------------------------------------------
-- MINI CUBE — invisible sky walls.
-- Only the baseplate is visible. The five "walls" (4 sides + ceiling) are
-- collision volumes with Transparency = 1, CanQuery = false, so from every
-- angle the space around the baseplate is just open sky. They still stop
-- the replica and any thrown props from leaving the volume.
--------------------------------------------------------------------------------
local function buildCube(plr, cf)
    local model = Instance.new("Model")
    model.Name = "Cube_" .. plr.Name

    local base = part{
        Name = "Base",
        Size = Vector3.new(CUBE_SIZE, 0.18, CUBE_SIZE),
        CFrame = cf,
        Material = Enum.Material.Slate,
        Color = Color3.fromRGB(48, 52, 62),
    }
    base.Parent = model
    model.PrimaryPart = base

    -- Top texture: same grid as the pocket slab so it reads as a mini version.
    local grid = Instance.new("Texture")
    grid.Face = Enum.NormalId.Top
    grid.Texture = "rbxassetid://6372755229"
    grid.StudsPerTileU, grid.StudsPerTileV = 0.4, 0.4
    grid.Transparency = 0.4
    grid.Color3 = Color3.fromRGB(90, 98, 116)
    grid.Parent = base

    -- Metal rim on the mini baseplate.
    local h = CUBE_SIZE / 2
    local rimT = 0.05
    for _, def in ipairs({
        { Vector3.new(CUBE_SIZE, 0.08, rimT), Vector3.new(0, 0.1,  h) },
        { Vector3.new(CUBE_SIZE, 0.08, rimT), Vector3.new(0, 0.1, -h) },
        { Vector3.new(rimT, 0.08, CUBE_SIZE), Vector3.new( h, 0.1, 0) },
        { Vector3.new(rimT, 0.08, CUBE_SIZE), Vector3.new(-h, 0.1, 0) },
    }) do
        local m = part{
            Size = def[1],
            CFrame = base.CFrame * CFrame.new(def[2]),
            Material = Enum.Material.Metal,
            Color = Color3.fromRGB(150, 158, 178),
            CanCollide = false,
        }
        m.Parent = model
        weld(base, m)
    end

    -- Invisible collision walls (sky). Glass material with full transparency
    -- still catches a faint edge highlight in most lighting setups — we use
    -- ForceField with fully transparent Color so nothing renders at all.
    local wallH = CUBE_SIZE
    local wallDefs = {
        { Vector3.new(CUBE_SIZE, wallH, 0.08), Vector3.new(0, wallH/2,  h) },
        { Vector3.new(CUBE_SIZE, wallH, 0.08), Vector3.new(0, wallH/2, -h) },
        { Vector3.new(0.08, wallH, CUBE_SIZE), Vector3.new( h, wallH/2, 0) },
        { Vector3.new(0.08, wallH, CUBE_SIZE), Vector3.new(-h, wallH/2, 0) },
        { Vector3.new(CUBE_SIZE, 0.08, CUBE_SIZE), Vector3.new(0, wallH, 0) },
    }
    for _, def in ipairs(wallDefs) do
        local w = part{
            Name = "SkyWall",
            Size = def[1],
            CFrame = base.CFrame * CFrame.new(def[2]),
            Material = Enum.Material.ForceField,
            Color = Color3.fromRGB(0, 0, 0),
            Transparency = 1,
            Reflectance = 0,
            CanCollide = true,
            CanQuery = false,
            CanTouch = true,
            CastShadow = false,
        }
        w.Parent = model
        weld(base, w)
    end

    -- Faint floor glow around the baseplate edge, so the "where do I stand"
    -- question is answered without visible walls.
    local glow = Instance.new("PointLight")
    glow.Brightness = 1.4
    glow.Range = CUBE_SIZE * 3
    glow.Color = Color3.fromRGB(160, 200, 255)
    glow.Parent = base

    model.Parent = workspace
    return model, base
end

--------------------------------------------------------------------------------
-- REPLICA
--------------------------------------------------------------------------------
local function buildReplica(character, parent)
    character.Archivable = true
    local rep = character:Clone()
    rep.Name = "Replica"

    for _, d in ipairs(rep:GetDescendants()) do
        if d:IsA("BaseScript") or d:IsA("Tool") then d:Destroy() end
    end

    rep:ScaleTo(SCALE)

    for _, d in ipairs(rep:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored, d.CanCollide = true, false
            d.CanQuery, d.CanTouch  = false, false
            d.Massless              = true
            d.CastShadow            = false
        end
    end

    rep.Parent = parent
    return rep
end

--------------------------------------------------------------------------------
-- GRAB / RELEASE
--------------------------------------------------------------------------------
local function findHand(char)
    return char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
end

local function setPhysics(cube, anchored, massless, collide, group)
    for _, d in ipairs(cube:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored        = anchored
            d.Massless        = massless
            d.CollisionGroup  = group
            d.CanCollide      = (d.Name == "Base") and collide or false
        end
    end
end

local function grab(plr, cube)
    if held[cube] then return end
    local char = plr.Character
    local hand = char and findHand(char)
    if not hand then return end

    setPhysics(cube, false, true, false, "SandboxHeld")

    local handGrip = Instance.new("Attachment")
    handGrip.Name, handGrip.CFrame, handGrip.Parent = "Grip", GRIP, hand

    local cubeGrip = Instance.new("Attachment")
    cubeGrip.Name, cubeGrip.Parent = "Grip", cube.PrimaryPart

    local ap = Instance.new("AlignPosition")
    ap.Attachment0, ap.Attachment1 = cubeGrip, handGrip
    ap.Mode            = Enum.PositionAlignmentMode.TwoAttachment
    ap.Responsiveness  = HOLD_RESP
    ap.MaxForce        = HOLD_FORCE
    ap.Parent          = cube.PrimaryPart

    local ao = Instance.new("AlignOrientation")
    ao.Attachment0, ao.Attachment1 = cubeGrip, handGrip
    ao.Mode            = Enum.OrientationAlignmentMode.TwoAttachment
    ao.Responsiveness  = HOLD_RESP
    ao.MaxTorque       = HOLD_FORCE * 3
    ao.Parent          = cube.PrimaryPart

    local hi = Instance.new("Highlight")
    hi.FillColor          = Color3.fromRGB(160, 200, 255)
    hi.FillTransparency   = 0.88
    hi.OutlineTransparency = 1
    hi.Parent = cube

    held[cube] = {
        ap = ap, ao = ao,
        handGrip = handGrip, cubeGrip = cubeGrip,
        highlight = hi, hand = hand, holder = plr,
    }

    ping(cube.PrimaryPart, 0.35, 1)
end

local function release(cube)
    local s = held[cube]
    if not s then return end

    local base = cube.PrimaryPart
    local v = s.hand.AssemblyLinearVelocity

    s.ap:Destroy(); s.ao:Destroy()
    s.handGrip:Destroy(); s.cubeGrip:Destroy()
    s.highlight:Destroy()

    setPhysics(cube, false, false, true, "Default")

    base.AssemblyLinearVelocity = v * 1.2
    base.AssemblyAngularVelocity = Vector3.new(
        (math.random() - 0.5) * 6,
        (math.random() - 0.5) * 6,
        (math.random() - 0.5) * 6
    )

    held[cube] = nil
    ping(base, 0.3, 0.85)
end

--------------------------------------------------------------------------------
-- CREATE / DESTROY
--------------------------------------------------------------------------------
local function destroy(plr)
    local s = sandboxes[plr]
    if not s then return end
    if held[s.cube] then
        local h = held[s.cube]
        h.ap:Destroy(); h.ao:Destroy()
        h.handGrip:Destroy(); h.cubeGrip:Destroy()
        h.highlight:Destroy()
        held[s.cube] = nil
    end
    s.pocket:Destroy()
    s.cube:Destroy()
    s.exit:Destroy()
    sandboxes[plr] = nil
end

local function create(plr)
    if sandboxes[plr] then return destroy(plr) end

    local char = plr.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local pocket, pocketSlab = buildPocket(plr)
    local cube, cubeBase      = buildCube(plr, hrp.CFrame * CFrame.new(0, 3.5, 0))
    local replica             = buildReplica(char, cube)

    -- Exit pad sits on top of the slab, near the back edge.
    local exit = part{
        Name = "Exit",
        Shape = Enum.PartType.Cylinder,
        Size = Vector3.new(0.25, 5, 5),
        CFrame = pocketSlab.CFrame
            * CFrame.new(0, 1.85, -BASE_SIZE/2 + 5)
            * CFrame.Angles(0, 0, math.rad(90)),
        Material = Enum.Material.Neon,
        Color = Color3.fromRGB(255, 100, 100),
        Transparency = 0.15,
        CanCollide = false,
    }
    exit.Parent = workspace

    local exitPrompt  = prompt(exit,     "Leave", "Back to the world",   0.2, nil, nil)
    local grabPrompt  = prompt(cubeBase, "Grab",  plr.DisplayName .. "'s Box",     0.15, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
    local enterPrompt = prompt(cubeBase, "Enter", plr.DisplayName .. "'s Sandbox", 0.3,  Enum.KeyCode.F, Enum.KeyCode.ButtonY)

    sandboxes[plr] = {
        pocket = pocket, pocketSlab = pocketSlab,
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
            root.CFrame = pocketSlab.CFrame * CFrame.new(0, 5, 0)
            ping(pocketSlab, 0.3, 1.3)
        end
    end)

    exitPrompt.Triggered:Connect(function(actor)
        local c = actor.Character
        local root = c and c:FindFirstChild("HumanoidRootPart")
        if root then
            root.CFrame = cubeBase.CFrame * CFrame.new(0, 3, 0)
            ping(cubeBase, 0.3, 0.8)
        end
    end)

    hrp.CFrame = pocketSlab.CFrame * CFrame.new(0, 5, 0)
end

--------------------------------------------------------------------------------
-- MIRROR
--------------------------------------------------------------------------------
RunService.Heartbeat:Connect(function()
    for plr, s in pairs(sandboxes) do
        local char = plr.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp or not s.replica.Parent then continue end

        local rel = s.pocketSlab.CFrame:ToObjectSpace(hrp.CFrame)
        local pos = rel.Position * SCALE
        local rot = rel - rel.Position
        local _, size = s.replica:GetBoundingBox()

        s.replica:PivotTo(
            s.cubeBase.CFrame
            * CFrame.new(pos.X, pos.Y + size.Y * 0.5 + 0.1, pos.Z)
            * rot
        )
    end
end)

--------------------------------------------------------------------------------
-- WIRING
--------------------------------------------------------------------------------
local function hook(plr)
    plr.Chatted:Connect(function(msg)
        local m = msg:lower():gsub("%s+", "")
        if m == "!sandbox" or m == "/sandbox" then create(plr) end
    end)
    plr.CharacterRemoving:Connect(function() destroy(plr) end)
end

Players.PlayerAdded:Connect(hook)
for _, p in ipairs(Players:GetPlayers()) do hook(p) end
Players.PlayerRemoving:Connect(destroy)
