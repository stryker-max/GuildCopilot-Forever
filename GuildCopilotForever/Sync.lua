local _, GC = ...

GC.Sync = {
    registered = false,
    sendPending = false,
    guildProfileSendPending = false,
    guildProfileForceSend = false,
    guildProfileIncoming = {},
    bulkQueue = {},
    bulkAllowance = 4000,
    reliableQueue = {},
    lastAnnounceAt = 0,
    -- Wie viele Pakete gerade unterwegs sind. Der Zaehler ist die einzige
    -- Quelle fuer den Fortschrittsbalken und deckt beide Sendewege ab: die
    -- eigene Warteschlange und ChatThrottleLib.
    bulkOutstanding = 0,
    -- Uebertragungen, die nicht ueber SendBulk laufen, sondern selbst
    -- getaktet senden (Gildenprofil, Raidauswertung).
    serialPending = 0,
}

-- Der Handshake läuft bewusst ohne Dauerbroadcast: gesendet wird nur beim
-- Login, beim Betreten einer Gruppe und als Antwort auf eine Anfrage. Beide
-- Mindestabstände verhindern, dass mehrere gleichzeitige Logins den
-- Addon-Kanal fluten.
local MIN_ANNOUNCE_INTERVAL = 60
local MIN_REPLY_INTERVAL = 15
local MIN_PROFILE_REPLY_INTERVAL = 30
local MIN_MANUAL_SYNC_INTERVAL = 15
local INCOMING_TTL = 5 * 60
-- Wie weit ein fremder Zeitstempel hoechstens in der Zukunft liegen darf, bevor
-- er als falsch gestellte Uhr gilt. Ein Tag ist grosszuegig genug fuer
-- Realm-Wechsel und Sommerzeit und eng genug, um eine um Jahre verstellte Uhr
-- nicht zur ewigen Autoritaet ueber das Gildenprofil zu machen.
local MAX_CLOCK_SKEW = 24 * 60 * 60
-- ChatThrottleLib nutzt dieselben konservativen Grenzwerte. Ist die Bibliothek
-- bereits durch ein anderes Addon geladen, reihen wir uns dort ein. Andernfalls
-- stellt diese kleine lokale Warteschlange denselben Schutz bereit: bis zu 4 KB
-- Burst und danach 800 Bytes pro Sekunde. Alle Pakete werden sofort eingereiht;
-- es gibt keine feste Pause pro Rezept.
local BULK_BYTES_PER_SECOND = 800
local BULK_BURST_BYTES = 4000
local BULK_MESSAGE_OVERHEAD = 40
local BULK_MAX_RETRIES = 8
-- Lehnt der Client eine Nachricht ab (eingebautes Addon-Ratenlimit), braucht der
-- Kanal echte Zeit zum Erholen. Die Wiederholungen bekommen deshalb einen
-- wachsenden zeitlichen Abstand, statt im selben Frame zu verbrennen.
local BULK_RETRY_BACKOFF = 0.75
local BULK_MAX_RETRY_DELAY = 4

-- Liegt eine benutzbare ChatThrottleLib vor? Die Frage stellt sich nur noch
-- vor der Uebergabe. Als Grund, ein bereits uebergebenes Paket aufzugeben,
-- taugt sie ausdruecklich NICHT: Die Bibliothek haelt ihre eigene Referenz
-- und einen laufenden Frame, das Paket geht also weiter raus, auch wenn die
-- globale Variable verschwindet.
local function throttleAvailable()
    local throttle = _G and _G.ChatThrottleLib
    return throttle ~= nil and type(throttle.SendAddonMessage) == "function"
end

-- Der Rahmen, dessen OnUpdate die Bulk-Warteschlange antreibt. Er steht hier
-- oben, damit SendBulk und PumpBulk ihn zeigen und verstecken koennen: Ein
-- verstecktes Frame bekommt kein OnUpdate, eine leere Warteschlange kostet
-- damit keinen einzigen Handleraufruf pro Frame. Verdrahtet wird das Skript
-- unten bei den uebrigen Ereignisrahmen.
local bulkFrame = CreateFrame("Frame")

-- Werkstattkataloge und Gildenbankbestaende sind die einzigen wirklich grossen
-- Uebertragungen im Addon. Im Kampf haben sie nichts verloren: Dort zaehlt
-- jede Millisekunde, und niemand sieht in dem Moment in die Werkstatt.
-- Die Warteschlange bleibt dabei stehen, es geht nichts verloren - sie laeuft
-- weiter, sobald der Kampf vorbei ist.
--
-- Handshakes, Profile und Raidauswertungen laufen bewusst nicht hierueber:
-- Sie sind wenige Bytes und teils zeitkritisch.
--
-- Diese Pruefung steht hier oben, weil SendBulk sie braucht. Stand sie weiter
-- unten, war der Name in SendBulk zur Uebersetzungszeit noch kein lokaler -
-- der Aufruf waere als globaler Zugriff auf ein nicht vorhandenes InCombat
-- gelandet und haette immer nil ergeben.
local function InCombat()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return true
    end
    return type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player") == true
end

local RELIABLE_WINDOW = 4
local RELIABLE_RETRY_DELAY = 1.5
-- Der Whisper-Transfer teilt sich das Kanalbudget mit ChatThrottleLib und dem
-- Verkehr anderer Addons. Ein einzelnes Paket darf deshalb mehrfach und mit
-- wachsendem Abstand erneut anlaufen, bevor es als verloren gilt; sonst meldet
-- ein kurzzeitig ueberlasteter Kanal faelschlich einen Fehlschlag.
local RELIABLE_MAX_ATTEMPTS = 8
local RELIABLE_MAX_RETRY_DELAY = 6

-- === Fortschritt des Gildenabgleichs =======================================
--
-- Der Balken unten in der Werkstatt beantwortet zwei Fragen: Ist gerade noch
-- etwas unterwegs, und ist der Stand vollstaendig? Beides wird nicht geschaetzt,
-- sondern gezaehlt - ausgehende Pakete ueber bulkOutstanding und serialPending,
-- eingehende ueber die noch fehlenden Teile aller laufenden Uebertragungen, und
-- fehlende Daten ueber die Berufe, die ein fremdes Manifest gemeldet hat und die
-- hier noch nicht angekommen sind.
--
-- Ein Zyklus beginnt, sobald das Erste unterwegs ist, und endet, wenn nichts
-- mehr aussteht. Die Hoechstzahl des Zyklus ist der Nenner des Balkens; sie
-- waechst mit, wenn waehrenddessen Neues dazukommt, faellt aber nie zurueck.
local PROGRESS_TICK = 0.5
-- Eine eingehende Uebertragung, zu der so lange kein Teil mehr kam, gilt als
-- verloren statt als "laeuft noch". Sonst behauptet der Balken minutenlang
-- Betrieb, obwohl der Absender laengst offline ist.
local PROGRESS_INCOMING_STALE = 30
-- Und ab wann sie gar nicht mehr vorkommt. Dieselbe Frist, die jedes Modul fuer
-- seine eigenen Tabellen benutzt.
local PROGRESS_INCOMING_DROP = 5 * 60
-- Kommt der SENDEZAEHLER so lange nicht voran, ist ein Rueckruf ausgeblieben.
-- Nur er wird zurueckgesetzt: Empfang und bekannte Luecken haben eigene
-- Verfallszeiten und heilen von selbst. Wer hier alles auf null setzt, erfindet
-- Verluste, die zwei Sekunden spaeter wieder als offen dastehen - und der
-- Zyklus faengt im Zweiminutentakt von vorn an.
local PROGRESS_STALL_SECONDS = 120
local progressFrame = CreateFrame("Frame")
progressFrame:Hide()
local progressElapsed = 0

local function PruneIncoming(transfers)
    local cutoff = GC.Util.Now() - INCOMING_TTL
    for key, transfer in pairs(transfers) do
        if (tonumber(transfer.receivedAt) or 0) < cutoff then
            transfers[key] = nil
        end
    end
end

-- === Wer antwortet auf eine gildenweite Anfrage? ===========================
--
-- Das war der schwerste Konstruktionsfehler des Addons, und er war keiner der
-- Logik, sondern der Menge: Auf jede Anfrage im Gildenkanal antwortete JEDER
-- Client einzeln. Bei fuenfzehn Leuten faellt das nicht auf, bei 250 ist es
-- das Ende des Kanals. Gemessen an einer Gilde mit 500 Mitgliedern, 250 davon
-- online, loeste ein einziger Login aus:
--
--   GQ  Gildenprofil       22 Pakete je Antwortendem  ->  5.500 gildenweit
--   RQ  Auswertung         40 Pakete je Antwortendem  -> 10.000 gildenweit
--   O|Q Auftragsabgleich    3 Pakete je Auftrag       ->    750 je Auftrag
--
-- Blizzards Addon-Kanal stellt groessenordnungsmaessig zehn Pakete je Sekunde
-- und Absender zu und verwirft den Rest lautlos. Es kam also nicht mehr an,
-- was gesendet wurde - und der Fortschrittsbalken meldete zu Recht dauerhaft
-- "unvollstaendig".
--
-- Zwei Verfahren loesen das, und beide stehen im Addon schon an je einer
-- Stelle. Sie werden hier zusammengefasst, damit jeder Anfragetyp sie nutzt.
--
--   1. WAHL (IsElectedResponder). Nur eine Handvoll Clients antwortet
--      ueberhaupt. Wer dazugehoert, rechnet jeder fuer sich aus - ohne eine
--      einzige Zusatznachricht und ohne Absprache. Grundlage ist eine
--      Streuzahl aus Anfragendem und Kandidat: Sie ist auf jedem Client
--      dieselbe, verteilt die Last aber bei jedem Anfragenden neu, sodass
--      nicht immer dieselben drei die Arbeit tragen.
--
--   2. STILLE (NotePeerAnswer/PeerAnsweredSince). Wer die Antwort eines
--      anderen SIEHT, schweigt. Das greift nur bei Antworten ueber den
--      Gildenkanal - eine Fluesterantwort sieht niemand sonst. Genau dieses
--      Verfahren nutzten Workshop:KR und Inventory:BR schon; es wird jetzt
--      allgemein verfuegbar.
--
-- Beides zusammen: gewaehlt wird, wer ueberhaupt antworten darf, und wer
-- waehrend seiner Streuzeit einen anderen hoert, laesst es trotzdem bleiben.
--
-- === WANN BEIDES ERLAUBT IST - bitte vor dem naechsten Aufruf lesen ========
--
-- Beide Verfahren ersetzen viele gleiche Antworten durch wenige. Sie sind
-- deshalb an EINE Voraussetzung gebunden:
--
--   Die Antwort muss bei jedem Antwortenden DIESELBE sein.
--
-- Das gilt fuer geteilte Gildendaten - Gildenprofil, Gildenbank, Auftraege:
-- Dort haelt jeder Client eine Kopie desselben Standes, und drei Kopien davon
-- sind so gut wie zweihundertfuenfzig.
--
-- Es gilt NICHT, wo jeder Client etwas EIGENES beitraegt. Beim ersten Anlauf
-- stand die Wahl auch vor der Werkstatt-Anfrage - und dort antwortet jeder
-- mit den Berufen seines eigenen Accounts. Von zweihundertfuenfzig Antworten
-- blieben drei uebrig, und der Fragende erfuhr die Berufe von drei Spielern
-- statt von der ganzen Gilde. Dasselbe gilt fuer die Stille: Ein fremdes
-- Manifest belegt nicht, dass die eigenen Berufe schon jemand gemeldet hat.
--
-- Wo jeder etwas Eigenes hat, hilft nur STREUUNG IN DER ZEIT: Alle antworten,
-- aber verteilt ueber ein Fenster, das gross genug ist, dass der Kanal
-- mitkommt.
--
-- Und wo die Antwort davon abhaengt, ob dieser Client die Daten ueberhaupt
-- hat (Raidauswertungen), gehoert diese Pruefung VOR die Wahl - sonst
-- verbraucht ein Client ohne Daten einen der wenigen Plaetze und schweigt.

-- Wie viele Clients eine gildenweite Anfrage beantworten. Drei statt einem,
-- damit ein Ausfall (Ladebildschirm, Verbindungsabbruch, alter Client) die
-- Antwort nicht ganz ausfallen laesst; die Empfaengerseite verwirft Doppeltes
-- ohnehin ueber Zeitstempel und Fingerabdruck.
local RESPONDER_SLOTS = 3

-- Bewusst dieselbe Streufunktion wie die Werkstatt-Fingerabdruecke (djb2):
-- klein, ohne Bibliothek und auf jedem Client bitgleich. Alle Zwischenwerte
-- bleiben unter 2^36 und damit im Bereich, in dem eine Fliesskommazahl exakt
-- rechnet - sonst waere das Ergebnis zwar immer noch auf jedem Client
-- dasselbe, aber die unteren Stellen waeren Zufall statt Streuung.
local function Djb2(text)
    local hash = 5381
    for index = 1, #text do
        hash = ((hash * 33) + text:byte(index)) % 2147483647
    end
    return hash
end

-- Die Streuzahl eines Kandidaten fuer eine bestimmte Anfrage.
--
-- ZWEI Runden, und das ist nicht Zierde. Mit einer Runde ueber
-- "anfragender|kandidat" blieb die Wahl zwar bei drei Antwortenden, traf aber
-- fast immer dieselben: Bei 200 verschiedenen Anfragenden kamen ueber alle
-- Anfragen nur neun verschiedene Clients zum Zug, einer davon 82 mal.
--
-- Der Grund steckt in djb2 selbst. Die Kette h = h*33 + byte ergibt fuer eine
-- Verkettung h(A..B) = h(A) * 33^laenge(B) + f(B). Weil alle Kandidatennamen
-- aehnlich lang sind, ist 33^laenge(B) praktisch konstant - der Anfragende
-- verschiebt damit ALLE Streuzahlen um denselben Faktor und aendert die
-- REIHENFOLGE nicht. Genau die Reihenfolge ist aber das Einzige, worauf es
-- ankommt.
--
-- Die zweite Runde streut das Ergebnis der ersten erneut, zusammen mit dem
-- Anfragenden. Damit haengt die Reihenfolge tatsaechlich an beidem, und die
-- Antwortlast wandert durch die Gilde, statt an drei Leuten haengenzubleiben.
local function ResponderScore(requesterKey, candidateKey)
    return Djb2(tostring(Djb2(candidateKey .. "|" .. requesterKey)) .. "|" .. requesterKey)
end

-- Wie lange die Kandidatenliste gilt. Sie aendert sich nur, wenn jemand ein-
-- oder ausloggt; innerhalb weniger Sekunden ist sie dieselbe. Ohne diesen
-- Merker kostete jede Wahl bei 250 Kandidaten 0,86 ms, und gewaehlt wird bei
-- jeder eingehenden Anfrage - zur Anmeldezeit also hunderte Male.
local RESPONDER_CACHE_SECONDS = 3

-- Alle Charaktere, die als Antwortende in Frage kommen: bekannte Addon-Nutzer,
-- die laut Roster in der Gilde und online sind. Doppelt abgelegte Eintraege
-- (Voll- und Kurzname zeigen auf dieselbe Tabelle) zaehlen einmal.
function GC.Sync:CollectResponderKeys()
    local ownKey = GC.Util.PlayerKey(GC:GetPlayerFullName())
    local now = GC.Util.Now()
    local cached = self.responderCache
    if cached and cached.ownKey == ownKey
        and (now - cached.at) < RESPONDER_CACHE_SECONDS then
        return cached.keys, ownKey
    end

    local keys = { [ownKey] = true }
    local rosterReady = #GC.Roster.members > 0
    if rosterReady then
        local seen = {}
        for _, entry in pairs(GC.DB:GetGuild().addonUsers or {}) do
            if type(entry) == "table" and not seen[entry] then
                seen[entry] = true
                local member = GC.Roster:GetMember(entry.name)
                if member and member.online then
                    local key = GC.Util.PlayerKey(entry.name)
                    if key ~= "" then
                        keys[key] = true
                    end
                end
            end
        end
    end

    -- Ein leeres Roster wird ausdruecklich NICHT gemerkt: Direkt nach dem
    -- Login ist es regelmaessig noch leer, und drei Sekunden spaeter steht die
    -- ganze Gilde darin. Ein gemerktes "ich bin allein" waere genau in dem
    -- Zeitraum falsch, in dem die meisten Anfragen eintreffen.
    if rosterReady then
        self.responderCache = { keys = keys, ownKey = ownKey, at = now }
    else
        self.responderCache = nil
    end
    return keys, ownKey
