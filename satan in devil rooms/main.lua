local mod = RegisterMod('Satan in Devil Rooms', 1)
local json = require('json')
local game = Game()
local music = MusicManager()

mod.isSatanFight = false
mod.onGameStartHasRun = false
mod.gridIndex22 = 22
mod.gridIndex52 = 52
mod.rng = RNG()

mod.difficulty = {
  [Difficulty.DIFFICULTY_NORMAL] = 'normal',
  [Difficulty.DIFFICULTY_HARD] = 'hard',
  [Difficulty.DIFFICULTY_GREED] = 'greed',
  [Difficulty.DIFFICULTY_GREEDIER] = 'greedier'
}
mod.dropTypes = { 'keys only', 'keys then items', 'items only' }

mod.state = {}
mod.state.stageSeeds = {} -- per stage/type
mod.state.devilRooms = {} -- per stage/type
mod.state.fallenAngelDropType = 'keys only'
mod.state.probabilitySatan = { normal = 3, hard = 20, greed = 0, greedier = 0 }

function mod:onGameStart(isContinue)
  local level = game:GetLevel()
  local seeds = game:GetSeeds()
  local stageSeed = seeds:GetStageSeed(level:GetStage())
  mod:setStageSeed(stageSeed)
  mod:clearDevilRooms(false)
  mod:seedRng()
  
  if mod:HasData() then
    local _, state = pcall(json.decode, mod:LoadData())
    
    if type(state) == 'table' then
      if isContinue and type(state.stageSeeds) == 'table' then
        -- quick check to see if this is the same run being continued
        if state.stageSeeds[mod:getStageIndex()] == stageSeed then
          for key, value in pairs(state.stageSeeds) do
            if type(key) == 'string' and math.type(value) == 'integer' then
              mod.state.stageSeeds[key] = value
            end
          end
          if type(state.devilRooms) == 'table' then
            for key, value in pairs(state.devilRooms) do
              if type(key) == 'string' and type(value) == 'table' then
                mod.state.devilRooms[key] = {}
                for k, v in pairs(value) do
                  if type(k) == 'string' and type(v) == 'table' then
                    mod.state.devilRooms[key][k] = {}
                    if type(v['allowed']) == 'boolean' then
                      mod.state.devilRooms[key][k]['allowed'] = v['allowed']
                    end
                    if type(v['completed']) == 'boolean' then
                      mod.state.devilRooms[key][k]['completed'] = v['completed']
                    end
                  end
                end
              end
            end
          end
        end
      end
      if type(state.fallenAngelDropType) == 'string' and mod:getDropTypesIndex(state.fallenAngelDropType) >= 1 then
        mod.state.fallenAngelDropType = state.fallenAngelDropType
      end
      if type(state.probabilitySatan) == 'table' then
        for _, difficulty in ipairs({ 'normal', 'hard', 'greed', 'greedier' }) do
          if math.type(state.probabilitySatan[difficulty]) == 'integer' and state.probabilitySatan[difficulty] >= 0 and state.probabilitySatan[difficulty] <= 100 then
            mod.state.probabilitySatan[difficulty] = state.probabilitySatan[difficulty]
          end
        end
      end
    end
  end
  
  mod.onGameStartHasRun = true
  mod:onNewRoom()
end

function mod:onGameExit()
  mod:SaveData(json.encode(mod.state))
  mod.isSatanFight = false
  mod.onGameStartHasRun = false
  mod:clearStageSeeds()
  mod:clearDevilRooms(true)
end

function mod:onNewLevel()
  local level = game:GetLevel()
  local seeds = game:GetSeeds()
  local stageSeed = seeds:GetStageSeed(level:GetStage())
  mod:setStageSeed(stageSeed)
  mod:clearDevilRooms(false)
end

