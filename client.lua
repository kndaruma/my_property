local QBCore = exports['qb-core']:GetCoreObject()
local PlayerData = {}
local Houses = {}
local myDimension = 0
local myHouseId = nil
local myFurniture = {} 
local spawnedProps = {} 

local selectedFurniture = nil
local selectedCategory = nil 
local selectedDoor = nil
local clipboardCoords, clipboardRot = nil, nil
local deletePropertyId = nil 
local isEnteringPlacement = false
local isMenuOpen = false
local isModelLoading = false
local isKnocking = false

local pendingKnocks = {}
local selectedKnock = nil
local selectedKnockIndex = nil
local playersToInvite = {}
local pendingInvites = {}

-- ==========================================
-- [1] UI MENUS CREATION (RageUI)
-- ==========================================
local mainMenu = RageUI.CreateMenu("Manage Property", "Manage your property", 1350, 50)
local doorMenu = RageUI.CreateSubMenu(mainMenu, "Manage Doors", "Manage multiple entrances")
local doorActionMenu = RageUI.CreateSubMenu(doorMenu, "Door Actions", "Modify selected door")
local furnitureMenu = RageUI.CreateSubMenu(mainMenu, "Furniture", "Manage placed furniture")
local keyMenu = RageUI.CreateSubMenu(mainMenu, "Manage Keys", "Manage property access")
local keyListMenu = RageUI.CreateSubMenu(keyMenu, "Keyholders", "List of keyholders")
local buyFurnitureMenu = RageUI.CreateSubMenu(mainMenu, "Furniture Shop", "Select a category")
local buyCategoryMenu = RageUI.CreateSubMenu(buyFurnitureMenu, "Items", "Purchase furniture items")

local objectMenu = RageUI.CreateSubMenu(furnitureMenu, "Manage Object", "Actions for selected object", 1350, 50)
local flattenRotMenu = RageUI.CreateSubMenu(objectMenu, "Flatten Rotation", "Reset axis to 0")
local sharpRotMenu = RageUI.CreateSubMenu(objectMenu, "Sharp Rotation", "Rotate axis by 45 degrees")

local previewMenu = RageUI.CreateSubMenu(buyCategoryMenu, "Preview Item", "Manage new object", 1350, 50)
local pFlattenRotMenu = RageUI.CreateSubMenu(previewMenu, "Flatten Rotation", "Reset axis to 0")
local pSharpRotMenu = RageUI.CreateSubMenu(previewMenu, "Sharp Rotation", "Rotate axis by 45 degrees")

local deleteMenu = RageUI.CreateMenu("Delete Property", "Confirm property deletion")

local knockMenu = RageUI.CreateMenu("Knock Knock", "Someone is knocking", 1350, 50)
local knockActionMenu = RageUI.CreateSubMenu(knockMenu, "Action", "Manage knock")
local inviteListMenu = RageUI.CreateSubMenu(doorActionMenu, "Invite Players", "Players outside")
local inviteRequestMenu = RageUI.CreateMenu("House Invite", "You have a house invite", 1350, 50)

-- ==========================================
-- [2] DATA INITIALIZATION
-- ==========================================
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() PlayerData = QBCore.Functions.GetPlayerData() end)
RegisterNetEvent('QBCore:Player:SetPlayerData', function(val) PlayerData = val end)

Citizen.CreateThread(function() 
    Citizen.Wait(1000) 
    PlayerData = QBCore.Functions.GetPlayerData() 
    TriggerServerEvent('myproperty:requestSync') 
end)

local function KeyboardInput(TextEntry, ExampleText, MaxStringLength)
    AddTextEntry('FMMC_KEY_TIP1', TextEntry) 
    DisplayOnscreenKeyboard(1, "FMMC_KEY_TIP1", "", ExampleText, "", "", "", MaxStringLength)
    while UpdateOnscreenKeyboard() ~= 1 and UpdateOnscreenKeyboard() ~= 2 do Citizen.Wait(0) end
    if UpdateOnscreenKeyboard() ~= 2 then return GetOnscreenKeyboardResult() else return nil end
end

local function HasKey()
    if not myHouseId or not Houses[myHouseId] or not PlayerData.citizenid then return false end
    local house = Houses[myHouseId]
    if house.owner == PlayerData.citizenid then return true end
    if house.keys and house.keys[PlayerData.citizenid] then return true end
    if QBCore.Functions.GetPlayerData().metadata["isadmin"] then return true end 
    local keyCount = 0
    for k,v in pairs(house.keys or {}) do keyCount = keyCount + 1 end 
    if keyCount == 0 and QBCore.Functions.GetPlayerData().metadata["isadmin"] then
        TriggerServerEvent('myproperty:autoClaimOldHouse', myHouseId) return true 
    end
    return false 
end

local function isDynamicProp(modelName)
    local name = string.lower(modelName)
    local keywords = {"door", "gate", "vault", "safe", "barrier", "shutter", "window", "turnstile", "cell", "cage"}
    for _, kw in ipairs(keywords) do if string.find(name, kw) then return true end end return false
end

local function GetItemPrice(model)
    for _, cat in ipairs(Config.FurnitureShop) do for _, item in ipairs(cat.items) do if item.model == model then return item.price end end end return 0
end

local function GetPlacedFurnitureCount()
    local count = 0 for _, f in ipairs(myFurniture) do if not f.isPendingBuy then count = count + 1 end end return count
end

-- ==========================================
-- [3] FURNITURE RENDERING LOGIC
-- ==========================================
local function ClearHouseFurniture()
    for id, prop in pairs(spawnedProps) do if DoesEntityExist(prop) then DeleteEntity(prop) end end
    spawnedProps = {} myFurniture = {}
end

local function SpawnHouseFurniture(houseId)
    ClearHouseFurniture()
    if not Houses[houseId] or not Houses[houseId].furniture then return end
    myFurniture = Houses[houseId].furniture
    for _, f in ipairs(myFurniture) do
        local fDim = f.dimension or Houses[houseId].dimension
        if fDim == myDimension then
            local hash = GetHashKey(f.model) 
            RequestModel(hash) 
            while not HasModelLoaded(hash) do Citizen.Wait(0) end
            local prop = CreateObject(hash, f.coords.x, f.coords.y, f.coords.z, false, false, false)
            SetEntityCoordsNoOffset(prop, f.coords.x, f.coords.y, f.coords.z, false, false, false)
            SetEntityRotation(prop, f.rot.x, f.rot.y, f.rot.z, 2, true)
            if isDynamicProp(f.model) then FreezeEntityPosition(prop, false) else FreezeEntityPosition(prop, true) end
            SetEntityCollision(prop, not f.noCollision, not f.noCollision)
            spawnedProps[f.id] = prop
        end
    end
end

RegisterNetEvent('myproperty:syncHouses')
AddEventHandler('myproperty:syncHouses', function(serverHouses) 
    Houses = serverHouses 
    if myHouseId and Houses[myHouseId] then myFurniture = Houses[myHouseId].furniture or {} end
end)

-- ==========================================
-- [4] DIMENSION & TELEPORTATION
-- ==========================================
RegisterNetEvent('myproperty:syncDimension')
AddEventHandler('myproperty:syncDimension', function(dim) 
    myDimension = dim 
    myHouseId = nil
    for _, house in pairs(Houses) do
        if house.dimension == dim then myHouseId = house.id break end
        if house.lifts then 
            for _, f in ipairs(house.lifts) do if f.dim == dim then myHouseId = house.id break end end 
        end
    end
    if dim ~= 0 then _G.pendingFurnitureSpawn = true else _G.pendingFurnitureClear = true end
end)

RegisterNetEvent('myproperty:teleport')
AddEventHandler('myproperty:teleport', function(coords)
    local ped = PlayerPedId() 
    DoScreenFadeOut(500) 
    Citizen.Wait(500)
    
    if _G.pendingFurnitureClear then ClearHouseFurniture() _G.pendingFurnitureClear = false end
    
    if _G.pendingFurnitureSpawn then
        -- ล็อคความสูงที่ 0.5 ตามคำขอ
        SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z + 0.5, false, false, false)
        FreezeEntityPosition(ped, true)
        _G.isFrozenInProperty = true
        _G.pendingFurnitureSpawn = false
        if myHouseId then SpawnHouseFurniture(myHouseId) end
    else
        SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
    end
    Citizen.Wait(500) DoScreenFadeIn(500)
end)

RegisterNetEvent('myproperty:forceEnter')
AddEventHandler('myproperty:forceEnter', function(houseId, doorName)
    TriggerServerEvent('myproperty:enterHouse', houseId, doorName)
end)

