#!/usr/bin/env python3
"""Turn the headless website renders into web assets under docs/gallery/.

1. godot --headless --path . --script tools/render_site_gallery.gd   (raw PNGs + manifest)
2. python3 tools/build_site.py                                       (this script)

Pixel images are reduced to their logical resolution (one pixel per art pixel, lossless
palette PNG) and enlarged by the page with image-rendering: pixelated. Painted images
become WebP. Needs Pillow.
"""
import json
import shutil
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / 'test_output/site_gallery'
OUT = ROOT / 'docs/gallery'
# Pixel art is drawn with 2 px blocks at tile 64 (maps) and 4 px blocks at tile 128 (blocks, objects).
MAP_STEP = 2
BLOCK_STEP = 4


def trimmed(image):
    box = image.getchannel('A').getbbox()
    return image.crop(box) if box else image


def save_pixel(image, path, step):
    image = trimmed(image)
    w, h = image.width // step * step, image.height // step * step
    small = image.crop((0, 0, w, h)).resize((w // step, h // step), Image.NEAREST)
    colors = small.getcolors(maxcolors=255)
    if colors is not None:
        # Palette PNG with a transparent index keeps pixel art lossless and tiny.
        small = small.quantize(colors=len(colors) + 1, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    small.save(path.with_suffix('.png'), optimize=True)
    return path.with_suffix('.png').name, small.size


def save_painted(image, path, scale, thumb=None):
    image = trimmed(image)
    size = (round(image.width * scale), round(image.height * scale))
    image = image.resize(size, Image.LANCZOS)
    image.save(path.with_suffix('.webp'), quality=84, method=6)
    result = {'file': path.with_suffix('.webp').name, 'size': list(image.size)}
    if thumb:
        small = image.resize((thumb, round(image.height * thumb / image.width)), Image.LANCZOS)
        thumb_path = path.with_name(path.stem + '_thumb.webp')
        small.save(thumb_path, quality=80, method=6)
        result['thumb'] = thumb_path.name
    return result


def main():
    manifest = json.loads((RAW / 'manifest.json').read_text())
    if OUT.exists():
        shutil.rmtree(OUT)
    for folder in ['maps', 'blocks', 'objects']:
        (OUT / folder).mkdir(parents=True)
    for item in manifest['maps']:
        image = Image.open(RAW / 'maps' / f"{item['file']}.png").convert('RGBA')
        target = OUT / 'maps' / item['file']
        if item['style'] == 0:
            name, size = save_pixel(image, target, MAP_STEP)
            item.update(file=name, size=list(size), thumb=name, pixel=True)
        else:
            item.update(save_painted(image, target, 0.5, thumb=640), pixel=False)
    for terrain in manifest['terrains']:
        files = {}
        for stem in terrain['files']:
            image = Image.open(RAW / 'blocks' / f'{stem}.png').convert('RGBA')
            if '_pixel_' in stem:
                files[stem] = save_pixel(image, OUT / 'blocks' / stem, BLOCK_STEP)[0]
            else:
                trimmed(image).save(OUT / 'blocks' / f'{stem}.png', optimize=True)
                files[stem] = f'{stem}.png'
        terrain['files'] = files
    for item in manifest['objects']:
        for style in ['pixel', 'painted']:
            stem = f"{item['id']}_{style}"
            image = Image.open(RAW / 'objects' / f'{stem}.png').convert('RGBA')
            if style == 'pixel':
                item[style] = save_pixel(image, OUT / 'objects' / stem, BLOCK_STEP)[0]
            else:
                trimmed(image).save(OUT / 'objects' / f'{stem}.png', optimize=True)
                item[style] = f'{stem}.png'
    (OUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=1))
    total = sum(p.stat().st_size for p in OUT.rglob('*') if p.is_file())
    print(f"{len(manifest['maps'])} maps, {len(manifest['terrains'])} terrains, {len(manifest['objects'])} objects, {total / 1048576:.1f} MB")


if __name__ == '__main__':
    main()
