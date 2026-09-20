local _, GC = ...

GC.RaidMonitor = {
    session = nil,
    incoming = {},
    -- Je Anfragendem ein Zeitstempel: Eine Anfrage darf die eines anderen
    -- nicht aus der Drossel draengen.
    lastAnswerAt = {},
    selectedSessionID = nil,
    combatLogTracking = false,
}

-- Ein Abend kann bis zu drei Quellen belegen (Live, Warcraft Logs, Logdatei);
-- mit 12 Plätzen waren das nur vier Abende. 24 hält acht volle Abende.
--
-- Diese Rechnung galt, solange nur EIGENE Quellen in der Ablage lagen. Seit
-- jeder Raidteilnehmer seine Fassung als eigene Quelle abliefert
-- ("SYNC:<Name>"), fuellt ein einziger Abend die Ablage: Gemessen wurden 6
-- gespeicherte alte Raidabende, danach 40 SYNC-Antworten EINES Abends - alle
-- sechs alten Abende waren geloescht und alle 24 Plaetze mit Fassungen
-- desselben Abends belegt.
--
-- Die Ablage hat deshalb zwei getrennte Kontingente: unveraendert 24 Plaetze
-- fuer die eigenen Quellen (acht volle Abende) und MAX_SYNC_SUMMARIES
-- zusaetzliche Plaetze fuer fremde Fassungen. Fremde Fassungen verdraengen
-- eine eigene Auswertung nie, sie kommen obendrauf - deshalb steigt der
-- Gesamtdeckel um genau dieses Kontingent.
--
-- Zwoelf fremde Fassungen, davon hoechstens sechs je Abend: Repariert wird aus
-- Hoechstwerten, und dafuer bringt die siebte Fassung desselben Abends
-- praktisch nichts mehr, waehrend sechs auch dann noch reichen, wenn die
-- Haelfte davon selbst lueckenhaft ist.
local MAX_SYNC_PER_SESSION = 6
local MAX_SYNC_SUMMARIES = 12
local MAX_STORED_SESSIONS = 24 + MAX_SYNC_SUMMARIES
local MIN_SEGMENT_SECONDS = 15
local WIPE_RATIO = 0.5
local MAX_PAYLOAD_BYTES = 165
local MIN_ANSWER_INTERVAL = 30
local INCOMING_TTL = 5 * 60

-- Wie viele unfertige Auswertungs-Uebertragungen gleichzeitig offenstehen
-- duerfen. Die Tabelle hatte gar keinen Deckel und wurde bei JEDEM
-- eintreffenden Paket komplett durchlaufen (Verfallspruefung) - ueber einen
-- Sturm von 10.000 Paketen also quadratisch. 40 liegt weit ueber dem, was
-- nach der Antwortwahl (siehe REPAIR_RESPONDER_SLOTS) noch zusammenkommt, und
-- deckelt zugleich den Speicher gegen Muellpakete.
local MAX_INCOMING_TRANSFERS = 40

-- Wie viele Clients auf eine Anfrage nach Auswertungen ueberhaupt antworten.
--
-- Gemessen in einer Gilde mit 250 Online: Auf eine NACKTE RQ-Anfrage schickte
-- jeder Client bis zu fuenf Auswertungen zu je acht Bloecken - 40 Pakete je
-- Client und damit 10.000 Fluesterpakete an EINEN Anfragenden. Der Kanal
-- stellt groessenordnungsmaessig zehn Pakete je Sekunde zu; alles darueber
-- ging lautlos verloren.
--
-- Die Wahl kennt nur, WER online ist - nicht, wer den gefragten Abend
-- gespeichert hat. Das ist der entscheidende Unterschied zu allen anderen
-- Anfragen im Addon, und er kostet Plaetze.
--
-- Mit drei Plaetzen war der Knopf "Auswertung anfordern" nachweislich kaputt:
-- Gemessen an 250 Online, von denen 16 % ueberhaupt eine Auswertung hatten,
-- bekamen 70 % der Anfragen NIE eine Antwort - und weil die Streuzahl rein
-- rechnerisch ist, traf es bei jedem Knopfdruck dieselben Anfragenden. Wer
-- einmal Pech hatte, hatte es dauerhaft.
--
-- Beide Anfragen bekommen deshalb dieselbe grosszuegige Platzzahl. Sie ist
-- keine Sparmassnahme mehr, sondern nur noch eine Obergrenze gegen den Sturm:
-- Aus 24 Gewaehlten haelt bei 16 % Halterquote im Schnitt knapp vier der
-- Anfragende tatsaechlich fuer sich bereit, und die Wahrscheinlichkeit, dass
-- KEINER etwas hat, liegt unter zwei Prozent.
--
--   GEZIELT (RequestRepair) - nennt eine Sitzungskennung, also genau EINE
--   Auswertung zu acht Paketen je Antwortendem: hoechstens 24 x 8 = 192.
--
--   NACKT (Knopf "Auswertung anfordern") - waere mit fuenf Abenden je
--   Antwortendem bei 24 Plaetzen 960 Pakete. Deshalb schickt die nackte
--   Antwort nur noch die MAX_BARE_ANSWER_SUMMARIES juengsten Abende; damit
--   bleibt es bei 24 x 16 = 384. Wer mehr will, fragt gezielt nach einem
--   Abend - genau dafuer ist die Kennung da.
local SUMMARY_RESPONDER_SLOTS = 24
local REPAIR_RESPONDER_SLOTS = 24
local MAX_BARE_ANSWER_SUMMARIES = 2

-- Wie lange eine unterbrochene Sitzung fortgesetzt werden darf. Danach ist sie
-- kein laufender Abend mehr, sondern ein liegengebliebener - sie wird beim
-- naechsten Login ausgewertet und abgelegt, nicht weggeworfen.
local MAX_RESUME_AGE = 8 * 60 * 60

-- Wie viele Verbrauchseintraege je Teilnehmer aufgehoben werden - waehrend des
-- Abends UND in der abgelegten Auswertung.
--
-- Die Zahl steht bewusst nur EINMAL. Bis 0.9.116 gab es zwei: hundert waehrend
-- des Abends, vierzig beim Ablegen. Die Zaehler waren dadurch nie falsch, aber
-- die Gegenpruefung gegen das Kampflog vom 09.08.2026 endete bei siebzehn von
-- 175 Paaren im Ungewissen, weil das Protokoll der Vielverbraucher gekappt war.
--
-- 200 ist mit Reserve gewaehlt: Der hoechste je gemessene Wert liegt bei 70
-- Eintraegen an einem Sechsstundenabend. Was darueber hinausgeht, faellt
-- weiterhin vorn heraus und wird in consumableLogDropped ehrlich gezaehlt -
-- ein Protokoll, das schweigend unvollstaendig ist, waere schlimmer als ein
-- gekapptes, das es sagt.
local CONSUMABLE_LOG_LIMIT = 200

-- Der Herzschlag haelt die Sitzung im Raid zusammen: Nachzuegler und
-- Wiedereinsteiger erfahren davon, ohne dass jemand etwas anstossen muss.
-- Gesendet wird hoechstens alle SESSION_HEARTBEAT_INTERVAL Sekunden und immer
-- nur von einem: Wer einen fremden Herzschlag hoert, schweigt bis zum
-- naechsten Takt. Die Pruefung selbst laeuft im SESSION_HEARTBEAT_CHECK-Takt
-- und kostet einen Vergleich.
local SESSION_HEARTBEAT_INTERVAL = 60
local SESSION_HEARTBEAT_CHECK = 20

-- Der Rahmen, dessen OnUpdate den Herzschlag antreibt - dieselbe Bauweise wie
-- die Bulk-Warteschlange in Sync.lua: Ein verstecktes Frame bekommt kein
-- OnUpdate, ausserhalb einer Sitzung kostet der Herzschlag damit keinen
-- einzigen Handleraufruf pro Bild. Verdrahtet wird das Skript unten bei den
-- uebrigen Ereignisrahmen.
local heartbeatFrame = CreateFrame("Frame")
heartbeatFrame:Hide()
local heartbeatElapsed = 0

-- COMBAT_LOG_EVENT_UNFILTERED ist das haeufigste Ereignis im Spiel; im Raid
-- feuert es tausende Male pro Sekunde. Schon die Zustellung an einen Handler,
-- der sofort wieder aussteigt, kostet bei jedem einzelnen Ereignis Zeit.
-- Abonniert wird es deshalb nur, solange eine Sitzung wirklich mitschreibt.
-- Die uebrigen Ereignisse sind selten und bleiben dauerhaft registriert.
local raidEvents = CreateFrame("Frame")
raidEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
raidEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
raidEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
-- pcall, weil ein Client-Build ohne diese Ereignisse beim Registrieren
-- unbekannter Namen einen Fehler wirft - dann bleibt es bei der Heuristik.
pcall(raidEvents.RegisterEvent, raidEvents, "ENCOUNTER_START")
pcall(raidEvents.RegisterEvent, raidEvents, "ENCOUNTER_END")

function GC.RaidMonitor:SetCombatLogTracking(enabled)
    enabled = GC.Client.combatAnalysis and enabled and true or false
    if self.combatLogTracking == enabled then
        return
    end
    self.combatLogTracking = enabled
    if enabled then
        raidEvents:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    else
        raidEvents:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
end

local function SanitizedText(value, maximumBytes)
    value = GC.Util.Trim(value)
    value = value:gsub("[,;|]", " ")
    return GC.Util.SafeChatText(value, maximumBytes or 40)
end

local function NewCounters()
    local counters = {}
    for _, category in ipairs(GC.ConsumableCategories) do
        counters[category.key] = 0
    end
    return counters
end

-- Haelt alle laufenden Anwesenheitsuhren an und schreibt die bis dahin
-- gesammelte Zeit gut. Ohne Zeitpunkt wird nur angehalten - dann ist gar nicht
-- bekannt, bis wann jemand da war, und geschaetzte Zeit waere schlechter als
-- keine.
local function ClosePresence(session, at)
    for _, participant in pairs(session.participants) do
        if participant.presentSince then
            if at then
                participant.seconds = participant.seconds + math.max(0, at - participant.presentSince)
            end
            participant.presentSince = nil
        end
    end
end

function GC.RaidMonitor:IsInRaidGroup()
    return IsInRaid and IsInRaid() == true
end

function GC.RaidMonitor:IsInAnyGroup()
    if self:IsInRaidGroup() then
        return true
    end
    return IsInGroup and IsInGroup() == true
end

-- 2 = Raidleiter, 1 = Assistent, 0 = Mitglied, nil = nicht in der Gruppe.
function GC.RaidMonitor:GetRaidRank(playerName)
    if not self:IsInRaidGroup() or not GetNumGroupMembers or not GetRaidRosterInfo then
        return nil
    end
    local wanted = GC.Util.NormalizeName(GC.Util.PlayerIdentityName(playerName or GC:GetPlayerFullName()))
    for index = 1, (GetNumGroupMembers() or 0) do
        local name, rank = GetRaidRosterInfo(index)
        if name and GC.Util.NormalizeName(GC.Util.PlayerIdentityName(name)) == wanted then
            return tonumber(rank) or 0
        end
    end
    return nil
end

-- Eine Sitzung starten, beenden und einstellen darf nur ein Offizier: die
-- Gildenränge mit Zugriff auf die Mitgliederpflege (Vorgabe Rang 0 und 1, in
-- den Einstellungen änderbar und gildenweit abgeglichen).
--
-- Bis 0.9.82 genügte zusätzlich der Raidrang. Das war zu weit gefasst: Ein
-- Assistent ist im Pull-Chaos schnell ernannt, und ein versehentliches
-- „Sitzung beenden" schneidet den Abend mittendrin ab. Dieselbe Prüfung
-- entscheidet auch über eingehende Sitzungspakete – dort ist der Gildenrang
-- ohnehin die belastbarere Angabe, weil der Raidrang eines Fremden gar nicht
-- feststeht.
function GC.RaidMonitor:CanControlSession(playerName)
    return GC.Roster:CanAccessMemberCare(playerName or GC:GetPlayerFullName())
end

