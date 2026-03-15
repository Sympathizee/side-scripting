--[[
    Stardew Valley Inspired Fishing Minigame
    Rendered via DX functions.
]]

-- ==========================================================
-- DIFFICULTY & TWEAKING VARIABLES
-- Change these values to make the minigame harder or easier.
-- ==========================================================

-- The speed at which the catch progress fills up. Higher = faster catch.
local PROGRESS_FILL_RATE = 0.0025

-- The speed at which the catch progress depletes. Higher = faster escape.
local PROGRESS_DEPLETE_RATE = 0.0035

-- The speed range the fish can move. Higher = more erratic fish.
local MIN_FISH_SPEED = 0.003
local MAX_FISH_SPEED = 0.010

-- Base size of the catch bar (0 to 1). 0.2 means 20% of the bar's height.
local BASE_BAR_HEIGHT = 0.3

-- How much extra bar height is added per rod level.
local BONUS_BAR_PER_LEVEL = 0.033

-- Gravity pulling the catch bar down. Higher = falls faster.
local BAR_GRAVITY = 0.001

-- The upward velocity applied to the catch bar when the key is held. Higher = rises faster.
local BAR_THRUST = 0.0015

-- How often the fish changes its target position (in milliseconds)
local FISH_CHANGE_INTERVAL = 800


-- ==========================================================
-- INTERNAL VARIABLES
-- ==========================================================
local isMinigameActive = false

local fishPos = 0.5
local fishTarget = 0.5
local fishVelocity = 0
local currentFishSpeed = 0.005

local barPos = 0.5
local barVelocity = 0
local currentBarHeight = BASE_BAR_HEIGHT

local catchProgress = 0.2 -- Start with 20% progress

local isHoldingKey = false
local lastFishChange = 0

local callerFile = nil -- Identifies if c_fishing or c_fishing_job started it
local currentRodLevelForMinigame = 1

-- Screensize for drawing
local sx, sy = guiGetScreenSize()

-- ==========================================================
-- CORE MINIGAME LOGIC
-- ==========================================================

