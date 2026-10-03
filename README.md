# 8 Bit Evil Returns (Godot)

A Godot 4.5 remake of the Unity *8 Bit Evil Returns*: a Vampire Survivors-style
survival game for the Scareathon arcade. It uses portrait 9:16 and GDScript,
and exports to the web without threads, so it runs on iOS Safari and GitHub
Pages.

Play: https://scarbone98.github.io/8BitEvilReturns-godot/

This version was rebuilt from the compiled Unity WebGL build
(`scarbone98/8BitEvilReturnsBuild`), not from the Unity source. Anything marked
**(orig)** in `src/autoload/db.gd` comes straight from the build. Everything
else is inferred and still needs checking against the Plastic SCM source.

## Run it

```sh
godot4 --path .                 # play in the editor/desktop
./tools/publish_pages.sh        # build + push to gh-pages (live site)
./tools/build_web.sh            # export to build/web
cd build/web && python3 -m http.server 8791
```

### Dev flags

These work on the command line (`godot4 --path . -- --autoplay --give=fireball`)
and in the page URL (`index.html?autoplay&give=fireball`). Dev runs never save
or submit scores.

| flag | does |
|---|---|
| `autoplay` | a bot plays and picks upgrades, and logs status every 30s |
| `dev` | skip the menus and go straight into a run, with no bot |
| `char=matt` | which hero |
| `give=a,b,b` | add weapons/passives (repeat an id to level it up) |
| `minute=N` | start at minute N (waves, HP scaling) |
| `speed=N` | `Engine.time_scale` |
| `levelup` / `chest` / `die` | open that screen right away |
| `unlockall` | everything unlocked, nothing saved |
| `horde=N` / `bench` | spawn N enemies / time the simulation for 400 frames |
| `real` | with `autoplay`: save the run like a normal one |
| `stage=crimson_crypt` | which stage |

Every weapon, evolution and union: `python3 tools/test_weapons.py`

Balance check: `godot4 --headless --path . -- --autoplay --speed=8 --char=joe`

## Layout

```
src/data/*.gd           ALL content: weapons (+evolutions, unions), passives, heroes,
                        enemies, stages, feats, power-ups, sprite sheets
src/autoload/db.gd      gathers src/data into Db.WEAPONS etc, plus lookups
src/autoload/meta.gd    saved profile: silver, unlocks, feats, power-ups, totals
src/autoload/bridge.gd  Scareathon arcade page + API (same protocol as the Unity build)
src/main.gd             title → hero select → run
src/run/run.gd          one run: loop, wave spawner, drops, level-up/chest/pause/death screens
src/run/player.gd       movement (keys, gamepad, touch drag), stats, XP, inventory
src/run/weapon.gd       one owned weapon: level-ups + stats → fires shots
src/run/shots.gd        every projectile/effect, by behaviour type
src/run/enemies.gd      enemies as packed arrays + spatial grid (hundreds at once)
src/run/pickups.gd      candy (XP), silver, heart, clock, skull, basket, chest
src/run/obstacles.gd    endless graveyard props, generated per chunk from a hash
src/ui/                 HUD, theme (original GUI_border art), SheetView
```

## Adding content

- **A weapon.** Add an entry to `Db.WEAPONS` with a `behavior`:
  - `shooter`, `slash`, `boomerang`, `strike`, `orbit`, `flask`, `summon` or `seeker`
  - give it `base` stats and a `levels` list
  - for an evolution, set `evolve: {with, into}` and add the evolved weapon
    with `evolution: true`

  A new behaviour means a new spawn function and a new branch in
  `src/run/shots.gd`, plus a new case in `Weapon.fire()`.
- **A passive.** Add an entry to `Db.PASSIVES` with `per_level` stat bonuses.
  The stat names are in `Player.STAT_DEFAULTS`.
- **An enemy.** Add a sprite sheet to `Db.SHEETS` and an entry to `Db.ENEMIES`.
- **A stage.** Add an entry to `Db.STAGES` with spawn windows and timed events
  (`ring`, `boss`). Stage select isn't built yet: the run always uses
  `graveyard`.
- **A hero.** Add an entry to `Db.CHARACTERS` with a run sheet, an idle sheet,
  a starting weapon, stat bonuses and a silver cost.

## Co-op

Up to 4 players, each on their own device, join a room by code (CO-OP on
the title screen). One copy of the game runs the whole fight and streams
each player a snapshot of what they can see, 20 times a second; players
move their own hero locally and send its position back, and draw the world
0.1s behind the newest snapshot so it stays smooth.

That copy is normally a headless one the Scareathon server starts for the
room (the "Linux Server" export, published as the latest GitHub release
asset `8ber-server.x86_64` by `tools/publish_server.sh`, which
`tools/publish_pages.sh` runs too). If the server can't start one, the
player who made the room hosts it on their device instead. Team XP and level are
shared, everyone picks their own level-up card, and downed heroes come
back at the next team level-up. The Scareathon server only keeps the lobby
and relays packets (`/8bitevilreturns/v2/ws`, see
`server/eightBitEvilV2/rooms.js` in the site repo).

- `src/autoload/net.gd`: the socket, lobby, and packet relay
- `src/run/netsync.gd`: snapshot encoding/decoding, level-up and results messages
- Dev flags: `coop=host&players=N` makes a room and starts when N are in;
  `coop=join&room=CODE` joins; `server=http://127.0.0.1:8792` picks the server.
- `tools/coop_test.sh [server] [seconds] [players]` plays bots against each
  other headless. For a local relay, run the site's
  `routes/8bitevilreturnsV2.js` alone in Fastify on port 8792.

## Arcade integration

This is the same `postMessage` protocol the Unity build used, so the site
needs no changes. Point `EIGHT_BIT_EVIL_RETURNS_URL` at the new build.

- game → page `{type:"unityReady"}` on boot
- page → game `SCARATHON_USER {userId, accessToken, apiBaseUrl}`
- on death: `POST /8bitevilreturns/runs {runTimeSeconds, kills, candyCollected}`,
  then game → page `PLAYER_DIED {score: seconds}`
- V2 keeps its own account save: `GET/PUT /8bitevilreturns/v2/save`
  (unlocks, feats, power-ups, totals), separate from the Unity game's data

## Known gaps / to cross-check with the Unity source

- Evolution pairings and names are guesses. Only *Gatling Crossbow* is
  confirmed.
- Passive icons, per-level upgrade steps, enemy stats and wave timings are
  inferred.
- Heroes' starting weapons match Mystery Crypt. Unlock costs are made up.
- There is no audio yet. The Unity build has 4 audio clips that could be
  extracted.
- The web engine file is 38 MB before compression. A custom export template
  with unused modules stripped (3D, physics) would shrink it a lot.
