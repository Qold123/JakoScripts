-- JakoScripts WH v2 | Luau | generic Roblox shooter | VANTA Style A
-- Волхак с полным оверлеем: боксы (2D / углы / заливка), ники с оружием и хп-баром,
-- трассеры, скелет, стрелки к врагам за экраном, прицел и кольцо FOV.
-- Всё ТОЛЬКО Drawing: в игре не создаётся ни одной детали, сканерам ловить нечего.
-- Нужен executor с Drawing, без него скрипт честно скажет и выключится.
-- UI: Style A — окно 480x360, сайдбар 150, вкладки Visuals / Targets / Config, RightShift скрыть.
-- Запуск: loadstring(game:HttpGet("RAW_URL"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

if not Drawing then
    warn("[JakoScripts WH] нет Drawing в executor")
    return
end

-- ===== STATE =====
local State = {
    enabled = true,
    boxes = true,
    names = true,
    tracers = false,
    enemies_only = true, -- только враги (своих скрыть)
    team_check = true,
    maxdist = 1500,
    esp_skeleton = false,  -- линии скелета (Drawing Line, пул на игрока)
    esp_arrows = false,    -- стрелка у края экрана к цели за кадром
    esp_healthbar = true,  -- полоска HP слева от бокса (фон + заливка)
    esp_weapon = true,     -- имя Tool в строку ника
    fov_ring = true,       -- кольцо FOV по центру
    -- радиус кольца FOV, px (40..600)
    fov_size = 200,
    crosshair = false,     -- кастомный прицел из 4 Line
    box_style = "2D",      -- "2D" | "Corner" | "Filled"
    antiafk = true,        -- LocalPlayer.Idled -> VirtualUser
    dist_fade = false,     -- прозрачность бокса/ника растёт с дистанцией
}

-- ===== TEAM (реестр -> контейнеры -> Team) =====
local TeamReg, regAt = nil, 0
local function regTeam(plr)
    if TeamReg and type(TeamReg.players) == "table" then
        local ok, d = pcall(function() return TeamReg.players[plr] end)
        if ok and type(d) == "table" and d.team ~= nil then return tostring(d.team) end
        return nil
    end
    if type(filtergc) ~= "function" then return nil end
    if os.clock() - regAt < 5 then return nil end
    regAt = os.clock()
    local ok, reg = pcall(filtergc, "table", {
        Keys = { "isFriendly", "getclient", "getEnemyTeam", "getPlayer", "players" }
    }, true)
    if ok and type(reg) == "table" and type(reg.players) == "table" then
        TeamReg = reg
        local ok2, d2 = pcall(function() return reg.players[plr] end)
        if ok2 and type(d2) == "table" and d2.team ~= nil then return tostring(d2.team) end
    end
    return nil
end

local function sameTeam(plr)
    if plr == LocalPlayer then return true end
    if not State.team_check then return false end
    local myT = regTeam(LocalPlayer)
    if myT then local pT = regTeam(plr) if pT then return pT == myT end end
    local mc = LocalPlayer.Character
    local ch = plr.Character
    mc = mc and mc.Parent ~= Workspace and mc.Parent or nil
    local pc = ch and ch.Parent ~= Workspace and ch.Parent or nil
    if mc and pc then return mc == pc end
    local mt, pt = LocalPlayer.Team, plr.Team
    if mt ~= nil and pt ~= nil then return mt == pt end
    return false
end

local function isEnemy(plr)
    if plr == LocalPlayer then return false end
    local ch = plr.Character
    if not ch then return false end
    local hum = ch:FindFirstChildOfClass("Humanoid", true) -- рекурсивно: риг бывает вложенным
    if not hum or hum.Health <= 0 then return false end
    if State.enemies_only and State.team_check then
        return not sameTeam(plr)
    end
    return true
end

-- ===== OVERLAY POOL (один комплект Drawing на игрока, переиспользуем) =====
-- Всё, что создано для игрока, лежит в it.all -> скрыть/снять = один цикл.
local items = {} -- [player] = { all = {drawing...}, box, txt, line, ... }

local unloaded = false
local connRender, connHeartbeat, antiAfkConn = nil, nil, nil

local BOX_COLOR = Color3.fromRGB(255, 90, 70)
local BOX_ALPHA, TXT_ALPHA, LINE_ALPHA, SKEL_ALPHA = 0.9, 0.95, 0.7, 0.4
local ACCENT = Color3.fromRGB(124, 58, 237)

-- Кости: { {кандидаты A}, {кандидаты B} } — R15 + фолбэк R6 (Torso / "Left Arm")
local BONES = {
    { { "Head" }, { "UpperTorso", "Torso" } },
    { { "UpperTorso" }, { "LowerTorso" } },
    { { "UpperTorso", "Torso" }, { "LeftUpperArm", "Left Arm" } },
    { { "UpperTorso", "Torso" }, { "RightUpperArm", "Right Arm" } },
    { { "LeftUpperArm", "Left Arm" }, { "LeftLowerArm" } },
    { { "LeftLowerArm" }, { "LeftHand" } },
    { { "RightUpperArm", "Right Arm" }, { "RightLowerArm" } },
    { { "RightLowerArm" }, { "RightHand" } },
    { { "LowerTorso", "Torso" }, { "LeftUpperLeg", "Left Leg" } },
    { { "LeftUpperLeg", "Left Leg" }, { "LeftLowerLeg" } },
    { { "LeftLowerLeg" }, { "LeftFoot" } },
    { { "LowerTorso", "Torso" }, { "RightUpperLeg", "Right Leg" } },
    { { "RightUpperLeg", "Right Leg" }, { "RightLowerLeg" } },
    { { "RightLowerLeg" }, { "RightFoot" } },
}

local function newLine(it, thickness, alpha)
    local o = Drawing.new("Line")
    o.Thickness = thickness or 1
    o.Transparency = alpha or LINE_ALPHA
    o.Visible = false
    it.all[#it.all + 1] = o
    return o
end

local function newSquare(it, filled, alpha)
    local o = Drawing.new("Square")
    o.Filled = filled and true or false
    o.Thickness = 1
    o.Transparency = alpha or BOX_ALPHA
    o.Visible = false
    it.all[#it.all + 1] = o
    return o
end

local function newText(it)
    local o = Drawing.new("Text")
    o.Size = 13
    o.Center = true
    o.Outline = true
    o.Transparency = TXT_ALPHA
    o.Visible = false
    it.all[#it.all + 1] = o
    return o
end

local function newTriangle(it)
    local o = Drawing.new("Triangle")
    o.Filled = true
    o.Transparency = 0.15
    o.Visible = false
    it.all[#it.all + 1] = o
    return o
end

local function getItem(plr)
    local it = items[plr]
    if not it then
        it = { all = {} }
        it.box = newSquare(it, false, BOX_ALPHA)
        it.txt = newText(it)
        it.line = newLine(it, 1, LINE_ALPHA)
        items[plr] = it
    end
    return it
end

-- Ленивые пулы: создаём только то, что реально включено, дальше только прячем.
local function ensureFill(it)
    if not it.boxFill then it.boxFill = newSquare(it, true, 0.85) end
    return it.boxFill
end

local function ensureCorners(it)
    if not it.corner then
        local c = {}
        for i = 1, 8 do c[i] = newLine(it, 1, BOX_ALPHA) end
        it.corner = c
    end
    return it.corner
end

local function ensureHBar(it)
    if not it.hbar then
        it.hbar = newSquare(it, true, 0.35)  -- фон полоски
        it.hfill = newSquare(it, true, 0.1)  -- заливка HP
    end
end

local function ensureArrow(it)
    if not it.arrow then it.arrow = newTriangle(it) end
    return it.arrow
end

local function ensureSkel(it)
    if not it.skel then
        local s = {}
        for i = 1, #BONES do s[i] = newLine(it, 1, SKEL_ALPHA) end
        it.skel = s
    end
    return it.skel
end

local function hideItem(plr)
    local it = items[plr]
    if it then
        for i = 1, #it.all do it.all[i].Visible = false end
    end
end

local function dropItem(it)
    if not it then return end
    for i = 1, #it.all do
        local o = it.all[i]
        pcall(function() o:Remove() end)
    end
    it.all = {}
end

Players.PlayerRemoving:Connect(function(p)
    local it = items[p]
    if it then
        dropItem(it)
        items[p] = nil
    end
end)

-- ===== ЦВЕТ / ФОРМАТ =====
-- цвет по команде, если она есть; иначе базовый цвет бокса
local function espColor(p)
    local team = p.Team
    local tc = team and team.TeamColor
    local c = tc and tc.Color
    if c then return c end
    return BOX_COLOR
end

-- прозрачность: 0.15 на 100 ст -> 0.9 на maxdist
local function fadeAlpha(dist)
    local d1 = math.max(101, State.maxdist)
    return 0.15 + 0.75 * math.clamp((dist - 100) / (d1 - 100), 0, 1)
end

local function hpColor(f)
    if f > 0.5 then return Color3.fromRGB(0, 230, 118):Lerp(Color3.fromRGB(255, 221, 0), (1 - f) * 2) end
    return Color3.fromRGB(255, 221, 0):Lerp(Color3.fromRGB(255, 60, 60), 1 - f * 2)
end

local function weaponName(ch)
    if not ch then return nil end
    local tool = ch:FindFirstChildOfClass("Tool") or ch:FindFirstChildWhichIsA("Tool", true)
    return tool and tool.Name or nil
end

-- один рекурсивный поиск на имя за кадр, кэш на игрока
local function partOf(ch, cache, names)
    for i = 1, #names do
        local n = names[i]
        local hit = cache[n]
        if hit == nil then
            hit = ch:FindFirstChild(n, true) or false
            cache[n] = hit
        end
        if hit then return hit end
    end
    return nil
end

local function hideCorners(it)
    if it.corner then
        for i = 1, #it.corner do it.corner[i].Visible = false end
    end
end

local function hideSkel(it)
    if it.skel then
        for i = 1, #it.skel do it.skel[i].Visible = false end
    end
end

-- Corner: 8 Line, сегмент = 25% стороны
local function drawCorners(it, x, y, w, h, col, alpha)
    local c = ensureCorners(it)
    local sx, sy = w * 0.25, h * 0.25
    local x2, y2 = x + w, y + h
    c[1].From = Vector2.new(x, y)
    c[1].To = Vector2.new(x + sx, y)
    c[2].From = Vector2.new(x, y)
    c[2].To = Vector2.new(x, y + sy)
    c[3].From = Vector2.new(x2, y)
    c[3].To = Vector2.new(x2 - sx, y)
    c[4].From = Vector2.new(x2, y)
    c[4].To = Vector2.new(x2, y + sy)
    c[5].From = Vector2.new(x, y2)
    c[5].To = Vector2.new(x + sx, y2)
    c[6].From = Vector2.new(x, y2)
    c[6].To = Vector2.new(x, y2 - sy)
    c[7].From = Vector2.new(x2, y2)
    c[7].To = Vector2.new(x2 - sx, y2)
    c[8].From = Vector2.new(x2, y2)
    c[8].To = Vector2.new(x2, y2 - sy)
    for i = 1, 8 do
        local l = c[i]
        l.Color = col
        l.Transparency = alpha
        l.Visible = true
    end
end

local function drawSkeleton(it, ch, cam, col)
    local list = ensureSkel(it)
    local cache = {}
    for i = 1, #BONES do
        local pair = BONES[i]
        local l = list[i]
        local a = partOf(ch, cache, pair[1])
        local b = a and partOf(ch, cache, pair[2])
        if a and b then
            local pa, oa = cam:WorldToViewportPoint(a.Position)
            local pb, ob = cam:WorldToViewportPoint(b.Position)
            if oa and ob then
                l.From = Vector2.new(pa.X, pa.Y)
                l.To = Vector2.new(pb.X, pb.Y)
                l.Color = col
                l.Transparency = SKEL_ALPHA
                l.Visible = true
            else
                l.Visible = false
            end
        else
            l.Visible = false
        end
    end
end

-- Offscreen arrow: цель за кадром -> треугольник у края, радиус 0.42*min(vs)
local function updateArrow(it, pos, cam, vs, cx, cy, col)
    local a = ensureArrow(it)
    local sp, on = cam:WorldToViewportPoint(pos)
    if on then
        a.Visible = false
        return
    end
    local dir = Vector2.new(sp.X - cx, sp.Y - cy)
    if cam.CFrame.LookVector:Dot(pos - cam.CFrame.Position) < 0 then
        dir = Vector2.new(-dir.X, -dir.Y) -- цель за спиной
    end
    if dir.Magnitude < 1 or dir.X ~= dir.X or dir.Y ~= dir.Y then
        dir = Vector2.new(0, -1)
    end
    dir = dir.Unit
    local rad = 0.42 * math.min(vs.X, vs.Y)
    local mid = Vector2.new(cx, cy)
    local base = mid + dir * rad
    local perp = Vector2.new(-dir.Y, dir.X) * 9
    a.PointA = mid + dir * (rad + 14)
    a.PointB = base + perp
    a.PointC = base - perp
    a.Color = col
    a.Transparency = 0.15
    a.Visible = true
end

-- ===== ГЛОБАЛЬНЫЙ ПРИЦЕЛ: кольцо FOV + crosshair (вне пула игроков) =====
local fovCircle = Drawing.new("Circle")
fovCircle.Color = ACCENT
fovCircle.Thickness = 1
fovCircle.NumSides = 64
fovCircle.Filled = false
fovCircle.Transparency = 0.45
fovCircle.Visible = false

local crossLines = {}
for i = 1, 4 do
    local l = Drawing.new("Line")
    l.Thickness = 1
    l.Color = Color3.fromRGB(255, 255, 255)
    l.Transparency = 0.15
    l.Visible = false
    crossLines[i] = l
end

local CROSS_GAP, CROSS_LEN = 4, 6

local function updateCrosshair(vs, on)
    local cx, cy = vs.X / 2, vs.Y / 2
    if not on then
        for i = 1, 4 do crossLines[i].Visible = false end
        return
    end
    local d, e = CROSS_GAP, CROSS_GAP + CROSS_LEN
    local pts = {
        { Vector2.new(cx, cy - d), Vector2.new(cx, cy - e) },
        { Vector2.new(cx, cy + d), Vector2.new(cx, cy + e) },
        { Vector2.new(cx - d, cy), Vector2.new(cx - e, cy) },
        { Vector2.new(cx + d, cy), Vector2.new(cx + e, cy) },
    }
    for i = 1, 4 do
        local l = crossLines[i]
        l.From = pts[i][1]
        l.To = pts[i][2]
        l.Visible = true
    end
end

-- ===== ANTI-AFK (только pcall + Idled, без SetCore) =====
local function antiAfkPulse()
    pcall(function()
        local vu = game:GetService("VirtualUser")
        local cam = Workspace.CurrentCamera
        local cf = cam and cam.CFrame or CFrame.new()
        vu:Button2Down(Vector2.new(0, 0), cf)
        task.wait(1)
        vu:Button2Up(Vector2.new(0, 0), cf)
    end)
end

local function startAntiAfk()
    if antiAfkConn then return end
    antiAfkConn = LocalPlayer.Idled:Connect(antiAfkPulse)
end

local function stopAntiAfk()
    if antiAfkConn then
        pcall(function() antiAfkConn:Disconnect() end)
        antiAfkConn = nil
    end
end

local function syncAntiAfk()
    if State.antiafk then startAntiAfk() else stopAntiAfk() end
end

local dbgShow, dbgAlive = 0, 0

local function overlayTick()
    if unloaded then return end
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local vs = cam.ViewportSize
    local cx, cy = vs.X / 2, vs.Y / 2
    local myHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart", true)
    local myPos = myHrp and myHrp.Position or cam.CFrame.Position
    local shown, aliveN = 0, 0

    -- кольцо FOV и прицел — глобальные
    fovCircle.Position = Vector2.new(cx, cy)
    fovCircle.Radius = State.fov_size or 200
    fovCircle.Visible = State.fov_ring and true or false
    updateCrosshair(vs, State.crosshair and true or false)

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local pch = p.Character
            local phum = pch and pch:FindFirstChildOfClass("Humanoid", true)
            if pch and phum and phum.Health > 0 then aliveN += 1 end
        end
        if not State.enabled or not isEnemy(p) then
            hideItem(p)
        else
            local ch = p.Character
            -- рекурсивный поиск: у некоторых игр части лежат во вложенных моделях
            local head = ch and ch:FindFirstChild("Head", true)
            local hrp = ch and (ch:FindFirstChild("HumanoidRootPart", true)
                or ch:FindFirstChild("Torso", true)
                or ch:FindFirstChild("UpperTorso", true))
            if (not head or not hrp) and ch then
                local anyB = ch:FindFirstChildWhichIsA("BasePart", true)
                if anyB then head, hrp = anyB, anyB end
            end
            local it = getItem(p)
            if not head or not hrp then
                hideItem(p)
            else
                local dist = (myPos - hrp.Position).Magnitude
                if dist > State.maxdist then
                    hideItem(p)
                else
                    local col = espColor(p)
                    local p1, on1 = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.7, 0))
                    local p2, on2 = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0, 2.8, 0))
                    local h = math.abs(p2.Y - p1.Y)
                    local w = h * 0.6
                    local vis = (on1 and on2 and h >= 5) and true or false
                    if vis then shown += 1 end

                    -- стрелка: только если цель за кадром
                    if State.esp_arrows then
                        updateArrow(it, hrp.Position, cam, vs, cx, cy, col)
                    elseif it.arrow then
                        it.arrow.Visible = false
                    end

                    local alpha = State.dist_fade and fadeAlpha(dist) or BOX_ALPHA
                    local bx, by = p1.X - w / 2, p1.Y

                    if vis and State.boxes then
                        local style = State.box_style
                        if style == "Corner" then
                            it.box.Visible = false
                            if it.boxFill then it.boxFill.Visible = false end
                            drawCorners(it, bx, by, w, h, col, alpha)
                        elseif style == "Filled" then
                            hideCorners(it)
                            local f = ensureFill(it)
                            f.Size = Vector2.new(w, h)
                            f.Position = Vector2.new(bx, by)
                            f.Color = col
                            f.Transparency = State.dist_fade and math.max(0.85, alpha) or 0.85
                            f.Visible = true
                            it.box.Size = Vector2.new(w, h)
                            it.box.Position = Vector2.new(bx, by)
                            it.box.Color = col
                            it.box.Transparency = alpha
                            it.box.Visible = true -- контур поверх заливки
                        else
                            if it.boxFill then it.boxFill.Visible = false end
                            hideCorners(it)
                            it.box.Size = Vector2.new(w, h)
                            it.box.Position = Vector2.new(bx, by)
                            it.box.Color = col
                            it.box.Transparency = alpha
                            it.box.Visible = true
                        end
                    else
                        it.box.Visible = false
                        if it.boxFill then it.boxFill.Visible = false end
                        hideCorners(it)
                    end

                    if vis and State.names then
                        local tag = p.DisplayName .. " [" .. math.floor(dist + 0.5) .. "m]"
                        if State.esp_weapon then
                            local wn = weaponName(ch)
                            if wn then tag = tag .. " | " .. wn end
                        end
                        it.txt.Text = tag
                        it.txt.Position = Vector2.new(p1.X, math.max(0, p1.Y - 16))
                        it.txt.Color = col
                        it.txt.Transparency = State.dist_fade and fadeAlpha(dist) or TXT_ALPHA
                        it.txt.Visible = true
                    else
                        it.txt.Visible = false
                    end

                    if vis and State.tracers then
                        it.line.From = Vector2.new(cx, vs.Y)
                        it.line.To = Vector2.new(p1.X, p2.Y)
                        it.line.Color = col
                        it.line.Visible = true
                    else
                        it.line.Visible = false
                    end

                    -- Health bar: фон + заливка, высота = высота бокса
                    if vis and State.esp_healthbar then
                        local hum = ch:FindFirstChildOfClass("Humanoid", true)
                        local frac = 1
                        if hum and hum.MaxHealth > 0 then
                            frac = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                        end
                        ensureHBar(it)
                        local fillH = math.clamp(math.floor(h * frac + 0.5), 1, h)
                        it.hbar.Size = Vector2.new(3, h)
                        it.hbar.Position = Vector2.new(bx - 7, by)
                        it.hbar.Color = Color3.fromRGB(18, 18, 24)
                        it.hbar.Transparency = 0.35
                        it.hbar.Visible = true
                        it.hfill.Size = Vector2.new(3, fillH)
                        it.hfill.Position = Vector2.new(bx - 7, by + (h - fillH))
                        it.hfill.Color = hpColor(frac)
                        it.hfill.Transparency = 0.1
                        it.hfill.Visible = true
                    else
                        if it.hbar then it.hbar.Visible = false end
                        if it.hfill then it.hfill.Visible = false end
                    end

                    if State.esp_skeleton then
                        drawSkeleton(it, ch, cam, col)
                    else
                        hideSkel(it)
                    end
                end
            end
        end
    end
    dbgShow, dbgAlive = shown, aliveN
end

-- == VANTA STYLE A SHELL — inline block, правки только в шапке ==
local StyleA = (function()
    local SVC = game:GetService
    local UserInputService = SVC("UserInputService")
    local TweenService = SVC("TweenService")
    local Lighting = SVC("Lighting")

    local CONFIG = {
        theme    = "VantaViolet",
        brand    = "JakoScripts",
        mark     = "VANTA",
        wordmark = "SCRIPTS",
        font     = "Inter",
        blur     = 28,
        window   = Vector2.new(480, 360),
        sidebar  = 150,
        radius   = 12,
        pad      = 32,
    }

    local function hex(s)
        local n = tonumber(s, 16) or 0
        return Color3.fromRGB(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
    end

    local P = {
        bg        = hex("06060B"),
        white     = Color3.fromRGB(255, 255, 255),
        accent    = hex("7C3AED"),
        accent_hi = hex("C4B5FD"),
        icon      = hex("A78BFA"),
        text      = hex("FFFFFF"),
        muted     = hex("A1A1AA"),
        dim       = hex("71717A"),
        action_fg = hex("09090B"),
        warn      = Color3.fromRGB(255, 77, 94),
        ok        = Color3.fromRGB(52, 211, 153),
    }

    local A = {
        glass6   = 0.94, glass8 = 0.92,
        row      = 0.969, row_line = 0.941,
        stroke   = 0.890, hilite = 0.867,
        sw_off   = 0.882, track = 0.918,
    }

    local function corner(i, r)
        local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, r or CONFIG.radius) c.Parent = i return c
    end
    local function circle(i)
        local c = Instance.new("UICorner") c.CornerRadius = UDim.new(1, 0) c.Parent = i return c
    end
    local function stroke(i, col, th, tr)
        local s = Instance.new("UIStroke")
        s.Color = col or P.white s.Thickness = th or 1 s.Transparency = tr or A.stroke
        pcall(function() s.LineJoinMode = Enum.LineJoinMode.Round end)
        s.Parent = i return s
    end
    local function tween(i, props, t)
        if not TweenService then for k, v in pairs(props) do pcall(function() i[k] = v end) end return end
        TweenService:Create(i, TweenInfo.new(t or 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
    end
    -- Разрядка по буквам. Идём по код-пойнтам, а не по байтам: тире в "— VANTA"
    -- трёхбайтовое, побайтовый разбор разваливал его на три мусорных знака.
    local function tracked(s)
        local o = {}
        if utf8 and utf8.len and utf8.offset then
            local n = utf8.len(s)
            if n then
                for i = 1, n do
                    local from = utf8.offset(s, i)
                    local to = utf8.offset(s, i + 1)
                    o[#o + 1] = string.sub(s, from, (to or (#s + 1)) - 1)
                end
                return table.concat(o, " ")
            end
        end
        for i = 1, #s do o[#o + 1] = string.sub(s, i, i) end
        return table.concat(o, " ")
    end

    local FONT_OK, F_REG, F_MED, F_SEMI = false, nil, nil, nil
    do
        local ok, a, b, c = pcall(function()
            return Font.fromName(CONFIG.font, Enum.FontWeight.Regular, Enum.FontStyle.Normal),
                   Font.fromName(CONFIG.font, Enum.FontWeight.Medium, Enum.FontStyle.Normal),
                   Font.fromName(CONFIG.font, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
        end)
        if ok and a then FONT_OK, F_REG, F_MED, F_SEMI = true, a, b, c end
    end

    local function label(parent, text, size, col, weight)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1 l.Text = text or "" l.TextSize = size or 12
        l.TextColor3 = col or P.text l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextYAlignment = Enum.TextYAlignment.Center
        -- CoreGui-текст с включённой авто-локализацией заставляет движок дёргать
        -- CoreGui.RobloxGui.Modules.Common.Locales на каждой строке; в связке с
        -- экзекутором это даёт спам "attempt to call a nil value" из Locales
        pcall(function() l.AutoLocalize = false end)
        l.Parent = parent
        if FONT_OK then
            local f = (weight == "semi" and F_SEMI) or (weight == "med" and F_MED) or F_REG
            if f and pcall(function() l.FontFace = f end) then return l end
        end
        l.Font = (weight == "semi" and Enum.Font.GothamBold)
            or (weight == "med" and Enum.Font.GothamMedium) or Enum.Font.Gotham
        return l
    end

    -- Текст в CoreGui с AutoLocalize = true заставляет движок разбирать каждую
    -- строку через CoreGui.RobloxGui.Modules.Common.Locales. Под экзекутором этот
    -- модуль ломается, и консоль забивается "attempt to call a nil value".
    -- Локаль гасится на всех текстовых узлах: label() и mkButton().
    local function mkButton()
        local b = Instance.new("TextButton")
        pcall(function() b.AutoLocalize = false end)
        return b
    end
    -- ---------- lucide icons, vectors ----------
    local function tick(parent, x, y, w, h, col, rot)
        local f = Instance.new("Frame")
        f.BackgroundColor3 = col f.BorderSizePixel = 0
        f.AnchorPoint = Vector2.new(0.5, 0.5) f.Position = UDim2.new(0, x, 0, y)
        f.Size = UDim2.new(0, w, 0, h) f.Rotation = rot or 0 f.Parent = parent
        circle(f) return f
    end

    local function tint(holder, col)
        if holder:IsA("ImageLabel") then holder.ImageColor3 = col end
        if holder:IsA("Frame") and holder.BackgroundTransparency < 1 then holder.BackgroundColor3 = col end
        for _, d in ipairs(holder:GetDescendants()) do
            if d:IsA("UIStroke") then d.Color = col
            elseif d:IsA("ImageLabel") then d.ImageColor3 = col
            elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then d.BackgroundColor3 = col end
        end
    end

    local function icon(parent, kind, size, col)
        size = size or 16 col = col or P.icon
        local h = Instance.new("Frame")
        h.Name = "icon_" .. kind h.BackgroundTransparency = 1
        h.Size = UDim2.new(0, size, 0, size) h.Parent = parent
        local c, s = size / 2, size / 16
        local function ring(dia, th)
            local r = Instance.new("Frame")
            r.BackgroundTransparency = 1 r.AnchorPoint = Vector2.new(0.5, 0.5)
            r.Position = UDim2.new(0.5, 0, 0.5, 0) r.Size = UDim2.new(0, dia * s, 0, dia * s)
            r.Parent = h circle(r) stroke(r, col, (th or 1.4) * s, 0.05) return r
        end
        local function dot(dia)
            local d = Instance.new("Frame")
            d.BackgroundColor3 = col d.BorderSizePixel = 0
            d.AnchorPoint = Vector2.new(0.5, 0.5) d.Position = UDim2.new(0.5, 0, 0.5, 0)
            d.Size = UDim2.new(0, dia * s, 0, dia * s) d.Parent = h circle(d) return d
        end
        if kind == "target" then
            ring(10) dot(3)
            tick(h, c, 1.5 * s, 1.4 * s, 3 * s, col) tick(h, c, size - 1.5 * s, 1.4 * s, 3 * s, col)
            tick(h, 1.5 * s, c, 3 * s, 1.4 * s, col) tick(h, size - 1.5 * s, c, 3 * s, 1.4 * s, col)
        elseif kind == "eye" then
            local lid = ring(13, 1.4)
            lid.Size = UDim2.new(0, 15 * s, 0, 10 * s) lid.UIStroke.Thickness = 1.4 * s
            dot(4)
        elseif kind == "zap" then
            tick(h, c + 1.6 * s, c - 2.4 * s, 1.7 * s, 9 * s, col, -22)
            tick(h, c - 1.6 * s, c + 2.4 * s, 1.7 * s, 9 * s, col, -22)
            tick(h, c, c, 6 * s, 1.7 * s, col, 0)
        elseif kind == "settings" then
            ring(11) dot(3.2)
            for i = 0, 7 do
                local a = math.rad(i * 45) local r = 6.4 * s
                tick(h, c + math.cos(a) * r, c + math.sin(a) * r, 1.8 * s, 3.4 * s, col, i * 45)
            end
        end
        return h
    end

    local api = {}
    api.palette = P
    api.alpha = A
    api.config = CONFIG
    api.icons = { "target", "eye", "zap", "settings" }

    function api.new(cfg)
        cfg = cfg or {}
        local state = cfg.state or {}
        local TITLE = tostring(cfg.title or "SCRIPT")
        local VERSION = tostring(cfg.version or "v1")
        local KEY = cfg.key or state.ui_key or Enum.KeyCode.RightShift
        state.ui_key = KEY

        -- повторный запуск не должен копить BlurEffect в Lighting: старый снимаем
        pcall(function()
            local old = Lighting:FindFirstChild(CONFIG.brand .. "_Glass")
            if old then old:Destroy() end
        end)
        local blur = Instance.new("BlurEffect")
        blur.Name = CONFIG.brand .. "_Glass"
        blur.Size = CONFIG.blur
        blur.Enabled = true
        blur.Parent = Lighting

        local cands = {}
        do
            local function push(fn)
                local ok, r = pcall(fn)
                if ok and r then cands[#cands + 1] = r end
            end
            -- PlayerGui идёт ПЕРВЫМ. Любое движение в CoreGui заставляет
            -- TopbarPlus — а он есть в большинстве игр, включая HD Admin —
            -- перебрать свои модули, среди которых
            -- CoreGui.RobloxGui.Modules.Common.Locales. Под экзекутором он
            -- возвращает nil, и строка 1 падает с "attempt to call a nil value".
            -- В PlayerGui нашего окна для этого перебора просто не существует.
            push(function()
                local plr = SVC("Players").LocalPlayer
                return plr and plr:FindFirstChildOfClass("PlayerGui") or nil
            end)
            push(function() return gethui and gethui() or nil end)
            push(function() return get_hidden_gui and get_hidden_gui() or nil end)
            push(function() return get_hui and get_hui() or nil end)
            push(function() return SVC("CoreGui") end)
        end

        local gui = Instance.new("ScreenGui")
        gui.Name = CONFIG.brand
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.DisplayOrder = 999

        -- Сначала вычищаем окно прошлого запуска во ВСЕХ кандидатах, потом крепим
        -- новое. Иначе при смене места (CoreGui -> PlayerGui) старая копия осталась
        -- бы висеть там, откуда мы ушли.
        for _, p in ipairs(cands) do
            if p then
                pcall(function()
                    local old = p:FindFirstChild(CONFIG.brand)
                    if old and old ~= gui then old:Destroy() end
                end)
            end
        end

        -- Крепим по очереди: gethui есть не везде, а запись в CoreGui бывает
        -- запрещена. Раньше присваивание шло без pcall и молча роняло весь скрипт
        -- до первой печати — снаружи это выглядело как «скрипт не работает».
        local parent = nil
        for _, p in ipairs(cands) do
            if p then
                local ok = pcall(function() gui.Parent = p end)
                if ok and gui.Parent == p then parent = p break end
            end
        end
        if not parent then
            warn("[Style A] не удалось закрепить ScreenGui — UI не появится")
            pcall(function() blur:Destroy() end)
            return nil
        end

        local WIN, SIDE, PAD = CONFIG.window, CONFIG.sidebar, CONFIG.pad
        local root = Instance.new("Frame")
        root.BackgroundTransparency = 1
        root.Size = UDim2.new(0, WIN.X + PAD * 2, 0, WIN.Y + PAD * 2)
        root.Position = UDim2.new(0.5, -(WIN.X / 2 + PAD), 0.5, -(WIN.Y / 2 + PAD))
        root.ZIndex = 1 root.Parent = gui

        local glow = Instance.new("Frame")
        glow.BackgroundColor3 = P.accent glow.BackgroundTransparency = 0.94
        glow.BorderSizePixel = 0 glow.Size = UDim2.new(1, 0, 1, 0) glow.ZIndex = 1
        glow.Parent = root corner(glow, 28)

        local win = Instance.new("Frame")
        win.BackgroundColor3 = P.bg win.BackgroundTransparency = 0.08
        win.BorderSizePixel = 0 win.Active = true
        win.Size = UDim2.new(0, WIN.X, 0, WIN.Y)
        win.Position = UDim2.new(0, PAD, 0, PAD)
        win.ZIndex = 2 win.Parent = root corner(win, 16)
        stroke(win, P.white, 1, A.stroke)

        local hi = Instance.new("Frame")
        hi.BackgroundColor3 = P.white hi.BackgroundTransparency = A.hilite
        hi.BorderSizePixel = 0 hi.Size = UDim2.new(1, -32, 0, 1)
        hi.Position = UDim2.new(0, 16, 0, 0) hi.ZIndex = 3 hi.Parent = win

        -- sidebar
        local side = Instance.new("Frame")
        side.BackgroundColor3 = P.white side.BackgroundTransparency = A.glass6
        side.BorderSizePixel = 0 side.Size = UDim2.new(0, SIDE, 1, 0)
        side.ZIndex = 3 side.Parent = win corner(side, 16)

        local mask = Instance.new("Frame")
        mask.BackgroundColor3 = P.white mask.BackgroundTransparency = A.glass6
        mask.BorderSizePixel = 0 mask.Size = UDim2.new(0, 16, 1, 0)
        mask.Position = UDim2.new(0, SIDE - 16, 0, 0) mask.ZIndex = 3 mask.Parent = win

        local edge = Instance.new("Frame")
        edge.BackgroundColor3 = P.white edge.BackgroundTransparency = A.row_line
        edge.BorderSizePixel = 0 edge.Size = UDim2.new(0, 1, 1, -24)
        edge.Position = UDim2.new(0, SIDE, 0, 12) edge.ZIndex = 4 edge.Parent = win

        local logo = label(side, tracked("— " .. CONFIG.mark), 13, P.text, "med")
        logo.Size = UDim2.new(1, -32, 0, 20) logo.Position = UDim2.new(0, 16, 0, 16) logo.ZIndex = 4

        local word = label(side, tracked(CONFIG.wordmark), 10, P.icon, "semi")
        word.Size = UDim2.new(1, -32, 0, 14) word.Position = UDim2.new(0, 16, 0, 38) word.ZIndex = 4

        local sub = label(side, string.upper(tostring(cfg.subtitle or "")), 9, P.dim, "med")
        sub.Size = UDim2.new(1, -32, 0, 12) sub.Position = UDim2.new(0, 16, 0, 56) sub.ZIndex = 4

        local nav = Instance.new("Frame")
        nav.BackgroundTransparency = 1 nav.Size = UDim2.new(1, -24, 0, 200)
        nav.Position = UDim2.new(0, 12, 0, 84) nav.ZIndex = 4 nav.Parent = side
        local navLay = Instance.new("UIListLayout")
        navLay.Padding = UDim.new(0, 6) navLay.SortOrder = Enum.SortOrder.LayoutOrder navLay.Parent = nav

        local foot = Instance.new("Frame")
        foot.BackgroundTransparency = 1 foot.Size = UDim2.new(1, -24, 0, 34)
        foot.Position = UDim2.new(0, 12, 1, -46) foot.ZIndex = 4 foot.Parent = side

        local chip = Instance.new("Frame")
        chip.BackgroundColor3 = P.white chip.BackgroundTransparency = A.track
        chip.BorderSizePixel = 0 chip.Size = UDim2.new(0, 58, 0, 22) chip.ZIndex = 5 chip.Parent = foot
        corner(chip, 7) stroke(chip, P.white, 1, A.row_line)
        local chipText = label(chip, "", 9, P.muted, "semi")
        chipText.Size = UDim2.new(1, 0, 1, 0) chipText.TextXAlignment = Enum.TextXAlignment.Center chipText.ZIndex = 6

        local ver = label(foot, VERSION .. " · STYLE A", 9, P.dim, "reg")
        ver.Size = UDim2.new(1, -64, 1, 0) ver.Position = UDim2.new(0, 64, 0, 0)
        ver.TextXAlignment = Enum.TextXAlignment.Right ver.ZIndex = 5

        -- topbar
        local top = Instance.new("Frame")
        top.BackgroundTransparency = 1 top.Size = UDim2.new(1, -(SIDE + 32), 0, 30)
        top.Position = UDim2.new(0, SIDE + 16, 0, 16) top.ZIndex = 3 top.Parent = win

        local pageTitle = label(top, "", 12, P.text, "semi")
        pageTitle.Size = UDim2.new(0, 150, 1, 0) pageTitle.ZIndex = 4

        local statChip = Instance.new("Frame")
        statChip.BackgroundColor3 = P.white statChip.BackgroundTransparency = A.track
        statChip.BorderSizePixel = 0 statChip.Size = UDim2.new(0, 132, 0, 22)
        statChip.Position = UDim2.new(1, -160, 0.5, -11) statChip.ZIndex = 4 statChip.Parent = top
        corner(statChip, 8) stroke(statChip, P.white, 1, A.row_line)
        local statDot = Instance.new("Frame")
        statDot.BackgroundColor3 = P.accent statDot.BorderSizePixel = 0
        statDot.Size = UDim2.new(0, 6, 0, 6) statDot.Position = UDim2.new(0, 9, 0.5, -3)
        statDot.ZIndex = 5 statDot.Parent = statChip circle(statDot)
        local statText = label(statChip, "—", 10, P.muted, "med")
        statText.Size = UDim2.new(1, -22, 1, 0) statText.Position = UDim2.new(0, 20, 0, 0) statText.ZIndex = 5

        local minBtn = mkButton()
        minBtn.BackgroundTransparency = 1 minBtn.Text = "" minBtn.AutoButtonColor = false
        minBtn.Size = UDim2.new(0, 22, 0, 22) minBtn.Position = UDim2.new(1, -34, 0, 18)
        minBtn.ZIndex = 6 minBtn.Parent = win
        local minGlyph = label(minBtn, "—", 13, P.dim, "med")
        minGlyph.Size = UDim2.new(1, 0, 1, 0) minGlyph.TextXAlignment = Enum.TextXAlignment.Center minGlyph.ZIndex = 7
        minBtn.MouseEnter:Connect(function() minGlyph.TextColor3 = P.text end)
        minBtn.MouseLeave:Connect(function() minGlyph.TextColor3 = P.dim end)

        local content = Instance.new("Frame")
        content.BackgroundTransparency = 1 content.Size = UDim2.new(1, -(SIDE + 32), 1, -62)
        content.Position = UDim2.new(0, SIDE + 16, 0, 48) content.ZIndex = 3 content.Parent = win

        -- drag rail
        local rail = mkButton()
        rail.BackgroundTransparency = 1 rail.Text = "" rail.AutoButtonColor = false
        rail.Size = UDim2.new(1, 0, 0, 44) rail.ZIndex = 2 rail.Parent = win

        local pill = mkButton()
        pill.BackgroundColor3 = P.bg pill.BackgroundTransparency = 0.12 pill.Text = ""
        pill.AutoButtonColor = false pill.Size = UDim2.new(0, 42, 0, 42)
        pill.Position = UDim2.new(0, 16, 0.5, -21) pill.Visible = false
        pill.ZIndex = 20 pill.Parent = gui circle(pill) stroke(pill, P.white, 1, A.stroke)
        local pillText = label(pill, "JS", 12, P.icon, "semi")
        pillText.Size = UDim2.new(1, 0, 1, 0) pillText.TextXAlignment = Enum.TextXAlignment.Center pillText.ZIndex = 21

        -- toasts
        local toastHolder = Instance.new("Frame")
        toastHolder.BackgroundTransparency = 1 toastHolder.Size = UDim2.new(0, 250, 1, -32)
        toastHolder.Position = UDim2.new(1, -266, 0, 16) toastHolder.ZIndex = 20 toastHolder.Parent = gui
        local toastLay = Instance.new("UIListLayout")
        toastLay.Padding = UDim.new(0, 8) toastLay.HorizontalAlignment = Enum.HorizontalAlignment.Right
        toastLay.SortOrder = Enum.SortOrder.LayoutOrder toastLay.Parent = toastHolder
        local toastN = 0

        -- watermark
        local wm = Instance.new("Frame")
        wm.BackgroundColor3 = P.white wm.BackgroundTransparency = A.glass8
        wm.BorderSizePixel = 0 wm.Size = UDim2.new(0, 200, 0, 26)
        wm.Position = UDim2.new(0, 16, 0, 16) wm.ZIndex = 20 wm.Parent = gui
        corner(wm, 10) stroke(wm, P.white, 1, A.row_line)
        local wmMark = label(wm, tracked("— " .. CONFIG.mark), 10, P.text, "med")
        wmMark.Size = UDim2.new(0, 70, 1, 0) wmMark.Position = UDim2.new(0, 12, 0, 0) wmMark.ZIndex = 21
        local wmWord = label(wm, "SCRIPTS", 10, P.icon, "semi")
        wmWord.Size = UDim2.new(0, 48, 1, 0) wmWord.Position = UDim2.new(0, 80, 0, 0) wmWord.ZIndex = 21
        local wmTitle = label(wm, TITLE, 9, P.muted, "semi")
        wmTitle.Size = UDim2.new(0, 70, 1, 0) wmTitle.Position = UDim2.new(1, -82, 0, 0)
        wmTitle.TextXAlignment = Enum.TextXAlignment.Right wmTitle.ZIndex = 21

        local ui = {
            gui = gui, window = win, state = state,
            blur = blur, watermark = wm, toasts = toastHolder, content = content,
            pages = {}, nav = {}, rows = {}, listening = nil,
        }

        -- ---------- elements ----------
        local function newPage(name)
            local sc = Instance.new("ScrollingFrame")
            sc.Name = name sc.BackgroundTransparency = 1 sc.BorderSizePixel = 0
            sc.Size = UDim2.new(1, 0, 1, 0) sc.ScrollBarThickness = 2
            sc.ScrollBarImageColor3 = P.white sc.ScrollBarImageTransparency = 0.82
            sc.CanvasSize = UDim2.new(0, 0, 0, 0) sc.Visible = false sc.ZIndex = 3 sc.Parent = content
            local lay = Instance.new("UIListLayout")
            lay.Padding = UDim.new(0, 8) lay.SortOrder = Enum.SortOrder.LayoutOrder lay.Parent = sc
            local pad = Instance.new("UIPadding")
            pad.PaddingRight = UDim.new(0, 10) pad.PaddingBottom = UDim.new(0, 12) pad.Parent = sc
            lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                sc.CanvasSize = UDim2.new(0, 0, 0, lay.AbsoluteContentSize.Y + 12)
            end)
            return sc
        end

        local function rowBox(parent, h)
            local r = Instance.new("Frame")
            r.BackgroundColor3 = P.white r.BackgroundTransparency = A.row
            r.BorderSizePixel = 0 r.Size = UDim2.new(1, 0, 0, h or 40) r.ZIndex = 3 r.Parent = parent
            corner(r, CONFIG.radius) stroke(r, P.white, 1, A.row_line)
            return r
        end

        -- свитч: ON #7C3AED / OFF #FFFFFF1E, кноб белый, ход анимирован
        local function mkSwitch(parent, key, on_change)
            local pillS = Instance.new("Frame")
            pillS.BackgroundColor3 = state[key] and P.accent or P.white
            pillS.BackgroundTransparency = state[key] and 0 or A.sw_off
            pillS.BorderSizePixel = 0 pillS.Size = UDim2.new(0, 34, 0, 18)
            pillS.Position = UDim2.new(1, -48, 0.5, -9) pillS.ZIndex = 5 pillS.Parent = parent
            circle(pillS)
            local knob = Instance.new("Frame")
            knob.BackgroundColor3 = P.white knob.BorderSizePixel = 0
            knob.Size = UDim2.new(0, 14, 0, 14)
            knob.Position = state[key] and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
            knob.ZIndex = 6 knob.Parent = pillS circle(knob)
            local sw = {}
            function sw:Refresh()
                local on = state[key] and true or false
                tween(pillS, {
                    BackgroundColor3 = on and P.accent or P.white,
                    BackgroundTransparency = on and 0 or A.sw_off,
                }, 0.16)
                tween(knob, {
                    Position = on and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7),
                }, 0.16)
            end
            function sw:Toggle()
                state[key] = not state[key]
                self:Refresh()
                if on_change then on_change(state[key]) end
            end
            return sw
        end

        local function pageHandle(sc)
            local ph = {}
            function ph:Section(text)
                local f = Instance.new("Frame")
                f.BackgroundTransparency = 1 f.Size = UDim2.new(1, 0, 0, 22) f.ZIndex = 3 f.Parent = sc
                local l = label(f, tracked(string.upper(text)), 10, P.dim, "semi")
                l.Size = UDim2.new(1, 0, 1, 0) l.ZIndex = 4
                return f
            end
            function ph:Info(text)
                local r = rowBox(sc, 34)
                local l = label(r, text, 11, P.dim, "reg")
                l.Size = UDim2.new(1, -28, 1, 0) l.Position = UDim2.new(0, 14, 0, 0) l.ZIndex = 5
                return r
            end
            function ph:Toggle(text, key, def)
                if def ~= nil and state[key] == nil then state[key] = def end
                local r = rowBox(sc, 40)
                local l = label(r, text, 12, state[key] and P.text or P.muted, "reg")
                l.Size = UDim2.new(1, -66, 1, 0) l.Position = UDim2.new(0, 14, 0, 0) l.ZIndex = 5
                local b = mkButton()
                b.BackgroundTransparency = 1 b.Text = "" b.AutoButtonColor = false
                b.Size = UDim2.new(1, 0, 1, 0) b.ZIndex = 7 b.Parent = r
                local sw = mkSwitch(r, key)
                b.MouseButton1Click:Connect(function()
                    sw:Toggle()
                    l.TextColor3 = state[key] and P.text or P.muted
                end)
                ui.rows[key] = { Refresh = function()
                    sw:Refresh()
                    l.TextColor3 = state[key] and P.text or P.muted
                end }
                return sw
            end            function ph:Slider(text, key, min, max, suffix, on_change, fmt)
                suffix = suffix or ""
                if state[key] == nil then state[key] = min end
                local r = rowBox(sc, 54)
                local l = label(r, text, 12, P.muted, "reg")
                l.Size = UDim2.new(1, -100, 0, 16) l.Position = UDim2.new(0, 14, 0, 8) l.ZIndex = 5
                local function format(v)
                    if fmt then return fmt(v) end
                    return tostring(v) .. suffix
                end
                local val = label(r, format(state[key]), 11, P.icon, "semi")
                val.Size = UDim2.new(0, 70, 0, 16) val.Position = UDim2.new(1, -84, 0, 8)
                val.TextXAlignment = Enum.TextXAlignment.Right val.ZIndex = 5
                local track = Instance.new("Frame")
                track.BackgroundColor3 = P.white track.BackgroundTransparency = A.track
                track.BorderSizePixel = 0 track.Size = UDim2.new(1, -28, 0, 4)
                track.Position = UDim2.new(0, 14, 0, 36) track.ZIndex = 5 track.Parent = r circle(track)
                local fill = Instance.new("Frame")
                fill.BackgroundColor3 = P.accent fill.BorderSizePixel = 0
                fill.Size = UDim2.new(0, 0, 1, 0) fill.ZIndex = 6 fill.Parent = track circle(fill)
                local grad = Instance.new("UIGradient")
                grad.Color = ColorSequence.new(P.accent, P.accent_hi) grad.Parent = fill
                local knob = Instance.new("Frame")
                knob.BackgroundColor3 = P.white knob.BorderSizePixel = 0
                knob.AnchorPoint = Vector2.new(0.5, 0.5) knob.Size = UDim2.new(0, 12, 0, 12)
                knob.Position = UDim2.new(0, 0, 0.5, 0) knob.ZIndex = 7 knob.Parent = track circle(knob)
                local hit = mkButton()
                hit.BackgroundTransparency = 1 hit.Text = "" hit.AutoButtonColor = false
                hit.Size = UDim2.new(1, 0, 0, 24) hit.Position = UDim2.new(0, 0, 0, 24)
                hit.ZIndex = 8 hit.Parent = r
                local function ratio()
                    return math.clamp((state[key] - min) / math.max(1e-6, (max - min)), 0, 1)
                end
                local function paint(a)
                    fill.Size = UDim2.new(a, 0, 1, 0)
                    knob.Position = UDim2.new(a, 0, 0.5, 0)
                end
                local step = (max - min) >= 10
                local function setFromX(x)
                    local ax, w = track.AbsolutePosition.X, track.AbsoluteSize.X
                    if w <= 0 then return end
                    local a = math.clamp((x - ax) / w, 0, 1)
                    local v = min + a * (max - min)
                    v = step and math.floor(v + 0.5) or math.floor(v * 100 + 0.5) / 100
                    state[key] = v val.Text = format(v) paint(a)
                    if on_change then on_change(v) end
                end
                local drag = false
                hit.InputBegan:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                        drag = true setFromX(i.Position.X)
                    end
                end)
                UserInputService.InputChanged:Connect(function(i)
                    if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                        setFromX(i.Position.X)
                    end
                end)
                UserInputService.InputEnded:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
                end)
                paint(ratio())
                ui.rows[key] = { Refresh = function() val.Text = format(state[key]) paint(ratio()) end }
                return r
            end
            function ph:Cycle(text, key, options, on_change)
                if state[key] == nil then state[key] = options[1] end
                local r = rowBox(sc, 40)
                local l = label(r, text, 12, P.muted, "reg")
                l.Size = UDim2.new(1, -120, 1, 0) l.Position = UDim2.new(0, 14, 0, 0) l.ZIndex = 5
                local b = mkButton()
                b.BackgroundColor3 = P.white b.BackgroundTransparency = A.track
                b.BorderSizePixel = 0 b.Text = "" b.AutoButtonColor = false
                b.Size = UDim2.new(0, 104, 0, 24) b.Position = UDim2.new(1, -116, 0.5, -12)
                b.ZIndex = 6 b.Parent = r corner(b, 8) stroke(b, P.white, 1, A.row_line)
                local bl = label(b, tostring(state[key]), 10, P.icon, "semi")
                bl.Size = UDim2.new(1, 0, 1, 0) bl.TextXAlignment = Enum.TextXAlignment.Center bl.ZIndex = 7
                b.MouseButton1Click:Connect(function()
                    local idx = 1
                    for i, o in ipairs(options) do
                        if tostring(o) == tostring(state[key]) then idx = i break end
                    end
                    idx = (idx % #options) + 1
                    state[key] = options[idx] bl.Text = tostring(state[key])
                    if on_change then on_change(state[key]) end
                end)
                ui.rows[key] = { Refresh = function() bl.Text = tostring(state[key]) end }
                return r
            end
            function ph:Keybind(text, key)
                local r = rowBox(sc, 40)
                local l = label(r, text, 12, P.muted, "reg")
                l.Size = UDim2.new(1, -120, 1, 0) l.Position = UDim2.new(0, 14, 0, 0) l.ZIndex = 5
                local b = mkButton()
                b.BackgroundColor3 = P.white b.BackgroundTransparency = A.track
                b.BorderSizePixel = 0 b.Text = "" b.AutoButtonColor = false
                b.Size = UDim2.new(0, 104, 0, 24) b.Position = UDim2.new(1, -116, 0.5, -12)
                b.ZIndex = 6 b.Parent = r corner(b, 8)
                local bs = stroke(b, P.white, 1, A.row_line)
                local bl = label(b, state[key] and state[key].Name or "—", 10, P.muted, "semi")
                bl.Size = UDim2.new(1, 0, 1, 0) bl.TextXAlignment = Enum.TextXAlignment.Center bl.ZIndex = 7
                local function refresh()
                    bl.Text = state[key] and state[key].Name or "—"
                    bl.TextColor3 = P.muted bs.Color = P.white bs.Transparency = A.row_line
                end
                b.MouseButton1Click:Connect(function()
                    ui.listening = key
                    bl.Text = "PRESS KEY" bl.TextColor3 = P.icon
                    bs.Color = P.accent bs.Transparency = 0.2
                end)
                ui.rows[key] = { Refresh = refresh }
                return r
            end
            function ph:Button(text, style, cb)
                local b = mkButton()
                b.BorderSizePixel = 0 b.AutoButtonColor = false b.Text = ""
                b.Size = UDim2.new(1, 0, 0, 34) b.ZIndex = 4 b.Parent = sc corner(b, 12)
                local ghost = (style == "ghost")
                b.BackgroundColor3 = P.white b.BackgroundTransparency = ghost and A.row or 0
                local bl = label(b, text, 11, ghost and P.muted or P.action_fg, "semi")
                bl.Size = UDim2.new(1, 0, 1, 0) bl.TextXAlignment = Enum.TextXAlignment.Center bl.ZIndex = 5
                if ghost then stroke(b, P.white, 1, A.row_line) end
                b.MouseButton1Click:Connect(function() pcall(cb) end)
                b.MouseEnter:Connect(function()
                    if ghost then tween(b, { BackgroundTransparency = A.track }, 0.12) bl.TextColor3 = P.text
                    else tween(b, { BackgroundTransparency = 0.12 }, 0.12) end
                end)
                b.MouseLeave:Connect(function()
                    if ghost then tween(b, { BackgroundTransparency = A.row }, 0.12) bl.TextColor3 = P.muted
                    else tween(b, { BackgroundTransparency = 0 }, 0.12) end
                end)
                return b
            end
            return ph
        end

        -- ---------- tabs ----------
        local function switchTab(name)
            for n, p in pairs(ui.pages) do p.Visible = (n == name) end
            for n, it in pairs(ui.nav) do
                local on = (n == name)
                it.label.TextColor3 = on and P.text or P.dim
                it.wrap.BackgroundTransparency = on and A.row or 1
                it.rail.BackgroundTransparency = on and 0 or 1
                tint(it.holder, on and P.icon or P.dim)
            end
            ui.current = name
        end

        local tabOrder = 0
        function ui:Tab(name, iconName)
            local sc = newPage(name)
            tabOrder = tabOrder + 1
            local b = mkButton()
            b.Name = name b.BackgroundTransparency = 1 b.Text = "" b.AutoButtonColor = false
            b.Size = UDim2.new(1, 0, 0, 38) b.LayoutOrder = tabOrder b.ZIndex = 5 b.Parent = nav
            local rl = Instance.new("Frame")
            rl.BackgroundColor3 = P.accent rl.BackgroundTransparency = 1 rl.BorderSizePixel = 0
            rl.Size = UDim2.new(0, 2, 0, 18) rl.Position = UDim2.new(0, -8, 0.5, -9) rl.ZIndex = 6 rl.Parent = b
            circle(rl)
            local wrap = Instance.new("Frame")
            wrap.BackgroundColor3 = P.white wrap.BackgroundTransparency = 1 wrap.BorderSizePixel = 0
            wrap.Size = UDim2.new(0, 28, 0, 28) wrap.Position = UDim2.new(0, 6, 0.5, -14) wrap.ZIndex = 6 wrap.Parent = b
            corner(wrap, 9)
            local ic = icon(wrap, iconName or "target", 16, P.dim)
            ic.Position = UDim2.new(0.5, -8, 0.5, -8) ic.ZIndex = 7
            local l = label(b, name, 12, P.dim, "med")
            l.Size = UDim2.new(1, -48, 1, 0) l.Position = UDim2.new(0, 42, 0, 0) l.ZIndex = 6
            b.MouseEnter:Connect(function() if ui.current ~= name then wrap.BackgroundTransparency = A.glass6 end end)
            b.MouseLeave:Connect(function() if ui.current ~= name then wrap.BackgroundTransparency = 1 end end)
            b.MouseButton1Click:Connect(function()
                switchTab(name)
                pageTitle.Text = string.upper(name)
            end)
            ui.pages[name] = sc
            ui.nav[name] = { label = l, holder = ic, wrap = wrap, rail = rl }
            if not ui.current then
                switchTab(name)
                pageTitle.Text = string.upper(name)
            end
            return pageHandle(sc)
        end

        function ui:Toast(text, kind)
            if state.ui_toasts == false then return end
            toastN = toastN + 1
            local t = Instance.new("Frame")
            t.BackgroundColor3 = P.white t.BackgroundTransparency = A.glass8
            t.BorderSizePixel = 0 t.Size = UDim2.new(1, 0, 0, 38)
            t.LayoutOrder = toastN t.ZIndex = 21 t.Parent = toastHolder
            corner(t, 12) stroke(t, P.white, 1, A.row_line)
            local rl = Instance.new("Frame")
            rl.BackgroundColor3 = (kind == "warn" and P.warn) or (kind == "ok" and P.ok) or P.accent
            rl.BorderSizePixel = 0 rl.Size = UDim2.new(0, 2, 1, -16)
            rl.Position = UDim2.new(0, 10, 0, 8) rl.ZIndex = 22 rl.Parent = t circle(rl)
            local l = label(t, text, 11, P.text, "med")
            l.Size = UDim2.new(1, -30, 1, 0) l.Position = UDim2.new(0, 20, 0, 0) l.ZIndex = 22
            l.TextTransparency = 1
            tween(t, { BackgroundTransparency = A.glass8 }, 0.2)
            tween(l, { TextTransparency = 0 }, 0.2)
            task.delay(3.2, function()
                if not t.Parent then return end
                tween(t, { BackgroundTransparency = 0.999 }, 0.25)
                tween(l, { TextTransparency = 1 }, 0.25)
                task.delay(0.3, function() pcall(function() t:Destroy() end) end)
            end)
        end

        function ui:Stat(initial)
            statText.Text = tostring(initial or "—")
            return function(text, color)
                statText.Text = tostring(text)
                statDot.BackgroundColor3 = color or P.accent
            end
        end

        function ui:Banner(text)
            wmTitle.Text = string.upper(tostring(text))
        end

        function ui:Destroy()
            pcall(function() blur:Destroy() end)
            pcall(function() gui:Destroy() end)
        end

        -- ---------- input ----------
        do
            local drag, ds, sp = false, nil, nil
            rail.InputBegan:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                    drag, ds, sp = true, i.Position, root.Position
                end
            end)
            UserInputService.InputChanged:Connect(function(i)
                if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                    local d = i.Position - ds
                    root.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
                end
            end)
            UserInputService.InputEnded:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
            end)
        end

        local function setVisible(v)
            root.Visible = v pill.Visible = not v
        end
        minBtn.MouseButton1Click:Connect(function() setVisible(false) end)
        pill.MouseButton1Click:Connect(function() setVisible(true) end)

        UserInputService.InputBegan:Connect(function(i, gp)
            if gp then return end
            if ui.listening then
                if i.UserInputType == Enum.UserInputType.Keyboard then
                    state[ui.listening] = i.KeyCode
                    if ui.listening == "ui_key" then KEY = i.KeyCode end
                    local r = ui.rows[ui.listening]
                    if r and r.Refresh then pcall(r.Refresh) end
                    ui.listening = nil
                    chipText.Text = string.upper(string.sub(KEY.Name, 1, 8))
                    ui:Toast("Key: " .. KEY.Name, "ok")
                end
                return
            end
            if chipText.Text == "" then chipText.Text = string.upper(string.sub(KEY.Name, 1, 8)) end
            if i.KeyCode == KEY then setVisible(not root.Visible) end
        end)
        chipText.Text = string.upper(string.sub(KEY.Name, 1, 8))

        -- Страховка: строки создаются лениво, при вызове :Tab() из скрипта,
        -- поэтому одного прохода внутри label() мало. Раз в секунду добираем
        -- всё, что появилось после сборки окна.
        task.spawn(function()
            for _ = 1, 12 do
                task.wait(1)
                for _, d in ipairs(gui:GetDescendants()) do
                    if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                        if d.AutoLocalize then pcall(function() d.AutoLocalize = false end) end
                    end
                end
            end
        end)

        return ui
    end

    return api
end)()
-- == /VANTA STYLE A SHELL ==

local UI = StyleA.new({
    state    = State,
    title    = "WH",
    subtitle = "generic shooter",
    version  = "v2",
})

local setStat = UI:Stat("seen 0 / alive 0")

-- ===== UNLOAD (снять весь Drawing-оверлей: игроки + глобальные + коннекты) =====
local function unloadAll()
    if unloaded then return end
    unloaded = true
    stopAntiAfk()
    if connRender then
        pcall(function() connRender:Disconnect() end)
        connRender = nil
    end
    if connHeartbeat then
        pcall(function() connHeartbeat:Disconnect() end)
        connHeartbeat = nil
    end
    pcall(function() fovCircle:Remove() end)
    for i = 1, #crossLines do
        local o = crossLines[i]
        pcall(function() o:Remove() end)
    end
    for p, it in pairs(items) do
        dropItem(it)
        items[p] = nil
    end
    pcall(function() UI:Destroy() end)
end

-- Visuals
local tabVisuals = UI:Tab("Visuals", "eye")
tabVisuals:Section("players")
tabVisuals:Toggle("Wallhack", "enabled", true)
tabVisuals:Toggle("Boxes", "boxes", true)
tabVisuals:Toggle("Names + distance", "names", true)
tabVisuals:Toggle("Weapon", "esp_weapon", true)
tabVisuals:Toggle("Health bar", "esp_healthbar", true)
tabVisuals:Toggle("Tracers", "tracers", false)
tabVisuals:Toggle("Skeleton", "esp_skeleton", false)
tabVisuals:Toggle("Offscreen arrows", "esp_arrows", false)
tabVisuals:Toggle("Crosshair", "crosshair", false)
tabVisuals:Section("style")
tabVisuals:Cycle("Box style", "box_style", { "2D", "Corner", "Filled" })
tabVisuals:Toggle("Distance fade", "dist_fade", false)
tabVisuals:Section("aim")
tabVisuals:Toggle("FOV ring", "fov_ring", true)
tabVisuals:Slider("FOV size", "fov_size", 40, 600, "px")
tabVisuals:Section("misc")
tabVisuals:Toggle("Anti-AFK", "antiafk", true)

-- Targets
local tabTargets = UI:Tab("Targets", "target")
tabTargets:Section("filter")
tabTargets:Toggle("Enemies only", "enemies_only", true)
tabTargets:Toggle("Team check", "team_check", true)
tabTargets:Slider("Max distance", "maxdist", 300, 3000, "m")

-- Config
local tabConfig = UI:Tab("Config", "settings")
tabConfig:Section("interface")
tabConfig:Keybind("Toggle key", "ui_key")
tabConfig:Toggle("Notifications", "ui_toasts", true)
tabConfig:Section("session")
tabConfig:Button("Unload JakoScripts", "ghost", unloadAll)
tabConfig:Info("Drawing-оверлей: в игре не создаётся ни одной детали.")

-- ===== LOOP (боксы каждый кадр — плавно и дёшево) =====
connRender = RunService.RenderStepped:Connect(overlayTick)

local tStat = 0
connHeartbeat = RunService.Heartbeat:Connect(function(dt)
    tStat += dt
    if tStat >= 0.5 then
        tStat = 0
        syncAntiAfk()
        setStat("seen " .. dbgShow .. " / alive " .. dbgAlive)
    end
end)

syncAntiAfk()

UI:Toast("JakoScripts WH v2 loaded", "ok")
print("[JakoScripts WH v2 · Style A] loaded")
