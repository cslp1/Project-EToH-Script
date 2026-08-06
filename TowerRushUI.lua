-- ============================================================
--  Project EToH Script -- Tower Rush Auto-Completer
--  AJ hub custom UI (self-contained, no Obsidian / no external library)
--  Open menu: RightControl (rebindable in the Settings tab)
--
--  Pick a rush; the Times tab lists every tower in it with its own
--  mm:ss input. Set each tower's time, press Start Rush, and it walks
--  each route, touches that tower's WinPad to lock the win, then
--  advances to the next tower's TeleportTo.
-- ============================================================

local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VIM          = game:GetService("VirtualInputManager")
local player       = Players.LocalPlayer

-- hot-reload: unload a previous copy, then take over
if getgenv().TowerRushUI and getgenv().TowerRushUI.unload then
    pcall(getgenv().TowerRushUI.unload)
end
local TRU = { conns = {}, running = true }
getgenv().TowerRushUI = TRU
local function track(c) table.insert(TRU.conns, c); return c end

-- ============================================================
--  TOWER RUSH DATA + LOGIC  (unchanged behaviour)
-- ============================================================
local baseRepo    = "https://raw.githubusercontent.com/cslp1/Project-EToH-Script/refs/heads/main/Games/EToH/"
local registryUrl = baseRepo .. "TowerRegistry.lua"

-- Cache-buster so GitHub raw can't serve a stale route/registry.
local function fetch(url)
    local src
    local ok = pcall(function() src = game:HttpGet(url .. "?cb=" .. tostring(os.time())) end)
    if ok and type(src) == "string" and #src > 0 then return src end
    return nil
end

-- forward decl so early logic can post a toast once the UI exists
local notify

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
        warn("[TowerRush UI] Failed to load registry.")
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

-- ============================================================
--  AJ HUB CUSTOM UI FRAMEWORK
-- ============================================================
local FOLDER = "TowerRushUI"
local function filesOK() return typeof(writefile)=="function" and typeof(readfile)=="function" and typeof(isfile)=="function" end
local function ensureFolder() pcall(function() if typeof(makefolder)=="function" and typeof(isfolder)=="function" and not isfolder(FOLDER) then makefolder(FOLDER) end end) end
local function saveFile(n, s) if not filesOK() then return end ensureFolder(); pcall(function() writefile(FOLDER.."/"..n, s) end) end
local function loadFile(n) if not filesOK() then return nil end local d; pcall(function() if isfile(FOLDER.."/"..n) then d=readfile(FOLDER.."/"..n) end end); return d end

local function waitForPlayerGui()
    while not player:FindFirstChild("PlayerGui") do task.wait() end
    return player:WaitForChild("PlayerGui")
end

local function mkTheme(name, ac, acd, gt, gl, row, inp)
    return {name=name, Accent=ac, AccentDeep=acd, GlassTop=gt, GlassLow=gl, Row=row, Input=inp,
        Text=Color3.fromRGB(236,246,255), Sub=Color3.fromRGB(184,206,230), Off=Color3.fromRGB(62,82,106),
        Danger=Color3.fromRGB(240,104,112), White=Color3.fromRGB(255,255,255)}
end
local Themes = {
    mkTheme("Ice",      Color3.fromRGB(102,208,255), Color3.fromRGB(48,150,224), Color3.fromRGB(52,88,132), Color3.fromRGB(20,34,56),  Color3.fromRGB(70,108,150), Color3.fromRGB(28,46,70)),
    mkTheme("Aqua",     Color3.fromRGB(90,240,214),  Color3.fromRGB(34,176,158), Color3.fromRGB(40,96,96),  Color3.fromRGB(16,42,44),  Color3.fromRGB(56,116,116), Color3.fromRGB(24,52,54)),
    mkTheme("Midnight", Color3.fromRGB(132,150,255), Color3.fromRGB(84,96,214),  Color3.fromRGB(52,58,112), Color3.fromRGB(22,24,54),  Color3.fromRGB(72,80,140),  Color3.fromRGB(30,32,64)),
    mkTheme("Rose",     Color3.fromRGB(255,140,192), Color3.fromRGB(224,84,146), Color3.fromRGB(112,54,86), Color3.fromRGB(50,24,40),  Color3.fromRGB(140,78,108), Color3.fromRGB(58,30,46)),
    mkTheme("Emerald",  Color3.fromRGB(110,236,150), Color3.fromRGB(46,182,110), Color3.fromRGB(44,100,70), Color3.fromRGB(18,44,32),  Color3.fromRGB(64,120,90),  Color3.fromRGB(26,52,40)),
    mkTheme("Amethyst", Color3.fromRGB(190,142,255), Color3.fromRGB(140,90,222), Color3.fromRGB(80,56,120), Color3.fromRGB(36,24,56),  Color3.fromRGB(104,80,146), Color3.fromRGB(42,30,62)),
}
local ThemeByName = {}
for _, t in ipairs(Themes) do ThemeByName[t.name] = t end
local Theme = Themes[1]
local currentThemeName = "Ice"

