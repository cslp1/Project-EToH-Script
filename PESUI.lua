--[[
    PES UI -- the Project EToH Script Plus interface library.

    Written to be a drop-in replacement for Obsidian: it exposes the same API surface
    SC Script.lua already calls, so no feature code changes when switching to it.
    The point of owning this is that nothing outside this repo can break the menu --
    the previous setup pulled a third party's library from `main` on every single run.

    Exposes: Library (CreateWindow/Notify/Unload/SetDPIScale/SetNotifySide/Toggles/
    Options/KeybindFrame/ToggleKeybind/ShowCustomCursor/CornerRadius/Unloaded),
    Window (AddTab/SetCornerRadius), Tab (AddLeftGroupbox/AddRightGroupbox), and
    Groupbox (AddToggle/AddButton/AddLabel/AddDropdown/AddSlider/AddInput/AddDivider/
    AddColorPicker), plus Library.SaveManager and Library.ThemeManager.
]]

local Players           = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local RunService         = game:GetService("RunService")
local HttpService        = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

--============================================================================
-- Theme
--============================================================================

local Theme = {
    Background   = Color3.fromRGB(18, 18, 22),
    Sidebar      = Color3.fromRGB(24, 24, 30),
    Groupbox     = Color3.fromRGB(28, 28, 35),
    Control      = Color3.fromRGB(38, 38, 47),
    ControlHover = Color3.fromRGB(48, 48, 59),
    Outline      = Color3.fromRGB(52, 52, 64),
    Accent       = Color3.fromRGB(126, 106, 255),
    AccentDim    = Color3.fromRGB(86, 72, 178),
    Text         = Color3.fromRGB(235, 235, 240),
    SubText      = Color3.fromRGB(150, 150, 165),
    Disabled     = Color3.fromRGB(95, 95, 108),
    Good         = Color3.fromRGB(95, 210, 130),
    Bad          = Color3.fromRGB(235, 95, 95),
}

local FONT      = Enum.Font.Gotham
local FONT_BOLD = Enum.Font.GothamBold
local TEXT_SIZE = 13

--============================================================================
-- Library root
--============================================================================

local Library = {
    Toggles           = {},
    Options           = {},
    Theme             = Theme,
    Unloaded          = false,
    CornerRadius      = 6,
    ShowCustomCursor  = false,
    ToggleKeybind     = nil,
    NotifySide        = "Right",
    Connections       = {},
    Corners           = {},
    _accentObjects    = {},
}

-- Every control registers here so configs can round-trip generically.
local Registry = {}

local function track(conn)
    table.insert(Library.Connections, conn)
    return conn
end

--============================================================================
-- Instance helpers
--============================================================================

local function create(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        if k ~= "Parent" then inst[k] = v end
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    if props and props.Parent then inst.Parent = props.Parent end
    return inst
end

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or Library.CornerRadius)
    c.Parent = parent
    table.insert(Library.Corners, c)
    return c
end

local function stroke(parent, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or Theme.Outline
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function padding(parent, all)
    local p = Instance.new("UIPadding")
    p.PaddingTop = UDim.new(0, all)
    p.PaddingBottom = UDim.new(0, all)
    p.PaddingLeft = UDim.new(0, all)
    p.PaddingRight = UDim.new(0, all)
    p.Parent = parent
    return p
end

local function listLayout(parent, pad, sortOrder)
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, pad or 6)
    l.SortOrder = sortOrder or Enum.SortOrder.LayoutOrder
    l.Parent = parent
    return l
end

local function tween(inst, time, props)
    TweenService:Create(inst, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

-- Accent-coloured objects get retinted when the theme accent changes.
local function accent(inst, prop)
    table.insert(Library._accentObjects, { inst = inst, prop = prop or "BackgroundColor3" })
    return inst
end

--============================================================================
-- Root ScreenGui
--============================================================================

local function newScreenGui()
    local gui = Instance.new("ScreenGui")
    gui.Name = "PESUI_" .. tostring(math.random(100000, 999999))
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.IgnoreGuiInset = true

    -- Exploit environments vary; try the safest parents in order.
    local ok = pcall(function()
        if typeof(gethui) == "function" then
            gui.Parent = gethui()
        elseif game:GetService("RunService"):IsStudio() then
            gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
        else
            gui.Parent = game:GetService("CoreGui")
        end
    end)
    if not ok or not gui.Parent then
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    if typeof(syn) == "table" and typeof(syn.protect_gui) == "function" then
        pcall(syn.protect_gui, gui)
    end
    return gui
end

local ScreenGui = newScreenGui()
Library.ScreenGui = ScreenGui

local UIScale = Instance.new("UIScale")
UIScale.Scale = 1
UIScale.Parent = ScreenGui

--============================================================================
-- Dragging
--============================================================================

local function makeDraggable(frame, handle)
    local dragging, dragStart, startPos
    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging  = true
            dragStart = input.Position
            startPos  = frame.Position
        end
    end))
    track(handle.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end))
end

--============================================================================
-- Notifications
--============================================================================

local NotifyHolder = create("Frame", {
    Name                   = "Notifications",
    Parent                 = ScreenGui,
    BackgroundTransparency = 1,
    Position               = UDim2.new(1, -20, 0, 20),
    AnchorPoint            = Vector2.new(1, 0),
    Size                   = UDim2.new(0, 300, 1, -40),
})
local NotifyLayout = listLayout(NotifyHolder, 8)
NotifyLayout.VerticalAlignment = Enum.VerticalAlignment.Top

function Library:SetNotifySide(side)
    Library.NotifySide = side
    if side == "Left" then
        NotifyHolder.Position    = UDim2.new(0, 20, 0, 20)
        NotifyHolder.AnchorPoint = Vector2.new(0, 0)
    else
        NotifyHolder.Position    = UDim2.new(1, -20, 0, 20)
        NotifyHolder.AnchorPoint = Vector2.new(1, 0)
    end
end

