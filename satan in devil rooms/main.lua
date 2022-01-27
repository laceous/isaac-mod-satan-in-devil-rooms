local mod = RegisterMod('Satan in Devil Rooms', 1)
local json = require('json')
local game = Game()
local music = MusicManager()

mod.isSatanFight = false
mod.stateLoaded = false
mod.stateLoadedEarly = false
mod.gridIndex22 = 22
mod.gridIndex52 = 52
mod.rng = RNG()

mod.difficulty = {
  [Difficulty.DIFFICULTY_NORMAL] = 'normal',
  [Difficulty.DIFFICULTY_HARD] = 'hard',
  [Difficulty.DIFFICULTY_GREED] = 'greed',
  [Difficulty.DIFFICULTY_GREEDIER] = 'greedier'
}

mod.state = {}
mod.state.stageSeed = nil
mod.state.devilRooms = {}
mod.state.probabilitySatan = { normal = 3, hard = 20, greed = 0, greedier = 0 }

function mod:onGameStart(isContinue)
  mod:loadState(isContinue)
  mod.stateLoaded = true
end

function mod:loadState(isContinue)
  local level = game:GetLevel()
  local seeds = game:GetSeeds()
  local stageSeed = seeds:GetStageSeed(level:GetStage())
  mod.state.stageSeed = stageSeed
  
  local devilRooms
  if mod.stateLoadedEarly then
    devilRooms = mod:copyTable(mod.state.devilRooms)
  else
    mod:seedRng()
  end
  
  if mod:HasData() then
    local _, state = pcall(json.decode, mod:LoadData())
    
    if type(state) == 'table' then
      if math.type(state.stageSeed) == 'integer' and type(state.devilRooms) == 'table' then
        -- quick check to see if this is the same run being continued
        if state.stageSeed == stageSeed then
          mod.state.devilRooms = state.devilRooms
        end
      end
      if type(state.probabilitySatan) == 'table' then
        for _, difficulty in ipairs({ 'normal', 'hard', 'greed', 'greedier' }) do
          if math.type(state.probabilitySatan[difficulty]) == 'integer' and state.probabilitySatan[difficulty] >= 0 and state.probabilitySatan[difficulty] <= 100 then
            mod.state.probabilitySatan[difficulty] = state.probabilitySatan[difficulty]
          end
        end
      end
    end
    
    if not isContinue then
      mod:clearDevilRooms()
    end
  end
  
  if mod.stateLoadedEarly then
    for k, v in pairs(devilRooms) do
      mod.state.devilRooms[k] = v
    end
  end
end

function mod:onGameExit()
  mod:SaveData(json.encode(mod.state))
  mod.stateLoaded = false
  mod.stateLoadedEarly = false
end

function mod:onNewLevel()
  local level = game:GetLevel()
  local seeds = game:GetSeeds()
  local stageSeed = seeds:GetStageSeed(level:GetStage())
  mod.state.stageSeed = stageSeed
  mod:clearDevilRooms()
end

function mod:onNewRoom()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  
  mod.isSatanFight = false
  
  if room:GetType() == RoomType.ROOM_DEVIL then
    -- onNewRoom runs before onGameStart
    -- if we don't spawn Satan from here then the doors don't lock properly when continuing
    if not mod.stateLoaded then
      mod:loadState(false)
      mod.stateLoadedEarly = true
    end
    
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
      mod.isSatanFight = true
      room:SetClear(false)
      
      local hud = game:GetHUD()
      local player1 = game:GetPlayer(0)
      local player2 = player1:GetOtherTwin()
      local playerName = player1:GetName()
      if player2 and playerName == 'Jacob' and player2:GetName() == 'Esau' then
        playerName = 'Jacob+Esau'
      end
      hud:ShowItemText(playerName .. ' vs Satan', nil, false)
    else
      -- there's a grid entity that accompanies the statue effect
      for _, statue in ipairs(statues) do
        local gridIndex = room:GetGridIndex(statue.Position)
        local gridEntity = room:GetGridEntity(gridIndex)
        if gridEntity and gridEntity:GetType() == GridEntityType.GRID_STATUE then
          gridEntity:SetVariant(1) -- angel room variant that can spawn uriel/gabriel, this can cause an angel statue effect to be shown
        end
      end
      
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
  local room = game:GetRoom()
  local normalVariant = 0 -- 1 is krampus
  
  if room:GetType() == RoomType.ROOM_DEVIL then
    if mod.isSatanFight then
      if mod:modifySatanFight(entityNpc.Type, entityNpc.Variant) then
        entityNpc:Remove()
        
        if entityNpc.Type == EntityType.ENTITY_FALLEN and entityNpc.Variant == normalVariant then
          mod:playStartingSatanMusic()
          
          -- room:RemoveGridEntity doesn't save state on its own so we update the grid entity to a destroyed rock which does save state
          local gridEntity = room:GetGridEntity(mod.gridIndex52)
          if gridEntity and gridEntity:GetType() == GridEntityType.GRID_STATUE then
            gridEntity:SetType(GridEntityType.GRID_ROCK)
            gridEntity:SetVariant(0)
            gridEntity.State = 2 -- destroyed/rubble
          end
        end
      end
    else -- not satan fight
      if entityNpc.Type == EntityType.ENTITY_URIEL or entityNpc.Type == EntityType.ENTITY_GABRIEL then
        mod:playStartingAngelMusic()
      end
    end
  end
