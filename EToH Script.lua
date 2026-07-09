if _G.ProjectEToHLoaded then
    warn("[Project EToH Script] Already loaded!")
    return
end

local autoExecuteFile = "ProjectEToHScript/auto_execute.txt"
local uiStyleFile = "ProjectEToHScript/ui_style.txt"
local autoExecuteDefault = false
pcall(function()
    if isfile(autoExecuteFile) then
        autoExecuteDefault = readfile(autoExecuteFile) == "true"
    end
end)
local uiStyle = "Obsidian"
pcall(function()
    if isfile(uiStyleFile) then
        uiStyle = readfile(uiStyleFile)
    end
end)

local repo
if uiStyle == "Linoria" then
    repo = "https://raw.githubusercontent.com/mstudio45/LinoriaLib/main/"
else
    repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
end
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()

local function missing(t, f, fallback)
    if type(f) == t then return f end
    return fallback
end

local okHook, errHook = pcall(function() hookmetamethod = missing("function", hookmetamethod) end)
local okNcm,  errNcm  = pcall(function() getnamecallmethod = missing("function", getnamecallmethod or get_namecall_method) end)
local queueteleport   = missing("function", queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport))

local sUNCSupport = {
    hookmetamethod    = okHook and hookmetamethod ~= nil,
    getnamecallmethod = okNcm  and getnamecallmethod ~= nil,
    queueteleport     = queueteleport ~= nil,
}
sUNCSupport.Godmode = sUNCSupport.hookmetamethod and sUNCSupport.getnamecallmethod

print("[Project EToH Script] Functions Check:")
print("[Project EToH Script] Metatable Library:")
print((sUNCSupport.hookmetamethod    and "✅" or "❌") .. " hookmetamethod"    .. (not okHook and ": " .. tostring(errHook) or ""))
print((sUNCSupport.getnamecallmethod and "✅" or "❌") .. " getnamecallmethod" .. (not okNcm  and ": " .. tostring(errNcm)  or ""))
print("[Project EToH Script] Miscellaneous Library:")
print((sUNCSupport.queueteleport     and "✅" or "❌") .. " queueonteleport")
local HttpService = game:GetService("HttpService")
local version = "Unknown"
local ok, result = pcall(function()
    local data = HttpService:JSONDecode(game:HttpGet("https://raw.githubusercontent.com/cslp1/Project-EToH-Script/refs/heads/main/version.json"))
    return data.version
end)
if ok and result then version = result end
local Window = Library:CreateWindow({
    Title         = "Project EToH Script",
    Footer        = "Game: Eternal Towers of Hell | Version " .. version,
    NotifySide    = "Right",
    ToggleKeybind = Enum.KeyCode.RightShift,
    AutoShow      = true,
})
local isDev = game:GetService("Players").LocalPlayer.Name == "MaybeIsRealZack"

local Tabs = {
    Main       = Window:AddTab("Main",        "zap"),
    UISettings = Window:AddTab("UI Settings", "settings"),
    Logs       = Window:AddTab("Logs",        "list"),
}
local Options  = Library.Options

-- ===== Action Log (Logs tab) =====
local logLines      = {}
local MAX_LOG_LINES = 25
local LogBox        = Tabs.Logs:AddLeftGroupbox("Action Log")
local LogLabel      = LogBox:AddLabel({ Text = "(no actions yet)", DoesWrap = true })

