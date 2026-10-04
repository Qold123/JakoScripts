-- JakoScripts BLADE BALL v2.2 | Luau | Roblox Blade Ball | VANTA Style A
-- RAGE-режим: двойной цикл проверки, предсказание кручёных, паник-пари вблизи,
-- двойной фаер, компенсация пинга. Честно: 100% нет ни у кого — сервер режет
-- окно валидации и пинг не победить, но это потолок возможного. Бан реален.
--
-- v2.2 — про то, почему v2.1 «не работал» без единой ошибки в консоли:
--   1. ремоут искался ровно по пути Remotes.ParryButtonPress. Игра его
--      переименовала — скрипт грузился и молча ничего не делал. Теперь поиск
--      по смыслу (parry/block/deflect/guard) + выбор вручную в Timing.
--   2. мяч искался только в папке Balls. Теперь атрибут realBall → имя → сам
--      Workspace → папка, по порядку надёжности.
--   3. метка цели проверялась только как Highlight. Теперь ещё SelectionBox,
--      «target» в именах и атрибуты.
--   4. шелл крепил окно в непроверенный родитель без pcall и ронял весь скрипт
--      до первой печати. Теперь перебор gethui → hidden → hui → CoreGui → PlayerGui.
--   5. строка статуса стала диагностикой: видно, нашёлся ли ремоут и мяч.
-- Запуск: loadstring(game:HttpGet("RAW_URL"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- ===== STATE =====
local State = {
    enabled = true,
    target_only = true,   -- парить только когда мяч летит в тебя
    rage = true,          -- максимум: шире окно, без джиттера, паника, двойной фаер
    legit = false,        -- человекоподобная задержка + джиттер (выкл в rage)
    panic = true,         -- паник-пари когда мяч уже вплотную (против кручёных)
    panic_dist = 10,      -- дистанция паники (стады)
    double_fire = true,   -- второй фаер через 30мс (страховка)
    ping_comp = true,     -- компенсация пинга в окно реакции
    distance = 40,        -- макс. дистанция слежки (стады)
    base_react = 0.34,    -- окно реакции на медленных мячах (сек)
    react_scale_ui = 1,   -- отклик окна на скорость, ×1000 (1 = 0.001 с на ст/с)
    min_react = 0.12,     -- нижний предел окна (сек)
    min_interval = 0.08,  -- анти-спам между парированиями
    anti_afk = true,
    show_status = true,
    ui_toasts = true,     -- Style A: тосты шелла (Notifications в Config)
    remote_pick = "авто",
    scan_world = true,    -- доверять авто-поиску мяча вне папки Balls
}

local lastParry = 0
local parryCount = 0
local lastInfo = "—"
local ballSpeed, ballDist = 0, 0
local isTargetNow = false

-- ===== REMOTES: авто-поиск =====
-- v2.1 искал ровно один путь (Remotes.ParryButtonPress). Если игра его
-- переименовала — скрипт грузился, но парировать было нечем, и снаружи это
-- выглядело как «не работает». Теперь ремоут ищется по смыслу, а не по пути,
-- и выбор можно задать руками в Timing → «Ремоут».
local HINTS = { "parry", "block", "deflect", "guard", "counter", "click" }
local MAX_REMOTE_ROWS = 40

local function isRemoteObj(x)
    return x ~= nil and (x:IsA("RemoteEvent") or x:IsA("UnreliableRemoteEvent") or x:IsA("RemoteFunction"))
end

local function scoreRemote(name)
    local low = string.lower(name)
    for i, h in ipairs(HINTS) do
        if low == h then return 100 - i end
        if string.find(low, h, 1, true) then return 50 - i end
    end
    return 0
end

local RemoteList = {}      -- { {label=, obj=, score=} } по убыванию счёта
local RemotePick = "авто"
local ParryRemote = nil
local remoteStatus = "нет"

local function collectRemotes()
    RemoteList = {}
    local seen = {}
    local function add(obj)
        if not isRemoteObj(obj) then return end
        local ok, full = pcall(function() return obj:GetFullName() end)
        if not ok or not full or seen[full] then return end
        seen[full] = true
        RemoteList[#RemoteList + 1] = { label = full, obj = obj, score = scoreRemote(obj.Name) }
    end

    -- папка Remotes — в приоритете, но без завязки на конкретное имя
    local r = ReplicatedStorage:FindFirstChild("Remotes")
    if r then
        for _, d in ipairs(r:GetDescendants()) do add(d) end
    end

    local scanned = 0
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        scanned += 1
        if scanned > 4000 then break end
        add(d)
    end

    table.sort(RemoteList, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if #a.label ~= #b.label then return #a.label < #b.label end
        return a.label < b.label
    end)
    while #RemoteList > MAX_REMOTE_ROWS do table.remove(RemoteList) end
end

local function resolveRemote()
    ParryRemote = nil
    if RemotePick ~= "авто" then
        for _, c in ipairs(RemoteList) do
            if c.label == RemotePick and c.obj and c.obj.Parent then
                ParryRemote = c.obj
                remoteStatus = c.label
                return true
            end
        end
        remoteStatus = "выбранный не найден"
        return false
    end
    -- авто: лучший по имени, но не «на глаз», а по счёту
    for _, c in ipairs(RemoteList) do
        if c.score > 0 and c.obj and c.obj.Parent then
            ParryRemote = c.obj
            remoteStatus = c.label
            return true
        end
    end
    remoteStatus = "не найден"
    return false
end

-- ===== МЯЧ: авто-поиск контейнера =====
local BallsFolder = nil
local ballRoots = {}
local currentBall = nil

local function collectBallRoots()
    ballRoots = {}
    if BallsFolder and BallsFolder.Parent then ballRoots[#ballRoots + 1] = BallsFolder end
    local byName = Workspace:FindFirstChild("Balls")
    if byName and byName ~= BallsFolder then
        BallsFolder = byName
        ballRoots[#ballRoots + 1] = byName
    end
    for _, d in ipairs(Workspace:GetChildren()) do
        if d ~= Workspace.CurrentCamera and (d:IsA("Folder") or d:IsA("Model")) then
            if string.find(string.lower(d.Name), "ball", 1, true) then
                ballRoots[#ballRoots + 1] = d
            end
        end
    end
end

local function partNamedBall(b)
    return b:IsA("BasePart") and string.find(string.lower(b.Name), "ball", 1, true) ~= nil
end

local function getRealBall()
    if currentBall and currentBall.Parent then
        if currentBall:GetAttribute("realBall") ~= false then return currentBall end
        currentBall = nil
    end
    -- 1) атрибут realBall — самый надёжный признак
    for _, root in ipairs(ballRoots) do
        for _, b in ipairs(root:GetChildren()) do
            if b:IsA("BasePart") and b:GetAttribute("realBall") == true then
                currentBall = b
                return b
            end
        end
    end
    -- 2) имя похоже на мяч
    for _, root in ipairs(ballRoots) do
        for _, b in ipairs(root:GetChildren()) do
            if partNamedBall(b) then currentBall = b return b end
        end
    end
    -- 3) мяч лежит прямо в Workspace, без папки
    if State.scan_world then
        for _, b in ipairs(Workspace:GetChildren()) do
            if partNamedBall(b) then currentBall = b return b end
        end
    end
    -- 4) последний шанс: папка Balls, любой BasePart
    if BallsFolder and BallsFolder.Parent then
        for _, b in ipairs(BallsFolder:GetChildren()) do
            if b:IsA("BasePart") then currentBall = b return b end
        end
    end
    return nil
end

local function resolveRefs()
    if not BallsFolder or not BallsFolder.Parent then
        BallsFolder = Workspace:FindFirstChild("Balls")
    end
    if not ParryRemote or not ParryRemote.Parent then
        if #RemoteList == 0 then collectRemotes() end
        resolveRemote()
    end
    collectBallRoots()
end
resolveRefs()

-- Метку цели игра рисует Highlight'ом на персонаже. Если переименовали или
-- перенесли — ищем Highlight/SelectionBox в любом слоте и «target» в именах.
local TARGET_ATTRS = { "Targeted", "targeted", "Target", "target", "IsTarget", "isTarget", "isTargeted" }
local function isTarget()
    local ch = LocalPlayer.Character
    if not ch then return false end
    for _, d in ipairs(ch:GetChildren()) do
        if d:IsA("Highlight") or d:IsA("SelectionBox") then return true end
        if string.find(string.lower(d.Name), "target", 1, true) then return true end
    end
    for _, a in ipairs(TARGET_ATTRS) do
        if ch:GetAttribute(a) == true then return true end
    end
    return false
end

local function myPos()
    local ch = LocalPlayer.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position or nil
end

-- было StarterGui:SetCore("SendNotification", ...) — в Style A уведомления рисует шелл
local function notify(text)
    print("[JakoScripts BLADE BALL] " .. tostring(text))
end

local function parry(reason)
    local now = os.clock()
    if now - lastParry < State.min_interval then return false end
    if not ParryRemote then resolveRefs() end
    if not ParryRemote then return false end
    lastParry = now
    parryCount += 1
    lastInfo = reason or "auto"
    pcall(function() ParryRemote:FireServer() end)
    if State.double_fire and State.rage then
        task.delay(0.03, function() -- страховка: сервер мог съесть первый фаер
            pcall(function() ParryRemote:FireServer() end)
        end)
    end
    return true
end

-- пинг кэшируем в медленном цикле, не дёргаем Stats каждый кадр
local pingSec = 0
local function pingTick()
    if not State.ping_comp then pingSec = 0 return end
    pcall(function()
        local item = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]
        pingSec = math.clamp((item:GetValue() or 0) / 1000 * 0.5, 0, 0.15)
    end)
end

-- для предсказания кручёных: предыдущие скорость/время
local prevVel, prevTick = nil, 0

-- вспышка парирования была фреймом старого GUI; реализация — после создания шелла
local flashParry = function() end
local lastFlash = 0

-- ===== CORE: решение о парировании раз в Heartbeat (дешево и точно) =====
local function parryTick()
    isTargetNow = isTarget()
    ballSpeed, ballDist = 0, 0
    if not State.enabled then return end
    if State.target_only and not isTargetNow then return end
    local mp = myPos()
    if not mp then return end
    local ball = getRealBall()
    if not ball then return end

    local bp = ball.Position
    local vel = ball.AssemblyLinearVelocity
    if not vel or vel.Magnitude < 1 then return end
    local now = os.clock()
    local speed = vel.Magnitude

    -- предсказание кручёных: ускорение из прошлого кадра, смотрим позицию на +80мс
    local accel = Vector3.new(0, 0, 0)
    local dtPrev = now - prevTick
    if prevVel and dtPrev > 0 and dtPrev < 0.2 then
        accel = (vel - prevVel) / dtPrev
    end
    prevVel, prevTick = vel, now
    local lookAhead = 0.08
    local pp = bp + vel * lookAhead + accel * 0.5 * lookAhead * lookAhead

    local toMe = mp - pp
    local dist = toMe.Magnitude
    ballSpeed, ballDist = speed, (mp - bp).Magnitude
    if dist > State.distance then return end

    -- мяч должен лететь В НАС; в панике допуск шире (кручёные врут вектором)
    local approaching = vel:Dot(toMe.Unit)
    local needApproach = (State.panic and dist <= State.panic_dist) and (-speed * 0.2) or 0
    if approaching <= needApproach then return end

    -- паника вблизи: не считаем tti, просто жмём на кулдауне
    if State.panic and State.rage and dist <= State.panic_dist then
        if parry("panic") then flashParry() end
        return
    end

    local tti = dist / math.max(1, approaching)
    local react = math.clamp(State.base_react - speed * (State.react_scale_ui / 1000), State.min_react, State.base_react)
    if State.rage then react += 0.08 end      -- шире окно = раньше жмём
    react += pingSec                            -- пинг уже съел часть окна
    if State.legit then react += math.random() * 0.03 end

    if tti <= react then
        if parry(string.format("tti %.2f", tti)) then
            flashParry()
        end
    end
end

-- ===== UI: VANTA Style A (шелл подставляется по маркеру) =====
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
    title    = "BLADE BALL",
    subtitle = "blade ball",
    version  = "v2.2",
})
if not UI then
    warn("[JakoScripts BLADE BALL] UI не создан: экзекутор не дал родителя для ScreenGui")
    return
