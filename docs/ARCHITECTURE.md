# Architecture

Godot 4.4, GDScript. The game is split into a **pure rules core** (RefCounted classes,
no nodes, fully testable headless) and a **view** (scenes, 3D, HUD) that only reads
`GameState` and reacts to its events.

Online co-op later works by sending *actions* (small Dictionaries) between peers and
running the same `Rules.apply` on each, so every state change must go through `Rules`.

## Modules and owners

| Folder | Class | Owner workstream | What it does |
|---|---|---|---|
| `core/` | `Types`, `Grid`, `Unit`, `GameState`, `Rules` | core (shared) | Map, units, turn flow, action dispatch, damage, win/lose |
| `data/` | `UnitData` | core (shared) | Stat blocks for soldier classes and enemy types |
| `combat/` | `Combat` | **combat** | LOS, cover, hit chance, shoot, overwatch, hunker, class abilities |
| `infection/` | `Infection` | **infection** | Meter, tiers, mutation powers, Lapse rolls, Turning, cure |
| `ai/` | `EnemyAI` | **ai** | Enemy and Lapsed-soldier decisions |
| `view/`, `ui/`, `scenes/` | various | **view** | 3D board, camera, input, HUD, animations |
| `tests/` | `TestCase` | everyone | `tests/test_<module>.gd` per workstream |

Rules for parallel work:
- Only edit files your workstream owns. If you need a change in `core/` or `data/`,
  keep it small and additive (a new field, a new helper) and call it out in your summary.
- Keep public function signatures in `Combat`, `Infection`, `EnemyAI` stable: other
  workstreams code against them. Adding new public functions is fine.
- Never mutate `GameState` from the view. The view calls `Rules.validate`, `Rules.apply`,
  `Rules.set_ready`, and read-only queries.
- Random rolls use `state.rng` only (determinism for replays and networking).
- Run `./tests/run.sh` before you finish. It fails on any script error.

## Turn flow

1. `Rules.start_team_phase`: soldiers get 2 actions, overwatch/hunker clear, cooldowns tick,
   `Infection.on_team_phase_start` (Lapse rolls), then any `ai_controlled` soldier acts via `EnemyAI.take_turn`.
2. Team phase is simultaneous: any player acts with their own soldiers in any order
   (`GameState.controllable_units(player)`). Each player calls `Rules.set_ready`.
3. When all players are ready, `Rules.run_enemy_phase` runs each enemy through `EnemyAI.take_turn`
   sequentially, then the next team phase starts.
4. `Rules.check_end` after every action: no enemies = VICTORY; no living player-team soldiers (Turned ones count as enemies) = DEFEAT.

## Actions

`{"type": Types.MOVE, "unit": id, "to": Vector2i}` costs 1 action, range `unit.mobility` (8-way, no corner cutting).
`SHOOT` (`"target": id`), `OVERWATCH`, `HUNKER` end the unit's turn.
`ABILITY` (`"ability": id`, optional `"target"`/`"cell"`) and `MUTATION` (`"mutation": id`, ...) cost is defined by their module.

## Events

`GameState.event(ev)` is emitted for every change, in order. The view animates from these.

| type | fields |
|---|---|
| `team_phase` | `turn` |
| `enemy_phase` | `turn` |
| `ready` | `player`, `ready` |
| `rejected` | `action`, `reason` |
| `move` | `unit`, `from`, `path: Array[Vector2i]` (one event per segment between interrupts) |
| `shot` | `unit`, `target`, `hit`, `graze`, `crit`, `damage`, `chance`, `reaction` (a graze has `hit` and `graze` both true and reduced damage; emitted before its `damage` event) |
| `damage` | `unit`, `amount`, `hp`, `source` |
| `died` | `unit` |
| `overwatch` | `unit` |
| `hunker` | `unit` |
| `ability` | `unit`, `ability`, plus `target`/`cell` and ability-specific fields: `stim` → `heal`, `hp`; `breach` → `hit`, `damage`; `claw` → `hit`, `graze`, `damage`, `chance`; `spit` → `cell`, `units` (affected ids), `damage`. Emitted before the resulting `damage` events |
| `infection` | `unit`, `value`, `tier` |
| `mutation` | `unit`, `mutation`, plus target fields (`regenerate` adds `healed`, `hp`) |
| `lapse` / `recover` / `turned` | `unit` |
| `alerted` | `unit` (an Infected wakes up; emitted once per unit, see Enemy AI) |
| `mission_end` | `result` (`Types.Result`) |

