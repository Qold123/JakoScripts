--[[
    JakoScripts | MM2 — Style A "Dark Violet Glass"
    language: Luau | file: JakoScripts.lua | target: Roblox / Murder Mystery 2 (executor)
    ui: общий шелл VANTA Style A (480x360 · sidebar 150 · Combat / Visuals / Movement / Config)
        подставляется инжектором на место маркера ниже (source of truth: StyleA_shell.lua)
    font: Inter (auto-fallback Gotham) · icons: lucide target / eye / zap / settings, vector-drawn
    no emoji anywhere in the surface.

    ── brand lock ───────────────────────────────────────────────
      Название скрипта — всегда JakoScripts. Ни при каком билде не меняется:
      имя объекта в Explorer, вотермарка, тосты, print, конфиг на диске и глобалы.
      Единственный источник имени — таблица BRAND ниже.

    ── запуск ───────────────────────────────────────────────────
      инжектор, одной строкой (репозиторий приватный — токен в CFG.token бутстрапа):
        loadstring(game:HttpGet("https://raw.githubusercontent.com/JakoScripts/JakoScripts/main/JakoScripts_loader.lua"))()
      локально, если файл лежит в workspace экзекутора:
        loadstring(readfile("JakoScripts.lua"))()

    ── design lock (та же палитра, что и в шелле) ───────────────
      surface   #06060B
      glass     white 6-10% + blur 28px
      border    1px #FFFFFF1C   highlight #FFFFFF22
      accent    #7C3AED         icons #A78BFA
      text      #FFFFFF / #A1A1AA / #71717A
      action    #FFFFFF on #09090B
      row       #FFFFFF08 / border #FFFFFF0F / radius 12
      switch    ON #7C3AED   OFF #FFFFFF1E
      slider    track #FFFFFF15  fill #7C3AED -> #C4B5FD

    ── logic carried over from v2 / v3 (all fixes kept) ─────────
      1. murderer targets sheriff too               isEnemy()
      2. Highlight DepthMode.AlwaysOnTop            visible through walls
      3. item esp: cache + DescendantAdded + 2s sweep, no per-frame GetDescendants
      4. aim: lerp + FOV + wallcheck + closest-to-crosshair, no camera snap
      5. noclip restores collisions on toggle off / unload
      6. speed & jump re-apply on CharacterAdded
      7. executor without Drawing no longer errors   HAS_DRAWING guard
      8. full unload wipes highlights, drawings, gui, lighting
      9. role notify, coin magnet, fly, tp-to-gun, fullbright with full restore
     10. camera read dynamically — never cached across respawns
     11. Style A shell inlined by marker; sidebar nav, rebindable toggle key,
         panel opacity + acrylic toggle, save / load / reset profile, watermark + toasts
     12. _G.VANTA_THEME / _G.VANTA_WINDUI / _G.JakoScripts exported для остальных лоадеров
    ── new in v4 ────────────────────────────────────────────────
     13. skeleton ESP (Drawing line pool, R6/R15 fallback, role colors)
     14. offscreen arrows (Drawing triangle, edge-of-screen pointer)
     15. weapon name in the tag + health bar inside the BillboardGui
     16. murderer proximity warning -> UI:Toast("warn") + warn-colored status pill
     17. coins / alive counter in the status pill
     18. anti-AFK via LocalPlayer.Idled -> VirtualUser
     19. teleport to murderer button
     20. silent aim through hookmetamethod("__namecall"), camera mode as fallback
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

-- forward declarations (колбэки вкладок собираются раньше, чем секция логики)
-- заглушки — no-op: реальные тела объявляются в секции логики,
-- а сами имена уже видны колбэкам вкладок, собранным раньше.
local myChar, myHRP, myHum = nil, nil, nil
local saveConfig = nil
local loadConfig = nil
local installSilentHook = function() return false end
local teleportToMurderer = function() end
local resetDefaults = function() end
local teleportToGun = function() end

-- ── brand lock ───────────────────────────────────────────────
-- имя скрипта фиксировано: JakoScripts. правится только здесь.
local BRAND = {
    name     = "JakoScripts",
    mark     = "JAKO",
    wordmark = "SCRIPTS",
    product  = "JakoScripts | MM2",
    version  = "v4.0",
    style    = "VANTA Style A · Dark Violet Glass",
    tag      = "— JAKO SCRIPTS",
}
_G.JakoScripts = BRAND

-- ============================================================
-- 1. config descriptor + exported theme
-- ============================================================
local VANTA_WINDUI = {
    Transparent       = true,
    TransparencyValue = 0.12,
    Theme             = "VantaViolet",
    Acrylic           = true,
    AcrylicBlurAmount = 28,
}
_G.VANTA_WINDUI = VANTA_WINDUI

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
    -- combat / aimbot
    aimbot         = true,
    aim_hold       = true,
    aim_wallcheck  = true,
    aim_fov        = 150,
    aim_smooth     = 25,
    aim_part       = "Head",
    -- combat / silent
    silent_aim     = false,
    silent_method  = "namecall",
    -- combat / auto
    autoshoot      = false,
    auto_equip     = true,
    killaura       = false,
    killaura_range = 10,
    -- combat / warning
    warn_near      = true,
    warn_dist      = 120,
    -- visuals / players
    esp_murderer   = true,
    esp_sheriff    = true,
    esp_innocent   = false,
    esp_names      = true,
    esp_distance   = true,
    esp_health     = true,
    esp_weapon     = true,
    esp_healthbar  = true,
    esp_chams      = true,
    tracers        = false,
    esp_skeleton   = false,
    esp_arrows     = false,
    fov_ring       = true,
    -- visuals / items
    esp_items      = true,
    esp_coins      = true,
    esp_gun        = true,
    -- visuals / world
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
    antiafk        = true,
    -- interface
    ui_alpha       = 0.08,
    ui_blur        = true,
    ui_watermark   = true,
    ui_toasts      = true,
    ui_key         = CONFIG.toggle_key,
}

local DEFAULTS = {}
for k, v in pairs(State) do DEFAULTS[k] = v end

local Connections = {}
local function bind(c) Connections[#Connections + 1] = c; return c end

-- ============================================================
-- 3. role palette + fwd decls used by the shell wiring
--    (весь остальной UI-код живёт в шелле — см. маркер ниже)
-- ============================================================
local WHITE    = Color3.fromRGB(255, 255, 255)
local ACCENT   = Color3.fromRGB(124, 58, 237)
local ACCENT_H = Color3.fromRGB(196, 181, 253)

local ROLE_COLOR = {
    Murderer = Color3.fromRGB(255, 77, 94),
    Sheriff  = Color3.fromRGB(77, 141, 255),
    Innocent = Color3.fromRGB(52, 211, 153),
}

-- живой статус из пилюли шелла; до инициализации UI — no-op
local statApply = function() end

-- ============================================================
-- 4. VANTA Style A shell — общий блок, вшивается инжектором на маркер
-- ============================================================
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
    title    = "MM2",
    subtitle = "murder mystery 2",
    version  = "v4.0",
})

