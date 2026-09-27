# Fill the Store! 🛒

A bright, simple Roblox shop simulator built around one loop:

**Delivery arrives → grab a box → carry it to a shelf → customers buy → earn £ → upgrade → repeat**

…and on top of it, **level up to unlock new products**, **earn stars** by selling, and **rebirth** for a permanent cash bonus.

## Play it

1. Open **`FillTheStore.rbxlx`** in Roblox Studio.
2. Press **Play**.

Scripts build the world (road, six plots, shops, props and leaderboards) when the server starts, so the Workspace looks empty in edit mode. That's expected.

### A new player's first minute

A 4-step **tutorial card** at the top of the screen walks new players through the loop. Each step pays a cash reward with coins and confetti:

1. **GRAB A BOX!** A van pulls up a few seconds after you join and throws boxes onto the yellow loading bay. Walk up and press **E — Pick Up Box**.
2. **FILL A SHELF!** Carry the box into your shop and press **E — Unpack Here** at a shelf. The box pops open and the products fly onto the shelf.
3. **MAKE A SALE!** A customer takes something off the shelf, pays at the till, and coins fly into your cash counter.
4. **UPGRADE YOUR SHOP!** A bouncing 👈 points at the UPGRADE button, and the affordable upgrades glow.

The card also shows touch-screen wording on phones. After step 4 a **YOU'RE A SHOPKEEPER!** finale pays a bonus. A glowing outline and a guide beam point at whatever to do next, and a hint pill at the bottom of the screen says it in words. Returning players skip the tutorial, and **SKIP** skips it at any time.

### Getting better: levels, stars and rebirth

There are three things to work towards, each in its own layer:

**Levels (short term).** Selling earns XP (pricier products earn more), and so does unpacking a box. The purple bar under your cash shows your progress to the next level. Each level pays a cash reward (£25 × level), and some unlock a new product for your deliveries:

| Level | 1 | 2 | 3 | 4 | 6 | 8 | 10 | 12 | 15 | 18 | 22 | 26 | 30 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Unlocks | Water, Crisps | Chocolate | Cola | Energy Drink | Cereal | Toilet Roll | Pizza | Cleaning Spray | Headphones | Smartphone | Games Console | Laptop | Television |

The 📖 **ITEMS** menu (or tap the level bar) shows every product. Unlocked ones spin in 3D, and locked ones are dark silhouettes with the level they need. A **LEVEL UP!** popup names anything new.

**Stars (medium term).** Every unit of a product you sell counts towards its stars: 20, 75, 200, 500 and 1,200 sold. Each ⭐ makes that product sell for 10% more, up to +50%. The ITEMS menu shows each product's stars and how far it is to the next one.

**Rebirth (long term).** The 🔁 **REBIRTH** menu trades £50,000 for:

- a permanent **+50% cash** from every sale, per rebirth (×1.5, ×2, ×2.5…);
- a 🔷 **Rebirth Token** (every 5th rebirth gives 2).

Your cash, upgrades, shop size and stock reset. You keep your level and unlocks, stars, tokens, perks and game passes. Each rebirth costs 2.5× the last. The button asks you to tap twice so nobody rebirths by accident, and the REBIRTH button gets a **!** once you can afford it.

Tokens buy permanent **perks** on the menu's PERKS tab, each with 5 levels:

| Perk | Per level |
|---|---|
| 💰 Head Start | Start each rebirth with £1,000 more |
| 🚚 Express Vans | Deliveries come 8% sooner |
| 🍀 Lucky Boxes | +10% chance of Golden, Rainbow and Giant items |
| 🏃 Busy Street | +8% customers |
| 📦 Bulk Boxes | +10% items in every box |

All of the numbers are in `src/shared/Progression.luau`.

## Setting up for a real game

### Saving and global leaderboards

Saving and the global leaderboards both need DataStores, which need a published place:

1. **File → Publish to Roblox**.
2. **Game Settings → Security → Enable Studio Access to API Services** (only needed to test saves in Studio).

Without these the game still runs. It prints one warning (`Progress will NOT be saved this session`), and the leaderboards show only the players in the current server.

Also set **Max Players to 6** in Game Settings, since there are 6 shops per server.

### The Robux shop

The 🛍️ **SHOP** has three tabs: **Cash** packs, **Boosts** (Customer Rush, Instant Delivery, Golden Crate) and **Passes** (2x Cash, Lucky Charm, Big Deliveries, VIP Shop).

Every item starts in **test mode** with `Id = 0`. In test mode:

