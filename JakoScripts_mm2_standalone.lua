-- language: Luau (Roblox), file: JakoScripts.lua, runtime: Roblox client + executor (loadstring / HttpGet), UI: WindUI, target: Murder Mystery 2
-- VANTA Style A — Dark Violet Glass
-- REQUIRED executor surface: loadstring, game:HttpGet, getrawmetatable, setreadonly, newcclosure/hookmetamethod
-- MM2 BUILD NOTES (drift happens, re-derive after every game update):
--   1. Tool identities: murderer = "Knife", sheriff = "Gun". Verify with the "Dump World" button if autofire/autostab goes dead.
--   2. Ranged kill path: MM2 gun raycasts client-side from mouse.Hit -> silent aim hooks __index on the mouse object.
--      If shots stop landing, the build moved to mouse.UnitRay / mouse.Target only: all three are hooked.
--   3. Throw path: remote name differs per build. "Dump Remotes" prints every RemoteEvent/RemoteFunction full name,
--      put the exact one into Combat > Auto > Throw Remote.
--   4. Nothing here is version-locked: role detection, ESP and grab read live instance names, not offsets.

--===================================================================== services
local cloneref = cloneref or function(o) return o end
local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local HttpService = cloneref(game:GetService("HttpService"))
local TeleportService = cloneref(game:GetService("TeleportService"))
local StarterGui = cloneref(game:GetService("StarterGui"))
local Lighting = cloneref(game:GetService("Lighting"))
local RS = cloneref(game:GetService("ReplicatedStorage"))
local LocalPlayer = Players.LocalPlayer
local LP = LocalPlayer
local CAMERA = workspace.CurrentCamera
local MOUSE = LocalPlayer:GetMouse()

local protect = function(f) return f end
if typeof(newcclosure) == "function" then protect = newcclosure end

local getgenv_ref = getgenv or function() return _G end
local GENV = getgenv_ref()

--===================================================================== palette — VANTA Style A
local function hex(s)
	s = tostring(s):gsub("#", "")
	local a = 1
	if #s == 8 then
		a = (tonumber(s:sub(7, 8), 16) or 255) / 255
		s = s:sub(1, 6)
	end
	return Color3.fromHex("#" .. s), a
end

local BG = hex("#06060B")
local GLASS = hex("#FFFFFF")
local STROKE, STROKE_A = hex("#FFFFFF1C")   -- 1px border, alpha 0.11
local SHINE, SHINE_A = hex("#FFFFFF22")
local ACCENT = hex("#7C3AED")
local ICON = hex("#A78BFA")
local TEXT = hex("#FFFFFF")
local MUTED = hex("#A1A1AA")
local DIM = hex("#71717A")
local ONACC = hex("#09090B")
local TRACK, TRACK_A = hex("#FFFFFF15")
local ROW, ROW_A = hex("#FFFFFF08")         -- row fill 3%
local ROWBORD, ROWBORD_A = hex("#FFFFFF0F")
local SWOFF, SWOFF_A = hex("#FFFFFF1E")
local LILAC = hex("#C4B5FD")

--===================================================================== state
local STATE = {
	-- combat
	silent_aim = false,
	aim_hold = false,
	aim_key = "LeftAlt",
	fov = 140,
	fov_circle = true,
	target_mode = "Murderer first",
	wall_check = true,
	ignore_innocent = true,
	only_with_gun = true,
	auto_fire = false,
	fire_delay = 0.12,
	auto_stab = false,
	stab_range = 9,
	auto_throw = false,
	throw_remote = "",
	grab_gun = false,
	grab_teleport = true,
	-- visuals
	esp_players = true,
	esp_items = true,
	esp_distance = 400,
	esp_names = true,
	esp_distance_text = true,
	chams = true,
	tracers = false,
	fullbright = false,
	-- movement
	speed_enabled = false,
	speed_value = 16,
	jump_enabled = false,
	jump_value = 50,
	inf_jump = false,
	fly = false,
	fly_speed = 60,
	noclip = false,
	anti_afk = false,
	-- ui / config
	ui_key = "RightShift",
	vanta_skin = true,
	config_name = "default",
}

local CONN = {}
local CACHE = { highlights = {}, billboards = {}, tracers = {} }
local ORIG = {}
local aim_target = nil
local UNLOADED = false
local VANTA_WINDOW = nil
local GUI_ROOT = nil

--===================================================================== helpers
local function notify(title, content, icon)
	local ok = pcall(function()
		if VANTA_WINDOW and typeof(VANTA_WINDOW.Notification) == "function" then
			VANTA_WINDOW:Notification({ Title = title, Content = content, Icon = icon or "zap", Duration = 4 })
		end
	end)
	if ok then return end
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = title, Text = content, Duration = 4 })
	end)
end

local function is_alive(plr)
	local char = plr.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function char_of(plr)
	return plr.Character
end

local function get_tool(name)
	local char = LP.Character
	if char then
		local t = char:FindFirstChild(name)
		if t and t:IsA("Tool") then return t end
	end
	local bp = LP:FindFirstChildOfClass("Backpack")
	if bp then
		local t = bp:FindFirstChild(name)
		if t and t:IsA("Tool") then return t end
	end
	return nil
