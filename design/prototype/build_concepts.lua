-- Builds the two concept sheets used by the design examples (Aseprite batch mode):
--   aseprite -b --script-param root=<project>/design --script design/prototype/build_concepts.lua
-- Layout convention for every concept sheet (one frame):
--   reference : target look for review and regression comparison; code never samples it
--   palette   : named slices "ramp/<name>" (swatches dark -> light) and "accent/<name>"
--   motifs    : pixel clusters, drawn in the real default colours (slices "motif/<group>/<nn>")
--   brushes   : painted style only; white strokes whose alpha is the brush ("brush/<name>")
local root = app.params.root
assert(root and #root > 0, "missing --script-param root=<design dir>")
local source = app.fs.joinPath(root, "concepts", "source")

local function hex(value, alpha)
  return Color{ r = tonumber(value:sub(1, 2), 16), g = tonumber(value:sub(3, 4), 16), b = tonumber(value:sub(5, 6), 16), a = alpha or 255 }
end

local function layer(sprite, name)
  local result = sprite:newLayer()
  result.name = name
  local cel = sprite:newCel(result, 1, Image(sprite.width, sprite.height, ColorMode.RGB), Point(0, 0))
  return result, cel.image
end

local function slice(sprite, name, x, y, w, h)
  local s = sprite:newSlice(Rectangle(x, y, w, h))
  s.name = name
end

local function swatches(sprite, image, name, colors, x, y, size)
  for i, value in ipairs(colors) do
    for dy = 0, size - 1 do
      for dx = 0, size - 1 do
        image:drawPixel(x + (i - 1) * size + dx, y + dy, hex(value))
      end
    end
  end
  slice(sprite, name, x, y, #colors * size, size)
end

local function paste(image, path, x, y)
  local picture = Image{ fromFile = path }
  image:drawImage(picture, Point(x, y))
  return picture
end

-- Pixel concept --------------------------------------------------------------
local function pixel_concept()
  local file = io.open(app.fs.joinPath(source, "pixel_ramps.json"), "r")
  local text = file:read("a")
  file:close()
  local ramps = {}
  for name, body in text:gmatch('"(%w+)":%s*%[(.-)%]') do
    ramps[name] = {}
    for value in body:gmatch('"(%x+)"') do table.insert(ramps[name], value) end
  end
  local sprite = Sprite(222, 104, ColorMode.RGB)
  sprite.layers[1].name = "reference"
  local reference = sprite.cels[1].image
  paste(reference, app.fs.joinPath(source, "pixel_reference_block.png"), 2, 2)
  paste(reference, app.fs.joinPath(source, "pixel_reference_patch.png"), 54, 2)
  local _, palette = layer(sprite, "palette")
  swatches(sprite, palette, "ramp/top", ramps.top, 2, 34, 5)
  swatches(sprite, palette, "ramp/soil", ramps.soil, 2, 40, 5)
  swatches(sprite, palette, "ramp/stone", ramps.stone, 2, 46, 5)
  local accents = { white = "fff4d6", yellow = "f6d65a", lilac = "c8b6f0", shell = "f7d9cf" }
  local ax = 2
  for _, key in ipairs({ "white", "yellow", "lilac", "shell" }) do
    swatches(sprite, palette, "accent/" .. key, { accents[key] }, ax, 52, 5)
    ax = ax + 6
  end
  -- Motifs in real colours: digits index the material ramp named by the group.
  local _, motifs = layer(sprite, "motifs")
  local groups = {
    { "tuft", "top", { { "4.4", "2.2" }, { "4.4.4", "2.2.2" }, { ".4.", "424", "2.2" }, { "4..", "2.4", "..2" }, { "..4", "4.2", "2.." }, { "5.4", "424", "2.2" } } },
    { "flower", "top", { { "a", "2" }, { "b", "2" }, { "a.a", "2.2" }, { "d", "2" } } },
    { "cliff_stone", "stone", { { "443", "221" }, { ".44.", "4432", ".21." } } },
    { "root", "soil", { { "4", "4", "3" }, { "4.", ".4", ".3" } } },
    { "drip", "top", { { "33333333", "22222222", "1.21.2.1", "..1....." } } },
  }
  local accent_keys = { a = "white", b = "yellow", d = "lilac", l = "shell" }
  local x, y = 2, 62
  for _, group in ipairs(groups) do
    for index, rows in ipairs(group[3]) do
      local w, h = #rows[1], #rows
      if x + w > 50 then x, y = 2, y + 7 end
      for row, line in ipairs(rows) do
        for column = 1, #line do
          local key = line:sub(column, column)
          local color = nil
          if accent_keys[key] then color = hex(accents[accent_keys[key]])
          elseif key ~= "." then color = hex(ramps[group[2]][tonumber(key) + 1]) end
          if color then motifs:drawPixel(x + column - 1, y + row - 1, color) end
        end
      end
      slice(sprite, string.format("motif/%s/%02d", group[1], index), x, y, w, h)
      x = x + w + 2
    end
  end
  sprite:saveAs(app.fs.joinPath(root, "concepts", "pixel_grass.aseprite"))
  sprite:close()
end

-- Painted concept ------------------------------------------------------------
local function hash(x, y, seed)
  local h = (x * 374761393 + y * 668265263 + seed * 144269) % 2147483647
  h = ((h ~ (h >> 13)) * 1274126177) % 2147483647
  return (h ~ (h >> 16)) % 1000 / 1000
end

local function brush(sprite, image, name, x0, y0, w, h, alpha_at)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local a = alpha_at(x + 0.5, y + 0.5, w, h)
      if a > 0.02 then
        image:drawPixel(x0 + x, y0 + y, Color{ r = 255, g = 255, b = 255, a = math.floor(math.min(1, a) * 255 + 0.5) })
      end
    end
  end
  slice(sprite, "brush/" .. name, x0, y0, w, h)
end

local function soft(distance, width)
  return math.max(0, math.min(1, distance / width))
end

local function painted_concept()
  local sprite = Sprite(400, 200, ColorMode.RGB)
  sprite.layers[1].name = "reference"
  paste(sprite.cels[1].image, app.fs.joinPath(source, "painted_reference_block.png"), 6, 6)
  local _, palette = layer(sprite, "palette")
  swatches(sprite, palette, "ramp/top", { "3d6b48", "5a8f52", "70a862", "87b461", "aac151", "d8dc86" }, 150, 8, 14)
  swatches(sprite, palette, "ramp/soil", { "6e3b2e", "8b533a", "ab6743", "c97d4a", "e0a46c" }, 150, 26, 14)
  swatches(sprite, palette, "ramp/stone", { "5e4a55", "88696e", "a98d8a", "cdb8ae" }, 150, 44, 14)
  swatches(sprite, palette, "accent/white", { "fff6e4" }, 150, 62, 14)
  swatches(sprite, palette, "accent/yellow", { "f2d36b" }, 166, 62, 14)
  local _, strokes = layer(sprite, "brushes")
  -- Leaf dab: a tapered almond with a ragged edge, pointing right.
  brush(sprite, strokes, "leaf", 150, 90, 28, 16, function(x, y, w, h)
    local t = (x / w) * 2 - 1
    local half = (h * 0.5 - 0.5) * (1 - t * t) ^ 0.55 * (1 - 0.3 * math.max(0, t))
    half = half * (0.88 + 0.24 * hash(math.floor(x), 0, 3))
    return soft(half - math.abs(y - h * 0.5), 1.4)
  end)
  -- Round dab with a broken outline.
  brush(sprite, strokes, "round", 184, 90, 16, 16, function(x, y, w, h)
    local dx, dy = x - w * 0.5, y - h * 0.5
    local angle = math.atan(dy, dx)
    local radius = w * 0.45 * (0.9 + 0.1 * math.sin(angle * 5 + 1.3) + 0.06 * hash(math.floor(angle * 6), 1, 5))
    return soft(radius - math.sqrt(dx * dx + dy * dy), 1.5)
  end)
  -- Blade flick: thick at the base, sharp curved tip at the top.
  brush(sprite, strokes, "flick", 206, 84, 12, 22, function(x, y, w, h)
    local t = 1 - y / h
    local centre = w * 0.5 + 2.2 * t * t
    local half = 3.6 * (1 - t) ^ 0.75 + 0.35
    return soft(half - math.abs(x - centre), 1.0) * soft(h - y, 2.5)
  end)
  -- Dry smear: long stroke with bristle streaks and tapered ends.
  brush(sprite, strokes, "smear", 220, 92, 44, 10, function(x, y, w, h)
    local t = x / w
    local half = (h * 0.5 - 0.5) * math.sin(math.pi * t) ^ 0.35
    local streak = 0.62 + 0.38 * hash(0, math.floor(y), 9)
    return soft(half - math.abs(y - h * 0.5), 1.2) * streak
  end)
  -- Stone: a flat-bottomed pebble silhouette.
  brush(sprite, strokes, "stone", 270, 88, 26, 16, function(x, y, w, h)
    local dx, dy = (x - w * 0.5) / (w * 0.48), (y - h * 0.62) / (h * 0.6)
    if dy > 0 then dy = dy * 1.7 end
    local d = (math.abs(dx) ^ 2.6 + math.abs(dy) ^ 2.2)
    return soft((1 - d) * 4, 1)
  end)
  brush(sprite, strokes, "dot", 302, 94, 6, 6, function(x, y, w, h)
    local dx, dy = x - w * 0.5, y - h * 0.5
    return soft(2.4 - math.sqrt(dx * dx + dy * dy), 1)
  end)
  sprite:saveAs(app.fs.joinPath(root, "concepts", "painted_grass.aseprite"))
  sprite:close()
end

pixel_concept()
painted_concept()
print("concept sheets written")
