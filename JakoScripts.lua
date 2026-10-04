--[[
    JakoScripts | MM2 — Style A "Dark Violet Glass"
    language: Luau | file: JakoScripts.lua | target: Roblox / Murder Mystery 2 (executor)
    ui: 480x360 · sidebar 150 · tabs Combat / Visuals / Movement / Config · toggle: RightShift
    font: Inter (auto-fallback Gotham) · icons: lucide target / eye / zap / settings, vector-drawn
    no emoji anywhere in the surface.

    ── brand lock ───────────────────────────────────────────────
      Название скрипта — всегда JakoScripts. Ни при каком билде не меняется:
      файл, окно, вотермарка, тосты, print, имена объектов в Explorer, конфиг
      на диске и глобалы. Единственный источник имени — таблица BRAND ниже.

    ── запуск ───────────────────────────────────────────────────
      инжектор, одной строкой (репозиторий приватный — токен в CFG.token бутстрапа):
        loadstring(game:HttpGet("https://raw.githubusercontent.com/JakoScripts/JakoScripts/main/JakoScripts_loader.lua"))()
      локально, если файл лежит в workspace экзекутора:
        loadstring(readfile("JakoScripts.lua"))()

    ── design lock ──────────────────────────────────────────────
      surface   #06060B
      glass     white 6-10% + blur 28px
      border    1px #FFFFFF1C   highlight #FFFFFF22
      accent    #7C3AED         icons #A78BFA
      text      #FFFFFF / #A1A1AA / #71717A
      action    #FFFFFF on #09090B
      row       #FFFFFF08 / border #FFFFFF0F / radius 12
      switch    ON #7C3AED   OFF #FFFFFF1E
      slider    track #FFFFFF15  fill #7C3AED -> #C4B5FD

    ── logic carried over from v2 (all fixes kept) ──────────────
      1. murderer targets sheriff too               isEnemy()
      2. Highlight DepthMode.AlwaysOnTop            visible through walls
      3. item esp: cache + DescendantAdded + 2s sweep, no per-frame GetDescendants
      4. aim: lerp + FOV + wallcheck + closest-to-crosshair, no camera snap
      5. noclip restores collisions on toggle off / unload
      6. speed & jump re-apply on CharacterAdded
      7. executor without Drawing no longer errors   HAS_DRAWING guard
      8. full unload wipes highlights, drawings, gui, lighting
      9. role notify, coin magnet, fly, tp-to-gun, fullbright with full restore
    ── new in v3 ────────────────────────────────────────────────
     10. camera read dynamically — v2 cached Workspace.CurrentCamera and went stale on respawn
     11. Style A shell: sidebar nav, rebindable toggle key, panel opacity + acrylic toggle,
         save / load / reset profile, JakoScripts watermark + toasts
     12. _G.VANTA_THEME exported so every other loader renders the same palette,
         _G.JakoScripts carries the brand table (name / version / style)
]]

-- ============================================================
-- 0. environment
-- ============================================================
local cloneref = (cloneref or clone_ref or cloneRef)

local function svc(name)
    local ok, s = pcall(function() return game:GetService(name) end)
    if not ok or not s then return nil end
    if cloneref then pcall(cloneref, s) end
    return s
end

local Players          = svc("Players")
local RunService       = svc("RunService")
local UserInputService = svc("UserInputService")
local Lighting         = svc("Lighting")
local TweenService     = svc("TweenService")
local HttpService      = svc("HttpService")
local Workspace        = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local function cam() return Workspace.CurrentCamera end

local HAS_DRAWING = false
do
    local ok = pcall(function()
        if Drawing ~= nil then
            local t = Drawing.new("Line")
            t:Remove()
            HAS_DRAWING = true
        end
    end)
    if not ok then HAS_DRAWING = false end
end
local HAS_FIRETOUCH = (firetouchinterest ~= nil)
local HAS_FILE = (writefile ~= nil and readfile ~= nil and isfile ~= nil)

-- forward declarations (closures built before the logic section)
local myChar, myHRP, myHum, toast, saveConfig, loadConfig, watermark

-- ── brand lock ───────────────────────────────────────────────
-- имя скрипта фиксировано: JakoScripts. правится только здесь.
local BRAND = {
    name     = "JakoScripts",
    mark     = "JAKO",
    wordmark = "SCRIPTS",
    product  = "JakoScripts | MM2",
    version  = "v3.0",
    style    = "VANTA Style A · Dark Violet Glass",
    tag      = "— JAKO SCRIPTS",
}
_G.JakoScripts = BRAND

-- ============================================================
-- 1. config descriptor — Style A source of truth
-- ============================================================
local VANTA_WINDUI = {
    Transparent       = true,
    TransparencyValue = 0.12,
    Theme             = "VantaViolet",
    Acrylic           = true,
    AcrylicBlurAmount = 28,
}

local CONFIG = {
    theme       = "VantaViolet",
    font_family = "Inter",
    blur_px     = 28,
    window      = Vector2.new(480, 360),
    sidebar_w   = 150,
    toggle_key  = Enum.KeyCode.RightShift,
    config_file = "jakoscripts_mm2_config.json",
}

-- exported so every other VANTA loader pulls the same palette
local VANTA_THEME = {
    name       = CONFIG.theme,
    surface    = "#06060B",
    glass      = "#FFFFFF",
    glass_6    = 0.06,
    glass_8    = 0.08,
    glass_10   = 0.10,
    border     = "#FFFFFF1C",
    highlight  = "#FFFFFF22",
    accent     = "#7C3AED",
    accent_hi  = "#C4B5FD",
    icon       = "#A78BFA",
    text       = "#FFFFFF",
    text_muted = "#A1A1AA",
    text_dim   = "#71717A",
    action_bg  = "#FFFFFF",
    action_fg  = "#09090B",
    row_bg     = "#FFFFFF08",
    row_border = "#FFFFFF0F",
    radius     = 12,
    switch_on  = "#7C3AED",
    switch_off = "#FFFFFF1E",
    track      = "#FFFFFF15",
    blur       = 28,
    font       = "Inter",
}
_G.VANTA_THEME = VANTA_THEME

-- ============================================================
-- 2. state
-- ============================================================
local State = {
    -- combat
    aimbot         = false,
    aim_hold       = true,
    aim_wallcheck  = true,
    aim_fov        = 150,
    aim_smooth     = 25,
    aim_part       = "Head",
    autoshoot      = false,
    auto_equip     = true,
    killaura       = false,
    killaura_range = 10,
    -- visuals
    esp_murderer   = true,
    esp_sheriff    = true,
    esp_innocent   = false,
    esp_names      = true,
    esp_distance   = true,
    esp_health     = true,
    tracers        = false,
    esp_items      = true,
    esp_coins      = true,
    esp_gun        = true,
    fullbright     = false,
    -- movement
    speed          = false,
    speed_value    = 50,
    jump           = false,
    jump_value     = 100,
    noclip         = false,
    infjump        = false,
    fly            = false,
    fly_speed      = 60,
    -- farm
    coinFarm       = false,
    -- interface
    ui_alpha       = 0.08,
    ui_blur        = true,
    ui_watermark   = true,
    ui_toasts      = true,
    toggle_key     = CONFIG.toggle_key,
}

local DEFAULTS = {}
for k, v in pairs(State) do DEFAULTS[k] = v end

local Connections = {}
local function bind(c) Connections[#Connections + 1] = c; return c end

-- ============================================================
-- 3. palette / helpers
-- ============================================================
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
    murderer  = Color3.fromRGB(255, 77, 94),
    sheriff   = Color3.fromRGB(77, 141, 255),
    innocent  = Color3.fromRGB(52, 211, 153),
}

local A = {
    glass6   = 0.94,
    glass8   = 0.92,
    glass10  = 0.90,
    row      = 0.969,  -- #FFFFFF08
    row_line = 0.941,  -- #FFFFFF0F
    stroke   = 0.890,  -- #FFFFFF1C
    hilite   = 0.867,  -- #FFFFFF22
    sw_off   = 0.882,  -- #FFFFFF1E
    track    = 0.918,  -- #FFFFFF15
}

local UI = { pages = {}, nav = {}, rows = {}, current = nil, listening = nil }

local function corner(inst, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 12)
    c.Parent = inst
    return c
end

local function circle(inst)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(1, 0)
    c.Parent = inst
    return c
end

