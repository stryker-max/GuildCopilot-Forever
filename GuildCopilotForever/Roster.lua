local _, GC = ...

GC.Roster = {
    members = {},
    membersByName = {},
    lastUpdate = 0,
}

local function PutNameIndex(index, name, member)
    if not name or name == "" then
        return
    end
    index[GC.Util.NormalizeName(name)] = member
    index[GC.Util.NormalizeName(GC.Util.PlayerIdentityName(name))] = member
end

function GC.Roster:Request()
    if not IsInGuild or not IsInGuild() then
        self.members = {}
        self.membersByName = {}
        GC:FireCallback("ROSTER_UPDATED")
        return
    end

    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

function GC.Roster:Refresh()
    self:Request()
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function()
            self:Scan()
        end)
    else
        self:Scan()
    end
end

-- === Entprellung ==========================================================
--
-- GUILD_ROSTER_UPDATE feuert bei jedem Ein- und Ausloggen eines beliebigen
-- Gildenmitglieds - und zusaetzlich, sobald irgendein anderes Addon
-- GuildRoster() ruft. Jeder Scan liest alle Mitglieder neu ein, fuer jedes
-- Offline-Mitglied zusaetzlich die letzte Onlinezeit, und stoesst danach den
-- Neuaufbau der Oberflaeche an. Zur Prime Time lief das im Dauerfeuer; genau
-- daraus entstanden die gemeldeten Ruckler.
--
-- Gesammelt wird deshalb: Zehn Logins in fuenf Sekunden ergeben einen Scan.
-- Die Verzoegerung ist unkritisch, weil die Daten ohnehin erst beim naechsten
-- Blick ins Fenster gebraucht werden.
local SCAN_DEBOUNCE = 3

function GC.Roster:ScheduleScan(delay)
    delay = tonumber(delay) or SCAN_DEBOUNCE
    if not C_Timer or type(C_Timer.After) ~= "function" then
        self:Scan()
        return false
    end
    if self.scanPending then
        return false
    end
    self.scanPending = true
    C_Timer.After(delay, function()
        self.scanPending = false
        self:Scan()
    end)
    return true
end

function GC.Roster:Scan()
    GC.Perf:Measure("Gildenroster einlesen", self.ScanNow, self)
end

-- === Gefilterte Rosterliste ===============================================
--
-- Hat ein anderes Addon SetGuildRosterShowOffline(false) gesetzt, liefert
-- GetGuildRosterInfo nur noch die Online-Mitglieder. Der Scan stuerzt dabei
-- nicht ab - "if name then" faengt die Luecke -, das Roster schrumpft nur
-- stumm auf die Online-Liste. Betroffen ist damit alles, was ueber
-- IsGuildMember geht: Die Gildenprofil-Pakete der Offliner werden verworfen,
-- die Mitgliederpflege sieht sie nicht mehr, und
-- Workshop:PruneDepartedCrafters haelt sie fuer ausgetreten und LOESCHT ihre
-- Rezepte.
--
-- Erkannt wird das an der Ausbeute: GetNumGuildMembers() meldet die
-- Gesamtzahl, gelesen wird aber nur ein Bruchteil davon. Unter diesem Anteil
-- gilt die Liste als gefiltert. Ausdruecklich NICHT gemeint ist das leere
-- Roster direkt nach dem Login - dort meldet der Client die Gesamtzahl 0, und
-- 0 von 0 gelesenen Mitgliedern ist vollstaendig.
local ROSTER_COMPLETE_RATIO = 0.9
-- Nach einer gefilterten Liste wird erneut gelesen. Ein paar Sekunden alte
-- Daten sind allemal besser als ein Roster, das die halbe Gilde fuer
-- ausgetreten haelt.
local ROSTER_RETRY_DELAY = 5
-- Aber nicht endlos: Besteht ein anderes Addon dauerhaft auf seiner Ansicht,
-- soll daraus kein ewiger Wechsel aus Anfrage und Scan werden. Der naechste
-- GUILD_ROSTER_UPDATE bringt ohnehin einen neuen Versuch, und bis dahin bleibt
-- der letzte vollstaendige Stand stehen.
local ROSTER_RETRY_LIMIT = 3

-- Die Ursache beheben statt nur das Symptom. Die Funktion gibt es nicht in
-- jeder Spielfassung, deshalb ueber pcall.
local function RequestOfflineMembers()
    if type(SetGuildRosterShowOffline) ~= "function" then
        return false
    end
    return pcall(SetGuildRosterShowOffline, true) == true
end

