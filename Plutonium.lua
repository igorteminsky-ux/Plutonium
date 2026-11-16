local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

local Config = {
    -- Script
    FlyEnabled = false, NoclipEnabled = false, InfJumpEnabled = false,
    ESPEnabled = false, AimbotActive = false, ShowAimbotBtn = false, 
    SpinbotEnabled = false, SpeedEnabled = false, ShiftLockEnabled = false, 
    WalkSpeed = 28.8,

    -- MM2
    MM2Esp = false, AimMurderer = false, KillAll = false, CoinFarm = false, VoteFarmEnabled = false,
    
    -- Doors
    Fullbright = false, DoorsESP = false, EntityAlert = false, DoorsSpeed = false
}

local savedHomeCFrame, spinBAV, collectedCoins = nil, nil, {}
local isVerified, isMenuOpen = false, false
local noclipOriginalStates = {}
local voteFarmCFrame, voteFarmThread = nil, nil

-- ================= ЛОГИКА ROLE ESP (MM2) =================
local MM2_COLORS = {Sheriff = Color3.fromRGB(0, 120, 255), Murderer = Color3.fromRGB(255, 40, 40), Innocent = Color3.fromRGB(0, 220, 90)}
local mm2_highlights = {}
local function getMM2Role(player)
    local attr = player:GetAttribute("Role")
    if attr and MM2_COLORS[attr] then return attr end
    local char, backpack = player.Character, player:FindFirstChildOfClass("Backpack")
    local function has(name) return (backpack and backpack:FindFirstChild(name)) or (char and char:FindFirstChild(name)) end
    if has("Knife") then return "Murderer" elseif has("Gun") then return "Sheriff" end
    return "Innocent"
end
local function removeMM2Highlight(player)
    local h = mm2_highlights[player]
    if h then h:Destroy(); mm2_highlights[player] = nil end
end
local function applyMM2Highlight(player)
    local char = player.Character
    if not char or not Config.MM2Esp then removeMM2Highlight(player); return end
    local h = mm2_highlights[player]
    if not h or h.Parent == nil or h.Adornee ~= char then
        if h then h:Destroy() end
        h = Instance.new("Highlight")
        h.Name, h.DepthMode, h.FillTransparency, h.OutlineTransparency, h.Adornee, h.Parent = "MM2_Highlight", Enum.HighlightDepthMode.AlwaysOnTop, 0.5, 0, char, char
        mm2_highlights[player] = h
    end
    local color = MM2_COLORS[getMM2Role(player)]
    h.FillColor, h.OutlineColor = color, color
end

