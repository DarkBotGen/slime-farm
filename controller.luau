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
    local session = Http:GenerateGUID(false)
    local inventory, inventoryReady = {}, false
    local inventoryVersion = 0
    local storageStates = {}
    local permissionState = nil
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
            chestKey = active and active.chestKey,
            transport = "LargeChest",
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
        if active and isMain then
            active.request.cancelled = true
            write(requestPath, active.request)
        end
        finish("cancelled", "Cancelled; deposited items remain in the chest")
    end
    local utilityTools={Plow=true,Bucket=true,WateringCan=true,Pollinator=true}
    local function isTool(item)
        return config.Tool.Tools[item]~=nil or config.Weapon.Weapons[item]~=nil
            or config.Tool.StarterEquipment[item]==true or utilityTools[item]==true
    end
    local gelPriority={OrangeSlimeGel=1,PinkSlimeGel=2,BlueSlimeGel=3,SlimeGel=4}
    local function queueFor(scope, limit)
        local queue,total={},0
        for key,count in pairs(inventory) do
            local item=stackKey.item(key)
            local eligible=scope=="All backpack items" or string.match(item,"SlimeGel$")~=nil
                or config.Shiny.isShiny(item) or config.Flower.isFlower(item)
            if eligible and count>0 and not isTool(item) then
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
    table.insert(connections, R.get(R.InventoryChanged).OnClientEvent:Connect(function(a1, _, _, _, _, _, a7)
        if type(a1) == "table" then
            inventory = stackKey.split(a1, type(a7) == "table" and a7 or nil)
            inventoryReady = true
            inventoryVersion = inventoryVersion + 1
        end
    end))
    table.insert(connections,R.get(R.StorageUpdate).OnClientEvent:Connect(function(key,kind,contents,slots,stackSize)
        if kind=="LargeChest" and type(contents)=="table" then
            local copy={}
            for item,count in pairs(contents) do copy[item]=count end
            local previous=storageStates[key]
            local positive={}
            if previous then for item,count in pairs(previous.positive or {}) do positive[item]=count end end
            for item,count in pairs(copy) do
                positive[item]=(positive[item] or 0)+math.max(0,count-(previous and previous.contents[item] or 0))
            end
            storageStates[key]={contents=copy,positive=positive,slots=slots,stackSize=stackSize,updated=os.clock()}
        end
    end))
    if isMain then
        table.insert(connections,R.get(R.PermissionSummary).OnClientEvent:Connect(function(value)
            if type(value)=="table" then permissionState=value end
        end))
    end
    local function chestAt(key)
        local island=mainIsland()
        if not island then return nil end
        local best=nil
        for _,part in ipairs(island:GetDescendants()) do
            if part:IsA("BasePart") and part:GetAttribute("Container")=="LargeChest"
                and (not key or part:GetAttribute("CellKey")==key) then
                if not best or tostring(part:GetAttribute("CellKey"))<tostring(best:GetAttribute("CellKey")) then best=part end
            end
        end
        return best
    end
    local function openChest(chest)
        local prompt=chest:FindFirstChildOfClass("ProximityPrompt")
        if prompt then fireproximityprompt(prompt) end
    end
    local function permissionsReady(now)
        if not permissionState then
            if now-(active.lastPermissionRead or -10)>2 then
                active.lastPermissionRead=now
                R.get(R.RequestPermissionSummary):FireServer()
            end
            control.status="Reading island/chest permissions"
            return false
        end
        local sources=active.request.sources or {{userId=active.request.sourceId}}
        local roles={}
        for _,entry in ipairs(permissionState.roles or {}) do roles[entry.userId]=entry.role end
        local action=nil
        for _,entry in ipairs(sources) do
            if roles[entry.userId]~="TrustedBuilder" then
                action=function()R.get(R.RequestFriendAction):FireServer("SetRole",entry.userId,"TrustedBuilder")end
                break
            end
        end
        if not action then
            for key in pairs(config.Permission.StorageToggles) do
                if not permissionState.storage or permissionState.storage[key]~=true then
                    action=function()R.get(R.RequestPermissionToggle):FireServer("Storage",key,true)end
                    break
                end
            end
        end
        if not action then
            for key,def in pairs(config.Permission.IslandToggles) do
                if not def.deferred and (not permissionState.island or permissionState.island[key]~=true) then
                    action=function()R.get(R.RequestPermissionToggle):FireServer("Island",key,true)end
                    break
                end
            end
        end
        if action then
            control.status="Granting participating alts full island and chest permissions"
            if now-(active.lastPermissionWrite or -10)>1.1 then
                active.lastPermissionWrite=now
                action()
                R.get(R.RequestPermissionSummary):FireServer()
            end
            return false
        end
        return true
    end
    local function mainStep(root,now)
        local request=active.request
        active.completedSources=active.completedSources or {}
        active.allocatedCounts=active.allocatedCounts or {}
        local sources=request.sources or {{userId=request.sourceId,name=request.sourceName,session=request.altSession}}
        local records={}
        local transferred=0
        for _,entry in ipairs(sources) do
            local completed=active.completedSources[tostring(entry.userId)]
            if completed then transferred=transferred+completed.dropped
            else
                local record=peer(entry.userId)
                if not fresh(record) or record.session~=entry.session then
                    active.ready=false
                    control.status="Waiting for " .. tostring(entry.name) .. "; no items will be dropped"
                    return
                end
                if record.token==request.token then
                    if record.phase=="cancelled" then
                        finish("error",entry.name .. " cancelled its deposit")
                        return
                    end
                    transferred=transferred+(record.dropped or 0)
                    records[entry.userId]=record
                end
            end
        end
        local there=atMainIsland(root)
        if not there then
            active.ready=false
            active.holdCF=nil
            control.status="Returning to main island for chest deposits"
            if now-active.lastTravel>3 then
                active.lastTravel=now
                R.get(R.RequestFriendAction):FireServer("Home")
            end
            return
        end
        local chest=chestAt(active.chestKey)
        if not chest then
            active.ready=false
            active.holdCF=nil
            control.status="Waiting for a placed Large Chest on RobotTifaski's island"
            return
        end
        active.chestKey=chest:GetAttribute("CellKey")
        active.holdCF=CFrame.lookAt(chest.Position+Vector3.new(0,3,5),chest.Position)
        if root.Anchored then active.ready=false;return end
        root.CFrame=active.holdCF
        root.AssemblyLinearVelocity=Vector3.zero
        if not permissionsReady(now) then active.ready=false;return end
        if not active.chestRequestedAt then
            active.chestRequestedAt=now
            active.lastChestOpen=now
            openChest(chest)
            active.ready=false
            control.status="Reading Large Chest contents"
            return
        end
        if now-(active.lastChestOpen or 0)>1 then active.lastChestOpen=now;openChest(chest) end
        local state=storageStates[active.chestKey]
        if not state or state.updated<active.chestRequestedAt then active.ready=false;return end
        if not active.storageBaseline then
            active.storageBaseline={}
            active.initialChestContents={}
            for item,count in pairs(state.contents) do active.initialChestContents[item]=count end
            for item,count in pairs(state.positive) do active.storageBaseline[item]=count end
        end
        active.ready=true
        active.phase="receiving-chest"
        local backpackGains={}
        for key,count in pairs(inventory) do
            local item=stackKey.item(key)
            local gain=math.max(0,count-(active.baseline[key] or 0))
            backpackGains[item]=(backpackGains[item] or 0)+gain
        end
        local gains={}
        local received=0
        for item,count in pairs(state.positive) do
            local deposited=math.max(0,count-(active.storageBaseline[item] or 0))
            local collected=math.max(0,(backpackGains[item] or 0)-(active.initialChestContents[item] or 0))
            local gain=math.min(deposited,collected)
            gains[item]=gain
            received=received+gain
        end
        local chestEmpty=true
        for _,count in pairs(state.contents) do if count>0 then chestEmpty=false;break end end
        if not chestEmpty and now-(active.lastCollectAll or -10)>0.25 then
            active.lastCollectAll=now
            R.get(R.RequestStorageWithdrawAll):FireServer(active.chestKey)
        end
        active.received=received
        for _,entry in ipairs(sources) do
            local record=records[entry.userId]
            if record and record.phase=="waiting-storage" then
                local required={}
                local total=0
                for key,count in pairs(record.droppedCounts or {}) do
                    local item=stackKey.item(key)
                    required[item]=(required[item] or 0)+count
                    total=total+count
                end
                local enough=total==(record.dropped or 0)
                for item,count in pairs(required) do
                    if (gains[item] or 0)-(active.allocatedCounts[item] or 0)<count then enough=false end
                end
                if enough then
                    for item,count in pairs(required) do
                        active.allocatedCounts[item]=(active.allocatedCounts[item] or 0)+count
                    end
                    active.completedSources[tostring(entry.userId)]={dropped=total}
                end
            end
        end
        local completed=0
        for _ in pairs(active.completedSources) do completed=completed+1 end
        active.dropped=transferred
        control.status=string.format("Large Chest: %d / %d alts finished | deposited %d | collected %d",completed,#sources,transferred,received)
        if completed==#sources and chestEmpty then
            finish("complete",string.format("Chest transfer complete: %d items collected by main",received))
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
        local chest=chestAt(mainRecord.chestKey)
        if not chest then
            active.phase="waiting-chest"
            control.status="Waiting for the destination Large Chest"
            return
        end
        local ownEntry=sourceEntry(request,player.UserId)
        local angle=request.parallel and ((ownEntry.index-1)*math.pi*2/#request.sources) or 0
        local offset=Vector3.new(math.cos(angle)*4,2,math.sin(angle)*4)
        active.holdCF=CFrame.lookAt(chest.Position+offset,chest.Position)
        root.CFrame=active.holdCF
        root.AssemblyLinearVelocity=Vector3.zero
        if now-(active.lastChestOpen or -10)>2 then
            active.lastChestOpen=now
            openChest(chest)
        end
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
            active.phase="waiting-storage"
            control.status="All non-tool items deposited; verifying chest receipt"
            return
        end
        active.phase="depositing"
        control.status=string.format("Depositing %s: %d / %d",stackKey.item(entry.key),dropped,active.total)
        if entry.lastCount ~= inventory[entry.key] then
            entry.lastCount=inventory[entry.key]
            entry.progressAt=now
        end
        if entry.awaitCount and (inventory[entry.key] or 0) < entry.awaitCount then
            entry.awaitCount = nil
        end
        if now-(entry.progressAt or now)>10 then
            active.phase="blocked"
            control.status="Chest full or deposit blocked for " .. stackKey.item(entry.key) .. "; waiting for space"
            if now-(entry.retryAt or 0)>2 then
                entry.retryAt=now
                entry.awaitCount=nil
                entry.progressAt=now
            else return end
        end
        -- Whole-stack deposits, with no ground-drop fallback.
        if entry.awaitCount then return end
        if now-(active.lastDrop or 0)>=0.07 then
            active.lastDrop=now
            entry.awaitCount=inventory[entry.key]
            local taken=math.max(0,entry.initial-(inventory[entry.key] or 0))
            local quantity=math.min(entry.amount-taken,inventory[entry.key] or 0,config.Storage.RequestCap)
            if quantity>0 then
                R.get(R.RequestStorageStore):FireServer(chest:GetAttribute("CellKey"),stackKey.item(entry.key),quantity)
            end
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
    function control.getTransferPreview()
        local queue,total=queueFor("All backpack items",nil)
        local kept={}
        for key,count in pairs(inventory) do
            if isTool(stackKey.item(key)) and count>0 then kept[key]=count end
        end
        return {eligibleCount=total,items=queue,keptTools=kept}
    end
    function control.getInventorySummary()
        local total=0
        for _,count in pairs(inventory)do total=total+count end
        return total,inventoryReady
    end
    publish(rootOf(player))
    return control
end
