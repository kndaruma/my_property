local QBCore = exports['qb-core']:GetCoreObject()
local isPlacing = false
local previewObj = nil
local placementMode = 'Moving' 
local speed = 0.05
local currentItemData = nil
local objectFrozen = false 
local lastSpeedChange = 0

local function DrawText3DUI(text, x, y, scale)
    SetTextFont(4) 
    SetTextScale(scale, scale)
    SetTextColour(255, 255, 255, 255)
    SetTextOutline() 
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

local function DrawPlacementUI(coords, rot)
    local startY = 0.4
    local spacing = 0.025 
    local xPos = 0.05
    SetTextCentre(false) 
    DrawText3DUI(string.format("X: %.2f | Y: %.2f | Z: %.2f", coords.x, coords.y, coords.z), xPos, startY, 0.35)
    DrawText3DUI(string.format("Rot X: %.2f | Y: %.2f | Z: %.2f", rot.x, rot.y, rot.z), xPos, startY + spacing, 0.35)
    
    local line = 3
    DrawText3DUI("~y~Press [R] to change mode", xPos, startY + (spacing * line), 0.4); line = line + 1
    DrawText3DUI("Mode: ~y~" .. placementMode, xPos, startY + (spacing * line), 0.4); line = line + 1
    
    -- แก้ไขตรงนี้เพื่อให้หน้าจอแสดงผลจุดทศนิยม (เช่น 0.0001)
    DrawText3DUI("Speed: ~y~" .. string.format("%.4f", speed), xPos, startY + (spacing * line), 0.4); line = line + 1
    
    DrawText3DUI("Speed Up/Down: ~y~[PageUp/PageDown]", xPos, startY + (spacing * line), 0.4); line = line + 1
    DrawText3DUI("Speed Min/Max: ~y~[=]", xPos, startY + (spacing * line), 0.4); line = line + 1
    
    local freezeText = objectFrozen and "~g~Frozen (Player Can Move)" or "~r~Unfrozen (Object Can Move)"
    DrawText3DUI("Freeze/Unfreeze: ~y~[F]", xPos, startY + (spacing * line), 0.4); line = line + 1
    DrawText3DUI("Object Status: " .. freezeText, xPos, startY + (spacing * line), 0.4); line = line + 1
    
    if placementMode == 'Moving' then
        DrawText3DUI("Local Move: ~y~Arrows / W S", xPos, startY + (spacing * line), 0.4); line = line + 1
    else
        DrawText3DUI("Rot X: ~y~Up/Down ~w~| Rot Y: ~y~W/S ~w~| Rot Z: ~y~L/R", xPos, startY + (spacing * line), 0.35); line = line + 1
    end
    
    DrawText3DUI("Validate: ~g~[ENTER]", xPos, startY + (spacing * line), 0.4); line = line + 1
    DrawText3DUI("Cancel: ~r~[DELETE] / [BACKSPACE]", xPos, startY + (spacing * line), 0.4); line = line + 1
    SetTextCentre(false) 
end

