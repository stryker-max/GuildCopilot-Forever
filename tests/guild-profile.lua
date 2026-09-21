return function(addon, check)
    local guild = addon.DB:GetGuild()
    local oldProfile = addon.Util.DeepCopy(guild.profile)
    local oldTemplates = addon.Util.DeepCopy(guild.replyTemplates)
    local oldRecruitment = addon.Util.DeepCopy(guild.recruitment)
    local oldPlan = addon.RaidSearch:GetData().plan
    local permission = addon.Roster.CanEditGuildProfile
    addon.Roster.CanEditGuildProfile = function() return true end
    guild.profile.enabled, guild.profile.disabledFields = true, {}
    guild.profile.description, guild.profile.raidTimes = "Zusammen spielen", "Dienstag 20 Uhr"
    guild.profile.progress, guild.profile.lootSystem = "Testprogress", "Testloot"
    guild.profile.discord, guild.profile.contact = "discord.example/test", "Ansprechpartner"
    check(addon.Recruitment:GenerateAdvertisement():find("Dienstag", 1, true), "Active raid times missing")
    guild.profile.disabledFields = { raidTimes = true, progress = true, lootSystem = true, discord = true, contact = true }
    check(not addon.Recruitment:GenerateAdvertisement():find("Dienstag", 1, true), "Disabled raid times in ad")
    check(guild.profile.raidTimes == "Dienstag 20 Uhr", "Disabled field value erased")
    guild.replyTemplates.INFO = "{beschreibung} Raidzeiten: {raidzeiten}. Lootsystem: {loot}. Progress: {progress}."
    local reply = addon.Recruitment:GenerateReply("INFO", "Tester")
    check(reply:find("Zusammen spielen", 1, true) and not reply:find("Raidzeiten", 1, true)
        and not reply:find("Testloot", 1, true), "Default reply included disabled fields/empty labels")
    check(addon.Recruitment:GenerateReply("DISCORD", "Tester") == "", "Disabled Discord reply generated")
    guild.replyTemplates.INFO = "Hallo {name}! Loot: {loot}. Kontakt: {kontakt}. Willkommen!"
    reply = addon.Recruitment:GenerateReply("INFO", "Tester")
    check(reply:find("Hallo", 1, true) and reply:find("Willkommen", 1, true)
        and not reply:find("Loot", 1, true) and not reply:find("Kontakt", 1, true), "Custom reply retained disabled clauses")
    check(addon.RaidSearch:NewPlan().loot.rule ~= "Testloot", "Disabled guild loot used for new raid")
    guild.profile.enabled = false
    check(not addon.Recruitment:GenerateAdvertisement():find("Zusammen spielen", 1, true)
        and addon.Recruitment:GenerateReply("INFO", "Tester") == "", "Disabled whole profile leaked into output")
    addon.UI:RefreshSuggestions()
    check(addon.UI.pages.SUGGESTIONS.metricCards.PROFILE.value:GetText() == "DEAKTIVIERT", "Disabled profile marked incomplete")
    addon.UI:RefreshGuild()
    local page = addon.UI.pages.GUILD
    check(not page.guildFields.description:IsEnabled() and page.guildFields.description:GetText() == "Zusammen spielen",
        "Disabled editor lost saved value or remained editable")
    page.guildEnabled:SetChecked(true)
    page.guildEnabled.scripts.OnClick(page.guildEnabled)
    page.guildFieldToggles.raidTimes:SetChecked(true)
    page.guildFieldToggles.raidTimes.scripts.OnClick(page.guildFieldToggles.raidTimes)
    check(page.guildFields.raidTimes:IsEnabled(), "Re-enabled field is not editable")
    guild.recruitment.confirmedText = "Old advertisement with disabled values"
    page.guildSaveButton.scripts.OnClick(page.guildSaveButton)
    check(guild.profile.enabled and not guild.profile.disabledFields.raidTimes
        and guild.profile.raidTimes == "Dienstag 20 Uhr", "Saving did not restore enabled field/value")
    check(guild.recruitment.confirmedText == nil, "Profile change retained old ad confirmation")
    addon.Roster.CanEditGuildProfile = function() return false end
    addon.UI:RefreshGuild()
    page.guildEnabled:SetChecked(false)
    page.guildSaveButton.scripts.OnClick(page.guildSaveButton)
    check(not page.guildEnabled:IsEnabled() and guild.profile.enabled, "Unauthorized profile options saved")
    addon.Roster.CanEditGuildProfile = permission

    guild.profile.enabled, guild.profile.updatedAt = false, addon.Util.Now()
    local messages = addon.Sync:BuildGuildProfileMessages()
    check(#messages > 0, "Optional profile failed to serialize")
    guild.profile.enabled, guild.profile.disabledFields, guild.profile.updatedAt = true, {}, 0
    guild.profile.discord = ""
    for i = #messages, 1, -1 do addon.Sync:ReceiveGuildProfileChunk(messages[i], "Heiler-Realm", "GUILD") end
    check(guild.profile.enabled == false and guild.profile.disabledFields.discord
        and guild.profile.discord == "discord.example/test", "Sync lost switches or dormant values")
    addon.DB:Initialize()
    check(addon.DB:GetGuild().profile.enabled == false, "Database defaults re-enabled disabled profile")
    guild.profile, guild.replyTemplates, guild.recruitment = oldProfile, oldTemplates, oldRecruitment
    addon.RaidSearch:GetData().plan = oldPlan
    addon.UI:RefreshGuild()
end