end

local function role_of(plr)
	local char = char_of(plr)
	if char then
		if char:FindFirstChild("Knife") then return "Murderer" end
		if char:FindFirstChild("Gun") then return "Sheriff" end
	end
	local bp = plr:FindFirstChildOfClass("Backpack")
	if bp then
		if bp:FindFirstChild("Knife") then return "Murderer" end
		if bp:FindFirstChild("Gun") then return "Sheriff" end
	end
	return "Innocent"
end

local function role_color(role)
	if role == "Murderer" then return ACCENT end
	if role == "Sheriff" then return ICON end
	return TEXT
end

local function local_role()
	if get_tool("Knife") then return "Murderer" end
	if get_tool("Gun") then return "Sheriff" end
	return "Innocent"
end

local function holder_humanoid(inst)
	local p = inst.Parent
	while p and p ~= workspace do
		if p:FindFirstChildOfClass("Humanoid") then return true end
		p = p.Parent
	end
	return false
end

local function part_visible(part)
	local origin = CAMERA.CFrame.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LP.Character, CAMERA }
	local hit = workspace:Raycast(origin, part.Position - origin, params)
	if not hit then return true end
	return hit.Instance:IsDescendantOf(part.Parent)
end

--===================================================================== silent aim (mouse metatable hook)
local AIM = { installed = false, old_index = nil, mt = nil }

function AIM.install()
	if AIM.installed then return true end
	local ok = pcall(function()
		local mt = getrawmetatable(game)
		AIM.mt = mt
		AIM.old_index = mt.__index
		setreadonly(mt, false)
		rawset(mt, "__index", protect(function(self, key)
			local t = aim_target
			if STATE.silent_aim and t and t.part and t.part.Parent and self == MOUSE then
				if key == "Hit" then
					return CFrame.new(t.part.Position)
				elseif key == "Target" then
					return t.part
				elseif key == "UnitRay" then
					return Ray.new(CAMERA.CFrame.Position, (t.part.Position - CAMERA.CFrame.Position))
				end
			end
			return AIM.old_index(self, key)
		end))
		setreadonly(mt, true)
	end)
	AIM.installed = ok
	return ok
end

function AIM.remove()
	if not AIM.installed or not AIM.mt then return end
	pcall(function()
		setreadonly(AIM.mt, false)
		rawset(AIM.mt, "__index", AIM.old_index)
		setreadonly(AIM.mt, true)
	end)
	AIM.installed = false
end

local function target_rank(role)
	if STATE.target_mode == "Murderer first" then
		if role == "Murderer" then return 0 end
		if role == "Sheriff" then return 1 end
		return 2
	end
	if STATE.target_mode == "Sheriff first" then
		if role == "Sheriff" then return 0 end
		if role == "Murderer" then return 1 end
		return 2
	end
	return 0
end

local function pick_target()
	local me = local_role()
	local center = CAMERA.ViewportSize * 0.5
	local best, best_score = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP and is_alive(plr) then
			local char = char_of(plr)
			local head = char and char:FindFirstChild("Head")
			local role = role_of(plr)
			local skip = false
			if me == "Sheriff" and STATE.ignore_innocent and role == "Innocent" then skip = true end
			if not skip and head then
				local sp, on_screen = CAMERA:WorldToViewportPoint(head.Position)
				if on_screen and sp.Z > 0 then
					local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
					local dist = (CAMERA.CFrame.Position - head.Position).Magnitude
					if d <= STATE.fov and dist <= STATE.esp_distance then
						if (not STATE.wall_check) or part_visible(head) then
							local score = target_rank(role) * 100000 + d
							if score < best_score then
								best_score = score
								best = { plr = plr, part = head, role = role, screen_dist = d }
							end
						end
					end
				end
			end
		end
	end
	if STATE.only_with_gun then
		local held = LP.Character and (LP.Character:FindFirstChild("Gun") or LP.Character:FindFirstChild("Knife"))
		if not held then return nil end
	end
	return best
end

local function aim_hold_ok()
	if not STATE.aim_hold then return true end
	local key = Enum.KeyCode[STATE.aim_key]
	if not key then return true end
	return UserInputService:IsKeyDown(key)
end

--===================================================================== ESP
local function clear_esp()
	for _, obj in pairs(CACHE.highlights) do pcall(function() obj:Destroy() end) end
	for _, obj in pairs(CACHE.billboards) do pcall(function() obj:Destroy() end) end
	CACHE.highlights = {}
	CACHE.billboards = {}
end