function Library:Notify(info)
    -- Accepts Notify("text") or Notify({Title=, Description=, Duration=}).
    if type(info) == "string" then info = { Description = info } end
    info = info or {}
    local title    = info.Title or "Project EToH Script"
    local body     = info.Description or info.Text or ""
    local duration = info.Duration or 4

    -- NOTE: nothing in this card may size itself relative to the card's height. The card
    -- is AutomaticSize.Y, so a child with Size.Y.Scale = 1 creates a feedback loop and the
    -- card grows without bound (which also pushes the text out of sight). Fixed heights and
    -- AutomaticSize.Y only.
    local card = create("Frame", {
        Parent                 = NotifyHolder,
        BackgroundColor3       = Theme.Groupbox,
        Size                   = UDim2.new(1, 0, 0, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
    })
    corner(card)
    stroke(card)
    padding(card, 10)
    local col = listLayout(card, 3)
    col.SortOrder = Enum.SortOrder.LayoutOrder

    -- Accent lives in the title colour rather than a full-height bar, for the reason above.
    local titleLabel = create("TextLabel", {
        Parent                 = card,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 16),
        Font                   = FONT_BOLD,
        Text                   = title,
        TextColor3             = Theme.Accent,
        TextSize               = TEXT_SIZE,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextTruncate           = Enum.TextTruncate.AtEnd,
        LayoutOrder            = 1,
    })
    accent(titleLabel, "TextColor3")

    if body ~= "" then
        create("TextLabel", {
            Parent                 = card,
            BackgroundTransparency = 1,
            Size                   = UDim2.new(1, 0, 0, 0),
            AutomaticSize          = Enum.AutomaticSize.Y,
            Font                   = FONT,
            Text                   = body,
            TextColor3             = Theme.Text,
            TextSize               = TEXT_SIZE - 1,
            TextXAlignment         = Enum.TextXAlignment.Left,
            TextYAlignment         = Enum.TextYAlignment.Top,
            TextWrapped            = true,
            LayoutOrder            = 2,
        })
    end

    tween(card, 0.18, { BackgroundTransparency = 0 })
    task.delay(duration, function()
        if card and card.Parent then
            tween(card, 0.18, { BackgroundTransparency = 1 })
            task.wait(0.2)
            card:Destroy()
        end
    end)
    return card
end

--============================================================================
-- Control base: registration, disabling, change signalling
--============================================================================

local function newControl(kind, idx, default, container)
    local control = {
        Type       = kind,
        Value      = default,
        Disabled   = false,
        Callbacks  = {},
        Container  = container,
    }

    function control:OnChanged(fn)
        table.insert(self.Callbacks, fn)
        return self
    end

    function control:Fire()
        for _, fn in ipairs(self.Callbacks) do
            task.spawn(function()
                local ok, err = pcall(fn, self.Value)
                if not ok then warn("[PES UI] callback error on '" .. tostring(idx) .. "': " .. tostring(err)) end
            end)
        end
    end

    function control:SetDisabled(state)
        self.Disabled = state and true or false
        if self.Container then
            self.Container.Visible = true
            for _, d in ipairs(self.Container:GetDescendants()) do
                if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                    d.TextColor3 = self.Disabled and Theme.Disabled or Theme.Text
                end
            end
            self.Container.Active = not self.Disabled
        end
        return self
    end

    if idx then
        Registry[idx] = control
    end
    return control
end

--============================================================================
-- Groupbox controls
--============================================================================

local Groupbox = {}
Groupbox.__index = Groupbox

-- Only one dropdown list may be open at a time; opening another closes the previous one.
local closeActiveDropdown = nil

local function rowFrame(parent, height)
    return create("Frame", {
        Parent                 = parent,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, height or 22),
    })
end

--------------------------------------------------------------------- Toggle
function Groupbox:AddToggle(idx, info)
    info = info or {}
    local row = rowFrame(self.Content, 22)

    local box = create("Frame", {
        Parent           = row,
        BackgroundColor3 = Theme.Control,
        Size             = UDim2.new(0, 36, 0, 18),
        Position         = UDim2.new(1, -36, 0.5, -9),
    })
    corner(box, 9)
    stroke(box)

    local knob = create("Frame", {
        Parent           = box,
        BackgroundColor3 = Theme.SubText,
        Size             = UDim2.new(0, 12, 0, 12),
        Position         = UDim2.new(0, 3, 0.5, -6),
    })
    corner(knob, 6)

    local label = create("TextLabel", {
        Parent                 = row,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, -44, 1, 0),
        Font                   = FONT,
        Text                   = info.Text or tostring(idx),
        TextColor3             = Theme.Text,
        TextSize               = TEXT_SIZE,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextTruncate           = Enum.TextTruncate.AtEnd,
    })

    local button = create("TextButton", {
        Parent                 = row,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 1, 0),
        Text                   = "",
    })

    local control = newControl("Toggle", idx, info.Default and true or false, row)
    control.Text = info.Text or tostring(idx)

    function control:Render()
        if self.Value then
            tween(box, 0.12, { BackgroundColor3 = Theme.Accent })
            tween(knob, 0.12, { Position = UDim2.new(1, -15, 0.5, -6), BackgroundColor3 = Theme.Text })
        else
            tween(box, 0.12, { BackgroundColor3 = Theme.Control })
            tween(knob, 0.12, { Position = UDim2.new(0, 3, 0.5, -6), BackgroundColor3 = Theme.SubText })
        end
    end

    function control:SetValue(value)
        if self.Disabled then return self end
        self.Value = value and true or false
        self:Render()
        self:Fire()
        return self
    end

    track(button.MouseButton1Click:Connect(function()
        if control.Disabled then return end
        control:SetValue(not control.Value)
    end))

    control:Render()
    if info.Tooltip then
        -- Tooltips render as hover text on the row.
        track(button.MouseEnter:Connect(function() label.TextColor3 = Theme.Accent end))
        track(button.MouseLeave:Connect(function()
            label.TextColor3 = control.Disabled and Theme.Disabled or Theme.Text
        end))
    end

    if info.Callback then control:OnChanged(info.Callback) end
    Library.Toggles[idx] = control

    -- AddKeyPicker / AddColorPicker chain off a toggle in the existing script.
    control.Row = row
    function control:AddKeyPicker(kIdx, kInfo)
        return Groupbox.AttachKeyPicker(row, kIdx, kInfo)
    end
    function control:AddColorPicker(cIdx, cInfo)
        return Groupbox.AttachColorPicker(row, cIdx, cInfo)
    end

    self:Resize()
    return control
