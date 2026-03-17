-- ========================================================
-- c_crafting_ui.lua
-- Premium DX-based Crafting UI interaction hook.
-- ========================================================

local screenW, screenH = guiGetScreenSize()
local active = false
local recipes = {}
local selectedIdx = 1
local scrollOffset = 0
local fadeAlpha = 0
local isClosing = false
local cachedAvailability = {} -- [recipeIdx][ingIdx] = count
local activeNPC = nil

-- UI Dimensions
local panelW, panelH = 900, 600
local x, y = (screenW - panelW) / 2, (screenH - panelH) / 2
local leftPanelW = 300
local rightPanelW = panelW - leftPanelW

-- Colors
local colorBg = tocolor(15, 15, 15, 245)
local colorHeader = tocolor(204, 153, 0, 255)
local colorSelected = tocolor(204, 153, 0, 100)
local colorHover = tocolor(255, 255, 255, 10)
local colorText = tocolor(220, 220, 220, 255)
local colorTextDim = tocolor(150, 150, 150, 255)
local colorSuccess = tocolor(46, 204, 113, 255)
local colorFail = tocolor(231, 76, 60, 255)

local function drawText(text, tx, ty, tw, th, color, scale, font, alignX, alignY, clip, wordBreak)
    dxDrawText(text, tx, ty, tx+tw, ty+th, color, scale, font, alignX or "left", alignY or "top", clip, wordBreak)
end

function renderCraftingUI()
    if not active then return end

    -- Fade Animation
    if isClosing then
        fadeAlpha = math.max(0, fadeAlpha - 15)
        if fadeAlpha <= 0 then
            active = false
            removeEventHandler("onClientRender", root, renderCraftingUI)
            showCursor(false)
            guiSetInputMode("allow_binds")
            return
        end
    else
        fadeAlpha = math.min(255, fadeAlpha + 15)
    end

    local alphaMult = fadeAlpha / 255
    local currentBg = tocolor(15, 15, 15, 245 * alphaMult)
    local currentHeader = tocolor(204, 153, 0, 255 * alphaMult)
    local currentText = tocolor(220, 220, 220, 255 * alphaMult)

    -- Background Shadow
    dxDrawRectangle(x - 5, y - 5, panelW + 10, panelH + 10, tocolor(0, 0, 0, 100 * alphaMult))
    dxDrawRectangle(x, y, panelW, panelH, currentBg)
    
    -- Header
    dxDrawRectangle(x, y, panelW, 40, tocolor(10, 10, 10, 255 * alphaMult))
    dxDrawRectangle(x, y + 40, panelW, 2, currentHeader)
    drawText("CRAFTING", x + 20, y, panelW, 40, currentHeader, 1.5, "default-bold", "left", "center")

    -- Close Button
    local closeW, closeH = 30, 30
    local cx, cy = x + panelW - 35, y + 5
    local isCloseHover = false
    local curX, curY = getCursorPosition()
    if curX then
        curX, curY = curX * screenW, curY * screenH
        if curX >= cx and curX <= cx + closeW and curY >= cy and curY <= cy + closeH then
            isCloseHover = true
        end
    end
    drawText("X", cx, cy, closeW, closeH, isCloseHover and tocolor(255, 50, 50, 255 * alphaMult) or currentText, 1.5, "default-bold", "center", "center")

    -- Left Panel (Recipes List)
    dxDrawRectangle(x, y + 42, leftPanelW, panelH - 42, tocolor(20, 20, 20, 150 * alphaMult))
    local itemH = 60
    
    for i, recipe in ipairs(recipes) do
        local rx, ry = x, y + 42 + (i-1)*itemH - scrollOffset
        if ry >= y + 42 - itemH and ry <= y + panelH then
            local isSelected = (selectedIdx == i)
            local isHover = false
            
            local cx, cy = getCursorPosition()
            if cx then
                cx, cy = cx * screenW, cy * screenH
                if cx >= rx and cx <= rx + leftPanelW and cy >= ry and cy <= ry + itemH then
                    isHover = true
                end
            end

            -- Clipping for list items
            if ry >= y + 42 and ry + itemH <= y + panelH then
                if isSelected then
                    dxDrawRectangle(rx, ry, leftPanelW, itemH, tocolor(204, 153, 0, 40 * alphaMult))
                    dxDrawRectangle(rx, ry, 4, itemH, currentHeader)
                elseif isHover then
                    dxDrawRectangle(rx, ry, leftPanelW, itemH, tocolor(255, 255, 255, 10 * alphaMult))
                end

                -- Item Icon
                local iconSize = 40
                local icon = exports["item-system"]:getImage(recipe.image or recipe.resultID, recipe.resultValue or "")
                if icon then
                    dxDrawImage(rx + 10, ry + (itemH - iconSize)/2, iconSize, iconSize, icon, 0, 0, 0, tocolor(255, 255, 255, 255 * alphaMult))
                end

                drawText(recipe.name or "Unknown Item", rx + 60, ry, leftPanelW - 65, itemH, isSelected and currentHeader or currentText, 1.1, "default-bold", "left", "center", true)
            end
        end
    end

    -- Right Panel (Details)
    local selected = recipes[selectedIdx]
    if selected then
        local dx, dy = x + leftPanelW, y + 42
        
        -- Large Image Preview
        local previewSize = 120
        local icon = exports["item-system"]:getImage(selected.image or selected.resultID, selected.resultValue or "")
        if icon then
            dxDrawImage(dx + (rightPanelW - previewSize)/2, dy + 20, previewSize, previewSize, icon, 0, 0, 0, tocolor(255, 255, 255, 255 * alphaMult))
        end
        
        drawText(selected.name or "Select an Item", dx, dy + 150, rightPanelW, 30, currentHeader, 1.4, "default-bold", "center", "top")
        
        -- Requirements Header
        dxDrawRectangle(dx + 50, dy + 190, rightPanelW - 100, 1, tocolor(255, 255, 255, 20 * alphaMult))
        drawText("REQUIREMENTS", dx + 50, dy + 200, 200, 20, tocolor(150, 150, 150, 255 * alphaMult), 1.0, "default-bold")
        
        -- Ingredients List
        local canCraft = true
        for i, ing in ipairs(selected.ingredients or {}) do
            local iy = dy + 230 + (i-1)*30
            
            -- Use cached server-side availability if present
            local hasAmount = 0
            if cachedAvailability[selectedIdx] and cachedAvailability[selectedIdx][i] then
                hasAmount = cachedAvailability[selectedIdx][i]
            else
                -- Fallback to client-side countItems (might not work for money)
                hasAmount = exports["item-system"]:countItems(localPlayer, ing.id) or 0
            end

            local isMet = (hasAmount >= ing.amount)
            if not isMet then canCraft = false end
            
            local statusColor = isMet and colorSuccess or colorFail
            statusColor = (statusColor - (statusColor % 16777216)) + (math.floor(255 * alphaMult))

            drawText("• " .. (ing.name or "Item #"..ing.id), dx + 60, iy, 400, 30, currentText, 1.1, "default")
            drawText(hasAmount .. " / " .. ing.amount, dx + 60, iy, rightPanelW - 120, 30, statusColor, 1.1, "default-bold", "right")
        end
        
        -- Craft Button
        local btnW, btnH = 200, 50
        local bx, by = dx + (rightPanelW - btnW)/2, y + panelH - 80
        local isBtnHover = false
        local cx, cy = getCursorPosition()
        if cx then
            cx, cy = cx * screenW, cy * screenH
            if cx >= bx and cx <= bx + btnW and cy >= by and cy <= by + btnH then
                isBtnHover = true
            end
        end

        local btnAlpha = (isBtnHover and 200 or 150) * alphaMult
        local btnColor = canCraft and tocolor(204, 153, 0, btnAlpha) or tocolor(50, 50, 50, 100 * alphaMult)
        dxDrawRectangle(bx, by, btnW, btnH, btnColor)
        drawText("CRAFT ITEM", bx, by, btnW, btnH, canCraft and tocolor(255, 255, 255, 255 * alphaMult) or tocolor(100, 100, 100, 255 * alphaMult), 1.2, "default-bold", "center", "center")
    end
