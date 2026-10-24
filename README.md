# Slime farm

Two tabs: **Autofarm** and **Transfer**. The current version walks above ground.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/DarkBotGen/slime-farm/main/slime-farm.luau"))()
```

## Walking and combat

The character follows Roblox PathfindingService waypoints with Humanoid:MoveTo(), using normal jump waypoints and replanning when a path is blocked, a target moves, or movement stalls. There is one path computation in flight per client, with an 0.8-second minimum between computations. Unreachable targets are retried later.

Sprinting uses the game's InputController.toggleSprintButton(), which sends the game's normal server-validated sprint request. The script does not change WalkSpeed, jump power, character position, velocity, or collisions. It does not load the underground guard. Normal player movement controls are suspended while following the route and restored on pause or stop.

Slime priority remains orange > pink > blue > green. The starter weapon is selected automatically. Attacks require the equipped sword's configured range and line of sight, follow AnimationController.playSwing(), and respect its readiness plus the configured weapon cooldown. Delayed hits recheck the current target, range, and line of sight before sending a request. It no longer sends attacks every frame.

Outside HUB, the script walks to the nearest streamed island HUB portal and lets the game's portal perform travel. It never moves the character directly to the trigger. Respawned characters are picked up automatically. If the previous script left a character underground, start from a normal above-ground respawn; this version will not reposition it out of the terrain.

Nearby shinies and mature flowers are reached on foot between slime targets. Interactions are sent only within ordinary interaction distance and with line of sight. F6 pauses farming and releases movement controls; F7 toggles collection. Built-in idle handling remains enabled.

## Transfer

Transfer travel is disabled in walking mode, and the GUI explains this. The retained legacy chest-transfer implementation is blocked before either its travel step or group-transfer request can run. There are no scheduled transfers.

## Alt resource savings

RobotTifaski (user ID 1407091060) is excluded before any graphics or FPS change. Other accounts use 3D rendering off, a 30 FPS cap, low engine quality, reduced textures/effects/shadows, and muted workspace audio. Rendering changes leave gameplay instances, normal character physics, and pathfinding intact. These changes cannot purge Roblox's asset cache or alter Studio-only streaming settings.

Stop all farming with getgenv().SlimeFarm.stop(). To restore an alt's graphics while leaving farming running, use getgenv().SlimeFarm.performance.stop().

## Discord reporting

Local Real workspace settings are in slime-farm-webhook/settings.json, with enabled, url, and intervalSeconds (minimum 60). Credentials must stay out of this repository. Participating accounts share one Real workspace and can be in different servers. A single elected reporter updates one Discord message with combined pink, blue, green, and orange gel rates and estimated sale value per hour.

Prices are user supplied: pink 40,000; blue 1,500; green 1,500; orange 10,000 coins per gel. Sale figures are estimates, not completed sales. Reporting counts positive inventory gains while actively farming in HUB, excludes the initial inventory baseline, and extrapolates until the first full hour. Manually receiving gels while farming in HUB also counts as gains.

Run SlimeChartRenderer.exe once on the shared computer for dark PNG charts. It listens only on 127.0.0.1:17384 and receives numeric yield data, without webhook credentials. Restart it after restarting Windows. Without it, text reporting continues. Build SlimeChartRenderer.cs as a .NET Framework winexe with System.Drawing.dll and System.Web.Extensions.dll references.

## Validation

The walking entrypoint, navigation module, transfer guard, and two-tab GUI pass Real's diagnostics. Mocked navigation checks cover normal sprint, jump waypoints, waypoint advancement, blocked-path replanning, arrival, movement-control cleanup, and cancelling/resuming an in-flight path computation. No walking farm was deployed or live combat tested for this change.

The previous teleporting/underground implementation was reported to have led to bans. Normal locomotion does not guarantee that automation is permitted or undetectable.

The UI uses [Luna Interface Suite](https://github.com/Nebula-Softworks/Luna-Interface-Suite), with a clean retained-template fallback for clients whose GetObjects returns an empty asset result.
