-- Above-ground walking farm. F6 pauses; F7 toggles optional nearby collection.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Input=game:GetService("UserInputService")
local Tags=game:GetService("CollectionService")
local VirtualUser=game:GetService("VirtualUser")
local player=Players.LocalPlayer
local loadModule: any=require
local shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local controllers=player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Controllers")
local hotbar=loadModule(controllers:WaitForChild("HotbarController"))
local animation=loadModule(controllers:WaitForChild("AnimationController"))
local remotes=loadModule(shared:WaitForChild("Remotes"))
local config=loadModule(shared:WaitForChild("Config"))
local swing=remotes.get(remotes.RequestSwing)
local harvest=remotes.get(remotes.RequestHarvest)
local env=getgenv()
if env.SlimeFarm and env.SlimeFarm.stop then env.SlimeFarm.stop() end
local farm: any={enabled=true,collect=true,walkingOnly=true,undergroundOnly=false,
    attacks=0,kills=0,flowers=0,shinies=0,hubReturns=0,autoHub=true,mode="starting",
    antiAfk=true,antiAfkEvents=0}
env.SlimeFarm=farm
local navigationOK=pcall(function()
    local factory=assert(loadstring(game:HttpGet("https://raw.githubusercontent.com/DarkBotGen/slime-farm/7f3b757b26d9a447ed23cb53bb58be0bbe070c73/navigation.luau")))()
    farm.navigation=factory(farm,{loadModule=loadModule,controllers=controllers,config=config})
end)
if not navigationOK then farm.navigationError="Navigation unavailable; farming paused";farm.enabled=false end
local stopped=false
local connections={}
local enemies,flowers,shinies={},{},{}
local blocked=setmetatable({},{__mode="k"})
local retries=setmetatable({},{__mode="k"})
local counted=setmetatable({},{__mode="k"})
local folder=nil
local collection=nil
local portal=nil
local travelling=false
local character=nil
local hpConnection=nil
local lastScan,lastEquip,lastSwing=-10,-10,-10
local previousHP,lastProgress,lastDistance=nil,0,math.huge
local priorities={OrangeSlime=1,PinkSlime=2,BlueSlime=3,GreenSlime=4}
local function connect(signal,callback)
    local c=signal:Connect(callback);table.insert(connections,c);return c
end
local function inHub(position)
    local delta=position-config.Hub.Origin
    local half=config.Hub.SizeStuds*0.5
    return math.abs(delta.X)<=half.X+40 and math.abs(delta.Z)<=half.Z+40 and math.abs(delta.Y)<=160
end
local function health(part)
    if not part.Parent then return 0 end
    local gui=part:FindFirstChild("Health")
    local bar=gui and gui:FindFirstChild("Bar")
    return bar and bar.Size.X.Scale or 1
end
local function valid(part)
    return part and part:IsA("BasePart") and part.Parent==folder
        and string.find(string.lower(part.Name),"slime")~=nil and health(part)>0
end
local function countKill(part)
    if not counted[part] then counted[part]=true;farm.kills+=1 end
end
local function choose(root,now)
    local best,score=nil,math.huge
    for candidate in pairs(enemies) do
        if valid(candidate) and (blocked[candidate] or 0)<=now then
            local def=config.Enemy.Enemies[candidate:GetAttribute("EnemyId")]
            local distance=(root.Position-candidate.Position).Magnitude
            local cost=(priorities[candidate:GetAttribute("EnemyId")] or 5)*1000000
                +distance*10+health(candidate)*(def and def.hp or 150)
            if cost<score then best,score=candidate,cost end
        end
    end
    farm.target=best
    if hpConnection then hpConnection:Disconnect();hpConnection=nil end
    local gui=best and best:FindFirstChild("Health")
    local bar=gui and gui:FindFirstChild("Bar")
    if bar then
        hpConnection=bar:GetPropertyChangedSignal("Size"):Connect(function()
            if farm.target==best and health(best)<=0 then countKill(best);farm.target=nil end
        end)
    end
    previousHP=best and health(best) or nil
    lastProgress=now
    lastDistance=best and (best.Position-root.Position).Magnitude or math.huge
    return best