-- ================= FLY SYSTEM =================
local FlySystem = {}
local function SetupFlySystem()
    local controls = require(LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
    local MIN_SPEED, MAX_SPEED = 20, 150
    local speed = 60
    local ACCENT, DARK, WHITE = Color3.fromRGB(120, 200, 255), Color3.fromRGB(20, 22, 28), Color3.new(1, 1, 1)
    local flying, upGui, downGui, upKey, downKey = false, false, false, false, false
    local vel, lean, roll = Vector3.zero, 0, 0
    local baseFov, pulseId, conn, bv, bg, trail, att0, att1 = 70, 0, nil, nil, nil, nil, nil, nil

    local function tw(obj, t, props, style, dir)
        TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props):Play()
    end

    if LocalPlayer.PlayerGui:FindFirstChild("FlyGui") then LocalPlayer.PlayerGui.FlyGui:Destroy() end
    local FlyGui = Instance.new("ScreenGui")
    FlyGui.Name, FlyGui.ResetOnSpawn, FlyGui.IgnoreGuiInset, FlyGui.Enabled = "FlyGui", false, true, false
    FlyGui.DisplayOrder = 999999
    pcall(function() FlyGui.Parent = game:GetService("CoreGui") end)
    if not FlyGui.Parent then FlyGui.Parent = LocalPlayer.PlayerGui end
    FlySystem.Gui = FlyGui

    local function corner(obj, r) local c = Instance.new("UICorner"); c.CornerRadius = r or UDim.new(1, 0); c.Parent = obj end
    local function makeStroke(obj, tr, th) local s = Instance.new("UIStroke"); s.Color, s.Transparency, s.Thickness, s.ApplyStrokeMode, s.Parent = WHITE, tr, th, Enum.ApplyStrokeMode.Border, obj; return s end
    local function makeButton(parent, size, text, textSize, pos)
        local b = Instance.new("TextButton")
        b.AnchorPoint, b.Position, b.Size, b.BackgroundColor3, b.BackgroundTransparency, b.AutoButtonColor = Vector2.new(0.5, 0.5), pos, UDim2.fromOffset(size, size), DARK, 0.35, false
        b.Text, b.TextColor3, b.TextTransparency, b.TextSize, b.Font, b.Parent = text, WHITE, 0.15, textSize, Enum.Font.GothamMedium, parent
        corner(b); local stroke = makeStroke(b, 0.8, 1.5); local scale = Instance.new("UIScale"); scale.Parent = b
        b.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then tw(scale, 0.12, { Scale = 0.88 }) end end)
        b.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then tw(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back) end end)
        return b, stroke
    end

    local holder = Instance.new("Frame")
    holder.AnchorPoint, holder.Position, holder.Size, holder.BackgroundTransparency, holder.Parent = Vector2.new(0, 0.5), UDim2.new(0, 14, 0.5, 80), UDim2.fromOffset(48, 48), 1, FlyGui
    local mainBtn, mainStroke = makeButton(holder, 48, "FLY", 13, UDim2.fromScale(0.5, 0.5)); mainBtn.ZIndex = 3
    
    local extras = Instance.new("CanvasGroup")
    extras.AnchorPoint, extras.Position, extras.Size, extras.BackgroundTransparency, extras.GroupTransparency, extras.Visible, extras.Parent = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(60, 160), 1, 1, false, holder
    local upBtn = makeButton(extras, 34, "▲", 12, UDim2.new(0.5, 0, 0.5, -50))
    local downBtn = makeButton(extras, 34, "▼", 12, UDim2.new(0.5, 0, 0.5, 50))
    local gearBtn = makeButton(holder, 26, "•••", 11, UDim2.new(0, 70, 0.5, 0)); gearBtn.BackgroundTransparency, gearBtn.TextTransparency = 0.55, 0.35

    local panel = Instance.new("CanvasGroup")
    panel.AnchorPoint, panel.Position, panel.Size, panel.BackgroundColor3, panel.BackgroundTransparency, panel.GroupTransparency, panel.Visible, panel.Parent = Vector2.new(0, 0.5), UDim2.new(0, 82, 0.5, 0), UDim2.fromOffset(160, 50), DARK, 0.3, 1, false, holder
    corner(panel, UDim.new(0, 12)); makeStroke(panel, 0.85, 1)
    
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency, label.Position, label.Size, label.Font, label.TextSize, label.TextXAlignment, label.TextColor3, label.TextTransparency, label.Parent = 1, UDim2.fromOffset(12, 7), UDim2.new(1, -24, 0, 16), Enum.Font.GothamMedium, 12, Enum.TextXAlignment.Left, WHITE, 0.2, panel
    local track = Instance.new("Frame"); track.Position, track.Size, track.BackgroundColor3, track.BackgroundTransparency, track.BorderSizePixel, track.Parent = UDim2.new(0, 12, 0, 34), UDim2.new(1, -24, 0, 4), WHITE, 0.8, 0, panel; corner(track)
    local fill = Instance.new("Frame"); fill.Size, fill.BackgroundColor3, fill.BorderSizePixel, fill.Parent = UDim2.fromScale(0.5, 1), ACCENT, 0, track; corner(fill)
    local knob = Instance.new("Frame"); knob.AnchorPoint, knob.Size, knob.BackgroundColor3, knob.BorderSizePixel, knob.Parent = Vector2.new(0.5, 0.5), UDim2.fromOffset(12, 12), WHITE, 0, track; corner(knob)
    local hit = Instance.new("TextButton"); hit.BackgroundTransparency, hit.Text, hit.Position, hit.Size, hit.Parent = 1, "", UDim2.new(0, 0, 0, 24), UDim2.new(1, 0, 0, 26), panel

    local function setSpeed(alpha)
        alpha = math.clamp(alpha, 0, 1); speed = math.floor(MIN_SPEED + (MAX_SPEED - MIN_SPEED) * alpha + 0.5)
        fill.Size, knob.Position, label.Text = UDim2.fromScale(alpha, 1), UDim2.fromScale(alpha, 0.5), "Скорость · " .. speed
    end
    setSpeed((speed - MIN_SPEED) / (MAX_SPEED - MIN_SPEED))

    local dragging = false
    hit.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = true; setSpeed((i.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X); tw(knob, 0.15, { Size = UDim2.fromOffset(16, 16) }, Enum.EasingStyle.Back) end end)
    UserInputService.InputChanged:Connect(function(i) if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then setSpeed((i.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X) end end)
    UserInputService.InputEnded:Connect(function(i) if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then dragging = false; tw(knob, 0.2, { Size = UDim2.fromOffset(12, 12) }) end end)

    local panelOpen = false
    gearBtn.MouseButton1Click:Connect(function()
        panelOpen = not panelOpen
        if panelOpen then panel.Visible = true; panel.Position = UDim2.new(0, 74, 0.5, 0); tw(panel, 0.25, { GroupTransparency = 0, Position = UDim2.new(0, 82, 0.5, 0) }); tw(gearBtn, 0.2, { TextColor3 = ACCENT })
        else tw(panel, 0.2, { GroupTransparency = 1, Position = UDim2.new(0, 74, 0.5, 0) }); tw(gearBtn, 0.2, { TextColor3 = WHITE }); task.delay(0.2, function() if not panelOpen then panel.Visible = false end end) end
    end)

    local function currentVertical() return ((upGui or upKey) and 1 or 0) - ((downGui or downKey) and 1 or 0) end
    
    local function setActiveVisual(on)
        pulseId += 1; local myId = pulseId
        if on then
            extras.Visible = true; tw(extras, 0.3, { GroupTransparency = 0 }); tw(mainBtn, 0.25, { TextColor3 = ACCENT, BackgroundTransparency = 0.2 }); tw(mainStroke, 0.25, { Color = ACCENT, Transparency = 0.15, Thickness = 2 })
            task.spawn(function() while flying and pulseId == myId do tw(mainStroke, 0.9, { Transparency = 0.6 }, Enum.EasingStyle.Sine); task.wait(0.9); if not (flying and pulseId == myId) then break end; tw(mainStroke, 0.9, { Transparency = 0.15 }, Enum.EasingStyle.Sine); task.wait(0.9) end end)
        else
            tw(extras, 0.25, { GroupTransparency = 1 }); task.delay(0.25, function() if not flying then extras.Visible = false end end); tw(mainBtn, 0.25, { TextColor3 = WHITE, BackgroundTransparency = 0.35 }); tw(mainStroke, 0.25, { Color = WHITE, Transparency = 0.8, Thickness = 1.5 })
        end
    end

    local function stopFly()
        if not flying then return end
        flying, upGui, downGui = false, false, false
        if conn then conn:Disconnect(); conn = nil end
        if bv then bv:Destroy(); bv = nil end
        if bg then bg:Destroy(); bg = nil end
        if trail then trail:Destroy(); trail = nil end
        if att0 then att0:Destroy(); att0 = nil end
        if att1 then att1:Destroy(); att1 = nil end
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hum then hum.PlatformStand = false end
        if hrp then
            local look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
            if look.Magnitude > 0.01 then hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + look) end
        end
        if workspace.CurrentCamera then tw(workspace.CurrentCamera, 0.4, { FieldOfView = baseFov }) end
        setActiveVisual(false)
    end

    local function startFly()
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then return end
        flying, lean, roll = true, 0, 0
        hum.PlatformStand = true
        vel = Vector3.zero
        baseFov = workspace.CurrentCamera.FieldOfView
        bv = Instance.new("BodyVelocity"); bv.MaxForce, bv.Velocity, bv.Parent = Vector3.new(1e5, 1e5, 1e5), Vector3.zero, hrp
        bg = Instance.new("BodyGyro"); bg.MaxTorque, bg.P, bg.D, bg.CFrame, bg.Parent = Vector3.new(1e5, 1e5, 1e5), 1e4, 600, hrp.CFrame, hrp
        att0 = Instance.new("Attachment"); att0.Position, att0.Parent = Vector3.new(0, 0.9, 0.3), hrp
        att1 = Instance.new("Attachment"); att1.Position, att1.Parent = Vector3.new(0, -0.9, 0.3), hrp
        trail = Instance.new("Trail")
        trail.Attachment0, trail.Attachment1, trail.Lifetime, trail.LightEmission, trail.Color, trail.Transparency, trail.Enabled, trail.Parent = att0, att1, 0.4, 0.6, ColorSequence.new(ACCENT, WHITE), NumberSequence.new(0.35, 1), false, hrp
        setActiveVisual(true)
        conn = RunService.RenderStepped:Connect(function(dt)
            local cam = workspace.CurrentCamera
            local move = controls:GetMoveVector()
            local vert = currentVertical()
            local dir = cam.CFrame.RightVector * move.X - cam.CFrame.LookVector * move.Z + Vector3.yAxis * vert
            if dir.Magnitude > 1 then dir = dir.Unit end
            vel = vel:Lerp(dir * speed, 1 - math.exp(-6 * dt))
            local bob = 0
            if dir.Magnitude < 0.05 then bob = math.sin(os.clock() * 2.2) * 0.8 end
            bv.Velocity = vel + Vector3.new(0, bob, 0)
            local k = 1 - math.exp(-8 * dt)
            lean += (move.Z * 35 - lean) * k
            roll += (-move.X * 22 - roll) * k
            local flat = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
            if flat.Magnitude < 0.01 then flat = hrp.CFrame.LookVector end
            bg.CFrame = CFrame.lookAt(Vector3.zero, flat) * CFrame.Angles(math.rad(lean), 0, math.rad(roll))
            local ratio = math.clamp(vel.Magnitude / MAX_SPEED, 0, 1)
            cam.FieldOfView = baseFov + 14 * ratio
            trail.Enabled = vel.Magnitude > 10
        end)
    end

    mainBtn.MouseButton1Click:Connect(function() if flying then stopFly() else startFly() end end)
    local function bindHold(btn, setter)
        btn.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then setter(true) end end)
        btn.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then setter(false) end end)
    end
    bindHold(upBtn, function(v) upGui = v end)
    bindHold(downBtn, function(v) downGui = v end)
    LocalPlayer.CharacterAdded:Connect(function() stopFly() end)
    FlySystem.Stop = stopFly