function mod:onNewRoom()
  if not mod.onGameStartHasRun then
    return
  end
  
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  
  mod.isSatanFight = false
  
  if room:GetType() == RoomType.ROOM_DEVIL then
    mod:setDevilRoomAllowed(roomDesc)
    
    local statues = {}
    local pickups = {}
    
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
      if entity.Type == EntityType.ENTITY_EFFECT and entity.Variant == EffectVariant.DEVIL then
        table.insert(statues, entity)
      elseif entity.Type == EntityType.ENTITY_PICKUP and entity.Variant == PickupVariant.PICKUP_COLLECTIBLE then
        local pickup = entity:ToPickup()
        if pickup.Price ~= 0 and pickup.Price ~= PickupPrice.PRICE_FREE and pickup.Price ~= PickupPrice.PRICE_SPIKES then
          table.insert(pickups, pickup)
        end
      end
    end
    
    -- don't spawn satan in small devil rooms
    if room:GetRoomShape() == RoomShape.ROOMSHAPE_1x1 and #statues == 1 and room:GetGridIndex(statues[1].Position) == mod.gridIndex52 and #pickups > 0 and room:IsClear() and mod:isDevilRoomAllowed(roomDesc) then
      statues[1]:Remove() -- effect
      
      -- devil statue should be at GridIndex(52)
      -- satan needs to go to GridIndex(22) because its base position is 2 spaces higher (52 - 15 - 15 = 22)
      Isaac.Spawn(EntityType.ENTITY_SATAN, 0, 0, room:GetGridPosition(mod.gridIndex22), Vector(0,0), nil)
      mod:closeDoors() -- needed if this is triggered from onGameStart
      mod.isSatanFight = true
      room:SetClear(false)
      mod:showSatanFightText()
    else
      mod:updateGridStatues(statues)
      mod:setDevilRoomAllowed(roomDesc, false)
    end
  end
end

function mod:onUpdate()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  
  if room:GetType() == RoomType.ROOM_DEVIL then
    if mod.isSatanFight then
      if room:IsClear() then
        mod.isSatanFight = false
        mod:setDevilRoomCompleted(roomDesc)
        mod:setPrices()
        mod:playEndingMusic()
      end
    else -- not satan fight
      if mod:isDevilRoomCompleted(roomDesc) then
        mod:setPrices()
      end
    end
  end
end

function mod:onPreEntitySpawn(entityType, variant, subType, position, velocity, spawner, seed)
  local room = game:GetRoom()
  local fallenVariant = 1
  
  if room:GetType() == RoomType.ROOM_DEVIL then
    if (entityType == EntityType.ENTITY_URIEL or entityType == EntityType.ENTITY_GABRIEL) then
      return { entityType, fallenVariant, subType, seed } -- fallen uriel / fallen gabriel
    elseif entityType == EntityType.ENTITY_EFFECT and (variant == EffectVariant.DEVIL or variant == EffectVariant.ANGEL) then
      return { entityType, EffectVariant.DEVIL, subType, seed } -- the devil effect sometimes turns into an angel effect
    end
  end
end

-- filtered to ENTITY_URIEL / ENTITY_GABRIEL / ENTITY_LEECH / ENTITY_FALLEN / ENTITY_SATAN
-- removing entities from here (rather than onUpdate) means that the player won't collide with the enemy and take damage
function mod:onNpcInit(entityNpc)
  local isGreedMode = game:IsGreedMode()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local stage = level:GetStage()
  local normalVariant = 0 -- 1 is krampus
  local stompVariant = 10 -- 0 is normal
  
  if room:GetType() == RoomType.ROOM_DEVIL then
    if mod.isSatanFight then
      if entityNpc.Type == EntityType.ENTITY_LEECH then -- filter out leech
        entityNpc:Remove()
      elseif entityNpc.Type == EntityType.ENTITY_FALLEN and entityNpc.Variant == normalVariant then -- filter out fallen
        entityNpc:Remove()
        mod:removeGridStatue()
        mod:playStartingSatanMusic()
      elseif entityNpc.Type == EntityType.ENTITY_SATAN and entityNpc.Variant == stompVariant then
        if (isGreedMode and stage < LevelStage.STAGE4_GREED) or (not isGreedMode and stage < LevelStage.STAGE4_1) then -- filter out foot stomps before the womb
          entityNpc:Remove()
        end
      end
    else -- not satan fight
      if entityNpc.Type == EntityType.ENTITY_URIEL or entityNpc.Type == EntityType.ENTITY_GABRIEL then
        mod:playStartingAngelMusic()
      end
    end
  end
end