end

-- filtered to ENTITY_URIEL and ENTITY_GABRIEL
function mod:onNpcDeath(entityNpc)
  local room = game:GetRoom()
  
  if room:GetType() == RoomType.ROOM_DEVIL then
    local key = entityNpc.Type == EntityType.ENTITY_URIEL and CollectibleType.COLLECTIBLE_KEY_PIECE_1 or CollectibleType.COLLECTIBLE_KEY_PIECE_2
    
    if not mod:hasBothKeyPieces() then
      Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, key, entityNpc.Position, Vector(0,0), nil)
    end
    
    mod:playEndingMusic()
  end
end

function mod:modifySatanFight(entityType, entityVariant)
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local normalVariant = 0 -- 1 is krampus
  local stompVariant = 10 -- 0 is normal
  
  if mod.isSatanFight and room:GetType() == RoomType.ROOM_DEVIL then
    -- filter out leech and fallen
    if entityType == EntityType.ENTITY_LEECH or (entityType == EntityType.ENTITY_FALLEN and entityVariant == normalVariant) then
      return true
    elseif entityType == EntityType.ENTITY_SATAN and entityVariant == stompVariant then
      local isGreedMode = game:IsGreedMode()
      local stage = level:GetStage()
      -- stage 4 is the womb, filter out foot stomps before that
      if (isGreedMode and stage < LevelStage.STAGE4_GREED) or (not isGreedMode and stage < LevelStage.STAGE4_1) then
        return true
      end
    end
  end
  
  return false
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
  local listIdx = tostring(roomDesc.ListIndex)
  
  if type(mod.state.devilRooms[listIdx]) ~= 'table' then
    mod.state.devilRooms[listIdx] = {}
  end
  
  if type(override) == 'boolean' then
    mod.state.devilRooms[listIdx]['allowed'] = override
  elseif type(mod.state.devilRooms[listIdx]['allowed']) ~= 'boolean' then
    mod.state.devilRooms[listIdx]['allowed'] = mod.rng:RandomInt(100) < mod.state.probabilitySatan[mod.difficulty[game.Difficulty]]
  end
  
  if type(mod.state.devilRooms[listIdx]['completed']) ~= 'boolean' then
    mod.state.devilRooms[listIdx]['completed'] = false
  end
end

function mod:setDevilRoomCompleted(roomDesc)
  local listIdx = tostring(roomDesc.ListIndex)
  
  if type(mod.state.devilRooms[listIdx]) ~= 'table' then
    mod:setDevilRoomAllowed(roomDesc)
  end
  
  mod.state.devilRooms[listIdx]['completed'] = true
end

function mod:isDevilRoomAllowed(roomDesc)
  local listIdx = tostring(roomDesc.ListIndex)
  
  if type(mod.state.devilRooms[listIdx]) == 'table' then
    if type(mod.state.devilRooms[listIdx]['allowed']) == 'boolean' then
      return mod.state.devilRooms[listIdx]['allowed']
    end
  end
  
  return false
end

function mod:isDevilRoomCompleted(roomDesc)
  local listIdx = tostring(roomDesc.ListIndex)
  
  if type(mod.state.devilRooms[listIdx]) == 'table' then
    if type(mod.state.devilRooms[listIdx]['completed']) == 'boolean' then
      return mod.state.devilRooms[listIdx]['completed']
    end
  end
  
  return false
end

function mod:clearDevilRooms()
  for key, _ in pairs(mod.state.devilRooms) do
    mod.state.devilRooms[key] = nil
  end
end

function mod:seedRng()
  repeat
    local rand = Random()  -- 0 to 2^32
    if rand > 0 then       -- if this is 0, it causes a crash later on
      mod.rng:SetSeed(rand, 1)
    end
  until(rand > 0)
end

-- shallow copy
function mod:copyTable(tbl)
  local copy = {}
  for k, v in pairs(tbl) do
    copy[k] = v
  end
  return copy
end

-- start ModConfigMenu --
function mod:setupModConfigMenu()
  ModConfigMenu.AddText(mod.Name, nil, 'What\'s the probability of Satan')
  ModConfigMenu.AddText(mod.Name, nil, 'showing up in a Devil Room?')
  ModConfigMenu.AddSpace(mod.Name, nil)
  for _, difficulty in ipairs({ 'normal', 'hard', 'greed', 'greedier' }) do
    ModConfigMenu.AddSetting(
      mod.Name,
      nil,
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
mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, mod.onNpcDeath, EntityType.ENTITY_URIEL)
mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, mod.onNpcDeath, EntityType.ENTITY_GABRIEL)

if ModConfigMenu then
  mod:setupModConfigMenu()
end