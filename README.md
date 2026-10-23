# Quarantine

Co-op tactics roguelike: a squad of Carriers fighting an infection that is also their power source.
First playable MVP: one mission, four soldiers, local hot-seat co-op.

- Engine: Godot 4.4 (GDScript)
- Run the game: open the folder in Godot 4.4 and press F5
- Run tests: `./tests/run.sh` (set `GODOT=/path/to/godot` if it is not on your PATH)
- Code layout and module contracts: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Playing the MVP

Hot-seat co-op: Player 1 has the Trooper and Marksman, Player 2 the Medic and Breacher. Both act in any
order during the squad phase; the enemy phase runs when both press READY.

| Input | Does |
|---|---|
| Left-click soldier / Tab | Select (Tab cycles soldiers with actions left) |
| Left-click highlighted cell | Move (hover shows path and cover: blue full, yellow half) |
| 1 Shoot, 2 Overwatch, 3 Hunker, 4+ abilities and mutations | Pick an action |
| Tab / Enter (in Shoot) | Next target / fire |
| Esc or right-click | Cancel, then deselect |
| WASD, Q/E, wheel, F | Pan, rotate, zoom, focus selected |

Dev flags: `godot --headless -- --autoplay` plays a mission headlessly;
`xvfb-run godot --rendering-driver opengl3 -- --screenshot=out.png [--screenshot-action=shoot]` saves a frame.