end

-- Gehoert dieser Client zu den ausgewaehlten Antwortenden fuer diese Anfrage?
--
-- Gerechnet wird ohne Nachricht: Jeder Kandidat bekommt eine Streuzahl aus
-- Anfragendem und eigenem Namen, und wer unter den <slots> kleinsten liegt,
-- antwortet. Kennt dieser Client weniger Kandidaten als Plaetze da sind -
-- kleine Gilde, frischer Login, leeres Roster -, antwortet er immer: Lieber
-- eine Antwort zu viel als eine Anfrage, die ins Leere laeuft.
function GC.Sync:IsElectedResponder(requester, slots)
    slots = math.max(1, tonumber(slots) or RESPONDER_SLOTS)
    local requesterKey = GC.Util.PlayerKey(requester)
    local candidates, ownKey = self:CollectResponderKeys()

    local ownScore = ResponderScore(requesterKey, ownKey)
    local better = 0
    for key in pairs(candidates) do
        -- Der Anfragende zaehlt nicht mit. Er steht in der Kandidatenliste,
        -- weil sie schlicht alle bekannten Online-Nutzer sammelt - beantworten
        -- wird er seine eigene Anfrage aber nie. Gewann er einen der wenigen
        -- Plaetze, blieb dieser leer: In einer kleinen Gilde fiel damit
        -- regelmaessig ein Drittel der ohnehin knappen Antworten aus.
        if key ~= ownKey and key ~= requesterKey then
            local score = ResponderScore(requesterKey, key)
            -- Gleichstand entscheidet der Name, damit die Reihenfolge auf
            -- jedem Client dieselbe ist.
            if score < ownScore or (score == ownScore and key < ownKey) then
                better = better + 1
                if better >= slots then
                    return false
                end
            end
        end
    end
    return true
end

-- Ein anderer hat auf eine Anfrage dieser Art geantwortet. Der Vermerk gilt
-- je Art, nicht je Anfragendem: Eine Gildenprofil-Antwort erreicht alle und
-- macht damit jede weitere ueberfluessig, ganz gleich wer gefragt hatte.
function GC.Sync:NotePeerAnswer(kind)
    self.peerAnswers = self.peerAnswers or {}
    self.peerAnswers[kind] = GC.Util.Now()
end

function GC.Sync:PeerAnsweredSince(kind, since)
    local at = self.peerAnswers and self.peerAnswers[kind]
    return at ~= nil and at >= (tonumber(since) or 0)
end

local function BoolField(value)
    return value and "1" or "0"
end

local function SortedEnabledRanks(values)
    local ranks = {}
    for rankIndex, enabled in pairs(values or {}) do
        local rank = tonumber(rankIndex)
        if enabled and rank and rank >= 0 and rank <= 9 and rank % 1 == 0 then
            ranks[#ranks + 1] = rank
        end
    end
    table.sort(ranks, function(left, right)
        return left < right
    end)
    for index, rank in ipairs(ranks) do
        ranks[index] = tostring(rank)
    end
    return ranks
end

local function DecodeEnabledRanks(payload)
    local ranks = {}
    for rankIndex in tostring(payload or ""):gmatch("[^,]+") do
        local rank = tonumber(rankIndex)
        if rank and rank >= 0 and rank <= 9 and rank % 1 == 0 then
            ranks[tostring(rank)] = true
        end
    end
    return ranks
end

-- Entscheidungen als "name:status:datum", getrennt durch Komma. Das Feld hängt
-- am Ende der Gildenprofil-Nutzlast, damit ältere Clients es schlicht
-- ignorieren; fehlt es beim Empfang, bleiben die eigenen Einträge stehen.
local function EncodeMemberCareDecisions(decisions)
    local records = {}
    for _, decision in pairs(decisions or {}) do
        local name = GC.Util.Trim(decision.name):gsub("[,:|]", "")
        if name ~= "" and GC.MemberCareDecisions[decision.status] then
            records[#records + 1] = table.concat({
                name,
                decision.status,
                decision.until_ or "",
            }, ":")
        end
    end
    table.sort(records)
    while #records > GC.MemberCareMaxDecisions do
        table.remove(records)
    end
    return table.concat(records, ",")
end

local function DecodeMemberCareDecisions(payload)
    local decisions = {}
    for record in tostring(payload or ""):gmatch("[^,]+") do
        local name, status, untilDate = record:match("^([^:]+):([^:]+):?([^:]*)$")
        if name and GC.MemberCareDecisions[status] then
            decisions[GC.Util.NormalizeName(name)] = {
                name = name,
                status = status,
                until_ = untilDate or "",
                at = GC.Util.Now(),
            }
        end
    end
    return decisions
end

-- Nur ID und Stufe wandern durch die Gilde; den Namen loest jeder Client in
-- seiner eigenen Sprache aus dem Tooltip auf.
local VERDICT_CODES = { OPTIMAL = "O", SOLID = "S", IMPROVABLE = "V" }
local VERDICT_BY_CODE = { O = "OPTIMAL", S = "SOLID", V = "IMPROVABLE" }

