local rodId = {285,286,287,288,289}
local items = exports['item-system']
local showAllHotspots = false

-- Hotspot Constants
local HOTSPOT_BLIP_SIZE = 3
local EVENT_HOTSPOT_BLIP_SIZE = 6
local HOTSPOT_RADIUS = 50
local EVENT_HOTSPOT_RADIUS = 75
local BLIP_DISTANCE_LIMIT = 200

isFishingActive = false
currentFishingLevel = 0

addEvent("fishing:updateLevel", true)
addEventHandler("fishing:updateLevel", root, function(level)
    currentFishingLevel = tonumber(level) or 0
end)

addEvent("fishing:receiveHotspots", true)
addEvent("fishing:minigameResult", true)
-- Initial data loading

-- Pancingan dibuat bisa patah supaya bisa beli terus juga
local snappedCaught = 0.02 -- 2% chance patah jika dapet ikan
local snappedEscaped = 0.05 -- 5% chance pancingan patah jika ikan lepas

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("fishing:requestInitialData", localPlayer)
end)

local hotspotMarkers = {}
local hotspotBlips = {}
local activeHotspots = {}
local isEventActiveClient = false

function updateHotspotVisibility()
    local px, py, pz = getElementPosition(localPlayer)
    local isNearBoat = onBoat()
    local canSeeMarker = showAllHotspots
    
    for id, spot in pairs(activeHotspots) do
        local dist = getDistanceBetweenPoints3D(px, py, pz, spot.x, spot.y, spot.z)
        -- Check if event requirement is met
        local eventAllows = not spot.is_event or isEventActiveClient
        
        -- Blip visibility: show if (showAllHotspots) OR (onBoat AND within distance)
        -- Note: We allow event blips to always show if event is active to help players find them
        local withinDistance = dist < BLIP_DISTANCE_LIMIT
        local canSeeBlip = showAllHotspots or (isNearBoat and (withinDistance or spot.is_event))
        
        -- Blip Handling
        if eventAllows and canSeeBlip then
            if not isElement(hotspotBlips[id]) then
                local r, g, b = 255, 255, 255
                local blipSize = HOTSPOT_BLIP_SIZE
                
                if spot.is_event then
                    r, g, b = 0, 255, 255
                    blipSize = EVENT_HOTSPOT_BLIP_SIZE
                elseif spot.state == "Good" then
                    r, g, b = 0, 255, 0
                elseif spot.state == "Medium" then
                    r, g, b = 255, 255, 0
                elseif spot.state == "Bad" then
                    r, g, b = 255, 0, 0
                end
                hotspotBlips[id] = createBlip(spot.x, spot.y, spot.z, 0, blipSize, r, g, b, 255, 0, 99999)
            end
        else
            if isElement(hotspotBlips[id]) then
                destroyElement(hotspotBlips[id])
                hotspotBlips[id] = nil
            end
        end

        -- Marker Handling (Only in debug mode)
        if eventAllows and canSeeMarker then
            if not isElement(hotspotMarkers[id]) then
                local r, g, b = 255, 255, 255
                local size = HOTSPOT_RADIUS
                
                if spot.is_event then
                    r, g, b = 0, 255, 255
                    size = EVENT_HOTSPOT_RADIUS
                elseif spot.state == "Good" then
                    r, g, b = 0, 255, 0
                elseif spot.state == "Medium" then
                    r, g, b = 255, 255, 0
                elseif spot.state == "Bad" then
                    r, g, b = 255, 0, 0
                end
                hotspotMarkers[id] = createMarker(spot.x, spot.y, -50, "checkpoint", size, r, g, b, 100)
            end
        else
            if isElement(hotspotMarkers[id]) then
                destroyElement(hotspotMarkers[id])
                hotspotMarkers[id] = nil
            end
        end
    end
end

-- Refresh visibility periodically (every 5 seconds to save performance)
setTimer(updateHotspotVisibility, 5000, 0)

addEventHandler("fishing:receiveHotspots", root, function(hotspots, isEventActive)
    outputDebugString("[FISHING] Received hotspots from server.")
    activeHotspots = hotspots
    isEventActiveClient = isEventActive or false
    
    -- Clear current elements before recreating
    for id, marker in pairs(hotspotMarkers) do
        if isElement(marker) then destroyElement(marker) end
    end
    hotspotMarkers = {}
    
    for id, blip in pairs(hotspotBlips) do
        if isElement(blip) then destroyElement(blip) end
    end
    hotspotBlips = {}
    
    -- Next timer tick will create the elements if needed
    updateHotspotVisibility()
end)

