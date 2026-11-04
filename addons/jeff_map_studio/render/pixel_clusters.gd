@tool
class_name MapPixelClusters
extends Resource
## Small surface clusters imported from assets/pixel/clusters.aseprite.
## Each group maps to an array of PackedStringArray rows; digits are ramp indices.
@export var groups: Dictionary = {}
