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

## Validation

The chest supports bulk deposits. Tests covered a concurrent 22-item deposit, and a later 9-item deposit-and-auto-collect transfer with all nine verified in the main backpack. The collector also cleared pre-existing chest contents. Tool exclusion and independent alt completion were checked. The final manual-only controller and two-tab Luna GUI pass Real's script diagnostics. Long-duration idle prevention and every possible capacity scenario have not been exhaustively tested.

The UI uses [Luna Interface Suite](https://github.com/Nebula-Softworks/Luna-Interface-Suite), discontinued by its authors in April 2025.
