-- JakonScripts | Universal FPS
-- Aimbot / Silent Aim / ESP / Fly / Speed / No Recoil, меню на RightShift.
-- Запуск: вставить целиком в executor, RightShift — открыть/закрыть меню.

if getgenv().JakonScripts_Loaded then
    pcall(function() getgenv().JakonScripts_Unload() end)
end
getgenv().JakonScripts_Loaded = true

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Palette = {
    bg        = Color3.fromHex("06060B"),
    accent    = Color3.fromHex("7C3AED"),
    accent2   = Color3.fromHex("C4B5FD"),
    icon      = Color3.fromHex("A78BFA"),
    text      = Color3.fromHex("FFFFFF"),
    text2     = Color3.fromHex("A1A1AA"),
    text3     = Color3.fromHex("71717A"),
    btn_text  = Color3.fromHex("09090B"),
}

local FontMain = Enum.Font.GothamMedium
local FontAlt  = Enum.Font.Gotham

local Config = {
    aimbot     = { enabled = false, fov = 120, smoothness = 0.20, part = "Head", team_check = true, visible_check = false, auto_shoot = false },
    silent     = { enabled = false, hit_chance = 100, team_check = true, wallbang = true },
    triggerbot = { enabled = false, delay = 0.05, team_check = true, visible_check = false },
    prediction = { enabled = false, value = 0.12 },
    esp        = { enabled = false, name = true, health = true, distance = true, max_distance = 600, team_color = true },
    speed      = { enabled = false, value = 32 },
    fly        = { enabled = false, speed = 60 },
    no_recoil  = { enabled = false },
}

local Connections = {}
local Highlights = {}
local Billboards = {}
local FovCircle = nil
local Gui = nil
local AimHeld = false
local TriggerLatched = false
local VirtualInputManager = nil
pcall(function() VirtualInputManager = game:GetService("VirtualInputManager") end)
local OldNamecall = nil
local RawMeta = nil
local MetaWasLocked = true
local RecoilBackup = {}

local function track(connection)
    table.insert(Connections, connection)
    return connection
end

-- ============================================================
-- ЦЕЛИ
-- ============================================================

local function is_valid_target(plr)
    if plr == LocalPlayer then return false end
    if Config.aimbot.team_check and plr.Team ~= nil and plr.Team == LocalPlayer.Team then return false end
    local char = plr.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    if not char:FindFirstChild("Head") then return false end
    return true
end

local function get_part(plr, part_name)
    local char = plr.Character
    if not char then return nil end
    local part = char:FindFirstChild(part_name) or char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
    return part
end

local function is_visible(part)
    if not Config.aimbot.visible_check then return true end
    local origin = Camera.CFrame.Position
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character }
    local result = Workspace:Raycast(origin, part.Position - origin, params)
    return result == nil or result.Instance:IsDescendantOf(part.Parent)
end

local function get_target()
    local mouse = UserInputService:GetMouseLocation()
    local best, best_dist = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if is_valid_target(plr) then
            local part = get_part(plr, Config.aimbot.part)
            if part then
                local screen, on_screen = Camera:WorldToViewportPoint(part.Position)
                if on_screen then
                    local dist = (Vector2.new(screen.X, screen.Y) - mouse).Magnitude
                    if dist <= Config.aimbot.fov and dist < best_dist then
                        if is_visible(part) then
                            best, best_dist = part, dist
                        end
                    end
                end
            end
        end
    end
    return best
end

local function get_velocity(part)
    if not Config.prediction.enabled then return Vector3.zero end
    local char = part.Parent
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and hum.MoveDirection.Magnitude > 0 then
        return hum.MoveDirection * hum.WalkSpeed * Config.prediction.value
    end
    return part.AssemblyLinearVelocity * Config.prediction.value
end

-- Прямая видимость цели от камеры.
local function has_line_of_sight(part)
    local origin = Camera.CFrame.Position
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character, Camera }
    local result = Workspace:Raycast(origin, part.Position - origin, params)
    return result == nil or result.Instance:IsDescendantOf(part.Parent)
