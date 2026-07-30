--[[
    Project EToH Script -- Tower Rush Auto-Completer (Obsidian UI)
    -------------------------------------------------------------
    Pick a rush; the menu lists every tower in it with its own mm:ss time input.
    Set each tower's time individually, press Start, and it walks each route,
    touches that tower's WinPad to lock the win, then advances to the next tower's
    TeleportTo -- the ToAST -> WinPad -> ToA TeleportTo flow.

    Load:
        loadstring(game:HttpGet("https://raw.githubusercontent.com/cslp1/Project-EToH-Script/refs/heads/main/TowerRushUI.lua"))()
]]

if _G.TowerRushUILoaded then
    warn("[TowerRush UI] already loaded")
    return
end

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VIM          = game:GetService("VirtualInputManager")
local player       = Players.LocalPlayer

local baseRepo    = "https://raw.githubusercontent.com/cslp1/Project-EToH-Script/refs/heads/main/Games/EToH/"
local registryUrl = baseRepo .. "TowerRegistry.lua"

-- Pinned Obsidian commit (matches your main script's pin).
local obsidianRepo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/398653c103a0b4a8d2a3b68bcd383af21814a512/"

-- Cache-buster so GitHub raw can't serve a stale route/registry.
local function fetch(url)
    local src
    local ok = pcall(function() src = game:HttpGet(url .. "?cb=" .. tostring(os.time())) end)
    if ok and type(src) == "string" and #src > 0 then return src end
    return nil
end

-- ===== Load Obsidian =====
local Library
do
    local ok, lib = pcall(function()
        return loadstring(game:HttpGet(obsidianRepo .. "Library.lua"))()
    end)
    if not ok or type(lib) ~= "table" or not lib.CreateWindow then
        warn("[TowerRush UI] failed to load Obsidian: " .. tostring(lib))
        return
    end
    Library = lib
end

-- ===== Registry =====
local Registry
do
    for attempt = 1, 4 do
        local src = fetch(registryUrl)
        if src then
            local fn = loadstring(src)
            if fn then
                local ok, result = pcall(fn)
                if ok and type(result) == "table" and type(result.Towers) == "table" then
                    Registry = result
                    break
                end
            end
        end
        if attempt < 4 then task.wait(0.75) end
    end
    if not Registry then
        Library:Notify({ Title = "Tower Rush", Description = "Failed to load registry.", Time = 6 })
        return
    end
end

-- name -> { category, sec }
local TowerInfo = {}
for _, t in ipairs(Registry.Towers or {}) do
    TowerInfo[t.name] = {
        category = t.category,
        sec = (tonumber(t.suggestedTime.min) or 0) * 60 + (tonumber(t.suggestedTime.sec) or 0),
    }
end
-- rush acronym -> { category, sec }
local RushInfo, RushNames = {}, {}
for _, tr in ipairs(Registry.TowerRush or {}) do
    RushInfo[tr.name] = {
        category = tr.category,
        sec = (tonumber(tr.suggestedTime.min) or 0) * 60 + (tonumber(tr.suggestedTime.sec) or 0),
    }
    RushNames[#RushNames + 1] = tr.name
end
table.sort(RushNames)

-- ===== Geometry / resolution helpers =====
local PLAYER_FOOT_OFFSET = 3
local function getTopPos(part)
    local cf, size = part.CFrame, part.Size
    local halfTop = 0.5 * (
        math.abs(cf.UpVector.Y)    * size.Y +
        math.abs(cf.RightVector.Y) * size.X +
        math.abs(cf.LookVector.Y)  * size.Z
    )
    return part.Position + Vector3.new(0, halfTop + PLAYER_FOOT_OFFSET, 0)
end
local function towerFolder(name)
    local towers = workspace:FindFirstChild("Towers")
    return towers and towers:FindFirstChild(name)
end
-- Keep (L)/(C)/(M); only strip ":SE" style suffixes.
local function folderName(name)
    local colon = name:find(":")
    return colon and name:sub(1, colon - 1) or name
end
local function resolveTeleportTo(name)
    local f = towerFolder(folderName(name))
    if not f then return nil end
    local tp    = f:FindFirstChild("Teleporter")
    local exact = tp and tp:FindFirstChild("TeleportTo")
    if exact and exact:IsA("BasePart") then return exact end
    local any = f:FindFirstChild("TeleportTo", true)
    return (any and any:IsA("BasePart")) and any or nil
end
local function resolveWinPad(name)
    local f = towerFolder(folderName(name))
    if not f then return nil end
    local wp = f:FindFirstChild("WinPad", true)
    return (wp and wp:IsA("BasePart")) and wp or nil
end
local function rushTeleporter(rushName)
    local ok, part = pcall(function()
        local tower = workspace.Towers[rushName]
        local ok1, tp1 = pcall(function() return tower.Teleporter.Teleporter.Teleport end)
        if ok1 and tp1 then return tp1 end
        local ok2, tp2 = pcall(function() return tower.Teleporter.Teleporter.TowerRushPortal.Teleport end)
        if ok2 and tp2 then return tp2 end
        return nil
    end)
    return ok and part or nil
end

-- ===== Fetch a rush's tower list =====
local function getRushTowerList(rushName)
    local rush = RushInfo[rushName]
    if not rush then return nil end
    local src = fetch(baseRepo .. rush.category .. "/" .. rushName .. ".lua")
    if not src then return nil end
    local fn = loadstring(src)
    if not fn then return nil end
    local ok, getList = pcall(fn)
    if not ok or type(getList) ~= "function" then return nil end
    local ok2, list = pcall(getList)
    if not ok2 or type(list) ~= "table" then return nil end
    return list
end

-- ===== Run state =====
local running = false

local function characterHrp()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart"), char
end

local function moveToPart(part, timeout)
    local hrp, char = characterHrp()
    if not hrp then return false end
    local touched = false
    local conn = part.Touched:Connect(function(hit)
        if char and hit:IsDescendantOf(char) then touched = true end
    end)
    local deadline = os.clock() + (timeout or 6)
    while running and not touched and os.clock() < deadline do
        hrp, char = characterHrp()
        if not hrp then break end
        if (hrp.Position - part.Position).Magnitude < 8 then touched = true break end
        hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0)) * (hrp.CFrame - hrp.CFrame.Position)
        task.wait(0.1)
    end
    conn:Disconnect()
    return touched