-- filtered to ENTITY_SATAN
-- this is in update rather than init because Satan's HP is set to 0 initially
function mod:onNpcUpdate(entityNpc)
  local isGreedMode = game:IsGreedMode()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local stage = level:GetStage()
  
  if mod.isSatanFight and room:GetType() == RoomType.ROOM_DEVIL then
    if entityNpc.HitPoints == 600 and entityNpc.MaxHitPoints == 600 then
      if (isGreedMode and stage < LevelStage.STAGE2_GREED) or (not isGreedMode and stage < LevelStage.STAGE2_1) then
        entityNpc.HitPoints = 150
        entityNpc.MaxHitPoints = 150
      elseif (isGreedMode and stage < LevelStage.STAGE3_GREED) or (not isGreedMode and stage < LevelStage.STAGE3_1) then
        entityNpc.HitPoints = 300
        entityNpc.MaxHitPoints = 300
      elseif (isGreedMode and stage < LevelStage.STAGE4_GREED) or (not isGreedMode and stage < LevelStage.STAGE4_1) then
        entityNpc.HitPoints = 450
        entityNpc.MaxHitPoints = 450
      end
    end
  end
end

-- filtered to ENTITY_URIEL and ENTITY_GABRIEL
function mod:onNpcDeath(entityNpc)
  local room = game:GetRoom()
  
  if room:GetType() == RoomType.ROOM_DEVIL then
    local keyPiece = entityNpc.Type == EntityType.ENTITY_URIEL and CollectibleType.COLLECTIBLE_KEY_PIECE_1 or CollectibleType.COLLECTIBLE_KEY_PIECE_2
    local hasKey = mod:hasBothKeyPieces()
    local position = room:FindFreePickupSpawnPosition(entityNpc.Position, 0, false, false)
    
    if mod.state.fallenAngelDropType == 'items only' or mod:hasFiligreeFeather() then
      -- null will use the item pool of the current room
      Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, CollectibleType.COLLECTIBLE_NULL, position, Vector(0,0), nil)
    elseif mod.state.fallenAngelDropType == 'keys then items' then
      local collectible = hasKey and CollectibleType.COLLECTIBLE_NULL or keyPiece
      Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, collectible, position, Vector(0,0), nil)
    else -- keys only
      if not hasKey then
        Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, keyPiece, position, Vector(0,0), nil)
      end
    end
    
    mod:playEndingMusic()
  end
end

function mod:showSatanFightText()
  local hud = game:GetHUD()
  local player1 = game:GetPlayer(0)
  local player2 = player1:GetOtherTwin()
  local playerName = player1:GetName()
  
  if player2 and playerName == 'Jacob' and player2:GetName() == 'Esau' then
    playerName = 'Jacob+Esau'
  end
  
  hud:ShowItemText(playerName .. ' vs Satan', nil, false)
end

function mod:closeDoors()
  local room = game:GetRoom()
  
  for i = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
    local door = room:GetDoor(i)
    if door and door:IsOpen() then
      door:Close(true)
    end
  end
end

function mod:updateGridStatues(statues)
  local room = game:GetRoom()
  
  -- there's a grid entity that accompanies the statue effect
  for _, statue in ipairs(statues) do
    local gridEntity = room:GetGridEntityFromPos(statue.Position)
    if gridEntity and gridEntity:GetType() == GridEntityType.GRID_STATUE then
      gridEntity:SetVariant(1) -- angel room variant that can spawn uriel/gabriel, this can cause an angel statue effect to be shown
    end
  end
end

function mod:removeGridStatue()
  local room = game:GetRoom()
  
  -- room:RemoveGridEntity doesn't save state on its own so we update the grid entity to a destroyed rock which does save state
  local gridEntity = room:GetGridEntity(mod.gridIndex52)
  if gridEntity and gridEntity:GetType() == GridEntityType.GRID_STATUE then
    gridEntity:SetType(GridEntityType.GRID_ROCK)
    gridEntity:SetVariant(0)
    gridEntity.State = 2 -- destroyed/rubble
  end
end

function mod:setPrices()
  for _, entity in ipairs(Isaac.GetRoomEntities()) do
    if entity.Type == EntityType.ENTITY_PICKUP and entity.Variant == PickupVariant.PICKUP_COLLECTIBLE then
      local pickup = entity:ToPickup()
      if pickup.Price ~= 0 and pickup.Price ~= PickupPrice.PRICE_FREE and pickup.Price ~= PickupPrice.PRICE_SPIKES then
        pickup.Price = PickupPrice.PRICE_SPIKES
        pickup.AutoUpdatePrice = false
      end
    end
  end
end

function mod:hasBothKeyPieces()
  local hasKeyPiece1 = false
  local hasKeyPiece2 = false
  
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    if player:HasCollectible(CollectibleType.COLLECTIBLE_KEY_PIECE_1, false) then
      hasKeyPiece1 = true
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_KEY_PIECE_2, false) then
      hasKeyPiece2 = true
    end
  end
  
  return hasKeyPiece1 and hasKeyPiece2
