@tool
class_name MapArtConcept
extends Resource
## Data imported from an Aseprite concept sheet by tools/import_concepts.gd.
## The sheet's reference layer is for review only and is not imported.

@export var source: String = ""
## SHA-256 of the exported palette and motif data; part of the atlas cache key.
@export var source_hash: String = ""
## Ramp name -> PackedColorArray, dark to light.
@export var ramps: Dictionary = {}
## Single-letter key -> Color for fixed accents (flowers, shells).
@export var accents: Dictionary = {}
## Accent key -> slice name, for people reading the resource.
@export var accent_names: Dictionary = {}
## Motif group -> Array of PackedStringArray. Digits index the group's ramp.
@export var motifs: Dictionary = {}
## Motif group -> ramp name its colours were drawn from.
@export var motif_ramps: Dictionary = {}