local function ensure_esp(plr, char)
	local role = role_of(plr)
	local head = char:FindFirstChild("Head")
	local existing = CACHE.highlights[plr]
	if existing and existing.Parent ~= char then
		pcall(function() existing:Destroy() end)
		CACHE.highlights[plr] = nil
		existing = nil
	end
	if not existing then
		local hl = Instance.new("Highlight")
		hl.Name = "JakoESP"
		hl.DepthMode = STATE.chams and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
		hl.FillTransparency = 0.55
		hl.OutlineTransparency = 0.15
		hl.Parent = char
		CACHE.highlights[plr] = hl
		existing = hl
	end
	existing.FillColor = role_color(role)
	existing.OutlineColor = LILAC
	existing.DepthMode = STATE.chams and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
	existing.Enabled = STATE.esp_players

	local bb = CACHE.billboards[plr]
	if bb and bb.Parent ~= char then
		pcall(function() bb:Destroy() end)
		CACHE.billboards[plr] = nil
		bb = nil
	end
	if not bb then
		local gui = Instance.new("BillboardGui")
		gui.Name = "JakoESPText"
		gui.Size = UDim2.fromOffset(220, 34)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Tag"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 13
		label.TextStrokeTransparency = 0.45
		label.TextStrokeColor3 = BG
		label.TextColor3 = TEXT
		label.Parent = gui
		gui.Adornee = head
		gui.Parent = char
		CACHE.billboards[plr] = gui
		bb = gui
	end
	bb.Adornee = head
	bb.MaxDistance = STATE.esp_distance
	local label = bb:FindFirstChild("Tag")
	if label then
		local pieces = {}
		if STATE.esp_names then table.insert(pieces, plr.Name) end
		table.insert(pieces, role)
		if STATE.esp_distance_text and head then
			local dist = math.floor((CAMERA.CFrame.Position - head.Position).Magnitude)
			table.insert(pieces, tostring(dist) .. "m")
		end
		label.Text = table.concat(pieces, "  ")
		label.TextColor3 = role_color(role)
		label.Visible = true
	end
end

local function esp_step()
	if STATE.esp_players then
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LP then
				local char = char_of(plr)
				if char and is_alive(plr) and char:FindFirstChild("Head") then
					ensure_esp(plr, char)
				end
			end
		end
	end
	for plr, hl in pairs(CACHE.highlights) do
		if not plr.Parent or not char_of(plr) or not STATE.esp_players then
			pcall(function() hl:Destroy() end)
			CACHE.highlights[plr] = nil
			local bb = CACHE.billboards[plr]
			if bb then pcall(function() bb:Destroy() end) CACHE.billboards[plr] = nil end
		elseif not is_alive(plr) then
			hl.Enabled = false
			local bb = CACHE.billboards[plr]
			if bb then bb.Enabled = false end
		else
			local bb = CACHE.billboards[plr]
			if bb then bb.Enabled = true end
		end
	end
end

local function dropped_items()
	local out = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if (d:IsA("Tool") or d:IsA("Model")) and (d.Name == "Gun" or d.Name == "Knife") then
			if not holder_humanoid(d) and not d:IsDescendantOf(LP.Character) then
				local part = d:FindFirstChild("Handle") or d:FindFirstChildWhichIsA("BasePart")
				if part then table.insert(out, { inst = d, part = part, name = d.Name }) end
			end
		end
	end
	return out
end

local function item_esp_step()
	if not STATE.esp_items then
		for _, hl in pairs(CACHE.items or {}) do pcall(function() hl:Destroy() end) end
		CACHE.items = {}
		return
	end
	CACHE.items = CACHE.items or {}
	local live = {}
	for _, item in ipairs(dropped_items()) do
		live[item.part] = true
		local hl = CACHE.items[item.part]
		if not hl or hl.Parent ~= item.part then
			if hl then pcall(function() hl:Destroy() end) end
			hl = Instance.new("Highlight")
			hl.Name = "JakoItemESP"
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.FillColor = item.name == "Gun" and ICON or ACCENT
			hl.FillTransparency = 0.45
			hl.OutlineColor = LILAC
			hl.Parent = item.part
			CACHE.items[item.part] = hl
		end
	end
	for part, hl in pairs(CACHE.items) do
		if not live[part] or not part.Parent then
			pcall(function() hl:Destroy() end)
			CACHE.items[part] = nil
		end
	end
end

-- tracers need the executor Drawing API; silently skipped when absent
local DRAW_OK = pcall(function()
	local d = Drawing.new("Line")
	d:Remove()
end)

local function tracer_step()
	if not DRAW_OK then return end
	if not STATE.tracers then
		for _, t in pairs(CACHE.tracers) do pcall(function() t:Remove() end) end
		CACHE.tracers = {}
		return
	end
	local origin = Vector2.new(CAMERA.ViewportSize.X / 2, CAMERA.ViewportSize.Y)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP and is_alive(plr) then
			local head = char_of(plr):FindFirstChild("Head")
			if head then
				local sp, on_screen = CAMERA:WorldToViewportPoint(head.Position)
				local line = CACHE.tracers[plr]
				if not line then
					line = Drawing.new("Line")
					line.Thickness = 1
					line.Transparency = 1
					CACHE.tracers[plr] = line
				end
				line.From = origin
				line.To = Vector2.new(sp.X, sp.Y)
				line.Color = role_color(role_of(plr))
				line.Visible = on_screen
			end
		end
	end
end

--===================================================================== combat actions
local last_fire, last_stab, last_throw, last_grab = 0, 0, 0, 0
local THROW_HINTS = { "throw", "slash", "swing", "knife", "gun", "fire", "attack" }

