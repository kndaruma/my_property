local QBCore = exports['qb-core']:GetCoreObject()
local isPlacing = false
local previewObj = nil
local placementMode = 'Moving' 
local speed = 1.00 
local currentItemData = nil
local objectFrozen = false 
local lastSpeedChange = 0 

local function cleanTrig(val)
    if math.abs(val) < 0.000001 then return 0.0 end
    if math.abs(val - 1.0) < 0.000001 then return 1.0 end
    if math.abs(val + 1.0) < 0.000001 then return -1.0 end
    return val
end

local function GetVectorsFromRotation(rot)
    local radX = math.rad(rot.x)
    local radY = math.rad(rot.y)
    local radZ = math.rad(rot.z)
    
    local sX, cX = cleanTrig(math.sin(radX)), cleanTrig(math.cos(radX))
    local sY, cY = cleanTrig(math.sin(radY)), cleanTrig(math.cos(radY))
    local sZ, cZ = cleanTrig(math.sin(radZ)), cleanTrig(math.cos(radZ))
    
    local right = vector3(cZ * cY - sZ * sX * sY, sZ * cY + cZ * sX * sY, -cX * sY)
    local fwd = vector3(-sZ * cX, cZ * cX, sX)
    local up = vector3(cZ * sY + sZ * sX * cY, sZ * sY - cZ * sX * cY, cX * cY)
    
    return right, fwd, up
end

local function DrawText3DUI(text, x, y, scale)
    SetTextFont(4) 
    SetTextScale(scale, scale)
    SetTextColour(255, 255, 255, 255)
    SetTextOutline() 
    SetTextCentre(true)
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

local function formatCoord(val)
    local rounded = math.floor((val * 1000) + 0.5) / 1000
    if rounded % 1 == 0 then
        return tostring(math.floor(rounded))
    end
    local str = string.format("%.3f", rounded)
    return str:gsub("0+$", "") 
end

