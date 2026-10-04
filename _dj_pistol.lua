-- VANTA Pistol Arena v1 | Luau | [Ранговая] Арена пистолетов | Executor
-- Аимбот для FPS (доводка камеры, FOV + воллчек + сглаживание), триггербот,
-- ESP-оверлей (боксы/ники/дистанция). Только Drawing — деталей в игре нет.
-- Ранкед = античит строже: только альт, legit-настройки по умолчанию.
-- UI: RightShift / кнопка V.
-- Запуск: loadstring(game:HttpGet("RAW_URL"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

if not Drawing then
    warn("[VANTA PA] нет Drawing в executor")
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "VANTA", Text = "Нужен executor с Drawing", Duration = 4,
        })
    end)
    return
end

-- ===== STATE =====
local State = {
    aimbot = true,
    aim_hold = true,      -- только пока зажата клавиша
    aim_key = Enum.KeyCode.E,
    aim_part = "Head",
    aim_fov = 110,
    aim_smooth = 25,      -- 1..100, меньше = плавнее/легитнее
    aim_wallcheck = true,
    triggerbot = false,   -- авто-выстрел при наведении
    trigger_dist = 12,    -- пикселей от центра
    trigger_delay = 0.12,
    esp = true,
    names = true,
    tracers = false,
    fov_show = true,
    maxdist = 1200,
    team_check = true,
    show_allies = false,
    antiafk = true,
}

local aiming = false
local rmbDown = false
local cachedPart, cachedPlr = nil, nil
local lastTrigger = 0
local dbgShown = 0
local teamSrc = "team"

local function notify(t)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", { Title = "VANTA", Text = tostring(t), Duration = 2 })
    end)
end

-- ===== TEAM =====
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
    if isEnemy(plr) then return true end
    return State.show_allies
end

local function aimPartOf(char)
    if not char then return nil end
    return char:FindFirstChild(State.aim_part, true)
        or char:FindFirstChild("Head", true)
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
    -- от глаз FPS-камеры: исключаем камеру, себя и руки (ViewModel)
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
    local myHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart", true)
    if not myHrp then return end
    local center = Camera.ViewportSize / 2
    local cands = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and isEnemy(p) then
            local ch = p.Character
            local pt = ch and aimPartOf(ch)
            if pt then
                if (myHrp.Position - pt.Position).Magnitude <= State.maxdist then
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
    end
    if #cands == 0 then return end
    table.sort(cands, function(a, b) return a.dd < b.dd end)
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
                    if now - lastTrigger > State.trigger_delay then
                        lastTrigger = now
                        pcall(function() mouse1click() end)
                    end
                end
            end
        end
    end
end

-- ===== OVERLAY =====
local items = {}
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

Players.PlayerRemoving:Connect(function(p)
    local it = items[p]
    if it then
        pcall(function() it.box:Remove() end)
        pcall(function() it.txt:Remove() end)
        pcall(function() it.line:Remove() end)
        items[p] = nil
    end
    if cachedPlr == p then cachedPart, cachedPlr = nil, nil end
end)

local fovC = nil
pcall(function()
    fovC = Drawing.new("Circle")
    fovC.Thickness = 1 fovC.NumSides = 48 fovC.Filled = false
    fovC.Transparency = 0.7 fovC.Color = Color3.fromRGB(140, 220, 140)
end)

