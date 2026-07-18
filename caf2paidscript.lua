----------------------------------------------------------------------
-- bypass.lua — FIRST executable code (no WaitForChild on hot path)
-- made by @j7l - sai / owned by xanax
-- Owns GET_2 clean handshake so CreditsHandler cannot return 99999 → 267.
----------------------------------------------------------------------
do
    local getgenv = getgenv or function() return _G end
    local genv = getgenv()
    genv.__CAF2_BOOT = "bypass-start"

    local Players = game:GetService("Players")
    local RS = game:GetService("ReplicatedStorage")
    local CP = game:GetService("ContentProvider")
    local ncc = (typeof(newcclosure) == "function") and newcclosure or function(f) return f end

    local BAIT = {
        [123270741994898] = true, [103147620865081] = true, [116048588333795] = true,
        [83640716223541] = true, [72579423244522] = true, [10734950309] = true,
        [12977615774] = true, [18245826428] = true, [116204929609664] = true,
        [128155293790451] = true, [95816097006870] = true, [4996891970] = true,
        [70449495580650] = true, [1204397029] = true, [529659138] = true,
        [108952102602834] = true, [11520996670] = true, [11444348176] = true,
        [115346308182122] = true, [5642383285] = true, [4702850565] = true,
        [100148515061030] = true, [16898613699] = true, [85888499115674] = true,
        [132968326823931] = true, [127464789357538] = true, [3926305904] = true,
    }

    local function assetNum(id)
        local n = tostring(id or ""):match("(%d+)")
        return n and tonumber(n) or nil
    end

    local function cleanHandshake(seed)
        seed = tonumber(seed) or 0
        local v15 = bit32.bxor(1, seed * 2654435761 % 4294967296) % 4294967296
        local v16 = bit32.lrotate(v15, seed % 17 + 3)
        local v17 = bit32.bxor(v16, 33554432)
        return bit32.bxor(v17, (1 * seed + 9301) % 4294967296) % 65535 + 1
    end

    if typeof(genv.__CAF2_HS_FN) ~= "function" then
        genv.__CAF2_HS_FN = ncc(function(seed)
            local res = cleanHandshake(seed)
            genv.__CAF2_LAST_HS = { seed = seed, t = os.clock(), res = res }
            genv.__CAF2_HS_COUNT = (genv.__CAF2_HS_COUNT or 0) + 1
            return res
        end)
    end

    -- Non-yielding only — WaitForChild is deferred so hooks install immediately.
    local function armGet2()
        local remotes = RS:FindFirstChild("Remotes")
        if not remotes then return false end
        local GET_2 = remotes:FindFirstChild("GET_2")
        if not GET_2 then return false end
        GET_2.OnClientInvoke = genv.__CAF2_HS_FN
        genv.__CAF2_GET2_HOOKED = true
        return true
    end

    local function neuterCredits()
        local lp = Players.LocalPlayer
        if lp then
            local ps = lp:FindFirstChild("PlayerScripts")
            local ch = ps and ps:FindFirstChild("CreditsHandler")
            if ch and (ch:IsA("LocalScript") or ch:IsA("Script")) then
                pcall(function() ch.Disabled = true end)
            end
        end
        if typeof(getconnections) ~= "function" then return end
        pcall(function()
            for _, c in ipairs(getconnections(game:GetService("LogService").MessageOut)) do
                local src = ""
                pcall(function()
                    src = tostring(debug.info(c.Function, "s") or "")
                end)
                if src:find("CreditsHandler") then
                    pcall(function() c:Disable() end)
                end
            end
        end)
    end

    local function hookTouchedQuests()
        if genv.__CAF2_TQ_HARD then return end
        local remotes = RS:FindFirstChild("Remotes")
        local TQ = remotes and remotes:FindFirstChild("TouchedQuests")
        if not (TQ and typeof(hookfunction) == "function") then return end
        local old
        old = hookfunction(TQ.FireServer, ncc(function(self, ...)
            local a1 = tostring(({ ... })[1] or ""):lower()
            if a1:find("pokemon") or a1:find("cornball") or a1:find("lyzn") or a1:find("weird") then
                genv.__CAF2_BLOCKED_SNITCH = (genv.__CAF2_BLOCKED_SNITCH or 0) + 1
                return nil
            end
            return old(self, ...)
        end))
        genv.__CAF2_TQ_HARD = true
    end

    local function hookPlayerSnitches()
        if genv.__CAF2_PLAYER_SNITCH_HOOKED then return end
        local remotes = RS:FindFirstChild("Remotes")
        local PR = remotes and remotes:FindFirstChild("Player")
        if not (PR and typeof(hookfunction) == "function") then return end
        local old
        old = hookfunction(PR.FireServer, ncc(function(self, ...)
            local a1 = tostring(({ ... })[1] or ""):lower()
            -- These are AC reports → Error 267 ("Hitbox Expander" / fly detect).
            if a1 == "hitbox expander" or a1 == "flying"
                or a1:find("hitbox") or a1:find("expander") then
                genv.__CAF2_BLOCKED_SNITCH = (genv.__CAF2_BLOCKED_SNITCH or 0) + 1
                return nil
            end
            return old(self, ...)
        end))
        genv.__CAF2_PLAYER_SNITCH_HOOKED = true
    end

    -- 1) Own handshake + neuter AC BEFORE suite / before any yield
    pcall(armGet2)
    pcall(neuterCredits)

    -- 2) Sync hooks (still no WaitForChild)
    if not genv.__CAF2_BAIT_HOOKED then
        pcall(function()
            local old
            old = hookfunction(CP.GetAssetFetchStatus, ncc(function(self, id)
                local n = assetNum(id)
                if n and BAIT[n] then
                    return Enum.AssetFetchStatus.None
                end
                return old(self, id)
            end))
            genv.__CAF2_BAIT_HOOKED = true
        end)
    end
    pcall(hookTouchedQuests)
    pcall(hookPlayerSnitches)

    if not genv._J7L_BYPASS_LOADED then
        genv._J7L_BYPASS_LOADED = true
        print("bypass made by @j7l - sai")
        print("owned by xanax")
        print("[CAF2] GET_2 LOCKED stable callback — kick path sealed")

        pcall(function()
            local oldKick
            oldKick = hookfunction(Instance.new("Player").Kick, ncc(function(self, ...)
                if checkcaller() then return oldKick(self, ...) end
                if self == Players.LocalPlayer then return nil end
                return oldKick(self, ...)
            end))
        end)

        pcall(function()
            if getconnections then
                for _, c in ipairs(getconnections(game:GetService("ScriptContext").Error)) do
                    pcall(function() c:Disable() end)
                end
            end
        end)
    else
        print("[CAF2] GET_2 killswitch re-armed")
    end

    -- ONE cheap __namecall hook. Old builds lowercased + string.find'd EVERY Instance
    -- call (FindFirstChild, etc.) → severe FPS hitching. Rejoin once if you still lag
    -- after this update (stacked old hooks can't be removed mid-session).
    -- V5: Hands/Unguard ALWAYS swallowed while Kill Aura is on (Hands was still
    -- reaching the server → Guarding tag stayed, but Head did 0 damage).
    if not genv.__CAF2_NC_V5 then
        genv.__CAF2_NC_V5 = true
        pcall(function()
            local oldNamecall
            oldNamecall = hookmetamethod(game, "__namecall", ncc(function(self, ...)
                local method = getnamecallmethod()
                if method == "FireServer" or method == "fireServer" then
                    if typeof(self) == "Instance" and self.Name == "Combat" then
                        local a1 = ...
                        if a1 == "Hands" or a1 == "Unguard" then
                            local st = genv.CAF2
                            if st and st.S and (st.S.killAura or st.S.ragdollAura) then
                                return
                            end
                        end
                        if a1 == "Block" and not checkcaller() then
                            local st = genv.CAF2
                            if st and st.S and st.S.killAura then
                                return
                            end
                        end
                    end
                end
                if checkcaller() then return oldNamecall(self, ...) end
                if method == "Kick" or method == "kick" then
                    if self == Players.LocalPlayer then return nil end
                    return oldNamecall(self, ...)
                end
                if method == "FireServer" or method == "fireServer" then
                    if typeof(self) == "Instance" then
                        local n = self.Name
                        if n == "Player" then
                            local a1 = ...
                            if a1 == "Hitbox Expander" or a1 == "Flying"
                                or a1 == "hitbox expander" or a1 == "flying" then
                                return nil
                            end
                        elseif n == "TouchedQuests" then
                            local a1 = ...
                            if type(a1) == "string" then
                                local l = a1:lower()
                                if l:find("pokemon", 1, true) or l:find("lyzn", 1, true)
                                    or l:find("cornball", 1, true) or l:find("weird", 1, true) then
                                    return nil
                                end
                            end
                        end
                    end
                end
                return oldNamecall(self, ...)
            end))
        end)
    end

    -- 3) Deferred wait/re-arm (does not block suite load)
    if not genv.__CAF2_HS_GUARD then
        genv.__CAF2_HS_GUARD = true
        task.spawn(function()
            if not genv.__CAF2_GET2_HOOKED then
                local remotes = RS:FindFirstChild("Remotes") or RS:WaitForChild("Remotes", 30)
                if remotes and not remotes:FindFirstChild("GET_2") then
                    remotes:WaitForChild("GET_2", 30)
                end
            end
            pcall(armGet2)
            pcall(neuterCredits)
            pcall(hookTouchedQuests)
            pcall(hookPlayerSnitches)
            -- Short seal window, then rare re-arm (was: 40×0.25s neuter + every 1s forever).
            for _ = 1, 6 do
                task.wait(0.5)
                pcall(armGet2)
            end
            pcall(neuterCredits)
            while task.wait(8) do
                pcall(armGet2)
            end
        end)
    end

    if Players.LocalPlayer and not genv.__CAF2_CHAR_HS then
        genv.__CAF2_CHAR_HS = true
        Players.LocalPlayer.CharacterAdded:Connect(function()
            task.defer(function()
                pcall(armGet2)
                pcall(neuterCredits)
            end)
        end)
    end

    genv.__CAF2_BOOT = "bypass-done"
end

----------------------------------------------------------------------
-- Services / locals
----------------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local Workspace        = workspace
local CollectionService = game:GetService("CollectionService")
local LP   = Players.LocalPlayer
local Cam  = Workspace.CurrentCamera
local S
-- Exposed for live MCP probes / re-exec (chunk locals are otherwise invisible).
local function publishState()
    local genv = (typeof(getgenv) == "function" and getgenv()) or _G
    genv.CAF2 = genv.CAF2 or {}
    genv.CAF2.S = S
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local Combat  = Remotes and Remotes:WaitForChild("Combat", 10)
if not Combat then warn("[CAF2] Combat remote not found"); return end
do
    local g = (typeof(getgenv) == "function" and getgenv()) or _G
    g.__CAF2_BOOT = "combat-ok"
end
-- cloneref bypasses any leftover FireServer hooks from older executes (a Hands-swallow
-- hook once broke varargs and made Head do 0 damage while still "firing" client-side).
pcall(function()
    if typeof(cloneref) == "function" then
        Combat = cloneref(Combat)
    end
end)

local LOGO_PATH = "C:/Users/jake/Downloads/logo.png"
local LOGO_ASSET = nil
pcall(function()
	if typeof(getcustomasset) == "function" and typeof(isfile) == "function" then
		if isfile(LOGO_PATH) then
			LOGO_ASSET = getcustomasset(LOGO_PATH)
		end
	end
end)



----------------------------------------------------------------------
-- Key system removed - Premium always active
----------------------------------------------------------------------
local premiumUnlocked = true

-- persistent global so re-execution unloads the old instance instead of stacking
local genv = (typeof(getgenv) == "function" and getgenv()) or _G
if genv.__CAF2_SUITE and genv.__CAF2_SUITE.Unload then pcall(genv.__CAF2_SUITE.Unload) end
for _, root in ipairs({ (typeof(gethui) == "function" and gethui()) or nil, LP:FindFirstChild("PlayerGui") }) do
    if root then
        for _, g in ipairs(root:GetChildren()) do
            if (g.Name:match("^CAF2_Suite") or g.Name:match("^CAF2_Loader") or g.Name == "CAF2_ESP" or g.Name == "CAF2_KeyGate" or g.Name == "CAF2HubPremium" or g.Name == "CAF2Hub") then
                pcall(function() g:Destroy() end)
            end
        end
    end
end
local MY_SESSION = (genv.__CAF2_SESSION or 0) + 1
genv.__CAF2_SESSION = MY_SESSION
local function isCurrent() return genv.__CAF2_SESSION == MY_SESSION end

-- Always unlock camera on (re)load — never leave Scriptable/LockCenter from a prior session.
pcall(function()
    local UIS = game:GetService("UserInputService")
    local cam = workspace.CurrentCamera
    LP.CameraMode = Enum.CameraMode.Classic
    LP.CameraMinZoomDistance = 0.5
    LP.CameraMaxZoomDistance = 128
    UIS.MouseBehavior = Enum.MouseBehavior.Default
    UIS.MouseIconEnabled = true
    if cam then
        cam.CameraType = Enum.CameraType.Custom
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then cam.CameraSubject = hum end
        if cam.FieldOfView < 50 or cam.FieldOfView > 120 then cam.FieldOfView = 70 end
    end
end)

----------------------------------------------------------------------
-- Maid
----------------------------------------------------------------------
local Maid = { conns = {}, insts = {} }
function Maid:Give(c)     table.insert(self.conns, c); return c end
function Maid:GiveInst(i) table.insert(self.insts, i); return i end
function Maid:Clean()
    for _, c in ipairs(self.conns) do pcall(function() c:Disconnect() end) end
    for _, i in ipairs(self.insts) do pcall(function() i:Destroy() end) end
    self.conns, self.insts = {}, {}
end

----------------------------------------------------------------------
-- Theme (charcoal glass — crimson only as sparse accents)
----------------------------------------------------------------------
local Theme = {
    Bg      = Color3.fromRGB(14, 14, 16),
    Panel   = Color3.fromRGB(28, 28, 32),
    Panel2  = Color3.fromRGB(40, 40, 46),
    Sidebar = Color3.fromRGB(22, 22, 26),
    Card    = Color3.fromRGB(32, 32, 36),
    CardActive = Color3.fromRGB(42, 42, 48),
    Stroke  = Color3.fromRGB(70, 70, 78),
    Text    = Color3.fromRGB(225, 225, 232),
    SubText = Color3.fromRGB(130, 130, 140),
    Muted   = Color3.fromRGB(110, 110, 120),
    Accent  = Color3.fromRGB(190, 68, 78),
    AccentGlow = Color3.fromRGB(210, 130, 138),
    Accent2 = Color3.fromRGB(90, 40, 46),
    Good    = Color3.fromRGB(50, 215, 75),
    Warn    = Color3.fromRGB(255, 214, 10),
    Locked  = Color3.fromRGB(130, 130, 140),
    Error   = Color3.fromRGB(255, 69, 58),
}

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
S = {
    killAura = false, paRange = 7, paCD = 0.07, paHits = 2, paVisualRange = false,
    ragdollAura = false, raRange = 6, raCD = 0, raVisualRange = false,
    safeEverything = false,
    rapidPunch = false, rapidPunchHits = 4, rapidPunchRange = 12, rapidPunchVisualRange = false,
    autoUnblock = false, autoUnblockRange = 18, autoUnblockVisualRange = false,
    autoSlam = false, slamRange = 6, slamCD = 0, slamHotkey = false,
    antiStun = false,
    slamHotkeyRange = 12, slamHotkeyVisualRange = false, slamHotkeyCD = 0,
    autoBlock = false, blockRange = 6, safeBlock = false,
    infStamina = false,
    godmode = false, antiRagdoll = false, antiKnockdown = false,
    noclip = false,
    esp = false, espFill = 0.75, hpEsp = false, showLocked = false, rgbMode = false, espRgb = false, lockRgb = false, flashRgb = false, slamVisualRange = false, blockVisualRange = false,
    whitelistParty = true,
    reach = false, reachRange = 30, reachVisualRange = false,
    safeZone = false,
    antiAfk = false,
    autoDaily = false, autoSpin = false,
    godmodeReach = 15,
    antiSlam = false,
    antiFling = false, antiStaff = false,
    streamerMode = false,
    -- Touch Fling (walk-into → real DiveVelocity + server Dived On)
    touchFling = false, touchFlingRange = 3.6, touchFlingPower = 7, touchFlingVfx = true,
    grabSlamEnabled = false, grabSlamRange = 30, grabSlamVisualRange = false, aTrainFX = false, slamSound = true,
    flashStepEnabled = false, flashStepDistance = 25, flashStepVisualRange = false, flashStepAnim = true, flashSound = true,
    flashStepColor = Color3.fromRGB(64, 200, 255),
    walkEnabled = false, walkActive = false, walkspeedValue = 50,
    jumpEnabled = false, jumpPowerValue = 50,
    noFallDamage = false,
    firstPerson = false, firstPersonFov = 100,
    firstPersonLockOn = false, firstPersonLockRange = 10,
    bindSlamKb  = Enum.KeyCode.V, bindSlamGp  = Enum.KeyCode.DPadRight,
    bindGrabKb  = Enum.KeyCode.G, bindGrabGp  = Enum.KeyCode.ButtonY,
    bindFlashKb = Enum.KeyCode.F, bindFlashGp = Enum.KeyCode.ButtonB,
    bindWalkKb  = Enum.KeyCode.X, bindWalkGp  = Enum.KeyCode.DPadLeft,
    ragdollRate = 1.1,
    killFocus = false, freezeFocus = false,
    -- Fly (capped-vertical, camera relative)
    fly = false, flyActive = false, flySpeed = 55, flyNoclip = true,
    bindFlyKb = Enum.KeyCode.E, bindFlyGp = Enum.KeyCode.DPadDown,
    -- Rewards + party
    autoSpin = false,
}
publishState()
activeCapture = nil
whitelist = {}
lastSlam = 0
lastAutoSlam = 0
lastHotkeySlam = 0
lastRapidBurst = 0
isBlocking = false
blockSuppressUntil = 0
lastBlockFire = 0
-- When auto-block/godmode force-equips Fist/Guarding, FP must ignore that Guarding tag.
fpBlockForcedGuard = false
lastIncoming = 0
lockTarget = nil
slamDetectedTime, wasSlammed = 0, false

----------------------------------------------------------------------
-- Local image assets (dcpfp logo + background)
-- Base64-embedded, written to the executor workspace at runtime and loaded
-- via getcustomasset. Degrades gracefully (text logo / solid bg) when the
-- executor lacks writefile/getcustomasset.
----------------------------------------------------------------------
local DCPFP_B64 = nil -- embedded logo removed for executor compatibility
local BG_B64 = nil -- embedded background removed for executor compatibility

local function decodeBase64(data)
    for _, fn in ipairs({
        function() return crypt.base64decode(data) end,
        function() return crypt.base64.decode(data) end,
        function() return base64.decode(data) end,
        function() return base64_decode(data) end,
        function() return crypt.base64_decode(data) end,
    }) do
        local ok, res = pcall(fn)
        if ok and type(res) == "string" and #res > 0 then return res end
    end
    -- pure-Lua fallback
    local lookup = {}
    do
        local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        for i = 1, #b do lookup[b:sub(i, i)] = i - 1 end
    end
    local out, acc, nbits = {}, 0, 0
    for i = 1, #data do
        local v = lookup[data:sub(i, i)]
        if v then
            acc = acc * 64 + v
            nbits = nbits + 6
            if nbits >= 8 then
                nbits = nbits - 8
                out[#out + 1] = string.char(math.floor(acc / 2 ^ nbits) % 256)
                acc = acc % (2 ^ nbits)
            end
        end
    end
    return table.concat(out)
end

local function loadLocalImage(fileName, b64)
    if type(b64) ~= "string" or #b64 < 16 or b64:sub(1, 2) == "__" then return nil end
    local getter = (typeof(getcustomasset) == "function" and getcustomasset)
        or (typeof(getsynasset) == "function" and getsynasset) or nil
    if typeof(writefile) ~= "function" or not getter then return nil end
    local ok, content = pcall(function()
        writefile(fileName, decodeBase64(b64))
        return getter(fileName)
    end)
    if ok and type(content) == "string" and #content > 0 then return content end
    return nil
end

local DCPFP_IMAGE = loadLocalImage("dcpfp_caf2_logo.png", DCPFP_B64)
local BG_IMAGE    = loadLocalImage("dcpfp_caf2_bg.jpg", BG_B64)

----------------------------------------------------------------------
-- UI primitives
----------------------------------------------------------------------
local TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local FAST  = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function corner(p, r) return new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, p) end
local function stroke(p, col, th, trans)
    return new("UIStroke", {
        Color = col or Theme.Stroke,
        Thickness = th or 1,
        Transparency = trans or 0.78,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, p)
end
local function gradient(p, c1, c2, rot) return new("UIGradient", { Color = ColorSequence.new(c1, c2), Rotation = rot or 0 }, p) end
local function pad(p, l, t, r, b)
    return new("UIPadding", {
        PaddingLeft = UDim.new(0, l or 0), PaddingTop = UDim.new(0, t or l or 0),
        PaddingRight = UDim.new(0, r or l or 0), PaddingBottom = UDim.new(0, b or t or l or 0),
    }, p)
end
----------------------------------------------------------------------
-- Crisp monogram icons (Gotham letter marks — stay sharp when scaled)
----------------------------------------------------------------------
local ICON_LETTER = {
    Combat = "C",
    Slam = "S",
    Target = "T",
    Protection = "P",
    ["Bowling Ball"] = "B",
    Morphs = "M",
    ["Flash Step"] = "F",
    FlashStep = "F",
    Visuals = "E",
    Whitelist = "W",
    Settings = "O",
}
local function createVectorIcon(name, parent, size)
    size = size or 16
    local holder = new("Frame", {
        Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 5,
    }, parent)
    local key = name:gsub("%s+", "")
    local letter = ICON_LETTER[name] or ICON_LETTER[key] or string.sub(name, 1, 1):upper()
    local lbl = new("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        Text = letter, TextColor3 = Color3.fromRGB(235, 235, 240),
        Font = Enum.Font.GothamBlack, TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = 6,
    }, holder)
    new("UITextSizeConstraint", {
        MaxTextSize = math.max(9, math.floor(size * 0.78)),
        MinTextSize = 7,
    }, lbl)
    return holder
end
local function makeLogo(parent, size, x, y, radius, zindex)
    local rad = radius or math.floor(size * 0.32)
    local z = zindex or 3
    local holder = new("Frame", {
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(size, size),
        BackgroundColor3 = Color3.fromRGB(28, 28, 32), BorderSizePixel = 0, ZIndex = z + 2,
    }, parent)
    corner(holder, rad)
    stroke(holder, Theme.Stroke, 1, 0.45)
    new("Frame", {
        Size = UDim2.new(0, 3, 0.5, 0), Position = UDim2.new(0, 0, 0.25, 0),
        BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = z + 3,
    }, holder)
    local txt = new("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "V",
        TextColor3 = Theme.Text, Font = Enum.Font.GothamBlack, TextScaled = true, ZIndex = z + 4,
    }, holder)
    new("UITextSizeConstraint", { MaxTextSize = math.max(8, math.floor(size * 0.58)) }, txt)
    new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3) }, txt)
    local logoImg = LOGO_ASSET or DCPFP_IMAGE
    if logoImg then
        local img = new("ImageLabel", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = logoImg,
            ScaleType = Enum.ScaleType.Crop, ZIndex = z + 5,
        }, holder)
        corner(img, rad)
    end
    return holder
end

local ScreenGui = new("ScreenGui", {
    Name = "CAF2_Suite_" .. tostring(math.random(1e4, 9e4)),
    ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true,
    DisplayOrder = 1000000,
})
do
    local ok = false
    if typeof(gethui) == "function" then ok = pcall(function() ScreenGui.Parent = gethui() end) end
    if not ok and syn and syn.protect_gui then pcall(function() syn.protect_gui(ScreenGui); ScreenGui.Parent = game:GetService("CoreGui") end); ok = true end
    if not ok then pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end) end
    if not ScreenGui.Parent then ScreenGui.Parent = LP:WaitForChild("PlayerGui") end
end
Maid:GiveInst(ScreenGui)

local function notify(title, text)
    pcall(function() game:GetService("StarterGui"):SetCore("SendNotification", { Title = title, Text = text, Duration = 4 }) end)
end

-- Bottom-right toast (bypass credits after loader). Own ScreenGui so the suite
-- window / autoload notify can't cover or parent-fail it.
local function showCornerToast(title, body, duration)
    task.spawn(function()
        duration = duration or 6
        -- Also fire stock notify so something always shows even if custom GUI fails.
        notify(title, body)

        local host = Instance.new("ScreenGui")
        host.Name = "CAF2_ToastGui"
        host.ResetOnSpawn = false
        host.IgnoreGuiInset = true
        host.DisplayOrder = 2147483647
        host.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        local okParent = false
        if typeof(gethui) == "function" then
            okParent = pcall(function() host.Parent = gethui() end)
        end
        if not okParent then
            okParent = pcall(function() host.Parent = game:GetService("CoreGui") end)
        end
        if not okParent then
            pcall(function() host.Parent = LP:WaitForChild("PlayerGui") end)
        end
        if not host.Parent then return end

        local toast = Instance.new("Frame")
        toast.Name = "CreditToast"
        toast.AnchorPoint = Vector2.new(1, 1)
        toast.Position = UDim2.new(1, -16, 1, 80) -- start slightly below
        toast.Size = UDim2.fromOffset(340, 78)
        toast.BackgroundColor3 = Color3.fromRGB(17, 17, 17)
        toast.BorderSizePixel = 0
        toast.ZIndex = 10
        toast.Parent = host
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 12)
        c.Parent = toast
        local s = Instance.new("UIStroke")
        s.Color = Theme.Accent
        s.Thickness = 1.5
        s.Transparency = 0.35
        s.Parent = toast

        local accent = Instance.new("Frame")
        accent.Size = UDim2.new(0, 4, 1, -16)
        accent.Position = UDim2.fromOffset(10, 8)
        accent.BackgroundColor3 = Theme.Accent
        accent.BorderSizePixel = 0
        accent.ZIndex = 11
        accent.Parent = toast
        local ac = Instance.new("UICorner")
        ac.CornerRadius = UDim.new(0, 2)
        ac.Parent = accent

        local t1 = Instance.new("TextLabel")
        t1.BackgroundTransparency = 1
        t1.Size = UDim2.new(1, -28, 0, 24)
        t1.Position = UDim2.fromOffset(22, 12)
        t1.Font = Enum.Font.GothamBold
        t1.TextSize = 14
        t1.TextColor3 = Color3.fromRGB(255, 255, 255)
        t1.TextXAlignment = Enum.TextXAlignment.Left
        t1.Text = title
        t1.ZIndex = 11
        t1.Parent = toast

        local t2 = Instance.new("TextLabel")
        t2.BackgroundTransparency = 1
        t2.Size = UDim2.new(1, -28, 0, 32)
        t2.Position = UDim2.fromOffset(22, 36)
        t2.Font = Enum.Font.Gotham
        t2.TextSize = 13
        t2.TextColor3 = Color3.fromRGB(200, 200, 210)
        t2.TextXAlignment = Enum.TextXAlignment.Left
        t2.TextWrapped = true
        t2.Text = body
        t2.ZIndex = 11
        t2.Parent = toast

        pcall(function()
            TweenService:Create(toast, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                Position = UDim2.new(1, -16, 1, -16),
            }):Play()
        end)

        task.wait(duration)
        pcall(function()
            local out = TweenService:Create(toast, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
                Position = UDim2.new(1, -16, 1, 80),
            })
            out:Play()
            out.Completed:Wait()
        end)
        pcall(function() host:Destroy() end)
    end)
end

----------------------------------------------------------------------
-- VELORIX — window (complete frontend redesign)
--
-- A unified titlebar + icon navigation rail + grouped content surface,
-- styled after premium desktop software (Linear / SteelSeries GG / Arc).
-- Every component factory below keeps its ORIGINAL signature and return
-- contract, so the feature builders, the config engine, and the
-- hotkey / drag / loader code all run against it unchanged.
----------------------------------------------------------------------

-- Forward declarations for the names later code (feature tabs, config
-- engine, hotkeys, dragging, loader) closes over. Transient construction
-- locals live inside the do-block to keep main-chunk register use flat.
local C, SMOOTH, SNAP, GLIDE
local mainFrame, uiVisible, setVisible
local TopBar, Sidebar, panelInner, titleLabel, subtitleLabel
local navHolder, navIndicator, headerIconHolder
local Tabs, tabOrder = {}, {}
local TabMeta = {
    Combat        = "Real-time striking tools",
    Slam          = "Ground slams & grabs",
    Target        = "Lock one player & destroy",
    Protection    = "Survival & anti-cheat",
    ["Bowling Ball"] = "Roll into people",
    Morphs        = "Change into other characters",
    ["Flash Step"] = "Blink, speed & movement",
    Visuals       = "ESP & target highlighting",
    Whitelist     = "Players never targeted",
    Settings      = "Session, configs & info",
}
local UIControls, keybindRefreshers = {}, {}
local makeTab, section, card, toggle, slider, colorpicker, keybind, label

local function tw(o, info, props) return TweenService:Create(o, info, props) end

-- Layout bag (single upvalue — avoids main-chunk register pressure)
local Layout = {
    mobile = false,
    override = nil,
    DESKTOP_W = 380,
    DESKTOP_H = 520,
    TABH = 34,
}
local ContentRoot, fitHost

C = {
    Ink0 = Color3.fromRGB(12, 12, 14),
    Ink1 = Color3.fromRGB(16, 16, 18),
    Ink2 = Color3.fromRGB(28, 28, 32),
    Ink3 = Color3.fromRGB(40, 40, 46),
    Ink4 = Color3.fromRGB(52, 52, 58),
    Line = Color3.fromRGB(70, 70, 78),
    Red  = Theme.Accent,
    RedHi = Theme.AccentGlow,
    RedLo = Theme.Accent2,
    RedInk = Color3.fromRGB(48, 28, 32),
    Text = Theme.Text,
    Mid  = Theme.SubText,
    Low  = Theme.Muted,
    GlassBody = 0.30, GlassRail = 0.35, GlassCard = 0.32, GlassChip = 0.38,
    Knob = Color3.fromRGB(200, 200, 208),
}
SMOOTH = TweenInfo.new(0.30, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
SNAP   = TweenInfo.new(0.16, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
GLIDE  = TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

do
    local HEADH, RADIUS = 48, 14
    local DESKTOP_W, DESKTOP_H, TABH = Layout.DESKTOP_W, Layout.DESKTOP_H, Layout.TABH

    mainFrame = new("Frame", {
        Name = "VelorixWindow", Size = UDim2.fromOffset(DESKTOP_W, DESKTOP_H),
        Position = UDim2.new(1, -18, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5),
        BackgroundTransparency = 1, BorderSizePixel = 0, Active = true, Visible = false,
    }, ScreenGui)
    local winScale = new("UIScale", { Scale = 1 }, mainFrame)

    for i = 1, 2 do
        local sh = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(1, i * 12, 1, i * 12),
            BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.8 + i * 0.06,
            BorderSizePixel = 0, ZIndex = -4,
        }, mainFrame)
        corner(sh, RADIUS + i * 5)
    end

    local body = new("CanvasGroup", {
        Name = "Body", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Ink1,
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
    }, mainFrame)
    corner(body, RADIUS)
    do
        local plate = new("Frame", {
            Name = "GlassPlate", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Ink1,
            BackgroundTransparency = C.GlassBody, BorderSizePixel = 0, ZIndex = 0,
        }, body)
        corner(plate, RADIUS)
        gradient(plate, Color3.fromRGB(34, 34, 40), Color3.fromRGB(12, 12, 14), 155)
    end
    do
        local rim = new("Frame", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 20,
        }, body)
        corner(rim, RADIUS)
        stroke(rim, C.Line, 1, 0.78)
    end

    if BG_IMAGE then
        new("ImageLabel", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = BG_IMAGE,
            ImageTransparency = 0.92, ScaleType = Enum.ScaleType.Crop, ZIndex = 1,
        }, body)
    end

    ----------------------------------------------------------------
    -- Titlebar: [logo + brand] .............. [chip] [min] [close]
    ----------------------------------------------------------------
    TopBar = new("Frame", {
        Name = "TitleBar", Size = UDim2.new(1, 0, 0, HEADH), BackgroundTransparency = 1, ZIndex = 8,
    }, body)

    makeLogo(TopBar, 26, 12, 11, 7, 9)

    local brandStack = new("Frame", {
        Name = "Brand", Position = UDim2.fromOffset(46, 8), Size = UDim2.new(1, -238, 0, 32),
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 9, ClipsDescendants = true,
    }, TopBar)
    local brandTitle = new("TextLabel", {
        Name = "BrandTitle", Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 17), BackgroundTransparency = 1,
        Text = "VELORIX", TextColor3 = C.Text, Font = Enum.Font.GothamBlack, TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 9,
    }, brandStack)
    local brandSub = new("TextLabel", {
        Name = "BrandSub", Position = UDim2.fromOffset(0, 17), Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 1,
        Text = "CAF2  ·  PC", TextColor3 = C.Mid, Font = Enum.Font.GothamMedium, TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 9,
    }, brandStack)
    Layout.brandStack = brandStack
    Layout.brandTitle = brandTitle
    Layout.brandSub = brandSub

    -- right controls first so chip can sit left of them without overlap
    local function ctrlBtn(rightX, kind)
        local b = new("TextButton", {
            Name = kind == "close" and "CloseBtn" or "MinBtn",
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -rightX, 0.5, 0),
            Size = UDim2.fromOffset(26, 26), BackgroundColor3 = C.Ink3, BackgroundTransparency = 0.2,
            AutoButtonColor = false, Text = "", BorderSizePixel = 0, ZIndex = 11,
        }, TopBar)
        corner(b, 8)
        local bs = stroke(b, C.Line, 1, 0.65)
        if kind == "close" then
            for _, rot in ipairs({ 45, -45 }) do
                new("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
                    Size = UDim2.fromOffset(9, 1.4), BackgroundColor3 = C.Mid, BorderSizePixel = 0,
                    Rotation = rot, ZIndex = 12,
                }, b)
            end
        else
            new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(9, 1.4), BackgroundColor3 = C.Mid, BorderSizePixel = 0, ZIndex = 12,
            }, b)
        end
        Maid:Give(b.MouseEnter:Connect(function()
            tw(b, SNAP, { BackgroundColor3 = C.Red, BackgroundTransparency = 0.12 }):Play()
            tw(bs, SNAP, { Color = C.RedHi, Transparency = 0.4 }):Play()
        end))
        Maid:Give(b.MouseLeave:Connect(function()
            tw(b, SNAP, { BackgroundColor3 = C.Ink3, BackgroundTransparency = 0.2 }):Play()
            tw(bs, SNAP, { Color = C.Line, Transparency = 0.65 }):Play()
        end))
        Maid:Give(b.MouseButton1Click:Connect(function() setVisible(false) end))
        return b
    end
    local closeBtn = ctrlBtn(10, "close")
    local minBtn = ctrlBtn(40, "min")
    Layout.closeBtn = closeBtn
    Layout.minBtn = minBtn

    -- account chip: pfp + truncated name, always left of window controls
    local accountChip
    do
        local uname = tostring(LP.Name or "Player")
        if #uname > 12 then uname = string.sub(uname, 1, 11) .. "..." end
        accountChip = new("Frame", {
            Name = "AccountChip",
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -80, 0.5, 0),
            Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = C.Ink2, BackgroundTransparency = C.GlassChip,
            BorderSizePixel = 0, ZIndex = 10, ClipsDescendants = true,
        }, TopBar)
        corner(accountChip, 8); stroke(accountChip, C.Line, 1, 0.75)
        new("UIPadding", {
            PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 8),
            PaddingTop = UDim.new(0, 0), PaddingBottom = UDim.new(0, 0),
        }, accountChip)
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
            VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
        }, accountChip)
        local pfp = new("Frame", {
            LayoutOrder = 1, Size = UDim2.fromOffset(20, 20),
            BackgroundColor3 = C.Ink3, BorderSizePixel = 0, ZIndex = 11,
        }, accountChip)
        corner(pfp, 6)
        local img = new("ImageLabel", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
            Image = "rbxthumb://type=AvatarHeadShot&id=" .. LP.UserId .. "&w=150&h=150",
            ScaleType = Enum.ScaleType.Crop, ZIndex = 12,
        }, pfp)
        corner(img, 6)
        new("TextLabel", {
            LayoutOrder = 2, Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1, Text = uname, TextColor3 = C.Text,
            Font = Enum.Font.GothamBold, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 11,
        }, accountChip)
        -- hard max so chip never eats the brand
        local maxW = new("UISizeConstraint", { MaxSize = Vector2.new(110, 28), MinSize = Vector2.new(28, 28) }, accountChip)
        Layout.accountMax = maxW
    end
    Layout.accountChip = accountChip

    ----------------------------------------------------------------
    -- Top chip strip (unique vs free side-rail / right drawer)
    ----------------------------------------------------------------
    Sidebar = new("Frame", {
        Name = "TabStrip", Position = UDim2.fromOffset(10, HEADH), Size = UDim2.new(1, -20, 0, TABH),
        BackgroundColor3 = C.Ink2, BackgroundTransparency = 0.28, BorderSizePixel = 0, ZIndex = 4,
    }, body)
    corner(Sidebar, 12)
    stroke(Sidebar, C.Line, 1, 0.72)

    navIndicator = new("Frame", {
        Position = UDim2.fromOffset(8, TABH - 4), Size = UDim2.fromOffset(40, 2), BackgroundColor3 = C.Red,
        BorderSizePixel = 0, ZIndex = 7, BackgroundTransparency = 1,
    }, Sidebar)
    corner(navIndicator, 1)

    navHolder = new("ScrollingFrame", {
        Name = "TabHolder", Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
        ScrollingDirection = Enum.ScrollingDirection.X, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.X, ZIndex = 5, Active = true, ScrollingEnabled = true,
    }, Sidebar)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center,
    }, navHolder)
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
        PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2),
    }, navHolder)

    ----------------------------------------------------------------
    -- Content column (full width under chips)
    ----------------------------------------------------------------
    local Content = new("Frame", {
        Name = "Content", Position = UDim2.fromOffset(0, HEADH + TABH + 4),
        Size = UDim2.new(1, 0, 1, -(HEADH + TABH + 4)), BackgroundTransparency = 1, ZIndex = 2,
    }, body)
    ContentRoot = Content
    pad(Content, 10, 6, 8, 8)

    titleLabel = new("TextLabel", {
        Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, -8, 0, 18), BackgroundTransparency = 1,
        Text = "COMBAT", TextColor3 = C.Text, Font = Enum.Font.GothamBlack, TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
    }, Content)
    subtitleLabel = new("TextLabel", {
        Position = UDim2.fromOffset(1, 18), Size = UDim2.new(1, -8, 0, 13), BackgroundTransparency = 1,
        Text = "Real-time striking tools", TextColor3 = C.Mid, Font = Enum.Font.Gotham, TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
    }, Content)
    headerIconHolder = new("Frame", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.fromOffset(28, 28),
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3, Visible = false,
    }, Content)

    panelInner = new("Frame", {
        Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 1, -36), BackgroundTransparency = 1, ZIndex = 2,
        ClipsDescendants = true,
    }, Content)

    ----------------------------------------------------------------
    -- Open / close animation
    ----------------------------------------------------------------
    uiVisible = true
    setVisible = function(v)
        pcall(function() getgenv().__SV = (getgenv().__SV or "") .. tostring(v) .. "@" .. string.format("%.2f", tick() % 100) .. ";" end)
        uiVisible = v and true or false
        if not premiumUnlocked then return end
        if uiVisible then
            mainFrame.Visible = true
            winScale.Scale = 0.92
            body.BackgroundTransparency = 1
            local plate = body:FindFirstChild("GlassPlate")
            if plate then plate.BackgroundTransparency = 1 end
            tw(winScale, GLIDE, { Scale = 1 }):Play()
            if plate then tw(plate, SMOOTH, { BackgroundTransparency = C.GlassBody }):Play() end
        else
            local plate = body:FindFirstChild("GlassPlate")
            local a = tw(winScale, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { Scale = 0.93 })
            local b = tw(body, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { BackgroundTransparency = 1 })
            if plate then tw(plate, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play() end
            b.Completed:Connect(function() if not uiVisible then mainFrame.Visible = false end end)
            a:Play(); b:Play()
        end
    end
end

-- Responsive: desktop chip deck / mobile bottom sheet (kept tight for registers)
do
    local function clamp(n, a, b)
        if n < a then return a end
        if n > b then return b end
        return n
    end
    fitHost = function()
        local vp = (Cam and Cam.ViewportSize) or Vector2.new(1280, 720)
        local mobile = Layout.override
        if mobile == nil then
            -- keyboard = PC (touch laptops still report TouchEnabled)
            if UserInputService.KeyboardEnabled then
                mobile = false
            elseif UserInputService.TouchEnabled then
                mobile = true
            else
                mobile = (vp.X < 700 and vp.Y < 900)
            end
        end
        Layout.mobile = mobile and true or false
        do
            local sub = Layout.brandSub
            if (not sub or not sub.Parent) and Layout.brandStack then
                sub = Layout.brandStack:FindFirstChild("BrandSub")
                Layout.brandSub = sub
            end
            if sub then
                sub.Text = Layout.mobile and "CAF2  ·  MOBILE" or "CAF2  ·  PC"
            end
        end
        local HEADH = 48
        local TABH = Layout.TABH
        local sc = mainFrame:FindFirstChildOfClass("UIScale")
        if sc then sc.Scale = 1 end
        if Layout.accountChip then Layout.accountChip.Visible = not Layout.mobile end
        if Layout.brandStack then
            -- leave room for chip + window controls on desktop; controls only on mobile
            Layout.brandStack.Size = Layout.mobile
                and UDim2.new(1, -78, 0, 32)
                or UDim2.new(1, -238, 0, 32)
        end
        if Layout.accountChip and not Layout.mobile then
            Layout.accountChip.Position = UDim2.new(1, -80, 0.5, 0)
            if Layout.accountMax then
                Layout.accountMax.MaxSize = Vector2.new(110, 28)
            end
        end
        if Layout.minBtn then Layout.minBtn.Visible = true end
        if Layout.closeBtn then Layout.closeBtn.Visible = true end

        -- desktop: hide scrollbar chrome; mobile: touch scroll with a thin bar
        if navHolder and navHolder:IsA("ScrollingFrame") then
            pcall(function()
                navHolder.HorizontalScrollBarInset = Enum.ScrollBarInset.None
                navHolder.VerticalScrollBarInset = Enum.ScrollBarInset.None
            end)
            navHolder.ScrollingEnabled = true
            navHolder.Active = true
            navHolder.AutomaticCanvasSize = Enum.AutomaticSize.X
            if Layout.mobile then
                navHolder.ScrollBarThickness = 3
                navHolder.ScrollBarImageTransparency = 0.35
                navHolder.ScrollBarImageColor3 = C.Line
                pcall(function()
                    navHolder.ElasticBehavior = Enum.ElasticBehavior.Always
                    navHolder.ScrollingDirection = Enum.ScrollingDirection.X
                end)
            else
                navHolder.ScrollBarThickness = 0
                navHolder.ScrollBarImageTransparency = 1
            end
        end
        for _, t in pairs(Tabs) do
            if t.page and t.page:IsA("ScrollingFrame") then
                t.page.ScrollingEnabled = true
                t.page.Active = true
                t.page.AutomaticCanvasSize = Enum.AutomaticSize.Y
                pcall(function()
                    t.page.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
                    t.page.HorizontalScrollBarInset = Enum.ScrollBarInset.None
                    t.page.ScrollingDirection = Enum.ScrollingDirection.Y
                end)
                if Layout.mobile then
                    -- visible thin bar + elastic so touch-drag feels native
                    t.page.ScrollBarThickness = 4
                    t.page.ScrollBarImageTransparency = 0.25
                    t.page.ScrollBarImageColor3 = C.Red
                    pcall(function()
                        t.page.ElasticBehavior = Enum.ElasticBehavior.Always
                    end)
                else
                    t.page.ScrollBarThickness = 3
                    t.page.ScrollBarImageTransparency = 0.45
                    t.page.ScrollBarImageColor3 = C.Line
                    pcall(function()
                        t.page.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
                        t.page.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
                    end)
                end
            end
        end

        if Layout.mobile then
            local baseW = (Layout.override == true) and 390 or vp.X
            local baseH = (Layout.override == true) and 844 or vp.Y
            -- wider bottom sheet; leave room for game controls under it
            local w = clamp(math.floor(baseW - 16), 320, 420)
            local h = clamp(math.floor(baseH * 0.58), 300, 420)
            mainFrame.Size = UDim2.fromOffset(w, h)
            mainFrame.AnchorPoint = Vector2.new(0.5, 1)
            mainFrame.Position = UDim2.new(0.5, 0, 1, -10)
            TopBar.Size = UDim2.new(1, 0, 0, 42)
            Sidebar.Position = UDim2.fromOffset(8, 42)
            Sidebar.Size = UDim2.new(1, -16, 0, 40)
            if ContentRoot then
                ContentRoot.Position = UDim2.fromOffset(0, 86)
                ContentRoot.Size = UDim2.new(1, 0, 1, -86)
            end
            if titleLabel then titleLabel.TextSize = 14 end
            if subtitleLabel then subtitleLabel.Visible = false end
            -- original names; chip width from label length, swipe tabs horizontally
            for name, t in pairs(Tabs) do
                local chipW = math.clamp((#name) * 7 + 22, 72, 118)
                if t.frame then
                    t.frame.AutomaticSize = Enum.AutomaticSize.None
                    t.frame.Size = UDim2.fromOffset(chipW, 32)
                end
                if t.lbl then
                    t.lbl.Text = name
                    t.lbl.TextSize = 11
                    t.lbl.TextScaled = false
                    t.lbl.TextTruncate = Enum.TextTruncate.None
                    t.lbl.AutomaticSize = Enum.AutomaticSize.None
                    t.lbl.Size = UDim2.fromScale(1, 1)
                end
            end
        else
            local w = math.min(Layout.DESKTOP_W, math.max(340, math.floor(vp.X * 0.22)))
            local h = math.min(Layout.DESKTOP_H, math.max(360, math.floor(vp.Y * 0.58)))
            mainFrame.Size = UDim2.fromOffset(w, h)
            mainFrame.AnchorPoint = Vector2.new(1, 0.5)
            mainFrame.Position = UDim2.new(1, -18, 0.5, 0)
            TopBar.Size = UDim2.new(1, 0, 0, HEADH)
            Sidebar.Position = UDim2.fromOffset(10, HEADH)
            Sidebar.Size = UDim2.new(1, -20, 0, TABH)
            if ContentRoot then
                ContentRoot.Position = UDim2.fromOffset(0, HEADH + TABH + 2)
                ContentRoot.Size = UDim2.new(1, 0, 1, -(HEADH + TABH + 2))
            end
            if titleLabel then titleLabel.TextSize = 16 end
            if subtitleLabel then subtitleLabel.Visible = true end
            for name, t in pairs(Tabs) do
                if t.frame then
                    t.frame.Size = UDim2.fromOffset(86, 30)
                    t.frame.AutomaticSize = Enum.AutomaticSize.None
                end
                if t.lbl then
                    t.lbl.TextSize = 11
                    t.lbl.Text = name
                    t.lbl.AutomaticSize = Enum.AutomaticSize.None
                end
            end
        end
    end
    if Cam then
        Maid:Give(Cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            if fitHost then fitHost() end
        end))
    end
end

----------------------------------------------------------------------
-- Tabs (text-first like free — crisp underline, no muddy icon boxes)
----------------------------------------------------------------------
makeTab = function(name)
    local idx = #tabOrder
    local chipW = Layout.mobile and 72 or 86
    local frame = new("Frame", {
        Name = "Nav_" .. name, Size = UDim2.fromOffset(chipW, 30),
        BackgroundColor3 = C.Ink3, BackgroundTransparency = 1,
        BorderSizePixel = 0, ZIndex = 5, LayoutOrder = idx,
    }, navHolder)
    corner(frame, 7)

    local lbl = new("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, Text = name, TextColor3 = C.Mid, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6,
    }, frame)
    local marker = new("Frame", {
        Name = "Marker", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2),
        Size = UDim2.fromOffset(22, 2), BackgroundColor3 = C.Red, BackgroundTransparency = 1,
        BorderSizePixel = 0, ZIndex = 7,
    }, frame)
    corner(marker, 1)
    local click = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 8 }, frame)

    local page = new("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
        ScrollBarImageTransparency = 1, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
        Visible = false, ZIndex = 2, ScrollingEnabled = true, Active = true,
        VerticalScrollBarInset = Enum.ScrollBarInset.None,
        HorizontalScrollBarInset = Enum.ScrollBarInset.None,
    }, panelInner)
    new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, page)
    new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingRight = UDim.new(0, 2), PaddingBottom = UDim.new(0, 6) }, page)

    local function deselect()
        page.Visible = false
        tw(frame, SMOOTH, { BackgroundTransparency = 1 }):Play()
        tw(marker, SMOOTH, { BackgroundTransparency = 1 }):Play()
        tw(lbl, SMOOTH, { TextColor3 = C.Mid }):Play()
    end
    local function select()
        for _, t in pairs(Tabs) do t.deselect() end
        page.Visible = true
        tw(frame, SMOOTH, { BackgroundColor3 = C.Ink2, BackgroundTransparency = 0.45 }):Play()
        tw(marker, SMOOTH, { BackgroundTransparency = 0 }):Play()
        tw(lbl, SMOOTH, { TextColor3 = C.Text }):Play()
        titleLabel.Text = name:upper()
        subtitleLabel.Text = TabMeta[name] or "Catch A Fade 2 • Premium"
        if not Layout.mobile then
            pcall(function()
                local x = frame.AbsolutePosition.X - navHolder.AbsolutePosition.X + navHolder.CanvasPosition.X
                local view = navHolder.AbsoluteSize.X
                if x < navHolder.CanvasPosition.X then
                    navHolder.CanvasPosition = Vector2.new(math.max(0, x - 8), 0)
                elseif x + frame.AbsoluteSize.X > navHolder.CanvasPosition.X + view then
                    navHolder.CanvasPosition = Vector2.new(x + frame.AbsoluteSize.X - view + 8, 0)
                end
            end)
        end
    end
    Maid:Give(click.MouseButton1Click:Connect(select))
    Maid:Give(click.MouseEnter:Connect(function()
        if not page.Visible then
            tw(frame, SNAP, { BackgroundColor3 = C.Ink2, BackgroundTransparency = 0.65 }):Play()
            tw(lbl, SNAP, { TextColor3 = C.Text }):Play()
        end
    end))
    Maid:Give(click.MouseLeave:Connect(function()
        if not page.Visible then
            tw(frame, SNAP, { BackgroundTransparency = 1 }):Play()
            tw(lbl, SNAP, { TextColor3 = C.Mid }):Play()
        end
    end))
    Tabs[name] = { frame = frame, page = page, select = select, deselect = deselect, marker = marker, lbl = lbl }
    table.insert(tabOrder, name)
    return page
end

----------------------------------------------------------------------
-- Section header (muted — no crimson wash)
----------------------------------------------------------------------
section = function(page, title)
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, BorderSizePixel = 0 }, page)
    new("TextLabel", {
        Position = UDim2.fromOffset(2, 4), Size = UDim2.new(1, -4, 0, 14), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, Text = title:upper(), TextColor3 = C.Mid, TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2,
    }, holder)
    return holder
end

----------------------------------------------------------------------
-- Card: flat inset row. Hover reveals a growing crimson edge + wash.
-- Returns the surface frame (children attach to it), same as before.
----------------------------------------------------------------------
card = function(page, h)
    h = h or 40
    local f = new("Frame", { Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, BorderSizePixel = 0 }, page)
    local inner = new("Frame", {
        Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Ink2, BackgroundTransparency = C.GlassCard,
        BorderSizePixel = 0, ZIndex = 2,
    }, f)
    corner(inner, 11)
    local s = stroke(inner, C.Line, 1, 0.9)
    local acc = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(2, 0),
        BackgroundColor3 = C.Red, BorderSizePixel = 0, ZIndex = 4,
    }, inner)
    corner(acc, 1)
    local accH = math.max(12, h - 16)
    Maid:Give(inner.MouseEnter:Connect(function()
        tw(inner, SNAP, { BackgroundColor3 = C.Ink3, BackgroundTransparency = 0.08 }):Play()
        tw(s, SNAP, { Color = C.Line, Transparency = 0.55 }):Play()
        tw(acc, SNAP, { Size = UDim2.fromOffset(2.5, accH), BackgroundTransparency = 0 }):Play()
    end))
    Maid:Give(inner.MouseLeave:Connect(function()
        tw(inner, SNAP, { BackgroundColor3 = C.Ink2, BackgroundTransparency = C.GlassCard }):Play()
        tw(s, SNAP, { Color = C.Line, Transparency = 0.88 }):Play()
        tw(acc, SNAP, { Size = UDim2.fromOffset(2, 0) }):Play()
    end))
    return inner
end

----------------------------------------------------------------------
-- Hint text under a control (what the option does).
----------------------------------------------------------------------
hint = function(page, text)
    if type(text) ~= "string" or text == "" then return end
    local f = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, BorderSizePixel = 0,
    }, page)
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 12),
        PaddingTop = UDim.new(0, 0), PaddingBottom = UDim.new(0, 4),
    }, f)
    new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Font = Enum.Font.Gotham,
        Text = text, TextColor3 = C.Low, TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
    }, f)
end

----------------------------------------------------------------------
-- Toggle: redesigned pill switch with crimson glow halo + knob overshoot.
----------------------------------------------------------------------
toggle = function(page, text, default, callback, desc)
    local TR_W, TR_H, KNOB, MARG = 42, 22, 16, 3
    local f = card(page, 36)
    new("TextLabel", {
        Size = UDim2.new(1, -80, 1, 0), Position = UDim2.fromOffset(14, 0), BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium, Text = text, TextColor3 = C.Text, TextSize = 12.5,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3,
    }, f)
    local track = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(TR_W, TR_H),
        BackgroundColor3 = default and C.Red or C.Ink4, BorderSizePixel = 0, ZIndex = 3,
    }, f)
    corner(track, TR_H / 2)
    local trackStroke = stroke(track, default and C.RedHi or C.Line, 1.2, default and 0.35 or 0.85)
    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, default and (TR_W - KNOB - MARG) or MARG, 0.5, 0),
        Size = UDim2.fromOffset(KNOB, KNOB), BackgroundColor3 = C.Knob,
        BorderSizePixel = 0, ZIndex = 5,
    }, track)
    corner(knob, KNOB / 2)
    local knobScale = new("UIScale", { Scale = 1 }, knob)
    local state = default and true or false
    local function render(anim)
        local slide = anim and TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out) or TweenInfo.new(0)
        local col = anim and SNAP or TweenInfo.new(0)
        tw(track, col, { BackgroundColor3 = state and C.Red or C.Ink4 }):Play()
        tw(trackStroke, col, { Color = state and C.RedHi or C.Line, Transparency = state and 0.5 or 0.9 }):Play()
        tw(knob, slide, { Position = UDim2.new(0, state and (TR_W - KNOB - MARG) or MARG, 0.5, 0) }):Play()
        if anim then
            knobScale.Scale = 0.82
            tw(knobScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
        end
    end
    local function setState(v, fire)
        local nv = v and true or false
        if nv == state and fire == false then return end
        state = nv; render(true)
        if fire ~= false then callback(state) end
    end
    local btn = new("TextButton", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 6,
        AutoButtonColor = false, Active = true,
    }, f)
    -- allow vertical touch-drag to scroll the page instead of eating the gesture
    do
        local pressY, scrolling
        Maid:Give(btn.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
                pressY = i.Position.Y
                scrolling = false
            end
        end))
        Maid:Give(btn.InputChanged:Connect(function(i)
            if pressY and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
                if math.abs(i.Position.Y - pressY) > 10 then scrolling = true end
            end
        end))
        Maid:Give(btn.MouseButton1Click:Connect(function()
            if scrolling then return end
            setState(not state, true)
        end))
        Maid:Give(UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
                pressY, scrolling = nil, false
            end
        end))
    end
    UIControls[text] = {
        get = function() return state end,
        set = function(v, fire)
            if fire == nil then fire = true end
            setState(v, fire)
        end,
    }
    if default then task.spawn(callback, true) end
    if desc then hint(page, desc) end
    return f
end

----------------------------------------------------------------------
-- Slider: thick rounded track, ringed glowing thumb, value chip.
----------------------------------------------------------------------
slider = function(page, text, min, max, default, suffix, callback, desc)
    local f = card(page, 46)
    new("TextLabel", {
        Size = UDim2.new(1, -96, 0, 16), Position = UDim2.fromOffset(14, 6), BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium, Text = text, TextColor3 = C.Text, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
    }, f)
    local valPill = new("Frame", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 5), Size = UDim2.fromOffset(60, 18),
        BackgroundColor3 = C.Ink4, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 3,
    }, f)
    corner(valPill, 6); stroke(valPill, C.Line, 1, 0.9)
    local valLbl = new("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = tostring(default) .. (suffix or ""), TextColor3 = C.Text, TextSize = 11, ZIndex = 4,
    }, valPill)
    local bar = new("Frame", {
        Size = UDim2.new(1, -28, 0, 5), Position = UDim2.fromOffset(14, 32), BackgroundColor3 = C.Ink4,
        BorderSizePixel = 0, ZIndex = 3,
    }, f)
    corner(bar, 3)
    local fill = new("Frame", {
        Size = UDim2.fromScale((default - min) / (max - min), 1), BackgroundColor3 = C.Red, BorderSizePixel = 0, ZIndex = 4,
    }, bar)
    corner(fill, 3); gradient(fill, C.RedHi, C.Red, 0)
    local thumbGlow = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new((default - min) / (max - min), 0, 0.5, 0),
        Size = UDim2.fromOffset(22, 22), BackgroundColor3 = C.Red, BackgroundTransparency = 0.78,
        BorderSizePixel = 0, ZIndex = 4,
    }, bar)
    corner(thumbGlow, 11)
    local thumb = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new((default - min) / (max - min), 0, 0.5, 0),
        Size = UDim2.fromOffset(14, 14), BackgroundColor3 = C.Knob, BorderSizePixel = 0, ZIndex = 6,
    }, bar)
    corner(thumb, 7); stroke(thumb, C.Red, 1.5, 0.15)
    local dragging = false
    local curValue = default
    local function apply(value, fire)
        curValue = math.clamp(value, min, max)
        local pct = (curValue - min) / (max - min)
        local qi = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        tw(fill, qi, { Size = UDim2.fromScale(pct, 1) }):Play()
        tw(thumb, qi, { Position = UDim2.new(pct, 0, 0.5, 0) }):Play()
        tw(thumbGlow, qi, { Position = UDim2.new(pct, 0, 0.5, 0) }):Play()
        valLbl.Text = tostring(curValue) .. (suffix or "")
        if fire ~= false then callback(curValue) end
    end
    local function setFromX(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        apply(math.floor(min + (max - min) * rel + 0.5), true)
    end
    local hit = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 28), BackgroundTransparency = 1, Text = "", ZIndex = 7,
    }, f)
    Maid:Give(f.MouseEnter:Connect(function()
        tw(bar, SNAP, { Size = UDim2.new(1, -28, 0, 8), Position = UDim2.fromOffset(14, 37) }):Play()
        tw(thumbGlow, SNAP, { Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 0.68 }):Play()
    end))
    Maid:Give(f.MouseLeave:Connect(function()
        if not dragging then
            tw(bar, SNAP, { Size = UDim2.new(1, -28, 0, 6), Position = UDim2.fromOffset(14, 38) }):Play()
            tw(thumbGlow, SNAP, { Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 0.78 }):Play()
        end
    end))
    Maid:Give(hit.MouseButton1Down:Connect(function() dragging = true; setFromX(UserInputService:GetMouseLocation().X) end))
    Maid:Give(UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))
    Maid:Give(UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            setFromX(i.Position.X)
        end
    end))
    UIControls[text] = { get = function() return curValue end, set = function(v) apply(v, true) end }
    if desc then hint(page, desc) end
    return f
end

----------------------------------------------------------------------
-- Colour picker: swatch preview + three channel sliders. get/set keep the
-- "RRGGBB" hex contract so the JSON config engine round-trips it.
----------------------------------------------------------------------
colorpicker = function(page, text, default, callback, desc)
    local f = card(page, 104)
    new("TextLabel", {
        Size = UDim2.new(1, -72, 0, 20), Position = UDim2.fromOffset(14, 8), BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium, Text = text, TextColor3 = C.Text, TextSize = 12.5,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3,
    }, f)
    local swatch = new("Frame", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 8), Size = UDim2.fromOffset(40, 20),
        BackgroundColor3 = default, BorderSizePixel = 0, ZIndex = 3,
    }, f)
    corner(swatch, 6); stroke(swatch, C.Line, 1, 0.75)
    local r, g, b = math.floor(default.R * 255 + 0.5), math.floor(default.G * 255 + 0.5), math.floor(default.B * 255 + 0.5)
    local function fire()
        local col = Color3.fromRGB(r, g, b)
        swatch.BackgroundColor3 = col
        callback(col)
    end
    local function channel(yOff, chanColor, getv, setv)
        local barc = new("Frame", {
            Size = UDim2.new(1, -28, 0, 5), Position = UDim2.fromOffset(14, yOff), BackgroundColor3 = C.Ink4,
            BorderSizePixel = 0, ZIndex = 3,
        }, f)
        corner(barc, 3)
        local fillc = new("Frame", { Size = UDim2.fromScale(getv() / 255, 1), BackgroundColor3 = chanColor, BorderSizePixel = 0, ZIndex = 4 }, barc)
        corner(fillc, 3)
        local thumbc = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(getv() / 255, 0, 0.5, 0), Size = UDim2.fromOffset(11, 11),
            BackgroundColor3 = Color3.fromRGB(250, 250, 252), BorderSizePixel = 0, ZIndex = 6,
        }, barc)
        corner(thumbc, 6); stroke(thumbc, chanColor, 1.2, 0.2)
        local dragging = false
        local function setFromX(x)
            local rel = math.clamp((x - barc.AbsolutePosition.X) / barc.AbsoluteSize.X, 0, 1)
            setv(math.floor(rel * 255 + 0.5))
            fillc.Size = UDim2.fromScale(getv() / 255, 1)
            thumbc.Position = UDim2.new(getv() / 255, 0, 0.5, 0)
            fire()
        end
        local hit = new("TextButton", {
            Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, yOff - 5), BackgroundTransparency = 1, Text = "", ZIndex = 7,
        }, f)
        Maid:Give(hit.MouseButton1Down:Connect(function() dragging = true; setFromX(UserInputService:GetMouseLocation().X) end))
        Maid:Give(UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end))
        Maid:Give(UserInputService.InputChanged:Connect(function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then setFromX(i.Position.X) end
        end))
        return function() fillc.Size = UDim2.fromScale(getv() / 255, 1); thumbc.Position = UDim2.new(getv() / 255, 0, 0.5, 0) end
    end
    local refR = channel(42, Color3.fromRGB(227, 60, 60), function() return r end, function(v) r = v end)
    local refG = channel(64, Color3.fromRGB(70, 210, 90), function() return g end, function(v) g = v end)
    local refB = channel(86, Color3.fromRGB(70, 130, 235), function() return b end, function(v) b = v end)
    UIControls[text] = {
        get = function() return string.format("%02X%02X%02X", r, g, b) end,
        set = function(hex)
            if typeof(hex) == "Color3" then
                r, g, b = math.floor(hex.R * 255 + 0.5), math.floor(hex.G * 255 + 0.5), math.floor(hex.B * 255 + 0.5)
            elseif type(hex) == "string" and #hex >= 6 then
                r = tonumber(hex:sub(1, 2), 16) or r
                g = tonumber(hex:sub(3, 4), 16) or g
                b = tonumber(hex:sub(5, 6), 16) or b
            end
            refR(); refG(); refB(); fire()
        end,
    }
    task.spawn(fire)
    if desc then hint(page, desc) end
    return f
end

----------------------------------------------------------------------
-- Keybind picker: PC (keyboard) + Controller (gamepad), keycap styling.
----------------------------------------------------------------------
local function keyName(kc)
    if not kc or kc == Enum.KeyCode.Unknown then return "None" end
    return tostring(kc.Name)
end
keybind = function(page, text, getKb, setKb, getGp, setGp, desc)
    local f = card(page, 58)
    new("TextLabel", {
        Size = UDim2.new(1, -28, 0, 18), Position = UDim2.fromOffset(14, 7), BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium, Text = text, TextColor3 = C.Text, TextSize = 12.5,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3,
    }, f)
    new("TextLabel", {
        Position = UDim2.new(0, 14, 0, 30), Size = UDim2.fromOffset(24, 20), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, Text = "PC", TextColor3 = C.Low, TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 3,
    }, f)
    new("TextLabel", {
        Position = UDim2.new(0.5, 7, 0, 30), Size = UDim2.fromOffset(32, 20), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, Text = "CTRL", TextColor3 = C.Low, TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 3,
    }, f)
    local function mkBtn(posX, posOff, wOff)
        local b = new("TextButton", {
            Position = UDim2.new(posX, posOff, 0, 30), Size = UDim2.new(0.5, wOff, 0, 22),
            BackgroundColor3 = C.Ink4, BackgroundTransparency = 0.2, AutoButtonColor = false,
            Font = Enum.Font.GothamBold, Text = "", TextColor3 = C.Text, TextSize = 10.5, BorderSizePixel = 0, ZIndex = 4,
        }, f)
        corner(b, 6)
        local bs = stroke(b, C.Line, 1, 0.88)
        new("Frame", { -- keycap top glint
            Size = UDim2.new(1, -8, 0, 1), Position = UDim2.fromOffset(4, 2), BackgroundColor3 = C.Line,
            BackgroundTransparency = 0.85, BorderSizePixel = 0, ZIndex = 5,
        }, b)
        Maid:Give(b.MouseEnter:Connect(function()
            tw(b, SNAP, { BackgroundColor3 = C.Ink3, BackgroundTransparency = 0 }):Play()
            tw(bs, SNAP, { Color = C.Red, Transparency = 0.5 }):Play()
        end))
        Maid:Give(b.MouseLeave:Connect(function()
            tw(b, SNAP, { BackgroundColor3 = C.Ink4, BackgroundTransparency = 0.2 }):Play()
            tw(bs, SNAP, { Color = C.Line, Transparency = 0.88 }):Play()
        end))
        return b, bs
    end
    local kbBtn = mkBtn(0, 42, -54)
    local gpBtn = mkBtn(0.5, 42, -56)
    kbBtn.Text = keyName(getKb())
    gpBtn.Text = keyName(getGp())
    local function arm(which, btn, setter)
        if activeCapture then pcall(activeCapture.cancel) end
        local prevText = btn.Text
        btn.Text = "press…"; btn.BackgroundColor3 = C.Red
        activeCapture = {
            assign = function(kc, isGp)
                if which == "kb" and isGp then return false end
                if which == "gp" and not isGp then return false end
                setter(kc)
                btn.Text = keyName(kc)
                btn.BackgroundColor3 = C.Ink4
                activeCapture = nil
                return true
            end,
            cancel = function() btn.Text = prevText; btn.BackgroundColor3 = C.Ink4; activeCapture = nil end,
        }
    end
    Maid:Give(kbBtn.MouseButton1Click:Connect(function() arm("kb", kbBtn, setKb) end))
    Maid:Give(gpBtn.MouseButton1Click:Connect(function() arm("gp", gpBtn, setGp) end))
    table.insert(keybindRefreshers, function()
        kbBtn.Text = keyName(getKb())
        gpBtn.Text = keyName(getGp())
    end)
    if desc then hint(page, desc) end
    return f
end

----------------------------------------------------------------------
-- Label / note block: muted body text with a crimson tick. Returns the
-- TextLabel so callers can set .Text / .TextWrapped / .TextColor3.
----------------------------------------------------------------------
label = function(page, color)
    local f = new("Frame", {
        Size = UDim2.new(1, 0, 0, 24), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.Ink2,
        BackgroundTransparency = 0.2, BorderSizePixel = 0,
    }, page)
    corner(f, 9); stroke(f, C.Line, 1, 0.92)
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
        PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7),
    }, f)
    return new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 12), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium, Text = "", TextColor3 = color or C.Mid, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
    }, f)
end
----------------------------------------------------------------------
-- Game helpers
----------------------------------------------------------------------
local function getHRP(plr) local ch = plr.Character; return ch and ch:FindFirstChild("HumanoidRootPart"), ch end
local function myChar() return LP.Character end
local function myHRP() local c = LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function sameParty(p) local a, b = LP:FindFirstChild("Party"), p:FindFirstChild("Party"); return a and b and a.Value == b.Value end
local function isWhitelisted(p)
    if whitelist[p.UserId] then return true end
    if S.whitelistParty and sameParty(p) then return true end
    return false
end
local function validEnemy(p, char)
    if p == LP or not char then return false end
    if isWhitelisted(p) then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hv  = p:FindFirstChild("Health")
    if hv and hv.Value <= 0 then return false end
    return hrp ~= nil and hum ~= nil and hum.Health > 0
end
-- Part used for distance. Prefer Head — HRP flings hard during DiveRagdoll/KO and
-- would falsely put downed targets "out of range" of Kill Aura.
local function targetAnchor(char)
    if not char then return nil end
    return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
end
-- Closest of Head/HRP so standing + ragdolled both register correctly.
local function distToEnemy(fromPos, char)
    local best = math.huge
    local head = char:FindFirstChild("Head")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if head then best = math.min(best, (fromPos - head.Position).Magnitude) end
    if hrp then best = math.min(best, (fromPos - hrp.Position).Magnitude) end
    return best
end
local function nearest(range)
    local hrp = myHRP(); if not hrp then return nil end
    local best, bestD = nil, range or math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        local c = p.Character
        if validEnemy(p, c) then
            local d = distToEnemy(hrp.Position, c)
            if d < bestD then best, bestD = c, d end
        end
    end
    return best
end

----------------------------------------------------------------------
-- Combat helpers (real server contract: hits/slam need the "guarding" tag)
----------------------------------------------------------------------
local function guard() Combat:FireServer("Guarding") end
local function fists() Combat:FireServer("Fist") end

-- Post-BIG-UPDATE: the server only accepts guard/hit actions once your fists are equipped.
-- The real client fires "Hands" to equip on spawn; without it a fresh life's "Guarding" tag
-- never applies (verified live) and hits/slam are dropped. Equip on load + every respawn.
local function equipHands() pcall(function() Combat:FireServer("Hands") end) end
local kaStanceReady = false
local lastKaStance = 0
local lastKaUnblock = 0
task.spawn(function() task.wait(0.5); equipHands() end)
Maid:Give(LP.CharacterAdded:Connect(function()
    kaStanceReady = false
    lastKaStance = 0
    lastKaUnblock = 0
    task.wait(0.8)
    equipHands()
end))

-- Ragdoll detection (post-BIG-UPDATE): the "slammed"/"slamming" tags are gone; ragdoll now
-- shows as the Humanoid RagdollEnabled attribute / Physics state / the RagdollTrigger BoolValue
-- / the "DiveRagdoll" tag. Works on any character (local or enemy), all replicated.
local function isRagdolled(char)
    if not char then return false end
    local rt = char:FindFirstChild("RagdollTrigger")
    if rt and rt.Value then return true end
    local ok = pcall(function()
        return char:HasTag("DiveRagdoll") or char:HasTag("Slammed")
    end)
    if ok and (char:HasTag("DiveRagdoll") or char:HasTag("Slammed")) then return true end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        if hum:GetAttribute("RagdollEnabled") then return true end
        if hum.PlatformStand then return true end
        if hum:GetState() == Enum.HumanoidStateType.Physics then return true end
    end
    return false
end

-- Kill Aura: living enemies only (Health > 0). Includes ragdolled-but-alive so we finish
-- them on the floor. Dead KO corpses are skipped — they were starving the next target.
local function realHp(p)
    local hv = p and p:FindFirstChild("Health")
    return hv and hv.Value or 0
end
local function validKillTarget(p, char)
    if p == LP or not char or isWhitelisted(p) then return false end
    if not (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")) then return false end
    local dead = false
    pcall(function() dead = char:HasTag("Dead") end)
    if dead then return false end
    return realHp(p) > 0
end

-- All living enemies inside `range`. Sorted nearest-first. includeDowned keeps ragdolled-alive.
local function enemiesInRange(range, includeDowned)
    local hrp = myHRP(); if not hrp then return {} end
    local maxR = range or 7
    local out = {}
    for _, p in ipairs(Players:GetPlayers()) do
        local c = p.Character
        local ok
        if includeDowned then
            ok = validKillTarget(p, c)
        else
            ok = validEnemy(p, c) and not isRagdolled(c)
        end
        if ok and distToEnemy(hrp.Position, c) <= maxR then
            out[#out + 1] = { char = c, plr = p, d = distToEnemy(hrp.Position, c) }
        end
    end
    table.sort(out, function(a, b) return a.d < b.d end)
    local chars = {}
    for i = 1, #out do chars[i] = out[i].char end
    return chars
end

-- Block-break: detect if target is blocking so we can slam / dive through it.
local function targetIsBlocking(targetChar)
    if not targetChar then return false end
    local ok, res = pcall(function()
        return targetChar:HasTag("Blocking")
            or targetChar:HasTag("Perfect Block")
            or targetChar:HasTag("Block")
            or targetChar:HasTag("blocking")
    end)
    if ok and res then return true end
    -- Some builds only replicate the block tool / anim attribute
    local hum = targetChar:FindFirstChildOfClass("Humanoid")
    if hum and hum:GetAttribute("Blocking") then return true end
    return false
end

-- Block posture: server only sets the Blocking tag — no animation. We play the style's "Block"
-- anim (arms-up defend), NOT "Guard" (fists standby). Guard stays playing at Action4 weight 6
-- while fists are out, so we must damp Guard + Idle or Block never reads.
local CombatAnims = ReplicatedStorage:FindFirstChild("Animations") and ReplicatedStorage.Animations:FindFirstChild("Combat")
local blockTrack = nil
local blockDampedTracks = nil
local function styleFolder()
    if not CombatAnims then return nil end
    local sv = LP:FindFirstChild("UserData") and LP.UserData:FindFirstChild("Style")
    local name = (sv and sv.Value) or "Default"
    local folder
    for _, f in ipairs(CombatAnims:GetChildren()) do
        if f:IsA("Folder") and f.Name:lower() == tostring(name):lower() then folder = f; break end
    end
    return folder or CombatAnims:FindFirstChild("Default")
end
local function styleBlockAnim()
    local folder = styleFolder()
    -- Prefer Block (real defend pose). Guard is standby fists — only use if Block is missing.
    return folder and (folder:FindFirstChild("Block") or folder:FindFirstChild("Guard"))
end
local function playBlockAnim()
    pcall(function()
        if blockTrack and blockTrack.IsPlaying then return end
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        local anim = styleBlockAnim()
        if not (animator and anim) then return end
        -- damp Guard (standby) + Idle on Action4 so Block wins the blend
        blockDampedTracks = {}
        for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
            if t.Priority == Enum.AnimationPriority.Action4 and (t.Name == "Idle" or t.Name == "Guard") then
                table.insert(blockDampedTracks, { track = t, weight = t.WeightCurrent > 0 and t.WeightCurrent or 1 })
                pcall(function() t:AdjustWeight(0.05, 0.08) end)
            end
        end
        blockTrack = animator:LoadAnimation(anim)
        blockTrack.Looped = true
        blockTrack.Priority = Enum.AnimationPriority.Action4
        blockTrack:Play(0.08, 10, 1) -- weight 10 beats residual Guard
    end)
end
local function stopBlockAnim()
    if blockTrack then pcall(function() blockTrack:Stop(0.12) end); blockTrack = nil end
    if blockDampedTracks then
        for _, entry in ipairs(blockDampedTracks) do
            local t, w = entry.track, entry.weight or 1
            pcall(function()
                if t and t.IsPlaying then t:AdjustWeight(w, 0.12) end
            end)
        end
        blockDampedTracks = nil
    end
end
-- Auto Block alone = silent Block remote. Safe Block + Auto Block + Guard out = real Block pose.
-- Anim only right after a real L/R/kick swing starts — never from proximity alone.
S._wantBlockAnim = function()
    if not (S.autoBlock and S.safeBlock) or S.godmode then return false end
    local c = LP.Character
    if not (c and c:HasTag("Guarding")) then return false end
    return (tick() - (lastIncoming or 0)) <= 0.22
end

-- Safe Mode: play your real punch animation (alternating L/R of the equipped style).
-- speed (optional) scales playback. Returns the AnimationTrack so callers can gate on it.
local punchToggle = false
local function playPunchAnim(speed)
    -- Mark that WE are swinging: the AnimationPlayed hook keys reach/rapid off attack
    -- anims, and our own synthetic swings look identical to a real punch — this window
    -- stops them from feeding back into reach/rapid (auto-hits / "speed of light").
    S.selfSwingUntil = tick() + 0.25
    local track
    pcall(function()
        if not CombatAnims then return end
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if not animator then return end
        local sv = LP:FindFirstChild("UserData") and LP.UserData:FindFirstChild("Style")
        local name = (sv and sv.Value) or "Default"
        local folder
        for _, f in ipairs(CombatAnims:GetChildren()) do
            if f:IsA("Folder") and f.Name:lower() == name:lower() then folder = f; break end
        end
        folder = folder or CombatAnims:FindFirstChild("Default")
        punchToggle = not punchToggle
        local anim = folder and (punchToggle and folder:FindFirstChild("L") or folder:FindFirstChild("R"))
        if not anim then
            anim = folder and (folder:FindFirstChild("Punch") or folder:FindFirstChild("Attack"))
        end
        if anim then
            -- Dip guard stance so the swing reads clearly
            if blockTrack and blockTrack.IsPlaying then
                pcall(function() blockTrack:AdjustWeight(0.15, 0.05) end)
            end
            track = animator:LoadAnimation(anim)
            track.Priority = Enum.AnimationPriority.Action4
            track:Play(0.05, 1, speed or 1)
            if speed and speed ~= 1 then track:AdjustSpeed(speed) end
            pcall(function()
                track.Stopped:Connect(function()
                    if blockTrack and blockTrack.IsPlaying then
                        pcall(function() blockTrack:AdjustWeight(10, 0.12) end)
                    end
                end)
            end)
        end
    end)
    return track
end
-- Rapid Punch: play the swing fast (1.5x) but let it fully complete before starting another,
-- so it reads as a fast-but-whole punch rather than a stuttering loop.
local rapidTrack = nil
local function playRapidPunchAnim()
    if rapidTrack and rapidTrack.IsPlaying then return end
    rapidTrack = playPunchAnim(1.5)
end

----------------------------------------------------------------------
-- v2533 damage model (live Player.FireHit contract)
----------------------------------------------------------------------
-- Damage is still Combat:FireServer("Body"|"Head", targetChar, roundKick) — same as the client's
-- FireHit. The cooldown table u40 only gates Fist/Hands/Guarding/Unguard/Block/Unblock; Body/Head
-- are not client-cooled. Enter combat is Fist -> Guarding; Hands is for LEAVING combat (do NOT
-- fire Hands before a hit). Server distance-checks hits (~7 studs) and kicks on large teleports
-- (Err 267), so we close with bounded hops. Slam is still Combat "Slam"+target on contact (needs
-- meter); knockdown without meter uses Player "Dived On".
-- Scoped in a do-block and exposed on S.* so it adds ZERO top-level locals. Call sites use
-- S.landHit, S.boundedApproach, S.boundedTeleport, S.ragdollHit, S.diveRagdoll.
do
    local PlayerRemoteTop = Remotes and Remotes:FindFirstChild("Player")
    local HIT_RANGE = 7          -- server hit distance check (studs)
    local MAX_HOP   = 14         -- max studs moved per hop before position AC risks flagging
    S.hitRange = HIT_RANGE

    local function faceTowards(hrp, pos)
        local flat = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z)
        if flat.Magnitude > 0.05 then
            hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + flat.Unit)
        end
    end

    -- Ensure Fist -> Guarding stance (never Hands — that leaves combat).
    local function ensureGuarding()
        local c = myChar()
        if not c then return false end
        if not c:HasTag("Guarding") then
            Combat:FireServer("Fist", nil, nil)
            Combat:FireServer("Guarding", nil, nil)
            local t0 = tick()
            while tick() - t0 < 0.2 do
                if c:HasTag("Guarding") then break end
                task.wait()
            end
        end
        return c:HasTag("Guarding") or true
    end

    -- Teleport that never exceeds MAX_HOP in a single jump: for longer distances it steps the
    -- character there, waiting a frame between hops so the position AC sees a series of plausible
    -- deltas instead of one flag-worthy jump. `faceDir` orients you at the destination.
    local function boundedTeleport(destPos, faceDir)
        local hrp = myHRP(); if not hrp then return false end
        for _ = 1, 600 do
            local gap = (destPos - hrp.Position).Magnitude
            if gap <= 0.5 then break end
            local step = math.min(gap, MAX_HOP)
            local dir = (destPos - hrp.Position).Unit
            local nextPos = hrp.Position + dir * step
            local flat = Vector3.new(dir.X, 0, dir.Z)
            if flat.Magnitude > 0.05 then
                hrp.CFrame = CFrame.new(nextPos, nextPos + flat.Unit)
            else
                hrp.CFrame = CFrame.new(nextPos)
            end
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            if gap <= MAX_HOP then break end
            task.wait(0.05)
            hrp = myHRP(); if not hrp then return false end
        end
        local fh = myHRP()
        if fh and faceDir then
            local flat = Vector3.new(faceDir.X, 0, faceDir.Z)
            if flat.Magnitude > 0.05 then fh.CFrame = CFrame.new(fh.Position, fh.Position + flat.Unit) end
        end
        return true
    end

    -- Close to within hit range of `pos` using bounded hops, stopping `stopDist` studs short so we
    -- land just inside range rather than clipping into the target. Returns the final flat distance.
    local function boundedApproach(pos, stopDist)
        local hrp = myHRP(); if not hrp then return math.huge end
        stopDist = math.max(stopDist or (HIT_RANGE - 1), 1)
        for _ = 1, 8 do
            local flatGap = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(hrp.Position.X, 0, hrp.Position.Z)).Magnitude
            if flatGap <= stopDist then break end
            local step = math.min(flatGap - stopDist, MAX_HOP)
            local dir = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z).Unit
            local dest = hrp.Position + dir * step
            hrp.CFrame = CFrame.new(dest, dest + dir)
            hrp.AssemblyLinearVelocity = Vector3.zero
            task.wait(0.05)
            hrp = myHRP(); if not hrp then return math.huge end
        end
        local fh = myHRP()
        return fh and (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(fh.Position.X, 0, fh.Position.Z)).Magnitude or math.huge
    end

    -- Land a hit matching FireHit: Fist->Guarding, then Body/Head + target + roundKick.
    -- Never fires Hands (that leaves combat).
    -- noMove=true: never hop/TP — only hit if already inside HIT_RANGE (Kill Aura).
    -- skipAnim=true: skip local punch anim for faster spam.
    local function landHit(targetChar, maxRange, useHead, noMove, skipAnim)
        if not isCombatSafe() then return false end
        local hrp = myHRP()
        local thrp = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
        if not (hrp and thrp) then return false end
        local gap = (thrp.Position - hrp.Position).Magnitude
        if maxRange and gap > maxRange then return false end
        if gap > HIT_RANGE then
            if noMove then return false end
            boundedApproach(thrp.Position, HIT_RANGE - 1)
            hrp = myHRP(); thrp = targetChar:FindFirstChild("HumanoidRootPart")
            if not (hrp and thrp) then return false end
            gap = (thrp.Position - hrp.Position).Magnitude
            if gap > HIT_RANGE then return false end
        end
        if not noMove then faceTowards(hrp, thrp.Position) end
        ensureGuarding()
        Combat:FireServer(useHead and "Head" or "Body", targetChar, false)
        if not skipAnim then playPunchAnim() end
        return true
    end

    -- Slam / dive knockdown. NEVER CFrame-approaches (desyncs hitreg + Error 267).
    -- Real client: FireCombat("Slam", character) after grab contact; dive = Player "Dived On".
    -- We fire Slam then Dive from melee only. approach=true uses Humanoid:MoveTo (walk), not TP.
    local function ragdollHit(targetChar, approach)
        if not targetChar then return false end
        local thrp = targetChar:FindFirstChild("HumanoidRootPart")
        local hrp = myHRP()
        if not (thrp and hrp) then return false end

        local gap = (thrp.Position - hrp.Position).Magnitude
        if gap > HIT_RANGE then
            if not approach then return false end
            local hum = myChar() and myChar():FindFirstChildOfClass("Humanoid")
            if not hum then return false end
            local t0 = tick()
            while tick() - t0 < 0.9 do
                thrp = targetChar:FindFirstChild("HumanoidRootPart")
                hrp = myHRP()
                if not (thrp and hrp) then return false end
                gap = (thrp.Position - hrp.Position).Magnitude
                if gap <= HIT_RANGE - 0.5 then break end
                hum:MoveTo(thrp.Position)
                task.wait(0.05)
            end
            thrp = targetChar:FindFirstChild("HumanoidRootPart")
            hrp = myHRP()
            if not (thrp and hrp) then return false end
            if (thrp.Position - hrp.Position).Magnitude > HIT_RANGE then return false end
        end

        faceTowards(hrp, thrp.Position)
        ensureGuarding()
        -- Dive first (no slam-meter gate). Slam also fired in case meter is charged.
        if PlayerRemoteTop then
            PlayerRemoteTop:FireServer("Dived On", targetChar)
        end
        Combat:FireServer("Slam", targetChar)
        return true
    end

    local function diveRagdoll(targetChar, approach)
        if not targetChar or not PlayerRemoteTop then return false end
        local thrp = targetChar:FindFirstChild("HumanoidRootPart")
        local hrp = myHRP()
        if not (thrp and hrp) then return false end
        local gap = (thrp.Position - hrp.Position).Magnitude
        if gap > HIT_RANGE then
            if not approach then return false end
            local hum = myChar() and myChar():FindFirstChildOfClass("Humanoid")
            if not hum then return false end
            local t0 = tick()
            while tick() - t0 < 0.9 do
                thrp = targetChar:FindFirstChild("HumanoidRootPart")
                hrp = myHRP()
                if not (thrp and hrp) then return false end
                if (thrp.Position - hrp.Position).Magnitude <= HIT_RANGE - 0.5 then break end
                hum:MoveTo(thrp.Position)
                task.wait(0.05)
            end
            thrp = targetChar:FindFirstChild("HumanoidRootPart")
            hrp = myHRP()
            if not (thrp and hrp) then return false end
            if (thrp.Position - hrp.Position).Magnitude > HIT_RANGE then return false end
        end
        faceTowards(hrp, thrp.Position)
        PlayerRemoteTop:FireServer("Dived On", targetChar)
        return true
    end

    S.landHit         = landHit
    S.boundedApproach = boundedApproach
    S.boundedTeleport = boundedTeleport
    S.ragdollHit      = ragdollHit
    S.diveRagdoll     = diveRagdoll
end

----------------------------------------------------------------------
-- Combat cooldown bypass (client Slam meter UI + FireCombat debounce +
-- StartCombatCooldown indicators). Server still owns real slam charge, so we
-- always Dive as the reliable knockdown; this clears the stuck CD UI that
-- makes toggles feel like they "won't turn off".
--
-- PERF: never scan getgc on Heartbeat. Cache upvalues once (refresh rarely)
-- and only wipe those tables on demand (slam / hotkey).
----------------------------------------------------------------------
do
    local hookedStartCd = false
    local lastBypassSweep = 0
    local lastGcRefresh = 0
    local cachedSlamFn, cachedSlamIdx = nil, nil
    local cachedCdTables = {}

    local function clearCooldownGui()
        pcall(function()
            local pg = LP:FindFirstChild("PlayerGui")
            if not pg then return end
            local cds = pg:FindFirstChild("Cooldowns", true)
            if not cds then
                for _, d in ipairs(pg:GetChildren()) do
                    local c = d:FindFirstChild("Cooldowns", true)
                    if c then cds = c; break end
                end
            end
            if not cds then return end
            for _, c in ipairs(cds:GetChildren()) do
                if c.Name ~= "IndicatorTemplate" and c:IsA("GuiObject") then
                    pcall(function() c:Destroy() end)
                end
            end
        end)
    end

    local function refreshGcCache()
        cachedSlamFn, cachedSlamIdx = nil, nil
        cachedCdTables = {}
        if typeof(getgc) ~= "function" then return end
        pcall(function()
            for _, fn in ipairs(getgc(false)) do
                if typeof(fn) == "function" then
                    local ok, name = pcall(debug.info, fn, "n")
                    if ok and name then
                        if name == "SetSlamUI" and typeof(debug.setupvalue) == "function" then
                            local ups = debug.getupvalues(fn)
                            for i, v in pairs(ups) do
                                if typeof(v) == "number" and v <= 100 then
                                    cachedSlamFn, cachedSlamIdx = fn, i
                                    break
                                end
                            end
                        elseif name == "FireCombat" or name == "StartCombatCooldown" then
                            local ups = debug.getupvalues(fn)
                            for _, v in pairs(ups) do
                                if typeof(v) == "table" then
                                    cachedCdTables[#cachedCdTables + 1] = v
                                end
                            end
                        end
                    end
                end
            end
        end)
        lastGcRefresh = tick()
    end

    local function hookStartCombatCooldown()
        if hookedStartCd or typeof(getgc) ~= "function" or typeof(hookfunction) ~= "function" then return end
        pcall(function()
            for _, fn in ipairs(getgc(false)) do
                if typeof(fn) == "function" then
                    local ok, name = pcall(debug.info, fn, "n")
                    if ok and name == "StartCombatCooldown" then
                        hookfunction(fn, function(...) return nil end)
                        hookedStartCd = true
                        break
                    end
                end
            end
        end)
    end

    function S.bypassCombatCooldowns(force)
        local now = tick()
        if not force and (now - lastBypassSweep) < 2.0 then return end
        lastBypassSweep = now

        if (not cachedSlamFn and #cachedCdTables == 0) or (now - lastGcRefresh) > 30 then
            refreshGcCache()
            hookStartCombatCooldown()
        end

        if cachedSlamFn and cachedSlamIdx and typeof(debug.setupvalue) == "function" then
            pcall(debug.setupvalue, cachedSlamFn, cachedSlamIdx, 100)
        end
        for _, t in ipairs(cachedCdTables) do
            for k, val in pairs(t) do
                if typeof(val) == "number" then
                    t[k] = 0
                elseif typeof(k) == "string" and (typeof(val) == "table" or typeof(val) == "thread") then
                    t[k] = nil
                end
            end
        end
        if force then clearCooldownGui() end
    end

    function S.resetSlamTimers()
        lastSlam = 0
        lastAutoSlam = 0
        lastHotkeySlam = 0
    end

    -- No Heartbeat getgc loop — that hitch'd FPS every ~0.35s whenever combat toggles were on.
end

local function playSound(name, url, volume, parent)
    pcall(function()
        local sound = Instance.new("Sound")
        local localName = "CAF2_" .. name
        local sId = ""
        if typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(getcustomasset) == "function" then
            pcall(function()
                local data = nil
                if isfile(localName) then
                    data = readfile(localName)
                end
                if not data or #data < 500 then
                    data = game:HttpGet(url)
                    if data and #data > 500 then
                        writefile(localName, data)
                    else
                        data = nil
                    end
                end
                if data then
                    sId = getcustomasset(localName)
                end
            end)
        end
        if not sId or sId == "" then
            if name:lower():find("whoosh") then
                sId = "rbxasset://sounds/action_swipe.mp3"
            else
                sId = "rbxasset://sounds/thunder.mp3"
            end
        end
        sound.SoundId = sId
        sound.Volume = volume or 1
        sound.Parent = parent or workspace.CurrentCamera
        sound:Play()
        task.delay(5, function()
            sound:Destroy()
        end)
    end)
end

local function playATrainFX(originPos, destPos)
    pcall(function()
        local folder = Instance.new("Folder")
        folder.Name = "CAF2_ATrainFX"
        folder.Parent = Workspace
        playSound("whoosh.wav", "https://remotion.media/whoosh.wav", 0.6)
        local function createSonicBoom(pos)
            local boom = Instance.new("Part")
            boom.Shape = Enum.PartType.Ball
            boom.Size = Vector3.new(1, 1, 1)
            boom.Color = Color3.fromRGB(240, 245, 255)
            boom.Material = Enum.Material.ForceField
            boom.Transparency = 0.75
            boom.Anchored = true
            boom.CanCollide = false
            boom.CanQuery = false
            boom.CanTouch = false
            boom.CFrame = CFrame.new(pos)
            boom.Parent = folder
            local att = Instance.new("Attachment")
            att.CFrame = CFrame.new(0, -2, 0)
            att.Parent = boom
            local emitter = Instance.new("ParticleEmitter")
            emitter.Texture = "rbxassetid://243098098"
            emitter.Color = ColorSequence.new(Color3.fromRGB(220, 220, 225), Color3.fromRGB(160, 160, 165))
            emitter.Size = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 2),
                NumberSequenceKeypoint.new(1, 10)
            })
            emitter.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.5),
                NumberSequenceKeypoint.new(1, 1)
            })
            emitter.Lifetime = NumberRange.new(0.5, 1.0)
            emitter.Rate = 0
            emitter.Speed = NumberRange.new(15, 25)
            emitter.SpreadAngle = Vector2.new(360, 0)
            emitter.VelocitySpread = 360
            emitter.Parent = att
            emitter:Emit(35)
            task.spawn(function()
                for i = 1, 12 do
                    local t = i / 12
                    boom.Size = Vector3.new(1, 1, 1) * (1 + t * 11)
                    boom.Transparency = 0.75 + t * 0.25
                    task.wait(0.02)
                end
                boom:Destroy()
            end)
        end
        createSonicBoom(destPos)
        if originPos then
            createSonicBoom(originPos)
            local diff = destPos - originPos
            local dist = diff.Magnitude
            local steps = math.floor(dist / 3)
            for i = 1, steps do
                task.spawn(function()
                    task.wait(i * 0.006)
                    local p = originPos:Lerp(destPos, i / steps)
                    local windPart = Instance.new("Part")
                    windPart.Size = Vector3.new(1, 1, 1)
                    windPart.Anchored = true
                    windPart.CanCollide = false
                    windPart.CanQuery = false
                    windPart.CanTouch = false
                    windPart.Transparency = 1
                    windPart.CFrame = CFrame.new(p)
                    windPart.Parent = folder
                    local emitter = Instance.new("ParticleEmitter")
                    emitter.Texture = "rbxassetid://305417387"
                    emitter.Color = ColorSequence.new(Color3.fromRGB(240, 245, 255))
                    emitter.Size = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 1.5),
                        NumberSequenceKeypoint.new(1, 5)
                    })
                    emitter.Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0.4),
                        NumberSequenceKeypoint.new(1, 1)
                    })
                    emitter.Lifetime = NumberRange.new(0.25, 0.5)
                    emitter.Rate = 0
                    emitter.Speed = NumberRange.new(8, 16)
                    emitter.VelocitySpread = 60
                    emitter.Parent = windPart
                    emitter:Emit(4)
                    task.delay(0.8, function() windPart:Destroy() end)
                    
                    local char = myChar()
                    if char then
                        local ghost = Instance.new("Model")
                        ghost.Name = "CAF2_ATrainGhost"
                        ghost.Parent = folder
                        local count = 0
                        for _, desc in ipairs(char:GetDescendants()) do
                            if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" and desc.Transparency < 1 then
                                local clone = desc:Clone()
                                clone:ClearAllChildren()
                                clone.Anchored = true
                                clone.CanCollide = false
                                clone.CanQuery = false
                                clone.CanTouch = false
                                clone.Material = Enum.Material.Neon
                                clone.Color = Color3.fromRGB(64, 180, 255)
                                clone.Transparency = 0.7
                                local offset = char.HumanoidRootPart.CFrame:ToObjectSpace(desc.CFrame)
                                clone.CFrame = CFrame.new(p) * char.HumanoidRootPart.CFrame.Rotation * offset
                                clone.Parent = ghost
                                count = count + 1
                            end
                        end
                        if count > 0 then
                            task.spawn(function()
                                for k = 1, 10 do
                                    for _, part in ipairs(ghost:GetChildren()) do
                                        if part:IsA("BasePart") then
                                            part.Transparency = 0.7 + k * 0.03
                                        end
                                    end
                                    task.wait(0.02)
                                end
                                ghost:Destroy()
                            end)
                        else
                            ghost:Destroy()
                        end
                    end
                end)
            end
        end
        task.delay(3, function()
            folder:Destroy()
        end)
    end)
end

local function slam(targetChar)
    local thrp = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
    if thrp and S.aTrainFX then
        playATrainFX(nil, thrp.Position)
    end
    -- Walk-close if needed, then Slam + Dive fallback. No CFrame hops.
    return S.ragdollHit(targetChar, true)
end

function reachPunch()
    if not S.reach or not isCombatSafe() then return end
    -- never swing while knocked down / ragdolled / dead
    local c0 = myChar()
    local h0 = c0 and c0:FindFirstChildOfClass("Humanoid")
    if not h0 or h0.Health <= 0 or h0.PlatformStand then return end
    local tr0 = c0 and c0:FindFirstChild("RagdollTrigger")
    if tr0 and tr0.Value then return end
    local now = tick()
    if now - (S.lastReach or 0) < 0.2 then return end
    S.lastReach = now
    local t = nearest(S.reachRange or 30)
    if not t then return end
    task.spawn(function()
        local wasBlocking = isBlocking
        if wasBlocking then
            isBlocking = false
            Combat:FireServer("Unblock", nil, nil)
            blockSuppressUntil = tick() + 0.12
            task.wait(0.02)
        end
        -- Bounded-hop into hit range, then FireHit-style Body damage.
        S.landHit(t, S.reachRange or 30, false)
    end)
end

-- Rapid Punch: a short fast burst at the nearest target, fired ONLY when you actually punch
-- (left/right click, RT/LT, or — on mobile — the game's own attack, detected via its punch
-- animation). Debounced so it never free-runs and so our own swing anim can't re-trigger it.
local function rapidPunchBurst()
    if not S.rapidPunch then return end
    local now = tick()
    if now - lastRapidBurst < 0.12 then return end
    lastRapidBurst = now
    playRapidPunchAnim()
    local t = nearest(S.rapidPunchRange or S.paRange)
    if not t then return end
    task.spawn(function()
        for _ = 1, 4 do
            if not (t and t.Parent) then break end
            if not S.landHit(t, S.rapidPunchRange or S.paRange, false) then break end
            task.wait(0.06)
        end
    end)
end

-- Safe Block gate: only guard while the character is actually on its feet. The same signals
-- the game's own ToggleRagdoll keys off — Humanoid attr RagdollEnabled, the RagdollTrigger
-- BoolValue, PlatformStand, and the Physics/Ragdoll/Freefall states — mark "knocked over or
-- falling". When any is set we can't legitimately guard, so safe block releases instead of
-- holding a block through a ragdoll (which looks blatant and does nothing while you're down).
local NON_GUARD_STATES = {
    [Enum.HumanoidStateType.Physics]     = true,
    [Enum.HumanoidStateType.Ragdoll]     = true,
    [Enum.HumanoidStateType.FallingDown] = true,
    [Enum.HumanoidStateType.Freefall]    = true,
    [Enum.HumanoidStateType.Flying]      = true,
    [Enum.HumanoidStateType.Dead]        = true,
    [Enum.HumanoidStateType.PlatformStanding] = true,  -- CAF2 knockdown lands here
    [Enum.HumanoidStateType.GettingUp]   = true,       -- don't guard mid-recovery (stand-up)
}
local function canGuard()
    local c = myChar(); if not c then return false end
    local hum = c:FindFirstChildOfClass("Humanoid"); if not hum then return false end
    if hum.Health <= 0 or hum.PlatformStand then return false end
    if hum:GetAttribute("RagdollEnabled") then return false end
    local trig = c:FindFirstChild("RagdollTrigger")
    if trig and trig:IsA("BoolValue") and trig.Value then return false end
    if NON_GUARD_STATES[hum:GetState()] then return false end
    local ph = LP:FindFirstChild("Health")        -- server-owned real health
    if ph and ph:IsA("NumberValue") and ph.Value <= 0 then return false end
    return true
end

-- Defensive-block detection for Kill Aura / auto-block. The "guarding" tag only means your fight tool is
-- equipped (you need it to attack too), so it is NOT a block. A real block sets "blocking" /
-- "perfect block", which flicker as the tag breaks and re-applies — so debounce over a short window.
lastBlockSeen = 0
local function guardIsUp()
    if isBlocking then return true end
    local c = myChar()
    if c and (c:HasTag("Blocking") or c:HasTag("Perfect Block")) then
        lastBlockSeen = tick(); return true
    end
    return tick() - lastBlockSeen <= 0.4
end

function isCombatSafe()
    if not S.safeEverything then return true end
    local c = myChar()
    if not c then return false end
    local hasGuard = c:HasTag("Guarding") or guardIsUp()
    return canGuard() or hasGuard
end

----------------------------------------------------------------------
-- Kill Aura: in-place Head spam (NO hop/TP).
-- DOES NOT use isCombatSafe / Global Safe Mode — that was killing DPS after the
-- first KO (Hands drops Guarding → Safe Mode returns false → aura freezes).
----------------------------------------------------------------------
local lastPunch = 0
local lastKaFocus = nil

local function clearSelfSoftLock(char)
    if not char then return end
    pcall(function()
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.PlatformStand = false
            if hum:GetAttribute("RagdollEnabled") then hum:SetAttribute("RagdollEnabled", false) end
            local st = hum:GetState()
            if st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.Ragdoll
                or st == Enum.HumanoidStateType.FallingDown then
                hum:ChangeState(Enum.HumanoidStateType.Running)
            end
        end
        local trig = char:FindFirstChild("RagdollTrigger")
        if trig and trig:IsA("BoolValue") then trig.Value = false end
    end)
end

-- Returns true when Guarding is on. If not, fires Fist/Guarding (rate-limited) but
-- callers may still fire Head the same tick — waiting for the tag was freezing DPS.
local function ensureKaStance(char, now, force)
    if not char then return false end
    local guarding = false
    pcall(function() guarding = char:HasTag("Guarding") end)
    if guarding then
        kaStanceReady = true
        return true
    end
    if force or (now - lastKaStance) >= 0.15 then
        lastKaStance = now
        Combat:FireServer("Fist", nil, nil)
        Combat:FireServer("Guarding", nil, nil)
    end
    return false
end

-- Kill Aura: nearest living enemy. Multi-Head every Heartbeat. Never waits on
-- Guarding tag, never faces, never Slam/Dive. Auto Block / Godmode / Ragdoll Aura
-- must not interrupt while KA is on (that was the random multi-second stalls).
local tryKillAura, tryRagdollAura
do
    local lastDiveAt = setmetatable({}, { __mode = "k" })
    local lastSeenHp = setmetatable({}, { __mode = "k" })
    local lastHurtAt = setmetatable({}, { __mode = "k" })
    local lastRagdollAura = 0

    local function noteTargetHp(t)
        local plr = Players:GetPlayerFromCharacter(t)
        if not plr then return end
        local hv = plr:FindFirstChild("Health")
        if not (hv and hv:IsA("NumberValue")) then return end
        local nowHp, prev = hv.Value, lastSeenHp[t]
        if prev and nowHp < prev then
            lastHurtAt[t] = tick()
        end
        lastSeenHp[t] = nowHp
    end

    local function recentlyHurt(t, now)
        local tHurt = lastHurtAt[t]
        return tHurt and (now - tHurt) < 2.5
    end

    local function isDeadChar(t)
        if not t or not t.Parent then return true end
        local dead = false
        pcall(function() dead = t:HasTag("Dead") end)
        if dead then return true end
        local plr = Players:GetPlayerFromCharacter(t)
        if plr then
            local hv = plr:FindFirstChild("Health")
            if hv and hv.Value <= 0 then return true end
        end
        return false
    end

    local function canDiveTarget(t, now)
        if not t or isRagdolled(t) or isDeadChar(t) then return false end
        local prev = lastDiveAt[t]
        if prev and (now - prev) < 0.35 then return false end
        if S.killAura then
            if targetIsBlocking(t) then return true end
            if not recentlyHurt(t, now) then return false end
        end
        return true
    end

    local function markDive(t, now)
        lastDiveAt[t] = now
    end

    tryKillAura = function()
        if not S.killAura then return end
        local char = myChar()
        if not char then return end
        if isRagdolled(char) then clearSelfSoftLock(char) end

        local now = tick()
        -- Soft floor so bursts stay steady and don't trip CAF remote-rate kicks.
        local cd = math.max(tonumber(S.paCD) or 0.07, 0.05)
        if (now - lastPunch) < cd then return end

        blockSuppressUntil = now + 1.0
        local blocking = isBlocking
        if not blocking then
            pcall(function()
                blocking = char:HasTag("Blocking") or char:HasTag("Perfect Block")
            end)
        end
        if blocking then
            isBlocking = false
            Combat:FireServer("Unblock", nil, nil)
            stopBlockAnim()
            lastKaUnblock = now
        end

        -- Need Guarding for Head to count. Ask once, then wait — don't Head while out of combat.
        local guarding = false
        pcall(function() guarding = char:HasTag("Guarding") end)
        if not guarding then
            if (now - lastKaStance) >= 0.3 then
                lastKaStance = now
                Combat:FireServer("Fist", nil, nil)
                Combat:FireServer("Guarding", nil, nil)
            end
            return
        end

        local hitRange = S.hitRange or 7
        local auraRange = math.min(tonumber(S.paRange) or hitRange, hitRange)

        -- Sticky player, always re-resolve to live Character (stale char = 0 damage).
        local focus, focusPlr = nil, nil
        if lastKaFocus and lastKaFocus.Parent then
            focusPlr = Players:GetPlayerFromCharacter(lastKaFocus)
        end
        if focusPlr and focusPlr.Character and focusPlr.Character.Parent then
            focus = focusPlr.Character
            if isDeadChar(focus) then
                focus, focusPlr = nil, nil
                lastKaFocus = nil
            else
                local hrp = myHRP()
                if not hrp or distToEnemy(hrp.Position, focus) > (auraRange + 1.5) then
                    focus, focusPlr = nil, nil
                    lastKaFocus = nil
                end
            end
        else
            lastKaFocus = nil
        end
        if not focus then
            for _, t in ipairs(enemiesInRange(auraRange, true)) do
                if not isDeadChar(t) then
                    focus = t
                    focusPlr = Players:GetPlayerFromCharacter(t)
                    break
                end
            end
        end
        if not focus then
            lastKaFocus = nil
            return
        end
        if focusPlr and focusPlr.Character then
            focus = focusPlr.Character
        end
        if isDeadChar(focus) then
            lastKaFocus = nil
            return
        end

        lastKaFocus = focus
        lastPunch = now

        local hits = math.clamp(math.floor(tonumber(S.paHits) or 2), 1, 4)
        for _ = 1, hits do
            Combat:FireServer("Head", focus, false)
        end

        local dbg = S.kaDebug
        if type(dbg) ~= "table" then
            dbg = { heads = 0, t0 = now }
            S.kaDebug = dbg
        end
        dbg.heads = (dbg.heads or 0) + hits
        dbg.lastFire = now
        dbg.focus = focusPlr and focusPlr.Name or focus.Name
    end

    tryRagdollAura = function()
        -- Never dive while Kill Aura is melting — Dived On soft-locks Head damage.
        if S.killAura then return end
        if not S.ragdollAura then return end
        local char = myChar()
        if not char then return end
        clearSelfSoftLock(char)
        local now = tick()
        if now - lastRagdollAura < math.max(S.raCD or 0, 0) then return end
        local maxR = math.min(S.raRange or 6, 7)
        local targets = enemiesInRange(maxR, false)
        if #targets == 0 then return end
        local PlayerRemote = Remotes and Remotes:FindFirstChild("Player")
        if not PlayerRemote then return end
        ensureKaStance(char, now, false)
        local any = false
        for _, t in ipairs(targets) do
            noteTargetHp(t)
            if canDiveTarget(t, now) then
                any = true
                markDive(t, now)
                PlayerRemote:FireServer("Dived On", t)
            end
        end
        if any then lastRagdollAura = now end
    end
end

-- Auto block: fire "block" ONCE per engage (server rate-limits it to 0.05s, so spamming it
-- every frame means the blocking tag never applies). Re-fire only to recover from breaks.
local function block()
    local c = myChar(); if not c then return end
    local now = tick()
    if not c:HasTag("Guarding") then
        if S.safeBlock then return end          -- safe: ride your equipped guard, never force it on
        fpBlockForcedGuard = true              -- do NOT trigger First Person from this force-equip
        Combat:FireServer("Fist", nil, nil)
        Combat:FireServer("Guarding", nil, nil)
        -- Server rejects Block until Guarding sticks — defer the first Block fire.
        if not isBlocking then
            isBlocking = true
            lastBlockFire = now
            task.delay(0.06, function()
                if not isBlocking or not isCurrent() then return end
                local ch = myChar()
                if not ch then return end
                pcall(function() Combat:FireServer("Block", nil, nil) end)
                lastBlockFire = tick()
            end)
        end
    else
        if not isBlocking then
            Combat:FireServer("Block", nil, nil); isBlocking = true; lastBlockFire = now
        elseif not c:HasTag("Blocking") and now - lastBlockFire > 0.12 then
            Combat:FireServer("Block", nil, nil); lastBlockFire = now
        end
    end
    -- Anim only for Auto Block + Safe Block while Guard is out (never touch anim otherwise).
    if S._wantBlockAnim and S._wantBlockAnim() then
        if not (blockTrack and blockTrack.IsPlaying) then playBlockAnim() end
    end
end
-- Never fire Hands here — Hands LEAVES combat and was making Kill Aura die / feel slower over time.
local function unblock()
    if not isBlocking then return end
    isBlocking = false
    Combat:FireServer("Unblock", nil, nil)
    stopBlockAnim()
end

-- Reactive auto-block detection. Replicated tracks lose their Name, so match attacks by
-- AnimationId (set from the Combat folder). ONLY L/R punches + kicks — never Guard/Idle
-- Action4 fallback, and never Slam/Grab (those were holding Block while people stood near).
local attackIds = {}
local excludedAnims = {
    "guard", "block", "stance", "walk", "run", "idle",
    "slammed", "stumble", "liftpants", "perfectblocked",
    "equip", "unequip", "hands", "emote", "dance", "fall", "land",
    "slam", "grab", "head", "dive",
}
local function animKey(id)
    local s = tostring(id or ""):gsub("%s+", "")
    return s:match("(%d%d%d+)") or s
end
local function isSwingAnimName(n)
    n = tostring(n or ""):lower()
    if n == "l" or n == "r" then return true end
    if n:find("punch") or n:find("kick") or n:find("jab") or n:find("hook") or n:find("cross") then
        return true
    end
    return false
end
if CombatAnims then
    for _, d in ipairs(CombatAnims:GetDescendants()) do
        if d:IsA("Animation") then
            local n = d.Name:lower()
            local skip = false
            for _, ex in ipairs(excludedAnims) do
                if n:find(ex) then
                    skip = true
                    break
                end
            end
            if not skip and isSwingAnimName(n) then
                local key = animKey(d.AnimationId)
                if key ~= "" then attackIds[key] = true end
            end
        end
    end
end

local function isEnemyAttacking()
    local mh = myHRP()
    if not mh then return false end
    local range = S.blockRange or 6
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and not isWhitelisted(p) and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp and (hrp.Position - mh.Position).Magnitude <= range then
                local hum = p.Character:FindFirstChildOfClass("Humanoid")
                local animator = hum and hum:FindFirstChildOfClass("Animator")
                if animator then
                    local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
                    if ok and tracks then
                        for _, track in ipairs(tracks) do
                            if track.IsPlaying then
                                local anim = track.Animation
                                local key = anim and animKey(anim.AnimationId)
                                if key and attackIds[key] then
                                    -- Only the windup/active of the swing — not a lingering track
                                    local tpos = track.TimePosition or 0
                                    local len = track.Length or 0
                                    local window = (len > 0.05) and math.min(0.4, len * 0.5) or 0.35
                                    if tpos <= window then
                                        return true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end

local function hookAttacks(p)
    local function hookChar(char)
        local hum = char:WaitForChild("Humanoid", 10)
        local animator = hum and hum:WaitForChild("Animator", 10)
        if not animator then return end
        Maid:Give(animator.AnimationPlayed:Connect(function(track)
            if not isCurrent() then return end
            local a = track.Animation
            local key = a and animKey(a.AnimationId)
            if not (key and attackIds[key]) then return end
            if p == LP then
                -- ignore anims WE played (reach/rapid/aura swings) so they don't loop
                if not (tick() < (S.selfSwingUntil or 0)) then
                    if S.rapidPunch then S.doRapidPunch() end
                    if S.reach then reachPunch() end
                end
                -- Kill Aura manages its own Unblock — don't 0.5s-suppress AB here or DPS gaps appear
                if not S.godmode and not S.killAura then
                    blockSuppressUntil = tick() + 0.5; unblock()
                end
            else
                local hrp = char:FindFirstChild("HumanoidRootPart")
                local mh = myHRP()
                if hrp and mh and (mh.Position - hrp.Position).Magnitude <= (S.blockRange or 6) then
                    lastIncoming = tick()
                    if S.autoBlock or S.godmode then
                        block()
                    end
                end
            end
        end))
    end
    if p.Character then task.spawn(hookChar, p.Character) end
    Maid:Give(p.CharacterAdded:Connect(hookChar))
end
for _, p in ipairs(Players:GetPlayers()) do hookAttacks(p) end
Maid:Give(Players.PlayerAdded:Connect(hookAttacks))

----------------------------------------------------------------------
-- Anti Stun: swallow Combat OnClientEvent "Stun" (verified — 2 client handlers)
----------------------------------------------------------------------
function applyAntiStunHooks()
    local genv = (typeof(getgenv) == "function" and getgenv()) or _G
    if genv.__CAF2_ANTISTUN_HOOKED then return end
    if typeof(getconnections) ~= "function" or typeof(hookfunction) ~= "function" then return end
    local CombatRemote = Remotes and Remotes:FindFirstChild("Combat")
    if not CombatRemote then return end
    local ncc = (typeof(newcclosure) == "function") and newcclosure or function(f) return f end
    local okAny = false
    pcall(function()
        for _, c in ipairs(getconnections(CombatRemote.OnClientEvent)) do
            local orig = c.Function
            if type(orig) == "function" then
                local ok = pcall(function()
                    hookfunction(orig, ncc(function(ev, ...)
                        local st = ((typeof(getgenv) == "function" and getgenv()) or _G).CAF2
                        if st and st.S and st.S.antiStun and ev == "Stun" then
                            return
                        end
                        return orig(ev, ...)
                    end))
                end)
                if ok then okAny = true end
            end
        end
    end)
    if okAny then
        genv.__CAF2_ANTISTUN_HOOKED = true
        if genv.CAF2 then genv.CAF2.S = S end
    end
end

----------------------------------------------------------------------
-- Hands leave-combat guard. Live Player script fires Combat "Hands" on walk/idle
-- (leaves combat). Swallow game-originated Hands while auras are on.
-- Uses Combat:FireServer hook — NOT a second __namecall (that stacked & tanked FPS).
----------------------------------------------------------------------
local function applyHandsLeaveBlock()
    local genv = (typeof(getgenv) == "function" and getgenv()) or _G
    -- V3: swallow Hands/Unguard whenever KA/RA is on (checkcaller lied on some executors).
    if genv.__CAF2_HANDS_FS_V3 then return end
    if typeof(hookfunction) ~= "function" then return end
    local CombatRemote = Remotes and Remotes:FindFirstChild("Combat")
    if not (CombatRemote and CombatRemote.FireServer) then return end
    local ncc = (typeof(newcclosure) == "function") and newcclosure or function(f) return f end
    local ok = pcall(function()
        local old
        old = hookfunction(CombatRemote.FireServer, ncc(function(self, ...)
            local action = ...
            if action == "Hands" or action == "Unguard" then
                local st = ((typeof(getgenv) == "function" and getgenv()) or _G).CAF2
                if st and st.S and (st.S.killAura or st.S.ragdollAura) then
                    return
                end
            end
            if action == "Block" and not checkcaller() then
                local st = ((typeof(getgenv) == "function" and getgenv()) or _G).CAF2
                if st and st.S and st.S.killAura then
                    return
                end
            end
            return old(self, ...)
        end))
    end)
    if ok then genv.__CAF2_HANDS_FS_V3 = true end
end
-- Legacy no-op name kept so older toggle callbacks don't nil-index.
local function silencePlayerHandsRunning()
    applyHandsLeaveBlock()
end

task.defer(function()
    applyAntiStunHooks()
    applyHandsLeaveBlock()
end)
Maid:Give(LP.CharacterAdded:Connect(function()
    task.defer(applyHandsLeaveBlock)
end))

----------------------------------------------------------------------
-- Anti-ragdoll / godmode / noclip / inf-stamina enforcement
----------------------------------------------------------------------
local gmOrig = {}  -- [part] = {origCanTouch, origCanQuery} so godmode restores exactly
local function clearRagdoll(char)
    if not char then return end
    local trig = char:FindFirstChild("RagdollTrigger")
    if trig and trig:IsA("BoolValue") and trig.Value then trig.Value = false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        if hum:GetAttribute("RagdollEnabled") then hum:SetAttribute("RagdollEnabled", false) end
        hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
        if hum.PlatformStand then hum.PlatformStand = false end
        local st = hum:GetState()
        if st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.Ragdoll then hum:ChangeState(Enum.HumanoidStateType.GettingUp) end
    end
end
local farmThread = nil
local farmCFrame = nil  -- set by farm loop, held by Stepped

-- NOTE: farm tuning constants (FARM_DEPTH/CADENCE/SETTLE/NODMG_ABANDON) and the realHealth helper
-- live INSIDE startFarmLoop, not here. The main chunk is near Luau's 200-local-register ceiling, so
-- top-level locals must be kept to a minimum — function-scoped locals don't count against it.

Maid:Give(RunService.Stepped:Connect(function()
    if not isCurrent() then return end
    -- Idle early-out: no movement/protection work → skip every physics step.
    if not (S.antiRagdoll or S.antiKnockdown or S.godmode or S.noclip
        or S.walkEnabled or S.jumpEnabled or S.noFallDamage or S.antiSlam
        or S.antiFling or (S.killFocus and farmCFrame)) then
        return
    end
    local char = myChar(); if not char then return end
    if S.antiRagdoll or S.antiKnockdown or S.godmode then clearRagdoll(char) end

    if S.noclip then
        for _, p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end end
    end
    if S.walkEnabled and S.walkActive then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.WalkSpeed ~= S.walkspeedValue then hum.WalkSpeed = S.walkspeedValue end
    end
    if S.jumpEnabled then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            local jp = S.jumpPowerValue or 50
            -- High JumpPower freefall rubberbands (AC). Keep humanoid ≤50; super-jumps
            -- use the controlled LinearVelocity hop on JumpRequest.
            local apply = (jp > 55) and 0 or jp
            hum.UseJumpPower = true
            if hum.JumpPower ~= apply then hum.JumpPower = apply end
            if hum.JumpHeight ~= 0 and jp > 55 then hum.JumpHeight = 0 end
        end
    end
    if S.noFallDamage then
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hum then
            pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false) end)
            local st = hum:GetState()
            if st == Enum.HumanoidStateType.FallingDown then
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
            elseif st == Enum.HumanoidStateType.Landed then
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
            end
        end
        -- Cap downward speed so land impact never reaches fall-damage thresholds.
        if hrp then
            local v = hrp.AssemblyLinearVelocity
            if v.Y < -90 then
                hrp.AssemblyLinearVelocity = Vector3.new(v.X, -90, v.Z)
            end
        end
    end
    if S.antiSlam then
        pcall(function()
            -- Post-update ragdoll = Humanoid RagdollEnabled attribute / Physics state / DiveRagdoll
            -- tag (not the old "slammed" tags). Force back up by clearing the attribute the local
            -- ToggleRagdoll script watches, then requesting GettingUp.
            local isSlammed = isRagdolled(char)
            if isSlammed then
                if not wasSlammed then
                    wasSlammed = true
                    slamDetectedTime = tick()
                end
                if tick() - slamDetectedTime >= 0.35 then
                    CollectionService:RemoveTag(char, "DiveRagdoll")
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum then
                        hum:SetAttribute("RagdollEnabled", false)
                        hum.PlatformStand = false
                        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                    end
                end
            else
                wasSlammed = false
            end
        end)
    end
    if S.antiFling then
        pcall(function()
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local vel = hrp.AssemblyLinearVelocity
                if vel.Magnitude > 75 then
                    hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                end
                local angVel = hrp.AssemblyAngularVelocity
                if angVel.Magnitude > 75 then
                    hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                end
            end
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LP and p.Character then
                    for _, part in ipairs(p.Character:GetDescendants()) do
                        if part:IsA("BasePart") and part.CanCollide then
                            part.CanCollide = false
                        end
                    end
                end
            end
        end)
    end
    -- Auto Farm: hard-hold the underground engage point. No server AC polices this, so the only
    -- goal is a rock-steady position below the floor where no player can see us — stability beats
    -- physics-realism here. Pin CFrame and kill velocity/gravity every frame; PlatformStand stops
    -- the humanoid fighting the hold.
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp and S.killFocus and farmCFrame then
        hrp.CFrame = farmCFrame
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and not hum.PlatformStand then hum.PlatformStand = true end
    end
end))
-- Inf stamina: pin the live regen closure's stamina upvalues (max/current/regen) so the punch
-- gate "stamina >= cost" always passes. We do NOT raise the persistent MaxStamina/StaminaRegen
-- values — that made stamina stay infinite after death and impossible to turn off. Instead we
-- re-pin each life (CharacterAdded) and RESTORE the originals when the toggle is turned off.
local STAM_MAX, STAM_REGEN = 100, 0.475
do
    local ms, sr = LP:FindFirstChild("MaxStamina"), LP:FindFirstChild("StaminaRegen")
    if ms and ms.Value > 0 and ms.Value <= 1000 then STAM_MAX = ms.Value end
    if sr and sr.Value > 0 and sr.Value <= 10 then STAM_REGEN = sr.Value end
    if ms and ms.Value > 1000 then ms.Value = STAM_MAX end       -- clean leftover from old runs
    if sr and sr.Value > 10 then sr.Value = STAM_REGEN end
end
-- Post-2528: stamina is no longer an LP.Stamina NumberValue — it lives in a LOCAL upvalue ("Value")
-- shared by the game's RegenStamina / TakeStamina closures. The old pin (which looked for a Stamina-
-- BAR UI ref + 3 numbers) no longer matches anything, so inf stamina silently did nothing. We now
-- find that closure by a stable fingerprint — it closes over BOTH LP.MaxStamina and LP.StaminaRegen —
-- and pin its numeric stamina upvalue to full every frame so punches never gate out. No hooks
-- (CAF2 kicks on those); this is debug.getupvalues/setupvalue only.
local staminaPin = nil   -- { fn = , idx = } for this life's stamina closure
local function findStaminaClosure()
    if not (getgc and debug and debug.getupvalues) then return nil end
    local maxV = LP:FindFirstChild("MaxStamina")
    local regenV = LP:FindFirstChild("StaminaRegen")
    if not (maxV and regenV) then return nil end
    local found
    pcall(function()
        for _, fn in ipairs(getgc(true)) do
            if type(fn) == "function" then
                local ok, ups = pcall(debug.getupvalues, fn)
                if ok and type(ups) == "table" then
                    local hasMax, hasRegen, numIdx = false, false, nil
                    for i, v in pairs(ups) do
                        if v == maxV then hasMax = true
                        elseif v == regenV then hasRegen = true
                        elseif type(v) == "number" and v >= 0 and v <= 300 then numIdx = numIdx or i end
                    end
                    if hasMax and hasRegen and numIdx then found = { fn = fn, idx = numIdx }; return end
                end
            end
        end
    end)
    return found
end
local _infStamThread = nil
local function applyInfStamina()
    if _infStamThread then return end
    _infStamThread = task.spawn(function()
        while S.infStamina and isCurrent() do
            -- (Re)acquire the closure — it's recreated each life, so re-find when we lose it.
            if not (staminaPin and staminaPin.fn) then
                staminaPin = findStaminaClosure()
            end
            if staminaPin and staminaPin.fn and debug and debug.setupvalue then
                local ms = LP:FindFirstChild("MaxStamina")
                local maxV = (ms and typeof(ms.Value) == "number" and ms.Value > 0 and ms.Value <= 1000) and ms.Value or STAM_MAX
                local okSet = pcall(debug.setupvalue, staminaPin.fn, staminaPin.idx, maxV)
                if not okSet then staminaPin = nil end   -- stale closure (respawn) → re-find next tick
            end
            task.wait(0.05)
        end
        _infStamThread = nil
    end)
end
local function disableInfStamina()
    S.infStamina = false
    _infStamThread = nil
    staminaPin = nil
    local ms, sr = LP:FindFirstChild("MaxStamina"), LP:FindFirstChild("StaminaRegen")
    if ms and ms.Value > 1000 then ms.Value = STAM_MAX end
    if sr and sr.Value > 10 then sr.Value = STAM_REGEN end
end
local function sweepGuis(root)
    if not root then return end
    pcall(function()
        for _, desc in ipairs(root:GetDescendants()) do
            if desc:IsA("BillboardGui") or desc:IsA("ScreenGui") or desc:IsA("GuiObject") then
                local name = desc.Name:lower()
                if name:find("perfect") or name:find("block") then
                    desc:Destroy()
                end
            end
        end
    end)
end

local charConn = nil
local function monitorCharacter(char)
    if charConn then pcall(function() charConn:Disconnect() end); charConn = nil end
    if not char then return end
    charConn = char.DescendantAdded:Connect(function(desc)
        if S.godmode then
            pcall(function()
                if desc:IsA("BillboardGui") or desc:IsA("ScreenGui") or desc:IsA("GuiObject") then
                    local name = desc.Name:lower()
                    if name:find("perfect") or name:find("block") then
                        desc:Destroy()
                    end
                end
            end)
        end
    end)
    if S.godmode then sweepGuis(char) end
end

local function checkStaff(p)
    if not S.antiStaff or not p or p == LP then return end
    pcall(function()
        -- Group-rank checks only (name keywords false-positive too often and self-kick).
        if p:GetRankInGroup(1200769) >= 100 or p:GetRankInGroup(32380007) >= 1 then
            LP:Kick("Staff Detected: " .. p.Name)
        end
    end)
end

Maid:Give(Players.PlayerAdded:Connect(checkStaff))
Maid:Give(LP.Idled:Connect(function()
    if not S.antiAfk then return end
    pcall(function()
        local VU = game:GetService("VirtualUser")
        VU:CaptureController(); VU:ClickButton2(Vector2.new())
    end)
end))

task.spawn(function()
    while task.wait(1.5) do
        if S.antiStaff then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LP then
                    checkStaff(p)
                end
            end
        end
    end
end)

if LP.Character then monitorCharacter(LP.Character) end

Maid:Give(LP.CharacterAdded:Connect(function(char)
    staminaPin = nil
    if S.infStamina then task.delay(1.5, applyInfStamina) end
    monitorCharacter(char)
end))

Maid:Give(LP.PlayerGui.DescendantAdded:Connect(function(desc)
    if S.godmode then
        pcall(function()
            if desc:IsA("BillboardGui") or desc:IsA("ScreenGui") or desc:IsA("GuiObject") then
                local name = desc.Name:lower()
                if name:find("perfect") or name:find("block") then
                    desc:Destroy()
                end
            end
        end)
    end
end))



----------------------------------------------------------------------
-- Auto Farm: dedicated loop (not in heartbeat — needs task.wait)
----------------------------------------------------------------------
local function startFarmLoop()
    if farmThread and coroutine.status(farmThread) ~= "dead" then return end
    -- Farm tuning, measured live against this game. Scoped here (not main chunk) to avoid blowing
    -- Luau's 200-local-register limit on the top-level scope.
    --   * Server hit range ~9-10 studs: depth 6 & 9 land, 12 & 16 miss. -6.5 = under the floor AND in range.
    --   * Faster cadence = more DPS (0.12s -> 23 dmg/s, 0.05s -> 31 dmg/s); server swing cd caps the gain.
    --   * Hits ONLY register unanchored once your new position has replicated — hence the settle.
    --   * No real server anticheat: bans are player-report only, so staying underground (unseen) is the defense.
    local FARM_BURY         = 4.5   -- studs below the FLOOR under the target — our resting Y. Keeps the nametag
                                    -- under the map even when the target jumps/is knocked airborne. Grounded
                                    -- target HRP sits ~floor+3, so the vertical gap stays ~7.5 < hit range.
    local FARM_DEPTH        = 6.5   -- fallback depth below the TARGET when no floor is found beneath them (ledge/pit)
    local FARM_CADENCE      = 0.06  -- seconds between hits — fast; near the server swing cd, ~doubles old kill speed
    local FARM_SETTLE       = 0.22  -- pause after snapping under a new target so the position replicates first
    local FARM_NODMG_ABANDON = 1.1  -- bail if the target takes 0 damage this long (airborne too long/safezone) and move on
    local FARM_WAIT_DROP    = 14    -- extra studs we drop DOWN to a lower waiting spot between kills (Medium pace)

    -- Real health lives in player.Health (IntValue); Humanoid.Health always reads 100 here.
    local function realHealth(plr)
        local hv = plr and plr:FindFirstChild("Health")
        return hv and hv.Value or 0
    end

    -- Kill Loop safety: between kills (while the focus target is respawning) we drop the bury
    -- pin, which with noclip on would let us fall out of the world. Instead we spawn a private
    -- invisible platform right where we are and pin on it until the target is back.
    -- Post-2528: no underground rest platform (the deep teleport tripped the position AC). Between
    -- kills we simply idle in place as a normal standing player until the focus target respawns.
    local restPlatform = nil
    local function clearRest()
        if restPlatform then pcall(function() restPlatform:Destroy() end); restPlatform = nil end
    end
    local function restOnPlatform()
        farmCFrame = nil
        S.noclip = false
        task.wait(0.3)
    end

    farmThread = task.spawn(function()
        while S.killFocus and isCurrent() do
            local char = myChar()
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then
                task.wait(0.4)
            elseif S.safeZone then
                -- Paused while the Cheaters Safe Zone is on: stay enabled but stop targeting and release the
                -- position pin so the safe-zone platform TP isn't fought. Resumes automatically when it's off.
                farmCFrame = nil
                task.wait(0.3)
            else
            -- No noclip / no burial post-2528: we stay a real, grounded fighter and walk up in
            -- bounded hops. Noclip here would drop us through the floor now that nothing pins us.
            S.noclip = false

            -- Target selection. Travel is instant and underground (nobody sees it), so we no longer
            -- care about distance for stealth — pick whatever kills fastest. Target Lowest HP ranks
            -- by REAL health (player.Health, not the always-100 Humanoid). Default takes the nearest
            -- valid enemy just to keep target-hopping orderly.
            local farmTarget, farmPlayer = nil, nil
            -- Kill Loop (Target tab): lock onto the chosen player; when they die/respawn we re-kill.
            if S.killFocus and S.focusTarget then
                local fp = S.focusTarget
                if validEnemy(fp, fp.Character) then farmTarget, farmPlayer = fp.Character, fp end
            end
            if farmTarget and farmPlayer then
                -- alive check (real health; humanoid health is meaningless here)
                local function targetAlive()
                    if not farmTarget or not farmTarget.Parent then return false end
                    return realHealth(farmPlayer) > 0
                end

                -- best position from target (HRP first, any BasePart as fallback for ragdoll)
                local function getTargetPos()
                    local tHRP = farmTarget:FindFirstChild("HumanoidRootPart")
                    if tHRP and tHRP.Parent then return tHRP.Position end
                    for _, part in ipairs(farmTarget:GetChildren()) do
                        if part:IsA("BasePart") then return part.Position end
                    end
                    return nil
                end

                -- Resting CFrame: track the target's X/Z but pin Y just BELOW THE FLOOR under them, so
                -- the nametag (which renders ~1.5 studs under the HRP) stays buried even when the target
                -- jumps or gets knocked into the air. Raycast finds the ground under the target each tick;
                -- if there's none (ledge/pit) we fall back to a fixed depth below the target itself.
                local floorRP = RaycastParams.new()
                floorRP.FilterType = Enum.RaycastFilterType.Exclude
                local function buryCF(p)
                    floorRP.FilterDescendantsInstances = { myChar(), farmTarget }
                    local hit = workspace:Raycast(Vector3.new(p.X, p.Y + 2, p.Z), Vector3.new(0, -60, 0), floorRP)
                    local y = hit and (hit.Position.Y - FARM_BURY) or (p.Y - FARM_DEPTH)
                    return CFrame.new(p.X, y, p.Z)
                end

                if targetAlive() then
                    clearRest()
                    farmCFrame = nil            -- no burial: the update's position AC kicks on the deep teleport
                    local pos = getTargetPos()
                    if pos then
                        -- Post-2528 farm: silent-aim/burial are dead (removed remotes + position AC). Instead
                        -- bounded-hop up to the target like a real player, face them, and land real Fists.
                        S.boundedApproach(pos, S.hitRange - 1)
                        task.wait(FARM_SETTLE)

                        -- Watchdog: if the target stops taking damage (blocking / safezone / invalid), bail.
                        local lastHealth = realHealth(farmPlayer)
                        local lastDamageT = os.clock()

                        while S.killFocus and isCurrent() and targetAlive() and not S.safeZone do
                            if targetIsBlocking(farmTarget) then
                                S.ragdollHit(farmTarget, false)   -- break their guard with a dive-ragdoll
                            else
                                S.landHit(farmTarget, nil, true)  -- bounded-follow + Head hit
                            end

                            local hpNow = realHealth(farmPlayer)
                            if hpNow < lastHealth then lastHealth = hpNow; lastDamageT = os.clock()
                            elseif os.clock() - lastDamageT > FARM_NODMG_ABANDON then break end

                            task.wait(FARM_CADENCE)
                        end

                        -- PACING: every KO prints "<you> KNOCKED OUT <victim>" in the GLOBAL feed, and
                        -- the server credits your name — that can't be hidden client-side. So on Medium,
                        -- after an actual KO we wait a human-like gap before the next one so your name
                        -- doesn't machine-gun the feed. During the gap we TP DOWN to a lower waiting spot
                        -- (further below the floor) and the Stepped hold pins us there like a platform —
                        -- well out of the way until the next target. High = no gap (fastest, obvious).
                    end
                end
                if not S.killFocus then farmCFrame = nil end
                task.wait(0.05)
            else
                -- Kill Loop: focus target is dead / respawning — rest on a safe platform.
                if S.killFocus then restOnPlatform() else task.wait(0.4) end
            end
            end
        end
        -- farm stopped, clean up
        clearRest()
        farmCFrame = nil
        local char = myChar()
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.Anchored = false end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false end
        end
        S.noclip = false
    end)
end

local kaAdorn = nil
local raAdorn = nil
local slamAdorn = nil
local blockAdorn = nil
local grabAdorn = nil
local flashAdorn = nil
local slamHkAdorn = nil
local unblockAdorn = nil

local function ensureRangeCylinder(adorn, hrp, color, transparency, zindex, yoff)
    if not adorn or adorn.Parent ~= hrp then
        if adorn then adorn:Destroy() end
        adorn = Instance.new("CylinderHandleAdornment")
        adorn.Height = 0.02
        adorn.Color3 = color
        adorn.Transparency = transparency
        adorn.ZIndex = zindex
        adorn.AlwaysOnTop = true
        adorn.Adornee = hrp
        adorn.CFrame = CFrame.new(0, yoff, 0) * CFrame.Angles(math.pi / 2, 0, 0)
        adorn.Parent = hrp
    end
    return adorn
end

local function updateRangeVisuals()
    local char = myChar()
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        if kaAdorn then kaAdorn:Destroy(); kaAdorn = nil end
        if raAdorn then raAdorn:Destroy(); raAdorn = nil end
        if slamAdorn then slamAdorn:Destroy(); slamAdorn = nil end
        if blockAdorn then blockAdorn:Destroy(); blockAdorn = nil end
        if grabAdorn then grabAdorn:Destroy(); grabAdorn = nil end
        if flashAdorn then flashAdorn:Destroy(); flashAdorn = nil end
        if slamHkAdorn then slamHkAdorn:Destroy(); slamHkAdorn = nil end
        if unblockAdorn then unblockAdorn:Destroy(); unblockAdorn = nil end
        return
    end
    if S.paVisualRange then
        if not kaAdorn or kaAdorn.Parent ~= hrp then
            if kaAdorn then kaAdorn:Destroy() end
            kaAdorn = Instance.new("CylinderHandleAdornment")
            kaAdorn.Height = 0.02
            kaAdorn.Color3 = Color3.fromRGB(186, 85, 211)
            kaAdorn.Transparency = 0.4
            kaAdorn.ZIndex = 10
            kaAdorn.AlwaysOnTop = true
            kaAdorn.Adornee = hrp
            kaAdorn.CFrame = CFrame.new(0, -3.1, 0) * CFrame.Angles(math.pi/2, 0, 0)
            kaAdorn.Parent = hrp
        end
        local kaR = math.min(S.paRange or 7, S.hitRange or 7)
        kaAdorn.Radius = kaR
        kaAdorn.InnerRadius = math.max(kaR - 0.2, 0)
    else
        if kaAdorn then kaAdorn:Destroy(); kaAdorn = nil end
    end
    if S.raVisualRange then
        raAdorn = ensureRangeCylinder(raAdorn, hrp, Color3.fromRGB(255, 140, 40), 0.42, 11, -3.0)
        local raR = math.min(S.raRange or 6, 7)
        raAdorn.Radius = raR
        raAdorn.InnerRadius = math.max(raR - 0.2, 0)
    else
        if raAdorn then raAdorn:Destroy(); raAdorn = nil end
    end
    if S.slamVisualRange then
        if not slamAdorn or slamAdorn.Parent ~= hrp then
            if slamAdorn then slamAdorn:Destroy() end
            slamAdorn = Instance.new("CylinderHandleAdornment")
            slamAdorn.Height = 0.02
            slamAdorn.Color3 = Color3.fromRGB(138, 43, 226)
            slamAdorn.Transparency = 0.5
            slamAdorn.ZIndex = 9
            slamAdorn.AlwaysOnTop = true
            slamAdorn.Adornee = hrp
            slamAdorn.CFrame = CFrame.new(0, -3.15, 0) * CFrame.Angles(math.pi/2, 0, 0)
            slamAdorn.Parent = hrp
        end
        slamAdorn.Radius = S.slamRange
        slamAdorn.InnerRadius = S.slamRange - 0.2
    else
        if slamAdorn then slamAdorn:Destroy(); slamAdorn = nil end
    end
    if S.blockVisualRange then
        if not blockAdorn or blockAdorn.Parent ~= hrp then
            if blockAdorn then blockAdorn:Destroy() end
            blockAdorn = Instance.new("CylinderHandleAdornment")
            blockAdorn.Height = 0.02
            blockAdorn.Color3 = Color3.fromRGB(147, 112, 219)
            blockAdorn.Transparency = 0.6
            blockAdorn.ZIndex = 8
            blockAdorn.AlwaysOnTop = true
            blockAdorn.Adornee = hrp
            blockAdorn.CFrame = CFrame.new(0, -3.2, 0) * CFrame.Angles(math.pi/2, 0, 0)
            blockAdorn.Parent = hrp
        end
        blockAdorn.Radius = S.blockRange
        blockAdorn.InnerRadius = S.blockRange - 0.2
    else
        if blockAdorn then blockAdorn:Destroy(); blockAdorn = nil end
    end
    if S.grabSlamVisualRange then
        grabAdorn = ensureRangeCylinder(grabAdorn, hrp, Color3.fromRGB(255, 120, 40), 0.45, 11, -3.05)
        grabAdorn.Radius = S.grabSlamRange
        grabAdorn.InnerRadius = math.max(S.grabSlamRange - 0.2, 0)
    else
        if grabAdorn then grabAdorn:Destroy(); grabAdorn = nil end
    end
    if S.flashStepVisualRange then
        flashAdorn = ensureRangeCylinder(flashAdorn, hrp, S.flashStepColor or Color3.fromRGB(64, 200, 255), 0.45, 12, -3.0)
        flashAdorn.Color3 = S.flashStepColor or Color3.fromRGB(64, 200, 255)
        flashAdorn.Radius = S.flashStepDistance
        flashAdorn.InnerRadius = math.max(S.flashStepDistance - 0.2, 0)
    else
        if flashAdorn then flashAdorn:Destroy(); flashAdorn = nil end
    end
    if S.slamHotkeyVisualRange then
        slamHkAdorn = ensureRangeCylinder(slamHkAdorn, hrp, Color3.fromRGB(255, 64, 120), 0.45, 13, -2.95)
        slamHkAdorn.Radius = S.slamHotkeyRange
        slamHkAdorn.InnerRadius = math.max(S.slamHotkeyRange - 0.2, 0)
    else
        if slamHkAdorn then slamHkAdorn:Destroy(); slamHkAdorn = nil end
    end
    if S.autoUnblockVisualRange then
        unblockAdorn = ensureRangeCylinder(unblockAdorn, hrp, Color3.fromRGB(0, 255, 255), 0.45, 14, -2.8)
        unblockAdorn.Radius = S.autoUnblockRange
        unblockAdorn.InnerRadius = math.max(S.autoUnblockRange - 0.2, 0)
    else
        if unblockAdorn then unblockAdorn:Destroy(); unblockAdorn = nil end
    end
    if S.reachVisualRange then
        local ra = hrp:FindFirstChild("CAF2_ReachRing")
        if not ra then
            ra = Instance.new("CylinderHandleAdornment")
            ra.Name = "CAF2_ReachRing"
            ra.Height = 0.02
            ra.Color3 = Color3.fromRGB(255, 210, 70)
            ra.Transparency = 0.4
            ra.ZIndex = 14
            ra.AlwaysOnTop = true
            ra.Adornee = hrp
            ra.CFrame = CFrame.new(0, -2.9, 0) * CFrame.Angles(math.pi / 2, 0, 0)
            ra.Parent = hrp
        end
        ra.Radius = S.reachRange
        ra.InnerRadius = math.max(S.reachRange - 0.2, 0)
    else
        local ra = hrp:FindFirstChild("CAF2_ReachRing")
        if ra then ra:Destroy() end
    end
    if S.rapidPunchVisualRange then
        local rp = hrp:FindFirstChild("CAF2_RapidRing")
        if not rp then
            rp = Instance.new("CylinderHandleAdornment")
            rp.Name = "CAF2_RapidRing"
            rp.Height = 0.02
            rp.Color3 = Color3.fromRGB(255, 120, 60)
            rp.Transparency = 0.4
            rp.ZIndex = 15
            rp.AlwaysOnTop = true
            rp.Adornee = hrp
            rp.CFrame = CFrame.new(0, -2.85, 0) * CFrame.Angles(math.pi / 2, 0, 0)
            rp.Parent = hrp
        end
        rp.Radius = S.rapidPunchRange
        rp.InnerRadius = math.max(S.rapidPunchRange - 0.2, 0)
    else
        local rp = hrp:FindFirstChild("CAF2_RapidRing")
        if rp then rp:Destroy() end
    end
end

Maid:Give(function()
    if kaAdorn then kaAdorn:Destroy() end
    if raAdorn then raAdorn:Destroy() end
    if slamAdorn then slamAdorn:Destroy() end
    if blockAdorn then blockAdorn:Destroy() end
    if grabAdorn then grabAdorn:Destroy() end
    if flashAdorn then flashAdorn:Destroy() end
    if slamHkAdorn then slamHkAdorn:Destroy() end
    if unblockAdorn then unblockAdorn:Destroy() end
    local mh = myHRP(); if mh then
        local reachRing = mh:FindFirstChild("CAF2_ReachRing"); if reachRing then reachRing:Destroy() end
        local rp = mh:FindFirstChild("CAF2_RapidRing"); if rp then rp:Destroy() end
        local rg = mh:FindFirstChild("CAF2_RagdollRing"); if rg then rg:Destroy() end
    end
end)

----------------------------------------------------------------------
-- Main combat loop
----------------------------------------------------------------------
rangeVisAccum = 0
Maid:Give(RunService.Heartbeat:Connect(function(dt)
    if not isCurrent() then return end
    rangeVisAccum = rangeVisAccum + dt
    if rangeVisAccum >= 0.066 then rangeVisAccum = 0; pcall(updateRangeVisuals) end

    -- Idle early-out when no combat helpers need per-frame work.
    if not (S.killAura or S.ragdollAura or S.autoSlam or S.slamHotkey
        or S.autoBlock or S.godmode or S.autoUnblock or S.rapidPunch or S.reach
        or S.grabSlamEnabled) then
        return
    end

    local now = tick()
    local char = myChar(); if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart"); if not hrp then return end

    lockTarget = nearest(math.max(math.min(S.paRange, S.hitRange or 7), S.slamRange))

    if S.autoUnblock and not S.killAura and isCombatSafe() then
        local t = nearest(S.autoUnblockRange or 18)
        if t then
            local blockingNow = targetIsBlocking(t)
            if S.unblockTarget == t and S.unblockWas and not blockingNow and now - (S.lastUnblockHit or 0) > 0.3 then
                S.lastUnblockHit = now
                task.spawn(function()
                    if isBlocking then isBlocking = false; Combat:FireServer("Unblock", nil, nil); blockSuppressUntil = tick() + 0.2; stopBlockAnim(); task.wait(0.03) end
                    -- Punish the opening with a Head hit (bounded-approach handles range).
                    S.landHit(t, S.autoUnblockRange or 18, true)
                end)
            end
            S.unblockTarget = t
            S.unblockWas = blockingNow
        else
            S.unblockTarget = nil; S.unblockWas = false
        end
    end

    -- Ragdoll Aura only when Kill Aura is OFF (dive soft-locks Head).
    if not S.killAura then tryRagdollAura() end
    tryKillAura()
    -- Never Auto Slam while Kill Aura is melting — Slam was stealing cadence.
    if S.autoSlam and not S.killAura and now - lastAutoSlam >= (S.slamCD or 0) then
        if not isRagdolled(char) then
            local t = nearest(math.max(S.slamRange or 6, 7))
            if t and not isRagdolled(t) then
                lastAutoSlam = now
                lastSlam = now
                pcall(function() S.bypassCombatCooldowns(true) end)
                task.spawn(slam, t)
            end
        end
    end
    -- Kill Aura owns combat input: never Block while it's on (AB/Godmode thrash = stalls).
    if S.killAura then
        if isBlocking then unblock() end
        if blockTrack then stopBlockAnim() end
    elseif S.godmode and not S.killFocus then
        if now >= blockSuppressUntil then
            block()
        end
        if blockTrack then stopBlockAnim() end
    elseif S.autoBlock and not S.killFocus then
        local swinging = isEnemyAttacking()
        if swinging then
            lastIncoming = now
        end
        if S.safeBlock and (not canGuard() or not (myChar() and myChar():HasTag("Guarding"))) then
            unblock()
        elseif now >= blockSuppressUntil and (swinging or (now - (lastIncoming or 0)) <= 0.3) then
            block()
        else
            unblock()
        end
        if S._wantBlockAnim and S._wantBlockAnim() then
            if not (blockTrack and blockTrack.IsPlaying) then playBlockAnim() end
        elseif blockTrack then
            stopBlockAnim()
        end
    elseif isBlocking or S.killFocus then
        unblock()
    end
end))

-- Extra Kill Aura cadence on Heartbeat only. RenderStepped doubled Head spam
-- and helped trip CAF's remote-rate kick (Error 267).
-- (RenderStepped hook removed on purpose.)

----------------------------------------------------------------------
-- ESP + purple lock highlight
----------------------------------------------------------------------
espFolder = new("Folder", { Name = "CAF2_ESP" }, ScreenGui)
Maid:GiveInst(espFolder)
hls = {}
hpBars = {}

function clearEsp(p)
    if hls[p] then pcall(function() hls[p]:Destroy() end); hls[p] = nil end
    if hpBars[p] then pcall(function() hpBars[p]:Destroy() end); hpBars[p] = nil end
end

function realHealth(plr)
    local hv = plr and plr:FindFirstChild("Health")
    return hv and hv.Value or 0
end

function ensureEsp(plr, char)
    local h = hls[plr]
    if h and h.Adornee == char and h.Parent == espFolder then return h end
    if h then clearEsp(plr) end
    h = new("Highlight", { Name = "ESP_" .. plr.Name, Adornee = char, FillColor = Theme.Accent, OutlineColor = Theme.Accent, FillTransparency = S.espFill, OutlineTransparency = 0, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Parent = espFolder })
    hls[plr] = h
    return h
end

function updateHpBar(plr, char)
    local bar = hpBars[plr]
    if not S.hpEsp then
        if bar then bar:Destroy(); hpBars[plr] = nil end
        return
    end
    local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
    if not head then
        if bar then bar:Destroy(); hpBars[plr] = nil end
        return
    end
    if not bar or bar.Parent ~= head or bar.Adornee ~= head then
        if bar then pcall(function() bar:Destroy() end) end
        -- Parent to Head (not gethui folder) so BillboardGui always renders in-world.
        local bg = Instance.new("BillboardGui")
        bg.Name = "CAF2_HPBar"
        bg.Size = UDim2.new(0, 120, 0, 30)
        bg.StudsOffset = Vector3.new(0, 1.75, 0)
        bg.AlwaysOnTop = true
        bg.MaxDistance = 300
        bg.LightInfluence = 0
        bg.ResetOnSpawn = false
        bg.Adornee = head
        bg.Parent = head

        local nameLbl = Instance.new("TextLabel")
        nameLbl.Name = "Name"
        nameLbl.BackgroundTransparency = 1
        nameLbl.Size = UDim2.new(1, 0, 0, 13)
        nameLbl.Font = Enum.Font.GothamBold
        nameLbl.TextSize = 12
        nameLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        nameLbl.TextStrokeTransparency = 0.25
        nameLbl.Text = plr.Name
        nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
        nameLbl.Parent = bg

        local track = Instance.new("Frame")
        track.Name = "Track"
        track.Size = UDim2.new(1, 0, 0, 12)
        track.Position = UDim2.new(0, 0, 0, 15)
        track.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
        track.BackgroundTransparency = 0.1
        track.BorderSizePixel = 0
        track.Parent = bg
        local trackCorner = Instance.new("UICorner")
        trackCorner.CornerRadius = UDim.new(0, 4)
        trackCorner.Parent = track
        local trackStroke = Instance.new("UIStroke")
        trackStroke.Color = Color3.fromRGB(255, 255, 255)
        trackStroke.Thickness = 1
        trackStroke.Transparency = 0.55
        trackStroke.Parent = track

        local fill = Instance.new("Frame")
        fill.Name = "Fill"
        fill.Size = UDim2.new(1, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(50, 220, 90)
        fill.BorderSizePixel = 0
        fill.ZIndex = 1
        fill.Parent = track
        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(0, 4)
        fillCorner.Parent = fill

        local hpLbl = Instance.new("TextLabel")
        hpLbl.Name = "HPText"
        hpLbl.BackgroundTransparency = 1
        hpLbl.Size = UDim2.new(1, 0, 1, 0)
        hpLbl.Font = Enum.Font.GothamBold
        hpLbl.TextSize = 10
        hpLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        hpLbl.TextStrokeTransparency = 0.2
        hpLbl.ZIndex = 2
        hpLbl.Parent = track

        bar = bg
        hpBars[plr] = bar
    end

    local track = bar:FindFirstChild("Track")
    local fill = track and track:FindFirstChild("Fill")
    local hpLbl = track and track:FindFirstChild("HPText")
    local nameLbl = bar:FindFirstChild("Name")
    if nameLbl then nameLbl.Text = plr.Name end
    if fill then
        local hp = realHealth(plr)
        local hum = char:FindFirstChildOfClass("Humanoid")
        local maxHp = (hum and hum.MaxHealth > 0) and hum.MaxHealth or 100
        local pct = math.clamp(hp / maxHp, 0, 1)
        if hp <= 0 then pct = 0 end
        fill.Size = UDim2.new(pct, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(230, 50, 50):Lerp(Color3.fromRGB(50, 220, 90), pct)
        if hpLbl then
            hpLbl.Text = hp <= 0 and "KO" or (tostring(math.max(0, math.floor(hp + 0.5))) .. "/" .. tostring(math.floor(maxHp)))
        end
    end
end

lockHL = new("Highlight", { Name = "CAF2_Lock", FillColor = Color3.fromRGB(170, 60, 255), OutlineColor = Color3.fromRGB(190, 120, 255), FillTransparency = 0.45, OutlineTransparency = 0, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Enabled = false, Parent = espFolder })

espAccum = 0
Maid:Give(RunService.Heartbeat:Connect(function(dt)
    if not isCurrent() then return end
    espAccum = espAccum + dt
    if espAccum < 0.08 then return end
    espAccum = 0
    if S.esp or S.hpEsp then
        local rgbColor = S.espRgb and Color3.fromHSV((tick() * 0.12) % 1, 0.8, 1) or Theme.Accent
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and not isWhitelisted(p) and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                if S.esp then
                    local h = ensureEsp(p, p.Character)
                    h.FillTransparency = S.espFill
                    h.FillColor = rgbColor
                    h.OutlineColor = S.espRgb and rgbColor:Lerp(Color3.new(1, 1, 1), 0.3) or Theme.Accent
                else
                    if hls[p] then hls[p]:Destroy(); hls[p] = nil end
                end
                updateHpBar(p, p.Character)
            else
                clearEsp(p)
            end
        end
    else
        for p in pairs(hls) do clearEsp(p) end
        for p in pairs(hpBars) do clearEsp(p) end
    end
    if S.showLocked and lockTarget and lockTarget.Parent then
        lockHL.Adornee = lockTarget
        lockHL.Enabled = true
        if S.lockRgb then
            local rgbColor = Color3.fromHSV((tick() * 0.12) % 1, 0.8, 1)
            lockHL.FillColor = rgbColor
            lockHL.OutlineColor = rgbColor:Lerp(Color3.new(1, 1, 1), 0.3)
        else
            lockHL.FillColor = Color3.fromRGB(170, 60, 255)
            lockHL.OutlineColor = Color3.fromRGB(190, 120, 255)
        end
    else
        lockHL.Enabled = false
        lockHL.Adornee = nil
    end
end))
Maid:Give(Players.PlayerRemoving:Connect(clearEsp))

----------------------------------------------------------------------
-- NEW: server-verified power features (Ragdoll / Fly / AC-bypass / Party / Spin)
-- All runtime logic is scoped in do-blocks and hung on S.* to keep the main
-- chunk's top-level local count flat (near Luau's 200 register ceiling).
----------------------------------------------------------------------

-- NOTE: No FireServer/__namecall hooking anywhere in this suite. CAF2 runs a
-- client-side namecall-hook detector that KICKS ("namecallInstance detector
-- detected", Error 267) — verified live. Every feature below uses only plain
-- RemoteEvent:FireServer calls, which are indistinguishable from the real client.

-- Ragdoll tools -----------------------------------------------------------------
-- Fires the game's dive-ragdoll remote at the target from WHERE YOU STAND — this never
-- teleports you and never punches anyone (no kill-aura behaviour). Heads-up: the BIG
-- UPDATE tightened this server-side (it now prefers a real dive contact), so a from-range
-- fire may not always connect — but it's the non-disruptive version you wanted. If you
-- ever want the guaranteed-but-teleporting slam version back, it's a one-line switch.
do
    local PlayerRemote = Remotes and Remotes:FindFirstChild("Player")
    local lastFire = {}   -- [player] = tick of the last ragdoll we sent

    local function canRagdoll(ch)
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        return (ch and ch:FindFirstChild("HumanoidRootPart") and hum and hum.Health > 0
            and not ch:HasTag("Dead")) and true or false
    end

    -- Fire the dive-ragdoll at a player. No teleport, no punches.
    local function ragdollPlayer(p)
        local ch = p and p.Character
        if not (PlayerRemote and canRagdoll(ch)) then return false end
        PlayerRemote:FireServer("Dived On", ch)
        return true
    end
    S.ragdollPlayer = ragdollPlayer

    -- One-shot: fire the dive-ragdoll at every non-whitelisted player. Stays put.
    function S.ragdollBomb()
        notify("Ragdoll Bomb", "Disabled — was flagging / kicking.")
    end
    Maid:Give(Players.PlayerRemoving:Connect(function(p) lastFire[p] = nil end))

    task.spawn(function()
        while true do
            if not isCurrent() then break end
            task.wait(0.15)
        end
    end)
end

-- Fly ---------------------------------------------------------------------------
-- CAF position AC rubberbands AssemblyLinearVelocity flight after ~2s (verified
-- live: snap back to last good pos). LinearVelocity + PlatformStand does NOT —
-- 6s / 200+ studs with 0 snaps, and BodyMovers aren't used so the BodyGyro
-- "Flying" snitch never fires. Recreate the constraint if anything strips it.
do
    local VY_CAP = 50
    local flyConn
    local flyLV, flyAtt
    local noclipAccum = 0

    local function destroyFlyConstraint()
        if flyLV then pcall(function() flyLV:Destroy() end); flyLV = nil end
        if flyAtt then pcall(function() flyAtt:Destroy() end); flyAtt = nil end
    end

    local function ensureFlyConstraint(hrp)
        if flyLV and flyLV.Parent == hrp and flyAtt and flyAtt.Parent == hrp then
            return flyLV
        end
        destroyFlyConstraint()
        flyAtt = Instance.new("Attachment")
        flyAtt.Name = "CAF2_FlyAtt"
        flyAtt.Parent = hrp
        flyLV = Instance.new("LinearVelocity")
        flyLV.Name = "CAF2_FlyLV"
        flyLV.Attachment0 = flyAtt
        flyLV.RelativeTo = Enum.ActuatorRelativeTo.World
        flyLV.MaxForce = 1e9
        flyLV.VectorVelocity = Vector3.zero
        flyLV.Parent = hrp
        return flyLV
    end

    local function stopFly()
        if flyConn then pcall(function() flyConn:Disconnect() end); flyConn = nil end
        destroyFlyConstraint()
        local char = myChar()
        local h = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if h then pcall(function() h.AssemblyLinearVelocity = Vector3.zero end) end
        if hum then pcall(function() hum.PlatformStand = false end) end
    end

    local function startFly()
        stopFly()
        flyConn = Maid:Give(RunService.Heartbeat:Connect(function(dt)
            if not (S.fly and S.flyActive) then return end
            local h = myHRP(); if not h then return end
            local hum = h.Parent and h.Parent:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health <= 0 then return end
            if hum then hum.PlatformStand = true end

            local lv = ensureFlyConstraint(h)
            local cam = Workspace.CurrentCamera
            local look, right = cam.CFrame.LookVector, cam.CFrame.RightVector
            local function down(k) return UserInputService:IsKeyDown(k) end
            local dir = Vector3.zero
            if down(Enum.KeyCode.W) then dir = dir + look end
            if down(Enum.KeyCode.S) then dir = dir - look end
            if down(Enum.KeyCode.D) then dir = dir + right end
            if down(Enum.KeyCode.A) then dir = dir - right end
            local up = 0
            if down(Enum.KeyCode.Space) then up = up + 1 end
            if down(Enum.KeyCode.LeftControl) or down(Enum.KeyCode.LeftShift) then up = up - 1 end
            local speed = math.clamp(S.flySpeed or 55, 16, 90)
            local vel, vy
            if dir.Magnitude > 0 or up ~= 0 then
                vel = (dir.Magnitude > 0) and (dir.Unit * speed) or Vector3.zero
                vy = math.clamp(vel.Y + up * speed, -VY_CAP, VY_CAP)
            else
                local md = (hum and hum.MoveDirection) or Vector3.zero
                if md.Magnitude > 0.05 then
                    local fdir = Vector3.new(md.X, look.Y, md.Z)
                    fdir = (fdir.Magnitude > 0) and fdir.Unit or md
                    local v = fdir * speed
                    vel = Vector3.new(v.X, 0, v.Z)
                    vy = math.clamp(v.Y, -VY_CAP, VY_CAP)
                else
                    vel = Vector3.zero
                    vy = 0 -- true hover (LinearVelocity holds against gravity)
                end
            end
            lv.VectorVelocity = Vector3.new(vel.X, vy, vel.Z)

            if S.flyNoclip and h.Parent then
                noclipAccum = noclipAccum + (dt or 0.016)
                if noclipAccum >= 0.12 then
                    noclipAccum = 0
                    for _, pt in ipairs(h.Parent:GetDescendants()) do
                        if pt:IsA("BasePart") and pt.CanCollide then pt.CanCollide = false end
                    end
                end
            end
        end))
    end

    function S.setFly(on)
        S.fly = on; S.flyActive = on
        if on then startFly() else stopFly() end
    end
    function S.toggleFly() if S.setFly then S.setFly(not S.fly) end end
    Maid:Give(LP.CharacterAdded:Connect(function()
        destroyFlyConstraint()
        if S.fly and S.flyActive then task.wait(0.6); startFly() end
    end))
end

----------------------------------------------------------------------
-- Touch Fling / Bowling Ball — mirrors live Dive() → Touched → Player "Dived On".
-- Seat/physics yeets are CLIENT-ONLY on CAF. Server launch = dive path only:
--   DiveVelocity on HRP + FireServer("Dived On", char)
-- Never Combat "Slam" — Slam ragdolls differently and was overriding the bowl dive.
-- IIFE keeps dive locals out of the main-chunk 200-register limit.
----------------------------------------------------------------------
;(function()
    local PlayerRemote = Remotes and Remotes:FindFirstChild("Player")
    local lastTouchFling = {} -- [Player] = tick
    local diveLV, diveAtt
    local diveTouchConns = {}
    local diveBusyUntil = 0
    local lastGlobalDive = 0
    local destroyDiveVelocity -- forward decl (endBowlMorph cleans dive leftovers)

    -- Local bowling-ball morph (client visual only)
    local bowlBall, bowlSpinConn, bowlHide = nil, nil, {}
    local bowlRollAng, bowlRollAxis = 0, Vector3.new(1, 0, 0)
    local bowlMorphUntil = 0

    local function endBowlMorph()
        bowlMorphUntil = 0
        if bowlSpinConn then pcall(function() bowlSpinConn:Disconnect() end); bowlSpinConn = nil end
        if bowlBall then pcall(function() bowlBall:Destroy() end); bowlBall = nil end
        for part, lt in pairs(bowlHide) do
            if part and part.Parent then
                pcall(function()
                    if part:IsA("BasePart") then
                        part.LocalTransparencyModifier = lt
                    elseif part:IsA("Decal") or part:IsA("Texture") then
                        part.Transparency = lt
                    end
                end)
            end
            bowlHide[part] = nil
        end
        bowlRollAng = 0
        -- Morph end = dive window over — never leave DiveVelocity on the body.
        if destroyDiveVelocity then pcall(destroyDiveVelocity) end
    end

    local function buildBowlVisual(hrp, DIAM)
        -- Motor6D → HRP only. Never touch CameraSubject / CameraType.
        local root = Instance.new("Model")
        root.Name = "CAF2_BowlingBall"
        root.Parent = Workspace

        local R = DIAM * 0.5
        local ball = Instance.new("Part")
        ball.Name = "Ball"
        ball.Shape = Enum.PartType.Ball
        ball.Size = Vector3.new(DIAM, DIAM, DIAM)
        ball.Material = Enum.Material.SmoothPlastic
        ball.Color = Color3.fromRGB(210, 18, 28) -- clean house-ball red
        ball.Reflectance = 0.12
        ball.CanCollide = false
        ball.CanQuery = false
        ball.CanTouch = false
        ball.Massless = true
        ball.Anchored = false
        ball.CastShadow = true
        ball.CFrame = hrp.CFrame
        ball.Parent = root

        -- 3 flat black circles (finger holes) in a bowling-ball triangle
        local holeDirs = {
            Vector3.new(-0.28, 0.42, 0.86).Unit,
            Vector3.new(0.28, 0.42, 0.86).Unit,
            Vector3.new(0, -0.02, 0.999).Unit,
        }
        local holeDiam = math.clamp(DIAM * 0.22, 0.55, 0.85)
        for i, dir in ipairs(holeDirs) do
            local hole = Instance.new("Part")
            hole.Name = "Hole" .. i
            hole.Shape = Enum.PartType.Cylinder
            -- Cylinder axis = X; flat face points along dir so it reads as a black circle
            hole.Size = Vector3.new(0.08, holeDiam, holeDiam)
            hole.Material = Enum.Material.SmoothPlastic
            hole.Color = Color3.fromRGB(5, 5, 6)
            hole.Reflectance = 0
            hole.CanCollide = false
            hole.CanQuery = false
            hole.CanTouch = false
            hole.Massless = true
            hole.CastShadow = false
            hole.Parent = root
            local w = Instance.new("Weld")
            w.Part0 = ball
            w.Part1 = hole
            w.C0 = CFrame.new(dir * (R - 0.02))
                * CFrame.lookAt(Vector3.zero, dir)
                * CFrame.Angles(0, math.rad(90), 0)
            w.Parent = hole
        end

        local motor = Instance.new("Motor6D")
        motor.Name = "BowlMotor"
        motor.Part0 = hrp
        motor.Part1 = ball
        motor.C0 = CFrame.new()
        motor.C1 = CFrame.new()
        motor.Parent = ball

        return root, ball
    end

    local function startBowlMorph(duration)
        local char = myChar()
        local hrp = myHRP()
        if not (char and hrp) then return end
        endBowlMorph()
        bowlMorphUntil = os.clock() + (duration or 1.6)

        -- hide body visuals only — never HRP (camera / dive physics stay on humanoid)
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") and d ~= hrp then
                bowlHide[d] = d.LocalTransparencyModifier
                d.LocalTransparencyModifier = 1
            elseif d:IsA("Decal") or d:IsA("Texture") then
                bowlHide[d] = d.Transparency
                pcall(function() d.Transparency = 1 end)
            end
        end

        local DIAM = 2.85
        local root, ball = buildBowlVisual(hrp, DIAM)
        Maid:GiveInst(root)
        bowlBall = root

        bowlSpinConn = RunService.RenderStepped:Connect(function(dt)
            if not isCurrent() or not bowlBall or not bowlBall.Parent then
                endBowlMorph()
                return
            end
            if os.clock() > bowlMorphUntil then
                endBowlMorph()
                return
            end
            local h = myHRP()
            if not h then endBowlMorph(); return end
            for part, _ in pairs(bowlHide) do
                if part and part.Parent then
                    if part:IsA("BasePart") then
                        part.LocalTransparencyModifier = 1
                    elseif part:IsA("Decal") or part:IsA("Texture") then
                        part.Transparency = 1
                    end
                end
            end
            local vel = h.AssemblyLinearVelocity
            local flat = Vector3.new(vel.X, 0, vel.Z)
            local speed = flat.Magnitude
            if speed > 0.5 then
                local axis = Vector3.new(0, 1, 0):Cross(flat.Unit)
                if axis.Magnitude > 0.05 then
                    bowlRollAxis = axis.Unit
                    bowlRollAng = bowlRollAng + (speed / (DIAM * 0.5)) * dt
                end
            else
                bowlRollAng = bowlRollAng + 6 * dt
            end
            local m = ball and ball:FindFirstChild("BowlMotor")
            if m then
                m.C0 = CFrame.fromAxisAngle(bowlRollAxis, bowlRollAng)
            end
        end)
        Maid:Give(bowlSpinConn)
    end

    local function clearDiveTouches()
        for i = #diveTouchConns, 1, -1 do
            local c = diveTouchConns[i]
            if c then pcall(function() c:Disconnect() end) end
            diveTouchConns[i] = nil
        end
    end

    destroyDiveVelocity = function()
        clearDiveTouches()
        if diveLV then pcall(function() diveLV:Destroy() end); diveLV = nil end
        if diveAtt then pcall(function() diveAtt:Destroy() end); diveAtt = nil end
        local hrp = myHRP()
        if hrp then
            for _, d in ipairs(hrp:GetChildren()) do
                local n = d.Name
                -- Wipe every dive mover leftover (stuck LinearVelocity felt like jump boost).
                if n == "DiveVelocity" or n == "VelocityAttachment"
                    or n == "CAF2_DiveLV" or n == "CAF2_DiveAtt" then
                    pcall(function() d:Destroy() end)
                end
            end
            -- Clamp leftover launch Y so the next jump isn't double-boosted.
            pcall(function()
                local v = hrp.AssemblyLinearVelocity
                if v.Y > 10 then
                    hrp.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
                end
            end)
        end
    end

    local function playTouchVfx(atPos)
        if not S.touchFlingVfx then return end
        pcall(function()
            local ring = Instance.new("Part")
            ring.Name = "CAF2_TouchRing"
            ring.Shape = Enum.PartType.Cylinder
            ring.Size = Vector3.new(0.18, 1.2, 1.2)
            ring.CFrame = CFrame.new(atPos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
            ring.Anchored = true
            ring.CanCollide = false
            ring.CanQuery = false
            ring.CanTouch = false
            ring.Material = Enum.Material.Neon
            ring.Color = (Theme and Theme.Accent) or Color3.fromRGB(200, 40, 50)
            ring.Transparency = 0.2
            ring.Parent = Workspace
            Maid:GiveInst(ring)
            local t0 = os.clock()
            local conn
            conn = RunService.RenderStepped:Connect(function()
                local a = (os.clock() - t0) / 0.32
                if a >= 1 or not ring.Parent then
                    if conn then conn:Disconnect() end
                    pcall(function() ring:Destroy() end)
                    return
                end
                local s = 1.2 + a * 6
                ring.Size = Vector3.new(0.1, s, s)
                ring.Transparency = 0.2 + a * 0.8
            end)
            Maid:Give(conn)
        end)
    end

    -- Live Dive() cooldown is ~9s; power shortens our per-target / global debounce.
    local function flingCooldown()
        local p = math.clamp(S.touchFlingPower or 7, 1, 10)
        return math.clamp(2.4 - (p - 1) * 0.15, 0.85, 2.4)
    end

    local function hasGuardingChild(char)
        return char and char:FindFirstChild("Guarding") ~= nil
    end

    local function fireDivedOn(targetChar)
        if not (PlayerRemote and targetChar) then return end
        if hasGuardingChild(targetChar) then return end
        pcall(function()
            PlayerRemote:FireServer("Dived On", targetChar)
        end)
    end

    -- Exact live Dive() mover names + force setup; power scales up/forward boost.
    local diveGen = 0
    local function startDiveVelocity(towardPos)
        local hrp = myHRP(); if not hrp then return end
        if S.fly and S.flyActive then return end
        destroyDiveVelocity()
        diveGen = diveGen + 1
        local myGen = diveGen

        local dir = towardPos - hrp.Position
        local flat = Vector3.new(dir.X, 0, dir.Z)
        if flat.Magnitude < 0.05 then
            flat = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
        end
        if flat.Magnitude < 0.05 then flat = Vector3.new(0, 0, -1) else flat = flat.Unit end
        hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)

        local power = math.clamp(S.touchFlingPower or 7, 1, 10)
        local upBoost = 20 + (power - 5) * 2.2
        local fwdBoost = math.max(0, (power - 5) * 3.5)
        local base = hrp.AssemblyLinearVelocity * 1.2 + hrp.CFrame.UpVector * upBoost
        if fwdBoost > 0 then
            base = base + flat * fwdBoost
        end

        diveAtt = Instance.new("Attachment")
        diveAtt.Name = "VelocityAttachment"
        diveAtt.Parent = hrp
        diveLV = Instance.new("LinearVelocity")
        diveLV.Name = "DiveVelocity"
        diveLV.Attachment0 = diveAtt
        diveLV.RelativeTo = Enum.ActuatorRelativeTo.World
        diveLV.MaxForce = 100000
        diveLV.ForceLimitsEnabled = true
        diveLV.ForceLimitMode = Enum.ForceLimitMode.PerAxis
        diveLV.MaxAxesForce = Vector3.new(25000, 25000, 25000)
        diveLV.VectorVelocity = base
        diveLV.Parent = hrp

        -- After a beat, live client zeroes Y force so you arc into them.
        task.delay(0.075, function()
            if myGen ~= diveGen then return end
            if diveLV and diveLV.Parent then
                diveLV.MaxAxesForce = Vector3.new(25000, 0, 25000)
            end
        end)
        task.delay(1.55, function()
            if myGen ~= diveGen then return end
            destroyDiveVelocity()
            diveBusyUntil = 0
        end)
    end

    local function armDiveTouches(preferredChar)
        local char = myChar(); if not char then return end
        clearDiveTouches()
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                local conn
                conn = part.Touched:Connect(function(hit)
                    if not (S.touchFling and isCurrent() and PlayerRemote) then return end
                    local other = hit and hit.Parent
                    if not (other and other:FindFirstChildOfClass("Humanoid")) then return end
                    if other == char then return end
                    if hasGuardingChild(other) then return end
                    if preferredChar and other ~= preferredChar then
                        local plr = Players:GetPlayerFromCharacter(other)
                        if not plr or isWhitelisted(plr) then return end
                    end
                    fireDivedOn(other)
                    clearDiveTouches() -- one dive knock per window (match live intent)
                end)
                diveTouchConns[#diveTouchConns + 1] = conn
            end
        end
        task.delay(1.5, clearDiveTouches)
    end

    local function doServerTouchFling(targetChar, plr)
        if not (S.touchFling and PlayerRemote and targetChar and plr) then return end
        if not isCurrent() then return end
        if isWhitelisted(plr) then return end
        if hasGuardingChild(targetChar) then return end

        local now = tick()
        local cd = flingCooldown()
        if (lastTouchFling[plr] or 0) + cd > now then return end
        if now - lastGlobalDive < math.max(0.55, cd * 0.35) then return end
        if os.clock() < diveBusyUntil then return end

        local thrp = targetChar:FindFirstChild("HumanoidRootPart")
        local hrp = myHRP()
        local my = myChar()
        local hum = my and my:FindFirstChildOfClass("Humanoid")
        if not (thrp and hrp and hum) then return end
        if isRagdolled(my) then return end

        -- CAF custom movement often leaves Humanoid.MoveDirection at 0.
        -- Prefer HRP flat velocity toward the target; allow near-overlap either way.
        local gap = (thrp.Position - hrp.Position).Magnitude
        local toThem = thrp.Position - hrp.Position
        local flat = Vector3.new(toThem.X, 0, toThem.Z)
        local vel = hrp.AssemblyLinearVelocity
        local flatVel = Vector3.new(vel.X, 0, vel.Z)
        if flat.Magnitude > 0.2 and flatVel.Magnitude > 1.2 then
            if flatVel.Unit:Dot(flat.Unit) < 0.05 then
                return
            end
        elseif gap > 3.0 then
            -- Not closing in and not already overlapping → skip (avoids pure aura spam).
            return
        end

        lastTouchFling[plr] = now
        lastGlobalDive = now
        diveBusyUntil = os.clock() + 1.55
        playTouchVfx((hrp.Position + thrp.Position) * 0.5)
        pcall(startBowlMorph, 1.65)

        -- Dive-only knockdown. Never Slam — Slam ragdolls and overrides the bowl dive.
        startDiveVelocity(thrp.Position)
        armDiveTouches(targetChar)
        fireDivedOn(targetChar)

        local power = math.clamp(S.touchFlingPower or 7, 1, 10)
        if power >= 7 then
            task.delay(0.06, function()
                if not (S.touchFling and isCurrent()) then return end
                local c = plr.Character
                if c and validEnemy(plr, c) and not hasGuardingChild(c) then
                    fireDivedOn(c)
                end
            end)
        end
        if power >= 9 then
            task.delay(0.22, function()
                if not (S.touchFling and isCurrent()) then return end
                local c = plr.Character
                if c and validEnemy(plr, c) and not hasGuardingChild(c) then
                    fireDivedOn(c)
                end
            end)
        end
    end

    Maid:Give(RunService.Heartbeat:Connect(function()
        if not isCurrent() or not S.touchFling then return end
        local hrp = myHRP(); if not hrp then return end
        local range = math.clamp(S.touchFlingRange or 3.6, 2.2, 7)
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then
                local c = plr.Character
                if validEnemy(plr, c) and not isRagdolled(c) and not hasGuardingChild(c) then
                    local d = distToEnemy(hrp.Position, c)
                    if d <= range then
                        doServerTouchFling(c, plr)
                    end
                end
            end
        end
    end))

    Maid:Give(Players.PlayerRemoving:Connect(function(p)
        lastTouchFling[p] = nil
    end))

    Maid:Give(LP.CharacterAdded:Connect(function()
        endBowlMorph()
        pcall(destroyDiveVelocity)
        diveBusyUntil = 0
    end))

    S._stopTouchFling = function()
        S.touchFling = false
        destroyDiveVelocity()
        endBowlMorph()
        diveBusyUntil = 0
    end
    S._diveBusy = function()
        return os.clock() < diveBusyUntil
    end
    S._previewBowlMorph = function(sec)
        startBowlMorph(tonumber(sec) or 2.5)
    end
end)()

-- Party / pacify / spin rewards -------------------------------------------------
-- Live Player contract (Workspace.<player>.Player):
--   Party:FireServer("Attempt Party")              -- open invite (Attempt Party tag)
--   Party:FireServer("Attempt Join Party", plr)   -- join ONLY if they have Attempt Party
--   Party:FireServer("Leave Party", isLeaderBool) -- true=disband, false=leave
--   PartyRequest:InvokeServer(actionName, member) -- leader kick/etc (not invite)
do
    local PlayerRemote = Remotes and Remotes:FindFirstChild("Player")
    local PartyRemote  = Remotes and Remotes:FindFirstChild("Party")

    local function partySame(a, b)
        if not (a and b) then return false end
        local av, bv = a.Value, b.Value
        return av ~= nil and bv ~= nil and av == bv and tostring(av) ~= "" and tostring(av) ~= "None"
    end

    local function leaveMyParty()
        if not PartyRemote then return end
        local mine = LP:FindFirstChild("Party")
        local isLeader = mine and mine.Value == LP.Name
        pcall(function() PartyRemote:FireServer("Leave Party", isLeader and true or false) end)
    end

    -- Resolve the player we should Attempt Join Party on (prefer party leader).
    local function joinTargetFor(plr)
        if not plr then return nil end
        local pv = plr:FindFirstChild("Party")
        if pv and typeof(pv.Value) == "string" and pv.Value ~= "" then
            local leader = Players:FindFirstChild(pv.Value)
            if leader then return leader end
        end
        return plr
    end

    -- Force-party the nearest enemy: party members can't damage each other.
    function S.pacifyNearest()
        if not PartyRemote then
            notify("Pacify", "Party remote missing in this game.")
            return
        end
        local t = nearest(math.huge)
        local plr = t and Players:GetPlayerFromCharacter(t)
        if not plr then notify("Pacify", "No target in range.") return end

        if partySame(LP:FindFirstChild("Party"), plr:FindFirstChild("Party")) then
            notify("Pacify", plr.Name .. " is already in your party.")
            return
        end

        leaveMyParty()
        task.wait(0.25)

        -- Face them within party ray range (~4 studs) so join mirrors the real button
        local hrp = myHRP()
        local thrp = t:FindFirstChild("HumanoidRootPart")
        if hrp and thrp then
            pcall(function()
                hrp.CFrame = CFrame.lookAt(thrp.Position - thrp.CFrame.LookVector * 3, thrp.Position)
            end)
        end

        local joinPlr = joinTargetFor(plr)
        -- Open our invite too (if they press Party facing us, they join us)
        pcall(function() PartyRemote:FireServer("Attempt Party") end)

        local ok = false
        for _ = 1, 8 do
            pcall(function() PartyRemote:FireServer("Attempt Join Party", joinPlr) end)
            if joinPlr ~= plr then
                pcall(function() PartyRemote:FireServer("Attempt Join Party", plr) end)
            end
            task.wait(0.2)
            if partySame(LP:FindFirstChild("Party"), plr:FindFirstChild("Party"))
                or (joinPlr and partySame(LP:FindFirstChild("Party"), joinPlr:FindFirstChild("Party"))) then
                ok = true
                break
            end
        end

        if ok then
            notify("Pacify", "Partied " .. plr.Name .. " — neither of you can land hits.")
        else
            local open = false
            pcall(function() open = joinPlr:HasTag("Attempt Party") or plr:HasTag("Attempt Party") end)
            if open then
                notify("Pacify", "Their invite is open but join didn't stick — try again.")
            else
                -- Keep our Attempt Party tag up so they can join US by facing + Party
                pcall(function() PartyRemote:FireServer("Attempt Party") end)
                notify("Pacify", plr.Name .. " has no open invite — your invite is open; they must Party you (or open theirs).")
            end
        end
    end
    function S.leaveParty()
        if PartyRemote then
            leaveMyParty()
            notify("Party", "Left your party.")
        else
            notify("Party", "Party remote missing.")
        end
    end
    function S.claimSpin()
        if not PlayerRemote then return end
        local sw = LP:FindFirstChild("UserData") and LP.UserData:FindFirstChild("SpinWheel")
        if sw and (os.time() - sw.Value) < 43200 then
            notify("Spin Wheel", "On cooldown (~" .. math.ceil((43200 - (os.time() - sw.Value)) / 3600) .. "h left).")
            return
        end
        PlayerRemote:FireServer("spin wheel", "free")
        notify("Spin Wheel", "Claimed your spin reward.")
    end

    task.spawn(function()
        while true do
            if not isCurrent() then break end
            if S.autoSpin and PlayerRemote then
                local sw = LP:FindFirstChild("UserData") and LP.UserData:FindFirstChild("SpinWheel")
                if sw and (os.time() - sw.Value) >= 43200 then
                    PlayerRemote:FireServer("spin wheel", "free")
                    notify("Auto Spin", "Claimed spin reward.")
                end
            end
            task.wait(5)
        end
    end)
end

-- Daily Rewards (legit, server-granted, 100% safe — the game's own claim remote used as intended) ---
do
    local DR = Remotes and Remotes:FindFirstChild("DailyRewards")
    local function canClaim()
        if not (DR and DR:FindFirstChild("GetStatus")) then return false end
        local ok, res = pcall(function() return DR.GetStatus:InvokeServer() end)
        return ok and type(res) == "table" and res.CanClaim == true
    end
    function S.claimDaily()
        if not (DR and DR:FindFirstChild("Claim")) then notify("Daily Reward", "Unavailable in this game.") return end
        if not canClaim() then notify("Daily Reward", "Already claimed — come back tomorrow.") return end
        local ok, res = pcall(function() return DR.Claim:InvokeServer() end)
        if ok and type(res) == "table" and res.Success then
            notify("Daily Reward", "Claimed today's reward.")
        else
            notify("Daily Reward", "Claim failed" .. ((type(res) == "table" and res.Message) and (": " .. tostring(res.Message)) or "."))
        end
    end
    S.autoDaily = false
    task.spawn(function()
        while true do
            if not isCurrent() then break end
            if S.autoDaily and canClaim() then
                pcall(function() DR.Claim:InvokeServer() end)
                notify("Auto Daily", "Claimed today's reward.")
            end
            task.wait(30)
        end
    end)
end

-- Target tab + its functions (focus target, teleport-to-target, Max Damage, freeze) were removed.

----------------------------------------------------------------------
-- Hotkey actions (shared by keyboard binds, gamepad binds, and mobile buttons)
----------------------------------------------------------------------
-- Manual slam (Slam Hotkey): search within slamHotkeyRange, walk into melee, Dive+Slam.
function manualSlam()
    if UserInputService:GetFocusedTextBox() then return end
    local now = tick()
    if now - lastHotkeySlam < (S.slamHotkeyCD or 0) then return end
    local c = myChar(); if not c or isRagdolled(c) then return end
    local t = nearest(S.slamHotkeyRange or 12)
    if not t or isRagdolled(t) then return end
    lastHotkeySlam = now
    lastSlam = now
    pcall(function() S.bypassCombatCooldowns(true) end)
    task.spawn(function()
        slam(t)
    end)
end

-- Godmode reach punch: full unblock -> guard -> hit -> reblock sequence on a chosen target.
local function godmodeHit(t)
    if not t then return end
    task.spawn(function()
        blockSuppressUntil = tick() + 0.2
        Combat:FireServer("Unblock", nil, nil); isBlocking = false
        task.wait(0.05)
        -- Land a Head hit; if they're blocking, Slam/dive-break them instead.
        if targetIsBlocking(t) then
            S.ragdollHit(t, true)
        else
            S.landHit(t, S.godmodeReach or 15, true)
        end
        task.wait(0.05)
        Combat:FireServer("Block", nil, nil); isBlocking = true; lastBlockFire = tick()
    end)
end
local function godmodeClickHit()
    if not S.godmode then return end
    godmodeHit(nearest(S.godmodeReach or 15))
end

-- Target picker that RESPECTS the given range: prefer the lock-on target only when it
-- is actually within range, otherwise the nearest enemy inside range (nil if none).
local function targetInRange(range)
    local hrp = myHRP(); if not hrp then return nil end
    local lt = lockTarget
    if lt and lt.Parent then
        local lth = lt:FindFirstChild("HumanoidRootPart")
        if lth and (lth.Position - hrp.Position).Magnitude <= range then return lt end
    end
    return nearest(range)
end

-- Rapid Punch: on each punch, throw a flurry of NORMAL punches at whoever you're locked onto (or
-- the nearest enemy inside Rapid Punch Range). Uses real body punches (NOT round kicks) so the
-- swing animation matches — one swing plays per hit, so you see all N punches. Own range so it
-- isn't a "kill aura" reaching across the map. Stops the instant they block. Re-entry guard: one
-- flurry at a time (the punch-anim hook fires on our OWN swings too, which would re-trigger it).
function S.doRapidPunch()
    if not S.rapidPunch or S.rapidActive or not isCombatSafe() then return end
    -- never punch while knocked down / ragdolled / dead
    local c0 = myChar()
    local h0 = c0 and c0:FindFirstChildOfClass("Humanoid")
    if not h0 or h0.Health <= 0 or h0.PlatformStand then return end
    local tr0 = c0 and c0:FindFirstChild("RagdollTrigger")
    if tr0 and tr0.Value then return end
    local hrp = myHRP()
    local range = S.rapidPunchRange or 12
    local t = (lockTarget and lockTarget.Parent) and lockTarget or nil
    if t then
        local th = t:FindFirstChild("HumanoidRootPart")
        if not th or (th.Position - hrp.Position).Magnitude > range then t = nil end
    end
    t = t or nearest(range)
    if not t then return end
    S.rapidActive = true
    task.spawn(function()
        if isBlocking then isBlocking = false; Combat:FireServer("Unblock", nil, nil); blockSuppressUntil = tick() + 0.3; stopBlockAnim() end
        local hits = math.max(1, math.floor(S.rapidPunchHits or 4))
        for i = 1, hits do
            local cur = t
            if not (cur and cur.Parent) then break end
            -- stop the flurry the moment they put up a block (the server rejects the hits anyway)
            if targetIsBlocking(cur) then break end
            local mh, ch = myHRP(), cur:FindFirstChild("HumanoidRootPart")
            if not (mh and ch) then break end
            if (ch.Position - mh.Position).Magnitude > range then
                cur = nearest(range); if not cur then break end
                if targetIsBlocking(cur) then break end
            end
            -- Real Body hit per swing; landHit bounded-approaches into range and faces.
            if not S.landHit(cur, range, false) then break end
            if i < hits then task.wait(0.1) end
        end
        S.rapidActive = false
    end)
end

-- One Tap (risky): on your punch, dump a fast burst of head hits into whoever you're locked onto
-- to drop them instantly. Each hit is server-capped (~15 dmg) and the server nullifies rapid hits
-- when its anti-cheat is watching — but this cheat neuters that anti-cheat on load, so the burst
-- lands and melts them near-instantly. Marked risky because it's blatant (a fresh player folding
-- the moment you touch them). No teleport. Stops early once they're dead. (S.flinging = debounce.)


-- Grab & Slam: teleport onto a target within Grab Range and slam them.
function grabSlam()
    if not isCombatSafe() then return end
    task.spawn(function()
        local t = targetInRange(S.grabSlamRange or 30)
        local thrp = t and t:FindFirstChild("HumanoidRootPart")
        local hrp = myHRP()
        if not (thrp and hrp) then return end
        local c = myChar(); if c and isRagdolled(c) then return end
        local originPos = hrp.Position
        local destPos = (thrp.CFrame * CFrame.new(0, 0, 2.6)).Position
        if S.aTrainFX then
            playATrainFX(originPos, destPos)
        end
        -- Post-2528: bounded stepped hop to the target (not one big teleport that trips the AC),
        -- then dive-ragdoll them in contact range.
        S.boundedTeleport(destPos, thrp.Position - destPos)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        task.wait(0.07)
        S.ragdollHit(t, false)
        lastSlam = tick()
    end)
end

function flashGhost()
    local char = myChar(); if not char then return end
    pcall(function()
        local col = S.flashRgb and Color3.fromHSV((tick() * 0.12) % 1, 0.8, 1) or S.flashStepColor or Color3.fromRGB(64, 200, 255)
        local ghost = Instance.new("Model")
        ghost.Name = "CAF2_FlashGhost"
        local count = 0
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart")
                and p.Name ~= "HumanoidRootPart"
                and (p.Transparency < 1 or p.Name == "Head")
                and p.Name:sub(1, 1) ~= "_" then
                local c = p:Clone()
                c:ClearAllChildren()
                c.Anchored = true; c.CanCollide = false; c.CanQuery = false; c.CanTouch = false; c.Massless = true
                c.CastShadow = false
                c.Transparency = 0.6
                c.Color = col
                c.Material = Enum.Material.SmoothPlastic
                c.Parent = ghost
                count = count + 1
            end
        end
        if count == 0 then ghost:Destroy(); return end
        ghost.Parent = Workspace
        local hl = Instance.new("Highlight")
        hl.FillColor = col
        hl.OutlineColor = col:Lerp(Color3.new(1, 1, 1), 0.5)
        hl.FillTransparency = 0.35
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Adornee = ghost
        hl.Parent = ghost
        task.spawn(function()
            task.wait(1.2)
            for i = 1, 16 do
                local f = i / 16
                hl.FillTransparency = math.min(1, 0.35 + f * 0.65)
                hl.OutlineTransparency = math.min(1, f)
                for _, part in ipairs(ghost:GetChildren()) do
                    if part:IsA("BasePart") then
                        part.Transparency = math.min(1, 0.4 + f * 0.6)
                    end
                end
                task.wait(0.03)
            end
            ghost:Destroy()
        end)
    end)
end

function flashBlinkFX(originPos, destPos)
    pcall(function()
        local diff = destPos - originPos
        local dist = diff.Magnitude
        if dist < 1 then return end
        local col = S.flashRgb and Color3.fromHSV((tick() * 0.12) % 1, 0.8, 1) or S.flashStepColor or Color3.fromRGB(64, 200, 255)
        local dir = diff.Unit
        local ref = math.abs(dir.Y) < 0.9 and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)
        local side = dir:Cross(ref).Unit
        local up2 = side:Cross(dir).Unit
        local segs = math.clamp(math.floor(dist / 1.5), 8, 35)
        local amp = math.min(dist * 0.18, 4)
        local bolt = Instance.new("Model"); bolt.Name = "CAF2_FlashBolt"; bolt.Parent = Workspace
        local prev = originPos
        local function createSegment(p1, p2, thicknessScale)
            local len = (p2 - p1).Magnitude
            if len < 0.01 then return end
            local cf = CFrame.new((p1 + p2) / 2, p2)
            local scale = thicknessScale or 1
            local outer = Instance.new("Part")
            outer.Anchored = true; outer.CanCollide = false; outer.CanQuery = false; outer.CanTouch = false; outer.CastShadow = false
            outer.Material = Enum.Material.Neon
            outer.Color = col
            outer.Transparency = 0.4
            outer.Size = Vector3.new(0.24 * scale, 0.24 * scale, len)
            outer.CFrame = cf
            outer.Parent = bolt
            local inner = Instance.new("Part")
            inner.Anchored = true; inner.CanCollide = false; inner.CanQuery = false; inner.CanTouch = false; inner.CastShadow = false
            inner.Material = Enum.Material.Neon
            inner.Color = Color3.new(1, 1, 1)
            inner.Transparency = 0.1
            inner.Size = Vector3.new(0.08 * scale, 0.08 * scale, len)
            inner.CFrame = cf
            inner.Parent = bolt
        end
        for i = 1, segs do
            local f = i / segs
            local base = originPos:Lerp(destPos, f)
            local taper = 1 - math.abs(f * 2 - 1)
            local off = (side * (math.random() - 0.5) + up2 * (math.random() - 0.5)) * 2 * amp * taper
            local pt = (i == segs) and destPos or (base + off)
            createSegment(prev, pt, 1)
            if i < segs and math.random() < 0.25 then
                task.spawn(function()
                    local bPrev = pt
                    local bDir = (dir + (side * (math.random() - 0.5) + up2 * (math.random() - 0.5)) * 1.5).Unit
                    local bSegs = math.random(2, 4)
                    local bLen = math.random(1.5, 3.5)
                    for j = 1, bSegs do
                        local bf = j / bSegs
                        local bTaper = 1 - (j / bSegs)
                        local bPt = bPrev + bDir * (bLen / bSegs) + (side * (math.random() - 0.5) + up2 * (math.random() - 0.5)) * 0.8 * bTaper
                        createSegment(bPrev, bPt, 0.5 * bTaper)
                        bPrev = bPt
                    end
                end)
            end
            prev = pt
        end
        task.spawn(function()
            task.wait(0.35)
            for k = 1, 15 do
                for _, s in ipairs(bolt:GetChildren()) do
                    if s:IsA("BasePart") then
                        s.Transparency = math.min(1, s.Transparency + 0.06)
                    end
                end
                task.wait(0.035)
            end
            bolt:Destroy()
        end)
    end)
    local char = myChar()
    if char then
        pcall(function()
            local col = S.rgbMode and Color3.fromHSV((tick() * 0.12) % 1, 0.8, 1) or S.flashStepColor or Color3.fromRGB(64, 200, 255)
            local hl = Instance.new("Highlight")
            hl.FillColor = col
            hl.OutlineColor = col:Lerp(Color3.new(1, 1, 1), 0.4)
            hl.FillTransparency = 0.55
            hl.OutlineTransparency = 0.3
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Adornee = char
            hl.Parent = char
            task.spawn(function()
                for k = 1, 10 do
                    hl.FillTransparency = math.min(1, 0.55 + k * 0.045)
                    hl.OutlineTransparency = math.min(1, 0.3 + k * 0.07)
                    task.wait(0.03)
                end
                hl:Destroy()
            end)
        end)
    end
end

function flashStep()
    if not isCombatSafe() then return end
    local hrp = myHRP(); if not hrp then return end
    local t = targetInRange(S.flashStepDistance or 25)
    local thrp = t and t:FindFirstChild("HumanoidRootPart")
    if not thrp then return end
    if S.flashSound then
        playSound("whoosh.wav", "https://remotion.media/whoosh.wav", 0.35)
    end
    local originPos = hrp.Position
    if S.flashStepAnim then flashGhost() end
    local head = t:FindFirstChild("Head")
    local look = (head and head.CFrame.LookVector) or thrp.CFrame.LookVector
    look = Vector3.new(look.X, 0, look.Z)
    if look.Magnitude < 0.05 then look = thrp.CFrame.LookVector end
    look = look.Unit
    local dest = thrp.Position - look * 1.5
    -- Bounded stepped blink so the AC sees plausible deltas instead of one big teleport.
    S.boundedTeleport(dest, look)
    local fh = myHRP()
    if fh then fh.AssemblyLinearVelocity = Vector3.zero; fh.AssemblyAngularVelocity = Vector3.zero end
    if S.flashStepAnim then flashBlinkFX(originPos, dest) end
end

-- Walkspeed: remember the game's real default so we can restore it exactly.
local WALK_BASE = 16
-- Jump OFF must restore CAF's real jump — NOT Roblox studio defaults (50 / 7.2).
-- Forcing 50/7.2 on execute was making people jump higher with nothing enabled.
local GAME_JP, GAME_JH = 50, 7.2
local GAME_USE_POWER = true
local gameJumpCaptured = false
local JUMP_POWER_BASE = 50
local JUMP_HEIGHT_BASE = 7.2
local jumpOurs = false -- true only while our Jump Power toggle is actively overriding

-- Capture CAF's actual jump once (or again on respawn if values look sane).
-- Reject already-boosted leftovers so we never bake a hack into the restore base.
local function captureGameJump(h, force)
    if not h then return end
    if gameJumpCaptured and not force then return end
    local jp = tonumber(h.JumpPower) or 0
    local jh = tonumber(h.JumpHeight) or 0
    if jp > 60 or jh > 12 or jp < 0 then
        if not gameJumpCaptured then
            GAME_JP, GAME_JH, GAME_USE_POWER = 50, 7.2, true
            gameJumpCaptured = true
        end
        return
    end
    -- jp == 0 with JumpHeight mode is valid (UseJumpPower false)
    GAME_JP = jp
    GAME_JH = (jh > 0 and jh) or GAME_JH
    GAME_USE_POWER = h.UseJumpPower and true or false
    JUMP_POWER_BASE = GAME_JP
    JUMP_HEIGHT_BASE = GAME_JH
    gameJumpCaptured = true
end

local function stripJumpMovers(char)
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local diving = false
    pcall(function()
        diving = S.touchFling and S._diveBusy and S._diveBusy()
    end)
    for _, d in ipairs(hrp:GetChildren()) do
        local n = d.Name
        if n == "CAF2_JumpLV" or n == "CAF2_JumpAtt"
            or n == "CAF2_FlyLV" or n == "CAF2_FlyAtt" then
            pcall(function() d:Destroy() end)
        elseif not diving and (n == "DiveVelocity" or n == "VelocityAttachment"
            or n == "CAF2_DiveLV" or n == "CAF2_DiveAtt") then
            -- Stuck bowling dive mover = fake jump boost. Never touch mid-dive.
            pcall(function() d:Destroy() end)
        end
    end
end

-- Jump Power OFF → put back the game's jump (not a hardcoded studio default).
local function restoreGameJump(hum)
    if not hum or S.jumpEnabled then return end
    jumpOurs = false
    if not gameJumpCaptured then captureGameJump(hum) end
    pcall(function()
        hum.UseJumpPower = GAME_USE_POWER
        hum.JumpPower = GAME_JP
        hum.JumpHeight = GAME_JH
    end)
end
-- Back-compat name used elsewhere
local function sanitizeJumpSpawn(hum)
    restoreGameJump(hum)
end

do
    local h = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if h then
        if h.WalkSpeed > 0 then WALK_BASE = h.WalkSpeed end
        -- MUST capture before any reset/sanitize writes
        captureGameJump(h)
    end
end
Maid:Give(LP.CharacterAdded:Connect(function(c)
    -- New body: clear hop state so a prior life's boost can never stick.
    jumpOurs = false
    pcall(function() if S._stopJumpAssist then S._stopJumpAssist() end end)
    task.defer(function() stripJumpMovers(c) end)

    local h = c:WaitForChild("Humanoid", 5)
    if h then
        if not (S.walkEnabled and S.walkActive) and h.WalkSpeed > 0 then WALK_BASE = h.WalkSpeed end
        task.defer(function()
            applyWalk()
            if S.jumpEnabled then
                applyJump()
            else
                -- Re-read this life's game jump (don't overwrite with 50/7.2).
                captureGameJump(h, true)
                stripJumpMovers(c)
            end
            applyNoFall()
        end)
        if not S.jumpEnabled then
            for _, delaySec in ipairs({ 0.15, 0.5, 1.0 }) do
                task.delay(delaySec, function()
                    if not h.Parent or S.jumpEnabled then return end
                    captureGameJump(h, true)
                    stripJumpMovers(c)
                end)
            end
        end
    end
end))

-- Jump Power OFF: only strip leftover movers + undo real boosts. Never force 50/7.2.
Maid:Give(RunService.Heartbeat:Connect(function()
    if not isCurrent() or S.jumpEnabled then return end
    local char = myChar()
    if not char then return end
    stripJumpMovers(char)
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if not gameJumpCaptured then captureGameJump(hum) end
    local jp = tonumber(hum.JumpPower) or 0
    local jh = tonumber(hum.JumpHeight) or 0
    -- Only intervene when jump is clearly boosted above the game's own values
    if jp > GAME_JP + 1.0 or jh > GAME_JH + 0.25 then
        restoreGameJump(hum)
    end
end))
-- Soft-cancel fall impact states (FallingDown / hard Landed) while no-fall is on.
Maid:Give(LP.CharacterAdded:Connect(function(c)
    local hum = c:WaitForChild("Humanoid", 5)
    if not hum then return end
    Maid:Give(hum.StateChanged:Connect(function(_, new)
        if not S.noFallDamage then return end
        if new == Enum.HumanoidStateType.FallingDown then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
        elseif new == Enum.HumanoidStateType.Landed then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
            local hrp = c:FindFirstChild("HumanoidRootPart")
            if hrp then
                local v = hrp.AssemblyLinearVelocity
                if v.Y < 0 then
                    hrp.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
                end
            end
        end
    end))
end))
if LP.Character then
    local hum0 = LP.Character:FindFirstChildOfClass("Humanoid")
    if hum0 then
        Maid:Give(hum0.StateChanged:Connect(function(_, new)
            if not S.noFallDamage then return end
            if new == Enum.HumanoidStateType.FallingDown then
                pcall(function() hum0:ChangeState(Enum.HumanoidStateType.GettingUp) end)
            elseif new == Enum.HumanoidStateType.Landed then
                pcall(function() hum0:ChangeState(Enum.HumanoidStateType.Running) end)
            end
        end))
    end
end
local function applyWalk()
    local hum = myChar() and myChar():FindFirstChildOfClass("Humanoid")
    if not hum then return end
    hum.WalkSpeed = (S.walkEnabled and S.walkActive) and S.walkspeedValue or WALK_BASE
end
local function applyJump()
    local hum = myChar() and myChar():FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if S.jumpEnabled then
        if not jumpOurs then
            -- Keep GAME_* as restore target; only refresh if current looks like real CAF jump.
            captureGameJump(hum, false)
            jumpOurs = true
        end
        local jp = S.jumpPowerValue or 50
        hum.UseJumpPower = true
        if jp > 55 then
            -- Zero humanoid jump — JumpRequest drives the AC-safe controlled hop.
            hum.JumpPower = 0
            hum.JumpHeight = 0
        else
            -- Only raise JumpPower; keep game JumpHeight (don't invent jp/5).
            hum.JumpPower = jp
            hum.JumpHeight = GAME_JH
        end
    else
        -- Toggle OFF → CAF's real jump + strip our movers. Never force studio 50/7.2.
        pcall(function() if S._stopJumpAssist then S._stopJumpAssist() end end)
        stripJumpMovers(myChar())
        jumpOurs = false
        restoreGameJump(hum)
    end
end

-- Hard reset: strip hop leftovers, restore CAF jump (not Roblox defaults).
local function resetJumpHard()
    jumpOurs = false
    S.jumpEnabled = false
    pcall(function() if S._stopJumpAssist then S._stopJumpAssist() end end)
    local char = myChar()
    if not char then return end
    stripJumpMovers(char)
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hrp then
        pcall(function()
            local v = hrp.AssemblyLinearVelocity
            if v.Y > 40 or v.Y < -120 then
                hrp.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
            end
        end)
    end
    if hum then
        -- If we never captured yet, read NOW before any write (execute path).
        if not gameJumpCaptured then captureGameJump(hum) end
        restoreGameJump(hum)
        pcall(function() hum.PlatformStand = false end)
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true) end)
    end
end

----------------------------------------------------------------------
-- High jump AC bypass: raw JumpPower >~70 freefalls peak high enough that
-- CAF position AC snaps you back (~1.6s). Controlled PlatformStand +
-- LinearVelocity hop (up then soft descent) does NOT rubberband — live-
-- verified to ~120 stud peaks. JumpPower ≤55 stays as normal humanoid jump.
----------------------------------------------------------------------
do
    local jumpBusy = false
    local jumpConn

    local function peakFromJP(jp)
        -- Slider 50→~16 studs (normal), 100→~41, 250→~110 (capped).
        return math.clamp(16 + (math.max(jp, 50) - 50) * 0.47, 16, 110)
    end

    local function stopJumpAssist()
        if jumpConn then pcall(function() jumpConn:Disconnect() end); jumpConn = nil end
        local char = myChar()
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hrp then
            for _, d in ipairs(hrp:GetChildren()) do
                if d.Name == "CAF2_JumpLV" or d.Name == "CAF2_JumpAtt" then
                    pcall(function() d:Destroy() end)
                end
            end
        end
        if hum and not (S.fly and S.flyActive) then
            pcall(function() hum.PlatformStand = false end)
        end
        jumpBusy = false
    end

    local function doControlledHop()
        if jumpBusy then return end
        if not S.jumpEnabled then return end
        if S.fly and S.flyActive then return end
        local jp = S.jumpPowerValue or 50
        if jp <= 55 then return end

        local char = myChar()
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not (hrp and hum) or hum.Health <= 0 then return end

        jumpBusy = true
        local peakTarget = peakFromJP(jp)
        local maxVy = 75
        local upTime = math.clamp(peakTarget / maxVy, 0.35, 1.55)
        local upVy = math.clamp(peakTarget / upTime, 28, maxVy)
        local downTime = upTime * 1.15
        local total = upTime + downTime
        local t0 = os.clock()

        hum.PlatformStand = true
        local att = Instance.new("Attachment")
        att.Name = "CAF2_JumpAtt"
        att.Parent = hrp
        local lv = Instance.new("LinearVelocity")
        lv.Name = "CAF2_JumpLV"
        lv.Attachment0 = att
        lv.RelativeTo = Enum.ActuatorRelativeTo.World
        lv.MaxForce = 1e9
        lv.VectorVelocity = Vector3.zero
        lv.Parent = hrp

        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude

        if jumpConn then pcall(function() jumpConn:Disconnect() end) end
        jumpConn = Maid:Give(RunService.Heartbeat:Connect(function()
            if not (S.jumpEnabled and jumpBusy) then
                stopJumpAssist()
                return
            end
            char = myChar()
            hrp = char and char:FindFirstChild("HumanoidRootPart")
            hum = char and char:FindFirstChildOfClass("Humanoid")
            if not (hrp and lv and lv.Parent == hrp) then
                stopJumpAssist()
                return
            end
            if hum then hum.PlatformStand = true end

            local elapsed = os.clock() - t0
            local look = Workspace.CurrentCamera.CFrame.LookVector
            local flat = Vector3.new(look.X, 0, look.Z)
            local hx, hz = 0, 0
            local md = hum and hum.MoveDirection or Vector3.zero
            if md.Magnitude > 0.05 then
                hx, hz = md.X * 16, md.Z * 16
            elseif flat.Magnitude > 0.1 then
                flat = flat.Unit * 12
                hx, hz = flat.X, flat.Z
            end

            if elapsed < upTime then
                lv.MaxForce = 1e9
                lv.VectorVelocity = Vector3.new(hx, upVy, hz)
            elseif elapsed < total then
                lv.MaxForce = 1e9
                lv.VectorVelocity = Vector3.new(hx, -math.clamp(upVy * 0.9, 20, 55), hz)
                rayParams.FilterDescendantsInstances = { char }
                local hit = Workspace:Raycast(hrp.Position, Vector3.new(0, -5.5, 0), rayParams)
                if hit then
                    lv.VectorVelocity = Vector3.zero
                    lv.MaxForce = 0
                    stopJumpAssist()
                end
            else
                stopJumpAssist()
            end
        end))
    end

    Maid:Give(UserInputService.JumpRequest:Connect(function()
        if not isCurrent() then return end
        if not S.jumpEnabled then return end
        if (S.jumpPowerValue or 50) <= 55 then return end
        doControlledHop()
    end))

    Maid:Give(LP.CharacterAdded:Connect(function()
        stopJumpAssist()
    end))

    -- Expose so unload / toggle-off can clear mid-hop.
    S._stopJumpAssist = stopJumpAssist
end
local function applyNoFall()
    local hum = myChar() and myChar():FindFirstChildOfClass("Humanoid")
    if not hum then return end
    -- FallingDown is the stumble/impact state that usually applies fall damage.
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, not S.noFallDamage)
    end)
end
-- Hotkey / mobile button: flip the boost while the feature is enabled.
local function toggleWalk()
    if not S.walkEnabled then return end
    S.walkActive = not S.walkActive
    applyWalk()
end

----------------------------------------------------------------------
-- Mobile floating action buttons (only visible while their feature is enabled)
----------------------------------------------------------------------
local function makeActionButton(labelTxt, color, yPos, onTap)
    local f = new("Frame", {
        Name = "ActionBtn_" .. labelTxt, Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(20, yPos),
        BackgroundColor3 = C.Ink1, BackgroundTransparency = 0.05, BorderSizePixel = 0, ZIndex = 10,
        Visible = false, Active = true,
    }, ScreenGui)
    Maid:GiveInst(f)
    corner(f, 28)
    gradient(f, C.Ink3, C.Ink0, 90)
    local ring = stroke(f, C.Red, 1.6, 0.25)
    local glow = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 12, 1, 12),
        BackgroundColor3 = C.Red, BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 9,
    }, f)
    corner(glow, 34)
    local scaleObj = new("UIScale", { Scale = 1 }, f)
    new("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = labelTxt, TextColor3 = C.Text,
        Font = Enum.Font.GothamBlack, TextSize = 12, ZIndex = 11,
    }, f)

    local dragging, dragMoved, dragStart, startPos = false, false, nil, nil
    Maid:Give(f.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true; dragMoved = false; dragStart = i.Position; startPos = f.Position
            tw(scaleObj, SNAP, { Scale = 0.9 }):Play()
            tw(ring, SNAP, { Transparency = 0, Color = C.RedHi }):Play()
        end
    end))
    Maid:Give(f.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
            local d = i.Position - dragStart
            if d.Magnitude > 6 then dragMoved = true end
            f.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    Maid:Give(f.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
            tw(scaleObj, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
            tw(ring, SNAP, { Transparency = 0.25, Color = C.Red }):Play()
            if not dragMoved then pcall(onTap) end
            dragging = false
        end
    end))
    return f
end

local punchBtn = makeActionButton("PUNCH", nil, 160, godmodeClickHit)
local slamBtn  = makeActionButton("SLAM",  nil, 224, manualSlam)
local grabBtn  = makeActionButton("GRAB",  nil, 288, grabSlam)
local flashBtn = makeActionButton("FLASH", nil, 352, flashStep)
local walkBtn  = makeActionButton("SPEED", nil, 416, toggleWalk)
local flyBtn   = makeActionButton("FLY",   nil, 480, function() if S.toggleFly then S.toggleFly() end end)
local function showPunchBtn(v) punchBtn.Visible = v and true or false end
local function showSlamBtn(v)  slamBtn.Visible  = v and true or false end
local function showGrabBtn(v)  grabBtn.Visible  = v and true or false end
local function showFlashBtn(v) flashBtn.Visible = v and true or false end
local function showWalkBtn(v)  walkBtn.Visible  = v and true or false end
local function showFlyBtn(v)   flyBtn.Visible   = v and true or false end

----------------------------------------------------------------------
-- Cheaters Safe Zone: drop far under the map onto a private black platform, out of combat and
-- away from everyone; return snaps you back (used by the Protection tab button). ONE platform +
-- ONE safety net (fixed depth = no drift, no "fell out the map"). Hung on S (not a new top-level
-- local — the main chunk is near Luau's 200-register ceiling; config only serializes UIControls).
----------------------------------------------------------------------
S.SafeZone = {}
do
    local SafeZone = S.SafeZone   -- block-local alias (no top-level register cost)
    local platform, savedCF, holdConn = nil, nil, nil
    local SAFE_MARGIN = 60        -- how far ABOVE the world's destroy plane the platform sits

    local function stopHold()
        if holdConn then pcall(function() holdConn:Disconnect() end); holdConn = nil end
    end

    function SafeZone.isActive() return S.safeZone == true end

    function SafeZone.leave()
        stopHold()
        S.safeZone = false        -- farm resumes
        if platform then pcall(function() platform:Destroy() end); platform = nil end
        if savedCF then
            -- Stepped climb back up so the long return doesn't trip the position AC.
            S.boundedTeleport(savedCF.Position, savedCF.LookVector)
            local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if h then h.AssemblyLinearVelocity = Vector3.zero end
        end
    end

    function SafeZone.enter()
        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        -- only record a return point if we're up in the real map (never save a safe-zone/void position)
        if hrp.Position.Y > -200 then savedCF = hrp.CFrame end
        S.safeZone = true         -- PAUSE the farm (stays enabled, auto-resumes on return)
        S.noclip = false
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = false end
        for _, pt in ipairs(char:GetDescendants()) do if pt:IsA("BasePart") then pt.CanCollide = true end end
        farmCFrame = nil          -- release the farm's per-frame pin so the TP sticks
        if platform then pcall(function() platform:Destroy() end); platform = nil end
        -- Sit a fixed margin ABOVE the world's FallenPartsDestroyHeight: far down, but never past
        -- the plane that deletes the character (crossing it is the real "fall out the map" bug).
        local safeY = workspace.FallenPartsDestroyHeight + SAFE_MARGIN
        local topY = safeY + 2
        local base = Vector3.new(hrp.Position.X, safeY, hrp.Position.Z)
        local p = Instance.new("Part")
        p.Size = Vector3.new(400, 4, 400)
        p.Anchored = true
        p.CanCollide = true
        p.Color = Color3.new(0, 0, 0)
        p.Material = Enum.Material.SmoothPlastic
        p.TopSurface = Enum.SurfaceType.Smooth
        p.Position = base
        p.Name = "CheatersSafeZone"
        p.Parent = workspace
        platform = p
        task.wait()               -- let the pin release a frame before TP
        -- Stepped descent so the deep drop doesn't trip the position AC (it kicks on big jumps).
        S.boundedTeleport(Vector3.new(base.X, topY + 3, base.Z), nil)
        local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if h then h.AssemblyLinearVelocity = Vector3.zero end
        -- Safety net (bidirectional): snap us back onto the platform if anything pulls us off it.
        stopHold()
        holdConn = Maid:Give(RunService.Heartbeat:Connect(function()
            if not S.safeZone or not platform or platform.Parent ~= workspace then return end
            local cc = LP.Character
            local hh = cc and cc:FindFirstChild("HumanoidRootPart")
            if not hh then return end
            local pp = platform.Position
            local dx, dz = hh.Position.X - pp.X, hh.Position.Z - pp.Z
            local offPlatform = hh.Position.Y < topY - 4 or hh.Position.Y > topY + 60
                or (dx * dx + dz * dz) > (190 * 190)
            if offPlatform then
                hh.CFrame = CFrame.new(pp.X, topY + 3, pp.Z)
                hh.AssemblyLinearVelocity = Vector3.zero
            end
        end))
    end

    function SafeZone.toggle()
        if S.safeZone then SafeZone.leave() else SafeZone.enter() end
    end
end


----------------------------------------------------------------------
-- FPS optimizer: GENTLE — cuts only the expensive extras (particle FX,
-- dynamic light shadows, post-processing, terrain grass, bushes/foliage)
-- and disables part shadows. It NEVER touches player characters or
-- collidable structural meshes (walls/floors), so the map stays walkable.
----------------------------------------------------------------------
function S.optimizeFPS()
    local removed = 0
    local function nuke(inst)
        if not inst then return end
        pcall(function() inst:Destroy() end)
        removed = removed + 1
    end

    -- Lighting: shadows off + drop post-processing polish. KEEP Sky / Atmosphere /
    -- Clouds / ColorCorrection so the world still looks like the real game.
    pcall(function()
        local Lighting = game:GetService("Lighting")
        Lighting.GlobalShadows = false
        for _, e in ipairs(Lighting:GetChildren()) do
            if e:IsA("BloomEffect") or e:IsA("BlurEffect")
                or e:IsA("SunRaysEffect") or e:IsA("DepthOfFieldEffect") then
                nuke(e)
            end
        end
    end)

    -- Terrain: only turn off grass decoration + calm the water waves. Water and its
    -- look stay (no transparency/reflectance wipe that made it vanish before).
    pcall(function()
        local t = Workspace.Terrain
        t.WaterWaveSize = 0
        t.WaterWaveSpeed = 0
        pcall(function() t.Decoration = false end)
    end)

    -- Rendering quality: force the LOWEST level. This keeps textures/meshes/materials (so it still
    -- looks like the real game) but cuts render distance, shadow detail, particle count and mesh LOD
    -- — the big FPS win. (Level05 before was often HIGHER than the device's auto pick, which added
    -- load instead of cutting it — that's why it felt laggier.)
    pcall(function()
        local UserSettings = UserSettings()
        local gs = UserSettings:GetService("UserGameSettings")
        gs.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
    end)
    pcall(function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    end)

    -- Is this instance part of a player / NPC character? (walk up to a Model with a Humanoid)
    local function inCharacter(inst)
        local m = inst
        for _ = 1, 6 do
            m = m.Parent
            if not m or m == Workspace then break end
            if m:FindFirstChildOfClass("Humanoid") then return true end
        end
        return false
    end

    local function looksLikeBush(inst)
        local n = string.lower(tostring(inst.Name or ""))
        -- foliage / vegetation clutter (keep trees' trunks if collidable via MeshPart rule below)
        if n:find("bush", 1, true) or n:find("shrub", 1, true) or n:find("hedge", 1, true)
            or n:find("foliage", 1, true) or n:find("weed", 1, true) or n:find("fern", 1, true)
            or n:find("flower", 1, true) or n:find("plant", 1, true) or n:find("grass", 1, true)
            or n:find("ivy", 1, true) or n:find("vine", 1, true) or n:find("leaf", 1, true)
            or n:find("leaves", 1, true) or n:find("brush", 1, true) then
            return true
        end
        return false
    end

    -- Per-instance: cut the heavy extras + decorative clutter meshes + named bushes.
    local function strip(obj)
        if not obj then return end
        if inCharacter(obj) then return end

        -- Explicit bush / foliage models & folders (whole cluster goes)
        if (obj:IsA("Model") or obj:IsA("Folder")) and looksLikeBush(obj) then
            nuke(obj); return
        end
        if (obj:IsA("BasePart") or obj:IsA("MeshPart") or obj:IsA("UnionOperation")) and looksLikeBush(obj) then
            nuke(obj); return
        end

        if obj:IsA("MeshPart") then
            -- Remove the extra decorative meshes: non-collidable (you walk through them, so removing
            -- them never breaks the map's structure/navigation) and not part of a character. Keep
            -- collidable meshes (walls/floors/props you stand on) so the world stays intact.
            if not obj.CanCollide then
                nuke(obj); return
            end
            pcall(function() obj.CastShadow = false end)
            return
        end
        if obj:IsA("BasePart") then
            pcall(function() obj.CastShadow = false end)   -- shadows are pure cost, no look loss on low
            return
        end
        if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
            or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") or obj:IsA("Explosion") then
            nuke(obj); return
        end
        if obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
            pcall(function() obj.Shadows = false end)       -- keep the light, drop its shadow cost
            return
        end
    end

    pcall(function()
        for _, d in ipairs(Workspace:GetDescendants()) do strip(d) end
    end)

    -- Keep cutting FX / bushes on streamed-in assets for a short window.
    local conn
    local untilT = os.clock() + 8
    conn = Workspace.DescendantAdded:Connect(function(d)
        if os.clock() > untilT then
            if conn then conn:Disconnect() end
            return
        end
        task.defer(strip, d)
    end)
    Maid:Give(conn)
    task.delay(8.2, function() if conn then pcall(function() conn:Disconnect() end) end end)

    notify("FPS Optimize", "Cut FX / shadows / grass / bushes (" .. tostring(removed) .. " removed).")
end

----------------------------------------------------------------------
-- First person — toggle arms the feature; camera only while Guard (fists) is on.
-- Hides head + accessories in FP. Never overwrites HRP (that broke punches/anims).
-- Menu stays open on top during FP; mouse/look free when menu is open.
----------------------------------------------------------------------
;(function()
    local saved = { min = nil, max = nil, fov = nil, mode = nil, camType = nil, subject = nil, mouse = nil }
    local lookYaw, lookPitch = 0, 0
    local smoothEye = nil
    local smoothCF = nil
    local fpActive = false
    local hideRestore = {}
    local FP_MOUSE_SENS = 0.0028
    -- Lock-on: high enough to feel snappy, low enough to avoid hard snaps
    local FP_LOCK_SMOOTH = 16
    local hideAccAccum = 0
    local guardHeldSince = 0
    local GUARD_ENTER_DELAY = 0.15

    local function getCam()
        return Workspace.CurrentCamera
    end

    local function lerpAngle(a, b, t)
        local d = (b - a + math.pi) % (math.pi * 2) - math.pi
        return a + d * t
    end

    -- Closest living enemy within FP Lock Range (0–10). Only while Guard is actually out.
    -- Never force / keep FP by itself — Lock On only steers an already-active FP camera.
    local function fpLockAllowed()
        if S.firstPerson ~= true or S.firstPersonLockOn ~= true then return false end
        if not fpActive then return false end
        if fpBlockForcedGuard then return false end
        if S.killAura or S.godmode then return false end
        local char = LP.Character
        if not char then return false end
        local ok, tagged = pcall(function() return char:HasTag("Guarding") end)
        return ok and tagged == true
    end

    local function resolveFpLockAim(eyePos)
        if not fpLockAllowed() then return nil end
        local range = math.clamp(tonumber(S.firstPersonLockRange) or 10, 0, 10)
        if range <= 0 then return nil end
        local t = nearest(range)
        if not t or not t.Parent then return nil end
        local part = t:FindFirstChild("Head") or t:FindFirstChild("HumanoidRootPart")
        if not part then return nil end
        if (part.Position - eyePos).Magnitude > range then return nil end
        lockTarget = t
        return part.Position
    end

    local function isGuardingNow()
        local char = LP.Character
        if not char then return false end
        local ok, tagged = pcall(function() return char:HasTag("Guarding") end)
        return ok and tagged == true
    end

    -- Toggle arms the feature; camera only while YOU have Guard (fists) out.
    -- Ignore Guarding forced by Kill Aura / godmode / auto-block force-equip.
    -- Do NOT exit FP when Auto Block holds Block — Safe Block + FP should stay locked in.
    -- FP Lock On must NEVER keep FP alive without Guard.
    local function wantFirstPerson()
        if S.firstPerson ~= true then
            guardHeldSince = 0
            return false
        end
        if not isGuardingNow() then
            guardHeldSince = 0
            fpBlockForcedGuard = false
            return false
        end
        -- Auto-block/godmode force-equip must never count as "fists out" for FP
        if fpBlockForcedGuard then return false end
        if S.killAura or S.godmode then return false end
        if guardHeldSince <= 0 then
            guardHeldSince = tick()
        end
        return (tick() - guardHeldSince) >= GUARD_ENTER_DELAY
    end

    local function cameraLooksStuckFp()
        local c = getCam()
        if not c then return false end
        if LP.CameraMode == Enum.CameraMode.LockFirstPerson then return true end
        if LP.CameraMaxZoomDistance <= 1 then return true end
        if c.CameraType == Enum.CameraType.Scriptable then return true end
        return false
    end

    -- Gentle unlock only. NEVER write cam.CFrame/Focus here — that kills Roblox's
    -- default RMB / touch orbit for desktop + mobile until you rejoin.
    local lastHardTp = 0
    local function hardThirdPerson(forceZoomOut)
        lastHardTp = tick()
        local c = getCam()
        local char = LP.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")

        pcall(function() LP.CameraMode = Enum.CameraMode.Classic end)
        LP.CameraMaxZoomDistance = 128
        if forceZoomOut then
            -- one-shot pop out of FP zoom distance (do not leave MinZoom elevated)
            LP.CameraMinZoomDistance = 8
        else
            LP.CameraMinZoomDistance = 0.5
        end
        pcall(function()
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            UserInputService.MouseIconEnabled = true
        end)
        if hum then
            pcall(function() hum.CameraOffset = Vector3.zero end)
        end
        if c then
            c.FieldOfView = (saved.fov and saved.fov > 1) and saved.fov or 70
            pcall(function()
                c.CameraType = Enum.CameraType.Custom
                if hum then c.CameraSubject = hum end
            end)
        end
        if forceZoomOut then
            task.defer(function()
                if fpActive then return end
                LP.CameraMinZoomDistance = 0.5
                LP.CameraMaxZoomDistance = 128
            end)
            task.delay(0.1, function()
                if fpActive then return end
                LP.CameraMinZoomDistance = 0.5
                LP.CameraMaxZoomDistance = 128
                pcall(function()
                    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
                    local cam = getCam()
                    local h = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
                    if cam then
                        cam.CameraType = Enum.CameraType.Custom
                        if h then cam.CameraSubject = h end
                    end
                end)
            end)
        end
        saved.min, saved.max, saved.fov, saved.mode = nil, nil, nil, nil
        saved.camType, saved.subject, saved.mouse = nil, nil, nil
    end

    local function clearFpHide()
        for inst, prev in pairs(hideRestore) do
            if inst and inst.Parent then
                pcall(function()
                    if inst:IsA("BasePart") then
                        inst.LocalTransparencyModifier = prev
                    elseif inst:IsA("Decal") or inst:IsA("Texture") then
                        inst.Transparency = prev
                    end
                end)
            end
            hideRestore[inst] = nil
        end
    end

    local function hideHeadAndAccessories(char)
        clearFpHide()
        if not char then return end
        local function hidePart(p)
            if not p or hideRestore[p] ~= nil then return end
            if p:IsA("BasePart") then
                hideRestore[p] = p.LocalTransparencyModifier
                p.LocalTransparencyModifier = 1
            end
        end
        local head = char:FindFirstChild("Head")
        if head then
            hidePart(head)
            for _, d in ipairs(head:GetDescendants()) do
                if d:IsA("Decal") or d:IsA("Texture") then
                    if hideRestore[d] == nil then
                        hideRestore[d] = d.Transparency
                        d.Transparency = 1
                    end
                elseif d:IsA("BasePart") then
                    hidePart(d)
                end
            end
        end
        for _, acc in ipairs(char:GetChildren()) do
            if acc:IsA("Accessory") or acc:IsA("Hat") then
                for _, d in ipairs(acc:GetDescendants()) do
                    if d:IsA("BasePart") then
                        hidePart(d)
                    elseif d:IsA("Decal") or d:IsA("Texture") then
                        if hideRestore[d] == nil then
                            hideRestore[d] = d.Transparency
                            d.Transparency = 1
                        end
                    end
                end
            end
        end
    end

    local function resetAvatarVisuals(char)
        clearFpHide()
        if not char then return end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then
                pcall(function() p.LocalTransparencyModifier = 0 end)
            elseif (p:IsA("Decal") or p:IsA("Texture")) and (p.Name == "face" or p.Name == "Face") then
                pcall(function() if p.Transparency >= 1 then p.Transparency = 0 end end)
            end
        end
        local head = char:FindFirstChild("Head")
        if head and head:IsA("BasePart") then
            pcall(function() head.LocalTransparencyModifier = 0; head.Transparency = 0 end)
        end
        for _, acc in ipairs(char:GetChildren()) do
            if acc:IsA("Accessory") or acc:IsA("Hat") then
                for _, d in ipairs(acc:GetDescendants()) do
                    if d:IsA("BasePart") then
                        pcall(function() d.LocalTransparencyModifier = 0; d.Transparency = 0 end)
                    elseif d:IsA("Decal") or d:IsA("Texture") then
                        pcall(function() d.Transparency = 0 end)
                    end
                end
            end
        end
    end

    -- Keep the suite GUI open while FP is active (user can still toggle with RightShift / V).
    -- Previously closed the menu so clicks punched — now clicks hit the GUI when it's open,
    -- and punch/look only when the menu is closed (existing uiVisible guards).
    local function keepMenuOnTop()
        pcall(function()
            if ScreenGui then
                ScreenGui.DisplayOrder = 1000000
                ScreenGui.Enabled = true
            end
        end)
    end

    local function apply(on)
        local c = getCam()
        local char = LP.Character
        if on then
            if saved.min == nil then
                saved.min = LP.CameraMinZoomDistance
                saved.max = LP.CameraMaxZoomDistance
                saved.fov = (c and c.FieldOfView) or 70
                saved.mode = LP.CameraMode
                saved.camType = c and c.CameraType
                saved.subject = c and c.CameraSubject
                saved.mouse = UserInputService.MouseBehavior
            end
            keepMenuOnTop()
            do
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local look = hrp.CFrame.LookVector
                    lookYaw = math.atan2(-look.X, -look.Z)
                else
                    lookYaw = 0
                end
                lookPitch = 0
                smoothEye, smoothCF = nil, nil
            end
            pcall(function() LP.CameraMode = Enum.CameraMode.Classic end)
            LP.CameraMinZoomDistance = 0.5
            LP.CameraMaxZoomDistance = 0.5
            if c then
                c.FieldOfView = math.clamp(S.firstPersonFov or 100, 70, 120)
                pcall(function() c.CameraType = Enum.CameraType.Scriptable end)
            end
            -- Menu open → free mouse so toggles still work. Closed → LockCenter look (desktop).
            -- Touch devices always Default (TouchMoved handles look).
            if UserInputService.TouchEnabled or uiVisible then
                pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
            else
                pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter end)
            end
            hideHeadAndAccessories(char)
        else
            hardThirdPerson(true)
            resetAvatarVisuals(char)
        end
    end

    local function setActive(on)
        on = on and true or false
        if on then
            if fpActive then
                hideHeadAndAccessories(LP.Character)
                return
            end
            fpActive = true
            apply(true)
            return
        end
        fpActive = false
        smoothEye, smoothCF = nil, nil
        lookYaw, lookPitch = 0, 0
        apply(false)
    end

    local function forceStopFp()
        S.firstPerson = false
        fpActive = false
        guardHeldSince = 0
        smoothEye, smoothCF = nil, nil
        lookYaw, lookPitch = 0, 0
        hardThirdPerson(true)
        resetAvatarVisuals(LP.Character)
    end

    S._setFirstPerson = function(v)
        S.firstPerson = v and true or false
        if not S.firstPerson then
            forceStopFp()
        end
    end
    S._stopFirstPerson = forceStopFp
    S._fpActive = function() return fpActive end
    S._unlockCamera = function()
        hardThirdPerson(false)
    end

    -- Punch while FP: ensure swing anim plays even if Scriptable cam confuses the game client.
    -- Never restart mid-swing — spam was cancelling the anim and making punches look stuttery.
    local fpPunchTrack = nil
    Maid:Give(UserInputService.InputBegan:Connect(function(input, gp)
        if not fpActive or gp then return end
        if uiVisible then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if fpPunchTrack and fpPunchTrack.IsPlaying then return end
            if typeof(playPunchAnim) == "function" then
                local ok, tr = pcall(playPunchAnim)
                if ok and tr then fpPunchTrack = tr end
            end
        end
    end))

    -- Touch look for mobile FP (no LockCenter / no right-click). Skip while lock-on has a target.
    Maid:Give(UserInputService.TouchMoved:Connect(function(touch, gp)
        if not fpActive or gp or uiVisible then return end
        if not isGuardingNow() then return end
        if fpLockAllowed() then
            local eyeGuess = LP.Character and LP.Character:FindFirstChild("Head")
            local eyePos = eyeGuess and eyeGuess.Position or Vector3.zero
            if resolveFpLockAim(eyePos) then return end
        end
        local d = touch.Delta
        lookYaw = lookYaw - d.X * FP_MOUSE_SENS
        lookPitch = math.clamp(lookPitch - d.Y * FP_MOUSE_SENS, -1.15, 1.15)
    end))

    Maid:Give(RunService.RenderStepped:Connect(function(dt)
        if not isCurrent() then return end
        dt = math.clamp(dt or 0.016, 0.001, 0.05)
        local want = wantFirstPerson()
        if want then
            if not fpActive then setActive(true) end
        else
            if fpActive then
                setActive(false)
            elseif cameraLooksStuckFp() then
                -- If FP / Lock On were used, pop out of Scriptable + zoom-lock quickly when Guard drops.
                local aggressive = S.firstPerson == true or S.firstPersonLockOn == true
                if (tick() - lastHardTp) > (aggressive and 0.25 or 2) then
                    hardThirdPerson(aggressive)
                end
            end
            return
        end
        if not fpActive then return end
        -- Belt-and-suspenders: Lock On must not run without Guard this frame
        if not isGuardingNow() then
            setActive(false)
            return
        end

        local menuOpen = uiVisible == true
        local c = getCam()
        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local head = char and char:FindFirstChild("Head")
        if not (c and hrp) then return end

        local locking = fpLockAllowed()
        local eyePreview = (head and head.Position or hrp.Position + Vector3.new(0, 1.5, 0))
        local lockAim = locking and resolveFpLockAim(eyePreview) or nil

        if menuOpen or UserInputService.TouchEnabled then
            -- Menu open: free cursor so GUI stays usable on top of FP.
            -- Touch: look comes from TouchMoved (skipped while menu open).
            pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
        else
            local md = UserInputService:GetMouseDelta()
            -- Drain delta while locked so it doesn't dump when target drops
            if not lockAim and md.Magnitude > 0 then
                lookYaw = lookYaw - md.X * FP_MOUSE_SENS
                lookPitch = math.clamp(lookPitch - md.Y * FP_MOUSE_SENS, -1.15, 1.15)
                if lookYaw > math.pi then lookYaw = lookYaw - math.pi * 2
                elseif lookYaw < -math.pi then lookYaw = lookYaw + math.pi * 2 end
            end
            if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
                pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter end)
            end
        end

        hideAccAccum = hideAccAccum + dt
        if hideAccAccum >= 0.15 then
            hideAccAccum = 0
            hideHeadAndAccessories(char)
        end

        pcall(function()
            LP.CameraMode = Enum.CameraMode.Classic
            LP.CameraMinZoomDistance = 0.5
            LP.CameraMaxZoomDistance = 0.5
            c.CameraType = Enum.CameraType.Scriptable
            c.FieldOfView = math.clamp(S.firstPersonFov or 100, 70, 120)

            local eye = eyePreview + hrp.CFrame.LookVector * 0.08 + Vector3.new(0, 0.05, 0)

            if lockAim then
                local dir = lockAim - eye
                if dir.Magnitude > 0.05 then
                    dir = dir.Unit
                    local ty = math.atan2(-dir.X, -dir.Z)
                    local tp = math.clamp(math.asin(math.clamp(dir.Y, -1, 1)), -1.15, 1.15)
                    local a = 1 - math.exp(-dt * FP_LOCK_SMOOTH)
                    lookYaw = lerpAngle(lookYaw, ty, a)
                    lookPitch = lookPitch + (tp - lookPitch) * a
                end
            end

            c.CFrame = CFrame.new(eye)
                * CFrame.Angles(0, lookYaw, 0)
                * CFrame.Angles(lookPitch, 0, 0)
        end)
    end))
    Maid:Give(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        Cam = Workspace.CurrentCamera
        if fpActive then apply(true) end
    end))
    Maid:Give(LP.CharacterAdded:Connect(function()
        clearFpHide()
        guardHeldSince = 0
        if fpActive then setActive(false) end
    end))
end)()

----------------------------------------------------------------------
----------------------------------------------------------------------
-- Build the feature tabs
----------------------------------------------------------------------
local abToggle = nil
do
    do local g=(typeof(getgenv)=="function" and getgenv()) or _G; g.__CAF2_BOOT="tabs-combat" end
    local page = makeTab("Combat")
    toggle(page, "Global Safe Mode (Only Stand/Guard)", false, function(v) S.safeEverything = v end,
        "Safer combat rules — only act while you can stand/Guard.")

    section(page, "Kill Aura")
    toggle(page, "Kill Aura", false, function(v)
        S.killAura = v
        if v then
            silencePlayerHandsRunning()
            kaStanceReady = false
            lastPunch = 0
            lastKaFocus = nil
            lastKaStance = 0
            pcall(function() S.bypassCombatCooldowns(true) end)
            -- Immediate stance so first Heads aren't 0-damage
            pcall(function()
                Combat:FireServer("Fist", nil, nil)
                Combat:FireServer("Guarding", nil, nil)
            end)
        else
            kaStanceReady = false
            lastKaStance = 0
            lastKaUnblock = 0
            lastKaFocus = nil
            pcall(function() S.bypassCombatCooldowns(true) end)
        end
    end, "Steady Head melt on the nearest enemy. Tuned for consistency (not max spam). While on: skips Auto Block / Godmode Block / Ragdoll Aura / Auto Slam / Auto Unblock, and blocks game Hands/Unguard.")
    slider(page, "Kill Aura Range", 1, 7, 7, " studs", function(v) S.paRange = v end,
        "How far Kill Aura can reach.")
    slider(page, "Kill Aura Speed", 50, 200, 70, " ms", function(v) S.paCD = v / 1000 end,
        "Delay between bursts. Lower = faster; 70ms default stays consistent.")
    slider(page, "Kill Aura Hits", 1, 4, 2, "x", function(v) S.paHits = v end,
        "Heads per burst. 2 is the stable default.")
    toggle(page, "Kill Aura Visual Range", false, function(v) S.paVisualRange = v end,
        "Shows a ring for Kill Aura range.")

    section(page, "Rapid Punches")
    toggle(page, "Rapid Punches", false, function(v) S.rapidPunch = v end,
        "Fires a burst of punches at once.")
    slider(page, "Rapid Punches Power", 1, 10, 4, " punches", function(v) S.rapidPunchHits = v end,
        "How many punches per burst.")
    slider(page, "Rapid Punches Range", 4, 40, 12, " studs", function(v) S.rapidPunchRange = v end,
        "Max distance for rapid punches.")
    toggle(page, "Rapid Punches Visual Range", false, function(v) S.rapidPunchVisualRange = v end,
        "Shows a ring for rapid punch range.")

    section(page, "Reach")
    toggle(page, "Reach", false, function(v) S.reach = v end,
        "Extends how far your punches land.")
    slider(page, "Reach Range", 0, 200, 30, " studs", function(v) S.reachRange = v end,
        "Punch distance when Reach is on.")
    toggle(page, "Reach Visual Range", false, function(v) S.reachVisualRange = v end,
        "Shows a ring for Reach range.")

    section(page, "Ragdoll Aura")
    toggle(page, "Ragdoll Aura", false, function(v)
        S.ragdollAura = v
        if v then
            silencePlayerHandsRunning()
            pcall(function() S.bypassCombatCooldowns(true) end)
        else
            pcall(function() S.bypassCombatCooldowns(true) end)
        end
    end, "Auto-ragdolls enemies near you.")
    slider(page, "Ragdoll Aura Range", 1, 7, 6, " studs", function(v) S.raRange = v end,
        "How far Ragdoll Aura reaches.")
    slider(page, "Ragdoll Aura Cooldown", 0, 1000, 0, " ms", function(v) S.raCD = v / 1000 end,
        "Wait between ragdoll attempts.")
    toggle(page, "Ragdoll Aura Visual Range", false, function(v) S.raVisualRange = v end,
        "Shows a ring for Ragdoll Aura range.")

end
do
    local page = makeTab("Slam")
    section(page, "Auto Slam")
    toggle(page, "Auto Slam", false, function(v)
        S.autoSlam = v
        if v then
            pcall(function() S.bypassCombatCooldowns(true) end)
            pcall(function() S.resetSlamTimers() end)
        else
            pcall(function() S.resetSlamTimers() end)
            pcall(function() S.bypassCombatCooldowns(true) end)
        end
    end, "Automatically slams nearby downed targets.")
    slider(page, "Auto Slam Range", 0, 7, 6, " studs", function(v) S.slamRange = v end,
        "How far Auto Slam looks for targets.")
    toggle(page, "Slam Visual Range", false, function(v) S.slamVisualRange = v end,
        "Shows a ring for Auto Slam range.")
    slider(page, "Auto Slam Cooldown", 0, 6000, 0, " ms", function(v) S.slamCD = v / 1000 end,
        "Wait between auto slams.")

    section(page, "Slam Hotkey")
    toggle(page, "Slam Hotkey", false, function(v)
        S.slamHotkey = v
        showSlamBtn(v)
        if v then
            pcall(function() S.bypassCombatCooldowns(true) end)
            pcall(function() S.resetSlamTimers() end)
        else
            pcall(function() S.resetSlamTimers() end)
            pcall(function() S.bypassCombatCooldowns(true) end)
        end
    end, "Lets you slam with a key / on-screen button.")
    keybind(page, "Slam Bind",
        function() return S.bindSlamKb end, function(k) S.bindSlamKb = k end,
        function() return S.bindSlamGp end, function(k) S.bindSlamGp = k end,
        "Keyboard / controller key for Slam Hotkey.")
    slider(page, "Slam Hotkey Range", 0, 50, 12, " studs", function(v) S.slamHotkeyRange = v end,
        "How far Slam Hotkey can grab a target.")
    toggle(page, "Slam Hotkey Visual Range", false, function(v) S.slamHotkeyVisualRange = v end,
        "Shows a ring for Slam Hotkey range.")
    slider(page, "Slam Hotkey Cooldown", 0, 3000, 0, " ms", function(v) S.slamHotkeyCD = v / 1000 end,
        "Wait between hotkey slams.")

    section(page, "Grab & Slam (TP to locked target)")
    toggle(page, "Grab & Slam Hotkey", false, function(v) S.grabSlamEnabled = v; showGrabBtn(v) end,
        "Teleports to your locked target and slams.")
    keybind(page, "Grab & Slam Bind",
        function() return S.bindGrabKb end, function(k) S.bindGrabKb = k end,
        function() return S.bindGrabGp end, function(k) S.bindGrabGp = k end,
        "Keyboard / controller key for Grab & Slam.")
    slider(page, "Grab Range", 0, 200, 30, " studs", function(v) S.grabSlamRange = v end,
        "Max distance to grab the locked target.")
    toggle(page, "Grab Visual Range", false, function(v) S.grabSlamVisualRange = v end,
        "Shows a ring for Grab range.")
    toggle(page, "Wind Slam Animation", false, function(v) S.aTrainFX = v end,
        "Plays a wind-style slam visual on Grab & Slam.")
end
do
    local page = makeTab("Bowling Ball")
    section(page, "Bowling Ball")
    toggle(page, "Bowling Ball", false, function(v)
        S.touchFling = v
        if not v and S._stopTouchFling then pcall(S._stopTouchFling) end
    end, "Dive into people and morph into a bowling ball on hit (dive only, no Slam).")
    slider(page, "Touch Range", 2.2, 6, 3.6, " studs", function(v) S.touchFlingRange = v end,
        "How close you must be to bowl someone.")
    slider(page, "Bowl Power", 1, 10, 7, "", function(v) S.touchFlingPower = v end,
        "Dive strength when bowling.")
    toggle(page, "Contact FX (local)", true, function(v) S.touchFlingVfx = v end,
        "Local hit ring effect when you bowl someone.")
    local flingNote = label(page, Theme.SubText)
    flingNote.Text = "Roll into people"
end
----------------------------------------------------------------------
-- Streamer Mode — client-side only. Hides YOUR username everywhere it
-- appears locally (nametag, PlayerGui, PlayerList). Restores only when
-- the toggle is turned off (or suite unload).
-- Lightweight: no full-tree Heartbeat scans (those tanked FPS on mobile).
----------------------------------------------------------------------
;(function()
    local StarterGui = game:GetService("StarterGui")
    local MASK = "******"
    local savedHum = nil
    local savedTexts = {}
    local savedBillboards = {}
    local textWatch = setmetatable({}, { __mode = "k" })
    local savedPlayerList = nil
    local conns = {}
    local safetyConn = nil
    local tokens = { LP.Name }
    local tokensDirty = true

    local function clearConns()
        for i = #conns, 1, -1 do
            pcall(function() conns[i]:Disconnect() end)
            conns[i] = nil
        end
        if safetyConn then
            pcall(function() task.cancel(safetyConn) end)
            safetyConn = nil
        end
        for k in pairs(textWatch) do textWatch[k] = nil end
    end

    local function isOurGui(inst)
        local p = inst
        local hops = 0
        while p and hops < 12 do
            local n = p.Name
            if type(n) == "string" and (string.sub(n, 1, 5) == "CAF2_" or string.sub(n, 1, 7) == "Velorix") then
                return true
            end
            p = p.Parent
            hops = hops + 1
        end
        return false
    end

    local function refreshTokens()
        tokens = { LP.Name }
        local dn = LP.DisplayName
        if type(dn) == "string" and dn ~= "" and dn ~= LP.Name then
            tokens[2] = dn
        end
        tokensDirty = false
    end

    local function getTokens()
        if tokensDirty then refreshTokens() end
        return tokens
    end

    local function containsMyName(str)
        if type(str) ~= "string" or str == "" or str == MASK then return false end
        for _, tok in ipairs(getTokens()) do
            if tok ~= "" and string.find(str, tok, 1, true) then
                return true
            end
        end
        return false
    end

    local function maskText(str)
        local out = str
        for _, tok in ipairs(getTokens()) do
            if tok ~= "" then
                out = string.gsub(out, tok, MASK)
            end
        end
        return out
    end

    local function hideHumanoid(hum)
        if not hum then return end
        if not savedHum or savedHum.hum ~= hum then
            savedHum = {
                hum = hum,
                ddt = hum.DisplayDistanceType,
                nd = hum.NameDisplayDistance,
                hd = hum.HealthDisplayDistance,
            }
        end
        pcall(function()
            if hum.DisplayDistanceType ~= Enum.HumanoidDisplayDistanceType.None then
                hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            end
            if hum.NameDisplayDistance ~= 0 then hum.NameDisplayDistance = 0 end
            if hum.HealthDisplayDistance ~= 0 then hum.HealthDisplayDistance = 0 end
        end)
    end

    local function bindHumanoid(hum)
        if not hum then return end
        hideHumanoid(hum)
        conns[#conns + 1] = hum:GetPropertyChangedSignal("DisplayDistanceType"):Connect(function()
            if S.streamerMode then hideHumanoid(hum) end
        end)
        conns[#conns + 1] = hum:GetPropertyChangedSignal("NameDisplayDistance"):Connect(function()
            if S.streamerMode then hideHumanoid(hum) end
        end)
    end

    local function restoreHumanoid()
        local s = savedHum
        savedHum = nil
        if s and s.hum and s.hum.Parent then
            pcall(function()
                s.hum.DisplayDistanceType = s.ddt
                s.hum.NameDisplayDistance = s.nd
                s.hum.HealthDisplayDistance = s.hd
            end)
        end
    end

    local function watchText(inst)
        if textWatch[inst] then return end
        textWatch[inst] = true
        conns[#conns + 1] = inst:GetPropertyChangedSignal("Text"):Connect(function()
            if not S.streamerMode or not isCurrent() then return end
            local t = inst.Text
            if not containsMyName(t) then return end
            if savedTexts[inst] == nil then
                savedTexts[inst] = t
            elseif t ~= maskText(savedTexts[inst]) and containsMyName(t) then
                -- Game pushed a fresh unmasked string — keep latest original for restore
                savedTexts[inst] = t
            end
            local masked = maskText(savedTexts[inst])
            if inst.Text ~= masked then
                inst.Text = masked
            end
        end)
    end

    local function scrubInstance(inst)
        if not inst or isOurGui(inst) then return end
        if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
            local t = inst.Text
            if containsMyName(t) then
                if savedTexts[inst] == nil or t ~= maskText(savedTexts[inst]) then
                    savedTexts[inst] = t
                end
                local masked = maskText(savedTexts[inst])
                if inst.Text ~= masked then
                    inst.Text = masked
                end
                watchText(inst)
            end
        elseif inst:IsA("BillboardGui") then
            local char = LP.Character
            local adorn = inst.Adornee
            local onMe = char and (
                inst:IsDescendantOf(char)
                or (adorn and adorn:IsDescendantOf(char))
            )
            if not onMe then return end
            local hasName = false
            for _, d in ipairs(inst:GetDescendants()) do
                if (d:IsA("TextLabel") or d:IsA("TextButton")) and containsMyName(d.Text) then
                    hasName = true
                    break
                end
            end
            local n = string.lower(inst.Name)
            if hasName or string.find(n, "name", 1, true) or string.find(n, "tag", 1, true) then
                if savedBillboards[inst] == nil then
                    savedBillboards[inst] = inst.Enabled
                end
                if inst.Enabled then
                    inst.Enabled = false
                end
            end
        end
    end

    local function scrubTree(root)
        if not root then return end
        scrubInstance(root)
        for _, d in ipairs(root:GetDescendants()) do
            scrubInstance(d)
        end
    end

    local function restoreAll()
        clearConns()
        restoreHumanoid()
        for inst, text in pairs(savedTexts) do
            if inst and inst.Parent then
                pcall(function() inst.Text = text end)
            end
            savedTexts[inst] = nil
        end
        for bb, en in pairs(savedBillboards) do
            if bb and bb.Parent then
                pcall(function() bb.Enabled = en end)
            end
            savedBillboards[bb] = nil
        end
        if savedPlayerList ~= nil then
            pcall(function()
                StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, savedPlayerList)
            end)
            savedPlayerList = nil
        end
    end

    local function watchTree(root)
        if not root then return end
        conns[#conns + 1] = root.DescendantAdded:Connect(function(d)
            if S.streamerMode then
                task.defer(scrubInstance, d)
            end
        end)
    end

    local function applyStreamer()
        clearConns()
        tokensDirty = true
        refreshTokens()

        if savedPlayerList == nil then
            local ok, en = pcall(function()
                return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
            end)
            savedPlayerList = (ok and en) and true or false
            pcall(function()
                StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
            end)
        end

        local char = LP.Character
        if char then
            bindHumanoid(char:FindFirstChildOfClass("Humanoid"))
            scrubTree(char)
            watchTree(char)
        end
        local pg = LP:FindFirstChild("PlayerGui")
        if pg then
            scrubTree(pg)
            watchTree(pg)
        end

        -- Rare safety pass only (not every frame / sub-second). Re-hides humanoid
        -- if something fights us; does NOT rescan all of PlayerGui.
        safetyConn = task.spawn(function()
            while S.streamerMode and isCurrent() do
                task.wait(2.5)
                if not S.streamerMode or not isCurrent() then break end
                local c = LP.Character
                if c then
                    hideHumanoid(c:FindFirstChildOfClass("Humanoid"))
                end
            end
            safetyConn = nil
        end)
    end

    function S.setStreamerMode(on)
        on = on and true or false
        if on then
            S.streamerMode = true
            applyStreamer()
        else
            S.streamerMode = false
            restoreAll()
        end
        pcall(publishState)
    end

    Maid:Give(LP:GetPropertyChangedSignal("DisplayName"):Connect(function()
        tokensDirty = true
    end))

    Maid:Give(LP.CharacterAdded:Connect(function(c)
        if not S.streamerMode then return end
        savedHum = nil
        task.defer(function()
            if not S.streamerMode or not isCurrent() then return end
            local hum = c:WaitForChild("Humanoid", 5)
            bindHumanoid(hum)
            scrubTree(c)
            watchTree(c)
        end)
    end))
end)()

do
    local page = makeTab("Protection")
    section(page, "Streamer Mode")
    toggle(page, "Streamer Mode", false, function(v)
        if S.setStreamerMode then
            S.setStreamerMode(v)
        else
            S.streamerMode = v
        end
    end, "Hides your username client-side (nametag, UIs, player list) so you can record. Names come back only when you turn this off.")

    section(page, "Survival")
    toggle(page, "Godmode", false, function(v)
        S.godmode = v
        showPunchBtn(v)
        if v then
            blockSuppressUntil = 0
            pcall(block)
        else
            unblock()
        end
    end, "Holds block / punch helpers so you are harder to hit.")
    slider(page, "Godmode Reach", 0, 100, 15, " studs", function(v) S.godmodeReach = v end,
        "Punch reach while Godmode is on.")
    toggle(page, "Anti Ragdoll", false, function(v) S.antiRagdoll = v end,
        "Stops ragdoll states on you.")
    toggle(page, "Anti Knockdown", false, function(v) S.antiKnockdown = v end,
        "Stops knockdown states on you.")
    toggle(page, "Anti Stun", false, function(v) S.antiStun = v; if v then applyAntiStunHooks() end end,
        "Clears stun so you can keep moving / hitting.")

    section(page, "Block")
    abToggle = toggle(page, "Auto Block (Perfect Block)", false, function(v)
        S.autoBlock = v
        if v then
            blockSuppressUntil = 0
        else
            if not S.godmode then unblock() end
            stopBlockAnim()
        end
    end, "Blocks when someone swings nearby. No block animation by itself — turn on Safe Block with this for the real block anim.")
    toggle(page, "Safe Block (only while Guard)", false, function(v)
        S.safeBlock = v
        if not v then stopBlockAnim() end
    end, "Must be enabled WITH Auto Block. Only auto-blocks while Guard/fists are already equipped (won't force-equip). Plays the real block animation on incoming swings.")
    slider(page, "Block Range", 0, 25, 6, " studs", function(v) S.blockRange = v end,
        "How close an attacking enemy must be.")
    toggle(page, "Block Visual Range", false, function(v) S.blockVisualRange = v end,
        "Shows a ring for Block range.")
    toggle(page, "Infinite Stamina", false, function(v) S.infStamina = v; if v then applyInfStamina() else disableInfStamina() end end,
        "Keeps your stamina full.")
    toggle(page, "Anti Slam", false, function(v) S.antiSlam = v end,
        "Helps stop people from slamming you.")

    section(page, "Movement / Anti Cheats")
    toggle(page, "Noclip", false, function(v) S.noclip = v end,
        "Walk through walls and props.")
    toggle(page, "Anti Launch", false, function(v) S.antiFling = v end,
        "Resists getting flung / launched.")
    toggle(page, "Anti Staff", false, function(v)
        S.antiStaff = v
        if v then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LP then checkStaff(p) end
            end
        end
    end, "Kicks you if staff joins the server.")
    toggle(page, "Anti AFK", false, function(v)
        S.antiAfk = v
        if v then
            task.spawn(function()
                local VU = game:GetService("VirtualUser")
                while S.antiAfk and isCurrent() do
                    pcall(function() VU:CaptureController(); VU:ClickButton2(Vector2.new()) end)
                    task.wait(30)
                end
            end)
        end
    end, "Stops Roblox from idle-kicking you.")

    section(page, "Party / Pacify")
    do
        local f = card(page, 44)
        local btn = new("TextButton", { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 7), BackgroundColor3 = Theme.Accent, AutoButtonColor = true, Font = Enum.Font.GothamBold, Text = "Pacify Nearest (Force Party)", TextColor3 = Theme.Card, TextSize = 13, BorderSizePixel = 0 }, f)
        corner(btn, 8)
        Maid:Give(btn.MouseButton1Click:Connect(function() if S.pacifyNearest then S.pacifyNearest() end end))
        hint(page, "Forces a party with the nearest player.")
    end
    do
        local f = card(page, 44)
        local btn = new("TextButton", { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 7), BackgroundColor3 = Theme.Panel2, AutoButtonColor = true, Font = Enum.Font.GothamBold, Text = "Leave Party", TextColor3 = Theme.Text, TextSize = 13, BorderSizePixel = 0 }, f)
        corner(btn, 8)
        Maid:Give(btn.MouseButton1Click:Connect(function() if S.leaveParty then S.leaveParty() end end))
        hint(page, "Leaves your current party.")
    end
    section(page, "Safe Zone")
    do
        local SafeZone = S.SafeZone
        local f = card(page, 44)
        local btn = new("TextButton", { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 7), BackgroundColor3 = Theme.Accent, AutoButtonColor = true, Font = Enum.Font.GothamBold, Text = "Go to Safe Zone", TextColor3 = Theme.Card, TextSize = 13, BorderSizePixel = 0 }, f); corner(btn, 8)
        local function refreshBtn()
            btn.Text = SafeZone.isActive() and "Return from Safe Zone" or "Go to Safe Zone"
            btn.BackgroundColor3 = SafeZone.isActive() and Color3.fromRGB(206, 74, 74) or Theme.Accent
        end
        Maid:Give(btn.MouseButton1Click:Connect(function()
            SafeZone.toggle()
            refreshBtn()
        end))
        refreshBtn()
        hint(page, "Teleports you to a safe spot (toggle again to return).")
    end
end
do
    local page = makeTab("Flash Step")
    section(page, "Flash Step")
    toggle(page, "Flash Step Hotkey", false, function(v) S.flashStepEnabled = v; showFlashBtn(v) end,
        "Dash forward with a key / button.")
    keybind(page, "Flash Step Bind",
        function() return S.bindFlashKb end, function(k) S.bindFlashKb = k end,
        function() return S.bindFlashGp end, function(k) S.bindFlashGp = k end,
        "Keyboard / controller key for Flash Step.")
    slider(page, "Flash Step Distance", 0, 100, 25, " studs", function(v) S.flashStepDistance = v end,
        "How far each flash dash travels.")
    toggle(page, "Flash Step Visual Range", false, function(v) S.flashStepVisualRange = v end,
        "Shows a ring for flash distance.")
    toggle(page, "Flash Step Animation", true, function(v) S.flashStepAnim = v end,
        "Plays the flash dash animation / ghost trail.")
    toggle(page, "Smooth RGB Flash Step", false, function(v) S.flashRgb = v end,
        "Cycles flash colors through RGB.")
    toggle(page, "Flash Step Sound Effects", true, function(v) S.flashSound = v end,
        "Plays a sound when you flash.")
    colorpicker(page, "Flash Step Color", S.flashStepColor, function(c) S.flashStepColor = c end,
        "Color used for flash visuals.")

    section(page, "Fly")
    toggle(page, "Fly", false, function(v) if S.setFly then S.setFly(v) end; showFlyBtn(v) end,
        "Lets you fly around.")
    keybind(page, "Fly Bind",
        function() return S.bindFlyKb end, function(k) S.bindFlyKb = k end,
        function() return S.bindFlyGp end, function(k) S.bindFlyGp = k end,
        "Keyboard / controller key to toggle fly.")
    slider(page, "Fly Speed", 16, 90, 55, " studs/s", function(v) S.flySpeed = v end,
        "How fast you fly.")
    toggle(page, "Fly Noclip", true, function(v) S.flyNoclip = v end,
        "Noclip while flying so you do not snag on walls.")

    section(page, "Walkspeed")
    toggle(page, "Walkspeed", false, function(v)
        S.walkEnabled = v; S.walkActive = v; showWalkBtn(v)
        applyWalk()
    end, "Overrides your walk speed.")
    keybind(page, "Walkspeed Bind",
        function() return S.bindWalkKb end, function(k) S.bindWalkKb = k end,
        function() return S.bindWalkGp end, function(k) S.bindWalkGp = k end,
        "Keyboard / controller key to toggle walkspeed.")
    slider(page, "Walk Speed", 16, 350, 50, " ws", function(v)
        S.walkspeedValue = v
        applyWalk()
    end, "Walk speed value when Walkspeed is on.")

    section(page, "Jump Power")
    toggle(page, "Jump Power", false, function(v)
        S.jumpEnabled = v
        if not v then
            pcall(function() if S._stopJumpAssist then S._stopJumpAssist() end end)
            pcall(resetJumpHard)
            -- resetJumpHard also clears the toggle — put the intended off-state back
            S.jumpEnabled = false
            local hum = myChar() and myChar():FindFirstChildOfClass("Humanoid")
            if hum then sanitizeJumpSpawn(hum) end
            stripJumpMovers(myChar())
        else
            applyJump()
        end
    end, "Overrides how high you jump. OFF = the game's normal jump.")
    slider(page, "Jump Power Value", 50, 250, 50, " jp", function(v)
        S.jumpPowerValue = v
        if S.jumpEnabled then applyJump() end
    end, "Jump strength when Jump Power is on.")
    section(page, "No Fall Damage")
    toggle(page, "No Fall Damage", false, function(v)
        S.noFallDamage = v
        applyNoFall()
    end, "Stops fall damage from high drops.")
end
do
    local page = makeTab("Visuals")
    section(page, "Camera")
    toggle(page, "First Person", false, function(v)
        if S._setFirstPerson then S._setFirstPerson(v) else S.firstPerson = v end
    end, "Arms only. Equip Guard → FP. Menu stays open on top — close it (RightShift/V) to free-look / punch. Unequip or turn off → third-person.")
    hint(page, "Close Gui To Look Around")
    toggle(page, "FP Lock On", false, function(v)
        S.firstPersonLockOn = v and true or false
    end, "Only while First Person + Guard are active. Locks onto the closest player in range — does nothing with Guard unequipped.")
    slider(page, "FOV", 70, 120, 100, "", function(v)
        S.firstPersonFov = v
    end, "Field of view while first person is active.")
    slider(page, "FP Lock Range", 0, 10, 10, " studs", function(v)
        S.firstPersonLockRange = v
    end, "Only lock the closest player within this distance (0–10).")

    section(page, "ESP")
    toggle(page, "Player ESP (Outline)", false, function(v) S.esp = v end,
        "Outlines other players through walls.")
    slider(page, "ESP Fill", 0, 100, 25, "%", function(v) S.espFill = 1 - v / 100 end,
        "How solid the ESP fill color is.")
    toggle(page, "HP Bar ESP", false, function(v) S.hpEsp = v end,
        "Shows health bars above players.")
    toggle(page, "Smooth RGB ESP", false, function(v) S.espRgb = v end,
        "Cycles ESP colors through RGB.")
    section(page, "Target")
    toggle(page, "Show Locked Target (Purple)", false, function(v) S.showLocked = v end,
        "Highlights your currently locked target.")
    toggle(page, "Smooth RGB Lock Highlight", false, function(v) S.lockRgb = v end,
        "Cycles the lock highlight through RGB.")
end
do
    local page = makeTab("Whitelist")
    section(page, "Filters")
    toggle(page, "Whitelist My Party", true, function(v) S.whitelistParty = v end,
        "Never targets players in your party.")
    section(page, "Players")
    local note = label(page, Theme.SubText); note.Text = "Tap a player to whitelist (never targeted)."
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, page)
    new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.Name }, holder)
    local rows = {}
    local function refresh()
        for _, r in pairs(rows) do r:Destroy() end
        rows = {}
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl ~= LP then
                local row = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.3, BorderSizePixel = 0 }, holder); corner(row, 8)
                local on = whitelist[pl.UserId] == true
                local nameLbl = new("TextLabel", { Size = UDim2.new(1, -70, 1, 0), Position = UDim2.fromOffset(10, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = pl.Name, TextColor3 = on and Theme.Good or Theme.Text, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, row)
                local b = new("TextButton", { Size = UDim2.fromOffset(54, 22), Position = UDim2.new(1, -62, 0.5, -11), BackgroundColor3 = on and Theme.Good or Theme.Panel2, Font = Enum.Font.GothamBold, Text = on and "WL" or "OFF", TextColor3 = Color3.new(1, 1, 1), TextSize = 12 }, row); corner(b, 6)
                Maid:Give(b.MouseButton1Click:Connect(function()
                    if whitelist[pl.UserId] then whitelist[pl.UserId] = nil else whitelist[pl.UserId] = true end
                    local nowOn = whitelist[pl.UserId] == true
                    b.Text = nowOn and "WL" or "OFF"; b.BackgroundColor3 = nowOn and Theme.Good or Theme.Panel2; nameLbl.TextColor3 = nowOn and Theme.Good or Theme.Text
                end))
                rows[pl] = row
            end
        end
    end
    refresh()
    Maid:Give(Players.PlayerAdded:Connect(function() task.wait(0.4); refresh() end))
    Maid:Give(Players.PlayerRemoving:Connect(function() task.wait(0.4); refresh() end))
end

-- Morphs — loaded as a separate chunk so it does not hit the main script's 200-local limit.
----------------------------------------------------------------------
do
    local ctx = {
        S = S, LP = LP, Players = Players, Maid = Maid, Theme = Theme,
        UIControls = UIControls, RunService = RunService, notify = notify,
        makeTab = makeTab, section = section, label = label, toggle = toggle,
        card = card, new = new, corner = corner, hint = hint, isCurrent = isCurrent,
    }
    local src = [=[
local S, LP, Players, Maid, Theme, UIControls, RunService, notify =
    ctx.S, ctx.LP, ctx.Players, ctx.Maid, ctx.Theme, ctx.UIControls, ctx.RunService, ctx.notify
local makeTab, section, label, toggle, card, new, corner, hint, isCurrent =
    ctx.makeTab, ctx.section, ctx.label, ctx.toggle, ctx.card, ctx.new, ctx.corner, ctx.hint, ctx.isCurrent
local AS = game:GetService("AssetService")
local MPS = game:GetService("MarketplaceService")
local page = makeTab("Morphs")
local M = {
    busy = false, activeName = nil, activeEntry = nil, originalDesc = nil,
    morphNames = {}, overlay = nil,
}

section(page, "Character")
do
    local f = card(page, 44)
    local btn = new("TextButton", {
        Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 7),
        BackgroundColor3 = Theme.Accent, AutoButtonColor = true, Font = Enum.Font.GothamBold,
        Text = "Force Respawn", TextColor3 = Theme.Card, TextSize = 13, BorderSizePixel = 0,
    }, f)
    corner(btn, 8)
    Maid:Give(btn.MouseButton1Click:Connect(function() S._forceRespawn() end))
    hint(page, "Kills your character so the game respawns you. Clears any active morph.")
end
section(page, "Packages")
label(page, Theme.SubText).Text = "Classic Roblox packages (overlay morph — works on all machines)."

function S._forceRespawn()
    M.busy = true
    M.activeName, M.activeEntry, M.originalDesc, M.overlay = nil, nil, nil, nil
    for _, n in ipairs(M.morphNames) do
        local c = UIControls[n]
        if c and c.get() then c.set(false, false) end
    end
    M.busy = false
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function() hum.Health = 0 end)
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Dead) end)
    elseif char then
        pcall(function() char:BreakJoints() end)
    end
    notify("Morph", "Forcing respawn…")
end

local function stripMorphJunk(char)
    if not char then return end
    for _, x in ipairs(char:GetChildren()) do
        if typeof(x.Name) == "string" and x.Name:match("^CAF2_Morph") then
            pcall(function() x:Destroy() end)
        elseif x:IsA("Highlight") or x:IsA("ForceField") or x:IsA("SelectionBox") then
            -- these wash the whole body cyan and hide package textures
            pcall(function() x:Destroy() end)
        end
    end
end

local function setRealBodyVisible(char, visible)
    if not char then return end
    local t = visible and 0 or 1
    for _, p in ipairs(char:GetChildren()) do
        if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
            p.Transparency = t
            pcall(function() p.LocalTransparencyModifier = visible and 0 or 1 end)
        end
    end
    local head = char:FindFirstChild("Head")
    if head then
        for _, d in ipairs(head:GetChildren()) do
            if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = t end
        end
    end
end

local function clearClothes(char)
    if not char then return end
    for _, x in ipairs(char:GetChildren()) do
        if x:IsA("Accessory") or x:IsA("Hat") or x:IsA("Shirt") or x:IsA("Pants")
            or x:IsA("ShirtGraphic") or x:IsA("BodyColors") or x:IsA("CharacterMesh") then
            pcall(function() x:Destroy() end)
        end
    end
end

local function buildDesc(bundleId)
    local info = AS:GetBundleDetailsAsync(bundleId)
    local d = Instance.new("HumanoidDescription")
    local hats = {}
    for _, it in ipairs(info.Items or {}) do
        if it.Type == "Asset" then
            local at = 0
            pcall(function()
                local pi = MPS:GetProductInfo(it.Id)
                at = pi and pi.AssetTypeId or 0
            end)
            local n = tostring(it.Name or ""):lower()
            local weapon = n:find("sword") or n:find("axe") or n:find("bow") or n:find("gun")
                or n:find("staff") or n:find("club") or n:find("blade") or n:find("firecracker")
            if at == 27 or n:find("torso") then d.Torso = it.Id
            elseif at == 29 or n:find("left arm") then d.LeftArm = it.Id
            elseif at == 28 or n:find("right arm") then d.RightArm = it.Id
            elseif at == 30 or n:find("left leg") then d.LeftLeg = it.Id
            elseif at == 31 or n:find("right leg") then d.RightLeg = it.Id
            elseif at == 17 or at == 79 or n:find("dynamic head") or (n:find("head") and not n:find("helmet") and not n:find("helm") and not n:find("hat")) then
                d.Head = it.Id
            elseif at == 18 then d.Face = it.Id
            elseif (at == 8 or at == 41 or at == 42 or at == 43 or at == 44 or at == 45 or at == 46 or at == 47) and not weapon then
                table.insert(hats, tostring(it.Id))
            end
        end
    end
    d.HatAccessory = table.concat(hats, ",")
    local gy = Color3.fromRGB(163, 162, 165)
    d.HeadColor, d.TorsoColor, d.LeftArmColor, d.RightArmColor, d.LeftLegColor, d.RightLegColor = gy, gy, gy, gy, gy, gy
    return d
end

local function assetKey(id)
    local s = tostring(id or ""):gsub("%s+", "")
    -- Prefer explicit id= / rbxassetid=; never match the "v1" in assetdelivery URLs
    return s:match("[?&]id=(%d+)") or s:match("rbxassetid://(%d+)") or s:match("asset/?id=(%d+)") or s:match("(%d%d%d%d+)") or ""
end

local function normalizeAsset(url)
    local id = assetKey(url)
    if id ~= "" then return "rbxassetid://" .. id end
    return tostring(url or ""):gsub("%s+", "")
end

-- Overlay morph: hide real body, weld a full package model on top.
-- MeshId writes on live body parts do NOT update rendering on CAF — overlay does.
local function applyBundle(hum, bundleId)
    local char = hum and hum.Parent
    if not char then return false, "No character" end
    local desc
    local okB, errB = pcall(function() desc = buildDesc(bundleId) end)
    if not okB or not desc then return false, tostring(errB or "Bundle failed") end
    local okM, model = pcall(function()
        return Players:CreateHumanoidModelFromDescription(desc, hum.RigType)
    end)
    if not okM or not model then
        pcall(function() desc:Destroy() end)
        return false, "Failed to build package"
    end
    local ut = model:FindFirstChild("UpperTorso")
    if not (ut and ut:IsA("MeshPart") and assetKey(ut.MeshId) ~= "" and assetKey(ut.MeshId) ~= "1") then
        -- allow texture-only classics (MeshId 1) if TextureID is real
        if not (ut and ut:IsA("MeshPart") and assetKey(ut.TextureID) ~= "" and assetKey(ut.TextureID) ~= "1") then
            pcall(function() model:Destroy() end)
            pcall(function() desc:Destroy() end)
            return false, "Package has no usable body mesh"
        end
    end
    for _, s in ipairs(model:GetDescendants()) do
        if s:IsA("BaseScript") or s:IsA("Humanoid") or s:IsA("Animator") then
            pcall(function() s:Destroy() end)
        end
    end
    stripMorphJunk(char)
    clearClothes(char)
    setRealBodyVisible(char, false)
    model.Name = "CAF2_MorphOverlay"
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CanCollide = false
            p.CanQuery = false
            p.CanTouch = false
            p.Massless = true
            p.Anchored = false
            if p:IsA("MeshPart") then
                p.MeshId = normalizeAsset(p.MeshId)
                p.TextureID = normalizeAsset(p.TextureID)
            end
            if p.Name == "HumanoidRootPart" then
                p.Transparency = 1
            elseif p.Name == "Head" then
                -- Overlay heads almost always render as a blank orb on CAF; hide them.
                -- Hoods/helms from the package still weld to the (hidden) real Head.
                p.Transparency = 1
                pcall(function() p.LocalTransparencyModifier = 1 end)
            else
                p.Transparency = 0
                pcall(function() p.LocalTransparencyModifier = 0 end)
            end
        end
    end
    model.Parent = char
    local welds = 0
    for _, fp in ipairs(model:GetChildren()) do
        if fp:IsA("BasePart") then
            local rp = char:FindFirstChild(fp.Name)
            if rp and rp:IsA("BasePart") then
                local w = Instance.new("Weld")
                w.Name = "CAF2_MorphWeld"
                w.Part0 = rp
                w.Part1 = fp
                w.C0 = CFrame.new()
                w.C1 = CFrame.new()
                w.Parent = fp
                welds = welds + 1
            end
        end
    end
    -- Re-anchor package hats to the real Head (Accessory welds die with fake Humanoid)
    local realHead = char:FindFirstChild("Head")
    for _, acc in ipairs(model:GetChildren()) do
        if (acc:IsA("Accessory") or acc:IsA("Hat")) and realHead then
            local handle = acc:FindFirstChild("Handle")
            if handle and handle:IsA("BasePart") then
                handle.CanCollide = false
                handle.Massless = true
                handle.Transparency = 0
                pcall(function() handle.LocalTransparencyModifier = 0 end)
                for _, s in ipairs(handle:GetChildren()) do
                    if s:IsA("Weld") or s:IsA("WeldConstraint") or s:IsA("Motor6D") then
                        pcall(function() s:Destroy() end)
                    end
                end
                local att = handle:FindFirstChildOfClass("Attachment")
                local c0, part0 = CFrame.new(), realHead
                if att then
                    local match = realHead:FindFirstChild(att.Name)
                    if match and match:IsA("Attachment") then
                        c0 = match.CFrame
                    else
                        for _, bp in ipairs(char:GetChildren()) do
                            if bp:IsA("BasePart") then
                                local a2 = bp:FindFirstChild(att.Name)
                                if a2 and a2:IsA("Attachment") then
                                    part0, c0 = bp, a2.CFrame
                                    break
                                end
                            end
                        end
                    end
                end
                local w = Instance.new("Weld")
                w.Name = "CAF2_MorphHat"
                w.Part0 = part0
                w.Part1 = handle
                w.C0 = c0
                w.C1 = att and att.CFrame or CFrame.new()
                w.Parent = handle
            end
        end
    end
    if char == LP.Character then
        M.overlay = model
    end
    pcall(function() desc:Destroy() end)
    if welds < 8 then
        return false, "Overlay weld failed"
    end
    return true
end

local function restore()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hadMorph = M.activeName ~= nil or M.overlay ~= nil
    M.activeName, M.activeEntry, M.overlay = nil, nil, nil
    pcall(function()
        LP:SetAttribute("VLXMorphBundle", nil)
        LP:SetAttribute("VLXMorphName", nil)
    end)
    if char then stripMorphJunk(char) end
    pcall(function()
        local cam = workspace.CurrentCamera
        LP.CameraMode = Enum.CameraMode.Classic
        LP.CameraMinZoomDistance = 0.5
        LP.CameraMaxZoomDistance = 128
        game:GetService("UserInputService").MouseBehavior = Enum.MouseBehavior.Default
        if cam then
            cam.CameraType = Enum.CameraType.Custom
            if hum then cam.CameraSubject = hum end
        end
    end)
    if not hadMorph or not char then return end
    setRealBodyVisible(char, true)
    if hum and M.originalDesc then
        local ok, model = pcall(function()
            return Players:CreateHumanoidModelFromDescription(M.originalDesc, hum.RigType)
        end)
        if ok and model then
            clearClothes(char)
            for _, src in ipairs(model:GetChildren()) do
                if src:IsA("Shirt") or src:IsA("Pants") or src:IsA("ShirtGraphic") or src:IsA("BodyColors") then
                    src:Clone().Parent = char
                elseif src:IsA("Accessory") or src:IsA("Hat") then
                    local cl = src:Clone()
                    pcall(function() hum:AddAccessory(cl) end)
                    if cl.Parent ~= char then cl.Parent = char end
                end
            end
            local head = char:FindFirstChild("Head")
            if head then
                head.Transparency = 0
                pcall(function() head.LocalTransparencyModifier = 0 end)
                for _, d in ipairs(head:GetChildren()) do
                    if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 0 end
                end
            end
            pcall(function() model:Destroy() end)
        end
    end
end

local function capture()
    if M.originalDesc then return true end
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local ok, desc = pcall(function() return hum:GetAppliedDescription() end)
    if ok and desc then
        M.originalDesc = desc:Clone()
        return true
    end
    return false
end

-- Classic Roblox catalog only (stable CDN on every machine).
-- Overlay morph + hooded/helmed packages (blank overlay heads are hidden).
-- Live-screenshot verified: Korblox Hunter, Red Dread Knight look correct.
local LIST = {
    { name = "Red Dread Knight", bundleId = 13 },
    { name = "Korblox Hunter", bundleId = 159 },
    { name = "Korblox Deathspeaker", bundleId = 192 },
    { name = "Korblox Lord of Death", bundleId = 154 },
    { name = "Captain Skeledeath", bundleId = 165 },
    { name = "Captain Bonegrim", bundleId = 6 },
    { name = "Sun Slayer", bundleId = 10 },
    { name = "Cy the Cyborg", bundleId = 1 },
    { name = "SinisterBot 5001", bundleId = 14 },
    { name = "The Abomination", bundleId = 29 },
    { name = "Ancient Dragon", bundleId = 50 },
    { name = "Tiger Warrior", bundleId = 40 },
}

local function shareMorphAttrs(entry)
    pcall(function()
        if entry then
            LP:SetAttribute("VLXMorphBundle", entry.bundleId)
            LP:SetAttribute("VLXMorphName", entry.name)
        else
            LP:SetAttribute("VLXMorphBundle", nil)
            LP:SetAttribute("VLXMorphName", nil)
        end
    end)
end

local function apply(entry)
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return false, "No character" end
    if not capture() then return false, "Could not save avatar" end
    local ok2, err = applyBundle(hum, entry.bundleId)
    if not ok2 then return false, tostring(err or "Failed") end
    M.activeName = entry.name
    M.activeEntry = entry
    shareMorphAttrs(entry)
    return true
end

-- Apply overlay morph onto another Velorix peer (local visual only; FE-safe).
local function applyPeerMorph(plr, bundleId)
    if not plr or plr == LP then return false end
    local char = plr.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local bid = tonumber(bundleId)
    if not bid then return false end
    local existing = char:FindFirstChild("CAF2_MorphOverlay")
    if existing and existing:GetAttribute("VLXBundle") == bid then
        return true
    end
    local ok2, err = applyBundle(hum, bid)
    if ok2 then
        local overlay = char:FindFirstChild("CAF2_MorphOverlay")
        if overlay then overlay:SetAttribute("VLXBundle", bid) end
    end
    return ok2, err
end

local function clearPeerMorph(plr)
    if not plr or plr == LP then return end
    local char = plr.Character
    if not char then return end
    stripMorphJunk(char)
    setRealBodyVisible(char, true)
end

S._morphRestore = restore
S._morphActive = function() return M.activeName end
S._morphSet = function(name, on)
    local c = UIControls[name]
    if not c then return false, "unknown morph" end
    c.set(on and true or false, true)
    return true, M.activeName
end
S._morphList = function()
    local out = {}
    for _, n in ipairs(M.morphNames) do table.insert(out, n) end
    return out
end
S._applyPeerMorph = applyPeerMorph

Maid:Give(RunService.Heartbeat:Connect(function()
    if not M.activeEntry or not isCurrent() then return end
    local now = os.clock()
    if M._nextCheck and now < M._nextCheck then return end
    M._nextCheck = now + 2.5
    local char = LP.Character
    if not char then return end
    local overlay = char:FindFirstChild("CAF2_MorphOverlay")
    if not overlay then
        -- game stripped overlay — rebuild
        pcall(function() applyBundle(char:FindFirstChildOfClass("Humanoid"), M.activeEntry.bundleId) end)
        return
    end
    M.overlay = overlay
    -- keep real body hidden + overlay visible; strip cyan wash
    setRealBodyVisible(char, false)
    for _, x in ipairs(char:GetChildren()) do
        if x:IsA("Highlight") or x:IsA("ForceField") or x:IsA("SelectionBox") then
            pcall(function() x:Destroy() end)
        end
    end
    for _, p in ipairs(overlay:GetDescendants()) do
        if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
            if p.Name == "Head" and p:IsA("MeshPart") and (assetKey(p.MeshId) == "" or assetKey(p.MeshId) == "1") then
                p.Transparency = 1
            elseif p.Transparency > 0.05 and not (p.Name == "Head" and p.Transparency >= 1) then
                p.Transparency = 0
            end
            pcall(function()
                if p.Transparency < 1 then p.LocalTransparencyModifier = 0 end
            end)
        end
    end
end))

Maid:Give(LP.CharacterAdded:Connect(function()
    M.originalDesc, M.activeName, M.activeEntry, M.overlay = nil, nil, nil, nil
    pcall(function()
        LP:SetAttribute("VLXMorphBundle", nil)
        LP:SetAttribute("VLXMorphName", nil)
    end)
    M.busy = true
    for _, n in ipairs(M.morphNames) do
        local c = UIControls[n]
        if c and c.get() then c.set(false, false) end
    end
    M.busy = false
end))

-- Peer morph sync: other Velorix users see each other's package overlays.
local peerMorphSeen = {}
local function syncPeerMorph(plr)
    if not plr or plr == LP then return end
    local isPeer = false
    pcall(function()
        if getgenv and type(getgenv().IsVelorixPeer) == "function" then
            isPeer = getgenv().IsVelorixPeer(plr) == true
        end
    end)
    if not isPeer then
        local okA, marked = pcall(function() return plr:GetAttribute("VLX") end)
        local okB, bundle = pcall(function() return plr:GetAttribute("VLXMorphBundle") end)
        isPeer = (okA and marked) or (okB and bundle ~= nil)
    end
    if not isPeer then return end
    local bundle = plr:GetAttribute("VLXMorphBundle")
    local key = plr.Name
    if bundle == nil then
        if peerMorphSeen[key] then
            peerMorphSeen[key] = nil
            clearPeerMorph(plr)
        end
        return
    end
    local bid = tonumber(bundle)
    if not bid then return end
    if peerMorphSeen[key] == bid then
        local char = plr.Character
        local overlay = char and char:FindFirstChild("CAF2_MorphOverlay")
        if overlay and overlay:GetAttribute("VLXBundle") == bid then return end
    end
    peerMorphSeen[key] = bid
    pcall(applyPeerMorph, plr, bid)
end
local function hookPeerMorphPlayer(plr)
    if not plr or plr == LP then return end
    pcall(function()
        plr:GetAttributeChangedSignal("VLXMorphBundle"):Connect(function()
            task.defer(function() syncPeerMorph(plr) end)
        end)
        plr.CharacterAdded:Connect(function()
            task.wait(0.6)
            syncPeerMorph(plr)
        end)
    end)
    task.defer(function() syncPeerMorph(plr) end)
end
for _, plr in ipairs(Players:GetPlayers()) do hookPeerMorphPlayer(plr) end
Maid:Give(Players.PlayerAdded:Connect(hookPeerMorphPlayer))
Maid:Give(Players.PlayerRemoving:Connect(function(plr)
    if plr then peerMorphSeen[plr.Name] = nil end
end))
task.spawn(function()
    while true do
        task.wait(1.25)
        for _, plr in ipairs(Players:GetPlayers()) do
            pcall(syncPeerMorph, plr)
        end
    end
end)

for i = 1, #LIST do
    table.insert(M.morphNames, LIST[i].name)
    toggle(page, LIST[i].name, false, function(v)
        local entry = LIST[i]
        local name = entry.name
        if M.busy then return end
        M.busy = true
        if v then
            for _, other in ipairs(M.morphNames) do
                if other ~= name then
                    local c = UIControls[other]
                    if c and c.get() then c.set(false, false) end
                end
            end
            local ok, err = apply(entry)
            if not ok then
                local self = UIControls[name]
                if self then self.set(false, false) end
                notify("Morph", tostring(err or "Failed"))
            else
                notify("Morph", name)
            end
        else
            if M.activeName == name then restore() end
        end
        M.busy = false
    end)
end
]=]
    -- inject ctx into the chunk environment
    local fn, err = loadstring("local ctx = ...\n" .. src)
    if not fn then
        warn("[VELORIX] morph compile failed: ", err)
    else
        local ok, runErr = pcall(fn, ctx)
        if not ok then warn("[VELORIX] morph init failed: ", runErr) end
    end
end

-- Config + Settings (IIFE = fresh 200-register frame; main chunk was full).
----------------------------------------------------------------------
;(function()
local HttpService = game:GetService("HttpService")
-- Configs save under the shared "workspace/velorix" folder so they're easy to find and hand to
-- other people (drop a saved .json into their workspace/velorix and it shows up in the list).
local CONFIG_DIR = "workspace/velorix"
local AUTOLOAD_FILE = CONFIG_DIR .. "/_autoload.txt"
local hasFS = typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(listfiles) == "function"

local function ensureDir()
    if typeof(isfolder) == "function" and typeof(makefolder) == "function" then
        -- make the parent first: some executors won't create a nested folder in one call
        if not isfolder("workspace") then pcall(makefolder, "workspace") end
        if not isfolder(CONFIG_DIR) then pcall(makefolder, CONFIG_DIR) end
    end
end
local function configPath(name) return CONFIG_DIR .. "/" .. name .. ".json" end
local function sanitize(name) return (tostring(name or ""):gsub("[^%w%-_ ]", ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function listConfigs()
    local out = {}
    if not hasFS then return out end
    ensureDir()
    local ok, files = pcall(listfiles, CONFIG_DIR)
    if ok and files then
        for _, p in ipairs(files) do
            local name = tostring(p):match("([^/\\]+)%.json$")
            if name and name ~= "_autoload" then table.insert(out, name) end
        end
    end
    table.sort(out)
    return out
end

local function buildConfigData()
    local controls = {}
    for lbl, c in pairs(UIControls) do
        local ok, v = pcall(c.get)
        if ok then controls[lbl] = v end
    end
    local function kn(k) return (k and k ~= Enum.KeyCode.Unknown) and k.Name or "Unknown" end
    return {
        controls = controls,
        binds = {
            slamKb = kn(S.bindSlamKb), slamGp = kn(S.bindSlamGp),
            grabKb = kn(S.bindGrabKb), grabGp = kn(S.bindGrabGp),
            flashKb = kn(S.bindFlashKb), flashGp = kn(S.bindFlashGp),
            walkKb = kn(S.bindWalkKb), walkGp = kn(S.bindWalkGp),
            flyKb = kn(S.bindFlyKb), flyGp = kn(S.bindFlyGp),
        },
    }
end

local function applyConfigData(data)
    if type(data) ~= "table" then return end
    if type(data.binds) == "table" then
        local b = data.binds
        local function kc(n) local ok, v = pcall(function() return Enum.KeyCode[n] end); return ok and v or nil end
        S.bindSlamKb  = kc(b.slamKb)  or S.bindSlamKb;  S.bindSlamGp  = kc(b.slamGp)  or S.bindSlamGp
        S.bindGrabKb  = kc(b.grabKb)  or S.bindGrabKb;  S.bindGrabGp  = kc(b.grabGp)  or S.bindGrabGp
        S.bindFlashKb = kc(b.flashKb) or S.bindFlashKb; S.bindFlashGp = kc(b.flashGp) or S.bindFlashGp
        S.bindWalkKb  = kc(b.walkKb)  or S.bindWalkKb;  S.bindWalkGp  = kc(b.walkGp)  or S.bindWalkGp
        S.bindFlyKb   = kc(b.flyKb)   or S.bindFlyKb;   S.bindFlyGp   = kc(b.flyGp)   or S.bindFlyGp
        for _, fn in ipairs(keybindRefreshers) do pcall(fn) end
    end
    if type(data.controls) == "table" then
        for lbl, v in pairs(data.controls) do
            local c = UIControls[lbl]
            if c then pcall(c.set, v) end
        end
    end
end

local function saveConfig(name)
    name = sanitize(name)
    if not hasFS or name == "" then return false end
    ensureDir()
    local ok, json = pcall(function() return HttpService:JSONEncode(buildConfigData()) end)
    if not ok then return false end
    return (pcall(writefile, configPath(name), json)), name
end
local function loadConfig(name)
    name = sanitize(name)
    if not hasFS or name == "" then return false end
    local ok, content = pcall(readfile, configPath(name))
    if not ok or not content then return false end
    local dok, data = pcall(function() return HttpService:JSONDecode(content) end)
    if not dok then return false end
    applyConfigData(data)
    return true
end
local function deleteConfig(name)
    name = sanitize(name)
    if not hasFS or name == "" then return end
    if typeof(delfile) == "function" then pcall(delfile, configPath(name)) end
end
local function setAutoload(name)
    if not hasFS then return end
    ensureDir()
    name = sanitize(name)
    if name ~= "" then pcall(writefile, AUTOLOAD_FILE, name)
    elseif typeof(delfile) == "function" then pcall(delfile, AUTOLOAD_FILE) end
end
local function getAutoload()
    if not hasFS then return nil end
    local ok, content = pcall(readfile, AUTOLOAD_FILE)
    if ok and content and content ~= "" then return sanitize(content) end
    return nil
end

-- Settings tab (same frame as config helpers)
    local page = makeTab("Settings")
    section(page, "Session")
    local st = label(page, Theme.Good); st.Text = "Premium:  ACTIVATED"
    local f = card(page, 34); f.BackgroundColor3 = Theme.Panel
    local b = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "Unload Suite", TextColor3 = Theme.Text, TextSize = 13 }, f)
    Maid:Give(b.MouseButton1Click:Connect(function() if genv.__CAF2_SUITE then genv.__CAF2_SUITE.Unload() end end))
    hint(page, "Fully unloads Velorix / CAF2 and removes the UI.")

    section(page, "Performance")
    do
        local f2 = card(page, 44)
        local btn = new("TextButton", { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 7), BackgroundColor3 = Theme.Accent, AutoButtonColor = true, Font = Enum.Font.GothamBold, Text = "Optimize Game (FPS)", TextColor3 = Theme.Card, TextSize = 13, BorderSizePixel = 0 }, f2)
        corner(btn, 8)
        Maid:Give(btn.MouseButton1Click:Connect(function()
            if S.optimizeFPS then S.optimizeFPS() end
        end))
        hint(page, "Cuts FX / shadows / grass / bushes for better FPS. Walls & players stay.")
    end

    section(page, "Config")
    if not hasFS then
        local warn = label(page, Theme.Warn); warn.Text = "This executor has no file API — configs can't be saved."; warn.TextWrapped = true
    else
        local status = label(page, Theme.SubText); status.Text = "Name a config, Save it, then Load or set Auto-Load."
        local function setStatus(t, c) status.Text = t; status.TextColor3 = c or Theme.SubText end

        local nameCard = card(page, 38)
        local nameBox = new("TextBox", { Size = UDim2.new(1, -20, 1, -10), Position = UDim2.fromOffset(10, 5), BackgroundColor3 = Theme.Panel2, Text = "", PlaceholderText = "Config name…", PlaceholderColor3 = Theme.Muted, Font = Enum.Font.GothamMedium, TextColor3 = Theme.Text, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, BorderSizePixel = 0 }, nameCard)
        corner(nameBox, 6); new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, nameBox)

        local selected = nil
        local ddCard = card(page, 36)
        local ddBtn = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = "▼   Saved configs", TextColor3 = Theme.Text, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left }, ddCard)
        new("UIPadding", { PaddingLeft = UDim.new(0, 12) }, ddBtn)
        local listHolder = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Visible = false }, page)
        new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, listHolder)

        local function refreshList()
            for _, c in ipairs(listHolder:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
            local configs = listConfigs()
            local al = getAutoload()
            if #configs == 0 then
                new("TextLabel", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = "  (no saved configs yet)", TextColor3 = Theme.Muted, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left }, listHolder)
            end
            for _, name in ipairs(configs) do
                local isAuto = (al == name)
                local row = new("TextButton", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = selected == name and Theme.CardActive or Theme.Panel, AutoButtonColor = true, Font = Enum.Font.GothamMedium, Text = "  " .. name .. (isAuto and "   auto" or ""), TextColor3 = isAuto and Theme.Warn or Theme.Text, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, BorderSizePixel = 0 }, listHolder)
                corner(row, 6)
                Maid:Give(row.MouseButton1Click:Connect(function()
                    selected = name; nameBox.Text = name; ddBtn.Text = "▼   " .. name
                    listHolder.Visible = false; refreshList()
                end))
            end
        end
        Maid:Give(ddBtn.MouseButton1Click:Connect(function()
            listHolder.Visible = not listHolder.Visible
            if listHolder.Visible then refreshList() end
        end))

        local function currentName()
            local n = sanitize(nameBox.Text)
            if n == "" then n = selected or "" end
            return n
        end

        local row1 = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1 }, page)
        local function rowBtn(parent, text, scaleX, offX, color)
            local btn = new("TextButton", { Size = UDim2.new(scaleX, offX, 1, 0), BackgroundColor3 = color, AutoButtonColor = true, Font = Enum.Font.GothamBold, Text = text, TextColor3 = Theme.Text, TextSize = 13, BorderSizePixel = 0 }, parent)
            corner(btn, 7); return btn
        end
        local saveB = rowBtn(row1, "Save", 0.33, -4, Theme.Accent2); saveB.Position = UDim2.new(0, 0, 0, 0)
        local loadB = rowBtn(row1, "Load", 0.33, -4, Theme.Panel2); loadB.Position = UDim2.new(0.335, 2, 0, 0)
        local delB  = rowBtn(row1, "Delete", 0.33, -2, Color3.fromRGB(60, 24, 28)); delB.Position = UDim2.new(0.67, 4, 0, 0)

        local row2 = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1 }, page)
        local autoB  = rowBtn(row2, "Set Auto-Load", 0.66, -4, Theme.Panel2); autoB.Position = UDim2.new(0, 0, 0, 0)
        local clearB = rowBtn(row2, "Clear Auto", 0.34, 0, Color3.fromRGB(60, 24, 28)); clearB.Position = UDim2.new(0.66, 4, 0, 0)

        Maid:Give(saveB.MouseButton1Click:Connect(function()
            local n = currentName()
            if n == "" then setStatus("Enter a config name first.", Theme.Warn); return end
            local ok = saveConfig(n)
            if ok then selected = n; ddBtn.Text = "▼   " .. n; setStatus("Saved config '" .. n .. "'.", Theme.Good); refreshList()
            else setStatus("Save failed.", Theme.Warn) end
        end))
        Maid:Give(loadB.MouseButton1Click:Connect(function()
            local n = currentName()
            if n == "" then setStatus("Pick a config to load.", Theme.Warn); return end
            if loadConfig(n) then setStatus("Loaded config '" .. n .. "'.", Theme.Good)
            else setStatus("Load failed (missing config?).", Theme.Warn) end
        end))
        Maid:Give(delB.MouseButton1Click:Connect(function()
            local n = currentName()
            if n == "" then setStatus("Pick a config to delete.", Theme.Warn); return end
            deleteConfig(n)
            if getAutoload() == n then setAutoload("") end
            if selected == n then selected = nil; nameBox.Text = ""; ddBtn.Text = "▼   Saved configs" end
            setStatus("Deleted config '" .. n .. "'.", Theme.SubText); refreshList()
        end))
        Maid:Give(autoB.MouseButton1Click:Connect(function()
            local n = currentName()
            if n == "" then setStatus("Save a config first, then set it as auto-load.", Theme.Warn); return end
            if not table.find(listConfigs(), n) then saveConfig(n) end
            setAutoload(n); setStatus("'" .. n .. "' saved as favorite — load it manually (autoload is off).", Theme.Good); refreshList()
        end))
        Maid:Give(clearB.MouseButton1Click:Connect(function()
            setAutoload(""); setStatus("Auto-load cleared.", Theme.SubText); refreshList()
        end))
    end

    label(page, Theme.SubText).Text = "Place v" .. tostring(game.PlaceVersion)
end)()

----------------------------------------------------------------------
-- Dragging (top bar & sidebar) — own register frame
----------------------------------------------------------------------
;(function()
    local dragging, dragStart, startPos
    local function startDrag(i)
        if (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) and UserInputService:GetFocusedTextBox() == nil then
            dragging = true; dragStart = i.Position; startPos = mainFrame.Position
        end
    end
    Maid:Give(TopBar.InputBegan:Connect(startDrag))
    -- sidebar drag fights tab swipe + content scroll on mobile
    Maid:Give(Sidebar.InputBegan:Connect(function(i)
        if Layout.mobile then return end
        startDrag(i)
    end))
    Maid:Give(UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    Maid:Give(UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))
end)()

----------------------------------------------------------------------
-- Visibility (RightShift / Insert) + hotkeys — own register frame
----------------------------------------------------------------------
;(function()
-- True when an input's KeyCode matches a feature's keyboard OR gamepad bind.
-- Keyboard binds fire even if gameProcessed (CAF marks some keys gp=true).
-- TextBox focus is filtered in the InputBegan handler.
local function isGamepad(ut)
    return ut == Enum.UserInputType.Gamepad1 or ut == Enum.UserInputType.Gamepad2
        or ut == Enum.UserInputType.Gamepad3 or ut == Enum.UserInputType.Gamepad4
        or ut == Enum.UserInputType.Gamepad5 or ut == Enum.UserInputType.Gamepad6
        or ut == Enum.UserInputType.Gamepad7 or ut == Enum.UserInputType.Gamepad8
end
local function matchBind(i, gp, kbKey, gpKey)
    -- Ignore TextBox focus at call sites. Allow binds even when gameProcessed
    -- (CAF swallows some keys as gp=true which previously killed Slam Hotkey).
    if kbKey and kbKey ~= Enum.KeyCode.Unknown
        and i.UserInputType == Enum.UserInputType.Keyboard and i.KeyCode == kbKey then
        return true
    end
    if gpKey and gpKey ~= Enum.KeyCode.Unknown
        and isGamepad(i.UserInputType) and i.KeyCode == gpKey then
        return true
    end
    return false
end

Maid:Give(UserInputService.InputBegan:Connect(function(i, gp)
    -- 1. A keybind picker is waiting for the next key / gamepad button.
    if activeCapture then
        local isKb = i.UserInputType == Enum.UserInputType.Keyboard
        local isGp = isGamepad(i.UserInputType)
        if (isKb or isGp) and i.KeyCode ~= Enum.KeyCode.Unknown then
            if i.KeyCode == Enum.KeyCode.Escape then pcall(activeCapture.cancel)
            else pcall(activeCapture.assign, i.KeyCode, isGp) end
            return
        end
    end

    if UserInputService:GetFocusedTextBox() then return end

    -- 2. UI toggle (works even when game-processed so it can't get stuck).
    if i.KeyCode == Enum.KeyCode.RightShift or i.KeyCode == Enum.KeyCode.Insert then
        setVisible(not uiVisible)
    end

    -- 3. Feature hotkeys (keyboard + controller).
    if S.slamHotkey      and matchBind(i, gp, S.bindSlamKb,  S.bindSlamGp)  then manualSlam() end
    if S.grabSlamEnabled and matchBind(i, gp, S.bindGrabKb,  S.bindGrabGp)  then grabSlam() end
    if S.flashStepEnabled and matchBind(i, gp, S.bindFlashKb, S.bindFlashGp) then flashStep() end
    if S.walkEnabled     and matchBind(i, gp, S.bindWalkKb,  S.bindWalkGp)  then toggleWalk() end
    if S.toggleFly       and matchBind(i, gp, S.bindFlyKb,   S.bindFlyGp)   then S.toggleFly() end
    if not gp then
        local ut = i.UserInputType
        -- left-click only: right-click is camera pan / block, not an attack
        local isClick = ut == Enum.UserInputType.MouseButton1
        local isTrigger = isGamepad(ut) and i.KeyCode == Enum.KeyCode.ButtonR2
        if S.rapidPunch and isCombatSafe() and (isClick or isTrigger or ut == Enum.UserInputType.Touch) then S.doRapidPunch() end
        if S.reach and isCombatSafe() and (isClick or isTrigger or ut == Enum.UserInputType.Touch) then reachPunch() end
        if S.godmode and isCombatSafe() and (isClick or isTrigger or ut == Enum.UserInputType.Touch) then godmodeClickHit() end
    end
end))
end)()

Tabs["Combat"].select()
fitHost()

----------------------------------------------------------------------
-- Floating launcher — charcoal "V" (draggable)
----------------------------------------------------------------------
;(function()
    local btnFrame = new("Frame", {
        Name = "ToggleButton", Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(20, 100),
        BackgroundColor3 = Color3.fromRGB(28, 28, 32), BorderSizePixel = 0, ZIndex = 10, Active = true,
    }, ScreenGui)
    Maid:GiveInst(btnFrame)
    corner(btnFrame, 22)
    stroke(btnFrame, C.Line, 1, 0.45)
    new("Frame", {
        Size = UDim2.new(0, 3, 0.45, 0), Position = UDim2.new(0, 0, 0.275, 0),
        BackgroundColor3 = C.Red, BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 11,
    }, btnFrame)
    local scaleObj = new("UIScale", { Scale = 1 }, btnFrame)

    new("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "V", TextColor3 = C.Text,
        Font = Enum.Font.GothamBlack, TextSize = 20, ZIndex = 12,
    }, btnFrame)

    local drag = { on = false, moved = false, start = nil, origin = nil }
    Maid:Give(btnFrame.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
            drag.on = true; drag.moved = false; drag.start = i.Position; drag.origin = btnFrame.Position
            tw(scaleObj, SNAP, { Scale = 0.9 }):Play()
        end
    end))
    Maid:Give(UserInputService.InputChanged:Connect(function(i)
        if drag.on and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
            local delta = i.Position - drag.start
            if delta.Magnitude > 5 then drag.moved = true end
            local o = drag.origin
            local vp = (Cam and Cam.ViewportSize) or Vector2.new(1280, 720)
            local nx = o.X.Offset + delta.X
            local ny = o.Y.Offset + delta.Y
            if nx < 4 then nx = 4 elseif nx > vp.X - 48 then nx = math.max(4, vp.X - 48) end
            if ny < 4 then ny = 4 elseif ny > vp.Y - 48 then ny = math.max(4, vp.Y - 48) end
            btnFrame.Position = UDim2.fromOffset(nx, ny)
        end
    end))
    Maid:Give(btnFrame.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
            tw(scaleObj, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
            if not drag.moved then setVisible(not uiVisible) end
            drag.on = false
        end
    end))
end)()

----------------------------------------------------------------------
-- Loading screen (own register frame)
----------------------------------------------------------------------
;(function()
    -- Nuke any leftover loader from a prior broken execute (do NOT touch the new suite GUI).
    pcall(function()
        local roots = {}
        if typeof(gethui) == "function" then pcall(function() roots[#roots + 1] = gethui() end) end
        pcall(function() roots[#roots + 1] = game:GetService("CoreGui") end)
        pcall(function() roots[#roots + 1] = LP:FindFirstChild("PlayerGui") end)
        for _, root in ipairs(roots) do
            for _, g in ipairs(root:GetChildren()) do
                if type(g.Name) == "string" and g.Name:match("^CAF2_Loader") then
                    pcall(function() g:Destroy() end)
                end
            end
        end
    end)

    local LoadingGui = new("ScreenGui", {
        Name = "CAF2_Loader_" .. tostring(MY_SESSION),
        ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true,
        DisplayOrder = 999999, Enabled = true,
    })
    local ok = false
    if typeof(gethui) == "function" then ok = pcall(function() LoadingGui.Parent = gethui() end) end
    if not ok and syn and syn.protect_gui then pcall(function() syn.protect_gui(LoadingGui); LoadingGui.Parent = game:GetService("CoreGui") end); ok = true end
    if not ok then pcall(function() LoadingGui.Parent = game:GetService("CoreGui") end) end
    if not LoadingGui.Parent then LoadingGui.Parent = LP:WaitForChild("PlayerGui") end

    local Acc = Theme.Accent or C.Red
    local AccGlow = Theme.AccentGlow or C.RedHi
    local Acc2 = Theme.Accent2 or C.RedInk

    ------------------------------------------------------------------
    -- Stage + rainfall / snowfall + cinematic intro
    ------------------------------------------------------------------
    local loadBg = new("Frame", {
        Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(14, 8, 14),
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 100,
    }, LoadingGui)
    gradient(loadBg, Color3.fromRGB(48, 18, 30), Color3.fromRGB(10, 6, 12), 140)

    -- soft vignette only (no giant red orbs)
    for _, band in ipairs({
        { UDim2.new(1, 0, 0, 160), UDim2.fromScale(0, 0), 0 },
        { UDim2.new(1, 0, 0, 180), UDim2.fromScale(0, 1), 1 },
    }) do
        local v = new("Frame", {
            Size = band[1], Position = band[2], AnchorPoint = Vector2.new(0, band[3]),
            BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 100,
        }, loadBg)
        local vg = new("UIGradient", { Rotation = 90 }, v)
        if band[3] == 0 then
            vg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
        else
            vg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
        end
    end

    local fxLayer = new("Frame", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
        ClipsDescendants = true, ZIndex = 101,
    }, loadBg)

    local function startRainDrop(drop)
        if not drop.Parent or not LoadingGui.Parent then return end
        local x = math.random(-5, 105) / 100
        drop.Position = UDim2.fromScale(x, -0.12)
        drop.BackgroundTransparency = 0.25 + math.random() * 0.45
        local dur = 0.85 + math.random() * 1.35
        local drift = (math.random() * 0.08) - 0.01
        local t = tw(drop, TweenInfo.new(dur, Enum.EasingStyle.Linear), {
            Position = UDim2.fromScale(x + drift, 1.12),
            BackgroundTransparency = 0.9,
        })
        t.Completed:Connect(function()
            if drop.Parent and LoadingGui.Parent then startRainDrop(drop) end
        end)
        t:Play()
    end

    for i = 1, 52 do
        local h = math.random(12, 26)
        local drop = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.fromScale(math.random(), -0.2),
            Size = UDim2.fromOffset(math.random(1, 2), h),
            BackgroundColor3 = (i % 4 == 0) and Color3.fromRGB(255, 190, 200) or Color3.fromRGB(240, 240, 250),
            BackgroundTransparency = 1, BorderSizePixel = 0, Rotation = 14, ZIndex = 101,
        }, fxLayer)
        corner(drop, 1)
        task.delay(math.random() * 2.2, function()
            if drop.Parent then startRainDrop(drop) end
        end)
    end

    local function startSnow(flake)
        if not flake.Parent or not LoadingGui.Parent then return end
        local x = math.random(-5, 105) / 100
        local size = math.random(2, 5)
        flake.Size = UDim2.fromOffset(size, size)
        flake.Position = UDim2.fromScale(x, -0.08)
        flake.BackgroundTransparency = 0.15 + math.random() * 0.4
        local dur = 2.4 + math.random() * 2.8
        local drift = (math.random() * 0.16) - 0.08
        local t = tw(flake, TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
            Position = UDim2.fromScale(x + drift, 1.1),
            BackgroundTransparency = 0.95,
        })
        t.Completed:Connect(function()
            if flake.Parent and LoadingGui.Parent then startSnow(flake) end
        end)
        t:Play()
    end

    for i = 1, 28 do
        local flake = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(math.random(), -0.1),
            Size = UDim2.fromOffset(3, 3),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 101,
        }, fxLayer)
        corner(flake, 999)
        task.delay(math.random() * 2.5, function()
            if flake.Parent then startSnow(flake) end
        end)
    end

    ------------------------------------------------------------------
    -- Cinematic intro overlay (before the card)
    ------------------------------------------------------------------
    local intro = new("Frame", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 150,
    }, loadBg)
    local introScale = new("UIScale", { Scale = 0.92 }, intro)
    local introMark = new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42),
        Size = UDim2.fromOffset(520, 70), BackgroundTransparency = 1,
        Text = "VELORIX", TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.GothamBlack, TextSize = 58, TextTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 151,
    }, intro)
    local introLine = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.50),
        Size = UDim2.fromOffset(0, 2), BackgroundColor3 = AccGlow,
        BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 151,
    }, intro)
    corner(introLine, 1)
    local introSub = new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55),
        Size = UDim2.fromOffset(420, 24), BackgroundTransparency = 1,
        Text = "CATCH A FADE 2  ·  PREMIUM", TextColor3 = Color3.fromRGB(255, 190, 200),
        Font = Enum.Font.GothamMedium, TextSize = 14, TextTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 151,
    }, intro)
    local introHint = new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62),
        Size = UDim2.fromOffset(360, 18), BackgroundTransparency = 1,
        Text = "booting suite...", TextColor3 = Color3.fromRGB(200, 180, 190),
        Font = Enum.Font.Gotham, TextSize = 12, TextTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 151,
    }, intro)

    ------------------------------------------------------------------
    -- Loader card (revealed after intro)
    ------------------------------------------------------------------
    local cardHost = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(360, 420), BackgroundTransparency = 1, ZIndex = 102,
        Visible = false,
    }, loadBg)
    local cardScale = new("UIScale", { Scale = 0.86 }, cardHost)

    for i = 1, 2 do
        local cardShadow = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(1, i * 16, 1, i * 16),
            BackgroundColor3 = Color3.fromRGB(0, 0, 0),
            BackgroundTransparency = 0.62 + i * 0.14, BorderSizePixel = 0, ZIndex = 102,
        }, cardHost)
        corner(cardShadow, 24 + i * 4)
    end

    local glass = new("CanvasGroup", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(42, 30, 40),
        BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 103,
    }, cardHost)
    corner(glass, 22)
    do
        local plate = new("Frame", {
            Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(42, 30, 40),
            BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 103,
        }, glass)
        corner(plate, 22)
        gradient(plate, Color3.fromRGB(68, 38, 50), Color3.fromRGB(28, 20, 32), 145)
    end
    do
        local rim = new("Frame", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 110,
        }, glass)
        corner(rim, 22)
        stroke(rim, Color3.fromRGB(255, 255, 255), 1, 0.88)
    end
    do
        local sheen = new("Frame", {
            Size = UDim2.new(1, 0, 0, 100), BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BackgroundTransparency = 0.94, BorderSizePixel = 0, ZIndex = 103,
        }, glass)
        local sg = new("UIGradient", { Rotation = 90 }, sheen)
        sg.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1),
        })
    end

    local container = new("Frame", {
        Size = UDim2.new(1, -40, 1, -40), Position = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1, ZIndex = 105,
    }, glass)

    local logoImg = LOGO_ASSET or DCPFP_IMAGE

    local logoGlow = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.fromOffset(126, 126),
        BackgroundColor3 = AccGlow, BackgroundTransparency = 0.76, BorderSizePixel = 0, ZIndex = 105,
    }, container)
    corner(logoGlow, 34)

    local logoRing = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.fromOffset(100, 100),
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 106,
    }, container)
    corner(logoRing, 28)
    stroke(logoRing, AccGlow, 2, 0.32)

    local logo = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.fromOffset(84, 84),
        BackgroundColor3 = Acc, BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 107,
    }, container)
    corner(logo, 24)
    gradient(logo, AccGlow, Acc2, 135)
    stroke(logo, Color3.fromRGB(255, 230, 235), 1.6, 0.28)
    local logoScale = new("UIScale", { Scale = 0.7 }, logo)
    do
        local shine = new("Frame", {
            Size = UDim2.new(1, -6, 0.42, 0), Position = UDim2.fromOffset(3, 3),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.68,
            BorderSizePixel = 0, ZIndex = 108,
        }, logo)
        corner(shine, 20)
        new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 1),
        }) }, shine)
    end

    local leftBar, rightBar
    if logoImg then
        local img = new("ImageLabel", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = logoImg,
            ScaleType = Enum.ScaleType.Crop, ZIndex = 109,
        }, logo)
        corner(img, 24)
    else
        local vLabel = new("TextLabel", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "V",
            Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 255, 255), TextScaled = true,
            TextStrokeTransparency = 0.6, TextStrokeColor3 = Color3.fromRGB(90, 10, 25), ZIndex = 109,
        }, logo)
        new("UITextSizeConstraint", { MaxTextSize = 52 }, vLabel)
        new("UIPadding", {
            PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
            PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
        }, vLabel)
        leftBar = vLabel
        rightBar = vLabel
    end

    local badge = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 118),
        Size = UDim2.fromOffset(120, 22), BackgroundColor3 = Acc, BackgroundTransparency = 1,
        BorderSizePixel = 0, ZIndex = 106,
    }, container)
    corner(badge, 11)
    stroke(badge, Acc, 1, 0.55)
    new("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "CATCH A FADE",
        TextColor3 = Color3.fromRGB(255, 220, 225), Font = Enum.Font.GothamBold, TextSize = 9, ZIndex = 107,
    }, badge)

    local title = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 152), BackgroundTransparency = 1,
        Text = "VELORIX", TextColor3 = Color3.fromRGB(255, 255, 255), Font = Enum.Font.GothamBlack, TextSize = 32,
        TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 106,
    }, container)
    local subtitle = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 188), BackgroundTransparency = 1,
        Text = "CATCH A FADE 2", TextColor3 = Color3.fromRGB(230, 170, 180), Font = Enum.Font.GothamMedium, TextSize = 11,
        TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 106,
    }, container)

    local pctLabel = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 228), BackgroundTransparency = 1,
        Text = "0%", TextColor3 = Color3.fromRGB(255, 255, 255), Font = Enum.Font.GothamBlack, TextSize = 20,
        TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 106,
    }, container)

    local barBg = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 262), Size = UDim2.fromOffset(240, 5),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.92, BorderSizePixel = 0, ZIndex = 106,
    }, container)
    corner(barBg, 3)
    local barFill = new("Frame", {
        Size = UDim2.fromScale(0, 1), BackgroundColor3 = Acc, BorderSizePixel = 0, ZIndex = 107,
    }, barBg)
    corner(barFill, 3)
    gradient(barFill, AccGlow, Acc, 0)

    local loadStatus = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 280), BackgroundTransparency = 1,
        Text = "Initializing...", TextColor3 = Color3.fromRGB(240, 210, 215), Font = Enum.Font.GothamMedium, TextSize = 11,
        TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 106,
    }, container)

    local tipLabel = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 310), BackgroundTransparency = 1,
        Text = "RightShift  ·  toggle menu", TextColor3 = Color3.fromRGB(200, 170, 175), Font = Enum.Font.Gotham, TextSize = 10,
        TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 106,
    }, container)

    new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(1, 0, 0, 14),
        BackgroundTransparency = 1, Text = "CATCH A FADE 2",
        TextColor3 = Color3.fromRGB(200, 150, 160), Font = Enum.Font.GothamBold, TextSize = 8,
        TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 106,
    }, container)

    ------------------------------------------------------------------
    -- Sequence: cinematic intro -> card -> load -> handoff
    ------------------------------------------------------------------
    task.spawn(function()
        local function finish()
            pcall(function()
                if LoadingGui and LoadingGui.Parent then LoadingGui:Destroy() end
            end)
            pcall(function() setVisible(true) end)
            task.delay(0.6, function()
                if not isCurrent() then return end
                showCornerToast("VELORIX", "Credits To @ sai (Xanax) for the Bypass", 7)
            end)
        end

        local okSeq, errSeq = pcall(function()
            tw(loadBg, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.32 }):Play()
            task.wait(0.25)

            tw(introScale, TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = 1 }):Play()
            tw(introMark, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
            task.wait(0.2)
            tw(introLine, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(220, 2) }):Play()
            tw(introSub, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { TextTransparency = 0.05 }):Play()
            task.wait(0.15)
            tw(introHint, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0.12 }):Play()
            task.wait(2.0)

            local fadeOut = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            tw(introMark, fadeOut, { TextTransparency = 1 }):Play()
            tw(introSub, fadeOut, { TextTransparency = 1 }):Play()
            tw(introHint, fadeOut, { TextTransparency = 1 }):Play()
            tw(introLine, fadeOut, { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 2) }):Play()
            tw(introScale, fadeOut, { Scale = 1.06 }):Play()
            task.wait(0.42)
            intro.Visible = false

            cardHost.Visible = true
            tw(cardScale, TweenInfo.new(0.65, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
            tw(logoScale, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
            tw(logoGlow, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
                { BackgroundTransparency = 0.78, Size = UDim2.fromOffset(122, 122) }):Play()
            tw(badge, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.7 }):Play()
            tw(title, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
            tw(subtitle, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { TextTransparency = 0.08 }):Play()
            tw(pctLabel, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0.05 }):Play()
            tw(loadStatus, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
            tw(tipLabel, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0.1 }):Play()
            tw(barBg, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.88 }):Play()
            if leftBar and leftBar:IsA("TextLabel") then leftBar.TextTransparency = 0 end
            task.wait(0.2)

            local steps = {
                { 0.14, "Initializing..." },
                { 0.30, "Loading interface..." },
                { 0.48, "Verifying modules..." },
                { 0.66, "Syncing combat..." },
                { 0.84, "Loading config..." },
                { 0.95, "Finalizing..." },
                { 1.00, "Welcome" },
            }
            for _, step in ipairs(steps) do
                if not isCurrent() or not LoadingGui.Parent then return end
                local targetVal, text = step[1], step[2]
                loadStatus.Text = text
                local targetPct = math.floor(targetVal * 100)
                local startPct = tonumber((pctLabel.Text or "0"):match("%d+")) or 0
                local frames = 12
                for f = 1, frames do
                    if not LoadingGui.Parent then return end
                    local alpha = f / frames
                    local pct = math.floor(startPct + (targetPct - startPct) * alpha)
                    pctLabel.Text = tostring(pct) .. "%"
                    barFill.Size = UDim2.fromScale(startPct / 100 + (targetVal - startPct / 100) * alpha, 1)
                    task.wait(0.03)
                end
                pctLabel.Text = tostring(targetPct) .. "%"
                barFill.Size = UDim2.fromScale(targetVal, 1)
                task.wait(0.06)
            end

            task.wait(0.28)
            if LoadingGui.Parent then
                local info = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                pcall(function() tw(cardScale, info, { Scale = 1.05 }):Play() end)
                pcall(function() tw(glass, info, { BackgroundTransparency = 1 }):Play() end)
                pcall(function() tw(loadBg, info, { BackgroundTransparency = 1 }):Play() end)
                pcall(function() tw(title, info, { TextTransparency = 1 }):Play() end)
                pcall(function() tw(pctLabel, info, { TextTransparency = 1 }):Play() end)
                pcall(function() tw(loadStatus, info, { TextTransparency = 1 }):Play() end)
                pcall(function() tw(subtitle, info, { TextTransparency = 1 }):Play() end)
                pcall(function() tw(badge, info, { BackgroundTransparency = 1 }):Play() end)
                task.wait(0.4)
            end
        end)

        if not okSeq then
            warn("[VELORIX] loader sequence error: ", errSeq)
        end
        finish()
    end)
end)()

genv.__CAF2_SUITE = {}
-- Only tear down THIS session's Maid/GUI. Never wipe all CAF2_* (that was
-- destroying the next execute's loader and freezing it at 0%).
function genv.__CAF2_SUITE.Unload()
    local dyingSession = MY_SESSION
    S.infStamina = false; S.fly = false; S.flyActive = false; S.noclip = false
    S.jumpEnabled = false; S.walkEnabled = false; S.walkActive = false
    S.noFallDamage = false
    S.killFocus = false; S.freezeFocus = false; S.killAura = false; S.ragdollAura = false; S.antiStun = false; S.godmode = false
    pcall(function() if S.setStreamerMode then S.setStreamerMode(false) end end)
    pcall(disableInfStamina)
    pcall(function() if S.setFly then S.setFly(false) end end)
    pcall(function() if S._stopJumpAssist then S._stopJumpAssist() end end)
    pcall(resetJumpHard) -- always wipe leftover hop / boosted JP (don't trust polluted bases)
    pcall(function() if S._stopTouchFling then S._stopTouchFling() end end)
    pcall(function() if S._stopFirstPerson then S._stopFirstPerson() end end)
    pcall(function() if S._morphRestore then S._morphRestore() end end)
    -- Belt-and-suspenders camera reset so a mid-FP unload never leaves you stuck
    pcall(function()
        LP.CameraMode = Enum.CameraMode.Classic
        LP.CameraMinZoomDistance = 0.5
        LP.CameraMaxZoomDistance = 128
        local c = Workspace.CurrentCamera
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if c then
            c.CameraType = Enum.CameraType.Custom
            if hum then c.CameraSubject = hum end
            c.FieldOfView = 70
        end
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        local char = LP.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.LocalTransparencyModifier = 0 end
            end
        end
    end)
    pcall(function()
        local h = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if h then
            h.WalkSpeed = WALK_BASE
            h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
        end
    end)
    pcall(function() Maid:Clean() end)
    if genv.__CAF2_SESSION == dyingSession then
        genv.__CAF2_SESSION = dyingSession + 1
    end
    genv.__CAF2_SUITE = nil
end
function genv.__CAF2_SUITE.SetMobileLayout(on)
    Layout.override = (on == true)
    if fitHost then fitHost() end
end
function genv.__CAF2_SUITE.ClearLayoutOverride()
    Layout.override = nil
    if fitHost then fitHost() end
end

do
    local g = (typeof(getgenv) == "function" and getgenv()) or _G
    g.__CAF2_BOOT = "done"
    g.CAF2 = g.CAF2 or {}
    g.CAF2.S = S
end

-- Fresh load = nothing enabled. Configs must be loaded manually from Settings.
-- (Autoload is intentionally not run so combat/morph/camera never come on hot.)
pcall(function()
    resetJumpHard() -- clear any leftover hop/boost from a prior execute
end)
pcall(function()
    if S._stopFirstPerson then S._stopFirstPerson() end
end)
pcall(function()
    local UIS = game:GetService("UserInputService")
    local cam = workspace.CurrentCamera
    LP.CameraMode = Enum.CameraMode.Classic
    LP.CameraMinZoomDistance = 0.5
    LP.CameraMaxZoomDistance = 128
    UIS.MouseBehavior = Enum.MouseBehavior.Default
    UIS.MouseIconEnabled = true
    if cam then
        cam.CameraType = Enum.CameraType.Custom
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum then cam.CameraSubject = hum end
    end
end)

print("[CAF2 Premium] loaded — RightShift to toggle, X to close.")