end

function mod:hasFiligreeFeather()
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    if player:HasTrinket(TrinketType.TRINKET_FILIGREE_FEATHERS, false) then
      return true
    end
  end
  
  return false
end

-- vanilla: boss music plays, gets cut off for satan boss music, ending music doesn't play
-- soundtrack menu: nothing plays (which is why we need this)
function mod:playStartingSatanMusic()
  -- if using vanilla, the initial boss music for the fallen always plays first
  music:Play(Music.MUSIC_SATAN_BOSS, Options.MusicVolume)
end

-- vanilla: boss music plays, ending music plays
-- soundtrack menu: nothing plays (which is why we need this)
function mod:playStartingAngelMusic()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local stageType = level:GetStageType()
  
  local bossMusic
  if stageType == StageType.STAGETYPE_REPENTANCE or stageType == StageType.STAGETYPE_REPENTANCE_B then
    bossMusic = Music.MUSIC_BOSS3
  else
    bossMusic = room:GetDecorationSeed() % 2 == 0 and Music.MUSIC_BOSS or Music.MUSIC_BOSS2
  end
  
  music:Play(bossMusic, Options.MusicVolume)
end

-- some of this is borrowed from music mod callback
function mod:playEndingMusic()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local stageType = level:GetStageType()
  
  local jingle
  if stageType == StageType.STAGETYPE_REPENTANCE or stageType == StageType.STAGETYPE_REPENTANCE_B then
    jingle = Music.MUSIC_JINGLE_BOSS_OVER3
  else
    jingle = room:GetDecorationSeed() % 2 == 0 and Music.MUSIC_JINGLE_BOSS_OVER or Music.MUSIC_JINGLE_BOSS_OVER2
  end
  
  music:Play(jingle, Options.MusicVolume)
  music:Queue(Music.MUSIC_BOSS_OVER) -- MUSIC_DEVIL_ROOM
end

function mod:setDevilRoomAllowed(roomDesc, override)
  local stageIndex = mod:getStageIndex()
  if type(mod.state.devilRooms[stageIndex]) ~= 'table' then
    mod.state.devilRooms[stageIndex] = {}
  end
  
  local listIdx = tostring(roomDesc.ListIndex)
  if type(mod.state.devilRooms[stageIndex][listIdx]) ~= 'table' then
    mod.state.devilRooms[stageIndex][listIdx] = {}
  end
  
  if type(override) == 'boolean' then
    mod.state.devilRooms[stageIndex][listIdx]['allowed'] = override
  elseif type(mod.state.devilRooms[stageIndex][listIdx]['allowed']) ~= 'boolean' then
    mod.state.devilRooms[stageIndex][listIdx]['allowed'] = mod.rng:RandomInt(100) < mod.state.probabilitySatan[mod.difficulty[game.Difficulty]]
  end
  
  if type(mod.state.devilRooms[stageIndex][listIdx]['completed']) ~= 'boolean' then
    mod.state.devilRooms[stageIndex][listIdx]['completed'] = false
  end
end

function mod:setDevilRoomCompleted(roomDesc)
  local stageIndex = mod:getStageIndex()
  local listIdx = tostring(roomDesc.ListIndex)
  
  if type(mod.state.devilRooms[stageIndex]) ~= 'table' or type(mod.state.devilRooms[stageIndex][listIdx]) ~= 'table' then
    mod:setDevilRoomAllowed(roomDesc)
  end
  
  mod.state.devilRooms[stageIndex][listIdx]['completed'] = true
end

function mod:isDevilRoomAllowed(roomDesc)
  local stageIndex = mod:getStageIndex()
  local listIdx = tostring(roomDesc.ListIndex)
  
  if type(mod.state.devilRooms[stageIndex]) == 'table' then
    if type(mod.state.devilRooms[stageIndex][listIdx]) == 'table' then
      if type(mod.state.devilRooms[stageIndex][listIdx]['allowed']) == 'boolean' then
        return mod.state.devilRooms[stageIndex][listIdx]['allowed']
      end
    end
  end
  
  return false
end

function mod:isDevilRoomCompleted(roomDesc)
  local stageIndex = mod:getStageIndex()
  local listIdx = tostring(roomDesc.ListIndex)
  
  if type(mod.state.devilRooms[stageIndex]) == 'table' then
    if type(mod.state.devilRooms[stageIndex][listIdx]) == 'table' then
      if type(mod.state.devilRooms[stageIndex][listIdx]['completed']) == 'boolean' then
        return mod.state.devilRooms[stageIndex][listIdx]['completed']
      end
    end
  end
  
  return false
