--[[
    Haze UI Library
    Holographic neon / cyberpunk glass UI for Roblox.

    Drop this entire file into a ModuleScript, then require it from a LocalScript
    or load it with your executor's preferred ModuleScript workflow.

    Public API:
        Haze:CreateWindow(config)
        Haze:Notify(config)
        Window:CreateTab(config)
        Tab:CreateSection(name)
        Section:CreateButton(config)
        Section:CreateToggle(config)
        Section:CreateSlider(config)
        Section:CreateDropdown(config)
        Section:CreateTextbox(config)
        Section:CreateKeybind(config)
        Section:CreateColorPicker(config)
        Section:CreateLabel(text)
--]]

--// Services -----------------------------------------------------------------

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

-- Required executor-aware parent. In an ordinary LocalScript, gethui is nil and
-- the library uses CoreGui. In supported executors, gethui() is preferred.
local parent = (gethui and gethui()) or game:GetService("CoreGui")

local Haze = {}
Haze.__index = Haze

--// Retheming -----------------------------------------------------------------

-- CHANGE THE DEFAULT ACCENT HERE. The default holographic gradient begins at
-- electric cyan and bleeds into the magenta value immediately below it.
local DEFAULT_ACCENT = Color3.fromRGB(0, 229, 255) -- #00E5FF
local DEFAULT_MAGENTA = Color3.fromRGB(255, 46, 151) -- #FF2E97

-- CHANGE THE REST OF THE THEME HERE if you want to retheme the glass, text,
-- shadows, corner radius, or typography without touching component code.
local THEME = {
    Accent = DEFAULT_ACCENT,
    AccentB = DEFAULT_MAGENTA,
    Background = Color3.fromRGB(7, 9, 18),
    Glass = Color3.fromRGB(15, 19, 34),
    GlassRaised = Color3.fromRGB(23, 28, 47),
    Control = Color3.fromRGB(25, 31, 51),
    Text = Color3.fromRGB(238, 247, 255),
    Muted = Color3.fromRGB(133, 148, 174),
    Dark = Color3.fromRGB(3, 5, 12),
    Success = Color3.fromRGB(72, 255, 182),
    Danger = Color3.fromRGB(255, 78, 111),
    Corner = UDim.new(0, 9),
    Font = Enum.Font.Gotham,
    FontMedium = Enum.Font.GothamMedium,
    FontBold = Enum.Font.GothamBold,
    FontBlack = Enum.Font.GothamBlack,
}

Haze.ToggleKey = Enum.KeyCode.RightShift
Haze._windows = {}
Haze._uiVisible = true
Haze._introState = "idle"
Haze._introCallbacks = {}
Haze._notificationId = 0
Haze._capturingKeybind = false
Haze._introObject = nil

--// Utility layer -------------------------------------------------------------

local function create(className, properties, children)
    local object = Instance.new(className)

    for property, value in pairs(properties or {}) do
        object[property] = value
    end

    for _, child in ipairs(children or {}) do
        child.Parent = object
    end

    return object
end

local function addCorner(object, radius)
    return create("UICorner", {
        CornerRadius = radius or THEME.Corner,
        Parent = object,
    })
end

local function addPadding(object, left, right, top, bottom)
    return create("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or left or 0),
        PaddingTop = UDim.new(0, top or left or 0),
        PaddingBottom = UDim.new(0, bottom or top or left or 0),
        Parent = object,
    })
end

local function addStroke(object, color, thickness, transparency)
    return create("UIStroke", {
        Color = color or THEME.Accent,
        Thickness = thickness or 1,
        Transparency = transparency == nil and 0.65 or transparency,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = object,
    })
end

local function addAccentGradient(object, rotation)
    return create("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, THEME.Accent),
            ColorSequenceKeypoint.new(0.5, THEME.AccentB),
            ColorSequenceKeypoint.new(1, THEME.Accent),
        }),
        Rotation = rotation or 0,
        Parent = object,
    })
end

local function tween(object, duration, style, direction, properties, repeatCount, reverses, delayTime)
    local animation = TweenService:Create(
        object,
        TweenInfo.new(
            duration,
            style or Enum.EasingStyle.Quart,
            direction or Enum.EasingDirection.Out,
            repeatCount or 0,
            reverses or false,
            delayTime or 0
        ),
        properties
    )
    animation:Play()
    return animation
end

local function safeCall(callback, ...)
    if type(callback) ~= "function" then
        return
    end

    local arguments = table.pack(...)
    task.spawn(function()
        local ok, message = pcall(function()
            callback(table.unpack(arguments, 1, arguments.n))
        end)
        if not ok then
            warn("[Haze UI] Callback error: " .. tostring(message))
        end
    end)
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function round(value, places)
    local power = 10 ^ (places or 0)
    return math.floor(value * power + 0.5) / power
end

local function formatNumber(value, minimum, maximum, step)
    if step and step >= 1 and minimum % 1 == 0 and maximum % 1 == 0 then
        return tostring(math.floor(value + 0.5))
    end

    local decimals = 2
    if step and step > 0 and step < 1 then
        local stepText = string.format("%.6f", step):gsub("0+$", "")
        local decimalPoint = string.find(stepText, ".", 1, true)
        if decimalPoint then
            decimals = math.min(6, #stepText - decimalPoint)
        end
    end

    local formatted = string.format("%." .. decimals .. "f", value)
    formatted = formatted:gsub("0+$", ""):gsub("%.$", "")
    return formatted
end

local function colorToHex(color)
    return string.format(
        "#%02X%02X%02X",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5)
    )
end

local function normalizeSize(value)
    if typeof(value) == "UDim2" then
        return value
    elseif typeof(value) == "Vector2" then
        return UDim2.fromOffset(value.X, value.Y)
    end
    return UDim2.fromOffset(760, 510)
end

local function keyName(keyCode)
    local name = keyCode.Name
    local replacements = {
        LeftShift = "L-SHIFT",
        RightShift = "R-SHIFT",
        LeftControl = "L-CTRL",
        RightControl = "R-CTRL",
        LeftAlt = "L-ALT",
        RightAlt = "R-ALT",
        Backspace = "BACK",
        Return = "ENTER",
        CapsLock = "CAPS",
    }
    return replacements[name] or string.upper(name)
end

local function bindConnection(owner, signal, callback)
    local connection = signal:Connect(callback)
    table.insert(owner._connections, connection)
    return connection
end

local function disconnectAll(owner)
    for _, connection in ipairs(owner._connections) do
        if connection.Connected then
            connection:Disconnect()
        end
    end
    table.clear(owner._connections)
end

-- A glow made entirely from Roblox UI objects; no external images are needed.
local function addSoftGlow(parentObject, color, cornerRadius, zIndex)
    local glow = create("Frame", {
        Name = "SoftGlow",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, 14, 1, 14),
        BackgroundColor3 = color or THEME.Accent,
        BackgroundTransparency = 0.91,
        BorderSizePixel = 0,
        ZIndex = zIndex or math.max(0, parentObject.ZIndex - 1),
        Parent = parentObject,
    })
    addCorner(glow, cornerRadius or UDim.new(0, 12))
    return glow
end

local function makeRipple(button, screenPosition)
    if not button or not button.Parent then
        return
    end

    local localX = screenPosition.X - button.AbsolutePosition.X
    local localY = screenPosition.Y - button.AbsolutePosition.Y
    local diameter = math.max(button.AbsoluteSize.X, button.AbsoluteSize.Y) * 2.25

    local ripple = create("Frame", {
        Name = "HazeRipple",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(localX, localY),
        Size = UDim2.fromOffset(0, 0),
        BackgroundColor3 = THEME.Accent,
        BackgroundTransparency = 0.55,
        BorderSizePixel = 0,
        ZIndex = button.ZIndex + 4,
        Parent = button,
    })
    addCorner(ripple, UDim.new(1, 0))

    local animation = tween(
        ripple,
        0.58,
        Enum.EasingStyle.Quint,
        Enum.EasingDirection.Out,
        {
            Size = UDim2.fromOffset(diameter, diameter),
            BackgroundTransparency = 1,
        }
    )
    animation.Completed:Connect(function()
        ripple:Destroy()
    end)
end

-- Common glass hover behavior used by controls.
local function installHover(owner, object, scale, stroke, amount)
    local hoverScale = amount or 1.015
    bindConnection(owner, object.MouseEnter, function()
        tween(scale, 0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Scale = hoverScale })
        tween(object, 0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
            BackgroundColor3 = THEME.GlassRaised,
            BackgroundTransparency = 0.12,
        })
        if stroke then
            tween(stroke, 0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
                Transparency = 0.28,
                Color = THEME.Accent,
            })
        end
    end)

    bindConnection(owner, object.MouseLeave, function()
        tween(scale, 0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, { Scale = 1 })
        tween(object, 0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
            BackgroundColor3 = THEME.Control,
            BackgroundTransparency = 0.22,
        })
        if stroke then
            tween(stroke, 0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
                Transparency = 0.7,
                Color = THEME.Accent,
            })
        end
    end)
end

--// Root GUI ------------------------------------------------------------------

local ROOT_NAME = "Haze_UI_Library"
local existing = parent:FindFirstChild(ROOT_NAME)
if existing then
    existing:Destroy()
end

