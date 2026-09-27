# Fill the Store! 🛒

A bright, simple Roblox shop game prototype built around one loop:

**Delivery arrives → grab a box → carry it in → open it → stock shelves → customers buy → earn £ → upgrade → repeat**

## Play it

1. Open **`FillTheStore.rbxlx`** in Roblox Studio.
2. Press **Play**.

The world (road, six plots, shops) is built by scripts when the server starts, so the Workspace looks empty in edit mode. That's expected.

What a new player sees in their first minute:

- They spawn in front of their own **Corner Shop**. A delivery van pulls up a few seconds later and throws boxes onto the yellow **loading bay**.
- A hint at the bottom of the screen, plus a bouncing arrow and a glowing line, show the next step: *Grab a delivery box → Carry it into your shop → Open the box → Stock your shelves*.
- Customers walk in, fill their baskets from the shelves, queue at the till and pay. You see **+£** popups and your cash counts up.
- **UPGRADES** lights up when you can afford something.

### Enabling saving

Saving uses DataStoreService and needs a published place:

1. **File → Publish to Roblox**.
2. **Game Settings → Security → Enable Studio Access to API Services** (only needed for testing saves in Studio).

Without these the game still runs normally. It prints one warning (`Progress will NOT be saved this session`) and plays without saving.

Also recommended: set **Max Players to 6** in Game Settings, since there are 6 shops per server.

## What's in the game

| System | Details |
|---|---|
| Plots | 6 shops per server (3 on each side of a road), one per player, with the owner's name on the sign and floating above the shop |
| Deliveries | A van arrives every 20–28s and throws 3+ boxes onto your loading bay (up to 12 can wait there). The tape colour hints at the rarity of what's inside |
| Boxes | **E — Pick Up Box**, carried in front of you with your arms out. **E — Open Box** only appears once you're inside your shop. Opening plays a shake / flaps / products-pop-out animation and a **DELIVERY OPENED!** card |
| Products | 14 products, from Water (£3) to Television (£700). Pricier ones appear in deliveries as your shop grows |
| Rare variants | Each unit rolls **Golden ×10**, **Rainbow ×100** or **Giant ×625** (Cola £8 → £80 → £800 → £5,000). Rares sparkle, rainbow items cycle colours, giants are big, and you get a **✨ RAINBOW COLA!** banner |
| Stocking | **E — Stock Shelf** fills the shelf item by item, with a pop animation and a rising-pitch sound. A bar above each shelf shows how full it is (**EMPTY!** in red). The **STOCK** menu shows your stock room; tap a product to stock it first |
| Customers | Walk in, pick products off stocked shelves (items visibly disappear), queue at the till, pay you and leave. Show 😞 if the shelves run out before they get there |
| Upgrades | One menu: Shelf Capacity, Delivery Size, Customer Rate, Product Luck, Store Size, Workers. Prices rise per level |
| Expansion | Corner Shop (2 shelves) → Local Store (4) → Mini Supermarket (10). The shop is rebuilt bigger and keeps its stock |
| Workers | Staff NPCs walk to the emptiest shelf and restock it from your stock room |
| Other players | Can walk into your shop but can't use your prompts, boxes, shelves or upgrades. The server checks ownership on everything |
| Saving | Cash, upgrades, store level, stock room, what's on each shelf, and stats |

## Project layout (Rojo)

```
default.project.json          Rojo project → builds FillTheStore.rbxlx
src/shared/   → ReplicatedStorage.Shared      data + helpers used by both sides
  Config          all the tuning numbers (delivery times, speeds, prices...)
  Products        product list + rarities         ← add products here
  Variants        Golden / Rainbow / Giant
  Upgrades        upgrade definitions + formulas   ← add/tune upgrades here
  StoreLevels     shop sizes, shelf positions, NPC waypoints ← add store levels here
  Items           "Cola:Golden"-style item keys, prices, names
  ProductVisuals  builds each product's 3D model from Parts
  BoxVisual, Build, Format, Remotes, Signal, Sounds
src/server/   → ServerScriptService.Server
  Main.server     wires everything up (players joining/leaving, respawning)
  Services/
    PlayerData    DataStore load/save, cash, inventory (server-authoritative)
    Stores        claims plots, builds/rebuilds shops
    Deliveries    the van + delivery timer
    Boxes         box landing, pick up, carry, open
    Shelves       stocking, visible products, stock bars
    Customers     customer NPC behaviour
    Workers       staff NPCs
    UpgradeService purchases (validated on the server)
    Registry, Net, NpcMotion  shared state + helpers
  Builders/       WorldBuilder, StoreBuilder, TruckBuilder, NpcBuilder (all plain Parts)
src/client/   → StarterPlayerScripts.Client
  Main.client     creates the UI and starts the controllers
  Controllers/    HUD, UpgradesPanel, StockPanel, Notifications, Effects,
                  Guide (onboarding hints), Prompts (owner-only prompts), ...
tests/            headless play-test (see below)
```

**Security:** the client never sends money, prices or amounts. It only asks for things: "buy upgrade X", "prefer product Y", or a ProximityPrompt trigger. The server validates all of it (ownership, distance, being inside your shop, affordability).

### Common tweaks

- **Add a product:** add an entry to `Products.List` (pick a `Shape` from `ProductVisuals`, or add a new shape builder there).
- **Rebalance:** `Config.luau` (timings), `Upgrades.luau` (costs and effects), `Variants.luau` (rare chances).
- **Add a store level:** add an entry to `StoreLevels.Levels` and a cost in `Upgrades.Defs.StoreSize.Costs`. Waypoints are generated automatically, and `tests/layout.luau` checks the new layout.
- **Change sounds:** `Sounds.luau`. They currently use sounds built into the Roblox client, each with an automatic fallback, so they can be swapped for Creator Store IDs.

## Working on it

With [Rokit](https://github.com/rojo-rbx/rokit) (or install Rojo 7.4 + Lune 0.8 yourself):

```sh
rokit install
rojo serve                 # live-sync into Studio with the Rojo plugin
./scripts/check.sh         # build + run the headless checks + refresh FillTheStore.rbxlx
```

### Headless play-test

`tests/emulator/` is a small Roblox engine emulator for [Lune](https://lune-org.github.io/docs). It loads the built place file and runs the real server and client scripts on a virtual clock. It validates every property read and write against Roblox's API database, and simulates humanoid walking, welds, remotes, DataStores and prompts.

- `tests/playtest.luau` has a bot play like a new player: first box, first stocked shelf, first sale. It then runs five minutes of the loop, buying upgrades through the actual UI buttons. After that it covers store expansion, workers, a second player who can't touch your stuff, saving and rejoining, and Studio without API access.
- `tests/layout.luau` checks, for every store level, that customer/worker routes and queue spots don't pass through walls, shelves or the till, and that shelves don't overlap.

The emulator is not the real engine: it has no physics collisions, no rendering and no real network. It's a strong smoke test, not a replacement for a quick play in Studio.
