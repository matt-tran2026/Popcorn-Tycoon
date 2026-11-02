# Visual Overhaul Verification

Run on November 2, 2026, against the uncommitted overhaul on top of `a883e92`: mesh crops, stations and oaks (VisualTemplates), themed HUD and icons (UITheme), custom harvest prompts (PromptController), and countryside (EnvironmentVisuals).

## Setup

The repository was moved to `Obsidian Vault/Popcorn Tycoon/Popcorn Tycoon/`. Native Script Sync was reconnected to the same three roots (`src/shared`, `src/server` and `src/client`, selected as parents), with the Disk version kept. Studio held 13 scripts with no duplicates. Single-player runners were installed as temporary ServerScriptService scripts during Play, outside the sync roots, and destroyed afterwards. The multiplayer runner used a temporary Workspace probe and `ExecuteMultiplayerTestAsync(2, …)`, and was removed after its result was collected.

## Results

| Check | Result |
| --- | --- |
| Bootstrap | Farm, countryside and HUD built. No "Visual template unavailable" warnings; 42 MeshParts and 380 BaseParts on the plot. |
| StarterField runner | PASS 30/30, including real ten-second regrowth. |
| FarmPlot runner | PASS 31/31: Humanoid:MoveTo from the entrance through every row, all twelve harvested and credited exactly once. |
| Multiplayer runner | PASS 11/11 with two simulated clients. |
| Keyboard harvest | A real E key press gave Raw Corn 38 → 41, showed the "+3 Corn · Growing again!" banner, and reset the stalk to 0 available. |
| Custom prompt state | Own-farm prompts switch to Custom style. A `HarvestPrompt` BillboardGui is created with "E · Pick corn" and the stalk's ObjectText. |
| Inventory | Mouse click opens it, X closes it, and I toggles it open and closed. The panel shows the corn/popcorn totals and the equipped tool. |
| Sync equality | All 13 Studio sources match the disk files exactly (newline-normalised hash). Git status is unchanged. |
| Output | Only the bootstrap messages and PASS lines. No runtime errors. |
| Cleanup | No runtime farms, countryside or test runners remain in Edit. |

## Not verified and observations

- **Custom prompt visibility: user-confirmed.** The creator confirmed in Play that the "Pick corn" button renders above ripe stalks. The MCP screen capture does not draw BillboardGuis at all (a red control billboard was also invisible), and the mouse tool can't target billboard buttons (AbsolutePosition 0,0). So the button's click and `Activated` touch path remain untested by automation.
- **Prompt count while standing still: fixed.** The button text used to be built only on PromptShown, so it could read `1/3` after ObjectText reached `3/3`. PromptController now refreshes the text on ObjectText changes and disconnects that listener when the prompt hides. In Play, standing still after a harvest, the button read 1/3 → 2/3 → 3/3, matching ObjectText each time. At 0/3 the prompt hides, and the button moves to the next ripe stalk (Stalk_5) with its own correct count.
- **Future design (creator, Nov 2):** the corn's appearance should keep changing as it grows toward full capacity. Deferred to a later milestone.
- **Real touch, device performance and visual acceptance** from a normal camera are still manual checks. Phone and tablet layouts were inspected in an earlier session, not rerun here.
- **Place save/reopen and Script Sync resumption** after a Studio restart are unverified.
