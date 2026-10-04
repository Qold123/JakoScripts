-- JakoScripts PISTOL ARENA v1 | Luau | [Ранговая] Арена пистолетов | VANTA Style A
-- Аимбот для FPS (доводка камеры, FOV + воллчек + сглаживание), триггербот,
-- ESP-оверлей (боксы/ники/дистанция). Только Drawing — деталей в игре нет.
-- Ранкед = античит строже: только альт, legit-настройки по умолчанию.
-- UI: Style A — окно 480x360, сайдбар 150, вкладки Combat / Visuals / Movement / Config,
-- RightShift — скрыть окно. Уведомления — тосты шелла, StarterGui:SetCore(...) не вызывается.
-- Запуск: loadstring(game:HttpGet("RAW_URL"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

if not Drawing then
    warn("[JakoScripts] нет Drawing в executor — оверлей не построить")
    return
end

-- mouse1click есть не во всех экзекуторах: держим локалом, вызов идёт не в глобал
local mouse1click = mouse1click or function() end

-- ===== STATE =====
local State = {
    aimbot = true,
    aim_hold = true,        -- только пока зажата клавиша
    aim_key = Enum.KeyCode.E,
    aim_part = "Head",
    aim_fov = 110,
    aim_smooth = 25,        -- 1..100, меньше = плавнее/легитнее
    aim_wallcheck = true,
    aim_maxdist = 1200,

    triggerbot = false,     -- авто-выстрел при наведении
    trigger_dist = 12,      -- пикселей от центра
    trigger_delay = 120,    -- мс, в расчёте делится на 1000

    esp = true,
    boxes = true,
    names = true,
    tracers = false,
    fov_show = true,
    maxdist = 1200,
    team_check = true,
    show_allies = false,

    antiafk = true,

    ui_watermark = true,
    ui_stats = true,
    ui_blur = true,
    ui_toasts = true,
    ui_key = Enum.KeyCode.RightShift,
}

local aiming = false
local rmbDown = false
local cachedPart, cachedPlr = nil, nil
local lastTrigger = 0
local dbgShown = 0
local teamSrc = "team"

-- ===== TEAM =====
local TeamReg, regAt = nil, 0
local function regTeam(plr)
    if TeamReg and type(TeamReg.players) == "table" then
        local ok, d = pcall(function() return TeamReg.players[plr] end)
        if ok and type(d) == "table" and d.team ~= nil then return tostring(d.team) end
        TeamReg = nil -- реестр есть, а игрока в нём нет: пересоберём на следующем круге
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
    local mt, pt = LocalPlayer.Team, plr.Team
    if mt ~= nil and pt ~= nil then teamSrc = "team" return mt == pt end
    local mc = LocalPlayer.Character
    local ch = plr.Character
    mc = mc and mc.Parent ~= Workspace and mc.Parent or nil
    local pc = ch and ch.Parent ~= Workspace and ch.Parent or nil
    if mc and pc then teamSrc = "cont" return mc == pc end
    local myT = regTeam(LocalPlayer)
    if myT then local pT = regTeam(plr) if pT then teamSrc = "reg" return pT == myT end end
    return false
end

local function aliveChar(plr)
    local ch = plr and plr.Character
    if not ch then return nil end
    local hum = ch:FindFirstChildOfClass("Humanoid", true)
    if not hum or hum.Health <= 0 then return nil end
    return ch
end

local function isEnemy(plr)
    if plr == LocalPlayer then return false end
    if not aliveChar(plr) then return false end
    if State.team_check then return not sameTeam(plr) end
    return true
end

local function canShow(plr)
    if plr == LocalPlayer then return false end
    if isEnemy(plr) then return true end
    -- своих показываем только живых: иначе бокс висит на трупе до респавна
    return State.show_allies and aliveChar(plr) ~= nil
end

local function findHead(ch) return ch and ch:FindFirstChild("Head", true) or nil end
local function findHrp(ch)
    return ch and (ch:FindFirstChild("HumanoidRootPart", true) or ch:FindFirstChild("Torso", true)) or nil
end

local function aimPartOf(char)
    if not char then return nil end
    return char:FindFirstChild(State.aim_part, true)
        or findHead(char)
        or char:FindFirstChild("UpperTorso", true)
        or char:FindFirstChild("HumanoidRootPart", true)
end

-- ===== VISIBILITY =====
local visParams = RaycastParams.new()
visParams.FilterType = Enum.RaycastFilterType.Exclude
visParams.IgnoreWater = true

local function vis(container, part)
    if not State.aim_wallcheck then return true end
    local ch = LocalPlayer.Character
    if not ch then return false end
    -- от глаз FPS-камеры: исключаем камеру, себя, руки (ViewModel) и служебную папку игры
    local excl = { Camera, ch }
    local vm = Workspace:FindFirstChild("ViewModel") or Workspace:FindFirstChild("Viewmodel")
    if vm then excl[#excl + 1] = vm end
    local ign = Workspace:FindFirstChild("ignore")
    if ign then excl[#excl + 1] = ign end
    visParams.FilterDescendantsInstances = excl
    local origin = Camera.CFrame.Position
    local res = Workspace:Raycast(origin, part.Position - origin, visParams)
    if res == nil then return true end
    if container and res.Instance:IsDescendantOf(container) then return true end
    return false
end

-- ===== AIMBOT =====
local function aimActive()
    if not State.aimbot then return false end
    if State.aim_hold then return aiming or rmbDown end
    return true
end

local function searchTarget()
    cachedPart, cachedPlr = nil, nil
    local myCh = LocalPlayer.Character
    local myHrp = myCh and myCh:FindFirstChild("HumanoidRootPart", true)
    if not myHrp then return end
    local center = Camera.ViewportSize / 2
    local cands = {}
    local all = Players:GetPlayers()
    for i = 1, #all do
        local p = all[i]
        if p ~= LocalPlayer and isEnemy(p) then
            local ch = p.Character
            local pt = ch and aimPartOf(ch)
            if pt and (myHrp.Position - pt.Position).Magnitude <= State.aim_maxdist then
                local sp, on = Camera:WorldToViewportPoint(pt.Position)
                if on then
                    local dd = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                    if dd <= State.aim_fov then
                        cands[#cands + 1] = { dd = dd, part = pt, who = p }
                    end
                end
            end
        end
    end
    if #cands == 0 then return end
    table.sort(cands, function(a, b) return a.dd < b.dd end)
    -- три ближайших к прицелу: если первые два за стеной, цель всё равно найдётся
    for i = 1, math.min(3, #cands) do
        local c = cands[i]
        if c.who.Character and vis(c.who.Character, c.part) then
            cachedPart, cachedPlr = c.part, c.who
            return
        end
    end
end

local function aimFrame()
    if not aimActive() then return end
    local pt = cachedPart
    if pt and pt.Parent then
        local k = math.clamp(State.aim_smooth / 100, 0.01, 1)
        Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, pt.Position), k)
        if State.triggerbot then
            local sp, on = Camera:WorldToViewportPoint(pt.Position)
            if on then
                local center = Camera.ViewportSize / 2
                if (Vector2.new(sp.X, sp.Y) - center).Magnitude <= State.trigger_dist then
                    local now = os.clock()
                    -- задержка задаётся в миллисекундах, в сравнении нужны секунды
                    if now - lastTrigger > State.trigger_delay / 1000 then
                        lastTrigger = now
                        pcall(function() mouse1click() end)
                    end
                end
            end
        end
    end
end

-- ===== OVERLAY (только Drawing) =====
local items = {}
local fovC = nil

local function getItem(p)
    local it = items[p]
    if not it then
        it = {}
        it.box = Drawing.new("Square")
        it.box.Thickness = 1 it.box.Filled = false it.box.Transparency = 0.9 it.box.Visible = false
        it.txt = Drawing.new("Text")
        it.txt.Size = 13 it.txt.Center = true it.txt.Outline = true it.txt.Transparency = 0.95 it.txt.Visible = false
        it.line = Drawing.new("Line")
        it.line.Thickness = 1 it.line.Transparency = 0.7 it.line.Visible = false
        items[p] = it
    end
    return it
end

local function hideItem(p)
    local it = items[p]
    if it then it.box.Visible = false it.txt.Visible = false it.line.Visible = false end
end

local function dropItem(p)
    local it = items[p]
    if it then
        pcall(function() it.box:Remove() end)
        pcall(function() it.txt:Remove() end)
        pcall(function() it.line:Remove() end)
        items[p] = nil
    end
end

Players.PlayerRemoving:Connect(function(p)
    dropItem(p)
    if cachedPlr == p then cachedPart, cachedPlr = nil, nil end
end)

pcall(function()
    fovC = Drawing.new("Circle")
    fovC.Thickness = 1 fovC.NumSides = 48 fovC.Filled = false
    fovC.Transparency = 0.7 fovC.Color = Color3.fromRGB(160, 140, 255)
end)

local function overlayTick()
    Camera = Workspace.CurrentCamera
    if fovC then
        fovC.Position = Camera.ViewportSize / 2
        fovC.Radius = State.aim_fov
        fovC.Visible = State.fov_show and State.aimbot
    end
    local myCh = LocalPlayer.Character
    local myHrp = myCh and myCh:FindFirstChild("HumanoidRootPart", true)
    local myPos = myHrp and myHrp.Position or Camera.CFrame.Position
    local shown = 0
    local all = Players:GetPlayers()
    for i = 1, #all do
        local p = all[i]
        if not State.esp or not canShow(p) then
            hideItem(p)
        else
            local ch = p.Character
            local head = findHead(ch)
            local hrp = findHrp(ch)
            if not head or not hrp then
                hideItem(p)
            else
                local dist = (myPos - hrp.Position).Magnitude
                if dist > State.maxdist then
                    hideItem(p)
                else
                    local it = getItem(p)
                    local p1, on1 = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.7, 0))
                    local p2, on2 = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 2.8, 0))
                    local h = (on1 and on2) and math.abs(p2.Y - p1.Y) or 0
                    if h < 5 then
                        hideItem(p)
                    else
                        shown += 1
                        local col = isEnemy(p) and Color3.fromRGB(255, 90, 70) or Color3.fromRGB(90, 180, 255)
                        local w = h * 0.6
                        it.box.Size = Vector2.new(w, h)
                        it.box.Position = Vector2.new(p1.X - w / 2, p1.Y)
                        it.box.Color = col
                        it.box.Visible = State.boxes
                        if State.names then
                            it.txt.Text = p.DisplayName .. " [" .. math.floor(dist + 0.5) .. "m]"
                            it.txt.Position = Vector2.new(p1.X, math.max(0, p1.Y - 16))
                            it.txt.Color = col
                            it.txt.Visible = true
                        else
                            it.txt.Visible = false
                        end
                        if State.tracers then
                            local vs = Camera.ViewportSize
                            it.line.From = Vector2.new(vs.X / 2, vs.Y)
                            it.line.To = Vector2.new(p1.X, p2.Y)
                            it.line.Color = col
                            it.line.Visible = true
                        else
                            it.line.Visible = false
                        end
                    end
                end
            end
        end
    end
    dbgShown = shown
