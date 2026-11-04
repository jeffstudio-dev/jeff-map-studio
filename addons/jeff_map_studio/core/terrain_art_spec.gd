@tool
class_name TerrainArtSpec
extends Resource
## Appearance rules for one terrain material in one style: what the concept sheet
## supplies, which values stay fixed, and the ranges the seed draws from.
## Default values reproduce the built-in pixel grass and moss cliffs (variant 0 exactly).

@export var id: String = "grass"
@export_enum("像素", "手绘") var style: int = MapProfile.Style.PIXEL
@export_enum("草地", "沙土", "岩石", "水面", "石砖") var material: int = TextureRecipe.MaterialKind.GRASS
## Raise when the drawing rules change; it invalidates cached atlases.
@export var version: int = 1
@export var concept: MapArtConcept

@export_group("Top field")
## Patch period = clamp(round(scale × factor), minimum, maximum) cells per tile.
@export_range(0.1, 4.0, 0.05) var period_factor: float = 0.75
@export_range(1, 16, 1) var period_min: int = 2
@export_range(1, 32, 1) var period_max: int = 12
@export_range(0.0, 1.0, 0.01) var coarse_weight: float = 0.65
## Field value below which the darker tone appears (scaled by grain).
@export_range(0.0, 1.0, 0.01) var dark_below: float = 0.3
## Field value above which the lighter tone appears.
@export_range(0.0, 1.0, 0.01) var light_above: float = 0.62

@export_group("Variants")
## Interior variation fades in over this share of the tile from the outline.
@export_range(0.05, 1.0, 0.01) var variant_window: float = 0.3
## Blocks this many pixel steps from the outline never vary, so variants tile freely.
@export_range(0.0, 4.0, 0.5) var variant_margin_steps: float = 1.0
@export_range(0.0, 1.0, 0.01) var variant_strength: float = 0.45
## Added to the field inside each variant (index = variant); lighter or darker moods.
@export var variant_tone_bias: PackedFloat32Array = PackedFloat32Array()
## Map cells per region when choosing variants; 0 picks each cell independently.
@export_range(0.0, 32.0, 0.5) var variant_region_cells: float = 0.0
@export_range(0.5, 4.0, 0.1) var variant_region_contrast: float = 1.8
## Random spread around the region's variant, in variant steps.
@export_range(0.0, 4.0, 0.1) var variant_mix: float = 1.0
## Variant ids along the region axis (e.g. flowery → plain → dense → clover), so
## neighbouring regions blend through related moods. Empty keeps 0, 1, 2, 3.
@export var variant_order: PackedInt32Array = PackedInt32Array()

@export_group("Motifs")
@export var motif_layers: Array[ArtMotifLayer] = []

@export_group("Edges")
@export_range(0, 5, 1) var rim_front_tone: int = 4
@export_range(0, 5, 1) var rim_rear_tone: int = 2

@export_group("Cliff (moss)")
@export_range(0, 8, 1) var lip_rows: int = 2
## Slow wave along the edge above which the lip grows one row longer.
@export_range(0.0, 1.0, 0.01) var lip_wave_above: float = 0.55
@export_range(0.0, 1.0, 0.01) var lip_strand_chance: float = 0.18
@export_range(2, 16, 1) var band_period: int = 5
@export var stone_cell: Vector2i = Vector2i(5, 3)
@export_range(0.0, 1.0, 0.01) var stone_chance: float = 0.42
@export var stone_color: Color = Color("8a86a0")
@export var stone_light: Color = Color("cfc8d6")
@export_range(0.0, 1.0, 0.01) var stone_tint: float = 0.2
@export_range(0.0, 1.0, 0.01) var root_chance: float = 0.12
@export_range(0, 16, 1) var root_rows: int = 5
@export_range(0.0, 1.0, 0.01) var speck_chance: float = 0.05

func period(scale: float) -> int:
	return clampi(roundi(scale * period_factor), period_min, period_max)

func tone_bias(variant: int) -> float:
	return variant_tone_bias[variant] if variant < variant_tone_bias.size() else 0.0

func validate() -> String:
	if period_min > period_max:
		return "%s：色块周期下限不能大于上限。" % id
	if dark_below >= light_above:
		return "%s：暗部阈值必须小于亮部阈值。" % id
	if not variant_order.is_empty():
		var sorted := Array(variant_order)
		sorted.sort()
		if sorted != range(variant_order.size()):
			return "%s：变体顺序必须是 0…n-1 的排列。" % id
	if stone_cell.x < 3 or stone_cell.y < 3:
		return "%s：石块网格至少 3×3。" % id
	for layer in motif_layers:
		if layer == null:
			return "%s：图案层为空。" % id
		var problem := layer.validate()
		if not problem.is_empty():
			return problem
		if concept != null and not concept.motifs.has(layer.group):
			return "%s：概念图中没有图案组 %s。" % [id, layer.group]
	return ""

## Changes whenever a drawing-relevant value changes, including the concept data.
func fingerprint() -> String:
	var text := ""
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE and property.name not in ["concept", "motif_layers", "script", "resource_path", "resource_name", "resource_local_to_scene"]:
			text += "%s=%s;" % [property.name, var_to_str(get(property.name))]
	for layer in motif_layers:
		if layer != null:
			text += "%s,%d,%s,%s,%s,%s;" % [layer.group, layer.placement, layer.per_tile, layer.scaled_by_grain, layer.requires_illustrated, layer.variant_scales]
	if concept != null:
		text += concept.source_hash
	return text.sha256_text().substr(0, 16)
