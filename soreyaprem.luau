local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local StarterGui         = game:GetService("StarterGui")
local CoreGui            = game:GetService("CoreGui")
local ContentProvider    = game:GetService("ContentProvider")
local VirtualUser        = game:GetService("VirtualUser")
local HttpService        = game:GetService("HttpService")
local Stats              = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

local INSTANCE_KEY = "__CHOCO_SOREYAPREMIUM_v100"


if _G[INSTANCE_KEY] then
    local prev = _G[INSTANCE_KEY]
    _G[INSTANCE_KEY] = { booting = true }
    if type(prev.cleanup) == "function" then pcall(prev.cleanup) end

    local waited = 0
    while prev.running and waited < 2 do task.wait(0.1); waited = waited + 0.1 end
    task.wait(0.2)
end


pcall(function()
    if getrawmetatable and _G.X0_OrigNamecall then
        local mt = getrawmetatable(game)
        if mt and mt.__namecall ~= _G.X0_OrigNamecall then
            if setreadonly then pcall(setreadonly, mt, false) end
            mt.__namecall = _G.X0_OrigNamecall
            if setreadonly then pcall(setreadonly, mt, true) end
            print("[MTSOREYA] restored original __namecall (cleared a leftover hook)")
        end
    end
end)

local _t0 = os.clock()
local function Log(m) print(string.format("[MTSOREYA][+%.2fs] %s", os.clock() - _t0, tostring(m))) end
local function Err(m, d) warn(string.format("[MTSOREYA][+%.2fs] ERROR: %s | %s", os.clock() - _t0, tostring(m), tostring(d or ""))) end


local ConnMgr = { conns = {} }
function ConnMgr:Add(conn) table.insert(self.conns, conn); return conn end
function ConnMgr:Clear() for _, c in ipairs(self.conns) do pcall(function() c:Disconnect() end) end; self.conns = {} end

local function Char() return LocalPlayer.Character end
local function Hum() local c = Char(); return c and c:FindFirstChildOfClass("Humanoid") end


local function IsMobile()
    local ok, v = pcall(function()
        return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
    end)
    if ok and v then return true end
    local ok2, v2 = pcall(function()
        return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    end)
    return (ok2 and v2) or false
end

local function IsGamepad()
    local ok, v = pcall(function() return UserInputService.GamepadEnabled end)
    return (ok and v) or false
end

local function IsPC()
    return not IsMobile()
end


local function MoveInput(hum)
    local fwd, right = 0, 0

    if IsPC() and UserInputService.KeyboardEnabled then

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then fwd = fwd + 1 end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then fwd = fwd - 1 end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then right = right + 1 end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then right = right - 1 end
    end

    if fwd == 0 and right == 0 and IsGamepad() then
        pcall(function()
            local st = UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
            for _, a in ipairs(st) do
                if a.KeyCode == Enum.KeyCode.Thumbstick1 then
                    fwd   = fwd + a.Position.Y
                    right = right + a.Position.X
                end
            end
        end)
    end

    if fwd == 0 and right == 0 and hum then


        local md = hum.MoveDirection
        if md and md.Magnitude > 0 then
            local cam = Camera or workspace.CurrentCamera
            local cf = cam and cam.CFrame
            if cf then
                local look  = Vector3.new(cf.LookVector.X,  0, cf.LookVector.Z)
                local side  = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
                local mv    = Vector3.new(md.X, 0, md.Z)
                if look.Magnitude > 0.001 then fwd   = fwd   + mv:Dot(look.Unit) end
                if side.Magnitude > 0.001 then right = right + mv:Dot(side.Unit) end
            end
        end
    end

    fwd   = math.clamp(fwd,   -1, 1)
    right = math.clamp(right, -1, 1)
    return fwd, right
end


local WindUI
do
    local ok, res = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
    end)
    if not ok or not res then error("[MTSOREYA] WindUI load failed: " .. tostring(res)) end
    WindUI = res
end

local HUB = {
    Name = "Choco HUB Premium", Game = "Mount Soreya", Version = "0.0.1",
    Author = "", LogoId = "rbxassetid://122666578965463",
}

local function GuiParent()
    local p = CoreGui
    pcall(function() if gethui then p = gethui() end end)
    return p
end

local function Notify(title, content, dur)


    if _G.X0_MTS_SummitNotifyOff and tostring(title) == "Auto Summit" then return end
    pcall(function()
        WindUI:Notify({ Title = tostring(title), Content = tostring(content), Duration = tonumber(dur) or 3 })
    end)
end


local Rod = {
    Tool        = nil,
    CastEvent   = nil,
    MiniGame    = nil,
    NotifyC     = nil,
    Marker      = nil,
    MiniGameActive = nil,
    LastBite    = 0,
    Reeling     = false,
}


local function HasCastRemote(t)
    if not (t and t:IsA("Tool")) then return false end
    for _, d in ipairs(t:GetDescendants()) do
        if d.Name == "CastEvent" then return true end
    end
    return false
end
local function IsRodTool(t)
    if not (t and t:IsA("Tool")) then return false end
    return HasCastRemote(t) or t.Name:lower():find("rod") ~= nil
end


local function getRodTool()
    local c  = Char()
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    local sources = { c, bp }

    for _, src in ipairs(sources) do
        if src then
            for _, t in ipairs(src:GetChildren()) do
                if HasCastRemote(t) then return t end
            end
        end
    end

    for _, src in ipairs(sources) do
        if src then
            for _, t in ipairs(src:GetChildren()) do
                if IsRodTool(t) then return t end
            end
        end
    end
    return nil
end

local function getMechanicsRemotes()
    local tool = getRodTool()
    if not tool then return nil end
    local mech = tool:FindFirstChild("Mechanics")
    local rem  = mech and mech:FindFirstChild("Remotes")
    if not rem then

        for _, d in ipairs(tool:GetDescendants()) do
            if d.Name == "Remotes" then rem = d; break end
        end
    end
    return rem
end


local function DiscoverRod()
    local tool = getRodTool()
    local changed = (tool ~= Rod.Tool)
    Rod.Tool = tool
    local rem = getMechanicsRemotes()
    if rem then
        local ce = rem:FindFirstChild("CastEvent")
        local mg = rem:FindFirstChild("MiniGame")
        local nc = rem:FindFirstChild("NotifyClient")
        if ce then Rod.CastEvent = ce end
        if mg then Rod.MiniGame  = mg end
        if nc then Rod.NotifyC   = nc end
    elseif changed then

        Rod.CastEvent, Rod.MiniGame, Rod.NotifyC = nil, nil, nil
    end
    Rod.Marker = ReplicatedStorage:FindFirstChild("TandaSeruBersama") or Rod.Marker

    if tool then
        local mech = tool:FindFirstChild("Mechanics")
        local st = mech and mech:FindFirstChild("Status")
        local b = st and st:FindFirstChild("MiniGameActive")
        Rod.MiniGameActive = (b and b:IsA("BoolValue")) and b or nil
    else
        Rod.MiniGameActive = nil
    end
    if changed and tool then
        pcall(function() print("[MTSOREYA] active rod -> " .. tool.Name) end)
    end
    return Rod.CastEvent and Rod.MiniGame
end


local Game = { MiniGame = nil, PowerBar = nil, AutoFish = nil, Tier = nil, FishDB = nil, ok = false, tried = false }

local function LoadGameModules()
    if Game.tried then return Game end
    Game.tried = true
    local mods = ReplicatedStorage:FindFirstChild("Modules")
    local fish = mods and mods:FindFirstChild("Fishing")
    if not fish then return Game end


    local sharedRequire = require
    pcall(function()
        if getrenv and type(getrenv) == "function" then
            local renv = getrenv()
            if type(renv.require) == "function" then sharedRequire = renv.require end
        end
    end)
    local function req(name)
        local inst = fish:FindFirstChild(name)
        if not inst then return nil end
        local ok, res = pcall(sharedRequire, inst)
        if not ok or res == nil then
            ok, res = pcall(require, inst)
        end
        return ok and res or nil
    end
    Game.MiniGame = req("MiniGameHandler")
    Game.PowerBar = req("PowerBarHandler")
    Game.AutoFish = req("AutoFishingModule")
    Game.Tier     = req("TierIkan")
    Game.FishDB   = req("FishingImageDatabase")
    Game.ok = (Game.MiniGame ~= nil)
    return Game
end


local function GameReeling()
    LoadGameModules()
    local mg = Game.MiniGame
    if mg and mg.IsActive then
        local ok, active = pcall(mg.IsActive)
        if ok and active then return true end
    end


    DiscoverRod()
    local b = Rod.MiniGameActive
    if b and b.Parent then return b.Value and true or false end
    if mg and mg.IsActive then
        local ok = pcall(mg.IsActive)
        if ok then return false end
    end
    return nil
end


local FishingGUI = nil
local function GetFishingGui()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    FishingGUI = pg:FindFirstChild("Fishing") or FishingGUI
    if FishingGUI and not FishingGUI.Parent then FishingGUI = nil end
    return FishingGUI
end

local function GetReelBars()
    local gui = GetFishingGui()
    if not gui then return nil, nil end


    local leftBar, rightBar
    local fallback = {}
    for _, d in ipairs(gui:GetDescendants()) do
        if d:IsA("GuiObject") and d.Name == "Bar" then
            local p = d.Parent
            local pn = p and p.Name:lower() or ""
            if pn == "left" then leftBar = d
            elseif pn == "right" then rightBar = d
            else fallback[#fallback + 1] = d end
        end
    end

    if not leftBar and not rightBar then
        leftBar = fallback[1]
        rightBar = fallback[2] or fallback[1]
    end
    return leftBar, rightBar
end


local function ReelFill()
    local l, r = GetReelBars()
    if not l and not r then return nil end
    local f = 0
    if l then f = math.max(f, l.Size.X.Scale) end
    if r then f = math.max(f, r.Size.X.Scale) end
    return f
end

local function IsReeling()


    local g = GameReeling()
    if g ~= nil then return g end
    local gui = GetFishingGui()
    if not gui or not gui.Enabled then return false end


    local main = gui:FindFirstChild("Main")
    if not main then return false end

    local l, r = GetReelBars()
    if (l and l.Visible) or (r and r.Visible) then return true end

    for _, d in ipairs(gui:GetDescendants()) do
        if d.Name == "ClickCount" and d.Visible then return true end
    end
    return ReelFill() ~= nil
end


local Auto = {
    Enabled       = false,

    AutoCast      = true,
    AutoClaim     = true,
    ClaimDelay    = 0.45,


    FastRecast    = true,
    CastSettle    = 0.0,

    CastPower     = 20,

    PerfectCast   = true,
    HideReelUI    = true,

    InstantAlert  = true,


    FastBite      = true,


    AutoShowMarker = false,
    Adaptive      = true,
    LineActive    = false,
    LastCast      = 0,
    Busy          = false,
    LoopStop      = false,


    SuperFast     = true,


    Ultra         = true,


    CaughtNotify  = true,


    LearnedClaim  = nil,
    MinClaim      = 0.10,
    MaxClaim      = 1.45,
    ClaimStart    = 0.15,


}


local function AutoActive()
    return Auto.Enabled
end


local StartAuto, StopAuto, ReelOnce, HookSendCatch


local LearnClaim

local function FireCast()
    DiscoverRod()
    if not Rod.CastEvent then return false, "no_cast_remote" end


    local look = Camera.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.001 then flat = Vector3.new(0, 0, -1) end
    flat = flat.Unit


    local power = Auto.CastPower or 20
    if Auto.PerfectCast then
        LoadGameModules()
        local pb = Game.PowerBar
        if pb and pb.StopFill then
            local okp, fill = pcall(pb.StopFill)
            if okp and tonumber(fill) and tonumber(fill) > 0 then
                power = math.max(power, math.min(tonumber(fill), 100))
            end
        end
    elseif Auto.FastBite then
        LoadGameModules()
        local pb = Game.PowerBar
        if pb and pb.MIN_POWER then power = tonumber(pb.MIN_POWER) or 20 end
    end

    local ok1 = pcall(function() Rod.CastEvent:FireServer(true) end)
    local ok2 = pcall(function() Rod.CastEvent:FireServer(false, power, flat) end)
    Auto.LastCast = tick()
    if ok1 and ok2 then return true, "cast" end
    return ok1, ok1 and "cast_partial" or "cast_error"
end


local DestroyAlert
local function EndLine()
    if not Auto.LineActive then return end
    Auto.LineActive = false
    DestroyAlert()


    if AutoActive() and Auto.AutoCast and Auto.FastRecast then
        Auto.LastCast = tick()
        task.spawn(function()
            if AutoActive() and not Auto.CastInFlight then
                Auto.CastInFlight = true
                FireCast()
                Auto.CastInFlight = false
            end
        end)
    end
end


_G.X0_MTS_LastClaimedBite = _G.X0_MTS_LastClaimedBite or -1
local function FireClaim(_force)
    return false, "no_claim_remote"
end

local function FireClaimVariant()
    return false, "no_claim_remote"
end
_G.X0_MTS_FireClaimVariant = FireClaimVariant


local function ClaimWaitForBite()
    local lo = Auto.MinClaim or 0.10
    if Auto.SuperFast then lo = math.min(lo, 0.08) end
    if Auto.Ultra then lo = 0.02 end
    if Auto.Adaptive and Auto.LearnedClaim then
        return math.clamp(Auto.LearnedClaim, lo, Auto.MaxClaim or 1.45)
    end
    if Auto.Adaptive then
        local startPt = Auto.ClaimStart or 0.15
        if Auto.Ultra then startPt = math.min(startPt, 0.05) end
        return math.clamp(startPt, lo, Auto.MaxClaim or 1.45)
    end
    local base = Auto.ClaimDelay or 0.15
    if Auto.SuperFast then base = math.min(base, 0.12) end
    if Auto.Ultra then base = math.min(base, 0.05) end
    return math.clamp(base, lo, Auto.MaxClaim or 1.45)
end
_G.X0_MTS_ClaimWaitForBite = ClaimWaitForBite


LearnClaim = function(success)
    if not Auto.Adaptive then return end
    local used = Auto.LastClaimWait or Auto.LearnedClaim or Auto.ClaimStart or 0.45


    local down = Auto.Ultra and 0.10 or (Auto.SuperFast and 0.06 or 0.03)
    local up   = Auto.Ultra and 0.04 or (Auto.SuperFast and 0.05 or 0.08)
    local floor = Auto.Ultra and 0.03 or (Auto.SuperFast and 0.15 or (Auto.MinClaim or 0.30))
    if success then
        Auto.LearnedClaim = math.max(floor, used - down)
    else
        Auto.LearnedClaim = math.min((Auto.MaxClaim or 1.45), used + up)
    end
end
_G.X0_MTS_LearnClaim = LearnClaim


ReelOnce = function(mgData)
    LoadGameModules()
    local mg = Game.MiniGame
    local start = tick()
    Auto.BiteAt = Rod.LastBite or start
    Auto.CaughtAt = nil


    local biteAt = Rod.LastBite or start
    local deadline = biteAt + 3.0
    local haveTap = (mg and type(mg.MobileTap) == "function")


    local openDeadline = biteAt + 0.6
    local opened = false
    while AutoActive() and tick() < openDeadline do
        if Auto.CaughtAt then return true, "landed" end
        if IsReeling() then opened = true break end
        RunService.Heartbeat:Wait()
    end


    if not opened and not IsReeling() then return false, "no_reel" end


    if haveTap then
        pcall(function()
            if mg.IsActive and mg.IsActive() then return end
            if mg.Setup then pcall(mg.Setup, Rod.Tool) end
            local difficulty, speed, meta
            if type(mgData) == "number" then
                difficulty = mgData
            elseif type(mgData) == "table" then
                difficulty = tonumber(mgData.difficulty) or 1
                speed      = tonumber(mgData.speed) or 0
                if mgData.sizeLabel or mgData.weight then
                    meta = {
                        sizeLabel = mgData.sizeLabel or "Medium",
                        weight    = mgData.weight or 1,
                        rarity    = mgData.rarity or "Common",
                        name      = mgData.name,
                        chance    = tonumber(mgData.chance),
                    }
                end
            end
            if mg.Start then pcall(mg.Start, difficulty or 1, speed or 0, meta) end
        end)
    end


    if haveTap then
        local burst = Auto.Ultra and 6 or (Auto.SuperFast and 4 or 2)
        while AutoActive() and tick() < deadline do
            if Auto.CaughtAt then return true, "landed" end
            for _ = 1, burst do pcall(mg.MobileTap) end
            if IsReeling() == false then return Auto.CaughtAt ~= nil, "reel_closed" end
            RunService.RenderStepped:Wait()
        end
        if Auto.CaughtAt then return true, "landed" end
    end


    while AutoActive() and tick() < deadline do
        if Auto.CaughtAt then return true, "landed" end
        if IsReeling() == false and tick() > biteAt + 0.5 then return false, "no_engine" end
        RunService.RenderStepped:Wait()
    end
    return Auto.CaughtAt ~= nil, "timeout"
end

_G.X0_MTS_Reel = ReelOnce


local function HideReelUI()
    if not (AutoActive() and Auto.HideReelUI) then return end
    local gui = GetFishingGui()
    if not gui then return end


    local main = gui:FindFirstChild("Main")
    if main and main:IsA("GuiObject") then
        pcall(function() main.Visible = false end)
    else
        pcall(function() gui.Enabled = false end)
    end
end


ConnMgr:Add(RunService.Heartbeat:Connect(function(dt)
    if not AutoActive() then return end
    if Auto.HideReelUI and Auto.LineActive then HideReelUI() end
end))


local Alert = { Gui = nil, Gen = 0 }

function DestroyAlert()
    if Alert.Gui then pcall(function() Alert.Gui:Destroy() end) end
    Alert.Gui = nil
end


local MarkerRemote = nil
local function GetMarkerRemote()
    local m = MarkerRemote or Rod.Marker
    if m and m.Parent then
        MarkerRemote = m
        return m
    end
    m = ReplicatedStorage:FindFirstChild("TandaSeruBersama")
    if not m then
        DiscoverRod()
        m = Rod.Marker
    end
    if m and m:IsA("RemoteEvent") then
        MarkerRemote = m
        Rod.Marker = m
    end
    return MarkerRemote
end

local RED = Color3.fromRGB(255, 70, 70)

local function FireSharedMarker()
    local m = GetMarkerRemote()
    if not m then return end


    local dur = Auto.Ultra and 1.0 or 1.5
    local ok = pcall(function()
        m:FireServer(RED, RED, ColorSequence.new(RED), dur)
    end)
    if not ok then
        pcall(function()
            m:FireServer(RED, RED, NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(1, 1),
            }), dur)
        end)
    end
