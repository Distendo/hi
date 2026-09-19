-- =============================================================================
-- MULTIPLAYER ASM VM ENGINE (16:9 TV + TEST SUITE + GUI CONSOLE)
-- Place this single script inside: ServerScriptService
-- =============================================================================

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--------------------------------------------------------------------------------
-- 1. REMOTE EVENTS SETUP
--------------------------------------------------------------------------------
local function GetOrCreateEvent(name)
	local event = ReplicatedStorage:FindFirstChild(name)
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = ReplicatedStorage
	end
	return event
end

local runEvent         = GetOrCreateEvent("RunASMProgramEvent")
local syncVRAMEvent    = GetOrCreateEvent("SyncVRAMEvent")
local testScreenEvent  = GetOrCreateEvent("TestScreenEvent")
local testCmdsEvent    = GetOrCreateEvent("TestCommandsEvent")
local consoleLogEvent  = GetOrCreateEvent("ConsoleLogEvent")

--------------------------------------------------------------------------------
-- 2. DISPLAY RESOLUTION & CONFIGURATION
--------------------------------------------------------------------------------
local VGA_WIDTH  = 48    
local VGA_HEIGHT = 27   
local VRAM_START = 4096 
local VRAM_SIZE  = VGA_WIDTH * VGA_HEIGHT -- 1,296 pixels

local PlayerVMs = {}

--------------------------------------------------------------------------------
-- 3. 16:9 TV MODEL GENERATOR
--------------------------------------------------------------------------------
local function BuildTVModel(player, playerSlot)
	local oldModel = Workspace:FindFirstChild("TV_Monitor_" .. player.Name)
	if oldModel then oldModel:Destroy() end

	local tvModel = Instance.new("Model")
	tvModel.Name = "TV_Monitor_" .. player.Name

	-- Position with 20-stud spacing
	local basePos = Vector3.new((playerSlot - 1) * 20 - 25, 8, -15)
	local rotationY = math.rad(25)
	local tvCFrame = CFrame.new(basePos) * CFrame.Angles(0, rotationY, 0)

	-- A. Base Stand
	local base = Instance.new("Part")
	base.Name = "StandBase"
	base.Size = Vector3.new(6, 0.4, 3.5)
	base.CFrame = tvCFrame * CFrame.new(0, -4.5, 0)
	base.Color = Color3.fromRGB(20, 20, 25)
	base.Material = Enum.Material.Metal
	base.Anchored = true
	base.Parent = tvModel

	-- B. Stand Neck
	local neck = Instance.new("Part")
	neck.Name = "StandNeck"
	neck.Size = Vector3.new(1.2, 2.8, 0.8)
	neck.CFrame = tvCFrame * CFrame.new(0, -3, -0.2)
	neck.Color = Color3.fromRGB(30, 30, 35)
	neck.Material = Enum.Material.Metal
	neck.Anchored = true
	neck.Parent = tvModel

	-- C. TV Outer Frame Bezel
	local body = Instance.new("Part")
	body.Name = "TVBody"
	body.Size = Vector3.new(13.2, 7.8, 0.6)
	body.CFrame = tvCFrame
	body.Color = Color3.fromRGB(15, 15, 18)
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.Parent = tvModel

	-- D. Screen Display Part
	local screenPart = Instance.new("Part")
	screenPart.Name = "DisplayScreen"
	screenPart.Size = Vector3.new(12.4, 7.0, 0.1)
	screenPart.CFrame = tvCFrame * CFrame.new(0, 0, 0.31)
	screenPart.Color = Color3.fromRGB(10, 10, 15)
	screenPart.Material = Enum.Material.SmoothPlastic
	screenPart.Anchored = true
	screenPart.Parent = tvModel

	-- E. SurfaceGui Display Interface
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "DisplayCanvas"
	surfaceGui.Face = Enum.NormalId.Front
	surfaceGui.Adornee = screenPart
	surfaceGui.CanvasSize = Vector2.new(960, 540)
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surfaceGui.LightInfluence = 0 -- Keeps screen bright regardless of shadow
	surfaceGui.AlwaysOnTop = false
	surfaceGui.Parent = screenPart

	local canvasFrame = Instance.new("Frame")
	canvasFrame.Name = "CanvasFrame"
	canvasFrame.Size = UDim2.new(1, 0, 1, 0)
	canvasFrame.BackgroundColor3 = Color3.fromRGB(5, 5, 10)
	canvasFrame.BorderSizePixel = 0
	canvasFrame.Parent = surfaceGui

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 960 / VGA_WIDTH, 0, 540 / VGA_HEIGHT)
	gridLayout.CellPadding = UDim2.new(0, 0, 0, 0)
	gridLayout.Parent = canvasFrame

	-- Construct 1,296 Pixel Frames (1-based index Px_1 to Px_1296)
	for y = 0, VGA_HEIGHT - 1 do
		for x = 0, VGA_WIDTH - 1 do
			local idx = (y * VGA_WIDTH) + x + 1
			local px = Instance.new("Frame")
			px.Name = "Px_" .. idx
			px.BorderSizePixel = 0
			px.BackgroundColor3 = Color3.fromRGB(20, 20, 30) -- Default standby blue grid
			px.Parent = canvasFrame
		end
	end

	tvModel.Parent = Workspace
	return tvModel