function GC.RaidMonitor:GetParticipant(session, name, classFile)
    if not session or not name or name == "" then
        return nil
    end
    local key = GC.Util.NormalizeName(GC.Util.PlayerIdentityName(name))
    if key == "" then
        return nil
    end
    local participant = session.participants[key]
    if not participant then
        participant = {
            name = GC.Util.PlayerIdentityName(name),
            classFile = classFile,
            seconds = 0,
            presentSince = nil,
            deaths = 0,
            resurrects = 0,
            interrupts = 0,
            dispels = 0,
            consumables = NewCounters(),
        }
        session.participants[key] = participant
        session.participantOrder[#session.participantOrder + 1] = key
        -- Ein neuer Teilnehmer macht gemerkte Fehltreffer ungueltig: Wer bis
        -- eben unbekannt war, koennte jetzt genau dieser Neue sein.
        session.nameLookup = nil
        session.nameLookupMisses = nil
    end
    if classFile and not participant.classFile then
        participant.classFile = classFile
    end
    return participant
end

-- Der Combat Log nennt Namen roh ("Schurke" oder "Schurke-Realm"), die
-- Teilnehmer sind normalisiert abgelegt. Statt bei jedem der vielen tausend
-- Kampfereignisse zwei Stringfunktionen zu durchlaufen, merkt sich die Sitzung
-- das Ergebnis je roher Schreibweise - Fehltreffer (NPCs, Fremde) als false,
-- denn gerade sie sind der haeufigste Fall.
--
-- Genau diese Fehltreffer waren aber unbegrenzt: Gemessen wurden 5.025
-- Eintraege nach 5.000 verschiedenen NPC-Namen, und ein Trashabend erzeugt
-- Zehntausende. Die TREFFER sind harmlos - es gibt hoechstens 40 Teilnehmer,
-- und jeder belegt eine Handvoll Schreibweisen.
--
-- Gedeckelt werden deshalb nur die Fehltreffer, und beim Ueberlauf werden auch
-- nur sie geleert. Der Memo ist eine Beschleunigung, kein Zustand: Ihn zu
-- leeren kostet nichts als eine erneute Namensnormalisierung, und die
-- gemerkten Teilnehmer bleiben unangetastet.
local MAX_NAME_LOOKUP_MISSES = 2000

function GC.RaidMonitor:FindParticipant(session, name)
    if not session or not name then
        return nil
    end
    local lookup = session.nameLookup
    if lookup then
        local cached = lookup[name]
        if cached ~= nil then
            return cached or nil
        end
    end
    local participant = session.participants[GC.Util.NormalizeName(GC.Util.PlayerIdentityName(name))]
    lookup = lookup or {}
    session.nameLookup = lookup
    if participant then
        lookup[name] = participant
        return participant
    end

    local misses = (tonumber(session.nameLookupMisses) or 0) + 1
    if misses > MAX_NAME_LOOKUP_MISSES then
        for key, cached in pairs(lookup) do
            if cached == false then
                lookup[key] = nil
            end
        end
        misses = 1
    end
    lookup[name] = false
    session.nameLookupMisses = misses
    return nil
end

function GC.RaidMonitor:SyncParticipants()
    local session = self.session
    if not session then
        return
    end

    local now = GC.Util.Now()
    local present = {}

    -- Die Einheit wird mitgereicht, weil daran haengt, was jemand beim
    -- Eintreten schon an Fläschchen, Elixieren und Essen traegt. Das laesst
    -- sich nur am lebenden Spieler ablesen, nicht im Kampfprotokoll.
    local function MarkPresent(name, classFile, unit)
        local participant = name and self:GetParticipant(session, name, classFile)
        if not participant then
            return
        end
        -- Wer die Verbindung verloren hat, bleibt Teilnehmer der Sitzung -
        -- aber seine Anwesenheitsuhr steht. Vorher zaehlte die blosse
        -- Raidmitgliedschaft: Wer nach zwanzig Minuten rausflog und nicht
        -- wiederkam, stand am Ende mit der vollen Abenddauer da, solange ihn
        -- niemand aus dem Raid nahm. Beim Wiedereinloggen laeuft die Uhr
        -- einfach weiter; die bis dahin gesammelte Zeit bleibt erhalten.
        if unit and UnitIsConnected and UnitIsConnected(unit) == false then
            return
        end
        present[participant] = true
        participant.presentSince = participant.presentSince or now
        self:ScanCarriedConsumables(unit, participant)
        -- Nur die eigene Waffe ist lesbar; Naeheres beim Waffenscan selbst.
        if unit == "player" then
            self:ScanWeaponConsumables(participant)
        end
    end

    -- Wer die Sitzung mitschreibt, ist immer dabei. Ohne diese Zeile bliebe
    -- eine Sitzung ausserhalb eines Raids ganz ohne Teilnehmer.
    local _, ownClassFile = UnitClass("player")
    MarkPresent(GC:GetPlayerFullName(), ownClassFile, "player")

    if self:IsInRaidGroup() and GetNumGroupMembers and GetRaidRosterInfo then
        for index = 1, (GetNumGroupMembers() or 0) do
            local name, _, _, _, _, classFile = GetRaidRosterInfo(index)
            MarkPresent(name, classFile, "raid" .. index)
        end
    elseif self:IsInAnyGroup() and GetNumGroupMembers then
        -- In einer Gruppe gibt es kein Raidroster; dort zaehlen die
        -- party-Einheiten. GetNumGroupMembers zaehlt den Spieler mit.
        for index = 1, math.max(0, (GetNumGroupMembers() or 0) - 1) do
            local unit = "party" .. index
            if UnitExists and UnitExists(unit) then
                local _, classFile = UnitClass(unit)
                MarkPresent(GC.Util.UnitIdentityName(unit), classFile, unit)
            end
        end
    end

    for _, participant in pairs(session.participants) do
        if not present[participant] and participant.presentSince then
            participant.seconds = participant.seconds + (now - participant.presentSince)
            participant.presentSince = nil
        end
    end
end

-- === Entprellung des Anwesenheitsabgleichs =================================
--
-- GROUP_ROSTER_UPDATE feuert im Raid haeufig: bei jedem Bei- und Austritt,
-- jeder Rangaenderung, jedem Verschieben zwischen den Untergruppen und jedem
-- Verbindungsverlust. Ein Umsortieren des Raids loest es dutzendfach in
-- Sekunden aus, und jeder Durchlauf liest bis zu 40 Raideinheiten, fragt fuer
-- neue Teilnehmer deren Buffs ab und laeuft danach noch einmal ueber alle
-- Teilnehmer.
--
-- Gesammelt wird deshalb wie beim Gildenroster (GC.Roster:ScheduleScan): Was
-- in ROSTER_SYNC_DEBOUNCE Sekunden anfaellt, ergibt einen Durchlauf. Die
-- Verzoegerung ist unkritisch, weil die Anwesenheit ueber presentSince
-- gerechnet wird - es geht hoechstens diese eine Sekunde verloren.
--
-- Entprellt wird NUR der Ereignispfad. StartSession, ResumeSession und die
-- Anwesenheitsrechnung brauchen den sofortigen Durchlauf und rufen
-- SyncParticipants weiterhin direkt.
local ROSTER_SYNC_DEBOUNCE = 1

function GC.RaidMonitor:ScheduleSyncParticipants(delay)
    delay = tonumber(delay) or ROSTER_SYNC_DEBOUNCE
    -- Ohne C_Timer (aeltere Clients, Testumgebung) bleibt es beim sofortigen
    -- Durchlauf: Lieber ungedrosselt als gar nicht.
    if not C_Timer or type(C_Timer.After) ~= "function" then
        self:SyncParticipants()
        return false
    end
    if self.syncParticipantsPending then
        return false
    end
    self.syncParticipantsPending = true
    C_Timer.After(delay, function()
        self.syncParticipantsPending = false
        -- Die Sitzung kann in der Wartezeit geendet haben.
        if self.session then
            self:SyncParticipants()
        end
    end)
    return true
end

function GC.RaidMonitor:StartSession(sessionID, startedBy, startedAt, zone)
    if not GC.Client.combatAnalysis then return false, GC.Client.combatAnalysisReason end
    self.session = {
        id = sessionID,
        startedBy = GC.Util.PlayerIdentityName(startedBy or ""),
        startedAt = tonumber(startedAt) or GC.Util.Now(),
        zone = SanitizedText(zone or (GetRealZoneText and GetRealZoneText()) or ""),
        participants = {},
        participantOrder = {},
        pulls = {},
        segment = nil,
        -- Unter welchen Zaehlregeln dieser Abend mitgeschrieben wird. Sie
        -- haengt an der SITZUNG, nicht am Speichern: Ein Abend, der gestern
        -- unter alten Regeln begonnen und heute fortgesetzt wird, bleibt ein
        -- Abend alter Regeln.
        rulesVersion = GC.Constants.RAID_RULES_VERSION,
        -- Zeitraeume, in denen dieser Client nicht mitgeschrieben hat.
        gaps = {},
    }
    self:SetCombatLogTracking(true)
    self:SyncParticipants()
    self:BeginSessionUpkeep()
    GC:FireCallback("RAID_SESSION_UPDATED")
    return self.session
end

-- === Lücken im eigenen Mitschnitt ===========================================
--
-- Eine Lücke ist ein Zeitraum, in dem dieser Client nachweislich nicht
-- mitgeschrieben hat: ein Reload, ein Verbindungsabbruch, ein später Einstieg
-- in einen schon laufenden Abend. Sie ist die Voraussetzung für zwei Dinge –
-- die eigene Auswertung darf sich als „lückenhaft" zu erkennen geben, und nur
-- dann werden fremde Daten überhaupt angefordert.
--
-- Umgekehrt gilt: Nur ein lückenloser Mitschnitt darf zum Reparieren eines
-- fremden herangezogen werden. Sonst wäre der höhere von zwei Werten nicht
-- der vollständigere, sondern bloß der größere.
local MIN_GAP_SECONDS = 5

function GC.RaidMonitor:NoteGap(session, from, to)
    session = session or self.session
    if not session then
        return false
    end
    session.gaps = session.gaps or {}
    from = tonumber(from)
    to = tonumber(to)
    -- Ohne bekannten Beginn ist die Länge unbekannt (Absturz statt sauberem
    -- Ausloggen). Der Eintrag steht trotzdem: Dass etwas fehlt, ist die
    -- wichtigere Auskunft als wie viel.
    if not from or not to then
        session.gaps[#session.gaps + 1] = { unknown = true }
        return true
    end
    if (to - from) < MIN_GAP_SECONDS then
        return false
    end
    session.gaps[#session.gaps + 1] = { from = from, to = to }
    return true
end

-- Hat dieser Mitschnitt den Abend lückenlos gesehen?
function GC.RaidMonitor:SessionIsComplete(session)
    session = session or self.session
    if not session then
        return false
    end
    return #(session.gaps or {}) == 0
end

-- === Zwei Sitzungen zur selben Zeit ========================================
--
-- Druecken zwei Offiziere gleichzeitig auf "Sitzung starten", entstehen zwei
-- Sitzungen mit zwei Kennungen. Bis 0.9.86 behielt jeder seine eigene und
-- verwarf die fremde stillschweigend: Der Abend wurde zweimal mitgeschrieben,
-- landete in zwei Auswertungen mit je einem Teil der Teilnehmer, und die
-- unterlegene Sitzung lief weiter, bis ihr Starter sie von Hand beendete - ein
-- "Sitzung beenden" schloss immer nur eine der beiden.
--
-- Aufgeloest wird das ohne Rueckfrage und ohne Wortmeldung, ueber eine Regel,
-- die auf JEDEM Client dasselbe Ergebnis liefert: Die frueher gestartete
-- Sitzung gewinnt, bei gleicher Sekunde die kleinere Kennung. Die Startzeit
-- kommt aus der Serverzeit und ist damit fuer alle auf dem Realm dieselbe; die
-- Kennung traegt einen Zufallsanteil und entscheidet den Gleichstand eindeutig.
function GC.RaidMonitor:IsPreferredSession(candidateAt, candidateID, currentAt, currentID)
    candidateAt = tonumber(candidateAt)
    if not candidateAt or type(candidateID) ~= "string" or candidateID == "" then
        return false
    end
    currentAt = tonumber(currentAt) or 0
    if candidateAt ~= currentAt then
        return candidateAt < currentAt
    end
    return candidateID < tostring(currentID or "")
end

-- SESSION_MERGE_GRACE und DiscardSession sind mit 0.9.89 entfallen. Beide
-- gab es nur, um zu entscheiden, WANN ein eigener Mitschnitt weggeworfen
-- werden darf. Weggeworfen wird jetzt gar nichts mehr.

-- Eine fremde Sitzungsmeldung gegen die eigene halten.
--
-- Bis 0.9.88 hat diese Stelle die eigene Sitzung VERWORFEN, wenn die fremde
-- nach der Regel oben gewann. Das war die falsche Richtung: Der eigene
-- Mitschnitt ist das, was dieser Client mit eigenen Augen gesehen hat, und
-- genau der ist beim Reparieren einer fremden Lücke die belastbare Quelle.
--
-- Übernommen wird deshalb nur noch das ETIKETT des Abends – die Kennung, unter
-- der alle denselben Abend ablegen. Die Daten bleiben in jedem Fall die
-- eigenen. Weil die Regel auf jedem Client dasselbe Ergebnis liefert, einigen
-- sich am Ende alle auf dieselbe Kennung, ohne dass jemand etwas verliert.
--
-- Rueckgabe: ob diese Meldung denselben Abend meint wie die eigene Sitzung.
function GC.RaidMonitor:AdoptForeignSession(sessionID, startedBy, startedAt, zone, sender)
    if type(sessionID) ~= "string" or sessionID == "" then
        return false
    end
    local session = self.session
    if not session then
        -- Später eingestiegen: Der Abend läuft schon, mitgeschrieben wird ab
        -- jetzt. Was davor passiert ist, fehlt - und steht als Lücke drin.
        local now = GC.Util.Now()
        local evening = tonumber(startedAt) or now
        session = self:StartSession(sessionID, startedBy, evening, zone)
        self:NoteGap(session, evening, now)
        GC:FireCallback("ORDERS_BANNER",
            "Raidsitzung gestartet von " .. GC.Util.PlayerIdentityName(sender or startedBy or ""))
        return true
    end
    if session.id == sessionID then
        return true
    end
    if not self:IsPreferredSession(startedAt, sessionID, session.startedAt, session.id) then
        return false
    end

    -- Die fremde Kennung gewinnt. Angefasst werden nur Kennung und die
    -- Eckdaten des Abends; Teilnehmer, Versuche und Zähler bleiben unberührt.
    -- Hat der Abend früher begonnen als der eigene Mitschnitt, ist die
    -- Differenz genau das, was diesem Client fehlt.
    local ownStart = tonumber(session.startedAt) or GC.Util.Now()
    local evening = tonumber(startedAt) or ownStart
    if evening < ownStart then
        self:NoteGap(session, evening, ownStart)
        session.startedAt = evening
    end
    session.id = sessionID
    session.startedBy = GC.Util.PlayerIdentityName(startedBy or sender or session.startedBy or "")
    if session.zone == "" and zone then
        session.zone = SanitizedText(zone)
    end
    self:PersistSession()
    GC:FireCallback("RAID_SESSION_UPDATED")
    return true
end

function GC.RaidMonitor:BeginSession()
    if not GC.Client.combatAnalysis then return false, GC.Client.combatAnalysisReason end
    if self.session then
        -- Wer die Sitzung gestartet hat, gehoert in die Absage: Sonst steht da
        -- "laeuft bereits" und niemand weiss, ob das die eigene von vorhin ist
        -- oder gerade jemand anderes schneller war.
        local startedBy = GC.Util.PlayerIdentityName(self.session.startedBy or "")
        if startedBy ~= "" then
            return false, GC.LFormat("Die Raidsitzung läuft bereits – gestartet von {name}.",
                { name = startedBy })
        end
        return false, GC.L("Es läuft bereits eine Sitzung.")
    end
    -- Starten darf jeder. Ein Start schreibt ausschliesslich in den eigenen
    -- Mitschnitt - er nimmt niemandem etwas weg und zwingt niemandem etwas
    -- auf. Die Rangsperre stand hier, solange EINE Sitzung dem ganzen Raid
    -- gehoerte; seit jeder seinen eigenen Abend fuehrt, hat sie keinen
    -- Gegenstand mehr. Beenden (RE) wirkt weiterhin auf alle und bleibt
    -- deshalb an den Rang gebunden.
    local sessionID = tostring(GC.Util.Now()) .. tostring(math.random(1000, 9999))
    local session = self:StartSession(sessionID, GC:GetPlayerFullName(), GC.Util.Now(), nil)
    GC.Sync:AnnounceSessionStart(session)
    return true, GC.L("Raidsitzung gestartet. Anwesenheit und Auswertung laufen mit.")
end

function GC.RaidMonitor:EndSession()
    if not self.session then
        return false, "Es läuft keine Sitzung."
    end
    -- Den EIGENEN Abend beendet jeder selbst - er schließt damit nur seinen
    -- eigenen Mitschnitt ab. Der Ruf an alle (RE), der auch fremde Sitzungen
    -- beendet, bleibt den freigegebenen Rängen vorbehalten.
    local mayAnnounce = self:CanControlSession()

    local summary = self:FinishSession(GC.Util.Now())
    if summary and mayAnnounce then
        GC.Sync:AnnounceSessionEnd(summary)
    end
    if summary then
        -- Ohne festen Kanal: DistributeSummary waehlt RAID oder PARTY danach,
        -- in welcher Gruppe die Sitzung tatsaechlich lief.
        GC.Sync:DistributeSummary(summary)
    end
    local participantCount = summary and #summary.participants or 0
    return true, GC.LFormat(
        "Raidsitzung beendet. {n} Teilnehmer ausgewertet – die Auswertung steht unten in der Liste.",
        { n = participantCount })
end

-- Beendet die Sitzung, verdichtet sie zur Zusammenfassung und verwirft die
-- laufenden Rohdaten. Gespeichert wird ausschließlich die Zusammenfassung.
function GC.RaidMonitor:FinishSession(endedAt)
    local session = self.session
    if not session then
        return nil
    end

    endedAt = tonumber(endedAt) or GC.Util.Now()
    self:CloseSegment(endedAt)
    ClosePresence(session, endedAt)

    local summary = self:BuildSummary(session, endedAt)
    self.session = nil
    self:EndSessionUpkeep()
    self:SetCombatLogTracking(false)
    self:StoreSummary(summary)

    -- Hatte der eigene Mitschnitt Lücken, wird jetzt genau dafür bei den
    -- anderen nachgefragt. Das ist der einzige Anlass: Wer den Abend
    -- lückenlos gesehen hat, braucht niemanden.
    if not summary.complete then
        self:RequestRepair(summary)
    end

    GC:FireCallback("RAID_SESSION_UPDATED")
    return summary
end

-- === Die laufende Sitzung überlebt den Verbindungsabbruch ================
--
-- Sie lag bisher ausschließlich im Arbeitsspeicher. Ein Disconnect, ein
-- Absturz oder auch nur ein `/reload` warf damit den halben Abend weg – und
-- zwar genau bei dem, der ihn führt.
--
-- Gespeichert wird deshalb in die SavedVariables, und zwar **dieselbe
-- Tabelle, keine Kopie**: Während des Raids kostet das exakt nichts, weil
-- nichts umgerechnet oder umkopiert wird. Geschrieben wird die Datei ohnehin
-- erst beim Ausloggen, und dort steht sie dann fertig. Zwei Dinge müssen vor
-- dem Schreiben noch geradegezogen werden – ein offener Kampfabschnitt und
-- die laufende Anwesenheitsuhr –, sonst zählt die fortgesetzte Sitzung die
-- Zeit über die Auszeit hinweg weiter.
function GC.RaidMonitor:PersistSession()
    if not GC.DB or not GC.DB.data then
        return false
    end
    GC.DB:GetCharacter().liveSession = self.session
    return true
end

function GC.RaidMonitor:ClearPersistedSession()
    if not GC.DB or not GC.DB.data then
        return
    end
    GC.DB:GetCharacter().liveSession = nil
end

-- Beim Ausloggen: offenen Abschnitt schließen, Anwesenheitsuhren anhalten und
-- den Zeitpunkt festhalten. Die Namenszuordnung des Kampflogs fliegt raus –
-- sie ist ein reiner Zwischenspeicher und kann tausende Rohschreibweisen
-- enthalten, die niemand wieder braucht.
function GC.RaidMonitor:SaveSessionForResume(at)
    local session = self.session
    if not session then
        self:ClearPersistedSession()
        return nil
    end
    at = tonumber(at) or GC.Util.Now()
    self:CloseSegment(at)
    ClosePresence(session, at)
    session.nameLookup = nil
    session.nameLookupMisses = nil
    session.savedAt = at
    self:PersistSession()
    return session
end

-- Beim Login: fortsetzen, wenn die Unterbrechung kurz war. Ein liegen
-- gebliebener Abend wird nicht weggeworfen, sondern mit seinem letzten
-- bekannten Stand ausgewertet und abgelegt – lieber eine unvollständige
-- Auswertung als gar keine.
function GC.RaidMonitor:ResumeSession()
    if not GC.Client.combatAnalysis then return false, GC.Client.combatAnalysisReason end
    if self.session or not GC.DB or not GC.DB.data then
        return nil
    end
    local session = GC.DB:GetCharacter().liveSession
    if type(session) ~= "table" or type(session.id) ~= "string" or session.id == "" then
        self:ClearPersistedSession()
        return nil
    end

    -- Von Hand bearbeitete oder unter einer älteren Version geschriebene
    -- SavedVariables dürfen den Mitschnitt nicht in einen Lua-Fehler laufen
    -- lassen; fehlende Zweige werden ersetzt, nicht vorausgesetzt.
    session.participants = type(session.participants) == "table" and session.participants or {}
    session.participantOrder = type(session.participantOrder) == "table" and session.participantOrder or {}
    session.pulls = type(session.pulls) == "table" and session.pulls or {}
    session.nameLookup = nil
    session.nameLookupMisses = nil
    session.startedAt = tonumber(session.startedAt) or GC.Util.Now()
    session.gaps = type(session.gaps) == "table" and session.gaps or {}
    -- Eine Sitzung ohne vermerkte Regelversion stammt aus einer Fassung vor
    -- 0.9.89. Ihre Zahlen bedeuten etwas anderes und werden deshalb nie mit
    -- heutigen verrechnet.
    session.rulesVersion = tonumber(session.rulesVersion) or 1
    -- Ohne savedAt kam die Datei aus einem Absturz statt aus einem sauberen
    -- Ausloggen. Dann ist unbekannt, wie lange danach noch gespielt wurde;
    -- die offenen Uhren werden ohne Gutschrift angehalten. Lieber ein paar
    -- Minuten zu wenig als eine über Nacht weiterlaufende Anwesenheit.
    local savedAt = tonumber(session.savedAt)
    ClosePresence(session, savedAt)

    -- Genau hier entsteht die Lücke, die die Reparatur später schließen soll:
    -- Zwischen dem letzten gespeicherten Stand und jetzt hat dieser Client
    -- nichts mitbekommen. Nach einem Absturz ist nicht einmal bekannt, wie
    -- lange das war.
    self:NoteGap(session, savedAt, GC.Util.Now())

    self.session = session
    if (GC.Util.Now() - (savedAt or session.startedAt)) > MAX_RESUME_AGE then
        local summary = self:FinishSession(savedAt or session.startedAt)
        return nil, summary
    end

    self:SetCombatLogTracking(true)
    self:SyncParticipants()
    self:BeginSessionUpkeep()
    GC:FireCallback("RAID_SESSION_UPDATED")
    return session
end

-- === Herzschlag: dieselbe Sitzung auf allen Clients ======================
--
-- Alle Addon-Nutzer im Raid schreiben denselben Abend mit. Wer erst später
-- dazustößt oder nach einem Verbindungsabbruch zurückkommt, hat den
-- Startruf aber verpasst und schriebe den Rest des Abends gar nicht mit.
--
-- Der Herzschlag schließt diese Lücke, ohne dabei den Kanal zu belasten:
-- Gesendet wird höchstens einmal je SESSION_HEARTBEAT_INTERVAL, und immer nur
-- von einem – wer einen fremden Herzschlag hört, schweigt bis zum nächsten
-- Takt. Wer zuerst spricht, spricht für alle; fällt der aus, übernimmt beim
-- nächsten Takt der Nächste, ganz ohne Absprache. Damit nicht alle gleichzeitig
-- losreden, wartet der Raidleiter am kürzesten, dann die Assistenten, dann der
-- Rest, jeder noch mit einem zufälligen Aufschlag gegen Gleichstand.
function GC.RaidMonitor:HeartbeatDelay()
    local raidRank = self:GetRaidRank() or 0
    local rankDelay = 10
    if raidRank >= 2 then
        rankDelay = 0
    elseif raidRank >= 1 then
        rankDelay = 5
    end
    return SESSION_HEARTBEAT_INTERVAL + rankDelay + (self.heartbeatJitter or 0)
end

function GC.RaidMonitor:NoteHeartbeat(at)
    local session = self.session
    if session then
        session.heartbeatAt = tonumber(at) or GC.Util.Now()
    end
end

function GC.RaidMonitor:PumpHeartbeat()
    local session = self.session
    -- Ohne Rangsperre: Der Herzschlag trägt das Etikett des Abends, und wer
    -- später dazustößt, braucht es unabhängig davon, welchen Rang gerade
    -- jemand hat. Ein Sturm entsteht dadurch nicht - wer einen fremden
    -- Herzschlag hört, schweigt bis zum nächsten Takt, und der Rang entscheidet
    -- weiterhin nur, wer zuerst spricht.
    if not session or not self:IsInAnyGroup() then
        return false
    end
    local last = tonumber(session.heartbeatAt) or 0
    if (GC.Util.Now() - last) < self:HeartbeatDelay() then
        return false
    end
    -- Auch ein fehlgeschlagener Sendeversuch gilt als Takt: Sonst versucht es
    -- ein Client ohne Gruppe im Sekundentakt immer wieder.
    self:NoteHeartbeat()
    return GC.Sync:AnnounceSessionHeartbeat(session) == true
end

function GC.RaidMonitor:BeginSessionUpkeep()
    self:PersistSession()
    self.heartbeatJitter = math.random() * 4
    self:NoteHeartbeat()
    heartbeatElapsed = 0
    heartbeatFrame:Show()
end

function GC.RaidMonitor:EndSessionUpkeep()
    self:ClearPersistedSession()
    heartbeatFrame:Hide()
end

function GC.RaidMonitor:BuildSummary(session, endedAt)
    local summary = {
        id = session.id,
        startedAt = session.startedAt,
        endedAt = tonumber(endedAt) or GC.Util.Now(),
        startedBy = session.startedBy,
        zone = session.zone,
        pulls = 0,
        kills = 0,
        wipes = 0,
        participants = {},
        source = "LIVE",
        receivedAt = GC.Util.Now(),
        -- Unter welchen Zaehlregeln diese Zahlen entstanden sind, und ob der
        -- Abend dabei lueckenlos gesehen wurde. Beides entscheidet spaeter,
        -- ob diese Auswertung eine fremde reparieren darf.
        rulesVersion = tonumber(session.rulesVersion) or GC.Constants.RAID_RULES_VERSION,
        complete = self:SessionIsComplete(session),
        gaps = #(session.gaps or {}),
    }

    -- Der boss-Filter räumt auch Sitzungen älterer Versionen auf, die noch
    -- Trashkämpfe als Versuche gespeichert haben.
    for _, pull in ipairs(session.pulls) do
        if pull.boss then
            summary.pulls = summary.pulls + 1
            if pull.result == "KILL" then
                summary.kills = summary.kills + 1
            elseif pull.result == "WIPE" then
                summary.wipes = summary.wipes + 1
            end
        end
    end

    for _, key in ipairs(session.participantOrder) do
        local participant = session.participants[key]
        if participant then
            -- Eine noch laufende Anwesenheitsuhr zaehlt bis zum Stichtag mit.
            -- Beim Sitzungsende ist sie immer schon geschlossen (FinishSession
            -- ruft vorher ClosePresence) - der Zweig traegt allein die
            -- Momentaufnahme der laufenden Sitzung (BuildLiveSummary), die
            -- nichts anhalten darf.
            local seconds = tonumber(participant.seconds) or 0
            if participant.presentSince then
                seconds = seconds + math.max(0, summary.endedAt - participant.presentSince)
            end
            local entry = {
                name = participant.name,
                classFile = participant.classFile,
                seconds = math.max(0, math.floor(seconds)),
                deaths = participant.deaths,
                resurrects = participant.resurrects,
                interrupts = participant.interrupts,
                dispels = participant.dispels,
                consumables = {},
            }
            for _, category in ipairs(GC.ConsumableCategories) do
                entry.consumables[category.key] = participant.consumables[category.key] or 0
            end
            -- Das Verbrauchsprotokoll wandert vollständig in die Aufbewahrung:
            -- Es steht bereits während des Abends unter derselben Obergrenze,
            -- ein zweites Kappen hier hätte nur die Beweisführung beschnitten.
            -- Es bleibt lokal - die Zusammenfassung wird ohne dieses Feld
            -- gesendet.
            local log = participant.consumableLog
            if log and #log > 0 then
                local kept = {}
                local start = math.max(1, #log - (CONSUMABLE_LOG_LIMIT - 1))
                for index = start, #log do
                    kept[#kept + 1] = log[index]
                end
                entry.consumableLog = kept
                entry.consumableLogDropped = (participant.consumableLogDropped or 0)
                    + (start - 1)
            end
            summary.participants[#summary.participants + 1] = entry
        end
    end
    return summary
end

-- Die laufende Sitzung als Momentaufnahme: dieselbe Verdichtung wie beim
-- Beenden, nur ohne etwas anzuhalten oder abzulegen. Damit steht der Abend
-- schon in der Sitzungsliste, WAEHREND er laeuft, und laesst sich jederzeit
-- auswerten - bei jedem, der ihn mitschreibt, also auch bei allen, die ueber
-- Startruf oder Herzschlag eingestiegen sind. Das Kennzeichen "live"
-- unterscheidet die Momentaufnahme von einer abgelegten Auswertung;
-- gespeichert wird sie nie, die Ablage uebernimmt weiterhin FinishSession.
function GC.RaidMonitor:BuildLiveSummary()
    local session = self.session
    if not session then
        return nil
    end
    local summary = self:BuildSummary(session, GC.Util.Now())
    summary.live = true
    return summary
end

-- Reihenfolge, in der fremde Fassungen aufgegeben werden: zuerst die
-- brauchbarste. "Brauchbar" heisst hier ausschliesslich "taugt zum
-- Reparieren", denn dafuer sind fremde Fassungen ueberhaupt da - und
-- CanRepairFrom verlangt beides: lueckenlos gesehen (complete) und dieselbe
-- Zaehlregel-Version wie der eigene Mitschnitt desselben Abends. Eine Fassung,
-- die keine der beiden Bedingungen erfuellt, wird nie eingerechnet und ist
-- damit reine Anzeige; sie weicht zuerst.
local function ForeignKeepOrder(left, right)
    if left.rank ~= right.rank then
        return left.rank > right.rank
    end
    if left.endedAt ~= right.endedAt then
        return left.endedAt > right.endedAt
    end
    if left.size ~= right.size then
        return left.size > right.size
    end
    return left.index < right.index
end

-- Kappt die fremden Fassungen ("SYNC:<Name>") auf ihr Kontingent: hoechstens
-- MAX_SYNC_PER_SESSION je Abend und hoechstens MAX_SYNC_SUMMARIES insgesamt.
--
-- Eigene Quellen (LIVE, REPAIR, WCL, Datei) fasst diese Kappung nicht an. Sie
-- ist der Grund, warum ein einziger Abend die Ablage nicht mehr fuellen kann:
-- Vorher legte jeder Raidteilnehmer seine Fassung als eigene Quelle ab, und 40
-- Antworten desselben Abends verdraengten sechs alte Raidabende vollstaendig.
--
-- Rueckgabe: ob etwas entfernt wurde.
function GC.RaidMonitor:PruneForeignSummaries(sessions)
    local foreign = {}
    local ownRules = {}
    for index = 1, #sessions do
        local stored = sessions[index]
        local id = tostring(stored.id or "")
        if self:SourceKind(stored.source) == "SYNC" then
            foreign[#foreign + 1] = {
                index = index,
                id = id,
                endedAt = tonumber(stored.endedAt) or 0,
                size = #(stored.participants or {}),
                complete = stored.complete == true,
                rulesVersion = tonumber(stored.rulesVersion) or 1,
            }
        elseif ownRules[id] == nil then
            -- Die Zaehlregel-Version, gegen die CanRepairFrom spaeter
            -- vergleicht, steht am eigenen Mitschnitt dieses Abends. Gibt es
            -- ihn (noch) nicht, ist die heutige Version die beste Annahme.
            ownRules[id] = tonumber(stored.rulesVersion) or 1
        end
    end
    if #foreign == 0 then
        return false
    end

    local currentRules = tonumber(GC.Constants.RAID_RULES_VERSION) or 1
    for _, entry in ipairs(foreign) do
        entry.rank = (entry.complete and 2 or 0)
            + (entry.rulesVersion == (ownRules[entry.id] or currentRules) and 1 or 0)
    end
    table.sort(foreign, ForeignKeepOrder)

    local perSession = {}
    local kept = 0
    local drop
    for _, entry in ipairs(foreign) do
        local used = perSession[entry.id] or 0
        if used < MAX_SYNC_PER_SESSION and kept < MAX_SYNC_SUMMARIES then
            perSession[entry.id] = used + 1
            kept = kept + 1
        else
            drop = drop or {}
            drop[entry.index] = true
        end
    end
    if not drop then
        return false
    end
    for index = #sessions, 1, -1 do
        if drop[index] then
            table.remove(sessions, index)
        end
    end
    return true
end

function GC.RaidMonitor:StoreSummary(summary)
    if not summary or not summary.id then
        return false
    end
    -- Jede eintreffende Fassung traegt zur dauerhaften Anwesenheit bei -
    -- ausdruecklich auch eine, die die Ablage gleich wieder aussortiert
    -- (siebte SYNC-Fassung desselben Abends): Der Hoechstwert-Merge kann
    -- durch eine zusaetzliche Quelle nur vollstaendiger werden, nie falscher.
    self:RecordAttendance(summary)

    local sessions = GC.DB:GetGuild().raidSessions
    for index, stored in ipairs(sessions) do
        -- Live-, Sync- und WCL-Daten bleiben getrennt und werden nie ineinander
        -- verrechnet - deshalb identifiziert erst Kennung UND Quelle zusammen
        -- eine Auswertung. Vorher zaehlte allein die Kennung: Jeder Teilnehmer
        -- speicherte beim Sitzungsende seine eigene LIVE-Fassung, und die
        -- vollstaendigere SYNC-Fassung des Raidleiters wurde danach mit
        -- derselben Kennung als "andere Quelle" verworfen, statt neben der
        -- eigenen zu stehen. Der Quellenvergleich hatte damit nie zwei Seiten.
        if stored.id == summary.id and stored.source == summary.source then
            -- Die vollständigere Auswertung gewinnt, bei Gleichstand die neuere.
            local storedSize = #(stored.participants or {})
            local incomingSize = #(summary.participants or {})
            if incomingSize > storedSize
                or (incomingSize == storedSize and (summary.endedAt or 0) >= (stored.endedAt or 0)) then
                sessions[index] = summary
                GC:FireCallback("RAID_SESSION_UPDATED")
                return true
            end
            return false
        end
    end

    table.insert(sessions, 1, summary)
    table.sort(sessions, function(left, right)
        return (left.endedAt or 0) > (right.endedAt or 0)
    end)
    -- Erst das Kontingent der fremden Fassungen, dann die allgemeine
    -- Verdraengung. Die Reihenfolge ist der Kern der Sache: Fremde Fassungen
    -- werden nach IHRER eigenen Grenze gekappt und koennen deshalb gar nicht
    -- erst dazu kommen, eine eigene Auswertung aus der Ablage zu druecken.
    self:PruneForeignSummaries(sessions)
    -- Beim Aufräumen fliegen zuerst Abende OHNE Bosskampf (in der Stadt
    -- gestartete Probe-Sitzungen). Vorher galt reine Aktualität - zwölf
    -- Orgrimmar-Minis verdrängten den frisch importierten Raidabend, und der
    -- Import meldete Erfolg, während die Auswertung sofort wieder verschwand.
    while #sessions > MAX_STORED_SESSIONS do
        local worstIndex

        -- Fremde Fassungen weichen zuerst - ABER nur, solange sie ihr eigenes
        -- Kontingent ueberschreiten.
        --
        -- Ohne diese Bedingung war der Zweig eine Falle: Sind die Plaetze mit
        -- EIGENEN Quellen gefuellt (Live, Reparatur, Warcraft Logs und
        -- Dateiimport zusammen erreichen das in einer Raidgilde nach wenigen
        -- Wochen), dann suchte er trotzdem zuerst einen SYNC-Eintrag - und der
        -- einzige, den es gab, war der eben eingefuegte. Jede eintreffende
        -- Fremdfassung wurde also eingefuegt und im selben Durchlauf wieder
        -- entfernt. StoreSummary meldete korrekt "nicht gespeichert", der
        -- Empfang rief TryRepair daraufhin nicht mehr auf, und die Reparatur
        -- lueckenhafter Mitschnitte fiel dauerhaft und lautlos aus, waehrend
        -- die 24 Antwortenden weiter ihre Fassungen schickten.
        local foreign = 0
        for index = 1, #sessions do
            if self:SourceKind(sessions[index].source) == "SYNC" then
                foreign = foreign + 1
            end
        end
        if foreign > MAX_SYNC_SUMMARIES then
            for index = #sessions, 1, -1 do
                if self:SourceKind(sessions[index].source) == "SYNC" then
                    worstIndex = index
                    break
                end
            end
        end

        -- Sonst weicht eine EIGENE Quelle, und zwar zuerst eine ohne
        -- Bosskampf: in der Stadt gestartete Probe-Sitzungen. Vorher galt
        -- reine Aktualitaet - zwoelf Orgrimmar-Minis verdraengten den frisch
        -- importierten Raidabend, und der Import meldete Erfolg, waehrend die
        -- Auswertung sofort wieder verschwand.
        if not worstIndex then
            for index = #sessions, 1, -1 do
                local candidate = sessions[index]
                if self:SourceKind(candidate.source) ~= "SYNC"
                    and (tonumber(candidate.pulls) or 0) <= 0 then
                    worstIndex = index
                    break
                end
            end
        end
        if not worstIndex then
            for index = #sessions, 1, -1 do
                if self:SourceKind(sessions[index].source) ~= "SYNC" then
                    worstIndex = index
                    break
                end
            end
        end
        table.remove(sessions, worstIndex or #sessions)
    end
    GC:FireCallback("RAID_SESSION_UPDATED")
    -- Gemeldet wird, was hinterher wirklich in der Ablage steht. Seit dem
    -- Kontingent kann die eben eingefuegte fremde Fassung sofort wieder
    -- aussortiert worden sein - etwa die siebte desselben Abends. Ein
    -- "gespeichert" waere dann falsch: Der Empfangszaehler zaehlte sie als
    -- Neuzugang und TryRepair suchte sie vergebens.
    for index = 1, #sessions do
        if sessions[index] == summary then
            return true
        end
    end
    return false
end

-- === Anwesenheit über Abende hinweg =========================================
--
-- Die Ablage der Auswertungen ist auf wenige Wochen und wenige Plaetze
-- begrenzt - fuer die Frage "wie zuverlaessig ist jemand ueber die Saison?"
-- taugt sie deshalb nicht. Die Anwesenheit bekommt darum ihr eigenes,
-- dauerhaftes Aggregat: je Abend ein kleiner Eintrag (wer, welcher Anteil),
-- unabhaengig davon, wann die Auswertung selbst aus der Ablage faellt.
--
-- Drei Regeln halten die Zahlen belastbar:
--   * Es zaehlen nur Abende mit mindestens einem erkannten Bosskampf - in
--     der Stadt gestartete Probesitzungen verduennen sonst jede Quote.
--   * Es zaehlen nur Quellen, deren Anwesenheit echte Anwesenheit ist
--     (Live, Sync, Reparatur - ab Zaehlregel-Version 2). Warcraft Logs und
--     Logdatei messen reine Encounter-Zeit und wuerden systematisch zu
--     niedrig einzahlen.
--   * Ueber mehrere Fassungen desselben Abends gewinnt je Teilnehmer der
--     HOECHSTWERT - dasselbe Argument wie bei der Reparatur: Niemand kann
--     laenger dagewesen sein, als er da war.
local ATTENDANCE_MAX_EVENINGS = 60
local ATTENDANCE_SOURCES = { LIVE = true, SYNC = true, REPAIR = true }

function GC.RaidMonitor:RecordAttendance(summary)
    if not summary or not summary.id or summary.live then
        return false
    end
    if not ATTENDANCE_SOURCES[self:SourceKind(summary.source)] then
        return false
    end
    if (tonumber(summary.rulesVersion) or 1) < 2 then
        return false
    end
    if (tonumber(summary.pulls) or 0) <= 0 then
        return false
    end
    local duration = math.max(0,
        (tonumber(summary.endedAt) or 0) - (tonumber(summary.startedAt) or 0))
    if duration <= 0 then
        return false
    end

    local log = GC.DB:GetGuild().attendance
    local evening = log[summary.id]
    if not evening then
        evening = { participants = {} }
        log[summary.id] = evening
    end
    evening.at = math.max(tonumber(evening.at) or 0, tonumber(summary.endedAt) or 0)
    if GC.Util.Trim(summary.zone) ~= "" then
        evening.zone = summary.zone
    end
    evening.duration = math.max(tonumber(evening.duration) or 0, duration)
    for _, participant in ipairs(summary.participants or {}) do
        local key = GC.Util.PlayerKey(participant.name)
        if key ~= "" then
            local share = math.min(1, (tonumber(participant.seconds) or 0) / duration)
            local known = evening.participants[key]
            if not known then
                evening.participants[key] = {
                    name = GC.Util.PlayerIdentityName(participant.name),
                    classFile = participant.classFile,
                    share = share,
                }
            else
                known.share = math.max(tonumber(known.share) or 0, share)
                known.classFile = known.classFile or participant.classFile
            end
        end
    end

    -- Deckel: die aeltesten Abende weichen. 60 Abende sind bei drei Raids je
    -- Woche fast fuenf Monate - genug fuer jede Saisonfrage, und der Eintrag
    -- je Abend ist klein.
    local order = {}
    for id, entry in pairs(log) do
        order[#order + 1] = { id = id, at = tonumber(entry.at) or 0 }
    end
    if #order > ATTENDANCE_MAX_EVENINGS then
        table.sort(order, function(left, right)
            return left.at > right.at
        end)
        for index = ATTENDANCE_MAX_EVENINGS + 1, #order do
            log[order[index].id] = nil
        end
    end
    return true
end

-- Die Uebersicht: je Spieler die Zahl der besuchten Abende und der mittlere
-- Anwesenheitsanteil ueber ALLE erfassten Abende - ein Fehlender Abend zaehlt
-- als null, sonst stuende ein Einmalgast mit einem vollen Abend bei 100 %.
function GC.RaidMonitor:GetAttendanceOverview()
    if not (GC.DB and GC.DB.data) then
        return {}, 0
    end
    local log = GC.DB:GetGuild().attendance
    local evenings = 0
    local players = {}
    for _, evening in pairs(log) do
        evenings = evenings + 1
        for key, participant in pairs(evening.participants or {}) do
            local row = players[key]
            if not row then
                row = {
                    key = key,
                    name = participant.name,
                    classFile = participant.classFile,
                    attended = 0,
                    shareSum = 0,
                    lastAt = 0,
                }
                players[key] = row
            end
            row.attended = row.attended + 1
            row.shareSum = row.shareSum + (tonumber(participant.share) or 0)
            row.classFile = row.classFile or participant.classFile
            row.lastAt = math.max(row.lastAt, tonumber(evening.at) or 0)
        end
    end

    local rows = {}
    for _, row in pairs(players) do
        row.percent = evenings > 0
            and math.floor((row.shareSum / evenings) * 100 + 0.5) or 0
        rows[#rows + 1] = row
    end
    table.sort(rows, function(left, right)
        if left.percent ~= right.percent then
            return left.percent > right.percent
        end
        return left.name < right.name
    end)
    return rows, evenings
end

-- Löscht einen ganzen Abend mit allen Quellen (Live, Logs, Datei) aus dem
-- lokalen Bestand. Nur lokal: Andere Clients behalten ihre Kopien, und
-- "Auswertung anfordern" kann Gelöschtes bewusst zurückholen.
--
-- Löschen dürfen nur die Ränge, die auch die Mitgliederpflege öffnen
-- (Standard: Offiziere oder höher). Der Kreis ist in den Einstellungen
-- einstellbar und wird gildenweit synchronisiert.
function GC.RaidMonitor:DeleteEvening(summaryKey)
    if not GC.Roster:CanAccessMemberCare() then
        return false, "Nur die in den Einstellungen freigegebenen Ränge dürfen Auswertungen löschen."
    end
    local evening = self:GetEveningOf(summaryKey)
    if not evening then
        return false, "Keine Auswertung gewählt."
    end
    -- Die Momentaufnahme der laufenden Sitzung liegt nirgends gespeichert;
    -- "löschen" gäbe es nur als leeres Erfolgsversprechen.
    if evening.live then
        return false, "Die laufende Sitzung lässt sich nicht löschen – erst beenden."
    end
    local drop = {}
    local dropped = 0
    for _, summary in ipairs(evening.sources) do
        drop[self:SummaryKey(summary)] = true
        dropped = dropped + 1
        -- "Abend gelöscht" heisst auch: raus aus der dauerhaften Anwesenheit.
        -- Eine falsch mitgeschriebene Sitzung soll die Quote nicht weiter
        -- verfaelschen; echte Abende loescht ohnehin niemand.
        if summary.id then
            GC.DB:GetGuild().attendance[summary.id] = nil
        end
    end
    local sessions = GC.DB:GetGuild().raidSessions
    for index = #sessions, 1, -1 do
        if drop[self:SummaryKey(sessions[index])] then
            table.remove(sessions, index)
        end
    end
    if self.selectedSessionID and drop[self.selectedSessionID] then
        self.selectedSessionID = nil
    end
    GC:FireCallback("RAID_SESSION_UPDATED")
    return true, dropped > 1
        and ("Abend gelöscht (" .. dropped .. " Quellen).")
        or "Auswertung gelöscht."
end

function GC.RaidMonitor:GetSummaries()
    return GC.DB:GetGuild().raidSessions or {}
end

-- Eine gespeicherte Auswertung wird durch Kennung UND Quelle identifiziert:
-- Derselbe Abend liegt als LIVE-Mitschrift und als SYNC-Fassung des
-- Raidleiters mit derselben Kennung nebeneinander. Wo frueher die Kennung
-- allein als Auswahl diente, traf sie damit immer nur die erste von beiden -
-- die zweite Quelle liess sich gar nicht anzeigen.
function GC.RaidMonitor:SummaryKey(summary)
    if not summary then
        return nil
    end
    return tostring(summary.id or "") .. "#" .. tostring(summary.source or "LIVE")
end

-- Die ART einer Quelle, ohne den Aufzeichner: "SYNC:Alex" wird zu "SYNC".
-- Wo es darum geht, WIE eine Zahl zustande kam (Beschriftung, Anwesenheits-
-- rechnung), zaehlt die Art; wo es darum geht, WESSEN Fassung das ist
-- (Speicherschluessel), die volle Quelle.
function GC.RaidMonitor:SourceKind(source)
    source = tostring(source or "LIVE")
    return source:match("^([^:]+)") or source
end

function GC.RaidMonitor:GetSummaryByKey(summaryKey)
    if not summaryKey then
        return nil
    end
    -- Auch die Momentaufnahme der laufenden Sitzung ist waehlbar. Ihr
    -- Schluessel (Kennung + "LIVE") geht nach dem Beenden nahtlos auf die
    -- dann gespeicherte Auswertung ueber - die Auswahl bleibt einfach stehen.
    local live = self:BuildLiveSummary()
    if live and self:SummaryKey(live) == summaryKey then
        return live
    end
    for _, summary in ipairs(self:GetSummaries()) do
        if self:SummaryKey(summary) == summaryKey then
            return summary
        end
    end
    return nil
end

-- Bestand einer Quelle: Gibt es zu dieser Kennung schon eine Auswertung
-- GENAU dieser Herkunft? Der Import fragt so, ob ein Report schon da ist.
function GC.RaidMonitor:GetSummary(sessionID, source)
    for _, summary in ipairs(self:GetSummaries()) do
        if summary.id == sessionID
            and (source == nil or (summary.source or "LIVE") == source) then
            return summary
        end
    end
    return nil
end

-- === Reparatur eines lückenhaften Mitschnitts ==============================
--
-- Wer während des Abends rausfliegt oder neu lädt, hat ein Loch in seinen
-- Zahlen. Andere im Raid haben denselben Abend durchgehend gesehen – aus
-- deren Auswertung lässt sich das Loch schließen.
--
-- Verrechnet wird der HÖCHSTWERT je Teilnehmer und Zähler, nicht die Summe.
-- Das ist der entscheidende Unterschied: Eine Summe würde doppelt zählen, was
-- beide gesehen haben. Der höhere Wert dagegen ist genau der eines Clients,
-- der mehr vom Abend mitbekommen hat – und niemand kann mehr Tode gesehen
-- haben, als es gab.
--
-- Damit dieses Argument trägt, müssen ZWEI Bedingungen erfüllt sein, und beide
-- sind hart:
--
--   1. Dieselbe Zählregel-Version. Ein Client vor 0.9.87 schreibt Trommeln
--      jedem Beschenkten gut - im Vergleichslog 68 statt 28. Der Höchstwert
--      würde also nicht den vollständigeren, sondern den kaputten Zähler
--      übernehmen. Dasselbe gilt für die Anwesenheit vor 0.9.88, die
--      Offlinezeit mitzählte. Fremde Regelversionen bleiben deshalb sichtbar
--      nebeneinander stehen und werden nie eingerechnet.
--
--   2. Die fremde Quelle meldet sich selbst als lückenlos. Hatte sie eigene
--      Löcher, ist ihr höherer Wert nur die bessere Untergrenze und nicht
--      belegbar der richtige.
--
-- Warcraft-Logs- und Dateiimporte scheiden ohnehin aus: Ihre Anwesenheit ist
-- reine Encounter-Zeit und ihre Verbrauchszählung folgt eigenen Regeln.
--
-- Das Ergebnis wird als EIGENE Quelle abgelegt. Der eigene Rohmitschnitt und
-- die fremde Fassung bleiben unverändert daneben stehen - die Reparatur ist
-- damit jederzeit nachvollziehbar und umkehrbar.
local REPAIRABLE_SOURCES = {
    LIVE = true,
    SYNC = true,
}

function GC.RaidMonitor:CanRepairFrom(target, candidate)
    if not target or not candidate or target == candidate then
        return false
    end
    if not REPAIRABLE_SOURCES[self:SourceKind(candidate.source)] then
        return false
    end
    if candidate.complete ~= true then
        return false
    end
    if (tonumber(candidate.rulesVersion) or 1) ~= (tonumber(target.rulesVersion) or 1) then
        return false
    end
    -- Verrechnet werden Zahlen, und das darf nur innerhalb DESSELBEN Abends
    -- geschehen. Beleg dafuer ist die Kennung: Seit 0.9.89 einigen sich alle
    -- Mitschreiber eines Abends ueber den Herzschlag auf dieselbe.
    --
    -- Hier stand bis 0.9.90 IsSameEvening, und das war in beide Richtungen
    -- falsch:
    --
    --   zu weit - geprueft werden ueberlappende Zeit und eine halbe
    --   Teilnehmerdeckung. Zwei Gruppen derselben Gilde, die gleichzeitig
    --   unterwegs sind und sich ein paar Leute teilen, erfuellen das. Im
    --   Test wurde ein lueckenhafter Karazhan-Abend aus einer parallel
    --   laufenden Gruul-Sitzung "repariert".
    --
    --   zu eng - die Deckungsschwelle scheitert ausgerechnet dann, wenn der
    --   eigene Mitschnitt sehr lueckenhaft ist. Wer den halben Abend weg war,
    --   kennt zu wenige Teilnehmer, um auf die Haelfte zu kommen - und bekam
    --   damit gerade in dem Fall keine Reparatur, fuer den sie gedacht ist.
    --
    -- Fuer die Zuordnung in der Abendliste bleibt IsSameEvening richtig: Ein
    -- Warcraft-Logs-Report und ein Dateiimport haben gar keine gemeinsame
    -- Kennung. Verrechnet wird aus denen aber ohnehin nichts.
    return tostring(target.id or "") == tostring(candidate.id or "")
end

local function MergeHigher(into, from, key)
    local value = tonumber(from[key]) or 0
    if value > (tonumber(into[key]) or 0) then
        into[key] = value
    end
end

-- Baut aus dem eigenen Mitschnitt und allen tauglichen fremden eine ergänzte
-- Fassung. Rueckgabe: die Auswertung und die Zahl der eingerechneten Quellen.
function GC.RaidMonitor:BuildRepairedSummary(target)
    if not target then
        return nil, 0
    end
    local sources = {}
    for _, candidate in ipairs(self:GetSummaries()) do
        if self:CanRepairFrom(target, candidate) then
            sources[#sources + 1] = candidate
        end
    end
    if #sources == 0 then
        return nil, 0
    end

    local repaired = GC.Util.DeepCopy(target)
    repaired.source = "REPAIR"
    repaired.receivedAt = GC.Util.Now()
    repaired.complete = true
    repaired.gaps = 0
    repaired.repairedFrom = {}

    local byKey = {}
    for _, participant in ipairs(repaired.participants) do
        byKey[GC.Util.PlayerKey(participant.name)] = participant
    end

    for _, candidate in ipairs(sources) do
        repaired.repairedFrom[#repaired.repairedFrom + 1] =
            candidate.recordedBy or GC.Util.PlayerIdentityName(candidate.startedBy or "")
        MergeHigher(repaired, candidate, "pulls")
        MergeHigher(repaired, candidate, "kills")
        MergeHigher(repaired, candidate, "wipes")
        if (tonumber(candidate.startedAt) or 0) < (tonumber(repaired.startedAt) or 0) then
            repaired.startedAt = candidate.startedAt
        end
        if (tonumber(candidate.endedAt) or 0) > (tonumber(repaired.endedAt) or 0) then
            repaired.endedAt = candidate.endedAt
        end

        for _, participant in ipairs(candidate.participants or {}) do
            local key = GC.Util.PlayerKey(participant.name)
            local own = byKey[key]
            if not own then
                -- Wen der eigene Mitschnitt gar nicht kennt, der war
                -- vermutlich genau während der Lücke da.
                own = GC.Util.DeepCopy(participant)
                own.consumableLog = nil
                own.consumableLogDropped = nil
                byKey[key] = own
                repaired.participants[#repaired.participants + 1] = own
            else
                own.classFile = own.classFile or participant.classFile
                MergeHigher(own, participant, "seconds")
                MergeHigher(own, participant, "deaths")
                MergeHigher(own, participant, "resurrects")
                MergeHigher(own, participant, "interrupts")
                MergeHigher(own, participant, "dispels")
                own.consumables = own.consumables or {}
                for _, category in ipairs(GC.ConsumableCategories) do
                    MergeHigher(own.consumables, participant.consumables or {}, category.key)
                end
            end
        end
    end
    return repaired, #sources
end

-- Anlauf zur Reparatur aller eigenen lückenhaften Auswertungen dieses Abends.
-- Wird nach jedem Empfang aufgerufen: Die fremden Fassungen treffen verstreut
-- ein, und die erste taugliche soll nicht auf die letzte warten.
function GC.RaidMonitor:TryRepair()
    local repairedAny = false
    -- Kandidaten sind die eigenen lückenhaften Mitschnitte. Welche fremden
    -- Fassungen zu welchem Abend gehören, entscheidet BuildRepairedSummary
    -- über IsSameEvening - hier braucht es keine zweite Zuordnung.
    local targets = {}
    for _, summary in ipairs(self:GetSummaries()) do
        if self:SourceKind(summary.source) == "LIVE" and summary.complete ~= true then
            targets[#targets + 1] = summary
        end
    end

    for _, target in ipairs(targets) do
        local repaired, count = self:BuildRepairedSummary(target)
        if repaired then
            -- Die fremden Fassungen treffen verstreut ein, und nach jeder wird
            -- neu gerechnet. Gemeldet wird aber nur, wenn wirklich eine Quelle
            -- dazugekommen ist - sonst stünde dieselbe Zeile fünfmal im Chat.
            local existing = self:GetSummary(target.id, "REPAIR")
            local before = existing and #(existing.repairedFrom or {}) or 0
            if self:StoreSummary(repaired) and count > before then
                repairedAny = true
                GC:Print("Dein Mitschnitt dieses Raidabends hatte Lücken und wurde aus "
                    .. count .. (count == 1 and " fremden Mitschnitt" or " fremden Mitschnitten")
                    .. " ergänzt (" .. table.concat(repaired.repairedFrom, ", ")
                    .. "). Deine eigene Fassung bleibt unverändert daneben stehen.")
            end
        end
    end
    if repairedAny then
        GC:FireCallback("RAID_SESSION_UPDATED")
    end
    return repairedAny
end

-- Fordert die Auswertungen der anderen an, weil der eigene Mitschnitt Lücken
-- hat. Gestreut, damit nicht alle gleichzeitig antworten.
function GC.RaidMonitor:RequestRepair(summary)
    if not GC.Sync or not summary then
        return false
    end
    self.repairWantedUntil = GC.Util.Now() + 600
    -- Gefragt wird nach GENAU diesem Abend. Bis 0.9.90 ging hier eine nackte
    -- Anfrage raus, und jeder antwortete mit bis zu fünf vollständigen
    -- Auswertungen - für eine einzige Lücke ein Vielfaches an Funkverkehr,
    -- und die Antworten drängten sich gegenseitig aus der Drossel.
    if not GC.Sync:Send("RQ|" .. tostring(GC.Constants.SCHEMA_VERSION)
        .. "|" .. tostring(summary.id or ""), "GUILD") then
        return false
    end
    GC:Print("Dein Mitschnitt dieses Abends hat Lücken – die Auswertungen der "
        .. "anderen werden angefordert.")
    return true
end

-- === Derselbe Abend aus mehreren Quellen =================================
--
-- Ein Raidabend kann dreifach vorliegen: als Livesitzung, als
-- Warcraft-Logs-Report und als Offline-Import aus der Logdatei. Ihre Zahlen
-- werden nie miteinander verrechnet, die Quellen sind unterschiedlich genau.
-- In der Liste soll der Abend aber einmal stehen und nicht dreimal.
--
-- Als Fingerabdruck taugt kein Hash aus den Teilnehmern: Jede Quelle zieht die
-- Liste anders (Warcraft Logs nach friendlyPlayers, die Logdatei nach
-- Anwesenheit im Encounter, die Livesitzung nach dem Raidroster). Ein exakter
-- Vergleich schlüge also genau dann fehl, wenn er gebraucht wird. Entschieden
-- wird deshalb über beides zusammen: überschneidende Zeiträume und eine
-- Teilnehmerdeckung von mindestens der Hälfte der kleineren Liste.

local SAME_EVENING_COVERAGE = 0.5

local function ParticipantNameSet(summary)
    local names = {}
    local count = 0
    for _, participant in ipairs(summary.participants or {}) do
        local key = GC.Util.NormalizeName(GC.Util.PlayerIdentityName(participant.name or ""))
        if key ~= "" and not names[key] then
            names[key] = true
            count = count + 1
        end
    end
    return names, count
end

function GC.RaidMonitor:IsSameEvening(left, right)
    if not left or not right then
        return false
    end
    local leftStart, leftEnd = tonumber(left.startedAt) or 0, tonumber(left.endedAt) or 0
    local rightStart, rightEnd = tonumber(right.startedAt) or 0, tonumber(right.endedAt) or 0
    if leftStart > rightEnd or rightStart > leftEnd then
        return false
    end

    local leftNames, leftCount = ParticipantNameSet(left)
    local rightNames, rightCount = ParticipantNameSet(right)
    if leftCount == 0 or rightCount == 0 then
        return false
    end
    local shared = 0
    for name in pairs(leftNames) do
        if rightNames[name] then
            shared = shared + 1
        end
    end
    return shared >= math.ceil(math.min(leftCount, rightCount) * SAME_EVENING_COVERAGE)
end

-- Die Quellen eines Abends, die die Oberfläche als eigene Fassung ANBIETET.
-- Fremde Mitschnitte ("SYNC:<Name>") sind reines Reparaturmaterial: Sobald der
-- Abend aus einer eigenen Quelle vorliegt - dem eigenen Livemitschnitt, seiner
-- ergänzten Fassung oder einem selbst geholten Report (Warcraft Logs,
-- Logdatei) -, werden die fremden ausgeblendet. Gespeichert bleiben sie, und
-- die Reparatur (GetSummaries) rechnet sie unverändert ein; sie sollen nur
-- nicht als zweiter, oft unvollständiger Zahlensatz neben der eigenen Fassung
-- stehen und Verwirrung stiften - eine abgeschnittene Fremdfassung sah aus wie
-- eine konkurrierende Wahrheit. Fehlt jede eigene Quelle (man war nicht dabei),
-- bleiben die fremden sichtbar, sonst wäre der Abend gar nicht lesbar.
function GC.RaidMonitor:VisibleSources(evening)
    local sources = (evening and evening.sources) or {}
    local hasOwn = false
    for _, candidate in ipairs(sources) do
        if self:SourceKind(candidate.source) ~= "SYNC" then
            hasOwn = true
            break
        end
    end
    if not hasOwn then
        return sources
    end
    local visible = {}
    for _, candidate in ipairs(sources) do
        if self:SourceKind(candidate.source) ~= "SYNC" then
            visible[#visible + 1] = candidate
        end
    end
    return visible
end

-- Je Abend ein Eintrag. Angezeigt wird die vollständigste EIGENE Auswertung;
-- die übrigen Quellen bleiben gespeichert und werden mitgeliefert, damit die
-- Oberfläche sie (soweit eigen) anbieten und die Reparatur sie einrechnen kann.
function GC.RaidMonitor:GetEvenings()
    local evenings = {}
    -- Die laufende Sitzung steht als erster Eintrag in der Liste. Sie bleibt
    -- ein eigener Abend und sammelt keine gespeicherten Quellen unter sich:
    -- Die Momentaufnahme verschwindet mit dem Sitzungsende, und was unter ihr
    -- gruppiert waere, fiele in diesem Moment aus der Liste.
    local live = self:BuildLiveSummary()
    if live then
        evenings[1] = { summary = live, sources = { live }, live = true }
    end
    for _, summary in ipairs(self:GetSummaries()) do
        local evening
        for _, candidate in ipairs(evenings) do
            if not candidate.live and self:IsSameEvening(candidate.summary, summary) then
                evening = candidate
                break
            end
        end
        if not evening then
            evening = { summary = summary, sources = {} }
            evenings[#evenings + 1] = evening
        end
        evening.sources[#evening.sources + 1] = summary
        -- Die vollständigere Auswertung führt den Abend an; bei Gleichstand
        -- die zuerst gespeicherte, denn die Liste ist schon nach Ende sortiert.
        if #(summary.participants or {}) > #(evening.summary.participants or {}) then
            evening.summary = summary
        end
    end

    -- Zweiter Durchgang: die anzeigbaren Quellen bestimmen und den Abend von
    -- der vollständigsten SICHTBAREN Fassung anführen lassen. Eine fremde
    -- Fassung mit mehr Teilnehmern übernimmt die Kopfzeile nicht mehr - sie ist
    -- ausgeblendet und dient nur noch der stillen Reparatur.
    for _, evening in ipairs(evenings) do
        evening.visibleSources = self:VisibleSources(evening)
        local primary = evening.visibleSources[1] or evening.summary
        for _, candidate in ipairs(evening.visibleSources) do
            if #(candidate.participants or {}) > #(primary.participants or {}) then
                primary = candidate
            end
        end
        evening.summary = primary
    end
    return evenings
end

-- Übersetzt einen (womöglich veralteten) Auswahlschlüssel in einen, den die
-- Oberfläche zeigen darf: den gewählten, wenn seine Quelle sichtbar ist; sonst
-- die Primärfassung desselben Abends (eine ausgeblendete Fremdfassung fällt so
-- auf die eigene zurück); sonst nil, wenn der Abend gar nicht mehr existiert.
function GC.RaidMonitor:VisibleSummaryKey(evenings, selectedKey)
    if not selectedKey then
        return nil
    end
    for _, evening in ipairs(evenings) do
        for _, candidate in ipairs(evening.visibleSources or evening.sources) do
            if self:SummaryKey(candidate) == selectedKey then
                return selectedKey
            end
        end
        for _, candidate in ipairs(evening.sources) do
            if self:SummaryKey(candidate) == selectedKey then
                return self:SummaryKey(evening.summary)
            end
        end
    end
    return nil
end

function GC.RaidMonitor:GetEveningOf(summaryKey)
    for _, evening in ipairs(self:GetEvenings()) do
        for _, summary in ipairs(evening.sources) do
            if self:SummaryKey(summary) == summaryKey then
                return evening
            end
        end
    end
    return nil
end

-- Erkannte und ausgeschlossene Gegnernamen. Der Combat Log nennt im Raid
-- dieselben Namen tausendfach; ohne diesen Zwischenspeicher liefe fuer jedes
-- Schadensereignis die ganze Bossliste durch.
--
-- Gedeckelt wie der Teilnehmer-Memo oben (MAX_NAME_LOOKUP_MISSES): Die
-- FEHLTREFFER - jeder Trashmob, jedes Totem, jeder fremde Begleiter - sind
-- unbegrenzt und wachsen ueber einen Trashabend in die Zehntausende, waehrend
-- die TREFFER auf die Handvoll Bosse der Bossliste beschraenkt bleiben. Beim
-- Ueberlauf werden deshalb nur die Fehltreffer geleert; die erkannten Bosse
-- bleiben stehen. Der Speicher ist eine Beschleunigung, kein Zustand - ihn zu
-- leeren kostet nur eine erneute Namenssuche.
local bossLookupCache = {}
local bossLookupMisses = 0
local MAX_BOSS_LOOKUP_MISSES = 2000

-- Erkannt wird ueber den Eigennamen als Teilzeichenkette: "Prinz Malchezaar"
-- und "Prince Malchezaar" enthalten beide "Malchezaar". Damit braucht es
-- keine belegte Uebersetzung je Client-Sprache.
function GC.RaidMonitor:ResolveBoss(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local cached = bossLookupCache[name]
    if cached ~= nil then
        return cached or nil
    end

    local lowered = name:lower()
    for _, boss in ipairs(GC.RaidBosses) do
        for _, needle in ipairs(boss.names) do
            if lowered:find(needle:lower(), 1, true) then
                bossLookupCache[name] = boss
                return boss
            end
        end
    end
    bossLookupMisses = bossLookupMisses + 1
    if bossLookupMisses > MAX_BOSS_LOOKUP_MISSES then
        for key, cached in pairs(bossLookupCache) do
            if cached == false then
                bossLookupCache[key] = nil
            end
        end
        bossLookupMisses = 1
    end
    bossLookupCache[name] = false
    return nil
end

-- Nur pruefen, solange der Boss des Abschnitts noch nicht feststeht: Ist er
-- einmal erkannt, kostet der Rest des Kampfes gar nichts mehr.
function GC.RaidMonitor:NoteBossParticipant(segment, guid, name)
    if not segment or segment.bossName then
        return
    end
    if not tostring(guid or ""):find("Creature", 1, true) then
        return
    end
    local boss = self:ResolveBoss(name)
    if boss then
        segment.bossName = SanitizedText(name, 36)
        segment.bossInstance = boss.instance
    end
end

function GC.RaidMonitor:BeginSegment(startedAt)
    local session = self.session
    if not session or session.segment then
        return
    end
    session.segment = {
        startedAt = tonumber(startedAt) or GC.Util.Now(),
        playerDeaths = 0,
        lastNPCDeath = nil,
        bossDied = false,
        bossName = nil,
        bossInstance = nil,
    }
end

-- Als Versuch zählt nur ein erkannter Bosskampf: entweder meldet ihn der
-- Client über ENCOUNTER_START, oder die Namensheuristik findet einen Boss im
-- Combat Log. Reine Trashkämpfe werden verworfen - sonst stünden nach dem
-- ersten Boss längst "8 Versuche" auf der Uhr. Sterben mindestens WIPE_RATIO
-- der Anwesenden, zählt der Abschnitt als Wipe.
function GC.RaidMonitor:CloseSegment(endedAt)
    local session = self.session
    local segment = session and session.segment
    if not segment then
        return
    end
    session.segment = nil

    if not segment.bossName then
        return
    end

    endedAt = tonumber(endedAt) or GC.Util.Now()
    local duration = endedAt - segment.startedAt
    -- Ein vom Client bestätigter Encounter zählt auch, wenn er kürzer war -
    -- eine überlegene Gruppe legt Attumen in unter 15 Sekunden.
    if not segment.encounterResult and duration < MIN_SEGMENT_SECONDS then
        return
    end

    local presentCount = 0
    for _, participant in pairs(session.participants) do
        if participant.presentSince then
            presentCount = presentCount + 1
        end
    end

    -- Mindestens zwei Tote, damit ein einzelner Ausfall in kleinen Gruppen
    -- nicht sofort als Wipe gilt.
    local wipeThreshold = math.max(2, math.ceil(presentCount * WIPE_RATIO))
    -- Reihenfolge: Der wirkliche Tod des Bosses schlaegt die Wipe-Heuristik.
    -- Ein Kill, bei dem die halbe Gruppe mitstirbt (Bossmechanik am Ende), ist
    -- ein Kill - nicht erst, wenn ENCOUNTER_END feuert. Steht die Todesquote
    -- vor bossDied, wird ohne ENCOUNTER_END genau so ein Kill als Wipe gebucht.
    local result = "RESET"
    if segment.encounterResult then
        result = segment.encounterResult
    elseif segment.bossDied then
        result = "KILL"
    elseif presentCount > 0 and segment.playerDeaths >= wipeThreshold then
        result = "WIPE"
    end

    -- Der erkannte Boss hat Vorrang vor dem zuletzt gestorbenen Gegner. Genau
    -- bei einem Wipe stirbt der Boss ja nicht, und dann stand hier bisher der
    -- Name irgendeines Adds - oder gar nichts.
    session.pulls[#session.pulls + 1] = {
        name = segment.bossName or segment.lastNPCDeath or "Kampf",
        instance = segment.bossInstance,
        boss = segment.bossName ~= nil,
        startedAt = segment.startedAt,
        endedAt = endedAt,
        result = result,
    }
    GC:FireCallback("RAID_SESSION_UPDATED")
end

-- Der Anniversary-Client meldet Bosskämpfe selbst: ENCOUNTER_START nennt den
-- Boss beim Namen, ENCOUNTER_END den Ausgang. Das schlägt jede Heuristik und
-- deckt auch Bosse ab, die in der eigenen Liste fehlen.
function GC.RaidMonitor:OnEncounterStart(_, encounterName)
    local session = self.session
    if not session then
        return
    end
    if not session.segment then
        self:BeginSegment(GC.Util.Now())
    end
    local segment = session.segment
    if not segment or segment.bossName then
        return
    end
    local name = SanitizedText(encounterName, 36)
    if name ~= "" then
        segment.bossName = name
        local boss = self:ResolveBoss(name)
        segment.bossInstance = (boss and boss.instance)
            or (GetRealZoneText and GetRealZoneText()) or nil
    end
end

function GC.RaidMonitor:OnEncounterEnd(_, encounterName, _, _, success)
    local session = self.session
    local segment = session and session.segment
    if not segment then
        return
    end
    if not segment.bossName then
        local name = SanitizedText(encounterName, 36)
        if name ~= "" then
            segment.bossName = name
        end
    end
    segment.encounterResult = (tonumber(success) == 1) and "KILL" or "WIPE"
    self:CloseSegment(GC.Util.Now())
end

-- Ein Verbrauchsgegenstand wird gezaehlt, WENN er verbraucht wird - und zwar
-- jedes Mal. Entscheidend ist, welches Ereignis dafuer der Beleg ist; das
-- steht je Kategorie in GC.ConsumableCategories:
--
--   CAST  Nur das Wirkereignis beim Benutzer. Der Buff, der daraus wird,
--         zaehlt ausdruecklich NICHT. Genau daran hing die groesste
--         Verfaelschung: Trommeln buffen die ganze Gruppe, also bekam jedes
--         Gruppenmitglied jede geworfene Trommel gutgeschrieben. Im
--         Vergleichslog vom 02.08.2026 haben fuenf Spieler Trommeln geworfen -
--         angezeigt wurden sie bei acht, einer davon mit 68 statt 28.
--         Traenke mit Buff (Hast, Zerstoerung) zaehlten aus demselben Grund
--         doppelt: einmal als Zauber, einmal als eigene Aura.
--   AURA  Nur die Aura beim Beschenkten. Das gilt allein fuer Essen: Ein
--         Wirkereignis gibt es dafuer nie, der Sattgegessen-Buff erscheint
--         Sekunden nach dem Essen von selbst.
--
-- Der frueher zusaetzlich gepruefte Auraname ("Sattgegessen"/"Well Fed") ist
-- entfallen. Er hat auf dem deutschen Client ohnehin nie getroffen - dort
-- heisst die Aura schlicht "Satt", und genau so heisst auch der
-- Kampfrausch-Debuff. Ein Namensvergleich haette also entweder nichts oder
-- das Falsche gefunden; die Spell-IDs stehen in GC.Consumables.
local function ResolveConsumable(spellID)
    local consumable = GC.Consumables[tonumber(spellID) or 0]
    if not consumable then
        return nil, nil
    end
    return GC.ConsumableCategoryByKey[consumable.category], consumable
end

-- Beim WEITERESSEN meldet der Client die Sattgegessen-Aura alle zehn Sekunden
-- erneut (SPELL_AURA_REFRESH). Jede Meldung zaehlte als neue Mahlzeit: Ein
-- einziges Essen ueber dreissig Sekunden stand dreifach im Protokoll - am
-- Vergleichsabend vom 07.08.2026 elf gezaehlte Essen bei real vier
-- Mahlzeiten, die Eintraege exakt im Zehnsekundentakt. Innerhalb dieses
-- Fensters gilt dieselbe Aura desselben Teilnehmers deshalb als EINE
-- Mahlzeit. Sechzig Sekunden decken die laengste Essdauer ab; ein echtes
-- Nachessen Minuten spaeter zaehlt weiterhin.
local AURA_RECOUNT_WINDOW = 60

local function MarkAuraCounted(participant, spellID)
    local key = tonumber(spellID) or 0
    local now = GC.Util.Now()
    local counted = participant.auraCountedAt
    if not counted then
        counted = {}
        participant.auraCountedAt = counted
    end
    local last = tonumber(counted[key])
    if last and (now - last) < AURA_RECOUNT_WINDOW then
        return false
    end
    counted[key] = now
    return true
end

-- Der Merker des Eintritts-Scans: Was einmal gezaehlt wurde, liest der Scan
-- nie wieder als neuen Verbrauch. Er sitzt am Zauber, nicht am Teilnehmer -
-- die Begruendung steht bei ScanCarriedConsumables.
local function MarkScanned(participant, spellID)
    local key = tonumber(spellID)
    if not key then
        return false
    end
    local scanned = participant.scanned
    if not scanned then
        scanned = {}
        participant.scanned = scanned
    end
    if scanned[key] then
        return false
    end
    scanned[key] = true
    return true
end

local function RecordConsumable(participant, category, consumable, spellID, spellName)
    participant.consumables[category.key] = (participant.consumables[category.key] or 0) + 1

    -- Zusaetzlich zum Zaehler ein Protokoll: WAS wurde WANN eingeworfen.
    -- Bleibt rein lokal (wird nie gesendet) und zeigt sich beim Klick auf
    -- den Teilnehmer. Die Kappe schuetzt vor Trommel-Spam; Verworfenes wird
    -- gezaehlt statt verschwiegen.
    local log = participant.consumableLog
    if not log then
        log = {}
        participant.consumableLog = log
    end
    log[#log + 1] = {
        t = GC.Util.Now(),
        -- In der Clientsprache: Auf englischen Clients der belegte englische
        -- Name aus der Tabelle, sonst der deutsche; erst danach der rohe
        -- Zaubername aus dem Kampfprotokoll.
        n = (consumable and GC.ConsumableDisplayName(consumable))
            or (spellName and tostring(spellName))
            or ("Zauber " .. tostring(spellID or "?")),
        c = category.key,
    }
    if #log > CONSUMABLE_LOG_LIMIT then
        table.remove(log, 1)
        participant.consumableLogDropped = (participant.consumableLogDropped or 0) + 1
    end
end

local function CountConsumable(monitor, session, playerName, spellID, spellName, isAura)
    local category, consumable = ResolveConsumable(spellID)
    if not category then
        return
    end
    -- Die eine Bedingung, die Trommelinflation und Doppelzaehlung erledigt.
    if category.track == "AURA" then
        if not isAura then
            return
        end
    elseif isAura then
        return
    end
    local participant = monitor:FindParticipant(session, playerName)
    if not participant then
        return
    end
    -- Aura-Kategorien (Essen) zusaetzlich entprellen: Das Weiteressen
    -- refresht dieselbe Aura im Zehnsekundentakt, und jeder Refresh kam
    -- hier als eigenes Ereignis an.
    if category.track == "AURA" and not MarkAuraCounted(participant, spellID) then
        return
    end
    -- Was das Kampfprotokoll gezaehlt hat, darf der Eintritts-Scan nicht ein
    -- zweites Mal zaehlen: Der Buff steht danach noch stundenlang auf dem
    -- Charakter, und jeder Scan saehe ihn erneut.
    if category.scan then
        MarkScanned(participant, spellID)
    end
    RecordConsumable(participant, category, consumable, spellID, spellName)
end

-- Buffs eines Raidmitglieds ablesen. Der Client bietet dafuer je nach
-- Spielfassung eine andere Schnittstelle an; welche vorhanden ist, entscheidet
-- sich zur Laufzeit. Faellt beides aus, wird nichts abgelesen - das ergibt
-- unvollstaendige Zahlen, aber keine falschen.
local function ForEachBuff(unit, callback)
    if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
        for index = 1, 40 do
            local data = C_UnitAuras.GetBuffDataByIndex(unit, index)
            if not data then
                return true
            end
            callback(data.spellId, data.name)
        end
        return true
    end
    if UnitBuff then
        for index = 1, 40 do
            local name, _, _, _, _, _, _, _, _, spellID = UnitBuff(unit, index)
            if not name then
                return true
            end
            callback(spellID, name)
        end
        return true
    end
    return false
end

-- Fläschchen, Elixiere und Essen kommen vor dem Raid auf den Charakter - oft
-- lange vor dem ersten Pull und damit lange vor dem Sitzungsbeginn. Aus dem
-- Kampfprotokoll ist davon nichts zu holen; ein vollstaendig gebuffter Raid
-- stand deshalb mit lauter Nullen da (im Vergleichslog vom 02.08.2026: 23 von
-- 25 Teilnehmern ohne Fläschchen).
--
-- Abgelesen wird deshalb, was jemand schon traegt. Die Frage ist nur, WIE OFT.
--
-- Bis 0.9.115 galt: genau einmal je Teilnehmer (`auraScanDone`). Das hatte
-- zwei Seiten, und beide waren falsch:
--
--   * Wer beim ersten Sichtkontakt noch nicht gebufft war, wurde nie wieder
--     gelesen - ein Scan sieht nur EINEN Augenblick, und der lag oft vor dem
--     ersten Fläschchen.
--   * Und der Merker hielt nicht, was er versprach. Am Abend des 09.08.2026
--     bekamen beim Zonenwechsel von der Höhle des Schlangenschreins ins Auge
--     23 von 25 Teilnehmern binnen zweier Minuten je eine zusaetzliche
--     Mahlzeit gutgeschrieben - zu einem Zeitpunkt, an dem das Kampflog
--     dieser Minuten ueberhaupt kein Ereignis kennt. Gegessen hatte niemand;
--     der Scan lief erneut und zaehlte, was laengst gezaehlt war.
--
-- Der Merker sitzt jetzt am ZAUBER statt am Teilnehmer: Was einmal gezaehlt
-- wurde, zaehlt der Scan nie wieder - egal, wie oft er laeuft. Damit darf er
-- bei jedem Anwesenheitsabgleich laufen und schliesst die erste Luecke gleich
-- mit. Das Kampfprotokoll bleibt davon unberuehrt: Ein echter Zauber ist ein
-- echter Verbrauch und zaehlt immer, er traegt seine Kennung nur zusaetzlich
-- in den Merker ein.
function GC.RaidMonitor:ScanCarriedConsumables(unit, participant)
    if not participant or not unit then
        return
    end
    -- Erst ablesen, wenn der Spieler wirklich sichtbar ist: In einer anderen
    -- Zone liefert die Abfrage nichts, und ein leeres Ergebnis darf nicht als
    -- "hat nichts dabei" durchgehen.
    if UnitExists and not UnitExists(unit) then
        return
    end
    if UnitIsVisible and not UnitIsVisible(unit) then
        return
    end
    ForEachBuff(unit, function(spellID, spellName)
        local category, consumable = ResolveConsumable(spellID)
        if category and category.scan and MarkScanned(participant, spellID) then
            -- Aura-Kategorien (Essen) hier zusaetzlich entprellen. Sonst zaehlte
            -- ein SPELL_AURA_REFRESH derselben Sattgegessen-Aura, das kurz nach
            -- dem Eintritts-Scan eintrifft, dieselbe Mahlzeit ein zweites Mal:
            -- Der Scan trug sie nur in "scanned" ein, nicht in "auraCountedAt",
            -- an dem der Kampflog-Pfad die Entprellung festmacht.
            if category.track == "AURA" then
                MarkAuraCounted(participant, spellID)
            end
            RecordConsumable(participant, category, consumable, spellID, spellName)
        end
    end)
end

-- === Öle und Steine auf der eigenen Waffe ===================================
--
-- Waffenöle sind keine Aura, sondern eine temporaere Verzauberung AUF DER
-- WAFFE - der Aura-Scan oben sieht sie nie, und wer sein Öl vor dem
-- Sitzungsstart auftraegt (der Regelfall, es haelt eine Stunde), stand mit
-- null in der Spalte "Öle/Steine". Gelesen wird deshalb zusaetzlich die
-- eigene Waffe: GC.API.GetWeaponEnchantInfo sagt, OB eine temporaere Verzauberung
-- sitzt, der Waffentooltip sagt WELCHE. Gezaehlt wird nur ein Treffer der
-- Muster aus GC.WeaponOilPatterns - Windzorn, Flammenzunge und Gifte sind
-- ebenfalls temporaere Verzauberungen und keine Verbrauchsgegenstaende.
--
-- Nur die eigene Waffe: Fuer fremde Spieler gibt die API das nicht her. Wer
-- sein Öl waehrend der Sitzung neu auftraegt, wird weiterhin ueber das
-- Wirkereignis im Kampfprotokoll gezaehlt.

local weaponScanTooltip

-- Die Tooltipzeilen eines eigenen Ausruestungsplatzes. Als eigene Methode
-- herausgeloest, damit die Tests sie durch feste Zeilen ersetzen koennen -
-- einen echten Tooltip gibt es nur im Spielclient.
function GC.RaidMonitor:ReadWeaponEnchantLines(slot)
    local lines = {}
    if not CreateFrame or not UIParent then
        return lines
    end
    if not weaponScanTooltip then
        local ok, tooltip = pcall(CreateFrame, "GameTooltip",
            "GuildCopilotForeverWeaponScan", nil, "GameTooltipTemplate")
        if not ok or not tooltip then
            return lines
        end
        weaponScanTooltip = tooltip
    end
    local ok = pcall(function()
        weaponScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        weaponScanTooltip:ClearLines()
        weaponScanTooltip:SetInventoryItem("player", slot)
    end)
    if not ok then
        return lines
    end
    for index = 1, (tonumber(weaponScanTooltip:NumLines()) or 0) do
        local text = _G["GuildCopilotForeverWeaponScanTextLeft" .. index]
        local value = text and text.GetText and text:GetText()
        if type(value) == "string" and value ~= "" then
            lines[#lines + 1] = value
        end
    end
    return lines
end

-- Die erste Tooltipzeile, die nach einem bekannten Öl oder Stein aussieht.
-- Kein Treffer heisst kein Fund - lieber eine Null zu viel als ein
-- Windzorn-Totem als "Öl" verbucht.
function GC.RaidMonitor:FindWeaponOilName(lines)
    for _, line in ipairs(lines or {}) do
        for _, pattern in ipairs(GC.WeaponOilPatterns or {}) do
            if line:find(pattern, 1, true) then
                return line
            end
        end
    end
    return nil
end

function GC.RaidMonitor:ScanWeaponConsumables(participant)
    if not participant or participant.weaponScanDone then
        return
    end
    if not GC.API.Has("GetWeaponEnchantInfo") then
        return
    end
    local category = GC.ConsumableCategoryByKey.OIL
    if not category then
        return
    end
    participant.weaponScanDone = true
    local hasMainHand, _, _, hasOffHand = GC.API.GetWeaponEnchantInfo()
    local slots = {}
    if hasMainHand then
        slots[#slots + 1] = 16
    end
    if hasOffHand then
        slots[#slots + 1] = 17
    end
    for _, slot in ipairs(slots) do
        local name = self:FindWeaponOilName(self:ReadWeaponEnchantLines(slot))
        if name then
            RecordConsumable(participant, category, nil, nil, SanitizedText(name, 44))
        end
    end
end

-- Der Combat Log liefert im Raid tausende Schadensereignisse pro Kampf. Sie
-- werden mit einem einzigen Tabellenzugriff abgewiesen, bevor irgendetwas
-- anderes passiert.
local TRACKED_SUBEVENTS = {
    UNIT_DIED = true,
    SPELL_RESURRECT = true,
    SPELL_INTERRUPT = true,
    SPELL_DISPEL = true,
    SPELL_STOLEN = true,
    SPELL_CAST_SUCCESS = true,
    SPELL_AURA_APPLIED = true,
    SPELL_AURA_REFRESH = true,
}

function GC.RaidMonitor:HandleCombatLogEvent(subevent, sourceGUID, sourceName, destGUID, destName, spellID, spellName)
    local session = self.session
    if not session or not TRACKED_SUBEVENTS[subevent] then
        return
    end

    -- Wer im Abschnitt mitmischt, verraet, gegen wen gekaempft wird. Der Boss
    -- wirkt Zauber, lange bevor er stirbt - deshalb steht sein Name auch dann
    -- fest, wenn der Versuch im Wipe endet.
    if session.segment and not session.segment.bossName then
        self:NoteBossParticipant(session.segment, sourceGUID, sourceName)
        self:NoteBossParticipant(session.segment, destGUID, destName)
    end

    if subevent == "UNIT_DIED" then
        local participant = self:FindParticipant(session, destName)
        if participant then
            participant.deaths = participant.deaths + 1
            if session.segment then
                session.segment.playerDeaths = session.segment.playerDeaths + 1
            end
        elseif session.segment and tostring(destGUID or ""):find("Creature", 1, true) then
            local npcName = SanitizedText(destName, 36)
            session.segment.lastNPCDeath = npcName
            -- Ein Sieg ist der Tod des BOSSES. Vorher genuegte irgendein toter
            -- Gegner: Fehlte ENCOUNTER_END, machte der erste gestorbene Add
            -- aus einem abgebrochenen Versuch einen "Kill".
            if self:ResolveBoss(destName)
                or (session.segment.bossName and npcName == session.segment.bossName) then
                session.segment.bossDied = true
            end
        end
        return
    end

    if subevent == "SPELL_RESURRECT" then
        local participant = self:FindParticipant(session, sourceName)
        if participant then
            participant.resurrects = participant.resurrects + 1
        end
        return
    end

    if subevent == "SPELL_INTERRUPT" then
        local participant = self:FindParticipant(session, sourceName)
        if participant then
            participant.interrupts = participant.interrupts + 1
        end
        return
    end

    if subevent == "SPELL_DISPEL" or subevent == "SPELL_STOLEN" then
        local participant = self:FindParticipant(session, sourceName)
        if participant then
            participant.dispels = participant.dispels + 1
        end
        return
    end

    -- Tränke, Runen und Trommeln werden gewirkt, dauerhafte Buffs erscheinen
    -- als Aura auf dem Ziel.
    if subevent == "SPELL_CAST_SUCCESS" then
        CountConsumable(self, session, sourceName, spellID, spellName, false)
    elseif subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
        CountConsumable(self, session, destName, spellID, spellName, true)
    end
end

function GC.RaidMonitor:OnCombatLogEvent()
    if not self.session or not CombatLogGetCurrentEventInfo then
        return
    end
    -- Der Zaubername steht an dreizehnter Stelle. Er wurde bisher nicht
    -- ausgelesen, weshalb Essen nie erkannt werden konnte.
    local _, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellID, spellName =
        CombatLogGetCurrentEventInfo()
    self:HandleCombatLogEvent(subevent, sourceGUID, sourceName, destGUID, destName, spellID, spellName)
end

function GC.RaidMonitor:EncodeSummary(summary)
    local records = {
        table.concat({
            "S",
            summary.id or "",
            tostring(summary.startedAt or 0),
            tostring(summary.endedAt or 0),
            SanitizedText(summary.zone or "", 40),
            SanitizedText(summary.startedBy or "", 20),
            tostring(summary.pulls or 0),
            tostring(summary.kills or 0),
            tostring(summary.wipes or 0),
            -- Felder 10 und 11 haengen hinten an, damit eine aeltere Fassung
            -- die Zeile weiter lesen kann: Sie liest die vorderen neun und
            -- ignoriert den Rest. Umgekehrt liest diese Fassung eine alte
            -- Zeile ohne die beiden Felder als "Regelversion 1, Vollstaendig-
            -- keit unbekannt" - und verrechnet sie damit nie.
            tostring(summary.rulesVersion or GC.Constants.RAID_RULES_VERSION),
            summary.complete and "1" or "0",
        }, ","),
    }

    for _, participant in ipairs(summary.participants or {}) do
        local fields = {
            "P",
            SanitizedText(participant.name or "", 20),
            participant.classFile or "",
            tostring(participant.seconds or 0),
            tostring(participant.deaths or 0),
            tostring(participant.resurrects or 0),
            tostring(participant.interrupts or 0),
            tostring(participant.dispels or 0),
        }
        for _, category in ipairs(GC.ConsumableCategories) do
            fields[#fields + 1] = tostring((participant.consumables or {})[category.key] or 0)
        end
        records[#records + 1] = table.concat(fields, ",")
    end
    return table.concat(records, ";")
end

function GC.RaidMonitor:DecodeSummary(payload)
    local summary
    for record in tostring(payload or ""):gmatch("[^;]+") do
        local fields = {}
        for field in (record .. ","):gmatch("(.-),") do
            fields[#fields + 1] = field
        end

        if fields[1] == "S" then
            summary = {
                id = fields[2],
                startedAt = tonumber(fields[3]) or 0,
                endedAt = tonumber(fields[4]) or 0,
                zone = fields[5] or "",
                startedBy = fields[6] or "",
                pulls = tonumber(fields[7]) or 0,
                kills = tonumber(fields[8]) or 0,
                wipes = tonumber(fields[9]) or 0,
                participants = {},
                source = "SYNC",
                receivedAt = GC.Util.Now(),
                -- Fehlen die beiden hinteren Felder, kommt die Auswertung aus
                -- einer Fassung vor 0.9.89. Deren Zahlen bedeuten etwas
                -- anderes (Trommeln beim Beschenkten, Anwesenheit inklusive
                -- Offlinezeit) - sie gelten deshalb als Regelversion 1 und
                -- ausdruecklich NICHT als lueckenlos. Damit koennen sie einen
                -- eigenen Mitschnitt nie verfaelschen.
                rulesVersion = tonumber(fields[10]) or 1,
                complete = fields[11] == "1",
            }
        elseif fields[1] == "P" and summary then
            local participant = {
                name = fields[2] or "",
                classFile = fields[3] ~= "" and fields[3] or nil,
                seconds = tonumber(fields[4]) or 0,
                deaths = tonumber(fields[5]) or 0,
                resurrects = tonumber(fields[6]) or 0,
                interrupts = tonumber(fields[7]) or 0,
                dispels = tonumber(fields[8]) or 0,
                consumables = {},
            }
            for index, category in ipairs(GC.ConsumableCategories) do
                participant.consumables[category.key] = tonumber(fields[8 + index]) or 0
            end
            if participant.name ~= "" then
                summary.participants[#summary.participants + 1] = participant
            end
        end
    end

    if not summary or not summary.id or summary.id == "" then
        return nil
    end
    return summary
end

function GC.RaidMonitor:BuildSummaryMessages(summary, token)
    local payload = self:EncodeSummary(summary)
    local chunks = {}
    for offset = 1, #payload, MAX_PAYLOAD_BYTES do
        chunks[#chunks + 1] = payload:sub(offset, offset + MAX_PAYLOAD_BYTES - 1)
    end

    token = token or (tostring(GC.Util.Now()) .. tostring(math.random(100, 999)))
    local messages = {}
    for index, chunk in ipairs(chunks) do
        messages[index] = table.concat({
            "RD",
            tostring(GC.Constants.SCHEMA_VERSION),
            token,
            tostring(index),
            tostring(#chunks),
            chunk,
        }, "|")
    end
    return messages
end

-- Auswertungen nimmt jedes Gildenmitglied entgegen, nicht nur die freigegebenen
-- Ränge. Anders ginge das neue Modell nicht auf: Der Mitschnitt eines normalen
-- Raiders ist genau die Quelle, aus der eine fremde Lücke geschlossen wird -
-- er war da, er hat mitgeschrieben, sein Rang ändert daran nichts.
--
-- Was eintrifft, ist damit ausdrücklich FREMDE Zahlenlage und wird auch so
-- behandelt: Sie wird unter dem Namen des Absenders abgelegt, überschreibt
-- nie den eigenen Mitschnitt und fließt nur dann in eine Reparatur ein, wenn
-- sie dieselbe Zählregel-Version trägt und sich selbst als lückenlos meldet.
-- Auch dann entsteht daraus eine eigene, benannte Quelle, die sich ansehen und
-- löschen lässt.
function GC.RaidMonitor:ReceiveSummaryChunk(message, sender)

    local schemaText, token, indexText, totalText, chunk =
        message:match("^RD|([^|]+)|([^|]+)|([^|]+)|([^|]+)|(.*)$")
    local schemaVersion = tonumber(schemaText)
    local index = tonumber(indexText)
    local total = tonumber(totalText)
    if schemaVersion ~= GC.Constants.SCHEMA_VERSION
        or not index or not total or index < 1 or index > total or total > 40
        or #token > 40 or #chunk > MAX_PAYLOAD_BYTES then
        return false
    end

    local now = GC.Util.Now()
    local cutoff = now - INCOMING_TTL
    local incomingCount = 0
    for key, transfer in pairs(self.incoming) do
        if (tonumber(transfer.receivedAt) or 0) < cutoff then
            self.incoming[key] = nil
        else
            incomingCount = incomingCount + 1
        end
    end
    local incomingKey = GC.Util.NormalizeName(sender) .. "|" .. token
    local incoming = self.incoming[incomingKey]
    if incoming and incoming.total ~= total then
        self.incoming[incomingKey] = nil
        incomingCount = incomingCount - 1
        incoming = nil
    end
    if not incoming then
        -- Greift die Grenze, weicht die AELTESTE unfertige Uebertragung, nicht
        -- die neue - dieselbe Regel wie in Workshop und Ausruestungspruefung.
        -- Das neue Paket ist immer mehr wert als eines, das seit Minuten nicht
        -- weitergekommen ist; wiederholt wird hier naemlich nichts.
        while incomingCount >= MAX_INCOMING_TRANSFERS do
            local oldestKey, oldestAt
            for key, transfer in pairs(self.incoming) do
                local receivedAt = tonumber(transfer.receivedAt) or 0
                if not oldestAt or receivedAt < oldestAt then
                    oldestKey, oldestAt = key, receivedAt
                end
            end
            if not oldestKey then
                break
            end
            self.incoming[oldestKey] = nil
            incomingCount = incomingCount - 1
        end
        incoming = { total = total, chunks = {}, receivedAt = now }
        self.incoming[incomingKey] = incoming
    end
    incoming.chunks[index] = chunk

    local parts = {}
    for chunkIndex = 1, total do
        if incoming.chunks[chunkIndex] == nil then
            return false
        end
        parts[chunkIndex] = incoming.chunks[chunkIndex]
    end
    self.incoming[incomingKey] = nil

    local summary = self:DecodeSummary(table.concat(parts))
    if not summary then
        return false
    end
    -- Die Quelle nennt den Aufzeichner. Vorher trugen ALLE empfangenen
    -- Auswertungen schlicht "SYNC", und StoreSummary unterscheidet nach
    -- Kennung UND Quelle - zwei Gildenmitglieder, die denselben Abend
    -- mitgeschrieben hatten, ueberschrieben sich damit gegenseitig. Genau
    -- diese zweite Fassung wird jetzt aber gebraucht: Sie ist es, aus der ein
    -- lueckenhafter eigener Mitschnitt repariert wird.
    summary.source = "SYNC:" .. GC.Util.PlayerIdentityName(sender or "")
    summary.recordedBy = GC.Util.PlayerIdentityName(sender or "")
    local stored = self:StoreSummary(summary)

    -- Jede eintreffende Fassung kann das fehlende Stück eines eigenen
    -- lückenhaften Mitschnitts sein. Geprüft wird deshalb bei jedem Empfang
    -- und nicht nur nach einer ausdrücklichen Anfrage - eine Auswertung, die
    -- jemand Stunden später nachreicht, hilft genauso.
    if stored then
        self:TryRepair()
    end
    -- Antwortzähler für "Auswertung anfordern": auch eine Antwort, die
    -- nichts Neues bringt, ist eine sichtbare Antwort.
    local stats = self.requestStats
    if stats and (GC.Util.Now() - (stats.at or 0)) < 180 then
        stats.answers = stats.answers + 1
        if stored then
            stats.new = stats.new + 1
        end
        GC:FireCallback("RAID_SUMMARY_ANSWERS")
    end
    return stored
end

function GC.RaidMonitor:OnMessage(message, sender, distribution)
    local messageType = message:match("^(%u+)|")
    if messageType == "RD" then
        return self:ReceiveSummaryChunk(message, sender)
    end

    local fields = GC.Util.SplitFields(message)
    if tonumber(fields[2]) ~= GC.Constants.SCHEMA_VERSION then
        return false
    end

    -- Hier stand bis 0.9.88 eine Rangprüfung über ALLE Sitzungsnachrichten:
    -- „darf der Absender eine Sitzung steuern". Sie hat den gemeldeten Fehler
    -- verursacht. Geprüft wurde der Gildenrang des Absenders in der EIGENEN
    -- Sicht - er musste im eigenen Rosterabbild stehen und einen Rang aus
    -- memberCare.accessRanks halten. Diese Einstellung wird zwar gildenweit
    -- abgeglichen, aber wen sie noch nicht erreicht hat oder wessen Roster den
    -- Absender nicht kennt, der verwarf den Startruf UND jeden Herzschlag -
    -- dauerhaft und lautlos. Der Starter sah eine normal laufende Sitzung, der
    -- Empfänger erfuhr nie davon.
    --
    -- Eine Berechtigung gehört auf die Sendeseite. Getrennt wird jetzt danach,
    -- was eine Nachricht bewirkt:
    --   RS/RH  sind Mitteilungen. Sie ändern beim Empfänger nur das Etikett
    --          seines eigenen Mitschnitts - dafür braucht niemand einen Rang.
    --   RE     beendet die Sitzung auch bei allen anderen. Das ist ein Befehl
    --          und bleibt an den Rang gebunden.
    --   RQ     fordert Auswertungen an. Offen für alle: Genau darauf beruht
    --          die Reparatur eines lückenhaften eigenen Mitschnitts.
    if fields[1] == "RS" then
        -- Alle Addon-Nutzer im Raid zeichnen dieselbe Sitzung mit, damit die
        -- Auswertung nicht an einem einzelnen Client hängt. Läuft hier schon
        -- eine andere, entscheidet die Regel oben, welche gilt - der Banner
        -- steckt in AdoptForeignSession.
        if distribution == "WHISPER" then
            return false
        end
        local adopted = self:AdoptForeignSession(
            fields[3], sender, tonumber(fields[4]), fields[5], sender)
        -- Nur der Ruf zur EIGENEN Sitzung zählt als „es redet schon jemand".
        -- Vorher stempelte jede fremde Meldung den eigenen Herzschlag und
        -- brachte die unterlegene Sitzung zusätzlich zum Schweigen.
        if adopted then
            self:NoteHeartbeat()
        end
        return true
    elseif fields[1] == "RH" then
        -- Der Herzschlag einer laufenden Sitzung. Für alle, die den Startruf
        -- verpasst haben, ist er zugleich der Startruf: Nachzügler und
        -- Wiedereinsteiger schreiben ab hier denselben Abend mit.
        if distribution == "WHISPER" then
            return false
        end
        local sessionID = fields[3]
        if type(sessionID) ~= "string" or sessionID == "" then
            return false
        end
        if not self.session then
            -- Ueber AdoptForeignSession statt direkt ueber StartSession: Nur
            -- dort wird vermerkt, dass der Abend schon lief, bevor dieser
            -- Client mitgeschrieben hat. Ohne diesen Vermerk gilt ein
            -- Nachzuegler faelschlich als lueckenloser Mitschnitt - und wuerde
            -- damit sogar zum Reparieren fremder Luecken herangezogen.
            self:AdoptForeignSession(sessionID, fields[6] ~= "" and fields[6] or sender,
                tonumber(fields[4]), fields[5], sender)
            self:NoteHeartbeat()
            return true
        end
        if self.session.id == sessionID then
            self:NoteHeartbeat()
            return true
        end
        -- Eine fremde Sitzung verdrängt die eigene nur, wenn sie nach derselben
        -- Regel gewinnt und die eigene noch frisch ist. Der Herzschlag heilt
        -- damit auch eine Spaltung, die dem Startruf entgangen ist - etwa weil
        -- jemand beim Drücken gerade im Ladebildschirm war.
        if self:AdoptForeignSession(sessionID, fields[6] ~= "" and fields[6] or sender,
            tonumber(fields[4]), fields[5], sender) then
            self:NoteHeartbeat()
            return true
        end
        return false
    elseif fields[1] == "RE" then
        -- Beenden wirkt auf alle und bleibt deshalb ein Recht der freigegebenen
        -- Ränge. Ausgewertet wird trotzdem der EIGENE Mitschnitt: Das Ende
        -- schließt den Abend, es übernimmt keine fremden Zahlen.
        if not self:CanControlSession(sender) then
            return false
        end
        local session = self.session
        if session and session.id == fields[3] then
            local summary = self:FinishSession(tonumber(fields[4]))
            return summary ~= nil
        end
        return false
    elseif fields[1] == "RQ" then
        -- Feld 3 ist optional: Steht dort eine Sitzungskennung, will der
        -- Anfragende genau diesen Abend reparieren und bekommt auch nur den.
        return self:AnswerSummaryRequest(sender, fields[3] ~= "" and fields[3] or nil)
    end
    return false
end

-- Offiziere außerhalb des Raids fragen die Auswertung gezielt an; geantwortet
-- wird per Flüsterkanal, damit nichts über den offenen Gildenkanal geht.
function GC.RaidMonitor:RequestSummaries()
    -- Ohne Rangsperre: Genau hierauf beruht die Reparatur eines lückenhaften
    -- eigenen Mitschnitts, und eine Lücke fragt nicht nach dem Rang. Angefragt
    -- werden Auswertungen des eigenen Raids, geantwortet wird geflüstert und
    -- gedrosselt - hier ist nichts zu schützen, was nicht ohnehin jedem im
    -- Addon offensteht.
    if not GC.Sync:Send("RQ|" .. tostring(GC.Constants.SCHEMA_VERSION), "GUILD") then
        return false, "Die Anfrage konnte nicht gesendet werden."
    end
    -- Ab jetzt zählen eintreffende Antworten mit, damit der Knopf sichtbar
    -- etwas tut - vorher kam entweder still etwas an oder still nichts.
    self.requestStats = { at = GC.Util.Now(), answers = 0, new = 0 }
    GC:FireCallback("RAID_SUMMARY_ANSWERS")
    return true, "Auswertung angefragt. Berechtigte Mitglieder antworten gleich."
end

function GC.RaidMonitor:AnswerSummaryRequest(requester, sessionID)
    -- Beantwortet wird mit bis zu fünf Abenden, Bossabende zuerst - nur die
    -- allerneueste Zusammenfassung zu schicken war sinnlos: Die hatte der
    -- Anfragende fast immer selbst, die Speicherung lehnte ab, und der Knopf
    -- wirkte völlig wirkungslos.
    --
    -- Nennt die Anfrage dagegen einen bestimmten Abend, geht auch nur der
    -- raus. Das ist der Fall der Reparatur, und dort ist alles andere
    -- unnötiger Funkverkehr.
    --
    -- Davor steht die Wahl: Bis 0.9.96 antwortete JEDER, der die Anfrage
    -- hoerte, jetzt nur eine Handvoll Gewaehlter. Gerechnet wird das
    -- lokal ueber (Anfragender, Kandidat), ohne eine einzige Zusatznachricht,
    -- und in kleinen Gilden - weniger bekannte Kandidaten als Plaetze - bleibt
    -- es beim bisherigen Verhalten, dass jeder antwortet. Die Begruendung der
    -- beiden Platzzahlen steht oben bei den Konstanten.
    --
    -- Das zweite Verfahren (NotePeerAnswer/PeerAnsweredSince) hilft hier
    -- nicht: Geantwortet wird geflüstert, und eine Flüsterantwort sieht kein
    -- anderer Client - er koennte also gar nicht verstummen.
    -- ERST der Bestand, DANN die Wahl. Die Reihenfolge ist der ganze Punkt.
    --
    -- Andersherum war es nachweislich kaputt: Die wenigen Plaetze wurden aus
    -- ALLEN Online-Addon-Nutzern gezogen, nicht aus denen, die den gefragten
    -- Abend ueberhaupt gespeichert haben. Ein Gewaehlter ohne Auswertung
    -- verbrauchte seinen Platz und schwieg, die Nichtgewaehlten schwiegen
    -- ohnehin - und weil die Streuzahl rein rechnerisch ist, waren es bei
    -- jedem Knopfdruck DIESELBEN Gewaehlten. Gemessen an 250 Online, von denen
    -- 16 % einen Abend gespeichert hatten: 70 % der Anfragen bekamen nie eine
    -- Antwort, und zwar dauerhaft dieselben Anfragenden. Der Knopf
    -- "Auswertung anfordern" fiel damit fuer die Betroffenen still aus.
    local candidates = {}
    for _, summary in ipairs(self:GetSummaries()) do
        if sessionID == nil or tostring(summary.id or "") == tostring(sessionID) then
            candidates[#candidates + 1] = summary
        end
    end
    if #candidates == 0 then
        return false
    end
    table.sort(candidates, function(left, right)
        local leftBoss = (tonumber(left.pulls) or 0) > 0 and 1 or 0
        local rightBoss = (tonumber(right.pulls) or 0) > 0 and 1 or 0
        if leftBoss ~= rightBoss then
            return leftBoss > rightBoss
        end
        return (left.endedAt or 0) > (right.endedAt or 0)
    end)

    local slots = sessionID and REPAIR_RESPONDER_SLOTS or SUMMARY_RESPONDER_SLOTS
    if not GC.Sync:IsElectedResponder(requester, slots) then
        return false
    end
    -- Gedrosselt wird je Anfragendem, nicht global.
    --
    -- Vorher stand hier ein einziger Zeitstempel für alle. Fliegen nach einem
    -- Serverruckler drei Leute gleichzeitig raus, stellt jeder von ihnen seine
    -- Reparaturanfrage - und nur der erste bekam eine Antwort, die beiden
    -- anderen liefen 30 Sekunden lang ins Leere. Ausgerechnet der Fall, für
    -- den die Reparatur gebaut ist, war damit der, in dem sie ausfiel.
    local now = GC.Util.Now()
    local requesterKey = GC.Util.PlayerKey(requester or "")
    self.lastAnswerAt = type(self.lastAnswerAt) == "table" and self.lastAnswerAt or {}
    for key, at in pairs(self.lastAnswerAt) do
        if (now - (tonumber(at) or 0)) > (MIN_ANSWER_INTERVAL * 10) then
            self.lastAnswerAt[key] = nil
        end
    end
    if (now - (tonumber(self.lastAnswerAt[requesterKey]) or 0)) < MIN_ANSWER_INTERVAL then
        return false
    end
    self.lastAnswerAt[requesterKey] = now

    -- Eine gezielte Anfrage hat ohnehin nur einen Abend gefunden. Die nackte
    -- wird gekappt, weil bei ihr die Platzzahl hoch ist - siehe
    -- MAX_BARE_ANSWER_SUMMARIES.
    local limit = sessionID and #candidates or MAX_BARE_ANSWER_SUMMARIES
    local canStagger = C_Timer and type(C_Timer.After) == "function"
    for index = 1, math.min(limit, #candidates) do
        local summary = candidates[index]
        if canStagger then
            -- Gestaffelt, damit sich die Antworten mehrerer Mitglieder nicht
            -- gegenseitig in den Kanal drängen.
            C_Timer.After(index + math.random() * 4, function()
                GC.Sync:DistributeSummary(summary, "WHISPER", requester)
            end)
        else
            -- Ohne C_Timer (aeltere Clients, Testumgebung) ungestaffelt, aber
            -- ueberhaupt: eine Antwort ohne Timer ist besser als keine.
            GC.Sync:DistributeSummary(summary, "WHISPER", requester)
        end
    end
    return true
end

-- Beim Betreten einer Raidinstanz fragt das Addon, ob eine Sitzung starten
-- soll - aber nur bei denen, die das auch duerfen (CanControlSession), nur
-- im Schlachtzug, nur ohne laufende Sitzung und nur einmal je Besuch.
function GC.RaidMonitor:OnZoneEntered()
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return
    end
    -- Kurz warten: Direkt nach dem Ladebildschirm sind Instanz- und
    -- Gruppendaten noch nicht verlaesslich.
    C_Timer.After(3, function()
        local monitor = GC.RaidMonitor
        local instanceType
        if IsInInstance then
            local _, kind = IsInInstance()
            instanceType = kind
        end
        if instanceType ~= "raid" then
            -- Draussen: Der naechste Instanzbesuch darf wieder fragen.
            monitor.sessionPromptShown = nil
            return
        end
        if monitor.session or monitor.sessionPromptShown then
            return
        end
        if not monitor:IsInRaidGroup() or not monitor:CanControlSession() then
            return
        end
        monitor.sessionPromptShown = true
        GC:FireCallback("RAID_SESSION_PROMPT",
            (GetRealZoneText and GetRealZoneText()) or "")
    end)
end

-- Der Rahmen steht oben bei den Herzschlag-Konstanten; er ist nur sichtbar,
-- solange eine Sitzung laeuft.
heartbeatFrame:SetScript("OnUpdate", function(_, elapsed)
    heartbeatElapsed = heartbeatElapsed + elapsed
    if heartbeatElapsed < SESSION_HEARTBEAT_CHECK then
        return
    end
    heartbeatElapsed = 0
    GC.RaidMonitor:PumpHeartbeat()
end)

raidEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
-- Der letzte Moment, in dem der Mitschnitt noch geradegezogen werden kann:
-- Danach schreibt WoW die SavedVariables, und was dort steht, ist der Stand,
-- mit dem die Sitzung nach dem Wiedereinloggen weiterläuft.
raidEvents:RegisterEvent("PLAYER_LOGOUT")

-- Der Rahmen und die dauerhaften Ereignisse stehen oben in der Datei, damit
-- StartSession und FinishSession das Combat-Log-Abo umschalten koennen.
raidEvents:SetScript("OnEvent", function(_, event, ...)
    if not GC.Client.combatAnalysis then return end
    if event == "PLAYER_ENTERING_WORLD" then
        GC.RaidMonitor:OnZoneEntered()
        return
    elseif event == "PLAYER_LOGOUT" then
        GC.RaidMonitor:SaveSessionForResume()
        return
    end
    if not GC.RaidMonitor.session then
        return
    end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        GC.RaidMonitor:OnCombatLogEvent()
    elseif event == "GROUP_ROSTER_UPDATE" then
        GC.RaidMonitor:ScheduleSyncParticipants()
    elseif event == "PLAYER_REGEN_DISABLED" then
        GC.RaidMonitor:BeginSegment(GC.Util.Now())
    elseif event == "PLAYER_REGEN_ENABLED" then
        GC.RaidMonitor:CloseSegment(GC.Util.Now())
    elseif event == "ENCOUNTER_START" then
        GC.RaidMonitor:OnEncounterStart(...)
    elseif event == "ENCOUNTER_END" then
        GC.RaidMonitor:OnEncounterEnd(...)
    end
end)

-- Nach dem Login steht die Sitzung wieder da, wo sie beim Ausloggen aufgehört
-- hat. Kurz gewartet wird trotzdem: Gruppen- und Zonendaten sind direkt nach
-- dem Ladebildschirm noch nicht verlässlich, und ohne Gruppe fände der
-- Herzschlag ohnehin keinen Kanal.
GC:RegisterCallback("PLAYER_LOGIN", GC.RaidMonitor, function(self)
    local function Resume()
        local session, closed = self:ResumeSession()
        if session then
            GC:Print("Die unterbrochene Raidsitzung läuft weiter ("
                .. #session.participantOrder .. " Teilnehmer).")
        elseif closed then
            GC:Print("Eine liegengebliebene Raidsitzung wurde ausgewertet und abgelegt.")
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(5, Resume)
    else
        Resume()
    end
end)