end
local function attach(newFolder)
    folder=newFolder
    table.clear(enemies)
    for _,part in ipairs(folder:GetChildren()) do enemies[part]=true end
    connect(folder.ChildAdded,function(part) enemies[part]=true end)
    connect(folder.ChildRemoved,function(part)
        enemies[part]=nil
        if farm.target==part then
            local gui=part:FindFirstChild("Health")
            local bar=gui and gui:FindFirstChild("Bar")
            if bar and bar.Size.X.Scale<=0 then countKill(part) end
            farm.target=nil
        end
    end)
end
local function flower(part) if part:IsA("BasePart") then flowers[part]=true end end
local function shiny(prompt)
    if prompt:IsA("ProximityPrompt") and prompt.Parent and prompt.Parent:IsA("BasePart")
        and prompt.Parent:GetAttribute("ShinyPiece") then shinies[prompt]=true end
end
for _,part in ipairs(Tags:GetTagged("Flower")) do flower(part) end
for _,prompt in ipairs(Tags:GetTagged("AbovePrompt")) do shiny(prompt) end
connect(Tags:GetInstanceAddedSignal("Flower"),flower)
connect(Tags:GetInstanceRemovedSignal("Flower"),function(part) flowers[part]=nil end)
connect(Tags:GetInstanceAddedSignal("AbovePrompt"),shiny)
connect(Tags:GetInstanceRemovedSignal("AbovePrompt"),function(prompt) shinies[prompt]=nil end)
local function pickup(root,now,maxDistance)
    local best,distance=nil,maxDistance
    for prompt in pairs(shinies) do
        local part=prompt.Parent
        if part and prompt:IsDescendantOf(workspace) and prompt.Enabled and inHub(part.Position)
            and (retries[prompt] or 0)<=now then
            local d=(part.Position-root.Position).Magnitude
            if d<distance then best={kind="shiny",object=prompt,part=part};distance=d end
        end
    end
    for part in pairs(flowers) do
        if part:IsDescendantOf(workspace) and part:GetAttribute("Mature")==true
            and inHub(part.Position) and (retries[part] or 0)<=now then
            local d=(part.Position-root.Position).Magnitude
            if d<distance then best={kind="flower",object=part,part=part};distance=d end
        end
    end
    if best then best.started=now;best.lastSent=-10 end
    return best
end
local function visible(root,part)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={root.Parent}
    params.RespectCanCollide=true
    local delta=part.Position-root.Position
    local hit=workspace:Raycast(root.Position,delta,params)
    return not hit or hit.Instance==part
end
local function weapon()
    local selected=hotbar.selected()
    local def=selected and config.Weapon.Weapons[selected.itemId]
    return selected,def
end
local function inSwordRange(root,target)
    local selected,def=weapon()
    return selected and selected.toolSlot=="Weapon" and def
        and (target.Position-root.Position).Magnitude<=(def.reachStuds or 5.4)
        and visible(root,target)
end
local function tryAttack(root,target,now)
    if not inSwordRange(root,target) or not animation.swingReady() then return end
    local _,def=weapon()
    local standard=def and def.standard
    local cooldown=standard and standard.AttackCooldown
    local interval=if type(cooldown)=="table" then cooldown.max or 0.7 else 0.7
    if now-lastSwing<math.max(0.12,interval) then return end
    lastSwing=now
    local function hit()
        local live=player.Character
        local currentRoot=live and live:FindFirstChild("HumanoidRootPart")
        if not stopped and farm.enabled and farm.target==target and valid(target)
            and currentRoot and inSwordRange(currentRoot,target) then
            swing:FireServer(target);farm.attacks+=1
        end
    end
    local result=animation.playSwing(hit)
    if result~="Scheduled" and result~="Cooldown" then hit() end
