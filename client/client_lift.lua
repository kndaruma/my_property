local Houses = {}
local showLiftMarker = true
local myDimension = 0
local myHouseId = nil
local PlayerData = {}
local QBCore = exports['qb-core']:GetCoreObject()

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
    myHouseId = nil
    for _, house in pairs(Houses) do
        if house.dimension == dim then myHouseId = house.id break end
        if house.lifts then 
            for _, f in ipairs(house.lifts) do 
                if f.dim == dim then myHouseId = house.id break end 
            end 
        end
    end
end)

-- ★ OPTIMIZED
local function HasKey()
    if not myHouseId or not Houses[myHouseId] or not PlayerData.citizenid then return false end
    if Houses[myHouseId].keys and Houses[myHouseId].keys[PlayerData.citizenid] then return true end
    if PlayerData.metadata and PlayerData.metadata["isadmin"] then return true end
    return false 
end

local function KeyboardInput(TextEntry, ExampleText, MaxStringLength)
    AddTextEntry('FMMC_KEY_TIP1', TextEntry) 
    DisplayOnscreenKeyboard(1, "FMMC_KEY_TIP1", "", ExampleText, "", "", "", MaxStringLength)
    while UpdateOnscreenKeyboard() ~= 1 and UpdateOnscreenKeyboard() ~= 2 do Citizen.Wait(0) end
    if UpdateOnscreenKeyboard() ~= 2 then return GetOnscreenKeyboardResult() else return nil end
end

local function openLiftMenu()
    local liftMenu = RageUI.CreateMenu("Elevator", "Select floor", 1350, 50)
    local deleteMenu = RageUI.CreateSubMenu(liftMenu, "Delete Floor", "Remove structural floor")
    RageUI.Visible(liftMenu, true)

    while liftMenu do
        Citizen.Wait(0)
        RageUI.IsVisible(liftMenu, true, true, true, function()
            local houseData = Houses[myHouseId] 
            if not houseData or not houseData.lifts then return end
            
            for i, floor in ipairs(houseData.lifts) do
                local status = floor.coords and "" or "~r~[No Marker]"
                RageUI.ButtonWithStyle(floor.name .. " " .. status, "Teleport to this floor", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                    if Selected then
                        RageUI.CloseAll() 
                        local targetCoords = floor.coords or houseData.lifts[1].coords
                        TriggerServerEvent('myproperty:useElevator', myHouseId, floor.dim, targetCoords)
                        if not floor.coords then
                            Citizen.SetTimeout(1000, function() 
                                TriggerEvent('chat:addMessage', { args = { '^3System', '⚠️ Use /pe to fly and /sl to set a lift marker here!' } }) 
                            end)
                        end
                    end
                end)
            end
            
            if HasKey() then
                RageUI.Separator("--- Manage Lift ---")
                RageUI.ButtonWithStyle("~g~+ Create New Floor", "Add a new dimension floor", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                    if Selected then
                        local name = KeyboardInput("Enter floor name (e.g. Basement):", "", 20)
                        if name and name ~= "" then TriggerServerEvent('myproperty:addLiftFloor', myHouseId, name) end
                    end
                end)
                
                local currentFloorIndex = nil
                for i, f in ipairs(houseData.lifts) do 
                    if f.dim == myDimension then currentFloorIndex = i break end 
                end
                
                if currentFloorIndex then
                    RageUI.ButtonWithStyle("~y~Update Lift Marker Here", "Set lift marker at current position", { RightLabel = "→" }, true, function(Hovered, Active, Selected)
                        if Selected then 
                            TriggerServerEvent('myproperty:updateLiftMarker', myHouseId, currentFloorIndex, GetEntityCoords(PlayerPedId())) 
                            RageUI.CloseAll() 
                        end
                    end)
                end
                
                if #houseData.lifts > 1 then 
                    RageUI.ButtonWithStyle("~r~- Delete Floor", "Permanently delete a floor", { RightLabel = "→" }, true, function() end, deleteMenu) 
                end
            end

            RageUI.Separator("-----------------------")
            RageUI.Checkbox("Show Lift Marker", "On/Off Marker", showLiftMarker, { Style = RageUI.CheckboxStyle.Tick }, function(Hovered, Selected, Active, Checked)
                if Selected then showLiftMarker = Checked end
            end)
            
        end, function() end)

        RageUI.IsVisible(deleteMenu, true, true, true, function()
            local houseData = Houses[myHouseId]
            for i, floor in ipairs(houseData.lifts) do
                if i > 1 then 
                    RageUI.ButtonWithStyle("Delete " .. floor.name, "Delete this floor permanently", { RightLabel = "X" }, true, function(Hovered, Active, Selected)
                        if Selected then 
                            TriggerServerEvent('myproperty:deleteLiftFloor', myHouseId, i) 
                            RageUI.CloseAll() 
                        end
                    end)
                end
            end
        end, function() end)

        if not RageUI.Visible(liftMenu) and not RageUI.Visible(deleteMenu) then 
            liftMenu = RMenu:DeleteType("Elevator", true) 
            break 
        end
    end
end

RegisterCommand('setlift', function()
    if myDimension == 0 then return end 
    if not HasKey() then TriggerEvent('chat:addMessage', { args = { '^1System', 'You do not have the keys for this property!' } }) return end 
    
    local houseData = Houses[myHouseId]
    if not houseData.lifts or #houseData.lifts == 0 then 
        TriggerServerEvent('myproperty:createFirstFloorLift', myHouseId, GetEntityCoords(PlayerPedId()))
    else 
        openLiftMenu() 
    end
end, false)

RegisterCommand('sl', function() ExecuteCommand('setlift') end, false)

Citizen.CreateThread(function()
    while true do
        local wait = 500
        if myDimension ~= 0 and Houses[myHouseId] and Houses[myHouseId].lifts then
            local ped = PlayerPedId() 
            local pCoords = GetEntityCoords(ped) 
            local houseData = Houses[myHouseId] 
            local liftMarkerPos = nil
            
            for _, floor in ipairs(houseData.lifts) do 
                if myDimension == floor.dim and floor.coords then 
                    liftMarkerPos = floor.coords 
                    break 
                end 
            end
            
            if liftMarkerPos then
                local dist = #(pCoords - vector3(liftMarkerPos.x, liftMarkerPos.y, liftMarkerPos.z))
                
                if dist < 5.0 then 
                    wait = 0
                    if showLiftMarker then 
                        DrawMarker(30, liftMarkerPos.x, liftMarkerPos.y, liftMarkerPos.z - 0.01, 0, 0, 0, 0, 0, 0, 0.60, 0.60, 0.80, 50, 150, 250, 150, false, false, false, false)
                    end
                    if dist < 1.5 then 
                        SetTextComponentFormat("STRING") 
                        AddTextComponentString("Press ~INPUT_CONTEXT~ to use Elevator") 
                        DisplayHelpTextFromStringLabel(0, 0, 1, -1)
                        if IsControlJustReleased(0, 38) then openLiftMenu() end
                    end
                end
            end
        end
        Citizen.Wait(wait)
    end
end)
