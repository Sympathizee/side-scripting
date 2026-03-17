-- =======================================================
-- CONFIGURATION & LOOT TABLES
-- =======================================================

-- DEEP SEA DEBRIS LOOT
DEBRIS_LOOT_TABLE = {
    {item = 91, name = "Metal", weight = 40},       -- 40% chance
    {item = 143, name = "Mur dan Baut", weight = 40}, -- 40% chance
    {item = 122, name = "Toll Pass", weight = 10},  -- 10% chance
    {item = 168, name = "Headlights", weight = 9},  -- 9% chance
    {item = 111, name = "Rusty Safe", weight = 1}   -- 1% chance (Rare Item 1)
}

-- EXOTIC SWARM JACKPOT
JACKPOT_CHANCE = 100000 -- 1 in 100,000
JACKPOT_ITEM_ID = 294   -- Bluefin Tuna (Level 5, Variant 2)
JACKPOT_WEIGHT = "50.0" -- Max weight
JACKPOT_NAME = "Legendary Bluefin Tuna"

-- =======================================================
-- CORE REWARD DISPATCHER
-- =======================================================

-- Mapping of Event Names to their reward functions
local eventHandlers = {
    ["Deep Sea Debris"] = handleDebrisReward,
    ["Exotic Swarm"] = handleExoticSwarmReward,
}

-- =======================================================
-- EVENT HANDLERS
-- =======================================================

-- Logic for: Deep Sea Debris
local function handleDebrisReward(thePlayer)
    local items = exports['item-system']
    local playerName = getPlayerName(thePlayer):gsub("_", " ")

    local totalWeight = 0
    for _, drop in ipairs(DEBRIS_LOOT_TABLE) do
        totalWeight = totalWeight + drop.weight
    end

    local rng = math.random(1, totalWeight)
    local currentWeight = 0
    local droppedItem = nil
    
    for _, drop in ipairs(DEBRIS_LOOT_TABLE) do
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
            if droppedItem.item == 111 then -- Rare Item Broadcast
                outputDebugString("[FISHING] " .. playerName .. " caught a rare Rusty Safe!")
            end
        else
            outputChatBox("You snagged something, but your inventory is full!", thePlayer, 255, 0, 0)
        end
    end
    return true -- Logic handled
end

-- Logic for: Exotic Swarm (Jackpot)
local function handleExoticSwarmReward(thePlayer)
    local items = exports['item-system']
    local playerName = getPlayerName(thePlayer):gsub("_", " ")

    local jackpotRoll = math.random(1, JACKPOT_CHANCE)
    if jackpotRoll == 1 then
        if items:hasSpaceForItem(thePlayer, JACKPOT_ITEM_ID, 1) then
            -- Format: Name (RPWeightkg):GameplayWeight:vVariant:RPWeightValue
            local itemString = JACKPOT_NAME .. " (" .. JACKPOT_WEIGHT .. "kg):0.5:v2:" .. JACKPOT_WEIGHT
            items:giveItem(thePlayer, JACKPOT_ITEM_ID, itemString)
            
            -- Server-wide Broadcast
            outputChatBox("[FISHING] WOW! " .. playerName .. " just hit the Jackpot and caught a " .. JACKPOT_NAME .. "!", root, 255, 194, 14)
            return true -- Logic handled
        end
    end
    return false -- Jackpot missed
end

function handleEventRewards(thePlayer, activeEvent)
    local handler = eventHandlers[activeEvent]
    if handler then
        return handler(thePlayer)
    end
    return false -- No handler found or event missed
end
