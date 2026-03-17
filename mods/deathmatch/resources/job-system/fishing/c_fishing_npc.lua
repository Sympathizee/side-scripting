-- =======================================================
-- CONFIGURATION & DIALOGUES
-- =======================================================

local localPlayer = getLocalPlayer()

-- Item IDs & Requirements
local rodId = {49, 286, 287, 288, 289}
local licenseDetail = {
    "Resident Fisher License (Level 1)",
    "Recreational Fishing Permit (Level 2)",
    "Sport Fisher License (Level 3)",
    "Professional Fishing License (Level 4)",
    "Charter Fishing License (Level 5)"
}

-- Rod Upgrade Recipes (Managed by NPC-system's Crafting UI)
local rodRecipes = {
    {
        name = "Riverbend Rod (Level 2)",
        resultID = 286,
        resultValue = "1",
        image = ":job-system/fishing/pancingan-2.png",
        ingredients = {
            { id = 49, amount = 1, name = "Original Fishing Rod" },
            { id = 143, amount = 10, name = "Mur dan Baut" },
            { id = 91, amount = 2, name = "Metal" },
            { id = 134, amount = 3000, name = "Money" },
            { id = 154, amount = 1, value = licenseDetail[2], name = licenseDetail[2] }
        }
    },
    {
        name = "Oakstream Rod (Level 3)",
        resultID = 287,
        resultValue = "1",
        image = ":job-system/fishing/pancingan-3.png",
        ingredients = {
            { id = 286, amount = 1, name = "Riverbend Rod" },
            { id = 143, amount = 20, name = "Mur dan Baut" },
            { id = 91, amount = 3, name = "Metal" },
            { id = 134, amount = 5000, name = "Money" },
            { id = 154, amount = 1, value = licenseDetail[3], name = licenseDetail[3] }
        }
    },
    {
        name = "Mariner's Rod (Level 4)",
        resultID = 288,
        resultValue = "1",
        image = ":job-system/fishing/pancingan-4.png",
        ingredients = {
            { id = 287, amount = 1, name = "Oakstream Rod" },
            { id = 143, amount = 30, name = "Mur dan Baut" },
            { id = 91, amount = 4, name = "Metal" },
            { id = 134, amount = 7000, name = "Money" },
            { id = 154, amount = 1, value = licenseDetail[4], name = licenseDetail[4] }
        }
    },
    {
        name = "Thunderstrike Rod (Level 5)",
        resultID = 289,
        resultValue = "1",
        image = ":job-system/fishing/pancingan-5.png",
        ingredients = {
            { id = 288, amount = 1, name = "Mariner's Rod" },
            { id = 143, amount = 40, name = "Mur dan Baut" },
            { id = 91, amount = 5, name = "Metal" },
            { id = 134, amount = 9000, name = "Money" },
            { id = 154, amount = 1, value = licenseDetail[5], name = licenseDetail[5] }
        }
    }
}

-- NPC Dialogue Trees
local dialogueFishingFisher = {
    [1] = {
        question = "Hey there! Got some fresh catch to sell, or looking for gear upgrades?",
        options = {
            "1. I want to sell my fish.",
            "2. I want to upgrade my fishing rod.",
            "3. Maybe later."
        },
        callbacks = {[1] = "fishing:npc:sell", [2] = "fishing:npc:upgrade"},
        rejections = {[3] = "Alright, see ya around!"}
    }
}

local dialogueFishingLicense = {
    [1] = {
        question = "Hello! Do you need to apply for or renew your fishing license?",
        options = {
            "1. Yes, I need a new license.",
            "2. No, just checking in."
        },
        callbacks = {[1] = "fishing:npc:license"},
        rejections = {[2] = "Have a nice day."}
    }
}

local dialogueFishingScrapper = {
    [1] = {
        question = "Whaddaya want? I got some scrap metal if you've got the cash. $2,500 per piece.",
        options = {
            "1. Buy 1x Metal ($2,500)",
            "2. I'll pass."
        },
        callbacks = {[1] = "fishing:npc:scrap"},
        rejections = {[2] = "Suit yourself. Beat it."}
    }
}

-- Event Handlers for Dialogue Callbacks
addEvent("fishing:npc:sell", true)
addEventHandler("fishing:npc:sell", localPlayer, function(npc)
    outputDebugString("[FISHING-NPC] Event: fishing:npc:sell for " .. tostring(npc))
    triggerServerEvent("fishing:sellFish", localPlayer, npc)
end)

addEvent("fishing:npc:upgrade", true)
addEventHandler("fishing:npc:upgrade", localPlayer, function(npc)
    outputDebugString("[FISHING-NPC] Event: fishing:npc:upgrade for " .. tostring(npc))
    exports["NPC-system"]:openCraftingUI(rodRecipes, npc)
end)

addEvent("fishing:npc:license", true)
addEventHandler("fishing:npc:license", localPlayer, function(npc)
    outputDebugString("[FISHING-NPC] Event: fishing:npc:license for " .. tostring(npc))
    triggerServerEvent("fishing:applyLicense", localPlayer, npc)
end)

addEvent("fishing:npc:scrap", true)
addEventHandler("fishing:npc:scrap", localPlayer, function(npc)
    outputDebugString("[FISHING-NPC] Event: fishing:npc:scrap for " .. tostring(npc))
    triggerServerEvent("fishing:buyScrap", localPlayer, 1, npc)
end)

-- Interaction handler
addEventHandler("onClientClick", root, function(button, state, absX, absY, wx, wy, wz, element)
    if button == "right" and state == "down" and isElement(element) then
        local npcType = getElementData(element, "fishnpc.type")
        if not npcType then return end
        
        -- Mapping NPC Types to Actions
        if npcType == "fisher" then
            exports["NPC-system"]:startCinematicDialogue(element, dialogueFishingFisher, nil, nil, true)
        elseif npcType == "license" then
            exports["NPC-system"]:startCinematicDialogue(element, dialogueFishingLicense, nil, nil, true)
        elseif npcType == "scrapper" then
            exports["NPC-system"]:startCinematicDialogue(element, dialogueFishingScrapper, nil, nil, true)
        end
    end
end)
