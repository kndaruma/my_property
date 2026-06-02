local QBCore = exports['qb-core']:GetCoreObject()
local Houses = {}
local nextHouseId = 1
local RequireAdminCheck = true 

-- =========================================================
-- [1] UTILITIES & HELPERS
-- =========================================================
local function IsAdmin(src)
    if not RequireAdminCheck then return true end 
    if QBCore.Functions.HasPermission(src, 'god') or QBCore.Functions.HasPermission(src, 'admin') then return true end
    if IsPlayerAceAllowed(src, 'command') then return true end
    return false
end

local function SaveHouseColumn(houseId, column, data)
    local query = string.format('UPDATE my_properties SET `%s` = ? WHERE id = ?', column)
    local value = data and json.encode(data) or nil
    MySQL.update(query, { value, houseId })
end

local function FormatVec3(vec)
    if type(vec) == "vector3" or type(vec) == "vector4" then return { x = vec.x, y = vec.y, z = vec.z } end
    if type(vec) == "table" and vec.x then return { x = vec.x, y = vec.y, z = vec.z } end
    return vec
end

local function SyncHouseToAll(houseId)
    if Houses[houseId] then
        TriggerClientEvent('myproperty:syncSingleHouse', -1, houseId, Houses[houseId])
    else
        TriggerClientEvent('myproperty:removeHouse', -1, houseId)
    end
end

-- =========================================================
-- [2] DATABASE INITIALIZATION 
-- =========================================================
Citizen.CreateThread(function()
    print("[MyProperty] Connecting to SQL Database...")
    MySQL.query('SELECT * FROM my_properties', {}, function(result)
        if result then
            for _, row in ipairs(result) do
                local id = row.id
                if id >= nextHouseId then nextHouseId = id + 1 end
                
                Houses[id] = {
                    id = id, dimension = row.dimension, parent_dimension = row.parent_dimension,
                    maxSlots = row.max_slots, doors = json.decode(row.doors) or {},
                    lifts = json.decode(row.lifts) or {}, keys = json.decode(row.keys) or {},
                    time = row.time and json.decode(row.time) or nil,
                    donate_expire = row.donate_expire or 0,
                    owner = row.owner, price = row.price or -1, furniture = {}
                }
            end
            
            MySQL.query('SELECT * FROM my_property_furniture', {}, function(fResult)
                if fResult then
                    for _, fRow in ipairs(fResult) do
                        local hId = fRow.house_id
                        if Houses[hId] then
                            local c, r = json.decode(fRow.coords), json.decode(fRow.rot)
                            if c and c.x and r and r.x then
                                table.insert(Houses[hId].furniture, {
                                    id = fRow.id, name = fRow.name, model = fRow.model, price = fRow.price,
                                    coords = c, rot = r, noCollision = (fRow.no_collision == 1), dimension = fRow.dimension
                                })
                            end
                        end
                    end
                end
                print("[MyProperty] Successfully loaded " .. #result .. " properties and furniture.")
            end)
        end
    end)
end)

-- =========================================================
-- [3] CORE PROPERTY MANAGEMENT & ADMIN SETTINGS
-- =========================================================
RegisterNetEvent('myproperty:requestSync', function() TriggerClientEvent('myproperty:syncHouses', source, Houses) end)

RegisterCommand('createhouse', function(source, args)
    local src = source
    if not IsAdmin(src) then TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'ไม่มีสิทธิ์ใช้งาน!' } }) return end
    
    local maxSlots = tonumber(args[1]) or 100
    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    local dim = nextHouseId + 5000 
    
    local Player = QBCore.Functions.GetPlayer(src)
    local cid = Player.PlayerData.citizenid
    local name = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
    
    local formattedCoords = { x = coords.x, y = coords.y, z = coords.z }
    local doorsData = { { name = "Main", entrance = formattedCoords, exit = nil, locked = false } }
    local keysData = { [cid] = name }
    
    MySQL.insert('INSERT INTO my_properties (dimension, parent_dimension, max_slots, doors, `keys`, owner, price) VALUES (?, ?, ?, ?, ?, ?, ?)', 
    {dim, 0, maxSlots, json.encode(doorsData), json.encode(keysData), cid, -1}, function(id)
        if id then
            Houses[id] = { 
                id = id, dimension = dim, parent_dimension = 0, maxSlots = maxSlots, 
                doors = doorsData, lifts = {}, keys = keysData, time = nil, 
                owner = cid, price = -1, furniture = {}, donate_expire = 0
            }
            nextHouseId = id + 1
            SyncHouseToAll(id)
            TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'สร้างบ้านสำเร็จ! ID: ' .. id .. ' (คุณคือเจ้าของ)' } })

            local backupData = json.encode(Houses[id], {indent = true})
            local fileName = "Backup_property/Backup_Property_" .. tostring(id) .. ".json"
            SaveResourceFile(GetCurrentResourceName(), fileName, backupData, -1)
        end
    end)