end
SetupFlySystem()

-- ================= UI БАЗА =================
local BLUE, WHITE, BLACK, PANEL_BG, OFF_BG, OFF_TEXT, KEYBOX_BG, KEYBOX_ERROR = Color3.fromRGB(30, 80, 150), Color3.new(1,1,1), Color3.new(0,0,0), Color3.fromRGB(250, 252, 255), Color3.fromRGB(200, 210, 220), Color3.fromRGB(80, 80, 80), Color3.fromRGB(220, 225, 230), Color3.fromRGB(255, 200, 200)
local MAIN_W, MAIN_H, KEY_W, KEY_H, PAD, TAB_W, TAB_H, TAB_GAP, DRAG_THRESHOLD, ROW_DELAY, TAB_LEAVE_TIME = 460, 310, 300, 200, 28, 90, 30, 5, 8, 0.045, 0.15
local EASE, DIR, CENTER, MOUSE1, TOUCH, MOUSE_MOVE = Enum.EasingStyle, Enum.EasingDirection, UDim2.new(0.5, 0, 0.5, 0), Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch, Enum.UserInputType.MouseMovement
local HUB_NAME, CORRECT_KEY, ERROR_TEXT = "PlutoniumHub", "zid22", "Неверный ключ!"
local currentTab, connections = nil, {}

local function Bind(signal, fn) connections[#connections + 1] = signal:Connect(fn) end
local function Create(className, props) local obj = Instance.new(className); local parent = nil; for key, value in pairs(props) do if key == "Parent" then parent = value else obj[key] = value end end; obj.Parent = parent; return obj end
local function Tween(obj, duration, goal, style, direction, delayTime) local info = TweenInfo.new(duration, style or EASE.Quad, direction or DIR.Out, 0, false, delayTime or 0); local tw = TweenService:Create(obj, info, goal); tw:Play(); return tw end
local function DestroyOld() for _, container in ipairs({game:GetService("CoreGui"), LocalPlayer:FindFirstChildOfClass("PlayerGui")}) do pcall(function() local old = container:FindFirstChild(HUB_NAME); if old then old:Destroy() end end) end end
local function Mount(gui) local ok = pcall(function() gui.Parent = game:GetService("CoreGui") end); if not ok or not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end end

DestroyOld()
local ScreenGui = Create("ScreenGui", { Name = HUB_NAME, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 99999 })

local pressedFx = {}
local function AttachFx(btn, scale, opts)
    opts = opts or {}; local hoverScale, pressScale, hoverRotation = opts.Hover or 1.03, opts.Press or 0.95, opts.HoverRotation; local hovered, pressed = false, false
    local function refresh() if pressed then Tween(scale, 0.08, {Scale = pressScale}, EASE.Quad, DIR.Out) elseif hovered then Tween(scale, 0.18, {Scale = hoverScale}, EASE.Quad, DIR.Out) else Tween(scale, 0.4, {Scale = 1}, EASE.Back, DIR.Out) end end
    local function release() if pressed then pressed = false; refresh() end end
    btn.InputBegan:Connect(function(input) local t = input.UserInputType; if t == MOUSE_MOVE then hovered = true; if hoverRotation then Tween(btn, 0.3, {Rotation = hoverRotation}, EASE.Back, DIR.Out) end; if not pressed then refresh() end elseif t == MOUSE1 or t == TOUCH then pressed = true; pressedFx[release] = true; refresh() end end)
    btn.InputEnded:Connect(function(input) if input.UserInputType == MOUSE_MOVE then hovered = false; if hoverRotation then Tween(btn, 0.3, {Rotation = 0}, EASE.Back, DIR.Out) end; if not pressed then refresh() end end end)
end

local MainDrag = nil
local function WindowMoved() return MainDrag ~= nil and MainDrag.Moved end

local function CreatePopup(shell, scale, inner, opts)
    opts = opts or {}; local hiddenScale, rise = opts.HiddenScale or 0.82, opts.Rise or 16; local popup = {IsOpen = false}; local token = 0
    local function setOpen(value) popup.IsOpen = value; if opts.OnChanged then opts.OnChanged(value) end end
    function popup.Show(delayTime)
        token = token + 1; local my = token; setOpen(true)
        local function run()
            if token ~= my then return end
            if not shell.Visible then scale.Scale = hiddenScale; shell.GroupTransparency = 1; inner.Position = UDim2.new(0.5, 0, 0.5, rise) end
            shell.Visible = true; Tween(scale, 0.5, {Scale = 1}, EASE.Back, DIR.Out); Tween(shell, 0.3, {GroupTransparency = 0}, EASE.Quad, DIR.Out); Tween(inner, 0.5, {Position = CENTER}, EASE.Quint, DIR.Out); if opts.OnShown then opts.OnShown() end
        end
        if delayTime and delayTime > 0 then task.delay(delayTime, run) else run() end
    end
    function popup.Hide()
        token = token + 1; local my = token; setOpen(false); if not shell.Visible then return end
        Tween(scale, 0.22, {Scale = 0.9}, EASE.Quad, DIR.In); Tween(inner, 0.22, {Position = UDim2.new(0.5, 0, 0.5, 10)}, EASE.Quad, DIR.In)
        local fade = Tween(shell, 0.2, {GroupTransparency = 1}, EASE.Quad, DIR.In); fade.Completed:Connect(function(state) if token == my and state == Enum.PlaybackState.Completed then shell.Visible = false end end)
    end
    return popup
end

local ToggleBtn = Create("TextButton", { Name = "ToggleBtn", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 50, 0, 50), Position = UDim2.new(0, 45, 0.5, 0), BackgroundColor3 = WHITE, BorderSizePixel = 0, Text = "🌐", TextSize = 28, TextColor3 = BLUE, Font = Enum.Font.GothamBold, AutoButtonColor = false, Parent = ScreenGui })
Create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = ToggleBtn})
local ToggleScale = Create("UIScale", {Scale = 0, Parent = ToggleBtn})
AttachFx(ToggleBtn, ToggleScale, {Hover = 1.08, Press = 0.88})