end

-- Отдельный отбор для silent aim: без FOV-круга, по ближайшему к центру экрана.
local function get_silent_target()
    local center = Camera.ViewportSize / 2
    local best, best_dist = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local team_ok = not (Config.silent.team_check and plr.Team ~= nil and plr.Team == LocalPlayer.Team)
            if team_ok then
                local char = plr.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    local part = get_part(plr, Config.aimbot.part)
                    if part then
                        local screen, on_screen = Camera:WorldToViewportPoint(part.Position)
                        if on_screen then
                            local dist = (Vector2.new(screen.X, screen.Y) - center).Magnitude
                            if dist < best_dist then
                                best, best_dist = part, dist
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

-- ============================================================
-- UI
-- ============================================================

local function new(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props) do
        if k ~= "Parent" then inst[k] = v end
    end
    inst.Parent = parent
    return inst
end

local function add_corner(parent, radius)
    return new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function add_stroke(parent, color, transparency, thickness)
    return new("UIStroke", {
        Color = color or Palette.text,
        Transparency = transparency or 0.88,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, parent)
end

local function create_toggle(parent, label, default, callback)
    local row = new("Frame", {
        Name = "Row_" .. label,
        Size = UDim2.new(1, -16, 0, 34),
        BackgroundColor3 = Palette.text,
        BackgroundTransparency = 0.97,
        BorderSizePixel = 0,
    }, parent)
    add_corner(row, 12)
    new("UIStroke", { Color = Palette.text, Transparency = 0.94, Thickness = 1 }, row)

    new("TextLabel", {
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Font = FontMain,
        Text = label,
        TextColor3 = Palette.text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local switch = new("TextButton", {
        Size = UDim2.new(0, 30, 0, 16),
        Position = UDim2.new(1, -42, 0.5, -8),
        BackgroundColor3 = Palette.text,
        BackgroundTransparency = 0.88,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    }, row)
    add_corner(switch, 8)

    local knob = new("Frame", {
        Size = UDim2.new(0, 14, 0, 14),
        Position = UDim2.new(0, 1, 0.5, -7),
        BackgroundColor3 = Palette.text,
        BorderSizePixel = 0,
    }, switch)
    add_corner(knob, 7)

    local state = default

    local function render()
        local goal_color = state and Palette.accent or Palette.text
        local goal_bg = state and 0 or 0.88
        local goal_pos = state and UDim2.new(1, -15, 0.5, -7) or UDim2.new(0, 1, 0.5, -7)
        TweenService:Create(switch, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundColor3 = goal_color,
            BackgroundTransparency = goal_bg,
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = goal_pos,
        }):Play()
    end

    switch.MouseButton1Click:Connect(function()
        state = not state
        render()
        callback(state)
    end)

    render()
    return row
end

local function create_slider(parent, label, min, max, default, suffix, callback)
    local row = new("Frame", {
        Name = "Slider_" .. label,
        Size = UDim2.new(1, -16, 0, 42),
        BackgroundColor3 = Palette.text,
        BackgroundTransparency = 0.97,
        BorderSizePixel = 0,
    }, parent)
    add_corner(row, 12)
    new("UIStroke", { Color = Palette.text, Transparency = 0.94, Thickness = 1 }, row)

    new("TextLabel", {
        Size = UDim2.new(0.6, 0, 0, 16),
        Position = UDim2.new(0, 12, 0, 6),
        BackgroundTransparency = 1,
        Font = FontMain,
        Text = label,
        TextColor3 = Palette.text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local value_label = new("TextLabel", {
        Size = UDim2.new(0.4, -12, 0, 16),
        Position = UDim2.new(0.6, 0, 0, 6),
        BackgroundTransparency = 1,
        Font = FontAlt,
        Text = tostring(default) .. suffix,
        TextColor3 = Palette.text2,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, row)

    local track = new("Frame", {
        Size = UDim2.new(1, -24, 0, 4),
        Position = UDim2.new(0, 12, 1, -14),
        BackgroundColor3 = Palette.text,
        BackgroundTransparency = 0.92,
        BorderSizePixel = 0,
    }, row)
    add_corner(track, 2)

    local fill = new("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Palette.accent,
        BorderSizePixel = 0,
    }, track)
    add_corner(fill, 2)
    new("UIGradient", {
        Color = ColorSequence.new(Palette.accent, Palette.accent2),
    }, fill)

    local knob = new("Frame", {
        Size = UDim2.new(0, 12, 0, 12),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundColor3 = Palette.text,
        BorderSizePixel = 0,
        ZIndex = 3,
    }, track)
    add_corner(knob, 6)

    local value = default
    local dragging = false

    local function set_value(v)
        value = math.clamp(v, min, max)
        local alpha = (max - min) == 0 and 0 or (value - min) / (max - min)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        local shown = math.floor(value * 100 + 0.5) / 100
        if shown == math.floor(shown) then shown = math.floor(shown) end
        value_label.Text = tostring(shown) .. suffix
        callback(value)
    end

    track( knob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
        end
    end) )

    track( track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            local rel = (input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
            set_value(min + (max - min) * rel)
        end
    end) )

    track( UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local rel = (input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
            set_value(min + (max - min) * rel)
        end
    end) )

    track( UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end) )

    set_value(default)
    return row
end

local function create_button(parent, label, callback)
    local btn = new("TextButton", {
        Size = UDim2.new(1, -16, 0, 30),
        BackgroundColor3 = Palette.text,
        BackgroundTransparency = 0.92,
        BorderSizePixel = 0,
        Font = FontMain,
        Text = label,
        TextColor3 = Palette.text,
        TextSize = 13,
        AutoButtonColor = false,
    }, parent)
    add_corner(btn, 12)
    new("UIStroke", { Color = Palette.text, Transparency = 0.94, Thickness = 1 }, btn)

    track( btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundTransparency = 0.86 }):Play()
    end) )
    track( btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundTransparency = 0.92 }):Play()
    end) )
    track( btn.MouseButton1Click:Connect(callback) )
    return btn
