@tool
class_name MapTileRule
extends Resource

enum Role { TOP, SIDE, DECORATION }
@export var terrain: int = 2
@export var role: Role = Role.TOP
## -1 matches every adjacency; otherwise bits follow MapGrid.directions().
@export var neighbor_mask: int = -1
@export var corner_mask: int = -1
@export var source_id: int = 0
@export var atlas_coords: Vector2i = Vector2i.ZERO
@export var alternative_id: int = 0
## Decoration IDs: -1 any, 1 tree, 2 rock, 3 crate, 4 mushrooms, 5 palm, 6 lighthouse.
@export var decoration_id: int = -1
@export_range(0.01, 100.0, 0.01) var weight: float = 1.0

func sort_key() -> String:
	return "%08d:%08d:%08d:%08d" % [source_id, atlas_coords.y, atlas_coords.x, alternative_id]