-- ==========================================
-- [5] SINGLE FURNITURE SYNC & APPLY ROTATION
-- ==========================================
RegisterNetEvent('myproperty:syncSingleFurniture')
AddEventHandler('myproperty:syncSingleFurniture', function(houseId, furniData, action)
    if not Houses[houseId] then Houses[houseId] = { furniture = {} } end
    if not Houses[houseId].furniture then Houses[houseId].furniture = {} end
    
    if action == "add" then
        table.insert(Houses[houseId].furniture, furniData)
        if myHouseId == houseId then
            myFurniture = Houses[houseId].furniture 
            local fDim = furniData.dimension or Houses[houseId].dimension
            if fDim == myDimension then
                local hash = GetHashKey(furniData.model) 
                RequestModel(hash) while not HasModelLoaded(hash) do Citizen.Wait(0) end
                local prop = CreateObject(hash, furniData.coords.x, furniData.coords.y, furniData.coords.z, false, false, false)
                SetEntityCoordsNoOffset(prop, furniData.coords.x, furniData.coords.y, furniData.coords.z, false, false, false)
                SetEntityRotation(prop, furniData.rot.x, furniData.rot.y, furniData.rot.z, 2, true)
                if isDynamicProp(furniData.model) then FreezeEntityPosition(prop, false) else FreezeEntityPosition(prop, true) end
                SetEntityCollision(prop, not furniData.noCollision, not furniData.noCollision)
                spawnedProps[furniData.id] = prop
            end
        end
    elseif action == "update" then
        for i, f in ipairs(Houses[houseId].furniture) do
            if tostring(f.id) == tostring(furniData.id) then 
                Houses[houseId].furniture[i].coords = furniData.coords 
                Houses[houseId].furniture[i].rot = furniData.rot 
                Houses[houseId].furniture[i].noCollision = furniData.noCollision break 
            end
        end
        if myHouseId == houseId and spawnedProps[furniData.id] then
            local prop = spawnedProps[furniData.id] 
            SetEntityCoordsNoOffset(prop, furniData.coords.x, furniData.coords.y, furniData.coords.z, false, false, false)
            SetEntityRotation(prop, furniData.rot.x, furniData.rot.y, furniData.rot.z, 2, true) 
            SetEntityCollision(prop, not furniData.noCollision, not furniData.noCollision) 
            SetEntityAlpha(prop, 255, false) 
            if isDynamicProp(furniData.model) then FreezeEntityPosition(prop, false) else FreezeEntityPosition(prop, true) end
        end
    elseif action == "remove" then
        for i, f in ipairs(Houses[houseId].furniture) do 
            if tostring(f.id) == tostring(furniData.id) then table.remove(Houses[houseId].furniture, i) break end 
        end
        if myHouseId == houseId and spawnedProps[furniData.id] then 
            DeleteEntity(spawnedProps[furniData.id]) spawnedProps[furniData.id] = nil 
        end
    end
end)

-- ★ แก้ไขฟังก์ชัน Update องศาให้ใช้ค่าเดียวเสมอ แก้บัคการดีดกลับของแกน
local function ApplyRotationChange(newRot)
    if not selectedFurniture then return end
    local prop = selectedFurniture.prop or spawnedProps[selectedFurniture.id]
    
    selectedFurniture.rot = newRot 
    
    if prop and DoesEntityExist(prop) then 
        SetEntityCoordsNoOffset(prop, selectedFurniture.coords.x, selectedFurniture.coords.y, selectedFurniture.coords.z, false, false, false)
        SetEntityRotation(prop, newRot.x, newRot.y, newRot.z, 2, true) 
    end
    
    -- เซฟลงฐานข้อมูลเฉพาะของที่ไม่ได้อยู่ในสถานะจัดวาง (Pending Move/Buy)
    if not selectedFurniture.isPendingBuy and not selectedFurniture.isPendingMove then 
        TriggerServerEvent('myproperty:updateFurniture', myHouseId, selectedFurniture.id, selectedFurniture.coords, newRot, selectedFurniture.noCollision) 
    end
end

-- ==========================================
-- [6] RAGE UI MAIN MENU & SUBMENUS
-- ==========================================
RegisterNetEvent('myproperty:openInviteList', function(players, houseId, doorName)
    playersToInvite = players
    openPropertyMenu("inviteList")
end)

