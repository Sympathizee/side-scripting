-- Get db connection
local db = exports.mysql:getConn('mta')
-- Get item system
local items = exports['item-system']

-- Initialize Tables
dbExec(db, "CREATE TABLE IF NOT EXISTS `fish_level` (`name` VARCHAR(50) PRIMARY KEY, `level` INT, `amount` INT)")
dbExec(db, "CREATE TABLE IF NOT EXISTS `fish_settings` (`name` VARCHAR(50) PRIMARY KEY, `x` FLOAT, `y` FLOAT, `z` FLOAT, `rot` FLOAT, `int` INT, `dim` INT, `skin` INT)")
dbExec(db, "CREATE TABLE IF NOT EXISTS `fish_hotspots` (`id` INT AUTO_INCREMENT PRIMARY KEY, `region` VARCHAR(50), `x` FLOAT, `y` FLOAT, `z` FLOAT)")
dbExec(db, "INSERT IGNORE INTO `fish_settings` (`name`, `x`, `y`, `z`, `rot`, `int`, `dim`, `skin`) VALUES ('Fisherman Herb', 361.2109, -2032.7460, 7.8359, 328, 0, 0, 209)")
dbExec(db, "INSERT IGNORE INTO `fish_settings` (`name`, `x`, `y`, `z`, `rot`, `int`, `dim`, `skin`) VALUES ('License Issuer', 360.0, -2032.0, 7.8359, 328, 0, 0, 147)")

local npcLocations = {}
local fishHotspots = {} -- To store all hotspots and their current states