local RootGui = create("ScreenGui", {
    Name = ROOT_NAME,
    IgnoreGuiInset = true,
    ResetOnSpawn = false,
    DisplayOrder = 999999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

-- Some ordinary LocalScript environments are stricter about CoreGui writes.
-- The required CoreGui/gethui target is attempted first; PlayerGui is only a
-- last-resort compatibility fallback if Roblox rejects that parent assignment.
local parented = pcall(function()
    RootGui.Parent = parent
end)
if not parented then
    local player = Players.LocalPlayer
    RootGui.Parent = player:WaitForChild("PlayerGui")
end

local WindowLayer = create("Frame", {
    Name = "Windows",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Parent = RootGui,
})

local NotificationLayer = create("Frame", {
    Name = "Notifications",
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -22, 1, -22),
    Size = UDim2.fromOffset(354, 560),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 500,
    Parent = RootGui,
})

create("UIListLayout", {
    FillDirection = Enum.FillDirection.Vertical,
    HorizontalAlignment = Enum.HorizontalAlignment.Right,
    VerticalAlignment = Enum.VerticalAlignment.Bottom,
    Padding = UDim.new(0, 10),
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = NotificationLayer,
})

--// Cinematic boot sequence ---------------------------------------------------

local function playIntro(onFinished)
    if type(onFinished) == "function" then
        table.insert(Haze._introCallbacks, onFinished)
    end

    if Haze._introState == "done" then
        local callbacks = Haze._introCallbacks
        Haze._introCallbacks = {}
        for _, callback in ipairs(callbacks) do
            safeCall(callback)
        end
        return
    elseif Haze._introState == "playing" then
        return
    end

    Haze._introState = "playing"

    local intro = create("CanvasGroup", {
        Name = "HazeBootSequence",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = THEME.Dark,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Visible = Haze._uiVisible,
        ZIndex = 1000,
        Parent = RootGui,
    })
    Haze._introObject = intro

    local introScale = create("UIScale", {
        Scale = 1,
        Parent = intro,
    })

    local atmosphere = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(640, 300),
        BackgroundColor3 = THEME.Accent,
        BackgroundTransparency = 0.96,
        BorderSizePixel = 0,
        ZIndex = 1001,
        Parent = intro,
    })
    addCorner(atmosphere, UDim.new(1, 0))
    local atmosphereGradient = addAccentGradient(atmosphere, 0)

    -- Fine horizontal scanlines across the fullscreen overlay. Keep the field
    -- viewport-aware and bounded so startup remains light on every device.
    local scanGrid = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 1001,
        Parent = intro,
    })
    local camera = workspace.CurrentCamera
    local viewportHeight = camera and camera.ViewportSize.Y or 720
    local scanSpacing = math.max(10, math.ceil(viewportHeight / 72))
    for y = 0, viewportHeight, scanSpacing do
        create("Frame", {
            Position = UDim2.new(0, 0, 0, y),
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = Color3.fromRGB(118, 180, 204),
            BackgroundTransparency = 0.965,
            BorderSizePixel = 0,
            ZIndex = 1001,
            Parent = scanGrid,
        })
    end

    local logoGroup = create("CanvasGroup", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, -12),
        Size = UDim2.fromOffset(520, 180),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        GroupTransparency = 0,
        ZIndex = 1002,
        Parent = intro,
    })
    local logoScale = create("UIScale", {
        Scale = 0.72,
        Parent = logoGroup,
    })

    -- Stacked labels fake a soft neon bloom without requiring an image asset.
    for index = 1, 3 do
        local glow = create("TextLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.42, 0),
            Size = UDim2.new(1, 20 * index, 0, 104 + 10 * index),
            BackgroundTransparency = 1,
            Text = "Haze",
            TextColor3 = index % 2 == 0 and THEME.AccentB or THEME.Accent,
            TextTransparency = 0.84 + index * 0.035,
            TextSize = 88 + index * 3,
            Font = THEME.FontBlack,
            ZIndex = 1002,
            Parent = logoGroup,
        })
        addAccentGradient(glow, -12)
    end

    local revealMask = create("Frame", {
        Name = "LogoReveal",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.42, 0),
        Size = UDim2.fromOffset(0, 122),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 1005,
        Parent = logoGroup,
    })

    local logo = create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(500, 120),
        BackgroundTransparency = 1,
        Text = "Haze",
        TextColor3 = Color3.new(1, 1, 1),
        TextTransparency = 0.02,
        TextSize = 92,
        Font = THEME.FontBlack,
        ZIndex = 1006,
        Parent = revealMask,
    })
    local logoGradient = addAccentGradient(logo, -60)

    local wipe = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, -12, 0.5, 0),
        Size = UDim2.fromOffset(5, 112),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        ZIndex = 1008,
        Parent = revealMask,
    })
    addSoftGlow(wipe, THEME.Accent, UDim.new(1, 0), 1007)
    addCorner(wipe, UDim.new(1, 0))

    local subtitle = create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.82, 0),
        Size = UDim2.fromOffset(340, 26),
        BackgroundTransparency = 1,
        Text = "made by $hane",
        TextColor3 = THEME.Text,
        TextTransparency = 1,
        TextSize = 15,
        Font = THEME.FontMedium,
        ZIndex = 1007,
        Parent = logoGroup,
    })
    local subtitleStroke = addStroke(subtitle, THEME.Accent, 1, 1)

    tween(intro, 0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { GroupTransparency = 0 })
    tween(atmosphere, 1.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
        Size = UDim2.fromOffset(820, 380),
        BackgroundTransparency = 0.975,
    })
    tween(atmosphereGradient, 2.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, { Rotation = 360 })
    tween(logoScale, 0.92, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
    tween(revealMask, 0.86, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, { Size = UDim2.fromOffset(500, 122) })
    tween(wipe, 0.86, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, { Position = UDim2.new(1, 12, 0.5, 0) })
    tween(logoGradient, 1.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, { Rotation = 300 })

    task.delay(0.48, function()
        if subtitle.Parent then
            tween(subtitle, 0.62, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
                TextTransparency = 0.08,
                Position = UDim2.new(0.5, 0, 0.78, 0),
            })
            tween(subtitleStroke, 0.62, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
                Transparency = 0.73,
            })
        end
    end)

    -- The logo holds on screen, then the complete layer blooms and fades away.
    task.delay(2.35, function()
        if not intro.Parent then
            return
        end

        tween(logoScale, 0.58, Enum.EasingStyle.Quint, Enum.EasingDirection.In, { Scale = 1.14 })
        tween(introScale, 0.58, Enum.EasingStyle.Quint, Enum.EasingDirection.In, { Scale = 1.03 })
        local fade = tween(intro, 0.62, Enum.EasingStyle.Quint, Enum.EasingDirection.In, {
            GroupTransparency = 1,
            BackgroundTransparency = 1,
        })
        fade.Completed:Connect(function()
            if intro.Parent then
                intro:Destroy()
            end
            if Haze._introObject == intro then
                Haze._introObject = nil
            end
            Haze._introState = "done"
            local callbacks = Haze._introCallbacks
            Haze._introCallbacks = {}
            for _, callback in ipairs(callbacks) do
                safeCall(callback)
            end
        end)
    end)
end

--// Notification system -------------------------------------------------------

function Haze:Notify(config)
    config = config or {}
    self._notificationId += 1

    local duration = math.max(0.75, tonumber(config.Duration) or 4)
    local slot = create("Frame", {
        Name = "NotificationSlot_" .. self._notificationId,
        Size = UDim2.fromOffset(350, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = -self._notificationId,
        ZIndex = 500,
        Parent = NotificationLayer,
    })

    local card = create("CanvasGroup", {
        Name = "Notification",
        Position = UDim2.new(1, 24, 0, 0),
        Size = UDim2.fromOffset(350, 92),
        BackgroundColor3 = THEME.Glass,
        BackgroundTransparency = 0.06,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        ClipsDescendants = true,
        ZIndex = 501,
        Parent = slot,
    })
    addCorner(card, UDim.new(0, 11))

    local cardStroke = addStroke(card, Color3.new(1, 1, 1), 1.35, 0.22)
    local cardGradient = addAccentGradient(cardStroke, -40)
    tween(cardGradient, 5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, { Rotation = 320 }, -1)

    local glowBar = create("Frame", {
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(4, 92),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        ZIndex = 503,
        Parent = card,
    })
    addAccentGradient(glowBar, 90)
    addCorner(glowBar, UDim.new(1, 0))

    create("TextLabel", {
        Position = UDim2.fromOffset(20, 14),
        Size = UDim2.new(1, -42, 0, 22),
        BackgroundTransparency = 1,
        Text = tostring(config.Title or "Haze"),
        TextColor3 = THEME.Text,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Font = THEME.FontBold,
        ZIndex = 503,
        Parent = card,
    })

    create("TextLabel", {
        Position = UDim2.fromOffset(20, 39),
        Size = UDim2.new(1, -42, 0, 34),
        BackgroundTransparency = 1,
        Text = tostring(config.Text or "Notification"),
        TextColor3 = THEME.Muted,
        TextSize = 12,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Font = THEME.Font,
        ZIndex = 503,
        Parent = card,
    })

    local progress = create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 5, 1, 0),
        Size = UDim2.new(1, -5, 0, 2),
        BackgroundColor3 = THEME.Accent,
        BackgroundTransparency = 0.12,
        BorderSizePixel = 0,
        ZIndex = 504,
        Parent = card,
    })
    addAccentGradient(progress, 0)

    tween(slot, 0.46, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Size = UDim2.fromOffset(350, 92) })
    tween(card, 0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
        Position = UDim2.fromOffset(0, 0),
        GroupTransparency = 0,
    })
    tween(progress, duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, {
        Size = UDim2.fromOffset(0, 2),
    })

    task.delay(duration, function()
        if not slot.Parent then
            return
        end
        tween(card, 0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.In, {
            Position = UDim2.new(1, 30, 0, 0),
            GroupTransparency = 1,
        })
        local collapse = tween(slot, 0.46, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut, {
            Size = UDim2.fromOffset(350, 0),
        }, 0, false, 0.15)
        collapse.Completed:Connect(function()
            if slot.Parent then
                slot:Destroy()
            end
        end)
    end)

    return card
end

--// Window class --------------------------------------------------------------

local Window = {}
Window.__index = Window

function Window:_bind(signal, callback)
    return bindConnection(self, signal, callback)
end

function Window:_startBorderLoop()
    if self._destroyed or self._closing or self._borderLoop or self._borderOpening then
        return
    end

    self.BorderGradient.Rotation = 0
    self._borderLoop = tween(
        self.BorderGradient,
        8,
        Enum.EasingStyle.Linear,
        Enum.EasingDirection.InOut,
        { Rotation = 360 },
        -1
    )
end