end
local function returnToHub(root,humanoid,now)
    if inHub(root.Position) then
        if travelling then farm.hubReturns+=1;farm.target=nil;collection=nil;farm.navigation.pause() end
        travelling=false;portal=nil;return true
    end
    travelling=true
    farm.target=nil;collection=nil
    if not farm.autoHub then farm.mode="Outside HUB";farm.navigation.pause();return false end
    if now-lastScan>=1 or not portal or not portal:IsDescendantOf(workspace) then
        lastScan=now;portal=nil
        local nearest=math.huge
        for _,island in ipairs(workspace:GetChildren()) do
            if typeof(island:GetAttribute("IslandOrigin"))=="Vector3" then
                for _,candidate in ipairs(island:GetChildren()) do
                    if candidate.Name=="HUB" or candidate:GetAttribute("PortalRotation")~=nil then
                        local trigger=candidate:FindFirstChild("TouchPart",true)
                        if trigger and trigger:IsA("BasePart") then
                            local d=(trigger.Position-root.Position).Magnitude
                            if d<nearest then portal,nearest=trigger,d end
                        end
                    end
                end
            end
        end
    end
    farm.mode=portal and "Walking to HUB portal" or "Waiting for HUB portal to load"
    if portal then farm.navigation.seek(root,humanoid,portal.Position,0.5,now) end
    return false
end
local function pause()
    if farm.navigation then farm.navigation.pause() end
    collection=nil;farm.target=nil
    farm.mode="paused"
end
function farm.setEnabled(value)
    farm.enabled=value==true
    if not farm.enabled then pause() end
end
function farm.stop()
    if stopped then return end
    stopped=true;farm.enabled=false
    if hpConnection then hpConnection:Disconnect() end
    for _,c in ipairs(connections) do c:Disconnect() end
    if farm.navigation then farm.navigation.stop() end
    if farm.controller then farm.controller.stop() end
    if farm.telemetry then farm.telemetry.stop() end
    if farm.performance then farm.performance.stop() end
    farm.mode="stopped"