end

--------------------------------------------------------------------- Button
function Groupbox:AddButton(a, b)
    -- Accepts AddButton("Text", fn) and AddButton({Text=, Callback=, Tooltip=}).
    local info = type(a) == "table" and a or { Text = a, Callback = b }
    local row = rowFrame(self.Content, 26)

    local button = create("TextButton", {
        Parent           = row,
        BackgroundColor3 = Theme.Control,
        Size             = UDim2.new(1, 0, 1, 0),
        Font             = FONT,
        Text             = info.Text or "Button",
        TextColor3       = Theme.Text,
        TextSize         = TEXT_SIZE,
        AutoButtonColor  = false,
    })
    corner(button)
    stroke(button)

    track(button.MouseEnter:Connect(function()
        tween(button, 0.12, { BackgroundColor3 = Theme.ControlHover })
    end))
    track(button.MouseLeave:Connect(function()
        tween(button, 0.12, { BackgroundColor3 = Theme.Control })
    end))
    track(button.MouseButton1Click:Connect(function()
        if info.Callback then
            task.spawn(function()
                local ok, err = pcall(info.Callback)
                if not ok then warn("[PES UI] button error: " .. tostring(err)) end
            end)
        end
    end))

    self:Resize()
    return { Instance = button, SetText = function(_, t) button.Text = t end }
end

--------------------------------------------------------------------- Label
function Groupbox:AddLabel(a, doesWrap)
    -- Accepts AddLabel("text"), AddLabel("text", true), AddLabel({Text=, DoesWrap=}).
    local info = type(a) == "table" and a or { Text = a, DoesWrap = doesWrap }
    local wrap = info.DoesWrap and true or false

    local row = create("Frame", {
        Parent                 = self.Content,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, wrap and 0 or 18),
        AutomaticSize          = wrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
    })

    local label = create("TextLabel", {
        Parent                 = row,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, wrap and 0 or 1, 0),
        AutomaticSize          = wrap and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
        Font                   = FONT,
        Text                   = info.Text or "",
        TextColor3             = Theme.SubText,
        TextSize               = TEXT_SIZE,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextWrapped            = wrap,
        RichText               = true,
    })

    local obj = { Instance = label, Row = row }
    function obj:SetText(text)
        label.Text = text
        return self
    end
    function obj:AddKeyPicker(kIdx, kInfo)
        return Groupbox.AttachKeyPicker(row, kIdx, kInfo)
    end
    function obj:AddColorPicker(cIdx, cInfo)
        return Groupbox.AttachColorPicker(row, cIdx, cInfo)
    end

    self:Resize()
    return obj
end

--------------------------------------------------------------------- Divider
function Groupbox:AddDivider()
    local row = rowFrame(self.Content, 8)
    create("Frame", {
        Parent           = row,
        BackgroundColor3 = Theme.Outline,
        Size             = UDim2.new(1, 0, 0, 1),
        Position         = UDim2.new(0, 0, 0.5, 0),
        BorderSizePixel  = 0,
    })
    self:Resize()
    return row
end

--------------------------------------------------------------------- Input
function Groupbox:AddInput(idx, info)
    info = info or {}
    local row = rowFrame(self.Content, info.Text and 40 or 24)

    if info.Text then
        create("TextLabel", {
            Parent                 = row,
            BackgroundTransparency = 1,
            Size                   = UDim2.new(1, 0, 0, 16),
            Font                   = FONT,
            Text                   = info.Text,
            TextColor3             = Theme.SubText,
            TextSize               = TEXT_SIZE,
            TextXAlignment         = Enum.TextXAlignment.Left,
        })
    end

    local box = create("TextBox", {
        Parent             = row,
        BackgroundColor3   = Theme.Control,
        Size               = UDim2.new(1, 0, 0, 22),
        Position           = UDim2.new(0, 0, 1, -22),
        Font               = FONT,
        Text               = info.Default or "",
        PlaceholderText    = info.Placeholder or "",
        TextColor3         = Theme.Text,
        PlaceholderColor3  = Theme.Disabled,
        TextSize           = TEXT_SIZE,
        ClearTextOnFocus   = false,
    })
    corner(box)
    stroke(box)
    padding(box, 6)

    local control = newControl("Input", idx, info.Default or "", row)

    function control:SetValue(value)
        self.Value = tostring(value or "")
        if box.Text ~= self.Value then box.Text = self.Value end
        self:Fire()
        return self
    end

    -- Finished=false means fire per keystroke (needed for live search boxes);
    -- otherwise only commit on Enter, matching Obsidian's behaviour.
    if info.Finished then
        track(box.FocusLost:Connect(function(enter)
            if enter then control:SetValue(box.Text) end
        end))
    else
        track(box:GetPropertyChangedSignal("Text"):Connect(function()
            if box.Text ~= control.Value then control:SetValue(box.Text) end
        end))
    end

    if info.Callback then control:OnChanged(info.Callback) end
    Library.Options[idx] = control
    self:Resize()
    return control
end

