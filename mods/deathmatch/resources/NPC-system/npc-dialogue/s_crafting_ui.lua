-- ========================================================
-- s_crafting_ui.lua
-- Server-side transaction handler for crafting.
-- ========================================================

-- Helper to check if item is money (Standard ID 134 in this system)
local function isMoneyItem(id)
    return id == 134
end

local function getIngredientCount(player, id)
    if isMoneyItem(id) then
        return exports.global:getMoney(player)
    else
        return exports["item-system"]:countItems(player, id) or 0
    end
end

local function takeIngredient(player, id, amount)
    if isMoneyItem(id) then
        return exports.global:takeMoney(player, amount)
    else
        return exports["item-system"]:takeItem(player, id, amount)
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
            availability[i][j] = getIngredientCount(player, ing.id)
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
        local hasAmount = getIngredientCount(player, ing.id)
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
    local consumedAll = true
    for _, ing in ipairs(recipe.ingredients or {}) do
        if not takeIngredient(player, ing.id, ing.amount) then
            consumedAll = false
        end
    end

    if not consumedAll then
        exports.global:sendLocalText(npc or player, "[Inggris] " .. npcName .. " says: Ada masalah teknis, coba lagi nanti.", 255, 255, 255, 10)
        triggerClientEvent(player, "crafting:feedback", player, false, "")
        return
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
