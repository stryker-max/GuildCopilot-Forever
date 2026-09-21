return function(addon, check, secret)
    local globals = { "UnitExists", "UnitIsConnected", "UnitIsVisible", "UnitAffectingCombat", "IsInRaid",
        "UnitNameUnmodified", "C_UnitAuras", "C_Container", "C_Item", "C_InstanceEncounter", "InCombatLockdown", "GetNumGroupMembers" }
    local previous = {}
    for _, key in ipairs(globals) do previous[key] = _G[key] end
    local oldSnapshot = addon.DB:GetCharacter().foreverPreparation
    local blocked, secretAura = false, false
    InCombatLockdown = function() return blocked end
    IsInRaid = function() return false end
    UnitExists = function(unit) return unit == "player" or unit == "party1" or unit == "party2" end
    UnitIsConnected = function(unit) return unit ~= "party2" end
    UnitIsVisible = function() return true end
    UnitAffectingCombat = function() return false end
    UnitNameUnmodified = function(unit) return unit, "Forever" end
    local reads = 0
    C_UnitAuras = { GetAuraDataByIndex = function(unit, index)
        reads = reads + 1
        if secretAura then return { name = secret, spellId = secret } end
        if index == 1 then return { name = "Forever Testbuff", spellId = 123456 } end
    end }
    C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
        GetContainerItemInfo = function(bag, slot) return { itemID = slot == 1 and 111 or 222, stackCount = 5 } end,
    }
    C_Item = {
        GetItemInfoInstant = function(id) return id, "", "", "", 1, id == 111 and 0 or 7 end,
        GetItemNameByID = function() return "Forever Testvorrat" end,
    }
    C_InstanceEncounter = { IsEncounterInProgress = function() return false end }
    check(addon.RaidPreparation:Capture(), "Preparation capture failed")
    local snapshot = addon.RaidPreparation:GetSnapshot()
    check(#snapshot.members == 3 and snapshot.members[1].buffs[1].spellID == 123456, "Group buffs not captured")
    check(snapshot.members[3].state == "UNKNOWN", "Offline member reported unbuffed")
    check(#snapshot.supplies.items == 1 and snapshot.supplies.items[1].count == 5, "Non-consumable counted or supply lost")
    check(addon.RaidPreparation:ReportText():find("Benutzte Tränke, Elixiere und Essen: nicht erfasst.", 1, true),
        "Consumption claimed from inventory")
    blocked = true
    local before = reads
    check(not addon.RaidPreparation:Capture() and reads == before and addon.RaidPreparation:GetSnapshot() == snapshot,
        "Preparation read during combat or erased previous snapshot")
    blocked, secretAura = false, true
    addon.RaidPreparation:Capture()
    check(addon.RaidPreparation:GetSnapshot().members[1].state == "UNKNOWN", "Secret buffs interpreted as missing")
    C_Container.GetContainerItemInfo = function() return { itemID = secret, stackCount = secret } end
    addon.RaidPreparation:Capture()
    check(not addon.RaidPreparation:GetSnapshot().supplies.complete, "Secret bag contents treated as empty")
    C_InstanceEncounter.IsEncounterInProgress = function() return true end
    before = reads
    check(not addon.RaidPreparation:Capture() and reads == before, "Preparation read during encounter")
    addon.DB:Initialize()
    check(addon.RaidPreparation:GetSnapshot() ~= nil, "Preparation snapshot not retained")
    addon.UI:RefreshStatistics()
    check(addon.UI.pages.STATISTICS.preparationText:GetText():find("unbekannt", 1, true), "Unknown preparation not shown")
    C_InstanceEncounter.IsEncounterInProgress = function() return false end
    IsInRaid = function() return true end
    GetNumGroupMembers = function() return 40 end
    check(addon.RaidPreparation:Capture() and #addon.RaidPreparation:GetSnapshot().members == 40,
        "Raid roster truncated or player duplicated")
    snapshot = addon.RaidPreparation:GetSnapshot()
    GetNumGroupMembers = function() return secret end
    check(not addon.RaidPreparation:Capture() and addon.RaidPreparation:GetSnapshot() == snapshot,
        "Protected raid roster replaced previous snapshot")
    for _, key in ipairs(globals) do _G[key] = previous[key] end
    addon.DB:GetCharacter().foreverPreparation = oldSnapshot
end
