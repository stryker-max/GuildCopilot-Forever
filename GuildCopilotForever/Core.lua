local addonName, GC = ...

_G.GuildCopilotForever = GC

GC.addonName = addonName
GC.callbacks = {}
GC.initialized = false

function GC:Print(message)
    local prefix = "|cff4ec9ffGuild Copilot Forever:|r "
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. tostring(message))
    end
end

function GC:RegisterCallback(eventName, owner, callback)
    if type(eventName) ~= "string" or type(callback) ~= "function" then
        return
    end

    self.callbacks[eventName] = self.callbacks[eventName] or {}
    table.insert(self.callbacks[eventName], { owner = owner, callback = callback })
end

function GC:FireCallback(eventName, ...)
    local callbacks = self.callbacks[eventName]
    if not callbacks then
        return
    end

    for _, entry in ipairs(callbacks) do
        local ok, err = pcall(entry.callback, entry.owner, ...)
        if not ok then
            self:Print("|cffff5555Fehler in " .. eventName .. ":|r " .. tostring(err))
        end
    end
end

-- === Messung ==============================================================
--
-- Ob ein Ruckler vom Addon kommt, laesst sich nicht aus dem Code lesen, nur
-- messen. Diese Messung ist standardmaessig aus und kostet dann genau einen
-- Tabellenzugriff je Aufruf; eingeschaltet wird sie mit "/gcpf debug".
--
-- Gemessen wird mit debugprofilestop() statt GetTimePreciseSec(): Ersteres
-- gibt es in jeder Spielfassung, Letzteres nicht.
GC.Perf = {
    enabled = false,
    samples = {},
}

function GC.Perf:Clock()
    if type(debugprofilestop) == "function" then
        return debugprofilestop()
    end
    return nil
end

-- Lua 5.1 (WoW) kennt unpack global, spaetere Fassungen nur table.unpack.
local unpackValues = unpack or table.unpack

-- Die Anzahl der Rueckgabewerte MIT zaehlen, statt sie spaeter aus der Tabelle
-- zu erraten.
--
-- "#t" ist keine Antwort auf "wie viele Werte waren es?": Bei { 1, 2, nil }
-- liefert die Laenge 2, das nachgestellte nil geht verloren, und bei einer
-- Luecke wie { 1, nil, 3 } darf Lua sich zwischen 1 und 3 frei entscheiden -
-- die Laenge einer Tabelle mit Loechern ist ausdruecklich undefiniert. Genau
-- deshalb gibt es table.pack in spaeteren Fassungen; WoWs Lua 5.1 hat es
-- nicht, also hier von Hand. select("#", ...) zaehlt die Werte, nicht die
-- belegten Tabellenplaetze.
local function PackResults(...)
    return select("#", ...), { ... }
end

function GC.Perf:Measure(label, fn, ...)
    if type(fn) ~= "function" then
        return
    end
    if not self.enabled then
        return fn(...)
    end
    -- Die Rueckgabe muss durchgereicht werden, und zwar VOLLSTAENDIG.
    --
    -- Hier stand "fn(...)" ohne return: Ausgeschaltet lieferte die Messung das
    -- Ergebnis der gemessenen Funktion, eingeschaltet nichts. Damit aenderte
    -- "/gcpf debug" das Programmverhalten statt es nur zu beobachten - eine
    -- Messung, die das Gemessene veraendert, ist wertlos, und der naechste
    -- Aufrufer waere darauf hereingefallen. Die Zwischentabelle kostet eine
    -- Belegung je Aufruf; das ist genau dann hinnehmbar, wenn ohnehin gemessen
    -- wird, und im Regelfall (aus) wird sie nie angelegt.
    local started = self:Clock()
    local count, results = PackResults(fn(...))
    local finished = self:Clock()
    if not started or not finished then
        return unpackValues(results, 1, count)
    end
    local elapsed = finished - started
    local sample = self.samples[label]
    if not sample then
        sample = { count = 0, total = 0, worst = 0 }
        self.samples[label] = sample
    end
    sample.count = sample.count + 1
    sample.total = sample.total + elapsed
    if elapsed > sample.worst then
        sample.worst = elapsed
    end
    return unpackValues(results, 1, count)
