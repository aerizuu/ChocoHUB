local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local StarterGui         = game:GetService("StarterGui")
local CoreGui            = game:GetService("CoreGui")
local ContentProvider    = game:GetService("ContentProvider")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

local INSTANCE_KEY = "__CHOCO_MTSOREYA_v100"

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

local WindUI
do
    local ok, res = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
    end)
    if not ok or not res then error("[MTSOREYA] WindUI load failed: " .. tostring(res)) end
    WindUI = res
end

local HUB = {
    Name = "Choco Hub", Game = "Mount Soreya", Version = "1.9.0",
    Author = "Voixera", LogoId = "rbxassetid://122666578965463",
}

local function GuiParent()
    local p = CoreGui
    pcall(function() if gethui then p = gethui() end end)
    return p
end

local function Notify(title, content, dur)
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
    local function req(name)
        local inst = fish:FindFirstChild(name)
        if not inst then return nil end
        local ok, res = pcall(require, inst)
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
    ClaimDelay    = 1.22,    
    FastRecast    = true,    
    CastSettle    = 0.0,
    CastPower     = 20,                                
    PerfectCast   = true,    
    HideReelUI    = true,   
    InstantAlert  = true,  
    BaitFast      = true,   
    BaitTime      = 0.08,  
    Adaptive      = true, 
    LineActive    = false,
    LastCast      = 0,
    Busy          = false,
    LoopStop      = false,
    CaughtNotify  = true,
    LearnedClaim  = nil,
    MinClaim      = 1.05,
    MaxClaim      = 1.45,
}

local function AutoActive()
    return Auto.Enabled
end

local StartAuto, StopAuto, ReelOnce
local function FireCast()
    DiscoverRod()
    if not Rod.CastEvent then return false, "no_cast_remote" end
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
    end
    local ok1 = pcall(function() Rod.CastEvent:FireServer(true) end)
    local look = Camera.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.001 then flat = Vector3.new(0, 0, -1) end
    flat = flat.Unit
    if (Auto.CastSettle or 0) > 0 then task.wait(Auto.CastSettle) end
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