-- forward refs
local selectTab, activeTab, setThemeByName, closeDropdown
local activePopup = nil

-- clean any stale gui, then build
pcall(function()
    local pg = player:FindFirstChild("PlayerGui")
    if pg then local g = pg:FindFirstChild("TowerRushGUI"); if g then g:Destroy() end end
end)

local gui = Instance.new("ScreenGui")
gui.Name="TowerRushGUI"; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.Parent=waitForPlayerGui()

TRU.unload = function()
    TRU.running = false
    running = false
    for _, c in ipairs(TRU.conns) do pcall(function() c:Disconnect() end) end
    local pg = player:FindFirstChild("PlayerGui")
    if pg then local g = pg:FindFirstChild("TowerRushGUI"); if g then g:Destroy() end end
end

-- theme registry
local themedRegistry = {}
local function tSet(obj, prop, key) obj[prop]=Theme[key]; table.insert(themedRegistry, {obj=obj, prop=prop, key=key}); return obj end
local function tFn(fn) fn(); table.insert(themedRegistry, {fn=fn}) end
local function tGrad(g) g.Color=ColorSequence.new(Theme.GlassTop, Theme.GlassLow); table.insert(themedRegistry, {grad=true, obj=g}); return g end
local function setTheme(t)
    Theme=t; currentThemeName=t.name
    for _, e in ipairs(themedRegistry) do
        pcall(function()
            if e.fn then e.fn()
            elseif e.grad then e.obj.Color=ColorSequence.new(Theme.GlassTop, Theme.GlassLow)
            else e.obj[e.prop]=Theme[e.key] end
        end)
    end
    if activeTab then selectTab(activeTab) end
end
setThemeByName = function(n) local t=ThemeByName[n]; if t then setTheme(t); saveFile("theme.txt", n) end end

-- ui helpers
local function tween(o,t,p,s,d) return TweenService:Create(o, TweenInfo.new(t, s or Enum.EasingStyle.Quad, d or Enum.EasingDirection.Out), p) end
local function corner(o,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 10); c.Parent=o; return c end
local function stroke(o,key,thick,trans) local s=Instance.new("UIStroke"); s.Thickness=thick or 1; s.Transparency=trans or 0; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=o; tSet(s,"Color",key or "Accent"); return s end
local function glass(o) local g=Instance.new("UIGradient"); g.Rotation=90; g.Parent=o; tGrad(g); return g end

local MENU_W, MENU_H = 560, 460
local RAIL_W = 140

local menu = Instance.new("Frame")
menu.Name="Menu"; menu.Size=UDim2.fromOffset(MENU_W,MENU_H); menu.Position=UDim2.fromScale(0.5,0.5)
menu.AnchorPoint=Vector2.new(0.5,0.5); menu.BackgroundColor3=Theme.White; menu.BackgroundTransparency=0.12
menu.BorderSizePixel=0; menu.Visible=false; menu.Parent=gui
corner(menu,16); stroke(menu,"Accent",1.4,0.35); glass(menu)

