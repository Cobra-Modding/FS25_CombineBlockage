-- ============================================================
-- FS25_CombineBlockageRegister.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis.
-- ============================================================

local modName = g_currentModName
local combineSpecializationName = modName .. ".combineBlockage"

local function injectCombineBlockage(typeManager)
    if typeManager.typeName ~= "vehicle" then
        return
    end

    for typeName, typeEntry in pairs(g_vehicleTypeManager.types) do
        if SpecializationUtil.hasSpecialization(Combine, typeEntry.specializations)
            and SpecializationUtil.hasSpecialization(Drivable, typeEntry.specializations)
            and SpecializationUtil.hasSpecialization(Motorized, typeEntry.specializations) then
            g_vehicleTypeManager:addSpecialization(typeName, combineSpecializationName)
        end
    end
end

TypeManager.validateTypes = Utils.appendedFunction(TypeManager.validateTypes, injectCombineBlockage)
