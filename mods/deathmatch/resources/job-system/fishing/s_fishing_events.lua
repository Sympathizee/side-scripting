-- =======================================================
-- CONFIGURATION & TIMING
-- =======================================================

-- List of Available Events
local fishingEvents = {
    "Exotic Swarm",
    "Deep Sea Debris"
}

-- Timing Configuration
local BLOCK_DURATION_HOURS = 3      -- Groups of hours used for scheduling (e.g., 0-3, 3-6)
local EVENT_DURATION_HOURS = 1      -- How long an event lasts
local EVENT_DURATION_MS = EVENT_DURATION_HOURS * 60 * 60 * 1000

-- Runtime State (Event Tracking)
local currentFishingEvent = nil     -- Name of the active event
local activeEventTimer = nil        -- Timer for current event duration
local nextEventTimer = nil          -- Timer until next scheduled event
local checkTimer = nil              -- Recurring 60s block check timer
local currentBlockStartHour = -1    -- Tracks the last processed block
local eventScheduledForCurrentBlock = false -- Ensures only one event per block

-- =======================================================
-- HELPER FUNCTIONS
-- =======================================================

local function broadcastToFishers(message)
    for _, p in ipairs(getElementsByType("player")) do
        -- Notify all players with a Fishing License (item 154)
        if exports.global:hasItem(p, 154) then
            outputChatBox("[FISHING] #FFFFFF" .. message, p, 255, 194, 14, true)
        end
    end
end

-- Function to stop the active event
function stopFishingEvent()
    if currentFishingEvent then
        outputDebugString("[FISHING EVENTS] Event ended automatically: " .. tostring(currentFishingEvent))
        currentFishingEvent = nil
        g_FishingEventActive = false
        if setActiveEventHotspot then setActiveEventHotspot(nil) end
        if exportSyncHotspots then exportSyncHotspots() end
    end
end

-- Function to get the current fishing event
function getCurrentFishingEvent()
    return currentFishingEvent
end

