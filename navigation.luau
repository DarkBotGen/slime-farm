-- Ordinary Humanoid locomotion only. No position, velocity, speed or collision writes.
return function(farm, context)
    local player=game:GetService("Players").LocalPlayer
    local Paths=game:GetService("PathfindingService")
    local input=context.loadModule(context.controllers:WaitForChild("InputController"))
    local controls=nil
    local playerModule=player.PlayerScripts:FindFirstChild("PlayerModule")
    if playerModule then pcall(function() controls=context.loadModule(playerModule):GetControls() end) end
    local nav: any={status="Idle",replans=0,failures=0}
    local stopped,active,ownSprint,computing=false,false,false,false
    local epoch=0
    local path,blockedConnection=nil,nil
    local waypoints,index={},1
    local currentRoot,goal,plannedGoal=nil,nil,nil
    local lastPlan,lastCommand,lastJump=-10,-10,-10
    local lastPosition,lastProgress=nil,0
    local function disconnectPath()
        if blockedConnection then blockedConnection:Disconnect();blockedConnection=nil end
        if path then path:Destroy();path=nil end
        waypoints={};index=1
    end
    local function sprint(wanted)
        if wanted and not input.sprinting then
            if not ownSprint then input.toggleSprintButton();ownSprint=true end
        elseif not wanted and ownSprint then
            if input.sprinting then input.toggleSprintButton() end
            ownSprint=false
        end
    end
    local function activate()
        if active then return end
        if controls then controls:Disable() end
        active=true
    end
    function nav.pause()
        epoch+=1
        disconnectPath()
        goal,plannedGoal=nil,nil
        sprint(false)
        if active then
            local character=player.Character
            local humanoid=character and character:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid:Move(Vector3.zero,false) end
            if controls then controls:Enable() end
        end
        active=false
        nav.status="Idle"
    end
    local function ground(position)
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Exclude
        local exclude={}
        for _,account in ipairs(game:GetService("Players"):GetPlayers()) do
            if account.Character then table.insert(exclude,account.Character) end
        end
        local hub=workspace:FindFirstChild("Hub")
        local enemies=hub and hub:FindFirstChild("Guardians")
        if enemies then table.insert(exclude,enemies) end
        params.FilterDescendantsInstances=exclude
        params.RespectCanCollide=true
        params.IgnoreWater=true
        local cfg=context.config
        local from=position+Vector3.new(0,2,0)
        if cfg then
            local relative=position-cfg.Hub.Origin
            local half=cfg.Hub.SizeStuds*0.5
            if math.abs(relative.X)<=half.X+40 and math.abs(relative.Z)<=half.Z+40 then
                params.FilterType=Enum.RaycastFilterType.Include
                params.FilterDescendantsInstances={workspace.Terrain}
                from=Vector3.new(position.X,cfg.Hub.Origin.Y+128,position.Z)
            end
        end
        local hit=workspace:Raycast(from,Vector3.new(0,-384,0),params)
        return hit and hit.Position+Vector3.new(0,0.1,0) or nil
    end
    local function plan(root,humanoid,destination,now)
        if computing or now-lastPlan<0.8 then return end
        computing=true
        lastPlan=now
        local generation=epoch
        local origin=root.Position
        task.spawn(function()
            local candidate
            local ok=pcall(function()
                local endpoint=ground(destination)
                if not endpoint then return end
                candidate=Paths:CreatePath({AgentRadius=2,AgentHeight=math.max(5,math.ceil(humanoid.HipHeight*2+root.Size.Y)),
                    AgentCanJump=true,AgentCanClimb=true,WaypointSpacing=4,Costs={Water=math.huge}})
                candidate:ComputeAsync(origin,endpoint)
            end)
            computing=false
            if stopped or generation~=epoch or currentRoot~=root or not goal
                or (goal-destination).Magnitude>8 then
                if candidate then candidate:Destroy() end
                return
            end
            nav.replans+=1
            if ok and candidate and candidate.Status==Enum.PathStatus.Success then
                disconnectPath()
                path=candidate
                waypoints=candidate:GetWaypoints()
                index=math.min(2,#waypoints)
                plannedGoal=destination
                nav.status="Following path"
                blockedConnection=candidate.Blocked:Connect(function(blockedIndex)
                    if blockedIndex>=index then plannedGoal=nil;lastPlan=-10 end
                end)
            else
                if candidate then candidate:Destroy() end
                nav.failures+=1
                nav.status="No walkable path; retrying"
                if not path then humanoid:Move(Vector3.zero,false) end
            end
        end)
    end
    function nav.seek(root,humanoid,destination,radius,now)
        if stopped then return false end
        activate()
        if currentRoot~=root then
            epoch+=1;disconnectPath()
            currentRoot=root;plannedGoal=nil;lastPlan=-10
            lastPosition=root.Position;lastProgress=now
        end
        if not goal or (goal-destination).Magnitude>10 then
            epoch+=1;disconnectPath();plannedGoal=nil
        end
        goal=destination
        if root.Anchored or humanoid.Health<=0 then sprint(false);nav.status="Waiting for character";return false end
        local horizontal=Vector3.new(destination.X-root.Position.X,0,destination.Z-root.Position.Z).Magnitude
        if horizontal<=radius and math.abs(destination.Y-root.Position.Y)<=8 then
            humanoid:Move(Vector3.zero,false)
            sprint(false)
            nav.status="In range"
            return true
        end
        sprint(true)
        if not plannedGoal or (plannedGoal-destination).Magnitude>4 or index>#waypoints then
            plan(root,humanoid,destination,now)
        end
        if lastPosition and (root.Position-lastPosition).Magnitude>1 then
            lastPosition=root.Position;lastProgress=now
        elseif now-lastProgress>2 then
            plannedGoal=nil
            if now-lastJump>2 and humanoid.FloorMaterial~=Enum.Material.Air then
                humanoid.Jump=true;lastJump=now
            end
            lastProgress=now
        end
        local waypoint=waypoints[index]
        while waypoint do
            local delta=waypoint.Position-root.Position
            if Vector3.new(delta.X,0,delta.Z).Magnitude>2 or math.abs(delta.Y)>5 then break end
            index+=1;waypoint=waypoints[index]
        end
        if waypoint and now-lastCommand>=0.15 then
            lastCommand=now
            if waypoint.Action==Enum.PathWaypointAction.Jump and humanoid.FloorMaterial~=Enum.Material.Air then
                humanoid.Jump=true
            end
            humanoid:MoveTo(waypoint.Position)
        end
        return false
    end
    function nav.stop()
        if stopped then return end
        nav.pause()
        stopped=true
    end
    return nav
end