function Window:_open()
    if self._destroyed or not self.Main.Parent then
        return
    end

    self._opened = true
    self._visible = Haze._uiVisible

    -- A window queued behind the splash must honor the current global hidden
    -- state instead of becoming visible after RightShift has already hidden UI.
    if not Haze._uiVisible then
        self.Main.Visible = false
        self.Main.GroupTransparency = 1
        self.Scale.Scale = 1
        self.Border.Transparency = 0.12
        self.BorderGradient.Rotation = 0
        self:_startBorderLoop()
        return
    end

    self.Main.Visible = true
    self.Main.GroupTransparency = 1
    self.Scale.Scale = 0
    self.Border.Transparency = 1
    self.BorderGradient.Rotation = -180
    self._borderOpening = true

    tween(self.Main, 0.54, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
        GroupTransparency = 0,
    })
    tween(self.Scale, 0.78, Enum.EasingStyle.Back, Enum.EasingDirection.Out, {
        Scale = 1,
    })
    tween(self.Border, 0.62, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
        Transparency = 0.12,
    })
    local borderReveal = tween(self.BorderGradient, 1.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
        Rotation = 0,
    })
    borderReveal.Completed:Connect(function()
        self._borderOpening = false
        self:_startBorderLoop()
    end)
end

function Window:SetVisible(isVisible)
    if self._destroyed or self._closing then
        return
    end

    self._visible = isVisible
    if not self._opened then
        return
    end

    if isVisible then
        self.Main.Visible = true
        self.Main.GroupTransparency = 1
        self.Scale.Scale = 0.94
        self.Border.Transparency = 0.12
        self:_startBorderLoop()
        tween(self.Main, 0.36, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
            GroupTransparency = 0,
        })
        tween(self.Scale, 0.48, Enum.EasingStyle.Back, Enum.EasingDirection.Out, {
            Scale = 1,
        })
    else
        tween(self.Scale, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In, {
            Scale = 0.94,
        })
        local fade = tween(self.Main, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In, {
            GroupTransparency = 1,
        })
        fade.Completed:Connect(function()
            if self.Main.Parent and not self._visible then
                self.Main.Visible = false
            end
        end)
    end
end

function Window:Close()
    if self._destroyed or self._closing then
        return
    end
    self._closing = true
    Haze._capturingKeybind = false

    if self._borderLoop then
        self._borderLoop:Cancel()
        self._borderLoop = nil
    end

    tween(self.BorderGradient, 0.46, Enum.EasingStyle.Quint, Enum.EasingDirection.In, {
        Rotation = 180,
    })
    tween(self.Scale, 0.48, Enum.EasingStyle.Back, Enum.EasingDirection.In, {
        Scale = 0,
    })
    local fade = tween(self.Main, 0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.In, {
        GroupTransparency = 1,
    })

    fade.Completed:Connect(function()
        self._destroyed = true
        disconnectAll(self)
        if self.Main.Parent then
            self.Main:Destroy()
        end
        local index = table.find(Haze._windows, self)
        if index then
            table.remove(Haze._windows, index)
        end
    end)
end

function Window:Destroy()
    self:Close()
end

--// Tab class -----------------------------------------------------------------

local Tab = {}
Tab.__index = Tab

local Section = {}
Section.__index = Section

function Window:_selectTab(tab)
    if self._activeTab == tab or self._destroyed then
        return
    end

    self._tabSwitchToken += 1
    local previous = self._activeTab
    self._activeTab = tab

    local direction = 1
    if previous and tab._index < previous._index then
        direction = -1
    end

    -- Cancel stale pages left by interrupted cross-fades. Only the outgoing and
    -- incoming pages participate in this transition, and only the active page
    -- is allowed to receive input.
    for _, other in ipairs(self._tabs) do
        if other ~= tab and other ~= previous then
            other.Page.Visible = false
            other.Page.Interactable = false
            other.Page.GroupTransparency = 1
            other.Page.Position = UDim2.fromOffset(0, 0)
        end
    end

    if previous then
        previous.Page.Interactable = false
        tween(previous.Button, 0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
            BackgroundTransparency = 1,
            TextColor3 = THEME.Muted,
        })
        tween(previous.Icon, 0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
            TextColor3 = THEME.Muted,
        })

        local oldAnimation = tween(previous.Page, 0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In, {
            Position = UDim2.new(0, -direction * 26, 0, 0),
            GroupTransparency = 1,
        })
        oldAnimation.Completed:Connect(function()
            if self._activeTab ~= previous and previous.Page.Parent then
                previous.Page.Visible = false
                previous.Page.Position = UDim2.fromOffset(0, 0)
            end
        end)
    end

    tab.Page.Visible = true
    tab.Page.Interactable = true
    tab.Page.Position = UDim2.new(0, direction * 28, 0, 0)
    tab.Page.GroupTransparency = 1

    tween(tab.Page, 0.48, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
        Position = UDim2.fromOffset(0, 0),
        GroupTransparency = 0,
    })
    tween(tab.Button, 0.34, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
        BackgroundTransparency = 0.76,
        TextColor3 = THEME.Text,
    })
    tween(tab.Icon, 0.34, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
        TextColor3 = THEME.Accent,
    })

    task.defer(function()
        if self._destroyed or not tab.Button.Parent then
            return
        end
        local targetY = tab.Button.AbsolutePosition.Y - self.Sidebar.AbsolutePosition.Y
        tween(self.TabIndicator, 0.48, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
            Position = UDim2.fromOffset(10, targetY + 7),
            Size = UDim2.fromOffset(3, math.max(18, tab.Button.AbsoluteSize.Y - 14)),
        })
    end)
end

function Window:CreateTab(config)
    config = config or {}
    local tab = setmetatable({}, Tab)
    tab.Window = self
    tab._index = #self._tabs + 1
    tab._sectionCount = 0

    local button = create("TextButton", {
        Name = tostring(config.Name or "Tab"),
        Size = UDim2.new(1, -8, 0, 42),
        BackgroundColor3 = THEME.Accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = tostring(config.Name or "Tab"),
        TextColor3 = THEME.Muted,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = THEME.FontMedium,
        ZIndex = 12,
        LayoutOrder = tab._index,
        Parent = self.TabList,
    })
    addCorner(button, UDim.new(0, 7))
    addPadding(button, 42, 8, 0, 0)

    local iconText = config.Icon
    if iconText == nil or iconText == "" then
        iconText = string.sub(tostring(config.Name or "T"), 1, 1)
    end

    local icon = create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(-21, 21), -- padding shifts TextButton content; negative offsets compensate
        Size = UDim2.fromOffset(24, 24),
        BackgroundTransparency = 1,
        Text = tostring(iconText),
        TextColor3 = THEME.Muted,
        TextSize = 14,
        Font = THEME.FontBold,
        ZIndex = 13,
        Parent = button,
    })

    -- Because UIPadding also affects child layout, put the icon at the true left
    -- after parenting. This keeps arbitrary text/font icons supported.
    icon.Position = UDim2.fromOffset(-29, 21)

    local page = create("CanvasGroup", {
        Name = tostring(config.Name or "Tab") .. "Page",
        Size = UDim2.fromScale(1, 1),
        Position = UDim2.fromOffset(0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Interactable = false,
        Visible = false,
        ZIndex = 10,
        Parent = self.ContentHolder,
    })

    local scroll = create("ScrollingFrame", {
        Name = "Scroll",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = THEME.Accent,
        ScrollBarImageTransparency = 0.28,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
        ZIndex = 11,
        Parent = page,
    })
    addPadding(scroll, 4, 10, 5, 14)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 12),
        Parent = scroll,
    })

    tab.Button = button
    tab.Icon = icon
    tab.Page = page
    tab.Scroll = scroll
    table.insert(self._tabs, tab)

    self:_bind(button.Activated, function()
        self:_selectTab(tab)
    end)

    self:_bind(button.MouseEnter, function()
        if self._activeTab ~= tab then
            tween(button, 0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
                BackgroundTransparency = 0.9,
                TextColor3 = THEME.Text,
            })
        end
    end)
    self:_bind(button.MouseLeave, function()
        if self._activeTab ~= tab then
            tween(button, 0.26, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
                BackgroundTransparency = 1,
                TextColor3 = THEME.Muted,
            })
        end
    end)

    if tab._index == 1 then
        task.defer(function()
            self:_selectTab(tab)
        end)
    end

    return tab
end

--// Section and control construction -----------------------------------------

function Tab:CreateSection(name)
    self._sectionCount += 1
    local section = setmetatable({}, Section)
    section.Tab = self
    section.Window = self.Window
    section._controlCount = 0

    local frame = create("Frame", {
        Name = tostring(name or "Section"),
        Size = UDim2.new(1, -2, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = THEME.Glass,
        BackgroundTransparency = 0.42,
        BorderSizePixel = 0,
        LayoutOrder = self._sectionCount,
        ZIndex = 12,
        Parent = self.Scroll,
    })
    addCorner(frame, UDim.new(0, 10))
    local frameStroke = addStroke(frame, THEME.Accent, 1, 0.82)
    addAccentGradient(frameStroke, 0)
    addPadding(frame, 10, 10, 10, 12)

    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = frame,
    })

    local titleRow = create("Frame", {
        Name = "SectionHeader",
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = 0,
        ZIndex = 13,
        Parent = frame,
    })

    create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromOffset(0, 12),
        Size = UDim2.fromOffset(3, 14),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        ZIndex = 14,
        Parent = titleRow,
    })

    create("TextLabel", {
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(1, -12, 1, 0),
        BackgroundTransparency = 1,
        Text = string.upper(tostring(name or "SECTION")),
        TextColor3 = THEME.Muted,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = THEME.FontBold,
        ZIndex = 14,
        Parent = titleRow,
    })

    section.Frame = frame
    return section
end

function Section:_nextOrder()
    self._controlCount += 1
    return self._controlCount
end

function Section:_base(name, height)
    local control = create("Frame", {
        Name = tostring(name or "Control"),
        Size = UDim2.new(1, 0, 0, height or 52),
        BackgroundColor3 = THEME.Control,
        BackgroundTransparency = 0.22,
        BorderSizePixel = 0,
        ClipsDescendants = false,
        LayoutOrder = self:_nextOrder(),
        Active = true,
        ZIndex = 14,
        Parent = self.Frame,
    })
    addCorner(control, UDim.new(0, 8))
    local stroke = addStroke(control, THEME.Accent, 1, 0.7)
    local scale = create("UIScale", { Scale = 1, Parent = control })
    return control, stroke, scale
end

