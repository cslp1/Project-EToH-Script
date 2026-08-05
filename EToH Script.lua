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

-- Dev/testing override: pick a library for this run without touching the saved setting
-- (the mobile test loader uses it to guarantee the PES UI, which owns the mobile layout).
if _G.PES_FORCE_UI_STYLE == "PES" or _G.PES_FORCE_UI_STYLE == "Obsidian" or _G.PES_FORCE_UI_STYLE == "Linoria" then
    uiStyle = _G.PES_FORCE_UI_STYLE
end

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

local UNCSupport = {
    hookmetamethod    = okHook and hookmetamethod ~= nil,
    getnamecallmethod = okNcm  and getnamecallmethod ~= nil,
    queueteleport     = queueteleport ~= nil,
}
UNCSupport.Godmode = UNCSupport.hookmetamethod and UNCSupport.getnamecallmethod

print("[Project EToH Script] Functions Check:")
print("[Project EToH Script] Metatable Library:")
print((UNCSupport.hookmetamethod    and "✅" or "❌") .. " hookmetamethod"    .. (not okHook and ": " .. tostring(errHook) or ""))
print((UNCSupport.getnamecallmethod and "✅" or "❌") .. " getnamecallmethod" .. (not okNcm  and ": " .. tostring(errNcm)  or ""))
print("[Project EToH Script] Miscellaneous Library:")
print((UNCSupport.queueteleport     and "✅" or "❌") .. " queueonteleport")
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
    Main       = Window:AddTab("Main",        "house"),
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
-- Why the last attempt failed. Every stage below used to throw its error away, so a
-- registry with a syntax error looked identical to a network failure: an empty tower
-- dropdown and a notification blaming HttpGet. Keep the reason and report it.
local registryErr = nil
-- Retry the fetch: a single failed HttpGet (GitHub raw hiccup / rate limit) would
-- otherwise drop us to the empty fallback registry -> "No towers found" with 0 towers.
for attempt = 1, 4 do
    local ok_reg, reg_src = pcall(function() return game:HttpGet(registryUrl) end)
    if not ok_reg then
        registryErr = "fetch failed: " .. tostring(reg_src)
    elseif type(reg_src) ~= "string" or #reg_src == 0 then
        registryErr = "fetch returned an empty body"
    else
        -- loadstring returns nil PLUS the syntax error; keeping that second value is the
        -- difference between "no towers, no idea why" and being told the exact line.
        local fn, syntaxErr = loadstring(reg_src)
        if not fn then
            registryErr = "registry has a syntax error: " .. tostring(syntaxErr)
        else
            local ok2, result = pcall(fn)
            if not ok2 then
                registryErr = "registry errored while running: " .. tostring(result)
            elseif type(result) ~= "table" or type(result.Towers) ~= "table" then
                registryErr = "registry didn't return a table with a Towers list"
            else
                Registry = result
                registryLoaded = true
                registryErr = nil
                break
            end
        end
    end
    warn(("[ProjectEToH] tower registry attempt %d/4 failed -- %s"):format(attempt, registryErr))
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

-- ===== Pit of Misery XL (place 14894545694) -- dynamic checkpoint routing =====
-- This game ships no per-tower route files. Every tower that has a folder in
-- workspace.Checkpoints is auto-discovered, and its route is that folder's numbered
-- checkpoints walked in NUMERIC ORDER (the child names are the order -- explorer order is
-- not), finishing on the tower's WinPad. Add a tower in-game and it just appears; no
-- script edit needed.
local POM_PLACE, POM_UNIVERSE = 14894545694, 5131529859
local isPomXL = (currentPlaceId == POM_PLACE) or (game.GameId == POM_UNIVERSE)

-- Entry portal: workspace["Tower Portals"].<name> -> a touchable Teleporter part.
local function pomPortal(name)
    local portals = workspace:FindFirstChild("Tower Portals")
    local folder  = portals and portals:FindFirstChild(name)
    if not folder then return nil end
    return toBasePart(folder:FindFirstChild("Teleporter", true))
        or toBasePart(folder:FindFirstChild("Portal", true))
        or toBasePart(folder)
end

-- WinPad so the route finishes on it and the win registers. The Winpads folder's naming
-- isn't confirmed, so try an exact-name child then a name-contains match; nil just means
-- the route ends on the last numbered checkpoint.
local function pomWinPad(name)
    local wpf = workspace:FindFirstChild("Winpads")
    if not wpf then return nil end
    local exact = wpf:FindFirstChild(name)
    if exact then return toBasePart(exact) end
    for _, c in ipairs(wpf:GetChildren()) do
        if c.Name:find(name, 1, true) then return toBasePart(c) end
    end
    return nil
end

