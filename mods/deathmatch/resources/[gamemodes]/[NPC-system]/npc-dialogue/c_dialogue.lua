-- ========================================================
-- feat/npc-dialogue
-- c_dialogue.lua
-- Reusable client-side cinematic NPC dialogue engine.
--
-- EXPORTED API:
--   startCinematicDialogue(npcElement, dialogueData, onSuccessEvent, onFailEvent)
--   stopCinematicDialogue(success)
--   isDialogueActive() -> bool
--
-- dialogueData format:
--   [stageIndex] = {
--     question  = "string",          -- NPC's question/statement
--     options   = { "A. ...", ... }, -- Exactly 4 choices
--     correct   = 1,                 -- 1-based index of the correct answer
--     rejections = {                 -- Optional per-wrong-answer NPC rejection text
--       [wrongIndex] = "string"
--     }
--   }
--
-- Events fired back on localPlayer:
--   onSuccessEvent(npcElement)        -- when all stages completed correctly
--   onFailEvent(npcElement, reason)   -- when wrong answer given, reason = rejection text
-- ========================================================

local screenW, screenH = guiGetScreenSize()

-- --------------------------------------------------------
-- Internal State
-- --------------------------------------------------------
local active = false
local npcEl  = nil
local data   = nil
local successEvent = nil
local failEvent    = nil

local currentStage   = 1
local selectedOption = 1
local fadeAlpha      = 0
local textIndex      = 0
local lastTick       = 0
local isClosing      = false

local currentText    = ""
local currentChoices = {}

local currentNPCAnim    = ""
local currentPlayerAnim = ""

-- --------------------------------------------------------
-- Animation Helpers
-- --------------------------------------------------------
local function setNPCAnim(lib, name)
    if not isElement(npcEl) then return end
    local key = (lib or "") .. ":" .. (name or "")
    if currentNPCAnim == key then return end
    currentNPCAnim = key
    if lib then
        setPedAnimation(npcEl, lib, name, -1, true, false, true, false)
    else
        setPedAnimation(npcEl, false)
    end
end

local function setPlayerAnim(lib, name)
    local key = (lib or "") .. ":" .. (name or "")
    if currentPlayerAnim == key then return end
    currentPlayerAnim = key
    if lib then
        setPedAnimation(localPlayer, lib, name, -1, true, false, true, false)
    else
        setPedAnimation(localPlayer, false)
    end
end

-- --------------------------------------------------------
-- Stage Management
-- --------------------------------------------------------
local function updateStage()
    local stageData = data[currentStage]
    if not stageData then return end

    currentText    = stageData.question
    currentChoices = stageData.options
    textIndex      = 0
    lastTick       = getTickCount()
    selectedOption = 1

    setNPCAnim("GANGS", "prtial_gngtlkA")
    setPlayerAnim(nil)
end

-- --------------------------------------------------------
-- Core Stop
-- --------------------------------------------------------
local function doStop(success)
    if not active then return end
    isClosing = true

    showCursor(false)
    guiSetInputMode("allow_binds")
    setCameraTarget(localPlayer)
    setElementFrozen(localPlayer, false)
    setPlayerAnim(nil)
    setNPCAnim(nil)

    local capturedNPC = npcEl

    setTimer(function()
        active = false
        isClosing = false
        removeEventHandler("onClientRender", root, renderDialogueUI)

        if success then
            if successEvent then
                triggerEvent(successEvent, localPlayer, capturedNPC)
            end
        else
            -- failEvent is fired immediately before this timer in handleAnswer
        end
    end, 500, 1)
end

-- --------------------------------------------------------
-- Answer Logic
-- --------------------------------------------------------
local function handleAnswer()
    if not active or isClosing then return end

    local stageData = data[currentStage]
    if not stageData then return end

    setPlayerAnim("GANGS", "prtial_gngtlkB")
    setNPCAnim("ped", "idle_chat")

    if selectedOption == stageData.correct then
        setTimer(function()
            if not active or isClosing then return end

            if currentStage < #data then
                currentStage = currentStage + 1
                updateStage()
                playSoundFrontEnd(13)
            else
                -- All stages complete!
                doStop(true)
            end
        end, 1500, 1)
    else
        local rejection = (stageData.rejections and stageData.rejections[selectedOption])
            or "Gue gak ada waktu buat orang kayak lu. Pergi!"

        setTimer(function()
            if not active or isClosing then return end
            if failEvent then
                triggerEvent(failEvent, localPlayer, npcEl, rejection)
            end
            doStop(false)
            playSoundFrontEnd(5)
        end, 1000, 1)
    end
