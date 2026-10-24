-- Two-tab manual-transfer UI.
return function(farm,control)
    setthreadidentity(8)
    local env=getgenv()
    env.ConfirmLuna=true
    local librarySource=game:HttpGet("https://raw.githubusercontent.com/Nebula-Softworks/Luna-Interface-Suite/master/source.lua")
    local Luna
    for attempt=1,3 do
        -- Some clients return an empty GetObjects result while retaining the
        -- previously loaded Luna screen. Reuse a clean clone of that asset.
        local uiRoot=gethui()
        local existing=uiRoot and uiRoot:FindFirstChild("Luna UI")
        if not env.SlimeFarmLunaTemplate and existing and existing:FindFirstChild("SmartWindow") then
            local template=existing:Clone()
            local main=template:FindFirstChild("SmartWindow")
            for _,container in ipairs({main:FindFirstChild("Elements"),main.Navigation:FindFirstChild("Tabs")}) do
                for _,name in ipairs({"Autofarm","Transfer"}) do
                    local old=container:FindFirstChild(name)
                    if old then old:Destroy() end
                end
            end
            env.SlimeFarmLunaTemplate=template
        end
        local source=librarySource
        if env.SlimeFarmLunaTemplate then
            local first,last=source:find('game:GetObjects("rbxassetid://86467455075715")[1]',1,true)
            if first then
                source=source:sub(1,first-1).."getgenv().SlimeFarmLunaTemplate:Clone()"..source:sub(last+1)
            end
        end
        local ok,value=pcall(function() return assert(loadstring(source))() end)
        if ok and value then Luna=value;break end
        if attempt<3 then task.wait(attempt) end
    end
    assert(Luna,"Luna UI asset unavailable after three attempts; farming continues")
    local player=game:GetService("Players").LocalPlayer
    local window=Luna:CreateWindow({Name="Slime Farm",Subtitle=player.Name,LoadingEnabled=false,KeySystem=false})
    local farmTab=window:CreateTab({Name="Autofarm",Icon="home",ImageSource="Material",ShowTitle=true})
    farmTab:CreateToggle({Name="Autofarm",CurrentValue=farm.enabled,Callback=function(value)farm.setEnabled(value)end})
    local farmStatus=farmTab:CreateParagraph({Title="Status",Text="Starting..."})
    local transferTab=window:CreateTab({Name="Transfer",Icon="swap_horiz",ImageSource="Material",ShowTitle=true})
    if farm.walkingOnly then
        transferTab:CreateParagraph({Title="Walking mode",Text="Chest transfer travel is disabled. This version walks above ground and does not use the old transfer teleports."})
    elseif control.isMain then
        transferTab:CreateButton({
            Name="TRANSFER ALL ALTS TO MAIN",
            Description="Bring connected alts to your island, deposit all non-tool items into the Large Chest, and collect everything into RobotTifaski's backpack.",
            Callback=function()
                local ok,message=control.requestParallel("All backpack items")
                if not ok then control.status=message end
            end,
        })
        transferTab:CreateParagraph({Title="Manual transfers only",Text="Join all accounts to the same server and run this script on each account. Press the transfer button when ready. There is no timer and no automatic transfer."})
    else
        transferTab:CreateParagraph({Title="Alt ready",Text="Join RobotTifaski's server and leave this script running. Start the transfer from RobotTifaski's Transfer tab. Farming resumes after your non-tool inventory is empty and the main has collected it."})
    end
    transferTab:CreateButton({Name="Cancel transfer",Callback=control.cancel})
    local transferStatus=transferTab:CreateParagraph({Title="Transfer status",Text="Idle"})
    local api={}
    function api.update()
        farmStatus:Set({Title="Status",Text=string.format("%s\nSlimes: %d | Flowers: %d | Shinies: %d",farm.mode,farm.kills,farm.flowers,farm.shinies)})
        local text=control.status
        if control.isMain then text=text .. "\nConnected alts: " .. table.concat(control.listAlts(),", ") end
        transferStatus:Set({Title="Transfer status",Text=text})
    end
    function api.destroy()Luna:Destroy()end
    control.attachGUI(api)
    return api
end