RegisterNetEvent('myproperty:startPlacement')
AddEventHandler('myproperty:startPlacement', function(data)
    if isPlacing then return end
    
    local model = GetHashKey(data.item.model)
    if not IsModelValid(model) then
        TriggerEvent('chat:addMessage', { args = { '^1System', 'Invalid model!' } })
        TriggerEvent('myproperty:cancelPlacement', data)
        return
    end

    currentItemData = data
    isPlacing = true
    placementMode = 'Moving'
    speed = 0.05
    objectFrozen = false 
    
    RequestModel(model)
    while not HasModelLoaded(model) do Citizen.Wait(10) end

    local ped = PlayerPedId()
    local currentCoords = vector3(data.item.coords.x, data.item.coords.y, data.item.coords.z)
    local currentRot = vector3(data.item.rot.x, data.item.rot.y, data.item.rot.z)

    -- ซ่อนของจริงไว้ก่อน เพื่อใช้ของจำลอง (Preview) ขยับแทน
    if data.prop and DoesEntityExist(data.prop) then
        SetEntityAlpha(data.prop, 0, false) 
        SetEntityCollision(data.prop, false, false)
    end

    previewObj = CreateObject(model, currentCoords.x, currentCoords.y, currentCoords.z, false, false, false)
    SetEntityCoordsNoOffset(previewObj, currentCoords.x, currentCoords.y, currentCoords.z, false, false, false)
    SetEntityRotation(previewObj, currentRot.x, currentRot.y, currentRot.z, 2, true)
    SetEntityAlpha(previewObj, 255, false)
    
    local canCollide = not data.item.noCollision
    SetEntityCollision(previewObj, canCollide, canCollide)

    Citizen.CreateThread(function()
        while isPlacing do
            Citizen.Wait(0)
            local ped = PlayerPedId()
            
            if not canCollide then
                SetEntityNoCollisionEntity(ped, previewObj, true)
            end

            DrawPlacementUI(currentCoords, currentRot)

            if IsControlJustPressed(0, 49) or IsDisabledControlJustPressed(0, 49) then
                objectFrozen = not objectFrozen
            end

            if not objectFrozen then
                _G.BlockPeditMove = true 
                FreezeEntityPosition(ped, true) 
                DisableControlAction(0, 30, true) DisableControlAction(0, 31, true) DisableControlAction(0, 32, true) 
                DisableControlAction(0, 33, true) DisableControlAction(0, 34, true) DisableControlAction(0, 35, true) 
                DisableControlAction(0, 24, true) DisableControlAction(0, 25, true) DisableControlAction(0, 140, true) 
            else
                _G.BlockPeditMove = false 
                FreezeEntityPosition(ped, false)
            end

            if not objectFrozen then

                local currentTime = GetGameTimer() 
                
                if (IsDisabledControlPressed(0, 10) or IsControlPressed(0, 10)) and (currentTime - lastSpeedChange > 50) then 
                    speed = speed + 0.0001 
                    lastSpeedChange = currentTime
                end 
                if (IsDisabledControlPressed(0, 11) or IsControlPressed(0, 11)) and (currentTime - lastSpeedChange > 50) then 
                    speed = speed - 0.0001 
                    lastSpeedChange = currentTime
                end 
                
                if IsDisabledControlJustPressed(0, 83) or IsControlJustPressed(0, 37) then
                    if speed >= 0.5 then speed = 0.0001 else speed = 0.5 end
                end
                
                -- ตั้งค่าขีดจำกัดความเร็วต่ำสุดเป็น 0.0001
                if speed < 0.0001 then speed = 0.0001 end
                if speed > 2.0 then speed = 2.0 end

                if IsDisabledControlJustPressed(0, 45) or IsControlJustPressed(0, 45) then 
                    placementMode = (placementMode == 'Moving') and 'Rotating' or 'Moving'
                end

                if placementMode == 'Moving' then
                    local xOff, yOff, zOff = 0.0, 0.0, 0.0
                    if IsDisabledControlPressed(0, 172) or IsControlPressed(0, 172) then yOff = speed end 
                    if IsDisabledControlPressed(0, 173) or IsControlPressed(0, 173) then yOff = -speed end 
                    if IsDisabledControlPressed(0, 174) or IsControlPressed(0, 174) then xOff = -speed end 
                    if IsDisabledControlPressed(0, 175) or IsControlPressed(0, 175) then xOff = speed end 
                    if IsDisabledControlPressed(0, 32) or IsControlPressed(0, 32) then zOff = speed end 
                    if IsDisabledControlPressed(0, 8) or IsControlPressed(0, 8) then zOff = -speed end 

                    if xOff ~= 0.0 or yOff ~= 0.0 or zOff ~= 0.0 then
                        currentCoords = GetOffsetFromEntityInWorldCoords(previewObj, xOff, yOff, zOff)
                        SetEntityCoordsNoOffset(previewObj, currentCoords.x, currentCoords.y, currentCoords.z, false, false, false)
                    end
                else
                    if IsDisabledControlPressed(0, 172) or IsControlPressed(0, 172) then currentRot = currentRot + vector3(speed * 25, 0, 0) end 
                    if IsDisabledControlPressed(0, 173) or IsControlPressed(0, 173) then currentRot = currentRot - vector3(speed * 25, 0, 0) end 
                    if IsDisabledControlPressed(0, 32) or IsControlPressed(0, 32) then currentRot = currentRot + vector3(0, speed * 25, 0) end 
                    if IsDisabledControlPressed(0, 8) or IsControlPressed(0, 8) then currentRot = currentRot - vector3(0, speed * 25, 0) end 
                    if IsDisabledControlPressed(0, 174) or IsControlPressed(0, 174) then currentRot = currentRot + vector3(0, 0, speed * 25) end 
                    if IsDisabledControlPressed(0, 175) or IsControlPressed(0, 175) then currentRot = currentRot - vector3(0, 0, speed * 25) end 
                    SetEntityRotation(previewObj, currentRot.x, currentRot.y, currentRot.z, 2, true)
                end
            end

            if IsDisabledControlJustPressed(0, 191) or IsControlJustPressed(0, 191) then 
                isPlacing = false
                _G.BlockPeditMove = false 
                FreezeEntityPosition(ped, false) 
                DeleteEntity(previewObj)
                TriggerEvent('myproperty:confirmPlacement', currentItemData, currentCoords, currentRot)
            end

            if IsDisabledControlJustPressed(0, 178) or IsControlJustPressed(0, 178) or IsDisabledControlJustPressed(0, 177) or IsControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 202) or IsControlJustPressed(0, 202) then 
                isPlacing = false
                _G.BlockPeditMove = false 
                FreezeEntityPosition(ped, false) 
                DeleteEntity(previewObj)
                TriggerEvent('myproperty:cancelPlacement', currentItemData)
            end
        end
    end)
end)
