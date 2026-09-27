# 8 Bit Evil Returns (Godot)

A Godot 4.5 remake of the Unity *8 Bit Evil Returns*: a Vampire Survivors-style
survival game for the Scareathon arcade. It uses portrait 9:16 and GDScript,
and exports to the web without threads, so it runs on iOS Safari and GitHub
Pages.

This version was rebuilt from the compiled Unity WebGL build
(`scarbone98/8BitEvilReturnsBuild`), not from the Unity source. Anything marked
**(orig)** in `src/autoload/db.gd` comes straight from the build. Everything
else is inferred and still needs checking against the Plastic SCM source.

## Run it

```sh
godot4 --path .                 # play in the editor/desktop
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

Balance check: `godot4 --headless --path . -- --autoplay --speed=8 --char=joe`

## Layout

```
src/autoload/db.gd      ALL content: weapons, passives, evolutions, heroes, enemies, stages
src/autoload/meta.gd    saved profile: silver, unlocked heroes, best time
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

## Arcade integration

This is the same `postMessage` protocol the Unity build used, so the site
needs no changes. Point `EIGHT_BIT_EVIL_RETURNS_URL` at the new build.

- game → page `{type:"unityReady"}` on boot
- page → game `SCARATHON_USER {userId, accessToken, apiBaseUrl}`
- on death: `POST /8bitevilreturns/runs {runTimeSeconds, kills, candyCollected}`,
  then game → page `PLAYER_DIED {score: seconds}`
- silver and unlocks: `getUserData`, `setUserData`, `unlockCharacter`

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
