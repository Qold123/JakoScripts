-- JakoScripts STEAL AN EGG v2.1 | Luau | Roblox Steal an Egg | VANTA Style A
-- ТИХИЙ РЕЖИМ: кража только рядом + человекоподобные задержки, без телепортов
-- и спида по умолчанию (риск-функции отдельно с предупреждениями).
-- ESP/фуллбрайт/анти-АФК сервер не видит.
-- UI: Style A — окно 480x360, сайдбар 150, вкладки Farm / Visuals / Stealth / Config, RightShift скрыть.
-- Запуск: loadstring(game:HttpGet("RAW_URL"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- ===== STATE =====
local State = {
    legit = true, -- тихий режим: блочит ТП и спид
    auto_steal = false,
    steal_range = 12,
    steal_infested_first = true,
    steal_cooldown = 2.5,
    auto_hatch = false,
    egg_esp = true,
    infested_esp = true,
    esp_names = true,
    esp_maxdist = 800,
    player_esp = false,
    speed = false,
    speed_value = 32,
    fullbright = false,
    antiafk = true,
}

local eggCache = {}  -- [BasePart] = isInfested(bool), обновляется медленно
local eggESP = {}    -- [BasePart] = {hl, gui, lbl}
local playerESP = {} -- [player] = {hl, gui, ...}
local hatchBtn = nil
local lastSteal, lastHatch = 0, 0
local dbgEggs, dbgInfested, dbgNearest = 0, 0, 0

-- ===== UTILS =====
-- StarterGui:SetCore("SendNotification") убран: сообщения идут в warn.
local function notify(text)
    warn("[JakoScripts STEAL AN EGG] " .. tostring(text))
end

local function myHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart") or nil
end

local function isAlive(plr)
    local c = plr and plr.Character
    if not c then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    return h ~= nil and h.Health > 0
end

local function eggPartOf(obj)
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        local ok, pp = pcall(function() return obj.PrimaryPart end)
        if ok and pp and pp:IsA("BasePart") then return pp end
        return obj:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function looksLikeEgg(obj)
    local n = string.lower(obj.Name)
    if obj:IsA("Humanoid") or n == "humanoidrootpart" then return false end
    if obj:IsA("BasePart") or obj:IsA("Model") then
        return (string.find(n, "egg", 1, true) ~= nil) or (string.find(n, "nest", 1, true) ~= nil)
    end
    return false
end

local function checkInfested(part)
    if not part or not part.Parent then return false end
    local host = part.Parent:IsA("Model") and part.Parent or part
    local n = string.lower(part.Name)
    if string.find(n, "infest", 1, true) or string.find(n, "parasite", 1, true) then return true end
    for _, c in ipairs(host:GetChildren()) do
        local cn = string.lower(c.Name)
        if string.find(cn, "parasite", 1, true) or string.find(cn, "infest", 1, true) then return true end
        if c:IsA("Highlight") then
            local f = c.FillColor
            if f.R > 0.5 and f.B > 0.5 and f.G < 0.5 then return true end -- фиолетовая подсветка игры
        end
    end
    return false
end

-- ===== EGG CORE (кэш: тяжёлый скан редко, всё остальное по кэшу) =====
local function scanEggs()
    local seen = {}
    local count = 0
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if count > 150 then break end
        if looksLikeEgg(obj) then
            local part = eggPartOf(obj)
            if part and part.Parent then
                seen[part] = true
                count += 1
                if eggCache[part] == nil then
                    eggCache[part] = checkInfested(part)
                end
            end
        end
    end
    for part, _ in pairs(eggCache) do
        if not seen[part] or not part.Parent then
            eggCache[part] = nil
            local e = eggESP[part]
            if e then
                if e.hl then pcall(function() e.hl:Destroy() end) end
                if e.gui then pcall(function() e.gui:Destroy() end) end
                eggESP[part] = nil
            end
        end
    end
end

local function bestEgg(maxDist, infestedBonus)
    local hrp = myHRP()
    if not hrp then return nil, nil end
    local best, bestScore, bestD = nil, math.huge, 0
    for part, inf in pairs(eggCache) do
        if part.Parent then
            local d = (hrp.Position - part.Position).Magnitude
            if d <= maxDist then
                local score = d - (inf and infestedBonus or 0)
                if score < bestScore then best, bestScore, bestD = part, score, d end
            end
        end
    end
    return best, bestD
end

-- ===== ESP =====
local function updateEggESP()
    local hrp = myHRP()
    local myPos = hrp and hrp.Position or nil
    local nE, nI, nD = 0, 0, math.huge
    for part, inf in pairs(eggCache) do
        if not part.Parent then
            eggCache[part] = nil
        else
            local dist = myPos and math.floor((myPos - part.Position).Magnitude) or 0
            if myPos and dist < nD then nD = dist end
            nE += 1
            if inf then nI += 1 end
            local show = (inf and State.infested_esp) or ((not inf) and State.egg_esp)
            if show and dist <= State.esp_maxdist then
                local e = eggESP[part]
                if not e then
                    e = {}
                    local hl = Instance.new("Highlight")
                    hl.Name = "VantaEgg" hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    hl.FillTransparency = 0.4 hl.OutlineTransparency = 0.1
                    hl.Adornee = part.Parent:IsA("Model") and part.Parent or part
                    hl.Parent = part
                    local g = Instance.new("BillboardGui")
                    g.Name = "VantaEggTag" g.Size = UDim2.new(0, 170, 0, 22)
                    g.StudsOffset = Vector3.new(0, 2.5, 0) g.AlwaysOnTop = true
                    g.Adornee = part g.Parent = part
                    local l = Instance.new("TextLabel") l.Size = UDim2.new(1, 0, 1, 0)
                    l.BackgroundTransparency = 1 l.Font = Enum.Font.GothamBold l.TextSize = 13
                    l.TextStrokeTransparency = 0.4 l.Parent = g
                    e.hl, e.gui, e.lbl = hl, g, l
                    eggESP[part] = e
                end
                local col = inf and Color3.fromRGB(190, 90, 255) or Color3.fromRGB(255, 200, 80)
                e.hl.FillColor = col
                if e.lbl then
                    e.lbl.TextColor3 = col
                    e.lbl.Text = (inf and "ЗАРАЖ." or "Яйцо") .. " • " .. dist .. "m"
                end
            else
                local e = eggESP[part]
                if e then
                    if e.hl then pcall(function() e.hl:Destroy() end) end
                    if e.gui then pcall(function() e.gui:Destroy() end) end
                    eggESP[part] = nil
                end
            end
        end
    end
    dbgEggs, dbgInfested, dbgNearest = nE, nI, (nD == math.huge and 0 or nD)
end

local function clearPlayerESP(p)
    local e = playerESP[p]
    if e then
        if e.hl then pcall(function() e.hl:Destroy() end) end
        if e.gui then pcall(function() e.gui:Destroy() end) end
        playerESP[p] = nil
    end
end

local function updatePlayerESP()
    local hrp = myHRP()
    local myPos = hrp and hrp.Position or nil
    if not State.player_esp then
        for p, _ in pairs(playerESP) do clearPlayerESP(p) end
        return
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer or not isAlive(p) then
            clearPlayerESP(p)
        else
            local ch = p.Character
            local head = ch and (ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart"))
            if not head then
                clearPlayerESP(p)
            else
                local e = playerESP[p]
                if not e then
                    e = {}
                    local hl = Instance.new("Highlight")
                    hl.Name = "VantaPlr" hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    hl.FillColor = Color3.fromRGB(255, 90, 90)
                    hl.FillTransparency = 0.55 hl.OutlineTransparency = 0.1
                    hl.Adornee = ch hl.Parent = ch
                    local g = Instance.new("BillboardGui")
                    g.Name = "VantaPlrTag" g.Size = UDim2.new(0, 180, 0, 22)
                    g.StudsOffset = Vector3.new(0, 3, 0) g.AlwaysOnTop = true
                    g.Adornee = ch:FindFirstChild("Head") or head g.Parent = ch
                    local l = Instance.new("TextLabel") l.Size = UDim2.new(1, 0, 1, 0)
                    l.BackgroundTransparency = 1 l.Font = Enum.Font.GothamBold l.TextSize = 13
                    l.TextColor3 = Color3.fromRGB(255, 120, 120) l.TextStrokeTransparency = 0.4 l.Parent = g
                    e.hl, e.gui, e.lbl = hl, g, l
                    playerESP[p] = e
                end
                if e.lbl and myPos then
                    local d = math.floor((myPos - head.Position).Magnitude)
                    e.lbl.Text = p.DisplayName .. " • " .. d .. "m"
                end
            end
        end
    end
    for p, _ in pairs(playerESP) do if not p.Parent then clearPlayerESP(p) end end
end
Players.PlayerRemoving:Connect(clearPlayerESP)

-- ===== AUTO STEAL (промпт > тач) =====
local function findPrompt(egg)
    local host = egg.Parent:IsA("Model") and egg.Parent or egg
    local pr = host:FindFirstChildOfClass("ProximityPrompt", true) or egg:FindFirstChildOfClass("ProximityPrompt")
    return pr
end

local function doAutoSteal()
    if not State.auto_steal then return end
    local now = os.clock()
    -- гуманизация: кулдаун ±40%, иначе робот виден по логам
    local cd = State.steal_cooldown * (0.8 + math.random() * 0.4)
    if now - lastSteal < cd then return end
    local egg = bestEgg(State.steal_range, State.steal_infested_first and 12 or 0)
    if not egg then return end
    local pr = findPrompt(egg)
    if not pr then return end -- без промпта не трогаем: тач-спам палится сильнее всего
    lastSteal = now
    task.spawn(function()
        task.wait(0.15 + math.random() * 0.5) -- «подошёл и нажал»
        if egg.Parent and pr.Parent then
            if fireproximityprompt then
                pcall(function() fireproximityprompt(pr) end)
            else
                pcall(function()
                    pr:InputHoldBegin()
                    task.wait(0.1 + math.random() * 0.2)
                    pr:InputHoldEnd()
                end)
            end
        end
    end)
end

-- ===== AUTO HATCH (кнопка кэшируется, скан редко) =====
local function rescanHatch()
    hatchBtn = nil
    local ok, pg = pcall(function() return LocalPlayer:FindFirstChild("PlayerGui") end)
    if not ok or not pg then return end
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextButton") then
            local t = string.lower(d.Text)
            if string.find(t, "hatch", 1, true) or string.find(t, "open", 1, true) or string.find(t, "вылуп", 1, true) then
                hatchBtn = d
                return
            end
        end
    end
end

local function doAutoHatch()
    if not State.auto_hatch then return end
    local now = os.clock()
    if now - lastHatch < 2 then return end
    lastHatch = now
    if hatchBtn and hatchBtn.Parent then
        pcall(function() hatchBtn:Activate() end)
    else
        rescanHatch()
    end
end

-- ===== TELEPORTS =====
local function tpTo(pos)
    local hrp = myHRP()
    if hrp and pos then
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        hrp.CFrame = CFrame.new(pos)
    end
end

local lastTp = 0
local function tpGuard()
    if State.legit then notify("Тихий режим: ТП выключено") return false end
    local now = os.clock()
    if now - lastTp < 5 then notify("ТП: подожди 5 сек") return false end
    lastTp = now
    return true
end

local function tpBestEgg()
    if not tpGuard() then return end
    local egg = bestEgg(5000, State.steal_infested_first and 60 or 0)
    if egg then
        tpTo(egg.Position + Vector3.new(0, 4, 0))
        notify("ТП к яйцу")
    else
        notify("Яиц не найдено")
    end
end

local function tpBase()
    if not tpGuard() then return end
    for _, o in ipairs(Workspace:GetDescendants()) do
        if o:IsA("BasePart") then
            local n = string.lower(o.Name)
            if string.find(n, "base", 1, true) or string.find(n, "safe", 1, true)
                or string.find(n, "plot", 1, true) or string.find(n, "tycoon", 1, true) then
                tpTo(o.Position + Vector3.new(0, 5, 0))
                notify("ТП на базу")
                return
            end
        end
    end
    notify("База не найдена")
end

UserInputService.InputBegan:Connect(function(i, gp)
    if gp then return end
    if i.KeyCode == Enum.KeyCode.T then tpBestEgg()
    elseif i.KeyCode == Enum.KeyCode.B then tpBase() end
end)

-- ===== MOVEMENT =====
local function movementTick()
    local ch = LocalPlayer.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if State.legit then -- тихий режим: скорость всегда обычная
        if hum.WalkSpeed ~= 16 then hum.WalkSpeed = 16 end
        return
    end
    if State.speed then
        if hum.WalkSpeed ~= State.speed_value then hum.WalkSpeed = State.speed_value end
    elseif hum.WalkSpeed ~= 16 then
        hum.WalkSpeed = 16
    end
end

-- ===== FULLBRIGHT =====
local savedLight, lastFB = nil, false
local function applyFB(on)
    if on then
        if not savedLight then
            savedLight = { B = Lighting.Brightness, A = Lighting.Ambient, O = Lighting.OutdoorAmbient, F = Lighting.FogEnd }
        end
        Lighting.Brightness = 2
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        Lighting.FogEnd = 100000
    elseif savedLight then
        Lighting.Brightness = savedLight.B
        Lighting.Ambient = savedLight.A
        Lighting.OutdoorAmbient = savedLight.O
        Lighting.FogEnd = savedLight.F
        savedLight = nil
    end
end

-- ===== ANTI-AFK =====
local afkConn = nil
pcall(function()
    local VU = game:GetService("VirtualUser")
    LocalPlayer.Idled:Connect(function()
        if State.antiafk then
            VU:Button2Down(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
            task.wait(1)
            VU:Button2Up(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
        end
    end)
end)

-- ===== UI (VANTA Style A) =====
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

        local parent
        do
            if gethui then local ok, r = pcall(gethui) if ok and r then parent = r end end
            if not parent and get_hidden_gui then local ok, r = pcall(get_hidden_gui) if ok and r then parent = r end end
            if not parent and get_hui then local ok, r = pcall(get_hui) if ok and r then parent = r end end
            if not parent then parent = SVC("CoreGui") end
        end
        pcall(function()
            local old = parent and parent:FindFirstChild(CONFIG.brand)
            if old then old:Destroy() end
        end)

        local gui = Instance.new("ScreenGui")
        gui.Name = CONFIG.brand
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.DisplayOrder = 999
        gui.Parent = parent

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

        local ui = { gui = gui, window = win, state = state, pages = {}, nav = {}, rows = {}, listening = nil }

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
    title    = "STEAL AN EGG",
    subtitle = "steal an egg",
    version  = "v2.1",
})

local setStat = UI:Stat("ТИХО 0 / 0 / 0m")

-- Farm
local tabFarm = UI:Tab("Farm", "target")
tabFarm:Section("steal")
tabFarm:Toggle("Авто-кража", "auto_steal", false)
tabFarm:Toggle("Сначала заражённые", "steal_infested_first", true)
tabFarm:Slider("Радиус кражи", "steal_range", 6, 16, "")
tabFarm:Slider("Кулдаун кражи (сек)", "steal_cooldown", 1, 5, "s")
tabFarm:Section("hatch")
tabFarm:Toggle("Авто-хэтч", "auto_hatch", false)
tabFarm:Button("Найти кнопку хэтча заново", "ghost", function()
    rescanHatch()
    notify(hatchBtn and "Кнопка хэтча найдена" or "Кнопка хэтча не найдена")
end)
tabFarm:Section("risk")
tabFarm:Info("T — к яйцу, B — на базу. В тихом режиме ТП выключено.")
tabFarm:Button("[РИСК] ТП к лучшему яйцу (T)", "ghost", tpBestEgg)
tabFarm:Button("[РИСК] ТП на базу (B)", "ghost", tpBase)

-- Visuals
local tabVisuals = UI:Tab("Visuals", "eye")
tabVisuals:Section("eggs")
tabVisuals:Toggle("ESP яиц", "egg_esp", true)
tabVisuals:Toggle("ESP заражённых", "infested_esp", true)
tabVisuals:Toggle("Подписи + дистанция", "esp_names", true)
tabVisuals:Slider("Макс. дистанция ESP", "esp_maxdist", 200, 2000, "m")
tabVisuals:Section("players")
tabVisuals:Toggle("ESP игроков", "player_esp", false)
tabVisuals:Section("world")
tabVisuals:Toggle("Фуллбрайт", "fullbright", false)
tabVisuals:Toggle("Анти-АФК", "antiafk", true)

-- Stealth
local tabStealth = UI:Tab("Stealth", "zap")
tabStealth:Section("quiet mode")
tabStealth:Toggle("ТИХИЙ режим (без ТП и спида)", "legit", true)
tabStealth:Section("movement (risk)")
State.speed_value = 22 -- слайдер шелла берёт старт из State: старый def слайдера (в STATE лежал 32)
tabStealth:Toggle("[РИСК] Спидхак (выкл в тихом)", "speed", false)
tabStealth:Slider("Скорость", "speed_value", 16, 40, "")

-- Config
local tabConfig = UI:Tab("Config", "settings")
tabConfig:Section("interface")
tabConfig:Keybind("Toggle key", "ui_key")
tabConfig:Toggle("Notifications", "ui_toasts", true)
tabConfig:Section("session")
tabConfig:Button("Unload JakoScripts", "ghost", function()
    State.auto_steal, State.auto_hatch = false, false
    State.speed, State.fullbright = false, false
    applyFB(false)
    for part, e in pairs(eggESP) do
        if e.hl then pcall(function() e.hl:Destroy() end) end
        if e.gui then pcall(function() e.gui:Destroy() end) end
        eggESP[part] = nil
    end
    for p, _ in pairs(playerESP) do clearPlayerESP(p) end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed = 16 end
    UI:Destroy()
    notify("Скрипт выгружен")
end)
tabConfig:Info("Тихий режим: кража только рядом, человекоподобные задержки, без ТП и спида.")

-- ===== STATUS =====
local function updateStatus()
    local quiet = State.legit
    setStat((quiet and "ТИХО " or "РИСК ") .. dbgEggs .. " / " .. dbgInfested .. " / " .. dbgNearest .. "m",
        quiet and Color3.fromRGB(52, 211, 153) or Color3.fromRGB(255, 77, 94))
end

-- ===== LOOPS (тяжёлое — редко) =====
scanEggs()
rescanHatch()
RunService.RenderStepped:Connect(function()
    doAutoSteal()
    movementTick()
    if State.fullbright ~= lastFB then applyFB(State.fullbright) lastFB = State.fullbright end
    if State.fullbright then
        Lighting.Brightness = 2
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
    end
end)
local tEsp, tScan, tHatch, tStat = 0, 0, 0, 0
RunService.Heartbeat:Connect(function(dt)
    tEsp += dt tScan += dt tHatch += dt tStat += dt
    if tScan >= 1.0 then tScan = 0 scanEggs() end
    if tEsp >= 0.4 then tEsp = 0 updateEggESP() updatePlayerESP() end
    if tHatch >= 2.0 then tHatch = 0 doAutoHatch() end
    if tStat >= 1.0 then tStat = 0 updateStatus() end
end)

UI:Toast("JakoScripts STEAL AN EGG loaded", "ok")
print("[JakoScripts STEAL AN EGG · Style A] loaded")