function Section:CreateButton(config)
    config = config or {}
    local control, stroke, scale = self:_base(config.Name or "Button", 50)
    control.ClipsDescendants = true

    local button = create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 16,
        Parent = control,
    })

    create("TextLabel", {
        Position = UDim2.fromOffset(16, 0),
        Size = UDim2.new(1, -58, 1, 0),
        BackgroundTransparency = 1,
        Text = tostring(config.Name or "Button"),
        TextColor3 = THEME.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = THEME.FontMedium,
        ZIndex = 17,
        Parent = control,
    })

    local arrow = create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(1, -24, 0.5, 0),
        Size = UDim2.fromOffset(22, 22),
        BackgroundTransparency = 1,
        Text = "›",
        TextColor3 = THEME.Accent,
        TextSize = 24,
        Font = THEME.FontMedium,
        ZIndex = 17,
        Parent = control,
    })

    local lastPointer = Vector2.new(control.AbsolutePosition.X + control.AbsoluteSize.X / 2, control.AbsolutePosition.Y + 25)
    local pointerHovering = false
    self.Window:_bind(button.MouseEnter, function()
        pointerHovering = true
    end)
    self.Window:_bind(button.MouseLeave, function()
        pointerHovering = false
    end)
    self.Window:_bind(button.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            lastPointer = input.Position
            tween(scale, 0.09, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Scale = 0.97 })
        end
    end)
    self.Window:_bind(button.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            local releaseScale = input.UserInputType == Enum.UserInputType.Touch and 1 or (pointerHovering and 1.03 or 1)
            tween(scale, 0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = releaseScale })
        end
    end)
    self.Window:_bind(button.Activated, function()
        makeRipple(control, lastPointer)
        tween(stroke, 0.12, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Transparency = 0.02 })
        tween(arrow, 0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
            Position = UDim2.new(1, -20, 0.5, 0),
        })
        task.delay(0.16, function()
            if control.Parent then
                tween(stroke, 0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, { Transparency = 0.42 })
                tween(arrow, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out, {
                    Position = UDim2.new(1, -24, 0.5, 0),
                })
            end
        end)
        safeCall(config.Callback)
    end)

    installHover(self.Window, control, scale, stroke, 1.03)
    return button
end

function Section:CreateToggle(config)
    config = config or {}
    local control, stroke, scale = self:_base(config.Name or "Toggle", 52)
    local state = config.Default == true

    create("TextLabel", {
        Position = UDim2.fromOffset(16, 0),
        Size = UDim2.new(1, -84, 1, 0),
        BackgroundTransparency = 1,
        Text = tostring(config.Name or "Toggle"),
        TextColor3 = THEME.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = THEME.FontMedium,
        ZIndex = 16,
        Parent = control,
    })

    local track = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = UDim2.fromOffset(46, 24),
        BackgroundColor3 = state and THEME.Accent or Color3.fromRGB(50, 59, 79),
        BackgroundTransparency = state and 0.08 or 0.16,
        BorderSizePixel = 0,
        ZIndex = 17,
        Parent = control,
    })
    addCorner(track, UDim.new(1, 0))
    local trackStroke = addStroke(track, state and THEME.Accent or THEME.Muted, 1, state and 0.2 or 0.7)

    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = state and UDim2.new(1, -21, 0.5, 0) or UDim2.fromOffset(3, 12),
        Size = UDim2.fromOffset(18, 18),
        BackgroundColor3 = state and Color3.new(1, 1, 1) or Color3.fromRGB(185, 196, 214),
        BorderSizePixel = 0,
        ZIndex = 19,
        Parent = track,
    })
    addCorner(knob, UDim.new(1, 0))
    local knobGlow = addSoftGlow(knob, THEME.Accent, UDim.new(1, 0), 18)
    knobGlow.BackgroundTransparency = state and 0.72 or 1

    local click = create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 21,
        Parent = control,
    })

    local api = {}

    local function setState(newState, fireCallback)
        newState = not not newState
        if state == newState and fireCallback then
            return
        end
        state = newState

        tween(track, 0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
            BackgroundColor3 = state and THEME.Accent or Color3.fromRGB(50, 59, 79),
            BackgroundTransparency = state and 0.08 or 0.16,
        })
        tween(trackStroke, 0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
            Color = state and THEME.Accent or THEME.Muted,
            Transparency = state and 0.05 or 0.7,
        })
        tween(knob, 0.48, Enum.EasingStyle.Back, Enum.EasingDirection.Out, {
            Position = state and UDim2.new(1, -21, 0.5, 0) or UDim2.fromOffset(3, 12),
            BackgroundColor3 = state and Color3.new(1, 1, 1) or Color3.fromRGB(185, 196, 214),
        })
        tween(knobGlow, 0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
            BackgroundTransparency = state and 0.56 or 1,
            Size = state and UDim2.new(1, 16, 1, 16) or UDim2.new(1, 10, 1, 10),
        })
        tween(stroke, 0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
            Transparency = state and 0.12 or 0.7,
        })
        task.delay(0.22, function()
            if knobGlow.Parent then
                tween(knobGlow, 0.52, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
                    BackgroundTransparency = state and 0.78 or 1,
                    Size = UDim2.new(1, 12, 1, 12),
                })
                tween(stroke, 0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
                    Transparency = state and 0.46 or 0.7,
                })
            end
        end)

        if fireCallback then
            safeCall(config.Callback, state)
        end
    end

    self.Window:_bind(click.Activated, function()
        setState(not state, true)
    end)
    installHover(self.Window, control, scale, stroke, 1.015)

    function api:Set(value)
        setState(value, true)
    end
    function api:Get()
        return state
    end

    return api
end

function Section:CreateSlider(config)
    config = config or {}
    local minimum = tonumber(config.Min) or 0
    local maximum = tonumber(config.Max) or 100
    if maximum <= minimum then
        maximum = minimum + 1
    end

    local requestedDefault = clamp(tonumber(config.Default) or minimum, minimum, maximum)
    local step = tonumber(config.Step)
    if not step or step <= 0 then
        -- Integer defaults keep the familiar one-unit slider behavior, while a
        -- decimal default automatically preserves hundredth precision.
        if minimum % 1 == 0 and maximum % 1 == 0 and requestedDefault % 1 == 0 then
            step = 1
        else
            step = 0.01
        end
    end

    local function quantize(inputValue)
        local stepIndex = math.floor(((inputValue - minimum) / step) + 0.5)
        return clamp(round(minimum + stepIndex * step, 6), minimum, maximum)
    end

    local value = quantize(requestedDefault)
    local targetAlpha = (value - minimum) / (maximum - minimum)
    local displayAlpha = targetAlpha
    local sliderAnimating = false
    local dragging = false
    local dragInput

    local control, stroke, scale = self:_base(config.Name or "Slider", 72)

    create("TextLabel", {
        Position = UDim2.fromOffset(16, 8),
        Size = UDim2.new(1, -100, 0, 24),
        BackgroundTransparency = 1,
        Text = tostring(config.Name or "Slider"),
        TextColor3 = THEME.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = THEME.FontMedium,
        ZIndex = 16,
        Parent = control,
    })

    local valuePill = create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, 8),
        Size = UDim2.fromOffset(58, 24),
        BackgroundColor3 = THEME.Dark,
        BackgroundTransparency = 0.28,
        BorderSizePixel = 0,
        ZIndex = 17,
        Parent = control,
    })
    addCorner(valuePill, UDim.new(0, 6))
    local valuePillStroke = addStroke(valuePill, THEME.Accent, 1, 0.65)
    local valueScale = create("UIScale", { Scale = 1, Parent = valuePill })

    local valueLabel = create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = formatNumber(value, minimum, maximum, step),
        TextColor3 = THEME.Accent,
        TextSize = 11,
        Font = THEME.FontBold,
        ZIndex = 18,
        Parent = valuePill,
    })

    local track = create("Frame", {
        Position = UDim2.new(0, 16, 1, -22),
        Size = UDim2.new(1, -32, 0, 7),
        BackgroundColor3 = Color3.fromRGB(43, 51, 72),
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Active = true,
        ZIndex = 17,
        Parent = control,
    })
    addCorner(track, UDim.new(1, 0))

    local fill = create("Frame", {
        Size = UDim2.new(displayAlpha, 0, 1, 0),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        ZIndex = 18,
        Parent = track,
    })
    addCorner(fill, UDim.new(1, 0))
    addAccentGradient(fill, 0)

    local fillGlow = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.new(1, 0, 1, 8),
        BackgroundColor3 = THEME.Accent,
        BackgroundTransparency = 0.86,
        BorderSizePixel = 0,
        ZIndex = 16,
        Parent = fill,
    })
    addCorner(fillGlow, UDim.new(1, 0))

    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(displayAlpha, 0, 0.5, 0),
        Size = UDim2.fromOffset(15, 15),
        BackgroundColor3 = THEME.Text,
        BorderSizePixel = 0,
        ZIndex = 20,
        Parent = track,
    })
    addCorner(knob, UDim.new(1, 0))
    local knobStroke = addStroke(knob, THEME.Accent, 2, 0.05)
    local knobScale = create("UIScale", { Scale = 1, Parent = knob })

    local api = {}

    local function setFromAlpha(alpha, fireCallback)
        alpha = clamp(alpha, 0, 1)
        local rawValue = minimum + (maximum - minimum) * alpha
        local newValue = quantize(rawValue)

        -- The visual target follows the committed value, so the fill, label,
        -- callback, and Get() never disagree when a Step is in use.
        targetAlpha = (newValue - minimum) / (maximum - minimum)
        sliderAnimating = true

        if newValue ~= value then
            value = newValue
            valueLabel.Text = formatNumber(value, minimum, maximum, step)
            tween(valueScale, 0.12, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Scale = 1.17 })
            task.delay(0.09, function()
                if valueScale.Parent then
                    tween(valueScale, 0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
                end
            end)
            if fireCallback then
                safeCall(config.Callback, value)
            end
        end
    end

    local function updateFromPosition(position)
        local alpha = (position.X - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X)
        setFromAlpha(alpha, true)
    end

    local function beginDrag(input)
        dragging = true
        dragInput = input
        updateFromPosition(input.Position)
        tween(knobScale, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1.3 })
        tween(knobStroke, 0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Thickness = 3, Transparency = 0 })
        tween(fillGlow, 0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { BackgroundTransparency = 0.64 })
        tween(valuePillStroke, 0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Transparency = 0.12 })
        tween(valueScale, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1.12 })
    end

    local function endDrag()
        if not dragging then
            return
        end
        dragging = false
        dragInput = nil
        tween(knobScale, 0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
        tween(knobStroke, 0.32, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Thickness = 2, Transparency = 0.05 })
        tween(fillGlow, 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, { BackgroundTransparency = 0.86 })
        tween(valuePillStroke, 0.34, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Transparency = 0.65 })
        tween(valueScale, 0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
    end

    self.Window:_bind(track.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            beginDrag(input)
        end
    end)
    self.Window:_bind(UserInputService.InputChanged, function(input)
        if not dragging then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput then
            updateFromPosition(input.Position)
        end
    end)
    self.Window:_bind(UserInputService.InputEnded, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input == dragInput) then
            endDrag()
        end
    end)
    self.Window:_bind(RunService.RenderStepped, function(deltaTime)
        if not sliderAnimating then
            return
        end

        local follow = 1 - math.exp(-deltaTime * (dragging and 24 or 16))
        displayAlpha += (targetAlpha - displayAlpha) * follow
        fill.Size = UDim2.new(displayAlpha, 0, 1, 0)
        knob.Position = UDim2.new(displayAlpha, 0, 0.5, 0)

        if not dragging and math.abs(targetAlpha - displayAlpha) < 0.0001 then
            displayAlpha = targetAlpha
            fill.Size = UDim2.new(displayAlpha, 0, 1, 0)
            knob.Position = UDim2.new(displayAlpha, 0, 0.5, 0)
            sliderAnimating = false
        end
    end)

    installHover(self.Window, control, scale, stroke, 1.01)

    function api:Set(newValue)
        newValue = clamp(tonumber(newValue) or minimum, minimum, maximum)
        setFromAlpha((newValue - minimum) / (maximum - minimum), true)
    end
    function api:Get()
        return value
    end

    return api