- In Studio, items show a red **TEST** sticker, and buying one gives it to you for free so you can try it.
- In a live game, the button says **SOON** and nothing can be bought.

To sell an item for real:

1. On the [Creator Dashboard](https://create.roblox.com/dashboard/creations), open your experience → **Monetization**.
2. Create a **Developer Product** for each entry in `Monetization.Products` (cash packs and boosts), and a **Game Pass** for each entry in `Monetization.Passes`.
3. Paste each ID into the `Id` field in `src/shared/Monetization.luau` (in Studio: `ReplicatedStorage.Shared.Monetization`).

Once an ID is set, the shop shows the item's real Robux price and uses Roblox's purchase prompt. Prices show the Robux logo. It's `rbxasset://textures/ui/common/robux.png`, which ships inside every Roblox client, so nothing needs uploading.

Purchases are handled safely:

- Developer products go through `ProcessReceipt`. Each receipt ID is stored in the player's save, so a purchase is never granted twice.
- The player's data is saved *before* Roblox is told the purchase succeeded.
- Game passes are checked with `UserOwnsGamePassAsync` when a player joins.
- Boost timers are saved, so they keep running if the player rejoins.

### NPC characters

Customers, workers and the cashier are standard Roblox R15 characters. Roblox builds them from a `HumanoidDescription` using `Players:CreateHumanoidModelFromDescription`: the default body and face, with different shirt, trouser and skin colours. They use Roblox's default R15 walk and idle animations.

- Each look is created once when the server starts, then cloned for every NPC.
- If Roblox can't create characters (for example, character assets fail to load), the game prints one warning and uses simple Part-built characters instead.
- The looks are in `NpcBuilder.luau`. You could add clothing or accessory IDs to `describe()` for more variety.

### Particles and effects

The loop's key moments each get a short, restrained effect:

| Moment | Effect |
|---|---|
| A box lands on the bay | Dust rolls out from its corners, with a ring on the ground |
| You pick up a box | Ring at your feet and a few sparkles |
| A box pops open | Flash and a burst of confetti in the tape's colour. Rare boxes get a loot beam in the colour of the rarest item |
| Each product lands on a shelf | A single twinkle |
| A shelf fills up | The shelf glows green |
| A sale | Coins with a few gold sparkles; rare sales add a gold flash and confetti |
| Upgrade, tutorial step or Robux purchase | Ring at your feet, a column of rising stars and a small camera "punch" |
| The shop expands | Three fireworks over the new sign |
| Level up | Purple ring at your feet, rising stars, a camera punch and a **LEVEL UP!** popup with confetti |
| A product earns a star | Sparkles over your head and a banner |
| Rebirth | Fireworks over your sign that other players nearby see too, a white flash, a camera punch, rainbow stars at your feet and a big popup |
| The delivery van drives | Gentle exhaust puffs |

How it stays light:

- `Controllers/Particles.luau` pools everything: one invisible part per effect and one emitter per colour, moved and re-used for every burst.
- Each effect has a particles-per-second budget and is skipped far from the camera.
- Particle counts are halved on low graphics settings.
- The textures are particle images built into every Roblox client, so nothing needs uploading.
- In the play-test, a busy shop averages about 5 particles per second.

### Low-poly style

Everything is built from ordinary Parts in a low-poly style, so nothing needs uploading. `src/shared/LowPoly.luau` provides the shapes:

- **Hexagonal prisms** (3 overlapping blocks) instead of cylinders: trunks, poles, cans, bottles, bins and wheels.
- **Triangle facets** (2 thin WedgeParts per triangle) that build faceted solids:
  - lumpy icosahedron tree crowns and rolling hills;
  - octahedron bushes and rocks;
  - six-sided pine tree tiers and a striped eight-sided parasol.
- **Bevelled blocks** for hedges, and blocks turned on a corner for small round things like flowers, bulbs, apples and coins.

Roblox shades each facet separately, which gives the flat-shaded low-poly look. The NPCs are the exception: they're standard Roblox characters.

### Drop-in meshes (optional)

The world is built from Parts and needs no uploads. To use real meshes instead, put models into **`ReplicatedStorage.CustomModels`**. You can get them from the Creator Store/Toolbox, or import your own from Blender with **File → Import 3D**.

| Folder | Model name | Replaces |
|---|---|---|
| `CustomModels/Products` | a product id, e.g. `Cola`, `Laptop`, `Television` (ids are in `Products.luau`) | that product on shelves, in the STOCK menu and popping out of boxes |
| `CustomModels/Props` | `DeliveryVan`, `Car`, `Forklift`, `Tree` | the delivery van and the matching props |

How custom models are used:

- Each model is scaled to fit the space the Part version uses, stood on the ground and turned to match its pivot. Point the model's pivot so its front faces forward (along the pivot's -Z).
- Golden and Rainbow variants recolour it automatically.
- Scripts inside free models are removed.
- If the folder is empty or a model is missing, the game uses the built-in Part version.

