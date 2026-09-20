local _, GC = ...

-- Verified against Blizzard's 1.60.1.69913 UI sources (Forever beta).
-- Keep compatibility inside this addon; never replace Blizzard globals.
local version, build, _, interface = "", "", nil, 0
if type(GetBuildInfo) == "function" then
    version, build, _, interface = GetBuildInfo()
end
local forever = type(version) == "string" and version:match("^1%.60%.") ~= nil
    or tonumber(interface) == 16000 or tonumber(interface) == 16001
GC.Client = {
    isForever = forever,
    version = version, build = build, interface = tonumber(interface) or 0,
    label = "WoW Forever Beta",
    maxLevel = 60,
    savedVariable = "GuildCopilotForeverDB",
    -- The legacy combat log reader is not part of Forever's public API.
    combatAnalysis = false,
    combatAnalysisReason = "WoW Forever Beta: Die bisherige Kampflog-Auswertung ist in diesem Client nicht verfügbar.",
}

function GC.Client.IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) or false
end

function GC.Client.HasSecretArguments(...)
    if not GC.Client.isForever then return false end
    for index = 1, select("#", ...) do
        if GC.Client.IsSecret(select(index, ...)) then return true end
    end
    return false
end

function GC.Client.InCombat()
    local fn = InCombatLockdown or (C_RestrictedActions and C_RestrictedActions.InCombatLockdown)
    return type(fn) == "function" and fn() or false
end

GC.API = {}
local apiNamespaces = { GetSpellInfo = "C_Spell", GetSkillLineInfo = "C_SkillInfo" }
function GC.API.Has(name)
    local namespace = apiNamespaces[name]
    return type(_G[name]) == "function"
        or (namespace and _G[namespace] and type(_G[namespace][name]) == "function") or false
end
local function Forward(name, namespace)
    apiNamespaces[name] = namespace
    GC.API[name] = function(...)
        local api = _G[namespace]
        local fn = (api and api[name]) or _G[name]
        if type(fn) == "function" then return fn(...) end
    end
end
Forward("GetItemInfo", "C_Item")
Forward("GetItemStats", "C_Item")
Forward("GetWeaponEnchantInfo", "C_Item")
Forward("PlaySound", "C_Sound")
Forward("GetNumSkillLines", "C_SkillInfo")
Forward("ExpandSkillHeader", "C_SkillInfo")
Forward("CollapseSkillHeader", "C_SkillInfo")
Forward("CanEditOfficerNote", "C_GuildInfo")

function GC.API.GetSpellInfo(spell)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spell)
        if info then
            return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID, info.originalIconID
        end
    elseif type(GetSpellInfo) == "function" then
        return GetSpellInfo(spell)
    end
end

function GC.API.GetSkillLineInfo(index)
    if C_SkillInfo and C_SkillInfo.GetSkillLineInfo then
        local info = C_SkillInfo.GetSkillLineInfo(index)
        if info then
            return info.name, info.isHeader, not info.isCollapsed, info.rank,
                info.tempPoints, info.modifier, info.maxRank, info.isAbandonable,
                info.stepCost, info.rankCost, info.minLevel, info.costType, info.description
        end
    elseif type(GetSkillLineInfo) == "function" then
        return GetSkillLineInfo(index)
    end
end

-- Unknown events raise at load time, preventing every subsequent module loading.
function GC.Client.RegisterEvent(frame, event)
    local ok = pcall(frame.RegisterEvent, frame, event)
    return ok
end