end, false)

RegisterCommand('setslots', function(source, args)
    local src = source
    if not IsAdmin(src) then TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'ไม่มีสิทธิ์ใช้งาน!' } }) return end
    
    local houseId = tonumber(args[1])
    local newSlots = tonumber(args[2])
    
    if not houseId or not newSlots then
        TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'วิธีใช้: /setslots [HouseID] [จำนวนช่อง]' } })
        return
    end
    
    if Houses[houseId] then
        Houses[houseId].maxSlots = newSlots
        MySQL.update('UPDATE my_properties SET max_slots = ? WHERE id = ?', {newSlots, houseId})
        SyncHouseToAll(houseId)
        TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'อัปเดตจำนวนช่องเฟอร์นิเจอร์บ้าน ID ' .. houseId .. ' เป็น ' .. newSlots .. ' ช่องเรียบร้อยแล้ว' } })
    else
        TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'ไม่พบบ้าน ID นี้ในระบบ!' } })
    end
end, false)

RegisterCommand('setpdonate', function(source, args)
    local src = source
    if not IsAdmin(src) then TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'ไม่มีสิทธิ์ใช้งาน!' } }) return end
    
    local houseId = tonumber(args[1])
    local days = tonumber(args[2])
    
    if not houseId or not days then
        TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'วิธีใช้: /setpdonate [HouseID] [จำนวนวัน (-1 คือถาวร, 0 คือลบ)]' } })
        return
    end
    
    if Houses[houseId] then
        local expireTime = 0
        if days == -1 then
            expireTime = -1 -- ถาวร
        elseif days > 0 then
            expireTime = os.time() + (days * 86400) -- คำนวณวันเป็นวินาที
        end
        
        Houses[houseId].donate_expire = expireTime
        MySQL.update('UPDATE my_properties SET donate_expire = ? WHERE id = ?', {expireTime, houseId})
        SyncHouseToAll(houseId)
        
        local msg = 'ลบสถานะ Donate ของบ้าน ID ' .. houseId .. ' แล้ว'
        if days == -1 then msg = 'ตั้งสถานะ Donate บ้าน ID ' .. houseId .. ' แบบ ถาวร สำเร็จ!'
        elseif days > 0 then msg = 'ตั้งสถานะ Donate บ้าน ID ' .. houseId .. ' จำนวน ' .. days .. ' วัน สำเร็จ!' end
        
        TriggerClientEvent('chat:addMessage', src, { args = { '^2System', msg } })
    else
        TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'ไม่พบบ้าน ID นี้ในระบบ!' } })
    end
end, false)

RegisterNetEvent('myproperty:requestDeleteMenu', function(houseId)
    local src = source
    if IsAdmin(src) then TriggerClientEvent('myproperty:openDeleteMenu', src, houseId) end
end)

RegisterNetEvent('myproperty:confirmDeleteProperty', function(houseId)
    local src = source
    if not IsAdmin(src) then return end
    if Houses[houseId] then
        MySQL.query('DELETE FROM my_properties WHERE id = ?', {houseId})
        MySQL.query('DELETE FROM my_property_furniture WHERE house_id = ?', {houseId})
        for _, player in ipairs(GetPlayers()) do
            local pId = tonumber(player)
            local currentDim = GetPlayerRoutingBucket(pId)
            local match = (currentDim == Houses[houseId].dimension)
            if not match and Houses[houseId].lifts then
                for _, f in ipairs(Houses[houseId].lifts) do if currentDim == f.dim then match = true break end end
            end
            if match then
                SetPlayerRoutingBucket(pId, Houses[houseId].parent_dimension)
                TriggerClientEvent('myproperty:syncDimension', pId, Houses[houseId].parent_dimension)
                local outCoords = Houses[houseId].doors[1].entrance
                if outCoords then TriggerClientEvent('myproperty:teleport', pId, outCoords) end
            end
        end
        Houses[houseId] = nil
        SyncHouseToAll(houseId)
        TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'ลบบ้านถาวรสำเร็จ!' } })
    end
end)

