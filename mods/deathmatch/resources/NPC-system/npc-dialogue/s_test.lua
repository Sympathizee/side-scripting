-- ========================================================
-- s_test.lua
-- Test script to spawn a dialogue and a crafting NPC.
-- ========================================================

addEventHandler("onResourceStart", resourceRoot, function()
    outputDebugString("[NPC] Test script loaded. Usage: /spawnnpcstest")
end)

addCommandHandler("spawnnpcstest", function(player, cmd)
    -- Permission check removed for testing

    local x, y, z = getElementPosition(player)

    -- Spawn Dialogue Test NPC
    spawnNPC("test_dialogue_1", {
        x = x + 2, y = y, z = z, rot = 0,
        skin = 120,
        name = "Tester Dialogue",
        type = "dialogue_test"
    })

    -- Spawn Crafting Test NPC
    spawnNPC("test_crafting_1", {
        x = x - 2, y = y, z = z, rot = 0,
        skin = 121,
        name = "Tester Crafting",
        type = "crafting_test"
    })

    outputChatBox("Successfully spawned Test NPCs (Dialogue and Crafting). Right click them to test.", player, 0, 255, 0)
end)

addCommandHandler("gettestitems", function(player, cmd)
    local items = {
        { id = 15, amount = 2, name = "Water" },
        { id = 28, amount = 4, name = "Glowstick" },
        { id = 13, amount = 1, name = "Donut" }
    }
    
    for _, item in ipairs(items) do
        exports["item-system"]:giveItem(player, item.id, item.amount)
    end
    
    -- Give $5000
    exports.global:giveMoney(player, 5000)
    
    outputChatBox("You've received the test items and $5000 for crafting!", player, 0, 255, 0)
end)