local BigAimbotBtn = Create("TextButton", { Name = "BigAimbotBtn", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 130, 0, 60), Position = UDim2.new(1, -150, 0.4, 0), BackgroundColor3 = Color3.fromRGB(180, 40, 40), Text = "AIMBOT: OFF", TextSize = 16, TextColor3 = WHITE, Font = Enum.Font.GothamBold, Visible = false, AutoButtonColor = false, Parent = ScreenGui })
Create("UICorner", {CornerRadius = UDim.new(0, 12), Parent = BigAimbotBtn})
AttachFx(BigAimbotBtn, Create("UIScale", {Parent = BigAimbotBtn}), {Hover = 1.05, Press = 0.9})

local MainShell = Create("CanvasGroup", { Name = "MainShell", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, MAIN_W + PAD * 2, 0, MAIN_H + PAD * 2), BackgroundTransparency = 1, BorderSizePixel = 0, GroupTransparency = 1, Visible = false, Parent = ScreenGui })
local MainScale = Create("UIScale", {Scale = 0.82, Parent = MainShell})
local MainFrame = Create("Frame", { Name = "MainFrame", AnchorPoint = Vector2.new(0.5, 0.5), Position = CENTER, Size = UDim2.new(0, MAIN_W, 0, MAIN_H), BackgroundColor3 = PANEL_BG, BorderSizePixel = 0, Active = true, ClipsDescendants = true, Parent = MainShell })
Create("UICorner", {CornerRadius = UDim.new(0, 12), Parent = MainFrame}); Create("UIStroke", {Color = BLUE, Thickness = 2, Parent = MainFrame})

local Header = Create("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 45), BackgroundColor3 = BLUE, BorderSizePixel = 0, Parent = MainFrame })
Create("UICorner", {CornerRadius = UDim.new(0, 12), Parent = Header}); Create("Frame", { Name = "HeaderFix", Size = UDim2.new(1, 0, 0, 10), Position = UDim2.new(0, 0, 1, -10), BackgroundColor3 = BLUE, BorderSizePixel = 0, Parent = Header })

local CloseBtn = Create("TextButton", { Name = "CloseBtn", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(1, -25, 0, 22), BackgroundTransparency = 1, BorderSizePixel = 0, Text = "❌", TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 20, AutoButtonColor = false, Parent = Header })
AttachFx(CloseBtn, Create("UIScale", {Parent = CloseBtn}), {Hover = 1.1, Press = 0.85, HoverRotation = 90})

local TabContainer = Create("Frame", { Name = "TabContainer", Size = UDim2.new(1, -60, 1, 0), Position = UDim2.new(0, 10, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = Header })
local TabHighlight = Create("Frame", { Name = "TabHighlight", AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.new(0, TAB_W, 0, TAB_H), Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2, Parent = TabContainer })
Create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = TabHighlight})

local function CreateTabBtn(text, index)
    local x = (index - 1) * (TAB_W + TAB_GAP)
    local pill = Create("Frame", { Name = "TabPill" .. index, AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.new(0, TAB_W, 0, TAB_H), Position = UDim2.new(0, x, 0.5, 0), BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 1, Parent = TabContainer })
    Create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = pill})
    local btn = Create("TextButton", { Name = "Tab" .. index, AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.new(0, TAB_W, 0, TAB_H), Position = UDim2.new(0, x, 0.5, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Text = text, TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = false, ZIndex = 3, Parent = TabContainer })
    btn.InputBegan:Connect(function(input) if input.UserInputType == MOUSE_MOVE then Tween(pill, 0.15, {BackgroundTransparency = 0.65}) end end)
    btn.InputEnded:Connect(function(input) if input.UserInputType == MOUSE_MOVE then Tween(pill, 0.2, {BackgroundTransparency = 0.8}) end end)
    return btn
end

local tabs, TabIndex = {}, {}
local TabNames, TabLabels = {"Script", "MM2", "Doors"}, {"Script", "MM2", "Doors"}
for i, name in ipairs(TabNames) do tabs[name] = CreateTabBtn(TabLabels[i], i); TabIndex[name] = i end

local Content = Create("Frame", { Name = "Content", Size = UDim2.new(1, -20, 1, -55), Position = UDim2.new(0, 10, 0, 50), BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true, Parent = MainFrame })
local pages, pageItems, containerInfo, itemCount, itemTweens = {}, {}, {}, {}, {}

local function RegisterContainer(frame, pageName, isFooter) containerInfo[frame] = {Page = pageName, Footer = isFooter == true} end
local function NewList(parent) return Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = parent }) end