-- Helper to randomly shuffle a table
local function shuffleTable(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

-- Hotspot Rotation Logic
function rotateHotspots()
    local regions = {}
    -- Group hotspots by region
    for id, spot in pairs(fishHotspots) do
        if not regions[spot.region] then regions[spot.region] = {} end
        table.insert(regions[spot.region], id)
    end
    
    -- Assign states per region
    for region, spotIds in pairs(regions) do
        shuffleTable(spotIds)
        
        for index, id in ipairs(spotIds) do
            local state = "Random"
            if index == 1 then
                state = "Good"
            elseif index == 2 or index == 3 then
                state = "Medium"
            elseif index == 4 then
                state = "Bad"
            else
                local rand = math.random(1, 3)
                if rand == 1 then state = "Good"
                elseif rand == 2 then state = "Medium"
                else state = "Bad" end
            end
            fishHotspots[id].state = state
        end
    end
    
    -- Sync with all clients
    triggerClientEvent(root, "fishing:receiveHotspots", resourceRoot, fishHotspots)
    outputDebugString("[FISHING] Hotspots rotated successfully.")
end

addEventHandler("onResourceStart", resourceRoot, function()
    -- Load NPCs
    dbQuery(function(qh)
        local res = dbPoll(qh, 0)
        if res then
            for _, row in ipairs(res) do
                npcLocations[row.name] = row
            end
        end
    end, db, "SELECT * FROM `fish_settings`")
    
    -- Load Hotspots
    dbQuery(function(qh)
        local res = dbPoll(qh, 0)
        if res then
            for _, row in ipairs(res) do
                fishHotspots[row.id] = {id = row.id, region = row.region, x = row.x, y = row.y, z = row.z, state = "Random"}
            end
            -- Perform initial rotation
            rotateHotspots()
        end
    end, db, "SELECT * FROM `fish_hotspots`")
    
    -- Set 1-hour rotation timer
    setTimer(rotateHotspots, 3600000, 0)
end)

addEvent("fishing:requestInitialData", true)
addEventHandler("fishing:requestInitialData", root, function()
    triggerClientEvent(client, "fishing:receiveNPCLocations", resourceRoot, npcLocations)
    triggerClientEvent(client, "fishing:receiveHotspots", resourceRoot, fishHotspots)
end)

addCommandHandler("movefishnpc", function(thePlayer, command, target)
    if not exports.integration:isPlayerTrialAdmin(thePlayer) then return end
    
    local npcName = ""
    if target == "fisherman" then npcName = "Fisherman Herb"
    elseif target == "license" then npcName = "License Issuer"
    else
        outputChatBox("Syntax: /movefishnpc [fisherman / license]", thePlayer, 255, 194, 14)
        return
    end
    
    local x, y, z = getElementPosition(thePlayer)
    local _, _, rot = getElementRotation(thePlayer)
    local int = getElementInterior(thePlayer)
    local dim = getElementDimension(thePlayer)
    
    dbExec(db, "UPDATE `fish_settings` SET `x`=?, `y`=?, `z`=?, `rot`=?, `int`=?, `dim`=? WHERE `name`=?", x, y, z, rot, int, dim, npcName)
    
    if npcLocations[npcName] then
        npcLocations[npcName].x = x
        npcLocations[npcName].y = y
        npcLocations[npcName].z = z
        npcLocations[npcName].rot = rot
        npcLocations[npcName].int = int
        npcLocations[npcName].dim = dim
        triggerClientEvent(root, "fishing:receiveNPCLocations", resourceRoot, npcLocations)
    end
    outputChatBox("Moved " .. npcName .. " to your position.", thePlayer, 0, 255, 0)
end)

-- Hotspot Admin Commands
addCommandHandler("createfishhotspot", function(thePlayer, command, region)
    if not exports.integration:isPlayerTrialAdmin(thePlayer) then return end
    if not region then
        outputChatBox("Syntax: /createfishhotspot [region name]", thePlayer, 255, 194, 14)
        return
    end
    
    local x, y, z = getElementPosition(thePlayer)
    dbExec(db, "INSERT INTO `fish_hotspots` (`region`, `x`, `y`, `z`) VALUES (?, ?, ?, ?)", region, x, y, z)
    
    -- Reload hotspots from DB to capture the new auto-increment ID
    dbQuery(function(qh)
        local res = dbPoll(qh, 0)
        if res and res[1] then
            local newId = res[1].id
            fishHotspots[newId] = {id = newId, region = region, x = x, y = y, z = z, state = "Random"}
            rotateHotspots() -- Re-rotate to include the new spot
            outputChatBox("Fishing hotspot created for region '"..region.."' with ID "..newId..".", thePlayer, 0, 255, 0)
        end
    end, db, "SELECT `id` FROM `fish_hotspots` ORDER BY `id` DESC LIMIT 1")
end)

addCommandHandler("deletefishhotspot", function(thePlayer, command, idStr)
    if not exports.integration:isPlayerTrialAdmin(thePlayer) then return end
    local id = tonumber(idStr)
    if not id then
        outputChatBox("Syntax: /deletefishhotspot [id]", thePlayer, 255, 194, 14)
        return
    end
    
    if fishHotspots[id] then
        dbExec(db, "DELETE FROM `fish_hotspots` WHERE `id`=?", id)
        fishHotspots[id] = nil
        rotateHotspots() -- Re-rotate without the deleted spot
        outputChatBox("Fishing hotspot ID "..id.." deleted.", thePlayer, 0, 255, 0)
    else
        outputChatBox("No fishing hotspot found with ID "..id..".", thePlayer, 255, 0, 0)
    end
end)

addCommandHandler("forcehotspotrotation", function(thePlayer, command)
    if not exports.integration:isPlayerTrialAdmin(thePlayer) then return end
    rotateHotspots()
    outputChatBox("Forced fishing hotspots rotation.", thePlayer, 0, 255, 0)
end)

-- Pancingan List item ids
--[[
Nama dan deskripsi item untuk 5 level pancingan (Nama - Deskripsi - Weight) pada g_items
Level 1
Beginner's Rod - Lightweight and easy to handle for novice fisher. - 1.5kg
Level 2
Riverbend Rod - Flexible and designed for precision casting. - 1.5kg
Level 3
Oakstream Rod - Sturdy and reliable, perfect for medium size fishes. - 1.5kg
Level 4
Mariner's Rod - Durable and versatile, ideal for large fishes. - 1.5kg
Level 5
Thunderstrike Rod - Powerful and robust, built to handle huge fishes. - 1.5kg
]]--
local rodId = {285,286,287,288,289}

-- Ikan List item ids, ada 5 objek ikan, dan setiap objek ikan ada 2 variasi
--[[
 Nama dan deskripsi item untuk 5 level ikan (Nama - Deskripsi - Weight) pada g_items
 Level 1
 Small Fish - A common fish, usually found on shallow waters. - 1kg
 Level 2
 Regular Fish - A common fish, usually found on deep oceans. - 1.6kg
 Level 3
 Medium Fish - An uncommon fish, usually found on deep oceans. - 2kg
 Level 4
 Large Fish - A rare fish, usually found on deep oceans. - 3.2kg
 Level 5
 Huge Fish - The rarest fish, can only be found on the deepest oceans. - 3.6kg
]]--
local fishId = {290,291,292,293,294}
-- Fish price per level, ikan varian ke 2 memiliki harga +20% dari harga normal
-- Price ikan sudah di hitung berdasarkan berat ikan yang tertera diatas.
local fishPrice = {95,160,220,250,300}
-- Jumlah ikan yang harus dijual untuk naik level
local expList = {100, 110, 120, 130, 140}
-- Nama dan Weight IC ikan yang ditangkap, diperhitungkan berdasarkan weight pada g_items
-- Variasi ikan penting secara IC karena variasi ikan ke 2 lebih rare, dan bisa dijadikan sarana RP lomba mancing SAN
local fishDetail = {
    {
        {name="Sardine", rpWeight="0.1-0.3kg", lWeight=0.1, hWeight=0.3},
        {name="Anchovy", rpWeight="0.2-0.5kg", lWeight=0.2, hWeight=0.5}
    },
    {
        {name="Herring", rpWeight="0.5-1.2kg", lWeight=0.5, hWeight=1.2},
        {name="Mackerel", rpWeight="0.8-1.8kg", lWeight=0.8, hWeight=1.8}
    },
    {
        {name="Red Snapper", rpWeight="2.5-8.0kg", lWeight=1.0, hWeight=2.5},
        {name="Mahi-Mahi", rpWeight="6.0-18.0kg", lWeight=1.5, hWeight=3.0}
    },
    {
        {name="Barracuda", rpWeight="15.0-30.0kg", lWeight=2.0, hWeight=3.5},
        {name="Halibut", rpWeight="25.0-100.0kg", lWeight=2.5, hWeight=4.0}
    },
    {
        {name="Swordfish", rpWeight="80.0-300.0kg", lWeight=3.0, hWeight=4.5},
        {name="Bluefin Tuna", rpWeight="150.0-500.0kg", lWeight=3.5, hWeight=5.0}
    },
}

-- Fishing License item id
local fishLicense = 154

local licenseDetail = {
    "Resident Fisher License",
    "Recreational Fishing Permit",
    "Sport Fisher License",
    "Professional Fishing License",
    "Charter Fishing License"
}

-- Chance dapet ikan setiap tier dan variasinya
local tierChance = 0.7
local multiplierTier = 0
local variantChance = 0.7
local multiplierVariant = 0

-- tblCooldown memiliki value ["Nama_Player"] = { amount = jumlah yang dijual sebelum cooldown, cooldown = status cooldown, current = jumlah ikan exp yang sudah dijual saat ini, level = level mancing player}
local tblCooldown = {}
local cooldownTime = 900000 -- 15 menit cooldown, bisa diganti

-- Save when logging out
addEventHandler("onPlayerQuit", root, function()
    local name = getPlayerName(source)
    if tblCooldown[name] then
        dbExec(db, "UPDATE `fish_level` SET `level`=?, `amount`=? WHERE `name`=?", tblCooldown[name].level, tblCooldown[name].current, name)
        tblCooldown[name] = nil
    end
end)

-- Mass save on server shutdown
addEventHandler("onResourceStop", resourceRoot, function()
    for name, data in pairs(tblCooldown) do
        dbExec(db, "UPDATE `fish_level` SET `level`=?, `amount`=? WHERE `name`=?", data.level, data.current, name)
    end
end)

-- Jumlah ikan yang bisa dijual sebelum cooldown
local maxFish = 5

-- Saya request nama NPC nya ini ya pak hehe
local npcName = "Fisherman Herb"

-- Item ID metal, mur dan baut. Jumlah mur dan metal yang dibutuhkan
local metalId = 91
local murId = 143
local murNeed = {10,20,30,40}
local metalNeed = {2,3,4,5}
local moneyNeed = {3000,5000,7000,9000}


--[[
Penjelasan sistem level mancing
Dari segi flow, level akan naik jika player berhasil menjual ikan dengan jumlah yang sudah ditentukan
Dari segi script, begitu ada yang jual, langsung update ke database
]]--



-- ============== Modul Level ==============

-- Notes from MTA:SA Scripting wiki
-- dbQuery(onServerQueryCallback, {"Some data"}, dbConnection, "SELECT * FROM `Players` WHERE `playerName` = ?", playerName)

-- Upsert (Update or Insert) to database
function addExp(thePlayer, name, level, current, sold)
    -- Get amount yang pernah dijual + yang sedang dijual
    local total = current + sold

    -- Kalau total lebih dari jumlah yang dibutuhin untuk naik level, trigger event naik level.
    -- Total jadi 0
    if(total >= expList[level] and level < 5)then
        total = 0
        giveFishLic(thePlayer, true)
        return
    end

    -- Update value di memori
    tblCooldown[name].level = level
    tblCooldown[name].current = total
end

-- ============== Modul Give Item Ikan ==============

-- Function to give fish type based on rodLevel (level pancingan)
function giveCatch(thePlayer, inHotspot, rodLevel)
    local caughtFish = 1 -- Default ikan yang didapatkan adalah ikan level 1

    -- Di kapal atau tidak di cek client side
    -- Tier ikan yang di dapat 70% chance dapat tier yang sama dengan level pancingan, 30% chance dapat tier dibawahnya
    local maxRodLevel = 1
    if inHotspot then
        maxRodLevel = tonumber(rodLevel) or 1
    end
    
    for i = maxRodLevel, 2, -1 do
        local roll = math.random() -- Roll apakah dapat ikan di tier ini atau tidak
        if(roll >= tierChance - (tierChance * multiplierTier))then
            caughtFish = i
            break
        end
    end

    -- Fish Variant
    local variant = 1
    if(math.random() > variantChance - (variantChance * multiplierVariant))then
        variant = 2
    end

    local fishItem = fishId[caughtFish] -- the item for the caught fish type
    local fishDesc = fishDetail[caughtFish][variant] -- the description for the fish item

    if items:hasSpaceForItem(thePlayer, fishItem, 1) then
        -- [Fish Name] ([RP Weight]):[Gameplay Weight]:[Fish Variant]
        local actualWeight = fishDesc.lWeight + (math.random() * (fishDesc.hWeight - fishDesc.lWeight))
        actualWeight = string.format("%.1f", actualWeight)
        
        local itemString = tostring(fishDesc.name) .. " (" .. fishDesc.rpWeight .. "):" .. actualWeight .. ":v" .. tostring(variant)
        items:giveItem(thePlayer, fishItem, itemString)
        outputChatBox("You've caught a " .. tostring(fishDesc.name) .. "!", thePlayer, 0, 255, 0)
    end


end

-- ============== Modul Jual Ikan ==============

-- Function to check value in array, returns true and index if value is in the array. Returns false and nil otherwise.
function has_value(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true, index
        end
    end

    return false, nil
end

-- Function to sell fish
function sellFish(thePlayer)
    -- Init level = 1 jika dia pertama kali, get player name yang jual
    local name = getPlayerName(thePlayer)
    local level = 1
    local current = 0
    local countFish = 0
    local query = "SELECT * FROM `fish_level` WHERE `name` = ?" -- Ngecek apakah ini pertama kali dia jual atau tidak
    local levelFish = 0 -- Jumlah ikan yang masuk dan jadi EXP level mancing
    local totalPayment = 0 -- Total pembayaran
    local cooldown = false -- Status cooldown

    -- Cek apa dia ada di table cooldown, kalo ga ada berarti ini pertama kali dia jual setelah cooldown
    if(tblCooldown[name])then
        countFish = tblCooldown[name].amount --Update jumlah ikan yang sudah dijual
        level = tblCooldown[name].level
        current = tblCooldown[name].current
        -- If on cooldown, stop disini and return false
        if(tblCooldown[name].cooldown)then
            exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: Kebanyakan ikan yang tadi dijual, nanti lagi ya!", 255, 255, 255, 10)
            return
        end
    else
        -- Run query select yang diatas jika belum ada di tblCooldown memori, initial load per session
        local qh = dbQuery(db, query, name)
        local result = dbPoll(qh, -1)
        
        if(result and #result > 0)then
            -- Update level jika dia ada di database
            level = tonumber(result[1]["level"])
            current = tonumber(result[1]["amount"])
            tblCooldown[name] = {amount = 0, cooldown = false, current = current, level = level}
            setElementData(thePlayer, "fishing_level", level)
        else
            exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: Kamu belum punya Fishing License, silahkan apply dulu ke License Issuer!", 255, 255, 255, 10)
            return
        end
    end
    
    
    -- Loop inven player, cari item yang ikan exp, dan jumlah ikan yang dijual
    for i, val in ipairs(items:getItems(thePlayer)) do
        local itemId, itemValue = unpack(val) -- Unpack item apa aja yang ada di inven
        local isFish, tier = has_value(fishId,itemId) -- Cek apakah item tersebut ikan atau bukan

        -- If ikan dan level player memadai untuk menjual ikan dengan tingkatan/tier tersebut, kalkulasi harga jual
        if(isFish and tier<=level)then

            -- Init variable
            countFish = countFish + 1
            local bonus = 0
            local price = tonumber(fishPrice[tier])

            -- Bonus untuk version 2 sebesar 20%
            if(string.find(":v2", itemValue))then
                bonus = price * 0.2
            end

            -- Take item and count payment
            totalPayment = totalPayment + price + bonus
            items:takeItem(thePlayer, itemId)

            -- If ikan yang dijual setara sama level sekarang tingkatnya, jadiin ikan exp
            if(itemId == fishId[level])then
                levelFish = levelFish + 1
            end

            -- If ikan yang dijual udah 5, stop loop.
            if(countFish == 5)then
                cooldown = true
                break
            end

        end

    end
    -- If ada yang kejual, maka total payment akan lebih dari 0
    if(totalPayment > 0)then

        -- Add the exp to the database, level 5 tidak bisa nambah exp lagi
        if(level < 5)then
            addExp(thePlayer, name, level, current, levelFish)
        end

        -- Cooldown added to table value can be true or false
        tblCooldown[name].amount = countFish;
        tblCooldown[name].cooldown = cooldown;

        -- Give money and send message
        exports.global:giveMoney(thePlayer, totalPayment)
        exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: Ini uang hasil penjualan ikanmu, kembali lagi nanti!", 255, 255, 255, 10)

        -- Disable Cooldown after 10 second, jadiin 15 menit nanti  
        if(cooldown)then
            setTimer(function() 
                
                -- Remove the player from the table after the cooldown is done
                tblCooldown[name].cooldown = false;
                tblCooldown[name].amount = 0;
                outputChatBox("You can sell some fish again!", thePlayer, 0, 255, 0)
            
            end, cooldownTime, 1)
        end
    else
        exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: Mau jual angin? Dateng kalau ada ikan buat dijual!", 255, 255, 255, 10)
    end

end

-- ============== Modul Items ==============

-- Mengambil ketika pancingan patah
function takeRod(thePlayer, currentRod)
    return items:takeItem(thePlayer, currentRod)
end

-- Memberikan fishing license, cek ke tabel, baru ngecek ke database 
function giveFishLic(thePlayer, levelUp)

    local name = getPlayerName(thePlayer)
    local query = "SELECT * FROM `fish_level` WHERE `name` = ?"
    local level = 1

    if(tblCooldown[name])then
        level = tblCooldown[name].level
    else
        local qh = dbQuery(db, query, name)
        local result = dbPoll(qh, -1)
        
        if(result and #result > 0)then
            level = tonumber(result[1]["level"])
            tblCooldown[name] = {amount = 0, cooldown = false, current = tonumber(result[1]["amount"]), level = level}
            setElementData(thePlayer, "fishing_level", level)
        else
            dbExec(db, "INSERT INTO `fish_level` (`name`, `level`, `amount`) VALUES (?, 1, 0)", name)
            tblCooldown[name] = {amount = 0, cooldown = false, current = 0, level = 1}
            setElementData(thePlayer, "fishing_level", 1)
        end
    end

    if(levelUp)then
        level = level + 1
        tblCooldown[name].level = level
        tblCooldown[name].current = 0
        setElementData(thePlayer, "fishing_level", level)
        exports.global:sendLocalText(thePlayer, "[English] License Issuer says: Selamat anda berhasil naik level!", 255, 255, 255, 10) 
    end

    if(hasFishingLicense(thePlayer, level))then -- Jika player memiliki fishing license yang paling baru
        message = "Wah, izin memancingmu sudah yang paling baru!"
    else
        if(items:hasItem(thePlayer, fishLicense))then
            items:takeItem(thePlayer, fishLicense) -- Ambil license yang lama
        end
        items:giveItem(thePlayer, fishLicense, licenseDetail[level])
        message = "Ini izin memancingmu yang baru, jangan sampai hilang ya!"
    end
    -- Send message
    exports.global:sendLocalText(thePlayer, "[English] License Issuer says: " .. message, 255, 255, 255, 10) 

end

function hasFishingLicense(thePlayer, level)
    return items:hasItem(thePlayer, fishLicense, licenseDetail[level])
end

function upgradeRod(thePlayer)
    -- Loop dari pancingan terendah
    for i, rod in ipairs(rodId) do
        local haveRod = items:hasItem(thePlayer, rod)
        -- If orangnya cuman punya pancingan level 5
        if(i==5 and haveRod)then
            exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: Pancinganmu sudah yang paling bagus, kembali dengan pancingan yang lain.", 255, 255, 255, 10)
            return
        -- If orangnya punya pancingan yang sedang di loop
        elseif(haveRod)then
            -- Cek punya mur, metal, duit, dan fishing license satu tingkat lebih tinggi
            local hasMur = items:countItems(thePlayer, murId) >= murNeed[i]
            local hasMetal = items:countItems(thePlayer, metalId) >= metalNeed[i]
            local hasMoney = exports.global:hasMoney(thePlayer, moneyNeed[i])
            local hasFishLic = hasFishingLicense(thePlayer, i+1)
            local message = ""
            
            if(not hasMur)then
                message = "Kamu membutuhkan " .. murNeed[i] .. " Mur dan Baut untuk meningkatkan kualitas pancingan, kembalilah lagi nanti."
            elseif(not hasMetal)then
                message = "Kamu membutuhkan " .. metalNeed[i] .. " Metal untuk meningkatkan kualitas pancingan, kembalilah lagi nanti."
            elseif(not hasMoney)then
                message = "Kamu membutuhkan $" .. moneyNeed[i] .. " untuk membayar biayanya, kembalilah lagi nanti."
            elseif(not hasFishLic)then
                message = "Kamu membutuhkan " .. licenseDetail[i+1] .. " untuk membuat pancingan ini."
            end

            -- Message will be empty if the player has it all in his inventory
            if(message == "")then
                -- Ngambil mur yang dibutuhin
                for j = 1, murNeed[i] do
                    items:takeItem(thePlayer, murId)
                end
                -- Ngambil metal yang dibutuhin
                for j = 1, metalNeed[i] do
                    items:takeItem(thePlayer, metalId)
                end
                -- Ngambil duit
                exports.global:takeMoney(thePlayer, moneyNeed[i])
                items:takeItem(thePlayer, rod) -- Ngambil pancingan yang lama
                items:giveItem(thePlayer, rodId[i+1], 1) -- Ngasih pancingan yang baru
                message = "Selamat menikmati pancingan baru!"

            end
            -- Send message
            exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: " .. message, 255, 255, 255, 10) 
            return
        end

    end
    -- Loop berakhir, dan tidak ada pancingan ditemukan
    exports.global:sendLocalText(thePlayer, "[English] " .. npcName .. " says: Pancingannya ketinggalan ya? Kesini lagi kalau udah ada pancingannya.", 255, 255, 255, 10)

end



-- ============== Debug Functions ==============
function giveLicense(thePlayer, command, level) -- Debug only
    outputChatBox("Granted fishing license level "..level.. "!", thePlayer, 0, 255, 0)
    items:giveItem(thePlayer, fishLicense, licenseDetail[tonumber(level)])
end

function giveRod(thePlayer, command, level) -- Debug only
    outputChatBox("Granted fishing rod level "..level.."!", thePlayer, 0, 255, 0)
    items:giveItem(thePlayer, rodId[tonumber(level)], 1)
end

function giveStuff(thePlayer, command, level) -- Debug only
    outputChatBox("Granted items to craft rod level "..level.."!", thePlayer, 0, 255, 0)
    for i = 1, murNeed[tonumber(level)], 1 do
        items:giveItem(thePlayer, murId, 1)
    end
    for i = 1, metalNeed[tonumber(level)], 1 do
        items:giveItem(thePlayer, metalId, 1)
    end
    exports.global:giveMoney(thePlayer, moneyNeed[tonumber(level)])
end

function giveFish(thePlayer, command, level) -- Debug only
    outputChatBox("Catching you a fish with rod level "..level.."!", thePlayer, 0, 255, 0)
    giveCatch(thePlayer, level)
end

-- Fungsi2 untuk proses debug, tidak untuk di up ke server utama
addCommandHandler("tbl", printTbl)
addCommandHandler("sellfish", sellFish)
addCommandHandler("givefish", giveFish)
addCommandHandler("upgraderod", upgradeRod)
addCommandHandler("givelic", giveLicense)
addCommandHandler("giverod", giveRod)
addCommandHandler("givestuff", giveStuff)


addEvent("fishing:giveCatch", true)
addEvent("fishing:takeRod", true)
addEvent("fishing:sellFish", true)
addEvent("fishing:giveLic", true)
addEvent("fishing:upgradeRod", true)
addEvent("fishing:applyLicense", true)
addEventHandler("fishing:giveCatch", root, giveCatch)
addEventHandler("fishing:takeRod", root, takeRod)
addEventHandler("fishing:sellFish", root, sellFish)
addEventHandler("fishing:giveLic", root, giveFishLic)
addEventHandler("fishing:upgradeRod", root, upgradeRod)

addEventHandler("fishing:applyLicense", root, function(thePlayer)
    giveFishLic(thePlayer, false)
end)

addEventHandler("onCharacterLogin", root, function()
    local name = getPlayerName(source)
    local query = "SELECT * FROM `fish_level` WHERE `name` = ?"
    dbQuery(function(qh, client)
        if isElement(client) then
            local res = dbPoll(qh, 0)
            if res and #res > 0 then
                local level = tonumber(res[1]["level"])
                tblCooldown[name] = {amount = 0, cooldown = false, current = tonumber(res[1]["amount"]), level = level}
                setElementData(client, "fishing_level", level)
            else
                setElementData(client, "fishing_level", 0)
            end
        end
    end, {source}, db, query, name)
end)

-- Commands and Events
--[[

    addEvent("fishing:giveCatch", true)
    addEvent("fishing:takeRod", true)
    addEvent("fishing:GeneratePayment", true)
    addEvent("fishing:sellFish", true)
    addEventHandler("fishing:giveCatch", root, giveCatch)
    addEventHandler("fishing:takeRod", root, takeRod)
    addEventHandler("fishing:GeneratePayment", root, GenerateFishPayment)
    addEventHandler("fishing:sellFish", root, sellFish)
]]