end

local function create_label(parent, text, color, size)
    return new("TextLabel", {
        Size = UDim2.new(1, -16, 0, 18),
        BackgroundTransparency = 1,
        Font = FontMain,
        Text = text,
        TextColor3 = color or Palette.text3,
        TextSize = size or 10,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, parent)
end

local function create_page(parent)
    return new("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Palette.accent,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
    }, parent)
end

-- ============================================================
-- ФИЧИ
-- ============================================================

local function set_speed(state, value)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    hum.WalkSpeed = state and value or 16
end

local function clear_fly()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    for _, name in ipairs({ "JS_FlyVelocity", "JS_FlyGyro" }) do
        local inst = hrp:FindFirstChild(name)
        if inst then inst:Destroy() end
    end
end

local function setup_fly()
    clear_fly()
    if not Config.fly.enabled then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    pcall(function() hrp:SetNetworkOwner(LocalPlayer) end)

    local bv = new("BodyVelocity", {
        Name = "JS_FlyVelocity",
        MaxForce = Vector3.new(1e5, 1e5, 1e5),
        Velocity = Vector3.zero,
        P = 1250,
    }, hrp)

    new("BodyGyro", {
        Name = "JS_FlyGyro",
        MaxTorque = Vector3.new(1e5, 1e5, 1e5),
        P = 10000,
        D = 500,
        CFrame = hrp.CFrame,
    }, hrp)

    bv.Velocity = Vector3.zero
end

local function apply_no_recoil()
    RecoilBackup = {}
    local roots = { LocalPlayer.Character, Camera }
    for _, root in ipairs(roots) do
        if root then
            for _, inst in ipairs(root:GetDescendants()) do
                if inst:IsA("NumberValue") then
                    local lower = string.lower(inst.Name)
                    if string.find(lower, "recoil", 1, true) or string.find(lower, "kick", 1, true) then
                        if RecoilBackup[inst] == nil then
                            RecoilBackup[inst] = inst.Value
                        end
                        inst.Value = 0
                    end
                end
            end
        end
    end
