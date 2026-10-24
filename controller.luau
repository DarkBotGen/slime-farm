-- Local multi-client transfer controller. Each participating Real client must run the script.
return function(farm, context)
    local Players = game:GetService("Players")
    local Http = game:GetService("HttpService")
    local Tags = game:GetService("CollectionService")
    local player = Players.LocalPlayer
    local R, config = context.remotes, context.config
    local build = context.loadModule(context.controllers:WaitForChild("BuildController"))
    local stackKey = context.loadModule(context.shared:WaitForChild("StackKey"))
    local mainId, mainName = 1407091060, "RobotTifaski"
    local isMain = player.UserId == mainId
    local prefix = "slime-farm-control/" .. game.JobId .. "/"
    local clientPath = prefix .. "client-" .. player.UserId .. ".json"
    local mainPath = prefix .. "client-" .. mainId .. ".json"
    local requestPath = prefix .. "request.json"
    local settingsPath = "slime-farm-control/auto-transfer-" .. mainId .. ".json"
    local session = Http:GenerateGUID(false)
    local inventory, inventoryReady = {}, false
    local inventoryVersion = 0
    local connections, active, gui = {}, nil, nil
    local stopped, lastPoll, lastPublish, lastSync, lastUI = false, 0, 0, -10, 0
    local seenTokens = {}
    local readCache = {}
    local control: any = {status = "Idle", isMain = isMain, mainName = mainName, selectedAlt = nil}
    farm.transfer = control
    local function read(path)
        local ok, value = pcall(function()
            if not isfile(path) then return nil end
            return Http:JSONDecode(readfile(path))
        end)
        if ok and type(value)=="table" then readCache[path]=value;return value end
        return readCache[path]
    end
    local function write(path, value)
        writefile(path, Http:JSONEncode(value))
    end
    local settings = read(settingsPath) or {}
    local savedInterval = tonumber(settings.intervalMinutes) or 15
    local auto = {
        enabled = isMain and settings.enabled ~= false,
        parallel = settings.parallel == true,
        intervalMinutes = math.clamp(savedInterval, 1, 1440),
        queue = {}, roundRunning = false, lastResult = "No round yet",
    }
    auto.nextAt = os.time() + math.floor(auto.intervalMinutes * 60)
    control.auto = auto
    local function saveAuto()
        if isMain then
            write(settingsPath, {enabled=auto.enabled, intervalMinutes=auto.intervalMinutes, parallel=auto.parallel})
        end
    end
    function control.setAutoEnabled(enabled)
        auto.enabled = isMain and enabled == true
        if not auto.enabled then
            table.clear(auto.queue)
            auto.roundRunning = false
        end
        auto.nextAt = os.time() + math.floor(auto.intervalMinutes * 60)
        saveAuto()
    end
    function control.setParallel(value)
        auto.parallel = value == true
        saveAuto()
    end
    function control.setAutoInterval(value)
        local minutes = tonumber(value)
        if not minutes or minutes < 1 or minutes > 1440 then
            return false, "Enter a transfer interval between 1 and 1440 minutes"
        end
        auto.intervalMinutes = minutes
        auto.nextAt = os.time() + math.floor(minutes * 60)
        saveAuto()
        return true
    end
    local function snapshot()
        local copy = {}
        for key, count in pairs(inventory) do copy[key] = count end
        return copy
    end
    local function rootOf(account)
        local character = account and account.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if root and humanoid and humanoid.Health > 0 then return root end
        return nil
    end
    local function mainIsland()
        for _, island in ipairs(workspace:GetChildren()) do
            if string.find(island.Name, "Island_" .. mainId .. ":", 1, true) == 1
                and typeof(island:GetAttribute("IslandOrigin")) == "Vector3" then return island end
        end
        return nil
    end
    local function atMainIsland(root)
        local island = mainIsland()
        local origin = island and island:GetAttribute("IslandOrigin")
        local current = build.islandOrigin()
        return island and typeof(current) == "Vector3" and (current - origin).Magnitude < 1
            and (root.Position - origin).Magnitude < 250, island, origin
    end
    local function fresh(record)
        return record and record.jobId == game.JobId and record.mainId == mainId
            and type(record.updated) == "number" and math.abs(os.time() - record.updated) <= 6
    end
    local function peer(userId)
        return read(prefix .. "client-" .. userId .. ".json")
    end
    function control.listAlts()
        local result = {}
        for _, account in ipairs(Players:GetPlayers()) do
            if account.UserId ~= mainId and fresh(peer(account.UserId)) then
                table.insert(result, account.Name)
            end
        end
        table.sort(result)
        return result
    end
    local function publish(root)
        local record = {
            jobId = game.JobId, mainId = mainId, userId = player.UserId, name = player.Name,
            session = session, updated = os.time(), inventoryReady = inventoryReady,
            token = active and active.request.token or control.lastToken,
            phase = active and active.phase or control.lastPhase or "idle",
            status = control.status, dropped = active and active.dropped or control.dropped or 0,
            received = active and active.received or control.received or 0,
            ready = active and active.ready or false,
            droppedCounts = active and active.droppedCounts or control.droppedCounts or {},
            completedSources = active and active.completedSources or control.completedSources or {},
            x = root and root.Position.X, y = root and root.Position.Y, z = root and root.Position.Z,
        }
        write(clientPath, record)
    end
    local function finish(phase, message)
        if active then
            control.lastToken, control.lastPhase = active.request.token, phase
            control.dropped, control.received = active.dropped, active.received
            control.droppedCounts = active.droppedCounts or {}
            control.completedSources = active.completedSources or {}
            seenTokens[active.request.token] = true
        end
        active = nil
        farm.transferBusy = false
        control.status = message
        farm.target = nil
    end
    function control.cancel()
        table.clear(auto.queue)
        auto.roundRunning = false
        auto.nextAt = os.time() + math.floor(auto.intervalMinutes * 60)
        if active and isMain then
            active.request.cancelled = true
            write(requestPath, active.request)
        end
        finish("cancelled", "Cancelled; already dropped items remain on the island")
    end
    local gelPriority={OrangeSlimeGel=1,PinkSlimeGel=2,BlueSlimeGel=3,SlimeGel=4}
    local function queueFor(scope, limit)
        local queue,total={},0
        for key,count in pairs(inventory) do
            local item=stackKey.item(key)
            local eligible=scope=="All backpack items" or string.match(item,"SlimeGel$")~=nil
                or config.Shiny.isShiny(item) or config.Flower.isFlower(item)
            if eligible and count>0 and not config.Tool.StarterEquipment[item] then
                table.insert(queue,{key=key,initial=count,amount=math.floor(count)})
            end
        end
        table.sort(queue,function(x,y)
            local xp=gelPriority[stackKey.item(x.key)] or 5
            local yp=gelPriority[stackKey.item(y.key)] or 5
            if xp~=yp then return xp<yp end
            return x.key<y.key
        end)
        local result={}
        for _,entry in ipairs(queue) do
            if limit then entry.amount=math.min(entry.amount,math.max(0,limit-total)) end
            if entry.amount>0 then table.insert(result,entry);total=total+entry.amount end
        end
        return result,total
    end
    function control.requestTransfer(altName, scope, testLimit)
        if not isMain then return false, "Start transfers from RobotTifaski's GUI" end
        if active then return false, "A transfer is already running" end
        if not inventoryReady then return false, "Waiting for inventory sync" end
        local account = Players:FindFirstChild(altName or "")
        local record = account and peer(account.UserId)
        if not account or account.UserId == mainId or not fresh(record) or not record.inventoryReady then
            return false, "Selected alt must run this script in the same server and Real workspace"
        end
        local request = {
            token = Http:GenerateGUID(false), jobId = game.JobId, mainId = mainId,
            mainSession = session, altSession = record.session, sourceId = account.UserId,
            sourceName = account.Name, scope = scope or "Farm loot", created = os.time(),
            expires = os.time() + 30, limit = testLimit,
        }
        active = {request=request, phase="travelling", started=os.clock(), lastTravel=-10,
            lastPickup=0, dropped=0, received=0, baseline=snapshot(), ready=false}
        farm.transferBusy = true
        control.status = "Going home; waiting for " .. account.Name
        write(requestPath, request)
        return true
    end
    local function sourceEntry(request, userId)
        if request.parallel then
            for _, source in ipairs(request.sources or {}) do
                if source.userId == userId then return source end
            end
        elseif request.sourceId == userId then
            return {userId=request.sourceId, name=request.sourceName, session=request.altSession, index=1}
        end
        return nil
    end
    function control.requestParallel(scope, testLimit)
        if not isMain then return false, "Only RobotTifaski can start a group transfer" end
        if active then return false, "A transfer is already running" end
        if not inventoryReady then return false, "Waiting for inventory sync" end
        local sources={}
        for _, name in ipairs(control.listAlts()) do
            local account=Players:FindFirstChild(name)
            local record=account and peer(account.UserId)
            if account and fresh(record) and record.inventoryReady then
                table.insert(sources,{userId=account.UserId,name=name,session=record.session,index=#sources+1})
            end
        end
        if #sources==0 then return false,"No connected alts with a ready inventory" end
        local request={
            token=Http:GenerateGUID(false),jobId=game.JobId,mainId=mainId,
            mainSession=session,parallel=true,sources=sources,
            scope=scope or "All backpack items",created=os.time(),expires=os.time()+30,limit=testLimit,
        }
        active={request=request,phase="travelling",started=os.clock(),lastTravel=-10,
            lastPickup=0,dropped=0,received=0,baseline=snapshot(),ready=false}
        farm.transferBusy=true
        control.status="Going home; gathering " .. #sources .. " alts"
        write(requestPath,request)
        return true
    end
    function control.runAutoRound()
        if not isMain then return false, "Only the main account schedules transfers" end
        if active or auto.roundRunning then return false, "A transfer round is already running" end
        local names = control.listAlts()
        if auto.parallel and #names>0 then
            local ok,message=control.requestParallel("All backpack items")
            if not ok then
                auto.nextAt=os.time()+math.floor(auto.intervalMinutes*60)
                auto.lastResult=tostring(message)
                return false,message
            end
            auto.queue={}
            auto.roundRunning=true
            auto.lastResult="Concurrent round started: " .. #names .. " alts"
            return true
        end
        auto.queue = names
        auto.roundRunning = #names > 0
        auto.nextAt = os.time() + math.floor(auto.intervalMinutes * 60)
        if #names == 0 then
            auto.lastResult = "No connected alts; waiting for the next interval"
            return false, auto.lastResult
        end
        auto.lastResult = "Round started: " .. #names .. " connected alts"
        return true
    end
    local function automaticTransfers()
        if not isMain or not inventoryReady or active then return end
        if auto.roundRunning then
            if #auto.queue > 0 then
                local name = table.remove(auto.queue, 1)
                local ok, message = control.requestTransfer(name, "All backpack items")
                if not ok then auto.lastResult = name .. ": " .. tostring(message) end
            else
                auto.roundRunning = false
                auto.nextAt = os.time() + math.floor(auto.intervalMinutes * 60)
                auto.lastResult = "Round complete; farming until the next interval"
            end
        elseif auto.enabled and os.time() >= auto.nextAt then
            control.runAutoRound()
        end
    end
    table.insert(connections, R.get(R.InventoryChanged).OnClientEvent:Connect(function(a1, _, _, _, _, _, a7)
        if type(a1) == "table" then
            inventory = stackKey.split(a1, type(a7) == "table" and a7 or nil)
            inventoryReady = true
            inventoryVersion = inventoryVersion + 1
        end
    end))
    local function looseNear(root)
        local result = {}
        for _, part in ipairs(Tags:GetTagged("LooseItem")) do
            if part:IsA("BasePart") and part:IsDescendantOf(workspace)
                and (part.Position - root.Position).Magnitude <= config.Build.Pickup.RadiusStuds then
                table.insert(result, part)
            end
        end
        return result
    end
    local function mainStep(root, now)
        local request = active.request
        local source,other
        local pendingSources={}
        active.completedSources=active.completedSources or {}
        active.allocatedCounts=active.allocatedCounts or {}
        if request.parallel then
            local allWaiting=true
            local dropped=0
            for _,entry in ipairs(request.sources) do
                local completed=active.completedSources[tostring(entry.userId)]
                if completed then
                    dropped=dropped+completed.dropped
                else
                    local account=Players:GetPlayerByUserId(entry.userId)
                    local record=peer(entry.userId)
                    if not account or not fresh(record) or record.session~=entry.session then
                        finish("error",entry.name .. " disconnected; group transfer stopped")
                        return
                    end
                    allWaiting=false
                    if record.token==request.token then
                        if record.phase=="error" or record.phase=="cancelled" then
                            finish("error",entry.name .. ": " .. tostring(record.status))
                            return
                        end
                        dropped=dropped+(record.dropped or 0)
                        if record.phase=="waiting-pickup" then
                            table.insert(pendingSources,{entry=entry,record=record})
                        end
                    end
                end
            end
            source={Name=tostring(#request.sources) .. " alts"}
            other={token=request.token,dropped=dropped,phase=allWaiting and "waiting-pickup" or "dropping"}
        else
            source=Players:GetPlayerByUserId(request.sourceId)
            other=peer(request.sourceId)
            if not source or not fresh(other) or other.session~=request.altSession then
                finish("error","Alt disconnected; transfer stopped")
                return
            end
            if other.token==request.token and (other.phase=="error" or other.phase=="cancelled") then
                finish("error",other.status or "Alt stopped")
                return
            end
        end
        local there, _, islandOrigin = atMainIsland(root)
        if not there then
            active.holdCF = nil
            active.ready = false
            control.status = "Returning RobotTifaski to home island"
            if now - active.lastTravel > 3 then
                active.lastTravel = now
                R.get(R.RequestFriendAction):FireServer("Home")
            end
            return
        end
        if root.Anchored then active.ready=false; return end
        local point = islandOrigin + Vector3.new(0, 5, 0)
        active.holdCF = CFrame.new(point)
        root.CFrame = active.holdCF
        root.AssemblyLinearVelocity = Vector3.zero
        active.ready = true
        active.phase = "receiving"
        local received=0
        local gains={}
        for key,count in pairs(inventory) do
            local gain=math.max(0,count-(active.baseline[key] or 0))
            gains[key]=gain
            received=received+gain
        end
        active.received = received
        local loose = looseNear(root)
        if now - active.lastPickup >= 0.1 then
            active.lastPickup = now
            for i=1, math.min(8,#loose) do
                local id=loose[i]:GetAttribute("EntityId")
                if id then R.get(R.RequestPickup):FireServer(id) end
            end
        end
        if request.parallel then
            for _,pending in ipairs(pendingSources) do
                local enough=true
                local counts=pending.record.droppedCounts or {}
                local total=0
                for key,count in pairs(counts) do
                    total=total+count
                    if (gains[key] or 0)-(active.allocatedCounts[key] or 0)<count then enough=false end
                end
                if total~=(pending.record.dropped or 0) then enough=false end
                if enough then
                    for key,count in pairs(counts) do
                        active.allocatedCounts[key]=(active.allocatedCounts[key] or 0)+count
                    end
                    active.completedSources[tostring(pending.entry.userId)]={dropped=total}
                end
            end
            local completed=0
            for _ in pairs(active.completedSources) do completed=completed+1 end
            active.dropped=other.dropped or 0
            control.status=string.format("%d / %d alts finished | dropped %d | received %d",completed,#request.sources,active.dropped,received)
            if completed==#request.sources then
                finish("complete",string.format("Complete: received %d items from %d alts",received,completed))
            end
            return
        end
        if other.token == request.token then
            active.dropped = other.dropped or 0
            control.status = string.format("%s: dropped %d | received %d", source.Name, active.dropped, received)
            if other.phase == "waiting-pickup" and #loose == 0 and received >= active.dropped then
                finish("complete", string.format("Complete: received %d items from %s", received, source.Name))
            end
        end
    end
    local function altStep(root, now)
        local request=active.request
        local mainRecord=read(mainPath)
        local main=Players:GetPlayerByUserId(mainId)
        local mainRoot=rootOf(main)
        local ownCompletion=mainRecord and mainRecord.completedSources
            and mainRecord.completedSources[tostring(player.UserId)]
        if fresh(mainRecord) and mainRecord.session==request.mainSession
            and mainRecord.token==request.token and ownCompletion then
            finish("complete","Inventory transferred and collected; returning to farming")
            return
        end
        if fresh(mainRecord) and mainRecord.session == request.mainSession
            and mainRecord.token == request.token and mainRecord.phase == "complete" then
            finish("complete", "Transfer complete; returning to farming")
            return
        end
        if not fresh(mainRecord) or mainRecord.session ~= request.mainSession or not main then
            active.phase="waiting-receiver"
            control.status="Waiting for receiver; remaining inventory is not empty"
            return
        end
        local latest=read(requestPath)
        if not latest then
            control.status="Waiting for transfer command"
            return
        end
        if latest.token ~= request.token or latest.cancelled then
            finish("cancelled", "Transfer cancelled by main account"); return
        end
        if mainRecord.token == request.token and mainRecord.phase == "complete" then
            finish("complete", "Transfer complete; returning to farming"); return
        end
        if mainRecord.token == request.token and (mainRecord.phase == "error" or mainRecord.phase == "cancelled") then
            active.phase="blocked"
            control.status=mainRecord.status or "Receiver stopped; inventory kept until retry or cancel"
            return
        end
        local there=atMainIsland(root)
        if not there then
            active.holdCF=nil
            active.phase="travelling"
            control.status="Visiting " .. mainName .. "'s island"
            if now-active.lastTravel>3 then
                active.lastTravel=now
                R.get(R.RequestFriendAction):FireServer("Visit",mainId)
            end
            return
        end
        if not mainRecord.ready or mainRecord.token ~= request.token or not mainRoot or root.Anchored then
            control.status="Waiting for receiver to be ready"; return
        end
        local ownEntry=sourceEntry(request,player.UserId)
        local angle=request.parallel and ((ownEntry.index-1)*math.pi*2/#request.sources) or 0
        local offset=Vector3.new(math.cos(angle)*4,0,math.sin(angle)*4)
        active.holdCF=CFrame.lookAt(mainRoot.Position+offset,mainRoot.Position)
        root.CFrame=active.holdCF
        root.AssemblyLinearVelocity=Vector3.zero
        if not active.queue then
            active.limit=type(request.limit)=="table" and request.limit[tostring(player.UserId)] or request.limit
            active.queue,active.total=queueFor(request.scope,active.limit)
            active.completedDrops=0
            active.completedCounts={}
            active.index=1
        end
        local dropped=active.completedDrops or 0
        local counts={}
        for key,count in pairs(active.completedCounts or {}) do counts[key]=count end
        for _,entry in ipairs(active.queue) do
            local taken=math.min(entry.amount,math.max(0,entry.initial-(inventory[entry.key] or 0)))
            counts[entry.key]=(counts[entry.key] or 0)+taken
            dropped=dropped+taken
        end
        active.droppedCounts=counts
        active.dropped=dropped
        while active.queue[active.index] do
            local entry=active.queue[active.index]
            local taken=math.max(0,entry.initial-(inventory[entry.key] or 0))
            if taken>=entry.amount then active.index=active.index+1 else break end
        end
        local entry=active.queue[active.index]
        if not entry and not active.limit then
            local remaining,total=queueFor(request.scope,nil)
            if #remaining>0 then
                active.completedDrops=active.dropped
                active.completedCounts=active.droppedCounts
                active.queue,active.index,active.total=remaining,1,active.dropped+total
                active.emptyVersion=nil
                entry=active.queue[1]
            elseif not active.emptyVersion then
                active.emptyVersion=inventoryVersion
                active.emptySyncAt=now
                R.get(R.RequestSync):FireServer()
                active.phase="checking-empty"
                control.status="Verifying that transferable inventory is empty"
                return
            elseif inventoryVersion<=active.emptyVersion then
                if now-active.emptySyncAt>5 then
                    active.emptySyncAt=now
                    R.get(R.RequestSync):FireServer()
                end
                active.phase="checking-empty"
                control.status="Waiting for final inventory verification"
                return
            end
        end
        if not entry then
            active.phase="waiting-pickup"
            control.status="All items dropped; waiting for pickup acknowledgement"
            return
        end
        active.phase="dropping"
        control.status=string.format("Dropping %s: %d / %d",stackKey.item(entry.key),dropped,active.total)
        if entry.lastCount ~= inventory[entry.key] then
            entry.lastCount=inventory[entry.key]
            entry.progressAt=now
        end
        if entry.awaitCount and (inventory[entry.key] or 0) < entry.awaitCount then
            entry.awaitCount = nil
        end
        if now-(entry.progressAt or now)>10 then
            active.phase="blocked"
            control.status="Waiting to drop " .. stackKey.item(entry.key) .. "; inventory is not empty"
            if now-(entry.retryAt or 0)>2 then
                entry.retryAt=now
                entry.awaitCount=nil
                entry.progressAt=now
            else return end
        end
        -- Small batches stay below the game's 50 loose-player-drop cap.
        if #looseNear(mainRoot)>=12 or entry.awaitCount then return end
        if now-(active.lastDrop or 0)>=0.07 then
            active.lastDrop=now
            entry.awaitCount=inventory[entry.key]
            R.get(R.RequestDrop):FireServer(stackKey.item(entry.key),stackKey.rollOf(entry.key))
        end
    end
    function control.step(root, now)
        if stopped then return false end
        if not inventoryReady and now-lastSync>5 then lastSync=now; R.get(R.RequestSync):FireServer() end
        if now-lastPoll>=0.08 then
            lastPoll=now
            if not isMain and not active and inventoryReady then
                local request=read(requestPath)
                local mainRecord=read(mainPath)
                local entry=request and sourceEntry(request,player.UserId)
                if request and request.jobId==game.JobId and request.mainId==mainId
                    and entry and entry.session==session
                    and request.expires>=os.time() and not request.cancelled
                    and not seenTokens[request.token] and fresh(mainRecord)
                    and mainRecord.session==request.mainSession then
                    seenTokens[request.token]=true
                    active={request=request,phase="travelling",started=now,lastTravel=-10,dropped=0,received=0,ready=false}
                    farm.transferBusy=true
                end
            end
            automaticTransfers()
            if active then
                if isMain then mainStep(root,now) else altStep(root,now) end
            end
        end
        if now-lastPublish>=0.25 then lastPublish=now; publish(root) end
        if gui and now-lastUI>=1 then
            lastUI=now
            local ok,err=pcall(gui.update)
            if not ok then control.uiError=tostring(err) end
        end
        if active then
            if active.holdCF and not root.Anchored then
                root.CFrame=active.holdCF
                root.AssemblyLinearVelocity=Vector3.zero
            end
            farm.mode=control.status
            return true
        end
        return false
    end
    function control.attachGUI(value) gui=value end
    function control.stop()
        if stopped then return end
        control.cancel()
        stopped=true
        for _,c in ipairs(connections) do c:Disconnect() end
        if gui then pcall(gui.destroy) end
        pcall(function()write(clientPath,{updated=0,userId=player.UserId})end)
    end
    function control.getInventorySummary()
        local total=0
        for _,count in pairs(inventory)do total=total+count end
        return total,inventoryReady
    end
    publish(rootOf(player))
    return control
end