## What's in the game

| System | Details |
|---|---|
| Plots | 6 shops per server (3 on each side of a road), one per player. The sign shows the shop's name (CORNER SHOP → LOCAL STORE → MINI SUPERMARKET) and its value; player names are never put on shops. A floating **⭐ YOUR SHOP** marker is shown only to the owner |
| Deliveries | A van arrives every 20–28s and throws 3+ boxes onto your loading bay (up to 12 can wait there). The tape colour hints at the rarity of what's inside |
| Boxes & stocking | **E — Pick Up Box**, then carry it to any shelf with space and press **E — Unpack Here**. It bursts open and the products fly onto the shelf. Anything that doesn't fit goes to your stock room. **E — Stock Shelf** fills shelves from the stock room, and the **STOCK** menu shows the stock room as spinning 3D products (tap one to shelve it first) |
| Products | 14 products, from Water (£3) to Television (£700). Pricier ones unlock as you level up |
| Levels | XP from selling and unpacking. Each level pays cash, and 12 of them unlock a product. The 📖 **ITEMS** menu shows what's next |
| Stars | Up to 5 ⭐ per product for selling it, each +10% on its price |
| Rebirth | The 🔁 **REBIRTH** menu: £50,000 (×2.5 each time) for +50% cash forever and a Rebirth Token. Resets cash, upgrades, shop size and stock |
| Perks | Head Start, Express Vans, Lucky Boxes, Busy Street and Bulk Boxes, bought with Rebirth Tokens |
| Rare variants | Each unit can roll **Golden ×10**, **Rainbow ×100** or **Giant ×625** (Cola £8 → £80 → £800 → £5,000). Rares sparkle, Rainbow items cycle colours, Giant items are big, and you get a **✨ RAINBOW COLA!** banner |
| Customers | Default Roblox R15 characters (see below). They walk in, take products off stocked shelves, queue at the till, pay and leave. Coins fly from the till to your cash counter |
| Upgrades | One menu: Shelf Capacity, Delivery Size, Customer Rate, Product Luck, Store Size, Workers, each with level pips and a before ➜ after preview |
| Expansion | Corner Shop (2 shelves) → Local Store (4) → Mini Supermarket (10). The shop is rebuilt bigger and keeps its stock |
| Workers | Staff NPCs in green (the cashier wears the same look) restock the emptiest shelf from your stock room |
| Leaderboards | Three double-sided boards stand on the street's central reservation: **TOP STORES** (store value), **TOP EARNERS** and **MOST SOLD**, with avatars. The same boards are in the 🏆 **TOP** menu, and Value, Rebirths, Cash and Sold also show in the player list |
| Robux shop | Cash packs that scale with progress, a 15-minute Customer Rush (3× customers), an Instant Delivery, and a Golden Crate (all Golden + a Rainbow). Passes: 2x Cash, Lucky Charm (2× rare chance), Big Deliveries, and VIP Shop (golden shop with a crown, red carpet, VIP tag and a free extra worker) |
| World | Low-poly throughout. Every plot has a car park with parked cars, planters, a bench and bin, a trolley corral, pallets of stock, a forklift, a picnic table with a parasol, flower beds, hedges and a fence. There are faceted trees and pines between the plots, and rolling hills and rocks around the edges. Shops have marquee lights around the sign, a gumball machine and an ice-cream freezer |
| Other players | Can walk into your shop but can't use your prompts, boxes, shelves or upgrades. The server checks ownership on everything |
| Saving | Cash, upgrades, store level, stock room, what's on each shelf, level and XP, units sold of each product, rebirths, tokens and perks, stats, tutorial progress, boost timers and processed receipts |

## Project layout (Rojo)