local function stroke(inst, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or P.white
    s.Thickness = thickness or 1
    s.Transparency = transparency or A.stroke
    pcall(function() s.LineJoinMode = Enum.LineJoinMode.Round end)
    s.Parent = inst
    return s
end

local function tween(inst, props, time)
    if not TweenService then
        for k, v in pairs(props) do pcall(function() inst[k] = v end) end
        return
    end
    local t = TweenService:Create(inst,
        TweenInfo.new(time or 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    t:Play()
    return t
end

-- roblox has no letter-spacing, so display strings are glyph-tracked
local function tracked(s)
    local out = {}
    for i = 1, #s do out[#out + 1] = string.sub(s, i, i) end
    return table.concat(out, " ")
end

-- Inter when the client has the family, Gotham otherwise — decided once
local FONT_OK, FONT_REG, FONT_MED, FONT_SEMI = false, nil, nil, nil
do
    local ok, a, b, c = pcall(function()
        return Font.fromName(CONFIG.font_family, Enum.FontWeight.Regular, Enum.FontStyle.Normal),
               Font.fromName(CONFIG.font_family, Enum.FontWeight.Medium, Enum.FontStyle.Normal),
               Font.fromName(CONFIG.font_family, Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
    end)
    if ok and a then FONT_OK, FONT_REG, FONT_MED, FONT_SEMI = true, a, b, c end
end

local function applyFont(lbl, weight)
    if FONT_OK then
        local f = (weight == "semi" and FONT_SEMI) or (weight == "med" and FONT_MED) or FONT_REG
        if f and pcall(function() lbl.FontFace = f end) then return lbl end
    end
    lbl.Font = (weight == "semi" and Enum.Font.GothamBold)
        or (weight == "med" and Enum.Font.GothamMedium)
        or Enum.Font.Gotham
    return lbl
end

local function label(parent, text, size, color, weight)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text or ""
    l.TextSize = size or 12
    l.TextColor3 = color or P.text
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.Parent = parent
    applyFont(l, weight or "reg")
    return l
end

-- ============================================================
-- 4. lucide icons as vectors — no image assets, no emoji
--    drop rbxassetid values into ICON_ASSETS to switch to the PNG set
-- ============================================================
local ICON_ASSETS = { target = nil, eye = nil, zap = nil, settings = nil }

local function tick(parent, x, y, w, h, color, rotation)
    local f = Instance.new("Frame")
    f.BackgroundColor3 = color
    f.BorderSizePixel = 0
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Position = UDim2.new(0, x, 0, y)
    f.Size = UDim2.new(0, w, 0, h)
    f.Rotation = rotation or 0
    f.Parent = parent
    circle(f)
    return f
end

local function tint(holder, color)
    if holder:IsA("ImageLabel") then holder.ImageColor3 = color end
    if holder:IsA("Frame") and holder.BackgroundTransparency < 1 then holder.BackgroundColor3 = color end
    for _, d in ipairs(holder:GetDescendants()) do
        if d:IsA("UIStroke") then
            d.Color = color
        elseif d:IsA("ImageLabel") then
            d.ImageColor3 = color
        elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
            d.BackgroundColor3 = color
        end
    end
end

local function icon(parent, kind, size, color)
    size = size or 16
    color = color or P.icon

    local asset = ICON_ASSETS[kind]
    if asset then
        local img = Instance.new("ImageLabel")
        img.BackgroundTransparency = 1
        img.Size = UDim2.new(0, size, 0, size)
        img.Image = asset
        img.ImageColor3 = color
        img.Parent = parent
        return img
    end

    local holder = Instance.new("Frame")
    holder.Name = "icon_" .. kind
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.new(0, size, 0, size)
    holder.Parent = parent

    local c = size / 2
    local s = size / 16 -- 16px design grid

    local function ring(dia, thick)
        local r = Instance.new("Frame")
        r.BackgroundTransparency = 1
        r.AnchorPoint = Vector2.new(0.5, 0.5)
        r.Position = UDim2.new(0.5, 0, 0.5, 0)
        r.Size = UDim2.new(0, dia * s, 0, dia * s)
        r.Parent = holder
        circle(r)
        stroke(r, color, (thick or 1.4) * s, 0.05)
        return r
    end

    local function dot(dia)
        local d = Instance.new("Frame")
        d.BackgroundColor3 = color
        d.BorderSizePixel = 0
        d.AnchorPoint = Vector2.new(0.5, 0.5)
        d.Position = UDim2.new(0.5, 0, 0.5, 0)
        d.Size = UDim2.new(0, dia * s, 0, dia * s)
        d.Parent = holder
        circle(d)
        return d
    end

    if kind == "target" then
        ring(10)
        dot(3)
        tick(holder, c, 1.5 * s, 1.4 * s, 3 * s, color)
        tick(holder, c, size - 1.5 * s, 1.4 * s, 3 * s, color)
        tick(holder, 1.5 * s, c, 3 * s, 1.4 * s, color)
        tick(holder, size - 1.5 * s, c, 3 * s, 1.4 * s, color)
    elseif kind == "eye" then
        local lid = ring(13, 1.4)
        lid.Size = UDim2.new(0, 15 * s, 0, 10 * s)
        lid.UIStroke.Thickness = 1.4 * s
        dot(4)
    elseif kind == "zap" then
        tick(holder, c + 1.6 * s, c - 2.4 * s, 1.7 * s, 9 * s, color, -22)
        tick(holder, c - 1.6 * s, c + 2.4 * s, 1.7 * s, 9 * s, color, -22)
        tick(holder, c, c, 6 * s, 1.7 * s, color, 0)
    elseif kind == "settings" then
        ring(11)
        dot(3.2)
        for i = 0, 7 do
            local ang = math.rad(i * 45)
            local r = 6.4 * s
            tick(holder, c + math.cos(ang) * r, c + math.sin(ang) * r, 1.8 * s, 3.4 * s, color, i * 45)
        end
    end

    return holder
end

-- ============================================================
-- 5. gui root
-- ============================================================
local parentGui
do
    if gethui then
        local ok, r = pcall(gethui)
        if ok and r then parentGui = r end
    end
    if not parentGui and get_hidden_gui then
        local ok, r = pcall(get_hidden_gui)
        if ok and r then parentGui = r end
    end
    if not parentGui then
        parentGui = svc("CoreGui") or LocalPlayer:FindFirstChild("PlayerGui")
    end
end

pcall(function()
    local old = parentGui and parentGui:FindFirstChild(BRAND.name)
    if old then old:Destroy() end
end)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = BRAND.name
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 999
screenGui.Parent = parentGui

-- blur behind the shell: this is what makes the glass read as glass
local blur = Instance.new("BlurEffect")
blur.Name = "JakoScripts_Glass"
blur.Size = CONFIG.blur_px
blur.Enabled = State.ui_blur
blur.Parent = Lighting

-- ============================================================
-- 6. window shell — 480x360, sidebar 150
-- ============================================================
local WIN, SIDE, PAD = CONFIG.window, CONFIG.sidebar_w, 32

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Size = UDim2.new(0, WIN.X + PAD * 2, 0, WIN.Y + PAD * 2)
root.Position = UDim2.new(0.5, -(WIN.X / 2 + PAD), 0.5, -(WIN.Y / 2 + PAD))
root.ZIndex = 1
root.Parent = screenGui

local glow = Instance.new("Frame")
glow.Name = "Glow"
glow.BackgroundColor3 = P.accent
glow.BackgroundTransparency = 0.94
glow.BorderSizePixel = 0
glow.Size = UDim2.new(1, 0, 1, 0)
glow.ZIndex = 1
glow.Parent = root
corner(glow, 28)

local win = Instance.new("Frame")
win.Name = "Window"
win.BackgroundColor3 = P.bg
win.BackgroundTransparency = State.ui_alpha
win.BorderSizePixel = 0
win.Size = UDim2.new(0, WIN.X, 0, WIN.Y)
win.Position = UDim2.new(0, PAD, 0, PAD)
win.Active = true
win.ZIndex = 2
win.Parent = root
corner(win, 16)
stroke(win, P.white, 1, A.stroke)

local winHi = Instance.new("Frame")
winHi.BackgroundColor3 = P.white
winHi.BackgroundTransparency = A.hilite
winHi.BorderSizePixel = 0
winHi.Size = UDim2.new(1, -32, 0, 1)
winHi.Position = UDim2.new(0, 16, 0, 0)
winHi.ZIndex = 3
winHi.Parent = win

-- ---------- sidebar ----------
local side = Instance.new("Frame")
side.Name = "Sidebar"
side.BackgroundColor3 = P.white
side.BackgroundTransparency = A.glass6
side.BorderSizePixel = 0
side.Size = UDim2.new(0, SIDE, 1, 0)
side.ZIndex = 3
side.Parent = win
corner(side, 16)

-- square off the sidebar's right edge so it reads as a docked rail
local sideMask = Instance.new("Frame")
sideMask.BackgroundColor3 = P.white
sideMask.BackgroundTransparency = A.glass6
sideMask.BorderSizePixel = 0
sideMask.Size = UDim2.new(0, 16, 1, 0)
sideMask.Position = UDim2.new(0, SIDE - 16, 0, 0)
sideMask.ZIndex = 3
sideMask.Parent = win

local sideEdge = Instance.new("Frame")
sideEdge.BackgroundColor3 = P.white
sideEdge.BackgroundTransparency = A.row_line
sideEdge.BorderSizePixel = 0
sideEdge.Size = UDim2.new(0, 1, 1, -24)
sideEdge.Position = UDim2.new(0, SIDE, 0, 12)
sideEdge.ZIndex = 4
sideEdge.Parent = win

local logoRow = Instance.new("Frame")
logoRow.BackgroundTransparency = 1
logoRow.Size = UDim2.new(1, -32, 0, 20)
logoRow.Position = UDim2.new(0, 16, 0, 16)
logoRow.ZIndex = 4
logoRow.Parent = side

local logo = label(logoRow, tracked("— " .. BRAND.mark), 13, P.text, "med")
logo.Size = UDim2.new(1, 0, 1, 0)
logo.ZIndex = 4

local wordmark = label(side, tracked(BRAND.wordmark), 10, P.icon, "semi")
wordmark.Size = UDim2.new(1, -32, 0, 14)
wordmark.Position = UDim2.new(0, 16, 0, 38)
wordmark.ZIndex = 4

local logoSub = label(side, "MURDER MYSTERY 2", 9, P.dim, "med")
logoSub.Size = UDim2.new(1, -32, 0, 12)
logoSub.Position = UDim2.new(0, 16, 0, 56)
logoSub.ZIndex = 4

local nav = Instance.new("Frame")
nav.BackgroundTransparency = 1
nav.Size = UDim2.new(1, -24, 0, 200)
nav.Position = UDim2.new(0, 12, 0, 84)
nav.ZIndex = 4
nav.Parent = side

local navLayout = Instance.new("UIListLayout")
navLayout.Padding = UDim.new(0, 6)
navLayout.SortOrder = Enum.SortOrder.LayoutOrder
navLayout.Parent = nav

local sideFoot = Instance.new("Frame")
sideFoot.BackgroundTransparency = 1
sideFoot.Size = UDim2.new(1, -24, 0, 34)
sideFoot.Position = UDim2.new(0, 12, 1, -46)
sideFoot.ZIndex = 4
sideFoot.Parent = side

local keyChip = Instance.new("Frame")
keyChip.BackgroundColor3 = P.white
keyChip.BackgroundTransparency = A.track
keyChip.BorderSizePixel = 0
keyChip.Size = UDim2.new(0, 58, 0, 22)
keyChip.ZIndex = 5
keyChip.Parent = sideFoot
corner(keyChip, 7)
stroke(keyChip, P.white, 1, A.row_line)

local keyChipText = label(keyChip, "RSHIFT", 9, P.muted, "semi")
keyChipText.Size = UDim2.new(1, 0, 1, 0)
keyChipText.TextXAlignment = Enum.TextXAlignment.Center
keyChipText.ZIndex = 6

local verText = label(sideFoot, "v3 · STYLE A", 9, P.dim, "reg")
verText.Size = UDim2.new(1, -64, 1, 0)
verText.Position = UDim2.new(0, 64, 0, 0)
verText.TextXAlignment = Enum.TextXAlignment.Right
verText.ZIndex = 5

-- ---------- content ----------
local topbar = Instance.new("Frame")
topbar.BackgroundTransparency = 1
topbar.Size = UDim2.new(1, -(SIDE + 32), 0, 30)
topbar.Position = UDim2.new(0, SIDE + 16, 0, 16)
topbar.ZIndex = 3
topbar.Parent = win

local pageTitle = label(topbar, "COMBAT", 12, P.text, "semi")
pageTitle.Size = UDim2.new(0, 120, 1, 0)
pageTitle.ZIndex = 4

local roleChip = Instance.new("Frame")
roleChip.BackgroundColor3 = P.white
roleChip.BackgroundTransparency = A.track
roleChip.BorderSizePixel = 0
roleChip.Size = UDim2.new(0, 84, 0, 22)
roleChip.Position = UDim2.new(1, -112, 0.5, -11)
roleChip.ZIndex = 4
roleChip.Parent = topbar
corner(roleChip, 8)
stroke(roleChip, P.white, 1, A.row_line)

local roleDot = Instance.new("Frame")
roleDot.BackgroundColor3 = P.dim
roleDot.BorderSizePixel = 0
roleDot.Size = UDim2.new(0, 6, 0, 6)
roleDot.Position = UDim2.new(0, 9, 0.5, -3)
roleDot.ZIndex = 5
roleDot.Parent = roleChip
circle(roleDot)

local roleText = label(roleChip, "—", 10, P.muted, "med")
roleText.Size = UDim2.new(1, -22, 1, 0)
roleText.Position = UDim2.new(0, 20, 0, 0)
roleText.ZIndex = 5

local minBtn = Instance.new("TextButton")
minBtn.Name = "Minimize"
minBtn.BackgroundTransparency = 1
minBtn.Text = ""
minBtn.AutoButtonColor = false
minBtn.Size = UDim2.new(0, 22, 0, 22)
minBtn.Position = UDim2.new(1, -34, 0, 18)
minBtn.ZIndex = 6
minBtn.Parent = win

local minGlyph = label(minBtn, "—", 13, P.dim, "med")
minGlyph.Size = UDim2.new(1, 0, 1, 0)
minGlyph.TextXAlignment = Enum.TextXAlignment.Center
minGlyph.ZIndex = 7
minBtn.MouseEnter:Connect(function() minGlyph.TextColor3 = P.text end)
minBtn.MouseLeave:Connect(function() minGlyph.TextColor3 = P.dim end)

local content = Instance.new("Frame")
content.BackgroundTransparency = 1
content.Size = UDim2.new(1, -(SIDE + 32), 1, -62)
content.Position = UDim2.new(0, SIDE + 16, 0, 48)
content.ZIndex = 3
content.Parent = win

-- ============================================================
-- 7. elements
-- ============================================================
local function newPage(name)
    local sc = Instance.new("ScrollingFrame")
    sc.Name = name
    sc.BackgroundTransparency = 1
    sc.BorderSizePixel = 0
    sc.Size = UDim2.new(1, 0, 1, 0)
    sc.ScrollBarThickness = 2
    sc.ScrollBarImageColor3 = P.white
    sc.ScrollBarImageTransparency = 0.82
    sc.ScrollingDirection = Enum.ScrollingDirection.Y
    sc.CanvasSize = UDim2.new(0, 0, 0, 0)
    sc.Visible = false
    sc.ZIndex = 3
    sc.Parent = content

    local lay = Instance.new("UIListLayout")
    lay.Padding = UDim.new(0, 8)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = sc

    local p = Instance.new("UIPadding")
    p.PaddingRight = UDim.new(0, 10)
    p.PaddingBottom = UDim.new(0, 12)
    p.Parent = sc

    lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        sc.CanvasSize = UDim.new(0, 0, lay.AbsoluteContentSize.Y + 12)
    end)

    UI.pages[name] = sc
    return sc
end

local function section(parent, text)
    local f = Instance.new("Frame")
    f.BackgroundTransparency = 1
    f.Size = UDim2.new(1, 0, 0, 22)
    f.ZIndex = 3
    f.Parent = parent
    local l = label(f, tracked(string.upper(text)), 10, P.dim, "semi")
    l.Size = UDim2.new(1, 0, 1, 0)
    l.ZIndex = 4
    return f
end

-- one glass row: #FFFFFF08 fill, #FFFFFF0F border, radius 12
local function row(parent, height)
    local r = Instance.new("Frame")
    r.BackgroundColor3 = P.white
    r.BackgroundTransparency = A.row
    r.BorderSizePixel = 0
    r.Size = UDim2.new(1, 0, 0, height or 40)
    r.ZIndex = 3
    r.Parent = parent
    corner(r, 12)
    stroke(r, P.white, 1, A.row_line)
    return r
end

local function switch(parent, key, on_change)
    local pill = Instance.new("Frame")
    pill.BackgroundColor3 = State[key] and P.accent or P.white
    pill.BackgroundTransparency = State[key] and 0 or A.sw_off
    pill.BorderSizePixel = 0
    pill.Size = UDim2.new(0, 34, 0, 18)
    pill.Position = UDim2.new(1, -48, 0.5, -9)
    pill.ZIndex = 5
    pill.Parent = parent
    circle(pill)

    local knob = Instance.new("Frame")
    knob.BackgroundColor3 = P.white
    knob.BorderSizePixel = 0
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = State[key] and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
    knob.ZIndex = 6
    knob.Parent = pill
    circle(knob)

    local api = {}
    function api:Refresh()
        local on = State[key] and true or false
        tween(pill, {
            BackgroundColor3 = on and P.accent or P.white,
            BackgroundTransparency = on and 0 or A.sw_off,
        }, 0.16)
        tween(knob, {
            Position = on and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7),
        }, 0.16)
    end
    function api:Toggle()
        State[key] = not State[key]
        self:Refresh()
        if on_change then on_change(State[key]) end
    end
    return api
end

local function toggle(parent, text, key, on_change)
    local r = row(parent, 40)
    local l = label(r, text, 12, P.muted, "reg")
    l.Size = UDim2.new(1, -66, 1, 0)
    l.Position = UDim2.new(0, 14, 0, 0)
    l.ZIndex = 5

    local btn = Instance.new("TextButton")
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.ZIndex = 7
    btn.Parent = r

    local sw = switch(r, key, on_change)
    l.TextColor3 = State[key] and P.text or P.muted

    UI.rows[key] = {
        kind = "toggle",
        Refresh = function()
            sw:Refresh()
            l.TextColor3 = State[key] and P.text or P.muted
        end,
    }

    btn.MouseButton1Click:Connect(function()
        sw:Toggle()
        l.TextColor3 = State[key] and P.text or P.muted
    end)
    return r
end

local function slider(parent, text, key, min, max, suffix, on_change, fmt)
    suffix = suffix or ""
    local r = row(parent, 54)

    local l = label(r, text, 12, P.muted, "reg")
    l.Size = UDim2.new(1, -100, 0, 16)
    l.Position = UDim2.new(0, 14, 0, 8)
    l.ZIndex = 5

    local function format(v)
        if fmt then return fmt(v) end
        return tostring(v) .. suffix
    end

    local val = label(r, format(State[key]), 11, P.icon, "semi")
    val.Size = UDim2.new(0, 70, 0, 16)
    val.Position = UDim2.new(1, -84, 0, 8)
    val.TextXAlignment = Enum.TextXAlignment.Right
    val.ZIndex = 5

    local track = Instance.new("Frame")
    track.BackgroundColor3 = P.white
    track.BackgroundTransparency = A.track
    track.BorderSizePixel = 0
    track.Size = UDim2.new(1, -28, 0, 4)
    track.Position = UDim2.new(0, 14, 0, 36)
    track.ZIndex = 5
    track.Parent = r
    circle(track)

    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = P.accent
    fill.BorderSizePixel = 0
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.ZIndex = 6
    fill.Parent = track
    circle(fill)

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new(P.accent, P.accent_hi)
    grad.Parent = fill

    local knob = Instance.new("Frame")
    knob.BackgroundColor3 = P.white
    knob.BorderSizePixel = 0
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Size = UDim2.new(0, 12, 0, 12)
    knob.Position = UDim2.new(0, 0, 0.5, 0)
    knob.ZIndex = 7
    knob.Parent = track
    circle(knob)

    local hit = Instance.new("TextButton")
    hit.BackgroundTransparency = 1
    hit.Text = ""
    hit.AutoButtonColor = false
    hit.Size = UDim2.new(1, 0, 0, 24)
    hit.Position = UDim2.new(0, 0, 0, 24)
    hit.ZIndex = 8
    hit.Parent = r

    local function ratio()
        return math.clamp((State[key] - min) / math.max(1e-6, (max - min)), 0, 1)
    end
    local function paint(a)
        fill.Size = UDim2.new(a, 0, 1, 0)
        knob.Position = UDim2.new(a, 0, 0.5, 0)
    end
    local function setFromX(x)
        local ax, w = track.AbsolutePosition.X, track.AbsoluteSize.X
        if w <= 0 then return end
        local a = math.clamp((x - ax) / w, 0, 1)
        local v = min + a * (max - min)
        v = (max - min) >= 10 and math.floor(v + 0.5) or math.floor(v * 100 + 0.5) / 100
        State[key] = v
        val.Text = format(v)
        paint(a)
        if on_change then on_change(v) end
    end

    local dragging = false
    hit.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromX(i.Position.X)
        end
    end)
    bind(UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            setFromX(i.Position.X)
        end
    end))
    bind(UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end))

    paint(ratio())
    UI.rows[key] = {
        kind = "slider",
        Refresh = function()
            val.Text = format(State[key])
            paint(ratio())
        end,
    }
    return r