local Sell = { Auto = false, Interval = 1.5, Running = false, Total = 0 }
local function SellRemotes()
    local out = {}
    local rem = ReplicatedStorage:FindFirstChild("Remote")
    local mancing = rem and rem:FindFirstChild("Mancing")
    if mancing then
        local js = mancing:FindFirstChild("JualSemua")
        if js then out[#out + 1] = js end
        local jc = mancing:FindFirstChild("JualSemuaCore")
        if jc then out[#out + 1] = jc end
    end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local sf = remotes and remotes:FindFirstChild("SellFish")
    if sf then out[#out + 1] = sf end
    return out
end

local function FireSell()
    local list = SellRemotes()
    if #list == 0 then return false, "no_sell_remote" end
    local gained = nil
    local any = false
    for _, js in ipairs(list) do
        local ok, a, b = pcall(function()
            if js:IsA("RemoteFunction") then return js:InvokeServer() end
            js:FireServer()
            return nil
        end)
        if ok then
            any = true
            local coins = tonumber(a) or tonumber(b)
            if coins and coins > 0 then gained = (gained or 0) + coins end
            break
        end
    end
    if gained then Sell.Total = Sell.Total + gained end
    return any, any and "sell" or "sell_error", gained
end
_G.X0_MTS_FireSell = FireSell

local function StartSellLoop()
    if Sell.Running then return end
    Sell.Running = true
    task.spawn(function()
        while Sell.Running and Sell.Auto do
            task.wait(Sell.Interval)
            if Sell.Running and Sell.Auto then
                local ok, _, gained = FireSell()
                if ok and gained and gained > 0 and Auto.CaughtNotify then
                    Notify("Auto Sell", "Sold for " .. tostring(math.floor(gained)), 2)
                end
            end
        end
        Sell.Running = false
    end)
end
local function StopSellLoop()
    Sell.Auto = false
    Sell.Running = false
end

_G.X0_MTS_LastClaimedBite = _G.X0_MTS_LastClaimedBite or -1
local function FireClaim()
    DiscoverRod()
    if not Rod.MiniGame then return false, "no_minigame_remote" end
    local bite = Rod.LastBite or 0
    if bite ~= 0 and _G.X0_MTS_LastClaimedBite == bite then
        return false, "already_claimed"
    end
    _G.X0_MTS_LastClaimedBite = bite
    if Auto.BiteAt and Auto.BiteAt > 0 then
        Auto.LastClaimWait = tick() - Auto.BiteAt
    end
    local ok = pcall(function() Rod.MiniGame:FireServer(true) end)
    return ok, ok and "claim" or "claim_error"
end

local function FireClaimVariant()
    DiscoverRod()
    if not Rod.MiniGame then return false, "no_minigame_remote" end
    local variants = {
        { true },
        {},
        { 999 },
        { true, 999 },
    }
    for _, v in ipairs(variants) do
        local ok = pcall(function()
            if #v == 0 then Rod.MiniGame:FireServer() else Rod.MiniGame:FireServer(table.unpack(v)) end
        end)
        if ok then return true, "claim" end
    end
    return false, "claim_error"
end
_G.X0_MTS_FireClaimVariant = FireClaimVariant

local function ClaimWaitForBite()
    if Auto.Adaptive and Auto.LearnedClaim then
        return math.clamp(Auto.LearnedClaim, Auto.MinClaim or 1.05, Auto.MaxClaim or 1.45)
    end
    local base = Auto.ClaimDelay or 1.22
    return math.clamp(base, Auto.MinClaim or 1.05, Auto.MaxClaim or 1.45)
end
_G.X0_MTS_ClaimWaitForBite = ClaimWaitForBite

local function LearnClaim(success)
    if not Auto.Adaptive then return end
    local used = Auto.LastClaimWait or Auto.ClaimDelay or 1.22
    if success then
        Auto.LearnedClaim = math.max((Auto.MinClaim or 1.05), (Auto.LearnedClaim or used) - 0.02)
    else
        Auto.LearnedClaim = math.min((Auto.MaxClaim or 1.45), (Auto.LearnedClaim or used) + 0.06)
    end
end
_G.X0_MTS_LearnClaim = LearnClaim

ReelOnce = function(mgData)
    LoadGameModules()
    local mg = Game.MiniGame
    local delay = (ClaimWaitForBite and ClaimWaitForBite()) or math.min(Auto.ClaimDelay or 1.22, 1.45)
    local start = tick()
    Auto.BiteAt = Rod.LastBite or start
    if mg and mg.MobileTap and mg.IsActive then
        local w = tick()
        local active = false
        while AutoActive() and tick() - w < 0.6 do
            local okA, a = pcall(mg.IsActive)
            if okA and a then active = true; break end
            task.wait(0.02)
        end
        if active then
            local deadline = tick() + 6
            while AutoActive() and tick() < deadline do
                local okA, a = pcall(mg.IsActive)
                if not (okA and a) then return true, "landed" end
                for _ = 1, 4 do pcall(mg.MobileTap) end
                RunService.RenderStepped:Wait()
            end
        end
    end

    local target = (Rod.LastBite or start) + delay
    local wait = target - tick()
    if wait > 0 then task.wait(wait) end
    if Auto.LineActive == false and not IsReeling() then return true, "resolved" end
    return FireClaim()
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

local Alert = { Gui = nil, Gen = 0 }

function DestroyAlert()
    if Alert.Gui then pcall(function() Alert.Gui:Destroy() end) end
    Alert.Gui = nil
end

local function FireSharedMarker()
    DiscoverRod()
    local m = Rod.Marker
    if not (m and m:IsA("RemoteEvent")) then return end
    local red = Color3.fromRGB(255, 70, 70)
    local ok = pcall(function()
        m:FireServer(red, red, ColorSequence.new(red), 1.5)
    end)
    if not ok then
        pcall(function()
            m:FireServer(red, red, NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(1, 1),
            }), 1.5)
        end)
    end
end

local function ShowBiteAlert()
    if not Auto.InstantAlert then return end
    pcall(FireSharedMarker)
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

local Bait = { Part = nil, Acc = 0 }

local function IsBaitLike(inst)
    if not inst then return false end
    local ok, name = pcall(function() return inst.Name end)
    if not ok or not name then return false end
    local n = name:lower()
    if n:find("bait") or n:find("umpan") or n:find("pelampung") or n:find("float") then return true end
    return false
end

do
    local origCreate = TweenService.Create
    Bait.OrigCreate = origCreate
    local hooked = false
    pcall(function()
        TweenService.Create = newcclosure(function(self, inst, info, goal)
            if Auto.BaitFast and AutoActive() and IsBaitLike(inst) and info then
                local t = tonumber(info.Time)
                if t and t > (Auto.BaitTime or 0.12) then
                    local ok, newInfo = pcall(function()
                        return TweenInfo.new(Auto.BaitTime, info.EasingStyle, info.EasingDirection,
                            info.RepeatCount, info.Reverses, info.DelayTime)
                    end)
                    if ok and newInfo then info = newInfo end
                end
            end
            return origCreate(self, inst, info, goal)
        end)
        hooked = true
    end)
    Bait.TweenHooked = hooked
end

local function UnhookBaitTween()
    if Bait.OrigCreate and Bait.TweenHooked then
        pcall(function() TweenService.Create = Bait.OrigCreate end)
        Bait.TweenHooked = false
    end
end

local function GetBaitTarget()
    DiscoverRod()
    local t = Rod.Tool
    if not t then return nil end
    local mech = t:FindFirstChild("Mechanics")
    local cfg = mech and mech:FindFirstChild("Configuration")
    local st = cfg and cfg:FindFirstChild("Status")
    local bp = st and st:FindFirstChild("BaitPosition")
    if bp and bp:IsA("Vector3Value") then
        local v = bp.Value
        if v.Magnitude > 0.01 then return v end
    end
    return nil
end

local function FindBaitPart()
    if Bait.Part and Bait.Part.Parent then return Bait.Part end
    Bait.Part = nil
    local char = Char()
    local roots = { char, workspace }
    for _, root in ipairs(roots) do
        if root then
            local n = 0
            for _, d in ipairs(root:GetDescendants()) do
                n = n + 1
                if n > 4000 then break end
                if d:IsA("BasePart") and IsBaitLike(d) then
                    Bait.Part = d
                    return d
                end
            end
        end
    end
    return nil
end

local function SnapBaitToWater()
    if not (AutoActive() and Auto.BaitFast) then return end
    local target = GetBaitTarget()
    if not target then return end
    local part = FindBaitPart()
    if not part then return end
    if (part.Position - target).Magnitude > 1.5 then
        pcall(function() part.CFrame = CFrame.new(target) end)
    end
end

ConnMgr:Add(RunService.Heartbeat:Connect(function(dt)
    if not AutoActive() then return end
    if Auto.HideReelUI and Auto.LineActive then HideReelUI() end
    if Auto.BaitFast and (Auto.LineActive or (tick() - (Auto.LastCast or 0) < 4)) then
        Bait.Acc = Bait.Acc + dt
        local every = 0.08
        if Bait.Acc >= every then
            Bait.Acc = 0
            SnapBaitToWater()
        end
    end
end))

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
                    local poll = 0.03
                    if Auto.LineActive or IsReeling() then
                        if Auto.LineActive and (tick() - Rod.LastBite) > 3 then
                            Auto.LineActive = false
                        end
                        task.wait(poll)
                    elseif Auto.AutoCast and (tick() - Auto.LastCast > 0.35) then
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
                if LearnClaim then LearnClaim(true) end
                if Auto.CaughtNotify then
                    Notify("Fishing", "Caught: " .. tostring(data and (data.originalName or data.baseName) or "fish"), 3)
                end
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
    local now = tick()
    if now - (Rod.LastOnBite or 0) < 0.5 then return end
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
    sg.Name = "Choco_MTSOREYA_Logo"
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
    Title   = HUB.Name .. " v" .. HUB.Version,
    Author  = HUB.Game .. " | by " .. HUB.Author,
    Icon    = HUB.LogoId,
    Folder  = "ChocoHub",
    Size    = UDim2.fromOffset(600, 480),
    Transparent = false,
    Acrylic = false,
    Theme   = "Dark",
    User = { Enabled = true, Anonymous = false },
    HideSearchBar = true,
    ToggleKey = Enum.KeyCode.Insert,
    OpenButton = { Title = HUB.Author, Enabled = false, Draggable = true },
})
_G[INSTANCE_KEY] = { version = HUB.Version, window = Window }

