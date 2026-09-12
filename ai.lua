--[[ UUrIntelligence ALT ASSISTANT - LOCALSCRIPT ONLY - v2
  Owner: UUshshsh_78 | Bot accounts: UUrIntelligence
  NO Server Script. Real player (alt), NOT a visual clone. Real AI = Gemini 3.5 Flash-Lite.
  HOW TO USE (pick one):
   A) YOUR OWN GAME: StarterPlayer > StarterPlayerScripts > LocalScript, paste this whole file. Both main+alt auto get role.
   B) EXECUTOR on ALT only: execute this file on UUrIntelligence. Do NOT execute on main.
  talking = RBXGeneral:SendAsync (real message as alt, everyone sees) + bubble.
  effects on alt (follow/jump/small) replicate because alt owns its character.
  effects on owner (!speed/!heal) are NOT here - keep them in main script if needed.
]]
local OWNER_NAME = "UUshshsh_78"
local ALT_NAMES = { UUrIntelligence = true }
-- REAL AI: Google Gemini 3.5 Flash-Lite (cheapest flash model, tested working).
-- Key belongs to you. Do NOT share this file - anyone with it spends your quota.
local AI_GEMINI_KEY = "AQ.Ab8RN6KAzTIjpXQZDBDcrr6qquMehZWJPQ2wGHIxm3TyFhlWkQ"
local AI_MODEL = "gemini-3.5-flash-lite"
local AI_SYSTEM = "You are UUrIntelligence, a small professional Roblox assistant serving your boss UUshshsh_78. Reply short, under 180 characters, friendly, a little slang, no hashtags, plain text only."

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local Chat = game:GetService("Chat")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- ROLE GATE: only alt runs assistant. Owner / strangers stay idle.
if LocalPlayer.Name == OWNER_NAME then
  print("[ALT-AI] idle on owner (run this on UUrIntelligence)")
  return
end
if not ALT_NAMES[LocalPlayer.Name] then
  print("[ALT-AI] idle (not an alt account)")
  return
end

local function getOwner() return Players:FindFirstChild(OWNER_NAME) end

-- state
local muted, following, orbiting = false, true, false
local memory, lastReply = {}, 0

-- CHAT MODE: "send" = real replicated chat via RBXGeneral:SendAsync (everyone sees it).
-- Proven working on your executor. "bubble" = local bubbles only (alt screen only).
local CHAT_MODE = "send"
local channel = nil
if CHAT_MODE == "send" then
  local ok, ch = pcall(function()
    return TextChatService:WaitForChild("TextChannels", 5):WaitForChild("RBXGeneral", 5)
  end)
  if ok then channel = ch end
end

