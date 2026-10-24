# Slime farm

Underground slime farming, automatic HUB portal return, shiny/flower collection, anti-AFK, and Large Chest deposits from alts.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/DarkBotGen/slime-farm/main/slime-farm.luau"))()
```

Run the same loader on RobotTifaski (user ID 1407091060) and every participating alt. They must be in the same Roblox server and share the same Real workspace on this computer.

## Farming

Priority: orange, pink, blue, green. Target health reaching zero, target removal, and higher-priority spawns trigger immediate target selection. Attacks are sent every Heartbeat; server damage cooldowns still apply. F6 toggles farming, F7 toggles collection. Portal travel and collection can bring the character above ground; this does not make it invisible.

Anti-AFK listens for the player's idle event and uses VirtualUser. It stays enabled while farming is paused and disconnects when the script stops. Long-duration idle prevention has not been verified.

## Chest transfers

Place a Large Chest on RobotTifaski's island. On the main account open Transfers and press **BRING ALL ALTS + DEPOSIT IN CHEST**. Selected-alt transfers are also available. Automatic rounds run every 15 minutes by default, with optional concurrent depositing via **All alts deposit together**.

The main account verifies/grants participating alts Trusted Builder roles, full available island permissions, and storage Deposit/View/Withdraw permissions. It then reads the chest contents and authorizes deposits. The currently placed chest at cell 0,1,-2 was tested. If multiple Large Chests exist, the script chooses the first by cell key and retains that destination during the round.

Alts visit the main island and deposit whole stacks using RequestStorageStore. There is **no ground-drop fallback** and the vending machine is not used or modified.

Order: orange gels, pink gels, blue gels, green gels, then other eligible items. Pickaxes, axes, swords, starter tools, buckets, plows, watering cans, and pollinators stay on the alts. The final inventory is refreshed and rescanned so leftover non-tool items are not silently skipped.

Each alt independently resumes its previous farming setting after its eligible inventory is empty and the deposits are verified against chest updates. If the chest fills or a deposit is blocked, that alt waits and retries until space/access is available or the transfer is cancelled. Clearing items out of the chest can free space; receipt accounting tracks positive chest changes rather than just its net contents. Items stay in the chest; the script does not automatically withdraw them.

The chest has 24 configured slots. Do not assume an unlimited number of different item types will fit. Server storage rules control capacity and quantities.

Cancel stops further deposits and clears the pending round queue. Deposited items remain in the chest. After a complete round, a new interval starts. The main client's script must remain running; interval preferences are saved locally, and the countdown restarts when the main reloads.

## GUI and validation

The GUI uses [Luna Interface Suite](https://github.com/Nebula-Softworks/Luna-Interface-Suite), discontinued by its authors in April 2025. Its current API has been tested in Real.

Validation included full permission read-back for the three connected alts, a five-item bulk chest deposit, a concurrent three-alt chest transfer with 22 deposited and 22 verified items, tool-exclusion preview, independent alt completion, and clean script diagnostics. Long full-inventory/capacity scenarios have not been exhaustively tested.