--------------------------------------------------------------------- Slider
function Groupbox:AddSlider(idx, info)
    info = info or {}
    local min      = info.Min or 0
    local max      = info.Max or 100
    local rounding = info.Rounding or 0

    local row = rowFrame(self.Content, 38)

    local label = create("TextLabel", {
        Parent                 = row,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 16),
        Font                   = FONT,
        Text                   = info.Text or tostring(idx),
        TextColor3             = Theme.SubText,
        TextSize               = TEXT_SIZE,
        TextXAlignment         = Enum.TextXAlignment.Left,
    })

    local valueLabel = create("TextLabel", {
        Parent                 = row,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(0, 80, 0, 16),
        Position               = UDim2.new(1, -80, 0, 0),
        Font                   = FONT,
        Text                   = "",
        TextColor3             = Theme.Text,
        TextSize               = TEXT_SIZE,
        TextXAlignment         = Enum.TextXAlignment.Right,
    })

    local track_ = create("Frame", {
        Parent           = row,
        BackgroundColor3 = Theme.Control,
        Size             = UDim2.new(1, 0, 0, 8),
        Position         = UDim2.new(0, 0, 1, -12),
    })
    corner(track_, 4)
    stroke(track_)

    local fill = accent(create("Frame", {
        Parent           = track_,
        BackgroundColor3 = Theme.Accent,
        Size             = UDim2.new(0, 0, 1, 0),
        BorderSizePixel  = 0,
    }))
    corner(fill, 4)

    local control = newControl("Slider", idx, info.Default or min, row)

    local function round(v)
        local mult = 10 ^ rounding
        return math.floor(v * mult + 0.5) / mult
    end

    function control:Render()
        local alpha = (max - min) == 0 and 0 or (self.Value - min) / (max - min)
        fill.Size = UDim2.new(math.clamp(alpha, 0, 1), 0, 1, 0)
        valueLabel.Text = ("%s/%s"):format(tostring(self.Value), tostring(max))
    end

    function control:SetValue(value)
        if self.Disabled then return self end
        self.Value = math.clamp(round(tonumber(value) or min), min, max)
        self:Render()
        self:Fire()
        return self
    end

    local dragging = false
    local function updateFromInput(input)
        local rel   = input.Position.X - track_.AbsolutePosition.X
        local alpha = math.clamp(rel / math.max(track_.AbsoluteSize.X, 1), 0, 1)
        control:SetValue(min + (max - min) * alpha)
    end

    track(track_.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            if control.Disabled then return end
            dragging = true
            updateFromInput(input)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(input)
        end
    end))

    control:Render()
    if info.Callback then control:OnChanged(info.Callback) end
    Library.Options[idx] = control
    self:Resize()
    return control
end