-- title bar
local titleBar = Instance.new("Frame")
titleBar.Size=UDim2.new(1,0,0,46); titleBar.BackgroundTransparency=0.05; titleBar.BorderSizePixel=0; titleBar.Parent=menu
tSet(titleBar,"BackgroundColor3","AccentDeep"); corner(titleBar,16)
local tcov = Instance.new("Frame"); tcov.Size=UDim2.new(1,0,0,18); tcov.Position=UDim2.new(0,0,1,-18)
tcov.BackgroundTransparency=0.05; tcov.BorderSizePixel=0; tcov.Parent=titleBar; tSet(tcov,"BackgroundColor3","AccentDeep")
local tline = Instance.new("Frame"); tline.Size=UDim2.new(1,0,0,2); tline.Position=UDim2.new(0,0,0,46)
tline.BackgroundTransparency=0.3; tline.BorderSizePixel=0; tline.Parent=menu; tSet(tline,"BackgroundColor3","Accent")
local titleLabel = Instance.new("TextLabel")
titleLabel.Size=UDim2.new(1,-60,1,0); titleLabel.Position=UDim2.new(0,16,0,0); titleLabel.BackgroundTransparency=1
titleLabel.Text="Tower Rush Auto"; titleLabel.TextColor3=Theme.White; titleLabel.Font=Enum.Font.GothamBold
titleLabel.TextSize=20; titleLabel.TextXAlignment=Enum.TextXAlignment.Left; titleLabel.Parent=titleBar
local closeBtn = Instance.new("TextButton")
closeBtn.Size=UDim2.fromOffset(30,30); closeBtn.Position=UDim2.new(1,-40,0.5,-15); closeBtn.AutoButtonColor=false
closeBtn.Text="X"; closeBtn.TextColor3=Theme.White; closeBtn.Font=Enum.Font.GothamBold; closeBtn.TextSize=15; closeBtn.Parent=titleBar
tSet(closeBtn,"BackgroundColor3","Danger"); corner(closeBtn,9)

-- tab rail + content
local rail = Instance.new("Frame")
rail.Size=UDim2.new(0,RAIL_W,1,-48); rail.Position=UDim2.new(0,0,0,48); rail.BackgroundTransparency=0.55; rail.BorderSizePixel=0; rail.Parent=menu
tSet(rail,"BackgroundColor3","GlassLow")
local railList = Instance.new("UIListLayout"); railList.Padding=UDim.new(0,4); railList.Parent=rail
local railPad = Instance.new("UIPadding"); railPad.PaddingTop=UDim.new(0,8); railPad.PaddingLeft=UDim.new(0,8); railPad.PaddingRight=UDim.new(0,8); railPad.Parent=rail
local content = Instance.new("Frame")
content.Size=UDim2.new(1,-RAIL_W,1,-48); content.Position=UDim2.new(0,RAIL_W,0,48); content.BackgroundTransparency=1; content.BorderSizePixel=0; content.Parent=menu

local pages, tabButtons = {}, {}
local order = 0
local function nextOrder() order += 1; return order end

selectTab = function(name)
    if closeDropdown then closeDropdown() end
    activeTab = name
    for n, info in pairs(tabButtons) do
        local a = (n == name)
        pages[n].Visible = a
        tween(info.btn, 0.15, {BackgroundTransparency = a and 0.25 or 1, TextColor3 = a and Theme.Text or Theme.Sub}):Play()
        tween(info.strip, 0.15, {BackgroundTransparency = a and 0 or 1}):Play()
    end
end

