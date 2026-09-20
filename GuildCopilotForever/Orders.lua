local _, GC = ...

-- Gildenaufträge: dokumentierte Absprachen über Katalogrezepte.
-- Konzept und Owner-Entscheidungen: docs/KONZEPT-werkstatt-gildenauftraege.md.
--
-- Das Modul ist eine Koordinationsschicht. Es bewegt weder Gold noch Waren;
-- es hält fest, was vereinbart wurde, wer als Nächstes dran ist, und
-- protokolliert jeden Schritt. Auftragnehmer ist immer der Account, nicht
-- der Charakter: Angenommen werden darf vom Twink, gefertigt wird mit dem
-- Charakter, der das Rezept laut Katalog beherrscht.

GC.Orders = {
    lastRequestAt = 0,
}

local MAX_OPEN_PER_ACCOUNT = 5
local OPEN_TTL = 14 * 24 * 60 * 60
local HISTORY_CAP = 20
local TOTAL_CAP = 60
local STALE_ACCEPT_SECONDS = 3 * 24 * 60 * 60
local MAX_LOG_ENTRIES = 12
-- UI limits; transport checks the encoded size separately (% expands to %25).
local MAX_NOTE_BYTES = 48
local MAX_NAME_BYTES = 30
local MIN_ANSWER_INTERVAL = 30
-- Ein gerichteter Auftrag ("Wunsch-Hersteller") ist so lange reserviert,
-- danach offen fuer alle. Die Frist wird nie gesendet - jeder Client rechnet
-- createdAt + RESERVATION_SECONDS selbst.
local RESERVATION_SECONDS = 24 * 60 * 60
local MAX_STATS_COUNTED = 200

-- Deckel fuer die beiden Massenwege. Beide verschickten bis 0.9.96 den ganzen
-- Bestand: die Abgleichantwort 180 Fluesterpakete bei 60 Auftraegen, der
-- Login-Push 120 Broadcasts - und das von jedem Client. Bei 250 Online waren
-- das 45.000 bzw. 30.000 Pakete je Login, waehrend Blizzards Addon-Kanal rund
-- zehn Pakete je Sekunde und Absender zustellt und den Rest lautlos verwirft.
local MAX_ANSWER_ORDERS = 40
local MAX_PUSH_ORDERS = 25

-- Wie lange der Vermerk "diesem Anfragenden wurde geantwortet" aufgehoben
-- wird. Zehn Drosselzeiten sind lange genug, dass keine Wiederholung
-- durchrutscht, und kurz genug, dass die Tabelle nicht ueber einen Spielabend
-- hinweg jeden Namen der Gilde sammelt.
local ANSWERED_MEMORY = MIN_ANSWER_INTERVAL * 10

-- Reihenfolge = Lebenslauf. RECEIVED gibt es nur, wenn nach dem Erhalt noch
-- eine Erstattung offen ist (Materialmodell C mit gemeldeten Kosten).
local STATUS = {
    OPEN = true, ACCEPTED = true, WORKING = true, CRAFTED = true,
    SHIPPED = true, RECEIVED = true, DONE = true, CANCELLED = true,
}

local TERMINAL = { DONE = true, CANCELLED = true }

GC.OrderStatusLabels = {
    OPEN = "Offen",
    ACCEPTED = "Angenommen",
    WORKING = "In Arbeit",
    CRAFTED = "Gefertigt",
    SHIPPED = "Versandt",
    RECEIVED = "Erhalten – Erstattung offen",
    DONE = "Abgeschlossen",
    CANCELLED = "Abgebrochen",
}

GC.OrderModelLabels = {
    A = "Auftraggeber liefert Materialien",
    B = "Materialien aus der Gildenbank",
    C = "Auftragnehmer besorgt, wird erstattet",
}

GC.OrderDeliveryLabels = {
    TRADE = "Persönliche Übergabe",
    MAIL = "Per Post",
}

-- Logereignisse. NOT ist die freie Notiz an die Gegenseite.
local EVENT_LABELS = {
    CRT = "Auftrag erstellt",
    ACC = "Angenommen",
    MAT = "Materialien vollständig",
    CRA = "Gefertigt",
    SNT = "Versandt",
    RCV = "Erhalten",
    RMB = "Erstattung überwiesen",
    RMR = "Erstattung erhalten",
    RET = "Zurückgelegt",
    CXL = "Abgebrochen",
    NOT = "Notiz",
}
GC.OrderEventLabels = EVENT_LABELS

local function Sanitized(value, maximumBytes)
    value = GC.Util.Trim(value)
    value = value:gsub("[|]", " ")
    return GC.Util.SafeChatText(value, maximumBytes or MAX_NOTE_BYTES)
end

function GC.Orders.FormatMoney(copper)
    copper = math.max(0, math.floor(tonumber(copper) or 0))
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local rest = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. "k" end
    return table.concat(parts, " ")
end

function GC.Orders:GetStore()
    local workshop = GC.DB:GetGuild().workshop
    workshop.orders = workshop.orders or {}
    return workshop.orders
end

function GC.Orders:GetOrder(orderID)
    return self:GetStore()[tostring(orderID or "")]
end

local function SameCharacter(left, right)
    if not left or not right then
        return false
    end
    local a = GC.Util.NormalizeName(left)
    local b = GC.Util.NormalizeName(right)
    if a == b then
        return true
    end
    return GC.Util.NormalizeName(GC.Util.PlayerIdentityName(left))
        == GC.Util.NormalizeName(GC.Util.PlayerIdentityName(right))
end

-- === Freitext-Auftraege =====================================================
--
-- "Freitext-Auftraege fuer nicht vorhandene Rezepte einbauen" - aus der Gilde,
-- 08/2026. Der Katalog kennt nur, was jemand mit Addon eingelesen hat; was
-- niemand gescannt hat oder was der Hersteller erst noch lernen muss, war
-- damit unbestellbar.
--
-- Ein Freitext-Auftrag traegt statt eines Rezeptschluessels den BERUF:
-- "Fverzauberkunst". Das ist Absicht und keine Notloesung -
--
--   * die Annahmepruefung bleibt echt: Nur wer den Beruf hat, darf annehmen,
--     und der Filter "nur machbare" behaelt seine Bedeutung. Ein Schluessel
--     ohne jede Pruefung waere fuer jeden machbar und damit fuer niemanden;
--   * er muss nicht eindeutig sein. Auftraege unterscheidet ihre id; der
--     Rezeptschluessel beantwortet allein die Frage "wer kann das?".
--
-- Katalogschluessel beginnen mit I (Item), E (Rezept-ID) oder N (Name) - das
-- F ist deshalb frei und kann nie mit einem echten Rezept kollidieren.
local FREE_PREFIX = "F"

function GC.Orders:FreeRecipeKey(professionName)
    local key = GC.CanonicalProfessionKey(professionName or "")
    if GC.Util.Trim(key) == "" or not GC.ProfessionByKey[key] then
        return nil
    end
    return FREE_PREFIX .. key
end

-- Liefert den Berufsschluessel eines Freitext-Auftrags, sonst nil.
function GC.Orders:GetFreeProfessionKey(recipeKey)
    recipeKey = tostring(recipeKey or "")
    if recipeKey:sub(1, 1) ~= FREE_PREFIX then
        return nil
    end
    local key = recipeKey:sub(2)
    return GC.ProfessionByKey[key] and key or nil
end

function GC.Orders:GetFreeProfessionName(recipeKey)
    local key = self:GetFreeProfessionKey(recipeKey)
    local definition = key and GC.ProfessionByKey[key]
    return definition and definition.name or nil
end

local function HasProfession(professions, professionKey)
    for storedKey, profession in pairs(professions or {}) do
        -- Der Tabellenschluessel ist die verlaessliche Quelle; der Name ist es
        -- bei Daten aus englischen Clients nicht immer, und ein Bergbau-Eintrag
        -- heisst im Fenster "Schmelzen".
        local name = (type(profession) == "table" and (profession.name or profession.key))
            or storedKey
        if GC.CanonicalProfessionKey(storedKey) == professionKey
            or GC.CanonicalProfessionKey(name) == professionKey then
            return true
        end
    end
    return false
end

-- === Wer kann was fertigen? =================================================