end

function Section:CreateDropdown(config)
    config = config or {}
    local options = config.Options or {}
    local isMulti = config.Multi == true
    local selected = isMulti and {} or nil
    local open = false
    local animationToken = 0
    local visibleOptions = math.min(#options, 6)
    local panelHeight = visibleOptions * 36 + 10

    local control, stroke, scale = self:_base(config.Name or "Dropdown", 54)
    control.ClipsDescendants = true

    create("TextLabel", {
        Position = UDim2.fromOffset(15, 6),
        Size = UDim2.new(0.46, -15, 0, 18),
        BackgroundTransparency = 1,
        Text = tostring(config.Name or "Dropdown"),
        TextColor3 = THEME.Muted,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = THEME.FontMedium,
        ZIndex = 17,
        Parent = control,
    })

    local selectionLabel = create("TextLabel", {
        Position = UDim2.fromOffset(15, 23),
        Size = UDim2.new(1, -60, 0, 23),
        BackgroundTransparency = 1,
        Text = "Select...",
        TextColor3 = THEME.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Font = THEME.FontMedium,
        ZIndex = 17,
        Parent = control,
    })

    local arrow = create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(1, -23, 0, 27),
        Size = UDim2.fromOffset(22, 22),
        BackgroundTransparency = 1,
        Text = "⌄",
        TextColor3 = THEME.Accent,
        TextSize = 18,
        Font = THEME.FontBold,
        Rotation = 0,
        ZIndex = 18,
        Parent = control,
    })

    local headerButton = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 54),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 20,
        Parent = control,
    })

    local panel = create("CanvasGroup", {
        Position = UDim2.fromOffset(8, 54),
        Size = UDim2.new(1, -16, 0, 0),
        BackgroundColor3 = THEME.Dark,
        BackgroundTransparency = 0.38,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        ClipsDescendants = true,
        ZIndex = 18,
        Parent = control,
    })
    addCorner(panel, UDim.new(0, 7))
    addStroke(panel, THEME.Accent, 1, 0.76)

    local optionScroll = create("ScrollingFrame", {
        Position = UDim2.fromOffset(5, 5),
        Size = UDim2.new(1, -10, 1, -10),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = #options > 6 and 2 or 0,
        ScrollBarImageColor3 = THEME.Accent,
        ScrollBarImageTransparency = 0.3,
        ZIndex = 19,
        Parent = panel,
    })
    create("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = optionScroll,
    })

    local optionVisuals = {}
    local api = {}

    local function selectedArray()
        local result = {}
        for _, option in ipairs(options) do
            if selected[option] then
                table.insert(result, option)
            end
        end
        return result
    end

    local function refreshLabel()
        if isMulti then
            local list = selectedArray()
            local labels = {}
            for index, option in ipairs(list) do
                labels[index] = tostring(option)
            end
            selectionLabel.Text = #labels > 0 and table.concat(labels, ", ") or "Select..."
        else
            selectionLabel.Text = selected ~= nil and tostring(selected) or "Select..."
        end
    end

    local function refreshOptions()
        for _, visual in ipairs(optionVisuals) do
            local option = visual.Value
            local active = isMulti and selected[option] == true or selected == option
            tween(visual.Button, 0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
                BackgroundTransparency = active and 0.78 or 1,
                TextColor3 = active and THEME.Text or THEME.Muted,
            })
            tween(visual.Mark, 0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out, {
                Size = active and UDim2.fromOffset(7, 7) or UDim2.fromOffset(0, 0),
                BackgroundTransparency = active and 0 or 1,
            })
        end
    end

    local function setOpen(newOpen)
        if open == newOpen then
            return
        end
        open = newOpen
        animationToken += 1
        local token = animationToken
        local targetHeight = open and (54 + panelHeight + 8) or 54

        tween(control, open and 0.46 or 0.38, open and Enum.EasingStyle.Back or Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
            Size = UDim2.new(1, 0, 0, targetHeight),
        })
        tween(panel, 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
            Size = UDim2.new(1, -16, 0, open and panelHeight or 0),
            GroupTransparency = open and 0 or 1,
        })
        tween(arrow, 0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out, {
            Rotation = open and 180 or 0,
        })
        tween(stroke, 0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
            Transparency = open and 0.28 or 0.7,
        })

        if open then
            for index, visual in ipairs(optionVisuals) do
                visual.Group.Position = UDim2.fromOffset(18, 0)
                visual.Group.GroupTransparency = 1
                task.delay((index - 1) * 0.045, function()
                    if token == animationToken and open and visual.Group.Parent then
                        tween(visual.Group, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
                            Position = UDim2.fromOffset(0, 0),
                            GroupTransparency = 0,
                        })
                    end
                end)
            end
        end
    end

    local function buildOptions()
        for _, child in ipairs(optionScroll:GetChildren()) do
            if not child:IsA("UIListLayout") then
                child:Destroy()
            end
        end
        table.clear(optionVisuals)
        visibleOptions = math.min(#options, 6)
        panelHeight = visibleOptions * 36 + 10
        optionScroll.ScrollBarThickness = #options > 6 and 2 or 0

        for index, rawOption in ipairs(options) do
            local option = rawOption
            local group = create("CanvasGroup", {
                Size = UDim2.new(1, -2, 0, 32),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                GroupTransparency = 1,
                LayoutOrder = index,
                ZIndex = 20,
                Parent = optionScroll,
            })

            local optionButton = create("TextButton", {
                Size = UDim2.fromScale(1, 1),
                BackgroundColor3 = THEME.Accent,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Text = tostring(option),
                TextColor3 = THEME.Muted,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                Font = THEME.FontMedium,
                AutoButtonColor = false,
                ZIndex = 21,
                Parent = group,
            })
            addCorner(optionButton, UDim.new(0, 6))
            addPadding(optionButton, 28, 8, 0, 0)

            local mark = create("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromOffset(-14, 16),
                Size = UDim2.fromOffset(0, 0),
                BackgroundColor3 = THEME.Accent,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ZIndex = 23,
                Parent = optionButton,
            })
            addCorner(mark, UDim.new(1, 0))

            table.insert(optionVisuals, {
                Value = option,
                Group = group,
                Button = optionButton,
                Mark = mark,
            })

            self.Window:_bind(optionButton.MouseEnter, function()
                tween(optionButton, 0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
                    BackgroundTransparency = 0.88,
                    TextColor3 = THEME.Text,
                })
            end)
            self.Window:_bind(optionButton.MouseLeave, refreshOptions)
            self.Window:_bind(optionButton.Activated, function()
                if isMulti then
                    selected[option] = not selected[option]
                    refreshLabel()
                    refreshOptions()
                    safeCall(config.Callback, selectedArray())
                else
                    selected = option
                    refreshLabel()
                    refreshOptions()
                    safeCall(config.Callback, option)
                    setOpen(false)
                end
            end)
        end

        refreshLabel()
        refreshOptions()

        -- SetOptions may rebuild while expanded; replacement rows must remain
        -- visible instead of inheriting their stagger-animation start state.
        if open then
            for _, visual in ipairs(optionVisuals) do
                visual.Group.Position = UDim2.fromOffset(0, 0)
                visual.Group.GroupTransparency = 0
            end
        end
    end

    self.Window:_bind(headerButton.Activated, function()
        setOpen(not open)
    end)
    installHover(self.Window, control, scale, stroke, 1.008)
    buildOptions()

    function api:Set(value)
        if isMulti then
            table.clear(selected)
            if type(value) == "table" then
                for _, item in ipairs(value) do
                    selected[item] = true
                end
            end
            refreshLabel()
            refreshOptions()
            safeCall(config.Callback, selectedArray())
        else
            selected = value
            refreshLabel()
            refreshOptions()
            safeCall(config.Callback, selected)
        end
    end

    function api:Get()
        return isMulti and selectedArray() or selected
    end

    function api:SetOptions(newOptions)
        options = newOptions or {}
        selected = isMulti and {} or nil
        buildOptions()
        if open then
            control.Size = UDim2.new(1, 0, 0, 54 + panelHeight + 8)
            panel.Size = UDim2.new(1, -16, 0, panelHeight)
        end
    end

    return api
end