New event types are fine; add them to this table.

## Cross-module contracts

- **Lapsed soldier**: `unit.status["lapsed"] = true` and `unit.ai_controlled = true`. `Unit.is_enemy_of`
  treats a lapsed unit as hostile to everyone. `EnemyAI.take_turn` must handle it (it is called for
  lapsed soldiers at the start of the team phase).
- **Turned soldier**: Infection sets `unit.team = Types.Team.ENEMY`, `ai_controlled = true`, `owner_player = -1`,
  `status["turned"] = true` and clears `lapsed`. It then acts in the enemy phase. Turning is permanent (`Infection.add` ignores turned units).
  The `turned` event follows the `infection` event that reached 100.
- **Infection tiers**: `Infection.tier(value)` -> `Infection.Tier` (CLEAN 0-24, EXPOSED 25-49, MUTATING 50-74, CRITICAL 75-99,
  TURNED 100; thresholds in `Infection.THRESHOLDS`). `tier_name(t)` and `tier_color(t)` are for the HUD.
  Tier passives (MUTATING +1 mobility; CRITICAL/TURNED +1 mobility, +10 aim) are applied directly to `unit.mobility`/`unit.aim`
  by `Infection.add`; the applied amounts are in `status["tier_mobility"]`/`status["tier_aim"]`, so a stat panel can show them.
- **Cure**: lowering infection is `Infection.add(s, u, -amount)` (Medic stim: -15). Passives revert automatically.
- **Hive Sense** (mutation): `unit.status["hive_sense"] = <turn>`; active while it equals `s.turn`.
  Query with `Infection.has_hive_sense(s, u)`. **Combat must treat the target's cover as NONE** for shots by a unit
  with Hive Sense active (hit chance and the HUD preview).
- **Adrenal Surge** (mutation): costs 0 actions but, like every action, needs `actions_left >= 1`; gives +1 action.
  Once per turn via `status["surge_turn"]`. Regenerate uses `unit.cooldowns["regenerate"]` (ticked by Rules).
- **Lapse**: rolled in `Infection.on_team_phase_start` (MUTATING 10%, CRITICAL 30%, `Infection.lapse_chance(value)`).
  A soldier lapsed at the previous phase start recovers (`recover` event) and does not roll again that phase.
- **Infection from damage**: `Rules.deal_damage` calls `Infection.on_damaged(s, target, source, amount)`.
- **Enemy activation** (owned by `EnemyAI`): Infected start dormant. `unit.status["alerted"] = true` once a
  hostile is in sight (`Combat.can_see`) at the start of its turn, it has taken damage (`hp < max_hp`), or an
  alerted ally is within 6 tiles; alerting chains to dormant allies within 6 tiles. Dormant enemies only shuffle.
  Other modules may call `EnemyAI.alert(s, u)` to wake one immediately. Turned and Lapsed soldiers are always active.
- **AI and abilities**: the AI only uses `claw` (`"target"`, adjacent hostile) and `spit` (`"cell"`) when
  `Rules.validate` accepts them, otherwise it falls back to SHOOT / MOVE.
- **Hit chance**: `Combat.hit_chance(s, attacker, target, from)` returns
  `{hit, graze, crit, cover, flanked, breakdown}`; the HUD and AI both use it, `from` lets them preview other cells.
- **Combat statuses** (in `unit.status`, owned by combat): `"suppressed"` and `"tagged"` hold the
  `Combat.phase_index` they expire at (team phase of turn T = 2T, enemy phase = 2T+1); read them with
  `Combat.has_status(s, u, key)`. `"ow_until"` / `"hunker_until"` time-limit the overwatch / hunker flags so
  enemy overwatch lasts until that enemy's next phase; use `Combat.is_overwatching` / `Combat.is_hunkered`.
  Expired entries are swept at the start of every `Combat.apply`.
- **Abilities / mutations for the HUD**: `Combat.available_abilities` and `Infection.available_mutations`
  return `{id, name, targeting: "none"|"unit"|"cell", ready, ...}`. Mutations also carry `desc`, `cost` (infection added),
  `actions` (action cost), `cooldown` (turns left) and `reason` (why not ready, "" if ready). The list is empty below EXPOSED.
  Combat adds `cooldown`, `cost` (actions, -1 = ends turn), `desc` and `targets` (legal unit ids for unit-targeted abilities).