end

-- живой статус: режим, скорость/дистанция мяча, метка цели, счётчик пари
local setStat = UI:Stat("scan · parry 0")

-- Combat
local tabCombat = UI:Tab("Combat", "zap")
tabCombat:Section("parry")
tabCombat:Toggle("Авто-парирование", "enabled", true)
tabCombat:Toggle("Только когда я цель", "target_only", true)
tabCombat:Toggle("RAGE-режим (макс. реакция)", "rage", true)
tabCombat:Toggle("Legit-режим (задержка+джиттер)", "legit", false)
tabCombat:Toggle("Паник-пари вблизи", "panic", true)
tabCombat:Toggle("Двойной фаер", "double_fire", true)
tabCombat:Toggle("Компенсация пинга", "ping_comp", true)
tabCombat:Button("Тест парирования", "ghost", function()
    if parry("manual") then flashParry() notify("Parry отправлен") else notify("Кулдаун / нет remote") end
end)

-- Timing
local tabTiming = UI:Tab("Timing", "target")
tabTiming:Section("limits")
tabTiming:Slider("Дистанция слежки", "distance", 15, 60, nil, nil, function(v) return math.floor(v + 0.5) .. " st" end)
tabTiming:Slider("Дистанция паники", "panic_dist", 6, 15, nil, nil, function(v) return math.floor(v + 0.5) .. " st" end)
tabTiming:Slider("Окно реакции", "base_react", 0.15, 0.5)
tabTiming:Slider("Минимум окна", "min_react", 0.05, 0.3)
-- Слайдер шелла округляет до 2 знаков, а отклик живёт в тысячных (0.001 с на ст/с).
-- Поэтому ключ хранится ×1000, а логика делит его обратно.
tabTiming:Slider("Отклик на скорость ×1000", "react_scale_ui", 0.5, 4, nil, nil, function(v)
    return string.format("%.2f", v)
end)
tabTiming:Slider("Анти-спам интервал", "min_interval", 0.05, 0.5)