function Section:CreateTextbox(config)
    config = config or {}
    local control, stroke, scale = self:_base(config.Name or "Textbox", 58)

    create("TextLabel", {
        Position = UDim2.fromOffset(15, 0),
        Size = UDim2.new(0.38, -15, 1, 0),
        BackgroundTransparency = 1,
        Text = tostring(config.Name or "Textbox"),
        TextColor3 = THEME.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Font = THEME.FontMedium,
        ZIndex = 16,
        Parent = control,
    })

    local inputFrame = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.new(0.6, 0, 0, 34),
        BackgroundColor3 = THEME.Dark,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        ZIndex = 17,
        Parent = control,
    })
    addCorner(inputFrame, UDim.new(0, 7))
    local inputStroke = addStroke(inputFrame, THEME.Accent, 1, 0.7)

    local textBox = create("TextBox", {
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -20, 1, 0),
        BackgroundTransparency = 1,
        ClearTextOnFocus = false,
        MultiLine = false,
        Text = tostring(config.Default or ""),
        PlaceholderText = tostring(config.Placeholder or "Type here..."),
        PlaceholderColor3 = THEME.Muted,
        TextColor3 = THEME.Text,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = THEME.Font,
        ZIndex = 18,
        Parent = inputFrame,
    })

    self.Window:_bind(textBox.Focused, function()
        tween(inputStroke, 0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
            Transparency = 0.08,
            Thickness = 1.5,
        })
        tween(inputFrame, 0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
            BackgroundTransparency = 0.12,
        })
        tween(scale, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1.01 })
    end)
    self.Window:_bind(textBox.FocusLost, function(enterPressed)
        tween(inputStroke, 0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
            Transparency = 0.7,
            Thickness = 1,
        })
        tween(inputFrame, 0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
            BackgroundTransparency = 0.3,
        })
        tween(scale, 0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Scale = 1 })
        safeCall(config.Callback, textBox.Text, enterPressed)
    end)

    installHover(self.Window, control, scale, stroke, 1.008)

    return {
        Set = function(_, text)
            textBox.Text = tostring(text or "")
        end,
        Get = function()
            return textBox.Text
        end,
        Focus = function()
            textBox:CaptureFocus()
        end,
    }
end

function Section:CreateKeybind(config)
    config = config or {}
    local control, stroke, scale = self:_base(config.Name or "Keybind", 52)
    local boundKey = typeof(config.Default) == "EnumItem" and config.Default or Enum.KeyCode.Unknown
    local listening = false

    create("TextLabel", {
        Position = UDim2.fromOffset(15, 0),
        Size = UDim2.new(1, -126, 1, 0),
        BackgroundTransparency = 1,
        Text = tostring(config.Name or "Keybind"),
        TextColor3 = THEME.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = THEME.FontMedium,
        ZIndex = 16,
        Parent = control,
    })

    local keyPill = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(98, 30),
        BackgroundColor3 = THEME.Dark,
        BackgroundTransparency = 0.24,
        BorderSizePixel = 0,
        Text = boundKey == Enum.KeyCode.Unknown and "UNBOUND" or keyName(boundKey),
        TextColor3 = THEME.Accent,
        TextSize = 10,
        Font = THEME.FontBold,
        AutoButtonColor = false,
        ZIndex = 18,
        Parent = control,
    })
    addCorner(keyPill, UDim.new(0, 7))
    local keyStroke = addStroke(keyPill, THEME.Accent, 1, 0.62)

    self.Window:_bind(keyPill.Activated, function()
        listening = true
        Haze._capturingKeybind = true
        keyPill.Text = "PRESS A KEY"
        tween(keyStroke, 0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
            Transparency = 0.05,
            Thickness = 1.5,
        })
        tween(scale, 0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1.012 })
    end)

    self.Window:_bind(UserInputService.InputBegan, function(input, gameProcessed)
        if listening then
            if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Unknown then
                listening = false
                Haze._capturingKeybind = false

                if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Haze.ToggleKey then
                    boundKey = Enum.KeyCode.Unknown
                    keyPill.Text = input.KeyCode == Haze.ToggleKey and "RESERVED" or "UNBOUND"
                    if input.KeyCode == Haze.ToggleKey then
                        task.delay(0.75, function()
                            if keyPill.Parent and boundKey == Enum.KeyCode.Unknown then
                                keyPill.Text = "UNBOUND"
                            end
                        end)
                    end
                else
                    boundKey = input.KeyCode
                    keyPill.Text = keyName(boundKey)
                end

                tween(keyStroke, 0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
                    Transparency = 0.62,
                    Thickness = 1,
                })
                tween(scale, 0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
            end
            return
        end

        if not gameProcessed and boundKey ~= Enum.KeyCode.Unknown and input.KeyCode == boundKey then
            tween(keyStroke, 0.12, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Transparency = 0 })
            task.delay(0.14, function()
                if keyStroke.Parent then
                    tween(keyStroke, 0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Transparency = 0.62 })
                end
            end)
            safeCall(config.Callback, boundKey)
        end
    end)

    installHover(self.Window, control, scale, stroke, 1.008)

    return {
        Set = function(_, keyCode)
            if typeof(keyCode) == "EnumItem" and keyCode ~= Haze.ToggleKey then
                boundKey = keyCode
                keyPill.Text = keyName(boundKey)
            end
        end,
        Get = function()
            return boundKey
        end,
    }
end

function Section:CreateColorPicker(config)
    config = config or {}
    local initialColor = typeof(config.Default) == "Color3" and config.Default or THEME.Accent
    local hue, saturation, brightness = Color3.toHSV(initialColor)
    local currentColor = initialColor
    local open = false
    local draggingSV = false
    local draggingHue = false
    local activeInput
    local expandedHeight = 222

    local control, stroke, scale = self:_base(config.Name or "Color Picker", 56)
    control.ClipsDescendants = true

    create("TextLabel", {
        Position = UDim2.fromOffset(15, 0),
        Size = UDim2.new(1, -150, 0, 56),
        BackgroundTransparency = 1,
        Text = tostring(config.Name or "Color Picker"),
        TextColor3 = THEME.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = THEME.FontMedium,
        ZIndex = 16,
        Parent = control,
    })

    local hexLabel = create("TextLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -52, 0, 28),
        Size = UDim2.fromOffset(74, 24),
        BackgroundTransparency = 1,
        Text = colorToHex(currentColor),
        TextColor3 = THEME.Muted,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Right,
        Font = THEME.FontMedium,
        ZIndex = 17,
        Parent = control,
    })

    local swatch = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0, 28),
        Size = UDim2.fromOffset(28, 28),
        BackgroundColor3 = currentColor,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 18,
        Parent = control,
    })
    addCorner(swatch, UDim.new(0, 7))
    local swatchStroke = addStroke(swatch, Color3.new(1, 1, 1), 1, 0.28)
    local swatchGlow = addSoftGlow(swatch, currentColor, UDim.new(0, 9), 17)
    swatchGlow.BackgroundTransparency = 0.82

    local picker = create("CanvasGroup", {
        Position = UDim2.fromOffset(10, 58),
        Size = UDim2.new(1, -20, 0, 154),
        BackgroundColor3 = THEME.Dark,
        BackgroundTransparency = 0.38,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Visible = false,
        ZIndex = 17,
        Parent = control,
    })
    addCorner(picker, UDim.new(0, 8))
    addStroke(picker, THEME.Accent, 1, 0.78)

    local sv = create("Frame", {
        Position = UDim2.fromOffset(10, 10),
        Size = UDim2.new(1, -42, 1, -20),
        BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
        BorderSizePixel = 0,
        Active = true,
        ClipsDescendants = true,
        ZIndex = 19,
        Parent = picker,
    })
    addCorner(sv, UDim.new(0, 6))

    local whiteLayer = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        ZIndex = 20,
        Parent = sv,
    })
    create("UIGradient", {
        Color = ColorSequence.new(Color3.new(1, 1, 1)),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Rotation = 0,
        Parent = whiteLayer,
    })

    local blackLayer = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BorderSizePixel = 0,
        ZIndex = 21,
        Parent = sv,
    })
    create("UIGradient", {
        Color = ColorSequence.new(Color3.new(0, 0, 0)),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Rotation = 90,
        Parent = blackLayer,
    })

    local svCursor = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(saturation, 1 - brightness),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = currentColor,
        BackgroundTransparency = 0.18,
        BorderSizePixel = 0,
        ZIndex = 24,
        Parent = sv,
    })
    addCorner(svCursor, UDim.new(1, 0))
    addStroke(svCursor, Color3.new(1, 1, 1), 2, 0)

    local hueBar = create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 10),
        Size = UDim2.fromOffset(18, 134),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Active = true,
        ZIndex = 20,
        Parent = picker,
    })
    addCorner(hueBar, UDim.new(1, 0))
    create("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
            ColorSequenceKeypoint.new(1 / 6, Color3.fromHSV(1 / 6, 1, 1)),
            ColorSequenceKeypoint.new(2 / 6, Color3.fromHSV(2 / 6, 1, 1)),
            ColorSequenceKeypoint.new(3 / 6, Color3.fromHSV(3 / 6, 1, 1)),
            ColorSequenceKeypoint.new(4 / 6, Color3.fromHSV(4 / 6, 1, 1)),
            ColorSequenceKeypoint.new(5 / 6, Color3.fromHSV(5 / 6, 1, 1)),
            ColorSequenceKeypoint.new(1, Color3.fromHSV(1, 1, 1)),
        }),
        Parent = hueBar,
    })

    local hueCursor = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, hue),
        Size = UDim2.fromOffset(24, 5),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        ZIndex = 23,
        Parent = hueBar,
    })
    addCorner(hueCursor, UDim.new(1, 0))
    addStroke(hueCursor, THEME.Dark, 1, 0.1)

    local api = {}

    local function updateColor(fireCallback)
        currentColor = Color3.fromHSV(hue, saturation, brightness)
        sv.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
        svCursor.Position = UDim2.fromScale(saturation, 1 - brightness)
        svCursor.BackgroundColor3 = currentColor
        hueCursor.Position = UDim2.fromScale(0.5, hue)
        swatch.BackgroundColor3 = currentColor
        swatchGlow.BackgroundColor3 = currentColor
        hexLabel.Text = colorToHex(currentColor)
        if fireCallback then
            safeCall(config.Callback, currentColor)
        end
    end

    local function updateSV(position)
        saturation = clamp((position.X - sv.AbsolutePosition.X) / math.max(1, sv.AbsoluteSize.X), 0, 1)
        brightness = 1 - clamp((position.Y - sv.AbsolutePosition.Y) / math.max(1, sv.AbsoluteSize.Y), 0, 1)
        updateColor(true)
    end

    local function updateHue(position)
        hue = clamp((position.Y - hueBar.AbsolutePosition.Y) / math.max(1, hueBar.AbsoluteSize.Y), 0, 1)
        updateColor(true)
    end

    local function setOpen(newOpen)
        open = newOpen
        if open then
            picker.Visible = true
            picker.GroupTransparency = 1
            picker.Position = UDim2.fromOffset(10, 68)
            tween(control, 0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out, {
                Size = UDim2.new(1, 0, 0, expandedHeight),
            })
            tween(picker, 0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
                GroupTransparency = 0,
                Position = UDim2.fromOffset(10, 58),
            })
            tween(stroke, 0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Transparency = 0.28 })
            tween(swatchGlow, 0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
                BackgroundTransparency = 0.66,
                Size = UDim2.new(1, 16, 1, 16),
            })
        else
            tween(control, 0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
                Size = UDim2.new(1, 0, 0, 56),
            })
            local fade = tween(picker, 0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In, {
                GroupTransparency = 1,
                Position = UDim2.fromOffset(10, 65),
            })
            fade.Completed:Connect(function()
                if not open and picker.Parent then
                    picker.Visible = false
                end
            end)
            tween(stroke, 0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Transparency = 0.7 })
            tween(swatchGlow, 0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
                BackgroundTransparency = 0.82,
                Size = UDim2.new(1, 14, 1, 14),
            })
        end
    end

    self.Window:_bind(swatch.Activated, function()
        setOpen(not open)
    end)
    self.Window:_bind(sv.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSV = true
            activeInput = input
            updateSV(input.Position)
            tween(svCursor, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Size = UDim2.fromOffset(17, 17) })
        end
    end)
    self.Window:_bind(hueBar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingHue = true
            activeInput = input
            updateHue(input.Position)
            tween(hueCursor, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Size = UDim2.fromOffset(28, 7) })
        end
    end)
    self.Window:_bind(UserInputService.InputChanged, function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input == activeInput then
            if draggingSV then
                updateSV(input.Position)
            elseif draggingHue then
                updateHue(input.Position)
            end
        end
    end)
    self.Window:_bind(UserInputService.InputEnded, function(input)
        if input == activeInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingSV = false
            draggingHue = false
            activeInput = nil
            tween(svCursor, 0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Size = UDim2.fromOffset(12, 12) })
            tween(hueCursor, 0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Size = UDim2.fromOffset(24, 5) })
        end
    end)

    installHover(self.Window, control, scale, stroke, 1.006)

    function api:Set(color)
        if typeof(color) ~= "Color3" then
            return
        end
        hue, saturation, brightness = Color3.toHSV(color)
        updateColor(true)
    end
    function api:Get()
        return currentColor
    end

    return api