- **Hit chance extras**: `hit_chance` also returns `los`, and takes an optional 5th arg `reaction` (overwatch −15).
  `graze` is the width of the graze band above `hit`; `crit` is the crit chance given a hit.
  `Combat.melee_chance` gives claw odds.

## View presentation (cinematics, animation, sound)

All of this is view-only and driven by event data, so it never touches `GameState` and every peer
in an online match plays the same thing.

- **Shot cinematics** (`view/event_player.gd`): `shot` events and the `claw` / `breach` abilities cut
  the camera over the shooter's shoulder (`CameraRig.cine`), push in, fly the round in slow motion
  (`EventPlayer.world_scale` slows unit animation and FX, not the beat clock), hit-stop on impact,
  and hold through the following `damage` / `died` / `infection` / `turned` / `alerted` beats
  (`CINE_FOLLOW`). Any other event, or the queue draining, cuts back to the tactical camera.
  Skipped when `EventPlayer.cinematics` is false (C key) or playback is sped up (autoplay).
- **Unit rigs** (`view/unit_view.gd`): generated models (`assets/models/*.glb` from
  `tools/gen_models.py`, loaded by `view/model_kit.gd`) on a jointed rig, posed procedurally in
  `tick` (idle, walk, aim with two-bone arm IK onto the weapon, recoil, hit, hunker, lunge,
  death). Two rigs so far: soldier (all classes, also Turned) and infected humanoid (Runner,
  Spitter; new enemies of that build reuse it). `view/character.gdshader` adds grime, rim light,
  spreading infection veins and hit flash; growth meshes `grow1..3_*` appear per infection tier.
  Calls: `set_moving`, `set_aim`, `recoil`, `hit_react`, `set_lunge`, `muzzle_world`, `chest_world`.
- **Facing**: `face_towards` turns units smoothly (`TURN_SPEED`) toward their path and targets;
  after every playback drain `MissionView.face_threats` turns each unit to its nearest hostile
  (dormant enemies keep their own headings). It reads only the shared state, so peers agree.
- **Sound** (`view/sfx.gd`): `MissionView.sfx.play(name)`; files in `audio/` are synthesized by
  `tools/gen_sfx.py`. `Sfx.muted` is the M key toggle.
- **Look**: environment and lights in `MissionView._build_environment`, set dressing in `Board`,
  vignette and grain in `view/post_fx.gd`.

## Networking (online co-op)

Host-authoritative, action-replicated, over Godot's built-in ENet. This builds on the rule that
every state change goes through `Rules`: peers never diverge as long as they apply the same actions
in the same order on the same seed.

- **`core/match_config.gd` (`MatchConfig`)**: a serializable description of a mission (map, squad
  split across N players, enemy list, seed). Every peer builds an identical `GameState` from it.
- **`net/local_session.gd` (`LocalSession`)** and **`net/net_session.gd` (`NetSession`)** implement the
  same small interface the view talks to: `local_players()`, `is_local(player)`, `submit(action)`,
  `set_ready(player, on)`, `restart()`, `can_restart()`, `status_text()`, `player_names`. The view and
  HUD never call `Rules` directly any more — they call the session, so hot-seat and online share one path.
- **`view/app.gd` (`App`)** is the game root (scene `scenes/app.tscn`): it owns the main menu/lobby,
  the session, and the mission view, and swaps between them.

Online flow:
1. Host opens a port; clients connect by address. The lobby syncs `{peer: {name, player}}` to everyone.
2. On start, the host assigns player numbers 0..n-1 and broadcasts the `MatchConfig`; each peer builds
   the same `GameState` and runs `Rules.start_mission`.
3. A client's `submit`/`set_ready` sends a request to the host. The host validates it (including that the
   sender owns the soldier), applies it, and broadcasts the accepted action with a sequence number and a
   `GameState.checksum()`. Clients apply it and compare checksums; a gap or mismatch triggers a full
   snapshot resync (`GameState.to_dict()` / `from_dict`).
4. A disconnected player's soldiers auto-hunker and their READY is pressed for them, so the match
   continues; if they reconnect they reclaim their slot and get a snapshot.

`GameState.to_dict()/from_dict()` and `Grid.to_dict()/from_dict()` also serve save/resume later.
The determinism this relies on: all randomness is `state.rng`, and the enemy/infection/AI code only
ever reads `state`. The two-process check in `tests/net_playtest.sh` asserts a host and client play a
whole match and end on the same checksum.
