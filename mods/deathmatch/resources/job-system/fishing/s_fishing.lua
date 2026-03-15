-- Get db connection
local db = exports.mysql:getConn('mta')
-- Get item system
local items = exports['item-system']

-- Fishing Constants
local HOTSPOT_RADIUS = 50
local EVENT_HOTSPOT_RADIUS = 75

local FISHING_TIMES = {
    ["Good"] = {min = 30000, max = 90000},
    ["Medium"] = {min = 90000, max = 180000},
    ["Bad"] = {min = 300000, max = 900000},
    ["Default"] = {min = 200000, max = 600000}
}
local activeFishingTimers = {}

-- Initialize Tables
dbExec(db, "CREATE TABLE IF NOT EXISTS `fish_level` (`name` VARCHAR(50) PRIMARY KEY, `level` INT, `amount` INT)")
dbExec(db, "CREATE TABLE IF NOT EXISTS `fish_settings` (`id` INT AUTO_INCREMENT PRIMARY KEY, `npc_type` VARCHAR(20), `name` VARCHAR(50), `x` FLOAT, `y` FLOAT, `z` FLOAT, `rot` FLOAT, `int` INT, `dim` INT, `skin` INT)")
dbExec(db, "CREATE TABLE IF NOT EXISTS `fish_hotspots` (`id` INT AUTO_INCREMENT PRIMARY KEY, `region` VARCHAR(50), `x` FLOAT, `y` FLOAT, `z` FLOAT, `is_event` TINYINT(1) DEFAULT 0)")

local rustyBaseLocation = nil -- Stores one of the scrapper NPC locations for the random arrival logic
local oldFishingRodId = 49

-- Active fish NPCs indexed by their database ID
fishHotspots = {} -- Managed hotspots (Global to this resource)
local activeEventHotspotID = nil
local activeFishNPCs = {}

-- tblCooldown memiliki value ["Nama_Player"] = { amount = jumlah yang dijual sebelum cooldown, cooldown = status cooldown, current = jumlah ikan exp yang sudah dijual saat ini, level = level mancing player}
local tblCooldown = {}
local cooldownMin = 15
local cooldownSec = 0
local cooldownTime = (cooldownMin * 60000) + (cooldownSec * 1000) -- 15 menit cooldown, bisa diganti

