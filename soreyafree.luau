--═══════════════════════════════════════════════════════════════════════════
-- CHOCO HUB  -  MOUNT SOREYA  (FREE)
-- UI: WindUI (Footagesus)
-- Version: 0.0.1
-- Tabs: Main | Automation | Auto Summit | Teleport | Misc | Settings | Config | Info
--
-- FREE SCRIPT: Auto Summit, Fly, Auto Core Catch and Auto Accept Galatama are
-- LOCKED (shown but not usable). Everything else is the same as the full hub.
--
-- FEATURES ONLY  -  no diagnostics, no capture panels, no dumps.
--
-- AUTO SUMMIT (Auto Summit tab): the 21 Mount Soreya checkpoints are baked in.
-- The capture proved the game fires NOTHING client->server for a checkpoint, so
-- they are SERVER-SIDE ZONE triggers. The summit is a TouchPart named
-- "SummitPart" (Workspace...Summit.SummitPart) - the server counts the summit
-- when the character actually TOUCHES it. So:
--   * every checkpoint: teleport + DWELL (hold the exact spot for the delay),
--   * the summit (CP21): land directly ON SummitPart and keep touching it,
--   * after the summit: touch "BackBC" (Workspace...BackBC.BackBC) which sends
--     the player back to Basecamp, so the loop can restart at CP1.
-- Basecamp -> Summit, 2s per checkpoint (a bit longer at the summit), loops
-- until the toggle is turned OFF. The tab is ONE section with everything in one
-- place: an "Auto Summit" ON/OFF toggle, a "Loop" ON/OFF toggle, a live
-- "Current: CPn / 21" readout and a per-checkpoint delay slider.
-- Remote.Checkpoint.TpToCheckpoint(index) is still fired as a best-effort.
--
-- RESUME: the hub tracks WHICH checkpoint the avatar is on (a helper compares
-- your position to the checkpoint list). Pressing the Auto Summit toggle OFF
-- saves that as the resume point, so turning it back ON continues from the LAST
-- checkpoint instead of restarting at CP1. The "Current: CPn / 21" button also
-- refreshes the resume point from wherever the avatar is standing.
--
-- Lean UI: the Main tab holds Instant Reel only. Auto Sell was removed entirely;
-- the Rusdy sell NPC now has its own "Teleport to NPC Sell" button in the
-- Teleport tab. The old Toggles / Tuning / Manual sections, the animation-speed
-- feature, the MAX SPEED PRESET and Blatant Mode were removed; the fast defaults
-- are baked in.
--
-- Fishing cycle (from a REAL in-game capture of the game's FishingClient):
--   CAST      : <any rod>.Mechanics.Remotes.CastEvent:FireServer(true)
--               <any rod>.Mechanics.Remotes.CastEvent:FireServer(false, 20, <dir>)
--   BITE      : Rod.MiniGame("Start", {...}) + Rod.NotifyClient("Bite", {...})
--   REEL      : client-side MiniGameHandler.MobileTap() every input frame
--   REWARD    : Rod.NotifyClient("GotFish", {...}) + Rod.MiniGame("Stop")
--
-- IMPORTANT (corrected from the game's REAL FishingClient source):
--   the reel is 100% CLIENT-side. There is NO Rod.MiniGame:FireServer(true)
--   win call anywhere in the game. The server only OPENS the reel
--   (MiniGame "Start") and CLOSES it (MiniGame "Stop"); the win is decided
--   entirely inside the module MiniGameHandler, which the client drives by
--   calling MobileTap() on every input frame. The hub does the same.
--   SELL      : ReplicatedStorage.Remote.Mancing.JualSemua:InvokeServer()
--   MARKER    : ReplicatedStorage.TandaSeruBersama:FireServer(col, col, seq, 1.5)
--
-- It also reads the game's OWN modules (leaked from the client source):
--   Modules.Fishing.MiniGameHandler  - IsActive() = authoritative reel check.
--   Modules.Fishing.PowerBarHandler  - StopFill() = exact cast power.
--
-- FAST REEL AUTO works like this (NO clicking, NO per-rod setup):
--   1. Fire CastEvent(true) + CastEvent(false, 20, dir) to cast.
--   2. Bait lands almost instantly (bait tween cut to ~0.01s + snapped to
--      BaitPosition every frame).
--   3. Wait for the server's MiniGame("Start") bite; the local "!" marker shows
--      the instant the bite lands.
--   4. Land it: the reel is CLIENT-side, so we drive the game's own reel engine
--      with MiniGameHandler.MobileTap() every frame (Ultra: 6 taps/frame - fast
--      but capped so the server never rejects the reel). If our module copy is
--      not the game's live one we Setup()/Start() it first so the taps actually
--      register - that is what makes the fish LAND.
--   5. Recast instantly on GotFish/Stop. Repeat.
--   The game's "Klik Cepat!" tap bar is hidden while auto-reeling.
--
-- SUPER FAST REEL (Main tab, ON by default): a capped 6-tap burst per frame, a
-- 0ms cast throttle and a 2ms poll - so the casts chain with as little dead time
-- as the server accepts.
--   NOTE: there is NO client->server claim in this game (proven from its real
--   FishingClient). The old MiniGame:FireServer(true) claim was WRONG and has
--   been removed; the win is entirely decided by MobileTap().
--
-- WORKS WITH EVERY ROD (Ares, Bamboo, Element, Diamond, Withering, Ghostfinn,
-- Starter, ...): the hub binds to whatever rod is currently equipped and
-- re-binds automatically when you switch rods. There is no Rod tab and no
-- per-rod configuration - it just works on whatever rod you hold.
--
-- HONEST NOTE: the server still decides whether a fish is landed (rarity/chance
-- are rolled server-side). This makes the reeling as fast as the game allows -
-- it cannot force a 100% catch on a fish the server already rolled as a miss.
--═══════════════════════════════════════════════════════════════════════════

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

local INSTANCE_KEY = "__CHOCO_SOREYAFREE_v100"

-- unload previous build first (clean reload). We grab the slot IMMEDIATELY so a
-- second execution cannot start while this one is still booting (that was making
-- TWO live instances fire the rod's remotes, e.g. two MiniGame(true) calls, which
-- the server rejects with MiniGame(false) and the fish never lands).
if _G[INSTANCE_KEY] then
    local prev = _G[INSTANCE_KEY]
    _G[INSTANCE_KEY] = { booting = true }   -- claim the slot immediately
    if type(prev.cleanup) == "function" then pcall(prev.cleanup) end
    -- wait until the old runs' loops have actually stopped
    local waited = 0
    while prev.running and waited < 2 do task.wait(0.1); waited = waited + 0.1 end
    task.wait(0.2)
end

-- If a previous script (e.g. the diagnostic) left a __namecall hook on the game
-- metatable, it can swallow/slow the rod's own remotes. Restore the original.
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

--───────────────────────────────────────────────────────────────────────────
-- HELPERS
--───────────────────────────────────────────────────────────────────────────
local ConnMgr = { conns = {} }
function ConnMgr:Add(conn) table.insert(self.conns, conn); return conn end
function ConnMgr:Clear() for _, c in ipairs(self.conns) do pcall(function() c:Disconnect() end) end; self.conns = {} end

local function Char() return LocalPlayer.Character end
local function Hum() local c = Char(); return c and c:FindFirstChildOfClass("Humanoid") end

--───────────────────────────────────────────────────────────────────────────
-- WINDUI (Footagesus)
--───────────────────────────────────────────────────────────────────────────
local WindUI
do
    local ok, res = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
    end)
    if not ok or not res then error("[MTSOREYA] WindUI load failed: " .. tostring(res)) end
    WindUI = res
end

local HUB = {
    Name = "Choco HUB Free", Game = "Mount Soreya", Version = "0.0.1",
    Author = "", LogoId = "rbxassetid://122666578965463",
}

local function GuiParent()
    local p = CoreGui
    pcall(function() if gethui then p = gethui() end end)
    return p
end

local function Notify(title, content, dur)
    -- Belt-and-suspenders: when the user turns Summit notifications OFF, suppress
    -- ANY popup whose title is "Auto Summit", no matter which code path raised it.
    if _G.X0_MTS_SummitNotifyOff and tostring(title) == "Auto Summit" then return end
    pcall(function()
        WindUI:Notify({ Title = tostring(title), Content = tostring(content), Duration = tonumber(dur) or 3 })
    end)
end

--───────────────────────────────────────────────────────────────────────────
-- ROD / REMOTE DISCOVERY  (live - the rod is a Tool in the character)
--───────────────────────────────────────────────────────────────────────────
local Rod = {
    Tool        = nil,   -- the currently equipped fishing rod (any name)
    CastEvent   = nil,   -- Mechanics.Remotes.CastEvent
    MiniGame    = nil,   -- Mechanics.Remotes.MiniGame  (server -> client reel events)
    NotifyC     = nil,   -- Mechanics.Remotes.NotifyClient
    Marker      = nil,   -- ReplicatedStorage.TandaSeruBersama
    MiniGameActive = nil,-- Mechanics.Status.MiniGameActive (server-driven BoolValue)
    LastBite    = 0,
    Reeling     = false,
}

-- Does this instance look like a fishing rod? A Tool carrying the fishing
-- remote set (a CastEvent descendant) is a definite rod. Name is only a hint.
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

-- Prefer the rod actually EQUIPPED in the character; then any rod in the
-- character; then any rod in the backpack. Rods that expose the CastEvent
-- remote are preferred over name-only matches. This makes EVERY rod work
-- (Ares, Bamboo, Element, Diamond, Withering, Ghostfinn, Starter, ...).
local function getRodTool()
    local c  = Char()
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    local sources = { c, bp }
    -- pass 1: a rod that actually has the CastEvent remote (definite rod)
    for _, src in ipairs(sources) do
        if src then
            for _, t in ipairs(src:GetChildren()) do
                if HasCastRemote(t) then return t end
            end
        end
    end
    -- pass 2: any tool that looks like a rod by name
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
        -- search a level deeper just in case
        for _, d in ipairs(tool:GetDescendants()) do
            if d.Name == "Remotes" then rem = d; break end
        end
    end
    return rem
end

-- Discover the active rod + its remotes. If the player switches rods, the
-- remotes are re-bound to the new rod automatically.
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
        -- rod swapped and the new one has no remotes yet: clear stale bindings
        Rod.CastEvent, Rod.MiniGame, Rod.NotifyC = nil, nil, nil
    end
    Rod.Marker = ReplicatedStorage:FindFirstChild("TandaSeruBersama") or Rod.Marker
    -- cache the server-driven reel flag (Status.MiniGameActive) for this rod
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

--───────────────────────────────────────────────────────────────────────────
-- REAL GAME MODULES  (leaked from the in-game FishingClient source)
--
--   ReplicatedStorage.Modules.Fishing.MiniGameHandler
--       runs the reel tug-of-war. IsActive() is the AUTHORITATIVE "a fish is on
--       the line" signal (the game's OWN watchdog uses it), and MobileTap() is
--       the game's own tap call.
--   ReplicatedStorage.Modules.Fishing.PowerBarHandler
--       the cast power gauge; StopFill() returns the exact power the game sends
--       (MIN_POWER = 20, i.e. the "perfect" cast we already send).
--   ReplicatedStorage.Modules.Fishing.AutoFishingModule
--       the game's BUILT-IN auto fisher (ShowGUI / HideGUI / Setup).
--   ReplicatedStorage.Modules.Fishing.TierIkan / FishingImageDatabase
--       fish tier + icon data.
--
-- We require them defensively: on a build where one is missing we simply fall
-- back to the GUI-polling path that already works.
--───────────────────────────────────────────────────────────────────────────
local Game = { MiniGame = nil, PowerBar = nil, AutoFish = nil, Tier = nil, FishDB = nil, ok = false, tried = false }

local function LoadGameModules()
    if Game.tried then return Game end
    Game.tried = true
    local mods = ReplicatedStorage:FindFirstChild("Modules")
    local fish = mods and mods:FindFirstChild("Fishing")
    if not fish then return Game end
    -- Prefer requiring from the GAME's shared environment (getrenv) so we get the
    -- SAME module instance the game's own client Start()ed. In a separate-VM
    -- executor the plain require() can hand back a fresh, never-Start()ed copy
    -- whose MobileTap() does nothing - that is why fish were not landing.
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
            ok, res = pcall(require, inst)        -- fall back to our own VM
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

-- Authoritative reel check straight from the game's own module. Returns
-- true/false, or nil when the module is unavailable (caller then falls back to
-- the GUI check). This is strictly better than polling the bars: the game's own
-- watchdog keys off exactly this value.
local function GameReeling()
    LoadGameModules()
    local mg = Game.MiniGame
    if mg and mg.IsActive then
        local ok, active = pcall(mg.IsActive)
        if ok and active then return true end
    end
    -- The module copy we require() may be a separate VM's instance that is never
    -- Start()ed (so IsActive() stays false even mid-reel). The SERVER-driven
    -- Status.MiniGameActive BoolValue is replicated and reliable in any VM, so
    -- read that as the authoritative signal when the module says "not active".
    DiscoverRod()
    local b = Rod.MiniGameActive
    if b and b.Parent then return b.Value and true or false end
    if mg and mg.IsActive then
        local ok = pcall(mg.IsActive)
        if ok then return false end
    end
    return nil
end

--───────────────────────────────────────────────────────────────────────────
-- THE FISHING GUI (Players.<you>.PlayerGui.Fishing)
--  .Main.Display.Minigame.Left.Bar   -> grows 0..1 (left tap bar)
--  .Main.Display.Minigame.Right.Bar  -> grows 0..1 (right tap bar)
--  .Main.Counter.ClickCount          -> "(002)" click counter
-- The bar reaching size.X.Scale >= ~1 means the reel is complete.
--───────────────────────────────────────────────────────────────────────────
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
    -- Find the Left/Right bars by NAME anywhere under the GUI (path varies by
    -- build). The capture showed: Fishing.Main.Left.Bar / Fishing.Main.Right.Bar,
    -- but the Display/Minigame subtree also exists, so we search widely and
    -- prefer a frame literally named "Bar" whose parent is "Left"/"Right".
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
    -- if Left/Right were not found, use the first two "Bar" frames we saw
    if not leftBar and not rightBar then
        leftBar = fallback[1]
        rightBar = fallback[2] or fallback[1]
    end
    return leftBar, rightBar
end

-- returns the highest bar fill (0..1) across both bars, or nil if no GUI
local function ReelFill()
    local l, r = GetReelBars()
    if not l and not r then return nil end
    local f = 0
    if l then f = math.max(f, l.Size.X.Scale) end
    if r then f = math.max(f, r.Size.X.Scale) end
    return f
end

local function IsReeling()
    -- Prefer the game's OWN module: MiniGameHandler.IsActive() is exactly what
    -- the client watchdog reads to decide a fish is on the line.
    local g = GameReeling()
    if g ~= nil then return g end
    local gui = GetFishingGui()
    if not gui or not gui.Enabled then return false end
    -- The reel minigame only shows while a fish is on the line. Prefer the
    -- strongest signal: the Rows/Point/ClickCount counters that only exist mid-reel.
    local main = gui:FindFirstChild("Main")
    if not main then return false end
    -- if the tug-of-war bars are present and visible, we are reeling
    local l, r = GetReelBars()
    if (l and l.Visible) or (r and r.Visible) then return true end
    -- fallback: any ClickCount label present means the reel UI is up
    for _, d in ipairs(gui:GetDescendants()) do
        if d.Name == "ClickCount" and d.Visible then return true end
    end
    return ReelFill() ~= nil
end

--───────────────────────────────────────────────────────────────────────────
-- AUTO REEL  -  cast -> wait for bite -> claim -> repeat
--───────────────────────────────────────────────────────────────────────────
local Auto = {
    Enabled       = false,     -- OFF by default: the script does NOT fish until you
                              -- turn on "Instant Reel" in the UI
    AutoCast      = true,
    AutoClaim     = true,     -- fire MiniGame(true) automatically
    ClaimDelay    = 0.45,     -- seconds after the BITE before claiming (SUPER-FAST
                              -- default; the adaptive learner measures the real
                              -- floor per rod and tightens toward MinClaim).
    FastRecast    = true,     -- recast the instant a fish is landed (no dead time)
    CastSettle    = 0.0,      -- delay between CastEvent(true) and the throw call.
                              -- 0 = same tick (the server accepts both in one frame).
    CastPower     = 20,       -- the 2nd arg of CastEvent(false, POWER, dir). The
                              -- capture always showed 20 (a full/"perfect" cast).
    PerfectCast   = true,     -- always cast at full power (auto-fill the gauge)
    HideReelUI    = true,     -- hide the game's "Klik Cepat!" tap-race bar while
                              -- auto-reeling (we claim without tapping)
    InstantAlert  = true,     -- draw the "!" bite marker the instant a fish bites
    -- FAST BITE: cast exactly like the GAME does. The game's own cast sequence is
    --   CastEvent:FireServer(true)        -- start
    --   CastEvent:FireServer(false, 0)   -- stop the gauge at 0 (shortest cast)
    -- A SHORT cast = the bait lands close = the server's bite wait is usually
    -- shorter. Our old cast sent (false, 20, direction) = a full-power cast, which
    -- casts FAR and can make the bite slower. Fast Bite uses the game's own
    -- (false, 0) call so the cycle (cast -> bite -> claim -> recast) is tightest.
    FastBite      = true,
    -- TANDASERU SHARED MARKER: firing the shared TandaSeruBersama marker adds a
    -- network call on every bite, which slows the reel. Default OFF so the reel
    -- stays ULTRA fast. When ON it fires ONCE per bite (single fire, off the
    -- critical path) - no keep-alive loop, no burst. Toggle in Settings.
    AutoShowMarker = false,
    Adaptive      = true,     -- learn the fastest claim time that still lands a fish
    LineActive    = false,    -- true from bite -> GotFish (do NOT cast while true)
    LastCast      = 0,
    Busy          = false,
    LoopStop      = false,    -- set by Unload to end the fishing loop for good
    -- Super Fast: push every timing to the server floor (fast probe on the
    -- game's own reel engine + near-instant recast). Set by the Main tab's
    -- "Reel Speed" dropdown (Fast/Ultra). Default = Ultra (fastest).
    SuperFast     = true,
    -- ULTRA SPEED: an even more aggressive tier than Super Fast. It slams every
    -- timing to its absolute floor (instant claim retried EVERY FRAME, no engine
    -- probe wait, no cast throttle, minimal poll). Selected via the "Reel Speed"
    -- dropdown in the Main tab. When true, SuperFast is implied.
    -- Default ON: this is the FASTEST mode.
    Ultra         = true,
    -- Caught notification: show the "Caught: <fish>" popup each time a fish is
    -- landed. Toggle in Settings. Default ON.
    CaughtNotify  = true,
    -- measured fastest landing claim (seconds after the bite). Starts at ClaimDelay
    -- and is tightened toward Auto.MinClaim as successes keep coming in.
    LearnedClaim  = nil,
    MinClaim      = 0.10,     -- hard lower bound for the adaptive probe (fast rods)
    MaxClaim      = 1.45,     -- hard upper bound (game aborts at ~1.5s)
    ClaimStart    = 0.15,     -- adaptive probe STARTS here (super fast) and relaxes
                              -- upward on failures, instead of starting slow.
                              -- Even if this is wrong, ReelOnce RETRIES the claim
                              -- every ~0.12s until GotFish, so no catch is lost.
}

-- The fishing loop runs whenever Instant Reel is on.
local function AutoActive()
    return Auto.Enabled
end

-- Forward declarations: ReelOnce is used before its definition in the file.
-- HookSendCatch is defined far below (Webhook tab) but referenced by the bite
-- watcher above it, so it is forward-declared here.
local StartAuto, StopAuto, ReelOnce, HookSendCatch
-- forward-declared: LearnClaim is defined in the CLAIM TIMING section but used by
-- EndLine (above it) and the bite watcher, so it must be a visible local upvalue.
local LearnClaim

local function FireCast()
    DiscoverRod()
    if not Rod.CastEvent then return false, "no_cast_remote" end

    -- FAST THROW: fire the two cast calls back-to-back in the SAME frame (no
    -- settle wait). The game's own cast is:
    --   CastEvent:FireServer(true)                      -- start the cast
    --   CastEvent:FireServer(false, POWER, <direction>) -- throw (power + unit dir)
    -- The server accepts both in one tick, so this is the fastest possible throw.
    local look = Camera.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.001 then flat = Vector3.new(0, 0, -1) end
    flat = flat.Unit

    -- power: minimum by default (a short cast lands the bait close), or the
    -- game's own full power when Perfect Cast is on.
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

-- Called the instant a fish is COMMITTED (NotifyClient "GotFish") or the reel
-- ends (MiniGame "Stop"). The server has already granted the fish by the time
-- "GotFish" arrives - everything the client does after that (popup, record,
-- Mythical cutscene) is pure cosmetics/idle time. So we recast right here,
-- immediately, instead of waiting for the popup to finish (zero dead time).
--
-- Forward declaration: DestroyAlert is implemented in the ALERT section below
-- but is referenced here by EndLine.
local DestroyAlert
local function EndLine()
    if not Auto.LineActive then return end
    Auto.LineActive = false
    DestroyAlert()
    -- NOTE: the old adaptive-claim-delay learner was tied to the removed
    -- MiniGame:FireServer(true) claim. The reel is client-side now (MobileTap),
    -- so there is no claim delay to learn. The learner hooks are kept as no-ops
    -- so the existing call sites keep working, but they no longer gate anything.
    if AutoActive() and Auto.AutoCast and Auto.FastRecast then
        Auto.LastCast = tick()          -- block the polling loop from also casting
        task.spawn(function()
            if AutoActive() and not Auto.CastInFlight then
                Auto.CastInFlight = true
                FireCast()
                Auto.CastInFlight = false
            end
        end)
    end
end

--───────────────────────────────────────────────────────────────────────────
-- CLAIM  -  REMOVED.
--
-- The game's REAL FishingClient source proves there is NO client->server claim:
-- the reel is client-side and the win happens inside MiniGameHandler when
-- MobileTap() is called. The old FireClaim()/FireClaimVariant() fired
-- MiniGame:FireServer(true), which the game never does - it only confused the
-- server's reel state. They are kept as harmless no-ops so the many call sites
-- and the _G handle keep working, but they fire NOTHING.
--───────────────────────────────────────────────────────────────────────────
_G.X0_MTS_LastClaimedBite = _G.X0_MTS_LastClaimedBite or -1
local function FireClaim(_force)
    return false, "no_claim_remote"     -- intentionally a no-op (see note above)
end

local function FireClaimVariant()
    return false, "no_claim_remote"     -- intentionally a no-op (see note above)
end
_G.X0_MTS_FireClaimVariant = FireClaimVariant

--───────────────────────────────────────────────────────────────────────────
-- CLAIM TIMING  (used by Instant Reel's ReelOnce)
--───────────────────────────────────────────────────────────────────────────

-- How long to wait after a bite before claiming: the learned fastest value if we
-- have one, else the fast adaptive start point. Bounded to [MinClaim, MaxClaim].
local function ClaimWaitForBite()
    local lo = Auto.MinClaim or 0.10
    if Auto.SuperFast then lo = math.min(lo, 0.08) end   -- super fast: allow a tighter floor
    if Auto.Ultra then lo = 0.02 end                     -- ultra: slam the floor to 0.02s
    if Auto.Adaptive and Auto.LearnedClaim then
        return math.clamp(Auto.LearnedClaim, lo, Auto.MaxClaim or 1.45)
    end
    if Auto.Adaptive then
        local startPt = Auto.ClaimStart or 0.15
        if Auto.Ultra then startPt = math.min(startPt, 0.05) end  -- ultra: start tiny
        return math.clamp(startPt, lo, Auto.MaxClaim or 1.45)
    end
    local base = Auto.ClaimDelay or 0.15
    if Auto.SuperFast then base = math.min(base, 0.12) end
    if Auto.Ultra then base = math.min(base, 0.05) end
    return math.clamp(base, lo, Auto.MaxClaim or 1.45)
end
_G.X0_MTS_ClaimWaitForBite = ClaimWaitForBite

-- Learn the fastest claim that still lands a fish: on each SUCCESS we nudge the
-- learned floor down a hair; on a FAILURE we back off harder.
LearnClaim = function(success)
    if not Auto.Adaptive then return end
    local used = Auto.LastClaimWait or Auto.LearnedClaim or Auto.ClaimStart or 0.45
    -- Super Fast: bigger success step so it reaches the floor in fewer catches.
    -- Ultra: even bigger steps + a much lower clamp so it dives to the floor.
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

--───────────────────────────────────────────────────────────────────────────
-- REEL  -  land the fish (no clicking by YOU)
--
-- CORRECTED from the game's REAL FishingClient: the reel is fully CLIENT-side.
-- The server only opens the reel (MiniGame "Start") and closes it ("Stop"); the
-- win is decided inside the module MiniGameHandler, which the game's own client
-- drives by calling MiniGameHandler.MobileTap() on every input frame. The hub
-- therefore does exactly the same thing - it calls MobileTap() every frame while
-- the reel is open. No claim remote is fired (the game has none).
--───────────────────────────────────────────────────────────────────────────
ReelOnce = function(mgData)
    LoadGameModules()
    local mg = Game.MiniGame
    local start = tick()
    Auto.BiteAt = Rod.LastBite or start
    Auto.CaughtAt = nil

    --───────────────────────────────────────────────────────────────────────
    -- THE REAL WIN PATH (confirmed from the game's OWN FishingClient source):
    --
    --   The reel is 100% CLIENT-side. The server only opens the reel with
    --   MiniGame("Start") and closes it with MiniGame("Stop"). The win is
    --   decided entirely by the client module MiniGameHandler: while the reel
    --   is running the client calls MiniGameHandler.MobileTap() on EVERY
    --   input frame, and the module fires the win itself when the bar fills.
    --   There is NO MiniGame:FireServer(true) anywhere in the game.
    --
    --   So the ONLY thing we must do to land the fish is call mg.MobileTap()
    --   every frame while the reel is active - exactly what the game does.
    --───────────────────────────────────────────────────────────────────────
    local biteAt = Rod.LastBite or start
    local deadline = biteAt + 3.0          -- generous: reel window + slack
    local haveTap = (mg and type(mg.MobileTap) == "function")

    -- 1) WAIT for the reel to actually open. The bite event fires a frame or two
    --    BEFORE Status.MiniGameActive turns true (the client flips it locally in
    --    mulaiBarTarikan). Hammering MobileTap here would be a no-op, and - worse -
    --    the old code returned early when the flag was still false, aborting the
    --    whole reel before it began. That is the "fish is not caught" bug.
    local openDeadline = biteAt + 0.6
    local opened = false
    while AutoActive() and tick() < openDeadline do
        if Auto.CaughtAt then return true, "landed" end
        if IsReeling() then opened = true break end
        RunService.Heartbeat:Wait()
    end

    -- If the reel never opened (rod has EnableMiniGame off, or this build hides
    -- it) there is nothing for MobileTap() to drive - bail instead of spinning.
    if not opened and not IsReeling() then return false, "no_reel" end

    -- 2) ENSURE the reel engine is actually live in OUR module copy. On a
    --    separate-VM executor the required MiniGameHandler can be a fresh copy
    --    that was never Setup()/Start()ed, so MobileTap() would silently do
    --    nothing. The game's own client does exactly this in onToolEquipped
    --    (Setup) and mulaiBarTarikan (Start) - we mirror it from the server's
    --    own "Start" payload we captured in OnBite(data).
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

    -- 3) DRIVE the reel: call MobileTap() like the game's own client does, on
    --    every frame, until the server closes the reel (MiniGameActive -> false /
    --    IsActive() -> false) or GotFish lands.
    --
    --    BURST NOTE: the game's client calls MobileTap() once per touch. Doing it
    --    a few times per frame is safe and fills the bar fast, but firing a huge
    --    burst every frame floods the remote and can make the server reject the
    --    reel. The burst is therefore capped: Ultra 6, Fast 4, Normal 2 - fast
    --    enough to fill the bar almost instantly, safe enough to always land.
    if haveTap then
        local burst = Auto.Ultra and 6 or (Auto.SuperFast and 4 or 2)
        while AutoActive() and tick() < deadline do
            if Auto.CaughtAt then return true, "landed" end     -- GotFish arrived
            for _ = 1, burst do pcall(mg.MobileTap) end
            if IsReeling() == false then return Auto.CaughtAt ~= nil, "reel_closed" end
            RunService.RenderStepped:Wait()
        end
        if Auto.CaughtAt then return true, "landed" end
    end

    -- FALLBACK: the module is unavailable / exposes no MobileTap. We cannot drive
    -- the game's reel, so just ride out the window and let the server settle it.
    -- (The bogus MiniGame:FireServer(true) claim was REMOVED - the game has no
    --  such remote call and firing it only confuses the server's reel state.)
    while AutoActive() and tick() < deadline do
        if Auto.CaughtAt then return true, "landed" end
        if IsReeling() == false and tick() > biteAt + 0.5 then return false, "no_engine" end
        RunService.RenderStepped:Wait()
    end
    return Auto.CaughtAt ~= nil, "timeout"
end

_G.X0_MTS_Reel = ReelOnce

--───────────────────────────────────────────────────────────────────────────
-- HIDE THE REEL UI  -  while a fish is on the line the game shows a "Klik Cepat!"
-- tap-race bar. We land the fish without tapping, so that bar is pure visual
-- noise. While auto-reeling we hide the whole "Fishing" ScreenGui (it only holds
-- the reel minigame) so nothing flashes on screen.
--───────────────────────────────────────────────────────────────────────────
local function HideReelUI()
    if not (AutoActive() and Auto.HideReelUI) then return end
    local gui = GetFishingGui()
    if not gui then return end
    -- Hide only the visual container (purely cosmetic) - we do NOT disable the
    -- ScreenGui itself, in case the game's own client reads its Enabled state.
    local main = gui:FindFirstChild("Main")
    if main and main:IsA("GuiObject") then
        pcall(function() main.Visible = false end)
    else
        pcall(function() gui.Enabled = false end)
    end
end

-- Re-hide the reel bar every frame while a fish is on the line (the game can
-- re-show it). This replaces the old bait-landing Heartbeat.
ConnMgr:Add(RunService.Heartbeat:Connect(function(dt)
    if not AutoActive() then return end
    if Auto.HideReelUI and Auto.LineActive then HideReelUI() end
end))

--───────────────────────────────────────────────────────────────────────────
-- INSTANT BITE ALERT  -  the game's own "!" marker is throttled (it can take up
-- to ~2s to appear), so during fast auto-fishing it is often missed entirely.
-- We draw our own "!" above the character the instant the bite arrives, and fire
-- the shared TandaSeruBersama marker so it is immediate for everyone.
--───────────────────────────────────────────────────────────────────────────
local Alert = { Gui = nil, Gen = 0 }

function DestroyAlert()
    if Alert.Gui then pcall(function() Alert.Gui:Destroy() end) end
    Alert.Gui = nil
end

-- Fast direct reference to the shared marker remote (no discovery cost in the
-- hot path). Resolved lazily and refreshed if it ever goes stale.
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
    -- captured signature: TandaSeruBersama:FireServer(color, color, seq, 1.5).
    -- ULTRA: a slightly shorter duration so the marker pops and clears quickly,
    -- matching the faster bite cadence.
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

-- fire the shared marker as fast as possible: ONE fire, fired on its own thread
-- so the bite handler never waits on it. No burst, no sequence variants in the
-- hot path (a single ColorSequence fire is the confirmed-working signature).
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
    -- NOTE: the shared TandaSeruBersama marker is already fired as the FIRST thing
    -- in OnBite() (before the debounce), so we do NOT re-fire it here - this
    -- function only draws our own fast local "!" above the character.
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

--───────────────────────────────────────────────────────────────────────────
-- AUTO SHOW TANDASERU  -  DISABLED keep-alive
--
-- The old version ran a Heartbeat loop that re-fired the shared marker every
-- 0.35s while a fish was on the line. That constant extra network traffic
-- competed with the reel claim and slowed fishing down, so it is REMOVED.
-- The marker is now fired exactly ONCE per bite (FireSharedMarkerFast), off the
-- critical path. AutoMarker is kept as a no-op so the Settings toggle still
-- works and Unload still has something to call.
--───────────────────────────────────────────────────────────────────────────
local AutoMarker = { Running = false }
_G.X0_MTS_AutoMarker = AutoMarker

function AutoMarker.Stop() AutoMarker.Running = false end
function AutoMarker.Start() AutoMarker.Running = true end
AutoMarker.Set = function(v) AutoMarker.Running = (v == true) end

--───────────────────────────────────────────────────────────────────────────
-- INSTANT BAIT LANDING  -  patch the game's OWN throw module.
--
-- From the real client script (StarterPlayerScripts.EfekLemparClient):
--   local EfekLempar = require(ReplicatedStorage.Modules.Fishing.EfekLempar)
--   EfekMancingEvent.OnClientEvent:("lempar", player, tool) ->
--         EfekLempar.Lempar(tool, player.Character, player)
--   and later ("dive", player, pos) -> EfekLempar.Dive(player, pos, ...)
--
-- Roblox returns the SAME cached module table to every `require`, so we can
-- require it ourselves and WRAP its Lempar/Dive. When the game fires the throw,
-- our wrapper runs FIRST: it finds the throw VFX the module just cloned, snaps it
-- straight to the water landing point (no flight), and lets the game continue.
-- Landing point (from the client):  tool.Mechanics.Configuration.Status.
-- BaitPosition if set, else HumanoidRootPart.CFrame * CFrame.new(0,0,-12).
-- This is the definitive, name-free, timing-free "bait lands instantly" fix.
--───────────────────────────────────────────────────────────────────────────
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

-- snap a freshly-cloned throw VFX to the landing point and freeze it there
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
            -- snapshot workspace children BEFORE the throw so we can spot exactly
            -- the VFX the module adds (no guessing, no touching other players).
            local before = {}
            if AutoActive() and BaitFix.On then
                for _, c in ipairs(workspace:GetChildren()) do before[c] = true end
            end
            local r = { orig(tool, character, player) }
            if AutoActive() and BaitFix.On then
                local pos = BaitLandPoint(tool)
                if pos then
                    -- slam the throw VFX to the water and KEEP it there for a few
                    -- frames (the module tweens it after Lempar returns).
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

--───────────────────────────────────────────────────────────────────────────
-- HIDE REEL UI while auto-reeling (no bait-landing flow here any more).
-- While a fish is on the line the game shows a "Klik Cepat!" tap-race bar; we
-- land the fish without tapping, so the whole Fishing ScreenGui is hidden so
-- nothing flashes on screen.
--───────────────────────────────────────────────────────────────────────────

StartAuto = function()
    if Auto.Busy then return end
    Auto.Busy = true
    Auto.LoopStop = false
    task.spawn(function()
        local lastNoRod = 0
        -- The loop runs until the hub is unloaded (Auto.LoopStop). When Instant
        -- Reel is off it simply IDLES instead of exiting - so flipping the toggle
        -- back on is instant and there is no start/stop race.
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
                    -- ULTRA: no cast throttle at all - recast the instant the line
                    -- is free. CastInFlight + LineActive already prevent doubles.
                    local castThrottle = Auto.Ultra and 0 or (Auto.SuperFast and 0.05 or 0.35)
                    if Auto.LineActive or IsReeling() then
                        -- a fish is on the line: the reel hook claims it after the
                        -- bite delay, and EndLine() recasts the instant it ends.
                        -- Safety: if no Stop/GotFish ever arrives, clear the flag.
                        if Auto.LineActive and (tick() - Rod.LastBite) > 3 then
                            Auto.LineActive = false
                        end
                        task.wait(poll)
                    elseif Auto.AutoCast and (tick() - Auto.LastCast > castThrottle) then
                        -- no line out and not reeling -> cast (full 2-call cast).
                        -- Normally EndLine already recast on GotFish, so this only
                        -- fires as a safety net; the throttle keeps it from doubling.
                        if not Auto.CastInFlight then
                            Auto.CastInFlight = true
                            FireCast()
                            Auto.CastInFlight = false
                        end
                        task.wait(poll)
                    else
                        -- waiting for a bite
                        task.wait(poll)
                    end
                end
            end
        end
        Auto.Busy = false
    end)
end

StopAuto = function()
    -- Restore run-time state and the game's own reel UI. Does NOT kill the loop
    -- (it idles) and does NOT touch Auto.Enabled - the toggle owns that.
    -- MasterCleanup sets Auto.LoopStop to end the loop for good.
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

--───────────────────────────────────────────────────────────────────────────
-- BITE LISTENER (server -> client) so we know when the "!" appears
--───────────────────────────────────────────────────────────────────────────
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
                Auto.CaughtAt = tick()                    -- success signal for the reel loop
                if Auto.CaughtNotify then
                    Notify("Fishing", "Caught: " .. tostring(data and (data.originalName or data.baseName) or "fish"), 3)
                end
                -- post to Discord (respects the Webhook tab's enable + rarity filter)
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

--───────────────────────────────────────────────────────────────────────────
-- INSTANT REEL HOOK  -  triggered directly by the server's bite event
--
-- The capture PROVED the server tells us exactly when a fish is on the line:
--   MiniGame("Start", {name=..., difficulty=..., rarity=..., ...})
--   NotifyClient("Bite", {duration=1.5, ...})
-- That is a 100% reliable signal - far better than polling the GUI. So we hook
-- the event itself: the moment "Start"/"Bite" arrives, draw the "!" and land the
-- fish (ReelOnce). FireClaim() carries a global one-per-bite lock.
--───────────────────────────────────────────────────────────────────────────
local ReelConns = {}
local function ClearReelConns()
    for _, c in ipairs(ReelConns) do pcall(function() c:Disconnect() end) end
    ReelConns = {}
end

local function OnBite(data)
    -- SHARED MARKER (server, costs a network call): only when Auto Show is ON.
    -- Kept OFF by default so the reel stays ultra fast. Single fire, own thread.
    if Auto.AutoShowMarker then FireSharedMarkerFast() end
    -- Debounce: "Start" and "Bite" both signal the same bite. If both arrive we
    -- must only reel ONCE - driving the reel twice would double-hammer MobileTap
    -- and can make the module fire the win twice, which the server rejects.
    -- ULTRA: tighten the debounce so back-to-back bites aren't dropped, but keep
    -- a safe floor so a split Start+Bite for the SAME bite can't double-drive.
    local now = tick()
    local debounce = Auto.Ultra and 0.25 or 0.5
    if now - (Rod.LastOnBite or 0) < debounce then return end
    Rod.LastOnBite = now
    Rod.LastBite = now
    if AutoActive() then Auto.LineActive = true end
    ShowBiteAlert()                        -- instant "!" marker (not throttled)
    if AutoActive() and Auto.HideReelUI then HideReelUI() end

    if not (AutoActive() and Auto.AutoClaim) then return end
    -- land it: drive the game's own reel with MobileTap(). Spawned so this event
    -- handler returns immediately (a blocking handler would stall the later
    -- "Stop" event, which is what recasts us).
    task.spawn(function() ReelOnce(data) end)
end

local function InstallReelHook()
    DiscoverRod()
    ClearReelConns()
    -- primary trigger: the server's own "Start" event (100% reliable)
    if Rod.MiniGame then
        table.insert(ReelConns, Rod.MiniGame.OnClientEvent:Connect(function(state, data)
            if state == "Start" then
                OnBite(data)
            elseif state == "Stop" then
                EndLine()                       -- recast immediately (no dead time)
            end
        end))
    end
    -- fallback trigger: the "Bite" notify (in case "Start" is absent on a build).
    -- OnBite() self-debounces, so calling it from both events is safe.
    if Rod.NotifyC then
        table.insert(ReelConns, Rod.NotifyC.OnClientEvent:Connect(function(kind, data)
            if kind == "Bite" then
                OnBite(data)
            elseif kind == "GotFish" then
                EndLine()                       -- recast immediately (no dead time)
            elseif kind == "CastFailed" then
                -- server said we are already fishing: back off the cast timer
                Auto.LastCast = tick()
            end
        end))
    end
end

--───────────────────────────────────────────────────────────────────────────
-- FLOATING LOGO  -  draggable logo that toggles the hub when clicked
--───────────────────────────────────────────────────────────────────────────
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
    sg.Name = "Choco_SOREYAFREE_Logo"
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

--───────────────────────────────────────────────────────────────────────────
-- BUILD UI
--───────────────────────────────────────────────────────────────────────────
local Window = WindUI:CreateWindow({
    Title   = HUB.Name,
    Author  = HUB.Game .. " | V " .. HUB.Version,
    Icon    = HUB.LogoId,
    Folder  = "ChocoHubFree",
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

-- MAIN TAB
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
    -- let other features (e.g. Automation) flip this toggle visually
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

--───────────────────────────────────────────────────────────────────────────
-- TELEPORT TAB  -  three locations: Core Locations, Spot Mancing, NPC Sell.
--
-- The map has no official teleport remote, so we move the character directly:
-- HumanoidRootPart CFrame + Character:PivotTo (kept in sync so the character
-- does not rubber-band).
--───────────────────────────────────────────────────────────────────────────
local Tp = {
    Presets = {
        CoreLocations = Vector3.new(-9035.890625, 1250.61279296875, -6511.6669921875),
        SpotMancing   = Vector3.new(-7833.33203125, 1236.7515869140625, -6327.37353515625),
        -- Rusdy the sell NPC (his Head WorldPivot from the in-game explorer)
        NpcSell       = Vector3.new(-6667.651, 1316.178, -9971.995),
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
    S:Button({ Title = "Teleport to NPC Sell", Icon = "hand-coins",
        Callback = function() TpTo(Tp.Presets.NpcSell, "NPC Sell") end })
end

--───────────────────────────────────────────────────────────────────────────
-- AUTO SUMMIT TAB  -  Basecamp -> Summit, teleport per checkpoint, looped.
--
-- The 21 Mount Soreya checkpoints (CP1 .. CP20 + CP21 Summit) are baked in.
-- "Start Auto Summit" teleports you through all 21 in order, pausing 2 seconds
-- at each. When it reaches CP21 it LOOPS: back to CP1 and through again, over
-- and over, until you press Stop.
--───────────────────────────────────────────────────────────────────────────
local Summit = {
    -- CP1 .. CP20 checkpoints, CP21 = Summit (basecamp -> summit in order)
    Points = {
        Vector3.new(468.4,   444.9,  -8948.0),    -- CP1
        Vector3.new(456.3,   489.0,  -9572.7),    -- CP2
        Vector3.new(391.9,   629.0,  -10117.5),   -- CP3
        Vector3.new(489.8,   637.0,  -10682.5),   -- CP4
        Vector3.new(1088.9,  725.0,  -11158.7),   -- CP5
        Vector3.new(971.5,   732.9,  -11820.6),   -- CP6
        Vector3.new(390.7,   885.0,  -11837.7),   -- CP7
        Vector3.new(-326.3,  849.0,  -11737.4),   -- CP8
        Vector3.new(-869.8,  853.0,  -11735.8),   -- CP9
        Vector3.new(-1281.2, 857.0,  -12091.2),   -- CP10
        Vector3.new(-1311.6, 889.0,  -12836.8),   -- CP11
        Vector3.new(-2316.0, 913.0,  -12667.7),   -- CP12
        Vector3.new(-2310.6, 917.0,  -11849.0),   -- CP13
        Vector3.new(-2448.4, 961.0,  -11058.7),   -- CP14
        Vector3.new(-3478.0, 981.0,  -11026.2),   -- CP15
        Vector3.new(-4228.0, 1001.0, -11012.6),   -- CP16
        Vector3.new(-4650.1, 1081.0, -11669.6),   -- CP17
        Vector3.new(-5551.0, 1101.0, -11646.9),   -- CP18
        Vector3.new(-6762.8, 1097.0, -11507.1),   -- CP19
        Vector3.new(-6768.3, 1102.6, -10790.2),   -- CP20
        Vector3.new(-6767.209, 1340.403, -10082.368),  -- CP21 (Summit = SummitPart)
    },
    MaxCP    = 21,
    CP       = 1,       -- current checkpoint (resume point; saved on Stop)
    Running  = false,
    Loop     = true,    -- restart from CP1 after reaching the summit
    ShowHUD  = true,
    Notify   = true,    -- show Auto Summit popups (toggle in Settings)
    Delay    = 2.0,     -- seconds to wait at each checkpoint (walk pace)
    -- diagnostic: when Debug.Print is on, every TpToCheckpoint we fire is
    -- printed to the output so you can see the exact index sent per checkpoint.
    Debug    = { Print = false },
    _SummitPart = nil,   -- cached Workspace...Summit.SummitPart (touch trigger)
    _BackBC     = nil,   -- cached Workspace...BackBC.BackBC (back-to-basecamp pad)
}

--───────────────────────────────────────────────────────────────────────────
-- TELEPORT PER CHECKPOINT (Teleport tab)
--
-- A dropdown listing all 21 Mount Soreya checkpoints (CP1 .. CP20 + CP21 Summit)
-- plus a single "Teleport" button, so you pick one and go. Uses the same
-- direct-CFrame TpTo as the other spots.
--───────────────────────────────────────────────────────────────────────────
do
    local T = Tabs.Teleport
    local S = T:Section({ Title = "Teleport Per Checkpoint" })

    -- label <-> index maps (the dropdown stores strings, we need the index back)
    local cpLabels = {}
    for i = 1, (Summit.MaxCP or #Summit.Points) do
        cpLabels[i] = (i == 21) and "CP21 (Summit)" or ("CP" .. tostring(i))
    end
    local cpIndex = {}          -- label -> index
    for i = 1, #cpLabels do cpIndex[cpLabels[i]] = i end

    local picked = cpLabels[1]  -- default to CP1
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

--───────────────────────────────────────────────────────────────────────────
-- TELEPORT TO PLAYER (Teleport tab)
--
-- A dropdown listing every OTHER player in the server plus a single "Teleport"
-- button, so you pick one and go. Movement is the same direct-CFrame TpTo.
--
-- IT ALWAYS TELEPORTS - there is NO "move closer first" dead-end.
--
-- How it stays reliable:
--   1. resolve the Player by NAME fresh at click time (never trust a stale map),
--   2. find their model + HumanoidRootPart via target.Character, then a workspace
--      model matched by GetPlayerFromCharacter / name (survives replication lag),
--   3. if the model is not in OUR workspace yet (a far, un-replicated player),
--      ask the engine to stream that area in (workspace:RequestStreamAroundAsync
--      when the executor exposes it) and poll - the model pops in a moment later,
--   4. land via a downward raycast so we do not clip into them, then re-snap once
--      more shortly after (covers the target moving / the model arriving late).
--
-- We only ever stop early if the player actually LEFT the server.
--───────────────────────────────────────────────────────────────────────────
-- Resolve a player's CURRENT character MODEL (and its HRP). Returns model, hrp.
-- We look in three places, in this order:
--   1) target.Character  - the normal path (their model under workspace).
--   2) workspace:FindFirstChild(target.Name) - the replicated model by name.
--   3) a workspace scan matched by GetPlayerFromCharacter (authoritative).
-- The model may exist while HRP has not replicated yet, so we return both.
-- Fully pcall-guarded: a missing instance / bad API NEVER throws here.
local function FindTargetModel(target)
    if not target or not target.Parent then return nil, nil end
    local function hrpOf(model)
        if not model then return nil end
        return model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("UpperTorso")
            or model:FindFirstChild("Torso")
            or model.PrimaryPart
    end
    -- 1) the normal path
    local char = target.Character
    if char then return char, hrpOf(char) end
    -- 2) by name in workspace
    local wp = workspace:FindFirstChild(target.Name)
    if wp then
        local okp, owner = pcall(function() return Players:GetPlayerFromCharacter(wp) end)
        if (okp and owner == target) or wp.Name == target.Name then
            return wp, hrpOf(wp)
        end
    end
    -- 3) scan
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

-- Position of a target as a Vector3, even when there is no HRP part (falls back
-- to the model pivot). Returns nil if the model itself isn't here yet.
local function TargetPos(target)
    local model, hrp = FindTargetModel(target)
    if hrp then return hrp.Position, model, hrp end
    if model then
        local ok, pos = pcall(function() return model:GetPivot().Position end)
        if ok and typeof(pos) == "Vector3" then return pos, model, nil end
    end
    return nil, model, nil
end

-- CFrame of a target (for a VD-style land that keeps their facing). Falls back
-- to "look from position" if only a position is known.
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

-- ask the engine to load the world around a position (pulls in a far player's
-- model when StreamingEnabled is on). Silent no-op if the executor lacks it.
local function RequestArea(pos)
    pcall(function()
        if pos and workspace.RequestStreamAroundAsync then
            workspace:RequestStreamAroundAsync(pos)
        end
    end)
end

-- TELEPORT TO PLAYER  -  works at ANY range, like the VD hub: we just WRITE the
-- target's HumanoidRootPart CFrame straight onto ours. There is NO "you must be
-- close" check and NO waiting-for-proximity gate. The only real-world catch is
-- that in a streaming game a FAR player's character may not be replicated to us
-- yet - so we do two things to still land on them:
--   1. fire the direct CFrame write the instant we have ANY position for them
--      (their model, or a cached last-known spot), and
--   2. keep re-snapping for ~3s, requesting the stream around the destination so
--      their model pops in and we lock onto the exact spot.
-- The move itself is never blocked by a raycast - that is optional polish.
local function TpToPlayer(target, label)
    local name = (target and target.Name) or tostring(label or "")
    if name == "" then
        Notify("Teleport", "Pick a player first", 3)
        return
    end

    -- re-resolve the Player object by name each tick (they may leave/rejoin).
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

    -- last-known position, so we can still jump toward them before their model
    -- replicates (streamed games keep far characters out of our workspace).
    local lastPos = nil

    -- one hard snap: direct CFrame write (+ PivotTo), no distance requirement.
    -- Like VD we land right ON the target with a small sideways offset so we
    -- don't stand inside them; accepts a CFrame (keeps their facing) or Vector3.
    local function snapOnce(cf, silent)
        if typeof(cf) == "Vector3" then cf = CFrame.new(cf) end
        if typeof(cf) ~= "CFrame" then return false end
        local char = Char()
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
        local dest = cf * CFrame.new(2, 0, 2)     -- VD offset (2 studs aside)
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

    -- 1) fire IMMEDIATELY with whatever we have (this is the VD behaviour)
    local cf0 = TargetCFrame(who)
    if cf0 then
        lastPos = cf0.Position
        snapOnce(cf0, false)
    end

    -- 2) keep locking on for a few seconds. Each pass: re-resolve the target,
    --    request the stream around their spot (and around our own char) so their
    --    model replicates if it hasn't, then snap straight onto it.
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
                -- their model still isn't replicated here; keep pulling the area
                -- and re-snapping to the last spot we knew them at.
                RequestArea(lastPos)
                snapOnce(CFrame.new(lastPos), true)
            end
        end
        -- final confirmation snap so we end EXACTLY on them if the model arrived
        local w = resolve()
        local cf = TargetCFrame(w)
        if cf then
            snapOnce(cf, true)
        elseif lastPos then
            snapOnce(CFrame.new(lastPos), true)
        end
    end)

    -- if we had nothing at all yet, tell the user we're still pulling them in
    if not lastPos then
        Notify("Teleport", "Pulling in " .. name .. " (their model isn't loaded yet)", 3)
        RequestArea(Char() and Char():GetPivot().Position or Vector3.zero)
    end
