local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local PhysicsService = game:GetService("PhysicsService")

local LocalPlayer = Players.LocalPlayer or Players:GetPlayers()[1]

local modes = {"anchored", "2 parts anchored", "no part anchored"}
local currentModeIndex = 2
local MODE = modes[currentModeIndex]

local sizes = {"Small", "Normal", "Big"}
local currentSizeIndex = 2
local SIZE = sizes[currentSizeIndex]

local lengths = {"Short", "Normal", "Long"}
local currentLengthIndex = 2
local LENGTH = lengths[currentLengthIndex]

local colorPresets = {
	{ name = "Match Torso", color = nil },
	{ name = "Hot Pink", color = Color3.fromRGB(255, 105, 180) },
	{ name = "Neon Green", color = Color3.fromRGB(57, 255, 20) },
	{ name = "Deep Blue", color = Color3.fromRGB(0, 102, 204) },
	{ name = "Crimson Red", color = Color3.fromRGB(220, 20, 60) }
}
local currentColorIndex = 1

local stiffnessPresets = { 50, 80, 150, 300 }
local currentStiffnessIndex = 2

local isVisible = true
local isSimulationActive = true
local isJimActive = false

local renderConnection = nil

local sizeScales = {
	Small = 0.6,
	Normal = 1.0,
	Big = 1.6
}

local lengthSettings = {
	Short = { count = 2, length = 0.7 },
	Normal = { count = 4, length = 0.9 },
	Long = { count = 7, length = 0.9 }
}

local function getTargetColor(char)
	local preset = colorPresets[currentColorIndex]
	if preset.color then
		return preset.color
	end
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	return torso and torso.Color or Color3.fromRGB(255, 225, 0)
end

