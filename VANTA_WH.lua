-- VANTA WH v2 | Luau | Roblox | только Drawing: в дерево игры не добавлено ничего
-- Боксы, ники, дистанция, полоса здоровья. Аимбот — доводка мышью, не записью
-- камеры: GetMouseDelta не ноль, игра видит живой ввод.
-- RightShift — вкл/выкл оверлей, E (зажать) — аимбот.
-- Запуск: loadstring(game:HttpGet("RAW_URL"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

if not Drawing or not LocalPlayer then return end

-- mousemoverel читаем значением: чего нет в сборке экзекьютора — то пустышка
local move_mouse = mousemoverel or function() end

local S = {
    on = true, box = true, name = true, dist = true, hp = true, allies = false,
    maxdist = 1500, key = Enum.KeyCode.RightShift,
    aim = true, aim_key = Enum.KeyCode.E, aim_hold = true, aim_part = "Head",
    aim_fov = 140, aim_speed = 22, aim_maxstep = 5, aim_jitter = 0.7,
    aim_reaction = 130, aim_wallcheck = true, aim_team = true,
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

-- ===== АИМБОТ =====
local ray = Instance.new("RaycastParams")
pcall(function() ray.FilterType = Enum.RaycastFilterType.Exclude end)
pcall(function() ray.FilterType = Enum.RaycastFilterType.Blacklist end)
ray.IgnoreWater = true

local filtered_char = nil
local function refresh_filter()
    local list = {}
    if Camera then list[#list + 1] = Camera end
    local char = LocalPlayer.Character
    if char then
        list[#list + 1] = char
        filtered_char = char
    end
    ray.FilterDescendantsInstances = list
end
refresh_filter()

local function part_of(char)
    if S.aim_part == "Head" then return char:FindFirstChild("Head") end
    if S.aim_part == "Torso" then
        return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
            or char:FindFirstChild("HumanoidRootPart")
    end
    return char:FindFirstChild("HumanoidRootPart")
end

local function line_clear(part)
    if not S.aim_wallcheck then return true end
    local origin = Camera.CFrame.Position
    local hit = Workspace:Raycast(origin, part.Position - origin, ray)
    if not hit then return true end
    return hit.Instance:IsDescendantOf(part.Parent)
end

local target, acquired = nil, 0
local acc_x, acc_y = 0, 0

local function pick()
    local best, best_offset = nil, math.huge
    local viewport = Camera.ViewportSize
    local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
    local origin = Camera.CFrame.Position
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local friendly = player.Team ~= nil and player.Team == LocalPlayer.Team
                if not (S.aim_team and friendly) then
                    local part = part_of(char)
                    local distance = part and (part.Position - origin).Magnitude or math.huge
                    if part and distance <= S.maxdist then
                        local screen, on_screen = Camera:WorldToViewportPoint(part.Position)
                        if on_screen ~= false and screen.Z > 0 then
                            local offset = (Vector2.new(screen.X, screen.Y) - center).Magnitude
                            if offset <= S.aim_fov and offset < best_offset and line_clear(part) then
                                best, best_offset = player, offset
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function steer()
    if not S.aim then return end
    if S.aim_hold and not UserInputService:IsKeyDown(S.aim_key) then
        target = nil
        acc_x, acc_y = 0, 0
        return
    end

    local now = os.clock()
    local found = pick()
    if found ~= target then
        target, acquired = found, now
        acc_x, acc_y = 0, 0
    end
    if not target then return end

    -- задержка реакции: живая рука не доводит в тот же кадр, что заметила цель
    if (now - acquired) * 1000 < S.aim_reaction then return end

    local char = target.Character
    local part = char and part_of(char)
    if not part then
        target = nil
        return
    end
    local screen, on_screen = Camera:WorldToViewportPoint(part.Position)
    if on_screen == false or screen.Z <= 0 then return end

    local viewport = Camera.ViewportSize
    local dx = screen.X - viewport.X / 2
    local dy = screen.Y - viewport.Y / 2
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < 0.6 then return end

    local gain = (S.aim_speed / 100) * math.clamp(distance / 220, 0.25, 1)
    local step_x, step_y = dx * gain, dy * gain
    if S.aim_maxstep > 0 then
        local length = math.sqrt(step_x * step_x + step_y * step_y)
        if length > S.aim_maxstep then
            step_x = step_x * S.aim_maxstep / length
            step_y = step_y * S.aim_maxstep / length
        end
    end
    if S.aim_jitter > 0 then
        step_x = step_x + (math.random() * 2 - 1) * S.aim_jitter
        step_y = step_y + (math.random() * 2 - 1) * S.aim_jitter
    end

    -- дробный остаток копится: mousemoverel принимает целые, без накопителя
    -- мелкая доводка не сдвинула бы курсор вообще
    acc_x, acc_y = acc_x + step_x, acc_y + step_y
    local mx = math.floor(acc_x + 0.5)
    local my = math.floor(acc_y + 0.5)
    if mx ~= 0 or my ~= 0 then
        acc_x, acc_y = acc_x - mx, acc_y - my
        move_mouse(mx, my)
    end
end

local function frame()
    local current = Workspace.CurrentCamera
    if current then Camera = current end
    if not Camera then return end
    if LocalPlayer.Character ~= filtered_char then refresh_filter() end

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
    steer()
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