end


local function FireSharedMarkerFast()
    local m = GetMarkerRemote()
    if not m then return end
    task.spawn(function()
        local dur = Auto.Ultra and 1.0 or 1.5
        pcall(function() m:FireServer(RED, RED, ColorSequence.new(RED), dur) end)
    end)
end

local function ShowBiteAlert()
    if not Auto.InstantAlert then return end


    local char = Char()
    local head = char and char:FindFirstChild("Head")
    if not head then return end
    DestroyAlert()
    local bg = Instance.new("BillboardGui")
    bg.Name = "ChocoBiteAlert"
    bg.Size = UDim2.fromOffset(64, 64)
    bg.StudsOffset = Vector3.new(0, 2.8, 0)
    bg.AlwaysOnTop = true
    bg.Adornee = head
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.fromScale(1, 1)
    lbl.BackgroundTransparency = 1
    lbl.Text = "!"
    lbl.TextColor3 = Color3.fromRGB(255, 60, 60)
    lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    lbl.TextStrokeTransparency = 0
    lbl.TextScaled = true
    lbl.Font = Enum.Font.FredokaOne
    lbl.Parent = bg
    bg.Parent = head
    Alert.Gui = bg
    Alert.Gen = Alert.Gen + 1
    local gen = Alert.Gen
    task.delay(1.6, function()
        if Alert.Gen == gen then DestroyAlert() end
    end)
end


local AutoMarker = { Running = false }
_G.X0_MTS_AutoMarker = AutoMarker

function AutoMarker.Stop() AutoMarker.Running = false end
function AutoMarker.Start() AutoMarker.Running = true end
AutoMarker.Set = function(v) AutoMarker.Running = (v == true) end


local BaitFix = { On = true, Mod = nil, OrigLempar = nil, OrigDive = nil }

local function BaitLandPoint(tool)
    local char = Char()
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local fallback = hrp and (hrp.CFrame * CFrame.new(0, 0, -12)).Position or nil
    if tool then
        local mech = tool:FindFirstChild("Mechanics")
        local cfg = mech and mech:FindFirstChild("Configuration")
        local st = cfg and st:FindFirstChild("Status")
        local bp = st and st:FindFirstChild("BaitPosition")
        if bp and bp:IsA("Vector3Value") and bp.Value.Magnitude > 0 then
            return bp.Value
        end
    end
    return fallback
end


local function SlamVFX(model, pos)
    if not (model and model.Parent and pos) then return end
    local goal = CFrame.new(pos)
    pcall(function()
        if model:IsA("Model") then
            model:PivotTo(goal)
        elseif model:IsA("BasePart") then
            model.CFrame = goal
        end
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                d.AssemblyLinearVelocity = Vector3.zero
                d.AssemblyAngularVelocity = Vector3.zero
                d.CanCollide = false
            end
        end
    end)
end

local function InstallBaitPatch()
    if BaitFix.Mod then return end
    local ok, mod = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Fishing"):WaitForChild("EfekLempar"))
    end)
    if not ok or type(mod) ~= "table" then return end
    BaitFix.Mod = mod
    if type(mod.Lempar) == "function" then
        local orig = mod.Lempar
        BaitFix.OrigLempar = orig
        mod.Lempar = function(tool, character, player)


            local before = {}
            if AutoActive() and BaitFix.On then
                for _, c in ipairs(workspace:GetChildren()) do before[c] = true end
            end
            local r = { orig(tool, character, player) }
            if AutoActive() and BaitFix.On then
                local pos = BaitLandPoint(tool)
                if pos then


                    task.spawn(function()
                        local deadline = tick() + 0.35
                        local tracked
                        while tick() < deadline do
                            if not AutoActive() then return end
                            if tracked and tracked.Parent then
                                SlamVFX(tracked, pos)
                            else
                                tracked = nil
                                for _, c in ipairs(workspace:GetChildren()) do
                                    if not before[c] and (c:IsA("Model") or c:IsA("BasePart")) then
                                        tracked = c
                                        SlamVFX(c, pos)
                                        break
                                    end
                                end
                            end
                            RunService.Stepped:Wait()
                        end
                    end)
                end
            end
            return table.unpack(r)
        end
    end
    if type(mod.Dive) == "function" then
        BaitFix.OrigDive = mod.Dive
    end
    _G.X0_MTS_BaitFix = BaitFix
end

local function UninstallBaitPatch()
    local mod = BaitFix.Mod
    if mod and BaitFix.OrigLempar then
        pcall(function() mod.Lempar = BaitFix.OrigLempar end)
    end
    BaitFix.Mod = nil
    BaitFix.OrigLempar = nil
    BaitFix.OrigDive = nil
end


StartAuto = function()
    if Auto.Busy then return end
    Auto.Busy = true
    Auto.LoopStop = false
    task.spawn(function()
        local lastNoRod = 0


        while not Auto.LoopStop do
            if not AutoActive() then
                Auto.LineActive = false
                task.wait(0.2)
            else
                DiscoverRod()
                if not Rod.Tool then
                    if tick() - lastNoRod > 8 then
                        lastNoRod = tick()
                        Notify("Choco Hub", "Equip ANY fishing rod to start", 4)
                    end
                    task.wait(1)
                else
                    local poll = Auto.Ultra and 0.002 or (Auto.SuperFast and 0.01 or 0.03)


                    local castThrottle = Auto.Ultra and 0 or (Auto.SuperFast and 0.05 or 0.35)
                    if Auto.LineActive or IsReeling() then


                        if Auto.LineActive and (tick() - Rod.LastBite) > 3 then
                            Auto.LineActive = false
                        end
                        task.wait(poll)
                    elseif Auto.AutoCast and (tick() - Auto.LastCast > castThrottle) then


                        if not Auto.CastInFlight then
                            Auto.CastInFlight = true
                            FireCast()
                            Auto.CastInFlight = false
                        end
                        task.wait(poll)
                    else

                        task.wait(poll)
                    end
                end
            end
        end
        Auto.Busy = false
    end)
end

StopAuto = function()


    Auto.LineActive = false
    pcall(DestroyAlert)
    local gui = GetFishingGui()
    if gui then
        pcall(function() gui.Enabled = true end)
        local main = gui:FindFirstChild("Main")
        if main and main:IsA("GuiObject") then pcall(function() main.Visible = true end) end
    end
end
_G.X0_MTS_Auto = Auto
_G.X0_MTS_FireCast = FireCast
_G.X0_MTS_FireClaim = FireClaim


local BiteConns = {}
local function ClearBiteConns()
    for _, c in ipairs(BiteConns) do pcall(function() c:Disconnect() end) end
    BiteConns = {}
end
local function InstallBiteWatch()
    DiscoverRod()
    ClearBiteConns()
    if Rod.NotifyC then
        table.insert(BiteConns, Rod.NotifyC.OnClientEvent:Connect(function(kind, data)
            if kind == "Bite" then
                Rod.LastBite = tick()
            elseif kind == "CastFailed" then
                Auto.LastCast = tick()
            elseif kind == "GotFish" then
                Auto.CaughtAt = tick()
                if Auto.CaughtNotify then
                    Notify("Fishing", "Caught: " .. tostring(data and (data.originalName or data.baseName) or "fish"), 3)
                end

                if HookSendCatch and data then pcall(HookSendCatch, data) end
            end
        end))
    end
    if Rod.MiniGame then
        table.insert(BiteConns, Rod.MiniGame.OnClientEvent:Connect(function(state)
            if state == "Start" then
                Rod.LastBite = tick()
            end
        end))
    end
end


local ReelConns = {}
local function ClearReelConns()
    for _, c in ipairs(ReelConns) do pcall(function() c:Disconnect() end) end
    ReelConns = {}
end

local function OnBite(data)


    if Auto.AutoShowMarker then FireSharedMarkerFast() end


    local now = tick()
    local debounce = Auto.Ultra and 0.25 or 0.5
    if now - (Rod.LastOnBite or 0) < debounce then return end
    Rod.LastOnBite = now
    Rod.LastBite = now
    if AutoActive() then Auto.LineActive = true end
    ShowBiteAlert()
    if AutoActive() and Auto.HideReelUI then HideReelUI() end

    if not (AutoActive() and Auto.AutoClaim) then return end


    task.spawn(function() ReelOnce(data) end)
end

local function InstallReelHook()
    DiscoverRod()
    ClearReelConns()

    if Rod.MiniGame then
        table.insert(ReelConns, Rod.MiniGame.OnClientEvent:Connect(function(state, data)
            if state == "Start" then
                OnBite(data)
            elseif state == "Stop" then
                EndLine()
            end
        end))
    end


    if Rod.NotifyC then
        table.insert(ReelConns, Rod.NotifyC.OnClientEvent:Connect(function(kind, data)
            if kind == "Bite" then
                OnBite(data)
            elseif kind == "GotFish" then
                EndLine()
            elseif kind == "CastFailed" then

                Auto.LastCast = tick()
            end
        end))
    end
end


local State = {
    FloatingLogo     = true,
    LogoGui          = nil,
    LogoImage        = nil,
    LogoSize         = 60,
    LogoTransparency = 0.1,
}

local FloatingLogo = {}

local function DestroyLogo()
    if State.LogoGui then pcall(function() State.LogoGui:Destroy() end) end
    local gp = GuiParent()
    if gp then
        for _, c in ipairs(gp:GetChildren()) do
            if c.Name == "Choco_MTSOREYA_Logo" then pcall(function() c:Destroy() end) end
        end
    end
    State.LogoGui = nil
    State.LogoImage = nil
end

function FloatingLogo.Build()
    DestroyLogo()
    local gp = GuiParent()
    if not gp then return false end

    local sg = Instance.new("ScreenGui")
    sg.Name = "Choco_SOREYAPREMIUM_Logo"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.DisplayOrder = 999999
    sg.Enabled = true
    local ok = pcall(function() sg.Parent = gp end)
    if not ok then pcall(function() sg.Parent = LocalPlayer:WaitForChild("PlayerGui", 5) end) end

    local size = State.LogoSize
    local img = Instance.new("ImageButton")
    img.Name = "Logo"
    img.Size = UDim2.new(0, size, 0, size)
    img.Position = UDim2.new(0, 20, 0, 100)
    img.BackgroundTransparency = 1
    img.BorderSizePixel = 0
    img.Image = HUB.LogoId
    img.ImageTransparency = State.LogoTransparency
    img.ScaleType = Enum.ScaleType.Fit
    img.AutoButtonColor = false
    img.Active = true
    img.Selectable = true
    img.Visible = true
    img.ZIndex = 100
    img.Parent = sg

    local dragging, dragStart, startPos, dragMoved = false, Vector2.zero, UDim2.new(), false
    img.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = i.Position; startPos = img.Position; dragMoved = false
        end
    end)
    img.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            if d.Magnitude > 4 then dragMoved = true end
            img.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    img.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    img.MouseButton1Click:Connect(function()
        if dragMoved then return end
        pcall(function()
            local h = _G[INSTANCE_KEY]
            if h and h.window then
                if h.window.Toggle then h.window:Toggle()
                elseif h.window.Minimize then h.window:Minimize() end
            end
        end)
    end)

    State.LogoGui = sg
    State.LogoImage = img
    return true