local function EncodeEnchantRules(rules)
    local records = {}
    for enchantID, rule in pairs(rules or {}) do
        local code = VERDICT_CODES[rule.verdict]
        if code and tonumber(enchantID) then
            records[#records + 1] = tostring(tonumber(enchantID)) .. ":" .. code
        end
    end
    table.sort(records)
    while #records > 80 do
        table.remove(records)
    end
    return table.concat(records, ",")
end

-- Spec-Bewertungen als "spec:id:code". Das Feld haengt am Ende der Nutzlast,
-- damit aeltere Clients es schlicht ignorieren, statt daran zu scheitern.
local function EncodeSpecEnchantRules(specRules)
    local records = {}
    for specKey, rules in pairs(specRules or {}) do
        if GC.SpecByKey[specKey] then
            for enchantID, rule in pairs(rules or {}) do
                local code = VERDICT_CODES[rule.verdict]
                if code and tonumber(enchantID) then
                    records[#records + 1] = specKey .. ":" .. tostring(tonumber(enchantID)) .. ":" .. code
                end
            end
        end
    end
    table.sort(records)
    while #records > 240 do
        table.remove(records)
    end
    return table.concat(records, ",")
end

local function DecodeSpecEnchantRules(payload)
    local specRules = {}
    for record in tostring(payload or ""):gmatch("[^,]+") do
        local specKey, enchantID, code = record:match("^([%u]+:%d+):(%d+):(%a)$")
        if specKey and GC.SpecByKey[specKey] and VERDICT_BY_CODE[code] then
            specRules[specKey] = specRules[specKey] or {}
            specRules[specKey][enchantID] = {
                verdict = VERDICT_BY_CODE[code],
                name = "",
                by = "",
                at = GC.Util.Now(),
            }
        end
    end
    return specRules
end

local function DecodeEnchantRules(payload)
    local rules = {}
    for record in tostring(payload or ""):gmatch("[^,]+") do
        local enchantID, code = record:match("^(%d+):(%a)$")
        if enchantID and VERDICT_BY_CODE[code] then
            rules[enchantID] = {
                verdict = VERDICT_BY_CODE[code],
                name = "",
                by = "",
                at = GC.Util.Now(),
            }
        end
    end
    return rules
end

-- Die Warcraft-Logs-Gildenquelle als "host,region,realm,gilde". Kommas kommen
-- in Hosts und Slugs nicht vor, der Gildenname wird beim Lesen wieder
-- zusammengesetzt. Das Feld haengt am Ende der Gildenprofil-Nutzlast, damit
-- aeltere Clients es schlicht ignorieren.
local function EncodeWarcraftLogsSource(data)
    data = data or {}
    local region = GC.Util.Trim(data.region)
    local serverSlug = GC.Util.Trim(data.serverSlug)
    if region == "" or serverSlug == "" then
        return ""
    end
    -- Die Klammern sind nicht schmueckend: gsub liefert zwei Werte, und der
    -- letzte Eintrag einer Tabellenliste wuerde beide aufnehmen.
    return table.concat({
        (GC.Util.Trim(data.host):gsub(",", "")),
        (region:gsub(",", "")),
        (serverSlug:gsub(",", "")),
        (GC.Util.Trim(data.guildSlug):gsub(",", " ")),
    }, ",")
end

local function DecodeWarcraftLogsSource(payload)
    local host, region, serverSlug, guildSlug =
        tostring(payload or ""):match("^([^,]*),([^,]+),([^,]+),(.*)$")
    if not region or GC.Util.Trim(serverSlug) == "" then
        return nil
    end
    host = GC.Util.Trim(host)
    if host == "" then
        host = GC.Constants.WCL_DEFAULT_HOST
    end
    return {
        host = host,
        region = region,
        serverSlug = serverSlug,
        guildSlug = GC.Util.Trim(guildSlug),
    }
end

function GC.Sync:RegisterPrefix()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        self.registered = C_ChatInfo.RegisterAddonMessagePrefix(GC.Constants.COMM_PREFIX) == true
    elseif RegisterAddonMessagePrefix then
        self.registered = RegisterAddonMessagePrefix(GC.Constants.COMM_PREFIX) == true
    end
end

-- Der Anniversary-Client liefert Enum.SendAddonMessageResult (0 = Erfolg,
-- 3/8 = gedrosselt, ...), klassische Clients true oder gar nichts. Wer nur auf
-- "~= false" prueft, haelt gedrosselte Pakete fuer zugestellt - sie gehen dann
-- lautlos verloren und der Transfer bleibt ohne erkennbaren Grund
-- unvollstaendig. Nur ein echter Erfolg zaehlt als gesendet; alles andere
-- laesst die Warteschlangen mit ihrem Backoff erneut anlaufen.
local function AddonSendSucceeded(result)
    if result == nil or result == true then
        return true
    end
    if type(result) == "number" then
        return result == 0
    end
    return result ~= false
end

function GC.Sync:Send(payload, distribution, target)
    distribution = distribution or "GUILD"
    if not payload or #payload > GC.Constants.MAX_CHAT_BYTES then
        return false
    end
    if distribution == "GUILD" and (not IsInGuild or not IsInGuild()) then
        return false
    end
    if distribution == "WHISPER" and GC.Util.Trim(target) == "" then
        return false
    end

    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        local success, result = pcall(
            C_ChatInfo.SendAddonMessage,
            GC.Constants.COMM_PREFIX,
            payload,
            distribution,
            target
        )
        return success and AddonSendSucceeded(result)
    elseif SendAddonMessage then
        local success, result = pcall(
            SendAddonMessage,
            GC.Constants.COMM_PREFIX,
            payload,
            distribution,
            target
        )
        return success and AddonSendSucceeded(result)
    end
    return false
end

local function FinishBulkEntry(entry, success)
    if type(entry.callback) == "function" then
        pcall(entry.callback, success == true)
    end
end

-- Grosse Datenmengen landen in einer gemeinsamen, durchsatzorientierten
-- Warteschlange. Ein vorhandenes ChatThrottleLib kennt auch den Verkehr
-- anderer Addons; der eingebaute Fallback macht Guild Copilot Forever eigenstaendig.
-- "untracked" schaltet die Fortschrittszaehlung fuer dieses Paket ab. Genau ein
-- Aufrufer braucht das: der bestaetigte Fluestertransfer. Seine Teile werden
-- ueber die ACK-Liste gezaehlt und wuerden hier ein zweites Mal auftauchen -
-- ein Zehn-Teile-Transfer meldete dadurch bis zu vierzehn offene Pakete.
function GC.Sync:SendBulk(payload, distribution, target, callback, untracked)
    distribution = distribution or "GUILD"
    if not payload or #payload > GC.Constants.MAX_CHAT_BYTES then
        return false
    end
    if distribution == "GUILD" and (not IsInGuild or not IsInGuild()) then
        return false
    end
    if distribution == "WHISPER" and GC.Util.Trim(target) == "" then
        return false
    end

    -- Ab hier gilt das Paket als eingereiht. Der Abschluss darf genau einmal
    -- gezaehlt werden, egal welcher der beiden Sendewege ihn meldet.
    if untracked ~= true then
        self:NoteBulkQueued()
    end
    local finished = false
    local function Finish(success)
        if finished then
            return
        end
        finished = true
        if untracked ~= true then
            GC.Sync:NoteBulkFinished(success)
        end
        if type(callback) == "function" then
            pcall(callback, success == true)
        end
    end

    -- JEDES Paket geht zuerst in die eigene Warteschlange - auch dann, wenn
    -- eine globale ChatThrottleLib vorhanden ist. An ChatThrottleLib uebergibt
    -- erst PumpBulk, und zwar Paket fuer Paket.
    --
    -- Bis 0.9.90 wurde hier direkt uebergeben, sofern kein Kampf lief. Damit
    -- war die Einstellung "Bulk-Sync im Kampf pausieren" nur halb wirksam: Ein
    -- Paket, das eine Sekunde vor dem Pull uebergeben wurde, lag nicht mehr in
    -- der eigenen Warteschlange und liess sich nicht mehr anhalten. Die
    -- Werkstatt reicht ihre gesamte Warteschlange in EINEM Durchlauf weiter
    -- (PumpSyncQueue) - ein vollstaendiger Rezeptkatalog war damit komplett
    -- ausser Reichweite, sobald der Kampf begann. Pausiert wurde nur noch,
    -- was zufaellig waehrend des Kampfes eingereiht wurde.
    --
    -- Die eigene Warteschlange bleibt deshalb massgeblich. ChatThrottleLib
    -- behaelt ihre Aufgabe - sie kennt den Verkehr anderer Addons und teilt
    -- den Kanal fair auf -, bekommt aber immer nur das naechste Paket.
    self.bulkQueue[#self.bulkQueue + 1] = {
        payload = payload,
        distribution = distribution,
        target = target,
        guildKey = (distribution == "GUILD" or distribution == "WHISPER") and GC:GetGuildKey() or nil,
        callback = Finish,
        retries = 0,
    }
    -- Waehrend der Leerlaufpause hat sich das Sendebudget weiter gefuellt;
    -- die verstrichene Zeit wird beim Aufwachen in einem Schritt nachgebucht.
    local idle = 0
    if self.bulkIdleAt then
        idle = math.max(0, GC.Util.Now() - self.bulkIdleAt)
        self.bulkIdleAt = nil
    end
    bulkFrame:Show()
    self:PumpBulk(idle)
    return true
end

-- Ein einzelnes Paket auf den Weg bringen. Liegt eine globale ChatThrottleLib
-- vor, geht es ueber sie: Sie kennt auch den Verkehr anderer Addons und teilt
-- den Kanal fair auf. Den Erfolg meldet sie erst spaeter ueber ihren Rueckruf -
-- fuer die Warteschlange ist das Paket mit der Uebergabe erledigt, der
-- Abschluss kommt dann von dort.
--
-- Rueckgabe: ob es raus ist, und ob der Abschluss noch aussteht.
local function DispatchBulk(self, entry)
    local throttle = _G and _G.ChatThrottleLib
    if throttleAvailable() then
        local queueName = GC.Constants.COMM_PREFIX .. ":" .. entry.distribution
            .. ":" .. (entry.target or "")

        -- Der Vermerk steht VOR der Uebergabe, und er traegt eine laufende
        -- Nummer.
        --
        -- Beides ist noetig, und beides hat gefehlt:
        --
        --   Vorher gesetzt, weil ChatThrottleLib den Rueckruf bei freiem Kanal
        --   SYNCHRON ausloest - noch innerhalb von SendAddonMessage. Stand der
        --   Vermerk danach, loeschte der Rueckruf ein Feld, das noch gar nicht
        --   gesetzt war, und anschliessend trug sich das laengst erledigte
        --   Paket als "unterwegs" ein. Aufgeloest hat das nur der Watchdog -
        --   fuenfzehn Sekunden, je Paket. Ein Abgleich mit dreissig Paketen
        --   haette so ueber sieben Minuten gebraucht statt weniger Sekunden.
        --
        --   Mit Nummer, weil ein verspaeteter Rueckruf sonst den Vermerk eines
        --   NEUEREN Pakets loescht. Hat der Watchdog Paket A freigegeben und
        --   laeuft laengst B, gaebe A's Rueckruf faelschlich C frei - und dann
        --   liegen wieder zwei gleichzeitig bei ChatThrottleLib, womit die
        --   Kampfpause ihre Zusicherung verliert.
        self.bulkDispatchToken = (tonumber(self.bulkDispatchToken) or 0) + 1
        local token = self.bulkDispatchToken
        self.bulkInFlight = entry
        self.bulkInFlightAt = GC.Util.Now()

        local ok = pcall(
            throttle.SendAddonMessage,
            throttle,
            "BULK",
            GC.Constants.COMM_PREFIX,
            entry.payload,
            entry.distribution,
            entry.target,
            queueName,
            function(_, sent)
                -- Erst dieser Rueckruf gibt das naechste Paket frei. Gesendet
                -- wird es aber nicht von hier aus, sondern beim naechsten
                -- OnUpdate des Rahmens - der prueft vorher wieder auf Kampf.
                if self.bulkDispatchToken == token then
                    self.bulkInFlight = nil
                    self.bulkInFlightAt = nil
                end
                FinishBulkEntry(entry, sent ~= false)
            end,
            nil
        )
        if ok then
            return true, true
        end

        -- Die Uebergabe selbst ist gescheitert: Der Vermerk muss wieder weg,
        -- sonst haelt er die Warteschlange bis zum Watchdog an.
        if self.bulkDispatchToken == token then
            self.bulkInFlight = nil
            self.bulkInFlightAt = nil
        end
    end
    return self:Send(entry.payload, entry.distribution, entry.target) == true, false
end

-- Der eigentliche Durchlauf. Er steht als lokale Funktion da, damit die
-- Wiedereintrittssperre in GC.Sync:PumpBulk ihn genau einmal umschliessen
-- kann - der Rumpf steigt an einem halben Dutzend Stellen vorzeitig aus, und
-- eine Sperre, die an jedem dieser Ausgaenge von Hand zurueckgesetzt werden
-- muss, ist genau die Sorte Fehler, die hier behoben wird.
local function PumpBulkOnce(self, elapsed)
    elapsed = math.max(0, tonumber(elapsed) or 0)
    self.bulkAllowance = math.min(
        BULK_BURST_BYTES,
        (tonumber(self.bulkAllowance) or BULK_BURST_BYTES) + (elapsed * BULK_BYTES_PER_SECOND)
    )

    -- Im Kampf schlafen legen statt jeden Frame leer durchzulaufen. Vorher
    -- blieb der Rahmen sichtbar: Der Handler lief den ganzen Kampf ueber bei
    -- jedem einzelnen Frame an, nur um sofort wieder auszusteigen.
    -- PLAYER_REGEN_ENABLED weckt ihn unten wieder auf.
    if #self.bulkQueue > 0 and InCombat() then
        self.bulkCombatAt = self.bulkCombatAt or GC.Util.Now()
        bulkFrame:Hide()
        return
    end
    self.bulkCombatAt = nil

    -- Bei ChatThrottleLib liegt immer hoechstens EIN Paket.
    --
    -- Das ist der Punkt, an dem die Kampfpause vollstaendig wird. Bis 0.9.91
    -- lief die Schleife unten weiter, solange das Burst-Budget reichte - rund
    -- vier Kilobyte, also gut achtzehn Pakete auf einen Schlag. Die lagen dann
    -- bei ChatThrottleLib und gingen auch waehrend des Kampfes weiter raus;
    -- anhalten laesst sich nur, was noch in der eigenen Warteschlange steht.
    --
    -- Freigegeben wird das naechste Paket erst vom Rueckruf des vorigen, und
    -- der Weg dorthin fuehrt wieder durch diese Funktion - also durch die
    -- Kampfpruefung darueber. Beginnt der Kampf, ist damit hoechstens noch ein
    -- einziges Paket unterwegs.
    if self.bulkInFlight then
        -- Der Platz bleibt belegt, bis ChatThrottleLib zurueckmeldet. Es gibt
        -- keine Frist, nach der er von selbst frei wird.
        --
        -- 0.9.92 hatte hier einen Watchdog: nach fuenfzehn Sekunden galt das
        -- Paket als verloren und das naechste ging raus. Die Annahme dahinter
        -- war falsch. ChatThrottleLib v31 kennt fuer eingereihte Nachrichten
        -- weder eine Ablaufzeit noch einen Abbruch - das Paket liegt weiter in
        -- ihrer Warteschlange und wird gesendet, sobald der Kanal es zulaesst.
        -- Wer den Platz freigibt, hat danach ZWEI Pakete draussen, nach dem
        -- naechsten Ablauf drei. Genau das war unter Last messbar.
        --
        -- Zeitueberschreitung ist eben nicht Verlust, sondern nur Wartezeit.
        -- Zurueckziehen laesst sich nichts, also wird gewartet. Dass der
        -- Abgleich haengt, meldet die Fortschrittsanzeige ueber ihre eigene
        -- Sperre (PROGRESS_STALL_SECONDS) - das ist die richtige Stelle dafuer,
        -- denn sie sagt es, ohne den Zustand zu verfaelschen.
        -- 0.9.94 hatte hier noch eine Ausnahme: Ist die globale
        -- ChatThrottleLib verschwunden, koenne sie nichts mehr zustellen, also
        -- duerfe der Platz frei werden. Auch das war eine unbelegte Annahme.
        -- Die Bibliothek haelt ihre eigene Referenz und einen laufenden Frame;
        -- eine eingereihte Nachricht geht weiter raus und meldet zurueck,
        -- ganz gleich ob die globale Variable noch existiert. Der Platz wurde
        -- damit erneut frei, waehrend das Paket noch unterwegs war.
        --
        -- Es gibt keinen Zustand, aus dem sich "das Paket kommt nie an"
        -- ableiten laesst. Also wird gewartet, und zwar ohne Ausnahme.
        return
    end

    -- Hat der Client zuletzt eine Nachricht abgelehnt, erst nach einer echten
    -- Wartezeit erneut senden. Ohne diese Pause verbraucht ein Ratenlimit alle
    -- Wiederholungen im selben Sekundenbruchteil, und Pakete gelten faelschlich
    -- als verloren, obwohl der Kanal nur kurz dicht war.
    if (self.bulkCooldown or 0) > 0 then
        self.bulkCooldown = math.max(0, self.bulkCooldown - elapsed)
        if self.bulkCooldown > 0 then
            return
        end
    end

    while #self.bulkQueue > 0 do
        local entry = self.bulkQueue[1]
        -- A combat pause can outlast a guild change. Old guild data must
        -- never resume into the newly joined guild (or to an old requester).
        while entry and entry.guildKey and entry.guildKey ~= GC:GetGuildKey() do
            table.remove(self.bulkQueue, 1)
            FinishBulkEntry(entry, false)
            entry = self.bulkQueue[1]
        end
        if not entry then break end
        local cost = #entry.payload + BULK_MESSAGE_OVERHEAD
        if self.bulkAllowance < cost then
            return
        end

        -- Das eigene Sendebudget gilt jetzt auch fuer den Weg ueber
        -- ChatThrottleLib. Beide drosseln damit, und es gilt die jeweils
        -- vorsichtigere Schranke - das ist gewollt: Der Kanal gehoert nicht
        -- diesem Addon allein.
        local sent, deferred = DispatchBulk(self, entry)
        if sent then
            self.bulkAllowance = self.bulkAllowance - cost
            table.remove(self.bulkQueue, 1)
            if deferred then
                -- Es liegt jetzt eines bei ChatThrottleLib. Schluss fuer
                -- diesen Durchlauf: Das naechste holt der Rueckruf, und der
                -- kommt hier oben wieder an der Kampfpruefung vorbei.
                return
            end
            FinishBulkEntry(entry, true)
        else
            entry.retries = entry.retries + 1
            if entry.retries >= BULK_MAX_RETRIES then
                table.remove(self.bulkQueue, 1)
                FinishBulkEntry(entry, false)
            else
                -- Der Kanal hat abgelehnt (Client-Ratenlimit). Kein Kanalbudget
                -- verbraucht, aber mit wachsendem zeitlichem Abstand erneut
                -- versuchen, damit sich das Limit erholen kann.
                self.bulkAllowance = math.max(cost, self.bulkAllowance)
                self.bulkCooldown = math.min(
                    BULK_MAX_RETRY_DELAY,
                    BULK_RETRY_BACKOFF * entry.retries
                )
                return
            end
        end
    end

    -- Die Warteschlange ist leer: schlafen legen, bis SendBulk wieder etwas
    -- einreiht. Der Zeitstempel merkt sich den Beginn der Pause fuer die
    -- Budget-Nachbuchung beim Aufwachen.
    self.bulkIdleAt = self.bulkIdleAt or GC.Util.Now()
    bulkFrame:Hide()
end

-- Wiedereintrittssperre.
--
-- ChatThrottleLib loest ihren Rueckruf bei freiem Kanal SYNCHRON aus - noch
-- innerhalb von SendAddonMessage, also mitten in DispatchBulk und damit
-- BEVOR die Schleife oben ihr Paket aus der Warteschlange genommen hat. Fuehrt
-- dieser Rueckruf zurueck in SendBulk - und genau das tun der bestaetigte
-- Fluestertransfer (ReliablePartDispatched -> PumpReliable) und die Werkstatt
-- (QueueProfessionSync im onFailure-Zweig) -, dann lief PumpBulk ein zweites
-- Mal an und griff auf dasselbe bulkQueue[1] zu.
--
-- Nachgestellt hat das Folgendes ergeben:
--   * das erste Paket ging ZWEIMAL ueber die Leitung,
--   * das im Rueckruf eingereihte Paket ging GAR NICHT raus,
--   * bulkOutstanding blieb auf 1 stehen und wurde nach zwei Minuten als
--     Verlust verbucht - der Grund fuer "Abgleich unvollstaendig" ohne
--     tatsaechlichen Verlust.
--
-- ChatThrottleLib ist ueber DBM, Details! und WeakAuras praktisch in jeder
-- Raidgilde geladen; ohne sie tritt der Fall nicht auf, weshalb er im Test
-- ohne Bibliothek unsichtbar blieb.
--
-- Der wiedereintretende Aufruf reiht sich jetzt nur vor und kehrt um; der
-- aeussere Durchlauf raeumt sein Paket ordentlich ab und holt die Vormerkung
-- danach nach.
function GC.Sync:PumpBulk(elapsed)
    if self.bulkPumping then
        self.bulkPumpPending = true
        return
    end
    self.bulkPumping = true
    local ok, err = pcall(PumpBulkOnce, self, elapsed)
    self.bulkPumping = false
    if not ok then
        -- Ein Fehler im Durchlauf darf die Sperre nicht dauerhaft stehen
        -- lassen; sonst stuende die Warteschlange bis zum Neuladen still.
        self.bulkPumpPending = false
        error(err, 0)
    end
    if self.bulkPumpPending then
        self.bulkPumpPending = false
        -- Ohne neue Zeitgutschrift: Das Budget wurde im aeusseren Durchlauf
        -- bereits verrechnet.
        self:PumpBulk(0)
    end
end

function GC.Sync:WakeProgress()
    if not progressFrame:IsShown() then
        progressElapsed = 0
        progressFrame:Show()
    end
end

function GC.Sync:NoteBulkQueued()
    self.bulkOutstanding = (tonumber(self.bulkOutstanding) or 0) + 1
    self:WakeProgress()
end

function GC.Sync:NoteBulkFinished(success)
    self.bulkOutstanding = math.max(0, (tonumber(self.bulkOutstanding) or 1) - 1)
    if success == false then
        self.progressFailed = (tonumber(self.progressFailed) or 0) + 1
    end
    self:WakeProgress()
end

-- Fuer Uebertragungen, die sich selbst takten statt SendBulk zu benutzen.
function GC.Sync:NoteSerialPending(delta)
    self.serialPending = math.max(0, (tonumber(self.serialPending) or 0) + (tonumber(delta) or 0))
    self:WakeProgress()
end

-- Wie viele Teile aller laufenden Uebertragungen noch fehlen - und wie viele
-- Uebertragungen so lange stillstehen, dass sie als verloren gelten.
--
-- Aufgeraeumt wird hier gleich mit, nach derselben Frist, die jedes Modul
-- ohnehin anwendet. Sonst haengt der Rest einer abgebrochenen Uebertragung bis
-- zum naechsten Verkehr derselben Art in der Zahl: Die Module raeumen ihre
-- Tabellen nur beim Empfang auf, und wenn nichts mehr kommt, kommt auch das
-- Aufraeumen nicht. Der Balken meldete dann bis zum Ausloggen "unvollstaendig",
-- obwohl das seit einer Stunde niemanden mehr betrifft.
local function CountMissingParts(transfers, now, pending, lost)
    for key, transfer in pairs(transfers or {}) do
        if type(transfer) == "table" then
            local age = now - (tonumber(transfer.receivedAt) or now)
            local total = tonumber(transfer.total) or 0
            local received = tonumber(transfer.received)
            if not received then
                received = 0
                for _ in pairs(transfer.chunks or transfer.parts or {}) do
                    received = received + 1
                end
            end
            local missing = math.max(0, total - received)
            if age > PROGRESS_INCOMING_DROP then
                transfers[key] = nil
            elseif missing > 0 then
                if age > PROGRESS_INCOMING_STALE then
                    lost[1] = lost[1] + missing
                else
                    pending[1] = pending[1] + missing
                end
            end
        end
    end
end

function GC.Sync:GetIncomingPendingCount()
    local now = GC.Util.Now()
    local pending, lost = { 0 }, { 0 }
    CountMissingParts(self.guildProfileIncoming, now, pending, lost)
    if GC.Workshop then
        CountMissingParts(GC.Workshop.incoming, now, pending, lost)
    end
    if GC.Inventory then
        CountMissingParts(GC.Inventory.guildBankIncoming, now, pending, lost)
    end
    if GC.GearAudit then
        CountMissingParts(GC.GearAudit.equipmentIncoming, now, pending, lost)
    end
    if GC.WarcraftLogs then
        CountMissingParts(GC.WarcraftLogs.syncIncoming, now, pending, lost)
    end
    if GC.RaidMonitor then
        CountMissingParts(GC.RaidMonitor.incoming, now, pending, lost)
    end
    return pending[1], lost[1]
end

-- Der aktuelle Stand des Abgleichs. Die Funktion schreibt den Zyklus fort und
-- gibt ihn zurueck; sie ist damit zugleich der Taktgeber und die Auskunft.
--
--   percent      0-100, immer ehrlich: 100 gibt es nur ohne offene Arbeit
--   state        RUNNING | SYNCED | INCOMPLETE | IDLE
--   outstanding  Pakete und Datensaetze, die noch fehlen
--   lastSyncedAt wann zuletzt nichts mehr offen war
function GC.Sync:GetSyncStatus()
    local now = GC.Util.Now()
    local status = self.syncStatus
    if not status then
        status = {
            total = 0,
            done = 0,
            failed = 0,
            percent = 100,
            state = "IDLE",
            outstanding = 0,
            outbound = 0,
            inbound = 0,
            missing = 0,
            lastSyncedAt = 0,
            changedAt = now,
        }
        self.syncStatus = status
    end

    -- Jedes Paket zaehlt genau einmal: gewoehnliche Bulk-Pakete ueber den
    -- Zaehler, selbst getaktete Uebertragungen ueber serialPending, bestaetigte
    -- Fluesterteile ueber ihre ACK-Liste. Die Teile des dritten Wegs sind
    -- ausdruecklich von der Bulk-Zaehlung ausgenommen (siehe SendBulk).
    -- Getrennt gehalten, weil nur der erste Teil von der Stillstandssperre
    -- unten abgeraeumt werden KANN: Die bestaetigten Fluesterteile haengen an
    -- ihrer eigenen Liste und geben mit GiveUpReliablePart selbst auf.
    local sweepable = math.max(0, tonumber(self.bulkOutstanding) or 0)
        + math.max(0, tonumber(self.serialPending) or 0)
    local reliable = self:GetReliablePendingCount()
    local outbound = sweepable + reliable

    -- Liegt nachweislich noch ein Paket bei ChatThrottleLib, wartet der
    -- Zaehler, er steht nicht still.
    --
    -- Genau das hat die Sperre unten bis 0.9.94 nicht unterschieden: Sie hat
    -- nach zwei Minuten ohne Bewegung alles als verloren verbucht - auch die
    -- Pakete, die noch ordnungsgemaess in der fremden Warteschlange lagen.
    -- Kamen deren Rueckmeldungen danach an, war der Fehlerzaehler laengst
    -- hochgesetzt, und der Abgleich blieb bis zum Ausloggen "unvollstaendig",
    -- obwohl jedes einzelne Paket angekommen war. Das ist derselbe Denkfehler,
    -- den 0.9.94 in der Warteschlange abgestellt hat - Wartezeit ist kein
    -- Verlust -, nur eine Ebene hoeher in der Anzeige.
    local waitingAt = self.bulkInFlight and tonumber(self.bulkInFlightAt) or nil
    status.waiting = waitingAt ~= nil
        and (now - waitingAt) > PROGRESS_STALL_SECONDS
        or false

    -- Im Kampf steht die Warteschlange absichtlich. Das ist keine Stoerung und
    -- gehoert auch nicht als solche angezeigt.
    status.paused = #self.bulkQueue > 0 and InCombat() or false

    -- Was nachweislich noch bei uns oder bei ChatThrottleLib liegt, ist nicht
    -- verloren. Beides zusammen: ein uebergebenes Paket (bulkInFlight) und
    -- alles, was noch in der eigenen Warteschlange steht.
    --
    -- Der zweite Teil hat gefehlt. Dauert ein Kampf laenger als zwei Minuten,
    -- liegen die pausierten Pakete weiterhin vollstaendig in bulkQueue - die
    -- Sperre hat sie trotzdem als verloren gebucht und den Zaehler abgeraeumt,
    -- obwohl sie nach dem Kampf ordnungsgemaess rausgingen.
    local held = self.bulkInFlight ~= nil or #self.bulkQueue > 0

    -- Der Sendezaehler ist der einzige Wert, der lecken kann. Kommt er zwei
    -- Minuten lang nicht voran UND ist nichts mehr in der Leitung, gilt das
    -- Ausstehende als verloren. Empfang und bekannte Luecken bleiben
    -- unangetastet - sie verfallen von selbst.
    --
    -- Ausgebucht wird ausschliesslich, was hier auch abgeraeumt wird.
    -- Vorher ging der GESAMTE outbound-Wert in den Fehlerzaehler, obwohl die
    -- Fluesterteile davon unberuehrt blieben: outbound sank dadurch nicht,
    -- outboundChangedAt rueckte nie weiter, und derselbe Block feuerte beim
    -- naechsten Statusabruf erneut - bei einem Anzeigetakt von einer halben
    -- Sekunde wuchs der gemeldete Verlust unbegrenzt.
    if sweepable > 0 and not held and outbound == status.outbound
        and (now - (status.outboundChangedAt or now)) > PROGRESS_STALL_SECONDS then
        self.progressFailed = (tonumber(self.progressFailed) or 0) + sweepable
        self.bulkOutstanding = 0
        self.serialPending = 0
        outbound = reliable
        -- Ausdruecklich weitersetzen: Bleibt outbound durch die Fluesterteile
        -- gleich, greift die Zuweisung unten nicht, und die Sperre liefe sofort
        -- wieder an.
        status.outboundChangedAt = now
    end
    if outbound ~= status.outbound then
        status.outboundChangedAt = now
    end

    local inbound, lostInbound = self:GetIncomingPendingCount()
    local missing = 0
    if GC.Workshop and GC.Workshop.GetPendingWantCount then
        missing = GC.Workshop:GetPendingWantCount()
    end
    -- Angekuendigte Berufe, deren Daten im Zeitfenster nicht kamen. Sie zaehlen
    -- wie verlorene Pakete in die Fehlbilanz: Ein Zyklus, in dem ein Beruf
    -- ausblieb, war nicht vollstaendig - bis 0.9.101 verschwand der Eintrag
    -- lautlos, und ueber dem Loch stand "Vollstaendig synchronisiert".
    local lostWants = 0
    if GC.Workshop and GC.Workshop.GetLostWantCount then
        lostWants = GC.Workshop:GetLostWantCount()
    end
    local outstanding = outbound + inbound + missing

    if outstanding ~= status.outstanding then
        status.changedAt = now
    end
    status.outbound = outbound
    status.inbound = inbound
    status.missing = missing
    status.outstanding = outstanding
    status.lostWants = lostWants
    status.failed = (tonumber(self.progressFailed) or 0) + lostInbound + lostWants
    -- Belegbar ist nur "nichts offen". Ob der eigene Stand dem der Gilde
    -- entspricht, weiss dieser Client erst, wenn sich ueberhaupt jemand
    -- gemeldet hat - vorher gibt es nichts, womit er sich vergleichen koennte.
    status.peerSeenAt = tonumber(self.lastPeerAt) or 0
    -- Die zweite Haelfte der Ehrlichkeit: Berufe, die es in der Gilde
    -- nachweislich gibt, deren Daten aber nie hier ankamen, weil ihr Besitzer
    -- nicht gleichzeitig online war. Sie sind keine offene Arbeit - anfordern
    -- laesst sich nichts -, aber "vollstaendig" darf die Anzeige mit ihnen
    -- nicht mehr sagen.
    if GC.Workshop and GC.Workshop.GetCoverageGapSummary then
        status.coverage = GC.Workshop:GetCoverageGapSummary()
    end

    if outstanding > 0 then
        if status.state ~= "RUNNING" then
            status.startedAt = now
            -- Ein neuer Zyklus faengt mit einer leeren Fehlerbilanz an - auch
            -- bei den ausgebliebenen Berufen: Was jetzt neu angekuendigt wird,
            -- bekommt seine eigene Frist.
            self.progressFailed = 0
            if GC.Workshop and GC.Workshop.ResetLostWants then
                GC.Workshop:ResetLostWants()
            end
            status.lostWants = 0
            status.failed = lostInbound
            -- ... und bei null. Ohne dieses Zuruecksetzen bliebe der Balken
            -- auf den 100 % des vorigen Durchlaufs stehen, weil er innerhalb
            -- eines Zyklus nicht mehr zurueckfaellt.
            status.total = 0
            status.done = 0
            status.percent = 0
        end
        status.total = math.max(status.total, status.done + outstanding)
        status.done = math.max(0, status.total - outstanding)

        -- Der Balken faellt innerhalb eines Zyklus nie zurueck.
        --
        -- Der Anteil done/total ist zwar richtig gerechnet, als Anzeige aber
        -- unbrauchbar: Der Nenner ist der UMFANG, und der waechst, sobald neue
        -- Arbeit auftaucht. Beim Berufsabgleich passiert das laufend - jedes
        -- eintreffende fremde Manifest meldet weitere fehlende Rezepte.
        --
        -- Gerechnet sah das so aus: 8 von 10 Paketen erledigt sind 80 %.
        -- Kommen zehn Pakete dazu, sind dieselben 8 nur noch 8 von 20 - also
        -- 40 %, ohne dass irgendetwas verloren gegangen waere. Bei einem Takt
        -- von einer halben Sekunde ergab das die gemeldete Folge
        -- 80 -> 40 -> 90 -> 10, und damit eine Anzeige, aus der sich der
        -- Fortschritt nicht mehr ablesen liess.
        --
        -- Erledigtes bleibt erledigt, also steigt der Balken nur. Dass der
        -- Umfang gewachsen ist, sagt die Zeile darunter mit der echten Zahl
        -- der offenen Pakete - dort ist ein Sprung nach oben eine Auskunft
        -- statt einer Irritation.
        local percent = status.total > 0
            and math.min(99, math.floor((status.done / status.total) * 100))
            or 0
        status.percent = math.max(tonumber(status.percent) or 0, percent)
        status.state = "RUNNING"
    else
        -- "Zuletzt vollstaendig" bekommt nur ein Zyklus, der auch vollstaendig
        -- war. Ein Durchlauf mit verlorenen Paketen darf sich nicht als Stand
        -- ausgeben - sonst steht "Stand: gerade eben" ueber luckenhaften Daten.
        if status.state == "RUNNING" and status.failed == 0 then
            status.lastSyncedAt = now
        end
        status.total = 0
        status.done = 0
        status.percent = 100
        if status.failed > 0 then
            status.state = "INCOMPLETE"
        elseif (status.lastSyncedAt or 0) > 0 then
            status.state = "SYNCED"
        else
            status.state = "IDLE"
        end
    end
    return status
end

-- Der Rahmen laeuft nur, solange etwas offen ist. Er haelt den Zyklus auch dann
-- fort, wenn niemand hinsieht - sonst waere "zuletzt vollstaendig abgeglichen"
-- eine Zahl, die vom Zufall abhaengt, ob das Fenster gerade offen war.
progressFrame:SetScript("OnUpdate", function(_, elapsed)
    progressElapsed = progressElapsed + elapsed
    if progressElapsed < PROGRESS_TICK then
        return
    end
    progressElapsed = 0
    local status = GC.Sync:GetSyncStatus()
    if status.state ~= "RUNNING" then
        progressFrame:Hide()
    end
    GC:FireCallback("SYNC_PROGRESS", status)
end)

local function ReliableEntryID(kind, token, target)
    return table.concat({
        tostring(kind or ""),
        tostring(token or ""),
        GC.Util.NormalizeName(target),
    }, "|")
end

-- Wie viele Teile noch echt unterwegs sind. Aufgegebene zaehlen NICHT mit:
-- Sie kommen nie mehr an, und "unterwegs" waere dafuer das falsche Wort - sie
-- stehen in der Fehlerbilanz. Vorher hing ein verlorener Teil bis zum Ende des
-- ganzen Transfers als offen in der Zahl.
function GC.Sync:GetReliablePendingCount(kind)
    local count = 0
    local function AddEntry(entry)
        if not kind or entry.kind == kind then
            count = count + math.max(0, #entry.messages
                - (entry.acknowledgedCount or 0) - (entry.failedCount or 0))
        end
    end
    if self.reliableActive then
        AddEntry(self.reliableActive)
    end
    for _, entry in ipairs(self.reliableQueue) do
        AddEntry(entry)
    end
    return count
end

function GC.Sync:QueueReliable(messages, target, kind, token, onComplete, onFailure)
    if type(messages) ~= "table" or #messages == 0
        or GC.Util.Trim(target) == "" or GC.Util.Trim(kind) == ""
        or GC.Util.Trim(token) == "" then
        return false
    end
    for _, message in ipairs(messages) do
        if type(message) ~= "string" or #message > GC.Constants.MAX_CHAT_BYTES then
            return false
        end
    end

    local entry = {
        id = ReliableEntryID(kind, token, target),
        kind = kind,
        token = token,
        target = target,
        messages = messages,
        acknowledged = {},
        acknowledgedCount = 0,
        failed = {},
        failedCount = 0,
        pending = {},
        attempts = {},
        retryParts = {},
        nextPart = 1,
        inFlight = 0,
        onComplete = onComplete,
        onFailure = onFailure,
    }
    self.reliableQueue[#self.reliableQueue + 1] = entry
    self:WakeProgress()
    self:PumpReliable()
    return true
end

function GC.Sync:FinishReliable(success)
    local entry = self.reliableActive
    if not entry then
        return
    end
    self.reliableActive = nil
    local callback = success and entry.onComplete or entry.onFailure
    if type(callback) == "function" then
        pcall(callback, entry)
    end
    if self.reliablePumping then
        self.reliablePumpPending = true
    else
        self:PumpReliable()
    end
end

-- Der Transfer ist fertig, sobald jedes Teilpaket entweder bestaetigt oder
-- endgueltig aufgegeben wurde. Erfolg meldet nur, wer kein einziges Paket
-- verloren hat; sonst geht die tatsaechliche Zahl verlorener Pakete in den
-- Fehlschlag-Rueckruf ein.
function GC.Sync:MaybeFinishReliable()
    local entry = self.reliableActive
    if not entry then
        return false
    end
    if (entry.acknowledgedCount + (entry.failedCount or 0)) >= #entry.messages then
        self:FinishReliable((entry.failedCount or 0) == 0)
        return true
    end
    return false
end

local function GiveUpReliablePart(self, entry, part)
    if entry.acknowledged[part] or entry.failed[part] then
        return
    end
    entry.failed[part] = true
    entry.failedCount = (entry.failedCount or 0) + 1
    -- Hier und nur hier entsteht der Verlust eines Fluesterteils. Seit die
    -- Teile nicht mehr als Bulk-Pakete mitgezaehlt werden, kommt die
    -- Fehlerbilanz sonst nie an diese Information.
    self.progressFailed = (tonumber(self.progressFailed) or 0) + 1
    if not self:MaybeFinishReliable() and self.reliableActive == entry then
        self:PumpReliable()
    end
end

function GC.Sync:ReliablePartDispatched(entryID, part, success)
    local entry = self.reliableActive
    if not entry or entry.id ~= entryID or entry.acknowledged[part] or entry.failed[part] then
        return
    end
    if not success then
        entry.attempts[part] = (entry.attempts[part] or 0) + 1
        entry.pending[part] = nil
        entry.inFlight = math.max(0, entry.inFlight - 1)
        if entry.attempts[part] >= RELIABLE_MAX_ATTEMPTS then
            GiveUpReliablePart(self, entry, part)
            return
        end
        entry.retryParts[#entry.retryParts + 1] = part
        self:PumpReliable()
        return
    end

    entry.attempts[part] = (entry.attempts[part] or 0) + 1
    local attempt = entry.attempts[part]
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return
    end
    -- Wachsender Abstand: ein ueberlasteter Kanal bekommt mehr Zeit, das ACK
    -- doch noch zu liefern, bevor erneut gesendet wird.
    local delay = math.min(RELIABLE_RETRY_DELAY * attempt, RELIABLE_MAX_RETRY_DELAY)
    C_Timer.After(delay, function()
        local active = GC.Sync.reliableActive
        if not active or active.id ~= entryID or active.acknowledged[part]
            or active.failed[part]
            or active.attempts[part] ~= attempt or not active.pending[part] then
            return
        end
        active.pending[part] = nil
        active.inFlight = math.max(0, active.inFlight - 1)
        if attempt >= RELIABLE_MAX_ATTEMPTS then
            GiveUpReliablePart(GC.Sync, active, part)
            return
        end
        active.retryParts[#active.retryParts + 1] = part
        GC.Sync:PumpReliable()
    end)
end

function GC.Sync:PumpReliable()
    if self.reliablePumping then
        return
    end
    if not self.reliableActive then
        self.reliableActive = table.remove(self.reliableQueue, 1)
    end
    local entry = self.reliableActive
    if not entry then
        return
    end

    self.reliablePumping = true
    while self.reliableActive == entry and entry.inFlight < RELIABLE_WINDOW do
        local part = table.remove(entry.retryParts, 1)
        if not part then
            part = entry.nextPart
            entry.nextPart = entry.nextPart + 1
        end
        if not part or part > #entry.messages then
            break
        end
        if not entry.acknowledged[part] and not entry.pending[part] and not entry.failed[part] then
            local queuedPart = part
            entry.pending[part] = true
            entry.inFlight = entry.inFlight + 1
            -- Ungezaehlt: Dieser Teil steht bereits in der ACK-Liste und wuerde
            -- als Bulk-Paket ein zweites Mal in den Fortschritt eingehen.
            local queued = self:SendBulk(entry.messages[queuedPart], "WHISPER", entry.target, function(success)
                GC.Sync:ReliablePartDispatched(entry.id, queuedPart, success)
            end, true)
            if not queued then
                -- Ein abgelehnter Sendeversuch (kein gueltiges Ziel, nicht in der
                -- Gilde) ist dauerhaft. Das Paket gilt als verloren, statt die
                -- Warteschlange ohne Fortschritt kreisen zu lassen.
                entry.pending[queuedPart] = nil
                entry.inFlight = math.max(0, entry.inFlight - 1)
                GiveUpReliablePart(self, entry, queuedPart)
                break
            end
        end
    end
    self.reliablePumping = false
    if self.reliablePumpPending or (not self.reliableActive and #self.reliableQueue > 0) then
        self.reliablePumpPending = false
        self:PumpReliable()
    end
end

function GC.Sync:SendReliableAck(kind, token, part, target)
    if GC.Util.Trim(kind) == "" or GC.Util.Trim(token) == ""
        or not tonumber(part) or GC.Util.Trim(target) == "" then
        return false
    end
    return self:Send(table.concat({
        "A",
        tostring(GC.Constants.SCHEMA_VERSION),
        GC.Util.EscapeField(kind),
        GC.Util.EscapeField(token),
        tostring(part),
    }, "|"), "WHISPER", target)
end

function GC.Sync:ReceiveReliableAck(fields, sender)
    if tonumber(fields[2]) ~= GC.Constants.SCHEMA_VERSION then
        return false
    end
    local kind = fields[3]
    local token = fields[4]
    local part = tonumber(fields[5])
    local entry = self.reliableActive
    if not entry or entry.kind ~= kind or entry.token ~= token
        or GC.Util.NormalizeName(entry.target) ~= GC.Util.NormalizeName(sender)
        or not part or part < 1 or part > #entry.messages
        or entry.acknowledged[part] then
        return false
    end

    -- Trifft doch noch ein spaetes ACK fuer ein bereits aufgegebenes Paket ein,
    -- zaehlt es wieder als zugestellt - und verschwindet damit auch wieder aus
    -- der Fehlerbilanz. Ein Paket, das doch ankam, darf dort nicht stehen
    -- bleiben.
    if entry.failed[part] then
        entry.failed[part] = nil
        entry.failedCount = math.max(0, (entry.failedCount or 0) - 1)
        self.progressFailed = math.max(0, (tonumber(self.progressFailed) or 0) - 1)
    end
    entry.acknowledged[part] = true
    entry.acknowledgedCount = entry.acknowledgedCount + 1
    if entry.pending[part] then
        entry.pending[part] = nil
        entry.inFlight = math.max(0, entry.inFlight - 1)
    end
    if (entry.acknowledgedCount + (entry.failedCount or 0)) >= #entry.messages then
        self:FinishReliable((entry.failedCount or 0) == 0)
    else
        self:PumpReliable()
    end
    return true
end

function GC.Sync:BuildProfileMessage()
    local profile = GC.Profile:Get()
    local professions = profile.professions or {}
    local profession1 = professions[1] or {}
    local profession2 = professions[2] or {}
    local absence = profile.absence or {}
    local fields = {
        "P",
        tostring(GC.Constants.SCHEMA_VERSION),
        profile.classFile or "",
        profile.detectedSpecKey or "",
        profile.talentSignature or "",
        profile.raidSpecKey or "",
        profile.secondarySpecKey or "",
        profile.mainStatus or "MAIN",
        BoolField(profile.flex),
        BoolField(profile.confirmed),
        profession1.name or "",
        profession1.skillLevel and (profession1.skillLevel .. "/" .. (profession1.maxSkillLevel or 0)) or "",
        profession2.name or "",
        profession2.skillLevel and (profession2.skillLevel .. "/" .. (profession2.maxSkillLevel or 0)) or "",
        tostring(profile.updatedAt or GC.Util.Now()),
        absence.from or "",
        absence.to or "",
        absence.reason or "",
    }
    for index, value in ipairs(fields) do
        fields[index] = GC.Util.EscapeField(value)
    end
    return table.concat(fields, "|")
end

function GC.Sync:SendProfile()
    self.sendPending = false
    self:Send(self:BuildProfileMessage())
end

function GC.Sync:QueueProfile()
    if self.sendPending then
        return
    end
    self.sendPending = true
    C_Timer.After(1, function()
        self:SendProfile()
    end)
end

-- Auf Zuruf alles anstossen: Versionen und Profile erfragen, das eigene
-- Profil senden, das Gildenprofil nachfordern. Gedacht fuer den Fall, dass
-- jemand nicht auf den naechsten Login warten will.
function GC.Sync:RequestSync()
    local now = GC.Util.Now()
    if (now - (self.lastManualSyncAt or 0)) < MIN_MANUAL_SYNC_INTERVAL then
        return false, "Der Abgleich lief gerade eben schon."
    end
    self.lastManualSyncAt = now
    self.lastRequestAt = now
    self:WakeProgress()

    self:AnnounceVersion(true)
    self:QueueProfile()
    self:RequestGuildProfile()
    if GC.Workshop then
        GC.Workshop:RequestGuildData()
    end
    if GC.WarcraftLogs then
        GC.WarcraftLogs:RequestRecruitmentData()
    end
    return true, "Abgleich angefragt."
end

-- Antwort auf eine Anfrage. Gedrosselt, damit mehrere Logins kurz
-- hintereinander nicht jedes Mal das ganze Profil erneut durch die Gilde
-- schicken; wer neu dazukommt, hat es dann vom letzten Mal noch nicht, deshalb
-- ist das Fenster bewusst kurz gehalten.
function GC.Sync:ReplyWithProfile()
    local now = GC.Util.Now()
    if (now - (self.lastProfileReplyAt or 0)) < MIN_PROFILE_REPLY_INTERVAL then
        return false
    end
    self.lastProfileReplyAt = now
    self:QueueProfile()
    return true
end

-- Die fertige Nutzlast des Gildenprofils, noch nicht zerlegt. Getrennt vom
-- Zerlegen, damit sich ihre Groesse schon beim Speichern pruefen laesst - und
-- nicht erst der Empfaenger stumm entscheidet, dass es zu viel war.
function GC.Sync:BuildGuildProfilePayload()
    local guildData = GC.DB:GetGuild()
    local profile = guildData.profile
    local permissions = guildData.profilePermissions
    local templates = guildData.replyTemplates
    local memberCare = guildData.memberCare
    local roster = guildData.roster
    local inboxSound = guildData.inboxSound
    local fields = {
        "GP",
        tostring(profile.updatedAt or 0),
        profile.description or "",
        profile.raidTimes or "",
        profile.progress or "",
        profile.lootSystem or "",
        profile.discord or "",
        profile.contact or "",
        BoolField(permissions.configured),
        table.concat(SortedEnabledRanks(permissions.editorRanks), ","),
        templates.THANKS or "",
        templates.INFO or "",
        templates.DISCORD or "",
        tostring(memberCare.inactivityDays or 60),
        BoolField(memberCare.protectedRanksConfigured),
        table.concat(SortedEnabledRanks(memberCare.protectedRanks), ","),
        BoolField(memberCare.accessRanksConfigured),
        table.concat(SortedEnabledRanks(memberCare.accessRanks), ","),
        BoolField(roster.rankFilterConfigured),
        table.concat(SortedEnabledRanks(roster.activeRaiderRanks), ","),
        EncodeMemberCareDecisions(memberCare.decisions),
        EncodeEnchantRules(guildData.enchantRules),
        EncodeSpecEnchantRules(guildData.enchantSpecRules),
        EncodeWarcraftLogsSource(guildData.warcraftLogs),
        -- Die Content-Phase der Gilde. Sie entscheidet, welche Regeln des
        -- ausgelieferten Verzauberungs-Regelsatzes ueberhaupt schon gelten.
        profile.contentPhase or "",
        -- Welche Raenge den Bewerberton hoeren. Steht am Ende, damit aeltere
        -- Clients die Nutzlast weiter lesen koennen; sie spielen dann wie
        -- bisher nach ihrer eigenen Vorgabe.
        BoolField(inboxSound.ranksConfigured),
        table.concat(SortedEnabledRanks(inboxSound.ranks), ","),
    }
    for index, value in ipairs(fields) do
        fields[index] = GC.Util.EscapeField(value)
    end
    return table.concat(fields, "|")
end

function GC.Sync:GetGuildProfileMaxBytes()
    return GC.Constants.GUILD_PROFILE_MAX_CHUNKS * GC.Constants.GUILD_PROFILE_CHUNK_BYTES
end

-- Aktuelle Groesse und Obergrenze der Gildenprofil-Nutzlast. Die Oberflaeche
-- fragt das vor dem Speichern ab und sagt es dem Offizier, statt lokal Erfolg
-- zu melden und gildenweit nichts auszuliefern.
function GC.Sync:GetGuildProfileSize()
    local bytes = #self:BuildGuildProfilePayload()
    local maximum = self:GetGuildProfileMaxBytes()
    return bytes, maximum, bytes > maximum
end

-- Zerlegt die Nutzlast in sendbare Bloecke. Passt sie nicht mehr durch, wird
-- gar nicht erst gesendet: Ein halbes Profil kann der Empfaenger ohnehin nicht
-- zusammensetzen, und die zweite Rueckgabe sagt, wie viel zu viel es war.
function GC.Sync:BuildGuildProfileMessages()
    local payload = self:BuildGuildProfilePayload()
    local maximum = self:GetGuildProfileMaxBytes()
    if #payload > maximum then
        return {}, #payload, maximum
    end

    local chunks = {}
    local chunkSize = GC.Constants.GUILD_PROFILE_CHUNK_BYTES
    for offset = 1, #payload, chunkSize do
        chunks[#chunks + 1] = payload:sub(offset, offset + chunkSize - 1)
    end
    local token = tostring(GC.Util.Now()) .. tostring(math.random(1000, 9999))
    local messages = {}
    for index, chunk in ipairs(chunks) do
        messages[index] = table.concat({
            "G",
            tostring(GC.Constants.SCHEMA_VERSION),
            token,
            tostring(index),
            tostring(#chunks),
            chunk,
        }, "|")
    end
    -- Die Kennung wandert mit hinaus: Der bestaetigte Versand unten braucht
    -- sie, um die Rueckmeldungen den Teilen zuzuordnen.
    return messages, #payload, maximum, token
end

-- === Der bestaetigte Weg zu EINEM Spieler ==================================
--
-- Das Gildenprofil ging bisher ausschliesslich ueber den Gildenkanal, ohne
-- Rueckmeldung und ohne Wiederholung: fuenf Pakete raus, und niemand erfaehrt
-- je, ob sie angekommen sind. Faellt eines aus - der eingebaute Ratenbegrenzer
-- des Clients verwirft im Anmeldegetuemmel regelmaessig welche -, verwirft der
-- Empfaenger den ganzen Transfer, weil er ihn nicht zusammensetzen kann. Nach
-- aussen sieht das aus wie "die Rechte kommen nicht an", ohne jeden Hinweis
-- worauf.
--
-- Werkstatt und Warcraft Logs haben fuer genau dieses Problem laengst den
-- bestaetigten Fluestertransfer: jedes Teil wird quittiert, unquittierte
-- laufen mit wachsendem Abstand erneut an, und am Ende steht ein Erfolg oder
-- eine Zahl verlorener Teile. Das Gildenprofil war der letzte Transfer ohne
-- ihn - dabei ist es der einzige, bei dem ein Ausfall Rechte kostet.
function GC.Sync:SendGuildProfileTo(target, onComplete, onFailure)
    target = GC.Util.Trim(target)
    if target == "" then
        return false
    end
    local messages, _, _, token = self:BuildGuildProfileMessages()
    if #messages == 0 then
        return false
    end
    return self:QueueReliable(messages, target, "G", token, onComplete, onFailure)
end

-- Alle bekannten Addon-Nutzer der Gilde, die gerade online sind; der eigene
-- Charakter nie.
--
-- Gezaehlt wird je SPIELER, nicht je Tabelleneintrag. Derselbe Charakter steht
-- in addonUsers unter zwei Schluesseln (mit und ohne Realmanteil), und das
-- sind nicht immer zwei Verweise auf dieselbe Tabelle: Wer einmal mit und
-- einmal ohne Realm gemeldet wurde, hat dort zwei echte Eintraege. Ein
-- Vergleich auf Tabellengleichheit haette ihn hier doppelt geliefert - und
-- damit denselben Transfer zweimal losgeschickt.
function GC.Sync:HasCapability(entry, capability)
    local capabilities = type(entry) == "table" and GC.Util.Trim(entry.capabilities) or ""
    return ("," .. capabilities .. ","):find("," .. capability .. ",", 1, true) ~= nil
end

function GC.Sync:GetOnlinePeerNames()
    local ownKey = GC.Util.PlayerKey(GC:GetPlayerFullName())
    local names, seen = {}, {}
    -- Wer online ist, aber die Quittung noch nicht kennt. Er bekommt den
    -- Rundruf wie bisher; gezaehlt wird er trotzdem, damit die Oberflaeche
    -- "zwei von zwei bestaetigt, sechs weitere mit aelterer Fassung" sagen
    -- kann statt "zwei von acht" - was nach Fehlschlag aussaehe, obwohl die
    -- sechs schlicht nie gefragt wurden.
-- Erst sammeln, dann entscheiden. Wer beide Schritte in einer Schleife macht,
-- laesst die Tabellenreihenfolge entscheiden, WELCHER der beiden Eintraege
-- desselben Spielers zaehlt - und nur einer von beiden traegt womoeglich die
-- Faehigkeitsliste. Derselbe Spieler galt damit mal als quittierfaehig und mal
-- als veraltet, von einem Aufruf zum naechsten. Gilt eine Faehigkeit an EINEM
-- seiner Eintraege, gilt sie fuer ihn.
    local outdated = 0
    for _, entry in pairs(GC.DB:GetGuild().addonUsers or {}) do
        if type(entry) == "table" then
            local key = GC.Util.PlayerKey(entry.name)
            if key ~= "" and key ~= ownKey then
                local member = GC.Roster:GetMember(entry.name)
                if member and member.online then
                    local known = seen[key]
                    if not known then
                        known = { name = entry.name, capable = false }
                        seen[key] = known
                    end
                    if self:HasCapability(entry, "guildprofile2") then
                        known.capable = true
                    end
                end
            end
        end
    end
    for _, known in pairs(seen) do
        if known.capable then
            names[#names + 1] = known.name
        else
            outdated = outdated + 1
        end
    end
    table.sort(names)
    return names, outdated
end

-- Beide Wege auf einmal: der Rundruf wie bisher fuer alle, und zusaetzlich der
-- bestaetigte Transfer an jeden, von dem dieser Client weiss, dass er gerade
-- online ist und das Addon faehrt. Der Rundruf erreicht auch die, die dieser
-- Client noch nicht kennt; der bestaetigte Weg sagt, ob es geklappt hat.
function GC.Sync:PushGuildProfile(onFinished)
    local broadcast = self:SendGuildProfile(true)
    local targets, outdated = self:GetOnlinePeerNames()
    local open, ok, lost = #targets, 0, 0
    if open == 0 then
        if type(onFinished) == "function" then
            onFinished(broadcast, 0, 0, 0, outdated)
        end
        return broadcast, 0, outdated
    end
    local function Note(success)
        if success then
            ok = ok + 1
        else
            lost = lost + 1
        end
        open = open - 1
        if open <= 0 and type(onFinished) == "function" then
            onFinished(broadcast, #targets, ok, lost, outdated)
        end
    end
    for _, name in ipairs(targets) do
        local queued = self:SendGuildProfileTo(name, function()
            Note(true)
        end, function()
            Note(false)
        end)
        if not queued then
            Note(false)
        end
    end
    return broadcast, #targets, outdated
end

function GC.Sync:SendGuildProfile(force)
    local guildKey = GC:GetGuildKey()
    self.guildProfileSendPending = false
    force = force == true or self.guildProfileForceSend
    self.guildProfileForceSend = false
    if not force and not GC.Roster:CanEditGuildProfile() then
        return false
    end
    local messages, bytes, maximum = self:BuildGuildProfileMessages()
    if #messages == 0 then
        -- Lieber laut scheitern als leise: Vorher sah der Offizier "Gespeichert",
        -- waehrend bei allen anderen nichts ankam.
        GC:Print("|cffff5555Das Gildenprofil ist zu gross zum Synchronisieren|r ("
            .. bytes .. " von höchstens " .. maximum .. " Zeichen). "
            .. "Bitte Texte, Antwortvorlagen oder Verzauberungsregeln kürzen.")
        GC:FireCallback("GUILD_PROFILE_TOO_LARGE", bytes, maximum)
        return false
    end
    local index = 1
    local retries = 0
    -- Der Versand taktet sich selbst und laeuft nicht ueber SendBulk; damit der
    -- Fortschrittsbalken ihn trotzdem kennt, wird er als offene Arbeit gebucht
    -- und auf jedem Ausgang wieder abgemeldet.
    local outstanding = #messages
    self:NoteSerialPending(outstanding)
    local function ReleaseSerial(count)
        count = math.min(outstanding, math.max(0, count or outstanding))
        outstanding = outstanding - count
        GC.Sync:NoteSerialPending(-count)
    end
    local function SendNext()
        if GC:GetGuildKey() ~= guildKey then
            ReleaseSerial()
            return
        end
        local message = messages[index]
        if not message then
            ReleaseSerial()
            return
        end
        local sent = self:Send(message)
        if sent then
            index = index + 1
            retries = 0
            ReleaseSerial(1)
        else
            retries = retries + 1
            if retries >= 5 then
                -- Auch der abgebrochene Versand war bisher unsichtbar.
                GC:Print("|cffff5555Das Gildenprofil konnte nicht vollständig gesendet werden|r ("
                    .. (index - 1) .. " von " .. #messages .. " Teilen). "
                    .. "Bitte im Gildenprofil erneut speichern.")
                self.progressFailed = (tonumber(self.progressFailed) or 0) + outstanding
                ReleaseSerial()
                return
            end
        end
        if messages[index] then
            C_Timer.After(sent and 0.45 or 1.25, SendNext)
        else
            ReleaseSerial()
        end
    end
    SendNext()
    return true
end

function GC.Sync:QueueGuildProfile(force)
    self.guildProfileForceSend = self.guildProfileForceSend or force == true
    if self.guildProfileSendPending then
        return
    end
    self.guildProfileSendPending = true
    C_Timer.After(0.6, function()
        self:SendGuildProfile()
    end)
end

function GC.Sync:ReceiveGuildProfileChunk(message, sender, distribution)
    -- Der Abgleich ist rangunabhaengig: die neuesten Daten gewinnen. Jeder
    -- Client haelt eine Kopie des Gildenprofils, also darf sie auch von einem
    -- einfachen Mitglied kommen - etwa wenn ein Offizier frisch auf einem
    -- anderen Rechner einsteigt und nur ein Mitglied gerade online ist. Vor dem
    -- Ueberschreiben schuetzt weiter unten der Zeitstempelvergleich: ein
    -- aelterer Stand wird verworfen, nur ein neuerer uebernommen. Gesperrt bleibt
    -- lediglich, wer nachweislich kein Gildenmitglied ist.
    if #GC.Roster.members > 0 and not GC.Roster:IsGuildMember(sender)
        and not GC.Roster:CanEditGuildProfile(sender) then
        return
    end
    local schemaText, token, indexText, totalText, chunk =
        message:match("^G|([^|]+)|([^|]+)|([^|]+)|([^|]+)|(.*)$")
    local schemaVersion = tonumber(schemaText)
    local index = tonumber(indexText)
    local total = tonumber(totalText)
    if schemaVersion ~= GC.Constants.SCHEMA_VERSION
        or not index or not total or index < 1 or index > total
        or total > GC.Constants.GUILD_PROFILE_MAX_CHUNKS
        or #token > 40 or #chunk > GC.Constants.GUILD_PROFILE_CHUNK_BYTES then
        return
    end

    -- Quittiert wird sofort und je Teil, noch bevor irgendetwas uebernommen
    -- wird: Die Bestaetigung sagt "angekommen", nicht "gefiel mir". Ein Teil,
    -- das erst nach der Zeitstempelpruefung quittiert wuerde, liefe beim
    -- Absender ewig als verloren - obwohl der Empfaenger es hat und bloss
    -- einen neueren Stand behaelt.
    if distribution == "WHISPER" then
        self:SendReliableAck("G", token, index, sender)
    end

    PruneIncoming(self.guildProfileIncoming)
    local incomingKey = GC.Util.NormalizeName(sender) .. "|" .. token
    local incoming = self.guildProfileIncoming[incomingKey]
    if not incoming or incoming.total ~= total then
        incoming = {
            total = total,
            chunks = {},
            receivedAt = GC.Util.Now(),
        }
        self.guildProfileIncoming[incomingKey] = incoming
    end
    incoming.chunks[index] = chunk

    local payloadParts = {}
    for chunkIndex = 1, total do
        if incoming.chunks[chunkIndex] == nil then
            return
        end
        payloadParts[chunkIndex] = incoming.chunks[chunkIndex]
    end
    self.guildProfileIncoming[incomingKey] = nil

    local payload = table.concat(payloadParts)
    local fields = GC.Util.SplitFields(payload)
    if fields[1] ~= "GP" then
        return
    end
    local updatedAt = tonumber(fields[2]) or 0
    local guildData = GC.DB:GetGuild()
    local now = GC.Util.Now()

    -- Eine Uhr, die weit in der Zukunft steht, hat sonst das letzte Wort auf
    -- Dauer: Ihr Zeitstempel ist groesser als jeder echte, und keine spaetere
    -- Aenderung kaeme je durch. Solche Staende werden weder uebernommen noch
    -- verteidigt.
    if updatedAt > (now + MAX_CLOCK_SKEW) then
        return
    end
    local storedAt = tonumber(guildData.profile.updatedAt) or 0
    if storedAt > (now + MAX_CLOCK_SKEW) then
        storedAt = 0
    end

    if updatedAt < storedAt then
        return
    end
    -- Gleicher Zeitstempel, zwei Fassungen: Bisher gewann schlicht die zuletzt
    -- eingetroffene, und damit auf jedem Rechner eine andere. Entschieden wird
    -- deshalb ueber die Nutzlast selbst - dieselbe Regel fuehrt ueberall zum
    -- selben Ergebnis, ohne dass ein Feld dafuer durch die Leitung muss.
    if updatedAt == storedAt and payload <= self:BuildGuildProfilePayload() then
        return
    end

    guildData.profile.description = fields[3] or ""
    guildData.profile.raidTimes = fields[4] or ""
    guildData.profile.progress = fields[5] or ""
    guildData.profile.lootSystem = fields[6] or ""
    guildData.profile.discord = fields[7] or ""
    guildData.profile.contact = fields[8] or ""
    guildData.profile.updatedAt = updatedAt
    guildData.profilePermissions.configured = fields[9] == "1"
    guildData.profilePermissions.editorRanks = DecodeEnabledRanks(fields[10])
    guildData.replyTemplates.THANKS = fields[11] or ""
    guildData.replyTemplates.INFO = fields[12] or ""
    guildData.replyTemplates.DISCORD = fields[13] or ""
    guildData.memberCare.inactivityDays = math.max(7, math.min(365, tonumber(fields[14]) or 60))
    guildData.memberCare.protectedRanksConfigured = fields[15] == "1"
    guildData.memberCare.protectedRanks = DecodeEnabledRanks(fields[16])
    guildData.memberCare.accessRanksConfigured = fields[17] == "1"
    guildData.memberCare.accessRanks = DecodeEnabledRanks(fields[18])
    guildData.roster.rankFilterConfigured = fields[19] == "1"
    guildData.roster.activeRaiderRanks = DecodeEnabledRanks(fields[20])
    -- Ältere Absender senden das Feld nicht; dann bleiben die eigenen
    -- Entscheidungen unangetastet statt gelöscht zu werden.
    if fields[21] ~= nil then
        guildData.memberCare.decisions = DecodeMemberCareDecisions(fields[21])
    end

    -- Drei Felder aendern die Bewertungsgrundlage: die allgemeinen Regeln, die
    -- Spec-Regeln und die Content-Phase. Jedes stiess bisher einen EIGENEN
    -- Durchlauf von ReapplyEnchantRules an - also dreimal dieselbe vollstaendige
    -- Neubewertung aller gespeicherten Ausruestungspruefungen, obwohl nach dem
    -- dritten Durchlauf nur das Ergebnis des dritten zaehlt.
    --
    -- Bei 500 gespeicherten Pruefungen waren das gemessene 932 ms Standbild je
    -- empfangenem Gildenprofil, und zwar bei JEDEM Mitglied - ausgeloest schon
    -- davon, dass ein Offizier ein einzelnes Rangkaestchen umlegt. Neu bewertet
    -- wird deshalb genau einmal, ganz am Ende.
    local rulesChanged = false
    if fields[22] ~= nil then
        guildData.enchantRules = DecodeEnchantRules(fields[22])
        rulesChanged = true
    end
    -- Fehlt das Feld, sendet der Absender eine aeltere Version. Dann bleiben
    -- die eigenen Spec-Regeln stehen, statt geleert zu werden.
    if fields[23] ~= nil then
        guildData.enchantSpecRules = DecodeSpecEnchantRules(fields[23])
        rulesChanged = true
    end
    -- Die Warcraft-Logs-Gildenquelle. Ein leeres oder fehlendes Feld laesst die
    -- eigene Quelle stehen: wer sie noch nicht gesetzt hat, soll sie einem
    -- anderen nicht loeschen.
    local wclSource = fields[24] ~= nil and DecodeWarcraftLogsSource(fields[24]) or nil
    if wclSource and GC.WarcraftLogs then
        GC.WarcraftLogs:ApplySource(wclSource)
    end
    -- Die Content-Phase. Nur bekannte Phasen werden uebernommen; ein leeres
    -- oder fehlendes Feld laesst die eigene Einstellung stehen, damit ein
    -- aelterer Client sie nicht zurueckdreht.
    local phase = fields[25]
    if type(phase) == "string" and GC.ContentPhaseByKey[phase] then
        if guildData.profile.contentPhase ~= phase then
            rulesChanged = true
        end
        guildData.profile.contentPhase = phase
    end
    -- Der eine Durchlauf fuer alle drei Aenderungen.
    if rulesChanged and GC.GearAudit then
        GC.GearAudit:ReapplyEnchantRules()
    end
    -- Die Rangfreigabe fuer den Bewerberton. Fehlt das Feld, sendet ein
    -- aelterer Client; dann bleibt die eigene Freigabe stehen, statt auf
    -- "niemand hoert etwas" zurueckzufallen.
    if fields[26] ~= nil then
        guildData.inboxSound.ranksConfigured = fields[26] == "1"
        guildData.inboxSound.ranks = DecodeEnabledRanks(fields[27])
    end
    GC:FireCallback("GUILD_PROFILE_UPDATED", sender)
    GC:FireCallback("SETTINGS_UPDATED")
end

function GC.Sync:RequestGuildProfile()
    self:Send("GQ|" .. tostring(GC.Constants.SCHEMA_VERSION))
end

-- Antwort auf eine Gildenprofil-Anfrage. Offiziere schicken ihren Stand immer.
-- Einfache Mitglieder geben ihre zwischengespeicherte Kopie nur weiter, wenn
-- sie ueberhaupt eine gepflegte Fassung haben - so bekommt ein frisch
-- eingestiegener Client die Infos auch dann, wenn gerade kein Offizier online
-- ist. Der Zeitstempelvergleich beim Empfaenger sorgt dafuer, dass niemand
-- einen neueren Stand mit einer alten Kopie ueberschreibt.
function GC.Sync:ReplyToGuildProfileRequest(requester)
    local canEdit = GC.Roster:CanEditGuildProfile()
    local hasProfile = (tonumber(GC.DB:GetGuild().profile.updatedAt) or 0) > 0
    if not canEdit and not hasProfile then
        return false
    end
    local now = GC.Util.Now()
    if (now - (self.lastGuildProfileReplyAt or 0)) < MIN_PROFILE_REPLY_INTERVAL then
        return false
    end

    -- Die Wahl: Nicht jeder schickt sein Gildenprofil. Bei 250 Online waren
    -- das 22 Pakete mal 250 - fuer eine Nutzlast, die bei allen dieselbe ist.
    if not self:IsElectedResponder(requester) then
        return false
    end
    self.lastGuildProfileReplyAt = now
    if not C_Timer or type(C_Timer.After) ~= "function" then
        self:SendGuildProfile(true)
        return true
    end

    -- Und die Stille: Die Streuzeit ist laenger als der erste Block einer
    -- fremden Antwort braucht. Wer in dieser Zeit ein "G|"-Paket sieht, weiss,
    -- dass ein anderer Gewaehlter schon liefert, und schweigt.
    local scheduledAt = now
    C_Timer.After(1 + math.random() * 3, function()
        if GC.Sync:PeerAnsweredSince("GUILDPROFILE", scheduledAt) then
            -- Ein anderer war schneller. Die Drossel wird dabei ausdruecklich
            -- zurueckgenommen: Es wurde nichts gesendet, also darf die naechste
            -- Anfrage wieder beantwortet werden.
            GC.Sync.lastGuildProfileReplyAt = 0
            return
        end
        GC.Sync:SendGuildProfile(true)
    end)
    return true
end

-- Direkt nach dem Login ist der Gildenroster oft noch leer; dann steht der
-- eigene Rang noch nicht fest. Ein paar Versuche warten darauf, damit ein
-- Offizier nicht faelschlich als einfaches Mitglied startet. Anschliessend wird
-- immer der aktuellste Stand erfragt (Annahme regelt der Zeitstempel), und wer
-- selbst pflegen darf, schickt seinen Stand zusaetzlich aktiv in die Gilde.
function GC.Sync:PrimeGuildProfileSync(attempt)
    attempt = tonumber(attempt) or 1
    if #GC.Roster.members == 0 and attempt < 5 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(2, function()
            GC.Sync:PrimeGuildProfileSync(attempt + 1)
        end)
        return
    end
    self:RequestGuildProfile()
    if GC.Roster:CanEditGuildProfile() then
        self:QueueGuildProfile()
    end
end

function GC.Sync:ReceiveProfile(fields, sender)
    local schemaVersion = tonumber(fields[2]) or 0
    local classFile = fields[3]
    local detectedSpecKey = fields[4] ~= "" and fields[4] or nil
    local raidSpecKey = fields[6] ~= "" and fields[6] or nil
    local secondarySpecKey
    local statusIndex = 7
    if schemaVersion >= 3 then
        secondarySpecKey = fields[7] ~= "" and fields[7] or nil
        statusIndex = 8
    end
    if not GC.Classes[classFile] then
        return
    end
    if detectedSpecKey and (not GC.SpecByKey[detectedSpecKey] or GC.SpecByKey[detectedSpecKey].classFile ~= classFile) then
        return
    end
    if raidSpecKey and (not GC.SpecByKey[raidSpecKey] or GC.SpecByKey[raidSpecKey].classFile ~= classFile) then
        return
    end
    if secondarySpecKey and (not GC.SpecByKey[secondarySpecKey] or GC.SpecByKey[secondarySpecKey].classFile ~= classFile) then
        return
    end
    if secondarySpecKey == raidSpecKey then
        secondarySpecKey = nil
    end

    local updatedAtIndex = statusIndex + 3
    local professions = {}
    if schemaVersion >= 4 then
        local function ReadSyncedProfession(name, skillText)
            if name == "" then
                return nil
            end
            local skillLevel, maxSkillLevel = tostring(skillText or ""):match("^(%d+)/(%d+)$")
            return {
                name = name,
                skillLevel = tonumber(skillLevel) or 0,
                maxSkillLevel = tonumber(maxSkillLevel) or 0,
            }
        end
        professions[1] = ReadSyncedProfession(fields[statusIndex + 3], fields[statusIndex + 4])
        professions[2] = ReadSyncedProfession(fields[statusIndex + 5], fields[statusIndex + 6])
        updatedAtIndex = statusIndex + 7
    end

    local profile = {
        fullName = sender,
        classFile = classFile,
        detectedSpecKey = detectedSpecKey,
        talentSignature = fields[5],
        raidSpecKey = raidSpecKey,
        secondarySpecKey = secondarySpecKey,
        mainStatus = fields[statusIndex] == "ALT" and "ALT" or "MAIN",
        flex = fields[statusIndex + 1] == "1",
        confirmed = fields[statusIndex + 2] == "1",
        professions = professions,
        updatedAt = tonumber(fields[updatedAtIndex]) or GC.Util.Now(),
        receivedAt = GC.Util.Now(),
    }
    if schemaVersion >= 6 then
        profile.absence = {
            from = fields[updatedAtIndex + 1] or "",
            to = fields[updatedAtIndex + 2] or "",
            reason = fields[updatedAtIndex + 3] or "",
        }
    else
        profile.absence = {
            from = "",
            to = "",
            reason = "",
        }
    end
    local key = GC.Util.NormalizeName(sender)
    local shortKey = GC.Util.NormalizeName(GC.Util.PlayerIdentityName(sender))
    local profiles = GC.DB:GetGuild().remoteProfiles

    -- Ein aelterer Stand darf einen neueren nicht ueberschreiben. Pakete
    -- desselben Absenders koennen sich ueberholen - eine Antwort auf eine
    -- Versionsanfrage und eine gerade gespeicherte Aenderung laufen parallel -,
    -- und dann gewann bisher schlicht das zuletzt eingetroffene.
    local stored = profiles[key] or profiles[shortKey]
    if stored and (tonumber(stored.updatedAt) or 0) > (tonumber(profile.updatedAt) or 0) then
        return
    end
    profiles[key] = profile
    profiles[shortKey] = profile
    GC:FireCallback("ROSTER_UPDATED")
end

function GC.Sync:BuildVersionMessage(requestReply)
    local fields = {
        "V",
        tostring(GC.Constants.SCHEMA_VERSION),
        GC.Constants.VERSION,
        table.concat(GC.Capabilities, ","),
        BoolField(requestReply),
        -- Feld 6: anonymes Account-Kennzeichen. Damit lassen sich die
        -- Charaktere eines Spielers zusammenfassen - WoW selbst verraet das
        -- nie. Aeltere Clients ignorieren das Feld schlicht.
        GC.DB:GetAccountTag(),
    }
    for index, value in ipairs(fields) do
        fields[index] = GC.Util.EscapeField(value)
    end
    return table.concat(fields, "|")
end

function GC.Sync:AnnounceVersion(requestReply, minimumInterval, distribution)
    minimumInterval = tonumber(minimumInterval) or 0
    local now = GC.Util.Now()
    if minimumInterval > 0 and (now - (self.lastAnnounceAt or 0)) < minimumInterval then
        return false
    end
    if not self:Send(self:BuildVersionMessage(requestReply), distribution) then
        return false
    end
    self.lastAnnounceAt = now
    return true
end

-- Der Versionsprüfer (/gcpf ver) fragt gezielt an: in der Gilde über den
-- Gildenkanal, in der Gruppe über RAID/PARTY - dort erreichen die Antworten
-- auch Mitglieder fremder Gilden.
function GC.Sync:RequestVersionCheck(mode)
    if mode == "GROUP" then
        local channel = self:GroupChannel()
        if not channel then
            return false
        end
        return self:Send(self:BuildVersionMessage(true), channel)
    end
    return self:AnnounceVersion(true, 5)
end

-- Frische Antworten der laufenden Sitzung, auch von Gruppenmitgliedern
-- fremder Gilden. Der Gildenbestand (addonUsers) bleibt der Langzeitspeicher.
-- Antworten der laufenden Sitzung. Die Liste ist rein lokal, wuchs aber
-- unbegrenzt: in einer Gilde mit 500 Mitgliedern ueber einen Abend um 500
-- Eintraege, die nach dem Versionspruefer niemand mehr liest. Aufgeraeumt wird
-- gesammelt, sobald sie zu gross wird - eine Frist je Eintrag waere teurer als
-- der Eintrag selbst.
local MAX_VERSION_REPLIES = 400
local VERSION_REPLY_TTL = 30 * 60

local function PruneVersionReplies(replies)
    local count = 0
    for _ in pairs(replies) do
        count = count + 1
    end
    if count <= MAX_VERSION_REPLIES then
        return
    end
    local cutoff = GC.Util.Now() - VERSION_REPLY_TTL
    for key, reply in pairs(replies) do
        if (tonumber(reply.at) or 0) < cutoff then
            replies[key] = nil
        end
    end
end

function GC.Sync:NoteVersionReply(sender, version)
    self.versionReplies = self.versionReplies or {}
    PruneVersionReplies(self.versionReplies)
    self.versionReplies[GC.Util.NormalizeName(GC.Util.PlayerIdentityName(sender))] = {
        version = GC.Util.Trim(version),
        at = GC.Util.Now(),
    }
    GC:FireCallback("VERSION_REPLIES_UPDATED")
end

function GC.Sync:GetKnownVersion(name, since)
    local key = GC.Util.NormalizeName(GC.Util.PlayerIdentityName(name))
    local reply = self.versionReplies and self.versionReplies[key]
    if reply and reply.version ~= "" and (not since or reply.at >= since) then
        return reply.version, true
    end
    local users = GC.DB:GetGuild().addonUsers or {}
    local entry = users[key] or users[GC.Util.NormalizeName(name)]
    if entry and GC.Util.Trim(entry.version) ~= "" then
        return entry.version, false
    end
    return nil, false
end

-- === Hinweis auf eine neuere Fassung ========================================
--
-- WoW laesst kein Addon ins Netz. "Gibt es etwas Neueres?" kann deshalb nur
-- die Gilde beantworten - und sie tut es laengst, ohne dass eine einzige
-- Nachricht dazukommt: Jede Versionsmeldung traegt in Feld 3 die Addon-Version
-- ihres Absenders. Ist eine davon hoeher als die eigene, ist die neue Fassung
-- draussen. Genauso macht es Details!, und aus demselben Grund.
--
-- Verglichen wird zahlenweise, nicht als Text: Als Zeichenkette stuende
-- "0.9.9" hinter "0.9.10", und genau dieser Sprung steht hier staendig an.
--
-- Was bewusst offen bleibt: Ein manipulierter Client kann eine Fassung melden,
-- die es nicht gibt. Der Schaden waere eine Zeile im Chat, die ins Leere
-- zeigt; der Preis einer Absicherung ueber zwei unabhaengige Melder waere,
-- dass der Erste mit der neuen Fassung nie einen zweiten bekommt - niemand
-- erfuehre je von einer Neuerung. Verlangt wird deshalb nur die genaue Form
-- "Zahl.Zahl.Zahl"; alles andere wird stumm verworfen.
local function ParseVersion(value)
    local major, minor, patch = tostring(value or ""):match("^%s*(%d+)%.(%d+)%.(%d+)%s*$")
    if not major then
        return nil
    end
    return tonumber(major), tonumber(minor), tonumber(patch)
end

function GC.Sync:IsNewerVersion(candidate, reference)
    local leftMajor, leftMinor, leftPatch = ParseVersion(candidate)
    local rightMajor, rightMinor, rightPatch = ParseVersion(reference)
    if not leftMajor or not rightMajor then
        return false
    end
    if leftMajor ~= rightMajor then
        return leftMajor > rightMajor
    end
    if leftMinor ~= rightMinor then
        return leftMinor > rightMinor
    end
    return leftPatch > rightPatch
end

-- Gemeldet wird einmal je Fassung und Sitzung. Wer nicht sofort aktualisieren
-- will, soll nicht bei jeder Anmeldung eines Gildenmitglieds erneut daran
-- erinnert werden; ein noch hoeherer Stand meldet sich dagegen noch einmal.
function GC.Sync:NoteSeenVersion(version)
    version = GC.Util.Trim(version)
    if not self:IsNewerVersion(version, self.newestVersion or GC.Constants.VERSION) then
        return false
    end
    self.newestVersion = version
    GC:Print(GC.LFormat("Version {new} ist verfügbar – du hast {own}."
        .. " Aktualisieren über die CurseForge-App oder den Guild-Copilot-Installer.",
        { new = version, own = GC.Constants.VERSION }))
    GC:FireCallback("UPDATE_AVAILABLE", version)
    return true
end

-- Beim Anmelden steht die Antwort oft schon in der Datenbank: Wer gestern mit
-- der neuen Fassung online war, ist dort vermerkt, auch wenn er heute fehlt.
-- Ohne diesen Blick hinge der Hinweis daran, dass ausgerechnet jetzt jemand
-- Aktualisierter online ist.
function GC.Sync:CheckKnownVersions()
    local newest = nil
    for _, entry in pairs(GC.DB:GetGuild().addonUsers or {}) do
        local version = GC.Util.Trim(entry and entry.version)
        if self:IsNewerVersion(version, newest or GC.Constants.VERSION) then
            newest = version
        end
    end
    if not newest then
        return false
    end
    return self:NoteSeenVersion(newest)
end

-- Die verfuegbare neuere Fassung oder nil - fuer Kopfzeile und Versionspruefer.
function GC.Sync:GetAvailableUpdate()
    if self:IsNewerVersion(self.newestVersion, GC.Constants.VERSION) then
        return self.newestVersion
    end
    return nil
end

function GC.Sync:NoteAddonUser(sender, info)
    if GC.Util.Trim(sender) == "" then
        return false
    end
    info = info or {}

    local guildData = GC.DB:GetGuild()
    local key = GC.Util.NormalizeName(sender)
    local shortKey = GC.Util.NormalizeName(GC.Util.PlayerIdentityName(sender))
    local entry = guildData.addonUsers[key] or guildData.addonUsers[shortKey]
    local changed = entry == nil
    entry = entry or {}

    local schemaVersion = tonumber(info.schemaVersion)
    if schemaVersion and entry.schemaVersion ~= schemaVersion then
        entry.schemaVersion = schemaVersion
        changed = true
    end
    local version = GC.Util.Trim(info.version)
    if version ~= "" and entry.version ~= version then
        entry.version = version
        changed = true
    end
    local capabilities = GC.Util.Trim(info.capabilities)
    if capabilities ~= "" and entry.capabilities ~= capabilities then
        entry.capabilities = capabilities
        changed = true
    end
    local accountTag = GC.Util.Trim(info.accountTag)
    if accountTag ~= "" and entry.accountTag ~= accountTag then
        entry.accountTag = accountTag
        changed = true
    end
    if info.source == "HANDSHAKE" and not entry.handshake then
        entry.handshake = true
        changed = true
    end

    entry.name = sender
    entry.seenAt = GC.Util.Now()
    -- Wann zuletzt ueberhaupt ein anderer Client etwas geschickt hat. Der
    -- Fortschrittsbalken haengt daran, ob er "vollstaendig" sagen darf: Wer
    -- allein online ist, hat nichts angekuendigt bekommen und kann deshalb auch
    -- nichts vermissen - "nichts offen" ist dann die ganze Wahrheit.
    self.lastPeerAt = entry.seenAt
    guildData.addonUsers[key] = entry
    guildData.addonUsers[shortKey] = entry
    if changed then
        GC:FireCallback("ADDON_USERS_UPDATED")
    end
    return changed
end

function GC.Sync:ReceiveVersion(fields, sender, distribution)
    local schemaVersion = tonumber(fields[2])
    if not schemaVersion then
        return
    end
    distribution = distribution or "GUILD"
    self:NoteVersionReply(sender, fields[3])
    -- Auch aus der Gruppe: Wer in einer fremden Gilde die neue Fassung faehrt,
    -- weiss davon genauso zuverlaessig wie ein Gildenmitglied.
    self:NoteSeenVersion(fields[3])
    -- In den Gildenbestand gehoeren nur Gildenmitglieder. Ueber RAID/PARTY
    -- melden sich auch Gruppenmitglieder fremder Gilden - deren Antworten
    -- leben nur im Sitzungsspeicher des Versionspruefers.
    if distribution == "GUILD" or GC.Roster:IsGuildMember(sender) then
        self:NoteAddonUser(sender, {
            schemaVersion = schemaVersion,
            version = fields[3],
            capabilities = fields[4],
            accountTag = fields[6],
            source = "HANDSHAKE",
        })
    end

    -- Nur auf ausdrückliche Anfragen antworten, niemals auf eine Antwort -
    -- und zwar auf demselben Kanal, auf dem gefragt wurde: Die Antwort in
    -- die eigene Gilde erreicht einen gildenfremden Frager nie.
    if fields[5] == "1" then
        C_Timer.After(0.5 + math.random() * 4, function()
            self:AnnounceVersion(false, MIN_REPLY_INTERVAL, distribution)
        end)
        -- Das eigene Profil gleich mitschicken. Ohne diese Antwort erfaehrt ein
        -- Client nur von denen etwas, die sich nach ihm einloggen oder ihr
        -- Profil aendern: Wer zuerst da war, hat laengst in einen leeren Raum
        -- gesendet.
        --
        -- Die Streuung haengt an der Zahl der bekannten Nutzer. Bei zweien
        -- muss niemand zehn Sekunden warten; bei zwanzig darf nicht alles
        -- gleichzeitig losgehen, sonst verschluckt der Addon-Kanal Nachrichten.
        local others = math.max(0, (self:GetAddonUserStats().known or 1) - 1)
        local spread = math.min(9, math.max(1, others))
        C_Timer.After(0.5 + math.random() * spread, function()
            self:ReplyWithProfile()
        end)

        -- Die Ausruestungsantwort ist der teuerste Teil des Handschlags: bis
        -- zu zehn Bloecke, und bis 0.9.96 schickte sie JEDER. Bei 250 Online
        -- waren das rund 750 Pakete je fremdem Login - fuer Daten, die der
        -- Empfaenger gar nicht alle annehmen kann (er verarbeitet hoechstens
        -- EQUIPMENT_MAX_INCOMING Uebertragungen gleichzeitig).
        --
        -- Geantwortet wird deshalb nur noch von einer gewaehlten Teilmenge,
        -- hier mit deutlich mehr Plaetzen als bei den uebrigen Anfragen: Wer
        -- neu dazukommt, soll seine Uebersicht zuegig fuellen. Weil die Wahl
        -- am Anfragenden haengt, ist es bei jedem Login eine andere Teilmenge -
        -- nach ein paar Logins kennt ein neuer Client trotzdem die halbe Gilde,
        -- nur eben verteilt statt auf einen Schlag.
        --
        -- Der eigene Stand geht davon unabhaengig ohnehin bei jedem Login
        -- einmal raus (AuditSelf -> QueueEquipmentSnapshot); hier wird also
        -- nichts endgueltig verpasst, sondern nur entzerrt.
        if GC.GearAudit and self:IsElectedResponder(sender, 10) then
            GC.GearAudit:ReplyWithEquipmentSnapshot()
        end
    end
end

function GC.Sync:GetAddonUser(name)
    local addonUsers = GC.DB:GetGuild().addonUsers
    return addonUsers[GC.Util.NormalizeName(name)]
        or addonUsers[GC.Util.NormalizeName(GC.Util.PlayerIdentityName(name))]
end

function GC.Sync:GetAddonUserStats()
    local stats = {
        known = 1,
        compatible = 1,
        outdated = 0,
        ahead = 0,
        -- "known" zaehlt Charaktere, "players" Accounts: wer mit Main und zwei
        -- Twinks unterwegs war, ist ein Spieler und nicht drei. Charaktere ohne
        -- gemeldetes Kennzeichen zaehlen einzeln - lieber eine Zahl zu hoch als
        -- fremde Spieler faelschlich zusammenlegen.
        players = 1,
        outdatedNames = {},
    }
    local ownTag = GC.DB:GetAccountTag()
    local countedTags = {}

    -- Ausgetretene Mitglieder erst ausblenden, wenn das Roster gelesen ist;
    -- direkt nach dem Login ist es noch leer.
    local rosterReady = #GC.Roster.members > 0
    local seen = {}
    for _, entry in pairs(GC.DB:GetGuild().addonUsers or {}) do
        if not seen[entry] and (not rosterReady or GC.Roster:IsGuildMember(entry.name)) then
            seen[entry] = true
            stats.known = stats.known + 1
            local accountTag = GC.Util.Trim(entry.accountTag)
            if accountTag == "" then
                stats.players = stats.players + 1
            elseif accountTag ~= ownTag and not countedTags[accountTag] then
                countedTags[accountTag] = true
                stats.players = stats.players + 1
            end
            local schemaVersion = tonumber(entry.schemaVersion) or 0
            if schemaVersion == GC.Constants.SCHEMA_VERSION then
                stats.compatible = stats.compatible + 1
            elseif schemaVersion > GC.Constants.SCHEMA_VERSION then
                stats.ahead = stats.ahead + 1
                stats.outdatedNames[#stats.outdatedNames + 1] = GC.Util.PlayerIdentityName(entry.name)
            else
                stats.outdated = stats.outdated + 1
                stats.outdatedNames[#stats.outdatedNames + 1] = GC.Util.PlayerIdentityName(entry.name)
            end
        end
    end
    table.sort(stats.outdatedNames)
    return stats
end

-- Der richtige Kanal fuer die aktuelle Gruppe. Sitzungen lassen sich auch in
-- einer normalen Party starten, Start, Ende und Auswertung gingen aber fest
-- ueber RAID - in einer Party erreichte das niemanden. Der Empfaenger nimmt
-- beide Kanaele schon immer an, nur gesendet wurde falsch.
function GC.Sync:GroupChannel()
    if IsInRaid and IsInRaid() then
        return "RAID"
    end
    if IsInGroup and IsInGroup() then
        return "PARTY"
    end
    return nil
end

function GC.Sync:AnnounceSessionStart(session)
    local channel = self:GroupChannel()
    if not channel then
        return false
    end
    return self:Send(table.concat({
        "RS",
        tostring(GC.Constants.SCHEMA_VERSION),
        session.id,
        tostring(session.startedAt),
        GC.Util.EscapeField(session.zone or ""),
    }, "|"), channel)
end

-- Der Herzschlag trägt alles, was ein Nachzügler zum Mitschreiben braucht -
-- er ist damit zugleich ein nachgereichter Startruf. Er geht nur in die eigene
-- Gruppe und nur, solange eine Sitzung läuft; Näheres in RaidMonitor.lua.
function GC.Sync:AnnounceSessionHeartbeat(session)
    local channel = self:GroupChannel()
    if not channel or not session then
        return false
    end
    return self:Send(table.concat({
        "RH",
        tostring(GC.Constants.SCHEMA_VERSION),
        session.id,
        tostring(session.startedAt),
        GC.Util.EscapeField(session.zone or ""),
        GC.Util.EscapeField(session.startedBy or ""),
    }, "|"), channel)
end

function GC.Sync:AnnounceSessionEnd(summary)
    local channel = self:GroupChannel()
    if not channel then
        return false
    end
    return self:Send(table.concat({
        "RE",
        tostring(GC.Constants.SCHEMA_VERSION),
        summary.id,
        tostring(summary.endedAt),
    }, "|"), channel)
end

-- Die Zusammenfassung geht gedrosselt und in Teilen raus; fehlgeschlagene
-- Pakete werden begrenzt wiederholt, damit keine Lücke entsteht.
function GC.Sync:DistributeSummary(summary, distribution, target)
    -- Ohne ausdrueckliches Ziel geht die Auswertung an die eigene Gruppe - in
    -- der Party ueber PARTY, im Raid ueber RAID.
    distribution = distribution or self:GroupChannel()
    if not distribution then
        return 0
    end
    local messages = GC.RaidMonitor:BuildSummaryMessages(summary)
    local index = 1
    local retries = 0
    local outstanding = #messages
    self:NoteSerialPending(outstanding)
    local function ReleaseSerial(count)
        count = math.min(outstanding, math.max(0, count or outstanding))
        outstanding = outstanding - count
        GC.Sync:NoteSerialPending(-count)
    end
    local function SendNext()
        local message = messages[index]
        if not message then
            ReleaseSerial()
            return
        end
        local sent = self:Send(message, distribution, target)
        if sent then
            index = index + 1
            retries = 0
            ReleaseSerial(1)
        else
            retries = retries + 1
            if retries >= 5 then
                self.progressFailed = (tonumber(self.progressFailed) or 0) + outstanding
                ReleaseSerial()
                return
            end
        end
        if messages[index] then
            C_Timer.After(sent and 0.5 or 1.5, SendNext)
        else
            ReleaseSerial()
        end
    end
    SendNext()
    return #messages
end

-- "RQ|7" oder "RQ|7|<kennung>" - beides ist eine Anfrage nach Auswertungen.
-- Bewusst kein Musterausdruck: "^RQ|7" wuerde auch auf "RQ|77" passen und
-- damit eine Nachricht einer fremden Schemaversion durchlassen.
local function IsSummaryRequest(message)
    local head = "RQ|" .. tostring(GC.Constants.SCHEMA_VERSION)
    return message == head or message:sub(1, #head + 1) == (head .. "|")
end

function GC.Sync:OnMessage(prefix, message, distribution, sender)
    if prefix ~= GC.Constants.COMM_PREFIX then
        return
    end
    if GC.Util.NormalizeName(sender) == GC.Util.NormalizeName(GC:GetPlayerFullName()) then
        return
    end

    if distribution ~= "GUILD" and distribution ~= "WHISPER"
        and distribution ~= "RAID" and distribution ~= "PARTY" then
        return
    end

    -- Ältere Clients kennen den Handshake nicht. Ihre Schemaversion steht aber
    -- in jedem P-, W-, G- und GQ-Paket, sodass sie trotzdem als Addon-Nutzer
    -- mit abweichender Version sichtbar werden.
    local messageType, messageSchema = message:match("^(%a+)|(%d+)")

    -- The guild channel authenticates membership; a whisper does not. An
    -- empty login roster is unknown membership, never permission to write.
    if distribution == "WHISPER"
        and (messageType == "A" or messageType == "W" or messageType == "L"
            or messageType == "E" or messageType == "O" or messageType == "RD"
            or messageType == "G" or messageType == "I")
        and not GC.Roster:IsGuildMember(sender) then
        return
    end
    if (distribution == "GUILD" or GC.Roster:IsGuildMember(sender))
        and (messageType == "P" or messageType == "W" or messageType == "G"
        or messageType == "GQ" or messageType == "E" or messageType == "L"
        or messageType == "B" or messageType == "O" or messageType == "I") then
        self:NoteAddonUser(sender, { schemaVersion = messageSchema, source = "TRAFFIC" })
    end

    -- Alles, was in Teilen ankommt, treibt den Fortschrittsbalken an: Erst
    -- danach weiss dieser Client ueberhaupt, dass eine Uebertragung laeuft.
    if messageType == "W" or messageType == "G" or messageType == "E"
        or messageType == "L" or messageType == "B" or messageType == "RD"
        or messageType == "I" then
        self:WakeProgress()
    end

    if messageType == "A" and distribution == "WHISPER" then
        self:ReceiveReliableAck(GC.Util.SplitFields(message), sender)
        return
    elseif message:sub(1, 2) == "W|" and (distribution == "GUILD" or distribution == "WHISPER") then
        local fields = GC.Util.SplitFields(message)
        if tonumber(fields[2]) == GC.Constants.SCHEMA_VERSION and GC.Workshop then
            GC.Workshop:ReceiveSync(fields, sender, distribution)
        end
        return
    elseif message:sub(1, 2) == "B|" and distribution == "GUILD" then
        -- Materialbestand: geteilt wird ausschliesslich die Gildenbank, und die
        -- gehoert allen. Eigene Taschen- und Bankbestaende verlassen den Account
        -- nie, es gibt fuer sie gar keinen Sendeweg.
        if GC.Inventory then
            GC.Inventory:ReceiveSync(GC.Util.SplitFields(message), sender)
        end
        return
    elseif message:sub(1, 2) == "L|" and (distribution == "GUILD" or distribution == "WHISPER") then
        local fields = GC.Util.SplitFields(message)
        if tonumber(fields[2]) == GC.Constants.SCHEMA_VERSION and GC.WarcraftLogs then
            GC.WarcraftLogs:ReceiveSync(fields, sender, distribution)
        end
        return
    elseif message:sub(1, 2) == "G|" and (distribution == "GUILD" or distribution == "WHISPER") then
        -- Hier liefert ein anderer bereits das Gildenprofil. Wer selbst noch
        -- eine Antwort geplant hat, laesst sie damit fallen. Ausdruecklich nur
        -- beim Rundruf: Ein Fluestern an MICH belegt nicht, dass die Gilde
        -- versorgt ist.
        if distribution == "GUILD" then
            self:NotePeerAnswer("GUILDPROFILE")
        end
        self:ReceiveGuildProfileChunk(message, sender, distribution)
        return
    elseif message:sub(1, 2) == "E|" and (distribution == "GUILD" or distribution == "WHISPER") then
        if GC.GearAudit then
            GC.GearAudit:ReceiveEquipmentChunk(message, sender)
        end
        return
    elseif message:sub(1, 2) == "I|" and (distribution == "GUILD" or distribution == "WHISPER") then
        -- Das Bewerber-Postfach. Die Anfrage laeuft ueber den Gildenkanal,
        -- die Antwort gezielt per Fluestern.
        if GC.Chat then
            GC.Chat:ReceiveSync(message, sender, distribution)
        end
        return
    elseif distribution == "GUILD" and IsSummaryRequest(message) then
        -- Seit 0.9.91 darf an die Anfrage eine Sitzungskennung angehaengt sein
        -- ("RQ|7|<kennung>"), damit eine Reparatur gezielt nach EINEM Abend
        -- fragen kann statt nach allem. Die nackte Form bleibt gueltig - sie
        -- kommt von aelteren Clients und vom Knopf "Auswertung anfordern".
        if GC.RaidMonitor then
            GC.RaidMonitor:OnMessage(message, sender, distribution)
        end
        return
    elseif message == ("GQ|" .. tostring(GC.Constants.SCHEMA_VERSION)) and distribution == "GUILD" then
        self:ReplyToGuildProfileRequest(sender)
        return
    end

    -- Gildenaufträge: Broadcasts über den Gildenkanal, Abgleichantworten
    -- gezielt per Flüstern. Vor dem Raid-Sammelzweig, der WHISPER schluckt.
    if messageType == "O" and (distribution == "GUILD" or distribution == "WHISPER") then
        if GC.Orders then
            GC.Orders:OnMessage(message, sender, distribution)
        end
        return
    end

    -- Der Versionsprüfer fragt auch über RAID/PARTY - diese V-Nachrichten
    -- müssen VOR dem Raid-Sammelzweig abbiegen, der sie sonst schluckt.
    if messageType == "V"
        and (distribution == "RAID" or distribution == "PARTY") then
        self:ReceiveVersion(GC.Util.SplitFields(message), sender, distribution)
        return
    end

    -- Raidauswertungen verwenden RAID/PARTY sowie gezielte WHISPER-Antworten.
    -- Erst nachdem die gildenweiten Direkttransfers oben geroutet wurden,
    -- landet der restliche Verkehr beim Raidmodul.
    if distribution == "RAID" or distribution == "PARTY" or distribution == "WHISPER" then
        if GC.RaidMonitor then
            GC.RaidMonitor:OnMessage(message, sender, distribution)
        end
        return
    end

    local fields = GC.Util.SplitFields(message)
    local schemaVersion = tonumber(fields[2])
    if fields[1] == "P"
        and (schemaVersion == 2 or schemaVersion == 3 or schemaVersion == 4
            or schemaVersion == 5 or schemaVersion == 6
            or schemaVersion == GC.Constants.SCHEMA_VERSION) then
        self:ReceiveProfile(fields, sender)
    elseif fields[1] == "V" then
        -- Bewusst ohne Schemaprüfung: gerade abweichende Versionen sollen
        -- erkannt werden.
        self:ReceiveVersion(fields, sender, distribution)
    end
end

local syncEvents = CreateFrame("Frame")
syncEvents:RegisterEvent("CHAT_MSG_ADDON")
syncEvents:RegisterEvent("GROUP_ROSTER_UPDATE")
syncEvents:SetScript("OnEvent", function(_, event, prefix, message, distribution, sender)
    if GC.Client.HasSecretArguments(prefix, message, distribution, sender) then return end
    if event == "GROUP_ROSTER_UPDATE" then
        local inGroup = IsInGroup and IsInGroup() == true
        if inGroup and not GC.Sync.wasInGroup then
            GC.Sync:AnnounceVersion(false, MIN_ANNOUNCE_INTERVAL)
        end
        GC.Sync.wasInGroup = inGroup
        return
    end
    GC.Sync:OnMessage(prefix, message, distribution, sender)
end)

-- Der Rahmen selbst steht oben bei den BULK-Konstanten; er ist nur sichtbar,
-- solange die Warteschlange Arbeit hat und kein Kampf laeuft.
bulkFrame:SetScript("OnUpdate", function(_, elapsed)
    GC.Sync:PumpBulk(elapsed)
end)

-- Ein verstecktes Frame bekommt weiterhin Ereignisse, nur kein OnUpdate. Genau
-- das weckt die im Kampf schlafen gelegte Warteschlange wieder auf.
bulkFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
bulkFrame:SetScript("OnEvent", function()
    if #GC.Sync.bulkQueue == 0 then
        return
    end
    -- Waehrend des Kampfes hat sich das Sendebudget weiter gefuellt; die
    -- verstrichene Zeit wird beim Aufwachen in einem Schritt nachgebucht -
    -- dieselbe Verrechnung wie nach einer Leerlaufpause.
    local slept = 0
    if GC.Sync.bulkCombatAt then
        slept = math.max(0, GC.Util.Now() - GC.Sync.bulkCombatAt)
        GC.Sync.bulkCombatAt = nil
    end
    bulkFrame:Show()
    GC.Sync:PumpBulk(slept)
end)

-- === Die Anlaufsequenz =====================================================
--
-- Alles, was ein Client beim Betreten einer Gilde einmal tun muss: sich
-- vorstellen, den Stand erfragen und den eigenen anbieten. Sie lief frueher
-- fest im PLAYER_LOGIN-Rueckruf und damit genau einmal je Sitzung; seit dem
-- Gildenwechsel-Rueckruf weiter unten ist sie eine eigene Funktion und laeuft
-- auch dann, wenn die Gilde erst im laufenden Spiel dazukommt.
--
-- Die Abstaende sind unveraendert: Sie entzerren den Addon-Kanal in den ersten
-- Sekunden, in denen ohnehin jeder andere Client seine eigene Sequenz faehrt.
function GC.Sync:RunStartupSequence()
    self.lastPrimeAt = GC.Util.Now()
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return false
    end
    C_Timer.After(3, function()
        self:QueueProfile()
    end)
    C_Timer.After(5, function()
        self:PrimeGuildProfileSync()
    end)
    C_Timer.After(7, function()
        self.wasInGroup = IsInGroup and IsInGroup() == true
        self:AnnounceVersion(true)
    end)
    C_Timer.After(9, function()
        if GC.WarcraftLogs then
            GC.WarcraftLogs:RequestRecruitmentData()
        end
    end)
    C_Timer.After(12, function()
        -- Erst hier, nicht beim Anmelden: Die Antworten auf die eigene
        -- Versionsanfrage (Sekunde 7, bis zu 4,5 Sekunden gestreut) sind dann
        -- da und zaehlen mit.
        self:CheckKnownVersions()
    end)
    C_Timer.After(13, function()
        -- Gildenaufträge abgleichen: Wer etwas kennt, liefert es nach.
        if GC.Orders then
            GC.Orders:RequestSync()
        end
    end)
    C_Timer.After(15, function()
        -- Und das Bewerber-Postfach: Was die Gilde kennt, kennt jeder. Die
        -- Antworten kommen gestreut und per Fluestern, damit ein Login nicht
        -- den halben Gildenkanal belegt.
        if GC.Chat then
            GC.Chat:RequestInbox()
        end
    end)
    C_Timer.After(17, function()
        -- ... und der Gegenweg: die eigenen laufenden Aufträge in die Gilde
        -- drücken, für alle, an denen die Live-Broadcasts vorbeigingen.
        if GC.Orders then
            GC.Orders:PushOpenOrders()
        end
    end)
    return true
end

GC:RegisterCallback("PLAYER_LOGIN", GC.Sync, function(self)
    self:RegisterPrefix()
    self:RunStartupSequence()
end)

-- Der Gildenwechsel im laufenden Spiel: dieselbe Sequenz noch einmal.
--
-- Der Mindestabstand faengt den einzigen Fall ab, in dem der Rueckruf nicht
-- gemeint ist: Direkt nach dem Anmelden liefert GetGuildInfo noch nichts, der
-- Schluessel springt eine Sekunde spaeter von "UNGUILDED" auf die echte Gilde -
-- und die Sequenz des Logins laeuft da ohnehin schon, mit dem richtigen
-- Gildenzweig, weil jeder ihrer Schritte den Schluessel erst beim Senden liest.
-- Ein echter Beitritt liegt immer weit hinter diesem Fenster.
local MIN_PRIME_INTERVAL = 30

GC:RegisterCallback("GUILD_CHANGED", GC.Sync, function(self)
    if not IsInGuild or not IsInGuild() then
        return
    end
    if (GC.Util.Now() - (tonumber(self.lastPrimeAt) or 0)) < MIN_PRIME_INTERVAL then
        return
    end
    self:RunStartupSequence()
end)

GC:RegisterCallback("PROFILE_UPDATED", GC.Sync, function(self)
    self:QueueProfile()
end)