local function overlayTick()
    Camera = Workspace.CurrentCamera
    if fovC then
        fovC.Position = Camera.ViewportSize / 2
        fovC.Radius = State.aim_fov
        fovC.Visible = State.fov_show and State.aimbot
    end
    local myHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart", true)
    local myPos = myHrp and myHrp.Position or Camera.CFrame.Position
    local shown = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if not State.esp or not canShow(p) then
            hideItem(p)
        else
            local ch = p.Character
            local head = ch and ch:FindFirstChild("Head", true)
            local hrp = ch and (ch:FindFirstChild("HumanoidRootPart", true) or ch:FindFirstChild("Torso", true))
            local it = getItem(p)
            if not head or not hrp then
                hideItem(p)
            else
                local dist = (myPos - hrp.Position).Magnitude
                if dist > State.maxdist then
                    hideItem(p)
                else
                    local p1, on1 = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.7, 0))
                    local p2, on2 = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 2.8, 0))
                    if not on1 or not on2 then
                        hideItem(p)
                    else
                        local h = math.abs(p2.Y - p1.Y)
                        if h < 5 then
                            hideItem(p)
                        else
                            shown += 1
                            local w = h * 0.6
                            local col = isEnemy(p) and Color3.fromRGB(255, 90, 70) or Color3.fromRGB(90, 180, 255)
                            it.box.Size = Vector2.new(w, h)
                            it.box.Position = Vector2.new(p1.X - w / 2, p1.Y)
                            it.box.Color = col
                            it.box.Visible = true
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
    end
    dbgShown = shown
end

-- ===== GUI =====
local parent
do
    if gethui then local ok, r = pcall(gethui) if ok and r then parent = r end
    elseif get_hui then local ok, r = pcall(get_hui) if ok and r then parent = r end end
    if not parent then parent = game:GetService("CoreGui") end
end
pcall(function() local o = parent:FindFirstChild("VantaPistol") if o then o:Destroy() end end)

local gui = Instance.new("ScreenGui")
gui.Name = "VantaPistol"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = parent

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 330, 0, 460)
main.Position = UDim2.new(0.5, -165, 0.5, -230)
main.BackgroundColor3 = Color3.fromRGB(16, 16, 21)
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
local mst = Instance.new("UIStroke", main) mst.Color = Color3.fromRGB(140, 220, 140) mst.Transparency = 0.5

local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, 0, 0, 36)
bar.BackgroundColor3 = Color3.fromRGB(26, 26, 34)
bar.BorderSizePixel = 0
bar.Parent = main
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 10)
local fix = Instance.new("Frame") fix.Size = UDim2.new(1, 0, 0, 10) fix.Position = UDim2.new(0, 0, 1, -10)
fix.BackgroundColor3 = Color3.fromRGB(26, 26, 34) fix.BorderSizePixel = 0 fix.Parent = bar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -90, 1, 0) title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1 title.Text = "VANTA | Pistol Arena  v1"
title.Font = Enum.Font.GothamBold title.TextSize = 14
title.TextColor3 = Color3.fromRGB(235, 235, 245) title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = bar

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -24, 0, 18) status.Position = UDim2.new(0, 12, 0, 38)
status.BackgroundTransparency = 1 status.Text = "E — аим | RightShift — скрыть"
status.Font = Enum.Font.Gotham status.TextSize = 12
status.TextColor3 = Color3.fromRGB(150, 150, 165) status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = main

local minB = Instance.new("TextButton")
minB.Size = UDim2.new(0, 28, 0, 28) minB.Position = UDim2.new(1, -34, 0, 4)
minB.BackgroundColor3 = Color3.fromRGB(45, 45, 58) minB.Text = "–"
minB.Font = Enum.Font.GothamBold minB.TextSize = 18
minB.TextColor3 = Color3.fromRGB(220, 220, 230) minB.Parent = bar
Instance.new("UICorner", minB).CornerRadius = UDim.new(0, 7)

local showB = Instance.new("TextButton")
showB.Size = UDim2.new(0, 44, 0, 44) showB.Position = UDim2.new(0, 20, 0.5, -22)
showB.BackgroundColor3 = Color3.fromRGB(16, 16, 21) showB.Text = "V"
showB.Font = Enum.Font.GothamBlack showB.TextSize = 20
showB.TextColor3 = Color3.fromRGB(140, 220, 140) showB.Visible = false showB.Parent = gui
Instance.new("UICorner", showB).CornerRadius = UDim.new(1, 0)
local sst = Instance.new("UIStroke", showB) sst.Color = Color3.fromRGB(140, 220, 140)