local function addTab(name)
    local btn = Instance.new("TextButton")
    btn.Size=UDim2.new(1,0,0,36); btn.AutoButtonColor=false; btn.BackgroundTransparency=1
    btn.Text=name; btn.Font=Enum.Font.GothamBold; btn.TextSize=14; btn.TextColor3=Theme.Sub
    btn.TextXAlignment=Enum.TextXAlignment.Left; btn.LayoutOrder=nextOrder(); btn.Parent=rail
    tSet(btn,"BackgroundColor3","Row"); corner(btn,8)
    local tp = Instance.new("UIPadding"); tp.PaddingLeft=UDim.new(0,14); tp.Parent=btn
    local strip = Instance.new("Frame"); strip.Size=UDim2.new(0,3,0.6,0); strip.Position=UDim2.new(0,0,0.2,0)
    strip.BorderSizePixel=0; strip.BackgroundTransparency=1; strip.Parent=btn; tSet(strip,"BackgroundColor3","Accent"); corner(strip,2)
    btn.MouseEnter:Connect(function() if activeTab~=name then tween(btn,0.12,{BackgroundTransparency=0.6}):Play() end end)
    btn.MouseLeave:Connect(function() if activeTab~=name then tween(btn,0.12,{BackgroundTransparency=1}):Play() end end)
    btn.MouseButton1Click:Connect(function() selectTab(name) end)

    local page = Instance.new("ScrollingFrame")
    page.Size=UDim2.new(1,-16,1,-12); page.Position=UDim2.new(0,8,0,6); page.BackgroundTransparency=1; page.BorderSizePixel=0
    page.ScrollBarThickness=5; page.ScrollBarImageTransparency=0.3; page.CanvasSize=UDim2.new(0,0,0,0); page.Visible=false; page.Parent=content
    tSet(page,"ScrollBarImageColor3","Accent")
    local pp=Instance.new("UIPadding"); pp.PaddingTop=UDim.new(0,4); pp.PaddingBottom=UDim.new(0,8); pp.PaddingRight=UDim.new(0,6); pp.Parent=page
    local pl=Instance.new("UIListLayout"); pl.Padding=UDim.new(0,10); pl.SortOrder=Enum.SortOrder.LayoutOrder; pl.Parent=page
    pl:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize=UDim2.new(0,0,0, pl.AbsoluteContentSize.Y + 14)
    end)
    pages[name]=page; tabButtons[name]={btn=btn, strip=strip}
    return page
end

-- row builders
local function newRow(page, hgt)
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,-4,0,hgt or 44); row.BackgroundTransparency=0.55; row.BorderSizePixel=0
    row.LayoutOrder=nextOrder(); row.Parent=page; tSet(row,"BackgroundColor3","Row"); corner(row,10)
    local s=stroke(row,"Accent",1,0.85)
    row.MouseEnter:Connect(function() tween(row,0.15,{BackgroundTransparency=0.35}):Play(); tween(s,0.15,{Transparency=0.5}):Play() end)
    row.MouseLeave:Connect(function() tween(row,0.15,{BackgroundTransparency=0.55}):Play(); tween(s,0.15,{Transparency=0.85}):Play() end)
    return row
end
local function newLabel(parent, text, size)
    local l=Instance.new("TextLabel"); l.Size=size; l.Position=UDim2.new(0,14,0,0); l.BackgroundTransparency=1
    l.Text=text; l.Font=Enum.Font.Gotham; l.TextSize=14; l.TextXAlignment=Enum.TextXAlignment.Left; l.TextWrapped=true; l.Parent=parent
    tSet(l,"TextColor3","Text"); return l
end
local function addSection(page, text)
    local h=Instance.new("TextLabel"); h.Size=UDim2.new(1,-4,0,18); h.BackgroundTransparency=1
    h.Text=string.upper(text); h.Font=Enum.Font.GothamBold; h.TextSize=12; h.TextXAlignment=Enum.TextXAlignment.Left
    h.LayoutOrder=nextOrder(); h.Parent=page; tSet(h,"TextColor3","Accent")
    local p=Instance.new("UIPadding"); p.PaddingLeft=UDim.new(0,4); p.Parent=h
end
local function addNote(page, text)
    local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-4,0,32); l.BackgroundTransparency=1
    l.Text=text; l.Font=Enum.Font.Gotham; l.TextSize=12; l.TextWrapped=true
    l.TextXAlignment=Enum.TextXAlignment.Left; l.LayoutOrder=nextOrder(); l.Parent=page; tSet(l,"TextColor3","Sub")
    local p=Instance.new("UIPadding"); p.PaddingLeft=UDim.new(0,4); p.Parent=l
    return l
end

local function createButton(page, label, cb)
    local row=newRow(page,42)
    local b=Instance.new("TextButton"); b.Size=UDim2.new(1,-20,1,-12); b.Position=UDim2.new(0,10,0,6); b.AutoButtonColor=false
    b.Text=label; b.Font=Enum.Font.GothamBold; b.TextSize=14; b.BackgroundTransparency=0.1; b.Parent=row
    tSet(b,"BackgroundColor3","AccentDeep"); tSet(b,"TextColor3","White"); corner(b,8)
    b.MouseEnter:Connect(function() tween(b,0.15,{BackgroundColor3=Theme.Accent}):Play() end)
    b.MouseLeave:Connect(function() tween(b,0.15,{BackgroundColor3=Theme.AccentDeep}):Play() end)
    b.MouseButton1Click:Connect(cb)
    return b
