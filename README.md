# Slime farm

Two tabs only: **Autofarm** and **Transfer**.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/DarkBotGen/slime-farm/main/slime-farm.luau"))()
```

## Autofarm

Toggle farming in the Autofarm tab. It keeps the existing underground slime farming, orange > pink > blue > green priority, event-driven target switching, HUB portal recovery, shiny/flower collection, and built-in anti-AFK. Server damage cooldowns still apply.

## Manual transfer

There are **no automatic transfer timers, schedules, or saved scheduling settings**.

1. Join RobotTifaski and your alts to the same Roblox server.
2. Run the script on each participating account in the same Real workspace.
3. On RobotTifaski, open Transfer and press **TRANSFER ALL ALTS TO MAIN**.

The connected alts visit RobotTifaski's island and deposit whole stacks into its Large Chest. RobotTifaski automatically uses the chest's collect-all action throughout the transfer, moving the items into the main backpack and freeing chest space.

Deposits prioritize orange gels, pink gels, blue gels, green gels, then remaining items. Weapons and tools (including buckets, plows, watering cans, and pollinators) remain on the alts. Each alt verifies its remaining eligible inventory and resumes farming independently after its deposits have been collected. No items are dropped on the ground.

The main script grants participating alts Trusted Builder and full available island/storage permissions during transfer setup. A Large Chest must be placed on the main island. The vending machine is not used or modified. Blocked deposits wait/retry; Cancel stops further transfers. Items already collected stay in the main backpack, and anything still in the chest remains there until collected.

The main account is RobotTifaski, user ID 1407091060. Coordination requires the same server and shared local Real workspace; it does not control accounts on other computers.

## Discord gel rates

Optional reporting reads `slime-farm-webhook/settings.json` from the local Real workspace. Keep credentials out of this repository. Settings use `enabled`, `url`, and `intervalSeconds` (minimum 60). All participating accounts must use the same Real workspace; they can farm in different servers. One elected account updates one Discord message with combined pink, blue, green, and orange gels per hour, plus estimated sale value per hour. Prices: pink 40,000, blue 1,500, green 1,500, orange 10,000 coins each. These are user-supplied estimates, not actual sale receipts.

For the dark PNG dashboard, run the local `SlimeChartRenderer.exe` once on the shared computer. It listens only on `127.0.0.1:17384`, draws a chart once per report, and receives only numeric yield data. It never reads webhook credentials. Charts show one-minute samples scaled to hourly yields; summary cards show the rolling average. The four gel charts and total estimated sale-value chart replace the previous image in the same Discord message. Without the helper, text rates and sale estimates still update. No third-party chart provider is used. Restart the helper after restarting Windows; it does not install a startup task.

Build the helper from `SlimeChartRenderer.cs` using the Windows .NET Framework C# compiler with references to `System.Drawing.dll` and `System.Web.Extensions.dll`, target `winexe`.

The report uses a rolling hour of positive inventory gains while farming inside HUB, excluding paused farming and chest transfers. Existing inventory is the baseline, not earnings. During the first hour, the observed session rate is extrapolated. Measurements survive reloads/rejoins locally. This measures observed farming gains; manually receiving gels while actively farming in HUB also counts. New computers require their own local settings.

## Alt resource savings

All accounts except RobotTifaski (immutable user ID 1407091060) use alt performance mode: 3D rendering off, 30 FPS cap, lowest engine quality, shadows and visual effects disabled, texture references cleared where writable, and existing/new workspace sounds muted. Existing and newly streamed visual instances are handled without repeated full-world scans. Gameplay parts, meshes, remotes, prompts, scripts, and streaming remain intact. The main-account guard runs before any graphics or FPS change.

Stopping the whole farm with `getgenv().SlimeFarm.stop()` restores settings modified by performance mode. `getgenv().SlimeFarm.performance.stop()` restores graphics while leaving farming running. Reloading the farm reapplies alt mode. The Autofarm toggle pauses farming while keeping resource savings enabled. The GUI still has only Autofarm and Transfer tabs.

The 30 FPS cap reduces attack requests to roughly 30 per second, while actual hits remain server limited. It was verified that an optimized live alt continued killing slimes. This primarily reduces graphics/rendering work; the script cannot purge Roblox's asset cache or change the game's Studio-only streaming settings, and it does not claim a fixed RAM reduction.

## Validation

The chest supports bulk deposits. Tests covered a concurrent 22-item deposit, and a later 9-item deposit-and-auto-collect transfer with all nine verified in the main backpack. The collector also cleared pre-existing chest contents. Tool exclusion and independent alt completion were checked. The final manual-only controller and two-tab Luna GUI pass Real's script diagnostics. Long-duration idle prevention and every possible capacity scenario have not been exhaustively tested.

The UI uses [Luna Interface Suite](https://github.com/Nebula-Softworks/Luna-Interface-Suite), discontinued by its authors in April 2025.
