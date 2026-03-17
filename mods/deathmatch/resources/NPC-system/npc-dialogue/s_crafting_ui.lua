-- ========================================================
-- s_crafting_ui.lua
-- Server-side transaction handler for crafting.
-- ========================================================

-- Helper to check if item is money (Standard ID 134 in this system)
local function isMoneyItem(id)
    return id == 134
end

-- ID 154 is Fishing License
local function isLicenseItem(id)
    return id == 154
end

local function getLicenseLevel(value)
    if not value or type(value) ~= "string" then return 0 end
    local level = value:match("%(Level (%d+)%)")
    return tonumber(level) or 0
end

local function getIngredientCount(player, id, value)
    local count = 0
    if isMoneyItem(id) then
        count = exports.global:getMoney(player)
    elseif isLicenseItem(id) then
        -- Hierarchical check: If player has ANY license with Level >= required Level, count as 1
        local requiredLevel = getLicenseLevel(value)
        local playerItems = exports["item-system"]:getItems(player) or {}
        for _, item in ipairs(playerItems) do
            if item[1] == id then -- ID matches
                local playerLevel = getLicenseLevel(item[2])
                if playerLevel >= requiredLevel then
                    count = 1 -- Satisfied
                    break
                end
            end
        end
    else
        count = exports["item-system"]:countItems(player, id, value) or 0
    end
    outputDebugString(string.format("[CRAFTING-DEBUG] Player %s: Count for ID %s (val: %s) = %s", getPlayerName(player), tostring(id), tostring(value), tostring(count)))
    return count
end

local function takeIngredient(player, id, amount, value)
    if isMoneyItem(id) then
        return exports.global:takeMoney(player, amount)
    elseif isLicenseItem(id) then
        -- Licenses are NOT consumed as ingredients
        return true
    else
        -- Loop to take items one by one if amount > 1
        -- (Most item systems take 1 per call unless they support stackable amount argument)
        local successCount = 0
        for i = 1, amount do
            if exports["item-system"]:takeItem(player, id, value) then
                successCount = successCount + 1
            else
                break
            end
        end
        return successCount == amount
    end
end

addEvent("crafting:getAvailability", true)
addEventHandler("crafting:getAvailability", root, function(recipeList)
    local player = client
    if not player or not recipeList then return end
    
    local availability = {}
    for i, recipe in ipairs(recipeList) do
        availability[i] = {}
        for j, ing in ipairs(recipe.ingredients or {}) do
            availability[i][j] = getIngredientCount(player, ing.id, ing.value)
        end
    end
    
    triggerClientEvent(player, "crafting:receiveAvailability", player, availability)
end)

addEvent("crafting:tryCraft", true)
addEventHandler("crafting:tryCraft", root, function(recipe, npc)
    local player = client
    if not player or not recipe then return end

    local npcName = "NPC"
    if isElement(npc) then
        npcName = (getElementData(npc, "name") or "NPC"):gsub("_", " ")
    end

    -- 1. Validate Ingredients
    local missing = {}
    for _, ing in ipairs(recipe.ingredients or {}) do
        local hasAmount = getIngredientCount(player, ing.id, ing.value)
        if hasAmount < ing.amount then
            table.insert(missing, (ing.name or "Item #"..ing.id))
        end
    end

    if #missing > 0 then
        local msg = "Kamu tidak mempunyai " .. table.concat(missing, ", ") .. ", kembali lagi jika sudah memiliki semua itu!"
        exports.global:sendLocalText(npc or player, "[Inggris] " .. npcName .. " says: " .. msg, 255, 255, 255, 10)
        triggerClientEvent(player, "crafting:feedback", player, false, "")
        return
    end

    -- 2. Check Space for Result
    if not exports["item-system"]:hasSpaceForItem(player, recipe.resultID, recipe.resultValue or 1) then
        exports.global:sendLocalText(npc or player, "[Inggris] " .. npcName .. " says: Tasmu sudah penuh, kosongkan dulu!", 255, 255, 255, 10)
        triggerClientEvent(player, "crafting:feedback", player, false, "")
        return
    end

    -- 3. Consume Ingredients
    for _, ing in ipairs(recipe.ingredients or {}) do
        outputDebugString("[CRAFTING-SERVER] Attempting to take " .. tostring(ing.name) .. " (ID: " .. tostring(ing.id) .. ") x" .. tostring(ing.amount) .. " val: " .. tostring(ing.value))
        if not takeIngredient(player, ing.id, ing.amount, ing.value) then
            outputDebugString("[CRAFTING-SERVER] FAILED to take " .. tostring(ing.name), 1)
            local itemName = ing.name or "Item #"..ing.id
            exports.global:sendLocalText(npc or player, "[Inggris] " .. npcName .. " says: Maaf, ada masalah saat mengambil " .. itemName .. ". Coba cek inventarismu.", 255, 255, 255, 10)
            triggerClientEvent(player, "crafting:feedback", player, false, "")
            return
        end
    end

    -- 4. Give Result
    local success = exports["item-system"]:giveItem(player, recipe.resultID, recipe.resultValue or 1)
    if success then
        local itemName = recipe.name or "ini"
        exports.global:sendLocalText(npc or player, "[Inggris] " .. npcName .. " says: Ini " .. itemName .. ", jangan sampai hilang!", 255, 255, 255, 10)
        triggerClientEvent(player, "crafting:feedback", player, true, "")
    else
        exports.global:sendLocalText(npc or player, "[Inggris] " .. npcName .. " says: Gagal memberikan barang, lapor admin.", 255, 255, 255, 10)
        triggerClientEvent(player, "crafting:feedback", player, false, "")
    end
end)
