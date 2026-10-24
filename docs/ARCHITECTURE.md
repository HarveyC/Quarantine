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
| `objectives/` | `Objectives` | **maps** | Fight objectives: win/lose rules, civilians, bonus objective, HUD line |
| `hazards/` | `Hazards` | **maps** | Fire, spore and acid tiles: placement, hits, ageing |
| `vision/` | `Vision` | **fog of war** | Squad vision, explored cells, hidden enemies, exposure, senses |
| `mapgen/`, `maps/` | `MapGen` | **maps** | Seeded tactical maps from hand-made parcels, per biome and objective |
| `elevation/` | `Elevation` | **maps** | High ground: aim and cover from height, in-fight level changes |
| `gear/` | `GearData`, `Loadout`, `GearTags`, `GearDraw`, `GearRun` | **gear** | Items, loadouts, stash, tags and set bonuses, reward offers |
| `view/`, `ui/`, `scenes/` | various | **view** | 3D board, camera, input, HUD, animations |
| `tutorial/`, `ui/tutorial/` | `Onboarding`, `TutorialScript`, `TutorialSession` | **onboarding** | Training mission, first-time tips, what the player has been taught |
| `net/` | `NetSession`, `LocalSession`, `NetTransport` (`EnetTransport`, `SteamTransport`) | net | Sessions the view talks to; online replication over ENet or Steam (see docs/STEAM.md) |
| `platform/` | `Platform` autoload, `CloudSync`, `CrashReporter` | net | Steam (optional), cloud saves, achievements bridge, rich presence, crash reports |
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
| `mutation` | `unit`, `mutation`, plus `target`/`cell` and effect fields (`leech_bite`: `hit`, `damage`, `healed`; `acid_spit`: `damage`; `rally_musk`/`rampage`/`bloom`: `units`). Passives that trigger also emit one (`second_heart`, `bloom`, `host_body`, `martyr_strain`, `ride_the_wave`) |
| `perk` | `unit`, `perk` (a perk that visibly triggered: `last_stand`, `double_tap`, `brink`) |
| `heal` | `unit`, `amount`, `hp`, `source` (passive heals: `clotting_blood`, `regenerator`, `transfusion`, `feed`) |
| `zone` / `zone_end` | `kind` (`spore_burst`, `growth`), `cells`, (`until`) |
| `lapse` / `recover` / `turned` | `unit` |
| `alerted` | `unit` (an Infected wakes up; emitted once per unit, see Enemy AI) |
| `mission_end` | `result` (`Types.Result`) |
| `hazard` | `kind`, `cells` (changed), `turns`, `source`, `spare` |
| `hazard_tick` | `unit`, `kind`, `cell`, `damage`, `infection` (emitted before the resulting `damage` / `infection` events) |
| `hazard_end` | `kind`, `cells` |
| `level_changed` | `cell`, `level` (Elevation.set_level: a roof collapsed or rose) |
| `objective` | `kind`, `progress`, `goal` (objective progress changed) |
| `rescued` | `unit` (a civilian reached the exit) |
| `left_behind` | `unit` (extract: the dropship left without them; a `died` follows) |
| `gear` | `unit`, `item` (gear effect that isn't a shot: `choke` splash `target`/`damage`, `feral_grip` `heal`/`hp`, `close_set` `actions`, `mark_set` `target`, `suppress` `target`) |
| `burning` / `burn` | `unit`, `turns` / `damage` (set Burning; the start-of-phase tick, before its `damage` event) |
| `spawned` | `unit`, `kind`, `cell`, `from` (spawner unit id or -1) — a new enemy appeared (Hive node, egg sac, root, wave, split, brood spit) |
| `telegraph` | `unit`, `kind` (`burst`/`charge`/`airstrike`/`core_slam`), `cells`, `turn` (when it lands) |
| `strike` | `kind`, `cells`, `unit`, `units` (hit ids), `damage` — a telegraphed airstrike / core slam lands (before its `damage` events) |
| `cover_destroyed` | `cells`, `unit` — half cover turned to floor (Brute charge, airstrike); the grid has changed |
| `source_pulse` | `unit` (the Source), `units`, `amount` |
| `reinforcements_incoming` | `cells`, `turn`, `count` — a wave arrives at these vents next enemy phase |
| `revealed` | `unit` (a hidden Lurker) |
| `pinned` / `released` | `unit` (soldier), `by` (Lurker) |
| `regenerate` | `unit`, `healed`, `hp` |
| `immune` | `unit`, `source`, `reason` (kind it is tethered to) — damage was ignored, no `damage` event follows |
| `untethered` | `unit` |
| `boss_phase` | `unit`, `phase`, `boss`, `text`, plus `hp`/`max_hp` for Hale |
| `boss_defeated` | `unit`, `boss` — the remaining enemies then die |
| `burrowed` | `unit` (a Burrower goes underground: hidden until it erupts) |
| `lock_lost` | `unit` (a Sharpshooter's target broke line of sight, or it was suppressed) |
| `fell` | `unit`, `damage` — knocked off a ledge or its raised tile collapsed (before its `damage` event) |
| `revealed_area` | `cell`, `radius` — a Recon drone shows an area from above for the rest of the fight |

`move` may carry `knockback: true` (Brute slam/charge) and is also emitted for the Source's pull
(the moved unit is the soldier). Enemy abilities (`slam`, `charge`, `burst`, `pounce`, `maul`,
`scream`, `brood_spit`, `airstrike`, `flashbang`, `pull`, `core_slam`) use the `ability` event;
area ones add `cells` and `units`.

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
- **Hive Sense** (legacy MVP mutation, no longer grantable): `unit.status["hive_sense"] = <turn>` still makes
  Combat treat the target's cover as NONE. Mutations are now grafted per soldier, see "Ranks, perks and mutations".
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
  `actions` (action cost), `cooldown` (turns left), `reason` (why not ready, "" if ready), `source` (`own`, `dormant`,
  `borrowed` via Hive Link, `mirror` via Mirror Graft) and `tier`. It lists the soldier's grafted active mutations; dormant
  ones have `ready = false` and reason "Dormant until <tier>".
  Combat adds `cooldown`, `cost` (actions, -1 = ends turn), `desc` and `targets` (legal unit ids for unit-targeted abilities).
- **Hit chance extras**: `hit_chance` also returns `los`, and takes an optional 5th arg `reaction` (overwatch −15).
  `graze` is the width of the graze band above `hit`; `crit` is the crit chance given a hit.
  `Combat.melee_chance` gives claw odds.

## Ranks, perks and mutations (progression/)

Owner: **ranks, perks and mutations**. Design: the doc's Classes and Mutations sections.

| File / class | What it does |
|---|---|
| `perk_data.gd` `PerkData` | Class passives (one per class) and the 7-perk pool per class: `tag`, `rare`, stat grants, granted `ability` |
| `mutation_data.gd` `MutationData` | Every mutation: `slot` (`exposed`/`mutating`/`critical`/`strain`), `awake_at` tier, active/passive, `tag`, graft and use cost, `bonded`, `vector`, `pending` |
| `progression.gd` `Progression` | The run record (`soldier_record.prog`), ranks, perk offers, grafts, Serum, reward cards, tag counts, unlocks, `prog_*` run actions |
| `kit.gd` `Kit` | In-mission hooks for passives, perks and mutation passives (one-line calls from Rules, Combat, Infection, EnemyAI) |
| `mutations.gd` `Mutations` | Active mutations: list, validate, apply (Infection delegates its mutation API here) |
| `class_abilities.gd` `ClassAbilities` | Incinerate, Siphon, Purge, Decon Shower, Squad Leader's order, Talk Down, Serum (Combat delegates ids it doesn't know) |
| `zones.gd` `Zones` | Spore Burst clouds and Overgrowth walls in `GameState.zones` (Incinerate fire and Overgrowth spores are `Hazards`) |
| `pick_screen.gd` | Rank-up perk picks and mutation offers (`Progression.pick_screen()`, hosted in the reward screen) |

**Unit status keys** (stamped by `Progression.apply_record`): `perks` (Array), `mutations` ({slot: id}), `rank`,
`bond` (`{"id", "partner"}` unit id or `"partner_sid"`), `inoculated` (half Infection gain), `cured` (a mid-fight Serum
happened; `after_fight` wipes the record's mutations), `serum` (full cures this soldier can give mid-fight; whoever owns
Serum stock sets it). Kit's own bookkeeping keys start with `k_`.

**Rules of the system.**
- Rank 1-5; `after_fight(prog, unit, fight_number)` ranks up after run fights 1, 3, 5, 7 and queues a pick. Each rank is
  +1 max HP (`Progression.max_hp`). A perk offer is 3 from the class pool minus owned, rares from Rank 4, deterministic
  from `run.seed`, the soldier id and `picks_taken` (`Progression.perk_offer(run, record)`), so no offer state is stored.
- A mutation is awake while `Infection.tier(unit.infection) >= MutationData.awake_at(id)`; dormant ones do nothing and
  count for no tags. Graft adds +10/+15/+20 Infection to the soldier record (capped at 99 between fights); actives cost
  5/10/15 per use, modified by Sealed Suit (+5), Willing Host and Apex (-5 each, minimum 5) and Patient Zero (0).
- Modifiers ignore Infection added before turn 1 (`s.turn == 0`), so restoring carried Infection is exact.
- Serum: `Progression.full_cure(record)` between fights (or the `prog_serum` action for 4 of the player's samples);
  the `serum` ability mid-fight (adjacent ally, 2 actions). Both wipe every mutation and leave the soldier Inoculated
  (half Infection gain) for 2 fights.
- Tag counts for GearTags: `Progression.tag_counts(record)` / `unit_tag_counts(unit)` (perk tags + awake mutation tags,
  +1 Strain per awake mutation; only tags above 0; names are `Progression.TAGS`).
- Reward cards for GearRun: `perk_card(rng, record)`, `mutation_card(rng, record)`, `apply_card(record, card)`;
  nests: `queue_nest_offer(run, record)` (picked with `prog_graft`, may hold a Bonded card with a partner).
- NodeRules hooks: `grant_random_mutation(run, record)`, `mutations_of(record)`, `remove_mutation(record, id)`,
  `grant_perk_pick(run, record)`, `mutation_name(id)`, `full_cure(record)`.
- Unlocks: `unlocked_classes(meta)` (base 4, `hazmat` with `act1_boss_beaten`, `vector` with `vector_unlocked`);
  `on_fight_end(run, outcome)` sets `vector_unlocked` when a won fight ends with a Mutating+ soldier who didn't Turn.

Run actions (`prog_*`, need `player` = the soldier's controller, not during a fight): `prog_perk_pick` {`sid`, `perk`},
`prog_graft` {`sid`, `mutation`, `partner` for Bonded}, `prog_skip_offer` {`sid`}, `prog_serum` {`sid`}.
Run events: `perk_pick` (`sid`, `perk`), `graft` (`sid`, `mutation`), `cured` (`sid`), `class_unlocked` (`kind`).

**Simplifications vs the doc** (worth a later pass): Hive Hush
only stops dormant Infected spotting you beyond 4 tiles; Lure Scent's aim bonus applies to reaction shots at enemies
within 6 tiles of you; Hollow Voice makes the target attack its nearest ally now and skip its next turn; Rampage moves
without triggering overwatch; Overgrowth turns empty cells into walls (the view doesn't draw zones yet); Firewall
is just the line shape (the AI already avoids fire through Hazards). Spore Sense is live through `Vision.sense_radius`
(and its double spore Infection in `Hazards`).

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
- **Run hooks** (`GearRun`, the run framework's contract): `init_run` (also gives every soldier, reserve
  included, 1 charge of their class consumable, `GearData.STARTER_CONSUMABLES`), `on_recruit(run, record)`
  (called by `RunRules.add_recruit`, same starter), `starting_kit_offers` (1 of 3
  Commons per soldier), `on_fight_won(run, "skirmish"|"nest"|"boss")` (one 1-of-3 offer per squad soldier:
  gear 37%, gun 8%, perk 15%, mutation 15% (Progression cards), consumable 15%, cache 10%; from the
  second fight an on-build card and a pivot card; nest card 1 Rare in the lead tag; boss all Rare, its
  last card an alternate gun for the soldier's class, plus the Doctrine vote; Hazard pay), `has_pending`, `apply_to_unit(unit, entry)` (flat stats, Bio-mesh, stamps
  `status["gear"]`, `["gear_tags"]`, `["pockets"]`, `["armor"]`, `["doctrines"]`), `absorb(record, unit)`
  (spent pocket charges), `squad_counts(run)`. Doctrines live in `run.modifiers.doctrines`; Field rations
  sets `run.modifiers.heal_after_fight`.
- **Run actions** (`gear_*`, routed by RunRules): `gear_pick {soldier, card (-1 = skip, +10 Supplies),
  to_stash?}` and `gear_doctrine {doctrine}` in REWARD; `gear_stash_take {soldier, index}` and
  `gear_unequip {soldier, slot}` and `gear_gun {soldier, gun ("" = signature)}` in MAP or REWARD. The
  soldier's controller (`run.controller_of`) acts.
- **Guns** (`combat/weapons.gd`): every class has a signature gun (`BY_KIND`) and alternate guns
  (`classes`, `rarity`, `tag`, flat `aim`/`dmg`/`mobility`, `look`). A soldier's owned alternates are
  `record.gear.guns`, the one carried `record.gear.gun` (`Loadout.gun`, `add_gun`, `set_gun`,
  `gun_pool`); its tag counts toward set bonuses like gear. `apply_to_unit` stamps
  `status["weapon"]` (`Weapons.equip_unit`), which `Weapons.of(unit)` and the view (feel in
  `view/gun_feel.gd` VARIANTS, model in `view/gun_models.gd` by look) read.
- **In a mission** (`GearFx`): one-line hooks in `Combat.hit_chance` (`odds_terms`), `Combat.fire`
  (`shot_damage`, `after_shot`), Combat's Suppress (`on_suppress`), `Rules.deal_damage` (`damage_taken`:
  armor), `Rules.start_team_phase` (`on_team_phase_start`: Burning ticks, Close set mobility), `Rules._do_move`
  (`on_move`) and `Infection.on_damaged` (`bite_infection`). Gadgets and pocket consumables are abilities
  with ids `gear:<item>` / `item:<consumable>` that Combat delegates to GearFx (they appear in
  `Combat.available_abilities` with `"gear": true`). Status keys: `burning` (ticks left), `suppress_extra`,
  `smoked`, `contained`, `gear_uses`, `gear_moved_turn`, `gear_refund_turn`, `gear_set_mobility`,
  `burn_source`, `gear_fire_mobility`. Fire from gear (Thermite line, Igniter barrel, Burn set spread)
  goes through `GearFx.set_fire` -> `Hazards.add(..., "fire", turns, unit.id)`, and `Hazards._hit` asks
  `GearFx.hazard_hit` (Flame-retardant coat, Filter mask, Scorched earth, Spotter flare). Sentry turret
  spawns a Deployables turret. `GearFx.PENDING` lists items whose systems don't exist yet (
  restraint, mutation costs); they stay out of draws until they work.
- **Gear max HP** (Kevlar vest etc.): `Loadout.equip / unequip / upgrade` move the run record's
  `max_hp` and `hp` by the change, so the record always holds HP including gear.
- **Screens** (`ui/gear/`): `GearRun.reward_screen()` and `GearRun.loadout_screen()` return Control
  scripts with `setup(run, session)` (they send `session.submit_run`); the loadout screen emits `closed`.
  `scenes/gear_demo.tscn` previews them on a seeded run (`-- --screen=reward|loadout|doctrine|kit`).

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
- **Depot**: 8 slots (gear 1 Common/Uncommon weighted to the squad's tags, gear 2 Uncommon or
  Rare from act 2, 1 alternate gun for a squad soldier's class (55 Uncommon / 90 Rare), 3 different consumables, 1 Serum dose for 50 once per depot, 1 service rolled from
  Armorer / Recruit 45 / Scar removal 40), reroll 20 then 35 (keeps Serum and the service), sell
  back at 40%, Quartermaster Doctrine −15%. Buyers pick one of their own soldiers.
- **Hospital**: one treatment per soldier by its owner; Patch up (full HP, −1 injury), Purge (−30
  Infection, 15 Supplies), Train (extra perk pick), Full cure (2 doses). Healing or purging anyone
  raises Outbreak by 1 once per visit; Train doesn't.
- **Survivors**: +10 Supplies on entry and one recruit; the first `node_claim` takes them,
  otherwise they join the smallest reserve when everyone leaves.

Node events (`run.event`): `event_start` (`event`, `subject`), `event_step` (`event`, `step`, `kind`),
`event_choice` (`player`, `step`, `option`: empty for secret picks), `event_vote` (`option`, `votes`),
`event_reveal` (`picks`), `event_end` (`event`, `results`, `fight`), `item_gained` (`sid`, `item`), `gun_gained` (`sid`, `gun`),
`soldier_hp` / `soldier_infection` / `soldier_mutation` / `perk_pick` / `full_cure` / `sit_out`
(`sid`, ...), `modifier` (`key`, `value`), `depot_open`, `depot_bought`, `depot_sold`,
`depot_reroll`, `hospital_open`, `hospital_treat` (`soldier`, `treatment`), `survivors_found`,
`node_leave` (`player`).

Screens (`ui/nodes/`, look from the approved mockups via `NodeUi`) extend `node_screen.gd`: they
rebuild from `run.node_state` after each run event and send input with `session.submit_run`. Every
button's enabled state comes from `NodeRules.validate`, so the screen and the rules can't disagree.

## Tactical map generator (mapgen/)

`MapGen.generate(spec) -> Grid` builds a fight's map XCOM 2-style: a **plot** (a whole-map layout
of slots) is filled with hand-made 4x4 **parcels**, each rotated or mirrored, then checked and
rerolled until it passes. Design rules are in the design doc's "Tactical maps" section.

- **Input**: `spec = {"biome", "objective", "seed"}` (other keys ignored). Biome "wall" (act 1) has
  parcels; "port" and "bore" fall back to it until `maps/biome_port.txt` / `biome_bore.txt` exist.
  Objective is skirmish / extract / hold / rescue / purge / elite / boss; unknown ones use skirmish.
- **Determinism**: its own RNG seeded from the spec (never `state.rng`), so every peer generates the
  same map from the `MatchConfig` the host broadcasts. A resync snapshot also carries the grid.
- **Content**: `maps/biome_<name>.txt` holds the parcels and plots; its header documents the format.
  Add parcels there to add variety, no code needed. Sizes: 16x16 or 19x19 (skirmish), 16x16 (elite),
  19x19 with 1-tile lanes (hold, rescue, purge), 16x20 (extract), 20x20 (boss). Most plots have 2-3
  `T` tower slots (high ground parcels).
- **Checks** (`_validate`, rerolled up to 30 times, then `maps/mission_01.txt`): every spawn and
  marker reachable from the drop zone, sealed pockets walled in, each pod's nearest cell 6 to 20 steps
  out, evac 12+ and other objectives 5+ steps out, nests 5+ apart, the cordon wall keeps 2+ gaps,
  cover density in band. Fix-up passes add half cover to dead ground and full cover to long open
  sightlines without ever sealing a path. `tests/test_mapgen.gd` asserts no fallback across seeds;
  `godot --headless -s tests/dump_maps.gd -- all 300` prints maps and the fallback rate.
- **Output** (`Grid`): `player_spawns` (4+ deploy cells, row-major), `enemy_spawns` (8+ cells,
  round-robin across pods so the first N spread out), `biome`, and `markers` (`grid.marker(key)`):

| marker | cells |
|---|---|
| `evac` | extract: 2x2 evac zone |
| `beacon` | hold: 3x3 beacon zone |
| `civilian` | rescue: 1-2 civilian start cells; `exit` = the deploy cells |
| `nest` | purge: 3 nest cells |
| `hive` | 1 cell: the elite parcel's Hive spot, else the open cell farthest from deploy (every map) |
| `boss` | boss: the centre cell, with open ground 2 tiles around it |
| `reinforce` | 4-6 edge cells 6+ steps from deploy: behind the squad (extract), side edges (hold), near civilians (rescue), far edge otherwise |

The view paints `evac` and `beacon` zones on the floor (`Board._build_zones`). For a look at a
generated map: `godot res://scenes/main.tscn -- --seed=5 --objective=hold --screenshot-action=overview --screenshot=x.png`.

## High ground (elevation/)

Three levels: ground (0), roof (1), upper roof (2). Data on the `Grid`: `level(c)`, `is_ladder(c)`,
`is_stairs(c)`, `is_fragile(c)`, `has_levels()`, all serialized in `to_dict`. Glyphs are read by
`Grid.read_glyph` (shared by handmade maps and MapGen): `^` roof, `%` half cover on a roof, `~`
fragile roof (scaffold), `2` upper roof, `$` half cover on it, `/` ladder and `s` stairs on the
ground, `|` ladder and `S` stairs on a roof; MapGen also reads `e` (enemy spawn on a roof).

- **Movement** (`Grid.step_cost`, Dijkstra in `reachable`/`find_path`, which return/minimise move
  cost): flat steps cost 1. Going up one level must be straight and needs stairs (cost 1) or a ladder
  (`Grid.LADDER_COST` = 2) at either end. Going down works the same way, or by dropping off any ledge
  (one way, 1 per level dropped, no damage). Diagonals never cut wall or ledge corners.
  `ignore_levels := true` (leapers, flyers) changes level anywhere for 1. `Grid.path_cost` sums a path.
- **Shooting** (`Combat.hit_chance` calls `Elevation`): from higher ground +10 aim ("High ground" in
  the breakdown, same for 1 or 2 levels up) and the target's cover counts one step lower. Shooting up
  at a higher target, it has at least half cover. Height never makes a shot a flank.
  `Combat.cover_against`: a raised block beside the target is a building wall, full cover against
  shooters below its roof.
- **Sight** (`Combat.can_see`): a raised cell blocks the line when it is higher than both ends
  (a flyer counts as at least level 1). Vision sight radius +2 per level.
- **Changing levels** in a fight: `Elevation.set_level(s, cell, n)` only (emits `level_changed`,
  drops ladders/stairs that join nothing, clears `fragile` at ground). `Elevation.blast(s, center,
  radius, by)` collapses fragile cells in the area (frag grenade radius 1, airstrike cells) and units
  on them fall (`fell`, 2 damage per level). The Burrower's collapse is `EnemyTerrain.collapse`.
- **View**: `Board.cell_to_world` lifts cells by `Board.RAISE` per level. Roofs are grey steel decks,
  upper roofs paler, scaffolds plank decks on poles with a tarp skirt; amber lips on ledges; ladders
  and stairs drawn on their climb side. Mouse picking tries the highest level's plane first.
- **MapGen**: 8x8 `@landmark` parcels fill a 2x2 block of `L` slots (lanes=0 plots). Validation: every
  walkable cell must walk to and back from the drop zone (one-way pits are sealed), 6-35% raised
  cells, at least 2 stairs/ladders. Dev aid: `-- --objective=hold --biome=wall --screenshot-action=map`
  renders the whole map with fog and HUD off.

## Objectives (objectives/)

The objective comes with the map: `grid.objective` (set by MapGen, saved with the grid). Progress is
`GameState.objective` (saved in `to_dict`). A fight ends the moment its objective is met.

| objective | win | loss (besides a squad wipe) |
|---|---|---|
| skirmish, elite, boss | every enemy dead | |
| extract | every living soldier on `evac` at the end of a squad turn | after turn 7 soldiers off the pad die (`left_behind`); defeat if none made it |
| hold | 4 rounds survived (`held`) | end of a round with enemies and no soldier in `beacon` |
| rescue | every living civilian on `exit` (kills win only once no civilian is alive) | |
| purge | no living unit of kind `spore_nest` (or every enemy dead) | |

- **Hooks**: `Objectives.setup(s)` at the end of `Rules.new_mission_on_grid`; `on_team_phase_end`
  (after hazards, from `Rules.set_ready`) and `on_enemy_phase_end` (after hazards); `Rules.check_end`
  uses `Objectives.check(s)` after the squad-wiped test. Squad = `Objectives.soldiers(s)` (no
  deployables, no civilians). Tests fake a win with `s.objective.result = Types.Result.VICTORY`.
- **Civilians** (rescue): player-team units with `status.civilian`, `owner_player = -1`, not
  `ai_controlled`; at each squad turn's end they make one MOVE toward the nearest soldier (overwatch
  and hazards apply), and step onto the exit when a soldier is within 3 tiles. Enemies target them.
