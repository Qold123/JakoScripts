-- VANTA Pistol Arena v3 | Luau | [Ранговая] Арена пистолетов | executor
-- language: Luau (Roblox) | file: VANTA_PistolArena.lua | runtime: executor (loadstring)
-- Написано с нуля под ранкед-шутер от первого лица. Ни одного HttpGet, ни одной
-- ссылки на стороннюю библиотеку: весь интерфейс и вся логика внутри файла.
--
-- Что внутри: аимбот с доводкой МЫШЬЮ (не записью камеры), триггербот, ESP-оверлей
-- на Drawing, круг FOV, анти-AFK, авто-прыжок, клиентский FOV камеры, конфиг на диск.
--
-- Почему именно так, а не проще:
--   * наведение идёт через mousemoverel. Камера двигается так же, как от руки,
--     GetMouseDelta не ноль, игра не видит записи CFrame;
--   * ни одного hookmetamethod, ни одного warn/print: игра читает логи и вставляет
--     их текст в сообщение кика, а хук __namecall ловится отдельно;
--   * ESP живёт только в Drawing — в дерево инстансов игры не добавляется ничего;
--   * у аима есть потолок поворота за кадр, задержка реакции, джиттер и кривая
--     доводки; у триггера — рандомный такт и шанс пропуска. Ровный автомат палится
--     поведенческим анализом.
--
-- Дизайн: VANTA Style A — surface #06060B, стекло белый 6-10% + blur 28px,
-- бордер #FFFFFF1C + блик #FFFFFF22, акцент #7C3AED, иконки #A78BFA,
-- текст #FFFFFF / #A1A1AA / #71717A, роу #FFFFFF08 / #FFFFFF0F радиус 12,
-- свитч ON #7C3AED OFF #FFFFFF1E, слайдер трек #FFFFFF15 заливка #7C3AED -> #C4B5FD.
-- Шрифт Inter с откатом на Gotham, иконки lucide target / eye / zap / settings,
-- нарисованы вектором. Эмодзи нет ни одного.
--
-- Окно 480x360, сайдбар 150, вкладки Combat / Visuals / Movement / Config,
-- скрыть/показать — RightShift (переназначается в Config).
--
-- Запуск: loadstring(game:HttpGet("RAW_URL"))()
--
-- Структура: все функции объявлены до первого использования, forward-declared
-- локалов нет — если сверху появится гейт по ключу, обфускатор ничего не потеряет.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local VirtualUser = game:GetService("VirtualUser")

-- Экзекьютор иногда стартует раньше, чем клиенту отдают LocalPlayer. Без него
-- строить нечего; повторный запуск после загрузки отработает штатно.
if not LocalPlayer then return end

-- Экзекьюторские функции читаем как значения, а не вызываем по имени: чего нет в
-- сборке экзекьютора, то становится пустышкой, и скрипт не падает посреди боя.
local move_mouse = mousemoverel or function() end
local click_mouse = mouse1click or function() end
local GENV = (getgenv or function() return _G end)()

-- ===== STATE =====
-- Ключи только те, что привязаны к строке интерфейса или переживают перезапуск.
-- Рантайм-переменные (текущая цель, накопитель хода мыши) живут в локалах ниже.
local State = {
    aimbot = true,
    aim_key = Enum.KeyCode.E,
    aim_hold = true,
    aim_part = "Head",
    aim_fov = 140,
    aim_speed = 22,
    aim_curve = "EaseOut",
    aim_maxstep = 5,
    aim_reaction = 130,
    aim_jitter = 0.7,
    aim_wallcheck = true,
    aim_maxdist = 1200,
    aim_teamcheck = true,

    triggerbot = false,
    trigger_key = Enum.KeyCode.CapsLock,
    trigger_hold = false,
    trigger_range = 220,
    trigger_ms_min = 70,
    trigger_ms_max = 190,
    trigger_chance = 85,

    esp = true,
    esp_box = true,
    esp_corners = true,
    esp_name = true,
    esp_dist = true,
    esp_hp = true,
    esp_tracer = false,
    esp_maxdist = 1400,
    esp_allies = false,
    fov_circle = true,

    antiafk = true,
    autojump = false,
    cam_fov_on = false,
    cam_fov = 90,

    ui_key = Enum.KeyCode.RightShift,
    ui_watermark = true,
    ui_stats = true,
    ui_blur = true,
    ui_toasts = true,
}

local DEFAULTS = {}
for key, value in pairs(State) do DEFAULTS[key] = value end