local function DrawPlacementUI(coords, rot)
    local startY = 0.30
    local spacing = 0.025 
    local xPos = 0.20 
    local line = 0

    DrawText3DUI("~g~Press R to change between rotate/move", xPos, startY + (spacing * line), 0.50); line = line + 1
    
    if placementMode == 'Moving' then
        DrawText3DUI("~w~Moving", xPos, startY + (spacing * line), 0.42); line = line + 1
    else
        DrawText3DUI("~w~Rotating", xPos, startY + (spacing * line), 0.42); line = line + 1
    end
    
    local dispSpeed = math.floor((speed * 100) + 0.5) / 100
    local speedStr = (dispSpeed % 1 == 0) and tostring(math.floor(dispSpeed)) or string.format("%.2f", dispSpeed)
    
    DrawText3DUI("~w~Speed: ~g~" .. speedStr, xPos, startY + (spacing * line), 0.42); line = line + 1
    
    if placementMode == 'Moving' then
        DrawText3DUI("~w~Move: ~g~Arrows", xPos, startY + (spacing * line), 0.42); line = line + 1
        DrawText3DUI("~w~Up/Down: ~g~W/S", xPos, startY + (spacing * line), 0.42); line = line + 1
    else
        DrawText3DUI("~w~Rotate X: ~g~Up/Down", xPos, startY + (spacing * line), 0.42); line = line + 1
        DrawText3DUI("~w~Rotate Y: ~g~W/S", xPos, startY + (spacing * line), 0.42); line = line + 1
        DrawText3DUI("~w~Rotate Z: ~g~Left/Right", xPos, startY + (spacing * line), 0.42); line = line + 1
    end
    
    DrawText3DUI("~w~Validate: ~g~Enter", xPos, startY + (spacing * line), 0.42); line = line + 1
    DrawText3DUI("~w~Cancel: ~g~Delete / Backspace", xPos, startY + (spacing * line), 0.42); line = line + 1
    DrawText3DUI("~w~Speed: ~g~PageUp/PageDown", xPos, startY + (spacing * line), 0.42); line = line + 1
    DrawText3DUI("~w~Speed (0.01): ~g~, / .", xPos, startY + (spacing * line), 0.42); line = line + 1
    DrawText3DUI("~w~Speed Min/Max: ~g~[ / ]", xPos, startY + (spacing * line), 0.42); line = line + 1
    
    local freezeText = objectFrozen and "~g~Frozen" or "~w~Unfrozen"
    DrawText3DUI("~w~Freeze/Unfreeze: ~g~F ~w~(" .. freezeText .. "~w~)", xPos, startY + (spacing * line), 0.42); line = line + 1

    local px, py, pz = formatCoord(coords.x), formatCoord(coords.y), formatCoord(coords.z)
    local rx, ry, rz = formatCoord(rot.x), formatCoord(rot.y), formatCoord(rot.z)

    line = line + 1 
    DrawText3DUI("~g~Current Position:", xPos, startY + (spacing * line), 0.42); line = line + 1
    DrawText3DUI(string.format("~g~X ~w~%s ~w~| ~g~Y ~w~%s ~w~| ~g~Z ~w~%s", px, py, pz), xPos, startY + (spacing * line), 0.42); line = line + 1
    DrawText3DUI("~g~Current Rotation:", xPos, startY + (spacing * line), 0.42); line = line + 1
    DrawText3DUI(string.format("~g~X ~w~%s ~w~| ~g~Y ~w~%s ~w~| ~g~Z ~w~%s", rx, ry, rz), xPos, startY + (spacing * line), 0.42); line = line + 1
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
    speed = 1.00 
    objectFrozen = false 
    
    RequestModel(model)
    while not HasModelLoaded(model) do Citizen.Wait(10) end

    local ped = PlayerPedId()
    
    local baseCoords = vector3(data.item.coords.x, data.item.coords.y, data.item.coords.z)
    local currentCoords = baseCoords
    local currentRot = vector3(data.item.rot.x, data.item.rot.y, data.item.rot.z)
    local localOffsetX, localOffsetY, localOffsetZ = 0.0, 0.0, 0.0

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
                
                -- ★ Speed (+/- 0.5) : PageUp (10) / PageDown (11)
                if (IsDisabledControlPressed(0, 10) or IsControlPressed(0, 10)) and (currentTime - lastSpeedChange > 100) then 
                    speed = speed + 0.5 
                    lastSpeedChange = currentTime
                end 
                if (IsDisabledControlPressed(0, 11) or IsControlPressed(0, 11)) and (currentTime - lastSpeedChange > 100) then 
                    speed = speed - 0.5 
                    lastSpeedChange = currentTime
                end 

                -- ★ Speed ละเอียด (+/- 0.01) : . (81) / , (82)
                if (IsDisabledControlPressed(0, 81) or IsControlPressed(0, 81)) and (currentTime - lastSpeedChange > 50) then 
                    speed = speed + 0.01 
                    lastSpeedChange = currentTime
                end 
                if (IsDisabledControlPressed(0, 82) or IsControlPressed(0, 82)) and (currentTime - lastSpeedChange > 50) then 
                    speed = speed - 0.01 
                    lastSpeedChange = currentTime
                end 
                
                -- ★ Speed Min (0.01) : [ (39)
                if IsDisabledControlJustPressed(0, 39) or IsControlJustPressed(0, 39) then
                    speed = 0.01
                end
                -- ★ Speed Max (10.0) : ] (40)
                if IsDisabledControlJustPressed(0, 40) or IsControlJustPressed(0, 40) then
                    speed = 10.0
                end
                
                if speed < 0.01 then speed = 0.01 end
                if speed > 10.0 then speed = 10.0 end

                if IsDisabledControlJustPressed(0, 45) or IsControlJustPressed(0, 45) then 
                    placementMode = (placementMode == 'Moving') and 'Rotating' or 'Moving'
                end

                local frameTime = GetFrameTime()
                local isMoved = false
                local isRotated = false
                
                if placementMode == 'Moving' then
                    local xOff, yOff, zOff = 0.0, 0.0, 0.0
                    local moveMultiplier = speed * frameTime * 5.0 

                    if IsDisabledControlPressed(0, 172) or IsControlPressed(0, 172) then yOff = moveMultiplier; isMoved = true end 
                    if IsDisabledControlPressed(0, 173) or IsControlPressed(0, 173) then yOff = -moveMultiplier; isMoved = true end 
                    if IsDisabledControlPressed(0, 174) or IsControlPressed(0, 174) then xOff = -moveMultiplier; isMoved = true end 
                    if IsDisabledControlPressed(0, 175) or IsControlPressed(0, 175) then xOff = moveMultiplier; isMoved = true end 
                    if IsDisabledControlPressed(0, 32) or IsControlPressed(0, 32) then zOff = moveMultiplier; isMoved = true end 
                    if IsDisabledControlPressed(0, 8) or IsControlPressed(0, 8) then zOff = -moveMultiplier; isMoved = true end 

                    if isMoved then
                        localOffsetX = localOffsetX + xOff
                        localOffsetY = localOffsetY + yOff
                        localOffsetZ = localOffsetZ + zOff

                        local right, fwd, up = GetVectorsFromRotation(currentRot)
                        currentCoords = baseCoords + (right * localOffsetX) + (fwd * localOffsetY) + (up * localOffsetZ)
                        
                        SetEntityCoordsNoOffset(previewObj, currentCoords.x, currentCoords.y, currentCoords.z, false, false, false)
                    end
                else
                    local rotMultiplier = speed * frameTime * 100.0 
                    local rx, ry, rz = 0.0, 0.0, 0.0

                    if IsDisabledControlPressed(0, 172) or IsControlPressed(0, 172) then rx = rotMultiplier; isRotated = true end 
                    if IsDisabledControlPressed(0, 173) or IsControlPressed(0, 173) then rx = -rotMultiplier; isRotated = true end 
                    if IsDisabledControlPressed(0, 32) or IsControlPressed(0, 32) then ry = rotMultiplier; isRotated = true end 
                    if IsDisabledControlPressed(0, 8) or IsControlPressed(0, 8) then ry = -rotMultiplier; isRotated = true end 
                    if IsDisabledControlPressed(0, 174) or IsControlPressed(0, 174) then rz = rotMultiplier; isRotated = true end 
                    if IsDisabledControlPressed(0, 175) or IsControlPressed(0, 175) then rz = -rotMultiplier; isRotated = true end 
                    
                    if isRotated then
                        if localOffsetX ~= 0.0 or localOffsetY ~= 0.0 or localOffsetZ ~= 0.0 then
                            baseCoords = currentCoords
                            localOffsetX, localOffsetY, localOffsetZ = 0.0, 0.0, 0.0
                        end

                        currentRot = currentRot + vector3(rx, ry, rz)
                        SetEntityRotation(previewObj, currentRot.x, currentRot.y, currentRot.z, 2, true)
                    end
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
