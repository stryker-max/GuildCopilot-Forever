local _, GC = ...

-- === Raidsuche (LFM) =======================================================
--
-- Das Werkzeug zum Auffüllen eines Raids: ein Suchzettel (Instanz, Termin,
-- Lootregeln, Sollbesetzung), aus dem sich der Chatspruch ableitet, dazu der
-- Zulauf - wer auf den Spruch antwortet, mit Einladen-Knopf und Vorlagen.
-- Konzept und Owner-Entscheidungen: docs/KONZEPT-raidsuche-lfm.md.
--
-- Grundsätze aus dem Konzept, die dieser Code einhält:
--   1. Der Spruch ist eine Ableitung des Zettels, kein zweites Formular.
--      Gepostet wird nur bestätigter Text (confirmedText-Muster der Werbung).
--   2. Ehrliche Zahlen: Klassen sind sicher (Gruppendaten, Whisper-GUID),
--      Specs nur aus Selbstauskunft (Raidprofil) oder Zuordnung im Zulauf.
--      Wer keine hat, wird KEINER Rolle zugeschlagen.
--   3. Jede Nachricht nach draußen ist ein Klick oder der eine Tastendruck
--      der Automatik (Chat.lua, GuildCopilotForeverAutoPostFrame). Kein Timer.
--
-- Owner-Entscheidung „nur ein Raid": genau EIN Suchzettel (plan), keine
-- Planliste. Mehrere Termine werden über Vorlagen vorbereitet.

GC.RaidSearch = {}

-- Höchstens eine Antwort je 40 Plätze, 10 Nachrichten je Antwort, 12
-- Suchzettel-Vorlagen, 8 Antwortvorlagen. Neue Listen ohne Obergrenze gibt es
-- im Projekt bewusst nicht; GC.DB:Prune() sichert dieselben Deckel nach.
local MAX_RESPONSES = 40
local MAX_RESPONSE_MESSAGES = 10
local MAX_TEMPLATES = 12
local MAX_REPLY_TEMPLATES = 8

-- WeekdayOfISO zählt Montag als 1; dieselbe Reihenfolge wie das Kalenderblatt.
local WEEKDAY_SHORT = { "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" }

local ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }
local ROLE_LABEL = { TANK = "Tank", HEALER = "Heiler", DAMAGER = "DD" }

-- Spec-Erkennung aus dem Antworttext ("kann holy"). Nur ein VORSCHLAG, und
-- nur wenn die Klasse bereits sicher feststeht (GUID): "holy" allein kann
-- Priester wie Paladin meinen, innerhalb einer bekannten Klasse ist es
-- eindeutig. Ganze Wörter, dieselbe Vorsicht wie GC.LeadClassAliases.
local SPEC_TEXT_ALIASES = {
    ["WARRIOR:1"] = { "arms", "waffen" },
    ["WARRIOR:2"] = { "fury", "furor" },
    ["WARRIOR:3"] = { "prot", "protection", "schutz", "tank" },
    ["PALADIN:1"] = { "holy", "heilig", "heal" },
    ["PALADIN:2"] = { "prot", "protection", "schutz", "tank" },
    ["PALADIN:3"] = { "retri", "ret", "vergelter", "vergeltung" },
    ["HUNTER:1"] = { "bm", "beast" },
    ["HUNTER:2"] = { "mm", "marksman" },
    ["HUNTER:3"] = { "surv", "survival" },
    ["PRIEST:1"] = { "disc", "diszi", "disziplin" },
    ["PRIEST:2"] = { "holy", "heilig", "heal" },
    ["PRIEST:3"] = { "shadow", "schatten", "sp" },
    ["SHAMAN:1"] = { "ele", "elemental", "elementar" },
    ["SHAMAN:2"] = { "enh", "enhancer", "verst" },
    ["SHAMAN:3"] = { "resto", "restoration", "heal" },
    ["MAGE:1"] = { "arcane", "arkan" },
    ["MAGE:2"] = { "fire", "feuer" },
    ["MAGE:3"] = { "frost" },
    ["WARLOCK:1"] = { "affli", "gebrechen" },
    ["WARLOCK:2"] = { "demo" },
    ["WARLOCK:3"] = { "destro", "zerstoerung" },
    ["DRUID:1"] = { "balance", "boomkin", "eule", "moonkin" },
    ["DRUID:2"] = { "feral", "wildheit", "bear", "cat", "tank" },
    ["DRUID:3"] = { "resto", "restoration", "heal" },
}

-- === Datenzugriff ==========================================================

function GC.RaidSearch:GetData()
    local guildData = GC.DB:GetGuild()
    guildData.raidSearch = guildData.raidSearch or {}
    local data = guildData.raidSearch
    if type(data.templates) ~= "table" then
        data.templates = {}
    end
    return data
end

function GC.RaidSearch:GetSettings()
    local settings = GC.DB:GetSettings()
    if type(settings.raidSearch) ~= "table" then
        -- Ein SavedVariables-Stand von vor dieser Version: MergeDefaults hat
        -- den Zweig beim ADDON_LOADED angelegt, aber ein Test oder ein von
        -- Hand bearbeiteter Bestand kann ihn verloren haben.
        settings.raidSearch = {}
    end
    return settings.raidSearch
end

function GC.RaidSearch:GetPlan()
    local plan = self:GetData().plan
    return type(plan) == "table" and plan or nil
end

function GC.RaidSearch:IsSearching()
    local plan = self:GetPlan()
    return plan ~= nil and plan.status == "SUCHT"
end

-- === Suchzettel ============================================================