end

-- settable status label
local function createLabel(page, text)
    local row=newRow(page,40)
    local l=newLabel(row, text, UDim2.new(1,-20,1,0))
    return { set=function(t) l.Text=t end }
end

-- mm:ss string input row (label settable, hideable)
local function createTimeRow(page)
    local row=newRow(page,42); row.Visible=false
    local lbl=newLabel(row,"-",UDim2.new(0.55,-14,1,0))
    local tb=Instance.new("TextBox"); tb.Size=UDim2.new(0.45,-14,0,28); tb.Position=UDim2.new(0.55,0,0.5,-14)
    tb.BackgroundTransparency=0.15; tb.Text=""; tb.PlaceholderText="mm:ss"; tb.Font=Enum.Font.Gotham; tb.TextSize=13
    tb.ClearTextOnFocus=false; tb.Parent=row; tSet(tb,"BackgroundColor3","Input"); tSet(tb,"TextColor3","Text")
    tSet(tb,"PlaceholderColor3","Sub"); corner(tb,8); local s=stroke(tb,"Accent",1,0.6)
    local onChangedFn
    tb.Focused:Connect(function() tween(s,0.15,{Transparency=0}):Play() end)
    tb.FocusLost:Connect(function()
        tween(s,0.15,{Transparency=0.6}):Play()
        if onChangedFn then onChangedFn(tb.Text) end
    end)
    return {
        setLabel   = function(t) lbl.Text=t end,
        setValue   = function(v) tb.Text=v end,
        getValue   = function() return tb.Text end,
        setVisible = function(v) row.Visible=v end,
        onChanged  = function(fn) onChangedFn=fn end,
    }
end