end

function GC.Perf:Reset()
    self.samples = {}
end

-- Sortiert nach der schlechtesten Einzelmessung: Ein Ruckler ist ein einzelner
-- langer Aufruf, kein hoher Durchschnitt.
function GC.Perf:Report()
    local rows = {}
    for label, sample in pairs(self.samples) do
        rows[#rows + 1] = { label = label, sample = sample }
    end
    if #rows == 0 then
        return { "Noch nichts gemessen." }
    end
    table.sort(rows, function(left, right)
        return left.sample.worst > right.sample.worst
    end)
    local lines = {}
    for index = 1, math.min(#rows, 12) do
        local row = rows[index]
        lines[#lines + 1] = string.format("%s: %d\195\151, schlimmste %.1f ms, Schnitt %.1f ms",
            row.label, row.sample.count, row.sample.worst, row.sample.total / row.sample.count)
    end
    return lines
end

GC.Util = {}

function GC.Util.Trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:match("^%s*(.-)%s*$") or ""
end

function GC.Util.NormalizeName(name)
    name = GC.Util.Trim(name):lower()
    -- Spaces can separate a Forever first name and surname. Removing them
    -- would merge distinct identities such as "Ana Bel" and "An Abel".
    if GC.Client.isForever then return (name:gsub("%s+", " ")) end
    return name:gsub("%s+", "")
end

function GC.Util.PlayerShortName(name)
    if type(name) ~= "string" then
        return ""
    end
    return name:match("^([^-]+)") or name
end

-- Forever names are regional first-name/surname identities. Never invent a
-- surname from GetRealmName or treat a first name as a unique character.
function GC.Util.PlayerIdentityName(name)
    if not GC.Client.isForever then return GC.Util.PlayerShortName(name) end
    return GC.Util.Trim(name)
end

function GC.Util.JoinPlayerName(name, surname)
    if GC.Client.HasSecretArguments(name, surname) then return nil end
    name, surname = GC.Util.Trim(name), GC.Util.Trim(surname)
    if name == "" then return nil end
    if surname == "" then return name end
    local separator = Constants and Constants.CharacterNameSeparatorConsts
        and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR
    -- Do not guess the wire format if the client has not exposed it yet.
    if type(separator) ~= "string" or separator == "" then return nil end
    if name:sub(-(#separator + #surname)) == separator .. surname then return name end
    return name .. separator .. surname
end

function GC.Util.UnitIdentityName(unit)
    if GC.Client.isForever then
        local reader = UnitNameUnmodified or UnitFullName or UnitName
        if not reader then return nil end
        return GC.Util.JoinPlayerName(reader(unit))
    end
    return UnitName and UnitName(unit)
end

-- Pfadsegment, kein Realm-Slug: Namen behalten ihre UTF-8-Zeichen und ihre
-- Schreibweise. Jedes Nicht-ASCII-Byte wird einzeln percent-kodiert.
function GC.Util.EncodeURLPath(value)
    return (GC.Util.Trim(value):gsub("[^A-Za-z0-9%-%._~]", function(byte)
        return string.format("%%%02X", string.byte(byte))
    end))
end

-- Keep the complete client identity in profiles, permissions and orders.
function GC.Util.PlayerKey(name)
    return GC.Util.NormalizeName(GC.Util.PlayerIdentityName(name))
end

function GC.Util.DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}
    for key, item in pairs(value) do
        result[GC.Util.DeepCopy(key)] = GC.Util.DeepCopy(item)
    end
    return result
end

function GC.Util.MergeDefaults(target, defaults)
    target = type(target) == "table" and target or {}
    for key, defaultValue in pairs(defaults) do
        if target[key] == nil then
            target[key] = GC.Util.DeepCopy(defaultValue)
        elseif type(defaultValue) == "table" then
            if type(target[key]) ~= "table" then
                -- Alte oder von Hand bearbeitete SavedVariables dürfen einen
                -- ganzen Einstellungszweig nicht unbenutzbar machen.
                target[key] = GC.Util.DeepCopy(defaultValue)
            else
                GC.Util.MergeDefaults(target[key], defaultValue)
            end
        end
    end
    return target
end

function GC.Util.JoinGerman(items)
    if #items == 0 then
        return ""
    elseif #items == 1 then
        return items[1]
    elseif #items == 2 then
        -- Die Bindewoerter laufen durch die Sprachschicht: Auf englischen
        -- Clients wird aus "A und B" ein "A and B".
        return items[1] .. GC.L(" und ") .. items[2]
    end

    local head = {}
    for index = 1, #items - 1 do
        head[#head + 1] = items[index]
    end
    return table.concat(head, ", ") .. GC.L(" sowie ") .. items[#items]
end

function GC.Util.SafeChatText(text, maximumBytes)
    text = GC.Util.Trim(text)
    maximumBytes = math.max(0, math.floor(tonumber(maximumBytes) or GC.Constants.MAX_CHAT_BYTES))
    if #text <= maximumBytes then
        return text
    end

    local suffix = maximumBytes >= 4 and "..." or ""
    local contentBytes = maximumBytes - #suffix
    if contentBytes <= 0 then
        return suffix:sub(1, maximumBytes)
    end

    local clipped = text:sub(1, contentBytes)
    if #clipped > 0 and clipped:byte(#clipped) >= 128 then
        local sequenceStart = #clipped
        while sequenceStart > 1 do
            local byte = clipped:byte(sequenceStart)
            if byte < 128 or byte >= 192 then
                break
            end
            sequenceStart = sequenceStart - 1
        end

        local lead = clipped:byte(sequenceStart)
        local expectedBytes
        if lead and lead >= 194 and lead <= 223 then
            expectedBytes = 2
        elseif lead and lead >= 224 and lead <= 239 then
            expectedBytes = 3
        elseif lead and lead >= 240 and lead <= 244 then
            expectedBytes = 4
        end
        local availableBytes = #clipped - sequenceStart + 1
        if not expectedBytes or availableBytes < expectedBytes then
            clipped = clipped:sub(1, sequenceStart - 1)
        end
    end

    local lastSpace = clipped:match("^.*()%s")
    if suffix ~= "" and lastSpace and lastSpace > contentBytes * 0.7 then
        clipped = clipped:sub(1, lastSpace - 1)
    end
    return clipped .. suffix
end

function GC.Util.EscapeField(value)
    value = tostring(value or "")
    return value:gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\n", "%%0A")
end

function GC.Util.UnescapeField(value)
    value = tostring(value or "")
    return value:gsub("%%0A", "\n"):gsub("%%7C", "|"):gsub("%%25", "%%")
end

function GC.Util.SplitFields(payload)
    local fields = {}
    for field in (tostring(payload) .. "|"):gmatch("(.-)|") do
        fields[#fields + 1] = GC.Util.UnescapeField(field)
    end
    return fields
end

-- A sequence prevents collisions when a whole catalog is sent in one second.
local transferSequence = 0
function GC.Util.NextTransferToken()
    transferSequence = transferSequence + 1
    return tostring(GC.Util.Now()) .. "-" .. tostring(transferSequence)
end

-- Keep %XX escapes whole, including for older receivers that decode each
-- fragment before joining it. UTF-8 bytes may be split; they are joined first.
function GC.Util.ChunkEscapedPayload(payload, limit)
    local chunks, offset = {}, 1
    while offset <= #payload do
        local last = math.min(#payload, offset + limit - 1)
        if last < #payload then
            if payload:sub(last, last) == "%" then
                last = last - 1
            elseif payload:sub(last - 1, last - 1) == "%" then
                last = last - 2
            end
        end
        chunks[#chunks + 1] = payload:sub(offset, last)
        offset = last + 1
    end
    return chunks
end

function GC.Util.PruneTransfers(transfers)
    local cutoff = GC.Util.Now() - 300
    local count = 0
    for key, transfer in pairs(transfers) do
        if (tonumber(transfer.at) or 0) < cutoff then
            transfers[key] = nil
        else
            count = count + 1
        end
    end
    return count
end

-- Bounded reassembly shared by inbox and oversized order messages. Reject a
-- conflicting fragment instead of silently combining two different records.
function GC.Util.CollectTransfer(transfers, key, index, count, chunk, maxParts)
    local active = GC.Util.PruneTransfers(transfers)
    if not index or not count or index ~= math.floor(index) or count ~= math.floor(count)
        or index < 1 or count < 1 or index > count or count > maxParts
        or type(chunk) ~= "string" or #chunk > GC.Constants.MAX_CHAT_BYTES then
        return nil
    end
    local pending = transfers[key]
    if pending and (pending.count ~= count
        or (pending.chunks[index] and pending.chunks[index] ~= chunk)) then
        transfers[key] = nil
        return nil
    end
    if not pending then
        if active >= 64 then return nil end
        pending = { chunks = {}, count = count }
        transfers[key] = pending
    end
    pending.chunks[index] = chunk
    pending.at = GC.Util.Now()
    pending.receivedAt = pending.at
    for position = 1, count do
        if pending.chunks[position] == nil then return nil end
    end
    transfers[key] = nil
    return table.concat(pending.chunks)
end

-- Zeitstempel entscheiden gildenweit, welcher Stand des Gildenprofils gewinnt.
-- Die lokale Systemuhr taugt dafuer schlecht: Sie geht auf jedem Rechner ein
-- bisschen anders, und eine falsch gestellte Uhr in der Zukunft konnte jede
-- spaetere Aenderung der ganzen Gilde blockieren. GetServerTime() liefert
-- dagegen fuer alle auf demselben Realm dieselbe Zeit. Wo es die Funktion
-- nicht gibt, bleibt es bei der Systemuhr.
function GC.Util.Now()
    if GetServerTime then
        local ok, serverTime = pcall(GetServerTime)
        if ok and tonumber(serverTime) then
            return serverTime
        end
    end
    return time and time() or 0
end

function GC.Util.TodayISO()
    return date and date("%Y-%m-%d") or "1970-01-01"
end

function GC.Util.AddDaysISO(days)
    days = tonumber(days) or 0
    if date and time then
        local ok, value = pcall(date, "%Y-%m-%d", time() + (days * 24 * 60 * 60))
        if ok and type(value) == "string" and value:match("^%d%d%d%d%-%d%d%-%d%d$") then
            return value
        end
    end
    return GC.Util.TodayISO()
end

local DAYS_PER_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

function GC.Util.IsLeapYear(year)
    year = tonumber(year)
    if not year then
        return false
    end
    return year % 400 == 0 or (year % 4 == 0 and year % 100 ~= 0)
end

function GC.Util.DaysInMonth(year, month)
    month = tonumber(month)
    if not month or month < 1 or month > 12 then
        return nil
    end
    if month == 2 and GC.Util.IsLeapYear(year) then
        return 29
    end
    return DAYS_PER_MONTH[month]
end

function GC.Util.FormatISO(year, month, day)
    return string.format("%04d-%02d-%02d", tonumber(year) or 0, tonumber(month) or 0, tonumber(day) or 0)
end

function GC.Util.IsValidISODate(value)
    local year, month, day = tostring(value or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    if not year or year < 2000 or year > 2099 or not month or month < 1 or month > 12 or not day then
        return false
    end
    return day >= 1 and day <= (GC.Util.DaysInMonth(year, month) or 0)
end

-- Nimmt an, was Leute tatsaechlich tippen. Anlass war die Rueckmeldung aus der
-- Gilde: Mit "JJJJ-MM-TT" kommen viele nicht zurecht und tragen 15.08.2026 ein.
-- Das ist keine Fehleingabe, sondern die hier uebliche Schreibweise - sie wird
-- deshalb angenommen und umgerechnet. Gespeichert und synchronisiert wird
-- weiterhin ausschliesslich ISO: Nur damit funktionieren die Vergleiche
-- "liegt zwischen von und bis" ueber einen simplen Stringvergleich.
function GC.Util.NormalizeDateInput(value)
    value = GC.Util.Trim(value)
    if value == "" then
        return ""
    end
    if GC.Util.IsValidISODate(value) then
        return value
    end
    -- 15.8.2026, 15.08.2026, 15/8/2026 und dieselben mit zweistelligem Jahr.
    local day, month, year = value:match("^(%d%d?)[%.%-/](%d%d?)[%.%-/](%d%d%d%d)$")
    if not day then
        day, month, year = value:match("^(%d%d?)[%.%-/](%d%d?)[%.%-/](%d%d)$")
        if year then
            year = "20" .. year
        end
    end
    if not day then
        return value
    end
    local candidate = GC.Util.FormatISO(year, month, day)
    if not GC.Util.IsValidISODate(candidate) then
        return value
    end
    return candidate
end

local function ISODateOrdinal(value)
    if not GC.Util.IsValidISODate(value) then
        return nil
    end
    local year, month, day = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    local monthOffsets = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 }
    local leapDays = math.floor((year - 1) / 4) - math.floor((year - 1) / 100)
        + math.floor((year - 1) / 400)
    local ordinal = ((year - 1) * 365) + leapDays + monthOffsets[month] + day
    if month > 2 and (year % 400 == 0 or (year % 4 == 0 and year % 100 ~= 0)) then
        ordinal = ordinal + 1
    end
    return ordinal
end

-- Wochentag eines ISO-Datums, 1 = Montag bis 7 = Sonntag.
--
-- Gerechnet statt gefragt: date()/time() haengen an der Systemzeitzone und der
-- Sommerzeit, und ein Kalenderblatt, das je nach Uhrzeit einen Tag verrutscht,
-- waere schlimmer als keins. Die fortlaufende Tagesnummer oben gibt es ohnehin;
-- als Anker dient der 1. Januar 2000, ein Samstag.
local ANCHOR_ORDINAL = 730120
local ANCHOR_WEEKDAY = 6

function GC.Util.WeekdayOfISO(value)
    local ordinal = ISODateOrdinal(value)
    if not ordinal then
        return nil
    end
    return ((ordinal - ANCHOR_ORDINAL + ANCHOR_WEEKDAY - 1) % 7) + 1
end

function GC.Util.DaysBetweenISO(left, right)
    local leftOrdinal = ISODateOrdinal(left)
    local rightOrdinal = ISODateOrdinal(right)
    if not leftOrdinal or not rightOrdinal then
        return nil
    end
    return rightOrdinal - leftOrdinal
end

function GC.Util.IsDateInRange(value, rangeFrom, rangeTo)
    return GC.Util.IsValidISODate(value)
        and GC.Util.IsValidISODate(rangeFrom)
        and GC.Util.IsValidISODate(rangeTo)
        and value >= rangeFrom
        and value <= rangeTo
end

-- Der eigene Name aendert sich innerhalb einer Sitzung nicht. Er wurde
-- trotzdem bei jedem Aufruf neu aus drei API-Aufrufen und einer
-- Zeichenverkettung zusammengesetzt - und er steht in Schleifen ueber alle
-- Gildenmitglieder (Roster:GetProfile ruft ihn zweimal je Mitglied auf, bei
-- 500 Mitgliedern also tausendmal je Uebersicht).
--
-- Gemerkt wird ausdruecklich NUR ein belastbarer Name: Direkt nach dem Laden
-- gibt der Client noch keinen heraus, und ein gemerktes "Unbekannt" waere fuer
-- den Rest der Sitzung falsch. PLAYER_LOGIN verwirft den Merker zusaetzlich,
-- damit der erste belastbare Stand auch wirklich der gemerkte ist.
function GC:GetPlayerFullName()
    local cached = self.playerFullName
    if cached then
        return cached
    end

    if GC.Client.isForever then
        local identity = GC.Util.UnitIdentityName("player")
        if identity and identity ~= "" then self.playerFullName = identity end
        return identity or "Unbekannt"
    end

    -- Hier stand "local name, realm = UnitFullName and UnitFullName(...)".
    -- Lua kuerzt einen and-Ausdruck auf genau einen Wert, realm blieb deshalb
    -- immer leer und wurde jedes Mal ueber den Fallback unten neu geholt.
    local name, realm
    if UnitFullName then
        name, realm = UnitFullName("player")
    end
    if not name or name == "" then
        name = UnitName and UnitName("player")
    end
    if not realm or realm == "" then
        realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName and GetRealmName() or ""
    end
    -- Ohne Namen darf hier nichts verkettet werden, sonst bricht der Aufruf ab.
    if not name or name == "" then
        return "Unbekannt"
    end

    local fullName = name
    if realm and realm ~= "" then
        fullName = name .. "-" .. realm
    end
    self.playerFullName = fullName
    return fullName
end

function GC:GetGuildName()
    local guildName = GetGuildInfo and GetGuildInfo("player")
    return guildName or ""
end

function GC:GetGuildKey()
    local guildName = self:GetGuildName()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName and GetRealmName() or ""
    if guildName == "" then
        return "UNGUILDED@" .. realm
    end
    return guildName .. "@" .. realm
end

-- === Gildenwechsel im laufenden Spiel ======================================
--
-- Der gesamte Handschlag des Addons haengt am PLAYER_LOGIN: Versionsansage,
-- Gildenprofil-Anfrage, Werkstattmanifest und Auftragsabgleich laufen einmal,
-- in den ersten zwanzig Sekunden einer Sitzung. Wer einer Gilde beitritt,
-- WAEHREND er eingeloggt ist, hat diesen Moment verpasst: Roster und
-- Gildenzweig stellen sich sofort um, das Fenster sieht vollstaendig aus - und
-- der Client hat in der neuen Gilde nie etwas gesendet und nie etwas
-- angefordert. Bis zum naechsten /reload blieb er stumm. Genau das war der
-- Fall, in dem ein frisch beigetretener Charakter "keinen Abgleich" hatte.
--
-- Gemeldet wird deshalb jeder echte Wechsel des Gildenschluessels. Nur ein
-- echter: PLAYER_GUILD_UPDATE feuert auch bei jeder Rangaenderung und ein paar
-- Mal beim Anmelden, waehrend GetGuildInfo noch nichts liefert.
-- Liest den aktuellen Gildenschluessel und meldet einen Wechsel. Beim ersten
-- Aufruf (Login) wird nur gemerkt, nicht gemeldet: Da hat sich nichts
-- geaendert, da faengt es an.
function GC:RefreshGuildKey(fireChange)
    local guildKey = self:GetGuildKey()
    if guildKey == self.lastGuildKey then
        return false
    end
    local previous = self.lastGuildKey
    self.lastGuildKey = guildKey
    if fireChange and previous ~= nil then
        self:FireCallback("GUILD_CHANGED", guildKey, previous)
        return true
    end
    return false
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName == addonName then
            GC:FireCallback("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        GC.initialized = true
        -- Erst ab hier gibt der Client Namen und Realm belastbar heraus; ein
        -- frueher gemerkter Stand wird deshalb verworfen.
        GC.playerFullName = nil
        GC:RefreshGuildKey(false)
        GC:FireCallback("PLAYER_LOGIN")
        GC:Print(GC.LFormat("v{v} geladen. Öffnen mit |cffffffff/gcpf|r.",
            { v = GC.Constants.VERSION }))
    elseif event == "PLAYER_GUILD_UPDATE" then
        -- Ab hier steht der Gildenzustand des Clients fest - auch ein "keine
        -- Gilde" ist jetzt eine Antwort und nicht mehr bloss ein noch nicht
        -- geladener Zustand. Profile.StampGuildKey haengt daran.
        GC.guildStateKnown = true
        GC:RefreshGuildKey(true)
    end
end)
