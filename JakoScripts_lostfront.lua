-- JakoScripts LOST FRONT v3.0 | Luau | Roblox Lost Front | VANTA Style A
-- TEAM CORE по Bac0nHck: 1) GC-реестр players[].team (filtergc), 2) контейнеры
-- персонажей (одна папка = одна команда), 3) ростер resources.teams,
-- 4) подсветка игры, 5) ручная сторона. Дроны по атрибутам player/throttle,
-- аим в hitbox/AimPoint. Своих не целим вообще.
-- v3.0: silent aim (хук __namecall), скелет Drawing по Motor6D, HP-бар, линия до цели,
-- приоритет цели и кривая наведения, триггербот со своей клавишей и радиусом,
-- скорость/прыжок/noclip/anti-afk, конфиг на диск, FPS/ping в вотермарке.
-- UI: Style A — окно 480x360, сайдбар 150, вкладки Combat / Visuals / Movement / Config,
-- RightShift — скрыть окно. Уведомления — тосты шелла, StarterGui:SetCore(...) не вызывается.
-- Запуск: loadstring(game:HttpGet("RAW_URL"))()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- executor-compat: mouse1click есть не во всех executor'ах — берём локалом, вызов идёт не в глобал
local mouse1click = mouse1click or function() end

-- ===== STATE =====
local State = {
    aimbot = true,
    aim_hold = true,
    aim_key = Enum.KeyCode.E,
    aim_part = "Head",
    aim_fov = 120,
    aim_smooth = 35,
    aim_wallcheck = true,
    aim_predict = true,
    aim_sticky = true,
    aim_drones = true,
    aim_priority = "Crosshair", -- Crosshair | Distance | LowHP
    aim_ease = "Linear",        -- Linear | EaseOut | Snap
    team_check = true,
    my_side = "AUTO", -- AUTO | attackers | defenders

    -- silent aim: клиентский рейкаст уводится в хитбокс, камера не двигается
    silent_aim = false,
    silent_hitpart = "Head",    -- Head | Torso | Random
    silent_fov = 160,
    silent_walls = false,       -- false = цель обязана быть в прямой видимости

    triggerbot = false,
    trigger_ms = 120,
    trigger_fov = 12,
    trigger_key = Enum.KeyCode.F,

    esp = true,
    show_enemies = true,
    show_allies = false,
    esp_names = true,
    esp_distance = true,
    esp_health = true,
    esp_chams = true,
    esp_maxdist = 600,
    drone_esp = true,
    show_own_drone = false, -- свой дрон не показываем/не целим
    drone_maxdist = 800,
    tracers = false,
    fov_show = true,
    esp_boxes = false,
    esp_hpbar = false,
    esp_skeleton = false,
    esp_skeleton_thick = 1,
    esp_target_line = false,
    fov_fill = false,
    cam_fov = 70,

    hitbox = false,
    hitbox_size = 4,
    drone_hitbox = false,
    drone_hitbox_size = 6,

    wallclimb = false,
    wallclimb_speed = 28,
    speed_on = false,
    speed_val = 32,
    jump_on = false,
    jump_val = 60,
    inf_jump = false,
    noclip = false,
    anti_afk = false,

    ui_watermark = true,
    ui_blur = true,
    ui_stats = true,
    ui_toasts = true,
    ui_key = Enum.KeyCode.RightShift,
}

-- снимок дефолтов: кнопка Config → Сброс возвращает ровно это состояние
local StateDefaults = {}
for k, v in pairs(State) do StateDefaults[k] = v end

local aiming = false
local rmbDown = false
local spaceHeld = false
local triggerHeld = false
local stickyTarget = nil
local teamSrc = "?" -- какой источник сейчас работает: roster | hilite | manual | ?
-- Общая коробка silent aim. Живёт в getgenv, а не в локальной переменной: хук
-- ставится один раз на процесс, и его замыкание обязано видеть состояние
-- повторных запусков. guard = идёт наш собственный рейкаст (воллчек, карабканье) —
-- такой запрос хук не трогает.
local silentBox = { on = false, part = nil, guard = false, hitpart = "Head" }
do
    local env = (getgenv and getgenv()) or _G
    if type(env) == "table" then
        if type(env.__JakoSilent) == "table" then
            silentBox = env.__JakoSilent -- коробка прошлого запуска: хук уже стоит
            silentBox.on = false
            silentBox.part = nil
            silentBox.guard = false
        else
            env.__JakoSilent = silentBox
        end
    end
end

-- ===== ЧАСТИ ТЕЛА (риг вложенный — ищем рекурсивно) =====
local function findHead(char) return char and char:FindFirstChild("Head", true) or nil end
local function findHRP(char) return char and char:FindFirstChild("HumanoidRootPart", true) or nil end
local function findHum(char) return char and char:FindFirstChildOfClass("Humanoid", true) or nil end

-- ===== TEAM RESOLVE v4 (портировано с Bac0nHck, адаптировано) =====
-- Источник 0: GC-реестр клиента players[Player].team (самый точный, если executor умеет filtergc)
local TeamReg, regCheckedAt = nil, 0
local function getReg()
    if TeamReg and type(TeamReg.players) == "table" then return TeamReg end
    if type(filtergc) ~= "function" then return nil end
    if os.clock() - regCheckedAt < 5 then return TeamReg end
    regCheckedAt = os.clock()
    local ok, reg = pcall(filtergc, "table", {
        Keys = { "isFriendly", "getclient", "getEnemyTeam", "getPlayer", "players" }
    }, true)
    if ok and type(reg) == "table" and type(reg.players) == "table" then
        TeamReg = reg
        return reg
    end
    return nil
end

local function regTeam(plr)
    local r = getReg()
    if not r then return nil end
    local ok, d = pcall(function() return r.players[plr] end)
    if ok and type(d) == "table" and d.team ~= nil then
        return tostring(d.team)
    end
    return nil
end

-- Источник 1: контейнеры персонажей (одна папка в Workspace = одна команда).
-- Персонажи НЕ лежат в корне Workspace, а сгруппированы по командам.
local function charContainer(plr)
    local ch = plr.Character
    if not ch or not ch.Parent or ch.Parent == Workspace then return nil end
    return ch.Parent
end

-- Источник 2: серверный ростер ReplicatedStorage.resources.teams
local teamFolder = nil
pcall(function()
    local res = RS:FindFirstChild("resources")
    teamFolder = res and res:FindFirstChild("teams") or RS:FindFirstChild("teams")
end)

local sideCache = {} -- [playerName] = sideName
local function rescanRoster()
    sideCache = {}
    if not teamFolder then teamSrc = "hilite" return end
    local found = false
    for _, side in ipairs(teamFolder:GetChildren()) do
        local sname = string.lower(side.Name)
        -- любые упоминания ника внутри ветки стороны = игрок этой стороны
        for _, d in ipairs(side:GetDescendants()) do
            local hitName = nil
            if d:IsA("StringValue") and d.Value ~= "" then hitName = d.Value end
            if d:IsA("ObjectValue") and d.Value and d.Value:IsA("Player") then hitName = d.Value.Name end
            if d.Name ~= side.Name and d.Name ~= "" then
                if Players:FindFirstChild(d.Name) then hitName = d.Name end
            end
            if hitName then sideCache[hitName] = side.Name found = true end
        end
        -- атрибуты ветки
        for k, v in pairs(side:GetAttributes()) do
            if Players:FindFirstChild(tostring(v)) then sideCache[tostring(v)] = side.Name found = true end
            if Players:FindFirstChild(k) then sideCache[k] = side.Name found = true end
        end
    end
    -- прямые дети-значения с никами тоже учитываем
    for _, c in ipairs(teamFolder:GetChildren()) do
        if Players:FindFirstChild(c.Name) and c:IsA("ValueBase") == false then
            -- Model/Player напрямую? пропускаем (это ветки сторон)
        end
    end
    if found then teamSrc = "roster" end
end

local function sideOf(plr)
    return sideCache[plr.Name] or sideCache[plr.DisplayName]
end