-- dropdown (label + value button + popup list parented to gui)
local function createDropdown(page, label, getValues, default, cb)
    local row=newRow(page,44); newLabel(row,label,UDim2.new(0.36,-14,1,0))
    local btn=Instance.new("TextButton"); btn.Size=UDim2.new(0.64,-14,0,30); btn.Position=UDim2.new(0.36,0,0.5,-15)
    btn.AutoButtonColor=false; btn.Font=Enum.Font.Gotham; btn.TextSize=13; btn.TextXAlignment=Enum.TextXAlignment.Left
    btn.Text=tostring(default or "-"); btn.Parent=row; tSet(btn,"BackgroundColor3","Input"); tSet(btn,"TextColor3","Text")
    corner(btn,8); stroke(btn,"Accent",1,0.6)
    local bp=Instance.new("UIPadding"); bp.PaddingLeft=UDim.new(0,10); bp.Parent=btn
    local arrow=Instance.new("TextLabel"); arrow.Size=UDim2.fromOffset(20,30); arrow.Position=UDim2.new(1,-22,0,0)
    arrow.BackgroundTransparency=1; arrow.Text="v"; arrow.Font=Enum.Font.GothamBold; arrow.TextSize=12; arrow.Parent=btn
    tSet(arrow,"TextColor3","Sub")

    local current=default

    local function build()
        local values=getValues()
        local shownCount=math.min(#values, 7)
        local popup=Instance.new("Frame")
        popup.Size=UDim2.fromOffset(btn.AbsoluteSize.X, shownCount*28 + 8)
        popup.Position=UDim2.fromOffset(btn.AbsolutePosition.X, btn.AbsolutePosition.Y + btn.AbsoluteSize.Y + 4)
        popup.BackgroundColor3=Theme.Input; popup.BackgroundTransparency=0.03; popup.BorderSizePixel=0
        popup.ZIndex=60; popup.Parent=gui
        corner(popup,8); stroke(popup,"Accent",1,0.25)
        local sf=Instance.new("ScrollingFrame"); sf.Size=UDim2.new(1,-8,1,-8); sf.Position=UDim2.new(0,4,0,4)
        sf.BackgroundTransparency=1; sf.BorderSizePixel=0; sf.ScrollBarThickness=4; sf.ZIndex=60
        sf.CanvasSize=UDim2.new(0,0,0,#values*28); sf.ScrollBarImageColor3=Theme.Accent; sf.Parent=popup
        local ll=Instance.new("UIListLayout"); ll.Padding=UDim.new(0,2); ll.Parent=sf
        for _, v in ipairs(values) do
            local it=Instance.new("TextButton"); it.Size=UDim2.new(1,0,0,26); it.AutoButtonColor=false
            it.BackgroundColor3=Theme.Accent; it.BackgroundTransparency=1; it.Font=Enum.Font.Gotham; it.TextSize=13
            it.Text=tostring(v); it.TextXAlignment=Enum.TextXAlignment.Left; it.ZIndex=61; it.Parent=sf
            it.TextColor3=Theme.Text; corner(it,6)
            local ip=Instance.new("UIPadding"); ip.PaddingLeft=UDim.new(0,8); ip.Parent=it
            it.MouseEnter:Connect(function() tween(it,0.12,{BackgroundTransparency=0.7}):Play() end)
            it.MouseLeave:Connect(function() tween(it,0.12,{BackgroundTransparency=1}):Play() end)
            it.MouseButton1Click:Connect(function()
                current=v; btn.Text=tostring(v)
                if closeDropdown then closeDropdown() end
                cb(v)
            end)
        end
        return popup
    end

    closeDropdown = closeDropdown -- keep upvalue

    btn.MouseButton1Click:Connect(function()
        if activePopup then
            local wasMine = activePopup:GetAttribute("owner") == tostring(btn)
            if closeDropdown then closeDropdown() end
            if wasMine then return end
        end
        activePopup = build()
        activePopup:SetAttribute("owner", tostring(btn))
    end)

    return {
        get=function() return current end,
        set=function(v) current=v; btn.Text=tostring(v); cb(v) end,
    }
end

closeDropdown = function()
    if activePopup then activePopup:Destroy(); activePopup=nil end
end

-- keybind row (for the menu open key)
local function createKeybindRow(page, name, getKC, setKC)
    local row=newRow(page,44); newLabel(row,name,UDim2.new(0.5,-14,1,0))
    local vBox=Instance.new("TextButton"); vBox.Size=UDim2.new(0.5,-14,0,30); vBox.Position=UDim2.new(0.5,0,0.5,-15)
    vBox.BackgroundTransparency=0.15; vBox.Font=Enum.Font.Gotham; vBox.TextSize=13; vBox.AutoButtonColor=false
    vBox.Text=getKC().Name; vBox.Parent=row; tSet(vBox,"BackgroundColor3","Input"); tSet(vBox,"TextColor3","Text")
    corner(vBox,8); local vs=stroke(vBox,"Accent",1,0.6)
    vBox.MouseButton1Click:Connect(function()
        vBox.Text="[ press key ]"; tween(vs,0.15,{Transparency=0}):Play(); tween(vBox,0.15,{BackgroundColor3=Theme.AccentDeep}):Play()
        local conn; conn=UIS.InputBegan:Connect(function(input)
            if input.UserInputType==Enum.UserInputType.Keyboard then
                setKC(input.KeyCode); vBox.Text=input.KeyCode.Name
                tween(vs,0.15,{Transparency=0.6}):Play(); tween(vBox,0.15,{BackgroundColor3=Theme.Input}):Play(); conn:Disconnect()
            end
        end)
    end)
end

-- ===== toast notifications =====
local activeToasts = 0
notify = function(title, desc, dur)
    dur = dur or 4
    local idx = activeToasts; activeToasts += 1
    local holder=Instance.new("Frame")
    holder.Size=UDim2.fromOffset(288, 56); holder.AnchorPoint=Vector2.new(1,1)
    holder.Position=UDim2.new(1,-16,1,-16 - idx*64)
    holder.BackgroundColor3=Theme.White; holder.BackgroundTransparency=1; holder.BorderSizePixel=0; holder.Parent=gui
    corner(holder,12); glass(holder); local hs=stroke(holder,"Accent",1,1)
    local t=Instance.new("TextLabel"); t.Size=UDim2.new(1,-24,0,20); t.Position=UDim2.new(0,12,0,8)
    t.BackgroundTransparency=1; t.Text=title or "Tower Rush"; t.Font=Enum.Font.GothamBold; t.TextSize=14
    t.TextXAlignment=Enum.TextXAlignment.Left; t.TextTransparency=1; t.Parent=holder; tSet(t,"TextColor3","Text")
    local d=Instance.new("TextLabel"); d.Size=UDim2.new(1,-24,0,20); d.Position=UDim2.new(0,12,0,28)
    d.BackgroundTransparency=1; d.Text=desc or ""; d.Font=Enum.Font.Gotham; d.TextSize=12
    d.TextXAlignment=Enum.TextXAlignment.Left; d.TextTransparency=1; d.TextWrapped=true; d.Parent=holder; tSet(d,"TextColor3","Sub")
    tween(holder,0.3,{BackgroundTransparency=0.12}):Play(); tween(hs,0.3,{Transparency=0.4}):Play()
    tween(t,0.3,{TextTransparency=0}):Play(); tween(d,0.3,{TextTransparency=0.15}):Play()
    task.delay(dur, function()
        tween(holder,0.4,{BackgroundTransparency=1}):Play(); tween(hs,0.4,{Transparency=1}):Play()
        tween(t,0.4,{TextTransparency=1}):Play(); tween(d,0.4,{TextTransparency=1}):Play()
        task.wait(0.45); holder:Destroy(); activeToasts = math.max(0, activeToasts-1)
    end)
end

-- ============================================================
--  BUILD TABS + WIDGETS
-- ============================================================
local menuKey = Enum.KeyCode.RightControl

local pRush     = addTab("Rush")
local pTimes    = addTab("Times")
local pSettings = addTab("Settings")

-- shared UI state
local currentList    = {}   -- current rush's tower names in order
local perTowerValues = {}   -- "rush|tower" -> "mm:ss"
local MAX_TOWERS     = 30
local timeRows       = {}
local rushDropdown, status

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

local function rebuildTimes(rushName)
    currentList = getRushTowerList(rushName) or {}
    for i = 1, MAX_TOWERS do
        local h    = timeRows[i]
        local name = currentList[i]
        if name then
            local key       = rushName .. "|" .. name
            local suggested = (TowerInfo[name] and TowerInfo[name].sec) or 360
            local existing  = perTowerValues[key]
            local shown     = (existing and existing ~= "") and existing or fmtTime(suggested)
            perTowerValues[key] = shown
            h.setLabel(("%d. %s"):format(i, name))
            h.setValue(shown)
            h.setVisible(true)
        else
            h.setVisible(false)
        end
    end
    if status then status.set(("Loaded %s -- %d towers."):format(rushName, #currentList)) end
end

-- ---- Rush tab ----
addSection(pRush, "Select Rush")
rushDropdown = createDropdown(pRush, "Rush", function() return RushNames end, RushNames[1], function(value)
    rebuildTimes(value)
end)
status = createLabel(pRush, "Pick a rush to load its towers.")
addNote(pRush, "Set each tower's time in the Times tab, then press Start Rush.")

-- ---- Times tab ----
addSection(pTimes, "Per-Tower Times (mm:ss)")
for i = 1, MAX_TOWERS do
    local h = createTimeRow(pTimes)
    timeRows[i] = h
    h.onChanged(function(text)
        local name = currentList[i]
        if not name then return end
        local rush = rushDropdown.get()
        perTowerValues[rush .. "|" .. name] = text
    end)
end
createButton(pTimes, "Reset Times to Suggested", function()
    local rushName = rushDropdown.get()
    for _, name in ipairs(currentList) do
        perTowerValues[rushName .. "|" .. name] = nil
    end
    rebuildTimes(rushName)
    notify("Tower Rush", "Times reset to suggested.", 3)
end)

-- ============================================================
--  RUNNER
-- ============================================================
local function runRush(rushName)
    if running then return end
    local rush = RushInfo[rushName]
    if not rush then
        notify("Tower Rush", "Unknown rush.", 4)
        return
    end
    local list = currentList
    if #list == 0 then list = getRushTowerList(rushName) or {} end
    if #list == 0 then
        notify("Tower Rush", "Couldn't load tower list.", 5)
        return
    end

    running = true
    if status then status.set("Running " .. rushName .. "...") end

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
        if status then status.set("Idle. Loaded " .. rushName .. ".") end
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

        notify("Tower Rush", ("(%d/%d) %s -- %s"):format(idx, #list, towerName, fmtTime(budget)), 3)
        local steps, err = resolveSteps(towerName, category)
        if steps then
            walkSteps(steps, budget)
        else
            warn(("[TowerRush] %s: %s"):format(towerName, tostring(err)))
        end
        if not running then break end

        if touchWinPad(towerName) then
            notify("Tower Rush", towerName .. " complete!", 2)
        else
            warn(("[TowerRush] %s: no WinPad found"):format(towerName))
        end
        task.wait(0.5)
    end

    cleanup()
    notify("Tower Rush", "Rush finished: " .. rushName, 5)
end

-- ---- Rush tab controls ----
createButton(pRush, "Start Rush", function()
    if running then
        notify("Tower Rush", "Already running.", 3)
        return
    end
    local rushName = rushDropdown.get()
    task.spawn(function() runRush(rushName) end)
end)
createButton(pRush, "Stop Rush", function()
    running = false
    notify("Tower Rush", "Stopping...", 3)
end)

-- ---- Settings tab ----
addSection(pSettings, "Appearance")
createDropdown(pSettings, "Theme", function()
    local names = {}
    for _, t in ipairs(Themes) do names[#names+1] = t.name end
    return names
end, currentThemeName, function(v) setThemeByName(v) end)
addSection(pSettings, "Keybind")
createKeybindRow(pSettings, "Open Menu", function() return menuKey end, function(k) menuKey = k end)
addSection(pSettings, "Script")
createButton(pSettings, "Unload", function()
    if TRU.unload then TRU.unload() end
end)
addNote(pSettings, "Project EToH Script -- Tower Rush. Owner: cslp1.")

-- ============================================================
--  OPEN / CLOSE / DRAG / MENU KEY
-- ============================================================
local menuOpen = false
local function openMenu()
    if menuOpen then return end
    menuOpen=true; menu.Visible=true
    menu.Size=UDim2.fromOffset(MENU_W*0.92, MENU_H*0.92); menu.BackgroundTransparency=1
    tween(menu,0.3,{Size=UDim2.fromOffset(MENU_W,MENU_H)},Enum.EasingStyle.Back):Play()
    tween(menu,0.24,{BackgroundTransparency=0.12}):Play()
end
local function closeMenu()
    if not menuOpen then return end
    menuOpen=false
    if closeDropdown then closeDropdown() end
    tween(menu,0.2,{Size=UDim2.fromOffset(MENU_W*0.92, MENU_H*0.92)}):Play()
    local t=tween(menu,0.2,{BackgroundTransparency=1}); t.Completed:Connect(function() if not menuOpen then menu.Visible=false end end); t:Play()
end
closeBtn.MouseButton1Click:Connect(closeMenu)
closeBtn.MouseEnter:Connect(function() tween(closeBtn,0.15,{BackgroundColor3=Color3.fromRGB(255,130,138)}):Play() end)
closeBtn.MouseLeave:Connect(function() tween(closeBtn,0.15,{BackgroundColor3=Theme.Danger}):Play() end)
do
    local dragging, dragStart, startPos
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true; dragStart=input.Position; startPos=menu.Position
            if closeDropdown then closeDropdown() end
            input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end)
        end
    end)
    track(UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
            local d=input.Position-dragStart
            menu.Position=UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
        end
    end))
end
track(UIS.InputBegan:Connect(function(input)
    if UIS:GetFocusedTextBox() then return end
    if input.KeyCode==menuKey then if menuOpen then closeMenu() else openMenu() end end
end))

-- close an open dropdown when clicking outside it
track(UIS.InputBegan:Connect(function(input)
    if not activePopup then return end
    if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
    local p, s = activePopup.AbsolutePosition, activePopup.AbsoluteSize
    local pos = input.Position
    if pos.X < p.X or pos.X > p.X+s.X or pos.Y < p.Y or pos.Y > p.Y+s.Y then
        task.defer(function() if closeDropdown then closeDropdown() end end)
    end
end))

-- ============================================================
--  STARTUP
-- ============================================================
do
    local savedTheme = loadFile("theme.txt")
    if savedTheme and ThemeByName[savedTheme] then setTheme(ThemeByName[savedTheme]) end
end
if RushNames[1] then rebuildTimes(RushNames[1]) end
selectTab("Rush")

notify("Tower Rush", "Loaded. Open with " .. menuKey.Name .. ".", 5)
