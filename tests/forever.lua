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
Constants = {
    CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = "-" },
    TraitConsts = { INSPECT_TRAIT_CONFIG_ID = -1 },
}
function UnitLevel() return 20 end
function UnitNameUnmodified(unit) return UnitFullName(unit) end
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
GetTalentTabInfo = nil
local talentPoints = { 0, 11, 0 }
local inspectValid, stagedTalents = true, false
C_SpecializationInfo = {
    GetActiveSpecGroup = function() return 1 end,
    GetCombatConfigIDForSpecGroup = function(group) return group == 1 and 101 or 102 end,
    GetSpecializationInfo = function() error("Not a Forever talent-tab reader") end,
}
C_Traits = {
    HasValidInspectData = function() return inspectValid end,
    ConfigHasStagedChanges = function() return stagedTalents end,
    GetConfigInfo = function(id) return { treeIDs = { 900 } } end,
    -- Shuffled deliberately: display order and returned currency order differ.
    GetGroupDisplayInfoByTreeID = function() return {
        { groupID = 30, orderIndex = 2 }, { groupID = 10, orderIndex = 0 }, { groupID = 20, orderIndex = 1 },
    } end,
    GetGroupCurrencyInfo = function() return {
        { traitNodeGroupID = 20, currencyInfos = { { spent = talentPoints[2] } } },
        { traitNodeGroupID = 30, currencyInfos = { { spent = talentPoints[3] } } },
        { traitNodeGroupID = 10, currencyInfos = { { spent = talentPoints[1] } } },
    } end,
}
-- Removed public legacy APIs must not accidentally keep the test working.
CombatLogGetCurrentEventInfo = nil
GetTradeSkillLine, GetNumTradeSkills, GetTradeSkillInfo = nil, nil, nil
GetCraftInfo, GetNumCrafts, GetCraftSkillLine, GetCraftDisplaySkillLine = nil, nil, nil, nil
local crafted
C_TradeSkillUI = {
    GetProfessionInfoBySkillLineID = function(id) return { skillLevel = 75, maxSkillLevel = 150 } end,
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
check(SLASH_GUILDCOPILOTFOREVER1 == "/gcp" and SLASH_GUILDCOPILOTFOREVER2 == "/guildcopilot"
    and type(SlashCmdList.GUILDCOPILOTFOREVER) == "function", "Guild Copilot commands changed")
check(addon.Util.PlayerKey("Same-FamilyOne") ~= addon.Util.PlayerKey("Same-FamilyTwo"), "Surnames collide")
check(addon.Util.PlayerKey("Tester") ~= addon.Util.PlayerKey("Tester-Realm"), "Missing surname was invented")
check(addon.Roster:GetProfile("Tester-Realm") == addon.Profile:Get(), "Own full-name profile lookup failed")
check(addon.Roster:GetProfile("Tester") == nil, "First name matched a full identity")
check(addon.Util.PlayerKey("Ana Bel") ~= addon.Util.PlayerKey("An Abel"), "Name boundaries discarded")
check(addon.Chat:CanonicalLeadName("Tester") == "tester", "Inbox invented a surname")
check(addon.DB:GetGuild().profile.progress == "", "TBC progress default leaked into Forever")
do
    local guild = addon.DB:GetGuild()
    guild.profile.progress, guild.profile.updatedAt = "SSC/TK", 0
    addon.DB.guildCache = nil
    check(addon.DB:GetGuild().profile.progress == "", "Untouched beta.1 progress not migrated")
    guild.profile.progress, guild.profile.updatedAt = "Eigener Fortschritt", 1
    addon.DB.guildCache = nil
    check(addon.DB:GetGuild().profile.progress == "Eigener Fortschritt", "Edited progress overwritten")
end
check(not addon.Recruitment:GenerateReply("INFO", "Other-Family"):find("SSC/TK", 1, true), "TBC progress in reply")
do
    local separator = Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR
    Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR = " "
    check(addon.Util.JoinPlayerName("Ana", "Forever") == "Ana Forever", "Client name separator ignored")
    check(addon.Util.JoinPlayerName("Ana Forever", "Forever") == "Ana Forever", "Surname doubled")
    check(addon.Util.JoinPlayerName(secret, "Forever") == nil, "Secret name evaluated")
    Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR = nil
    check(addon.Util.JoinPlayerName("Ana", "Forever") == nil, "Missing separator guessed")
    Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR = separator
end
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
do
    local previousMembers = addon.Roster.members
    local previousRules = addon.Roster.GetRaiderRules
    addon.Roster.GetRaiderRules = function()
        return { rankFilterConfigured = true, activeRaiderRanks = { ["1"] = true } }
    end
    addon.Roster.members = {
        { name = "Low", level = 10, rankIndex = 1, online = true },
        { name = "High", level = 60, rankIndex = 1, online = false },
        { name = "Excluded", level = 60, rankIndex = 2, online = true },
    }
    local visible = addon.Roster:GetActiveRaiders(50)
    check(#visible == 2 and visible[1].name == "Low" and visible[2].name == "High",
        "Overview filtered lower levels or lost rank filter/activity ordering")
    addon.Roster.members, addon.Roster.GetRaiderRules = previousMembers, previousRules
end
check(#addon.RaidInstances == 0 and addon.RaidSearch:NewPlan().zone == "", "TBC raid preset in Forever")
check(addon.API.GetSpellInfo(2963) == "Spell 2963", "SpellInfo table not adapted")
check(addon.API.GetItemInfo(14048) == "Runenstoffballen", "Namespaced item API not used")
addon.Profile:RefreshProfessions()
local profile = addon.Profile:Get()
check(profile.professionSource == "OK" and profile.professions[1].skillLevel == 75,
    "Forever profession book rank not detected")
check(not skillHeaderExpanded, "Skill header was not restored")
do
    local getProfessions, getProfessionInfo = GetProfessions, GetProfessionInfo
    GetProfessions, GetProfessionInfo = nil, nil
    addon.Profile:RefreshProfessions()
    check(profile.professionSource == "OK" and not skillHeaderExpanded, "Skill-line fallback failed")
    GetProfessions, GetProfessionInfo = getProfessions, getProfessionInfo
    addon.Profile:RefreshProfessions()
end
local spec, signature = addon.Profile:DetectTalentSpec()
check(spec == "HUNTER:2" and signature == "0/11/0", "Forever group talent points not detected")
check(addon.Profile:DetectTalentSpecForUnit("player") ~= nil, "Modern inspect talent points not detected")
check(addon.Profile:DetectTalentSpecForUnit("party1") == "HUNTER:2", "Low-level inspected talents rejected")
inspectValid = false
check(addon.Profile:DetectTalentSpecForUnit("party1") == nil, "Invalid inspect data accepted")
inspectValid = true
stagedTalents = true
check(addon.Profile:DetectTalentSpec() == nil, "Uncommitted talents published")
stagedTalents = false
talentPoints[2] = secret
check(addon.Profile:DetectTalentSpec() == nil, "Secret talent data evaluated")
talentPoints[2] = 11
talentPoints[1] = 11
check(addon.Profile:DetectTalentSpec() == nil, "Tied build guessed as one spec")
talentPoints[1] = 0
check(addon.Workshop:ScanOpenProfession(), "Modern profession scan failed")
local profession = addon.Workshop:GetOwnProfession("Tailoring")
local recipe = profession and profession.recipes.I2996
check(recipe and recipe.recipeID == 2963, "Known recipe not stored")
check(recipe.reagents[1].itemID == 2589 and recipe.reagents[1].count == 2, "Modern reagents not stored")
local count = 0
for _ in pairs(profession.recipes) do count = count + 1 end
check(count == 1, "Unlearned recipe stored")
do
    -- UTF-8 first/surnames can exceed a display-oriented byte budget.
    local crafter = "Éléonorianne-ÉléonorianneÉléonorianne"
    check(#crafter > 40 and #crafter <= 96, "Long identity fixture is not long")
    for _, builder in ipairs({ addon.Workshop.BuildProfessionMessages, function(self, data, compact, name)
        return self:BuildKeyListMessages(data, name)
    end }) do
        local messages = builder(addon.Workshop, profession, true, crafter)
        check(#messages > 0, "Long identity transfer empty")
        for _, message in ipairs(messages) do
            local fields = addon.Util.SplitFields(message)
            check(fields[12] == crafter and #message <= 255, "Identity truncated or packet oversized")
            addon.Workshop:ReceiveSync(fields, "Relay-Family", "GUILD")
        end
        local received = addon.Workshop:GetGuildWorkshop().crafters[addon.Util.PlayerKey(crafter)]
        check(received and received.name == crafter, "Crafter identity lost on receipt")
    end
    local oversized = addon.Util.DeepCopy(profession)
    oversized.name = string.rep("x", 300)
    check(#addon.Workshop:BuildKeyListMessages(oversized, crafter) == 0, "Invalid payload budget not rejected")
    local cooldowns = {}
    local longName = string.rep("a", 47) .. "-" .. string.rep("b", 48)
    for index = 1, 20 do
        cooldowns[index] = { key = "I123456" .. index, readyAt = addon.Util.Now() + 3600 }
    end
    local messages = addon.Workshop:BuildCooldownMessages(longName, cooldowns)
    check(#messages > 1, "Long-name cooldowns were not split")
    for _, message in ipairs(messages) do
        check(#message <= 255, "Cooldown packet oversized")
        addon.Workshop:ReceiveSync(addon.Util.SplitFields(message), "Relay-Family", "GUILD")
    end
    local stored = addon.Workshop:GetGuildWorkshop().crafters[addon.Util.PlayerKey(longName)]
    local receivedCount = 0
    for _ in pairs(stored and stored.cooldowns or {}) do receivedCount = receivedCount + 1 end
    check(receivedCount == 20, "Cooldown entries lost in transport")
    local large = addon.Util.DeepCopy(profession)
    large.updatedAt = addon.Util.Now() + 1
    large.fingerprint, large.fingerprintHash = nil, nil
    large.recipes = { I987654 = { key = "I987654", itemID = 987654, name = "Large recipe", reagents = {} } }
    for index = 1, 25 do
        large.recipes.I987654.reagents[index] = { itemID = 987000 + index, count = index }
    end
    for _, compact in ipairs({ true, false }) do
        addon.Workshop:GetGuildWorkshop().catalog.I987654 = nil
        local packets = addon.Workshop:BuildProfessionMessages(large, compact, longName)
        check(#packets > 1, "Large recipe did not span packets")
        for index = #packets, 1, -1 do
            check(#packets[index] <= 255, "Large recipe packet oversized")
            addon.Workshop:ReceiveSync(addon.Util.SplitFields(packets[index]), "Relay-Family", "GUILD")
        end
        local recipe = addon.Workshop:GetGuildWorkshop().catalog.I987654
        check(recipe and #recipe.reagents == 25 and recipe.reagents[25].count == 25,
            "Recipe transport silently discarded materials")
    end
    addon.Workshop:ReceiveSync({ "W", tostring(addon.Constants.SCHEMA_VERSION), "C", "legacy-fixture",
        "1", "1", "tailoring", "Schneiderei", "I987655,,2589:2", tostring(addon.Util.Now()), "1", longName },
        "Relay-Family", "GUILD")
    local legacyRecipe = addon.Workshop:GetGuildWorkshop().catalog.I987655
    check(legacyRecipe and legacyRecipe.reagents[1].count == 2, "Legacy recipe packet stopped working")
end
local orderOK, orderMessage = addon.Orders:Create("I2996", { quantity = 2, materialModel = "A" })
check(orderOK, "Crafting order failed: " .. tostring(orderMessage))
-- Long realm-qualified identities must survive reservation and packet round trips.
do
    local owner = "Requester-VeryLongForeverRealmName"
    local crafter = "Artisan-AnotherLongForeverRealmName"
    local originalCatalog = addon.Workshop.GetCatalogEntry
    addon.Workshop.GetCatalogEntry = function()
        return { name = "Bolt of Linen Cloth", crafters = { crafter } }
    end
    check(addon.Orders:Create("I2996", { preferredCrafter = crafter }), "Long-name reservation rejected")
    addon.Workshop.GetCatalogEntry = originalCatalog
    local reserved
    for _, order in pairs(addon.Orders:GetStore()) do
        if order.preferredCrafter ~= "" then reserved = order end
    end
    check(reserved and reserved.preferredCrafter == crafter, "Reserved crafter name truncated locally")
    local packet = {
        id = "long-realm-order", recipeKey = "I2996", recipeName = "Bolt of Linen Cloth",
        createdBy = owner, createdByTag = "longtag", createdAt = addon.Util.Now(),
        preferredCrafter = crafter, crafter = crafter, acceptedVia = crafter,
        rev = 1, status = "ACCEPTED", acceptedByTag = "crafttag", acceptedAt = addon.Util.Now(),
    }
    for _, message in ipairs(addon.Orders:BuildTransportMessages(addon.Orders:BuildCoreMessage(packet))) do
        addon.Orders:OnMessage(message, owner, "GUILD")
    end
    local received = addon.Orders:GetOrder(packet.id)
    check(received and received.createdBy == owner, "Order creator realm truncated on receipt")
    check(received.preferredCrafter == crafter, "Reserved crafter realm truncated on receipt")
    for _, message in ipairs(addon.Orders:BuildTransportMessages(addon.Orders:BuildStateMessage(packet))) do
        addon.Orders:OnMessage(message, crafter, "GUILD")
    end
    check(received.crafter == crafter and received.acceptedVia == crafter, "Accepted crafter realm truncated")
    check(received.log[1].by == owner, "Order history discarded creator realm")
end
addon.Workshop:CraftOpenRecipe("I2996", 2)
check(crafted and crafted[1] == 2963 and crafted[2] == 2, "Modern crafting not used")
do
    local craft = C_TradeSkillUI.CraftRecipe
    C_TradeSkillUI.CraftRecipe = function() error("Client rejected craft") end
    local ok, message = addon.Workshop:CraftOpenRecipe("I2996", 1)
    check(ok == false and message:find("abgewiesen", 1, true), "Failed craft reported success")
    C_TradeSkillUI.CraftRecipe = craft
end
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
do
    local before = #sentAddon
    local throttle = _G.ChatThrottleLib
    _G.ChatThrottleLib = { SendAddonMessage = function() error("Restricted CTL dispatch attempted") end }
    C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function() return true end
    check(not addon.Sync:Send("test", "GUILD") and #sentAddon == before, "Restricted addon send attempted")
    local completed
    check(addon.Sync:SendBulk("restricted-queue-test", "GUILD", nil, function(ok) completed = ok end),
        "Restricted packet could not be queued")
    for _ = 1, 12 do addon.Sync:PumpBulk(5) end
    check(completed == nil and #sentAddon == before, "Restricted queue lost or dispatched a packet")
    _G.ChatThrottleLib = throttle
    C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = nil
    addon.Sync:PumpBulk(5)
    check(completed == true, "Paused packet did not resume")
end
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
assert(loadfile("tests/inbox.lua"))()(addon, check, Fire, secret)
assert(loadfile("tests/raid-preparation.lua"))()(addon, check, secret)
assert(loadfile("tests/minimap.lua"))()(addon, check)
assert(loadfile("tests/guild-profile.lua"))()(addon, check)
assert(loadfile("tests/guild-profile-send.lua"))()(addon, check)
print("Forever: " .. checks .. " checks passed (API fixture 1.60.1.69913)")