end

local function undo_no_recoil()
    for inst, original in pairs(RecoilBackup) do
        if typeof(inst) == "Instance" and inst.Parent then
            inst.Value = original
        end
    end
    RecoilBackup = {}
end

local function clear_visuals()
    for _, highlight in pairs(Highlights) do
        if highlight and highlight.Parent then highlight:Destroy() end
    end
    for _, billboard in pairs(Billboards) do
        if billboard and billboard.Parent then billboard:Destroy() end
    end
    Highlights = {}
    Billboards = {}
end

local function refresh_esp(plr)
    if not Config.esp.enabled then return end
    local char = plr.Character
    local head = char and char:FindFirstChild("Head")
    if not head then return end

    if not Highlights[plr] or not Highlights[plr].Parent then
        local highlight = new("Highlight", {
            Name = "JS_ESP_" .. plr.Name,
            Adornee = char,
            FillTransparency = 0.72,
            OutlineTransparency = 0.15,
            DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
        }, char)
        if Config.esp.team_color and plr.Team then
            highlight.FillColor = plr.TeamColor.Color
            highlight.OutlineColor = plr.TeamColor.Color
        else
            highlight.FillColor = Palette.accent
            highlight.OutlineColor = Palette.accent2
        end
        Highlights[plr] = highlight
    end

    if not Billboards[plr] or not Billboards[plr].Parent then
        local bb = new("BillboardGui", {
            Name = "JS_BB_" .. plr.Name,
            Adornee = head,
            Size = UDim2.new(0, 140, 0, 42),
            StudsOffset = Vector3.new(0, 2.4, 0),
            AlwaysOnTop = true,
            MaxDistance = Config.esp.max_distance,
        }, head)

        new("TextLabel", {
            Name = "NameTag",
            Size = UDim2.new(1, 0, 0, 14),
            BackgroundTransparency = 1,
            Font = FontMain,
            Text = plr.Name,
            TextColor3 = Palette.text,
            TextSize = 12,
            TextStrokeTransparency = 0.6,
        }, bb)

        new("TextLabel", {
            Name = "HealthTag",
            Size = UDim2.new(1, 0, 0, 12),
            Position = UDim2.new(0, 0, 0, 14),
            BackgroundTransparency = 1,
            Font = FontAlt,
            Text = "HP 100",
            TextColor3 = Palette.accent2,
            TextSize = 10,
            TextStrokeTransparency = 0.6,
        }, bb)

        new("TextLabel", {
            Name = "DistTag",
            Size = UDim2.new(1, 0, 0, 12),
            Position = UDim2.new(0, 0, 0, 26),
            BackgroundTransparency = 1,
            Font = FontAlt,
            Text = "0m",
            TextColor3 = Palette.text2,
            TextSize = 10,
            TextStrokeTransparency = 0.6,
        }, bb)

        Billboards[plr] = bb
    end

    local bb = Billboards[plr]
    bb.MaxDistance = Config.esp.max_distance
    bb.NameTag.Visible = Config.esp.name
    bb.HealthTag.Visible = Config.esp.health
    bb.DistTag.Visible = Config.esp.distance

    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        bb.HealthTag.Text = string.format("HP %d", math.floor(hum.Health + 0.5))
    end

    local root = char:FindFirstChild("HumanoidRootPart") or head
    local distance = (root.Position - Camera.CFrame.Position).Magnitude
    bb.DistTag.Text = string.format("%dm", math.floor(distance + 0.5))
    bb.Enabled = distance <= Config.esp.max_distance
    if Highlights[plr] then
        Highlights[plr].Enabled = distance <= Config.esp.max_distance
    end
end