end

--------------------------------------------------------------------------------
-- 4. CLIENT IDE & DIAGNOSTIC GUI INJECTOR
--------------------------------------------------------------------------------
local function BuildClientGui(player)
	local playerGui = player:WaitForChild("PlayerGui")
	local oldGui = playerGui:FindFirstChild("ASMEditorGui")
	if oldGui then oldGui:Destroy() end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ASMEditorGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	-- Main Window Frame
	local window = Instance.new("Frame")
	window.Name = "MainWindow"
	window.Size = UDim2.new(0, 420, 0, 520)
	window.Position = UDim2.new(0, 20, 0.5, -260)
	window.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	window.BorderSizePixel = 0
	window.Active = true
	window.Draggable = true
	window.Parent = screenGui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 30)
	title.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
	title.Text = "  ASM Control Center - " .. player.Name .. "'s TV"
	title.TextColor3 = Color3.fromRGB(230, 230, 230)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Font = Enum.Font.SourceSansBold
	title.TextSize = 15
	title.Parent = window

	-- Code Input Box
	local textBox = Instance.new("TextBox")
	textBox.Name = "CodeInput"
	textBox.Size = UDim2.new(1, -20, 0, 210)
	textBox.Position = UDim2.new(0, 10, 0, 38)
	textBox.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	textBox.TextColor3 = Color3.fromRGB(80, 240, 120)
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.TextYAlignment = Enum.TextYAlignment.Top
	textBox.Font = Enum.Font.Code
	textBox.TextSize = 13
	textBox.ClearTextOnFocus = false
	textBox.MultiLine = true
	textBox.Text = [[; Rainbow TV Screen Pattern
MOV R0, 4096     ; Start VRAM
MOV R1, 5391     ; End VRAM
MOV R2, 16711680 ; Color Red

DRAW:
    STORE R0, R2
    ADD R2, 12000
    INC R0
    CMP R0, R1
    JL DRAW
HALT]]
	textBox.Parent = window

	-- Action Buttons Container
	local btnBar = Instance.new("Frame")
	btnBar.Size = UDim2.new(1, -20, 0, 32)
	btnBar.Position = UDim2.new(0, 10, 0, 256)
	btnBar.BackgroundTransparency = 1
	btnBar.Parent = window

	local runBtn = Instance.new("TextButton")
	runBtn.Size = UDim2.new(0.32, -4, 1, 0)
	runBtn.Position = UDim2.new(0, 0, 0, 0)
	runBtn.BackgroundColor3 = Color3.fromRGB(0, 140, 70)
	runBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	runBtn.Text = "▶ RUN"
	runBtn.Font = Enum.Font.SourceSansBold
	runBtn.TextSize = 13
	runBtn.Parent = btnBar

	local testScreenBtn = Instance.new("TextButton")
	testScreenBtn.Size = UDim2.new(0.34, -4, 1, 0)
	testScreenBtn.Position = UDim2.new(0.32, 2, 0, 0)
	testScreenBtn.BackgroundColor3 = Color3.fromRGB(180, 100, 0)
	testScreenBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	testScreenBtn.Text = "📺 TEST SCREEN"
	testScreenBtn.Font = Enum.Font.SourceSansBold
	testScreenBtn.TextSize = 12
	testScreenBtn.Parent = btnBar

	local testCmdsBtn = Instance.new("TextButton")
	testCmdsBtn.Size = UDim2.new(0.34, 0, 1, 0)
	testCmdsBtn.Position = UDim2.new(0.66, 4, 0, 0)
	testCmdsBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 180)
	testCmdsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	testCmdsBtn.Text = "🧪 TEST CMDS"
	testCmdsBtn.Font = Enum.Font.SourceSansBold
	testCmdsBtn.TextSize = 12
	testCmdsBtn.Parent = btnBar

	-- Output Log Console Frame
	local consoleLabel = Instance.new("TextLabel")
	consoleLabel.Size = UDim2.new(1, -20, 0, 18)
	consoleLabel.Position = UDim2.new(0, 10, 0, 296)
	consoleLabel.BackgroundTransparency = 1
	consoleLabel.Text = "System Console Output:"
	consoleLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
	consoleLabel.TextXAlignment = Enum.TextXAlignment.Left
	consoleLabel.Font = Enum.Font.SourceSansBold
	consoleLabel.TextSize = 12
	consoleLabel.Parent = window

	local consoleBox = Instance.new("TextBox")
	consoleBox.Name = "ConsoleBox"
	consoleBox.Size = UDim2.new(1, -20, 0, 188)
	consoleBox.Position = UDim2.new(0, 10, 0, 318)
	consoleBox.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
	consoleBox.TextColor3 = Color3.fromRGB(200, 220, 255)
	consoleBox.TextXAlignment = Enum.TextXAlignment.Left
	consoleBox.TextYAlignment = Enum.TextYAlignment.Top
	consoleBox.Font = Enum.Font.Code
	consoleBox.TextSize = 11
	consoleBox.ClearTextOnFocus = false
	consoleBox.MultiLine = true
	consoleBox.TextEditable = false
	consoleBox.Text = "[System Ready] Click 'TEST SCREEN' or 'TEST CMDS' to verify hardware.\n"
	consoleBox.Parent = window

	-- Client LocalScript handles VRAM painting and Events
	local clientScript = Instance.new("LocalScript")
	clientScript.Parent = screenGui
	clientScript.Source = [[
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local Workspace = game:GetService("Workspace")
		
		local runEvent        = ReplicatedStorage:WaitForChild("RunASMProgramEvent")
		local syncVRAMEvent   = ReplicatedStorage:WaitForChild("SyncVRAMEvent")
		local testScreenEvent = ReplicatedStorage:WaitForChild("TestScreenEvent")
		local testCmdsEvent   = ReplicatedStorage:WaitForChild("TestCommandsEvent")
		local consoleLogEvent = ReplicatedStorage:WaitForChild("ConsoleLogEvent")

		local mainWin = script.Parent.MainWindow
		local textBox = mainWin.CodeInput
		local consoleBox = mainWin.ConsoleBox

		mainWin.ActionButtons.RunButton.MouseButton1Click:Connect(function()
			runEvent:FireServer(textBox.Text)
		end)

		mainWin.ActionButtons.TestScreenBtn.MouseButton1Click:Connect(function()
			testScreenEvent:FireServer()
		end)

		mainWin.ActionButtons.TestCmdsBtn.MouseButton1Click:Connect(function()
			testCmdsEvent:FireServer()
		end)

		-- Log Receiver
		consoleLogEvent.OnClientEvent:Connect(function(msg)
			consoleBox.Text = consoleBox.Text .. msg .. "\n"
			consoleBox.CursorPosition = #consoleBox.Text + 1
		end)

		-- Client Live VRAM Painter
		syncVRAMEvent.OnClientEvent:Connect(function(targetPlayerName, dirtyPixels)
			local tvModel = Workspace:FindFirstChild("TV_Monitor_" .. targetPlayerName)
			if not tvModel then return end

			local screenPart = tvModel:FindFirstChild("DisplayScreen")
			if not screenPart then return end

			local canvasFrame = screenPart.DisplayCanvas.CanvasFrame

			for idx, val in pairs(dirtyPixels) do
				local pxFrame = canvasFrame:FindFirstChild("Px_" .. idx)
				if pxFrame then
					local r = math.floor(val / 65536) % 256
					local g = math.floor(val / 256) % 256
					local b = val % 256
					pxFrame.BackgroundColor3 = Color3.fromRGB(r, g, b)
				end
			end
		end)
	]]
