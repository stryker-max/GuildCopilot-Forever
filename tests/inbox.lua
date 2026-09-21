return function(addon, check, Fire, secret)
    local guild = addon.DB:GetGuild()
    local oldInbox, oldFilters, oldTombstones = guild.inbox, guild.inboxFilters, guild.inboxTombstones
    guild.inbox, guild.inboxFilters, guild.inboxTombstones = {}, {}, {}
    local settings = addon.DB:GetSettings()
    local onlyDuringSearch = settings.captureOnlyDuringSearch
    local filters = addon.Chat:GetRecruitmentFilters()
    local words = filters.whisperTriggers
    filters.whisperTriggers = { "gilde" }
    settings.captureOnlyDuringSearch = true
    addon.Chat.sessionActive, addon.Chat.sessionStartedAt = true, addon.Util.Now()
    Fire("CHAT_MSG_WHISPER", "Magier Level 20 sucht Gilde", "Ana-Forever", secret,
        nil, secret, nil, nil, nil, nil, nil, nil, secret)
    check(#guild.inbox == 1 and guild.inbox[1].guid == nil, "Readable whisper discarded with secret unused metadata/GUID: " .. #guild.inbox)
    local lead = guild.inbox[1]
    addon.Chat.sessionActive = false
    addon.Chat:CaptureWhisper("Danke, morgen passt!", "Ana-Forever")
    check(#lead.messages == 2, "Known applicant reply lost after search expired")
    local route = addon.RaidSearch.ShouldCaptureWhisper
    addon.RaidSearch.ShouldCaptureWhisper = function() return true end
    addon.Chat:CaptureWhisper("Bis morgen!", "Ana-Forever")
    check(#lead.messages == 3, "Raid search stole an existing inbox conversation")
    addon.RaidSearch.ShouldCaptureWhisper = route
    addon.Chat:CaptureWhisper("Ich suche eine Gilde", "New-Forever")
    check(#guild.inbox == 1, "New lead ignored search-only preference")
    addon.Chat:CaptureLead("Suche Gilde", "Ana-AndererNachname", nil, "CHANNEL")
    check(#guild.inbox == 2, "Different surnames merged")
    Fire("CHAT_MSG_CHANNEL", secret, "Hidden-Forever")
    check(#guild.inbox == 2, "Secret chat text was captured")

    local send = C_ChatInfo.SendChatMessage
    local replyAt = lead.lastReplyAt
    C_ChatInfo.SendChatMessage = function() error("blocked") end
    local ok, reason = addon.Chat:SendReply(lead.name, "Hallo!")
    check(not ok and reason:find("abgewiesen", 1, true) and lead.lastReplyAt == replyAt,
        "Rejected reply marked as answered or threw")
    addon.UI:ShowPage("INBOX")
    addon.UI.selectedLeadKey = addon.Util.NormalizeName(lead.name)
    addon.UI:RefreshInbox()
    local page = addon.UI.pages.INBOX
    page.replyEdit:SetText("Entwurf bleibt")
    page.replyButton.scripts.OnClick(page.replyButton)
    check(page.replyEdit:GetText() == "Entwurf bleibt" and page.replyResult:GetText():find("abgewiesen", 1, true),
        "Failed reply erased draft or hid its error")
    local called = 0
    C_ChatInfo.SendChatMessage = function() called = called + 1 end
    C_ChatInfo.InChatMessagingLockdown = function() return true end
    check(not addon.Chat:SendReply(lead.name, "Hallo!") and called == 0, "Reply attempted during chat lockdown")
    C_ChatInfo.InChatMessagingLockdown = nil
    check(not addon.Chat:SendReply(lead.name, string.rep("x", 256)) and called == 0, "Overlong reply silently truncated")
    check(addon.Chat:SendReply(lead.name, "Hallo!") and called == 1 and lead.lastReplyAt ~= nil, "Valid reply failed")
    C_ChatInfo.SendChatMessage = send

    local original = "Suche Gilde | 100% " .. string.rep("Grüße! ", 45)
    addon.Chat:CaptureLead(original, "Éléonorianne-Forever", nil, "WHISPER")
    local source = guild.inbox[1]
    for i = 1, 25 do addon.Chat:CaptureLead("Privater Folgetext " .. i, source.name, nil, "WHISPER") end
    local packets = addon.Chat:BuildInboxMessages(source)
    check(#packets > 1 and #source.messages == 20, "Fragmentation/history fixture failed")
    guild.inbox = {}
    for index = #packets, 1, -1 do
        check(#packets[index] <= 255, "Inbox packet exceeded limit")
        addon.Sync:OnMessage("GCPForever", packets[index], "GUILD", "Heiler-Realm")
    end
    check(#guild.inbox == 1 and guild.inbox[1].originMessage.text == original,
        "Inbox round trip lost UTF-8/escapes or disclosed follow-up messages")
    for _, packet in ipairs(packets) do addon.Chat:ReceiveSync(packet, "Heiler-Realm", "GUILD") end
    check(#guild.inbox == 1, "Duplicate transfer duplicated applicant")
    addon.Chat:RemoveLead(1)
    for _, packet in ipairs(packets) do addon.Chat:ReceiveSync(packet, "Heiler-Realm", "GUILD") end
    check(#guild.inbox == 0, "Deleted applicant resurrected through sync")
    addon.Chat:CaptureLead("Neue Bewerbung", source.name, nil, "WHISPER")
    check(#guild.inbox == 1, "Direct new application failed to clear deletion marker")
    addon.Chat:SetInboxFilter(source.name, 0)
    addon.Chat:CaptureLead("Neue Bewerbung", source.name, nil, "WHISPER")
    check(#guild.inbox == 0, "Ignored applicant returned")
    local forged = addon.Util.DeepCopy(source)
    forged.name = "Future-Forever"
    forged.lastSeenAt = addon.Util.Now() + 365 * 86400
    for _, packet in ipairs(addon.Chat:BuildInboxMessages(forged)) do addon.Chat:ReceiveSync(packet, "Heiler-Realm", "GUILD") end
    check(#guild.inbox == 0, "Far-future inbox record accepted")
    local bulk = addon.Sync.SendBulk
    addon.Sync.SendBulk = function() return false end
    check(not addon.Chat:SendLead(source), "Rejected inbox queue reported success")
    addon.Sync.SendBulk = bulk

    addon.Chat:CaptureLead("Gilde gesucht", "Saved-Forever", nil, "WHISPER")
    addon.DB:Initialize()
    check(addon.DB:GetGuild().inbox[1].name == "Saved-Forever", "Inbox lost during database reinitialization")
    guild.inbox = {}
    for i = 1, 101 do
        guild.inbox[i] = { name = "Applicant" .. i, lastSeenAt = addon.Util.Now() - i,
            firstSeenAt = addon.Util.Now() - i, messages = {} }
    end
    guild.inbox[101].lastSeenAt = addon.Util.Now()
    addon.DB:Prune()
    check(#guild.inbox == 100 and guild.inbox[1].name == "Applicant101",
        "Inbox capacity evicted recently active applicant")
    guild.inbox, guild.inboxFilters, guild.inboxTombstones = oldInbox, oldFilters, oldTombstones
    settings.captureOnlyDuringSearch = onlyDuringSearch
    filters.whisperTriggers = words
    addon.UI:ShowPage("STATISTICS")
end
