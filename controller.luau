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
    local connections, active, gui = {}, nil, nil
    local stopped, lastPoll, lastPublish, lastSync, lastUI = false, 0, 0, -10, 0
    local seenTokens = {}
    local control: any = {status = "Idle", isMain = isMain, mainName = mainName, selectedAlt = nil}
    farm.transfer = control
    local function read(path)
        local ok, value = pcall(function()
            if not isfile(path) then return nil end
            return Http:JSONDecode(readfile(path))
        end)
        return ok and type(value) == "table" and value or nil
    end
    local function write(path, value)
        writefile(path, Http:JSONEncode(value))
    end
    local settings = read(settingsPath) or {}
    local savedInterval = tonumber(settings.intervalMinutes) or 15
    local auto = {
        enabled = isMain and settings.enabled ~= false,
        intervalMinutes = math.clamp(savedInterval, 1, 1440),
        queue = {}, roundRunning = false, lastResult = "No round yet",
    }
    auto.nextAt = os.time() + math.floor(auto.intervalMinutes * 60)
    control.auto = auto
    local function saveAuto()
        if isMain then
            write(settingsPath, {enabled=auto.enabled, intervalMinutes=auto.intervalMinutes})
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
            x = root and root.Position.X, y = root and root.Position.Y, z = root and root.Position.Z,
        }
        write(clientPath, record)
    end
    local function finish(phase, message)
        if active then
            control.lastToken, control.lastPhase = active.request.token, phase
            control.dropped, control.received = active.dropped, active.received
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
    local function queueFor(scope, limit)
        local queue, total = {}, 0
        for key, count in pairs(inventory) do
            local item = stackKey.item(key)
            local eligible = scope == "All backpack items"
                or string.match(item, "SlimeGel$") ~= nil
                or config.Shiny.isShiny(item) or config.Flower.isFlower(item)
            if eligible and count > 0 and not config.Tool.StarterEquipment[item] then
                local amount = math.floor(count)
                if limit then amount = math.min(amount, math.max(0, limit - total)) end
                if amount > 0 then table.insert(queue, {key = key, initial = count, amount = amount}); total = total + amount end
            end
        end
        table.sort(queue, function(a,b) return a.key < b.key end)
        return queue, total
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
    function control.runAutoRound()
        if not isMain then return false, "Only the main account schedules transfers" end
        if active or auto.roundRunning then return false, "A transfer round is already running" end
        local names = control.listAlts()
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
        local source = Players:GetPlayerByUserId(request.sourceId)
        local other = peer(request.sourceId)
        if not source or not fresh(other) or other.session ~= request.altSession then
            finish("error", "Alt disconnected; transfer stopped"); return
        end
        if other.token == request.token and (other.phase == "error" or other.phase == "cancelled") then
            finish("error", other.status or "Alt stopped"); return
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
        local received = 0
        for key, count in pairs(inventory) do received = received + math.max(0, count - (active.baseline[key] or 0)) end
        active.received = received
        local loose = looseNear(root)
        if now - active.lastPickup >= 0.1 then
            active.lastPickup = now
            for i=1, math.min(8,#loose) do
                local id=loose[i]:GetAttribute("EntityId")
                if id then R.get(R.RequestPickup):FireServer(id) end
            end
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
        if fresh(mainRecord) and mainRecord.session == request.mainSession
            and mainRecord.token == request.token and mainRecord.phase == "complete" then
            finish("complete", "Transfer complete; returning to farming")
            return
        end
        if not fresh(mainRecord) or mainRecord.session ~= request.mainSession or not main then
            finish("error", "Receiver unavailable; stopped dropping"); return
        end
        local latest=read(requestPath)
        if not latest or latest.token ~= request.token or latest.cancelled then
            finish("cancelled", "Transfer cancelled by main account"); return
        end
        if mainRecord.token == request.token and mainRecord.phase == "complete" then
            finish("complete", "Transfer complete; returning to farming"); return
        end
        if mainRecord.token == request.token and (mainRecord.phase == "error" or mainRecord.phase == "cancelled") then
            finish("error", mainRecord.status or "Receiver stopped"); return
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
        active.holdCF=CFrame.new(mainRoot.Position+Vector3.new(3,0,0))
        root.CFrame=active.holdCF
        root.AssemblyLinearVelocity=Vector3.zero
        if not active.queue then
            active.queue,active.total=queueFor(request.scope,request.limit)
            active.index=1
        end
        local dropped=0
        for _, entry in ipairs(active.queue) do
            dropped=dropped+math.min(entry.amount, math.max(0,entry.initial-(inventory[entry.key] or 0)))
        end
        active.dropped=dropped
        while active.queue[active.index] do
            local entry=active.queue[active.index]
            local taken=math.max(0,entry.initial-(inventory[entry.key] or 0))
            if taken>=entry.amount then active.index=active.index+1 else break end
        end
        local entry=active.queue[active.index]
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
            finish("error", "Server refused item " .. stackKey.item(entry.key) .. "; remaining inventory kept"); return
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
                if request and request.jobId==game.JobId and request.mainId==mainId
                    and request.sourceId==player.UserId and request.altSession==session
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
                if now-active.started>1800 then finish("error","Transfer timed out; remaining items kept")
                elseif isMain then mainStep(root,now) else altStep(root,now) end
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
