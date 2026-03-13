local count = 0
local state = 0
local mgTimer = nil
local escapeTimer = nil
local pFish = nil
local rodId = {285,286,287,288,289}
local items = exports['item-system']

-- Pancingan dibuat bisa patah supaya bisa beli terus juga
local snappedCaught = 0.08 -- 8% chance patah jika dapet ikan
local snappedEscaped = 0.16 -- 16% chance pancingan patah jika ikan lepas

-- Peds will be loaded from the server
local peds = {}

addEvent("fishing:receiveNPCLocations", true)
addEventHandler("fishing:receiveNPCLocations", resourceRoot, function(locations)
    for name, data in pairs(locations) do
        if peds[name] and isElement(peds[name]) then
            setElementPosition(peds[name], data.x, data.y, data.z)
            setElementRotation(peds[name], 0, 0, data.rot)
            setElementInterior(peds[name], data.int)
            setElementDimension(peds[name], data.dim)
        else
            peds[name] = createPed(data.skin or 209, data.x, data.y, data.z)
            setElementRotation(peds[name], 0, 0, data.rot)
            setElementInterior(peds[name], data.int)
            setElementDimension(peds[name], data.dim)
            setElementData(peds[name], "nametag", true)
            setElementData(peds[name], "name", name:gsub(" ", "_"))
            setElementFrozen(peds[name], true)
        end
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("fishing:requestNPCLocations", localPlayer)
end)

local hotspotBlips = {}
local activeHotspots = {}