end

function Section:CreateLabel(text)
    local control, stroke = self:_base("Label", 0)
    control.AutomaticSize = Enum.AutomaticSize.Y
    control.BackgroundTransparency = 0.52
    stroke.Transparency = 0.86

    local label = create("TextLabel", {
        Position = UDim2.fromOffset(14, 11),
        Size = UDim2.new(1, -28, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Text = tostring(text or "Label"),
        TextColor3 = THEME.Muted,
        TextSize = 12,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Font = THEME.Font,
        ZIndex = 16,
        Parent = control,
    })
    create("UIPadding", {
        PaddingBottom = UDim.new(0, 11),
        Parent = label,
    })

    local api = {}
    function api:Set(newText)
        label.Text = tostring(newText or "")
    end
    function api:Get()
        return label.Text
    end
    return api
end

--// Public window constructor -------------------------------------------------

function Haze:CreateWindow(config)
    config = config or {}

    -- Accent is one library-wide variable by design. The first live window
    -- establishes it; additional windows share that accent so existing hover
    -- handlers and newly created controls can never drift into mixed themes.
    local hasLiveWindow = false
    for _, liveWindow in ipairs(self._windows) do
        if not liveWindow._destroyed and not liveWindow._closing then
            hasLiveWindow = true
            break
        end
    end

    if not hasLiveWindow then
        THEME.Accent = typeof(config.Accent) == "Color3" and config.Accent or DEFAULT_ACCENT
    elseif typeof(config.Accent) == "Color3" and config.Accent ~= THEME.Accent then
        warn("[Haze UI] Additional windows share the accent selected by the first live window.")
    end

    local window = setmetatable({}, Window)
    window._connections = {}
    window._tabs = {}
    window._activeTab = nil
    window._tabSwitchToken = 0
    window._visible = Haze._uiVisible
    window._opened = false
    window._closing = false
    window._destroyed = false
    window._dragging = false
    window._borderOpening = false
    window._borderLoop = nil

    local main = create("CanvasGroup", {
        Name = "HazeWindow_" .. HttpService:GenerateGUID(false),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = normalizeSize(config.Size),
        BackgroundColor3 = THEME.Glass,
        BackgroundTransparency = 0.04,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        ClipsDescendants = false,
        Visible = false,
        ZIndex = 5,
        Parent = WindowLayer,
    })
    addCorner(main, UDim.new(0, 11))

    local scale = create("UIScale", {
        Scale = 0,
        Parent = main,
    })

    -- Layered frame shadows create a soft glass silhouette without an asset.
    for index = 1, 4 do
        local shadow = create("Frame", {
            Name = "Shadow" .. index,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 3 + index * 2),
            Size = UDim2.new(1, 8 + index * 6, 1, 8 + index * 6),
            BackgroundColor3 = index % 2 == 0 and THEME.AccentB or THEME.Accent,
            BackgroundTransparency = 0.94 + index * 0.01,
            BorderSizePixel = 0,
            ZIndex = 1,
            Parent = main,
        })
        addCorner(shadow, UDim.new(0, 14 + index * 2))
    end

    local backgroundGradient = create("UIGradient", {
        Rotation = 125,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 31, 51)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(10, 13, 25)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(27, 15, 38)),
        }),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.05),
            NumberSequenceKeypoint.new(0.5, 0.16),
            NumberSequenceKeypoint.new(1, 0.08),
        }),
        Parent = main,
    })

    local border = addStroke(main, Color3.new(1, 1, 1), 1.6, 1)
    local borderGradient = addAccentGradient(border, -180)

    -- Static grid plus an animated scanline gives the panel its holographic HUD.
    local grid = create("Frame", {
        Name = "HolographicGrid",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 3,
        Parent = main,
    })
    for x = 0, 900, 36 do
        create("Frame", {
            Position = UDim2.fromOffset(x, 0),
            Size = UDim2.new(0, 1, 1, 0),
            BackgroundColor3 = THEME.Accent,
            BackgroundTransparency = 0.975,
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = grid,
        })
    end
    for y = 0, 650, 28 do
        create("Frame", {
            Position = UDim2.fromOffset(0, y),
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = THEME.AccentB,
            BackgroundTransparency = 0.978,
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = grid,
        })
    end

    local scanline = create("Frame", {
        Position = UDim2.new(0, 0, 0, -3),
        Size = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = THEME.Accent,
        BackgroundTransparency = 0.9,
        BorderSizePixel = 0,
        ZIndex = 4,
        Parent = grid,
    })
    addAccentGradient(scanline, 0)
    tween(scanline, 5.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, {
        Position = UDim2.new(0, 0, 1, 3),
    }, -1, false, 0.8)

    local topBar = create("Frame", {
        Name = "TopBar",
        Size = UDim2.new(1, 0, 0, 64),
        BackgroundColor3 = THEME.Dark,
        BackgroundTransparency = 0.42,
        BorderSizePixel = 0,
        Active = true,
        ZIndex = 8,
        Parent = main,
    })
    addCorner(topBar, UDim.new(0, 11))

    -- Covers the lower rounded top-bar corners so the divider remains straight.
    create("Frame", {
        Position = UDim2.new(0, 0, 1, -11),
        Size = UDim2.new(1, 0, 0, 11),
        BackgroundColor3 = THEME.Dark,
        BackgroundTransparency = 0.42,
        BorderSizePixel = 0,
        ZIndex = 8,
        Parent = topBar,
    })

    create("Frame", {
        Position = UDim2.new(0, 0, 1, -1),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = THEME.Accent,
        BackgroundTransparency = 0.74,
        BorderSizePixel = 0,
        ZIndex = 9,
        Parent = topBar,
    })

    local brandPip = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromOffset(18, 32),
        Size = UDim2.fromOffset(28, 28),
        BackgroundColor3 = THEME.Accent,
        BackgroundTransparency = 0.08,
        BorderSizePixel = 0,
        Rotation = 45,
        ZIndex = 10,
        Parent = topBar,
    })
    addCorner(brandPip, UDim.new(0, 7))
    addAccentGradient(brandPip, 45)
    addSoftGlow(brandPip, THEME.Accent, UDim.new(0, 9), 9).BackgroundTransparency = 0.8

    create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "H",
        TextColor3 = THEME.Dark,
        TextSize = 13,
        Font = THEME.FontBlack,
        Rotation = -45,
        ZIndex = 12,
        Parent = brandPip,
    })

    create("TextLabel", {
        Position = UDim2.fromOffset(58, 11),
        Size = UDim2.new(1, -180, 0, 25),
        BackgroundTransparency = 1,
        Text = tostring(config.Title or "Haze"),
        TextColor3 = THEME.Text,
        TextSize = 17,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Font = THEME.FontBold,
        ZIndex = 10,
        Parent = topBar,
    })

    create("TextLabel", {
        Position = UDim2.fromOffset(59, 35),
        Size = UDim2.new(1, -180, 0, 16),
        BackgroundTransparency = 1,
        Text = "HOLOGRAPHIC INTERFACE  /  HAZE",
        TextColor3 = THEME.Muted,
        TextSize = 8,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = THEME.FontBold,
        ZIndex = 10,
        Parent = topBar,
    })

    local minimize = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -52, 0.5, 0),
        Size = UDim2.fromOffset(30, 30),
        BackgroundColor3 = THEME.Control,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Text = "—",
        TextColor3 = THEME.Muted,
        TextSize = 13,
        Font = THEME.FontBold,
        AutoButtonColor = false,
        ZIndex = 12,
        Parent = topBar,
    })
    addCorner(minimize, UDim.new(0, 7))
    local minimizeStroke = addStroke(minimize, THEME.Accent, 1, 0.78)

    local close = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = UDim2.fromOffset(30, 30),
        BackgroundColor3 = THEME.Danger,
        BackgroundTransparency = 0.86,
        BorderSizePixel = 0,
        Text = "×",
        TextColor3 = THEME.Text,
        TextSize = 18,
        Font = THEME.FontMedium,
        AutoButtonColor = false,
        ZIndex = 12,
        Parent = topBar,
    })
    addCorner(close, UDim.new(0, 7))
    local closeStroke = addStroke(close, THEME.Danger, 1, 0.62)

    local sidebar = create("Frame", {
        Name = "Sidebar",
        Position = UDim2.fromOffset(0, 64),
        Size = UDim2.new(0, 184, 1, -64),
        BackgroundColor3 = THEME.Dark,
        BackgroundTransparency = 0.6,
        BorderSizePixel = 0,
        ZIndex = 7,
        Parent = main,
    })

    create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0, 1, 1, 0),
        BackgroundColor3 = THEME.Accent,
        BackgroundTransparency = 0.84,
        BorderSizePixel = 0,
        ZIndex = 8,
        Parent = sidebar,
    })

    create("TextLabel", {
        Position = UDim2.fromOffset(16, 15),
        Size = UDim2.new(1, -32, 0, 18),
        BackgroundTransparency = 1,
        Text = "NAVIGATION",
        TextColor3 = THEME.Muted,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = THEME.FontBold,
        ZIndex = 9,
        Parent = sidebar,
    })

    local tabList = create("Frame", {
        Position = UDim2.fromOffset(10, 42),
        Size = UDim2.new(1, -20, 1, -96),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 9,
        Parent = sidebar,
    })
    create("UIListLayout", {
        Padding = UDim.new(0, 5),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = tabList,
    })

    -- The indicator is an overlay sibling, not a UIListLayout child, so its
    -- position tween remains authoritative.
    local tabIndicator = create("Frame", {
        Position = UDim2.fromOffset(10, 49),
        Size = UDim2.fromOffset(3, 28),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        ZIndex = 14,
        Parent = sidebar,
    })
    addCorner(tabIndicator, UDim.new(1, 0))
    addSoftGlow(tabIndicator, THEME.Accent, UDim.new(1, 0), 13).BackgroundTransparency = 0.72

    create("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -14),
        Size = UDim2.new(1, -26, 0, 28),
        BackgroundTransparency = 1,
        Text = "RIGHTSHIFT  ·  TOGGLE UI",
        TextColor3 = THEME.Muted,
        TextTransparency = 0.28,
        TextSize = 8,
        Font = THEME.FontBold,
        ZIndex = 9,
        Parent = sidebar,
    })

    local contentHolder = create("Frame", {
        Name = "Content",
        Position = UDim2.fromOffset(194, 74),
        Size = UDim2.new(1, -204, 1, -84),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 9,
        Parent = main,
    })

    window.Main = main
    window.Scale = scale
    window.Border = border
    window.BorderGradient = borderGradient
    window.BackgroundGradient = backgroundGradient
    window.TopBar = topBar
    window.Sidebar = sidebar
    window.TabList = tabList
    window.TabIndicator = tabIndicator
    window.ContentHolder = contentHolder

    -- Smooth, framerate-independent drag interpolation for mouse and touch.
    local dragStart
    local startPosition
    local dragInput
    local targetPosition = main.Position

    window:_bind(topBar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            window._dragging = true
            dragStart = input.Position
            startPosition = main.Position
            dragInput = input
        end
    end)

    window:_bind(topBar.InputChanged, function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    window:_bind(UserInputService.InputChanged, function(input)
        if window._dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement) then
            local delta = input.Position - dragStart
            targetPosition = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end)

    window:_bind(UserInputService.InputEnded, function(input)
        if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
            window._dragging = false
        end
    end)

    window:_bind(RunService.RenderStepped, function(deltaTime)
        if main.Parent and (window._dragging or main.Position ~= targetPosition) then
            local alpha = 1 - math.exp(-deltaTime * 20)
            main.Position = main.Position:Lerp(targetPosition, alpha)
        end
    end)

    window:_bind(close.MouseEnter, function()
        tween(close, 0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { BackgroundTransparency = 0.58 })
        tween(closeStroke, 0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Transparency = 0.1 })
    end)
    window:_bind(close.MouseLeave, function()
        tween(close, 0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { BackgroundTransparency = 0.86 })
        tween(closeStroke, 0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Transparency = 0.62 })
    end)
    window:_bind(close.Activated, function()
        window:Close()
    end)

    window:_bind(minimize.MouseEnter, function()
        tween(minimize, 0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { BackgroundTransparency = 0.24 })
        tween(minimizeStroke, 0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Transparency = 0.3 })
    end)
    window:_bind(minimize.MouseLeave, function()
        tween(minimize, 0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { BackgroundTransparency = 0.5 })
        tween(minimizeStroke, 0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Transparency = 0.78 })
    end)
    window:_bind(minimize.Activated, function()
        Haze:SetVisible(false)
    end)

    table.insert(self._windows, window)

    -- If require() happened moments ago, this queues the main window behind the
    -- cinematic sequence. Later windows simply use the normal open animation.
    playIntro(function()
        if not window._destroyed then
            window:_open()
        end
    end)

    return window
