-- ========================================================
-- NPC-system
-- s_npc_manager.lua
-- Reusable server-side NPC spawning and lifecycle manager.
--
-- API:
--   spawnNPC(id, config)         -> bool   (create/refresh a managed NPC)
--   despawnNPC(id)               -> bool   (destroy a managed NPC)
--   forceNPCState(id, state)     -> void   (true=spawn, false=despawn, nil=back to schedule)
--   getNPCEntity(id)             -> ped|nil
--   updateNPCSchedule(id, cfg)   -> void   (update schedule config and re-evaluate)
--
-- config table fields:
--   x, y, z           (number)   World position
--   rot               (number)   Heading rotation
--   skin              (number)   Ped model ID
--   name              (string)   Display name (set as element data "name")
--   dimension         (number)   Default 0
--   interior          (number)   Default 0
--   useSchedule       (bool)     Enable time-based spawning
--   startHour         (number)
--   startMinute       (number)
--   endHour           (number)
--   endMinute         (number)
-- ========================================================

local managedNPCs = {}
-- Structure: managedNPCs[id] = {
--   config = {...},
--   entity = ped | nil,
--   forceState = true | false | nil,
-- }

-- --------------------------------------------------------
-- Internal Helpers
-- --------------------------------------------------------

local function isScheduleActive(cfg)
    if not cfg.useSchedule then return true end

    local h, m = getTime()
    local nowMinutes  = h * 60 + m
    local startM = (cfg.startHour or 0) * 60 + (cfg.startMinute or 0)
    local endM   = (cfg.endHour   or 0) * 60 + (cfg.endMinute   or 0)

    if startM < endM then
        return nowMinutes >= startM and nowMinutes < endM
    else
        -- Range crosses midnight (e.g. 22:00 -> 06:00)
        return nowMinutes >= startM or nowMinutes < endM
    end
end

local function createPedFromConfig(cfg)
    if not cfg.x or not cfg.y or not cfg.z then
        outputDebugString("[NPC-MODULE] spawnNPC failed: missing x/y/z in config", 1)
        return nil
    end

    if cfg.x == 0 and cfg.y == 0 then
        outputDebugString("[NPC-MODULE] Warning: NPC position is 0,0 – skipping spawn", 2)
        return nil
    end

    local ped = createPed(cfg.skin or 0, cfg.x, cfg.y, cfg.z, cfg.rot or 0)
    if not isElement(ped) then
        outputDebugString("[NPC-MODULE] Failed to createPed!", 1)
        return nil
    end

    setElementDimension(ped, cfg.dimension or 0)
    setElementInterior(ped,  cfg.interior  or 0)
    setElementFrozen(ped, true)
    setElementData(ped, "name", cfg.name or "NPC")
    setElementData(ped, "npc-module:managed", true)
    setElementData(ped, "npc-module:id", cfg._id or "unknown")

    -- Block all damage
    addEventHandler("onElementDamage", ped, function() cancelEvent() end)

    outputDebugString("[NPC-MODULE] Spawned NPC '" .. (cfg.name or "?") .. "' at " .. cfg.x .. ", " .. cfg.y .. ", " .. cfg.z)
    return ped
end

local function evaluateNPC(id)
    local entry = managedNPCs[id]
    if not entry then return end

    local cfg = entry.config
    local shouldBeActive

    if entry.forceState ~= nil then
        shouldBeActive = entry.forceState
    else
        shouldBeActive = isScheduleActive(cfg)
    end

    if not shouldBeActive then
        -- Despawn if currently alive
        if isElement(entry.entity) then
            destroyElement(entry.entity)
            entry.entity = nil
            outputDebugString("[NPC-MODULE] NPC '" .. id .. "' despawned (schedule/force).")
        end
        return
    end

    -- Should be active
    if isElement(entry.entity) then
        -- Check if config changed (position or skin)
        local ex, ey, ez = getElementPosition(entry.entity)
        local dist = getDistanceBetweenPoints3D(ex, ey, ez, cfg.x, cfg.y, cfg.z)
        local skinMatch = getElementModel(entry.entity) == (cfg.skin or 0)

        if dist < 0.1 and skinMatch then
            return -- No change needed
        else
            -- Config changed – recreate
            destroyElement(entry.entity)
            entry.entity = nil
        end
    end

    -- Spawn fresh
    cfg._id = id
    entry.entity = createPedFromConfig(cfg)
end

-- Shared 60s timer to re-evaluate all managed NPCs
local function tickAllNPCs()
    for id, _ in pairs(managedNPCs) do
        evaluateNPC(id)
    end
end

setTimer(tickAllNPCs, 60000, 0)

-- --------------------------------------------------------
-- Public API
-- --------------------------------------------------------

--- Registers and spawns (or refreshes) a managed NPC.
--- @param id       string  Unique identifier for this NPC
--- @param config   table   NPC configuration (see header)
--- @return boolean         true if registered successfully
function spawnNPC(id, config)
    if type(id) ~= "string" or type(config) ~= "table" then
        outputDebugString("[NPC-MODULE] spawnNPC: invalid arguments (id must be string, config must be table)", 1)
        return false
    end

    -- If already exists, despawn old entity first
    if managedNPCs[id] and isElement(managedNPCs[id].entity) then
        destroyElement(managedNPCs[id].entity)
    end

    managedNPCs[id] = {
        config     = config,
        entity     = nil,
        forceState = nil,
    }

    evaluateNPC(id)
    return true
end

--- Destroys and unregisters a managed NPC.
--- @param id string
--- @return boolean
function despawnNPC(id)
    local entry = managedNPCs[id]
    if not entry then return false end

    if isElement(entry.entity) then
        destroyElement(entry.entity)
    end
    managedNPCs[id] = nil
    outputDebugString("[NPC-MODULE] NPC '" .. id .. "' unregistered.")
    return true
end

--- Force or release the spawn state of a managed NPC.
--- @param id    string
--- @param state boolean|nil  true=force spawn, false=force despawn, nil=back to schedule
function forceNPCState(id, state)
    local entry = managedNPCs[id]
    if not entry then
        outputDebugString("[NPC-MODULE] forceNPCState: Unknown NPC id '" .. tostring(id) .. "'", 2)
        return
    end
    entry.forceState = state
    evaluateNPC(id)
end

--- Returns the ped element for a managed NPC, or nil if not spawned.
--- @param id string
--- @return ped|nil
function getNPCEntity(id)
    local entry = managedNPCs[id]
    if not entry then return nil end
    return isElement(entry.entity) and entry.entity or nil
end

--- Update the schedule/position config and immediately re-evaluate.
--- Only updates fields present in the `newConfig` table (partial update).
--- @param id        string
--- @param newConfig table
function updateNPCSchedule(id, newConfig)
    local entry = managedNPCs[id]
    if not entry then return end

    for k, v in pairs(newConfig) do
        entry.config[k] = v
    end
    evaluateNPC(id)
end