-- =========================================================
-- [4] DIMENSION & TELEPORTATION
-- =========================================================
RegisterNetEvent('myproperty:enterHouse', function(houseId, doorName)
    local src = source
    if Houses[houseId] then
        local door = nil
        for _, d in ipairs(Houses[houseId].doors) do if d.name == doorName then door = d break end end
        if door then
            if door.exit then
                SetPlayerRoutingBucket(src, Houses[houseId].dimension)
                TriggerClientEvent('myproperty:syncDimension', src, Houses[houseId].dimension)
                TriggerClientEvent('myproperty:teleport', src, door.exit)
            elseif IsAdmin(src) then
                SetPlayerRoutingBucket(src, Houses[houseId].dimension)
                TriggerClientEvent('myproperty:syncDimension', src, Houses[houseId].dimension)
                TriggerClientEvent('myproperty:teleport', src, door.entrance)
                TriggerClientEvent('chat:addMessage', src, { args = { '^3System', 'ยังไม่มีจุดออก! กรุณาใช้ noclip และ /se ด้านใน' } })
            else
                TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'ประตูนี้ยังไม่ได้ตั้งจุดออกด้านใน!' } })
            end
        end
    end
end)

RegisterNetEvent('myproperty:exitHouse', function(houseId, doorName)
    local src = source
    if Houses[houseId] then
        local door = nil
        for _, d in ipairs(Houses[houseId].doors) do if d.name == doorName then door = d break end end
        if door and door.entrance then
            SetPlayerRoutingBucket(src, Houses[houseId].parent_dimension)
            TriggerClientEvent('myproperty:syncDimension', src, Houses[houseId].parent_dimension)
            TriggerClientEvent('myproperty:teleport', src, door.entrance)
        else
            TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'ประตูนี้ยังไม่ได้ตั้งจุดเข้าด้านนอก!' } })
        end
    end
end)

RegisterCommand('dleave', function(source)
    local src = source
    if GetPlayerRoutingBucket(src) ~= 0 then
        SetPlayerRoutingBucket(src, 0)
        TriggerClientEvent('myproperty:syncDimension', src, 0)
        TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'คุณออกจากมิติแล้ว' } })
    end
end, false)

-- =========================================================
-- [5] KEYS & TIME MANAGEMENT
-- =========================================================
RegisterNetEvent('myproperty:giveKey', function(houseId, targetSrc)
    local src = source
    local Player = QBCore.Functions.GetPlayer(targetSrc)
    if not Player or not Houses[houseId] then return end
    
    local cid = Player.PlayerData.citizenid
    local name = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
    Houses[houseId].keys[cid] = name
    SaveHouseColumn(houseId, 'keys', Houses[houseId].keys)
    SyncHouseToAll(houseId)
    TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'มอบกุญแจให้ ' .. name } })
    TriggerClientEvent('chat:addMessage', targetSrc, { args = { '^2System', 'คุณได้รับกุญแจบ้าน ID: ' .. houseId } })
end)

RegisterNetEvent('myproperty:removeKey', function(houseId, cid, name)
    local src = source
    if Houses[houseId] and Houses[houseId].keys[cid] then
        Houses[houseId].keys[cid] = nil
        SaveHouseColumn(houseId, 'keys', Houses[houseId].keys)
        SyncHouseToAll(houseId)
        TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'ดึงกุญแจคืนจาก ' .. name } })
    end
end)

