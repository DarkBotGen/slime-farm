# Slime farm

Automatic hub return through the island portal, underground slime farming, and shiny/flower collection.

Priority: orange, pink, blue, green. Sends one attack request per frame; server damage cooldowns still apply.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/DarkBotGen/slime-farm/main/slime-farm.luau"))()
```

F6 toggles the farm. F7 toggles collection. Run separately in each client's executor. Portal travel and collection can bring the character above ground. This script does not make the character invisible.

Built-in anti-AFK listens for the local player's idle event and sends a VirtualUser right click. It remains enabled while farming is paused. Calling `getgenv().SlimeFarm.stop()` disconnects it; set `getgenv().SlimeFarm.antiAfk = false` to disable it separately. Runtime input failures appear in `SlimeFarm.antiAfkError`. Long-duration idle prevention has not been verified.