end

function mod:clearDevilRooms(clearAll)
  if clearAll then
    for key, _ in pairs(mod.state.devilRooms) do
      mod.state.devilRooms[key] = nil
    end
  else
    mod.state.devilRooms[mod:getStageIndex()] = nil
  end
end

function mod:getStageIndex()
  local level = game:GetLevel()
  return level:GetStage() .. '-' .. level:GetStageType() .. '-' .. (level:IsAltStage() and 1 or 0) .. '-' .. (level:IsPreAscent() and 1 or 0) .. '-' .. (level:IsAscent() and 1 or 0)
end

function mod:getStageSeed()
  return mod.state.stageSeeds[mod:getStageIndex()]
end

function mod:setStageSeed(seed)
  mod.state.stageSeeds[mod:getStageIndex()] = seed
end

function mod:clearStageSeeds()
  for key, _ in pairs(mod.state.stageSeeds) do
    mod.state.stageSeeds[key] = nil
  end
end

function mod:getDropTypesIndex(name)
  for i, value in ipairs(mod.dropTypes) do
    if name == value then
      return i
    end
  end
  return -1
end

function mod:seedRng()
  repeat
    local rand = Random()  -- 0 to 2^32
    if rand > 0 then       -- if this is 0, it causes a crash later on
      mod.rng:SetSeed(rand, 1)
    end
  until(rand > 0)
end

-- start ModConfigMenu --
function mod:setupModConfigMenu()
  ModConfigMenu.AddText(mod.Name, 'Satan', 'What\'s the probability of Satan')
  ModConfigMenu.AddText(mod.Name, 'Satan', 'showing up in a Devil Room?')
  ModConfigMenu.AddSpace(mod.Name, 'Satan')
  for _, difficulty in ipairs({ 'normal', 'hard', 'greed', 'greedier' }) do
    ModConfigMenu.AddSetting(
      mod.Name,
      'Satan',
      {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function()
          return mod.state.probabilitySatan[difficulty]
        end,
        Minimum = 0,
        Maximum = 100,
        Display = function()
          return difficulty .. ': ' .. mod.state.probabilitySatan[difficulty] .. '%'
        end,
        OnChange = function(n)
          mod.state.probabilitySatan[difficulty] = n
        end,
        Info = { 'Satan will only show up if there\'s a valid', 'deal with the devil and no other enemies' }
      }
    )
  end
  ModConfigMenu.AddSetting(
    mod.Name,
    'Angels',
    {
      Type = ModConfigMenu.OptionType.NUMBER,
      CurrentSetting = function()
        return mod:getDropTypesIndex(mod.state.fallenAngelDropType)
      end,
      Minimum = 1,
      Maximum = #mod.dropTypes,
      Display = function()
        return 'Drop type: ' .. mod.state.fallenAngelDropType
      end,
      OnChange = function(n)
        mod.state.fallenAngelDropType = mod.dropTypes[n]
      end,
      Info = { 'Should fallen angels drop items', 'in addition to key pieces?' }
    }
  )
end
-- end ModConfigMenu --

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)
mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, mod.onNewLevel)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_PRE_ENTITY_SPAWN, mod.onPreEntitySpawn)
mod:AddCallback(ModCallbacks.MC_POST_NPC_INIT, mod.onNpcInit, EntityType.ENTITY_URIEL)
mod:AddCallback(ModCallbacks.MC_POST_NPC_INIT, mod.onNpcInit, EntityType.ENTITY_GABRIEL)
mod:AddCallback(ModCallbacks.MC_POST_NPC_INIT, mod.onNpcInit, EntityType.ENTITY_LEECH)
mod:AddCallback(ModCallbacks.MC_POST_NPC_INIT, mod.onNpcInit, EntityType.ENTITY_FALLEN)
mod:AddCallback(ModCallbacks.MC_POST_NPC_INIT, mod.onNpcInit, EntityType.ENTITY_SATAN)
mod:AddCallback(ModCallbacks.MC_NPC_UPDATE, mod.onNpcUpdate, EntityType.ENTITY_SATAN)
mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, mod.onNpcDeath, EntityType.ENTITY_URIEL)
mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, mod.onNpcDeath, EntityType.ENTITY_GABRIEL)

if ModConfigMenu then
  mod:setupModConfigMenu()
end