local setStat = UI:Stat("You: —")
statApply = function(text, color)
    local ok = pcall(function()
        if setStat then setStat(text, color) end
    end)
    if not ok then return end
end

-- ============================================================
-- 5. tabs — Combat / Visuals / Movement / Config
-- ============================================================
-- Combat
local tabCombat = UI:Tab("Combat", "target")
tabCombat:Section("aimbot")
tabCombat:Toggle("Aimbot", "aimbot", true)
tabCombat:Toggle("Hold RMB only", "aim_hold", true)
tabCombat:Toggle("Visibility check", "aim_wallcheck", true)
tabCombat:Slider("FOV", "aim_fov", 40, 500, "px")
tabCombat:Slider("Smooth", "aim_smooth", 1, 100, "%")
tabCombat:Cycle("Aim part", "aim_part", { "Head", "HumanoidRootPart", "Torso" })
tabCombat:Section("silent")
tabCombat:Toggle("Silent aim", "silent_aim", false, function(on)
    if on then
        local ok = installSilentHook()
        if not ok then
            State.silent_method = "camera"
            statApply("silent: camera fallback", ROLE_COLOR.Murderer)
            UI:Toast("No hookmetamethod — camera mode", "warn")
        else
            UI:Toast("Silent aim: " .. tostring(State.silent_method), "ok")
        end
    end
end)
tabCombat:Cycle("Method", "silent_method", { "namecall", "camera" }, function(v)
    if v == "namecall" and State.silent_aim then
        if not installSilentHook() then
            statApply("silent: camera fallback", ROLE_COLOR.Murderer)
            UI:Toast("No hookmetamethod — camera mode", "warn")
        end
    end
end)
tabCombat:Info("namecall подменяет цель Raycast и не двигает камеру; camera — запасной камерный лок, если хука нет.")
tabCombat:Section("auto")
tabCombat:Toggle("Auto shoot", "autoshoot", false)
tabCombat:Toggle("Auto equip tool", "auto_equip", true)
tabCombat:Toggle("Kill aura", "killaura", false)
tabCombat:Slider("Aura range", "killaura_range", 4, 25, "m")
tabCombat:Section("warning")
tabCombat:Toggle("Murderer proximity warning", "warn_near", true)
tabCombat:Slider("Warn distance", "warn_dist", 50, 500, " st")