local function setVis(v) main.Visible = v showB.Visible = not v end
minB.MouseButton1Click:Connect(function() setVis(false) end)
showB.MouseButton1Click:Connect(function() setVis(true) end)
UserInputService.InputBegan:Connect(function(i, gp)
    if gp then return end
    if i.KeyCode == Enum.KeyCode.RightShift then setVis(not main.Visible) end
    if i.KeyCode == State.aim_key then aiming = true end
    if i.UserInputType == Enum.UserInputType.MouseButton2 then rmbDown = true end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.KeyCode == State.aim_key then aiming = false end
    if i.UserInputType == Enum.UserInputType.MouseButton2 then rmbDown = false end
end)

do
    local drag, ds, sp = false, nil, nil
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            drag, ds, sp = true, i.Position, main.Position
            i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then drag = false end end)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - ds
            main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
        end
    end)
end

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -70) scroll.Position = UDim2.new(0, 10, 0, 60)
scroll.BackgroundTransparency = 1 scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4 scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new(0, 0, 0, 0) scroll.Parent = main
local ll = Instance.new("UIListLayout") ll.Padding = UDim.new(0, 6) ll.SortOrder = Enum.SortOrder.LayoutOrder ll.Parent = scroll

local function section(t)
    local l = Instance.new("TextLabel") l.Size = UDim2.new(1, 0, 0, 20) l.BackgroundTransparency = 1
    l.Text = t:upper() l.Font = Enum.Font.GothamBold l.TextSize = 12
    l.TextColor3 = Color3.fromRGB(140, 220, 140) l.TextXAlignment = Enum.TextXAlignment.Left l.Parent = scroll
end
local function toggle(text, key, def, cb)
    State[key] = def
    local b = Instance.new("TextButton") b.Size = UDim2.new(1, 0, 0, 32)
    b.BackgroundColor3 = Color3.fromRGB(26, 26, 34) b.Text = "" b.Parent = scroll
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
    local l = Instance.new("TextLabel") l.Size = UDim2.new(1, -52, 1, 0) l.Position = UDim2.new(0, 10, 0, 0)
    l.BackgroundTransparency = 1 l.Text = text l.Font = Enum.Font.Gotham l.TextSize = 13
    l.TextColor3 = Color3.fromRGB(215, 215, 225) l.TextXAlignment = Enum.TextXAlignment.Left l.Parent = b
    local ind = Instance.new("Frame") ind.Size = UDim2.new(0, 18, 0, 18) ind.Position = UDim2.new(1, -30, 0.5, -9)
    ind.BackgroundColor3 = def and Color3.fromRGB(110, 200, 130) or Color3.fromRGB(60, 60, 72)
    ind.BorderSizePixel = 0 ind.Parent = b
    Instance.new("UICorner", ind).CornerRadius = UDim.new(1, 0)
    b.MouseButton1Click:Connect(function()
        State[key] = not State[key]
        ind.BackgroundColor3 = State[key] and Color3.fromRGB(110, 200, 130) or Color3.fromRGB(60, 60, 72)
        if cb then task.spawn(cb, State[key]) end
    end)