-- Eigene Charaktere (Account-lokal, aus den gemeinsamen SavedVariables), die
-- das Rezept beherrschen. Grundlage der Twink-Regel auf der Annehmen-Seite.
--
-- Nur Charaktere DIESER Gilde: Ein Auftrag der Gilde A mit einem Twink aus
-- Gilde B anzunehmen, traegt dessen Namen in eine Gilde, in der er nicht ist -
-- und die Uebergabe koennte dort ohnehin niemand einfordern.
function GC.Orders:GetOwnCrafters(recipeKey)
    recipeKey = tostring(recipeKey or "")
    local freeProfession = self:GetFreeProfessionKey(recipeKey)
    local candidates = {}
    local seen = {}
    for _, entry in ipairs(GC.Workshop:GetPublishableProfessions()) do
        local profession = entry.profession
        local matches
        if freeProfession then
            -- Beim Freitext zaehlt der Beruf, nicht das einzelne Rezept.
            matches = profession ~= nil
                and (GC.CanonicalProfessionKey(profession.key or "") == freeProfession
                    or GC.CanonicalProfessionKey(profession.name or "") == freeProfession)
        else
            matches = profession ~= nil and profession.recipes ~= nil
                and profession.recipes[recipeKey] ~= nil
        end
        if matches then
            local key = GC.Util.NormalizeName(entry.crafter)
            if not seen[key] then
                seen[key] = true
                candidates[#candidates + 1] = entry.crafter
            end
        end
    end
    table.sort(candidates)
    return candidates
end

-- Kann dieser Charakter das Rezept laut geteiltem Wissen fertigen? Prüft den
-- gildenweiten Herstellerindex und die eigenen Charaktere. Das ist die
-- Empfangsprüfung für Annahmen: nur Katalogwissen zählt, keine Behauptung.
function GC.Orders:IsKnownCrafter(characterName, recipeKey)
    recipeKey = tostring(recipeKey or "")
    if GC.Util.Trim(characterName) == "" or recipeKey == "" then
        return false
    end
    for _, own in ipairs(self:GetOwnCrafters(recipeKey)) do
        if SameCharacter(own, characterName) then
            return true
        end
    end
    local crafters = GC.Workshop:GetGuildWorkshop().crafters or {}
    local entry = crafters[GC.Util.NormalizeName(characterName)]
        or crafters[GC.Util.NormalizeName(GC.Util.PlayerIdentityName(characterName))]
    if not entry then
        return false
    end
    local freeProfession = self:GetFreeProfessionKey(recipeKey)
    if freeProfession then
        return HasProfession(entry.professions, freeProfession)
    end
    for _, profession in pairs(entry.professions or {}) do
        if profession.recipeKeys and profession.recipeKeys[recipeKey] then
            return true
        end
        if profession.recipes and profession.recipes[recipeKey] then
            return true
        end
    end
    return false
end

-- Gehört der Absender zum Auftragnehmer-Account? Erst der accountTag aus dem
-- Handshake, ersatzweise die beiden im Auftrag benannten Charaktere.
function GC.Orders:IsAcceptorCharacter(order, characterName)
    if not order or GC.Util.Trim(characterName) == "" then
        return false
    end
    if SameCharacter(order.crafter, characterName)
        or SameCharacter(order.acceptedVia, characterName) then
        return true
    end
    local tag = GC.Util.Trim(order.acceptedByTag)
    if tag == "" then
        return false
    end
    if tag == GC.DB:GetAccountTag() then
        -- Eigene Charaktere kennt der Client selbst.
        local ownName = GC:GetPlayerFullName()
        if SameCharacter(ownName, characterName) then
            return true
        end
        for characterKey, character in pairs((GC.DB.data and GC.DB.data.characters) or {}) do
            local name = (type(character) == "table" and character.fullName) or characterKey
            if SameCharacter(name, characterName) then
                return true
            end
        end
    end
    local users = GC.DB:GetGuild().addonUsers or {}
    local entry = users[GC.Util.NormalizeName(characterName)]
        or users[GC.Util.NormalizeName(GC.Util.PlayerIdentityName(characterName))]
    return entry ~= nil and GC.Util.Trim(entry.accountTag) == tag
end

function GC.Orders:IsCreatorCharacter(order, characterName)
    return order ~= nil and SameCharacter(order.createdBy, characterName)
end

-- Offiziers-Abbruchrecht (Owner-Entscheidung 2): dieselbe Rangfreigabe wie
-- die Mitgliederpflege.
function GC.Orders:CanAdministrate(characterName)
    return GC.Roster:CanAccessMemberCare(characterName)
end

-- Gerichteter Auftrag: 24 Stunden lang darf nur der Wunsch-Hersteller
-- annehmen, danach ist er offen fuer alle.
function GC.Orders:IsReserved(order, at)
    if not order or GC.Util.Trim(order.preferredCrafter) == "" then
        return false
    end
    return ((at or GC.Util.Now()) - (order.createdAt or 0)) < RESERVATION_SECONDS
end

function GC.Orders:IsReservedForOther(order, crafterName, at)
    return self:IsReserved(order, at)
        and not SameCharacter(order.preferredCrafter, crafterName)
end

-- Der beste Fluester-Empfaenger der Gegenseite: bevorzugt ein gerade
-- online sichtbarer Charakter des anderen Accounts, sonst der benannte.
function GC.Orders:GetCounterpartCharacter(order)
    if not order then
        return nil
    end
    local isCreator = self:IsCreatorCharacter(order, GC:GetPlayerFullName())
    local candidates
    if isCreator then
        candidates = { order.crafter, order.acceptedVia }
    else
        candidates = { order.createdBy }
    end
    local tag = isCreator and order.acceptedByTag or order.createdByTag
    if GC.Util.Trim(tag) ~= "" then
        for _, entry in pairs(GC.DB:GetGuild().addonUsers or {}) do
            if type(entry) == "table" and GC.Util.Trim(entry.accountTag) == tag then
                candidates[#candidates + 1] = entry.name
            end
        end
    end
    local fallback
    for _, name in ipairs(candidates) do
        if GC.Util.Trim(name or "") ~= "" then
            fallback = fallback or name
            local member = GC.Roster:GetMember(name)
            if member and member.online then
                return member.name
            end
        end
    end
    return fallback
end

-- Die Auftraege, die zwischen diesem Account und dem Handelspartner offen
-- sind - fuer den Helfer neben dem Handelsfenster. "Offen" heisst: Einer von
-- beiden schuldet dem anderen noch eine Handlung. OPEN faellt bewusst raus,
-- dort gibt es noch keinen Gegenpart und nichts zu uebergeben.
function GC.Orders:GetOrdersWithCounterpart(partnerName)
    local results = {}
    if GC.Util.Trim(partnerName) == "" then
        return results
    end
    local ownName = GC:GetPlayerFullName()
    local relevant = {
        ACCEPTED = true, WORKING = true, CRAFTED = true,
        SHIPPED = true, RECEIVED = true,
    }
    for _, order in pairs(self:GetStore()) do
        if relevant[order.status] then
            local ownCreator = self:IsCreatorCharacter(order, ownName)
            local ownAcceptor = self:IsAcceptorCharacter(order, ownName)
            local partnerCreator = self:IsCreatorCharacter(order, partnerName)
            local partnerAcceptor = self:IsAcceptorCharacter(order, partnerName)
            if (ownCreator and partnerAcceptor) or (ownAcceptor and partnerCreator) then
                results[#results + 1] = order
            end
        end
    end
    table.sort(results, function(left, right)
        return (tonumber(left.changedAt) or 0) > (tonumber(right.changedAt) or 0)
    end)
    return results
end

-- === Statistik ==============================================================
-- Zaehlt abgeschlossene Auftraege je Hersteller und Auftraggeber. Gezaehlt
-- wird beim Uebergang auf ABGESCHLOSSEN, je Auftrag genau einmal (die Liste
-- der bereits gezaehlten IDs verhindert Doppelzaehlung durch Kurierpakete).
--
-- Neben den Auftraegen zaehlen seit 0.9.110 die STUECKE mit. Vorher wog ein
-- Auftrag ueber 40 Urnen genauso schwer wie einer ueber einen Ring, und die
-- Statistik beantwortete die Frage "wie viel wurde eigentlich gefertigt?"
-- nicht - genau das kam aus der Gilde als "Mengen werden nicht gezaehlt"
-- zurueck. Die alten Tabellen bleiben, damit gesammelte Staende nicht
-- verfallen; die neuen fangen bei null an.
function GC.Orders:GetStats()
    local workshop = GC.DB:GetGuild().workshop
    workshop.orderStats = workshop.orderStats or {
        counted = {},
        byCrafter = {},
        byCreator = {},
    }
    workshop.orderStats.counted = workshop.orderStats.counted or {}
    workshop.orderStats.byCrafter = workshop.orderStats.byCrafter or {}
    workshop.orderStats.byCreator = workshop.orderStats.byCreator or {}
    workshop.orderStats.itemsByCrafter = workshop.orderStats.itemsByCrafter or {}
    workshop.orderStats.itemsByCreator = workshop.orderStats.itemsByCreator or {}
    return workshop.orderStats
end

function GC.Orders:CountCompletion(order, previousStatus)
    if not order or order.status ~= "DONE" or previousStatus == "DONE" then
        return false
    end
    local stats = self:GetStats()
    for _, countedID in ipairs(stats.counted) do
        if countedID == order.id then
            return false
        end
    end
    stats.counted[#stats.counted + 1] = order.id
    while #stats.counted > MAX_STATS_COUNTED do
        table.remove(stats.counted, 1)
    end
    -- Die vereinbarte Stueckzahl, nicht die gemeldete: Ein Auftrag wird erst
    -- abgeschlossen, wenn alle Stuecke da sind. craftedCount taugt hier nicht
    -- als Quelle - er kommt von Altclients als 0 an und wuerde die Zahl je
    -- nach Gegenueber verschlucken.
    local items = math.max(1, math.floor(tonumber(order.quantity) or 1))
    local crafterKey = GC.Util.PlayerIdentityName(order.crafter or "")
    if crafterKey ~= "" then
        stats.byCrafter[crafterKey] = (stats.byCrafter[crafterKey] or 0) + 1
        stats.itemsByCrafter[crafterKey] = (stats.itemsByCrafter[crafterKey] or 0) + items
    end
    local creatorKey = GC.Util.PlayerIdentityName(order.createdBy or "")
    if creatorKey ~= "" then
        stats.byCreator[creatorKey] = (stats.byCreator[creatorKey] or 0) + 1
        stats.itemsByCreator[creatorKey] = (stats.itemsByCreator[creatorKey] or 0) + items
    end
    return true
end

-- Ein Auftrag erreicht uns nicht dann, wenn er sich aendert, sondern dann, wenn
-- wir davon erfahren. Beim Login beantwortet jeder Client die Abfrage mit allen
-- ihm bekannten laufenden Auftraegen, und Kuriere reichen fremde Staende
-- weiter. Fuer den Empfaenger sah bisher jeder davon aus wie eine Aenderung von
-- jetzt: Bei jedem Login und jedem /reload lief die Klangfolge der letzten Tage
-- erneut ab, fuer Auftraege, die laengst erledigt waren.
--
-- Gemeldet wird deshalb nur, was frisch ist. Der Vergleich ist zwischen zwei
-- Rechnern zulaessig, weil changedAt aus GetServerTime kommt - dieselbe Uhr
-- fuer alle auf dem Realm, kein Geraeteversatz.
--
-- Die Frist ist bewusst grosszuegig: Sie muss den Weg ueber die Warteschlange
-- und eine Kampfpause aushalten, ohne eine echte Aenderung zu verschlucken.
-- Ein Nachholstand ist immer um Stunden aelter, nie um Minuten.
local NOTIFY_MAX_AGE = 120

local function IsFreshChange(at)
    return (GC.Util.Now() - (tonumber(at) or 0)) <= NOTIFY_MAX_AGE
end

-- Klang und Statistik an einer Stelle: Jede Statusaenderung laeuft hier durch.
--
-- "announce" trennt beides. Verbucht wird immer - die Statistik darf den
-- Nachholstand nicht verlieren, sonst zaehlt ein Auftrag je nachdem mit, ob man
-- online war, als er fertig wurde. Stumm bleibt nur der Lautsprecher. Ohne das
-- Argument wird gemeldet: Die eigenen Aktionen sind per Definition von jetzt.
function GC.Orders:NoteStatusChanged(order, previousStatus, announce)
    if announce ~= false then
        self:PlayStatusSound(order, previousStatus)
    end
    self:CountCompletion(order, previousStatus)
end

-- === Vorlagen ===============================================================
-- Eine Vorlage je Rezept, lokal im Account: Wiederkehrende Auftraege ("jede
-- Woche 15 Sphaeren") sind mit einem Klick wieder ausgefuellt.
function GC.Orders:SaveTemplate(recipeKey, options)
    if GC.Util.Trim(recipeKey) == "" or type(options) ~= "table" then
        return false
    end
    local settings = GC.DB:GetSettings()
    settings.orderTemplates = settings.orderTemplates or {}
    settings.orderTemplates[recipeKey] = {
        quantity = tonumber(options.quantity) or 1,
        materialModel = options.materialModel,
        delivery = options.delivery,
        costLimit = tonumber(options.costLimit) or 0,
        tip = tonumber(options.tip) or 0,
        note = tostring(options.note or ""),
        preferredCrafter = tostring(options.preferredCrafter or ""),
    }
    return true
end

function GC.Orders:GetTemplate(recipeKey)
    local templates = GC.DB:GetSettings().orderTemplates
    return templates and templates[recipeKey] or nil
end

-- === Verlauf ================================================================

local function AppendLog(order, at, by, event, note)
    order.log = order.log or {}
    at = tonumber(at) or GC.Util.Now()
    by = Sanitized(by, MAX_NAME_BYTES)
    note = Sanitized(note, MAX_NOTE_BYTES)
    for _, entry in ipairs(order.log) do
        if entry.at == at and entry.event == event
            and GC.Util.NormalizeName(entry.by) == GC.Util.NormalizeName(by) then
            return false
        end
    end
    order.log[#order.log + 1] = { at = at, by = by, event = event, note = note }
    table.sort(order.log, function(left, right)
        return (left.at or 0) < (right.at or 0)
    end)
    while #order.log > MAX_LOG_ENTRIES do
        table.remove(order.log, 1)
    end
    return true
end

-- === Wer ist dran? ==========================================================

-- Liefert "CREATOR", "ACCEPTOR" oder nil (terminal/offen) plus die passende
-- Handlungsaufforderung. Das ist die eine Wahrheit für Board, Reiterzähler,
-- Tracker und Minimap-Punkt.
function GC.Orders:GetNextActor(order)
    if not order or TERMINAL[order.status] then
        return nil, ""
    end
    if order.status == "OPEN" then
        return nil, "Wartet auf einen Hersteller."
    end
    if order.status == "ACCEPTED" then
        if order.materialModel == "A" then
            return "CREATOR", "Materialien an " .. GC.Util.PlayerIdentityName(order.crafter or "?") .. " liefern."
        end
        return "ACCEPTOR", "Materialien beschaffen und „vollständig“ melden."
    end
    if order.status == "WORKING" then
        local quantity = tonumber(order.quantity) or 1
        local crafted = tonumber(order.craftedCount) or 0
        if quantity > 1 then
            return "ACCEPTOR", "Fertigen (" .. crafted .. "/" .. quantity
                .. ") und „gefertigt“ melden."
        end
        return "ACCEPTOR", "Fertigen und „gefertigt“ melden."
    end
    if order.status == "CRAFTED" then
        if order.delivery == "MAIL" then
            return "ACCEPTOR", "An " .. GC.Util.PlayerIdentityName(order.createdBy or "?") .. " versenden."
        end
        return "CREATOR", "Übergabe vereinbaren und „erhalten“ bestätigen."
    end
    if order.status == "SHIPPED" then
        return "CREATOR", "Post prüfen und „erhalten“ bestätigen."
    end
    if order.status == "RECEIVED" then
        if (order.reimbursedAt or 0) == 0 then
            local rest = math.max(0, (order.actualCost or 0) - (tonumber(order.reimbursedPaid) or 0))
            return "CREATOR", "Erstattung überweisen – offen: "
                .. GC.Orders.FormatMoney(rest) .. "."
        end
        return "ACCEPTOR", "„Erstattung erhalten“ bestätigen."
    end
    return nil, ""
end

-- Zählt Aufträge, bei denen der eigene Account als Nächstes dran ist.
function GC.Orders:GetActionableCount()
    local count = 0
    local ownTag = GC.DB:GetAccountTag()
    local ownName = GC:GetPlayerFullName()
    for _, order in pairs(self:GetStore()) do
        local actor = self:GetNextActor(order)
        if actor == "CREATOR" and self:IsCreatorCharacter(order, ownName) then
            count = count + 1
        elseif actor == "ACCEPTOR" and GC.Util.Trim(order.acceptedByTag) ~= ""
            and order.acceptedByTag == ownTag then
            count = count + 1
        end
    end
    return count
end

-- === Übergänge ==============================================================

local function ClearAcceptor(order)
    order.acceptedByTag = ""
    order.acceptedAt = 0
    order.crafter = ""
    order.acceptedVia = ""
    order.actualCost = 0
    order.reimbursedAt = 0
    order.reimbursedPaid = 0
    order.craftedCount = 0
end

-- Eine Zustandsänderung, lokal ausgeführt und anschließend gesendet. Alle
-- eigenen Aktionen und alle Empfangswege laufen durch dieselbe Prüfung.
local function Transition(self, order, event, actor, at, extra, remote)
    at = tonumber(at) or GC.Util.Now()
    extra = extra or {}
    local status = order.status

    if TERMINAL[status] and event ~= "NOT" then
        return false, "Der Auftrag ist bereits abgeschlossen."
    end

    if event == "ACC" then
        if status ~= "OPEN" then
            return false, "Der Auftrag ist nicht mehr offen."
        end
        local crafter = GC.Util.Trim(extra.crafter)
        if crafter == "" or not self:IsKnownCrafter(crafter, order.recipeKey) then
            return false, "Laut Katalog beherrscht dieser Charakter das Rezept nicht."
        end
        if self:IsReservedForOther(order, crafter, at) then
            return false, "Der Auftrag ist noch für "
                .. GC.Util.PlayerIdentityName(order.preferredCrafter) .. " reserviert."
        end
        order.status = "ACCEPTED"
        order.acceptedByTag = Sanitized(extra.accountTag, 12)
        order.acceptedAt = at
        order.crafter = Sanitized(crafter, MAX_NAME_BYTES)
        order.acceptedVia = Sanitized(actor, MAX_NAME_BYTES)
    elseif event == "MAT" then
        if status ~= "ACCEPTED" then
            return false, "Materialien lassen sich nur nach der Annahme melden."
        end
        if not self:IsAcceptorCharacter(order, actor) then
            return false, "Nur der Auftragnehmer meldet Materialien."
        end
        order.status = "WORKING"
    elseif event == "CRA" then
        if status ~= "WORKING" then
            return false, "Gefertigt setzt „in Arbeit“ voraus."
        end
        if not self:IsAcceptorCharacter(order, actor) then
            return false, "Nur der Auftragnehmer meldet die Fertigung."
        end
        local cost = tonumber(extra.actualCost)
        if order.materialModel == "C" and cost and cost > 0 then
            order.actualCost = math.floor(cost)
        end
        -- Teilfertigung bei Stueckzahlen > 1: Der Auftrag bleibt in Arbeit,
        -- bis alle Stuecke gemeldet sind; der Zaehler steht an der Zeile.
        local quantity = tonumber(order.quantity) or 1
        local crafted = math.floor(tonumber(extra.craftedCount) or quantity)
        crafted = math.max(tonumber(order.craftedCount) or 0, math.min(crafted, quantity))
        order.craftedCount = crafted
        if crafted < quantity then
            extra.note = GC.Util.Trim(extra.note or "") ~= "" and extra.note
                or (crafted .. " von " .. quantity .. " gefertigt")
        else
            order.status = "CRAFTED"
        end
    elseif event == "SNT" then
        if status ~= "CRAFTED" or order.delivery ~= "MAIL" then
            return false, "Versandt gilt nur für fertige Postaufträge."
        end
        if not self:IsAcceptorCharacter(order, actor) then
            return false, "Nur der Auftragnehmer meldet den Versand."
        end
        order.status = "SHIPPED"
    elseif event == "RCV" then
        if status ~= "CRAFTED" and status ~= "SHIPPED" then
            return false, "Erhalten gilt erst nach der Fertigung."
        end
        if not self:IsCreatorCharacter(order, actor) then
            return false, "Nur der Auftraggeber bestätigt den Erhalt."
        end
        if order.materialModel == "C" and (order.actualCost or 0) > 0 then
            order.status = "RECEIVED"
        else
            order.status = "DONE"
        end
    elseif event == "RMB" then
        if status ~= "RECEIVED" then
            return false, "Es ist keine Erstattung offen."
        end
        if not self:IsCreatorCharacter(order, actor) then
            return false, "Nur der Auftraggeber meldet die Erstattung."
        end
        -- Teilzahlungen: Jede Meldung erhoeht den gezahlten Betrag; erst wenn
        -- nichts mehr offen ist, gilt die Erstattung als ueberwiesen und der
        -- Auftragnehmer ist mit der Bestaetigung dran.
        local paid = tonumber(order.reimbursedPaid) or 0
        local amount = math.floor(tonumber(extra.amount)
            or math.max(0, (order.actualCost or 0) - paid))
        paid = math.max(0, math.min(order.actualCost or 0, paid + math.max(0, amount)))
        order.reimbursedPaid = paid
        if paid >= (order.actualCost or 0) then
            order.reimbursedAt = at
        else
            extra.note = GC.Util.Trim(extra.note or "") ~= "" and extra.note
                or (GC.Orders.FormatMoney(amount) .. " gezahlt, offen "
                    .. GC.Orders.FormatMoney((order.actualCost or 0) - paid))
        end
    elseif event == "RMR" then
        if status ~= "RECEIVED" then
            return false, "Es ist keine Erstattung offen."
        end
        if not self:IsAcceptorCharacter(order, actor) then
            return false, "Nur der Auftragnehmer bestätigt die Erstattung."
        end
        order.status = "DONE"
    elseif event == "RET" then
        if status ~= "ACCEPTED" and status ~= "WORKING" then
            return false, "Nur angenommene Aufträge lassen sich zurücklegen."
        end
        -- Zurücklegen darf der Auftragnehmer selbst - oder der Auftraggeber,
        -- wenn der Auftrag lange stillsteht oder der Account die Gilde
        -- verlassen hat (Rückfall laut Konzept).
        local isAcceptor = self:IsAcceptorCharacter(order, actor)
        local isCreator = self:IsCreatorCharacter(order, actor)
        if not isAcceptor and not isCreator then
            return false, "Zurücklegen dürfen nur die Beteiligten."
        end
        if isCreator and not isAcceptor and not remote then
            local idle = at - (order.changedAt or order.acceptedAt or 0)
            if idle < STALE_ACCEPT_SECONDS and not extra.acceptorLeft then
                return false, "Der Rückfall steht erst nach "
                    .. math.floor(STALE_ACCEPT_SECONDS / 86400) .. " Tagen Stillstand offen."
            end
        end
        order.status = "OPEN"
        ClearAcceptor(order)
    elseif event == "CXL" then
        if not self:IsCreatorCharacter(order, actor)
            and not self:CanAdministrate(actor) then
            return false, "Abbrechen darf der Auftraggeber oder ein freigegebener Rang."
        end
        order.status = "CANCELLED"
    elseif event == "NOT" then
        if not self:IsCreatorCharacter(order, actor)
            and not self:IsAcceptorCharacter(order, actor) then
            return false, "Notizen dürfen nur die Beteiligten hinterlassen."
        end
        if GC.Util.Trim(extra.note or "") == "" then
            return false, "Die Notiz ist leer."
        end
    else
        return false, "Unbekanntes Ereignis."
    end

    order.rev = (tonumber(order.rev) or 0) + 1
    order.changedAt = at
    AppendLog(order, at, actor, event, extra.note)
    return true
end

-- === Serialisierung =========================================================

local SCHEMA = function() return tostring(GC.Constants.SCHEMA_VERSION) end

local function Join(parts)
    for index = 1, #parts do
        parts[index] = GC.Util.EscapeField(parts[index])
    end
    return table.concat(parts, "|")
end

-- C: der unveränderliche Kern. Wird bei jeder Änderung mitgesendet, damit
-- kein Empfänger je vor einem unbekannten Auftrag steht.
function GC.Orders:BuildCoreMessage(order)
    return Join({
        "O", SCHEMA(), "C",
        order.id,
        order.recipeKey,
        order.recipeName or "",
        tostring(order.quantity or 1),
        order.createdBy or "",
        order.createdByTag or "",
        tostring(order.createdAt or 0),
        order.materialModel or "A",
        order.delivery or "TRADE",
        tostring(order.costLimit or 0),
        tostring(order.tip or 0),
        order.note or "",
        -- Feld 16, von Altclients ignoriert: der Wunsch-Hersteller. Die
        -- 24-Stunden-Frist wird nie gesendet, sie folgt aus createdAt.
        order.preferredCrafter or "",
    })
end

-- U: der veränderliche Zustand samt der einen neuen Verlaufszeile.
function GC.Orders:BuildStateMessage(order, logEntry)
    return Join({
        "O", SCHEMA(), "U",
        order.id,
        tostring(order.rev or 1),
        order.status or "OPEN",
        tostring(order.changedAt or 0),
        order.acceptedByTag or "",
        tostring(order.acceptedAt or 0),
        order.crafter or "",
        order.acceptedVia or "",
        tostring(order.actualCost or 0),
        tostring(order.reimbursedAt or 0),
        logEntry and tostring(logEntry.at or 0) or "",
        logEntry and (logEntry.by or "") or "",
        logEntry and (logEntry.event or "") or "",
        logEntry and (logEntry.note or "") or "",
        -- Felder 18/19, von Altclients ignoriert: Teilzahlung und
        -- Teilfertigung.
        tostring(order.reimbursedPaid or 0),
        tostring(order.craftedCount or 0),
    })
end

-- Short messages retain their existing wire format. Only messages that could
-- not previously be sent use fragments; both peers need 0.9.142 for those.
function GC.Orders:BuildTransportMessages(payload)
    if #payload <= GC.Constants.MAX_CHAT_BYTES then return { payload } end
    local token = GC.Util.NextTransferToken()
    local header = "O|" .. SCHEMA() .. "|F|" .. token .. "|000|000|"
    local chunks = GC.Util.ChunkEscapedPayload(GC.Util.EscapeField(payload),
        GC.Constants.MAX_CHAT_BYTES - #header)
    if #chunks > 16 then return {} end
    local messages = {}
    for index, chunk in ipairs(chunks) do
        messages[#messages + 1] = "O|" .. SCHEMA() .. "|F|" .. token
            .. "|" .. index .. "|" .. #chunks .. "|" .. chunk
    end
    return messages
end

function GC.Orders:SendPayload(payload, bulk, distribution, target)
    if not GC.Sync then return false end
    local messages = self:BuildTransportMessages(payload)
    if #messages == 0 then return false end
    local ok = true
    for _, message in ipairs(messages) do
        local sent
        if bulk or #messages > 1 then
            sent = GC.Sync:SendBulk(message, distribution, target)
        else
            sent = GC.Sync:Send(message, distribution, target)
        end
        if not sent then ok = false end
    end
    return ok
end

function GC.Orders:BroadcastOrder(order)
    if not GC.Sync then
        return
    end
    local logEntry = order.log and order.log[#order.log]
    local core = self:BuildCoreMessage(order)
    local state = self:BuildStateMessage(order, logEntry)
    local bulk = #core > GC.Constants.MAX_CHAT_BYTES or #state > GC.Constants.MAX_CHAT_BYTES
    self:SendPayload(core, bulk)
    self:SendPayload(state, bulk)
end

-- === Eigene Aktionen ========================================================

local function NotifyChanged()
    GC:FireCallback("ORDERS_UPDATED")
end

-- === Ablehnen ===============================================================
--
-- Ein offener Auftrag, den man nicht machen will, stand bisher bis zu seinem
-- Verfall im Weg: Annehmen war die einzige Antwort, und die Liste zeigte
-- ohnehin nur drei Zeilen. Ablehnen blendet ihn deshalb aus - aber nur hier.
--
-- Der Vermerk ist bewusst LOKAL und wird nie gesendet: Der Auftrag bleibt für
-- alle anderen unverändert offen, und niemand in der Gilde erfährt, wer ihn
-- weggeklickt hat. Gespeichert wird kontoweit, weil auch die Annahme dem
-- Account gehört und nicht dem Charakter.
function GC.Orders:GetDeclined()
    local settings = GC.DB:GetSettings()
    settings.declinedOrders = settings.declinedOrders or {}
    return settings.declinedOrders
end

function GC.Orders:IsDeclined(orderID)
    return self:GetDeclined()[tostring(orderID or "")] == true
end

function GC.Orders:SetDeclined(orderID, declined)
    orderID = tostring(orderID or "")
    if orderID == "" then
        return false
    end
    -- nil statt false eintragen: Ein zurückgenommenes Ablehnen soll die Zeile
    -- aus den Einstellungen entfernen, nicht als "false" darin liegen bleiben.
    self:GetDeclined()[orderID] = (declined ~= false) and true or nil
    NotifyChanged()
    return true
end

-- === Mitgezaehlt, was wirklich gefertigt wird ===============================
--
-- "Tracken (Menge) von hergestellten Items ist nicht vorhanden" - der vierte
-- Punkt der Gildenrueckmeldung. Der Zaehler im Auftrag war eine reine
-- Handeingabe; wer im Berufsfenster fertigte, erzeugte fuer das Addon nichts.
--
-- Jetzt hoert der Client auf den erfolgreichen Herstellungszauber. Passt seine
-- Zauber-ID zum Rezept eines laufenden eigenen Auftrags, steigt ein Zaehler.
--
-- Der bleibt bewusst LOKAL und geht nie ins Netz: Vierzig Urnen waeren sonst
-- vierzig Rundrufe, und ein Gildenauftrag ist eine Absprache zwischen
-- Menschen - gemeldet wird auf Klick, so wie bisher. Der Zaehler fuellt nur
-- die Meldung vor und steht in der Zeile.
function GC.Orders:GetPendingCrafts()
    local settings = GC.DB:GetSettings()
    settings.pendingCrafts = settings.pendingCrafts or {}
    return settings.pendingCrafts
end

function GC.Orders:GetPendingCraftCount(orderID)
    return tonumber(self:GetPendingCrafts()[tostring(orderID or "")]) or 0
end

function GC.Orders:ClearPendingCrafts(orderID)
    self:GetPendingCrafts()[tostring(orderID or "")] = nil
end

-- Ein erfolgreicher Herstellungszauber. Sucht die eigenen laufenden Auftraege
-- nach dem passenden Rezept ab und zaehlt hoch; liefert die Zahl der
-- betroffenen Auftraege.
function GC.Orders:NoteCraftedSpell(spellID)
    spellID = tonumber(spellID)
    if not spellID or not GC.Workshop then
        return 0
    end
    local ownTag = GC.DB:GetAccountTag()
    local pending = self:GetPendingCrafts()
    local counted = 0
    for orderID, order in pairs(self:GetStore()) do
        if (order.status == "WORKING" or order.status == "ACCEPTED")
            and GC.Util.Trim(order.acceptedByTag) ~= ""
            and order.acceptedByTag == ownTag then
            local recipe = GC.Workshop:GetOwnRecipe(order.recipeKey)
            if recipe and tonumber(recipe.recipeID) == spellID then
                local quantity = tonumber(order.quantity) or 1
                local already = tonumber(order.craftedCount) or 0
                -- Ueber die Bestellmenge hinaus wird nicht gezaehlt: Wer
                -- nebenher fuer sich selbst fertigt, soll den Auftrag nicht
                -- ueberfuellt melden.
                local room = math.max(0, quantity - already - (tonumber(pending[orderID]) or 0))
                if room > 0 then
                    pending[orderID] = (tonumber(pending[orderID]) or 0) + 1
                    counted = counted + 1
                end
            end
        end
    end
    if counted > 0 then
        NotifyChanged()
    end
    return counted
end

function GC.Orders:CountDeclined()
    local count = 0
    local store = self:GetStore()
    for orderID in pairs(self:GetDeclined()) do
        local order = store[orderID]
        if order and order.status == "OPEN" then
            count = count + 1
        end
    end
    return count
end

function GC.Orders:Create(recipeKey, options)
    options = options or {}
    recipeKey = tostring(recipeKey or "")
    -- Zwei Wege in denselben Auftrag: aus dem Katalog (Rezept bekannt, samt
    -- Herstellerliste) oder als Freitext (Beruf bekannt, Rezept nicht).
    local freeProfession = self:GetFreeProfessionKey(recipeKey)
    local entry
    local wish
    if freeProfession then
        wish = Sanitized(options.freeName, MAX_NAME_BYTES)
        if GC.Util.Trim(wish) == "" then
            return false, "Schreib dazu, was du brauchst."
        end
    else
        entry = GC.Workshop:GetCatalogEntry(recipeKey)
        if not entry then
            return false, "Dieses Rezept steht nicht im Katalog der Gilde."
        end
        if #entry.crafters == 0 then
            return false, "Für dieses Rezept ist kein Hersteller bekannt."
        end
    end

    local ownName = GC:GetPlayerFullName()
    local ownTag = GC.DB:GetAccountTag()
    local openCount = 0
    for _, order in pairs(self:GetStore()) do
        if order.status == "OPEN" and order.createdByTag == ownTag then
            openCount = openCount + 1
        end
    end
    if openCount >= MAX_OPEN_PER_ACCOUNT then
        return false, "Höchstens " .. MAX_OPEN_PER_ACCOUNT .. " offene Aufträge je Account."
    end

    local model = options.materialModel
    if model ~= "A" and model ~= "B" and model ~= "C" then
        model = "A"
    end
    local delivery = options.delivery == "MAIL" and "MAIL" or "TRADE"

    -- Wunsch-Hersteller (optional): muss ein bekannter Hersteller des
    -- Rezepts sein, sonst waere die Reservierung eine Sackgasse. Beim
    -- Freitext gibt es keine Herstellerliste - dort bleibt das Feld leer.
    local preferred = not freeProfession and GC.Util.Trim(options.preferredCrafter or "") or ""
    if preferred ~= "" then
        local valid = false
        for _, crafterName in ipairs(entry.crafters) do
            if GC.Util.NormalizeName(crafterName)
                == GC.Util.NormalizeName(GC.Util.PlayerIdentityName(preferred)) then
                preferred = crafterName
                valid = true
                break
            end
        end
        if not valid then
            return false, "„" .. preferred .. "“ ist kein bekannter Hersteller dieses Rezepts."
        end
    end
    local now = GC.Util.Now()
    local order = {
        id = GC.Util.PlayerIdentityName(ownName) .. "-" .. tostring(now)
            .. "-" .. tostring(math.random(1000, 9999)),
        rev = 1,
        status = "OPEN",
        recipeKey = recipeKey,
        recipeName = wish or Sanitized(entry.name, MAX_NAME_BYTES),
        quantity = math.max(1, math.min(99, math.floor(tonumber(options.quantity) or 1))),
        createdBy = ownName,
        createdByTag = ownTag,
        createdAt = now,
        changedAt = now,
        materialModel = model,
        delivery = delivery,
        costLimit = model == "C" and math.max(0, math.floor(tonumber(options.costLimit) or 0)) or 0,
        tip = math.max(0, math.floor(tonumber(options.tip) or 0)),
        note = Sanitized(options.note, MAX_NOTE_BYTES),
        acceptedByTag = "",
        acceptedAt = 0,
        crafter = "",
        acceptedVia = "",
        actualCost = 0,
        reimbursedAt = 0,
        reimbursedPaid = 0,
        craftedCount = 0,
        preferredCrafter = Sanitized(preferred, 20),
        log = {},
    }
    AppendLog(order, now, ownName, "CRT",
        preferred ~= "" and ("Reserviert für " .. GC.Util.PlayerIdentityName(preferred)) or order.note)
    self:GetStore()[order.id] = order
    self:BroadcastOrder(order)
    NotifyChanged()
    return true, "Gildenauftrag erstellt: " .. order.recipeName .. " ×" .. order.quantity .. "."
end

function GC.Orders:Accept(orderID, crafterName)
    local order = self:GetOrder(orderID)
    if not order then
        return false, "Der Auftrag ist nicht mehr bekannt."
    end
    local candidates = self:GetOwnCrafters(order.recipeKey)
    if #candidates == 0 then
        return false, "Kein Charakter deines Accounts beherrscht dieses Rezept."
    end
    crafterName = GC.Util.Trim(crafterName)
    if crafterName == "" then
        crafterName = candidates[1]
    end
    local valid = false
    for _, candidate in ipairs(candidates) do
        if SameCharacter(candidate, crafterName) then
            valid = true
            crafterName = candidate
            break
        end
    end
    if not valid then
        return false, "Dieser Charakter gehört nicht zu deinem Account oder kann das Rezept nicht."
    end
    if order.createdByTag ~= "" and order.createdByTag == GC.DB:GetAccountTag() then
        return false, "Den eigenen Auftrag nimmt man nicht selbst an."
    end

    local previousStatus = order.status
    local ok, message = Transition(self, order, "ACC", GC:GetPlayerFullName(), nil, {
        crafter = crafterName,
        accountTag = GC.DB:GetAccountTag(),
    })
    if not ok then
        return false, message
    end
    self:BroadcastOrder(order)
    self:NoteStatusChanged(order, previousStatus)
    NotifyChanged()
    return true, "Angenommen. Es fertigt: " .. GC.Util.PlayerIdentityName(crafterName) .. "."
end

local SIMPLE_ACTIONS = {
    MarkMaterialsComplete = { event = "MAT", done = "Materialien als vollständig gemeldet." },
    MarkShipped = { event = "SNT", done = "Als versandt gemeldet." },
    MarkReceived = { event = "RCV", done = "Erhalt bestätigt." },
    ConfirmReimbursed = { event = "RMR", done = "Erstattung bestätigt – Auftrag abgeschlossen." },
    Cancel = { event = "CXL", done = "Auftrag abgebrochen." },
}

for methodName, definition in pairs(SIMPLE_ACTIONS) do
    GC.Orders[methodName] = function(self, orderID, note)
        local order = self:GetOrder(orderID)
        if not order then
            return false, "Der Auftrag ist nicht mehr bekannt."
        end
        local previousStatus = order.status
        local ok, message = Transition(self, order, definition.event,
            GC:GetPlayerFullName(), nil, { note = note })
        if not ok then
            return false, message
        end
        self:BroadcastOrder(order)
        self:NoteStatusChanged(order, previousStatus)
        NotifyChanged()
        return true, definition.done
    end
end

function GC.Orders:MarkCrafted(orderID, actualCost, note, craftedCount)
    local order = self:GetOrder(orderID)
    if not order then
        return false, "Der Auftrag ist nicht mehr bekannt."
    end
    local previousStatus = order.status
    local ok, message = Transition(self, order, "CRA", GC:GetPlayerFullName(), nil, {
        actualCost = actualCost,
        note = note,
        craftedCount = craftedCount,
    })
    if not ok then
        return false, message
    end
    -- Gemeldet ist gemeldet: Der lokale Mitzaehler faengt danach bei null an,
    -- sonst stuende dieselbe Fertigung zweimal im Vorschlag.
    self:ClearPendingCrafts(orderID)
    self:BroadcastOrder(order)
    self:NoteStatusChanged(order, previousStatus)
    NotifyChanged()
    if order.status == "WORKING" then
        return true, "Zwischenstand gemeldet: " .. (order.craftedCount or 0)
            .. " von " .. (order.quantity or 1) .. "."
    end
    return true, "Als gefertigt gemeldet."
end

-- Erstattung mit Betrag: ohne Angabe der offene Rest, mit Angabe eine
-- Teilzahlung. Erst wenn nichts mehr offen ist, wandert der Auftrag zum
-- Auftragnehmer zur Bestätigung.
function GC.Orders:MarkReimbursed(orderID, amount, note)
    local order = self:GetOrder(orderID)
    if not order then
        return false, "Der Auftrag ist nicht mehr bekannt."
    end
    local previousStatus = order.status
    local ok, message = Transition(self, order, "RMB", GC:GetPlayerFullName(), nil, {
        amount = amount,
        note = note,
    })
    if not ok then
        return false, message
    end
    self:BroadcastOrder(order)
    self:NoteStatusChanged(order, previousStatus)
    NotifyChanged()
    if (order.reimbursedAt or 0) > 0 then
        return true, "Erstattung vollständig überwiesen."
    end
    return true, "Teilzahlung vermerkt – offen: "
        .. GC.Orders.FormatMoney((order.actualCost or 0) - (order.reimbursedPaid or 0)) .. "."
end

function GC.Orders:Return(orderID, note, acceptorLeft)
    local order = self:GetOrder(orderID)
    if not order then
        return false, "Der Auftrag ist nicht mehr bekannt."
    end
    local ok, message = Transition(self, order, "RET", GC:GetPlayerFullName(), nil, {
        note = note,
        acceptorLeft = acceptorLeft == true,
    })
    if not ok then
        return false, message
    end
    self:BroadcastOrder(order)
    NotifyChanged()
    return true, "Der Auftrag ist wieder offen."
end

function GC.Orders:AddNote(orderID, note)
    local order = self:GetOrder(orderID)
    if not order then
        return false, "Der Auftrag ist nicht mehr bekannt."
    end
    local ok, message = Transition(self, order, "NOT", GC:GetPlayerFullName(), nil, { note = note })
    if not ok then
        return false, message
    end
    self:BroadcastOrder(order)
    NotifyChanged()
    return true, "Notiz hinterlassen."
end

-- Steht der Rückfall-Knopf dem Auftraggeber offen? (3 Tage Stillstand oder
-- Auftragnehmer nicht mehr in der Gilde.)
function GC.Orders:IsStale(order)
    if not order or (order.status ~= "ACCEPTED" and order.status ~= "WORKING") then
        return false
    end
    if (GC.Util.Now() - (order.changedAt or 0)) >= STALE_ACCEPT_SECONDS then
        return true
    end
    return self:HasAcceptorLeftGuild(order)
end

function GC.Orders:HasAcceptorLeftGuild(order)
    if not order or GC.Util.Trim(order.crafter) == "" then
        return false
    end
    if #GC.Roster.members == 0 then
        -- Ohne geladenen Roster keine Aussage - lieber kein falscher Rückfall.
        return false
    end
    return GC.Roster:GetMember(order.crafter) == nil
        and GC.Roster:GetMember(order.acceptedVia) == nil
end

-- === Empfang ================================================================

local function OrderExpired(createdAt)
    return (GC.Util.Now() - (tonumber(createdAt) or 0)) > OPEN_TTL
end

function GC.Orders:ReceiveCore(fields, sender)
    local orderID = GC.Util.Trim(fields[4])
    if orderID == "" then
        return false
    end
    local createdBy = fields[8]
    -- Kerne duerfen auch von Dritten kommen: Jeder Client ist Kurier fuer
    -- Auftraege, die er kennt (Login-Push und Abgleich-Antworten). Das ist
    -- dieselbe Vertrauensbasis wie beim Werkstatt-Sync, der Rezeptdaten
    -- anderer ebenfalls weiterreicht - Absender sind immer Gildenmitglieder
    -- (Gildenkanal bzw. gepruefte Fluesternachricht). Die fruehere Regel
    -- "Absender muss der Auftraggeber sein" verwarf genau diese Kurierpakete
    -- und liess Abgleich-Antworten nur eigene Auftraege durchbringen.
    local store = self:GetStore()
    if store[orderID] then
        return true
    end
    local createdAt = tonumber(fields[10]) or 0
    if OrderExpired(createdAt) then
        -- Verspätete Wiederbelebung eines längst verfallenen Auftrags.
        return false
    end
    store[orderID] = {
        id = orderID,
        rev = 0, -- der Zustand kommt mit der U-Nachricht
        status = "OPEN",
        recipeKey = GC.Util.Trim(fields[5]),
        recipeName = Sanitized(fields[6], MAX_NAME_BYTES),
        quantity = math.max(1, math.min(99, math.floor(tonumber(fields[7]) or 1))),
        createdBy = Sanitized(createdBy, MAX_NAME_BYTES),
        createdByTag = Sanitized(fields[9], 12),
        createdAt = createdAt,
        changedAt = createdAt,
        materialModel = (fields[11] == "B" or fields[11] == "C") and fields[11] or "A",
        delivery = fields[12] == "MAIL" and "MAIL" or "TRADE",
        costLimit = math.max(0, math.floor(tonumber(fields[13]) or 0)),
        tip = math.max(0, math.floor(tonumber(fields[14]) or 0)),
        note = Sanitized(fields[15], MAX_NOTE_BYTES),
        acceptedByTag = "",
        acceptedAt = 0,
        crafter = "",
        acceptedVia = "",
        actualCost = 0,
        reimbursedAt = 0,
        reimbursedPaid = 0,
        craftedCount = 0,
        preferredCrafter = Sanitized(fields[16], 20),
        log = {},
    }
    AppendLog(store[orderID], createdAt, createdBy, "CRT", store[orderID].note)
    return true
end

-- Die Doppelannahme: gleiche Revision, zwei Annehmende. Es gewinnt der
-- frühere Zeitstempel, bei Gleichstand die kleinere Account-Kennung - jeder
-- Client kommt ohne Rückfrage zum selben Ergebnis.
local function IncomingAcceptWins(order, incomingAt, incomingTag)
    local localAt = tonumber(order.acceptedAt) or 0
    incomingAt = tonumber(incomingAt) or 0
    if incomingAt ~= localAt then
        return incomingAt < localAt
    end
    return tostring(incomingTag) < tostring(order.acceptedByTag)
end

function GC.Orders:ReceiveState(fields, sender)
    local orderID = GC.Util.Trim(fields[4])
    local order = self:GetOrder(orderID)
    if not order then
        -- Der Kern zu diesem Auftrag fehlt hier - nachfordern statt schweigen.
        self:RequestRecovery()
        return false
    end
    local rev = tonumber(fields[5]) or 0
    local status = GC.Util.Trim(fields[6])
    if not STATUS[status] then
        return false
    end

    local incomingTag = Sanitized(fields[8], 12)
    local logAt = tonumber(fields[14])
    local logBy = GC.Util.Trim(fields[15])
    local logEvent = GC.Util.Trim(fields[16])
    local logNote = fields[17]

    if rev <= (tonumber(order.rev) or 0) then
        -- Gleiche Revision, widersprüchliche Annahme: die deterministische
        -- Regel entscheidet, und der lokale Verlierer räumt den Platz.
        if rev == (tonumber(order.rev) or 0)
            and status == "ACCEPTED" and order.status == "ACCEPTED"
            and incomingTag ~= "" and incomingTag ~= order.acceptedByTag
            and SameCharacter(fields[11], sender)
            and self:IsKnownCrafter(Sanitized(fields[10], MAX_NAME_BYTES), order.recipeKey)
            and IncomingAcceptWins(order, fields[9], incomingTag) then
            local lostOwn = order.acceptedByTag == GC.DB:GetAccountTag()
            order.acceptedByTag = incomingTag
            order.acceptedAt = tonumber(fields[9]) or 0
            order.crafter = Sanitized(fields[10], MAX_NAME_BYTES)
            order.acceptedVia = Sanitized(fields[11], MAX_NAME_BYTES)
            if logEvent ~= "" then
                AppendLog(order, logAt, logBy, logEvent, logNote)
            end
            if lostOwn then
                GC:Print(GC.Util.PlayerIdentityName(order.crafter)
                    .. " war schneller – der Auftrag „" .. (order.recipeName or "?")
                    .. "“ liegt wieder bei ihm.")
            end
            NotifyChanged()
            return true
        end
        return false
    end

    -- Berechtigung: Wer meldet diesen Schritt?
    if logEvent == "ACC" then
        local crafter = Sanitized(fields[10], MAX_NAME_BYTES)
        if not SameCharacter(fields[11], sender)
            or not self:IsKnownCrafter(crafter, order.recipeKey)
            or self:IsReservedForOther(order, crafter, tonumber(fields[9])) then
            return false
        end
    elseif logEvent == "MAT" or logEvent == "CRA" or logEvent == "SNT"
        or logEvent == "RMR" or logEvent == "RET" then
        if not self:IsAcceptorCharacter(order, sender)
            and not (logEvent == "RET" and self:IsCreatorCharacter(order, sender)) then
            return false
        end
    elseif logEvent == "RCV" or logEvent == "RMB" then
        if not self:IsCreatorCharacter(order, sender) then
            return false
        end
    elseif logEvent == "CXL" then
        if not self:IsCreatorCharacter(order, sender)
            and not self:CanAdministrate(sender) then
            return false
        end
    elseif logEvent == "NOT" then
        if not self:IsCreatorCharacter(order, sender)
            and not self:IsAcceptorCharacter(order, sender) then
            return false
        end
    end

    local previousStatus = order.status
    order.rev = rev
    order.status = status
    order.changedAt = tonumber(fields[7]) or GC.Util.Now()
    order.acceptedByTag = incomingTag
    order.acceptedAt = tonumber(fields[9]) or 0
    order.crafter = Sanitized(fields[10], MAX_NAME_BYTES)
    order.acceptedVia = Sanitized(fields[11], MAX_NAME_BYTES)
    order.actualCost = math.max(0, math.floor(tonumber(fields[12]) or 0))
    order.reimbursedAt = tonumber(fields[13]) or 0
    order.reimbursedPaid = math.max(0, math.floor(tonumber(fields[18]) or 0))
    order.craftedCount = math.max(0, math.floor(tonumber(fields[19]) or 0))
    if logEvent ~= "" then
        AppendLog(order, logAt, logBy, logEvent, logNote)
    end

    -- Nur eine Aenderung von jetzt wird gemeldet; ein Nachholstand vom Login
    -- laeuft still durch. Verbucht und angezeigt wird er trotzdem.
    local fresh = IsFreshChange(order.changedAt)
    if fresh then
        self:NotifyRemoteChange(order, previousStatus, logEvent, logBy)
    end
    self:NoteStatusChanged(order, previousStatus, fresh)
    NotifyChanged()
    return true
end

function GC.Orders:ReceiveLog(fields)
    local order = self:GetOrder(GC.Util.Trim(fields[4]))
    if not order then
        return false
    end
    local event = GC.Util.Trim(fields[7])
    if event == "" or not EVENT_LABELS[event] then
        return false
    end
    if AppendLog(order, tonumber(fields[5]), fields[6], event, fields[8]) then
        NotifyChanged()
        return true
    end
    return false
end

-- === Klangrückmeldung ======================================================
-- Owner-Wunsch: Stufenaufstieg bei neuen machbaren Aufträgen, Karten-Ping
-- beim Fortschritt eigener Aufträge, Questabschluss beim Abschluss - jedes
-- Ereignis in den Einstellungen umstellbar oder abschaltbar (leerer Wert).
local ORDER_SOUND_DEFAULTS = {
    newOrder = "LEVEL_UP",
    accepted = "IG_QUEST_ACTIVATE",
    progress = "MAP_PING",
    done = "IG_QUEST_LIST_COMPLETE",
}

function GC.Orders:PlayEventSound(event)
    if not GC.Chat then
        return false
    end
    local sounds = GC.DB:GetSettings().orderSounds or {}
    local key = sounds[event]
    if key == "" then
        return false
    end
    return GC.Chat:PlaySuccessSound(key or ORDER_SOUND_DEFAULTS[event]) == true
end

-- Zurücklegen und Abbrechen sind bewusst stumm - sie sind kein Fortschritt.
local PROGRESS_SOUND_STATUSES = {
    ACCEPTED = true, WORKING = true, CRAFTED = true, SHIPPED = true, RECEIVED = true,
}

function GC.Orders:PlayStatusSound(order, previousStatus)
    if not order or order.status == previousStatus then
        return
    end
    local involved = self:IsCreatorCharacter(order, GC:GetPlayerFullName())
        or (GC.Util.Trim(order.acceptedByTag) ~= ""
            and order.acceptedByTag == GC.DB:GetAccountTag())
    if not involved then
        return
    end
    if order.status == "DONE" then
        self:PlayEventSound("done")
    elseif order.status == "ACCEPTED" then
        -- Die Annahme klingt wie eine angenommene Quest (Owner-Wunsch),
        -- der uebrige Fortschritt pingt wie die Karte.
        self:PlayEventSound("accepted")
    elseif PROGRESS_SOUND_STATUSES[order.status] then
        self:PlayEventSound("progress")
    end
end

-- Dezente Chat-Hinweise: neue machbare Aufträge und Bewegungen an eigenen.
function GC.Orders:NotifyRemoteChange(order, previousStatus, logEvent, logBy)
    local ownTag = GC.DB:GetAccountTag()
    local ownName = GC:GetPlayerFullName()
    local involved = self:IsCreatorCharacter(order, ownName)
        or (GC.Util.Trim(order.acceptedByTag) ~= "" and order.acceptedByTag == ownTag)
    if not involved or order.status == previousStatus then
        return
    end
    local label = GC.OrderStatusLabels[order.status] or order.status
    GC:Print("Gildenauftrag „" .. (order.recipeName or "?") .. "“: " .. label
        .. (logBy ~= "" and (" (" .. GC.Util.PlayerIdentityName(logBy) .. ")") or "") .. ".")
end

function GC.Orders:NotifyNewOrder(order)
    if self:IsCreatorCharacter(order, GC:GetPlayerFullName()) then
        return
    end
    local candidates = self:GetOwnCrafters(order.recipeKey)
    if #candidates == 0 then
        return
    end
    -- Ist der Auftrag für jemand anderen reserviert, gibt es nur die
    -- Chatzeile - Klang und Meldung gehören dem Wunsch-Hersteller. Der
    -- bekommt dafür seine eigene "für dich"-Fassung (Owner-Wunsch).
    if self:IsReserved(order) then
        local mine = false
        for _, candidate in ipairs(candidates) do
            if SameCharacter(candidate, order.preferredCrafter) then
                mine = true
                break
            end
        end
        if not mine then
            GC:Print("Neuer Gildenauftrag „" .. (order.recipeName or "?")
                .. "“ – 24 h reserviert für "
                .. GC.Util.PlayerIdentityName(order.preferredCrafter) .. ".")
            return
        end
        GC:Print("Gildenauftrag für dich: „" .. (order.recipeName or "?") .. "“ von "
            .. GC.Util.PlayerIdentityName(order.createdBy or "?")
            .. " – reserviert für deinen "
            .. GC.Util.PlayerIdentityName(order.preferredCrafter) .. ".")
        self:PlayEventSound("newOrder")
        GC:FireCallback("ORDERS_BANNER", "Gildenauftrag für dich von "
            .. GC.Util.PlayerIdentityName(order.createdBy or "?"))
        return
    end
    GC:Print("Neuer Gildenauftrag: „" .. (order.recipeName or "?") .. "“ von "
        .. GC.Util.PlayerIdentityName(order.createdBy or "?") .. " – dein "
        .. GC.Util.PlayerIdentityName(candidates[1]) .. " kann das Rezept.")
    self:PlayEventSound("newOrder")
    -- Die Meldung nennt den Auftraggeber, aber kein Rezept - das steht im
    -- Chat und auf dem Board. Gleicher Absender wird in der Anzeige
    -- hochgezählt, verschiedene stapeln sich wie Scrolling Combat Text.
    GC:FireCallback("ORDERS_BANNER",
        "Neuer Gildenauftrag von " .. GC.Util.PlayerIdentityName(order.createdBy or "?"))
end

-- Wie viele andere Gildenmitglieder mit Guild Copilot Forever sind laut Roster gerade
-- online? Die Zahl traegt den Hinweis im Erstellen-Dialog: Ohne gemeinsame
-- Onlinezeit erreicht ein Auftrag niemanden - es gibt keinen Server, nur
-- Clients, die sich gegenseitig erzaehlen, was sie wissen.
function GC.Orders:GetOnlineAddonUserCount()
    local ownKey = GC.Util.NormalizeName(GC:GetPlayerFullName())
    local ownShortKey = GC.Util.NormalizeName(GC.Util.PlayerIdentityName(GC:GetPlayerFullName()))
    local counted = {}
    local count = 0
    for _, entry in pairs(GC.DB:GetGuild().addonUsers or {}) do
        if type(entry) == "table" and not counted[entry] then
            counted[entry] = true
            local key = GC.Util.NormalizeName(entry.name)
            if key ~= ownKey and key ~= ownShortKey then
                local member = GC.Roster:GetMember(entry.name)
                if member and member.online then
                    count = count + 1
                end
            end
        end
    end
    return count
end

-- === Abgleich ===============================================================

function GC.Orders:RequestSync()
    if not GC.Sync then
        return false
    end
    self.lastRequestAt = GC.Util.Now()
    -- Das vierte Feld war einmal ein Zeitstempel-Filter ("nur Neueres als …").
    -- Der Filter war ein Konstruktionsfehler: Die eigene juengste Aenderung
    -- maskierte alle aelteren Auftraege der anderen. Gesendet wird die 0 fuer
    -- Altclients, die das Feld noch lesen; beantwortet wird immer alles.
    return GC.Sync:Send(Join({ "O", SCHEMA(), "Q", "0" }))
end

-- Beim Login zusaetzlich der Gegenweg: laufende Auftraege als Push in den
-- Gildenkanal. Jeder Client ist damit Kurier: Wer einen Auftrag einmal
-- empfangen hat, traegt ihn zu jedem weiter, mit dem er online ist. So
-- erreicht auch der Auftrag von jemandem, der allein online war, die Gilde
-- ueber Dritte.
--
-- Die Kurierfunktion bleibt, sie darf aber nicht von allen gleichzeitig
-- ausgehen: Bis 0.9.96 pushte JEDER Client JEDEN bekannten laufenden Auftrag,
-- bei 60 Auftraegen 120 Pakete je Client und bei 250 Online 30.000 Broadcasts
-- fuer einen Inhalt, den fast alle laengst hatten. Jetzt gilt:
--
--   * Auftraege des eigenen Accounts (erstellt oder angenommen) gehen immer
--     raus. Fuer die ist dieser Client die Quelle - niemand sonst kann fuer
--     ihn einspringen, und genau sie sind der Grund fuer den Push.
--   * Fremde Auftraege nur, wenn dieser Client fuer deren AUFTRAGGEBER
--     gewaehlt ist. Die Wahl haengt bewusst am Auftraggeber und nicht am
--     eigenen Namen: So traegt jeden fremden Auftrag eine andere Handvoll
--     Clients weiter, statt dass immer dieselben drei die ganze Kurierarbeit
--     tun - und aus 250 Absendern je Auftrag werden drei.
--   * Hoechstens MAX_PUSH_ORDERS Auftraege je Push, eigene zuerst.
--
-- Ohne Verlaufszeilen, ueber die Bulk-Warteschlange.
function GC.Orders:PushOpenOrders()
    if not GC.Sync then
        return 0
    end
    local ownTag = GC.Util.Trim(GC.DB:GetAccountTag())
    local mine = {}
    local others = {}
    for _, order in pairs(self:GetStore()) do
        if not TERMINAL[order.status] then
            if ownTag ~= ""
                and (order.createdByTag == ownTag or order.acceptedByTag == ownTag) then
                mine[#mine + 1] = order
            elseif GC.Sync:IsElectedResponder(order.createdBy or "") then
                others[#others + 1] = order
            end
        end
    end
    -- Das Juengste zuerst: Ein gerade geaenderter Auftrag ist der, den die
    -- anderen am ehesten noch nicht haben.
    local function ByRecency(left, right)
        if (left.changedAt or 0) ~= (right.changedAt or 0) then
            return (left.changedAt or 0) > (right.changedAt or 0)
        end
        return tostring(left.id) < tostring(right.id)
    end
    table.sort(mine, ByRecency)
    table.sort(others, ByRecency)

    local pushed = 0
    for _, list in ipairs({ mine, others }) do
        for _, order in ipairs(list) do
            if pushed >= MAX_PUSH_ORDERS then
                return pushed
            end
            self:SendPayload(self:BuildCoreMessage(order), true, "GUILD")
            self:SendPayload(self:BuildStateMessage(order, nil), true, "GUILD")
            pushed = pushed + 1
        end
    end
    return pushed
end

-- Trifft ein Zustandswechsel zu einem unbekannten Auftrag ein, ist unterwegs
-- ein Kernpaket verloren gegangen. Einmal pro Minute darf deshalb eine
-- Nachforderung in die Gilde - die naechste Antwort bringt den ganzen Stand.
function GC.Orders:RequestRecovery()
    local now = GC.Util.Now()
    if (now - (self.lastRecoveryAt or 0)) < 60 then
        return false
    end
    self.lastRecoveryAt = now
    return GC.Sync and GC.Sync:Send(Join({ "O", SCHEMA(), "Q", "0" })) == true or false
end

-- Antwort auf eine Q-Anfrage: der Bestand ueber die Bulk-Warteschlange, Kern
-- und Zustand. Bewusst alles statt einer Differenz: Zeitstempel verschiedener
-- Absender sind nicht vergleichbar, und Revisionen plus Verlaufs-Dedup machen
-- Doppeltes ohnehin wirkungslos.
--
-- Drei Grenzen halten die Antwort klein. Bis 0.9.96 schickte JEDER Client den
-- KOMPLETTEN Bestand an JEDEN Anfragenden: 14 Pakete je Auftrag (Kern,
-- Zustand, bis zu 12 Verlaufszeilen), bei 60 Auftraegen 180 Pakete je Client,
-- bei 250 Online 45.000 Fluesterpakete je Login.
--
--   1. Die Wahl: Nur eine Handvoll Clients antwortet ueberhaupt. Die Nutzlast
--      ist bei allen dieselbe, 250 Kopien davon sind keine Sicherheit.
--   2. Keine Verlaufszeilen mehr. Sie waren 12 der 14 Pakete je Auftrag und
--      sind fuer den Abgleich entbehrlich: Kern und Zustand tragen den
--      Auftrag vollstaendig, der Verlauf ist reine Anzeige und faellt bei
--      jedem weiteren Schritt ohnehin wieder an. Die Zustandsnachricht bleibt
--      dabei OHNE Verlaufszeile - der Antwortende ist nur Kurier, und
--      ReceiveState bindet ein gemeldetes Ereignis an den Absender; mit einer
--      fremden Verlaufszeile wuerde das ganze Zustandspaket verworfen.
--   3. Hoechstens MAX_ANSWER_ORDERS Auftraege, die laufenden zuerst.
--
-- Die Drossel gilt je Anfragendem, damit zwei kurz nacheinander einloggende
-- Mitglieder beide ihre Antwort bekommen; der Zufallsversatz verhindert den
-- gleichzeitigen Chor mehrerer Antwortender.
function GC.Orders:AnswerRequest(_, requester)
    local guildKey = GC:GetGuildKey()
    local now = GC.Util.Now()
    self.answeredAt = type(self.answeredAt) == "table" and self.answeredAt or {}
    -- Sammelnd aufraeumen: Die Tabelle bekommt je Anfragendem einen Eintrag
    -- und wuchs bisher unbegrenzt - in einer 500er-Gilde stehen dort nach ein
    -- paar Abenden hunderte Namen, die laengst niemanden mehr drosseln.
    for key, at in pairs(self.answeredAt) do
        if (now - (tonumber(at) or 0)) > ANSWERED_MEMORY then
            self.answeredAt[key] = nil
        end
    end
    local requesterKey = GC.Util.NormalizeName(requester)
    if (now - (tonumber(self.answeredAt[requesterKey]) or 0)) < MIN_ANSWER_INTERVAL then
        return false
    end
    if not GC.Sync:IsElectedResponder(requester) then
        return false
    end
    local pending = {}
    for _, order in pairs(self:GetStore()) do
        pending[#pending + 1] = order
    end
    if #pending == 0 then
        return false
    end
    -- Laufende zuerst: Ein abgeschlossener Auftrag ist Archiv, ein laufender
    -- ist der, bei dem ein fehlendes Paket jemanden stehen laesst.
    table.sort(pending, function(left, right)
        local leftLive = TERMINAL[left.status] and 0 or 1
        local rightLive = TERMINAL[right.status] and 0 or 1
        if leftLive ~= rightLive then
            return leftLive > rightLive
        end
        if (left.changedAt or 0) ~= (right.changedAt or 0) then
            return (left.changedAt or 0) > (right.changedAt or 0)
        end
        return tostring(left.id) < tostring(right.id)
    end)
    self.answeredAt[requesterKey] = now

    local sendCount = math.min(#pending, MAX_ANSWER_ORDERS)
    local function SendAll()
        if GC:GetGuildKey() ~= guildKey then return end
        for index = 1, sendCount do
            local order = pending[index]
            self:SendPayload(self:BuildCoreMessage(order), true, "WHISPER", requester)
            self:SendPayload(self:BuildStateMessage(order, nil), true, "WHISPER", requester)
        end
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(1 + math.random() * 4, SendAll)
    else
        SendAll()
    end
    return true
end

function GC.Orders:OnMessage(message, sender, distribution)
    local fields = GC.Util.SplitFields(message)
    if fields[1] ~= "O" or tonumber(fields[2]) ~= GC.Constants.SCHEMA_VERSION then
        return false
    end
    local kind = fields[3]
    if kind == "F" then
        if GC.Util.Trim(fields[4]) == "" then return false end
        self.incoming = self.incoming or {}
        local chunk = message:match("^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|(.*)$")
        local payload = GC.Util.CollectTransfer(self.incoming,
            tostring(sender) .. "\1" .. fields[4], tonumber(fields[5]), tonumber(fields[6]), chunk, 16)
        if not payload then return false end
        payload = GC.Util.UnescapeField(payload)
        -- Never recurse into another fragment or replay a request as data.
        local inner = GC.Util.SplitFields(payload)
        if inner[3] ~= "C" and inner[3] ~= "U" and inner[3] ~= "L" then return false end
        return self:OnMessage(payload, sender, distribution)
    elseif kind == "C" then
        if self:ReceiveCore(fields, sender) then
            local order = self:GetOrder(fields[4])
            if order and (order.rev or 0) == 0 then
                -- Dieselbe Frist wie beim Zustand: Ein Auftrag von vorgestern
                -- ist keine Neuigkeit, nur weil wir ihn eben erst bekommen.
                if IsFreshChange(order.createdAt) then
                    self:NotifyNewOrder(order)
                end
                NotifyChanged()
            end
            return true
        end
        return false
    elseif kind == "U" then
        return self:ReceiveState(fields, sender)
    elseif kind == "L" then
        return self:ReceiveLog(fields)
    elseif kind == "Q" and distribution == "GUILD" then
        return self:AnswerRequest(fields[4], sender)
    end
    return false
end

GC:RegisterCallback("GUILD_CHANGED", GC.Orders, function(self)
    self.incoming = {}
    self.answeredAt = {}
end)

-- === Aufräumen ==============================================================

function GC.Orders:Prune()
    local store = self:GetStore()
    local now = GC.Util.Now()

    -- Offene Aufträge verfallen nach der TTL - bei jedem Client zur gleichen
    -- Regel, deshalb ohne Netznachricht.
    for orderID, order in pairs(store) do
        if order.status == "OPEN" and (now - (order.createdAt or 0)) > OPEN_TTL then
            store[orderID] = nil
        end
    end

    local terminal = {}
    local total = 0
    for _, order in pairs(store) do
        total = total + 1
        if TERMINAL[order.status] then
            terminal[#terminal + 1] = order
        end
    end
    table.sort(terminal, function(left, right)
        if (left.changedAt or 0) ~= (right.changedAt or 0) then
            return (left.changedAt or 0) < (right.changedAt or 0)
        end
        return tostring(left.id) < tostring(right.id)
    end)
    local removeTerminal = math.max(#terminal - HISTORY_CAP, total - TOTAL_CAP)
    for index = 1, math.min(removeTerminal, #terminal) do
        store[terminal[index].id] = nil
        total = total - 1
    end

    if total > TOTAL_CAP then
        local open = {}
        for _, order in pairs(store) do
            if order.status == "OPEN" then
                open[#open + 1] = order
            end
        end
        table.sort(open, function(left, right)
            if (left.createdAt or 0) ~= (right.createdAt or 0) then
                return (left.createdAt or 0) < (right.createdAt or 0)
            end
            return tostring(left.id) < tostring(right.id)
        end)
        for index = 1, math.min(#open, total - TOTAL_CAP) do
            store[open[index].id] = nil
        end
    end

    -- Ein Ablehnen lebt nur so lange wie sein Auftrag. Ohne dieses Aufräumen
    -- sammelte die Einstellungsdatei jede jemals weggeklickte Auftrags-ID.
    local declined = self:GetDeclined()
    for orderID in pairs(declined) do
        if not store[orderID] then
            declined[orderID] = nil
        end
    end

    -- Dasselbe fuer den Mitzaehler: Er gilt nur, solange der Auftrag laeuft.
    local pending = self:GetPendingCrafts()
    for orderID in pairs(pending) do
        local order = store[orderID]
        if not order or (order.status ~= "ACCEPTED" and order.status ~= "WORKING") then
            pending[orderID] = nil
        end
    end
end

-- Sortierte Sichten für Board und Tracker.
function GC.Orders:GetBoard()
    local ownTag = GC.DB:GetAccountTag()
    local ownName = GC:GetPlayerFullName()
    local mine = {}
    local open = {}
    local others = {}
    local closed = {}
    for _, order in pairs(self:GetStore()) do
        local actor, action = self:GetNextActor(order)
        local isCreator = self:IsCreatorCharacter(order, ownName)
        local isAcceptor = GC.Util.Trim(order.acceptedByTag) ~= ""
            and order.acceptedByTag == ownTag
        local row = {
            order = order,
            action = action,
            -- Wer als Nächstes dran ist, brauchen auch fremde Zeilen: Dort
            -- steht statt der Aufforderung, auf wen gewartet wird.
            actor = actor,
            yourTurn = (actor == "CREATOR" and isCreator)
                or (actor == "ACCEPTOR" and isAcceptor),
            involved = isCreator or isAcceptor,
        }
        if TERMINAL[order.status] then
            if row.involved then
                closed[#closed + 1] = row
            end
        elseif order.status == "OPEN" and not isCreator then
            row.declined = self:IsDeclined(order.id)
            local candidates = self:GetOwnCrafters(order.recipeKey)
            row.canAccept = #candidates > 0
            if row.canAccept and self:IsReserved(order) then
                local mine = false
                for _, candidate in ipairs(candidates) do
                    if SameCharacter(candidate, order.preferredCrafter) then
                        mine = true
                        break
                    end
                end
                row.reserved = not mine
                row.canAccept = mine
            end
            open[#open + 1] = row
        elseif row.involved then
            mine[#mine + 1] = row
        else
            -- Laufende Aufträge, an denen dieser Account nicht beteiligt ist.
            -- Sie standen bis 0.9.109 unter "MEINE AUFTRÄGE" und verdrängten
            -- dort bei drei sichtbaren Zeilen die eigenen. Weggeworfen werden
            -- sie trotzdem nicht: Wer sieht, dass sein Wunschrezept gerade
            -- jemand anders fertigt, fragt nicht zum zweiten Mal danach.
            others[#others + 1] = row
        end
    end
    local function ByTurnThenTime(left, right)
        if left.yourTurn ~= right.yourTurn then
            return left.yourTurn
        end
        return (left.order.changedAt or 0) > (right.order.changedAt or 0)
    end
    table.sort(mine, ByTurnThenTime)
    table.sort(open, function(left, right)
        if left.canAccept ~= right.canAccept then
            return left.canAccept == true
        end
        return (left.order.createdAt or 0) > (right.order.createdAt or 0)
    end)
    local function ByChange(left, right)
        return (left.order.changedAt or 0) > (right.order.changedAt or 0)
    end
    table.sort(others, ByChange)
    table.sort(closed, ByChange)
    return { mine = mine, open = open, others = others, closed = closed }
end

GC:RegisterCallback("PLAYER_LOGIN", GC.Orders, function(self)
    self:Prune()
end)

-- Der Herstellungszauber des eigenen Charakters. Ein einzelnes Ereignisabo,
-- das nur dann etwas tut, wenn ein laufender eigener Auftrag zum Zauber
-- passt - in jedem anderen Fall kostet es einen Tabellenzugriff.
local orderEvents = CreateFrame("Frame")
orderEvents:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
orderEvents:SetScript("OnEvent", function(_, _, unit, ...)
    if unit ~= "player" then
        return
    end
    -- Die Zauber-ID steht in jeder Spielfassung an letzter Stelle: in TBC
    -- Classic als (castGUID, spellID), in aelteren Classic-Staenden als
    -- (spellName, rank, lineID, spellID). Das letzte Argument zu nehmen ist
    -- deshalb richtiger als eine feste Position.
    local last = select("#", ...)
    local spellID = last > 0 and (select(last, ...)) or nil
    if GC.Client.IsSecret(spellID) then return end
    GC.Orders:NoteCraftedSpell(tonumber(spellID))
end)