local Tabs = {
    Fish     = Window:Tab({ Title = "Main",     Icon = "fish" }),
    Teleport = Window:Tab({ Title = "Teleport", Icon = "map-pin" }),
    Settings = Window:Tab({ Title = "Settings", Icon = "settings" }),
    Cfg      = Window:Tab({ Title = "Config",   Icon = "file-cog" }),
    Info     = Window:Tab({ Title = "Info",     Icon = "info" }),
}

do
    local S = Tabs.Fish:Section({ Title = "Instant Reel" })
    S:Toggle({
        Title = "Enable Instant Reel", Value = false,
        Callback = function(v)
            Auto.Enabled = v
            if AutoActive() then StartAuto() else StopAuto() end
            Notify("Instant Reel", v and "ON" or "OFF", 2)
        end,
    })
    S:Slider({
        Title = "Claim Delay x0.01s", Value = { Min = 105, Max = 145, Default = 122 }, Step = 1,
        Callback = function(v)
            Auto.ClaimDelay = v / 100
            Auto.LearnedClaim = nil
        end,
    })
    S:Toggle({ Title = "Adaptive Claim Speed", Value = true,
        Callback = function(v)
            Auto.Adaptive = v
            if not v then Auto.LearnedClaim = nil end
            Notify("Instant Reel", "Adaptive " .. (v and "ON" or "OFF"), 2)
        end })