local function setupCharacter(char)
	if not char then return end
	local rootPart = char:WaitForChild("HumanoidRootPart", 10)
	if not rootPart then return end
	
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	local existingFolder = char:FindFirstChild("CustomModelFolder")
	if existingFolder then existingFolder:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = "CustomModelFolder"
	folder.Parent = char

	local targetColor = getTargetColor(char)
	local sMult = sizeScales[SIZE]
	local lData = lengthSettings[LENGTH]
	local currentStiffness = stiffnessPresets[currentStiffnessIndex]

	local baseSphereDiameter = 1.3 * sMult
	local leftSphere = Instance.new("Part")
	leftSphere.Name = "LeftSphere"
	leftSphere.Shape = Enum.PartType.Ball
	leftSphere.Size = Vector3.new(baseSphereDiameter, baseSphereDiameter, baseSphereDiameter)
	leftSphere.Color = targetColor
	leftSphere.CanCollide = false
	leftSphere.Transparency = isVisible and 0 or 1
	leftSphere.Parent = folder

	local rightSphere = Instance.new("Part")
	rightSphere.Name = "RightSphere"
	rightSphere.Shape = Enum.PartType.Ball
	rightSphere.Size = Vector3.new(baseSphereDiameter, baseSphereDiameter, baseSphereDiameter)
	rightSphere.Color = targetColor
	rightSphere.CanCollide = false
	rightSphere.Transparency = isVisible and 0 or 1
	rightSphere.Parent = folder

	local baseDistX = 0.5 * sMult
	local baseOffsetZ = -0.8 * sMult

	leftSphere.CFrame = rootPart.CFrame * CFrame.new(-baseDistX, -1.4, baseOffsetZ)
	local w1 = Instance.new("WeldConstraint")
	w1.Part0 = rootPart
	w1.Part1 = leftSphere
	w1.Parent = leftSphere

	rightSphere.CFrame = rootPart.CFrame * CFrame.new(baseDistX, -1.4, baseOffsetZ)
	local w2 = Instance.new("WeldConstraint")
	w2.Part0 = rootPart
	w2.Part1 = rightSphere
	w2.Parent = rightSphere

	local totalSegments = lData.count
	local segmentLength = lData.length
	local segmentDiameter = 1.1 * sMult

	local previousPart = rootPart
	local baseOffset = CFrame.new(0, -1.2, -1.2 * sMult) * CFrame.Angles(0, math.rad(90), 0)
	local stretchyParts = {}

	for i = 1, totalSegments do
		local seg = Instance.new("Part")
		seg.Name = "Segment_" .. i
		seg.Shape = Enum.PartType.Cylinder
		seg.Size = Vector3.new(segmentLength, segmentDiameter, segmentDiameter)
		seg.Color = targetColor
		seg.CanCollide = false
		seg.Transparency = isVisible and 0 or 1
		seg.Parent = folder

		table.insert(stretchyParts, seg)

		if MODE == "anchored" or not isSimulationActive then
			if i == 1 then
				seg.CFrame = rootPart.CFrame * baseOffset
			else
				seg.CFrame = previousPart.CFrame * CFrame.new(segmentLength, 0, 0)
			end
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = previousPart
			weld.Part1 = seg
			weld.Parent = seg
			previousPart = seg

		elseif MODE == "2 parts anchored" then
			if i <= 2 then
				if i == 1 then
					seg.CFrame = rootPart.CFrame * baseOffset
				else
					seg.CFrame = previousPart.CFrame * CFrame.new(segmentLength, 0, 0)
				end
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = previousPart
				weld.Part1 = seg
				weld.Parent = seg
				previousPart = seg
			else
				seg.Massless = true
				seg.CFrame = previousPart.CFrame * CFrame.new(segmentLength, 0, 0)

				local att0 = Instance.new("Attachment")
				att0.CFrame = CFrame.new(segmentLength / 2, 0, 0)
				att0.Parent = previousPart

				local att1 = Instance.new("Attachment")
				att1.CFrame = CFrame.new(-segmentLength / 2, 0, 0)
				att1.Parent = seg

				local socket = Instance.new("BallSocketConstraint")
				socket.Attachment0 = att0
				socket.Attachment1 = att1
				socket.LimitsEnabled = true
				socket.UpperAngle = 25
				socket.TwistLimitsEnabled = true
				socket.TwistLowerAngle = -15
				socket.TwistUpperAngle = 15
				socket.Parent = seg

				local spring = Instance.new("SpringConstraint")
				spring.Attachment0 = att0
				spring.Attachment1 = att1
				spring.FreeLength = 0
				spring.Stiffness = currentStiffness
				spring.Damping = 4
				spring.Parent = seg

				previousPart = seg
			end

		elseif MODE == "no part anchored" then
			seg.Massless = true
			if i == 1 then
				seg.CFrame = rootPart.CFrame * baseOffset
			else
				seg.CFrame = previousPart.CFrame * CFrame.new(segmentLength, 0, 0)
			end

			local att0 = Instance.new("Attachment")
			if i == 1 then
				att0.CFrame = baseOffset
				att0.Parent = rootPart
			else
				att0.CFrame = CFrame.new(segmentLength / 2, 0, 0)
				att0.Parent = previousPart
			end

			local att1 = Instance.new("Attachment")
			att1.CFrame = CFrame.new(-segmentLength / 2, 0, 0)
			att1.Parent = seg

			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = att0
			socket.Attachment1 = att1
			socket.LimitsEnabled = true
			socket.UpperAngle = 30
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -15
			socket.TwistUpperAngle = 15
			socket.Parent = seg

			local spring = Instance.new("SpringConstraint")
			spring.Attachment0 = att0
			spring.Attachment1 = att1
			spring.FreeLength = 0
			spring.Stiffness = currentStiffness
			spring.Damping = 3.5
			spring.Parent = seg

			previousPart = seg
		end
	end

	local tipDiameter = 1.2 * sMult
	local tipSphere = Instance.new("Part")
	tipSphere.Name = "TipSphere"
	tipSphere.Shape = Enum.PartType.Ball
	tipSphere.Size = Vector3.new(tipDiameter, tipDiameter, tipDiameter)
	tipSphere.Color = targetColor
	tipSphere.CanCollide = false
	tipSphere.Transparency = isVisible and 0 or 1
	tipSphere.Parent = folder

	tipSphere.CFrame = previousPart.CFrame * CFrame.new(segmentLength / 2 + (0.3 * sMult), 0, 0)

	if MODE == "anchored" or not isSimulationActive or MODE == "2 parts anchored" then
		local tipWeld = Instance.new("WeldConstraint")
		tipWeld.Part0 = previousPart
		tipWeld.Part1 = tipSphere
		tipWeld.Parent = tipSphere
	else
		tipSphere.Massless = true
		local tipAtt0 = Instance.new("Attachment")
		tipAtt0.CFrame = CFrame.new(segmentLength / 2, 0, 0)
		tipAtt0.Parent = previousPart

		local tipAtt1 = Instance.new("Attachment")
		tipAtt1.CFrame = CFrame.new(-0.2 * sMult, 0, 0)
		tipAtt1.Parent = tipSphere

		local tipSocket = Instance.new("BallSocketConstraint")
		tipSocket.Attachment0 = tipAtt0
		tipSocket.Attachment1 = tipAtt1
		tipSocket.LimitsEnabled = true
		tipSocket.UpperAngle = 20
		tipSocket.Parent = tipSphere

		local tipSpring = Instance.new("SpringConstraint")
		tipSpring.Attachment0 = tipAtt0
		tipSpring.Attachment1 = tipAtt1
		tipSpring.FreeLength = 0
		tipSpring.Stiffness = currentStiffness
		tipSpring.Damping = 4
		tipSpring.Parent = tipSphere
	end

	local lastDropTime = 0
	renderConnection = RunService.RenderStepped:Connect(function()
		if not char or not char.Parent or not folder.Parent then
			if renderConnection then
				renderConnection:Disconnect()
				renderConnection = nil
			end
			return
		end

		if isJimActive and isSimulationActive and (os.clock() - lastDropTime) > 0.12 then
			lastDropTime = os.clock()

			local dropOrigin = tipSphere.Position
			local dropRadius = 0.35 * sMult

			local dropPart = Instance.new("Part")
			dropPart.Name = "DropParticle"
			dropPart.Shape = Enum.PartType.Ball
			dropPart.Size = Vector3.new(dropRadius * 2, dropRadius * 2, dropRadius * 2)
			dropPart.Color = Color3.fromRGB(255, 255, 255)
			dropPart.Material = Enum.Material.SmoothPlastic
			dropPart.CanCollide = false
			dropPart.Anchored = false
			dropPart.CFrame = CFrame.new(dropOrigin)
			dropPart.AssemblyLinearVelocity = Vector3.new(0, -10, 0)
			dropPart.Parent = workspace

			task.spawn(function()
				local dropStartTime = os.clock()
				local raycastParams = RaycastParams.new()
				raycastParams.FilterAncestorsOfKnownSubinstances = {char, folder, dropPart}
				raycastParams.FilterType = Enum.RaycastFilterType.Exclude

				while (os.clock() - dropStartTime) < 1.2 and dropPart and dropPart.Parent do
					local result = workspace:Raycast(dropPart.Position, Vector3.new(0, -0.8, 0), raycastParams)
					if result then
						local circleRadius = 0.5 * sMult
						local surfaceCircle = Instance.new("Part")
						surfaceCircle.Name = "DropCircle"
						surfaceCircle.Shape = Enum.PartType.Cylinder
						surfaceCircle.Size = Vector3.new(0.01, circleRadius * 2, circleRadius * 2)
						surfaceCircle.Color = Color3.fromRGB(255, 255, 255)
						surfaceCircle.Material = Enum.Material.SmoothPlastic
						surfaceCircle.CanCollide = false
						surfaceCircle.Anchored = true
						surfaceCircle.CFrame = CFrame.lookAt(result.Position + (result.Normal * 0.005), result.Position + result.Normal) * CFrame.Angles(0, math.rad(90), 0)
						surfaceCircle.Parent = workspace

						dropPart:Destroy()

						local fadeTween = TweenService:Create(surfaceCircle, TweenInfo.new(2, Enum.EasingStyle.Linear), {Transparency = 1})
						fadeTween:Play()
						fadeTween.Completed:Connect(function()
							surfaceCircle:Destroy()
						end)
						return
					end
					task.wait()
				end

				if dropPart and dropPart.Parent then
					dropPart:Destroy()
				end
			end)
		end

		if not isVisible or not isSimulationActive then return end

		local currentVel = rootPart.AssemblyLinearVelocity.Magnitude
		local stretchFactor = math.clamp(1 + (currentVel * 0.0025), 1, 1.3)

		for _, part in ipairs(stretchyParts) do
			if part and part.Parent then
				part.Size = Vector3.new(
					segmentLength * stretchFactor, 
					segmentDiameter / math.sqrt(stretchFactor), 
					segmentDiameter / math.sqrt(stretchFactor)
				)
			end
		end
	end)