end

function FloatingLogo.SetVisible(v)
    State.FloatingLogo = v
    if v then FloatingLogo.Build() else DestroyLogo() end
end
function FloatingLogo.SetSize(sz)
    State.LogoSize = sz
    if State.LogoImage then State.LogoImage.Size = UDim2.new(0, sz, 0, sz) end
end
function FloatingLogo.SetTransparency(a)
    State.LogoTransparency = a
    if State.LogoImage then State.LogoImage.ImageTransparency = a end
end

task.spawn(function()
    pcall(function() ContentProvider:PreloadAsync({ HUB.LogoId }) end)
end)


local Window = WindUI:CreateWindow({
    Title   = HUB.Name,
    Author  = HUB.Game .. " | V " .. HUB.Version,
    Icon    = HUB.LogoId,
    Folder  = "ChocoHubPremium",
    Size    = UDim2.fromOffset(600, 480),
    Transparent = false,
    Acrylic = false,
    Theme   = "Dark",
    User = { Enabled = true, Anonymous = false },
    HideSearchBar = true,
    ToggleKey = Enum.KeyCode.Insert,
    OpenButton = { Title = HUB.Name, Enabled = false, Draggable = true },
})
_G[INSTANCE_KEY] = { version = HUB.Version, window = Window }

local Tabs = {
    Fish     = Window:Tab({ Title = "Main",        Icon = "fish" }),
    AutoCore = Window:Tab({ Title = "Automation",  Icon = "gem" }),
    Summit   = Window:Tab({ Title = "Auto Summit", Icon = "mountain" }),
    Teleport = Window:Tab({ Title = "Teleport",    Icon = "map-pin" }),
    Misc     = Window:Tab({ Title = "Misc",        Icon = "sparkles" }),
    Hook     = Window:Tab({ Title = "Webhook",     Icon = "webhook" }),
    Settings = Window:Tab({ Title = "Settings",    Icon = "settings" }),
    Cfg      = Window:Tab({ Title = "Config",      Icon = "file-cog" }),
    Info     = Window:Tab({ Title = "Info",        Icon = "info" }),
}


do
    local S = Tabs.Fish:Section({ Title = "Instant Reel" })
    local reelToggle
    reelToggle = S:Toggle({
        Title = "Enable Instant Reel", Value = false,
        Callback = function(v)
            Auto.Enabled = v
            if AutoActive() then StartAuto() else StopAuto() end
            Notify("Instant Reel", v and "ON" or "OFF", 2)
        end,
    })

    Auto.SyncToggle = function(on)
        if reelToggle and reelToggle.SetValue then
            pcall(function() reelToggle:SetValue(on) end)
        elseif reelToggle and reelToggle.Value ~= nil then
            pcall(function() reelToggle.Value = on end)
        end
    end
    S:Dropdown({
        Title = "Reel Speed", Values = { "Normal", "Fast", "Ultra" },
        Value = "Ultra", SearchBarEnabled = false,
        Callback = function(v)
            local mode = tostring(v)
            Auto.Ultra     = (mode == "Ultra")
            Auto.SuperFast = (mode == "Ultra") or (mode == "Fast")
            Auto.LearnedClaim = nil
            Notify("Instant Reel", "Speed: " .. mode .. (mode == "Ultra" and " (fastest)" or ""), 2)
        end,
    })
    S:Slider({
        Title = "Claim Delay x0.01s", Value = { Min = 3, Max = 145, Default = 45 }, Step = 1,
        Callback = function(v)
            Auto.ClaimDelay = v / 100
            Auto.ClaimStart = v / 100
            Auto.LearnedClaim = nil
        end,
    })
    S:Toggle({ Title = "Adaptive Claim Speed", Value = true,
        Callback = function(v)
            Auto.Adaptive = v
            if not v then Auto.LearnedClaim = nil end
            Notify("Instant Reel", "Adaptive " .. (v and "ON" or "OFF"), 2)
        end })
    S:Toggle({ Title = "Ultra Fast Bite (short cast)", Value = true,
        Callback = function(v)
            Auto.FastBite = v
            Notify("Instant Reel", "Fast Bite " .. (v and "ON (short cast)" or "OFF"), 2)
        end })
    S:Toggle({ Title = "Instant Bait Landing (super fast)", Value = true,
        Callback = function(v)
            BaitFix.On = v
            if v then pcall(InstallBaitPatch) else pcall(UninstallBaitPatch) end
            Notify("Instant Reel", "Bait landing " .. (v and "ON (instant)" or "OFF"), 2)
        end })
end


local Tp = {
    Presets = {
        CoreLocations = Vector3.new(-9035.890625, 1250.61279296875, -6511.6669921875),
        SpotMancing   = Vector3.new(-7833.33203125, 1236.7515869140625, -6327.37353515625),

        SpotAnomali   = CFrame.new(-8172.0615, 1239.1294, -6275.3159)
            * CFrame.Angles(0, math.rad(179.94), 0),

        NpcSell       = Vector3.new(-6667.651, 1316.178, -9971.995),
    },
}

local function TpTo(pos, label)

    local cf
    if typeof(pos) == "Vector3" then
        cf = CFrame.new(pos + Vector3.new(0, 3, 0))
    elseif typeof(pos) == "CFrame" then
        cf = pos + Vector3.new(0, 3, 0)
    else
        Notify("Teleport", (label or "Spot") .. " has no coordinates yet", 3)
        return
    end
    local char = Char()
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    pcall(function()
        hrp.CFrame = cf
        char:PivotTo(cf)
        hrp.AssemblyLinearVelocity = Vector3.zero
    end)
    Notify("Teleport", "Teleported to " .. (label or "spot"), 2)
end

do
    local T = Tabs.Teleport
    local S = T:Section({ Title = "Teleport" })
    S:Button({ Title = "Core Locations", Icon = "gem",
        Callback = function() TpTo(Tp.Presets.CoreLocations, "Core Locations") end })
    S:Button({ Title = "Spot Mancing", Icon = "fish",
        Callback = function() TpTo(Tp.Presets.SpotMancing, "Spot Mancing") end })
    S:Button({ Title = "Spot Anomali", Icon = "triangle-alert",
        Callback = function() TpTo(Tp.Presets.SpotAnomali, "Spot Anomali") end })
    S:Button({ Title = "Teleport to NPC Sell", Icon = "hand-coins",
        Callback = function() TpTo(Tp.Presets.NpcSell, "NPC Sell") end })
end


local Summit = {

    Points = {
        Vector3.new(468.4,   444.9,  -8948.0),
        Vector3.new(456.3,   489.0,  -9572.7),
        Vector3.new(391.9,   629.0,  -10117.5),
        Vector3.new(489.8,   637.0,  -10682.5),
        Vector3.new(1088.9,  725.0,  -11158.7),
        Vector3.new(971.5,   732.9,  -11820.6),
        Vector3.new(390.7,   885.0,  -11837.7),
        Vector3.new(-326.3,  849.0,  -11737.4),
        Vector3.new(-869.8,  853.0,  -11735.8),
        Vector3.new(-1281.2, 857.0,  -12091.2),
        Vector3.new(-1311.6, 889.0,  -12836.8),
        Vector3.new(-2316.0, 913.0,  -12667.7),
        Vector3.new(-2310.6, 917.0,  -11849.0),
        Vector3.new(-2448.4, 961.0,  -11058.7),
        Vector3.new(-3478.0, 981.0,  -11026.2),
        Vector3.new(-4228.0, 1001.0, -11012.6),
        Vector3.new(-4650.1, 1081.0, -11669.6),
        Vector3.new(-5551.0, 1101.0, -11646.9),
        Vector3.new(-6762.8, 1097.0, -11507.1),
        Vector3.new(-6768.3, 1102.6, -10790.2),
        Vector3.new(-6767.209, 1340.403, -10082.368),
    },
    MaxCP    = 21,
    CP       = 1,
    Running  = false,
    Loop     = true,
    ShowHUD  = true,
    Notify   = true,
    Delay    = 2.0,


    Debug    = { Print = false },
    _SummitPart = nil,
    _BackBC     = nil,
}


