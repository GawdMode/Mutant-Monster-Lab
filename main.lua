-- Mutant Monster Lab - DEV64
-- Crystal / Gen1Recomp 0.2.53
--
-- DEV7 pivots the buried laboratory to Crystal's surviving Japanese-only
-- PokeCom/Mobile maps.  These maps retain their native Crystal block/tileset
-- data, so cloning them avoids the deleted legacy Cinnabar Lab blockset.

local CINNABAR = "CINNABAR_ISLAND"
local CHERRYGROVE = "CHERRYGROVE_CITY"

local ADMIN_TEMPLATE = "POKECOM_CENTER_ADMIN_OFFICE_MOBILE"
local TRADE_TEMPLATE = "MOBILE_TRADE_ROOM"
local BATTLE_TEMPLATE = "MOBILE_BATTLE_ROOM"

local LAB_MAIN = "CINNABAR_EXPERIMENTAL_LAB_MAIN"
local LAB_RESEARCH = "CINNABAR_EXPERIMENTAL_LAB_RESEARCH"
local LAB_TEST = "CINNABAR_EXPERIMENTAL_LAB_TEST"

-- Working DEV6 exterior.
local CAVE_CELL_X, CAVE_CELL_Y = 8, 5
local SIGN_X, SIGN_Y = 7, 7
local CAVE_WARP_INDEX = 1

-- Verified by DEV21 diagnostic:
-- player stands at (0,7), faces cell (0,6), block (0,3), ID $02.
local PINK_DOOR_PLAYER_X, PINK_DOOR_PLAYER_Y = 0, 7
local PINK_DOOR_TILE_X, PINK_DOOR_TILE_Y = 0, 6

-- Small lower-left computer/admin area shown in the user's second screenshot.
-- Use its red threshold as the paired internal doorway.
local COMPUTER_ROOM_ENTRY_X, COMPUTER_ROOM_ENTRY_Y = 1, 31
local COMPUTER_ROOM_EXIT_X, COMPUTER_ROOM_EXIT_Y = 1, 32


-- The native PokeCom map is 16x16 blocks = 32x32 walk cells. Its original
-- exit is tucked into the far lower-left administration corner, which made
-- DEV7 look like a tiny room. These coordinates place the player on the
-- broad central laboratory floor so the large facility is immediately visible.
local MAIN_ENTRY_X, MAIN_ENTRY_Y = 7, 15

-- Hub routing points on the surviving PokeCom floor.
-- The red entrance threshold is the bottom-center strip visible in the map.
local EXIT_MIN_X, EXIT_MAX_X, EXIT_Y = 6, 7, 15



-- Existing PokeCom admin-office computer locations.  For DEV7 these are
-- deliberately temporary room access points; after visual inspection we'll
-- replace them with physical doors placed where they make sense.
local RESEARCH_TERMINAL_X, RESEARCH_TERMINAL_Y = 6, 26
local TEST_TERMINAL_X, TEST_TERMINAL_Y = 6, 28