end

local function resolveSteps(towerName, category)
    local src = fetch(baseRepo .. category .. "/" .. towerName .. ".lua")
    if not src then return nil, "fetch failed" end
    local fn = loadstring(src)
    if not fn then return nil, "parse failed" end
    local ok, getCheckpoints = pcall(fn)
    if not ok or type(getCheckpoints) ~= "function" then return nil, "load failed" end
    local checkpoints
    local deadline = os.clock() + 8
    repeat
        local ok2, result = pcall(getCheckpoints)
        if ok2 and type(result) == "table" and #result > 0 then checkpoints = result end
        if not checkpoints then task.wait(0.1) end
    until checkpoints or os.clock() > deadline or not running
    if not checkpoints then return nil, "no checkpoints" end
    local hrp = characterHrp()
    local prevPos = hrp and hrp.Position or Vector3.zero
    local steps = {}
    for _, step in ipairs(checkpoints) do
        if step == "jump" then
            table.insert(steps, { type = "jump" })
        else
            local target = typeof(step) == "Instance" and step or (type(step) == "table" and step.target)
            if target and target:IsA("BasePart") then
                local destPos = getTopPos(target)
                table.insert(steps, { type = "tween", target = target, destPos = destPos, dist = (destPos - prevPos).Magnitude })
                prevPos = destPos
            end
        end
    end
    return steps
end

local function walkSteps(steps, budget)
    local remaining, cum = {}, 0
    for i = #steps, 1, -1 do
        if steps[i].type ~= "jump" then cum = cum + (steps[i].dist or 0) end
        remaining[i] = cum
    end
    local deadline = os.clock() + math.max(budget, 1)
    for i, step in ipairs(steps) do
        if not running then return false end
        local hrp, char = characterHrp()
        if not hrp then return false end
        if step.type == "jump" then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum.Jump = true end
        else
            local dist     = (step.destPos - hrp.Position).Magnitude
            local timeLeft = math.max(deadline - os.clock(), 0.001)
            local remDist  = remaining[i]
            local stepTime = math.max(remDist > 0 and (timeLeft * (dist / remDist)) or 0.05, 0.05)
            local dest  = CFrame.new(step.destPos) * (hrp.CFrame - hrp.CFrame.Position)
            local tween = TweenService:Create(hrp, TweenInfo.new(stepTime, Enum.EasingStyle.Linear), { CFrame = dest })
            local done  = false
            tween.Completed:Connect(function() done = true end)
            tween:Play()
            while running and not done do
                if not characterHrp() then tween:Cancel() return false end
                task.wait()
            end
            tween:Cancel()
        end
    end
    return true