-- The route: numbered checkpoints (sorted by number, not explorer order) + the WinPad.
-- Rebuilt on each call so parts that stream in late are picked up.
local function pomRoute(name)
    local cpRoot = workspace:FindFirstChild("Checkpoints")
    local folder = cpRoot and cpRoot:FindFirstChild(name)
    if not folder then return {} end
    local ordered = {}
    for _, c in ipairs(folder:GetChildren()) do
        local num = tonumber(c.Name)
        if num then ordered[#ordered + 1] = { num = num, inst = c } end
    end
    table.sort(ordered, function(a, b) return a.num < b.num end)
    local route = {}
    for _, e in ipairs(ordered) do
        local part = toBasePart(e.inst)
        if part then route[#route + 1] = part end
    end
    local wp = pomWinPad(name)
    if wp then route[#route + 1] = wp end
    return route
end

if isPomXL then
    local cpRoot = workspace:FindFirstChild("Checkpoints")
    if cpRoot then
        for _, folder in ipairs(cpRoot:GetChildren()) do
            local n = folder.Name
            local count = 0
            for _, c in ipairs(folder:GetChildren()) do
                if tonumber(c.Name) then count = count + 1 end
            end
            if count > 0 and not TowerConfigs[n] then
                -- Generous default budget (~45s per checkpoint, min 60s) so long Citadels
                -- don't walk fast enough to trip the server-side skip check. Tune per run
                -- with the Completion Time fields.
                local secTotal = math.max(count * 45, 60)
                SuggestedTimes[n] = { min = tostring(math.floor(secTotal / 60)), sec = tostring(secTotal % 60) }
                TowerConfigs[n] = {
                    tpFrame    = function() return pomPortal(n) end,
                    teleportTo = function() return pomPortal(n) end,
                    routeFn    = function() return pomRoute(n) end,
                }
                table.insert(DropdownValues, n)
            end
        end
        table.sort(DropdownValues)
    end
end

-- Resolve a tower's getCheckpoints() function. PoM XL towers carry a routeFn and use it
-- directly; every other tower fetches + loadstrings its route file as before. Returns the
-- function, or nil + an error message.
local function loadRouteFn(config)
    if config.routeFn then return config.routeFn end
    local routeSrc
    local ok, err = pcall(function() routeSrc = game:HttpGet(config.routeUrl) end)
    if not ok or not routeSrc then return nil, "Fetch failed: " .. tostring(err) end
    local fn, fnErr = loadstring(routeSrc)
    if not fn then return nil, "Parse failed: " .. tostring(fnErr) end
    local ok2, getCheckpoints = pcall(fn)
    if not ok2 or type(getCheckpoints) ~= "function" then
        return nil, "Load failed: " .. tostring(getCheckpoints)
    end
    return getCheckpoints
end

-- Surface why the tower list is empty instead of failing silently. This usually means
-- the registry didn't load, or none of its towers match this place (PlaceId may have
-- changed in a game update) and none are loaded in workspace.Towers.
if #DropdownValues == 0 then
    local towersFolder = workspace:FindFirstChild("Towers")
    local loadedCount = towersFolder and #towersFolder:GetChildren() or 0
    local reason = registryLoaded
        and "The registry may be out of date for this game version."
        or ((registryErr or "the tower registry couldn't be loaded")
            .. " -- full details in the F9 console.")
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
SuggestedLabel = TowerBox:AddLabel(getSuggestedLabel(DropdownValues[1] or "NEAT"))
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
TowerBox:AddInput("LobbyDelay", {
    Text        = "Delay Before Lobby (s)",
    Default     = "5",
    Numeric     = true,
    Placeholder = "5",
    Tooltip     = "After winning, wait this long before returning to spawn. Lowering it too far can cut off the win registering.",
})
TowerBox:AddInput("NextTowerDelay", {
    Text        = "Delay Before Next Tower (s)",
    Default     = "5",
    Numeric     = true,
    Placeholder = "5",
    Tooltip     = "After returning to spawn, wait this long before entering the next tower or repeating. Lowering it too far can enter before the lobby finishes loading.",
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
            local getCheckpoints = loadRouteFn(config)
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
-- The RestartBrick: touching it sends you back to the lobby (it has a TouchInterest).
-- It must be TOUCHED, not just teleported near -- that's why the old "set CFrame above
-- it" approach never returned you.
local function getLobbyReturnPart()
    local misc = workspace:FindFirstChild("Misc")
    local part = misc and misc:FindFirstChild("RestartBrick")
    if part then return part end
    return workspace:FindFirstChild("RestartBrick", true)
end

-- Reads a Numeric input as a number, falling back to `default` if it's blank, junk or
-- negative (the inputs are free text, so all three are reachable).
local function numOpt(name, default)
    local o = Library.Options[name]
    local v = o and tonumber(o.Value)
    if not v or v < 0 then return default end
    return v
end

-- After a win: wait (Delay Before Lobby), fire the RestartBrick's touch to return to the
-- lobby, then wait (Delay Before Next Tower) before the next tower / repeat is entered.
-- Shared by the Return to Lobby toggle and Auto Play repeats. Never re-enters.
local function returnToLobby()
    local player = game:GetService("Players").LocalPlayer
    task.wait(numOpt("LobbyDelay", 5))
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
    task.wait(numOpt("NextTowerDelay", 5))
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
        -- Declared before the stabiliser below, which behaves differently once the route
        -- starts (see there).
        local walking = false
        -- Keeps the character from fighting the route tween.
        --
        -- While `walking`, the tween is what drives position, so ANY leftover velocity is
        -- pure interference: a contact that survives noclip shoves the body sideways
        -- against the tween (stutter, and it can wedge in geometry), and the angular
        -- velocity from that same contact spins the root part -- which is what throws the
        -- camera around, since it follows the root's orientation. Zero both.
        --
        -- Before the route starts we still walk into the tower under our own power, so
        -- only gravity is cancelled there; zeroing everything would pin us in place.
        local function stabilise()
            if hrp and hrp.Parent then
                if walking then
                    hrp.AssemblyLinearVelocity  = Vector3.zero
                    hrp.AssemblyAngularVelocity = Vector3.zero
                else
                    hrp.AssemblyLinearVelocity = Vector3.new(
                        hrp.AssemblyLinearVelocity.X,
                        0,
                        hrp.AssemblyLinearVelocity.Z
                    )
                end
            end
            local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
            if h then
                if h.Sit then h.Sit = false end
                -- Re-assert: some towers knock the humanoid back out of PlatformStand,
                -- and once it's walking/standing again it fights the tween too.
                if walking and not h.PlatformStand then h.PlatformStand = true end
            end
        end
        -- Both sides of the physics step: Heartbeat alone only cleans up AFTER the solver
        -- has already applied the push, which is a frame of visible spin each time.
        local antiGravConn  = RunService.Heartbeat:Connect(stabilise)
        local antiGravConn2 = RunService.Stepped:Connect(stabilise)
        -- Anti-stuck: while walking the route, if the character hasn't moved ~4 studs in
        -- 5s (e.g. caught on a vine or zipline that needs a jump to release), jump to free
        -- it. Runs in parallel with the walk and only acts while `walking` is true.
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
            walking = false
            if antiGravConn then
                antiGravConn:Disconnect()
                antiGravConn = nil
            end
            if antiGravConn2 then
                antiGravConn2:Disconnect()
                antiGravConn2 = nil
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
                local getCheckpoints, loadErr = loadRouteFn(towerConfig)
                if not getCheckpoints then
                    Library:Notify({ Title = "Auto Play", Description = (loadErr or "Load failed") .. " for " .. towerName, Duration = 5 })
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
                -- getCheckpoints was already resolved by loadRouteFn above (before entering).
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

        -- Load the route once and reuse it for every repeat. PoM XL towers build it in-game
        -- from their numbered checkpoints; every other tower fetches its route file. (Re-
        -- running loadstring each repeat fails on executors that forward it to a server.)
        local getCheckpoints, loadErr = loadRouteFn(config)
        if not getCheckpoints then
            Library:Notify({ Title = "Auto Play", Description = loadErr, Duration = 5 })
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

    -- ===== Automake Route =====
    -- Builds a route from the tower's own parts instead of a hand-made file: every
    -- BasePart in its Obby ordered bottom-to-top by height, finishing on the WinPad.
    -- A tower is a vertical climb, so height order approximates progression well enough
    -- to autoplay most towers. Note this sorts by POSITION, not by child index --
    -- Obby:GetChildren() order is effectively arbitrary (early children are grouped
    -- section models), which is why an index-ordered version was tried and reverted.
    local function collectAutoRoute(name, descending)
        local folder = towerFolder(name)
        if not folder then return nil, name .. " isn't loaded in workspace.Towers." end
        local obby = folder:FindFirstChild("Obby")
        if not obby then return nil, name .. " has no Obby folder." end

        -- Direct children first: that's the usual layout and it keeps the emitted paths
        -- short. But some towers group their obby into section Models, so the top level
        -- holds no BaseParts at all -- fall back to the full descendant list instead of
        -- reporting the Obby as empty (which is what "CoIV's Obby has no parts" was).
        local parts = {}
        for _, v in ipairs(obby:GetChildren()) do
            if v:IsA("BasePart") then parts[#parts + 1] = v end
        end
        if #parts == 0 then
            for _, v in ipairs(obby:GetDescendants()) do
                if v:IsA("BasePart") then parts[#parts + 1] = v end
            end
        end
        if #parts == 0 then return nil, name .. "'s Obby has no parts." end
        -- Ascending = climb (lowest part first). Descending = a tower you go DOWN, so the
        -- highest part is the start and the order flips.
        if descending then
            table.sort(parts, function(a, b) return a.Position.Y > b.Position.Y end)
        else
            table.sort(parts, function(a, b) return a.Position.Y < b.Position.Y end)
        end

        local winPad = folder:FindFirstChild("WinPad", true) or folder:FindFirstChild("Winpad", true)
        return { parts = parts, winPad = winPad, obby = obby }
    end

    -- Path to a part written relative to the tower's Obby, by child index at every level.
    -- Index rather than name because obby parts share names constantly, and this has to
    -- work for parts nested inside section Models, not just direct children.
    local function pathFromObby(data, part, name)
        local segs, node = {}, part
        while node and node ~= data.obby do
            local parent = node.Parent
            if not parent then return nil end
            local idx
            for i, c in ipairs(parent:GetChildren()) do
                if c == node then idx = i break end
            end
            if not idx then return nil end
            table.insert(segs, 1, (":GetChildren()[%d]"):format(idx))
            node = parent
        end
        if node ~= data.obby then return nil end
        return ("workspace.Towers[%q].Obby%s"):format(name, table.concat(segs))
    end

    -- The same route as Lua source, in the exact format the repo's route files use, so it
    -- can be dropped into Games/EToH/<category>/ as-is.
    local function autoRouteSource(name, data)
        local out = { "return function()", "    return {" }
        for _, part in ipairs(data.parts) do
            local path = pathFromObby(data, part, name)
            if path then out[#out + 1] = "        " .. path .. "," end
        end
        if data.winPad then
            out[#out + 1] = "        " .. (data.winPad:GetFullName():gsub("^Workspace%.", "workspace."))  .. ","
        end
        out[#out + 1] = "    }"
        out[#out + 1] = "end"
        return table.concat(out, "\n")
    end

    PortalBox:AddDropdown("AutoRouteOrder", {
        Text    = "Route Order",
        Values  = { "Ascending", "Descending" },
        Default = "Ascending",
        Tooltip = "Ascending: a normal climb, lowest part first. Descending: a tower you go DOWN, highest part first.",
    })

    PortalBox:AddButton({
        Text    = "Automake Route",
        Tooltip = "Build a route for the selected tower from its own parts in the chosen order, arm it for Auto Play, and save it to a file.",
        Callback = function()
            local label = Options.PortalMatch and Options.PortalMatch.Value
            local name  = label and labelToName[label]
            if not name then
                Library:Notify({ Title = "Automake", Description = "Pick a tower first.", Duration = 3 })
                return
            end

            -- Read the order once, here, and keep it: the armed route must stay in the
            -- order it was made in even if the dropdown is changed afterwards.
            local descending = (Options.AutoRouteOrder and Options.AutoRouteOrder.Value) == "Descending"

            local data, err = collectAutoRoute(name, descending)
            if not data then
                Library:Notify({ Title = "Automake", Description = err, Duration = 5 })
                return
            end

            -- Resolve live each call so parts that streamed in since still count, and so a
            -- re-entry after a death doesn't walk stale instances.
            local function routeFn()
                local fresh = collectAutoRoute(name, descending)
                local steps = {}
                if fresh then
                    for _, p in ipairs(fresh.parts) do steps[#steps + 1] = p end
                    if fresh.winPad then steps[#steps + 1] = fresh.winPad end
                end
                return steps
            end

            -- Arm it: loadRouteFn() prefers config.routeFn over fetching a route file, so
            -- Auto Play uses this immediately with nothing published.
            local cfgName
            for n in pairs(TowerConfigs) do
                if getTpFrameName(n) == name then cfgName = n break end
            end
            if cfgName then
                TowerConfigs[cfgName].routeFn = routeFn
            else
                -- Not in the registry at all -- make it selectable so it can be played.
                cfgName = name
                TowerConfigs[name] = {
                    tpFrame    = function() return resolveTPFrame(name) end,
                    teleportTo = function() return resolveTeleportTo(name) end,
                    routeFn    = routeFn,
                }
                SuggestedTimes[name] = SuggestedTimes[name] or { min = "5", sec = "5" }
                table.insert(DropdownValues, name)
                table.sort(DropdownValues)
                pcall(function() Options.TowerSelect:SetValues(DropdownValues) end)
            end
            pcall(function() Options.TowerSelect:SetValue(cfgName) end)

            local saved = ""
            if type(writefile) == "function" then
                local ok = pcall(writefile, name .. ".lua", autoRouteSource(name, data))
                saved = ok and (" Saved to " .. name .. ".lua.") or " (couldn't write the file)"
            end
            local dir = descending and "descending" or "ascending"
            Library:Notify({
                Title       = "Automake",
                Description = ("%s: %d checkpoints %s%s, armed for Auto Play.%s"):format(
                    name, #data.parts, dir, data.winPad and " + WinPad" or " (no WinPad found)", saved),
                Duration    = 6,
            })
            logAction(("Automade a %d-checkpoint %s route for %s"):format(#data.parts, dir, name))
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

        -- Put collision back on everything noclip switched off -- the WORLD and the
        -- CHARACTER. (Missing the character half is a softlock: the world is solid again
        -- but you still fall through it.)
        --
        -- Only parts that were collidable when we touched them are ever recorded, so this
        -- can never turn on something the game ships non-collidable -- it strictly undoes
        -- our own changes. Restored in big batches so the floor is back almost instantly.
        if _G.noclipChanged then
            local restoring = _G.noclipChanged
            _G.noclipChanged = nil
            task.spawn(function()
                local n = 0
                for part in pairs(restoring) do
                    -- Noclip switched back on mid-restore: stop, or we'd be handing
                    -- collision back to parts the new pass has just switched off.
                    if _G.noclipChanged ~= nil then return end
                    if part and part.Parent then pcall(function() part.CanCollide = true end) end
                    n += 1
                    if n % 2000 == 0 then task.wait() end
                end
            end)
        end

        if not state then return end
        local conns = _G.noclipConns

        -- Every part noclip switches off is recorded here so it can be switched back on.
        -- The `part.CanCollide` test is the whole safety rule: a part is only ever recorded
        -- at the moment it was collidable, so restoring can only ever undo our own work.
        -- Not weak-keyed -- losing an entry would mean leaving that part non-collidable
        -- forever; destroyed parts are skipped on restore by the Parent check instead.
        local changed = {}
        _G.noclipChanged = changed
        local function forceUncollide(part)
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
                changed[part] = true
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
                if part.CanCollide then
                    part.CanCollide = false
                    changed[part] = true      -- it was on again; make sure we hand it back on
                end
            end)
        end
        local function hookChar(char)
            if not char then return end
            for _, p in ipairs(char:GetDescendants()) do hookPart(p) end
            conns[#conns + 1] = char.DescendantAdded:Connect(hookPart)
        end

        hookChar(Players.LocalPlayer.Character)
        conns[#conns + 1] = Players.LocalPlayer.CharacterAdded:Connect(hookChar)

        -- Uncollide the WORLD too, not just the character.
        --
        -- Character-only noclip is not enough: a collision needs both sides, so the moment
        -- the game re-asserts CanCollide on a body part (Pit of Misery does this
        -- constantly) the contact is back. And a contact does not just add velocity --
        -- the solver pushes the overlapping parts APART positionally, which is what
        -- fights the autoplay tween, throws the camera around and wedges you in geometry.
        -- Zeroing velocity cannot prevent that; the collision has to not exist. Killing it
        -- on the world side means it survives the character side being re-enabled.
        --
        -- The initial pass is spread over frames because a tower game's workspace is tens
        -- of thousands of parts and doing it in one go is a visible hitch.
        -- Shares the `changed` record above, so world and character are restored together.
        local uncollideWorld = forceUncollide
        -- Repeats, because re-asserted collision on an EXISTING world part is exactly the
        -- case a one-shot pass plus DescendantAdded would miss -- and re-asserting is the
        -- thing Pit of Misery does. Incremental (800 parts per frame) with a pause between
        -- passes, so it stays cheap on a tower-sized workspace.
        task.spawn(function()
            while _G.noclipConns == conns do
                local stack, n = { workspace }, 0
                while #stack > 0 do
                    if not (_G.noclipConns == conns) then return end   -- noclip turned off mid-sweep
                    local inst = table.remove(stack)
                    uncollideWorld(inst)
                    for _, kid in ipairs(inst:GetChildren()) do stack[#stack + 1] = kid end
                    n += 1
                    if n % 800 == 0 then task.wait() end
                end
                task.wait(2)
            end
        end)
        -- Parts that stream in later (new towers, moving platforms) get the same treatment.
        conns[#conns + 1] = workspace.DescendantAdded:Connect(uncollideWorld)

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
local godmodeKillBrickToken = nil   -- identity of the current re-sweep; stops the old one

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

    -- `original` is captured in its own local rather than read back out of
    -- `godmodeOriginal`. The hook runs for EVERY namecall in the game, so if godmode is
    -- switched off (or re-applied) while a call is in flight, reading the shared variable
    -- could find it nil mid-call and error -- and an erroring hook lets the damage call
    -- through. This copy can never be cleared out from under it.
    local original
    local blocker = function(self, ...)
        -- Identity check first: a cheap pointer compare that keeps the far more expensive
        -- getnamecallmethod() off the path of every unrelated namecall in the game. That
        -- matters when a floor is firing a damage call every few milliseconds.
        if self == damageEvent then
            -- Fail SAFE. getnamecallmethod() is the flaky part under a flood -- if it
            -- throws or returns nothing while calls are stacking up, the old
            -- `== "FireServer"` test was false and the damage went through, which is
            -- exactly godmode "sometimes" failing when instakills come thick and fast.
            -- Anything we can't positively identify as a different method is blocked;
            -- FireServer is realistically the only thing called on this remote anyway.
            local ok, method = pcall(getnamecallmethod)
            if not ok or method == nil or method == "FireServer" then
                return
            end
        end
        return original(self, ...)
    end
    -- Wrap it so the metamethod stays a C closure. A plain Lua function here adds Lua
    -- stack frames to every namecall in the game, which under a flood of damage calls can
    -- overflow the C stack -- the hook then errors and damage lands. This is the likely
    -- cause of godmode failing only when there are lots of instakills.
    if type(newcclosure) == "function" then
        local ok, wrapped = pcall(newcclosure, blocker)
        if ok and wrapped then blocker = wrapped end
    end

    original = hookmetamethod(game, "__namecall", blocker)
    godmodeOriginal = original
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
    godmodeKillBrickToken = nil   -- stop any running re-sweep before changing state
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

    -- Re-sweep on a timer as well. A one-shot pass plus DescendantAdded misses a kill
    -- brick that ALREADY existed and had its CanTouch turned back on -- towers re-enable
    -- them, and a floor full of instakills is exactly where one slipping through is fatal.
    -- Incremental so a tower-sized workspace doesn't hitch.
    local token = {}
    godmodeKillBrickToken = token
    task.spawn(function()
        while godmodeKillBrickToken == token do
            local stack, n = { workspace }, 0
            while #stack > 0 do
                if godmodeKillBrickToken ~= token then return end
                local inst = table.remove(stack)
                scanAndDisable(inst)
                for _, kid in ipairs(inst:GetChildren()) do stack[#stack + 1] = kid end
                n += 1
                if n % 800 == 0 then task.wait() end
            end
            task.wait(2)
        end
    end)
end

PlayerBox:AddToggle("GodmodeHook", {
    Text    = "Godmode: Hook Damage",
    Default = UNCSupport.Godmode,
    Tooltip = "Blocks ALL damage by hooking the game's DamageEvent so the damage call never reaches the server -- you simply never take damage. The cleanest method, but needs executor support for hookmetamethod + getnamecallmethod (greyed out if unsupported). On floors that spam instakills, turn on Kill Bricks as well: that stops the touches happening at all, instead of filtering a flood of damage calls.",
    Callback = function(state)
        if state and not UNCSupport.Godmode then
            Library.Toggles.GodmodeHook:SetValue(false)
            return
        end
        setGodmodeHook(state)
    end,
})

PlayerBox:AddToggle("GodmodeHeal", {
    Text    = "Godmode: Auto-Heal",
    Default = not UNCSupport.Godmode,
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

if not UNCSupport.Godmode then
    Library.Toggles.GodmodeHook:SetDisabled(true)
end

-- Apply the current (default or saved) states on load.
setGodmodeHook(Library.Toggles.GodmodeHook.Value)
setGodmodeHeal(Library.Toggles.GodmodeHeal.Value)
setGodmodeKillBricks(Library.Toggles.GodmodeKillBricks.Value)

Library.Toggles.UseSuggestedTime:SetValue(true)

-- Avatar loader, ported from AJ hub: type a username or UserId and wear their full R6
-- look -- body package, clothes, colours, face, accessories, headless.
--
-- Own function scope so its locals don't count against the main chunk's 200-local cap.
local function _initAvatar()
    local Players = game:GetService("Players")
    local player  = Players.LocalPlayer

    local AvatarBox = Tabs.Main:AddRightGroupbox("Avatar")

    local avatarTemplate       = nil    -- cached look-only clones (no live Humanoid)
    local avatarHead           = nil    -- cached head mesh/face for respawn re-apply
    local avatarActive         = false
    local avatarTargetHeadless = false  -- the loaded avatar is itself headless
    local statusLabel

    local function setStatus(text)
        if statusLabel then statusLabel:SetText(text) end
    end

    local function opt(name)
        local t = Library.Toggles[name]
        return t and t.Value
    end

    local function setHeadless(char, on)
        local head = char and char:FindFirstChild("Head")
        if not head then return end
        pcall(function() head.Transparency = on and 1 or 0 end)
        for _, d in ipairs(head:GetChildren()) do
            if d:IsA("Decal") then pcall(function() d.Transparency = on and 1 or 0 end) end
        end
    end

    local function isWelded(acc)
        local handle = acc:FindFirstChild("Handle")
        if not handle then return false end
        for _, w in ipairs(handle:GetChildren()) do
            if (w:IsA("Weld") or w:IsA("WeldConstraint") or w:IsA("Motor6D"))
                and w.Part0 and w.Part1 then return true end
        end
        return false
    end

    local function manualWeld(char, acc)
        local handle = acc:FindFirstChild("Handle")
        if not handle then return false end
        pcall(function() handle.Anchored = false; handle.CanCollide = false end)
        local a0 = handle:FindFirstChildWhichIsA("Attachment")
        if a0 then
            for _, d in ipairs(char:GetDescendants()) do
                if d:IsA("Attachment") and d.Name == a0.Name and d.Parent
                    and d.Parent:IsA("BasePart") and d.Parent ~= handle then
                    acc.Parent = char
                    local w = Instance.new("Weld")
                    w.Name = "PESAccWeld"
                    w.Part0, w.Part1 = d.Parent, handle
                    w.C0, w.C1 = d.CFrame, a0.CFrame
                    w.Parent = handle
                    return true
                end
            end
        end
        -- Legacy hats carry no attachment; weld them to the head.
        local head = char:FindFirstChild("Head")
        if head then
            acc.Parent = char
            local mesh = handle:FindFirstChildOfClass("SpecialMesh")
            local w = Instance.new("Weld")
            w.Name = "PESAccWeld"
            w.Part0, w.Part1 = head, handle
            w.C1 = CFrame.new(-((mesh and mesh.Offset) or Vector3.new(0, 0.5, 0)))
            w.Parent = handle
            return true
        end
        return false
    end

    local function attachAccessory(char, hum, acc)
        -- The clone still carries the source model's weld, which pins the hat at the
        -- world origin instead of on your body. Strip it before re-adding.
        local handle = acc:FindFirstChild("Handle")
        if handle then
            for _, w in ipairs(handle:GetChildren()) do
                if w:IsA("JointInstance") or w:IsA("WeldConstraint") then w:Destroy() end
            end
        end
        pcall(function() hum:AddAccessory(acc) end)
        local ok = (acc.Parent == char and isWelded(acc)) or manualWeld(char, acc)
        if ok then
            -- Kill physics on it, so wings and trailing accessories can't catch on
            -- tower parts and drag you off a ledge.
            for _, p in ipairs(acc:GetDescendants()) do
                if p:IsA("BasePart") then
                    pcall(function()
                        p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
                        p.Massless, p.Anchored = true, false
                    end)
                end
            end
        end
        return ok
    end

    local function targetIsHeadless(userId)
        local info
        local ok = pcall(function() info = Players:GetCharacterAppearanceInfoAsync(userId) end)
        if not ok or type(info) ~= "table" or type(info.assets) ~= "table" then return false end
        for _, a in ipairs(info.assets) do
            if tostring(a.name or ""):lower():find("headless") then return true end
        end
        return false
    end

    -- Keep only the appearance, so the heavy rig and its Humanoid can be freed.
    local function extractTemplate(model)
        local folder = Instance.new("Folder")
        local headInfo
        local head = model:FindFirstChild("Head")
        if head then
            local sm   = head:FindFirstChildOfClass("SpecialMesh")
            local face = head:FindFirstChild("face") or head:FindFirstChildOfClass("Decal")
            headInfo = {
                meshId  = sm and sm.MeshId or nil,
                texId   = sm and sm.TextureId or nil,
                scale   = sm and sm.Scale or nil,
                faceTex = face and face.Texture or nil,
            }
        end
        for _, item in ipairs(model:GetChildren()) do
            if item:IsA("CharacterMesh") or item:IsA("Shirt") or item:IsA("Pants")
                or item:IsA("ShirtGraphic") or item:IsA("BodyColors") or item:IsA("Accessory") then
                item:Clone().Parent = folder
            end
        end
        return folder, headInfo
    end

    local function applyLook(char, hum, folder, headInfo)
        for _, c in ipairs(char:GetChildren()) do
            if c:IsA("Accessory") or c:IsA("Shirt") or c:IsA("Pants")
                or c:IsA("ShirtGraphic") or c:IsA("BodyColors") or c:IsA("CharacterMesh") then
                c:Destroy()
            end
        end
        local myHead = char:FindFirstChild("Head")
        if myHead and headInfo then
            if headInfo.meshId then
                local mm = myHead:FindFirstChildOfClass("SpecialMesh")
                if not mm then mm = Instance.new("SpecialMesh"); mm.Parent = myHead end
                mm.MeshId, mm.TextureId = headInfo.meshId, headInfo.texId or ""
                if headInfo.scale then mm.Scale = headInfo.scale end
            end
            if headInfo.faceTex then
                local mf = myHead:FindFirstChild("face") or myHead:FindFirstChildOfClass("Decal")
                if mf then mf.Texture = headInfo.faceTex end
            end
        end
        local found, attached = 0, 0
        for _, item in ipairs(folder:GetChildren()) do
            if item:IsA("Accessory") then
                found = found + 1
                if opt("AvatarAccessories") and attachAccessory(char, hum, item:Clone()) then
                    attached = attached + 1
                end
            else
                pcall(function() item:Clone().Parent = char end)
            end
        end
        return found, attached
    end

    -- Building the model is allowed even where live ApplyDescription is blocked.
    local function buildModel(userId)
        local desc
        pcall(function() desc = Players:GetHumanoidDescriptionFromUserId(userId) end)
        local model
        if desc then
            pcall(function()
                model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
            end)
        end
        if not model then
            pcall(function() model = Players:CreateHumanoidModelFromUserId(userId) end)
        end
        return model
    end

    local function resolveUserId(input)
        input = tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if input == "" then return nil, "Enter a username or UserId" end
        if input:match("^%d+$") then return tonumber(input) end
        local uid
        local ok = pcall(function() uid = Players:GetUserIdFromNameAsync(input) end)
        if ok and uid then return uid end
        return nil, ("User '%s' not found"):format(input)
    end

    local function currentCharacter()
        local char = player.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        return char, hum
    end

    -- Forward declarations: the config hook below closes over these, and both are defined
    -- further down. Without this it would capture a nil global instead.
    local applyAvatar, wearPreset

    -- Round-trip the worn avatar through configs: saving records what you have on,
    -- loading puts it back. Registered straight into the library's config registry, so
    -- the existing serialise/deserialise path carries it with no special-casing --
    -- deserialise calls SetValue, which is what re-applies the look.
    --
    -- PESUI only. The Obsidian fallback owns its own registry and only serialises its
    -- Toggles/Options, so there it degrades to remembering nothing rather than breaking.
    local wornEntry
    local function setWorn(value)
        if wornEntry then wornEntry.Value = value end
    end
    if Library.Registry then
        wornEntry = { Type = "AvatarWorn", Value = nil }
        function wornEntry:SetValue(value)
            self.Value = value
            if type(value) ~= "string" or value == "" then return end
            local kind, rest = value:match("^(%a+):(.+)$")
            -- Deferred: a config can load before the character exists.
            task.spawn(function()
                if not player.Character then
                    player.CharacterAdded:Wait()
                    task.wait(0.5)
                end
                if kind == "user" then
                    applyAvatar(rest)
                elseif kind == "preset" then
                    wearPreset(rest)
                end
            end)
        end
        Library.Registry["AvatarWorn"] = wornEntry
    end

    applyAvatar = function(input)
        task.spawn(function()
            setStatus("Building avatar...")
            local uid, err = resolveUserId(input)
            if not uid then
                setStatus(err)
                Library:Notify({ Title = "Avatar", Description = err, Duration = 4 })
                return
            end
            local char, hum = currentCharacter()
            if not char or not hum then setStatus("No character.") return end

            local model = buildModel(uid)
            if not model then
                setStatus("Couldn't build that avatar (rate-limited?)")
                Library:Notify({ Title = "Avatar", Description = "Couldn't build that avatar -- possibly rate-limited.", Duration = 5 })
                return
            end
            local folder, headInfo = extractTemplate(model)
            pcall(function() model:Destroy() end)

            if avatarTemplate then pcall(function() avatarTemplate:Destroy() end) end
            avatarTemplate       = folder
            avatarHead           = headInfo
            avatarActive         = true
            avatarTargetHeadless = targetIsHeadless(uid)

            local found, attached = applyLook(char, hum, folder, headInfo)
            setHeadless(char, opt("AvatarHeadless") or avatarTargetHeadless)
            setWorn("user:" .. tostring(uid))
            setStatus(("Loaded UserId %d -- %d/%d accessories"):format(uid, attached, found))
            Library:Notify({
                Title       = "Avatar",
                Description = ("Loaded UserId %d (%d/%d accessories)"):format(uid, attached, found),
                Duration    = 4,
            })
        end)
    end

    local function resetAvatar()
        task.spawn(function()
            avatarActive         = false
            avatarTargetHeadless = false
            setWorn(nil)
            local char, hum = currentCharacter()
            setHeadless(char, opt("AvatarHeadless"))
            if avatarTemplate then
                pcall(function() avatarTemplate:Destroy() end)
                avatarTemplate = nil
            end
            avatarHead = nil
            if not char or not hum then setStatus("No character.") return end

            setStatus("Resetting...")
            local model = buildModel(player.UserId)
            if not model then setStatus("Reset failed (head restored)") return end
            local folder, headInfo = extractTemplate(model)
            pcall(function() model:Destroy() end)
            applyLook(char, hum, folder, headInfo)
            pcall(function() folder:Destroy() end)   -- one-shot, don't cache
            setHeadless(char, opt("AvatarHeadless"))
            setStatus("Reset to your own avatar")
        end)
    end

    ----------------------------------------------------------------------------
    -- Presets: saved HumanoidDescriptions you can wear without looking up a user.
    ----------------------------------------------------------------------------
    local HttpService = game:GetService("HttpService")
    local PRESET_DIR  = "ProjectEToHScript/outfits"

    local DESC_NUMS   = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg",
                          "Face", "Shirt", "Pants", "GraphicTShirt" }
    local DESC_COLORS = { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor",
                          "LeftLegColor", "RightLegColor" }
    local DESC_SCALES = { "HeightScale", "WidthScale", "HeadScale", "DepthScale",
                          "ProportionScale", "BodyTypeScale" }
    local DESC_ACCSTR = { "HatAccessory", "HairAccessory", "FaceAccessory", "NeckAccessory",
                          "ShouldersAccessory", "FrontAccessory", "BackAccessory", "WaistAccessory" }

    -- Shipped presets. Held as JSON rather than Lua tables because that is exactly the
    -- format the save/load path already round-trips, so there's no hand-conversion to get
    -- wrong. Order here is the order shown in the dropdown.
    local BUILTIN_ORDER = { "blockerman", "gehad", "kaan2005", "skit", "skit current" }
    local BUILTIN_PRESETS = {
        ["blockerman"] = [==[{"nums":{"RightArm":0,"Head":15093053680,"Torso":0,"GraphicTShirt":0,"Shirt":8354334846,"LeftArm":0,"Pants":89528719756784,"Face":0,"RightLeg":0,"LeftLeg":0},"scales":{"BodyTypeScale":0,"DepthScale":1,"HeadScale":1,"HeightScale":1,"WidthScale":1,"ProportionScale":0},"colors":{"HeadColor":[255,255,0],"TorsoColor":[163,162,165],"LeftArmColor":[255,255,0],"RightLegColor":[99,95,98],"RightArmColor":[255,255,0],"LeftLegColor":[99,95,98]},"accStrings":{"NeckAccessory":"13312726192","ShouldersAccessory":"","FrontAccessory":"","FaceAccessory":"","WaistAccessory":"6934144658,13937231284,18864865684","BackAccessory":"2222538922","HatAccessory":"","HairAccessory":""},"accessories":[{"AssetId":2222538922,"IsLayered":false,"AccessoryType":"Back"},{"AssetId":6934144658,"IsLayered":false,"AccessoryType":"Waist"},{"AssetId":13312726192,"IsLayered":false,"AccessoryType":"Neck"},{"AssetId":13937231284,"IsLayered":false,"AccessoryType":"Waist"},{"AssetId":18864865684,"IsLayered":false,"AccessoryType":"Waist"}]}]==],
        ["gehad"] = [==[{"nums":{"RightArm":0,"Head":74974372367270,"Torso":0,"GraphicTShirt":7541912145,"Shirt":330030567,"LeftArm":0,"Pants":330030618,"Face":0,"RightLeg":0,"LeftLeg":0},"scales":{"BodyTypeScale":0,"DepthScale":1,"HeadScale":1,"HeightScale":1,"WidthScale":1,"ProportionScale":0},"colors":{"HeadColor":[248,248,248],"TorsoColor":[17,17,17],"LeftArmColor":[27,42,53],"RightLegColor":[27,42,53],"RightArmColor":[163,162,165],"LeftLegColor":[99,95,98]},"accStrings":{"NeckAccessory":"","ShouldersAccessory":"10715291261,11970138578,18556350860","FrontAccessory":"","FaceAccessory":"","WaistAccessory":"5269089688","BackAccessory":"","HatAccessory":"7608861705","HairAccessory":""},"accessories":[{"AssetId":7608861705,"IsLayered":false,"AccessoryType":"Hat"},{"AssetId":10715291261,"IsLayered":false,"AccessoryType":"Shoulder"},{"AssetId":11970138578,"IsLayered":false,"AccessoryType":"Shoulder"},{"AssetId":18556350860,"IsLayered":false,"AccessoryType":"Shoulder"},{"AssetId":5269089688,"IsLayered":false,"AccessoryType":"Waist"}]}]==],
        ["kaan2005"] = [==[{"nums":{"RightArm":0,"Head":15093053680,"Torso":0,"GraphicTShirt":11968498114,"Shirt":0,"LeftArm":0,"Pants":1033312407,"Face":0,"RightLeg":0,"LeftLeg":0},"scales":{"BodyTypeScale":0,"DepthScale":1,"HeadScale":1,"HeightScale":1,"WidthScale":1,"ProportionScale":0},"colors":{"HeadColor":[205,205,205],"TorsoColor":[205,205,205],"LeftArmColor":[205,205,205],"RightLegColor":[205,205,205],"RightArmColor":[205,205,205],"LeftLegColor":[205,205,205]},"accStrings":{"NeckAccessory":"","ShouldersAccessory":"","FrontAccessory":"","FaceAccessory":"","WaistAccessory":"","BackAccessory":"","HatAccessory":"321346550","HairAccessory":""},"accessories":[{"AssetId":321346550,"IsLayered":false,"AccessoryType":"Hat"}]}]==],
        ["skit"] = [==[{"nums":{"RightArm":0,"Head":15093053680,"Torso":0,"GraphicTShirt":0,"Shirt":0,"LeftArm":0,"Pants":6941288880,"Face":0,"RightLeg":0,"LeftLeg":0},"scales":{"BodyTypeScale":0,"DepthScale":1,"HeadScale":1,"HeightScale":1,"WidthScale":1,"ProportionScale":0},"colors":{"HeadColor":[175,221,255],"TorsoColor":[175,221,255],"LeftArmColor":[128,187,220],"RightLegColor":[17,17,17],"RightArmColor":[0,255,0],"LeftLegColor":[255,255,0]},"accStrings":{"NeckAccessory":"","ShouldersAccessory":"","FrontAccessory":"","FaceAccessory":"","WaistAccessory":"6252477190","BackAccessory":"","HatAccessory":"14673809937","HairAccessory":""},"accessories":[{"AssetId":14673809937,"IsLayered":false,"AccessoryType":"Hat"},{"AssetId":6252477190,"IsLayered":false,"AccessoryType":"Waist"}]}]==],
        ["skit current"] = [==[{"nums":{"RightArm":0,"Head":15093053680,"Torso":48474356,"GraphicTShirt":0,"Shirt":0,"LeftArm":0,"Pants":0,"Face":0,"RightLeg":0,"LeftLeg":0},"scales":{"BodyTypeScale":0.20000000298023225,"DepthScale":0.8500000238418579,"HeadScale":1,"HeightScale":0.8999999761581421,"WidthScale":0.699999988079071,"ProportionScale":1},"colors":{"HeadColor":[249,249,249],"TorsoColor":[252,240,182],"LeftArmColor":[249,249,249],"RightLegColor":[25,25,25],"RightArmColor":[249,249,249],"LeftLegColor":[25,25,25]},"accStrings":{"NeckAccessory":"","ShouldersAccessory":"","FrontAccessory":"","FaceAccessory":"","WaistAccessory":"7853207982,13218275142","BackAccessory":"","HatAccessory":"1080949,71844152179630,1365767,76953774632480","HairAccessory":"75654134505201,111191802672513,114970157890902,124684280646469"},"accessories":[{"AssetId":1080949,"IsLayered":false,"AccessoryType":"Hat"},{"AssetId":1365767,"IsLayered":false,"AccessoryType":"Hat"},{"AssetId":7853207982,"IsLayered":false,"AccessoryType":"Waist"},{"AssetId":13218275142,"IsLayered":false,"AccessoryType":"Waist"},{"AssetId":71844152179630,"IsLayered":false,"AccessoryType":"Hat"},{"AssetId":75654134505201,"IsLayered":false,"AccessoryType":"Hair"},{"AssetId":76953774632480,"IsLayered":false,"AccessoryType":"Hat"},{"AssetId":111191802672513,"IsLayered":false,"AccessoryType":"Hair"},{"AssetId":114970157890902,"IsLayered":false,"AccessoryType":"Hair"},{"AssetId":124684280646469,"IsLayered":false,"AccessoryType":"Hair"}]}]==],
    }

    local function filesOK()
        return typeof(writefile) == "function" and typeof(readfile) == "function"
            and typeof(isfile) == "function" and typeof(listfiles) == "function"
    end

    local function ensurePresetDir()
        pcall(function()
            if typeof(makefolder) ~= "function" or typeof(isfolder) ~= "function" then return end
            if not isfolder("ProjectEToHScript") then makefolder("ProjectEToHScript") end
            if not isfolder(PRESET_DIR) then makefolder(PRESET_DIR) end
        end)
    end

    local function serializeDesc(desc)
        local t = { nums = {}, colors = {}, scales = {}, accStrings = {}, accessories = {} }
        for _, k in ipairs(DESC_NUMS)   do t.nums[k]       = desc[k] end
        for _, k in ipairs(DESC_SCALES) do t.scales[k]     = desc[k] end
        for _, k in ipairs(DESC_ACCSTR) do t.accStrings[k] = desc[k] end
        for _, k in ipairs(DESC_COLORS) do
            local c = desc[k]
            t.colors[k] = {
                math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5),
            }
        end
        local ok, list = pcall(function() return desc:GetAccessories(true) end)
        if ok and type(list) == "table" then
            for _, a in ipairs(list) do
                t.accessories[#t.accessories + 1] = {
                    AssetId       = a.AssetId,
                    AccessoryType = (typeof(a.AccessoryType) == "EnumItem") and a.AccessoryType.Name or nil,
                    IsLayered     = a.IsLayered,
                    Order         = a.Order,
                    Puffiness     = a.Puffiness,
                }
            end
        end
        return t
    end

    local function deserializeDesc(t)
        local desc = Instance.new("HumanoidDescription")
        for _, k in ipairs(DESC_NUMS) do
            if t.nums and t.nums[k] then pcall(function() desc[k] = t.nums[k] end) end
        end
        for _, k in ipairs(DESC_SCALES) do
            if t.scales and t.scales[k] then pcall(function() desc[k] = t.scales[k] end) end
        end
        for _, k in ipairs(DESC_COLORS) do
            local rgb = t.colors and t.colors[k]
            if rgb then pcall(function() desc[k] = Color3.fromRGB(rgb[1], rgb[2], rgb[3]) end) end
        end
        -- Prefer the structured accessory list (keeps layered/order/puffiness); fall back
        -- to the legacy comma-separated id strings when a preset has none.
        if t.accessories and #t.accessories > 0 then
            local list = {}
            for _, a in ipairs(t.accessories) do
                local e = {
                    AssetId = a.AssetId, Order = a.Order,
                    Puffiness = a.Puffiness, IsLayered = a.IsLayered,
                }
                if a.AccessoryType then
                    pcall(function() e.AccessoryType = Enum.AccessoryType[a.AccessoryType] end)
                end
                list[#list + 1] = e
            end
            pcall(function() desc:SetAccessories(list, true) end)
        else
            for _, k in ipairs(DESC_ACCSTR) do
                if t.accStrings and t.accStrings[k] then
                    pcall(function() desc[k] = t.accStrings[k] end)
                end
            end
        end
        return desc
    end

    local function buildFromDesc(desc)
        local model
        pcall(function()
            model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
        end)
        return model
    end

    local function userPresetNames()
        local out = {}
        if not filesOK() then return out end
        ensurePresetDir()
        pcall(function()
            for _, path in ipairs(listfiles(PRESET_DIR)) do
                local name = path:match("([^/\\]+)%.json$")
                -- A saved preset may share a built-in's name; the saved one wins on read.
                if name then out[#out + 1] = name end
            end
        end)
        table.sort(out)
        return out
    end

    local function presetNames()
        local seen, out = {}, {}
        for _, n in ipairs(BUILTIN_ORDER) do
            seen[n] = true
            out[#out + 1] = n
        end
        for _, n in ipairs(userPresetNames()) do
            if not seen[n] then out[#out + 1] = n end
        end
        return out
    end

    local function readPreset(name)
        -- Saved file takes priority, so a user can override a shipped preset.
        if filesOK() then
            local path, data = ("%s/%s.json"):format(PRESET_DIR, name), nil
            local ok = pcall(function()
                if isfile(path) then data = HttpService:JSONDecode(readfile(path)) end
            end)
            if ok and data then return data end
        end
        local raw = BUILTIN_PRESETS[name]
        if not raw then return nil end
        local ok, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
        return ok and decoded or nil
    end

    wearPreset = function(name)
        task.spawn(function()
            if not name or name == "" then
                setStatus("Pick a preset first.")
                return
            end
            local data = readPreset(name)
            if not data then setStatus(("Preset '%s' not found"):format(name)) return end

            local char, hum = currentCharacter()
            if not char or not hum then setStatus("No character.") return end

            setStatus(("Wearing '%s'..."):format(name))
            local model = buildFromDesc(deserializeDesc(data))
            if not model then
                setStatus("Couldn't build that preset (rate-limited?)")
                return
            end
            local folder, headInfo = extractTemplate(model)
            pcall(function() model:Destroy() end)

            if avatarTemplate then pcall(function() avatarTemplate:Destroy() end) end
            avatarTemplate       = folder
            avatarHead           = headInfo
            avatarActive         = true
            avatarTargetHeadless = false

            local found, attached = applyLook(char, hum, folder, headInfo)
            setHeadless(char, opt("AvatarHeadless"))
            setWorn("preset:" .. name)
            setStatus(("Wearing '%s' -- %d/%d accessories"):format(name, attached, found))
            Library:Notify({
                Title       = "Avatar",
                Description = ("Wearing preset '%s'"):format(name),
                Duration    = 4,
            })
        end)
    end

    local function saveCurrentPreset(name)
        if not name or name == "" then setStatus("Type a name to save as.") return end
        if not filesOK() then setStatus("Executor can't write files.") return end
        local desc
        local ok = pcall(function()
            desc = Players:GetHumanoidDescriptionFromUserId(player.UserId)
        end)
        if not ok or not desc then setStatus("Couldn't read your current avatar.") return end
        ensurePresetDir()
        local wrote = pcall(function()
            writefile(("%s/%s.json"):format(PRESET_DIR, name),
                HttpService:JSONEncode(serializeDesc(desc)))
        end)
        setStatus(wrote and ("Saved preset '%s'"):format(name) or "Save failed.")
        if wrote and Library.Options.AvatarPreset then
            Library.Options.AvatarPreset:SetValues(presetNames())
        end
    end

    AvatarBox:AddInput("AvatarUser", {
        Text        = "Username / ID",
        Default     = "",
        -- Finished=false so .Value tracks what's typed. With Finished=true the value only
        -- commits on Enter, so typing a name and clicking Load Avatar read an empty box.
        -- No Callback on purpose: with per-keystroke firing it would try to load an
        -- avatar for every partial name as you type.
        Finished    = false,
        Placeholder = "e.g. builderman",
        Tooltip     = "Type a username or UserId, then press Load Avatar.",
    })

    AvatarBox:AddButton({
        Text     = "Load Avatar",
        Tooltip  = "Wear this user's full R6 look.",
        Callback = function()
            local box = Library.Options.AvatarUser
            applyAvatar(box and box.Value or "")
        end,
    })
    AvatarBox:AddButton({
        Text     = "Reset Avatar",
        Tooltip  = "Restore your own appearance.",
        Callback = resetAvatar,
    })

    statusLabel = AvatarBox:AddLabel({ Text = "Idle.", DoesWrap = true })

    AvatarBox:AddToggle("AvatarAccessories", {
        Text    = "Load accessories",
        Default = true,
        Tooltip = "Accessories are welded with collision off so they can't snag on tower parts.",
    })
    AvatarBox:AddToggle("AvatarHeadless", {
        Text     = "Headless (hide head)",
        Default  = false,
        Callback = function(state)
            local char = player.Character
            setHeadless(char, state or (avatarActive and avatarTargetHeadless))
        end,
    })
    AvatarBox:AddToggle("AvatarKeepOnRespawn", {
        Text    = "Keep avatar on respawn",
        -- On by default: tower games rebuild your character on every death, so without
        -- this the look is lost constantly. Re-applies from the cached template, which is
        -- why it's instant rather than a rebuild.
        Default = true,
        Tooltip = "Re-apply your loaded avatar after deaths and respawns.",
    })

    AvatarBox:AddDivider()

    AvatarBox:AddDropdown("AvatarPreset", {
        Text      = "Preset",
        Values    = presetNames(),
        Default   = BUILTIN_ORDER[1],
        AllowNull = true,
        Tooltip   = "Saved avatars. Wearing one doesn't need a username lookup.",
    })
    AvatarBox:AddButton({
        Text     = "Wear Preset",
        Callback = function()
            local d = Library.Options.AvatarPreset
            wearPreset(d and d.Value or nil)
        end,
    })
    AvatarBox:AddInput("AvatarPresetName", {
        Text        = "Save current as",
        Default     = "",
        Finished    = false,
        Placeholder = "preset name",
        Tooltip     = "Saves YOUR current avatar under this name.",
    })
    AvatarBox:AddButton({
        Text     = "Save Current Avatar",
        Callback = function()
            local box = Library.Options.AvatarPresetName
            saveCurrentPreset(box and box.Value or "")
        end,
    })

    -- Tower games rebuild the character constantly, so re-apply from the cached template.
    player.CharacterAdded:Connect(function(char)
        local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
        if not hum then return end
        if avatarActive and avatarTemplate and opt("AvatarKeepOnRespawn") then
            task.wait(0.4)
            applyLook(char, hum, avatarTemplate, avatarHead)
            setHeadless(char, opt("AvatarHeadless") or avatarTargetHeadless)
        elseif opt("AvatarHeadless") then
            task.wait(0.3)
            setHeadless(char, true)
        end
    end)
end
_initAvatar()

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
    Tooltip = UNCSupport.queueteleport and "Re-executes this script after teleporting" or "Not supported by this executor",
    Callback = function(state)
        if not UNCSupport.queueteleport then
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
if not UNCSupport.queueteleport then
    Library.Toggles.AutoExecute:SetDisabled(true)
end
MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu bind")
    :AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
-- ===== Auto Rejoin =====
-- Gets you back in after a disconnect/kick instead of leaving the session dead. Kept in
-- its own function so its locals don't add to the main chunk's 200-local budget.
local function _initAutoRejoin()
    local TeleportService = game:GetService("TeleportService")
    local GuiService      = game:GetService("GuiService")
    local plr             = game:GetService("Players").LocalPlayer

    local enabled   = true
    local rejoining = false

    local function rejoinNow()
        -- One attempt at a time: the error prompt and the teleport-failed signal can both
        -- fire for the same disconnect, and two teleports at once just fail each other.
        if rejoining then return end
        rejoining = true
        task.delay(15, function() rejoining = false end)

        -- Private/VIP server: the same instance is off the table -- Roblox blocks client
        -- teleports into them (Error 773), TeleportToPlaceInstance does not work for
        -- reserved servers, and rejoining one needs an access code only the server side
        -- ever has. Roblox's own Reconnect fails the same way. Trying it anyway just
        -- produces a 773 dialog, so go straight to a normal server for the same place:
        -- a different server, but back in the game instead of stuck on a dead prompt.
        if game.PrivateServerId ~= "" then
            Library:Notify({
                Title       = "Auto Rejoin",
                Description = "Private server can't be rejoined by a script -- joining a public server for this place instead.",
                Duration    = 8,
            })
            pcall(function() TeleportService:Teleport(game.PlaceId, plr) end)
            return
        end

        -- Public server: rejoin the same instance, falling back to any instance of the
        -- place if that one is gone.
        local ok = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, plr)
        end)
        if not ok then
            pcall(function() TeleportService:Teleport(game.PlaceId, plr) end)
        end
    end

    MenuGroup:AddToggle("AutoRejoin", {
        Text    = "Auto Rejoin on disconnect",
        Default = true,
        Tooltip = "Automatically rejoin when you get disconnected or kicked.",
        Callback = function(value) enabled = value end,
    })

    -- Primary signal: the client replicator being removed IS the disconnect, so this
    -- can't be confused with anything else.
    pcall(function()
        local net = game:GetService("NetworkClient")
        net.ChildRemoved:Connect(function()
            if enabled then task.wait(0.5) rejoinNow() end
        end)
    end)
    -- Backup: the disconnect/kick dialog appearing. Kept because the replicator signal
    -- doesn't fire on every kick path, but it's the looser of the two -- other errors can
    -- raise a dialog too, which is what the rejoining guard above is there to contain.
    pcall(function()
        GuiService.ErrorMessageChanged:Connect(function()
            if enabled then task.wait(0.5) rejoinNow() end
        end)
    end)
    -- And retry if the teleport itself is what failed.
    pcall(function()
        TeleportService.TeleportInitFailed:Connect(function(who)
            if enabled and who == plr then task.wait(2) rejoinNow() end
        end)
    end)
end
_initAutoRejoin()

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
MenuGroup:AddButton("Sever Hop", function()
    local TeleportService = game:GetService("TeleportService")
    local player = game:GetService("Players").LocalPlayer
    Library:Notify({ Title = "Server Hop", Description = "Hopping to a new server...", Duration = 3 })
    local ok, err = pcall(function()
        TeleportService:Teleport(game.PlaceId, player)
    end)
    if not ok then
        Library:Notify({ Title = "Server Hop", Description = "Failed: " .. tostring(err), Duration = 5 })
    end
end)
MenuGroup:AddButton("Unload", function()
    _G.ProjectEToHLoaded = nil
    Library:Unload()
end)
Library.ToggleKeybind = Options.MenuKeybind

-- ===== Mobile (UI Settings) =====
-- Phones have no keyboard, so every keybind action is unreachable there. This adds movable
-- on-screen buttons for them, opt-in via a toggle. Kept in its own function so its locals
-- don't add to the main chunk's 200-local budget.
local function _initMobile()
    local MobileGroup = Tabs.UISettings:AddLeftGroupbox("Mobile")

    -- These controls are PES-UI only; Obsidian/Linoria don't have the mobile API.
    if type(Library.AddMobileButton) ~= "function" then
        MobileGroup:AddLabel("Mobile controls need the PES UI style (see UI Style above).", true)
        return
    end

    local onMobile = Library.IsMobile and true or false
    MobileGroup:AddLabel(onMobile
        and "Mobile detected -- the menu is using its compact size."
        or  "Desktop detected -- the menu is full size.", true)
    if onMobile then
        MobileGroup:AddLabel("Tap the round PES button to hide/show the menu. Drag it, the menu title bar, or any on-screen button to move them.", true)
    end

    MobileGroup:AddToggle("MobileButtons", {
        Text    = "On-screen buttons",
        Default = onMobile,
        Tooltip = "Movable buttons for the keybind actions. Drag one to reposition it, tap to use it.",
        Callback = function(value)
            Library:SetMobileButtonsVisible(value)
        end,
    })
    MobileGroup:AddSlider("MobileButtonScale", {
        Text     = "Button Size",
        Default  = 100,
        Min      = 60,
        Max      = 200,
        Rounding = 0,
        Callback = function(value)
            Library:SetMobileButtonScale(value)
        end,
    })
    MobileGroup:AddButton("Reset Button Positions", function()
        Library:ResetMobileButtons()
    end)

    -- One button per keybind action. Toggles flip through SetValue so the menu checkbox and
    -- the button never disagree; the All Jump ones call the same functions the keys do.
    local function flipToggle(name)
        local t = Library.Toggles[name]
        if t then t:SetValue(not t.Value) end
    end
    Library:AddMobileButton("Fly",         function() flipToggle("Fly") end)
    Library:AddMobileButton("Noclip",      function() flipToggle("Noclip") end)
    Library:AddMobileButton("AJ Place",    function() pcall(allJumpPlace) end)
    Library:AddMobileButton("AJ Remove",   function() pcall(allJumpRemove) end)
    Library:AddMobileButton("AJ Teleport", function() pcall(allJumpTeleport) end)

    if onMobile then Library:SetMobileButtonsVisible(true) end
end
_initMobile()

local CreditsGroup = Tabs.UISettings:AddRightGroupbox("Credits")
CreditsGroup:AddLabel('<font color="rgb(90,200,255)">[cslp1]</font>  Owner', true)

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
