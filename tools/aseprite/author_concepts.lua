-- Bootstrap for terrain concept sheets (Aseprite batch mode). Artists edit the
-- resulting .aseprite files directly afterwards, so existing files are kept unless
-- --script-param force=1. Optional --script-param reference=<png> fills the
-- reference layer (review only; code never reads it).
--   aseprite -b --script-param out=addons/jeff_map_studio/art/concepts/pixel --script tools/aseprite/author_concepts.lua
--
-- Sheet convention (one frame):
--   reference : target look, for review and regression comparison
--   palette   : slices "ramp/<name>" (swatches dark -> light) and "accent/<name>"
--   motifs    : slices "motif/<group>/<nn>", drawn in the real default colours;
--               tools/import_concepts.gd maps every colour back to a ramp step
local out = app.params.out
assert(out and #out > 0, "missing --script-param out=<directory>")
local force = app.params.force == "1"

local function hex(value)
  return Color{ r = tonumber(value:sub(1, 2), 16), g = tonumber(value:sub(3, 4), 16), b = tonumber(value:sub(5, 6), 16), a = 255 }
end

local function exists(path)
  local file = io.open(path, "rb")
  if file then file:close() return true end
  return false
end

local function layer(sprite, name)
  local result = sprite:newLayer()
  result.name = name
  return sprite:newCel(result, 1, Image(sprite.width, sprite.height, ColorMode.RGB), Point(0, 0)).image
end

local function slice(sprite, name, x, y, w, h)
  sprite:newSlice(Rectangle(x, y, w, h)).name = name
end

-- Pixel grass ----------------------------------------------------------------
-- Ramps are the plugin's default grass colours run through MapPixelArt.ramp().
local RAMPS = {
  top = { "21602b", "347831", "589245", "81ac5d", "bbd088", "dde6ab" },
  soil = { "641a23", "7d2d29", "98513c", "b37a52", "ccac85", "e0ceab" },
  stone = { "4b3752", "614c67", "7a647d", "927f93", "c6bbca", "e6e4db" },
}
local ACCENTS = { { "white", "fff4d6", "a" }, { "yellow", "f6d65a", "b" }, { "lilac", "c8b6f0", "d" }, { "shell", "f7d9cf", "l" } }
-- Digits are steps of the "top" ramp; letters are the accents above.
local MOTIFS = {
  { "tuft", { { "4.4", "2.2" }, { "4.4.4", "2.2.2" }, { ".4.", "424", "2.2" }, { "4..", "2.4", "..2" }, { "..4", "4.2", "2.." }, { "5.4", "424", "2.2" } } },
  { "flower", { { "a", "2" }, { "b", "2" }, { "a.a", "2.2" }, { "d", "2" } } },
  { "flower_patch", { { "a.b.", "2a2b", ".2.2" }, { ".d.a", "d2a2", "2.2." }, { "b.b", "2b2", ".2." } } },
  { "clover", { { ".4.4.", "43434", ".232." }, { "4.4", "343", ".2." }, { ".44", "433", "22." } } },
}

local function pixel_grass(path)
  local sprite = Sprite(212, 74, ColorMode.RGB)
  sprite.layers[1].name = "reference"
  local reference = app.params.reference
  if reference and #reference > 0 and exists(reference) then
    sprite.cels[1].image:drawImage(Image{ fromFile = reference }, Point(98, 2))
  end
  local palette = layer(sprite, "palette")
  local y = 2
  for _, name in ipairs({ "top", "soil", "stone" }) do
    for i, value in ipairs(RAMPS[name]) do
      for dy = 0, 4 do
        for dx = 0, 4 do palette:drawPixel(2 + (i - 1) * 5 + dx, y + dy, hex(value)) end
      end
    end
    slice(sprite, "ramp/" .. name, 2, y, #RAMPS[name] * 5, 5)
    y = y + 6
  end
  local accent_of = {}
  for i, item in ipairs(ACCENTS) do
    for dy = 0, 4 do
      for dx = 0, 4 do palette:drawPixel(2 + (i - 1) * 6 + dx, y + dy, hex(item[2])) end
    end
    slice(sprite, "accent/" .. item[1], 2 + (i - 1) * 6, y, 5, 5)
    accent_of[item[3]] = item[2]
  end
  local motifs = layer(sprite, "motifs")
  local x, my = 36, 2
  for _, group in ipairs(MOTIFS) do
    for index, rows in ipairs(group[2]) do
      local w, h = #rows[1], #rows
      if x + w > 94 then x, my = 36, my + 6 end
      for row, line in ipairs(rows) do
        for column = 1, #line do
          local key = line:sub(column, column)
          local value = accent_of[key] or (key ~= "." and RAMPS.top[tonumber(key) + 1]) or nil
          if value then motifs:drawPixel(x + column - 1, my + row - 1, hex(value)) end
        end
      end
      slice(sprite, string.format("motif/%s/%02d", group[1], index), x, my, w, h)
      x = x + w + 2
    end
    x, my = 36, my + 6
  end
  sprite:saveAs(path)
  sprite:close()
end

local path = app.fs.joinPath(out, "grass.aseprite")
if exists(path) and not force then
  print("skip existing " .. path)
else
  pixel_grass(path)
  print("wrote " .. path)
end
