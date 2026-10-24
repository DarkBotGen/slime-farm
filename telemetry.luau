-- Shared Real workspace aggregation. Webhook credentials are read locally only.
return function(farm, context)
    local Http = game:GetService("HttpService")
    local player = game:GetService("Players").LocalPlayer
    local R, config = context.remotes, context.config
    local ids = {"PinkSlimeGel", "BlueSlimeGel", "SlimeGel", "OrangeSlimeGel"}
    local names = {"Pink", "Blue", "Green", "Orange"}
    local prices = {40000,1500,1500,10000}
    local prefix = "slime-farm-webhook/"
    local directory = prefix .. "accounts/" .. tostring(game.GameId) .. "/"
    local path = directory .. player.UserId .. ".json"
    local function read(file)
        local ok, value = pcall(function() return Http:JSONDecode(readfile(file)) end)
        return if ok and type(value) == "table" then value else nil
    end
    local function write(file, value) writefile(file, Http:JSONEncode(value)) end
    local now = os.time()
    local record = read(path) or {startedAt=now, buckets={}}
    record.userId = player.UserId
    record.buckets = record.buckets or {}
    local baseline = nil
    local stopped, busy = false, false
    local lastPublish, lastSync, retryAt = 0, -10, 0
    local started = os.clock()
    local telemetry: any = {status="Starting", rates={0,0,0,0}}
    local connections = {}
    local function aggregate(records, timestamp)
        local totals = {0,0,0,0}
        local beginning = timestamp
        for _, entry in ipairs(records) do
            beginning = math.min(beginning, tonumber(entry.startedAt) or timestamp)
            for bucket, values in pairs(entry.buckets or {}) do
                local stamp = tonumber(bucket) or 0
                if stamp > timestamp-3600 and stamp <= timestamp then
                    for i=1,4 do totals[i] += math.max(0, tonumber(values[i]) or 0) end
                end
            end
        end
        local duration = math.clamp(timestamp-beginning, 1, 3600)
        for i=1,4 do totals[i] = totals[i]*3600/duration end
        return totals
    end
    telemetry.calculate = aggregate
    local function publish(timestamp)
        for bucket in pairs(record.buckets) do
            if (tonumber(bucket) or 0) <= timestamp-3600 then record.buckets[bucket]=nil end
        end
        record.updated = timestamp
        write(path, record)
    end
    table.insert(connections, R.get(R.InventoryChanged).OnClientEvent:Connect(function(items)
        if type(items) ~= "table" then return end
        local counts = {}
        for i,id in ipairs(ids) do counts[i]=tonumber(items[id]) or 0 end
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local eligible = false
        if root and root:IsA("BasePart") then
            local relative = root.Position-config.Hub.Origin
            local half = config.Hub.SizeStuds*0.5
            eligible = farm.enabled and not farm.transferBusy
                and math.abs(relative.X)<=half.X+40 and math.abs(relative.Z)<=half.Z+40
                and math.abs(relative.Y)<=160
        end
        if baseline and eligible then
            local key = tostring(math.floor(os.time()/10)*10)
            local gains = record.buckets[key] or {0,0,0,0}
            for i=1,4 do gains[i] += math.max(0, counts[i]-baseline[i]) end
            record.buckets[key]=gains
        end
        baseline=counts
    end))
    local function report(timestamp)
        local settings = read(prefix .. "settings.json")
        if not settings or not settings.enabled then telemetry.status="Disabled";return end
        local endpoint = tostring(settings.url or ""):match("^(https://discord%.com/api/webhooks/%d+/[%w_-]+)")
        if not endpoint then telemetry.status="Webhook missing";return end
        local records, leader, activeAccounts = {}, math.huge, 0
        for _,file in ipairs(listfiles(directory)) do
            local entry = read(file)
            if entry and type(entry.userId)=="number" then
                table.insert(records,entry)
                if timestamp-(tonumber(entry.updated) or 0)<25 then
                    activeAccounts+=1
                    if entry.userId==1407091060 then leader=1407091060
                    elseif leader~=1407091060 then leader=math.min(leader,entry.userId) end
                end
            end
        end
        telemetry.rates=aggregate(records,timestamp)
        telemetry.accounts=activeAccounts
        telemetry.moneyPerHour=0
        for i=1,4 do telemetry.moneyPerHour+=telemetry.rates[i]*prices[i] end
        if leader~=player.UserId then telemetry.status="Reporting through leader";return end
        local statePath=prefix .. "message.json"
        local state=read(statePath) or {}
        local endpointId=endpoint:match("/webhooks/(%d+)/")
        if state.endpointId~=endpointId then state={} end
        local interval=math.max(60,tonumber(settings.intervalSeconds) or 60)
        if timestamp-(tonumber(state.lastSent) or 0)<interval or timestamp<retryAt then return end
        local lines={}
        for i,name in ipairs(names) do
            table.insert(lines,string.format("%s gels: **%.0f / hour**",name,telemetry.rates[i]))
        end
        table.insert(lines,string.format("Estimated sale value: **%.0f coins / hour**",telemetry.moneyPerHour))
        local payload: any={content=table.concat(lines,"\n"),allowed_mentions={parse={}}}
        local contentType="application/json"
        local body
        -- A single local helper draws the chart once a minute for all clients.
        -- Only numeric yield data goes to loopback; credentials stay in this process.
        local chartOK=pcall(function()
            local beginning=timestamp
            for _,entry in ipairs(records) do beginning=math.min(beginning,tonumber(entry.startedAt) or timestamp) end
            beginning=math.max(timestamp-3600,beginning)
            local series={}
            local firstMinute=math.floor(beginning/60)*60
            local lastMinute=math.floor(timestamp/60)*60
            for minute=firstMinute,lastMinute,60 do
                local values={0,0,0,0}
                for _,entry in ipairs(records) do
                    for bucket,gains in pairs(entry.buckets or {}) do
                        local stamp=tonumber(bucket) or 0
                        if stamp>=minute and stamp<minute+60 and stamp>timestamp-3600 then
                            for i=1,4 do values[i]+=math.max(0,tonumber(gains[i]) or 0) end
                        end
                    end
                end
                local seconds=math.max(1,math.min(timestamp,minute+60)-math.max(beginning,minute))
                for i=1,4 do values[i]=values[i]*3600/seconds end
                table.insert(series,values)
            end
            local result=request({Url="http://127.0.0.1:17384/render",Method="POST",
                Headers={["Content-Type"]="application/json"},
                Body=Http:JSONEncode({rates=telemetry.rates,series=series,timestamp=timestamp,start=beginning,accounts=activeAccounts})})
            assert(type(result)=="table" and result.StatusCode==200,"Renderer unavailable")
            local png=base64decode(Http:JSONDecode(result.Body).png)
            assert(#png>8 and png:sub(2,4)=="PNG","Invalid PNG")
            payload.attachments={{id=0,filename="slime-rates.png"}}
            payload.embeds={{title="Slime farming dashboard",color=11462769,image={url="attachment://slime-rates.png"}}}
            local boundary="SlimeChart" .. Http:GenerateGUID(false):gsub("-","")
            contentType="multipart/form-data; boundary=" .. boundary
            body="--"..boundary.."\r\nContent-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json\r\n\r\n"
                ..Http:JSONEncode(payload).."\r\n--"..boundary.."\r\nContent-Disposition: form-data; name=\"files[0]\"; filename=\"slime-rates.png\"\r\nContent-Type: image/png\r\n\r\n"
                ..png.."\r\n--"..boundary.."--\r\n"
        end)
        telemetry.chartAvailable=chartOK
        if not chartOK then
            payload.attachments=nil
            payload.embeds=nil
            body=Http:JSONEncode(payload)
            contentType="application/json"
        end
        local url=endpoint .. (if state.messageId then "/messages/" .. tostring(state.messageId) else "?wait=true")
        local ok,response=pcall(request, {Url=url,Method=if state.messageId then "PATCH" else "POST",
            Headers={["Content-Type"]=contentType},Body=body})
        if stopped then return end
        if not ok or type(response)~="table" then telemetry.status="Network error";retryAt=timestamp+60;return end
        local code=response.StatusCode
        telemetry.httpStatus=code
        if code>=200 and code<300 then
            local decoded
            pcall(function() decoded=Http:JSONDecode(response.Body) end)
            state.messageId=state.messageId or (decoded and decoded.id)
            state.endpointId=endpointId
            state.lastSent=timestamp
            write(statePath,state)
            telemetry.status="Reporting"
        elseif code==404 and state.messageId then
            write(statePath,{})
            telemetry.status="Recreating message"
        elseif code==429 then
            local delay=60
            pcall(function() delay=math.max(1,tonumber(Http:JSONDecode(response.Body).retry_after) or 60) end)
            retryAt=timestamp+delay
            telemetry.status="Rate limited"
        else
            retryAt=timestamp+60
            telemetry.status="HTTP " .. tostring(code)
        end
    end
    table.insert(connections,game:GetService("RunService").Heartbeat:Connect(function()
        if stopped then return end
        local clock=os.clock()
        if not baseline and clock-lastSync>=5 then
            lastSync=clock
            R.get(R.RequestSync):FireServer()
        end
        if clock-lastPublish<5 then return end
        lastPublish=clock
        local timestamp=os.time()
        local ok=pcall(publish,timestamp)
        if not ok then telemetry.status="Local write error";return end
        if busy or clock-started<10 then return end
        busy=true
        task.spawn(function()
            local success=pcall(report,timestamp)
            if not success then telemetry.status="Report error" end
            busy=false
        end)
    end))
    function telemetry.stop()
        stopped=true
        for _,connection in ipairs(connections) do connection:Disconnect() end
        pcall(publish,os.time())
    end
    return telemetry
end