-- =====================================================================
--  ИНТЕРФЕЙС — Style A, написан с нуля
-- =====================================================================
local VANTA_UI = (function()
    local UserInputService = game:GetService("UserInputService")
    local TweenService = game:GetService("TweenService")
    local Lighting = game:GetService("Lighting")
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local LocalPlayer = Players.LocalPlayer

    local PALETTE = {
        surface = Color3.fromRGB(6, 6, 11),
        white = Color3.fromRGB(255, 255, 255),
        accent = Color3.fromRGB(124, 58, 237),
        accent2 = Color3.fromRGB(196, 181, 253),
        icon = Color3.fromRGB(167, 139, 250),
        text = Color3.fromRGB(255, 255, 255),
        muted = Color3.fromRGB(161, 161, 170),
        dim = Color3.fromRGB(113, 113, 122),
        onaccent = Color3.fromRGB(9, 9, 11),
        warn = Color3.fromRGB(255, 77, 94),
        good = Color3.fromRGB(52, 211, 153),
    }

    -- Прозрачности, выведенные из палитры: #FFFFFF08 -> 0.969, #FFFFFF1C -> 0.890,
    -- #FFFFFF22 -> 0.867, #FFFFFF1E -> 0.882, #FFFFFF15 -> 0.918.
    local ALPHA = {
        glass6 = 0.94,
        glass8 = 0.92,
        row = 0.969,
        row_line = 0.941,
        stroke = 0.890,
        hilite = 0.867,
        sw_off = 0.882,
        track = 0.918,
    }

    local WINDOW = Vector2.new(480, 360)
    local SIDEBAR = 150
    local RADIUS = 12
    local BLUR = 28
    local GAP = 8

    local function inst(class, parent)
        local obj = Instance.new(class)
        if parent then obj.Parent = parent end
        return obj
    end

    local function round(obj, radius)
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, radius or RADIUS)
        corner.Parent = obj
        return corner
    end

    local function circle(obj)
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = obj
        return corner
    end

    local function outline(obj, color, thickness, transparency)
        local line = Instance.new("UIStroke")
        line.Color = color or PALETTE.white
        line.Thickness = thickness or 1
        line.Transparency = transparency or ALPHA.stroke
        pcall(function() line.LineJoinMode = Enum.LineJoinMode.Round end)
        line.Parent = obj
        return line
    end

    local function glide(obj, props, seconds)
        TweenService:Create(
            obj,
            TweenInfo.new(seconds or 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            props
        ):Play()
    end

    local FONT_OK, F_REG, F_MED, F_SEMI = false, nil, nil, nil
    do
        local ok, a, b, c = pcall(function()
            return Font.fromName("Inter", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
                Font.fromName("Inter", Enum.FontWeight.Medium, Enum.FontStyle.Normal),
                Font.fromName("Inter", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)
        end)
        if ok and a then FONT_OK, F_REG, F_MED, F_SEMI = true, a, b, c end
    end
    local FALLBACK = {
        reg = Enum.Font.Gotham,
        med = Enum.Font.GothamMedium,
        semi = Enum.Font.GothamBold,
    }

    local function label(parent, content, size, color, weight)
        local text = inst("TextLabel", parent)
        text.BackgroundTransparency = 1
        text.Text = content or ""
        text.TextSize = size or 12
        text.TextColor3 = color or PALETTE.text
        text.TextXAlignment = Enum.TextXAlignment.Left
        text.TextYAlignment = Enum.TextYAlignment.Center
        -- Авто-локализация гонит каждую строку через CoreGui Locales и под
        -- экзекьютором сыпет "attempt to call a nil value" в консоль.
        pcall(function() text.AutoLocalize = false end)
        local w = weight or "reg"
        if FONT_OK then
            local face = (w == "semi" and F_SEMI) or (w == "med" and F_MED) or F_REG
            if face and pcall(function() text.FontFace = face end) then return text end
        end
        text.Font = FALLBACK[w] or FALLBACK.reg
        return text
    end

    local function hit(parent)
        local btn = inst("TextButton", parent)
        btn.Text = ""
        btn.AutoButtonColor = false
        pcall(function() btn.AutoLocalize = false end)
        return btn
    end

    -- Разрядка по буквам: интервал между знаками вместо LetterSpacing, которого в
    -- TextLabel нет. Идём по код-пойнтам, а не по байтам: тире в "— VANTA"
    -- трёхбайтовое, побайтовый разбор развалил бы его на три мусорных знака.
    local function tracked(str)
        local parts = {}
        if utf8 and utf8.len and utf8.offset then
            local count = utf8.len(str)
            if count then
                for i = 1, count do
                    local from = utf8.offset(str, i)
                    local to = utf8.offset(str, i + 1)
                    parts[#parts + 1] = string.sub(str, from, (to or (#str + 1)) - 1)
                end
                return table.concat(parts, " ")
            end
        end
        for i = 1, #str do parts[#parts + 1] = string.sub(str, i, i) end
        return table.concat(parts, " ")
    end

    -- ---------- lucide-иконки, вектором: target / eye / zap / settings ----------
    local function glyph(parent, kind, size, color)
        local box = inst("Frame", parent)
        box.BackgroundTransparency = 1
        box.AnchorPoint = Vector2.new(0.5, 0.5)
        box.Size = UDim2.fromOffset(size, size)
        local c = size / 2

        local function bar(w, h, x, y, rot)
            local f = inst("Frame", box)
            f.BackgroundColor3 = color
            f.BorderSizePixel = 0
            f.AnchorPoint = Vector2.new(0.5, 0.5)
            f.Size = UDim2.fromOffset(w, h)
            f.Position = UDim2.fromOffset(x, y)
            if rot then f.Rotation = rot end
            return f
        end

        local function ring(diameter, thickness)
            local f = inst("Frame", box)
            f.BackgroundTransparency = 1
            f.AnchorPoint = Vector2.new(0.5, 0.5)
            f.Size = UDim2.fromOffset(diameter, diameter)
            f.Position = UDim2.fromOffset(c, c)
            circle(f)
            local line = Instance.new("UIStroke")
            line.Color = color
            line.Thickness = thickness
            line.Parent = f
            return f
        end

        if kind == "target" then
            ring(size - 3, 1.3)
            bar(2, 2, c, c)
            bar(1.3, 3, c, 1.6)
            bar(1.3, 3, c, size - 1.6)
            bar(3, 1.3, 1.6, c)
            bar(3, 1.3, size - 1.6, c)
        elseif kind == "eye" then
            local lens = inst("Frame", box)
            lens.BackgroundTransparency = 1
            lens.AnchorPoint = Vector2.new(0.5, 0.5)
            lens.Size = UDim2.fromOffset(size - 1, size * 0.62)
            lens.Position = UDim2.fromOffset(c, c)
            circle(lens)
            local line = Instance.new("UIStroke")
            line.Color = color
            line.Thickness = 1.25
            line.Parent = lens
            bar(3.4, 3.4, c, c)
        elseif kind == "zap" then
            bar(1.8, 5.4, c - 1.8, c - 3.4, 32)
            bar(2.2, 3.4, c - 0.2, c - 1.2, -28)
            bar(1.8, 5.4, c + 1.8, c + 3.4, 32)
            bar(2.2, 3.4, c + 0.2, c + 1.2, -28)
        else
            ring(size - 5, 1.25)
            for i = 1, 6 do
                local angle = (i - 1) * 60
                local rad = math.rad(angle)
                local px = c + math.cos(rad) * (size / 2 - 2)
                local py = c + math.sin(rad) * (size / 2 - 2)
                bar(1.6, 3, px, py, angle)
            end
            bar(2.6, 2.6, c, c)
        end
        return box
    end

    -- ---------- окно ----------
    local function screen_parent()
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then return pg end
        local ok, hidden = pcall(function() return gethui and gethui() end)
        if ok and hidden then return hidden end
        return game:GetService("CoreGui")
    end

    local function build_window(cfg)
        local old = screen_parent():FindFirstChild("VANTA_PistolArena")
        if old then pcall(function() old:Destroy() end) end
        local stale = Lighting:FindFirstChild("VANTA_Blur")
        if stale then pcall(function() stale:Destroy() end) end

        local gui = inst("ScreenGui")
        gui.Name = "VANTA_PistolArena"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
        pcall(function() gui.DisplayOrder = 999 end)
        gui.Parent = screen_parent()

        local blur = nil
        if cfg.state.ui_blur then
            blur = inst("BlurEffect", Lighting)
            blur.Name = "VANTA_Blur"
            blur.Size = BLUR
        end

        local glow = inst("Frame", gui)
        glow.BackgroundColor3 = PALETTE.accent
        glow.BackgroundTransparency = 0.94
        glow.BorderSizePixel = 0
        glow.AnchorPoint = Vector2.new(0.5, 0.5)
        glow.Position = UDim2.fromScale(0.5, 0.5)
        glow.Size = UDim2.fromOffset(WINDOW.X + 16, WINDOW.Y + 16)
        round(glow, 18)

        local win = inst("Frame", gui)
        win.BackgroundColor3 = PALETTE.surface
        win.BackgroundTransparency = 0.08
        win.BorderSizePixel = 0
        win.AnchorPoint = Vector2.new(0.5, 0.5)
        win.Position = UDim2.fromScale(0.5, 0.5)
        win.Size = UDim2.fromOffset(WINDOW.X, WINDOW.Y)
        round(win, RADIUS + 2)
        outline(win, PALETTE.white, 1, ALPHA.stroke)
        win.ClipsDescendants = true

        -- блик по верхней кромке: 1px белого на 13% внутрь от краёв
        local shine = inst("Frame", win)
        shine.BackgroundColor3 = PALETTE.white
        shine.BackgroundTransparency = ALPHA.hilite
        shine.BorderSizePixel = 0
        shine.Size = UDim2.new(1, -32, 0, 1)
        shine.Position = UDim2.new(0, 16, 0, 0)
        shine.ZIndex = 3

        local side = inst("Frame", win)
        side.BackgroundColor3 = PALETTE.white
        side.BackgroundTransparency = ALPHA.glass6
        side.BorderSizePixel = 0
        side.Size = UDim2.new(0, SIDEBAR, 1, 0)
        side.ZIndex = 2

        local seam = inst("Frame", win)
        seam.BackgroundColor3 = PALETTE.white
        seam.BackgroundTransparency = ALPHA.row_line
        seam.BorderSizePixel = 0
        seam.Size = UDim2.new(0, 1, 1, -24)
        seam.Position = UDim2.new(0, SIDEBAR, 0, 12)
        seam.ZIndex = 4

        local logo = label(side, tracked("— VANTA"), 13, PALETTE.text, "med")
        logo.Size = UDim2.new(1, -32, 0, 20)
        logo.Position = UDim2.new(0, 16, 0, 18)
        logo.ZIndex = 4

        local word = label(side, tracked("SCRIPTS"), 10, PALETTE.icon, "semi")
        word.Size = UDim2.new(1, -32, 0, 14)
        word.Position = UDim2.new(0, 16, 0, 40)
        word.ZIndex = 4

        local sub = label(side, string.upper(tostring(cfg.subtitle or "")), 9, PALETTE.dim, "med")
        sub.Size = UDim2.new(1, -32, 0, 12)
        sub.Position = UDim2.new(0, 16, 0, 58)
        sub.ZIndex = 4

        local nav = inst("Frame", side)
        nav.BackgroundTransparency = 1
        nav.Size = UDim2.new(1, -24, 0, 200)
        nav.Position = UDim2.new(0, 12, 0, 88)
        nav.ZIndex = 4
        local nav_list = inst("UIListLayout", nav)
        nav_list.Padding = UDim.new(0, 4)
        nav_list.SortOrder = Enum.SortOrder.LayoutOrder

        -- верхняя плашка контента
        local head = inst("Frame", win)
        head.BackgroundTransparency = 1
        head.Size = UDim2.new(1, -(SIDEBAR + 32), 0, 30)
        head.Position = UDim2.new(0, SIDEBAR + 16, 0, 18)
        head.ZIndex = 3
        local head_hit = hit(head)
        head_hit.BackgroundTransparency = 1
        head_hit.Size = UDim2.new(1, 0, 0, 44)
        head_hit.Position = UDim2.new(0, 0, 0, -8)
        head_hit.ZIndex = 0

        local page = label(head, "COMBAT", 13, PALETTE.text, "semi")
        page.Size = UDim2.new(0, 150, 1, 0)
        page.ZIndex = 4

        local stat = inst("Frame", head)
        stat.BackgroundColor3 = PALETTE.white
        stat.BackgroundTransparency = ALPHA.track
        stat.BorderSizePixel = 0
        stat.AnchorPoint = Vector2.new(1, 0.5)
        stat.Position = UDim2.new(1, -34, 0.5, 0)
        stat.Size = UDim2.fromOffset(140, 22)
        stat.ZIndex = 4
        round(stat, 11)
        outline(stat, PALETTE.white, 1, ALPHA.row_line)

        local dot = inst("Frame", stat)
        dot.BackgroundColor3 = PALETTE.accent
        dot.BorderSizePixel = 0
        dot.Size = UDim2.fromOffset(6, 6)
        dot.Position = UDim2.new(0, 9, 0.5, -3)
        dot.ZIndex = 5
        circle(dot)

        local stat_text = label(stat, tostring(cfg.stat or ""), 10, PALETTE.muted, "med")
        stat_text.Size = UDim2.new(1, -22, 1, 0)
        stat_text.Position = UDim2.new(0, 20, 0, 0)
        stat_text.ZIndex = 5
        stat_text.TextTruncate = Enum.TextTruncate.AtEnd

        local content = inst("Frame", win)
        content.BackgroundTransparency = 1
        content.Size = UDim2.new(1, -(SIDEBAR + 32), 1, -66)
        content.Position = UDim2.new(0, SIDEBAR + 16, 0, 52)
        content.ZIndex = 3

        -- кнопка-пилюля: показать/скрыть окно. Живёт поверх окна и не прячется
        -- вместе с ним, иначе окно не вернуть.
        local pill = inst("TextButton", gui)
        pill.Text = ""
        pill.AutoButtonColor = false
        pill.BackgroundColor3 = PALETTE.surface
        pill.BackgroundTransparency = 0.12
        pill.BorderSizePixel = 0
        pill.Size = UDim2.fromOffset(34, 34)
        pill.ZIndex = 30
        round(pill, 10)
        outline(pill, PALETTE.white, 1, ALPHA.stroke)
        local pill_glyph = glyph(pill, "target", 15, PALETTE.icon)
        pill_glyph.Position = UDim2.fromScale(0.5, 0.5)
        pill_glyph.ZIndex = 31

        local mark = inst("Frame", gui)
        mark.BackgroundColor3 = PALETTE.white
        mark.BackgroundTransparency = ALPHA.glass8
        mark.BorderSizePixel = 0
        mark.Size = UDim2.fromOffset(200, 26)
        mark.Position = UDim2.fromOffset(16, 16)
        mark.ZIndex = 20
        round(mark, 10)
        outline(mark, PALETTE.white, 1, ALPHA.row_line)
        local mark_brand = label(mark, tracked("— VANTA"), 10, PALETTE.text, "med")
        mark_brand.Size = UDim2.fromOffset(70, 26)
        mark_brand.Position = UDim2.fromOffset(12, 0)
        mark_brand.ZIndex = 21
        local mark_word = label(mark, "SCRIPTS", 10, PALETTE.icon, "semi")
        mark_word.Size = UDim2.fromOffset(48, 26)
        mark_word.Position = UDim2.fromOffset(80, 0)
        mark_word.ZIndex = 21
        local mark_title = label(mark, string.upper(tostring(cfg.title or "")), 9, PALETTE.muted, "semi")
        mark_title.Size = UDim2.fromOffset(74, 26)
        mark_title.Position = UDim2.fromOffset(114, 0)
        mark_title.TextXAlignment = Enum.TextXAlignment.Right
        mark_title.TextTruncate = Enum.TextTruncate.AtEnd
        mark_title.ZIndex = 21

        local stack = inst("Frame", gui)
        stack.BackgroundTransparency = 1
        stack.AnchorPoint = Vector2.new(1, 1)
        stack.Position = UDim2.new(1, -16, 1, -16)
        stack.Size = UDim2.fromOffset(252, WINDOW.Y)
        stack.ZIndex = 25
        local stack_list = inst("UIListLayout", stack)
        stack_list.Padding = UDim.new(0, 6)
        stack_list.VerticalAlignment = Enum.VerticalAlignment.Bottom
        stack_list.SortOrder = Enum.SortOrder.LayoutOrder

        local pill_visible = true
        local function place_pill()
            local abs = win.AbsolutePosition
            local size = win.AbsoluteSize
            pill.Position = UDim2.fromOffset(abs.X + size.X - 12, abs.Y - 22)
        end
        place_pill()

        local function set_window(shown)
            pill_visible = shown
            win.Visible = shown
            glow.Visible = shown
            pill_glyph.Visible = not shown
            if shown then
                pill.BackgroundTransparency = 0.12
                place_pill()
            else
                pill.BackgroundTransparency = 0.35
            end
        end

        pill.MouseButton1Click:Connect(function() set_window(not pill_visible) end)

        -- перетаскивание: тянем за верхнюю плашку контента
        do
            local dragging, drag_start, origin = false, nil, nil
            head_hit.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    dragging = true
                    drag_start = input.Position
                    origin = win.Position
                end
            end)
            UserInputService.InputChanged:Connect(function(input)
                if not dragging then return end
                if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
                local delta = input.Position - drag_start
                win.Position = UDim2.new(
                    origin.X.Scale, origin.X.Offset + delta.X,
                    origin.Y.Scale, origin.Y.Offset + delta.Y
                )
                place_pill()
            end)
            UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
            end)
        end

        return {
            gui = gui,
            window = win,
            content = content,
            nav = nav,
            head_hit = head_hit,
            blur = blur,
            mark = mark,
            stat = stat,
            stat_text = stat_text,
            page = page,
            stack = stack,
            pill = pill,
            set_window = set_window,
            is_shown = function() return pill_visible end,
            place_pill = place_pill,
        }
    end

    -- ---------- строки ----------
    local order = 0
    local function row_frame(canvas, height)
        order = order + 1
        local frame = inst("Frame", canvas)
        frame.BackgroundColor3 = PALETTE.white
        frame.BackgroundTransparency = ALPHA.row
        frame.BorderSizePixel = 0
        frame.Size = UDim2.new(1, 0, 0, height)
        frame.LayoutOrder = order
        frame.ZIndex = 3
        round(frame, RADIUS)
        outline(frame, PALETTE.white, 1, ALPHA.row_line)
        return frame
    end

    local function section(canvas, title)
        order = order + 1
        local wrap = inst("Frame", canvas)
        wrap.BackgroundTransparency = 1
        wrap.Size = UDim2.new(1, 0, 0, 20)
        wrap.LayoutOrder = order
        local text = label(wrap, tracked(string.upper(title)), 10, PALETTE.dim, "semi")
        text.Size = UDim2.new(1, 0, 1, 0)
        text.ZIndex = 4
        return wrap
    end

    local function make_page(win_ctx, name, icon, page_label)
        local canvas = inst("ScrollingFrame", win_ctx.content)
        canvas.BackgroundTransparency = 1
        canvas.BorderSizePixel = 0
        canvas.Size = UDim2.new(1, 0, 1, 0)
        canvas.Position = UDim2.new(0, 0, 0, 0)
        canvas.ScrollBarThickness = 2
        canvas.ScrollBarImageColor3 = PALETTE.accent
        canvas.ScrollBarImageTransparency = 0.45
        canvas.CanvasSize = UDim2.new(0, 0, 0, 0)
        canvas.Visible = false
        canvas.ZIndex = 3
        local list = inst("UIListLayout", canvas)
        list.Padding = UDim.new(0, GAP)
        list.SortOrder = Enum.SortOrder.LayoutOrder
        local pad = inst("UIPadding", canvas)
        pad.PaddingBottom = UDim.new(0, 14)
        list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            canvas.CanvasSize = UDim2.new(0, 0, 0, list.AbsoluteContentSize.Y + pad.PaddingBottom.Offset)
        end)

        -- кнопка навигации
        local btn = inst("TextButton", win_ctx.nav)
        btn.Text = ""
        btn.AutoButtonColor = false
        btn.BackgroundTransparency = 1
        btn.Size = UDim2.new(1, 0, 0, 36)
        btn.LayoutOrder = order + 1
        btn.ZIndex = 5
        local rail = inst("Frame", btn)
        rail.BackgroundColor3 = PALETTE.accent
        rail.BackgroundTransparency = 1
        rail.BorderSizePixel = 0
        rail.Size = UDim2.new(0, 2, 0, 18)
        rail.Position = UDim2.new(0, -8, 0.5, -9)
        rail.ZIndex = 6
        local icon_box = inst("Frame", btn)
        icon_box.BackgroundTransparency = 1
        icon_box.Size = UDim2.fromOffset(26, 26)
        icon_box.Position = UDim2.new(0, 6, 0.5, -13)
        icon_box.ZIndex = 6
        local nav_icon = glyph(icon_box, icon, 16, PALETTE.dim)
        nav_icon.Position = UDim2.fromScale(0.5, 0.5)
        nav_icon.ZIndex = 6
        local nav_label = label(btn, name, 12, PALETTE.muted, "med")
        nav_label.Size = UDim2.new(1, -46, 1, 0)
        nav_label.Position = UDim2.new(0, 42, 0, 0)
        nav_label.ZIndex = 6

        local page = { canvas = canvas, name = name, btn = btn, rail = rail, label = nav_label }
        page.paint = function(active)
            rail.BackgroundTransparency = active and 0 or 1
            nav_label.TextColor3 = active and PALETTE.text or PALETTE.muted
            page.label_color = active
        end
        page.set_icon = function(color)
            nav_icon:Destroy()
            nav_icon = glyph(icon_box, icon, 16, color)
            nav_icon.Position = UDim2.fromScale(0.5, 0.5)
            nav_icon.ZIndex = 6
        end
        page.show = function(shown)
            canvas.Visible = shown
            win_ctx.page.Text = string.upper(name)
        end
        btn.MouseButton1Click:Connect(function()
            for _, other in ipairs(win_ctx.pages) do
                other.show(other == page)
                other.paint(other == page)
                other.set_icon(other == page and PALETTE.icon or PALETTE.dim)
            end
        end)
        return page
    end

    local function format_value(value, suffix)
        if type(value) == "number" then
            if math.abs(value - math.floor(value)) < 0.001 then
                return string.format("%d", value) .. (suffix or "")
            end
            return string.format("%.2f", value) .. (suffix or "")
        end
        return tostring(value)
    end

    local api = {}
    api.palette = PALETTE
    api.painters = {}

    function api.new(cfg)
        local win_ctx = build_window(cfg)
        win_ctx.pages = {}
        local state = cfg.state

        local function page_for(page)
            win_ctx.pages[#win_ctx.pages + 1] = page
            return page
        end

        local shell = {}
        shell.window = win_ctx.window
        shell.gui = win_ctx.gui
        shell.set_window = win_ctx.set_window
        shell.is_shown = win_ctx.is_shown

        function shell:Tab(name, icon)
            local page = page_for(make_page(win_ctx, name, icon))
            local tab = { page = page }

            function tab:Section(title)
                section(page.canvas, title)
                return tab
            end

            function tab:Info(content)
                order = order + 1
                local wrap = inst("Frame", page.canvas)
                wrap.BackgroundTransparency = 1
                wrap.Size = UDim2.new(1, 0, 0, 16)
                wrap.LayoutOrder = order
                local text = label(wrap, content, 10, PALETTE.dim, "reg")
                text.Size = UDim2.new(1, 0, 1, 0)
                text.TextWrapped = true
                text.ZIndex = 4
                return tab
            end

            function tab:Toggle(title, key, on_change)
                local frame = row_frame(page.canvas, 40)
                local text = label(frame, title, 12, PALETTE.muted, "reg")
                text.Size = UDim2.new(1, -76, 1, 0)
                text.Position = UDim2.new(0, 14, 0, 0)
                text.ZIndex = 5

                local pill = inst("Frame", frame)
                pill.BackgroundColor3 = PALETTE.white
                pill.BackgroundTransparency = ALPHA.sw_off
                pill.BorderSizePixel = 0
                pill.AnchorPoint = Vector2.new(1, 0.5)
                pill.Position = UDim2.new(1, -14, 0.5, 0)
                pill.Size = UDim2.fromOffset(34, 18)
                pill.ZIndex = 5
                round(pill, 9)
                local knob = inst("Frame", pill)
                knob.BackgroundColor3 = PALETTE.white
                knob.BorderSizePixel = 0
                knob.AnchorPoint = Vector2.new(0, 0.5)
                knob.Size = UDim2.fromOffset(14, 14)
                knob.Position = UDim2.new(0, 2, 0.5, 0)
                knob.ZIndex = 6
                circle(knob)

                local function paint()
                    local on = state[key] and true or false
                    pill.BackgroundColor3 = on and PALETTE.accent or PALETTE.white
                    pill.BackgroundTransparency = on and 0 or ALPHA.sw_off
                    glide(knob, { Position = UDim2.new(0, on and 18 or 2, 0.5, 0) }, 0.14)
                    text.TextColor3 = on and PALETTE.text or PALETTE.muted
                end
                api.painters[#api.painters + 1] = paint
                paint()

                local press = hit(frame)
                press.BackgroundTransparency = 1
                press.Size = UDim2.new(1, 0, 1, 0)
                press.ZIndex = 7
                press.MouseButton1Click:Connect(function()
                    state[key] = not state[key]
                    paint()
                    if on_change then pcall(on_change, state[key]) end
                end)
                return tab
            end

            function tab:Slider(title, key, low, high, suffix)
                local frame = row_frame(page.canvas, 54)
                local text = label(frame, title, 12, PALETTE.muted, "reg")
                text.Size = UDim2.new(1, -100, 0, 16)
                text.Position = UDim2.new(0, 14, 0, 8)
                text.ZIndex = 5
                local value = label(frame, format_value(state[key], suffix), 11, PALETTE.icon, "semi")
                value.Size = UDim2.new(0, 76, 0, 16)
                value.Position = UDim2.new(1, -90, 0, 8)
                value.TextXAlignment = Enum.TextXAlignment.Right
                value.ZIndex = 5

                local track = inst("Frame", frame)
                track.BackgroundColor3 = PALETTE.white
                track.BackgroundTransparency = ALPHA.track
                track.BorderSizePixel = 0
                track.Size = UDim2.new(1, -28, 0, 4)
                track.Position = UDim2.new(0, 14, 0, 38)
                track.ZIndex = 5
                circle(track)

                local fill = inst("Frame", track)
                fill.BackgroundColor3 = PALETTE.accent
                fill.BorderSizePixel = 0
                fill.Size = UDim2.new(0, 0, 1, 0)
                fill.ZIndex = 6
                circle(fill)
                local grad = inst("UIGradient", fill)
                grad.Color = ColorSequence.new(PALETTE.accent, PALETTE.accent2)

                local knob = inst("Frame", track)
                knob.BackgroundColor3 = PALETTE.white
                knob.BorderSizePixel = 0
                knob.AnchorPoint = Vector2.new(0.5, 0.5)
                knob.Size = UDim2.fromOffset(12, 12)
                knob.Position = UDim2.new(0, 0, 0.5, 0)
                knob.ZIndex = 7
                circle(knob)

                local grab = hit(frame)
                grab.BackgroundTransparency = 1
                grab.Size = UDim2.new(1, 0, 0, 26)
                grab.Position = UDim2.new(0, 0, 0, 28)
                grab.ZIndex = 8

                local function ratio()
                    return math.clamp((state[key] - low) / math.max(1e-6, high - low), 0, 1)
                end

                local function paint()
                    local a = ratio()
                    fill.Size = UDim2.new(a, 0, 1, 0)
                    knob.Position = UDim2.new(a, 0, 0.5, 0)
                    value.Text = format_value(state[key], suffix)
                end
                api.painters[#api.painters + 1] = paint
                paint()

                local coarse = (high - low) >= 10
                local function apply(x)
                    local abs = track.AbsolutePosition.X
                    local width = track.AbsoluteSize.X
                    if width <= 0 then return end
                    local a = math.clamp((x - abs) / width, 0, 1)
                    local raw = low + a * (high - low)
                    state[key] = coarse and math.floor(raw + 0.5) or math.floor(raw * 100 + 0.5) / 100
                    paint()
                end

                local dragging = false
                grab.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 then
                        dragging = true
                        apply(input.Position.X)
                    end
                end)
                UserInputService.InputChanged:Connect(function(input)
                    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                        apply(input.Position.X)
                    end
                end)
                UserInputService.InputEnded:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
                end)
                return tab
            end

            function tab:Cycle(title, key, options)
                local frame = row_frame(page.canvas, 40)
                local text = label(frame, title, 12, PALETTE.muted, "reg")
                text.Size = UDim2.new(1, -132, 1, 0)
                text.Position = UDim2.new(0, 14, 0, 0)
                text.ZIndex = 5

                local box = inst("TextButton", frame)
                box.BackgroundColor3 = PALETTE.white
                box.BackgroundTransparency = ALPHA.track
                box.BorderSizePixel = 0
                box.AnchorPoint = Vector2.new(1, 0.5)
                box.Position = UDim2.new(1, -14, 0.5, 0)
                box.Size = UDim2.fromOffset(104, 24)
                box.Text = ""
                box.AutoButtonColor = false
                box.ZIndex = 5
                round(box, 8)
                outline(box, PALETTE.white, 1, ALPHA.row_line)
                local current = label(box, tostring(state[key]), 11, PALETTE.icon, "semi")
                current.Size = UDim2.new(1, 0, 1, 0)
                current.TextXAlignment = Enum.TextXAlignment.Center
                current.ZIndex = 6

                local function paint()
                    current.Text = tostring(state[key])
                    current.TextColor3 = PALETTE.icon
                end
                api.painters[#api.painters + 1] = paint

                box.MouseButton1Click:Connect(function()
                    local at = 1
                    for index, option in ipairs(options) do
                        if tostring(state[key]) == tostring(option) then at = index end
                    end
                    local next_index = at % #options + 1
                    state[key] = options[next_index]
                    paint()
                end)
                return tab
            end

            function tab:Keybind(title, key)
                local frame = row_frame(page.canvas, 40)
                local text = label(frame, title, 12, PALETTE.muted, "reg")
                text.Size = UDim2.new(1, -132, 1, 0)
                text.Position = UDim2.new(0, 14, 0, 0)
                text.ZIndex = 5

                local box = inst("TextButton", frame)
                box.BackgroundColor3 = PALETTE.white
                box.BackgroundTransparency = ALPHA.track
                box.BorderSizePixel = 0
                box.AnchorPoint = Vector2.new(1, 0.5)
                box.Position = UDim2.new(1, -14, 0.5, 0)
                box.Size = UDim2.fromOffset(104, 24)
                box.Text = ""
                box.AutoButtonColor = false
                box.ZIndex = 5
                round(box, 8)
                outline(box, PALETTE.white, 1, ALPHA.row_line)
                local current = label(box, "", 11, PALETTE.icon, "semi")
                current.Size = UDim2.new(1, 0, 1, 0)
                current.TextXAlignment = Enum.TextXAlignment.Center
                current.ZIndex = 6

                local function paint()
                    local held = state[key]
                    current.Text = type(held) == "EnumItem" and held.Name or tostring(held)
                end
                api.painters[#api.painters + 1] = paint
                paint()

                local listening = false
                box.MouseButton1Click:Connect(function()
                    listening = true
                    current.Text = "PRESS KEY"
                    current.TextColor3 = PALETTE.accent2
                end)
                UserInputService.InputBegan:Connect(function(input, processed)
                    if not listening then return end
                    if input.UserInputType == Enum.UserInputType.Keyboard then
                        state[key] = input.KeyCode
                        listening = false
                        current.TextColor3 = PALETTE.icon
                        paint()
                    elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not processed then
                        listening = false
                        current.TextColor3 = PALETTE.icon
                        paint()
                    end
                end)
                return tab
            end

            function tab:Button(text, style, callback)
                order = order + 1
                local ghost = (style == "ghost")
                local btn = inst("TextButton", page.canvas)
                btn.BackgroundColor3 = PALETTE.white
                btn.BackgroundTransparency = ghost and ALPHA.row or 0
                btn.BorderSizePixel = 0
                btn.Text = ""
                btn.AutoButtonColor = false
                btn.Size = UDim2.new(1, 0, 0, 34)
                btn.LayoutOrder = order
                btn.ZIndex = 4
                round(btn, RADIUS)
                if ghost then outline(btn, PALETTE.white, 1, ALPHA.row_line) end
                local caption = label(btn, text, 11, ghost and PALETTE.muted or PALETTE.onaccent, "semi")
                caption.Size = UDim2.new(1, 0, 1, 0)
                caption.TextXAlignment = Enum.TextXAlignment.Center
                caption.ZIndex = 5
                btn.MouseEnter:Connect(function()
                    if ghost then
                        glide(btn, { BackgroundTransparency = ALPHA.track }, 0.12)
                        caption.TextColor3 = PALETTE.text
                    else
                        glide(btn, { BackgroundColor3 = PALETTE.accent2 }, 0.12)
                    end
                end)
                btn.MouseLeave:Connect(function()
                    if ghost then
                        glide(btn, { BackgroundTransparency = ALPHA.row }, 0.12)
                        caption.TextColor3 = PALETTE.muted
                    else
                        glide(btn, { BackgroundColor3 = PALETTE.white }, 0.12)
                    end
                end)
                btn.MouseButton1Click:Connect(function() pcall(callback) end)
                return tab
            end

            return tab
        end

        function shell:Stat(initial)
            win_ctx.stat_text.Text = tostring(initial or "")
            return function(content)
                win_ctx.stat_text.Text = tostring(content or "")
            end
        end

        function shell:Toast(content, kind)
            if not state.ui_toasts then return end
            order = order + 1
            local frame = inst("Frame", win_ctx.stack)
            frame.BackgroundColor3 = PALETTE.white
            frame.BackgroundTransparency = ALPHA.glass8
            frame.BorderSizePixel = 0
            frame.Size = UDim2.new(1, 0, 0, 34)
            frame.LayoutOrder = order
            frame.ZIndex = 25
            round(frame, 10)
            outline(frame, PALETTE.white, 1, ALPHA.row_line)
            local rail = inst("Frame", frame)
            rail.BackgroundColor3 = (kind == "warn" and PALETTE.warn)
                or (kind == "good" and PALETTE.good) or PALETTE.accent
            rail.BorderSizePixel = 0
            rail.Size = UDim2.new(0, 2, 1, -14)
            rail.Position = UDim2.new(0, 10, 0, 7)
            rail.ZIndex = 26
            local text = label(frame, content, 11, PALETTE.text, "med")
            text.Size = UDim2.new(1, -28, 1, 0)
            text.Position = UDim2.new(0, 20, 0, 0)
            text.ZIndex = 26
            text.TextTruncate = Enum.TextTruncate.AtEnd
            task.delay(3.4, function()
                if frame.Parent then
                    glide(frame, { BackgroundTransparency = 1 }, 0.2)
                    glide(text, { TextTransparency = 1 }, 0.2)
                    task.wait(0.22)
                    pcall(function() frame:Destroy() end)
                end
            end)
        end

        function shell:Destroy()
            if win_ctx.blur then pcall(function() win_ctx.blur:Destroy() end) end
            pcall(function() win_ctx.gui:Destroy() end)
        end

        shell:Tab("Combat", "target")
        shell:Tab("Visuals", "eye")
        shell:Tab("Movement", "zap")
        shell:Tab("Config", "settings")
        shell.pages = win_ctx.pages
        return shell
    end

    return api
end)()

local UI = VANTA_UI.new({
    state = State,
    title = "Pistol Arena",
    subtitle = "pistol arena",
    version = "v3",
    stat = "aim —",
})
local P = VANTA_UI.palette

-- Первая вкладка показывается сразу, остальные прячутся до клика.
do
    for index, page in ipairs(UI.pages) do
        page.show(index == 1)
        page.paint(index == 1)
        page.set_icon(index == 1 and P.icon or P.dim)
    end
end

local setStat = UI:Stat("aim —")

local function toast(content, kind)
    pcall(function() UI:Toast(content, kind) end)
end

-- Перерисовка строк после загрузки или сброса профиля: painters регистрируются
-- каждым Toggle / Slider / Cycle / Keybind в момент сборки окна.
local function refresh_ui()
    for _, paint in ipairs(VANTA_UI.painters) do pcall(paint) end
end

-- =====================================================================
--  КОНФИГ
-- =====================================================================
local CONFIG_FILE = "VANTA_PistolArena.json"

local function enum_item(class, name)
    local ok, item = pcall(function() return Enum[class][name] end)
    if ok and item then return item end
    return nil
end

local function save_config()
    if type(writefile) ~= "function" then
        toast("executor без writefile — конфиг не сохранить", "warn")
        return
    end
    local flat = {}
    for key, value in pairs(State) do
        if typeof(value) == "EnumItem" then
            flat[key] = { __enum = tostring(value.EnumType), name = value.Name }
        elseif type(value) == "number" or type(value) == "boolean" or type(value) == "string" then
            flat[key] = value
        end
    end
    local ok = pcall(writefile, CONFIG_FILE, HttpService:JSONEncode(flat))
    toast(ok and "конфиг сохранён" or "конфиг не записался", ok and "good" or "warn")
end

local function load_config(silent)
    if type(isfile) ~= "function" or type(readfile) ~= "function" then
        if not silent then toast("executor без readfile", "warn") end
        return
    end
    local exists = false
    pcall(function() exists = isfile(CONFIG_FILE) end)
    if not exists then
        if not silent then toast("сохранённого конфига нет", "warn") end
        return
    end
    local raw = nil
    pcall(function() raw = readfile(CONFIG_FILE) end)
    if type(raw) ~= "string" then
        if not silent then toast("конфиг не прочитался", "warn") end
        return
    end
    local ok, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok or type(decoded) ~= "table" then
        if not silent then toast("конфиг битый", "warn") end
        return
    end
    for key, value in pairs(decoded) do
        if State[key] ~= nil then
            if type(value) == "table" and value.__enum then
                local item = enum_item(value.__enum, value.name)
                if item then State[key] = item end
            elseif type(value) == "number" or type(value) == "boolean" or type(value) == "string" then
                State[key] = value
            end
        end
    end
    refresh_ui()
    if not silent then toast("конфиг загружен", "good") end
end

local function reset_config()
    for key, value in pairs(DEFAULTS) do State[key] = value end
    refresh_ui()
    toast("настройки сброшены", "good")
end

-- =====================================================================
--  COMbat
-- =====================================================================
local tabCombat = UI:Tab("Combat", "target")
tabCombat:Section("aim")
tabCombat:Toggle("Aimbot", "aimbot", nil)
tabCombat:Toggle("Hold to aim", "aim_hold", nil)
tabCombat:Keybind("Aim key", "aim_key")
tabCombat:Cycle("Target part", "aim_part", { "Head", "Torso", "Root" })
tabCombat:Slider("FOV radius", "aim_fov", 20, 400, " px")
tabCombat:Slider("Speed", "aim_speed", 1, 100, "%")
tabCombat:Cycle("Curve", "aim_curve", { "EaseOut", "Linear", "EaseInOut" })
tabCombat:Slider("Max step", "aim_maxstep", 0, 40, " px")
tabCombat:Slider("Reaction", "aim_reaction", 0, 400, " ms")
tabCombat:Slider("Jitter", "aim_jitter", 0, 8, " px")
tabCombat:Slider("Max distance", "aim_maxdist", 100, 3000, " m")
tabCombat:Toggle("Wall check", "aim_wallcheck", nil)
tabCombat:Toggle("Skip teammates", "aim_teamcheck", nil)
tabCombat:Section("trigger")
tabCombat:Toggle("Triggerbot", "triggerbot", nil)
tabCombat:Toggle("Hold to fire", "trigger_hold", nil)
tabCombat:Keybind("Trigger key", "trigger_key")
tabCombat:Slider("Range", "trigger_range", 30, 1000, " m")
tabCombat:Slider("Delay min", "trigger_ms_min", 10, 400, " ms")
tabCombat:Slider("Delay max", "trigger_ms_max", 20, 600, " ms")
tabCombat:Slider("Fire chance", "trigger_chance", 1, 100, "%")

-- =====================================================================
--  VISUALS
-- =====================================================================
local tabVisuals = UI:Tab("Visuals", "eye")
tabVisuals:Section("players")
tabVisuals:Toggle("ESP", "esp", nil)
tabVisuals:Toggle("Boxes", "esp_box", nil)
tabVisuals:Toggle("Corners", "esp_corners", nil)
tabVisuals:Toggle("Names", "esp_name", nil)
tabVisuals:Toggle("Distance", "esp_dist", nil)
tabVisuals:Toggle("Health bar", "esp_hp", nil)
tabVisuals:Toggle("Tracers", "esp_tracer", nil)
tabVisuals:Slider("Max distance", "esp_maxdist", 100, 3000, " m")
tabVisuals:Toggle("Show allies", "esp_allies", nil)
tabVisuals:Section("screen")
tabVisuals:Toggle("FOV circle", "fov_circle", nil)

-- =====================================================================
--  MOVEMENT
-- =====================================================================
local tabMovement = UI:Tab("Movement", "zap")
tabMovement:Section("character")
tabMovement:Toggle("Anti-AFK", "antiafk", nil)
tabMovement:Toggle("Auto jump", "autojump", nil)
tabMovement:Info("Auto jump держит прыжок, пока зажат Space — как распрыжка.")
tabMovement:Section("camera")
tabMovement:Toggle("Custom FOV", "cam_fov_on", nil)
tabMovement:Slider("Camera FOV", "cam_fov", 60, 120, " deg")

-- =====================================================================
--  CONFIG
-- =====================================================================
local tabConfig = UI:Tab("Config", "settings")
tabConfig:Section("interface")
tabConfig:Keybind("Toggle key", "ui_key")
tabConfig:Toggle("Watermark", "ui_watermark", nil)
tabConfig:Toggle("Stat pill", "ui_stats", nil)
tabConfig:Toggle("Blur", "ui_blur", nil)
tabConfig:Toggle("Toasts", "ui_toasts", nil)
tabConfig:Section("profile")
tabConfig:Button("Save config", "primary", save_config)
tabConfig:Button("Load config", "ghost", function() load_config(false) end)
tabConfig:Button("Reset settings", "ghost", reset_config)

-- =====================================================================
--  ЯДРО
-- =====================================================================
local connections = {}
local function bind(signal, callback)
    local conn = signal:Connect(callback)
    connections[#connections + 1] = conn
    return conn
end

local function character_of(player)
    if player == LocalPlayer then return LocalPlayer.Character end
    return player.Character
end

local function humanoid_of(player)
    local char = character_of(player)
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    return hum
end

local function same_team(player)
    if player.Team == nil or LocalPlayer.Team == nil then return false end
    return player.Team == LocalPlayer.Team
end

local function target_part(player)
    local char = character_of(player)
    if not char then return nil end
    if State.aim_part == "Head" then return char:FindFirstChild("Head") end
    if State.aim_part == "Torso" then
        return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
            or char:FindFirstChild("HumanoidRootPart")
    end
    return char:FindFirstChild("HumanoidRootPart")
end

-- Фильтр для рейкаста: собираем один раз и обновляем только при смене персонажа.
local ray_params = Instance.new("RaycastParams")
pcall(function() ray_params.FilterType = Enum.RaycastFilterType.Exclude end)
pcall(function() ray_params.FilterType = Enum.RaycastFilterType.Blacklist end)
ray_params.IgnoreWater = true
local filtered_char = nil
local function refresh_filter()
    local list = {}
    if Camera then list[#list + 1] = Camera end
    local char = LocalPlayer.Character
    if char then
        list[#list + 1] = char
        filtered_char = char
    end
    ray_params.FilterDescendantsInstances = list
end
refresh_filter()

local function has_line_of_sight(part)
    if not State.aim_wallcheck then return true end
    local origin = Camera.CFrame.Position
    local hit = Workspace:Raycast(origin, part.Position - origin, ray_params)
    if not hit then return true end
    return hit.Instance:IsDescendantOf(part.Parent)
end

-- ===== ESP: пул Drawing-объектов =====
-- Слоты переиспользуются, объекты не создаются и не уничтожаются каждый кадр:
-- и быстрее, и не оставляет мусора в реестре Drawing.
local SLOTS = 16
local pool = {}
local function drawing_of(kind)
    local ok, obj = pcall(Drawing.new, kind)
    if ok and obj then return obj end
    return nil
end

local function make_slot()
    local slot = {
        box = drawing_of("Square"),
        corners = {},
        name = drawing_of("Text"),
        dist = drawing_of("Text"),
        tracer = drawing_of("Line"),
        hp_bg = drawing_of("Square"),
        hp_fg = drawing_of("Square"),
    }
    for i = 1, 8 do slot.corners[i] = drawing_of("Line") end
    if slot.box then
        slot.box.Filled = false
        slot.box.Thickness = 1
    end
    if slot.hp_bg then
        slot.hp_bg.Filled = true
        slot.hp_bg.Color = Color3.fromRGB(0, 0, 0)
        slot.hp_bg.Transparency = 0.55
    end
    if slot.hp_fg then slot.hp_fg.Filled = true end
    for i = 1, 8 do
        if slot.corners[i] then slot.corners[i].Thickness = 1 end
    end
    if slot.name then
        slot.name.Center = true
        slot.name.Outline = true
        slot.name.OutlineColor = Color3.fromRGB(0, 0, 0)
        slot.name.Size = 13
        pcall(function() slot.name.Font = 3 end)
    end
    if slot.dist then
        slot.dist.Center = true
        slot.dist.Outline = true
        slot.dist.OutlineColor = Color3.fromRGB(0, 0, 0)
        slot.dist.Size = 11
        pcall(function() slot.dist.Font = 3 end)
    end
    if slot.tracer then slot.tracer.Thickness = 1 end
    return slot
end

for i = 1, SLOTS do pool[i] = make_slot() end

local function hide_slot(slot)
    if slot.box then slot.box.Visible = false end
    if slot.name then slot.name.Visible = false end
    if slot.dist then slot.dist.Visible = false end
    if slot.tracer then slot.tracer.Visible = false end
    if slot.hp_bg then slot.hp_bg.Visible = false end
    if slot.hp_fg then slot.hp_fg.Visible = false end
    for i = 1, 8 do
        if slot.corners[i] then slot.corners[i].Visible = false end
    end
end

local fov_ring = drawing_of("Circle")
if fov_ring then
    fov_ring.Thickness = 1
    fov_ring.Filled = false
    fov_ring.NumSides = 64
    fov_ring.Transparency = 0.45
    fov_ring.Color = P.accent
end

-- Габарит модели по восьми углам: аксессуары и оружие в руках раздувают бокс,
-- поэтому берём рамку модели и проецируем её целиком, а не две опорные точки.
local CORNERS = {
    Vector3.new(-1, -1, -1), Vector3.new(1, -1, -1),
    Vector3.new(-1, 1, -1), Vector3.new(1, 1, -1),
    Vector3.new(-1, -1, 1), Vector3.new(1, -1, 1),
    Vector3.new(-1, 1, 1), Vector3.new(1, 1, 1),
}

local function screen_box(model)
    local center, size = model:GetBoundingBox()
    local min_x, min_y = math.huge, math.huge
    local max_x, max_y = -math.huge, -math.huge
    for i = 1, 8 do
        local point = center * CFrame.new(
            CORNERS[i].X * size.X / 2,
            CORNERS[i].Y * size.Y / 2,
            CORNERS[i].Z * size.Z / 2
        )
        local screen, on_screen = Camera:WorldToViewportPoint(point.Position)
        if on_screen == false or screen.Z <= 0 then return nil end
        if screen.X < min_x then min_x = screen.X end
        if screen.Y < min_y then min_y = screen.Y end
        if screen.X > max_x then max_x = screen.X end
        if screen.Y > max_y then max_y = screen.Y end
    end
    if max_x - min_x < 2 or max_y - min_y < 2 then return nil end
    return min_x, min_y, max_x, max_y
end

local function draw_esp(viewport)
    if not State.esp then
        for i = 1, SLOTS do hide_slot(pool[i]) end
        return 0
    end
    local used = 0
    local center_x = viewport.X / 2
    local origin = Camera.CFrame.Position

    for _, player in ipairs(Players:GetPlayers()) do
        if used >= SLOTS then break end
        if player ~= LocalPlayer and humanoid_of(player) then
            local skip = (not State.esp_allies) and same_team(player)
            local char = character_of(player)
            local distance = 0
            if char then
                local root = char:FindFirstChild("HumanoidRootPart")
                if root then distance = (root.Position - origin).Magnitude end
            end
            if skip or distance > State.esp_maxdist then
                -- пропускаем
            else
                local min_x, min_y, max_x, max_y
                if char then min_x, min_y, max_x, max_y = screen_box(char) end
                if min_x then
                    used = used + 1
                    local slot = pool[used]
                    local width = max_x - min_x
                    local height = max_y - min_y
                    local mid_x = (min_x + max_x) / 2

                    if State.esp_box and slot.box then
                        slot.box.Position = Vector2.new(min_x, min_y)
                        slot.box.Size = Vector2.new(width, height)
                        slot.box.Color = P.accent
                        slot.box.Transparency = 0.12
                        slot.box.Visible = true
                    elseif slot.box then
                        slot.box.Visible = false
                    end

                    local tick = math.min(9, width / 3, height / 3)
                    for i = 1, 8 do
                        local line = slot.corners[i]
                        if line then
                            local corner = math.floor((i - 1) / 2) + 1
                            local horizontal = (i % 2 == 1)
                            local left = (corner == 1 or corner == 3)
                            local top = (corner <= 2)
                            local px = left and min_x or max_x
                            local py = top and min_y or max_y
                            line.Visible = State.esp_corners and true or false
                            line.Color = P.accent2
                            line.Transparency = 0.05
                            if horizontal then
                                line.From = Vector2.new(px, py)
                                line.To = Vector2.new(px + (left and tick or -tick), py)
                            else
                                line.From = Vector2.new(px, py)
                                line.To = Vector2.new(px, py + (top and tick or -tick))
                            end
                        end
                    end

                    if slot.name then
                        slot.name.Visible = State.esp_name and true or false
                        slot.name.Position = Vector2.new(mid_x, min_y - 8)
                        slot.name.Text = player.Name
                        slot.name.Color = P.text
                    end

                    if slot.dist then
                        slot.dist.Visible = State.esp_dist and true or false
                        slot.dist.Position = Vector2.new(mid_x, max_y + 7)
                        slot.dist.Text = string.format("%d m", math.floor(distance + 0.5))
                        slot.dist.Color = P.muted
                    end

                    if slot.tracer then
                        slot.tracer.Visible = State.esp_tracer and true or false
                        slot.tracer.From = Vector2.new(center_x, viewport.Y)
                        slot.tracer.To = Vector2.new(mid_x, max_y)
                        slot.tracer.Color = P.icon
                        slot.tracer.Transparency = 0.25
                    end

                    if slot.hp_bg and slot.hp_fg then
                        local hum = char and char:FindFirstChildOfClass("Humanoid")
                        local show = State.esp_hp and hum ~= nil
                        slot.hp_bg.Visible = show
                        slot.hp_fg.Visible = show
                        if show then
                            local ratio = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
                            local bar_x = min_x - 5
                            slot.hp_bg.Position = Vector2.new(bar_x, min_y)
                            slot.hp_bg.Size = Vector2.new(2, height)
                            slot.hp_fg.Position = Vector2.new(bar_x, min_y + height * (1 - ratio))
                            slot.hp_fg.Size = Vector2.new(2, height * ratio)
                            slot.hp_fg.Color = ratio > 0.55 and P.good or (ratio > 0.25 and P.accent2 or P.warn)
                        end
                    end
                end
            end
        end
    end

    for i = used + 1, SLOTS do hide_slot(pool[i]) end
    return used
end

-- ===== AIM =====
local aim_target = nil
local aim_acquired = 0
local accum_x, accum_y = 0, 0

local function pick_target(viewport)
    local best, best_distance = nil, math.huge
    local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
    local origin = Camera.CFrame.Position
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and humanoid_of(player) then
            if not (State.aim_teamcheck and same_team(player)) then
                local part = target_part(player)
                if part then
                    local distance = (part.Position - origin).Magnitude
                    if distance <= State.aim_maxdist then
                        local screen, on_screen = Camera:WorldToViewportPoint(part.Position)
                        if on_screen ~= false and screen.Z > 0 then
                            local offset = (Vector2.new(screen.X, screen.Y) - center).Magnitude
                            if offset <= State.aim_fov and offset < best_distance and has_line_of_sight(part) then
                                best, best_distance = player, offset
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function curve_gain(distance)
    if State.aim_curve == "Linear" then return 1 end
    if State.aim_curve == "EaseInOut" then
        return 0.45 + 0.55 * math.min(1, distance / 160)
    end
    return math.clamp(distance / 220, 0.25, 1)
end

local function steer(viewport)
    if not State.aimbot then
        aim_target = nil
        return
    end
    if State.aim_hold and not UserInputService:IsKeyDown(State.aim_key) then
        aim_target = nil
        accum_x, accum_y = 0, 0
        return
    end

    local target = pick_target(viewport)
    if target ~= aim_target then
        aim_target = target
        aim_acquired = os.clock()
        accum_x, accum_y = 0, 0
    end
    if not aim_target then return end

    -- Задержка реакции: живая рука не начинает доводку в тот же кадр, что заметила цель.
    if (os.clock() - aim_acquired) * 1000 < State.aim_reaction then return end

    local part = target_part(aim_target)
    if not part then
        aim_target = nil
        return
    end
    local screen, on_screen = Camera:WorldToViewportPoint(part.Position)
    if on_screen == false or screen.Z <= 0 then return end

    local dx = screen.X - viewport.X / 2
    local dy = screen.Y - viewport.Y / 2
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < 0.6 then return end

    local gain = (State.aim_speed / 100) * curve_gain(distance)
    local step_x = dx * gain
    local step_y = dy * gain

    if State.aim_maxstep > 0 then
        local step_length = math.sqrt(step_x * step_x + step_y * step_y)
        if step_length > State.aim_maxstep then
            local scale = State.aim_maxstep / step_length
            step_x = step_x * scale
            step_y = step_y * scale
        end
    end

    if State.aim_jitter > 0 then
        step_x = step_x + (math.random() * 2 - 1) * State.aim_jitter
        step_y = step_y + (math.random() * 2 - 1) * State.aim_jitter
    end

    -- Дробный остаток копится в накопителе: mousemoverel принимает целые, без
    -- накопителя мелкая доводка на малом шаге просто не сдвинула бы курсор.
    accum_x = accum_x + step_x
    accum_y = accum_y + step_y
    local move_x = math.floor(accum_x + 0.5)
    local move_y = math.floor(accum_y + 0.5)
    if move_x ~= 0 or move_y ~= 0 then
        accum_x = accum_x - move_x
        accum_y = accum_y - move_y
        move_mouse(move_x, move_y)
    end
end

-- ===== TRIGGER =====
local trigger_params = Instance.new("RaycastParams")
pcall(function() trigger_params.FilterType = Enum.RaycastFilterType.Exclude end)
pcall(function() trigger_params.FilterType = Enum.RaycastFilterType.Blacklist end)
trigger_params.IgnoreWater = true

local last_shot = 0
local next_gap = 0

local function fire_tick()
    if not State.triggerbot then return end
    if State.trigger_hold and not UserInputService:IsKeyDown(State.trigger_key) then return end

    local list = { Camera }
    if LocalPlayer.Character then list[#list + 1] = LocalPlayer.Character end
    trigger_params.FilterDescendantsInstances = list

    local origin = Camera.CFrame.Position
    local hit = Workspace:Raycast(origin, Camera.CFrame.LookVector * State.trigger_range, trigger_params)
    if not hit then return end

    local model = hit.Instance:FindFirstAncestorOfClass("Model")
    local player = model and Players:GetPlayerFromCharacter(model)
    if not player or player == LocalPlayer then return end
    if State.aim_teamcheck and same_team(player) then return end

    local now = os.clock()
    if now - last_shot < next_gap then return end

    local low = math.min(State.trigger_ms_min, State.trigger_ms_max)
    local high = math.max(State.trigger_ms_min, State.trigger_ms_max)
    next_gap = (low + math.random() * (high - low)) / 1000
    last_shot = now

    -- Шанс пропуска: ровный автомат по каждому проходу прицела — подпись скрипта.
    if math.random(1, 100) <= State.trigger_chance then click_mouse() end
end

-- ===== MOVEMENT =====
local base_fov = Camera and Camera.FieldOfView or 70
local applied_fov = false

bind(LocalPlayer.Idled, function()
    if not State.antiafk then return end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

local function movement_tick()
    if State.autojump and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        local hum = humanoid_of(LocalPlayer)
        if hum and hum.FloorMaterial ~= Enum.Material.Air then hum.Jump = true end
    end

    if State.cam_fov_on then
        if math.abs(Camera.FieldOfView - State.cam_fov) > 0.5 then
            Camera.FieldOfView = State.cam_fov
            applied_fov = true
        end
    elseif applied_fov then
        Camera.FieldOfView = base_fov
        applied_fov = false
    end
end

-- ===== КЛАВИША ОКНА =====
bind(UserInputService.InputBegan, function(input, processed)
    if processed then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if input.KeyCode == State.ui_key then
        UI.set_window(not UI.is_shown())
    end
end)

-- =====================================================================
--  ЦИКЛ
-- =====================================================================
local frame_index = 0
local esp_count = 0

bind(RunService.RenderStepped, function()
    local current = Workspace.CurrentCamera
    if current and current ~= Camera then
        Camera = current
        base_fov = Camera.FieldOfView
        refresh_filter()
    end
    if not Camera then return end

    local char = LocalPlayer.Character
    if char ~= filtered_char then refresh_filter() end

    local viewport = Camera.ViewportSize
    frame_index = frame_index + 1

    if fov_ring then
        fov_ring.Visible = State.fov_circle and State.aimbot
        if fov_ring.Visible then
            fov_ring.Position = Vector2.new(viewport.X / 2, viewport.Y / 2)
            fov_ring.Radius = State.aim_fov
        end
    end

    esp_count = draw_esp(viewport)
    steer(viewport)
    fire_tick()
    movement_tick()

    if State.ui_stats and frame_index % 8 == 0 then
        local label_text = aim_target and ("target " .. aim_target.Name) or "aim —"
        setStat(label_text .. "  |  esp " .. tostring(esp_count))
    end
end)

-- =====================================================================
--  ЗАВЕРШЕНИЕ
-- =====================================================================
local function unload()
    if applied_fov then pcall(function() Camera.FieldOfView = base_fov end) end
    for _, conn in ipairs(connections) do pcall(function() conn:Disconnect() end) end
    for i = 1, SLOTS do
        local slot = pool[i]
        hide_slot(slot)
        for _, key in ipairs({ "box", "name", "dist", "tracer", "hp_bg", "hp_fg" }) do
            if slot[key] then pcall(function() slot[key]:Remove() end) end
        end
        for j = 1, 8 do
            if slot.corners[j] then pcall(function() slot.corners[j]:Remove() end) end
        end
    end
    if fov_ring then pcall(function() fov_ring:Remove() end) end
    pcall(function() UI:Destroy() end)
end

GENV.VANTA = GENV.VANTA or {}
GENV.VANTA.pistol = { unload = unload, state = State }

load_config(true)
toast("загружено · RightShift — окно", "good")