local function CreatePage(name, isTwoCols)
    local page = Create("Frame", { Name = name, Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, Parent = Content })
    pageItems[name], itemTweens[name] = {}, {}
    if isTwoCols then
        local left = Create("Frame", { Name = "Left", Size = UDim2.new(0.5, -5, 1, -40), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = page }); NewList(left)
        local right = Create("Frame", { Name = "Right", Size = UDim2.new(0.5, -5, 1, -40), Position = UDim2.new(0.5, 5, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = page }); NewList(right)
        pages[name] = {Page = page, Left = left, Right = right}; RegisterContainer(left, name, false); RegisterContainer(right, name, false)
    else
        local main = Create("Frame", { Name = "Main", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = page }); NewList(main)
        pages[name] = {Page = page, Main = main}; RegisterContainer(main, name, false)
    end
end

CreatePage("Script", true); CreatePage("MM2", false); CreatePage("Doors", false)

local function MakeItem(parent, text, bgColor, textColor)
    local order = (itemCount[parent] or 0) + 1; itemCount[parent] = order
    local holder = Create("Frame", { Name = "Item", Size = UDim2.new(1, 0, 0, 35), BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = order, Parent = parent })
    local btn = Create("TextButton", { Name = "Button", AnchorPoint = Vector2.new(0.5, 0.5), Position = CENTER, Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = bgColor, BorderSizePixel = 0, Text = text, TextColor3 = textColor, Font = Enum.Font.GothamBold, TextSize = 13, AutoButtonColor = false, Parent = holder })
    Create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = btn}); AttachFx(btn, Create("UIScale", {Parent = btn}))
    local info = containerInfo[parent]
    if info then local list = pageItems[info.Page]; list[#list + 1] = {Btn = btn, Row = order - 1, Footer = info.Footer} end
    return btn
end

local function CreateToggle(parent, text, state, callback)
    local Btn = MakeItem(parent, text, state and BLUE or OFF_BG, state and WHITE or OFF_TEXT)
    Btn.MouseButton1Click:Connect(function()
        if WindowMoved() then return end
        state = not state; Tween(Btn, 0.25, { BackgroundColor3 = state and BLUE or OFF_BG, TextColor3 = state and WHITE or OFF_TEXT }, EASE.Quad, DIR.Out)
        if callback then task.spawn(callback, state, Btn) end
    end)
    return Btn
end

local function CreateAction(parent, text, callback)
    local Btn = MakeItem(parent, text, OFF_BG, OFF_TEXT)
    Btn.MouseButton1Click:Connect(function()
        if WindowMoved() then return end
        Tween(Btn, 0.1, {BackgroundColor3 = BLUE, TextColor3 = WHITE})
        task.delay(0.12, function() if Btn.Parent then Tween(Btn, 0.3, {BackgroundColor3 = OFF_BG, TextColor3 = OFF_TEXT}) end end)
        if callback then task.spawn(callback, Btn) end
    end)
    return Btn
end

local function CancelItemTweens(pageName) local list = itemTweens[pageName]; if list then for _, tw in ipairs(list) do tw:Cancel() end end; itemTweens[pageName] = {} end
local function TrackItemTween(pageName, tw) local list = itemTweens[pageName]; list[#list + 1] = tw end

local function EnterPage(pageName, restart, offX, offY, baseDelay)
    local items = pageItems[pageName]; if not items then return end
    CancelItemTweens(pageName); local maxRow = 0
    for _, it in ipairs(items) do if not it.Footer and it.Row > maxRow then maxRow = it.Row end end
    for _, it in ipairs(items) do
        local btn = it.Btn; local row = it.Footer and (maxRow + 1 + it.Row) or it.Row; local delayTime = baseDelay + row * ROW_DELAY
        if restart then btn.BackgroundTransparency = 1; btn.TextTransparency = 1; btn.Position = UDim2.new(0.5, offX, 0.5, offY) end
        TrackItemTween(pageName, Tween(btn, 0.45, {Position = CENTER}, EASE.Quint, DIR.Out, delayTime))
        TrackItemTween(pageName, Tween(btn, 0.3, {BackgroundTransparency = 0, TextTransparency = 0}, EASE.Quad, DIR.Out, delayTime))
    end
end

local function LeavePage(pageName, offX)
    local items = pageItems[pageName]; if not items then return end
    CancelItemTweens(pageName)
    for _, it in ipairs(items) do TrackItemTween(pageName, Tween(it.Btn, 0.15, { Position = UDim2.new(0.5, offX, 0.5, 0), BackgroundTransparency = 1, TextTransparency = 1 }, EASE.Quad, DIR.In)) end
end

local switchToken = 0
local function SwitchTab(name)
    if not tabs[name] or name == currentTab then return end
    local previous = currentTab; currentTab = name; switchToken = switchToken + 1; local my = switchToken
    for tabName, btn in pairs(tabs) do Tween(btn, 0.25, {TextColor3 = (tabName == name) and BLACK or WHITE}, EASE.Quad, DIR.Out) end
    local x = (TabIndex[name] - 1) * (TAB_W + TAB_GAP)
    if previous == nil then TabHighlight.Position = UDim2.new(0, x, 0.5, 0); TabHighlight.BackgroundTransparency = 0
    else Tween(TabHighlight, 0.4, {Position = UDim2.new(0, x, 0.5, 0)}, EASE.Quint, DIR.Out) end
    local dir = 0; if previous then dir = (TabIndex[name] > TabIndex[previous]) and 1 or -1 end
    local leaving = false
    for pageName, data in pairs(pages) do if pageName ~= name and data.Page.Visible then LeavePage(pageName, -dir * 14); leaving = true end end
    local function finish()
        if switchToken ~= my then return end
        for pageName, data in pairs(pages) do if pageName ~= name then data.Page.Visible = false end end
        local target = pages[name].Page; local wasVisible = target.Visible; target.Visible = true; EnterPage(name, not wasVisible, dir * 22, 0, 0)
    end
    if leaving then task.delay(TAB_LEAVE_TIME, finish) else finish() end
end

for name, btn in pairs(tabs) do btn.MouseButton1Click:Connect(function() if WindowMoved() then return end; SwitchTab(name) end) end

local KeyShell = Create("CanvasGroup", { Name = "KeyShell", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, KEY_W + PAD * 2, 0, KEY_H + PAD * 2), BackgroundTransparency = 1, BorderSizePixel = 0, GroupTransparency = 1, Visible = false, Parent = ScreenGui })
local KeyScale = Create("UIScale", {Scale = 0.82, Parent = KeyShell})
local KeyFrame = Create("Frame", { Name = "KeyFrame", AnchorPoint = Vector2.new(0.5, 0.5), Position = CENTER, Size = UDim2.new(0, KEY_W, 0, KEY_H), BackgroundColor3 = PANEL_BG, BorderSizePixel = 0, Active = true, Parent = KeyShell })
Create("UICorner", {CornerRadius = UDim.new(0, 12), Parent = KeyFrame}); Create("UIStroke", {Color = BLUE, Thickness = 2, Parent = KeyFrame})

local KeyTitle = Create("TextLabel", { Name = "KeyTitle", Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = BLUE, BorderSizePixel = 0, Text = "Plutonium", TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 20, Parent = KeyFrame })
Create("UICorner", {CornerRadius = UDim.new(0, 12), Parent = KeyTitle}); Create("Frame", { Name = "KeyTitleFix", Size = UDim2.new(1, 0, 0, 10), Position = UDim2.new(0, 0, 1, -10), BackgroundColor3 = BLUE, BorderSizePixel = 0, Parent = KeyTitle })

local KeyBox = Create("TextBox", { Name = "KeyBox", Size = UDim2.new(0.8, 0, 0, 40), Position = UDim2.new(0.1, 0, 0.4, 0), BackgroundColor3 = KEYBOX_BG, BorderSizePixel = 0, PlaceholderText = "Введите ключ...", Text = "", Font = Enum.Font.Gotham, TextSize = 16, Parent = KeyFrame })
Create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = KeyBox})