end

local function cycle(parent, text, key, options, on_change)
    local r = row(parent, 40)
    local l = label(r, text, 12, P.muted, "reg")
    l.Size = UDim2.new(1, -120, 1, 0)
    l.Position = UDim2.new(0, 14, 0, 0)
    l.ZIndex = 5

    local btn = Instance.new("TextButton")
    btn.BackgroundColor3 = P.white
    btn.BackgroundTransparency = A.track
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Size = UDim2.new(0, 104, 0, 24)
    btn.Position = UDim2.new(1, -116, 0.5, -12)
    btn.ZIndex = 6
    btn.Parent = r
    corner(btn, 8)
    stroke(btn, P.white, 1, A.row_line)

    local lbl = label(btn, tostring(State[key]), 10, P.icon, "semi")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.TextXAlignment = Enum.TextXAlignment.Center
    lbl.ZIndex = 7

    btn.MouseButton1Click:Connect(function()
        local idx = 1
        for i, o in ipairs(options) do
            if tostring(o) == tostring(State[key]) then idx = i break end
        end
        idx = (idx % #options) + 1
        State[key] = options[idx]
        lbl.Text = tostring(State[key])
        if on_change then on_change(State[key]) end
    end)

    UI.rows[key] = { kind = "cycle", Refresh = function() lbl.Text = tostring(State[key]) end }
    return r
end

local function button(parent, text, style, cb)
    local btn = Instance.new("TextButton")
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Text = ""
    btn.Size = UDim2.new(1, 0, 0, 34)
    btn.ZIndex = 4
    btn.Parent = parent
    corner(btn, 12)

    local lbl = label(btn, text, 11, P.action_fg, "semi")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.TextXAlignment = Enum.TextXAlignment.Center
    lbl.ZIndex = 5

    local ghost = (style == "ghost")
    btn.BackgroundColor3 = P.white
    btn.BackgroundTransparency = ghost and A.row or 0
    lbl.TextColor3 = ghost and P.muted or P.action_fg
    if ghost then stroke(btn, P.white, 1, A.row_line) end

    btn.MouseButton1Click:Connect(function() pcall(cb) end)
    btn.MouseEnter:Connect(function()
        if ghost then
            tween(btn, { BackgroundTransparency = A.track }, 0.12)
            lbl.TextColor3 = P.text
        else
            tween(btn, { BackgroundTransparency = 0.12 }, 0.12)
        end
    end)
    btn.MouseLeave:Connect(function()
        if ghost then
            tween(btn, { BackgroundTransparency = A.row }, 0.12)
            lbl.TextColor3 = P.muted
        else
            tween(btn, { BackgroundTransparency = 0 }, 0.12)
        end
    end)
    return btn
end

local function keybindRow(parent, text, key)
    local r = row(parent, 40)
    local l = label(r, text, 12, P.muted, "reg")
    l.Size = UDim2.new(1, -120, 1, 0)
    l.Position = UDim2.new(0, 14, 0, 0)
    l.ZIndex = 5

    local btn = Instance.new("TextButton")
    btn.BackgroundColor3 = P.white
    btn.BackgroundTransparency = A.track
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Size = UDim2.new(0, 104, 0, 24)
    btn.Position = UDim2.new(1, -116, 0.5, -12)
    btn.ZIndex = 6
    btn.Parent = r
    corner(btn, 8)
    local bs = stroke(btn, P.white, 1, A.row_line)

    local lbl = label(btn, State[key].Name, 10, P.muted, "semi")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.TextXAlignment = Enum.TextXAlignment.Center
    lbl.ZIndex = 7

    local function listen()
        UI.listening = key
        lbl.Text = "PRESS KEY"
        lbl.TextColor3 = P.icon
        bs.Color = P.accent
        bs.Transparency = 0.2
    end

    local function refresh()
        lbl.Text = State[key].Name
        lbl.TextColor3 = P.muted
        bs.Color = P.white
        bs.Transparency = A.row_line
    end

    btn.MouseButton1Click:Connect(listen)
    UI.rows[key] = { kind = "keybind", Refresh = refresh, Listen = listen, Done = refresh }
    return r
end

-- ============================================================
-- 8. tabs — Combat / Visuals / Movement / Config
-- ============================================================
local TABS = {
    { name = "Combat",   icon = "target",   title = "COMBAT" },
    { name = "Visuals",  icon = "eye",      title = "VISUALS" },
    { name = "Movement", icon = "zap",      title = "MOVEMENT" },
    { name = "Config",   icon = "settings", title = "CONFIG" },
}

local function switchTab(name)
    for n, page in pairs(UI.pages) do page.Visible = (n == name) end
    for n, item in pairs(UI.nav) do
        local active = (n == name)
        item.label.TextColor3 = active and P.text or P.dim
        item.wrap.BackgroundTransparency = active and A.row or 1
        item.rail.BackgroundTransparency = active and 0 or 1
        tint(item.holder, active and P.icon or P.dim)
    end
    UI.current = name
end

for i, tab in ipairs(TABS) do
    local btn = Instance.new("TextButton")
    btn.Name = tab.name
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Size = UDim2.new(1, 0, 0, 38)
    btn.LayoutOrder = i
    btn.ZIndex = 5
    btn.Parent = nav

    local rail = Instance.new("Frame")
    rail.BackgroundColor3 = P.accent
    rail.BackgroundTransparency = 1
    rail.BorderSizePixel = 0
    rail.Size = UDim2.new(0, 2, 0, 18)
    rail.Position = UDim2.new(0, -8, 0.5, -9)
    rail.ZIndex = 6
    rail.Parent = btn
    circle(rail)

    local wrap = Instance.new("Frame")
    wrap.BackgroundColor3 = P.white
    wrap.BackgroundTransparency = 1
    wrap.BorderSizePixel = 0
    wrap.Size = UDim2.new(0, 28, 0, 28)
    wrap.Position = UDim2.new(0, 6, 0.5, -14)
    wrap.ZIndex = 6
    wrap.Parent = btn
    corner(wrap, 9)

    local ico = icon(wrap, tab.icon, 16, P.dim)
    ico.Position = UDim2.new(0.5, -8, 0.5, -8)
    ico.ZIndex = 7

    local lbl = label(btn, tab.name, 12, P.dim, "med")
    lbl.Size = UDim2.new(1, -48, 1, 0)
    lbl.Position = UDim2.new(0, 42, 0, 0)
    lbl.ZIndex = 6

    btn.MouseEnter:Connect(function()
        if UI.current ~= tab.name then wrap.BackgroundTransparency = A.glass6 end
    end)
    btn.MouseLeave:Connect(function()
        if UI.current ~= tab.name then wrap.BackgroundTransparency = 1 end
    end)
    btn.MouseButton1Click:Connect(function()
        switchTab(tab.name)
        pageTitle.Text = tab.title
    end)

    UI.nav[tab.name] = { label = lbl, holder = ico, wrap = wrap, rail = rail }
    newPage(tab.name)
end

-- ---------- Combat ----------
do
    local p = UI.pages["Combat"]
    section(p, "aimbot")
    toggle(p, "Aimbot", "aimbot")
    toggle(p, "Hold RMB only", "aim_hold")
    toggle(p, "Visibility check", "aim_wallcheck")
    slider(p, "FOV", "aim_fov", 40, 500, "px")
    slider(p, "Smooth", "aim_smooth", 1, 100, "%")
    cycle(p, "Aim part", "aim_part", { "Head", "HumanoidRootPart", "Torso" })
    section(p, "auto")
    toggle(p, "Auto shoot", "autoshoot")
    toggle(p, "Auto equip tool", "auto_equip")
    toggle(p, "Kill aura", "killaura")
    slider(p, "Aura range", "killaura_range", 4, 25, "m")
end

-- ---------- Visuals ----------
do
    local p = UI.pages["Visuals"]
    section(p, "players")
    toggle(p, "ESP murderer", "esp_murderer")
    toggle(p, "ESP sheriff", "esp_sheriff")
    toggle(p, "ESP innocent", "esp_innocent")
    toggle(p, "Names + role", "esp_names")
    toggle(p, "Distance", "esp_distance")
    toggle(p, "Health", "esp_health")
    toggle(p, "Tracers", "tracers")
    section(p, "world")
    toggle(p, "Item ESP", "esp_items")
    toggle(p, "Coins", "esp_coins")
    toggle(p, "Dropped gun", "esp_gun")
    toggle(p, "Fullbright", "fullbright")
end

-- ---------- Movement ----------
do
    local p = UI.pages["Movement"]
    section(p, "speed")
    toggle(p, "Speed hack", "speed")
    slider(p, "Walk speed", "speed_value", 16, 150, "")
    toggle(p, "Higher jump", "jump")
    slider(p, "Jump power", "jump_value", 50, 250, "")
    toggle(p, "Noclip", "noclip")
    toggle(p, "Infinite jump", "infjump")
    section(p, "flight")
    toggle(p, "Fly", "fly")
    slider(p, "Fly speed", "fly_speed", 20, 200, "")
    section(p, "farm")
    toggle(p, "Coin magnet", "coinFarm")
    button(p, "Teleport to gun", "ghost", function()
        local gun = nil
        for _, o in ipairs(Workspace:GetDescendants()) do
            if o:IsA("BasePart") and (o.Name == "GunDrop" or o.Name == "Gun") then
                if o:IsDescendantOf(Workspace) then gun = o break end
            elseif o:IsA("Model") and string.find(string.lower(o.Name), "gun") then
                gun = o break
            end
        end
        local hrp = myHRP()
        if gun and hrp then
            local pos = gun:IsA("Model") and gun:GetPivot().Position or gun.Position
            hrp.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0))
            toast("Teleported to gun", "ok")
        else
            toast("Gun not found", "warn")
        end
    end)