RegisterNetEvent('myproperty:autoClaimOldHouse', function(houseId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if IsAdmin(src) and Houses[houseId] then
        local cid = Player.PlayerData.citizenid
        local name = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
        Houses[houseId].keys[cid] = name
        SaveHouseColumn(houseId, 'keys', Houses[houseId].keys)
        SyncHouseToAll(houseId)
        TriggerClientEvent('chat:addMessage', src, { args = { '^3System', 'รับสิทธิ์ครอบครองกุญแจบ้านอัตโนมัติ' } })
    end
end)

RegisterNetEvent('myproperty:setTime', function(houseId, h, m)
    if Houses[houseId] then
        Houses[houseId].time = { h = h, m = m }
        SaveHouseColumn(houseId, 'time', Houses[houseId].time)
        SyncHouseToAll(houseId)
        TriggerClientEvent('chat:addMessage', source, { args = { '^2System', string.format('ล็อคเวลาบ้านเป็น %02d:%02d', h, m) } })
    end
end)

RegisterNetEvent('myproperty:resetTime', function(houseId)
    if Houses[houseId] then
        Houses[houseId].time = nil
        SaveHouseColumn(houseId, 'time', nil)
        SyncHouseToAll(houseId)
        TriggerClientEvent('chat:addMessage', source, { args = { '^2System', 'รีเซ็ตเวลาบ้านตามเซิร์ฟเวอร์แล้ว' } })
    end
end)

-- =========================================================
-- [6] DOORS MANAGEMENT & LOCK SYSTEM
-- =========================================================
RegisterNetEvent('myproperty:addDoor', function(houseId, doorName, exitCoords)
    if Houses[houseId] then
        local formattedCoords = nil
        if exitCoords then formattedCoords = { x = exitCoords.x, y = exitCoords.y, z = exitCoords.z } end
        table.insert(Houses[houseId].doors, { name = doorName, entrance = nil, exit = formattedCoords, locked = false })
        SaveHouseColumn(houseId, 'doors', Houses[houseId].doors)
        SyncHouseToAll(houseId)
        TriggerClientEvent('chat:addMessage', source, { args = { '^2System', 'สร้างประตู [' .. doorName .. '] สำเร็จ!' } })
    end
end)

RegisterNetEvent('myproperty:deleteDoor', function(houseId, doorName)
    if Houses[houseId] then
        for i, d in ipairs(Houses[houseId].doors) do
            if d.name == doorName then
                table.remove(Houses[houseId].doors, i)
                SaveHouseColumn(houseId, 'doors', Houses[houseId].doors)
                SyncHouseToAll(houseId)
                TriggerClientEvent('chat:addMessage', source, { args = { '^2System', 'ลบประตู [' .. doorName .. '] แล้ว!' } })
                break
            end
        end
    end
end)

RegisterNetEvent('myproperty:setExitCoords', function(houseId, doorName, coords)
    if Houses[houseId] then
        for _, d in ipairs(Houses[houseId].doors) do
            if d.name == doorName then
                d.exit = { x = coords.x, y = coords.y, z = coords.z }
                SaveHouseColumn(houseId, 'doors', Houses[houseId].doors)
                SyncHouseToAll(houseId)
                TriggerClientEvent('chat:addMessage', source, { args = { '^2System', 'ตั้งพิกัดจุดออกสำหรับ [' .. doorName .. ']' } })
                break
            end
        end
    end
end)

RegisterNetEvent('myproperty:setEntranceCoords', function(houseId, doorName, coords)
    if Houses[houseId] then
        for _, d in ipairs(Houses[houseId].doors) do
            if d.name == doorName then
                d.entrance = { x = coords.x, y = coords.y, z = coords.z }
                SaveHouseColumn(houseId, 'doors', Houses[houseId].doors)
                SyncHouseToAll(houseId)
                TriggerClientEvent('chat:addMessage', source, { args = { '^2System', 'ตั้งพิกัดจุดเข้าสำหรับ [' .. doorName .. ']' } })
                break
            end
        end
    end
end)

RegisterNetEvent('myproperty:setDoorLock', function(houseId, doorName, state)
    local src = source
    if Houses[houseId] and Houses[houseId].doors then
        for _, d in ipairs(Houses[houseId].doors) do
            if d.name == doorName then
                d.locked = state
                SaveHouseColumn(houseId, 'doors', Houses[houseId].doors)
                SyncHouseToAll(houseId)
                local statusMsg = d.locked and "^1ล็อค" or "^2ปลดล็อค"
                TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'ประตู [' .. doorName .. '] ตอนนี้ ' .. statusMsg } })
                break
            end
        end
    end
end)

-- =========================================================
-- [7] KNOCK & INVITE SYSTEM 
-- =========================================================
RegisterNetEvent('myproperty:knockDoor', function(houseId, doorName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local knockerName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
    
    if Houses[houseId] then
        local houseDim = Houses[houseId].dimension
        local sentToSomeone = false
        
        for _, playerId in ipairs(GetPlayers()) do
            local pId = tonumber(playerId)
            if GetPlayerRoutingBucket(pId) == houseDim then
                TriggerClientEvent('myproperty:receiveKnock', pId, src, knockerName, houseId, doorName)
                sentToSomeone = true
            end
        end
        
        if sentToSomeone then
            TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'เคาะประตูแล้ว กรุณารอสักครู่...' } })
        else
            TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'ดูเหมือนจะไม่มีใครอยู่ข้างในบ้านเลย...' } })
        end
    end
end)

RegisterNetEvent('myproperty:answerKnock', function(targetSrc, houseId, doorName, isAllowed)
    local src = source
    if isAllowed then
        TriggerClientEvent('myproperty:forceEnter', targetSrc, houseId, doorName)
        TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'คุณอนุญาตให้เข้าบ้านแล้ว' } })
    else
        TriggerClientEvent('chat:addMessage', targetSrc, { args = { '^1System', 'เจ้าของบ้านปฏิเสธการให้เข้า' } })
        TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'คุณปฏิเสธการให้เข้าบ้าน' } })
    end
end)

RegisterNetEvent('myproperty:requestPlayersOutside', function(houseId, doorName)
    local src = source
    local house = Houses[houseId]
    local playersOutside = {}
    
    if house then
        local door = nil
        for _, d in ipairs(house.doors) do if d.name == doorName then door = d break end end
        if door and door.entrance then
            for _, playerId in ipairs(GetPlayers()) do
                local pId = tonumber(playerId)
                if GetPlayerRoutingBucket(pId) == house.parent_dimension then
                    local ped = GetPlayerPed(pId)
                    local pCoords = GetEntityCoords(ped)
                    local dist = #(pCoords - vector3(door.entrance.x, door.entrance.y, door.entrance.z))
                    if dist < 5.0 then
                        local Player = QBCore.Functions.GetPlayer(pId)
                        if Player then
                            local name = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
                            table.insert(playersOutside, { src = pId, name = name })
                        end
                    end
                end
            end
        end
    end
    TriggerClientEvent('myproperty:openInviteList', src, playersOutside, houseId, doorName)
end)