local function deep(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local o = {}
  seen[v] = o
  for k,x in pairs(v) do o[deep(k,seen)] = deep(x,seen) end
  return o
end


local function monName(game, mon)
  if not mon then return "POKéMON" end
  if mon.nickname and mon.nickname ~= "" then return mon.nickname end
  local def = game and game.data and game.data.pokemon
    and game.data.pokemon[mon.species]
  return (def and def.name) or tostring(mon.species or "POKéMON")
end

local function fusionData(mon)
  mon.cinnabarFusion = mon.cinnabarFusion or {
    stability = 100,
    spliceCount = 0,
    history = {},
    anomalies = {},
  }
  local f = mon.cinnabarFusion
  f.stability = tonumber(f.stability) or 100
  f.spliceCount = tonumber(f.spliceCount) or 0
  f.history = f.history or {}
  f.anomalies = f.anomalies or {}
  return f
end

local function stabilityLabel(value)
  value = tonumber(value) or 100
  if value >= 81 then return "STABLE" end
  if value >= 61 then return "ALTERED" end
  if value >= 41 then return "UNSTABLE" end
  if value >= 21 then return "CRITICAL" end
  if value >= 1 then return "CORRUPTED" end
  return "???"
end

local function falloutChance(stability)
  stability = tonumber(stability) or 100
  if stability >= 81 then return 0 end
  if stability >= 61 then return 0.15 end
  if stability >= 41 then return 0.30 end
  if stability >= 21 then return 0.50 end
  return 0.75
end

local function falloutSeverity(stability)
  stability = tonumber(stability) or 100
  if stability >= 61 then return 1 end
  if stability >= 41 then return 2 end
  if stability >= 21 then return 3 end
  return 4
end

return function(mod)
  mod.options:define({
    { key="dev_warp", label="DEV CINNABAR WARP", type="toggle", default=true },
    { key="dev_money", label="DEV MONEY ¥99999", type="toggle", default=false },
    { key="dev_fallout", label="DEV FORCE FALLOUT", type="toggle", default=false },
  })

  -- Spliced Pokémon keep the HOST species/sprite but can borrow the DONOR's
  -- native Crystal palette.  Wrap the two most important individual-mon pic
  -- renderers so this remains per Pokémon rather than recoloring a species
  -- globally.
  local Palettes = require("src.world.gen2.Palettes")
  -- Compatibility guard for other mods that accidentally run Gen 1 Stats.calc
  -- on a Gen 2 Pokemon while moving it through a custom PC flow. Vanilla
  -- Gen2 BoxMenu.withdraw never calls src/pokemon/Stats.lua, but a foreign
  -- wrapper can. Map split Special to a temporary Gen1-style Special instead
  -- of letting that cross-gen call crash at Stats.lua:28.
  local Gen1Stats = require("src.pokemon.Stats")
  if not Gen1Stats._cinnabarGen2Guard then
    local downstreamStatsCalc = Gen1Stats.calc
    Gen1Stats.calc = function(speciesDef, level, dvs, statExp)
      local bs = speciesDef and speciesDef.baseStats
      if bs and bs.special == nil
          and (bs.specialAttack ~= nil or bs.specialDefense ~= nil) then
        local safeDef = {}
        for k,v in pairs(speciesDef) do safeDef[k]=v end
        local safeStats = {}
        for k,v in pairs(bs) do safeStats[k]=v end
        safeStats.special = safeStats.specialAttack
          or safeStats.specialDefense or 1
        safeDef.baseStats = safeStats
        local safeDvs = dvs or {}
        if safeDvs.special == nil then
          local copied = {}
          for k,v in pairs(safeDvs) do copied[k]=v end
          copied.special = copied.specialAttack or copied.specialDefense or 0
          safeDvs = copied
        end
        return downstreamStatsCalc(safeDef, level, safeDvs, statExp)
      end
      return downstreamStatsCalc(speciesDef, level, dvs, statExp)
    end
    Gen1Stats._cinnabarGen2Guard = true
  end
  local AssetsGlobal = require("src.render.Assets")

  local function copyPalette(pal)
    if type(pal) ~= "table" then return nil end
    local out = {}
    for i=1,4 do
      local c = pal[i]
      if type(c) == "table" then out[i] = {c[1], c[2], c[3]} end
    end
    return out
  end

  local function effectivePalette(mon, paletteData)
    local f = mon and mon.cinnabarFusion
    if f and f.paletteOverride then return f.paletteOverride end
    if f and f.paletteSpecies then
      return Palettes.monColors(paletteData, f.paletteSpecies, false)
    end
    -- No Cinnabar color mutation: preserve the currently installed/base
    -- renderer's palette decision. This lets PokeSurvive/randomizer visuals
    -- remain the baseline under size/fragment-only Cinnabar mutations.
    if mon and mon.species then
      return Palettes.monColors(paletteData, mon.species, mon.shiny)
    end
    return nil
  end

  local SoundGlobal = require("src.core.Sound")

  local function cryMutation(mon)
    local f = mon and mon.cinnabarFusion
    return f and f.cryMutation or nil
  end

  local function effectiveCrySpecies(mon)
    local c = cryMutation(mon)
    return (c and c.species) or (mon and mon.species)
  end

  local function playIndividualCry(data, mon, pikaClip)
    if not (data and mon) then return nil end
    local species = effectiveCrySpecies(mon)
    if not species then return nil end
    local src = SoundGlobal.playCry(data, species, pikaClip)
    local c = cryMutation(mon)
    if src and c and tonumber(c.pitch) then
      pcall(src.setPitch, src, tonumber(c.pitch))
    end
    return src
  end

  local function withFusionPalette(mon, fn)
    local fusion = mon and mon.cinnabarFusion
    local donor = fusion and fusion.paletteSpecies
    local override = fusion and fusion.paletteOverride
    if not donor and not override then return fn() end

    local vanilla = Palettes.monColors
    Palettes.monColors = function(data, speciesId, shiny)
      if speciesId == mon.species then
        if override then return override end
        return vanilla(data, donor, false) or vanilla(data, speciesId, shiny)
      end
      return vanilla(data, speciesId, shiny)
    end
    local ok, a, b, c = pcall(fn)
    Palettes.monColors = vanilla
    if not ok then error(a) end
    return a, b, c
  end

  local function fragmentImage(data, species, back)
    local def = data and data.pokemon and data.pokemon[species]
    if not def then return nil end
    local path = back and def.spriteBack or def.spriteFront
    if not path then return nil end
    local ok, image = pcall(AssetsGlobal.image, path)
    return ok and image or nil
  end

  -- Runtime anatomy profiler. Gen1Recomp already exposes the extracted
  -- front-pic ImageData, so we can profile every species on demand instead of
  -- hand-authoring 251 rectangles. The profile finds occupied bounds and
  -- scores semantic extremity zones (ears/horns/face/arms/tail/feet).
  local anatomyCache = {}
  local ANATOMY_SLOTS = {
    -- Dedicated top-center zone is important for horns, crests and antennae.
    {id="TOP",    cx=.50, cy=.07, w=.26, h=.28, edge=.34},
    {id="HEAD_L", cx=.22, cy=.16, w=.28, h=.30, edge=.28},
    {id="HEAD_R", cx=.78, cy=.16, w=.28, h=.30, edge=.28},
    {id="FACE",   cx=.50, cy=.27, w=.30, h=.27, edge=.10},
    {id="SIDE_L", cx=.12, cy=.51, w=.28, h=.34, edge=.30},
    {id="SIDE_R", cx=.88, cy=.51, w=.28, h=.34, edge=.30},
    {id="FOOT_L", cx=.27, cy=.86, w=.28, h=.28, edge=.26},
    {id="FOOT_R", cx=.73, cy=.86, w=.28, h=.28, edge=.26},
  }

  local function clamp(v,a,b) return math.max(a,math.min(b,v)) end

  local function profileSprite(data, species)
    if anatomyCache[species] then return anatomyCache[species] end
    local def=data and data.pokemon and data.pokemon[species]
    local path=def and def.spriteFront
    if not path then return nil end
    local ok,id=pcall(AssetsGlobal.imageData,path)
    if not ok or not id then return nil end
    local w,h=id:getDimensions()
    local minx,miny,maxx,maxy=w,h,-1,-1

    -- Alpha is authoritative when present. Dark/outline pixels are a fallback
    -- for caches whose white shade is opaque.
    local occupied={}
    for y=0,h-1 do
      occupied[y]={}
      for x=0,w-1 do
        local r,g,b,a=id:getPixel(x,y)
        local on=(a or 0)>.05 and ((a or 0)<.999 or (r or 1)<.965)
        if on then
          occupied[y][x]=true
          minx,miny=math.min(minx,x),math.min(miny,y)
          maxx,maxy=math.max(maxx,x),math.max(maxy,y)
        end
      end
    end
    if maxx<minx then
      minx,miny,maxx,maxy=0,0,w-1,h-1
    end
    local bw,bh=maxx-minx+1,maxy-miny+1
    local slots={}
    for _,slot in ipairs(ANATOMY_SLOTS) do
      local rw=math.max(8,math.floor(bw*slot.w+.5))
      local rh=math.max(8,math.floor(bh*slot.h+.5))
      local cx=minx+bw*slot.cx
      local cy=miny+bh*slot.cy
      local rx=clamp(math.floor(cx-rw/2+.5),0,w-rw)
      local ry=clamp(math.floor(cy-rh/2+.5),0,h-rh)
      local count=0
      local lx,ly,lx2,ly2=rw,rh,-1,-1
      for yy=ry,math.min(h-1,ry+rh-1) do
        for xx=rx,math.min(w-1,rx+rw-1) do
          if occupied[yy] and occupied[yy][xx] then
            count=count+1
            local ox,oy=xx-rx,yy-ry
            lx,ly=math.min(lx,ox),math.min(ly,oy)
            lx2,ly2=math.max(lx2,ox),math.max(ly2,oy)
          end
        end
      end

      -- Crop tightly around the actual silhouette inside this semantic zone.
      -- This makes a horn look like a horn instead of "random square of Rhyhorn."
      local tightX,tightY,tightW,tightH=rx,ry,rw,rh
      if count>0 and lx2>=lx and ly2>=ly then
        local pad=1
        tightX=clamp(rx+lx-pad,0,w-1)
        tightY=clamp(ry+ly-pad,0,h-1)
        local ex=clamp(rx+lx2+pad,0,w-1)
        local ey=clamp(ry+ly2+pad,0,h-1)
        tightW=math.max(1,ex-tightX+1)
        tightH=math.max(1,ey-tightY+1)
      end

      local tightArea=math.max(1,tightW*tightH)
      local density=count/tightArea
      local compact=count/math.max(1,rw*rh)
      local extremity=math.abs(slot.cx-.5)+math.abs(slot.cy-.5)
      local edgeBonus=slot.edge or 0
      local score=density*.55 + compact*.18 + extremity*.12 + edgeBonus
      if count < 3 then score=score*.15 end

      slots[#slots+1]={
        id=slot.id,x=tightX,y=tightY,w=tightW,h=tightH,
        density=density,score=score,
        cx=slot.cx,cy=slot.cy,count=count,
      }
    end
    table.sort(slots,function(a,b) return a.score>b.score end)
    local p={w=w,h=h,minx=minx,miny=miny,maxx=maxx,maxy=maxy,
      bw=bw,bh=bh,slots=slots}
    anatomyCache[species]=p
    return p
  end

  local function slotById(profile,id)
    if not profile then return nil end
    for _,s in ipairs(profile.slots or {}) do
      if s.id==id then return s end
    end
    return nil
  end

  local function makeAnatomicalFragment(data,hostSpecies,donorSpecies,force,
      donorScale)
    local dp=profileSprite(data,donorSpecies)
    local hp=profileSprite(data,hostSpecies)
    if not (dp and hp and #dp.slots>0) then return nil end

    -- Choose among genuinely occupied high-scoring extremity zones.
    local candidates={}
    for _,slot in ipairs(dp.slots) do
      if (slot.count or 0)>=3 then candidates[#candidates+1]=slot end
    end
    if #candidates==0 then candidates=dp.slots end

    local pick
    if force then
      pick=candidates[1]
    else
      local top=math.min(3,#candidates)
      pick=candidates[math.random(top)]
    end

    -- Put ears where the host has ear-space, feet where it has foot-space,
    -- etc. If the exact semantic slot is empty, use the nearest equivalent.
    local target=slotById(hp,pick.id)
    if not target or (target.count or 0)<2 then
      local group={
        TOP={"HEAD_L","HEAD_R","FACE"},
        HEAD_L={"TOP","FACE","HEAD_R"},
        HEAD_R={"TOP","FACE","HEAD_L"},
        FACE={"TOP","HEAD_L","HEAD_R"},
        SIDE_L={"SIDE_R","FOOT_L"},
        SIDE_R={"SIDE_L","FOOT_R"},
        FOOT_L={"FOOT_R","SIDE_L"},
        FOOT_R={"FOOT_L","SIDE_R"},
      }
      for _,alt in ipairs(group[pick.id] or {}) do
        local cand=slotById(hp,alt)
        if cand and (cand.count or 0)>=2 then target=cand break end
      end
    end
    target=target or hp.slots[1]
    if not target then return nil end

    return {
      species=donorSpecies, slot=pick.id, targetSlot=target.id,
      sx=pick.x,sy=pick.y,sw=pick.w,sh=pick.h,
      tx=target.x,ty=target.y,tw=target.w,th=target.h,
      donorW=dp.w,donorH=dp.h,hostW=hp.w,hostH=hp.h,
      donorScale=tonumber(donorScale) or 1,
    }
  end

  local function drawAnatomicalFragment(mon,data,palettes,
      hostX,hostY,hostScale,hostColors,back,donorColorsOverride)
    local f=mon and mon.cinnabarFusion
    local frag=f and f.fragment
    if not frag and f and f.fragmentSpecies and mon.species then
      frag=makeAnatomicalFragment(data,mon.species,f.fragmentSpecies,true,1)
      f.fragment=frag
    end
    if not frag then return end
    local donorSpecies=frag.species or f.fragmentSpecies
    local donor=fragmentImage(data,donorSpecies,back)
    if not donor then return end
    local dw,dh=donor:getDimensions()
    local sx,sy,sw,sh=frag.sx,frag.sy,frag.sw,frag.sh

    -- Back sprites do not share front-pic anatomy. Keep the same semantic
    -- mutation visible there using the corresponding normalized crop.
    if back and frag.donorW and frag.donorH then
      sx=math.floor((frag.sx/frag.donorW)*dw)
      sy=math.floor((frag.sy/frag.donorH)*dh)
      sw=math.max(4,math.floor((frag.sw/frag.donorW)*dw))
      sh=math.max(4,math.floor((frag.sh/frag.donorH)*dh))
    end
    sx=clamp(sx or 0,0,math.max(0,dw-1))
    sy=clamp(sy or 0,0,math.max(0,dh-1))
    sw=clamp(sw or 8,1,math.max(1,dw-sx))
    sh=clamp(sh or 8,1,math.max(1,dh-sy))
    local ok,quad=pcall(love.graphics.newQuad,sx,sy,sw,sh,dw,dh)
    if not ok or not quad then return end

    local hostW=(frag.hostW or 56)*hostScale
    local hostH=(frag.hostH or 56)*hostScale
    local nx=(frag.tx or 0)/(frag.hostW or 56)
    local ny=(frag.ty or 0)/(frag.hostH or 56)
    local nw=(frag.tw or 10)/(frag.hostW or 56)
    local nh=(frag.th or 10)/(frag.hostH or 56)
    local zoneX=hostX+nx*hostW
    local zoneY=hostY+ny*hostH
    local zoneW=math.max(6,nw*hostW)
    local zoneH=math.max(6,nh*hostH)

    -- Keep the donor feature's proportions instead of stretching a horn into
    -- a rectangle. Donor size mutations can influence the graft modestly.
    local donorInfluence=clamp(tonumber(frag.donorScale) or 1,.78,1.25)
    local fit=math.min(zoneW/sw,zoneH/sh)*donorInfluence
    local tw,th=sw*fit,sh*fit
    local tx=zoneX+(zoneW-tw)/2
    local ty=zoneY+(zoneH-th)/2

    -- Replace only the actual destination occupied area.
    local GbcPalette=require("src.render.GbcPalette")
    local blank=hostColors and GbcPalette.color(hostColors,1) or {255,255,255}
    love.graphics.setColor(blank[1]/255,blank[2]/255,blank[3]/255,1)
    love.graphics.rectangle("fill",zoneX,zoneY,zoneW,zoneH)

    -- Anatomical contamination is now recolored as part of the HOST's body.
    -- This also automatically respects Bill's PC orange preview palette.
    local colors=hostColors
    love.graphics.setColor(1,1,1,1)
    local function body()
      love.graphics.draw(donor,quad,tx,ty,0,fit,fit)
    end
    if colors and GbcPalette.available() then GbcPalette.with(colors,body)
    else body() end
    love.graphics.setColor(1,1,1,1)
  end


  -- Shared mutation-aware portrait API.
  -- Standard engine screens are hooked below. Custom mod screens can use this
  -- same renderer, and Cinnabar can adapt known bespoke screens from its side.
  local Visuals = {}
  Visuals.version = 3

  Visuals.hasMutation = function(mon)
    local f = mon and mon.cinnabarFusion
    return not not (f and (f.paletteOverride or f.paletteSpecies
      or f.spriteScale or f.fragment or f.fragmentSpecies))
  end

  Visuals.palette = function(mon, paletteData)
    return effectivePalette(mon, paletteData)
  end

  Visuals.scale = function(mon)
    return tonumber(mon and mon.cinnabarFusion
      and mon.cinnabarFusion.spriteScale) or 1
  end

  Visuals.fragment = function(mon)
    local f = mon and mon.cinnabarFusion
    return f and (f.fragment or f.fragmentSpecies) or nil
  end

  Visuals.drawIndividual = function(mon, data, palettes, x, y, opts)
    opts = opts or {}
    if not mon then return false end
    local image = opts.image or fragmentImage(data, mon.species, opts.back)
    if not image then return false end

    local G = love.graphics
    local mutationScale = Visuals.scale(mon)
    local baseScale = tonumber(opts.scale) or 1
    local scale = baseScale * mutationScale
    local w, h = image:getDimensions()
    local dx, dy = x or 0, y or 0

    if opts.centered then
      local bw = tonumber(opts.boxW) or w * baseScale
      local bh = tonumber(opts.boxH) or h * baseScale
      dx = dx + (bw - w * scale) / 2
      dy = dy + (bh - h * scale) / 2
    end

    local colors = opts.colors or effectivePalette(mon, palettes)
    G.setColor(1,1,1,1)
    local GbcPalette = require("src.render.GbcPalette")
    local function body()
      G.draw(image, dx, dy, 0, scale, scale)
    end
    if colors and GbcPalette.available() then
      GbcPalette.with(colors, body)
    else
      body()
    end

    local f = mon.cinnabarFusion
    if f and (f.fragment or f.fragmentSpecies) then
      drawAnatomicalFragment(mon, data, palettes, dx, dy, scale, colors,
        opts.back or false, opts.fragmentColors)
    end

    G.setColor(1,1,1,1)
    return true
  end

  Visuals.draw = Visuals.drawIndividual

  mod.exports.visualsVersion = Visuals.version
  mod.exports.hasMutation = Visuals.hasMutation
  mod.exports.palette = Visuals.palette
  -- Shared cross-mod contract: callers such as PokeSurvive, Angler's Cove and
  -- Safari Derby can ask Cinnabar first. An individual paletteOverride is the
  -- highest-priority visual palette whenever present.
  mod.exports.palettePriority = 1000
  mod.exports.hasIndividualPalette = function(mon)
    local f=mon and mon.cinnabarFusion
    return not not (f and f.paletteOverride)
  end
  mod.exports.effectiveIndividualPalette = Visuals.palette

  -- Stable cross-mod palette bridge. Cinnabar is the highest-priority visual
  -- authority for an INDIVIDUAL that carries paletteOverride. The game arg is
  -- accepted for compatibility with bespoke mod bridges but is not required.
  local function cinnabarPaletteForMon(game,mon)
    if not mon then return nil end
    local f=mon.cinnabarFusion
    if not (f and f.paletteOverride) then return nil end
    local paletteData=game and game.data and game.data.gen2Palettes
    return Visuals.palette(mon,paletteData)
  end
  mod.exports.paletteForMon=cinnabarPaletteForMon
  mod.exports.effectivePaletteForMon=cinnabarPaletteForMon
  mod.exports.paletteForPokemon=cinnabarPaletteForMon
  mod.exports.derby={
    paletteForMon=cinnabarPaletteForMon,
    effectivePaletteForMon=cinnabarPaletteForMon,
    palettePriority=1000,
  }
  mod.exports.anglers={
    paletteForMon=cinnabarPaletteForMon,
    effectivePaletteForMon=cinnabarPaletteForMon,
    palettePriority=1000,
  }

  mod.exports.scale = Visuals.scale
  mod.exports.fragment = Visuals.fragment
  mod.exports.drawIndividual = Visuals.drawIndividual
  mod.exports.draw = Visuals.drawIndividual
  Visuals.crySpecies = effectiveCrySpecies
  Visuals.playCry = playIndividualCry
  mod.exports.crySpecies = Visuals.crySpecies
  mod.exports.playCry = Visuals.playCry

  -- Gen2 evolution animation mutation adapter.
  -- The vanilla evolution movie loads species art directly, so persistent
  -- individual palette/size/fragment/cry mutations were invisible until the
  -- movie ended.  Keep the movie's blackout flashing, but render the actual
  -- mutated individual on both sides of the transformation.
  local Gen2EvolutionAnim=require("src.ui.gen2.EvolutionAnim")
  if not Gen2EvolutionAnim._cinnabarVisualWrapped then
    Gen2EvolutionAnim._cinnabarVisualWrapped=true

    local downstreamEvoDrawPic=Gen2EvolutionAnim.drawPic
    local downstreamEvoPlayCry=Gen2EvolutionAnim.playCry

    local function evolutionPreviewMon(self,species)
      local source=self and self.mon
      if not (source and source.cinnabarFusion) then return source end
      if species==source.species then return source end

      local preview={}
      for k,v in pairs(source) do preview[k]=v end
      preview.species=species
      preview.cinnabarFusion=deep(source.cinnabarFusion)

      local f=preview.cinnabarFusion
      if f.fragmentSpecies then
        local oldFrag=source.cinnabarFusion.fragment
        local donorScale=tonumber(oldFrag and oldFrag.donorScale) or 1
        f.fragment=makeAnatomicalFragment(
          self.data,species,f.fragmentSpecies,true,donorScale)
      end
      return preview
    end

    Gen2EvolutionAnim.drawPic=function(self)
      local source=self and self.mon
      local f=source and source.cinnabarFusion
      if not (f and Visuals.hasMutation(source)) then
        return downstreamEvoDrawPic(self)
      end

      local species=self.showNew and self.newSpecies or self.oldSpecies
      local mon=evolutionPreviewMon(self,species)
      if not mon then return downstreamEvoDrawPic(self) end

      local image=self:pic(species)
      if not image then return end

      -- Evolution's 7x7 front-pic box is at pixel (56,16), bottom aligned.
      -- During the flash retain the canonical blackout palette so the effect
      -- still reads like Crystal's evolution movie; only geometry/fragment
      -- mutations alter the silhouette.  On reveal, restore the individual's
      -- persistent palette.
      local box=56
      local colors
      if self.blackout then
        colors=self:picColors(species)
      else
        colors=effectivePalette(mon,self.palettes)
      end

      Visuals.drawIndividual(mon,self.data,self.palettes,56,16,{
        image=image,
        scale=1,
        centered=true,
        boxW=box,
        boxH=box,
        colors=colors,
      })
    end

    Gen2EvolutionAnim.playCry=function(self,species)
      local mon=self and self.mon
      if mon and cryMutation(mon) then
        return playIndividualCry(self.data,mon)
      end
      return downstreamEvoPlayCry(self,species)
    end
  end

  -- Compatibility fallback for older/custom screens.
  _G.CinnabarPokemonVisuals = Visuals

  -- Safari Derby bespoke winner-screen adapter.
  --
  -- This is deliberately guarded with pcall: a compatibility adapter must
  -- NEVER prevent the lab itself from loading if another mod changes.
  local function installSafariDerbyAdapter()
    local derby = mod.find("safari_derby_dev")
    if not derby then return false end

    local screen = mod.content.screens:get("SafariDerbyRace")
    if type(screen) ~= "table" or type(screen.new) ~= "function" then
      return false
    end

    local originalNew = screen.new
    local wrapped = {
      new = function(game, opts)
        local state = originalNew(game, opts)
        if type(state) ~= "table" then return state end

        -- Derby stores the player's actual registered slot in its own save.
        -- Resolve that same party individual before the race clears registration.
        local derbySave = game and game.save and game.save.modData
          and game.save.modData.safari_derby_dev
        local slot = derbySave and tonumber(derbySave.registered_slot)
        local party = game and game.save and game.save.party or {}
        local owned = slot and party[slot] or nil

        -- Fallback: Derby's state.player contains species/name.
        if not owned and state.player and state.player.player then
          for _, mon in ipairs(party) do
            if mon and mon.species == state.player.species then
              owned = mon
              break
            end
          end
        end
        state._cinnabarOwnedRacer = owned

        local originalDraw = state.draw
        if type(originalDraw) == "function" then
          state.draw = function(self, ...)
            local result = { originalDraw(self, ...) }

            if self.phase == "finish" and self.result and self.result.player then
              local mon = self._cinnabarOwnedRacer
              if mon and mon.species == self.result.species
                  and Visuals.hasMutation(mon) then
                local data = game and game.data or {}
                local def = data.pokemon and data.pokemon[mon.species]
                local path = def and def.spriteFront
                local image
                if path then
                  local ok, img = pcall(AssetsGlobal.image, path)
                  if ok then image = img end
                end

                if image then
                  -- Derby's winner art occupies the 52x52 interior of its frame.
                  love.graphics.setColor(1,1,1,.97)
                  love.graphics.rectangle("fill",54,25,52,52)

                  local iw, ih = image:getDimensions()
                  local baseScale = math.min(52/iw, 52/ih)
                  if baseScale > 1 then baseScale = math.floor(baseScale) end

                  Visuals.drawIndividual(mon, data, data.gen2Palettes,
                    54, 25, {
                      image = image,
                      scale = baseScale,
                      centered = true,
                      boxW = 52,
                      boxH = 52,
                    })
                end
              end
            end

            love.graphics.setColor(1,1,1,1)

            -- Recomp's current Lua sandbox is Lua 5.1/LuaJIT-style here:
            -- table.unpack is not guaranteed to exist. The wrapped Derby draw
            -- normally returns nil, but preserve its first return value without
            -- depending on table.unpack so this adapter cannot crash the game.
            return result[1]
          end
        end
        return state
      end,
    }

    mod.content.screens:override("SafariDerbyRace", wrapped)
    return true
  end

  local okDerby, derbyInstalled = pcall(installSafariDerbyAdapter)
  if not okDerby then
    mod.log:warn("Safari Derby visual adapter skipped safely: %s",
      tostring(derbyInstalled))
  elseif derbyInstalled then
    mod.log:info("Safari Derby mutation portrait adapter installed")
  end

  local SummaryMenuCry = require("src.ui.gen2.SummaryMenu")
  if not SummaryMenuCry._cinnabarCryWrapped then
    SummaryMenuCry._cinnabarCryWrapped = true
    local baseSummaryPlayCry = SummaryMenuCry.playCry
    SummaryMenuCry.playCry = function(self)
      local mon = self and self.mon
      if mon and cryMutation(mon) and not mon.isEgg then
        playIndividualCry(self.game and self.game.data, mon)
        if self.startPicAnim then self:startPicAnim() end
        return
      end
      return baseSummaryPlayCry(self)
    end
  end

  local BoxMenuCry = require("src.ui.gen2.BoxMenu")
  if not BoxMenuCry._cinnabarCryWrapped then
    BoxMenuCry._cinnabarCryWrapped = true
    local baseBoxPlayCry = BoxMenuCry.playMonCry
    BoxMenuCry.playMonCry = function(self, mon)
      if mon and cryMutation(mon) and not mon.isEgg then
        return playIndividualCry(self.game and self.game.data, mon)
      end
      return baseBoxPlayCry(self, mon)
    end
  end

  local BattleState = require("src.ui.gen2.BattleState")
  if not BattleState._cinnabarCryWrapped then
    BattleState._cinnabarCryWrapped = true
    local baseBattlePlayCry = BattleState.playCry
    BattleState.playCry = function(self, mon)
      if mon and cryMutation(mon) then
        return playIndividualCry(self.game and self.game.data, mon)
      end
      return baseBattlePlayCry(self, mon)
    end
  end

  local downstreamBattleDrawPic = BattleState.drawPic
  local function drawBattleFragment(self,mon,back)
    local f=mon and mon.cinnabarFusion
    if not (f and f.fragment) then return end
    local image=self:pic(mon,back)
    if not image then return end
    local w,h=image:getDimensions()
    local boxTiles=back and BattleState.PLAYER_PIC_TILES
      or BattleState.ENEMY_PIC_TILES
    local box=boxTiles*8
    local boxX=(back and BattleState.PLAYER_PIC_TILE_X
      or BattleState.ENEMY_PIC_TILE_X)*8
    local boxY=(back and BattleState.PLAYER_PIC_TILE_Y
      or BattleState.ENEMY_PIC_TILE_Y)*8
    local scale=tonumber(f.spriteScale) or 1
    local hostX=boxX+(box-w*scale)/2
    local hostY=boxY+(box-h*scale)
    local colors=self.palettes and effectivePalette(mon,self.palettes) or nil
    local data=self.data or (self.game and self.game.data) or {}
    drawAnatomicalFragment(mon,data,self.palettes,
      hostX,hostY,scale,colors,back)
  end

  BattleState.drawPic = function(self, mon, back)
    -- During BattleIntroSlidingPics the lower-left box contains the TRAINER,
    -- not the lead Pokemon.  The old adapter blindly drew the lead mon's donor
    -- fragment on top of that trainer art.
    if back and self.showPlayerTrainer then
      return downstreamBattleDrawPic(self, mon, back)
    end
    return withFusionPalette(mon, function()
      local out = downstreamBattleDrawPic(self, mon, back)
      drawBattleFragment(self, mon, back)
      return out
    end)
  end

  -- Chromatic instability can permanently alter the apparent size of
  -- the Host. BattleState already has a scale pipeline, so compose our
  -- individual-mon mutation with it instead of changing the species globally.
  local downstreamPicScale = BattleState.picScale
  BattleState.picScale = function(self, path, mon, back)
    local base = downstreamPicScale(self, path, mon, back)
    if back and self.showPlayerTrainer then return base end
    local f = mon and mon.cinnabarFusion
    local mutant = f and tonumber(f.spriteScale)
    if mutant then return base * mutant end
    return base
  end

  local SummaryMenu = require("src.ui.gen2.SummaryMenu")
  local GbcPaletteSummary = require("src.render.GbcPalette")
  local SUMMARY_PAD = { [7]={0,0}, [6]={1,1}, [5]={1,2} }

  -- Size fallout is part of the specimen, not just the fusion cutscene.
  -- Reflect it on the STATS/SUMMARY portrait as well as in battle.
  SummaryMenu.drawPic = function(self)
    local mon = self.mon
    local image = mon and self:picFor(mon)
    if not image then return end
    local colors = self.palettes and effectivePalette(mon, self.palettes) or nil
    local sheet, quad, animSize = self:picAnimFrame()
    local drawImage = sheet or image
    local sourceSize = animSize or image:getWidth()
    local wide = math.floor(sourceSize / 8)
    local pad = SUMMARY_PAD[wide] or SUMMARY_PAD[7]
    local scale = tonumber(mon and mon.cinnabarFusion
      and mon.cinnabarFusion.spriteScale) or 1
    local G = love.graphics

    local blank = colors and GbcPaletteSummary.color(colors, 1)
      or {255,255,255}
    G.setColor(blank[1]/255, blank[2]/255, blank[3]/255, 1)
    G.rectangle("fill", 0, 0, 56, 56)

    local baseX, baseY = pad[1]*8, pad[2]*8
    local w = sourceSize
    local h = sourceSize
    local x = baseX + (w - w*scale)/2
    local y = baseY + (h - h*scale)
    G.setColor(1,1,1,1)
    local function body()
      if quad then
        G.draw(drawImage, quad, x, y, 0, scale, scale)
      else
        G.draw(drawImage, x, y, 0, scale, scale)
      end
    end
    if colors and GbcPaletteSummary.available() then
      GbcPaletteSummary.with(colors, body)
    else
      body()
    end

    local f=mon and mon.cinnabarFusion
    if f and f.fragment then
      local data=(self.game and self.game.data) or {}
      drawAnatomicalFragment(mon,data,self.palettes,
        x,y,scale,colors,false)
    end
    G.setColor(1,1,1,1)
  end


  -- Bill's PC uses BoxMenu rather than SummaryMenu, so hook that shared engine
  -- surface too. Deposit/withdraw previews now retain individual lab mutations.
  local BoxMenu = require("src.ui.gen2.BoxMenu")
  local downstreamBoxDrawPic = BoxMenu.drawPic
  local downstreamBoxDrawPicBlock = BoxMenu.drawPicBlock
  BoxMenu.drawPic = function(self, mon)
    local oldBlock = self.drawPicBlock
    self.drawPicBlock = function(boxSelf, image, colors)
      local f = mon and mon.cinnabarFusion
      local scale = tonumber(f and f.spriteScale) or 1
      if scale == 1 and not (f and (f.fragment or f.fragmentSpecies)) then
        return downstreamBoxDrawPicBlock(boxSelf,image,colors)
      end
      if not image then return end
      local G = love.graphics
      boxSelf:fillPicBlock(colors)
      local w,h=image:getDimensions()
      local boxX,boxY=8,32 -- Bills PC PIC_X=1, PIC_Y=4
      local box=56
      local x=boxX+(box-w*scale)/2
      local y=boxY+(box-h*scale)/2
      G.setColor(1,1,1,1)
      local GbcPalette = require("src.render.GbcPalette")
      local function body() G.draw(image,x,y,0,scale,scale) end
      if colors and GbcPalette.available() then GbcPalette.with(colors,body)
      else body() end

      if f and f.fragment then
        local data=(boxSelf.game and boxSelf.game.data) or {}
        local browseOrange = nil
        if boxSelf.phase ~= "submenu" and boxSelf.phase ~= "insert" then
          browseOrange = colors
        end
        drawAnatomicalFragment(mon,data,boxSelf.palettes,
          x,y,scale,colors,false,browseOrange)
      end
      G.setColor(1,1,1,1)
    end

    local ok,a,b,c=pcall(function()
      return withFusionPalette(mon,function()
        return downstreamBoxDrawPic(self,mon)
      end)
    end)
    self.drawPicBlock=oldBlock
    if not ok then error(a) end
    return a,b,c
  end


  -- Fusion presentation screen: host and donor slide together slowly,
  -- pulse as silhouettes, then the HOST is revealed in the DONOR palette.
  -- The result remains visible until the player presses A.
  mod.content.screens:register("CinnabarFusionAnim", {
    new = function(game, opts)
      local Assets = require("src.render.Assets")
      local Chrome = require("src.ui.gen2.Chrome")
      local GbcPalette = require("src.render.GbcPalette")
      local Palettes2 = require("src.world.gen2.Palettes")

      local A = {}
      A.__index = A
      A.isOpaque = true

      local function pic(data, species)
        local def = data and data.pokemon and data.pokemon[species]
        if not (def and def.spriteFront) then return nil end
        local ok, im = pcall(Assets.image, def.spriteFront)
        return ok and im or nil
      end

      function A.new()
        return setmetatable({
          game=game, data=game.data, t=0,
          host=opts.host, donor=opts.donor,
          hostSpecies=opts.hostSpecies or opts.host.species,
          donorSpecies=opts.donorSpecies or opts.donor.species,
          resultSpecies=opts.resultSpecies or opts.host.species,
          resultLost=opts.resultLost==true,
          hostPaletteSpecies=opts.hostPaletteSpecies or opts.host.species,
          hostPaletteOverride=opts.hostPaletteOverride,
          donorPaletteSpecies=opts.donorPaletteSpecies or opts.donor.species,
          donorPaletteOverride=opts.donorPaletteOverride,
          resultPaletteSpecies=opts.resultPaletteSpecies
            or opts.donorPaletteSpecies or opts.donor.species,
          resultPaletteOverride=opts.resultPaletteOverride,
          hostScale=opts.hostScale or 1,
          donorScale=opts.donorScale or 1,
          hostFragment=opts.hostFragment,
          hostFragmentSpecies=opts.hostFragmentSpecies,
          donorFragment=opts.donorFragment,
          donorFragmentSpecies=opts.donorFragmentSpecies,
          resultScale=opts.resultScale or 1,
          resultCrySpecies=opts.resultCrySpecies or opts.host.species,
          resultCryPitch=opts.resultCryPitch or 1,
          fragmentSpecies=opts.fragmentSpecies,
          fragment=opts.fragment,
          onDone=opts.onDone,
          hostPic=pic(game.data, opts.hostSpecies or opts.host.species),
          donorPic=pic(game.data, opts.donorSpecies or opts.donor.species),
          resultPic=pic(game.data, opts.resultSpecies or opts.host.species),
          fragmentPic=opts.fragmentSpecies and pic(game.data, opts.fragmentSpecies) or nil,
          startedMusic=false,
          mergeSfx=false,
          revealSfx=false,
          revealFrames=0,
          result=false,
        }, A)
      end

      function A:wantsFillScale() return true end
      function A:drawsWidescreen() return true end

      local function drawMon(self, image, x, y, colors, scale)
        if not image then return end
        scale = tonumber(scale) or 1
        local w,h = image:getDimensions()
        local px,py = x-(w*scale)/2, y-(h*scale)

        love.graphics.setColor(1,1,1,1)
        local function body()
          love.graphics.draw(image, px, py, 0, scale, scale)
        end
        if colors and GbcPalette.available() then
          GbcPalette.with(colors, body)
        else
          body()
        end
        love.graphics.setColor(1,1,1,1)
      end

      local function drawSourceFragment(self,image,x,y,colors,scale,frag,fragSpecies)
        if not (image and frag) then return end
        local w,h=image:getDimensions()
        local px=x-(w*scale)/2
        local py=y-(h*scale)
        local fake={cinnabarFusion={
          fragment=frag, fragmentSpecies=fragSpecies, spriteScale=scale,
        }}
        drawAnatomicalFragment(fake,self.data,self.data.gen2Palettes,
          px,py,scale,colors,false)
      end

      local function finish(self)
        local cb = self.onDone
        self.onDone = nil
        if self.game and self.game.stack then self.game.stack:pop() end
        local world = self.game and self.game.world
        if world and world.playMapMusic then world:playMapMusic() end
        if cb then cb() end
      end

      function A:update(_dt)
        local input = self.game and self.game.input
        if not self.startedMusic then
          self.startedMusic = true
          local Music = require("src.core.Music")
          pcall(Music.play, self.data, "Music_Evolution", true,
            { reason="cinnabar_fusion" })
        end

        if not self.result then
          self.t = self.t + 1

          if self.t >= 118 and not self.mergeSfx then
            self.mergeSfx = true
            local Sound = require("src.core.Sound")
            pcall(Sound.play, self.data, "Sfx_MasterBall")
          end

          if self.t >= 222 then
            self.t = 222
            self.result = true
            if not self.revealSfx then
              self.revealSfx = true
              local Sound = require("src.core.Sound")
              pcall(Sound.play, self.data, "Sfx_GsIntroPokemonAppears")
              if self.resultLost then
                pcall(Sound.play, self.data, "Sfx_Strength")
              else
                local okCry, src = pcall(Sound.playCry, self.data,
                  self.resultCrySpecies)
                if okCry and src and self.resultCryPitch then
                  pcall(src.setPitch, src, self.resultCryPitch)
                end
              end
            end
          end
          return
        end

        self.revealFrames = self.revealFrames + 1
        -- Don't let the confirmation press that launched the scene skip the
        -- reveal. Give the player a short look, then require a fresh A press.
        if self.revealFrames > 18 and input and input:wasPressed("a") then
          finish(self)
        end
      end

      function A:drawPanel()
        Chrome.clear()
        local t = self.t

        local hostColors = self.hostPaletteOverride
          or Palettes2.monColors(self.data.gen2Palettes,
            self.hostPaletteSpecies, false)
        local donorColors = self.donorPaletteOverride
          or Palettes2.monColors(self.data.gen2Palettes,
            self.donorPaletteSpecies, false)

        if t < 112 then
          -- Slower approach than DEV33.
          local p = math.min(1, t / 92)
          local hx = 20 + (60-20)*p
          local dx = 140 - (60)*p
          drawMon(self,self.hostPic,hx,88,hostColors,self.hostScale)
          drawSourceFragment(self,self.hostPic,hx,88,hostColors,self.hostScale,
            self.hostFragment,self.hostFragmentSpecies)
          drawMon(self,self.donorPic,dx,88,donorColors,self.donorScale)
          drawSourceFragment(self,self.donorPic,dx,88,donorColors,self.donorScale,
            self.donorFragment,self.donorFragmentSpecies)

        elseif t < 222 then
          -- Evolution-style silhouette pulse. Both source portraits overlap.
          local pulse = (math.floor(t/7) % 2 == 0)
          local hostPal = pulse and Palettes2.BLACKOUT or hostColors
          local donorPal = pulse and Palettes2.BLACKOUT or donorColors
          drawMon(self,self.hostPic,80,88,hostPal,self.hostScale)
          drawSourceFragment(self,self.hostPic,80,88,hostPal,self.hostScale,
            self.hostFragment,self.hostFragmentSpecies)
          drawMon(self,self.donorPic,80,88,donorPal,self.donorScale)
          drawSourceFragment(self,self.donorPic,80,88,donorPal,self.donorScale,
            self.donorFragment,self.donorFragmentSpecies)

          love.graphics.setColor(0,0,0,1)
          for i=1,8 do
            local a = (t*0.12) + i*math.pi/4
            local r = 27 + ((t+i*3)%12)
            local x = 80 + math.cos(a)*r
            local y = 58 + math.sin(a)*r
            love.graphics.circle("fill", x, y, ((i+t)%2==0) and 2 or 1)
          end
          love.graphics.setColor(1,1,1,1)

        else
          -- Reveal ONLY the finished HOST, now wearing the DONOR palette.
          -- No blackout palette is used in this phase.
          local resultColors = self.resultPaletteOverride
            or Palettes2.monColors(self.data.gen2Palettes,
              self.resultPaletteSpecies, false) or donorColors

          -- Result uses the specimen's persistent scale too.
          if not self.resultLost then
            drawMon(self, self.resultPic or self.hostPic, 80, 88,
              resultColors, self.resultScale)
          end

          -- Severe chromatic fallout can leave a literal piece of the donor
          -- caught in the Host's rendered result. Only a small clipped region
          -- is shown; the mutation itself is recorded persistently.
          if self.fragment and not self.resultLost then
            local resultImage=self.resultPic or self.hostPic
            local rw,rh=resultImage:getDimensions()
            local rx=80-(rw*self.resultScale)/2
            local ry=88-(rh*self.resultScale)
            local fake={cinnabarFusion={
              fragment=self.fragment,
              fragmentSpecies=self.fragmentSpecies,
              spriteScale=self.resultScale,
            }}
            drawAnatomicalFragment(fake,self.data,self.data.gen2Palettes,
              rx,ry,self.resultScale,resultColors,false)
          end

          if self.revealFrames < 28 then
            love.graphics.setColor(0,0,0,1)
            for i=1,6 do
              local a = self.revealFrames*.18 + i
              love.graphics.circle("fill",
                80+math.cos(a)*34, 58+math.sin(a)*25, 2)
            end
            love.graphics.setColor(1,1,1,1)
          end
        end

        Chrome.box(0,12,20,6)
        if not self.result then
          Chrome.print("FUSION IN", 2,14)
          Chrome.print("PROGRESS...", 2,16)
        else
          if self.resultLost then
            Chrome.print("SPECIMEN LOST!", 2,14)
          else
            Chrome.print("SPLICE COMPLETE!", 2,14)
          end
          Chrome.print("A: CONTINUE", 2,16)
        end
      end

      function A:draw() self:drawPanel() end
      function A:drawWidescreen(w,h)
        local G=love.graphics
        Chrome.letterbox(w,h,1,1,1)
        local scale=Chrome.fitScale(w,h)
        local x,y=Chrome.fitOrigin(w,h,scale)
        G.push()
        G.translate(x,y)
        G.scale(scale,scale)
        self:drawPanel()
        G.pop()
      end

      return A.new()
    end,
  })

  -- Tier-up construction interstitial. The player has already confirmed
  -- and paid before this screen appears.
  mod.content.screens:register("CinnabarUpgradeAnim", {
    new=function(game,opts)
      local U={}
      U.__index=U
      U.isOpaque=true
      function U.new()
        return setmetatable({game=game,t=0,onDone=opts and opts.onDone,
          hit={}},U)
      end
      function U:wantsFillScale() return true end
      function U:drawsWidescreen() return true end
      local function sfx(self,name)
        local Sound=require("src.core.Sound")
        pcall(Sound.play,self.game.data,name)
      end
      function U:update(_dt)
        self.t=self.t+1
        local cues={
          {18,"Sfx_PokeballsPlacedOnTable"},
          {48,"Sfx_Strength"},
          {78,"Sfx_PokeballsPlacedOnTable"},
          {108,"Sfx_Cut"},
          {138,"Sfx_Strength"},
        }
        for _,c in ipairs(cues) do
          if self.t>=c[1] and not self.hit[c[1]] then
            self.hit[c[1]]=true
            sfx(self,c[2])
          end
        end
        if self.t>=170 then
          local cb=self.onDone
          self.onDone=nil
          if self.game and self.game.stack then self.game.stack:pop() end
          if cb then cb() end
        end
      end
      function U:draw()
        love.graphics.clear(0,0,0,1)
      end
      function U:drawWidescreen(w,h)
        love.graphics.clear(0,0,0,1)
      end
      return U.new()
    end,
  })

  -- Tier 5 Holon Collider activation spectacle.
  -- DEV101 preserves DEV99's existing matrix/title/crash presentation and
  -- deliberately stretches the pacing while making the audio increasingly
  -- ridiculous. Timing is elapsed seconds so GAME SPEED cannot rush it.
  mod.content.screens:register("CinnabarColliderAnim", {
    new=function(game,opts)
      local C={}
      C.__index=C
      C.isOpaque=true
      local PHASE={MATRIX=1,BLACK1=2,TITLE=3,CRASH=4,CRASH_DIALOG=5,BLACK2=6}

      local function loadColliderImage(name)
        local candidates={
          "mods/cinnabar_experimental_lab/assets/"..name,
          "cinnabar_experimental_lab/assets/"..name,
          "assets/"..name,
        }
        for _,p in ipairs(candidates) do
          local ok,img=pcall(love.graphics.newImage,p)
          if ok and img then
            img:setFilter("nearest","nearest")
            return img
          end
        end
      end

      function C.new()
        local self=setmetatable({
          game=game, phase=PHASE.MATRIX, elapsed=0, hit={},
          onDone=opts and opts.onDone,
          colliderTitle=loadColliderImage("collider_title.png"),
          colliderCrash=loadColliderImage("collider_crash.png"),
          dialogueStarted=false,
        },C)
        local Music=require("src.core.Music")
        pcall(Music.stop)
        return self
      end

      function C:wantsFillScale() return true end
      function C:drawsWidescreen() return true end

      local function sfx(self,name)
        local Sound=require("src.core.Sound")
        pcall(Sound.play,self.game.data,name)
      end
      local function stopMusic()
        local Music=require("src.core.Music")
        pcall(Music.stop)
        pcall(Music.setPitch,1)
      end
      local function titleMusic(self)
        local Music=require("src.core.Music")
        pcall(Music.stop)
        pcall(Music.play,self.game.data,"Music_TitleScreen",true,
          {reason="holon_collider"})
        pcall(Music.setPitch,0.58)
      end
      local function setPhase(self,p)
        self.phase=p
        self.elapsed=0
      end

      local function restoreLabMusic(self)
        local world=self.game and self.game.world
        if world and world.restoreMapMusic then
          pcall(function() world:restoreMapMusic() end)
        elseif world and world.refreshMusic then
          pcall(function() world:refreshMusic() end)
        elseif world and world.playMapMusic then
          pcall(function() world:playMapMusic() end)
        end
      end

      function C:finish()
        stopMusic()
        local cb=self.onDone
        self.onDone=nil
        if self.game and self.game.stack then self.game.stack:pop() end
        restoreLabMusic(self)
        if cb then cb() end
      end

      function C:startCrashDialogue()
        if self.dialogueStarted then return end
        self.dialogueStarted=true
        self.phase=PHASE.CRASH_DIALOG
        self.elapsed=0

        local world=self.game and self.game.world
        if not world then
          setPhase(self,PHASE.BLACK2)
          return
        end

        -- Make the real nearby scientist face the actual player before speaking.
        local npc=world.objectEntity and world:objectEntity(4)
        if npc and world.player then
          local dx=world.player.cellX-npc.cellX
          local dy=world.player.cellY-npc.cellY
          if math.abs(dx)>math.abs(dy) then
            npc.facing=dx>0 and "right" or "left"
          else
            npc.facing=dy>0 and "down" or "up"
          end
        end

        -- This is the REAL Gen2 map textbox. TextBox is non-opaque, so this
        -- Collider screen remains visible underneath it.
        world:showText("Huh. Well this turned\nout even worse than",function()
          world:showText("I anticipated.",function()
            stopMusic()
            setPhase(self,PHASE.BLACK2)
            sfx(self,"Sfx_Psychic")
          end)
        end)
      end

      function C:update(dt)
        dt=tonumber(dt) or (1/60)
        self.elapsed=self.elapsed+dt

        if self.phase==PHASE.MATRIX then
          local cues={
            {0.30,"Sfx_PokeballsPlacedOnTable"},
            {0.68,"Sfx_Strength"},
            {1.02,"Sfx_Psychic"},
            {1.34,"Sfx_Thunder"},
            {1.62,"Sfx_WarpTo"},
            {1.88,"Sfx_Strength"},
            {2.12,"Sfx_Psychic"},
            {2.34,"Sfx_Thunder"},
            {2.54,"Sfx_WarpTo"},
            {2.73,"Sfx_Strength"},
            {2.91,"Sfx_Thunder"},
            {3.10,"Sfx_Psychic"},
            {3.32,"Sfx_HyperBeam"},
          }
          for i,c in ipairs(cues) do
            if self.elapsed>=c[1] and not self.hit["m"..i] then
              self.hit["m"..i]=true
              sfx(self,c[2])
            end
          end
          if self.elapsed>=3.65 then setPhase(self,PHASE.BLACK1) end

        elseif self.phase==PHASE.BLACK1 then
          if self.elapsed>=2.0 then
            titleMusic(self)
            setPhase(self,PHASE.TITLE)
          end

        elseif self.phase==PHASE.TITLE then
          if self.elapsed>=2.20 then
            stopMusic()
            setPhase(self,PHASE.CRASH)
          end

        elseif self.phase==PHASE.CRASH then
          if self.elapsed>=1.15 then self:startCrashDialogue() end

        elseif self.phase==PHASE.CRASH_DIALOG then
          -- The real TextBox screens own input until their callbacks return.
          return

        elseif self.phase==PHASE.BLACK2 then
          local cues={
            {0.20,"Sfx_Strength"},
            {0.48,"Sfx_Thunder"},
            {0.76,"Sfx_WarpTo"},
            {1.02,"Sfx_Psychic"},
            {1.28,"Sfx_HyperBeam"},
          }
          for i,c in ipairs(cues) do
            if self.elapsed>=c[1] and not self.hit["b"..i] then
              self.hit["b"..i]=true
              sfx(self,c[2])
            end
          end
          if self.elapsed>=1.85 then self:finish() end
        end
      end

      -- Draw an uploaded screenshot without distortion.
      -- "contain" keeps every pixel visible; the exposed crash surround is
      -- exactly the sampled #1f1f1f instead of black.
      local function drawContained(img,bg)
        local G=love.graphics
        G.clear(bg[1],bg[2],bg[3],1)
        if not img then return end
        local iw,ih=img:getDimensions()
        local scale=math.min(160/iw,144/ih)
        local dw,dh=iw*scale,ih*scale
        local x=(160-dw)/2
        local y=(144-dh)/2
        G.setColor(1,1,1,1)
        G.draw(img,x,y,0,scale,scale)
      end

      -- Title should read as a screen takeover, not an inset. Use proportional
      -- cover scaling and crop only the outer edges if the aspect differs.
      local function drawCover(img,bg)
        local G=love.graphics
        G.clear(bg[1],bg[2],bg[3],1)
        if not img then return end
        local iw,ih=img:getDimensions()
        local scale=math.max(160/iw,144/ih)
        local dw,dh=iw*scale,ih*scale
        local x=(160-dw)/2
        local y=(144-dh)/2
        G.setColor(1,1,1,1)
        G.draw(img,x,y,0,scale,scale)
      end

      function C:drawRealActors()
        local world=self.game and self.game.world
        if not (world and world.drawPeople) then return end

        -- World:drawPeople uses the engine's actual Player/NPC sprite objects,
        -- palettes, facing, frames and camera. Filter all NPCs except the
        -- Collider specialist, while the player remains included automatically.
        local oldFilter=world.spriteFilter
        local scientist=world.objectEntity and world:objectEntity(4)
        world.spriteFilter=function(npc)
          return npc==scientist
        end
        local ok=pcall(function() world:drawPeople(1,nil) end)
        world.spriteFilter=oldFilter
        return ok
      end

      function C:drawPanel()
        local Chrome=require("src.ui.gen2.Chrome")
        local G=love.graphics

        if self.phase==PHASE.MATRIX then
          G.clear(1,1,1,1)
          local shake=(self.elapsed>1.25)
            and ((math.floor(self.elapsed*18)%2==0) and 2 or -2) or 0
          G.push()
          G.translate(shake,0)
          Chrome.print("HOLON COLLIDER",3,5)
          Chrome.print("FIELD MATRIX",4,8)
          Chrome.print("EXPANDING...",4,10)
          Chrome.print("LIMIT: ?????",4,13)
          G.pop()

        elseif self.phase==PHASE.BLACK1 or self.phase==PHASE.BLACK2 then
          G.clear(0,0,0,1)

        elseif self.phase==PHASE.TITLE then
          drawCover(self.colliderTitle,{0,0,0})

        elseif self.phase==PHASE.CRASH or self.phase==PHASE.CRASH_DIALOG then
          -- Full-screen user-supplied fake crash background.
          drawCover(self.colliderCrash,{31/255,31/255,31/255})
          self:drawRealActors()
        end

        G.setColor(1,1,1,1)
      end

      function C:draw() self:drawPanel() end
      function C:drawWidescreen(w,h)
        local Chrome=require("src.ui.gen2.Chrome")
        local G=love.graphics
        G.clear(0,0,0,1)
        local scale=Chrome.fitScale(w,h)
        local x,y=Chrome.fitOrigin(w,h,scale)
        G.push()
        G.translate(x,y)
        G.scale(scale,scale)
        self:drawPanel()
        G.pop()
      end

      return C.new()
    end,
  })

  -- First clone the intact Japanese Crystal maps, stripping all original
  -- mobile scripts/NPCs/events while preserving native blocks + tileset.
  local admin = mod.content.maps:get(ADMIN_TEMPLATE)
  local trade = mod.content.maps:get(TRADE_TEMPLATE)
  local battle = mod.content.maps:get(BATTLE_TEMPLATE)

  if not admin then mod.log("DEV7: missing "..ADMIN_TEMPLATE) end
  if not trade then mod.log("DEV7: missing "..TRADE_TEMPLATE) end
  if not battle then mod.log("DEV7: missing "..BATTLE_TEMPLATE) end

  -- Exterior cave must be patched after we know the custom lab map exists,
  -- but its destination can safely reference the custom ID before register.
  local cinn = mod.content.maps:get(CINNABAR)
  if cinn then
    local edited = deep(cinn)
    local bx, by = 4, 2
    local i = by * edited.width + bx + 1
    edited.blocks[i] = 0x70

    edited.warps = edited.warps or {}
    CAVE_WARP_INDEX = #edited.warps + 1
    edited.warps[CAVE_WARP_INDEX] = {
      x=CAVE_CELL_X, y=CAVE_CELL_Y,
      destMap=LAB_MAIN, destWarp=1,
    }
    mod.content.maps:override(CINNABAR, edited)
  else
    mod.log("DEV7: CINNABAR_ISLAND not available")
  end

  if admin then
    local d = deep(admin)
    d.id = LAB_MAIN
    d.label = "Mutant Monster Lab"
    d.index = 1110
    -- Crystal's map-name sign explicitly suppresses LANDMARK_SPECIAL.
    -- This prevents the cloned PokeCom floor from announcing GOLDENROD CITY.
    d.landmark = "LANDMARK_SPECIAL"

    -- Remove the two inherited visual trouble spots completely.
    -- Main map is 16 blocks wide.
    --   pink doorway: block (1,4) -> copy neighboring wall block (2,4)
    --   left stairs:  block (0,7) -> copy neighboring floor/edge block (1,7)

    -- Visual cleanup for Cinnabar conversion.
    -- Work only on the cloned LAB_MAIN copy; the source PokeCom map is untouched.

    -- Remove the inherited far-left stairs. This exact block replacement
    -- worked in the earlier build, so DEV21 reapplies only this known-good edit.
    if d.blocks then
      local function bi(x, y) return y * d.width + x + 1 end
      d.blocks[bi(0,7)] = d.blocks[bi(1,7)]
    end

    -- Remove original Mobile System behavior completely, then repopulate
    -- the converted Cinnabar lab with our own staff.
    --
    -- Diagnostic anchors supplied by the user:
    --   player (7,9),  facing (7,8)   -> scientist BEHIND desk at (7,7)
    --   player (16,9), facing (16,8)  -> scientist BEHIND desk at (16,7)
    --   player (26,12), facing (27,12) -> scientist at (27,12)
    --
    -- Gen II movement:
    --   6 = standing down
    --   8 = standing left
    d.objects = {
      {
        index=1,
        sprite="SPRITE_SCIENTIST",
        x=7, y=7,
        movement=6,
        radius={x=0,y=0},
        hours={-1,-1},
        palette=0, type=0, sight=0,
      },
      {
        index=2,
        sprite="SPRITE_SCIENTIST",
        x=16, y=8,
        movement=6,
        radius={x=0,y=0},
        hours={-1,-1},
        palette=0, type=0, sight=0,
      },
      {
        index=3,
        sprite="SPRITE_SCIENTIST",
        x=27, y=12,
        movement=8,
        radius={x=0,y=0},
        hours={-1,-1},
        palette=0, type=0, sight=0,
      },
      {
        index=4,
        sprite="SPRITE_GAMEBOY_KID",
        x=10, y=12,
        movement=6,
        radius={x=0,y=0},
        hours={-1,-1},
        palette=0, type=0, sight=0,
      },
      {
        index=5,
        sprite="SPRITE_SCIENTIST",
        x=4, y=27,
        movement=7,
        radius={x=0,y=0},
        hours={-1,-1},
        palette=0, type=0, sight=0,
      },
      {
        index=6,
        sprite="SPRITE_SCIENTIST",
        x=7, y=27,
        movement=7,
        radius={x=0,y=0},
        hours={-1,-1},
        palette=0, type=0, sight=0,
      },
      {
        index=7,
        sprite="SPRITE_SCIENTIST",
        x=7, y=29,
        movement=7,
        radius={x=0,y=0},
        hours={-1,-1},
        palette=0, type=0, sight=0,
      },
    }
    -- The pink door/computer annex stays locked until a later
    -- facility tier. Remove both ends of the temporary DEV pairing.
    for i = #d.warps, 1, -1 do
      local w = d.warps[i]
      if (w.x == PINK_DOOR_TILE_X and w.y == PINK_DOOR_TILE_Y)
          or (w.x == COMPUTER_ROOM_ENTRY_X and w.y == COMPUTER_ROOM_ENTRY_Y)
          or (w.x == COMPUTER_ROOM_ENTRY_X - 1
              and w.y == COMPUTER_ROOM_ENTRY_Y) then
        table.remove(d.warps, i)
      end
    end

    d.signs = {}

    -- Cinnabar Research Lab ambience.
    -- Ruins of Alph interior gives the rebuilt facility a strange,
    -- scientific/mysterious tone while staying entirely native to Crystal.
    d.music = 0xD5
    d.bgEvents = {}
    d.coordEvents = {}
    d.sceneScripts = {}
    d.callbacks = {}
    d.connections = {}

    -- The source admin office has two exits at (0,31) and (1,31).
    -- Both now return to our northern Cinnabar cave.
    d.warps = {
      -- Warp #1: Cinnabar cave arrival/return anchor.
      { x=MAIN_ENTRY_X, y=MAIN_ENTRY_Y,
        destMap=CINNABAR, destWarp=CAVE_WARP_INDEX },

      -- The source map's lower-left exit cells are no longer routed to
      -- Cinnabar. Keep them internal so the computer room cannot accidentally
      -- dump the player out of the cave.
      { x=0, y=31, destMap=LAB_MAIN, destWarp=4 },
      { x=1, y=31, destMap=LAB_MAIN, destWarp=4 },

      -- Warp #4: verified pink doorway on the main lab wall.
      { x=PINK_DOOR_TILE_X, y=PINK_DOOR_TILE_Y,
        destMap=LAB_MAIN, destWarp=5 },

      -- Warp #5: computer-room red-carpet arrival. The pink door lands here.
      -- Exiting south is handled by movement logic so standing on the carpet
      -- itself never auto-warps.
      { x=COMPUTER_ROOM_ENTRY_X, y=COMPUTER_ROOM_ENTRY_Y,
        destMap=LAB_MAIN, destWarp=4 },
    }
    mod.content.maps:register(LAB_MAIN, d)
  end

  if trade then
    local d = deep(trade)
    d.id = LAB_RESEARCH
    d.label = "Cinnabar Lab - Research Room"
    d.index = 1111
    d.landmark = "LANDMARK_SPECIAL"
    d.objects = {}
    d.signs = {}
    d.bgEvents = {}
    d.coordEvents = {}
    d.sceneScripts = {}
    d.callbacks = {}
    d.connections = {}
    -- Native mobile warps removed; DEV11 owns both directions explicitly.
    d.warps = {}
    mod.content.maps:register(LAB_RESEARCH, d)
  end

  if battle then
    local d = deep(battle)
    d.id = LAB_TEST
    d.label = "Cinnabar Lab - Testing Room"
    d.index = 1112
    d.landmark = "LANDMARK_SPECIAL"
    d.objects = {}
    d.signs = {}
    d.bgEvents = {}
    d.coordEvents = {}
    d.sceneScripts = {}
    d.callbacks = {}
    d.connections = {}
    -- Native mobile warps removed; DEV11 owns both directions explicitly.
    d.warps = {}
    mod.content.maps:register(LAB_TEST, d)
  end

  local function warp(map,x,y,facing)
    local ok,err = mod.world:warpTo(map,x,y,facing)
    if not ok then mod.log("Cinnabar Lab warp failed: "..tostring(err)) end
  end



  local showNatural
  local showStatChanges

  local function stabilityReport(value)
    value = tonumber(value) or 100
    if value >= 81 then return "HOLDING STEADY" end
    if value >= 61 then return "MINOR DRIFT" end
    if value >= 41 then return "UNSTABLE" end
    if value >= 21 then return "CRITICAL" end
    if value >= 1 then return "SEVERE ANOMALIES" end
    return "NO STABLE READING"
  end

  local function inspectFusion(world, mon)
    local game = world and world.game
    local f = fusionData(mon)
    local name = monName(game, mon)
    world:showText(name .. "\nFUSION REPORT", function()
      world:showText(stabilityReport(f.stability), function()
        if f.spliceCount <= 0 then
          world:showText("No splice history\nis recorded.")
        else
          local function finalAssessment()
            if f.stability >= 81 then
              showNatural(world,"Integration appears to be holding steady.")
            elseif f.stability >= 61 then
              showNatural(world,"I'm seeing signs of genetic drift.")
            elseif f.stability >= 41 then
              showNatural(world,"Another procedure would carry real risk.")
            else
              showNatural(world,"I would not splice this one again.")
            end
          end
          if f.lastStatChanges and #f.lastStatChanges>0 then
            showNatural(world,"Latest stat changes:",function()
              showStatChanges(world,f.lastStatChanges,finalAssessment)
            end)
          else
            finalAssessment()
          end
        end
      end)
    end)
  end

  local function faceNpcAt(world, x, y)
    if not (world and world.player) then return nil end
    for _, npc in ipairs(world.npcs or {}) do
      if npc.cellX == x and npc.cellY == y then
        local dx = world.player.cellX - npc.cellX
        local dy = world.player.cellY - npc.cellY
        if math.abs(dx) > math.abs(dy) then
          npc.facing = dx > 0 and "right" or "left"
        else
          npc.facing = dy > 0 and "down" or "up"
        end
        world.talkNpc = npc
        return npc
      end
    end
    return nil
  end

  local function showPages(world, pages, done, i)
    i = i or 1
    if i > #pages then
      if done then done() end
      return
    end
    world:showText(pages[i], function()
      showPages(world, pages, done, i + 1)
    end)
  end

  local function wrapTwoLines(text)
    -- Use the exact same pixel-aware wrapping routine as Gen1Recomp's
    -- dialogue box. This respects Crystal's variable-width glyphs.
    local TextBox = require("src.render.TextBox")
    local wrapped = TextBox.paginate(tostring(text), 18)
    local lines = wrapped[1] or {""}
    local pages = {}
    local i = 1
    while i <= #lines do
      local page = lines[i] or ""
      if lines[i + 1] then page = page .. "\n" .. lines[i + 1] end
      pages[#pages + 1] = page
      i = i + 2
    end
    return pages
  end

  showNatural = function(world, text, done)
    showPages(world, wrapTwoLines(text), done)
  end

  -- Native milestone/fanfare text. Unlike direct Sound.play calls, this uses
  -- the same TextBox sound command path as vanilla item/badge reward dialogue.
  -- The fanfare fires when the final page finishes typing and the textbox
  -- waits for it before accepting the player's confirmation.
  local function showNaturalFanfare(world,text,sound,done)
    local pages=wrapTwoLines(text)
    local game=world and world.game
    local TextBox=require("src.render.TextBox")
    local function page(i)
      if i>#pages then
        if done then done() end
        return
      end
      local opts=nil
      if i==#pages then opts=TextBox.soundOpts(game,sound or "Get_Item1") end
      game.stack:push(TextBox.new(game,pages[i],function()
        page(i+1)
      end,opts))
    end
    page(1)
  end

  local splicePickMode = nil
  local fusionBusy = false
  local generalMutationLine
  local cinnabarLevelCap

  local function labState(game)
    local save = game and game.save
    if not save then return { tier=1, experiments=0, intro=true } end
    save.cinnabarLab = save.cinnabarLab or {
      tier = 1, experiments = 0, introComplete = false,
    }
    local l = save.cinnabarLab
    l.tier = tonumber(l.tier) or 1
    l.experiments = tonumber(l.experiments) or 0
    l.tier2Funded = l.tier2Funded == true
    l.annexGiftClaimed = l.annexGiftClaimed == true
    l.statGiftClaimed = l.statGiftClaimed == true
    l.typeGiftClaimed = l.typeGiftClaimed == true
    l.typeSpliceCompleted = l.typeSpliceCompleted == true
    l.colliderIntroSeen = l.colliderIntroSeen == true
    l.colliderFired = l.colliderFired == true
    l.colliderChargeHours = math.max(0, tonumber(l.colliderChargeHours) or 0)
    l.colliderGeneration = math.max(0, tonumber(l.colliderGeneration) or 0)
    l.colliderEffects = type(l.colliderEffects)=="table" and l.colliderEffects or {}
    l.colliderSeed = tonumber(l.colliderSeed) or 0
    return l
  end

  -- Holon Collider field phenomena. Each firing replaces the WORLD field with
  -- three unique effects. Pokémon caught under a field are stamped with the
  -- effects that belong to the individual, so later firings do not erase them.
  local COLLIDER_EFFECTS={
    -- Weight 5: common-ish anomalies.
    {id="HOLON_TYPING",name="HOLON TYPING",weight=5},
    {id="CHROMATIC_FIELD",name="CHROMATIC FIELD",weight=5},
    {id="MOVE_COLLAPSE",name="MOVE COLLAPSE",weight=5},
    {id="STAT_DISTORTION",name="STAT DISTORTION",weight=5},
    {id="WILD_SHUFFLE",name="WILD SHUFFLE",weight=5},

    -- Weight 3: major but not catastrophic phenomena.
    {id="LIMIT_BREAK",name="LIMIT BREAK",weight=3},
    {id="EVOLUTION_CASCADE",name="EVOLUTION CASCADE",weight=3},
    {id="PRISMA",name="PRISMA",weight=3},
    {id="LEVEL_CASCADE",name="LEVEL CASCADE",weight=3},

    -- Weight 1: the dangerous stuff.
    {id="LOCKDOWN",name="LOCKDOWN",weight=1},
    {id="VOLATILE_ECOSYSTEM",name="VOLATILE ECOSYSTEM",weight=1},
  }
  local COLLIDER_NAMES={}
  for _,e in ipairs(COLLIDER_EFFECTS) do COLLIDER_NAMES[e.id]=e.name end

  local COLLIDER_TYPE_POOL={
    "NORMAL","FIGHTING","FLYING","POISON","GROUND","ROCK","BUG","GHOST",
    "STEEL","FIRE","WATER","GRASS","ELECTRIC","PSYCHIC_TYPE","ICE","DRAGON","DARK",
  }

  local function hasColliderEffect(game,id)
    local lab=labState(game)
    for _,v in ipairs(lab.colliderEffects or {}) do if v==id then return true end end
    return false
  end

  local function rollHolonTypes()
    local first=COLLIDER_TYPE_POOL[math.random(#COLLIDER_TYPE_POOL)]
    local out={first}
    -- Slightly under half become dual-type. Never duplicate the primary.
    if math.random(100)<=45 then
      local second=first
      while second==first do
        second=COLLIDER_TYPE_POOL[math.random(#COLLIDER_TYPE_POOL)]
      end
      out[2]=second
    end
    return out
  end

  local function chromaticChannel()
    -- GbcPalette consumes byte RGB values (0..255), matching the recomp's
    -- extracted Pokemon palette data. DEV112 accidentally supplied 0..1
    -- floats, which collapsed the body shades to near-black.
    return math.random(32,235)
  end

  local function rollChromaticPalette()
    local c1={chromaticChannel(),chromaticChannel(),chromaticChannel()}
    local c2={chromaticChannel(),chromaticChannel(),chromaticChannel()}
    -- Force useful separation between the two body shades.
    local tries=0
    local function dist(a,b)
      return math.abs(a[1]-b[1])+math.abs(a[2]-b[2])+math.abs(a[3]-b[3])
    end
    while dist(c1,c2)<120 and tries<12 do
      c2={chromaticChannel(),chromaticChannel(),chromaticChannel()}
      tries=tries+1
    end
    -- Preserve canonical white/black endpoints so outlines remain crisp.
    return {
      {255,255,255},
      c1,
      c2,
      {0,0,0},
    }
  end

  local function colliderMoveIds(data)
    local ids={}
    for id,def in pairs((data and data.moves) or {}) do
      if type(id)=="string" and type(def)=="table"
          and tonumber(def.pp) and tonumber(def.pp)>0
          and id~="STRUGGLE" then
        ids[#ids+1]=id
      end
    end
    table.sort(ids)
    return ids
  end

  local function rollMoveCollapseLearnset(game)
    local ids=colliderMoveIds(game and game.data)
    local out={}
    if #ids==0 then return out end

    -- One persistent alternate level-up biology for this individual.
    -- Early entries guarantee a newly caught low-level mon is usable; later
    -- entries continue all the way through vanilla level 100.
    local levels={1,1,5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90,95,100}
    local used={}
    for _,level in ipairs(levels) do
      local id
      local tries=0
      repeat
        id=ids[math.random(#ids)]
        tries=tries+1
      until not used[id] or tries>40
      if id then
        used[id]=true
        out[#out+1]={level=level,move=id}
      end
    end
    return out
  end

  local function movesFromCollapsedLearnset(game,learnset,level)
    local known={}
    local seen={}
    for _,entry in ipairs(learnset or {}) do
      if (tonumber(entry.level) or 1)<=level and entry.move and not seen[entry.move] then
        seen[entry.move]=true
        known[#known+1]=entry.move
        if #known>4 then table.remove(known,1) end
      end
    end
    local out={}
    for _,id in ipairs(known) do
      local def=game.data and game.data.moves and game.data.moves[id]
      out[#out+1]={
        id=id,
        pp=tonumber(def and def.pp) or 0,
        maxPp=tonumber(def and def.pp) or 0,
      }
    end
    return out
  end

  local function collapsedMovesAtLevel(mon,level)
    local c=mon and mon.cinnabarCollider
    if not (c and c.moveCollapse and type(c.moveLearnset)=="table") then
      return {}
    end
    local out={}
    for _,entry in ipairs(c.moveLearnset) do
      if tonumber(entry.level)==tonumber(level) and entry.move then
        out[#out+1]=entry.move
      end
    end
    return out
  end

  local function rollStatDistortion(game,mon)
    local def=game and game.data and game.data.pokemon
      and mon and game.data.pokemon[mon.species]
    local base=def and def.baseStats
    if not base then return nil end

    -- Preserve the species' original BST while redistributing it wildly.
    -- Gen2 uses the five-stat model: hp/attack/defense/speed/special.
    local keys={"hp","attack","defense","speed","special"}
    local total=0
    for _,k in ipairs(keys) do total=total+(tonumber(base[k]) or 1) end
    if total<#keys then return nil end

    local values={}
    local remaining=total
    for i,k in ipairs(keys) do
      local slots=#keys-i
      if slots==0 then
        values[k]=remaining
      else
        -- Keep every base stat legal (1..255) while guaranteeing enough
        -- budget remains for all later slots.
        local minHere=math.max(1,remaining-(slots*255))
        local maxHere=math.min(255,remaining-slots)
        local v=math.random(minHere,maxHere)
        values[k]=v
        remaining=remaining-v
      end
    end

    -- Shuffle the generated distribution once more so the sequential budget
    -- construction does not bias a particular named stat.
    local nums={}
    for _,k in ipairs(keys) do nums[#nums+1]=values[k] end
    for i=#nums,2,-1 do
      local j=math.random(i)
      nums[i],nums[j]=nums[j],nums[i]
    end
    for i,k in ipairs(keys) do values[k]=nums[i] end
    return values,total
  end

  local function stampStatDistortion(game,mon)
    if not (game and mon) then return end
    local profile,total=rollStatDistortion(game,mon)
    if not profile then return end

    mon.cinnabarCollider=mon.cinnabarCollider or {}
    local c=mon.cinnabarCollider
    c.statDistortion=true
    c.statProfile=profile
    c.statBudget=total
    c.generation=labState(game).colliderGeneration

    -- Reuse the mature Cinnabar individual-stat override path so every
    -- summary/battle/PC/stat-refresh surface sees the same physiology.
    mon.cinnabarFusion=mon.cinnabarFusion or {}
    mon.cinnabarFusion.statOverrides={}
    for k,v in pairs(profile) do
      mon.cinnabarFusion.statOverrides[k]=v
    end
    -- This helper is defined earlier than the shared Gen2Mon local binding,
    -- so resolve the module here instead of indexing a not-yet-in-scope global.
    local Mon=require("src.battle.gen2.Mon")
    Mon.refreshStats(mon,game.data)
  end

  local function stampEvolutionCascade(game,mon)
    if not (game and mon) then return end
    mon.cinnabarCollider=mon.cinnabarCollider or {}
    local c=mon.cinnabarCollider
    c.evolutionCascade=true
    c.cascadeSeed=tonumber(c.cascadeSeed) or math.random(1,2147483646)
    -- Catching one must NOT immediately transform it at its current level.
    -- The first mutation is armed only after it gains another level.
    c.cascadeLastLevel=tonumber(mon.level) or 1
    c.cascadeHistory=type(c.cascadeHistory)=="table" and c.cascadeHistory or {}
    c.generation=labState(game).colliderGeneration
  end

  local function stampLimitBreak(game,mon)
    if not (game and mon) then return end
    mon.cinnabarCollider=mon.cinnabarCollider or {}
    local c=mon.cinnabarCollider
    c.limitBreak=true
    c.levelCap=255
    c.generation=labState(game).colliderGeneration
  end

  local function stampVolatileEcosystem(game,mon)
    if not (game and mon) then return end
    mon.moves=mon.moves or {}

    local explosionDef=game.data and game.data.moves
      and game.data.moves.EXPLOSION
    local pp=tonumber(explosionDef and explosionDef.pp) or 5

    -- If EXPLOSION is already present, just normalize its PP and keep the
    -- existing slot. Otherwise replace one slot at random when full, or append
    -- it when the Pokemon has fewer than four moves.
    local slot
    for i,m in ipairs(mon.moves) do
      if m and m.id=="EXPLOSION" then slot=i break end
    end
    if not slot then
      if #mon.moves<4 then slot=#mon.moves+1
      else slot=math.random(1,4) end
    end
    mon.moves[slot]={id="EXPLOSION",pp=pp,maxPp=pp}

    mon.cinnabarCollider=mon.cinnabarCollider or {}
    local c=mon.cinnabarCollider
    c.volatileEcosystem=true
    c.explosionSlot=slot
    c.generation=labState(game).colliderGeneration
  end

  local function stampMoveCollapse(game,mon)
    if not (game and mon) then return end
    local learnset=rollMoveCollapseLearnset(game)
    if #learnset==0 then return end

    mon.cinnabarCollider=mon.cinnabarCollider or {}
    local c=mon.cinnabarCollider
    c.moveCollapse=true
    c.moveLearnset={}
    for i,e in ipairs(learnset) do
      c.moveLearnset[i]={level=e.level,move=e.move}
    end
    c.generation=labState(game).colliderGeneration

    -- Current moves are derived from the individual's alternate learnset,
    -- exactly like a normal species derives its four current moves.
    mon.moves=movesFromCollapsedLearnset(game,learnset,tonumber(mon.level) or 1)
  end

  local function stampChromaticField(game,mon)
    if not (game and mon) then return end
    local palette=rollChromaticPalette()
    local f=fusionData(mon)
    f.paletteOverride={}
    for i,row in ipairs(palette) do
      f.paletteOverride[i]={row[1],row[2],row[3]}
    end
    mon.cinnabarCollider=mon.cinnabarCollider or {}
    mon.cinnabarCollider.chromaticField=true
    mon.cinnabarCollider.chromaticPalette={}
    for i,row in ipairs(palette) do
      mon.cinnabarCollider.chromaticPalette[i]={row[1],row[2],row[3]}
    end
    mon.cinnabarCollider.generation=labState(game).colliderGeneration
  end

  local function stampHolonTyping(game,mon)
    if not (game and mon) then return end
    local types=rollHolonTypes()
    local f=fusionData(mon)
    f.typeOverride={}
    mon.types={}
    for i,t in ipairs(types) do
      f.typeOverride[i]=t
      mon.types[i]=t
    end
    mon.cinnabarCollider=mon.cinnabarCollider or {}
    mon.cinnabarCollider.holonTyping=true
    mon.cinnabarCollider.holonTypes={}
    for i,t in ipairs(types) do mon.cinnabarCollider.holonTypes[i]=t end
    mon.cinnabarCollider.generation=labState(game).colliderGeneration
  end

  local function rollColliderEffects(game)
    -- Weighted draw WITHOUT replacement: exactly three unique phenomena.
    -- Removing the selected entry after each draw keeps duplicates impossible
    -- while preserving the 5 / 3 / 1 rarity bands.
    local pool={}
    local seen={}
    for _,e in ipairs(COLLIDER_EFFECTS) do
      if e.id and not seen[e.id] then
        seen[e.id]=true
        pool[#pool+1]={
          id=e.id,
          weight=math.max(1,tonumber(e.weight) or 1),
        }
      end
    end
    if #pool<3 then return {} end

    local chosen={}
    for pick=1,3 do
      local total=0
      for _,e in ipairs(pool) do total=total+e.weight end
      local roll=math.random()*total
      local running=0
      local selectedIndex=#pool
      for i,e in ipairs(pool) do
        running=running+e.weight
        if roll<=running then selectedIndex=i break end
      end
      chosen[#chosen+1]=pool[selectedIndex].id
      table.remove(pool,selectedIndex)
    end

    local lab=labState(game)
    lab.colliderGeneration=(lab.colliderGeneration or 0)+1
    lab.colliderSeed=math.random(1,2147483646)
    lab.colliderEffects={chosen[1],chosen[2],chosen[3]}

    lab.colliderLastRoll={
      generation=lab.colliderGeneration,
      seed=lab.colliderSeed,
      effects={chosen[1],chosen[2],chosen[3]},
    }
    lab.colliderRollHistory=type(lab.colliderRollHistory)=="table"
      and lab.colliderRollHistory or {}
    lab.colliderRollHistory[#lab.colliderRollHistory+1]=deep(lab.colliderLastRoll)
    while #lab.colliderRollHistory>8 do table.remove(lab.colliderRollHistory,1) end

    return lab.colliderEffects
  end

  local function colliderSpeciesIds(data)
    local ids={}
    local pokemon=data and data.pokemon or {}
    for id,def in pairs(pokemon) do
      if type(id)=="string" and type(def)=="table"
          and def.name and def.spriteFront then
        ids[#ids+1]=id
      end
    end
    table.sort(ids)
    return ids
  end

  local function colliderHash(text,seed)
    -- Simple deterministic 31-bit hash, intentionally local to this mod.
    local h=(tonumber(seed) or 1)%2147483647
    for i=1,#text do
      h=(h*1103515245 + text:byte(i)*12345 + 1013904223)%2147483647
    end
    return h
  end

  local function shuffledWildSpecies(game,original,ctx)
    local lab=labState(game)
    local ids=colliderSpeciesIds(game and game.data)
    if #ids==0 then return original end
    local key=table.concat({
      tostring(original or "?"),
      tostring(ctx and ctx.mapId or "?"),
      tostring(ctx and ctx.terrain or "?"),
      tostring(ctx and ctx.kind or "?"),
    },"|")
    local idx=(colliderHash(key,lab.colliderSeed)%#ids)+1
    return ids[idx] or original
  end

  local function colliderSummary(game)
    local out={}
    for _,id in ipairs(labState(game).colliderEffects or {}) do
      out[#out+1]=COLLIDER_NAMES[id] or id
    end
    return out
  end

  local function randomPaletteSpecies(game, avoidA, avoidB)
    local pokemon=game and game.data and game.data.pokemon or {}
    local ids={}
    for id,def in pairs(pokemon) do
      -- Current Gen1Recomp Pokémon tables are keyed by canonical species ids
      -- such as "PIKACHU" / "RHYHORN", not numeric Pokédex numbers.
      if type(id)=="string" and def and def.name
          and id~=avoidA and id~=avoidB then
        ids[#ids+1]=id
      end
    end
    if #ids==0 then return nil end
    return ids[math.random(#ids)]
  end

  local function funkyPalette(base)
    base = copyPalette(base) or {
      {255,255,255},{255,96,192},{64,224,224},{0,0,0}
    }
    local a = base[2] or {200,120,80}
    local b = base[3] or {80,80,80}
    local mode = math.random(4)
    local c2,c3
    if mode == 1 then
      c2={255-(a[1] or 0),255-(a[2] or 0),255-(a[3] or 0)}
      c3={b[2] or 0,255-(b[3] or 0),b[1] or 0}
    elseif mode == 2 then
      c2={a[2] or 0,a[3] or 0,a[1] or 0}
      c3={b[3] or 0,b[1] or 0,b[2] or 0}
    elseif mode == 3 then
      c2={255,math.floor((a[1] or 0)*.35),math.floor((a[3] or 0)*.75)}
      c3={math.floor((b[1] or 0)*.35),255,math.floor((b[2] or 0)*.55)}
    else
      c2={math.min(255,(a[1] or 0)+90),math.floor((a[2] or 0)*.35),255}
      c3={255,math.min(255,(b[2] or 0)+70),math.floor((b[3] or 0)*.25)}
    end
    local function cap(c)
      return {math.max(24,math.min(255,c[1] or 0)),
        math.max(24,math.min(255,c[2] or 0)),
        math.max(24,math.min(255,c[3] or 0))}
    end
    return {
      copyPalette(base)[1] or {255,255,255},
      cap(c2), cap(c3),
      copyPalette(base)[4] or {0,0,0},
    }
  end

  local function chromaticFallout(game, host, donor, donorSpecies, donorPaletteOverride)
    local f = fusionData(host)
    local result = {
      kind = "NONE",
      paletteSpecies = donorSpecies,
      paletteOverride = copyPalette(donorPaletteOverride),
      scale = tonumber(f.spriteScale) or 1,
      fragmentSpecies = f.fragmentSpecies,
      fragment = f.fragment,
      cryMutation = f.cryMutation and deep(f.cryMutation) or nil,
    }

    local dev = game and game.save and game.save.cinnabarDev
    local force = (dev and dev.forceFallout) or mod.options:get("dev_fallout")
    if not force and math.random() >= falloutChance(f.stability) then
      return result
    end

    local severity = falloutSeverity(f.stability)
    if force and severity < 3 then severity = 3 end
    local pool = {"WRONG_PALETTE"}
    if severity >= 2 then
      pool[#pool+1] = "SIZE"
      pool[#pool+1] = "CRY"
    end
    if severity >= 3 then pool[#pool+1] = "DONOR_FRAGMENT" end
    if severity >= 4 then
      pool[#pool+1] = "SIZE"
      pool[#pool+1] = "DONOR_FRAGMENT"
      pool[#pool+1] = "CRY"
    end

    if force then
      local save = game and game.save
      save.cinnabarDev = save.cinnabarDev or {}
      local testIndex = (tonumber(save.cinnabarDev.falloutTestIndex) or 0) + 1
      if testIndex > 4 then testIndex = 1 end
      save.cinnabarDev.falloutTestIndex = testIndex
      result.kind = ({"WRONG_PALETTE","SIZE","DONOR_FRAGMENT","CRY"})[testIndex]
    else
      result.kind = pool[math.random(#pool)]
    end

    if result.kind == "WRONG_PALETTE" then
      local base = donorPaletteOverride
        or Palettes.monColors(game.data.gen2Palettes, donorSpecies, false)
      result.paletteOverride = funkyPalette(base)
      result.paletteSpecies = nil
      f.paletteSpecies = nil
      f.paletteOverride = copyPalette(result.paletteOverride)
      f.anomalies[#f.anomalies+1] = {
        procedure="CHROMATIC", kind="WRONG_PALETTE",
        paletteOverride=copyPalette(result.paletteOverride),
      }
    elseif result.kind == "SIZE" then
      if force then
        local save = game and game.save
        save.cinnabarDev = save.cinnabarDev or {}
        save.cinnabarDev.sizeGrowNext = not save.cinnabarDev.sizeGrowNext
        result.scale = save.cinnabarDev.sizeGrowNext and 1.30 or 0.72
      else
        local scales = severity >= 3
          and {0.62,0.72,0.82,0.90,1.10,1.18,1.30,1.42}
          or {0.82,0.90,1.10,1.18}
        result.scale = scales[math.random(#scales)]
      end
      f.spriteScale = result.scale
      f.anomalies[#f.anomalies+1] = {
        procedure="CHROMATIC", kind="SIZE", scale=result.scale,
      }
    elseif result.kind == "DONOR_FRAGMENT" then
      local donorFusion=donor and donor.cinnabarFusion
      local donorScale=tonumber(donorFusion and donorFusion.spriteScale) or 1
      local frag=makeAnatomicalFragment(game.data,host.species,donorSpecies,
        force,donorScale)
      result.fragmentSpecies=donorSpecies
      result.fragment=frag
      f.fragmentSpecies=donorSpecies
      f.fragment=frag
      f.anomalies[#f.anomalies+1] = {
        procedure="CHROMATIC", kind="DONOR_FRAGMENT",
        species=donorSpecies, fragment=deep(frag),
        sourceSlot=frag and frag.slot, targetSlot=frag and frag.targetSlot,
      }
    elseif result.kind == "CRY" then
      local save = game and game.save
      save.cinnabarDev = save.cinnabarDev or {}
      local variant
      if force then
        local n = (tonumber(save.cinnabarDev.cryTestIndex) or 0) + 1
        if n > 3 then n = 1 end
        save.cinnabarDev.cryTestIndex = n
        variant = ({"DONOR","RANDOM","PITCH"})[n]
      else
        local choices = {"DONOR","RANDOM","PITCH"}
        variant = choices[math.random(#choices)]
      end

      local crySpecies = host.species
      local cryPitch = 1
      if variant == "DONOR" then
        crySpecies = donorSpecies
      elseif variant == "RANDOM" then
        crySpecies = randomPaletteSpecies(game, host.species, donorSpecies)
          or donorSpecies
      else
        local pitches = {0.62,0.76,1.28,1.48}
        cryPitch = pitches[math.random(#pitches)]
      end

      f.cryMutation = {
        kind=variant, species=crySpecies, pitch=cryPitch,
      }
      result.cryMutation = deep(f.cryMutation)
      f.anomalies[#f.anomalies+1] = {
        procedure="CHROMATIC", kind="CRY",
        variant=variant, species=crySpecies, pitch=cryPitch,
      }
    end

    return result
  end

  local function chromaticFalloutText(world, fallout, done)
    if not fallout or fallout.kind == "NONE" then
      if done then done() end
      return
    end
    if fallout.kind == "WRONG_PALETTE" then
      showNatural(world,
        "That's not the color profile I programmed. The splice drifted during transfer.",
        done)
    elseif fallout.kind == "SIZE" then
      showNatural(world,
        "Its proportions changed. That was definitely not part of the procedure.",
        done)
    elseif fallout.kind == "DONOR_FRAGMENT" then
      showNatural(world,
        "Wait. Some of the DONOR's structure came through with the pigment. That's new.",
        done)
    elseif fallout.kind == "CRY" then
      showNatural(world,
        "Its vocal pattern changed during the splice. That definitely wasn't requested.",
        done)
    elseif done then
      done()
    end
  end

  local function pickForSplice(world, prompt, onPicked)
    local game = world and world.game
    local save = game and game.save
    local party = save and save.party or {}
    if not (game and game.stack and #party > 0) then
      if onPicked then onPicked(nil, nil) end
      return false
    end

    local Screens = require("src.ui.Screens")
    splicePickMode = { onPicked=onPicked }

    local finished = false
    local function finish(index, mon)
      if finished then return end
      finished = true
      splicePickMode = nil
      if index and mon and world and world.playSfxNamed then
        world:playSfxNamed("Sfx_ReadText2")
      end
      if game.stack then game.stack:pop() end
      if onPicked then onPicked(index, mon) end
    end

    Screens.push(game, "Gen2PartyMenu", {
      save = save,
      party = party,
      prompt = prompt or "Choose a POKéMON.",
      submenu = true,
      onChoose = function(index, mon) finish(index, mon) end,
      onCancel = function() finish(nil, nil) end,
    })
    return true
  end

  -- A tiny movement-script helper. Object 0 is the player; extracted scientist
  -- #2 is script object id 3 (object ids are extracted index + 1).
  local function moveObj(world, objectId, bytes, done)
    world:beginMovement(objectId, bytes, done)
  end

  local STEP_DOWN, STEP_UP, STEP_LEFT, STEP_RIGHT, TURN_UP, TURN_DOWN, END =
    0x0c, 0x0d, 0x0e, 0x0f, 0x01, 0x00, 0x47

  local function runFusionProcedure(world, host, donor, finishMutation)
    -- Middle scientist is interaction-locked for the entire machine sequence.
    moveObj(world, 3, {STEP_UP, TURN_UP, END}, function()
      world:playSfxNamed("Sfx_PokeballsPlacedOnTable")
      world:playSfxNamed("Sfx_PokeballsPlacedOnTable")

      moveObj(world, 3, {STEP_RIGHT, TURN_UP, END}, function()
        showNatural(world, "All set. Beginning the splice now.", function()
          finishMutation(function()
            moveObj(world, 3, {STEP_LEFT, STEP_LEFT, TURN_UP, END}, function()
              world:playSfxNamed("Sfx_PokeballsPlacedOnTable")
              moveObj(world, 3, {STEP_RIGHT, STEP_DOWN, TURN_DOWN, END}, function()
                faceNpcAt(world, 16, 8)
                local f = fusionData(host)
                local fallout = world.cinnabarLastFallout
                world.cinnabarLastFallout = nil
                local line
                if fallout == "CATA_DITTO" then
                  line = "The structure collapsed, but it stabilized as a DITTO."
                elseif fallout == "CATA_GLITCH" then
                  line = "It survived, but nearly every reading changed at once."
                elseif fallout == "CATA_LOSS" then
                  line = "I... don't have anything to give back to you."
                elseif fallout == "STAT_WRONG_STAT" then
                  line = "The stat transfer drifted. A different trait took hold."
                elseif fallout == "STAT_TRADEOFF" then
                  line = "The target improved, but another stat deteriorated."
                elseif fallout == "STAT_SWAP" then
                  line = "Two stat profiles inverted during the transfer."
                elseif fallout == "STAT_OVERCHARGE" then
                  line = "That stat overshot our safe projections by a lot."
                elseif fallout == "STAT_SCRAMBLE" then
                  line = "Multiple stat readings changed. The profile destabilized."
                elseif fallout == "MOVE_WRONG_MOVE" then
                  line = "The move channel drifted. That is not the move we isolated."
                elseif fallout == "MOVE_ZERO_PP" then
                  line = "The move is present, but it has no usable energy at all."
                elseif fallout == "MOVE_LOW_PP" then
                  line = "The move took, but its usable energy is badly reduced."
                elseif fallout == "WRONG_PALETTE" then
                  line = "That color profile drifted badly. It isn't what I programmed."
                elseif fallout == "SIZE" then
                  line = "Its body size changed during transfer. That wasn't intentional."
                elseif fallout == "DONOR_FRAGMENT" then
                  line = "Part of the DONOR's anatomy replaced its own. I've never seen that before."
                elseif fallout == "CRY" then
                  line = "That cry is wrong. The splice altered its vocal pattern too."
                elseif f.stability >= 81 then
                  line = "There we are. The splice held well."
                elseif f.stability >= 61 then
                  line = "It worked. I did notice some minor drift."
                elseif f.stability >= 41 then
                  line = "It worked, but the readings are odd."
                else
                  line = "It worked... but those readings worry me."
                end
                showNatural(world, line, function()
                  local gm=world.cinnabarGeneralMutation
                  world.cinnabarGeneralMutation=nil
                  local extra=generalMutationLine(gm)
                  if extra then
                    showNatural(world,extra,function() fusionBusy=false end)
                  else
                    fusionBusy=false
                  end
                end)
              end)
            end)
          end)
        end)
      end)
    end)
  end

  local chooseScriptMenu

  local STAT_PRICE = 7500
  local STAT_KEYS={"hp","attack","defense","speed","specialAttack","specialDefense"}
  local STAT_LABELS={"HP","ATTACK","DEFENSE","SPEED","SP. ATK","SP. DEF","CANCEL"}
  local STAT_DISPLAY={
    hp="HP",attack="ATTACK",defense="DEFENSE",speed="SPEED",
    specialAttack="SP. ATK",specialDefense="SP. DEF",
  }

  local function captureDisplayedStats(mon)
    local out={}
    for _,k in ipairs(STAT_KEYS) do
      local v=mon and mon.stats and mon.stats[k]
      if type(v)=="number" then out[k]=v end
    end
    return out
  end

  local function diffDisplayedStats(before,mon)
    local out={}
    for _,k in ipairs(STAT_KEYS) do
      local a=before and before[k]
      local b=mon and mon.stats and mon.stats[k]
      if type(a)=="number" and type(b)=="number" and a~=b then
        out[#out+1]={key=k,from=a,to=b}
      end
    end
    return out
  end

  showStatChanges = function(world,changes,done)
    if not changes or #changes==0 then
      showNatural(world,"No displayed stat changed at this level.",done)
      return
    end
    local i=1
    local function nextChange()
      if i>#changes then
        if done then done() end
        return
      end
      local c=changes[i]
      i=i+1
      showNatural(world,
        (STAT_DISPLAY[c.key] or c.key)..": "..c.from.." - "..c.to,
        nextChange)
    end
    nextChange()
  end

  local function baseStat(game,mon,key)
    local def=game and game.data and game.data.pokemon and game.data.pokemon[mon.species]
    local bs=def and def.baseStats or {}
    if key=="specialAttack" then return tonumber(bs.specialAttack or bs.special) or 1 end
    if key=="specialDefense" then return tonumber(bs.specialDefense or bs.special) or 1 end
    return tonumber(bs[key]) or 1
  end

  local function statOverrides(mon)
    local f=fusionData(mon)
    f.statOverrides=f.statOverrides or {}
    return f.statOverrides
  end

  local function effectiveBaseStat(game,mon,key)
    return tonumber(statOverrides(mon)[key]) or baseStat(game,mon,key)
  end

  local function fusedBaseStats(game,mon)
    local def=game and game.data and game.data.pokemon
      and game.data.pokemon[mon.species]
    if not (def and def.baseStats) then return nil end
    local bs={}
    for k,v in pairs(def.baseStats) do bs[k]=v end
    local f=mon and mon.cinnabarFusion
    local o=f and f.statOverrides
    if o then
      for k,v in pairs(o) do
        if tonumber(v) then bs[k]=tonumber(v) end
      end
    end
    return bs
  end

  local function recalcFusedStats(game,mon)
    if not (game and mon) then return end
    local Mon=require("src.battle.gen2.Mon")
    local bs=fusedBaseStats(game,mon)
    if not bs then return end
    local oldMax=mon.maxHp or (mon.stats and mon.stats.hp)
    local oldHp=mon.hp
    local newStats=Mon.stats(bs,mon.dvs or {},mon.level or 1,mon.statExp or {})
    mon.stats=newStats
    mon.maxHp=newStats.hp
    if oldMax and oldHp then
      mon.hp=math.max(0,math.min(newStats.hp,oldHp+(newStats.hp-oldMax)))
    else
      mon.hp=math.min(oldHp or newStats.hp,newStats.hp)
    end
  end

  local function statFallout(game,host,donor,requested)
    local f=fusionData(host)
    local dev=game.save and game.save.cinnabarDev
    local force=(dev and dev.forceFallout) or mod.options:get("dev_fallout")
    local kind="NONE"
    if force then
      dev.statFalloutIndex=((tonumber(dev.statFalloutIndex) or 0)%5)+1
      kind=({"WRONG_STAT","TRADEOFF","SWAP","OVERCHARGE","SCRAMBLE"})[dev.statFalloutIndex]
    elseif math.random()<falloutChance(f.stability) then
      local pool={"WRONG_STAT","TRADEOFF","SWAP"}
      if f.stability<55 then pool[#pool+1]="OVERCHARGE" end
      if f.stability<35 then pool[#pool+1]="SCRAMBLE" end
      kind=pool[math.random(#pool)]
    end
    return kind
  end

  local function applyStatSplice(game,host,donor,requested,kind)
    local before=captureDisplayedStats(host)
    local o=statOverrides(host)
    local donorValue=effectiveBaseStat(game,donor,requested)
    local result=requested
    local touched={}
    local function touch(k) touched[k]=true end
    if kind=="WRONG_STAT" then
      local pool={}
      for _,k in ipairs(STAT_KEYS) do if k~=requested then pool[#pool+1]=k end end
      result=pool[math.random(#pool)]
      o[result]=effectiveBaseStat(game,donor,result)
      touch(result)
    elseif kind=="TRADEOFF" then
      o[requested]=donorValue
      touch(requested)
      local pool={}
      for _,k in ipairs(STAT_KEYS) do if k~=requested then pool[#pool+1]=k end end
      local loss=pool[math.random(#pool)]
      o[loss]=math.max(1,math.floor(effectiveBaseStat(game,host,loss)*.70))
      touch(loss)
    elseif kind=="SWAP" then
      local pool={}
      for _,k in ipairs(STAT_KEYS) do if k~=requested then pool[#pool+1]=k end end
      local other=pool[math.random(#pool)]
      local a=effectiveBaseStat(game,host,requested)
      local b=effectiveBaseStat(game,host,other)
      o[requested]=b; o[other]=a
      touch(requested); touch(other)
    elseif kind=="OVERCHARGE" then
      o[requested]=math.min(255,math.max(1,math.floor(donorValue*1.35)))
      touch(requested)
    elseif kind=="SCRAMBLE" then
      for _,k in ipairs(STAT_KEYS) do
        local d=effectiveBaseStat(game,donor,k)
        o[k]=math.max(1,math.min(255,d+math.random(-35,35)))
        touch(k)
      end
    else
      o[requested]=donorValue
      touch(requested)
    end
    recalcFusedStats(game,host)
    local changes=diffDisplayedStats(before,host)
    local f=fusionData(host)
    f.lastStatChanges=changes
    f.lastStatTouched={}
    for _,k in ipairs(STAT_KEYS) do
      if touched[k] then f.lastStatTouched[#f.lastStatTouched+1]=k end
    end
    return result,changes
  end

  local function statFalloutText(world,kind,done)
    local lines={
      NONE="The selected stat profile transferred cleanly.",
      WRONG_STAT="The transfer drifted. A different stat profile took hold.",
      TRADEOFF="The target stat improved, but another part of the profile deteriorated.",
      SWAP="The stat matrix inverted. Two of the HOST's traits traded places.",
      OVERCHARGE="The transferred stat overshot every safe projection.",
      SCRAMBLE="The stat matrix destabilized. Multiple readings have changed.",
    }
    showNatural(world,lines[kind] or lines.NONE,done)
  end

  local function findPartyMonIndex(party,mon)
    for i,m in ipairs(party or {}) do
      if m==mon then return i end
    end
    return nil
  end

  local function captureFusionVisual(mon)
    local f=mon and mon.cinnabarFusion
    return {
      species=mon and mon.species,
      paletteSpecies=(f and f.paletteSpecies) or (mon and mon.species),
      paletteOverride=f and copyPalette(f.paletteOverride),
      scale=tonumber(f and f.spriteScale) or 1,
      fragment=f and f.fragment and deep(f.fragment) or nil,
      fragmentSpecies=f and f.fragmentSpecies,
    }
  end

  local function syncExperienceToLevel(game,mon,oldLevel,oldExperience)
    if not (game and mon) then return end
    local Mon=require("src.battle.gen2.Mon")
    local def=game.data and game.data.pokemon and game.data.pokemon[mon.species]
    local growth=Mon.growthFor(game.data,def and def.growthRate)
    if not growth then return end

    oldLevel=math.max(1,tonumber(oldLevel) or tonumber(mon.level) or 1)
    local newLevel=math.max(1,tonumber(mon.level) or 1)
    oldExperience=tonumber(oldExperience) or tonumber(mon.experience)
      or Mon.experienceForLevel(growth,oldLevel)

    local oldBase=Mon.experienceForLevel(growth,oldLevel)
    local oldNext=Mon.experienceForLevel(growth,oldLevel+1)
    local fraction=0
    if oldNext and oldBase and oldNext>oldBase then
      fraction=math.max(0,math.min(1,
        (oldExperience-oldBase)/(oldNext-oldBase)))
    end

    local newBase=Mon.experienceForLevel(growth,newLevel)
    local newNext=Mon.experienceForLevel(growth,newLevel+1)
    if newBase and newNext and newNext>newBase then
      mon.experience=math.floor(newBase+
        fraction*(newNext-newBase))
    elseif newBase then
      mon.experience=newBase
    end
  end

  local function repairMutantExperience(mon,data)
    local f=mon and mon.cinnabarFusion
    if not (f and mon and data) then return end
    local Mon=require("src.battle.gen2.Mon")
    local def=data.pokemon and data.pokemon[mon.species]
    local growth=Mon.growthFor(data,def and def.growthRate)
    if not growth then return end
    local level=math.max(1,tonumber(mon.level) or 1)
    local base=Mon.experienceForLevel(growth,level)
    local next_=Mon.experienceForLevel(growth,level+1)
    local exp=tonumber(mon.experience)
    -- A stable Gen2 mon should always sit inside its current level's EXP span.
    -- Old DEV83-85 level mutations could leave EXP on the previous level's
    -- curve, producing a permanently empty battle EXP bar.
    if exp==nil or exp<base
        or (next_ and level<(cinnabarLevelCap and cinnabarLevelCap(mon) or 100)
            and exp>=next_) then
      mon.experience=base
    end
  end

  -- General instability is independent of the requested splice. These are
  -- specimen-wide anomalies caused by repeated exposure to the machine.
  local function rollGeneralMutation(game,host,donor)
    if not host then return nil end
    local f=fusionData(host)
    local save=game and game.save
    local dev=save and save.cinnabarDev
    local forced=dev and dev.forceGeneralMutation
    if forced then dev.forceGeneralMutation=false end

    local st=tonumber(f.stability) or 100
    local chance=0
    if st<=20 then chance=.45
    elseif st<=40 then chance=.28
    elseif st<=60 then chance=.14
    elseif st<=80 then chance=.05 end
    if not forced and (chance<=0 or math.random()>=chance) then return nil end

    local pool={"LEVEL_LOSS","LEVEL_GAIN","CRY_DRIFT","NEXT_EVOLUTION","LEVEL_CAP"}
    local kind
    if forced then
      dev.generalMutationIndex=((tonumber(dev.generalMutationIndex) or 0)%#pool)+1
      kind=pool[dev.generalMutationIndex]
    else kind=pool[math.random(#pool)] end

    local result={kind=kind}
    if kind=="LEVEL_LOSS" then
      local old=tonumber(host.level) or 1
      local loss=math.min(old-1,math.random(2,8))
      if loss<=0 then kind="LEVEL_GAIN"; result.kind=kind
      else
        local oldExp=host.experience
        host.level=old-loss; result.before=old; result.after=host.level
        syncExperienceToLevel(game,host,old,oldExp)
        local Mon=require("src.battle.gen2.Mon")
        pcall(Mon.refreshStats,host,game.data)
      end
    end
    if kind=="LEVEL_GAIN" then
      local old=tonumber(host.level) or 1
      local gain=math.random(2,8)
      local oldExp=host.experience
      host.level=math.min(100,old+gain)
      result.before=old; result.after=host.level
      syncExperienceToLevel(game,host,old,oldExp)
      local Mon=require("src.battle.gen2.Mon")
      pcall(Mon.refreshStats,host,game.data)
    elseif kind=="CRY_DRIFT" then
      local species=randomPaletteSpecies(game,host.species,donor and donor.species)
        or (donor and donor.species) or host.species
      f.cryMutation={kind="GENERAL",species=species,
        pitch=({.70,.82,1.18,1.34})[math.random(4)]}
      result.species=species
    elseif kind=="NEXT_EVOLUTION" then
      local species=randomPaletteSpecies(game,host.species,donor and donor.species)
      if species then f.nextEvolutionSpecies=species; result.species=species end
    elseif kind=="LEVEL_CAP" then
      f.levelCap=255
      result.cap=255
    end
    f.generalMutations=f.generalMutations or {}
    f.generalMutations[#f.generalMutations+1]=deep(result)
    return result
  end

  generalMutationLine = function(m)
    if not m then return nil end
    if m.kind=="LEVEL_LOSS" then
      return "Its level regressed from "..tostring(m.before).." to "..tostring(m.after).."."
    elseif m.kind=="LEVEL_GAIN" then
      return "Its level jumped from "..tostring(m.before).." to "..tostring(m.after).."."
    elseif m.kind=="CRY_DRIFT" then
      return "Its vocal pattern changed too. That wasn't part of the procedure."
    elseif m.kind=="NEXT_EVOLUTION" then
      return "Its next level-up will trigger an unrelated random evolution."
    elseif m.kind=="LEVEL_CAP" then
      return "Its growth limit is reading above normal. Far above normal."
    end
  end

  local function rollCatastrophe(game,stability,canLose)
    local save=game and game.save
    local dev=save and save.cinnabarDev
    if dev and dev.forceCatastrophe then
      dev.forceCatastrophe=false
      dev.catastropheTestIndex=((tonumber(dev.catastropheTestIndex) or 0)%3)+1
      local forced=({"DITTO","GLITCH","LOSS"})[dev.catastropheTestIndex]
      if forced=="LOSS" and not canLose then forced="DITTO" end
      return forced
    end

    stability=tonumber(stability) or 100
    if stability>20 then return nil end
    local chance
    if stability<=0 then
      chance=.70
    else
      chance=.12 + ((20-stability)/19)*.18
    end
    if math.random()>=chance then return nil end

    local r=math.random(100)
    local kind
    if r<=70 then kind="DITTO"
    elseif r<=90 then kind="GLITCH"
    else kind="LOSS" end
    if kind=="LOSS" and not canLose then kind="DITTO" end
    return kind
  end

  local function applyCatastrophe(game,host,donor,kind)
    local data=game and game.data
    local f=fusionData(host)
    f.catastrophes=f.catastrophes or {}

    if kind=="DITTO" then
      f.catastrophes[#f.catastrophes+1]={
        kind="DITTO",fromSpecies=host.species,stability=f.stability}
      f.paletteSpecies=nil
      f.paletteOverride=nil
      f.spriteScale=nil
      f.fragment=nil
      f.fragmentSpecies=nil
      f.cryMutation=nil
      f.statOverrides=nil
      f.typeOverride=nil
      f.lastTypeChange=nil
      local dittoDef=game and game.data and game.data.pokemon
        and game.data.pokemon[host.species]
      if dittoDef and dittoDef.types then
        host.types={}
        for i,t in ipairs(dittoDef.types) do host.types[i]=t end
      end
      f.lastStatChanges=nil
      f.lastStatTouched=nil
      host.species="DITTO"
      local Mon=require("src.battle.gen2.Mon")
      local def=data and data.pokemon and data.pokemon.DITTO
      if def then
        Mon.syncIdentity(host,data)
        host.moves=Mon.movesAtLevel(def,host.level or 1,data.moves)
        Mon.refreshStats(host,data)
      end
      f.stability=50
      f.catastrophe="DITTO_COLLAPSE"

    elseif kind=="GLITCH" then
      local palettes=data and data.gen2Palettes
      local base=palettes and effectivePalette(host,palettes)
      f.paletteOverride=funkyPalette(base)
      f.paletteSpecies=nil
      local scales={.65,.78,1.28,1.48}
      f.spriteScale=scales[math.random(#scales)]
      f.fragmentSpecies=donor and donor.species or f.fragmentSpecies
      f.fragment=makeAnatomicalFragment(data,host.species,
        f.fragmentSpecies,false,
        tonumber(donor and donor.cinnabarFusion
          and donor.cinnabarFusion.spriteScale) or 1)
      f.cryMutation={
        kind="RANDOM",
        species=randomPaletteSpecies(game,host.species,
          donor and donor.species) or (donor and donor.species) or host.species,
        pitch=({.62,.76,1.28,1.48})[math.random(4)],
      }
      local donorTypes=effectiveTypes(game,donor)
      if donorTypes and #donorTypes>0 then
        f.typeOverride={donorTypes[math.random(#donorTypes)]}
        local ownTypes=speciesTypes(game,host)
        if #ownTypes>0 and math.random(2)==1 then
          local second=ownTypes[math.random(#ownTypes)]
          if second~=f.typeOverride[1] then f.typeOverride[2]=second end
        end
      end
      local o=statOverrides(host)
      for _,k in ipairs(STAT_KEYS) do
        local d=donor and effectiveBaseStat(game,donor,k)
          or effectiveBaseStat(game,host,k)
        o[k]=math.max(1,math.min(255,(d or 1)+math.random(-45,45)))
      end
      recalcFusedStats(game,host)
      f.stability=1
      f.catastrophe="GLITCH_SURVIVOR"
      f.catastrophes[#f.catastrophes+1]={
        kind="GLITCH",species=host.species,stability=1}

    elseif kind=="LOSS" then
      f.catastrophe="TOTAL_FAILURE"
      f.catastrophes[#f.catastrophes+1]={
        kind="LOSS",species=host.species,stability=f.stability}
    end
  end

  local function showCatastropheResult(world,party,host,kind,done)
    if kind=="DITTO" then
      showNatural(world,
        "The specimen collapsed completely... then stabilized as a DITTO.",
        function()
          showNatural(world,"FUSION STABILITY: "..stabilityReport(
            fusionData(host).stability),done)
        end)
    elseif kind=="GLITCH" then
      showNatural(world,
        "It survived. Barely. Multiple traits mutated at the same time.",
        function()
          showNatural(world,"FUSION STABILITY: "..stabilityReport(
            fusionData(host).stability),done)
        end)
    elseif kind=="LOSS" then
      local index=findPartyMonIndex(party,host)
      if index then table.remove(party,index) end
      showNatural(world,
        "The specimen destabilized completely. There's nothing left to recover.",
        done)
    elseif done then done() end
  end

  local function pushCatastropheAnim(world,party,host,donor,kind,
      beforeHost,beforeDonor,afterAnim)
    local game=world.game
    local f=fusionData(host)
    local Screens=require("src.ui.Screens")
    Screens.push(game,"CinnabarFusionAnim",{
      host=host,donor=donor,
      hostSpecies=beforeHost.species,
      donorSpecies=beforeDonor.species,
      resultSpecies=(kind=="DITTO") and "DITTO" or host.species,
      resultLost=kind=="LOSS",
      hostPaletteSpecies=beforeHost.paletteSpecies,
      hostPaletteOverride=beforeHost.paletteOverride,
      donorPaletteSpecies=beforeDonor.paletteSpecies,
      donorPaletteOverride=beforeDonor.paletteOverride,
      resultPaletteSpecies=(f.paletteSpecies or host.species),
      resultPaletteOverride=copyPalette(f.paletteOverride),
      hostScale=beforeHost.scale,
      donorScale=beforeDonor.scale,
      hostFragment=beforeHost.fragment,
      hostFragmentSpecies=beforeHost.fragmentSpecies,
      donorFragment=beforeDonor.fragment,
      donorFragmentSpecies=beforeDonor.fragmentSpecies,
      resultScale=tonumber(f.spriteScale) or 1,
      resultCrySpecies=effectiveCrySpecies(host),
      resultCryPitch=(cryMutation(host) and cryMutation(host).pitch) or 1,
      fragmentSpecies=f.fragmentSpecies,
      fragment=f.fragment,
      onDone=function()
        showCatastropheResult(world,party,host,kind,afterAnim)
      end,
    })
  end

  local function startStatSplice(world)
    local game=world.game
    local save=game.save
    local party=save.party or {}
    local lab=labState(game)
    if lab.tier<3 then showNatural(world,"Stat splicing requires FACILITY TIER 3.") return end
    if fusionBusy then return end
    if #party<2 then showNatural(world,"Bring me two POKéMON for the procedure.") return end
    local player=save.player
    if not player or (player.money or 0)<STAT_PRICE then
      showNatural(world,"A stat splice costs ¥7500. You don't have enough money.") return
    end
    showNatural(world,"Choose the HOST. Its stat profile will be rewritten.",function()
      pickForSplice(world,"Choose the HOST.",function(hi,host)
        if not host then return end
        showNatural(world,"Choose the DONOR. We'll isolate one of its stat profiles.",function()
          pickForSplice(world,"Choose the DONOR.",function(di,donor)
            if not donor then return end
            if di==hi then showNatural(world,"HOST and DONOR must be different.") return end
            showNatural(world,"Which stat should the DONOR contribute?",function()
              chooseScriptMenu(world,STAT_LABELS,function(index)
                if not index or index>#STAT_KEYS then return end
                local key=STAT_KEYS[index]
                showNatural(world,
                  monName(game,host).." will receive "..STAT_LABELS[index].." potential from "..monName(game,donor)..".",
                  function()
                    world:askYesNo(function(yes)
                      if not yes then return end
                      fusionBusy=true
                      player.money=math.max(0,(player.money or 0)-STAT_PRICE)
                      runFusionProcedure(world,host,donor,function(afterAnim)
                        table.remove(party,di)
                        local f=fusionData(host)
                        local beforeHost=captureFusionVisual(host)
                        local beforeDonor=captureFusionVisual(donor)
                        f.spliceCount=f.spliceCount+1
                        f.stability=math.max(0,f.stability-12)
                        local catastrophe=rollCatastrophe(game,f.stability,#party>1)
                        if catastrophe then
                          f.history[#f.history+1]={kind="STAT",
                            donorSpecies=donor.species,requestedStat=key,
                            catastrophe=catastrophe}
                          world.cinnabarLastFallout="CATA_"..catastrophe
                          applyCatastrophe(game,host,donor,catastrophe)
                          pushCatastropheAnim(world,party,host,donor,
                            catastrophe,beforeHost,beforeDonor,afterAnim)
                          return
                        end
                        local fallout=statFallout(game,host,donor,key)
                        local result,changed=
                          applyStatSplice(game,host,donor,key,fallout)
                        world.cinnabarGeneralMutation=rollGeneralMutation(game,host,donor)
                        f.history[#f.history+1]={kind="STAT",donorSpecies=donor.species,
                          requestedStat=key,resultStat=result,fallout=fallout}
                        lab.experiments=lab.experiments+1
                        world.cinnabarLastFallout=fallout=="NONE" and nil or ("STAT_"..fallout)
                        local Screens=require("src.ui.Screens")
                        Screens.push(game,"CinnabarFusionAnim",{
                          host=host,donor=donor,
                          hostPaletteSpecies=(host.cinnabarFusion and host.cinnabarFusion.paletteSpecies) or host.species,
                          hostPaletteOverride=host.cinnabarFusion and copyPalette(host.cinnabarFusion.paletteOverride),
                          donorPaletteSpecies=(donor.cinnabarFusion and donor.cinnabarFusion.paletteSpecies) or donor.species,
                          donorPaletteOverride=donor.cinnabarFusion and copyPalette(donor.cinnabarFusion.paletteOverride),
                          resultPaletteSpecies=(host.cinnabarFusion and host.cinnabarFusion.paletteSpecies) or host.species,
                          resultPaletteOverride=host.cinnabarFusion and copyPalette(host.cinnabarFusion.paletteOverride),
                          hostScale=tonumber(host.cinnabarFusion and host.cinnabarFusion.spriteScale) or 1,
                          donorScale=tonumber(donor.cinnabarFusion and donor.cinnabarFusion.spriteScale) or 1,
                          hostFragment=host.cinnabarFusion and host.cinnabarFusion.fragment,
                          hostFragmentSpecies=host.cinnabarFusion and host.cinnabarFusion.fragmentSpecies,
                          donorFragment=donor.cinnabarFusion and donor.cinnabarFusion.fragment,
                          donorFragmentSpecies=donor.cinnabarFusion and donor.cinnabarFusion.fragmentSpecies,
                          resultScale=tonumber(host.cinnabarFusion and host.cinnabarFusion.spriteScale) or 1,
                          resultCrySpecies=effectiveCrySpecies(host),
                          resultCryPitch=(cryMutation(host) and cryMutation(host).pitch) or 1,
                          fragmentSpecies=host.cinnabarFusion and host.cinnabarFusion.fragmentSpecies,
                          fragment=host.cinnabarFusion and host.cinnabarFusion.fragment,
                          onDone=function()
                            statFalloutText(world,fallout,function()
                              showStatChanges(world,changed,function()
                                showNatural(world,
                                  "FUSION STABILITY: "..stabilityReport(f.stability),
                                  afterAnim)
                              end)
                            end)
                          end,
                        })
                      end)
                    end)
                  end)
              end,1,17)
            end)
          end)
        end)
      end)
    end)
  end

  local CHROMATIC_PRICE = 2500

  -- Tier 4: individual Type Splicing. Custom/new types are deliberately
  -- postponed until after 1.0; DEV78 only works with canonical Crystal types.
  local TYPE_PRICE = 10000

  local function speciesTypes(game,mon)
    local def=game and game.data and game.data.pokemon
      and mon and game.data.pokemon[mon.species]
    -- Gen2 party mons carry their actual type pair on mon.types. Prefer it:
    -- it preserves dual types such as RHYHORN's GROUND/ROCK pair.
    local source=(mon and mon.types) or (def and def.types) or {}
    local out={}
    for _,t in ipairs(source) do
      if t and t~="" then
        local seen=false
        for _,have in ipairs(out) do if have==t then seen=true break end end
        if not seen then out[#out+1]=t end
      end
    end
    if #out==0 then out[1]="NORMAL" end
    return out
  end

  local function effectiveTypes(game,mon)
    local f=mon and mon.cinnabarFusion
    if f and type(f.typeOverride)=="table" and #f.typeOverride>0 then
      local out={}
      for i,t in ipairs(f.typeOverride) do out[i]=t end
      return out
    end
    return speciesTypes(game,mon)
  end

  local function typeLabel(t)
    if t=="PSYCHIC_TYPE" then return "PSYCHIC" end
    return tostring(t or "?"):gsub("_"," ")
  end

  local function typePairText(types)
    if not types or #types==0 then return "UNKNOWN" end
    if #types==1 or types[1]==types[2] then return typeLabel(types[1]) end
    return typeLabel(types[1]).."/"..typeLabel(types[2])
  end

  local function typeFallout(game,host,donor,requestedType,slot)
    local save=game and game.save
    local dev=save and save.cinnabarDev
    local force=(dev and dev.forceFallout) or mod.options:get("dev_fallout")
    local stability=tonumber(fusionData(host).stability) or 100
    if not force and (stability>45 or math.random(100)>math.max(8,55-stability)) then
      return "NONE",requestedType,slot
    end
    local donorTypes=effectiveTypes(game,donor)
    local alternatives={}
    for _,t in ipairs(donorTypes) do
      if t~=requestedType then alternatives[#alternatives+1]=t end
    end
    local roll=math.random(3)
    if roll==1 and #alternatives>0 then
      return "WRONG_TYPE",alternatives[math.random(#alternatives)],slot
    elseif roll==2 then
      return "WRONG_SLOT",requestedType,(slot==1 and 2 or 1)
    else
      return "DOUBLE",requestedType,slot
    end
  end

  local function applyTypeSplice(game,host,donor,requestedType,slot,fallout)
    local before=effectiveTypes(game,host)
    local result={before[1],before[2]}
    local donorTypes=effectiveTypes(game,donor)
    if fallout=="DOUBLE" then
      result[1]=donorTypes[1] or requestedType
      result[2]=donorTypes[2] or donorTypes[1] or requestedType
    else
      result[slot]=requestedType
    end
    if not result[1] then result[1]=result[2] or "NORMAL" end
    if result[2]==result[1] then result[2]=nil end
    local f=fusionData(host)
    f.typeOverride={result[1]}
    if result[2] then f.typeOverride[2]=result[2] end
    -- Gen2 SummaryMenu reads mon.types before the species definition.
    -- Keep the live individual in sync with the persistent fusion override.
    monTypes={}
    for i,t in ipairs(f.typeOverride) do monTypes[i]=t end
    host.types=monTypes
    f.lastTypeChange={before=before,after=f.typeOverride}
    return before,f.typeOverride
  end

  local function typeFalloutText(world,kind,done)
    if kind=="WRONG_TYPE" then
      showNatural(world,"The transfer drifted. A different DONOR type took hold.",done)
    elseif kind=="WRONG_SLOT" then
      showNatural(world,"The type held, but it bonded to the wrong side of the HOST's profile.",done)
    elseif kind=="DOUBLE" then
      showNatural(world,"The splice overreached. Both type slots copied the DONOR profile.",done)
    elseif done then done() end
  end

  local function startTypeSplice(world)
    local game=world.game
    local save=game.save
    local party=save.party or {}
    local lab=labState(game)
    if lab.tier<4 then showNatural(world,"Type splicing requires FACILITY TIER 4.") return end
    if fusionBusy then return end
    if #party<2 then showNatural(world,"Bring me two POKéMON for the procedure.") return end
    local player=save.player
    if not player or (player.money or 0)<TYPE_PRICE then
      showNatural(world,"A type splice costs ¥10000. You don't have enough money.") return
    end
    showNatural(world,"Choose the HOST. Its individual type profile will be rewritten.",function()
      pickForSplice(world,"Choose the HOST.",function(hi,host)
        if not host then return end
        showNatural(world,"Choose the DONOR. We'll isolate one of its existing types.",function()
          pickForSplice(world,"Choose the DONOR.",function(di,donor)
            if not donor then return end
            if di==hi then showNatural(world,"HOST and DONOR must be different.") return end
            local dtypes=effectiveTypes(game,donor)
            local labels={}
            for _,t in ipairs(dtypes) do labels[#labels+1]=typeLabel(t) end
            labels[#labels+1]="CANCEL"
            showNatural(world,"Which DONOR type should we transplant?",function()
              chooseScriptMenu(world,labels,function(ti)
                if not ti or ti>#dtypes then return end
                local requested=dtypes[ti]
                local htypes=effectiveTypes(game,host)
                for _,existing in ipairs(htypes) do
                  if existing==requested then
                    showNatural(world,
                      monName(game,host).." already has the "..typeLabel(requested)..
                      " type. That splice would accomplish nothing.")
                    return
                  end
                end
                -- Keep labels compact enough for the native Crystal menu width.
                local slots={"1: "..typeLabel(htypes[1])}
                slots[#slots+1]="2: "..(htypes[2] and typeLabel(htypes[2]) or "EMPTY")
                slots[#slots+1]="CANCEL"
                showNatural(world,
                  "Choose the HOST type slot to overwrite.",function()
                  chooseScriptMenu(world,slots,function(si)
                    if not si or si>2 then return end
                    showNatural(world,monName(game,host).." will receive "..typeLabel(requested)..
                      " in that type slot. The DONOR will be consumed.",function()
                      world:askYesNo(function(yes)
                        if not yes then return end
                        fusionBusy=true
                        player.money=math.max(0,(player.money or 0)-TYPE_PRICE)
                        runFusionProcedure(world,host,donor,function(afterAnim)
                          local beforeHost=captureFusionVisual(host)
                          local beforeDonor=captureFusionVisual(donor)
                          table.remove(party,di)
                          local f=fusionData(host)
                          f.spliceCount=f.spliceCount+1
                          f.stability=math.max(0,f.stability-15)
                          local catastrophe=rollCatastrophe(game,f.stability,#party>1)
                          if catastrophe then
                            f.history[#f.history+1]={kind="TYPE",donorSpecies=donor.species,
                              requestedType=requested,catastrophe=catastrophe}
                            world.cinnabarLastFallout="CATA_"..catastrophe
                            applyCatastrophe(game,host,donor,catastrophe)
                            pushCatastropheAnim(world,party,host,donor,catastrophe,
                              beforeHost,beforeDonor,afterAnim)
                            return
                          end
                          local fallout,resultType,resultSlot=
                            typeFallout(game,host,donor,requested,si)
                          local before,after=applyTypeSplice(game,host,donor,
                            resultType,resultSlot,fallout)
                          world.cinnabarGeneralMutation=rollGeneralMutation(game,host,donor)
                          f.history[#f.history+1]={kind="TYPE",donorSpecies=donor.species,
                            requestedType=requested,resultTypes=after,fallout=fallout}
                          lab.experiments=lab.experiments+1
                          lab.typeSpliceCompleted=true
                          world.cinnabarLastFallout=
                            fallout=="NONE" and nil or ("TYPE_"..fallout)
                          local Screens=require("src.ui.Screens")
                          Screens.push(game,"CinnabarFusionAnim",{
                            host=host,donor=donor,
                            hostPaletteSpecies=beforeHost.paletteSpecies,
                            hostPaletteOverride=beforeHost.paletteOverride,
                            donorPaletteSpecies=beforeDonor.paletteSpecies,
                            donorPaletteOverride=beforeDonor.paletteOverride,
                            resultPaletteSpecies=(f.paletteSpecies or host.species),
                            resultPaletteOverride=copyPalette(f.paletteOverride),
                            hostScale=beforeHost.scale,donorScale=beforeDonor.scale,
                            hostFragment=beforeHost.fragment,
                            hostFragmentSpecies=beforeHost.fragmentSpecies,
                            donorFragment=beforeDonor.fragment,
                            donorFragmentSpecies=beforeDonor.fragmentSpecies,
                            resultScale=tonumber(f.spriteScale) or 1,
                            resultCrySpecies=effectiveCrySpecies(host),
                            resultCryPitch=(cryMutation(host) and cryMutation(host).pitch) or 1,
                            fragmentSpecies=f.fragmentSpecies,fragment=f.fragment,
                            onDone=function()
                              typeFalloutText(world,fallout,function()
                                showNatural(world,"TYPE PROFILE: "..typePairText(before)..
                                  " -> "..typePairText(after),function()
                                  showNatural(world,"FUSION STABILITY: "..
                                    stabilityReport(f.stability),afterAnim)
                                end)
                              end)
                            end,
                          })
                        end)
                      end)
                    end)
                  end,2,13)
                end)
              end,3,14)
            end)
          end)
        end)
      end)
    end)
  end

  local MOVE_PRICE = 5000

  local function moveName(game, id)
    local def=game and game.data and game.data.moves and game.data.moves[id]
    return (def and def.name) or tostring(id or "MOVE"):gsub("_"," ")
  end

  local function copyMove(mv)
    if type(mv)~="table" then return nil end
    local out={}
    for k,v in pairs(mv) do out[k]=v end
    return out
  end

  chooseScriptMenu = function(world,labels,done,top,bottom,onCancel)
    local Screens=require("src.ui.Screens")
    local closed=false
    local function close()
      if closed then return false end
      closed=true
      if world.game and world.game.stack then world.game.stack:pop() end
      return true
    end
    Screens.push(world.game,"Gen2ScriptMenu",{
      header={left=2,top=top or 3,right=19,bottom=bottom or 15,
        items=labels,dataFlags=0x80,cursor=1},
      style="vertical",
      onChoose=function(index)
        if not close() then return end
        if done then done(index) end
      end,
      onCancel=function()
        if not close() then return end
        if onCancel then onCancel() end
      end,
    })
  end

  local function pickDonorMove(world, donor, done)
    local moves=donor and donor.moves or {}
    if #moves==0 then
      showNatural(world,"That DONOR has no moves I can isolate.")
      return
    end
    local labels={}
    for i,mv in ipairs(moves) do
      labels[i]=moveName(world.game,mv.id)
    end
    labels[#labels+1]="CANCEL"
    chooseScriptMenu(world,labels,function(index)
      if index and index<=#moves then
        if world.playSfxNamed then world:playSfxNamed("Sfx_ReadText2") end
        done(index,moves[index])
      end
    end,2,15)
  end

  local function chooseHostMoveSlot(world,host,newMove,done)
    local moves=host.moves or {}
    if #moves<4 then
      done(#moves+1)
      return
    end
    local labels={}
    for i,mv in ipairs(moves) do labels[i]=moveName(world.game,mv.id) end
    labels[#labels+1]="CANCEL"
    showNatural(world,"Which HOST move should be replaced?",function()
      chooseScriptMenu(world,labels,function(index)
        if index and index<=#moves then
          if world.playSfxNamed then world:playSfxNamed("Sfx_ReadText2") end
          done(index)
        end
      end,2,15)
    end)
  end

  local function moveFallout(game,host,donor,requested)
    local f=fusionData(host)
    local dev=game and game.save and game.save.cinnabarDev
    local force=(dev and dev.forceFallout) or mod.options:get("dev_fallout")
    local outcome="NONE"
    if force then
      dev=dev or {}
      game.save.cinnabarDev=dev
      local n=(tonumber(dev.moveFalloutIndex) or 0)+1
      if n>3 then n=1 end
      dev.moveFalloutIndex=n
      outcome=({"WRONG_MOVE","ZERO_PP","LOW_PP"})[n]
    elseif math.random()<falloutChance(f.stability) then
      local pool={"WRONG_MOVE","LOW_PP"}
      if f.stability<41 then pool[#pool+1]="ZERO_PP" end
      outcome=pool[math.random(#pool)]
    end

    local result=copyMove(requested) or {}
    if outcome=="WRONG_MOVE" then
      local choices={}
      for _,mv in ipairs((donor and donor.moves) or {}) do
        if mv.id~=requested.id then choices[#choices+1]=mv end
      end
      if #choices>0 then result=copyMove(choices[math.random(#choices)]) end
    elseif outcome=="ZERO_PP" then
      result.pp=0
      result.maxPp=0
    elseif outcome=="LOW_PP" then
      local max=tonumber(result.maxPp or result.pp) or 1
      result.maxPp=math.max(1,math.floor(max*.25))
      result.pp=result.maxPp
    end
    return outcome,result
  end

  local function moveFalloutText(world,outcome,moveId,done)
    if outcome=="NONE" then
      showNatural(world,moveName(world.game,moveId).." transferred successfully.",done)
    elseif outcome=="WRONG_MOVE" then
      showNatural(world,"The transfer drifted. A different DONOR move came through.",done)
    elseif outcome=="ZERO_PP" then
      showNatural(world,"The move transferred, but its energy channels are completely inert.",done)
    elseif outcome=="LOW_PP" then
      showNatural(world,"The move transferred with severely reduced usable energy.",done)
    elseif done then done() end
  end

  local function startMoveSplice(world)
    local game=world and world.game
    local save=game and game.save
    local party=save and save.party or {}
    local lab=labState(game)
    if lab.tier<2 then
      showNatural(world,"Move splicing requires FACILITY TIER 2.")
      return
    end
    if fusionBusy then return end
    if #party<2 then
      showNatural(world,"Bring me two POKéMON for the procedure.")
      return
    end
    local player=save and save.player
    if not player or (player.money or 0)<MOVE_PRICE then
      showNatural(world,"A move splice costs ¥5000. You don't have enough money.")
      return
    end

    showNatural(world,"Choose the HOST. This POKéMON will receive the move.",function()
      pickForSplice(world,"Choose the HOST.",function(hostIndex,host)
        if not host then return end
        showNatural(world,"Now choose the DONOR. We'll isolate one of its moves.",function()
          pickForSplice(world,"Choose the DONOR.",function(donorIndex,donor)
            if not donor then return end
            if donor==host or donorIndex==hostIndex then
              showNatural(world,"HOST and DONOR must be different.")
              return
            end
            pickDonorMove(world,donor,function(_,requestedMove)
              if not requestedMove or not requestedMove.id then return end
              chooseHostMoveSlot(world,host,requestedMove,function(slot)
                if not slot then return end
                local hname=monName(game,host)
                local dname=monName(game,donor)
                local mname=moveName(game,requestedMove.id)
                showNatural(world,
                  hname.." will receive "..mname..". "..dname.." will be consumed.",
                  function()
                    world:askYesNo(function(yes)
                      if not yes then
                        showNatural(world,"Move splice canceled.")
                        return
                      end
                      fusionBusy=true
                      player.money=math.max(0,(player.money or 0)-MOVE_PRICE)

                      runFusionProcedure(world,host,donor,function(afterAnim)
                        table.remove(party,donorIndex)
                        local f=fusionData(host)
                        local beforeHost=captureFusionVisual(host)
                        local beforeDonor=captureFusionVisual(donor)
                        f.spliceCount=f.spliceCount+1
                        f.stability=math.max(0,f.stability-8)

                        local catastrophe=rollCatastrophe(game,f.stability,#party>1)
                        if catastrophe then
                          f.history[#f.history+1]={kind="MOVE",
                            donorSpecies=donor.species,
                            requestedMove=requestedMove.id,
                            catastrophe=catastrophe}
                          world.cinnabarLastFallout="CATA_"..catastrophe
                          applyCatastrophe(game,host,donor,catastrophe)
                          pushCatastropheAnim(world,party,host,donor,
                            catastrophe,beforeHost,beforeDonor,afterAnim)
                          return
                        end

                        local outcome,resultMove=moveFallout(game,host,donor,requestedMove)
                        host.moves=host.moves or {}
                        host.moves[slot]=resultMove
                        world.cinnabarGeneralMutation=rollGeneralMutation(game,host,donor)
                        f.history[#f.history+1]={
                          kind="MOVE", donorSpecies=donor.species,
                          requestedMove=requestedMove.id,
                          resultMove=resultMove.id, fallout=outcome,
                        }
                        lab.experiments=lab.experiments+1
                        world.cinnabarLastFallout =
                          outcome=="NONE" and nil or ("MOVE_"..outcome)

                        local Screens=require("src.ui.Screens")
                        Screens.push(game,"CinnabarFusionAnim",{
                          host=host, donor=donor,
                          hostPaletteSpecies=(host.cinnabarFusion and host.cinnabarFusion.paletteSpecies) or host.species,
                          hostPaletteOverride=host.cinnabarFusion and copyPalette(host.cinnabarFusion.paletteOverride),
                          donorPaletteSpecies=(donor.cinnabarFusion and donor.cinnabarFusion.paletteSpecies) or donor.species,
                          donorPaletteOverride=donor.cinnabarFusion and copyPalette(donor.cinnabarFusion.paletteOverride),
                          resultPaletteSpecies=(host.cinnabarFusion and host.cinnabarFusion.paletteSpecies) or host.species,
                          resultPaletteOverride=host.cinnabarFusion and copyPalette(host.cinnabarFusion.paletteOverride),
                          hostScale=tonumber(host.cinnabarFusion and host.cinnabarFusion.spriteScale) or 1,
                          donorScale=tonumber(donor.cinnabarFusion and donor.cinnabarFusion.spriteScale) or 1,
                          hostFragment=host.cinnabarFusion and host.cinnabarFusion.fragment,
                          hostFragmentSpecies=host.cinnabarFusion and host.cinnabarFusion.fragmentSpecies,
                          donorFragment=donor.cinnabarFusion and donor.cinnabarFusion.fragment,
                          donorFragmentSpecies=donor.cinnabarFusion and donor.cinnabarFusion.fragmentSpecies,
                          resultScale=tonumber(host.cinnabarFusion and host.cinnabarFusion.spriteScale) or 1,
                          resultCrySpecies=effectiveCrySpecies(host),
                          resultCryPitch=(cryMutation(host) and cryMutation(host).pitch) or 1,
                          fragmentSpecies=host.cinnabarFusion and host.cinnabarFusion.fragmentSpecies,
                          fragment=host.cinnabarFusion and host.cinnabarFusion.fragment,
                          onDone=function()
                            moveFalloutText(world,outcome,resultMove.id,function()
                              showNatural(world,
                                "FUSION STABILITY: "..stabilityReport(f.stability),
                                afterAnim)
                            end)
                          end,
                        })
                      end)
                    end)
                  end)
              end)
            end)
          end)
        end)
      end)
    end)
  end

  local function startChromaticSplice(world)
    local game = world and world.game
    local save = game and game.save
    local party = save and save.party or {}

    if fusionBusy then return end

    if #party < 2 then
      showNatural(world, "Bring me two POKéMON for the procedure.")
      return
    end

    local player = save and save.player
    if not player or (player.money or 0) < CHROMATIC_PRICE then
      showNatural(world, "A chromatic splice will cost ¥2500.", function()
        showNatural(world, "You don't have enough money.")
      end)
      return
    end

    showNatural(world, "Choose the HOST. This is the POKéMON that stays with you.", function()
      pickForSplice(world, "Choose the HOST.", function(hostIndex, host)
        if not host then return end

        showNatural(world, "Now choose a DONOR. Its color profile will be used.", function()
          pickForSplice(world, "Choose the DONOR.", function(donorIndex, donor)
            if not donor then return end
            if donor == host or donorIndex == hostIndex then
              showNatural(world, "HOST and DONOR must be different.")
              return
            end

            local hostName = monName(game, host)
            local donorName = monName(game, donor)
            showNatural(world,
              string.format("%s + %s? The DONOR will be consumed.", hostName, donorName),
              function()
                world:askYesNo(function(yes)
                  if not yes then
                    showNatural(world, "Splice canceled.")
                    return
                  end

                  fusionBusy = true
                  player.money = math.max(0, (player.money or 0) - CHROMATIC_PRICE)

                  -- A previously chromatically-spliced DONOR passes on its
                  -- CURRENT color profile, not its original species palette.
                  local donorSpecies = donor.species
                  local donorFusion = donor.cinnabarFusion
                  local donorPaletteSpecies =
                    (donorFusion and donorFusion.paletteSpecies) or donorSpecies
                  local donorPaletteOverride =
                    donorFusion and copyPalette(donorFusion.paletteOverride)

                  -- Snapshot the HOST's current appearance before overwriting it.
                  local hostFusion = host.cinnabarFusion
                  local hostPaletteSpecies =
                    (hostFusion and hostFusion.paletteSpecies) or host.species
                  local hostPaletteOverride =
                    hostFusion and copyPalette(hostFusion.paletteOverride)
                  local hostScale = tonumber(hostFusion and hostFusion.spriteScale) or 1
                  local donorScale = tonumber(donorFusion and donorFusion.spriteScale) or 1

                  runFusionProcedure(world, host, donor, function(afterAnim)
                    local beforeHost=captureFusionVisual(host)
                    local beforeDonor=captureFusionVisual(donor)
                    table.remove(party, donorIndex)
                    local f = fusionData(host)
                    f.spliceCount = f.spliceCount + 1
                    f.stability = math.max(0, f.stability - 5)

                    local catastrophe=rollCatastrophe(game,f.stability,#party>1)
                    if catastrophe then
                      f.history[#f.history+1]={
                        kind="CHROMATIC",donorSpecies=donorSpecies,
                        donorPaletteSpecies=donorPaletteSpecies,
                        catastrophe=catastrophe}
                      world.cinnabarLastFallout="CATA_"..catastrophe
                      applyCatastrophe(game,host,donor,catastrophe)
                      pushCatastropheAnim(world,party,host,donor,
                        catastrophe,beforeHost,beforeDonor,afterAnim)
                      return
                    end

                    f.paletteSpecies = donorPaletteSpecies
                    f.paletteOverride = copyPalette(donorPaletteOverride)
                    f.history[#f.history + 1] = {
                      kind = "CHROMATIC",
                      donorSpecies = donorSpecies,
                      donorPaletteSpecies = donorPaletteSpecies,
                    }

                    local fallout = chromaticFallout(game, host, donor,
                      donorPaletteSpecies, donorPaletteOverride)
                    world.cinnabarGeneralMutation=rollGeneralMutation(game,host,donor)
                    f.history[#f.history].fallout = fallout.kind
                    world.cinnabarLastFallout = fallout.kind

                    local lab = labState(game)
                    lab.experiments = lab.experiments + 1

                    local Screens = require("src.ui.Screens")
                    Screens.push(game, "CinnabarFusionAnim", {
                      host = host,
                      donor = donor,
                      hostPaletteSpecies = hostPaletteSpecies,
                      hostPaletteOverride = hostPaletteOverride,
                      donorPaletteSpecies = donorPaletteSpecies,
                      donorPaletteOverride = donorPaletteOverride,
                      hostScale = hostScale,
                      donorScale = donorScale,
                      resultPaletteSpecies = fallout.paletteSpecies,
                      resultPaletteOverride = fallout.paletteOverride,
                      resultScale = fallout.scale,
                      resultCrySpecies = (fallout.cryMutation
                        and fallout.cryMutation.species)
                        or effectiveCrySpecies(host),
                      resultCryPitch = (fallout.cryMutation
                        and fallout.cryMutation.pitch)
                        or ((cryMutation(host) and cryMutation(host).pitch) or 1),
                      fragmentSpecies = fallout.fragmentSpecies,
                      fragment = fallout.fragment,
                      onDone = function()
                        local function finishReport()
                          showNatural(world,
                            "FUSION STABILITY: " .. stabilityReport(f.stability),
                            afterAnim)
                        end

                        if fallout.kind == "NONE" then
                          showNatural(world,
                            string.format("%s inherited the DONOR color profile.", hostName),
                            finishReport)
                        else
                          chromaticFalloutText(world, fallout, function()
                            showNatural(world,
                              "The splice completed, but not as planned.",
                              finishReport)
                          end)
                        end
                      end,
                    })
                  end)
                end)
              end)
          end)
        end)
      end)
    end)
  end

  mod.hooks:wrap("ui.party.submenu", function(nextFn, game, items, mon, ctx)
    if not splicePickMode or (ctx and ctx.battle) then
      return nextFn(game, items, mon, ctx)
    end

    nextFn(game, items, mon, ctx)
    return {
      { id="STATS", label="STATS" },
      { label="CHOOSE",
        onSelect=function(chosen)
          local top = game and game.stack and game.stack:top()
          if top and top.onChoose then
            top.onChoose(top.index, chosen)
          end
        end },
      { label="CANCEL",
        onSelect=function()
          local top = game and game.stack and game.stack:top()
          if top and top.onCancel then top.onCancel() end
        end },
    }
  end, 0, "cinnabar_splice_picker")

  local OC = require("src.world.OverworldController")
  local downstream = OC.interact
  OC.interact = function(ow)
    local p = ow and ow.player

    -- DEV21 pink-door diagnostic:
    -- In the main lab, press A while facing the pink door (or any nearby tile).
    -- We report:
    --   player cell
    --   faced cell
    --   4x4 block coordinate containing the faced cell
    --   block ID currently occupying that block
    if p and ow.map and ow.map.id == LAB_MAIN
        and mod.options:get("door_diag")
        and not p.moving then
      local delta = {up={0,-1},down={0,1},left={-1,0},right={1,0}}
      local dd = delta[p.facing]
      if dd then
        local fx, fy = p.cellX + dd[1], p.cellY + dd[2]
        local bx, by = math.floor(fx / 2), math.floor(fy / 2)
        -- Gen II recomp map block coordinates are 2 walk-cells per map block.
        local blockId = nil
        if ow.map.blocks and ow.map.width then
          local idx = by * ow.map.width + bx + 1
          blockId = ow.map.blocks[idx]
        end

        local function hx(v)
          if type(v) ~= "number" then return "??" end
          return string.format("$%02X", v)
        end

        ow:showText(
          string.format("PLAYER %d,%d\nFACE %d,%d", p.cellX, p.cellY, fx, fy),
          function()
            ow:showText(
              string.format("BLOCK %d,%d\nID %s", bx, by, hx(blockId))
            )
          end
        )
        return true
      end
    end
    if p and ow.map and not p.moving then
      local delta = {up={0,-1},down={0,1},left={-1,0},right={1,0}}
      local dd = delta[p.facing]
      if dd then
        local fx, fy = p.cellX + dd[1], p.cellY + dd[2]

        if ow.map.id == CINNABAR then
          if fx == SIGN_X and fy == SIGN_Y then
            ow:showText("CINNABAR ISLAND", function()
              ow:showText("The research lab\nis being rebuilt.", function()
                ow:showText("Enter through the\nnorthern cave.")
              end)
            end)
            return true
          end
          if fx == CAVE_CELL_X and fy == CAVE_CELL_Y then
            -- Enter on the broad central floor instead of the source map's
            -- tucked-away lower-left administration exit.
            warp(LAB_MAIN, MAIN_ENTRY_X, MAIN_ENTRY_Y, "up")
            return true
          end

        elseif ow.map.id == LAB_MAIN then
          -- Lead researcher behind the left desk. The player talks through
          -- the counter front tile at (7,8); scientist is at (7,7).
          -- Lead researcher behind the left desk. After onboarding,
          -- he becomes the lab's information / stability NPC.
          if fx == 7 and fy == 8 then
            faceNpcAt(ow, 7, 7)
            local lab = labState(ow.game)

            local function explainLab()
              local pages={
                "We study controlled POKéMON variation. Each splice needs a HOST and a DONOR. " ..
                "Your HOST is the POKéMON that comes back. The DONOR provides the altered trait. " ..
                "Repeated splicing lowers stability. Push a specimen too far and strange changes may begin."
              }
              if lab.tier>=2 then
                pages[#pages+1]=
                  "TIER 2 unlocked MOVE SPLICING. We can transplant one move from the DONOR into the HOST."
              end
              if lab.tier>=3 then
                pages[#pages+1]=
                  "TIER 3 unlocked STAT SPLICING. We can transplant underlying stat potential without copying the DONOR's level."
              end
              if lab.tier>=4 then
                pages[#pages+1]=
                  "TIER 4 unlocked TYPE SPLICING. We can transplant a DONOR type into one HOST type slot. The change belongs to that individual POKéMON, not the species as a whole."
              end
              if lab.tier>=5 then
                pages[#pages+1]=
                  "TIER 5 brings the HOLON COLLIDER online. That machine does not respect ordinary research boundaries."
              end
              local i=1
              local function nextPage()
                if i>#pages then return end
                local text=pages[i]
                i=i+1
                showNatural(ow,text,nextPage)
              end
              nextPage()
            end

            local function explainProgress()
              if lab.tier <= 1 then
                local left=math.max(0,10-(lab.experiments or 0))
                local money=(ow.game.save.player and ow.game.save.player.money) or 0
                if left>0 then
                  showNatural(ow,
                    string.format(
                      "We're still gathering data for TIER 2. We need %d more successful experiments. The expansion will also require ¥10000.",left))
                elseif money<10000 then
                  showNatural(ow,
                    "Our TIER 2 research data is complete. We still need ¥10000 in expansion funding.")
                else
                  showNatural(ow,
                    "We have everything we need. The TIER 2 expansion will cost ¥10000 in funding.",
                    function()
                      showNatural(ow,"Spend ¥10000 and authorize the expansion?",function()
                        ow:askYesNo(function(yes)
                          if not yes then return end
                          -- Payment happens immediately after confirmation.
                          ow.game.save.player.money=math.max(0,money-10000)
                          lab.tier=2
                          lab.tier2Funded=true
                          -- Object const 6 is the annex researcher.
                          if ow.appearObject then ow:appearObject(6) end
                          local Screens=require("src.ui.Screens")
                          Screens.push(ow.game,"CinnabarUpgradeAnim",{
                            onDone=function()
                              showNatural(ow,
                                "Construction complete! FACILITY TIER 2 is now online. Move splicing is cleared for testing.",
                                function()
                                  -- Current Crystal audio uses actual Gen2 SFX
                                  -- labels, not Gen1's Get_Item1 alias. Clear any
                                  -- lingering construction SFX, then use the
                                  -- stereo path to bypass the normal priority
                                  -- gate. Sfx_GetBadge is a native celebratory
                                  -- fanfare in Crystal and ducks map music.
                                  local Sound=require("src.core.Sound")
                                  pcall(Sound.waitSfxDone)
                                  pcall(Sound.playStereo,ow.game.data,"Sfx_GetBadge")
                                  showNatural(ow,
                                    "The annex is unlocked as well. We're finally starting to look like a real laboratory.")
                                end)
                            end,
                          })
                        end)
                      end)
                    end)
                end
              elseif lab.tier==2 then
                local left=math.max(0,25-(lab.experiments or 0))
                local money=(ow.game.save.player and ow.game.save.player.money) or 0
                if left>0 then
                  showNatural(ow,string.format(
                    "TIER 3 needs %d more successful experiments and ¥25000 in expansion funding.",left))
                elseif money<25000 then
                  showNatural(ow,"Our TIER 3 data is ready. We still need ¥25000 in expansion funding.")
                else
                  showNatural(ow,"TIER 3 is ready. The expansion will cost ¥25000.",function()
                    showNatural(ow,"Spend ¥25000 and authorize the expansion?",function()
                      ow:askYesNo(function(yes)
                        if not yes then return end
                        ow.game.save.player.money=math.max(0,money-25000)
                        lab.tier=3
                        if ow.appearObject then ow:appearObject(7) end
                        local Screens=require("src.ui.Screens")
                        Screens.push(ow.game,"CinnabarUpgradeAnim",{
                          onDone=function()
                            showNatural(ow,
                              "Construction complete! FACILITY TIER 3 is now online. Stat splicing is cleared for testing.",
                              function()
                                local Sound=require("src.core.Sound")
                                pcall(Sound.waitSfxDone)
                                pcall(Sound.playStereo,ow.game.data,"Sfx_GetBadge")
                                showNatural(ow,"A new stat researcher has joined the annex.")
                              end)
                          end})
                      end)
                    end)
                  end)
                end
              elseif lab.tier==3 then
                local left=math.max(0,40-(lab.experiments or 0))
                local money=(ow.game.save.player and ow.game.save.player.money) or 0
                if left>0 then
                  showNatural(ow,string.format(
                    "TIER 4 needs %d more successful experiments and ¥50000 in expansion funding.",left))
                elseif money<50000 then
                  showNatural(ow,"Our TIER 4 research is ready. We still need ¥50000 in expansion funding.")
                else
                  showNatural(ow,"TIER 4 is ready. The expansion will cost ¥50000.",function()
                    showNatural(ow,"Spend ¥50000 and authorize the expansion?",function()
                      ow:askYesNo(function(yes)
                        if not yes then return end
                        ow.game.save.player.money=math.max(0,money-50000)
                        lab.tier=4
                        local Screens=require("src.ui.Screens")
                        Screens.push(ow.game,"CinnabarUpgradeAnim",{onDone=function()
                          showNatural(ow,
                            "Construction complete! FACILITY TIER 4 is now online. Type splicing is cleared for testing.",
                            function()
                              local Sound=require("src.core.Sound")
                              pcall(Sound.waitSfxDone)
                              pcall(Sound.playStereo,ow.game.data,"Sfx_GetBadge")
                              showNatural(ow,
                                "We can now rewrite an individual POKéMON's type profile without changing its species.")
                            end)
                        end})
                      end)
                    end)
                  end)
                end
              elseif lab.tier==4 then
                local left=math.max(0,60-(lab.experiments or 0))
                local money=(ow.game.save.player and ow.game.save.player.money) or 0
                if left>0 then
                  showNatural(ow,string.format(
                    "TIER 5 needs %d more successful experiments. Final construction will cost ¥75000.",left))
                elseif not lab.typeSpliceCompleted then
                  showNatural(ow,
                    "Our research volume is sufficient, but I need one successful TYPE SPLICE before we proceed.")
                elseif money<75000 then
                  showNatural(ow,
                    "The HOLON COLLIDER plans are ready. We still need ¥75000 in final construction funding.")
                else
                  showNatural(ow,
                    "We have enough data. The final project is the HOLON COLLIDER.",
                    function()
                      showNatural(ow,
                        "Construction will deduct ¥75000. This is the last facility expansion.",
                        function()
                          showNatural(ow,
                            "Spend ¥75000 and authorize TIER 5 construction?",
                            function()
                              ow:askYesNo(function(yes)
                                if not yes then return end
                                ow.game.save.player.money=math.max(0,money-75000)
                                lab.tier=5
                                -- Move the former far-right Collider specialist
                                -- beside the rear-left activation panel.
                                if ow.moveObject then ow:moveObject(4,22,3) end
                                local npc=ow.objectEntity and ow:objectEntity(4)
                                if npc then npc.facing="down" end

                                local Screens=require("src.ui.Screens")
                                Screens.push(ow.game,"CinnabarUpgradeAnim",{onDone=function()
                                  showNatural(ow,
                                    "Construction complete! FACILITY TIER 5 is now online.",
                                    function()
                                      local Sound=require("src.core.Sound")
                                      pcall(Sound.waitSfxDone)
                                      pcall(Sound.playStereo,ow.game.data,"Sfx_GetBadge")
                                      showNatural(ow,
                                        "We did it. With your help, the HOLON COLLIDER is finally back online.",
                                        function()
                                          showNatural(ow,
                                            "Go speak with my associate behind the COLLIDER.",
                                            function()
                                              showNatural(ow,
                                                "He's waiting beside the activation panel.")
                                            end)
                                        end)
                                    end)
                                end})
                              end)
                            end)
                        end)
                    end)
                end
              else
                showNatural(ow,
                  "TIER 5 is online. The HOLON COLLIDER is now our final research platform.")
              end
            end

            local function checkStability()
              local party = ow.game and ow.game.save and ow.game.save.party or {}
              if #party <= 0 then
                ow:showText("Bring me a POKéMON.\nI'll examine it.")
                return
              end
              ow:showText("Choose a POKéMON.\nI'll examine it.", function()
                ow:selectPartyMon("Choose a POKéMON.", function(_, mon)
                  if mon then inspectFusion(ow, mon) end
                end)
              end)
            end

            local function infoMenu()
              ow:showText("Need something?\nAsk away.", function()
                local Screens = require("src.ui.Screens")
                local labels = {
                  "EXPLANATION",
                  "CHECK STABILITY",
                  "LAB PROGRESS",
                  "CANCEL",
                }

                Screens.push(ow.game, "Gen2ScriptMenu", {
                  header = {
                    left = 2,
                    top = 4,
                    right = 19,
                    bottom = 13,
                    items = labels,
                    dataFlags = 0x80,
                    cursor = 1,
                  },
                  style = "vertical",
                  onChoose = function(index)
                    if ow.game and ow.game.stack then
                      ow.game.stack:pop()
                    end

                    if index == 1 then
                      explainLab()
                    elseif index == 2 then
                      checkStability()
                    elseif index == 3 then
                      explainProgress()
                    end
                    -- index 4 or B simply closes the menu.
                  end,
                })
              end)
            end

            infoMenu()
            return true
          end

          -- Stability/explanation sign beside the inaccessible left desk.
          -- Verified by player diagnostic: stand (2,10), face (2,9).
          -- Research sign: intentionally minimal. It only displays
          -- the current facility tier; all explanations live with the lead
          -- researcher behind the left desk.
          if fx == 2 and fy == 9 then
            local lab = labState(ow.game)
            ow:showText(string.format("CINNABAR LAB\nFACILITY TIER %d", lab.tier))
            return true
          end

          -- Middle scientist: main splicer. Ignore A presses while he
          -- is operating/retrieving from the machine.
          if fx == 16 and fy == 8 then
            if fusionBusy then return true end
            faceNpcAt(ow,16,8)
            local lab=labState(ow.game)
            if lab.tier<2 then
              showNatural(ow,
                "Chromatic splicing is ready. Each procedure costs ¥2500.",
                function()
                  showNatural(ow,"Run an experiment?",function()
                    ow:askYesNo(function(yes)
                      if yes then startChromaticSplice(ow) end
                    end)
                  end)
                end)
            else
              showNatural(ow,"Which procedure do you want to run?",function()
                local labels={"CHROMATIC ¥2500","MOVE ¥5000"}
                if lab.tier>=3 then labels[#labels+1]="STAT ¥7500" end
                if lab.tier>=4 then labels[#labels+1]="TYPE ¥10000" end
                labels[#labels+1]="CANCEL"
                chooseScriptMenu(ow,labels,function(index)
                  if index==1 then startChromaticSplice(ow)
                  elseif index==2 then startMoveSplice(ow)
                  elseif index==3 and lab.tier>=3 then startStatSplice(ow)
                  elseif index==4 and lab.tier>=4 then startTypeSplice(ow) end
                end,3,14)
              end)
            end
            return true
          end

          -- Holon Collider specialist. Before Tier 5 he remains at the
          -- far-right station; Tier 5 relocates him beside the activation panel.
          if (labState(ow.game).tier<5 and fx==27 and fy==12)
              or (labState(ow.game).tier>=5 and fx==22 and fy==3) then
            local lab=labState(ow.game)
            if lab.tier<5 then
              faceNpcAt(ow,27,12)
              ow:showText("The HOLON COLLIDER\nis still offline.",function()
                ow:showText("We're working to\nbring it online.")
              end)
            else
              faceNpcAt(ow,22,3)
              if not lab.colliderIntroSeen then
                lab.colliderIntroSeen=true
                showNatural(ow,
                  "So... this is it. The HOLON COLLIDER.",
                  function()
                    showNatural(ow,
                      "It was built to alter POKéMON on a scale we've never attempted.",
                      function()
                        showNatural(ow,
                          "I'm not sure we should turn this thing on.",
                          function()
                            showNatural(ow,
                              "But you've literally bankrolled our careers.",
                              function()
                                showNatural(ow,
                                  "So who am I to argue with you?",
                                  function()
                                    showNatural(ow,
                                      "The activation panel is right beside me.",
                                      function()
                                        showNatural(ow,
                                          "Use it at your own risk. You should probably save first.",
                                          function()
                                            showNatural(ow,"You've been warned.")
                                          end)
                                      end)
                                  end)
                              end)
                          end)
                      end)
                  end)
              else
                local lines={
                  "The COLLIDER is waiting. I still think saving first is a very good idea.",
                  "That panel controls the whole system. Somehow, you also control our budget.",
                  "I ran the numbers again. They did not become more comforting.",
                }
                showNatural(ow,lines[math.random(#lines)])
              end
            end
            return true
          end

          -- Rear-left Holon Collider activation panel.
          -- Verified from the current lab layout: player stands at (14,11)
          -- facing the panel at (14,10). DEV97 intentionally stops after the
          -- double confirmation; the reality-break activation movie comes next.
          if fx==23 and fy==3 then
            if ow.playSfxNamed then ow:playSfxNamed("Sfx_BootPc") end
            local lab=labState(ow.game)
            if lab.tier<5 then
              if lab.tier<=1 then
                showNatural(ow,
                  "COLLIDER OFFLINE.",
                  function()
                    showNatural(ow,
                      "No systems are responding.")
                  end)
              elseif lab.tier==2 then
                showNatural(ow,
                  "COLLIDER OFFLINE.",
                  function()
                    showNatural(ow,
                      "Restoration work is underway.")
                  end)
              elseif lab.tier==3 then
                showNatural(ow,
                  "PARTIAL POWER DETECTED.",
                  function()
                    showNatural(ow,
                      "Core systems are responding.")
                  end)
              else
                showNatural(ow,
                  "COLLIDER STANDBY.",
                  function()
                    showNatural(ow,
                      "Activation controls remain locked.")
                  end)
              end
            elseif lab.colliderChargeHours>0 then
              local days=math.ceil(lab.colliderChargeHours/24)
              ow:showText("COLLIDER OFFLINE.",function()
                ow:showText("ENERGY RECHARGING.",function()
                  ow:showText("ETA: "..tostring(days).." DAYS.")
                end)
              end)
            else
              ow:showText("COLLIDER ONLINE.",function()
                ow:showText("Activate?",function()
                  ow:askYesNo(function(yes)
                    if not yes then return end
                    ow:showText("Are you sure?",function()
                      ow:askYesNo(function(really)
                        if not really then return end
                        local Screens=require("src.ui.Screens")
                        Screens.push(ow.game,"CinnabarColliderAnim",{
                          onDone=function()
                            local lab=labState(ow.game)
                            lab.colliderFired=true
                            -- Seven in-game days exactly.
                            lab.colliderChargeHours=7*24
                            local phenomena=rollColliderEffects(ow.game)
                            lab.colliderLastActivationGeneration=
                              lab.colliderGeneration
                            showNatural(ow,
                              "You're still here. That's encouraging.",
                              function()
                                showNatural(ow,
                                  "Your POKéMON appear unchanged.",
                                  function()
                                    showNatural(ow,
                                      "But every OTHER wild POKéMON...",
                                      function()
                                        showNatural(ow,
                                          "Something happened to them.",
                                          function()
                                            showNatural(ow,
                                              "If you wouldn't mind, we'd love some field data.",
                                              function()
                                                showNatural(ow,
                                                  "The field matrix shows three active phenomena.",
                                                  function()
                                                    local names=colliderSummary(ow.game)
                                                    showNatural(ow,
                                                      (names[1] or "UNKNOWN")..".",
                                                      function()
                                                        showNatural(ow,
                                                          (names[2] or "UNKNOWN")..".",
                                                          function()
                                                            showNatural(ow,
                                                              (names[3] or "UNKNOWN")..".",
                                                              function()
                                                                showNatural(ow,
                                                                  "Go test the results outside.")
                                                              end)
                                                          end)
                                                      end)
                                                  end)
                                              end)
                                          end)
                                      end)
                                  end)
                              end)
                          end
                        })
                      end)
                    end)
                  end)
                end)
              end)
            end
            return true
          end

          -- Tier 2 unlocks the annex.
          if fx == PINK_DOOR_TILE_X and fy == PINK_DOOR_TILE_Y then
            local lab=labState(ow.game)
            if lab.tier<2 then
              ow:showText("The annex is\ncurrently locked.")
            else
              if ow.warpSound then ow:warpSound() end
              warp(LAB_MAIN,COMPUTER_ROOM_ENTRY_X,COMPUTER_ROOM_ENTRY_Y,"down")
            end
            return true
          end

          -- Tier 2 annex researcher at diagnostic facing cell (4,27).
          if fx==4 and fy==27 then
            local lab=labState(ow.game)
            if lab.tier<2 then return true end
            faceNpcAt(ow,4,27)
            if not lab.annexGiftClaimed then
              showNatural(ow,
                "Oh! You're the trainer funding all this? I'm studying how transplanted moves retain usable energy.",
                function()
                  showNatural(ow,
                    "Here. This should help with field testing. Consider it a research expense.",
                    function()
                      local Bag=require("src.inventory.Bag")
                      local ok=Bag.add(ow.game.save,"PP_UP",5,ow.game.data)
                      if ok then
                        lab.annexGiftClaimed=true
                        if ow.playSfxNamed then ow:playSfxNamed("Sfx_Item") end
                        showNatural(ow,"You received 5 PP UPs!")
                      else
                        showNatural(ow,
                          "Your PACK is full. Come back when you can carry the PP UPs.")
                      end
                    end)
                end)
            else
              local lines={
                "Move splicing is fascinating. A move can survive even when the rest of the transfer goes wrong.",
                "I'm logging PP changes after each experiment. Zero is technically a result. Not a useful one.",
                "The annex was empty last week. Give us another tier and this place may actually look staffed.",
              }
              showNatural(ow,lines[math.random(#lines)])
            end
            return true
          end

          -- Tier 3 annex stat researcher, positioned in front of the desk.
          if fx==7 and fy==27 then
            local lab=labState(ow.game)
            if lab.tier<3 then return true end
            faceNpcAt(ow,7,27)
            if not lab.statGiftClaimed then
              showNatural(ow,
                "You're our field tester? Perfect. I model how a splice changes a POKéMON's underlying potential.",
                function()
                  showNatural(ow,"You'll need comparison data. Take this vitamin set.",function()
                    local Bag=require("src.inventory.Bag")
                    local gifts={{"HP_UP",2},{"PROTEIN",2},{"IRON",2},{"CARBOS",2},{"CALCIUM",2}}
                    local added={}
                    for _,g in ipairs(gifts) do
                      if Bag.add(ow.game.save,g[1],g[2],ow.game.data) then added[#added+1]=g end
                    end
                    if #added==#gifts then
                      lab.statGiftClaimed=true
                      if ow.playSfxNamed then ow:playSfxNamed("Sfx_Item") end
                      showNatural(ow,"You received 2 of each stat vitamin!")
                    else
                      -- Avoid duplicate partial grants: mark claimed if anything was added.
                      if #added>0 then lab.statGiftClaimed=true end
                      showNatural(ow,"I added what your PACK could hold. That's your research kit.")
                    end
                  end)
                end)
            else
              local lines={
                "Level changes the final number. I care about the potential underneath it.",
                "A clean stat splice is predictable. An unstable one can redistribute everything.",
                "If a reading looks impossible, write it down before somebody calls it a rounding error.",
              }
              showNatural(ow,lines[math.random(#lines)])
            end
            return true
          end

          -- Tier 4 annex type researcher, final scientist in the computer room.
          if fx==7 and fy==29 then
            local lab=labState(ow.game)
            if lab.tier<4 then return true end
            faceNpcAt(ow,7,29)
            if not lab.typeGiftClaimed then
              showNatural(ow,
                "So you're our field tester. I map how altered type profiles react outside the lab.",
                function()
                  showNatural(ow,
                    "You'll want controlled comparisons. Take this type-testing kit.",
                    function()
                      local Bag=require("src.inventory.Bag")
                      local gifts={
                        {"MAGNET",1},
                        {"SOFT_SAND",1},
                        {"CHARCOAL",1},
                        {"MYSTIC_WATER",1},
                      }
                      local added=0
                      for _,g in ipairs(gifts) do
                        if Bag.add(ow.game.save,g[1],g[2],ow.game.data) then
                          added=added+1
                        end
                      end
                      if added==#gifts then
                        lab.typeGiftClaimed=true
                        if ow.playSfxNamed then ow:playSfxNamed("Sfx_Item") end
                        showNatural(ow,
                          "You received MAGNET, SOFT SAND, CHARCOAL, and MYSTIC WATER!")
                      elseif added>0 then
                        lab.typeGiftClaimed=true
                        showNatural(ow,
                          "I added what your PACK could hold. That's your type-testing kit.")
                      else
                        showNatural(ow,
                          "Your PACK is full. Come back when you have room for the testing kit.")
                      end
                    end)
                end)
            else
              local lines={
                "A type splice belongs to the individual. The species itself stays unchanged.",
                "Dual typing is where this gets interesting. One altered slot can rewrite an entire matchup.",
                "If a POKéMON already has the donor type, there is nothing useful for us to transplant.",
                "Keep notes on weaknesses after a splice. The battle data matters more than the label.",
              }
              showNatural(ow,lines[math.random(#lines)])
            end
            return true
          end

          -- Game Boy Kid: short random two-line remarks only.
          -- Each facility tier adds fresh lines without removing the old ones.
          if fx == 10 and fy == 12 then
            faceNpcAt(ow, 10, 12)
            local lab=labState(ow.game)
            local lines = {
              {"My dad works here.", "I hang out here."},
              {"Dad says not to", "touch machines."},
              {"I brought my", "GAME BOY today."},
              {"I beat the GYM", "while Dad worked."},
              {"Scientists talk", "about cells a lot."},
              {"Dad says the", "collider is scary."},
              {"My rival is named", "after Dad's boss."},
              {"Can you splice", "MISSINGNO.?"},
            }
            if lab.tier >= 2 then
              lines[#lines+1]={"They hired a new", "scientist today."}
              lines[#lines+1]={"Dad says MOVE", "splicing is safe-ish."}
              lines[#lines+1]={"I asked for FLY.", "Dad said no."}
            end
            if lab.tier >= 3 then
              lines[#lines+1]={"More computers now.", "Still no snacks."}
              lines[#lines+1]={"They keep saying", "stat potential."}
              lines[#lines+1]={"Can you make a", "super-fast SNORLAX?"}
            end
            if lab.tier >= 4 then
              lines[#lines+1]={"Dad says TYPE", "splicing is huge."}
              lines[#lines+1]={"Can PONYTA be", "WATER type now?"}
              lines[#lines+1]={"I asked for a", "GHOST MAGIKARP."}
            end
            if lab.tier >= 5 then
              lines[#lines+1]={"They fixed the", "big machine."}
              lines[#lines+1]={"Dad said DON'T", "touch the panel."}
              lines[#lines+1]={"Everyone looks", "nervous today."}
              lines[#lines+1]={"If it explodes,", "can I keep a piece?"}
              lines[#lines+1]={"I saved my game.", "You should too."}
            end
            local q = lines[math.random(#lines)]
            ow:showText(q[1] .. "\n" .. q[2])
            return true
          end
        end
      end
    end
    return downstream(ow)
  end


  -- Shared Gen2 individual-type adapter.
  -- syncIdentity normally restores vanilla species types whenever a Pokemon is
  -- opened in menus. Reapply the Cinnabar per-mon override immediately after.
  local Gen2Mon=require("src.battle.gen2.Mon")
  if not Gen2Mon._cinnabarTypeIdentityWrapped then
    Gen2Mon._cinnabarTypeIdentityWrapped=true
    local downstreamSyncIdentity=Gen2Mon.syncIdentity
    Gen2Mon.syncIdentity=function(mon,data)
      local out=downstreamSyncIdentity(mon,data)
      local f=mon and mon.cinnabarFusion
      if f and type(f.typeOverride)=="table" and #f.typeOverride>0 then
        mon.types={}
        for i,t in ipairs(f.typeOverride) do mon.types[i]=t end
      end
      return out
    end
  end

  -- Shared Gen2 stat-override adapter.
  -- Individual broken-level-cap support. Vanilla remains capped at 100.
  cinnabarLevelCap = function(mon)
    local f=mon and mon.cinnabarFusion
    local c=mon and mon.cinnabarCollider
    if (f and tonumber(f.levelCap)==255)
        or (c and c.limitBreak==true) then
      return 255
    end
    return 100
  end

  local function setMutantLevel(mon,level,data)
    if not (mon and data) then return false end
    local cap=cinnabarLevelCap(mon)
    level=math.max(1,math.min(cap,math.floor(tonumber(level) or 1)))
    local def=data.pokemon and data.pokemon[mon.species]
    local growth=Gen2Mon.growthFor(data,def and def.growthRate)
    local oldMax=mon.maxHp or (mon.stats and mon.stats.hp) or 1
    mon.level=level
    mon.experience=Gen2Mon.experienceForLevel(growth,level)
    Gen2Mon.refreshStats(mon,data)
    local newMax=mon.maxHp or (mon.stats and mon.stats.hp) or oldMax
    mon.hp=math.max(0,math.min(newMax,(mon.hp or oldMax)+(newMax-oldMax)))
    return true
  end

  local function mutantGainExperience(mon,amount,data)
    if cinnabarLevelCap(mon)<=100 then return nil end
    local def=data and data.pokemon and data.pokemon[mon.species]
    local growth=Gen2Mon.growthFor(data,def and def.growthRate)
    local before=tonumber(mon.level) or 1
    mon.experience=(tonumber(mon.experience) or 0)+math.max(0,amount or 0)
    local capExp=Gen2Mon.experienceForLevel(growth,255)
    if mon.experience>capExp then mon.experience=capExp end
    local after=before
    while after<255
        and mon.experience>=Gen2Mon.experienceForLevel(growth,after+1) do
      after=after+1
    end
    if after<=before then return {levels=0,learned={}} end
    local oldMax=mon.maxHp or (mon.stats and mon.stats.hp) or 1
    mon.level=after
    Gen2Mon.refreshStats(mon,data)
    local newMax=mon.maxHp or (mon.stats and mon.stats.hp) or oldMax
    mon.hp=math.max(0,math.min(newMax,(mon.hp or oldMax)+(newMax-oldMax)))
    local learned={}
    for level=before+1,after do
      for _,entry in ipairs((def and def.levelMoves) or {}) do
        if entry.level==level then learned[#learned+1]=entry.move end
      end
    end
    return {levels=after-before,learned=learned}
  end

  -- Summary, Party, PC/battle setup and other Gen2 surfaces all funnel through
  -- Mon.refreshStats, so fused stat potential must be applied there rather
  -- than through the Gen1 Stats.ensure helper.
  if not Gen2Mon._cinnabarStatWrapped then
    Gen2Mon._cinnabarStatWrapped=true
    local downstreamRefreshStats=Gen2Mon.refreshStats
    Gen2Mon.refreshStats=function(mon,data)
      repairMutantExperience(mon,data)
      if mon and mon.cinnabarFusion and mon.cinnabarFusion.statOverrides then
        Gen2Mon.syncIdentity(mon,data)
        local def=data and data.pokemon and data.pokemon[mon.species]
        if def and def.baseStats then
          local bs={}
          for k,v in pairs(def.baseStats) do bs[k]=v end
          for k,v in pairs(mon.cinnabarFusion.statOverrides or {}) do
            if tonumber(v) then bs[k]=tonumber(v) end
          end
          local oldMax=mon.maxHp or (mon.stats and mon.stats.hp)
          local stats=Gen2Mon.stats(bs,mon.dvs or {},mon.level or 1,
            mon.statExp or {})
          mon.stats=stats
          mon.maxHp=stats.hp
          if mon.hp==nil then
            mon.hp=stats.hp
          elseif oldMax and stats.hp~=oldMax then
            mon.hp=math.max(0,math.min(stats.hp,
              mon.hp+(stats.hp-oldMax)))
          else
            mon.hp=math.max(0,math.min(mon.hp,stats.hp))
          end
          return mon
        end
      end
      return downstreamRefreshStats(mon,data)
    end

    -- Level-up recalculates directly instead of calling refreshStats.
    local downstreamGainExperience=Gen2Mon.gainExperience
    Gen2Mon.gainExperience=function(mon,amount,data)
      repairMutantExperience(mon,data)
      local oldLevel=mon and tonumber(mon.level) or nil
      local mutantOut=mutantGainExperience(mon,amount,data)
      local out=mutantOut or downstreamGainExperience(mon,amount,data)
      local c=mon and mon.cinnabarCollider
      if c and c.moveCollapse and out and tonumber(out.to) then
        local learned={}
        for level=(tonumber(out.from) or oldLevel or 1)+1,tonumber(out.to) do
          local at=collapsedMovesAtLevel(mon,level)
          for _,id in ipairs(at) do learned[#learned+1]=id end
        end
        out.learned=learned
      end
      local f=mon and mon.cinnabarFusion
      if f and f.statOverrides then Gen2Mon.refreshStats(mon,data) end
      -- Corrupted next-level evolution is handled by the real Gen2 Evolution
      -- pipeline below. That catches BOTH battle level-ups and Rare Candy,
      -- and preserves the normal "What? X is evolving!" movie.
      return out
    end
  end

  -- Rare Candy normally refuses at level 100. Current Gen1Recomp resolves
  -- item effects through ItemEffects.recordFor(), preferring the merged
  -- data.gen2ItemEffects registry over ItemEffects.RECORDS. Wrap that central
  -- resolver so the LV255 behavior actually reaches the Bag/Party item path.
  local Gen2ItemEffects=require("src.core.gen2.ItemEffects")
  if not Gen2ItemEffects._cinnabarLevelCandyWrapped then
    Gen2ItemEffects._cinnabarLevelCandyWrapped=true
    local downstreamRecordFor=Gen2ItemEffects.recordFor
    Gen2ItemEffects.recordFor=function(itemId,data)
      local vanilla=downstreamRecordFor(itemId,data)
      if itemId~="RARE_CANDY" then return vanilla end
      return {
        action=(vanilla and vanilla.action) or "candy",
        field=true,
        needsTarget=true,
        use=function(ctx)
          local mon=ctx and ctx.mon
          local data=ctx and ctx.data
          if not mon then
            if vanilla and vanilla.use then return vanilla.use(ctx) end
            return {used=false,text="It won't have any effect."}
          end

          local c=mon.cinnabarCollider
          local moveCollapse=c and c.moveCollapse
          local cap=cinnabarLevelCap(mon)
          local before=tonumber(mon.level) or 1

          -- Ordinary non-Cinnabar mons stay completely vanilla below 100.
          if not moveCollapse and cap<=100 and before<100 then
            if vanilla and vanilla.use then return vanilla.use(ctx) end
            return {used=false,text="It won't have any effect."}
          end

          if before>=cap then
            return {used=false,text="It won't have any effect."}
          end

          local def=data and data.pokemon and data.pokemon[mon.species]
          local growth=Gen2Mon.growthFor(data,def and def.growthRate)
          local oldMax=mon.maxHp or (mon.stats and mon.stats.hp) or 1
          local newLevel=before+1

          mon.level=newLevel
          mon.experience=Gen2Mon.experienceForLevel(growth,newLevel)
          Gen2Mon.refreshStats(mon,data)
          local newMax=mon.maxHp or (mon.stats and mon.stats.hp) or oldMax
          mon.hp=math.max(0,math.min(newMax,
            (mon.hp or oldMax)+(newMax-oldMax)))

          local learned={}
          if moveCollapse then
            learned=collapsedMovesAtLevel(mon,newLevel)
          else
            for _,entry in ipairs((def and def.levelMoves) or {}) do
              if entry.level==newLevel then learned[#learned+1]=entry.move end
            end
          end

          return {
            used=true,
            level=newLevel,
            learned=learned,
            sfx="Sfx_DexFanfare5079",
            text=(mon.nickname or mon.name or mon.species or "POKéMON")
              .." grew to\nlevel "..tostring(newLevel).."!",
          }
        end,
      }
    end
  end

  -- Gen2 Evolution.apply rebuilds the evolved record through Mon.new.
  -- Mon.new intentionally clamps its input to Mon.MAX_LEVEL (100), so a
  -- LIMIT BREAK mon at 101+ was silently rebuilt as level 100. Wrap the
  -- evolution builder and restore the individual's true extended level after
  -- the native evolution has copied all persistent custom fields.
  local Evolution=require("src.core.gen2.Evolution")
  if not Evolution._cinnabarLimitBreakWrapped then
    Evolution._cinnabarLimitBreakWrapped=true
    local downstreamEvolutionApply=Evolution.apply
    Evolution.apply=function(data,mon,entry)
      local c=mon and mon.cinnabarCollider
      local trueLevel=mon and tonumber(mon.level) or 1
      local trueExperience=mon and tonumber(mon.experience)
      local needsExtended=c and c.limitBreak and trueLevel>100
      if not needsExtended then
        return downstreamEvolutionApply(data,mon,entry)
      end

      -- Native apply must see a builder-safe level, but keep the original
      -- party record untouched for every other persistent field.
      local savedLevel=mon.level
      local savedExperience=mon.experience
      mon.level=100
      local evolved=downstreamEvolutionApply(data,mon,entry)
      mon.level=savedLevel
      mon.experience=savedExperience

      if not evolved then return nil end

      evolved.level=trueLevel
      evolved.cinnabarCollider=evolved.cinnabarCollider or c
      evolved.cinnabarCollider.limitBreak=true
      evolved.cinnabarCollider.levelCap=255

      local def=data and data.pokemon and data.pokemon[evolved.species]
      local growth=Gen2Mon.growthFor(data,def and def.growthRate)
      -- Preserve the exact pre-evolution EXP when it is valid on the new
      -- growth curve; otherwise normalize to the new species' current level.
      local base=growth and Gen2Mon.experienceForLevel(growth,trueLevel)
      local next_=growth and trueLevel<255
        and Gen2Mon.experienceForLevel(growth,trueLevel+1) or nil
      if trueExperience and base
          and trueExperience>=base
          and (not next_ or trueExperience<next_) then
        evolved.experience=trueExperience
      elseif base then
        evolved.experience=base
      else
        evolved.experience=trueExperience
      end
      Gen2Mon.refreshStats(evolved,data)
      evolved.hp=math.max(0,math.min(evolved.hp or evolved.maxHp,evolved.maxHp))
      return evolved
    end
  end

  -- General mutation: corrupted next-level evolution.
  -- Route it through Crystal's real Evolution.checkMon/apply path so Rare
  -- Candy, battle EXP, evolution text, animation, cry, and post-evolution
  -- bookkeeping all behave like a native evolution.
  local Gen2Evolution=require("src.core.gen2.Evolution")
  if not Gen2Evolution._cinnabarCorruptEvolutionWrapped then
    Gen2Evolution._cinnabarCorruptEvolutionWrapped=true

    local downstreamCheckMon=Gen2Evolution.checkMon
    Gen2Evolution.checkMon=function(data,mon,ctx)
      local f=mon and mon.cinnabarFusion
      local target=f and f.nextEvolutionSpecies

      -- Stone/trade/forced checks are not "the next level" and must retain
      -- their vanilla behavior.
      local nonLevelCheck=ctx and (ctx.force or ctx.item or ctx.link)
      if target and not nonLevelCheck and data and data.pokemon
          and data.pokemon[target] then
        return {
          method=Gen2Evolution.LEVEL,
          into=target,
          level=tonumber(mon.level) or 1,
          cinnabarCorruptEvolution=true,
        },false
      end
      return downstreamCheckMon(data,mon,ctx)
    end

    local downstreamApply=Gen2Evolution.apply
    Gen2Evolution.apply=function(data,mon,entry,...)
      local target=entry and entry.into
      local corrupted=entry and entry.cinnabarCorruptEvolution

      -- Evolution builds a fresh Gen2 mon record. Preserve Cinnabar's
      -- individual mutation payload explicitly rather than relying on the
      -- engine's generic unknown-field copy.
      local savedFusion=mon and mon.cinnabarFusion and deep(mon.cinnabarFusion)
      or nil
      local oldFragment= savedFusion and savedFusion.fragment
      local evolved=downstreamApply(data,mon,entry,...)

      if evolved and savedFusion then
        evolved.cinnabarFusion=savedFusion
        local f=evolved.cinnabarFusion

        -- Palette, size, cry, level cap and history are species-independent
        -- individual mutations and ride forward unchanged.

        -- A donor fragment's destination geometry IS host-species dependent.
        -- Re-profile its placement for the evolved body's new front sprite
        -- while keeping the same donor anatomy source.
        if f.fragmentSpecies then
          local donorScale=tonumber(oldFragment and oldFragment.donorScale) or 1
          f.fragment=makeAnatomicalFragment(
            data,evolved.species,f.fragmentSpecies,true,donorScale)
        end

        -- Explicit Type Splicing survives evolution. Natural typing changes
        -- only when this individual has no type override.
        if type(f.typeOverride)=="table" and #f.typeOverride>0 then
          evolved.types={}
          for i,t in ipairs(f.typeOverride) do evolved.types[i]=t end
        end

        -- Explicit Stat Splicing survives evolution too, but must be
        -- recalculated against the evolved record at its current level.
        -- Our mutation-aware refreshStats handles those overrides.
        Gen2Mon.refreshStats(evolved,data)

        if corrupted then
          f.nextEvolutionSpecies=nil
          f.history=f.history or {}
          f.history[#f.history+1]={
            kind="GENERAL_EVOLUTION",
            species=target,
          }
        end
      elseif evolved and corrupted then
        local f=evolved.cinnabarFusion
        if f then
          f.nextEvolutionSpecies=nil
          f.history=f.history or {}
          f.history[#f.history+1]={
            kind="GENERAL_EVOLUTION",
            species=target,
          }
        end
      end

      return evolved
    end
  end

  -- EVOLUTION CASCADE: a caught affected individual changes into a
  -- deterministic random valid species every time it gains a level.
  -- The species is the shell; persistent Collider/Lab mutations belong to the
  -- individual and ride through the transformation.
  if not Gen2Evolution._cinnabarEvolutionCascadeWrapped then
    Gen2Evolution._cinnabarEvolutionCascadeWrapped=true

    local downstreamCascadeCheck=Gen2Evolution.checkMon
    local downstreamCascadeApply=Gen2Evolution.apply

    local function cascadeTarget(data,mon,level)
      local c=mon and mon.cinnabarCollider
      if not (c and c.evolutionCascade) then return nil end
      local ids=colliderSpeciesIds(data)
      if #ids<=1 then return nil end
      local seed=tonumber(c.cascadeSeed) or 1
      local h=colliderHash(
        tostring(seed).."|LV|"..tostring(level).."|"..tostring(mon.species),
        seed)
      local start=(h%#ids)+1
      for offset=0,#ids-1 do
        local id=ids[((start-1+offset)%#ids)+1]
        if id~=mon.species then return id end
      end
      return nil
    end

    Gen2Evolution.checkMon=function(data,mon,ctx)
      local c=mon and mon.cinnabarCollider
      if not (c and c.evolutionCascade) then
        return downstreamCascadeCheck(data,mon,ctx)
      end

      -- Stones/trades/forced evolution remain explicit player actions and
      -- retain their native behavior. Cascade owns ordinary level evolution.
      local nonLevelCheck=ctx and (ctx.force or ctx.item or ctx.link)
      if nonLevelCheck then return downstreamCascadeCheck(data,mon,ctx) end

      -- A one-time laboratory "next evolution" corruption gets one chance to
      -- fire before the permanent Collider cascade resumes on later levels.
      local f=mon and mon.cinnabarFusion
      if f and f.nextEvolutionSpecies then
        local existing,consume=downstreamCascadeCheck(data,mon,ctx)
        if existing and existing.cinnabarCorruptEvolution then
          return existing,consume
        end
      end

      local level=tonumber(mon.level) or 1
      local last=tonumber(c.cascadeLastLevel) or level
      if level<=last then
        -- Prevent summary/menu checks from repeatedly evolving the same level.
        return nil,false
      end

      local target=cascadeTarget(data,mon,level)
      if not target then return nil,false end

      c.pendingCascadeLevel=level
      c.pendingCascadeSpecies=target
      return {
        method=Gen2Evolution.LEVEL,
        into=target,
        level=level,
        cinnabarEvolutionCascade=true,
      },false
    end

    Gen2Evolution.apply=function(data,mon,entry,...)
      local isCascade=entry and entry.cinnabarEvolutionCascade
      if not isCascade then
        return downstreamCascadeApply(data,mon,entry,...)
      end

      local fromSpecies=mon and mon.species
      local level=tonumber(mon and mon.level) or 1
      local savedCollider=mon and mon.cinnabarCollider
        and deep(mon.cinnabarCollider) or nil
      local savedFusion=mon and mon.cinnabarFusion
        and deep(mon.cinnabarFusion) or nil
      local savedShiny=mon and mon.shiny

      local evolved=downstreamCascadeApply(data,mon,entry,...)
      if not evolved then return nil end

      -- Explicitly restore the complete INDIVIDUAL mutation payload. The
      -- engine already carries unknown fields, but this contract prevents a
      -- future engine field list from silently eating Collider inheritance.
      if savedCollider then
        evolved.cinnabarCollider=savedCollider
        local c=evolved.cinnabarCollider
        c.evolutionCascade=true
        c.cascadeLastLevel=level
        c.pendingCascadeLevel=nil
        c.pendingCascadeSpecies=nil
        c.cascadeHistory=type(c.cascadeHistory)=="table"
          and c.cascadeHistory or {}
        c.cascadeHistory[#c.cascadeHistory+1]={
          level=level,
          from=fromSpecies,
          into=evolved.species,
        }

        -- PRISMA is a true persistent shiny property. The original forced
        -- shiny may not be encoded in DVs, so evolution must not reroll it.
        if c.prisma then evolved.shiny=true
        elseif savedShiny~=nil then evolved.shiny=savedShiny end
      end

      if savedFusion then
        evolved.cinnabarFusion=savedFusion
        local f=evolved.cinnabarFusion

        -- STAT DISTORTION is an individual physiology. Reassert the Collider
        -- profile after a species-shell change even if other fusion history
        -- also exists.
        local ec=evolved.cinnabarCollider
        if ec and ec.statDistortion and type(ec.statProfile)=="table" then
          f.statOverrides={}
          for k,v in pairs(ec.statProfile) do f.statOverrides[k]=v end
        end

        -- Re-profile donor anatomy for the new body while preserving the
        -- donor source, palette, size, cry, stat splice, etc.
        if f.fragmentSpecies then
          local oldFragment=savedFusion.fragment
          local donorScale=tonumber(oldFragment and oldFragment.donorScale) or 1
          f.fragment=makeAnatomicalFragment(
            data,evolved.species,f.fragmentSpecies,true,donorScale)
        end

        -- HOLON TYPING / explicit type splice stays with the individual.
        -- Without a type override, Evolution.apply's new-species types remain.
        if type(f.typeOverride)=="table" and #f.typeOverride>0 then
          evolved.types={}
          for i,t in ipairs(f.typeOverride) do evolved.types[i]=t end
        end
      end

      -- LIMIT BREAK, stat splice and any future individual stat profile are
      -- all respected by the shared mutation-aware stat refresh.
      Gen2Mon.refreshStats(evolved,data)
      return evolved
    end
  end

  -- Individual Type Splicing adapter for the Gen2 battle engine.
  local Gen2Battle=require("src.battle.gen2.Battle")
  if not Gen2Battle._cinnabarTypeWrapped then
    Gen2Battle._cinnabarTypeWrapped=true
    local downstreamSpeciesDef=Gen2Battle.speciesDef
    Gen2Battle.speciesDef=function(battle,mon)
      local def=downstreamSpeciesDef(battle,mon)
      local f=mon and mon.cinnabarFusion
      if not (def and f and type(f.typeOverride)=="table"
          and #f.typeOverride>0) then return def end
      local overlay={}
      for k,v in pairs(def) do overlay[k]=v end
      overlay.types={}
      for i,t in ipairs(f.typeOverride) do overlay.types[i]=t end
      return overlay
    end
  end

  -- Collider encounter field. This hook is Gen2's canonical species/level
  -- seam and therefore covers ordinary grass/water/script encounter rolls.
  mod.hooks:wrap("encounter.species",function(next,enc,ctx)
    local out=next(enc,ctx)
    if type(out)~="table" then return out end
    local game=(ctx and ctx.world and ctx.world.game) or nil
    -- World does not currently put itself in ctx, so use the live Gen2 world
    -- installed by the mod's warp helper when available.
    game=game or (_G.Game and _G.Game.save and _G.Game) or nil
    if not game then return out end
    local changed=false
    local copy
    local function writable()
      if copy then return copy end
      copy={}
      for k,v in pairs(out) do copy[k]=v end
      out=copy
      return copy
    end

    if hasColliderEffect(game,"WILD_SHUFFLE") and out.species then
      writable().species=shuffledWildSpecies(game,out.species,ctx)
      changed=true
    end
    if hasColliderEffect(game,"LEVEL_CASCADE") then
      writable().level=100
      changed=true
    end
    return out
  end,40,"cinnabar_collider_encounter")

  -- PRISMA is safe and global through the native Gen2 shiny seam. It only
  -- affects newly-built wild candidates while a Collider field is active.
  mod.hooks:wrap("shiny.roll",function(next,ctx)
    local base=next(ctx)
    local game=_G.Game
    if game and hasColliderEffect(game,"PRISMA") then return true end
    return base
  end,40,"cinnabar_collider_prisma")

  -- LOCKDOWN uses the battle's native escape hook. Trainer battles are never
  -- changed; only wild battles generated while the field is active are pinned.
  mod.hooks:wrap("battle.run",function(next,ctx)
    local battle=ctx and ctx.battle
    local game=_G.Game
    if game and battle and battle.wild and hasColliderEffect(game,"LOCKDOWN") then
      return false
    end
    return next(ctx)
  end,40,"cinnabar_collider_lockdown")

  -- Refresh cached battler types on the shared damage seam too.
  mod.hooks:wrap("battle.damage",function(next,ctx)
    local function apply(b)
      local mon=b and (b.mon or b)
      local f=mon and mon.cinnabarFusion
      if b and f and type(f.typeOverride)=="table"
          and #f.typeOverride>0 and b.curTypes then
        b.curTypes={}
        for i,t in ipairs(f.typeOverride) do b.curTypes[i]=t end
      end
    end
    apply(ctx and ctx.user)
    apply(ctx and ctx.target)
    return next(ctx)
  end,50)

  -- DEV10 hub navigation. Intercept movement before collision so the red
  -- threshold, decorative doorway, and staircase can function as real exits
  -- without rewriting the PokeCom blockset.
  local World2 = require("src.world.gen2.World")

  -- Gen2's enemy HUD places the gender glyph immediately after the two normal
  -- level digit cells. At level 100 the third digit occupies that same cell,
  -- so the gender icon overwrites the final zero and visually reads as Lv10.
  -- Hide ONLY that gender glyph for 3-digit levels; the actual level remains
  -- 100 and the HUD can now show all three digits correctly.
  do
    local BattleUi=require("src.ui.gen2.BattleState")
    if BattleUi and not BattleUi._cinnabarThreeDigitLevelHud then
      BattleUi._cinnabarThreeDigitLevelHud=true
      local downstreamGender=BattleUi.genderSymbol
      BattleUi.genderSymbol=function(ui,mon,...)
        if mon and tonumber(mon.level) and tonumber(mon.level)>=100 then
          return nil
        end
        return downstreamGender(ui,mon,...)
      end
    end
  end

  -- DEV109: Collider field behavior must read the LIVE world's save directly.
  -- DEV108's generic hook path tried to discover the Game through _G.Game,
  -- which current Gen1Recomp does not guarantee, so the rolled effects were
  -- saved/announced but never reached actual encounters or battles.
  if not World2._cinnabarColliderRuntimeWrapped then
    World2._cinnabarColliderRuntimeWrapped=true

    local downstreamRollEncounter=World2.rollEncounter
    World2.rollEncounter=function(world,kind,terrain,tables,vanilla)
      local out=downstreamRollEncounter(world,kind,terrain,tables,vanilla)
      if type(out)~="table" then return out end
      local game=world and world.game
      if not game then return out end

      local changed=false
      local copy
      local function writable()
        if copy then return copy end
        copy={}
        for k,v in pairs(out) do copy[k]=v end
        out=copy
        return copy
      end

      if hasColliderEffect(game,"WILD_SHUFFLE") and out.species then
        writable().species=shuffledWildSpecies(game,out.species,{
          mapId=world.map and world.map.id,
          terrain=terrain,
          kind=kind,
        })
        changed=true
      end

      if hasColliderEffect(game,"LEVEL_CASCADE") then
        writable().level=100
        changed=true
      end

      return out
    end

    local downstreamStartBattle=World2.startBattle
    World2.startBattle=function(world,opts,onDone)
      local game=world and world.game
      if game and type(opts)=="table" and opts.wild and not opts.trainer then
        -- Copy the options table so a scripted caller's reusable table is not
        -- permanently altered by a temporary Collider field.
        local altered={}
        for k,v in pairs(opts) do altered[k]=v end
        opts=altered

        local wild=opts.wild

        if hasColliderEffect(game,"STAT_DISTORTION") then
          -- Give this individual a persistent alternate base-stat profile.
          stampStatDistortion(game,wild)
        end

        if hasColliderEffect(game,"EVOLUTION_CASCADE") then
          -- Arm this individual for a random species mutation on every
          -- subsequent level gained. The capture level itself does not count.
          stampEvolutionCascade(game,wild)
        end

        if hasColliderEffect(game,"LIMIT_BREAK") then
          -- LIMIT BREAK changes this individual's permanent growth ceiling;
          -- it does not alter the encounter's current level.
          stampLimitBreak(game,wild)
        end

        if hasColliderEffect(game,"MOVE_COLLAPSE") then
          -- Build the individual's randomized learnset/current moves first.
          stampMoveCollapse(game,wild)
        end

        if hasColliderEffect(game,"VOLATILE_ECOSYSTEM") then
          -- Apply after MOVE COLLAPSE so EXPLOSION is always guaranteed in
          -- the final battle moveset when both phenomena roll together.
          stampVolatileEcosystem(game,wild)
        end

        if hasColliderEffect(game,"CHROMATIC_FIELD") then
          -- Persistent individual palette mutation. This deliberately writes
          -- Cinnabar's existing paletteOverride, which is used for BOTH front
          -- and back mutation-aware sprite rendering. If PRISMA is also active
          -- below, mon.shiny remains true (sparkle/status) while this palette
          -- wins visually.
          stampChromaticField(game,wild)
        end

        if hasColliderEffect(game,"HOLON_TYPING") then
          -- Stamp the INDIVIDUAL wild mon before Battle.new sees it.
          -- mon.types drives the native Gen2 battle/summary path, while the
          -- existing Cinnabar typeOverride is the persistent fallback used by
          -- the lab's mutation-aware battle seam. If caught, this exact mon
          -- object enters the party/box with the randomized typing intact.
          stampHolonTyping(game,wild)
        end

        if hasColliderEffect(game,"PRISMA") then
          -- Gen2 battle, summary, PC and catch persistence all read mon.shiny.
          -- Stamp the actual wild object, so a catch stays shiny permanently.
          wild.shiny=true
          wild.cinnabarCollider=wild.cinnabarCollider or {}
          wild.cinnabarCollider.prisma=true
          wild.cinnabarCollider.generation=labState(game).colliderGeneration
        end

        if hasColliderEffect(game,"LOCKDOWN") then
          -- BATTLETYPE_TRAP is Crystal's native no-escape battle type. It also
          -- correctly blocks Teleport/Roar escape paths instead of only
          -- failing the RUN menu roll.
          opts.battleType="trap"
        end
      end
      return downstreamStartBattle(world,opts,onDone)
    end
  end

  -- Annex researcher exists in the map definition so Tier 2 can reveal him,
  -- but Tier 1 must never render him. Gen2 object_const 6 maps to object index 5.
  if not World2._cinnabarTierNpcWrapped then
    World2._cinnabarTierNpcWrapped=true
    local downstreamSetMap=World2.setMap
    World2.setMap=function(world,mapId,...)
      local ok=downstreamSetMap(world,mapId,...)
      if ok and mapId==LAB_MAIN then
        local lab=labState(world.game)
        if lab.tier>=2 then world:appearObject(6)
        else world:disappearObject(6) end
        if lab.tier>=3 then world:appearObject(7)
        else world:disappearObject(7) end
        if lab.tier>=4 then world:appearObject(8)
        else world:disappearObject(8) end
        if lab.tier>=5 then
          world:moveObject(4,22,3)
          local colliderNpc=world.objectEntity and world:objectEntity(4)
          if colliderNpc then colliderNpc.facing="down" end
        else
          world:moveObject(4,27,12)
        end
      end
      return ok
    end
  end

  if not World2._cinnabarFacingGuard then
    World2._cinnabarFacingGuard=true
    local downstreamInteractBody=World2.interactBody
    World2.interactBody=function(world,...)
      local p=world and world.player
      if p then
        local facing=p.facing
        if facing~="up" and facing~="down"
            and facing~="left" and facing~="right" then
          p.facing="down"
        end
      end
      return downstreamInteractBody(world,...)
    end
  end

  local downstreamMovePlayer = World2.movePlayer
  World2.movePlayer = function(world, dir)
    local p = world and world.player
    local mapId = world and world.map and world.map.id

    if mod.options:get("dev_money") then
      local save = world and world.game and world.game.save
      if save and save.player then save.player.money = 99999 end
    end

    if p and not p.moving then
      if mapId == LAB_MAIN then
        local lab = labState(world.game)
        if not lab.introComplete
            and p.cellX == MAIN_ENTRY_X and p.cellY == MAIN_ENTRY_Y then
          -- Six upward cells puts the player directly at the front desk.
          moveObj(world, 0,
            {STEP_UP,STEP_UP,STEP_UP,STEP_UP,STEP_UP,STEP_UP,TURN_UP,END},
            function()
              faceNpcAt(world, 7, 7)
              local introText =
                "Ah, a visitor! Perfect timing. I'm heading this new Cinnabar " ..
                "research facility. This island once stood for bold science, " ..
                "and we're rebuilding that legacy from scratch. But we're not " ..
                "here just to repeat old work. We want to learn how far POKéMON " ..
                "can vary. Color is only our first safe test. Later, we hope to " ..
                "alter deeper traits: types, growth, even potential itself. " ..
                "Someday, two members of the same species may be completely " ..
                "different from one another. To reach that point, we need data, " ..
                "specimens, equipment, and unfortunately, a great deal of money."

              showNatural(world, introText, function()
                local function recruit()
                  world:showText("Will you help with\nour research?", function()
                    world:askYesNo(function(yes)
                      if not yes then
                        world:showText("Please reconsider!\nWe need your help.", recruit)
                        return
                      end

                      lab.introComplete = true
                      local acceptText =
                        "Excellent. We'll begin cautiously. Each splice uses two " ..
                        "POKéMON. The HOST is the one you keep afterward, while " ..
                        "the DONOR provides the altered trait. Repeated procedures " ..
                        "reduce stability, so every experiment carries some risk. " ..
                        "Talk to our technician by the splice machine when you're " ..
                        "ready. The research board beside me tracks our progress. " ..
                        "Complete ten successful experiments and raise ¥10000 to " ..
                        "fund our next research tier."
                      showNatural(world, acceptText)
                    end)
                  end)
                end
                recruit()
              end)
            end)
          return "moved"
        end
        -- Internal computer-room red carpet. Standing on the carpet is safe;
        -- pressing Down exits back through the pink doorway.
        if lab.tier>=2 and dir=="down"
            and p.cellY==COMPUTER_ROOM_ENTRY_Y
            and (p.cellX==COMPUTER_ROOM_ENTRY_X
              or p.cellX==COMPUTER_ROOM_ENTRY_X-1) then
          if world.warpSound then world:warpSound() end
          warp(LAB_MAIN,PINK_DOOR_PLAYER_X,PINK_DOOR_PLAYER_Y,"down")
          return "moved"
        end

        -- Main southern doorway -> Cinnabar.
        if dir == "down"
            and p.cellY == EXIT_Y
            and (p.cellX == EXIT_MIN_X or p.cellX == EXIT_MAX_X) then
          if world.warpSound then world:warpSound() end
          warp(CINNABAR, CAVE_CELL_X, CAVE_CELL_Y + 1, "down")
          return "moved"
        end

      elseif mapId == LAB_RESEARCH then
        -- Research room is DEV-only for now. South returns to main entrance.
        if dir == "down"
            and p.cellY == 7
            and (p.cellX == 4 or p.cellX == 5) then
          warp(LAB_MAIN, MAIN_ENTRY_X, MAIN_ENTRY_Y, "down")
          return "moved"
        end

      elseif mapId == LAB_TEST then
        if dir == "down"
            and p.cellY == 7
            and (p.cellX == 4 or p.cellX == 5) then
          warp(LAB_MAIN, MAIN_ENTRY_X, MAIN_ENTRY_Y, "down")
          return "moved"
        end
      end
    end

    return downstreamMovePlayer(world, dir)
  end


end
