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
    -- LEGIT NO-STUN (slow walk-out)
    -- During an M1 combo the LocalCharacterScript drops WalkSpeed to 0 (Action
    -- folder) or 5 (`creator` tag). We don't remove those — the hit reaction still
    -- plays normally, server still thinks we're stunned. We just override
    -- Humanoid.WalkSpeed every Heartbeat (which runs AFTER the script's PreRender
    -- WalkSpeed write) to the user-configured walk-out value, so we visibly drift
    -- out of the combo at a slow pace instead of being frozen.
    -- ============================================================================
    local NOSTUN_FOLDERS = { Action = true }
    local NOSTUN_TAGS    = { creator = true, WASUPFLINGED = true, GotSlammed = true }

    local nostun_enabled  = false
    local nostun_walkout  = 8

    local TagSystem2 = (function()
        local ok, m = pcall(require, game:GetService("ReplicatedStorage"):WaitForChild("TagSystem2"))
        return ok and m or nil
    end)()

    local RagePlayerGroup = Tabs.PvP:AddRightGroupbox("Survival")

    RagePlayerGroup:AddToggle("LegitNoStunTgl", {
        Text = "Legit No-Stun",
        Default = false,
        Tooltip = "Walk slowly out of M1 combos instead of being frozen.",
    })

    RagePlayerGroup:AddSlider("LegitWalkoutSpeed", {
        Text = "Walk-out Speed",
        Default = 8, Min = 4, Max = 16, Rounding = 0, Increment = 1, Suffix = " studs/s",
    })

    -- Event-driven combo flag. Updated by ChildAdded/Removed on Character and
    -- TagSystem2 TagAdded/Removed on the same. Avoids polling-window misses.
    local nostun_inCombo   = false
    local nostun_folderCnt = 0
    local nostun_tagCnt    = 0
    local function nostunRecompute() nostun_inCombo = (nostun_folderCnt + nostun_tagCnt) > 0 end

    local nostun_listeners = {}  -- list of disconnect callbacks
    local function nostunUnbindChar()
        for _, d in ipairs(nostun_listeners) do pcall(d) end
        table.clear(nostun_listeners)
        nostun_folderCnt, nostun_tagCnt = 0, 0
        nostunRecompute()
    end

    local function nostunBindChar(char)
        nostunUnbindChar()
        if not char then return end
        -- Initial folder scan.
        for _, c in ipairs(char:GetChildren()) do
            if NOSTUN_FOLDERS[c.Name] then nostun_folderCnt = nostun_folderCnt + 1 end
        end
        local addConn = char.ChildAdded:Connect(function(c)
            if NOSTUN_FOLDERS[c.Name] then
                nostun_folderCnt = nostun_folderCnt + 1
                nostunRecompute()
            end
        end)
        local remConn = char.ChildRemoved:Connect(function(c)
            if NOSTUN_FOLDERS[c.Name] then
                nostun_folderCnt = math.max(0, nostun_folderCnt - 1)
                nostunRecompute()
            end
        end)
        table.insert(nostun_listeners, function() addConn:Disconnect() end)
        table.insert(nostun_listeners, function() remConn:Disconnect() end)
        -- TagSystem2.
        if TagSystem2 then
            for name in pairs(NOSTUN_TAGS) do
                if TagSystem2:HasTag(char, name) then nostun_tagCnt = nostun_tagCnt + 1 end
            end
            local tagAdd = TagSystem2.TagAdded(char, function(tag)
                if NOSTUN_TAGS[tag.Name] then
                    nostun_tagCnt = nostun_tagCnt + 1
                    nostunRecompute()
                end
            end)
            local tagRem = TagSystem2.TagRemoved(char, function(tag)
                if NOSTUN_TAGS[tag.Name] then
                    nostun_tagCnt = math.max(0, nostun_tagCnt - 1)
                    nostunRecompute()
                end
            end)
            table.insert(nostun_listeners, function()
                pcall(function() TagSystem2.AddedDisconnect(tagAdd) end)
                pcall(function() TagSystem2.AddedDisconnect(tagRem) end)
            end)
        end
        nostunRecompute()
    end

    nostunBindChar(LP.Character)
    LP.CharacterAdded:Connect(nostunBindChar)

    -- Bind LAST so we run AFTER the LocalCharacterScript's PreRender hook that
    -- writes WalkSpeed = 0/5 during combo. Otherwise our write gets clobbered
    -- before physics sees it.
    local nostun_debug = false
    local nostun_lastPrint = 0
    RunService:BindToRenderStep("LegitNoStunWS", Enum.RenderPriority.Last.Value, function()
        if not nostun_enabled then return end
        local char = LP.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not (char and hum and hum.Health > 0) then return end
        if nostun_inCombo then
            hum.WalkSpeed = nostun_walkout
            if hum.JumpPower < 35 then hum.JumpPower = 35 end
        end
        if nostun_debug and tick() - nostun_lastPrint > 0.1 then
            nostun_lastPrint = tick()
            local movers = {}
            if hrp then
                for _, c in ipairs(hrp:GetChildren()) do
                    if c:IsA("BodyMover") or c:IsA("Constraint") or c:IsA("VectorForce") or c:IsA("LinearVelocity") or c:IsA("AlignPosition") or c:IsA("BodyVelocity") or c:IsA("BodyPosition") then
                        movers[#movers+1] = c.ClassName .. ":" .. c.Name .. " v=" .. tostring(c:IsA("BodyVelocity") and c.Velocity or "")
                    end
                end
            end
            print(string.format("[NS] inCombo=%s (f=%d t=%d) WS=%.1f JP=%.1f PS=%s movers=[%s]",
                tostring(nostun_inCombo), nostun_folderCnt, nostun_tagCnt,
                hum.WalkSpeed, hum.JumpPower,
                tostring(hum.PlatformStand), table.concat(movers, ",")))
        end
    end)
    RagePlayerGroup:AddToggle("LegitNoStunDbg", {
        Text = "No-Stun Debug Print",
        Default = false,
    })
    Toggles.LegitNoStunDbg:OnChanged(function()
        nostun_debug = Toggles.LegitNoStunDbg.Value
    end)

    Toggles.LegitNoStunTgl:OnChanged(function()
        nostun_enabled = Toggles.LegitNoStunTgl.Value
    end)

    Options.LegitWalkoutSpeed:OnChanged(function()
        nostun_walkout = Options.LegitWalkoutSpeed.Value
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
