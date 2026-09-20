-- Contract fixture: Blizzard UI source 1.60.1.69913, not a real client test.
dofile("tests/wow-stubs.lua")
-- Real timers never recurse synchronously. Keep delayed login/background work
-- queued; the actions under test are invoked explicitly below.
timerDelayThreshold = 0
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, message)
end
function GetBuildInfo() return "1.60.1", "69913", "Sep 18 2026", 16001 end
local secret = {}
function issecretvalue(value) return rawequal(value, secret) end
local errors = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message)
    if message:find("Fehler in", 1, true) then errors[#errors + 1] = message end
end }
local frames = {}
local classicFrame = CreateFrame
function CreateFrame(...)
    local frame = classicFrame(...)
    frame.registeredEvents = {}
    function frame:RegisterEvent(event)
        if event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" or event == "CRAFT_CLOSE"
            or event == "TRADE_SKILL_UPDATE" or event == "COMBAT_LOG_EVENT_UNFILTERED" then
            error("Removed or unavailable Forever event: " .. event)
        end
        self.registeredEvents[event] = true
    end
    frames[#frames + 1] = frame
    return frame
end
local function Fire(event, ...)
    for _, frame in ipairs(frames) do
        if frame.registeredEvents[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

C_Item = { GetItemInfo = GetItemInfo, GetItemStats = GetItemStats }
C_Sound = { PlaySound = PlaySound }
C_Spell = { GetSpellInfo = function(id) return { name = "Spell " .. tostring(id), spellID = id, iconID = 123, castTime = 0 } end }
C_RestrictedActions = { InCombatLockdown = InCombatLockdown }
GetItemInfo, GetItemStats, GetSpellInfo, PlaySound = nil, nil, nil, nil
local oldNum, oldSkill = GetNumSkillLines, GetSkillLineInfo
C_SkillInfo = {
    GetNumSkillLines = oldNum,
    ExpandSkillHeader = ExpandSkillHeader,
    CollapseSkillHeader = CollapseSkillHeader,
    GetSkillLineInfo = function(index)
        local name, header, expanded, rank, temp, modifier, maximum = oldSkill(index)
        if name then return { name = name, isHeader = header, isCollapsed = not expanded,
            rank = rank, tempPoints = temp, modifier = modifier, maxRank = maximum } end
    end,
}
GetNumSkillLines, GetSkillLineInfo, ExpandSkillHeader, CollapseSkillHeader = nil, nil, nil, nil
GetProfessions, GetProfessionInfo, GetTalentTabInfo = nil, nil, nil
local talentPoints = { 0, 31, 0 }
C_SpecializationInfo = { GetSpecializationInfo = function(index, inspect)
    return index, "Talent", "", 1, "DAMAGER", 1, talentPoints[index]
end }
-- Removed public legacy APIs must not accidentally keep the test working.
CombatLogGetCurrentEventInfo = nil
GetTradeSkillLine, GetNumTradeSkills, GetTradeSkillInfo = nil, nil, nil
GetCraftInfo, GetNumCrafts, GetCraftSkillLine, GetCraftDisplaySkillLine = nil, nil, nil, nil
local crafted
C_TradeSkillUI = {
    IsTradeSkillReady = function() return true end,
    GetBaseProfessionInfo = function() return { professionName = "Tailoring", skillLevel = 100, maxSkillLevel = 150 } end,
    GetAllRecipeIDs = function() return { 2963, 999999 } end,
    GetRecipeInfo = function(id) return { name = "Bolt of Linen Cloth", learned = id == 2963 } end,
    GetRecipeItemLink = function(id) return "|cffffffff|Hitem:2996::::::::20|h[Bolt of Linen Cloth]|h|r" end,
    GetRecipeSchematic = function(id) return { reagentSlotSchematics = {
        { quantityRequired = 2, reagents = { { itemID = 2589 } } },
    } } end,
    GetRecipeCooldown = function() return 0 end,
    CraftRecipe = function(id, count) crafted = { id, count } end,
}
local oldSlots, oldLink, oldInfo = GetContainerNumSlots, GetContainerItemLink, GetContainerItemInfo
C_Container = {
    GetContainerNumSlots = oldSlots, GetContainerItemLink = oldLink,
    GetContainerItemInfo = function(bag, slot)
        local _, count = oldInfo(bag, slot)
        if count then return { stackCount = count } end
    end,
}
GetContainerNumSlots, GetContainerItemLink, GetContainerItemInfo = nil, nil, nil
GuildCopilotDB = { sentinel = "TBC data must remain intact" }
local tbc = GuildCopilotDB
local addon = LoadAddonFrom(FOREVER_ADDON_DIR or "GuildCopilotForever")
Fire("ADDON_LOADED", "GuildCopilotForever")
Fire("PLAYER_LOGIN")
check(#errors == 0, "Startup callback failed: " .. table.concat(errors, "; "))
check(addon.Client.isForever and addon.Constants.INTERFACE_VERSION == 16001, "Wrong client detection")
check(GuildCopilotDB == tbc and tbc.sentinel ~= nil and tbc.settings == nil, "TBC SavedVariables overwritten")
check(addon.DB.data == GuildCopilotForeverDB and addon.DB.data ~= tbc, "Forever storage not isolated")
local saved = GuildCopilotForeverDB
saved.settings.window.alpha = 73
addon.DB:Initialize()
check(addon.DB.data.settings.window.alpha == 73, "Existing Forever settings lost on reinitialization")
check(addon.Constants.COMM_PREFIX == "GCPForever", "Shared TBC communication prefix")
check(GuildCopilotForever == addon and GuildCopilot == nil, "TBC addon namespace overwritten")
check(SLASH_GUILDCOPILOTFOREVER1 == "/gcpf" and SlashCmdList.GUILDCOPILOT == nil, "TBC slash command overwritten")
check(addon.Util.PlayerKey("Same-RealmOne") ~= addon.Util.PlayerKey("Same-RealmTwo"), "Cross-realm identities collide")
check(addon.Util.PlayerKey("Tester") == addon.Util.PlayerKey("Tester-Realm"), "Local realm name not canonical")
check(addon.Roster:GetProfile("Tester") == addon.Profile:Get(), "Own short-name profile lookup failed")
do
    local fullName = UnitFullName
    UnitFullName = function(unit) return "Same", unit == "party1" and "RealmOne" or "RealmTwo" end
    check(addon.Util.UnitIdentityName("party1") == "Same-RealmOne", "Unit realm discarded")
    check(addon.Util.UnitIdentityName("party2") == "Same-RealmTwo", "Unit realm conflated")
    UnitFullName = fullName
end
check(addon.WarcraftLogs == nil, "TBC logs module loaded in Forever")
check(next(addon.EnchantRuleSet.rules) == nil and addon.DefaultContentPhase == "FOREVER_BETA", "TBC rules leaked")
check(not addon.DB:GetSettings().gearAudit.acceptUnratedEnchants, "Unverified enchants silently marked good")
check(not addon.RaidMonitor:BeginSession() and not addon.RaidMonitor:StartSession("s", "Tester", 100, "Zone"), "Unavailable combat analysis started")
check(addon.RaidMonitor.session == nil, "Fake raid session exists")
check(addon.Roster:CountsAsActiveRaider({level=60}) and not addon.Roster:CountsAsActiveRaider({level=59}), "Forever level cap wrong")
check(#addon.RaidInstances == 0 and addon.RaidSearch:NewPlan().zone == "", "TBC raid preset in Forever")
check(addon.API.GetSpellInfo(2963) == "Spell 2963", "SpellInfo table not adapted")
check(addon.API.GetItemInfo(14048) == "Runenstoffballen", "Namespaced item API not used")
addon.Profile:RefreshProfessions()
local profile = addon.Profile:Get()
check(profile.professionSource == "OK", "Namespaced skills not detected")
check(not skillHeaderExpanded, "Skill header was not restored")
local spec, signature = addon.Profile:DetectTalentSpec()
check(spec ~= nil and signature == "0/31/0", "Modern talent points not detected")
check(addon.Profile:DetectTalentSpecForUnit("player") ~= nil, "Modern inspect talent points not detected")
talentPoints[2] = secret
check(addon.Profile:DetectTalentSpec() == nil, "Secret talent data evaluated")
talentPoints[2] = 31
check(addon.Workshop:ScanOpenProfession(), "Modern profession scan failed")
local profession = addon.Workshop:GetOwnProfession("Tailoring")
local recipe = profession and profession.recipes.I2996
check(recipe and recipe.recipeID == 2963, "Known recipe not stored")
check(recipe.reagents[1].itemID == 2589 and recipe.reagents[1].count == 2, "Modern reagents not stored")
local count = 0
for _ in pairs(profession.recipes) do count = count + 1 end
check(count == 1, "Unlearned recipe stored")
local orderOK, orderMessage = addon.Orders:Create("I2996", { quantity = 2, materialModel = "A" })
check(orderOK, "Crafting order failed: " .. tostring(orderMessage))
addon.Workshop:CraftOpenRecipe("I2996", 2)
check(crafted and crafted[1] == 2963 and crafted[2] == 2, "Modern crafting not used")
addon.Inventory:ScanBags()
check(addon.Inventory:GetOwnStore().bags.counts[22445] == 20, "Namespaced bag contents lost")
local scans = 0
local schedule = addon.Workshop.ScheduleScan
addon.Workshop.ScheduleScan = function() scans = scans + 1 end
Fire("TRADE_SKILL_LIST_UPDATE")
Fire("TRADE_SKILL_DATA_SOURCE_CHANGED")
Fire("NEW_RECIPE_LEARNED")
check(scans == 3, "Modern profession events not connected")
addon.Workshop.ScheduleScan = schedule
Fire("CHAT_MSG_WHISPER", secret, "Other-Realm")
Fire("CHAT_MSG_ADDON", "GCPForever", secret, "GUILD", "Other-Realm")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", secret)
check(#errors == 0, "Secret payload caused an error")
addon.UI:CreateMainFrame()
addon.UI.frame:Show()
addon.UI:Refresh()
for _, tab in ipairs(addon.UI.tabs) do addon.UI:ShowPage(tab.key) end
check(addon.UI.pages.WCL == nil, "TBC logs page visible")
check(addon.UI.pages.STATISTICS.sessionButton == nil, "Unavailable analysis button visible")
check(#errors == 0, "UI callback failed: " .. table.concat(errors, "; "))
check(addon.Sync:AnnounceVersion(false, 0), "Version handshake not sent")
addon.Sync:SendProfile()
check(#sentAddon >= 2, "Sync checks did not exercise actual sends")
local wireProfile = addon.Sync:BuildProfileMessage()
addon.Sync:OnMessage("GCPForever", wireProfile, "GUILD", "Same-RealmOne")
addon.Sync:OnMessage("GCPForever", wireProfile, "GUILD", "Same-RealmTwo")
check(addon.Roster:GetProfile("Same-RealmOne") ~= nil and addon.Roster:GetProfile("Same-RealmTwo") ~= nil,
    "Cross-realm profile sync dropped a sender")
check(addon.Roster:GetProfile("Same-RealmOne") ~= addon.Roster:GetProfile("Same-RealmTwo"),
    "Cross-realm sync merged two characters")
addon.Sync:OnMessage("GuildCopilot", wireProfile, "GUILD", "TBC-Realm")
check(addon.Roster:GetProfile("TBC-Realm") == nil, "TBC packet accepted")
for _, msg in ipairs(sentAddon) do check(msg[1] == "GCPForever", "Packet used TBC prefix") end
print("Forever: " .. checks .. " checks passed (API fixture 1.60.1.69913)")