-- Col untuk mancing di ujung SMB saja
--   0 0 349.0771484375 -2089.2978515625 7.8300905227661 Koordinat yang saya pakai
-- Di paling ujung tempat bianglala SMB
local smbCol = createColRectangle(349.0771484375, -2089.2978515625, 61.0, 2.0)
-- ============== Helping Function(s) ==============

function has_value(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true, index
        end
    end
    return false, nil
end

-- ============== Modul Start Fishing ==============

function startFishing(command)
    local currentRodLevel = nil
    -- get pancingan yang sekarang dipake, diambil pancingan yang terkecil levelnya
    for i, rod in ipairs(rodId) do
        local haveRod = items:hasItem(localPlayer, rod)
        if(haveRod)then
            currentRodLevel = i
            break
        end
    end

    -- Mulai memancing
    if currentRodLevel then
        if isFishingActive then
            outputChatBox("Kamu sedang memancing...", 255, 0, 0)
        else 
            if isPedInVehicle(localPlayer) then
                return outputChatBox("Tidak dapat memancing sambil berlayar.", 255, 0, 0) 
            end
            local hotspotState = getNearestHotspot()
            local fishingLevel = currentFishingLevel

            if (currentRodLevel > fishingLevel) then
                return outputChatBox("Pancinganmu tidak cocok dengan kemampuan memancingmu!", 255, 0, 0)
            end

            if fishingLevel == 0 then
                return outputChatBox("Kamu butuh Fishing License untuk memancing!", 255, 0, 0)
            end

            local allowed = false
            local reason = "Kamu tidak dapat memancing di sini."

            if fishingLevel == 1 then
                if atSMB() then
                    allowed = true
                else
                    reason = "Level 1 hanya bisa memancing di area Santa Maria Beach (SMB)."
                end
            elseif fishingLevel >= 2 then
                if atSMB() or onBoat() then
                    allowed = true
                else
                    reason = "Level 2+ bisa memancing di SMB atau di laut menggunakan kapal."
                end
            end

            if allowed then
                triggerServerEvent("sendAmeClient", localPlayer, "melemparkan pancingnya ke laut.")
                triggerServerEvent("artifacts:add", localPlayer, localPlayer, "rod")
                isFishingActive = true
                
                triggerServerEvent("fishing:startTimer", localPlayer, currentRodLevel)
                
                outputChatBox("Gunakan /stopfishing untuk berhenti memancing kapan saja.", 0, 255, 0)
            else 
                outputChatBox(reason, 255, 0, 0)
            end
        end
    else
        outputChatBox("Kamu tidak memiliki pancingan.", 255, 0, 0)
    end
end

-- ============== Modul Check Boat ==============

function onBoat()
    local element = getPedContactElement(localPlayer)
    local px, py, pz = getElementPosition(localPlayer)

    if (isElement(element)) and (getVehicleType(element) == "Boat") and testLineAgainstWater(px, py, pz, px, py, pz - 25) then
        return true
    else 
        return false
    end
end

function atSMB()
    return isInsideColShape(smbCol, getElementPosition(localPlayer))
end

function getNearestHotspot()
    local x, y, z = getElementPosition(localPlayer)
    local nearestDist = 50 -- 50 meters radius
    local state = nil
    
    for id, spot in pairs(activeHotspots) do
        -- If it's an event hotspot, only consider it if the event is active.
        -- We'll also give event hotspots a much larger radius.
        if not spot.is_event or isEventActiveClient then
            local radius = spot.is_event and EVENT_HOTSPOT_RADIUS or HOTSPOT_RADIUS -- Event hotspots are larger
            local dist = getDistanceBetweenPoints3D(x, y, z, spot.x, spot.y, spot.z)
            
            if dist < radius and dist < nearestDist then
                nearestDist = dist
                -- Treat event hotspots as "Good" state for fishing times/rates
                state = spot.is_event and "Good" or spot.state
            end
        end
    end
    return state
end

-- ============== Modul Dialog Ped ==============

addEvent("fishing:timerFinished", true)
addEventHandler("fishing:timerFinished", root, function(currentRodLevel)
    if not isFishingActive then return end
    
    local fishingLevel = currentFishingLevel
    local stillAllowed = false
    if fishingLevel == 1 then
        if atSMB() then stillAllowed = true end
    elseif fishingLevel >= 2 then
        if atSMB() or onBoat() then stillAllowed = true end
    end
    
    if not stillAllowed then
        endFishing()
        return outputChatBox("Anda tidak bisa memancing disini.", 255, 0, 0)
    end
    
    exports.hud:sendBottomNotification(localPlayer, "Fishing", "Pancingan anda digigit! Jaga ikan di dalam area hijau!")
    startStardewFishingMinigame(currentRodLevel, "c_fishing")
end)

function endFishing()
    if isFishingActive then

        triggerServerEvent("fishing:stopTimer", localPlayer)

        triggerServerEvent("artifacts:remove", localPlayer, localPlayer, "rod")
        triggerServerEvent("sendAmeClient", localPlayer, "reels in his line.")
        isFishingActive = false
    end
end

addEventHandler("fishing:minigameResult", root, function(success, rodLevel)
    if success then
        endFishing()
        local hotspotState = getNearestHotspot()
        local inHotspot = hotspotState ~= nil
        triggerServerEvent("fishing:giveCatch", localPlayer, inHotspot, rodLevel)
    else
        endFishing()
        local snap = math.random()
        if (snap < snappedEscaped) then
            outputChatBox("Saat menarik ikan, pancinganmu patah dan ikan terlepas.", 255, 0, 0)
            triggerServerEvent("fishing:takeRod", localPlayer, rodLevel)
        else
            outputChatBox("Ikan melepaskan gigitannya, kamu tidak mendapatkan apa-apa.", 255, 0, 0)
        end
    end
end)

function npcRightClick(button, state, absX, absY, wx, wy, wz, element)
    if (element) and (getElementType(element)=="ped") and (button=="right") and (state=="down") then
		local npc_type = getElementData(element, "fishnpc.type")
        local pedName = (getElementData(element, "rpp.npc.name") or "Fisherman"):gsub("_", " ")

        if(npc_type == "fisher") then 
            local rcMenu = exports.rightclick:create(pedName)
            local sell = exports.rightclick:addRow("Jual Ikan")
            local upgradeRod = exports.rightclick:addRow("Perbaharui Pancingan")
            addEventHandler("onClientGUIClick", sell,  function (button, state)
                triggerServerEvent("fishing:sellFish", localPlayer, element)
            end, false)
            addEventHandler("onClientGUIClick", upgradeRod,  function (button, state)
                triggerServerEvent("fishing:upgradeRod", localPlayer, element)
            end, false)
            local close = exports.rightclick:addRow("Close")
            addEventHandler("onClientGUIClick", close,  function (button, state)
                exports.rightclick:destroy(rcMenu)
            end, false)
        elseif(npc_type == "license") then
            local rcMenu = exports.rightclick:create(pedName)
            local apply = exports.rightclick:addRow("Perbaharui Izin Memancing")
            local close = exports.rightclick:addRow("Close")
            
            addEventHandler("onClientGUIClick", apply,  function (button, state)
                triggerServerEvent("fishing:applyLicense", localPlayer, element)
            end, false)
            addEventHandler("onClientGUIClick", close,  function (button, state)
                exports.rightclick:destroy(rcMenu)
            end, false)
        elseif(npc_type == "scrapper") then
            local rcMenu = exports.rightclick:create(pedName)
            local buyMetal = exports.rightclick:addRow("Buy 1x Metal ($2,500)")
            local close = exports.rightclick:addRow("Close")
            
            addEventHandler("onClientGUIClick", buyMetal,  function (button, state)
                triggerServerEvent("fishing:buyScrap", localPlayer, 1, element)
            end, false)
            addEventHandler("onClientGUIClick", close,  function (button, state)
                exports.rightclick:destroy(rcMenu)
            end, false)
        end
    end
end

function DestroySellingGUI()
    if isElement(sellfishGUI) then
        destroyElement(sellfishGUI)
        showCursor(false)
    end
end

-- Commands
addCommandHandler("fishnew", startFishing)
addCommandHandler("stopfishing", endFishing)
addEventHandler("onClientChangeChar", root, endFishing)
addEventHandler("onClientRender", root, renderFishingMinigame)

addCommandHandler("debugfishing", function()
    showAllHotspots = not showAllHotspots
    outputChatBox("[FISHING] Hotspot debug mode is now " .. (showAllHotspots and "#00FF00Enabled" or "#FF0000Disabled") .. ".", 255, 255, 255, true)
    updateHotspotVisibility()
end)
addEventHandler("onClientClick", root, npcRightClick)