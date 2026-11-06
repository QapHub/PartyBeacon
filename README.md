# PartyBeacon (WoW Forever)

Puts a beacon and a big, bright name tag over your party members' heads so you
can pick them out of a crowd of players and NPCs.

`/pb` opens the options. `/pb test` previews it on your current target while solo.
You can also bind a toggle key under Key Bindings > AddOns.

## Options

**Over their head**
- Beacon style: arrow, chevrons, gem, light pillar, raid icon (only you see it), Hunter's Mark icon, or none
- Beacon colour: different per member, class colour, custom colour, or rainbow
- Size, lift above the name, bob, glow, pulse

**Name tag**
- Big name above their head in its own colour: per member, class, custom, or rainbow
- Size and outline

**Nameplates**
- Turns friendly nameplates on while you're grouped, and puts your setting back when you leave or log out
- Hides every other friendly nameplate so only your party stands out (your target is never hidden)
- Can hide Blizzard's bar on party members, leaving only the beacon and name
- Click-through friendly plates, max nameplate range, whole raid or just your subgroup

**Shared world markers** (off by default)
- Puts real raid icons (star, circle...) on party members. The whole group sees them.
- Never takes an icon that's already on something it can see, never re-places an icon someone moved, and only clears icons it placed.

## Limits
- Beacons and name tags are drawn on nameplates, because that's the only way an addon can attach anything to a character in the world. They show only when that person's nameplate is on screen and in range.
- **Inside dungeons and raids the game blocks addons from friendly nameplates**, so beacons and name tags can't show there. Use the shared world markers (`/pb markers instance`) for dungeons.
- The game has no way to outline or recolour a character's model, so this addon doesn't do that.

## Files
- `Core.lua`: settings, roster, nameplate settings, world markers, slash commands
- `Beacon.lua`: draws the overlays on nameplates
- `Options.lua`: the `/pb` window
- `Media/`: textures (made by `tools/make-media.js`)
- `tests/`: headless tests: `npm install fengari`, then `node tests/run.js tests/test.lua`

## Install
Download this repo (Code > Download ZIP), and copy everything except `tools/` and
`tests/` into a folder named `PartyBeacon` in
`World of Warcraft\_forever_\Interface\AddOns\`, so the path ends in
`AddOns\PartyBeacon\PartyBeacon.toc`. Restart the game or `/reload`.