-- Источник 2: цвет подсветки САМОЙ ИГРЫ (то, что видишь ты: красная=враг, зелёная=свой)
local function hlMark(char)
    if not char then return nil end
    local ally, enemy = false, false
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("Highlight") then
            local f = d.FillColor
            local o = d.OutlineColor
            local function green(c) return c.G > 0.65 and c.R < 0.65 end
            local function red(c) return c.R > 0.65 and c.G < 0.55 end
            if green(f) or green(o) then ally = true end
            if red(f) or red(o) then enemy = true end
        end
    end
    if ally and not enemy then return "ally" end
    if enemy and not ally then return "enemy" end
    if ally and enemy then return "ally" end -- своя обводка поверх чужой = свой
    return nil
end

local mySideCache = nil
local function mySide()
    if State.my_side ~= "AUTO" then
        teamSrc = "manual"
        return State.my_side
    end
    local rt = regTeam(LocalPlayer)
    if rt then teamSrc = "reg" mySideCache = rt return rt end
    local s = sideOf(LocalPlayer)
    if s then
        teamSrc = "roster"
        mySideCache = s
        return s
    end
    return mySideCache
end

local function sameTeam(plr)
    if plr == LocalPlayer then return true end
    if not State.team_check then return false end
    -- 0) GC-реестр (точнее некуда)
    local myT = regTeam(LocalPlayer)
    if myT then
        local pT = regTeam(plr)
        if pT then
            teamSrc = "reg"
            return pT == myT
        end
    end
    -- 1) контейнеры персонажей (одна папка = одна команда)
    local mc = charContainer(LocalPlayer)
    local pc = charContainer(plr)
    if mc and pc then
        teamSrc = "cont"
        return mc == pc
    end
    -- 2) ручной режим + ростер
    if State.my_side ~= "AUTO" then
        teamSrc = "manual"
        local ps = sideOf(plr)
        if ps then return string.lower(ps) == string.lower(State.my_side) end
        local m = hlMark(plr.Character)
        if m then return m == "ally" end
        return false
    end
    -- 3) авто: ростер
    local ms = sideOf(LocalPlayer)
    if ms then
        teamSrc = "roster"
        local ps = sideOf(plr)
        if ps then return ps == ms end
        return false
    end
    -- 4) подсветка игры
    teamSrc = "hilite"
    local m = hlMark(plr.Character)
    if m then return m == "ally" end
    return false -- неизвестно = враг (своих не прячем)
end

local function isEnemy(plr)
    if plr == LocalPlayer then return false end
    if not State.team_check then return true end
    return not sameTeam(plr)
end

-- СВОИХ НЕ ЦЕЛИМ ВООБЩЕ
local function canAim(plr)
    local c = plr.Character
    if not c then return false end
    local h = findHum(c)
    if not h or h.Health <= 0 then return false end
    return isEnemy(plr)
end

local function canShow(plr)
    if isEnemy(plr) then return State.show_enemies end
    return State.show_allies
end

-- ===== UTILS =====

local function isAlive(plr)
    local c = plr and plr.Character
    if not c then return false end
    local h = findHum(c)
    return h ~= nil and h.Health > 0
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Blacklist
rayParams.IgnoreWater = true