function GC.RaidSearch:NewPlan()
    local first = GC.RaidInstances[1]
    local plan = {
        createdBy = GC:GetPlayerFullName(),
        createdAt = GC.Util.Now(),
        status = "ENTWURF",
        zone = first and first.name or "",
        zoneShort = first and first.short or "",
        size = first and first.size or (GC.Client.isForever and 5 or 25),
        dateISO = GC.Util.TodayISO(),
        timeText = "19:30",
        marker = 0,
        loot = { rule = "", hr = "", srLink = "" },
        note = "",
        need = { roles = { TANK = 0, HEALER = 0, DAMAGER = 0 }, specs = {} },
        confirmedText = nil,
        responses = {},
        tombstones = {},
    }
    -- Die gildenweite Lootregel aus dem Gildenprofil ist die beste Vorbelegung;
    -- das Feld bleibt Freitext und darf je Abend abweichen.
    local lootSystem = GC.Util.Trim(GC.DB:GetActiveGuildProfile().lootSystem)
    if lootSystem ~= "" then
        plan.loot.rule = lootSystem
    end
    self:GetData().plan = plan
    GC:FireCallback("RAIDSEARCH_UPDATED")
    return plan
end

function GC.RaidSearch:EnsurePlan()
    return self:GetPlan() or self:NewPlan()
end

-- Jede inhaltliche Änderung am Zettel entwertet den bestätigten Spruch - die
-- Bestätigung gilt dem Text, der aus GENAU diesem Stand entstanden ist.
local function TouchPlan(plan)
    plan.confirmedText = nil
    GC:FireCallback("RAIDSEARCH_UPDATED")
end

function GC.RaidSearch:SetZone(name, short, size)
    local plan = self:EnsurePlan()
    plan.zone = GC.Util.Trim(name)
    plan.zoneShort = GC.Util.Trim(short)
    if tonumber(size) then
        plan.size = math.max(2, math.min(40, math.floor(tonumber(size))))
    end
    TouchPlan(plan)
end

function GC.RaidSearch:SetSize(size)
    local plan = self:EnsurePlan()
    plan.size = math.max(2, math.min(40, math.floor(tonumber(size) or plan.size or 25)))
    TouchPlan(plan)
end

function GC.RaidSearch:SetDate(dateISO)
    local plan = self:EnsurePlan()
    local normalized = GC.Util.NormalizeDateInput(dateISO)
    if GC.Util.IsValidISODate(normalized) then
        plan.dateISO = normalized
        TouchPlan(plan)
        return true
    end
    return false
end

-- "1930", "19.30", "19:3", "19" - eingegeben wird, was die Hand hergibt,
-- gespeichert wird "19:30". Dasselbe Prinzip wie NormalizeDateInput.
function GC.RaidSearch.NormalizeTimeInput(value)
    local text = GC.Util.Trim(value)
    if text == "" then
        return ""
    end
    local hours, minutes = text:match("^(%d%d?)[:%.](%d%d?)$")
    if not hours then
        hours, minutes = text:match("^(%d%d?)(%d%d)$")
    end
    if not hours then
        hours = text:match("^(%d%d?)$")
        minutes = "0"
    end
    hours = tonumber(hours)
    minutes = tonumber(minutes)
    if not hours or not minutes or hours > 23 or minutes > 59 then
        return nil
    end
    return string.format("%02d:%02d", hours, minutes)
end

function GC.RaidSearch:SetTime(value)
    local plan = self:EnsurePlan()
    local normalized = self.NormalizeTimeInput(value)
    if not normalized then
        return false
    end
    plan.timeText = normalized
    TouchPlan(plan)
    return true
end

function GC.RaidSearch:SetLootRule(value)
    local plan = self:EnsurePlan()
    plan.loot.rule = GC.Util.Trim(value)
    TouchPlan(plan)
end

function GC.RaidSearch:SetHardReserve(value)
    local plan = self:EnsurePlan()
    plan.loot.hr = GC.Util.Trim(value)
    TouchPlan(plan)
end

function GC.RaidSearch:SetSrLink(value)
    local plan = self:EnsurePlan()
    plan.loot.srLink = GC.Util.Trim(value)
    TouchPlan(plan)
end

function GC.RaidSearch:SetNote(value)
    local plan = self:EnsurePlan()
    plan.note = GC.Util.SafeChatText(GC.Util.Trim(value), 120)
    TouchPlan(plan)
end

function GC.RaidSearch:SetMarker(markerIndex)
    local plan = self:EnsurePlan()
    markerIndex = math.floor(tonumber(markerIndex) or 0)
    -- Ein zweiter Klick auf das aktive Symbol nimmt es wieder heraus - der
    -- Spruch kommt auch ohne aus, und LFM-Zeilen leben von Kürze.
    plan.marker = (markerIndex >= 1 and markerIndex <= 8 and markerIndex ~= plan.marker)
        and markerIndex or 0
    TouchPlan(plan)
end

function GC.RaidSearch:AdjustRoleNeed(role, delta)
    if not ROLE_LABEL[role] then
        return
    end
    local plan = self:EnsurePlan()
    local roles = plan.need.roles
    roles[role] = math.max(0, math.min(40, (tonumber(roles[role]) or 0) + delta))
    TouchPlan(plan)
end

function GC.RaidSearch:AddSpecWish(specKey)
    if not GC.SpecByKey[specKey] then
        return
    end
    local plan = self:EnsurePlan()
    plan.need.specs[specKey] = math.min(9, (tonumber(plan.need.specs[specKey]) or 0) + 1)
    TouchPlan(plan)
end

function GC.RaidSearch:RemoveSpecWish(specKey)
    local plan = self:GetPlan()
    if not plan or not plan.need.specs[specKey] then
        return
    end
    plan.need.specs[specKey] = nil
    TouchPlan(plan)
end

-- Fuer die Kaestchenliste (wie Klassen & Specs): an/aus statt hoch-/runter.
-- Angehakt heisst schlicht "einmal gewuenscht"; die Stueckzahl bleibt im
-- Datenmodell moeglich, wird aber ueber die Liste nicht mehr hochgezaehlt.
function GC.RaidSearch:SetSpecWish(specKey, enabled)
    if not GC.SpecByKey[specKey] then
        return
    end
    local plan = self:EnsurePlan()
    plan.need.specs[specKey] = enabled and math.max(1, tonumber(plan.need.specs[specKey]) or 1) or nil
    TouchPlan(plan)