function openPropertyMenu(startPage)
    if isMenuOpen then return end
    isMenuOpen = true
    isModelLoading = false 

    if startPage == "buy" then RageUI.Visible(buyFurnitureMenu, true)
    elseif startPage == "object" then RageUI.Visible(objectMenu, true)
    elseif startPage == "preview" then RageUI.Visible(previewMenu, true)
    elseif startPage == "delete" then RageUI.Visible(deleteMenu, true)
    elseif startPage == "knock" then RageUI.Visible(knockMenu, true)
    elseif startPage == "inviteList" then RageUI.Visible(inviteListMenu, true)
    elseif startPage == "inviteRequest" then RageUI.Visible(inviteRequestMenu, true)
    else RageUI.Visible(mainMenu, true) end

    local sortedFurniList = {} 
    local lastMenuState = nil 
    isEnteringPlacement = false

    Citizen.CreateThread(function()
        while isMenuOpen do
            Citizen.Wait(0)
            local currentHouseSlots = Houses[myHouseId] and Houses[myHouseId].maxSlots or 100
            local currentMenuState = "none"
            
            if RageUI.Visible(mainMenu) then currentMenuState = "mainMenu"
            elseif RageUI.Visible(doorMenu) then currentMenuState = "doorMenu"
            elseif RageUI.Visible(doorActionMenu) then currentMenuState = "doorActionMenu"
            elseif RageUI.Visible(furnitureMenu) then currentMenuState = "furnitureMenu"
            elseif RageUI.Visible(keyMenu) then currentMenuState = "keyMenu"
            elseif RageUI.Visible(keyListMenu) then currentMenuState = "keyListMenu"
            elseif RageUI.Visible(buyFurnitureMenu) then currentMenuState = "buyFurnitureMenu"
            elseif RageUI.Visible(buyCategoryMenu) then currentMenuState = "buyCategoryMenu"
            elseif RageUI.Visible(objectMenu) then currentMenuState = "objectMenu"
            elseif RageUI.Visible(flattenRotMenu) then currentMenuState = "flattenRotMenu"
            elseif RageUI.Visible(sharpRotMenu) then currentMenuState = "sharpRotMenu"
            elseif RageUI.Visible(previewMenu) then currentMenuState = "previewMenu"
            elseif RageUI.Visible(pFlattenRotMenu) then currentMenuState = "pFlattenRotMenu"
            elseif RageUI.Visible(pSharpRotMenu) then currentMenuState = "pSharpRotMenu"
            elseif RageUI.Visible(deleteMenu) then currentMenuState = "deleteMenu" 
            elseif RageUI.Visible(knockMenu) then currentMenuState = "knockMenu"
            elseif RageUI.Visible(knockActionMenu) then currentMenuState = "knockActionMenu"
            elseif RageUI.Visible(inviteListMenu) then currentMenuState = "inviteListMenu"
            elseif RageUI.Visible(inviteRequestMenu) then currentMenuState = "inviteRequestMenu" end

            if lastMenuState == "previewMenu" and currentMenuState ~= "previewMenu" and currentMenuState ~= "pFlattenRotMenu" and currentMenuState ~= "pSharpRotMenu" and not isEnteringPlacement then
                if selectedFurniture and selectedFurniture.isPendingBuy then
                    if selectedFurniture.prop and DoesEntityExist(selectedFurniture.prop) then DeleteEntity(selectedFurniture.prop) end
                    for i = #myFurniture, 1, -1 do if tostring(myFurniture[i].id) == tostring(selectedFurniture.id) then table.remove(myFurniture, i) break end end
                    selectedFurniture = nil
                end
            end

            if lastMenuState == "objectMenu" and currentMenuState ~= "objectMenu" and currentMenuState ~= "flattenRotMenu" and currentMenuState ~= "sharpRotMenu" and not isEnteringPlacement then
                if selectedFurniture and selectedFurniture.isPendingMove then
                    local prop = spawnedProps[selectedFurniture.id] 
                    if prop and DoesEntityExist(prop) then 
                        SetEntityCoordsNoOffset(prop, selectedFurniture.originalCoords.x, selectedFurniture.originalCoords.y, selectedFurniture.originalCoords.z, false, false, false)
                        SetEntityRotation(prop, selectedFurniture.originalRot.x, selectedFurniture.originalRot.y, selectedFurniture.originalRot.z, 2, true)
                        SetEntityAlpha(prop, 255, false) 
                    end
                    selectedFurniture.coords = selectedFurniture.originalCoords
                    selectedFurniture.rot = selectedFurniture.originalRot
                    selectedFurniture.isPendingMove = nil
                    selectedFurniture = nil
                elseif selectedFurniture and not selectedFurniture.isPendingBuy then
                    selectedFurniture = nil
                end
            end

            if currentMenuState == "furnitureMenu" and lastMenuState ~= "furnitureMenu" then
                local pedCoords = GetEntityCoords(PlayerPedId()) 
                sortedFurniList = {}
                for _, furni in ipairs(myFurniture) do
                    local fDim = furni.dimension or Houses[myHouseId].dimension
                    if not furni.isPendingBuy and fDim == myDimension then
                        furni.distance = #(pedCoords - vector3(furni.coords.x, furni.coords.y, furni.coords.z)) table.insert(sortedFurniList, furni)
                    end
                end
                table.sort(sortedFurniList, function(a, b) return a.distance < b.distance end)
            end
            lastMenuState = currentMenuState

            -- ====================
            -- MAIN MENU
            -- ====================
            RageUI.IsVisible(mainMenu, true, true, true, function()
                if myHouseId then RageUI.Separator("--- Property ID: " .. myHouseId .. " ---") end
                RageUI.ButtonWithStyle("Manage Doors", "Set multiple entrances/exits", { RightLabel = "→" }, true, function() end, doorMenu)
                RageUI.ButtonWithStyle("Manage Furniture", "Placed: " .. GetPlacedFurnitureCount() .. " / " .. currentHouseSlots, { RightLabel = "→" }, true, function() end, furnitureMenu)
                RageUI.ButtonWithStyle("Manage Keys", "Manage property access keys", { RightLabel = "→" }, true, function() end, keyMenu)
                RageUI.ButtonWithStyle("Buy Furniture", "Purchase new furniture", { RightLabel = "→" }, true, function() end, buyFurnitureMenu)
                RageUI.ButtonWithStyle("Close Menu", "", { RightLabel = "→" }, true, function(_, _, Selected) if Selected then RageUI.CloseAll() end end)
            end, function() end)

            -- ====================
            -- DOOR MENU
            -- ====================
            RageUI.IsVisible(doorMenu, true, true, true, function()
                RageUI.ButtonWithStyle("Add New Door", "Create a new entrance/exit pair", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                    if Selected then
                        Citizen.CreateThread(function()
                            Citizen.Wait(150)
                            local name = KeyboardInput("Door Name (e.g. Balcony):", "", 20)
                            if name and name ~= "" then 
                                TriggerServerEvent('myproperty:addDoor', myHouseId, name, GetEntityCoords(PlayerPedId())) 
                            else TriggerEvent('chat:addMessage', { args = { '^1System', 'ยกเลิกการสร้างประตู' } }) end
                        end)
                    end
                end)
                if Houses[myHouseId] and Houses[myHouseId].doors then
                    for _, door in ipairs(Houses[myHouseId].doors) do
                        RageUI.ButtonWithStyle(door.name, "Manage this door", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                            if Selected then selectedDoor = door end
                        end, doorActionMenu)
                    end
                end
            end, function() end)

            RageUI.IsVisible(doorActionMenu, true, true, true, function()
                if selectedDoor then
                    RageUI.Separator("Door: " .. selectedDoor.name)
                    RageUI.ButtonWithStyle("Invite Player", "Invite players outside the door", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                        if Selected then TriggerServerEvent('myproperty:requestPlayersOutside', myHouseId, selectedDoor.name) end
                    end)
                    RageUI.ButtonWithStyle("Set Inside Exit Here", "Update exit marker to current position", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                        if Selected then TriggerServerEvent('myproperty:setExitCoords', myHouseId, selectedDoor.name, GetEntityCoords(PlayerPedId())) RageUI.GoBack() end
                    end)
                    RageUI.ButtonWithStyle("How to set Outside Entrance?", "Info on setting exterior point", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                        if Selected then TriggerEvent('chat:addMessage', { args = { '^3System', 'เดินไปยืนหน้าบ้านด้านนอกแล้วพิมพ์: ^2/setentrance ' .. myHouseId .. ' ' .. selectedDoor.name } }) end
                    end)
                    if selectedDoor.name ~= "Main" then
                        RageUI.ButtonWithStyle("Delete Door", "Remove this door permanently", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                            if Selected then TriggerServerEvent('myproperty:deleteDoor', myHouseId, selectedDoor.name) RageUI.GoBack() end
                        end)
                    end
                end
            end, function() end)

            RageUI.IsVisible(inviteListMenu, true, true, true, function()
                if #playersToInvite == 0 then
                    RageUI.Separator("No players outside")
                else
                    for _, p in ipairs(playersToInvite) do
                        RageUI.ButtonWithStyle(p.name, "Send house invite", { RightLabel = "Invite →" }, true, function(Hovered, Active, Selected)
                            if Selected then
                                TriggerServerEvent('myproperty:sendInvite', p.src, myHouseId, selectedDoor.name)
                                RageUI.GoBack()
                            end
                        end)
                    end
                end
            end, function() end)

            -- ====================
            -- KEY MENU
            -- ====================
            RageUI.IsVisible(keyMenu, true, true, true, function()
                RageUI.ButtonWithStyle("Give Key", "Give key to nearest player", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                    if Selected then
                        local closestPlayer, closestDistance = QBCore.Functions.GetClosestPlayer()
                        if closestPlayer ~= -1 and closestDistance < 3.0 then TriggerServerEvent('myproperty:giveKey', myHouseId, GetPlayerServerId(closestPlayer)) 
                        else TriggerEvent('chat:addMessage', { args = { '^1System', 'ไม่มีผู้เล่นอยู่ใกล้ๆ' } }) end
                    end
                end)
                RageUI.ButtonWithStyle("Delete Keys", "Revoke property keys", { RightLabel = "→" }, true, function() end, keyListMenu)
            end, function() end)

            RageUI.IsVisible(keyListMenu, true, true, true, function()
                local keys = (myHouseId and Houses[myHouseId]) and Houses[myHouseId].keys or {} 
                local hasKeys = false
                for cid, name in pairs(keys) do
                    hasKeys = true
                    RageUI.ButtonWithStyle(name, "CitizenID: " .. cid, { RightLabel = "Revoke X" }, true, function(Hovered, Active, Selected)
                        if Selected then TriggerServerEvent('myproperty:removeKey', myHouseId, cid, name) RageUI.GoBack() end
                    end)
                end
                if not hasKeys then RageUI.Separator("No keyholders found") end
            end, function() end)

            -- ====================
            -- FURNITURE SHOP
            -- ====================
            RageUI.IsVisible(buyFurnitureMenu, true, true, true, function()
                for i, cat in ipairs(Config.FurnitureShop) do RageUI.ButtonWithStyle(cat.category, "Browse category", { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then selectedCategory = cat end end, buyCategoryMenu) end
            end, function() end)

            RageUI.IsVisible(buyCategoryMenu, true, true, true, function()
                if selectedCategory then
                    for i, item in ipairs(selectedCategory.items) do
                        RageUI.ButtonWithStyle(item.name, "Price: $" .. item.price, { RightLabel = "Preview →" }, true, function(Hovered, Active, Selected)
                            if Selected then
                                if isModelLoading then return end
                                if GetPlacedFurnitureCount() < currentHouseSlots then
                                    isModelLoading = true
                                    Citizen.CreateThread(function()
                                        local ped = PlayerPedId() 
                                        local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.0, 0.0) 
                                        local rot = vector3(0.0, 0.0, GetEntityHeading(ped)) 
                                        local hash = GetHashKey(item.model) RequestModel(hash) while not HasModelLoaded(hash) do Citizen.Wait(0) end
                                        local prop = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false) SetEntityRotation(prop, rot.x, rot.y, rot.z, 2, true) SetEntityAlpha(prop, 255, false) FreezeEntityPosition(prop, true)
                                        local newItem = { id = math.random(1000000, 9999999), name = item.name, model = item.model, price = item.price, coords = coords, rot = rot, prop = prop, noCollision = false, isPendingBuy = true, dimension = myDimension }
                                        table.insert(myFurniture, newItem) selectedFurniture = newItem 
                                        RageUI.Visible(buyCategoryMenu, false) RageUI.Visible(previewMenu, true) isModelLoading = false
                                    end)
                                else TriggerEvent('chat:addMessage', { args = { '^1System', 'จำนวนเฟอร์นิเจอร์ถึงขีดจำกัดแล้ว!' } }) end
                            end
                        end)
                    end
                end
            end, function() end)

            -- ====================
            -- MANAGE PLACED OBJECTS
            -- ====================
            RageUI.IsVisible(furnitureMenu, true, true, true, function()
                local placedCount = GetPlacedFurnitureCount() 
                RageUI.Separator("Slots Used: " .. placedCount .. " / " .. currentHouseSlots)
                
                for i = #sortedFurniList, 1, -1 do
                    local found = false
                    for _, mf in ipairs(myFurniture) do if tostring(mf.id) == tostring(sortedFurniList[i].id) then found = true break end end
                    if not found then table.remove(sortedFurniList, i) end
                end
                
                if #sortedFurniList == 0 then RageUI.Separator("No furniture placed in this floor") else
                    for _, furni in ipairs(sortedFurniList) do
                        local distText = string.format("%.1fm →", furni.distance)
                        RageUI.ButtonWithStyle(furni.name, "Model: " .. furni.model, { RightLabel = distText }, true, function(Hovered, Active, Selected) if Selected then selectedFurniture = furni end end, objectMenu)
                    end
                end
            end, function() end)

            RageUI.IsVisible(objectMenu, true, true, true, function()
                if selectedFurniture then
                    local title = "Manage: " .. selectedFurniture.name 
                    if selectedFurniture.isPendingMove then title = "[MOVING] " .. title end
                    RageUI.Separator(title)
                    
                    RageUI.ButtonWithStyle("1 - Move (Placement Mode)", "Enter placement mode", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                        if Selected then
                            Citizen.CreateThread(function()
                                local itemToMove = selectedFurniture 
                                local propEntity = selectedFurniture.prop or spawnedProps[itemToMove.id]
                                if not itemToMove.isPendingMove then 
                                    itemToMove.originalCoords = itemToMove.coords 
                                    itemToMove.originalRot = itemToMove.rot 
                                    itemToMove.isPendingMove = true 
                                end
                                if propEntity and DoesEntityExist(propEntity) then SetEntityCollision(propEntity, not itemToMove.noCollision, not itemToMove.noCollision) end
                                isEnteringPlacement = true RageUI.CloseAll() Citizen.Wait(100)
                                TriggerEvent('myproperty:startPlacement', { item = itemToMove, mode = "move", prop = propEntity }) 
                            end)
                        end
                    end)
                    
                    if not selectedFurniture.isPendingMove then
                        RageUI.ButtonWithStyle("2 - Duplicate", "Duplicate this object", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                            if Selected then
                                if isModelLoading then return end
                                if GetPlacedFurnitureCount() < currentHouseSlots then
                                    isModelLoading = true
                                    Citizen.CreateThread(function()
                                        local hash = GetHashKey(selectedFurniture.model) RequestModel(hash) while not HasModelLoaded(hash) do Citizen.Wait(0) end
                                        local prop = CreateObject(hash, selectedFurniture.coords.x, selectedFurniture.coords.y, selectedFurniture.coords.z, false, false, false) SetEntityRotation(prop, selectedFurniture.rot.x, selectedFurniture.rot.y, selectedFurniture.rot.z, 2, true) FreezeEntityPosition(prop, true)
                                        local newItem = { id = math.random(1000000, 9999999), name = selectedFurniture.name, model = selectedFurniture.model, price = GetItemPrice(selectedFurniture.model), coords = selectedFurniture.coords, rot = selectedFurniture.rot, prop = prop, noCollision = selectedFurniture.noCollision, isPendingBuy = true, dimension = myDimension }
                                        table.insert(myFurniture, newItem) selectedFurniture = newItem
                                        RageUI.Visible(objectMenu, false) RageUI.Visible(previewMenu, true) isModelLoading = false
                                    end)
                                else TriggerEvent('chat:addMessage', { args = { '^1System', 'จำนวนเฟอร์นิเจอร์ถึงขีดจำกัดแล้ว!' } }) end
                            end
                        end)
                    end
                    
                    RageUI.ButtonWithStyle("3 - Copy Position", nil, { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then clipboardCoords = selectedFurniture.coords TriggerEvent('chat:addMessage', { args = { '^2System', 'คัดลอกพิกัดแล้ว!' } }) end end)
                    RageUI.ButtonWithStyle("4 - Paste Position", nil, { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                        if Selected and clipboardCoords then 
                            selectedFurniture.coords = clipboardCoords 
                            local prop = selectedFurniture.prop or spawnedProps[selectedFurniture.id]
                            if prop and DoesEntityExist(prop) then SetEntityCoordsNoOffset(prop, clipboardCoords.x, clipboardCoords.y, clipboardCoords.z, false, false, false) end
                            if not selectedFurniture.isPendingMove and not selectedFurniture.isPendingBuy then TriggerServerEvent('myproperty:updateFurniture', myHouseId, selectedFurniture.id, clipboardCoords, selectedFurniture.rot, selectedFurniture.noCollision) end
                        end
                    end)
                    RageUI.ButtonWithStyle("5 - Copy Rotation", nil, { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then clipboardRot = selectedFurniture.rot TriggerEvent('chat:addMessage', { args = { '^2System', 'คัดลอกองศาแล้ว!' } }) end end)
                    RageUI.ButtonWithStyle("  - Paste Rotation", nil, { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected and clipboardRot then ApplyRotationChange(clipboardRot) end end)
                    RageUI.ButtonWithStyle("6 - Flatten Rotation", nil, { RightLabel = "→" }, true, function() end, flattenRotMenu)
                    RageUI.ButtonWithStyle("7 - Sharp Rotation", nil, { RightLabel = "→" }, true, function() end, sharpRotMenu)
                    
                    local colState = selectedFurniture.noCollision and "ON" or "OFF"
                    RageUI.ButtonWithStyle("8 - No Collision: " .. colState, nil, { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                        if Selected then 
                            selectedFurniture.noCollision = not selectedFurniture.noCollision 
                            local prop = selectedFurniture.prop or spawnedProps[selectedFurniture.id]
                            if prop and DoesEntityExist(prop) then SetEntityCollision(prop, not selectedFurniture.noCollision, not selectedFurniture.noCollision) end
                            if not selectedFurniture.isPendingMove then TriggerServerEvent('myproperty:updateFurniture', myHouseId, selectedFurniture.id, selectedFurniture.coords, selectedFurniture.rot, selectedFurniture.noCollision) end 
                        end
                    end)
                    
                    if not selectedFurniture.isPendingMove then 
                        RageUI.ButtonWithStyle("9 - Sell", "Sell/Remove this object", { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then TriggerServerEvent('myproperty:deleteFurniture', myHouseId, selectedFurniture.id) RageUI.GoBack() end end) 
                    end

                    if selectedFurniture.isPendingMove then
                        RageUI.Separator("-----------------------")
                        RageUI.ButtonWithStyle("Confirm Move", "Save new position", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                            if Selected then Citizen.CreateThread(function() TriggerServerEvent('myproperty:updateFurniture', myHouseId, selectedFurniture.id, selectedFurniture.coords, selectedFurniture.rot, selectedFurniture.noCollision) selectedFurniture.isPendingMove = nil end) end
                        end)
                        RageUI.ButtonWithStyle("Cancel Move", "Revert to original position", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                            if Selected then 
                                Citizen.CreateThread(function()
                                    selectedFurniture.coords = selectedFurniture.originalCoords selectedFurniture.rot = selectedFurniture.originalRot 
                                    local prop = spawnedProps[selectedFurniture.id] 
                                    if prop and DoesEntityExist(prop) then SetEntityCoordsNoOffset(prop, selectedFurniture.coords.x, selectedFurniture.coords.y, selectedFurniture.coords.z, false, false, false) SetEntityRotation(prop, selectedFurniture.rot.x, selectedFurniture.rot.y, selectedFurniture.rot.z, 2, true) SetEntityAlpha(prop, 255, false) end
                                    selectedFurniture.isPendingMove = nil 
                                end)
                            end
                        end)
                    end
                end
            end, function() end)

            RageUI.IsVisible(previewMenu, true, true, true, function()
                if selectedFurniture then
                    RageUI.Separator("[NEW] " .. selectedFurniture.name)
                    RageUI.ButtonWithStyle("1 - Move (Placement Mode)", "Enter placement mode", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                        if Selected then
                            Citizen.CreateThread(function()
                                local itemToMove = selectedFurniture local propEntity = selectedFurniture.prop
                                if not itemToMove.isPendingMove then 
                                    itemToMove.originalCoords = itemToMove.coords 
                                    itemToMove.originalRot = itemToMove.rot 
                                    itemToMove.isPendingMove = true 
                                end
                                if propEntity and DoesEntityExist(propEntity) then SetEntityCollision(propEntity, not itemToMove.noCollision, not itemToMove.noCollision) end
                                isEnteringPlacement = true RageUI.CloseAll() Citizen.Wait(100)
                                TriggerEvent('myproperty:startPlacement', { item = itemToMove, mode = "move", prop = propEntity }) 
                            end)
                        end
                    end)
                    RageUI.ButtonWithStyle("2 - Copy Position", nil, { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then clipboardCoords = selectedFurniture.coords TriggerEvent('chat:addMessage', { args = { '^2System', 'คัดลอกพิกัดแล้ว!' } }) end end)
                    RageUI.ButtonWithStyle("3 - Paste Position", nil, { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                        if Selected and clipboardCoords then 
                            selectedFurniture.coords = clipboardCoords 
                            local prop = selectedFurniture.prop
                            if prop and DoesEntityExist(prop) then SetEntityCoordsNoOffset(prop, clipboardCoords.x, clipboardCoords.y, clipboardCoords.z, false, false, false) end
                        end
                    end)
                    RageUI.ButtonWithStyle("4 - Copy Rotation", nil, { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then clipboardRot = selectedFurniture.rot TriggerEvent('chat:addMessage', { args = { '^2System', 'คัดลอกองศาแล้ว!' } }) end end)
                    RageUI.ButtonWithStyle("  - Paste Rotation", nil, { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected and clipboardRot then ApplyRotationChange(clipboardRot) end end)
                    RageUI.ButtonWithStyle("5 - Flatten Rotation", nil, { RightLabel = "→" }, true, function() end, pFlattenRotMenu)
                    RageUI.ButtonWithStyle("6 - Sharp Rotation", nil, { RightLabel = "→" }, true, function() end, pSharpRotMenu)
                    local colState = selectedFurniture.noCollision and "ON" or "OFF"
                    RageUI.ButtonWithStyle("7 - No Collision: " .. colState, nil, { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                        if Selected then 
                            selectedFurniture.noCollision = not selectedFurniture.noCollision 
                            local prop = selectedFurniture.prop if prop then SetEntityCollision(prop, not selectedFurniture.noCollision, not selectedFurniture.noCollision) end 
                        end
                    end)
                    RageUI.Separator("-----------------------")
                    RageUI.ButtonWithStyle("Confirm Buy", "Pay $" .. selectedFurniture.price, { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                        if Selected then 
                            Citizen.CreateThread(function()
                                local newItem = { id = math.random(1000000, 9999999), name = selectedFurniture.name, model = selectedFurniture.model, price = selectedFurniture.price or 0, coords = selectedFurniture.coords, rot = selectedFurniture.rot, noCollision = selectedFurniture.noCollision, dimension = myDimension } 
                                if selectedFurniture.prop and DoesEntityExist(selectedFurniture.prop) then DeleteEntity(selectedFurniture.prop) end
                                for i = #myFurniture, 1, -1 do if tostring(myFurniture[i].id) == tostring(selectedFurniture.id) then table.remove(myFurniture, i) break end end 
                                TriggerServerEvent('myproperty:buyFurniture', myHouseId, newItem) selectedFurniture = nil RageUI.Visible(previewMenu, false) RageUI.Visible(buyCategoryMenu, true)
                            end)
                        end
                    end)
                    RageUI.ButtonWithStyle("Cancel Buy", "Cancel and discard model", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                        if Selected then 
                            Citizen.CreateThread(function()
                                if selectedFurniture.prop and DoesEntityExist(selectedFurniture.prop) then DeleteEntity(selectedFurniture.prop) end
                                for i = #myFurniture, 1, -1 do if tostring(myFurniture[i].id) == tostring(selectedFurniture.id) then table.remove(myFurniture, i) break end end 
                                selectedFurniture = nil RageUI.Visible(previewMenu, false) RageUI.Visible(buyCategoryMenu, true)
                            end)
                        end
                    end)
                end
            end, function() end)

            -- ====================
            -- ROTATION MENUS
            -- ====================
            RageUI.IsVisible(flattenRotMenu, true, true, true, function()
                if selectedFurniture then 
                    local rot = selectedFurniture.rot 
                    RageUI.ButtonWithStyle("X Axis (Pitch)", "Set X axis to 0", { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then ApplyRotationChange(vector3(0.0, rot.y, rot.z)) end end) 
                    RageUI.ButtonWithStyle("Y Axis (Roll)", "Set Y axis to 0", { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then ApplyRotationChange(vector3(rot.x, 0.0, rot.z)) end end) 
                    RageUI.ButtonWithStyle("Z Axis (Yaw)", "Set Z axis to 0", { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then ApplyRotationChange(vector3(rot.x, rot.y, 0.0)) end end) 
                    RageUI.ButtonWithStyle("All Axes (Reset)", "Reset all axes to 0", { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then ApplyRotationChange(vector3(0.0, 0.0, 0.0)) end end) 
                end
            end, function() end)
            RageUI.IsVisible(sharpRotMenu, true, true, true, function()
                if selectedFurniture then 
                    local rot = selectedFurniture.rot 
                    RageUI.ButtonWithStyle("X Axis (Pitch)", "Rotate X axis by +45 deg", { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then ApplyRotationChange(vector3((rot.x + 45.0) % 360.0, rot.y, rot.z)) end end) 
                    RageUI.ButtonWithStyle("Y Axis (Roll)", "Rotate Y axis by +45 deg", { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then ApplyRotationChange(vector3(rot.x, (rot.y + 45.0) % 360.0, rot.z)) end end) 
                    RageUI.ButtonWithStyle("Z Axis (Yaw)", "Rotate Z axis by +45 deg", { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then ApplyRotationChange(vector3(rot.x, rot.y, (rot.z + 45.0) % 360.0)) end end) 
                end
            end, function() end)
            RageUI.IsVisible(pFlattenRotMenu, true, true, true, function()
                if selectedFurniture then 
                    local rot = selectedFurniture.rot 
                    RageUI.ButtonWithStyle("X Axis (Pitch)", "Set X axis to 0", { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then ApplyRotationChange(vector3(0.0, rot.y, rot.z)) end end) 
                    RageUI.ButtonWithStyle("Y Axis (Roll)", "Set Y axis to 0", { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then ApplyRotationChange(vector3(rot.x, 0.0, rot.z)) end end) 
                    RageUI.ButtonWithStyle("Z Axis (Yaw)", "Set Z axis to 0", { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then ApplyRotationChange(vector3(rot.x, rot.y, 0.0)) end end) 
                    RageUI.ButtonWithStyle("All Axes (Reset)", "Reset all axes to 0", { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then ApplyRotationChange(vector3(0.0, 0.0, 0.0)) end end) 
                end
            end, function() end)
            RageUI.IsVisible(pSharpRotMenu, true, true, true, function()
                if selectedFurniture then 
                    local rot = selectedFurniture.rot 
                    RageUI.ButtonWithStyle("X Axis (Pitch)", "Rotate X axis by +45 deg", { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then ApplyRotationChange(vector3((rot.x + 45.0) % 360.0, rot.y, rot.z)) end end) 
                    RageUI.ButtonWithStyle("Y Axis (Roll)", "Rotate Y axis by +45 deg", { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then ApplyRotationChange(vector3(rot.x, (rot.y + 45.0) % 360.0, rot.z)) end end) 
                    RageUI.ButtonWithStyle("Z Axis (Yaw)", "Rotate Z axis by +45 deg", { RightLabel = "→" }, true, function(Hovered, Active, Selected) if Selected then ApplyRotationChange(vector3(rot.x, rot.y, (rot.z + 45.0) % 360.0)) end end) 
                end
            end, function() end)

            -- ====================
            -- DELETE MENU
            -- ====================
            RageUI.IsVisible(deleteMenu, true, true, true, function()
                RageUI.Separator("WARNING! Are you sure?")
                RageUI.ButtonWithStyle("Confirm Delete", "Delete property and all furniture", { RightLabel = "→" }, true, function(Hovered, Active, Selected) 
                    if Selected then TriggerServerEvent('myproperty:confirmDeleteProperty', deletePropertyId) RageUI.CloseAll() end 
                end)
                RageUI.ButtonWithStyle("Cancel", "Cancel", { RightLabel = "→" }, true, function(Hovered, Active, Selected) 
                    if Selected then RageUI.CloseAll() end 
                end)
            end, function() end)

            -- ====================
            -- KNOCK SYSTEM MENUS
            -- ====================
            RageUI.IsVisible(knockMenu, true, true, true, function()
                if #pendingKnocks == 0 then
                    RageUI.Separator("No active knocks")
                else
                    for i, knock in ipairs(pendingKnocks) do
                        RageUI.Separator("Door: " .. knock.doorName)
                        RageUI.ButtonWithStyle(knock.name, "Click to manage", { RightLabel = "Manage →" }, true, function(Hovered, Active, Selected)
                            if Selected then selectedKnock = knock selectedKnockIndex = i end
                        end, knockActionMenu)
                    end
                end
            end, function() end)

            RageUI.IsVisible(knockActionMenu, true, true, true, function()
                if selectedKnock then
                    RageUI.Separator(selectedKnock.name)
                    RageUI.ButtonWithStyle("Allow Entry", "Temporarily unlock door", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                        if Selected then
                            TriggerServerEvent('myproperty:answerKnock', selectedKnock.src, selectedKnock.houseId, selectedKnock.doorName, true)
                            table.remove(pendingKnocks, selectedKnockIndex) RageUI.GoBack()
                        end
                    end)
                    RageUI.ButtonWithStyle("Deny Entry", "Refuse entry", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                        if Selected then
                            TriggerServerEvent('myproperty:answerKnock', selectedKnock.src, selectedKnock.houseId, selectedKnock.doorName, false)
                            table.remove(pendingKnocks, selectedKnockIndex) RageUI.GoBack()
                        end
                    end)
                end
            end, function() end)

            -- ====================
            -- INVITE REQUEST MENU
            -- ====================
            RageUI.IsVisible(inviteRequestMenu, true, true, true, function()
                if #pendingInvites == 0 then
                    RageUI.Separator("No pending invites")
                else
                    for i, inv in ipairs(pendingInvites) do
                        RageUI.Separator("Invite from: " .. inv.name)
                        RageUI.ButtonWithStyle("Accept", "Warp inside immediately", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                            if Selected then
                                TriggerServerEvent('myproperty:enterHouse', inv.houseId, inv.doorName) 
                                table.remove(pendingInvites, i) RageUI.CloseAll()
                            end
                        end)
                        RageUI.ButtonWithStyle("Decline", "Reject the invite", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                            if Selected then table.remove(pendingInvites, i) RageUI.CloseAll() end
                        end)
                    end
                end
            end, function() end)

            if currentMenuState == "none" then
                if not isEnteringPlacement then
                    if selectedFurniture then
                        if selectedFurniture.isPendingBuy then
                            if selectedFurniture.prop and DoesEntityExist(selectedFurniture.prop) then DeleteEntity(selectedFurniture.prop) end
                            for i = #myFurniture, 1, -1 do if tostring(myFurniture[i].id) == tostring(selectedFurniture.id) then table.remove(myFurniture, i) break end end
                        elseif selectedFurniture.isPendingMove then
                            local prop = spawnedProps[selectedFurniture.id] 
                            if prop and DoesEntityExist(prop) then 
                                SetEntityCoordsNoOffset(prop, selectedFurniture.originalCoords.x, selectedFurniture.originalCoords.y, selectedFurniture.originalCoords.z, false, false, false)
                                SetEntityRotation(prop, selectedFurniture.originalRot.x, selectedFurniture.originalRot.y, selectedFurniture.originalRot.z, 2, true)
                                SetEntityAlpha(prop, 255, false) 
                            end 
                            selectedFurniture.coords = selectedFurniture.originalCoords
                            selectedFurniture.rot = selectedFurniture.originalRot
                        end
                    end
                    selectedFurniture = nil
                end
                isEnteringPlacement = false
                isMenuOpen = false
                break
            end
        end
    end)
end

-- ==========================================
-- [7] NEW EVENTS FOR KNOCK & INVITE
-- ==========================================
RegisterNetEvent('myproperty:receiveKnock', function(knockerSrc, knockerName, houseId, doorName)
    table.insert(pendingKnocks, { src = knockerSrc, name = knockerName, houseId = houseId, doorName = doorName })
    PlaySoundFrontend(-1, "DOOR_HARD", "HUD_WINDOW_SOUNDSET", true)
    if not isMenuOpen then openPropertyMenu("knock") end
end)

RegisterNetEvent('myproperty:receiveInvite', function(inviterName, houseId, doorName)
    table.insert(pendingInvites, { name = inviterName, houseId = houseId, doorName = doorName })
    if not isMenuOpen then openPropertyMenu("inviteRequest") end
end)

-- ==========================================
-- [8] PLACEMENT EVENT HANDLERS
-- ==========================================
RegisterNetEvent('myproperty:confirmPlacement')
AddEventHandler('myproperty:confirmPlacement', function(data, coords, rot)
    local item = data.item 
    item.coords = coords 
    item.rot = rot
    local prop = item.prop or spawnedProps[item.id] 
    if prop and DoesEntityExist(prop) then 
        SetEntityCoordsNoOffset(prop, coords.x, coords.y, coords.z, false, false, false) 
        SetEntityRotation(prop, rot.x, rot.y, rot.z, 2, true) 
        SetEntityAlpha(prop, 255, false) 
        SetEntityCollision(prop, not item.noCollision, not item.noCollision)
    end
    selectedFurniture = item 
    if item.isPendingBuy then openPropertyMenu("preview") else openPropertyMenu("object") end
end)

RegisterNetEvent('myproperty:cancelPlacement')
AddEventHandler('myproperty:cancelPlacement', function(data)
    local item = data.item 
    local prop = item.prop or spawnedProps[item.id]
    if prop and DoesEntityExist(prop) then 
        SetEntityCoordsNoOffset(prop, item.coords.x, item.coords.y, item.coords.z, false, false, false) 
        SetEntityRotation(prop, item.rot.x, item.rot.y, item.rot.z, 2, true) 
        SetEntityAlpha(prop, 255, false) 
        SetEntityCollision(prop, not item.noCollision, not item.noCollision)
    end
    selectedFurniture = item 
    if item.isPendingBuy then openPropertyMenu("preview") else openPropertyMenu("object") end
end)

RegisterNetEvent('myproperty:openDeleteMenu') 
AddEventHandler('myproperty:openDeleteMenu', function(hId) deletePropertyId = hId openPropertyMenu("delete") end)

-- ==========================================
-- [9] COMMANDS 
-- ==========================================
local function ToggleDoorLockState(wantsLock)
    local ped = PlayerPedId() local pCoords = GetEntityCoords(ped) local foundDoor = nil local foundHouseId = nil
    for _, house in pairs(Houses) do
        if house.doors then
            if myDimension == house.parent_dimension then
                for _, door in ipairs(house.doors) do
                    if door.entrance then
                        local dist = #(pCoords - vector3(door.entrance.x, door.entrance.y, door.entrance.z))
                        if dist < 1.5 then foundDoor = door.name foundHouseId = house.id break end
                    end
                end
            end
            if myDimension == house.dimension and not foundDoor then
                for _, door in ipairs(house.doors) do
                    if door.exit then
                        local dist = #(pCoords - vector3(door.exit.x, door.exit.y, door.exit.z))
                        if dist < 1.5 then foundDoor = door.name foundHouseId = house.id break end
                    end
                end
            end
        end
        if foundDoor then break end
    end
    if foundDoor and foundHouseId then
        local hasPerm = false
        if Houses[foundHouseId].owner == PlayerData.citizenid then hasPerm = true end
        if Houses[foundHouseId].keys and Houses[foundHouseId].keys[PlayerData.citizenid] then hasPerm = true end
        if PlayerData.metadata["isadmin"] then hasPerm = true end
        if hasPerm then TriggerServerEvent('myproperty:setDoorLock', foundHouseId, foundDoor, wantsLock)
        else TriggerEvent('chat:addMessage', { args = { '^1System', 'คุณไม่มีกุญแจสำหรับบ้านหลังนี้!' } }) end
    else TriggerEvent('chat:addMessage', { args = { '^1System', 'คุณต้องยืนอยู่ในวงวาร์ปประตู!' } }) end
end

RegisterCommand('knockd', function()
    if isKnocking then return end
    local ped = PlayerPedId() local pCoords = GetEntityCoords(ped) local foundHouseId, foundDoorName = nil, nil
    for _, house in pairs(Houses) do
        if house.doors and myDimension == house.parent_dimension then
            for _, door in ipairs(house.doors) do
                if door.entrance then
                    local dist = #(pCoords - vector3(door.entrance.x, door.entrance.y, door.entrance.z))
                    if dist < 1.5 then foundHouseId = house.id foundDoorName = door.name break end
                end
            end
        end
        if foundHouseId then break end
    end
    if foundHouseId then
        isKnocking = true
        Citizen.CreateThread(function()
            RequestAnimDict("timetable@jimmy@doorknock@") while not HasAnimDictLoaded("timetable@jimmy@doorknock@") do Citizen.Wait(10) end
            TaskPlayAnim(ped, "timetable@jimmy@doorknock@", "knockdoor_idle", 8.0, 8.0, -1, 49, 0, false, false, false)
            PlaySoundFrontend(-1, "DOOR_HARD", "HUD_WINDOW_SOUNDSET", true)
            Citizen.Wait(2000) ClearPedTasks(ped) isKnocking = false
        end)
        TriggerServerEvent('myproperty:knockDoor', foundHouseId, foundDoorName)
    else TriggerEvent('chat:addMessage', { args = { '^1System', 'ต้องยืนที่วงวาร์ปทางเข้าหน้าบ้านเท่านั้น!' } }) end
end, false)

RegisterCommand('invitetop', function()
    if myDimension == 0 then
        TriggerEvent('chat:addMessage', { args = { '^1System', 'คุณต้องอยู่ในบ้านเพื่อใช้คำสั่งนี้' } })
        return
    end

    if not HasKey() then
        TriggerEvent('chat:addMessage', { args = { '^1System', 'คุณไม่มีกุญแจบ้านหลังนี้!' } })
        return
    end

    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local nearestDoor = nil
    local shortestDist = 5.0 

    if Houses[myHouseId] and Houses[myHouseId].doors then
        for _, door in ipairs(Houses[myHouseId].doors) do
            if door.exit then
                local dist = #(pCoords - vector3(door.exit.x, door.exit.y, door.exit.z))
                if dist < shortestDist then
                    shortestDist = dist
                    nearestDoor = door.name
                end
            end
        end
    end

    if nearestDoor then
        TriggerServerEvent('myproperty:requestPlayersOutside', myHouseId, nearestDoor)
    else
        TriggerEvent('chat:addMessage', { args = { '^1System', 'คุณต้องไปยืนใกล้ๆ ประตูทางออกด้านในบ้านก่อนถึงจะเชิญคนได้' } })
    end
end, false)

RegisterCommand('lockdoor', function() ToggleDoorLockState(true) end, false)
RegisterCommand('ld', function() ExecuteCommand('lockdoor') end, false)
RegisterCommand('unlockdoor', function() ToggleDoorLockState(false) end, false)
RegisterCommand('ud', function() ExecuteCommand('unlockdoor') end, false)

RegisterCommand('checkhouse', function()
    local ped = PlayerPedId() local pCoords = GetEntityCoords(ped) local found = false
    for _, house in pairs(Houses) do
        if house.doors and house.doors[1] and house.doors[1].entrance and myDimension == house.parent_dimension then
            local dist = #(pCoords - vector3(house.doors[1].entrance.x, house.doors[1].entrance.y, house.doors[1].entrance.z))
            if dist < 1.5 then TriggerEvent('chat:addMessage', { args = { '^5System', 'ข้อมูลบ้าน ID: ' .. house.id } }) found = true break end
        end
    end
    if not found then TriggerEvent('chat:addMessage', { args = { '^1System', 'คุณต้องยืนในวงวาร์ปทางเข้าเพื่อเช็ค ID' } }) end
end, false)

RegisterCommand('deleteproperty', function(source, args)
    local houseId = tonumber(args[1])
    if not houseId then TriggerEvent('chat:addMessage', { args = { '^1System', 'วิธีใช้: /deleteproperty [ID]' } }) return end
    if not Houses[houseId] then TriggerEvent('chat:addMessage', { args = { '^1System', 'ไม่พบ ID บ้านนี้!' } }) return end
    local ped = PlayerPedId() 
    local dist = #(GetEntityCoords(ped) - vector3(Houses[houseId].doors[1].entrance.x, Houses[houseId].doors[1].entrance.y, Houses[houseId].doors[1].entrance.z))
    if dist > 3.0 then TriggerEvent('chat:addMessage', { args = { '^1System', 'คุณต้องยืนใกล้ทางเข้าเพื่อลบ' } }) return end
    TriggerServerEvent('myproperty:requestDeleteMenu', houseId)
end, false)

RegisterCommand('manageproperty', function() 
    if myDimension ~= 0 and HasKey() then openPropertyMenu("main") 
    elseif myDimension ~= 0 then TriggerEvent('chat:addMessage', { args = { '^1System', 'คุณไม่มีกุญแจสำหรับบ้านหลังนี้!' } }) end 
end, false)
RegisterCommand('mp', function() ExecuteCommand('manageproperty') end, false)

RegisterCommand('buyfurniture', function() 
    if myDimension ~= 0 and HasKey() then openPropertyMenu("buy") 
    elseif myDimension ~= 0 then TriggerEvent('chat:addMessage', { args = { '^1System', 'คุณไม่มีกุญแจสำหรับบ้านหลังนี้!' } }) end 
end, false)
RegisterCommand('bf', function() ExecuteCommand('buyfurniture') end, false)

RegisterCommand('setexit', function(source, args) 
    if myDimension ~= 0 and HasKey() then TriggerServerEvent('myproperty:setExitCoords', myHouseId, args[1] or "Main", GetEntityCoords(PlayerPedId())) 
    elseif myDimension ~= 0 then TriggerEvent('chat:addMessage', { args = { '^1System', 'คุณไม่มีกุญแจสำหรับบ้านหลังนี้!' } }) end 
end, false)
RegisterCommand('se', function(source, args) ExecuteCommand('setexit ' .. (args[1] or "")) end, false)

RegisterCommand('setentrance', function(source, args)
    local houseId = tonumber(args[1]) local doorName = args[2]
    if not houseId or not doorName then TriggerEvent('chat:addMessage', { args = { '^1System', 'วิธีใช้: /setentrance [HouseID] [DoorName]' } }) return end
    local hasPerm = false
    if Houses[houseId] and Houses[houseId].owner == PlayerData.citizenid then hasPerm = true end
    if Houses[houseId] and Houses[houseId].keys and Houses[houseId].keys[PlayerData.citizenid] then hasPerm = true end
    if QBCore.Functions.GetPlayerData().metadata["isadmin"] then hasPerm = true end
    if hasPerm then TriggerServerEvent('myproperty:setEntranceCoords', houseId, doorName, GetEntityCoords(PlayerPedId()))
    else TriggerEvent('chat:addMessage', { args = { '^1System', 'คุณไม่มีกุญแจสำหรับบ้านหลังนี้!' } }) end
end, false)

RegisterCommand('clearprops', function()
    local coords = GetEntityCoords(PlayerPedId()) local deletedCount = 0
    for _, cat in ipairs(Config.FurnitureShop) do 
        for _, item in ipairs(cat.items) do 
            local prop = GetClosestObjectOfType(coords.x, coords.y, coords.z, 5.0, GetHashKey(item.model), false, false, false) 
            if DoesEntityExist(prop) then DeleteEntity(prop) deletedCount = deletedCount + 1 end 
        end 
    end
    if deletedCount > 0 then TriggerEvent('chat:addMessage', { args = { '^2System', 'ล้างไอเทมบัค ' .. deletedCount .. ' ชิ้น' } }) 
    else TriggerEvent('chat:addMessage', { args = { '^1System', 'ไม่พบไอเทมบัคอยู่ใกล้ๆ' } }) end
end, false)

RegisterCommand('setptime', function(source, args)
    if myDimension == 0 then return end
    if not HasKey() then TriggerEvent('chat:addMessage', { args = { '^1System', 'คุณไม่มีกุญแจสำหรับบ้านหลังนี้!' } }) return end
    if args[1] == "reset" then TriggerServerEvent('myproperty:resetTime', myHouseId)
    else
        local h = tonumber(args[1])
        if h and h >= 0 and h <= 23 then TriggerServerEvent('myproperty:setTime', myHouseId, h, tonumber(args[2]) or 0)
        else TriggerEvent('chat:addMessage', { args = { '^1System', 'วิธีใช้: /setptime [0-23] หรือ /setptime reset' } }) end
    end
end, false)

RegisterCommand('sellproperty', function(source, args)
    local price = tonumber(args[1])
    if not price or price < 0 then TriggerEvent('chat:addMessage', { args = { '^1System', 'วิธีใช้: /sellproperty [ราคา]' } }) return end
    local ped = PlayerPedId() local pCoords = GetEntityCoords(ped) local foundHouseId = nil
    for _, house in pairs(Houses) do
        if house.doors and myDimension == house.parent_dimension then
            for _, door in ipairs(house.doors) do
                if door.entrance then
                    local dist = #(pCoords - vector3(door.entrance.x, door.entrance.y, door.entrance.z))
                    if dist < 1.5 then foundHouseId = house.id break end
                end
            end
        end
        if foundHouseId then break end
    end
    if foundHouseId then TriggerServerEvent('myproperty:sellProperty', foundHouseId, price)
    else TriggerEvent('chat:addMessage', { args = { '^1System', 'ต้องยืนที่วงวาร์ปหน้าบ้านเท่านั้น!' } }) end
end, false)

RegisterCommand('cancelsellp', function()
    local ped = PlayerPedId() local pCoords = GetEntityCoords(ped) local foundHouseId = nil
    for _, house in pairs(Houses) do
        if house.doors and myDimension == house.parent_dimension then
            for _, door in ipairs(house.doors) do
                if door.entrance then
                    local dist = #(pCoords - vector3(door.entrance.x, door.entrance.y, door.entrance.z))
                    if dist < 1.5 then foundHouseId = house.id break end
                end
            end
        end
        if foundHouseId then break end
    end
    if foundHouseId then TriggerServerEvent('myproperty:cancelSell', foundHouseId)
    else TriggerEvent('chat:addMessage', { args = { '^1System', 'ต้องยืนที่วงวาร์ปหน้าบ้านเท่านั้น!' } }) end
end, false)

RegisterCommand('buyproperty', function()
    local ped = PlayerPedId() local pCoords = GetEntityCoords(ped) local foundHouseId = nil
    for _, house in pairs(Houses) do
        if house.doors and myDimension == house.parent_dimension then
            for _, door in ipairs(house.doors) do
                if door.entrance then
                    local dist = #(pCoords - vector3(door.entrance.x, door.entrance.y, door.entrance.z))
                    if dist < 1.5 then foundHouseId = house.id break end
                end
            end
        end
        if foundHouseId then break end
    end
    if foundHouseId then TriggerServerEvent('myproperty:buyProperty', foundHouseId)
    else TriggerEvent('chat:addMessage', { args = { '^1System', 'ต้องยืนที่วงวาร์ปหน้าบ้านที่จะซื้อเท่านั้น!' } }) end
end, false)

RegisterCommand('checkdim', function()
    TriggerEvent('chat:addMessage', { args = { '^5System', 'มิติปัจจุบัน (Bucket): ' .. myDimension } })
end, false)

AddEventHandler('onResourceStop', function(resourceName) if (GetCurrentResourceName() == resourceName) then ClearHouseFurniture() end end)

-- ==========================================
-- [10] MARKER RENDERING & TELEPORT LOGIC
-- ==========================================
Citizen.CreateThread(function()
    while true do
        local wait = 500 local pCoords = GetEntityCoords(PlayerPedId())
        for _, house in pairs(Houses) do
            if house.doors then
                if myDimension == house.parent_dimension then
                    for _, door in ipairs(house.doors) do
                        if door.entrance then
                            local dist = #(pCoords - vector3(door.entrance.x, door.entrance.y, door.entrance.z))
                            if dist < 10.0 then 
                                wait = 0 local m = Config.Marker
                                local r, g, b = m.EnterColor.r, m.EnterColor.g, m.EnterColor.b
                                if door.locked then r, g, b = 200, 50, 50 end
                                DrawMarker(m.Type, door.entrance.x, door.entrance.y, door.entrance.z - 0.98, 0, 0, 0, 0, 0, 0, m.Size.x, m.Size.y, m.Size.z, r, g, b, m.EnterColor.a, false, false, false, false)
                                
                                if dist < 1.5 then 
                                    SetTextComponentFormat("STRING") 
                                    if house.price and house.price >= 0 then
                                        AddTextComponentString("Press ~INPUT_CONTEXT~ to Enter~n~~g~For Sale: $" .. house.price .. " ~w~(/buyproperty)") 
                                    else
                                        if door.locked then 
                                            AddTextComponentString("~r~[LOCKED] ~w~" .. door.name .. " (Use /knockd to knock)") 
                                        else 
                                            AddTextComponentString("Press ~INPUT_CONTEXT~ to Enter " .. door.name .. " (Use /ld)") 
                                        end
                                    end
                                    DisplayHelpTextFromStringLabel(0, 0, 1, -1)
                                    
                                    if IsControlJustReleased(0, 38) then 
                                        if not door.locked then TriggerServerEvent('myproperty:enterHouse', house.id, door.name) 
                                        else TriggerEvent('chat:addMessage', { args = { '^1System', 'ประตูล็อคอยู่! พิมพ์ /knockd เพื่อเคาะประตู' } }) end
                                    end
                                end
                            end
                        end
                    end
                end
                
                if myDimension == house.dimension then
                    for _, door in ipairs(house.doors) do
                        if door.exit then
                            local dist = #(pCoords - vector3(door.exit.x, door.exit.y, door.exit.z))
                            if dist < 10.0 then 
                                wait = 0 local m = Config.Marker
                                local r, g, b = m.ExitColor.r, m.ExitColor.g, m.ExitColor.b
                                if door.locked then r, g, b = 200, 50, 50 end
                                DrawMarker(m.Type, door.exit.x, door.exit.y, door.exit.z - 0.98, 0, 0, 0, 0, 0, 0, m.Size.x, m.Size.y, m.Size.z, r, g, b, m.ExitColor.a, false, false, false, false)
                                
                                if dist < 1.5 then 
                                    SetTextComponentFormat("STRING") 
                                    if door.locked then AddTextComponentString("~r~[LOCKED] ~w~" .. door.name .. " (Use /ud)") 
                                    else AddTextComponentString("Press ~INPUT_CONTEXT~ to Exit " .. door.name .. " (Use /ld)") end
                                    DisplayHelpTextFromStringLabel(0, 0, 1, -1)
                                    
                                    if IsControlJustReleased(0, 38) then 
                                        if not door.locked then TriggerServerEvent('myproperty:exitHouse', house.id, door.name) 
                                        else TriggerEvent('chat:addMessage', { args = { '^1System', 'ประตูนี้ล็อคอยู่!' } }) end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        Citizen.Wait(wait)
    end
end)

-- ==========================================
-- [11] TIME & WEATHER OVERRIDE (Property Time)
-- ==========================================
Citizen.CreateThread(function()
    local wasOverridingTime = false
    while true do
        local wait = 500
        
        if _G.isFrozenInProperty then
            wait = 0
            local ped = PlayerPedId()
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            
            SetTextFont(4)
            SetTextScale(0.5, 0.5)
            SetTextColour(255, 255, 255, 255)
            SetTextOutline()
            SetTextEntry("STRING")
            AddTextComponentString("~y~Property Loaded! ~w~Press ~g~[H] ~w~to unlock movement.")
            DrawText(0.35, 0.85)

            if IsControlJustReleased(0, 74) then 
                _G.isFrozenInProperty = false
                FreezeEntityPosition(ped, false)
                TriggerEvent('chat:addMessage', { args = { '^2System', 'ปลดล็อคการเคลื่อนไหวแล้ว!' } })
            end
        end

        if myDimension ~= 0 and myHouseId and Houses[myHouseId] and Houses[myHouseId].time then
            wait = 0 
            local t = Houses[myHouseId].time
            if not wasOverridingTime then
                wasOverridingTime = true
                TriggerEvent('qb-weathersync:client:DisableSync')
                TriggerEvent('vSync:requestSync', false)
            end
            NetworkOverrideClockTime(t.h, t.m, 0)
            PauseClock(true)
        else
            if wasOverridingTime then
                wasOverridingTime = false
                NetworkClearClockTimeOverride()
                PauseClock(false)
                TriggerEvent('qb-weathersync:client:EnableSync')
                TriggerEvent('vSync:requestSync', true)
            end
        end
        Citizen.Wait(wait)
    end
end)