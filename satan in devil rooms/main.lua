local mod = RegisterMod('Satan in Devil Rooms', 1)
local json = require('json')
local game = Game()
local music = MusicManager()

mod.isSatanFight = false
mod.onGameStartHasRun = false
mod.gridIndex22 = 22
mod.gridIndex52 = 52
mod.rngShiftIndex = 35

mod.difficulty = {
  [Difficulty.DIFFICULTY_NORMAL] = 'normal',
  [Difficulty.DIFFICULTY_HARD] = 'hard',
  [Difficulty.DIFFICULTY_GREED] = 'greed',
  [Difficulty.DIFFICULTY_GREEDIER] = 'greedier'
}
mod.dropTypes = { 'keys only', 'keys then items', 'items only' }

mod.state = {}
mod.state.devilRooms = {} -- per stage/type
mod.state.fallenAngelDropType = 'keys only'
mod.state.easierFallenAngels = false
mod.state.spawnHolyCard = false
mod.state.probabilitySatan = { normal = 3, hard = 20, greed = 0, greedier = 0 }

function mod:onGameStart(isContinue)
  mod:clearDevilRooms(false)
  
  if mod:HasData() then
    local _, state = pcall(json.decode, mod:LoadData())
    
    if type(state) == 'table' then
      if isContinue then
        if type(state.devilRooms) == 'table' then
          for key, value in pairs(state.devilRooms) do
            if type(key) == 'string' and type(value) == 'table' then
              mod.state.devilRooms[key] = {}
              for k, v in pairs(value) do
                if type(k) == 'string' and type(v) == 'table' then
                  mod.state.devilRooms[key][k] = {}
                  if type(v.allowed) == 'boolean' then
                    mod.state.devilRooms[key][k].allowed = v.allowed
                  end
                  if type(v.spawned) == 'boolean' then
                    mod.state.devilRooms[key][k].spawned = v.spawned
                  end
                  if type(v.completed) == 'boolean' then
                    mod.state.devilRooms[key][k].completed = v.completed
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
      if type(state.easierFallenAngels) == 'boolean' then
        mod.state.easierFallenAngels = state.easierFallenAngels
      end
      if type(state.spawnHolyCard) == 'boolean' then
        mod.state.spawnHolyCard = state.spawnHolyCard
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
  
  mod:updateEid()
  
  mod.onGameStartHasRun = true
  mod:onNewRoom()
end

function mod:onGameExit(shouldSave)
  if shouldSave then
    mod:save()
    mod:clearDevilRooms(true)
  else
    mod:clearDevilRooms(true)
    mod:save()
  end
  
  mod.isSatanFight = false
  mod.onGameStartHasRun = false
end

function mod:save(settingsOnly)
  if settingsOnly then
    local _, state
    if mod:HasData() then
      _, state = pcall(json.decode, mod:LoadData())
    end
    if type(state) ~= 'table' then
      state = {}
    end
    
    state.fallenAngelDropType = mod.state.fallenAngelDropType
    state.easierFallenAngels = mod.state.easierFallenAngels
    state.spawnHolyCard = mod.state.spawnHolyCard
    state.probabilitySatan = mod.state.probabilitySatan
    
    mod:SaveData(json.encode(state))
  else
    mod:SaveData(json.encode(mod.state))
  end
end

function mod:onNewLevel()
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
    if room:IsFirstVisit() then
      mod:setDevilRoomAllowed(roomDesc)
    end
    
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
    
    local statuesCount = #statues
    local pickupsCount = #pickups
    
    -- don't spawn satan in small devil rooms
    if room:GetRoomShape() == RoomShape.ROOMSHAPE_1x1 and room:IsClear() and mod:isDevilRoomAllowed(roomDesc) and
       (
         (pickupsCount > 0 and statuesCount == 1 and room:GetGridIndex(statues[1].Position) == mod.gridIndex52) or
         mod:isDevilRoomSpawned(roomDesc)
       )
    then
      if statuesCount == 1 then
        mod:removeStatue(statues[1]) -- effect + grid
      end
      mod:removePits() -- make room fair for satan fight
      
      if mod:isDevilRoomCompleted(roomDesc) then
        mod:setPrices()
      else
        mod:setDevilRoomSpawned(roomDesc)
        mod:spawnSatan()
        mod.isSatanFight = true
        mod:closeDoors() -- needed if this is triggered from onGameStart
        mod:showSatanFightText()
        room:SetClear(false)
      end
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
        mod:updateEid()
      else
        mod:solidifySatanStatue() -- the game keeps trying to undo this
      end
    else -- not satan fight
      if mod:isDevilRoomCompleted(roomDesc) then
        mod:setPrices() -- this could be moved to MC_POST_PICKUP_UPDATE, but the behavior doesn't seem to be any different
      end
    end
  end
