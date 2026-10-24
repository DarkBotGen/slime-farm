-- Slime + shiny + flower farm. F6 toggles everything; F7 toggles collection.
-- One attack per Heartbeat, with no added attack delay. Server cooldown still applies.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local Tags = game:GetService("CollectionService")
local VirtualUser = game:GetService("VirtualUser")
local player = Players.LocalPlayer
local loadModule: any = require
local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
assert(shared, "Shared folder missing")
local controllers = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Controllers")
local hotbar = loadModule(controllers:WaitForChild("HotbarController"))
local remotes = loadModule(shared:WaitForChild("Remotes"))
local config = loadModule(shared:WaitForChild("Config"))
local swing = remotes.get(remotes.RequestSwing)
local harvest = remotes.get(remotes.RequestHarvest)
local env = getgenv()
if env.SlimeFarm and env.SlimeFarm.stop then env.SlimeFarm.stop() end
local farm: any = {
    enabled = true, collect = true, attacks = 0, kills = 0,
    flowers = 0, shinies = 0, target = nil, lastError = nil,
    mode = "starting", height = -8, hubReturns = 0, autoHub = true,
    antiAfk = true, antiAfkEvents = 0, antiAfkError = nil
}
env.SlimeFarm = farm
local connections = {}
local enemies = {}
local flowers = {}
local shinies = {}
local retryAfter = setmetatable({}, {__mode = "k"})
local stopped = false
local folder = nil
local trackedCharacter = nil
local origin = nil
local collection = nil
local lastEquip = 0
local previousHP = nil
local lastDamageAt = 0
local lastProgressAt = 0
local blocked = setmetatable({}, {__mode = "k"})
local targetHealthConnection = nil

local portal = nil
local portalScanAt = 0
local portalStartedAt = 0
local returningToHub = false
local lastWarningAt = 0
local function inHub(position)
    local relative = position - config.Hub.Origin
    local half = config.Hub.SizeStuds * 0.5
    return math.abs(relative.X) <= half.X + 40
        and math.abs(relative.Z) <= half.Z + 40
        and math.abs(relative.Y) <= 160
end
local function returnToHub(root, now)
    if inHub(root.Position) then
        if returningToHub then
            farm.hubReturns = farm.hubReturns + 1
            farm.target = nil
            collection = nil
            origin = root.CFrame
        end
        returningToHub = false
        portal = nil
        return true
    end
    if not farm.autoHub then return false end
    returningToHub = true
    farm.target = nil
    collection = nil
    farm.mode = "finding HUB portal"
    if now - portalScanAt >= 0.5 or not portal or not portal:IsDescendantOf(workspace) then
        portalScanAt = now
        local bestDistance = math.huge
        portal = nil
        for _, island in ipairs(workspace:GetChildren()) do
            if typeof(island:GetAttribute("IslandOrigin")) == "Vector3" then
                for _, candidate in ipairs(island:GetChildren()) do
                    if candidate.Name == "HUB" or candidate:GetAttribute("PortalRotation") ~= nil then
                        local touch = candidate:FindFirstChild("TouchPart", true)
                        if touch and touch:IsA("BasePart") then
                            local distance = (touch.Position - root.Position).Magnitude
                            if distance < bestDistance then
                                portal, bestDistance = touch, distance
                            end
                        end
                    end
                end
            end
        end
    end
    if portal then
        farm.mode = "entering HUB portal"
        if now - portalStartedAt > 4 then portalStartedAt = now end
        -- Briefly leave the trigger between attempts to generate a fresh touch.
        local offset = now - portalStartedAt < 0.15 and portal.CFrame.LookVector * 6 or Vector3.zero
        if not root.Anchored then
            root.CFrame = portal.CFrame + offset
            root.AssemblyLinearVelocity = Vector3.zero
        end
    end
    return false
end
local function connect(signal, callback)
    local c = signal:Connect(callback)
    table.insert(connections, c)
    return c
