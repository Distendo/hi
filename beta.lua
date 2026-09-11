local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

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

local isVisible = true
local isSimulationActive = true
local isJimActive = false

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

local function setupCharacter(char)
	if not char then return end
	local rootPart = char:WaitForChild("HumanoidRootPart", 10)
	if not rootPart then return end
	
	local existingFolder = char:FindFirstChild("CustomModelFolder")
	if existingFolder then existingFolder:Destroy() end
	
	local folder = Instance.new("Folder")
	folder.Name = "CustomModelFolder"
	folder.Parent = char

	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	local targetColor = torso and torso.Color or Color3.fromRGB(255, 255, 0)

	local sMult = sizeScales[SIZE]
	local lData = lengthSettings[LENGTH]

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
				spring.Stiffness = 80
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
			spring.Stiffness = 70
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
		tipSpring.Stiffness = 80
		tipSpring.Damping = 4
		tipSpring.Parent = tipSphere
	end

	local lastDropTime = 0
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not char or not char.Parent or not folder.Parent then
			connection:Disconnect()
			return
		end

		if isJimActive and isSimulationActive and (tick() - lastDropTime) > 0.12 then
			lastDropTime = tick()
			
			local dropOrigin = tipSphere.Position
			local dropSphereRadius = 0.35 * sMult

			local dropPart = Instance.new("Part")
			dropPart.Name = "DropSphere"
			dropPart.Shape = Enum.PartType.Ball
			dropPart.Size = Vector3.new(dropSphereRadius * 2, dropSphereRadius * 2, dropSphereRadius * 2)
			dropPart.Color = Color3.fromRGB(255, 255, 255)
			dropPart.Material = Enum.Material.SmoothPlastic
			dropPart.CanCollide = false
			dropPart.Anchored = false
			dropPart.CFrame = CFrame.new(dropOrigin)
			dropPart.Parent = workspace

			task.spawn(function()
				local dropStartTime = tick()
				while tick() - dropStartTime < 1.2 do
					local ray = Ray.new(dropPart.Position, Vector3.new(0, -0.6, 0))
					local hitPart, hitPos, hitNormal = workspace:FindPartOnRayWithIgnoreList(ray, {char, folder, dropPart})
					
					if hitPart then
						local circleRadius = 0.5 * sMult
						local surfaceCircle = Instance.new("Part")
						surfaceCircle.Name = "DropCircle"
						surfaceCircle.Shape = Enum.PartType.Cylinder
						surfaceCircle.Size = Vector3.new(0.01, circleRadius * 2, circleRadius * 2)
						surfaceCircle.Color = Color3.fromRGB(255, 255, 255)
						surfaceCircle.Material = Enum.Material.SmoothPlastic
						surfaceCircle.CanCollide = false
						surfaceCircle.Anchored = true
						surfaceCircle.CFrame = CFrame.lookAt(hitPos + (hitNormal * 0.005), hitPos + hitNormal) * CFrame.Angles(0, math.rad(90), 0)
						surfaceCircle.Parent = workspace

						dropPart:Destroy()

						local fadeInfo = TweenInfo.new(2, Enum.EasingStyle.Linear)
						local fadeTween = TweenService:Create(surfaceCircle, fadeInfo, {Transparency = 1})
						fadeTween:Play()
						fadeTween.Completed:Connect(function()
							surfaceCircle:Destroy()
						end)
						return
					end
					task.wait()
				end

				if dropPart and dropPart.Parent then
					local circleRadius = 0.5 * sMult
					local surfaceCircle = Instance.new("Part")
					surfaceCircle.Name = "DropCircle"
					surfaceCircle.Shape = Enum.PartType.Cylinder
					surfaceCircle.Size = Vector3.new(0.01, circleRadius * 2, circleRadius * 2)
					surfaceCircle.Color = Color3.fromRGB(255, 255, 255)
					surfaceCircle.Material = Enum.Material.SmoothPlastic
					surfaceCircle.CanCollide = false
					surfaceCircle.Anchored = true
					surfaceCircle.CFrame = CFrame.new(dropPart.Position) * CFrame.Angles(math.rad(90), 0, 0)
					surfaceCircle.Parent = workspace

					dropPart:Destroy()

					local fadeInfo = TweenInfo.new(2, Enum.EasingStyle.Linear)
					local fadeTween = TweenService:Create(surfaceCircle, fadeInfo, {Transparency = 1})
					fadeTween:Play()
					fadeTween.Completed:Connect(function()
						surfaceCircle:Destroy()
					end)
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
	frame.Size = UDim2.new(0, 190, 0, 210)
	frame.Position = UDim2.new(0.85, 0, 0.35, 0)
	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
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

	local modeBtn = Instance.new("TextButton")
	modeBtn.Name = "ModeButton"
	modeBtn.Size = UDim2.new(0.9, 0, 0, 24)
	modeBtn.Position = UDim2.new(0.05, 0, 0.14, 0)
	modeBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	modeBtn.Text = "Mode: " .. MODE
	modeBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
	modeBtn.Font = Enum.Font.SourceSans
	modeBtn.TextSize = 12
	modeBtn.Parent = frame

	local sizeBtn = Instance.new("TextButton")
	sizeBtn.Name = "SizeButton"
	sizeBtn.Size = UDim2.new(0.9, 0, 0, 24)
	sizeBtn.Position = UDim2.new(0.05, 0, 0.28, 0)
	sizeBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	sizeBtn.Text = "Thickness: " .. SIZE
	sizeBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
	sizeBtn.Font = Enum.Font.SourceSans
	sizeBtn.TextSize = 12
	sizeBtn.Parent = frame

	local lengthBtn = Instance.new("TextButton")
	lengthBtn.Name = "LengthButton"
	lengthBtn.Size = UDim2.new(0.9, 0, 0, 24)
	lengthBtn.Position = UDim2.new(0.05, 0, 0.42, 0)
	lengthBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	lengthBtn.Text = "Length: " .. LENGTH
	lengthBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
	lengthBtn.Font = Enum.Font.SourceSans
	lengthBtn.TextSize = 12
	lengthBtn.Parent = frame

	local jimBtn = Instance.new("TextButton")
	jimBtn.Name = "JimButton"
	jimBtn.Size = UDim2.new(0.9, 0, 0, 24)
	jimBtn.Position = UDim2.new(0.05, 0, 0.56, 0)
	jimBtn.BackgroundColor3 = isJimActive and Color3.fromRGB(0, 120, 180) or Color3.fromRGB(45, 45, 45)
	jimBtn.Text = isJimActive and "Jim: ON" or "Jim: OFF"
	jimBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	jimBtn.Font = Enum.Font.SourceSansBold
	jimBtn.TextSize = 12
	jimBtn.Parent = frame

	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Name = "ToggleBtn"
	toggleBtn.Size = UDim2.new(0.9, 0, 0, 24)
	toggleBtn.Position = UDim2.new(0.05, 0, 0.70, 0)
	toggleBtn.BackgroundColor3 = isSimulationActive and Color3.fromRGB(0, 150, 75) or Color3.fromRGB(180, 40, 40)
	toggleBtn.Text = isSimulationActive and "State: RUNNING" or "State: STOPPED"
	toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	toggleBtn.Font = Enum.Font.SourceSansBold
	toggleBtn.TextSize = 12
	toggleBtn.Parent = frame

	local visBtn = Instance.new("TextButton")
	visBtn.Name = "VisBtn"
	visBtn.Size = UDim2.new(0.9, 0, 0, 24)
	visBtn.Position = UDim2.new(0.05, 0, 0.84, 0)
	visBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	visBtn.Text = isVisible and "Visibility: SHOWN (T)" or "Visibility: HIDDEN (T)"
	visBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
	visBtn.Font = Enum.Font.SourceSans
	visBtn.TextSize = 12
	visBtn.Parent = frame

	local function updateUI()
		modeBtn.Text = "Mode: " .. MODE
		sizeBtn.Text = "Thickness: " .. SIZE
		lengthBtn.Text = "Length: " .. LENGTH
		jimBtn.Text = isJimActive and "Jim: ON" or "Jim: OFF"
		jimBtn.BackgroundColor3 = isJimActive and Color3.fromRGB(0, 120, 180) or Color3.fromRGB(45, 45, 45)
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
end

if LocalPlayer then
	createDraggableUI(LocalPlayer)
	if LocalPlayer.Character then setupCharacter(LocalPlayer.Character) end
	LocalPlayer.CharacterAdded:Connect(function(char)
		setupCharacter(char)
		createDraggableUI(LocalPlayer)
	end)
end