function GC.Roster:ScanNow()
    local members = {}
    local index = {}
    local memberCount = GetNumGuildMembers and GetNumGuildMembers() or 0
    local readCount = 0

    for rosterIndex = 1, memberCount do
        local name, rank, rankIndex, level, className, zone, note, officerNote, online, status, classFile, achievementPoints, achievementRank, isMobile, canSoR, reputation, guid = GetGuildRosterInfo(rosterIndex)
        if name then
            local member = {
                name = name,
                rank = rank,
                rankIndex = rankIndex,
                level = level,
                className = className,
                classFile = classFile,
                zone = zone,
                online = online == true,
                status = status,
                guid = guid,
            }
            if not online and GetGuildRosterLastOnline then
                local ok, years, months, days, hours = pcall(GetGuildRosterLastOnline, rosterIndex)
                if ok and (years or months or days or hours) then
                    member.lastOnlineHours = ((tonumber(years) or 0) * 8760)
                        + ((tonumber(months) or 0) * 730)
                        + ((tonumber(days) or 0) * 24)
                        + (tonumber(hours) or 0)
                end
            elseif online then
                member.lastOnlineHours = 0
            end
            members[#members + 1] = member
            PutNameIndex(index, name, member)
            readCount = readCount + 1
        end
    end

    -- Gefilterte Liste: den vorherigen Stand NICHT ersetzen, die Offliner
    -- anfordern und es gleich noch einmal versuchen.
    if memberCount > 0 and readCount < memberCount * ROSTER_COMPLETE_RATIO then
        local attempt = (self.incompleteScans or 0) + 1
        self.incompleteScans = attempt
        RequestOfflineMembers()
        if attempt <= ROSTER_RETRY_LIMIT then
            self:Request()
            self:ScheduleScan(ROSTER_RETRY_DELAY)
        end
        return
    end
    self.incompleteScans = 0

    self.members = members
    self.membersByName = index
    self.lastUpdate = GC.Util.Now()
    GC:FireCallback("ROSTER_UPDATED")
end

-- Wer zaehlt als aktiver Raider? Diese Frage beantwortete bisher nur die
-- Raiderliste fuer sich selbst; die Rekrutierungsabdeckung zaehlte dagegen
-- JEDES Gildenmitglied mit - auch den Stufe-12-Twink und einen Rang, der
-- ausdruecklich ausgeschlossen war. Eine gesuchte Spec galt dadurch als
-- abgedeckt, obwohl sie niemand raiden konnte. Beide Seiten fragen jetzt hier.
-- Die Maßstaebe einmal einsammeln. GC.DB:GetGuild() faehrt bei JEDEM Aufruf
-- rekursiv den kompletten Vorgabenbaum ab (MergeDefaults) - in einer Schleife
-- ueber alle Gildenmitglieder ist genau das der teure Teil. Die Pruefungen
-- unten nehmen die fertigen Regeln deshalb entgegen, statt sie sich je Mitglied
-- selbst zu holen.
function GC.Roster:GetRaiderRules()
    local guildData = GC.DB:GetGuild()
    return {
        rankFilterConfigured = guildData.roster.rankFilterConfigured,
        activeRaiderRanks = guildData.roster.activeRaiderRanks,
        inactivityHours = (tonumber(guildData.memberCare.inactivityDays) or 60) * 24,
    }
end

function GC.Roster:CountsAsActiveRaider(member, rules)
    if not member then
        return false
    end
    if (tonumber(member.level) or 0) < GC.Client.maxLevel then
        return false
    end
    rules = rules or self:GetRaiderRules()
    if rules.rankFilterConfigured
        and rules.activeRaiderRanks[tostring(member.rankIndex)] ~= true then
        return false
    end
    return true
end

-- Fuer die Abdeckung reicht "darf raiden" nicht: Wer seit Monaten nicht mehr
-- eingeloggt war, deckt keine Spec ab. Ausgeschlossen wird aber nur, wessen
-- Abwesenheit wirklich bekannt ist - liefert der Client keine Zeit seit dem
-- letzten Login, darf das niemanden aus der Rechnung werfen.
function GC.Roster:CountsForCoverage(member, rules)
    rules = rules or self:GetRaiderRules()
    if not self:CountsAsActiveRaider(member, rules) then
        return false
    end
    local lastOnlineHours = tonumber(member.lastOnlineHours)
    if lastOnlineHours and lastOnlineHours > rules.inactivityHours then
        return false
    end
    return true
end

function GC.Roster:GetActiveRaiders(limit)
    local raiders = {}
    local rules = self:GetRaiderRules()
    for _, member in ipairs(self.members) do
        if self:CountsAsActiveRaider(member, rules) then
            raiders[#raiders + 1] = member
        end
    end
    table.sort(raiders, function(left, right)
        if left.online ~= right.online then
            return left.online == true
        end
        local leftHours = left.lastOnlineHours or math.huge
        local rightHours = right.lastOnlineHours or math.huge
        if leftHours ~= rightHours then
            return leftHours < rightHours
        end
        return tostring(left.name or "") < tostring(right.name or "")
    end)

    local result = {}
    for index = 1, math.min(tonumber(limit) or GC.Constants.ACTIVE_RAIDER_LIMIT, #raiders) do
        result[index] = raiders[index]
    end
    return result
end

function GC.Roster:GetRankDefinitions()
    local byIndex = {}
    for _, member in ipairs(self.members) do
        local rankIndex = tonumber(member.rankIndex)
        if rankIndex ~= nil and not byIndex[rankIndex] then
            byIndex[rankIndex] = {
                index = rankIndex,
                name = member.rank or ("Rang " .. (rankIndex + 1)),
            }
        end
    end

    local ranks = {}
    for _, definition in pairs(byIndex) do
        ranks[#ranks + 1] = definition
    end
    table.sort(ranks, function(left, right)
        return left.index < right.index
    end)
    return ranks
end

function GC.Roster:GetMember(name)
    return self.membersByName[GC.Util.NormalizeName(name)]
        or self.membersByName[GC.Util.NormalizeName(GC.Util.PlayerIdentityName(name))]
end

function GC.Roster:IsRankActive(rankIndex)
    local settings = GC.DB:GetGuild().roster
    if not settings.rankFilterConfigured then
        return true
    end
    return settings.activeRaiderRanks[tostring(rankIndex)] == true
end

function GC.Roster:SetRankActive(rankIndex, active)
    if not self:CanEditGuildSettings() then
        return false
    end
    local settings = GC.DB:GetGuild().roster
    if not settings.rankFilterConfigured then
        for _, rank in ipairs(self:GetRankDefinitions()) do
            settings.activeRaiderRanks[tostring(rank.index)] = true
        end
    end
    settings.rankFilterConfigured = true
    settings.activeRaiderRanks[tostring(rankIndex)] = active == true
    GC:FireCallback("ROSTER_FILTER_UPDATED")
    GC.DB:GetGuild().profile.updatedAt = GC.Util.Now()
    if GC.Sync and GC.Sync.QueueGuildProfile then
        GC.Sync:QueueGuildProfile(true)
    end
    return true
end

function GC.Roster:SetAllRanksActive(active)
    if not self:CanEditGuildSettings() then
        return false
    end
    local settings = GC.DB:GetGuild().roster
    settings.rankFilterConfigured = true
    settings.activeRaiderRanks = {}
    if active then
        for _, rank in ipairs(self:GetRankDefinitions()) do
            settings.activeRaiderRanks[tostring(rank.index)] = true
        end
    end
    GC:FireCallback("ROSTER_FILTER_UPDATED")
    GC.DB:GetGuild().profile.updatedAt = GC.Util.Now()
    if GC.Sync and GC.Sync.QueueGuildProfile then
        GC.Sync:QueueGuildProfile(true)
    end
    return true
end

function GC.Roster:IsGuildProfileEditorRank(rankIndex)
    if tonumber(rankIndex) == 0 then
        return true
    end
    local permissions = GC.DB:GetGuild().profilePermissions
    if not permissions.configured then
        return tonumber(rankIndex) ~= nil and tonumber(rankIndex) <= 1
    end
    return permissions.editorRanks[tostring(rankIndex)] == true
end

function GC.Roster:CanEditGuildProfile(playerName)
    local member = self:GetMember(playerName or GC:GetPlayerFullName())
    return member ~= nil and self:IsGuildProfileEditorRank(member.rankIndex)
end

function GC.Roster:CanEditGuildSettings(playerName)
    return self:CanEditGuildProfile(playerName)
end

local function HasBlizzardOfficerAuthority()
    local checks = {
        IsGuildLeader,
        GC.API.CanEditOfficerNote,
        CanGuildPromote,
        CanGuildRemove,
    }
    for _, check in ipairs(checks) do
        if type(check) == "function" then
            local success, allowed = pcall(check)
            if success and allowed == true then
                return true
            end
        end
    end
    return false
end

function GC.Roster:CanUseEditorRecovery(rankIndex)
    local member = self:GetMember(GC:GetPlayerFullName())
    local ownRankIndex = member and tonumber(member.rankIndex)
    return GC.DB:GetGuild().editorRecoveryAvailable == true
        and ownRankIndex ~= nil
        and (ownRankIndex <= 1 or HasBlizzardOfficerAuthority())
        and ownRankIndex == tonumber(rankIndex)
        and not self:IsGuildProfileEditorRank(ownRankIndex)
end

local function InitializeDefaultEditorRanks()
    local permissions = GC.DB:GetGuild().profilePermissions
    if permissions.configured then
        return permissions
    end
    for _, rank in ipairs(GC.Roster:GetRankDefinitions()) do
        permissions.editorRanks[tostring(rank.index)] = rank.index <= 1
    end
    permissions.configured = true
    return permissions
end

local function GuildProfilePermissionsChanged()
    GC.DB:GetGuild().profile.updatedAt = GC.Util.Now()
    GC:FireCallback("SETTINGS_UPDATED")
    GC:FireCallback("GUILD_PROFILE_UPDATED")
    if GC.Sync and GC.Sync.QueueGuildProfile then
        GC.Sync:QueueGuildProfile(true)
    end
end

function GC.Roster:SetGuildProfileRankActive(rankIndex, active)
    rankIndex = tonumber(rankIndex)
    local member = self:GetMember(GC:GetPlayerFullName())
    local ownRankIndex = member and tonumber(member.rankIndex)

    if active and self:CanUseEditorRecovery(rankIndex) then
        local recoveryPermissions = InitializeDefaultEditorRanks()
        recoveryPermissions.editorRanks[tostring(rankIndex)] = true
        GC.DB:GetGuild().editorRecoveryAvailable = false
        GuildProfilePermissionsChanged()
        return true, "RECOVERED"
    end

    if not self:CanEditGuildProfile() then
        return false, "NO_PERMISSION"
    end
    if not active and ownRankIndex == rankIndex then
        return false, "OWN_RANK"
    end
    if not active and (rankIndex == 0 or ownRankIndex == nil or ownRankIndex >= rankIndex) then
        return false, "HIGHER_RANK_REQUIRED"
    end
    local permissions = InitializeDefaultEditorRanks()
    if not active then
        local otherEditorExists = false
        for storedRankIndex, enabled in pairs(permissions.editorRanks) do
            if enabled and tostring(storedRankIndex) ~= tostring(rankIndex) then
                otherEditorExists = true
                break
            end
        end
        if not otherEditorExists then
            return false, "LAST_EDITOR"
        end
    end
    permissions.editorRanks[tostring(rankIndex)] = active == true
    GuildProfilePermissionsChanged()
    return true, "UPDATED"
end

function GC.Roster:SetAllGuildProfileRanksActive(active)
    if not self:CanEditGuildProfile() then
        return false
    end
    if not active then
        return false
    end
    local permissions = InitializeDefaultEditorRanks()
    permissions.editorRanks = {}
    if active then
        for _, rank in ipairs(self:GetRankDefinitions()) do
            permissions.editorRanks[tostring(rank.index)] = true
        end
    end
    GuildProfilePermissionsChanged()
    return true
end

local function InitializeDefaultProtectedRanks()
    local settings = GC.DB:GetGuild().memberCare
    if settings.protectedRanksConfigured then
        return settings
    end
    for _, rank in ipairs(GC.Roster:GetRankDefinitions()) do
        settings.protectedRanks[tostring(rank.index)] = rank.index <= 1
    end
    settings.protectedRanksConfigured = true
    return settings
end

local function InitializeDefaultMemberCareAccessRanks()
    local settings = GC.DB:GetGuild().memberCare
    if settings.accessRanksConfigured then
        return settings
    end
    for _, rank in ipairs(GC.Roster:GetRankDefinitions()) do
        settings.accessRanks[tostring(rank.index)] = rank.index <= 1
    end
    settings.accessRanksConfigured = true
    return settings
end

local function MemberCareSettingsChanged()
    GC.DB:GetGuild().profile.updatedAt = GC.Util.Now()
    GC:FireCallback("MEMBERCARE_UPDATED")
    if GC.Sync and GC.Sync.QueueGuildProfile then
        GC.Sync:QueueGuildProfile(true)
    end
end

function GC.Roster:IsMemberCareRankProtected(rankIndex)
    local settings = GC.DB:GetGuild().memberCare
    if not settings.protectedRanksConfigured then
        return tonumber(rankIndex) ~= nil and tonumber(rankIndex) <= 1
    end
    return settings.protectedRanks[tostring(rankIndex)] == true
end

function GC.Roster:IsMemberCareAccessRank(rankIndex)
    local settings = GC.DB:GetGuild().memberCare
    if not settings.accessRanksConfigured then
        return tonumber(rankIndex) ~= nil and tonumber(rankIndex) <= 1
    end
    return settings.accessRanks[tostring(rankIndex)] == true
end

function GC.Roster:CanAccessMemberCare(playerName)
    local member = self:GetMember(playerName or GC:GetPlayerFullName())
    return member ~= nil and self:IsMemberCareAccessRank(member.rankIndex)
end

function GC.Roster:SetMemberCareAccessRank(rankIndex, active)
    if not self:CanEditGuildSettings() then
        return false
    end
    local settings = InitializeDefaultMemberCareAccessRanks()
    if not active then
        local otherAccessRankExists = false
        for storedRankIndex, enabled in pairs(settings.accessRanks) do
            if enabled and tostring(storedRankIndex) ~= tostring(rankIndex) then
                otherAccessRankExists = true
                break
            end
        end
        if not otherAccessRankExists then
            return false
        end
    end
    settings.accessRanks[tostring(rankIndex)] = active == true
    MemberCareSettingsChanged()
    GC:FireCallback("SETTINGS_UPDATED")
    return true
end

-- === Bewerberton je Rang =================================================
--
-- Der Ton meldet einen fremden Interessenten. Wer nicht rekrutiert, will ihn
-- nicht hoeren, weiss aber meist nicht, dass er ihn abschalten koennte -
-- deshalb entscheidet der Gildenrang und nicht jeder fuer sich. Erfasst wird
-- weiter fuer alle, nur ohne Ton.

local function InitializeDefaultInboxSoundRanks()
    local settings = GC.DB:GetGuild().inboxSound
    if settings.ranksConfigured then
        return settings
    end
    for _, rank in ipairs(GC.Roster:GetRankDefinitions()) do
        settings.ranks[tostring(rank.index)] = rank.index <= 1
    end
    settings.ranksConfigured = true
    return settings
end

function GC.Roster:IsInboxSoundRank(rankIndex)
    local settings = GC.DB:GetGuild().inboxSound
    if not settings.ranksConfigured then
        return tonumber(rankIndex) ~= nil and tonumber(rankIndex) <= 1
    end
    return settings.ranks[tostring(rankIndex)] == true
end

-- Ist der eigene Rang unbekannt - Roster noch nicht geladen, gerade gar keine
-- Gilde -, wird der Ton gespielt. Ein Ton zu viel ist verzeihlicher als der
-- eine verpasste Bewerber, auf den ein Offizier wartet.
function GC.Roster:HearsInboxSound(playerName)
    local member = self:GetMember(playerName or GC:GetPlayerFullName())
    if not member or tonumber(member.rankIndex) == nil then
        return true
    end
    return self:IsInboxSoundRank(member.rankIndex)
end

function GC.Roster:SetInboxSoundRank(rankIndex, active)
    if not self:CanEditGuildSettings() then
        return false
    end
    local settings = InitializeDefaultInboxSoundRanks()
    settings.ranks[tostring(rankIndex)] = active == true
    GC.DB:GetGuild().profile.updatedAt = GC.Util.Now()
    if GC.Sync and GC.Sync.QueueGuildProfile then
        GC.Sync:QueueGuildProfile(true)
    end
    GC:FireCallback("SETTINGS_UPDATED")
    return true
end

function GC.Roster:SetMemberCareRankProtected(rankIndex, protected)
    if not self:CanEditGuildProfile() then
        return false
    end
    local settings = InitializeDefaultProtectedRanks()
    settings.protectedRanks[tostring(rankIndex)] = protected == true
    MemberCareSettingsChanged()
    return true
end

function GC.Roster:SetMemberCareInactivityDays(days)
    if not self:CanEditGuildProfile() then
        return false
    end
    days = math.max(7, math.min(365, tonumber(days) or 60))
    GC.DB:GetGuild().memberCare.inactivityDays = math.floor(days)
    MemberCareSettingsChanged()
    return true
end

-- === Entscheidungen zu Pflegevorschlägen ====================================

local function DecisionKey(name)
    return GC.Util.NormalizeName(GC.Util.PlayerIdentityName(name))
end

function GC.Roster:PruneMemberCareDecisions(today)
    today = today or GC.Util.TodayISO()
    local decisions = GC.DB:GetGuild().memberCare.decisions
    local changed = false
    for key, decision in pairs(decisions) do
        if type(decision) ~= "table"
            or not GC.MemberCareDecisions[decision.status]
            or (decision.status == "POSTPONED"
                and (not GC.Util.IsValidISODate(decision.until_) or today > decision.until_)) then
            decisions[key] = nil
            changed = true
        end
    end
    return changed
end

function GC.Roster:GetMemberCareDecision(name, today)
    local key = DecisionKey(name)
    if key == "" then
        return nil
    end
    local decision = GC.DB:GetGuild().memberCare.decisions[key]
    if not decision then
        return nil
    end
    if decision.status == "POSTPONED" then
        today = today or GC.Util.TodayISO()
        if not GC.Util.IsValidISODate(decision.until_) or today > decision.until_ then
            return nil
        end
    end
    return decision
end

function GC.Roster:SetMemberCareDecision(name, status, untilDate)
    if not self:CanAccessMemberCare() then
        return false, "Für deinen Gildenrang ist die Mitgliederpflege nicht freigeschaltet."
    end
    if not GC.MemberCareDecisions[status] then
        return false, "Unbekannte Entscheidung."
    end
    local key = DecisionKey(name)
    if key == "" then
        return false, "Kein Spieler ausgewählt."
    end

    local decisions = GC.DB:GetGuild().memberCare.decisions
    self:PruneMemberCareDecisions()
    local existingCount = 0
    for _ in pairs(decisions) do
        existingCount = existingCount + 1
    end
    if not decisions[key] and existingCount >= GC.MemberCareMaxDecisions then
        return false, "Die Liste ist voll. Bitte zuerst alte Einträge zurückholen."
    end

    if status == "POSTPONED" and not GC.Util.IsValidISODate(untilDate) then
        untilDate = GC.Util.AddDaysISO(GC.MemberCarePostponeDays)
    end
    decisions[key] = {
        name = GC.Util.PlayerIdentityName(name),
        status = status,
        until_ = status == "POSTPONED" and untilDate or "",
        by = GC.Util.PlayerIdentityName(GC:GetPlayerFullName()),
        at = GC.Util.Now(),
    }
    MemberCareSettingsChanged()
    return true, GC.MemberCareDecisions[status].label .. " für " .. decisions[key].name .. " gespeichert."
end

function GC.Roster:ClearMemberCareDecision(name)
    if not self:CanAccessMemberCare() then
        return false, "Für deinen Gildenrang ist die Mitgliederpflege nicht freigeschaltet."
    end
    local key = DecisionKey(name)
    local decisions = GC.DB:GetGuild().memberCare.decisions
    if not decisions[key] then
        return false, "Für diesen Spieler ist nichts hinterlegt."
    end
    decisions[key] = nil
    MemberCareSettingsChanged()
    return true, "Eintrag zurückgeholt."
end

function GC.Roster:GetMemberCareDecisions()
    if self:PruneMemberCareDecisions() then
        MemberCareSettingsChanged()
    end
    local entries = {}
    for _, decision in pairs(GC.DB:GetGuild().memberCare.decisions) do
        entries[#entries + 1] = decision
    end
    table.sort(entries, function(left, right)
        if left.status ~= right.status then
            return left.status < right.status
        end
        return tostring(left.name) < tostring(right.name)
    end)
    return entries
end

-- === Gildenausschluss: aus einem Addon heraus nicht moeglich ==============
--
-- Hier stand eine ganze Maschinerie: Berechtigungspruefungen, Namensformen,
-- Slash-Handler, Bestaetigungsdialog, Nachpruefung im Gildenroster. Sie ist
-- ersatzlos entfallen.
--
-- GuildUninvite ist eine geschuetzte Funktion ("can only be called from
-- secure code"). Ein Addon kann niemanden aus der Gilde entfernen, ueber
-- keinen Umweg: nicht per API, nicht ueber den Slash-Befehl, nicht ueber
-- Blizzards eigenen Dialog. Was zuletzt blieb, war ein Knopf, der bloss das
-- Gildenfenster oeffnete - ein Umweg, der aussah wie eine Funktion und keine
-- war. Owner-Entscheidung: weg damit.
--
-- Die Mitgliederpflege beantwortet damit genau eine Frage, und die
-- beantwortet sie gut: WEN sollte man sich ansehen? Gehandelt wird in WoW.
--
-- Quelle: https://warcraft.wiki.gg/wiki/API_GuildUninvite

function GC.Roster:GetGuildAbsences()
    local absences = {}
    local today = GC.Util.TodayISO()
    -- Einmal fuer den ganzen Durchlauf und durchgereicht, genau wie in
    -- GetSummary: Bis 0.9.96 suchte sich GetProfile den Gildendatensatz je
    -- Mitglied selbst.
    local guildData = GC.DB:GetGuild()
    for _, member in ipairs(self.members) do
        local profile = self:GetProfile(member.name, guildData)
        local state = profile and GC.Profile:GetAbsenceState(profile, today) or "NONE"
        if state == "ACTIVE" or state == "UPCOMING" then
            absences[#absences + 1] = {
                member = member,
                profile = profile,
                absence = profile.absence,
                state = state,
            }
        end
    end
    table.sort(absences, function(left, right)
        if left.state ~= right.state then
            return left.state == "ACTIVE"
        end
        if left.absence.from ~= right.absence.from then
            return left.absence.from < right.absence.from
        end
        return tostring(left.member.name) < tostring(right.member.name)
    end)
    return absences
end

function GC.Roster:GetMemberCareCandidates()
    -- Den Gildendatensatz einmal holen und durchreichen, wie GetSummary es
    -- vormacht: Bis 0.9.96 kam dieser Durchlauf allein auf 1.503 Aufrufe von
    -- GC.DB:GetGuild(), weil GetProfile ihn sich je Mitglied selbst suchte.
    local guildData = GC.DB:GetGuild()
    local settings = guildData.memberCare
    local thresholdDays = tonumber(settings.inactivityDays) or 60
    local today = GC.Util.TodayISO()
    local candidates = {}
    for _, member in ipairs(self.members) do
        local offlineDays = member.lastOnlineHours and math.floor(member.lastOnlineHours / 24)
        local profile = self:GetProfile(member.name, guildData)
        local isAlt = profile and profile.mainStatus == "ALT"
        local absenceState = profile and GC.Profile:GetAbsenceState(profile, today) or "NONE"
        local rankProtected = self:IsMemberCareRankProtected(member.rankIndex)
        local decided = self:GetMemberCareDecision(member.name, today) ~= nil
        if not member.online
            and offlineDays
            and offlineDays >= thresholdDays
            and not isAlt
            and absenceState ~= "ACTIVE"
            and not rankProtected
            and not decided then
            local knownMain = profile and profile.confirmed and profile.mainStatus == "MAIN"
            -- "Main/Twink prüfen" stand hier in JEDER Zeile, in der niemand ein
            -- bestätigtes Profil hat - also fast immer. Eine Angabe, die auf
            -- alle zutrifft, unterscheidet nichts und kostet nur Platz; der
            -- Zustand steht ohnehin schon in der Statusspalte ("PRÜFEN").
            -- Genannt wird deshalb nur noch, was wirklich etwas aussagt.
            local reasons = {
                offlineDays .. " Tage offline",
                "nicht abgemeldet",
            }
            if knownMain then
                reasons[#reasons + 1] = "Main bestätigt"
            end
            candidates[#candidates + 1] = {
                member = member,
                profile = profile,
                offlineDays = offlineDays,
                status = knownMain and "VORSCHLAG" or "PRÜFEN",
                reason = table.concat(reasons, "  •  "),
            }
        end
    end
    table.sort(candidates, function(left, right)
        if left.offlineDays ~= right.offlineDays then
            return left.offlineDays > right.offlineDays
        end
        return tostring(left.member.name) < tostring(right.member.name)
    end)
    return candidates
end

function GC.Roster:IsGuildMember(name)
    return self:GetMember(name) ~= nil
end

-- "guildData" ist optional und rein fuer Schleifen gedacht: Wer ueber alle
-- Mitglieder laeuft, holt den Gildendatensatz einmal und reicht ihn durch,
-- statt ihn je Mitglied erneut ueber den Vorgabenbaum aufbauen zu lassen.
-- === Beim Inspizieren erkannte Spec ========================================
--
-- Legt die Spec eines fremden Spielers ab, die beim Ausruestungsabgleich aus
-- seinem Talentbaum gelesen wurde. Sie ist die SCHWAECHSTE Quelle und drueckt
-- sich niemand vor:
--
--   * Wer sein Profil selbst gepflegt hat, behaelt es - der Spieler weiss
--     besser als sein Talentbaum, womit er raiden will (Dual-Spec!).
--   * Ein Warcraft-Logs-Import bleibt ebenfalls stehen.
--   * Ueberschrieben wird nur ein aelterer Eintrag derselben Herkunft.
--
-- Gesendet wird sie nicht: Jeder Client inspiziert ohnehin selbst, und eine
-- abgeleitete Angabe hat im gildenweiten Abgleich nichts verloren.
function GC.Roster:NoteInspectedSpec(name, specKey, classFile)
    if GC.Util.Trim(name) == "" or GC.Util.Trim(specKey) == "" then
        return false
    end
    local key = GC.Util.PlayerKey(name)
    if key == "" or key == GC.Util.PlayerKey(GC:GetPlayerFullName()) then
        return false
    end

    local guildData = GC.DB:GetGuild()
    -- Ein Spieler steht in diesen Tabellen unter zwei Schluesseln: mit und ohne
    -- Realmanteil. Wer nur einen davon nachsieht, uebersieht ein gepflegtes
    -- Profil unter dem anderen und legt daneben einen abgeleiteten Eintrag an -
    -- dieselbe Falle, in der schon GetOnlinePeerNames sass.
    local fullKey = GC.Util.NormalizeName(name)
    local existing = guildData.remoteProfiles[key] or guildData.remoteProfiles[fullKey]
    if existing and existing.source ~= "INSPECT" then
        return false
    end
    local imported = guildData.warcraftLogs and guildData.warcraftLogs.members or {}
    if imported[key] or imported[fullKey] then
        return false
    end

    local entry = existing or {}
    local changed = entry.detectedSpecKey ~= specKey
    entry.fullName = entry.fullName or name
    entry.detectedSpecKey = specKey
    entry.raidSpecKey = specKey
    entry.classFile = classFile or entry.classFile
    entry.source = "INSPECT"
    entry.confirmed = false
    entry.receivedAt = GC.Util.Now()
    entry.updatedAt = GC.Util.Now()
    guildData.remoteProfiles[key] = entry
    if changed then
        GC:FireCallback("ROSTER_UPDATED")
    end
    return changed
end

function GC.Roster:GetProfile(name, guildData)
    local normalized = GC.Util.NormalizeName(GC.Client.isForever and GC.Util.PlayerIdentityName(name) or name)
    local ownName = GC.Util.NormalizeName(GC:GetPlayerFullName())
    local ownShortName = GC.Util.NormalizeName(GC.Util.PlayerIdentityName(GC:GetPlayerFullName()))
    if normalized == ownName or normalized == ownShortName then
        return GC.Profile:Get()
    end

    guildData = guildData or GC.DB:GetGuild()
    local shortName = GC.Util.NormalizeName(GC.Util.PlayerIdentityName(name))
    local remote = guildData.remoteProfiles[normalized] or guildData.remoteProfiles[shortName]
    if remote then
        return remote
    end

    local imported = guildData.warcraftLogs and guildData.warcraftLogs.members or {}
    return imported[normalized] or imported[shortName]
end

function GC.Roster:GetSummary()
    local summary = {
        total = #self.members,
        online = 0,
        knownProfiles = 0,
        confirmedProfiles = 0,
        classCounts = {},
        specCounts = {},
        secondarySpecCounts = {},
        coverageSpecCounts = {},
        importedProfiles = 0,
    }

    -- Einmal fuer den ganzen Durchlauf, nicht einmal je Mitglied: Sonst laeuft
    -- bei 200 Mitgliedern zweihundertfach der Vorgabenbaum durch.
    local rules = self:GetRaiderRules()
    local guildData = GC.DB:GetGuild()

    for _, member in ipairs(self.members) do
        if member.online then
            summary.online = summary.online + 1
        end
        if member.classFile then
            summary.classCounts[member.classFile] = (summary.classCounts[member.classFile] or 0) + 1
        end

        local profile = self:GetProfile(member.name, guildData)
        if profile then
            -- Gezaehlt wird weiter alles, was in der Gilde steht - nur die
            -- Abdeckung, aus der die Rekrutierungsvorschlaege entstehen, zaehlt
            -- ausschliesslich Spieler, die tatsaechlich raiden koennen.
            local counts = self:CountsForCoverage(member, rules)
            local specKey = profile.raidSpecKey or profile.detectedSpecKey
            if specKey and GC.SpecByKey[specKey] then
                summary.knownProfiles = summary.knownProfiles + 1
                summary.specCounts[specKey] = (summary.specCounts[specKey] or 0) + 1
                if counts then
                    summary.coverageSpecCounts[specKey] = (summary.coverageSpecCounts[specKey] or 0) + 1
                end
            end
            local secondarySpecKey = profile.secondarySpecKey
            if secondarySpecKey and GC.SpecByKey[secondarySpecKey] then
                summary.secondarySpecCounts[secondarySpecKey] = (summary.secondarySpecCounts[secondarySpecKey] or 0) + 1
                if counts then
                    summary.coverageSpecCounts[secondarySpecKey] = (summary.coverageSpecCounts[secondarySpecKey] or 0) + 1
                end
            end
            if profile.confirmed then
                summary.confirmedProfiles = summary.confirmedProfiles + 1
            end
            if profile.source == "WARCRAFT_LOGS" then
                summary.importedProfiles = summary.importedProfiles + 1
            end
        end
    end
    return summary
end

local rosterEvents = CreateFrame("Frame")
rosterEvents:RegisterEvent("GUILD_ROSTER_UPDATE")
rosterEvents:RegisterEvent("PLAYER_GUILD_UPDATE")
rosterEvents:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_GUILD_UPDATE" then
        GC.Roster:Request()
    else
        GC.Roster:ScheduleScan()
    end
end)

GC:RegisterCallback("PLAYER_LOGIN", GC.Roster, function(self)
    self:Request()
    C_Timer.After(2, function()
        self:Scan()
    end)
end)