RegisterNetEvent('myproperty:sendInvite', function(targetSrc, houseId, doorName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if Player then
        local inviterName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
        TriggerClientEvent('myproperty:receiveInvite', targetSrc, inviterName, houseId, doorName)
        TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'ส่งคำเชิญให้ผู้เล่นแล้ว' } })
    end
end)

-- =========================================================
-- [8] LIFT / ELEVATOR MANAGEMENT
-- =========================================================
RegisterNetEvent('myproperty:createFirstFloorLift', function(houseId, coords)
    if Houses[houseId] then
        Houses[houseId].lifts = { { name = "1st Floor", dim = Houses[houseId].dimension, coords = coords } }
        SaveHouseColumn(houseId, 'lifts', Houses[houseId].lifts)
        SyncHouseToAll(houseId)
    end
end)
RegisterNetEvent('myproperty:addLiftFloor', function(houseId, name)
    if Houses[houseId] then
        local newDim = (houseId * 100) + #Houses[houseId].lifts + 1
        table.insert(Houses[houseId].lifts, { name = name, dim = newDim, coords = nil })
        SaveHouseColumn(houseId, 'lifts', Houses[houseId].lifts)
        SyncHouseToAll(houseId)
    end
end)
RegisterNetEvent('myproperty:updateLiftMarker', function(houseId, floorIndex, coords)
    if Houses[houseId] and Houses[houseId].lifts[floorIndex] then
        Houses[houseId].lifts[floorIndex].coords = coords
        SaveHouseColumn(houseId, 'lifts', Houses[houseId].lifts)
        SyncHouseToAll(houseId)
    end
end)
RegisterNetEvent('myproperty:deleteLiftFloor', function(houseId, floorIndex)
    if Houses[houseId] and Houses[houseId].lifts[floorIndex] then
        table.remove(Houses[houseId].lifts, floorIndex)
        SaveHouseColumn(houseId, 'lifts', Houses[houseId].lifts)
        SyncHouseToAll(houseId)
    end
end)
RegisterNetEvent('myproperty:useElevator', function(houseId, targetDim, coords)
    SetPlayerRoutingBucket(source, targetDim)
    TriggerClientEvent('myproperty:syncDimension', source, targetDim)
    TriggerClientEvent('myproperty:teleport', source, coords)
end)

-- =========================================================
-- [9] PROPERTY MARKET (BUY / SELL / CANCEL)
-- =========================================================
RegisterNetEvent('myproperty:sellProperty', function(houseId, price)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local house = Houses[houseId]
    if not house then return end
    local hasPerm = false
    if IsAdmin(src) then hasPerm = true end
    if house.owner == Player.PlayerData.citizenid then hasPerm = true end
    if not house.owner and house.keys and house.keys[Player.PlayerData.citizenid] then hasPerm = true end

    if hasPerm then
        house.price = price
        MySQL.update('UPDATE my_properties SET price = ? WHERE id = ?', {price, houseId})
        SyncHouseToAll(houseId)
        TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'ประกาศขายบ้านเรียบร้อยในราคา $' .. price } })
    else TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'คุณไม่ใช่เจ้าของบ้านหลังนี้!' } }) end
end)

RegisterNetEvent('myproperty:cancelSell', function(houseId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local house = Houses[houseId]
    if not house then return end
    local hasPerm = false
    if IsAdmin(src) then hasPerm = true end
    if house.owner == Player.PlayerData.citizenid then hasPerm = true end
    if not house.owner and house.keys and house.keys[Player.PlayerData.citizenid] then hasPerm = true end

    if hasPerm then
        house.price = -1 
        MySQL.update('UPDATE my_properties SET price = -1 WHERE id = ?', {houseId})
        SyncHouseToAll(houseId)
        TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'ยกเลิกการขายบ้านหลังนี้แล้ว' } })
    else TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'คุณไม่ใช่เจ้าของบ้านหลังนี้!' } }) end
end)