end

-- filtered to CARD_HOLY
function mod:onUseCard(card, player, useFlags)
  if mod.state.spawnHolyCard and mod:isAnyDevilRoomCompleted() then
    local level = game:GetLevel()
    local room = level:GetCurrentRoom()
    
    if room:GetType() == RoomType.ROOM_DEVIL then
      player:AddItemWisp(CollectibleType.COLLECTIBLE_ACT_OF_CONTRITION, player.Position, true)
    else
      level:AddAngelRoomChance(0.1) -- 10%
    end
  end
end

function mod:onPreSpawnAward(rng, pos)
  local room = game:GetRoom()
  
  if room:GetType() == RoomType.ROOM_DEVIL and mod.isSatanFight and mod.state.spawnHolyCard then
    mod:spawnHolyCard(pos)
    return true -- cancel default spawn
  end
end

function mod:onPreEntitySpawn(entityType, variant, subType, position, velocity, spawner, seed)
  local room = game:GetRoom()
  local fallenVariant = 1
  
  if room:GetType() == RoomType.ROOM_DEVIL then
    if entityType == EntityType.ENTITY_URIEL or entityType == EntityType.ENTITY_GABRIEL then
      return { entityType, fallenVariant, subType, seed } -- fallen uriel / fallen gabriel
    elseif entityType == EntityType.ENTITY_EFFECT and (variant == EffectVariant.DEVIL or variant == EffectVariant.ANGEL) then
      -- the devil effect will turn into an angel effect when walking back into the room
      -- because we switched the statue variant to an angel so we could spawn uriel/gabriel
      return { entityType, EffectVariant.DEVIL, subType, seed }
    end
  end
end

-- filtered to ENTITY_URIEL / ENTITY_GABRIEL / ENTITY_LEECH / ENTITY_NULLS / ENTITY_FALLEN / ENTITY_SATAN
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
      if entityNpc.Type == EntityType.ENTITY_LEECH or entityNpc.Type == EntityType.ENTITY_NULLS then -- filter out leech/nulls
        entityNpc:Remove()
      elseif entityNpc.Type == EntityType.ENTITY_FALLEN and entityNpc.Variant == normalVariant then -- filter out fallen
        entityNpc:Remove()
        mod:playStartingSatanMusic()
      elseif entityNpc.Type == EntityType.ENTITY_SATAN and entityNpc.Variant == stompVariant then
        if (isGreedMode and stage < LevelStage.STAGE4_GREED) or (not isGreedMode and stage < LevelStage.STAGE4_1) then -- filter out foot stomps before the womb
          entityNpc:Remove()
        end
      end
    else -- not satan fight
      if entityNpc.Type == EntityType.ENTITY_URIEL then
        if mod.state.easierFallenAngels and entityNpc.HitPoints == 450 and entityNpc.MaxHitPoints == 450 then
          entityNpc.HitPoints = 400
          entityNpc.MaxHitPoints = 400
        end
        mod:playStartingAngelMusic()
      elseif entityNpc.Type == EntityType.ENTITY_GABRIEL then
        if mod.state.easierFallenAngels and entityNpc.HitPoints == 750 and entityNpc.MaxHitPoints == 750 then
          entityNpc.HitPoints = 660
          entityNpc.MaxHitPoints = 660
        end
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
    
    -- safety check, sometimes the wrong angel spawns, angel rooms will still give you the other key piece to complete your set
    if keyPiece == CollectibleType.COLLECTIBLE_KEY_PIECE_1 and mod:hasKeyPiece1() then
      keyPiece = CollectibleType.COLLECTIBLE_KEY_PIECE_2
    elseif keyPiece == CollectibleType.COLLECTIBLE_KEY_PIECE_2 and mod:hasKeyPiece2() then
      keyPiece = CollectibleType.COLLECTIBLE_KEY_PIECE_1
    end
    
    if mod.state.fallenAngelDropType == 'items only' or mod:hasFiligreeFeather() then
      -- null will use the item pool of the current room
      Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, CollectibleType.COLLECTIBLE_NULL, position, Vector.Zero, nil)
    elseif mod.state.fallenAngelDropType == 'keys then items' then
      local collectible = hasKey and CollectibleType.COLLECTIBLE_NULL or keyPiece
      Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, collectible, position, Vector.Zero, nil)
    else -- keys only
      if not hasKey then
        Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, keyPiece, position, Vector.Zero, nil)
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
  
  if player2 and player1:GetPlayerType() == PlayerType.PLAYER_JACOB and player2:GetPlayerType() == PlayerType.PLAYER_ESAU then
    playerName = player1:GetName() .. '+' .. player2:GetName()
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