-- Visuals
local tabVisuals = UI:Tab("Visuals", "eye")
tabVisuals:Section("players")
tabVisuals:Toggle("ESP murderer", "esp_murderer", true)
tabVisuals:Toggle("ESP sheriff", "esp_sheriff", true)
tabVisuals:Toggle("ESP innocent", "esp_innocent", false)
tabVisuals:Toggle("Names + role", "esp_names", true)
tabVisuals:Toggle("Distance", "esp_distance", true)
tabVisuals:Toggle("Health", "esp_health", true)
tabVisuals:Toggle("Weapon", "esp_weapon", true)
tabVisuals:Toggle("Health bar", "esp_healthbar", true)
tabVisuals:Toggle("Chams", "esp_chams", true)
tabVisuals:Toggle("Tracers", "tracers", false)
tabVisuals:Toggle("Skeleton", "esp_skeleton", false)
tabVisuals:Toggle("Offscreen arrows", "esp_arrows", false)
tabVisuals:Toggle("FOV ring", "fov_ring", true)
tabVisuals:Section("items")
tabVisuals:Toggle("Item ESP", "esp_items", true)
tabVisuals:Toggle("Coins", "esp_coins", true)
tabVisuals:Toggle("Dropped gun", "esp_gun", true)
tabVisuals:Section("world")
tabVisuals:Toggle("Fullbright", "fullbright", false)

-- Movement
local tabMovement = UI:Tab("Movement", "zap")
tabMovement:Section("speed")
tabMovement:Toggle("Speed hack", "speed")
tabMovement:Slider("Walk speed", "speed_value", 16, 150, "")
tabMovement:Toggle("Higher jump", "jump")
tabMovement:Slider("Jump power", "jump_value", 50, 250, "")
tabMovement:Toggle("Noclip", "noclip")
tabMovement:Toggle("Infinite jump", "infjump")
tabMovement:Section("flight")
tabMovement:Toggle("Fly", "fly")
tabMovement:Slider("Fly speed", "fly_speed", 20, 200, "")
tabMovement:Section("farm")
tabMovement:Toggle("Coin magnet", "coinFarm")
tabMovement:Toggle("Anti-AFK", "antiafk", true)
tabMovement:Button("Teleport to gun", "ghost", function() teleportToGun() end)
tabMovement:Button("Teleport to murderer", "ghost", function() teleportToMurderer() end)

-- Config
local tabConfig = UI:Tab("Config", "settings")
tabConfig:Section("interface")
tabConfig:Keybind("Toggle key", "ui_key")
tabConfig:Slider("Panel opacity", "ui_alpha", 0, 0.6, "", function(v)
    UI.window.BackgroundTransparency = v
end, function(v)
    return tostring(math.floor(v * 100 + 0.5)) .. "%"
end)
tabConfig:Toggle("Acrylic blur", "ui_blur", true, function(v)
    UI.blur.Enabled = v
end)
tabConfig:Toggle("Watermark", "ui_watermark", true, function(v)
    UI.watermark.Visible = v
end)
tabConfig:Toggle("Notifications", "ui_toasts", true)
tabConfig:Section("profile")
tabConfig:Button("Save config", "solid", function() saveConfig() end)
tabConfig:Button("Load config", "ghost", function() loadConfig() end)
tabConfig:Button("Reset defaults", "ghost", function() resetDefaults() end)
tabConfig:Section("session")
tabConfig:Button("Unload " .. BRAND.name, "ghost", function()
    if _G.__JAKOSCRIPTS_UNLOAD then _G.__JAKOSCRIPTS_UNLOAD() end
end)

-- применяем сохранённое состояние к шеллу (шелл стартует с alpha 0.08 / blur on / wm on)
pcall(function()
    UI.window.BackgroundTransparency = State.ui_alpha
    UI.blur.Enabled = State.ui_blur
    UI.watermark.Visible = State.ui_watermark
end)

-- ============================================================
-- 6. game logic
-- ============================================================
local RUNNING = true

-- ---------- role detection ----------
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

local function tagLabel(parent, text, size, color, weight)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text or ""
    l.TextSize = size or 12
    l.TextColor3 = color or WHITE
    l.TextXAlignment = Enum.TextXAlignment.Center
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.TextStrokeTransparency = 0.3
    l.Parent = parent
    applyFont(l, weight or "reg")
    return l