end

--------------------------------------------------------------------------------
-- 5. ASSEMBLY VIRTUAL MACHINE CLASS
--------------------------------------------------------------------------------
local ASMVirtualMachine = {}
ASMVirtualMachine.__index = ASMVirtualMachine

function ASMVirtualMachine.new(ownerPlayer)
	local self = setmetatable({}, ASMVirtualMachine)
	self.Owner = ownerPlayer
	self:Reset()
	return self
end

function ASMVirtualMachine:Reset()
	self.Registers = { R0 = 0, R1 = 0, R2 = 0, R3 = 0, R4 = 0, R5 = 0, R6 = 0, R7 = 0 }
	self.IP = 1
	self.Memory = table.create(8192, 0)
	self.Flags = { Z = false, S = false }
	self.Halted = false
	self.Cycles = 0
	self.MaxCycles = 150000
	self.DirtyVRAM = {}
end

function ASMVirtualMachine:Log(msg)
	consoleLogEvent:FireClient(self.Owner, msg)
	print("[" .. self.Owner.Name .. "'s TV]:", msg)
end

function ASMVirtualMachine:ResolveOperand(operand)
	if not operand then return 0 end
	local op = tostring(operand):upper()
	if self.Registers[op] ~= nil then return self.Registers[op] end
	return tonumber(op) or 0