function mod:removePits()
  local room = game:GetRoom()
  
  for i = 0, room:GetGridSize() - 1 do
    local gridEntity = room:GetGridEntity(i)
    if gridEntity and gridEntity:GetType() == GridEntityType.GRID_PIT then
      gridEntity:ToPit():MakeBridge(nil) -- room:RemoveGridEntity doesn't save when re-entering room
    end
  end
end

function mod:updateGridStatues(statues)
  local room = game:GetRoom()
  local angelVariant = 1 -- 0 is devil
  
  -- there's a grid entity that accompanies the statue effect
  for _, statue in ipairs(statues) do
    local gridEntity = room:GetGridEntityFromPos(statue.Position)
    if gridEntity and gridEntity:GetType() == GridEntityType.GRID_STATUE and gridEntity:GetVariant() ~= angelVariant then
      gridEntity:SetVariant(angelVariant) -- angel room variant that can spawn uriel/gabriel, this can cause an angel statue effect to be shown
    end
  end
end

function mod:removeStatue(statue)
  local room = game:GetRoom()
  local destroyedState = 2 -- destroyed/rubble
  
  statue:Remove() -- effect
  
  -- this allows you to walk through the satan statue
  -- but it blocks the devil statue from showing up again on continue
  local gridEntity = room:GetGridEntityFromPos(statue.Position)
  if gridEntity and gridEntity:GetType() == GridEntityType.GRID_STATUE and gridEntity.State ~= destroyedState then
    gridEntity.State = destroyedState
  end
end

function mod:solidifySatanStatue()
  local room = game:GetRoom()
  local satans = Isaac.FindByType(EntityType.ENTITY_SATAN, 0, -1, false, false)
  
  if #satans == 1 then
    local satan = satans[1]:ToNPC()
    if satan and satan.State == NpcState.STATE_IDLE then
      local gridEntity = room:GetGridEntity(mod.gridIndex52)
      if gridEntity and gridEntity:GetType() == GridEntityType.GRID_STATUE and gridEntity.CollisionClass ~= GridCollisionClass.COLLISION_SOLID then
        gridEntity.CollisionClass = GridCollisionClass.COLLISION_SOLID
      end
    end
  end
end

function mod:spawnSatan()
  local room = game:GetRoom()
  
  -- devil statue should be at GridIndex(52)
  -- satan needs to go to GridIndex(22) because its base position is 2 spaces higher (52 - 15 - 15 = 22)
  local satan = Isaac.Spawn(EntityType.ENTITY_SATAN, 0, 0, room:GetGridPosition(mod.gridIndex22), Vector.Zero, nil)
  satan:Update() -- fix on continue positioning, why does onGameStart happen after onNewRoom?
end

function mod:spawnHolyCard(pos)
  Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, Card.CARD_HOLY, Isaac.GetFreeNearPosition(pos, 3), Vector.Zero, nil)
end

function mod:setPrices()
  for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, -1, false, false)) do
    local pickup = entity:ToPickup()
    if pickup.Price ~= 0 and pickup.Price ~= PickupPrice.PRICE_FREE and pickup.Price ~= PickupPrice.PRICE_SPIKES then
      pickup.Price = PickupPrice.PRICE_SPIKES
      pickup.AutoUpdatePrice = false
    end
  end
end