local function resolve_throw_remote(tool)
	if STATE.throw_remote ~= "" then
		local direct = RS:FindFirstChild(STATE.throw_remote, true)
		if direct and (direct:IsA("RemoteEvent") or direct:IsA("RemoteFunction")) then return direct end
	end
	local scan_roots = { tool, RS }
	for _, root in ipairs(scan_roots) do
		if root then
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("RemoteEvent") then
					local n = d.Name:lower()
					for _, hint in ipairs(THROW_HINTS) do
						if n:find(hint, 1, true) then return d end
					end
				end
			end
		end
	end
	return nil
end

local function combat_step(now)
	local tool_gun = get_tool("Gun")
	local tool_knife = get_tool("Knife")

	if STATE.silent_aim and aim_hold_ok() then
		aim_target = pick_target()
	end
	if not STATE.silent_aim then aim_target = nil end

	if tool_gun and STATE.auto_fire and aim_target and now - last_fire >= STATE.fire_delay then
		last_fire = now
		pcall(function() tool_gun:Activate() end)
	end

	if tool_knife and STATE.auto_stab and now - last_stab >= 0.25 then
		local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= LP and is_alive(plr) then
					local head = char_of(plr):FindFirstChild("Head")
					if head and (head.Position - hrp.Position).Magnitude <= STATE.stab_range then
						aim_target = { plr = plr, part = head, role = role_of(plr), screen_dist = 0 }
						last_stab = now
						pcall(function() tool_knife:Activate() end)
						break
					end
				end
			end
		end
	end

	if STATE.auto_throw and aim_target and (tool_gun or tool_knife) and now - last_throw >= 0.35 then
		local remote = resolve_throw_remote(tool_gun or tool_knife)
		if remote then
			last_throw = now
			pcall(function()
				if remote:IsA("RemoteEvent") then remote:FireServer() else remote:InvokeServer() end
			end)
		end
	end

	if STATE.grab_gun and now - last_grab >= 0.4 and not (tool_gun or tool_knife) then
		last_grab = now
		local items = dropped_items()
		local pick = items[1]
		if pick then
			local prompt = pick.inst:FindFirstChildWhichIsA("ProximityPrompt", true)
			if prompt then
				pcall(function() fireproximityprompt(prompt) end)
			elseif STATE.grab_teleport then
				local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					pcall(function() hrp.CFrame = pick.part.CFrame * CFrame.new(0, 1.5, 0) end)
				end
			else
				local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local dir = (pick.part.Position - hrp.Position).Unit
					pcall(function() hrp.CFrame = CFrame.new(hrp.Position + dir * 2.2) end)
				end
			end
		end
	end
end

--===================================================================== movement
local fly_bv = nil
local function clear_fly()
	if fly_bv then pcall(function() fly_bv:Destroy() end) fly_bv = nil end
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then pcall(function() hum.PlatformStand = false end) end
end

local function movement_step()
	local char = LP.Character
	if not char then clear_fly() return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then return end

	if STATE.speed_enabled then
		if hum.WalkSpeed ~= STATE.speed_value then hum.WalkSpeed = STATE.speed_value end
	elseif ORIG.walk and hum.WalkSpeed ~= ORIG.walk then
		hum.WalkSpeed = ORIG.walk
	end

	if STATE.jump_enabled then
		if hum.UseJumpPower then hum.JumpPower = STATE.jump_value else hum.JumpHeight = STATE.jump_value / 7.5 end
	end

	if STATE.noclip then
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
		end
	end

	if STATE.fly then
		if not fly_bv or fly_bv.Parent ~= hrp then
			clear_fly()
			fly_bv = Instance.new("BodyVelocity")
			fly_bv.Name = "JakoFly"
			fly_bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
			fly_bv.P = 2500
			fly_bv.Velocity = Vector3.zero
			fly_bv.Parent = hrp
		end
		local move = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += CAMERA.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= CAMERA.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= CAMERA.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += CAMERA.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.yAxis end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.yAxis end
		if move.Magnitude > 0 then
			fly_bv.Velocity = move.Unit * STATE.fly_speed
		else
			fly_bv.Velocity = Vector3.zero
		end
	else
		clear_fly()
	end
end

--===================================================================== world
local function set_fullbright(on)
	if on then
		if not ORIG.lighting then
			ORIG.lighting = {
				Brightness = Lighting.Brightness,
				ClockTime = Lighting.ClockTime,
				Ambient = Lighting.Ambient,
				OutdoorAmbient = Lighting.OutdoorAmbient,
				FogEnd = Lighting.FogEnd,
			}
		end
		Lighting.Brightness = 2
		Lighting.ClockTime = 12
		Lighting.Ambient = Color3.fromRGB(178, 178, 178)
		Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
		Lighting.FogEnd = 100000
	elseif ORIG.lighting then
		Lighting.Brightness = ORIG.lighting.Brightness
		Lighting.ClockTime = ORIG.lighting.ClockTime
		Lighting.Ambient = ORIG.lighting.Ambient
		Lighting.OutdoorAmbient = ORIG.lighting.OutdoorAmbient
		Lighting.FogEnd = ORIG.lighting.FogEnd
		ORIG.lighting = nil
	end