end

-- One visibility source of truth covers windows, notifications, and an intro
-- that may still be playing when RightShift is pressed.
function Haze:SetVisible(isVisible)
    self._uiVisible = not not isVisible
    NotificationLayer.Visible = self._uiVisible

    if self._introObject and self._introObject.Parent then
        self._introObject.Visible = self._uiVisible
    end

    for _, window in ipairs(self._windows) do
        window:SetVisible(self._uiVisible)
    end
end

-- Global visibility keybind. It is suspended while a component is capturing a
-- key, and RightShift itself is reserved from component keybinds.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or Haze._capturingKeybind or input.KeyCode ~= Haze.ToggleKey then
        return
    end

    Haze:SetVisible(not Haze._uiVisible)
end)

-- Start the boot sequence as soon as the ModuleScript is required. A window
-- created immediately after require() is queued and opens when the splash ends.
playIntro()

--[[
    ===========================================================================
    COMPLETE EXAMPLE (place this in a LocalScript; keep the library above in a
    ModuleScript named "HazeUILibrary" beside it)
    ===========================================================================

    local Haze = require(script.Parent.HazeUILibrary)

    local Window = Haze:CreateWindow({
        Title = "Haze Control Deck",
        Size = UDim2.fromOffset(780, 530),
        Accent = Color3.fromRGB(0, 229, 255), -- Change your accent here.
    })

    local MainTab = Window:CreateTab({
        Name = "Main",
        Icon = "◆", -- Font glyphs work without external icon assets.
    })

    local PlayerSection = MainTab:CreateSection("Player Controls")

    PlayerSection:CreateLabel(
        "Every control is animated, touch-ready, and styled with the Haze holographic glass theme."
    )

    PlayerSection:CreateButton({
        Name = "Launch Sequence",
        Callback = function()
            Haze:Notify({
                Title = "Sequence Started",
                Text = "The launch button callback fired successfully.",
                Duration = 4,
            })
        end,
    })

    local Toggle = PlayerSection:CreateToggle({
        Name = "Neon Overdrive",
        Default = true,
        Callback = function(enabled)
            print("Neon Overdrive:", enabled)
        end,
    })

    local Slider = PlayerSection:CreateSlider({
        Name = "Walk Speed",
        Min = 8,
        Max = 100,
        Default = 16,
        Callback = function(value)
            local player = game:GetService("Players").LocalPlayer
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid.WalkSpeed = value
            end
        end,
    })

    local Dropdown = PlayerSection:CreateDropdown({
        Name = "Target Zone",
        Options = { "Alpha District", "Neon Harbor", "Void Sector", "Skyline" },
        Multi = false,
        Callback = function(option)
            print("Selected zone:", option)
        end,
    })

    local MultiDropdown = PlayerSection:CreateDropdown({
        Name = "Active Modules",
        Options = { "ESP", "Movement", "Automation", "Visuals", "Utility" },
        Multi = true,
        Callback = function(options)
            print("Active modules:", table.concat(options, ", "))
        end,
    })

    PlayerSection:CreateTextbox({
        Name = "Callsign",
        Placeholder = "Enter a callsign...",
        Callback = function(text, enterPressed)
            print("Callsign:", text, "Submitted with Enter:", enterPressed)
        end,
    })

    PlayerSection:CreateKeybind({
        Name = "Pulse Ability",
        Default = Enum.KeyCode.Q,
        Callback = function(key)
            print("Pulse fired with:", key.Name)
        end,
    })

    PlayerSection:CreateColorPicker({
        Name = "Tracer Color",
        Default = Color3.fromRGB(255, 46, 151),
        Callback = function(color)
            print("Tracer color:", color)
        end,
    })

    local VisualsTab = Window:CreateTab({
        Name = "Visuals",
        Icon = "◈",
    })

    local VisualSection = VisualsTab:CreateSection("Interface")
    VisualSection:CreateToggle({
        Name = "Ambient Grid",
        Default = true,
        Callback = function(enabled)
            print("Ambient Grid:", enabled)
        end,
    })

    VisualSection:CreateSlider({
        Name = "Bloom Intensity",
        Min = 0,
        Max = 2,
        Default = 0.65,
        Callback = function(value)
            print("Bloom:", value)
        end,
    })

    local SettingsTab = Window:CreateTab({
        Name = "Settings",
        Icon = "⚙",
    })

    local SettingsSection = SettingsTab:CreateSection("Haze")
    SettingsSection:CreateLabel("Press RightShift at any time to hide or show Haze UI.")
    SettingsSection:CreateButton({
        Name = "Show Test Notification",
        Callback = function()
            Haze:Notify({
                Title = "Haze UI Library",
                Text = "Holographic systems are online.",
                Duration = 5,
            })
        end,
    })

    -- Returned component controllers can be changed later:
    -- Toggle:Set(false)
    -- Slider:Set(50)
    -- Dropdown:Set("Void Sector")
    -- MultiDropdown:Set({ "ESP", "Utility" })
]]

return Haze