local function cleanup_player(plr)
    if Highlights[plr] then
        if Highlights[plr].Parent then Highlights[plr]:Destroy() end
        Highlights[plr] = nil
    end
    if Billboards[plr] then
        if Billboards[plr].Parent then Billboards[plr]:Destroy() end
        Billboards[plr] = nil
    end
end

-- ============================================================
-- SILENT AIM HOOK
-- ============================================================

local function install_silent_hook()
    if not (hookmetamethod and getrawmetatable and setreadonly) then return end
    RawMeta = getrawmetatable(game)
    if not RawMeta then return end
    OldNamecall = RawMeta.__namecall
    MetaWasLocked = not pcall(function() return isreadonly(RawMeta) end) or isreadonly(RawMeta)

    setreadonly(RawMeta, false)
    RawMeta.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if Config.silent.enabled and (method == "Raycast" or method == "FindPartOnRay"
            or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist") then
            local target = get_silent_target()
            if target and math.random(1, 100) <= Config.silent.hit_chance then
                local args = table.pack(...)
                if method == "Raycast" and typeof(args[1]) == "Vector3" and typeof(args[2]) == "Vector3" then
                    args[2] = target.Position - args[1]
                    return OldNamecall(self, table.unpack(args, 1, args.n))
                elseif typeof(args[1]) == "Ray" then
                    args[1] = Ray.new(args[1].Origin, target.Position - args[1].Origin)
                    return OldNamecall(self, table.unpack(args, 1, args.n))
                end
            end
        end
        return OldNamecall(self, ...)
    end)
    setreadonly(RawMeta, true)
end

local function remove_silent_hook()
    if RawMeta and OldNamecall then
        pcall(function()
            setreadonly(RawMeta, false)
            RawMeta.__namecall = OldNamecall
            setreadonly(RawMeta, MetaWasLocked)
        end)
    end
    RawMeta = nil
    OldNamecall = nil
end

-- ============================================================
-- ПОСТРОЕНИЕ МЕНЮ
-- ============================================================