--------------------------------------------------------------------- Dropdown
function Groupbox:AddDropdown(idx, info)
    info = info or {}
    local multi = info.Multi and true or false

    local row = create("Frame", {
        Parent                 = self.Content,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, info.Text and 40 or 24),
        ClipsDescendants       = false,
    })

    if info.Text then
        create("TextLabel", {
            Parent                 = row,
            BackgroundTransparency = 1,
            Size                   = UDim2.new(1, 0, 0, 16),
            Font                   = FONT,
            Text                   = info.Text,
            TextColor3             = Theme.SubText,
            TextSize               = TEXT_SIZE,
            TextXAlignment         = Enum.TextXAlignment.Left,
        })
    end

    local button = create("TextButton", {
        Parent           = row,
        BackgroundColor3 = Theme.Control,
        Size             = UDim2.new(1, 0, 0, 22),
        Position         = UDim2.new(0, 0, 1, -22),
        Font             = FONT,
        Text             = "---",
        TextColor3       = Theme.Text,
        TextSize         = TEXT_SIZE,
        AutoButtonColor  = false,
        TextTruncate     = Enum.TextTruncate.AtEnd,
    })
    corner(button)
    stroke(button)
    padding(button, 6)

    -- Full-screen invisible blocker that sits under the list but over everything else.
    --
    -- Without it, a click aimed at an option could be taken by whatever GuiObject happens
    -- to sit beneath the floating list -- a toggle, or another dropdown's button, which
    -- would then close this list and open its own. The blocker swallows every click that
    -- isn't on the list itself, so nothing underneath can ever receive it. It's also what
    -- dismisses the list, replacing the old mouse-coordinate test.
    local blocker = create("TextButton", {
        Parent                 = ScreenGui,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 1, 0),
        Text                   = "",
        Visible                = false,
        Active                 = true,
        AutoButtonColor        = false,
        ZIndex                 = 99,
    })

    -- The option list floats above everything so it isn't clipped by the column.
    local listHolder = create("Frame", {
        Parent           = ScreenGui,
        BackgroundColor3 = Theme.Groupbox,
        Size             = UDim2.new(0, 100, 0, 0),
        Visible          = false,
        ZIndex           = 100,
        ClipsDescendants = true,
    })
    corner(listHolder)
    stroke(listHolder)

    local scroller = create("ScrollingFrame", {
        Parent                 = listHolder,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 1, 0),
        ScrollBarThickness     = 3,
        ScrollBarImageColor3   = Theme.Accent,
        CanvasSize             = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize    = Enum.AutomaticSize.Y,
        ZIndex                 = 51,
    })
    listLayout(scroller, 2)
    padding(scroller, 4)

    local control = newControl("Dropdown", idx, multi and {} or info.Default, row)
    control.Values    = info.Values or {}
    control.AllowNull = info.AllowNull and true or false
    control.Multi     = multi

    local function displayText()
        if multi then
            local picked = {}
            for value, on in pairs(control.Value or {}) do
                if on then table.insert(picked, tostring(value)) end
            end
            table.sort(picked)
            return #picked > 0 and table.concat(picked, ", ") or "---"
        end
        return control.Value ~= nil and tostring(control.Value) or "---"
    end

    local LIST_ROW_H, LIST_MAX_ROWS = 22, 8
    local function listHeight()
        local count = math.min(#control.Values, LIST_MAX_ROWS)
        return math.max(count * LIST_ROW_H + 8, 26)
    end

    local function closeList()
        listHolder.Visible = false
        blocker.Visible    = false
        if closeActiveDropdown == closeList then closeActiveDropdown = nil end
    end
    track(blocker.MouseButton1Click:Connect(closeList))

    local rebuild
    function control:SetValue(value)
        if multi then
            self.Value = value or {}
        else
            self.Value = value
        end
        button.Text = displayText()
        self:Fire()
        if listHolder.Visible then rebuild() end
        return self
    end

    function control:SetValues(values)
        self.Values = values or {}
        -- Drop a selection that no longer exists, so stale text can't linger.
        if not multi and self.Value ~= nil then
            local stillThere = false
            for _, v in ipairs(self.Values) do
                if v == self.Value then stillThere = true break end
            end
            if not stillThere then
                self.Value  = nil
                button.Text = displayText()
            end
        end
        if listHolder.Visible then rebuild() end
        return self
    end

    rebuild = function()
        for _, child in ipairs(scroller:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        for _, value in ipairs(control.Values) do
            local selected = multi and (control.Value or {})[value] or (control.Value == value)
            local opt = create("TextButton", {
                Parent           = scroller,
                BackgroundColor3 = selected and Theme.AccentDim or Theme.Control,
                Size             = UDim2.new(1, 0, 0, 20),
                Font             = FONT,
                Text             = tostring(value),
                TextColor3       = Theme.Text,
                TextSize         = TEXT_SIZE,
                AutoButtonColor  = false,
                ZIndex           = 52,
                TextTruncate     = Enum.TextTruncate.AtEnd,
            })
            corner(opt, 4)
            track(opt.MouseButton1Click:Connect(function()
                if multi then
                    local map = control.Value or {}
                    map[value] = not map[value] or nil
                    control:SetValue(map)
                else
                    if control.AllowNull and control.Value == value then
                        control:SetValue(nil)
                    else
                        control:SetValue(value)
                    end
                    closeList()
                end
            end))
        end
        -- AbsoluteSize/AbsolutePosition are post-scale screen values, but Position/Size
        -- offsets get multiplied by UIScale again, so divide it back out.
        local scale = UIScale.Scale > 0 and UIScale.Scale or 1
        listHolder.Size = UDim2.fromOffset(button.AbsoluteSize.X / scale, listHeight())
    end

    track(button.MouseButton1Click:Connect(function()
        if control.Disabled then return end
        if listHolder.Visible then closeList() return end
        if closeActiveDropdown then closeActiveDropdown() end
        closeActiveDropdown = closeList
        rebuild()

        local scale = UIScale.Scale > 0 and UIScale.Scale or 1
        local pos   = button.AbsolutePosition
        local viewH = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y or 720

        -- Compute the height rather than reading AbsoluteSize: it was only just set this
        -- frame and hasn't been laid out yet, so reading it back gives a stale value and
        -- the flip-above decision lands the list on top of its own button.
        local screenH = listHeight() * scale
        local top     = pos.Y + button.AbsoluteSize.Y + 4

        -- Not enough room below -> sit fully above the button, never overlapping it.
        if top + screenH > viewH then
            top = math.max(pos.Y - screenH - 4, 0)
        end

        listHolder.Position = UDim2.fromOffset(pos.X / scale, top / scale)
        blocker.Visible     = true
        listHolder.Visible  = true
    end))

    -- Mouse dismissal is the blocker's job. Only Escape is handled here, which matters for
    -- multi-select lists that stay open while you tick several entries.
    --
    -- Note for future edits: do NOT go back to comparing GetMouseLocation() against
    -- AbsolutePosition. GetMouseLocation() excludes the topbar inset while this ScreenGui
    -- sets IgnoreGuiInset, so they differ by ~36px -- that mismatch made clicks near the
    -- top of a list read as "outside" and closed it on mouse-press, before the option's
    -- click-on-release could register.
    track(UserInputService.InputBegan:Connect(function(input)
        if not listHolder.Visible then return end
        if input.KeyCode == Enum.KeyCode.Escape then closeList() end
    end))

    button.Text = displayText()
    if info.Callback then control:OnChanged(info.Callback) end
    Library.Options[idx] = control
    self:Resize()
    return control
end

--------------------------------------------------------------------- KeyPicker
-- Attached to a toggle or label row rather than being its own row, matching how the
-- script chains them: AddLabel("Place"):AddKeyPicker("AJPlace", {...}).
function Groupbox.AttachKeyPicker(row, idx, info)
    info = info or {}
    local button = create("TextButton", {
        Parent           = row,
        BackgroundColor3 = Theme.Control,
        Size             = UDim2.new(0, 46, 0, 18),
        Position         = UDim2.new(1, -46, 0, 0),
        Font             = FONT,
        Text             = tostring(info.Default or "None"),
        TextColor3       = Theme.SubText,
        TextSize         = TEXT_SIZE - 2,
        AutoButtonColor  = false,
        ZIndex           = 3,
    })
    corner(button, 4)
    stroke(button)

    local control  = newControl("KeyPicker", idx, info.Default, row)
    control.Mode   = info.Mode or "Toggle"
    control.Clicks = {}
    control.Active = false

    function control:OnClick(fn)
        table.insert(self.Clicks, fn)
        return self
    end

    function control:SetValue(value)
        -- Obsidian passes {key, mode} for keypickers; accept either shape.
        if type(value) == "table" then
            self.Value = value[1]
            self.Mode  = value[2] or self.Mode
        else
            self.Value = value
        end
        button.Text = tostring(self.Value or "None")
        self:Fire()
        return self
    end

    function control:GetState()
        return self.Active
    end

    local binding = false
    track(button.MouseButton1Click:Connect(function()
        binding = true
        button.Text = "..."
    end))

    track(UserInputService.InputBegan:Connect(function(input, processed)
        if binding then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                binding = false
                control:SetValue(input.KeyCode.Name)
            end
            return
        end
        if processed or control.Disabled or not control.Value then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if input.KeyCode.Name ~= control.Value then return end

        if control.Mode == "Toggle" then
            control.Active = not control.Active
        else
            control.Active = true
        end
        for _, fn in ipairs(control.Clicks) do
            task.spawn(function()
                local ok, err = pcall(fn)
                if not ok then warn("[PES UI] keypicker error: " .. tostring(err)) end
            end)
        end
        control:Fire()
    end))

    track(UserInputService.InputEnded:Connect(function(input)
        if control.Mode == "Hold" and input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode.Name == control.Value then
            control.Active = false
        end
    end))

    if info.Callback then control:OnChanged(info.Callback) end
    Library.Options[idx] = control
    return control
end

--------------------------------------------------------------------- ColorPicker
function Groupbox.AttachColorPicker(row, idx, info)
    info = info or {}
    local swatch = create("TextButton", {
        Parent           = row,
        BackgroundColor3 = info.Default or Color3.fromRGB(255, 255, 255),
        Size             = UDim2.new(0, 18, 0, 18),
        Position         = UDim2.new(1, -68, 0, 0),
        Text             = "",
        AutoButtonColor  = false,
        ZIndex           = 3,
    })
    corner(swatch, 4)
    stroke(swatch)

    local control = newControl("ColorPicker", idx, info.Default or Color3.new(1, 1, 1), row)

    function control:SetValueRGB(color)
        self.Value = color
        swatch.BackgroundColor3 = color
        self:Fire()
        return self
    end
    control.SetValue = control.SetValueRGB

    -- Cycling a small palette keeps this useful without a full HSV picker; the script
    -- only uses it for route colour.
    local palette = {
        Color3.fromRGB(126, 106, 255), Color3.fromRGB(95, 210, 130),
        Color3.fromRGB(235, 95, 95),   Color3.fromRGB(255, 200, 70),
        Color3.fromRGB(90, 200, 255),  Color3.fromRGB(255, 255, 255),
    }
    local at = 1
    track(swatch.MouseButton1Click:Connect(function()
        at = at % #palette + 1
        control:SetValueRGB(palette[at])
    end))

    if info.Callback then control:OnChanged(info.Callback) end
    Library.Options[idx] = control
    return control
end

--============================================================================
-- Groupbox construction
--============================================================================

function Groupbox:Resize()
    -- Columns auto-size; this exists because Obsidian exposes it and addons call it.
    return self
end

local function newGroupbox(parentColumn, title)
    local frame = create("Frame", {
        Parent           = parentColumn,
        BackgroundColor3 = Theme.Groupbox,
        Size             = UDim2.new(1, 0, 0, 0),
        AutomaticSize    = Enum.AutomaticSize.Y,
    })
    corner(frame)
    stroke(frame)
    padding(frame, 10)
    local col = listLayout(frame, 6)
    col.SortOrder = Enum.SortOrder.LayoutOrder

    create("TextLabel", {
        Parent                 = frame,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 18),
        Font                   = FONT_BOLD,
        Text                   = title or "Group",
        TextColor3             = Theme.Text,
        TextSize               = TEXT_SIZE + 1,
        TextXAlignment         = Enum.TextXAlignment.Left,
        LayoutOrder            = -1,
    })

    local box = setmetatable({ Frame = frame, Content = frame }, Groupbox)
    return box
end

--============================================================================
-- Tabs / Window
--============================================================================

local function newTab(window, name)
    local tabButton = create("TextButton", {
        Parent           = window.Sidebar,
        BackgroundColor3 = Theme.Sidebar,
        BackgroundTransparency = 1,
        Size             = UDim2.new(1, 0, 0, 30),
        Font             = FONT,
        Text             = "  " .. name,
        TextColor3       = Theme.SubText,
        TextSize         = TEXT_SIZE,
        TextXAlignment   = Enum.TextXAlignment.Left,
        AutoButtonColor  = false,
    })
    corner(tabButton, 5)

    local page = create("Frame", {
        Parent                 = window.Pages,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 1, 0),
        Visible                = false,
    })

    local function column(xScale, xOffset)
        local scroller = create("ScrollingFrame", {
            Parent                 = page,
            BackgroundTransparency = 1,
            Size                   = UDim2.new(0.5, -6, 1, 0),
            Position               = UDim2.new(xScale, xOffset, 0, 0),
            ScrollBarThickness     = 3,
            ScrollBarImageColor3   = Theme.Accent,
            CanvasSize             = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize    = Enum.AutomaticSize.Y,
            BorderSizePixel        = 0,
        })
        listLayout(scroller, 8)
        return scroller
    end

    local tab = {
        Name    = name,
        Button  = tabButton,
        Page    = page,
        Left    = column(0, 0),
        Right   = column(0.5, 6),
    }

    function tab:AddLeftGroupbox(title)  return newGroupbox(self.Left, title)  end
    function tab:AddRightGroupbox(title) return newGroupbox(self.Right, title) end

    track(tabButton.MouseButton1Click:Connect(function()
        window:SelectTab(tab)
    end))

    table.insert(window.Tabs, tab)
    if #window.Tabs == 1 then window:SelectTab(tab) end
    return tab
