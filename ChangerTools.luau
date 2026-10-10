local Players            = game:GetService("Players")
local InsertService      = game:GetService("InsertService")
local MarketplaceService = game:GetService("MarketplaceService")
local CoreGui            = game:GetService("CoreGui")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local ContentProvider    = game:GetService("ContentProvider")
local Lighting           = game:GetService("Lighting")
local Workspace          = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

local TOOL_KEY = "__CHOCO_CHANGER_v100"
if _G[TOOL_KEY] then
    local prev = _G[TOOL_KEY]
    if type(prev.destroy) == "function" then pcall(prev.destroy) end
    _G[TOOL_KEY] = nil
    task.wait(0.25)
end

-- WindUI (Footagesus) - modern UI library
local WindUI
do
    local ok, result = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
    end)
    if not ok or not result then
        error("[Choco] WindUI load failed: " .. tostring(result))
    end
    WindUI = result
end

local TOOL = {
    Name    = "Choco Changer",
    Version = "1.00",
    LogoId  = "rbxassetid://129308061683379",
}

local CM = { _list = {} }
function CM:Add(sig, cb)
    if not sig then return end
    local s, conn = pcall(function() return sig:Connect(cb) end)
    if s and conn then table.insert(self._list, conn); return conn end
end
function CM:Cleanup()
    for _, c in ipairs(self._list) do pcall(function() c:Disconnect() end) end
    self._list = {}
end

local function GuiParent()
    local p = CoreGui
    pcall(function() if gethui then p = gethui() end end)
    return p
end

local function Notif(t, c, d)
    pcall(function()
        WindUI:Notify({ Title = tostring(t), Content = tostring(c), Duration = tonumber(d) or 3 })
    end)
end

local function GetChar() return LocalPlayer.Character end
local function GetHumanoid()
    local c = GetChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function IsR15()
    local h = GetHumanoid()
    return h and h.RigType == Enum.HumanoidRigType.R15
end
local function Log(m) print("[Choco Changer] " .. tostring(m)) end

local State = {
    SavedIds         = {},
    Instances        = {},

    Headless         = false,
    KorbloxRight     = false,
    KorbloxLeft      = false,

    -- manual mesh override (paste a working Korblox mesh id here)
    ManualMeshRight  = "",
    ManualTexRight   = "",
    ManualMeshLeft   = "",
    ManualTexLeft    = "",

    FloatingLogo     = true,
    LogoGui          = nil,
    LogoImage        = nil,
    LogoSize         = 60,
    LogoTransparency = 0.1,

    -- Cinematic
    Cinematic        = false,
    CineBarsGui      = nil,
    CineBarTop       = nil,
    CineBarBottom    = nil,
    CineFOV          = 70,
    CineDofEnabled   = true,
    CineBarSize      = 12,   -- % of screen height per bar

    -- Graphics
    Fullbright       = false,
    NoFog            = false,
    NoShadows        = false,
    NoBlur           = false,
    NoParticles      = false,
    NoGrass          = false,
    QualityLevel     = 10,   -- 1..10 (Level01..Level10) or 0 = Automatic
    GraphicsFOV      = 70,
    ClockTime        = 14,
    _lightBackup     = nil,
}

-- Real Korblox Deathspeaker bundle asset ids (these are ASSETS, not mesh files)
local KORBLOX_RIGHT_ID = 139607718
local KORBLOX_LEFT_ID  = 139607673

local _korbloxBackup = {}

-- Forward declarations: these are used by AddAccessorySafe (defined below)
-- before their full definitions appear. Declaring them here avoids nil-global
-- errors at runtime. (This was a real bug in v2.4.0.)
local TrackInstance, DestroyTracked, FindSaved, AddSaved, RemoveSaved

-- Forward declarations for Cinematic/Graphics (used by CharacterAdded handler
-- before the modules are defined further down).
local Cinematic, Graphics

-- Per-side cache of the REAL mesh info extracted at runtime from the asset
-- { meshId = "...", textureId = "..." }
local _korbloxRealMesh = { Right = nil, Left = nil }

-- HARDCODED FALLBACK (belt-and-suspenders):
-- Diagnostic PROVED GetObjects is unavailable and InsertService:LoadAsset is
-- blocked in the executor - so runtime loading CANNOT work. We use hardcoded
-- mesh ids applied directly. This is how all working Korblox scripts do it.
--
-- 101851696 = "Korblox-SM-RL" right leg mesh   (real, confirmed)
-- 101851254 = Korblox overlay texture          (real, confirmed)
-- R6 uses CharacterMesh (native swap). R15 uses SpecialMesh on the leg parts.
local KORBLOX_MESH_NUM   = 101851696
local KORBLOX_TEX_NUM    = 101851254
local KORBLOX_MESH_STR   = "rbxassetid://" .. KORBLOX_MESH_NUM
local KORBLOX_TEX_STR    = "rbxassetid://" .. KORBLOX_TEX_NUM

local KORBLOX_FALLBACK = {
    Right = {
        meshId     = KORBLOX_MESH_STR,   -- string form (SpecialMesh)
        meshIdText = KORBLOX_MESH_NUM,   -- number form (CharacterMesh)
        textureId  = KORBLOX_TEX_STR,
        textureIdText = KORBLOX_TEX_NUM,
        nativeSize = nil,   -- nil => scale (1,1,1)
        pieces = {},
    },
    Left = {
        meshId     = KORBLOX_MESH_STR,
        meshIdText = KORBLOX_MESH_NUM,
        textureId  = KORBLOX_TEX_STR,
        textureIdText = KORBLOX_TEX_NUM,
        nativeSize = nil,
        pieces = {},
    },
}
local function HasFallback(side)
    local t = KORBLOX_FALLBACK[side]
    return t and t.meshId ~= nil
end

local function IsValidMeshId(mid)
    if type(mid) ~= "string" or mid == "" then return false end
    return mid:find("rbxassetid://") ~= nil or mid:find("asset/?id=") ~= nil
end

local R6_ATTACHMENT_FALLBACKS = {
    HatAttachment          = { part = "Head", cf = CFrame.new(0, 0.5, 0) },
    HairAttachment         = { part = "Head", cf = CFrame.new(0, 0.6, 0) },
    FaceFrontAttachment    = { part = "Head", cf = CFrame.new(0, 0, -0.5) },
    FaceCenterAttachment   = { part = "Head", cf = CFrame.new(0, 0, 0) },

    NeckAttachment         = { part = "Torso", cf = CFrame.new(0, 1, 0) },
    BodyFrontAttachment    = { part = "Torso", cf = CFrame.new(0, 0, -0.5) },
    BodyBackAttachment     = { part = "Torso", cf = CFrame.new(0, 0, 0.5) },
    WaistCenterAttachment  = { part = "Torso", cf = CFrame.new(0, -1, 0) },
    WaistFrontAttachment   = { part = "Torso", cf = CFrame.new(0, -1, -0.5) },
    WaistBackAttachment    = { part = "Torso", cf = CFrame.new(0, -1, 0.5) },
    LeftCollarAttachment   = { part = "Torso", cf = CFrame.new(-0.5, 1, 0) },
    RightCollarAttachment  = { part = "Torso", cf = CFrame.new(0.5, 1, 0) },

    LeftShoulderAttachment  = { part = "Left Arm", cf = CFrame.new(0, 0.5, 0) },
    LeftElbowAttachment     = { part = "Left Arm", cf = CFrame.new(0, 0, 0) },
    LeftWristAttachment     = { part = "Left Arm", cf = CFrame.new(0, -0.5, 0) },

    RightShoulderAttachment = { part = "Right Arm", cf = CFrame.new(0, 0.5, 0) },
    RightElbowAttachment    = { part = "Right Arm", cf = CFrame.new(0, 0, 0) },
    RightWristAttachment    = { part = "Right Arm", cf = CFrame.new(0, -0.5, 0) },

    LeftHipAttachment       = { part = "Left Leg", cf = CFrame.new(0, 0.5, 0) },
    LeftKneeAttachment      = { part = "Left Leg", cf = CFrame.new(0, 0, 0) },
    LeftAnkleAttachment     = { part = "Left Leg", cf = CFrame.new(0, -0.5, 0) },

    RightHipAttachment      = { part = "Right Leg", cf = CFrame.new(0, 0.5, 0) },
    RightKneeAttachment     = { part = "Right Leg", cf = CFrame.new(0, 0, 0) },
    RightAnkleAttachment    = { part = "Right Leg", cf = CFrame.new(0, -0.5, 0) },
}