end

do
    local S = Tabs.Fish:Section({ Title = "Auto Sell" })
    S:Toggle({ Title = "Enable Auto Sell", Value = false,
        Callback = function(v)
            Sell.Auto = v
            if v then StartSellLoop() else StopSellLoop() end
            Notify("Auto Sell", v and "ON (no NPC needed)" or "OFF", 2)
        end })
end

local Tp = {
    Presets = {
        CoreLocations = Vector3.new(-9035.890625, 1250.61279296875, -6511.6669921875),
        SpotMancing   = Vector3.new(-7833.33203125, 1236.7515869140625, -6327.37353515625),
    },
}

local function TpTo(pos, label)
    if typeof(pos) ~= "Vector3" then
        Notify("Teleport", (label or "Spot") .. " has no coordinates yet", 3)
        return
    end
    local char = Char()
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    pcall(function()
        hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
        char:PivotTo(CFrame.new(pos + Vector3.new(0, 3, 0)))
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
        Desc = "Game: " .. HUB.Game .. "\nAuthor: " .. HUB.Author,
    })
    S:Button({ Title = "Unload Hub", Icon = "power", Callback = function()
        if _G[INSTANCE_KEY] and _G[INSTANCE_KEY].cleanup then pcall(_G[INSTANCE_KEY].cleanup)
        else pcall(function() _G[INSTANCE_KEY].destroy() end) end
    end })
end

local function MasterCleanup()
    Auto.LoopStop = true
    Auto.Enabled = false
    StopAuto()
    pcall(StopSellLoop)
    pcall(DestroyAlert)
    pcall(UnhookBaitTween)
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
    if AutoActive() then StartAuto() end
    Log("Choco Hub - Mount Soreya v" .. HUB.Version .. " loaded")
    Notify("Choco Hub", "Mount Soreya v" .. HUB.Version .. " loaded", 4)
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
end))