function mod:hasKeyPiece1()
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    if player:HasCollectible(CollectibleType.COLLECTIBLE_KEY_PIECE_1, false) then
      return true
    end
  end
  
  return false
end

function mod:hasKeyPiece2()
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    if player:HasCollectible(CollectibleType.COLLECTIBLE_KEY_PIECE_2, false) then
      return true
    end
  end
  
  return false
end

function mod:hasBothKeyPieces()
  return mod:hasKeyPiece1() and mod:hasKeyPiece2()
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
    mod.state.devilRooms[stageIndex][listIdx].allowed = override
  else
    local rng = RNG()
    rng:SetSeed(roomDesc.SpawnSeed, mod.rngShiftIndex) -- AwardSeed, DecorationSeed
    mod.state.devilRooms[stageIndex][listIdx].allowed = rng:RandomInt(100) < mod.state.probabilitySatan[mod.difficulty[game.Difficulty]]
  end
  
  mod.state.devilRooms[stageIndex][listIdx].spawned = false
  mod.state.devilRooms[stageIndex][listIdx].completed = false
end

function mod:setDevilRoomSpawned(roomDesc)
  local stageIndex = mod:getStageIndex()
  local listIdx = tostring(roomDesc.ListIndex)
  
  if type(mod.state.devilRooms[stageIndex]) ~= 'table' or type(mod.state.devilRooms[stageIndex][listIdx]) ~= 'table' then
    mod:setDevilRoomAllowed(roomDesc)
  end
  
  mod.state.devilRooms[stageIndex][listIdx].spawned = true
end

function mod:setDevilRoomCompleted(roomDesc)
  local stageIndex = mod:getStageIndex()
  local listIdx = tostring(roomDesc.ListIndex)
  
  if type(mod.state.devilRooms[stageIndex]) ~= 'table' or type(mod.state.devilRooms[stageIndex][listIdx]) ~= 'table' then
    mod:setDevilRoomAllowed(roomDesc)
  end
  
  mod.state.devilRooms[stageIndex][listIdx].completed = true
end

function mod:isDevilRoomAllowed(roomDesc)
  local stageIndex = mod:getStageIndex()
  local listIdx = tostring(roomDesc.ListIndex)
  
  if type(mod.state.devilRooms[stageIndex]) == 'table' and type(mod.state.devilRooms[stageIndex][listIdx]) == 'table' then
    return mod.state.devilRooms[stageIndex][listIdx].allowed or false
  end
  
  return false
end

function mod:isDevilRoomSpawned(roomDesc)
  local stageIndex = mod:getStageIndex()
  local listIdx = tostring(roomDesc.ListIndex)
  
  if type(mod.state.devilRooms[stageIndex]) == 'table' and type(mod.state.devilRooms[stageIndex][listIdx]) == 'table' then
    return mod.state.devilRooms[stageIndex][listIdx].spawned or false
  end
  
  return false
end

function mod:isDevilRoomCompleted(roomDesc)
  local stageIndex = mod:getStageIndex()
  local listIdx = tostring(roomDesc.ListIndex)
  
  if type(mod.state.devilRooms[stageIndex]) == 'table' and type(mod.state.devilRooms[stageIndex][listIdx]) == 'table' then
    return mod.state.devilRooms[stageIndex][listIdx].completed or false
  end
  
  return false
end

function mod:isAnyDevilRoomCompleted()
  for _, v in pairs(mod.state.devilRooms) do
    for _, w in pairs(v) do
      if w.completed then
        return true
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
  local stage = level:GetStage()
  local stageType = level:GetStageType()
  local isAltStage = level:IsAltStage()
  
  -- home switches these midway through, keep it consistent
  if stage == LevelStage.STAGE8 then
    stageType = StageType.STAGETYPE_ORIGINAL -- normal: STAGETYPE_ORIGINAL -> STAGETYPE_WOTL
    isAltStage = false                       -- normal: false -> true
  end
  
  return game:GetVictoryLap() .. '-' .. stage .. '-' .. stageType .. '-' .. (isAltStage and 1 or 0) .. '-' .. (level:IsPreAscent() and 1 or 0) .. '-' .. (level:IsAscent() and 1 or 0)
end

function mod:getDropTypesIndex(name)
  for i, value in ipairs(mod.dropTypes) do
    if name == value then
      return i
    end
  end
  return -1