-- Function to trigger the actual event
function triggerFishingEvent()
    if #fishingEvents == 0 then
        outputDebugString("[FISHING EVENTS] No fishing events defined yet.")
        return
    end

    -- Select a random event
    local randomIndex = math.random(1, #fishingEvents)
    currentFishingEvent = fishingEvents[randomIndex]
    g_FishingEventActive = true
    
    -- Pick a random region and a specific hotspot within it
    local regions = {}
    for id, spot in pairs(fishHotspots or {}) do
        if spot.is_event then
            if not regions[spot.region] then regions[spot.region] = {} end
            table.insert(regions[spot.region], id)
        end
    end
    
    local regionList = {}
    for regionName, _ in pairs(regions) do
        table.insert(regionList, regionName)
    end
    
    if #regionList > 0 then
        local randomRegion = regionList[math.random(1, #regionList)]
        local spotIds = regions[randomRegion]
        local selectedSpotID = spotIds[math.random(1, #spotIds)]
        
        if setActiveEventHotspot then
            setActiveEventHotspot(selectedSpotID)
        end
        
        -- Sync hotspots to clients
        if exportSyncHotspots then exportSyncHotspots() end
        
        -- Immersive Announcement
        local regionNameDisplay = randomRegion:gsub("_", " ")
        local immersiveMsg = ""
        if currentFishingEvent == "Exotic Swarm" then
            immersiveMsg = "Perhatian! Sekawanan #00FFFF Exotic Fish #FFFFFF telah terlihat! Siapkan alat pancing kalian!"
        elseif currentFishingEvent == "Deep Sea Debris" then
            immersiveMsg = "Perhatian! #00FFFF Deep Sea Debris #FFFFFF sedang bermunculan! Waktunya mencari barang-barang berharga!"
        else
            immersiveMsg = "Perhatian! #00FFFF " .. tostring(currentFishingEvent) .. " #FFFFFFtelah dimulai!"
        end
        immersiveMsg = immersiveMsg .. " Marker telah ditambahkan di peta anda!"
        broadcastToFishers(immersiveMsg)
    else
        outputDebugString("[FISHING EVENTS] No event hotspots found in DB. Event started without a location marker.")
        if exportSyncHotspots then exportSyncHotspots() end
    end
    
    outputDebugString("[FISHING EVENTS] Event started: " .. tostring(currentFishingEvent))
    
    -- Set a timer to end the event after 1 hour
    if isTimer(activeEventTimer) then killTimer(activeEventTimer) end
    activeEventTimer = setTimer(stopFishingEvent, EVENT_DURATION_MS, 1)
end

-- Core logic to check time and schedule events
function checkAndScheduleEvent()
    local time = getRealTime()
    local currentHour = time.hour
    
    -- Calculate the start hour of the current 3-hour block
    -- Blocks run: 0-2 (0-3), 3-5 (3-6), 6-8 (6-9), 9-11 (9-12), 12-14 (12-15), 15-17 (15-18), 18-20 (18-21), 21-23 (21-24)
    local blockStartHour = math.floor(currentHour / BLOCK_DURATION_HOURS) * BLOCK_DURATION_HOURS
    
    -- If we've entered a new block, reset the flag and ensure any active event is ended
    if blockStartHour ~= currentBlockStartHour then
        currentBlockStartHour = blockStartHour
        eventScheduledForCurrentBlock = false
        stopFishingEvent() -- Make sure any running event from the past block is ended
    end
    
    -- If we haven't scheduled an event for this block yet, do it now
    if not eventScheduledForCurrentBlock then
        -- We want the event to run for 1 hour.
        -- Therefore, it can start anytime from the beginning of the block up to (BLOCK_DURATION_HOURS - 1) hours into the block.
        -- i.e., in a 6-9 block, it can start between 6:00 and 8:00 (so it ends by 9:00).
        
        -- Get current timestamp and block boundary timestamps
        local nowTimestamp = time.timestamp
        -- Convert current time to seconds since start of day
        local secondsSinceMidnight = (time.hour * 3600) + (time.minute * 60) + time.second
        
        local blockStartSeconds = blockStartHour * 3600
        -- Latest possible start time is 2 hours into the 3 hour block
        local latestStartSeconds = (blockStartHour + (BLOCK_DURATION_HOURS - 1)) * 3600
        
        -- If we are already past the latest possible start time for this block,
        -- we should NOT start the event
        if secondsSinceMidnight >= latestStartSeconds then
            outputDebugString(string.format("[FISHING EVENTS] Script started >= 2 hours into block %02d:00-%02d:00. No event will run for this block.", blockStartHour, blockStartHour + BLOCK_DURATION_HOURS))
            eventScheduledForCurrentBlock = true -- Mark as scheduled so we don't keep checking
            return
        else
            -- We can pick a random start time between max(now, blockStart) and latestStart
            local earliestStart = math.max(secondsSinceMidnight, blockStartSeconds) + 10 -- Add a small buffer of 10s
            
            -- Ensure latest start is strictly > earliest start for math.random
            if latestStartSeconds <= earliestStart then
                startSeconds = earliestStart
            else
                startSeconds = math.random(earliestStart, latestStartSeconds)
            end
        end
        
        -- Calculate how many milliseconds from now to start the event
        local msUntilStart = (startSeconds - secondsSinceMidnight) * 1000
        
        if isTimer(nextEventTimer) then killTimer(nextEventTimer) end
        
        if msUntilStart <= 0 then
            -- Fallback in case of weird timing issues
            triggerFishingEvent()
        else
            nextEventTimer = setTimer(triggerFishingEvent, msUntilStart, 1)
            outputDebugString(string.format("[FISHING EVENTS] Scheduled next event for block %02d:00-%02d:00 to start in %d minutes.", blockStartHour, blockStartHour + BLOCK_DURATION_HOURS, math.floor(msUntilStart / 60000)))
        end
        
        eventScheduledForCurrentBlock = true
    end
end

-- Initialize the system
addEventHandler("onResourceStart", resourceRoot, function()
    -- Check immediately on start
    checkAndScheduleEvent()
    
    -- Check every 60 seconds to see if we've entered a new block
    checkTimer = setTimer(checkAndScheduleEvent, 60000, 0)
    outputDebugString("[FISHING EVENTS] Event system initialized using 3-hour time blocks.")
end)

-- Debug Commands

addCommandHandler("triggerfishevent", function(thePlayer, command, eventName)
    if not exports.integration:isPlayerTrialAdmin(thePlayer) then return end
    
    -- Stop existing instances
    if isTimer(activeEventTimer) then killTimer(activeEventTimer) end
    if isTimer(nextEventTimer) then killTimer(nextEventTimer) end
    
    if eventName then
        local found = false
        for _, ev in ipairs(fishingEvents) do
            if ev == eventName then
                found = true
                break
            end
        end
        
        if found then
            currentFishingEvent = eventName
            g_FishingEventActive = true
            if exportSyncHotspots then exportSyncHotspots() end
            outputChatBox("Fishing event '" .. eventName .. "' has been manually triggered for 1 hour.", thePlayer, 0, 255, 0)
            outputDebugString("[FISHING EVENTS] Event manually triggered by " .. getPlayerName(thePlayer) .. ": " .. tostring(currentFishingEvent))
            activeEventTimer = setTimer(stopFishingEvent, EVENT_DURATION_MS, 1)
        else
            outputChatBox("Event not found. Available events: " .. table.concat(fishingEvents, ", "), thePlayer, 255, 0, 0)
        end
    else
        triggerFishingEvent()
        outputChatBox("A random fishing event has been manually triggered for 1 hour.", thePlayer, 0, 255, 0)
    end
end)

addCommandHandler("stopfishevent", function(thePlayer, command)
    if not exports.integration:isPlayerTrialAdmin(thePlayer) then return end
    
    if currentFishingEvent then
        outputChatBox("Fishing event '" .. currentFishingEvent .. "' has been stopped.", thePlayer, 0, 255, 0)
        outputDebugString("[FISHING EVENTS] Event manually stopped by " .. getPlayerName(thePlayer) .. ": " .. tostring(currentFishingEvent))
        currentFishingEvent = nil
        g_FishingEventActive = false
        if exportSyncHotspots then exportSyncHotspots() end
        if isTimer(activeEventTimer) then killTimer(activeEventTimer) end
    else
        outputChatBox("There is currently no active fishing event.", thePlayer, 255, 0, 0)
    end
end)

addCommandHandler("fisheventstatus", function(thePlayer, command)
    if not exports.integration:isPlayerTrialAdmin(thePlayer) then return end
    
    local time = getRealTime()
    local blockStartHour = math.floor(time.hour / BLOCK_DURATION_HOURS) * BLOCK_DURATION_HOURS
    outputChatBox(string.format("Current Time Block: %02d:00 - %02d:00", blockStartHour, blockStartHour + BLOCK_DURATION_HOURS), thePlayer, 255, 255, 255)
    
    if currentFishingEvent then
        local timeLeftStr = "Unknown"
        if isTimer(activeEventTimer) then
            local timeLeftMs = getTimerDetails(activeEventTimer)
            timeLeftStr = math.floor(timeLeftMs / 60000) .. " minutes"
        end
        outputChatBox("Active Event: " .. currentFishingEvent .. " (Ends in " .. timeLeftStr .. ")", thePlayer, 0, 255, 0)
    else
        outputChatBox("Active Event: None", thePlayer, 255, 255, 0)
        
        if eventScheduledForCurrentBlock and isTimer(nextEventTimer) then
            local timeLeftMs = getTimerDetails(nextEventTimer)
            local minutesLeft = math.floor(timeLeftMs / 60000)
            outputChatBox("A random event is scheduled to start in " .. minutesLeft .. " minutes.", thePlayer, 0, 255, 0)
        elseif eventScheduledForCurrentBlock then
            outputChatBox("The event for the current block has already finished.", thePlayer, 255, 150, 0)
        else
            outputChatBox("No event is scheduled. This might be an error.", thePlayer, 255, 0, 0)
        end
    end
end)
