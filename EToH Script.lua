if _G.ProjectEToHLoaded then
    warn("[Project EToH Script] Already loaded!")
    return
end

local autoExecuteFile = "ProjectEToHScript/auto_execute.txt"
local uiStyleFile = "ProjectEToHScript/ui_style.txt"
local uiMigrationFile = "ProjectEToHScript/ui_migrated_pes.txt"
local autoExecuteDefault = false
pcall(function()
    if isfile(autoExecuteFile) then
        autoExecuteDefault = readfile(autoExecuteFile) == "true"
    end
end)
-- "PES" is our own library (see PESUI.lua) and the default. Obsidian and Linoria stay
-- selectable as fallbacks. Owning the UI means nothing outside this repo can break the
-- menu -- an upstream push to Obsidian silently halted it once already.
local uiStyle = "PES"
pcall(function()
    -- One-time migration. Existing installs already have ui_style.txt saying "Obsidian"
    -- (the UI Style dropdown writes it), which would pin them to the old library forever
    -- and make the new default look like it never applied. Ignore the stored value once,
    -- switch to PES, then respect whatever is chosen from then on.
    if not isfile(uiMigrationFile) then
        if not isfolder("ProjectEToHScript") then makefolder("ProjectEToHScript") end
        writefile(uiStyleFile, "PES")
        writefile(uiMigrationFile, "1")
        return
    end
    if isfile(uiStyleFile) then
        local saved = readfile(uiStyleFile):gsub("%s+$", "")
        if saved == "PES" or saved == "Obsidian" or saved == "Linoria" then
            uiStyle = saved
        end
    end
end)

local PES_UI_URL =
    "https://raw.githubusercontent.com/cslp1/Project-EToH-Script/refs/heads/main/PESUI.lua"

local repo = ""
local Library, SaveManager, ThemeManager

if uiStyle == "Linoria" or uiStyle == "Obsidian" then
    if uiStyle == "Linoria" then
        repo = "https://raw.githubusercontent.com/mstudio45/LinoriaLib/main/"
    else
        -- Pinned to a known-good commit (2026-07-09) rather than tracking their main,
        -- so an upstream push can't land in this script unannounced.
        repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/398653c103a0b4a8d2a3b68bcd383af21814a512/"
    end
    Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
    SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
    ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
else
    -- PESUI ships its own SaveManager/ThemeManager exposing the same methods, so the
    -- setup block further down works unchanged. _G.PESUI_SOURCE lets a locally-built
    -- test copy inline the library instead of fetching it.
    --
    -- Guarded, because the UI Style setting that switches back to Obsidian lives INSIDE
    -- the menu: if PESUI failed to load there'd be no menu, and therefore no way to
    -- recover. On any failure, fall back to Obsidian and say so.
    local ok, result = pcall(function()
        if _G.PESUI_SOURCE then
            return loadstring(_G.PESUI_SOURCE, "PESUI")()
        end
        return loadstring(game:HttpGet(PES_UI_URL))()
    end)

    if ok and type(result) == "table" and result.CreateWindow then
        Library      = result
        SaveManager  = Library.SaveManager
        ThemeManager = Library.ThemeManager
    else
        warn("[Project EToH Script] PES UI failed to load, falling back to Obsidian: "
            .. tostring(result))
        uiStyle = "Obsidian"
        repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/398653c103a0b4a8d2a3b68bcd383af21814a512/"
        Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
        SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
        ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
        pcall(function() writefile(uiStyleFile, "Obsidian") end)
    end
end

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
local isDev = game:GetService("Players").LocalPlayer.Name == "cslp1"

local Tabs = {
    Main       = Window:AddTab("Main",        "zap"),
    UISettings = Window:AddTab("UI Settings", "settings"),
    Logs       = Window:AddTab("Logs",        "list"),
}
local Options  = Library.Options

-- ===== Action Log (Logs tab) =====
-- A rolling, newest-first log of everything the script does. logAction() is the sink;
-- most actions reach it automatically via the Library:Notify wrap below, and every
-- toggle flip is hooked at the end of the script.
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

-- Mirror every notification into the log -- covers virtually every in-script action,
-- since they all notify. Wrapped once, here, before any action can fire.
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
local startAutoPlay -- forward declaration (assigned where the Auto Play button is built)
local autoPlayStop = false -- set true to stop a running Auto Play without dying/rejoining

local baseRepo = "https://raw.githubusercontent.com/cslp1/Project-EToH-Script/refs/heads/main/Games/EToH/"
local registryUrl = "https://raw.githubusercontent.com/cslp1/Project-EToH-Script/refs/heads/main/Games/EToH/TowerRegistry.lua"

local Registry
local registryLoaded = false
-- Retry the fetch: a single failed HttpGet (GitHub raw hiccup / rate limit) would
-- otherwise drop us to the empty fallback registry -> "No towers found" with 0 towers.
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

-- Studs from the HumanoidRootPart center to the character's feet.
local PLAYER_FOOT_OFFSET = 3
-- Returns a position on top of `part`'s surface, raised so the character stands
-- on top of it instead of clipping into the part. Accounts for the part's size
-- and orientation so it works for thick and rotated parts, not just thin ones.
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