end

local function createDraggableUI(player)
	local playerGui = player:WaitForChild("PlayerGui", 10)
	if not playerGui then return end

	local existingGui = playerGui:FindFirstChild("ModelControlGui")
	if existingGui then existingGui:Destroy() end

	local sg = Instance.new("ScreenGui")
	sg.Name = "ModelControlGui"
	sg.ResetOnSpawn = false
	sg.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "MainFrame"
	frame.Size = UDim2.new(0, 200, 0, 275)
	frame.Position = UDim2.new(0.82, 0, 0.30, 0)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	frame.Active = true
	frame.Draggable = true
	frame.Parent = sg

	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, 8)
	uiCorner.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 25)
	title.BackgroundTransparency = 1
	title.Text = "Control Panel (Drag)"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Font = Enum.Font.SourceSansBold
	title.TextSize = 14
	title.Parent = frame

	local function makeButton(name, posY)
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.Size = UDim2.new(0.9, 0, 0, 22)
		btn.Position = UDim2.new(0.05, 0, 0, posY)
		btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		btn.TextColor3 = Color3.fromRGB(220, 220, 220)
		btn.Font = Enum.Font.SourceSans
		btn.TextSize = 12
		btn.Parent = frame
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = btn
		return btn
	end

	local modeBtn = makeButton("ModeBtn", 30)
	local sizeBtn = makeButton("SizeBtn", 58)
	local lengthBtn = makeButton("LengthBtn", 86)
	local colorBtn = makeButton("ColorBtn", 114)
	local stiffBtn = makeButton("StiffBtn", 142)
	local jimBtn = makeButton("JimBtn", 170)
	local toggleBtn = makeButton("ToggleBtn", 198)
	local visBtn = makeButton("VisBtn", 226)

	local function updateUI()
		modeBtn.Text = "Mode: " .. MODE
		sizeBtn.Text = "Thickness: " .. SIZE
		lengthBtn.Text = "Length: " .. LENGTH
		colorBtn.Text = "Color: " .. colorPresets[currentColorIndex].name
		stiffBtn.Text = "Stiffness: " .. stiffnessPresets[currentStiffnessIndex]
		jimBtn.Text = isJimActive and "Jim Drops: ON" or "Jim Drops: OFF"
		jimBtn.BackgroundColor3 = isJimActive and Color3.fromRGB(0, 120, 180) or Color3.fromRGB(40, 40, 40)
		toggleBtn.Text = isSimulationActive and "State: RUNNING" or "State: STOPPED"
		toggleBtn.BackgroundColor3 = isSimulationActive and Color3.fromRGB(0, 150, 75) or Color3.fromRGB(180, 40, 40)
		visBtn.Text = isVisible and "Visibility: SHOWN (T)" or "Visibility: HIDDEN (T)"
	end

	local function executeAction(action)
		if action == "MODE" then
			currentModeIndex = (currentModeIndex % #modes) + 1
			MODE = modes[currentModeIndex]
			if player.Character then setupCharacter(player.Character) end
		elseif action == "SIZE" then
			currentSizeIndex = (currentSizeIndex % #sizes) + 1
			SIZE = sizes[currentSizeIndex]
			if player.Character then setupCharacter(player.Character) end
		elseif action == "LENGTH" then
			currentLengthIndex = (currentLengthIndex % #lengths) + 1
			LENGTH = lengths[currentLengthIndex]
			if player.Character then setupCharacter(player.Character) end
		elseif action == "COLOR" then
			currentColorIndex = (currentColorIndex % #colorPresets) + 1
			if player.Character then setupCharacter(player.Character) end
		elseif action == "STIFFNESS" then
			currentStiffnessIndex = (currentStiffnessIndex % #stiffnessPresets) + 1
			if player.Character then setupCharacter(player.Character) end
		elseif action == "JIM" then
			isJimActive = not isJimActive
		elseif action == "TOGGLE" then
			isSimulationActive = not isSimulationActive
			if player.Character then setupCharacter(player.Character) end
		elseif action == "VISIBILITY" then
			isVisible = not isVisible
			if player.Character then
				local folder = player.Character:FindFirstChild("CustomModelFolder")
				if folder then
					for _, child in ipairs(folder:GetChildren()) do
						if child:IsA("BasePart") then
							child.Transparency = isVisible and 0 or 1
						end
					end
				end
			end
		end
		updateUI()
	end

	modeBtn.MouseButton1Click:Connect(function() executeAction("MODE") end)
	sizeBtn.MouseButton1Click:Connect(function() executeAction("SIZE") end)
	lengthBtn.MouseButton1Click:Connect(function() executeAction("LENGTH") end)
	colorBtn.MouseButton1Click:Connect(function() executeAction("COLOR") end)
	stiffBtn.MouseButton1Click:Connect(function() executeAction("STIFFNESS") end)
	jimBtn.MouseButton1Click:Connect(function() executeAction("JIM") end)
	toggleBtn.MouseButton1Click:Connect(function() executeAction("TOGGLE") end)
	visBtn.MouseButton1Click:Connect(function() executeAction("VISIBILITY") end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.Y then
			executeAction("MODE")
		elseif input.KeyCode == Enum.KeyCode.T then
			executeAction("VISIBILITY")
		end
	end)

	updateUI()
end

if LocalPlayer then
	createDraggableUI(LocalPlayer)
	if LocalPlayer.Character then setupCharacter(LocalPlayer.Character) end
	LocalPlayer.CharacterAdded:Connect(function(char)
		setupCharacter(char)
		createDraggableUI(LocalPlayer)
	end)
end
