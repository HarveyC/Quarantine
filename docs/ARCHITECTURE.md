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
| `gear/` | `GearData`, `Loadout`, `GearTags`, `GearDraw`, `GearRun` | **gear** | Items, loadouts, stash, tags and set bonuses, reward offers |
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

## Equipment (gear/)

Run-level and pure data, like the rules core. Design: "Equipment and builds" in the design doc.

- **Data** (`GearData`): `ITEMS` (37: name, tag, slot `weapon|ammo|armor|gadget`, rarity
  `common|uncommon|rare`, desc, desc_mk2, optional flat `stats`/`stats_mk2`), `PROTOTYPES` (9: two `tags`,
  rarity "prototype", start at Mk II, not sold), `CONSUMABLES` (with `price`), `TAGS` (the 8 capitalised
  tag names) and `TAG_INFO` (colour, set bonus text). `price(id)`, `upgrade_price(id)` (Armorer).
- **Loadout** (`Loadout`, on the run soldier record as `record.gear`):
  `{"slots": {slot: {"id", "mk"} | null}, "pockets": [{"id", "charges"} | null]}`. Always go through
  `Loadout.equip(run, record, id)` (duplicate -> Mk II; a different item in the slot goes to the stash,
  or is scrapped for 10 Supplies if the stash is full), `unequip`, `upgrade(record, slot)`,
  `take_from_stash`, `add_consumable`, `use_consumable`. The 4-item squad stash is `run.gear.stash`.
- **Tags** (`GearTags`): `counts(record)` / `unit_counts(unit)` = gear + `Progression.tag_counts` /
  `Progression.unit_tag_counts` (perks and awake mutations; loaded by path `res://progression/progression.gd`,
  optional). `has_set`, `active_sets`, `ranked`, `qualified_prototypes`, `preview(record, id)` (threshold
  preview for cards). Set bonus at 3, Prototype at two tags at 2.
- **Draws** (`GearDraw`): tag weight = 1 + 2 per point (max +6); rarity odds per act with +2% Rare pity per
  Common seen; `draw_item(rng, counts, rarity, exclude, only_tags)`; `depot_items(rng, squad_counts, act)`.
- **Run hooks** (`GearRun`), reading `run.supplies`, `run.act`, `run.rng`, `run.soldiers` (records with
  `id`, `kind`, `player`) and owning `run.gear`: `init_run(run)`, `starting_kit_offers(run)`,
  `on_fight_won(run, "skirmish"|"nest"|"boss")` (one 1-of-3 offer per living soldier: gear 45%, perk 15%,
  mutation 15%, consumable 15%, cache 10%; from the second fight an on-build card and a pivot card),
  `all_picked(run)`, `apply_to_unit(unit, record)` when spawning a mission soldier (flat stats; stamps
  `status["gear"]`, `["gear_tags"]`, `["pockets"]`, `["armor"]`), `sync_from_unit` after the mission.
- **Run actions** (replicated like mission actions; `GearRun.handles(action)`, `validate`, `apply`):
  `gear_pick {player, soldier, card (-1 = skip for +10 Supplies), to_stash?}`,
  `gear_stash_take {player, soldier, index}`, `gear_unequip {player, soldier, slot}`. `player` -1 = anyone.

## Non-combat nodes (nodes/)

