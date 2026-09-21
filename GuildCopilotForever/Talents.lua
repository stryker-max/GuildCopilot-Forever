local _, GC = ...

-- Same public group/currency model as Blizzard_PlayerSpells/Camelot in
-- build 69913. GetSpecializationInfo is not a Classic talent-tab reader.
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or GC.Client.IsSecret(value) then return nil end
    return value
end

local function Number(value)
    return not GC.Client.IsSecret(value) and type(value) == "number"
        and value == value and value ~= math.huge and value ~= -math.huge
end

function GC.Client.ReadTalentGroups(inspect)
    if GC.Client.InCombat() or not C_Traits then return nil end
    local configID
    if inspect then
        if Read(C_Traits.HasValidInspectData) ~= true then return nil end
        configID = Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
    else
        local api = C_SpecializationInfo
        local group = api and Read(api.GetActiveSpecGroup)
        if Number(group) then configID = Read(api.GetCombatConfigIDForSpecGroup, group) end
        if not Number(configID) and C_ClassTalents then
            configID = Read(C_ClassTalents.GetActiveConfigID)
        end
    end
    if not Number(configID) then return nil end
    -- Ignore uncommitted points while the user is editing their build.
    if not inspect and Read(C_Traits.ConfigHasStagedChanges, configID) == true then return nil end
    local config = Read(C_Traits.GetConfigInfo, configID)
    if type(config) ~= "table" or GC.Client.IsSecret(config.treeIDs)
        or type(config.treeIDs) ~= "table" then return nil end
    for _, treeID in ipairs(config.treeIDs) do
        if not Number(treeID) then return nil end
        local displays = Read(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
        if type(displays) == "table" and #displays == 3 then
            local ordered, ids, seen = {}, {}, {}
            for _, display in ipairs(displays) do
                if GC.Client.IsSecret(display) or type(display) ~= "table"
                    or not Number(display.groupID) or not Number(display.orderIndex)
                    or seen[display.groupID] then return nil end
                seen[display.groupID] = true
                ordered[#ordered + 1] = { id = display.groupID, order = display.orderIndex }
                ids[#ids + 1] = display.groupID
            end
            table.sort(ordered, function(a, b) return a.order < b.order end)
            if ordered[1].order == ordered[2].order or ordered[2].order == ordered[3].order then return nil end
            local currencies = Read(C_Traits.GetGroupCurrencyInfo, configID, ids)
            if type(currencies) ~= "table" then return nil end
            local byID = {}
            for _, group in ipairs(currencies) do
                if GC.Client.IsSecret(group) or type(group) ~= "table"
                    or not Number(group.traitNodeGroupID) or GC.Client.IsSecret(group.currencyInfos)
                    or type(group.currencyInfos) ~= "table" then return nil end
                local currency = group.currencyInfos[1]
                if GC.Client.IsSecret(currency) or type(currency) ~= "table"
                    or not Number(currency.spent) or currency.spent < 0 then return nil end
                byID[group.traitNodeGroupID] = currency.spent
            end
            local points = {}
            for index, group in ipairs(ordered) do
                if byID[group.id] == nil then return nil end
                points[index] = byID[group.id]
            end
            return points
        end
    end
    return nil
end
