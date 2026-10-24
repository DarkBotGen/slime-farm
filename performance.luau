-- Alt-only graphics reduction. Keep gameplay instances and replication intact.
return function(farm)
    local player = game:GetService("Players").LocalPlayer
    local mode: any = {enabled=false, skippedMain=false, changed=0, fpsCap=30}
    -- Check the immutable user ID before changing settings or subscribing to events.
    if player.UserId == 1407091060 then
        mode.skippedMain=true
        function mode.stop() end
        return mode
    end
    setthreadidentity(8)
    local Run = game:GetService("RunService")
    local stopped=false
    local connections={}
    local originals=setmetatable({}, {__mode="k"})
    local oldCap=getfpscap()
    local function change(object: any, property, value)
        pcall(function()
            if object[property]==value then return end
            local properties=originals[object]
            if not properties then properties={};originals[object]=properties end
            if not properties[property] then properties[property]={before=object[property],applied=value} end
            object[property]=value
            mode.changed+=1
        end)
    end
    local function reduce(object)
        if stopped then return end
        if object:IsA("BasePart") then
            change(object,"CastShadow",false)
        elseif object:IsA("Decal") or object:IsA("Texture") then
            change(object,"Texture","")
        elseif object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam")
            or object:IsA("Smoke") or object:IsA("Fire") or object:IsA("Sparkles")
            or object:IsA("Light") or object:IsA("PostEffect") then
            change(object,"Enabled",false)
        elseif object:IsA("Sound") then
            change(object,"Volume",0)
            change(object,"Playing",false)
        elseif object:IsA("SurfaceAppearance") then
            change(object,"ColorMap","")
            change(object,"NormalMap","")
            change(object,"MetalnessMap","")
            change(object,"RoughnessMap","")
        elseif object:IsA("SpecialMesh") then
            change(object,"TextureId","")
        elseif object:IsA("Clouds") then
            change(object,"Enabled",false)
        end
        if object:IsA("MeshPart") then change(object,"TextureID","") end
    end
    local lighting=game:GetService("Lighting")
    change(lighting,"GlobalShadows",false)
    change(workspace.Terrain,"WaterWaveSize",0)
    change(workspace.Terrain,"WaterWaveSpeed",0)
    change(workspace.Terrain,"WaterReflectance",0)
    change(game:GetService("SoundService"),"AmbientReverb",Enum.ReverbType.NoReverb)
    pcall(function() change(settings().Rendering,"QualityLevel",Enum.QualityLevel.Level01) end)
    local ok=pcall(function() Run:Set3dRenderingEnabled(false) end)
    mode.renderingDisabled=ok
    pcall(function() setfpscap(mode.fpsCap) end)
    mode.enabled=true
    -- Subscribe before the initial scan so newly streamed instances are covered.
    -- These signals do no per-frame scanning or property re-enforcement.
    table.insert(connections,workspace.DescendantAdded:Connect(reduce))
    table.insert(connections,lighting.DescendantAdded:Connect(reduce))
    task.spawn(function()
        local objects=workspace:GetDescendants()
        for _,object in ipairs(lighting:GetDescendants()) do table.insert(objects,object) end
        for i,object in ipairs(objects) do
            if stopped then return end
            reduce(object)
            if i%200==0 then task.wait() end
        end
        mode.scanComplete=true
    end)
    function mode.stop()
        if stopped then return end
        stopped=true
        for _,connection in ipairs(connections) do connection:Disconnect() end
        for object,properties in pairs(originals) do
            for property,values in pairs(properties) do
                pcall(function()
                    if object[property]==values.applied then object[property]=values.before end
                end)
            end
        end
        table.clear(originals)
        pcall(function() Run:Set3dRenderingEnabled(true) end)
        pcall(function() setfpscap(if oldCap>0 then oldCap else 60) end)
        mode.enabled=false
    end
    -- Farm cleanup restores graphics; turning farming off alone keeps alts economical.
    farm.performance=mode
    return mode
end
