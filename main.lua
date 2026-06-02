    local repo = "https://raw.githubusercontent.com/Tzvyy/JopLib/main/"
    local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
    local Elements = loadstring(game:HttpGet(repo .. "Elements.lua"))()
    local ThemeManager = loadstring(game:HttpGet(repo .. "ThemeManager.lua"))()
    local SaveManager = loadstring(game:HttpGet(repo .. "SaveManager.lua"))()

    Elements:Setup(Library)
    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)

    -- Services & Locals
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UIS = game:GetService("UserInputService")
    local VIM = game:GetService("VirtualInputManager")
    local WS = game:GetService("Workspace")
    local LP = Players.LocalPlayer
    local PlayerGui = LP:WaitForChild("PlayerGui")
    local Camera = WS.CurrentCamera

    -- Localized globals
    local V2, V3 = Vector2.new, Vector3.new
    local min, max, floor, clamp, huge, pow, fmt = math.min, math.max, math.floor, math.clamp, math.huge, math.pow, string.format
    local insert = table.insert
    local SIGNS = {V3(-1,-1,-1),V3(-1,-1,1),V3(-1,1,-1),V3(-1,1,1),V3(1,-1,-1),V3(1,-1,1),V3(1,1,-1),V3(1,1,1)}

    -- Proxy tables
    local Toggles = Library.Toggles
    local Options = Library.Options

    -- Window
    local Window = Library:CreateWindow({
        Title = "ABA Helper | by josepi",
        Center = true,
        AutoShow = true,
        TabPadding = 8,
    })

    local Tabs = {
        Tween      = Window:AddTab("Tween"),
        PvP        = Window:AddTab("PvP"),
        Esp        = Window:AddTab("Esp"),
        Macros     = Window:AddTab("Macros"),
        Exploits   = Window:AddTab("Exploits"),
        ["GUI Settings"] = Window:AddTab("GUI Settings"),
    }

    -- State
    local status_nanami, status_camera, status_kokushibo = false, false, false
    local status_esp = false
    local status_esp_box = false
    local status_esp_name = false
    local status_esp_hpbar = false
    local status_esp_modebar = false
    local status_esp_modepct = false
    local cam_lock_enabled, camera_lock_timing = false, false
    local tween_enabled = false
    local Target, CamLockTarget, TweenConnection = nil, nil, nil

    -- FOV Circles
    local function mkCircle(color)
        local c = Drawing.new("Circle")
        c.Thickness = 1; c.NumSides = 64; c.Filled = false; c.Transparency = 0.5; c.Color = color
        return c
    end
    local FOVCircle = mkCircle(Color3.new(1,1,1))
    local CamLockFOVCircle = mkCircle(Color3.fromRGB(255,50,50))

    -- ============================================================================
    --                         BOX ESP + CHARGE BAR
    -- ============================================================================

    local ESP_COL        = Color3.new(1,1,1)
    local ESP_THICK      = 1.5
    local BAR_T          = 6       -- bar thickness (same for both)
    local BAR_GAP        = 3       -- gap between box and bar
    local TXT_GAP        = 2
    local HP_COL         = Color3.fromRGB(0,200,80)
    local MODE_COL       = Color3.fromRGB(255,50,50)
    local BAR_BG_COL     = Color3.fromRGB(40,40,40)
    local DIV_COL        = Color3.fromRGB(20,20,20)
    local espCache = {}

    local function mkDraw(t, props)
        local d = Drawing.new(t)
        for k,v in pairs(props) do d[k] = v end
        return d
    end

    local function mkBar(fillCol)
        return {
            bg   = mkDraw("Square",{Color=BAR_BG_COL,Filled=true,Transparency=0.5,Visible=false}),
            fill = mkDraw("Square",{Color=fillCol,Filled=true,Transparency=0.8,Visible=false}),
            out  = mkDraw("Square",{Color=Color3.new(0,0,0),Thickness=1,Filled=false,Visible=false}),
            d1   = mkDraw("Line",{Color=DIV_COL,Thickness=1,Visible=false}),
            d2   = mkDraw("Line",{Color=DIV_COL,Thickness=1,Visible=false}),
            d3   = mkDraw("Line",{Color=DIV_COL,Thickness=1,Visible=false}),
        }
    end

    local function getEspCache(m)
        local d = espCache[m]; if d then return d end
        d = {
            box  = mkDraw("Square",{Color=ESP_COL,Thickness=ESP_THICK,Filled=false,Visible=false}),
            name = mkDraw("Text",{Color=ESP_COL,Size=14,Font=0,Center=true,Outline=true,Visible=false}),
            pct  = mkDraw("Text",{Color=Color3.new(1,1,1),Size=17,Font=0,Center=true,Outline=true,Visible=false}),
            hp   = mkBar(HP_COL),
            mode = mkBar(MODE_COL),
        }
        espCache[m] = d; return d
    end

    local function removeBar(b)
        b.bg:Remove(); b.fill:Remove(); b.out:Remove(); b.d1:Remove(); b.d2:Remove(); b.d3:Remove()
    end

    local function cleanEsp(k)
        local d = espCache[k]; if not d then return end
        d.box:Remove(); d.name:Remove(); d.pct:Remove()
        removeBar(d.hp); removeBar(d.mode)
        espCache[k] = nil
    end

    local function hideBar(b)
        b.bg.Visible,b.fill.Visible,b.out.Visible,b.d1.Visible,b.d2.Visible,b.d3.Visible = false,false,false,false,false,false
    end

    local function hideEsp(d)
        d.box.Visible,d.name.Visible,d.pct.Visible = false,false,false
        hideBar(d.hp); hideBar(d.mode)
    end

    -- Draw a vertical bar (fills bottom-to-top)
    local function drawVBar(b, x, y, w, h, pct)
        b.bg.Size,b.bg.Position,b.bg.Visible = V2(w,h),V2(x,y),true
        b.out.Size,b.out.Position,b.out.Visible = V2(w,h),V2(x,y),true
        local fh = h * pct; if fh < 1 then fh = 1 end
        b.fill.Size,b.fill.Position,b.fill.Visible = V2(w,fh),V2(x, y + h - fh),true
        -- 3 dividers at 25%, 50%, 75%
        for i,div in ipairs({b.d1,b.d2,b.d3}) do
            local dy = y + h * (i * 0.25)
            div.From,div.To,div.Visible = V2(x,dy),V2(x+w,dy),true
        end
    end

    -- Draw a horizontal bar (fills left-to-right)
    local function drawHBar(b, x, y, w, h, pct)
        b.bg.Size,b.bg.Position,b.bg.Visible = V2(w,h),V2(x,y),true
        b.out.Size,b.out.Position,b.out.Visible = V2(w,h),V2(x,y),true
        local fw = w * pct; if fw < 1 then fw = 1 end
        b.fill.Size,b.fill.Position,b.fill.Visible = V2(fw,h),V2(x,y),true
        -- 3 dividers at 25%, 50%, 75%
        for i,div in ipairs({b.d1,b.d2,b.d3}) do
            local dx = x + w * (i * 0.25)
            div.From,div.To,div.Visible = V2(dx,y),V2(dx,y+h),true
        end
    end

    local function bbox(model)
        local mnX,mnY,mxX,mxY = huge,huge,-huge,-huge
        local found = false
        for _,v in ipairs(model:GetChildren()) do
            if v:IsA("BasePart") then
                found = true
                local cf,sz = v.CFrame, v.Size*0.5
                for i=1,8 do
                    local s = SIGNS[i]
                    local sp,on = Camera:WorldToViewportPoint(cf*V3(s.X*sz.X,s.Y*sz.Y,s.Z*sz.Z))
                    if not on then return nil end
                    local x,y = sp.X,sp.Y
                    if x<mnX then mnX=x end; if y<mnY then mnY=y end
                    if x>mxX then mxX=x end; if y>mxY then mxY=y end
                end
            end
        end
        return found and mnX or nil, mnY, mxX, mxY
    end

    -- Player map (reused by ESP + targeting)
    local pMap = {}
    local function rebuildPlayerMap()
        for k in pairs(pMap) do pMap[k] = nil end
        for _,p in ipairs(Players:GetPlayers()) do
            if p ~= LP and p.Character then pMap[p.Character] = p end
        end
    end

    -- ============================================================================
    --                         SHARED TARGET FINDER
    -- ============================================================================

    local function findClosestTarget(fovRadius, range)
        local vp = Camera.ViewportSize
        local center = V2(vp.X * 0.5, vp.Y * 0.5)
        local myHrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        local best, bestScore = nil, huge

        -- Iterate player characters from pMap (already built)
        for char, _ in pairs(pMap) do
            local hum = char:FindFirstChildOfClass("Humanoid")
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hum and hrp and hum.Health > 0 then
                local distMe = myHrp and (hrp.Position - myHrp.Position).Magnitude or 0
                if distMe <= range then
                    local sp, on = Camera:WorldToViewportPoint(hrp.Position)
                    if on then
                        local distCenter = (V2(sp.X, sp.Y) - center).Magnitude
                        if distCenter <= fovRadius then
                            local score = distCenter + distMe * 0.5
                            if score < bestScore then bestScore = score; best = char end
                        end
                    end
                end
            end
        end

        -- Also check NPCs in workspace.Live
        local live = WS:FindFirstChild("Live")
        if live then
            local lc = LP.Character
            for _, npc in ipairs(live:GetChildren()) do
                if npc:IsA("Model") and npc ~= lc and not pMap[npc] then
                    local hum = npc:FindFirstChildOfClass("Humanoid")
                    local hrp = npc:FindFirstChild("HumanoidRootPart")
                    if hum and hrp and hum.Health > 0 then
                        local distMe = myHrp and (hrp.Position - myHrp.Position).Magnitude or 0
                        if distMe <= range then
                            local sp, on = Camera:WorldToViewportPoint(hrp.Position)
                            if on then
                                local distCenter = (V2(sp.X, sp.Y) - center).Magnitude
                                if distCenter <= fovRadius then
                                    local score = distCenter + distMe * 0.5
                                    if score < bestScore then bestScore = score; best = npc end
                                end
                            end
                        end
                    end
                end
            end
        end

        return best
    end

    -- ============================================================================
    --                              AUTO QTEs
    -- ============================================================================

    local function clicarM1()
        VIM:SendMouseButtonEvent(0,0,0,true,game,0)
        task.wait(0.01)
        VIM:SendMouseButtonEvent(0,0,0,false,game,0)
    end

    local function clicarM2()
        VIM:SendMouseButtonEvent(0,0,1,true,game,0)
        task.wait(0.05)
        VIM:SendMouseButtonEvent(0,0,1,false,game,0)
    end

    local function processarKokushibo(gui)
        local done = false
        local function checar(obj)
            if status_kokushibo and obj.Name == "ImageLabel" and not done then
                done = true; task.wait(0.30); clicarM2()
            end
        end
        for _, d in ipairs(gui:GetDescendants()) do checar(d) end
        local conn = gui.DescendantAdded:Connect(checar)
        gui.AncestryChanged:Connect(function() if not gui.Parent and conn then conn:Disconnect() end end)
    end

    PlayerGui.ChildAdded:Connect(function(child)
        if child.Name == "FrenchKokushibo" then processarKokushibo(child) end
    end)

    Camera:GetPropertyChangedSignal("FieldOfView"):Connect(function()
        if not status_camera then camera_lock_timing = false return end
        local fov = Camera.FieldOfView
        if fov <= 10 then camera_lock_timing = true end
        if camera_lock_timing and fov >= 15 then camera_lock_timing = false; clicarM1() end
    end)

    local function handleNanami(gui)
        local bar = gui:WaitForChild("MainBar", 5)
        local g = bar and bar:WaitForChild("Goal", 5)
        local c = bar and bar:WaitForChild("Cutter", 5)
        if not g or not c then return end
        task.wait(0.2)
        local conn; conn = RunService.Heartbeat:Connect(function()
            if not status_nanami or not gui.Parent then conn:Disconnect() return end
            if c.AbsolutePosition.X > 10 and c.AbsolutePosition.X >= g.AbsolutePosition.X + g.AbsoluteSize.X * 0.5 + 1 then
                clicarM1(); conn:Disconnect()
            end
        end)
    end

    WS.Live.DescendantAdded:Connect(function(obj)
        if obj.Name == "NanamiCutGUI" and status_nanami then handleNanami(obj) end
    end)

    -- ============================================================================
    --                            TWEEN SYSTEM
    -- ============================================================================

    local function startTweenLoop()
        if TweenConnection then TweenConnection:Disconnect() end
        TweenConnection = RunService.Heartbeat:Connect(function(dt)
            if not tween_enabled then return end
            local char = LP.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            if Target then
                local hum = Target:FindFirstChildOfClass("Humanoid")
                if not Target.Parent or (hum and hum.Health <= 0) then
                    Target = nil; Toggles.TweenTgl:SetValue(false); return
                end
            else
                Target = findClosestTarget(Options.FOVRadius and Options.FOVRadius.Value or 150, Options.TweenRange and Options.TweenRange.Value or 500)
                if not Target then return end
            end
            local head = Target:FindFirstChild("Head") or Target:FindFirstChild("HumanoidRootPart")
            if not head then return end
            local desired = head.Position + V3(0, Options.Height.Value, 0) + head.CFrame.LookVector * Options.Offset.Value
            local delta = desired - hrp.Position
            local dist = delta.Magnitude
            if dist < 0.1 then return end
            hrp.CFrame = hrp.CFrame + delta.Unit * min(dist, Options.Speed.Value * dt * 1.05)
        end)
    end

    -- ============================================================================
    --                       PROJECTILE MULTI-HIT (Ball)
    -- ============================================================================

    local proj_enabled = false
    local ThrownFolder = WS:FindFirstChild("Thrown") or WS:WaitForChild("Thrown", 5)
    local trackedBalls = {}
    local thrownAddedConn = nil

    local function buildProjectileTargets()
        local list, seen = {}, {}
        local myChar = LP.Character
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and p.Character and not seen[p.Character] then
                local hum = p.Character:FindFirstChildOfClass("Humanoid")
                local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                if hum and hrp and hum.Health > 0 then
                    seen[p.Character] = true
                    insert(list, p.Character)
                end
            end
        end
        if Toggles.ProjTpIncludeLive and Toggles.ProjTpIncludeLive.Value then
            local live = WS:FindFirstChild("Live")
            if live then
                for _, m in ipairs(live:GetChildren()) do
                    if m:IsA("Model") and m ~= myChar and not seen[m] then
                        local hum = m:FindFirstChildOfClass("Humanoid")
                        local hrp = m:FindFirstChild("HumanoidRootPart")
                        if hum and hrp and hum.Health > 0 then
                            seen[m] = true
                            insert(list, m)
                        end
                    end
                end
            end
        end
        return list
    end

    local function detachBall(ball)
        local s = trackedBalls[ball]
        if not s then return end
        trackedBalls[ball] = nil
        s.alive = false
        pcall(function()
            if s.bvForceSaved and s.bv and s.bv.Parent then s.bv.MaxForce = s.origMaxForce end
        end)
    end

    local function attachBall(ball)
        if trackedBalls[ball] or not ball:IsA("BasePart") then return end
        local s = { alive = true }
        trackedBalls[ball] = s

        local bv = ball:FindFirstChildOfClass("BodyVelocity")
        if bv then
            s.bv = bv
            s.origMaxForce = bv.MaxForce
            s.bvForceSaved = true
            bv.MaxForce = V3(0, 0, 0)
        end

        ball.AncestryChanged:Connect(function(_, parent)
            if not parent then detachBall(ball) end
        end)

        task.spawn(function()
            local targets = buildProjectileTargets()
            if #targets == 0 then detachBall(ball); return end
            local idx = 1
            while s.alive and proj_enabled do
                if not ball.Parent or not ball:IsDescendantOf(WS) then break end
                local t = targets[idx]
                local hum = t and t:FindFirstChildOfClass("Humanoid")
                local hrp = t and t:FindFirstChild("HumanoidRootPart")
                local valid = t and t.Parent and hum and hum.Health > 0 and hrp
                if not valid then
                    idx = idx + 1; if idx > #targets then idx = 1 end
                    targets = buildProjectileTargets()
                    if #targets == 0 then break end
                    if idx > #targets then idx = 1 end
                    task.wait(0.05)
                else
                    local ok = pcall(function()
                        ball.CFrame = CFrame.new(hrp.Position + V3(0, 1, 0))
                        ball.AssemblyLinearVelocity = V3(0, 0, 0)
                    end)
                    if not ok then break end
                    task.wait(0.05)
                    idx = idx + 1; if idx > #targets then idx = 1; targets = buildProjectileTargets(); if #targets == 0 then break end end
                end
            end
            detachBall(ball)
        end)
    end

    local function startProjectileWatcher()
        if thrownAddedConn or not ThrownFolder then return end
        thrownAddedConn = ThrownFolder.ChildAdded:Connect(function(c)
            if proj_enabled and c:IsA("BasePart") and c.Name == "Ball" then
                attachBall(c)
            end
        end)
        for _, c in ipairs(ThrownFolder:GetChildren()) do
            if c:IsA("BasePart") and c.Name == "Ball" then attachBall(c) end
        end
    end

    local function stopProjectileWatcher()
        if thrownAddedConn then thrownAddedConn:Disconnect(); thrownAddedConn = nil end
        for ball in pairs(trackedBalls) do detachBall(ball) end
    end

    -- ============================================================================
    --                           INTERFACE (JOPLIB)
    -- ============================================================================

    -- TWEEN TAB
    local TweenGroup = Tabs.Tween:AddLeftGroupbox("Tween")

    TweenGroup:AddToggle("TweenTgl", {
        Text = "Toggle Tween",
        Default = false,
    }):AddKeyPicker("TweenKey", {
        Default = "None",
        SyncToggleState = true,
        Mode = "Toggle",
        Text = "Toggle Tween",
    })

    TweenGroup:AddToggle("ShowFOV", {
        Text = "Show Fov",
        Default = false,
    })

    TweenGroup:AddSlider("FOVRadius", {
        Text = "Fov Size",
        Default = 150,
        Min = 50,
        Max = 500,
        Rounding = 0,
    })

    TweenGroup:AddSlider("TweenRange", {
        Text = "Range",
        Default = 250,
        Min = 10,
        Max = 500,
        Rounding = 0,
    })

    TweenGroup:AddSlider("Speed", {
        Text = "Speed",
        Default = 60,
        Min = 5,
        Max = 200,
        Rounding = 0,
    })

    TweenGroup:AddSlider("Height", {
        Text = "Height",
        Default = 3.5,
        Min = -5,
        Max = 10,
        Rounding = 1,
    })

    TweenGroup:AddSlider("Offset", {
        Text = "Offset",
        Default = 0.2,
        Min = -5,
        Max = 5,
        Rounding = 1,
    })

    Toggles.TweenTgl:OnChanged(function()
        tween_enabled = Toggles.TweenTgl.Value
        if tween_enabled then
            Target = findClosestTarget(Options.FOVRadius and Options.FOVRadius.Value or 150, Options.TweenRange and Options.TweenRange.Value or 500)
            startTweenLoop()
        else
            if TweenConnection then TweenConnection:Disconnect() end
            Target = nil
        end
    end)

    -- PVP TAB
    local RageGroup = Tabs.PvP:AddLeftGroupbox("Camera Lock")

    RageGroup:AddToggle("CamLockTgl", {
        Text = "Camera Lock",
        Default = false,
    }):AddKeyPicker("CamLockBind", {
        Default = "None",
        SyncToggleState = true,
        Mode = "Toggle",
        Text = "Camera Lock",
    })

    RageGroup:AddToggle("ShowCamLockFov", {
        Text = "Show Fov",
        Default = false,
    })

    RageGroup:AddSlider("CamLockFovSize", {
        Text = "Fov Size",
        Default = 150,
        Min = 50,
        Max = 800,
        Rounding = 0,
    })

    RageGroup:AddSlider("CamLockRange", {
        Text = "Range",
        Default = 250,
        Min = 10,
        Max = 500,
        Rounding = 0,
    })

    RageGroup:AddSlider("CamLockSmoothness", {
        Text = "Smoothness",
        Default = 25,
        Min = 0,
        Max = 100,
        Rounding = 0,
    })

    Toggles.CamLockTgl:OnChanged(function()
        cam_lock_enabled = Toggles.CamLockTgl.Value
        UIS.MouseDeltaSensitivity = cam_lock_enabled and 0 or 1
    end)

    -- ============================================================================
    -- LEGIT NO-STUN (velocity-only walk-out)
    --
    -- During an M1 / light-skill stun the game pins `Humanoid.WalkSpeed = 5` and
    -- suppresses humanoid acceleration. We never touch WalkSpeed (server-safe
    -- if the game adds a sanity check); instead, between knockback BVs, we
    -- write `HumanoidRootPart.AssemblyLinearVelocity` from WASD at the user's
    -- configured walk-out speed.
    --
    -- Gates (ALL must be true to override):
    --   * toggle on
    --   * an enemy-attributed stun tag (TagSystem2.TagReplicate) fired in last 0.6s
    --   * `Humanoid.WalkSpeed == 5` (M1 slow-walk; WS==0 grabs are NOT touched)
    --   * no StunBV/UpFling/DownerFling currently on HRP (knockback plays untouched)
    -- ============================================================================
    local nostun_enabled = false
    local nostun_walkout = 8
    local nostun_lastTagAt     = 0
    local nostun_actionAddedAt = 0

    -- Enemy-attributed stun tag names. `creator` is filtered by TrueValue so
    -- our own casts don't trigger.
    local STUN_TAG_NAMES = { creator = true, WASUPFLINGED = true, GotSlammed = true }

    local CombatGroup = Tabs.PvP:AddRightGroupbox("Combat")

    CombatGroup:AddToggle("LegitNoStunTgl", {
        Text = "Legit No-Stun",
        Default = false,
        Tooltip = "Walk out of M1 combos at the configured speed instead of being frozen.",
    })

    CombatGroup:AddSlider("LegitWalkoutSpeed", {
        Text = "Walk-out Speed",
        Default = 8, Min = 4, Max = 24, Rounding = 0, Increment = 1, Suffix = " studs/s",
    })

    Toggles.LegitNoStunTgl:OnChanged(function()
        nostun_enabled = Toggles.LegitNoStunTgl.Value
    end)
    Options.LegitWalkoutSpeed:OnChanged(function()
        nostun_walkout = Options.LegitWalkoutSpeed.Value
    end)

    -- ============================================================================
    -- AUTO TRADE — when blocking (F held) and an enemy hit registers (creator
    -- tag on our character), instantly fire one M1 back. ABA blocks the impact
    -- automatically since we're still holding F, so the trade is a free hit.
    -- ============================================================================
    CombatGroup:AddToggle("AutoTradeTgl", {
        Text = "Auto M1 Trade",
        Default = false,
        Tooltip = "When an enemy M1 hits your block, instantly trade with an M1 back.",
    })
    CombatGroup:AddSlider("AutoTradeComboGap", {
        Text = "Combo Gap Threshold",
        Default = 0.45, Min = 0.20, Max = 0.80, Rounding = 2,
        Increment = 0.05, Suffix = "s",
        Tooltip = "If two enemy M1 anims arrive within this gap, treat it as a held combo and delay the trade until hit #2 lands. Larger = more aggressive combo detection.",
    })
    local autotrade_enabled    = false
    local autotrade_lastAt     = 0      -- last time a trade actually fired (cooldown)
    local autotrade_lastAnimAt = 0      -- last time any enemy M1 anim arrived
    local autotrade_pendingTok = 0      -- token used to cancel scheduled trades
    local autotrade_running    = false  -- a trade sequence is currently executing
    local autotrade_animsSinceTrade = 0 -- enemy M1 anims observed since last trade fired
    local autotrade_hitsSinceTrade  = 0 -- enemy hits registered (TagReplicate) since last trade
    local autotrade_comboGap   = 0.45
    -- Pre-declared because runTrade (defined below) closes over them. The
    -- AutoBlock UI block lower down only assigns to these via OnChanged.
    local autoblock_enabled    = false
    local autoblock_range      = 12
    local autoblock_holding    = false
    local autoblock_raiseTok   = 0      -- bumped on every eager BlockOn; watchdog uses this to cancel
    Toggles.AutoTradeTgl:OnChanged(function()
        autotrade_enabled = Toggles.AutoTradeTgl.Value
    end)
    Options.AutoTradeComboGap:OnChanged(function()
        autotrade_comboGap = Options.AutoTradeComboGap.Value
    end)

    -- Resolve the Input remote (Backpack/Input) used for BlockOn/BlockOff/M1.
    -- Backpack is rebuilt on respawn so we re-resolve after CharacterAdded.
    local inputRemote
    local function refreshInputRemote()
        local bp = LP:FindFirstChildOfClass("Backpack")
        inputRemote = bp and bp:FindFirstChild("Input")
    end
    refreshInputRemote()
    LP.CharacterAdded:Connect(function() task.delay(0.5, refreshInputRemote) end)

    -- Core trade sequence. Returns immediately if the script unloaded or the
    -- character is gone. `needRaise` means we should manage block ourselves
    -- (auto-block path); otherwise the user is holding F.
    -- Eager BlockOn with self-cancelling watchdog: forces BlockOff after
    -- AUTOBLOCK_MAX_HOLD if no trade consumes it (cancelled schedule, toggle
    -- flipped off, finisher arrived, etc). Prevents stuck-block.
    local AUTOBLOCK_MAX_HOLD     = 0.8  -- per-raise watchdog timeout
    local AUTOBLOCK_ABSOLUTE_MAX = 1.5  -- absolute ceiling: drop block this long after FIRST raise no matter what
    local autoblock_firstRaiseAt = 0
    local function eagerBlockOn(shortHold)
        if not inputRemote then refreshInputRemote() end
        if not inputRemote then return end
        inputRemote:FireServer("BlockOn")
        local wasUp = autoblock_holding
        autoblock_holding   = true
        autoblock_raiseTok  = autoblock_raiseTok + 1
        local myTok = autoblock_raiseTok
        if not wasUp then autoblock_firstRaiseAt = tick() end
        local firstRaise = autoblock_firstRaiseAt
        local hold = shortHold or AUTOBLOCK_MAX_HOLD
        -- Per-raise watchdog: drops block if no further raises within hold.
        task.delay(hold, function()
            if myTok ~= autoblock_raiseTok then return end -- superseded
            if autotrade_running then return end
            if UIS:IsKeyDown(Enum.KeyCode.F) then return end
            if inputRemote then inputRemote:FireServer("BlockOff") end
            autoblock_holding = false
        end)
        -- Absolute-ceiling watchdog: even if anim spam keeps superseding the
        -- per-raise timer, force-drop block at firstRaise + ABSOLUTE_MAX.
        if not wasUp then
            task.delay(AUTOBLOCK_ABSOLUTE_MAX, function()
                if autoblock_firstRaiseAt ~= firstRaise then return end -- new sequence started
                if autotrade_running then return end
                if UIS:IsKeyDown(Enum.KeyCode.F) then return end
                if inputRemote then inputRemote:FireServer("BlockOff") end
                autoblock_holding = false
            end)
        end
    end

    local function runTrade(needRaise, myCharSnap, preImpactWait, postBlockOffWait)
        autotrade_lastAt   = tick()
        autotrade_running  = true
        autoblock_holding  = needRaise
        autoblock_raiseTok = autoblock_raiseTok + 1 -- invalidate pre-trade watchdogs
        autotrade_animsSinceTrade = 0
        autotrade_hitsSinceTrade  = 0
        autoblock_firstRaiseAt    = 0  -- next eagerBlockOn starts a fresh sequence
        local wait1 = preImpactWait or 0.15
        local wait2 = postBlockOffWait or 0.02
        task.spawn(function()
            if not inputRemote then refreshInputRemote() end
            local function bail()
                autotrade_running = false
                autoblock_holding = false
            end
            if not inputRemote then return bail() end
            if not (myCharSnap and myCharSnap.Parent) then return bail() end

            if needRaise then
                inputRemote:FireServer("BlockOn")
            end
            -- Wait for the enemy's M1 to land on block.
            if wait1 > 0 then task.wait(wait1) end
            if not myCharSnap.Parent then return bail() end

            local h2  = myCharSnap:FindFirstChildOfClass("Humanoid")
            local air = h2 and (h2:GetState() == Enum.HumanoidStateType.Freefall) or false
            inputRemote:FireServer("BlockOff")
            if wait2 > 0 then task.wait(wait2) end
            inputRemote:FireServer("M1", {
                air = air,
                skeyreal = false,
                skeydown = true,
                mousehit = Camera.CFrame,
                md = h2 and h2.MoveDirection or V3(0, 0, 0),
            })
            -- Re-raise block ONLY if the user is still manually holding F.
            -- In auto-block-only mode we leave block down: the next enemy M1
            -- anim re-triggers the eager BlockOn naturally.
            if UIS:IsKeyDown(Enum.KeyCode.F) then
                inputRemote:FireServer("BlockOn")
            end
            autotrade_running = false
            autoblock_holding = false
        end)
    end

    -- Auto Block lives inside a DependencyBox gated on Auto M1 Trade.
    local AutoBlockDep = CombatGroup:AddDependencyBox()
    AutoBlockDep:AddToggle("AutoBlockTgl", {
        Text = "Auto Block",
        Default = false,
        Tooltip = "When an enemy starts an M1 within range, auto-press block briefly. Skips the combo-finisher M1 which breaks block.",
    })
    AutoBlockDep:AddSlider("AutoBlockRange", {
        Text = "Auto Block Range",
        Default = 12, Min = 4, Max = 20, Rounding = 0, Increment = 1, Suffix = " studs",
    })
    AutoBlockDep:SetupDependencies({ { Toggles.AutoTradeTgl, true } })

    Toggles.AutoBlockTgl:OnChanged(function()
        autoblock_enabled = Toggles.AutoBlockTgl.Value
    end)
    Options.AutoBlockRange:OnChanged(function()
        autoblock_range = Options.AutoBlockRange.Value
    end)

    -- Universal ABA enemy-M1 animation IDs (captured via discovery).
    -- The first 4 are normal M1s, the last is the combo-finisher (length 1.00)
    -- which BREAKS block — we exclude it from auto-block but allow auto-trade
    -- to still respond if the user is already manually blocking.
    local ENEMY_M1_ANIM_IDS = {
        -- Fists
        ["rbxassetid://1461128166"] = true,
        ["rbxassetid://1461128859"] = true,
        ["rbxassetid://1461136273"] = true,
        ["rbxassetid://1461136875"] = true,
        -- Sword
        ["rbxassetid://1470422387"] = true,
        ["rbxassetid://1470439852"] = true,
        ["rbxassetid://1470449816"] = true,
        ["rbxassetid://1470447472"] = true,
    }
    local ENEMY_M1_FINISHER_IDS = {
        ["rbxassetid://1461137417"] = true, -- Fists finisher
        ["rbxassetid://1470454728"] = true, -- Sword finisher
    }

    -- Standing Downslam — toggle gate + Hold-only keybind. While the toggle is
    -- on, every press of the bound key fires an air-M1 once.
    local function fireDownslam()
        if not inputRemote then refreshInputRemote() end
        if not inputRemote then return end
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        inputRemote:FireServer("M1", {
            air = true,
            skeyreal = false,
            skeydown = true,
            mousehit = Camera.CFrame,
            md = hum and hum.MoveDirection or V3(0, 0, 0),
        })
    end

    CombatGroup:AddHotkey("DownslamM1Hotkey", {
        Text = "Standing Downslam",
        Default = "None",
        Callback = function() fireDownslam() end,
    })

    -- Animation discovery — logs animations played on every other player for 10s.
    CombatGroup:AddButton({
        Text = "Capture Enemy Anims 10s",
        Tooltip = "Logs Animator.AnimationPlayed on all other players for 10s. Have an enemy spam M1 during the window.",
        Func = function() _G.__abp_anim_capture_request = true end,
    })

    task.spawn(function()
        local Players = game:GetService("Players")
        local active, untilT, buf = false, 0, nil
        local bound = setmetatable({}, { __mode = "k" })

        local function bindChar(label, char)
            if not char or bound[char] then return end
            bound[char] = true
            task.spawn(function()
                local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
                local animator = hum and (hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 5))
                if not animator then return end
                animator.AnimationPlayed:Connect(function(track)
                    local anim = track.Animation
                    local id   = anim and anim.AnimationId
                    if not id then return end

                    -- Discovery capture (button-driven).
                    if active then
                        buf[#buf+1] = string.format("[%6.3fs] %s | id=%s name=%s len=%.2f",
                            tick() - (untilT - 10), label,
                            tostring(id), tostring(anim.Name), tostring(track.Length))
                    end

                    -- Live trigger: only on real M1 anims (or finishers, which
                    -- only act to cancel pending trades — never trigger one).
                    local isM1       = ENEMY_M1_ANIM_IDS[id]
                    local isFinisher = ENEMY_M1_FINISHER_IDS[id]
                    if not (isM1 or isFinisher) then return end
                    if not autotrade_enabled then return end

                    local myChar = LP.Character
                    local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
                    local enHrp  = char:FindFirstChild("HumanoidRootPart")
                    if not (myHrp and enHrp) then return end

                    -- Self-cast guard: never act if we're mid-skill.
                    if myChar:FindFirstChild("Action") then return end

                    -- Finisher: cancel any pending schedule and bail (regardless
                    -- of range — finishers are dangerous if they close in).
                    if isFinisher then
                        autotrade_pendingTok = autotrade_pendingTok + 1
                        return
                    end

                    -- Track anim arrival regardless of range so combo detection
                    -- works even when the enemy is dash-spamming from outside.
                    autotrade_animsSinceTrade = autotrade_animsSinceTrade + 1
                    autotrade_lastAnimAt = tick()

                    -- Block-arming: only raise block when enemy is actually
                    -- in range. Out-of-range anims don't auto-block (dash
                    -- watcher below handles cross-in). Suppressed briefly
                    -- after a trade so we don't re-block immediately after
                    -- our M1.
                    local dist = (enHrp.Position - myHrp.Position).Magnitude
                    local armRadius = math.min(autoblock_range * 2.5, 35)
                    local POST_TRADE_BLOCK_LOCKOUT = 0.6
                    local postTradeQuiet = (tick() - autotrade_lastAt) > POST_TRADE_BLOCK_LOCKOUT
                    -- Closing-speed helper: returns true if enemy is moving
                    -- toward us fast enough to be a dash threat.
                    local function isClosingFast(eh, mh)
                        if not (eh and mh) then return false end
                        local toMe = mh.Position - eh.Position
                        local toMeFlat = V3(toMe.X, 0, toMe.Z)
                        local mag = toMeFlat.Magnitude
                        if mag <= 0.1 then return false end
                        local v = eh.AssemblyLinearVelocity
                        local vFlat = V3(v.X, 0, v.Z)
                        return vFlat:Dot(toMeFlat / mag) > 12 -- studs/sec
                    end

                    if postTradeQuiet
                        and (not UIS:IsKeyDown(Enum.KeyCode.F))
                        and autoblock_enabled and not autotrade_running then
                        if dist <= autoblock_range then
                            eagerBlockOn()
                        elseif dist <= armRadius and isClosingFast(enHrp, myHrp) then
                            eagerBlockOn(0.4)
                        elseif dist <= armRadius then
                            -- Velocity not yet replicated: poll for a few
                            -- frames and raise block as soon as the closing
                            -- speed crosses the threshold or they cross in.
                            local snapEn, snapMy = enHrp, myHrp
                            local deadline = tick() + 0.25
                            local conn
                            conn = RunService.Heartbeat:Connect(function()
                                if tick() >= deadline
                                    or not (snapEn.Parent and snapMy.Parent)
                                    or autotrade_running
                                    or (tick() - autotrade_lastAt) <= POST_TRADE_BLOCK_LOCKOUT then
                                    conn:Disconnect(); return
                                end
                                local d = (snapEn.Position - snapMy.Position).Magnitude
                                if d <= autoblock_range or isClosingFast(snapEn, snapMy) then
                                    conn:Disconnect()
                                    eagerBlockOn(0.4)
                                end
                            end)
                        end
                    end

                    -- Trade decision (anim-based fallback in case TagReplicate
                    -- doesn't fire for blocked hits). Combo-aware: 1st hit
                    -- defers; 2nd hit within combo gap fires immediately.
                    local function armTrade()
                        local fDown = UIS:IsKeyDown(Enum.KeyCode.F)
                        local needRaise = (not fDown) and autoblock_enabled
                        if not (fDown or needRaise) then return end
                        if (tick() - autotrade_lastAt) <= 0.6 then return end
                        if autotrade_running then return end
                        local count = autotrade_animsSinceTrade
                        if count >= 2 then
                            -- Combo confirmed at hit #2's anim. Hit #2's
                            -- impact lands ~0.25s after the anim, so we
                            -- need a longer pre-impact wait here so block
                            -- stays up through hit #2 before BlockOff+M1.
                            autotrade_pendingTok = autotrade_pendingTok + 1
                            runTrade(needRaise, myChar, 0.25, 0.015)
                        else
                            autotrade_pendingTok = autotrade_pendingTok + 1
                            local myTok = autotrade_pendingTok
                            local snapChar = myChar
                            local snapNeedRaise = needRaise
                            task.delay(autotrade_comboGap + 0.05, function()
                                if myTok ~= autotrade_pendingTok then return end
                                if not autotrade_enabled then return end
                                if autotrade_running then return end
                                if (tick() - autotrade_lastAt) <= 0.6 then return end
                                runTrade(snapNeedRaise, snapChar)
                            end)
                        end
                    end
                    if dist <= autoblock_range then
                        armTrade()
                    elseif dist <= armRadius then
                        -- Dash: poll for cross-in. On cross-in, raise block
                        -- and arm trade. Block is NOT raised pre-emptively
                        -- so out-of-range anims don't waste it.
                        local deadline = tick() + autotrade_comboGap + 0.1
                        local conn
                        conn = RunService.Heartbeat:Connect(function()
                            if tick() >= deadline
                                or not (myChar and myChar.Parent and char.Parent) then
                                conn:Disconnect(); return
                            end
                            local h1 = myChar:FindFirstChild("HumanoidRootPart")
                            local h2 = char:FindFirstChild("HumanoidRootPart")
                            if h1 and h2 and (h2.Position - h1.Position).Magnitude <= autoblock_range then
                                conn:Disconnect()
                                if (not UIS:IsKeyDown(Enum.KeyCode.F))
                                    and autoblock_enabled and not autotrade_running
                                    and (tick() - autotrade_lastAt) > POST_TRADE_BLOCK_LOCKOUT then
                                    eagerBlockOn()
                                end
                                armTrade()
                            end
                        end)
                    end
                end)
            end)
        end

        -- Players (real opponents).
        local function bindPlayer(plr)
            if plr == LP then return end
            if plr.Character then bindChar(plr.Name, plr.Character) end
            plr.CharacterAdded:Connect(function(c) bindChar(plr.Name, c) end)
        end
        for _, p in ipairs(Players:GetPlayers()) do bindPlayer(p) end
        Players.PlayerAdded:Connect(bindPlayer)

        -- NPCs / dummies under workspace.Live.
        local function maybeBindLive(inst)
            if not inst:IsA("Model") then return end
            -- Skip our own character (also lives under Live).
            if inst == LP.Character then return end
            -- Bind any Model with a Humanoid (Attack Dummy, mobs, etc).
            if inst:FindFirstChildOfClass("Humanoid") then
                bindChar("NPC:" .. inst.Name, inst)
            else
                -- Humanoid may be added later; wait a moment.
                task.delay(0.5, function()
                    if inst.Parent and inst:FindFirstChildOfClass("Humanoid") then
                        bindChar("NPC:" .. inst.Name, inst)
                    end
                end)
            end
        end
        local Live = workspace:FindFirstChild("Live")
        if Live then
            for _, c in ipairs(Live:GetChildren()) do maybeBindLive(c) end
            Live.ChildAdded:Connect(maybeBindLive)
        else
            workspace.ChildAdded:Connect(function(c)
                if c.Name == "Live" then
                    for _, k in ipairs(c:GetChildren()) do maybeBindLive(k) end
                    c.ChildAdded:Connect(maybeBindLive)
                end
            end)
        end

        while not Library.Unloaded do
            if _G.__abp_anim_capture_request then
                _G.__abp_anim_capture_request = nil
                buf = {}; active = true; untilT = tick() + 10
                print("[ABP-ANIM] capturing 10s...")
            end
            if active and tick() >= untilT then
                active = false
                local txt = table.concat(buf, "\n")
                local copyFn = rawget(getfenv(), "setclipboard") or rawget(getfenv(), "toclipboard")
                local copied = false
                if copyFn then copied = pcall(copyFn, txt) end
                print(string.format("\n========== ABP ANIM DUMP (%d entries, clipboard=%s) ==========\n%s\n========== END ==========",
                    #buf, tostring(copied), txt))
                buf = nil
            end
            task.wait(0.1)
        end
    end)

    -- Self-cast guard: own casts add the `Action` folder well before any
    -- TagReplicate; enemy stuns add Action and the tag ~simultaneously. If
    -- Action has been present for >120 ms when a TagReplicate arrives, it's
    -- our own cast — ignore.
    local function trackActionFolder(char)
        if not char then return end
        local function bind(folder)
            if folder.Name == "Action" then nostun_actionAddedAt = tick() end
        end
        for _, c in ipairs(char:GetChildren()) do bind(c) end
        char.ChildAdded:Connect(bind)
    end
    trackActionFolder(LP.Character)
    LP.CharacterAdded:Connect(trackActionFolder)

    task.spawn(function()
        local RS = game:GetService("ReplicatedStorage")
        local TS = RS:WaitForChild("TagSystem2", 30)
        local TR = TS and TS:WaitForChild("TagReplicate", 30)
        if not (TR and TR:IsA("RemoteEvent")) then return end
        TR.OnClientEvent:Connect(function(payload, target)
            local myChar = LP.Character
            if target ~= myChar or type(payload) ~= "table" then return end
            local action = myChar and myChar:FindFirstChild("Action")
            local actionStale = action and (tick() - nostun_actionAddedAt) > 0.12

            for _, entry in pairs(payload) do
                if type(entry) == "table" then
                    local name = entry.TrueName
                    local isEnemyTag = STUN_TAG_NAMES[name]
                        and (name ~= "creator" or entry.TrueValue ~= myChar)

                    if isEnemyTag then
                        -- No-stun trigger (skip if it's our own cast).
                        if not actionStale then
                            nostun_lastTagAt = tick()
                        end

                        -- ============================================================
                        -- AUTO TRADE — event-driven trigger. ABA fires this the
                        -- exact moment a hit lands on us (blocked or not), so we
                        -- can M1 back without any impact-time guessing.
                        -- ============================================================
                        if autotrade_enabled
                            and not autotrade_running
                            and not actionStale
                            and (tick() - autotrade_lastAt) > 0.6 then
                            local fDown = UIS:IsKeyDown(Enum.KeyCode.F)
                            local needRaise = (not fDown) and autoblock_enabled
                            -- Only trade if we were actually blocking (manual F
                            -- or auto-block currently holding via eagerBlockOn).
                            if fDown or (needRaise and autoblock_holding) then
                                autotrade_hitsSinceTrade = autotrade_hitsSinceTrade + 1
                                if autotrade_hitsSinceTrade >= 2 then
                                    -- Combo: blocked 2+ hits, fire trade now.
                                    -- Block stayed up the whole time.
                                    autotrade_pendingTok = autotrade_pendingTok + 1
                                    runTrade(needRaise, myChar, 0, 0.015)
                                else
                                    -- Single hit so far: schedule deferred trade.
                                    -- If a 2nd hit arrives within combo gap, the
                                    -- combo branch above pre-empts this schedule.
                                    autotrade_pendingTok = autotrade_pendingTok + 1
                                    local myTok        = autotrade_pendingTok
                                    local snapChar     = myChar
                                    local snapNeedRaise = needRaise
                                    task.delay(autotrade_comboGap + 0.05, function()
                                        if myTok ~= autotrade_pendingTok then return end
                                        if not autotrade_enabled then return end
                                        if autotrade_running then return end
                                        if (tick() - autotrade_lastAt) <= 0.6 then return end
                                        runTrade(snapNeedRaise, snapChar, 0, 0.015)
                                    end)
                                end
                            end
                        end
                        return
                    end
                end
            end
        end)
    end)

    -- Bind LAST so we run AFTER the LocalCharacterScript's PreRender writes.
    RunService:BindToRenderStep("LegitNoStunWS", Enum.RenderPriority.Last.Value, function()
        if not nostun_enabled then return end
        if (tick() - nostun_lastTagAt) >= 0.6 then return end

        local char = LP.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if not (hum and hum.Health > 0 and hum.WalkSpeed == 5) then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        -- Bail if any knockback/fling BV is active — let the game's push play.
        for _, d in ipairs(hrp:GetDescendants()) do
            if d:IsA("BodyVelocity") then
                local pn = d.Parent and d.Parent.Name or ""
                if pn == "StunBV" or pn == "UpFling" or pn == "DownerFling"
                    or d.Name == "StunBV" or d.Name == "UpFling" or d.Name == "DownerFling" then
                    return
                end
            end
        end

        -- Throw-inertia bail: if we're already moving faster horizontally than
        -- walkout * 1.4, we're being thrown / sliding under inertia from a
        -- combo finisher — don't clamp it. Squared compare avoids a sqrt.
        local cur = hrp.AssemblyLinearVelocity
        local thresh = nostun_walkout * 1.4
        if (cur.X * cur.X + cur.Z * cur.Z) > (thresh * thresh) then return end

        -- Read WASD directly (PlayerModule input is suppressed during stun).
        local x, z = 0, 0
        if UIS:IsKeyDown(Enum.KeyCode.W) then z = z - 1 end
        if UIS:IsKeyDown(Enum.KeyCode.S) then z = z + 1 end
        if UIS:IsKeyDown(Enum.KeyCode.A) then x = x - 1 end
        if UIS:IsKeyDown(Enum.KeyCode.D) then x = x + 1 end
        if x == 0 and z == 0 then return end

        local cf  = Camera.CFrame
        local fwd = V3(cf.LookVector.X, 0, cf.LookVector.Z)
        if fwd.Magnitude < 0.001 then return end
        local rgt = V3(cf.RightVector.X, 0, cf.RightVector.Z)
        local dir = (rgt.Unit * x + fwd.Unit * (-z)).Unit
        hrp.AssemblyLinearVelocity = V3(dir.X * nostun_walkout, cur.Y, dir.Z * nostun_walkout)
    end)


    -- Exploits: Characters 1
    local ProjGroup = Tabs.Exploits:AddLeftGroupbox("Characters 1")

    ProjGroup:AddToggle("ProjTpTgl", {
        Text = "Yosuke Urameshi Spirit Gun",
        Default = false,
    })

    ProjGroup:AddToggle("ProjTpIncludeLive", {
        Text = "Hit Dummys",
        Default = false,
    })

    Toggles.ProjTpTgl:OnChanged(function()
        proj_enabled = Toggles.ProjTpTgl.Value
        if proj_enabled then startProjectileWatcher() else stopProjectileWatcher() end
    end)

    -- ============================================================================
    -- HITBOX EXPANDER
    -- Inflates client-owned projectiles (BaseParts spawned in workspace.Thrown near
    -- the LocalPlayer) so their Touched/Region hit detection catches more targets.
    -- ============================================================================
    ProjGroup:AddToggle("HitboxExpTgl", {
        Text = "Projectile Hitbox Expander",
        Default = false,
    })

    ProjGroup:AddSlider("HitboxExpSize", {
        Text = "Hitbox Size",
        Default = 10, Min = 3, Max = 2000, Rounding = 1, Increment = 1, Suffix = " studs",
    })

    local hitbox_enabled = false
    local hitbox_size    = 10
    local hitbox_tracked = {}        -- [part] = { size=Vector3, canCollide=bool, conn=RBXScriptConnection }
    local hitbox_conn    = nil
    local HITBOX_CLAIM_RANGE_SQ = 60 * 60

    local function hitboxRestore(part)
        local s = hitbox_tracked[part]
        if not s then return end
        hitbox_tracked[part] = nil
        if s.conn then pcall(function() s.conn:Disconnect() end) end
        if part and part.Parent then
            pcall(function()
                part.Size = s.size
                part.CanCollide = s.canCollide
            end)
        end
    end

    local function hitboxApply(part)
        if not hitbox_enabled or hitbox_tracked[part] then return end
        if not part:IsA("BasePart") then return end
        local myChar = LP.Character
        local myHrp  = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHrp then return end
        if (part.Position - myHrp.Position).Magnitude ^ 2 > HITBOX_CLAIM_RANGE_SQ then return end
        local s = {
            size       = part.Size,
            canCollide = part.CanCollide,
        }
        hitbox_tracked[part] = s
        pcall(function()
            part.Size       = V3(hitbox_size, hitbox_size, hitbox_size)
            part.CanCollide = false
        end)
        s.conn = part.AncestryChanged:Connect(function(_, parent)
            if not parent then hitboxRestore(part) end
        end)
    end

    local function hitboxStart()
        if hitbox_conn or not ThrownFolder then return end
        hitbox_conn = ThrownFolder.ChildAdded:Connect(function(c)
            if hitbox_enabled then hitboxApply(c) end
        end)
        for _, c in ipairs(ThrownFolder:GetChildren()) do hitboxApply(c) end
    end

    local function hitboxStop()
        if hitbox_conn then hitbox_conn:Disconnect(); hitbox_conn = nil end
        for p in pairs(hitbox_tracked) do hitboxRestore(p) end
    end

    Toggles.HitboxExpTgl:OnChanged(function()
        hitbox_enabled = Toggles.HitboxExpTgl.Value
        if hitbox_enabled then hitboxStart() else hitboxStop() end
    end)

    Options.HitboxExpSize:OnChanged(function()
        hitbox_size = Options.HitboxExpSize.Value
        if not hitbox_enabled then return end
        local v = V3(hitbox_size, hitbox_size, hitbox_size)
        for p in pairs(hitbox_tracked) do
            if p.Parent then pcall(function() p.Size = v end) end
        end
    end)

    -- MACROS TAB
    local QTEGroup = Tabs.Macros:AddLeftGroupbox("Auto QTE")

    QTEGroup:AddToggle("Nanami_Tgl", {
        Text = "Auto Nanami",
        Default = false,
    })

    QTEGroup:AddToggle("Koku_Tgl", {
        Text = "Auto Kokushibo",
        Default = false,
    })

    QTEGroup:AddToggle("Camera_Tgl", {
        Text = "Auto Camera Timing",
        Default = false,
    })

    Toggles.Nanami_Tgl:OnChanged(function() status_nanami = Toggles.Nanami_Tgl.Value end)
    Toggles.Koku_Tgl:OnChanged(function() status_kokushibo = Toggles.Koku_Tgl.Value end)
    Toggles.Camera_Tgl:OnChanged(function() status_camera = Toggles.Camera_Tgl.Value end)

    -- ESP TAB
    local EspGroup = Tabs.Esp:AddLeftGroupbox("ESP")

    EspGroup:AddToggle("EspMasterTgl", {
        Text = "Enable ESP",
        Default = false,
    })

    EspGroup:AddDropdown("EspElements", {
        Text = "ESP Elements",
        Values = { "Box", "Name", "HP Bar", "Mode Bar", "Mode %" },
        Default = {},
        Multi = true,
    })

    Toggles.EspMasterTgl:OnChanged(function()
        status_esp = Toggles.EspMasterTgl.Value
        if not status_esp then for _,d in pairs(espCache) do hideEsp(d) end end
    end)

    local function updateEspFlags()
        local sel = Options.EspElements.Value
        local newBox = sel["Box"] or false
        local newName = sel["Name"] or false
        local newHp = sel["HP Bar"] or false
        local newMode = sel["Mode Bar"] or false
        local newPct = sel["Mode %"] or false

        if status_esp_box and not newBox then for _,d in pairs(espCache) do d.box.Visible = false end end
        if status_esp_name and not newName then for _,d in pairs(espCache) do d.name.Visible = false end end
        if status_esp_hpbar and not newHp then for _,d in pairs(espCache) do hideBar(d.hp) end end
        if status_esp_modebar and not newMode then for _,d in pairs(espCache) do hideBar(d.mode) end end
        if status_esp_modepct and not newPct then for _,d in pairs(espCache) do d.pct.Visible = false end end

        status_esp_box = newBox
        status_esp_name = newName
        status_esp_hpbar = newHp
        status_esp_modebar = newMode
        status_esp_modepct = newPct
    end

    Options.EspElements:OnChanged(function()
        updateEspFlags()
    end)


    -- ============================================================================
    --                          MAIN RENDER LOOP
    -- ============================================================================

    local RenderConnection = RunService.RenderStepped:Connect(function()
        -- Rebuild player map once per frame (shared by ESP + cam lock + tween)
        rebuildPlayerMap()

        -- Viewport center (cached once per frame)
        local vp = Camera.ViewportSize
        local vpCenter = V2(vp.X * 0.5, vp.Y * 0.5)

        -- FOV circles
        FOVCircle.Visible = Toggles.ShowFOV.Value
        FOVCircle.Radius = Options.FOVRadius.Value
        FOVCircle.Position = vpCenter

        CamLockFOVCircle.Visible = Toggles.ShowCamLockFov.Value
        CamLockFOVCircle.Radius = Options.CamLockFovSize.Value
        CamLockFOVCircle.Position = vpCenter

        -- Camera lock
        if cam_lock_enabled then
            if not CamLockTarget or not CamLockTarget.Parent or (CamLockTarget:FindFirstChild("Humanoid") and CamLockTarget.Humanoid.Health <= 0) then
                CamLockTarget = findClosestTarget(Options.CamLockFovSize.Value, Options.CamLockRange.Value)
            end
            if CamLockTarget then
                local hrp = CamLockTarget:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local alpha = clamp(pow(0.5, Options.CamLockSmoothness.Value / 15), 0.005, 1)
                    Camera.CFrame = Camera.CFrame:Lerp(CFrame.lookAt(Camera.CFrame.Position, hrp.Position), alpha)
                end
            end
        else CamLockTarget = nil end

        -- ESP
        if status_esp then
            local live = WS:FindFirstChild("Live")
            if live then
                local lc = LP.Character
                local active = {}
                for _,m in ipairs(live:GetChildren()) do
                    if m:IsA("Model") and m ~= lc and pMap[m] then
                        active[m] = true
                        local d = getEspCache(m)
                        local hrp = m:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            local top, onT = Camera:WorldToViewportPoint(hrp.Position + V3(0, 2.5, 0))
                            local bot, onB = Camera:WorldToViewportPoint(hrp.Position - V3(0, 3.0, 0))
                        if onT and onB then
                            local rawH = bot.Y - top.Y
                            local padY = rawH * 0.05
                            local h  = rawH + padY * 2
                            local w  = h * 0.75
                            local mid, _ = Camera:WorldToViewportPoint(hrp.Position)
                            local cx = mid.X
                            local adjY1 = top.Y - padY
                            local newX1 = cx - (w * 0.5)

                            -- Box
                            if status_esp_box then
                                d.box.Size,d.box.Position,d.box.Visible = V2(w,h),V2(newX1,adjY1),true
                            else d.box.Visible = false end

                            -- Name
                            if status_esp_name then
                                d.name.Text,d.name.Position,d.name.Visible = m.Name,V2(cx,adjY1-16),true
                            else d.name.Visible = false end

                            -- HP bar (vertical, left side)
                            if status_esp_hpbar then
                                local hum = m:FindFirstChildOfClass("Humanoid")
                                if hum and hum.MaxHealth > 0 then
                                    local hpPct = clamp(hum.Health / hum.MaxHealth, 0, 1)
                                    drawVBar(d.hp, newX1 - BAR_T - BAR_GAP, adjY1, BAR_T, h, hpPct)
                                else hideBar(d.hp) end
                            else hideBar(d.hp) end

                            -- Mode bar + Mode %
                            local plr = pMap[m]
                            local ch = plr and plr:FindFirstChild("Charge")
                            local boxBottom = adjY1 + h
                            if ch and ch.MaxValue > 0 then
                                local modePct = clamp(ch.Value / ch.MaxValue, 0, 1)
                                if status_esp_modebar then
                                    drawHBar(d.mode, newX1, boxBottom + BAR_GAP, w, BAR_T, modePct)
                                else hideBar(d.mode) end
                                if status_esp_modepct then
                                    d.pct.Text,d.pct.Position,d.pct.Visible = fmt("%d%%",floor(modePct*100)),V2(cx,boxBottom+BAR_GAP+BAR_T+TXT_GAP),true
                                else d.pct.Visible = false end
                            else
                                hideBar(d.mode); d.pct.Visible = false
                            end
                        else hideEsp(d) end
                        else hideEsp(d) end
                    end
                end
                for k in pairs(espCache) do if not active[k] then cleanEsp(k) end end
            end
        end
    end)

    -- ============================================================================
    --                           GUI SETTINGS TAB
    -- ============================================================================

    local MenuGroup = Tabs["GUI Settings"]:AddLeftGroupbox("Menu")

    MenuGroup:AddButton({
        Text = "Unload",
        Func = function() Library:Unload() end,
    })

    MenuGroup:AddLabel(""):AddKeyPicker("MenuKeybind", {
        Default = "End",
        NoUI = true,
        Text = "Menu keybind",
    })

    Library.ToggleKeybind = Options.MenuKeybind

    -- ============================================================================
    --                         SAVE / THEME / UNLOAD
    -- ============================================================================

    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({ "MenuKeybind" })

    SaveManager:BuildConfigSection(Tabs["GUI Settings"])
    ThemeManager:ApplyToTab(Tabs["GUI Settings"], MenuGroup)

    Library:OnUnload(function()
        if RenderConnection then RenderConnection:Disconnect() end
        if TweenConnection then TweenConnection:Disconnect() end
        stopProjectileWatcher()
        hitboxStop()
        pcall(function() RunService:UnbindFromRenderStep("LegitNoStunWS") end)
        FOVCircle:Remove()
        CamLockFOVCircle:Remove()
        for k in pairs(espCache) do cleanEsp(k) end
        Library.Unloaded = true
    end)

    SaveManager:LoadAutoloadConfig()
    ThemeManager:LoadAutoloadTheme()