tabTiming:Section("источники")
collectRemotes()
local remoteOptions = { "авто" }
for _, c in ipairs(RemoteList) do remoteOptions[#remoteOptions + 1] = c.label end
tabTiming:Cycle("Ремоут парирования", "remote_pick", remoteOptions, function(v)
    RemotePick = v
    resolveRemote()
    UI:Toast("Ремоут: " .. tostring(remoteStatus), ParryRemote and "ok" or "warn")
end)
tabTiming:Toggle("Искать мяч вне папки Balls", "scan_world", true)
tabTiming:Button("Пересканировать игру", "ghost", function()
    collectRemotes()
    collectBallRoots()
    resolveRemote()
    UI:Toast("ремоут: " .. tostring(remoteStatus), ParryRemote and "ok" or "warn")
end)
tabTiming:Info("Ремоут ищется по смыслу (parry/block/deflect/guard), а не по жёсткому пути. Если авто промахнулось — выбери строку из списка. Метку цели игра рисует Highlight'ом; если её не видно — выключи «Только когда я цель» в Combat.")

-- Visuals
local tabVisuals = UI:Tab("Visuals", "eye")
tabVisuals:Section("overlay")
tabVisuals:Toggle("Живой статус", "show_status", true)
tabVisuals:Section("world")
tabVisuals:Toggle("Анти-АФК", "anti_afk", true)

-- Config
local tabConfig = UI:Tab("Config", "settings")
tabConfig:Section("interface")
tabConfig:Keybind("Toggle key", "ui_key")
tabConfig:Toggle("Notifications", "ui_toasts", true)
tabConfig:Section("session")
tabConfig:Button("Unload JakoScripts", "ghost", function()
    State.enabled = false      -- гасим парирование сразу
    State.anti_afk = false     -- afkTick сам снимет Idled-коннект
    UI:Destroy()
    print("[JakoScripts BLADE BALL] unloaded")
end)
tabConfig:Info("Двойной цикл, предсказание кручёных, паник-пари.")

-- вспышка парирования: свой оверлей у шелла, поэтому сигнал — тост с троттлингом
flashParry = function()
    local now = os.clock()
    if now - lastFlash < 0.6 then return end
    lastFlash = now
    UI:Toast(string.format("parry #%d", parryCount), "ok")
end

-- ===== ANTI-AFK (тихое, с ретраем VirtualUser) =====
local afkConn = nil
local function afkTick()
    if State.anti_afk and not afkConn then
        afkConn = LocalPlayer.Idled:Connect(function()
            local ok, VU = pcall(function() return game:GetService("VirtualUser") end)
            if ok and VU then
                pcall(function()
                    VU:CaptureController()
                    VU:ClickButton2(Vector2.new())
                end)
            end
        end)
    elseif not State.anti_afk and afkConn then
        pcall(function() afkConn:Disconnect() end)
        afkConn = nil
    end
end

-- ===== STATUS =====
-- Строка статуса — это же и диагностика: видно, нашёлся ли ремоут и мяч.
local function statusTick()
    if not State.show_status then setStat("status off") return end
    local mode = State.rage and "RAGE" or (State.legit and "LEGIT" or "CUSTOM")
    local ball = getRealBall()
    local bad = Color3.fromRGB(255, 120, 120)
    local calm = Color3.fromRGB(150, 150, 165)
    if not State.enabled then
        setStat(mode .. " · off · parry " .. parryCount)
    elseif not ParryRemote then
        setStat(mode .. " · ремоут НЕ найден → Timing → Пересканировать", bad)
    elseif not ball then
        setStat(mode .. " · ремоут ok · мяч не найден · parry " .. parryCount, bad)
    else
        setStat(string.format("%s · %d st/s · %d st · %s · %d", mode,
            math.floor(ballSpeed + 0.5), math.floor(ballDist + 0.5),
            isTargetNow and "ТЫ ЦЕЛЬ" or "ждём", parryCount),
            isTargetNow and Color3.fromRGB(255, 150, 120) or calm)
    end
end

-- ===== LOOPS =====
if BallsFolder then
    BallsFolder.ChildAdded:Connect(function() currentBall = nil end)
end
-- решение 2 раза за кадр (Render + Heartbeat): против зажимов важна каждая миллисекунда
RunService.RenderStepped:Connect(function()
    parryTick()
end)
RunService.Heartbeat:Connect(function()
    parryTick()
end)
local tSlow = 0
RunService.Heartbeat:Connect(function(dt)
    tSlow += dt
    if tSlow >= 0.25 then
        tSlow = 0
        resolveRefs()
        pingTick()
        afkTick()
        statusTick()
    end
end)

UI:Toast("JakoScripts BLADE BALL loaded", "ok")
print("[JakoScripts BLADE BALL · Style A] loaded")