end
-- Uses each client's own idle event; no focused-window or OS input dependency.
-- Remains active while F6 pauses farming and disconnects with farm.stop().
connect(player.Idled, function()
    if stopped or not farm.antiAfk then return end
    local ok, message = pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
    if ok then
        farm.antiAfkEvents = farm.antiAfkEvents + 1
        farm.antiAfkError = nil
    else
        farm.antiAfkError = tostring(message)
        warn("Anti-AFK input failed: " .. tostring(message))
    end
end)
local function health(part)
    if not part.Parent then return 0 end
    local gui = part:FindFirstChild("Health")
    local bar = gui and gui:FindFirstChild("Bar")
    return bar and bar.Size.X.Scale or 1
end
local function validSlime(part)
    return part:IsA("BasePart") and part.Parent == folder
        and string.find(string.lower(part.Name), "slime") ~= nil
        and part.Position.Y > 0 and health(part) > 0
end
local slimePriority = {OrangeSlime = 1, PinkSlime = 2, BlueSlime = 3, GreenSlime = 4}
local function selectTarget(root, now)
    local best, score = nil, math.huge
    for candidate in pairs(enemies) do
        if validSlime(candidate) and (blocked[candidate] or 0) <= now then
            local def = config.Enemy.Enemies[candidate:GetAttribute("EnemyId")]
            local remaining = health(candidate) * (def and def.hp or 150)
            local distance = (candidate.Position - root.Position).Magnitude
            local priority = slimePriority[candidate:GetAttribute("EnemyId")] or 5
            local cost = priority * 1000000 + remaining + distance * 0.015
            if cost < score then best, score = candidate, cost end
        end
    end
    farm.target = best
    if targetHealthConnection then targetHealthConnection:Disconnect();targetHealthConnection=nil end
    local hpGui=best and best:FindFirstChild("Health")
    local hpBar=hpGui and hpGui:FindFirstChild("Bar")
    if hpBar then
        targetHealthConnection=hpBar:GetPropertyChangedSignal("Size"):Connect(function()
            if farm.target==best and health(best)<=0 and farm.enabled and not farm.transferBusy then
                farm.kills=farm.kills+1
                local character=player.Character
                local nextRoot=character and character:FindFirstChild("HumanoidRootPart")
                if nextRoot then selectTarget(nextRoot,os.clock()) end
            end
        end)
    end
    previousHP = best and health(best) or nil
    lastProgressAt = now
    farm.height = -8
    return best
end
local function registerFlower(part)
    if part:IsA("BasePart") then flowers[part] = true end
end
local function registerShiny(prompt)
    local parent = prompt.Parent
    if prompt:IsA("ProximityPrompt") and parent and parent:IsA("BasePart")
        and parent:GetAttribute("ShinyPiece") then shinies[prompt] = true end
end
for _,part in ipairs(Tags:GetTagged("Flower")) do registerFlower(part) end
for _,prompt in ipairs(Tags:GetTagged("AbovePrompt")) do registerShiny(prompt) end
connect(Tags:GetInstanceAddedSignal("Flower"), registerFlower)
connect(Tags:GetInstanceRemovedSignal("Flower"), function(part) flowers[part] = nil end)
connect(Tags:GetInstanceAddedSignal("AbovePrompt"), registerShiny)
connect(Tags:GetInstanceRemovedSignal("AbovePrompt"), function(prompt) shinies[prompt] = nil end)
local function attachFolder(newFolder)
    folder = newFolder
    table.clear(enemies)
    for _,part in ipairs(folder:GetChildren()) do enemies[part] = true end
    connect(folder.ChildAdded, function(part)
        enemies[part]=true
        if farm.enabled and not farm.transferBusy and validSlime(part) then
            local current=farm.target
            local nextPriority=slimePriority[part:GetAttribute("EnemyId")] or 5
            local currentPriority=current and (slimePriority[current:GetAttribute("EnemyId")] or 5) or math.huge
            if not current or not validSlime(current) or nextPriority<currentPriority then
                local character=player.Character
                local root=character and character:FindFirstChild("HumanoidRootPart")
                if root then selectTarget(root,os.clock()) end
            end
        end
    end)
    connect(folder.ChildRemoved, function(part)
        enemies[part] = nil
        if farm.target == part then
            farm.kills = farm.kills + 1
            farm.target = nil
            local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if root and farm.enabled then selectTarget(root, os.clock()) end
        end
    end)
