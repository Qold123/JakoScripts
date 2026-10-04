--[[
    JakoScripts — loader / инжектор-строка
    language: Luau | file: JakoScripts_loader.lua | target: Roblox executor

    Одна строка для инжектора:

        loadstring(game:HttpGet("https://raw.githubusercontent.com/USER/REPO/main/JakoScripts_loader.lua"))()

    Лоадер тянет основной файл JakoScripts.lua и запускает его.
    Правь только CFG.primary / CFG.mirrors ниже — больше нигде URL не живёт.

    Порядок поиска:
      1. локальный файл из workspace экзекутора (readfile), если есть и свежий
      2. CFG.primary
      3. CFG.mirrors по очереди
    Тело проверяется на маркер и минимальную длину — HTML-страница ошибки
    (404 / rate-limit) не будет выполнена как скрипт.
]]

local CFG = {
    name           = "JakoScripts",
    version        = "v3.0",
    -- ── приватный репозиторий ────────────────────────────────────
    -- token пустой -> обычный raw (публичный репо или локальный файл).
    -- token заполнен -> GitHub Contents API с Bearer, потом raw с токеном в URL.
    owner          = "JakoScripts",
    repo           = "JakoScripts",
    branch         = "main",
    token          = "",   -- fine-grained PAT: только этот репо, Contents: Read-only
    -- ── публичный raw-URL (используется когда token пустой) ──────
    primary        = "https://raw.githubusercontent.com/JakoScripts/JakoScripts/main/JakoScripts.lua",
    mirrors        = {
        "https://cdn.jsdelivr.net/gh/JakoScripts/JakoScripts@main/JakoScripts.lua",
        "https://raw.githack.com/JakoScripts/JakoScripts/main/JakoScripts.lua",
    },
    -- локальная копия в workspace экзекутора (Delta / Xeno / Solara кладут файлы рядом)
    local_file     = "JakoScripts.lua",
    prefer_local   = false,
    marker         = "JakoScripts",
    min_bytes      = 2000,
    bust_cache     = false,
    timeout_note   = "если primary отдал HTML — проверь ветку (main/master) и имя файла",
}

-- ── http-бэкенды: у экзекуторов они разные ───────────────────────
local function http_get(url, headers)
    local tries = {}

    if syn and syn.request then
        tries[#tries + 1] = function()
            local r = syn.request({ Url = url, Method = "GET", Headers = headers or {} })
            return r and r.Body
        end
    end
    if request then
        tries[#tries + 1] = function()
            local r = request({ Url = url, Method = "GET", Headers = headers or {} })
            return r and r.Body
        end
    end
    if http_request then
        tries[#tries + 1] = function()
            local r = http_request({ Url = url, Method = "GET", Headers = headers or {} })
            return r and r.Body
        end
    end
    if http and http.get then
        tries[#tries + 1] = function() return http.get(url) end
    end
    if game and game.HttpGet then
        tries[#tries + 1] = function() return game:HttpGet(url) end
    end

    for _, fn in ipairs(tries) do
        local ok, body = pcall(fn)
        if ok and type(body) == "string" and #body > 0 then return body end
    end
    return nil
end

local function url_with_cache_bust(url)
    if not CFG.bust_cache then return url end
    local sep = string.find(url, "?", 1, true) and "&" or "?"
    return url .. sep .. "t=" .. tostring(os.time())
end

local function looks_valid(body)
    if type(body) ~= "string" then return false end
    if #body < CFG.min_bytes then return false end
    if not string.find(body, CFG.marker, 1, true) then return false end
    -- HTML-заглушка вместо кода
    local head = string.lower(string.sub(body, 1, 200))
    if string.find(head, "<!doctype", 1, true) or string.find(head, "<html", 1, true) then return false end
    return true
end

-- ── локальный файл ──────────────────────────────────────────────
local function from_local()
    if not (readfile and isfile) then return nil end
    local ok, exists = pcall(isfile, CFG.local_file)
    if not ok or not exists then return nil end
    local ok2, body = pcall(readfile, CFG.local_file)
    if ok2 and looks_valid(body) then return body, "local:" .. CFG.local_file end
    return nil
end

local function from_net()
    -- приватный репозиторий: Contents API + Bearer
    if CFG.token ~= "" then
        local api = ("https://api.github.com/repos/%s/%s/contents/%s?ref=%s"):format(
            CFG.owner, CFG.repo, CFG.local_file, CFG.branch)
        local body = http_get(api, {
            ["Accept"]        = "application/vnd.github.raw",
            ["Authorization"] = "Bearer " .. CFG.token,
            ["User-Agent"]    = CFG.name,
        })
        if looks_valid(body) then return body, "api:" .. CFG.repo .. "/" .. CFG.local_file end

        -- classic PAT прямо в raw-URL
        local raw = ("https://%s@raw.githubusercontent.com/%s/%s/%s/%s"):format(
            CFG.token, CFG.owner, CFG.repo, CFG.branch, CFG.local_file)
        body = http_get(raw)
        if looks_valid(body) then return body, "raw:" .. CFG.repo end
    end

    local sources = { CFG.primary }
    for _, m in ipairs(CFG.mirrors) do sources[#sources + 1] = m end
    for _, url in ipairs(sources) do
        local body = http_get(url_with_cache_bust(url))
        if looks_valid(body) then return body, url end
    end
    return nil
end

-- ── fetch ───────────────────────────────────────────────────────
local body, source
if CFG.prefer_local then body, source = from_local() end
if not body then body, source = from_net() end
if not body and not CFG.prefer_local then body, source = from_local() end

if not body then
    local msg = "[" .. CFG.name .. "] источник не отдал код. " .. CFG.timeout_note
    warn(msg)
    pcall(function() print(msg) end)
    return
end

-- ── run ─────────────────────────────────────────────────────────
local loader = loadstring or load
if type(loader) ~= "function" then
    warn("[" .. CFG.name .. "] экзекутор без loadstring")
    return
end

local chunk, compile_err = loader(body, "@" .. CFG.name .. ".lua")
if not chunk then
    warn("[" .. CFG.name .. "] ошибка компиляции: " .. tostring(compile_err))
    return
end

local ok, run_err = pcall(chunk)
if not ok then
    warn("[" .. CFG.name .. "] ошибка выполнения: " .. tostring(run_err))
    return
end

getgenv().JakoScripts = {
    name    = CFG.name,
    version = CFG.version,
    source  = source,
    loaded  = os.time(),
}

print(string.format("[%s %s] loaded from %s", CFG.name, CFG.version, tostring(source)))