```
default.project.json          Rojo project → builds FillTheStore.rbxlx
src/shared/   → ReplicatedStorage.Shared      data + helpers used by both sides
  Config          all the tuning numbers (delivery times, speeds, prices...)
  Products        product list + rarities         ← add products here
  Variants        Golden / Rainbow / Giant
  Upgrades        upgrade definitions + formulas   ← add/tune upgrades here
  StoreLevels     shop sizes, shelf positions, NPC waypoints ← add store levels here
  Monetization    Robux shop catalogue             ← paste product / pass IDs here
  Tutorial        the tutorial steps and rewards
  Progression     levels, unlocks, stars, rebirth cost/bonus, perks ← tune progression here
  Items           "Cola:Golden"-style item keys, prices, names
  ProductVisuals  each product's 3D model (Parts, or a custom mesh)
  LowPoly         low-poly shapes from Parts (hex prisms, wedge triangles, gems)
  ModelLibrary    drop-in meshes from ReplicatedStorage.CustomModels
  BoxVisual, Build, Format, Remotes, Signal, Sounds
src/server/   → ServerScriptService.Server
  Main.server     wires everything up (players joining/leaving, respawning)
  Services/
    PlayerData    DataStore load/save, cash, inventory (server-authoritative)
    Stores        claims plots, builds/rebuilds shops
    Deliveries    the van + delivery timer
    Boxes         box landing, pick up, carry, unpack
    Shelves       stocking, visible products, stock bars
    Customers     customer NPC behaviour
    Workers       staff NPCs
    UpgradeService    upgrade purchases (validated on the server)
    TutorialService   tutorial progress + rewards
    ProgressionService  XP, level-ups, stars, rebirth, perk purchases
    MonetizationService  ProcessReceipt, game passes, Studio test purchases
    Perks         what passes and boosts do (2x cash, luck, extra boxes...)
    Leaderboards  OrderedDataStore boards + signs
    Events, Registry, Net, NpcMotion  shared state + helpers
  Builders/       WorldBuilder, StoreBuilder, PropBuilder, TruckBuilder,
                  NpcBuilder, LeaderboardBuilder
src/client/   → StarterPlayerScripts.Client
  Main.client     creates the UI and starts the controllers
  Controllers/    HUD, UpgradesPanel, StockPanel, ShopPanel, LeaderboardPanel,
                  UnlocksPanel (ITEMS), RebirthPanel (REBIRTH + PERKS),
                  TutorialUI, Notifications, Effects + Particles (pooled effects),
                  Guide (hints + outlines),
                  Prompts (owner-only prompts), UIKit + Window (chunky UI kit)
tests/            headless play-test (see below)
```

**Security:** the client never sends money, prices or amounts. It only asks for things ("buy upgrade X", "prefer product Y", "skip the tutorial") or triggers a ProximityPrompt. The server validates all of it: ownership, distance, being inside your shop, and affordability. Free test purchases only work when the server is running in Studio.

### Common tweaks

- **Add a product:** add an entry to `Products.List`. Pick a `Shape` from `ProductVisuals`, or drop a mesh into `CustomModels/Products`.
- **Rebalance:** `Config.luau` (timings), `Upgrades.luau` (costs and effects), `Variants.luau` (rare chances), `Tutorial.luau` (step rewards), `Monetization.luau` (pack sizes, boost lengths), `Progression.luau` (XP curve, star thresholds, rebirth cost and bonus, perks).
- **Change when a product unlocks:** its `UnlockLevel` in `Products.luau`.
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

`tests/emulator/` is a small Roblox engine emulator for [Lune](https://lune-org.github.io/docs). It loads the built place file and runs the real server and client scripts on a virtual clock. It validates every property read and write against Roblox's API database, and simulates humanoid walking, welds, remotes, DataStores, OrderedDataStores, MarketplaceService and prompts.

- `tests/playtest.luau` has a bot play like a brand-new player. It follows the tutorial (grab, unpack at a shelf, first sale, upgrade) and checks the timings and rewards. It then plays five minutes buying upgrades through the real UI buttons, and checks:
  - NPCs are Roblox R15 characters, each look is made once, and the fallback works;
  - player names never appear on shop signs;
  - levels, product unlocks and stars (only unlocked products turn up, and the ITEMS menu matches);
  - the leaderboards;
  - every Robux shop item in Studio test mode;
  - real product and pass IDs, including receipt de-duplication;
  - store expansion and workers;
  - a second player who can't touch your stuff;
  - rebirth through the menu: it's refused without the cash, needs a second tap, resets the right things, keeps the rest, and perks can be bought;
  - saving and rejoining (passes, boosts, tutorial, rebirths and perks);
  - Studio without API access.
- `tests/layout.luau` checks every store level, normal and VIP:
  - customer and worker routes and queue spots don't pass through walls, shelves, the till or props;
  - shelves don't overlap;
  - the walk from every loading-bay spot to the door is clear;
  - drop-in mesh models are scaled, placed and recoloured correctly.

The emulator is not the real engine. It has no physics collisions, no rendering and no real network. It's a strong smoke test, not a replacement for a quick play in Studio.
