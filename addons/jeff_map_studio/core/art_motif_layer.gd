@tool
class_name ArtMotifLayer
extends Resource
## One group of concept motifs stamped on a terrain top.

enum Placement { SHARED, INTERIOR }
## Motif group name in the concept sheet (slices "motif/<group>/<nn>").
@export var group: String = ""
## Shared motifs repeat on the tile lattice and may cross edges; interior motifs stay
## inside one tile and may differ per variant.
@export_enum("跨格共享", "仅格内") var placement: int = Placement.SHARED
@export_range(0.0, 64.0, 0.1) var per_tile: float = 0.0
@export var scaled_by_grain: bool = true
@export var requires_illustrated: bool = true
## Multiplier per top variant (interior layers only); missing entries count as 1.
@export var variant_scales: PackedFloat32Array = PackedFloat32Array()

func count(density: float, variant: int) -> int:
	var scale := variant_scales[variant] if placement == Placement.INTERIOR and variant < variant_scales.size() else 1.0
	return roundi(per_tile * (density if scaled_by_grain else 1.0) * scale)

func validate() -> String:
	if group.is_empty():
		return "图案层缺少分组名。"
	if not is_finite(per_tile) or per_tile < 0.0:
		return "图案层 %s 的每格数量必须 ≥ 0。" % group
	for value in variant_scales:
		if not is_finite(value) or value < 0.0:
			return "图案层 %s 的变体倍率必须 ≥ 0。" % group
	return ""