end

-- ---------- Config ----------
do
    local p = UI.pages["Config"]
    section(p, "interface")
    keybindRow(p, "Toggle key", "toggle_key")
    slider(p, "Panel opacity", "ui_alpha", 0, 0.6, "", function(v)
        win.BackgroundTransparency = v
    end, function(v)
        return tostring(math.floor(v * 100 + 0.5)) .. "%"
    end)
    toggle(p, "Acrylic blur", "ui_blur", function(v)
        blur.Enabled = v
    end)
    toggle(p, "Watermark", "ui_watermark", function(v)
        if watermark then watermark.Visible = v end
    end)
    toggle(p, "Notifications", "ui_toasts")
    section(p, "profile")
    button(p, "Save config", "solid", function() saveConfig() end)
    button(p, "Load config", "ghost", function() loadConfig() end)
    button(p, "Reset defaults", "ghost", function()
        for k, v in pairs(DEFAULTS) do State[k] = v end
        win.BackgroundTransparency = State.ui_alpha
        blur.Enabled = State.ui_blur
        if watermark then watermark.Visible = State.ui_watermark end
        for _, r in pairs(UI.rows) do if r.Refresh then pcall(r.Refresh) end end
        toast("Defaults restored", "ok")
    end)
    section(p, "session")
    button(p, "Unload " .. BRAND.name, "ghost", function()
        if _G.__JAKOSCRIPTS_UNLOAD then _G.__JAKOSCRIPTS_UNLOAD() end
    end)