-- True if a tower's folder is actually loaded in workspace.Towers right now. Used so
-- the dropdown shows the towers physically present in the current place even if the
-- registry's hardcoded category PlaceId no longer matches (e.g. after a game update),
-- instead of silently filtering everything out and leaving a blank tower list.
local function towerFolderPresent(name)
    local towersFolder = workspace:FindFirstChild("Towers")
    return towersFolder ~= nil and towersFolder:FindFirstChild(name) ~= nil
end

local function towerFolder(name)
    local towersFolder = workspace:FindFirstChild("Towers")
    return towersFolder and towersFolder:FindFirstChild(name)
end

-- Resolve a tower's entry teleporter parts. Tries EToH's exact nesting first
-- (Teleporter.Teleporter.TPFRAME / Teleporter.TeleportTo), then falls back to a recursive
-- search by name so towers in other games using the same JToH kit (e.g. The Eternal Abyss)
-- resolve even if the hierarchy differs. Returns nil if the folder/part is gone.
-- Tower games don't agree on what the entry portal is called. Observed so far:
--   EToH  Teleporter.Teleporter.TPFRAME
--   TEA   Portal            (siblings: Frame, WinPad, SpawnPad)
--   CSCD  TP                (siblings: Checkpoints, Frame, DO_NOT_MOVE_...)
-- Ordered most- to least-specific. Deliberately excludes Frame (the tower's base) and
-- WinPad (the finish, not the entry).
local PORTAL_NAMES = {
    "TPFRAME", "Portal", "TP", "TeleportTo", "Teleporter", "Entrance", "SpawnPad", "Spawn",
}
-- Substring pass for games not covered above. Same exclusions.
local PORTAL_HINTS = { "tpframe", "portal", "teleport", "entrance", "spawnpad" }

-- Callers need a BasePart (they read .CFrame/.Position/.Size), but these can be Models
-- or Folders, so resolve down to an actual part.
local function toBasePart(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") and inst.PrimaryPart then return inst.PrimaryPart end
    return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function resolveTPFrame(name)
    local f = towerFolder(name)
    if not f then return nil end

    -- EToH's exact nesting first: cheapest, and unambiguous when it's there.
    local tp    = f:FindFirstChild("Teleporter")
    local inner = tp and tp:FindFirstChild("Teleporter")
    local exact = inner and inner:FindFirstChild("TPFRAME")
    if exact then
        local part = toBasePart(exact)
        if part then return part end
    end

    -- Then each known name, recursively, in priority order.
    for _, candidate in ipairs(PORTAL_NAMES) do
        local part = toBasePart(f:FindFirstChild(candidate, true))
        if part then return part end
    end

    -- Last resort: any part whose name merely looks like a portal.
    for _, descendant in ipairs(f:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local lower = descendant.Name:lower()
            for _, hint in ipairs(PORTAL_HINTS) do
                if lower:find(hint, 1, true) then return descendant end
            end
        end
    end

    return nil
end
local function resolveTeleportTo(name)
    local f = towerFolder(name)
    if not f then return nil end
    local tp    = f:FindFirstChild("Teleporter")
    local exact = tp and tp:FindFirstChild("TeleportTo")
    return exact or f:FindFirstChild("TeleportTo", true)
end

-- F9 diagnostic: dump a tower folder's children when entry resolution fails, so an
-- unexpected structure (a game that doesn't use the standard TPFRAME/TeleportTo names)
-- can be identified in one shot.
local function warnTowerStructure(name)
    local f = towerFolder(name)
    if not f then
        warn(("[Auto Play] no folder named '%s' in workspace.Towers"):format(name))
        return
    end
    -- Include ClassName: knowing whether the candidate is a Part, Model or Folder is what
    -- decides how to reach its BasePart when adding support for a new tower game.
    local kids = {}
    for _, c in ipairs(f:GetChildren()) do
        kids[#kids + 1] = ("%s (%s)"):format(c.Name, c.ClassName)
    end
    warn(("[Tower Portal] '%s' portal unresolved. Children: %s"):format(name, table.concat(kids, ", ")))
end

-- A place spec is one place id or a list of them; true if we're in one of them.
local function placeMatches(ids)
    if type(ids) == "table" then
        for _, id in ipairs(ids) do
            if id == currentPlaceId then return true end
        end
        return false
    end
    return ids == currentPlaceId
end

-- Which places an entry belongs to: its own `places` overrides its category's place(s).
-- Lets a tower share a category (and route folder) with towers in another game while being
-- restricted to only some of those places -- e.g. PoMTR is in the Pit of Misery category
-- but doesn't exist in The Eternal Abyss, so it pins itself to the original place.
local function entryMatchesPlace(entry)
    if entry.places ~= nil then
        return placeMatches(entry.places)
    end
    return placeMatches(Registry.Categories[entry.category])
end

-- Is the current place one the registry recognizes (its id appears in some category)?
local placeIsKnown = false
for _, ids in pairs(Registry.Categories or {}) do
    if placeMatches(ids) then
        placeIsKnown = true
        break
    end
end

-- Whether to list an entry here. In a KNOWN place we trust the registry's place mapping
-- exactly. The folder-name fallback (show anything whose folder happens to be loaded) is
-- only for UNKNOWN places -- e.g. EToH after a place-id update -- otherwise a different
-- game that reuses EToH acronyms (The Eternal Abyss: ToSD/ToTF/ToER/...) would surface
-- every colliding tower even though those aren't the real EToH towers.
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
    }
    table.insert(DropdownValues, n)
end

-- Surface why the tower list is empty instead of failing silently. This usually means
-- the registry didn't load, or none of its towers match this place (PlaceId may have
-- changed in a game update) and none are loaded in workspace.Towers.
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
    Tooltip     = "Auto Play the tower this many times. The Completion Time above is the TOTAL for all repeats, split evenly across them.",
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
            local routeSrc
            local ok = pcall(function() routeSrc = game:HttpGet(config.routeUrl) end)
            if not ok or not routeSrc then return end
            local fn = loadstring(routeSrc)
            if not fn then return end
            local ok2, getCheckpoints = pcall(fn)
            if not ok2 or type(getCheckpoints) ~= "function" then return end
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
-- The RestartBrick: touching it sends you back to the lobby (it has a TouchInterest).
-- It must be TOUCHED, not just teleported near -- that's why the old "set CFrame above
-- it" approach never returned you.
local function getLobbyReturnPart()
    local misc = workspace:FindFirstChild("Misc")
    local part = misc and misc:FindFirstChild("RestartBrick")
    if part then return part end
    return workspace:FindFirstChild("RestartBrick", true)
end

-- After a win: wait 5s, fire the RestartBrick's touch to return to the lobby, then wait
-- another 5s. Shared by the Return to Lobby toggle and Auto Play repeats. Never re-enters.
local function returnToLobby()
    local player = game:GetService("Players").LocalPlayer
    task.wait(5)
    local part = getLobbyReturnPart()
    local char = player.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if part and hrp then
        hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0)
        if firetouchinterest then
            -- Directly fire the touch a few times so the return reliably registers.
            for _ = 1, 3 do
                pcall(function()
                    firetouchinterest(part, hrp, 0)
                    firetouchinterest(part, hrp, 1)
                end)
                task.wait(0.1)
            end
        else
            -- No firetouchinterest: physically overlap the part so a real touch fires.
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

-- Suggested seconds for a single tower.
local function towerSuggestedSec(name)
    local t = SuggestedTimes[name]
    return t and ((tonumber(t.min) or 0) * 60 + (tonumber(t.sec) or 0)) or 0
end
-- The tower names shown in the Auto Complete dropdown: the registry towers, plus any
-- added at runtime by Auto Detect Towers.
local acValues = {}
for _, name in ipairs(DropdownValues) do acValues[#acValues + 1] = name end
-- Towers ticked in the Auto Complete dropdown, in list order.
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
    Tooltip = "Press to Auto Play each ticked tower in order, returning to the lobby between each (wait 5s, touch RestartBrick, wait 5s). Time works like Repeat: with Use Suggested Time on, each tower uses its own suggested time (total = the sum shown); otherwise the custom Completion Time is applied per tower. Press again to stop.",
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

            -- Each tower is played for its own completion time: its suggested time when
            -- Use Suggested Time is on, otherwise the custom Completion Time applied per
            -- tower (the time is never split across towers).
            -- Save the UI fields we drive, then restore them at the end.
            local origTower  = Library.Options.TowerSelect.Value
            local origMin    = Library.Options.CompletionMin.Value
            local origSec    = Library.Options.CompletionSec.Value
            local origRepeat = Library.Options.RepeatCount.Value
            Library.Options.RepeatCount:SetValue("1") -- one run per tower

            for i, name in ipairs(towers) do
                if not _G.autoCompleteActive then break end
                if i > 1 then
                    Library:Notify({ Title = "Auto Complete", Description = ("(%d/%d) Returning to lobby..."):format(i, #towers), Duration = 4 })
                    returnToLobby()
                end
                if not _G.autoCompleteActive then break end
                Library:Notify({ Title = "Auto Complete", Description = ("(%d/%d) Playing %s"):format(i, #towers, name), Duration = 3 })
                -- Selecting the tower sets its suggested time when Use Suggested Time is on;
                -- otherwise the custom Completion Time is left as-is for every tower.
                Library.Options.TowerSelect:SetValue(name)
                startAutoPlay() -- yields until this tower's run finishes
            end

            -- Restore the UI fields.
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

-- ===== Personal Features (built specifically for gavin) =====
local PersonalBox = Tabs.Main:AddLeftGroupbox("Personal Features")

-- For each tower: enter via its teleporter, use a boost item, wait, then teleport to its
-- WinPad to complete it. Regular towers use the VM (slot 5) with a ~30-75s wait; citadels
-- ("Citadel of X" -> "CoX") use the jump coil (slot 4) with a 5-25 min wait, since they're
-- much larger. A boost-item way to clear towers, including ones not in the registry.
-- Returns to the lobby between towers.
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

            -- Enter the tower via its teleporter (TPFRAME then TeleportTo). Recursive search
            -- by name so it works regardless of how the game nests them.
            local entryParts = {}
            local tpFramePart = tower:FindFirstChild("TPFRAME", true)
            local teleToPart  = tower:FindFirstChild("TeleportTo", true)
            if tpFramePart then entryParts[#entryParts + 1] = tpFramePart end
            if teleToPart  then entryParts[#entryParts + 1] = teleToPart end
            for _, part in ipairs(entryParts) do
                local t0 = os.clock()
                repeat
                    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0) end
                    task.wait(0.1)
                until os.clock() - t0 > 1.5 or not _G.vmActive
            end

            -- Citadels get the jump coil (slot 4) + a long wait; everything else the VM (slot 5).
            local citadel  = isCitadel(name)
            local slotKey  = citadel and Enum.KeyCode.Four or Enum.KeyCode.Five
            local itemName = citadel and "jump coil" or "VM"
            VIM:SendKeyEvent(true, slotKey, false, game)
            task.wait(0.1)
            VIM:SendKeyEvent(false, slotKey, false, game)

            -- Wait for the boost to clear the tower: 5-15 min for citadels, 15-60s otherwise.
            local waitSec   = citadel and math.random(300, 900) or math.random(15, 60)
            local waitLabel = citadel and ("%.1f min"):format(waitSec / 60) or ("%ds"):format(waitSec)
            Library:Notify({ Title = "Auto VM", Description = ("(%d/%d) %s -- %s, waiting %s"):format(i, #towerNames, name, itemName, waitLabel), Duration = 4 })
            local waitUntil = os.clock() + waitSec
            while os.clock() < waitUntil and _G.vmActive do task.wait(0.5) end

            -- Teleport to the WinPad to complete the tower (recursive: nesting may vary).
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
    Tooltip = "For each ticked tower in 'Auto Complete: Towers': enter it, use the VM item (key 5), wait 30s, then teleport to the WinPad. Press again to stop.",
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
    Tooltip = "Detect every tower loaded in the current area (including ones not in the registry) and add them to the 'Auto Complete: Towers' list, so you can tick them and run Auto Use VM on them.",
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
            end
        end
        warn(("[Auto Detect] workspace.Towers has %d children; %d new: %s")
            :format(#children, added, table.concat(newNames, ", ")))
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
        -- Anti-stuck: while walking the route, if the character hasn't moved ~4 studs in
        -- 5s (e.g. caught on a vine or zipline that needs a jump to release), jump to free
        -- it. Runs in parallel with the walk and only acts while `walking` is true.
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

        -- Manual stop: pressing Auto Play again sets autoPlayStop; halt it like a death.
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

        local function checkDied()
            if died then
                local msg = stopReason == "stopped" and "Stopped!"
                    or (stopReason == "exited" and "Exited, stopping!" or "Character died, stopping!")
                Library:Notify({ Title = "Auto Play", Description = msg, Duration = 3 })
                clearRouteHighlights()
                stopAutoNoclip()
                isAutoPlaying = false
                return true
            end
            return false
        end
        Library:Notify({ Title = "Auto Play", Description = "Fetching " .. selected .. " route...", Duration = 3 })

        if config.isTowerRush then
            local VirtualInputManager = game:GetService("VirtualInputManager")
            local ok, tpFrame = pcall(config.tpFrame)
            if not ok or not tpFrame then
                warnTowerStructure(getTpFrameName(selected))
                Library:Notify({ Title = "Auto Play", Description = selected .. " teleporter not found!", Duration = 3 })
                isAutoPlaying = false
                stopAutoNoclip()
                return
            end
            Library:Notify({ Title = "Auto Play", Description = "Fetching " .. selected .. " tower list...", Duration = 3 })
            local r1trSrc
            local okFetch = pcall(function() r1trSrc = game:HttpGet(config.routeUrl) end)
            if not okFetch or not r1trSrc then
                Library:Notify({ Title = "Auto Play", Description = selected .. " fetch failed!", Duration = 5 })
                isAutoPlaying = false
                stopAutoNoclip()
                return
            end
            local r1trFn = loadstring(r1trSrc)
            if not r1trFn then
                Library:Notify({ Title = "Auto Play", Description = selected .. " parse failed!", Duration = 5 })
                isAutoPlaying = false
                stopAutoNoclip()
                return
            end
            local okR1, getTowers = pcall(r1trFn)
            if not okR1 or type(getTowers) ~= "function" then
                Library:Notify({ Title = "Auto Play", Description = selected .. " load failed!", Duration = 5 })
                isAutoPlaying = false
                stopAutoNoclip()
                return
            end
            local okR2, towerList = pcall(getTowers)
            if not okR2 or type(towerList) ~= "table" then
                Library:Notify({ Title = "Auto Play", Description = selected .. " tower list failed!", Duration = 5 })
                isAutoPlaying = false
                stopAutoNoclip()
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
                Library:Notify({ Title = "Auto Play", Description = "Fetching " .. towerName .. " route... (" .. towerIndex .. "/" .. #towerList .. ")", Duration = 3 })
                local routeSrc
                local okFetch = pcall(function() routeSrc = game:HttpGet(towerConfig.routeUrl) end)
                if not okFetch or not routeSrc then
                    Library:Notify({ Title = "Auto Play", Description = "Fetch failed for " .. towerName, Duration = 5 })
                    isAutoPlaying = false
                    stopAutoNoclip()
                    return
                end
                local towerSec
                if useCustomTime and totalSuggestedSec > 0 then
                    local st = SuggestedTimes[towerName]
                    local thisSuggestedSec = st and ((tonumber(st.min) or 0) * 60 + (tonumber(st.sec) or 0)) or 0
                    towerSec = totalCustomSec * (thisSuggestedSec / totalSuggestedSec)
                else
                    local tMin = tonumber(SuggestedTimes[towerName].min) or 3
                    local tSec = tonumber(SuggestedTimes[towerName].sec) or 0
                    towerSec = tMin * 60 + tSec
                end
                local towerDeadline = os.clock() + math.max(towerSec, 1)
                Library:Notify({ Title = "Auto Play", Description = "Entering " .. towerName .. "...", Duration = 3 })
                if towerIndex > 1 then
                    local ok2, teleportTo = pcall(towerConfig.teleportTo)
                    if not ok2 or not teleportTo then
                        Library:Notify({ Title = "Auto Play", Description = towerName .. " TeleportTo not found!", Duration = 3 })
                        isAutoPlaying = false
                        stopAutoNoclip()
                        return
                    end
                    Library:Notify({ Title = "Auto Play", Description = "Waiting for " .. towerName .. " teleport...", Duration = 3 })
                    local touched = false
                    local conn
                    conn = teleportTo.Touched:Connect(function(hit)
                        if hit:IsDescendantOf(char) and not touched then
                            touched = true
                            conn:Disconnect()
                        end
                    end)
                    while not touched do
                        if checkDied() then return end
                        local distToTP = (hrp.Position - teleportTo.Position).Magnitude
                        if distToTP < 10 then
                            touched = true
                            conn:Disconnect()
                            break
                        end
                        hrp.CFrame = teleportTo.CFrame + Vector3.new(0, 3, 0)
                        task.wait(0.1)
                    end
                    if checkDied() then return end
                end
                local posBeforeTP = hrp.Position
                task.wait(0.5)
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
                repeat
                    if checkDied() then
                        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
                        return
                    end
                    task.wait(0.1)
                    char = player.Character
                    hrp  = char and char:FindFirstChild("HumanoidRootPart")
                until hrp and (hrp.Position - posBeforeTP).Magnitude > 0.1
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
                if checkDied() then return end
                local fn, fnErr = loadstring(routeSrc)
                if not fn then
                    Library:Notify({ Title = "Auto Play", Description = towerName .. " parse failed: " .. tostring(fnErr), Duration = 5 })
                    isAutoPlaying = false
                    stopAutoNoclip()
                    return
                end
                local ok3, getCheckpoints = pcall(fn)
                if not ok3 or type(getCheckpoints) ~= "function" then
                    Library:Notify({ Title = "Auto Play", Description = towerName .. " load failed!", Duration = 5 })
                    isAutoPlaying = false
                    stopAutoNoclip()
                    return
                end
                local checkpoints
                repeat
                    if checkDied() then return end
                    local ok4, result = pcall(getCheckpoints)
                    if ok4 and type(result) == "table" and #result > 0 then
                        checkpoints = result
                    end
                    if not checkpoints then task.wait(0.1) end
                until checkpoints
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
                for i, step in ipairs(resolvedSteps) do
                    if checkDied() then return end
                    char = player.Character
                    hrp  = char and char:FindFirstChild("HumanoidRootPart")
                    if not hrp then
                        Library:Notify({ Title = "Auto Play", Description = "Character lost, stopping!", Duration = 3 })
                        isAutoPlaying = false
                        stopAutoNoclip()
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

                    local startRot   = hrp.CFrame - hrp.CFrame.Position
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
                        if dir ~= dir then return end -- nan check
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

        local routeSrc
        local ok0, err0 = pcall(function()
            routeSrc = game:HttpGet(config.routeUrl)
        end)
        if not ok0 or not routeSrc then
            Library:Notify({ Title = "Auto Play", Description = "Fetch failed: " .. tostring(err0), Duration = 5 })
            isAutoPlaying = false
            return
        end

        -- Load the route once and reuse it for every repeat. Re-running loadstring each
        -- repeat fails on executors that throttle/forward loadstring to a server.
        local fn, fnErr = loadstring(routeSrc)
        if not fn then
            Library:Notify({ Title = "Auto Play", Description = "Parse failed: " .. tostring(fnErr), Duration = 5 })
            isAutoPlaying = false
            return
        end
        local okLoad, getCheckpoints = pcall(fn)
        if not okLoad or type(getCheckpoints) ~= "function" then
            Library:Notify({ Title = "Auto Play", Description = "Load failed: " .. tostring(getCheckpoints), Duration = 5 })
            isAutoPlaying = false
            return
        end

        local repeatCount = math.max(math.floor(tonumber(Library.Options.RepeatCount.Value) or 1), 1)
        local reqSec = (tonumber(Library.Options.CompletionMin.Value) or 0) * 60
                     + (tonumber(Library.Options.CompletionSec.Value) or 0)
        -- The completion time is the time for EACH run (suggested or custom), never a
        -- total that gets split across repeats.
        local perRepeatTime = math.max(reqSec, 1)

        for rep = 1, repeatCount do
        local repTag = repeatCount > 1 and (" [" .. rep .. "/" .. repeatCount .. "]") or ""
        warn(("[ProjectEToH] Auto Play run %d/%d (%s) budget=%.1fs"):format(rep, repeatCount, tostring(selected), perRepeatTime))
        if rep > 1 then
            -- After the previous win, return to the lobby (5s wait, tp onto the return
            -- part, 5s wait), then re-enter the tower for the next run.
            Library:Notify({ Title = "Auto Play", Description = "Returning to lobby before next run..." .. repTag, Duration = 4 })
            returnToLobby()
            if died and stopReason == "exited" then checkDied() return end
            -- Returning respawns us at the lobby; refresh the character and re-apply setup.
            char = player.Character or player.CharacterAdded:Wait()
            char:WaitForChild("HumanoidRootPart", 10)
            task.wait(0.5)
            char = player.Character
            hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then
                Library:Notify({ Title = "Auto Play", Description = "Character didn't respawn, stopping!", Duration = 3 })
                stopAutoNoclip()
                isAutoPlaying = false
                return
            end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
                if hum.Sit then hum.Sit = false end
                hum.PlatformStand = true
            end
            -- Re-arm death detection on the fresh character; ignore the win/respawn itself.
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
        -- Each run is a full Auto Play pass -- go to the teleporter, enter the tower, and
        -- walk the route -- the same as pressing Auto Play again after a completion.
        local ok, tpFrame = pcall(config.tpFrame)
        if not ok or not tpFrame then
            warnTowerStructure(getTpFrameName(selected))
            Library:Notify({ Title = "Auto Play", Description = selected .. " teleporter not found!", Duration = 3 })
            isAutoPlaying = false
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
            task.wait(0.1)
        end
        if checkDied() then return end
        local ok2, teleportTo = pcall(config.teleportTo)
        if not ok2 or not teleportTo then
            Library:Notify({ Title = "Auto Play", Description = "TeleportTo not found!", Duration = 3 })
            isAutoPlaying = false
            return
        end
        Library:Notify({ Title = "Auto Play", Description = "Waiting for teleport...", Duration = 3 })
        local touched = false
        local connection
        connection = teleportTo.Touched:Connect(function(hit)
            if hit:IsDescendantOf(char) and not touched then
                touched = true
                connection:Disconnect()
            end
        end)
        while not touched do
            if checkDied() then return end
            hrp.CFrame = teleportTo.CFrame + Vector3.new(0, 3, 0)
            task.wait(0.1)
        end
        if checkDied() then return end
        Library:Notify({ Title = "Auto Play", Description = "Waiting for teleport to complete...", Duration = 3 })
        local posBeforeTP = hrp.Position
        local VirtualInputManager = game:GetService("VirtualInputManager")
        task.wait(0.5)
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
        repeat
            if checkDied() then
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
                return
            end
            task.wait(0.1)
            char = player.Character
            hrp  = char and char:FindFirstChild("HumanoidRootPart")
        until hrp and (hrp.Position - posBeforeTP).Magnitude > 0.1
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
        if checkDied() then return end
        local deadline = os.clock() + perRepeatTime
        local checkpoints
        local lastErr = ""
        local lastNotify = os.clock()
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
        until checkpoints
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
        local remainingTime = math.max(deadline - os.clock(), 1)
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
                -- Character removed without a death = tower win / respawn (checkDied()
                -- above already handles real deaths). End this run instead of stopping
                -- autoplay, so the repeat loop can wait for respawn and re-enter.
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
        startAutoPlay()
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

-- Tower Portal: type an acronym, get live matches, teleport to that tower's entry portal.
--
-- Kept inside its own function so its locals live in this function's registers rather than
-- the main chunk's -- Luau caps a function at 200 locals and the top level is already busy.
local function _initTowerPortal()
    local PortalBox = Tabs.Main:AddRightGroupbox("Tower Portal")

    local MAX_RESULTS = 12
    local searchText  = ""
    local labelToName = {}   -- display label -> real tower folder name
    local lastLabels  = ""   -- serialised list, so we only push changes to the dropdown

    -- Everything we could plausibly teleport to: registry towers valid for this place,
    -- plus whatever is physically in workspace.Towers (catches towers the registry
    -- doesn't list, e.g. after a place-id change).
    local function candidates()
        local seen, out = {}, {}
        for name in pairs(TowerConfigs) do
            local folderName = getTpFrameName(name)
            if not seen[folderName] then
                seen[folderName] = true
                out[#out + 1] = folderName
            end
        end
        local towersFolder = workspace:FindFirstChild("Towers")
        if towersFolder then
            for _, child in ipairs(towersFolder:GetChildren()) do
                if not seen[child.Name] then
                    seen[child.Name] = true
                    out[#out + 1] = child.Name
                end
            end
        end
        return out
    end

    -- Rank: exact acronym, then prefix, then substring. Empty query lists everything.
    local function rankOf(name, query)
        if query == "" then return 3 end
        local lower = name:lower()
        if lower == query then return 0 end
        if lower:sub(1, #query) == query then return 1 end
        if lower:find(query, 1, true) then return 2 end
        return nil
    end

    local function refresh()
        -- The input is created before the dropdown and may fire its callback immediately,
        -- so there's a window where PortalMatch doesn't exist yet.
        if not Options.PortalMatch then return end

        local query  = searchText:gsub("%s", ""):lower()
        local ranked = {}
        for _, name in ipairs(candidates()) do
            local rank = rankOf(name, query)
            if rank then ranked[#ranked + 1] = { name = name, rank = rank } end
        end
        table.sort(ranked, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            return a.name:lower() < b.name:lower()
        end)

        local labels = {}
        labelToName = {}
        for i, entry in ipairs(ranked) do
            if i > MAX_RESULTS then break end
            -- Say up front whether it's actually teleportable. EToH's ultra-LDM unloads
            -- towers you aren't near, and an unloaded tower has no portal to jump to.
            local loaded = towerFolder(entry.name) ~= nil
            local label  = loaded and entry.name or (entry.name .. "  (not loaded)")
            labels[#labels + 1] = label
            labelToName[label]  = entry.name
        end

        -- Only touch the dropdown when the list really changed, so it doesn't fight the
        -- user while they have it open.
        local serialised = table.concat(labels, "\0")
        if serialised == lastLabels then return end
        lastLabels = serialised

        local keep = Options.PortalMatch and Options.PortalMatch.Value
        Options.PortalMatch:SetValues(labels)
        if keep and labelToName[keep] then
            Options.PortalMatch:SetValue(keep)
        end
    end

    PortalBox:AddInput("PortalSearch", {
        Text        = "Search",
        Default     = "",
        Finished    = false,   -- fire per keystroke so suggestions track typing
        Placeholder = "Acronym, e.g. ToH",
        Tooltip     = "Type part of a tower's acronym. Matches update as you type.",
        Callback    = function(value)
            searchText = value or ""
            refresh()
        end,
    })

    PortalBox:AddDropdown("PortalMatch", {
        Text      = "Matches",
        Values    = {},
        Default   = nil,
        AllowNull = true,
        Tooltip   = "Closest matches, best first. '(not loaded)' means the tower isn't in workspace yet.",
    })

    PortalBox:AddButton({
        Text     = "Teleport to Portal",
        Tooltip  = "Teleport to the selected tower's entry portal (TPFRAME).",
        Callback = function()
            local label = Options.PortalMatch and Options.PortalMatch.Value
            local name  = label and labelToName[label]
            if not name then
                Library:Notify({ Title = "Tower Portal", Description = "Pick a tower first.", Duration = 3 })
                return
            end

            local part = resolveTPFrame(name)
            if not part then
                -- Dump the folder's children to F9 so an unexpected hierarchy is one look away.
                warnTowerStructure(name)
                Library:Notify({
                    Title       = "Tower Portal",
                    Description = ("No portal found for %s -- it may not be loaded yet. See F9."):format(name),
                    Duration    = 5,
                })
                return
            end

            local char = game:GetService("Players").LocalPlayer.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then
                Library:Notify({ Title = "Tower Portal", Description = "No character to teleport.", Duration = 3 })
                return
            end

            -- Keep the current facing; only move the position, same as the other teleports.
            hrp.CFrame = CFrame.new(getTopPos(part)) * (hrp.CFrame - hrp.CFrame.Position)
            Library:Notify({ Title = "Tower Portal", Description = "Teleported to " .. name, Duration = 3 })
        end,
    })

    -- Keep scanning: towers stream in and out as you move, so a match that was "(not
    -- loaded)" a second ago may be teleportable now.
    task.spawn(function()
        while true do
            task.wait(1)
            if not Library.Unloaded then
                pcall(refresh)
            else
                break
            end
        end
    end)

    refresh()
end
_initTowerPortal()

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

        -- Tear down any previous noclip hooks.
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
        -- Disable collision on every character part, including the HumanoidRootPart,
        -- and immediately revert it whenever the game re-enables it. Some areas (e.g.
        -- Pit of Misery) re-assert floor collision every frame, which a once-per-frame
        -- sweep can lose the race against; reacting to the property change wins it.
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

        -- Per-frame sweep on both sides of the physics step, as a fallback for
        -- anything the signal hooks miss.
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
                -- Character respawned, reinitialize
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
    Tooltip = "Each jump press gives one jump, mid-air included -- holding the key won't keep you rising.",
    Callback = function(state)
        if _G.InfiniteJumpConn then
            _G.InfiniteJumpConn:Disconnect()
            _G.InfiniteJumpConn = nil
        end
        if state then
            local Players = game:GetService("Players")
            local UIS     = game:GetService("UserInputService")
            -- InputBegan fires ONCE per key press (unlike JumpRequest, which repeats
            -- while held), so you get a single jump per press instead of flying upward.
            _G.InfiniteJumpConn = UIS.InputBegan:Connect(function(input)
                if UIS:GetFocusedTextBox() then return end
                if input.KeyCode ~= Enum.KeyCode.Space and input.KeyCode ~= Enum.KeyCode.ButtonA then return end
                local char = Players.LocalPlayer.Character
                local hum  = char and char:FindFirstChildOfClass("Humanoid")
                if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
            end)
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
            -- Idled fires just before Roblox kicks for inactivity; a VirtualUser
            -- right-click resets the idle timer without affecting gameplay.
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
            -- Snapshot the original lighting once so we can restore it later.
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
            -- Re-assert every frame -- dark towers keep overwriting lighting per area.
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

-- Godmode is split into independent methods -- enable any one or several at once.

-- Not every place has ReplicatedStorage.DamageEvent -- The Eternal Abyss doesn't.
-- A bare WaitForChild there yields FOREVER, and since the godmode toggles are applied
-- during load, that silently halts the rest of the script: the UI Settings tab gets
-- created but never filled, and the Theme/Save managers never run. Time out instead.
local function getDamageEvent()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    return ReplicatedStorage:FindFirstChild("DamageEvent")
        or ReplicatedStorage:WaitForChild("DamageEvent", 5)
end

-- Turn the toggle back off and say why, so it can't sit there looking enabled.
local function godmodeUnavailable(toggleName)
    Library:Notify({
        Title       = "Godmode",
        Description = "No DamageEvent in this place -- that mode isn't available here.",
        Duration    = 5,
    })
    local toggle = Library.Toggles[toggleName]
    if toggle then toggle:SetValue(false) end
end

-- Hook: intercept DamageEvent:FireServer through __namecall so damage never reaches
-- the server. Cleanest, but needs hookmetamethod + getnamecallmethod support.
local function setGodmodeHook(state)
    if godmodeOriginal then
        hookmetamethod(game, "__namecall", godmodeOriginal)
        godmodeOriginal = nil
    end
    if not state then return end
    local damageEvent = getDamageEvent()
    if not damageEvent then return godmodeUnavailable("GodmodeHook") end
    godmodeOriginal = hookmetamethod(game, "__namecall", function(self, ...)
        if self == damageEvent and getnamecallmethod() == "FireServer" then
            return
        end
        return godmodeOriginal(self, ...)
    end)
end

-- Auto-Heal: heal back to full whenever health drops (heal loop via DamageEvent).
local function setGodmodeHeal(state)
    if godmodeV2Connection then
        godmodeV2Connection:Disconnect()
        godmodeV2Connection = nil
    end
    if not state then return end
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local damageEvent = getDamageEvent()
    if not damageEvent then return godmodeUnavailable("GodmodeHeal") end
    godmodeV2Connection = RunService.Heartbeat:Connect(function()
        local char = Players.LocalPlayer.Character
        if not char then return end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health < humanoid.MaxHealth then
            damageEvent:FireServer(-humanoid.MaxHealth)
        end
    end)
end

-- Kill Bricks: set CanTouch = false on every kill brick so it can't register a hit.
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
    Tooltip = "Blocks ALL damage by hooking the game's DamageEvent so the damage call never reaches the server -- you simply never take damage. The cleanest, most reliable method, but needs executor support for hookmetamethod + getnamecallmethod (greyed out if unsupported).",
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
    Tooltip = "Instantly heals you back to full whenever you take damage (a loop that fires the DamageEvent with negative damage). Works on ANY executor, but you may flash a bit of damage before healing, so it's less clean than the hook.",
    Callback = function(state)
        setGodmodeHeal(state)
    end,
})

PlayerBox:AddToggle("GodmodeKillBricks", {
    Text    = "Godmode: Disable Kill Bricks",
    Default = false,
    Tooltip = "Turns off touch detection on every kill brick (parts named \"Kill Brick\" or holding a 'kills' value), including ones spawned later, so they can't kill you. Stops kill-brick deaths at the source but does nothing against other damage.",
    Callback = function(state)
        setGodmodeKillBricks(state)
    end,
})

if not sUNCSupport.Godmode then
    Library.Toggles.GodmodeHook:SetDisabled(true)
end

-- Apply the current (default or saved) states on load.
setGodmodeHook(Library.Toggles.GodmodeHook.Value)
setGodmodeHeal(Library.Toggles.GodmodeHeal.Value)
setGodmodeKillBricks(Library.Toggles.GodmodeKillBricks.Value)

Library.Toggles.UseSuggestedTime:SetValue(true)
local MenuGroup = Tabs.UISettings:AddLeftGroupbox("Menu")
MenuGroup:AddDropdown("UIStyle", {
    Text    = "UI Style",
    Values  = { "PES", "Obsidian", "Linoria" },
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
-- Both PESUI and Obsidian implement Window:SetCornerRadius; Linoria doesn't.
local isObsidian = repo:find("deividcomsono") ~= nil or uiStyle == "PES"

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
        -- In a private/VIP server, Teleport(PlaceId) targets a restricted public place
        -- (Error 773) and Roblox blocks client teleports into the private server, so
        -- there's no client-side way to rejoin it -- report instead of throwing 773.
        -- In a public server, fall back to a fresh server.
        if inPrivate then
            Library:Notify({ Title = "Rejoin", Description = "Can't rejoin a private server from a script (Roblox restricts it)." .. (msg and (" " .. tostring(msg)) or ""), Duration = 8 })
        else
            pcall(function() TeleportService:Teleport(game.PlaceId, player) end)
        end
    end

    -- Catch async teleport failures so we handle them ourselves instead of the raw dialog.
    local conn
    conn = TeleportService.TeleportInitFailed:Connect(function(plr, _result, msg)
        if plr ~= player then return end
        conn:Disconnect()
        onFail(msg)
    end)

    -- TeleportToPlaceInstance rejoins the exact server you're in (works in public).
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
CreditsGroup:AddLabel('<font color="rgb(90,200,255)">[cslp1]</font>  Original Creator', true)
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
        copyLoadstring("Original Script", 'loadstring(game:HttpGet("https://raw.githubusercontent.com/cslp1/Project-EToH-Script/refs/heads/main/Loader.lua"))()')
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

-- Log every toggle flip. Installed last -- after LoadAutoloadConfig -- so restoring a
-- saved config on startup doesn't spam the log; only genuine flips after load are recorded.
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