end
local function slider(text, key, minV, maxV, def)
    State[key] = def
    local h = Instance.new("Frame") h.Size = UDim2.new(1, 0, 0, 46)
    h.BackgroundColor3 = Color3.fromRGB(26, 26, 34) h.BorderSizePixel = 0 h.Parent = scroll
    Instance.new("UICorner", h).CornerRadius = UDim.new(0, 7)
    local l = Instance.new("TextLabel") l.Size = UDim2.new(1, -20, 0, 20) l.Position = UDim2.new(0, 10, 0, 2)
    l.BackgroundTransparency = 1 l.Font = Enum.Font.Gotham l.TextSize = 13
    l.TextColor3 = Color3.fromRGB(215, 215, 225) l.TextXAlignment = Enum.TextXAlignment.Left l.Parent = h
    local barS = Instance.new("Frame") barS.Size = UDim2.new(1, -20, 0, 6) barS.Position = UDim2.new(0, 10, 0, 30)
    barS.BackgroundColor3 = Color3.fromRGB(50, 50, 62) barS.BorderSizePixel = 0 barS.Parent = h
    Instance.new("UICorner", barS).CornerRadius = UDim.new(1, 0)
    local f = Instance.new("Frame") f.Size = UDim2.new(0, 0, 1, 0)
    f.BackgroundColor3 = Color3.fromRGB(110, 200, 130) f.BorderSizePixel = 0 f.Parent = barS
    Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
    local function ref()
        l.Text = text .. ": " .. tostring(math.floor(State[key] + 0.5))
        f.Size = UDim2.new(math.clamp((State[key] - minV) / math.max(1e-6, (maxV - minV)), 0, 1), 0, 1, 0)
    end
    ref()
    local sl = false
    local function ap(x)
        local r = math.clamp((x - barS.AbsolutePosition.X) / math.max(1, barS.AbsoluteSize.X), 0, 1)
        State[key] = minV + (maxV - minV) * r ref()
    end
    barS.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then sl = true ap(i.Position.X) end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then sl = false end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if sl and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then ap(i.Position.X) end
    end)
end
local function button(text, cb)
    local b = Instance.new("TextButton") b.Size = UDim2.new(1, 0, 0, 32)
    b.BackgroundColor3 = Color3.fromRGB(28, 52, 36) b.Text = text
    b.Font = Enum.Font.GothamBold b.TextSize = 13 b.TextColor3 = Color3.fromRGB(230, 230, 240) b.Parent = scroll
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
    b.MouseButton1Click:Connect(function() task.spawn(cb) end)
end

section("Аим")
toggle("Аимбот", "aimbot", true)
toggle("Только пока зажата клавиша", "aim_hold", true)
toggle("Воллчек", "aim_wallcheck", true)
slider("FOV", "aim_fov", 40, 400, 110)
slider("Плавность (меньше=плавнее)", "aim_smooth", 1, 100, 25)
button("Часть: Голова / Торс", function()
    State.aim_part = (State.aim_part == "Head") and "HumanoidRootPart" or "Head"
    notify("Аим: " .. State.aim_part)
end)
button("Сменить клавишу аима", function()
    notify("Нажми клавишу...")
    local c c = UserInputService.InputBegan:Connect(function(i, gp)
        if gp or i.KeyCode == Enum.KeyCode.Unknown or i.KeyCode == Enum.KeyCode.RightShift then return end
        State.aim_key = i.KeyCode
        notify("Клавиша: " .. tostring(i.KeyCode):gsub("Enum.KeyCode.", ""))
        c:Disconnect()
    end)
end)

section("Стрельба")
toggle("Триггербот", "triggerbot", false)
slider("Радиус триггера (px)", "trigger_dist", 4, 40, 12)
slider("Задержка триггера (мс)", "trigger_delay", 50, 500, 120)

section("Визуал")
toggle("ESP", "esp", true)
toggle("Ники", "names", true)
toggle("Трассеры", "tracers", false)
toggle("FOV-круг", "fov_show", true)
slider("Макс. дистанция", "maxdist", 300, 3000, 1200)
toggle("Проверка команды", "team_check", true)
toggle("Показывать своих", "show_allies", false)

section("Мир")
toggle("Анти-АФК", "antiafk", true)

-- ===== ANTI-AFK =====
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

-- ===== LOOPS =====
RunService.RenderStepped:Connect(function()
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
        status.Text = "цель: " .. tn .. " | видно: " .. dbgShown .. " | src:" .. teamSrc
    end
end)

notify("VANTA Pistol v1 загружен")
print("[VANTA Pistol v1] loaded")