end

switchTab("Combat")
pageTitle.Text = "COMBAT"

-- ============================================================
-- 9. toasts + watermark
-- ============================================================
local toastHolder = Instance.new("Frame")
toastHolder.BackgroundTransparency = 1
toastHolder.Size = UDim2.new(0, 244, 1, -32)
toastHolder.Position = UDim2.new(1, -260, 0, 16)
toastHolder.ZIndex = 20
toastHolder.Parent = screenGui

local toastLayout = Instance.new("UIListLayout")
toastLayout.Padding = UDim.new(0, 8)
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.Parent = toastHolder

local toastOrder = 0
function toast(text, kind)
    if not State.ui_toasts then return end
    toastOrder = toastOrder + 1

    local t = Instance.new("Frame")
    t.BackgroundColor3 = P.white
    t.BackgroundTransparency = A.glass8
    t.BorderSizePixel = 0
    t.Size = UDim2.new(1, 0, 0, 38)
    t.LayoutOrder = toastOrder
    t.ZIndex = 21
    t.Parent = toastHolder
    corner(t, 12)
    stroke(t, P.white, 1, A.row_line)

    local rail = Instance.new("Frame")
    rail.BackgroundColor3 = (kind == "warn" and P.murderer) or (kind == "role" and P.sheriff) or P.accent
    rail.BorderSizePixel = 0
    rail.Size = UDim2.new(0, 2, 1, -16)
    rail.Position = UDim2.new(0, 10, 0, 8)
    rail.ZIndex = 22
    rail.Parent = t
    circle(rail)

    local l = label(t, text, 11, P.text, "med")
    l.Size = UDim2.new(1, -30, 1, 0)
    l.Position = UDim2.new(0, 20, 0, 0)
    l.ZIndex = 22
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

watermark = Instance.new("Frame")
watermark.BackgroundColor3 = P.white
watermark.BackgroundTransparency = A.glass8
watermark.BorderSizePixel = 0
watermark.Size = UDim2.new(0, 200, 0, 26)
watermark.Position = UDim2.new(0, 16, 0, 16)
watermark.Visible = State.ui_watermark
watermark.ZIndex = 20
watermark.Parent = screenGui
corner(watermark, 10)
stroke(watermark, P.white, 1, A.row_line)

local wmLogo = label(watermark, tracked("— " .. BRAND.mark), 10, P.text, "med")
wmLogo.Size = UDim2.new(0, 70, 1, 0)
wmLogo.Position = UDim2.new(0, 12, 0, 0)
wmLogo.ZIndex = 21

local wmWord = label(watermark, BRAND.wordmark, 10, P.icon, "semi")
wmWord.Size = UDim2.new(0, 48, 1, 0)
wmWord.Position = UDim2.new(0, 80, 0, 0)
wmWord.ZIndex = 21

local wmRole = label(watermark, "—", 9, P.icon, "semi")
wmRole.Size = UDim2.new(0, 58, 1, 0)
wmRole.Position = UDim2.new(1, -70, 0, 0)
wmRole.TextXAlignment = Enum.TextXAlignment.Right
wmRole.ZIndex = 21

-- ============================================================
-- 10. window input — drag rail, toggle key, minimize
-- ============================================================
local pill = Instance.new("TextButton")
pill.Name = "JakoScriptsPill"
pill.BackgroundColor3 = P.bg
pill.BackgroundTransparency = 0.12
pill.Text = ""
pill.AutoButtonColor = false
pill.Size = UDim2.new(0, 42, 0, 42)
pill.Position = UDim2.new(0, 16, 0.5, -21)
pill.Visible = false
pill.ZIndex = 20
pill.Parent = screenGui
circle(pill)
stroke(pill, P.white, 1, A.stroke)

