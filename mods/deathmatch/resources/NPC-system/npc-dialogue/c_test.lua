-- ========================================================
-- c_test.lua
-- Test script for interacting with Dialogue and Crafting NPCs.
-- ========================================================

-- Define a test dialogue
local testDialogue = {
    [1] = {
        question = "Hello there! Are you here to test my dialogue system?",
        options = {
            "1. Yes, I am testing it.",
            "2. No, just wandering around.",
            "3. Who are you?",
            "4. Goodbye."
        },
        correct = 1,
        rejections = {
            [2] = "Oh, well, enjoy your walk then.",
            [3] = "I'm just a tester NPC, built for this.",
            [4] = "See you later."
        }
    },
    [2] = {
        question = "Great! It seems to be working perfectly. Want your reward?",
        options = {
            "1. Give it to me!",
            "2. No, I don't want a reward.",
            "3. Maybe later.",
            "4. Leave me alone."
        },
        correct = 1,
        rejections = {
            [2] = "Suit yourself.",
            [3] = "I'll be here.",
            [4] = "How rude!"
        }
    }
}

-- Define test recipes (includes 3 generic items and $5000)
local testRecipes = {
    {
        name = "Secret Stash (Test)",
        resultID = 1, -- Rewards a Hotdog
        resultValue = "1",
        image = 1,
        ingredients = {
            { id = 15, amount = 2, name = "Water" },
            { id = 28, amount = 4, name = "Glowstick" },
            { id = 13, amount = 1, name = "Donut" },
            { id = 134, amount = 5000, name = "Money" }
        }
    }
}

-- Handle interactions
addEventHandler("onClientClick", root, function(button, state, absX, absY, wx, wy, wz, element)
    if button == "right" and state == "down" and isElement(element) then
        local npcType = getElementData(element, "npc-module:type")
        local isManaged = getElementData(element, "npc-module:managed")
        
        if isManaged then
            if npcType == "dialogue_test" then
                startCinematicDialogue(element, testDialogue, "onTestDialogueSuccess", "onTestDialogueFail")
            elseif npcType == "crafting_test" then
                openCraftingUI(testRecipes, element)
            end
        end
    end
end)

-- Dialogue Events
addEvent("onTestDialogueSuccess", true)
addEventHandler("onTestDialogueSuccess", localPlayer, function(npc)
    outputChatBox("Test Dialogue Completed Successfully!", 0, 255, 0)
end)

addEvent("onTestDialogueFail", true)
addEventHandler("onTestDialogueFail", localPlayer, function(npc, reason)
    outputChatBox("Test Dialogue Failed: " .. tostring(reason), 255, 0, 0)
end)