do
    local T = Tabs.Teleport
    local S = T:Section({ Title = "Teleport Per Checkpoint" })


    local cpLabels = {}
    for i = 1, (Summit.MaxCP or #Summit.Points) do
        cpLabels[i] = (i == 21) and "CP21 (Summit)" or ("CP" .. tostring(i))
    end
    local cpIndex = {}
    for i = 1, #cpLabels do cpIndex[cpLabels[i]] = i end

    local picked = cpLabels[1]
    S:Dropdown({
        Title  = "Select Checkpoint",
        Values = cpLabels,
        Value  = picked,
        Callback = function(value) picked = value end,
    })
    S:Button({ Title = "Teleport To Checkpoint", Icon = "flag",
        Callback = function()
            local idx = cpIndex[picked]
            if not idx then
                Notify("Teleport", "Pick a checkpoint first", 2)
                return
            end
            TpTo(Summit.Points[idx], cpLabels[idx])
        end })
end


local function FindTargetModel(target)
    if not target or not target.Parent then return nil, nil end
    local function hrpOf(model)
        if not model then return nil end
        return model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("UpperTorso")
            or model:FindFirstChild("Torso")
            or model.PrimaryPart
    end

    local char = target.Character
    if char then return char, hrpOf(char) end

    local wp = workspace:FindFirstChild(target.Name)
    if wp then
        local okp, owner = pcall(function() return Players:GetPlayerFromCharacter(wp) end)
        if (okp and owner == target) or wp.Name == target.Name then
            return wp, hrpOf(wp)
        end
    end

    for _, c in ipairs(workspace:GetChildren()) do
        if c:IsA("Model") then
            local okp, owner = pcall(function() return Players:GetPlayerFromCharacter(c) end)
            if (okp and owner == target) or c.Name == target.Name then
                return c, hrpOf(c)
            end
        end
    end
    return nil, nil
end


local function TargetPos(target)
    local model, hrp = FindTargetModel(target)
    if hrp then return hrp.Position, model, hrp end
    if model then
        local ok, pos = pcall(function() return model:GetPivot().Position end)
        if ok and typeof(pos) == "Vector3" then return pos, model, nil end
    end
    return nil, model, nil
end


local function TargetCFrame(target)
    local model, hrp = FindTargetModel(target)
    if hrp then
        local ok, cf = pcall(function() return hrp.CFrame end)
        if ok and typeof(cf) == "CFrame" then return cf end
    end
    local pos = TargetPos(target)
    if pos then return CFrame.new(pos) end
    return nil
end


local function RequestArea(pos)
    pcall(function()
        if pos and workspace.RequestStreamAroundAsync then
            workspace:RequestStreamAroundAsync(pos)
        end
    end)
end


local function TpToPlayer(target, label)
    local name = (target and target.Name) or tostring(label or "")
    if name == "" then
        Notify("Teleport", "Pick a player first", 3)
        return
    end


    local function resolve()
        local me = Players.LocalPlayer
        for _, other in ipairs(Players:GetPlayers()) do
            if other ~= me and other.Name == name then return other end
        end
        return nil
    end

    local who = resolve()
    if not who then
        Notify("Teleport", name .. " left the server", 3)
        return
    end


    local lastPos = nil


    local function snapOnce(cf, silent)
        if typeof(cf) == "Vector3" then cf = CFrame.new(cf) end
        if typeof(cf) ~= "CFrame" then return false end
        local char = Char()
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
        local dest = cf * CFrame.new(2, 0, 2)
        local ok = pcall(function()
            hrp.CFrame = dest
            char:PivotTo(dest)
            hrp.AssemblyLinearVelocity = Vector3.zero
        end)
        if ok and not silent then
            Notify("Teleport", "Teleported to " .. tostring(name), 2)
        end
        return ok
    end


    local cf0 = TargetCFrame(who)
    if cf0 then
        lastPos = cf0.Position
        snapOnce(cf0, false)
    end


    task.spawn(function()
        local deadline = os.clock() + 3.0
        while os.clock() < deadline do
            task.wait(0.1)
            local w = resolve()
            if not w then break end
            local cf = TargetCFrame(w)
            if cf then
                lastPos = cf.Position
                RequestArea(cf.Position)
                snapOnce(cf, true)
            elseif lastPos then


                RequestArea(lastPos)
                snapOnce(CFrame.new(lastPos), true)
            end
        end

        local w = resolve()
        local cf = TargetCFrame(w)
        if cf then
            snapOnce(cf, true)
        elseif lastPos then
            snapOnce(CFrame.new(lastPos), true)
        end
    end)


    if not lastPos then
        Notify("Teleport", "Pulling in " .. name .. " (their model isn't loaded yet)", 3)
        RequestArea(Char() and Char():GetPivot().Position or Vector3.zero)
    end
end

do
    local T = Tabs.Teleport
    local S = T:Section({ Title = "Teleport To Player" })

    local picked = nil


    local function buildNames()
        local me = Players.LocalPlayer
        local names = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= me then
                names[#names + 1] = p.Name
            end
        end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        return names
    end

    local namesNow = buildNames()
    if #namesNow > 0 then picked = namesNow[1] end

    local dd = S:Dropdown({
        Title  = "Select Player",
        Values = (#namesNow > 0) and namesNow or { "No other players online" },
        Value  = picked,
        Callback = function(value) picked = value end,
    })
    S:Button({ Title = "Teleport To Player", Icon = "user",
        Callback = function()


            local function findByName(nm)
                if not nm then return nil end
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= Players.LocalPlayer and p.Name == nm then return p end
                end
                return nil
            end

            local who = findByName(picked)
            if not who then

                local cur
                pcall(function() cur = dd.Value end)
                who = findByName(cur)
                if who then picked = cur end
            end
            if not who then
                who = Players:GetPlayers() and (function()
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p ~= Players.LocalPlayer then return p end
                    end
                    return nil
                end)()
                if who then picked = who.Name end
            end
            if not who then
                Notify("Teleport", "No other players in the server", 2)
                return
            end
            TpToPlayer(who, who.Name)
        end })
    S:Button({ Title = "Refresh Players", Icon = "refresh-cw",
        Callback = function()
            local names = buildNames()
            if #names > 0 then
                picked = (picked and table.find(names, picked)) and picked or names[1]
            else
                picked = nil
            end


            pcall(function() dd:Refresh((#names > 0) and names or { "No other players online" }) end)
            Notify("Teleport", #names > 0 and ("Found " .. #names .. " player(s)") or "No other players online", 2)
        end })


    local function autoRefresh()
        local names = buildNames()
        if #names == 0 then
            picked = nil
        elseif not (picked and table.find(names, picked)) then
            picked = names[1]
        end
        pcall(function() dd:Refresh((#names > 0) and names or { "No other players online" }) end)
    end
    ConnMgr:Add(Players.PlayerAdded:Connect(function() task.wait(0.3); autoRefresh() end))
    ConnMgr:Add(Players.PlayerRemoving:Connect(function() task.wait(0.3); autoRefresh() end))
end


local function SummitFireRemote(index0)
    local rem = ReplicatedStorage:FindFirstChild("Remote")
    local cp  = rem and rem:FindFirstChild("Checkpoint")
    local tp  = cp and cp:FindFirstChild("TpToCheckpoint")
    if tp and (tp:IsA("RemoteEvent") or tp:IsA("RemoteFunction")) then
        if Summit.Debug and Summit.Debug.Print then
            print(("[MTSOREYA][Summit] TpToCheckpoint <- %d"):format(index0))
        end
        local ok, res = pcall(function()
            if tp:IsA("RemoteFunction") then return tp:InvokeServer(index0)
            else tp:FireServer(index0); return true end
        end)
        if ok then return true end
    end
    return false
end


local function FindSummitPart()
    if Summit._SummitPart and Summit._SummitPart.Parent then
        return Summit._SummitPart
    end
    local found
    local function walk(root)
        if found then return end
        for _, d in ipairs(root:GetDescendants()) do
            if found then return end
            if d.Name == "SummitPart" and d:IsA("BasePart") then
                found = d
                return
            end
        end
    end
    pcall(function()

        local ws = game:GetService("Workspace")
        local s = ws:FindFirstChild("Summit", true)
        if s then
            local sp = s:FindFirstChild("SummitPart", true)
            if sp and sp:IsA("BasePart") then found = sp end
        end
        if not found then walk(ws) end
    end)
    if found then
        Summit._SummitPart = found
        if Summit.Debug and Summit.Debug.Print then
            print("[MTSOREYA][Summit] SummitPart found: " .. found:GetFullName())
        end
    end
    return found
end


local function FindBackBC()
    if Summit._BackBC and Summit._BackBC.Parent then
        return Summit._BackBC
    end
    local found
    pcall(function()
        local ws = game:GetService("Workspace")
        local folder = ws:FindFirstChild("BackBC", true)
        if folder then
            local part = folder:FindFirstChild("BackBC", true)
            if part and part:IsA("BasePart") then found = part end
        end
        if not found then
            for _, d in ipairs(ws:GetDescendants()) do
                if d.Name == "BackBC" and d:IsA("BasePart") then found = d; break end
            end
        end
    end)
    if found then
        Summit._BackBC = found
        if Summit.Debug and Summit.Debug.Print then
            print("[MTSOREYA][Summit] BackBC found: " .. found:GetFullName())
        end
    end
    return found
end


local function TouchPart(part, dwell)
    if not part then return end
    local p = part.Position
    local function snap()
        local char = Char()
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            pcall(function()
                hrp.CFrame = CFrame.new(p)
                char:PivotTo(CFrame.new(p))
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end
    snap()
    local char0 = Char()
    local hum = char0 and char0:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function() hum:MoveTo(p) end)
    end
    local t, step = 0, 0.1
    while (dwell == nil or t < dwell) do
        task.wait(step); t = t + step
        snap()
        if hum then pcall(function() hum:MoveTo(p) end) end
        if dwell == nil then break end
    end
end


local function SummitTeleport(pos, index0, dwell, onSummit)
    local usedRemote = false
    if index0 ~= nil then
        usedRemote = SummitFireRemote(index0)
    end

    local function snapTo(target)
        local char = Char()
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            pcall(function()
                hrp.CFrame = target
                char:PivotTo(target)
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            end)
        end
        return hrp ~= nil
    end


    local target
    local summitPart
    if onSummit then
        summitPart = FindSummitPart()
        if summitPart then


            local p = summitPart.Position
            target = CFrame.new(Vector3.new(p.X, p.Y, p.Z))
        end
    end
    if not target and typeof(pos) == "Vector3" then
        target = CFrame.new(pos + Vector3.new(0, 3, 0))
    end
    if not target then return usedRemote end

    snapTo(target)


    if onSummit and summitPart then
        local dest = Vector3.new(summitPart.Position.X, summitPart.Position.Y, summitPart.Position.Z)
        local char0 = Char()
        local hum = char0 and char0:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function()
                hum:MoveTo(dest)
                hum:ChangeState(Enum.HumanoidStateType.Running)
            end)
            local w = 0
            while Summit.Running and w < 0.6 do
                task.wait(0.05); w = w + 0.05
                pcall(function() hum:MoveTo(dest) end)
            end
        end
    end


    local t, step = 0, 0.1
    while Summit.Running and t < (dwell or 0) do
        task.wait(step)
        t = t + step
        snapTo(target)
    end
    return usedRemote
end


local RefreshSummitLbl = function() end


local function SummitNearestCP(radius)
    radius = radius or 90
    local char = Char()
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local here = hrp.Position
    local bestI, bestD = nil, math.huge
    for i, p in ipairs(Summit.Points) do
        local d = (Vector3.new(p.X, here.Y, p.Z) - Vector3.new(here.X, here.Y, here.Z)).Magnitude
        if d < bestD then bestD, bestI = d, i end
    end
    if bestI and bestD <= radius then return bestI end
    return nil
end


local function SummitPass(fromCP)
    local start = math.clamp(fromCP or Summit.CP or 1, 1, #Summit.Points)
    for i = start, #Summit.Points do
        if not Summit.Running then return false end
        Summit.CP = i
        local isSummit = (i == Summit.MaxCP)
        local tag = isSummit and ("CP" .. i .. " (Summit)") or ("CP" .. i)
        local dwell = (Summit.Delay or 2.0) + (isSummit and 0.7 or 0)
        SummitTeleport(Summit.Points[i], i - 1, dwell, isSummit)
        if Summit.Debug and Summit.Debug.Print then
            print(("[MTSOREYA][Summit] step %d/%d -> %s  idx=%d  dwell=%.1fs")
                :format(i, #Summit.Points, tag, i - 1, dwell))
        end
        if Summit.ShowHUD and Summit.Notify ~= false then
            pcall(function()
                WindUI:Notify({
                    Title = "Auto Summit " .. i .. "/" .. #Summit.Points,
                    Content = "Reached " .. tag,
                    Duration = 1.2,
                })
            end)
        end
    end
    return true
end

function Summit.Run()
    if Summit.Running then return end


    local near = SummitNearestCP()
    local startCP = near or Summit.CP or 1
    if startCP > #Summit.Points then startCP = 1 end

    Summit.CP = startCP
    Summit.Running = true
    task.spawn(function()
        repeat
            local from = Summit.CP or startCP
            Summit.Msg("Auto Summit",
                (from > 1) and ("Resuming from CP" .. from .. " ...") or "Walking Basecamp -> Summit...", 2)
            local finished = SummitPass(from)
            if not Summit.Running then break end
            if finished then
                Summit.CP = 1
                Summit.Msg("Auto Summit", "Summit reached - touching BackBC to go back", 3)


                local bc = FindBackBC()
                if bc then
                    TouchPart(bc, Summit.Delay or 2.0)
                else

                    Summit.Msg("Auto Summit", "BackBC not found - teleporting to CP1", 3)
                    SummitTeleport(Summit.Points[1], nil, Summit.Delay or 2.0, false)
                end
                task.wait(Summit.Delay or 2.0)
            end
        until (not Summit.Running) or (not Summit.Loop)
        Summit.Running = false
    end)
end

function Summit.Stop()
    Summit.Running = false


    local near = SummitNearestCP()
    if near then Summit.CP = near end
    RefreshSummitLbl()
    if Summit.SyncToggle then Summit.SyncToggle(false) end
    Summit.Msg("Auto Summit", "Stopped - will resume from CP" .. (Summit.CP or 1), 3)
end
_G.X0_MTS_Summit = Summit


function Summit.Msg(title, content, dur)
    if Summit.Notify == false then return end
    Notify(title, content, dur)
end
_G.X0_MTS_SummitMsg = Summit.Msg


_G.X0_MTS_SummitNotifyOff = (Summit.Notify == false)

do
    local T = Tabs.Summit
    local S = T:Section({ Title = "Auto Summit" })


    local startToggle
    startToggle = S:Toggle({ Title = "Auto Summit", Value = false,
        Callback = function(v)
            if v then
                Summit.Run()
            else
                Summit.Stop()
            end
        end })

    Summit.SyncToggle = function(on)
        if startToggle and startToggle.SetValue then
            pcall(function() startToggle:SetValue(on) end)
        elseif startToggle and startToggle.Value ~= nil then
            pcall(function() startToggle.Value = on end)
        end
    end

    S:Toggle({ Title = "Loop", Value = true,
        Callback = function(v)
            Summit.Loop = v
            Summit.Msg("Auto Summit", "Loop " .. (v and "ON" or "OFF"), 2)
        end })


    local statBtn
    RefreshSummitLbl = function()
        if not statBtn then return end
        pcall(function()
            statBtn:SetTitle("Current: CP" .. (Summit.CP or 1) .. " / " .. Summit.MaxCP)
        end)
    end
    statBtn = S:Button({ Title = "Current: CP" .. (Summit.CP or 1) .. " / " .. Summit.MaxCP,
        Icon = "map-pin",
        Callback = function()
            local near = SummitNearestCP()
            if near then Summit.CP = near end
            RefreshSummitLbl()
            Summit.Msg("Auto Summit", "Resume point: CP" .. (Summit.CP or 1), 2)
        end })

    S:Slider({
        Title = "Delay Per Checkpoint x0.1s",
        Value = { Min = 0, Max = 50, Default = 20 }, Step = 1,
        Callback = function(v)

            Summit.Delay = v / 10
            Summit.Msg("Auto Summit", "Delay " .. string.format("%.1f", Summit.Delay) .. "s", 2)
        end,
    })
end


local function FullDebugPath(inst)
    local parts, cur, guard = {}, inst, 0
    while cur and cur ~= game and guard < 30 do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
        guard = guard + 1
    end
    return table.concat(parts, ".")
end

local Galatama = {
    Enabled   = false,
    Running   = false,
    Conn      = nil,
    LastFire  = 0,
    LastClick = 0,
    Fired     = 0,
    RemoteObj = nil,
    RemotePath = "(searching...)",
    LastSweep = 0,
    WatchConn = nil,
}
_G.X0_MTS_Galatama = Galatama


local GALATAMA_ACCEPT_NAMES = {
    "ikut", "join", "gabung", "ya", "yes", "terima", "accept", "ok", "okey", "oke",
}

local function _nameIsAccept(nm)
    if not nm then return false end
    nm = string.lower(tostring(nm))
    for _, w in ipairs(GALATAMA_ACCEPT_NAMES) do
        if string.find(nm, w, 1, true) then return true end
    end
    return false
end


local function RobustClick(btn)
    if not btn then return false end
    pcall(function() btn.Activated:Fire() end)
    pcall(function() btn.MouseButton1Click:Fire() end)
    pcall(function() btn.MouseButton1Down:Fire() end)
    pcall(function() btn.MouseButton1Up:Fire() end)
    pcall(function() btn:Activate() end)
    return true
end


local function FindGalatamaRemote()

    local cached = Galatama.RemoteObj
    if cached and cached.Parent then return cached end

    local found = nil

    local function isRemote(c)
        return c:IsA("RemoteEvent") or c:IsA("RemoteFunction")
            or c:IsA("BindableFunction") or c:IsA("BindableEvent")
    end


    pcall(function()
        local remote = ReplicatedStorage:FindFirstChild("Remote")
        local glat   = remote and remote:FindFirstChild("Glatama")
        local ikut   = glat and glat:FindFirstChild("Ikut")
        if ikut and isRemote(ikut) then found = ikut end
    end)
    if found then
        Galatama.RemoteObj = found
        Galatama.RemotePath = FullDebugPath(found)
        return found
    end


    local roots = {}
    pcall(function() roots[#roots + 1] = ReplicatedStorage end)
    pcall(function() roots[#roots + 1] = game:GetService("ReplicatedFirst") end)
    pcall(function() roots[#roots + 1] = workspace end)
    pcall(function() roots[#roots + 1] = LocalPlayer:FindFirstChild("PlayerGui") end)
    pcall(function() roots[#roots + 1] = CoreGui end)


    for _, root in ipairs(roots) do
        if found then break end
        pcall(function()
            for _, d in ipairs(root:GetDescendants()) do
                if d.Name == "Ikut" and isRemote(d) then found = d; return end
            end
        end)
    end


    if not found then
        for _, root in ipairs(roots) do
            if found then break end
            pcall(function()
                for _, d in ipairs(root:GetDescendants()) do
                    if isRemote(d) and _nameIsAccept(d.Name) then

                        local cur, depth = d.Parent, 0
                        while cur and cur ~= game and depth < 6 do
                            local nm = string.lower(cur.Name)
                            if string.find(nm, "glatama", 1, true)
                                or string.find(nm, "galatama", 1, true)
                                or string.find(nm, "gabung", 1, true) then
                                found = d
                                return
                            end
                            cur = cur.Parent
                            depth = depth + 1
                        end
                    end
                end
            end)
        end
    end


    if not found then
        pcall(function()
            local glat = ReplicatedStorage:FindFirstChild("Glatama")
            local direct = glat and glat:FindFirstChild("Ikut")
            if direct then found = direct end
        end)
    end

    if found then
        Galatama.RemoteObj = found
        Galatama.RemotePath = FullDebugPath(found)
    end
    return found
end


local function FireGalatamaJoin()
    local now = os.clock()
    if now - (Galatama.LastFire or 0) < 1.0 then return false end
    local r = FindGalatamaRemote()
    if not r then return false end
    local ok = pcall(function()
        if r:IsA("RemoteEvent") then
            r:FireServer()
        elseif r:IsA("RemoteFunction") then
            r:InvokeServer(true)
        elseif r:IsA("BindableFunction") then
            r:Invoke(true)
        elseif r:IsA("BindableEvent") then
            r:Fire(true)
        end
    end)
    if ok then
        Galatama.LastFire = now
        Galatama.Fired = (Galatama.Fired or 0) + 1
    end
    return ok
end


local function ClickAcceptIn(root)
    if not root then return false end
    local clicked = false
    pcall(function()
        local stack = { root }
        local guard = 0
        while #stack > 0 and guard < 4000 do
            guard = guard + 1
            local node = table.remove(stack)
            if node and node.Parent then

                if (node:IsA("TextButton") or node:IsA("ImageButton"))
                    and _nameIsAccept(node.Name) then

                    if node.Visible and node.AbsoluteSize.X > 0 then
                        RobustClick(node)
                        clicked = true
                        break
                    end
                end
                for _, ch in ipairs(node:GetChildren()) do
                    stack[#stack + 1] = ch
                end
            end
        end
    end)
    return clicked
end


local function TryClickGalatamaPopup()
    local now = os.clock()
    if now - (Galatama.LastClick or 0) < 0.5 then return false end

    local clicked = false


    pcall(function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if not pg then return end
        for _, d in ipairs(pg:GetDescendants()) do
            if (d:IsA("TextButton") or d:IsA("ImageButton"))
                and (d.Name == "BERGABUNG" or d.Name == "Gabung" or d.Name == "Ikut")
                and d.Visible and d.AbsoluteSize.X > 0 then
                RobustClick(d)
                clicked = true
                return
            end
        end
    end)
    if clicked then
        Galatama.LastClick = now
        return true
    end


    local containers = {}
    pcall(function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then containers[#containers + 1] = pg end
    end)
    pcall(function() containers[#containers + 1] = CoreGui end)
    for _, c in ipairs(containers) do
        if ClickAcceptIn(c) then
            Galatama.LastClick = now
            return true
        end
    end
    return false
end


local function GalatamaPopupVisible()
    local vis = false
    pcall(function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if not pg then return end
        local stack, guard = { pg }, 0
        while #stack > 0 and guard < 6000 do
            guard = guard + 1
            local node = table.remove(stack)
            if node and node.Parent then
                if (node:IsA("TextButton") or node:IsA("ImageButton"))
                    and node.Visible and node.AbsoluteSize.X > 0
                    and _nameIsAccept(node.Name) then
                    vis = true
                    return
                end
                for _, ch in ipairs(node:GetChildren()) do
                    stack[#stack + 1] = ch
                end
            end
        end
    end)
    return vis
end


function Galatama.Start()
    if Galatama.Running then return end
    Galatama.Running = true
    Galatama.Enabled = true


    local function TryJoin()
        if not Galatama.Enabled then return end

        FireGalatamaJoin()

        TryClickGalatamaPopup()
    end


    pcall(function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            Galatama.WatchConn = pg.DescendantAdded:Connect(function(d)
                if not Galatama.Enabled then return end

                if d:IsA("GuiObject") or d:IsA("ScreenGui") or d:IsA("LayerCollector") then

                    task.defer(function() TryJoin() end)
                end
            end)
        end
    end)


    Galatama.Conn = RunService.Heartbeat:Connect(function()
        if not Galatama.Enabled then return end
        local now = os.clock()
        if now - (Galatama.LastSweep or 0) < 0.25 then return end
        Galatama.LastSweep = now
        if GalatamaPopupVisible() then
            TryJoin()
        end
    end)

    Notify("Galatama", "Auto Accept ON (watches for the random invite)", 3)
end

function Galatama.Stop()
    Galatama.Enabled = false
    Galatama.Running = false
    if Galatama.Conn then pcall(function() Galatama.Conn:Disconnect() end); Galatama.Conn = nil end
    if Galatama.WatchConn then pcall(function() Galatama.WatchConn:Disconnect() end); Galatama.WatchConn = nil end
end


local Automation = {
    Enabled      = false,
    EveryMin     = 60,
    FishMin      = 10,
    State        = "idle",
    CorePos      = Tp.Presets.CoreLocations,
    MancingPos   = Tp.Presets.SpotAnomali,
    RodSyarat    = "Withering Rod",
    Running      = false,
    Thread       = nil,
    LblRefresh   = function() end,
}
_G.X0_MTS_Automation = Automation


local function nowSec()
    local ok, t = pcall(os.date, "*t")
    if ok and type(t) == "table" then
        return (t.hour or 0) * 3600 + (t.min or 0) * 60 + (t.sec or 0)
    end

    local ok2, epoch = pcall(os.time)
    if ok2 and type(epoch) == "number" then
        return math.floor(epoch) % 86400
    end
    return nil
end


local function clockStr(secOfDay)
    if not secOfDay then return ":" end
    local h = math.floor(secOfDay / 3600) % 24
    local m = math.floor((secOfDay % 3600) / 60)
    return string.format("%02d:%02d", h, m)
end


local function secsUntilNextSlot(now, everyMin)
    everyMin = math.max(1, tonumber(everyMin) or 60)
    local step = everyMin * 60
    local nextAt = (math.floor(now / step) + 1) * step
    return (nextAt - now) % 86400, nextAt % 86400
end


local function LoadCoreConfig()
    pcall(function()
        local mods = ReplicatedStorage:FindFirstChild("Modules")
        local fish = mods and mods:FindFirstChild("Fishing")
        local cfg  = fish and fish:FindFirstChild("CoreConfig")
        if not cfg then return end
        local ok, res = pcall(require, cfg)
        if ok and type(res) == "table" then
            if type(res.RodSyarat) == "string" and res.RodSyarat ~= "" then
                Automation.RodSyarat = res.RodSyarat
            end
            if type(res.NamaItem) == "string" and res.NamaItem ~= "" then
                Automation.ItemName = res.NamaItem
            end
        end
    end)
end


local function HasCoreRod()
    local want = tostring(Automation.RodSyarat or ""):lower()
    if want == "" then return true end
    local char = Char()
    local bp   = LocalPlayer:FindFirstChildOfClass("Backpack")
    for _, src in ipairs({ char, bp }) do
        if src then
            for _, t in ipairs(src:GetChildren()) do
                if t:IsA("Tool") and tostring(t.Name):lower():find(want, 1, true) then
                    return true
                end
            end
        end
    end
    return false
end


local function EnsureFishingOn()
    if not AutoActive() then
        Auto.Enabled = true
        if Auto.SyncToggle then pcall(Auto.SyncToggle, true) end
        pcall(StartAuto)
    end
end

local function AutomationStop(silent)
    Automation.Enabled = false
    Automation.Running = false
    Automation.State   = "idle"
    if Automation.SyncToggle then pcall(Automation.SyncToggle, false) end
    pcall(Automation.LblRefresh)
    if not silent then
        Notify("Auto Core", "Stopped", 3)
    end
end

local function AutomationSetState(state, content)
    Automation.State = state
    pcall(Automation.LblRefresh)
    if content then Notify("Auto Core", content, 4) end
end


local function SleepWhileRunning(secs)
    local until_ = os.clock() + math.max(0, secs)
    while Automation.Running and os.clock() < until_ do
        task.wait(math.min(1, until_ - os.clock()))
    end
    return Automation.Running
end


local function AutomationRun()
    if Automation.Running then return end
    Automation.Running = true
    Automation.Enabled = true

    LoadCoreConfig()
    Automation.Thread = task.spawn(function()
        local fishSecs = math.max(1, tonumber(Automation.FishMin) or 10) * 60

        while Automation.Running do

            local now = nowSec()
            if now then
                local waitSecs, slotAt = secsUntilNextSlot(now, Automation.EveryMin)
                Automation.NextSlotAt = slotAt
                AutomationSetState("waiting",
                    "Waiting for " .. clockStr(slotAt) .. " (in " .. math.floor(waitSecs / 60) .. " min)")
                if not SleepWhileRunning(waitSecs) then break end
            else

                AutomationSetState("waiting", "Waiting ~60 min (no clock)")
                if not SleepWhileRunning(60 * 60) then break end
            end


            if not HasCoreRod() then
                Notify("Auto Core",
                    "WARNING: " .. tostring(Automation.RodSyarat) .. " not found - cores will not drop", 6)
            else
                Notify("Auto Core",
                    clockStr(nowSec()) .. " - Core Spot, fishing " .. tostring(Automation.FishMin) .. " min", 4)
            end
            AutomationSetState("core", nil)
            pcall(TpTo, Automation.CorePos, "Core Spot")
            task.wait(0.6)
            EnsureFishingOn()

            if not SleepWhileRunning(fishSecs) then break end


            Notify("Auto Core", clockStr(nowSec()) .. " - back to Spot Anomali", 4)
            AutomationSetState("back", nil)
            pcall(TpTo, Automation.MancingPos, "Spot Anomali")

        end

        Automation.Running = false
        AutomationSetState("idle", nil)
    end)
end


do
    local T = Tabs.AutoCore
    local S = T:Section({ Title = "Auto Core Catch" })

    local startToggle
    startToggle = S:Toggle({ Title = "Auto Core Catch (1 hour)", Value = false,
        Callback = function(v)
            if v then
                AutomationRun()
            else
                AutomationStop()
            end
        end })
    Automation.SyncToggle = function(on)
        if startToggle and startToggle.SetValue then
            pcall(function() startToggle:SetValue(on) end)
        elseif startToggle and startToggle.Value ~= nil then
            pcall(function() startToggle.Value = on end)
        end
    end

    local statBtn
    Automation.LblRefresh = function()
        if not statBtn then return end
        local label = ({
            idle    = "Idle",
            waiting = "Waiting for " .. clockStr(Automation.NextSlotAt or 0),
            core    = "Fishing Core Spot",
            back    = "Returned to Spot Anomali",
        })[Automation.State] or tostring(Automation.State)
        pcall(function()
            statBtn:SetTitle("Status: " .. label)
        end)
    end
    statBtn = S:Button({ Title = "Status: Idle", Icon = "gem",
        Callback = function()
            Automation.LblRefresh()
            Notify("Auto Core",
                "Every " .. tostring(Automation.EveryMin) .. " min (on the clock)  -  "
                .. tostring(Automation.FishMin) .. " min at Core Spot"
                .. "  -  next: " .. clockStr(Automation.NextSlotAt or 0)
                .. "  -  rod: " .. tostring(Automation.RodSyarat), 5)
        end })

    S:Slider({
        Title = "Trigger Every (minutes on the clock)",
        Value = { Min = 10, Max = 120, Default = 60 }, Step = 10,
        Callback = function(v)
            Automation.EveryMin = v
            Notify("Auto Core",
                "Fires at every " .. v .. "-minute mark on the real clock"
                .. (v == 60 and " (top of each hour)" or ""), 3)
        end,
    })
    S:Slider({
        Title = "Fish At Core Spot (minutes)",
        Value = { Min = 1, Max = 30, Default = 10 }, Step = 1,
        Callback = function(v)
            Automation.FishMin = v
            Notify("Auto Core", "Fishing " .. v .. " min at Core Spot", 2)
        end,
    })

    S:Button({ Title = "Go Core Spot Now", Icon = "map-pin",
        Callback = function()
            pcall(TpTo, Automation.CorePos, "Core Spot")
            Automation.LblRefresh()
        end })
end


do
    local T = Tabs.AutoCore


    local S = T:Section({ Title = "Auto Accept Galatama" })

    S:Toggle({ Title = "Auto Accept Galatama", Value = false, Locked = true,
        LockedTitle = "Maintenance" })

    S:Button({ Title = "Join Galatama Now", Icon = "lock", Locked = true,
        LockedTitle = "Maintenance" })
end


do
    local T = Tabs.Settings
    local LookSec = T:Section({ Title = "UI Appearance" })
    LookSec:Dropdown({
        Title  = "Theme",
        Values = {
            "Dark", "Light", "Rose", "Plant", "Red", "Indigo", "Sky",
            "Violet", "Amber", "Emerald", "Midnight", "Crimson",
            "MonokaiPro", "CottonCandy", "Mellowsi", "Rainbow",
        },
        Value  = "Dark",
        Callback = function(value)
            local ok = pcall(function() WindUI:SetTheme(value) end)
            Notify("Theme", ok and ("Set to " .. tostring(value)) or ("Failed: " .. tostring(value)), 2)
        end,
    })
    LookSec:Space()
    LookSec:Toggle({
        Title = "Solid Window Background",
        Value = true,
        Callback = function(v) pcall(function() Window:SetPanelBackground(v) end) end,
    })

    local NotifSec = T:Section({ Title = "Notifications" })
    NotifSec:Toggle({
        Title = "Show TandaSeru (slows reel)",
        Value = Auto.AutoShowMarker,
        Callback = function(v)
            Auto.AutoShowMarker = v
            pcall(function() AutoMarker.Set(v) end)
            Notify("TandaSeru", "Shared marker " .. (v and "ON (1 per bite)" or "OFF (fastest)"), 2)
        end,
    })
    NotifSec:Space()
    local caughtBtn
    local function caughtLabel()
        return "Caught Notification: " .. (Auto.CaughtNotify and "ON" or "OFF")
    end
    caughtBtn = NotifSec:Button({
        Title = caughtLabel(),
        Icon  = "bell",
        Callback = function()
            Auto.CaughtNotify = not Auto.CaughtNotify
            pcall(function() caughtBtn:SetTitle(caughtLabel()) end)
            Notify("Notifications", "Caught popup " .. (Auto.CaughtNotify and "ON" or "OFF"), 2)
        end,
    })

    local summitBtn
    local function summitLabel()
        return "Summit Notification: " .. (Summit.Notify and "ON" or "OFF")
    end
    summitBtn = NotifSec:Button({
        Title = summitLabel(),
        Icon  = "mountain",
        Callback = function()
            Summit.Notify = not Summit.Notify
            _G.X0_MTS_SummitNotifyOff = (Summit.Notify == false)
            pcall(function() summitBtn:SetTitle(summitLabel()) end)


            Notify("Notifications", "Summit popups " .. (Summit.Notify and "ON" or "OFF"), 2)
        end,
    })

    local ProfSec = T:Section({ Title = "Profile Card" })
    ProfSec:Toggle({
        Title = "Anonymous Mode",
        Value = false,
        Callback = function(v) pcall(function() Window.User:SetAnonymous(v) end) end,
    })

    local LogoSec = T:Section({ Title = "Floating Logo" })
    LogoSec:Toggle({
        Title = "Show Logo",
        Value = true,
        Callback = function(v) FloatingLogo.SetVisible(v) end,
    })
    LogoSec:Space()
    LogoSec:Slider({
        Title = "Logo Size",
        Step  = 1,
        Value = { Min = 30, Max = 140, Default = 60 },
        Callback = function(v) FloatingLogo.SetSize(v) end,
    })
    LogoSec:Space()
    LogoSec:Slider({
        Title = "Logo Transparency %",
        Step  = 1,
        Value = { Min = 0, Max = 90, Default = 10 },
        Callback = function(v) FloatingLogo.SetTransparency(v / 100) end,
    })
    LogoSec:Space()
    LogoSec:Button({
        Title = "Rebuild Logo",
        Icon  = "refresh-cw",
        Callback = function()
            State.FloatingLogo = true
            FloatingLogo.Build()
            Notify("Logo", "Rebuilt", 2)
        end,
    })

    local UnSec = T:Section({ Title = "Script" })
    UnSec:Button({
        Title = "Unload Script",
        Icon  = "power",
        Callback = function()
            if _G[INSTANCE_KEY] and _G[INSTANCE_KEY].cleanup then pcall(_G[INSTANCE_KEY].cleanup)
            else pcall(function() _G[INSTANCE_KEY].destroy() end) end
        end,
    })
end


do
    local T = Tabs.Cfg
    local ConfigSec = T:Section({ Title = "Configs" })
    local ConfigManager = Window.ConfigManager
    local ConfigName = "default"

    local input = ConfigSec:Input({
        Title = "Config Name",
        Icon  = "file-cog",
        Value = "default",
        Callback = function(value) ConfigName = value end,
    })
    ConfigSec:Space()

    local AllConfigs = {}
    pcall(function() AllConfigs = ConfigManager:AllConfigs() or {} end)
    local DefaultValue = table.find(AllConfigs, ConfigName) and ConfigName or nil

    local dd = ConfigSec:Dropdown({
        Title  = "All Configs",
        Values = AllConfigs,
        Value  = DefaultValue,
        Callback = function(value)
            ConfigName = value
            pcall(function() input:Set(value) end)
        end,
    })
    ConfigSec:Space()

    ConfigSec:Button({
        Title = "Save Config",
        Icon  = "save",
        Callback = function()
            Window.CurrentConfig = ConfigManager:Config(ConfigName)
            if Window.CurrentConfig:Save() then
                Notify("Config", "Saved '" .. tostring(ConfigName) .. "'", 3)
            end
            pcall(function() dd:Refresh(ConfigManager:AllConfigs() or {}) end)
        end,
    })
    ConfigSec:Space()
    ConfigSec:Button({
        Title = "Load Config",
        Icon  = "folder-open",
        Callback = function()
            Window.CurrentConfig = ConfigManager:CreateConfig(ConfigName)
            if Window.CurrentConfig:Load() then
                Notify("Config", "Loaded '" .. tostring(ConfigName) .. "'", 3)
            end
        end,
    })
    ConfigSec:Space()
    ConfigSec:Button({
        Title = "Refresh Config List",
        Icon  = "refresh-cw",
        Callback = function()
            pcall(function() dd:Refresh(ConfigManager:AllConfigs() or {}) end)
            Notify("Config", "Config list refreshed", 2)
        end,
    })
end


do
    local S = Tabs.Info:Section({ Title = "About" })
    S:Paragraph({
        Title = HUB.Name .. " v" .. HUB.Version,
        Desc = "Game: " .. HUB.Game .. "\nVersion: " .. HUB.Version,
    })
    S:Button({ Title = "Unload Hub", Icon = "power", Callback = function()
        if _G[INSTANCE_KEY] and _G[INSTANCE_KEY].cleanup then pcall(_G[INSTANCE_KEY].cleanup)
        else pcall(function() _G[INSTANCE_KEY].destroy() end) end
    end })
end


local Hook = {
    Enabled   = false,
    Url       = "",
    Rarities  = {},
    MentionId = "",
    LastSent  = 0,
    Sent      = 0,

    AllRarities = {
        "Common", "UnCommon", "Rare", "Epic",
        "Legendary", "Mythical", "Secret", "Forgotten", "CORE",
    },
}
_G.X0_MTS_Hook = Hook


local function HookRequest(url, payload)
    local body = nil
    pcall(function() body = HttpService:JSONEncode(payload) end)
    if not body then return false, "no_body" end
    local req = (syn and syn.request) or (http and http.request) or http_request
              or (fluxus and fluxus.request) or (request)
    if not req then return false, "no_http" end
    local ok = pcall(req, {
        Url = url,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = body,
    })
    if not ok then return false, "request_error" end
    return true
end


local FISH_ICONS = {
    ["1x1x1x1 Shark"] = "rbxassetid://126602140465429",
    ["Ancient Lochness Monster"] = "rbxassetid://122849883484708",
    ["Astralune"] = "rbxassetid://90494527372442",
    ["Cerulean Dragon"] = "rbxassetid://134510300238125",
    ["Bonemaw Tyrant"] = "rbxassetid://113238296585201",
    ["Caustic Maw"] = "rbxassetid://139189575041763",
    ["Cursed Kraken"] = "rbxassetid://88584771745160",
    ["Dark Megalodon"] = "rbxassetid://114809272977194",
    ["ElRetro Gran Maja"] = "rbxassetid://87213487175221",
    ["Emerald Winter Whale"] = "rbxassetid://77578943978639",
    ["Frostbite Leviathan"] = "rbxassetid://138115573993316",
    ["Glacial Serpent"] = "rbxassetid://89525947297991",
    ["Leviathan"] = "rbxassetid://121794505904244",
    ["Love Nessie"] = "rbxassetid://120503903398099",
    ["MACHODON"] = "rbxassetid://130552446361290",
    ["Monster Shark"] = "rbxassetid://109551787474599",
    ["Moonwake Ray"] = "rbxassetid://87417594759708",
    ["Mosasaur Shark"] = "rbxassetid://119021943786069",
    ["Pelagon"] = "rbxassetid://107218888924440",
    ["Riftborn Arowana"] = "rbxassetid://95701753644235",
    ["Starglass Guardian"] = "rbxassetid://98146489999756",
    ["Strawberry Choc Megalodon"] = "rbxassetid://113501574324315",
    ["Strawberry Orca"] = "rbxassetid://130161552256138",
    ["Talon Serpent"] = "rbxassetid://108665275325646",
    ["Zombie Shark"] = "rbxassetid://118840558184490",
    ["Alien Dumbo"] = "rbxassetid://128286231503570",
    ["Astral Kelpie"] = "rbxassetid://126269480898079",
    ["Cloudy Clown Fish"] = "rbxassetid://87304745725267",
    ["Cloudy Seal"] = "rbxassetid://140661976882978",
    ["Comet Toad"] = "rbxassetid://119821385082086",
    ["Constellation Kittyfish"] = "rbxassetid://140207585843469",
    ["Cowboy Octopus"] = "rbxassetid://97628300043628",
    ["Dream Jelly"] = "rbxassetid://101465505536352",
    ["Everblaze"] = "rbxassetid://97301252727253",
    ["Helios Wrasse"] = "rbxassetid://138920389571449",
    ["Moonribbon"] = "rbxassetid://104502566570668",
    ["Mr. Bubbles"] = "rbxassetid://106179266201603",
    ["Radiant Catfish"] = "rbxassetid://79120957970216",
    ["Rainy Koi"] = "rbxassetid://139379489409075",
    ["Saturnpuff"] = "rbxassetid://73799332410580",
    ["Solar Koi"] = "rbxassetid://132358226825805",
    ["Tidecrest Dolphin"] = "rbxassetid://92733459298447",
    ["Sparkly Eel"] = "rbxassetid://130960270024387",
    ["Starbell Angler"] = "rbxassetid://74755593085536",
    ["Starbloom Jelly"] = "rbxassetid://72807328965207",
    ["Starbloom Manta"] = "rbxassetid://99711256305287",
    ["Starlight Scampi"] = "rbxassetid://125282307411862",
    ["Twinkle Star Jelly"] = "rbxassetid://105121842462758",
    ["Twinkleclaw"] = "rbxassetid://93710326460650",
    ["Ancient Pufferfish"] = "rbxassetid://94080226439959",
    ["Crystal Pufferfish"] = "rbxassetid://112088257164749",
    ["Cute Octopus"] = "rbxassetid://101240566251348",
    ["Glowspore Toad"] = "rbxassetid://78757139553667",
    ["Pilot Fish"] = "rbxassetid://114269547366510",
    ["Pink Dolphin"] = "rbxassetid://86256600614394",
    ["Prismy Seahorse"] = "rbxassetid://105300029672501",
    ["Radiant Dolphin"] = "rbxassetid://131894183285640",
    ["Rubber Ducky"] = "rbxassetid://82654651283708",
    ["Sapphyra"] = "rbxassetid://113400641461947",
    ["Silly Easter Duck"] = "rbxassetid://108887524454215",
    ["Abyr Squid"] = "rbxassetid://119969620866795",
    ["Abyss Seahorse"] = "rbxassetid://140212951494890",
    ["Ancient Magma Whale"] = "rbxassetid://79419619363511",
    ["Ancient Squid"] = "rbxassetid://103962641004338",
    ["Aurora Starfish"] = "rbxassetid://80178492807600",
    ["Axolotl"] = "rbxassetid://76558551981982",
    ["Baby Maya Fish"] = "rbxassetid://131357209936807",
    ["Bioluminescent Manta Ray"] = "rbxassetid://115522251824285",
    ["Blob Shark"] = "rbxassetid://120294742064292",
    ["Blocky Lochness Monster"] = "rbxassetid://132674647664341",
    ["Bloodmoon Whale"] = "rbxassetid://113886190969614",
    ["Blue Lobster"] = "rbxassetid://79569787883962",
    ["Blue Sea Dragon"] = "rbxassetid://87051285933726",
    ["Blueflame Ray"] = "rbxassetid://113303332536600",
    ["Caeruleum Razerback"] = "rbxassetid://104374429564135",
    ["Cavern Dweller"] = "rbxassetid://110427632040144",
    ["Coral Reaper"] = "rbxassetid://101738084296566",
    ["Coral Whale"] = "rbxassetid://118677548023630",
    ["Cosmic Bass"] = "rbxassetid://77233971011934",
    ["Cosmic Mutant Shark"] = "rbxassetid://73059280090488",
    ["Cryoshade Glider"] = "rbxassetid://107008051913908",
    ["Crystal Goliath"] = "rbxassetid://99835874671011",
    ["Crystalline Behemoth"] = "rbxassetid://84364000635470",
    ["Darwin Clownfish"] = "rbxassetid://109996187340520",
    ["Deepsea Leech"] = "rbxassetid://113281885958896",
    ["Depthseeker Ray"] = "rbxassetid://92527448781061",
    ["Eerie Shark"] = "rbxassetid://114252804065144",
    ["Elemental Tempestray"] = "rbxassetid://116857965937952",
    ["Elpirate Gran Maja"] = "rbxassetid://131441237084542",
    ["Elshark Gran Maja"] = "rbxassetid://115522161459382",
    ["Emberback Spider Crab"] = "rbxassetid://118591368349318",
    ["Enchanted Angelfish"] = "rbxassetid://108347802265821",
    ["Flame Tyrant"] = "rbxassetid://72886777827927",
    ["Flatheaded Whale Shark"] = "rbxassetid://73809550216371",
    ["Fluorivane"] = "rbxassetid://76689054310510",
    ["Frostborn Shark"] = "rbxassetid://125463067542850",
    ["Frostmoon Whale"] = "rbxassetid://79116906979409",
    ["Ghost Shark"] = "rbxassetid://102028503382077",
    ["Ghostlight Oarfish"] = "rbxassetid://127259190499355",
    ["Giant Squid"] = "rbxassetid://135470649745250",
    ["Gilded Giant Isopod"] = "rbxassetid://71711170092047",
    ["Gladiator Shark"] = "rbxassetid://131785277053113",
    ["Ragnarex"] = "rbxassetid://110734945290028",
    ["Astrelle"] = "rbxassetid://134189875557993",
    ["Great Whale"] = "rbxassetid://110349456710432",
    ["Hammerhead Shark"] = "rbxassetid://91373020648344",
    ["Horseshoe Crab"] = "rbxassetid://86456527945308",
    ["Hybodus Shark"] = "rbxassetid://97369977225977",
    ["King Crab"] = "rbxassetid://136951139611035",
    ["King Jelly"] = "rbxassetid://104757933481327",
    ["Korblox Shark"] = "rbxassetid://136829917357354",
    ["Lavafin Tuna"] = "rbxassetid://96111934641941",
    ["Lobster"] = "rbxassetid://106973499045957",
    ["Lochness Monster"] = "rbxassetid://88964613838360",
    ["Lumenray"] = "rbxassetid://135399887019150",
    ["Luminous Fish"] = "rbxassetid://78374908088019",
    ["Luminous Thornyhead"] = "rbxassetid://99741495690083",
    ["Magma Shark"] = "rbxassetid://133485972581430",
    ["Magma Swordfish"] = "rbxassetid://90983146928602",
    ["Manta Ray"] = "rbxassetid://88385941559907",
    ["Megalodon"] = "rbxassetid://126066407227328",
    ["Panther Eel"] = "rbxassetid://101328665301159",
    ["Phantom Goblin Shark"] = "rbxassetid://122833094819099",
    ["Pirate Megalodon"] = "rbxassetid://111717850876602",
    ["Plasma Serpent"] = "rbxassetid://129918689550932",
    ["Plasma Shark"] = "rbxassetid://88847410678758",
    ["Primordial Octopus"] = "rbxassetid://102375471622278",
    ["Queen Crab"] = "rbxassetid://73709080100110",
    ["Robot Kraken"] = "rbxassetid://95734141724576",
    ["Runic Abyssal Shark"] = "rbxassetid://89862768656792",
    ["Runic Sea Crustacean"] = "rbxassetid://78787372617743",
    ["Runic Squid"] = "rbxassetid://76096764311236",
    ["Sacred Guardian Squid"] = "rbxassetid://129358445149074",
    ["Scare"] = "rbxassetid://76893887663677",
    ["Scorching Veinmaw"] = "rbxassetid://130117020359343",
    ["Sea Eater"] = "rbxassetid://94750467234464",
    ["Sharp One"] = "rbxassetid://84629313345829",
    ["Skeleton Narwhal"] = "rbxassetid://72248976760148",
    ["Spine Eel"] = "rbxassetid://78210102976480",
    ["Starlight Manta Ray"] = "rbxassetid://132585714096538",
    ["Glacierback Sea Turtle"] = "rbxassetid://110505216403394",
    ["Thin Armor Shark"] = "rbxassetid://123540389497955",
    ["Thunderzilla"] = "rbxassetid://100901086602309",
    ["Vampire Squid"] = "rbxassetid://87203317027314",
    ["Viridis Lurker"] = "rbxassetid://104425720050620",
    ["Voidlight Deepfish"] = "rbxassetid://96750512492708",
    ["Worm Fish"] = "rbxassetid://88157067345872",
    ["ELEMENTAL HYDRA"] = "rbxassetid://97892641589815",
    ["Crimson Dreadtusk"] = "rbxassetid://121698261616702",
    ["Everbloom"] = "rbxassetid://119244536069110",
    ["Iridesca"] = "rbxassetid://92850313420357",
    ["VeloByte"] = "rbxassetid://87480890153006",
    ["GigaByte"] = "rbxassetid://82113529654342",
    ["Mr Money Bags"] = "rbxassetid://79425130872856",
    ["Jellybeam"] = "rbxassetid://90794797545427",
    ["Stormshell Brute"] = "rbxassetid://108844510160138",
    ["Pyrocoil"] = "rbxassetid://83448114611390",
    ["Shellshock X"] = "rbxassetid://74747147486812",
    ["Ashen Kingfish"] = "rbxassetid://75710475218086",
}
local DEFAULT_ICON = "rbxassetid://6764432293"


local MUTATION_WORDS = {
    "Big", "Golden", "Shiny", "Glowing", "Frozen", "Toxic", "Rainbow",
    "Mythic", "Cursed", "Shadow", "Electric", "Magma", "Ice", "Storm",
    "Crystal", "Molten", "Emerald", "Ruby", "Sapphire", "Diamond",
    "Void", "Radiance", "Ancient", "Aquatic", "Hydro",
}
local function StripMutation(name)
    local base = name:match("^(.-)%s*%[") or name
    for _, w in ipairs(MUTATION_WORDS) do
        local pre = w .. " "
        if base:sub(1, #pre) == pre then
            base = base:sub(#pre + 1)
        end
    end
    return (base:gsub("^%s+", ""):gsub("%s+$", ""))
end


local CORE_ICON_FALLBACK = "rbxassetid://116659997697473"
local CORE_NAME_FALLBACK = "Withering Core"
local CoreCfg, CoreCfgTried = nil, false
local function LoadCoreCfg()
    if CoreCfgTried then return CoreCfg end
    CoreCfgTried = true
    pcall(function()
        CoreCfg = require(ReplicatedStorage.Modules.Fishing.CoreConfig)
    end)
    return CoreCfg
end
local function CoreItemName()
    LoadCoreCfg()
    if CoreCfg and type(CoreCfg.NamaItem) == "string" and CoreCfg.NamaItem ~= "" then
        return CoreCfg.NamaItem
    end
    return CORE_NAME_FALLBACK
end
local function CoreIcon()
    LoadCoreCfg()
    if CoreCfg and type(CoreCfg.Icon) == "string" and CoreCfg.Icon ~= "" then
        return CoreCfg.Icon
    end
    return CORE_ICON_FALLBACK
end


local function IsCoreCatch(name, data)
    if type(data) == "table" then
        if data.CoreId ~= nil or data.coreId ~= nil then return true end
        if data.isCore == true or data.core == true then return true end
        if type(data.rarity) == "string" and string.upper(data.rarity) == "CORE" then return true end
        if type(data.grade) == "string" and string.upper(data.grade) == "CORE" then return true end
    end
    local n = tostring(name or "")
    if n == "" then return false end
    if n == CoreItemName() then return true end
    if n:gsub("%s+$", ""):sub(-5) == " Core" then return true end
    return false
end


local FishImageDB, FishImageTried = nil, false
local function HookFishImage(name, data)
    if not name then return DEFAULT_ICON end


    if type(data) == "table" then
        local direct = data.ikon or data.icon or data.Icon
        if type(direct) == "string" and direct ~= "" then return direct end
    end

    if IsCoreCatch(name, data) then return CoreIcon() end
    if not FishImageTried then
        FishImageTried = true
        pcall(function()
            FishImageDB = require(ReplicatedStorage.Modules.Fishing.FishingImageDatabase)
        end)
    end

    if FishImageDB and FishImageDB.Fish then
        local n = tostring(name)
        local entry = FishImageDB.Fish[n] or FishImageDB.Fish[n:gsub("%s+", "")] or FishImageDB.Fish[StripMutation(n)]
        if type(entry) == "table" and entry.Icon then return entry.Icon end
        if type(entry) == "string" then return entry end
    end

    local n = tostring(name)
    local icon = FISH_ICONS[n]
        or FISH_ICONS[n:gsub("%s+", "")]
        or FISH_ICONS[StripMutation(n)]
    return icon or DEFAULT_ICON
end


local ThumbCache = {}
local function GetRequestFn()
    return (syn and syn.request) or (http and http.request) or http_request
        or (fluxus and fluxus.request) or (request)
end
local function ResolveAssetUrl(id)
    if ThumbCache[id] then return ThumbCache[id] end


    local fallback = "https://www.roblox.com/asset-thumbnail/image?assetId=" .. id
                  .. "&width=420&height=420&format=png"
    local api = "https://thumbnails.roblox.com/v1/assets?assetIds=" .. id
              .. "&size=420x420&format=Png&isCircular=false"
    local url = fallback
    local req = GetRequestFn()
    if req then
        for _ = 1, 5 do
            local ok, res = pcall(req, { Url = api, Method = "GET" })
            local body = ok and res and (res.Body or res.body)
            if body then
                local okd, data = pcall(HttpService.JSONDecode, HttpService, body)
                local d = okd and data and data.data and data.data[1]
                if d and d.imageUrl and d.state == "Completed" then
                    url = d.imageUrl
                    break
                end

                if d and d.state ~= "Pending" then break end
            else
                break
            end
            task.wait(0.6)
        end
    end
    ThumbCache[id] = url
    return url
end

local function HookThumbUrl(asset)
    if not asset then return nil end
    local id = tostring(asset):match("(%d+)")
    if not id then return asset end
    return ResolveAssetUrl(id)
end

local RARITY_COLOR = {
    Common    = 0x9E9E9E,
    UnCommon  = 0x4CAF50,
    Rare      = 0x2196F3,
    Epic      = 0x9C27B0,
    Legendary = 0xFF9800,
    Mythical  = 0xFF4081,
    Secret    = 0xFF3B3B,
    Forgotten = 0x607D8B,
}


local function HookShouldSend(rarity)
    if next(Hook.Rarities) == nil then return true end
    rarity = tostring(rarity or "Common")
    for _, r in ipairs(Hook.Rarities) do
        if r == rarity then return true end
    end
    return false
end


HookSendCatch = function(data)
    if not Hook.Enabled then return end
    if not Hook.Url or Hook.Url == "" then return end
    if type(data) ~= "table" then return end

    local name = data.baseName or data.originalName or data.toolName or "Mystery Fish"
    local isCore = IsCoreCatch(name, data)
    local rarity = tostring(data.rarity or data.grade or "Common")

    if isCore then rarity = "CORE" end
    local weight = tonumber(data.weight) or 0
    local mutation = tostring(data.mutation or "Normal")

    if not HookShouldSend(rarity) then return end

    local tierUp = string.upper(rarity)

    Hook.LastSent = tick()
    Hook.Sent = (Hook.Sent or 0) + 1

    local embed = {

        color  = RARITY_COLOR[rarity] or (isCore and 0x8A2BE2 or 0x5865F2),
        fields = {
            { name = "Item Name :", value = tostring(name),                        inline = false },
            { name = "Tier :",      value = tierUp,                                inline = false },
            { name = "Weight :",    value = string.format("%.2f Kg", weight),      inline = false },
            { name = "Mutation :",  value = mutation,                              inline = false },
        },
        footer = {
            text    = "Choco Webhook  -  Mount Soreya",

        },
        timestamp = DateTime.now():ToIsoDate(),
    }

    local content
    if isCore then
        content = "You have obtained a new CORE - " .. tostring(name) .. "!"
    else
        content = "You have obtained a new " .. tierUp .. " fish - " .. tostring(name) .. "!"
    end
    local payload = {
        username = "Choco Webhook",
        content  = content,
        embeds   = { embed },
    }
    if Hook.MentionId and Hook.MentionId ~= "" then
        payload.content = "<@" .. tostring(Hook.MentionId):gsub("%D", "") .. ">  " .. payload.content
    end


    task.spawn(function()

        local img = HookThumbUrl(HookFishImage(name, data))
        if img then embed.image = { url = img } end

        local logo = HookThumbUrl(HUB.LogoId)
        if logo then embed.footer.icon_url = logo end

        local ok, err = HookRequest(Hook.Url, payload)
        if not ok and err == "no_http" then
            Notify("Webhook", "Your executor has no HTTP request function", 5)
        end
    end)
end
_G.X0_MTS_HookSend = HookSendCatch


do
    local S = Tabs.Hook:Section({ Title = "Discord Webhook" })

    S:Toggle({
        Title = "Enable Catch Webhook", Value = false,
        Callback = function(v)
            Hook.Enabled = v
            Notify("Webhook", v and "ON (fish will be posted)" or "OFF", 2)
        end,
    })

    S:Input({
        Title = "Webhook URL", Icon = "link", Value = "",
        Callback = function(v) Hook.Url = tostring(v) end,
    })

    S:Input({
        Title = "Mention ID (optional)", Icon = "at-sign", Value = "",
        Callback = function(v) Hook.MentionId = tostring(v) end,
    })

    S:Space()


    local rarityDD = S:Dropdown({
        Title = "Rarity Filter (empty = all fish)",
        Values = Hook.AllRarities,
        Value = {},
        Multi = true,
        SearchBarEnabled = false,
        Callback = function(v)
            Hook.Rarities = {}
            if type(v) == "table" then
                for _, r in ipairs(v) do Hook.Rarities[#Hook.Rarities + 1] = r end
            elseif v ~= nil then
                Hook.Rarities = { tostring(v) }
            end
            if next(Hook.Rarities) == nil then
                Notify("Webhook", "Rarity: ALL fish", 2)
            else
                Notify("Webhook", "Rarity: " .. table.concat(Hook.Rarities, ", "), 3)
            end
        end,
    })

    S:Space()


    local probeName = "Great Whale"
    S:Input({
        Title = "Test Fish Image (type a fish name)", Icon = "image", Value = probeName,
        Callback = function(v) probeName = tostring(v) end,
    })

    S:Button({
        Title = "Resolve Fish Image URL", Icon = "image",
        Callback = function()
            local nm = probeName
            local asset = HookFishImage(nm)
            local url = HookThumbUrl(asset)
            if setclipboard then pcall(setclipboard, tostring(url)) end
            Notify("Webhook", tostring(nm) .. " -> " .. tostring(asset) .. " (url copied)", 5)
            pcall(function() print("[MTSOREYA] image " .. tostring(nm) .. " asset=" .. tostring(asset) .. " url=" .. tostring(url)) end)
        end,
    })

    S:Button({
        Title = "Send Test Webhook", Icon = "send",
        Callback = function()
            if Hook.Url == "" then
                Notify("Webhook", "Paste a webhook URL first", 3)
                return
            end
            local wasEnabled = Hook.Enabled
            Hook.Enabled = true
            HookSendCatch({ baseName = "Cerulean Dragon", rarity = "Forgotten", weight = 1000000, mutation = "None" })
            Hook.Enabled = wasEnabled
            Notify("Webhook", "Test sent", 3)
        end,
    })


    S:Button({
        Title = "Send Test Core Webhook", Icon = "gem",
        Callback = function()
            if Hook.Url == "" then
                Notify("Webhook", "Paste a webhook URL first", 3)
                return
            end
            local wasEnabled = Hook.Enabled
            Hook.Enabled = true
            HookSendCatch({
                baseName = CoreItemName(),
                CoreId = "test",
                rarity = "CORE",
                weight = tonumber(CoreCfg and CoreCfg.BeratNormal and CoreCfg.BeratNormal.max) or 1000,
                mutation = "Normal",
            })
            Hook.Enabled = wasEnabled
            Notify("Webhook", "Core test sent (image = " .. tostring(CoreIcon()) .. ")", 4)
        end,
    })

    S:Button({
        Title = "Clear Rarity Filter (all fish)", Icon = "filter",
        Callback = function()
            Hook.Rarities = {}
            pcall(function() rarityDD:Refresh({}) end)
            Notify("Webhook", "Rarity: ALL fish", 2)
        end,
    })

    S:Button({
        Title = "Clear Webhook URL", Icon = "trash",
        Callback = function()
            Hook.Url = ""
            Notify("Webhook", "URL cleared", 2)
        end,
    })
end


local Fly = {
    Active = false,
    Speed  = 50,
    Thread = nil,
    Bv     = nil,
    Bg     = nil,
    Jump   = nil,
    Down   = false,
}

function Fly.Stop()
    Fly.Active = false
    Fly.Down = false
    if Fly.Bv then pcall(function() Fly.Bv:Destroy() end) Fly.Bv = nil end
    if Fly.Bg then pcall(function() Fly.Bg:Destroy() end) Fly.Bg = nil end
    if Fly.Jump then pcall(function() Fly.Jump:Disconnect() end) Fly.Jump = nil end
    Fly.Thread = nil
    local char = Char()
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() hum.PlatformStand = false end) end
end

function Fly.Start(speed)
    Fly.Stop()
    local char = Char()
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (char and hrp and hum) then
        Notify("Fly", "Character not ready", 2)
        return false
    end
    Fly.Active = true
    Fly.Speed = speed or Fly.Speed or 50
    pcall(function() hum.PlatformStand = true end)

    local bv = Instance.new("BodyVelocity")
    bv.Velocity = Vector3.zero
    bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    bv.Parent   = hrp
    Fly.Bv = bv

    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    bg.D = 100
    bg.Parent = hrp
    Fly.Bg = bg


    Fly.Jump = UserInputService.JumpRequest:Connect(function()
        if not Fly.Active then return end
        local h = Char() and Char():FindFirstChildOfClass("Humanoid")
        if h then pcall(function() h.Jump = true end) end
    end)

    Fly.Thread = task.spawn(function()
        while Fly.Active and hrp and hrp.Parent do
            local cam = Camera or workspace.CurrentCamera
            local cf = cam and cam.CFrame
            if cf then


                local fwd, right = MoveInput(hum)
                local look = Vector3.new(cf.LookVector.X,  0, cf.LookVector.Z)
                local side = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
                local move = Vector3.zero
                if look.Magnitude > 0.001 then move = move + look.Unit * fwd   end
                if side.Magnitude > 0.001 then move = move + side.Unit * right end

                if move.Magnitude > 1 then move = move.Unit end


                local vert = 0
                if hum.Jump or UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                    vert = vert + 1
                end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or Fly.Down then
                    vert = vert - 1
                end
                if vert ~= 0 then
                    move = move + Vector3.new(0, vert, 0)
                end

                pcall(function() hum.Jump = false end)

                bv.Velocity = move * Fly.Speed
                bg.CFrame = cf
            end
            RunService.Heartbeat:Wait()
        end
    end)
    return true
end
_G.X0_MTS_Fly = Fly

do
    local S = Tabs.Misc:Section({ Title = "Fly" })
    S:Toggle({ Title = "Enable Fly", Value = false,
        Callback = function(v)
            if v then
                local ok = Fly.Start(Fly.Speed)
                if not ok then Fly.Stop() end
                Notify("Fly", ok and "ON  (joystick to move, hold JUMP to rise)" or "OFF", 3)
            else
                Fly.Stop()
                Notify("Fly", "OFF", 2)
            end
        end })
    S:Slider({ Title = "Fly Speed", Value = { Min = 5, Max = 300, Default = 50 }, Step = 1,
        Callback = function(v)
            Fly.Speed = math.floor(v)
        end })
end


local AntiAFK = { Enabled = false }
_G.X0_MTS_AntiAFK = AntiAFK

ConnMgr:Add(LocalPlayer.Idled:Connect(function()
    if not AntiAFK.Enabled then return end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end)
end))

do
    local S = Tabs.Misc:Section({ Title = "Anti-AFK" })
    S:Toggle({ Title = "Enable Anti-AFK", Value = false,
        Callback = function(v)
            AntiAFK.Enabled = v
            Notify("Anti-AFK", v and "ON (never get kicked for idling)" or "OFF", 2)
        end })
end


local Invis = { Enabled = false, Conn = nil, Saved = {} }
_G.X0_MTS_Invis = Invis

local function InvisApply()
    local char = Char()
    if not char then return end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") or d:IsA("Decal") then
            if Invis.Saved[d] == nil then
                Invis.Saved[d] = d.Transparency
            end
            pcall(function() d.Transparency = 1 end)
            pcall(function() d.LocalTransparencyModifier = 1 end)
        end
    end
end

function Invis.Stop()
    Invis.Enabled = false
    if Invis.Conn then pcall(function() Invis.Conn:Disconnect() end) Invis.Conn = nil end
    for obj, t in pairs(Invis.Saved) do
        pcall(function()
            if obj and obj.Parent then
                obj.Transparency = t
                obj.LocalTransparencyModifier = 0
            end
        end)
    end
    Invis.Saved = {}
end

function Invis.Start()
    Invis.Stop()
    Invis.Enabled = true
    InvisApply()
    Invis.Conn = RunService.Stepped:Connect(function()
        if not Invis.Enabled then return end
        InvisApply()
    end)
    return true
end

do
    local S = Tabs.Misc:Section({ Title = "Invisible Avatar" })
    S:Toggle({ Title = "Enable Invisible Avatar", Value = false,
        Callback = function(v)
            if v then
                Invis.Start()
                Notify("Invisible", "ON (your character is hidden)", 2)
            else
                Invis.Stop()
                Notify("Invisible", "OFF", 2)
            end
        end })
end


local InvisGui = { Enabled = false, Conn = nil, Saved = {} }
_G.X0_MTS_InvisGui = InvisGui

local function InvisGuiApply()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return end
    for _, g in ipairs(pg:GetChildren()) do
        if g:IsA("ScreenGui") then
            if InvisGui.Saved[g] == nil then
                InvisGui.Saved[g] = g.Enabled
            end
            pcall(function() g.Enabled = false end)
        end
    end
end

function InvisGui.Stop()
    InvisGui.Enabled = false
    if InvisGui.Conn then pcall(function() InvisGui.Conn:Disconnect() end) InvisGui.Conn = nil end
    for gui, was in pairs(InvisGui.Saved) do
        pcall(function()
            if gui and gui.Parent then gui.Enabled = was end
        end)
    end
    InvisGui.Saved = {}
end

function InvisGui.Start()
    InvisGui.Stop()
    InvisGui.Enabled = true
    InvisGuiApply()
    InvisGui.Conn = RunService.Stepped:Connect(function()
        if not InvisGui.Enabled then return end
        InvisGuiApply()
    end)
    return true
end

do
    local S = Tabs.Misc:Section({ Title = "Invisible GUI" })
    S:Toggle({ Title = "Hide All GUI", Value = false,
        Callback = function(v)
            if v then
                InvisGui.Start()
                Notify("Invisible GUI", "ON (game UI hidden)", 2)
            else
                InvisGui.Stop()
                Notify("Invisible GUI", "OFF", 2)
            end
        end })
end


local NoAnim = { Enabled = false, Conn = nil }
_G.X0_MTS_NoAnim = NoAnim

local function GetAnimator()
    local char = Char()
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local anim = hum and hum:FindFirstChildOfClass("Animator")
    if not anim and hum then
        anim = Instance.new("Animator")
        anim.Parent = hum
    end
    return anim
end

function NoAnim.Stop()
    NoAnim.Enabled = false
    if NoAnim.Conn then pcall(function() NoAnim.Conn:Disconnect() end) NoAnim.Conn = nil end
end

function NoAnim.Start()
    NoAnim.Stop()
    NoAnim.Enabled = true
    NoAnim.Conn = RunService.Stepped:Connect(function()
        if not NoAnim.Enabled then return end
        local anim = GetAnimator()
        if not anim then return end
        pcall(function()
            for _, track in ipairs(anim:GetPlayingAnimationTracks()) do
                track:Stop(0)
            end
        end)
    end)
    return true
end

do
    local S = Tabs.Misc:Section({ Title = "No Animation" })
    S:Toggle({ Title = "Disable Rod / Character Animations", Value = false,
        Callback = function(v)
            if v then
                NoAnim.Start()
                Notify("No Animation", "ON (rod animations hidden)", 2)
            else
                NoAnim.Stop()
                Notify("No Animation", "OFF", 2)
            end
        end })
end


local FPSCounter = {
    Enabled    = false,
    Gui        = nil,
    Labels     = nil,
    Frames     = 0,
    LastUpdate = 0,
    LastValue  = 0,
    LastPing   = 0,
}
_G.X0_MTS_FPS = FPSCounter

local function DestroyFPS()
    if FPSCounter.Gui then pcall(function() FPSCounter.Gui:Destroy() end) end
    FPSCounter.Gui = nil
    FPSCounter.Labels = nil
end

function FPSCounter.Build()
    DestroyFPS()
    local gp = GuiParent()
    if not gp then return end
    local sg = Instance.new("ScreenGui")
    sg.Name = "Choco_SOREYAPREMIUM_FPS"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.DisplayOrder = 998
    local ok = pcall(function() sg.Parent = gp end)
    if not ok then pcall(function() sg.Parent = LocalPlayer:WaitForChild("PlayerGui", 5) end) end

    local pill = Instance.new("Frame")
    pill.Name = "Pill"
    pill.Size = UDim2.new(0, 105, 0, 20)
    pill.Position = UDim2.new(0, 10, 0, 10)
    pill.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
    pill.BackgroundTransparency = 0.15
    pill.BorderSizePixel = 0
    pill.Active = true
    pill.Parent = sg
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
    local stroke = Instance.new("UIStroke", pill)
    stroke.Color = Color3.fromRGB(45, 45, 55)
    stroke.Thickness = 1
    stroke.Transparency = 0.3
    local layout = Instance.new("UIListLayout", pill)
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center

    local fpsLbl = Instance.new("TextLabel", pill)
    fpsLbl.Size = UDim2.new(0, 42, 1, 0)
    fpsLbl.BackgroundTransparency = 1
    fpsLbl.Text = " fps"
    fpsLbl.TextColor3 = Color3.fromRGB(255, 90, 90)
    fpsLbl.Font = Enum.Font.GothamBold
    fpsLbl.TextSize = 11
    fpsLbl.TextXAlignment = Enum.TextXAlignment.Right
    fpsLbl.LayoutOrder = 1

    local sep = Instance.new("TextLabel", pill)
    sep.Size = UDim2.new(0, 12, 1, 0)
    sep.BackgroundTransparency = 1
    sep.Text = " . "
    sep.TextColor3 = Color3.fromRGB(180, 180, 180)
    sep.Font = Enum.Font.GothamBold
    sep.TextSize = 11
    sep.LayoutOrder = 2

    local pingLbl = Instance.new("TextLabel", pill)
    pingLbl.Size = UDim2.new(0, 46, 1, 0)
    pingLbl.BackgroundTransparency = 1
    pingLbl.Text = " ms"
    pingLbl.TextColor3 = Color3.fromRGB(120, 240, 120)
    pingLbl.Font = Enum.Font.GothamBold
    pingLbl.TextSize = 11
    pingLbl.TextXAlignment = Enum.TextXAlignment.Left
    pingLbl.LayoutOrder = 3


    local dragging, dragStart, startPos = false, Vector2.zero, UDim2.new()
    pill.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = i.Position; startPos = pill.Position
        end
    end)
    pill.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            pill.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    pill.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    FPSCounter.Gui = sg
    FPSCounter.Labels = { fps = fpsLbl, ping = pingLbl }
end

local function GetPingMs()
    local ok, ping = pcall(function()
        return math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
    end)
    return (ok and ping) or 0
end


ConnMgr:Add(RunService.RenderStepped:Connect(function()
    if not (FPSCounter.Enabled and FPSCounter.Labels) then return end
    FPSCounter.Frames = FPSCounter.Frames + 1
    local now = tick()
    if now - FPSCounter.LastUpdate < 0.5 then return end
    local elapsed = now - FPSCounter.LastUpdate
    FPSCounter.LastValue = math.floor(FPSCounter.Frames / elapsed)
    FPSCounter.Frames = 0
    FPSCounter.LastUpdate = now
    FPSCounter.LastPing = GetPingMs()
    pcall(function()
        local L = FPSCounter.Labels
        if not L then return end
        L.fps.Text = FPSCounter.LastValue .. " fps"
        L.fps.TextColor3 = FPSCounter.LastValue >= 55 and Color3.fromRGB(120, 240, 120)
            or (FPSCounter.LastValue >= 30 and Color3.fromRGB(255, 210, 100) or Color3.fromRGB(255, 90, 90))
        L.ping.Text = FPSCounter.LastPing .. " ms"
        L.ping.TextColor3 = FPSCounter.LastPing < 100 and Color3.fromRGB(120, 240, 120)
            or (FPSCounter.LastPing < 250 and Color3.fromRGB(255, 210, 100) or Color3.fromRGB(255, 90, 90))
    end)
end))

function FPSCounter.SetVisible(v)
    FPSCounter.Enabled = v
    if v then FPSCounter.Build() else DestroyFPS() end
end


local function SetFPSCap(val)
    if val == "None" or val == "Unlimited" then
        if setfpscap then pcall(setfpscap, 9999) end
        Notify("FPS Cap", "Unlimited", 2)
    else
        local num = tonumber(val)
        if num and setfpscap then
            pcall(setfpscap, num)
            Notify("FPS Cap", num .. " FPS", 2)
        elseif not setfpscap then
            Notify("FPS Cap", "setfpscap not supported on this executor", 4)
        end
    end
end
_G.X0_MTS_SetFPSCap = SetFPSCap

do
    local S = Tabs.Misc:Section({ Title = "FPS + Ping" })
    S:Toggle({ Title = "FPS + Ping HUD", Value = false,
        Callback = function(v)
            FPSCounter.SetVisible(v)
            Notify("FPS + Ping", v and "ON (drag the pill to move it)" or "OFF", 2)
        end })
    S:Dropdown({
        Title = "Lock FPS", Values = { "None", "30", "60", "120", "144", "165", "180", "240", "360" },
        Value = "None", SearchBarEnabled = false,
        Callback = function(v) SetFPSCap(v) end,
    })
end


local function MasterCleanup()
    Auto.LoopStop = true
    Auto.Enabled = false
    StopAuto()
    pcall(function() Summit.Stop() end)
    pcall(function() if Automation and Automation.Running then Automation.Enabled = false; Automation.Running = false end end)
    pcall(Fly.Stop)
    pcall(function() if Invis.Stop then Invis.Stop() end end)
    pcall(function() if InvisGui.Stop then InvisGui.Stop() end end)
    pcall(function() if NoAnim.Stop then NoAnim.Stop() end end)
    pcall(DestroyAlert)
    pcall(function() if AutoMarker and AutoMarker.Stop then AutoMarker.Stop() end end)
    pcall(UninstallBaitPatch)
    pcall(DestroyFPS)
    pcall(function() if Galatama and Galatama.Stop then Galatama.Stop() end end)

    pcall(function()
        if Hook then
            Hook.Enabled = false
            Hook.Url = ""
            Hook.MentionId = ""
            Hook.Rarities = {}
        end
        _G.X0_MTS_Hook = nil
        _G.X0_MTS_HookSend = nil
    end)
    pcall(function() ConnMgr.Clear() end)
    pcall(ClearBiteConns)
    pcall(ClearReelConns)
    pcall(DestroyLogo)
    if _G[INSTANCE_KEY] then
        _G[INSTANCE_KEY].running = false
        local w = _G[INSTANCE_KEY].window or _G[INSTANCE_KEY].Window
        if w then pcall(function() w:Destroy() end) end
    end
    _G[INSTANCE_KEY] = nil
    Notify("Choco Hub", "Hub unloaded", 2)
end
_G[INSTANCE_KEY].cleanup = MasterCleanup
_G[INSTANCE_KEY].destroy = MasterCleanup
_G[INSTANCE_KEY].running = true


task.spawn(function()
    task.wait(0.5)
    DiscoverRod()
    InstallBiteWatch()
    InstallReelHook()

    pcall(InstallBaitPatch)


    if AutoActive() then StartAuto() end

    if Auto.AutoShowMarker then pcall(AutoMarker.Start) end
    Log("Choco Hub Premium Loaded")
    Notify("Choco Hub Premium", "Loaded", 4)
end)


task.spawn(function()
    task.wait(0.6)
    if State.FloatingLogo then
        local ok = FloatingLogo.Build()
        if not ok then
            for _ = 1, 3 do task.wait(1); if FloatingLogo.Build() then break end end
        end
    end
    while task.wait(5) do
        if State.FloatingLogo and not (State.LogoGui and State.LogoGui.Parent) then
            FloatingLogo.Build()
        end

        if FPSCounter.Enabled and not (FPSCounter.Gui and FPSCounter.Gui.Parent) then
            FPSCounter.Build()
        end
    end
end)


local _lastBoundMiniGame = nil
local _rodCheckAcc = 0
ConnMgr:Add(RunService.Heartbeat:Connect(function(dt)
    _rodCheckAcc = _rodCheckAcc + dt
    if _rodCheckAcc < 0.5 then return end
    _rodCheckAcc = 0
    local tool = getRodTool()
    if tool ~= Rod.Tool then
        DiscoverRod()
    end
    if Rod.MiniGame ~= _lastBoundMiniGame then
        _lastBoundMiniGame = Rod.MiniGame
        InstallBiteWatch()
        InstallReelHook()
    end
end))


ConnMgr:Add(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    DiscoverRod()
    InstallBiteWatch()
    InstallReelHook()

    if Invis.Enabled then pcall(Invis.Start) end
end))
