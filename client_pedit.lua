local Houses = {}
local myDimension = 0
local inPeditMode = false
local peditSpeed = 0.2 
local QBCore = exports['qb-core']:GetCoreObject()
local PlayerData = {}

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() PlayerData = QBCore.Functions.GetPlayerData() end)
RegisterNetEvent('QBCore:Player:SetPlayerData', function(val) PlayerData = val end)

Citizen.CreateThread(function() 
    Citizen.Wait(1000) 
    PlayerData = QBCore.Functions.GetPlayerData() 
end)

RegisterNetEvent('myproperty:syncHouses')
AddEventHandler('myproperty:syncHouses', function(serverHouses) 
    Houses = serverHouses 
end)

RegisterNetEvent('myproperty:syncDimension')
AddEventHandler('myproperty:syncDimension', function(dim) 
    myDimension = dim 
    local myHouseId = nil
    for _, house in pairs(Houses) do
        if house.dimension == dim then myHouseId = house.id break end
        if house.lifts then 
            for _, f in ipairs(house.lifts) do 
                if f.dim == dim then myHouseId = house.id break end 
            end 
        end
    end
    _G.myHouseIdForPedit = myHouseId 
end)

local function HasKey()
    local hid = _G.myHouseIdForPedit
    if not hid or not Houses[hid] or not PlayerData.citizenid then return false end
    if Houses[hid].keys and Houses[hid].keys[PlayerData.citizenid] then return true end
    if PlayerData.metadata and PlayerData.metadata["isadmin"] then return true end
    return false 
end

local function DrawUIText(text, x, y, scale)
    SetTextFont(4) 
    SetTextScale(scale, scale) 
    SetTextColour(255, 255, 255, 255) 
    SetTextOutline() 
    SetTextEntry("STRING") 
    AddTextComponentString(text) 
    DrawText(x, y)
end

RegisterCommand('peditmode', function()
    if myDimension == 0 then return end
    if not HasKey() then TriggerEvent('chat:addMessage', { args = { '^1System', 'You do not have the keys for this property!' } }) return end
    
    inPeditMode = not inPeditMode 
    local ped = PlayerPedId()
    
    if inPeditMode then 
        SetEntityAlpha(ped, 150, false) 
        SetEntityCollision(ped, false, false) 
        FreezeEntityPosition(ped, true) 
        peditSpeed = 0.2
    else 
        SetEntityAlpha(ped, 255, false) 
        SetEntityCollision(ped, true, true) 
        FreezeEntityPosition(ped, false) 
    end
end, false)

RegisterCommand('pe', function() ExecuteCommand('peditmode') end, false)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if inPeditMode then
            local ped = PlayerPedId()
            
            DisableControlAction(0, 14, true) 
            DisableControlAction(0, 15, true) 
            
            if IsDisabledControlJustPressed(0, 15) then peditSpeed = peditSpeed + 0.05 end 
            if IsDisabledControlJustPressed(0, 14) then peditSpeed = peditSpeed - 0.05 end 
            
            if peditSpeed < 0.01 then peditSpeed = 0.01 end 
            if peditSpeed > 2.0 then peditSpeed = 2.0 end
            
            -- ★ เช็คสัญญาณจาก placement.lua ถ้า Block อยู่ จะไม่ให้ใช้ WASD ของ /pe ขยับตัว
            if not _G.BlockPeditMove then
                local pos = GetEntityCoords(ped)
                local camRot = GetGameplayCamRot(2)
                local heading = math.rad(camRot.z)
                local pitch = math.rad(camRot.x)
                
                local dx = -math.sin(heading) * peditSpeed
                local dy = math.cos(heading) * peditSpeed
                local dz = math.sin(pitch) * peditSpeed
                local rightDx = math.cos(heading) * peditSpeed
                local rightDy = math.sin(heading) * peditSpeed
                
                local newPos = pos
                if IsControlPressed(0, 32) then newPos = newPos + vector3(dx, dy, dz) end 
                if IsControlPressed(0, 8) then newPos = newPos - vector3(dx, dy, dz) end 
                if IsControlPressed(0, 34) then newPos = newPos - vector3(rightDx, rightDy, 0.0) end 
                if IsControlPressed(0, 9) then newPos = newPos + vector3(rightDx, rightDy, 0.0) end 
                if IsControlPressed(0, 22) then newPos = newPos + vector3(0.0, 0.0, peditSpeed) end 
                if IsControlPressed(0, 21) then newPos = newPos - vector3(0.0, 0.0, peditSpeed) end 
                
                SetEntityCoordsNoOffset(ped, newPos.x, newPos.y, newPos.z, true, true, true) 
                SetEntityHeading(ped, camRot.z)
            end
            
            local lines = { 
                "~y~Property Editor", 
                "Speed: ~g~" .. string.format("%.2f", peditSpeed), 
                "[W A S D] Move", 
                "[SPACEBAR] Up", 
                "[SHIFT] Down", 
                "[Scroll Wheel] Adjust Speed", 
                "[BACKSPACE] Exit" 
            }
            local startY = 0.62 
            local spacing = 0.028 
            for i, text in ipairs(lines) do 
                DrawUIText(text, 0.85, startY + (i * spacing), 0.4) 
            end
            
            if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 202) then 
                ExecuteCommand('peditmode') 
            end
        end
    end
end)
