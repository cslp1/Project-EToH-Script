--[[
    Project EToH Script -- Standalone Tower Rush Auto-Completer
    ------------------------------------------------------------
    Reuses your repo's TowerRegistry + per-tower route files. For each tower in a
    rush list it: walks the real route (Auto Play style), TOUCHES that tower's WinPad
    to register the win, then touches the NEXT tower's TeleportTo to advance -- exactly
    the ToAST->WinPad->ToA TeleportTo flow you described. This is the piece that was
    getting skipped (e.g. ToKY) in the old loop.

    Load with:
        loadstring(game:HttpGet("https://raw.githubusercontent.com/cslp1/Project-EToH-Script/refs/heads/main/TowerRushAuto.lua"))()
    then call:  _G.RunTowerRush("R1TR")   -- or any rush acronym in your registry
    stop with:  _G.StopTowerRush()
]]

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VIM          = game:GetService("VirtualInputManager")
local player       = Players.LocalPlayer

local baseRepo    = "https://raw.githubusercontent.com/cslp1/Project-EToH-Script/refs/heads/main/Games/EToH/"
local registryUrl = baseRepo .. "TowerRegistry.lua"

-- Cache-buster so GitHub's raw cache can't serve a stale route/registry (the bug that
-- cost us earlier). Remove ?cb once your files are stable if you want caching back.
local function fetch(url)
    local src
    local ok = pcall(function() src = game:HttpGet(url .. "?cb=" .. tostring(os.time())) end)
    if ok and type(src) == "string" and #src > 0 then return src end
    return nil
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
        warn("[TowerRush] failed to load registry")
        return
    end
end

-- name -> { category, suggestedSec } for every tower (used to size each tower's slice)
local TowerInfo = {}
for _, t in ipairs(Registry.Towers or {}) do
    TowerInfo[t.name] = {
        category = t.category,
        sec = (tonumber(t.suggestedTime.min) or 0) * 60 + (tonumber(t.suggestedTime.sec) or 0),
    }
end
-- rush acronym -> { category, suggestedSec }
local RushInfo = {}
for _, tr in ipairs(Registry.TowerRush or {}) do
    RushInfo[tr.name] = {
        category = tr.category,
        sec = (tonumber(tr.suggestedTime.min) or 0) * 60 + (tonumber(tr.suggestedTime.sec) or 0),
    }
end

-- ===== Geometry helpers (same math as your main script) =====
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

-- ===== Folder / part resolution =====
local function towerFolder(name)
    local towers = workspace:FindFirstChild("Towers")
    return towers and towers:FindFirstChild(name)
end

-- Strip a ":SE" style suffix for the folder name, but KEEP "(L)/(C)/(M)" -- those are
-- part of the real folder name (learned the hard way with ToUB(L)).
local function folderName(name)
    local colon = name:find(":")
    return colon and name:sub(1, colon - 1) or name
end

local function resolveTPFrame(name)
    local f = towerFolder(folderName(name))
    if not f then return nil end
    local tp    = f:FindFirstChild("Teleporter")
    local inner = tp and tp:FindFirstChild("Teleporter")
    local exact = inner and inner:FindFirstChild("TPFRAME")
    if exact and exact:IsA("BasePart") then return exact end
    local any = f:FindFirstChild("TPFRAME", true)
    return (any and any:IsA("BasePart")) and any or nil
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

-- ===== State =====
local running = false
_G.StopTowerRush = function() running = false end

-- Return true (and stop) if the player's character is gone/dead mid-run.
local function characterOk()
    local char = player.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    return char and hum and hrp and hum.Health > 0
end

-- Move onto a part and wait until we've either touched it or are within range.
local function moveToPart(part, timeout)
    local char = player.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local touched = false
    local conn = part.Touched:Connect(function(hit)
        if hit:IsDescendantOf(char) then touched = true end
    end)
    local deadline = os.clock() + (timeout or 6)
    while running and not touched and os.clock() < deadline do
        char = player.Character
        hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then break end
        if (hrp.Position - part.Position).Magnitude < 8 then touched = true break end
        hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0)) * (hrp.CFrame - hrp.CFrame.Position)
        task.wait(0.1)
    end
    conn:Disconnect()
    return touched
end

-- Fetch + resolve a tower's checkpoint parts into ordered {type,target,destPos,dist} steps.
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

    local char = player.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local prevPos = hrp and hrp.Position or Vector3.zero
    local steps = {}
    for _, step in ipairs(checkpoints) do
        if step == "jump" then
            table.insert(steps, { type = "jump" })
        else
            local target = typeof(step) == "Instance" and step
                or (type(step) == "table" and step.target)
            if target and target:IsA("BasePart") then
                local destPos = getTopPos(target)
                table.insert(steps, {
                    type = "tween", target = target, destPos = destPos,
                    dist = (destPos - prevPos).Magnitude,
                })
                prevPos = destPos
            end
        end
    end
    return steps
