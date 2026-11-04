extends "res://tools/render_map_samples.gd"
## Headless renders for the project website: generated maps for every studio preset,
## block references for every terrain and both objects sets. Raw PNGs and a manifest
## go to test_output/site_gallery; tools/build_site.py turns them into docs/gallery.

const OUT := "res://test_output/site_gallery"
const SEEDS := [20261017, 7, 2026]
const SIZE := 48
## Same table as MapStudioPanel._build_presets: name, subtitle, generator, grid, projection.
const PRESETS := [
	["coast", "海岸群岛", "沙滩 · 森林 · 浅海", 0, 0, 1],
	["highland", "高原大陆", "岩层 · 高差 · 雪地", 0, 0, 1],
	["dungeon", "石砖地牢", "房间 · 回路 · 走廊", 1, 0, 0],
	["cave", "天然洞穴", "洞室 · 随机通道", 2, 0, 0],
	["hex_islands", "六角群岛", "六角柱 · 等角地块", 0, 1, 1],
	["hex_dungeon", "六角地牢", "六边形房间 · 走廊", 1, 1, 1],
]
const BLOCK_SEEDS := [42, 1337, 90210]

func run() -> void:
	if DisplayServer.get_name() != "headless":
		quit(1)
		return
	for folder in ["maps", "blocks", "objects"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.path_join(folder)))
	var manifest := {"maps": [], "terrains": [], "objects": []}
	for preset: Array in PRESETS:
		for seed_value: int in SEEDS:
			for style in 2:
				var data := preset_map(preset, seed_value, style)
				var name := "%s_%d_%s" % [preset[0], seed_value, ["pixel", "painted"][style]]
				if data == null:
					print("skipped ", name, ": generation failed")
					continue
				render(data).save_png(OUT.path_join("maps/%s.png" % name))
				manifest.maps.append({"file": name, "preset": preset[1], "subtitle": preset[2], "seed": seed_value, "style": style, "grid": ["方形", "六角"][preset[4]], "projection": ["俯视", "等角"][preset[5]], "size": SIZE, "cells": data.terrain.size()})
				print("map ", name)
	var nature := [load("res://addons/jeff_map_studio/examples/libraries/nature_pixel.tres"), load("res://addons/jeff_map_studio/examples/libraries/nature_soft.tres")]
	var dungeon := [load("res://addons/jeff_map_studio/examples/libraries/dungeon_pixel.tres"), load("res://addons/jeff_map_studio/examples/libraries/dungeon_soft.tres")]
	for terrain in 8:
		var entry := {"id": terrain, "name": MapData.TERRAIN_NAMES[terrain], "files": []}
		for style in 2:
			var library: TileLibrary = (dungeon if terrain >= MapData.Terrain.WALL else nature)[style]
			var recipe := (library.recipes[terrain] as TextureRecipe).duplicate(true) as TextureRecipe
			recipe.style = style
			recipe.resolution = 128
			for shape in 3:
				var file := "%d_%s_%s" % [terrain, ["pixel", "painted"][style], ["square", "hex_pointy", "hex_flat"][shape]]
				MapBlockSurface.thumbnail(recipe, shape, 48, 128).save_png(OUT.path_join("blocks/%s.png" % file))
				entry.files.append(file)
			for seed_value: int in BLOCK_SEEDS:
				var seeded := recipe.duplicate(true) as TextureRecipe
				seeded.seed_value = seed_value
				var file := "%d_%s_seed%d" % [terrain, ["pixel", "painted"][style], seed_value]
				MapBlockSurface.thumbnail(seeded, 0, 48, 128).save_png(OUT.path_join("blocks/%s.png" % file))
				entry.files.append(file)
		manifest.terrains.append(entry)
		print("terrain ", terrain)
	for id in range(1, MapData.DECORATION_NAMES.size()):
		for style in 2:
			var file := "%d_%s" % [id, ["pixel", "painted"][style]]
			MapLandmarkArt.sprite(style, id, 128).save_png(OUT.path_join("objects/%s.png" % file))
		manifest.objects.append({"id": id, "name": MapData.DECORATION_NAMES[id]})
	var json := FileAccess.open(OUT.path_join("manifest.json"), FileAccess.WRITE)
	json.store_string(JSON.stringify(manifest, "\t"))
	json.close()
	print("SITE GALLERY: ", manifest.maps.size(), " maps, ", manifest.terrains.size(), " terrains, ", manifest.objects.size(), " objects")
	quit()

## Mirrors MapStudioPanel._preset so a visitor can reproduce any picture in the studio.
func preset_map(preset: Array, seed_value: int, style: int) -> MapData:
	var p := MapProfile.new()
	p.generator = preset[3]
	p.grid = preset[4]
	p.projection = preset[5]
	p.style = style
	p.base_thickness = 16
	p.island = preset[1] != "高原大陆"
	if p.generator != MapProfile.Generator.NATURE:
		p.decoration_density = 0.02
		p.max_height = 2
	p.width = SIZE
	p.height = SIZE
	p.seed_value = seed_value
	var data := MapGenerator.generate(p, null, MapGenerationJob.new())
	if data == null:
		return null
	data.tile_library = load("res://addons/jeff_map_studio/examples/libraries/%s_%s.tres" % ["nature" if p.generator == 0 else "dungeon", "pixel" if style == 0 else "soft"])
	return data

func render(data: MapData) -> Image:
	var images := MapAtlasBuilder.prepare_images(data.profile, data.tile_library, MapGenerationJob.new())
	var atlas := images.duplicate()
	atlas["tileset"] = MapAtlasBuilder.create_tileset(images, data.profile)
	var renderer := MapRenderer.new()
	root.add_child(renderer)
	renderer.setup(data, atlas, data.tile_library)
	for i in data.terrain.size():
		renderer.update_cell(data.cell_at(i))
	var commands := draw_commands(renderer, images)
	var image := composite(commands, command_bounds(commands).grow(8))
	renderer.free()
	return image