end

function Library:CreateWindow(info)
    info = info or {}

    -- Sized against the viewport rather than fixed, so it isn't tiny on a big monitor.
    -- Clamped so it stays usable on small screens too.
    local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
        or Vector2.new(1280, 720)
    local width  = math.clamp(math.floor(viewport.X * 0.62), 720, 1100)
    local height = math.clamp(math.floor(viewport.Y * 0.68), 500, 760)

    local main = create("Frame", {
        Parent           = ScreenGui,
        BackgroundColor3 = Theme.Background,
        Size             = UDim2.new(0, width, 0, height),
        Position         = UDim2.new(0.5, -width / 2, 0.5, -height / 2),
        ClipsDescendants = false,
    })
    corner(main)
    stroke(main)

    local titleBar = create("Frame", {
        Parent           = main,
        BackgroundColor3 = Theme.Sidebar,
        Size             = UDim2.new(1, 0, 0, 34),
    })
    corner(titleBar)

    create("TextLabel", {
        Parent                 = titleBar,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, -20, 1, 0),
        Position               = UDim2.new(0, 12, 0, 0),
        Font                   = FONT_BOLD,
        Text                   = info.Title or "Project EToH Script",
        TextColor3             = Theme.Text,
        TextSize               = TEXT_SIZE + 2,
        TextXAlignment         = Enum.TextXAlignment.Left,
    })

    local footer = create("TextLabel", {
        Parent                 = main,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, -20, 0, 18),
        Position               = UDim2.new(0, 12, 1, -22),
        Font                   = FONT,
        Text                   = info.Footer or "",
        TextColor3             = Theme.SubText,
        TextSize               = TEXT_SIZE - 2,
        TextXAlignment         = Enum.TextXAlignment.Left,
    })

    local sidebar = create("Frame", {
        Parent           = main,
        BackgroundColor3 = Theme.Sidebar,
        Size             = UDim2.new(0, 130, 1, -60),
        Position         = UDim2.new(0, 8, 0, 40),
    })
    corner(sidebar)
    padding(sidebar, 6)
    listLayout(sidebar, 4)

    local pages = create("Frame", {
        Parent                 = main,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, -160, 1, -60),
        Position               = UDim2.new(0, 148, 0, 40),
    })

    local window = {
        Main    = main,
        Sidebar = sidebar,
        Pages   = pages,
        Footer  = footer,
        Tabs    = {},
    }

    function window:SelectTab(tab)
        for _, t in ipairs(self.Tabs) do
            local on = (t == tab)
            t.Page.Visible = on
            t.Button.TextColor3 = on and Theme.Text or Theme.SubText
            tween(t.Button, 0.12, { BackgroundTransparency = on and 0 or 1 })
            t.Button.BackgroundColor3 = Theme.Control
        end
    end

    function window:AddTab(name)
        return newTab(self, name)
    end

    function window:SetCornerRadius(radius)
        Library.CornerRadius = radius
        for _, c in ipairs(Library.Corners) do
            if c and c.Parent then c.CornerRadius = UDim.new(0, radius) end
        end
        return self
    end

    makeDraggable(main, titleBar)

    -- Keybind list, shown bottom-left; the script toggles its Visible directly.
    local keybindFrame = create("Frame", {
        Parent           = ScreenGui,
        BackgroundColor3 = Theme.Groupbox,
        Size             = UDim2.new(0, 160, 0, 0),
        AutomaticSize    = Enum.AutomaticSize.Y,
        Position         = UDim2.new(0, 20, 1, -140),
        Visible          = false,
    })
    corner(keybindFrame)
    stroke(keybindFrame)
    padding(keybindFrame, 8)
    listLayout(keybindFrame, 4)
    create("TextLabel", {
        Parent                 = keybindFrame,
        BackgroundTransparency = 1,
        Size                   = UDim2.new(1, 0, 0, 16),
        Font                   = FONT_BOLD,
        Text                   = "Keybinds",
        TextColor3             = Theme.Text,
        TextSize               = TEXT_SIZE,
        TextXAlignment         = Enum.TextXAlignment.Left,
    })
    Library.KeybindFrame = keybindFrame

    Library.Window = window
    Library.MainFrame = main

    if info.AutoShow ~= false then main.Visible = true end

    -- Menu toggle key. ToggleKeybind may be an Enum.KeyCode (at creation) or, later,
    -- a KeyPicker control the script assigns -- accept both.
    local defaultKey = info.ToggleKeybind or Enum.KeyCode.RightShift
    track(UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

        local bind = Library.ToggleKeybind
        local wanted
        if typeof(bind) == "EnumItem" then
            wanted = bind.Name
        elseif type(bind) == "table" and bind.Value then
            wanted = tostring(bind.Value)
        else
            wanted = defaultKey.Name
        end
        if input.KeyCode.Name == wanted then
            main.Visible = not main.Visible
        end
    end))

    return window
