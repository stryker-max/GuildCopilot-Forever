local _, GC = ...

-- A preparation snapshot, never a reconstructed combat log or a use counter.
GC.RaidPreparation = {}
local MAX_AURAS = 100

local function Read(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, ...)
    if not ok or GC.Client.IsSecret(value) then return false end
    return true, value
end

local function Number(value)
    return not GC.Client.IsSecret(value) and type(value) == "number"
        and value == value and value >= 0 and value < math.huge
end

local function ReadMember(unit)
    local ok, name = pcall(GC.Util.UnitIdentityName, unit)
    local member = { name = ok and name or nil, buffs = {}, state = "UNKNOWN" }
    member.name = member.name or unit
    local exists, present = Read(UnitExists, unit)
    local connected, online = Read(UnitIsConnected, unit)
    local visible, inView = Read(UnitIsVisible, unit)
    local combatOK, combat = Read(UnitAffectingCombat, unit)
    if not exists or not present or not connected or not online
        or not visible or not inView or not combatOK or combat then return member end
    local reader = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    for index = 1, MAX_AURAS do
        local readable, aura = Read(reader, unit, index, "HELPFUL")
        if not readable then return member end
        if aura == nil then member.state = "READABLE"; return member end
        if type(aura) ~= "table" or GC.Client.HasSecretArguments(aura.name, aura.spellId)
            or type(aura.name) ~= "string" or not Number(aura.spellId) then return member end
        member.buffs[#member.buffs + 1] = { name = aura.name, spellID = aura.spellId }
    end
    return member -- truncated/partially protected lists remain unknown
end

local function ReadSupplies()
    local supplies = { items = {}, complete = true }
    local api = C_Container
    if not api or not C_Item or type(C_Item.GetItemInfoInstant) ~= "function" then
        supplies.complete = false; return supplies
    end
    local counts = {}
    local lastBag = Number(NUM_BAG_SLOTS) and math.min(NUM_BAG_SLOTS, 10) or 4
    for bag = 0, lastBag do
        local ok, slots = Read(api.GetContainerNumSlots, bag)
        if not ok or not Number(slots) or slots > 200 then
            supplies.complete = false
        else
            for slot = 1, slots do
                local readable, info = Read(api.GetContainerItemInfo, bag, slot)
                if not readable then supplies.complete = false
                elseif info ~= nil then
                    if type(info) ~= "table" or not Number(info.itemID) or not Number(info.stackCount) then
                        supplies.complete = false
                    else
                        local itemOK, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, info.itemID)
                        if not itemOK or not Number(classID) then supplies.complete = false
                        elseif classID == 0 then -- documented ItemClass.Consumable
                            counts[info.itemID] = (counts[info.itemID] or 0) + info.stackCount
                        end
                    end
                end
            end
        end
    end
    for itemID, count in pairs(counts) do
        local ok, name = Read(C_Item.GetItemNameByID, itemID)
        supplies.items[#supplies.items + 1] = {
            itemID = itemID, count = count,
            name = ok and type(name) == "string" and name or ("Gegenstand #" .. itemID),
        }
    end
    table.sort(supplies.items, function(a, b) return a.itemID < b.itemID end)
    return supplies
end

function GC.RaidPreparation:Capture()
    if GC.Client.InCombat() then return false, "Vorbereitung bitte außerhalb des Kampfes erfassen." end
    if C_InstanceEncounter and type(C_InstanceEncounter.IsEncounterInProgress) == "function" then
        local ok, active = Read(C_InstanceEncounter.IsEncounterInProgress)
        if not ok or active then return false, "Während eines Bossversuchs wird keine Vorbereitung erfasst." end
    end
    local snapshot = { capturedAt = GC.Util.Now(), members = {}, supplies = ReadSupplies(), source = "FOREVER_PREPARATION" }
    local inRaid, raid = Read(IsInRaid)
    if inRaid and raid then
        local ok, count = Read(GetNumGroupMembers)
        if not ok or not Number(count) or count < 1 or count > 40 then return false, "Raidliste derzeit nicht lesbar." end
        for index = 1, count do snapshot.members[#snapshot.members + 1] = ReadMember("raid" .. index) end
    else
        snapshot.members[1] = ReadMember("player")
        for index = 1, 4 do
            local ok, exists = Read(UnitExists, "party" .. index)
            if ok and exists then snapshot.members[#snapshot.members + 1] = ReadMember("party" .. index) end
        end
    end
    -- Local, per-character and saved by WoW. No inventory disclosure via sync.
    GC.DB:GetCharacter().foreverPreparation = snapshot
    return true, "Vorbereitung erfasst. Aktive Buffs und Vorräte sind kein Verbrauchsnachweis."
end

function GC.RaidPreparation:GetSnapshot()
    return GC.DB:GetCharacter().foreverPreparation
end

function GC.RaidPreparation:ReportText()
    local snapshot = self:GetSnapshot()
    if not snapshot then return "Noch kein Check. Vor dem Pull außerhalb des Kampfes auf „Vorbereitung erfassen“ klicken." end
    local lines = {
        "Momentaufnahme: " .. (date and date("%d.%m.%Y %H:%M", snapshot.capturedAt) or tostring(snapshot.capturedAt)),
        "Keine Pflichtbewertung: Alle lesbaren hilfreichen Effekte, einschließlich Klassenbuffs.", "",
    }
    for _, member in ipairs(snapshot.members or {}) do
        local names = {}
        if member.state == "READABLE" then
            for _, buff in ipairs(member.buffs or {}) do names[#names + 1] = buff.name end
        end
        lines[#lines + 1] = member.name .. ": " .. (member.state ~= "READABLE" and "unbekannt (nicht vollständig lesbar)"
            or (#names > 0 and table.concat(names, ", ") or "keine aktiven hilfreichen Effekte erkannt"))
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Eigene mitgeführte Verbrauchsgegenstände (keine fremden Taschen):"
    for _, item in ipairs(snapshot.supplies.items or {}) do
        lines[#lines + 1] = item.name .. " ×" .. item.count
    end
    if not snapshot.supplies.complete then lines[#lines + 1] = "Bestand unvollständig lesbar – fehlende Gegenstände sind unbekannt." end
    if #snapshot.supplies.items == 0 and snapshot.supplies.complete then lines[#lines + 1] = "Keine erkannt." end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Benutzte Tränke, Elixiere und Essen: nicht erfasst. Bestandsabnahmen beweisen keinen Verbrauch."
    return table.concat(lines, "\n")
end
