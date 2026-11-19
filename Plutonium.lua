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
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    local CONFIG = {
        ToggleKey = Enum.KeyCode.F,
        UpKeys = { Enum.KeyCode.Space, Enum.KeyCode.E },
        DownKeys = { Enum.KeyCode.LeftControl, Enum.KeyCode.Q },
        MinSpeed = 20,
        MaxSpeed = 150,
        StartSpeed = 60,
        Smoothing = 5,
        TurnResponsiveness = 35,
        TiltForward = 3.0,
        TiltBackward = 0.7,
        TiltSide = 0.55,
        FovBoost = 14,
        ExitTime = 0.45,
        ShowVerticalButtons = UserInputService.TouchEnabled,
    }

    local THEME = {
        Accent = Color3.fromRGB(120, 200, 255),
        Dark = Color3.fromRGB(20, 22, 28),
        White = Color3.new(1, 1, 1),
    }

    local speed = CONFIG.StartSpeed
    local upHeld, downHeld = false, false
    local flying, exiting, busy = false, false, false
    local vel, idleBlend, wasMoving = Vector3.zero, 1, false
    local lastFlat = Vector3.new(0, 0, -1)
    local exitUntil, baseFov, fov = 0, 70, 70
    local stepConn, diedConn
    local flyHum, flyHrp, prevAutoRotate
    local linVel, alignOri
    local trailList, fxList = {}, {}
    local hintShown = false

    local function create(className, props, children)
        local inst = Instance.new(className)
        local parent
        for key, value in pairs(props or {}) do
            if key == "Parent" then parent = value else inst[key] = value end
        end
        for _, child in ipairs(children or {}) do child.Parent = inst end
        inst.Parent = parent
        return inst
    end

    local function tween(obj, duration, goal, style, direction)
        local info = TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
        local t = TweenService:Create(obj, info, goal)
        t:Play()
        return t
    end

    local function isPointer(input)
        return input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
    end

    local function smooth(rate, dt)
        return 1 - math.exp(-rate * dt)
    end

    local controls
    do
        local ok, result = pcall(function()
            local module = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)
            return require(module):GetControls()
        end)
        if ok then controls = result end
    end

    local function getMoveVector()
        if controls then return controls:GetMoveVector() end
        local x = (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
        local z = (UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
        return Vector3.new(x, 0, z)
    end

    local function anyKeyDown(keys)
        for _, key in ipairs(keys) do
            if UserInputService:IsKeyDown(key) then return true end
        end
        return false
    end

    local function verticalInput()
        local up, down = upHeld, downHeld
        if not UserInputService:GetFocusedTextBox() then
            up = up or anyKeyDown(CONFIG.UpKeys)
            down = down or anyKeyDown(CONFIG.DownKeys)
        end
        return (up and 1 or 0) - (down and 1 or 0)
    end

    -- ================= GUI =================
    local oldGui = PlayerGui:FindFirstChild("FlyGui") or (game:GetService("CoreGui") and game:GetService("CoreGui"):FindFirstChild("FlyGui"))
    if oldGui then oldGui:Destroy() end

    local gui = create("ScreenGui", {
        Name = "FlyGui",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 999999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Enabled = false,
    })
    pcall(function() gui.Parent = game:GetService("CoreGui") end)
    if not gui.Parent then gui.Parent = PlayerGui end
    FlySystem.Gui = gui

    local function makeButton(parent, size, text, textSize, position)
        local button = create("TextButton", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = position,
            Size = UDim2.fromOffset(size, size),
            BackgroundColor3 = THEME.Dark,
            BackgroundTransparency = 0.3,
            AutoButtonColor = false,
            Text = text,
            TextColor3 = THEME.White,
            TextTransparency = 0.1,
            TextSize = textSize,
            Font = Enum.Font.GothamMedium,
            Parent = parent,
        })
        create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = button })
        local stroke = create("UIStroke", {
            Color = THEME.White,
            Transparency = 0.82,
            Thickness = 1.5,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Parent = button,
        })
        local scale = create("UIScale", { Parent = button })
        button.InputBegan:Connect(function(input)
            if isPointer(input) then tween(scale, 0.1, { Scale = 0.88 }) end
        end)
        button.InputEnded:Connect(function(input)
            if isPointer(input) then tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back) end
        end)
        return button, stroke
    end

    local function bindHold(button, setHeld)
        local active
        button.InputBegan:Connect(function(input)
            if isPointer(input) and not active then active = input; setHeld(true) end
        end)
        button.InputEnded:Connect(function(input)
            if isPointer(input) then active = nil; setHeld(false) end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if active and input == active then active = nil; setHeld(false) end
        end)
    end

    local holder = create("Frame", {
        Name = "Holder",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 16, 0.5, 60),
        Size = UDim2.fromOffset(52, 52),
        BackgroundTransparency = 1,
        Parent = gui,
    })
    local mainBtn, mainStroke = makeButton(holder, 52, "FLY", 13, UDim2.fromScale(0.5, 0.5))

    local vertical, upBtn, downBtn
    if CONFIG.ShowVerticalButtons then
        vertical = create("CanvasGroup", {
            Name = "Vertical",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(60, 160),
            BackgroundTransparency = 1,
            GroupTransparency = 1,
            Visible = false,
            Parent = holder,
        })
        upBtn = makeButton(vertical, 34, "▲", 12, UDim2.new(0.5, 0, 0.5, -50))
        downBtn = makeButton(vertical, 34, "▼", 12, UDim2.new(0.5, 0, 0.5, 50))
        bindHold(upBtn, function(v) upHeld = v end)
        bindHold(downBtn, function(v) downHeld = v end)
    end

    local gearBtn = makeButton(holder, 28, "•••", 11, UDim2.new(0, 74, 0.5, 0))
    gearBtn.BackgroundTransparency = 0.55
    gearBtn.TextTransparency = 0.3

    local panel = create("CanvasGroup", {
        Name = "SpeedPanel",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 96, 0.5, 0),
        Size = UDim2.fromOffset(170, 52),
        BackgroundColor3 = THEME.Dark,
        BackgroundTransparency = 0.3,
        GroupTransparency = 1,
        Visible = false,
        Parent = holder,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 14) }),
        create("UIStroke", {
            Color = THEME.White,
            Transparency = 0.85,
            Thickness = 1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }),
    })

    local speedLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 8),
        Size = UDim2.new(1, -28, 0, 16),
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = THEME.White,
        TextTransparency = 0.15,
        Text = "",
        Parent = panel,
    })
    local track = create("Frame", {
        Position = UDim2.new(0, 14, 0, 36),
        Size = UDim2.new(1, -28, 0, 4),
        BackgroundColor3 = THEME.White,
        BackgroundTransparency = 0.82,
        BorderSizePixel = 0,
        Parent = panel,
    }, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local fill = create("Frame", {
        Size = UDim2.fromScale(0.5, 1),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        Parent = track,
    }, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = THEME.White,
        BorderSizePixel = 0,
        Parent = track,
    }, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local hit = create("TextButton", {
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Position = UDim2.new(0, 0, 0, 24),
        Size = UDim2.new(1, 0, 0, 28),
        Parent = panel,
    })

    local speedAlpha = (speed - CONFIG.MinSpeed) / (CONFIG.MaxSpeed - CONFIG.MinSpeed)
    local function setSpeed(alpha)
        speedAlpha = math.clamp(alpha, 0, 1)
        speed = math.floor(CONFIG.MinSpeed + (CONFIG.MaxSpeed - CONFIG.MinSpeed) * speedAlpha + 0.5)
        fill.Size = UDim2.fromScale(speedAlpha, 1)
        knob.Position = UDim2.fromScale(speedAlpha, 0.5)
        speedLabel.Text = "Скорость · " .. speed
    end
    setSpeed(speedAlpha)

    local dragging = false
    hit.InputBegan:Connect(function(input)
        if isPointer(input) then
            dragging = true
            tween(knob, 0.15, { Size = UDim2.fromOffset(16, 16) }, Enum.EasingStyle.Back)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local trackX = track.AbsolutePosition.X
            local trackW = math.max(track.AbsoluteSize.X, 1)
            setSpeed((input.Position.X - trackX) / trackW)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if dragging and isPointer(input) then
            dragging = false
            tween(knob, 0.2, { Size = UDim2.fromOffset(12, 12) })
        end
    end)

    local panelOpen = false
    gearBtn.Activated:Connect(function()
        panelOpen = not panelOpen
        if panelOpen then
            panel.Visible = true
            panel.Position = UDim2.new(0, 88, 0.5, 0)
            tween(panel, 0.25, { GroupTransparency = 0, Position = UDim2.new(0, 96, 0.5, 0) })
            tween(gearBtn, 0.2, { TextColor3 = THEME.Accent })
        else
            tween(panel, 0.2, { GroupTransparency = 1, Position = UDim2.new(0, 88, 0.5, 0) })
            tween(gearBtn, 0.2, { TextColor3 = THEME.White })
            task.delay(0.2, function() if not panelOpen then panel.Visible = false end end)
        end
    end)

    local toastGroup = create("CanvasGroup", {
        Name = "Toast",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 64),
        Size = UDim2.fromOffset(290, 34),
        BackgroundColor3 = THEME.Dark,
        BackgroundTransparency = 0.25,
        GroupTransparency = 1,
        Parent = gui,
    }, {
        create("UICorner", { CornerRadius = UDim.new(1, 0) }),
        create("UIStroke", {
            Color = THEME.White,
            Transparency = 0.85,
            Thickness = 1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }),
    })
    local toastLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = THEME.White,
        Text = "",
        Parent = toastGroup,
    })

    local toastToken = 0
    local function toast(text, duration)
        toastToken = toastToken + 1
        local myToken = toastToken
        toastLabel.Text = text
        toastGroup.Position = UDim2.new(0.5, 0, 0, 54)
        tween(toastGroup, 0.3, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 0, 64) })
        task.delay(duration or 2.2, function()
            if toastToken == myToken then tween(toastGroup, 0.3, { GroupTransparency = 1 }) end
        end)
    end

    local pulse
    local visualToken = 0
    local function setActiveVisual(on)
        visualToken = visualToken + 1
        local myToken = visualToken
        if pulse then pulse:Cancel(); pulse = nil end

        if on then
            tween(mainBtn, 0.25, { TextColor3 = THEME.Accent, BackgroundTransparency = 0.15 })
            tween(mainStroke, 0.25, { Color = THEME.Accent, Transparency = 0.1, Thickness = 2 })
            task.delay(0.28, function()
                if myToken ~= visualToken then return end
                pulse = TweenService:Create(mainStroke,
                    TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
                    { Transparency = 0.65 })
                pulse:Play()
            end)
            if vertical then
                vertical.Visible = true
                tween(vertical, 0.3, { GroupTransparency = 0 })
                tween(upBtn, 0.35, { Position = UDim2.new(0.5, 0, 0.5, -50) }, Enum.EasingStyle.Back)
                tween(downBtn, 0.35, { Position = UDim2.new(0.5, 0, 0.5, 50) }, Enum.EasingStyle.Back)
            end
        else
            tween(mainBtn, 0.25, { TextColor3 = THEME.White, BackgroundTransparency = 0.3 })
            tween(mainStroke, 0.25, { Color = THEME.White, Transparency = 0.82, Thickness = 1.5 })
            if vertical then
                tween(vertical, 0.25, { GroupTransparency = 1 })
                tween(upBtn, 0.25, { Position = UDim2.fromScale(0.5, 0.5) })
                tween(downBtn, 0.25, { Position = UDim2.fromScale(0.5, 0.5) })
                task.delay(0.26, function() if myToken == visualToken then vertical.Visible = false end end)
            end
        end
    end

    local function makeTrail(hrp, side)
        local a0 = create("Attachment", { Position = Vector3.new(1.5 * side, 0.25, 0.3), Parent = hrp })
        local a1 = create("Attachment", { Position = Vector3.new(1.5 * side, -0.25, 0.3), Parent = hrp })
        local trail = create("Trail", {
            Attachment0 = a0,
            Attachment1 = a1,
            Lifetime = 0.5,
            MinLength = 0.05,
            FaceCamera = true,
            LightEmission = 0.7,
            Enabled = false,
            Color = ColorSequence.new(THEME.Accent, THEME.White),
            Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }),
            WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
            Parent = hrp,
        })
        table.insert(fxList, a0); table.insert(fxList, a1); table.insert(fxList, trail)
        table.insert(trailList, trail)
    end

    local function finalize(hard)
        if not flying then return end
        flying, exiting = false, false
        Config.FlyEnabled = false
        if stepConn then stepConn:Disconnect(); stepConn = nil end
        if diedConn then diedConn:Disconnect(); diedConn = nil end
        for _, inst in ipairs(fxList) do inst:Destroy() end
        fxList, trailList, linVel, alignOri = {}, {}, nil, nil
        local hum = flyHum
        if hum and hum.Parent then
            hum.PlatformStand = false
            if prevAutoRotate ~= nil then hum.AutoRotate = prevAutoRotate end
            if hum.Health > 0 then hum:ChangeState(Enum.HumanoidStateType.Freefall) end
        end
        flyHum, flyHrp = nil, nil
        local cam = workspace.CurrentCamera
        if cam then cam.FieldOfView = baseFov end
        upHeld, downHeld = false, false
        if hard then setActiveVisual(false) end
    end

    local function step(dt)
        local hum, hrp, cam = flyHum, flyHrp, workspace.CurrentCamera
        if not (hum and hrp and cam and linVel and alignOri) or not hrp.Parent or hum.Health <= 0 then
            finalize(true); return
        end
        local camCF = cam.CFrame
        local move = getMoveVector()
        local dir = Vector3.zero
        if not exiting then
            dir = camCF.RightVector * move.X - camCF.LookVector * move.Z + Vector3.yAxis * verticalInput()
            if dir.Magnitude > 1 then dir = dir.Unit end
        end
        vel = vel:Lerp(dir * speed, smooth(exiting and 9 or CONFIG.Smoothing, dt))

        local idle = (not exiting) and dir.Magnitude < 0.05
        idleBlend = idleBlend + ((idle and 1 or 0) - idleBlend) * smooth(4, dt)
        local bob = math.sin(os.clock() * 2.2) * 0.9 * idleBlend
        linVel.VectorVelocity = vel + Vector3.new(0, bob, 0)

        local look = camCF.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude > 0.05 then lastFlat = flat.Unit end
        local yaw = CFrame.lookAt(Vector3.zero, lastFlat)
        local tilt = Vector3.zero
        if not exiting then
            local localVel = yaw:VectorToObjectSpace(vel)
            local ref = math.max(speed, 1)
            local f = math.clamp(-localVel.Z / ref, -1, 1)
            local s = math.clamp(localVel.X / ref, -1, 1)
            local k = (f >= 0) and CONFIG.TiltForward or CONFIG.TiltBackward
            tilt = lastFlat * (f * k) + yaw.RightVector * (s * CONFIG.TiltSide)
        end
        local up = (Vector3.yAxis + tilt).Unit
        local face = (lastFlat - up * lastFlat:Dot(up)).Unit
        alignOri.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + face, up)

        local ratio = math.clamp(vel.Magnitude / CONFIG.MaxSpeed, 0, 1)
        fov = fov + (baseFov + CONFIG.FovBoost * ratio - fov) * smooth(6, dt)
        cam.FieldOfView = fov

        local fast = vel.Magnitude > 12
        for _, trail in ipairs(trailList) do trail.Enabled = fast end

        if exiting and os.clock() >= exitUntil then finalize(false) end
    end

    local function startFly()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local cam = workspace.CurrentCamera
        if not (hum and hrp and cam) or hum.Health <= 0 then return false end

        flyHum, flyHrp = hum, hrp
        prevAutoRotate = hum.AutoRotate
        hum.PlatformStand = true
        hum.AutoRotate = false

        vel = hrp.AssemblyLinearVelocity * 0.2
        idleBlend, wasMoving = 1, false
        baseFov = cam.FieldOfView
        fov = baseFov

        local look = hrp.CFrame.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        lastFlat = (flat.Magnitude > 0.05) and flat.Unit or Vector3.new(0, 0, -1)

        local attachment = create("Attachment", { Name = "FlyAttachment", Parent = hrp })
        linVel = create("LinearVelocity", {
            Name = "FlyVelocity",
            Attachment0 = attachment,
            VelocityConstraintMode = Enum.VelocityConstraintMode.Vector,
            MaxForce = math.huge,
            VectorVelocity = vel,
            Parent = hrp,
        })
        alignOri = create("AlignOrientation", {
            Name = "FlyOrientation",
            Attachment0 = attachment,
            Mode = Enum.OrientationAlignmentMode.OneAttachment,
            RigidityEnabled = false,
            MaxTorque = math.huge,
            MaxAngularVelocity = math.huge,
            Responsiveness = CONFIG.TurnResponsiveness,
            CFrame = hrp.CFrame.Rotation,
            Parent = hrp,
        })
        table.insert(fxList, attachment)
        table.insert(fxList, linVel)
        table.insert(fxList, alignOri)
        makeTrail(hrp, -1)
        makeTrail(hrp, 1)

        flying, exiting = true, false
        Config.FlyEnabled = true
        diedConn = hum.Died:Connect(function() finalize(true) end)
        stepConn = RunService.RenderStepped:Connect(step)
        setActiveVisual(true)

        if not hintShown and not UserInputService.TouchEnabled then
            hintShown = true
            toast("Space ▲  ·  Ctrl ▼  ·  F — выкл", 3)
        end
        return true
    end

    local function beginExit()
        if not flying or exiting then return end
        exiting = true
        exitUntil = os.clock() + CONFIG.ExitTime
        upHeld, downHeld = false, false
        setActiveVisual(false)
    end

    local function toggle()
        if busy or exiting then return end
        if flying then beginExit(); return end
        busy = true
        local ok, err = pcall(startFly)
        busy = false
        if not ok then warn("[Fly] " .. tostring(err)) end
    end

    mainBtn.Activated:Connect(toggle)

    UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and input.KeyCode == CONFIG.ToggleKey then toggle() end
    end)

    LocalPlayer.CharacterAdded:Connect(function() finalize(true) end)
    LocalPlayer.CharacterRemoving:Connect(function() finalize(true) end)

    FlySystem.Stop = finalize
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
Tween(ToggleScale, 0.6, {Scale = 1}, EASE.Back, DIR.Out) local Players = game:GetService("Players")
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
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    local CONFIG = {
        ToggleKey = Enum.KeyCode.F,
        UpKeys = { Enum.KeyCode.Space, Enum.KeyCode.E },
        DownKeys = { Enum.KeyCode.LeftControl, Enum.KeyCode.Q },
        MinSpeed = 20,
        MaxSpeed = 150,
        StartSpeed = 60,
        Smoothing = 5,
        TurnResponsiveness = 35,
        TiltForward = 3.0,
        TiltBackward = 0.7,
        TiltSide = 0.55,
        FovBoost = 14,
        ExitTime = 0.45,
        ShowVerticalButtons = UserInputService.TouchEnabled,
    }

    local THEME = {
        Accent = Color3.fromRGB(120, 200, 255),
        Dark = Color3.fromRGB(20, 22, 28),
        White = Color3.new(1, 1, 1),
    }

    local speed = CONFIG.StartSpeed
    local upHeld, downHeld = false, false
    local flying, exiting, busy = false, false, false
    local vel, idleBlend, wasMoving = Vector3.zero, 1, false
    local lastFlat = Vector3.new(0, 0, -1)
    local exitUntil, baseFov, fov = 0, 70, 70
    local stepConn, diedConn
    local flyHum, flyHrp, prevAutoRotate
    local linVel, alignOri
    local trailList, fxList = {}, {}
    local hintShown = false

    local function create(className, props, children)
        local inst = Instance.new(className)
        local parent
        for key, value in pairs(props or {}) do
            if key == "Parent" then parent = value else inst[key] = value end
        end
        for _, child in ipairs(children or {}) do child.Parent = inst end
        inst.Parent = parent
        return inst
    end

    local function tween(obj, duration, goal, style, direction)
        local info = TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
        local t = TweenService:Create(obj, info, goal)
        t:Play()
        return t
    end

    local function isPointer(input)
        return input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
    end

    local function smooth(rate, dt)
        return 1 - math.exp(-rate * dt)
    end

    local controls
    do
        local ok, result = pcall(function()
            local module = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)
            return require(module):GetControls()
        end)
        if ok then controls = result end
    end

    local function getMoveVector()
        if controls then return controls:GetMoveVector() end
        local x = (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
        local z = (UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
        return Vector3.new(x, 0, z)
    end

    local function anyKeyDown(keys)
        for _, key in ipairs(keys) do
            if UserInputService:IsKeyDown(key) then return true end
        end
        return false
    end

    local function verticalInput()
        local up, down = upHeld, downHeld
        if not UserInputService:GetFocusedTextBox() then
            up = up or anyKeyDown(CONFIG.UpKeys)
            down = down or anyKeyDown(CONFIG.DownKeys)
        end
        return (up and 1 or 0) - (down and 1 or 0)
    end

    -- ================= GUI =================
    local oldGui = PlayerGui:FindFirstChild("FlyGui") or (game:GetService("CoreGui") and game:GetService("CoreGui"):FindFirstChild("FlyGui"))
    if oldGui then oldGui:Destroy() end

    local gui = create("ScreenGui", {
        Name = "FlyGui",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 999999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Enabled = false,
    })
    pcall(function() gui.Parent = game:GetService("CoreGui") end)
    if not gui.Parent then gui.Parent = PlayerGui end
    FlySystem.Gui = gui

    local function makeButton(parent, size, text, textSize, position)
        local button = create("TextButton", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = position,
            Size = UDim2.fromOffset(size, size),
            BackgroundColor3 = THEME.Dark,
            BackgroundTransparency = 0.3,
            AutoButtonColor = false,
            Text = text,
            TextColor3 = THEME.White,
            TextTransparency = 0.1,
            TextSize = textSize,
            Font = Enum.Font.GothamMedium,
            Parent = parent,
        })
        create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = button })
        local stroke = create("UIStroke", {
            Color = THEME.White,
            Transparency = 0.82,
            Thickness = 1.5,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Parent = button,
        })
        local scale = create("UIScale", { Parent = button })
        button.InputBegan:Connect(function(input)
            if isPointer(input) then tween(scale, 0.1, { Scale = 0.88 }) end
        end)
        button.InputEnded:Connect(function(input)
            if isPointer(input) then tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back) end
        end)
        return button, stroke
    end

    local function bindHold(button, setHeld)
        local active
        button.InputBegan:Connect(function(input)
            if isPointer(input) and not active then active = input; setHeld(true) end
        end)
        button.InputEnded:Connect(function(input)
            if isPointer(input) then active = nil; setHeld(false) end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if active and input == active then active = nil; setHeld(false) end
        end)
    end

    local holder = create("Frame", {
        Name = "Holder",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 16, 0.5, 60),
        Size = UDim2.fromOffset(52, 52),
        BackgroundTransparency = 1,
        Parent = gui,
    })
    local mainBtn, mainStroke = makeButton(holder, 52, "FLY", 13, UDim2.fromScale(0.5, 0.5))

    local vertical, upBtn, downBtn
    if CONFIG.ShowVerticalButtons then
        vertical = create("CanvasGroup", {
            Name = "Vertical",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(60, 160),
            BackgroundTransparency = 1,
            GroupTransparency = 1,
            Visible = false,
            Parent = holder,
        })
        upBtn = makeButton(vertical, 34, "▲", 12, UDim2.new(0.5, 0, 0.5, -50))
        downBtn = makeButton(vertical, 34, "▼", 12, UDim2.new(0.5, 0, 0.5, 50))
        bindHold(upBtn, function(v) upHeld = v end)
        bindHold(downBtn, function(v) downHeld = v end)
    end

    local gearBtn = makeButton(holder, 28, "•••", 11, UDim2.new(0, 74, 0.5, 0))
    gearBtn.BackgroundTransparency = 0.55
    gearBtn.TextTransparency = 0.3

    local panel = create("CanvasGroup", {
        Name = "SpeedPanel",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 96, 0.5, 0),
        Size = UDim2.fromOffset(170, 52),
        BackgroundColor3 = THEME.Dark,
        BackgroundTransparency = 0.3,
        GroupTransparency = 1,
        Visible = false,
        Parent = holder,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 14) }),
        create("UIStroke", {
            Color = THEME.White,
            Transparency = 0.85,
            Thickness = 1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }),
    })

    local speedLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 8),
        Size = UDim2.new(1, -28, 0, 16),
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = THEME.White,
        TextTransparency = 0.15,
        Text = "",
        Parent = panel,
    })
    local track = create("Frame", {
        Position = UDim2.new(0, 14, 0, 36),
        Size = UDim2.new(1, -28, 0, 4),
        BackgroundColor3 = THEME.White,
        BackgroundTransparency = 0.82,
        BorderSizePixel = 0,
        Parent = panel,
    }, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local fill = create("Frame", {
        Size = UDim2.fromScale(0.5, 1),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        Parent = track,
    }, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = THEME.White,
        BorderSizePixel = 0,
        Parent = track,
    }, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local hit = create("TextButton", {
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Position = UDim2.new(0, 0, 0, 24),
        Size = UDim2.new(1, 0, 0, 28),
        Parent = panel,
    })

    local speedAlpha = (speed - CONFIG.MinSpeed) / (CONFIG.MaxSpeed - CONFIG.MinSpeed)
    local function setSpeed(alpha)
        speedAlpha = math.clamp(alpha, 0, 1)
        speed = math.floor(CONFIG.MinSpeed + (CONFIG.MaxSpeed - CONFIG.MinSpeed) * speedAlpha + 0.5)
        fill.Size = UDim2.fromScale(speedAlpha, 1)
        knob.Position = UDim2.fromScale(speedAlpha, 0.5)
        speedLabel.Text = "Скорость · " .. speed
    end
    setSpeed(speedAlpha)

    local dragging = false
    hit.InputBegan:Connect(function(input)
        if isPointer(input) then
            dragging = true
            tween(knob, 0.15, { Size = UDim2.fromOffset(16, 16) }, Enum.EasingStyle.Back)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local trackX = track.AbsolutePosition.X
            local trackW = math.max(track.AbsoluteSize.X, 1)
            setSpeed((input.Position.X - trackX) / trackW)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if dragging and isPointer(input) then
            dragging = false
            tween(knob, 0.2, { Size = UDim2.fromOffset(12, 12) })
        end
    end)

    local panelOpen = false
    gearBtn.Activated:Connect(function()
        panelOpen = not panelOpen
        if panelOpen then
            panel.Visible = true
            panel.Position = UDim2.new(0, 88, 0.5, 0)
            tween(panel, 0.25, { GroupTransparency = 0, Position = UDim2.new(0, 96, 0.5, 0) })
            tween(gearBtn, 0.2, { TextColor3 = THEME.Accent })
        else
            tween(panel, 0.2, { GroupTransparency = 1, Position = UDim2.new(0, 88, 0.5, 0) })
            tween(gearBtn, 0.2, { TextColor3 = THEME.White })
            task.delay(0.2, function() if not panelOpen then panel.Visible = false end end)
        end
    end)

    local toastGroup = create("CanvasGroup", {
        Name = "Toast",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 64),
        Size = UDim2.fromOffset(290, 34),
        BackgroundColor3 = THEME.Dark,
        BackgroundTransparency = 0.25,
        GroupTransparency = 1,
        Parent = gui,
    }, {
        create("UICorner", { CornerRadius = UDim.new(1, 0) }),
        create("UIStroke", {
            Color = THEME.White,
            Transparency = 0.85,
            Thickness = 1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }),
    })
    local toastLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = THEME.White,
        Text = "",
        Parent = toastGroup,
    })

    local toastToken = 0
    local function toast(text, duration)
        toastToken = toastToken + 1
        local myToken = toastToken
        toastLabel.Text = text
        toastGroup.Position = UDim2.new(0.5, 0, 0, 54)
        tween(toastGroup, 0.3, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 0, 64) })
        task.delay(duration or 2.2, function()
            if toastToken == myToken then tween(toastGroup, 0.3, { GroupTransparency = 1 }) end
        end)
    end

    local pulse
    local visualToken = 0
    local function setActiveVisual(on)
        visualToken = visualToken + 1
        local myToken = visualToken
        if pulse then pulse:Cancel(); pulse = nil end

        if on then
            tween(mainBtn, 0.25, { TextColor3 = THEME.Accent, BackgroundTransparency = 0.15 })
            tween(mainStroke, 0.25, { Color = THEME.Accent, Transparency = 0.1, Thickness = 2 })
            task.delay(0.28, function()
                if myToken ~= visualToken then return end
                pulse = TweenService:Create(mainStroke,
                    TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
                    { Transparency = 0.65 })
                pulse:Play()
            end)
            if vertical then
                vertical.Visible = true
                tween(vertical, 0.3, { GroupTransparency = 0 })
                tween(upBtn, 0.35, { Position = UDim2.new(0.5, 0, 0.5, -50) }, Enum.EasingStyle.Back)
                tween(downBtn, 0.35, { Position = UDim2.new(0.5, 0, 0.5, 50) }, Enum.EasingStyle.Back)
            end
        else
            tween(mainBtn, 0.25, { TextColor3 = THEME.White, BackgroundTransparency = 0.3 })
            tween(mainStroke, 0.25, { Color = THEME.White, Transparency = 0.82, Thickness = 1.5 })
            if vertical then
                tween(vertical, 0.25, { GroupTransparency = 1 })
                tween(upBtn, 0.25, { Position = UDim2.fromScale(0.5, 0.5) })
                tween(downBtn, 0.25, { Position = UDim2.fromScale(0.5, 0.5) })
                task.delay(0.26, function() if myToken == visualToken then vertical.Visible = false end end)
            end
        end
    end

    local function makeTrail(hrp, side)
        local a0 = create("Attachment", { Position = Vector3.new(1.5 * side, 0.25, 0.3), Parent = hrp })
        local a1 = create("Attachment", { Position = Vector3.new(1.5 * side, -0.25, 0.3), Parent = hrp })
        local trail = create("Trail", {
            Attachment0 = a0,
            Attachment1 = a1,
            Lifetime = 0.5,
            MinLength = 0.05,
            FaceCamera = true,
            LightEmission = 0.7,
            Enabled = false,
            Color = ColorSequence.new(THEME.Accent, THEME.White),
            Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }),
            WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
            Parent = hrp,
        })
        table.insert(fxList, a0); table.insert(fxList, a1); table.insert(fxList, trail)
        table.insert(trailList, trail)
    end

    local function finalize(hard)
        if not flying then return end
        flying, exiting = false, false
        Config.FlyEnabled = false
        if stepConn then stepConn:Disconnect(); stepConn = nil end
        if diedConn then diedConn:Disconnect(); diedConn = nil end
        for _, inst in ipairs(fxList) do inst:Destroy() end
        fxList, trailList, linVel, alignOri = {}, {}, nil, nil
        local hum = flyHum
        if hum and hum.Parent then
            hum.PlatformStand = false
            if prevAutoRotate ~= nil then hum.AutoRotate = prevAutoRotate end
            if hum.Health > 0 then hum:ChangeState(Enum.HumanoidStateType.Freefall) end
        end
        flyHum, flyHrp = nil, nil
        local cam = workspace.CurrentCamera
        if cam then cam.FieldOfView = baseFov end
        upHeld, downHeld = false, false
        if hard then setActiveVisual(false) end
    end

    local function step(dt)
        local hum, hrp, cam = flyHum, flyHrp, workspace.CurrentCamera
        if not (hum and hrp and cam and linVel and alignOri) or not hrp.Parent or hum.Health <= 0 then
            finalize(true); return
        end
        local camCF = cam.CFrame
        local move = getMoveVector()
        local dir = Vector3.zero
        if not exiting then
            dir = camCF.RightVector * move.X - camCF.LookVector * move.Z + Vector3.yAxis * verticalInput()
            if dir.Magnitude > 1 then dir = dir.Unit end
        end
        vel = vel:Lerp(dir * speed, smooth(exiting and 9 or CONFIG.Smoothing, dt))

        local idle = (not exiting) and dir.Magnitude < 0.05
        idleBlend = idleBlend + ((idle and 1 or 0) - idleBlend) * smooth(4, dt)
        local bob = math.sin(os.clock() * 2.2) * 0.9 * idleBlend
        linVel.VectorVelocity = vel + Vector3.new(0, bob, 0)

        local look = camCF.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude > 0.05 then lastFlat = flat.Unit end
        local yaw = CFrame.lookAt(Vector3.zero, lastFlat)
        local tilt = Vector3.zero
        if not exiting then
            local localVel = yaw:VectorToObjectSpace(vel)
            local ref = math.max(speed, 1)
            local f = math.clamp(-localVel.Z / ref, -1, 1)
            local s = math.clamp(localVel.X / ref, -1, 1)
            local k = (f >= 0) and CONFIG.TiltForward or CONFIG.TiltBackward
            tilt = lastFlat * (f * k) + yaw.RightVector * (s * CONFIG.TiltSide)
        end
        local up = (Vector3.yAxis + tilt).Unit
        local face = (lastFlat - up * lastFlat:Dot(up)).Unit
        alignOri.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + face, up)

        local ratio = math.clamp(vel.Magnitude / CONFIG.MaxSpeed, 0, 1)
        fov = fov + (baseFov + CONFIG.FovBoost * ratio - fov) * smooth(6, dt)
        cam.FieldOfView = fov

        local fast = vel.Magnitude > 12
        for _, trail in ipairs(trailList) do trail.Enabled = fast end

        if exiting and os.clock() >= exitUntil then finalize(false) end
    end

    local function startFly()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local cam = workspace.CurrentCamera
        if not (hum and hrp and cam) or hum.Health <= 0 then return false end

        flyHum, flyHrp = hum, hrp
        prevAutoRotate = hum.AutoRotate
        hum.PlatformStand = true
        hum.AutoRotate = false

        vel = hrp.AssemblyLinearVelocity * 0.2
        idleBlend, wasMoving = 1, false
        baseFov = cam.FieldOfView
        fov = baseFov

        local look = hrp.CFrame.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        lastFlat = (flat.Magnitude > 0.05) and flat.Unit or Vector3.new(0, 0, -1)

        local attachment = create("Attachment", { Name = "FlyAttachment", Parent = hrp })
        linVel = create("LinearVelocity", {
            Name = "FlyVelocity",
            Attachment0 = attachment,
            VelocityConstraintMode = Enum.VelocityConstraintMode.Vector,
            MaxForce = math.huge,
            VectorVelocity = vel,
            Parent = hrp,
        })
        alignOri = create("AlignOrientation", {
            Name = "FlyOrientation",
            Attachment0 = attachment,
            Mode = Enum.OrientationAlignmentMode.OneAttachment,
            RigidityEnabled = false,
            MaxTorque = math.huge,
            MaxAngularVelocity = math.huge,
            Responsiveness = CONFIG.TurnResponsiveness,
            CFrame = hrp.CFrame.Rotation,
            Parent = hrp,
        })
        table.insert(fxList, attachment)
        table.insert(fxList, linVel)
        table.insert(fxList, alignOri)
        makeTrail(hrp, -1)
        makeTrail(hrp, 1)

        flying, exiting = true, false
        Config.FlyEnabled = true
        diedConn = hum.Died:Connect(function() finalize(true) end)
        stepConn = RunService.RenderStepped:Connect(step)
        setActiveVisual(true)

        if not hintShown and not UserInputService.TouchEnabled then
            hintShown = true
            toast("Space ▲  ·  Ctrl ▼  ·  F — выкл", 3)
        end
        return true
    end

    local function beginExit()
        if not flying or exiting then return end
        exiting = true
        exitUntil = os.clock() + CONFIG.ExitTime
        upHeld, downHeld = false, false
        setActiveVisual(false)
    end

    local function toggle()
        if busy or exiting then return end
        if flying then beginExit(); return end
        busy = true
        local ok, err = pcall(startFly)
        busy = false
        if not ok then warn("[Fly] " .. tostring(err)) end
    end

    mainBtn.Activated:Connect(toggle)

    UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and input.KeyCode == CONFIG.ToggleKey then toggle() end
    end)

    LocalPlayer.CharacterAdded:Connect(function() finalize(true) end)
    LocalPlayer.CharacterRemoving:Connect(function() finalize(true) end)

    FlySystem.Stop = finalize
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
