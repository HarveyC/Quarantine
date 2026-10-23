class_name Types
extends RefCounted
## Shared enums and constants. Owned by core; other modules read, never redefine.

enum Team { PLAYER, ENEMY }
enum Cover { NONE, HALF, FULL }
enum Tile { FLOOR, WALL, LOW }
enum Phase { TEAM, ENEMY, ENDED }
enum Result { NONE, VICTORY, DEFEAT }

const ACTIONS_PER_TURN := 2

# Action type ids. An action is a Dictionary: {"type": <id>, "unit": <unit id>, ...}
const MOVE := "move"            # + "to": Vector2i
const SHOOT := "shoot"          # + "target": unit id
const OVERWATCH := "overwatch"
const HUNKER := "hunker"
const ABILITY := "ability"      # + "ability": String, optional "target" (unit id) / "cell" (Vector2i)
const MUTATION := "mutation"    # + "mutation": String, optional "target" / "cell"
