--[[
    JakoScripts — bootstrap
    language: Luau | file: JakoScripts_bootstrap.lua | target: Roblox executor

    Для приватного репозитория. Вставляется в инжектор как есть:

      1. вставь свой fine-grained PAT в TOKEN ниже
         (GitHub → Settings → Developer settings → Fine-grained tokens:
          Repository access = только JakoScripts, Permissions = Contents: Read-only)
      2. вставь весь этот файл в инжектор и запусти

    Патч тянется из приватного репо через GitHub Contents API с Bearer-токеном.
    Для публичного репо токен можно оставить пустым — тогда идёт обычный raw.

    ВНИМАНИЕ: токен лежит в тексте скрипта. Кто получил этот файл — получил токен.
    Поэтому только fine-grained, только один репозиторий, только Contents: Read.
    Утёк — отзывается одной кнопкой в GitHub Settings, остальные репо не затронуты.
]]

local CFG = {
    owner  = "Qold123",
    repo   = "Qold123",
    branch = "main",
    file   = "JakoScripts.lua",
    token  = "",           -- ← fine-grained PAT, Contents: Read-only
}

local function fetch(url, headers)
    local fn = (syn and syn.request) or request or http_request
    if fn then
        local ok, r = pcall(fn, { Url = url, Method = "GET", Headers = headers or {} })
        if ok and r and r.Body and #r.Body > 0 then return r.Body end
    end
    return nil
end

local body
if CFG.token ~= "" then
    body = fetch(("https://api.github.com/repos/%s/%s/contents/%s?ref=%s"):format(
        CFG.owner, CFG.repo, CFG.file, CFG.branch), {
        ["Accept"]        = "application/vnd.github.raw",
        ["Authorization"] = "Bearer " .. CFG.token,
        ["User-Agent"]    = "Qold123",
    })
    -- запасной путь: classic PAT прямо в raw-URL
    if not body then
        body = fetch(("https://%s@raw.githubusercontent.com/%s/%s/%s/%s"):format(
            CFG.token, CFG.owner, CFG.repo, CFG.branch, CFG.file))
    end
else
    body = fetch(("https://raw.githubusercontent.com/%s/%s/%s/%s"):format(
        CFG.owner, CFG.repo, CFG.branch, CFG.file))
end

if not body or #body < 2000 or not string.find(body, "Qold123", 1, true) then
    return warn("[JakoScripts] не получил код. Проверь токен (Contents: Read), ветку " ..
        CFG.branch .. " и имя файла " .. CFG.file)
end

local chunk, err = (loadstring or load)(body, "@JakoScripts.lua")
if not chunk then return warn("[JakoScripts] compile: " .. tostring(err)) end
local ok, rerr = pcall(chunk)
if not ok then return warn("[JakoScripts] runtime: " .. tostring(rerr)) end

CFG.token = nil
getgenv().JakoScripts = { name = "Qold123", version = "v3.0", source = "github:" .. CFG.repo }
print("[JakoScripts] loaded from github:" .. CFG.owner .. "/" .. CFG.repo)
