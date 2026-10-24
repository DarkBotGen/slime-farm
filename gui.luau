-- Luna UI. The library is discontinued; its current API was tested with Real.
return function(farm, control)
    setthreadidentity(8)
    local env=getgenv()
    if env.__SlimeLunaTest then pcall(function()env.__SlimeLunaTest:Destroy()end);env.__SlimeLunaTest=nil end
    env.ConfirmLuna=true
    local Luna=loadstring(game:HttpGet("https://raw.githubusercontent.com/Nebula-Softworks/Luna-Interface-Suite/master/source.lua"))()
    local player=game:GetService("Players").LocalPlayer
    local window=Luna:CreateWindow({Name="Slime Farm",Subtitle=player.Name,LoadingEnabled=false,KeySystem=false})
    local tab=window:CreateTab({Name="Farm",Icon="home",ImageSource="Material",ShowTitle=true})
    tab:CreateToggle({Name="Automatic farming",CurrentValue=farm.enabled,Callback=function(value)farm.setEnabled(value)end})
    tab:CreateToggle({Name="Collect shinies and flowers",CurrentValue=farm.collect,Callback=function(value)farm.collect=value end})
    tab:CreateToggle({Name="Anti-AFK",CurrentValue=farm.antiAfk,Callback=function(value)farm.antiAfk=value end})
    tab:CreateParagraph({Title="Slime priority",Text="Orange > Pink > Blue > Green. Underground farming and automatic HUB portal return. F6 toggles farming; F7 toggles collection."})
    local stats=tab:CreateParagraph({Title="Live status",Text="Starting..."})
    local transfer=window:CreateTab({Name="Transfers",Icon="swap_horiz",ImageSource="Material",ShowTitle=true})
    transfer:CreateParagraph({Title="Main account: RobotTifaski",Text="Run this script on each participating client in the same server and Real workspace. One alt transfers at a time; both accounts resume farming afterward."})
    local selected=nil
    local scope="Farm loot"
    local dropdown=nil
    if control.isMain then
        local options=control.listAlts()
        if #options==0 then options={"No connected alts"} end
        selected=options[1]
        dropdown=transfer:CreateDropdown({Name="Select alt account",Options=options,CurrentOption=selected,MultipleOptions=false,Callback=function(value)selected=type(value)=="table" and value[1] or value end})
        transfer:CreateButton({Name="Refresh connected alts",Callback=function()
            local values=control.listAlts()
            if #values==0 then values={"No connected alts"}end
            selected=values[1]
            dropdown:Set({Options=values,CurrentOption=selected})
        end})
        transfer:CreateDropdown({Name="Items to transfer",Options={"Farm loot","All backpack items"},CurrentOption=scope,MultipleOptions=false,Callback=function(value)scope=type(value)=="table" and value[1] or value end})
        transfer:CreateParagraph({Title="Transfer contents",Text="Farm loot: all slime gels, shinies, and flowers. All backpack items: also blocks, seeds, machines, and spare equipment. Starter tools are kept. Items are dropped one at a time and picked up by RobotTifaski."})
        transfer:CreateButton({Name="Transfer selected alt to main",Description="Visits your island and drops the selected inventory for collection.",Callback=function()
            local ok,message=control.requestTransfer(selected,scope)
            if not ok then control.status=message end
        end})
    else
        transfer:CreateParagraph({Title="Alt receiver enabled",Text="Select " .. player.Name .. " in RobotTifaski's Transfers tab to start. This account will pause farming, visit the main island, and transfer its selected inventory."})
    end
    transfer:CreateButton({Name="Cancel transfer",Callback=control.cancel})
    local status=transfer:CreateParagraph({Title="Transfer status",Text="Idle"})
    tab:CreateButton({Name="Stop script and close GUI",Callback=farm.stop})
    local api={}
    function api.update()
        local count,ready=control.getInventorySummary()
        stats:Set({Title="Live status",Text=string.format("%s\nSlimes: %d | Flowers: %d | Shinies: %d\nInventory: %d%s | Anti-AFK events: %d",farm.mode,farm.kills,farm.flowers,farm.shinies,count,ready and "" or " (syncing)",farm.antiAfkEvents or 0)})
        status:Set({Title="Transfer status",Text=control.status})
    end
    function api.destroy()Luna:Destroy()end
    control.attachGUI(api)
    return api
end