end

local function touchWinPad(towerName)
    local wp = resolveWinPad(towerName)
    if not wp then return false end
    local hrp = characterHrp()
    if not hrp then return false end
    hrp.CFrame = wp.CFrame + Vector3.new(0, 3, 0)
    if firetouchinterest then
        for _ = 1, 3 do
            pcall(function()
                firetouchinterest(wp, hrp, 0)
                firetouchinterest(wp, hrp, 1)
            end)
            task.wait(0.1)
        end
    else
        task.wait(1.5)
    end
    return true
end

-- ===== UI =====
local Window = Library:CreateWindow({
    Title         = "Tower Rush Auto",
    Footer        = "Project EToH Script",
    NotifySide    = "Right",
    ToggleKeybind = Enum.KeyCode.RightControl,
    AutoShow      = true,
})
local Tab     = Window:AddTab("Rush", "zap")
local Options = Library.Options
local Toggles = Library.Toggles

local PickBox  = Tab:AddLeftGroupbox("Select Rush")
local TimesBox = Tab:AddRightGroupbox("Per-Tower Times (mm:ss)")

-- Fixed pool of inputs; only the current rush's towers are shown. SetVisible works on
-- this Obsidian build (Input template has Visible + Input:SetVisible is defined).
local MAX_TOWERS = 30
local timeInputs = {}     -- index -> option id string
local currentList = {}    -- current rush's tower names, in order
local perTowerValues = {} -- "rushName|towerName" -> "mm:ss", persists across rush switches

local function parseTime(str, fallback)
    if not str or str == "" then return fallback end
    local m, s = str:match("^(%d+):(%d+)$")
    if m then return tonumber(m) * 60 + tonumber(s) end
    local n = tonumber(str)
    if n then return n end
    return fallback
end
local function fmtTime(sec)
    return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

for i = 1, MAX_TOWERS do
    local id = "RushTime" .. i
    TimesBox:AddInput(id, {
        Text        = "-",
        Default     = "",
        Numeric     = false,
        Placeholder = "mm:ss",
        Visible     = false,
        Callback    = function(value)
            local name = currentList[i]
            if name then
                local rush = Options.RushSelect and Options.RushSelect.Value or ""
                perTowerValues[rush .. "|" .. name] = value
            end
        end,
    })
    timeInputs[i] = id
end

local statusLabel