Events, Supply depot, Field hospital and Survivors (design doc: "Run map and events", "Economy and
rewards"). Pure run-level rules like `RunRules`, plus one screen per node kind in `ui/nodes/`.

- **`NodeRules`** is the entry point the framework calls: `enter(run, kind, event_id = "")`,
  `validate(run, action) -> String`, `apply(run, action) -> bool`, `is_done(run)` (every present
  player has sent `node_leave`), `pending_fight(run)`, `screen(kind) -> Script`, and
  `autoplay_actions(run)` (the actions that close the node with defaults: for absent players'
  timers and headless tests). The open screen is `run.node_state` (`kind` = event / depot /
  hospital / survivors, `left` = players who have left).
- **Actions** (all carry `player`, only in the NODE phase, benched players can't act):
  `node_choose {option, soldier?}`, `node_pass` (decline a volunteer step), `node_timeout` (host
  only: the 20 s choice timer ran out, missing picks take the default), `node_leave`;
  depot `node_buy {index, soldier?, slot?}`, `node_sell {soldier, slot}`, `node_reroll`;
  hospital `node_treat {soldier, treatment: patch|purge|train|cure}`; survivors `node_claim`.
- **Events** are data in `EventData.EVENTS` (15, written in the world's voice), run by
  `EventRules`. An event is a graph of steps; each step is decided one of five ways: `vote`
  (majority, the host breaks a tie, re-voting allowed until the last vote is in), `secret` (picks
  revealed together, with an optional `unanimous` bonus), `per_player` (each player for their own
  soldiers, applied at once), `volunteer` (first claim; everyone passing runs `nobody`) and `owner`
  (only the owner of the event's subject soldier). Options carry requirements, an optional own-soldier
  target and a list of effects (format at the top of `event_data.gd`). Events never repeat in a run,
  are filtered by act and squad state (Whispers needs a soldier at 50+, Last seat a wounded one,
  The Source's signal is act 3 only) and act 1 weights the low-stakes ones x3. A solo player answers
  every kind of step alone and votes resolve at once.
- **What nodes write**: shared values only through `RunRules.add_supplies` / `add_intel` /
  `add_serum` / `add_outbreak` / `add_recruit`; soldier `hp`, `infection` (capped at 99 outside a
  fight), `injuries`, `scars`, `sit_out` (Checkpoint "held") and `status = gone` (Last seat);
  gear only through `Loadout`; perks and mutations only through Progression (late-bound:
  `grant_random_mutation`, `mutations_of`, `remove_mutation`, `full_cure`, `grant_perk_pick`,
  `mutation_name`), with a small fallback in `record.prog.mutations` before it lands. A recruit
  from Stragglers may carry `hidden_carrier: true` (it joins at 50 Infection).
- **Modifiers set**: `extra_enemies` (Last broadcast +1, small ambush −1), `enemies_dead_at_start`
  (Air support 2), `force_nest_next` (Air support), `ambush`, `boss_health_mult` (Signal 0.8),
  `first_turn_action_loss` (Whispers), `remove_column` (The bridge), and `pending_fight`
  (`{"kind": "skirmish"|"ambush", "objective"}`: Checkpoint "force the gate", Field chapel ambush).
- **Depot**: 7 slots (gear 1 Common/Uncommon weighted to the squad's tags, gear 2 Uncommon or
  Rare from act 2, 3 different consumables, 1 Serum dose for 50 once per depot, 1 service rolled from
  Armorer / Recruit 45 / Scar removal 40), reroll 20 then 35 (keeps Serum and the service), sell
  back at 40%, Quartermaster Doctrine −15%. Buyers pick one of their own soldiers.
- **Hospital**: one treatment per soldier by its owner; Patch up (full HP, −1 injury), Purge (−30
  Infection, 15 Supplies), Train (extra perk pick), Full cure (2 doses). Healing or purging anyone
  raises Outbreak by 1 once per visit; Train doesn't.
- **Survivors**: +10 Supplies on entry and one recruit; the first `node_claim` takes them,
  otherwise they join the smallest reserve when everyone leaves.

Node events (`run.event`): `event_start` (`event`, `subject`), `event_step` (`event`, `step`, `kind`),
`event_choice` (`player`, `step`, `option`: empty for secret picks), `event_vote` (`option`, `votes`),
`event_reveal` (`picks`), `event_end` (`event`, `results`, `fight`), `item_gained` (`sid`, `item`),
`soldier_hp` / `soldier_infection` / `soldier_mutation` / `perk_pick` / `full_cure` / `sit_out`
(`sid`, ...), `modifier` (`key`, `value`), `depot_open`, `depot_bought`, `depot_sold`,
`depot_reroll`, `hospital_open`, `hospital_treat` (`soldier`, `treatment`), `survivors_found`,
`node_leave` (`player`).

Screens (`ui/nodes/`, look from the approved mockups via `NodeUi`) extend `node_screen.gd`: they
rebuild from `run.node_state` after each run event and send input with `session.submit_run`. Every
button's enabled state comes from `NodeRules.validate`, so the screen and the rules can't disagree.

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

## Run framework (roguelike run)

A run is 3 acts of 5-row node maps (design doc, "Run structure" and "Run map and events").
It follows the same pattern as a mission: a pure, serializable **`RunState`** changed only through
**`RunRules.apply(run, action)`**, so online play replicates run actions exactly like mission
actions, and save/resume is `RunState.to_dict()`. Solo (1 player) is a first-class case: the
player owns all 4 soldiers, every vote resolves the moment they click, and no lobby or network is
involved (`LocalSession`).

### Modules and owners

| Folder / class | Owner | What it does |
|---|---|---|
| `run/` `RunState`, `RunRules`, `RunMap`, `RunSoldier`, `RunHooks` | **run framework** | Run state, map generation, route vote, node flow, fight setup and results, income, save/resume |
| `core/match_config.gd` `MatchConfig.for_fight` / `build` | run framework | Turns a fight node into a mission config, builds the GameState |
| `gear/` `GearRun` (+ `ui/gear/` screens) | **gear, rewards and loadout** | Gear, stash, post-fight 1-of-3 rewards, Doctrines, loadout |
| `progression/` `Progression` | **ranks, perks and mutations** | Soldier rank/perk/mutation record, rank-up picks, grafts |
| `nodes/` `NodeRules` | **events, shop and hospital** | Event, Supply depot, Field hospital and Survivors nodes |
| `enemies/` `FightBuilder`, `EnemyRoster`, `Encounter` | **enemy roster and bosses** | Enemy lists per fight, elites, bosses, Outbreak effects in a fight, spore zones |
| `mapgen/` `MapGen`, `objectives/` `Objectives` | **tactical map variety** | Mission maps per biome/objective, objective win rules |

**Late binding.** The framework calls the other modules through `RunHooks.call_static("Class",
"method", [args], fallback)`, so `main` builds and the whole run plays (with stand-ins) before a
module lands, and each module goes live the moment its class exists. Keep the class names and
static signatures below exactly; add new functions freely.

### RunState fields

Framework-owned (read freely; change only through `RunRules` or the helpers below):
`seed`, `rng` (all run randomness), `phase` (`RunState.Phase` MAP / NODE / FIGHT / REWARD / ENDED),
`result` (`Types.Result`), `players: Array[int]` (everyone in the run, 0..n-1, solo = `[0]`),
`host_player` (0, breaks split votes), `benched` (player -> true while absent), `act` (1-3),
`row` (row of the current node, 0 before the act's first node), `node` (current node id, -1 at act
start), `map` (Array of node Dictionaries, see below), `supplies` (shared), `intel` (shared),
`outbreak`, `serum` (player -> samples; 2 samples = 1 dose), `fights_won`, `soldiers` (every soldier
record of the run), `votes` (player -> node id), `steps` (queued steps of the current node),
`fight_config` (the current fight's MatchConfig), `fight_snapshot` (GameState.to_dict for save),
`seen_events`, `unknown_streak`, `echoes` (soldiers who Turned: `{sid, kind, name, act}`), `meta`
(read-only copy of profile unlock flags such as `act1_boss_beaten`, `vector_unlocked`).

Queries: `present_players()` (not benched; these vote), `is_solo()`, `squad()` (active records,
max 4), `soldiers_of(player)` (active), `reserve_of(player)`, `get_soldier(sid)`, `get_node(id)`,
`current_node()`, `reachable_nodes()`, `controller_of(record)` (owner, or the host while the owner
is benched).

Module-owned fields (opaque to the framework, saved and synced as-is):
- `run.gear` — GearRun (stash, reward offers, pity).
- `run.node_state` — NodeRules: the open event/depot/hospital/survivors screen. Cleared on node exit.
- `run.modifiers` — effects for later, set by NodeRules/GearRun, consumed by the framework and
  FightBuilder: `extra_enemies` (int), `enemies_dead_at_start` (int), `ambush` (bool),
  `boss_health_mult` (float), `first_turn_action_loss` (Array of soldier ids), all one-shot (cleared
  when the next fight starts and passed to FightBuilder as `spec.modifiers`); `force_nest_next`
  (bool, the next route vote must pick a reachable nest); `remove_column` (framework, not yet);
  `pending_fight` (`{"kind", "objective"}`: a fight runs right after the current node, with
  rewards); `heal_after_fight` (float, default 0.25, a Doctrine may raise it); `doctrines` (Array of
  ids, GearRun).

### Soldier record

`run.soldiers` holds Dictionaries (`RunSoldier.make(run, kind, owner, status)`):

| key | owner | meaning |
|---|---|---|
| `id` | framework | soldier id (`sid`), stable for the run; units carry it as `unit.status["sid"]` |
| `kind`, `name`, `owner` | framework | class id, surname, owning player |
| `status` | framework | `active` (squad) / `reserve` / `dead` / `turned` / `gone` (`RunSoldier.ACTIVE`, ...) |
| `hp`, `max_hp`, `infection` | framework | carried between fights (copied back from the unit after each fight) |
| `fights` | framework | fights survived (XP) |
| `injuries` (int), `scars` (Array), `sit_out` (int fights to miss, e.g. Checkpoint "held") | framework, written by NodeRules | |
| `prog` | **Progression** | `Progression.new_record(kind)`; rank, perks, mutations, pending picks |
| `gear` | **GearRun** | loadout: 4 slots + 2 pockets |

A soldier who dies or Turns stays in the list with that status; their owner's first reserve recruit
deploys in their place (`Progression.on_recruit_deployed(new_prog, lost_prog)` sets the rank one below).

### Node map

`RunMap.generate(rng, act)` returns the act's nodes. A node: `id`, `row` (1-5), `col`, `x` (0-1
layout), `type` (`RunMap.SKIRMISH`/`NEST`/`EVENT`/`DEPOT`/`HOSPITAL`/`SURVIVORS`/`BOSS`/`UNKNOWN`),
`links` (ids in the next row), `objective` (`extract`/`hold`/`rescue`/`purge` for fights, `boss`),
`seed` (fight seed), `visited`, `hidden` (an unrevealed "?"), `resolved` (what a "?" became:
`event`/`ambush`/`depot`/`survivors`). Show `RunMap.shown_type(n)` on the map. Rules from the doc:
row 1 Skirmish, row 4 Field hospital, row 5 boss, rows 2-3 rolled from the act weights with the
placement rules (no act-1 row-2 nest, no back-to-back depots/hospitals, a non-combat node on every
path, a nest and a depot every act); links never cross, 1-2 out per node.

### Run actions

`{"type": String, "player": int, ...}` through `RunRules.validate(run, action) -> String` and
`RunRules.apply(run, action) -> bool`. Built in:

| type | fields | |
|---|---|---|
| `vote` | `node` | MAP phase, present players. Resolves when every present player has voted (solo: instantly); majority wins, a split goes to the host's pick |
| `close_vote` | | host only: the 20 s vote timer ran out, resolve with the votes cast |
| `reveal` | `node` | spend 1 Intel to reveal a "?" node |
| `bench` | `target`, `on` | host only (sessions send it when a player drops or rejoins) |
| `fight_end` | `outcome` | host only, once the mission is over: `RunRules.fight_outcome(state, bonus)` |

Prefixed types are routed to the owning module's `validate(run, action) -> String` and
`apply(run, action)`: **`gear_*` -> `GearRun`**, **`prog_*` -> `Progression`**, **`node_*` ->
`NodeRules`**. A module checks its own phase rules (e.g. `gear_equip` in MAP and REWARD, depot
buys only in NODE). Modules change shared values with the helpers `RunRules.add_supplies(run, n,
reason)`, `add_intel`, `add_serum(run, player, samples, reason)`, `add_outbreak`, and
`add_recruit(run, player, kind, infection)`, which emit the matching events. All randomness is
`run.rng`.

### Node flow

```
MAP --vote--> enter_node: Outbreak +1, "?" resolves, then the node's steps:
  fight nodes (skirmish, ambush, nest, boss):  [fight, rewards]
  other nodes (event, depot, hospital, survivors): [node]   (+ [fight, rewards] if pending_fight)
FIGHT   fight_config is set; every peer builds the GameState with MatchConfig.build and plays it.
        The host sends fight_end. Results: HP/Infection copied back, dead/Turned recorded,
        recruits deploy, 25% heal, income (Skirmish 40, nest 50 + 1 Serum sample per soldier
        controlled, boss 60 + 1 sample, +10 Supplies and +1 Intel for a bonus objective),
        boss: Outbreak -3. Then GearRun.on_fight_won(run, "skirmish"|"nest"|"boss").
        A lost fight (squad wiped) ends the run in DEFEAT; the act-3 boss ends it in VICTORY.
REWARD  waits while GearRun.has_pending(run) or Progression.has_pending(run).
NODE    NodeRules.enter(run, kind) opens the screen; waits until NodeRules.is_done(run).
then    back to MAP, or after the boss the next act's map.
```
The run also starts in REWARD if `GearRun.starting_kit_offers(run)` leaves picks pending.

### Hooks other modules implement

All static. Missing ones fall back to the stand-in in brackets.

- **GearRun**: `init_run(run)`, `starting_kit_offers(run)`, `on_fight_won(run, kind)` (roll 1-of-3
  per soldier; after a boss also the Doctrine vote), `has_pending(run) -> bool` [false],
  `apply_to_unit(unit, entry)` (entry is the squad entry, gear in `entry.gear`, Doctrine ids in
  `entry.doctrines`), `absorb(record, unit)` (survivors after a fight: spend used pockets),
  `validate`/`apply` for `gear_*`, `autoplay_actions(run)` (default picks, for autoplay and dropped players). Fight income is the framework's; a skipped pick's +10 Supplies is GearRun's (use
  `RunRules.add_supplies`).
- **Progression**: `new_record(kind) -> Dictionary` [`{kind, rank: 1}`], `apply_record(unit, prog)`,
  `after_fight(prog, unit, fight_number)` (queue rank-up picks), `has_pending(run) -> bool` [false],
  `on_recruit_deployed(new_prog, lost_prog)`, `on_fight_end(run, outcome)` (every fight, after the
  results are applied; may set unlock flags in `run.meta`), `unlocked_classes(meta) -> Array[String]`
  (recruit pool), `validate`/`apply` for `prog_*` (perk picks, grafts, Serum use).
- **NodeRules**: `enter(run, kind)`, `is_done(run) -> bool` [true: the node is skipped],
  `validate`/`apply` for `node_*`, `screen(kind)`, `autoplay_actions(run)`. Events that fight set
  `modifiers.pending_fight`.
- **Objectives**: `bonus_met(state) -> bool` [false], read by `RunRules.fight_outcome`.
- **FightBuilder**: `build(spec) -> {"enemies": Array[String], "encounter": Dictionary}`
  [`MatchConfig.default_enemies`]. `spec` = `{act, row, node, objective, outbreak, seed, players,
  modifiers}`; deterministic from it. Optional `preview(spec) -> {"title", "elite"}` for the map.
- **Encounter**: `setup(state, encounter)`, called by `MatchConfig.build` after the GameState exists.
- **MapGen**: `generate(map_spec) -> Grid` [`maps/mission_01.txt`]. `map_spec` = `{biome ("wall" /
  "port" / "bore" for acts 1-3), objective, seed, act, row, outbreak}`.

Units for run fights are built by `Rules.new_mission_on_grid`; squad entries from a run carry
`sid`, `name`, `hp`, `infection`, `prog`, `gear`, `first_turn_action_loss`, and
`RunSoldier.apply_entry` applies them (Progression, then GearRun, then HP and Infection).

### Screens and sessions

The run view (framework) shows the node map and swaps in each phase's screen. A module screen is
a `Control` with `setup(run: RunState, session)`; it reads `run`, listens to `run.event`, and sends
input with `session.submit_run(action)`. Screens must work for **every player count**: draw a
section for each player in `session.local_players()` (solo and hot-seat: all of them; online: one)
and, for per-soldier picks, one row per soldier that player controls (`run.soldiers_of(p)`), so a
solo player picks for all four. Votes and secret choices from one player resolve at once.
Registered screens: REWARD -> `GearRun.reward_screen()` (returns the script), loadout button on the
map -> `GearRun.loadout_screen()`, NODE -> `NodeRules.screen(kind)`, rank-up picks inside the
reward screen via `Progression.pick_screen()`. Visual target: the approved UI mockups (dark
see-through panels with amber corner marks, amber only for actionable things, teal only for
Infection, player-colour stripes on soldier cards).

Sessions (`LocalSession`, `NetSession`) have `run: RunState`, `submit_run(action)` and a
`run_changed` signal; `App` shows `RunView` (`ui/run/run_view.gd`) between fights and the mission
view during one (held 3 s after the mission ends so the result plays).
- **Solo / hot-seat** (`LocalSession.start_run(players)` / `resume_run(saved)`): no lobby, no
  network. A map click votes for every local player, so solo moves on at once.
- **Online** (`NetSession.start_run()`, host): the host builds the run from a seed (or `resume`, a
  loaded save) and sends the whole RunState once (`_run_start`). After that run actions travel as
  `{"type": "run", "action": ...}` through the same request -> validate -> commit path as mission
  actions, with one sequence number and a checksum covering run and mission. When the run enters a
  fight, every peer builds the same GameState from `run.fight_config`; at `mission_end` the host
  commits `fight_end`. A dropped player is benched (host plays their soldiers from the next fight,
  they don't vote) and unbenched when they rejoin. The host closes a route vote 20 s after its
  first pin (`close_vote`).
- Autoplay (`-- --run=1 --autoplay`, or `--host --autostart=2 --autostart-run --autoplay`) plays a
  whole run headless; `tests/net_playtest.sh` scenario 3 checks host and client finish a run in sync.

### Run events

`run.event(ev)`: `run_start` (`players`, `seed`), `act_start` (`act`), `vote` (`player`, `node`),
`vote_result` (`node`, `votes`), `reveal` (`node`, `as`), `node_enter` (`node`, `node_type`, `row`),
`step` (`step`), `map`, `fight_start` (`kind`, `objective`), `fight_end` (`result`, `kind`),
`soldier_lost` (`sid`, `how`), `recruit` / `recruit_deployed`, `supplies` / `intel` / `outbreak`
(`amount`, `total`, `reason`), `serum` (+ `player`), `bench` (`player`, `on`), `rejected`, `run_end`
(`result`). Modules may add their own; list them here.

### Save / resume

`run.save_string()` / `RunState.from_save_string(text)` (Godot `var_to_str`, so ints and Vector2i
survive). `RunSave` (one slot, `user://run_save.txt`): the host or solo player saves after every
run action and at the start of every team phase in a fight (`fight_snapshot`, so a resume lands in
that turn). Main menu: "Continue run" resumes locally; online, the host ticks "Continue the saved
run" in the lobby and absent players are benched until they join. `Profile` (`user://profile.cfg`)
keeps unlock flags between runs (`act1_boss_beaten`, anything a module sets true in `run.meta`) and
run counts; runs get a copy as `run.meta`.