end

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

local function myChar() return LocalPlayer.Character end
local function myHRP()
    local c = myChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function myHum()
    local c = myChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function roleColor(role)
    return ROLE_COLOR[role] or ROLE_COLOR.Innocent
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

-- ---------- alive counters / status pill ----------
local coinsNow, aliveNow = 0, 0
local warnUntil = 0
local lastRoles = {}
local lastStat = ""

local function refreshStat(force)
    local mine = getRole(LocalPlayer)
    local text = "You: " .. mine .. " · coins " .. coinsNow .. " · alive " .. aliveNow
    local color = roleColor(mine)
    if warnUntil > os.clock() then color = ROLE_COLOR.Murderer end
    if force or text ~= lastStat then
        lastStat = text
        statApply(text, color)
    end
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

local function heldToolName(char)
    if not char then return nil end
    local tool = char:FindFirstChildOfClass("Tool")
    return tool and tool.Name or nil
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
                    hl.OutlineColor = WHITE
                    hl.FillTransparency = 0.55
                    hl.OutlineTransparency = 0
                    pcall(function() hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop end)
                    hl.Adornee = char
                    hl.Parent = char
                    e.hl = hl

                    local bill = Instance.new("BillboardGui")
                    bill.Name = "JSTag"
                    bill.Size = UDim2.new(0, 170, 0, 62)
                    bill.StudsOffset = Vector3.new(0, 2.6, 0)
                    bill.AlwaysOnTop = true
                    bill.LightInfluence = 0
                    bill.MaxDistance = 1000
                    bill.Adornee = head
                    bill.Parent = char

                    local nameL = tagLabel(bill, "", 13, color, "semi")
                    nameL.Size = UDim2.new(1, 0, 0, 18)
                    nameL.Position = UDim2.new(0, 0, 0, 0)

                    local distL = tagLabel(bill, "", 11, WHITE, "reg")
                    distL.Size = UDim2.new(1, 0, 0, 14)
                    distL.Position = UDim2.new(0, 0, 0, 18)

                    local toolL = tagLabel(bill, "", 10, ACCENT_H, "med")
                    toolL.Size = UDim2.new(1, 0, 0, 12)
                    toolL.Position = UDim2.new(0, 0, 0, 32)

                    -- health bar: фон + заливка, ширина фиксирована, HP в процентах
                    local barBg = Instance.new("Frame")
                    barBg.Name = "HPBack"
                    barBg.BackgroundColor3 = WHITE
                    barBg.BackgroundTransparency = 0.86
                    barBg.BorderSizePixel = 0
                    barBg.Size = UDim2.new(0, 120, 0, 4)
                    barBg.Position = UDim2.new(0.5, -60, 0, 48)
                    barBg.Parent = bill
                    local bgc = Instance.new("UICorner")
                    bgc.CornerRadius = UDim.new(1, 0)
                    bgc.Parent = barBg

                    local barFill = Instance.new("Frame")
                    barFill.Name = "HPFill"
                    barFill.BackgroundColor3 = color
                    barFill.BorderSizePixel = 0
                    barFill.Size = UDim2.new(1, 0, 1, 0)
                    barFill.Parent = barBg
                    local fgc = Instance.new("UICorner")
                    fgc.CornerRadius = UDim.new(1, 0)
                    fgc.Parent = barFill

                    e.bill, e.nameL, e.distL, e.toolL = bill, nameL, distL, toolL
                    e.barBg, e.barFill = barBg, barFill
                    playerESP[plr] = e
                end

                if e.hl then
                    e.hl.FillColor = color
                    e.hl.Enabled = State.esp_chams and true or false
                    if e.hl.Adornee ~= char then e.hl.Adornee = char end
                end
                if e.bill then
                    if e.bill.Adornee ~= head then e.bill.Adornee = head end
                    e.bill.Enabled = State.esp_names or State.esp_distance or State.esp_health
                        or State.esp_weapon or State.esp_healthbar
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

                    local tool = heldToolName(char)
                    e.toolL.Visible = State.esp_weapon and tool ~= nil
                    e.toolL.Text = tool or ""

                    local hp = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
                    e.barBg.Visible = State.esp_healthbar
                    e.barFill.Visible = State.esp_healthbar
                    e.barFill.Size = UDim2.new(hp, 0, 1, 0)
                    e.barFill.BackgroundColor3 = Color3.fromRGB(
                        math.floor(255 * (1 - hp) + 52 * hp),
                        math.floor(77 * (1 - hp) + 211 * hp),
                        math.floor(94 * (1 - hp) + 153 * hp))
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
    if State.esp_coins and n == "Coin" then return ACCENT_H end
    if State.esp_gun and (n == "GunDrop" or n == "Gun") then return ROLE_COLOR.Sheriff end
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
    hl.OutlineColor = WHITE
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
    coinsNow = 0
    if not State.esp_items then
        for o, hl in pairs(itemESP) do pcall(function() hl:Destroy() end); itemESP[o] = nil end
        return
    end
    local found = {}
    for _, o in ipairs(Workspace:GetDescendants()) do
        local color = itemOK(o)
        if color then
            found[o] = true
            if o.Name == "Coin" then coinsNow = coinsNow + 1 end
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