end

-- Walk one tower's steps within `budget` seconds, distributing time by remaining distance.
local function walkSteps(steps, budget)
    local remaining = {}
    local cum = 0
    for i = #steps, 1, -1 do
        if steps[i].type ~= "jump" then cum = cum + (steps[i].dist or 0) end
        remaining[i] = cum
    end
    local deadline = os.clock() + math.max(budget, 1)

    for i, step in ipairs(steps) do
        if not running then return false end
        local char = player.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end -- win/respawn ended the walk
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
                if not (player.Character and player.Character:FindFirstChild("HumanoidRootPart")) then
                    tween:Cancel()
                    return false
                end
                task.wait()
            end
            tween:Cancel()
        end
    end
    return true
end

-- Touch a tower's WinPad to register the completion. This is the step that was missing.
local function touchWinPad(towerName)
    local wp = resolveWinPad(towerName)
    if not wp then return false end
    local char = player.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    -- Fire a real touch: teleport on, and if firetouchinterest exists, force it too.
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

-- ===== Main =====
_G.RunTowerRush = function(rushName)
    if running then warn("[TowerRush] already running") return end
    local rush = RushInfo[rushName]
    if not rush then warn("[TowerRush] unknown rush: " .. tostring(rushName)) return end

    -- Pull the rush's tower list from its own route file (same file your main script reads).
    local listSrc = fetch(baseRepo .. rush.category .. "/" .. rushName .. ".lua")
    if not listSrc then warn("[TowerRush] couldn't fetch rush list") return end
    local listFn = loadstring(listSrc)
    if not listFn then warn("[TowerRush] rush list parse failed") return end
    local okList, getList = pcall(listFn)
    if not okList or type(getList) ~= "function" then warn("[TowerRush] rush list load failed") return end
    local okList2, towerList = pcall(getList)
    if not okList2 or type(towerList) ~= "table" then warn("[TowerRush] rush list bad") return end

    running = true

    -- Enable a light noclip so tweened movement doesn't snag on geometry.
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
    end

    -- Move to the rush teleporter first.
    local rushTp = rushTeleporter(rushName)
    if rushTp then moveToPart(rushTp, 6) end
    task.wait(0.5)

    -- Total budget = rush's suggested time; slice per tower by each tower's suggested time.
    local totalSuggested = 0
    for _, tn in ipairs(towerList) do
        totalSuggested = totalSuggested + (TowerInfo[tn] and TowerInfo[tn].sec or 360)
    end
    local totalBudget = rush.sec > 0 and rush.sec or totalSuggested

    for idx, towerName in ipairs(towerList) do
        if not running then break end
        local info = TowerInfo[towerName]
        local category = info and info.category or rush.category
        local towerBudget = totalBudget * ((info and info.sec or 360) / math.max(totalSuggested, 1))

        -- For towers after the first, touch THIS tower's TeleportTo to enter it.
        if idx > 1 then
            local tpTo = resolveTeleportTo(towerName)
            if tpTo then
                moveToPart(tpTo, 6)
                -- nudge forward so the teleport fires
                local posBefore = player.Character and player.Character.HumanoidRootPart.Position
                VIM:SendKeyEvent(true, Enum.KeyCode.W, false, game)
                local t0 = os.clock()
                repeat task.wait(0.1) until (not running)
                    or (player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                        and posBefore and (player.Character.HumanoidRootPart.Position - posBefore).Magnitude > 0.1)
                    or os.clock() - t0 > 3
                VIM:SendKeyEvent(false, Enum.KeyCode.W, false, game)
            end
        end
        if not running then break end

        -- Resolve + walk the real route.
        local steps, err = resolveSteps(towerName, category)
        if not steps then
            warn(("[TowerRush] %s: %s -- skipping"):format(towerName, tostring(err)))
        else
            print(("[TowerRush] (%d/%d) %s -- %d steps, %.0fs budget")
                :format(idx, #towerList, towerName, #steps, towerBudget))
            walkSteps(steps, towerBudget)
        end
        if not running then break end

        -- ALWAYS touch this tower's WinPad before advancing -- the fix for ToKY-style skips.
        -- Even if the walk finished a hair short, this registers the win so the next
        -- tower's TeleportTo has a completed tower behind it.
        if touchWinPad(towerName) then
            print(("[TowerRush] %s complete (WinPad touched)"):format(towerName))
        else
            warn(("[TowerRush] %s: no WinPad found -- relying on route finish"):format(towerName))
        end
        task.wait(0.5)
    end

    cleanup()
    print("[TowerRush] done: " .. rushName)
end

print("[TowerRush] loaded. Run with _G.RunTowerRush(\"R1TR\"), stop with _G.StopTowerRush().")