RegisterNetEvent('myproperty:buyProperty', function(houseId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local house = Houses[houseId]
    if not house or not house.price or house.price < 0 then 
        TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'บ้านหลังนี้ไม่ได้ประกาศขาย!' } }) return 
    end

    local price = house.price
    local buyerCid = Player.PlayerData.citizenid
    local buyerName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname

    if house.owner == buyerCid then TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'คุณเป็นเจ้าของบ้านหลังนี้อยู่แล้ว!' } }) return end

    if Player.Functions.RemoveMoney('bank', price, "property-buy") then
        if house.owner then
            local tPlayer = QBCore.Functions.GetPlayerByCitizenId(house.owner)
            if tPlayer then
                tPlayer.Functions.AddMoney('bank', price, "property-sell")
                TriggerClientEvent('chat:addMessage', tPlayer.PlayerData.source, { args = { '^2System', 'มีคนซื้อบ้านของคุณ! ได้รับเงินโอนเข้าธนาคาร $' .. price } })
            else
                MySQL.query('SELECT money FROM players WHERE citizenid = ?', {house.owner}, function(result)
                    if result[1] then
                        local money = json.decode(result[1].money)
                        if money then money.bank = (money.bank or 0) + price MySQL.update('UPDATE players SET money = ? WHERE citizenid = ?', {json.encode(money), house.owner}) end
                    end
                end)
            end
        end

        house.owner = buyerCid
        house.price = -1 
        house.keys = { [buyerCid] = buyerName }
        MySQL.update('UPDATE my_properties SET owner = ?, price = -1, keys = ? WHERE id = ?', {buyerCid, json.encode(house.keys), houseId})
        SyncHouseToAll(houseId)
        TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'ยินดีด้วย! คุณซื้อบ้านหลังนี้เรียบร้อยแล้ว' } })
    else TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'เงินในธนาคารของคุณไม่พอ!' } }) end
end)

-- =========================================================
-- [10] FURNITURE MANAGEMENT
-- =========================================================
RegisterNetEvent('myproperty:buyFurniture', function(hId, data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local price = data.price or 0

    if Houses[hId] then 
        if price <= 0 or Player.Functions.RemoveMoney('cash', price, "property-buy-furniture") then
            local formattedCoords, formattedRot = FormatVec3(data.coords), FormatVec3(data.rot)
            local query = 'INSERT INTO my_property_furniture (id, house_id, name, model, price, coords, rot, no_collision, dimension) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
            MySQL.insert(query, { data.id, hId, data.name, data.model, price, json.encode(formattedCoords), json.encode(formattedRot), data.noCollision and 1 or 0, data.dimension })
            
            data.coords = formattedCoords 
            data.rot = formattedRot
            
            if not Houses[hId].furniture then Houses[hId].furniture = {} end
            table.insert(Houses[hId].furniture, data)
            
            TriggerClientEvent('myproperty:syncSingleFurniture', -1, hId, data, "add") 
            
            if price > 0 then
                TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'ซื้อเฟอร์นิเจอร์สำเร็จ หักเงินสด $' .. price } })
            end
        else
            TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'เงินสดของคุณไม่พอสำหรับซื้อเฟอร์นิเจอร์ชิ้นนี้!' } })
        end
    end 
end)

RegisterNetEvent('myproperty:updateFurniture', function(hId, fId, c, r, n)
    if Houses[hId] then 
        local formattedCoords, formattedRot = FormatVec3(c), FormatVec3(r)
        for _, f in ipairs(Houses[hId].furniture) do 
            if tostring(f.id) == tostring(fId) then 
                f.coords, f.rot, f.noCollision = formattedCoords, formattedRot, n 
                MySQL.update('UPDATE my_property_furniture SET coords = ?, rot = ?, no_collision = ? WHERE id = ? AND house_id = ?', { json.encode(formattedCoords), json.encode(formattedRot), n and 1 or 0, fId, hId })
                TriggerClientEvent('myproperty:syncSingleFurniture', -1, hId, f, "update") 
                break 
            end 
        end 
    end 
end)

RegisterNetEvent('myproperty:deleteFurniture', function(hId, fId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)

    if Houses[hId] then 
        for i, f in ipairs(Houses[hId].furniture) do 
            if tostring(f.id) == tostring(fId) then 
                local removedItem = table.remove(Houses[hId].furniture, i)
                local price = removedItem.price or 0
                
                if Player and price > 0 then
                    Player.Functions.AddMoney('cash', price, "property-sell-furniture")
                    TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'ขายเฟอร์นิเจอร์สำเร็จ ได้รับเงินสดคืน $' .. price } })
                end

                MySQL.query('DELETE FROM my_property_furniture WHERE id = ? AND house_id = ?', {removedItem.id, hId})
                TriggerClientEvent('myproperty:syncSingleFurniture', -1, hId, removedItem, "remove") 
                break 
            end 
        end 
    end 
end)