local function build_ui()
    local parent = CoreGui
    local ok = pcall(function() return CoreGui:FindFirstChild("RobloxGui") ~= nil end)
    if not ok then parent = LocalPlayer:WaitForChild("PlayerGui") end

    Gui = new("ScreenGui", {
        Name = "JakonScripts",
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, parent)

    local main = new("Frame", {
        Name = "Main",
        Size = UDim2.new(0, 480, 0, 360),
        Position = UDim2.new(0.5, -240, 0.5, -180),
        BackgroundColor3 = Palette.bg,
        BackgroundTransparency = 0.12,
        BorderSizePixel = 0,
        Active = true,
    }, Gui)
    add_corner(main, 14)
    new("UIStroke", { Color = Palette.text, Transparency = 0.88, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, main)
    new("Frame", {
        Name = "TopEdge",
        Size = UDim2.new(1, -28, 0, 1),
        Position = UDim2.new(0, 14, 0, 0),
        BackgroundColor3 = Color3.fromHex("FFFFFF"),
        BackgroundTransparency = 0.87,
        BorderSizePixel = 0,
    }, main)

    local sidebar = new("Frame", {
        Name = "Sidebar",
        Size = UDim2.new(0, 150, 1, -16),
        Position = UDim2.new(0, 8, 0, 8),
        BackgroundColor3 = Palette.text,
        BackgroundTransparency = 0.96,
        BorderSizePixel = 0,
    }, main)
    add_corner(sidebar, 12)
    new("UIStroke", { Color = Palette.text, Transparency = 0.88, Thickness = 1 }, sidebar)

    new("TextLabel", {
        Name = "Logo",
        Size = UDim2.new(1, -20, 0, 20),
        Position = UDim2.new(0, 14, 0, 14),
        BackgroundTransparency = 1,
        Font = FontMain,
        Text = "— V A N T A",
        TextColor3 = Palette.text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, sidebar)

    local content = new("Frame", {
        Name = "Content",
        Size = UDim2.new(1, -166, 1, -16),
        Position = UDim2.new(0, 158, 0, 8),
        BackgroundTransparency = 1,
    }, main)

    local pages = {}
    local tabs = {}

    local tab_defs = {
        { key = "Combat",   glyph = "◎" },
        { key = "Visuals",  glyph = "◉" },
        { key = "Movement", glyph = "⚡" },
        { key = "Config",   glyph = "⚙" },
    }

    for index, def in ipairs(tab_defs) do
        local btn = new("TextButton", {
            Name = "Tab_" .. def.key,
            Size = UDim2.new(1, -20, 0, 30),
            Position = UDim2.new(0, 10, 0, 44 + (index - 1) * 34),
            BackgroundColor3 = Palette.accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Font = FontMain,
            Text = def.glyph .. "   " .. def.key,
            TextColor3 = Palette.text2,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            AutoButtonColor = false,
        }, sidebar)
        add_corner(btn, 12)
        new("UIPadding", { PaddingLeft = UDim.new(0, 12) }, btn)
        tabs[def.key] = btn
        pages[def.key] = create_page(content)
    end

    local function select_tab(key)
        for name, btn in pairs(tabs) do
            local active = (name == key)
            TweenService:Create(btn, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                BackgroundTransparency = active and 0.88 or 1,
                TextColor3 = active and Palette.text or Palette.text2,
            }):Play()
        end
        for name, page in pairs(pages) do
            page.Visible = (name == key)
        end
    end

    for name, btn in pairs(tabs) do
        track( btn.MouseButton1Click:Connect(function() select_tab(name) end) )
    end

    -- ---- COMBAT ----
    local combat = pages.Combat
    local function stack(page)
        return new("UIListLayout", {
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, page)
    end
    new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 8) }, combat)
    stack(combat)

    create_label(combat, "AIM", Palette.text3, 10)
    create_toggle(combat, "Aimbot", Config.aimbot.enabled, function(state)
        Config.aimbot.enabled = state
    end)
    create_toggle(combat, "Silent Aim", Config.silent.enabled, function(state)
        Config.silent.enabled = state
    end)
    create_slider(combat, "FOV", 20, 400, Config.aimbot.fov, "px", function(v)
        Config.aimbot.fov = v
    end)
    create_slider(combat, "Smoothness", 0.02, 0.9, Config.aimbot.smoothness, "", function(v)
        Config.aimbot.smoothness = v
    end)
    create_slider(combat, "Hit Chance", 1, 100, Config.silent.hit_chance, "%", function(v)
        Config.silent.hit_chance = v
    end)
    create_toggle(combat, "Team Check", Config.aimbot.team_check, function(state)
        Config.aimbot.team_check = state
        Config.silent.team_check = state
    end)
    create_toggle(combat, "Visible Check", Config.aimbot.visible_check, function(state)
        Config.aimbot.visible_check = state
    end)
    create_toggle(combat, "Auto Shoot", Config.aimbot.auto_shoot, function(state)
        Config.aimbot.auto_shoot = state
    end)
    create_toggle(combat, "Triggerbot", Config.triggerbot.enabled, function(state)
        Config.triggerbot.enabled = state
    end)
    create_slider(combat, "Trigger Delay", 0.01, 0.5, Config.triggerbot.delay, "s", function(v)
        Config.triggerbot.delay = v
    end)
    create_toggle(combat, "Prediction", Config.prediction.enabled, function(state)
        Config.prediction.enabled = state
    end)
    create_slider(combat, "Prediction", 0.02, 0.5, Config.prediction.value, "", function(v)
        Config.prediction.value = v
    end)

    local parts = { "Head", "Torso", "HumanoidRootPart", "UpperTorso" }
    local part_index = 1
    local part_btn = create_button(combat, "Hit Part: " .. parts[part_index], function()
        part_index = part_index % #parts + 1
        Config.aimbot.part = parts[part_index]
        part_btn.Text = "Hit Part: " .. parts[part_index]
    end)

    -- ---- VISUALS ----
    local visuals = pages.Visuals
    new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 8) }, visuals)
    stack(visuals)

    create_label(visuals, "ESP", Palette.text3, 10)
    create_toggle(visuals, "Enable ESP", Config.esp.enabled, function(state)
        Config.esp.enabled = state
        if not state then clear_visuals() end
    end)
    create_toggle(visuals, "Name", Config.esp.name, function(state) Config.esp.name = state end)
    create_toggle(visuals, "Health", Config.esp.health, function(state) Config.esp.health = state end)
    create_toggle(visuals, "Distance", Config.esp.distance, function(state) Config.esp.distance = state end)
    create_toggle(visuals, "Team Color", Config.esp.team_color, function(state)
        Config.esp.team_color = state
        clear_visuals()
    end)
    create_slider(visuals, "Max Distance", 50, 2000, Config.esp.max_distance, "m", function(v)
        Config.esp.max_distance = v
    end)

    -- ---- MOVEMENT ----
    local movement = pages.Movement
    new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 8) }, movement)
    stack(movement)

    create_label(movement, "MOVE", Palette.text3, 10)
    create_toggle(movement, "Speed", Config.speed.enabled, function(state)
        Config.speed.enabled = state
        set_speed(state, Config.speed.value)
    end)
    create_slider(movement, "WalkSpeed", 16, 300, Config.speed.value, "", function(v)
        Config.speed.value = v
        if Config.speed.enabled then set_speed(true, v) end
    end)
    create_toggle(movement, "Fly", Config.fly.enabled, function(state)
        Config.fly.enabled = state
        if state then setup_fly() else clear_fly() end
    end)
    create_slider(movement, "Fly Speed", 10, 400, Config.fly.speed, "", function(v)
        Config.fly.speed = v
    end)
    create_toggle(movement, "No Recoil", Config.no_recoil.enabled, function(state)
        Config.no_recoil.enabled = state
        if state then apply_no_recoil() else undo_no_recoil() end
    end)

    -- ---- CONFIG ----
    local config_page = pages.Config
    new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 8) }, config_page)
    stack(config_page)

    create_label(config_page, "SYSTEM", Palette.text3, 10)
    create_label(config_page, "Toggle UI: RightShift", Palette.text2, 12)
    create_label(config_page, "Build: Universal FPS", Palette.text3, 10)

    create_button(config_page, "Reset Aim Settings", function()
        Config.aimbot.fov = 120
        Config.aimbot.smoothness = 0.20
        Config.aimbot.part = "Head"
        part_index = 1
        part_btn.Text = "Hit Part: Head"
    end)

    create_button(config_page, "Clear ESP", function()
        clear_visuals()
    end)

    create_button(config_page, "Unload", function()
        getgenv().JakonScripts_Unload()
    end)

    select_tab("Combat")

    -- ---- DRAG ----
    local dragging, drag_start, start_pos = false, nil, nil
    track( sidebar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            drag_start = input.Position
            start_pos = main.Position
        end
    end) )
    track( UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - drag_start
            main.Position = UDim2.new(
                start_pos.X.Scale, start_pos.X.Offset + delta.X,
                start_pos.Y.Scale, start_pos.Y.Offset + delta.Y
            )
        end
    end) )
    track( UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end) )

    return main