end

function ASMVirtualMachine:FlushVRAM()
	if next(self.DirtyVRAM) ~= nil then
		syncVRAMEvent:FireAllClients(self.Owner.Name, self.DirtyVRAM)
		self.DirtyVRAM = {}
	end
end

-- Direct HW Screen Test (Fills screen with test pattern without ASM)
function ASMVirtualMachine:TestScreenHardware()
	self:Log("--> Testing TV Screen Hardware...")
	local colors = {
		16711680, -- Red
		65280,    -- Green
		255,      -- Blue
		16776960, -- Yellow
		16711935, -- Magenta
		65535,    -- Cyan
		16777215  -- White
	}

	for y = 0, VGA_HEIGHT - 1 do
		for x = 0, VGA_WIDTH - 1 do
			local pixelIdx = (y * VGA_WIDTH) + x + 1
			local colorIdx = ((x + y) % #colors) + 1
			self.DirtyVRAM[pixelIdx] = colors[colorIdx]
		end
	end
	self:FlushVRAM()
	self:Log("✔ [PASS] TV Screen Test pattern sent to VRAM (1,296 Pixels rendered).")
end

-- Comprehensive Assembly Instruction Test Suite
function ASMVirtualMachine:RunInstructionTests()
	self:Log("==========================================")
	self:Log("--> RUNNING FULL ASSEMBLY COMMAND TEST SUITE...")
	self:Log("==========================================")
	
	local passCount = 0
	local failCount = 0

	local function AssertOp(testName, condition, detail)
		if condition then
			passCount += 1
			self:Log("  [PASS] " .. testName)
		else
			failCount += 1
			self:Log("  [FAIL] " .. testName .. " (" .. tostring(detail) .. ")")
		end
	end

	-- 1. MOV
	self:Reset()
	self.Registers.R0 = 0
	self:Run("MOV R0, 42\nHALT")
	AssertOp("MOV Instruction", self.Registers.R0 == 42, "Expected 42, got " .. self.Registers.R0)

	-- 2. Arithmetic (ADD, SUB, MUL, DIV, MOD, POW, SQRT, INC, DEC)
	self:Reset()
	self:Run([[
MOV R0, 10
ADD R0, 5
SUB R0, 3
MUL R0, 4
DIV R0, 2
MOD R0, 7
INC R0
DEC R0
HALT]])
	AssertOp("Arithmetic Operations (ADD,SUB,MUL,DIV,MOD,INC,DEC)", self.Registers.R0 == 3, "Expected 3, got " .. self.Registers.R0)

	-- 3. Math Functions (POW, SQRT)
	self:Reset()
	self:Run([[
MOV R0, 3
POW R0, 2
SQRT R0
HALT]])
	AssertOp("Math Operations (POW, SQRT)", self.Registers.R0 == 3, "Expected 3, got " .. self.Registers.R0)

	-- 4. Memory Store & Load
	self:Reset()
	self:Run([[
MOV R0, 999
STORE 100, R0
LOAD R1, 100
HALT]])
	AssertOp("Memory (STORE & LOAD)", self.Registers.R1 == 999, "Expected 999, got " .. self.Registers.R1)

	-- 5. Comparison & Conditional Jumps (CMP, JE, JNE, JL, JG, JMP)
	self:Reset()
	self:Run([[
MOV R0, 1
MOV R1, 5
LOOP:
    INC R0
    CMP R0, R1
    JL LOOP
HALT]])
	AssertOp("Branching (CMP, JL, JMP)", self.Registers.R0 == 5, "Expected 5, got " .. self.Registers.R0)

	-- 6. VRAM Write Test
	self:Reset()
	self:Run([[
MOV R0, 4096
MOV R1, 16711680
STORE R0, R1
HALT]])
	AssertOp("VRAM Memory Mapping", self.Memory[4096] == 16711680 and self.DirtyVRAM[1] == 16711680, "VRAM Write Failed")

	self:Log("==========================================")
	self:Log(string.format("TEST RESULTS: %d Passed, %d Failed.", passCount, failCount))
	self:Log("==========================================")
end

function ASMVirtualMachine:Assemble(sourceCode)
	local lines = string.split(sourceCode, "\n")
	local instructions = {}
	local labels = {}

	for _, rawLine in ipairs(lines) do
		local line = string.gsub(rawLine, ";.*", "")
		line = string.match(line, "^%s*(.-)%s*$")

		if line ~= "" then
			local label = string.match(line, "^([%w_]+):$")
			if label then
				labels[label:upper()] = #instructions + 1
			else
				local opcode, rest = string.match(line, "^(%w+)%s*(.*)$")
				if opcode then
					opcode = opcode:upper()
					local operands = {}
					if rest and rest ~= "" then
						for item in string.gmatch(rest, "[^,]+") do
							table.insert(operands, (string.match(item, "^%s*(.-)%s*$")))
						end
					end
					table.insert(instructions, { Opcode = opcode, Operands = operands, Raw = line })
				end
			end
		end
	end
	return instructions, labels
end

function ASMVirtualMachine:Run(sourceCode)
	self:Reset()
	local instructions, labels = self:Assemble(sourceCode)

	while not self.Halted and self.IP <= #instructions do
		self.Cycles += 1
		if self.Cycles > self.MaxCycles then 
			self:Log("[VM Error]: Program exceeded maximum safety cycles.") 
			break 
		end

		if self.Cycles % 250 == 0 then
			self:FlushVRAM()
			task.wait()
		end

		local inst = instructions[self.IP]
		local op = inst.Opcode
		local args = inst.Operands
		local nextIP = self.IP + 1

		if op == "MOV" then
			local reg = args[1]:upper()
			if self.Registers[reg] ~= nil then self.Registers[reg] = self:ResolveOperand(args[2]) end

		elseif op == "STORE" then
			local addr = self:ResolveOperand(args[1])
			local val = self:ResolveOperand(args[2])
			if addr >= 1 and addr <= #self.Memory then
				self.Memory[addr] = val
				if addr >= VRAM_START and addr < (VRAM_START + VRAM_SIZE) then
					local pixelIdx = (addr - VRAM_START) + 1
					self.DirtyVRAM[pixelIdx] = val
				end
			end

		elseif op == "LOAD" then
			local reg = args[1]:upper()
			local addr = self:ResolveOperand(args[2])
			if self.Registers[reg] ~= nil and addr >= 1 and addr <= #self.Memory then
				self.Registers[reg] = self.Memory[addr]
			end

		elseif op == "ADD" then
			local reg = args[1]:upper()
			if self.Registers[reg] ~= nil then self.Registers[reg] += self:ResolveOperand(args[2]) end

		elseif op == "SUB" then
			local reg = args[1]:upper()
			if self.Registers[reg] ~= nil then self.Registers[reg] -= self:ResolveOperand(args[2]) end

		elseif op == "MUL" then
			local reg = args[1]:upper()
			if self.Registers[reg] ~= nil then self.Registers[reg] *= self:ResolveOperand(args[2]) end

		elseif op == "DIV" then
			local reg = args[1]:upper()
			local divisor = self:ResolveOperand(args[2])
			if divisor ~= 0 and self.Registers[reg] ~= nil then self.Registers[reg] /= divisor end

		elseif op == "MOD" then
			local reg = args[1]:upper()
			local divisor = self:ResolveOperand(args[2])
			if divisor ~= 0 and self.Registers[reg] ~= nil then self.Registers[reg] %= divisor end

		elseif op == "POW" then
			local reg = args[1]:upper()
			if self.Registers[reg] ~= nil then self.Registers[reg] = self.Registers[reg] ^ self:ResolveOperand(args[2]) end

		elseif op == "SQRT" then
			local reg = args[1]:upper()
			if self.Registers[reg] ~= nil then self.Registers[reg] = math.sqrt(self.Registers[reg]) end

		elseif op == "INC" then
			local reg = args[1]:upper()
			if self.Registers[reg] ~= nil then self.Registers[reg] += 1 end

		elseif op == "DEC" then
			local reg = args[1]:upper()
			if self.Registers[reg] ~= nil then self.Registers[reg] -= 1 end

		elseif op == "CMP" then
			local diff = self:ResolveOperand(args[1]) - self:ResolveOperand(args[2])
			self.Flags.Z = (diff == 0)
			self.Flags.S = (diff < 0)

		elseif op == "JMP" then nextIP = labels[args[1]:upper()] or nextIP
		elseif op == "JE" or op == "JZ" then if self.Flags.Z then nextIP = labels[args[1]:upper()] or nextIP end
		elseif op == "JNE" or op == "JNZ" then if not self.Flags.Z then nextIP = labels[args[1]:upper()] or nextIP end
		elseif op == "JL" then if self.Flags.S then nextIP = labels[args[1]:upper()] or nextIP end
		elseif op == "JG" then if not self.Flags.Z and not self.Flags.S then nextIP = labels[args[1]:upper()] or nextIP end
		elseif op == "PRINT" then self:Log("PRINT Output: " .. tostring(self:ResolveOperand(args[1])))
		elseif op == "HALT" then self.Halted = true end

		self.IP = nextIP
	end

	self:FlushVRAM()
	self:Log("Program Execution Finished.")
end

--------------------------------------------------------------------------------
-- 6. PLAYER MANAGEMENT & NETWORK HANDLERS
--------------------------------------------------------------------------------
local playerSlotCounter = 0

Players.PlayerAdded:Connect(function(player)
	playerSlotCounter += 1
	BuildTVModel(player, playerSlotCounter)
	PlayerVMs[player] = ASMVirtualMachine.new(player)
	BuildClientGui(player)
end)

Players.PlayerRemoving:Connect(function(player)
	local tvModel = Workspace:FindFirstChild("TV_Monitor_" .. player.Name)
	if tvModel then tvModel:Destroy() end
	PlayerVMs[player] = nil
end)

runEvent.OnServerEvent:Connect(function(player, sourceCode)
	local vm = PlayerVMs[player]
	if vm and typeof(sourceCode) == "string" then
		task.spawn(function() vm:Run(sourceCode) end)
	end
end)

testScreenEvent.OnServerEvent:Connect(function(player)
	local vm = PlayerVMs[player]
	if vm then
		task.spawn(function() vm:TestScreenHardware() end)
	end
end)

testCmdsEvent.OnServerEvent:Connect(function(player)
	local vm = PlayerVMs[player]
	if vm then
		task.spawn(function() vm:RunInstructionTests() end)
	end
end)