local KeyBtn = Create("TextButton", { Name = "KeyBtn", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0.8, 0, 0, 40), Position = UDim2.new(0.5, 0, 0.7, 20), BackgroundColor3 = BLUE, BorderSizePixel = 0, Text = "Проверить", TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 16, AutoButtonColor = false, Parent = KeyFrame })
Create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = KeyBtn}); AttachFx(KeyBtn, Create("UIScale", {Parent = KeyBtn}))

local MainPopup = CreatePopup(MainShell, MainScale, MainFrame, { OnChanged = function(open) isMenuOpen = open end, OnShown = function() if currentTab then EnterPage(currentTab, true, 0, 16, 0.1) end end })
local KeyPopup = CreatePopup(KeyShell, KeyScale, KeyFrame, {})

local function ToggleUI() if not isVerified then if KeyPopup.IsOpen then KeyPopup.Hide() else KeyPopup.Show() end else if MainPopup.IsOpen then MainPopup.Hide() else MainPopup.Show() end end end
CloseBtn.MouseButton1Click:Connect(function() if WindowMoved() then return end; MainPopup.Hide() end)

local dragObjects = {}
local function MakeDraggable(handle, target, halfW, halfH, onClick)
    local drag = {Moved = false}; local active, loop = nil, nil; local pointerStart, startX, startY, goalX, goalY, curX, curY = Vector2.new(0, 0), 0, 0, 0, 0, 0, 0
    local function clampOffsets(x, y)
        local screen = ScreenGui.AbsoluteSize; if screen.X < 1 or screen.Y < 1 then return x, y end
        local p = target.Position; local baseX, baseY = p.X.Scale * screen.X, p.Y.Scale * screen.Y
        local loX, hiX, loY, hiY = math.min(halfW, screen.X - halfW), math.max(halfW, screen.X - halfW), math.min(halfH, screen.Y - halfH), math.max(halfH, screen.Y - halfH)
        return math.clamp(baseX + x, loX, hiX) - baseX, math.clamp(baseY + y, loY, hiY) - baseY
    end
    local function apply(x, y) local p = target.Position; target.Position = UDim2.new(p.X.Scale, math.floor(x + 0.5), p.Y.Scale, math.floor(y + 0.5)) end
    local function startLoop()
        if loop then return end; curX, curY = target.Position.X.Offset, target.Position.Y.Offset
        loop = RunService.RenderStepped:Connect(function(dt)
            local a = 1 - math.exp(-dt * 26); curX, curY = curX + (goalX - curX) * a, curY + (goalY - curY) * a
            if active == nil and math.abs(goalX - curX) < 0.3 and math.abs(goalY - curY) < 0.3 then apply(goalX, goalY); loop:Disconnect(); loop = nil; return end
            apply(curX, curY)
        end)
    end
    handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= MOUSE1 and input.UserInputType ~= TOUCH then return end
        active, drag.Moved, pointerStart = input, false, Vector2.new(input.Position.X, input.Position.Y)
        local p = target.Position; startX, startY, goalX, goalY = p.X.Offset, p.Y.Offset, p.X.Offset, p.Y.Offset
    end)
    function drag.OnChanged(input)
        if active == nil or not ((input == active) or (active.UserInputType == MOUSE1 and input.UserInputType == MOUSE_MOVE)) then return end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - pointerStart
        if not drag.Moved then if delta.Magnitude < DRAG_THRESHOLD then return end; drag.Moved = true; startLoop() end
        goalX, goalY = clampOffsets(startX + delta.X, startY + delta.Y)
    end
    function drag.OnEnded(input)
        if active == nil or not ((input == active) or (active.UserInputType == MOUSE1 and input.UserInputType == MOUSE1) or (active.UserInputType == TOUCH and input.UserInputType == TOUCH)) then return end
        active = nil; if not drag.Moved and onClick then onClick() end
    end
    function drag.Reclamp() local p = target.Position; local x, y = clampOffsets(p.X.Offset, p.Y.Offset); apply(x, y) end
    function drag.Destroy() if loop then loop:Disconnect(); loop = nil end end
    dragObjects[#dragObjects + 1] = drag; return drag
end

MainDrag = MakeDraggable(MainFrame, MainShell, MAIN_W / 2, MAIN_H / 2, nil)
MakeDraggable(ToggleBtn, ToggleBtn, 25, 25, ToggleUI)

local function CleanAllESP()
    for _, v in pairs(Players:GetPlayers()) do if v.Character then for _, obj in pairs(v.Character:GetChildren()) do if obj:IsA("Highlight") or obj.Name == "TitanHighlight" or obj.Name == "PlayerESP" then obj:Destroy() end end end end
end
local function GetMurderer()
    for _, v in pairs(Players:GetPlayers()) do if v ~= LocalPlayer and v.Character and v.Character:FindFirstChild("Humanoid") and v.Character.Humanoid.Health > 0 and (v.Character:FindFirstChild("Knife") or (v:FindFirstChild("Backpack") and v.Backpack:FindFirstChild("Knife"))) then return v end end
    return nil
end
local function GetClosestPlayer()
    local closest, dist = nil, math.huge
    for _, v in pairs(Players:GetPlayers()) do if v ~= LocalPlayer and v.Character and v.Character:FindFirstChild("HumanoidRootPart") and v.Character:FindFirstChild("Humanoid") and v.Character.Humanoid.Health > 0 then local d = (LocalPlayer.Character.HumanoidRootPart.Position - v.Character.HumanoidRootPart.Position).Magnitude; if d < dist then dist = d; closest = v end end end
    return closest
end

BigAimbotBtn.MouseButton1Click:Connect(function()
    Config.AimbotActive = not Config.AimbotActive
    TweenService:Create(BigAimbotBtn, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = Config.AimbotActive and Color3.fromRGB(40, 180, 40) or Color3.fromRGB(180, 40, 40)}):Play()
    BigAimbotBtn.Text = Config.AimbotActive and "AIMBOT: ON" or "AIMBOT: OFF"
end)

