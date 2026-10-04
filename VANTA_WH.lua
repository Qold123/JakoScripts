-- VANTA WH v1 | Luau | Roblox | только Drawing: в дерево игры не добавлено ничего
-- Боксы, ники, дистанция, полоса здоровья. RightShift — вкл/выкл.
-- Запуск: loadstring(game:HttpGet("RAW_URL"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

if not Drawing or not LocalPlayer then return end

local S = {
    on = true, box = true, name = true, dist = true, hp = true, allies = false,
    maxdist = 1500, key = Enum.KeyCode.RightShift,
}

local ACCENT = Color3.fromRGB(124, 58, 237)
local TEXT = Color3.fromRGB(255, 255, 255)
local MUTED = Color3.fromRGB(161, 161, 170)
local GOOD = Color3.fromRGB(52, 211, 153)
local WARN = Color3.fromRGB(255, 77, 94)
local BLACK = Color3.fromRGB(0, 0, 0)

local SLOTS = 20
local pool = {}

local function mk(kind)
    local ok, d = pcall(Drawing.new, kind)
    if ok then return d end
end

for i = 1, SLOTS do
    local s = {
        box = mk("Square"), name = mk("Text"), dist = mk("Text"),
        hp_bg = mk("Square"), hp_fg = mk("Square"),
    }
    if s.box then
        s.box.Filled = false
        s.box.Thickness = 1
    end
    if s.hp_bg then
        s.hp_bg.Filled = true
        s.hp_bg.Color = BLACK
        s.hp_bg.Transparency = 0.5
    end
    if s.hp_fg then s.hp_fg.Filled = true end
    if s.name then
        s.name.Center = true
        s.name.Outline = true
        s.name.OutlineColor = BLACK
        s.name.Size = 13
        s.name.Color = TEXT
    end
    if s.dist then
        s.dist.Center = true
        s.dist.Outline = true
        s.dist.OutlineColor = BLACK
        s.dist.Size = 11
        s.dist.Color = MUTED
    end
    pool[i] = s
end

local function hide(s)
    if s.box then s.box.Visible = false end
    if s.name then s.name.Visible = false end
    if s.dist then s.dist.Visible = false end
    if s.hp_bg then s.hp_bg.Visible = false end
    if s.hp_fg then s.hp_fg.Visible = false end
end

local CORNERS = {
    Vector3.new(-1, -1, -1), Vector3.new(1, -1, -1),
    Vector3.new(-1, 1, -1), Vector3.new(1, 1, -1),
    Vector3.new(-1, -1, 1), Vector3.new(1, -1, 1),
    Vector3.new(-1, 1, 1), Vector3.new(1, 1, 1),
}

-- Рамка по восьми углам габарита модели: аксессуары и оружие в руках её не ломают.
local function box_of(model)
    local center, size = model:GetBoundingBox()
    local min_x, min_y = math.huge, math.huge
    local max_x, max_y = -math.huge, -math.huge
    for i = 1, 8 do
        local point = (center * CFrame.new(
            CORNERS[i].X * size.X / 2, CORNERS[i].Y * size.Y / 2, CORNERS[i].Z * size.Z / 2
        )).Position
        local screen, on_screen = Camera:WorldToViewportPoint(point)
        if on_screen == false or screen.Z <= 0 then return nil end
        min_x = math.min(min_x, screen.X)
        min_y = math.min(min_y, screen.Y)
        max_x = math.max(max_x, screen.X)
        max_y = math.max(max_y, screen.Y)
    end
    if max_x - min_x < 2 or max_y - min_y < 2 then return nil end
    return min_x, min_y, max_x, max_y
end

local function skip(player)
    if player == LocalPlayer then return true end
    local char = player.Character
    if not char then return true end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return true end
    if not S.allies and player.Team ~= nil and player.Team == LocalPlayer.Team then return true end
    return false
end

local function frame()
    local current = Workspace.CurrentCamera
    if current then Camera = current end
    if not Camera then return end

    local used = 0
    local origin = Camera.CFrame.Position

    if S.on then
        for _, player in ipairs(Players:GetPlayers()) do
            if used >= SLOTS then break end
            if not skip(player) then
                local char = player.Character
                local root = char:FindFirstChild("HumanoidRootPart")
                local distance = root and (root.Position - origin).Magnitude or 0
                if root and distance <= S.maxdist then
                    local min_x, min_y, max_x, max_y = box_of(char)
                    if min_x then
                        used = used + 1
                        local s = pool[used]
                        local width = max_x - min_x
                        local height = max_y - min_y
                        local mid = (min_x + max_x) / 2

                        if s.box then
                            s.box.Visible = S.box
                            s.box.Position = Vector2.new(min_x, min_y)
                            s.box.Size = Vector2.new(width, height)
                            s.box.Color = ACCENT
                            s.box.Transparency = 0.1
                        end
                        if s.name then
                            s.name.Visible = S.name
                            s.name.Text = player.Name
                            s.name.Position = Vector2.new(mid, min_y - 8)
                        end
                        if s.dist then
                            s.dist.Visible = S.dist
                            s.dist.Text = string.format("%d m", math.floor(distance + 0.5))
                            s.dist.Position = Vector2.new(mid, max_y + 7)
                        end
                        if s.hp_bg and s.hp_fg then
                            local hum = char:FindFirstChildOfClass("Humanoid")
                            local show = S.hp and hum ~= nil
                            s.hp_bg.Visible = show
                            s.hp_fg.Visible = show
                            if show then
                                local ratio = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
                                s.hp_bg.Position = Vector2.new(min_x - 5, min_y)
                                s.hp_bg.Size = Vector2.new(2, height)
                                s.hp_fg.Position = Vector2.new(min_x - 5, min_y + height * (1 - ratio))
                                s.hp_fg.Size = Vector2.new(2, height * ratio)
                                s.hp_fg.Color = ratio > 0.55 and GOOD or (ratio > 0.25 and ACCENT or WARN)
                            end
                        end
                    end
                end
            end
        end
    end

    for i = used + 1, SLOTS do hide(pool[i]) end
end

local render = RunService.RenderStepped:Connect(frame)
local keys = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == S.key then
        S.on = not S.on
    end
end)

local function unload()
    pcall(function() render:Disconnect() end)
    pcall(function() keys:Disconnect() end)
    for i = 1, SLOTS do
        local s = pool[i]
        hide(s)
        for _, key in ipairs({ "box", "name", "dist", "hp_bg", "hp_fg" }) do
            if s[key] then pcall(function() s[key]:Remove() end) end
        end
    end
end

local GENV = (getgenv or function() return _G end)()
GENV.VANTA_WH = { unload = unload, settings = S }