end

function GC.RaidSearch:HasSpecWish(specKey)
    local plan = self:GetPlan()
    return plan ~= nil and (tonumber(plan.need.specs[specKey]) or 0) > 0
end

-- Alle Spec-Wuensche loeschen (Knopf im Auswahlfenster).
function GC.RaidSearch:ClearSpecWishes()
    local plan = self:GetPlan()
    if not plan then
        return
    end
    plan.need.specs = {}
    TouchPlan(plan)
end

-- Die Spec-Wünsche in stabiler Reihenfolge (Klassenreihenfolge, dann
-- Spec-Index), damit Anzeige und Spruch nicht bei jedem Aufruf würfeln.
function GC.RaidSearch:GetSpecWishes()
    local plan = self:GetPlan()
    local wishes = {}
    if not plan then
        return wishes
    end
    for _, classFile in ipairs(GC.ClassOrder) do
        for _, spec in ipairs(GC.Classes[classFile].specs) do
            local count = tonumber(plan.need.specs[spec.key]) or 0
            if count > 0 then
                wishes[#wishes + 1] = { specKey = spec.key, count = count, spec = spec }
            end
        end
    end
    return wishes
end

-- === Termin ================================================================

-- "heute 19:30", "morgen 19:30", sonst "Do 19:30" - für den Spruch. Die
-- Langform fürs Fenster hängt das Datum an.
function GC.RaidSearch:FormatWhen(plan, long)
    plan = plan or self:GetPlan()
    if not plan then
        return ""
    end
    local dateISO = plan.dateISO or ""
    local label
    local today = GC.Util.TodayISO()
    if dateISO == today then
        label = "heute"
    elseif dateISO == GC.Util.AddDaysISO(1) then
        label = "morgen"
    else
        label = WEEKDAY_SHORT[GC.Util.WeekdayOfISO(dateISO) or 0] or dateISO
    end
    if long then
        local day, month = dateISO:match("^%d%d%d%d%-(%d%d)%-(%d%d)$")
        if day then
            -- match liefert (Monat, Tag) in dieser Reihenfolge des Musters.
            label = label .. " " .. month .. "." .. day .. "."
        end
    end
    local timeText = GC.Util.Trim(plan.timeText)
    if timeText ~= "" then
        label = label .. " " .. timeText
    end
    return label
end

-- Wer laut Abmeldung am Termin fehlt. Nur eine Auskunft am Zettel - die
-- Abmeldungen selbst pflegt die Mitgliederpflege.
function GC.RaidSearch:GetAbsentAtDate()
    local plan = self:GetPlan()
    if not plan or not GC.Util.IsValidISODate(plan.dateISO) then
        return {}
    end
    local names = {}
    for _, entry in ipairs(GC.Roster:GetGuildAbsences()) do
        local absence = entry.absence or {}
        if GC.Util.IsDateInRange(plan.dateISO, absence.from, absence.to) then
            names[#names + 1] = GC.Util.PlayerIdentityName(entry.member.name)
        end
    end
    return names
end

-- === Ist-Besetzung =========================================================

-- Wer ist schon dabei, und was zählt er? Klassen sind sicher (Gruppendaten).
-- Die Rolle kommt aus drei Quellen, in dieser Reihenfolge:
--   1. Spec-Zuordnung im Zulauf (vom Raidleiter gesetzt oder aus dem Text),
--   2. Raidprofil des Spielers (eigenes Profil oder geteiltes der Gilde),
--   3. sonst "ohne Zuordnung" - ehrlich ungezählt statt geraten.
-- Wildheit-Druiden tragen im Spec-Katalog die Rolle FLEX (Tank oder DD);
-- auch sie stehen in der Ohne-Zuordnung-Zeile, statt eine Rolle zu raten.
function GC.RaidSearch:GetRosterState()
    local state = {
        total = 0,
        roles = { TANK = 0, HEALER = 0, DAMAGER = 0 },
        unassigned = 0,
        specCounts = {},
        members = {},
    }
    local plan = self:GetPlan()
    local guildData = GC.DB:GetGuild()

    local function ResolveSpecKey(fullName)
        local key = GC.Util.NormalizeName(GC.Util.PlayerIdentityName(fullName))
        if plan then
            for _, response in ipairs(plan.responses or {}) do
                if GC.Util.NormalizeName(GC.Util.PlayerIdentityName(response.name)) == key
                    and GC.SpecByKey[response.specKey or ""] then
                    return response.specKey
                end
            end
        end
        local profile = GC.Roster:GetProfile(fullName, guildData)
        if profile and GC.SpecByKey[profile.raidSpecKey or ""] then
            return profile.raidSpecKey
        end
        return nil
    end

    local function MarkPresent(name, classFile)
        if GC.Util.Trim(name) == "" then
            return
        end
        local key = GC.Util.NormalizeName(GC.Util.PlayerIdentityName(name))
        if state.members[key] then
            return
        end
        state.total = state.total + 1
        local specKey = ResolveSpecKey(name)
        local role = specKey and GC.SpecByKey[specKey] and GC.SpecByKey[specKey].role or nil
        if specKey then
            state.specCounts[specKey] = (state.specCounts[specKey] or 0) + 1
        end
        if role and state.roles[role] ~= nil then
            state.roles[role] = state.roles[role] + 1
        else
            state.unassigned = state.unassigned + 1
        end
        state.members[key] = { name = name, classFile = classFile, specKey = specKey }
    end

    -- Dasselbe Leseverfahren wie der Anwesenheitsabgleich der Raidauswertung
    -- (RaidMonitor): Raidroster, sonst party-Einheiten, der eigene Charakter
    -- immer.
    local _, ownClassFile = UnitClass("player")
    MarkPresent(GC:GetPlayerFullName(), ownClassFile)
    if IsInRaid and IsInRaid() and GetNumGroupMembers and GetRaidRosterInfo then
        for index = 1, (GetNumGroupMembers() or 0) do
            local name, _, _, _, _, classFile = GetRaidRosterInfo(index)
            MarkPresent(name, classFile)
        end
    elseif IsInGroup and IsInGroup() and GetNumGroupMembers then
        for index = 1, math.max(0, (GetNumGroupMembers() or 0) - 1) do
            local unit = "party" .. index
            if UnitExists and UnitExists(unit) then
                local _, classFile = UnitClass(unit)
                MarkPresent(GC.Util.UnitIdentityName(unit), classFile)
            end
        end
    end
    return state
end

function GC.RaidSearch:IsInCurrentGroup(name)
    local key = GC.Util.NormalizeName(GC.Util.PlayerIdentityName(name))
    return self:GetRosterState().members[key] ~= nil
end

-- Was noch fehlt: Soll minus sicher Zugeordnete, je Rolle und je Spec-Wunsch.
function GC.RaidSearch:GetOpenNeeds(rosterState)
    local plan = self:GetPlan()
    local open = { roles = {}, specs = {}, anyRole = false }
    if not plan then
        return open
    end
    rosterState = rosterState or self:GetRosterState()
    for _, role in ipairs(ROLE_ORDER) do
        local missing = math.max(0,
            (tonumber(plan.need.roles[role]) or 0) - (rosterState.roles[role] or 0))
        open.roles[role] = missing
        if missing > 0 then
            open.anyRole = true
        end
    end
    for _, wish in ipairs(self:GetSpecWishes()) do
        local missing = math.max(0, wish.count - (rosterState.specCounts[wish.specKey] or 0))
        if missing > 0 then
            open.specs[#open.specs + 1] = { spec = wish.spec, count = missing }
        end
    end
    return open
end

-- "1 Tank, 2 Heiler, 3 DD" - der Bedarfsbaustein des Spruchs.
function GC.RaidSearch:DescribeOpenRoles(open)
    local parts = {}
    for _, role in ipairs(ROLE_ORDER) do
        local count = open.roles[role] or 0
        if count > 0 then
            parts[#parts + 1] = count .. " " .. ROLE_LABEL[role]
        end
    end
    return table.concat(parts, ", ")
end

-- === Der Spruch ============================================================

-- Wie der Werbetext (Recruitment.lua, GenerateAdvertisement): mehrere
-- Ausführlichkeitsstufen bauen, die erste nehmen, die in die 255 Bytes einer
-- Chatnachricht passt. Gekürzt wird der Reihe nach: erst die Notiz, dann die
-- Spec-Wünsche, dann die HR-Liste (sofern ein SR-Link sie ersetzt), zuletzt
-- der Instanzname durch seinen Kurznamen.
-- Termin fuer den Spruch: Wochentag UND Datum (Owner-Wunsch), dazu Uhrzeit -
-- "Fr 05.09. 19:30". Bewusst kein "heute"/"morgen" wie in der Fensteranzeige:
-- Im Chat soll das echte Datum stehen, damit niemand rechnen muss.
function GC.RaidSearch:FormatWhenForSpruch(plan)
    plan = plan or self:GetPlan()
    if not plan then
        return ""
    end
    local parts = {}
    local weekday = WEEKDAY_SHORT[GC.Util.WeekdayOfISO(plan.dateISO or "") or 0]
    local day, month = tostring(plan.dateISO or ""):match("^%d%d%d%d%-(%d%d)%-(%d%d)$")
    if weekday and day then
        parts[#parts + 1] = weekday .. " " .. month .. "." .. day .. "."
    elseif weekday then
        parts[#parts + 1] = weekday
    end
    local timeText = GC.Util.Trim(plan.timeText)
    if timeText ~= "" then
        parts[#parts + 1] = timeText
    end
    return table.concat(parts, " ")
end

-- Der Bedarf als eine Liste: erst die Rollen mit Zahl ("1 Tank"), dann die
-- ausdruecklich gewuenschten Specs als Kuerzel ("Shadow Priest") - alles in
-- EINER "noch ..."-Aufzaehlung, ohne den frueheren "(Wuensche: ...)"-Zusatz
-- (Owner-Wunsch). "withSpecs=false" laesst die Specs weg, wenn es sonst zu
-- lang wird.
function GC.RaidSearch:DescribeNeed(open, withSpecs)
    local parts = {}
    for _, role in ipairs(ROLE_ORDER) do
        local count = open.roles[role] or 0
        if count > 0 then
            parts[#parts + 1] = count .. " " .. ROLE_LABEL[role]
        end
    end
    if withSpecs then
        for _, entry in ipairs(open.specs) do
            parts[#parts + 1] = (entry.count > 1 and (entry.count .. "x ") or "")
                .. GC.SpecShort(entry.spec.key)
        end
    end
    return table.concat(parts, ", ")
end

function GC.RaidSearch:BuildAnnouncement()
    local plan = self:GetPlan()
    if not plan then
        return ""
    end
    local rosterState = self:GetRosterState()
    local open = self:GetOpenNeeds(rosterState)
    local needFull = self:DescribeNeed(open, true)
    local needRoles = self:DescribeNeed(open, false)

    local function Compose(zoneName, needText, includeNote, hrText)
        local parts = { "LFM " .. zoneName }
        local when = self:FormatWhenForSpruch(plan)
        if when ~= "" then
            parts[1] = parts[1] .. " " .. when
        end
        if plan.marker and plan.marker >= 1 and plan.marker <= 8 then
            parts[1] = parts[1] .. " {rt" .. plan.marker .. "}"
        end
        local rule = GC.Util.Trim(plan.loot.rule)
        if rule ~= "" then
            parts[#parts + 1] = rule
        end
        if hrText ~= "" then
            parts[#parts] = (parts[#parts] or "") .. ", HR: " .. hrText
        end
        if needText ~= "" then
            parts[#parts + 1] = "noch " .. needText
        elseif rosterState.total < (tonumber(plan.size) or 0) then
            parts[#parts + 1] = "noch " .. ((tonumber(plan.size) or 0) - rosterState.total)
                .. " Plätze"
        end
        local srLink = GC.Util.Trim(plan.loot.srLink)
        if srLink ~= "" then
            parts[#parts + 1] = "SR: " .. srLink
        end
        if includeNote and GC.Util.Trim(plan.note) ~= "" then
            parts[#parts + 1] = GC.Util.Trim(plan.note)
        end
        parts[#parts + 1] = "/w me"
        return table.concat(parts, " - ")
    end

    local hr = GC.Util.Trim(plan.loot.hr)
    local hrShort = hr
    if hr ~= "" and GC.Util.Trim(plan.loot.srLink) ~= "" then
        hrShort = "s. SR-Link"
    end
    local zone = GC.Util.Trim(plan.zone)
    local zoneShort = GC.Util.Trim(plan.zoneShort)
    if zoneShort == "" then
        zoneShort = zone
    end

    -- Von ausfuehrlich (mit Specs und Notiz) nach knapp (Kurzname, nur Rollen).
    local candidates = {
        Compose(zone, needFull, true, hr),
        Compose(zone, needFull, false, hr),
        Compose(zone, needRoles, false, hr),
        Compose(zone, needRoles, false, hrShort),
        Compose(zoneShort, needRoles, false, hrShort),
    }
    for _, candidate in ipairs(candidates) do
        if #candidate <= GC.Constants.MAX_CHAT_BYTES then
            return candidate
        end
    end
    return GC.Util.SafeChatText(candidates[#candidates], GC.Constants.MAX_CHAT_BYTES)
end

function GC.RaidSearch:ConfirmText(text)
    local plan = self:EnsurePlan()
    text = GC.Util.SafeChatText(text)
    if text == "" then
        plan.confirmedText = nil
        return false, "Ein leerer Suchspruch kann nicht bestätigt werden."
    end
    plan.confirmedText = text
    GC:FireCallback("RAIDSEARCH_UPDATED")
    return true, "Suchspruch bestätigt und bereit."
end

-- === Kanäle ================================================================

-- Neben den vier Kanalarten der Werbung stehen der Gildenchat und die selbst
-- beigetretenen Kanäle zur Wahl (Owner-Entscheidung). Ein eigener Kanal wird
-- unter seinem NAMEN gemerkt, nie unter seiner Nummer - die Nummer kann sich
-- mit jedem Login ändern.
local SYSTEM_CHANNEL_ALIASES = {
    "lokaleverteidigung", "localdefense", "weltverteidigung", "worlddefense",
}

function GC.RaidSearch:GetCustomChannels()
    local custom = {}
    if not GetChannelList then
        return custom
    end
    local channels = { GetChannelList() }
    for index = 1, #channels, 3 do
        local channelID = channels[index]
        local channelName = channels[index + 1]
        local disabled = channels[index + 2]
        if channelID and channelID > 0 and channelName and not disabled then
            local normalized = GC.Chat:NormalizeChannelName(channelName)
            local known = false
            for _, definition in pairs(GC.ChannelKinds) do
                for _, alias in ipairs(definition.aliases) do
                    if normalized == GC.Chat:NormalizeChannelName(alias) then
                        known = true
                        break
                    end
                end
            end
            for _, alias in ipairs(SYSTEM_CHANNEL_ALIASES) do
                if normalized == alias then
                    known = true
                    break
                end
            end
            if not known then
                custom[#custom + 1] = { id = channelID, name = channelName }
            end
        end
    end
    return custom
end

-- Alle wählbaren Ziele mit Zustand, für Kanalzeile und Posten. "key" ist
-- zugleich der Cooldown-Schlüssel in guildData.lastPosts - die Kanalarten
-- teilen ihn sich mit der Gildenwerbung, mit Absicht: Server-Drosselung und
-- der Ruf als Spammer hängen am Spieler und am Kanal, nicht am Werkzeug.
function GC.RaidSearch:GetChannelTargets()
    local settings = self:GetSettings()
    settings.channels = type(settings.channels) == "table" and settings.channels or {}
    settings.channels.custom = type(settings.channels.custom) == "table"
        and settings.channels.custom or {}
    local targets = {}
    for _, kind in ipairs({ "LFG", "TRADE", "GENERAL", "RECRUITMENT" }) do
        local channelID = GC.Chat:FindChannel(kind)
        targets[#targets + 1] = {
            key = kind,
            label = GC.ChannelKinds[kind].label,
            chatType = "CHANNEL",
            channelID = channelID,
            joined = channelID ~= nil,
            selected = settings.channels[kind] == true,
        }
    end
    targets[#targets + 1] = {
        key = "GUILD",
        label = "Gilde",
        chatType = "GUILD",
        joined = IsInGuild and IsInGuild() == true or GC:GetGuildName() ~= "",
        selected = settings.channels.GUILD == true,
    }
    for _, channel in ipairs(self:GetCustomChannels()) do
        targets[#targets + 1] = {
            key = "C:" .. channel.name,
            label = channel.name,
            chatType = "CHANNEL",
            channelID = channel.id,
            joined = true,
            selected = settings.channels.custom[channel.name] == true,
        }
    end
    return targets
end

function GC.RaidSearch:SetChannelSelected(key, selected)
    local settings = self:GetSettings()
    settings.channels = type(settings.channels) == "table" and settings.channels or {}
    settings.channels.custom = type(settings.channels.custom) == "table"
        and settings.channels.custom or {}
    local customName = tostring(key or ""):match("^C:(.+)$")
    if customName then
        settings.channels.custom[customName] = selected == true or nil
    else
        settings.channels[key] = selected == true
    end
end

-- === Posten ================================================================

-- Postet den bestätigten Spruch in die gewählten Kanäle und startet damit die
-- Suche (ENTWURF wird SUCHT). Läuft per Klick oder im Tastendruck-Kontext der
-- Automatik; StartSearch der Werbung ist das Vorbild, samt der Regel, dass
-- lastPosts erst beim ECHTEN Versand geschrieben wird.
function GC.RaidSearch:Post()
    local plan = self:GetPlan()
    if not plan then
        return false, "Kein Suchzettel angelegt."
    end
    local text = GC.Util.SafeChatText(plan.confirmedText or "")
    if text == "" then
        return false, "Bitte den Suchspruch zuerst bestätigen."
    end
    local guildData = GC.DB:GetGuild()
    local posted = {}
    local skipped = {}
    for _, target in ipairs(self:GetChannelTargets()) do
        if target.selected then
            if GC.Chat:GetRemainingCooldown(target.key) > 0 then
                skipped[#skipped + 1] = target.label .. " (Cooldown)"
            elseif not target.joined then
                skipped[#skipped + 1] = target.label .. " (nicht beigetreten)"
            elseif GC.Chat:SendChat(text, target.chatType, nil, target.channelID) then
                guildData.lastPosts[target.key] = GC.Util.Now()
                posted[#posted + 1] = target.label
            end
        end
    end

    if #posted > 0 then
        if plan.status ~= "SUCHT" then
            plan.status = "SUCHT"
            plan.startedSearchAt = GC.Util.Now()
            -- Der Suchbalken ist die sichtbare Anzeige der laufenden Suche;
            -- ein früheres Wegklicken gilt nur bis zum nächsten Start.
            self:GetSettings().bar = type(self:GetSettings().bar) == "table"
                and self:GetSettings().bar or {}
            self:GetSettings().bar.hidden = false
        end
        GC:FireCallback("RAIDSEARCH_UPDATED")
    end
    if #posted == 0 then
        return false, #skipped > 0 and table.concat(skipped, ", ") or "Keine Kanäle ausgewählt."
    end
    return true, "Gepostet in: " .. table.concat(posted, ", ")
end

function GC.RaidSearch:EndSearch()
    local plan = self:GetPlan()
    if not plan then
        return
    end
    plan.status = "BEENDET"
    plan.endedAt = GC.Util.Now()
    GC:FireCallback("RAIDSEARCH_UPDATED")
end

-- === Zulauf ================================================================

local function ResponseKey(name)
    return GC.Util.NormalizeName(GC.Util.PlayerIdentityName(name))
end

function GC.RaidSearch:FindResponse(name)
    local plan = self:GetPlan()
    if not plan then
        return nil
    end
    local key = ResponseKey(name)
    for index, response in ipairs(plan.responses or {}) do
        if ResponseKey(response.name) == key then
            return response, index
        end
    end
    return nil
end

-- Die Weiche in Chat.lua fragt hier an, BEVOR das Bewerber-Postfach zum Zug
-- kommt (Reihenfolge im Konzept festgelegt):
--   * ohne laufende Suche ändert sich am heutigen Verhalten nichts;
--   * Gildenmitglieder gehören immer dem Zulauf - das Postfach schließt sie
--     ohnehin aus, für die Raidsuche sind sie die liebsten Antworten;
--   * Externe, deren Nachricht ein Postfach-Triggerwort trägt, bleiben dem
--     Postfach - wer Anschluss sucht, ist Bewerber, kein Raid-Auffüller;
--   * alle übrigen Whisper Externer landen im Zulauf. LFM-Antworten sind
--     formlos ("kann mein mage mit?"), ein Triggerzwang würde sie verlieren.
function GC.RaidSearch:ShouldCaptureWhisper(message, sender)
    if not self:IsSearching() then
        return false
    end
    if GC.Util.Trim(sender) == ""
        or GC.Util.NormalizeName(sender) == GC.Util.NormalizeName(GC:GetPlayerFullName()) then
        return false
    end
    local plan = self:GetPlan()
    if plan.tombstones and plan.tombstones[ResponseKey(sender)] then
        return false
    end
    if not GC.Roster:IsGuildMember(sender) then
        local normalized = tostring(message or ""):lower()
        local triggers = GC.Chat:GetRecruitmentWords("whisperTriggers")
        for _, word in ipairs(triggers) do
            if normalized:find(word, 1, true) then
                return false
            end
        end
    end
    return true
end

-- Ein Spec-Vorschlag aus dem Antworttext, nur bei sicher bekannter Klasse.
function GC.RaidSearch:ReadSpecFromText(text, classFile)
    if not classFile or not GC.Classes[classFile] then
        return nil
    end
    local lowered = tostring(text or ""):lower()
    if lowered == "" then
        return nil
    end
    for _, spec in ipairs(GC.Classes[classFile].specs) do
        for _, alias in ipairs(SPEC_TEXT_ALIASES[spec.key] or {}) do
            if lowered:find("%f[%w]" .. alias .. "%f[%W]") then
                return spec.key
            end
        end
    end
    return nil
end

function GC.RaidSearch:CaptureResponse(message, sender, guid)
    local plan = self:GetPlan()
    if not plan then
        return
    end
    plan.responses = type(plan.responses) == "table" and plan.responses or {}
    local response = self:FindResponse(sender)
    if not response then
        response = {
            name = sender,
            guid = guid,
            state = "NEU",
            firstSeenAt = GC.Util.Now(),
            messages = {},
        }
        table.insert(plan.responses, 1, response)
        while #plan.responses > MAX_RESPONSES do
            table.remove(plan.responses)
        end
    end
    response.guid = response.guid or guid
    response.lastSeenAt = GC.Util.Now()
    response.messages = type(response.messages) == "table" and response.messages or {}
    table.insert(response.messages, { receivedAt = GC.Util.Now(), text = message })
    while #response.messages > MAX_RESPONSE_MESSAGES do
        table.remove(response.messages, 1)
    end
    -- Klasse aus der GUID (sicher) und Stufe aus dem Text - dieselben Leser
    -- wie im Postfach; ReadLeadDetails arbeitet auf jeder Tabelle mit
    -- classFile- und level-Feldern.
    GC.Chat:ResolveLeadClass(response)
    GC.Chat:ReadLeadDetails(response, message)
    if not GC.SpecByKey[response.specKey or ""] then
        response.specKey = self:ReadSpecFromText(message, response.classFile)
    end
    if self:GetSettings().sound then
        GC.Chat:PlaySuccessSound()
    end
    GC:FireCallback("RAIDSEARCH_UPDATED")
end

function GC.RaidSearch:SetResponseSpec(name, specKey)
    local response = self:FindResponse(name)
    if not response then
        return
    end
    response.specKey = GC.SpecByKey[specKey or ""] and specKey or nil
    GC:FireCallback("RAIDSEARCH_UPDATED")
end

function GC.RaidSearch:RemoveResponse(name)
    local plan = self:GetPlan()
    local response, index = self:FindResponse(name)
    if not plan or not response then
        return
    end
    -- Wie der Löschmerker des Postfachs, nur je Suche: Wer entfernt wurde,
    -- kommt für den Rest DIESER Suche nicht wieder herein.
    plan.tombstones = type(plan.tombstones) == "table" and plan.tombstones or {}
    plan.tombstones[ResponseKey(name)] = GC.Util.Now()
    table.remove(plan.responses, index)
    GC:FireCallback("RAIDSEARCH_UPDATED")
end

-- Gruppeneinladung, mit Umwandlung zum Schlachtzug, sobald die Fünfergruppe
-- voll ist und der Zettel mehr als fünf Plätze vorsieht. Beide Aufrufe laufen
-- im Klick-Kontext des Einladen-Knopfs. Fehlt die API in diesem Client, wird
-- das ehrlich gemeldet statt still nichts zu tun (Lektion GuildUninvite).
function GC.RaidSearch:Invite(name)
    local response = self:FindResponse(name)
    local plan = self:GetPlan()
    if plan and (tonumber(plan.size) or 0) > 5
        and not (IsInRaid and IsInRaid())
        and GetNumGroupMembers and (GetNumGroupMembers() or 0) >= 5 then
        if C_PartyInfo and type(C_PartyInfo.ConvertToRaid) == "function" then
            C_PartyInfo.ConvertToRaid()
        elseif type(ConvertToRaid) == "function" then
            ConvertToRaid()
        end
    end
    local invited = false
    if C_PartyInfo and type(C_PartyInfo.InviteUnit) == "function" then
        C_PartyInfo.InviteUnit(name)
        invited = true
    elseif type(InviteUnit) == "function" then
        InviteUnit(name)
        invited = true
    end
    if not invited then
        return false, "Dieser Client bietet keine Gruppeneinladung per Addon an."
    end
    if response then
        response.state = "EINGELADEN"
        GC:FireCallback("RAIDSEARCH_UPDATED")
    end
    return true, GC.Util.PlayerIdentityName(name) .. " wurde eingeladen."
end

function GC.RaidSearch:CountNewResponses()
    local plan = self:GetPlan()
    if not plan then
        return 0
    end
    local count = 0
    for _, response in ipairs(plan.responses or {}) do
        if response.state == "NEU" then
            count = count + 1
        end
    end
    return count
end

-- === Antwortvorlagen (zum Selbstbasteln) ===================================
--
-- Owner-Entscheidung: eine frei bearbeitbare, PERSÖNLICHE Vorlagenliste statt
-- fest verdrahteter Texte. Sie liegt lokal in den Einstellungen - Raid-
-- Antworten sind der Ton des Raidleiters, anders als die gildenweiten
-- Standardantworten des Postfachs. Zwei Beispiele stehen ab Werk da und sind
-- ebenso veränderbar; das Seeded-Flag verhindert, dass gelöschte Beispiele
-- beim nächsten Login wiederauferstehen.
function GC.RaidSearch:GetReplyTemplates()
    local settings = self:GetSettings()
    if type(settings.replyTemplates) ~= "table" then
        settings.replyTemplates = {}
    end
    if not settings.replyTemplatesSeeded then
        settings.replyTemplatesSeeded = true
        if #settings.replyTemplates == 0 then
            settings.replyTemplates[1] = {
                label = "Invite kommt",
                text = "Hallo {name}! Passt - Invite kommt. {instanz} {termin}, Loot: {loot}.",
            }
            settings.replyTemplates[2] = {
                label = "Leider voll",
                text = "Hallo {name}, danke dir - der Platz ist leider schon vergeben. "
                    .. "Viel Erfolg noch!",
            }
        end
    end
    return settings.replyTemplates
end

function GC.RaidSearch:SetReplyTemplate(index, label, text)
    local templates = self:GetReplyTemplates()
    index = tonumber(index)
    if not index or index < 1 or index > MAX_REPLY_TEMPLATES then
        return false
    end
    label = GC.Util.SafeChatText(GC.Util.Trim(label), 40)
    text = GC.Util.SafeChatText(GC.Util.Trim(text))
    if label == "" and text == "" then
        return false
    end
    templates[index] = { label = label ~= "" and label or ("Vorlage " .. index), text = text }
    GC:FireCallback("RAIDSEARCH_UPDATED")
    return true
end

function GC.RaidSearch:RemoveReplyTemplate(index)
    local templates = self:GetReplyTemplates()
    index = tonumber(index)
    if not index or not templates[index] then
        return false
    end
    table.remove(templates, index)
    GC:FireCallback("RAIDSEARCH_UPDATED")
    return true
end

function GC.RaidSearch:BuildReply(template, playerName)
    local plan = self:GetPlan()
    local replacements = {
        ["{name}"] = GC.Util.PlayerIdentityName(playerName or ""),
        ["{instanz}"] = plan and plan.zone or "",
        ["{termin}"] = plan and self:FormatWhen(plan) or "",
        ["{loot}"] = plan and GC.Util.Trim(plan.loot.rule) or "",
        ["{srlink}"] = plan and GC.Util.Trim(plan.loot.srLink) or "",
    }
    local reply = tostring(template and template.text or "")
    for token, value in pairs(replacements) do
        reply = reply:gsub(token, function()
            return value
        end)
    end
    return GC.Util.SafeChatText(GC.Util.Trim(reply))
end

-- Sendet eine der eigenen Vorlagen als Flüsternachricht. Der Klick auf die
-- Vorlage ist die bewusste Entscheidung UND das Hardware-Ereignis; der Text
-- stammt ohnehin aus der Hand des Raidleiters.
function GC.RaidSearch:SendReply(playerName, templateIndex)
    local templates = self:GetReplyTemplates()
    local template = templates[tonumber(templateIndex) or 0]
    if not template then
        return false, "Keine Vorlage gewählt."
    end
    local reply = self:BuildReply(template, playerName)
    if reply == "" then
        return false, "Die Vorlage ist leer."
    end
    if not GC.Chat:SendChat(reply, "WHISPER", nil, nil, playerName) then
        return false, "Senden nicht möglich."
    end
    local response = self:FindResponse(playerName)
    if response and response.state == "NEU" then
        response.state = "ANGESCHRIEBEN"
    end
    GC:FireCallback("RAIDSEARCH_UPDATED")
    return true, "Antwort an " .. GC.Util.PlayerIdentityName(playerName) .. " gesendet."
end

-- === Suchzettel-Vorlagen ===================================================
--
-- "Kara dienstags 19:30" als Vorlage: der Zettel ohne Zulauf, mit Wochentag
-- statt Datum. Anwenden erzeugt einen frischen Zettel mit dem nächsten
-- passenden Datum - der wiederkehrende Raid ist damit zwei Klicks.
function GC.RaidSearch:SaveTemplate()
    local plan = self:GetPlan()
    if not plan then
        return false, "Kein Suchzettel zum Speichern."
    end
    local templates = self:GetData().templates
    local weekday = GC.Util.WeekdayOfISO(plan.dateISO) or 1
    local template = {
        label = GC.Util.Trim(plan.zoneShort ~= "" and plan.zoneShort or plan.zone)
            .. " " .. (WEEKDAY_SHORT[weekday] or "?") .. " " .. (plan.timeText or ""),
        zone = plan.zone,
        zoneShort = plan.zoneShort,
        size = plan.size,
        weekday = weekday,
        timeText = plan.timeText,
        marker = plan.marker,
        loot = GC.Util.DeepCopy(plan.loot),
        note = plan.note,
        need = GC.Util.DeepCopy(plan.need),
        savedAt = GC.Util.Now(),
    }
    -- Eine Vorlage je Instanz+Wochentag+Uhrzeit: erneutes Speichern erneuert
    -- sie, statt die Liste mit Fast-Doppelten zu füllen.
    for index, existing in ipairs(templates) do
        if existing.label == template.label then
            templates[index] = template
            GC:FireCallback("RAIDSEARCH_UPDATED")
            return true, "Vorlage „" .. template.label .. "“ erneuert."
        end
    end
    table.insert(templates, 1, template)
    while #templates > MAX_TEMPLATES do
        table.remove(templates)
    end
    GC:FireCallback("RAIDSEARCH_UPDATED")
    return true, "Vorlage „" .. template.label .. "“ gespeichert."
end

-- Das nächste Datum mit diesem Wochentag; heute zählt mit (der Raid heute
-- Abend ist der häufigste Fall, in dem jemand die Vorlage zieht).
function GC.RaidSearch.NextDateForWeekday(weekday)
    local today = GC.Util.TodayISO()
    local todayWeekday = GC.Util.WeekdayOfISO(today) or 1
    local delta = ((tonumber(weekday) or 1) - todayWeekday) % 7
    return delta == 0 and today or GC.Util.AddDaysISO(delta)
end

function GC.RaidSearch:ApplyTemplate(index)
    local template = self:GetData().templates[tonumber(index) or 0]
    if not template then
        return false, "Vorlage nicht gefunden."
    end
    local plan = self:NewPlan()
    plan.zone = template.zone or plan.zone
    plan.zoneShort = template.zoneShort or plan.zoneShort
    plan.size = tonumber(template.size) or plan.size
    plan.dateISO = self.NextDateForWeekday(template.weekday)
    plan.timeText = template.timeText or plan.timeText
    plan.marker = tonumber(template.marker) or 0
    plan.loot = GC.Util.DeepCopy(template.loot or plan.loot)
    plan.note = template.note or ""
    plan.need = GC.Util.DeepCopy(template.need or plan.need)
    GC:FireCallback("RAIDSEARCH_UPDATED")
    return true, "Vorlage „" .. tostring(template.label) .. "“ angewendet."
end

function GC.RaidSearch:RemoveTemplate(index)
    local templates = self:GetData().templates
    index = tonumber(index)
    if not index or not templates[index] then
        return false
    end
    table.remove(templates, index)
    GC:FireCallback("RAIDSEARCH_UPDATED")
    return true
end

-- === Ereignisse ============================================================

-- Ein Beitritt oder Austritt ändert Ist-Besetzung und Zulauf-Zustände; die
-- Seite merkt sich das über den üblichen Sammelweg, der Suchbalken frischt
-- sich über seinen eigenen Takt auf.
local raidSearchEvents = CreateFrame("Frame")
raidSearchEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
raidSearchEvents:SetScript("OnEvent", function()
    if GC.UI and GC.UI.Invalidate then
        GC.UI:Invalidate("RAIDSEARCH")
    end
end)