end
local function nextCollection(root, now)
    local best, cost = nil, math.huge
    for prompt in pairs(shinies) do
        local part = prompt.Parent
        if part and prompt:IsDescendantOf(workspace) and inHub(part.Position) and prompt.Enabled
            and (retryAfter[prompt] or 0) <= now then
            local distance = (part.Position - root.Position).Magnitude
            if distance < cost then
                best = {kind = "shiny", object = prompt, part = part}
                cost = distance
            end
        end
    end
    if best then return best end
    for part in pairs(flowers) do
        if part:IsDescendantOf(workspace) and inHub(part.Position) and part:GetAttribute("Mature") == true
            and (retryAfter[part] or 0) <= now then
            local distance = (part.Position - root.Position).Magnitude
            if distance < cost then
                best = {kind = "flower", object = part, part = part}
                cost = distance
            end
        end
    end
    return best
end
local function release()
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root and origin and character == trackedCharacter then
        root.CFrame = origin
        root.AssemblyLinearVelocity = Vector3.zero
    end
    origin = nil
    collection = nil
    farm.target = nil
    farm.mode = "paused"
end
function farm.stop()
    if stopped then return end
    stopped = true
    if farm.telemetry then farm.telemetry.stop() end
    if farm.controller then farm.controller.stop() end
    farm.enabled = false
    if targetHealthConnection then targetHealthConnection:Disconnect();targetHealthConnection=nil end
    for _,c in ipairs(connections) do c:Disconnect() end
    release()
end
function farm.setEnabled(value)
    farm.enabled = value == true
    if not farm.enabled and not farm.transferBusy then release() end