local errorToken, shaking = 0, false
local function ShakeKeyBox() if shaking then return end; shaking = true; task.spawn(function() for _, ox in ipairs({9, -9, 6, -6, 3, -3, 0}) do Tween(KeyBox, 0.05, {Position = UDim2.new(0.1, ox, 0.4, 0)}, EASE.Sine, DIR.InOut); task.wait(0.05) end; shaking = false end) end
local function VerifyKey()
    if isVerified then return end
    if string.match(KeyBox.Text, "^%s*(.-)%s*$") == CORRECT_KEY then isVerified = true; KeyBox:ReleaseFocus(); KeyPopup.Hide(); SwitchTab("Script"); MainPopup.Show(0.12)
    else errorToken += 1; local my = errorToken; KeyBox.Text = ERROR_TEXT; Tween(KeyBox, 0.1, {BackgroundColor3 = KEYBOX_ERROR}); task.delay(0.15, function() Tween(KeyBox, 0.6, {BackgroundColor3 = KEYBOX_BG}) end); ShakeKeyBox(); task.delay(1, function() if errorToken == my and KeyBox.Text == ERROR_TEXT then KeyBox.Text = "" end end) end
end
KeyBtn.MouseButton1Click:Connect(VerifyKey); KeyBox.FocusLost:Connect(function(enterPressed) if enterPressed then VerifyKey() end end)

-- ================= НАПОЛНЕНИЕ ВКЛАДОК =================
local p1 = pages.Script
CreateToggle(p1.Left, "Fly", false, function(s) Config.FlyEnabled = s; if FlySystem.Gui then FlySystem.Gui.Enabled = s end; if not s and FlySystem.Stop then FlySystem.Stop() end end)
CreateToggle(p1.Left, "Noclip", false, function(s) Config.NoclipEnabled = s end)
CreateToggle(p1.Left, "Inf Jump", false, function(s) Config.InfJumpEnabled = s end)
CreateToggle(p1.Left, "ESP (Игроки)", false, function(s) Config.ESPEnabled = s; if not s then CleanAllESP() end end)
CreateToggle(p1.Right, "Shift Lock", false, function(s) Config.ShiftLockEnabled = s end)
CreateToggle(p1.Right, "Speed hack", false, function(s) Config.SpeedEnabled = s end)
CreateToggle(p1.Right, "Spinbot", false, function(s) Config.SpinbotEnabled = s end)
CreateToggle(p1.Right, "Aimbot", false, function(s) Config.ShowAimbotBtn = s; BigAimbotBtn.Visible = s; if s then Config.AimbotActive = false; BigAimbotBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40); BigAimbotBtn.Text = "AIMBOT: OFF" else Config.AimbotActive = false end end)
local homeBtn = CreateAction(p1.Left, "Set Home", function(btn) if not savedHomeCFrame then if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then savedHomeCFrame = LocalPlayer.Character.HumanoidRootPart.CFrame; btn.Text = "Home" end else if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then LocalPlayer.Character.HumanoidRootPart.CFrame = savedHomeCFrame end end end)
CreateAction(p1.Right, "Reset Home", function() savedHomeCFrame = nil; homeBtn.Text = "Set Home" end)
local dieFrame = Create("Frame", { Name = "Bottom", Size = UDim2.new(1, 0, 0, 35), Position = UDim2.new(0, 0, 1, -35), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = pages.Script.Page })
RegisterContainer(dieFrame, "Script", true)
CreateAction(dieFrame, "Умереть", function() if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then LocalPlayer.Character.Humanoid.Health = 0 end end)

-- MM2
local p3 = pages.MM2
CreateToggle(p3.Main, "Role ESP", false, function(s) Config.MM2Esp = s; if not s then for _, h in pairs(mm2_highlights) do if h then h:Destroy() end end; mm2_highlights = {} end end)
CreateToggle(p3.Main, "Murderer Aim", false, function(s) Config.AimMurderer = s end)
CreateToggle(p3.Main, "Bring All (Kill All)", false, function(s) Config.KillAll = s end)
CreateToggle(p3.Main, "Coin Farm", false, function(s) Config.CoinFarm = s end)
CreateToggle(p3.Main, "Vote Farm (Fast)", false, function(s)
    Config.VoteFarmEnabled = s
    if s then
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then voteFarmCFrame = char.HumanoidRootPart.CFrame else return end
        if voteFarmThread then task.cancel(voteFarmThread) end
        voteFarmThread = task.spawn(function()
            while Config.VoteFarmEnabled do
                local currentChar = LocalPlayer.Character
                local hum = currentChar and currentChar:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then hum.Health = 0 end
                local newChar = LocalPlayer.CharacterAdded:Wait()
                local newHrp = newChar:WaitForChild("HumanoidRootPart", 5)
                if newHrp and voteFarmCFrame then newHrp.CFrame = voteFarmCFrame end
                task.wait(0.1)
            end
        end)
    else
        if voteFarmThread then task.cancel(voteFarmThread); voteFarmThread = nil end
    end
end)

-- Doors
local p4 = pages.Doors
CreateToggle(p4.Main, "Fullbright", false, function(v) Config.Fullbright = v; if v then Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShadows = 2, 14, 100000, false else Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShadows = 1, 0, 1000, true end end)
CreateToggle(p4.Main, "ESP (Двери, Лут)", false, function(v)
    Config.DoorsESP = v
    task.spawn(function() while Config.DoorsESP do for _, obj in pairs(workspace:GetDescendants()) do
        if obj.Name == "Door" and obj:IsA("Model") and obj:FindFirstChild("Door") then local target = obj:FindFirstChild("Door"); local hl = target:FindFirstChild("TitanHighlight") or Instance.new("Highlight", target); hl.Name, hl.FillColor, hl.FillTransparency = "TitanHighlight", Color3.fromRGB(0, 255, 255), 0.5
        elseif obj.Name == "Lever" or obj.Name == "LeverForPuzzle" then local hl = obj:FindFirstChild("TitanHighlight") or Instance.new("Highlight", obj); hl.Name, hl.FillColor, hl.FillTransparency = "TitanHighlight", Color3.fromRGB(255, 100, 0), 0.3
        elseif obj.Name == "Key" or obj.Name == "KeyObtain" or obj.Name == "LiveHintBook" then local hl = obj:FindFirstChild("TitanHighlight") or Instance.new("Highlight", obj); hl.Name, hl.FillColor, hl.FillTransparency = "TitanHighlight", Color3.fromRGB(255, 255, 0), 0.2
        elseif (obj.Name == "Lighter" or obj.Name == "Vitamins" or obj.Name == "Battery" or obj.Name == "Bandage" or obj.Name == "Flashlight" or obj.Name == "GoldPile") or (obj:FindFirstChildOfClass("ProximityPrompt") and obj:IsA("BasePart")) then
            if obj.Name ~= "Drawer" and obj.Name ~= "Wardrobe" then local hl = obj:FindFirstChild("TitanHighlight") or Instance.new("Highlight", obj); hl.Name, hl.FillColor, hl.FillTransparency = "TitanHighlight", Color3.fromRGB(0, 255, 0), 0.4 end
        end
    end; task.wait(0.4) end end)
end)
CreateToggle(p4.Main, "Entity Alert", false, function(v) Config.EntityAlert = v; workspace.ChildAdded:Connect(function(child) if Config.EntityAlert then for _, name in pairs({"RushMoving", "AmbushMoving", "SeekMoving", "Eyes", "Screech"}) do if child.Name == name then local hl = Instance.new("Highlight", child); hl.FillColor = Color3.fromRGB(255, 0, 0) end end end end) end)
CreateToggle(p4.Main, "Safe Speed", false, function(v) Config.DoorsSpeed = v; task.spawn(function() while Config.DoorsSpeed do if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then LocalPlayer.Character.Humanoid.WalkSpeed = 20.8 end; task.wait(0.1) end; if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then LocalPlayer.Character.Humanoid.WalkSpeed = 16 end end) end)

