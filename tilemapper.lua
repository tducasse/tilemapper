-- tilemapper v0.0.1
-- Depends on:
--  - json.lua (https://github.com/rxi/json.lua)
--  - classic.lua (https://github.com/rxi/classic)
--  - bump.lua (https://github.com/kikito/bump.lua)

local json = require("json")
local Class = required("classic")

local Tilemapper = Class:extend()

local Layer = Class:extend()
function Layer:new(tiles, name)
  self.tiles = tiles
  self.name = name
end

local IntGrid = Layer:extend()
function IntGrid:new(tiles, name, size)
  IntGrid.super.new(self, tiles, name)
  self.type = "int"
  self.size = size
end

local AutoLayer = Layer:extend()
function AutoLayer:new(tiles, name, tileset, size, spacing, padding)
  AutoLayer.super.new(self, tiles, name)
  self.type = "auto"
  self.tileset = love.graphics.newImage(tileset)
  self.size = size
  local quadInfo = {}
  for i = 1, #tiles do
    local tile = tiles[i]
    if not quadInfo[tile.t] then
      quadInfo[tile.t] = tile.src
    end
  end
  local quads = {}
  for k, info in pairs(quadInfo) do
    local offX = math.floor(info[1] / size) * (padding + spacing) + padding
    local offY = math.floor(info[2] / size) * (padding + spacing) + padding
    quads[k] = love.graphics.newQuad(
                   offX, offY, size, size, self.tileset:getWidth(),
                   self.tileset:getHeight())
  end
  self.quads = quads
end

local function getIntGrid(layer)
  local width = layer.__cWid
  local grid = layer.intGridCsv
  local tiles = {}
  local size = layer.__gridSize
  for i = 0, #grid - 1 do
    if grid[i + 1] > 0 then
      local y = math.floor(i / width)
      local x = i - y * width
      tiles[#tiles + 1] = {
        x = x * size,
        y = y * size,
        v = grid[i + 1],
        h = size,
        w = size,
      }
    end
  end
  return IntGrid(tiles, layer.__identifier, size)
end

local function getAutoLayer(layer, root, options, tilesets)
  local tilesetPath = root .. layer.__tilesetRelPath
  local tileset = tilesets[layer.__tilesetDefUid]
  if options and options.aseprite then
    tilesetPath = tilesetPath:gsub("aseprite", "png")
  end
  return AutoLayer(
             layer.autoLayerTiles, layer.__identifier, tilesetPath,
             layer.__gridSize, tileset.spacing, tileset.padding)
end

local function getEntities(layer)
  local instances = layer.entityInstances
  local entities = {}
  for i = 1, #instances do
    local entity = instances[i]
    local _fields = entity.fieldInstances
    local fields = {}
    for j = 1, #_fields do
      local field = _fields[j]
      fields[field.__identifier] = field.__value
    end
    entities[entity.__identifier] = {
      x = entity.px[1],
      y = entity.px[2],
      top = fields.top,
      left = fields.left,
      w = entity.width,
      h = entity.height,
    }
  end
  entities.name = layer.__identifier
  return entities
end

local layerTypes = {
  AutoLayer = getAutoLayer,
  IntGrid = getIntGrid,
  Entities = getEntities,
}

local function getLayer(_layer, root, options, tilesets)
  local layer = {}
  local getLayerByType = layerTypes[_layer.__type]
  if getLayerByType then
    layer = getLayerByType(_layer, root, options, tilesets)
  else
    layer.name = _layer.__identifier
  end
  return layer
end

local function getLayers(_layers, root, options, tilesets)
  local layers = {}
  for i = 1, #_layers do
    local _layer = _layers[i]
    local layer = getLayer(_layer, root, options, tilesets)
    layers[layer.name] = layer
  end
  return layers
end

local function getNeighbours(level, levelsByUid)
  local _neighbours = level.__neighbours
  local neighbours = {}
  for i = 1, #_neighbours do
    local neighbour = _neighbours[i]
    neighbours[neighbour.dir] = levelsByUid[neighbour.levelUid]
  end
  return neighbours
end

local function getLevel(_level, root, options, tilesets, levelsByUid)
  local level = getLayers(_level.layerInstances, root, options, tilesets)
  level.name = _level.identifier
  level.width = _level.pxWid
  level.height = _level.pxHei
  level.next = getNeighbours(_level, levelsByUid)
  return level
end

local function getLevels(_levels, root, options, tilesets, levelsByUid)
  local levels = {}
  for i = 1, #_levels do
    local _level = _levels[i]
    local level = getLevel(_level, root, options, tilesets, levelsByUid)
    levels[level.name] = level
  end
  return levels
end

function Tilemapper:new(path, options)
  local root = path:gsub("[^/]+.ldtk", "")
  local data = love.filesystem.read(path)
  local raw = json.decode(data)
  local _levels = raw.levels
  local _tilesets = raw.defs.tilesets
  local tilesets = {}
  for i = 1, #_tilesets do
    local tileset = _tilesets[i]
    tilesets[tileset.uid] = {
      padding = tileset.padding,
      spacing = tileset.spacing,
    }
  end
  local levelsByUid = {}
  for i = 1, #_levels do
    local level = _levels[i]
    levelsByUid[level.uid] = level.identifier
  end
  local levels = getLevels(_levels, root, options, tilesets, levelsByUid)
  self.levels = levels
end

function IntGrid:addCollisions(world)
  local tiles = self.tiles
  for i = 1, #tiles do
    local tile = tiles[i]
    world:add(tile, tile.x, tile.y, tile.w, tile.h)
  end
end

function Tilemapper:addCollisions()
  local layers = self.active
  for _, layer in pairs(layers) do
    local meta = getmetatable(layer)
    if meta and meta.addCollisions then
      layer:addCollisions(self.world)
    end
  end
end

function IntGrid:removeCollisions(world)
  local tiles = self.tiles
  for i = 1, #tiles do
    local tile = tiles[i]
    world:remove(tile)
  end
end

function Tilemapper:removeCollisions()
  local layers = self.active
  for _, layer in pairs(layers) do
    local meta = getmetatable(layer)
    if meta and meta.addCollisions then
      layer:removeCollisions(self.world)
    end
  end
end

function AutoLayer:draw()
  local tiles = self.tiles
  for i = 1, #tiles do
    local tile = tiles[i]
    love.graphics.draw(self.tileset, self.quads[tile.t], tile.px[1], tile.px[2])
  end
end

function Tilemapper:loadLevel(name, world)
  if not self.world and world then
    self.world = world
  end
  if not self.levels[name] then
    return false
  end
  self.current = name
  if self.active then
    self:removeCollisions()
  end
  self.active = self.levels[self.current]
  self:addCollisions()
end

function Tilemapper:nextLevel(dir)
  local nextLevel = self.active.next[dir]
  if not nextLevel then
    return false
  end
  self:loadLevel(self.active.next[dir])
end

function Tilemapper:draw()
  local layers = self.active
  for _, layer in pairs(layers) do
    local meta = getmetatable(layer)
    if meta and meta.draw then
      layer:draw()
    end
  end
end

return Tilemapper