-- ---------- drawing pools: fov ring / tracers / skeleton / arrows ----------
local tracerLines, boneESP, arrowESP = {}, {}, {}
local bonePool, arrowPool = {}, {}
local fovCircle = nil

if HAS_DRAWING then
    pcall(function()
        fovCircle = Drawing.new("Circle")
        fovCircle.Thickness = 1
        fovCircle.NumSides = 64
        fovCircle.Filled = false
        fovCircle.Transparency = 0.55
        fovCircle.Color = ACCENT
        fovCircle.Visible = false
    end)
end

local function hideTracer(plr)
    local line = tracerLines[plr]
    if line then pcall(function() line.Visible = false end) end
end

local function hideBones(plr)
    local binfo = boneESP[plr]
    if not binfo then return end
    -- список может быть «дырявым» (nil в середине), поэтому не ipairs
    for i = 1, #binfo do
        local obj = binfo[i]
        if obj then
            pcall(function() obj.Visible = false end)
            bonePool[#bonePool + 1] = obj
        end
    end
    boneESP[plr] = nil
end

local function hideArrow(plr)
    local a = arrowESP[plr]
    if a then
        pcall(function() a.Visible = false end)
        arrowPool[#arrowPool + 1] = a
        arrowESP[plr] = nil
    end
end

local function hideRecord(plr)
    hideTracer(plr)
    hideBones(plr)
    hideArrow(plr)
end

-- ---------- skeleton rig (R15 -> R6 fallback, никаких Instance) ----------
local SKELETON_BONES = {
    { "Head", "UpperTorso" },
    { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" },
    { "LeftUpperArm", "LeftLowerArm" },
    { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" },
    { "RightUpperArm", "RightLowerArm" },
    { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" },
    { "LeftUpperLeg", "LeftLowerLeg" },
    { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" },
    { "RightUpperLeg", "RightLowerLeg" },
    { "RightLowerLeg", "RightFoot" },
}

local SKELETON_BONES_R6 = {
    { "Head", "Torso" },
    { "Torso", "Left Arm" },
    { "Torso", "Right Arm" },
    { "Torso", "Left Leg" },
    { "Torso", "Right Leg" },
    { "Left Arm", "Left Arm" },
    { "Right Arm", "Right Arm" },
    { "Left Leg", "Left Leg" },
    { "Right Leg", "Right Leg" },
}

local function rigInfo(char)
    if not char then return nil end
    local head = char:FindFirstChild("Head")
    local upper = char:FindFirstChild("UpperTorso")
    if head and upper then
        return { head = head, upper = upper, lower = char:FindFirstChild("LowerTorso"), bones = SKELETON_BONES }
    end
    local torso = char:FindFirstChild("Torso")
    if head and torso then
        return { head = head, upper = torso, lower = nil, bones = SKELETON_BONES_R6 }
    end
    return nil
end

local function showBones(plr, info, c, color)
    local list = boneESP[plr]
    if not list then list = {} boneESP[plr] = list end
    for i, bone in ipairs(info.bones) do
        local a = info.head.Parent and info.head.Parent:FindFirstChild(bone[1])
        local b = info.head.Parent and info.head.Parent:FindFirstChild(bone[2])
        local line = list[i]
        if a and b then
            local p1, on1 = c:WorldToViewportPoint(a.Position)
            local p2, on2 = c:WorldToViewportPoint(b.Position)
            if on1 and on2 then
                if not line then
                    line = table.remove(bonePool)
                    if not line then
                        line = Drawing.new("Line")
                        line.Thickness = 1.2
                        line.Transparency = 0.85
                    end
                    list[i] = line
                end
                line.Color = color
                line.From = Vector2.new(p1.X, p1.Y)
                line.To = Vector2.new(p2.X, p2.Y)
                line.Visible = true
            elseif line then
                line.Visible = false
            end
        elseif line then
            line.Visible = false
        end
    end
end

local function updateSkeleton(c)
    if not HAS_DRAWING then return end
    if not State.esp_skeleton then
        for plr in pairs(boneESP) do hideBones(plr) end
        return
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        local info = nil
        local color = WHITE
        if plr ~= LocalPlayer and isAlive(plr) then
            local role = getRole(plr)
            if shouldShow(plr, role) then
                info = rigInfo(plr.Character)
                color = roleColor(role)
            end
        end
        if info then
            showBones(plr, info, c, color)
        else
            hideBones(plr)
        end
    end
    for plr in pairs(boneESP) do
        if not plr.Parent then hideBones(plr) end
    end
end

-- ---------- offscreen arrows ----------
local function updateArrows(c, vs, cx, cy)
    if not HAS_DRAWING then return end
    if not State.esp_arrows then
        for plr in pairs(arrowESP) do hideArrow(plr) end
        return
    end
    local radius = 0.42 * math.min(vs.X, vs.Y)
    for _, plr in ipairs(Players:GetPlayers()) do
        local show, dx, dy, color = false, 0, 0, WHITE
        if plr ~= LocalPlayer and isAlive(plr) then
            local char = plr.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local role = getRole(plr)
            if hrp and shouldShow(plr, role) then
                local sp, onScr = c:WorldToViewportPoint(hrp.Position)
                if not onScr then
                    -- цель вне вьюпорта: направление берём из проекции, при нуле — из мировой позиции
                    local px, py = sp.X, sp.Y
                    if px == 0 and py == 0 then
                        local rel = c.CFrame:PointToObjectSpace(hrp.Position)
                        px, py = -rel.X, -rel.Y
                    end
                    dx, dy = px - cx, py - cy
                    local m = math.sqrt(dx * dx + dy * dy)
                    if m < 1e-3 then dx, dy = 0, -1 else dx, dy = dx / m, dy / m end
                    show = true
                    color = roleColor(role)
                end
            end
        end
        local tri = arrowESP[plr]
        if show then
            if not tri then
                tri = table.remove(arrowPool)
                if not tri then
                    tri = Drawing.new("Triangle")
                    tri.Filled = true
                    tri.Thickness = 1
                    tri.Transparency = 0.9
                end
                arrowESP[plr] = tri
            end
            local ax, ay = cx + dx * radius, cy + dy * radius
            local px, py = -dy, dx
            tri.Color = color
            tri.PointA = Vector2.new(ax + dx * 11, ay + dy * 11)
            tri.PointB = Vector2.new(ax + px * 7 - dx * 5, ay + py * 7 - dy * 5)
            tri.PointC = Vector2.new(ax - px * 7 - dx * 5, ay - py * 7 - dy * 5)
            tri.Visible = true
        elseif tri then
            hideArrow(plr)
        end
    end
    for plr in pairs(arrowESP) do
        if not plr.Parent then hideArrow(plr) end
    end
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
        fovCircle.Visible = State.fov_ring == true and State.aimbot == true
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        local line = tracerLines[plr]
        local show, targetPos = false, nil
        local color = WHITE
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
    updateSkeleton(c)
    updateArrows(c, vs, cx, cy)
end

-- ---------- silent aim (namecall hook, по образцу deagle) ----------
local silentTarget, silentDist, silentPart = nil, 0, nil
local silentHookOK, silentHooked = false, false
local silentRayParams = RaycastParams.new()
pcall(function()
    silentRayParams.FilterType = Enum.RaycastFilterType.Exclude or Enum.RaycastFilterType.Blacklist
end)
silentRayParams.IgnoreWater = true
silentRayParams.FilterDescendantsInstances = {}

local function refreshSilentFilter()
    local list = { myChar(), cam() }
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character then list[#list + 1] = plr.Character end
    end
    silentRayParams.FilterDescendantsInstances = list
end

installSilentHook = function()
    if silentHooked then return silentHookOK end
    if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
        silentHookOK = false
        return false
    end
    local ok = pcall(function()
        local old = nil
        old = hookmetamethod(game, "__namecall", function(self, ...)
            if State.silent_aim and State.silent_method == "namecall"
                and getnamecallmethod() == "Raycast" and self == Workspace then
                local t = silentTarget
                if t and t.Parent then
                    local args = { ... }
                    if typeof(args[1]) == "Vector3" and typeof(args[2]) == "Vector3" and args[2].Magnitude > 1 then
                        local origin = args[1]
                        -- сохраняем длину луча, меняем только направление на цель
                        args[2] = (t.Position - origin).Unit * args[2].Magnitude
                        local ok2 = pcall(function() refreshSilentFilter() end)
                        if ok2 then args[3] = silentRayParams end
                        return old(self, table.unpack(args))
                    end
                end
            end
            return old(self, ...)
        end)
    end)
    silentHooked = true
    silentHookOK = ok
    return ok
end

local function updateSilentTarget()
    silentTarget, silentDist, silentPart = nil, 0, nil
    if not State.silent_aim then return end
    local c = cam()
    local myHrp = myHRP()
    if not c or not myHrp then return end
    local vs = c.ViewportSize
    local cx, cy = vs.X / 2, vs.Y / 2
    local best, bestD, bestPart = nil, State.aim_fov, nil
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and isAlive(plr) and isEnemy(plr) then
            local char = plr.Character
            local part = char and (char:FindFirstChild(State.aim_part) or char:FindFirstChild("Head"))
            if part then
                local sp, onScr = c:WorldToViewportPoint(part.Position)
                if onScr then
                    local d2 = Vector2.new(sp.X - cx, sp.Y - cy).Magnitude
                    if d2 < bestD and isVisible(c.CFrame.Position, part.Position, char) then
                        best, bestD, bestPart = plr, d2, part
                    end
                end
            end
        end
    end
    if best and bestPart then
        silentTarget = bestPart
        silentPart = bestPart
        silentDist = (myHrp.Position - bestPart.Position).Magnitude
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
    if State.silent_aim and State.silent_method == "camera" then
        -- камерный запасной режим: ведём камеру на кэш сайлента
        local t = silentTarget
        local c = cam()
        if t and t.Parent and c then
            local k = math.clamp(State.aim_smooth / 100, 0.02, 1)
            c.CFrame = c.CFrame:Lerp(CFrame.new(c.CFrame.Position, t.Position), k)
        end
        return
    end
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
    local okTarget = getAimTarget() and aimPart ~= nil
    if not okTarget and silentTarget and silentTarget.Parent then okTarget = true end
    if okTarget then
        local now = os.clock()
        if now - lastShoot > 0.25 then
            lastShoot = now
            local part = aimPart or silentTarget
            local c = cam()
            -- в режиме namecall камеру не трогаем: цель подменяет хук
            if c and part and not (State.silent_aim and State.silent_method == "namecall") then
                c.CFrame = CFrame.new(c.CFrame.Position, part.Position)
            end
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

-- ---------- murderer proximity warning ----------
local warnCD = {}
local function updateWarn()
    if not State.warn_near then return end
    local hrp = myHRP()
    if not hrp then return end
    local now = os.clock()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and isAlive(plr) and getRole(plr) == "Murderer" then
            local thrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
            if thrp then
                local d = (hrp.Position - thrp.Position).Magnitude
                if d <= State.warn_dist then
                    local last = warnCD[plr] or 0
                    if now - last > 5 then
                        warnCD[plr] = now
                        warnUntil = now + 1.5
                        UI:Toast("Murderer " .. tostring(math.floor(d + 0.5)) .. " st", "warn")
                        refreshStat(true)
                    end
                end
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

-- anti-AFK: VirtualUser жмёт кнопку, клиент не выкидывает за простой
bind(LocalPlayer.Idled:Connect(function()
    if not State.antiafk then return end
    pcall(function()
        local vu = game:GetService("VirtualUser")
        vu:Button2Down(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
        task.wait(1)
        vu:Button2Up(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
    end)
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

-- ---------- teleports ----------
teleportToGun = function()
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
        UI:Toast("Teleported to gun", "ok")
    else
        UI:Toast("Gun not found", "warn")
    end
end

local function findMurderer()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and isAlive(plr) and getRole(plr) == "Murderer" then return plr end
    end
    return nil
end

teleportToMurderer = function()
    local target = findMurderer()
    local hrp = myHRP()
    local thrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    if target and hrp and thrp then
        hrp.CFrame = CFrame.new(thrp.Position + Vector3.new(0, 4, 0))
        UI:Toast("Teleported to " .. tostring(target.DisplayName), "ok")
    else
        UI:Toast("Murderer not found", "warn")
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

-- ---------- role watch (status pill + role toasts) ----------
task.spawn(function()
    while RUNNING do
        pcall(function()
            local aliveN = 1
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    if isAlive(plr) then aliveN = aliveN + 1 end
                    local r = getRole(plr)
                    if lastRoles[plr] ~= r and (r == "Murderer" or r == "Sheriff") then
                        UI:Toast(plr.DisplayName .. " — " .. string.upper(r), nil)
                    end
                    lastRoles[plr] = r
                end
            end
            aliveNow = aliveN
            refreshStat(false)
        end)
        task.wait(1)
    end
end)

-- ============================================================
-- 7. config io
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

-- применяем состояние к шеллу одним местом (reset / load / init)
local function applyUiState()
    pcall(function()
        UI.window.BackgroundTransparency = State.ui_alpha
        UI.blur.Enabled = State.ui_blur
        UI.watermark.Visible = State.ui_watermark
    end)
end

local function refreshRows()
    for _, r in pairs(UI.rows) do
        if r and r.Refresh then pcall(r.Refresh) end
    end
end

local function saveConfig()
    if not HAS_FILE then UI:Toast("Executor has no writefile", "warn") return end
    local ok = pcall(function() writefile(CONFIG.config_file, serialize()) end)
    UI:Toast(ok and "Config saved" or "Save failed", ok and "ok" or "warn")
end

local function loadConfig()
    if not HAS_FILE then UI:Toast("Executor has no readfile", "warn") return end
    local ok, data = pcall(function() return readfile(CONFIG.config_file) end)
    if not ok or not data then UI:Toast("No config on disk", "warn") return end
    local dec
    if HttpService then
        local ok2, d = pcall(function() return HttpService:JSONDecode(data) end)
        if ok2 then dec = d end
    end
    if type(dec) ~= "table" then UI:Toast("Config unreadable", "warn") return end
    for k, v in pairs(dec) do
        if k == "ui_key" and type(v) == "string" then
            local kc = Enum.KeyCode[v]
            if kc then State.ui_key = kc end
        elseif DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) then
            State[k] = v
        end
    end
    applyUiState()
    refreshRows()
    UI:Toast("Config loaded", "ok")
end

local function resetDefaults()
    for k, v in pairs(DEFAULTS) do State[k] = v end
    applyUiState()
    refreshRows()
    UI:Toast("Defaults restored", "ok")
end

-- ============================================================
-- 8. unload
-- ============================================================
local function teardownDrawings()
    if not HAS_DRAWING then return end
    for plr, line in pairs(tracerLines) do pcall(function() line:Remove() end) tracerLines[plr] = nil end
    for plr in pairs(boneESP) do
        local list = boneESP[plr]
        for i = 1, #list do
            local obj = list[i]
            if obj then pcall(function() obj:Remove() end) end
        end
        boneESP[plr] = nil
    end
    for plr, tri in pairs(arrowESP) do pcall(function() tri:Remove() end) arrowESP[plr] = nil end
    for i = #bonePool, 1, -1 do pcall(function() bonePool[i]:Remove() end) bonePool[i] = nil end
    for i = #arrowPool, 1, -1 do pcall(function() arrowPool[i]:Remove() end) arrowPool[i] = nil end
    if fovCircle then pcall(function() fovCircle:Remove() end) fovCircle = nil end
end

_G.__JAKOSCRIPTS_UNLOAD = function()
    RUNNING = false
    State.silent_aim = false
    State.aimbot = false
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    for plr in pairs(playerESP) do clearPlayerESP(plr) end
    for o, hl in pairs(itemESP) do pcall(function() hl:Destroy() end) itemESP[o] = nil end
    teardownDrawings()
    if lastFB then applyFullbright(false) end
    setFly(false)
    restoreCollisions()
    local hum = myHum()
    if hum then hum.WalkSpeed = 16 hum.JumpPower = 50 end
    pcall(function() UI:Destroy() end)
    _G.__JAKOSCRIPTS_UNLOAD = nil
end

-- ============================================================
-- 9. loops + boot
-- ============================================================
bind(RunService.RenderStepped:Connect(function()
    pcall(updateSilentTarget)
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
    while RUNNING do
        pcall(updateESP)
        task.wait(0.25)
    end
end)

task.spawn(function()
    fullItemScan()
    while RUNNING do
        pcall(fullItemScan)
        task.wait(2)
    end
end)

task.spawn(function()
    while RUNNING do
        pcall(updateCoinFarm)
        task.wait(0.4)
    end
end)

task.spawn(function()
    while RUNNING do
        pcall(updateWarn)
        task.wait(0.5)
    end
end)

refreshStat(true)
UI:Toast(BRAND.product .. " " .. BRAND.version .. " loaded", "ok")
task.delay(0.8, function()
    UI:Toast("You are " .. string.upper(getRole(LocalPlayer)), "ok")
end)

print(string.format("[%s %s · Style A] theme=%s blur=%dpx drawing=%s file=%s",
    BRAND.product, BRAND.version, CONFIG.theme, CONFIG.blur_px, tostring(HAS_DRAWING), tostring(HAS_FILE)))