end

--===================================================================== dumps (per-build derivation)
local function dump_remotes()
	local lines = {}
	for _, d in ipairs(RS:GetDescendants()) do
		if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
			table.insert(lines, d:GetFullName())
		end
	end
	print("[JakoScripts] remotes (" .. tostring(#lines) .. "):")
	for _, l in ipairs(lines) do print("  " .. l) end
	notify("Dump Remotes", tostring(#lines) .. " remote(s) printed to console", "eye")
end

local function dump_world()
	print("[JakoScripts] dropped items:")
	for _, item in ipairs(dropped_items()) do
		print("  " .. item.inst:GetFullName() .. "  class=" .. item.inst.ClassName)
	end
	print("[JakoScripts] tools held by players:")
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if char then
			for _, d in ipairs(char:GetChildren()) do
				if d:IsA("Tool") then print("  " .. plr.Name .. " -> " .. d.Name) end
			end
		end
	end
	notify("Dump World", "roles + drops printed to console", "eye")
end

--===================================================================== state re-apply (used by config load)
local function apply_state()
	if STATE.silent_aim then AIM.install() end
	set_fullbright(STATE.fullbright)
	if not STATE.fly then clear_fly() end
	if GUI_ROOT then GUI_ROOT.Enabled = true end
end

--===================================================================== config
local CONFIG_KEYS = {
	"silent_aim", "aim_key", "fov", "fov_circle", "target_mode", "wall_check", "ignore_innocent", "only_with_gun",
	"auto_fire", "fire_delay", "auto_stab", "stab_range", "auto_throw", "throw_remote", "grab_gun", "grab_teleport",
	"esp_players", "esp_items", "esp_distance", "esp_names", "esp_distance_text", "chams", "tracers", "fullbright",
	"speed_enabled", "speed_value", "jump_enabled", "jump_value", "inf_jump", "fly", "fly_speed", "noclip", "anti_afk",
	"ui_key", "vanta_skin",
}

local function file_api_ok()
	return typeof(writefile) == "function" and typeof(readfile) == "function"
end

local function save_config(name)
	if not file_api_ok() then
		notify("Config", "executor has no file API", "settings")
		return
	end
	local data = {}
	for _, k in ipairs(CONFIG_KEYS) do data[k] = STATE[k] end
	pcall(function()
		if typeof(isfolder) == "function" and not isfolder("JakoScripts") then makefolder("JakoScripts") end
		writefile("JakoScripts/" .. name .. ".json", HttpService:JSONEncode(data))
	end)
	notify("Config saved", name, "settings")
end

local function load_config(name)
	if not file_api_ok() then
		notify("Config", "executor has no file API", "settings")
		return
	end
	local raw
	pcall(function() raw = readfile("JakoScripts/" .. name .. ".json") end)
	if not raw then
		notify("Config", "not found: " .. name, "settings")
		return
	end
	local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok or typeof(data) ~= "table" then
		notify("Config", "corrupt: " .. name, "settings")
		return
	end
	for _, k in ipairs(CONFIG_KEYS) do
		if data[k] ~= nil then STATE[k] = data[k] end
	end
	apply_state()
	notify("Config loaded", name, "settings")
end

--===================================================================== UI — WindUI, VantaViolet theme
local WINDUI_SOURCES = {
	"https://github.com/Footagesus/WindUI/releases/latest/download/main.lua",
	"https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua",
}

local WindUI
for _, url in ipairs(WINDUI_SOURCES) do
	local ok, res = pcall(function() return loadstring(game:HttpGet(url))() end)
	if ok and typeof(res) == "table" then WindUI = res break end
end

if not WindUI then
	notify("JakoScripts", "WindUI failed to load — check executor HttpGet", "zap")
	return
end

local THEME = {
	Name = "VantaViolet",
	Accent = ACCENT,
	Accent2 = LILAC,
	Background = BG,
	Background2 = Color3.fromHex("#0B0B12"),
	Outline = STROKE,
	Outline2 = ROWBORD,
	Text = TEXT,
	Text2 = MUTED,
	Text3 = DIM,
	Placeholder = DIM,
	Icon = ICON,
	Selected = ROW,
	Hover = Color3.fromHex("#FFFFFF0A"),
	Button = TEXT,
	ButtonText = ONACC,
	ToggleOn = ACCENT,
	ToggleOff = SWOFF,
	SliderTrack = TRACK,
	SliderFill = ACCENT,
	accent = ACCENT,
	background = BG,
	text = TEXT,
	icon = ICON,
	toggleon = ACCENT,
	toggleoff = SWOFF,
	slidertrack = TRACK,
	sliderfill = ACCENT,
}
pcall(function() WindUI:AddTheme(THEME) end)
pcall(function() WindUI:AddTheme("VantaViolet", THEME) end)
pcall(function()
	WindUI.Themes = WindUI.Themes or {}
	WindUI.Themes.VantaViolet = THEME
end)

local screens_before = {}
do
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	if pg then
		for _, g in ipairs(pg:GetChildren()) do screens_before[g] = true end
	end
end

local WIN_ARGS = {
	Title = "JakoScripts",
	Icon = "target",
	Author = "— VANTA",
	Folder = "JakoScripts",
	Size = UDim2.fromOffset(480, 360),
	Transparent = true,
	TransparencyValue = 0.12,
	Theme = "VantaViolet",
	SideBarWidth = 150,
	HasOutline = true,
	User = { Enabled = false },
}

local function find_new_screengui()
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	if not pg then return nil end
	for _, g in ipairs(pg:GetChildren()) do
		if not screens_before[g] and g:IsA("ScreenGui") then return g end
	end
	return nil
end

local function purge_new_screenguis()
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	if not pg then return end
	for _, g in ipairs(pg:GetChildren()) do
		if not screens_before[g] then pcall(function() g:Destroy() end) end
	end
end

do
	local ok, win = pcall(function() return WindUI:CreateWindow(WIN_ARGS) end)
	if not ok or typeof(win) ~= "table" then
		purge_new_screenguis()
		WIN_ARGS.Theme = "Dark"
		ok, win = pcall(function() return WindUI:CreateWindow(WIN_ARGS) end)
	end
	if not ok or typeof(win) ~= "table" then
		notify("JakoScripts", "WindUI window failed — falling back to skin pass only", "zap")
		return
	end
	VANTA_WINDOW = win
end

GENV.JakoScripts = GENV.JakoScripts or {}
GENV.JakoScripts.window = VANTA_WINDOW

GUI_ROOT = find_new_screengui()

--===================================================================== VANTA glass skin pass
local function luminance(c) return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B end
local function saturated(c)
	local mx = math.max(c.R, c.G, c.B)
	local mn = math.min(c.R, c.G, c.B)
	return (mx - mn) > 0.18 and mx > 0.3
end

local function skin_one(d)
	pcall(function()
		if d:IsA("ImageLabel") or d:IsA("ImageButton") then
			local parent = d.Parent
			if parent and parent:IsA("GuiObject") and luminance(parent.BackgroundColor3) > 0.7 then
				d.ImageColor3 = ONACC
			else
				d.ImageColor3 = ICON
			end
		elseif d:IsA("TextLabel") or d:IsA("TextButton") then
			local lum = luminance(d.TextColor3)
			if d:IsA("TextButton") then
				if saturated(d.BackgroundColor3) then
					d.BackgroundColor3 = ACCENT
					d.TextColor3 = TEXT
				elseif luminance(d.BackgroundColor3) > 0.7 then
					d.BackgroundColor3 = TEXT
					d.TextColor3 = ONACC
				end
			end
			if d.TextColor3 ~= ONACC then
				if lum > 0.85 then d.TextColor3 = TEXT
				elseif lum > 0.45 then d.TextColor3 = MUTED
				else d.TextColor3 = DIM end
			end
			if d.Text:find("VANTA", 1, true) then
				d.Text = "— V A N T A"
				d.TextSize = 13
				d.TextColor3 = MUTED
				d.Font = Enum.Font.GothamMedium
			end
		elseif d:IsA("GuiObject") then
			if d.BackgroundTransparency < 0.99 then
				if saturated(d.BackgroundColor3) then
					d.BackgroundColor3 = ACCENT
				elseif luminance(d.BackgroundColor3) < 0.25 then
					d.BackgroundColor3 = d.BackgroundColor3:Lerp(BG, 0.72)
				end
			end
			local corner = d:FindFirstChildOfClass("UICorner")
			if corner then
				local h = d.AbsoluteSize.Y
				if h >= 46 then
					corner.CornerRadius = UDim.new(0, 12)
				elseif h >= 18 then
					corner.CornerRadius = UDim.new(0, 8)
				end
			end
			local stroke = d:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = STROKE
				stroke.Transparency = 1 - STROKE_A
				stroke.Thickness = 1
			end
			local grad = d:FindFirstChildOfClass("UIGradient")
			if grad then grad.Color = ColorSequence.new(SHINE, Color3.fromRGB(255, 255, 255)) end
		end
	end)
end

local function skin_all(root)
	if not root then return end
	for _, d in ipairs(root:GetDescendants()) do skin_one(d) end
end

if GUI_ROOT then
	skin_all(GUI_ROOT)
	CONN.skin = GUI_ROOT.DescendantAdded:Connect(function(d)
		if not STATE.vanta_skin then return end
		skin_one(d)
		if #d:GetDescendants() > 0 then skin_all(d) end
	end)
end

--===================================================================== FOV ring
local fov_ring = Instance.new("Frame")
fov_ring.Name = "JakoFOV"
fov_ring.AnchorPoint = Vector2.new(0.5, 0.5)
fov_ring.Position = UDim2.fromScale(0.5, 0.5)
fov_ring.BackgroundTransparency = 1
fov_ring.Visible = false
fov_ring.ZIndex = 5
fov_ring.Parent = LP:FindFirstChildOfClass("PlayerGui")
do
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = fov_ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT
	stroke.Thickness = 1
	stroke.Transparency = 0.25
	stroke.Parent = fov_ring
end

--===================================================================== UI helper (tolerates WindUI API drift)
local function call_first(obj, names, arg)
	for _, n in ipairs(names) do
		local m = obj[n]
		if typeof(m) == "function" then
			local ok, res = pcall(m, obj, arg)
			if ok then return res end
		end
	end
	return nil
end

local function make_tab(title, icon)
	return call_first(VANTA_WINDOW, { "Tab", "CreateTab" }, { Title = title, Icon = icon })
end

local function section(tab, title)
	if not tab then return nil end
	return call_first(tab, { "Section", "CreateSection" }, { Title = title })
end

local function toggle(sec, title, key, desc)
	if not sec then return end
	local arg = {
		Title = title,
		Desc = desc or "",
		Value = STATE[key],
		Callback = function(v)
			STATE[key] = v
			if key == "silent_aim" and v then AIM.install() end
			if key == "fullbright" then set_fullbright(v) end
			if key == "fly" and not v then clear_fly() end
		end,
	}
	call_first(sec, { "Toggle", "CreateToggle", "Checkbox" }, arg)
end

local function slider(sec, title, key, min, max, step)
	if not sec then return end
	call_first(sec, { "Slider", "CreateSlider" }, {
		Title = title,
		Value = STATE[key],
		Min = min,
		Max = max,
		Rounding = step or 1,
		Callback = function(v) STATE[key] = v end,
	})
end

local function dropdown(sec, title, key, values)
	if not sec then return end
	call_first(sec, { "Dropdown", "CreateDropdown" }, {
		Title = title,
		Values = values,
		Items = values,
		Value = STATE[key],
		Callback = function(v) STATE[key] = v end,
	})
end

local function button(sec, title, cb)
	if not sec then return end
	call_first(sec, { "Button", "CreateButton" }, { Title = title, Callback = cb })
end

local function input(sec, title, key, placeholder)
	if not sec then return end
	call_first(sec, { "Input", "Textbox", "TextBox", "InputText" }, {
		Title = title,
		Value = STATE[key],
		Placeholder = placeholder or "",
		InputPlaceholder = placeholder or "",
		Callback = function(v) STATE[key] = v end,
	})
end

local function keybind(sec, title, key, default)
	if not sec then return end
	call_first(sec, { "Keybind", "CreateKeybind" }, {
		Title = title,
		Value = STATE[key] or default,
		Callback = function(v)
			if typeof(v) == "table" and v.Key then
				STATE[key] = tostring(v.Key)
			else
				STATE[key] = tostring(v)
			end
		end,
	})
end

--===================================================================== tabs
local tab_combat = make_tab("Combat", "target")
local tab_visuals = make_tab("Visuals", "eye")
local tab_movement = make_tab("Movement", "zap")
local tab_config = make_tab("Config", "settings")

do -- Combat
	local aim = section(tab_combat, "Silent Aim")
	toggle(aim, "Silent Aim", "silent_aim", "hook mouse.Hit / Target / UnitRay")
	toggle(aim, "Hold To Aim", "aim_hold", "aim only while key is down")
	keybind(aim, "Aim Key", "aim_key", "LeftAlt")
	slider(aim, "FOV", "fov", 30, 600, 1)
	toggle(aim, "FOV Ring", "fov_circle")
	dropdown(aim, "Priority", "target_mode", { "Murderer first", "Sheriff first", "Nearest" })
	toggle(aim, "Wall Check", "wall_check", "skip targets behind geometry")
	toggle(aim, "Ignore Innocent", "ignore_innocent", "sheriff: never lock an innocent")
	toggle(aim, "Only With Tool", "only_with_gun")

	local auto = section(tab_combat, "Auto")
	toggle(auto, "Auto Fire", "auto_fire", "sheriff gun")
	slider(auto, "Fire Delay", "fire_delay", 0.05, 1, 0.01)
	toggle(auto, "Auto Stab", "auto_stab", "murderer knife")
	slider(auto, "Stab Range", "stab_range", 3, 20, 0.5)
	toggle(auto, "Auto Throw", "auto_throw")
	input(auto, "Throw Remote", "throw_remote", "exact RemoteEvent name (optional)")
	toggle(auto, "Gun Grabber", "grab_gun", "pick up dropped gun / knife")
	toggle(auto, "Grab: Teleport", "grab_teleport", "off = step toward item")

	local util = section(tab_combat, "Derivation")
	button(util, "Dump Remotes", dump_remotes)
	button(util, "Dump World", dump_world)
end

do -- Visuals
	local esp = section(tab_visuals, "ESP")
	toggle(esp, "Player ESP", "esp_players")
	toggle(esp, "Item ESP", "esp_items", "dropped gun / knife")
	toggle(esp, "Chams (Always On Top)", "chams")
	toggle(esp, "Names", "esp_names")
	toggle(esp, "Distance", "esp_distance_text")
	toggle(esp, "Tracers", "tracers", "2D lines, needs Drawing")
	slider(esp, "Max Distance", "esp_distance", 50, 2000, 10)

	local world = section(tab_visuals, "World")
	toggle(world, "Fullbright", "fullbright")
end

do -- Movement
	local mv = section(tab_movement, "Speed")
	toggle(mv, "WalkSpeed", "speed_enabled")
	slider(mv, "Speed", "speed_value", 16, 250, 1)
	toggle(mv, "JumpPower", "jump_enabled")
	slider(mv, "Jump", "jump_value", 50, 300, 1)
	toggle(mv, "Infinite Jump", "inf_jump")

	local fly = section(tab_movement, "Fly")
	toggle(fly, "Fly", "fly", "Space up / LeftControl down")
	slider(fly, "Fly Speed", "fly_speed", 10, 400, 5)
	toggle(fly, "Noclip", "noclip")
	toggle(fly, "Anti-AFK", "anti_afk")
end

do -- Config
	local cfg = section(tab_config, "Profile")
	input(cfg, "Name", "config_name", "default")
	button(cfg, "Save", function() save_config(STATE.config_name) end)
	button(cfg, "Load", function() load_config(STATE.config_name) end)

	local ui = section(tab_config, "Interface")
	toggle(ui, "Vanta Skin", "vanta_skin", "re-apply glass palette")
	keybind(ui, "UI Toggle", "ui_key", "RightShift")
	button(ui, "Rejoin", function()
		pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP) end)
	end)
	button(ui, "Unload", function() VANTA.unload() end)
end

pcall(function() VANTA_WINDOW:SelectTab(1) end)

--===================================================================== loops
local last_esp, last_items, last_tracer = 0, 0, 0

CONN.render = RunService.RenderStepped:Connect(function(dt)
	if UNLOADED then return end
	local now = os.clock()
	combat_step(now)
	movement_step()
	if aim_target and STATE.fov_circle then
		fov_ring.Visible = true
		fov_ring.Size = UDim2.fromOffset(STATE.fov * 2, STATE.fov * 2)
	else
		fov_ring.Visible = false
	end
	if now - last_esp >= 0.2 then
		last_esp = now
		esp_step()
	end
	if now - last_items >= 0.5 then
		last_items = now
		item_esp_step()
	end
	if now - last_tracer >= 0.05 then
		last_tracer = now
		tracer_step()
	end
	if ORIG.walk == nil and LP.Character then
		local hum = LP.Character:FindFirstChildOfClass("Humanoid")
		if hum then ORIG.walk = hum.WalkSpeed end
	end
end)

CONN.char = LP.CharacterAdded:Connect(function()
	aim_target = nil
	clear_fly()
	ORIG.walk = nil
	task.wait(0.5)
	notify("Round", "role: " .. local_role(), "target")
	if STATE.noclip then
		local char = LP.Character
		if char then
			for _, p in ipairs(char:GetDescendants()) do
				if p:IsA("BasePart") then p.CanCollide = false end
			end
		end
	end
end)

CONN.jump = UserInputService.JumpRequest:Connect(function()
	if STATE.inf_jump and not UNLOADED then
		local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
		if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end) end
	end
end)

CONN.key = UserInputService.InputBegan:Connect(function(inp, processed)
	if processed or UNLOADED then return end
	if UserInputService:GetFocusedTextBox() then return end
	local want = Enum.KeyCode[STATE.ui_key]
	if want and inp.KeyCode == want and GUI_ROOT then
		GUI_ROOT.Enabled = not GUI_ROOT.Enabled
		notify("Interface", GUI_ROOT.Enabled and "shown" or "hidden", "settings")
	end
end)

CONN.idle = LP.Idled:Connect(function()
	if STATE.anti_afk and not UNLOADED then
		pcall(function()
			local vu = game:GetService("VirtualUser")
			vu:CaptureController()
			vu:ClickButton2(Vector2.new())
		end)
	end
end)

--===================================================================== unload
function VANTA.unload()
	if UNLOADED then return end
	UNLOADED = true
	AIM.remove()
	clear_fly()
	set_fullbright(false)
	clear_esp()
	for _, hl in pairs(CACHE.items or {}) do pcall(function() hl:Destroy() end) end
	for _, t in pairs(CACHE.tracers) do pcall(function() t:Remove() end) end
	for _, c in pairs(CONN) do pcall(function() c:Disconnect() end) end
	pcall(function() fov_ring:Destroy() end)
	pcall(function()
		if VANTA_WINDOW and typeof(VANTA_WINDOW.Destroy) == "function" then VANTA_WINDOW:Destroy() end
	end)
	pcall(function() if GUI_ROOT then GUI_ROOT:Destroy() end end)
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and ORIG.walk then hum.WalkSpeed = ORIG.walk end
	GENV.JakoScripts = nil
	print("[JakoScripts] unloaded")
end

GENV.JakoScripts = GENV.JakoScripts or {}
GENV.JakoScripts.state = STATE
GENV.JakoScripts.unload = VANTA.unload
GENV.JakoScripts.dump = { remotes = dump_remotes, world = dump_world }

notify("JakoScripts", "loaded — " .. tostring(#Players:GetPlayers()) .. " players, right shift toggles UI", "zap")
print("[JakoScripts] v" .. VANTA.version .. " ready — " .. STATE.ui_key .. " toggles the interface")