end

-- ============================================================
-- FOV-КРУГ
-- ============================================================

local function build_fov_circle()
    if not Drawing then return end
    FovCircle = Drawing.new("Circle")
    FovCircle.Thickness = 1
    FovCircle.NumSides = 64
    FovCircle.Radius = Config.aimbot.fov
    FovCircle.Filled = false
    FovCircle.Transparency = 1
    FovCircle.Color = Palette.accent
    FovCircle.Visible = false
end

-- ============================================================
-- ЦИКЛЫ
-- ============================================================

local function start_loops()
    track( RunService.RenderStepped:Connect(function()
        if FovCircle then
            FovCircle.Visible = Config.aimbot.enabled and Config.silent.enabled == false
            FovCircle.Position = UserInputService:GetMouseLocation()
            FovCircle.Radius = Config.aimbot.fov
        end

        if Config.aimbot.enabled and AimHeld then
            local target = get_target()
            if target then
                local aim_point = target.Position + get_velocity(target)
                local goal = CFrame.new(Camera.CFrame.Position, aim_point)
                Camera.CFrame = Camera.CFrame:Lerp(goal, Config.aimbot.smoothness)
                if Config.aimbot.auto_shoot then
                    if mouse1click then
                        pcall(mouse1click)
                    elseif VirtualInputManager then
                        pcall(function()
                            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
                            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
                        end)
                    end
                end
            end
        end

        if Config.triggerbot.enabled then
            local target = get_target()
            if target
                and not (Config.triggerbot.team_check and LocalPlayer.Team and target.Parent
                    and Players:GetPlayerFromCharacter(target.Parent)
                    and Players:GetPlayerFromCharacter(target.Parent).Team == LocalPlayer.Team)
                and (not Config.triggerbot.visible_check or has_line_of_sight(target)) then
                if not TriggerLatched then
                    TriggerLatched = true
                    task.spawn(function()
                        task.wait(Config.triggerbot.delay)
                        if Config.triggerbot.enabled and mouse1click then
                            pcall(mouse1click)
                        end
                        TriggerLatched = false
                    end)
                end
            end
        end
    end) )

    track( RunService.Heartbeat:Connect(function()
        if Config.esp.enabled then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    refresh_esp(plr)
                end
            end
        end
        if Config.no_recoil.enabled then
            apply_no_recoil()
        end
    end) )

    track( RunService.Stepped:Connect(function()
        if not Config.fly.enabled then return end
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local bv = hrp and hrp:FindFirstChild("JS_FlyVelocity")
        local bg = hrp and hrp:FindFirstChild("JS_FlyGyro")
        if not (bv and bg) then return end

        local direction = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then direction += Camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then direction -= Camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then direction -= Camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then direction += Camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then direction += Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then direction -= Vector3.new(0, 1, 0) end

        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid.PlatformStand = true end

        if direction.Magnitude > 0 then
            bv.Velocity = direction.Unit * Config.fly.speed
        else
            bv.Velocity = Vector3.zero
        end
        bg.CFrame = Camera.CFrame
    end) )

    track( UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            if Gui then Gui.Enabled = not Gui.Enabled end
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            AimHeld = true
        end
    end) )

    track( UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            AimHeld = false
        end
    end) )

    track( LocalPlayer.CharacterAdded:Connect(function()
        task.wait(1)
        AimHeld = false
        clear_visuals()
        if Config.speed.enabled then set_speed(true, Config.speed.value) end
        if Config.fly.enabled then setup_fly() end
    end) )

    track( Players.PlayerRemoving:Connect(function(plr)
        cleanup_player(plr)
    end) )
end

-- ============================================================
-- UNLOAD
-- ============================================================

getgenv().JakonScripts_Unload = function()
    getgenv().JakonScripts_Loaded = false

    for _, connection in ipairs(Connections) do
        pcall(function() connection:Disconnect() end)
    end
    Connections = {}

    clear_visuals()
    remove_silent_hook()
    clear_fly()
    undo_no_recoil()

    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = 16
        humanoid.PlatformStand = false
    end

    if FovCircle then
        pcall(function() FovCircle:Remove() end)
        FovCircle = nil
    end

    if Gui then
        Gui:Destroy()
        Gui = nil
    end
end

-- ============================================================
-- ЗАПУСК
-- ============================================================

build_ui()
build_fov_circle()
install_silent_hook()
start_loops()

pcall(function()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            plr.CharacterAdded:Connect(function()
                task.wait(0.5)
                if Config.esp.enabled then refresh_esp(plr) end
            end)
        end
    end
end)

-- RightShift открывает меню. Aimbot — зажми ПКМ, Speed/Fly/No Recoil — в Movement.