local pillText = label(pill, "JS", 12, P.icon, "semi")
pillText.Size = UDim2.new(1, 0, 1, 0)
pillText.TextXAlignment = Enum.TextXAlignment.Center
pillText.ZIndex = 21

local function setVisible(v)
    root.Visible = v
    pill.Visible = not v
end

-- drag rail: top 44px of the shell. Sits under the buttons, so rows stay clickable.
local dragRail = Instance.new("TextButton")
dragRail.Name = "DragRail"
dragRail.BackgroundTransparency = 1
dragRail.Text = ""
dragRail.AutoButtonColor = false
dragRail.Size = UDim2.new(1, 0, 0, 44)
dragRail.ZIndex = 2
dragRail.Parent = win

do
    local dragging, dragStart, startPos = false, nil, nil
    dragRail.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = root.Position
        end
    end)
    bind(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    bind(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end))

    local pdrag, pstart, ppos = false, nil, nil
    pill.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            pdrag = true
            pstart = input.Position
            ppos = pill.Position
        end
    end)
    bind(UserInputService.InputChanged:Connect(function(input)
        if pdrag and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - pstart
            if d.Magnitude > 8 then
                pill.Position = UDim2.new(ppos.X.Scale, ppos.X.Offset + d.X, ppos.Y.Scale, ppos.Y.Offset + d.Y)
            end
        end
    end))
    bind(UserInputService.InputEnded:Connect(function() pdrag = false end))
end

local function refreshKeyChip()
    local n = (State.toggle_key and State.toggle_key.Name) or "RightShift"
    keyChipText.Text = string.upper(n == "RightShift" and "RSHIFT" or string.sub(n, 1, 8))
end
refreshKeyChip()

minBtn.MouseButton1Click:Connect(function() setVisible(false) end)
pill.MouseButton1Click:Connect(function() setVisible(true) end)

bind(UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if UI.listening then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            local key = input.KeyCode
            State.toggle_key = key
            UI.listening = nil
            local r = UI.rows["toggle_key"]
            if r and r.Done then r.Done() end
            refreshKeyChip()
            toast("Toggle key: " .. key.Name, "ok")
        end
        return
    end
    if input.KeyCode == State.toggle_key then
        setVisible(not root.Visible)
    end
end))

-- ============================================================
-- 11. game logic
-- ============================================================
local function hasToolFuzzy(plr, keywords)
    local char = plr.Character
    local bp = plr:FindFirstChildOfClass("Backpack")
    for _, cont in ipairs({ char, bp }) do
        if cont then
            for _, tool in ipairs(cont:GetChildren()) do
                if tool:IsA("Tool") then
                    local n = string.lower(tool.Name)
                    for _, kw in ipairs(keywords) do
                        if string.find(n, string.lower(kw), 1, true) then return true end
                    end
                end
            end
            if cont:FindFirstChild("Knife") then
                for _, kw in ipairs(keywords) do
                    if kw == "Knife" then return true end
                end
            end
            if cont:FindFirstChild("Gun") or cont:FindFirstChild("Revolver") then
                for _, kw in ipairs(keywords) do
                    if kw == "Gun" or kw == "Revolver" then return true end
                end
            end
        end
    end
    return false
end

local function getRole(plr)
    if not plr then return "Innocent" end
    if hasToolFuzzy(plr, { "Knife" }) then return "Murderer" end
    if hasToolFuzzy(plr, { "Gun", "Revolver" }) then return "Sheriff" end
    return "Innocent"
end

local function isAlive(plr)
    local c = plr and plr.Character
    if not c then return false end
    local hum = c:FindFirstChildOfClass("Humanoid")
    local hrp = c:FindFirstChild("HumanoidRootPart")
    return hum ~= nil and hrp ~= nil and hum.Health > 0
end

function myChar() return LocalPlayer.Character end
function myHRP()
    local c = myChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end
function myHum()
    local c = myChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function roleColor(role)
    if role == "Murderer" then return P.murderer end
    if role == "Sheriff" then return P.sheriff end
    return P.innocent
end

local function isEnemy(plr)
    local mine = getRole(LocalPlayer)
    local r = getRole(plr)
    if mine == "Murderer" then return r == "Innocent" or r == "Sheriff" end
    return r == "Murderer"
end

local RayParams = RaycastParams.new()
pcall(function()
    RayParams.FilterType = Enum.RaycastFilterType.Exclude or Enum.RaycastFilterType.Blacklist
end)
RayParams.IgnoreWater = true

local function isVisible(from, to, ignoreChar)
    if not State.aim_wallcheck then return true end
    RayParams.FilterDescendantsInstances = { myChar(), ignoreChar, cam() }
    local ok, res = pcall(function() return Workspace:Raycast(from, to - from, RayParams) end)
    if not ok then return true end
    return res == nil
end

-- ---------- ESP ----------
local playerESP, itemESP = {}, {}
local ROLE_TAG = { Murderer = "M", Sheriff = "S", Innocent = "I" }

local function clearPlayerESP(plr)
    local e = playerESP[plr]
    if e then
        pcall(function() if e.hl then e.hl:Destroy() end end)
        pcall(function() if e.bill then e.bill:Destroy() end end)
        playerESP[plr] = nil
    end
end

local function shouldShow(plr, role)
    if plr == LocalPlayer then return false end
    if not isAlive(plr) then return false end
    if role == "Murderer" then return State.esp_murderer end
    if role == "Sheriff" then return State.esp_sheriff end
    return State.esp_innocent
end

local function updateESP()
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        if plr == LocalPlayer or not char then
            clearPlayerESP(plr)
        else
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local head = char:FindFirstChild("Head")
            local hum = char:FindFirstChildOfClass("Humanoid")
            local role = getRole(plr)
            if not hrp or not head or not hum or hum.Health <= 0 or not shouldShow(plr, role) then
                clearPlayerESP(plr)
            else
                local color = roleColor(role)
                local e = playerESP[plr]
                if not e then
                    e = {}
                    local hl = Instance.new("Highlight")
                    hl.Name = "JS_" .. tostring(math.random(100000, 999999))
                    hl.FillColor = color
                    hl.OutlineColor = P.white
                    hl.FillTransparency = 0.55
                    hl.OutlineTransparency = 0
                    pcall(function() hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop end)
                    hl.Adornee = char
                    hl.Parent = char
                    e.hl = hl

                    local bill = Instance.new("BillboardGui")
                    bill.Name = "JSTag"
                    bill.Size = UDim2.new(0, 170, 0, 46)
                    bill.StudsOffset = Vector3.new(0, 2.6, 0)
                    bill.AlwaysOnTop = true
                    bill.LightInfluence = 0
                    bill.MaxDistance = 1000
                    bill.Adornee = head
                    bill.Parent = char

                    local nameL = label(bill, "", 13, color, "semi")
                    nameL.Size = UDim2.new(1, 0, 0, 18)
                    nameL.TextXAlignment = Enum.TextXAlignment.Center
                    nameL.TextStrokeTransparency = 0.3

                    local distL = label(bill, "", 11, P.muted, "reg")
                    distL.Size = UDim2.new(1, 0, 0, 14)
                    distL.Position = UDim2.new(0, 0, 0, 18)
                    distL.TextXAlignment = Enum.TextXAlignment.Center
                    distL.TextStrokeTransparency = 0.3

                    e.bill, e.nameL, e.distL = bill, nameL, distL
                    playerESP[plr] = e
                end

                if e.hl then
                    e.hl.FillColor = color
                    if e.hl.Adornee ~= char then e.hl.Adornee = char end
                end
                if e.bill then
                    if e.bill.Adornee ~= head then e.bill.Adornee = head end
                    e.bill.Enabled = State.esp_names or State.esp_distance or State.esp_health
                    e.nameL.Visible = State.esp_names
                    e.nameL.TextColor3 = color
                    e.nameL.Text = plr.DisplayName .. "  [" .. (ROLE_TAG[role] or "?") .. "]"

                    local parts = {}
                    if State.esp_distance then
                        local mhrp = myHRP()
                        local d = mhrp and math.floor((mhrp.Position - hrp.Position).Magnitude) or 0
                        parts[#parts + 1] = tostring(d) .. "m"
                    end
                    if State.esp_health then
                        parts[#parts + 1] = tostring(math.floor(hum.Health)) .. "%"
                    end
                    e.distL.Visible = #parts > 0
                    e.distL.Text = table.concat(parts, "  ·  ")
                end
            end
        end
    end
    for plr in pairs(playerESP) do
        if not plr.Parent then clearPlayerESP(plr) end
    end
end

local function itemColor(obj)
    local n = obj.Name
    if State.esp_coins and n == "Coin" then return P.accent_hi end
    if State.esp_gun and (n == "GunDrop" or n == "Gun") then return P.sheriff end
    return nil
end

local function itemOK(obj)
    if not obj or not obj.Parent or not State.esp_items then return nil end
    if not obj:IsA("BasePart") then return nil end
    if not obj:IsDescendantOf(Workspace) then return nil end
    local char = LocalPlayer.Character
    if char and obj:IsDescendantOf(char) then return nil end
    local par = obj.Parent
    if par and par:IsA("Tool") then return nil end
    return itemColor(obj)
end

local function attachItemESP(obj, color)
    if itemESP[obj] then
        itemESP[obj].FillColor = color
        return
    end
    local hl = Instance.new("Highlight")
    hl.Name = "JSi_" .. tostring(math.random(100000, 999999))
    hl.FillColor = color
    hl.OutlineColor = P.white
    hl.FillTransparency = 0.4
    hl.OutlineTransparency = 0
    pcall(function() hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop end)
    if pcall(function() hl.Adornee = obj; hl.Parent = obj end) then
        itemESP[obj] = hl
    else
        pcall(function() hl:Destroy() end)
    end
end

local function fullItemScan()
    if not State.esp_items then
        for o, hl in pairs(itemESP) do pcall(function() hl:Destroy() end); itemESP[o] = nil end
        return
    end
    local found = {}
    for _, o in ipairs(Workspace:GetDescendants()) do
        local color = itemOK(o)
        if color then
            found[o] = true
            if not itemESP[o] then attachItemESP(o, color) end
        end
    end
    for o, hl in pairs(itemESP) do
        if not found[o] or not o.Parent then
            pcall(function() hl:Destroy() end)
            itemESP[o] = nil
        end
    end
end

bind(Workspace.DescendantAdded:Connect(function(o)
    if not State.esp_items then return end
    task.defer(function()
        local color = itemOK(o)
        if color then attachItemESP(o, color) end
    end)
end))

bind(Players.PlayerRemoving:Connect(function(plr) clearPlayerESP(plr) end))

-- ---------- tracers + fov ring ----------
local tracerLines, fovCircle = {}, nil
if HAS_DRAWING then
    pcall(function()
        fovCircle = Drawing.new("Circle")
        fovCircle.Thickness = 1
        fovCircle.NumSides = 64
        fovCircle.Filled = false
        fovCircle.Transparency = 0.55
        fovCircle.Color = P.accent
        fovCircle.Visible = false
    end)
end

local function updateDrawings()
    if not HAS_DRAWING then return end
    local c = cam()
    if not c then return end
    local vs = c.ViewportSize
    local cx, cy = vs.X / 2, vs.Y / 2
    if fovCircle then
        fovCircle.Position = Vector2.new(cx, cy)
        fovCircle.Radius = State.aim_fov
        fovCircle.Visible = State.aimbot == true
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        local line = tracerLines[plr]
        local show, targetPos = false, nil
        local color = P.white
        if State.tracers and plr ~= LocalPlayer and isAlive(plr) then
            local role = getRole(plr)
            if shouldShow(plr, role) then
                local head = plr.Character and plr.Character:FindFirstChild("Head")
                if head then
                    local sp, onScr = c:WorldToViewportPoint(head.Position)
                    if onScr then
                        show = true
                        targetPos = Vector2.new(sp.X, sp.Y)
                        color = roleColor(role)
                    end
                end
            end
        end
        if show then
            if not line then
                line = Drawing.new("Line")
                line.Thickness = 1.5
                line.Transparency = 0.85
                tracerLines[plr] = line
            end
            line.Color = color
            line.From = Vector2.new(cx, vs.Y - 4)
            line.To = targetPos
            line.Visible = true
        elseif line then
            line.Visible = false
        end
    end
    for plr, line in pairs(tracerLines) do
        if not plr.Parent then pcall(function() line:Remove() end); tracerLines[plr] = nil end
    end
end

-- ---------- aimbot ----------
local aimHolding = false
bind(UserInputService.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton2 then aimHolding = true end
end))
bind(UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton2 then aimHolding = false end
end))