local mm2_acc = 0
RunService.Heartbeat:Connect(function(dt)
    if Config.ESPEnabled then for _, v in pairs(Players:GetPlayers()) do if v ~= LocalPlayer and v.Character and not v.Character:FindFirstChild("PlayerESP") then local hl = Instance.new("Highlight"); hl.Name, hl.Adornee, hl.DepthMode, hl.FillTransparency, hl.OutlineColor, hl.OutlineTransparency, hl.Parent = "PlayerESP", v.Character, Enum.HighlightDepthMode.AlwaysOnTop, 1, Color3.fromRGB(255, 255, 255), 0, v.Character end end end
    if Config.MM2Esp then mm2_acc += dt; if mm2_acc >= 0.2 then mm2_acc = 0; for _, player in ipairs(Players:GetPlayers()) do if player ~= LocalPlayer then applyMM2Highlight(player) end end end end
end)
Players.PlayerRemoving:Connect(removeMM2Highlight)

task.spawn(function()
    while true do task.wait(0.1)
        if Config.CoinFarm and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local root, target, dist = LocalPlayer.Character.HumanoidRootPart, nil, math.huge
            for _, obj in pairs(workspace:GetDescendants()) do if obj:IsA("BasePart") and (obj.Name == "Coin_Server" or obj.Name == "Coin" or obj.Name == "Snowflake") and not collectedCoins[obj] then local d = (root.Position - obj.Position).Magnitude; if d < dist then dist, target = d, obj end end end
            if target then
                TweenService:Create(root, TweenInfo.new(dist/22, Enum.EasingStyle.Linear), {CFrame = target.CFrame}):Play()
                local start = tick(); repeat task.wait() until (root.Position - target.Position).Magnitude < 2 or not Config.CoinFarm or tick()-start > 5
                collectedCoins[target] = true; task.delay(3, function() collectedCoins[target] = nil end)
            end
        end
    end
end)

RunService.RenderStepped:Connect(function()
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        local hrp, hum = LocalPlayer.Character.HumanoidRootPart, LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if Config.KillAll then for _, v in pairs(Players:GetPlayers()) do if v ~= LocalPlayer and v.Character and v.Character:FindFirstChild("HumanoidRootPart") then v.Character.HumanoidRootPart.CFrame = hrp.CFrame * CFrame.new(0, 0, -3) end end end
        if Config.SpinbotEnabled then if not spinBAV then spinBAV = Instance.new("BodyAngularVelocity", hrp); spinBAV.AngularVelocity, spinBAV.MaxTorque, spinBAV.P = Vector3.new(0, 15, 0), Vector3.new(0, math.huge, 0), 10000 end elseif spinBAV then spinBAV:Destroy(); spinBAV = nil end
        if Config.ShiftLockEnabled then UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter; local _, y, _ = Camera.CFrame:ToEulerAnglesYXZ(); hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, y, 0) end
        local target = nil
        if Config.AimMurderer then target = GetMurderer() elseif Config.AimbotActive then target = GetClosestPlayer() end
        if target and target.Character then local aimPart = target.Character:FindFirstChild("HumanoidRootPart") or target.Character:FindFirstChild("UpperTorso"); if aimPart then Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, aimPart.Position), 0.3) end end
        local targetSpeed = 16; if Config.SpeedEnabled then targetSpeed = Config.WalkSpeed end; if hum.WalkSpeed ~= targetSpeed then hum.WalkSpeed = targetSpeed end
    end
end)

RunService.Stepped:Connect(function()
    if Config.NoclipEnabled then
        local char = LocalPlayer.Character
        if char then
            for _, p in pairs(char:GetDescendants()) do
                if p:IsA("BasePart") then
                    if noclipOriginalStates[p] == nil then noclipOriginalStates[p] = p.CanCollide end
                    p.CanCollide = false
                end
            end
        end
    else
        for part, original in pairs(noclipOriginalStates) do
            if part and part.Parent then part.CanCollide = original end
        end
        noclipOriginalStates = {}
    end
end)

UserInputService.JumpRequest:Connect(function() if Config.InfJumpEnabled and LocalPlayer.Character then LocalPlayer.Character:FindFirstChildOfClass("Humanoid"):ChangeState("Jumping") end end)

Bind(UserInputService.InputBegan, function(input) if input.UserInputType == MOUSE1 or input.UserInputType == TOUCH then for _, d in ipairs(dragObjects) do d.Moved = false end end end)
Bind(UserInputService.InputChanged, function(input) for _, d in ipairs(dragObjects) do d.OnChanged(input) end end)
Bind(UserInputService.InputEnded, function(input) if input.UserInputType == MOUSE1 or input.UserInputType == TOUCH then for fn in pairs(pressedFx) do pressedFx[fn] = nil; fn() end end; for _, d in ipairs(dragObjects) do d.OnEnded(input) end end)
ScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() for _, d in ipairs(dragObjects) do d.Reclamp() end end)
ScreenGui.Destroying:Connect(function() for _, c in ipairs(connections) do c:Disconnect() end; connections = {}; for _, d in ipairs(dragObjects) do d.Destroy() end end)

Mount(ScreenGui)
Tween(ToggleScale, 0.6, {Scale = 1}, EASE.Back, DIR.Out)