end
connect(Input.InputBegan, function(key, processed)
    if processed or Input:GetFocusedTextBox() then return end
    if key.KeyCode == Enum.KeyCode.F6 then
        farm.setEnabled(not farm.enabled)
        print("Farm: " .. (farm.enabled and "ON" or "OFF"))
    elseif key.KeyCode == Enum.KeyCode.F7 then
        farm.collect = not farm.collect
        collection = nil
        print("Auto collection: " .. (farm.collect and "ON" or "OFF"))
    end
end)
connect(RunService.Heartbeat, function()
    if stopped then return end
    local ok, message = pcall(function()
        local now = os.clock()
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not root or not humanoid or humanoid.Health <= 0 then
            farm.mode = "waiting for respawn"
            farm.target, origin, collection = nil, nil, nil
            return
        end
        if trackedCharacter ~= character then
            trackedCharacter, origin, collection = character, nil, nil
        end
        if farm.controller and farm.controller.step(root, now) then return end
        if not farm.enabled then return end
        if not returnToHub(root, now) then return end
        if root.Anchored then farm.mode = "waiting for travel"; return end
        if not origin then origin = root.CFrame end
        do
            local hub = workspace:FindFirstChild("Hub")
            local current = hub and hub:FindFirstChild("Guardians")
            if current and current ~= folder then attachFolder(current) end
        end
        if hotbar.selected().toolSlot ~= "Weapon" and now-lastEquip>0.1 then
            lastEquip=now
            hotbar.select(1)
        end
        local target = farm.target
        if not target or not validSlime(target) then
            target = selectTarget(root, now)
        else
            local currentPriority = slimePriority[target:GetAttribute("EnemyId")] or 5
            for candidate in pairs(enemies) do
                if validSlime(candidate) and (blocked[candidate] or 0) <= now
                    and (slimePriority[candidate:GetAttribute("EnemyId")] or 5) < currentPriority then
                    target = selectTarget(root, now)
                    break
                end
            end
        end
        if target then
            local hp = health(target)
            if previousHP and hp < previousHP then
                lastDamageAt, lastProgressAt = now, now
            end
            previousHP = hp
            if now - lastProgressAt > 1.2 and not collection then farm.height = -4 end
            if now - lastProgressAt > 7 and not collection then
                blocked[target] = now + 5
                target = selectTarget(root, now)
            end
        end
        -- Short collection visits run during the sword's observed damage cooldown.
        if farm.collect and not collection
            and (not target or (now - lastDamageAt < 0.12)) then
            collection = nextCollection(root, now)
            if collection then collection.started = now end
        end
        if collection then
            local item = collection
            if not item.part:IsDescendantOf(workspace)
                or (item.kind == "flower" and item.part:GetAttribute("Mature") ~= true) then
                if item.sent then
                    if item.kind == "flower" then farm.flowers = farm.flowers + 1
                    else farm.shinies = farm.shinies + 1 end
                end
                collection = nil
            elseif now - item.started > 0.45 then
                retryAfter[item.object] = now + 5
                collection = nil
            else
                root.CFrame = CFrame.new(item.part.Position + Vector3.new(0, 3, 3), item.part.Position)
                root.AssemblyLinearVelocity = Vector3.zero
                farm.mode = "collecting " .. item.kind
                if not item.sent and now - item.started >= 0.15 then
                    item.sent = true
                    if item.kind == "flower" then harvest:FireServer(item.object)
                    else fireproximityprompt(item.object) end
                end
            end
        end
        if not collection then
            farm.mode = target and "attacking" or "waiting for spawns"
            if target then
                local point = target.Position + Vector3.new(0, farm.height, 0.1)
                root.CFrame = CFrame.lookAt(point, target.Position)
                root.AssemblyLinearVelocity = Vector3.zero
            end
        end
        if target and target.Parent then
            swing:FireServer(target)
            farm.attacks = farm.attacks + 1
        end
    end)
    if not ok then
        farm.lastError = tostring(message)
        farm.target = nil
        collection = nil
        farm.mode = "recovering"
        if os.clock() - lastWarningAt > 5 then
            lastWarningAt = os.clock()
            warn("Farm retrying after: " .. tostring(message))
        end
    end
end)
print("Automatic farm ON: HUB portal recovery, attacks every frame, instant switching, shinies + flowers. F6 all; F7 collection.")



-- The same entrypoint is used on the main account and each alt.
local uiOK, uiError = pcall(function()
    local controllerFactory = assert(loadstring(game:HttpGet("https://raw.githubusercontent.com/DarkBotGen/slime-farm/cecd01ed31882947c4ee84a5f834ecb62b598768/controller.luau")))()
    farm.controller = controllerFactory(farm, {
        remotes=remotes, config=config, loadModule=loadModule,
        controllers=controllers, shared=shared,
    })
    local guiFactory = assert(loadstring(game:HttpGet("https://raw.githubusercontent.com/DarkBotGen/slime-farm/cecd01ed31882947c4ee84a5f834ecb62b598768/gui.luau")))()
    farm.gui = guiFactory(farm, farm.controller)
end)
if not uiOK then farm.uiError=tostring(uiError); warn("Farm GUI: " .. tostring(uiError)) end

local telemetryOK = pcall(function()
    local factory = assert(loadstring(game:HttpGet("https://raw.githubusercontent.com/DarkBotGen/slime-farm/a8f6eaf15b6f0edb829fd0312e7def33775acdbf/telemetry.luau")))()
    farm.telemetry = factory(farm, {remotes=remotes, config=config})
end)
if not telemetryOK then farm.telemetryError="Could not load gel reporting" end