addEvent("fishing:receiveHotspots", true)
addEventHandler("fishing:receiveHotspots", resourceRoot, function(hotspots)
    activeHotspots = hotspots
    for id, blip in pairs(hotspotBlips) do
        if isElement(blip) then destroyElement(blip) end
    end
    hotspotBlips = {}
    
    for id, spot in pairs(hotspots) do
        local r, g, b = 255, 255, 255
        if spot.state == "Good" then
            r, g, b = 0, 255, 0
        elseif spot.state == "Medium" then
            r, g, b = 255, 255, 0
        elseif spot.state == "Bad" then
            r, g, b = 255, 0, 0
        end
        hotspotBlips[id] = createBlip(spot.x, spot.y, spot.z, 0, 3, r, g, b, 255, 0, 99999)
    end
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
    local currentRod = nil
    -- get pancingan yang sekarang dipake, diambil pancingan yang terkecil levelnya
    for i, rod in ipairs(rodId) do
        local haveRod = items:hasItem(localPlayer, rod)
        if(haveRod)then
            currentRod = rod
            break
        end
    end

    -- Mulai memancing
    if currentRod then
        if getElementData(localPlayer, "isfishing") then
            outputChatBox("Kamu sedang memancing...", 255, 0, 0)
        else 
            if isPedInVehicle(localPlayer) then
                return outputChatBox("Tidak dapat memancing sambil berlayar.", 255, 0, 0) 
            end
            local hotspotState = getNearestHotspot()
            local fishingLevel = getElementData(localPlayer, "fishing_level") or 0

            if fishingLevel == 0 then
                return outputChatBox("Kamu butuh Fishing License untuk memancing! Temui License Issuer.", 255, 0, 0)
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
                if atSMB() or hotspotState or onBoat() then
                    allowed = true
                else
                    reason = "Level 2+ bisa memancing di SMB, Hotspot, atau di laut pinggir kapal."
                end
            end

            if allowed then
                triggerServerEvent("sendAmeClient", localPlayer, "melemparkan pancingnya ke laut.")
                triggerServerEvent("artifacts:add", localPlayer, localPlayer, "rod")
                setElementData(localPlayer, "isfishing", true)
                
                local minTime = 180000
                local maxTime = 600000
                if hotspotState == "Good" then
                    minTime, maxTime = 30000, 90000
                elseif hotspotState == "Medium" then
                    minTime, maxTime = 90000, 180000
                elseif hotspotState == "Bad" then
                    minTime, maxTime = 300000, 900000
                end
                
                mgTimer = setTimer(
                    function()
                        local stillAllowed = false
                        if fishingLevel == 1 then
                            if atSMB() then stillAllowed = true end
                        elseif fishingLevel >= 2 then
                            if atSMB() or getNearestHotspot() or onBoat() then stillAllowed = true end
                        end
                        
                        if not stillAllowed then
                            endFishing()
                            return outputChatBox("Anda tidak bisa memancing disini.", 255, 0, 0)
                        end
                        pFish = guiCreateProgressBar(0.425, 0.75, 0.2, 0.035, true)
                        exports.hud:sendBottomNotification(localPlayer, "Fishing", "Pancingan anda digigt! Gunakan [ and ] untuk menarik ikan.")
                        bindKey("[", "down", beginFishingGame)
                        -- Start the timer which determins if the fish would get away.
                        escapeTimer = setTimer(
                            function() 
                                endFishing()
                                local snap = math.random()
                                if(snap < snappedEscaped)then
                                    outputChatBox("Saat menarik ikan, pancinganmu patah dan ikan terlepas.", 255, 0, 0)
                                    triggerServerEvent("fishing:takeRod", localPlayer, localPlayer, currentRod)
                                else
                                    outputChatBox("Ikan melepaskan gigitannya, kamu tidak mendapatkan apa-apa.", 255, 0, 0)
                                end
                            end, 
                        math.random(10000, 15000), 1)
                    end
                , math.random(minTime, maxTime), 1)
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
        local dist = getDistanceBetweenPoints3D(x, y, z, spot.x, spot.y, spot.z)
        if dist < nearestDist then
            nearestDist = dist
            state = spot.state
        end
    end
    return state
end

-- ============== Modul Dialog Ped ==============

function endFishing()
    if (getElementData(localPlayer, "isfishing")) then

        if isTimer(mgTimer) then
            killTimer(mgTimer)
        end

        if isTimer(escapeTimer) then
            killTimer(escapeTimer)
        end

        if isElement(pFish) then
            destroyElement(pFish)
            pFish = nil
            count = 0
            unbindKey("[", "down", reelItIn)
            unbindKey("]", "down", reelItIn)
        end

        triggerServerEvent("artifacts:remove", localPlayer, localPlayer, "rod")
        triggerServerEvent("sendAmeClient", localPlayer, "reels in his line.")
        setElementData(localPlayer, "isfishing", false)
    end
end

-- Minigame yang lama tapi saya tambahin chance pancingan rusak sama ada yang saya benerin
function beginFishingGame()
    if (state==0) then
		bindKey("]", "down", beginFishingGame)
		unbindKey("[", "down", beginFishingGame)
		state = 1
	elseif (state==1) then
		bindKey("[", "down", beginFishingGame)
		unbindKey("]", "down", beginFishingGame)
		state = 0
	end
	
    count = count + 1
    guiProgressBarSetProgress(pFish, count)
	
    if (count>=100) then
        local currentRod = nil;

        for i, rod in ipairs(rodId) do
            local haveRod = items:hasItem(localPlayer, rod)
            if(haveRod)then
                currentRod = rod
                break
            end
        end

        killTimer(escapeTimer)
		destroyElement(pFish)
        pFish = nil
        count = 0
		unbindKey("[", "down", reelItIn)
        unbindKey("]", "down", reelItIn)
        local snap = math.random()
        if(snap < snappedCaught)then
            triggerServerEvent("fishing:takeRod", localPlayer, localPlayer, currentRod)
        end
        endFishing()
        local hotspotState = getNearestHotspot()
        local inHotspot = hotspotState ~= nil
        triggerServerEvent("fishing:giveCatch", localPlayer, localPlayer, inHotspot)
    end
end

function npcRightClick(button, state, absX, absY, wx, wy, wz, element)
    if (element) and (getElementType(element)=="ped") and (button=="right") and (state=="down") then
		local pedName = getElementData(element, "name") or "The Storekeeper"
		pedName = tostring(pedName):gsub("_", " ")

        local rcMenu
        if(pedName == "Fisherman Herb") then 
            rcMenu = exports.rightclick:create(pedName)
            local sell = exports.rightclick:addRow("Sell Fish")
            local upgradeRod = exports.rightclick:addRow("Upgrade Fishing Rod")
            addEventHandler("onClientGUIClick", sell,  function (button, state)
                triggerServerEvent("fishing:sellFish", localPlayer, localPlayer)
            end, false)
            addEventHandler("onClientGUIClick", upgradeRod,  function (button, state)
                triggerServerEvent("fishing:upgradeRod", localPlayer, localPlayer)
            end, false)
            local close = exports.rightclick:addRow("Close")
            addEventHandler("onClientGUIClick", close,  function (button, state)
                exports.rightclick:destroy(rcMenu)
            end, false)
        elseif(pedName == "License Issuer") then
            rcMenu = exports.rightclick:create(pedName)
            local apply = exports.rightclick:addRow("Apply For/Renew License")
            local close = exports.rightclick:addRow("Close")
            
            addEventHandler("onClientGUIClick", apply,  function (button, state)
                triggerServerEvent("fishing:applyLicense", localPlayer, localPlayer)
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
addCommandHandler("anjing", anjing)
addCommandHandler("fishnew", startFishing)
addCommandHandler("stopfishing", endFishing)
addEventHandler("onClientChangeChar", root, endFishing)
addEventHandler("onClientClick", root, npcRightClick)