local aimPart = nil

local function getAimTarget()
    local c = cam()
    if not c then return nil end
    local vs = c.ViewportSize
    local cx, cy = vs.X / 2, vs.Y / 2
    local best, bestDist = nil, State.aim_fov
    local camPos = c.CFrame.Position
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and isAlive(plr) and isEnemy(plr) then
            local char = plr.Character
            local part = char and (char:FindFirstChild(State.aim_part) or char:FindFirstChild("Head"))
            if part then
                local sp, onScr = c:WorldToViewportPoint(part.Position)
                if onScr then
                    local d2 = Vector2.new(sp.X - cx, sp.Y - cy).Magnitude
                    if d2 < bestDist and isVisible(camPos, part.Position, char) then
                        best, bestDist, aimPart = plr, d2, part
                    end
                end
            end
        end
    end
    return best
end

local function updateAimbot()
    if not State.aimbot then return end
    if State.aim_hold and not aimHolding then return end
    local target = getAimTarget()
    local c = cam()
    if target and aimPart and c then
        local k = math.clamp(State.aim_smooth / 100, 0.02, 1)
        local cur = c.CFrame
        c.CFrame = cur:Lerp(CFrame.new(cur.Position, aimPart.Position), k)
    end
end

-- ---------- autoshoot / killaura ----------
local lastShoot, lastKill = 0, 0

local function equipTool(match)
    if not State.auto_equip then return nil end
    local char, hum = myChar(), myHum()
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not char or not hum or not bp then return nil end
    for _, t in ipairs(bp:GetChildren()) do
        if t:IsA("Tool") then
            local n = string.lower(t.Name)
            for _, kw in ipairs(match) do
                if string.find(n, kw, 1, true) then
                    pcall(function() hum:EquipTool(t) end)
                    return t
                end
            end
        end
    end
    return nil
end

local function currentTool(match)
    local char = myChar()
    if not char then return nil end
    local t = char:FindFirstChildOfClass("Tool")
    if not t then return nil end
    local n = string.lower(t.Name)
    for _, kw in ipairs(match) do
        if string.find(n, kw, 1, true) then return t end
    end
    return nil
end

local function updateAutoShoot()
    if not State.autoshoot then return end
    if getRole(LocalPlayer) == "Murderer" then return end
    local tool = currentTool({ "gun", "revolver" }) or equipTool({ "gun", "revolver" })
    if not tool then return end
    if getAimTarget() and aimPart then
        local now = os.clock()
        if now - lastShoot > 0.25 then
            lastShoot = now
            local c = cam()
            if c then c.CFrame = CFrame.new(c.CFrame.Position, aimPart.Position) end
            pcall(function() tool:Activate() end)
        end
    end
end

local function updateKillAura()
    if not State.killaura then return end
    if getRole(LocalPlayer) ~= "Murderer" then return end
    local hrp = myHRP()
    if not hrp then return end
    local tool = currentTool({ "knife" }) or equipTool({ "knife" })
    if not tool then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and isAlive(plr) and isEnemy(plr) then
            local thrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
            if thrp and (hrp.Position - thrp.Position).Magnitude <= State.killaura_range then
                local now = os.clock()
                if now - lastKill > 0.3 then
                    lastKill = now
                    pcall(function() tool:Activate() end)
                end
                break
            end
        end
    end
end

-- ---------- movement ----------
bind(RunService.Stepped:Connect(function()
    if not State.noclip then return end
    local char = myChar()
    if not char then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
    end
end))

local function restoreCollisions()
    local char = myChar()
    if not char then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
            local n = p.Name
            if n == "Head" or n == "Torso" or n == "UpperTorso" or n == "LowerTorso"
                or string.find(n, "Arm") or string.find(n, "Leg") then
                p.CanCollide = true
            end
        end
    end
end

bind(UserInputService.JumpRequest:Connect(function()
    if State.infjump then
        local hum = myHum()
        if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end) end
    end
end))

local flyBV, flyGyro = nil, nil
local function setFly(on)
    local hrp = myHRP()
    if on and hrp then
        if not flyBV then
            flyBV = Instance.new("BodyVelocity")
            flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            flyBV.Velocity = Vector3.zero
            flyGyro = Instance.new("BodyGyro")
            flyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            flyGyro.CFrame = hrp.CFrame
        end
        flyBV.Parent = hrp
        flyGyro.Parent = hrp
    else
        if flyBV then flyBV.Parent = nil end
        if flyGyro then flyGyro.Parent = nil end
        local hrp2 = myHRP()
        if hrp2 then hrp2.Velocity = Vector3.zero end
    end
end

local flyKeys = { W = false, A = false, S = false, D = false, Up = false, Down = false }
bind(UserInputService.InputBegan:Connect(function(i, gp)
    if gp then return end
    local c = i.KeyCode
    if c == Enum.KeyCode.W then flyKeys.W = true
    elseif c == Enum.KeyCode.A then flyKeys.A = true
    elseif c == Enum.KeyCode.S then flyKeys.S = true
    elseif c == Enum.KeyCode.D then flyKeys.D = true
    elseif c == Enum.KeyCode.Space then flyKeys.Up = true
    elseif c == Enum.KeyCode.LeftShift then flyKeys.Down = true end
end))
bind(UserInputService.InputEnded:Connect(function(i)
    local c = i.KeyCode
    if c == Enum.KeyCode.W then flyKeys.W = false
    elseif c == Enum.KeyCode.A then flyKeys.A = false
    elseif c == Enum.KeyCode.S then flyKeys.S = false
    elseif c == Enum.KeyCode.D then flyKeys.D = false
    elseif c == Enum.KeyCode.Space then flyKeys.Up = false
    elseif c == Enum.KeyCode.LeftShift then flyKeys.Down = false end
end))