-- Helper to randomly shuffle a table
local function shuffleTable(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

-- Hotspot Rotation Logic
function rotateHotspots()
    local regions = {}
    -- Group hotspots by region
    for id, spot in pairs(fishHotspots) do
        if not regions[spot.region] then regions[spot.region] = {} end
        table.insert(regions[spot.region], id)
    end
    
    -- Assign states per region
    for region, spotIds in pairs(regions) do
        shuffleTable(spotIds)
        
        for index, id in ipairs(spotIds) do
            local state = "Random"
            if index == 1 then
                state = "Good"
            elseif index == 2 or index == 3 then
                state = "Medium"
            elseif index == 4 then
                state = "Bad"
            else
                local rand = math.random(1, 3)
                if rand == 1 then state = "Good"
                elseif rand == 2 then state = "Medium"
                else state = "Bad" end
            end
            fishHotspots[id].state = state
        end
    end
    
    -- Sync with all clients
    exportSyncHotspots()
    outputDebugString("[FISHING] Hotspots rotated successfully.")
end

function setActiveEventHotspot(id)
    activeEventHotspotID = id
end

function exportSyncHotspots()
    outputDebugString("[FISHING] Syncing hotspots to all players.")
    local filteredHotspots = {}
    for id, spot in pairs(fishHotspots) do
        -- Only send normal hotspots OR the currently active event hotspot
        if not spot.is_event or (g_FishingEventActive and id == activeEventHotspotID) then
            filteredHotspots[id] = spot
        end
    end
    triggerClientEvent(root, "fishing:receiveHotspots", root, filteredHotspots, g_FishingEventActive and true or false)
end



local function spawnFishingNpc(row)
    if not row or not row.id then return end
    
    local id = tonumber(row.id)
    if activeFishNPCs[id] and isElement(activeFishNPCs[id]) then
        destroyElement(activeFishNPCs[id])
    end

    local ped = createPed(row.skin or 209, row.x, row.y, row.z)
    if not ped then
        outputDebugString("[FISHING] Failed to create ped ID " .. id .. ": " .. tostring(row.name))
        return
    end

    setElementRotation(ped, 0, 0, row.rot or 0)
    setElementInterior(ped, row.int or 0)
    setElementDimension(ped, row.dim or 0)
    setElementFrozen(ped, true)
    
    -- Interaction type mapped from npc_type
    local interactionType = "fishing.generic"
    if row.npc_type == "fisher" then interactionType = "fishing.herb"
    elseif row.npc_type == "license" then interactionType = "fishing.license"
    elseif row.npc_type == "scrapper" then interactionType = "fishing.scrap"
    end

    setElementData(ped, "fishnpc.id", id)
    setElementData(ped, "fishnpc.type", row.npc_type)
    setElementData(ped, "rpp.npc.type", interactionType)
    setElementData(ped, "rpp.npc.name", row.name)
    setElementData(ped, "nametag", true)
    setElementData(ped, "name", (row.name:gsub(" ", "_")))
    
    activeFishNPCs[id] = ped
    outputDebugString("[FISHING] Spawned NPC [" .. id .. "] (" .. row.npc_type .. "): " .. row.name)
end

addEventHandler("onResourceStart", resourceRoot, function()
    -- Load NPCs and spawn them server-side
    dbQuery(function(qh)
        local res = dbPoll(qh, 0)
        if res then
            for _, row in ipairs(res) do
                if row.npc_type == "scrapper" then
                    -- Use the first scrapper found as the base for the random arrival logic
                    if not rustyBaseLocation then
                        rustyBaseLocation = row
                    end
                else
                    spawnFishingNpc(row)
                end
            end

        end
    end, db, "SELECT * FROM `fish_settings`")

    
    -- Load Hotspots
    dbQuery(function(qh)
        local res = dbPoll(qh, 0)
        if res then
            for _, row in ipairs(res) do
                fishHotspots[row.id] = {id = row.id, region = row.region, x = row.x, y = row.y, z = row.z, state = "Random", is_event = row.is_event == 1}
            end
            -- Perform initial rotation
            rotateHotspots()
        end
    end, db, "SELECT * FROM `fish_hotspots`")
    
    -- Set 1-hour rotation timer
    setTimer(rotateHotspots, 3600000, 0)
end)

addEvent("fishing:requestInitialData", true)
addEventHandler("fishing:requestInitialData", root, function()

    local name = getPlayerName(client)
    outputDebugString("[FISHING] Sending initial hotspots to " .. name)
    triggerClientEvent(client, "fishing:receiveHotspots", root, fishHotspots, g_FishingEventActive and true or false)
    if tblCooldown[name] then
        triggerClientEvent(client, "fishing:updateLevel", client, tblCooldown[name].level)
    else
        dbQuery(function(qh, clientElement, playerName)
            if isElement(clientElement) then
                local res = dbPoll(qh, 0)
                local level = 0
                if res and #res > 0 then
                    level = tonumber(res[1]["level"])
                    tblCooldown[playerName] = {amount = 0, cooldown = false, current = tonumber(res[1]["amount"]), level = level}
                end
                triggerClientEvent(clientElement, "fishing:updateLevel", clientElement, level)
            end
        end, {client, name}, db, "SELECT * FROM `fish_level` WHERE `name` = ?", name)
    end
end)

addCommandHandler("createfishnpc", function(thePlayer, command, npc_type, ...)
    if not exports.integration:isPlayerTrialAdmin(thePlayer) then return end
    if not npc_type or not (...) then
        return outputChatBox("Syntax: /" .. command .. " [fisher/license/scrapper] [name] [optional skin]", thePlayer, 255, 194, 14)
    end
    
    local nameParts = {...}
    local skin = 209
    if #nameParts > 1 and tonumber(nameParts[#nameParts]) then
        skin = tonumber(nameParts[#nameParts])
        table.remove(nameParts, #nameParts)
    end
    local name = table.concat(nameParts, " ")
    
    local x, y, z = getElementPosition(thePlayer)
    local _, _, rot = getElementRotation(thePlayer)
    local int = getElementInterior(thePlayer)
    local dim = getElementDimension(thePlayer)
    
    dbExec(db, "INSERT INTO `fish_settings` (`npc_type`, `name`, `x`, `y`, `z`, `rot`, `int`, `dim`, `skin`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", 
        npc_type, name, x, y, z, rot, int, dim, skin)
    
    dbQuery(function(qh)
        local res = dbPoll(qh, 0)
        if res and res[1] then
            spawnFishingNpc(res[1])
            outputChatBox("Created " .. npc_type .. " NPC: " .. name .. " with ID " .. res[1].id, thePlayer, 0, 255, 0)
        end
    end, db, "SELECT * FROM `fish_settings` WHERE `id` = LAST_INSERT_ID()")
end)

addCommandHandler("deletefishnpc", function(thePlayer, command, id)
    if not exports.integration:isPlayerTrialAdmin(thePlayer) then return end
    id = tonumber(id)
    if not id then
        return outputChatBox("Syntax: /" .. command .. " [ID]", thePlayer, 255, 194, 14)
    end
    
    dbExec(db, "DELETE FROM `fish_settings` WHERE `id` = ?", id)
    if activeFishNPCs[id] and isElement(activeFishNPCs[id]) then
        destroyElement(activeFishNPCs[id])
        activeFishNPCs[id] = nil
        outputChatBox("Deleted fishing NPC ID " .. id, thePlayer, 0, 255, 0)
    else
        outputChatBox("Fishing NPC with ID " .. id .. " not found or not currently spawned.", thePlayer, 255, 0, 0)
    end
end)

addCommandHandler("nearbyfishnpc", function(thePlayer, command)
    if not exports.integration:isPlayerTrialAdmin(thePlayer) then return end
    local x, y, z = getElementPosition(thePlayer)
    local peds = getElementsWithinRange(x, y, z, 10, "ped")
    local found = false
    
    outputChatBox("Nearby Fishing NPCs (10m):", thePlayer, 255, 194, 14)
    for _, ped in ipairs(peds) do
        local id = getElementData(ped, "fishnpc.id")
        if id then
            local npc_type = getElementData(ped, "fishnpc.type")
            local name = (getElementData(ped, "rpp.npc.name") or "Unknown"):gsub("_", " ")
            outputChatBox("  ID: " .. id .. " | Type: " .. npc_type .. " | Name: " .. name, thePlayer, 255, 255, 0)
            found = true
        end
    end
    
    if not found then
        outputChatBox("  None found.", thePlayer, 255, 0, 0)
    end
end)

-- Force-spawn Rusty for testing (admin only)
addCommandHandler("spawnrusty", function(thePlayer)
    if not exports.integration:isPlayerTrialAdmin(thePlayer) then return end
    if isRustyActive then despawnRusty() end
    spawnRusty()
    if isRustyActive then
        local name = (rustyBaseLocation and rustyBaseLocation.name or "Scrap Dealer"):gsub("_", " ")
        outputChatBox("[FISHING] " .. name .. " force-spawned with " .. metalStock .. " metal.", thePlayer, 0, 255, 0)
    else
        outputChatBox("[FISHING] Failed - set his position first with /movefishnpc scrap.", thePlayer, 255, 0, 0)
    end
end)

-- Hotspot Admin Commands
addCommandHandler("createfishhotspot", function(thePlayer, command, region, isEventStr)
    if not exports.integration:isPlayerTrialAdmin(thePlayer) then return end
    if not region then
        outputChatBox("Syntax: /createfishhotspot [region name] [is_event (0 or 1, optional)]", thePlayer, 255, 194, 14)
        return
    end
    
    local isEvent = (tonumber(isEventStr) == 1) and 1 or 0
    local isEventBool = isEvent == 1
    
    local x, y, z = getElementPosition(thePlayer)
    z = 0
    dbExec(db, "INSERT INTO `fish_hotspots` (`region`, `x`, `y`, `z`, `is_event`) VALUES (?, ?, ?, ?, ?)", region, x, y, z, isEvent)
    
    -- Reload hotspots from DB to capture the new auto-increment ID
    dbQuery(function(qh)
        local res = dbPoll(qh, 0)
        if res and res[1] then
            local newId = res[1].id
            fishHotspots[newId] = {id = newId, region = region, x = x, y = y, z = z, state = "Random", is_event = isEventBool}
            
            -- Re-rotate to include the new spot
            rotateHotspots() 
            
            local typeStr = isEventBool and "Event " or ""
            outputChatBox(typeStr .. "Fishing hotspot created for region '"..region.."' with ID "..newId..".", thePlayer, 0, 255, 0)
        end
    end, db, "SELECT `id` FROM `fish_hotspots` ORDER BY `id` DESC LIMIT 1")
end)

addCommandHandler("deletefishhotspot", function(thePlayer, command, idStr)
    if not exports.integration:isPlayerTrialAdmin(thePlayer) then return end
    local id = tonumber(idStr)
    if not id then
        outputChatBox("Syntax: /deletefishhotspot [id]", thePlayer, 255, 194, 14)
        return
    end
    
    if fishHotspots[id] then
        dbExec(db, "DELETE FROM `fish_hotspots` WHERE `id`=?", id)
        fishHotspots[id] = nil
        rotateHotspots() -- Re-rotate without the deleted spot
        outputChatBox("Fishing hotspot ID "..id.." deleted.", thePlayer, 0, 255, 0)
    else
        outputChatBox("No fishing hotspot found with ID "..id..".", thePlayer, 255, 0, 0)
    end
end)

addCommandHandler("forcehotspotrotation", function(thePlayer, command)
    if not exports.integration:isPlayerTrialAdmin(thePlayer) then return end
    rotateHotspots()
    outputChatBox("Forced fishing hotspots rotation.", thePlayer, 0, 255, 0)
end)

-- Pancingan List item ids
--[[
Nama dan deskripsi item untuk 5 level pancingan (Nama - Deskripsi - Weight) pada g_items
Level 1
Beginner's Rod - Lightweight and easy to handle for novice fisher. - 1.5kg
Level 2
Riverbend Rod - Flexible and designed for precision casting. - 1.5kg
Level 3
Oakstream Rod - Sturdy and reliable, perfect for medium size fishes. - 1.5kg
Level 4
Mariner's Rod - Durable and versatile, ideal for large fishes. - 1.5kg
Level 5
Thunderstrike Rod - Powerful and robust, built to handle huge fishes. - 1.5kg
]]--
local rodId = {285,286,287,288,289}

-- Ikan List item ids, ada 5 objek ikan, dan setiap objek ikan ada 2 variasi
--[[
 Nama dan deskripsi item untuk 5 level ikan (Nama - Deskripsi - Weight) pada g_items
 Level 1
 Small Fish - A common fish, usually found on shallow waters. - 1kg
 Level 2
 Regular Fish - A common fish, usually found on deep oceans. - 1.6kg
 Level 3
 Medium Fish - An uncommon fish, usually found on deep oceans. - 2kg
 Level 4
 Large Fish - A rare fish, usually found on deep oceans. - 3.2kg
 Level 5
 Huge Fish - The rarest fish, can only be found on the deepest oceans. - 3.6kg
]]--
local fishId = {290,291,292,293,294}
-- Base fish price, will be multiplied by the multiplier in fishDetail
local basePrice = 50
-- Jumlah ikan yang harus dijual untuk naik level
local expList = {150, 350, 700, 1000}
-- Nama dan Weight IC ikan yang ditangkap, diperhitungkan berdasarkan weight pada g_items
-- Variasi ikan penting secara IC karena variasi ikan ke 2 lebih rare, dan bisa dijadikan sarana RP lomba mancing SAN
local fishDetail = {
    {
        {name="Sardine", lRPWeight=1.0, hRPWeight=1.5, lWeight=0.5, multiplier=0.9},
        {name="Anchovy", lRPWeight=1.2, hRPWeight=1.8, lWeight=0.5, multiplier=1.0}
    },
    {
        {name="Herring", lRPWeight=1.8, hRPWeight=2.5, lWeight=0.5, multiplier=0.85},
        {name="Mackerel", lRPWeight=2.2, hRPWeight=3.0, lWeight=0.5, multiplier=0.9}
    },
    {
        {name="Red Snapper", lRPWeight=3.0, hRPWeight=5.0, lWeight=0.5, multiplier=0.75},
        {name="Mahi-Mahi", lRPWeight=4.5, hRPWeight=7.0, lWeight=0.5, multiplier=0.8}
    },
    {
        {name="Barracuda", lRPWeight=5.0, hRPWeight=7.0, lWeight=0.5, multiplier=0.5},
        {name="Halibut", lRPWeight=7.0, hRPWeight=10.0, lWeight=0.5, multiplier=0.55}
    },
    {
        {name="Swordfish", lRPWeight=10.0, hRPWeight=15.0, lWeight=0.5, multiplier=0.2},
        {name="Bluefin Tuna", lRPWeight=15.0, hRPWeight=25.0, lWeight=0.5, multiplier=0.25}
    },
}

-- Fishing License item id
local fishLicense = 154

local licenseDetail = {
    "Resident Fisher License (Level 1)",
    "Recreational Fishing Permit (Level 2)",
    "Sport Fisher License (Level 3)",
    "Professional Fishing License (Level 4)",
    "Charter Fishing License (Level 5)"
}

-- Chance dapet ikan setiap tier dan variasinya
local tierChance = 0.7
local multiplierTier = 0
local variantChance = 0.7
local multiplierVariant = 0


-- Save when logging out
addEventHandler("onPlayerQuit", root, function()
    local name = getPlayerName(source)
    if isTimer(activeFishingTimers[source]) then
        killTimer(activeFishingTimers[source])
        activeFishingTimers[source] = nil
    end

    if tblCooldown[name] then
        dbExec(db, "UPDATE `fish_level` SET `level`=?, `amount`=? WHERE `name`=?", tblCooldown[name].level, tblCooldown[name].current, name)
        tblCooldown[name] = nil
    end
end)

-- Mass save on server shutdown
addEventHandler("onResourceStop", resourceRoot, function()
    for name, data in pairs(tblCooldown) do
        dbExec(db, "UPDATE `fish_level` SET `level`=?, `amount`=? WHERE `name`=?", data.level, data.current, name)
    end
end)

-- Jumlah ikan yang bisa dijual sebelum cooldown berdasasarkan level 1-5
local maxFishLevelCap = {5, 7, 7, 9, 11}

-- NPC Name logic is now dynamic based on the ped being interacted with

-- Item ID metal, mur dan baut. Jumlah mur dan metal yang dibutuhkan
local metalId = 91
local murId = 143
local murNeed = {10,20,30,40}
local metalNeed = {2,3,4,5}
local moneyNeed = {3000,5000,7000,9000}


--[[
Penjelasan sistem level mancing
Dari segi flow, level akan naik jika player berhasil menjual ikan dengan jumlah yang sudah ditentukan
Dari segi script, begitu ada yang jual, langsung update ke database
]]--

-- ============== Modul Level ==============

-- Upsert (Update or Insert) to database
function addExp(thePlayer, name, level, current, sold)
    -- Get amount yang pernah dijual + yang sedang dijual
    local total = current + sold

    -- Kalau total lebih dari jumlah yang dibutuhin untuk naik level, trigger event naik level.
    -- Total jadi 0
    if(total >= expList[level] and level < 5)then
        total = 0
        giveFishLic(thePlayer, true)
        return
    end

    -- Update value di memori
    tblCooldown[name].level = level
    tblCooldown[name].current = total
end

-- ============== Modul Give Item Ikan ==============

-- Helper to get nearest hotspot server-side
local function getNearestHotspotServer(player)
    local x, y, z = getElementPosition(player)
    local nearestDist = HOTSPOT_RADIUS -- Default max radius
    local foundSpot = nil
    
    for id, spot in pairs(fishHotspots) do
        -- Only consider normal hotspots OR the single active event hotspot
        if not spot.is_event or (g_FishingEventActive and id == activeEventHotspotID) then
            local radius = spot.is_event and EVENT_HOTSPOT_RADIUS or HOTSPOT_RADIUS
            local dist = getDistanceBetweenPoints3D(x, y, z, spot.x, spot.y, spot.z)
            if dist < radius and dist < nearestDist then
                nearestDist = dist
                foundSpot = spot
            end
        end
    end
    return foundSpot
end

-- ============== Modul Fishing Timer ==============
addEvent("fishing:startTimer", true)
addEventHandler("fishing:startTimer", root, function(rodLevel)
    local player = source
    if isTimer(activeFishingTimers[player]) then
        killTimer(activeFishingTimers[player])
    end
    
    local spot = getNearestHotspotServer(player)
    
    local activeEvent = nil
    if spot and spot.is_event then
        activeEvent = getCurrentFishingEvent and getCurrentFishingEvent() or nil
    end

    local state = "Default"
    if spot then
        state = spot.is_event and "Good" or spot.state
    end
    
    local minT = FISHING_TIMES[state].min
    local maxT = FISHING_TIMES[state].max
    
    -- Event Modifier: Exotic Swarm
    -- Speed mathematically reduced by 50%
    if activeEvent == "Exotic Swarm" then
        minT = minT * 0.5
        maxT = maxT * 0.5
    end
    
    -- Dev override for quick testing
    minT, maxT = 50, 50 
    
    local timeToWait = math.random(minT, maxT)
    
    activeFishingTimers[player] = setTimer(function(p, rLvl)
        if isElement(p) then
            triggerClientEvent(p, "fishing:timerFinished", p, rLvl)
        end
        activeFishingTimers[p] = nil
    end, timeToWait, 1, player, rodLevel)
end)

addEvent("fishing:stopTimer", true)
addEventHandler("fishing:stopTimer", root, function()
    local player = source
    if isTimer(activeFishingTimers[player]) then
        killTimer(activeFishingTimers[player])
    end
    activeFishingTimers[player] = nil
end)

-- Function to give fish type based on rodLevel (level pancingan)
function giveCatch(thePlayer, clientInHotspot, rodLevel)
    local caughtFish = 1 -- Default ikan yang didapatkan adalah ikan level 1
    rodLevel = tonumber(rodLevel) or 1
    
    -- Level player yang mancing
    local name = getPlayerName(thePlayer)
    local playerLevel = 1
    if tblCooldown[name] then
        playerLevel = tblCooldown[name].level
    end
    
    -- Evaluate hotspot server-side to prevent spoofing and identify events
    local spot = getNearestHotspotServer(thePlayer)
    local inHotspot = spot ~= nil
    local inEventHotspot = spot and spot.is_event
    local activeEvent = nil
    
    if inEventHotspot then
        activeEvent = getCurrentFishingEvent and getCurrentFishingEvent() or nil
    end
    
    -- =======================================================
    -- EVENT: Deep Sea Debris (Replaces Loot Pool Entirely)
    -- =======================================================
    if activeEvent == "Deep Sea Debris" then
        -- Weighted Loot Table configuration
        local debrisLootTable = {
            {item = 91, name = "Metal", weight = 40},       -- 40% chance
            {item = 143, name = "Mur dan Baut", weight = 40}, -- 40% chance
            {item = 122, name = "Toll Pass", weight = 10},  -- 10% chance
            {item = 168, name = "Headlights", weight = 9},  -- 9% chance
            {item = 111, name = "Rusty Safe", weight = 1}   -- 1% chance (Rare)
        }

        -- Weighted Randomizer Function
        local totalWeight = 0
        for _, drop in ipairs(debrisLootTable) do
            totalWeight = totalWeight + drop.weight
        end

        local rng = math.random(1, totalWeight)
        local currentWeight = 0
        local droppedItem = nil
        
        for _, drop in ipairs(debrisLootTable) do
            currentWeight = currentWeight + drop.weight
            if rng <= currentWeight then
                droppedItem = drop
                break
            end
        end

        if droppedItem then
            if items:hasSpaceForItem(thePlayer, droppedItem.item, 1) then
                items:giveItem(thePlayer, droppedItem.item, 1)
                outputChatBox("You snagged something from the deep: a " .. droppedItem.name .. "!", thePlayer, 255, 150, 0)
            else
                outputChatBox("You snagged something, but your inventory is full!", thePlayer, 255, 0, 0)
            end
        end
        return -- Bypass standard fish logic
    end
    -- =======================================================

    -- Tier ikan yang di dapat 70% chance dapat tier yang sama dengan level pancingan, 30% chance dapat tier dibawahnya
    local maxRodLevel = 1
    if inHotspot then
        maxRodLevel = tonumber(rodLevel) or 1
    end
    
    for i = maxRodLevel, 2, -1 do
        local roll = math.random() -- Roll apakah dapat ikan di tier ini atau tidak
        if(roll <= tierChance - (tierChance * multiplierTier))then
            caughtFish = i
            break
        end
    end

    -- Fish Variant
    local variant = 1
    if(math.random() > variantChance - (variantChance * multiplierVariant))then
        variant = 2
    end
    
    -- =======================================================
    -- EVENT: Exotic Swarm (The Jackpot Roll)
    -- =======================================================
    if activeEvent == "Exotic Swarm" then
        local jackpotRoll = math.random(1, 100000)
        if jackpotRoll == 1 then -- 0.001% chance
            local jackpotItem = 294 -- Huge Fish (Highest Tier)
            local jackpotWeight = "25.0"
            local jackpotName = "Legendary Golden Swordfish"
            
            if items:hasSpaceForItem(thePlayer, jackpotItem, 1) then
                -- Format: Name (RPWeightkg):GameplayWeight:vVariant:RPWeightValue
                local itemString = jackpotName .. " (" .. jackpotWeight .. "kg):0.5:v2:" .. jackpotWeight
                items:giveItem(thePlayer, jackpotItem, itemString)
                
                -- Server-wide Broadcast
                outputChatBox("[FISHING] WOW! " .. name:gsub("_", " ") .. " just hit the Jackpot and caught a " .. jackpotName .. "!", root, 255, 194, 14)
                return -- Stop normal fish generation
            end
        end
    end
    -- =======================================================

    local fishItem = fishId[caughtFish] -- the item for the caught fish type
    local fishDesc = fishDetail[caughtFish][variant] -- the description for the fish item

    if items:hasSpaceForItem(thePlayer, fishItem, 1) then
        -- Set the actual gameplay weight to be static instead of random
        local actualWeight = string.format("%.1f", fishDesc.lWeight)
        
        -- Generate the RP weight
        local rpWeightVal = fishDesc.lRPWeight + (math.random() * (fishDesc.hRPWeight - fishDesc.lRPWeight))
        local formattedRPWeight = string.format("%.1f", rpWeightVal)
        
        -- Format: Name (RPWeightkg):GameplayWeight:vVariant:RPWeightValue
        local itemString = tostring(fishDesc.name) .. " (" .. formattedRPWeight .. "kg):" .. actualWeight .. ":v" .. tostring(variant) .. ":" .. formattedRPWeight
        items:giveItem(thePlayer, fishItem, itemString)
        outputChatBox("You've caught a " .. formattedRPWeight .. "kg " .. tostring(fishDesc.name) .. "!", thePlayer, 0, 255, 0)
    end


end

-- ============== Modul Jual Ikan ==============

-- Function to check value in array, returns true and index if value is in the array. Returns false and nil otherwise.
function has_value(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true, index
        end
    end

    return false, nil
end

-- Function to sell fish
function sellFish(thePlayer, ped)
    local npcName = ped and (getElementData(ped, "rpp.npc.name") or "Fisherman"):gsub("_", " ") or "Fisherman"
    -- Init level = 1 jika dia pertama kali, get player name yang jual
    local name = getPlayerName(thePlayer)
    local level = 1
    local current = 0
    local countFish = 0
    local query = "SELECT * FROM `fish_level` WHERE `name` = ?" -- Ngecek apakah ini pertama kali dia jual atau tidak
    local levelFish = 0 -- Jumlah ikan yang masuk dan jadi EXP level mancing
    local totalPayment = 0 -- Total pembayaran
    local cooldown = false -- Status cooldown

    -- Cek apa dia ada di table cooldown, kalo ga ada berarti ini pertama kali dia jual setelah cooldown
    if(tblCooldown[name])then
        countFish = tblCooldown[name].amount --Update jumlah ikan yang sudah dijual
        level = tblCooldown[name].level
        current = tblCooldown[name].current
        -- If on cooldown, stop disini and return false
        if(tblCooldown[name].cooldown)then
            exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: Kebanyakan ikan yang tadi dijual, nanti lagi ya!", 255, 255, 255, 10)
            return
        end
    else
        -- Run query select yang diatas jika belum ada di tblCooldown memori, initial load per session
        local qh = dbQuery(db, query, name)
        local result = dbPoll(qh, -1)
        
        if(result and #result > 0)then
            -- Update level jika dia ada di database
            level = tonumber(result[1]["level"])
            current = tonumber(result[1]["amount"])
            tblCooldown[name] = {amount = 0, cooldown = false, current = current, level = level}
            triggerClientEvent(thePlayer, "fishing:updateLevel", thePlayer, level)
        else
            exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: Kamu belum punya Fishing License, silahkan apply dulu ke License Issuer!", 255, 255, 255, 10)
            return
        end
    end
    
    
    -- Loop inven player, cari item yang ikan exp, dan jumlah ikan yang dijual
    for i, val in ipairs(items:getItems(thePlayer)) do
        local itemId, itemValue = unpack(val) -- Unpack item apa aja yang ada di inven
        local isFish, tier = has_value(fishId,itemId) -- Cek apakah item tersebut ikan atau bukan

        -- Cek jika tier ikan lebih tinggi dari level player
        if(isFish and tier > level)then
            exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: Ikan ini terlalu berbahaya untukmu tangani.. Aku tidak bisa menerimanya dari pemula.", 255, 255, 255, 10)
            return
        end

        -- If ikan dan level player memadai untuk menjual ikan dengan tingkatan/tier tersebut, kalkulasi harga jual
        if(isFish and tier<=level)then

            -- Init variable
            countFish = countFish + 1

            -- Cek variant dari string di itemvalue
            local variant = 1
            if(string.find(itemValue, ":v2"))then
                variant = 2
            end
            
            -- Extract the RP weight from the string (last segment after colon)
            -- If not found or legacy string, fallback to 1.0kg multiplier
            local rpWeightStr = string.match(itemValue, ":([%d%.]+)$")
            local rpWeight = 1.0
            if rpWeightStr and tonumber(rpWeightStr) then
                rpWeight = tonumber(rpWeightStr)
            end

            local multiplier = fishDetail[tier][variant].multiplier or 1.0
            -- Price is: basePrice * (multi per variant) * (rpWeight / 1kg)
            local price = math.floor(basePrice * multiplier * rpWeight)

            -- Take item and count payment
            totalPayment = totalPayment + price
            items:takeItem(thePlayer, itemId)

            -- If ikan yang dijual yang memiliki multiplier exp
            if(itemId == fishId[level])then
                levelFish = levelFish + 1
            end

            -- If ikan yang dijual udah maksimal untuk level dia, stop loop.
            if(countFish >= maxFishLevelCap[level])then
                cooldown = true
                break
            end

        end

    end
    -- If ada yang kejual, maka total payment akan lebih dari 0
    if(totalPayment > 0)then

        -- Add the exp to the database, level 5 tidak bisa nambah exp lagi
        if(level < 5)then
            addExp(thePlayer, name, level, current, levelFish)
        end

        -- Cooldown added to table value can be true or false
        tblCooldown[name].amount = countFish;
        tblCooldown[name].cooldown = cooldown;

        -- Give money and send message
        exports.global:giveMoney(thePlayer, totalPayment)
        exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: Ini uang hasil penjualan ikanmu, kembali lagi nanti!", 255, 255, 255, 10)

        -- Disable Cooldown after 10 second, jadiin 15 menit nanti  
        if(cooldown)then
            setTimer(function() 
                
                -- Remove the player from the table after the cooldown is done
                tblCooldown[name].cooldown = false;
                tblCooldown[name].amount = 0;
                outputChatBox("You can sell some fish again!", thePlayer, 0, 255, 0)
            
            end, cooldownTime, 1)
        end
    else
        exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: Mau jual angin? Dateng kalau ada ikan buat dijual!", 255, 255, 255, 10)
    end

end

-- ============== Modul Items ==============

-- Mengambil ketika pancingan patah
function takeRod(thePlayer, rodLevel)
    rodLevel = tonumber(rodLevel) or 1
    local rodItem = rodId[rodLevel]
    return items:takeItem(thePlayer, rodItem)
end

-- Memberikan fishing license, cek ke tabel, baru ngecek ke database 
function giveFishLic(thePlayer, levelUp, ped)
    local npcName = ped and (getElementData(ped, "rpp.npc.name") or "License Issuer"):gsub("_", " ") or "License Issuer"

    local name = getPlayerName(thePlayer)
    local query = "SELECT * FROM `fish_level` WHERE `name` = ?"
    local level = 1

    if(tblCooldown[name])then
        level = tblCooldown[name].level
    else
        local qh = dbQuery(db, query, name)
        local result = dbPoll(qh, -1)
        
        if(result and #result > 0)then
            level = tonumber(result[1]["level"])
            tblCooldown[name] = {amount = 0, cooldown = false, current = tonumber(result[1]["amount"]), level = level}
            triggerClientEvent(thePlayer, "fishing:updateLevel", thePlayer, level)
        else
            dbExec(db, "INSERT INTO `fish_level` (`name`, `level`, `amount`) VALUES (?, 1, 0)", name)
            tblCooldown[name] = {amount = 0, cooldown = false, current = 0, level = 1}
            triggerClientEvent(thePlayer, "fishing:updateLevel", thePlayer, 1)
        end
    end

    if(levelUp)then
        level = level + 1
        tblCooldown[name].level = level
        tblCooldown[name].current = 0
        triggerClientEvent(thePlayer, "fishing:updateLevel", thePlayer, level)
        exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: Selamat anda berhasil naik level!", 255, 255, 255, 10) 
    end

    if(hasFishingLicense(thePlayer, level))then -- Jika player memiliki fishing license yang paling baru
        message = "Wah, izin memancingmu sudah yang paling baru!"
    else
        if(items:hasItem(thePlayer, fishLicense))then
            items:takeItem(thePlayer, fishLicense) -- Ambil license yang lama
        end
        items:giveItem(thePlayer, fishLicense, licenseDetail[level])
        message = "Ini izin memancingmu yang baru, jangan sampai hilang ya!"
    end
    -- Send message
    exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: " .. message, 255, 255, 255, 10) 

end

function hasFishingLicense(thePlayer, level)
    return items:hasItem(thePlayer, fishLicense, licenseDetail[level])
end

function upgradeRod(thePlayer, ped)
    local npcName = ped and (getElementData(ped, "rpp.npc.name") or "Fisherman"):gsub("_", " ") or "Fisherman"
    -- Check for old fishing rod (Item ID 49) to exchange for Level 1 Rod
    if items:hasItem(thePlayer, oldFishingRodId) then
        items:takeItem(thePlayer, oldFishingRodId)
        items:giveItem(thePlayer, 285, 1)
        exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: Saya ganti pancingan lamamu dengan yang baru untuk pemula, kamu bisa mulai memancing di ujung dermaga Santa Maria Beach.", 255, 255, 255, 10)
        return
    end

    for i, rod in ipairs(rodId) do
        local haveRod = items:hasItem(thePlayer, rod)
        -- If orangnya cuman punya pancingan level 5
        if(i==5 and haveRod)then
            exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: Pancinganmu sudah yang paling bagus, kembali dengan pancingan yang lain.", 255, 255, 255, 10)
            return
        -- If orangnya punya pancingan yang sedang di loop
        elseif(haveRod)then
            -- Cek punya mur, metal, duit, dan fishing license satu tingkat lebih tinggi
            local hasMur = items:countItems(thePlayer, murId) >= murNeed[i]
            local hasMetal = items:countItems(thePlayer, metalId) >= metalNeed[i]
            local hasMoney = exports.global:hasMoney(thePlayer, moneyNeed[i])
            local hasFishLic = hasFishingLicense(thePlayer, i+1)
            local message = ""
            
            if(not hasMur)then
                message = "Kamu membutuhkan " .. murNeed[i] .. " Mur dan Baut untuk meningkatkan kualitas pancingan, kembalilah lagi nanti."
            elseif(not hasMetal)then
                message = "Kamu membutuhkan " .. metalNeed[i] .. " Metal untuk meningkatkan kualitas pancingan, kembalilah lagi nanti."
            elseif(not hasMoney)then
                message = "Kamu membutuhkan $" .. moneyNeed[i] .. " untuk membayar biayanya, kembalilah lagi nanti."
            elseif(not hasFishLic)then
                message = "Kamu membutuhkan " .. licenseDetail[i+1] .. " untuk membuat pancingan ini."
            end

            -- Message will be empty if the player has it all in his inventory
            if(message == "")then
                -- Ngambil mur yang dibutuhin
                for j = 1, murNeed[i] do
                    items:takeItem(thePlayer, murId)
                end
                -- Ngambil metal yang dibutuhin
                for j = 1, metalNeed[i] do
                    items:takeItem(thePlayer, metalId)
                end
                -- Ngambil duit
                exports.global:takeMoney(thePlayer, moneyNeed[i])
                items:takeItem(thePlayer, rod) -- Ngambil pancingan yang lama
                items:giveItem(thePlayer, rodId[i+1], 1) -- Ngasih pancingan yang baru
                message = "Selamat menikmati pancingan baru!"

            end
            -- Send message
            exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: " .. message, 255, 255, 255, 10) 
            return
        end

    end
    -- Loop berakhir, dan tidak ada pancingan ditemukan
    exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: Beli Fishing Rod di 24/7 dahulu. Nanti baru upgrade disini.", 255, 255, 255, 10)

end



-- ============== Debug Functions ==============
function giveLicense(thePlayer, command, level) -- Debug only
    outputChatBox("Granted fishing license level "..level.. "!", thePlayer, 0, 255, 0)
    items:giveItem(thePlayer, fishLicense, licenseDetail[tonumber(level)])
end

function giveRod(thePlayer, command, level) -- Debug only
    outputChatBox("Granted fishing rod level "..level.."!", thePlayer, 0, 255, 0)
    items:giveItem(thePlayer, rodId[tonumber(level)], 1)
end

function giveStuff(thePlayer, command, level) -- Debug only
    outputChatBox("Granted items to craft rod level "..level.."!", thePlayer, 0, 255, 0)
    for i = 1, murNeed[tonumber(level)], 1 do
        items:giveItem(thePlayer, murId, 1)
    end
    for i = 1, metalNeed[tonumber(level)], 1 do
        items:giveItem(thePlayer, metalId, 1)
    end
    exports.global:giveMoney(thePlayer, moneyNeed[tonumber(level)])
end

function giveFish(thePlayer, command, level) -- Debug only
    outputChatBox("Catching you a fish with rod level "..level.."!", thePlayer, 0, 255, 0)
    giveCatch(thePlayer, level)
end

-- Fungsi2 untuk proses debug, tidak untuk di up ke server utama
addCommandHandler("sellfish", sellFish)
addCommandHandler("givefish", giveFish)
addCommandHandler("upgraderod", upgradeRod)
addCommandHandler("givelic", giveLicense)
addCommandHandler("giverod", giveRod)
addCommandHandler("givestuff", giveStuff)

-- CMD CHECK & SET LEVEL
addCommandHandler("fishlevel", function(thePlayer, commandName)
    local name = getPlayerName(thePlayer)
    if not tblCooldown[name] then
        outputChatBox("Kamu belum memiliki izin memancing.", thePlayer, 255, 0, 0)
        return
    end
    outputChatBox("Level memancingmu saat ini: " .. tblCooldown[name].level, thePlayer, 0, 255, 0)
end)

addCommandHandler("fishhelp", function(thePlayer, commandName)
    outputChatBox("------- Fishing System Help -------", thePlayer, 255, 194, 14)
    outputChatBox("/fishnew - Start fishing (SMB end or Boat).", thePlayer, 255, 255, 255)
    outputChatBox("/stopfishing - Stop fishing.", thePlayer, 255, 255, 255)
    outputChatBox("/fishlevel - Check your current fishing level and exp.", thePlayer, 255, 255, 255)
    outputChatBox("Tip: Right-click Fishing NPCs to Sell Fish, Upgrade Rod, or Renew License.", thePlayer, 0, 255, 0)

    if exports.integration:isPlayerTrialAdmin(thePlayer) then
        outputChatBox("------- Admin / Debug Commands -------", thePlayer, 255, 0, 0)
        outputChatBox("/triggerfishevent [name] - Start a specific or random event.", thePlayer, 255, 255, 255)
        outputChatBox("/stopfishevent - Stop the current active event.", thePlayer, 255, 255, 255)
        outputChatBox("/fisheventstatus - See active event and time until next event.", thePlayer, 255, 255, 255)
        outputChatBox("/createfishnpc [type] [name] - Create a fishing NPC.", thePlayer, 255, 255, 255)
        outputChatBox("/deletefishnpc [id] - Remove a fishing NPC.", thePlayer, 255, 255, 255)
        outputChatBox("/nearbyfishnpc - Find IDs of nearby fishing NPCs.", thePlayer, 255, 255, 255)
        outputChatBox("/createfishhotspot [region] [is_event] - Create a hotspot.", thePlayer, 255, 255, 255)
        outputChatBox("/deletefishhotspot [id] - Remove a fishing hotspot.", thePlayer, 255, 255, 255)
        outputChatBox("/setfishlevel [player] [level] - Set player fishing level.", thePlayer, 255, 255, 255)
        outputChatBox("/spawnrusty - Force spawn Scrap Dealer Rusty.", thePlayer, 255, 255, 255)
        outputChatBox("/debugfishing - (Client) Toggle hotspot visibility.", thePlayer, 255, 255, 255)
        outputChatBox("/givefish, /giverod, /givelic, /givestuff - Quick debug tools.", thePlayer, 255, 255, 255)
    end
end)

addCommandHandler("setfishlevel", function(thePlayer, commandName, tPlayerName, level)
    if not exports.integration:isPlayerTrialAdmin(thePlayer) then return end
    if not tPlayerName or not level then
        outputChatBox("Syntax: /setfishlevel [Player Name / ID] [Level]", thePlayer, 255, 194, 14)
        return
    end
    
    local targetPlayer, targetPlayerName = exports.global:findPlayerByPartialNick(thePlayer, tPlayerName)
    if not targetPlayer then
        outputChatBox("Pemain tidak ditemukan.", thePlayer, 255, 0, 0)
        return
    end
    
    local newLvl = tonumber(level)
    local name = getPlayerName(targetPlayer)
    if not tblCooldown[name] then
        tblCooldown[name] = {amount = 0, cooldown = false, current = 0, level = newLvl}
    else
        tblCooldown[name].level = newLvl
    end
    
    dbExec(db, "UPDATE `fish_level` SET `level` = ? WHERE `name` = ?", newLvl, name)
    triggerClientEvent(targetPlayer, "fishing:updateLevel", targetPlayer, newLvl)
    
    outputChatBox("Admin " .. getPlayerName(thePlayer) .. " mengatur level memancingmu ke " .. newLvl .. ".", targetPlayer, 0, 255, 0)
    outputChatBox("Anda mengatur level memancing " .. targetPlayerName .. " ke " .. newLvl .. ".", thePlayer, 0, 255, 0)
end)


addEvent("fishing:giveCatch", true)
addEvent("fishing:takeRod", true)
addEvent("fishing:sellFish", true)
addEvent("fishing:giveLic", true)
addEvent("fishing:upgradeRod", true)
addEvent("fishing:applyLicense", true)
addEventHandler("fishing:giveCatch", root, function(inHotspot, rodLevel)
    giveCatch(source, inHotspot, rodLevel)
end)

addEventHandler("fishing:takeRod", root, function(rodLevel)
    takeRod(source, rodLevel)
end)

addEventHandler("fishing:sellFish", root, function(ped)
    sellFish(source, ped)
end)

addEventHandler("fishing:giveLic", root, function(levelUp, ped)
    giveFishLic(source, levelUp, ped)
end)

addEventHandler("fishing:upgradeRod", root, function(ped)
    upgradeRod(source, ped)
end)

addEventHandler("fishing:applyLicense", root, function(ped)
    giveFishLic(source, false, ped)
end)

addEventHandler("onCharacterLogin", root, function()
    local name = getPlayerName(source)
    local query = "SELECT * FROM `fish_level` WHERE `name` = ?"
    dbQuery(function(qh, client)
        if isElement(client) then
            local res = dbPoll(qh, 0)
            if res and #res > 0 then
                local level = tonumber(res[1]["level"])
                tblCooldown[name] = {amount = 0, cooldown = false, current = tonumber(res[1]["amount"]), level = level}
                triggerClientEvent(client, "fishing:updateLevel", client, level)
            else
                triggerClientEvent(client, "fishing:updateLevel", client, 0)
            end
        end
    end, {source}, db, query, name)
end)

-- Commands and Events
--[[

    addEvent("fishing:giveCatch", true)
    addEvent("fishing:takeRod", true)
    addEvent("fishing:GeneratePayment", true)
    addEvent("fishing:sellFish", true)
    addEventHandler("fishing:giveCatch", root, giveCatch)
    addEventHandler("fishing:takeRod", root, takeRod)
    addEventHandler("fishing:GeneratePayment", root, GenerateFishPayment)
    addEventHandler("fishing:sellFish", root, sellFish)
]]

-- ==========================================
-- Scrap Dealer Rusty (Metal Supply)
-- ==========================================

-- Rusty's name is derived from the database row
local metalStock = 0
local scrapCost = 2500

local rustyActiveTimer = nil
local rustyNextTimer = nil
local rustyCheckTimer = nil
local isRustyActive = false
local currentRestockBlock = -1

local rustyPed = nil -- The actual ped element for Rusty

function despawnRusty()
    if isRustyActive then
        local name = (rustyBaseLocation and rustyBaseLocation.name or "Scrap Dealer"):gsub("_", " ")
        if isElement(rustyPed) then
            destroyElement(rustyPed)
        end
        rustyPed = nil
        isRustyActive = false
        outputDebugString("[FISHING] " .. name .. " has despawned.")
    end
end

function spawnRusty()
    if not rustyBaseLocation then
        outputDebugString("[FISHING] Warning: Scrap Dealer location is not placed. Use /createfishnpc scrapper to set a position.")
        return
    end
    
    -- Destroy any lingering ped
    if isElement(rustyPed) then destroyElement(rustyPed) end
    
    local loc = rustyBaseLocation
    local name = loc.name or "Scrap Dealer"
    rustyPed = createPed(loc.skin or 209, loc.x, loc.y, loc.z)
    if not rustyPed then
        outputDebugString("[FISHING] ERROR: Failed to create ped for " .. name)
        return
    end
    
    setElementRotation(rustyPed, 0, 0, loc.rot or 0)
    setElementInterior(rustyPed, loc.int or 0)
    setElementDimension(rustyPed, loc.dim or 0)
    setElementFrozen(rustyPed, true)
    
    -- Tag for the ped-system right-click handler
    setElementData(rustyPed, "fishnpc.id", loc.id)
    setElementData(rustyPed, "fishnpc.type", "scrapper")
    setElementData(rustyPed, "rpp.npc.type", "fishing.scrap")
    setElementData(rustyPed, "rpp.npc.name", name)
    setElementData(rustyPed, "nametag", true)
    setElementData(rustyPed, "name", (name:gsub(" ", "_")))
    
    metalStock = math.random(6, 10)
    isRustyActive = true
    
    -- Notify all players with a Fishing License (item 154)
    for _, p in ipairs(getElementsByType("player")) do
        if exports.global:hasItem(p, 154) then
            outputChatBox("[FISHING] Rumor has it " .. name .. " just arrived at his spot to trade some metal!", p, 255, 194, 14)
        end
    end
    
    outputDebugString("[FISHING] " .. name .. " spawned with " .. metalStock .. " metal.")
    
    if isTimer(rustyActiveTimer) then killTimer(rustyActiveTimer) end
    rustyActiveTimer = setTimer(despawnRusty, 3600000, 1) -- 1 hour despawn
end

function checkAndScheduleRusty()
    local time = getRealTime()
    local currentHour = time.hour
    local blockStartHour = math.floor(currentHour / 3) * 3
    
    if blockStartHour ~= currentRestockBlock then
        currentRestockBlock = blockStartHour
        despawnRusty()
        
        local secondsSinceMidnight = (time.hour * 3600) + (time.minute * 60) + time.second
        local blockStartSeconds = blockStartHour * 3600
        -- Max start time is 2 hours into the 3 hour block
        local latestStartSeconds = (blockStartHour + 2) * 3600
        
        if secondsSinceMidnight >= latestStartSeconds then
            outputDebugString("[FISHING] Rusty missed block " .. blockStartHour .. ":00. Waiting for next.")
        else
            local earliestStart = math.max(secondsSinceMidnight, blockStartSeconds) + 10
            local startSeconds = earliestStart
            if latestStartSeconds > earliestStart then
                startSeconds = math.random(earliestStart, latestStartSeconds)
            end
            
            local msUntilStart = (startSeconds - secondsSinceMidnight) * 1000
            
            if isTimer(rustyNextTimer) then killTimer(rustyNextTimer) end
            if msUntilStart <= 0 then
                spawnRusty()
            else
                rustyNextTimer = setTimer(spawnRusty, msUntilStart, 1)
                outputDebugString("[FISHING] Rusty scheduled to arrive in " .. math.floor(msUntilStart / 60000) .. " mins.")
            end
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    -- Wait 1 second to ensure DB finishes loading rustyBaseLocation
    setTimer(function()
        checkAndScheduleRusty()
        rustyCheckTimer = setTimer(checkAndScheduleRusty, 60000, 0)
    end, 1000, 1)
end)

addEvent("fishing:buyScrap", true)
addEventHandler("fishing:buyScrap", root, function(amount, ped)
    local thePlayer = source
    local npcName = ped and (getElementData(ped, "rpp.npc.name") or "Scrap Dealer"):gsub("_", " ") or "Scrap Dealer"
    amount = tonumber(amount)
    if not amount or amount <= 0 or amount ~= math.floor(amount) then
        exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: How many pieces of scrap do you want? Don't waste my time.", 255, 255, 255, 10)
        return
    end
    
    if ped and isElement(ped) then
        local rx, ry, rz = getElementPosition(ped)
        local px, py, pz = getElementPosition(thePlayer)
        if getDistanceBetweenPoints3D(px, py, pz, rx, ry, rz) > 5 or getElementDimension(thePlayer) ~= getElementDimension(ped) or getElementInterior(thePlayer) ~= getElementInterior(ped) then
            outputChatBox("You must be near " .. npcName .. " to use this command.", thePlayer, 255, 0, 0)
            return
        end
    end
    
    if metalStock < amount then
        exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: Look around, pal. I only got " .. metalStock .. " pieces left. Wait till I restock.", 255, 255, 255, 10)
        return
    end
    
    local cost = amount * scrapCost
    if not exports.global:takeMoney(thePlayer, cost) then
        exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: You're short on cash! That'll be $" .. exports.global:formatMoney(cost) .. ".", 255, 255, 255, 10)
        return
    end
    
    metalStock = metalStock - amount
    
    for i = 1, amount do
        exports.global:giveItem(thePlayer, metalId, 1)
    end
    
    exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: Hands off the merchandise! Here's your " .. amount .. " scrap. Don't tell the mob.", 255, 255, 255, 10)
    outputChatBox("You purchased " .. amount .. " Metal for $" .. exports.global:formatMoney(cost) .. ".", thePlayer, 0, 255, 0)
end)