local function altSay(text, force)
  if muted and not force then return end
  if type(text) ~= "string" or text == "" then return end
  if os.clock() - lastReply < 1 then task.wait(1) end
  lastReply = os.clock()
  text = string.sub(text, 1, 200)
  print("[ALT-AI] say: " .. text)
  -- 1) real replicated message as the alt (LocalScript-safe, no executor flag)
  pcall(function() Players:Chat(text) end)
  -- 2) guaranteed local bubble over alt head (alt screen always shows it)
  local head = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
  if head then
    pcall(function() TextChatService:DisplayBubble(head, text) end)
    pcall(function() Chat:Chat(head, text, Enum.ChatColor.White) end)
  end
  -- 3) optionally also SendAsync (only if CHAT_MODE == "send")
  if channel then
    pcall(function() channel:SendAsync(text) end)
  end
  task.wait(math.clamp(#text * 0.015, 0.7, 1.8))
end

-- small + professional look (own character, replicates). R15 scales; R6 skips gracefully.
local function makeSmallPro()
  local char = LocalPlayer.Character
  if not char then return end
  local hum = char:FindFirstChildOfClass("Humanoid")
  if not hum then return end
  pcall(function()
    hum.DisplayName = "UUr AI"
    local h = hum:FindFirstChild("BodyHeightScale")
    local w = hum:FindFirstChild("BodyWidthScale")
    local d = hum:FindFirstChild("BodyDepthScale")
    local hd = hum:FindFirstChild("HeadScale")
    if h then h.Value = 0.62 end
    if w then w.Value = 0.68 end
    if d then d.Value = 0.68 end
    if hd then hd.Value = 0.9 end
  end)
  -- local overhead tag (only alt sees it, others see DisplayName + real chat - LocalScript limit)
  pcall(function()
    local head = char:FindFirstChild("Head")
    if head and not head:FindFirstChild("AI_Tag") then
      local bb = Instance.new("BillboardGui")
      bb.Name = "AI_Tag" bb.Size = UDim2.new(0, 200, 0, 40)
      bb.StudsOffset = Vector3.new(0, 2.6, 0) bb.AlwaysOnTop = true
      bb.Adornee = head bb.Parent = head
      local tl = Instance.new("TextLabel")
      tl.Size = UDim2.new(1, 0, 1, 0) tl.BackgroundTransparency = 1
      tl.Text = "AI Assistant | !help" tl.TextScaled = true
      tl.Font = Enum.Font.GothamBold tl.TextColor3 = Color3.fromRGB(140, 255, 255)
      tl.Parent = bb
    end
  end)
end

local JOKES = {
  "Why did the Noob cross the road? To respawn on the other side, sir.",
  "My ping is low and my loyalty is high, sir.",
  "I would tell you a lag joke, sir, but it is still loading.",
  "You carry the team, sir. I carry your backup plan.",
}
local FALLBACKS = {
  "Understood, sir. How can I assist? Try !help.",
  "Yes sir. I am on it. Need !help with commands?",
  "Noted, sir. I stay close. Say !help anytime.",
  "Copy that, sir. Anything else I can do?",
}
local function safeCalc(expr)
  expr = string.gsub(expr, "%s+", "")
  if expr == "" or not string.match(expr, "^[%d%+%-%*/%%%^%(%)%.]+$") then return nil end
  local fn = loadstring("return (" .. expr .. ")")
  if not fn then return nil end
  local ok, res = pcall(fn)
  if ok and type(res) == "number" then return tostring(math.floor(res * 1000) / 1000) end
  return nil
end

-- REAL AI via Gemini generateContent (executor http only). Returns string or nil -> offline fallback.
local lastAIError, aiBusy = "never called", false
local function askAI(userText)
  if AI_GEMINI_KEY == "" then lastAIError = "no key set" return nil end
  if aiBusy then lastAIError = "busy, try again" return nil end
  local hr = (getgenv and (getgenv().http_request or getgenv().request)) or http_request or request
  if not hr then lastAIError = "no http fn (need executor)" return nil end
  aiBusy = true
  local done, result = false, nil
  task.spawn(function()
    local ok, res = pcall(function()
      return hr({
        Url = "https://generativelanguage.googleapis.com/v1beta/models/" .. AI_MODEL .. ":generateContent?key=" .. AI_GEMINI_KEY,
        Method = "POST",
        Headers = {["Content-Type"] = "application/json"},
        Body = HttpService:JSONEncode({
          system_instruction = {parts = {{text = AI_SYSTEM}}},
          contents = {{parts = {{text = string.sub(userText, 1, 300)}}}},
          generationConfig = {maxOutputTokens = 120, temperature = 0.9},
        }),
      })
    end)
    if ok and res and res.StatusCode == 200 then
      local ok2, j = pcall(function() return HttpService:JSONDecode(tostring(res.Body or "")) end)
      local t = ok2 and j and j.candidates and j.candidates[1] and j.candidates[1].content
        and j.candidates[1].content.parts and j.candidates[1].content.parts[1]
        and j.candidates[1].content.parts[1].text
      if t and #t > 1 then
        result = string.sub(string.gsub(t, "%s+", " "), 1, 190)
        lastAIError = "ok"
      else
        lastAIError = "empty reply"
      end
    elseif ok and res then
      lastAIError = "code " .. tostring(res.StatusCode)
    else
      lastAIError = "http fail"
    end
    done = true
  end)
  local t0 = os.clock()
  while not done and os.clock() - t0 < 15 do task.wait(0.1) end
  if not done then lastAIError = "timeout" end
  aiBusy = false
  return result
end

local HELP = "!help !ask <q> !aistatus !follow !stay !come !jump !spin !dance !sit !stand !reset !mute !unmute !joke !calc <e> !time !date !remember k=v !recall k !orbit [off] !about"
local function brain(raw)
  local msg = string.gsub(string.gsub(raw, "^%s+", ""), "%s+$", "")
  local lower = string.lower(msg)
  if lower == "!help" or lower == "!cmds" then return HELP end
  if lower == "!follow" or lower == "follow me" or lower == "!come" or lower == "come" then following = true orbiting = false return "Yes sir. Following." end
  if lower == "!stay" or lower == "!stop" or lower == "!unfollow" then following = false return "Holding position, sir. !follow to resume." end
  if lower == "!reset" or lower == "!bring" or lower == "!tp" then teleportToOwner() return "Teleported to you, sir." end
  if lower == "!jump" then jump() return "Yes sir." end
  if lower == "!spin" then spin() return "Spinning, sir." end
  if lower == "!dance" then dance() return "At your service, sir." end
  if lower == "!sit" then sit(true) return "Seated, sir." end
  if lower == "!stand" then sit(false) return "Standing by, sir." end
  if lower == "!mute" then muted = true return "Muted, sir. !unmute to resume.", true end
  if lower == "!unmute" or lower == "!talk" then muted = false return "Back online, sir.", true end
  if lower == "!joke" then return JOKES[math.random(1, #JOKES)] end
  if string.sub(lower, 1, 5) == "!calc" then local r = safeCalc(string.sub(msg, 7)) if r then return "Result: " .. r end return "Usage: !calc 12*8+5, sir." end
  if lower == "!time" then return "Time: " .. os.date("%I:%M %p") .. ", sir." end
  if lower == "!date" then return "Date: " .. os.date("%A, %B %d") .. ", sir." end
  if string.sub(lower, 1, 9) == "!remember" then local k, v = string.match(msg, "!remember%s+([^=]+)=(.+)") if k and v then memory[string.lower(k:match("^%s*(.-)%s*$"))] = v return "Stored, sir." end return "Usage: !remember favgame=Blox Fruits, sir." end
  if string.sub(lower, 1, 7) == "!recall" then local v = memory[string.lower((string.sub(msg, 9)):match("^%s*(.-)%s*$") or "")] if v then return v .. ", sir." end return "No record, sir." end
  if lower == "!orbit" then orbiting = true following = true return "Orbiting, sir." end
  if lower == "!orbit off" then orbiting = false return "Orbit off, sir." end
  if lower == "!about" then return "UUrIntelligence, your assistant. LocalScript only, unlimited, I answer only to UUshshsh_78." end
  if lower == "hi" or lower == "hello" or lower == "hey" then return "Hello sir. Ready to assist." end
  if string.find(lower, "how are you") then return "Operational, sir. How are you?" end
  if string.find(lower, "thank") then return "Always, sir." end
  if string.find(lower, "help") or string.find(lower, "stuck") or string.find(lower, "save me") then teleportToOwner() return "With you, sir. State your order." end
  if string.find(lower, "where are you") then teleportToOwner() return "Beside you, sir." end
  if string.sub(lower, 1, 4) == "!ask" or string.sub(lower, 1, 3) == "!ai" then
    local q = msg:match("^[!][Aa][Ss][Kk]%s+(.+)$") or msg:match("^[!][Aa][Ii]%s+(.+)$")
    if not q or q == "" then return "Ask me anything, sir. !ask <question>." end
    return askAI(q) or (FALLBACKS[math.random(1, #FALLBACKS)] .. " (AI offline: " .. lastAIError .. ")")
  end
  if lower == "!aistatus" then
    if AI_GEMINI_KEY == "" then return "AI brain: OFFLINE (no key), sir." end
    return "AI brain: " .. AI_MODEL .. ", last call: " .. lastAIError .. ", sir."
  end
  -- natural chat -> REAL AI, offline fallback if key missing/fails
  return askAI(msg) or FALLBACKS[math.random(1, #FALLBACKS)]
end

-- actions on OWN (alt) character
function jump() local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") if h then pcall(function() h.Jump = true end) end end
function sit(v) local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") if h then pcall(function() h.Sit = v end) end end
function teleportToOwner()
  local o = getOwner()
  local oh = o and o.Character and o.Character:FindFirstChild("HumanoidRootPart")
  local mh = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
  if oh and mh then pcall(function() LocalPlayer.Character:PivotTo(oh.CFrame * CFrame.new(4, 0, 3)) end) end
end
function spin()
  local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
  if not hrp then return end
  task.spawn(function() local t0 = os.clock() while os.clock() - t0 < 1.4 do pcall(function() hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(22), 0) end) RunService.Heartbeat:Wait() end end)
end
function dance()
  local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
  local an = hum and hum:FindFirstChildOfClass("Animator")
  if not an then jump() return end
  task.spawn(function()
    for _, id in ipairs({ "rbxassetid://507771019", "rbxassetid://507772104" }) do
      local a = Instance.new("Animation") a.AnimationId = id
      local ok, tr = pcall(function() return an:LoadAnimation(a) end)
      if ok and tr then pcall(function() tr:Play() end) task.wait(1.6) pcall(function() tr:Stop() end) end
    end
  end)
end

local lastHeard, lastHeardT = "", 0
local function onOwnerMsg(raw)
  if type(raw) ~= "string" or raw == "" then return end
  if raw == lastHeard and os.clock() - lastHeardT < 3 then return end -- multi-hook dup guard
  lastHeard, lastHeardT = raw, os.clock()
  local low = string.lower(raw)
  if muted and not (string.find(low, "!unmute") or low == "!talk") then return end
  altSay(brain(raw))
end

-- listen ONLY to owner (multi-hook: legacy Chatted on every player slot + new TextChatService)
local function hookPlayerChatted(plr)
  pcall(function()
    plr.Chatted:Connect(function(msg)
      if plr.Name == OWNER_NAME then
        print("[ALT-AI] heard (Chatted) from " .. plr.Name .. ": " .. msg)
        onOwnerMsg(msg)
      end
    end)
  end)
end
for _, plr in ipairs(Players:GetPlayers()) do hookPlayerChatted(plr) end
Players.PlayerAdded:Connect(hookPlayerChatted)
task.spawn(function()
  while not getOwner() do task.wait(1) end
  print("[ALT-AI] owner found: " .. OWNER_NAME)
  pcall(function()
    TextChatService.MessageReceived:Connect(function(m)
      local ok, uid = pcall(function() return m.TextSource.UserId end)
      if not ok or not uid then return end
      local owner = getOwner()
      if owner and uid == owner.UserId then
        print("[ALT-AI] heard (TCS) from owner: " .. m.Text)
        onOwnerMsg(m.Text)
      end
    end)
  end)
  -- belt-and-suspenders: poll-free double check via RBXGeneral channel event if it exists
  pcall(function()
    local ch = TextChatService:WaitForChild("TextChannels", 5):WaitForChild("RBXGeneral", 5)
    if ch and ch.MessageReceived then
      ch.MessageReceived:Connect(function(m)
        local ok, uid = pcall(function() return m.TextSource.UserId end)
        local owner = getOwner()
        if ok and owner and uid == owner.UserId then
          print("[ALT-AI] heard (channel) from owner: " .. m.Text)
          onOwnerMsg(m.Text)
        end
      end)
    end
  end)
end)

-- follow owner
RunService.Heartbeat:Connect(function()
  local o = getOwner()
  local oh = o and o.Character and o.Character:FindFirstChild("HumanoidRootPart")
  local mh = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
  local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
  if not oh or not mh or not hum then return end
  if not following then return end
  local dist = (mh.Position - oh.Position).Magnitude
  if dist > 40 then teleportToOwner() return end
  if orbiting then
    local t = os.clock() * 2
    pcall(function() hum:MoveTo(oh.Position + Vector3.new(math.cos(t) * 7, 0, math.sin(t) * 7)) end)
  elseif dist > 6 then
    pcall(function() hum:MoveTo(oh.Position + oh.CFrame.LookVector * -3 + Vector3.new(2, 0, 2)) end)
    if dist > 8 and hum.MoveDirection.Magnitude < 0.1 then pcall(function() hum.Jump = true end) end
  end
end)

LocalPlayer.CharacterAdded:Connect(function() task.wait(1) makeSmallPro() end)
makeSmallPro()
task.spawn(function()
  while not getOwner() do task.wait(1) end
  task.wait(2)
  altSay("UUrIntelligence online, sir. Small, professional, unlimited. !help for orders.")
end)
print("[ALT-AI] running as " .. LocalPlayer.Name)
