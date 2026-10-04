--[[
    JakoScripts — silencer
    language: Luau | file: JakoScripts_silencer.lua | target: Roblox executor

    Гасит нативные тосты Roblox — путь SetCore("SendNotification").
    Именно он роняет в консоль:

        [Roblox][CoreGui.RobloxGui.Modules.Common.Locales.en-us]
        CoreGui.xxxxxxxx:1: attempt to call a nil value

    В JakoScripts v3 своих SetCore-вызовов нет: уведомления — собственные
    тосты на фреймах. Ошибку кидает либо старый v2 (notify() на каждой
    смене роли), либо сам экзекутор. Глушилка ставится один раз за сессию.

    Вставлять до основного скрипта:
        loadstring(readfile("JakoScripts_silencer.lua"))()
]]

local SG = game:GetService("StarterGui")

if type(hookfunction) ~= "function" then
    return warn("[JakoScripts] hookfunction недоступен — глушилка не поставлена. " ..
        "Выключи уведомления в настройках экзекутора.")
end

if type(SG.SetCore) ~= "function" then
    return warn("[JakoScripts] StarterGui.SetCore не найден")
end

local orig = SG.SetCore

local function hook(self, what, ...)
    if what == "SendNotification" then return false end
    return orig(self, what, ...)
end

local wrapped = hook
if type(newcclosure) == "function" then
    local ok, c = pcall(newcclosure, hook)
    if ok and c then wrapped = c end
end

local ok, err = pcall(hookfunction, orig, wrapped)
if not ok then
    return warn("[JakoScripts] hook не встал: " .. tostring(err))
end

getgenv().JakoScriptsSilencer = { active = true, at = os.time() }
print("[JakoScripts] SetCore(SendNotification) silenced")
