-- ServerScriptService/PocketSandbox.server.lua
--
-- !sandbox  →  gives you a "PocketSandbox" tool (classic gear flow, droppable,
--              pickupable). Equipping the tool puts a studded mini baseplate in
--              your hand. Clicking enters your pocket sandbox; a stud slab
--              512 studs up where you walk around normally. Everything you do
--              there — movement, pose, any loose object you carry, throw or
--              drop — mirrors in real-time onto the mini baseplate in your
--              hand, scaled 1:12.5. The mini baseplate's "walls" are the sky.
--
-- Exit through the red pad.

local Players  = game:GetService("Players")
local RunService = game:GetService("RunService")
local Physics  = game:GetService("PhysicsService")
local Debris   = game:GetService("Debris")

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------
local SCALE        = 0.08
local BASE_SIZE    = 32
local CUBE_SIZE    = BASE_SIZE * SCALE          -- 2.56 studs
local POCKET_Y     = 512
local POCKET_GAP   = 200
local TOOL_NAME    = "PocketSandbox"
local MIRROR_BOX   = Vector3.new(BASE_SIZE + 24, 240, BASE_SIZE + 24)
local MIRROR_CENTER_Y = 70

local COLOR_PLASTIC = Color3.fromRGB(96, 100, 108)
local COLOR_RIM     = Color3.fromRGB(190, 196, 212)
local COLOR_EXIT    = Color3.fromRGB(255, 90, 90)

