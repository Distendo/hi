local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local LocalPlayer = Players.LocalPlayer
local ALLOWED_USER = "UUshshsh_78"
local AI_NAME = "Companion AI"

-- State tracking
local isMuted = false

-- Function to query the external g4f / free AI API
local function requestAIResponse(userPrompt)
	local requestData = {
		Url = "https://text.pollinations.ai/",
		Method = "POST",
		Headers = {
			["Content-Type"] = "application/json"
		},
		Body = HttpService:JSONEncode({
			messages = {
				{ role = "system", content = "You are an AI companion in Roblox. Keep responses concise and under 150 characters." },
				{ role = "user", content = userPrompt }
			},
			model = "openai"
		})
	}

	local success, response = pcall(function()
		return HttpService:RequestAsync(requestData)
	end)

	if success and response.Success then
		return response.Body
	else
		return "I'm having trouble connecting to my AI backend right now."
	end
end

-- Function to output text directly to the local player's chat
local function sendLocalChatMessage(text)
	local generalChannel = TextChatService.TextChannels:FindFirstChild("RBXGeneral")
	if generalChannel then
		generalChannel:DisplaySystemMessage("[" .. AI_NAME .. "]: " .. text)
	end
end

-- Listen for local chat inputs
LocalPlayer.Chatted:Connect(function(message)
	-- Command to toggle mute locally
	if message:lower() == "!mute" then
		isMuted = true
		sendLocalChatMessage("AI has been muted.")
		return
	elseif message:lower() == "!unmute" then
		isMuted = false
		sendLocalChatMessage("AI has been unmuted.")
		return
	end

	-- Check if the player is UUshshsh_78
	if LocalPlayer.Name ~= ALLOWED_USER then
		return
	end

	-- Do not process if currently muted
	if isMuted then
		return
	end

	-- Process AI request in a background thread
	task.spawn(function()
		local aiReply = requestAIResponse(message)
		sendLocalChatMessage(aiReply)
	end)
end)