end
connect(player.Idled,function()
    if stopped or not farm.antiAfk then return end
    local ok=pcall(function() VirtualUser:CaptureController();VirtualUser:ClickButton2(Vector2.zero) end)
    if ok then farm.antiAfkEvents+=1 end
end)
connect(Input.InputBegan,function(key,processed)
    if processed or Input:GetFocusedTextBox() then return end
    if key.KeyCode==Enum.KeyCode.F6 then farm.setEnabled(not farm.enabled)
    elseif key.KeyCode==Enum.KeyCode.F7 then farm.collect=not farm.collect;collection=nil end
end)
local lastWarning=-10
connect(RunService.Heartbeat,function()
    if stopped then return end
    local ok,err=pcall(function()
        local now=os.clock()
        local live=player.Character
        local root=live and live:FindFirstChild("HumanoidRootPart")
        local humanoid=live and live:FindFirstChildOfClass("Humanoid")
        if not root or not humanoid or humanoid.Health<=0 then
            if farm.navigation then farm.navigation.pause() end
            farm.mode="waiting for respawn";farm.target=nil;collection=nil;return
        end
        if character~=live then
            character=live;collection=nil;farm.target=nil
            if farm.navigation then farm.navigation.pause() end
        end
        if farm.controller then farm.controller.step(root,now) end
        if not farm.enabled or not farm.navigation then return end
        if root.Anchored then farm.navigation.pause();farm.mode="waiting for travel";return end
        if not returnToHub(root,humanoid,now) then return end
        local hub=workspace:FindFirstChild("Hub")
        local current=hub and hub:FindFirstChild("Guardians")
        if current and current~=folder then attach(current) end
        if hotbar.selected().toolSlot~="Weapon" and now-lastEquip>0.3 then lastEquip=now;hotbar.select(1) end
        local target=farm.target
        if not valid(target) then target=choose(root,now) end
        if target then
            local priority=priorities[target:GetAttribute("EnemyId")] or 5
            for candidate in pairs(enemies) do
                if valid(candidate) and (blocked[candidate] or 0)<=now
                    and (priorities[candidate:GetAttribute("EnemyId")] or 5)<priority then target=choose(root,now);break end
            end
            local distance=(target.Position-root.Position).Magnitude
            local hp=health(target)
            if (previousHP and hp<previousHP) or distance<lastDistance-1 then lastProgress=now;lastDistance=distance end
            previousHP=hp
            if now-lastProgress>15 and not collection then
                blocked[target]=now+15;target=choose(root,now)
            end
        end
        -- Combat has priority. Walk to pickups between targets, never teleport.
        if farm.collect and not collection and not target then collection=pickup(root,now,100) end
        if collection and target then collection=nil end
        if collection then
            local item=collection
            if not item.part:IsDescendantOf(workspace) or (item.kind=="flower" and item.part:GetAttribute("Mature")~=true) then
                if item.sent then if item.kind=="flower" then farm.flowers+=1 else farm.shinies+=1 end end
                collection=nil
            elseif now-item.started>30 then retries[item.object]=now+20;collection=nil
            else
                local reach=if item.kind=="shiny" then math.min(6,item.object.MaxActivationDistance) else math.min(6,config.Player.InteractReachStuds or 6)
                farm.mode="Walking to "..item.kind
                local close=(item.part.Position-root.Position).Magnitude<=reach
                farm.navigation.seek(root,humanoid,item.part.Position,math.max(1,reach-1),now)
                if close and visible(root,item.part) and now-item.lastSent>1 then
                    item.lastSent=now;item.sent=true
                    if item.kind=="flower" then harvest:FireServer(item.object) else fireproximityprompt(item.object) end
                end
            end
        elseif target then
            local _,def=weapon()
            local reach=def and def.reachStuds or 5.4
            local close=inSwordRange(root,target)
            farm.navigation.seek(root,humanoid,target.Position,math.max(1,reach*0.6),now)
            farm.mode=close and "attacking" or "Walking to "..target.Name
            tryAttack(root,target,now)
        else
            farm.navigation.pause()
            farm.mode="waiting for spawns"
        end
    end)
    if not ok then
        farm.lastError=tostring(err)
        if farm.navigation then farm.navigation.pause() end
        farm.mode="recovering"
        if os.clock()-lastWarning>5 then lastWarning=os.clock();warn("Walking farm: "..tostring(err)) end
    end
end)
local performanceOK=pcall(function()
    local factory=assert(loadstring(game:HttpGet("https://raw.githubusercontent.com/DarkBotGen/slime-farm/7f3b757b26d9a447ed23cb53bb58be0bbe070c73/performance.luau")))()
    farm.performance=factory(farm)
end)
if not performanceOK then farm.performanceError="Could not enable alt resource savings" end
local uiOK,uiError=pcall(function()
    local factory=assert(loadstring(game:HttpGet("https://raw.githubusercontent.com/DarkBotGen/slime-farm/f938d59f7b6da62d16d4fa1017b52082164826be/controller.luau")))()
    farm.controller=factory(farm,{remotes=remotes,config=config,loadModule=loadModule,controllers=controllers,shared=shared})
    local guiFactory=assert(loadstring(game:HttpGet("https://raw.githubusercontent.com/DarkBotGen/slime-farm/f938d59f7b6da62d16d4fa1017b52082164826be/gui.luau")))()
    farm.gui=guiFactory(farm,farm.controller)
end)
if not uiOK then farm.uiError=tostring(uiError) end
local telemetryOK=pcall(function()
    local factory=assert(loadstring(game:HttpGet("https://raw.githubusercontent.com/DarkBotGen/slime-farm/f5fa220cdd7bbc6301f4c03be5ae161db1c65da1/telemetry.luau")))()
    farm.telemetry=factory(farm,{remotes=remotes,config=config})
end)
if not telemetryOK then farm.telemetryError="Could not load gel reporting" end
print("Walking farm: normal sprint, pathfinding, ordinary sword range/cooldown, and walking HUB portal entry. F6 pause; F7 collection.")

