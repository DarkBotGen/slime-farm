-- Constrain this script's movements. This is not server-side invisibility.
return function(farm, config)
    local player=game:GetService("Players").LocalPlayer
    local Run=game:GetService("RunService")
    local policy: any={depth=4, corrections=0, status="Starting"}
    local connections={}
    local collisions=setmetatable({}, {__mode="k"})
    local stopped=false
    local portalLease=nil
    local islands,cache={},{}
    local scanned=-10
    local function surface(position)
        local relative=position-config.Hub.Origin
        local half=config.Hub.SizeStuds*0.5
        if math.abs(relative.X)<=half.X+40 and math.abs(relative.Z)<=half.Z+40 then
            return config.Hub.Origin.Y
        end
        if os.clock()-scanned>1 then
            scanned=os.clock()
            table.clear(islands)
            for _,island in ipairs(workspace:GetChildren()) do
                local origin=island:GetAttribute("IslandOrigin")
                if typeof(origin)=="Vector3" then table.insert(islands,origin) end
            end
        end
        local best,distance=nil,350*350
        for _,origin in ipairs(islands) do
            local d=(origin.X-position.X)^2+(origin.Z-position.Z)^2
            if d<distance then best,distance=origin.Y,d end
        end
        return best
    end
    local function ceiling(position)
        local plane=surface(position)
        if not plane then policy.status="Unknown terrain; movement blocked";return nil end
        local key=math.floor(position.X/8)..":"..math.floor(position.Z/8)..":"..plane
        local entry=cache[key]
        if not entry or os.clock()-entry.at>0.5 then
            local params=RaycastParams.new()
            params.FilterType=Enum.RaycastFilterType.Exclude
            local exclude={}
            for _,account in ipairs(game:GetService("Players"):GetPlayers()) do
                if account.Character then table.insert(exclude,account.Character) end
            end
            local hub=workspace:FindFirstChild("Hub")
            local guardians=hub and hub:FindFirstChild("Guardians")
            if guardians then table.insert(exclude,guardians) end
            params.FilterDescendantsInstances=exclude
            params.RespectCanCollide=true
            local hit=workspace:Raycast(Vector3.new(position.X,plane+0.5,position.Z),Vector3.new(0,-192,0),params)
            entry={at=os.clock(),y=if hit then math.min(plane,hit.Position.Y) else plane}
            -- Keep the cache bounded during long sessions.
            local count=0
            for k,v in pairs(cache) do
                count+=1
                if os.clock()-v.at>2 then cache[k]=nil end
            end
            if count>128 then table.clear(cache) end
            cache[key]=entry
        end
        local depth=policy.depth
        local character=player.Character
        if character then
            -- Account for tall avatar accessories, not only root position.
            local ok,box,size=pcall(character.GetBoundingBox,character)
            local root=character:FindFirstChild("HumanoidRootPart")
            if ok and root and root:IsA("BasePart") then
                depth=math.max(depth,box.Position.Y+size.Y/2-root.Position.Y+0.75)
            end
        end
        return entry.y-depth
    end
    function policy.move(root, position, facing)
        if stopped or root.Anchored then return false end
        local limit=ceiling(position)
        if not limit then return false end
        local point=Vector3.new(position.X,math.min(position.Y,limit),position.Z)
        -- Stay upright; looking upward at slimes can tilt an avatar through a floor.
        local direction=facing and Vector3.new(facing.X-point.X,0,facing.Z-point.Z) or Vector3.new(0,0,-1)
        if direction.Magnitude<0.01 then direction=Vector3.new(0,0,-1) end
        root.CFrame=CFrame.lookAt(point,point+direction)
        root.AssemblyLinearVelocity=Vector3.zero
        root.AssemblyAngularVelocity=Vector3.zero
        policy.status="Below mapped terrain"
        return true
    end
    function policy.portalTouch(root, trigger, offset)
        if stopped or root.Anchored or not trigger:IsDescendantOf(workspace) then return false end
        local relative=trigger.Position-config.Hub.Origin
        local half=config.Hub.SizeStuds*0.5
        if math.abs(relative.X)<=half.X+40 and math.abs(relative.Z)<=half.Z+40 then return false end
        -- Only the portal's immediate trigger area gets a short exception.
        portalLease={root=root,trigger=trigger,expires=os.clock()+0.25}
        root.CFrame=CFrame.new(trigger.Position+offset)
        root.AssemblyLinearVelocity=Vector3.zero
        root.AssemblyAngularVelocity=Vector3.zero
        policy.status="Entering HUB portal"
        return true
    end
    local function enforce()
        if stopped then return end
        local character=player.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        if not root or not root:IsA("BasePart") or root.Anchored then return end
        if portalLease then
            if portalLease.root==root and os.clock()<portalLease.expires
                and portalLease.trigger:IsDescendantOf(workspace)
                and (root.Position-portalLease.trigger.Position).Magnitude<=12 then return end
            portalLease=nil
        end
        local limit=ceiling(root.Position)
        if not limit then return end
        for _,part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                collisions[part]=true
                part.CanCollide=false
            end
        end
        if root.Position.Y>limit then
            policy.corrections+=1
        end
        if math.abs(root.Position.Y-limit)>0.001 then
            policy.move(root,Vector3.new(root.Position.X,limit,root.Position.Z),root.Position+root.CFrame.LookVector)
        end
        -- Hold position even while farming is paused or no slime is available.
        root.AssemblyLinearVelocity=Vector3.zero
        root.AssemblyAngularVelocity=Vector3.zero
    end
    table.insert(connections,Run.PreSimulation:Connect(enforce))
    table.insert(connections,Run.Heartbeat:Connect(enforce))
    table.insert(connections,player.CharacterAdded:Connect(function(character)
        table.insert(connections,character.ChildAdded:Connect(function(child)
            if child.Name=="HumanoidRootPart" then enforce() end
        end))
        enforce()
    end))
    function policy.stop()
        if stopped then return end
        stopped=true
        for _,connection in ipairs(connections) do connection:Disconnect() end
        for part in pairs(collisions) do pcall(function() part.CanCollide=true end) end
        table.clear(collisions)
    end
    enforce()
    return policy
end