end

function openCraftingUI(newRecipes, npc)
    if active then return end
    if not newRecipes or #newRecipes == 0 then return end
    
    recipes = newRecipes
    activeNPC = npc
    selectedIdx = 1
    scrollOffset = 0
    fadeAlpha = 0
    isClosing = false
    active = true
    cachedAvailability = {}
    
    showCursor(true)
    guiSetInputMode("no_binds")
    addEventHandler("onClientRender", root, renderCraftingUI)

    -- Request server-side ingredient check
    triggerServerEvent("crafting:getAvailability", localPlayer, recipes)
end

-- Input Handling
addEventHandler("onClientClick", root, function(button, state, absX, absY)
    if not active or isClosing or state ~= "down" then return end

    local dx, dy = x + leftPanelW, y + 42
    local btnW, btnH = 200, 50
    local bx, by = dx + (rightPanelW - btnW)/2, y + panelH - 80
    
    -- Close button check
    local cx, cy = x + panelW - 35, y + 5
    if absX >= cx and absX <= cx + 30 and absY >= cy and absY <= cy + 30 then
        isClosing = true
        playSoundFrontEnd(1)
        return
    end

    if absX >= bx and absX <= bx + btnW and absY >= by and absY <= by + btnH then
        local selected = recipes[selectedIdx]
        if selected then
            triggerServerEvent("crafting:tryCraft", localPlayer, selected, activeNPC)
        end
    end

    -- Selection in list
    if absX >= x and absX <= x + leftPanelW and absY >= y + 42 and absY <= y + panelH then
        local itemH = 60
        local clickedIdx = math.floor((absY - (y + 42) + scrollOffset) / itemH) + 1
        if recipes[clickedIdx] then
            selectedIdx = clickedIdx
            playSoundFrontEnd(1)
        end
    end
end)

addEventHandler("onClientKey", root, function(button, press)
    if not active or isClosing or not press then return end
    
    if button == "escape" or button == "backspace" then
        isClosing = true
        cancelEvent()
    elseif button == "mouse_wheel_up" then
        scrollOffset = math.max(0, scrollOffset - 30)
    elseif button == "mouse_wheel_down" then
        local maxScroll = math.max(0, (#recipes * 60) - (panelH - 42))
        scrollOffset = math.min(maxScroll, scrollOffset + 30)
    end
end)

-- Receive feedback from server
addEvent("crafting:feedback", true)
addEventHandler("crafting:feedback", localPlayer, function(success, message)
    if success then
        -- outputChatBox("[CRAFTING] " .. message, 46, 204, 113) -- Removed for RP dialogue
        playSoundFrontEnd(13)
        -- Refresh counts after success
        triggerServerEvent("crafting:getAvailability", localPlayer, recipes)
    else
        -- outputChatBox("[CRAFTING] " .. message, 231, 76, 60) -- Removed for RP dialogue
        playSoundFrontEnd(5)
    end
end)

addEvent("crafting:receiveAvailability", true)
addEventHandler("crafting:receiveAvailability", localPlayer, function(avail)
    cachedAvailability = avail
end)
