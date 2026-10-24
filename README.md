# Slime farm

Automatic hub return through the island portal, underground slime farming, and shiny/flower collection.

Priority: orange, pink, blue, green. Sends one attack request per frame; server damage cooldowns still apply.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/DarkBotGen/slime-farm/main/slime-farm.luau"))()
```

F6 toggles the farm. F7 toggles collection. Run separately in each client's executor. Portal travel and collection can bring the character above ground. This script does not make the character invisible.

Built-in anti-AFK listens for the local player's idle event and sends a VirtualUser right click. It remains enabled while farming is paused. Calling `getgenv().SlimeFarm.stop()` disconnects it; set `getgenv().SlimeFarm.antiAfk = false` to disable it separately. Runtime input failures appear in `SlimeFarm.antiAfkError`. Long-duration idle prevention has not been verified.

## Luna GUI and alt transfers

Run the same loader on RobotTifaski and each participating alt. The main account is identified by user ID `1407091060`. Clients must be in the same Roblox server and share the same Real workspace on this computer. This does not remotely control accounts on separate computers or accounts that are not running this script.

On RobotTifaski, open **Transfers**, click **Refresh connected alts**, select an alt, choose the contents, and click **Transfer selected alt to main**.

For a single-click group transfer, press **BRING ALL ALTS + DROP ALL ITEMS** at the top of RobotTifaski's Transfers tab. It immediately gathers every registered alt and starts concurrent transfer of all backpack items, without selecting accounts or enabling the concurrent-round toggle. An existing transfer must finish or be cancelled before starting another.

- **Farm loot:** slime gels, shinies, and flowers.
- **All backpack items:** all inventory stacks, including spare equipment, blocks, seeds, and machines. Starter tools are retained. Items refused by the server keep that alt at the transfer point with a visible waiting/retry status; use Cancel to stop it.

The main account goes home and waits. The selected alt visits the main island, pauses farming, and drops one item at a time. Each drop waits for an inventory acknowledgement, and dropping stops if the receiver disconnects or the transfer is cancelled. The main collects nearby loose items, acknowledges receipt, and both clients resume their previous farming setting. Selected-alt transfers run individually. Group rounds can use sequential or concurrent dropping.

Automatic transfer rounds are enabled by default, with **15 minutes between rounds**. RobotTifaski queues every connected alt and transfers **All backpack items**, regardless of the manual transfer selector. By default these are processed sequentially. Enable **Drop from all alts together** in the Transfers tab to make scheduled rounds and **Transfer all connected alts now** gather and drop from all registered alts concurrently. Each alt stands at a separate position around the receiver, and every item still uses its own acknowledged drop request. The main account accounts for received items per stack and acknowledges each empty alt independently. A completed alt resumes farming without waiting for the other alts. After the last queued alt finishes, the next 15-minute farming period begins. Adjust the interval in the Transfers tab, or disable automatic transfers with its toggle. The enabled setting and interval are saved in Real's shared workspace; the countdown starts again when the main account reloads the script. Cancelling clears the current round's queue and restarts the interval; it does not disable future rounds. The main client must remain connected and running the script.

The **Cancel transfer** button stops further drops; already dropped items remain on the island. The game's player-drop pickup policy allows anyone to pick up dropped items, so the transfer is not an atomic trade. The script does not change island permissions.

The GUI uses [Luna Interface Suite](https://github.com/Nebula-Softworks/Luna-Interface-Suite), which its authors discontinued in April 2025. The current API was verified in Real. Validation included island visits, item dropping/pickup, an exact three-item transfer with matching inventory gain, a concurrent three-alt transfer with nine total items and matching receiver inventory gain, cancellation, and clean script diagnostics. Long full-inventory transfers have not been exhaustively tested.


Drop order is orange gels, pink gels, blue gels, green gels, then remaining items. Before an unlimited transfer finishes, the alt refreshes its inventory and rescans for remaining transferable items. It does not return to farming merely because its original snapshot was exhausted. Starter tools remain excluded. Receiver or drop errors keep an incomplete alt waiting; explicit cancellation can return it to farming with remaining items.