end

-- external item descriptions
function mod:updateEid()
  if EID then
    local card = Card.CARD_HOLY
    local tblName = EID:getTableName(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TAROTCARD, card) -- cards
    
    -- do this for all languages
    -- if we only do this for english then regardless of the selected language, only english will be shown
    for lang, v in pairs(EID.descriptions) do
      local tbl = v[tblName]
      
      if tbl and tbl[card] then
        local name = tbl[card][2]
        local description = tbl[card][3]
        
        -- english only for now
        if mod.state.spawnHolyCard and mod:isAnyDevilRoomCompleted() then
          description = description .. '#{{DevilRoom}} In Devil Rooms, spawns an Act of Contrition item wisp#{{AngelRoom}} Outside of Devil Rooms, grants a 10% Angel Room chance for the floor'
        end
        
        -- add to custom table
        EID:addCard(card, description, name, lang)
      end
    end
  end
end

-- start ModConfigMenu --
function mod:setupModConfigMenu()
  for _, v in ipairs({ 'Satan', 'Angels' }) do
    ModConfigMenu.RemoveSubcategory(mod.Name, v)
  end
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
          mod:save(true)
        end,
        Info = { 'Satan will only show up if there\'s a valid', 'deal with the devil and no other enemies' }
      }
    )
  end
  ModConfigMenu.AddSpace(mod.Name, 'Satan')
  ModConfigMenu.AddSetting(
    mod.Name,
    'Satan',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return mod.state.spawnHolyCard
      end,
      Display = function()
        return (mod.state.spawnHolyCard and 'Spawn' or 'Do not spawn') .. ' holy card'
      end,
      OnChange = function(b)
        mod.state.spawnHolyCard = b
        mod:updateEid()
        mod:save(true)
      end,
      Info = { 'Spawn holy card after defeating Satan?', 'Grants act of contrition item wisp', '-or- 10% angel room chance' }
    }
  )
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
        mod:save(true)
      end,
      Info = { 'Should fallen angels drop items', 'in addition to key pieces?' }
    }
  )
  ModConfigMenu.AddSetting(
    mod.Name,
    'Angels',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return mod.state.easierFallenAngels
      end,
      Display = function()
        return 'Difficulty: ' .. (mod.state.easierFallenAngels and 'easier' or 'default')
      end,
      OnChange = function(b)
        mod.state.easierFallenAngels = b
        mod:save(true)
      end,
      Info = { 'Default: Uriel has 450 HP, Gabriel has 750 HP', 'Easier: Uriel has 400 HP, Gabriel has 660 HP' }
    }
  )
end
-- end ModConfigMenu --

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)
mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, mod.onNewLevel)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_USE_CARD, mod.onUseCard, Card.CARD_HOLY)
mod:AddCallback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, mod.onPreSpawnAward)
mod:AddCallback(ModCallbacks.MC_PRE_ENTITY_SPAWN, mod.onPreEntitySpawn)
mod:AddCallback(ModCallbacks.MC_POST_NPC_INIT, mod.onNpcInit, EntityType.ENTITY_URIEL)
mod:AddCallback(ModCallbacks.MC_POST_NPC_INIT, mod.onNpcInit, EntityType.ENTITY_GABRIEL)
mod:AddCallback(ModCallbacks.MC_POST_NPC_INIT, mod.onNpcInit, EntityType.ENTITY_LEECH)
mod:AddCallback(ModCallbacks.MC_POST_NPC_INIT, mod.onNpcInit, EntityType.ENTITY_NULLS)
mod:AddCallback(ModCallbacks.MC_POST_NPC_INIT, mod.onNpcInit, EntityType.ENTITY_FALLEN)
mod:AddCallback(ModCallbacks.MC_POST_NPC_INIT, mod.onNpcInit, EntityType.ENTITY_SATAN)
mod:AddCallback(ModCallbacks.MC_NPC_UPDATE, mod.onNpcUpdate, EntityType.ENTITY_SATAN)
mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, mod.onNpcDeath, EntityType.ENTITY_URIEL)
mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, mod.onNpcDeath, EntityType.ENTITY_GABRIEL)

if ModConfigMenu then
  mod:setupModConfigMenu()
end