--------------------------------------------------------------------------------
-- COLLISION GROUP (held parts don't shove the holder)
--------------------------------------------------------------------------------
do
    pcall(function()
        Physics:RegisterCollisionGroup("SandboxHeld")
        Physics:CollisionGroupSetCollidable("SandboxHeld", "Default", false)
    end)
end

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local pockets = {}          -- [Tool] -> data
local pocketIndex = 0

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
    return w
end

local function ping(parent, vol, pitch)
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://6042053626"
    s.Volume  = vol   or 0.4
    s.PlaybackSpeed = pitch or 1
    s.Parent  = parent
    s:Play()
    Debris:AddItem(s, 2)
end

local function isCharacterPart(inst)
    local node = inst
    while node do
        if Players:GetPlayerFromCharacter(node) then return true end
        node = node.Parent
    end
    return false
end

--------------------------------------------------------------------------------
-- POCKET SANDBOX  (the big studded slab you actually stand on)
--------------------------------------------------------------------------------
local function buildPocket(origin)
    local model = Instance.new("Model")
    model.Name = "PocketSandbox"

    -- Stud baseplate.
    local slab = part{
        Name        = "Slab",
        Size        = Vector3.new(BASE_SIZE, 3, BASE_SIZE),
        Position    = origin,
        Material    = Enum.Material.Plastic,
        Color       = COLOR_PLASTIC,
        TopSurface  = Enum.SurfaceType.Studs,      -- classic stud top
        BottomSurface = Enum.SurfaceType.Inlet,
    }
    slab.Parent = model

    -- Red exit pad at the back edge.
    local exit = part{
        Name        = "ExitPad",
        Shape       = Enum.PartType.Cylinder,
        Size        = Vector3.new(0.25, 5, 5),
        CFrame      = slab.CFrame
            * CFrame.new(0, 1.85, -BASE_SIZE / 2 + 5)
            * CFrame.Angles(0, 0, math.rad(90)),
        Material    = Enum.Material.Neon,
        Color       = COLOR_EXIT,
        Transparency = 0.15,
        CanCollide  = false,
    }
    exit.Parent = model

    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText  = "Leave"
    prompt.ObjectText  = "Back to the world"
    prompt.HoldDuration = 0.2
    prompt.MaxActivationDistance = 12
    prompt.RequiresLineOfSight = false
    prompt.KeyboardKeyCode = Enum.KeyCode.F
    prompt.GamepadKeyCode  = Enum.KeyCode.ButtonY
    prompt.Parent = exit

    model.PrimaryPart = slab
    model.Parent = workspace
    return model, slab, exit, prompt
end

--------------------------------------------------------------------------------
-- TOOL  (mini studded baseplate you hold + invisible sky "windows")
--------------------------------------------------------------------------------
local function buildTool()
    local tool = Instance.new("Tool")
    tool.Name           = TOOL_NAME
    tool.RequiresHandle = true
    tool.CanBeDropped   = true
    tool.ToolTip        = "Pocket Sandbox — click to enter"

    -- Handle = mini stud baseplate.
    local handle = part{
        Name       = "Handle",
        Size       = Vector3.new(CUBE_SIZE, 0.18, CUBE_SIZE),
        Material   = Enum.Material.Plastic,
        Color      = COLOR_PLASTIC,
        TopSurface = Enum.SurfaceType.Studs,      -- stud top on the mini too
        Massless   = true,
    }
    handle.Parent = tool

    local h = CUBE_SIZE / 2

    -- Thin metal rim around the edge.
    local rimT = 0.04
    for _, def in ipairs({
        { Vector3.new(CUBE_SIZE, 0.06, rimT), Vector3.new(0, 0.09,  h) },
        { Vector3.new(CUBE_SIZE, 0.06, rimT), Vector3.new(0, 0.09, -h) },
        { Vector3.new(rimT, 0.06, CUBE_SIZE), Vector3.new( h, 0.09, 0) },
        { Vector3.new(rimT, 0.06, CUBE_SIZE), Vector3.new(-h, 0.09, 0) },
    }) do
        local m = part{
            Size       = def[1],
            CFrame     = handle.CFrame * CFrame.new(def[2]),
            Material   = Enum.Material.Metal,
            Color      = COLOR_RIM,
            CanCollide = false,
            Massless   = true,
        }
        m.Parent = tool
        weld(handle, m)
    end

    -- Invisible sky "windows". Five fully-invisible volumes — no sheen, no
    -- shadow, no reflected material — so from outside you look straight
    -- through into the sky behind. They don't collide or query.
    local wallH = CUBE_SIZE
    for _, def in ipairs({
        { Vector3.new(CUBE_SIZE, wallH, 0.05), Vector3.new(0, wallH / 2,  h) },
        { Vector3.new(CUBE_SIZE, wallH, 0.05), Vector3.new(0, wallH / 2, -h) },
        { Vector3.new(0.05, wallH, CUBE_SIZE), Vector3.new( h, wallH / 2, 0) },
        { Vector3.new(0.05, wallH, CUBE_SIZE), Vector3.new(-h, wallH / 2, 0) },
        { Vector3.new(CUBE_SIZE, 0.05, CUBE_SIZE), Vector3.new(0, wallH, 0) },
    }) do
        local w = part{
            Name         = "SkyWindow",
            Size         = def[1],
            CFrame       = handle.CFrame * CFrame.new(def[2]),
            Material     = Enum.Material.ForceField,
            Color        = Color3.new(0, 0, 0),
            Transparency = 1,
            Reflectance  = 0,
            CanCollide   = false,
            CanQuery     = false,
            CanTouch     = false,
            CastShadow   = false,
            Massless     = true,
        }
        w.Parent = tool
        weld(handle, w)
    end

    return tool, handle
end

--------------------------------------------------------------------------------
-- REPLICA  (scaled clone of the holder)
--------------------------------------------------------------------------------
local function buildReplica(char, parent)
    char.Archivable = true
    local rep = char:Clone()
    rep.Name = "Replica"

    for _, d in ipairs(rep:GetDescendants()) do
        if d:IsA("BaseScript") or d:IsA("Tool") then d:Destroy() end
    end

    rep:ScaleTo(SCALE)

    -- Cache a name -> part map so per-frame mirroring is O(1).
    local map = {}
    for _, d in ipairs(rep:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored   = true
            d.CanCollide = false
            d.CanQuery   = false
            d.CanTouch   = false
            d.Massless   = true
            d.CastShadow = false
            map[d.Name] = map[d.Name] or d
        end
    end
    rep:SetAttribute("MirrorMap", true)

    rep.Parent = parent
    return rep, map
end

--------------------------------------------------------------------------------
-- MIRROR: character pose  (this is what makes animations replicate)
--
-- The player's pose is entirely encoded in the world CFrames of the
-- character's limbs. If we sample those CFrames every frame, scale them into
-- the mini baseplate's local space and write them onto the replica, the
-- replica plays the exact same walk / idle / jump / tool swing as the player
-- with zero animation IDs, zero Animator plumbing, and zero latency.
--------------------------------------------------------------------------------
local function mirrorCharacter(char, replica, map, slab, handle)
    for _, charPart in ipairs(char:GetDescendants()) do
        if charPart:IsA("BasePart") then
            local repPart = map[charPart.Name]
            if repPart then
                local rel = slab.CFrame:ToObjectSpace(charPart.CFrame)
                repPart.CFrame = handle.CFrame
                    * CFrame.new(rel.Position * SCALE)
                    * (rel - rel.Position)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- MIRROR: loose objects  (props you drop / throw / carry in the pocket)
--------------------------------------------------------------------------------
local function updateObjectMirrors(data, handle)
    local slab = data.slab
    local origin = slab.Position
    local boxCF  = CFrame.new(origin + Vector3.new(0, MIRROR_CENTER_Y, 0))

    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {
        data.model,
        data.replicaFolder,
    }

    local hits = workspace:GetPartBoundsInBox(boxCF, MIRROR_BOX, params)
    local seen = {}

    for _, src in ipairs(hits) do
        if src.Anchored then continue end
        if isCharacterPart(src) then continue end
        if src.CollisionGroup == "SandboxHeld" then continue end

        seen[src] = true

        local mirror = data.mirrors[src]
        if not mirror or not mirror.Parent then
            -- Clone part and shrink it.
            local ok, clone = pcall(function() return src:Clone() end)
            if not ok then continue end
            clone.Name = "Mirror_" .. src.Name

            if clone:IsA("BasePart") then
                clone.Anchored   = true
                clone.CanCollide = false
                clone.CanQuery   = false
                clone.CanTouch   = false
                clone.Massless   = true
                clone.CastShadow = false
                clone.CollisionGroup = "Default"
                clone.Size = clone.Size * SCALE
            end
            for _, d in ipairs(clone:GetDescendants()) do
                if d:IsA("BasePart") then
                    d.Anchored   = true
                    d.CanCollide = false
                    d.CanQuery   = false
                    d.CanTouch   = false
                    d.Massless   = true
                    d.CastShadow = false
                    d.Size = d.Size * SCALE
                end
            end
            clone.Parent = data.replicaFolder
            data.mirrors[src] = clone
            mirror = clone
        end

        if mirror and mirror:IsA("BasePart") then
            local rel = slab.CFrame:ToObjectSpace(src.CFrame)
            mirror.CFrame = handle.CFrame
                * CFrame.new(rel.Position * SCALE)
                * (rel - rel.Position)
        elseif mirror then
            -- Model clone: pivot it.
            local _, srcSize = src:GetBoundingBox()
            local rel = slab.CFrame:ToObjectSpace(src.CFrame)
            mirror:PivotTo(
                handle.CFrame
                * CFrame.new(rel.Position * SCALE)
                * (rel - rel.Position)
            )
        end
    end

    -- Prune mirrors whose source is gone.
    for src, m in pairs(data.mirrors) do
        if not seen[src] or not src.Parent then
            m:Destroy()
            data.mirrors[src] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- SANDBOX CREATION
--------------------------------------------------------------------------------
local function createSandboxFor(plr)
    -- Bail if the player already has one of these tools.
    local function alreadyHas()
        for _, it in ipairs(plr.Backpack:GetChildren()) do
            if it:IsA("Tool") and it.Name == TOOL_NAME then return true end
        end
        if plr.Character then
            for _, it in ipairs(plr.Character:GetChildren()) do
                if it:IsA("Tool") and it.Name == TOOL_NAME then return true end
            end
        end
        return false
    end
    if alreadyHas() then return end

    pocketIndex = pocketIndex + 1
    local origin = Vector3.new(pocketIndex * POCKET_GAP, POCKET_Y, 0)

    local model, slab, exit, exitPrompt = buildPocket(origin)
    local tool, handle = buildTool()

    local replicaFolder = Instance.new("Folder")
    replicaFolder.Name = "Mirror_" .. plr.Name
    replicaFolder.Parent = workspace

    local data = {
        model         = model,
        slab          = slab,
        exit          = exit,
        exitPrompt    = exitPrompt,
        handle        = handle,
        replicaFolder = replicaFolder,
        replica       = nil,
        replicaMap    = nil,
        replicaChar   = nil,
        mirrors       = {},
        returnCFrames = {},
    }
    pockets[tool] = data

    -- ── tool events ─────────────────────────────────────────────────────────
    tool.Equipped:Connect(function()
        handle.Anchored = false
        local char = tool.Parent
        if not char or not char:IsA("Model") then return end
        if not Players:GetPlayerFromCharacter(char) then return end

        if data.replica and data.replicaChar ~= char then
            data.replica:Destroy()
            data.replica, data.replicaMap = nil, nil
        end

        if not data.replica then
            replicaFolder.Parent = workspace
            local rep, map = buildReplica(char, replicaFolder)
            data.replica      = rep
            data.replicaMap   = map
            data.replicaChar  = char
        end
    end)

    tool.Unequipped:Connect(function()
        handle.Anchored = true
    end)

    -- Click = enter / exit the pocket sandbox.
    tool.Activated:Connect(function()
        local holder = Players:GetPlayerFromCharacter(tool.Parent)
        if not holder then return end
        local char = holder.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        if hrp.Position.Y > POCKET_Y - 120 then
            -- Currently inside pocket → send home.
            local ret = data.returnCFrames[holder]
            hrp.CFrame = ret or CFrame.new(0, 10, 0)
            ping(handle, 0.3, 0.8)
        else
            -- Outside → warp into pocket.
            data.returnCFrames[holder] = hrp.CFrame
            hrp.CFrame = slab.CFrame * CFrame.new(0, 5, 0)
            ping(slab, 0.3, 1.25)
        end
    end)

    exitPrompt.Triggered:Connect(function(actor)
        local char = actor.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local ret = data.returnCFrames[actor]
        hrp.CFrame = ret or CFrame.new(0, 10, 0)
        ping(slab, 0.3, 0.8)
    end)

    tool.Destroying:Connect(function()
        local d = pockets[tool]
        if d then
            if d.model         then d.model:Destroy()         end
            if d.replicaFolder then d.replicaFolder:Destroy() end
            pockets[tool] = nil
        end
    end)

    tool.Parent = plr.Backpack
end

--------------------------------------------------------------------------------
-- PER-FRAME MIRRORING LOOP
--------------------------------------------------------------------------------
RunService.Heartbeat:Connect(function()
    for tool, data in pairs(pockets) do
        local handle = tool:FindFirstChild("Handle")
        local slab   = data.slab
        local folder = data.replicaFolder

        -- Handle isn't in the world (tool is stowed) — hide the mirror.
        local active = handle and handle:IsDescendantOf(workspace) and slab and slab.Parent
        if not active then
            if folder and folder.Parent then folder.Parent = nil end
            continue
        end
        if not folder.Parent then folder.Parent = workspace end

        -- Mirror the holder's body/pose onto the replica.
        local char = tool.Parent
        if char and char:IsA("Model") and Players:GetPlayerFromCharacter(char)
           and data.replica and data.replica.Parent and data.replicaMap then
            mirrorCharacter(char, data.replica, data.replicaMap, slab, handle)
        end

        -- Mirror any loose props inside the pocket.
        updateObjectMirrors(data, handle)
    end
end)

--------------------------------------------------------------------------------
-- CHAT HOOK
--------------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(plr)
    plr.Chatted:Connect(function(msg)
        local m = msg:lower():gsub("%s+", "")
        if m == "!sandbox" or m == "/sandbox" then
            createSandboxFor(plr)
        end
    end)
end)