end

--============================================================================
-- Misc Library methods the script calls
--============================================================================

function Library:SetDPIScale(scale)
    UIScale.Scale = (tonumber(scale) or 100) / 100
    return self
end

function Library:Unload()
    Library.Unloaded = true
    for _, conn in ipairs(Library.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    Library.Connections = {}
    pcall(function() ScreenGui:Destroy() end)
    return self
end

--============================================================================
-- SaveManager -- config persistence, same method names the script uses
--============================================================================

local SaveManager = {
    Library = nil,
    Folder  = "PESUI",
    Ignore  = {},
}

function SaveManager:SetLibrary(lib) self.Library = lib return self end

function SaveManager:SetFolder(folder)
    self.Folder = folder
    pcall(function()
        if not isfolder(folder) then makefolder(folder) end
        if not isfolder(folder .. "/settings") then makefolder(folder .. "/settings") end
    end)
    return self
end

function SaveManager:IgnoreThemeSettings()
    -- Themes live outside configs here, so nothing to exclude; kept for API parity.
    return self
end

function SaveManager:SetIgnoreIndexes(list)
    for _, idx in ipairs(list or {}) do self.Ignore[idx] = true end
    return self
end

local function serialise()
    local data = {}
    for idx, control in pairs(Registry) do
        if not SaveManager.Ignore[idx] then
            local value = control.Value
            if typeof(value) == "Color3" then
                data[idx] = { __type = "Color3", r = value.R, g = value.G, b = value.B }
            elseif type(value) ~= "table" then
                data[idx] = { __type = "raw", v = value }
            else
                -- Multi-dropdown maps are plain string->bool.
                data[idx] = { __type = "map", v = value }
            end
        end
    end
    return data
end

local function deserialise(data)
    for idx, entry in pairs(data or {}) do
        local control = Registry[idx]
        if control and type(entry) == "table" then
            if entry.__type == "Color3" then
                pcall(function() control:SetValue(Color3.new(entry.r, entry.g, entry.b)) end)
            else
                pcall(function() control:SetValue(entry.v) end)
            end
        end
    end
end

function SaveManager:Save(name)
    if not name or name == "" then return false, "no name" end
    local path = ("%s/settings/%s.json"):format(self.Folder, name)
    local ok, err = pcall(function()
        writefile(path, HttpService:JSONEncode(serialise()))
    end)
    return ok, err
end

function SaveManager:Load(name)
    if not name or name == "" then return false, "no name" end
    local path = ("%s/settings/%s.json"):format(self.Folder, name)
    local ok, err = pcall(function()
        if not isfile(path) then error("config not found") end
        deserialise(HttpService:JSONDecode(readfile(path)))
    end)
    return ok, err
end

function SaveManager:Delete(name)
    local path = ("%s/settings/%s.json"):format(self.Folder, name)
    return pcall(function() if isfile(path) then delfile(path) end end)
end

function SaveManager:RefreshList()
    local out = {}
    pcall(function()
        for _, file in ipairs(listfiles(self.Folder .. "/settings")) do
            local name = file:match("([^/\\]+)%.json$")
            if name then table.insert(out, name) end
        end
    end)
    table.sort(out)
    return out
end

function SaveManager:LoadAutoloadConfig()
    local path = self.Folder .. "/autoload.txt"
    pcall(function()
        if isfile(path) then
            local name = readfile(path)
            local ok = self:Load(name)
            Library:Notify({
                Title       = "Configs",
                Description = ok and ("Autoloaded '" .. name .. "'") or ("Couldn't autoload '" .. name .. "'"),
                Duration    = 4,
            })
        end
    end)
    return self
end

function SaveManager:BuildConfigSection(tab)
    local box = tab:AddRightGroupbox("Configs")

    box:AddInput("SaveManager_ConfigName", { Text = "Config name", Finished = true })
    box:AddDropdown("SaveManager_ConfigList", {
        Text      = "Saved configs",
        Values    = self:RefreshList(),
        AllowNull = true,
    })

    local function selected()
        return Library.Options.SaveManager_ConfigList
            and Library.Options.SaveManager_ConfigList.Value
    end

    box:AddButton({
        Text = "Create",
        Callback = function()
            local name = Library.Options.SaveManager_ConfigName
                and Library.Options.SaveManager_ConfigName.Value
            local ok, err = self:Save(name)
            Library:Notify({
                Title       = "Configs",
                Description = ok and ("Saved '" .. tostring(name) .. "'") or ("Save failed: " .. tostring(err)),
                Duration    = 4,
            })
            if ok then Library.Options.SaveManager_ConfigList:SetValues(self:RefreshList()) end
        end,
    })
    box:AddButton({
        Text = "Load",
        Callback = function()
            local name = selected()
            local ok, err = self:Load(name)
            Library:Notify({
                Title       = "Configs",
                Description = ok and ("Loaded '" .. tostring(name) .. "'") or ("Load failed: " .. tostring(err)),
                Duration    = 4,
            })
        end,
    })
    box:AddButton({
        Text = "Overwrite",
        Callback = function()
            local name = selected()
            local ok = self:Save(name)
            Library:Notify({
                Title       = "Configs",
                Description = ok and ("Overwrote '" .. tostring(name) .. "'") or "Overwrite failed",
                Duration    = 4,
            })
        end,
    })
    box:AddButton({
        Text = "Delete",
        Callback = function()
            local name = selected()
            self:Delete(name)
            Library.Options.SaveManager_ConfigList:SetValues(self:RefreshList())
            Library:Notify({ Title = "Configs", Description = "Deleted '" .. tostring(name) .. "'", Duration = 4 })
        end,
    })
    box:AddButton({
        Text = "Set as autoload",
        Callback = function()
            local name = selected()
            if not name then return end
            pcall(function() writefile(self.Folder .. "/autoload.txt", name) end)
            Library:Notify({ Title = "Configs", Description = "Autoload set to '" .. name .. "'", Duration = 4 })
        end,
    })
    box:AddButton({
        Text = "Refresh list",
        Callback = function()
            Library.Options.SaveManager_ConfigList:SetValues(self:RefreshList())
        end,
    })

    return box
end

--============================================================================
-- ThemeManager -- accent switching
--============================================================================

local ThemeManager = { Library = nil }

function ThemeManager:SetLibrary(lib) self.Library = lib return self end
function ThemeManager:SetFolder(folder) self.Folder = folder return self end

local PRESETS = {
    Purple = Color3.fromRGB(126, 106, 255),
    Green  = Color3.fromRGB(95, 210, 130),
    Red    = Color3.fromRGB(235, 95, 95),
    Blue   = Color3.fromRGB(90, 160, 255),
    Amber  = Color3.fromRGB(255, 190, 70),
    Mono   = Color3.fromRGB(200, 200, 210),
}

function ThemeManager:ApplyAccent(color)
    Theme.Accent = color
    for _, entry in ipairs(Library._accentObjects) do
        if entry.inst and entry.inst.Parent then
            pcall(function() entry.inst[entry.prop] = color end)
        end
    end
    for _, d in ipairs(ScreenGui:GetDescendants()) do
        if d:IsA("ScrollingFrame") then d.ScrollBarImageColor3 = color end
    end
    return self
end

function ThemeManager:ApplyToTab(tab)
    local box = tab:AddRightGroupbox("Theme")
    local names = {}
    for name in pairs(PRESETS) do table.insert(names, name) end
    table.sort(names)

    box:AddDropdown("ThemeManager_Accent", {
        Text     = "Accent",
        Values   = names,
        Default  = "Purple",
        Callback = function(value)
            if PRESETS[value] then ThemeManager:ApplyAccent(PRESETS[value]) end
        end,
    })
    return box
end

function ThemeManager:ApplyToGroupbox(box) return box end

--============================================================================

Library.SaveManager  = SaveManager
Library.ThemeManager = ThemeManager
Library.Registry     = Registry

getgenv().PESUI = Library
return Library