end

-- --------------------------------------------------------
-- Renderer
-- --------------------------------------------------------
function renderDialogueUI()
    if not active then return end

    -- Fade
    if isClosing then
        fadeAlpha = math.max(0, fadeAlpha - 10)
    else
        fadeAlpha = math.min(255, fadeAlpha + 10)
        if not isClosing then
            setElementFrozen(localPlayer, true)
        end
    end

    local boxW = 850
    local boxH = 240
    local x    = (screenW - boxW) / 2
    local y    = screenH - boxH - 50

    -- Background
    dxDrawRectangle(x, y,     boxW, boxH, tocolor(10, 10, 10, fadeAlpha * 0.95))
    dxDrawRectangle(x, y,     boxW, 2,    tocolor(204, 153, 0, fadeAlpha))

    -- NPC Name
    local npcName = (isElement(npcEl) and getElementData(npcEl, "name")) or "NPC"
    dxDrawText(npcName .. ":", x + 30, y + 20, x + boxW - 30, y + 45,
        tocolor(204, 153, 0, fadeAlpha), 1.3, "default-bold", "left", "top")

    -- Typewriter
    local isTyping = textIndex < #currentText
    if isTyping then
        if getTickCount() - lastTick > 25 then
            textIndex = textIndex + 1
            lastTick  = getTickCount()
            playSoundFrontEnd(41)
        end
    else
        if not isClosing and currentPlayerAnim == ":" then
            setNPCAnim("ped", "idle_chat")
        end
    end

    local displayText = string.sub(currentText, 1, textIndex)
    if isTyping then displayText = displayText .. "..." end
    dxDrawText(displayText, x + 30, y + 50, x + boxW - 30, y + 120,
        tocolor(255, 255, 255, fadeAlpha), 1.2, "default-bold", "left", "top", true, true)

    -- Choices
    if not isTyping then
        local cursorX, cursorY = getCursorPosition()
        if cursorX then
            cursorX = cursorX * screenW
            cursorY = cursorY * screenH
        end

        for i = 1, math.min(4, #currentChoices) do
            local choiceY  = y + 115 + (i - 1) * 28
            local isHov    = false

            if cursorX and cursorX >= x + 25 and cursorX <= x + boxW - 25
                and cursorY >= choiceY and cursorY <= choiceY + 25 then
                isHov = true
                if selectedOption ~= i then
                    selectedOption = i
                    playSoundFrontEnd(1)
                end
            end

            local isSel   = (selectedOption == i)
            local color   = isSel and tocolor(204, 153, 0, fadeAlpha) or tocolor(180, 180, 180, fadeAlpha * 0.7)
            local prefix  = isSel and "> " or "  "

            if isSel then
                dxDrawRectangle(x + 25, choiceY, boxW - 50, 25, tocolor(255, 255, 255, fadeAlpha * 0.05))
            end
            dxDrawText(prefix .. currentChoices[i], x + 35, choiceY, x + boxW - 35, choiceY + 25,
                color, 1.1, isSel and "default-bold" or "default", "left", "center", true)
        end

        dxDrawText("Gunakan [W/S], [ARROW] atau [KLIK] untuk memilih",
            x, y + boxH + 10, x + boxW, 0,
            tocolor(150, 150, 150, fadeAlpha * 0.5), 1.0, "default", "center", "top")
    else
        dxDrawText("[ENTER / KLIK untuk Lewati Teks]",
            x, y + boxH - 30, x + boxW, 0,
            tocolor(100, 100, 100, fadeAlpha * 0.4), 0.9, "default", "center", "top")
    end
end

-- --------------------------------------------------------
-- Public API
-- --------------------------------------------------------

--- Start a cinematic dialogue.
--- @param npcElement    element  The ped to talk to
--- @param dialogueData  table    Staged dialogue table (see header)
--- @param onSuccess     string   Event name triggered on localPlayer on success
--- @param onFail        string   Event name triggered on localPlayer on failure
function startCinematicDialogue(npcElement, dialogueData, onSuccess, onFail)
    if active then return end
    if not isElement(npcElement) then
        outputDebugString("[NPC-DIALOGUE] startCinematicDialogue: invalid npcElement", 1)
        return
    end
    if type(dialogueData) ~= "table" or #dialogueData == 0 then
        outputDebugString("[NPC-DIALOGUE] startCinematicDialogue: dialogueData is empty or invalid", 1)
        return
    end

    active         = true
    npcEl          = npcElement
    data           = dialogueData
    successEvent   = onSuccess
    failEvent      = onFail
    currentStage   = 1
    selectedOption = 1
    fadeAlpha      = 0
    isClosing      = false
    currentNPCAnim    = ""
    currentPlayerAnim = ""

    showCursor(true)
    guiSetInputMode("no_binds")

    -- Cinematic camera between player and NPC
    local nx, ny, nz = getElementPosition(npcEl)
    local px, py, pz = getElementPosition(localPlayer)
    local camX = nx + (px - nx) * 0.5
    local camY = ny + (py - ny) * 0.5
    local camZ = nz + 1.2
    setCameraMatrix(camX + 1.5, camY + 1.5, camZ + 0.5, nx, ny, nz + 0.6)

    addEventHandler("onClientRender", root, renderDialogueUI)
    updateStage()
end

--- Forcefully stop the dialogue. success=false by default.
--- @param success bool
function stopCinematicDialogue(success)
    doStop(success == true)
end

--- @return boolean
function isDialogueActive()
    return active
end

-- --------------------------------------------------------
-- Input Events
-- --------------------------------------------------------
addEventHandler("onClientKey", root, function(button, press)
    if not active or isClosing or not press then return end

    if button == "arrow_up" or button == "w" then
        selectedOption = selectedOption - 1
        if selectedOption < 1 then selectedOption = math.min(4, #currentChoices) end
        playSoundFrontEnd(1)

    elseif button == "arrow_down" or button == "s" then
        selectedOption = selectedOption + 1
        if selectedOption > math.min(4, #currentChoices) then selectedOption = 1 end
        playSoundFrontEnd(1)

    elseif button == "enter" or button == "num_enter" then
        if textIndex < #currentText then
            textIndex = #currentText
        else
            handleAnswer()
        end

    elseif button == "backspace" or button == "escape" then
        cancelEvent()
        doStop(false)
        if failEvent then
            triggerEvent(failEvent, localPlayer, npcEl, "Dialog dibatalkan.")
        end
    end
end)

addEventHandler("onClientClick", root, function(button, state, absX, absY)
    if not active or isClosing then return end

    if button == "left" and state == "down" then
        -- Skip typewriter
        if textIndex < #currentText then
            textIndex = #currentText
            return
        end

        local boxW = 850
        local boxH = 240
        local x    = (screenW - boxW) / 2
        local y    = screenH - boxH - 50

        for i = 1, math.min(4, #currentChoices) do
            local choiceY = y + 115 + (i - 1) * 28
            if absX >= x + 25 and absX <= x + boxW - 25
                and absY >= choiceY and absY <= choiceY + 25 then
                selectedOption = i
                playSoundFrontEnd(1)
                handleAnswer()
                return
            end
        end
    end
end)

-- --------------------------------------------------------
-- Cleanup on resource events
-- --------------------------------------------------------
addEventHandler("onClientResourceStop", resourceRoot, function()
    if active then
        setCameraTarget(localPlayer)
        showCursor(false)
        guiSetInputMode("allow_binds")
        setElementFrozen(localPlayer, false)
        removeEventHandler("onClientRender", root, renderDialogueUI)
        active = false
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    setCameraTarget(localPlayer)
end)