-- =========================================================
-- [11] AUTO-BACKUP SYSTEM
-- =========================================================
Citizen.CreateThread(function()
    Citizen.Wait(10000) 

    while true do
        local count = 0
        
        for houseId, houseData in pairs(Houses) do
            local backupData = json.encode(houseData, {indent = true})
            local fileName = "Backup_property/Backup_Property_" .. tostring(houseId) .. ".json"
            SaveResourceFile(GetCurrentResourceName(), fileName, backupData, -1)
            count = count + 1
            
            -- พอเซฟครบทุกๆ 10 หลัง ให้เซิร์ฟเวอร์หยุดพักหายใจ 50ms ป้องกันเซิร์ฟเวอร์ค้าง
            if count % 10 == 0 then
                Citizen.Wait(50)
            end
        end
        
        if count > 0 then
            print("^2[MyProperty] Auto-Backup completed! Saved " .. count .. " properties to 'Backup_property' folder.^7")
        end
        
        Citizen.Wait(2 * 60 * 60 * 1000) 
    end
end)

-- ==========================================
-- [RENT SYSTEM] ระบบเช่าบ้าน (คิดราคาต่อวัน)
-- ==========================================
RegisterNetEvent('myproperty:setRent', function(houseId, pricePerDay)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Houses[houseId] then return end
    
    if Houses[houseId].owner == Player.PlayerData.citizenid then
        MySQL.update('UPDATE my_properties SET is_rentable = 1, rent_price_per_day = ? WHERE id = ?', {pricePerDay, houseId})
        Houses[houseId].is_rentable = 1
        Houses[houseId].rent_price_per_day = pricePerDay
        TriggerClientEvent('myproperty:syncSingleHouse', -1, houseId, Houses[houseId])
        TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'ตั้งเปิดเช่าบ้านเรียบร้อย ราคา: $'..pricePerDay..' / วัน' } })
    end
end)

RegisterNetEvent('myproperty:rentHouse', function(houseId, days)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Houses[houseId] then return end
    
    if Houses[houseId].is_rentable == 1 and not Houses[houseId].renter then
        local pricePerDay = Houses[houseId].rent_price_per_day or 0
        local totalCost = pricePerDay * days
        
        if Player.PlayerData.money['bank'] >= totalCost then
            Player.Functions.RemoveMoney('bank', totalCost, 'rent-property')
            
            -- โอนเงินให้เจ้าของบ้าน
            local ownerCid = Houses[houseId].owner
            local OwnerPlayer = QBCore.Functions.GetPlayerByCitizenId(ownerCid)
            if OwnerPlayer then
                OwnerPlayer.Functions.AddMoney('bank', totalCost, 'property-rent-income')
                TriggerClientEvent('chat:addMessage', OwnerPlayer.PlayerData.source, { args = { '^2System', 'มีผู้เช่าบ้านของคุณ ได้รับเงินเข้าธนาคาร $'..totalCost } })
            else
                local result = MySQL.query.await('SELECT money FROM players WHERE citizenid = ?', {ownerCid})
                if result and result[1] then
                    local money = json.decode(result[1].money)
                    money.bank = money.bank + totalCost
                    MySQL.update('UPDATE players SET money = ? WHERE citizenid = ?', {json.encode(money), ownerCid})
                end
            end
            
            local expireTime = os.time() + (days * 86400)
            MySQL.update('UPDATE my_properties SET is_rentable = 0, renter = ?, rent_expire = ? WHERE id = ?', {Player.PlayerData.citizenid, expireTime, houseId})
            
            Houses[houseId].is_rentable = 0
            Houses[houseId].renter = Player.PlayerData.citizenid
            Houses[houseId].rent_expire = expireTime
            
            TriggerClientEvent('myproperty:syncSingleHouse', -1, houseId, Houses[houseId])
            TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'เช่าบ้านสำเร็จ! สัญญาเช่าจำนวน '..days..' วัน (หักเงินธนาคาร $'..totalCost..')' } })
        else
            TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'เงินในธนาคารไม่พอ (ต้องการ $'..totalCost..')' } })
        end
    else
        TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'บ้านหลังนี้ไม่ได้เปิดให้เช่า หรือมีคนเช่าไปแล้ว!' } })
    end
end)