end

do
    local T = Tabs.Teleport
    local S = T:Section({ Title = "Teleport To Player" })

    local picked = nil          -- currently chosen player name

    -- build the current list of other players (sorted by name)
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
            -- Resolve the picked name into a live Player. If "picked" is stale or
            -- nil, fall back to the dropdown's current selection, then to the first
            -- other player - so the button ALWAYS teleports to someone who is here.
            local function findByName(nm)
                if not nm then return nil end
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= Players.LocalPlayer and p.Name == nm then return p end
                end
                return nil
            end

            local who = findByName(picked)
            if not who then
                -- read the dropdown's live value (WindUI stores it on .Value)
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
            -- WindUI's Refresh(values) does NOT re-select, so pass the value too
            -- by re-pointing the dropdown at the current list; the Value is kept
            -- in sync via the callback when the user clicks.
            pcall(function() dd:Refresh((#names > 0) and names or { "No other players online" }) end)
            Notify("Teleport", #names > 0 and ("Found " .. #names .. " player(s)") or "No other players online", 2)
        end })

    -- keep the list live: auto-refresh when someone joins/leaves so "picked"
    -- never points at a player who is no longer in the server. Connections are
    -- tracked by ConnMgr and removed on Unload.
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

-- Fire the game's OWN checkpoint teleport remote (this is what actually
-- registers a checkpoint on the server - moving the character by CFrame alone
-- does NOT trigger it, which is why checkpoints never fired before):
--     ReplicatedStorage.Remote.Checkpoint.TpToCheckpoint:FireServer(<index>)
--
-- HOWEVER the capture proved that when you legitimately reach the summit the
-- game fires NOTHING client->server - so the summit is a SERVER-SIDE zone/touch
-- trigger: the server watches your position and counts the checkpoint when you
-- actually STAND in its region (a TouchPart). Teleporting *through* a spot too
-- fast can miss the touch, so we now LAND and DWELL in each checkpoint for the
-- full delay (and a bit longer at the summit) so the server registers it.
-- We still fire TpToCheckpoint first (it moves you onto the exact pad) as a
-- best-effort, then snap + dwell so the touch definitely fires.
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

-- Locate the summit TouchPart (Workspace...Summit.SummitPart). The server counts
-- the summit when the character TOUCHES this part, so we must land ON it, not
-- float above it. Searched by name once and cached.
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
        -- fast paths first, then a full scan
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

-- Locate the BackBC touch pad (Workspace...BackBC.BackBC). Touching it sends the
-- player back to Basecamp, so we touch it after the summit to start the next lap.
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

-- Touch a part reliably: snap the character onto its centre, then do a short
-- physics walk into it so the engine fires a genuine Touched, then dwell.
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

-- teleport to a checkpoint and DWELL there: fire the remote (best effort), snap
-- onto the exact spot, then keep re-asserting the CFrame for `dwell` seconds so
-- the server-side touch/zone trigger actually fires.
-- When `onSummit` is true we land directly ON SummitPart (CFrame from the part
-- itself) and keep touching it, because a Touched event is what counts.
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

    -- build the snap CFrame
    local target
    local summitPart
    if onSummit then
        summitPart = FindSummitPart()
        if summitPart then
            -- SummitPart is a tall slab (Size.Y ~57), so its Position is the
            -- CENTER. Put the HumanoidRootPart right at the part's X/Z and at a
            -- height inside the slab so the body actually overlaps it and Touched
            -- fires - do NOT sit on top of it.
            local p = summitPart.Position
            target = CFrame.new(Vector3.new(p.X, p.Y, p.Z))
        end
    end
    if not target and typeof(pos) == "Vector3" then
        target = CFrame.new(pos + Vector3.new(0, 3, 0))
    end
    if not target then return usedRemote end

    snapTo(target)

    -- For the summit, also do a short PHYSICS walk into the part so the engine
    -- generates a genuine Touched event (a pure CFrame snap often does not).
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
                pcall(function() hum:MoveTo(dest) end)   -- keep steering in
            end
        end
    end

    -- hold position: re-assert over the dwell window so the Touched fires.
    local t, step = 0, 0.1
    while Summit.Running and t < (dwell or 0) do
        task.wait(step)
        t = t + step
        snapTo(target)
    end
    return usedRemote
end

-- current-checkpoint status label (set when the UI builds; forward-declared so
-- Summit.Stop can refresh it).
local RefreshSummitLbl = function() end

-- Helper: which checkpoint is the avatar standing at right now?
-- Compares the character's position to every checkpoint and returns the index of
-- the closest one (within a generous radius) so the hub knows where you are.
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

-- walk the route once, STARTING at `fromCP` (defaults to the saved progress).
-- Each checkpoint is fired then DWELLED in for the full delay so the server-side
-- zone trigger registers it; the summit dwells a bit longer so the reach fires.
local function SummitPass(fromCP)
    local start = math.clamp(fromCP or Summit.CP or 1, 1, #Summit.Points)
    for i = start, #Summit.Points do
        if not Summit.Running then return false end
        Summit.CP = i                        -- remember where we are
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

    -- Resume logic: if the avatar is standing near a checkpoint, continue from it;
    -- otherwise continue from the last checkpoint we saved when we stopped.
    local near = SummitNearestCP()
    local startCP = near or Summit.CP or 1
    if startCP > #Summit.Points then startCP = 1 end   -- already at summit -> restart

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
                Summit.CP = 1   -- full lap done; next lap starts at CP1
                Summit.Msg("Auto Summit", "Summit reached - touching BackBC to go back", 3)
                -- Touch the BackBC pad: this is what sends the player back to
                -- Basecamp so the next lap can start from checkpoint 1.
                local bc = FindBackBC()
                if bc then
                    TouchPart(bc, Summit.Delay or 2.0)
                else
                    -- fallback: jump straight back to the Basecamp coordinate
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
    -- keep Summit.CP as the resume point; also snap-save where the avatar is,
    -- so the next Start continues from the checkpoint you're actually on.
    local near = SummitNearestCP()
    if near then Summit.CP = near end
    RefreshSummitLbl()
    if Summit.SyncToggle then Summit.SyncToggle(false) end
    Summit.Msg("Auto Summit", "Stopped - will resume from CP" .. (Summit.CP or 1), 3)
end
_G.X0_MTS_Summit = Summit

-- Auto Summit notification gate: everything Summit-related routes through here so
-- the Settings "Summit Notification" toggle can silence the popups entirely.
-- Defined on the Summit table so the Summit functions above/below can call it.
function Summit.Msg(title, content, dur)
    if Summit.Notify == false then return end
    Notify(title, content, dur)
end
_G.X0_MTS_SummitMsg = Summit.Msg
-- mirror the flag so the global Notify() can also suppress "Auto Summit" popups
-- regardless of the code path that raised them.
_G.X0_MTS_SummitNotifyOff = (Summit.Notify == false)

do
    local T = Tabs.Summit
    local S = T:Section({ Title = "Auto Summit (LOCKED)" })

    -- FREE SCRIPT: WindUI native lock (Locked=true). All controls are fully INERT.
    S:Toggle({ Title = "Auto Summit", Value = false, Locked = true,
        LockedTitle = "Locked in the Free script" })

    S:Toggle({ Title = "Loop", Value = true, Locked = true,
        LockedTitle = "Locked in the Free script" })

    S:Button({ Title = "Current: CP1 / " .. Summit.MaxCP, Icon = "lock", Locked = true,
        LockedTitle = "Locked in the Free script" })

    S:Slider({
        Title = "Delay Per Checkpoint x0.1s",
        Value = { Min = 0, Max = 50, Default = 20 }, Step = 1,
        Locked = true, LockedTitle = "Locked in the Free script",
    })
end

--───────────────────────────────────────────────────────────────────────────
-- AUTO ACCEPT GALATAMA  (Automation tab)
--
-- WHAT IT DOES (one toggle, OFF by default):
--   The game's "Glatama" event shows a popup with a Join / No choice. This
--   feature AUTO-JOINS: the moment the invite appears it fires the join remote
--   for you, so you never have to tap it yourself.
--
-- HOW IT WORKS (robust - the exact remote kind isn't assumed):
--   The remotes live under ReplicatedStorage (confirmed in Explorer):
--       ReplicatedStorage.Gabung            (folder)
--           Umumkan                          (announce)
--       ReplicatedStorage.Glatama           (folder)
--           Ikut                             <- JOIN  (this is what we fire)
--           Hasil  |  Keadaan  |  Papan      (results / status / board)
--
--   Every tick we:
--     1. find the "Ikut" remote under ReplicatedStorage.Glatama (by name; we
--        also walk the whole Glatama folder in case it moves) and fire it:
--          - RemoteEvent      -> :FireServer()
--          - RemoteFunction   -> :InvokeServer(true)   (server asks, we say yes)
--          - BindableFunction -> :Invoke(true)
--     2. scan PlayerGui / CoreGui for the NEW galatama popup and click its
--        accept button (matched by common names: Ikut / Join / Gabung / Ya /
--        Yes / Terima / Accept / OK). This covers the case where joining is done
--        by pressing the on-screen button rather than a remote.
--   Both paths are pcall-guarded and rate-limited, so nothing ever errors.
--───────────────────────────────────────────────────────────────────────────
local Galatama = {
    Enabled   = false,     -- master toggle (OFF by default)
    Running   = false,
    Conn      = nil,       -- our scan loop connection
    LastFire  = 0,         -- throttle for remote fires
    LastClick = 0,         -- throttle for button clicks
    Fired     = 0,         -- count of auto-joins this session
    RemotePath = "ReplicatedStorage.Glatama.Ikut",
}
_G.X0_MTS_Galatama = Galatama

-- names that count as the JOIN/ACCEPT button on the popup
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

-- find the join remote under ReplicatedStorage.Glatama (name "Ikut"), walking
-- the folder in case it is nested/moved. Returns the instance or nil.
local function FindGalatamaRemote()
    local found = nil
    pcall(function()
        local glat = ReplicatedStorage:FindFirstChild("Glatama")
        if not glat then return end
        -- direct child named Ikut first
        local direct = glat:FindFirstChild("Ikut")
        if direct then found = direct; return end
        -- otherwise any RemoteEvent/RemoteFunction inside
        for _, c in ipairs(glat:GetDescendants()) do
            if c:IsA("RemoteEvent") or c:IsA("RemoteFunction")
                or c:IsA("BindableFunction") or c:IsA("BindableEvent") then
                if c.Name == "Ikut" or _nameIsAccept(c.Name) then found = c; return end
            end
        end
    end)
    return found
end

-- fire the join remote in whatever form it takes
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

-- scan a GUI container and click the first small "accept" button we find inside
-- a popup. Returns true if we clicked something.
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
                -- is this a button-ish element whose name says accept?
                if (node:IsA("TextButton") or node:IsA("ImageButton"))
                    and _nameIsAccept(node.Name) then
                    -- only click if it is actually visible
                    if node.Visible and node.AbsoluteSize.X > 0 then
                        pcall(function() node:Activate() end)
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

-- find the galatama popup (a ScreenGui that contains an accept button) anywhere
-- in PlayerGui / CoreGui, and click its accept button.
local function TryClickGalatamaPopup()
    local now = os.clock()
    if now - (Galatama.LastClick or 0) < 0.5 then return false end
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

-- start/stop the scan loop
function Galatama.Start()
    if Galatama.Running then return end
    Galatama.Running = true
    Galatama.Enabled = true
    Galatama.Conn = RunService.Heartbeat:Connect(function()
        if not Galatama.Enabled then return end
        -- 1) proactively fire the join remote (harmless if there is no invite)
        FireGalatamaJoin()
        -- 2) click the popup's accept button if one is showing
        TryClickGalatamaPopup()
    end)
    Notify("Galatama", "Auto Accept ON (auto-joins the Glatama event)", 3)
end

function Galatama.Stop()
    Galatama.Enabled = false
    Galatama.Running = false
    if Galatama.Conn then pcall(function() Galatama.Conn:Disconnect() end); Galatama.Conn = nil end
end

--───────────────────────────────────────────────────────────────────────────
-- AUTOMATION TAB  -  Auto Core Catch
--
-- WHAT IT DOES (one toggle):
--   it follows the REAL local clock. At every top-of-hour mark (1:00, 2:00,
--   3:00 ... am/pm - any multiple of the "Trigger Every" minutes), it teleports
--   you to the CORE SPOT, turns Instant Reel ON and fishes there for 10 minutes
--   (cores like "Withering Core" can drop from the fish you catch - the drop
--   itself is rolled SERVER-side, so the hub only automates the grind, it cannot
--   force a core), then teleports back to SPOT MANCING and waits for the NEXT
--   clock mark. Repeats until you switch it OFF.
--
--   TIMELINE (default 60 min trigger / 10 min fish):
--     [01:00] -> Core Spot, fish 10 min
--     [01:10] -> back to Spot Mancing, idle
--     [02:00] -> Core Spot again ... (loop, on the real clock)
--
--   REQUIREMENTS: cores only drop while the required rod is equipped (the game's
--   CoreConfig.RodSyarat, normally "Withering Rod"). The hub WARNS you if that
--   rod is not in your inventory, but it still runs the cycle.
--───────────────────────────────────────────────────────────────────────────
local Automation = {
    Enabled      = false,     -- master toggle (OFF by default)
    EveryMin     = 60,        -- fire at EVERY top-of-hour boundary (:00) by default
    FishMin      = 10,        -- how long to fish at the Core Spot (10 minutes)
    State        = "idle",    -- idle | core | back | waiting
    CorePos      = Tp.Presets.CoreLocations,  -- Core Spot (same coords as Teleport tab)
    MancingPos   = Tp.Presets.SpotMancing,    -- Spot Mancing (same coords as Teleport tab)
    RodSyarat    = "Withering Rod",  -- core rod requirement (from game CoreConfig)
    Running      = false,
    Thread       = nil,
    LblRefresh   = function() end,
}
_G.X0_MTS_Automation = Automation

--───────────────────────────────────────────────────────────────────────────
-- REAL-TIME CLOCK  -  all scheduling keys off the ACTUAL local wall clock, not
-- a rolling timer. So with EveryMin = 60 the run happens at 1:00, 2:00, 3:00 ...
-- exactly on the hour (am/pm alike), like a real clock - not 60 min after you
-- pressed the toggle.
--
--   nowSec()  = whole seconds since local midnight (0..86399)
--   nextSlot(now, everyMin) = the next multiple of everyMin minutes AFTER now
--───────────────────────────────────────────────────────────────────────────
local function nowSec()
    local ok, t = pcall(os.date, "*t")
    if ok and type(t) == "table" then
        return (t.hour or 0) * 3600 + (t.min or 0) * 60 + (t.sec or 0)
    end
    -- fallback: derive from os.time() if os.date is unavailable
    local ok2, epoch = pcall(os.time)
    if ok2 and type(epoch) == "number" then
        return math.floor(epoch) % 86400
    end
    return nil
end

-- clock string like "01:00" for the status readout
local function clockStr(secOfDay)
    if not secOfDay then return "--:--" end
    local h = math.floor(secOfDay / 3600) % 24
    local m = math.floor((secOfDay % 3600) / 60)
    return string.format("%02d:%02d", h, m)
end

-- seconds from `now` until the next slot (a multiple of everyMin minutes).
-- always > 0 (if exactly on the boundary it schedules the NEXT one).
local function secsUntilNextSlot(now, everyMin)
    everyMin = math.max(1, tonumber(everyMin) or 60)
    local step = everyMin * 60
    local nextAt = (math.floor(now / step) + 1) * step
    return (nextAt - now) % 86400, nextAt % 86400
end

-- read the game's own CoreConfig if we can, so the rod requirement + item name
-- stay in sync with the build (falls back to the baked defaults above).
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

-- is the required core rod present in the backpack or equipped?
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

-- make sure the auto-reel loop is actually fishing (turn Instant Reel on if off)
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

-- sleep in small slices so Stop() is instant even on a long wait
local function SleepWhileRunning(secs)
    local until_ = os.clock() + math.max(0, secs)
    while Automation.Running and os.clock() < until_ do
        task.wait(math.min(1, until_ - os.clock()))
    end
    return Automation.Running
end

-- the worker: wait for the next real-clock slot, go to Core Spot, fish, come back
local function AutomationRun()
    if Automation.Running then return end
    Automation.Running = true
    Automation.Enabled = true

    LoadCoreConfig()
    Automation.Thread = task.spawn(function()
        local fishSecs = math.max(1, tonumber(Automation.FishMin) or 10) * 60

        while Automation.Running do
            --── WAIT until the next real-clock slot (top of the hour by default) ──
            local now = nowSec()
            if now then
                local waitSecs, slotAt = secsUntilNextSlot(now, Automation.EveryMin)
                Automation.NextSlotAt = slotAt
                AutomationSetState("waiting",
                    "Waiting for " .. clockStr(slotAt) .. " (in " .. math.floor(waitSecs / 60) .. " min)")
                if not SleepWhileRunning(waitSecs) then break end
            else
                -- no clock available: fall back to a simple hourly wait
                AutomationSetState("waiting", "Waiting ~60 min (no clock)")
                if not SleepWhileRunning(60 * 60) then break end
            end

            --── GO to the Core Spot and fish ──
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

            --── BACK to Spot Mancing ──
            Notify("Auto Core", clockStr(nowSec()) .. " - back to Spot Mancing", 4)
            AutomationSetState("back", nil)
            pcall(TpTo, Automation.MancingPos, "Spot Mancing")
            -- loop back to the WAIT step, which now targets the NEXT :00 slot
        end

        Automation.Running = false
        AutomationSetState("idle", nil)
    end)
end

--───────────────────────────────────────────────────────────────────────────
-- AUTO CORE CATCH  (Automation tab)
-- FREE SCRIPT: Locked (Locked=true) - the controls are fully INERT.
--───────────────────────────────────────────────────────────────────────────
do
    local T = Tabs.AutoCore
    local S = T:Section({ Title = "Auto Core Catch (LOCKED)" })

    S:Toggle({ Title = "Auto Core Catch (1 hour)", Value = false, Locked = true,
        LockedTitle = "Locked in the Free script" })

    S:Button({ Title = "Status: Locked", Icon = "lock", Locked = true,
        LockedTitle = "Locked in the Free script" })

    S:Slider({
        Title = "Trigger Every (minutes on the clock)",
        Value = { Min = 10, Max = 120, Default = 60 }, Step = 10,
        Locked = true, LockedTitle = "Locked in the Free script",
    })
    S:Slider({
        Title = "Fish At Core Spot (minutes)",
        Value = { Min = 1, Max = 30, Default = 10 }, Step = 1,
        Locked = true, LockedTitle = "Locked in the Free script",
    })

    S:Button({ Title = "Go Core Spot Now", Icon = "lock", Locked = true,
        LockedTitle = "Locked in the Free script" })
end

--───────────────────────────────────────────────────────────────────────────
-- AUTO ACCEPT GALATAMA  (Automation tab)  -  auto-joins the Glatama event.
-- FREE SCRIPT: Locked (Locked=true) - the controls are fully INERT.
--───────────────────────────────────────────────────────────────────────────
do
    local T = Tabs.AutoCore
    local S = T:Section({ Title = "Auto Accept Galatama (LOCKED)" })

    S:Toggle({ Title = "Auto Accept Galatama", Value = false, Locked = true,
        LockedTitle = "Locked in the Free script" })

    S:Button({ Title = "Join Galatama Now", Icon = "lock", Locked = true,
        LockedTitle = "Locked in the Free script" })
end

-- SETTINGS TAB
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
            _G.X0_MTS_SummitNotifyOff = (Summit.Notify == false)   -- keep global gate in sync
            pcall(function() summitBtn:SetTitle(summitLabel()) end)
            -- always confirm via a direct notify so the user sees it flip even
            -- when the Summit popups themselves are being silenced.
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

-- CONFIG TAB
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

-- INFO TAB
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

--───────────────────────────────────────────────────────────────────────────
-- WEBHOOK  (Webhook tab)
--
-- Posts a Discord embed every time a fish is caught, laid out like the
-- reference: a top content line, four stacked fields, the big fish image, then
-- a footer with the hub name + timestamps.
--
-- The catch payload comes straight from the rod's NotifyClient "GotFish" event:
--   baseName / originalName / toolName  -> fish name
--   rarity / grade                      -> tier (Common..Secret..Forgotten)
--   weight                              -> number (kg)
--   mutation                            -> e.g. None / Golden / ...
-- The big fish IMAGE is looked up from the game's own database:
--   ReplicatedStorage.Modules.Fishing.FishingImageDatabase.Fish[<name>].Icon
--
-- Embed layout (matches the reference screenshot):
--   Content : "You have obtained a new <TIER> fish - <Name>!"
--   Field 1 : "Fish Name :"  -> <name>
--   Field 2 : "Fish Tier :"  -> <TIER>        (uppercase)
--   Field 3 : "Weight :"     -> <n> Kg
--   Field 4 : "Mutation :"   -> <mutation>
--   Image   : the large fish art
--   Footer  : "Choco Webhook  -  Mount Soreya"  + timestamp
-- NOTE: no Sell Price field.
--
-- RARITY FILTER: pick nothing -> EVERY fish is posted. Pick one or more rarities
-- (dropdown) -> ONLY those rarities are posted (e.g. pick "Secret" and you ONLY
-- get Secret-catch webhooks).
--───────────────────────────────────────────────────────────────────────────
local Hook = {
    Enabled   = false,
    Url       = "",
    Rarities  = {},           -- empty = ALL fish; else only these rarities
    MentionId = "",           -- optional role/user id to ping
    LastSent  = 0,
    Sent      = 0,
    -- the canonical rarity list the game uses (TierIkan) plus CORE for cores.
    AllRarities = {
        "Common", "UnCommon", "Rare", "Epic",
        "Legendary", "Mythical", "Secret", "Forgotten", "CORE",
    },
}
_G.X0_MTS_Hook = Hook

-- Find the executor's HTTP request function (varies per executor).
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

-- FISH IMAGE DATABASE (embedded).
--
-- These are the game's OWN fish icons (asset ids), embedded so the webhook image
-- works even if require() of the game module fails on this executor/VM. The
-- lookup below also tries the LIVE game module first and falls back to this table.
-- Names are matched with the game's own rules: exact -> spaces-stripped -> strip a
-- leading mutation word ("Golden ", "Big ", etc.) -> default icon.
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

-- strip a leading mutation word ("Golden ", "Big ", ...) from a fish name.
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

--───────────────────────────────────────────────────────────────────────────
-- CORE ICON  -  a "Core" is NOT a normal fish, so it is NOT in the fish image
-- database: a core's art lives in the game's own CoreConfig
-- (ReplicatedStorage.Modules.Fishing.CoreConfig). The default is the Withering
-- Core art, which is what the game itself falls back to.
--
--   CoreConfig = {
--       NamaItem  = "Withering Core",
--       RodSyarat = "Withering Rod",
--       Icon      = "rbxassetid://116659997697473",
--   }
--
-- The webhook used to look a core catch up like any fish, miss, and post the
-- generic DEFAULT_ICON - that is the "fallback image" the core was showing. We
-- now read the LIVE CoreConfig.Icon first (so a future core art works too) and
-- fall back to the baked Withering Core art.
--───────────────────────────────────────────────────────────────────────────
local CORE_ICON_FALLBACK = "rbxassetid://116659997697473"   -- Withering Core (game default)
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

-- Is this catch a Core (vs a normal fish)? True when the payload carries a
-- CoreId, or the name matches the CoreConfig item name ("Withering Core"), or it
-- simply ends with " Core".
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

-- Look up the fish's in-game icon. Tries the LIVE game module first (authoritative,
-- may include fish added after this build), then the embedded `FISH_ICONS` table.
local FishImageDB, FishImageTried = nil, false
local function HookFishImage(name, data)
    if not name then return DEFAULT_ICON end
    -- 0) the payload's OWN icon override, if the server sent one (GotFish "ikon").
    --    This is authoritative - the game itself uses it verbatim.
    if type(data) == "table" then
        local direct = data.ikon or data.icon or data.Icon
        if type(direct) == "string" and direct ~= "" then return direct end
    end
    -- a Core is not a fish: use the CoreConfig art, never the fish database
    if IsCoreCatch(name, data) then return CoreIcon() end
    if not FishImageTried then
        FishImageTried = true
        pcall(function()
            FishImageDB = require(ReplicatedStorage.Modules.Fishing.FishingImageDatabase)
        end)
    end
    -- 1) live game module
    if FishImageDB and FishImageDB.Fish then
        local n = tostring(name)
        local entry = FishImageDB.Fish[n] or FishImageDB.Fish[n:gsub("%s+", "")] or FishImageDB.Fish[StripMutation(n)]
        if type(entry) == "table" and entry.Icon then return entry.Icon end
        if type(entry) == "string" then return entry end
    end
    -- 2) embedded table (same matching rules as the game's GetFishData)
    local n = tostring(name)
    local icon = FISH_ICONS[n]
        or FISH_ICONS[n:gsub("%s+", "")]
        or FISH_ICONS[StripMutation(n)]
    return icon or DEFAULT_ICON
end

-- Turn an rbxassetid string into a URL Discord can actually render.
--
-- The OLD 'roblox.com/asset-thumbnail/image?assetId=' endpoint does NOT reliably
-- serve decal/image assets, so Discord shows a broken image. The correct way is
-- Roblox's thumbnail API, which returns the real CDN url:
--   https://thumbnails.roblox.com/v1/assets?assetIds=<id>&size=420x420&format=Png
-- We resolve it with the same executor HTTP function and cache the result per id
-- so we only pay the extra call once per unique fish.
local ThumbCache = {}
local function GetRequestFn()
    return (syn and syn.request) or (http and http.request) or http_request
        or (fluxus and fluxus.request) or (request)
end
local function ResolveAssetUrl(id)
    if ThumbCache[id] then return ThumbCache[id] end
    -- Fallbacks, in order of preference. The thumbnails API is best but returns
    -- state="Pending" the FIRST time a fresh asset is requested (Roblox renders
    -- it on demand), so we poll a few times until it completes.
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
                -- Pending -> wait briefly and ask again
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

-- Should this catch be posted? No rarity picked = ALL; else only picked ones.
local function HookShouldSend(rarity)
    if next(Hook.Rarities) == nil then return true end
    rarity = tostring(rarity or "Common")
    for _, r in ipairs(Hook.Rarities) do
        if r == rarity then return true end
    end
    return false
end

-- Build the Discord embed from a GotFish payload and POST it.
-- Layout matches the reference: a content line ("You have obtained a new
-- <RARITY> fish - <Name>!"), then FOUR stacked fields (Fish Name / Fish Tier /
-- Weight / Mutation), then the LARGE fish image, then a footer with the hub name
-- and the timestamp.
--
-- A CORE catch is handled separately: it is not a fish (no fish rarity), so it
-- gets a "CORE" tier badge, the core's own art (CoreConfig.Icon) and a
-- "new CORE - <name>!" content line - never the generic fallback image.
HookSendCatch = function(data)
    if not Hook.Enabled then return end
    if not Hook.Url or Hook.Url == "" then return end
    if type(data) ~= "table" then return end

    local name = data.baseName or data.originalName or data.toolName or "Mystery Fish"
    local isCore = IsCoreCatch(name, data)
    local rarity = tostring(data.rarity or data.grade or "Common")
    -- A core has no fish rarity; present it as a CORE tier for the badge/colour.
    if isCore then rarity = "CORE" end
    local weight = tonumber(data.weight) or 0
    local mutation = tostring(data.mutation or "Normal")

    if not HookShouldSend(rarity) then return end

    local tierUp = string.upper(rarity)

    Hook.LastSent = tick()
    Hook.Sent = (Hook.Sent or 0) + 1

    local embed = {
        -- each field's "name" is the bold label line, "value" sits under it.
        color  = RARITY_COLOR[rarity] or (isCore and 0x8A2BE2 or 0x5865F2),
        fields = {
            { name = "Item Name :", value = tostring(name),                        inline = false },
            { name = "Tier :",      value = tierUp,                                inline = false },
            { name = "Weight :",    value = string.format("%.2f Kg", weight),      inline = false },
            { name = "Mutation :",  value = mutation,                              inline = false },
        },
        footer = {
            text    = "Choco Webhook  -  Mount Soreya",
            -- icon_url is filled in below (resolved from the hub logo asset id)
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

    -- fire-and-forget on its own thread: image resolution (a blocking HTTP GET)
    -- and the POST both happen here, so the fishing loop is never stalled.
    task.spawn(function()
        -- resolve the fish icon -> real CDN url, then attach as the big image
        local img = HookThumbUrl(HookFishImage(name, data))
        if img then embed.image = { url = img } end
        -- hub logo as the footer icon (resolved to a renderable url)
        local logo = HookThumbUrl(HUB.LogoId)
        if logo then embed.footer.icon_url = logo end

        local ok, err = HookRequest(Hook.Url, payload)
        if not ok and err == "no_http" then
            Notify("Webhook", "Your executor has no HTTP request function", 5)
        end
    end)
end
_G.X0_MTS_HookSend = HookSendCatch

-- WEBHOOK TAB
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

    -- RARITY picker. Leave EMPTY for ALL fish, or pick the rarity/rarities you
    -- want posted (e.g. only "Secret" -> only Secret catches send a webhook).
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

    -- DEBUG: resolve a fish name -> icon asset -> final CDN url, and show it.
    -- Use this to confirm the image pipeline works on your executor.
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

    -- send a CORE test so you can confirm the core art (CoreConfig.Icon) shows
    -- instead of the generic fallback. Uses the game's live CoreConfig values.
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

-- MISCELLANEOUS TAB  -  Fly  (same approach as Choco Misc)
--
-- Uses the proven Choco Misc fly: Humanoid.PlatformStand = true so the Humanoid
-- stops fighting us, a BodyVelocity for movement force + a BodyGyro that tracks
-- the camera so the character stays upright and faces where you look. A
-- Heartbeat loop reads WASD (camera relative), Space (up) and LeftControl (down)
-- and sets the BodyVelocity to dir.Unit * Fly Speed. Everything is destroyed and
-- PlatformStand restored on toggle-off and on Unload.
--───────────────────────────────────────────────────────────────────────────
local Fly = {
    Active = false,
    Speed  = 50,        -- studs/second
    Thread = nil,
    Bv     = nil,       -- BodyVelocity mover
    Bg     = nil,       -- BodyGyro (camera-upright)
}

function Fly.Stop()
    Fly.Active = false
    if Fly.Bv then pcall(function() Fly.Bv:Destroy() end) Fly.Bv = nil end
    if Fly.Bg then pcall(function() Fly.Bg:Destroy() end) Fly.Bg = nil end
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

    Fly.Thread = task.spawn(function()
        while Fly.Active and hrp and hrp.Parent do
            local dir = Vector3.zero
            local cam = Camera or workspace.CurrentCamera
            local cf = cam and cam.CFrame
            if cf then
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cf.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cf.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cf.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cf.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0, 1, 0) end
                if dir.Magnitude > 0 then
                    bv.Velocity = dir.Unit * Fly.Speed
                else
                    bv.Velocity = Vector3.zero
                end
                bg.CFrame = cf
            end
            RunService.Heartbeat:Wait()
        end
    end)
    return true
end
_G.X0_MTS_Fly = Fly

do
    local S = Tabs.Misc:Section({ Title = "Fly (LOCKED)" })
    S:Toggle({ Title = "Enable Fly", Value = false, Locked = true,
        LockedTitle = "Locked in the Free script" })
    S:Slider({ Title = "Fly Speed", Value = { Min = 5, Max = 300, Default = 50 }, Step = 1,
        Locked = true, LockedTitle = "Locked in the Free script" })
end

--───────────────────────────────────────────────────────────────────────────
-- ANTI-AFK  (Misc tab)
--
-- Roblox fires Player.Idled when you would be kicked for being idle (after
-- ~20 minutes). The standard trick is to answer it with a virtual input so the
-- client counts as active: CaptureController() + ClickButton2(). We connect to
-- Idled once and only act while the toggle is on, so flipping it off restores
-- normal AFK behaviour. The connection is registered with ConnMgr so Unload
-- removes it.
--───────────────────────────────────────────────────────────────────────────
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

--───────────────────────────────────────────────────────────────────────────
-- INVISIBLE AVATAR  (Misc tab)
--
-- Makes your whole character (parts + accessories + decals) fully transparent.
-- A Stepped loop keeps re-applying it, because the game can reset a part's
-- transparency at any time (respawn, animation, gear). Turning it off restores
-- the ORIGINAL transparency of every part we touched. Client-side only - other
-- players may still see you (this hides YOU from your own view + local effects).
--───────────────────────────────────────────────────────────────────────────
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

--───────────────────────────────────────────────────────────────────────────
-- INVISIBLE GUI  (Misc tab)
--
-- Hides every ScreenGui in your PlayerGui (the game's HUD, the fishing UI, other
-- executors' menus, etc.). A Stepped loop re-hides new GUIs as the game creates
-- them. Turning it off re-enables EXACTLY the GUIs we hid, so nothing the game
-- added while hidden is left disabled.
--───────────────────────────────────────────────────────────────────────────
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

--───────────────────────────────────────────────────────────────────────────
-- NO ANIMATION  (Misc tab)
--
-- The rod plays swing/hold animation tracks through the character's Animator
-- (the game's RodAnim module loads them). This toggle stops every playing
-- AnimationTrack on your Humanoid's Animator each frame, so the rod "skin"
-- animation never shows. It is client-side: your character simply stops
-- animating (rod swing, cast pose, etc.). Turning it off lets animations run
-- normally again - we do NOT permanently destroy tracks, just Stop() them.
--───────────────────────────────────────────────────────────────────────────
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

--───────────────────────────────────────────────────────────────────────────
-- FPS + PING HUD  (Misc tab)  -  same draggable "pill" as the VD hub.
--
-- A small rounded pill at the top-left showing live FPS and ping, colour-coded
-- (green good / yellow ok / red bad). It is draggable by mouse or touch. FPS is
-- measured by counting RenderStepped frames over a 0.5s window; ping is read
-- from the engine's own Stats.Network.ServerStatsItem["Data Ping"]. Destroyed
-- and rebuilt by the toggle, and fully removed on Unload.
--───────────────────────────────────────────────────────────────────────────
local FPSCounter = {
    Enabled    = false,
    Gui        = nil,
    Labels     = nil,       -- { fps = TextLabel, ping = TextLabel }
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
    sg.Name = "Choco_SOREYAFREE_FPS"
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
    fpsLbl.Text = "-- fps"
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
    pingLbl.Text = "-- ms"
    pingLbl.TextColor3 = Color3.fromRGB(120, 240, 120)
    pingLbl.Font = Enum.Font.GothamBold
    pingLbl.TextSize = 11
    pingLbl.TextXAlignment = Enum.TextXAlignment.Left
    pingLbl.LayoutOrder = 3

    -- drag by mouse or touch
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

-- the measuring loop (registered with ConnMgr so Unload removes it)
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

-- optional FPS cap (executor setfpscap). "None" = uncapped.
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

--───────────────────────────────────────────────────────────────────────────
-- CLEANUP
--───────────────────────────────────────────────────────────────────────────
local function MasterCleanup()
    Auto.LoopStop = true                    -- end the fishing loop for good
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
    -- webhook: stop posting and clear the saved URL (don't leave it in _G)
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
        _G[INSTANCE_KEY].running = false        -- tell any booting instance we stopped
        local w = _G[INSTANCE_KEY].window or _G[INSTANCE_KEY].Window
        if w then pcall(function() w:Destroy() end) end
    end
    _G[INSTANCE_KEY] = nil
    Notify("Choco Hub", "Hub unloaded", 2)
end
_G[INSTANCE_KEY].cleanup = MasterCleanup
_G[INSTANCE_KEY].destroy = MasterCleanup
_G[INSTANCE_KEY].running = true

--───────────────────────────────────────────────────────────────────────────
-- BOOT
--───────────────────────────────────────────────────────────────────────────
task.spawn(function()
    task.wait(0.5)
    DiscoverRod()
    InstallBiteWatch()
    InstallReelHook()
    -- patch the game's throw module so the bait lands in the water instantly
    pcall(InstallBaitPatch)
    -- Both features are OFF by default: nothing fishes until you toggle one on.
    -- (The hooks above are still installed so the toggles work immediately.)
    if AutoActive() then StartAuto() end
    -- keep the shared "!" marker auto-showing while a fish is on the line
    if Auto.AutoShowMarker then pcall(AutoMarker.Start) end
    Log("Choco HUB Free Loaded")
    Notify("Choco HUB Free", "Loaded", 4)
end)

-- build the floating logo (retry + self-heal, like the other Choco hubs)
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
        -- self-heal the FPS/ping pill too (the game can clear ScreenGuis)
        if FPSCounter.Enabled and not (FPSCounter.Gui and FPSCounter.Gui.Parent) then
            FPSCounter.Build()
        end
    end
end)

--───────────────────────────────────────────────────────────────────────────
-- ROD-CHANGE WATCHER  -  when you equip a different rod, its CastEvent/MiniGame
-- are NEW instances, so the old hook connections are dead. This re-binds the
-- bite + reel hooks to whatever rod is currently equipped, so EVERY rod works
-- (Ares, Bamboo, Element, Diamond, Withering, Ghostfinn, Starter, ...).
--───────────────────────────────────────────────────────────────────────────
local _lastBoundMiniGame = nil
local _rodCheckAcc = 0
ConnMgr:Add(RunService.Heartbeat:Connect(function(dt)
    _rodCheckAcc = _rodCheckAcc + dt
    if _rodCheckAcc < 0.5 then return end      -- throttle: heavy scan, 2x/sec
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

-- re-hook the bite listener after respawn / rod re-equip
ConnMgr:Add(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    DiscoverRod()
    InstallBiteWatch()
    InstallReelHook()
    -- re-apply Misc features that need a character after a respawn
    if Invis.Enabled then pcall(Invis.Start) end
end))
