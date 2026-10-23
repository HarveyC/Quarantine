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
4. `Rules.check_end` after every action: no enemies = VICTORY; no player-controlled soldiers = DEFEAT.

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
| `shot` | `unit`, `target`, `hit`, `graze`, `crit`, `damage`, `chance`, `reaction` |
| `damage` | `unit`, `amount`, `hp`, `source` |
| `died` | `unit` |
| `overwatch` | `unit` |
| `hunker` | `unit` |
| `ability` | `unit`, `ability`, plus `target`/`cell` and ability-specific fields |
| `infection` | `unit`, `value`, `tier` |
| `mutation` | `unit`, `mutation`, plus target fields |
| `lapse` / `recover` / `turned` | `unit` |
| `mission_end` | `result` (`Types.Result`) |

New event types are fine; add them to this table.

## Cross-module contracts

- **Lapsed soldier**: `unit.status["lapsed"] = true` and `unit.ai_controlled = true`. `Unit.is_enemy_of`
  treats a lapsed unit as hostile to everyone. `EnemyAI.take_turn` must handle it (it is called for
  lapsed soldiers at the start of the team phase).
- **Turned soldier**: Infection sets `unit.team = Types.Team.ENEMY`, `ai_controlled = true`. It then acts in the enemy phase.
- **Infection from damage**: `Rules.deal_damage` calls `Infection.on_damaged(s, target, source, amount)`.
- **Hit chance**: `Combat.hit_chance(s, attacker, target, from)` returns
  `{hit, graze, crit, cover, flanked, breakdown}`; the HUD and AI both use it, `from` lets them preview other cells.
- **Abilities / mutations for the HUD**: `Combat.available_abilities` and `Infection.available_mutations`
  return `{id, name, targeting: "none"|"unit"|"cell", ready, ...}`.