RegisterNetEvent('myproperty:payRent', function(houseId, extendDays)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Houses[houseId] then return end
    
    if Houses[houseId].renter == Player.PlayerData.citizenid then
        local pricePerDay = Houses[houseId].rent_price_per_day or 0
        local totalCost = pricePerDay * extendDays
        
        if Player.PlayerData.money['bank'] >= totalCost then
            Player.Functions.RemoveMoney('bank', totalCost, 'extend-rent-property')
            
            -- โอนเงินให้เจ้าของบ้าน
            local ownerCid = Houses[houseId].owner
            local OwnerPlayer = QBCore.Functions.GetPlayerByCitizenId(ownerCid)
            if OwnerPlayer then
                OwnerPlayer.Functions.AddMoney('bank', totalCost, 'property-rent-income')
            else
                local result = MySQL.query.await('SELECT money FROM players WHERE citizenid = ?', {ownerCid})
                if result and result[1] then
                    local money = json.decode(result[1].money)
                    money.bank = money.bank + totalCost
                    MySQL.update('UPDATE players SET money = ? WHERE citizenid = ?', {json.encode(money), ownerCid})
                end
            end
            
            local newExpire = Houses[houseId].rent_expire + (extendDays * 86400)
            MySQL.update('UPDATE my_properties SET rent_expire = ? WHERE id = ?', {newExpire, houseId})
            
            Houses[houseId].rent_expire = newExpire
            TriggerClientEvent('myproperty:syncSingleHouse', -1, houseId, Houses[houseId])
            TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'ต่อสัญญาเช่า '..extendDays..' วันสำเร็จ! (หักเงินธนาคาร $'..totalCost..')' } })
        else
            TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'เงินในธนาคารไม่พอต่อสัญญา (ต้องการ $'..totalCost..')' } })
        end
    else
        TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'คุณไม่ใช่ผู้เช่าบ้านหลังนี้!' } })
    end
end)

-- ★ ลูปเช็คบ้านเช่าหมดอายุ (ตรวจทุกๆ 10 นาที)
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(10 * 60 * 1000) 
        local currentTime = os.time()
        for id, house in pairs(Houses) do
            if house.renter and house.rent_expire and house.rent_expire > 0 then
                if currentTime > house.rent_expire then
                    MySQL.update('UPDATE my_properties SET renter = NULL, rent_expire = 0, is_rentable = 1 WHERE id = ?', {id})
                    Houses[id].renter = nil
                    Houses[id].rent_expire = 0
                    Houses[id].is_rentable = 1
                    TriggerClientEvent('myproperty:syncSingleHouse', -1, id, Houses[id])
                end
            end
        end
    end
end)

-- ==========================================
-- [CANCEL RENT] ระบบยกเลิกการเช่า / เตะผู้เช่า
-- ==========================================
RegisterNetEvent('myproperty:cancelRent', function(houseId, isOwner)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Houses[houseId] then return end
    
    local cid = Player.PlayerData.citizenid
    local house = Houses[houseId]
    
    if isOwner then
        -- ★ กรณี Owner เป็นคนกดยกเลิก
        if house.owner == cid then
            if house.renter then
                -- มีคนเช่าอยู่ -> เตะออก และปิดรับคนเช่า
                MySQL.update('UPDATE my_properties SET renter = NULL, rent_expire = 0, is_rentable = 0 WHERE id = ?', {houseId})
                house.renter = nil
                house.rent_expire = 0
                house.is_rentable = 0 
                TriggerClientEvent('myproperty:syncSingleHouse', -1, houseId, house)
                TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'ยกเลิกสัญญาและเตะผู้เช่าออกเรียบร้อยแล้ว!' } })
            else
                -- ไม่มีคนเช่า แต่อยากยกเลิกป้ายประกาศ
                MySQL.update('UPDATE my_properties SET is_rentable = 0 WHERE id = ?', {houseId})
                house.is_rentable = 0
                TriggerClientEvent('myproperty:syncSingleHouse', -1, houseId, house)
                TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'ยกเลิกการประกาศให้เช่าบ้านเรียบร้อยแล้ว!' } })
            end
        else
            TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'คุณไม่ใช่เจ้าของบ้านหลังนี้!' } })
        end
    else
        -- ★ กรณี ผู้เช่า เป็นคนกดยกเลิก (คืนบ้าน)
        if house.renter == cid then
            -- คืนบ้าน -> ปล่อยว่าง และเปิดรับคนเช่าใหม่ต่อทันที
            MySQL.update('UPDATE my_properties SET renter = NULL, rent_expire = 0, is_rentable = 1 WHERE id = ?', {houseId})
            house.renter = nil
            house.rent_expire = 0
            house.is_rentable = 1 
            TriggerClientEvent('myproperty:syncSingleHouse', -1, houseId, house)
            TriggerClientEvent('chat:addMessage', src, { args = { '^2System', 'คุณได้ยกเลิกสัญญาเช่าและคืนบ้านหลังนี้แล้ว!' } })
            
            -- วาร์ปผู้เล่นออกมาหน้าบ้านถ้าอยู่ในบ้าน
            local outCoords = house.doors[1].entrance
            if outCoords then 
                TriggerClientEvent('myproperty:teleport', src, outCoords) 
                SetPlayerRoutingBucket(src, house.parent_dimension)
                TriggerClientEvent('myproperty:syncDimension', src, house.parent_dimension)
            end
        else
            TriggerClientEvent('chat:addMessage', src, { args = { '^1System', 'คุณไม่ได้เช่าบ้านหลังนี้อยู่!' } })
        end
    end
end)