end

-- ===== ANTI-AFK =====
do
    local ok, VU = pcall(function() return game:GetService("VirtualUser") end)
    if ok and VU then
        LocalPlayer.Idled:Connect(function()
            if not State.antiafk then return end
            -- без CaptureController виртуальный ввод игнорируется и кик всё равно приходит
            pcall(function()
                VU:CaptureController()
                VU:ClickButton2(Vector2.new())
            end)
        end)
    end
end

-- ===== МЕНЮ: ФОРВАРД-ДЕКЛАРАЦИИ =====
-- таблицы Drawing объявлены выше, а кнопка выгрузки живёт в меню ниже —
-- поэтому реализация teardownESP подставляется после сборки UI
local teardownESP = function() end

-- == VANTA STYLE A SHELL — inline block, правки только в шапке ==
local StyleA = (function()
    local SVC = game:GetService
    local UserInputService = SVC("UserInputService")
    local TweenService = SVC("TweenService")
    local Lighting = SVC("Lighting")

    local CONFIG = {
        theme    = "VantaViolet",
        brand    = "JakoScripts",
        mark     = "JAKO",
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
    local function tracked(s)
        local o = {}
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
        l.TextYAlignment = Enum.TextYAlignment.Center l.Parent = parent
        if FONT_OK then
            local f = (weight == "semi" and F_SEMI) or (weight == "med" and F_MED) or F_REG
            if f and pcall(function() l.FontFace = f end) then return l end
        end
        l.Font = (weight == "semi" and Enum.Font.GothamBold)
            or (weight == "med" and Enum.Font.GothamMedium) or Enum.Font.Gotham
        return l
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
            push(function() return gethui and gethui() or nil end)
            push(function() return get_hidden_gui and get_hidden_gui() or nil end)
            push(function() return get_hui and get_hui() or nil end)
            push(function() return SVC("CoreGui") end)
            push(function()
                local plr = SVC("Players").LocalPlayer
                return plr and plr:FindFirstChildOfClass("PlayerGui") or nil
            end)
        end

        local gui = Instance.new("ScreenGui")
        gui.Name = CONFIG.brand
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.DisplayOrder = 999

        -- Крепим по очереди: gethui есть не везде, а запись в CoreGui бывает
        -- запрещена. Раньше присваивание шло без pcall и молча роняло весь скрипт
        -- до первой печати — снаружи это выглядело как «скрипт не работает».
        local parent = nil
        for _, p in ipairs(cands) do
            if p then
                pcall(function()
                    local old = p:FindFirstChild(CONFIG.brand)
                    if old and old ~= gui then old:Destroy() end
                end)
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

        local minBtn = Instance.new("TextButton")
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
        local rail = Instance.new("TextButton")
        rail.BackgroundTransparency = 1 rail.Text = "" rail.AutoButtonColor = false
        rail.Size = UDim2.new(1, 0, 0, 44) rail.ZIndex = 2 rail.Parent = win

        local pill = Instance.new("TextButton")
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
        local wmMark = label(wm, tracked("— JAKO"), 10, P.text, "med")
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
                local b = Instance.new("TextButton")
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
                local hit = Instance.new("TextButton")
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
                local b = Instance.new("TextButton")
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
                local b = Instance.new("TextButton")
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
                local b = Instance.new("TextButton")
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
            local b = Instance.new("TextButton")
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

        return ui
    end

    return api
end)()
-- == /VANTA STYLE A SHELL ==

local UI = StyleA.new({
    state    = State,
    title    = "PISTOL ARENA",
    subtitle = "pistol arena",
    version  = "v1",
})

-- живой статус из тика ниже (бывший status.Text)
local setStat = UI:Stat("цель: —")

-- Combat
local tabCombat = UI:Tab("Combat", "target")
tabCombat:Section("Аим — доводка камеры")
tabCombat:Toggle("Аимбот", "aimbot", true)
tabCombat:Toggle("Только пока зажата клавиша", "aim_hold", true)
tabCombat:Toggle("Воллчек", "aim_wallcheck", true)
tabCombat:Slider("FOV", "aim_fov", 40, 400)
tabCombat:Slider("Плавность (меньше = плавнее)", "aim_smooth", 1, 100)
tabCombat:Slider("Макс. дистанция аима", "aim_maxdist", 300, 3000)
tabCombat:Cycle("Аим-часть: Голова / Торс", "aim_part", { "Head", "HumanoidRootPart" })
tabCombat:Keybind("Клавиша аима", "aim_key")
tabCombat:Section("Стрельба")
tabCombat:Toggle("Триггербот", "triggerbot", false)
tabCombat:Slider("Радиус триггера (px)", "trigger_dist", 4, 40)
tabCombat:Slider("Задержка триггера (мс)", "trigger_delay", 50, 500)
tabCombat:Section("Команда")
tabCombat:Toggle("Проверка команды", "team_check", true)
tabCombat:Info("Своих не целим. Источник стороны: Team, контейнеры, GC-реестр.")

-- Visuals
local tabVisuals = UI:Tab("Visuals", "eye")
tabVisuals:Section("Оверлей — только Drawing")
tabVisuals:Toggle("ESP", "esp", true)
tabVisuals:Toggle("Боксы", "boxes", true)
tabVisuals:Toggle("Ники + дистанция", "names", true)
tabVisuals:Toggle("Трассеры", "tracers", false)
tabVisuals:Toggle("FOV-круг", "fov_show", true)
tabVisuals:Slider("Макс. дистанция", "maxdist", 300, 3000)
tabVisuals:Toggle("Показывать своих", "show_allies", false)
tabVisuals:Button("Сбросить оверлей", "ghost", function()
    for p, _ in pairs(items) do dropItem(p) end
    cachedPart, cachedPlr = nil, nil
end)

-- Movement
local tabMovement = UI:Tab("Movement", "zap")
tabMovement:Section("Сессия")
tabMovement:Toggle("Анти-АФК", "antiafk", true)
tabMovement:Info("Ранкед: античит строже. По умолчанию всё в legit-режиме.")

-- Config
local tabConfig = UI:Tab("Config", "settings")
tabConfig:Section("interface")
tabConfig:Keybind("Toggle key", "ui_key")
tabConfig:Toggle("Notifications", "ui_toasts", true)
tabConfig:Toggle("Watermark", "ui_watermark", true)
tabConfig:Toggle("Watermark: счётчик", "ui_stats", true)
tabConfig:Toggle("Background blur", "ui_blur", true)
tabConfig:Section("session")
tabConfig:Button("Unload JakoScripts", "ghost", function()
    UI:Destroy()
    teardownESP()
end)
tabConfig:Info("JakoScripts • VANTA Style A")

-- ===== ВВОД =====
UserInputService.InputBegan:Connect(function(i, gp)
    if gp or UI.listening then return end
    if i.KeyCode == State.aim_key then aiming = true end
    if i.UserInputType == Enum.UserInputType.MouseButton2 then rmbDown = true end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.KeyCode == State.aim_key then aiming = false end
    if i.UserInputType == Enum.UserInputType.MouseButton2 then rmbDown = false end
end)

-- ===== КОЛБЭКИ МЕНЮ =====
teardownESP = function()
    State.esp = false
    State.boxes = false
    State.names = false
    State.tracers = false
    State.fov_show = false
    State.aimbot = false
    State.triggerbot = false
    cachedPart, cachedPlr = nil, nil
    for p, _ in pairs(items) do dropItem(p) end
    if fovC then pcall(function() fovC:Remove() end) end
    fovC = nil
end

-- ===== LOOPS =====
Camera = Workspace.CurrentCamera
RunService.RenderStepped:Connect(function()
    Camera = Workspace.CurrentCamera
    aimFrame()
    overlayTick()
end)

local tSel, tStat = 0, 0
RunService.Heartbeat:Connect(function(dt)
    tSel += dt tStat += dt
    if tSel >= 0.08 then
        tSel = 0
        if aimActive() then searchTarget() end
    end
    if tStat >= 0.5 then
        tStat = 0
        local tn = cachedPlr and cachedPlr.DisplayName or "—"
        setStat("цель: " .. tn .. " E" .. dbgShown .. " " .. teamSrc)
        if UI.watermark and UI.watermark.Visible ~= State.ui_watermark then
            UI.watermark.Visible = State.ui_watermark
        end
        if UI.blur and UI.blur.Enabled ~= State.ui_blur then
            UI.blur.Enabled = State.ui_blur
        end
        UI:Banner(State.ui_stats
            and ("PA v1 · " .. dbgShown .. " в кадре · src " .. teamSrc)
            or "PISTOL ARENA")
    end
end)

UI:Toast("JakoScripts PISTOL ARENA v1 загружен", "ok")
print("[JakoScripts PISTOL ARENA v1 · Style A] loaded")
