-- Universal FPS Cheat for Roblox
-- Executor: Synapse, Krnl, Fluxus, etc.
-- Works with most first-person shooters (pistol duels, shooters)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

-- ============ CONFIG ============
local Config = {
    AimbotEnabled = false,
    TriggerbotEnabled = false,
    AutoShootEnabled = false,
    AimKey = Enum.UserInputType.MouseButton2, -- ПКМ для прицеливания
    AimPart = "Head", -- "Head" или "HumanoidRootPart"
    FOV = 150, -- радиус поиска цели в пикселях
    Smoothness = 0.25, -- 0 = мгновенно, 1 = очень плавно
    TeamCheck = true, -- игнорировать союзников
    TriggerDelay = 0.05, -- задержка перед выстрелом (сек)
    AutoShootRange = 300, -- макс. дистанция автострельбы
}

-- ============ GUI ============
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "FPS_Cheat"
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
ScreenGui.ResetOnSpawn = false

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 240, 0, 320)
MainFrame.Position = UDim2.new(0, 20, 0, 100)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
MainFrame.BackgroundTransparency = 0.1
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 12)
UICorner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 40)
Title.BackgroundTransparency = 1
Title.Text = "VANTA FPS"
Title.TextColor3 = Color3.fromRGB(0, 200, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 20
Title.Parent = MainFrame

local buttonY = 50
local function createToggle(text, default, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 34)
    btn.Position = UDim2.new(0, 10, 0, buttonY)
    btn.BackgroundColor3 = default and Color3.fromRGB(0, 130, 0) or Color3.fromRGB(45, 45, 60)
    btn.Text = text .. ": " .. (default and "ON" or "OFF")
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 14
    btn.Parent = MainFrame
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = btn
    local state = default
    btn.MouseButton1Click:Connect(function()
        state = not state
        btn.BackgroundColor3 = state and Color3.fromRGB(0, 130, 0) or Color3.fromRGB(45, 45, 60)
        btn.Text = text .. ": " .. (state and "ON" or "OFF")
        callback(state)
    end)
    buttonY = buttonY + 38
    return btn
end

createToggle("Aimbot", Config.AimbotEnabled, function(v) Config.AimbotEnabled = v end)
createToggle("Triggerbot", Config.TriggerbotEnabled, function(v) Config.TriggerbotEnabled = v end)
createToggle("AutoShoot", Config.AutoShootEnabled, function(v) Config.AutoShootEnabled = v end)

-- ============ FUNCTIONS ============
local function isEnemy(plr)
    if plr == LocalPlayer then return false end
    if not plr.Character or not plr.Character:FindFirstChild("Humanoid") then return false end
    local hum = plr.Character.Humanoid
    if hum.Health <= 0 then return false end
    if Config.TeamCheck and LocalPlayer.Team and plr.Team then
        if LocalPlayer.Team == plr.Team then return false end
    end
    return true
end

local function getTargetPart(plr)
    if not plr.Character then return nil end
    if Config.AimPart == "Head" then
        return plr.Character:FindFirstChild("Head")
    else
        return plr.Character:FindFirstChild("HumanoidRootPart")
    end
end

local function getClosestTarget()
    local closest = nil
    local shortest = Config.FOV
    local mousePos = UserInputService:GetMouseLocation()
    for _, plr in ipairs(Players:GetPlayers()) do
        if isEnemy(plr) then
            local part = getTargetPart(plr)
            if part then
                local screenPos, onScreen = Camera:WorldToScreenPoint(part.Position)
                if onScreen then
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if dist < shortest then
                        shortest = dist
                        closest = part
                    end
                end
            end
        end
    end
    return closest
end

local function aimAt(target)
    if not target then return end
    local targetPos = target.Position
    local camPos = Camera.CFrame.Position
    local newCFrame = CFrame.new(camPos, targetPos)
    if Config.Smoothness > 0 then
        Camera.CFrame = Camera.CFrame:Lerp(newCFrame, 1 - Config.Smoothness)
    else
        Camera.CFrame = newCFrame
    end
end

local function triggerbot()
    if not Config.TriggerbotEnabled then return end
    local target = Mouse.Target
    if target and target.Parent then
        local plr = Players:GetPlayerFromCharacter(target.Parent)
        if plr and isEnemy(plr) then
            if mouse1click then
                mouse1click()
            elseif VirtualUser then
                VirtualUser:ClickButton1(Vector2.new())
            end
        end
    end
end

local function autoShoot()
    if not Config.AutoShootEnabled then return end
    local char = LocalPlayer.Character
    if not char then return end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return end
    local target = getClosestTarget()
    if not target then return end
    local dist = (Camera.CFrame.Position - target.Position).Magnitude
    if dist <= Config.AutoShootRange then
        if tool:IsA("Tool") and tool:FindFirstChild("Handle") then
            tool:Activate()
        end
    end
end

-- ============ MAIN LOOP ============
RunService.RenderStepped:Connect(function()
    if Config.AimbotEnabled then
        local isAiming = UserInputService:IsMouseButtonPressed(Config.AimKey)
        if isAiming then
            local target = getClosestTarget()
            if target then
                aimAt(target)
            end
        end
    end
    if Config.TriggerbotEnabled then
        triggerbot()
    end
    if Config.AutoShootEnabled then
        autoShoot()
    end
end)

-- Сброс при респавне
LocalPlayer.CharacterAdded:Connect(function()
    wait(1)
    -- ничего не сбрасываем, конфиг сохраняется
end)
