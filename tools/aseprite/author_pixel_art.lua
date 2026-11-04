-- Bootstrap for the pixel-style Aseprite sources. Run once in batch mode:
--   aseprite -b --script-param out=addons/jeff_map_studio/assets/pixel --script tools/aseprite/author_pixel_art.lua
-- It refuses to overwrite existing .aseprite files unless --script-param force=1,
-- because artists edit those files directly afterwards.
local out = app.params.out
assert(out and #out > 0, "missing --script-param out=<directory>")
local force = app.params.force == "1"

local function hex(value)
  local r = tonumber(value:sub(1, 2), 16)
  local g = tonumber(value:sub(3, 4), 16)
  local b = tonumber(value:sub(5, 6), 16)
  return Color{ r = r, g = g, b = b, a = 255 }
end

local function exists(path)
  local file = io.open(path, "rb")
  if file then file:close() return true end
  return false
end

local function palette_of(keys, colors)
  local palette = Palette(#keys + 1)
  palette:setColor(0, Color{ r = 0, g = 0, b = 0, a = 0 })
  for i, key in ipairs(keys) do
    palette:setColor(i, hex(colors[key]))
  end
  return palette
end

-- Objects: one frame per object, bottom-centred, contact shadow on its own 50% layer.
local OBJECT_COLORS = {
  ["1"] = "183a33",
  ["2"] = "2a6142",
  ["3"] = "3f8c48",
  ["4"] = "6fb853",
  ["5"] = "b8e070",
  ["q"] = "3a2124",
  ["w"] = "6b3a2c",
  ["e"] = "9c5b38",
  ["r"] = "cf9254",
  ["R"] = "eab976",
  ["z"] = "2b2c45",
  ["x"] = "545a78",
  ["c"] = "8790aa",
  ["v"] = "bfc6d6",
  ["V"] = "e6eaf0",
  ["g"] = "7d4f1d",
  ["h"] = "d49a32",
  ["j"] = "ffe08a",
  ["m"] = "5c1b2c",
  ["n"] = "a8323f",
  ["o"] = "e2574d",
  ["O"] = "f2907a",
  ["a"] = "fff6e0",
  ["s"] = "e6d5b5",
  ["d"] = "b39d86",
  ["f"] = "7d6a62",
  ["t"] = "173d4c",
  ["y"] = "25737c",
  ["u"] = "4fb3a8",
  ["U"] = "9de0c8",
  ["p"] = "d9768f",
  ["l"] = "f6c3cf",
}
local OBJECT_KEYS = { "1", "2", "3", "4", "5", "q", "w", "e", "r", "R", "z", "x", "c", "v", "V", "g", "h", "j", "m", "n", "o", "O", "a", "s", "d", "f", "t", "y", "u", "U", "p", "l" }
local SHADOW = "102028"
local OBJECTS = {
  { name = "tree", rows = {
    "............222.........",
    "........22224441........",
    ".......255544441........",
    ".......255444433122.....",
    ".....222444443332542....",
    "..22244414443322544411..",
    ".2555444313332554444331.",
    ".2544444322222444443331.",
    ".2444443255441144433321.",
    ".244433255444431333321..",
    ".133332444444331332221..",
    "..11112444443321111111..",
    "......1133333221q.......",
    "........1332111q........",
    "..........qrewq.........",
    "..........qrwq..........",
    ".........qrewq..........",
    ".........qreq...........",
    ".........qrewq..........",
    "........qrreewq.........",
    ".......qrreeewwq........",
    "....3.qrrqewwqwq.4......",
    "...c%vcqq%%%qq%vc43.....",
    "....%%%%%%%%%%%%%.......",
  } },
  { name = "rock", rows = {
    "......zz........",
    ".....zvvz.......",
    "....zvVcz.......",
    "...3zvccxz......",
    "..34zvjhxz......",
    "..zz4vhcxz.zz...",
    ".zvvzvjjxzzvcz..",
    ".zvc4vccxxzzvcz.",
    "zvVcxvccxxxzccxz",
    "zvccxvccxxxzvcxz",
    "zcc4xcccxx3zcxxz",
    "3zxxzxcxx34zxxz3",
    "43zzzzzzz243zz34",
    ".%%%%%%%%%%%%%%.",
  } },
  { name = "chest", rows = {
    ".....tttttt....",
    "...ttuuuuyytt..",
    ".ttuUUuuyyyyyt.",
    "tuUUuuuuyyyyyyt",
    "tyuuuuyyyyyytyt",
    "thhjjhhhhhhhhgt",
    "qrrhhrrrrrrrhgq",
    "qrRhjhrrrrrrhwq",
    "qrrhghreeeeehwq",
    "qeehhheeeeeehwq",
    "qweehweeeeeehwq",
    ".qqqqqqqqqqqqq.",
    "..%%%%%%%%%%%..",
  } },
  { name = "mushrooms", rows = {
    "....mmmmm.......",
    "..mmOOaoonm.....",
    ".mOOaaaoooonm...",
    ".mOoaaooaaonm...",
    "mOooooooaaonnm..",
    "mooaooooooonnm..",
    ".mnnnnnnnnnmm...",
    "...mfssaadf.mmm.",
    "....fsaadf.mOonm",
    ".mmm.saad.mooanm",
    "mOonmsaadmnnnnm.",
    "mnnnfsaadf.saf..",
    ".dsf.saasd.saf3.",
    "34saddssdd2sad42",
    ".%2342%3%%42%%..",
  } },
  { name = "palm", rows = {
    "..........1111...........",
    ".........145441..........",
    ".........1454421.........",
    "...11111..134421.11111...",
    ".11555541.13421.14555511.",
    "1455444441134211444445541",
    "1443333224134214223333441",
    "143221.1.21wh1121.1.12341",
    "1321....1qwjhgq1....1231.",
    "131....14qhgwhq41....131.",
    "11....1453qwgq3541....11.",
    ".....14531.qwq.13541.....",
    "....14321..qreq..12341...",
    "...1431....qrwq....1341..",
    "...131....qreq......131..",
    "...11.....qrwq.......11..",
    "..........qreq...........",
    ".........qrwq............",
    ".........qreq............",
    ".........qrewq...........",
    ".........qrweq...........",
    "........qrreeq...........",
    ".......3qrreewq3.........",
    "......l34qrrewq43pl......",
    ".....lpl4qqqqqq3lpl......",
    "......%%%%%%%%%%%%.......",
  } },
  { name = "lighthouse", rows = {
    "......g......",
    ".....ghg.....",
    "....tyuyt....",
    "...tyUuyyt...",
    "..tyuuyyyyt..",
    ".ttttttttttt.",
    "..qjjhjhhgq..",
    "..qjaajhhgq..",
    "..qhjjhhggq..",
    ".qqqqqqqqqqq.",
    ".q.q.q.q.q.q.",
    "...faassdf...",
    "...fassddf...",
    "...fasttdf...",
    "...fassddf...",
    "..mOonnnnnm..",
    "..mOonnnnnm..",
    "..fassssddf..",
    "..fasssssdf..",
    "..faasssddf..",
    ".fasssssdddf.",
    ".fassqqqsddf.",
    ".fassqwrqsdf.",
    "zvvccqwrqcxxz",
    "zvccxqwrqxxxz",
    "3zvccxxxxxxz4",
    "43zzzzzzzzz34",
    ".%%%%%%%%%%%.",
  } },
}

local function build_objects(path)
  local width, height = 0, 0
  for _, object in ipairs(OBJECTS) do
    width = math.max(width, #object.rows[1])
    height = math.max(height, #object.rows)
  end
  width = width + 2
  height = height + 1
  local sprite = Sprite(width, height, ColorMode.RGB)
  sprite:setPalette(palette_of(OBJECT_KEYS, OBJECT_COLORS))
  local art = sprite.layers[1]
  art.name = "art"
  local shadow = sprite:newLayer()
  shadow.name = "contact shadow"
  shadow.opacity = 128
  for index, object in ipairs(OBJECTS) do
    if index > 1 then sprite:newEmptyFrame() end
    local art_image = Image(width, height, ColorMode.RGB)
    local shadow_image = Image(width, height, ColorMode.RGB)
    local w, h = #object.rows[1], #object.rows
    local ox, oy = 1 + (width - 2 - w) // 2, height - h
    for y, row in ipairs(object.rows) do
      for x = 1, w do
        local key = row:sub(x, x)
        if key == "%" then
          shadow_image:drawPixel(ox + x - 1, oy + y - 1, hex(SHADOW))
        elseif key ~= "." then
          art_image:drawPixel(ox + x - 1, oy + y - 1, hex(OBJECT_COLORS[key]))
        end
      end
    end
    sprite:newCel(art, index, art_image, Point(0, 0))
    sprite:newCel(shadow, index, shadow_image, Point(0, 0))
  end
  -- Tags are added last: a tag ending on the final frame grows with each new frame.
  for index, object in ipairs(OBJECTS) do
    local tag = sprite:newTag(index, index)
    tag.name = object.name
  end
  sprite:saveAs(path)
  sprite:close()
end

-- Clusters: ramp keys 0-5 are recoloured per material at runtime; letters are fixed accents.
local CLUSTER_COLORS = {
  ["0"] = "1c1f26", ["1"] = "3d434f", ["2"] = "666e7d", ["3"] = "959daa", ["4"] = "c4cad3", ["5"] = "f2f4f7",
  ["a"] = "fff4d6", ["b"] = "f6d65a", ["d"] = "c8b6f0", ["l"] = "f7d9cf",
}
local CLUSTER_KEYS = { "0", "1", "2", "3", "4", "5", "a", "b", "d", "l" }
local CLUSTERS = {
  { name = "grass_tufts", stamps = {
    { "4.4", "2.2" },
    { "4.4.4", "2.2.2" },
    { ".4.", "424", "2.2" },
    { "4..", "2.4", "..2" },
    { "..4", "4.2", "2.." },
    { "5.4", "424", "2.2" },
  } },
  { name = "grass_flowers", stamps = {
    { "a", "2" },
    { "b", "2" },
    { "a.a", "2.2" },
    { "d", "2" },
  } },
  { name = "sand_pebbles", stamps = {
    { "4", "1" },
    { "54", "21" },
    { "5.", "2." },
    { "l", "2" },
  } },
  { name = "water_glints", stamps = {
    { "44" },
    { "454" },
    { "44.", "..4" },
    { "5" },
    { ".4.", "4.4" },
  } },
  { name = "rock_chips", stamps = {
    { "45", "21" },
    { ".4.", "432" },
  } },
}

local function build_clusters(path)
  local width, height = 0, 0
  for _, group in ipairs(CLUSTERS) do
    for _, stamp in ipairs(group.stamps) do
      width = math.max(width, #stamp[1])
      height = math.max(height, #stamp)
    end
  end
  local sprite = Sprite(width, height, ColorMode.RGB)
  sprite:setPalette(palette_of(CLUSTER_KEYS, CLUSTER_COLORS))
  sprite.layers[1].name = "clusters"
  local frame = 0
  local ranges = {}
  for _, group in ipairs(CLUSTERS) do
    local first = frame + 1
    for _, stamp in ipairs(group.stamps) do
      frame = frame + 1
      if frame > 1 then sprite:newEmptyFrame() end
      local image = Image(width, height, ColorMode.RGB)
      local oy = height - #stamp
      for y, row in ipairs(stamp) do
        for x = 1, #row do
          local key = row:sub(x, x)
          if key ~= "." then
            image:drawPixel(x - 1, oy + y - 1, hex(CLUSTER_COLORS[key]))
          end
        end
      end
      sprite:newCel(sprite.layers[1], frame, image, Point(0, 0))
    end
    table.insert(ranges, { group.name, first, frame })
  end
  for _, range in ipairs(ranges) do
    local tag = sprite:newTag(range[2], range[3])
    tag.name = range[1]
  end
  sprite:saveAs(path)
  sprite:close()
end

for _, item in ipairs({ { "landmarks.aseprite", build_objects }, { "clusters.aseprite", build_clusters } }) do
  local path = app.fs.joinPath(out, item[1])
  if exists(path) and not force then
    print("skip existing " .. path)
  else
    item[2](path)
    print("wrote " .. path)
  end
end