--------------------------------------------------------------------------------
-- TRANSPARENCY LOCK (keeps Korblox visible even in games that hide parts)
--------------------------------------------------------------------------------
CM:Add(RunService.RenderStepped, function()
    local char = GetChar()
    if not char then return end

    if State.KorbloxRight then
        local rLegR6 = char:FindFirstChild("Right Leg")
        if rLegR6 then
            rLegR6.Transparency = 1
            pcall(function() rLegR6.LocalTransparencyModifier = 1 end)
        end
        if IsR15() and char:FindFirstChild("X0_Korblox_Folder_Right") then
            for _, n in ipairs({"RightUpperLeg", "RightLowerLeg", "RightFoot"}) do
                local p = char:FindFirstChild(n)
                if p then
                    p.Transparency = 1
                    pcall(function() p.LocalTransparencyModifier = 1 end)
                end
            end
        end
    end

    if State.KorbloxLeft then
        local lLegR6 = char:FindFirstChild("Left Leg")
        if lLegR6 then
            lLegR6.Transparency = 1
            pcall(function() lLegR6.LocalTransparencyModifier = 1 end)
        end
        if IsR15() and char:FindFirstChild("X0_Korblox_Folder_Left") then
            for _, n in ipairs({"LeftUpperLeg", "LeftLowerLeg", "LeftFoot"}) do
                local p = char:FindFirstChild(n)
                if p then
                    p.Transparency = 1
                    pcall(function() p.LocalTransparencyModifier = 1 end)
                end
            end
        end
    end

    for _, child in ipairs(char:GetChildren()) do
        if child.Name:match("^X0_Korblox_Folder") then
            for _, p in ipairs(child:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.Transparency = 0
                    pcall(function() p.LocalTransparencyModifier = 0 end)
                end
            end
        end
    end

    if State.Headless then
        local head = char:FindFirstChild("Head")
        if head then
            head.Transparency = 1
            pcall(function() head.LocalTransparencyModifier = 1 end)
            for _, d in ipairs(head:GetChildren()) do
                if d:IsA("Decal") then d.Transparency = 1 end
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- ID / ASSET HELPERS
--------------------------------------------------------------------------------
local function ParseId(input)
    if not input or input == "" then return nil end
    input = tostring(input):gsub("%s+", "")

    local urlId = input:match("roblox%.com/catalog/(%d+)")
              or input:match("roblox%.com/bundles/(%d+)")
              or input:match("roblox%.com/library/(%d+)")
              or input:match("roblox%.com/item/(%d+)")
              or input:match("roblox%.com/.+/catalog/(%d+)")
    if urlId then return tonumber(urlId) end

    local rbxId = input:match("rbxassetid://(%d+)")
    if rbxId then return tonumber(rbxId) end

    if input:match("^%d+$") then return tonumber(input) end

    local num = input:match("(%d+)")
    if num and #num >= 5 then return tonumber(num) end

    return nil
end

local ASSET_TYPE_MAP = {
    [2]  = "TShirt",  [8]  = "Hat",     [11] = "Shirt",   [12] = "Pants",
    [17] = "Head",    [18] = "Face",    [19] = "Gear",    [27] = "Torso",
    [28] = "RightArm",[29] = "LeftArm", [30] = "LeftLeg", [31] = "RightLeg",
    [41] = "Hair",    [42] = "FaceAccessory", [43] = "Neck", [44] = "Shoulder",
    [45] = "Front",   [46] = "Back",    [47] = "Waist",
    [64] = "TShirtAccessory", [65] = "ShirtAccessory", [66] = "PantsAccessory",
    [67] = "Jacket",  [68] = "Sweater", [69] = "Shorts",
    [70] = "LeftShoe",[71] = "RightShoe", [72] = "DressSkirt",
    [76] = "Eyebrow", [77] = "Eyelash",
}

local function GetAssetInfo(assetId)
    local info = nil
    pcall(function()
        info = MarketplaceService:GetProductInfo(assetId, Enum.InfoType.Asset)
    end)
    return info
end

local function LoadAssetModel(assetId)
    local assetStr = "rbxassetid://" .. tostring(assetId)
    local model = nil
    local method = "none"

    if typeof(GetObjects) == "function" then
        local ok, res = pcall(function() return GetObjects(assetStr) end)
        if ok and res then
            if typeof(res) == "table" and res[1] then model = res[1]; method = "GetObjects"
            elseif typeof(res) == "Instance" then model = res; method = "GetObjects" end
        end
    end

    if not model then
        local ok, res = pcall(function() return InsertService:LoadLocalAsset(assetStr) end)
        if ok and res then model = res; method = "LoadLocalAsset" end
    end

    if not model then
        local ok, res = pcall(function() return InsertService:LoadAsset(assetId) end)
        if ok and res then model = res; method = "LoadAsset" end
    end

    return model, method
end

--------------------------------------------------------------------------------
-- KORBLOX: EXTRACT THE REAL MESH FROM THE ASSET
--------------------------------------------------------------------------------
-- Reads every mesh-ish descendant of the loaded asset and returns the best
-- meshId + textureId pair (the actual Korblox leg mesh files).
local function ExtractMeshInfo(model)
    if not model then return nil end
    local out = { pieces = {} }

    for _, v in ipairs(model:GetDescendants()) do
        local meshId, texId = nil, nil
        local nativeSize = nil
        if v:IsA("MeshPart") then
            meshId = v.MeshId
            texId  = v.TextureID
            nativeSize = v.Size
        elseif v:IsA("SpecialMesh") then
            meshId = v.MeshId
            texId  = v.TextureId
            local host = v.Parent
            if host and host:IsA("BasePart") then nativeSize = host.Size end
        elseif v:IsA("FileMesh") then
            meshId = v.MeshId
            texId  = v.TextureId
            local host = v.Parent
            if host and host:IsA("BasePart") then nativeSize = host.Size end
        end

        if meshId and meshId ~= "" then
            table.insert(out.pieces, {
                source = v,
                meshId = meshId,
                textureId = texId,
                partName = v.Parent and v.Parent.Name or v.Name,
                size = nativeSize,
                nativeSize = nativeSize,
            })
        end
    end

    if #out.pieces == 0 then return nil end
    out.meshId = out.pieces[1].meshId
    out.meshIdText = tonumber(tostring(out.meshId):match("(%d+)"))
    out.textureId = out.pieces[1].textureId
    out.textureIdText = out.textureId and tonumber(tostring(out.textureId):match("(%d+)")) or nil
    out.nativeSize = out.pieces[1].nativeSize
    return out
end

-- Load the real Korblox asset and remember the true mesh ids (cached per side).
-- Order: manual override -> runtime asset -> hardcoded fallback.
local function EnsureRealKorbloxMesh(side)
    if _korbloxRealMesh[side] then return _korbloxRealMesh[side] end

    -- 1) MANUAL OVERRIDE (user pasted a known-good mesh id)
    do
        local mid = (side == "Right") and State.ManualMeshRight or State.ManualMeshLeft
        local tid = (side == "Right") and State.ManualTexRight  or State.ManualTexLeft
        if mid and mid ~= "" then
            local info = {
                meshId = mid,
                meshIdText = tonumber(tostring(mid):match("(%d+)")),
                textureId = (tid ~= "" and tid) or nil,
                textureIdText = (tid ~= "" and tonumber(tostring(tid):match("(%d+)"))) or nil,
                nativeSize = nil,
                pieces = { { meshId = mid, textureId = tid, partName = "leg", nativeSize = nil } },
            }
            _korbloxRealMesh[side] = info
            Log("Korblox " .. side .. ": using MANUAL mesh " .. tostring(mid))
            return info
        end
    end

    -- 2) HARDCODED FALLBACK FIRST.
    -- Diagnostic proved InsertService:LoadAsset + GetObjects are BLOCKED in most
    -- executors, so the known-good hardcoded mesh is the reliable path. We use it
    -- directly instead of wasting time on a load call that will fail.
    if HasFallback(side) then
        local fb = KORBLOX_FALLBACK[side]
        local info = {
            meshId = fb.meshId,
            meshIdText = fb.meshIdText,
            textureId = fb.textureId,
            textureIdText = fb.textureIdText,
            nativeSize = fb.nativeSize,
            pieces = fb.pieces or {},
        }
        if #info.pieces == 0 then
            info.pieces = { { meshId = fb.meshId, textureId = fb.textureId, partName = "leg", nativeSize = info.nativeSize } }
        end
        _korbloxRealMesh[side] = info
        Log("Korblox " .. side .. ": using HARDCODED mesh " .. tostring(fb.meshId))
        return info
    end

    -- 3) RUNTIME (last resort - only worth trying if no fallback exists)
    local assetId = (side == "Right") and KORBLOX_RIGHT_ID or KORBLOX_LEFT_ID
    local model, method = LoadAssetModel(assetId)

    if model then
        local info = ExtractMeshInfo(model)
        pcall(function() model:Destroy() end)

        if info and IsValidMeshId(info.meshId) then
            _korbloxRealMesh[side] = info
            Log("Korblox " .. side .. ": REAL mesh = " .. tostring(info.meshId)
                .. " | texture = " .. tostring(info.textureId)
                .. " | nativeSize = " .. tostring(info.nativeSize)
                .. " | pieces = " .. #info.pieces .. " (" .. method .. ")")
            return info
        end
        Log("Korblox " .. side .. ": asset loaded (" .. method .. ") but no VALID mesh found")
    else
        Log("Korblox " .. side .. ": could NOT load asset " .. assetId .. " (InsertService blocked?)")
    end

    Log("Korblox " .. side .. ": NO mesh available. Set a Manual Mesh ID in the UI.")
    return nil
end

-- Build one Korblox mesh piece as a plain Part + SpecialMesh using the REAL
-- mesh id/texture. This is what makes it look identical to Roblox's Korblox.
local function SpawnMeshPiece(meshId, textureId, sizeVec, name)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = (typeof(sizeVec) == "Vector3") and sizeVec or Vector3.new(1, 1, 1)
    p.CanCollide = false
    p.Massless = true
    p.Anchored = false
    p.Transparency = 0
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    pcall(function() p.LocalTransparencyModifier = 0 end)

    local sm = Instance.new("SpecialMesh")
    sm.MeshType = Enum.MeshType.FileMesh
    sm.MeshId = meshId
    if textureId and textureId ~= "" then sm.TextureId = textureId end
    sm.Scale = Vector3.new(1, 1, 1)
    sm.Parent = p

    return p
end

-- Weld a part to a target part at a given local offset.
local function WeldTo(targetPart, piece, localCF)
    piece.CFrame = targetPart.CFrame * (localCF or CFrame.new())
    local weld = Instance.new("WeldConstraint")
    weld.Name = "X0_Weld"
    weld.Part0 = targetPart
    weld.Part1 = piece
    weld.Parent = piece
end

--------------------------------------------------------------------------------
-- ACCESSORY ATTACH (unchanged - works well)
--------------------------------------------------------------------------------
local function AddAccessorySafe(model, assetId)
    local char = GetChar()
    local hum  = GetHumanoid()
    if not char or not hum then return false end

    local accessory = model
    if not (model:IsA("Accessory") or model:IsA("Accoutrement")) then
        accessory = model:FindFirstChildOfClass("Accessory") or model:FindFirstChildWhichIsA("Accoutrement")
        if not accessory then
            for _, d in ipairs(model:GetDescendants()) do
                if d:IsA("Accessory") or d:IsA("Accoutrement") then accessory = d; break end
            end
        end
    end
    if not accessory then return false end

    local acc = accessory:Clone()
    acc.Name = "X0_Acc_" .. tostring(assetId)

    local tag = Instance.new("BoolValue")
    tag.Name = "X0_Tag"
    tag.Parent = acc

    for _, v in ipairs(acc:GetDescendants()) do
        if v:IsA("Weld") or v:IsA("WeldConstraint") or v:IsA("ManualWeld") or v:IsA("Glue") or v:IsA("TouchTransmitter") then
            pcall(function() v:Destroy() end)
        end
    end

    local handle = acc:FindFirstChild("Handle")
    local attached = false

    if handle and handle:IsA("BasePart") then
        local att = handle:FindFirstChildOfClass("Attachment")
        local targetPart, targetAtt = nil, nil

        if att then
            for _, p in ipairs(char:GetChildren()) do
                if p:IsA("BasePart") then
                    local match = p:FindFirstChild(att.Name)
                    if match and match:IsA("Attachment") then targetPart = p; targetAtt = match; break end
                end
            end
        end

        if not targetAtt and att then
            local fb = R6_ATTACHMENT_FALLBACKS[att.Name]
            if fb then
                local pName = fb.part
                targetPart = char:FindFirstChild(pName)
                if not targetPart then
                    if pName == "Torso" then targetPart = char:FindFirstChild("UpperTorso") end
                    if pName == "Left Arm" then targetPart = char:FindFirstChild("LeftUpperArm") end
                    if pName == "Right Arm" then targetPart = char:FindFirstChild("RightUpperArm") end
                    if pName == "Left Leg" then targetPart = char:FindFirstChild("LeftUpperLeg") end
                    if pName == "Right Leg" then targetPart = char:FindFirstChild("RightUpperLeg") end
                end
                if targetPart then
                    targetAtt = targetPart:FindFirstChild(att.Name)
                    if not targetAtt then
                        targetAtt = Instance.new("Attachment")
                        targetAtt.Name = att.Name
                        targetAtt.CFrame = fb.cf
                        targetAtt.Parent = targetPart
                    end
                end
            end
        end

        if not targetPart then
            targetPart = char:FindFirstChild("Head") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
        end

        if targetPart then
            if targetAtt and att then
                handle.CFrame = targetAtt.WorldCFrame * att.CFrame:Inverse()
            else
                handle.CFrame = targetPart.CFrame
            end
            handle.CanCollide = false
            handle.Massless = true

            local weld = Instance.new("WeldConstraint")
            weld.Name = "X0_Weld"
            weld.Part0 = targetPart
            weld.Part1 = handle
            weld.Parent = handle
            attached = true
        end
    end

    if attached then
        acc.Parent = char
        TrackInstance(assetId, acc)
    end

    pcall(function() model:Destroy() end)
    return attached
end

--------------------------------------------------------------------------------
-- KORBLOX APPLY (the fixed part)
--------------------------------------------------------------------------------
local function ApplyKorbloxSide(side, enable)
    local char = GetChar()
    if not char then return false end

    -- Always drop the cached mesh so a new manual input / re-extract is used next time.
    _korbloxRealMesh[side] = nil

    local isR15Rig = IsR15()
    local r6LegName = (side == "Right") and "Right Leg" or "Left Leg"
    local r15LegNames = (side == "Right")
        and { "RightUpperLeg", "RightLowerLeg", "RightFoot" }
        or  { "LeftUpperLeg",  "LeftLowerLeg",  "LeftFoot" }

    -- always clean previous
    local oldFolder = char:FindFirstChild("X0_Korblox_Folder_" .. side)
    if oldFolder then pcall(function() oldFolder:Destroy() end) end

    -- restore hidden leg parts
    if isR15Rig then
        for _, name in ipairs(r15LegNames) do
            local part = char:FindFirstChild(name)
            if part and _korbloxBackup[part] then
                pcall(function()
                    part.Transparency = _korbloxBackup[part].Transparency
                    part.LocalTransparencyModifier = _korbloxBackup[part].Transparency
                end)
            end
        end
    else
        local r6Leg = char:FindFirstChild(r6LegName)
        if r6Leg and _korbloxBackup[r6Leg] then
            pcall(function()
                r6Leg.Transparency = _korbloxBackup[r6Leg].Transparency
                r6Leg.LocalTransparencyModifier = _korbloxBackup[r6Leg].Transparency
            end)
        end
    end

    if not enable then
        Log("Korblox " .. side .. " disabled")
        return true
    end

    -- get the REAL mesh from the asset
    local realMesh = EnsureRealKorbloxMesh(side)
    if not realMesh then
        Notif("Korblox Error", "Could not load real Korblox " .. side .. " asset", 4)
        return false
    end

    local folder = Instance.new("Folder")
    folder.Name = "X0_Korblox_Folder_" .. side
    folder.Parent = char

    if not isR15Rig then
        ---------------- R6 ----------------
        -- WORKING METHOD (confirmed in game):
        --   Weld a SpecialMesh Part at the LEG'S OWN size + CFrame, then hide
        --   the real leg. The mesh sits exactly where the leg was, so it joins
        --   the body at the hip (no long dangling leg, no floating torso).
        --   We only hide the real leg AFTER the mesh part is built, so the
        --   character is never left legless if something fails.
        local r6Leg = char:FindFirstChild(r6LegName)
        if not r6Leg or not r6Leg:IsA("BasePart") then
            Notif("Korblox Error", "Missing " .. r6LegName, 3)
            return false
        end

        local usedMeshPart = false
        local okB = pcall(function()
            local piece = Instance.new("Part")
            piece.Name = "X0_Korblox_" .. side .. "_R6"
            piece.Size = r6Leg.Size              -- exactly the leg's size
            piece.CanCollide = false
            piece.Massless = true
            piece.Anchored = false
            piece.Transparency = 0
            piece.TopSurface = Enum.SurfaceType.Smooth
            piece.BottomSurface = Enum.SurfaceType.Smooth

            local sm = Instance.new("SpecialMesh")
            sm.MeshType = Enum.MeshType.FileMesh
            sm.MeshId = realMesh.meshId
            if realMesh.textureId and realMesh.textureId ~= "" then sm.TextureId = realMesh.textureId end
            sm.Scale = Vector3.new(1, 1, 1)
            sm.Parent = piece

            -- weld at the leg's exact CFrame -> sits in the same spot, joined
            -- to the torso at the hip.
            piece.CFrame = r6Leg.CFrame
            local weld = Instance.new("WeldConstraint")
            weld.Name = "X0_Weld"
            weld.Part0 = r6Leg
            weld.Part1 = piece
            weld.Parent = piece
            piece.Parent = folder
            usedMeshPart = true
        end)
        Log("R6 SpecialMesh part " .. side .. " ok=" .. tostring(okB))

        -- hide the real leg now that the mesh part exists
        if usedMeshPart then
            if not _korbloxBackup[r6Leg] then
                _korbloxBackup[r6Leg] = { Transparency = r6Leg.Transparency }
            end
            r6Leg.Transparency = 1
            pcall(function() r6Leg.LocalTransparencyModifier = 1 end)
        end

        Log("Korblox " .. side .. " enabled (R6 meshPart=" .. tostring(usedMeshPart) .. ")")
        return usedMeshPart
    end

    ---------------- R15 ----------------
    -- SAME single-part method as R6 (no double legs!).
    -- We place ONE Korblox mesh over the whole right leg, sized to fill the
    -- leg (upper + lower + foot), welded at the hip so it joins the body.
    -- Then we hide the real R15 leg segments so there is no overlap.
    local upper = char:FindFirstChild(r15LegNames[1])   -- RightUpperLeg
    if not upper or not upper:IsA("BasePart") then
        Notif("Korblox Error", "Missing " .. tostring(r15LegNames[1]), 3)
        return false
    end

    -- figure out the full leg height so the single mesh covers the whole leg
    local totalY, originY = 0, upper.Position.Y
    local segs = {}
    for _, name in ipairs(r15LegNames) do
        local p = char:FindFirstChild(name)
        if p and p:IsA("BasePart") then
            segs[#segs+1] = p
            totalY = totalY + p.Size.Y
        end
    end
    if #segs == 0 then totalY = upper.Size.Y * 2 end

    local usedMeshPart = false
    local okR15 = pcall(function()
        local piece = Instance.new("Part")
        piece.Name = "X0_Korblox_" .. side .. "_R15"
        -- cover the whole leg: width/depth from the upper leg, height = full leg
        piece.Size = Vector3.new(upper.Size.X, totalY, upper.Size.Z)
        piece.CanCollide = false
        piece.Massless = true
        piece.Anchored = false
        piece.Transparency = 0
        piece.TopSurface = Enum.SurfaceType.Smooth
        piece.BottomSurface = Enum.SurfaceType.Smooth

        local sm = Instance.new("SpecialMesh")
        sm.MeshType = Enum.MeshType.FileMesh
        sm.MeshId = realMesh.meshId
        if realMesh.textureId and realMesh.textureId ~= "" then sm.TextureId = realMesh.textureId end
        sm.Scale = Vector3.new(1, 1, 1)
        sm.Parent = piece

        -- weld at the TOP of the leg (hip) so the mesh joins the body and hangs
        -- down exactly like a normal leg
        piece.CFrame = upper.CFrame * CFrame.new(0, -(totalY - upper.Size.Y) / 2, 0)
        local weld = Instance.new("WeldConstraint")
        weld.Name = "X0_Weld"
        weld.Part0 = upper
        weld.Part1 = piece
        weld.Parent = piece
        piece.Parent = folder
        usedMeshPart = true
    end)
    Log("R15 SpecialMesh part " .. side .. " ok=" .. tostring(okR15))

    -- hide every real leg segment now that the single mesh exists
    if usedMeshPart then
        for _, p in ipairs(segs) do
            if not _korbloxBackup[p] then
                _korbloxBackup[p] = { Transparency = p.Transparency }
            end
            p.Transparency = 1
            pcall(function() p.LocalTransparencyModifier = 1 end)
        end
    end

    Log("Korblox " .. side .. " enabled (R15 single mesh, h=" .. tostring(totalY) .. ")")
    return usedMeshPart
end

local function ApplyKorbloxRight(enable)
    State.KorbloxRight = enable
    return ApplyKorbloxSide("Right", enable)
end

local function ApplyKorbloxLeft(enable)
    State.KorbloxLeft = enable
    return ApplyKorbloxSide("Left", enable)
end

local function ReapplyKorblox()
    if State.KorbloxRight then ApplyKorbloxSide("Right", true) end
    if State.KorbloxLeft  then ApplyKorbloxSide("Left",  true) end
end

-- Nuke ANY stray X0 Korblox parts (folders/parts) anywhere in the character or
-- workspace leftovers - this clears the "black boxes" from broken attempts.
local function PurgeStrayKorblox()
    local char = GetChar()
    local function purge(container)
        if not container then return end
        for _, d in ipairs(container:GetDescendants()) do
            if d:IsA("BasePart") and (d.Name:match("^X0_Korblox") or d.Name:match("^X0_Acc_")) then
                pcall(function() d:Destroy() end)
            end
            if d:IsA("Folder") and d.Name:match("^X0_Korblox_Folder") then
                pcall(function() d:Destroy() end)
            end
        end
    end
    purge(char)
    -- also scan CurrentCamera-free workspace leftovers by name
    for _, d in ipairs(workspace:GetDescendants()) do
        if (d:IsA("BasePart") and d.Name:match("^X0_Korblox")) then
            pcall(function() d:Destroy() end)
        elseif d:IsA("Folder") and d.Name:match("^X0_Korblox_Folder") then
            pcall(function() d:Destroy() end)
        end
    end
end

--------------------------------------------------------------------------------
-- OTHER AVATAR OPERATIONS (unchanged)
--------------------------------------------------------------------------------
local function RestoreOriginalAvatar()
    local char = GetChar()

    if char then
        for _, child in ipairs(char:GetChildren()) do
            if child.Name:match("^X0_") or child:FindFirstChild("X0_Tag") then
                pcall(function() child:Destroy() end)
            end
        end
    end

    ApplyKorbloxSide("Right", false)
    ApplyKorbloxSide("Left", false)
    _korbloxBackup = {}
    PurgeStrayKorblox()

    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Transparency = 0
                pcall(function() part.LocalTransparencyModifier = 0 end)
            end
            if part:IsA("Decal") then part.Transparency = 0 end
        end
    end

    State.SavedIds = {}
    State.Instances = {}
    State.Headless = false
    State.KorbloxRight = false
    State.KorbloxLeft = false

    Log("Avatar restored")
end

function TrackInstance(assetId, inst)
    local key = tostring(assetId)
    if not State.Instances[key] then State.Instances[key] = {} end
    table.insert(State.Instances[key], inst)
end

function DestroyTracked(assetId)
    local key = tostring(assetId)
    local list = State.Instances[key]
    if list then
        for _, inst in ipairs(list) do pcall(function() inst:Destroy() end) end
        State.Instances[key] = nil
    end
end

function FindSaved(assetId)
    for i, entry in ipairs(State.SavedIds) do
        if entry.id == assetId then return i, entry end
    end
    return nil, nil
end

function AddSaved(assetId, name, assetType)
    if FindSaved(assetId) then return end
    table.insert(State.SavedIds, { id = assetId, name = name or tostring(assetId), type = assetType or "Unknown" })
end

function RemoveSaved(assetId)
    local idx = FindSaved(assetId)
    if idx then table.remove(State.SavedIds, idx) end
end

local function ApplyClothing(assetId, assetType)
    local char = GetChar()
    if not char then return false, "No character" end

    DestroyTracked(assetId)

    local className, propName
    if assetType == "Shirt" then className = "Shirt"; propName = "ShirtTemplate"
    elseif assetType == "Pants" then className = "Pants"; propName = "PantsTemplate"
    elseif assetType == "TShirt" then className = "ShirtGraphic"; propName = "Graphic"
    else return false, "Unknown clothing" end

    for _, c in ipairs(char:GetChildren()) do
        if c:IsA(className) then pcall(function() c:Destroy() end) end
    end

    local obj = Instance.new(className)
    obj.Name = "X0_" .. className
    obj[propName] = "rbxassetid://" .. tostring(assetId)
    obj.Parent = char
    TrackInstance(assetId, obj)
    return true
end

local function ApplyFace(assetId)
    local char = GetChar()
    if not char then return false, "No character" end
    local head = char:FindFirstChild("Head")
    if not head then return false, "No head" end

    DestroyTracked(assetId)

    local face = head:FindFirstChild("face") or head:FindFirstChildOfClass("Decal")
    if not face then
        face = Instance.new("Decal")
        face.Name = "face"
        face.Face = Enum.NormalId.Front
        face.Parent = head
    end
    face.Texture = "rbxassetid://" .. tostring(assetId)
    TrackInstance(assetId, face)
    return true
end

local function ApplyBodyPartDescription(assetId, assetType)
    local hum = GetHumanoid()
    if not hum then return false, "No humanoid" end
    local ok = pcall(function()
        local desc = hum:GetAppliedDescription()
        if assetType == "Head" then desc.Head = assetId
        elseif assetType == "Torso" then desc.Torso = assetId
        elseif assetType == "RightArm" then desc.RightArm = assetId
        elseif assetType == "LeftArm" then desc.LeftArm = assetId
        elseif assetType == "LeftLeg" then desc.LeftLeg = assetId
        elseif assetType == "RightLeg" then desc.RightLeg = assetId
        elseif assetType == "Face" then desc.Face = assetId end
        hum:ApplyDescription(desc)
    end)
    return ok
end

local function ApplyAccessoryViaDescription(assetId)
    local hum = GetHumanoid()
    if not hum then return false end
    local ok = pcall(function()
        local desc = hum:GetAppliedDescription()
        local accessories = desc:GetAccessories(true)
        for _, a in ipairs(accessories) do
            if a.AssetId == assetId then return end
        end
        table.insert(accessories, {
            AssetId = assetId,
            AccessoryType = Enum.AccessoryType.Unknown,
            IsLayered = false,
            Order = #accessories + 1,
            Puffiness = 0.5,
        })
        desc:SetAccessories(accessories, true)
        hum:ApplyDescription(desc)
    end)
    return ok
end

local function ApplyCatalogItem(rawInput, silent)
    local assetId = ParseId(rawInput)
    if not assetId then return false, "Invalid ID or URL" end
    if FindSaved(assetId) then return false, "Already applied (" .. assetId .. ")" end

    local info = GetAssetInfo(assetId)
    local assetName   = (info and info.Name) or tostring(assetId)
    local assetTypeId = (info and info.AssetTypeId) or 0
    local assetType   = ASSET_TYPE_MAP[assetTypeId] or "Unknown"

    Log("Applying " .. assetName .. " (" .. assetId .. ") type=" .. assetType)

    local ok, err = false, nil

    if assetType == "Shirt" or assetType == "Pants" or assetType == "TShirt" then
        ok, err = ApplyClothing(assetId, assetType)
    elseif assetType == "Face" then
        ok, err = ApplyFace(assetId)
    elseif assetType == "Head" or assetType == "Torso"
        or assetType == "RightArm" or assetType == "LeftArm"
        or assetType == "LeftLeg" or assetType == "RightLeg" then
        if IsR15() then
            ok = ApplyBodyPartDescription(assetId, assetType)
        else
            err = "Body part meshes not supported on R6 character"
        end
    else
        local model = LoadAssetModel(assetId)
        if model then
            ok = AddAccessorySafe(model, assetId)
            if not ok then err = "Could not attach accessory" end
        end
        if not ok and IsR15() then
            ok = ApplyAccessoryViaDescription(assetId)
            if ok then err = nil; Log("Applied via HumanoidDescription")
            else err = "LoadAsset failed and Description fallback failed" end
        end
    end

    if ok then
        AddSaved(assetId, assetName, assetType)
        return true, assetName .. " [" .. assetType .. "]"
    else
        return false, err or "Apply failed"
    end
end

local function RemoveItem(assetId)
    DestroyTracked(assetId)
    RemoveSaved(assetId)

    local hum = GetHumanoid()
    if hum and IsR15() then
        pcall(function()
            local desc = hum:GetAppliedDescription()
            local accs = desc:GetAccessories(true)
            local newAccs = {}
            for _, a in ipairs(accs) do
                if a.AssetId ~= assetId then table.insert(newAccs, a) end
            end
            desc:SetAccessories(newAccs, true)
            hum:ApplyDescription(desc)
        end)
    end
end

local function RemoveAllItems()
    for _, list in pairs(State.Instances) do
        for _, inst in ipairs(list) do pcall(function() inst:Destroy() end) end
    end
    State.Instances = {}

    local char = GetChar()
    if char then
        for _, c in ipairs(char:GetChildren()) do
            if c.Name:match("^X0_") then pcall(function() c:Destroy() end) end
        end
    end

    local ids = {}
    for _, entry in ipairs(State.SavedIds) do table.insert(ids, entry.id) end
    State.SavedIds = {}

    local hum = GetHumanoid()
    if hum and IsR15() then
        pcall(function()
            local desc = hum:GetAppliedDescription()
            local accs = desc:GetAccessories(true)
            local newAccs = {}
            for _, a in ipairs(accs) do
                local keep = true
                for _, rid in ipairs(ids) do
                    if a.AssetId == rid then keep = false; break end
                end
                if keep then table.insert(newAccs, a) end
            end
            desc:SetAccessories(newAccs, true)
            hum:ApplyDescription(desc)
        end)
    end
end

local function ForceReapplyAll()
    local char = GetChar()
    local hum  = GetHumanoid()
    if not char or not hum then Notif("Re-apply", "No character", 2); return end

    local snapshot = {}
    for _, entry in ipairs(State.SavedIds) do
        table.insert(snapshot, { id = entry.id })
    end

    for _, list in pairs(State.Instances) do
        for _, inst in ipairs(list) do pcall(function() inst:Destroy() end) end
    end
    State.Instances = {}
    State.SavedIds = {}

    local okCount = 0
    for _, item in ipairs(snapshot) do
        local ok = ApplyCatalogItem(tostring(item.id), true)
        if ok then okCount = okCount + 1 end
        task.wait(0.15)
    end

    ReapplyKorblox()
    if State.Headless then SetHeadless(true) end

    Notif("Re-apply", okCount .. " items | Korblox refreshed", 4)
end

local _headBackup = nil
local _faceBackup = {}

function SetHeadless(enable)
    local char = GetChar()
    if not char then return end
    local head = char:FindFirstChild("Head")
    if not head then return end

    if enable then
        if _headBackup == nil then _headBackup = head.Transparency end
        head.Transparency = 1
        pcall(function() head.LocalTransparencyModifier = 1 end)
        for _, d in ipairs(head:GetChildren()) do
            if d:IsA("Decal") then
                if _faceBackup[d] == nil then _faceBackup[d] = d.Transparency end
                d.Transparency = 1
            end
        end
    else
        if _headBackup ~= nil then
            head.Transparency = _headBackup
            pcall(function() head.LocalTransparencyModifier = _headBackup end)
        end
        for d, t in pairs(_faceBackup) do
            if d and d.Parent then d.Transparency = t end
        end
        _faceBackup = {}
        _headBackup = nil
    end
end

--------------------------------------------------------------------------------
-- FLOATING LOGO
--------------------------------------------------------------------------------
local FloatingLogo = {}

local function DestroyLogo()
    if State.LogoGui then pcall(function() State.LogoGui:Destroy() end) end
    local gp = GuiParent()
    if gp then
        for _, c in ipairs(gp:GetChildren()) do
            if c.Name == "Choco_Changer_Logo" then pcall(function() c:Destroy() end) end
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
    sg.Name = "Choco_Changer_Logo"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.DisplayOrder = 999999
    sg.Enabled = true
    local ok = pcall(function() sg.Parent = gp end)
    if not ok then
        pcall(function() sg.Parent = LocalPlayer:WaitForChild("PlayerGui", 5) end)
    end

    local size = State.LogoSize
    local img = Instance.new("ImageButton")
    img.Name = "Logo"
    img.Size = UDim2.new(0, size, 0, size)
    img.Position = UDim2.new(0, 20, 0, 100)
    img.BackgroundTransparency = 1
    img.BorderSizePixel = 0
    img.Image = TOOL.LogoId
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
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = i.Position; startPos = img.Position; dragMoved = false
        end
    end)

    img.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
                      or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            if d.Magnitude > 4 then dragMoved = true end
            img.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                     startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)

    img.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    img.MouseButton1Click:Connect(function()
        if dragMoved then return end
        pcall(function()
            local h = _G[TOOL_KEY]
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
    pcall(function() ContentProvider:PreloadAsync({TOOL.LogoId}) end)
end)

CM:Add(LocalPlayer.CharacterAdded, function()
    task.spawn(function()
        task.wait(1.0)

        local snapshot = {}
        for _, entry in ipairs(State.SavedIds) do
            table.insert(snapshot, entry.id)
        end
        State.SavedIds = {}
        State.Instances = {}

        for _, id in ipairs(snapshot) do
            ApplyCatalogItem(tostring(id), true)
            task.wait(0.15)
        end

        task.wait(0.2)
        ReapplyKorblox()
        if State.Headless then SetHeadless(true) end

        -- re-assert cinematic bars + graphics on respawn
        pcall(function()
            Camera = Workspace.CurrentCamera or Camera
            if State.Cinematic then
                Cinematic.BuildBars()
                Cinematic.ApplyFX(true)
                if Camera then Camera.FieldOfView = tonumber(State.CineFOV) or 70 end
            end
        end)
    end)
end)

--------------------------------------------------------------------------------
-- CINEMATIC MODE
--------------------------------------------------------------------------------
-- Letterbox bars + film look: depth of field, bloom, high-quality lighting,
-- adjustable FOV. Everything is backed up and restored on disable.
Cinematic = {}

local function GetCineTopBar()
    return State.CineBarTop
end

function Cinematic.BuildBars()
    Cinematic.DestroyBars()
    local gp = GuiParent()
    if not gp then return end

    local sg = Instance.new("ScreenGui")
    sg.Name = "X0_CineBars"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.DisplayOrder = 999998
    sg.Enabled = true
    local ok = pcall(function() sg.Parent = gp end)
    if not ok then pcall(function() sg.Parent = LocalPlayer:WaitForChild("PlayerGui", 5) end) end

    local top = Instance.new("Frame")
    top.Name = "TopBar"
    top.BackgroundColor3 = Color3.new(0, 0, 0)
    top.BorderSizePixel = 0
    top.Size = UDim2.new(1, 0, State.CineBarSize / 100, 0)
    top.Position = UDim2.new(0, 0, 0, 0)
    top.ZIndex = 100
    top.Parent = sg

    local bottom = top:Clone()
    bottom.Name = "BottomBar"
    bottom.Position = UDim2.new(0, 0, 1 - State.CineBarSize / 100, 0)
    bottom.Parent = sg

    State.CineBarsGui = sg
    State.CineBarTop = top
    State.CineBarBottom = bottom
end

function Cinematic.DestroyBars()
    if State.CineBarsGui then pcall(function() State.CineBarsGui:Destroy() end) end
    local gp = GuiParent()
    if gp then
        for _, c in ipairs(gp:GetChildren()) do
            if c.Name == "X0_CineBars" then pcall(function() c:Destroy() end) end
        end
    end
    State.CineBarsGui = nil
    State.CineBarTop = nil
    State.CineBarBottom = nil
end

function Cinematic.SetBarSize(pct)
    State.CineBarSize = tonumber(pct) or 12
    if State.CineBarTop then
        State.CineBarTop.Size = UDim2.new(1, 0, State.CineBarSize / 100, 0)
    end
    if State.CineBarBottom then
        State.CineBarBottom.Position = UDim2.new(0, 0, 1 - State.CineBarSize / 100, 0)
    end
end

function Cinematic.AddEffect(className, props, name)
    local e = Instance.new(className)
    e.Name = name or className
    for k, v in pairs(props or {}) do pcall(function() e[k] = v end) end
    e.Parent = Lighting
    return e
end

function Cinematic.ApplyFX(enable)
    -- remove stale ones first
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("PostEffect") and obj.Name:match("^X0Cine_") then
            obj.Enabled = enable
            if not enable then pcall(function() obj:Destroy() end) end
        end
    end
    if not enable then return end

    Cinematic.AddEffect("DepthOfFieldEffect", {
        Name = "X0Cine_DOF",
        FarIntensity = 0.15,
        FocusDistance = 40,
        InFocusRadius = 30,
        NearIntensity = 0.25,
        Enabled = State.CineDofEnabled,
    }, "X0Cine_DOF")

    Cinematic.AddEffect("BloomEffect", {
        Name = "X0Cine_Bloom",
        Intensity = 0.6,
        Size = 24,
        Threshold = 1.1,
        Enabled = true,
    }, "X0Cine_Bloom")

    Cinematic.AddEffect("SunRaysEffect", {
        Name = "X0Cine_SunRays",
        Intensity = 0.12,
        Spread = 0.8,
        Enabled = true,
    }, "X0Cine_SunRays")

    Cinematic.AddEffect("ColorCorrectionEffect", {
        Name = "X0Cine_CC",
        Brightness = 0.02,
        Contrast = 0.12,
        Saturation = 0.1,
        TintColor = Color3.fromRGB(255, 250, 245),
        Enabled = true,
    }, "X0Cine_CC")
end

function Cinematic.FullApply(enable)
    if enable then
        State.Cinematic = true
        Cinematic.BuildBars()
        Cinematic.ApplyFX(true)
        if Camera then Camera.FieldOfView = tonumber(State.CineFOV) or 70 end
        -- remember the visual baseline once
        if not State._lightBackup then
            State._lightBackup = {
                Ambient = Lighting.Ambient,
                OutdoorAmbient = Lighting.OutdoorAmbient,
                Brightness = Lighting.Brightness,
                ClockTime = Lighting.ClockTime,
                FogEnd = Lighting.FogEnd,
                FogStart = Lighting.FogStart,
                GlobalShadows = Lighting.GlobalShadows,
                EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
                EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
            }
        end
        pcall(function()
            Lighting.EnvironmentDiffuseScale = 0.5
            Lighting.EnvironmentSpecularScale = 0.5
            if not State.NoShadows then Lighting.GlobalShadows = true end
        end)
    else
        State.Cinematic = false
        Cinematic.DestroyBars()
        Cinematic.ApplyFX(false)
        if Camera then Camera.FieldOfView = tonumber(State.GraphicsFOV) or 70 end
    end
end

function Cinematic.SetFOV(fov)
    State.CineFOV = tonumber(fov) or 70
    if State.Cinematic and Camera then Camera.FieldOfView = State.CineFOV end
end

function Cinematic.SetDof(enable)
    State.CineDofEnabled = enable
    local e = Lighting:FindFirstChild("X0Cine_DOF")
    if e then e.Enabled = enable end
end

--------------------------------------------------------------------------------
-- GRAPHICS SETTINGS
--------------------------------------------------------------------------------
Graphics = {}

function Graphics.Backup()
    if State._lightBackup then return end
    State._lightBackup = {
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
        GlobalShadows = Lighting.GlobalShadows,
        EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
        EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
    }
end

function Graphics.RestoreLight()
    Graphics.Backup()
    for k, v in pairs(State._lightBackup) do
        pcall(function() Lighting[k] = v end)
    end
end

function Graphics.SetQuality(level)
    level = tonumber(level) or 0
    State.QualityLevel = level
    pcall(function()
        if level <= 0 then
            settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
        else
            level = math.clamp(math.floor(level), 1, 10)
            settings().Rendering.QualityLevel = Enum.QualityLevel["Level" .. string.format("%02d", level)]
        end
    end)
end

function Graphics.Fullbright(enable)
    State.Fullbright = enable
    Graphics.Backup()
    if enable then
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        Lighting.Brightness = 2
        Lighting.GlobalShadows = false
    else
        pcall(function()
            Lighting.Ambient = State._lightBackup.Ambient
            Lighting.OutdoorAmbient = State._lightBackup.OutdoorAmbient
            Lighting.Brightness = State._lightBackup.Brightness
            Lighting.GlobalShadows = State._lightBackup.GlobalShadows
        end)
    end
end

function Graphics.NoFog(enable)
    State.NoFog = enable
    Graphics.Backup()
    if enable then
        Lighting.FogEnd = 1e6
        Lighting.FogStart = 1e6
    else
        pcall(function()
            Lighting.FogEnd = State._lightBackup.FogEnd
            Lighting.FogStart = State._lightBackup.FogStart
        end)
    end
end

function Graphics.NoShadows(enable)
    State.NoShadows = enable
    Graphics.Backup()
    Lighting.GlobalShadows = not enable
end

function Graphics.NoBlur(enable)
    State.NoBlur = enable
    for _, v in ipairs(Lighting:GetDescendants()) do
        if not v.Name:match("^X0Cine_") then
            if v:IsA("BlurEffect") or v:IsA("DepthOfFieldEffect")
            or v:IsA("SunRaysEffect") or v:IsA("BloomEffect") then
                pcall(function() v.Enabled = not enable end)
            end
        end
    end
end

function Graphics.NoParticles(enable)
    State.NoParticles = enable
    for _, v in ipairs(Workspace:GetDescendants()) do
        if v:IsA("ParticleEmitter") or v:IsA("Fire")
        or v:IsA("Smoke") or v:IsA("Trail") or v:IsA("Sparkles") then
            pcall(function() v.Enabled = not enable end)
        end
    end
end

function Graphics.NoGrass(enable)
    State.NoGrass = enable
    pcall(function()
        for _, v in ipairs(Workspace:GetDescendants()) do
            if v:IsA("Decal") and (v.Name:lower():find("grass") or v.Name:lower():find("leaf")) then
                v.Transparency = enable and 1 or 0
            end
            if v:IsA("Texture") and (v.Name:lower():find("grass") or v.Name:lower():find("leaf")) then
                v.Transparency = enable and 1 or 0
            end
        end
    end)
end

function Graphics.SetFOV(fov)
    State.GraphicsFOV = tonumber(fov) or 70
    if not State.Cinematic and Camera then Camera.FieldOfView = State.GraphicsFOV end
end

function Graphics.SetClock(t)
    State.ClockTime = tonumber(t) or 14
    Graphics.Backup()
    pcall(function() Lighting.ClockTime = State.ClockTime end)
end

function Graphics.ResetAll()
    State.Fullbright = false
    State.NoFog = false
    State.NoShadows = false
    State.NoBlur = false
    State.NoParticles = false
    State.NoGrass = false
    pcall(Graphics.RestoreLight)
    pcall(function() Camera.FieldOfView = 70 end)
    for _, v in ipairs(Lighting:GetDescendants()) do
        if v:IsA("BlurEffect") or v:IsA("DepthOfFieldEffect")
        or v:IsA("SunRaysEffect") or v:IsA("BloomEffect") then
            if not v.Name:match("^X0Cine_") then pcall(function() v.Enabled = true end) end
        end
    end
    for _, v in ipairs(Workspace:GetDescendants()) do
        if v:IsA("ParticleEmitter") or v:IsA("Fire")
        or v:IsA("Smoke") or v:IsA("Trail") or v:IsA("Sparkles") then
            pcall(function() v.Enabled = true end)
        end
    end
end

function Graphics.ClearCineFX()
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj.Name:match("^X0Cine_") then pcall(function() obj:Destroy() end) end
    end
end

local function CleanupAll()
    pcall(RestoreOriginalAvatar)
    DestroyLogo()
    pcall(Cinematic.FullApply, false)
    pcall(Graphics.ClearCineFX)
    pcall(Graphics.RestoreLight)
    CM:Cleanup()
    Log("Unloaded - avatar restored")
end
--------------------------------------------------------------------------------
-- UI (WindUI)
--------------------------------------------------------------------------------
local BuildUI = function()
    local Window = WindUI:CreateWindow({
        Title  = TOOL.Name,
        Icon   = "rbxassetid://129308061683379",
        Author = "by Voixera",
        Folder = "ChocoChanger",
        Size   = UDim2.fromOffset(620, 520),
        Transparent = false,
        Acrylic = false,
        Theme  = "Dark",
        User = {
            Enabled = true,
            Anonymous = false,
        },
        HideSearchBar = true,
        ToggleKey = Enum.KeyCode.F8,
    })

    _G[TOOL_KEY] = { version = TOOL.Version, window = Window, destroy = CleanupAll }

    local Tabs = {
        Main     = Window:Tab({ Title = "Main",     Icon = "user-round" }),
        Settings = Window:Tab({ Title = "Settings", Icon = "settings" }),
        Cfg      = Window:Tab({ Title = "Config",   Icon = "file-cog" }),
    }

    ------------------------------------------------------------------------------
    -- MAIN TAB
    ------------------------------------------------------------------------------
    do
        local T = Tabs.Main

        local AboutSec = T:Section({ Title = "About" })
        AboutSec:Paragraph({
            Title = TOOL.Name .. " v" .. TOOL.Version,
            Desc  = "Full catalog avatar changer with real Korblox legs.",
        })
        AboutSec:Paragraph({
            Title = "Signed in as",
            Desc  = tostring(LocalPlayer.DisplayName) .. " (@" .. tostring(LocalPlayer.Name) .. ")",
        })

        local CatalogSec = T:Section({ Title = "Catalog Item Loader" })
        local inputValue = ""

        CatalogSec:Input({
            Title       = "Catalog URL / Asset ID",
            Placeholder = "URL or ID...",
            Value       = "",
            Callback    = function(v) inputValue = v end,
        })
        CatalogSec:Space()

        CatalogSec:Button({
            Title = "Apply Item",
            Icon  = "download",
            Callback = function()
                if inputValue == "" then Notif("Error", "Enter a URL or ID first", 3); return end
                Notif("Loading", "Fetching asset...", 2)
                task.spawn(function()
                    local ok, msg = ApplyCatalogItem(inputValue)
                    if ok then Notif("Applied", msg, 3) else Notif("Failed", tostring(msg), 4) end
                end)
            end,
        })
        CatalogSec:Space()

        CatalogSec:Button({
            Title = "Remove Last Parsed ID",
            Icon  = "minus",
            Callback = function()
                local id = ParseId(inputValue)
                if not id then Notif("Error", "No valid ID in input", 3); return end
                if FindSaved(id) then
                    RemoveItem(id)
                    Notif("Removed", "Asset " .. id, 2)
                else
                    Notif("Error", "That ID is not applied", 3)
                end
            end,
        })
        CatalogSec:Space()

        CatalogSec:Button({
            Title = "Remove All Applied Items",
            Icon  = "trash-2",
            Callback = function()
                RemoveAllItems()
                Notif("Cleared", "All catalog items removed", 2)
            end,
        })
        CatalogSec:Space()

        CatalogSec:Button({
            Title = "List Applied Items",
            Icon  = "list",
            Callback = function()
                local count = #State.SavedIds
                for _, entry in ipairs(State.SavedIds) do
                    print("[Choco Changer] " .. entry.name .. " | " .. entry.type .. " | " .. entry.id)
                end
                Notif("Applied", count .. " item(s)  (see console F9)", 3)
            end,
        })

        local HeadSec = T:Section({ Title = "Head" })
        HeadSec:Toggle({
            Title = "Headless Head",
            Value = false,
            Callback = function(v)
                State.Headless = v
                SetHeadless(v)
            end,
        })

        local KorSec = T:Section({ Title = "Korblox (Real Deathspeaker Meshes)" })
        KorSec:Toggle({
            Title = "Korblox Right Leg",
            Value = false,
            Callback = function(v)
                local ok = ApplyKorbloxRight(v)
                if v and ok then Notif("Korblox", "Right leg on", 2)
                elseif not v then Notif("Korblox", "Right leg off", 2) end
            end,
        })
        KorSec:Space()
        KorSec:Toggle({
            Title = "Korblox Left Leg",
            Value = false,
            Callback = function(v)
                local ok = ApplyKorbloxLeft(v)
                if v and ok then Notif("Korblox", "Left leg on", 2)
                elseif not v then Notif("Korblox", "Left leg off", 2) end
            end,
        })
        KorSec:Space()
        KorSec:Button({
            Title = "Korblox Both Legs",
            Icon  = "footprints",
            Callback = function()
                ApplyKorbloxRight(true)
                ApplyKorbloxLeft(true)
                Notif("Korblox", "Both legs on", 2)
            end,
        })
        KorSec:Space()
        KorSec:Button({
            Title = "Remove Korblox Legs",
            Icon  = "eraser",
            Callback = function()
                ApplyKorbloxRight(false)
                ApplyKorbloxLeft(false)
                PurgeStrayKorblox()
                Notif("Korblox", "Legs restored", 2)
            end,
        })
        KorSec:Space()
        KorSec:Input({
            Title       = "Manual Right Mesh ID",
            Placeholder = "rbxassetid://... or id",
            Value       = "",
            Callback    = function(v) State.ManualMeshRight = v end,
        })
        KorSec:Space()
        KorSec:Input({
            Title       = "Manual Right Texture ID",
            Placeholder = "optional",
            Value       = "",
            Callback    = function(v) State.ManualTexRight = v end,
        })
        KorSec:Space()
        KorSec:Input({
            Title       = "Manual Left Mesh ID",
            Placeholder = "rbxassetid://... or id",
            Value       = "",
            Callback    = function(v) State.ManualMeshLeft = v end,
        })
        KorSec:Space()
        KorSec:Input({
            Title       = "Manual Left Texture ID",
            Placeholder = "optional",
            Value       = "",
            Callback    = function(v) State.ManualTexLeft = v end,
        })
        KorSec:Space()
        KorSec:Button({
            Title = "Re-apply Korblox (use manual ids)",
            Icon  = "refresh-cw",
            Callback = function()
                -- normalize "12345" -> "rbxassetid://12345"
                local function norm(s)
                    if not s or s == "" then return "" end
                    if s:find("rbxassetid://") or s:find("asset/?id=") then return s end
                    local n = s:match("(%d+)")
                    return n and ("rbxassetid://" .. n) or s
                end
                State.ManualMeshRight = norm(State.ManualMeshRight)
                State.ManualTexRight  = norm(State.ManualTexRight)
                State.ManualMeshLeft  = norm(State.ManualMeshLeft)
                State.ManualTexLeft   = norm(State.ManualTexLeft)
                if State.KorbloxRight then ApplyKorbloxSide("Right", true) end
                if State.KorbloxLeft  then ApplyKorbloxSide("Left", true) end
                if not State.KorbloxRight and not State.KorbloxLeft then
                    ApplyKorbloxSide("Right", true)
                end
                Notif("Korblox", "Re-applied with manual ids", 2)
            end,
        })
        KorSec:Space()
        KorSec:Button({
            Title = "Debug: Dump Real Korblox Mesh IDs",
            Icon  = "bug",
            Callback = function()
                task.spawn(function()
                    for _, side in ipairs({ "Right", "Left" }) do
                        local info = EnsureRealKorbloxMesh(side)
                        if info then
                            Log(side .. " meshId=" .. tostring(info.meshId) .. " texId=" .. tostring(info.textureId) .. " pieces=" .. #info.pieces)
                            for i, pc in ipairs(info.pieces) do
                                Log("   piece " .. i .. ": name=" .. tostring(pc.partName) .. " mesh=" .. tostring(pc.meshId) .. " tex=" .. tostring(pc.textureId))
                            end
                            -- copy-paste-ready block
                            local _ = (pcall(function()
                                local lines = { side .. " = {",
                                    '  meshId = "' .. tostring(info.meshId) .. '",',
                                    '  textureId = "' .. tostring(info.textureId) .. '",',
                                    "  pieces = {" }
                                for _, pc in ipairs(info.pieces) do
                                    table.insert(lines, '    { name="' .. tostring(pc.partName) .. '", mesh="' .. tostring(pc.meshId) .. '", tex="' .. tostring(pc.textureId) .. '" },')
                                end
                                table.insert(lines, "  },")
                                table.insert(lines, "},")
                                Log("--- PASTE THIS TO VOIXERA ---")
                                Log(table.concat(lines, "\n"))
                                Log("--- END ---")
                            end))
                        else
                            Log(side .. " -> COULD NOT LOAD (InsertService may be blocked)")
                        end
                    end
                end)
                Notif("Debug", "Dumping to console (F9)", 3)
            end,
        })

        local CharSec = T:Section({ Title = "Character" })
        CharSec:Button({
            Title = "Strip All Character Accessories",
            Icon  = "shirt",
            Callback = function()
                local char = GetChar()
                if not char then return end
                for _, child in ipairs(char:GetChildren()) do
                    if child:IsA("Accessory") or child:IsA("Accoutrement") then
                        pcall(function() child:Destroy() end)
                    end
                end
                Notif("Stripped", "Character accessories removed", 2)
            end,
        })
        CharSec:Space()
        CharSec:Button({
            Title = "Force Re-apply All",
            Icon  = "rotate-cw",
            Callback = function() task.spawn(ForceReapplyAll) end,
        })
        CharSec:Space()
        CharSec:Button({
            Title = "Restore Original Avatar",
            Icon  = "undo-2",
            Callback = function()
                RestoreOriginalAvatar()
                Notif("Restored", "Original avatar restored", 3)
            end,
        })
    end

    ------------------------------------------------------------------------------
    -- CINEMATIC (section of Main)
    ------------------------------------------------------------------------------
    do
        local T = Tabs.Main

        local CineSec = T:Section({ Title = "Cinematic Mode" })
        CineSec:Toggle({
            Title = "Enable Cinematic",
            Desc  = "Letterbox bars + film look (DOF, Bloom, SunRays, color grade)",
            Value = false,
            Callback = function(v)
                Cinematic.FullApply(v)
                Notif("Cinematic", v and "Enabled" or "Disabled", 2)
            end,
        })
        CineSec:Space()
        CineSec:Slider({
            Title = "Letterbox Bar Size %",
            Desc  = "Height of the top/bottom black bars",
            Step  = 1,
            Value = { Min = 0, Max = 25, Default = 12 },
            Callback = function(v) Cinematic.SetBarSize(v) end,
        })
        CineSec:Space()
        CineSec:Slider({
            Title = "Cinematic FOV",
            Desc  = "Camera field of view while cinematic is on",
            Step  = 1,
            Value = { Min = 30, Max = 120, Default = 70 },
            Callback = function(v) Cinematic.SetFOV(v) end,
        })
        CineSec:Space()
        CineSec:Toggle({
            Title = "Depth of Field",
            Desc  = "Blur far/near objects for a movie look",
            Value = true,
            Callback = function(v) Cinematic.SetDof(v) end,
        })
    end

    ------------------------------------------------------------------------------
    -- GRAPHICS (section of Main)
    ------------------------------------------------------------------------------
    do
        local T = Tabs.Main

        local VisSec = T:Section({ Title = "Graphics" })
        VisSec:Toggle({
            Title = "No Fog",
            Value = false,
            Callback = function(v) Graphics.NoFog(v) end,
        })
        VisSec:Space()
        VisSec:Slider({
            Title = "Time of Day",
            Desc  = "Lighting.ClockTime (0-24)",
            Step  = 1,
            Value = { Min = 0, Max = 24, Default = 14 },
            Callback = function(v) Graphics.SetClock(v) end,
        })
    end

    ------------------------------------------------------------------------------
    -- INFO / CHANGELOG (section of Settings)
    ------------------------------------------------------------------------------
    do
        local T = Tabs.Settings

        local HowSec = T:Section({ Title = "How To Use" })

        HowSec:Paragraph({
            Title = "Catalog Item Loader",
            Desc  = "Paste a catalog URL or asset ID, then press Apply Item.\nExample: https://www.roblox.com/catalog/89728916471078/Black-Plaid-Scarf",
        })
        HowSec:Space()
        HowSec:Paragraph({
            Title = "Korblox Legs - R6 & R15",
            Desc  = "Uses the REAL Roblox Korblox Deathspeaker assets live:\n  Right: 139607718   Left: 139607673\nThe actual mesh is extracted at runtime and scaled to the leg so it fits the body (no long dangling leg). Works on R6 and R15.",
        })
        HowSec:Space()
        HowSec:Paragraph({
            Title = "Debug: Dump Real Korblox Mesh IDs",
            Desc  = "Press it, then open the console (F9). It prints the real mesh id + texture id + a copy-paste block. Send that block to Voixera so it can be hardcoded (works even if the map blocks InsertService).",
        })
        HowSec:Space()
        HowSec:Paragraph({
            Title = "Headless Head",
            Desc  = "Hides the head + face decals on your character.",
        })
        HowSec:Space()
        HowSec:Paragraph({
            Title = "Force Re-apply All",
            Desc  = "Reloads every saved catalog item, plus Korblox and Headless.",
        })
        HowSec:Space()
        HowSec:Paragraph({
            Title = "Floating Logo",
            Desc  = "No background frame. Drag to move. Click to toggle the hub.",
        })

        local ClSec = T:Section({ Title = "Changelog" })
        ClSec:Paragraph({
            Title = "v1.00",
            Desc  = "Choco Changer release. Full catalog loader, real Korblox legs, Headless, Cinematic + Graphics sections, floating logo, sidebar profile (Anonymous mode) and Config manager.",
        })
        ClSec:Space()
        ClSec:Paragraph({
            Title = "Notes",
            Desc  = "Tabs: Main (catalog / korblox / head / cinematic / graphics), Settings (appearance, profile, logo, unload), Config (save / load).",
        })
    end

    ------------------------------------------------------------------------------
    -- SETTINGS TAB
    ------------------------------------------------------------------------------
    do
        local T = Tabs.Settings

        local LookSec = T:Section({ Title = "UI Appearance" })

        LookSec:Dropdown({
            Title  = "Theme",
            Desc   = "WindUI color theme",
            Values = {
                "Dark", "Light", "Rose", "Plant", "Red", "Indigo", "Sky",
                "Violet", "Amber", "Emerald", "Midnight", "Crimson",
                "MonokaiPro", "CottonCandy", "Mellowsi", "Rainbow",
            },
            Value  = "Dark",
            Callback = function(value)
                local ok = pcall(function() WindUI:SetTheme(value) end)
                if ok then Notif("Theme", "Set to " .. tostring(value), 2)
                else Notif("Theme", "Failed to set " .. tostring(value), 3) end
            end,
        })
        LookSec:Space()

        LookSec:Toggle({
            Title = "Solid Window Background",
            Desc  = "Show a solid (non-transparent) window panel",
            Value = true,
            Callback = function(v)
                pcall(function() Window:SetPanelBackground(v) end)
            end,
        })

        local ProfSec = T:Section({ Title = "Profile Card" })
        ProfSec:Paragraph({
            Title = "Sidebar Profile",
            Desc  = "Your avatar, display name and username show at the bottom of the sidebar.",
        })
        ProfSec:Toggle({
            Title = "Anonymous Mode",
            Value = false,
            Callback = function(v)
                pcall(function() Window.User:SetAnonymous(v) end)
            end,
        })

        local LogoSec = T:Section({ Title = "Floating Logo" })

        LogoSec:Toggle({
            Title = "Show Logo",
            Value = true,
            Callback = function(v)
                FloatingLogo.SetVisible(v)
            end,
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
                Notif("Logo", "Rebuilt", 2)
            end,
        })

        local UnSec = T:Section({ Title = "Script" })
        UnSec:Button({
            Title = "Unload Script",
            Desc  = "Restore original avatar and close hub",
            Icon  = "power",
            Callback = function()
                CleanupAll()
                _G[TOOL_KEY] = nil
                pcall(function() Window:Destroy() end)
            end,
        })
    end

    ------------------------------------------------------------------------------
    -- CONFIG MANAGER (WindUI built-in)
    ------------------------------------------------------------------------------
    do
        local T = Tabs.Cfg
        local ConfigSec = T:Section({ Title = "Configs" })

        local ConfigManager = Window.ConfigManager
        local ConfigName = "default"

        local input = ConfigSec:Input({
            Title = "Config Name",
            Icon  = "file-cog",
            Value = "default",
            Callback = function(value)
                ConfigName = value
            end,
        })
        ConfigSec:Space()

        local AllConfigs = {}
        pcall(function() AllConfigs = ConfigManager:AllConfigs() or {} end)
        local DefaultValue = table.find(AllConfigs, ConfigName) and ConfigName or nil

        local dd = ConfigSec:Dropdown({
            Title  = "All Configs",
            Desc   = "Select existing configs",
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
                    Notif("Config", "Saved '" .. tostring(ConfigName) .. "'", 3)
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
                    Notif("Config", "Loaded '" .. tostring(ConfigName) .. "'", 3)
                end
            end,
        })
        ConfigSec:Space()
        ConfigSec:Button({
            Title = "Refresh Config List",
            Icon  = "refresh-cw",
            Callback = function()
                pcall(function() dd:Refresh(ConfigManager:AllConfigs() or {}) end)
                Notif("Config", "Config list refreshed", 2)
            end,
        })
    end

    return Window
end

local Window = BuildUI()

task.spawn(function()
    task.wait(0.5)
    if State.FloatingLogo then
        local ok = FloatingLogo.Build()
        if not ok then
            for _ = 1, 3 do
                task.wait(1)
                if FloatingLogo.Build() then break end
            end
        end
    end
    while task.wait(5) do
        if State.FloatingLogo and not (State.LogoGui and State.LogoGui.Parent) then
            FloatingLogo.Build()
        end
    end
end)

Notif(TOOL.Name, "v" .. TOOL.Version .. " loaded", 4)
Log(HUB and HUB.Name or TOOL.Name .. " v" .. TOOL.Version .. " ready (WindUI)")
