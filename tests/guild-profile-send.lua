return function(addon, check)
    local sync, profile = addon.Sync, addon.DB:GetGuild().profile
    local oldEnabled, oldDescription = profile.enabled, profile.description
    local oldAfter, oldPrint, oldNow = C_Timer.After, addon.Print, addon.Util.Now
    local oldGuild, oldRestricted, oldSend = IsInGuild, C_ChatInfo.AreOutgoingAddonChatMessagesRestricted, C_ChatInfo.SendAddonMessage
    local keys = { "guildProfileTransfer", "guildProfileSendPending", "guildProfileForceSend", "serialPending", "progressFailed", "syncStatus" }
    local previous = {}
    for _, key in ipairs(keys) do previous[key] = sync[key]; sync[key] = nil end
    sync.serialPending, sync.progressFailed = 0, 0
    local timers, printed, sent = {}, {}, {}
    local now, restricted, succeeds, inGuild = oldNow(), true, true, true
    addon.Util.Now = function() return now end
    addon.Print = function(_, message) printed[#printed + 1] = message end
    C_Timer.After = function(_, callback) timers[#timers + 1] = callback end
    IsInGuild = function() return inGuild end
    C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function() return restricted end
    C_ChatInfo.SendAddonMessage = function(_, message) sent[#sent + 1] = message; return succeeds end
    local function Tick()
        local callback = table.remove(timers, 1)
        if callback then callback() end
    end
    local function Drain()
        for _ = 1, 100 do if #timers == 0 then return end; Tick() end
        error("Guild profile timers failed to drain")
    end
    profile.enabled = false
    check(not sync:QueueGuildProfile() and not sync:SendGuildProfile() and #timers == 0,
        "Disabled profile started automatic broadcast")
    check(sync:QueueGuildProfile(true), "Explicit disable update was not queued")
    Tick()
    local pending, transfer = sync.serialPending, sync.guildProfileTransfer
    check(pending > 0 and transfer ~= nil, "Restricted disable update was dropped")
    sync:GetSyncStatus()
    for _ = 1, 12 do now = now + 30; Tick(); sync:GetSyncStatus() end
    check(#sent == 0 and #printed == 0 and sync.progressFailed == 0 and sync.serialPending == pending,
        "Long client restriction caused attempts, warnings or lost progress")
    check(sync:GetSyncStatus().paused, "Restricted guild profile not shown as paused")
    check(sync:SendGuildProfile(true) and sync.guildProfileTransfer == transfer and sync.serialPending == pending,
        "Duplicate broadcast started a second transfer")
    restricted = false
    Drain()
    check(#sent == pending and sync.serialPending == 0 and sync.guildProfileTransfer == nil,
        "Paused profile failed to resume/finish")
    check(#printed == 0, "Completed disable update printed a failure")

    restricted = true
    profile.description = "OLD-PROFILE"
    sync:SendGuildProfile(true)
    profile.description = "NEW-PROFILE"
    sync:SendGuildProfile(true)
    local before = #sent
    restricted = false
    Drain()
    local payload = ""
    for i = before + 1, #sent do payload = payload .. (sent[i]:match("^G|[^|]+|[^|]+|[^|]+|[^|]+|(.*)$") or "") end
    check(payload:find("NEW-PROFILE", 1, true) and not payload:find("OLD-PROFILE", 1, true) and sync.serialPending == 0,
        "Superseded profile sent stale parts or leaked progress")

    succeeds = false
    sync:SendGuildProfile(true)
    Drain()
    check(#printed == 0 and sync.progressFailed > 0, "Disabled profile spammed or hid failed-sync status")
    profile.enabled = true
    sync:SendGuildProfile(true)
    Drain()
    check(#printed == 1, "Real active-profile failure was not reported once")
    inGuild = false
    before = #sent
    check(not sync:SendGuildProfile(true) and #sent == before and #timers == 0, "Unguilded player started retries")
    inGuild, restricted, succeeds = true, true, true
    sync:SendGuildProfile(true)
    inGuild = false
    Drain()
    check(sync.serialPending == 0 and sync.guildProfileTransfer == nil and #printed == 1,
        "Leaving guild failed to cancel paused profile cleanly")
    profile.enabled, profile.description = oldEnabled, oldDescription
    C_Timer.After, addon.Print, addon.Util.Now = oldAfter, oldPrint, oldNow
    IsInGuild, C_ChatInfo.AreOutgoingAddonChatMessagesRestricted, C_ChatInfo.SendAddonMessage = oldGuild, oldRestricted, oldSend
    for _, key in ipairs(keys) do sync[key] = previous[key] end
end