local function renderFishingMinigame()
    if not isMinigameActive then return end

    local now = getTickCount()

    -- 1. Input Processing
    isHoldingKey = getKeyState("e")

    -- 2. Catch Bar Physics
    if isHoldingKey then
        barVelocity = barVelocity - BAR_THRUST
    else
        barVelocity = barVelocity + BAR_GRAVITY
    end

    -- Add some friction/damping to the bar
    barVelocity = barVelocity * 0.9

    -- Apply velocity to position
    barPos = barPos + barVelocity

    -- Constrain bar position (barPos is the top of the bar)
    if barPos < 0 then
        barPos = 0
        barVelocity = 0
    elseif barPos > (1 - currentBarHeight) then
        barPos = 1 - currentBarHeight
        barVelocity = 0
    end

    -- 3. Fish AI / Movement
    -- If time is up OR we are close to the target, pick a new target and new speed
    if (now - lastFishChange > FISH_CHANGE_INTERVAL) or (math.abs(fishPos - fishTarget) < 0.02) then
        fishTarget = math.random() -- New target position (0 to 1)
        currentFishSpeed = math.random() * (MAX_FISH_SPEED - MIN_FISH_SPEED) + MIN_FISH_SPEED
        lastFishChange = now
    end

    -- Move fish towards target
    if fishPos < fishTarget then
        fishPos = fishPos + math.min(currentFishSpeed, fishTarget - fishPos)
    elseif fishPos > fishTarget then
        fishPos = fishPos - math.min(currentFishSpeed, fishPos - fishTarget)
    end

    -- Constrain fish position
    fishPos = math.max(0, math.min(1, fishPos))

    -- 4. Catch Mechanics
    -- The fish is represented as a point (or small area). We'll treat fishPos as a point.
    local fishInsideBar = (fishPos >= barPos and fishPos <= barPos + currentBarHeight)

    if fishInsideBar then
        catchProgress = catchProgress + PROGRESS_FILL_RATE
    else
        catchProgress = catchProgress - PROGRESS_DEPLETE_RATE
    end

    -- Constrain progress
    catchProgress = math.max(0, math.min(1, catchProgress))

    -- 5. Drawing the UI
    local bgWidth = 40
    local bgHeight = 400
    local bgX = sx - bgWidth - 50
    local bgY = (sy - bgHeight) / 2

    -- Border outline (drawn slightly larger than background)
    local borderThick = 2
    dxDrawRectangle(bgX - borderThick, bgY - borderThick, bgWidth + (borderThick * 2), bgHeight + (borderThick * 2), tocolor(0, 0, 0, 255))
    
    -- Background (Deep blue/water color)
    dxDrawRectangle(bgX, bgY, bgWidth, bgHeight, tocolor(0, 50, 100, 200))

    -- Catch Bar (Green)
    local actualBarHeight = bgHeight * currentBarHeight
    local actualBarY = bgY + (barPos * bgHeight)
    
    -- If fish is inside, turn the bar a brighter green or yellow
    local barColor = fishInsideBar and tocolor(50, 255, 50, 200) or tocolor(0, 150, 0, 150)
    dxDrawRectangle(bgX + (bgWidth * 0.15), actualBarY, bgWidth * 0.7, actualBarHeight, barColor)

    -- Fish (Using image)
    local fishSize = 20 -- The image size
    local actualFishY = bgY + (fishPos * bgHeight) - (fishSize / 2)
    -- Constrain visually so it doesn't poke out
    actualFishY = math.max(bgY, math.min(bgY + bgHeight - fishSize, actualFishY))
    dxDrawRectangle(bgX + (bgWidth / 2) - (fishSize / 2), actualFishY, fishSize, fishSize)

    -- Progress Bar (Right side of the minigame box)
    local progWidth = 10
    local progX = bgX + bgWidth + 5
    
    -- Progress Bar Background
    dxDrawRectangle(progX, bgY, progWidth, bgHeight, tocolor(50, 50, 50, 200))
    
    -- Actual Progress Fill (Fills from bottom to top)
    local progFillHeight = bgHeight * catchProgress
    local progFillY = bgY + bgHeight - progFillHeight
    
    -- Color changes based on progress
    local progColor = tocolor(255 * (1 - catchProgress), 255 * catchProgress, 0, 255)
    dxDrawRectangle(progX, progFillY, progWidth, progFillHeight, progColor)

    -- Instructions
    dxDrawText("Hold E", bgX - 50, bgY + bgHeight + 10, bgX + bgWidth + 50, bgY + bgHeight + 30, tocolor(255, 255, 255, 255), 1, "default-bold", "center", "center")

    -- 6. Win / Loss Condition Check
    if catchProgress >= 1 then
        stopStardewFishingMinigame(true)
    elseif catchProgress <= 0 then
        stopStardewFishingMinigame(false)
    end
end

-- ==========================================================
-- EXPORTED / GLOBAL FUNCTIONS
-- ==========================================================

function startStardewFishingMinigame(rodLevel, scriptCaller)
    if isMinigameActive then return end

    -- Reset variables
    fishPos = 0.5
    fishTarget = 0.5
    fishVelocity = 0
    barPos = 0.5
    barVelocity = 0
    catchProgress = 0.4
    isHoldingKey = false
    lastFishChange = getTickCount()

    callerFile = scriptCaller
    currentRodLevelForMinigame = tonumber(rodLevel) or 1

    -- Calculate bar height based on rod level
    -- rodLevel of 1 gives BASE_BAR_HEIGHT (0.15)
    -- rodLevel 5 would give 0.15 + (5 * 0.02) = 0.25 (25% of the bar)
    currentBarHeight = BASE_BAR_HEIGHT + ((tonumber(rodLevel) or 1) * BONUS_BAR_PER_LEVEL)
    -- Cap maximum size
    currentBarHeight = math.min(0.5, currentBarHeight)

    isMinigameActive = true
    toggleAllControls(false, true, false) -- Disable GTA movement/action controls
    addEventHandler("onClientRender", root, renderFishingMinigame)
end

function stopStardewFishingMinigame(success)
    if not isMinigameActive then return end

    isMinigameActive = false
    removeEventHandler("onClientRender", root, renderFishingMinigame)
    toggleAllControls(true, true, false) -- Re-enable GTA controls
    triggerEvent("fishing:minigameResult", localPlayer, success, currentRodLevelForMinigame)
end