local function isVisible(container, part)
    if not State.aim_wallcheck then return true end
    local char = LocalPlayer.Character
    if not char then return false end
    -- Exclude-фильтр как у Bac0nHck: камера + свой персонаж + папка ignore игры.
    -- Попадание в саму цель засчитываем как видимость.
    local exclusions = { Camera, char }
    local ign = Workspace:FindFirstChild("ignore")
    if ign then exclusions[#exclusions + 1] = ign end
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = exclusions
    local origin = Camera.CFrame.Position
    silentBox.guard = true
    local res = Workspace:Raycast(origin, part.Position - origin, rayParams)
    silentBox.guard = false
    if res == nil then return true end
    if container and res.Instance:IsDescendantOf(container) then return true end
    return false
end

local function getAnchor(char)
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("Head")
        or char:FindFirstChildWhichIsA("BasePart", true)
end

local function getAimPart(char)
    if not char then return nil end
    if State.aim_part == "Head" then
        return findHead(char) or char:FindFirstChild("UpperTorso", true) or char:FindFirstChild("Torso", true) or findHRP(char) or getAnchor(char)
    else
        return findHRP(char) or char:FindFirstChild("UpperTorso", true) or char:FindFirstChild("Torso", true) or findHead(char) or getAnchor(char)
    end
end

local function predictPos(part)
    if not State.aim_predict then return part.Position end
    local m = part.Parent
    local hrp = m and m:FindFirstChild("HumanoidRootPart", true)
    local vel = hrp and hrp.AssemblyLinearVelocity or part.AssemblyLinearVelocity
    if not vel or vel.Magnitude < 1 then return part.Position end
    local dist = (Camera.CFrame.Position - part.Position).Magnitude
    local t = math.clamp(dist / 1000, 0, 0.2)
    return part.Position + vel * t
end

-- ===== ДРОНЫ =====
local droneParts = {}
local droneESP = {}
local DRONE_PATTERNS = { "drone", "fpv", "uav", "quad", "copter", "recon" }

local function modelNameHits(s)
    s = string.lower(s)
    for i = 1, #DRONE_PATTERNS do
        if string.find(s, DRONE_PATTERNS[i], 1, true) then return true end
    end
    return false
end

local function isDroneModel(m)
    if not m or not m:IsA("Model") then return false end
    if Players:GetPlayerFromCharacter(m) then return false end -- персонаж, не дрон
    -- точный признак из Bac0nHck: атрибуты player (ник владельца) + throttle
    local owner = m:GetAttribute("player")
    local thr = m:GetAttribute("throttle")
    if type(owner) == "string" and owner ~= "" and thr ~= nil then return true end
    -- запасной: имя + характерные дети
    if modelNameHits(m.Name) then
        if m:FindFirstChild("propellers") or m:FindFirstChild("hitbox") or m:FindFirstChild("AimPoint") then
            return true
        end
    end
    return false
end

-- точка аима дрона: хитбокс -> AimPoint -> корень (как у Bac0nHck)
-- droneRoot объявлен ниже: без форвард-декларации вызов уходил в глобал (nil) и
-- ронял поиск цели на любом дроне без hitbox/AimPoint.
local droneRoot
local function droneAimPart(m)
    local hb = m:FindFirstChild("hitbox")
    if hb and hb:IsA("BasePart") then return hb end
    local ap = m:FindFirstChild("AimPoint")
    if ap and ap:IsA("BasePart") then return ap end
    return droneRoot(m)
end

local function droneOwner(m)
    local o = m:GetAttribute("player")
    if type(o) == "string" and o ~= "" then return Players:FindFirstChild(o) end
    return nil
end

local function isOwnDrone(m)
    local o = m:GetAttribute("player")
    return type(o) == "string" and o ~= "" and o == LocalPlayer.Name
end

-- вражеский ли дрон: свой пропускаем, союзника пропускаем, бесхозный считаем врагом
local function droneEnemy(m)
    if isOwnDrone(m) then return false end
    local owner = droneOwner(m)
    if owner then
        if owner == LocalPlayer then return false end
        return isEnemy(owner)
    end
    return true
end

-- присваивание в уже объявленный local (не `local function` — иначе новая переменная
-- затеняет форвард-декларацию, и droneAimPart продолжает видеть nil)
function droneRoot(m)
    if not m or not m.Parent then return nil end
    local ok, pp = pcall(function() return m.PrimaryPart end)
    if ok and pp and pp:IsA("BasePart") then return pp end
    local h = m:FindFirstChild("HumanoidRootPart", true)
    if h and h:IsA("BasePart") then return h end
    return m:FindFirstChildWhichIsA("BasePart", true)
end

local function scanDrones()
    if not State.drone_esp and not State.aim_drones and not State.drone_hitbox then
        for m, _ in pairs(droneParts) do droneParts[m] = nil end
        for m, e in pairs(droneESP) do
            if e.hl then pcall(function() e.hl:Destroy() end) end
            if e.gui then pcall(function() e.gui:Destroy() end) end
            droneESP[m] = nil
        end
        return
    end
    local seen = {}
    local count = 0
    local folder = Workspace:FindFirstChild("Drones") or Workspace:FindFirstChild("Drone")
    local roots = {}
    if folder then
        for _, c in ipairs(folder:GetChildren()) do roots[#roots + 1] = c end
    else
        roots = Workspace:GetChildren()
    end
    for i = 1, #roots do
        local m = roots[i]
        if m:IsA("Model") and isDroneModel(m) then
            local r = droneRoot(m)
            if r then seen[m] = r count += 1 end
            if count >= 30 then break end
        end
    end
    if count < 5 and not folder then
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("Model") and isDroneModel(d) and not seen[d] then
                local r = droneRoot(d)
                if r then seen[d] = r count += 1 end
                if count >= 30 then break end
            end
        end
    end
    for m, r in pairs(seen) do droneParts[m] = r end
    for m, _ in pairs(droneParts) do
        if not seen[m] then
            droneParts[m] = nil
            local e = droneESP[m]
            if e then
                if e.hl then pcall(function() e.hl:Destroy() end) end
                if e.gui then pcall(function() e.gui:Destroy() end) end
                droneESP[m] = nil
            end
        end
    end
end

local function updateDroneESP(myPos)
    if not State.drone_esp or not State.esp then
        for m, e in pairs(droneESP) do
            if e.hl then pcall(function() e.hl:Destroy() end) end
            if e.gui then pcall(function() e.gui:Destroy() end) end
            droneESP[m] = nil
        end
        return
    end
    for m, part in pairs(droneParts) do
        if not m.Parent or not part.Parent then
            droneParts[m] = nil
            local e0 = droneESP[m]
            if e0 then
                if e0.hl then pcall(function() e0.hl:Destroy() end) end
                if e0.gui then pcall(function() e0.gui:Destroy() end) end
                droneESP[m] = nil
            end
        else
            local dist = myPos and math.floor((myPos - part.Position).Magnitude) or 0
            if dist > State.drone_maxdist or (isOwnDrone(m) and not State.show_own_drone) then
                local e0 = droneESP[m]
                if e0 then
                    if e0.hl then pcall(function() e0.hl:Destroy() end) end
                    if e0.gui then pcall(function() e0.gui:Destroy() end) end
                    droneESP[m] = nil
                end
            else
                local e = droneESP[m]
                if not e then
                    e = {}
                    if State.esp_chams then
                        local hl = Instance.new("Highlight")
                        hl.Name = "VantaDrone" hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        hl.FillColor = Color3.fromRGB(255, 160, 40)
                        hl.FillTransparency = 0.5 hl.OutlineTransparency = 0.1 hl.Adornee = m hl.Parent = m
                        e.hl = hl
                    end
                    local g = Instance.new("BillboardGui")
                    g.Name = "VantaDroneTag" g.Size = UDim2.new(0, 160, 0, 24)
                    g.StudsOffset = Vector3.new(0, 2, 0) g.AlwaysOnTop = true
                    g.Adornee = part g.Parent = m
                    local l = Instance.new("TextLabel") l.Size = UDim2.new(1, 0, 1, 0)
                    pcall(function() l.AutoLocalize = false end)
                    l.BackgroundTransparency = 1 l.Font = Enum.Font.GothamBold l.TextSize = 13
                    l.TextColor3 = Color3.fromRGB(255, 180, 80) l.TextStrokeTransparency = 0.4 l.Parent = g
                    e.gui, e.lbl = g, l
                    droneESP[m] = e
                end
                if e.lbl then
                    local on = m:GetAttribute("player")
                    local teamTag = ""
                    local ow = (type(on) == "string" and on ~= "") and Players:FindFirstChild(on) or nil
                    if ow then
                        local t = regTeam(ow) or sideOf(ow)
                        if t then teamTag = "[" .. string.upper(t):sub(1, 3) .. "]" end
                    end
                    e.lbl.Text = "ДРОН" .. ((type(on) == "string" and on ~= "") and (":" .. on) or "") .. teamTag .. " • " .. dist .. "m"
                end
                if e.gui and e.gui.Adornee ~= part then e.gui.Adornee = part end
            end
        end
    end
end

-- ===== МЕНЮ: ФОРВАРД-ДЕКЛАРАЦИИ =====
-- espCache / lines / boxes / fovC объявлены НИЖЕ (после UI-обёртки), поэтому колбэки меню
-- объявляются здесь и получают реализацию сразу после создания этих таблиц.
local invalidateFilters = function() end
local teardownESP = function() end
-- перерисовка всех строк меню из State: нужна после загрузки/сброса конфига
local refreshRows = function() end

-- ===== V3.0: ПРОИЗВОДИТЕЛЬНОСТЬ / ТЕЛЕМЕТРИЯ =====
-- fps считается по кадрам за окно 0.5с, ping тянется из Stats (у части экзекуторов
-- Stats.Network недоступен — тогда держим последнее значение).
local perf = { fps = 0, ping = 0, frames = 0, acc = 0 }
RunService.RenderStepped:Connect(function(dt)
    perf.frames += 1
    perf.acc += dt
    if perf.acc >= 0.5 then
        perf.fps = math.floor(perf.frames / perf.acc + 0.5)
        perf.frames, perf.acc = 0, 0
    end
end)

local Stats = game:GetService("Stats")
local function serverPing()
    local ok, v = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
    if ok and type(v) == "number" then
        perf.ping = math.floor(v + 0.5)
    end
    return perf.ping
end

-- ===== V3.0: SILENT AIM =====
-- Перехват __namecall: клиентский рейкаст разворачивается в выбранную точку хитбокса,
-- камера при этом не двигается — попадание считает сервер, траектория в логе остаётся
-- ровной. Работает на играх, где выстрел считается через Workspace:Raycast /
-- FindPartOnRay / FindPartOnRayWithIgnoreList. Там, где попадание уходит ремоутом с
-- направлением камеры, хук не участвует — нужен перехват конкретного ремоута,
-- имя которого своё у каждой версии игры.
-- Хук ставится ОДИН раз на процесс. Раньше каждый повторный exec вешал новый
-- __namecall поверх предыдущего: старые замыкания держали мёртвое окружение, и
-- внутренние вызовы движка начинали сыпать "attempt to call a nil value" из
-- CoreGui-модулей. Решение: флаг в getgenv + одно замыкание на всех.
local function silentArgs(self, ...)
    local method = getnamecallmethod()
    if self ~= Workspace then return false end
    if method ~= "Raycast" and method ~= "FindPartOnRay" and method ~= "FindPartOnRayWithIgnoreList" then
        return false
    end
    local part = silentBox.part
    if not (part and part.Parent) then return false end
    local args = { ... }
    local origin
    if method == "Raycast" then
        if typeof(args[1]) == "Vector3" then origin = args[1] end
    elseif typeof(args[1]) == "Ray" then
        origin = args[1].Origin
    end
    -- уводим только рейкасты из-под своей камеры: чужие системы игры не трогаем
    if not origin or (origin - Camera.CFrame.Position).Magnitude >= 25 then return false end
    local aimAt = part.Position
    if silentBox.hitpart == "Random" then
        aimAt = part.Position + Vector3.new(
            (math.random() - 0.5) * part.Size.X,
            (math.random() - 0.5) * part.Size.Y,
            (math.random() - 0.5) * part.Size.Z)
    end
    if method == "Raycast" then
        args[2] = aimAt - origin
    else
        args[1] = Ray.new(origin, (aimAt - origin).Unit * 1000)
    end
    return true, args
end

do
    local env = (getgenv and getgenv()) or _G
    local already = type(env) == "table" and env.__JakoSilentHook
    if not already then
        local mt = getrawmetatable and getrawmetatable(game)
        local old = mt and mt.__namecall
        if mt and old and setreadonly and newcclosure then
            setreadonly(mt, false)
            mt.__namecall = newcclosure(function(self, ...)
                -- решение о подмене принимает pcall: что бы внутри ни сломалось,
                -- вызов всё равно уйдёт в оригинал и движок не пострадает
                if silentBox.on and silentBox.part and not silentBox.guard then
                    local ok, swapped, args = pcall(silentArgs, self, ...)
                    if ok and swapped then
                        return old(self, table.unpack(args))
                    end
                end
                return old(self, ...)
            end)
            setreadonly(mt, true)
            if type(env) == "table" then env.__JakoSilentHook = true end
        end
    end
end

local function silentHitPart(ch)
    if not ch then return nil end
    if State.silent_hitpart == "Torso" then
        return findHRP(ch) or ch:FindFirstChild("UpperTorso", true) or findHead(ch)
    end
    return findHead(ch) or ch:FindFirstChild("UpperTorso", true) or findHRP(ch)
end

-- выбор цели для silent aim: тот же FOV-критерий, но без движения камеры
local function refreshSilent()
    silentBox.on = State.silent_aim and true or false
    silentBox.hitpart = State.silent_hitpart
    if not silentBox.on then
        silentBox.part = nil
        return
    end
    local center = Camera.ViewportSize / 2
    local best, bestD = nil, State.silent_fov
    local all = Players:GetPlayers()
    for i = 1, #all do
        local p = all[i]
        if p ~= LocalPlayer and canAim(p) then
            local ch = p.Character
            local pt = silentHitPart(ch)
            if pt then
                local pos, on = Camera:WorldToViewportPoint(pt.Position)
                if on then
                    local d = (Vector2.new(pos.X, pos.Y) - center).Magnitude
                    if d <= bestD and (State.silent_walls or isVisible(ch, pt)) then
                        best, bestD = pt, d
                    end
                end
            end
        end
    end
    silentBox.part = best
end

-- ===== V3.0: ХОДЬБА / ПРЫЖОК / NOCLIP =====
local baseSpeed, baseJump = 16, 50
do
    local hum = findHum(LocalPlayer.Character)
    if hum then baseSpeed, baseJump = hum.WalkSpeed, hum.JumpPower end
end

local function applyMovement()
    local char = LocalPlayer.Character
    local hum = findHum(char)
    if not hum then return end
    local wantSpeed = State.speed_on and State.speed_val or baseSpeed
    if math.abs(hum.WalkSpeed - wantSpeed) > 0.01 then hum.WalkSpeed = wantSpeed end
    if State.jump_on then
        pcall(function() hum.UseJumpPower = true end)
        if math.abs(hum.JumpPower - State.jump_val) > 0.01 then hum.JumpPower = State.jump_val end
    elseif math.abs(hum.JumpPower - baseJump) > 0.01 then
        hum.JumpPower = baseJump
    end
    if State.noclip and char then
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") and d.CanCollide then d.CanCollide = false end
        end
    end
end

local function applyInfJump()
    if not State.inf_jump then return end
    local hum = findHum(LocalPlayer.Character)
    if not hum then return end
    local st = hum:GetState()
    if st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.Jumping then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

-- anti-afk: Roblox кикает за 20 минут простоя, Idled срабатывает до кика
do
    local ok, VU = pcall(function() return game:GetService("VirtualUser") end)
    if ok and VU then
        LocalPlayer.Idled:Connect(function()
            if not State.anti_afk then return end
            pcall(function()
                VU:CaptureController()
                VU:ClickButton2(Vector2.new())
            end)
        end)
    end
end

-- ===== V3.0: КОНФИГ НА ДИСК =====
-- Сериализатор знает три типа + EnumItem: KeyCode переживает перезапуск экзекутора.
local CFG_PATH = "JakoScripts/lostfront.cfg"

local function encodeValue(v)
    if type(v) == "number" then return string.format("%.6g", v) end
    if type(v) == "boolean" then return v and "true" or "false" end
    if type(v) == "string" then return string.format("%q", v) end
    if typeof(v) == "EnumItem" then return string.format("Enum.%s.%s", v.EnumType.Name, v.Name) end
    return "nil"
end

local function decodeValue(s)
    s = string.match(s, "^%s*(.-)%s*$") or s
    if s == "true" then return true end
    if s == "false" then return false end
    local num = tonumber(s)
    if num then return num end
    local str = string.match(s, '^"(.*)"$')
    if str then return str end
    local et, en = string.match(s, "^Enum%.([%w_]+)%.([%w_]+)$")
    if et and en then
        local ok, item = pcall(function() return Enum[et][en] end)
        if ok then return item end
    end
    return nil
end

local CONFIG_SKIP = { ui_key = true } -- ключ интерфейса живёт в шелле, не перезаписываем

local function saveConfig()
    if not writefile then return false, "экзекутор без writefile" end
    local keys = {}
    for k in pairs(State) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = { "-- JakoScripts LOST FRONT v3.0 config" }
    for i = 1, #keys do
        local k = keys[i]
        if not CONFIG_SKIP[k] then
            out[#out + 1] = k .. "=" .. encodeValue(State[k])
        end
    end
    if makefolder then pcall(makefolder, "JakoScripts") end
    local ok = pcall(writefile, CFG_PATH, table.concat(out, "\n"))
    return ok, ok and CFG_PATH or "запись не удалась"
end

local function loadConfig()
    if not (readfile and isfile) then return false, "экзекутор без readfile" end
    local exists = false
    pcall(function() exists = isfile(CFG_PATH) end)
    if not exists then return false, "файла нет" end
    local ok, body = pcall(readfile, CFG_PATH)
    if not ok or type(body) ~= "string" then return false, "чтение не удалось" end
    local n = 0
    for line in string.gmatch(body, "[^\r\n]+") do
        if not string.match(line, "^%s*%-%-") then
            local k, v = string.match(line, "^([%w_]+)%s*=%s*(.+)$")
            if k and State[k] ~= nil and not CONFIG_SKIP[k] then
                local val = decodeValue(v)
                if val ~= nil then State[k] = val n += 1 end
            end
        end
    end
    return n > 0, n .. " значений"
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
    title    = "LOST FRONT",
    subtitle = "lost front",
    version  = "v3.0",
})

-- живой статус из updateStatus() (бывший status.Text)
local setStat = UI:Stat("Я: — E0 A0 D0")

-- Combat
local tabCombat = UI:Tab("Combat", "target")
tabCombat:Section("Аим — только враги")
tabCombat:Toggle("Аимбот", "aimbot", true)
tabCombat:Toggle("Аим только пока зажата клавиша", "aim_hold", true)
tabCombat:Toggle("Аим по ДРОНАМ", "aim_drones", true)
tabCombat:Toggle("Воллчек", "aim_wallcheck", true)
tabCombat:Toggle("Упреждение (предикт)", "aim_predict", true)
tabCombat:Toggle("Залипание на цели", "aim_sticky", true)
tabCombat:Cycle("Приоритет цели", "aim_priority", { "Crosshair", "Distance", "LowHP" })
tabCombat:Cycle("Кривая наведения", "aim_ease", { "Linear", "EaseOut", "Snap" })
tabCombat:Slider("FOV", "aim_fov", 40, 500)
tabCombat:Slider("Плавность (больше=резче)", "aim_smooth", 1, 100)
tabCombat:Keybind("Сменить клавишу аима", "aim_key")
tabCombat:Cycle("Аим-часть: Голова / Торс", "aim_part", { "Head", "HumanoidRootPart" })

tabCombat:Section("Silent aim — камера не двигается")
tabCombat:Toggle("Silent aim (хук рейкаста)", "silent_aim", false)
tabCombat:Cycle("Точка попадания", "silent_hitpart", { "Head", "Torso", "Random" })
tabCombat:Slider("Silent FOV", "silent_fov", 40, 500)
tabCombat:Toggle("Silent: бить через стены", "silent_walls", false)

tabCombat:Section("Команда")
tabCombat:Toggle("Проверка команды", "team_check", true)
tabCombat:Cycle("Моя сторона: АВТО", "my_side", { "AUTO", "attackers", "defenders" }, function()
    invalidateFilters()
end)

tabCombat:Section("Триггербот")
tabCombat:Toggle("Триггербот", "triggerbot", false)
tabCombat:Keybind("Клавиша триггера", "trigger_key")
tabCombat:Slider("Задержка триггера (мс)", "trigger_ms", 50, 500)
tabCombat:Slider("Радиус триггера (px)", "trigger_fov", 4, 60)

tabCombat:Section("Хитбоксы")
tabCombat:Toggle("Хитбокс игроков-врагов", "hitbox", false)
tabCombat:Slider("Размер хитбокса", "hitbox_size", 2, 12)
tabCombat:Toggle("Хитбокс ДРОНОВ", "drone_hitbox", false)
tabCombat:Slider("Размер хитбокса дронов", "drone_hitbox_size", 3, 15)

-- Visuals
local tabVisuals = UI:Tab("Visuals", "eye")
tabVisuals:Section("Визуал — враги")
tabVisuals:Toggle("ESP вкл", "esp", true)
tabVisuals:Toggle("Показывать ПРОТИВНИКОВ", "show_enemies", true)
tabVisuals:Toggle("Показывать СВОИХ (обычно выкл)", "show_allies", false)
tabVisuals:Toggle("Имена", "esp_names", true)
tabVisuals:Toggle("Дистанция", "esp_distance", true)
tabVisuals:Toggle("Здоровье", "esp_health", true)
tabVisuals:Toggle("HP-бар (Drawing)", "esp_hpbar", false)
tabVisuals:Toggle("Чамсы Highlight (жрёт FPS)", "esp_chams", true)
tabVisuals:Slider("Макс. дистанция ESP", "esp_maxdist", 150, 1500)
tabVisuals:Section("Оверлеи")
tabVisuals:Toggle("Скелет (Drawing)", "esp_skeleton", false)
tabVisuals:Slider("Толщина скелета", "esp_skeleton_thick", 1, 4)
tabVisuals:Toggle("Линия до цели", "esp_target_line", false)
tabVisuals:Toggle("Трассеры", "tracers", false)
tabVisuals:Toggle("2D-боксы (Drawing)", "esp_boxes", false)
tabVisuals:Toggle("FOV круг", "fov_show", true)
tabVisuals:Toggle("FOV заливка", "fov_fill", false)
tabVisuals:Slider("FOV камеры", "cam_fov", 70, 120, nil, function(v)
    if Camera then Camera.FieldOfView = v end
end)
tabVisuals:Section("Дроны")
tabVisuals:Toggle("ESP ДРОНОВ", "drone_esp", true)
tabVisuals:Toggle("Показывать СВОЙ дрон", "show_own_drone", false)
tabVisuals:Slider("Макс. дистанция дронов", "drone_maxdist", 150, 1500)
tabVisuals:Button("Обновить ростер / сбросить цель", "ghost", function()
    rescanRoster()
    invalidateFilters()
end)

-- Movement
local tabMovement = UI:Tab("Movement", "zap")
tabMovement:Section("Движение")
tabMovement:Toggle("Карабканье по стенам (держи Space)", "wallclimb", false)
tabMovement:Slider("Скорость карабканья", "wallclimb_speed", 10, 60)
tabMovement:Toggle("Своя скорость ходьбы", "speed_on", false)
tabMovement:Slider("Скорость", "speed_val", 16, 200)
tabMovement:Toggle("Своя сила прыжка", "jump_on", false)
tabMovement:Slider("Сила прыжка", "jump_val", 50, 300)
tabMovement:Toggle("Бесконечный прыжок", "inf_jump", false)
tabMovement:Toggle("Noclip (сквозь стены)", "noclip", false)
tabMovement:Toggle("Anti-AFK", "anti_afk", false)

-- Config
local tabConfig = UI:Tab("Config", "settings")
tabConfig:Section("interface")
tabConfig:Keybind("Toggle key", "ui_key")
tabConfig:Toggle("Notifications", "ui_toasts", true)
tabConfig:Toggle("Watermark", "ui_watermark", true)
tabConfig:Toggle("Watermark: FPS / ping", "ui_stats", true)
tabConfig:Toggle("Background blur", "ui_blur", true)
tabConfig:Section("config")
tabConfig:Button("Сохранить настройки", nil, function()
    local ok, info = saveConfig()
    UI:Toast(ok and ("Сохранено: " .. tostring(info)) or ("Не сохранено: " .. tostring(info)), ok and "ok" or "warn")
end)
tabConfig:Button("Загрузить настройки", "ghost", function()
    local ok, info = loadConfig()
    refreshRows()
    if Camera then Camera.FieldOfView = State.cam_fov end
    if UI.blur then pcall(function() UI.blur.Enabled = State.ui_blur end) end
    if UI.watermark then UI.watermark.Visible = State.ui_watermark end
    UI:Toast(ok and ("Загружено: " .. tostring(info)) or ("Не загружено: " .. tostring(info)), ok and "ok" or "warn")
end)
tabConfig:Button("Сбросить к дефолту", "ghost", function()
    for k, v in pairs(StateDefaults) do State[k] = v end
    refreshRows()
    if Camera then Camera.FieldOfView = State.cam_fov end
    if UI.blur then pcall(function() UI.blur.Enabled = State.ui_blur end) end
    if UI.watermark then UI.watermark.Visible = State.ui_watermark end
    UI:Toast("Настройки сброшены", "ok")
end)
tabConfig:Section("session")
tabConfig:Button("Unload JakoScripts", "ghost", function()
    UI:Destroy()
    teardownESP()
end)
tabConfig:Info("Сторона: GC-реестр, контейнеры, ростер, подсветка.")
tabConfig:Info("Silent aim работает на рейкаст-играх. Если игра считает попадание ремоутом, нужен перехват этого ремоута.")

-- ввод аима и карабканья — перенесён из старого GUI-блока (RightShift теперь у шелла)
UserInputService.InputBegan:Connect(function(i, gp)
    if gp or UI.listening then return end -- пока идёт переназначение клавиши, ввод не трогаем
    if i.KeyCode == State.aim_key then aiming = true end
    if i.KeyCode == State.trigger_key then triggerHeld = true end
    if i.UserInputType == Enum.UserInputType.MouseButton2 then rmbDown = true end
    if i.KeyCode == Enum.KeyCode.Space then
        spaceHeld = true
        if State.inf_jump then applyInfJump() end
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.KeyCode == State.aim_key then aiming = false stickyTarget = nil end
    if i.KeyCode == State.trigger_key then triggerHeld = false end
    if i.UserInputType == Enum.UserInputType.MouseButton2 then rmbDown = false end
    if i.KeyCode == Enum.KeyCode.Space then spaceHeld = false end
end)

-- ===== DRAWING =====
local hasDraw = false
pcall(function() if Drawing then hasDraw = true end end)
local ACCENT = Color3.fromRGB(160, 140, 255)
local fovC, cross, targetLine = nil, nil, nil
local lines, boxes = {}, {}
local skelCache = {} -- [player] = { char, links = { {a, b, line} }, n, next }
local bars = {}      -- [player] = { bg, fill }
if hasDraw then
    pcall(function()
        fovC = Drawing.new("Circle") fovC.Thickness = 1 fovC.NumSides = 48
        fovC.Filled = false fovC.Transparency = 0.7 fovC.Color = ACCENT
        cross = Drawing.new("Text") cross.Size = 16 cross.Center = true cross.Outline = true
        cross.Text = "+" cross.Color = Color3.fromRGB(255,255,255) cross.Transparency = 0.8
        targetLine = Drawing.new("Line") targetLine.Thickness = 1
        targetLine.Transparency = 0.45 targetLine.Color = ACCENT targetLine.Visible = false
    end)
end

local function dropSkeleton(p)
    local e = skelCache[p]
    if e then
        for i = 1, #e.links do pcall(function() e.links[i].line:Remove() end) end
        skelCache[p] = nil
    end
end

local function dropBar(p)
    local b = bars[p]
    if b then
        if b.bg then pcall(function() b.bg:Remove() end) end
        if b.fill then pcall(function() b.fill:Remove() end) end
        bars[p] = nil
    end
end

local function hideDraw(p)
    local l = lines[p] if l then l.Visible = false end
    local b = boxes[p] if b then b.Visible = false end
    local s = skelCache[p]
    if s then for i = 1, #s.links do s.links[i].line.Visible = false end end
    local hb = bars[p]
    if hb then
        if hb.bg then hb.bg.Visible = false end
        if hb.fill then hb.fill.Visible = false end
    end
end

Players.PlayerRemoving:Connect(function(p)
    hideDraw(p)
    local l = lines[p] if l then pcall(function() l:Remove() end) lines[p] = nil end
    local b = boxes[p] if b then pcall(function() b:Remove() end) boxes[p] = nil end
    dropSkeleton(p)
    dropBar(p)
end)

-- ---------- скелет: кости читаем из Motor6D, поэтому риг подходит любой ----------
-- (R6, R15, кастомный). Список костей пересобирается раз в 0.5с, линии живут между
-- пересборками — иначе GetDescendants в каждом кадре съедал бы fps.
local SKELETON_RESCAN = 0.5

local function rigMotors(char)
    local out = {}
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("Motor6D") then
            local a, b = d.Part0, d.Part1
            if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
                out[#out + 1] = { a, b }
            end
        end
    end
    return out
end

local function drawSkeleton(p, char, col)
    local e = skelCache[p]
    if not e or e.char ~= char then
        dropSkeleton(p)
        e = { char = char, links = {}, n = -1, next = 0 }
        skelCache[p] = e
    end
    local now = os.clock()
    if e.n < 0 or now >= e.next then
        e.next = now + SKELETON_RESCAN
        local defs = rigMotors(char)
        if #defs ~= e.n then
            for i = 1, #e.links do pcall(function() e.links[i].line:Remove() end) end
            e.links = {}
            for i = 1, #defs do
                local ln = Drawing.new("Line")
                ln.Transparency = 0.85
                e.links[i] = { a = defs[i][1], b = defs[i][2], line = ln }
            end
            e.n = #defs
        end
    end
    for i = 1, #e.links do
        local lk = e.links[i]
        if lk.a.Parent and lk.b.Parent then
            local pa, oa = Camera:WorldToViewportPoint(lk.a.Position)
            local pb, ob = Camera:WorldToViewportPoint(lk.b.Position)
            if oa and ob and pa.Z > 0 and pb.Z > 0 then
                lk.line.From = Vector2.new(pa.X, pa.Y)
                lk.line.To = Vector2.new(pb.X, pb.Y)
                lk.line.Thickness = State.esp_skeleton_thick
                lk.line.Color = col
                lk.line.Visible = true
            else
                lk.line.Visible = false
            end
        else
            lk.line.Visible = false
        end
    end
end

local function drawHPBar(p, headPos, hp, maxhp)
    local b = bars[p]
    if not b then
        b = { bg = Drawing.new("Square"), fill = Drawing.new("Square") }
        b.bg.Filled = true b.bg.Thickness = 0
        b.bg.Color = Color3.fromRGB(10, 10, 14) b.bg.Transparency = 0.45
        b.fill.Filled = true b.fill.Thickness = 0
        bars[p] = b
    end
    local pos, on = Camera:WorldToViewportPoint(headPos + Vector3.new(0, 2.2, 0))
    local dist = (Camera.CFrame.Position - headPos).Magnitude
    if not (on and pos.Z > 0 and dist < State.esp_maxdist) then
        b.bg.Visible = false b.fill.Visible = false
        return
    end
    local sc = 900 / math.max(20, dist)
    local w = math.clamp(sc * 0.6, 24, 160)
    local h = 4
    local x, y = pos.X - w / 2, pos.Y
    b.bg.Size = Vector2.new(w, h) b.bg.Position = Vector2.new(x, y) b.bg.Visible = true
    local r = math.clamp(hp / math.max(1, maxhp), 0, 1)
    b.fill.Size = Vector2.new(math.max(1, w * r), h)
    b.fill.Position = Vector2.new(x, y)
    b.fill.Color = r > 0.5 and Color3.fromRGB(140, 255, 140)
        or (r > 0.25 and Color3.fromRGB(255, 190, 80) or Color3.fromRGB(255, 90, 90))
    b.fill.Visible = true
end

-- ===== ESP игроков =====
local espCache = {}
local function clearESP(p)
    local e = espCache[p]
    if e then
        if e.hl then pcall(function() e.hl:Destroy() end) end
        if e.gui then pcall(function() e.gui:Destroy() end) end
        espCache[p] = nil
    end
    hideDraw(p)
end

-- ===== МЕНЮ: КОЛБЭКИ (реализация форвард-деклараций выше) =====
invalidateFilters = function()
    stickyTarget = nil
    for p, _ in pairs(espCache) do clearESP(p) end
end

-- перерисовка строк меню из State — после загрузки/сброса конфига
refreshRows = function()
    for _, row in pairs(UI.rows or {}) do
        if row and row.Refresh then pcall(row.Refresh) end
    end
end

-- снять всё, что скрипт создал в игре (кнопка Unload JakoScripts)
teardownESP = function()
    State.esp = false
    State.drone_esp = false
    State.aimbot = false
    State.silent_aim = false
    State.triggerbot = false
    State.hitbox = false
    State.drone_hitbox = false
    State.wallclimb = false
    State.noclip = false
    State.inf_jump = false
    State.tracers = false
    State.esp_boxes = false
    State.esp_skeleton = false
    State.esp_hpbar = false
    State.esp_target_line = false
    State.fov_show = false
    State.speed_on = false
    State.jump_on = false
    silentBox.on = false
    silentBox.part = nil
    stickyTarget = nil
    triggerHeld = false
    for p, _ in pairs(espCache) do clearESP(p) end
    for m, e in pairs(droneESP) do
        if e.hl then pcall(function() e.hl:Destroy() end) end
        if e.gui then pcall(function() e.gui:Destroy() end) end
        droneESP[m] = nil
    end
    for _, l in pairs(lines) do pcall(function() l:Remove() end) end
    for _, b in pairs(boxes) do pcall(function() b:Remove() end) end
    lines, boxes = {}, {}
    for p, _ in pairs(skelCache) do dropSkeleton(p) end
    for p, _ in pairs(bars) do dropBar(p) end
    if fovC then pcall(function() fovC:Remove() end) end
    if cross then pcall(function() cross:Remove() end) end
    if targetLine then pcall(function() targetLine:Remove() end) end
    fovC, cross, targetLine = nil, nil, nil
    local hum = findHum(LocalPlayer.Character)
    if hum then
        hum.WalkSpeed = baseSpeed
        hum.JumpPower = baseJump
    end
    if Camera then Camera.FieldOfView = 70 end
end

-- фильтры показа переключили в меню: старый toggle-колбэк сбрасывал цель и кэш ESP
local shownSnap = { State.show_enemies, State.show_allies, State.esp_chams }
local function filtersDirty()
    if shownSnap[1] == State.show_enemies and shownSnap[2] == State.show_allies
        and shownSnap[3] == State.esp_chams then
        return false
    end
    shownSnap[1], shownSnap[2], shownSnap[3] = State.show_enemies, State.show_allies, State.esp_chams
    return true
end

local function ensureESP(p, char, enemy)
    local e = espCache[p]
    if not e then
        e = {}
        if State.esp_chams then
            local hl = Instance.new("Highlight")
            hl.Name = "VantaLF" hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.FillTransparency = 0.6 hl.OutlineTransparency = 0.1 hl.Adornee = char hl.Parent = char
            e.hl = hl
        end
        local head = findHead(char)
        if head then
            local g = Instance.new("BillboardGui")
            g.Name = "VantaLFName" g.Size = UDim2.new(0,200,0,54)
            g.StudsOffset = Vector3.new(0,3,0) g.AlwaysOnTop = true
            g.Adornee = head g.Parent = char
            local n = Instance.new("TextLabel") n.Size = UDim2.new(1,0,0,20) n.BackgroundTransparency = 1
            pcall(function() n.AutoLocalize = false end)
            n.Font = Enum.Font.GothamBold n.TextSize = 13 n.TextStrokeTransparency = 0.4 n.Parent = g
            local d = Instance.new("TextLabel") d.Size = UDim2.new(1,0,0,16) d.Position = UDim2.new(0,0,0,19)
            pcall(function() d.AutoLocalize = false end)
            d.BackgroundTransparency = 1 d.Font = Enum.Font.Gotham d.TextSize = 12
            d.TextColor3 = Color3.fromRGB(230,230,235) d.TextStrokeTransparency = 0.4 d.Parent = g
            local hp = Instance.new("TextLabel") hp.Size = UDim2.new(1,0,0,14) hp.Position = UDim2.new(0,0,0,34)
            pcall(function() hp.AutoLocalize = false end)
            hp.BackgroundTransparency = 1 hp.Font = Enum.Font.GothamBold hp.TextSize = 12 hp.TextStrokeTransparency = 0.4 hp.Parent = g
            e.gui, e.n, e.d, e.hp = g, n, d, hp
        end
        espCache[p] = e
    end
    if State.esp_chams and not e.hl and char then
        local hl = Instance.new("Highlight")
        hl.Name = "VantaLF" hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillTransparency = 0.6 hl.OutlineTransparency = 0.1 hl.Adornee = char hl.Parent = char
        e.hl = hl
    elseif not State.esp_chams and e.hl then
        pcall(function() e.hl:Destroy() end) e.hl = nil
    end
    if e.hl then
        if e.hl.Adornee ~= char then e.hl.Adornee = char end
        e.hl.FillColor = enemy and Color3.fromRGB(255,70,70) or Color3.fromRGB(90,255,130)
    end
    local col = enemy and Color3.fromRGB(255,70,70) or Color3.fromRGB(90,255,130)
    return e, col
end

local myHRP = nil
local dbgEnemies, dbgAllies = 0, 0
local function updateESP()
    if filtersDirty() then invalidateFilters() end
    local char0 = LocalPlayer.Character
    myHRP = findHRP(char0)
    local myPos = myHRP and myHRP.Position or nil
    updateDroneESP(myPos)
    if not State.esp then
        for p, _ in pairs(espCache) do clearESP(p) end
        for p, _ in pairs(lines) do hideDraw(p) end
        for p, _ in pairs(skelCache) do hideDraw(p) end
        for p, _ in pairs(bars) do hideDraw(p) end
        dbgEnemies, dbgAllies = 0, 0
        return
    end
    local nE, nA = 0, 0
    local all = Players:GetPlayers()
    for i = 1, #all do
        local p = all[i]
        if p == LocalPlayer or not isAlive(p) or not canShow(p) then
            if espCache[p] then clearESP(p) end
        else
            local char = p.Character
            local hrp = findHRP(char)
            local head = findHead(char)
            if not hrp or not head then
                if espCache[p] then clearESP(p) end
            else
                local dist = myPos and math.floor((myPos - hrp.Position).Magnitude) or 0
                if dist > State.esp_maxdist then
                    if espCache[p] then clearESP(p) end
                    hideDraw(p)
                else
                    local enemy = isEnemy(p)
                    if enemy then nE += 1 else nA += 1 end
                    local e, col = ensureESP(p, char, enemy)
                    if e.gui then
                        e.gui.Enabled = State.esp_names or State.esp_distance or State.esp_health
                        if e.n then e.n.Visible = State.esp_names end
                        if e.d then e.d.Visible = State.esp_distance end
                        if e.hp then e.hp.Visible = State.esp_health end
                        if State.esp_names and e.n then e.n.Text = p.DisplayName e.n.TextColor3 = col end
                        if State.esp_distance and e.d then e.d.Text = dist .. "m" end
                        if State.esp_health and e.hp then
                            local h = findHum(char)
                            local hpv = h and math.floor(h.Health) or 0
                            e.hp.Text = "HP " .. hpv
                            e.hp.TextColor3 = hpv > 50 and Color3.fromRGB(140,255,140) or Color3.fromRGB(255,150,80)
                        end
                    end
                    if hasDraw then
                        local pos, on = Camera:WorldToViewportPoint(head.Position)
                        local vs = Camera.ViewportSize
                        local l = lines[p]
                        if State.tracers and on then
                            if not l then l = Drawing.new("Line") l.Thickness = 1 l.Transparency = 0.75 lines[p] = l end
                            l.Color = col l.From = Vector2.new(vs.X/2, vs.Y) l.To = Vector2.new(pos.X, pos.Y) l.Visible = true
                        elseif l then l.Visible = false end
                        local b = boxes[p]
                        if State.esp_boxes and on then
                            if not b then b = Drawing.new("Square") b.Thickness = 1 b.Filled = false b.Transparency = 0.9 boxes[p] = b end
                            local sc = 900 / math.max(20, (Camera.CFrame.Position - head.Position).Magnitude)
                            b.Size = Vector2.new(sc*0.6, sc)
                            b.Position = Vector2.new(pos.X - sc*0.3, pos.Y - sc/2)
                            b.Color = col b.Visible = true
                        elseif b then b.Visible = false end
                    end
                    if hasDraw then
                        if State.esp_skeleton then
                            drawSkeleton(p, char, col)
                        else
                            local s = skelCache[p]
                            if s then for i = 1, #s.links do s.links[i].line.Visible = false end end
                        end
                        if State.esp_hpbar then
                            local h = findHum(char)
                            drawHPBar(p, head.Position, h and h.Health or 0, h and h.MaxHealth or 100)
                        else
                            dropBar(p)
                        end
                    end
                end
            end
        end
    end
    dbgEnemies, dbgAllies = nE, nA
    for p, _ in pairs(espCache) do if not p.Parent then clearESP(p) end end
end
Players.PlayerRemoving:Connect(clearESP)

-- ===== AIMBOT (игроки + дроны, только враги) =====
local function aimActive()
    if not State.aimbot then return false end
    if State.aim_hold then return aiming or rmbDown end
    return true
end

local cachedPart = nil

local function stickyValid()
    local t = stickyTarget
    if not t then return nil end
    if typeof(t) == "Instance" and t:IsA("Model") then
        if State.aim_drones and droneEnemy(t) then
            local part = droneAimPart(t)
            if part and part.Parent then return part end
        end
        return nil
    else
        if t.Parent and canAim(t) then
            local ch = t.Character
            local pt = ch and getAimPart(ch)
            if pt then
                local pos, on = Camera:WorldToViewportPoint(pt.Position)
                if on and (Vector2.new(pos.X,pos.Y) - Camera.ViewportSize/2).Magnitude <= State.aim_fov * 1.5 then
                    return pt
                end
            end
        end
        return nil
    end
end

local function searchTarget()
    if State.aim_sticky then
        local sp = stickyValid()
        if sp then cachedPart = sp return end
        stickyTarget = nil
    end
    cachedPart = nil
    local center = Camera.ViewportSize / 2
    local cands = {}
    local all = Players:GetPlayers()
    for i = 1, #all do
        local p = all[i]
        if p ~= LocalPlayer and canAim(p) then
            local ch = p.Character
            local pt = ch and getAimPart(ch)
            if pt then
                local pos, on = Camera:WorldToViewportPoint(pt.Position)
                if on then
                    local dx = pos.X - center.X
                    local dy = pos.Y - center.Y
                    local dd = math.sqrt(dx*dx + dy*dy)
                    if dd <= State.aim_fov then
                        local hum = findHum(ch)
                        cands[#cands + 1] = {
                            dd = dd, part = pt, who = p,
                            hp = hum and hum.Health or math.huge,
                            d3 = (Camera.CFrame.Position - pt.Position).Magnitude,
                        }
                    end
                end
            end
        end
    end
    if State.aim_drones then
        for m, _ in pairs(droneParts) do
            if m.Parent and droneEnemy(m) then
                local part = droneAimPart(m)
                if part and part.Parent then
                    local pos, on = Camera:WorldToViewportPoint(part.Position)
                    if on then
                        local dx = pos.X - center.X
                        local dy = pos.Y - center.Y
                        local dd = math.sqrt(dx*dx + dy*dy)
                        if dd <= State.aim_fov then
                            cands[#cands + 1] = {
                                dd = dd, part = part, who = m,
                                hp = math.huge, -- у дрона нет Humanoid: в LowHP он всегда последний
                                d3 = (Camera.CFrame.Position - part.Position).Magnitude,
                            }
                        end
                    end
                end
            end
        end
    end
    if #cands == 0 then return end
    local prio = State.aim_priority
    table.sort(cands, function(a, b)
        if prio == "Distance" and a.d3 ~= b.d3 then return a.d3 < b.d3 end
        if prio == "LowHP" and a.hp ~= b.hp then return a.hp < b.hp end
        return a.dd < b.dd
    end)
    for i = 1, math.min(3, #cands) do
        local c = cands[i]
        local cont = nil
        if typeof(c.who) == "Instance" and c.who:IsA("Model") then cont = c.who
        elseif c.who.Character then cont = c.who.Character end
        if isVisible(cont, c.part) then
            cachedPart, stickyTarget = c.part, c.who
            return
        end
    end
end

local lastTrigger = 0
local function aimFrame()
    if fovC then
        local vs = Camera.ViewportSize
        fovC.Position = vs/2 fovC.Radius = State.aim_fov
        fovC.Visible = State.fov_show
        fovC.Filled = State.fov_fill
        fovC.Transparency = State.fov_fill and 0.92 or 0.7
    end
    if cross then
        local vs = Camera.ViewportSize
        cross.Position = Vector2.new(vs.X/2, vs.Y/2 - 14) cross.Visible = true
    end
    if not aimActive() then
        cachedPart = nil
        if targetLine then targetLine.Visible = false end
        return
    end
    local mc = LocalPlayer.Character
    if not mc or not findHRP(mc) then return end
    local pt = cachedPart
    if targetLine then
        if State.esp_target_line and pt and pt.Parent then
            local pos, on = Camera:WorldToViewportPoint(pt.Position)
            local vs = Camera.ViewportSize
            if on then
                targetLine.From = Vector2.new(vs.X/2, vs.Y/2)
                targetLine.To = Vector2.new(pos.X, pos.Y)
                targetLine.Visible = true
            else
                targetLine.Visible = false
            end
        else
            targetLine.Visible = false
        end
    end
    if pt and pt.Parent then
        local goal = predictPos(pt)
        local k = math.clamp(State.aim_smooth/100, 0.01, 1)
        -- кривая подлёта: Linear — ровно, EaseOut — быстро в начале и мягко у цели,
        -- Snap — мгновенно (по сути без плавности)
        if State.aim_ease == "EaseOut" then
            k = 1 - (1 - k) * (1 - k)
        elseif State.aim_ease == "Snap" then
            k = 1
        end
        if k >= 1 then
            Camera.CFrame = CFrame.new(Camera.CFrame.Position, goal)
        else
            Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, goal), k)
        end
    end
    -- триггербот: отдельная клавиша, свой радиус, работает и без движения камеры
    if State.triggerbot and pt and pt.Parent and (triggerHeld or not State.aim_hold) then
        local pos, on = Camera:WorldToViewportPoint(pt.Position)
        if on and (Vector2.new(pos.X,pos.Y) - Camera.ViewportSize/2).Magnitude < State.trigger_fov then
            local now = os.clock()
            if now - lastTrigger > State.trigger_ms/1000 then
                lastTrigger = now
                pcall(function() mouse1click() end)
            end
        end
    end
end

-- ===== КАРАБКАНЬЕ ПО СТЕНАМ =====
local climbParams = RaycastParams.new()
climbParams.FilterType = Enum.RaycastFilterType.Blacklist
climbParams.IgnoreWater = true
local function wallclimbTick()
    if not State.wallclimb or not spaceHeld then return end
    local char = LocalPlayer.Character
    local hrp = findHRP(char)
    local hum = findHum(char)
    if not hrp or not hum or hum.Health <= 0 then return end
    if hum.FloorMaterial ~= Enum.Material.Air then return end
    climbParams.FilterDescendantsInstances = { char }
    local origin = hrp.Position
    local cf = hrp.CFrame
    local dirs = { cf.LookVector, -cf.LookVector, cf.RightVector, -cf.RightVector }
    for i = 1, 4 do
        silentBox.guard = true
        local res = Workspace:Raycast(origin, dirs[i] * 4, climbParams)
        silentBox.guard = false
        if res and math.abs(res.Normal.Y) < 0.35 then
            local v = hrp.AssemblyLinearVelocity
            hrp.AssemblyLinearVelocity = Vector3.new(v.X * 0.25, State.wallclimb_speed, v.Z * 0.25)
            break
        end
    end
end

-- ===== HITBOX =====
-- исходные размер / прозрачность / коллизию запоминаем на саму часть: восстановление
-- не должно угадывать по Transparency == 0.7 — чужой скрипт мог выставить то же число.
local hitboxOrig = setmetatable({}, { __mode = "k" })

local function restorePart(part)
    local o = hitboxOrig[part]
    if not o then return end
    pcall(function()
        part.Size = o.size
        part.Transparency = o.transparency
        part.CanCollide = o.collide
    end)
    hitboxOrig[part] = nil
end

local function expandPart(part, size, transparency)
    if not hitboxOrig[part] then
        hitboxOrig[part] = { size = part.Size, transparency = part.Transparency, collide = part.CanCollide }
    end
    part.Size = Vector3.new(size, size, size)
    part.Transparency = transparency
    part.CanCollide = false
end

local function applyHitbox()
    local all = Players:GetPlayers()
    for i = 1, #all do
        local p = all[i]
        if p ~= LocalPlayer and p.Character then
            local part = findHRP(p.Character)
            if part then
                if State.hitbox and isEnemy(p) and isAlive(p) then
                    expandPart(part, State.hitbox_size, 0.7)
                else
                    restorePart(part)
                end
            end
        end
    end
    for m, part in pairs(droneParts) do
        if part.Parent then
            if State.drone_hitbox then
                expandPart(part, State.drone_hitbox_size, 0.5)
            else
                restorePart(part)
            end
        end
    end
end

-- ===== STATUS =====
local function mySideLabel()
    if State.my_side ~= "AUTO" then return State.my_side .. "|manual" end
    local rt = regTeam(LocalPlayer)
    if rt then teamSrc = "reg" return rt .. "|reg" end
    local s = sideOf(LocalPlayer)
    if s then return s .. "|roster" end
    local mc = charContainer(LocalPlayer)
    if mc then return "ok|cont" end
    return "?|hilite"
end

local function updateStatus()
    local dc = 0
    for _ in pairs(droneParts) do dc += 1 end
    setStat("Я: " .. mySideLabel() .. " E" .. dbgEnemies .. " A" .. dbgAllies .. " D" .. dc
        .. (State.silent_aim and " S" or ""))
end

-- ===== LOOPS =====
rescanRoster()
-- живые дроны подхватываем сразу при спавне (как у Bac0nHck)
Workspace.DescendantAdded:Connect(function(d)
    if d:IsA("Model") then
        task.delay(0.35, function()
            if isDroneModel(d) then
                local r = droneRoot(d)
                if r then droneParts[d] = r end
            end
        end)
    end
end)
Camera = Workspace.CurrentCamera
RunService.RenderStepped:Connect(function()
    Camera = Workspace.CurrentCamera
    aimFrame()
end)
local tAim, tEsp, tMisc, tScan, tStat, tRos = 0, 0, 0, 0, 0, 0
RunService.Heartbeat:Connect(function(dt)
    wallclimbTick()
    applyMovement()
    tAim += dt tEsp += dt tMisc += dt tScan += dt tStat += dt tRos += dt
    if tAim >= 0.08 then
        tAim = 0
        if aimActive() then searchTarget() end
        refreshSilent()
    end
    if tEsp >= 0.4 then
        tEsp = 0
        updateESP()
    end
    if tScan >= 1.5 then
        tScan = 0
        scanDrones()
    end
    if tRos >= 3 then
        tRos = 0
        rescanRoster()
    end
    if tMisc >= 2.0 then
        tMisc = 0
        applyHitbox()
    end
    if tStat >= 1.0 then
        tStat = 0
        updateStatus()
        -- шелл держит blur и вотермарку на себе: синхронизируем с State раз в секунду,
        -- чтобы тумблеры Config не обрастали колбэками
        if UI.watermark and UI.watermark.Visible ~= State.ui_watermark then
            UI.watermark.Visible = State.ui_watermark
        end
        if UI.blur and UI.blur.Enabled ~= State.ui_blur then
            UI.blur.Enabled = State.ui_blur
        end
        -- FOV камеры игра сбрасывает сама — переустанавливаем не каждый кадр, а раз в секунду
        if Camera and math.abs(Camera.FieldOfView - State.cam_fov) > 0.5 then
            Camera.FieldOfView = State.cam_fov
        end
        UI:Banner(State.ui_stats
            and string.format("LF v3.0 · %d FPS · %d MS", perf.fps, serverPing())
            or "LOST FRONT")
    end
end)
scanDrones()

UI:Toast("JakoScripts LOST FRONT v3.0 loaded", "ok")
print("[JakoScripts LOST FRONT v3.0 · Style A] loaded")