- **Bonus** (`Objectives.bonus_met(s)`, used by `RunRules.fight_outcome`): extract nobody left
  behind; hold the beacon never contested; rescue every civilian saved; skirmish / elite / purge
  won by the end of turn 5; boss none.
- **HUD**: `Objectives.describe(s)` is the objective line under the turn banner.

## Fog of war (vision/)

Owned by the fog of war workstream. `Vision` is pure rules like `Combat`; the view only reads it.

- **Shared squad vision**: a cell is visible when any living squad unit (soldiers and deployables, not
  Lapsed soldiers) is within its sight radius and `Combat.can_see` it. Sight: soldiers 8, Marksman 10,
  turret 6, enemies 8 (`Vision.KIND_SIGHT`), +2 on high ground (`Elevation.height` > 0), plus
  `status["sight_bonus"]` for perks or gear. Queries: `sight(s, u)`, `cell_visible(s, team, c)` (cheap),
  `sees_unit(s, team, t)`, `visible_cells(s)`, `fog_grid(s)` (per cell `UNEXPLORED`/`EXPLORED`/`VISIBLE`),
  `is_explored`, `visible_enemies`. `Vision.disable(s)` turns fog off for a fight (other modules' tests).
- **Line of sight by height** (`Combat.can_see`): between two ground-level cells a raised cell blocks
  like a wall; if either end is high (raised cell, or a flying unit on it) roofs don't block.
- **Shooting**: squad units can only target enemies the squad sees (`Combat.visible_targets` adds
  `Combat.in_squad_sight`), still within their own line of sight and weapon range (14): spotting for
  each other matters. Suppress, Tag and Breach need it too. `Combat.shot_targets(s, u)` adds Smart-link
  shots; the HUD and input use it. **Enemy targeting and activation are unchanged** (fog is the
  players' information problem; the AI keeps its own rules, which keeps the roster's balance).
- **Hidden enemies** act exactly as before. Their intents and danger tiles are hidden
  (`EnemyIntent` filters by `Vision`; telegraphed strikes and Burrower eruptions still show), and
  hidden Lurkers only show their ripple inside vision (`EnemyIntent.ripples`). `status["hidden"]`
  units (Lurker, burrowed Burrower) are never seen and never trigger overwatch.
- **Firing gives you away**: an attacker (SHOOT or a unit ability at a hostile, the cell attacks in
  `Rules.EXPOSING_CELL_ABILITIES`, or any damage through `Rules.deal_damage`) is exposed for 2
  half-turns (`Vision.expose`): an enemy that shoots from the dark stays visible through the next
  squad phase and can be shot back.
- **Overwatch** covers the watcher's own sight radius (+ Rangefinder 2/3), not the squad's
  (`Vision.overwatch_sees`); Twin Sight (`Kit.shared_sight`) adds the partner's vision.
- **State** `GameState.vision` (saved, resynced, checksummed): `explored` (PackedByteArray),
  `exposed` {id: phase index}, `last_seen` {id: cell}, `blips` {id: {cell, until}}, `reveals`
  [{cell, radius, until}]. `Rules` calls `Vision.refresh` after every action, at team-phase start
  (before the `team_phase` event, so run snapshots carry it) and after each enemy's turn, and
  `Vision.on_step` for every step of a move (soldiers explore as they walk).
- **Senses**: Spore Sense (awake mutation, or `status["sense_radius"]`) senses infected enemies within
  6 tiles through walls: `Vision.sensed(s)`, drawn as see-through ghosts with intents, not targetable.
  Motion tracker: an enemy moving within 8/12 tiles in the enemy phase leaves a blip until the end of
  the next squad phase (`Vision.blips`). Recon drone (pocket, range 10, no line of sight needed):
  `Vision.add_reveal(s, cell, 6)` shows that radius from above for the fight. `Vision.last_seen(s)`:
  where enemies out of sight were last seen.
- **Online: full state, fog drawn view-side.** Every peer runs the same `Rules.apply` on the same
  actions (lockstep, checksums, snapshot resync), so every peer must hold the whole state, and vision is
  computed from it identically. Filtering would mean replacing lockstep with host-sent state diffs. The
  game is co-op, so nobody has an opponent to cheat against; a client reading memory only spoils
  their own game.
- **View** (`view/fog_overlay.gd`): a full-screen pass rebuilds world position from depth and darkens
  by a one-texel-per-cell fog texture (visible clear, explored dim and desaturated, unexplored near
  black with drifting haze), cross-fading as soldiers move. `MissionView._on_state_event` tags each
  event with what the squad saw at that moment (`FogOverlay.annotate`: `_unseen`, `_sensed`, `_fog`,
  `_seen` per path cell of an enemy move, `_hidden`); the event player applies it as the beat plays,
  so enemies appear and vanish mid-walk, unseen enemies' beats and log lines are skipped, and hidden
  views can't be hovered (`unit_view_at`). `IntentOverlay` draws last-seen "?" markers and blips.
- Dev aid: `-- --screenshot-action=scout` (a soldier walks out, leaving explored fog behind).

## Tile hazards (hazards/)

One shared system for ground effects; gear, class abilities, mutations, enemies and maps all call it.

- **State**: `GameState.hazards` = `{cell: {"kind", "turns", "source", "spare"}}`, one hazard per cell,
  saved in `to_dict` (so it is in the checksum and resyncs). No RNG.
- **Kinds** (`Hazards.KINDS`): `fire` 2 damage, `spore` +10 Infection to soldiers (enemies immune),
  `acid` 1 damage. Each lists the kinds it `replaces` on its cell (fire burns spores and acid away) and
  an AI `avoid` weight. Deployables (`status.deployable`) and Turned units take no Infection.
- **Add / remove**: `Hazards.add(s, cells, kind, turns, source_id := -1, spare_team := -1) -> Array[Vector2i]`
  (walls skipped; `turns` in rounds, `Hazards.PERMANENT` = -1; `spare_team` makes it harmless to that
  team, e.g. a squad-safe burn). Same kind keeps the longer duration. `Hazards.remove(s, cells, kind := "")`.
- **Hits**: once per move per kind crossed or ended on (`Rules._do_move` -> `Hazards.on_move`), and at
  the end of the unit's own side's turn while standing in one (`on_team_phase_end` from `Rules.set_ready`,
  `on_enemy_phase_end` at the end of `Rules.run_enemy_phase`). Damage via `Rules.deal_damage` (no
  source), Infection via `Infection.add`. Hazards age by one round at the end of the enemy phase.
- **Queries**: `Hazards.at(s, cell)`, `cells_of(s, kind)`, `affects(u, kind)`, `avoid_cost(s, u, cell)`
  (0 if harmless to `u`) for AI cell scoring.
- **View**: `Board.set_hazard` / `clear_hazard` / `sync_hazards`, driven by the events above.

## View presentation (cinematics, animation, sound)

All of this is view-only and driven by event data, so it never touches `GameState` and every peer
in an online match plays the same thing.

- **Shot cinematics** (`view/event_player.gd`): `shot` events and the `claw` / `breach` abilities cut
  the camera over the shooter's shoulder (`CameraRig.cine`), push in, fly the round in slow motion
  (`EventPlayer.world_scale` slows unit animation and FX, not the beat clock), hit-stop on impact,
  and hold through the following `damage` / `died` / `infection` / `turned` / `alerted` beats
  (`CINE_FOLLOW`). Any other event, or the queue draining, cuts back to the tactical camera.
  Skipped when `EventPlayer.cinematics` is false (C key) or playback is sped up (autoplay).
- **Unit models** (`view/unit_view.gd`, `view/skinned_body.gd`, `view/model_kit.gd`): every
  unit but the props is a skinned character (`assets/characters/*.glb`, built by
  `tools/build_characters.py` from CC0 Quaternius base bodies plus our gear and growths; the
  Lurker and Burrower are on the Quaternius spider rig). Humanoids share one skeleton and play
  clips from `anims_ual1/2.glb` (Universal Animation Library), advanced from `tick` so slow
  motion slows them: idle / jog / crouch loops, hit, melee and spit one-shots, death seeked by
  progress. Armed units carry the weapon on a "gun" bone that is posed procedurally (low ready
  to shouldered, recoil, chest bladed when aiming) and both arms are bent onto its grips by
  two-bone IK. Turned soldiers switch to the infected clips. Props and the Drifter
  (`assets/models`, `tools/gen_models.py`) are static and breathe. Per-kind body size is
  `ModelKit.SIZE`. `view/character.gdshader` adds grime, camo, rim light, spreading infection
  veins and hit flash (skinned meshes read rest positions from vertex colours so the noise
  stays put); growth meshes `grow1..3_*` appear per infection tier.
  Calls: `set_moving`, `set_aim`, `recoil`, `hit_react`, `set_lunge`, `muzzle_world`, `chest_world`.
- **Facing**: `face_towards` turns units smoothly (`TURN_SPEED`) toward their path and targets;
  after every playback drain `MissionView.face_threats` turns each unit to its nearest hostile
  (dormant enemies keep their own headings). It reads only the shared state, so peers agree.
- **Sound** (`view/sfx.gd`): `MissionView.sfx.play(name)`; files in `audio/` are synthesized by
  `tools/gen_sfx.py`. `Sfx.muted` is the M key toggle (mutes the Master bus).
- **Music and soundscape** (`view/soundscape.gd`, autoload `Soundscape`): picks a mood from what's
  on screen (title, route map, rest nodes, fight, boss fight, after a fight, run summary) and
  crossfades music and the ambience bed (per act: The Wall, Port Ardent, The Bore). Combat music
  is synced stems (base, pulse, danger, bloom) whose volumes follow `Soundscape.combat_info(view)`:
  visible enemies, low HP, the enemy turn and squad Infection. Boss fights use the boss stems.
  Stingers for contact, boss, win/lose, node arrival and spoils. `view/enemy_voices.gd` plays
  per-kind barks and death cries in 3D from the event player's beats. Every BaseButton gets
  hover/click sounds (set meta "silent" to opt out). Files in `audio/music`, `audio/amb`,
  `audio/vo`, `audio/ui` come from `tools/gen_music.py`.
- **Buses** (`default_bus_layout.tres`): Master > Music (ducks under Weapons), Ambience,
  SFX > Weapons, Voices, and UI. The Sound panel (`ui/audio_settings.gd`, F10 or the title
  screen) saves per-bus volume to `user://audio.cfg`.
- **Look**: environment and lights in `MissionView._build_environment`, set dressing in `Board`,
  vignette and grain in `view/post_fx.gd`.
- **Settings** (`view/game_settings.gd`, static class `GameSettings`; autoload `SettingsHost` in
  `view/settings_host.gd`): graphics (window, v-sync, FPS cap, quality preset, 3D render scale),
  gameplay (game speed, shot cams, edge scroll, camera speed), accessibility (colour vision filter,
  UI scale, text size, screen shake) and key bindings, saved to `user://settings.cfg`. View-only,
  never sent over the network. Read values with `GameSettings.get_value(section, key)` or the
  helpers (`game_speed()`, `screen_shake()`, `puddle_lights()`...). A scene that builds an
  `Environment` calls `GameSettings.apply_environment(env)` so the quality preset can drop SSAO,
  SSIL and volumetric fog. Text built with `Styles.label/caps/mono/bold` follows the text size.
  The screen is `ui/settings_menu.gd` (F10, gamepad Back, `GameSettings.open_menu(tab)`).
- **Input actions**: fight and camera controls are InputMap actions built by
  `GameSettings.apply_input_map()` (`GameSettings.ACTIONS` for keys, `GameSettings.PAD` for the
  fixed gamepad layout); use `event.is_action_pressed("ready")`, never raw keycodes, so rebinding
  works. `GameSettings.action_label("ready")` gives the current key for help text. The gamepad
  pointer in `SettingsHost` turns the left stick into mouse movement and A/B into click/Escape, so
  plain mouse UIs work on a pad; a screen that wants focus navigation instead joins the group
  `pad_focus` (the pointer then stands down and Godot's `ui_*` actions drive it).

## Networking (online co-op)

Host-authoritative, action-replicated, over Godot's built-in ENet. This builds on the rule that
every state change goes through `Rules`: peers never diverge as long as they apply the same actions
in the same order on the same seed.

- **`core/match_config.gd` (`MatchConfig`)**: a serializable description of a mission (map, squad,
  enemy list, seed). `squad_plan(players, picks)` decides who plays what: solo is a squad of 4 for
  player 0, co-op is one soldier per player, of the class they picked in the lobby
  (`NetSession.pick_class`, stored as `lobby[id].class`) or the first class nobody took. Every peer builds an identical `GameState` from it.
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
involved (`LocalSession`). In co-op each player controls one soldier (squad size = player
count) plus their own reserve recruits; a player whose soldier is down in a fight is counted as
ready automatically (`Rules._auto_ready`) and watches until a recruit deploys after the fight.

### Modules and owners

| Folder / class | Owner | What it does |
|---|---|---|
| `run/` `RunState`, `RunRules`, `RunMap`, `RunSoldier`, `RunHooks` | **run framework** | Run state, map generation, route vote, node flow, fight setup and results, income, save/resume |
| `core/match_config.gd` `MatchConfig.for_fight` / `build` | run framework | Turns a fight node into a mission config, builds the GameState |
| `story/` `Story`, `StoryProfile`, `StoryData` (+ `ui/story/`) | **story** | Wave count, Echoes, intel logs, the ending vote; scenes and radio |
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
(read-only copy of profile unlock flags such as `act1_boss_beaten`, `vector_unlocked`, plus
`packs`, `severity`, `start_flags`), `tally` (MetaProgress).

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

### Meta progression (between runs)

`meta/` owns what carries between runs (design doc, "Economy and rewards"):
- **`Profile`** (`run/profile.gd`, file `Profile.path`, default `user://profile.cfg`): unlock flags,
  Field Data balance, owned packs, Severity, lifetime stats, run log and achievements.
  `Profile.meta()` is copied into `run.meta` with `packs` (owned unlocks) and `severity` (picked
  level). `record_run(run, player)` runs on every peer (each player earns their own Field Data)
  and folds only flags earned during the run (`run.meta.start_flags` are skipped).
- **`MetaProgress`**: `run.tally` (fights won by kind, bosses by act, bonus objectives, dead,
  Turned), Field Data (15 skirmish, 25 nest, 60 act boss, 120 the Source, +10% per Severity level),
  run log entries.
- **`MetaUnlocks`**: Field Data packs. Content listed in an unowned pack is locked: `bind(meta)`
  runs in `RunRules.new_run` and `RunState.from_dict`, and the draws (GearDraw, the Doctrine vote,
  MutationData pools) skip `is_locked(id)`. Unlisted content is always available; a meta with no
  `packs` key (tests, tools) locks nothing. Online, the host pools every lobby player's packs.
- **`Severity`** 0-10 (the doc's "Outbreak levels"): stacking rules applied in `new_run`,
  `MatchConfig.for_fight`, depot prices, fight income and the boss Outbreak drop.
- **`Achievements`**: `DEFS`, `unlocked()`, `is_unlocked(id)`, `on_unlocked(cb)`, `stats()` for
  store integrations; ids are stable.
- UI: `ui/meta/field_hq.gd` (Field HQ from the main menu); dev shot `tools/shot_field_hq.gd`.

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
`NodeRules`**, **`story_*` -> `Story`**. A module checks its own phase rules (e.g. `gear_equip` in MAP and REWARD, depot
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
  squad, modifiers}`; `squad` is the number of soldiers deploying, and FightBuilder scales the
  threat budget, enemy cap, waves and boss health to it (`SQUAD_BUDGET`, `SQUAD_BOSS_HEALTH`); deterministic from it. Optional `preview(spec) -> {"title", "elite"}` for the map.
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
view during one. When a fight ends the mission stays up for the debrief (`ui/fight_debrief.gd`:
a short beat on the last action, a "Mission complete" / "Squad lost" banner and each soldier's
kills, wounds and Infection, read from `unit.status` `kills`, `start_hp`, `start_infection`), then
fades into the run view. The debrief is local presentation: each peer builds it from its own
identical GameState, and a player who skips it only moves themselves on.
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
(`result`). Story adds `echo_met` (`key`, `name`), `echo_laid` (`key`, `name`), `lore` (`id`),
`ending_vote`, `ending_voted` (`player`, `ending`) and `ending` (`ending`, `carrier`). Modules may
add their own; list them here.

### Save / resume

`run.save_string()` / `RunState.from_save_string(text)` (Godot `var_to_str`, so ints and Vector2i
survive). `RunSave` (one slot, `user://run_save.txt`): the host or solo player saves after every
run action and at the start of every team phase in a fight (`fight_snapshot`, so a resume lands in
that turn). Main menu: "Continue run" resumes locally; online, the host ticks "Continue the saved
run" in the lobby and absent players are benched until they join. `Profile` (`user://profile.cfg`)
keeps unlock flags between runs (`act1_boss_beaten`, anything a module sets true in `run.meta`) and
run counts; runs get a copy as `run.meta`.

## Training and first-time tips (tutorial/, ui/tutorial/)

Owned by the onboarding workstream. Visual first: tile markers, arrows and short captions, no
text walls.

- **`Onboarding`** (`tutorial/onboarding.gd`): what this player has been taught, in the profile
  (`user://profile.cfg`, section `onboarding`): `training_done`, `training_offered`, `hints_off`, and
  `hint_<id>` per tip shown. `should_offer_training()`, `hints_enabled()` / `set_hints_enabled(on)`,
  `reset_hints()` (for a settings screen). Each machine has its own profile, so online every player
  gets their own tips.
- **Training mission**: `TutorialScript` (pure, like `Rules`) builds a fixed map (`maps/tutorial.txt`,
  Trooper + Marksman for player 0) and runs 12 lessons in `STEPS`: welcome and camera, move, cover,
  Ready / team phase, fog of war, hit chance, high ground, overwatch, clear, Infection and a mutation,
  Turning, purge the nest. Each lesson has a goal read from the state (a soldier on a marked tile, an
  enemy spotted, a reaction shot, a mutation used...) and a set-up when it starts (a Runner in the
  fog, a wave of two, a dose of Infection) that goes through `EnemyRoster` / `Encounter.spawn` /
  `Infection.add`, so the view plays it like any fight. A hidden spore nest walled into a corner keeps
  the fight open between lessons and dies at the end. `TutorialSession` (a `LocalSession`, never
  saves) ticks the script after each change. Main menu "Training", or `-- --training`
  (`--training-step=N` opens on lesson N for screenshots).
- **Overlay** (`ui/tutorial/tutorial_overlay.gd`, added to the HUD by `App`): the lesson card top right,
  amber markers on the lesson's tiles (`cell_markers.gd`), an arrow to the HUD piece it is about
  (`ActionBar.find_button(key)` / `ready_button()`, target panel, roster), and its own "Training
  complete" card instead of the Victory screen. It hides while the event player is busy.
- **First-time tips** (`ui/tutorial/coach.gd`, on its own layer in `App`): watches the run view
  (`RunView.hint_target(key)`) and the fight's events and shows one short card per moment: route
  map, Outbreak, Intel, spoils, loadout, each node kind, the squad phase, Infection, Lapse, Turned,
  telegraphed strikes, reinforcements. Fight tips fire only for this machine's soldiers. Off for
  `--autoplay` and screenshot runs (`--hints` turns them back on). It also asks a new player
  "play training first?" before their first run from the menu.

## Deployables (turrets, decoys)

Owned by the run framework (`deployables/`, `Deployables`). Tile hazards (fire, spore, acid) are
the map thread's `Hazards` module.

- `Deployables.spawn(s, kind, cell, owner_unit, turns = -1) -> Unit` places one; call it from inside
  an action's apply (a gadget, ability or mutation) so it replicates with that action.
  `can_place(s, kind, cell) -> String` checks first. Kinds and stats are in `Deployables.KINDS`
  (`turret`: shoots, 3 team phases; `decoy`: draws enemy fire, 2 team phases); add new kinds there.
- A deployable is a player-team `Unit` with `status["deployable"] = kind`, `ai_controlled`, mobility 0,
  `status["owner_unit"]`, and `status["expires_turn"]`. It acts at team-phase start through
  `EnemyAI` (generic brain: shoot the best visible hostile). Decoys have `status["decoy"]`, which
  `EnemyAI._target_score` favours.
- They are not squad: `Deployables.soldiers(s)` is the living squad without them (defeat uses it;
  objectives and run results should too), `Infection.add` ignores them, and run outcomes only
  carry units with a `sid`.
- Events: `deployed` (`unit`, `kind`, `cell`, `owner`), `deployable_end` (`unit`, then `died`).
  The view builds a unit view lazily; models fall back to the trooper model until a turret model exists.

## Enemies (roster, elites, bosses)

Folder `enemies/`, owned by the enemy roster workstream. Design doc section "Enemies".

| Class | What it does |
|---|---|
| `EnemyRoster` | Threat costs, act pools, elites and affixes, enemy spec strings, `make(spec)` |
| `FightBuilder` | `build(spec) -> {enemies, encounter}` and `preview(spec)` for the run map |
| `Encounter` | Fight-level rules called by `Rules`: spawners, waves, spore zones (as `Hazards` spore tiles), telegraphs, affixes, bosses |
| `EnemyAbilities` | Enemy-only abilities, routed by `Rules` instead of `Combat` |
| `EnemyBehaviours` | AI behaviours Cover shooter, Seek cluster, Ambush, Support, the Brute charge and the bosses (`EnemyAI` dispatches to it) |
| `EnemyTerrain` | Elevation reads for enemies (`Grid.level`), fall damage (2 per level; knockbacks stop at a step up), collapsing raised tiles via `Elevation.set_level` |
| `EnemyIntent` | Pure "what will it do" reads for the view's intent labels and danger tiles |

View side: `view/enemy_beats.gd` (beats and log lines for the events above, placeholder scale per
kind) and `view/intent_overlay.gd` (`MissionView.intents`, refreshed when the event queue drains).

- **Spec strings** (MatchConfig `enemies`): `"runner"`; `"brute!armoured,hasted"` = elite (double HP)
  with affixes; `"runner+hasted"` = regular that bought an affix. `Rules.new_mission_on_grid` builds
  them with `EnemyRoster.make`.
- **Rules hooks** (all in `Encounter`): `validate` (pinned soldiers can't act, hidden units can't be
  targeted), `after_action`, `on_team_phase_start`, `on_enemy_phase_start` (telegraphs land, Source pulse, spawners, waves), `on_unit_turn_start/end` (hasted, regenerating, Bloater
  swell, Brute wind-up), `on_enemy_phase_end` (frenzy expiry, Source spore rings, wave
  warnings), and in `Rules.deal_damage`: `modify_damage` (tethers, armour, Carrier twist, bosses
  always reach phase 2), `on_damaged` (virulent, Outbreak infection bonus, pin release, boss phases),
  `on_died` (splitting, death burst, boss defeat, tethers). `EnemyRoster.infects(source)` gates
  `Infection.on_damaged` (Fallen bullets don't infect).
- **`GameState.encounter`** is serialized with the state. Keys: `act`, `node`, `objective`,
  `outbreak`, `stage`, `boss`, `hive`, `purge_nests`, `ambush`, `boss_health_mult`, `infect_bonus`,
  `start_infection`, `spore_patches`, `waves` ([{turn, every, kinds}]), `incoming`, `telegraphs` ([{kind, cells, turn, damage, source, smash, unit}]),
  `lapse_double`, `over`.
- **Statuses** (enemy units unless noted): `elite`, `affixes`, `armour`, `hidden`, `boss`,
  `boss_phase`, `spawner` ({kinds, every, next, i}), `tether` (kind whose living units make it
  immune), `swelling`, `charge_dir`, `pinning`, soldier `pinned_by`, `frenzy`/`frenzy_mob`/`frenzy_aim`,
  `pull_turn`, `leap_cell` (Leaper landing), `sighted` (Sharpshooter target id), `burrowed` +
  `emerge_cell` (Burrower), `flying` (Drifter; Elevation reads it as height 1). **`burned_turn`** (int turn) is read, not written: set it from a flame ability to stop
  Regenerating that turn (GearFx `burning` also stops it).
- **Static units** (`UnitData.ENEMIES[kind].static`: Hive node, egg sac, spore nest, Source root)
  never act; `Objectives` can count living `spore_nest` units for Purge.
- **Outbreak stages** (`FightBuilder.stage`): Spreading +1 enemy (2 budget) and a spore patch;
  Rampant +1 more, a wave on turn 4, +5 Infection on infected hits; Critical a skirmish elite (50%),
  2 patches, 2 elite affixes in nests; Collapse +10 starting Infection and waves every 3 turns.
  Budget past the 5-enemy cap buys affixes or an earlier wave. Objective pressure: Hold gets a wave
  every turn from 2 sides, Extract 2 enemies every 2 turns, Purge 3 spore nests on `markers.nest`.
- **Vertical enemies**: Leaper (marks a 3x3 landing a turn ahead, jumps over terrain and height,
  overwatch can't catch it, knocks soldiers off ledges), Drifter (flies over everything, drops from
  above ignoring cover), Sharpshooter (claims high ground, telegraphed laser lock that fires next
  turn unless line of sight breaks or it is suppressed; height lowers the target's cover as for any shot), Burrower (act 3, hidden underground, erupts
  next to the soldier on the highest ground, destroys cover and collapses raised tiles). Each act
  weights its `EnemyRoster.SIGNATURE` enemies double.
- **Map markers used** (`grid.markers`, optional): `hive`, `boss`, `nest`, `reinforce`.
- Dev aid: `-- --fight=<node>,<act>,<outbreak>` plays one built fight on the test map.

## Story (story/, ui/story/)

World, Echoes and endings from the design doc's "World and story". Rules live in `story/`, presentation in
`ui/story/`; all text is data in `StoryData`.

- **`run.story`** (owned by `Story`, saved and synced as-is): `wave`, `runs`, `last_result`, `last_ending`,
  `last_wave`, `source_reached`, `known` (intel ids the host's profile had), `lore` (found this run),
  `echoes` (`[{key, kind, name, wave, met, laid}]`), `open`/`votes`/`ending`/`carrier` (the ending vote).
- **Profile.** `StoryProfile` keeps sections `story` and `echoes` in the profile file (`Profile.path`).
  `Profile.meta()["story"]` is its `snapshot()`, so `Story.init_run` (called by `RunRules.new_run`, host side)
  reads only run data. `Profile.record_run` calls `StoryProfile.record_run(run)`: idempotent, safe on every peer.
  When a run ends, its Turned soldiers (`run.echoes`) join the Echo pool (max 12, oldest drop off).
- **Echoes.** Up to 2 per run, oldest first. `MatchConfig.for_fight` asks `Story.fight_echo(run, st)`: the
  first non-boss fight after 1 win (then after 4) gets one, replacing the last enemy. `MatchConfig.build`
  calls `Story.setup_echo(state, echo)`: a soldier unit of the old class on the enemy team with
  `status.turned`, `status.echo` (key), double health, named "Echo <surname>". `RunRules.fight_outcome`
  lists dead ones in `echoes_down`; `Story.on_fight_end` pays 15 Supplies ("dog tags") and recovers intel,
  and the profile drops a laid Echo from the pool. `UnitView.soldier_body` builds it from the soldier model.
- **Intel logs.** `StoryData.LORE`, recovered in order (deterministic, no rng): one per boss win, one per
  Echo laid to rest. The last (`contact`) unlocks Carry it. Main menu "Archive" reads them.
- **Ending vote.** The act 3 boss win calls `Story.begin_ending`; the run waits in REWARD
  (`Story.has_pending`) and RunView shows `Story.screen()`. Action `story_ending` (`ending`: `burn` /
  `sample` / `carry`), majority with the host breaking ties. Burn is always open; Sample needs a Halden-Voss
  event this run (`StoryData.HV_EVENTS`); Carry needs the `contact` log and a living Critical soldier, who
  becomes `run.story.carrier`. Then the `victory` step ends the run.
- **Presentation** (`ui/story/story_director.gd`, a CanvasLayer in `App`, local only): the briefing at run
  start, act 2 and 3 transitions, boss intros at `fight_start`, the ending scene, radio barks on run and fight
  events (act 2 garbled, act 3 a soldier speaks) and Source whispers when a local player's soldier reaches
  Mutating or Critical. Scenes are `story_scene.gd` (letterbox, title card, captions; Space next, Esc skip)
  over `story_stage.gd` (a 3D set from primitives plus the game's models, own SubViewport world).
- Dev aid: `godot -s tools/shot_story.gd -- out.png <intro|act2|act3|brood_mother|colonel_hale|the_source|burn|sample|carry|ending_vote> [secs]`
  (under xvfb, `--rendering-driver opengl3`) and `tools/shot_story_fight.gd` (an Echo, radio and a whisper in a fight).