local function logAction(msg)
    logLines[#logLines + 1] = ("[%s] %s"):format(os.date("%X"), tostring(msg))
    while #logLines > MAX_LOG_LINES do table.remove(logLines, 1) end
    local ordered = {}
    for i = #logLines, 1, -1 do ordered[#ordered + 1] = logLines[i] end
    LogLabel:SetText(table.concat(ordered, "\n"))
end
_G.logAction = logAction

LogBox:AddButton({
    Text     = "Clear Logs",
    Callback = function()
        table.clear(logLines)
        LogLabel:SetText("(no actions yet)")
    end,
})

do
    local rawNotify = Library.Notify
    Library.Notify = function(self, ...)
        local first = select(1, ...)
        local line
        if typeof(first) == "table" then
            local title, desc = first.Title, first.Description
            if title and title ~= "" and tostring(title) ~= "nil" then
                line = tostring(title) .. ": " .. tostring(desc)
            else
                line = tostring(desc)
            end
        else
            line = tostring(first)
        end
        pcall(logAction, line)
        return rawNotify(self, ...)
    end
end
local isAutoPlaying = false
local currentResolvedSteps = nil
local startAutoPlay -- forward declaration
local autoPlayStop = false

local baseRepo = "https://raw.githubusercontent.com/cslp1/Project-EToH-Script/refs/heads/main/Games/EToH/"
local registryUrl = "https://raw.githubusercontent.com/cslp1/Project-EToH-Script/refs/heads/main/Games/EToH/TowerRegistry.lua"

local Registry
local registryLoaded = false
for attempt = 1, 4 do
    local ok_reg, reg_src = pcall(function() return game:HttpGet(registryUrl) end)
    if ok_reg and type(reg_src) == "string" and #reg_src > 0 then
        local fn = loadstring(reg_src)
        if fn then
            local ok2, result = pcall(fn)
            if ok2 and type(result) == "table" and type(result.Towers) == "table" then
                Registry = result
                registryLoaded = true
                break
            end
        end
    end
    if attempt < 4 then task.wait(0.75) end
end
if not Registry then
    Registry = {
        Categories = { Ring1 = 9070657865, Ring2 = 9070979698 },
        Towers = {},
        TowerRush = {},
    }
end

local SuggestedTimes = {}
local TowerConfigs   = {}
local DropdownValues = {}

local function getTpFrameName(name)
    local colonPos = name:find(":")
    return colonPos and name:sub(1, colonPos - 1) or name
end

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

local currentPlaceId = game.PlaceId

local function towerFolderPresent(name)
    local towersFolder = workspace:FindFirstChild("Towers")
    return towersFolder ~= nil and towersFolder:FindFirstChild(name) ~= nil
end

local function towerFolder(name)
    local towersFolder = workspace:FindFirstChild("Towers")
    return towersFolder and towersFolder:FindFirstChild(name)
end

-- The Eternal Abyss (and other JToH-kit games) expose a single entry part at
-- workspace.Towers.<tower>.Portal instead of Teleporter.Teleporter.TPFRAME +
-- Teleporter.TeleportTo. It may be a BasePart directly, or a Model wrapping one.
local function resolvePortalPart(name)
    local f = towerFolder(name)
    if not f then return nil end
    local portal = f:FindFirstChild("Portal")
    if not portal then return nil end
    if portal:IsA("BasePart") then return portal end
    return portal:FindFirstChildWhichIsA("BasePart", true)
end

-- Fire a part's TouchInterest if the executor supports it. Portals teleport on touch,
-- so standing on them isn't always enough -- especially while noclip is on and the
-- character never physically collides with anything.
local function fireTouch(part, hrp)
    if not (firetouchinterest and part and hrp) then return end
    pcall(function()
        firetouchinterest(part, hrp, 0)
        firetouchinterest(part, hrp, 1)
    end)
end

local function resolveTPFrame(name)
    local f = towerFolder(name)
    if not f then return nil end
    local tp    = f:FindFirstChild("Teleporter")
    local inner = tp and tp:FindFirstChild("Teleporter")
    local exact = inner and inner:FindFirstChild("TPFRAME")
    return exact or f:FindFirstChild("TPFRAME", true) or resolvePortalPart(name)
end
local function resolveTeleportTo(name)
    local f = towerFolder(name)
    if not f then return nil end
    local tp    = f:FindFirstChild("Teleporter")
    local exact = tp and tp:FindFirstChild("TeleportTo")
    return exact or f:FindFirstChild("TeleportTo", true) or resolvePortalPart(name)
end

-- Fallback route: when a tower has no route file on the repo (e.g. TEA towers), build
-- one from the tower's own checkpoint parts. Auto Play noclips and tweens the
-- HumanoidRootPart straight between targets, so a checkpoint-only route usually still
-- clears the tower -- it just cuts through geometry instead of following the intended
-- path. Numbered checkpoints are used in order; unnumbered ones are ordered by height,
-- which assumes the tower goes upward. Returns nil if nothing usable is found.
local function generateCheckpointRoute(folderName)
    local f = towerFolder(folderName)
    if not f then return nil end
    local numbered, plain, winpad = {}, {}, nil
    for _, d in ipairs(f:GetDescendants()) do
        if d:IsA("BasePart") then
            local lower = d.Name:lower()
            local num = lower:match("^checkpoint%s*(%d+)$")
            if num then
                numbered[#numbered + 1] = { part = d, index = tonumber(num) }
            elseif lower == "checkpoint" then
                plain[#plain + 1] = d
            elseif lower == "winpad" and not winpad then
                winpad = d
            end
        end
    end
    local ordered = {}
    if #numbered > 0 then
        table.sort(numbered, function(a, b) return a.index < b.index end)
        for _, e in ipairs(numbered) do ordered[#ordered + 1] = e.part end
    elseif #plain > 0 then
        table.sort(plain, function(a, b) return a.Position.Y < b.Position.Y end)
        for _, p in ipairs(plain) do ordered[#ordered + 1] = p end
    end
    if winpad then ordered[#ordered + 1] = winpad end
    if #ordered == 0 then return nil end
    return function() return ordered end, #ordered, (winpad ~= nil)
end

local function warnTowerStructure(name)
    local f = towerFolder(name)
    if not f then
        warn(("[Auto Play] no folder named '%s' in workspace.Towers"):format(name))
        return
    end
    local kids = {}
    for _, c in ipairs(f:GetChildren()) do kids[#kids + 1] = c.Name end
    warn(("[Auto Play] '%s' teleporter unresolved. Children: %s"):format(name, table.concat(kids, ", ")))
end

local function placeMatches(ids)
    if type(ids) == "table" then
        for _, id in ipairs(ids) do
            if id == currentPlaceId then return true end
        end
        return false
    end
    return ids == currentPlaceId
end

local function entryMatchesPlace(entry)
    if entry.places ~= nil then
        return placeMatches(entry.places)
    end
    return placeMatches(Registry.Categories[entry.category])
end

local placeIsKnown = false
for _, ids in pairs(Registry.Categories or {}) do
    if placeMatches(ids) then
        placeIsKnown = true
        break
    end
end

local function shouldShow(entry, folderName)
    if entryMatchesPlace(entry) then return true end
    return (not placeIsKnown) and towerFolderPresent(folderName)
end

for _, tower in ipairs(Registry.Towers or {}) do
    local n = tower.name
    local tpName = getTpFrameName(n)
    if not shouldShow(tower, tpName) then continue end
    SuggestedTimes[n] = tower.suggestedTime
    TowerConfigs[n] = {
        tpFrame    = function() return resolveTPFrame(tpName) end,
        teleportTo = function() return resolveTeleportTo(tpName) end,
        routeUrl   = baseRepo .. tower.category .. "/" .. n .. ".lua",
        folderName = tpName,
    }
    table.insert(DropdownValues, n)
end

for _, tr in ipairs(Registry.TowerRush or {}) do
    local n = tr.name
    if not shouldShow(tr, n) then continue end
    SuggestedTimes[n] = tr.suggestedTime
    TowerConfigs[n] = {
        tpFrame = function()
            local tower = workspace.Towers[n]
            local ok1, tp1 = pcall(function() return tower.Teleporter.Teleporter.Teleport end)
            if ok1 and tp1 then return tp1 end
            local ok2, tp2 = pcall(function() return tower.Teleporter.Teleporter.TowerRushPortal.Teleport end)
            if ok2 and tp2 then return tp2 end
            return nil
        end,
        routeUrl    = baseRepo .. tr.category .. "/" .. n .. ".lua",
        isTowerRush = true,
        folderName  = n,
    }
    table.insert(DropdownValues, n)
end

-- Any tower loaded in workspace.Towers with a Portal but no registry entry (TEA towers)
-- gets a config built on the fly, so it can be picked in Select Tower and Auto Played.
do
    local towersFolder = workspace:FindFirstChild("Towers")
    if towersFolder then
        for _, t in ipairs(towersFolder:GetChildren()) do
            if not TowerConfigs[t.Name] and t:FindFirstChild("Portal") then
                local n = t.Name
                TowerConfigs[n] = {
                    tpFrame    = function() return resolvePortalPart(n) end,
                    teleportTo = function() return resolvePortalPart(n) end,
                    routeUrl   = nil, -- no route file: falls back to checkpoint route
                    folderName = n,
                    isPortal   = true,
                }
                table.insert(DropdownValues, n)
            end
        end
    end
end

if #DropdownValues == 0 then
    local towersFolder = workspace:FindFirstChild("Towers")
    local loadedCount = towersFolder and #towersFolder:GetChildren() or 0
    local reason = registryLoaded
        and "The registry may be out of date for this game version."
        or "Couldn't fetch the tower registry (network/HttpGet) -- try re-executing the script."
    Library:Notify({
        Title       = "Project EToH Script",
        Description  = ("No towers found (PlaceId %s, registry towers: %d, loaded in workspace.Towers: %d). %s")
            :format(tostring(currentPlaceId), #(Registry.Towers or {}), loadedCount, reason),
        Duration    = 10,
    })
end

local TowerBox = Tabs.Main:AddLeftGroupbox("Towers")
local AllJumpBox = Tabs.Main:AddLeftGroupbox("All Jump Mode")
local function getSuggestedLabel(tower)
    tower = tower or "NEAT"
    local t = SuggestedTimes[tower]
    if t then
        return tower .. " Suggested Time: " .. t.min .. ":" .. (t.sec == "0" and "00" or t.sec)
    end
    return "No suggested time available"
end
local SuggestedLabel
TowerBox:AddDropdown("TowerSelect", {
    Text    = "Select Tower",
    Values  = DropdownValues,
    Default = DropdownValues[1] or "NEAT",
    Callback = function(value)
        if Library.Toggles.UseSuggestedTime.Value then
            local t = SuggestedTimes[value]
            if t then
                Library.Options.CompletionMin:SetValue(t.min)
                Library.Options.CompletionSec:SetValue(t.sec)
            end
        end
        SuggestedLabel:SetText(getSuggestedLabel(value))
        Library.Toggles.UseSuggestedTime:SetDisabled(false)
        Library.Options.CompletionMin:SetDisabled(not Library.Toggles.UseSuggestedTime.Value)
        Library.Options.CompletionSec:SetDisabled(not Library.Toggles.UseSuggestedTime.Value)
    end,
})
TowerBox:AddToggle("UseSuggestedTime", {
    Text    = "Use Suggested Time",
    Default = true,
    Callback = function(state)
        Library.Options.CompletionMin:SetDisabled(state)
        Library.Options.CompletionSec:SetDisabled(state)
        if state then
            local t = SuggestedTimes[Library.Options.TowerSelect.Value]
            if t then
                Library.Options.CompletionMin:SetValue(t.min)
                Library.Options.CompletionSec:SetValue(t.sec)
            end
        end
    end,
})
SuggestedLabel = TowerBox:AddLabel(getSuggestedLabel("NEAT"))
TowerBox:AddInput("CompletionMin", {
    Text        = "Completion Time (min)",
    Default     = "3",
    Numeric     = true,
    Placeholder = "3",
})
TowerBox:AddInput("CompletionSec", {
    Text        = "Completion Time (s)",
    Default     = "0",
    Numeric     = true,
    Placeholder = "0",
})
TowerBox:AddInput("RepeatCount", {
    Text        = "Repeat Count",
    Default     = "1",
    Numeric     = true,
    Placeholder = "1",
    Tooltip     = "Auto Play the tower this many times.",
})
local routeHighlights = {}
local routeUpdateConn = nil

local function clearRouteHighlights()
    if routeUpdateConn then
        routeUpdateConn:Disconnect()
        routeUpdateConn = nil
    end
    for _, obj in ipairs(routeHighlights) do
        obj:Destroy()
    end
    routeHighlights = {}
end

local MAX_SIZE = 2048

local function buildSegmentParts(folder, a, b)
    local parts = {}
    local dir  = (b - a)
    local dist = dir.Magnitude
    if dist <= 0 then return parts end
    local segments = math.ceil(dist / MAX_SIZE)
    for s = 0, segments - 1 do
        local segStart = a + dir * (s / segments)
        local segEnd   = a + dir * ((s + 1) / segments)
        local segMid   = (segStart + segEnd) / 2
        local segDist  = (segEnd - segStart).Magnitude
        local part = Instance.new("Part")
        part.Anchored     = true
        part.CanCollide   = false
        part.CastShadow   = false
        part.Size         = Vector3.new(0.3, 0.3, segDist)
        part.CFrame       = CFrame.lookAt(segMid, segEnd)
        part.Material     = Enum.Material.Neon
        part.Color        = Options.RouteColor and Options.RouteColor.Value or Color3.fromRGB(0, 255, 0)
        part.Transparency = 0
        part.Parent       = folder
        table.insert(parts, part)
    end
    return parts
end

local function showRoute(resolvedSteps)
    clearRouteHighlights()
    if not resolvedSteps then return end

    local points = {}
    for _, step in ipairs(resolvedSteps) do
        if step.type ~= "jump" and step.destPos then
            table.insert(points, { pos = step.destPos, target = step.target })
        end
    end

    local folder = Instance.new("Folder")
    folder.Name   = "RouteHighlight"
    folder.Parent = workspace
    table.insert(routeHighlights, folder)

    local links = {}
    for i = 1, #points - 1 do
        local a, b = points[i], points[i + 1]
        local posA = (a.target and a.target.Parent) and getTopPos(a.target) or a.pos
        local posB = (b.target and b.target.Parent) and getTopPos(b.target) or b.pos
        local link = { posA = posA, posB = posB, targetA = a.target, targetB = b.target, parts = {} }
        link.parts = buildSegmentParts(folder, link.posA, link.posB)
        for _, p in ipairs(link.parts) do table.insert(routeHighlights, p) end
        if link.targetA or link.targetB then
            table.insert(links, link)
        end
    end

    if #links > 0 then
        local RunService = game:GetService("RunService")
        local lastCheck  = 0
        routeUpdateConn = RunService.Heartbeat:Connect(function()
            if os.clock() - lastCheck < 0.1 then return end
            lastCheck = os.clock()
            for _, link in ipairs(links) do
                local a = link.posA
                local b = link.posB
                if link.targetA and link.targetA.Parent then
                    a = getTopPos(link.targetA)
                end
                if link.targetB and link.targetB.Parent then
                    b = getTopPos(link.targetB)
                end
                if (a - link.posA).Magnitude > 0.1 or (b - link.posB).Magnitude > 0.1 then
                    for _, p in ipairs(link.parts) do
                        p:Destroy()
                        for idx, h in ipairs(routeHighlights) do
                            if h == p then table.remove(routeHighlights, idx) break end
                        end
                    end
                    link.posA  = a
                    link.posB  = b
                    link.parts = buildSegmentParts(folder, a, b)
                    for _, p in ipairs(link.parts) do table.insert(routeHighlights, p) end
                end
            end
        end)
    end
end

-- Resolve a tower's checkpoint provider: the repo route file if it has one, otherwise
-- the generated checkpoint route. Returns getCheckpoints (a function) or nil + reason.
local function resolveCheckpointProvider(name, config)
    if config.routeUrl then
        local routeSrc
        local okFetch = pcall(function() routeSrc = game:HttpGet(config.routeUrl) end)
        if okFetch and routeSrc then
            local fn = loadstring(routeSrc)
            if fn then
                local okLoad, getCheckpoints = pcall(fn)
                if okLoad and type(getCheckpoints) == "function" then
                    return getCheckpoints, "route file"
                end
            end
        end
    end
    local gen, count = generateCheckpointRoute(config.folderName or getTpFrameName(name))
    if gen then
        return gen, ("generated route (%d checkpoints)"):format(count)
    end
    return nil, "no route file and no checkpoint parts found in the tower"
end

local ShowRouteToggle = TowerBox:AddToggle("ShowRoute", {
    Text    = "Show Route",
    Default = false,
    Tooltip = "Show route with parts connecting each checkpoint",
    Callback = function(state)
        if state then
            if isAutoPlaying and currentResolvedSteps then
                showRoute(currentResolvedSteps)
                return
            end
            local selected = Library.Options.TowerSelect.Value
            local config   = TowerConfigs[selected]
            if not config then return end
            local getCheckpoints = resolveCheckpointProvider(selected, config)
            if not getCheckpoints then return end
            local ok3, checkpoints = pcall(getCheckpoints)
            if not ok3 or type(checkpoints) ~= "table" then return end
            local steps = {}
            local prevPos = game:GetService("Players").LocalPlayer.Character and
                game:GetService("Players").LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and
                game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.Position or Vector3.zero
            for _, step in ipairs(checkpoints) do
                if step == "jump" then
                    table.insert(steps, { type = "jump" })
                    continue
                end
                local target = typeof(step) == "Instance" and step or (type(step) == "table" and step.target)
                if target and target:IsA("BasePart") then
                    local destPos = getTopPos(target)
                    table.insert(steps, { type = "tween", target = target, destPos = destPos, dist = (destPos - prevPos).Magnitude })
                    prevPos = destPos
                end
            end
            showRoute(steps)
        else
            clearRouteHighlights()
        end
    end,
})
ShowRouteToggle:AddColorPicker("RouteColor", {
    Default  = Color3.fromRGB(0, 255, 0),
    Title    = "Route Color",
    Callback = function(value)
        for _, obj in ipairs(routeHighlights) do
            if obj:IsA("Part") then
                obj.Color = value
            end
        end
    end,
})

local function getLobbyReturnPart()
    local misc = workspace:FindFirstChild("Misc")
    local part = misc and misc:FindFirstChild("RestartBrick")
    if part then return part end
    return workspace:FindFirstChild("RestartBrick", true)
end

local function returnToLobby()
    local player = game:GetService("Players").LocalPlayer
    task.wait(5)
    local part = getLobbyReturnPart()
    local char = player.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if part and hrp then
        hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0)
        if firetouchinterest then
            for _ = 1, 3 do
                fireTouch(part, hrp)
                task.wait(0.1)
            end
        else
            local stop = os.clock() + 1
            repeat
                char = player.Character
                hrp  = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then hrp.CFrame = part.CFrame end
                task.wait(0.1)
            until os.clock() >= stop
        end
    end
    task.wait(5)
end

TowerBox:AddToggle("AutoReturnToLobby", {
    Text    = "Return to Lobby",
    Default = false,
    Tooltip = "Automatically return to lobby when you win",
    Callback = function(state)
        if state then
            local player = game:GetService("Players").LocalPlayer
            if not player then return end

            if _G.returnToLobbyConn then
                _G.returnToLobbyConn:Disconnect()
                _G.returnToLobbyConn = nil
            end

            _G.returnToLobbyConn = player:GetPropertyChangedSignal("Team"):Connect(function()
                local winnerTeam = game:GetService("Teams"):FindFirstChild("Winner!")
                if player.Team == winnerTeam then
                    returnToLobby()
                end
            end)
        else
            if _G.returnToLobbyConn then
                _G.returnToLobbyConn:Disconnect()
                _G.returnToLobbyConn = nil
            end
        end
    end,
})

local function towerSuggestedSec(name)
    local t = SuggestedTimes[name]
    return t and ((tonumber(t.min) or 0) * 60 + (tonumber(t.sec) or 0)) or 0
end
local acValues = {}
for _, name in ipairs(DropdownValues) do acValues[#acValues + 1] = name end
local function getSelectedTowers()
    local picked = Library.Options.ACTowers and Library.Options.ACTowers.Value or {}
    local list = {}
    for _, name in ipairs(acValues) do
        if picked[name] then list[#list + 1] = name end
    end
    return list
end
local ACSuggestedLabel
local function updateACTime()
    if not ACSuggestedLabel then return end
    local total = 0
    for _, name in ipairs(getSelectedTowers()) do total = total + towerSuggestedSec(name) end
    ACSuggestedLabel:SetText(("Selected total suggested: %d:%02d"):format(math.floor(total / 60), total % 60))
end

TowerBox:AddDropdown("ACTowers", {
    Text     = "Auto Complete: Towers",
    Values   = acValues,
    Multi    = true,
    Default  = {},
    Tooltip  = "Tick which towers Auto Complete Selected plays (in list order).",
    Callback = function() updateACTime() end,
})
ACSuggestedLabel = TowerBox:AddLabel("Selected total suggested: 0:00")
updateACTime()

TowerBox:AddButton({
    Text    = "Auto Complete Selected Towers",
    Tooltip = "Auto Play each ticked tower in order, returning to the lobby between each. Press again to stop.",
    Callback = function()
        if _G.autoCompleteActive then
            _G.autoCompleteActive = false
            Library:Notify({ Title = "Auto Complete", Description = "Stopping after the current tower...", Duration = 3 })
            return
        end
        _G.autoCompleteActive = true
        task.spawn(function()
            local towers = getSelectedTowers()
            if #towers == 0 then
                Library:Notify({ Title = "Auto Complete", Description = "No towers selected!", Duration = 4 })
                _G.autoCompleteActive = false
                return
            end

            local origTower  = Library.Options.TowerSelect.Value
            local origMin    = Library.Options.CompletionMin.Value
            local origSec    = Library.Options.CompletionSec.Value
            local origRepeat = Library.Options.RepeatCount.Value
            Library.Options.RepeatCount:SetValue("1")

            for i, name in ipairs(towers) do
                if not _G.autoCompleteActive then break end
                if i > 1 then
                    Library:Notify({ Title = "Auto Complete", Description = ("(%d/%d) Returning to lobby..."):format(i, #towers), Duration = 4 })
                    returnToLobby()
                end
                if not _G.autoCompleteActive then break end
                Library:Notify({ Title = "Auto Complete", Description = ("(%d/%d) Playing %s"):format(i, #towers, name), Duration = 3 })
                Library.Options.TowerSelect:SetValue(name)
                startAutoPlay()
            end

            Library.Options.TowerSelect:SetValue(origTower)
            Library.Options.CompletionMin:SetValue(origMin)
            Library.Options.CompletionSec:SetValue(origSec)
            Library.Options.RepeatCount:SetValue(origRepeat)

            if _G.autoCompleteActive then
                Library:Notify({ Title = "Auto Complete", Description = "Done -- all selected towers played!", Duration = 5 })
            end
            _G.autoCompleteActive = false
        end)
    end,
})

-- ===== TEA Portals =====
local TEABox = Tabs.Main:AddRightGroupbox("TEA Portals")

local function listPortalTowers()
    local names = {}
    local towersFolder = workspace:FindFirstChild("Towers")
    if towersFolder then
        for _, t in ipairs(towersFolder:GetChildren()) do
            if t:FindFirstChild("Portal") then names[#names + 1] = t.Name end
        end
    end
    table.sort(names)
    return names
end

local _teaInit = listPortalTowers()
TEABox:AddDropdown("TEAPortalSelect", {
    Text      = "Portal Tower",
    Values    = _teaInit,
    Default   = _teaInit[1],
    AllowNull = true,
    Tooltip   = "Towers in workspace.Towers that have a Portal child.",
})

TEABox:AddButton({
    Text     = "Refresh List",
    Callback = function()
        local names = listPortalTowers()
        pcall(function() Library.Options.TEAPortalSelect:SetValues(names) end)
        Library:Notify({ Title = "TEA Portals", Description = ("%d towers with a Portal found."):format(#names), Duration = 4 })
    end,
})

TEABox:AddButton({
    Text     = "Teleport to Portal",
    Tooltip  = "Teleport onto the selected tower's Portal and fire its touch so you enter.",
    Callback = function()
        local name = Library.Options.TEAPortalSelect.Value
        if not name or name == "" then
            Library:Notify({ Title = "TEA Portals", Description = "Pick a tower first!", Duration = 3 })
            return
        end
        local part = resolvePortalPart(name)
        if not part then
            Library:Notify({ Title = "TEA Portals", Description = name .. " has no Portal part!", Duration = 4 })
            return
        end
        local char = game:GetService("Players").LocalPlayer.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then
            Library:Notify({ Title = "TEA Portals", Description = "Character not found!", Duration = 3 })
            return
        end
        hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0)
        for _ = 1, 3 do
            fireTouch(part, hrp)
            task.wait(0.05)
        end
        Library:Notify({ Title = "TEA Portals", Description = "Teleported to " .. name .. " Portal.", Duration = 3 })
    end,
})

-- ===== Personal Features =====
local PersonalBox = Tabs.Main:AddLeftGroupbox("Personal Features")

local function isCitadel(name)
    return name:match("^Co%u") ~= nil
end
local function runVMFlow(towerNames)
    local player = game:GetService("Players").LocalPlayer
    local VIM    = game:GetService("VirtualInputManager")
    local towersFolder = workspace:FindFirstChild("Towers")
    if not towersFolder or #towerNames == 0 then
        Library:Notify({ Title = "Auto VM", Description = "No towers to run!", Duration = 4 })
        _G.vmActive = false
        return
    end
    for i, name in ipairs(towerNames) do
        if not _G.vmActive then break end
        local tower = towersFolder:FindFirstChild(name)
        if tower then
            if i > 1 then returnToLobby() end
            if not _G.vmActive then break end
            Library:Notify({ Title = "Auto VM", Description = ("(%d/%d) %s"):format(i, #towerNames, name), Duration = 3 })

            local entryParts = {}
            local tpFramePart = tower:FindFirstChild("TPFRAME", true)
            local teleToPart  = tower:FindFirstChild("TeleportTo", true)
            if tpFramePart then entryParts[#entryParts + 1] = tpFramePart end
            if teleToPart  then entryParts[#entryParts + 1] = teleToPart end
            if #entryParts == 0 then
                local portalPart = resolvePortalPart(name)
                if portalPart then entryParts[1] = portalPart end
            end
            for _, part in ipairs(entryParts) do
                local t0 = os.clock()
                repeat
                    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0)
                        fireTouch(part, hrp)
                    end
                    task.wait(0.1)
                until os.clock() - t0 > 1.5 or not _G.vmActive
            end

            local citadel  = isCitadel(name)
            local slotKey  = citadel and Enum.KeyCode.Four or Enum.KeyCode.Five
            local itemName = citadel and "jump coil" or "VM"
            VIM:SendKeyEvent(true, slotKey, false, game)
            task.wait(0.1)
            VIM:SendKeyEvent(false, slotKey, false, game)

            local waitSec   = citadel and math.random(300, 900) or math.random(15, 60)
            local waitLabel = citadel and ("%.1f min"):format(waitSec / 60) or ("%ds"):format(waitSec)
            Library:Notify({ Title = "Auto VM", Description = ("(%d/%d) %s -- %s, waiting %s"):format(i, #towerNames, name, itemName, waitLabel), Duration = 4 })
            local waitUntil = os.clock() + waitSec
            while os.clock() < waitUntil and _G.vmActive do task.wait(0.5) end

            local winpad = tower:FindFirstChild("WinPad", true)
            if winpad then
                local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then hrp.CFrame = winpad.CFrame + Vector3.new(0, 3, 0) end
                task.wait(1.5)
            end
        end
    end
    if _G.vmActive then
        Library:Notify({ Title = "Auto VM", Description = "Done!", Duration = 5 })
    end
    _G.vmActive = false
end

PersonalBox:AddButton({
    Text    = "Auto Use VM (selected)",
    Tooltip = "For each ticked tower: enter it, use the VM item, wait, then teleport to the WinPad. Press again to stop.",
    Callback = function()
        if _G.vmActive then
            _G.vmActive = false
            Library:Notify({ Title = "Auto VM", Description = "Stopping...", Duration = 3 })
            return
        end
        _G.vmActive = true
        task.spawn(function() runVMFlow(getSelectedTowers()) end)
    end,
})

PersonalBox:AddButton({
    Text    = "Auto Detect Towers",
    Tooltip = "Detect every tower loaded in the current area and add them to the 'Auto Complete: Towers' list.",
    Callback = function()
        local towersFolder = workspace:FindFirstChild("Towers")
        if not towersFolder then
            warn("[Auto Detect] workspace.Towers not found")
            Library:Notify({ Title = "Auto Detect", Description = "workspace.Towers not found in this area!", Duration = 5 })
            return
        end
        local children = towersFolder:GetChildren()
        local existing = {}
        for _, name in ipairs(acValues) do existing[name] = true end
        local added, newNames = 0, {}
        for _, t in ipairs(children) do
            if not existing[t.Name] then
                acValues[#acValues + 1] = t.Name
                existing[t.Name] = true
                added = added + 1
                newNames[#newNames + 1] = t.Name
                -- Also give it an Auto Play config if it exposes a Portal.
                if not TowerConfigs[t.Name] and t:FindFirstChild("Portal") then
                    local n = t.Name
                    TowerConfigs[n] = {
                        tpFrame    = function() return resolvePortalPart(n) end,
                        teleportTo = function() return resolvePortalPart(n) end,
                        routeUrl   = nil,
                        folderName = n,
                        isPortal   = true,
                    }
                    table.insert(DropdownValues, n)
                end
            end
        end
        warn(("[Auto Detect] workspace.Towers has %d children; %d new: %s")
            :format(#children, added, table.concat(newNames, ", ")))
        pcall(function() Library.Options.TowerSelect:SetValues(DropdownValues) end)
        local ok, err = pcall(function() Library.Options.ACTowers:SetValues(acValues) end)
        if not ok then
            warn("[Auto Detect] SetValues failed: " .. tostring(err))
            Library:Notify({ Title = "Auto Detect", Description = ("Found %d towers but list refresh failed (see F9)"):format(#children), Duration = 6 })
            return
        end
        Library:Notify({ Title = "Auto Detect", Description = ("%d towers here, %d new added (%d in list)"):format(#children, added, #acValues), Duration = 6 })
    end,
})

startAutoPlay = function()
        if isAutoPlaying then
            Library:Notify({ Title = "Auto Play", Description = "Already running!", Duration = 3 })
            return
        end
        local selected = Library.Options.TowerSelect.Value
        local config   = TowerConfigs[selected]
        if not config then
            Library:Notify({ Title = "Auto Play", Description = "No config for " .. selected, Duration = 3 })
            return
        end
        local Players      = game:GetService("Players")
        local TweenService = game:GetService("TweenService")
        local player       = Players.LocalPlayer
        local char         = player.Character
        if not char then
            Library:Notify({ Title = "Auto Play", Description = "Character not found!", Duration = 3 })
            return
        end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        local hrp      = char:FindFirstChild("HumanoidRootPart")
        if not hrp then
            Library:Notify({ Title = "Auto Play", Description = "HumanoidRootPart not found!", Duration = 3 })
            return
        end
        isAutoPlaying = true
        autoPlayStop = false
        Library.Toggles.Noclip:SetValue(true)
        Library.Toggles.Noclip:SetDisabled(true)
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
        if humanoid.Sit then humanoid.Sit = false end
        humanoid.PlatformStand = true
        local RunService = game:GetService("RunService")
        local antiGravConn = RunService.Heartbeat:Connect(function()
            if hrp and hrp.Parent then
                hrp.AssemblyLinearVelocity = Vector3.new(
                    hrp.AssemblyLinearVelocity.X,
                    0,
                    hrp.AssemblyLinearVelocity.Z
                )
            end
            local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
            if h and h.Sit then h.Sit = false end
        end)
        local walking = false
        task.spawn(function()
            local lastPos, lastMove
            while isAutoPlaying do
                task.wait(0.25)
                if not walking then lastPos = nil continue end
                local c = player.Character
                local h = c and c:FindFirstChild("HumanoidRootPart")
                if not h then continue end
                if not lastPos or (h.Position - lastPos).Magnitude > 4 then
                    lastPos  = h.Position
                    lastMove = os.clock()
                elseif os.clock() - lastMove >= 5 then
                    local hum = c:FindFirstChildOfClass("Humanoid")
                    if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
                    local VIM = game:GetService("VirtualInputManager")
                    VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                    task.wait(0.1)
                    VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
                    lastMove = os.clock()
                    lastPos  = h.Position
                end
            end
        end)
        local died = false
        local stopReason = "died"
        local diedConn
        diedConn = humanoid.Died:Connect(function()
            died = true
            stopReason = "died"
            diedConn:Disconnect()
        end)

        local exitButtonConn = nil
        local okBtn, exitBtn = pcall(function()
            return player.PlayerGui.Menu.wrapper.inner.exit.main.confirm.hitbox
        end)
        if okBtn and exitBtn then
            exitButtonConn = exitBtn.Activated:Connect(function()
                died = true
                stopReason = "exited"
            end)
        end

        local stopWatchConn
        stopWatchConn = RunService.Heartbeat:Connect(function()
            if autoPlayStop and not died then
                died = true
                stopReason = "stopped"
            end
        end)

        local function stopAutoNoclip()
            if antiGravConn then
                antiGravConn:Disconnect()
                antiGravConn = nil
            end
            Library.Toggles.Noclip:SetDisabled(false)
            Library.Toggles.Noclip:SetValue(false)
            Library.Toggles.Fly:SetValue(false)
            if exitButtonConn then
                exitButtonConn:Disconnect()
                exitButtonConn = nil
            end
            if stopWatchConn then
                stopWatchConn:Disconnect()
                stopWatchConn = nil
            end
            task.wait(0.1)
            local c = game:GetService("Players").LocalPlayer.Character
            if c then
                local h = c:FindFirstChild("HumanoidRootPart")
                if h then
                    h.AssemblyLinearVelocity = Vector3.zero
                end
                local hum = c:FindFirstChildOfClass("Humanoid")
                if hum then
                    hum:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
                    hum.PlatformStand = false
                end
            end
        end

        -- Single exit point for every failure path, so noclip / PlatformStand can never
        -- be left stuck on. (The original returned early in several places without it.)
        local function abort(msg, dur)
            Library:Notify({ Title = "Auto Play", Description = msg, Duration = dur or 5 })
            clearRouteHighlights()
            stopAutoNoclip()
            isAutoPlaying = false
            currentResolvedSteps = nil
        end

        local function checkDied()
            if died then
                local msg = stopReason == "stopped" and "Stopped!"
                    or (stopReason == "exited" and "Exited, stopping!" or "Character died, stopping!")
                abort(msg, 3)
                return true
            end
            return false
        end
        Library:Notify({ Title = "Auto Play", Description = "Fetching " .. selected .. " route...", Duration = 3 })

        if config.isTowerRush then
            local VirtualInputManager = game:GetService("VirtualInputManager")
            local okTp, tpFrame = pcall(config.tpFrame)
            if not okTp or not tpFrame then
                warnTowerStructure(getTpFrameName(selected))
                abort(selected .. " teleporter not found!", 3)
                return
            end
            Library:Notify({ Title = "Auto Play", Description = "Fetching " .. selected .. " tower list...", Duration = 3 })
            local r1trSrc
            local okFetch = pcall(function() r1trSrc = game:HttpGet(config.routeUrl) end)
            if not okFetch or not r1trSrc then
                abort(selected .. " fetch failed!")
                return
            end
            local r1trFn = loadstring(r1trSrc)
            if not r1trFn then
                abort(selected .. " parse failed!")
                return
            end
            local okR1, getTowers = pcall(r1trFn)
            if not okR1 or type(getTowers) ~= "function" then
                abort(selected .. " load failed!")
                return
            end
            local okR2, towerList = pcall(getTowers)
            if not okR2 or type(towerList) ~= "table" then
                abort(selected .. " tower list failed!")
                return
            end
            Library:Notify({ Title = "Auto Play", Description = "Moving to " .. selected .. " teleporter...", Duration = 3 })
            local tpTouched = false
            local tpConn
            tpConn = tpFrame.Touched:Connect(function(hit)
                if hit:IsDescendantOf(char) and not tpTouched then
                    tpTouched = true
                    tpConn:Disconnect()
                end
            end)
            while not tpTouched do
                if checkDied() then return end
                hrp.CFrame = CFrame.new(tpFrame.Position + Vector3.new(0, 3, 0)) * (hrp.CFrame - hrp.CFrame.Position)
                fireTouch(tpFrame, hrp)
                task.wait(0.1)
            end
            if checkDied() then return end

            local totalSuggestedSec = 0
            for _, towerName in ipairs(towerList) do
                local st = SuggestedTimes[towerName]
                if st then
                    totalSuggestedSec = totalSuggestedSec + (tonumber(st.min) or 0) * 60 + (tonumber(st.sec) or 0)
                end
            end
            local useCustomTime = not Library.Toggles.UseSuggestedTime.Value
            local totalCustomSec = 0
            if useCustomTime then
                local cMin = tonumber(Library.Options.CompletionMin.Value) or 0
                local cSec = tonumber(Library.Options.CompletionSec.Value) or 0
                totalCustomSec = cMin * 60 + cSec
            end

            for towerIndex, towerName in ipairs(towerList) do
                if checkDied() then return end
                local towerConfig = TowerConfigs[towerName]
                if not towerConfig then continue end

                local getCheckpoints, source = resolveCheckpointProvider(towerName, towerConfig)
                if not getCheckpoints then
                    abort(towerName .. ": " .. tostring(source))
                    return
                end
                Library:Notify({ Title = "Auto Play", Description = ("%s route via %s (%d/%d)"):format(towerName, source, towerIndex, #towerList), Duration = 3 })

                local towerSec
                if useCustomTime and totalSuggestedSec > 0 then
                    local st = SuggestedTimes[towerName]
                    local thisSuggestedSec = st and ((tonumber(st.min) or 0) * 60 + (tonumber(st.sec) or 0)) or 0
                    towerSec = totalCustomSec * (thisSuggestedSec / totalSuggestedSec)
                else
                    local st = SuggestedTimes[towerName]
                    local tMin = st and tonumber(st.min) or 3
                    local tSec = st and tonumber(st.sec) or 0
                    towerSec = tMin * 60 + tSec
                end
                local towerDeadline = os.clock() + math.max(towerSec, 1)
                Library:Notify({ Title = "Auto Play", Description = "Entering " .. towerName .. "...", Duration = 3 })

                -- Portal towers use one part for both TPFRAME and TeleportTo; touching it
                -- once already teleports you in, so don't wait on a second touch.
                local okA, trTpPart = false, nil
                local okB, trToPart = false, nil
                if type(towerConfig.tpFrame) == "function" then
                    okA, trTpPart = pcall(towerConfig.tpFrame)
                end
                if type(towerConfig.teleportTo) == "function" then
                    okB, trToPart = pcall(towerConfig.teleportTo)
                end
                local trSingle = okA and okB and trTpPart ~= nil and trTpPart == trToPart

                if towerIndex > 1 then
                    if not okB or not trToPart then
                        abort(towerName .. " TeleportTo not found!", 3)
                        return
                    end
                    Library:Notify({ Title = "Auto Play", Description = "Waiting for " .. towerName .. " teleport...", Duration = 3 })
                    if trSingle then
                        -- One-part portal: sit on it, fire the touch, move on.
                        local t0 = os.clock()
                        repeat
                            if checkDied() then return end
                            hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                            if hrp then
                                hrp.CFrame = trToPart.CFrame + Vector3.new(0, 3, 0)
                                fireTouch(trToPart, hrp)
                            end
                            task.wait(0.1)
                        until os.clock() - t0 > 1.5 or not hrp
                    else
                        local touched = false
                        local conn
                        conn = trToPart.Touched:Connect(function(hit)
                            if hit:IsDescendantOf(char) and not touched then
                                touched = true
                                conn:Disconnect()
                            end
                        end)
                        while not touched do
                            if checkDied() then return end
                            local distToTP = (hrp.Position - trToPart.Position).Magnitude
                            if distToTP < 10 then
                                touched = true
                                conn:Disconnect()
                                break
                            end
                            hrp.CFrame = trToPart.CFrame + Vector3.new(0, 3, 0)
                            fireTouch(trToPart, hrp)
                            task.wait(0.1)
                        end
                    end
                    if checkDied() then return end
                end

                local posBeforeTP = hrp and hrp.Position or Vector3.zero
                task.wait(0.5)
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
                local nudgeStop = os.clock() + 8
                repeat
                    if checkDied() then
                        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
                        return
                    end
                    task.wait(0.1)
                    char = player.Character
                    hrp  = char and char:FindFirstChild("HumanoidRootPart")
                until (hrp and (hrp.Position - posBeforeTP).Magnitude > 0.1) or os.clock() > nudgeStop
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
                if checkDied() then return end

                local checkpoints
                local cpDeadline = os.clock() + 15
                repeat
                    if checkDied() then return end
                    local ok4, result = pcall(getCheckpoints)
                    if ok4 and type(result) == "table" and #result > 0 then
                        checkpoints = result
                    end
                    if not checkpoints then task.wait(0.1) end
                until checkpoints or os.clock() > cpDeadline
                if not checkpoints then
                    abort(towerName .. ": route returned no checkpoints (timed out).")
                    return
                end

                local totalDistance = 0
                local prevPos = hrp.Position
                local resolvedSteps = {}
                for _, step in ipairs(checkpoints) do
                    if step == "jump" then
                        table.insert(resolvedSteps, { type = "jump" })
                        continue
                    end
                    local stepType = "tween"
                    local target
                    if typeof(step) == "Instance" then
                        target = step
                    elseif type(step) == "table" then
                        stepType = step.type or "tween"
                        target   = step.target
                    end
                    if target and target:IsA("BasePart") then
                        local destPos = getTopPos(target)
                        local dist    = (destPos - prevPos).Magnitude
                        totalDistance = totalDistance + dist
                        table.insert(resolvedSteps, { type = stepType, target = target, destPos = destPos, dist = dist })
                        prevPos = destPos
                    end
                end
                currentResolvedSteps = resolvedSteps
                if Library.Toggles.ShowRoute.Value then
                    showRoute(resolvedSteps)
                end
                Library:Notify({ Title = "Auto Play", Description = towerName .. " - Starting route, " .. #resolvedSteps .. " checkpoints", Duration = 3 })
                local remainingDistances = {}
                local cumDist = 0
                for i = #resolvedSteps, 1, -1 do
                    local s = resolvedSteps[i]
                    if s.type ~= "jump" then cumDist = cumDist + (s.dist or 0) end
                    remainingDistances[i] = cumDist
                end
                walking = true
                for i, step in ipairs(resolvedSteps) do
                    if checkDied() then return end
                    char = player.Character
                    hrp  = char and char:FindFirstChild("HumanoidRootPart")
                    if not hrp then
                        walking = false
                        abort("Character lost, stopping!", 3)
                        return
                    end
                    if step.type == "jump" then
                        local hum = char:FindFirstChildOfClass("Humanoid")
                        if hum then hum.Jump = true end
                        continue
                    end
                    local dist       = (step.destPos - hrp.Position).Magnitude
                    local timeLeft   = math.max(towerDeadline - os.clock(), 0.001)
                    local remainDist = remainingDistances[i]
                    local stepTime   = remainDist > 0 and (timeLeft * (dist / remainDist)) or 0.05
                    stepTime         = math.max(stepTime, 0.05)

                    local startTime  = os.clock()
                    local moveTarget = step.target
                    local done       = false
                    local lastPos    = hrp.Position
                    local moveConn
                    moveConn = RunService.Heartbeat:Connect(function(dt)
                        if died then
                            done = true
                            moveConn:Disconnect()
                            return
                        end
                        local c = player.Character
                        local h = c and c:FindFirstChild("HumanoidRootPart")
                        if not h then
                            done = true
                            moveConn:Disconnect()
                            return
                        end
                        if (h.Position - lastPos).Magnitude > 10 then
                            task.wait(0.5)
                            lastPos = h.Position
                            startTime = os.clock()
                            return
                        end
                        lastPos = h.Position
                        local currentDest = step.destPos
                        if moveTarget and moveTarget.Parent then
                            currentDest = getTopPos(moveTarget)
                        end
                        local currentDist = (currentDest - h.Position).Magnitude
                        if currentDist <= 0.1 then
                            done = true
                            moveConn:Disconnect()
                            return
                        end
                        local speed = stepTime > 0 and (dist / stepTime) or 50
                        local moveDist = math.min(speed * dt, currentDist)
                        local rawDir = (currentDest - h.Position)
                        if rawDir.Magnitude < 0.001 then return end
                        local dir = rawDir.Unit
                        if dir ~= dir then return end
                        h.CFrame = CFrame.new(h.Position + dir * moveDist)
                        lastPos = h.Position
                        if (os.clock() - startTime) >= stepTime then
                            h.CFrame = CFrame.new(currentDest)
                            done = true
                            moveConn:Disconnect()
                        end
                    end)
                    repeat task.wait() until done
                end
                walking = false
                Library:Notify({ Title = "Auto Play", Description = towerName .. " complete!", Duration = 3 })
            end
            if not died then
                Library:Notify({ Title = "Auto Play", Description = selected .. " Complete!", Duration = 5 })
                clearRouteHighlights()
            end
            stopAutoNoclip()
            isAutoPlaying = false
            return
        end

        -- Resolve the route once and reuse it for every repeat. Falls back to a generated
        -- checkpoint route when the tower has no route file (TEA / unregistered towers).
        local getCheckpoints, routeSource = resolveCheckpointProvider(selected, config)
        if not getCheckpoints then
            abort(selected .. ": " .. tostring(routeSource))
            return
        end
        Library:Notify({ Title = "Auto Play", Description = ("%s route via %s"):format(selected, routeSource), Duration = 4 })

        local repeatCount = math.max(math.floor(tonumber(Library.Options.RepeatCount.Value) or 1), 1)
        local reqSec = (tonumber(Library.Options.CompletionMin.Value) or 0) * 60
                     + (tonumber(Library.Options.CompletionSec.Value) or 0)
        local perRepeatTime = math.max(reqSec, 1)

        for rep = 1, repeatCount do
        local repTag = repeatCount > 1 and (" [" .. rep .. "/" .. repeatCount .. "]") or ""
        warn(("[ProjectEToH] Auto Play run %d/%d (%s) budget=%.1fs"):format(rep, repeatCount, tostring(selected), perRepeatTime))
        if rep > 1 then
            Library:Notify({ Title = "Auto Play", Description = "Returning to lobby before next run..." .. repTag, Duration = 4 })
            returnToLobby()
            if died and stopReason == "exited" then checkDied() return end
            char = player.Character or player.CharacterAdded:Wait()
            char:WaitForChild("HumanoidRootPart", 10)
            task.wait(0.5)
            char = player.Character
            hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then
                abort("Character didn't respawn, stopping!", 3)
                return
            end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
                if hum.Sit then hum.Sit = false end
                hum.PlatformStand = true
            end
            died = false
            stopReason = "died"
            if diedConn then diedConn:Disconnect() end
            diedConn = hum and hum.Died:Connect(function()
                died = true
                stopReason = "died"
                diedConn:Disconnect()
            end)
            warn(("[ProjectEToH] run %d: returned to lobby, re-entering"):format(rep))
        end

        local okTp, tpFrame = pcall(config.tpFrame)
        if not okTp or not tpFrame then
            warnTowerStructure(config.folderName or getTpFrameName(selected))
            abort(selected .. " teleporter not found!", 3)
            return
        end
        local okTo, teleportTo = pcall(config.teleportTo)
        if not okTo or not teleportTo then
            abort("TeleportTo not found!", 3)
            return
        end
        -- Portal towers: tpFrame == teleportTo, one part does both. Touch it once.
        local singleEntry = (tpFrame == teleportTo)

        local posBeforeTP = hrp.Position
        local VirtualInputManager = game:GetService("VirtualInputManager")

        -- Walk onto `part` and wait until it registers. Returns false if we stopped/died.
        -- Succeeds on: a real Touched event, the character being removed (teleported in),
        -- or a large displacement (the portal fired but Touched never reported to us).
        local function touchPart(part)
            local touched = false
            local conn
            conn = part.Touched:Connect(function(hit)
                local c = player.Character
                if c and hit:IsDescendantOf(c) and not touched then
                    touched = true
                    conn:Disconnect()
                end
            end)
            local t0 = os.clock()
            while not touched do
                if checkDied() then
                    if conn.Connected then conn:Disconnect() end
                    return false
                end
                char = player.Character
                hrp  = char and char:FindFirstChild("HumanoidRootPart")
                if not hrp then
                    if conn.Connected then conn:Disconnect() end
                    return true
                end
                if not part.Parent then
                    if conn.Connected then conn:Disconnect() end
                    return true
                end
                hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0)) * (hrp.CFrame - hrp.CFrame.Position)
                fireTouch(part, hrp)
                if (hrp.Position - posBeforeTP).Magnitude > 50 and (os.clock() - t0) > 0.5 then
                    if conn.Connected then conn:Disconnect() end
                    return true
                end
                task.wait(0.1)
            end
            return true
        end

        Library:Notify({ Title = "Auto Play", Description = "Moving to " .. selected .. " teleporter...", Duration = 3 })
        if not touchPart(tpFrame) then return end
        if checkDied() then return end

        if not singleEntry then
            Library:Notify({ Title = "Auto Play", Description = "Waiting for teleport...", Duration = 3 })
            if not touchPart(teleportTo) then return end
            if checkDied() then return end
        end

        Library:Notify({ Title = "Auto Play", Description = "Waiting for teleport to complete...", Duration = 3 })
        posBeforeTP = hrp and hrp.Position or posBeforeTP
        task.wait(0.5)
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
        local nudgeStop = os.clock() + 8
        repeat
            if checkDied() then
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
                return
            end
            task.wait(0.1)
            char = player.Character
            hrp  = char and char:FindFirstChild("HumanoidRootPart")
        until (hrp and (hrp.Position - posBeforeTP).Magnitude > 0.1) or os.clock() > nudgeStop
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
        if checkDied() then return end
        if not hrp then
            abort("Character lost after teleport, stopping!", 3)
            return
        end

        local deadline = os.clock() + perRepeatTime
        local checkpoints
        local lastErr = ""
        local lastNotify = os.clock()
        -- Bounded: the original spun forever if the route never returned checkpoints.
        local cpDeadline = os.clock() + 15
        repeat
            if checkDied() then return end
            local ok2b, result = pcall(getCheckpoints)
            if ok2b and type(result) == "table" and #result > 0 then
                checkpoints = result
            elseif not ok2b then
                lastErr = tostring(result)
                if os.clock() - lastNotify > 3 then
                    lastNotify = os.clock()
                    Library:Notify({ Title = "Auto Play", Description = "Retrying: " .. lastErr, Duration = 3 })
                end
            end
            if not checkpoints then task.wait(0.1) end
        until checkpoints or os.clock() > cpDeadline
        if not checkpoints then
            abort("Route returned no checkpoints" .. (lastErr ~= "" and (": " .. lastErr) or " (timed out)."))
            return
        end

        local totalDistance = 0
        local prevPos = hrp.Position
        local resolvedSteps = {}
        for _, step in ipairs(checkpoints) do
            if step == "jump" then
                table.insert(resolvedSteps, { type = "jump" })
                continue
            end
            local stepType = "tween"
            local target
            if typeof(step) == "Instance" then
                target = step
            elseif type(step) == "table" then
                stepType = step.type or "tween"
                target   = step.target
            end
            if target and target:IsA("BasePart") then
                local destPos = getTopPos(target)
                local dist    = (destPos - prevPos).Magnitude
                totalDistance = totalDistance + dist
                table.insert(resolvedSteps, { type = stepType, target = target, destPos = destPos, dist = dist })
                prevPos = destPos
            end
        end
        currentResolvedSteps = resolvedSteps
        if Library.Toggles.ShowRoute.Value then
            showRoute(resolvedSteps)
        end
        Library:Notify({ Title = "Auto Play", Description = "Starting route, " .. #resolvedSteps .. " checkpoints", Duration = 3 })
        warn(("[ProjectEToH] run %d: walking %d steps, %.1fs left"):format(rep, #resolvedSteps, math.max(deadline - os.clock(), 0)))
        local remainingDistances = {}
        local cumDist = 0
        for i = #resolvedSteps, 1, -1 do
            local s = resolvedSteps[i]
            if s.type ~= "jump" then
                cumDist = cumDist + (s.dist or 0)
            end
            remainingDistances[i] = cumDist
        end
        walking = true
        for i, step in ipairs(resolvedSteps) do
            if checkDied() then return end
            char = player.Character
            hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then
                warn(("[ProjectEToH] run %d: character gone at step %d/%d (win/respawn), ending run"):format(rep, i, #resolvedSteps))
                break
            end
            if step.type == "jump" then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.Jump = true end
                continue
            end
            local dist         = (step.destPos - hrp.Position).Magnitude
            local timeLeft     = math.max(deadline - os.clock(), 0.001)
            local remainDist   = remainingDistances[i]
            local stepTime     = remainDist > 0 and (timeLeft * (dist / remainDist)) or 0.05
            stepTime           = math.max(stepTime, 0.05)

            local startTime  = os.clock()
            local moveTarget = step.target
            local isMoving   = moveTarget and moveTarget.Parent and
                               (getTopPos(moveTarget) - step.destPos).Magnitude > 0.5
            local done       = false

            if not isMoving then
                local dest = CFrame.new(step.destPos) * (hrp.CFrame - hrp.CFrame.Position)
                local tween = TweenService:Create(hrp, TweenInfo.new(stepTime, Enum.EasingStyle.Linear), { CFrame = dest })
                tween:Play()
                tween.Completed:Connect(function() done = true end)
                repeat task.wait() until done or died
                tween:Cancel()
            else
                local touchConn
                if moveTarget then
                    touchConn = moveTarget.Touched:Connect(function(hit)
                        local c = player.Character
                        if c and hit:IsDescendantOf(c) then
                            done = true
                        end
                    end)
                end
                local moveConn
                moveConn = RunService.Heartbeat:Connect(function(dt)
                    if died then done = true moveConn:Disconnect() return end
                    local c = player.Character
                    local h = c and c:FindFirstChild("HumanoidRootPart")
                    if not h then done = true moveConn:Disconnect() return end
                    local currentDest = step.destPos
                    if moveTarget and moveTarget.Parent then
                        currentDest = getTopPos(moveTarget)
                    end
                    local currentDist = (currentDest - h.Position).Magnitude
                    if currentDist <= 0.1 then done = true moveConn:Disconnect() return end
                    local speed = stepTime > 0 and (dist / stepTime) or 50
                    local moveDist = math.min(speed * dt, currentDist)
                    local rawDir = (currentDest - h.Position)
                    if rawDir.Magnitude < 0.001 then return end
                    local dir = rawDir.Unit
                    if dir ~= dir then return end
                    h.CFrame = CFrame.new(h.Position + dir * moveDist)
                    if (os.clock() - startTime) >= stepTime then
                        h.CFrame = CFrame.new(currentDest)
                        done = true
                        moveConn:Disconnect()
                    end
                end)
                repeat task.wait() until done
                if moveConn then moveConn:Disconnect() end
                if touchConn then touchConn:Disconnect() end
            end
        end
        walking = false
        warn(("[ProjectEToH] run %d/%d finished (died=%s)"):format(rep, repeatCount, tostring(died)))
        if not died then
            Library:Notify({ Title = "Auto Play", Description = "Complete!" .. repTag, Duration = 3 })
        end
        if died then break end
        end -- repeat loop

        if not died then
            Library:Notify({
                Title       = "Auto Play",
                Description  = repeatCount > 1 and ("All " .. repeatCount .. " repeats complete!") or "Complete!",
                Duration    = 5,
            })
        end
        clearRouteHighlights()
        stopAutoNoclip()
        isAutoPlaying = false
        currentResolvedSteps = nil
end
TowerBox:AddButton({
    Text     = "Auto Play",
    Tooltip  = "Press to start. Press again to stop (no dying or rejoining needed).",
    Callback = function()
        if isAutoPlaying then
            autoPlayStop = true
            Library:Notify({ Title = "Auto Play", Description = "Stopping...", Duration = 3 })
            return
        end
        task.spawn(startAutoPlay)
    end,
})
local allJumpCheckpoints = {}
local allJumpVisuals = {}

AllJumpBox:AddToggle("AllJumpMode", {
    Text    = "Enable All Jump Mode",
    Default = false,
    Tooltip = "Place checkpoints and teleport back to them",
    Callback = function(state)
        if not state then
            for _, v in ipairs(allJumpVisuals) do
                if v and v.Parent then v:Destroy() end
            end
            allJumpCheckpoints = {}
            allJumpVisuals = {}
        end
    end,
})

local function allJumpPlace()
    if not Library.Toggles.AllJumpMode.Value then return end
    local char = game:GetService("Players").LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    table.insert(allJumpCheckpoints, hrp.CFrame)
    local part = Instance.new("Part")
    part.Size         = hrp.Size
    part.CFrame       = hrp.CFrame
    part.Anchored     = true
    part.CanCollide   = false
    part.Transparency = 0.5
    part.Material     = Enum.Material.Neon
    part.Color        = Color3.fromRGB(255, 255, 255)
    part.Parent       = workspace
    table.insert(allJumpVisuals, part)
end

local function allJumpRemove()
    if not Library.Toggles.AllJumpMode.Value then return end
    if #allJumpCheckpoints > 0 then
        table.remove(allJumpCheckpoints)
        local v = table.remove(allJumpVisuals)
        if v then v:Destroy() end
    end
end

local function allJumpTeleport()
    if not Library.Toggles.AllJumpMode.Value then return end
    if #allJumpCheckpoints == 0 then return end
    local char = game:GetService("Players").LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        hrp.CFrame = allJumpCheckpoints[#allJumpCheckpoints]
    end
end

local kb_AJPlace = AllJumpBox:AddLabel("Place"):AddKeyPicker("AJPlace", {
    Text    = "Place",
    Default = "Q",
    Mode    = "Press",
})
Options.AJPlace:OnClick(allJumpPlace)

local kb_AJRemove = AllJumpBox:AddLabel("Remove"):AddKeyPicker("AJRemove", {
    Text    = "Remove",
    Default = "T",
    Mode    = "Press",
})
Options.AJRemove:OnClick(allJumpRemove)

local kb_AJTeleport = AllJumpBox:AddLabel("Teleport"):AddKeyPicker("AJTeleport", {
    Text    = "Teleport",
    Default = "R",
    Mode    = "Press",
})
Options.AJTeleport:OnClick(allJumpTeleport)

local PlayerBox = Tabs.Main:AddRightGroupbox("Player")

local wsConn = nil
local wsCAConn = nil
local jpConn = nil
local jpCAConn = nil

local function applyCharacterStats(char)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then
        char:WaitForChild("Humanoid", 5)
        hum = char:FindFirstChildOfClass("Humanoid")
    end
    if hum then
        hum.WalkSpeed = Library.Options.WalkSpeed.Value
        hum.JumpPower = Library.Options.JumpPower.Value
    end
end

game:GetService("Players").LocalPlayer.CharacterAdded:Connect(applyCharacterStats)

PlayerBox:AddSlider("WalkSpeed", {
    Text     = "Walk Speed",
    Default  = 16,
    Min      = 0,
    Max      = 100,
    Rounding = 0,
    Callback = function(value)
        local char = game:GetService("Players").LocalPlayer.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = value end
    end,
})

PlayerBox:AddToggle("LockWalkSpeed", {
    Text    = "Lock Walk Speed",
    Default = false,
    Callback = function(state)
        local player = game:GetService("Players").LocalPlayer
        if wsConn then wsConn:Disconnect() wsConn = nil end
        if wsCAConn then wsCAConn:Disconnect() wsCAConn = nil end
        if not state then return end
        local function applyWS(char)
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not hum then
                char:WaitForChild("Humanoid", 5)
                hum = char:FindFirstChildOfClass("Humanoid")
            end
            if not hum then return end
            hum.WalkSpeed = Library.Options.WalkSpeed.Value
            wsConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
                if Library.Toggles.LockWalkSpeed.Value then
                    hum.WalkSpeed = Library.Options.WalkSpeed.Value
                end
            end)
        end
        applyWS(player.Character)
        wsCAConn = player.CharacterAdded:Connect(function(char)
            if wsConn then wsConn:Disconnect() wsConn = nil end
            applyWS(char)
        end)
    end,
})

PlayerBox:AddSlider("JumpPower", {
    Text     = "Jump Power",
    Default  = 50,
    Min      = 0,
    Max      = 200,
    Rounding = 0,
    Callback = function(value)
        local char = game:GetService("Players").LocalPlayer.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.JumpPower = value end
    end,
})

PlayerBox:AddToggle("LockJumpPower", {
    Text    = "Lock Jump Power",
    Default = false,
    Callback = function(state)
        local player = game:GetService("Players").LocalPlayer
        if jpConn then jpConn:Disconnect() jpConn = nil end
        if jpCAConn then jpCAConn:Disconnect() jpCAConn = nil end
        if not state then return end
        local function applyJP(char)
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not hum then
                char:WaitForChild("Humanoid", 5)
                hum = char:FindFirstChildOfClass("Humanoid")
            end
            if not hum then return end
            hum.JumpPower = Library.Options.JumpPower.Value
            jpConn = hum:GetPropertyChangedSignal("JumpPower"):Connect(function()
                if Library.Toggles.LockJumpPower.Value then
                    hum.JumpPower = Library.Options.JumpPower.Value
                end
            end)
        end
        applyJP(player.Character)
        jpCAConn = player.CharacterAdded:Connect(function(char)
            if jpConn then jpConn:Disconnect() jpConn = nil end
            applyJP(char)
        end)
    end,
})

PlayerBox:AddButton({
    Text     = "Reset Walk Speed & Jump Power",
    Callback = function()
        Library.Options.WalkSpeed:SetValue(16)
        Library.Options.JumpPower:SetValue(50)
    end,
})
PlayerBox:AddDivider()
PlayerBox:AddToggle("Noclip", {
    Text    = "Noclip",
    Default = false,
    Tooltip = "Walk through walls",
    Callback = function(state)
        local Players    = game:GetService("Players")
        local RunService = game:GetService("RunService")

        if _G.noclipConns then
            for _, c in ipairs(_G.noclipConns) do c:Disconnect() end
        end
        _G.noclipConns = {}
        if noclipConnection then noclipConnection:Disconnect() noclipConnection = nil end
        if not state then return end
        local conns = _G.noclipConns

        local function forceUncollide(part)
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end
        local function hookPart(part)
            if not part:IsA("BasePart") then return end
            forceUncollide(part)
            conns[#conns + 1] = part:GetPropertyChangedSignal("CanCollide"):Connect(function()
                if part.CanCollide then part.CanCollide = false end
            end)
        end
        local function hookChar(char)
            if not char then return end
            for _, p in ipairs(char:GetDescendants()) do hookPart(p) end
            conns[#conns + 1] = char.DescendantAdded:Connect(hookPart)
        end

        hookChar(Players.LocalPlayer.Character)
        conns[#conns + 1] = Players.LocalPlayer.CharacterAdded:Connect(hookChar)

        local function sweep()
            local char = Players.LocalPlayer.Character
            if not char then return end
            for _, p in ipairs(char:GetDescendants()) do forceUncollide(p) end
        end
        conns[#conns + 1] = RunService.Stepped:Connect(sweep)
        conns[#conns + 1] = RunService.Heartbeat:Connect(sweep)
    end,
}):AddKeyPicker("NoclipKeybind", {
    Text            = "Noclip Keybind",
    Default         = "V",
    Mode            = "Toggle",
    SyncToggleState = true,
})
local flyConnection = nil
local flyInputBeganConn = nil
local flyInputEndedConn = nil
local function setFly(state)
    local Players  = game:GetService("Players")
    local player   = Players.LocalPlayer
    local char     = player.Character
    if not char then return end
    local hrp      = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid then return end
    if state then
        local BodyVelocity = Instance.new("BodyVelocity")
        BodyVelocity.Name       = "FlyVelocity"
        BodyVelocity.Velocity   = Vector3.zero
        BodyVelocity.MaxForce   = Vector3.new(1e9, 1e9, 1e9)
        BodyVelocity.Parent     = hrp
        local BodyGyro = Instance.new("BodyGyro")
        BodyGyro.Name       = "FlyGyro"
        BodyGyro.MaxTorque  = Vector3.new(1e9, 1e9, 1e9)
        BodyGyro.P          = 9e4
        BodyGyro.CFrame     = hrp.CFrame
        BodyGyro.Parent     = hrp

        local UserInputService = game:GetService("UserInputService")
        local RunService       = game:GetService("RunService")
        local SPEED = 50

        local CONTROL = { F = 0, B = 0, L = 0, R = 0, U = 0, D = 0 }

        flyInputBeganConn = UserInputService.InputBegan:Connect(function(input, processed)
            if processed then return end
            if input.KeyCode == Enum.KeyCode.W then CONTROL.F = 1
            elseif input.KeyCode == Enum.KeyCode.S then CONTROL.B = -1
            elseif input.KeyCode == Enum.KeyCode.A then CONTROL.L = -1
            elseif input.KeyCode == Enum.KeyCode.D then CONTROL.R = 1
            elseif input.KeyCode == Enum.KeyCode.Space then CONTROL.U = 1
            elseif input.KeyCode == Enum.KeyCode.LeftShift then CONTROL.D = -1
            end
        end)

        flyInputEndedConn = UserInputService.InputEnded:Connect(function(input, processed)
            if input.KeyCode == Enum.KeyCode.W then CONTROL.F = 0
            elseif input.KeyCode == Enum.KeyCode.S then CONTROL.B = 0
            elseif input.KeyCode == Enum.KeyCode.A then CONTROL.L = 0
            elseif input.KeyCode == Enum.KeyCode.D then CONTROL.R = 0
            elseif input.KeyCode == Enum.KeyCode.Space then CONTROL.U = 0
            elseif input.KeyCode == Enum.KeyCode.LeftShift then CONTROL.D = 0
            end
        end)

        flyConnection = RunService.Heartbeat:Connect(function()
            local newChar = player.Character
            local newHrp  = newChar and newChar:FindFirstChild("HumanoidRootPart")
            if newHrp ~= hrp then
                hrp      = newHrp
                char     = newChar
                humanoid = newChar and newChar:FindFirstChildOfClass("Humanoid")
                if hrp then
                    if not hrp:FindFirstChild("FlyVelocity") then
                        local bv2 = Instance.new("BodyVelocity")
                        bv2.Name     = "FlyVelocity"
                        bv2.Velocity = Vector3.zero
                        bv2.MaxForce = Vector3.new(1e9, 1e9, 1e9)
                        bv2.Parent   = hrp
                    end
                    if not hrp:FindFirstChild("FlyGyro") then
                        local bg2 = Instance.new("BodyGyro")
                        bg2.Name      = "FlyGyro"
                        bg2.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
                        bg2.P         = 9e4
                        bg2.CFrame    = hrp.CFrame
                        bg2.Parent    = hrp
                    end
                end
            end
            hrp      = newHrp
            humanoid = newChar and newChar:FindFirstChildOfClass("Humanoid")
            local bv = hrp and hrp:FindFirstChild("FlyVelocity")
            local bg = hrp and hrp:FindFirstChild("FlyGyro")
            if not bv or not bg then return end
            if humanoid then humanoid.PlatformStand = true end
            local cam = workspace.CurrentCamera
            local moveDir = (cam.CFrame.LookVector * (CONTROL.F + CONTROL.B))
                          + (cam.CFrame.RightVector * (CONTROL.L + CONTROL.R))
                          + (Vector3.new(0, 1, 0) * (CONTROL.U + CONTROL.D))
            bv.Velocity = moveDir * SPEED
            bg.CFrame   = cam.CFrame
        end)
    else
        if flyConnection then
            flyConnection:Disconnect()
            flyConnection = nil
        end
        if flyInputBeganConn then
            flyInputBeganConn:Disconnect()
            flyInputBeganConn = nil
        end
        if flyInputEndedConn then
            flyInputEndedConn:Disconnect()
            flyInputEndedConn = nil
        end
        local hrp2 = char:FindFirstChild("HumanoidRootPart")
        if hrp2 then
            local bv = hrp2:FindFirstChild("FlyVelocity")
            local bg = hrp2:FindFirstChild("FlyGyro")
            if bv then bv:Destroy() end
            if bg then bg:Destroy() end
            hrp2.AssemblyLinearVelocity = Vector3.zero
        end
        if humanoid then humanoid.PlatformStand = false end
    end
end
local FlyToggle = PlayerBox:AddToggle("Fly", {
    Text    = "Fly",
    Default = false,
    Tooltip = "Toggle fly mode",
    Callback = function(state)
        setFly(state)
    end,
})
FlyToggle:AddKeyPicker("FlyKeybind", {
    Text             = "Fly Keybind",
    Default          = "F",
    Mode             = "Toggle",
    SyncToggleState  = true,
})

PlayerBox:AddToggle("InfiniteJump", {
    Text    = "Infinite Jump",
    Default = false,
    Callback = function(state)
        if state then
            local Players = game:GetService("Players")
            local UIS     = game:GetService("UserInputService")
            _G.InfiniteJumpConn = UIS.JumpRequest:Connect(function()
                local char = Players.LocalPlayer.Character
                local hum  = char and char:FindFirstChildOfClass("Humanoid")
                if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
            end)
        else
            if _G.InfiniteJumpConn then
                _G.InfiniteJumpConn:Disconnect()
                _G.InfiniteJumpConn = nil
            end
        end
    end,
})

PlayerBox:AddToggle("AntiAFK", {
    Text    = "Anti AFK",
    Default = false,
    Tooltip = "Prevents being kicked for inactivity",
    Callback = function(state)
        if _G.AntiAFKConn then
            _G.AntiAFKConn:Disconnect()
            _G.AntiAFKConn = nil
        end
        if state then
            local VirtualUser = game:GetService("VirtualUser")
            local Players     = game:GetService("Players")
            _G.AntiAFKConn = Players.LocalPlayer.Idled:Connect(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end
    end,
})

PlayerBox:AddToggle("Fullbright", {
    Text    = "Fullbright",
    Default = false,
    Tooltip = "Removes darkness, fog and shadows so the whole level is fully lit",
    Callback = function(state)
        local Lighting   = game:GetService("Lighting")
        local RunService = game:GetService("RunService")
        if _G.FullbrightConn then
            _G.FullbrightConn:Disconnect()
            _G.FullbrightConn = nil
        end
        if state then
            if not _G.FullbrightOriginal then
                _G.FullbrightOriginal = {
                    Brightness     = Lighting.Brightness,
                    ClockTime      = Lighting.ClockTime,
                    FogEnd         = Lighting.FogEnd,
                    FogStart       = Lighting.FogStart,
                    GlobalShadows  = Lighting.GlobalShadows,
                    Ambient        = Lighting.Ambient,
                    OutdoorAmbient = Lighting.OutdoorAmbient,
                }
            end
            _G.FullbrightConn = RunService.RenderStepped:Connect(function()
                Lighting.Brightness     = 2
                Lighting.ClockTime      = 12
                Lighting.FogEnd         = 1e9
                Lighting.FogStart       = 0
                Lighting.GlobalShadows  = false
                Lighting.Ambient        = Color3.fromRGB(255, 255, 255)
                Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
            end)
        else
            local o = _G.FullbrightOriginal
            if o then
                Lighting.Brightness     = o.Brightness
                Lighting.ClockTime      = o.ClockTime
                Lighting.FogEnd         = o.FogEnd
                Lighting.FogStart       = o.FogStart
                Lighting.GlobalShadows  = o.GlobalShadows
                Lighting.Ambient        = o.Ambient
                Lighting.OutdoorAmbient = o.OutdoorAmbient
                _G.FullbrightOriginal   = nil
            end
        end
    end,
})
local godmodeOriginal = nil
local godmodeV2Connection = nil
local godmodeKillBrickConn = nil
local godmodeKillBrickParts = {}

local function isKillBrickPart(inst)
    if not inst:IsA("BasePart") then return false end
    if inst.Name == "Kill Brick" then return true end
    local kills = inst:FindFirstChild("kills")
    if kills and kills:IsA("BoolValue") then return true end
    return false
end

local function setGodmodeHook(state)
    if godmodeOriginal then
        hookmetamethod(game, "__namecall", godmodeOriginal)
        godmodeOriginal = nil
    end
    if not state then return end
    local damageEvent = game:GetService("ReplicatedStorage"):WaitForChild("DamageEvent")
    godmodeOriginal = hookmetamethod(game, "__namecall", function(self, ...)
        if self == damageEvent and getnamecallmethod() == "FireServer" then
            return
        end
        return godmodeOriginal(self, ...)
    end)
end

local function setGodmodeHeal(state)
    if godmodeV2Connection then
        godmodeV2Connection:Disconnect()
        godmodeV2Connection = nil
    end
    if not state then return end
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local damageEvent = game:GetService("ReplicatedStorage"):WaitForChild("DamageEvent")
    godmodeV2Connection = RunService.Heartbeat:Connect(function()
        local char = Players.LocalPlayer.Character
        if not char then return end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health < humanoid.MaxHealth then
            damageEvent:FireServer(-humanoid.MaxHealth)
        end
    end)
end

local function setGodmodeKillBricks(state)
    if godmodeKillBrickConn then
        godmodeKillBrickConn:Disconnect()
        godmodeKillBrickConn = nil
    end
    if not state then
        for part in pairs(godmodeKillBrickParts) do
            if part and part.Parent then part.CanTouch = true end
        end
        godmodeKillBrickParts = {}
        return
    end
    local function scanAndDisable(inst)
        if isKillBrickPart(inst) and inst.CanTouch then
            inst.CanTouch = false
            godmodeKillBrickParts[inst] = true
        end
    end
    for _, inst in ipairs(workspace:GetDescendants()) do
        scanAndDisable(inst)
    end
    godmodeKillBrickConn = workspace.DescendantAdded:Connect(scanAndDisable)
end

PlayerBox:AddToggle("GodmodeHook", {
    Text    = "Godmode: Hook Damage",
    Default = sUNCSupport.Godmode,
    Tooltip = "Blocks ALL damage by hooking the game's DamageEvent. Needs hookmetamethod + getnamecallmethod.",
    Callback = function(state)
        if state and not sUNCSupport.Godmode then
            Library.Toggles.GodmodeHook:SetValue(false)
            return
        end
        setGodmodeHook(state)
    end,
})

PlayerBox:AddToggle("GodmodeHeal", {
    Text    = "Godmode: Auto-Heal",
    Default = not sUNCSupport.Godmode,
    Tooltip = "Instantly heals you back to full whenever you take damage. Works on any executor.",
    Callback = function(state)
        setGodmodeHeal(state)
    end,
})

PlayerBox:AddToggle("GodmodeKillBricks", {
    Text    = "Godmode: Disable Kill Bricks",
    Default = false,
    Tooltip = "Turns off touch detection on every kill brick, including ones spawned later.",
    Callback = function(state)
        setGodmodeKillBricks(state)
    end,
})

if not sUNCSupport.Godmode then
    Library.Toggles.GodmodeHook:SetDisabled(true)
end

setGodmodeHook(Library.Toggles.GodmodeHook.Value)
setGodmodeHeal(Library.Toggles.GodmodeHeal.Value)
setGodmodeKillBricks(Library.Toggles.GodmodeKillBricks.Value)

Library.Toggles.UseSuggestedTime:SetValue(true)
local MenuGroup = Tabs.UISettings:AddLeftGroupbox("Menu")
MenuGroup:AddDropdown("UIStyle", {
    Text    = "UI Style",
    Values  = { "Obsidian", "Linoria" },
    Default = uiStyle,
    Callback = function(value)
        pcall(function()
            if not isfolder("ProjectEToHScript") then
                makefolder("ProjectEToHScript")
            end
            writefile(uiStyleFile, value)
        end)
        Library:Notify({ Title = "UI Style", Description = "Will apply on next launch!", Duration = 3 })
    end,
})
MenuGroup:AddToggle("KeybindMenuOpen", {
    Default = Library.KeybindFrame.Visible,
    Text = "Open Keybind Menu",
    Callback = function(value)
        Library.KeybindFrame.Visible = value
    end,
})
MenuGroup:AddToggle("ShowCustomCursor", {
    Text = "Custom Cursor",
    Default = true,
    Callback = function(Value)
        Library.ShowCustomCursor = Value
    end,
})
MenuGroup:AddDropdown("NotificationSide", {
    Values = { "Left", "Right" },
    Default = "Right",
    Text = "Notification Side",
    Callback = function(Value)
        Library:SetNotifySide(Value)
    end,
})
MenuGroup:AddDropdown("DPIDropdown", {
    Values = { "50%", "75%", "100%", "125%", "150%", "175%", "200%" },
    Default = "100%",
    Text = "DPI Scale",
    Callback = function(Value)
        Value = Value:gsub("%%", "")
        local DPI = tonumber(Value)
        Library:SetDPIScale(DPI)
    end,
})
local function getMasterVolume()
    local ok, v = pcall(function() return UserSettings():GetService("UserGameSettings").MasterVolume end)
    return ok and v or 0.5
end
MenuGroup:AddSlider("GameVolume", {
    Text     = "Game Volume",
    Default  = math.floor(getMasterVolume() * 100 + 0.5),
    Min      = 0,
    Max      = 100,
    Rounding = 0,
    Tooltip  = "Master game volume -- the same as the volume slider in Roblox's Esc menu.",
    Callback = function(value)
        pcall(function()
            UserSettings():GetService("UserGameSettings").MasterVolume = value / 100
        end)
    end,
})
local isObsidian = repo:find("deividcomsono") ~= nil

if isObsidian then
    MenuGroup:AddSlider("UICornerSlider", {
        Text = "Corner Radius",
        Default = Library.CornerRadius,
        Min = 0,
        Max = 20,
        Rounding = 0,
        Callback = function(value)
            Window:SetCornerRadius(value)
        end
    })
end
MenuGroup:AddToggle("AutoExecute", {
    Text    = "Auto Execute on Teleport",
    Default = autoExecuteDefault,
    Tooltip = sUNCSupport.queueteleport and "Re-executes this script after teleporting" or "Not supported by this executor",
    Callback = function(state)
        if not sUNCSupport.queueteleport then
            Library:Notify({ Title = "Auto Execute", Description = "queue_on_teleport not supported!", Duration = 3 })
            Library.Toggles.AutoExecute:SetValue(false)
            return
        end
        pcall(function()
            if not isfolder("ProjectEToHScript") then makefolder("ProjectEToHScript") end
            writefile(autoExecuteFile, tostring(state))
        end)
        if state then
            queueteleport([[
                local uiStyle = "Obsidian"
                pcall(function()
                    if isfile("ProjectEToHScript/ui_style.txt") then
                        uiStyle = readfile("ProjectEToHScript/ui_style.txt")
                    end
                end)
                SCRIPT_KEY = "KEYLESS"
                loadstring(game:HttpGet("https://raw.githubusercontent.com/cslp1/Project-EToH-Script/refs/heads/main/SC%20Script.lua"))()
            ]])
        end
    end,
})
if not sUNCSupport.queueteleport then
    Library.Toggles.AutoExecute:SetDisabled(true)
end
MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu bind")
    :AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
MenuGroup:AddButton("Rejoin", function()
    local TeleportService = game:GetService("TeleportService")
    local player = game:GetService("Players").LocalPlayer
    local inPrivate = game.PrivateServerId ~= ""
    Library:Notify({ Title = "Rejoin", Description = "Rejoining server...", Duration = 3 })

    local function onFail(msg)
        if inPrivate then
            Library:Notify({ Title = "Rejoin", Description = "Can't rejoin a private server from a script (Roblox restricts it)." .. (msg and (" " .. tostring(msg)) or ""), Duration = 8 })
        else
            pcall(function() TeleportService:Teleport(game.PlaceId, player) end)
        end
    end

    local conn
    conn = TeleportService.TeleportInitFailed:Connect(function(plr, _result, msg)
        if plr ~= player then return end
        conn:Disconnect()
        onFail(msg)
    end)

    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
    end)
    if not ok then
        conn:Disconnect()
        onFail(err)
    end
end)
MenuGroup:AddButton("Unload", function()
    _G.ProjectEToHLoaded = nil
    Library:Unload()
end)
Library.ToggleKeybind = Options.MenuKeybind

local CreditsGroup = Tabs.UISettings:AddRightGroupbox("Credits")
CreditsGroup:AddLabel('<font color="rgb(255,210,70)">[Mr.man]</font>  Owner', true)
CreditsGroup:AddLabel('<font color="rgb(90,200,255)">[MaybeIsRealZack]</font>  Original Creator', true)
CreditsGroup:AddLabel('<font color="rgb(120,230,120)">[canadianeditz]</font>  Contributor', true)

local OtherScriptsGroup = Tabs.UISettings:AddRightGroupbox("Other Scripts")
local function copyLoadstring(name, code)
    local ok = pcall(setclipboard, code)
    Library:Notify({
        Title       = "Other Scripts",
        Description  = ok and ("Copied " .. name .. " loadstring to clipboard") or "setclipboard isn't supported by your executor",
        Duration    = 4,
    })
end
OtherScriptsGroup:AddButton({
    Text     = "Original Script",
    Tooltip  = "Original script of this project. Click to copy its loadstring.",
    Callback = function()
        copyLoadstring("Original Script", 'loadstring(game:HttpGet("https://raw.githubusercontent.com/MaybeIsRealZack/Project-EToH-Script/refs/heads/main/Loader.lua"))()')
    end,
})
OtherScriptsGroup:AddButton({
    Text     = "SC Script",
    Tooltip  = "Focuses on SC towers. Click to copy its loadstring.",
    Callback = function()
        copyLoadstring("SC Script", 'loadstring(game:HttpGet("https://raw.githubusercontent.com/cslp1/Project-SC-Script/refs/heads/main/SC%20Script.lua"))()')
    end,
})


ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:SetFolder("ProjectEToHScript")
SaveManager:IgnoreThemeSettings()
ThemeManager:ApplyToTab(Tabs.UISettings)
SaveManager:BuildConfigSection(Tabs.UISettings)
SaveManager:LoadAutoloadConfig()

for idx, toggle in pairs(Library.Toggles) do
    if type(toggle) == "table" and toggle.OnChanged then
        toggle:OnChanged(function(value)
            local label = (type(toggle.Text) == "string" and toggle.Text) or tostring(idx)
            logAction(("Toggle: %s -> %s"):format(label, value and "ON" or "OFF"))
        end)
    end
end
logAction("Script loaded")

_G.ProjectEToHLoaded = true
