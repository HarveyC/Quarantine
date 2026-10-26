# Balance sim

Plays thousands of fights headless with the real rules: `squad_bot.gd` plays the squad (moves to
cover with a shot, shoots the best target, uses Stim/Breach/Tag/Suppress/Incinerate/Siphon when they
clearly help, overwatches otherwise) and `EnemyAI` plays the enemies. Nothing here ships in the game.

```
GODOT=path/to/godot python3 tools/balance/run_sims.py OUT_DIR            # ~20-30 min on 4 cores
GODOT=path/to/godot python3 tools/balance/run_sims.py OUT_DIR --only=boss # one batch type
python3 tools/balance/report.py OUT_DIR                                    # Markdown tables
```

One fight by hand: `godot --headless -s tools/balance/balance_sim.gd -- squad=trooper,medic act=2 node=boss n=5`
(also `enemies=brute,brute` to skip FightBuilder, `rank=`, `outbreak=`, `seed=`, and `order=bloom_cache`
to deploy every soldier with one of the run-start deployment orders from gear/deploy_orders.gd).

Batches: real FightBuilder skirmishes and bosses for every act, squad size 1-4 and starter-class mix;
duels (one soldier of each class vs two of each regular enemy); and threat (the starter squad vs
three of one enemy kind). Soldiers get the rank they'd typically have in that act (1/3/5) and random
class perks, but no gear, so later acts read a little harder than a real run.

What to look for: "squad HP lost" per fight should be about the same at every squad size (HP carries
over between fights, so this is the run-level difficulty), skirmish wins near 95%+, bosses 85-95%.
The bot is a decent but not expert player: it doesn't dodge telegraphs on purpose or play objectives
(only skirmish and boss fights are simulated).

## Build quality

`build=none|scattered|lane|full` (see `build_quality.gd`) gives every soldier gear, perks, mutations and
Grafts for the act: the same number of pieces at every level, differing in how well they overlap on
tags (`none` has no pieces, `scattered` draws any tag, `lane` the class's two lane tags, `full` stacks the
first lane tag with Mk II gear and the best rarity). `node=act` plays a whole act as a run does: three
skirmishes then the boss, HP and Infection carried, the 35% heal after each won fight, the fallen stay down.

```
GODOT=path/to/godot python3 tools/balance/run_sims.py OUT_DIR --only=build,buildboss   # ~40 min on 4 cores
python3 tools/balance/build_report.py OUT_DIR                  # against the target curve
python3 tools/balance/build_report.py BASE_DIR VARIANT_DIR     # base to variant, for a balance change
```

`BUILD_N`, `BUILD_BOSS_N` and `BUILD_ACTS` (e.g. `2,3`) shrink or widen the batch. To test a rules change,
make it in a worktree, rerun the batch into a second directory and compare. The bot never fires gadgets or
active mutations, so builds that live on those read lower than they play. Capstones do not exist yet:
`capstones()` counts tags at 6 pieces, and the `full` level already stacks past that.