local function updateFly()
    if not State.fly then return end
    local hrp = myHRP()
    local c = cam()
    if not hrp or not flyBV or not flyGyro or not c then return end
    local dir = Vector3.zero
    local cf = c.CFrame
    if flyKeys.W then dir = dir + cf.LookVector end
    if flyKeys.S then dir = dir - cf.LookVector end
    if flyKeys.D then dir = dir + cf.RightVector end
    if flyKeys.A then dir = dir - cf.RightVector end
    if flyKeys.Up then dir = dir + Vector3.new(0, 1, 0) end
    if flyKeys.Down then dir = dir - Vector3.new(0, 1, 0) end
    if UserInputService.TouchEnabled and dir.Magnitude == 0 then
        local hum = myHum()
        if hum and hum.MoveDirection.Magnitude > 0.1 then dir = hum.MoveDirection end
    end
    flyBV.Velocity = dir.Magnitude > 0 and (dir.Unit * State.fly_speed) or Vector3.zero
    flyGyro.CFrame = cf
end

local lastFly, lastNoclip = false, false
local function updateMovement()
    local hum = myHum()
    if hum then
        local wantSpeed = State.speed and State.speed_value or 16
        if hum.WalkSpeed ~= wantSpeed then hum.WalkSpeed = wantSpeed end
        local wantJump = State.jump and State.jump_value or 50
        hum.UseJumpPower = true
        if hum.JumpPower ~= wantJump then hum.JumpPower = wantJump end
    end
    if State.noclip ~= lastNoclip then
        if not State.noclip then restoreCollisions() end
        lastNoclip = State.noclip
    end
    if State.fly ~= lastFly then
        setFly(State.fly)
        lastFly = State.fly
    end
    updateFly()
    local hrp = myHRP()
    if State.fly and hrp and flyBV and flyBV.Parent ~= hrp then
        flyBV.Parent = hrp
        flyGyro.Parent = hrp
    end
end

bind(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    lastFly = false
    if State.fly then setFly(true); lastFly = true end
end))

local function updateCoinFarm()
    if not State.coinFarm or not HAS_FIRETOUCH then return end
    local hrp = myHRP()
    if not hrp then return end
    local best, bestD = nil, 18
    for _, o in ipairs(Workspace:GetDescendants()) do
        if o:IsA("BasePart") and o.Name == "Coin" then
            local d = (hrp.Position - o.Position).Magnitude
            if d < bestD then best, bestD = o, d end
        end
    end
    if best then
        pcall(function()
            firetouchinterest(hrp, best, 0)
            task.wait()
            firetouchinterest(hrp, best, 1)
        end)
    end
end

-- ---------- fullbright ----------
local savedLight, savedFX = nil, nil
local lastFB = false

local function applyFullbright(on)
    if on then
        if not savedLight then
            savedLight = {
                B = Lighting.Brightness, A = Lighting.Ambient, OA = Lighting.OutdoorAmbient,
                FE = Lighting.FogEnd, FS = Lighting.FogStart, GS = Lighting.GlobalShadows,
                EX = Lighting.ExposureCompensation, CT = Lighting.ClockTime,
            }
            savedFX = {}
            for _, fx in ipairs(Lighting:GetChildren()) do
                if fx:IsA("PostEffect") and fx.Name ~= "JakoScripts_Glass" then
                    savedFX[fx] = fx.Enabled
                    fx.Enabled = false
                end
            end
        end
        Lighting.Brightness = 2
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        Lighting.FogEnd = 100000
        Lighting.FogStart = 0
        Lighting.GlobalShadows = false
        Lighting.ExposureCompensation = 0.5
    elseif savedLight then
        Lighting.Brightness = savedLight.B
        Lighting.Ambient = savedLight.A
        Lighting.OutdoorAmbient = savedLight.OA
        Lighting.FogEnd = savedLight.FE
        Lighting.FogStart = savedLight.FS
        Lighting.GlobalShadows = savedLight.GS
        Lighting.ExposureCompensation = savedLight.EX
        Lighting.ClockTime = savedLight.CT
        if savedFX then
            for fx, en in pairs(savedFX) do pcall(function() fx.Enabled = en end) end
        end
    end
end

-- ---------- role watch (feeds the role chip + watermark) ----------
local lastRoles = {}
task.spawn(function()
    while screenGui.Parent do
        local mine = getRole(LocalPlayer)
        local mc = roleColor(mine)
        roleText.Text = mine
        roleText.TextColor3 = mc
        roleDot.BackgroundColor3 = mc
        wmRole.Text = string.upper(mine)

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local r = getRole(plr)
                if lastRoles[plr] ~= r and (r == "Murderer" or r == "Sheriff") then
                    toast(plr.DisplayName .. " — " .. string.upper(r), "role")
                end
                lastRoles[plr] = r
            end
        end
        task.wait(1)
    end
end)

-- ============================================================
-- 12. config io
-- ============================================================
local function serialize()
    local out = {}
    for k, v in pairs(State) do
        local t = type(v)
        if t == "number" or t == "boolean" or t == "string" then
            out[k] = v
        elseif typeof(v) == "EnumItem" then
            out[k] = v.Name
        end
    end
    if HttpService then
        local ok, s = pcall(function() return HttpService:JSONEncode(out) end)
        if ok then return s end
    end
    local parts = {}
    for k, v in pairs(out) do
        local val = type(v) == "string" and ('"' .. v .. '"') or tostring(v)
        parts[#parts + 1] = '"' .. k .. '":' .. val
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

function saveConfig()
    if not HAS_FILE then toast("Executor has no writefile", "warn") return end
    local ok = pcall(function() writefile(CONFIG.config_file, serialize()) end)
    toast(ok and "Config saved" or "Save failed", ok and "ok" or "warn")
end

function loadConfig()
    if not HAS_FILE then toast("Executor has no readfile", "warn") return end
    local ok, data = pcall(function() return readfile(CONFIG.config_file) end)
    if not ok or not data then toast("No config on disk", "warn") return end
    local dec
    if HttpService then
        local ok2, d = pcall(function() return HttpService:JSONDecode(data) end)
        if ok2 then dec = d end
    end
    if type(dec) ~= "table" then toast("Config unreadable", "warn") return end
    for k, v in pairs(dec) do
        if k == "toggle_key" and type(v) == "string" then
            local kc = Enum.KeyCode[v]
            if kc then State.toggle_key = kc end
        elseif DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) then
            State[k] = v
        end
    end
    win.BackgroundTransparency = State.ui_alpha
    blur.Enabled = State.ui_blur
    if watermark then watermark.Visible = State.ui_watermark end
    for _, r in pairs(UI.rows) do if r.Refresh then pcall(r.Refresh) end end
    refreshKeyChip()
    toast("Config loaded", "ok")
end

-- ============================================================
-- 13. unload
-- ============================================================
_G.__JAKOSCRIPTS_UNLOAD = function()
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    for plr in pairs(playerESP) do clearPlayerESP(plr) end
    for _, hl in pairs(itemESP) do pcall(function() hl:Destroy() end) end
    if HAS_DRAWING then
        for _, l in pairs(tracerLines) do pcall(function() l:Remove() end) end
        if fovCircle then pcall(function() fovCircle:Remove() end) end
    end
    if lastFB then applyFullbright(false) end
    setFly(false)
    restoreCollisions()
    local hum = myHum()
    if hum then hum.WalkSpeed = 16 hum.JumpPower = 50 end
    pcall(function() blur:Destroy() end)
    pcall(function() screenGui:Destroy() end)
    _G.__JAKOSCRIPTS_UNLOAD = nil
end

-- ============================================================
-- 14. loops + boot
-- ============================================================
bind(RunService.RenderStepped:Connect(function()
    pcall(updateAimbot)
    pcall(updateDrawings)
    pcall(updateAutoShoot)
    pcall(updateKillAura)
    pcall(updateMovement)
    if State.fullbright ~= lastFB then
        applyFullbright(State.fullbright)
        lastFB = State.fullbright
    end
end))

task.spawn(function()
    while screenGui.Parent do
        pcall(updateESP)
        task.wait(0.25)
    end
end)

task.spawn(function()
    fullItemScan()
    while screenGui.Parent do
        pcall(fullItemScan)
        task.wait(2)
    end
end)

task.spawn(function()
    while screenGui.Parent do
        pcall(updateCoinFarm)
        task.wait(0.4)
    end
end)

toast(BRAND.product .. " " .. BRAND.version .. " loaded", "ok")
task.delay(0.8, function()
    toast("You are " .. string.upper(getRole(LocalPlayer)), "role")
end)

print(string.format("[%s %s · Style A] theme=%s blur=%dpx drawing=%s file=%s",
    BRAND.product, BRAND.version, CONFIG.theme, CONFIG.blur_px, tostring(HAS_DRAWING), tostring(HAS_FILE)))