local function rebuildTimes(rushName)
    currentList = getRushTowerList(rushName) or {}
    for i = 1, MAX_TOWERS do
        local name = currentList[i]
        local opt  = Options[timeInputs[i]]
        if opt then
            if name then
                local key       = rushName .. "|" .. name
                local suggested = TowerInfo[name] and TowerInfo[name].sec or 360
                local existing  = perTowerValues[key]
                local shown     = (existing and existing ~= "") and existing or fmtTime(suggested)
                perTowerValues[key] = shown
                opt:SetText(("%d. %s"):format(i, name))
                opt:SetVisible(true)
                opt:SetValue(shown)
            else
                opt:SetVisible(false)
            end
        end
    end
    if statusLabel then
        statusLabel:SetText(("Loaded %s -- %d towers."):format(rushName, #currentList))
    end
end

PickBox:AddDropdown("RushSelect", {
    Text     = "Rush",
    Values   = RushNames,
    Default  = RushNames[1],
    Callback = function(value) rebuildTimes(value) end,
})

statusLabel = PickBox:AddLabel("Pick a rush to load its towers.", true)

PickBox:AddButton({
    Text    = "Reset Times to Suggested",
    Tooltip = "Set every tower's time back to its registry suggested time.",
    Callback = function()
        local rushName = Options.RushSelect.Value
        for _, name in ipairs(currentList) do
            perTowerValues[rushName .. "|" .. name] = nil
        end
        rebuildTimes(rushName)
        Library:Notify({ Title = "Tower Rush", Description = "Times reset to suggested.", Time = 3 })
    end,
})

-- ===== Runner =====
local function runRush(rushName)
    if running then return end
    local rush = RushInfo[rushName]
    if not rush then
        Library:Notify({ Title = "Tower Rush", Description = "Unknown rush.", Time = 4 })
        return
    end
    local list = currentList
    if #list == 0 then list = getRushTowerList(rushName) or {} end
    if #list == 0 then
        Library:Notify({ Title = "Tower Rush", Description = "Couldn't load tower list.", Time = 5 })
        return
    end

    running = true
    if statusLabel then statusLabel:SetText("Running " .. rushName .. "...") end

    local noclipConn = RunService.Stepped:Connect(function()
        local char = player.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
            end
        end
    end)
    local function cleanup()
        running = false
        if noclipConn then noclipConn:Disconnect() noclipConn = nil end
        local char = player.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = false end
        if statusLabel then statusLabel:SetText("Idle. Loaded " .. rushName .. ".") end
    end

    local rushTp = rushTeleporter(rushName)
    if rushTp then moveToPart(rushTp, 6) end
    task.wait(0.5)

    for idx, towerName in ipairs(list) do
        if not running then break end
        local info     = TowerInfo[towerName]
        local category = info and info.category or rush.category
        local key      = rushName .. "|" .. towerName
        local budget   = parseTime(perTowerValues[key], info and info.sec or 360)

        if idx > 1 then
            local tpTo = resolveTeleportTo(towerName)
            if tpTo then
                moveToPart(tpTo, 6)
                local hrp = characterHrp()
                local posBefore = hrp and hrp.Position
                VIM:SendKeyEvent(true, Enum.KeyCode.W, false, game)
                local t0 = os.clock()
                repeat task.wait(0.1)
                    hrp = characterHrp()
                until (not running)
                    or (hrp and posBefore and (hrp.Position - posBefore).Magnitude > 0.1)
                    or os.clock() - t0 > 3
                VIM:SendKeyEvent(false, Enum.KeyCode.W, false, game)
            end
        end
        if not running then break end

        Library:Notify({ Title = "Tower Rush", Description = ("(%d/%d) %s -- %s"):format(idx, #list, towerName, fmtTime(budget)), Time = 3 })
        local steps, err = resolveSteps(towerName, category)
        if steps then
            walkSteps(steps, budget)
        else
            warn(("[TowerRush] %s: %s"):format(towerName, tostring(err)))
        end
        if not running then break end

        if touchWinPad(towerName) then
            Library:Notify({ Title = "Tower Rush", Description = towerName .. " complete!", Time = 2 })
        else
            warn(("[TowerRush] %s: no WinPad found"):format(towerName))
        end
        task.wait(0.5)
    end

    cleanup()
    Library:Notify({ Title = "Tower Rush", Description = "Rush finished: " .. rushName, Time = 5 })
end

local ControlBox = Tab:AddLeftGroupbox("Control")
ControlBox:AddButton({
    Text    = "Start Rush",
    Tooltip = "Walk each tower for its set time, touch its WinPad, then advance.",
    Callback = function()
        if running then
            Library:Notify({ Title = "Tower Rush", Description = "Already running.", Time = 3 })
            return
        end
        local rushName = Options.RushSelect.Value
        task.spawn(function() runRush(rushName) end)
    end,
})
ControlBox:AddButton({
    Text    = "Stop Rush",
    Tooltip = "Stop after the current step.",
    Callback = function()
        running = false
        Library:Notify({ Title = "Tower Rush", Description = "Stopping...", Time = 3 })
    end,
})
ControlBox:AddButton({
    Text    = "Unload",
    Callback = function()
        running = false
        _G.TowerRushUILoaded = nil
        Library:Unload()
    end,
})

-- Initial population.
if RushNames[1] then rebuildTimes(RushNames[1]) end

_G.TowerRushUILoaded = true
Library:Notify({ Title = "Tower Rush", Description = "Loaded. Pick a rush and set each tower's time.", Time = 5 })
