local _, GC = ...

GC.Workshop = {
    incoming = {},
    completedIncoming = {},
    syncQueue = {},
    bulkPending = 0,
    syncSending = false,
    scanPending = false,
    -- Berufe, die ein fremdes Manifest gemeldet hat und die hier noch fehlen.
    -- Sie sind der Unterschied zwischen "gerade ist nichts unterwegs" und
    -- "der Stand ist vollstaendig" - genau die Frage, die der
    -- Fortschrittsbalken beantworten soll.
    pendingWants = {},
    syncStats = {
        queued = 0,
        sent = 0,
        failed = 0,
        receivedProfessions = 0,
        receivedRecipes = 0,
        lastSender = "",
    },
}

local MAX_PAYLOAD_BYTES = 180
local LEGACY_MAX_PAYLOAD_BYTES = 170
local MAX_RECORD_BYTES = 165
local MAX_TRANSFER_PARTS = 300
-- Die Grenze schuetzt vor Speicherfrass durch Muellpakete, nicht vor der
-- eigenen Gilde - und stand mit 20 weit unter dem, was ein Login ausloest.
-- Gemessen: von 60 gleichzeitigen Absendern wurden 20 angenommen und 40 stumm
-- verworfen, ohne Wiederholung und ohne Meldung.
local MAX_INCOMING_TRANSFERS = 64
local INCOMING_TTL = 5 * 60
local MIN_REQUEST_REPLY_INTERVAL = 30
-- Die Merkliste beantworteter Werkstatt-Anfragen wuchs unbegrenzt: ein Eintrag
-- je Anfragendem, bei 500 Mitgliedern also 500 - obwohl ein Eintrag nach
-- MIN_REQUEST_REPLY_INTERVAL Sekunden nichts mehr bewirkt.
local MAX_REQUEST_REPLIES = 200
-- Streuzeit vor der eigenen Antwort auf eine Werkstatt-Anfrage. Jeder Client
-- traegt hier die Berufe seines EIGENEN Accounts bei, es antworten also alle -
-- verteilt statt gleichzeitig. Das Manifest ist klein (ein bis drei Pakete)
-- und darf eng streuen; der Vollversand an einen Altclient geht in Dutzenden
-- Paketen raus und bekommt deshalb ein Vielfaches an Fenster.
local MANIFEST_REPLY_SPREAD = 30
local FULL_REPLY_SPREAD = 120
-- Sammelfrist fuer das Verwerfen des Katalogindex, siehe
-- ScheduleCatalogInvalidation.
local CATALOG_INVALIDATE_DELAY = 0.5
local SCAN_RETRY_DELAYS = { 0.15, 0.45, 1.0, 2.0 }
-- Fehlende Rezepte werden gesammelt und mit Streuung nachgefordert, damit bei
-- vielen Mitgliedern nicht alle gleichzeitig dasselbe Rezept anfragen.
local MISSING_REQUEST_DELAY = 8
local MISSING_REQUEST_SUPPRESS = 60
local MAX_KEYS_PER_REQUEST = 40
local DEPARTED_PRUNE_INTERVAL = 60
-- So lange gilt ein aus dem Manifest gemeldeter Beruf als "kommt noch". Danach
-- ist er nicht mehr unterwegs, sondern ausgeblieben - er wandert in die
-- Fehlbilanz des Zyklus (GetLostWantCount) und in die Bestandsluecken, statt
-- lautlos zu verschwinden. Weil ein Ablauf jetzt sichtbar "unvollstaendig"
-- meldet, ist die Frist grosszuegiger als die alten 120 s: Manifestantwort
-- (bis 31 s Streuung), Schluessellisten-Anfrage und die Antwort durch einen
-- vollen Sendepuffer brauchen zusammen schon mal laenger.
local WANT_TTL = 180
-- Wie viele gewaehlte Antwortende ein Bestandsmanifest ("CM") schicken: das
-- Wissen, welche Hersteller es in der Gilde gibt, auch wenn deren Besitzer
-- offline sind. Owner-Grundsatz fuer alles Neue hier: Bei 250 Online in einer
-- 500er-Gilde antworten auf eine Frage ein, zwei Gewaehlte - nie der ganze
-- Raum durcheinander. Zwei statt einem, weil jeder nur nennen kann, was er
-- selbst schon empfangen hat.
local COVERAGE_RESPONDER_SLOTS = 2
-- Obergrenze der gemerkten Bestandsluecken. 35 aktive Charaktere mit je zwei,
-- drei Berufen sind gut hundert Eintraege; die Grenze schuetzt nur gegen
-- Muellfluten, nicht gegen normalen Betrieb.
local MAX_COVERAGE_GAPS = 400
-- Wie viele gewaehlte Boten eine Rezeptnachforderung ("N") aus ihrem Katalog
-- beantworten, wenn der Hersteller selbst nicht antwortet. Zwei statt drei:
-- Die Antwort ist ein voller Datentransfer, und dank der Doppelantwort-
-- Daempfung (PeerAnsweredSince) bleibt es meist bei einem.
local RELAY_DETAIL_SLOTS = 2
-- Die Merkliste unterdrueckter Rezeptanfragen wuchs bisher unbegrenzt: ein
-- Eintrag je Rezept, in einer grossen Gilde ueber Stunden mehrere tausend.
-- Sie wird deshalb aufgeraeumt, sobald sie zu gross wird.
local MAX_SUPPRESSED_REQUESTS = 600
-- Dasselbe fuer die Merkliste unterdrueckter SCHLUESSELLISTEN-Anfragen. Sie
-- bekommt einen Eintrag je Hersteller UND Beruf und wuchs als einzige noch
-- unbegrenzt: In einer Gilde mit 500 Mitgliedern und zwei Berufen je Spieler
-- sind das bis zu tausend Eintraege, von denen nach
-- MISSING_REQUEST_SUPPRESS Sekunden keiner mehr etwas unterdrueckt.
local MAX_SUPPRESSED_KEY_REQUESTS = 400

-- Wartezeiten. Umwandlungen, Spezialtuche und Sphaeren sind nicht dadurch
-- begrenzt, wer sie kann, sondern dadurch, wann er wieder darf - und genau das
-- wusste die Werkstatt bisher nicht.
--
-- Gemerkt wird ausschliesslich eine LAUFENDE Sperre. Die API schweigt, wenn
-- ein Rezept frei ist, und sie schweigt genauso, wenn es ueberhaupt keine
-- Wartezeit kennt: Beides ist von aussen nicht zu unterscheiden. Deshalb sagt
-- das Addon "gesperrt bis", niemals "frei".
--
-- Eine gemerkte Sperre altert anders als jede andere Zahl der Werkstatt. Sie
-- wird nicht falsch, sondern hoechstens zu guenstig: Hat der Hersteller nach
-- dem Ablesen erneut hergestellt, ist er SPAETER frei, nie frueher. Der
-- gespeicherte Zeitpunkt ist damit eine Untergrenze - und wird ueberall als
-- "fruehestens" beschriftet.
local MIN_COOLDOWN_SECONDS = 60
-- Die laengste Wartezeit in TBC sind vier Tage (Spezialtuche). Der Riegel gilt
-- fremden Absendern: Ohne ihn koennte ein fehlerhafter Client ein Rezept fuer
-- Jahre als gesperrt melden.
local MAX_COOLDOWN_SECONDS = 14 * 24 * 60 * 60
local MAX_COOLDOWNS_PER_CRAFTER = 40
local MAX_COOLDOWNS_PER_MESSAGE = 12
-- Gespeichert wird auf die Minute gerundet. Ohne das liefert jeder erneute
-- Scan derselben laufenden Sperre einen um Sekunden verschobenen Zeitpunkt,
-- und das Addon haelt jedes Mal fuer eine Aenderung, was keine ist.
local COOLDOWN_ROUNDING = 60

-- Rezeptschluessel sind Item- oder Zauber-IDs. Nach Typ gruppiert und als
-- Differenzen aufsteigender Zahlen kosten 294 Schluessel rund 590 Bytes statt
-- 34 KB voller Rezeptdaten - der Grund, weshalb ein Beruf beim Zweiten und
-- allen Folgenden nur noch aus Schluesseln besteht.
local function EncodeRecipeKeys(keys)
    local numeric = { I = {}, E = {} }
    local literal = {}
    for _, recipeKey in ipairs(keys) do
        local prefix, digits = tostring(recipeKey):match("^([IE])(%d+)$")
        if prefix and #digits <= 12 then
            local group = numeric[prefix]
            group[#group + 1] = tonumber(digits)
        elseif tostring(recipeKey):match("^N[%w]+$") then
            literal[#literal + 1] = tostring(recipeKey):sub(2)
        end
    end

    local parts = {}
    for _, prefix in ipairs({ "I", "E" }) do
        local group = numeric[prefix]
        if #group > 0 then
            table.sort(group)
            local deltas, previous = {}, 0
            for _, id in ipairs(group) do
                if id ~= previous then
                    deltas[#deltas + 1] = tostring(id - previous)
                    previous = id
                end
            end
            parts[#parts + 1] = prefix .. "=" .. table.concat(deltas, ".")
        end
    end
    if #literal > 0 then
        table.sort(literal)
        parts[#parts + 1] = "N=" .. table.concat(literal, ".")
    end
    return table.concat(parts, ";")
end

local function DecodeRecipeKeys(payload)
    local keys = {}
    for group in tostring(payload or ""):gmatch("[^;]+") do
        local prefix, values = group:match("^([IEN])=(.*)$")
        if prefix == "N" then
            for name in tostring(values):gmatch("[^.]+") do
                keys[#keys + 1] = "N" .. name
            end
        elseif prefix then
            local current = 0
            for delta in tostring(values):gmatch("[^.]+") do
                local step = tonumber(delta)
                if not step or step < 0 then
                    break
                end
                current = current + step
                if current > 0 then
                    keys[#keys + 1] = prefix .. tostring(current)
                end
            end
        end
    end
    return keys
end

-- Nach aussen sichtbar, damit die Tests die Kodierung direkt pruefen koennen.
GC.Workshop.EncodeRecipeKeys = function(_, keys)
    return EncodeRecipeKeys(keys)
end
GC.Workshop.DecodeRecipeKeys = function(_, payload)
    return DecodeRecipeKeys(payload)
end

-- Uebertragen wird die RESTZEIT, nicht der Zeitpunkt. Zwei Rechner koennen
-- verschieden gehen, und ein absoluter Zeitstempel wuerde diesen Fehler
-- unbesehen uebernehmen - ausgerechnet bei einer Angabe, die nur als
-- Zeitpunkt etwas wert ist. Der Empfaenger rechnet die Restzeit mit seiner
-- eigenen Uhr um; die Sekunden Uebertragungsweg fallen bei Wartezeiten von
-- Stunden nicht ins Gewicht.
local function EncodeCooldowns(entries, now)
    local parts = {}
    for _, entry in ipairs(entries or {}) do
        local remaining = math.floor((tonumber(entry.readyAt) or 0) - now)
        if remaining >= MIN_COOLDOWN_SECONDS and remaining <= MAX_COOLDOWN_SECONDS then
            parts[#parts + 1] = tostring(entry.key) .. ":" .. tostring(remaining)
        end
    end
    return table.concat(parts, ";")
end

local function DecodeCooldowns(payload, now)
    local entries = {}
    for record in tostring(payload or ""):gmatch("[^;]+") do
        local recipeKey, secondsText = record:match("^([IEN]%w+):(%d+)$")
        local remaining = tonumber(secondsText)
        if recipeKey and remaining and #recipeKey <= 60
            and remaining >= MIN_COOLDOWN_SECONDS and remaining <= MAX_COOLDOWN_SECONDS then
            entries[#entries + 1] = { key = recipeKey, readyAt = now + remaining }
        end
    end
    return entries
end

local function NormalizeKey(value)
    value = GC.Util.Trim(value):lower()
    value = value:gsub("ä", "a"):gsub("ö", "o"):gsub("ü", "u"):gsub("ß", "ss")
    value = value:gsub("[^%w]", "")
    -- Verschiedene Schreibweisen desselben Berufs muessen denselben Filter-
    -- und Speicherschluessel ergeben: die Alltagsform "Alchemie" neben dem
    -- Clientnamen "Alchimie", vor allem aber die englischen Namen - ein
    -- englischer Client scannt "Enchanting", und ohne diese Zuordnung stand
    -- dieselbe Verzauberkunst doppelt im Katalog. Die Tabelle steht in
    -- Constants.lua bei den ProfessionDefinitions.
    return GC.ProfessionKeyByAlias[value] or value
end

local function ItemIDFromLink(link)
    return tonumber(tostring(link or ""):match("item:(%d+)"))
end

local function RecipeIDFromLink(link)
    return tonumber(tostring(link or ""):match("enchant:(%d+)"))
        or tonumber(tostring(link or ""):match("spell:(%d+)"))
end

local function SanitizedName(value)
    value = GC.Util.Trim(value)
    value = value:gsub("[,;|%%]", " ")
    return GC.Util.SafeChatText(value, 52)
end

local function SortedKeys(values)
    local keys = {}
    for key in pairs(values or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function RecipeFingerprint(profession)
    local records = {}
    for _, recipeKey in ipairs(SortedKeys(profession.recipes)) do
        local recipe = profession.recipes[recipeKey]
        local reagents = {}
        for _, reagent in ipairs(recipe.reagents or {}) do
            reagents[#reagents + 1] = tostring(reagent.itemID or 0) .. ":" .. tostring(reagent.count or 0)
        end
        records[#records + 1] = table.concat({
            recipeKey,
            tostring(recipe.itemID or 0),
            recipe.name or "",
            table.concat(reagents, "."),
        }, ",")
    end
    return table.concat(records, ";")
end

local function FingerprintHash(value)
    local hash = 5381
    for index = 1, #tostring(value or "") do
        hash = ((hash * 33) + tostring(value):byte(index)) % 2147483647
    end
    return tostring(hash)
end

-- Welcher von zwei Rezeptstaenden gewinnt? Der neuere - und bei gleicher
-- Sekunde der mit dem groesseren Fingerabdruck.
--
-- Dieselbe Regel und derselbe Grund wie bei der Gildenbank: updatedAt kennt
-- nur ganze Sekunden (GetServerTime), zwei Staende derselben Sekunde sind also
-- alltaeglich. Bis 0.9.90 hatten die beiden Seiten hier verschiedene Regeln -
-- das Manifest forderte bei JEDER Abweichung an (auch bei einem aelteren
-- Stand), waehrend die Uebernahme nur strikt aeltere verwarf. Ergebnis: Ein
-- Stand gleicher Sekunde wurde angefordert und ueberschrieb dann den
-- vorhandenen, und ein aelterer wurde angefordert und verworfen - immer
-- wieder, bei jedem Manifest.
--
-- Entscheidend ist wie dort, dass BEIDE Seiten dieselbe Funktion benutzen.
local function ProfessionWins(updatedAt, fingerprintHash, knownAt, knownHash)
    updatedAt = tonumber(updatedAt) or 0
    knownAt = tonumber(knownAt) or 0
    if updatedAt ~= knownAt then
        return updatedAt > knownAt
    end
    return tostring(fingerprintHash or "") > tostring(knownHash or "")
end

local function RecipeCount(profession)
    local count = 0
    for _ in pairs(profession and profession.recipes or {}) do
        count = count + 1
    end
    return count
end

local function RecipeKeyCount(profession)
    local count = 0
    for _ in pairs(profession and profession.recipeKeys or {}) do
        count = count + 1
    end
    return count
end

local function BuildRecipeRecord(recipe, recordLimit)
    recordLimit = math.min(MAX_RECORD_BYTES, tonumber(recordLimit) or MAX_RECORD_BYTES)
    local reagentTokens = {}
    for _, reagent in ipairs(recipe.reagents or {}) do
        if tonumber(reagent.itemID) then
            reagentTokens[#reagentTokens + 1] = tostring(reagent.itemID) .. ":" .. tostring(reagent.count or 1)
        end
    end

    local name = SanitizedName(recipe.name)
    local function Compose()
        return table.concat({
            recipe.key or "",
            tostring(recipe.itemID or 0),
            name,
            table.concat(reagentTokens, "."),
        }, ",")
    end

    local record = Compose()
    while #record > recordLimit and #reagentTokens > 0 do
        table.remove(reagentTokens)
        record = Compose()
    end
    while #record > recordLimit and #name > 8 do
        name = GC.Util.SafeChatText(name, #name - 4)
        record = Compose()
    end
    if #record > recordLimit then
        name = ""
        record = Compose()
    end
    return #record <= recordLimit and record or nil
end

local function BuildCompactRecipeRecord(recipe, recordLimit)
    recordLimit = math.min(MAX_RECORD_BYTES, tonumber(recordLimit) or MAX_RECORD_BYTES)
    local recipeKey = GC.Util.SafeChatText(tostring(recipe.key or ""), 36)
    if recipeKey == "" then
        return nil
    end

    local name = ""
    if not recipeKey:match("^I%d+$") then
        name = SanitizedName(recipe.name)
    end

    local reagentTokens = {}
    for _, reagent in ipairs(recipe.reagents or {}) do
        local itemID = tonumber(reagent.itemID)
        if itemID then
            local count = math.max(1, math.floor(tonumber(reagent.count) or 1))
            reagentTokens[#reagentTokens + 1] = tostring(itemID) .. ":" .. tostring(count)
        end
    end

    local function Compose()
        return table.concat({ recipeKey, name, table.concat(reagentTokens, ".") }, ",")
    end

    local record = Compose()
    while #record > recordLimit and #reagentTokens > 0 do
        table.remove(reagentTokens)
        record = Compose()
    end
    while #record > recordLimit and #name > 8 do
        name = GC.Util.SafeChatText(name, #name - 4)
        record = Compose()
    end
    if #record > recordLimit then
        name = ""
        record = Compose()
    end
    return #record <= recordLimit and record or nil
end

local function BuildMessage(fields)
    local escaped = {}
    for index, value in ipairs(fields) do
        escaped[index] = GC.Util.EscapeField(value)
    end
    return table.concat(escaped, "|")
end

-- Der echte Gegenstandsname aus dem Item-Cache des Clients - oder nil, wenn
-- der Client den Gegenstand (noch) nicht kennt. Schon der Aufruf stoesst das
-- Nachladen beim Server an; die Ankunft meldet GET_ITEM_INFO_RECEIVED, und
-- ScheduleNameRefresh baut den Katalogindex danach neu auf.
local function LookupItemName(itemID)
    if tonumber(itemID) and tonumber(itemID) > 0 and GC.API.GetItemInfo then
        local name = GC.API.GetItemInfo(tonumber(itemID))
        if name and name ~= "" then
            return name
        end
    end
    return nil
end

-- Ein gespeicherter Name kann der Notbehelf eines frueheren Empfangs sein
-- ("Item #25708"): Der Absender schickt nur die ID, und der Cache kannte den
-- Gegenstand beim Dekodieren noch nicht. Solche Platzhalter sind keine
-- Auskunft und duerfen nie als Fallback dienen - sonst ueberleben sie jedes
-- Nachladen und stehen dauerhaft in den Rezeptdetails.
local function IsPlaceholderName(name)
    name = tostring(name or "")
    return name == "" or name:match("^Item #%d+$") ~= nil
end

local function ResolveItemName(itemID, fallback)
    local name = LookupItemName(itemID)
    if name then
        return name
    end
    if not IsPlaceholderName(fallback) then
        return fallback
    end
    return tonumber(itemID) and ("Item #" .. itemID) or "Unbekannt"
end

local function ResolveRecipeName(recipeKey, fallback)
    local itemID = tonumber(tostring(recipeKey or ""):match("^I(%d+)$"))
    if itemID then
        return ResolveItemName(itemID, fallback)
    end

    local spellID = tonumber(tostring(recipeKey or ""):match("^E(%d+)$"))
    if spellID and GC.API.Has("GetSpellInfo") then
        local ok, name = pcall(GC.API.GetSpellInfo, spellID)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return fallback or tostring(recipeKey or "Unbekanntes Rezept")
end

-- Fuehrt die Berufe eines eigenen Werkstatt-Datensatzes einmalig auf die
-- kanonischen Schluessel zusammen. Frueher stand hier nur der Sonderfall
-- Alchemie/Alchimie; mit den englischen Clients kam dieselbe Lage fuer jeden
-- Beruf dazu ("enchanting" neben "verzauberkunst"). Liegen beide Schreibweisen
-- vor, werden die Rezepte vereinigt - beide sind eigene Scans, keiner luegt.
local function CanonicalizeOwnProfessions(workshop)
    if workshop.professionKeysCanonical then
        return
    end
    workshop.professionKeysCanonical = true
    local professions = workshop.professions or {}
    -- Erst sammeln, dann umhaengen: Waehrend eines pairs-Durchlaufs einen
    -- NEUEN Schluessel zu setzen ist in Lua nicht definiert.
    local moves = {}
    for key, profession in pairs(professions) do
        local canonical = NormalizeKey(key)
        if canonical ~= key and type(profession) == "table" then
            moves[#moves + 1] = { from = key, to = canonical, profession = profession }
        end
    end
    for _, move in ipairs(moves) do
        local target = professions[move.to]
        if not target then
            move.profession.key = move.to
            move.profession.name = GC.CanonicalProfessionName(move.profession.name)
                or move.profession.name
            professions[move.to] = move.profession
        elseif target ~= move.profession then
            target.recipes = target.recipes or {}
            for recipeKey, recipe in pairs(move.profession.recipes or {}) do
                target.recipes[recipeKey] = target.recipes[recipeKey] or recipe
            end
            target.fingerprint = RecipeFingerprint(target)
            target.fingerprintHash = FingerprintHash(target.fingerprint)
        end
        professions[move.from] = nil
    end
end

function GC.Workshop:GetOwnData()
    local profile = GC.Profile:Get()
    profile.workshop = profile.workshop or { professions = {} }
    profile.workshop.professions = profile.workshop.professions or {}
    CanonicalizeOwnProfessions(profile.workshop)
    return profile.workshop
end

-- Der eigene Werkstatt-Datensatz zu einem Berufsnamen, egal in welcher
-- Schreibweise er ankommt (Alchemie/Alchimie). Für die Profilseite: Skill,
-- Rezeptzahl und Stand des letzten Einlesens.
function GC.Workshop:GetOwnProfession(professionName)
    if GC.Util.Trim(professionName or "") == "" then
        return nil
    end
    return self:GetOwnData().professions[NormalizeKey(professionName)]
end

-- Der gildenweite Bestand besteht aus zwei getrennten Teilen: einem
-- Rezeptkatalog, in dem jedes Rezept genau einmal steht, und einem Index, wer
-- welches Rezept kann. Vor dieser Trennung hielt jeder Crafter eine eigene
-- Vollkopie aller Rezepte - bei hundert Mitgliedern ein Vielfaches an
-- Uebertragung und Speicher fuer immer dieselben Daten.
function GC.Workshop:GetGuildWorkshop()
    local workshop = GC.DB:GetGuild().workshop
    workshop.crafters = workshop.crafters or {}
    workshop.catalog = workshop.catalog or {}
    if not workshop.catalogMigrated then
        workshop.catalogMigrated = true
        for _, crafter in pairs(workshop.crafters) do
            for professionKey, profession in pairs((type(crafter) == "table" and crafter.professions) or {}) do
                if type(profession) == "table" and type(profession.recipes) == "table" then
                    profession.recipeKeys = profession.recipeKeys or {}
                    for recipeKey, recipe in pairs(profession.recipes) do
                        profession.recipeKeys[recipeKey] = true
                        if not workshop.catalog[recipeKey] and type(recipe) == "table" then
                            workshop.catalog[recipeKey] = {
                                key = recipeKey,
                                itemID = recipe.itemID,
                                recipeID = recipe.recipeID,
                                name = recipe.name,
                                professionKey = professionKey,
                                profession = profession.name or recipe.profession,
                                reagents = recipe.reagents or {},
                            }
                        end
                    end
                    profession.recipes = nil
                end
            end
        end
    end

    -- Bis 0.9.87 stand der eigene Charakter mit Realmanteil in der Tabelle
    -- ("alex-ewigerhain"), von fremden Clients gemeldete Herstellernamen aber
    -- ohne ("alex"). Derselbe Spieler fuellte damit zwei Zeilen. Die alten
    -- Schluessel werden einmalig auf den Kurznamen zusammengefuehrt; bei
    -- doppelten Berufen gewinnt der neuere Stand.
    if not workshop.crafterKeysMigrated then
        workshop.crafterKeysMigrated = true
        -- Erst sammeln, dann umhaengen: Waehrend eines pairs-Durchlaufs einen
        -- NEUEN Schluessel zu setzen ist in Lua nicht definiert.
        local moves = {}
        for key, crafter in pairs(workshop.crafters) do
            local shortKey = GC.Util.PlayerKey(key)
            if shortKey ~= "" and shortKey ~= key and type(crafter) == "table" then
                moves[#moves + 1] = { from = key, to = shortKey, crafter = crafter }
            end
        end
        for _, move in ipairs(moves) do
            local target = workshop.crafters[move.to]
            if type(target) ~= "table" then
                workshop.crafters[move.to] = move.crafter
            else
                target.professions = target.professions or {}
                for professionKey, profession in pairs(move.crafter.professions or {}) do
                    local known = target.professions[professionKey]
                    if not known
                        or (tonumber(profession.updatedAt) or 0) > (tonumber(known.updatedAt) or 0) then
                        target.professions[professionKey] = profession
                    end
                end
            end
            workshop.crafters[move.from] = nil
        end
    end

    -- Von englischen Clients gemeldete Berufe standen bis 0.9.101 unter ihrem
    -- englischen Schluessel ("enchanting") NEBEN dem deutschen Bestand
    -- ("verzauberkunst") - im Katalogkopf zaehlte dieselbe Gilde dadurch 16
    -- Berufe statt 11. Beide Schreibweisen werden einmalig zusammengefuehrt;
    -- bei doppelten Staenden desselben Herstellers gewinnt der nach derselben
    -- Regel, nach der auch Manifeste und Uebernahme entscheiden.
    if not workshop.professionKeysCanonical then
        workshop.professionKeysCanonical = true
        for _, crafter in pairs(workshop.crafters) do
            local professions = type(crafter) == "table" and crafter.professions
            if professions then
                local moves = {}
                for key, profession in pairs(professions) do
                    local canonical = NormalizeKey(key)
                    if canonical ~= key and type(profession) == "table" then
                        moves[#moves + 1] = { from = key, to = canonical, profession = profession }
                    end
                end
                for _, move in ipairs(moves) do
                    local known = professions[move.to]
                    if not known or ProfessionWins(move.profession.updatedAt,
                        move.profession.fingerprintHash, known.updatedAt, known.fingerprintHash) then
                        move.profession.key = move.to
                        move.profession.name = GC.CanonicalProfessionName(move.profession.name)
                            or move.profession.name
                        professions[move.to] = move.profession
                    end
                    professions[move.from] = nil
                end
            end
        end
        for _, entry in pairs(workshop.catalog) do
            if type(entry) == "table" then
                if entry.professionKey then
                    entry.professionKey = NormalizeKey(entry.professionKey)
                end
                entry.profession = GC.CanonicalProfessionName(entry.profession)
                    or entry.profession
            end
        end
    end

    -- Bekannte Bestandsluecken: Berufe, die es in der Gilde nachweislich gibt,
    -- deren Daten dieser Client aber noch nie empfangen hat (Naeheres bei
    -- NoteCoverageGap).
    workshop.coverageGaps = workshop.coverageGaps or {}
    return workshop
end

-- Ein Rezept wandert nur dann in den Katalog, wenn es dort fehlt oder bisher
-- ohne Reagenzien steckt. Rezeptdaten sind fuer alle identisch: der Schluessel
-- ist die Item- beziehungsweise Zauber-ID, die Reagenzien haengen nicht am
-- Spieler. Deshalb gibt es nichts abzuwaegen, wenn zwei Absender dasselbe
-- Rezept melden.
--
-- "deferInvalidate" ist fuer Aufrufer gedacht, die in einer Schleife ganze
-- Rezeptlisten einlagern: Sie stossen das Verwerfen des Katalogindex einmal am
-- Ende an, statt je Rezept. Ohne das Kennzeichen verwirft die Funktion selbst,
-- damit jeder andere Aufrufer wie bisher korrekt bleibt.
function GC.Workshop:StoreCatalogRecipe(recipe, professionKey, professionName, deferInvalidate)
    if type(recipe) ~= "table" or GC.Util.Trim(recipe.key) == "" then
        return false
    end
    local catalog = self:GetGuildWorkshop().catalog
    local existing = catalog[recipe.key]
    if existing and #(existing.reagents or {}) > 0 and #(recipe.reagents or {}) == 0 then
        return false
    end
    catalog[recipe.key] = {
        key = recipe.key,
        itemID = recipe.itemID,
        recipeID = recipe.recipeID,
        name = recipe.name,
        professionKey = professionKey or (existing and existing.professionKey),
        profession = professionName or (existing and existing.profession),
        reagents = recipe.reagents or (existing and existing.reagents) or {},
    }
    if not deferInvalidate then
        self:ScheduleCatalogInvalidation()
    end
    return true
end

-- Traegt ein, wer einen Beruf mit welchen Rezepten kann. "sharedBy" haelt fest,
-- welches Gildenmitglied den Eintrag eingebracht hat: Twinks stehen nicht im
-- Gildenroster und duerfen beim Aufraeumen nicht mit Ausgetretenen verwechselt
-- werden.
function GC.Workshop:ClaimRecipes(info)
    local crafterKey = GC.Util.PlayerKey(info.crafter)
    if crafterKey == "" or GC.Util.Trim(info.professionKey) == "" then
        return nil
    end
    -- Zweite Verteidigungslinie neben dem Empfangspfad: Was hier ankommt,
    -- landet kanonisch im Herstellerindex, gleich woher es kam.
    info.professionKey = NormalizeKey(info.professionKey)
    info.professionName = GC.CanonicalProfessionName(info.professionName)
        or info.professionName
    local workshop = self:GetGuildWorkshop()
    local crafter = workshop.crafters[crafterKey] or { professions = {} }
    crafter.name = info.crafter
    crafter.professions = crafter.professions or {}
    crafter.updatedAt = GC.Util.Now()
    if GC.Util.Trim(info.sharedBy) ~= "" then
        crafter.sharedBy = info.sharedBy
    end

    -- Ein aelterer Stand darf einen neueren nicht zurueckdrehen. Das trifft
    -- zwei reale Faelle: ein Paket, das sich im Gildenkanal verspaetet hat,
    -- und einen Zweitclient, der seit Stunden laeuft und seinen alten Stand
    -- weitermeldet. Beide haben bisher die Rezeptliste ueberschrieben - bei
    -- einer vollen Schluesselliste ("K") samt der Rezepte, die seitdem
    -- dazugelernt wurden.
    --
    -- Bei gleicher Sekunde entscheidet der Fingerabdruck - nach derselben
    -- Regel, nach der das Manifest ueberhaupt erst angefordert hat. Ein
    -- blosser Vergleich der Zeitstempel liess hier jeden Stand derselben
    -- Sekunde durch: Zwei verschiedene Rezeptstaende mit demselben Zeitstempel
    -- ueberschrieben einander, und wer zuletzt eintraf, gewann.
    local incomingAt = tonumber(info.updatedAt) or GC.Util.Now()
    local known = crafter.professions[info.professionKey]
    if known and not ProfessionWins(incomingAt, info.fingerprintHash,
        known.updatedAt, known.fingerprintHash) then
        workshop.crafters[crafterKey] = crafter
        self:ClearCoverageGapIfCovered(info.crafter, info.professionKey)
        return crafter
    end

    local recipeKeys = {}
    for _, recipeKey in ipairs(info.recipeKeys or {}) do
        recipeKeys[recipeKey] = true
    end
    crafter.professions[info.professionKey] = {
        key = info.professionKey,
        name = info.professionName,
        updatedAt = incomingAt,
        fingerprintHash = info.fingerprintHash,
        recipeKeys = recipeKeys,
    }
    workshop.crafters[crafterKey] = crafter
    self:ClearWanted(info.crafter, info.professionKey)
    self:ClearCoverageGapIfCovered(info.crafter, info.professionKey)
    self:ScheduleCatalogInvalidation()
    return crafter
end

-- Welche der gemeldeten Rezepte kennt dieser Client noch gar nicht? Nur fuer
-- die lohnt eine Nachforderung der vollen Daten - und zwar einmal gildenweit,
-- nicht einmal je Spieler.
function GC.Workshop:GetUnknownRecipeKeys(recipeKeys)
    local catalog = self:GetGuildWorkshop().catalog
    local own = self:GetOwnData().professions
    local missing = {}
    for _, recipeKey in ipairs(recipeKeys or {}) do
        local known = catalog[recipeKey] and #(catalog[recipeKey].reagents or {}) > 0
        if not known then
            for _, profession in pairs(own) do
                if (profession.recipes or {})[recipeKey] then
                    known = true
                    break
                end
            end
        end
        if not known then
            missing[#missing + 1] = recipeKey
        end
    end
    return missing
end

-- Fehlt zu einem gemeldeten Rezept die Datenzeile, wird sie beim Hersteller
-- nachgefordert - aber mit Streuung und nur einmal je Rezept. Sieht dieser
-- Client in der Zwischenzeit die Anfrage eines anderen oder trifft das Rezept
-- ein, entfaellt die eigene Anfrage. So bleibt es bei hundert Mitgliedern bei
-- wenigen Anfragen statt hundert gleichlautenden.
-- Abgelaufene Merker fliegen raus, sobald die Liste zu gross wird. Sie ist rein
-- lokal und lebt nur in dieser Sitzung, wuchs aber mit jedem je angefragten
-- Rezept weiter - in einer grossen Gilde ueber einen Raidabend hinweg um
-- mehrere tausend Eintraege.
-- Dieselbe Bauweise raeumt inzwischen auch die Merkliste beantworteter
-- Werkstatt-Anfragen auf; "maximum" sagt, ab welcher Groesse es losgeht.
local function PruneSuppressed(suppressed, ttl, maximum)
    local count = 0
    for _ in pairs(suppressed) do
        count = count + 1
    end
    if count <= (tonumber(maximum) or MAX_SUPPRESSED_REQUESTS) then
        return
    end
    local cutoff = GC.Util.Now() - ttl
    for key, at in pairs(suppressed) do
        if (tonumber(at) or 0) < cutoff then
            suppressed[key] = nil
        end
    end
end

function GC.Workshop:ScheduleMissingRecipeRequest(crafterName, recipeKeys)
    local missing = self:GetUnknownRecipeKeys(recipeKeys)
    if #missing == 0 or GC.Util.Trim(crafterName) == "" then
        return false
    end
    self.suppressedRequests = self.suppressedRequests or {}
    PruneSuppressed(self.suppressedRequests, MISSING_REQUEST_SUPPRESS)
    local now = GC.Util.Now()
    local pending = {}
    for _, recipeKey in ipairs(missing) do
        local suppressedAt = self.suppressedRequests[recipeKey]
        if not suppressedAt or (now - suppressedAt) > MISSING_REQUEST_SUPPRESS then
            pending[#pending + 1] = recipeKey
        end
    end
    if #pending == 0 then
        return false
    end
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return self:SendMissingRecipeRequest(crafterName, pending)
    end
    C_Timer.After(1 + math.random() * MISSING_REQUEST_DELAY, function()
        GC.Workshop:SendMissingRecipeRequest(crafterName, pending)
    end)
    return true
end

function GC.Workshop:SendMissingRecipeRequest(crafterName, recipeKeys)
    if not GC.Sync then
        return false
    end
    -- Zwischen Planung und Absenden kann das Rezept eingetroffen sein oder ein
    -- anderer die Anfrage gestellt haben.
    local stillMissing = self:GetUnknownRecipeKeys(recipeKeys)
    self.suppressedRequests = self.suppressedRequests or {}
    local now = GC.Util.Now()
    local wanted = {}
    for _, recipeKey in ipairs(stillMissing) do
        local suppressedAt = self.suppressedRequests[recipeKey]
        if not suppressedAt or (now - suppressedAt) > MISSING_REQUEST_SUPPRESS then
            wanted[#wanted + 1] = recipeKey
            if #wanted >= MAX_KEYS_PER_REQUEST then
                break
            end
        end
    end
    if #wanted == 0 then
        return false
    end
    for _, recipeKey in ipairs(wanted) do
        self.suppressedRequests[recipeKey] = now
    end
    local message = BuildMessage({
        "W",
        GC.Constants.SCHEMA_VERSION,
        "N",
        GC.Util.SafeChatText(GC.Util.Trim(crafterName), 40),
        EncodeRecipeKeys(wanted),
    })
    if #message > GC.Constants.MAX_CHAT_BYTES then
        return false
    end
    return GC.Sync:SendBulk(message, "GUILD")
end

function GC.Workshop:ScheduleScan()
    self:ScanOpenProfession()
    if self.scanPending then
        return
    end

    self.scanPending = true
    local attempt = 1
    local function RetryScan()
        GC.Workshop:ScanOpenProfession()
        attempt = attempt + 1
        local delay = SCAN_RETRY_DELAYS[attempt]
        if delay and C_Timer and C_Timer.After then
            C_Timer.After(delay, RetryScan)
        else
            GC.Workshop.scanPending = false
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(SCAN_RETRY_DELAYS[attempt], RetryScan)
    else
        self.scanPending = false
    end
end

-- Ein Berufsscan endet immer gleich: erst die Rezepte, dann die dabei
-- abgelesenen Sperren. Beides bleibt getrennt, weil eine Wartezeit den
-- Rezeptfingerabdruck nicht anfassen darf - sonst gaelte jeder Scan als
-- geaenderter Rezeptstand und zoege einen vollstaendigen Abgleich nach sich,
-- nur weil eine Umwandlung laeuft.
--
-- "cooldowns == nil" heisst "nicht abgelesen" und laesst den gespeicherten
-- Stand unangetastet; eine leere Tabelle heisst "abgelesen, nichts gesperrt"
-- und raeumt ihn ab. Der Unterschied ist der zwischen einer fehlenden und
-- einer verneinenden Antwort.
function GC.Workshop:FinishScan(professionName, skillLevel, maxSkillLevel, recipes, scannedCount, cooldowns)
    local stored, changed = self:StoreProfession(
        professionName, skillLevel, maxSkillLevel, recipes, scannedCount)
    if stored and cooldowns and self:RecordOwnCooldowns(professionName, cooldowns) then
        self:SendCooldowns()
        -- Der naechste Ablauf kann sich mit jedem Scan verschieben; die
        -- Erinnerung plant dann neu.
        self:ScheduleCooldownReminder()
    end
    return stored, changed
end

function GC.Workshop:StoreProfession(professionName, skillLevel, maxSkillLevel, recipes, scannedCount)
    if not next(recipes) then
        return false
    end

    -- Gespeichert und angezeigt wird der deutsche Name, gleich in welcher
    -- Sprache der Client das Fenster beschriftet: Das Addon ist deutschsprachig,
    -- und nur mit einem gemeinsamen Namen zaehlt "Enchanting" nicht als
    -- eigener Beruf neben "Verzauberkunst".
    professionName = GC.CanonicalProfessionName(professionName) or professionName
    local professionKey = NormalizeKey(professionName)
    local workshop = self:GetOwnData()
    local previous = workshop.professions[professionKey]
    if previous
        and (tonumber(skillLevel) or 0) >= (tonumber(previous.skillLevel) or 0)
        and (tonumber(maxSkillLevel) or 0) >= (tonumber(previous.maxSkillLevel) or 0) then
        for recipeKey, previousRecipe in pairs(previous.recipes or {}) do
            if not recipes[recipeKey] then
                recipes[recipeKey] = previousRecipe
            end
        end
    end
    local profession = {
        key = professionKey,
        name = professionName,
        skillLevel = tonumber(skillLevel) or 0,
        maxSkillLevel = tonumber(maxSkillLevel) or 0,
        updatedAt = GC.Util.Now(),
        recipes = recipes,
        -- Wartezeiten haengen am Charakter, nicht am Rezeptstand. Ein erneuter
        -- Scan baut diese Tabelle vollstaendig neu auf und wuerde den
        -- gemerkten Stand sonst jedes Mal mitnehmen - auch dann, wenn die
        -- Spielfassung gar keine Wartezeiten liefert und es folglich nichts
        -- gibt, was ihn ersetzt. Wurde beim Scan abgelesen, ueberschreibt
        -- RecordOwnCooldowns die uebernommenen Werte unmittelbar danach.
        cooldowns = previous and previous.cooldowns or nil,
        cooldownsAt = previous and previous.cooldownsAt or nil,
    }
    profession.fingerprint = RecipeFingerprint(profession)
    profession.fingerprintHash = FingerprintHash(profession.fingerprint)
    workshop.professions[professionKey] = profession
    self:InvalidateCatalog()
    self.lastScan = {
        name = professionName,
        recipes = #SortedKeys(recipes),
        scannedAt = GC.Util.Now(),
    }

    local changed = not previous or previous.fingerprint ~= profession.fingerprint
    if changed then
        local profile = GC.Profile:Get()
        profile.updatedAt = GC.Util.Now()
        self:QueueProfessionSync(profession)
        GC:Print(GC.LFormat("{beruf}: {geprueft} Einträge geprüft, {gespeichert} Rezepte gespeichert.", {
            beruf = professionName,
            geprueft = tonumber(scannedCount) or 0,
            gespeichert = #SortedKeys(recipes),
        }))
    end
    GC:FireCallback("WORKSHOP_UPDATED", profession)
    return true, changed
end

local function SafeAPICall(func, ...)
    if type(func) ~= "function" then
        return nil
    end
    local ok, result = pcall(func, ...)
    return ok and result or nil
end

local function PrepareClassicTradeSkill(professionName)
    if GC.Workshop.preparedProfession ~= professionName then
        GC.Workshop.preparedProfession = professionName
        if type(ExpandTradeSkillSubClass) == "function" then
            SafeAPICall(ExpandTradeSkillSubClass, 0)
        end
        if type(SetTradeSkillInvSlotFilter) == "function" then
            SafeAPICall(SetTradeSkillInvSlotFilter, 0, 1, 0)
        end
        if type(SetTradeSkillSubClassFilter) == "function" then
            SafeAPICall(SetTradeSkillSubClassFilter, 0, 1, 0)
        end
        if type(SetTradeSkillItemNameFilter) == "function" then
            SafeAPICall(SetTradeSkillItemNameFilter, nil)
        end
        if type(SetTradeSkillItemLevelFilter) == "function" then
            SafeAPICall(SetTradeSkillItemLevelFilter, 0, 0)
        end
        if type(TradeSkillOnlyShowSkillUps) == "function" then
            SafeAPICall(TradeSkillOnlyShowSkillUps, false)
        end
        if type(TradeSkillOnlyShowMakeable) == "function" then
            SafeAPICall(TradeSkillOnlyShowMakeable, false)
        end
    end

    if type(GetNumTradeSkills) ~= "function" or type(GetTradeSkillInfo) ~= "function"
        or type(ExpandTradeSkillSubClass) ~= "function" then
        return
    end

    for index = (tonumber(SafeAPICall(GetNumTradeSkills)) or 0), 1, -1 do
        local ok, _, skillType, _, isExpanded = pcall(GetTradeSkillInfo, index)
        if ok and (skillType == "header" or skillType == "subheader") and isExpanded == false then
            SafeAPICall(ExpandTradeSkillSubClass, index)
        end
    end
end

function GC.Workshop:ScanModernProfession()
    local api = C_TradeSkillUI
    if not api or type(api.GetRecipeInfo) ~= "function" or type(api.GetRecipeSchematic) ~= "function" then
        return false
    end
    if type(api.IsTradeSkillReady) == "function" and not SafeAPICall(api.IsTradeSkillReady) then
        return false
    end
    if type(api.IsDataSourceChanging) == "function" and SafeAPICall(api.IsDataSourceChanging) then
        return false
    end

    local baseInfo = SafeAPICall(api.GetBaseProfessionInfo) or {}
    local professionName = baseInfo.parentProfessionName or baseInfo.professionName
    if not professionName or professionName == "" or professionName == "UNKNOWN" then
        return false
    end

    local recipeIDs = {}
    if type(api.GetAllRecipeIDs) == "function" then
        recipeIDs = SafeAPICall(api.GetAllRecipeIDs) or {}
    elseif type(api.GetFilteredRecipeIDs) == "function" then
        recipeIDs = SafeAPICall(api.GetFilteredRecipeIDs) or {}
    end
    if #recipeIDs == 0 then
        return false
    end

    local recipes = {}
    -- Wie im klassischen Zweig: nil heisst "nicht abgelesen".
    local cooldowns = type(api.GetRecipeCooldown) == "function" and {} or nil
    for _, recipeID in ipairs(recipeIDs) do
        local recipeInfo = SafeAPICall(api.GetRecipeInfo, recipeID)
        if recipeInfo and recipeInfo.name and recipeInfo.learned ~= false then
            local itemLink = SafeAPICall(api.GetRecipeItemLink, recipeID)
            local recipeLink = SafeAPICall(api.GetRecipeLink, recipeID)
            local itemID = ItemIDFromLink(itemLink)
            local recipeKey = itemID and ("I" .. itemID) or ("E" .. tostring(recipeID))
            local reagents = {}
            local schematic = SafeAPICall(api.GetRecipeSchematic, recipeID, false)
            for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
                local reagent = slot.reagents and slot.reagents[1]
                local reagentItemID = reagent and reagent.itemID
                if reagentItemID then
                    reagents[#reagents + 1] = {
                        itemID = reagentItemID,
                        -- nil statt Platzhalter: aufgeloest wird bei der
                        -- Anzeige, dann mit gefuelltem Item-Cache.
                        name = LookupItemName(reagentItemID),
                        count = tonumber(slot.quantityRequired) or 1,
                    }
                end
            end
            recipes[recipeKey] = {
                key = recipeKey,
                name = recipeInfo.name,
                itemID = itemID,
                recipeID = tonumber(recipeID),
                itemLink = itemLink or recipeLink,
                profession = professionName,
                reagents = reagents,
            }
            if cooldowns then
                local remaining = SafeAPICall(api.GetRecipeCooldown, recipeID)
                if (tonumber(remaining) or 0) > 0 then
                    cooldowns[recipeKey] = tonumber(remaining)
                end
            end
        end
    end
    return self:FinishScan(
        professionName,
        baseInfo.skillLevel or baseInfo.skillLineCurrentLevel,
        baseInfo.maxSkillLevel or baseInfo.skillLineMaxLevel,
        recipes,
        #recipeIDs,
        cooldowns
    )
end

function GC.Workshop:ScanClassicCraftProfession()
    if not GetCraftInfo or not GetNumCrafts then
        return false
    end
    local professionName, skillLevel, maxSkillLevel
    if GetCraftSkillLine then
        professionName, skillLevel, maxSkillLevel = GetCraftSkillLine(1)
    end
    if (not professionName or professionName == "" or professionName == "UNKNOWN")
        and GetCraftDisplaySkillLine then
        professionName = GetCraftDisplaySkillLine()
    end
    if not professionName or professionName == "" or professionName == "UNKNOWN" then
        return false
    end

    local recipes = {}
    -- Verzauberkunst laeuft in TBC ueber die Craft-API, nicht ueber die
    -- Berufsfenster-API - und genau dort sitzen zwei der Rezepte, wegen denen
    -- es die Wartezeiten ueberhaupt gibt: Sphaere der Leere und Prismasphaere.
    -- Dieser Zweig las sie bis 0.9.97 nicht mit und ging an FinishScan vorbei,
    -- wo das Merken und Senden erst passiert. Fuer einen Verzauberer war die
    -- Anzeige damit unerreichbar, ohne dass irgendetwas fehlschlug.
    --
    -- Dieselbe Regel wie in den anderen beiden Zweigen: nil heisst "nicht
    -- abgelesen" und laesst den gemerkten Stand stehen, eine leere Tabelle
    -- heisst "abgelesen, nichts gesperrt".
    local cooldowns = GetCraftCooldown and {} or nil
    local recipeCount = GetNumCrafts() or 0
    for recipeIndex = 1, recipeCount do
        local recipeName, _, recipeType = GetCraftInfo(recipeIndex)
        if recipeName and recipeType ~= "header" and recipeType ~= "subheader" then
            local itemLink = GetCraftItemLink and GetCraftItemLink(recipeIndex)
            local recipeID = RecipeIDFromLink(itemLink)
            local itemID = ItemIDFromLink(itemLink)
            local recipeKey = itemID and ("I" .. itemID)
                or recipeID and ("E" .. recipeID)
                or ("N" .. NormalizeKey(recipeName))
            local reagents = {}
            local reagentCount = GetCraftNumReagents and (GetCraftNumReagents(recipeIndex) or 0) or 0
            for reagentIndex = 1, reagentCount do
                local reagentName, _, requiredCount = GetCraftReagentInfo(recipeIndex, reagentIndex)
                local reagentLink = GetCraftReagentItemLink
                    and GetCraftReagentItemLink(recipeIndex, reagentIndex)
                reagents[#reagents + 1] = {
                    itemID = ItemIDFromLink(reagentLink),
                    name = reagentName,
                    count = tonumber(requiredCount) or 1,
                }
            end
            recipes[recipeKey] = {
                key = recipeKey,
                name = recipeName,
                itemID = itemID,
                recipeID = recipeID,
                itemLink = itemLink,
                profession = professionName,
                reagents = reagents,
            }
            if cooldowns then
                local remaining = SafeAPICall(GetCraftCooldown, recipeIndex)
                if (tonumber(remaining) or 0) > 0 then
                    cooldowns[recipeKey] = tonumber(remaining)
                end
            end
        end
    end
    return self:FinishScan(
        professionName, skillLevel, maxSkillLevel, recipes, recipeCount, cooldowns)
end

function GC.Workshop:ScanOpenProfession()
    if GetTradeSkillLine then
        local tradeSkillName, _, tradeSkillMaximum = GetTradeSkillLine()
        if tradeSkillName == "UNKNOWN" or (tonumber(tradeSkillMaximum) or 0) == 0 then
            local craftSuccess, craftChanged = self:ScanClassicCraftProfession()
            if craftSuccess then
                return craftSuccess, craftChanged
            end
        end
    end
    if C_TradeSkillUI and type(C_TradeSkillUI.GetRecipeInfo) == "function" then
        local modernSuccess, modernChanged = self:ScanModernProfession()
        if modernSuccess then
            return modernSuccess, modernChanged
        end
    end
    if not GetTradeSkillLine or not GetNumTradeSkills or not GetTradeSkillInfo then
        return false
    end

    local professionName, skillLevel, maxSkillLevel = GetTradeSkillLine()
    if not professionName or professionName == "" or professionName == "UNKNOWN" then
        return false
    end

    PrepareClassicTradeSkill(professionName)

    local recipes = {}
    -- Nur der Client kennt die Wartezeit, und er nennt sie nur, solange das
    -- Berufsfenster offen ist. Sie wird deshalb hier mitgelesen, wo ohnehin
    -- jede Zeile einmal angefasst wird - ein zweiter Durchlauf waere nichts
    -- als zusaetzliche Arbeit im laufenden Spiel.
    --
    -- Fehlt die Abfrage in dieser Spielfassung, bleibt es bei nil: Dann ist
    -- nichts abgelesen worden, und der gemerkte Stand bleibt stehen. Eine
    -- leere Tabelle waere die Behauptung, es laufe nichts.
    local cooldowns = GetTradeSkillCooldown and {} or nil
    local recipeCount = GetNumTradeSkills() or 0
    for recipeIndex = 1, recipeCount do
        local recipeName, recipeType = GetTradeSkillInfo(recipeIndex)
        if recipeName and recipeType ~= "header" and recipeType ~= "subheader" then
            local itemLink = GetTradeSkillItemLink and GetTradeSkillItemLink(recipeIndex)
            local recipeLink = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(recipeIndex)
            local itemID = ItemIDFromLink(itemLink)
            local recipeID = RecipeIDFromLink(recipeLink)
            local recipeKey = itemID and ("I" .. itemID)
                or recipeID and ("E" .. recipeID)
                or ("N" .. NormalizeKey(recipeName))
            local reagents = {}
            local reagentCount = GetTradeSkillNumReagents and (GetTradeSkillNumReagents(recipeIndex) or 0) or 0
            for reagentIndex = 1, reagentCount do
                local reagentName, _, requiredCount = GetTradeSkillReagentInfo(recipeIndex, reagentIndex)
                local reagentLink = GetTradeSkillReagentItemLink
                    and GetTradeSkillReagentItemLink(recipeIndex, reagentIndex)
                reagents[#reagents + 1] = {
                    itemID = ItemIDFromLink(reagentLink),
                    name = reagentName,
                    count = tonumber(requiredCount) or 1,
                }
            end
            recipes[recipeKey] = {
                key = recipeKey,
                name = recipeName,
                itemID = itemID,
                recipeID = recipeID,
                itemLink = itemLink,
                profession = professionName,
                reagents = reagents,
            }
            if cooldowns then
                local remaining = SafeAPICall(GetTradeSkillCooldown, recipeIndex)
                if (tonumber(remaining) or 0) > 0 then
                    cooldowns[recipeKey] = tonumber(remaining)
                end
            end
        end
    end
    return self:FinishScan(professionName, skillLevel, maxSkillLevel, recipes, recipeCount, cooldowns)
end

-- === Herstellen aus dem Cockpit =============================================
--
-- "Moeglichkeit, aus dem Cockpit heraus Items herzustellen?" - aus der Gilde,
-- 08/2026. Machbar, aber mit zwei Grenzen, die das Spiel setzt und die kein
-- Addon umgeht:
--
--   1. Nur der Charakter, der GERADE spielt. Der Katalog kennt die Rezepte
--      aller Twinks der Gilde; fertigen kann immer nur der eingeloggte.
--   2. Nur bei offenem Berufsfenster. Die Rezeptlisten der drei APIs
--      existieren ausschliesslich, solange es offen steht - deshalb wird hier
--      nichts gemerkt, sondern bei jedem Auftrag neu gesucht. Ein gemerkter
--      Index waere schon nach dem naechsten Filterwechsel falsch.
--
-- Geoeffnet wird das Fenster ueber einen sicheren Knopf in der Oberflaeche
-- (Zauber, echter Tastendruck) - genau wie im Einrichtungsassistenten.

-- Das Rezept des eingeloggten Charakters, oder nil.
function GC.Workshop:GetOwnRecipe(recipeKey)
    recipeKey = tostring(recipeKey or "")
    if recipeKey == "" then
        return nil
    end
    for _, profession in pairs(self:GetOwnData().professions) do
        local recipe = profession.recipes and profession.recipes[recipeKey]
        if recipe then
            return recipe, profession
        end
    end
    return nil
end

-- Sucht das Rezept im gerade offenen Berufsfenster. Liefert die Angaben, die
-- der jeweilige Herstellbefehl braucht: "modern" die Rezept-ID, die beiden
-- klassischen Wege ihren Listenindex.
function GC.Workshop:FindOpenRecipe(recipeKey)
    recipeKey = tostring(recipeKey or "")
    if recipeKey == "" then
        return nil
    end

    local api = C_TradeSkillUI
    if api and type(api.GetRecipeInfo) == "function" and type(api.GetAllRecipeIDs) == "function"
        and (type(api.IsTradeSkillReady) ~= "function" or SafeAPICall(api.IsTradeSkillReady)) then
        for _, recipeID in ipairs(SafeAPICall(api.GetAllRecipeIDs) or {}) do
            local info = SafeAPICall(api.GetRecipeInfo, recipeID)
            if info and info.learned ~= false then
                local itemID = ItemIDFromLink(SafeAPICall(api.GetRecipeItemLink, recipeID))
                local key = itemID and ("I" .. itemID) or ("E" .. tostring(recipeID))
                if key == recipeKey then
                    return { kind = "MODERN", recipeID = recipeID, name = info.name }
                end
            end
        end
    end

    if GetNumCrafts and GetCraftInfo and (GetNumCrafts() or 0) > 0 then
        for index = 1, GetNumCrafts() do
            local name, _, craftType = GetCraftInfo(index)
            if name and craftType ~= "header" and craftType ~= "subheader" then
                local link = GetCraftItemLink and GetCraftItemLink(index)
                local itemID = ItemIDFromLink(link)
                local recipeID = RecipeIDFromLink(link)
                local key = itemID and ("I" .. itemID)
                    or recipeID and ("E" .. recipeID)
                    or ("N" .. NormalizeKey(name))
                if key == recipeKey then
                    return { kind = "CRAFT", index = index, name = name }
                end
            end
        end
    end

    if GetNumTradeSkills and GetTradeSkillInfo and (GetNumTradeSkills() or 0) > 0 then
        for index = 1, GetNumTradeSkills() do
            local name, skillType = GetTradeSkillInfo(index)
            if name and skillType ~= "header" and skillType ~= "subheader" then
                local itemID = ItemIDFromLink(GetTradeSkillItemLink and GetTradeSkillItemLink(index))
                local recipeID = RecipeIDFromLink(
                    GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(index))
                local key = itemID and ("I" .. itemID)
                    or recipeID and ("E" .. recipeID)
                    or ("N" .. NormalizeKey(name))
                if key == recipeKey then
                    return { kind = "CLASSIC", index = index, name = name }
                end
            end
        end
    end
    return nil
end

-- Startet die Herstellung. Gibt Erfolg und eine Meldung zurueck; ausgeloest
-- wird immer nur EIN Herstellbefehl, das Spiel wiederholt ihn selbst.
function GC.Workshop:CraftOpenRecipe(recipeKey, count)
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false, "Im Kampf wird nicht gefertigt."
    end
    if not self:GetOwnRecipe(recipeKey) then
        return false, "Dieser Charakter kennt das Rezept nicht."
    end
    local found = self:FindOpenRecipe(recipeKey)
    if not found then
        return false, "Öffne zuerst das Berufsfenster – der Client gibt die Rezeptliste nur dann her."
    end
    count = math.max(1, math.min(40, math.floor(tonumber(count) or 1)))

    if found.kind == "MODERN" and C_TradeSkillUI
        and type(C_TradeSkillUI.CraftRecipe) == "function" then
        SafeAPICall(C_TradeSkillUI.CraftRecipe, found.recipeID, count)
    elseif found.kind == "CRAFT" and type(DoCraft) == "function" then
        -- Die Craft-API (Verzauberkunst in TBC) kennt keine Wiederholung:
        -- ein Aufruf, ein Stueck.
        SafeAPICall(DoCraft, found.index)
        count = 1
    elseif found.kind == "CLASSIC" and type(DoTradeSkill) == "function" then
        SafeAPICall(DoTradeSkill, found.index, count)
    else
        return false, "Diese Spielfassung kennt keinen Herstellbefehl für das Rezept."
    end
    return true, count == 1 and ("„" .. (found.name or "?") .. "“ wird hergestellt.")
        or ("„" .. (found.name or "?") .. "“ wird " .. count .. "× hergestellt.")
end

-- "recipeKeyFilter" schraenkt die Nutzlast auf einzelne Rezepte ein. Damit
-- werden nachgeforderte Rezepte gezielt nachgeliefert, statt den ganzen Beruf
-- erneut zu senden.
function GC.Workshop:BuildProfessionMessages(profession, compact, crafterName, recipeKeyFilter)
    local operation = compact == false and "D" or "C"
    local token = tostring(GC.Util.Now()) .. tostring(math.random(100, 999))
    -- Der Herstellername wird als zusaetzliches Feld angehaengt, damit auch die
    -- Berufe der eigenen Twinks korrekt dem jeweiligen Charakter zugeordnet
    -- werden. Aeltere Clients ignorieren das Feld schlicht und schreiben die
    -- Daten wie bisher dem Absender zu.
    local crafterField = GC.Util.SafeChatText(GC.Util.Trim(crafterName or ""), 40)
    local fingerprintHash = profession.fingerprintHash
        or FingerprintHash(profession.fingerprint or RecipeFingerprint(profession))

    -- Das Nutzlast-Budget ergibt sich aus dem echten 255-Byte-Chatlimit
    -- abzueglich der vollstaendigen Kopfzeile (mit dreistelligen Platzhaltern
    -- fuer Teil und Gesamtzahl). Eine feste Nutzlastgroesse hat bei langen
    -- Berufs- oder Herstellernamen das Limit gesprengt; solche Pakete wurden
    -- vor dem Senden kommentarlos verworfen und der Transfer blieb beim
    -- Empfaenger fuer immer unvollstaendig.
    local header = BuildMessage({
        "W",
        GC.Constants.SCHEMA_VERSION,
        operation,
        token,
        "000",
        "000",
        profession.key,
        profession.name,
        "",
        tostring(profession.updatedAt or 0),
        fingerprintHash,
        crafterField,
    })
    local payloadLimit = math.min(
        compact == false and LEGACY_MAX_PAYLOAD_BYTES or MAX_PAYLOAD_BYTES,
        GC.Constants.MAX_CHAT_BYTES - #header
    )

    local records = {}
    for _, recipeKey in ipairs(SortedKeys(profession.recipes)) do
        if not recipeKeyFilter or recipeKeyFilter[recipeKey] then
            local recipe = profession.recipes[recipeKey]
            local record = compact == false
                and BuildRecipeRecord(recipe, payloadLimit)
                or BuildCompactRecipeRecord(recipe, payloadLimit)
            if record then
                records[#records + 1] = record
            end
        end
    end
    if recipeKeyFilter and #records == 0 then
        return {}, token
    end

    local payloads = {}
    local current = ""
    for _, record in ipairs(records) do
        local candidate = current == "" and record or (current .. ";" .. record)
        if #candidate > payloadLimit and current ~= "" then
            payloads[#payloads + 1] = current
            current = record
        else
            current = candidate
        end
    end
    payloads[#payloads + 1] = current

    local messages = {}
    for index, payload in ipairs(payloads) do
        messages[#messages + 1] = BuildMessage({
            "W",
            GC.Constants.SCHEMA_VERSION,
            operation,
            token,
            index,
            #payloads,
            profession.key,
            profession.name,
            payload,
            tostring(profession.updatedAt or 0),
            fingerprintHash,
            crafterField,
        })
    end
    return messages, token
end

-- Die Schluesselliste eines Berufs: nur "wer kann was", ohne Rezeptdaten. Sie
-- nutzt dieselbe Kopfzeile und damit dieselbe Zusammensetzung beim Empfaenger
-- wie ein voller Transfer - nur die Nutzlast ist eine andere.
function GC.Workshop:BuildKeyListMessages(profession, crafterName)
    local token = tostring(GC.Util.Now()) .. tostring(math.random(100, 999))
    local crafterField = GC.Util.SafeChatText(GC.Util.Trim(crafterName or ""), 40)
    local fingerprintHash = profession.fingerprintHash
        or FingerprintHash(profession.fingerprint or RecipeFingerprint(profession))
    local header = BuildMessage({
        "W", GC.Constants.SCHEMA_VERSION, "K", token, "000", "000",
        profession.key, profession.name, "",
        tostring(profession.updatedAt or 0), fingerprintHash, crafterField,
    })
    local payloadLimit = math.min(
        MAX_PAYLOAD_BYTES,
        GC.Constants.MAX_CHAT_BYTES - #header
    )

    -- Eigene Berufe fuehren volle Rezepte, der Herstellerindex nur die
    -- Schluesselmenge - fuer die Liste ist beides dasselbe. So kann auch ein
    -- Bote antworten, der die Daten eines Dritten nur aus dem Index kennt.
    local payload = EncodeRecipeKeys(SortedKeys(profession.recipeKeys or profession.recipes))
    -- Wie beim Gildenprofil wird stumpf nach Bytes geschnitten; gelesen wird
    -- erst die wieder zusammengesetzte Nutzlast.
    local chunks = {}
    for offset = 1, math.max(1, #payload), payloadLimit do
        chunks[#chunks + 1] = payload:sub(offset, offset + payloadLimit - 1)
    end

    local messages = {}
    for index, chunk in ipairs(chunks) do
        messages[#messages + 1] = BuildMessage({
            "W", GC.Constants.SCHEMA_VERSION, "K", token, index, #chunks,
            profession.key, profession.name, chunk,
            tostring(profession.updatedAt or 0), fingerprintHash, crafterField,
        })
    end
    return messages, token
end

function GC.Workshop:QueueProfessionSync(profession, compact, target, reliable, crafterName, recipeKeyFilter)
    if not profession then
        return
    end

    local messages, token = self:BuildProfessionMessages(profession, compact, crafterName, recipeKeyFilter)
    if #messages == 0 then
        return false
    end
    if reliable and target and compact ~= false and GC.Sync and GC.Sync.QueueReliable then
        self.syncStats.queued = self.syncStats.queued + #messages
        local queued = GC.Sync:QueueReliable(
            messages,
            target,
            "W",
            token,
            function()
                GC.Workshop.syncStats.sent = GC.Workshop.syncStats.sent + #messages
                GC:FireCallback("WORKSHOP_UPDATED")
            end,
            function(entry)
                -- Kommt der bestaetigte Fluestertransfer nicht durch (in manchen
                -- Umgebungen erreichen Addon-Fluester den Empfaenger nicht,
                -- waehrend der Gildenkanal laeuft), wird der Beruf ueber den
                -- bewaehrten Gildenkanal nachgereicht. So bekommt der Anfragende
                -- die Daten trotzdem, ohne dass ein Fehl-Banner stehen bleibt -
                -- echte Verluste zaehlt die Gilden-Warteschlange selbst.
                local lost = entry.failedCount
                    or math.max(1, #messages - (entry.acknowledgedCount or 0))
                if lost > 0 then
                    GC.Workshop:QueueProfessionSync(profession, true, nil, nil, crafterName)
                else
                    GC:FireCallback("WORKSHOP_UPDATED")
                end
            end
        )
        if not queued then
            -- Der Fluesterweg liess sich gar nicht erst starten: sofort ueber
            -- den Gildenkanal senden.
            self:QueueProfessionSync(profession, true, nil, nil, crafterName)
        end
        GC:FireCallback("WORKSHOP_UPDATED")
        return queued
    end

    -- Zusammen mit dem Beruf identifiziert der Herstellername ein Paket
    -- eindeutig, damit zwei eigene Charaktere mit demselben Beruf sich beim
    -- Einreihen nicht gegenseitig verdraengen.
    local crafterKey = GC.Util.PlayerKey(crafterName or "")
    for index = #self.syncQueue, 1, -1 do
        if self.syncQueue[index].professionKey == profession.key
            and self.syncQueue[index].target == target
            and (self.syncQueue[index].crafterKey or "") == crafterKey then
            table.remove(self.syncQueue, index)
        end
    end

    for _, message in ipairs(messages) do
        if #message <= GC.Constants.MAX_CHAT_BYTES then
            self.syncQueue[#self.syncQueue + 1] = {
                message = message,
                retries = 0,
                professionKey = profession.key,
                crafterKey = crafterKey,
                distribution = target and "WHISPER" or "GUILD",
                target = target,
            }
            self.syncStats.queued = self.syncStats.queued + 1
        else
            self.syncStats.failed = self.syncStats.failed + 1
        end
    end
    GC:FireCallback("WORKSHOP_UPDATED")
    self:PumpSyncQueue()
end

-- Alle Berufe aller eigenen Charaktere desselben Accounts, jeweils mit dem
-- richtigen Charakternamen. So teilt jeder eingeloggte Charakter der Gilde auch
-- die Berufe seiner Twinks mit - das Addon kennt sie ja lokal aus der
-- gemeinsamen SavedVariables und muss sie nicht erneut erlernen.
--
-- Diese Fassung liefert ALLE Charaktere und ist damit die richtige fuer alles,
-- was den Account betrifft und nie den Rechner verlaesst: die eigene
-- Berufsuebersicht und die Wartezeit-Erinnerungen. Was in die Gilde geht,
-- nimmt GetPublishableProfessions.
function GC.Workshop:GetAccountProfessions()
    local entries = {}
    local ownName = GC:GetPlayerFullName()
    local ownKey = GC.Util.PlayerKey(ownName)
    for _, profession in pairs(self:GetOwnData().professions) do
        entries[#entries + 1] = { crafter = ownName, profession = profession }
    end
    for characterKey, character in pairs((GC.DB.data and GC.DB.data.characters) or {}) do
        local characterName = (type(character) == "table" and character.fullName) or characterKey
        local workshop = type(character) == "table" and character.workshop
        if workshop and workshop.professions
            and GC.Util.PlayerKey(characterName) ~= ownKey then
            -- Auch die Twinks koennen mit einem englischen Client eingelesen
            -- worden sein; ihre Schluessel wandern beim ersten Lesen mit.
            CanonicalizeOwnProfessions(workshop)
            for _, profession in pairs(workshop.professions) do
                entries[#entries + 1] = {
                    crafter = characterName,
                    profession = profession,
                    guildKey = type(character) == "table" and character.guildKey or nil,
                }
            end
        end
    end
    return entries
end

-- Dieselbe Liste, aber nur die Charaktere, die in DIESER Gilde stehen.
--
-- Wer mit einem Account in zwei Gilden spielt, hat sonst seinen Twink aus
-- Gilde A samt Namen und Rezepten in Gilde B angekuendigt - der Gildenkanal
-- trennt zwar sauber, die Quelle der Daten tat es nicht. Gefragt wird deshalb
-- der Vermerk, den jeder Charakter beim Einloggen hinterlaesst
-- (Profile.StampGuildKey).
--
-- Der eingeloggte Charakter ist immer dabei: Er IST die aktuelle Gilde, dafuer
-- braucht es keinen gespeicherten Vermerk.
--
-- Ein Charakter OHNE Vermerk bleibt draussen. Das trifft nach dem Update jeden
-- Twink genau so lange, bis er einmal eingeloggt war, und kostet in dieser Zeit
-- einen unvollstaendigen Gildenkatalog. Die Gegenrichtung waere, im Zweifel zu
-- senden - und damit genau den Uebertritt zu wiederholen, den diese Funktion
-- verhindern soll. Eine Luecke, die sich von selbst schliesst, ist das kleinere
-- Uebel als ein Leck, das niemand bemerkt.
function GC.Workshop:GetPublishableProfessions()
    local guildKey = GC:GetGuildKey()
    local ownKey = GC.Util.PlayerKey(GC:GetPlayerFullName())
    local entries = {}
    for _, entry in ipairs(self:GetAccountProfessions()) do
        if GC.Util.PlayerKey(entry.crafter) == ownKey or entry.guildKey == guildKey then
            entries[#entries + 1] = entry
        end
    end
    return entries
end

-- Wie viele eigene Charaktere gerade zurueckgehalten werden, weil ihr
-- Gildenvermerk fehlt. Die Werkstatt sagt es dem Besitzer, statt ihn eine
-- Luecke suchen zu lassen, die keine ist.
function GC.Workshop:CountUnassignedCrafters()
    local ownKey = GC.Util.PlayerKey(GC:GetPlayerFullName())
    local names = {}
    for _, entry in ipairs(self:GetAccountProfessions()) do
        if GC.Util.PlayerKey(entry.crafter) ~= ownKey and entry.guildKey == nil then
            names[GC.Util.PlayerKey(entry.crafter)] = true
        end
    end
    local count = 0
    for _ in pairs(names) do
        count = count + 1
    end
    return count
end

-- Reiht eine Schluesselliste in dieselbe Warteschlange ein wie volle Transfers.
function GC.Workshop:QueueKeyList(profession, crafterName)
    if not profession then
        return false
    end
    local messages = self:BuildKeyListMessages(profession, crafterName)
    local crafterKey = GC.Util.PlayerKey(crafterName or "")
    for index = #self.syncQueue, 1, -1 do
        local queued = self.syncQueue[index]
        if queued.professionKey == profession.key and queued.keyList
            and (queued.crafterKey or "") == crafterKey then
            table.remove(self.syncQueue, index)
        end
    end
    for _, message in ipairs(messages) do
        if #message <= GC.Constants.MAX_CHAT_BYTES then
            self.syncQueue[#self.syncQueue + 1] = {
                message = message,
                retries = 0,
                professionKey = profession.key,
                crafterKey = crafterKey,
                keyList = true,
                distribution = "GUILD",
            }
            self.syncStats.queued = self.syncStats.queued + 1
        else
            self.syncStats.failed = self.syncStats.failed + 1
        end
    end
    GC:FireCallback("WORKSHOP_UPDATED")
    self:PumpSyncQueue()
    return true
end

-- "fullData" verlangt ausdruecklich die vollen Rezeptdaten. Ohne das Kennzeichen
-- gehen nur Schluessellisten raus. Vorher entschied das eine gildenweite
-- Vermutung: ein einziger Eintrag mit veralteten Faehigkeiten liess damit jeden
-- Login und jedes /reload zum Vollversand werden.
function GC.Workshop:QueueAllProfessions(compact, target, reliable, fullData)
    if #self.syncQueue == 0 and not self.syncSending then
        self.syncStats.queued = 0
        self.syncStats.sent = 0
        self.syncStats.failed = 0
    end
    -- Der Regelfall ist die kurze Schluesselliste: die Rezeptdaten selbst sind
    -- in der Gilde langst bekannt, weil jedes Rezept fuer alle identisch ist.
    -- Volle Daten gehen nur an gezielte Empfaenger oder solange noch ein Client
    -- ohne Schluesselliste in der Gilde ist.
    local keyListOnly = not target and compact ~= false and not fullData
    for _, entry in ipairs(self:GetPublishableProfessions()) do
        if keyListOnly then
            self:QueueKeyList(entry.profession, entry.crafter)
        else
            self:QueueProfessionSync(entry.profession, compact, target, reliable, entry.crafter)
            if not target then
                -- Zusammen mit den vollen Daten geht die Schluesselliste raus,
                -- damit aktuelle Clients den Herstellerindex auch dann sauber
                -- fuehren, wenn einzelne Rezeptpakete verloren gehen.
                self:QueueKeyList(entry.profession, entry.crafter)
            end
        end
    end
end

function GC.Workshop:PumpSyncQueue()
    if self.syncSending or #self.syncQueue == 0 then
        return
    end
    self.syncSending = true
    while #self.syncQueue > 0 do
        local entry = table.remove(self.syncQueue, 1)
        self.bulkPending = (self.bulkPending or 0) + 1
        local queued = GC.Sync and GC.Sync:SendBulk(
            entry.message,
            entry.distribution,
            entry.target,
            function(success)
                GC.Workshop.bulkPending = math.max(0, (GC.Workshop.bulkPending or 1) - 1)
                if success then
                    GC.Workshop.syncStats.sent = GC.Workshop.syncStats.sent + 1
                else
                    GC.Workshop.syncStats.failed = GC.Workshop.syncStats.failed + 1
                end
                GC:FireCallback("WORKSHOP_UPDATED")
            end
        )
        if not queued then
            self.bulkPending = math.max(0, (self.bulkPending or 1) - 1)
            self.syncStats.failed = self.syncStats.failed + 1
        end
    end
    self.syncSending = false
    GC:FireCallback("WORKSHOP_UPDATED")
end

function GC.Workshop:RequestGuildData()
    if not IsInGuild or not IsInGuild() then
        return false, "Du bist in keiner Gilde."
    end
    -- Jede Anfrage loest gildenweit gestreute Antworten aus - bei 250 Online
    -- sind das schnell hunderte Pakete. Doppelklicks und Slash-Wiederholungen
    -- innerhalb der Antwortstreuung bringen nichts Neues und bleiben deshalb
    -- hier haengen; die Antwortenden drosseln denselben Frager zusaetzlich
    -- selbst (requestReplies).
    local now = GC.Util.Now()
    if (now - (tonumber(self.lastGuildRequestAt) or 0)) < MANIFEST_REPLY_SPREAD then
        return false, "Die Anfrage läuft schon – Antworten treffen gestreut ein."
    end
    if not GC.Sync or not GC.Sync:Send(BuildMessage({ "W", GC.Constants.SCHEMA_VERSION, "Q", "3" })) then
        return false, "Werkstatt-Anfrage konnte nicht gesendet werden."
    end
    self.lastGuildRequestAt = now
    self.syncStats.receivedProfessions = 0
    self.syncStats.receivedRecipes = 0
    self.syncStats.lastSender = ""
    -- Eine neue Anfrage startet einen frischen Abgleichzyklus. Ein alter
    -- Fehlschlag-Zaehler aus einem frueheren Zyklus darf den Statushinweis nicht
    -- dauerhaft blockieren, sonst bleibt "Uebertragung unvollstaendig" stehen,
    -- obwohl der neue Durchlauf laeuft. Dasselbe gilt fuer die ausgebliebenen
    -- Berufe: Der neue Durchlauf fragt sie erneut an.
    self.syncStats.failed = 0
    self:ResetLostWants()
    GC:FireCallback("WORKSHOP_UPDATED")
    return true, "Anfrage gesendet. Rezeptlisten werden ohne künstliche Wartezeit übertragen."
end

function GC.Workshop:GetPendingPacketCount()
    local reliable = GC.Sync and GC.Sync.GetReliablePendingCount
        and GC.Sync:GetReliablePendingCount("W") or 0
    return #self.syncQueue + (self.bulkPending or 0) + reliable
end

-- === Wartezeiten ===========================================================

local function RoundCooldown(readyAt)
    return math.floor(((tonumber(readyAt) or 0) / COOLDOWN_ROUNDING) + 0.5) * COOLDOWN_ROUNDING
end

-- Die Sperren des eigenen Charakters, so wie sie beim letzten Blick ins
-- Berufsfenster standen. Der eigene Stand ist als einziger vollstaendig: Was
-- das Berufsfenster jetzt nicht mehr meldet, ist auch nicht mehr gesperrt.
-- Deshalb wird hier ersetzt, waehrend fremde Staende nur ergaenzt werden.
function GC.Workshop:RecordOwnCooldowns(professionName, remainingByKey)
    local profession = self:GetOwnData().professions[NormalizeKey(professionName)]
    if not profession then
        return false
    end

    local now = GC.Util.Now()
    local cooldowns, count = {}, 0
    for _, recipeKey in ipairs(SortedKeys(remainingByKey)) do
        local remaining = tonumber(remainingByKey[recipeKey]) or 0
        if remaining >= MIN_COOLDOWN_SECONDS and remaining <= MAX_COOLDOWN_SECONDS
            and count < MAX_COOLDOWNS_PER_CRAFTER then
            cooldowns[recipeKey] = RoundCooldown(now + remaining)
            count = count + 1
        end
    end

    local previous = profession.cooldowns or {}
    local changed = false
    for recipeKey, readyAt in pairs(cooldowns) do
        if previous[recipeKey] ~= readyAt then
            changed = true
        end
    end
    for recipeKey in pairs(previous) do
        if not cooldowns[recipeKey] then
            changed = true
        end
    end

    profession.cooldowns = cooldowns
    profession.cooldownsAt = now
    if changed then
        self.cooldownIndex = nil
    end
    return changed
end

-- Fremde Sperren. Ein Absender kennt immer nur seine eigenen Charaktere, also
-- wird hier ausschliesslich ergaenzt: Das Fehlen eines Rezepts in einem Paket
-- ist keine Aussage ueber dieses Rezept.
function GC.Workshop:StoreCrafterCooldowns(crafterName, entries, sharedBy)
    local crafterKey = GC.Util.PlayerKey(crafterName)
    if crafterKey == "" or #(entries or {}) == 0 then
        return false
    end

    local workshop = self:GetGuildWorkshop()
    local crafter = workshop.crafters[crafterKey] or { professions = {} }
    crafter.name = crafter.name or crafterName
    crafter.professions = crafter.professions or {}
    if GC.Util.Trim(sharedBy) ~= "" then
        crafter.sharedBy = crafter.sharedBy or sharedBy
    end

    local now = GC.Util.Now()
    local cooldowns = crafter.cooldowns or {}
    local changed = false
    for _, entry in ipairs(entries) do
        local readyAt = RoundCooldown(entry.readyAt)
        -- Der spaetere Zeitpunkt gewinnt. Beide Angaben sind Untergrenzen, und
        -- die groessere ist die belastbarere - ein im Gildenkanal verspaetetes
        -- Paket darf einen frischeren Stand nicht zurueckdrehen.
        if readyAt > (tonumber(cooldowns[entry.key]) or 0) then
            cooldowns[entry.key] = readyAt
            changed = true
        end
    end

    -- Abgelaufenes fliegt beim Schreiben heraus. Damit bleibt die Tabelle von
    -- selbst klein, ohne einen eigenen Aufraeumlauf zu brauchen.
    local live = {}
    for recipeKey, readyAt in pairs(cooldowns) do
        if (tonumber(readyAt) or 0) <= now then
            cooldowns[recipeKey] = nil
        else
            live[#live + 1] = recipeKey
        end
    end
    if #live > MAX_COOLDOWNS_PER_CRAFTER then
        table.sort(live, function(left, right)
            return (cooldowns[left] or 0) > (cooldowns[right] or 0)
        end)
        for index = MAX_COOLDOWNS_PER_CRAFTER + 1, #live do
            cooldowns[live[index]] = nil
        end
    end

    crafter.cooldowns = cooldowns
    workshop.crafters[crafterKey] = crafter
    if changed then
        self.cooldownIndex = nil
        GC:FireCallback("WORKSHOP_UPDATED")
    end
    return changed
end

-- Rezept -> Hersteller -> Zeitpunkt. Der Index behaelt bewusst auch abgelaufene
-- Eintraege: Wuerde hier nach der Uhr gefiltert, waere das Ergebnis eine
-- Momentaufnahme, die im Zwischenspeicher liegen bleibt und mit jeder Minute
-- unrichtiger wird. Gefiltert wird deshalb erst bei der Abfrage.
function GC.Workshop:GetCooldownIndex()
    if self.cooldownIndex then
        return self.cooldownIndex
    end

    local index = {}
    local function Add(crafterName, recipeKey, readyAt)
        readyAt = tonumber(readyAt) or 0
        local crafterKey = GC.Util.PlayerKey(crafterName)
        if readyAt <= 0 or crafterKey == "" or GC.Util.Trim(recipeKey) == "" then
            return
        end
        local byCrafter = index[recipeKey]
        if not byCrafter then
            byCrafter = {}
            index[recipeKey] = byCrafter
        end
        if (tonumber(byCrafter[crafterKey]) or 0) < readyAt then
            byCrafter[crafterKey] = readyAt
        end
    end

    for _, entry in ipairs(self:GetAccountProfessions()) do
        for recipeKey, readyAt in pairs(entry.profession.cooldowns or {}) do
            Add(entry.crafter, recipeKey, readyAt)
        end
    end
    for crafterKey, crafter in pairs(self:GetGuildWorkshop().crafters) do
        if type(crafter) == "table" then
            for recipeKey, readyAt in pairs(crafter.cooldowns or {}) do
                Add(crafter.name or crafterKey, recipeKey, readyAt)
            end
        end
    end

    self.cooldownIndex = index
    return index
end

-- Der Zeitpunkt, vor dem dieser Hersteller dieses Rezept nachweislich nicht
-- machen kann. nil heisst nicht "frei", sondern "keine bekannte Sperre".
function GC.Workshop:GetRecipeCooldown(recipeKey, crafterName)
    local byCrafter = self:GetCooldownIndex()[recipeKey]
    if not byCrafter then
        return nil
    end
    local readyAt = tonumber(byCrafter[GC.Util.PlayerKey(crafterName)])
    if not readyAt or readyAt <= GC.Util.Now() then
        return nil
    end
    return readyAt
end

-- === Wartezeit-Erinnerung ===================================================
--
-- Das Addon kennt die laufenden Sperren der eigenen Charaktere - was fehlte,
-- war der Moment, in dem dieses Wissen etwas nuetzt: wenn die Sperre
-- ABGELAUFEN ist. Gemeldet wird im Chat, einmal je Sperre: Der Merker haelt
-- den Ablaufzeitpunkt fest, und eine neue Umwandlung ergibt einen neuen
-- Zeitpunkt und damit wieder genau eine Meldung. Beim Login wird gesammelt
-- gemeldet, waehrend der Sitzung weckt ein Zeitgeber zum naechsten Ablauf.
--
-- Die Meldung sagt "abgelaufen", nicht "frei": Der gespeicherte Zeitpunkt ist
-- eine Untergrenze (siehe Kopf des Wartezeiten-Abschnitts). Fuer die eigenen
-- Charaktere ist er praktisch immer exakt, denn jede neue Umwandlung laeuft
-- durchs eigene Berufsfenster und damit durch den Scan.
local COOLDOWN_REMINDER_LOGIN_DELAY = 25
local MAX_COOLDOWN_REMINDER_LINES = 5
local COOLDOWN_REMINDER_KEEP = 30 * 24 * 60 * 60

local function CooldownReminderStore()
    if not (GC.DB and GC.DB.data) then
        return nil
    end
    GC.DB.data.cooldownReminded = GC.DB.data.cooldownReminded or {}
    return GC.DB.data.cooldownReminded
end

-- Alle abgelaufenen und noch nicht gemeldeten Sperren der eigenen Charaktere.
function GC.Workshop:CollectDueCooldownReminders(now)
    now = tonumber(now) or GC.Util.Now()
    local reminded = CooldownReminderStore()
    local due = {}
    for _, entry in ipairs(self:GetAccountProfessions()) do
        for _, recipeKey in ipairs(SortedKeys(entry.profession.cooldowns)) do
            local readyAt = tonumber(entry.profession.cooldowns[recipeKey]) or 0
            if readyAt > 0 and readyAt <= now then
                local key = GC.Util.PlayerKey(entry.crafter) .. "|" .. recipeKey
                if not reminded or (tonumber(reminded[key]) or 0) ~= readyAt then
                    due[#due + 1] = {
                        key = key,
                        crafter = entry.crafter,
                        recipeKey = recipeKey,
                        readyAt = readyAt,
                    }
                end
            end
        end
    end
    return due
end

function GC.Workshop:AnnounceDueCooldowns()
    if GC.DB:GetSettings().cooldownReminder == false then
        return 0
    end
    local now = GC.Util.Now()
    local due = self:CollectDueCooldownReminders(now)
    local reminded = CooldownReminderStore()
    if reminded then
        -- Merker, deren Ablauf einen Monat zurueckliegt, bewirken nichts
        -- mehr: Die laengste Sperre in TBC sind vier Tage, ein so alter
        -- Eintrag gehoert laengst zu einer abgeraeumten Sperre.
        local cutoff = now - COOLDOWN_REMINDER_KEEP
        for key, readyAt in pairs(reminded) do
            if (tonumber(readyAt) or 0) < cutoff then
                reminded[key] = nil
            end
        end
    end
    for index, entry in ipairs(due) do
        if reminded then
            reminded[entry.key] = entry.readyAt
        end
        if index <= MAX_COOLDOWN_REMINDER_LINES then
            GC:Print(GC.LFormat("Wartezeit abgelaufen: {rezept} ({charakter}) – wieder herstellbar.", {
                rezept = ResolveRecipeName(entry.recipeKey),
                charakter = GC.Util.PlayerIdentityName(entry.crafter),
            }))
        elseif index == MAX_COOLDOWN_REMINDER_LINES + 1 then
            GC:Print(GC.LFormat("… und {n} weitere abgelaufene Wartezeiten.",
                { n = #due - MAX_COOLDOWN_REMINDER_LINES }))
        end
    end
    return #due
end

-- Plant den Zeitgeber auf den naechsten kuenftigen Ablauf. Ein laufender
-- Zeitgeber laesst sich nicht zurueckziehen; der Stempel entwertet veraltete.
function GC.Workshop:ScheduleCooldownReminder()
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return false
    end
    local now = GC.Util.Now()
    local nextAt
    for _, entry in ipairs(self:GetAccountProfessions()) do
        for _, readyAt in pairs(entry.profession.cooldowns or {}) do
            readyAt = tonumber(readyAt) or 0
            if readyAt > now and (not nextAt or readyAt < nextAt) then
                nextAt = readyAt
            end
        end
    end
    if not nextAt then
        return false
    end
    self.cooldownReminderToken = (tonumber(self.cooldownReminderToken) or 0) + 1
    local token = self.cooldownReminderToken
    C_Timer.After(math.max(1, nextAt - now + 2), function()
        if GC.Workshop.cooldownReminderToken ~= token then
            return
        end
        GC.Workshop:AnnounceDueCooldowns()
        -- Nur weiterplanen, wenn die Zeit den Ablauf wirklich erreicht hat.
        -- In Umgebungen, deren Zeitgeber sofort feuern (Tests), liefe die
        -- Kette sonst endlos gegen denselben kuenftigen Zeitpunkt an.
        if GC.Util.Now() >= nextAt then
            GC.Workshop:ScheduleCooldownReminder()
        end
    end)
    return true
end

-- Jede Nachricht steht fuer sich: Sperren sind einzelne Tatsachen, keine
-- Liste, die vollstaendig ankommen muesste. Es gibt deshalb weder Token noch
-- Teilzaehler noch ein Zusammensetzen beim Empfaenger - was ankommt, gilt,
-- was fehlt, wird beim naechsten Mal mitgeteilt.
function GC.Workshop:BuildCooldownMessages(crafterName, entries)
    local messages = {}
    local now = GC.Util.Now()
    local crafterField = GC.Util.SafeChatText(GC.Util.Trim(crafterName or ""), 40)
    local batch = {}

    local function Flush()
        if #batch == 0 then
            return
        end
        local payload = EncodeCooldowns(batch, now)
        batch = {}
        if payload == "" then
            return
        end
        messages[#messages + 1] = BuildMessage({
            "W",
            GC.Constants.SCHEMA_VERSION,
            "CD",
            crafterField,
            payload,
        })
    end

    for _, entry in ipairs(entries or {}) do
        batch[#batch + 1] = entry
        if #batch >= MAX_COOLDOWNS_PER_MESSAGE then
            Flush()
        end
    end
    Flush()
    return messages
end

-- Die laufenden Sperren aller eigenen Charaktere. Ohne Ziel geht es an die
-- Gilde, sonst gezielt an den Fragenden. Wer nichts zu melden hat - der
-- Regelfall - sendet auch nichts.
function GC.Workshop:SendCooldowns(target)
    local now = GC.Util.Now()
    local lists, order = {}, {}
    for _, entry in ipairs(self:GetPublishableProfessions()) do
        for _, recipeKey in ipairs(SortedKeys(entry.profession.cooldowns)) do
            local readyAt = tonumber(entry.profession.cooldowns[recipeKey]) or 0
            if (readyAt - now) >= MIN_COOLDOWN_SECONDS then
                local crafterKey = GC.Util.PlayerKey(entry.crafter)
                local list = lists[crafterKey]
                if not list then
                    list = { crafter = entry.crafter, entries = {} }
                    lists[crafterKey] = list
                    order[#order + 1] = crafterKey
                end
                list.entries[#list.entries + 1] = { key = recipeKey, readyAt = readyAt }
            end
        end
    end

    local sent = 0
    for _, crafterKey in ipairs(order) do
        local list = lists[crafterKey]
        for _, message in ipairs(self:BuildCooldownMessages(list.crafter, list.entries)) do
            if GC.Sync:Send(message, target and "WHISPER" or "GUILD", target) then
                sent = sent + 1
            end
        end
    end
    return sent
end

-- === Bekannte Luecken ======================================================
--
-- Ein fremdes Manifest sagt, welche Berufe es in der Gilde gibt. Was davon hier
-- fehlt, ist eine Luecke mit Namen - und damit die einzige belastbare Antwort
-- auf "bin ich auf dem aktuellsten Stand?". Ohne diese Liste wuerde ein Client,
-- bei dem gerade kein Paket unterwegs ist, sich fuer vollstaendig halten,
-- obwohl er drei Berufe nie bekommen hat.

local function WantKey(crafter, professionKey)
    return GC.Util.PlayerKey(crafter) .. "|" .. tostring(professionKey or "")
end

function GC.Workshop:NoteWanted(entries)
    local now = GC.Util.Now()
    self.pendingWants = self.pendingWants or {}
    for _, entry in ipairs(entries or {}) do
        if GC.Util.Trim(entry.crafter) ~= "" and GC.Util.Trim(entry.professionKey) ~= "" then
            self.pendingWants[WantKey(entry.crafter, entry.professionKey)] = {
                crafter = entry.crafter,
                professionKey = entry.professionKey,
                at = now,
                -- Herkunft des angekuendigten Stands: Bleibt die Antwort aus,
                -- wird daraus die Bestandsluecke (siehe GetPendingWantCount).
                updatedAt = entry.updatedAt,
                fingerprintHash = entry.fingerprintHash,
                reportedBy = entry.reportedBy,
            }
        end
    end
    if GC.Sync and GC.Sync.WakeProgress then
        GC.Sync:WakeProgress()
    end
end

function GC.Workshop:ClearWanted(crafter, professionKey)
    if self.pendingWants then
        self.pendingWants[WantKey(crafter, professionKey)] = nil
    end
    if self.lostWants then
        self.lostWants[WantKey(crafter, professionKey)] = nil
    end
end

function GC.Workshop:GetPendingWantCount()
    local now = GC.Util.Now()
    local count = 0
    for key, want in pairs(self.pendingWants or {}) do
        if (now - (tonumber(want.at) or 0)) > WANT_TTL then
            self.pendingWants[key] = nil
            -- Ausgeblieben ist nicht erledigt. Bis 0.9.101 verschwand ein
            -- abgelaufener Eintrag lautlos: Der Zaehler fiel auf null, der
            -- Zyklus endete ohne Fehler, und ueber dem lueckenhaften Bestand
            -- stand "Vollstaendig synchronisiert - Stand: gerade eben". Jetzt
            -- wandert er in die Fehlbilanz des Zyklus (der Status wird
            -- "unvollstaendig") UND in die dauerhaften Bestandsluecken - dort
            -- bleibt er sichtbar, bis die Daten wirklich eintreffen.
            self.lostWants = self.lostWants or {}
            self.lostWants[key] = want
            self:NoteCoverageGap({
                crafter = want.crafter,
                professionKey = want.professionKey,
                updatedAt = want.updatedAt,
                fingerprintHash = want.fingerprintHash,
                reportedBy = want.reportedBy,
            })
        else
            count = count + 1
        end
    end
    return count
end

-- Berufe, deren angekuendigte Daten im laufenden Zyklus ausgeblieben sind.
-- Sie zaehlen als Fehlschlag wie ein verlorenes Paket; GetSyncStatus rechnet
-- sie in die Fehlbilanz ein. Ein neuer Zyklus beginnt mit leerer Liste
-- (ResetLostWants), trifft der Beruf spaeter doch ein, raeumt ClearWanted auf.
function GC.Workshop:GetLostWantCount()
    local count = 0
    for _ in pairs(self.lostWants or {}) do
        count = count + 1
    end
    return count
end

function GC.Workshop:ResetLostWants()
    self.lostWants = nil
end

-- Welche Berufe genau noch fehlen - fuer den Tooltip des Balkens.
function GC.Workshop:GetPendingWantNames(maximum)
    local names = {}
    local now = GC.Util.Now()
    for _, want in pairs(self.pendingWants or {}) do
        if (now - (tonumber(want.at) or 0)) <= WANT_TTL then
            names[#names + 1] = GC.Util.PlayerIdentityName(want.crafter)
        end
    end
    table.sort(names)
    while #names > (tonumber(maximum) or 6) do
        table.remove(names)
    end
    return names
end

-- Zerlegt Manifestdatensaetze in Pakete, die in den Chatrahmen passen. Ein
-- Zerleger fuer beide Manifeste ("KM" und "CM"): Die Datensaetze sind gleich
-- gebaut, nur die Operation unterscheidet sich.
local function ChunkManifestRecords(records, operation)
    local header = BuildMessage({ "W", GC.Constants.SCHEMA_VERSION, operation, "" })
    local payloadLimit = math.min(MAX_PAYLOAD_BYTES,
        GC.Constants.MAX_CHAT_BYTES - #header)
    local messages = {}
    local current = ""
    for _, record in ipairs(records) do
        local candidate = current == "" and record or (current .. ";" .. record)
        if #candidate > payloadLimit and current ~= "" then
            messages[#messages + 1] = BuildMessage({
                "W", GC.Constants.SCHEMA_VERSION, operation, current,
            })
            current = record
        else
            current = candidate
        end
    end
    if current ~= "" then
        messages[#messages + 1] = BuildMessage({
            "W", GC.Constants.SCHEMA_VERSION, operation, current,
        })
    end
    return messages
end

-- === Bestandsluecken ========================================================
--
-- Rezepte wandern nur vom besitzenden Account zu dem, der gerade zuhoert -
-- niemand leitet Daten Dritter weiter. Wer selten mit anderen gleichzeitig
-- online ist, dem fehlt deshalb der halbe Katalog, OHNE dass irgendetwas
-- "offen" waere: Sein Client hat nie erfahren, was es alles gibt. Genau daran
-- scheiterte die Statuszeile - sie meldete "Vollstaendig synchronisiert" ueber
-- einem Drittel des Bestands.
--
-- Die Bestandsluecke ist die fehlende Haelfte dieses Wissens: ein Beruf, den
-- es in der Gilde nachweislich gibt (per Manifest des Besitzers oder per
-- Bestandsmanifest eines Dritten), dessen Daten hier aber nie angekommen sind.
-- Sie zaehlt NICHT als offene Arbeit - anfordern liesse sich ja nichts, der
-- Besitzer ist offline -, sondern haelt die Statuszeile ehrlich: "Nichts
-- offen" und "vollstaendig" sind zwei verschiedene Aussagen. Sie lebt in den
-- SavedVariables und uebersteht den Relog; erledigt ist sie erst, wenn die
-- Daten wirklich da sind (ClaimRecipes), der Hersteller die Gilde verlaesst
-- (PruneDepartedCrafters) oder der Eintrag veraltet.

local function CoverageGapKey(crafter, professionKey)
    return GC.Util.PlayerKey(crafter) .. "|" .. tostring(professionKey or "")
end

-- Alle Charaktere dieses Accounts. Ueber die eigenen Berufe weiss der Client
-- selbst am besten Bescheid; als Bestandsluecke taugen sie nie.
local function OwnCharacterKeys()
    local keys = {}
    for characterKey, character in pairs((GC.DB.data and GC.DB.data.characters) or {}) do
        local characterName = (type(character) == "table" and character.fullName) or characterKey
        keys[GC.Util.PlayerKey(characterName)] = true
    end
    keys[GC.Util.PlayerKey(GC:GetPlayerFullName())] = true
    return keys
end

function GC.Workshop:NoteCoverageGap(entry)
    local crafter = GC.Util.Trim(entry and entry.crafter)
    local professionKey = NormalizeKey(entry and entry.professionKey)
    if crafter == "" or professionKey == "" then
        return false
    end
    local crafterKey = GC.Util.PlayerKey(crafter)
    if OwnCharacterKeys()[crafterKey] then
        return false
    end

    local workshop = self:GetGuildWorkshop()
    local known = workshop.crafters[crafterKey]
    local knownProfession = known and known.professions and known.professions[professionKey]
    local gapKey = CoverageGapKey(crafter, professionKey)
    -- Deckt der eigene Bestand den gemeldeten Stand bereits, gibt es keine
    -- Luecke - auch eine alte faellt dann weg.
    if knownProfession and not ProfessionWins(entry.updatedAt, entry.fingerprintHash,
        knownProfession.updatedAt, knownProfession.fingerprintHash) then
        workshop.coverageGaps[gapKey] = nil
        return false
    end

    local count = 0
    for _ in pairs(workshop.coverageGaps) do
        count = count + 1
    end
    if count >= MAX_COVERAGE_GAPS and not workshop.coverageGaps[gapKey] then
        return false
    end
    workshop.coverageGaps[gapKey] = {
        crafter = crafter,
        professionKey = professionKey,
        updatedAt = tonumber(entry.updatedAt) or 0,
        fingerprintHash = tostring(entry.fingerprintHash or ""),
        reportedBy = GC.Util.Trim(entry.reportedBy),
        at = GC.Util.Now(),
    }
    return true
end

-- Raeumt eine Luecke, sobald der eigene Bestand sie deckt. Aufgerufen aus
-- ClaimRecipes - auch dann, wenn der eintreffende Stand aelter war als der
-- vorhandene: Entscheidend ist, was jetzt im Index steht, nicht was zuletzt
-- ankam.
function GC.Workshop:ClearCoverageGapIfCovered(crafter, professionKey)
    professionKey = NormalizeKey(professionKey)
    local workshop = self:GetGuildWorkshop()
    local gapKey = CoverageGapKey(crafter, professionKey)
    local gap = workshop.coverageGaps[gapKey]
    if not gap then
        return
    end
    local known = workshop.crafters[GC.Util.PlayerKey(crafter)]
    local knownProfession = known and known.professions and known.professions[professionKey]
    if knownProfession and not ProfessionWins(gap.updatedAt, gap.fingerprintHash,
        knownProfession.updatedAt, knownProfession.fingerprintHash) then
        workshop.coverageGaps[gapKey] = nil
    end
end

-- Wie viele Berufe und Hersteller nachweislich fehlen. Veraltete Eintraege
-- verfallen hier, mit derselben Frist wie die Addon-Nutzerliste: Wen dreissig
-- Tage niemand mehr gemeldet hat, den fuehrt auch die Luecke nicht weiter.
function GC.Workshop:GetCoverageGapSummary()
    -- GetSyncStatus fragt hier bei jedem Takt nach - als einziger seiner
    -- Zaehler liegt dieser in den SavedVariables. Vor deren Initialisierung
    -- gibt es schlicht keine Luecken statt eines Fehlers.
    if not (GC.DB and GC.DB.data) then
        return { professions = 0, crafters = 0 }
    end
    local workshop = self:GetGuildWorkshop()
    local now = GC.Util.Now()
    local professions = 0
    local crafters = {}
    local crafterCount = 0
    for gapKey, gap in pairs(workshop.coverageGaps) do
        if (now - (tonumber(gap.at) or 0)) > GC.Constants.ADDON_USER_TTL then
            workshop.coverageGaps[gapKey] = nil
        else
            professions = professions + 1
            local crafterKey = GC.Util.PlayerKey(gap.crafter)
            if not crafters[crafterKey] then
                crafters[crafterKey] = true
                crafterCount = crafterCount + 1
            end
        end
    end
    return { professions = professions, crafters = crafterCount }
end

-- Welche Hersteller genau - fuer die Statuszeile.
function GC.Workshop:GetCoverageGapNames(maximum)
    local names = {}
    local seen = {}
    for _, gap in pairs(self:GetGuildWorkshop().coverageGaps) do
        local shortName = GC.Util.PlayerIdentityName(gap.crafter)
        if not seen[shortName] then
            seen[shortName] = true
            names[#names + 1] = shortName
        end
    end
    table.sort(names)
    while #names > (tonumber(maximum) or 6) do
        table.remove(names)
    end
    return names
end

-- Das Bestandsmanifest ("CM"): dieselben Datensaetze wie das eigene Manifest,
-- nur ueber FREMDE Hersteller - das Wissen, was es in der Gilde gibt, nicht
-- die Rezeptdaten selbst. Die bleiben beim Besitzer; ein Empfaenger merkt sich
-- nur die Luecke und holt die Daten, sobald der Besitzer wieder online ist.
-- Eigene Charaktere fehlen absichtlich: Die meldet jeder selbst per "KM",
-- und nur der Besitzer kennt ihren aktuellen Stand.
function GC.Workshop:BuildCoverageManifestMessages()
    local records = {}
    local ownKeys = OwnCharacterKeys()
    for crafterKey, crafter in pairs(self:GetGuildWorkshop().crafters) do
        if not ownKeys[crafterKey] and type(crafter) == "table" then
            for professionKey, profession in pairs(crafter.professions or {}) do
                records[#records + 1] = table.concat({
                    (GC.Util.Trim(crafter.name or crafterKey):gsub(",", "")),
                    professionKey,
                    tostring(tonumber(profession.updatedAt) or 0),
                    tostring(RecipeKeyCount(profession)),
                    tostring(tonumber(profession.fingerprintHash) or 0),
                }, ",")
            end
        end
    end
    if #records == 0 then
        return {}
    end
    table.sort(records)
    return ChunkManifestRecords(records, "CM")
end

function GC.Workshop:SendCoverageManifest()
    if not GC.Sync or not IsInGuild or not IsInGuild() then
        return false
    end
    local messages = self:BuildCoverageManifestMessages()
    if #messages == 0 then
        return false
    end
    for _, message in ipairs(messages) do
        if #message <= GC.Constants.MAX_CHAT_BYTES then
            GC.Sync:SendBulk(message, "GUILD")
        end
    end
    return true
end

-- Gestreut wie die Manifestantwort daneben und aus demselben Grund; gewaehlt
-- wird trotzdem (anders als beim "KM"): Ein Bestandsmanifest beschreibt
-- fremde Staende, und die kennen viele Clients gleichermassen - es muss also
-- nicht jeder schicken.
function GC.Workshop:ScheduleCoverageReply()
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return self:SendCoverageManifest()
    end
    C_Timer.After(1 + math.random() * MANIFEST_REPLY_SPREAD, function()
        GC.Workshop:SendCoverageManifest()
    end)
    return true
end

-- === Botendienst fuer Rezeptdetails ========================================
--
-- Rezeptdetails (Name, Reagenzien) haengen am Rezept, nicht am Spieler - sie
-- stehen im Katalog jedes Clients, der sie je empfangen hat. Eine
-- Nachforderung ("N") kann deshalb auch ein Dritter beantworten, wenn der
-- Besitzer offline ist. Der Transfer traegt dabei den Stand DES BESITZERS
-- (craftedBy, updatedAt, Fingerabdruck aus dem Herstellerindex), nie eigene
-- Zeitstempel: Die Uebernahme beim Empfaenger entscheidet damit nach
-- derselben Regel wie immer, und ein Bote kann einen neueren Stand nie
-- zurueckdrehen.

-- Geplant wird nur, wenn der Besitzer nicht selbst antworten kann: Ist er als
-- Addon-Nutzer online, hielte der Bote nur dagegen.
function GC.Workshop:ScheduleRelayedRecipeAnswer(crafterName, recipeKeys)
    local member = GC.Roster and GC.Roster.GetMember and GC.Roster:GetMember(crafterName)
    if member and member.online and GC.Sync and GC.Sync.GetAddonUser
        and GC.Sync:GetAddonUser(crafterName) then
        return false
    end
    local scheduledAt = GC.Util.Now()
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return self:SendRelayedRecipeAnswer(crafterName, recipeKeys, scheduledAt)
    end
    C_Timer.After(1 + math.random() * MANIFEST_REPLY_SPREAD, function()
        GC.Workshop:SendRelayedRecipeAnswer(crafterName, recipeKeys, scheduledAt)
    end)
    return true
end

function GC.Workshop:SendRelayedRecipeAnswer(crafterName, recipeKeys, scheduledAt)
    local crafterKey = GC.Util.PlayerKey(crafterName)
    local crafterEntry = self:GetGuildWorkshop().crafters[crafterKey]
    if not crafterEntry or type(crafterEntry.professions) ~= "table" then
        return false
    end
    -- Nach Beruf gruppiert: Der Transferumschlag traegt den Stand des
    -- Besitzers, und der haengt am Beruf. Geliefert wird nur, was der Katalog
    -- vollstaendig hat UND was der Hersteller laut Index wirklich kann.
    local groups = {}
    for _, recipeKey in ipairs(recipeKeys or {}) do
        local entry = self:GetCatalogEntry(recipeKey)
        if entry and #(entry.reagents or {}) > 0 then
            local professionKey = NormalizeKey(entry.professionKey or entry.profession)
            local profession = crafterEntry.professions[professionKey]
            if profession and (profession.recipeKeys or {})[recipeKey] then
                local group = groups[professionKey]
                if not group then
                    group = { profession = profession, recipes = {}, filter = {} }
                    groups[professionKey] = group
                end
                group.recipes[recipeKey] = entry
                group.filter[recipeKey] = true
            end
        end
    end
    local queued = false
    for professionKey, group in pairs(groups) do
        -- Hat inzwischen ein anderer geliefert - der zweite gewaehlte Bote
        -- oder doch der Besitzer -, schweigt dieser hier.
        if not (GC.Sync and GC.Sync.PeerAnsweredSince
            and GC.Sync:PeerAnsweredSince("WDETAIL|" .. crafterKey .. "|" .. professionKey,
                scheduledAt)) then
            self:QueueProfessionSync({
                key = professionKey,
                name = group.profession.name,
                updatedAt = group.profession.updatedAt,
                -- Ein alter Indexeintrag ohne Fingerabdruck bekommt "0": Der
                -- verliert beim Empfaenger jeden Gleichstand, die
                -- Katalogdetails kommen trotzdem an - genau richtig fuer
                -- eine Nachlieferung.
                fingerprintHash = group.profession.fingerprintHash or "0",
                recipes = group.recipes,
            }, true, nil, nil, crafterEntry.name or crafterName, group.filter)
            queued = true
        end
    end
    return queued
end

-- === Fluesterbefehl "!rezept" ===============================================
--
-- Nach dem Vorbild von Pro Enchanters (dort "!enchant ..."), aber als
-- Gildendienst statt Handelsgeschaeft: Ein Gildenmitglied fluestert
-- "!rezept <suche>" und bekommt Materialliste und Hersteller aus dem Katalog.
-- Selbst gebaut auf der eigenen Suche - der Katalog kann das laengst, es
-- fehlte nur der Chat-Zugang fuer Leute ohne das Addon.
--
-- Drei bewusste Grenzen: Das Addon fluestert NIE von selbst, solange der
-- Schalter aus ist (Vorgabe: aus - "keine heimliche Chateingabe" gilt auch
-- fuer Antworten). Es antwortet nur Gildenmitgliedern - der Katalog ist
-- Gildenwissen. Und je Absender hoechstens alle RECIPE_WHISPER_THROTTLE
-- Sekunden, damit niemand einen Antwortautomaten melken kann.

local RECIPE_WHISPER_PREFIXES = { "!rezept ", "!recipe ", "!enchant " }
local RECIPE_WHISPER_THROTTLE = 20
local MAX_RECIPE_WHISPER_SENDERS = 60

function GC.Workshop:AnswerRecipeWhisper(message, sender)
    message = tostring(message or "")
    local query
    local lowered = message:lower()
    for _, prefix in ipairs(RECIPE_WHISPER_PREFIXES) do
        if lowered:sub(1, #prefix) == prefix then
            query = GC.Util.Trim(message:sub(#prefix + 1))
            break
        end
    end
    if not query then
        return false
    end

    -- Ab hier gilt die Nachricht als behandelt: Ein Befehl gehoert nie ins
    -- Bewerber-Postfach, auch wenn die Antwort unterbleibt.
    if GC.DB:GetSettings().workshopWhisperReply ~= true or query == "" then
        return true
    end
    if #GC.Roster.members > 0 and not GC.Roster:IsGuildMember(sender) then
        return true
    end
    local senderKey = GC.Util.PlayerKey(sender)
    local now = GC.Util.Now()
    self.recipeWhisperReplies = self.recipeWhisperReplies or {}
    PruneSuppressed(self.recipeWhisperReplies, RECIPE_WHISPER_THROTTLE,
        MAX_RECIPE_WHISPER_SENDERS)
    local last = self.recipeWhisperReplies[senderKey]
    if senderKey == "" or (last and (now - last) < RECIPE_WHISPER_THROTTLE) then
        return true
    end
    self.recipeWhisperReplies[senderKey] = now

    local matches = self:GetCatalog(query)
    local reply
    if #matches == 0 then
        reply = "Guild Copilot Forever: Zu „" .. GC.Util.SafeChatText(query, 40)
            .. "“ steht nichts im Gildenkatalog."
    else
        local entry = matches[1]
        local parts = {}
        for _, reagent in ipairs(entry.reagents or {}) do
            parts[#parts + 1] = tostring(reagent.count or 1) .. "×"
                .. ResolveItemName(reagent.itemID, reagent.name)
        end
        local crafters = {}
        for index = 1, math.min(3, #entry.crafters) do
            crafters[index] = entry.crafters[index]
        end
        if #entry.crafters > #crafters then
            crafters[#crafters + 1] = "+" .. (#entry.crafters - #crafters) .. " weitere"
        end
        reply = "Guild Copilot Forever: " .. entry.name
            .. (#parts > 0 and (" – Mats: " .. table.concat(parts, ", ")) or "")
            .. (#entry.crafters > 0 and (" – können: " .. table.concat(crafters, ", ")) or "")
            .. (#matches > 1 and (" (+" .. (#matches - 1) .. " Treffer)") or "")
    end
    if GC.Chat and GC.Chat.SendChat then
        GC.Chat:SendChat(GC.Util.SafeChatText(reply), "WHISPER", nil, nil, sender)
    end
    return true
end

-- Manifest fuer den Gildenkanal: je Beruf des Accounts nur Hersteller,
-- Zeitstempel, Anzahl und Fingerabdruck. Wer nichts Neues hat, kostet damit ein
-- Paket pro Login statt einer vollen Schluesselliste.
function GC.Workshop:BuildKeyManifestMessages()
    local records = {}
    for _, entry in ipairs(self:GetPublishableProfessions()) do
        local profession = entry.profession
        local fingerprintHash = profession.fingerprintHash
            or FingerprintHash(profession.fingerprint or RecipeFingerprint(profession))
        records[#records + 1] = table.concat({
            (GC.Util.Trim(entry.crafter):gsub(",", "")),
            profession.key,
            tostring(tonumber(profession.updatedAt) or 0),
            tostring(RecipeCount(profession)),
            fingerprintHash,
        }, ",")
    end
    if #records == 0 then
        return {}
    end
    table.sort(records)
    return ChunkManifestRecords(records, "KM")
end

function GC.Workshop:SendKeyManifest()
    if not GC.Sync or not IsInGuild or not IsInGuild() then
        return false
    end
    local messages = self:BuildKeyManifestMessages()
    if #messages == 0 then
        return false
    end
    for _, message in ipairs(messages) do
        if #message <= GC.Constants.MAX_CHAT_BYTES then
            GC.Sync:SendBulk(message, "GUILD")
        end
    end
    return true
end

-- Die Antwort auf eine Werkstatt-Anfrage wird GESTREUT, nicht gewaehlt.
--
-- Hier stand zwischenzeitlich beides: die Wahl der Antwortenden und die
-- Stille beim Sehen einer fremden Antwort. Beides war an dieser Stelle
-- falsch, und zwar aus demselben Grund.
--
-- Ein Manifest beschreibt ausschliesslich die Berufe des EIGENEN Accounts
-- (BuildKeyManifestMessages baut es aus GetAccountProfessions). Kein anderer
-- Client kann es liefern. Mit der Wahl bekam der Fragende die Berufe von drei
-- Spielern statt von der ganzen Gilde, und die Stille nahm ihm noch die
-- uebrigen zwei: Ein fremdes "KM" belegt eben nicht, dass die eigenen Berufe
-- schon gemeldet sind - es belegt das Gegenteil, naemlich dass gerade jemand
-- ANDERES seine gemeldet hat.
--
-- Wo jeder etwas Eigenes beitraegt, hilft nur Streuung in der Zeit. Alle
-- antworten, aber verteilt: Das Manifest ist ein bis drei Pakete, bei 250
-- Online also hoechstens rund 750 - verteilt ueber MANIFEST_REPLY_SPREAD
-- Sekunden gut zwei Dutzend je Sekunde gildenweit. Das ist die Groessenordnung,
-- die der Kanal traegt, und es ist genau der Verkehr, um dessentwillen es das
-- Manifest ueberhaupt gibt: Es ersetzt die vollen Rezeptlisten, die frueher an
-- dieser Stelle gingen.
function GC.Workshop:ScheduleKeyManifestReply()
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return self:SendKeyManifest()
    end
    C_Timer.After(1 + math.random() * MANIFEST_REPLY_SPREAD, function()
        GC.Workshop:SendKeyManifest()
    end)
    return true
end

-- Der Vollversand an einen Client ohne Manifest-Verstaendnis. Dieselbe
-- Begruendung wie oben, nur mit deutlich weiterem Fenster: Hier gehen je
-- Antwortendem Dutzende Pakete raus, und alle 250 gleichzeitig loswerden zu
-- wollen hiesse, den Kanal fuer alles andere zu schliessen. Ueber
-- FULL_REPLY_SPREAD Sekunden verteilt bleibt der Durchsatz in der
-- Groessenordnung, die der Kanal traegt - und der Altclient bekommt trotzdem
-- den vollstaendigen Bestand statt eines Ausschnitts.
--
-- "compact" wird uebergeben statt hier ermittelt: SupportsCompactWorkshop ist
-- eine lokale Funktion und steht weiter unten in der Datei. Ein Aufruf von
-- hier aus waere zur Uebersetzungszeit noch kein lokaler Name gewesen und
-- haette als Zugriff auf eine nicht vorhandene Globale geendet - also immer
-- nil, und der Vollversand waere ohne Meldung im falschen Format rausgegangen.
-- Dieselbe Streuung fuer die laufenden Sperren. Sie sind ein Paket je
-- Hersteller und damit so klein wie das Manifest; sie teilen sich deshalb
-- dessen Fenster.
function GC.Workshop:ScheduleCooldownReply()
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return self:SendCooldowns()
    end
    C_Timer.After(1 + math.random() * MANIFEST_REPLY_SPREAD, function()
        GC.Workshop:SendCooldowns()
    end)
    return true
end

function GC.Workshop:ScheduleFullProfessionReply(compact)
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return self:QueueAllProfessions(compact, nil, nil, true)
    end
    C_Timer.After(1 + math.random() * FULL_REPLY_SPREAD, function()
        GC.Workshop:QueueAllProfessions(compact, nil, nil, true)
    end)
    return true
end

-- Fordert die Schluesselliste eines fremden Berufs an - gestreut und nur einmal,
-- damit nicht alle gleichzeitig dasselbe verlangen.
function GC.Workshop:ScheduleKeyListRequest(wanted)
    self.suppressedKeyRequests = self.suppressedKeyRequests or {}
    -- Sammelnd aufraeumen, nach derselben Bauweise wie die unterdrueckten
    -- Rezeptanfragen daneben.
    PruneSuppressed(self.suppressedKeyRequests, MISSING_REQUEST_SUPPRESS,
        MAX_SUPPRESSED_KEY_REQUESTS)
    local now = GC.Util.Now()
    local pending = {}
    for _, entry in ipairs(wanted or {}) do
        local suppressKey = GC.Util.PlayerKey(entry.crafter) .. "|" .. entry.professionKey
        local suppressedAt = self.suppressedKeyRequests[suppressKey]
        if not suppressedAt or (now - suppressedAt) > MISSING_REQUEST_SUPPRESS then
            pending[#pending + 1] = entry
        end
    end
    if #pending == 0 then
        return false
    end
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return self:SendKeyListRequest(pending)
    end
    C_Timer.After(1 + math.random() * MISSING_REQUEST_DELAY, function()
        GC.Workshop:SendKeyListRequest(pending)
    end)
    return true
end

function GC.Workshop:SendKeyListRequest(wanted)
    if not GC.Sync then
        return false
    end
    self.suppressedKeyRequests = self.suppressedKeyRequests or {}
    local now = GC.Util.Now()
    -- Gruppiert je Hersteller UND Boten: Eine Anfrage an den Besitzer traegt
    -- kein sechstes Feld, eine an einen Boten dessen Namen - beides fuer
    -- denselben Hersteller zu mischen ergaebe zwei halbe Nachrichten.
    local groups = {}
    local order = {}
    for _, entry in ipairs(wanted or {}) do
        local suppressKey = GC.Util.PlayerKey(entry.crafter) .. "|" .. entry.professionKey
        local suppressedAt = self.suppressedKeyRequests[suppressKey]
        if not suppressedAt or (now - suppressedAt) > MISSING_REQUEST_SUPPRESS then
            self.suppressedKeyRequests[suppressKey] = now
            local relayTarget = GC.Util.Trim(entry.relayTarget)
            local groupKey = entry.crafter .. "\031" .. relayTarget
            if not groups[groupKey] then
                groups[groupKey] = { crafter = entry.crafter, relayTarget = relayTarget, keys = {} }
                order[#order + 1] = groupKey
            end
            local list = groups[groupKey].keys
            -- Angefragt wird mit dem Schluessel, den der Angesprochene selbst
            -- gemeldet hat - nur den versteht auch ein Altclient sicher.
            list[#list + 1] = entry.requestKey or entry.professionKey
        end
    end
    if #order == 0 then
        return false
    end
    for _, groupKey in ipairs(order) do
        local group = groups[groupKey]
        local fields = {
            "W",
            GC.Constants.SCHEMA_VERSION,
            "KR",
            GC.Util.SafeChatText(GC.Util.Trim(group.crafter), 40),
            table.concat(group.keys, ","),
        }
        -- Das sechste Feld adressiert einen Boten: Der Genannte antwortet aus
        -- seinem Herstellerindex, alle anderen schweigen. Aeltere Clients
        -- lesen das Feld nicht - sie antworten wie bisher nur als Besitzer.
        if group.relayTarget ~= "" then
            fields[6] = GC.Util.SafeChatText(group.relayTarget, 40)
        end
        local message = BuildMessage(fields)
        if #message <= GC.Constants.MAX_CHAT_BYTES then
            GC.Sync:SendBulk(message, "GUILD")
        end
    end
    return true
end

function GC.Workshop:BuildManifestMessages()
    local records = {}
    for _, professionKey in ipairs(SortedKeys(self:GetOwnData().professions)) do
        local profession = self:GetOwnData().professions[professionKey]
        local fingerprintHash = profession.fingerprintHash
            or FingerprintHash(profession.fingerprint or RecipeFingerprint(profession))
        records[#records + 1] = table.concat({
            profession.key,
            tostring(profession.updatedAt or 0),
            tostring(RecipeCount(profession)),
            fingerprintHash,
        }, ",")
    end
    local messages = {}
    local current = ""
    for _, record in ipairs(records) do
        local candidate = current == "" and record or (current .. ";" .. record)
        if #candidate > MAX_PAYLOAD_BYTES and current ~= "" then
            messages[#messages + 1] = BuildMessage({
                "W",
                GC.Constants.SCHEMA_VERSION,
                "M",
                current,
            })
            current = record
        else
            current = candidate
        end
    end
    if current ~= "" then
        messages[#messages + 1] = BuildMessage({
            "W",
            GC.Constants.SCHEMA_VERSION,
            "M",
            current,
        })
    end
    return messages
end

function GC.Workshop:SendManifest(target)
    if GC.Util.Trim(target) == "" or not GC.Sync then
        return false
    end
    local messages = self:BuildManifestMessages()
    if #messages == 0 then
        return false
    end
    local queued = true
    for _, message in ipairs(messages) do
        queued = GC.Sync:SendBulk(message, "WHISPER", target) and queued
    end
    return queued
end

local function DecodeRecipeRecord(record, professionName)
    local recipeKey, itemID, recipeName, reagentText = record:match("^([^,]+),([^,]*),([^,]*),?(.*)$")
    if not recipeKey then
        return nil
    end
    itemID = tonumber(itemID)
    local reagents = {}
    for reagentToken in tostring(reagentText or ""):gmatch("[^.]+") do
        local reagentID, count = reagentToken:match("^(%d+):(%d+)$")
        if reagentID then
            reagentID = tonumber(reagentID)
            reagents[#reagents + 1] = {
                itemID = reagentID,
                -- Kein Platzhalter in die Ablage: Was der Cache jetzt nicht
                -- kennt, bleibt nil und wird beim Katalogaufbau erneut
                -- aufgeloest, sobald der Client den Gegenstand nachgeladen hat.
                name = LookupItemName(reagentID),
                count = tonumber(count) or 1,
            }
        end
    end
    return {
        key = recipeKey,
        itemID = itemID and itemID > 0 and itemID or nil,
        name = ResolveItemName(itemID, recipeName ~= "" and recipeName or recipeKey),
        profession = professionName,
        reagents = reagents,
    }
end

local function DecodeCompactRecipeRecord(record, professionName)
    local recipeKey, recipeName, reagentText = record:match("^([^,]+),([^,]*),(.*)$")
    if not recipeKey then
        return nil
    end

    local itemID = tonumber(recipeKey:match("^I(%d+)$"))
    local recipeID = tonumber(recipeKey:match("^E(%d+)$"))
    local reagents = {}
    for reagentToken in tostring(reagentText or ""):gmatch("[^.]+") do
        local reagentID, count = reagentToken:match("^(%d+):(%d+)$")
        if reagentID then
            reagentID = tonumber(reagentID)
            reagents[#reagents + 1] = {
                itemID = reagentID,
                -- Wie im Langformat: nil statt Platzhalter, aufgeloest wird
                -- beim Katalogaufbau - dann mit gefuelltem Item-Cache.
                name = LookupItemName(reagentID),
                count = tonumber(count) or 1,
            }
        end
    end
    return {
        key = recipeKey,
        recipeID = recipeID,
        itemID = itemID,
        name = ResolveRecipeName(recipeKey, recipeName ~= "" and recipeName or nil),
        profession = professionName,
        reagents = reagents,
    }
end

local function SupportsCompactWorkshop(sender)
    local user = GC.Sync and GC.Sync.GetAddonUser and GC.Sync:GetAddonUser(sender)
    local capabilities = user and tostring(user.capabilities or "") or ""
    return ("," .. capabilities .. ","):find(",workshop2,", 1, true) ~= nil
end

local function SupportsKeyListWorkshop(sender)
    local user = GC.Sync and GC.Sync.GetAddonUser and GC.Sync:GetAddonUser(sender)
    local capabilities = user and tostring(user.capabilities or "") or ""
    return ("," .. capabilities .. ","):find(",workshop4,", 1, true) ~= nil
end

local function SupportsReliableWorkshop(sender)
    local user = GC.Sync and GC.Sync.GetAddonUser and GC.Sync:GetAddonUser(sender)
    local capabilities = user and tostring(user.capabilities or "") or ""
    return ("," .. capabilities .. ","):find(",workshop3,", 1, true) ~= nil
end

local function SupportsCoverageWorkshop(sender)
    local user = GC.Sync and GC.Sync.GetAddonUser and GC.Sync:GetAddonUser(sender)
    local capabilities = user and tostring(user.capabilities or "") or ""
    return ("," .. capabilities .. ","):find(",workshop5,", 1, true) ~= nil
end

local function SupportsRelayWorkshop(sender)
    local user = GC.Sync and GC.Sync.GetAddonUser and GC.Sync:GetAddonUser(sender)
    local capabilities = user and tostring(user.capabilities or "") or ""
    return ("," .. capabilities .. ","):find(",workshop6,", 1, true) ~= nil
end

function GC.Workshop:ReceiveSync(fields, sender, distribution)
    local operation = fields[3]
    if operation == "Q" then
        local senderKey = GC.Util.PlayerKey(sender)
        local now = GC.Util.Now()
        self.requestReplies = self.requestReplies or {}
        -- Aufgeraeumt wird sammelnd, nach derselben Bauweise wie bei den
        -- unterdrueckten Rezeptanfragen: Ein Eintrag, der aelter ist als die
        -- Drosselzeit, bewirkt nichts mehr.
        PruneSuppressed(self.requestReplies, MIN_REQUEST_REPLY_INTERVAL, MAX_REQUEST_REPLIES)
        local lastReply = self.requestReplies[senderKey]
        if senderKey == ""
            or (lastReply and (now - lastReply) < MIN_REQUEST_REPLY_INTERVAL) then
            return
        end
        self.requestReplies[senderKey] = now
        -- Der Abgleich läuft über den Gildenkanal, weil Addon-Flüster in
        -- manchen Umgebungen nicht ankommen. Entscheidend ist, was *dieser*
        -- Fragende versteht: kennt er Manifeste, bekommt er nur eines (ein
        -- Paket) und fordert daraus gezielt an, was ihm fehlt. Nur ein Client
        -- ohne Manifest-Verständnis braucht den vollen Bestand. Früher
        -- entschied das die Gilde als Ganzes - ein einziger veralteter Eintrag
        -- ließ dann jeden Abgleich zum Vollversand werden.
        --
        -- Gestreut wird beides, gewaehlt wird nichts: Jeder Client traegt hier
        -- die Berufe SEINES Accounts bei, und die kann kein anderer fuer ihn
        -- melden. Naeheres im Kopf von ScheduleKeyManifestReply.
        if SupportsKeyListWorkshop(sender) then
            self:ScheduleKeyManifestReply()
        else
            -- Der Vollversand an einen Altclient ist der teure Fall: gemessen
            -- 66 Pakete je Antwortendem. Er trifft nur noch Clients, die
            -- "workshop4" nicht melden - seit 0.9.96 gibt es die praktisch
            -- nicht mehr -, und er wird deshalb besonders weit gestreut,
            -- statt ihn zu beschneiden. Beschneiden hiesse hier: dem
            -- Altclient die halbe Gilde vorenthalten.
            self:ScheduleFullProfessionReply(SupportsCompactWorkshop(sender))
        end
        -- Wer frisch eingeloggt ist, kennt die laufenden Sperren nicht. Sie
        -- haengen an keinem Rezeptstand und wuerden deshalb von Manifest und
        -- Nachforderung nicht erfasst. Ein Paket, und nur, wenn es ueberhaupt
        -- etwas zu melden gibt.
        --
        -- Gestreut wie das Manifest daneben, und aus demselben Grund: Auch
        -- eine Sperre gehoert dem eigenen Account, kein anderer kann sie
        -- melden. Es antworten also alle - nur nicht alle gleichzeitig.
        self:ScheduleCooldownReply()
        -- Das Bestandsmanifest dagegen schicken nur Gewaehlte: Fremde Staende
        -- kennen viele Clients gleichermassen, drei Antworten decken den
        -- Fragenden ein. Nur fuer Clients, die "CM" auch verstehen - ein
        -- Altclient wirft die Pakete stumm weg, und umsonst gesendet ist
        -- trotzdem gesendet.
        if SupportsCoverageWorkshop(sender) and GC.Sync and GC.Sync.IsElectedResponder
            and GC.Sync:IsElectedResponder(sender, COVERAGE_RESPONDER_SLOTS) then
            self:ScheduleCoverageReply()
        end
        return
    elseif operation == "M" then
        local senderKey = GC.Util.PlayerKey(sender)
        if senderKey == "" or distribution ~= "WHISPER" then
            return
        end
        local crafter = GC.DB:GetGuild().workshop.crafters[senderKey]
        local requested = {}
        for record in tostring(fields[4] or ""):gmatch("[^;]+") do
            local professionKey, updatedText, countText, fingerprintHash =
                record:match("^([^,]+),(%d+),(%d+),(%d+)$")
            local updatedAt = tonumber(updatedText)
            local recipeCount = tonumber(countText)
            -- Verglichen wird kanonisch (der eigene Bestand liegt so vor),
            -- angefordert aber mit dem Schluessel DES ABSENDERS: Ein Altclient
            -- mit englischer Spielsprache findet "verzauberkunst" in seinen
            -- Daten nicht - seinen eigenen Schluessel versteht er immer.
            local known = crafter and crafter.professions
                and crafter.professions[NormalizeKey(professionKey)]
            -- Dieselbe gemeinsame Regel wie oben: angefordert wird nur, was
            -- die Uebernahme spaeter auch annimmt.
            if professionKey and #professionKey <= 80 and updatedAt and recipeCount
                and #fingerprintHash <= 20
                and (not known
                    or ProfessionWins(updatedAt, fingerprintHash,
                        known.updatedAt, known.fingerprintHash)) then
                requested[#requested + 1] = professionKey
            end
        end
        for _, professionKey in ipairs(requested) do
            GC.Sync:Send(BuildMessage({
                "W",
                GC.Constants.SCHEMA_VERSION,
                "R",
                professionKey,
            }), "WHISPER", sender)
        end
        return
    elseif operation == "R" then
        if distribution ~= "WHISPER" then
            return
        end
        local professionKey = NormalizeKey(fields[4])
        local profession = self:GetOwnData().professions[professionKey]
        if profession then
            self:QueueProfessionSync(profession, true, sender, true)
        end
        return
    elseif operation == "KM" then
        -- Ein fremdes Manifest. Angefordert wird nur, was hier nachweislich
        -- fehlt oder veraltet ist; unveraenderte Berufe kosten null Pakete.
        --
        -- Hier stand kurzzeitig ein Vermerk "ein anderer hat geantwortet", der
        -- die eigene, noch geplante Antwort fallen liess. Das war genau
        -- verkehrt herum gedacht: Ein fremdes Manifest traegt die Berufe eines
        -- ANDEREN Accounts und belegt damit gerade nicht, dass die eigenen
        -- schon gemeldet sind.
        local wanted = {}
        local crafters = self:GetGuildWorkshop().crafters
        for record in tostring(fields[4] or ""):gmatch("[^;]+") do
            local crafter, professionKey, updatedText, countText, fingerprint =
                record:match("^([^,]+),([^,]+),(%d+),(%d+),(%d+)$")
            local updatedAt = tonumber(updatedText)
            local recipeCount = tonumber(countText)
            if crafter and professionKey and updatedAt and recipeCount
                and #crafter <= 60 and #professionKey <= 80 and #fingerprint <= 20 then
                local known = crafters[GC.Util.PlayerKey(crafter)]
                -- Verglichen und vorgemerkt wird kanonisch; die Nachfrage beim
                -- Absender traegt dessen eigenen Schluessel (requestKey), denn
                -- ein Altclient englischer Spielsprache kennt nur den.
                local knownProfession = known and known.professions
                    and known.professions[NormalizeKey(professionKey)]
                -- Angefordert wird nur, was die Uebernahme spaeter auch
                -- annimmt. Vorher stand hier eine reine Ungleichheitspruefung:
                -- Sie meldete auch nachweislich AELTERE Staende als "fehlt",
                -- der Absender schickte sie, und die Uebernahme verwarf sie
                -- genau deshalb wieder - bei jedem Manifest von neuem. Die
                -- Anzahl faellt als Kriterium weg; sie steckt im
                -- Fingerabdruck.
                local stale = not knownProfession
                    or ProfessionWins(updatedAt, fingerprint,
                        knownProfession.updatedAt, knownProfession.fingerprintHash)
                if stale then
                    wanted[#wanted + 1] = {
                        crafter = crafter,
                        professionKey = NormalizeKey(professionKey),
                        requestKey = professionKey,
                        -- Fuer die Bestandsluecke, falls die Antwort ausbleibt:
                        -- welcher Stand angekuendigt war und von wem.
                        updatedAt = updatedAt,
                        fingerprintHash = fingerprint,
                        reportedBy = sender,
                    }
                end
            end
        end
        if #wanted > 0 then
            -- Erst vormerken, dann anfragen: Vorgemerkt ist die Luecke auch
            -- dann, wenn die Anfrage gerade unterdrueckt wird, weil ein anderer
            -- sie schon gestellt hat.
            self:NoteWanted(wanted)
            self:ScheduleKeyListRequest(wanted)
        end
        return
    elseif operation == "CM" then
        -- Ein Bestandsmanifest: Wissen aus zweiter Hand darueber, welche
        -- Hersteller es in der Gilde gibt. Gemerkt wird die Luecke - sie haelt
        -- die Statuszeile ehrlich und raeumt sich weg, sobald die Daten
        -- eintreffen.
        --
        -- Und seit dem Botendienst wird sie auch gefuellt: Der Absender hat
        -- die Staende nachweislich (er hat sie gerade aufgezaehlt) und ist
        -- nachweislich online. Kann er adressierte Anfragen beantworten
        -- (workshop6), wird die Schluesselliste direkt BEI IHM angefordert -
        -- der Besitzer muss dafuer nicht mehr online kommen. Bei einem
        -- aelteren Absender bleibt es beim blossen Wissen: Er liesse die
        -- adressierte Anfrage stumm liegen, und der Zyklus endete grundlos
        -- als "unvollstaendig".
        local changed = false
        local wanted = {}
        local relayCapable = SupportsRelayWorkshop(sender)
        for record in tostring(fields[4] or ""):gmatch("[^;]+") do
            local crafter, professionKey, updatedText, countText, fingerprint =
                record:match("^([^,]+),([^,]+),(%d+),(%d+),(%d+)$")
            local updatedAt = tonumber(updatedText)
            if crafter and professionKey and updatedAt and tonumber(countText)
                and #crafter <= 60 and #professionKey <= 80 and #fingerprint <= 20 then
                if self:NoteCoverageGap({
                    crafter = crafter,
                    professionKey = professionKey,
                    updatedAt = updatedAt,
                    fingerprintHash = fingerprint,
                    reportedBy = sender,
                }) then
                    changed = true
                    if relayCapable then
                        wanted[#wanted + 1] = {
                            crafter = crafter,
                            professionKey = NormalizeKey(professionKey),
                            requestKey = professionKey,
                            updatedAt = updatedAt,
                            fingerprintHash = fingerprint,
                            reportedBy = sender,
                            relayTarget = sender,
                        }
                    end
                end
            end
        end
        if #wanted > 0 then
            -- Dieselbe Reihenfolge wie beim Manifest des Besitzers: erst
            -- vormerken, dann anfragen - vorgemerkt bleibt die Luecke auch,
            -- wenn die Anfrage gerade unterdrueckt ist.
            self:NoteWanted(wanted)
            self:ScheduleKeyListRequest(wanted)
        end
        if changed then
            GC:FireCallback("WORKSHOP_UPDATED")
        end
        return
    elseif operation == "KR" then
        -- Jemand verlangt die Schluesselliste eines Berufs. Angesprochen ist der
        -- genannte Hersteller; auch eine fremde Anfrage unterdrueckt die eigene.
        local wantedCrafter = GC.Util.Trim(fields[4] or "")
        local wantedKey = GC.Util.PlayerKey(wantedCrafter)
        self.suppressedKeyRequests = self.suppressedKeyRequests or {}
        PruneSuppressed(self.suppressedKeyRequests, MISSING_REQUEST_SUPPRESS,
            MAX_SUPPRESSED_KEY_REQUESTS)
        local requested = {}
        for professionKey in tostring(fields[5] or ""):gmatch("[^,]+") do
            requested[NormalizeKey(professionKey)] = true
            self.suppressedKeyRequests[wantedKey .. "|" .. NormalizeKey(professionKey)] =
                GC.Util.Now()
        end
        if wantedKey == "" or not next(requested) then
            return
        end
        local ownAnswered = false
        for _, entry in ipairs(self:GetPublishableProfessions()) do
            if GC.Util.PlayerKey(entry.crafter) == wantedKey
                and requested[entry.profession.key] then
                self:QueueKeyList(entry.profession, entry.crafter)
                ownAnswered = true
            end
        end
        -- Der Botendienst: Nennt das sechste Feld DIESEN Client, antwortet er
        -- aus seinem Herstellerindex - mit dem Stand und den Zeitstempeln des
        -- Besitzers, nicht mit eigenen. Es antwortet genau der eine Genannte;
        -- alle anderen haben oben nur ihre Unterdrueckung gesetzt. So bleibt
        -- die Regel auch bei 250 Online gewahrt: eine Frage, ein Antworter.
        local relayTarget = GC.Util.Trim(fields[6] or "")
        if not ownAnswered and relayTarget ~= ""
            and GC.Util.PlayerKey(relayTarget) == GC.Util.PlayerKey(GC:GetPlayerFullName()) then
            local crafterEntry = self:GetGuildWorkshop().crafters[wantedKey]
            for professionKey in pairs(requested) do
                local profession = crafterEntry and crafterEntry.professions
                    and crafterEntry.professions[professionKey]
                if profession then
                    self:QueueKeyList(profession, crafterEntry.name or wantedCrafter)
                end
            end
        end
        return
    elseif operation == "N" then
        -- Jemandem fehlen Rezeptdaten. Angesprochen ist genau der genannte
        -- Hersteller; die Antwort geht dennoch ueber den Gildenkanal, weil in
        -- der Regel mehreren dasselbe Rezept fehlt.
        local wantedCrafter = GC.Util.Trim(fields[4] or "")
        local requestedKeys = DecodeRecipeKeys(fields[5])
        self.suppressedRequests = self.suppressedRequests or {}
        PruneSuppressed(self.suppressedRequests, MISSING_REQUEST_SUPPRESS)
        local now = GC.Util.Now()
        for _, recipeKey in ipairs(requestedKeys) do
            -- Wer dieselbe Anfrage schon unterwegs sieht, stellt sie nicht
            -- erneut. Sonst fragen bei hundert Mitgliedern hundert Clients
            -- dasselbe Rezept nach.
            self.suppressedRequests[recipeKey] = now
        end
        local wantedKey = GC.Util.PlayerKey(wantedCrafter)
        if wantedKey == "" or #requestedKeys == 0 then
            return
        end
        local filter = {}
        for _, recipeKey in ipairs(requestedKeys) do
            filter[recipeKey] = true
        end
        local ownAnswered = false
        for _, entry in ipairs(self:GetPublishableProfessions()) do
            if GC.Util.PlayerKey(entry.crafter) == wantedKey then
                self:QueueProfessionSync(entry.profession, true, nil, nil, entry.crafter, filter)
                ownAnswered = true
            end
        end
        -- Der Botendienst: Ist der Besitzer nicht da, liefern hoechstens zwei
        -- Gewaehlte aus ihrem Katalog - gestreut, und wer inzwischen eine
        -- fremde Lieferung sieht, schweigt. Bei 250 Online antwortet damit in
        -- aller Regel genau einer statt des ganzen Raums.
        if not ownAnswered and GC.Sync and GC.Sync.IsElectedResponder
            and GC.Sync:IsElectedResponder(sender, RELAY_DETAIL_SLOTS) then
            self:ScheduleRelayedRecipeAnswer(wantedCrafter, requestedKeys)
        end
        return
    elseif operation == "CD" then
        -- Wartezeiten. Feld 4 nennt den Charakter, dem sie gehoeren - ein
        -- Spieler meldet auch die seiner Twinks, genau wie bei den Rezepten.
        local crafterName = GC.Util.Trim(fields[4] or "")
        if crafterName == "" or #crafterName > 60 then
            crafterName = sender
        end
        self:StoreCrafterCooldowns(crafterName, DecodeCooldowns(fields[5], GC.Util.Now()), sender)
        return
    end
    if operation ~= "D" and operation ~= "C" and operation ~= "K" then
        return
    end

    local token = fields[4]
    local part = tonumber(fields[5])
    local total = tonumber(fields[6])
    local professionKey = fields[7] or ""
    local professionName = fields[8] or ""
    local payload = fields[9] or ""
    local updatedAt = tonumber(fields[10]) or GC.Util.Now()
    local fingerprintHash = tostring(fields[11] or "")
    -- Feld 12 (optional): der eigentliche Hersteller. Fehlt es (aeltere Clients
    -- oder eigener Charakter), wird der Beruf wie bisher dem Absender
    -- zugeschrieben. So teilt ein Spieler auch die Berufe seiner Twinks mit.
    local craftedBy = GC.Util.Trim(fields[12] or "")
    if not token or not part or not total or total < 1 or part < 1 or part > total
        or total > MAX_TRANSFER_PARTS
        or #token > 40 or #professionKey > 80 or #professionName > 80
        or #payload > MAX_PAYLOAD_BYTES
        or #fingerprintHash > 20 or #craftedBy > 60
        or professionKey == "" or professionName == "" then
        return
    end

    -- Ein Altclient mit englischer Spielsprache schickt "enchanting" als
    -- Schluessel und "Enchanting" als Namen. Abgelegt wird kanonisch, sonst
    -- entsteht derselbe Beruf doppelt. Neue Clients senden bereits kanonisch;
    -- fuer sie aendert sich hier nichts.
    professionKey = NormalizeKey(professionKey)
    professionName = GC.CanonicalProfessionName(professionName) or professionName

    local senderKey = GC.Util.PlayerKey(sender)
    if senderKey == "" then
        return
    end
    local crafterName = craftedBy ~= "" and craftedBy or sender
    local crafterKey = GC.Util.PlayerKey(crafterName)
    if crafterKey == "" then
        crafterName = sender
        crafterKey = senderKey
    end
    -- Ein laufender Detailtransfer zu diesem Beruf IST die Antwort, auf die
    -- ein geplanter Bote wartet: Er sieht den Vermerk und schweigt. Schon das
    -- erste Teilpaket zaehlt - auf das letzte zu warten hiesse, dass der
    -- zweite Bote mitten im Transfer des ersten lossendet.
    if operation ~= "K" and GC.Sync and GC.Sync.NotePeerAnswer then
        GC.Sync:NotePeerAnswer("WDETAIL|" .. crafterKey .. "|" .. professionKey)
    end
    local now = GC.Util.Now()
    local incomingCount = 0
    for key, transfer in pairs(self.incoming) do
        if (now - (transfer.receivedAt or 0)) > INCOMING_TTL then
            self.incoming[key] = nil
        else
            incomingCount = incomingCount + 1
        end
    end

    local incomingKey = senderKey .. "|" .. token .. "|" .. professionKey .. "|" .. crafterKey
    for key, completedAt in pairs(self.completedIncoming) do
        if (now - (tonumber(completedAt) or 0)) > INCOMING_TTL then
            self.completedIncoming[key] = nil
        end
    end
    if self.completedIncoming[incomingKey] then
        if operation == "C" and distribution == "WHISPER" and GC.Sync then
            GC.Sync:SendReliableAck("W", token, part, sender)
        end
        return
    end

    local incoming = self.incoming[incomingKey]
    if incoming and (incoming.total ~= total
        or incoming.professionKey ~= professionKey
        or incoming.professionName ~= professionName
        or incoming.operation ~= operation
        or incoming.updatedAt ~= updatedAt
        or incoming.fingerprintHash ~= fingerprintHash) then
        self.incoming[incomingKey] = nil
        return
    end
    if not incoming then
        -- Greift die Grenze doch, weicht die AELTESTE unfertige Uebertragung.
        -- Bis 0.9.96 wurde stattdessen das NEUE Paket stumm verworfen - und mit
        -- ihm der ganze Transfer, denn wiederholt wird hier nichts. Ein frisches
        -- Paket ist immer mehr wert als eines, das seit Minuten nicht
        -- weitergekommen ist.
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
        incoming = {
            parts = {},
            received = 0,
            total = total,
            professionKey = professionKey,
            professionName = professionName,
            operation = operation,
            updatedAt = updatedAt,
            fingerprintHash = fingerprintHash,
            receivedAt = now,
        }
    end
    incoming.receivedAt = now
    if incoming.parts[part] and incoming.parts[part] ~= payload then
        self.incoming[incomingKey] = nil
        return
    elseif not incoming.parts[part] then
        incoming.parts[part] = payload
        incoming.received = incoming.received + 1
    end
    self.incoming[incomingKey] = incoming
    if operation == "C" and distribution == "WHISPER" and GC.Sync then
        GC.Sync:SendReliableAck("W", token, part, sender)
    end
    if incoming.received < incoming.total then
        return
    end

    self.incoming[incomingKey] = nil
    self.completedIncoming[incomingKey] = now

    local receivedKeys = {}
    local receivedRecipeCount = 0
    if operation == "K" then
        -- Nur "wer kann was". Die Schluesselliste ist byteweise geteilt und wird
        -- deshalb erst zusammengesetzt und dann gelesen. Die Rezeptdaten selbst
        -- stehen im Katalog, weil sie fuer alle identisch sind.
        local assembled = {}
        for partIndex = 1, incoming.total do
            assembled[partIndex] = incoming.parts[partIndex] or ""
        end
        receivedKeys = DecodeRecipeKeys(table.concat(assembled))
        -- Auch ohne uebertragene Rezeptdaten sind das die Rezepte, die dieser
        -- Hersteller ab jetzt nachweislich kann - der Status soll sie nennen.
        receivedRecipeCount = #receivedKeys
    else
        -- Rezeptpakete sind an Datensatzgrenzen geteilt, ohne das Trennzeichen
        -- mitzunehmen. Sie werden deshalb Paket fuer Paket gelesen; ein
        -- Zusammensetzen wuerde den letzten Datensatz eines Pakets mit dem
        -- ersten des naechsten verschmelzen.
        --
        -- Das Verwerfen des Katalogindex haengt hier ausdruecklich am Ende und
        -- nicht am einzelnen Rezept: Ein voller Beruf bringt bis zu 300 Pakete
        -- mit hunderten Rezepten mit, und jedes einzelne warf bisher den Index
        -- weg.
        local catalogChanged = false
        for partIndex = 1, incoming.total do
            for record in tostring(incoming.parts[partIndex] or ""):gmatch("[^;]+") do
                local recipe = operation == "C"
                    and DecodeCompactRecipeRecord(record, professionName)
                    or DecodeRecipeRecord(record, professionName)
                if recipe then
                    if self:StoreCatalogRecipe(recipe, professionKey, professionName, true) then
                        catalogChanged = true
                    end
                    receivedKeys[#receivedKeys + 1] = recipe.key
                    receivedRecipeCount = receivedRecipeCount + 1
                end
            end
        end
        if catalogChanged then
            self:ScheduleCatalogInvalidation()
        end
    end

    -- Eine gezielte Nachlieferung enthaelt nur einzelne Rezepte und darf den
    -- vollstaendigen Herstellerindex nicht auf diese wenigen zusammenstreichen.
    local existing = self:GetGuildWorkshop().crafters[crafterKey]
    local existingProfession = existing and existing.professions
        and existing.professions[professionKey]
    local isPartialDelivery = operation ~= "K" and existingProfession
        and existingProfession.recipeKeys
        and RecipeKeyCount(existingProfession) > #receivedKeys
    if isPartialDelivery then
        for recipeKey in pairs(existingProfession.recipeKeys) do
            receivedKeys[#receivedKeys + 1] = recipeKey
        end
    end

    self:ClaimRecipes({
        crafter = crafterName,
        sharedBy = sender,
        professionKey = professionKey,
        professionName = professionName,
        recipeKeys = receivedKeys,
        updatedAt = incoming.updatedAt,
        fingerprintHash = incoming.fingerprintHash ~= "" and incoming.fingerprintHash or nil,
    })

    if operation == "K" then
        self:ScheduleMissingRecipeRequest(crafterName, receivedKeys)
    end
    self.syncStats.receivedProfessions = self.syncStats.receivedProfessions + 1
    self.syncStats.receivedRecipes = self.syncStats.receivedRecipes + receivedRecipeCount
    self.syncStats.lastSender = GC.Util.PlayerIdentityName(crafterName)
    GC:FireCallback("WORKSHOP_UPDATED")
end

-- Reagenzienlisten werden fuer den Katalogindex kopiert UND dabei neu
-- aufgeloest. Der gespeicherte Name ist nur der Stand des letzten Dekodierens;
-- was der Client seither nachgeladen hat, gehoert in die Anzeige. Genau hier
-- sass "16x Item #25708" in den Rezeptdetails: Der Platzhalter wurde beim
-- Empfang einmal gespeichert und dann bei jedem Aufbau unveraendert
-- weiterkopiert - das Nachladen des Gegenstands erreichte die Anzeige nie.
-- Jeder Aufbau loest jetzt erneut auf; ein noch fehlender Gegenstand wird
-- durch den LookupItemName-Aufruf zugleich beim Server angefordert, und
-- GET_ITEM_INFO_RECEIVED -> ScheduleNameRefresh traegt den echten Namen nach.
local function ResolvedReagentCopies(reagents)
    local copies = {}
    for index, reagent in ipairs(reagents or {}) do
        copies[index] = {
            itemID = reagent.itemID,
            count = reagent.count,
            name = ResolveItemName(reagent.itemID, reagent.name),
        }
    end
    return copies
end

local function AddCrafterToCatalog(catalog, crafterName, professions)
    for _, profession in pairs(professions or {}) do
        for recipeKey, recipe in pairs(profession.recipes or {}) do
            local entry = catalog[recipeKey]
            if not entry then
                entry = {
                    key = recipeKey,
                    name = ResolveRecipeName(recipeKey, recipe.name),
                    -- Der Name, wie ihn der Scanner-Client geschrieben hat. Er
                    -- wandert mit in den Suchtext: Ein englischer Client hat
                    -- "Boar's Speed" gespeichert, dieser hier loest
                    -- "Ebergeschwindigkeit" auf - gefunden werden muss beides,
                    -- sonst suchen deutsche und englische Gildennutzer
                    -- aneinander vorbei.
                    scannedName = recipe.name,
                    itemID = recipe.itemID,
                    profession = profession.name or recipe.profession or "Unbekannt",
                    reagents = ResolvedReagentCopies(recipe.reagents),
                    crafters = {},
                    crafterKeys = {},
                }
                catalog[recipeKey] = entry
            else
                entry.name = ResolveRecipeName(recipeKey, entry.name or recipe.name)
                entry.scannedName = entry.scannedName or recipe.name
            end
            local crafterKey = GC.Util.PlayerKey(crafterName)
            if not entry.crafterKeys[crafterKey] then
                entry.crafterKeys[crafterKey] = true
                entry.crafters[#entry.crafters + 1] = GC.Util.PlayerIdentityName(crafterName)
            end
            if #entry.reagents == 0 and #(recipe.reagents or {}) > 0 then
                entry.reagents = ResolvedReagentCopies(recipe.reagents)
            end
        end
    end
end

-- Der Katalogaufbau ist der teuerste Vorgang der ganzen Werkstatt: Er laeuft
-- ueber die eigenen Rezepte, die aller Twinks desselben Accounts und den
-- kompletten Gildenindex und kopiert dabei jede Reagenzienliste. Bei mehreren
-- tausend Rezepten ist das nichts, was pro Tastendruck passieren darf - und
-- genau das tat es: die Suche baute ihn ueber GetSummary und GetCatalog gleich
-- zweimal je Zeichen neu auf. Gebaut wird jetzt einmal; gesucht wird im
-- Ergebnis. Neu entsteht der Index nur, wenn sich die Daten wirklich geaendert
-- haben - dafuer sorgt InvalidateCatalog an den vier schreibenden Stellen.
function GC.Workshop:GetCatalogIndex()
    if self.catalogIndex then
        return self.catalogIndex
    end

    local catalog = {}
    local ownName = GC:GetPlayerFullName()
    AddCrafterToCatalog(catalog, ownName, self:GetOwnData().professions)
    -- Weitere Charaktere desselben Accounts: ihre Berufe liegen lokal in der
    -- gemeinsamen SavedVariables. So sieht jeder eigene Charakter auch die
    -- Berufe der anderen eigenen Charaktere (z. B. die Verzauberkunst des
    -- Magier-Twinks auf dem Main), ohne auf eine Netzwerksynchronisierung zu
    -- warten - das Addon kennt die Daten ja bereits.
    local ownKey = GC.Util.PlayerKey(ownName)
    for characterKey, character in pairs((GC.DB.data and GC.DB.data.characters) or {}) do
        local workshop = type(character) == "table" and character.workshop
        local characterName = (type(character) == "table" and character.fullName) or characterKey
        if workshop and workshop.professions
            and GC.Util.PlayerKey(characterName) ~= ownKey then
            CanonicalizeOwnProfessions(workshop)
            AddCrafterToCatalog(catalog, characterName, workshop.professions)
        end
    end
    -- Der gildenweite Teil: der Katalog liefert die Rezeptdaten, der
    -- Herstellerindex nur noch die Namen. Fehlt zu einem gemeldeten Rezept die
    -- Datenzeile noch, entsteht der Eintrag trotzdem - Name und Beruf loest der
    -- Client aus der Item- beziehungsweise Zauber-ID selbst auf, allein die
    -- Reagenzien bleiben leer, bis die Nachlieferung eintrifft.
    local guildWorkshop = self:GetGuildWorkshop()
    for _, crafter in pairs(guildWorkshop.crafters) do
        local crafterKey = GC.Util.PlayerKey(crafter.name)
        for _, profession in pairs(crafter.professions or {}) do
            for recipeKey in pairs(profession.recipeKeys or {}) do
                local known = guildWorkshop.catalog[recipeKey]
                local entry = catalog[recipeKey]
                if not entry then
                    entry = {
                        key = recipeKey,
                        name = ResolveRecipeName(recipeKey, known and known.name),
                        scannedName = known and known.name,
                        itemID = known and known.itemID,
                        profession = (known and known.profession)
                            or profession.name or "Unbekannt",
                        reagents = ResolvedReagentCopies(known and known.reagents),
                        crafters = {},
                        crafterKeys = {},
                    }
                    catalog[recipeKey] = entry
                elseif #entry.reagents == 0 and known and #(known.reagents or {}) > 0 then
                    entry.reagents = ResolvedReagentCopies(known.reagents)
                end
                if not entry.crafterKeys[crafterKey] then
                    entry.crafterKeys[crafterKey] = true
                    entry.crafters[#entry.crafters + 1] = GC.Util.PlayerIdentityName(crafter.name)
                end
            end
        end
    end

    -- Suchtext und Berufsschluessel entstehen einmal hier und nicht bei jedem
    -- Tastendruck erneut fuer jeden der tausenden Eintraege.
    local entries = {}
    local byKey = {}
    for _, entry in pairs(catalog) do
        table.sort(entry.crafters)
        -- Der Suchtext traegt BEIDE Namen, wenn Scanner- und Anzeigesprache
        -- auseinanderliegen: aufgeloest in der Sprache dieses Clients, dazu
        -- die Schreibweise des Scanners. So findet "boars speed" denselben
        -- Eintrag wie "ebergeschwindigkeit".
        local scannedPart = ""
        if entry.scannedName and entry.scannedName ~= entry.name then
            scannedPart = " " .. entry.scannedName
        end
        entry.searchable = NormalizeKey(
            entry.name .. scannedPart .. " " .. entry.profession
                .. " " .. table.concat(entry.crafters, " "))
        entry.professionKey = NormalizeKey(entry.profession)
        entries[#entries + 1] = entry
        byKey[entry.key] = entry
    end
    table.sort(entries, function(left, right)
        if left.profession ~= right.profession then
            return left.profession < right.profession
        end
        return left.name < right.name
    end)

    -- Der Schluesselindex haengt bewusst NICHT am Ergebnisarray: Aufrufer
    -- duerfen weiter mit pairs darueber laufen, ohne ein Zusatzfeld zu treffen.
    self.catalogByKey = byKey
    self.catalogIndex = entries
    return entries
end

-- Verwirft den zwischengespeicherten Index.
--
-- REGEL FUER NEUE SCHREIBSTELLEN: Wer an den eigenen Berufen, am Herstellerindex
-- oder am Rezeptkatalog etwas aendert, ruft das hier auf. Ein pauschales Netz an
-- WORKSHOP_UPDATED gab es kurzzeitig, es ist wieder weg: Dieses Ereignis feuert
-- auch fuer reine Synchronisierungszaehler, und bei geoeffneter Werkstatt wurde
-- der Katalog waehrend eines Transfers dutzendfach neu gebaut - genau der
-- Aufwand, den der Cache vermeiden soll.
--
-- Die Wanderungen in GetOwnData und GetGuildWorkshop brauchen keinen Aufruf:
-- Sie laufen einmalig INNERHALB des Aufbaus, ihr Ergebnis steht also schon im
-- frisch gebauten Index.
function GC.Workshop:InvalidateCatalog()
    self.catalogIndex = nil
    self.catalogByKey = nil
    self.catalogSummary = nil
    -- Der Wartezeitenindex haengt an derselben Charakterliste. Er ist billig
    -- gebaut, und ihn hier stehen zu lassen waere genau die Art Halbwissen,
    -- die spaeter niemand mehr zuordnet.
    self.cooldownIndex = nil
end

-- Dasselbe, aber gesammelt - fuer alles, was in Schueben eintrifft.
--
-- Waehrend eines Abgleichs verwarf jedes eingehende Rezept und jeder
-- uebernommene Beruf den Index einzeln: 20 eingehende Berufe waren 20
-- Verwerfungen. Der Neuaufbau kostet gemessen 204 ms, und bei geoeffneter
-- Werkstatt baute die Oberflaeche ihn dadurch alle 0,25 s neu auf - die
-- Bildrate fiel auf rund 4 Bilder je Sekunde. Verworfen wird jetzt hoechstens
-- alle CATALOG_INVALIDATE_DELAY Sekunden, nach derselben Bauweise wie bei den
-- nachgeladenen Namen (ScheduleNameRefresh).
function GC.Workshop:ScheduleCatalogInvalidation()
    if self.catalogInvalidatePending then
        return
    end
    if not C_Timer or type(C_Timer.After) ~= "function" then
        self:InvalidateCatalog()
        GC:FireCallback("WORKSHOP_UPDATED")
        return
    end
    self.catalogInvalidatePending = true
    C_Timer.After(CATALOG_INVALIDATE_DELAY, function()
        GC.Workshop.catalogInvalidatePending = false
        GC.Workshop:InvalidateCatalog()
        GC:FireCallback("WORKSHOP_UPDATED")
    end)
end

-- Ein einzelnes Rezept nach Schluessel. Vorher suchten die Aufrufer linear
-- durch den kompletten Katalog - bei jedem Auftragsdialog einmal komplett.
function GC.Workshop:GetCatalogEntry(recipeKey)
    self:GetCatalogIndex()
    return self.catalogByKey[tostring(recipeKey or "")]
end

function GC.Workshop:GetCatalog(query, professionFilter, favoritesOnly)
    local entries = self:GetCatalogIndex()
    query = NormalizeKey(query)
    professionFilter = NormalizeKey(professionFilter)
    if query == "" and professionFilter == "" and not favoritesOnly then
        return entries
    end

    local favorites = GC.DB:GetSettings().workshopFavorites or {}
    local matches = {}
    for _, entry in ipairs(entries) do
        local professionMatches = professionFilter == "" or entry.professionKey == professionFilter
        local favoriteMatches = not favoritesOnly or favorites[entry.key] == true
        if professionMatches and favoriteMatches
            and (query == "" or entry.searchable:find(query, 1, true)) then
            matches[#matches + 1] = entry
        end
    end
    return matches
end

-- Wer die Gilde verlaesst, verschwindet mit seinen Rezepten aus der Werkstatt.
-- Der Roster allein reicht als Maßstab aber nicht: Twinks stehen nie im
-- Gildenroster, und ihre Berufe werden seit 0.9.26 bewusst geteilt. Ein Eintrag
-- faellt deshalb nur, wenn weder der Hersteller selbst noch das Gildenmitglied,
-- das ihn eingebracht hat, noch im Roster steht. Solange der Roster nach dem
-- Login leer ist, wird gar nichts entfernt.
function GC.Workshop:PruneDepartedCrafters()
    if #GC.Roster.members == 0 then
        return 0
    end
    local workshop = self:GetGuildWorkshop()
    -- Eigene Charaktere stehen nicht im Gildenroster und duerfen deshalb nicht
    -- fuer Ausgetretene gehalten werden - aber nur die, die WIRKLICH in dieser
    -- Gilde sind. Ein Twink aus einer anderen Gilde war frueher durch dieselbe
    -- Ausnahme geschuetzt und blieb damit dauerhaft im fremden Gildenkatalog
    -- stehen; genau das raeumt diese Einschraenkung mit auf.
    local guildKey = GC:GetGuildKey()
    local ownKeys, foreignKeys = {}, {}
    for characterKey, character in pairs((GC.DB.data and GC.DB.data.characters) or {}) do
        local characterName = (type(character) == "table" and character.fullName) or characterKey
        local characterGuild = type(character) == "table" and character.guildKey or nil
        -- Nur ein NAMENTLICH anderer Gildenschluessel ist ein Beleg dafuer, dass
        -- dieser Charakter woanders steht. Ein leerer Vermerk ist keiner: Er
        -- entsteht auch dort, wo der Client beim Anmelden noch nichts wusste,
        -- und darf deshalb nichts loeschen. Zurueckhalten reicht - das erledigt
        -- GetPublishableProfessions, und eine Luecke heilt beim naechsten
        -- Einloggen von selbst. Ein geloeschter Bestand nicht.
        if characterGuild ~= nil and characterGuild ~= "" and characterGuild ~= guildKey then
            foreignKeys[GC.Util.PlayerKey(characterName)] = true
        else
            ownKeys[GC.Util.PlayerKey(characterName)] = true
        end
    end
    ownKeys[GC.Util.PlayerKey(GC:GetPlayerFullName())] = true
    foreignKeys[GC.Util.PlayerKey(GC:GetPlayerFullName())] = nil

    local now = GC.Util.Now()
    local removed = 0
    for crafterKey, crafter in pairs(workshop.crafters) do
        local name = type(crafter) == "table" and crafter.name or crafterKey
        local sharedBy = type(crafter) == "table" and crafter.sharedBy or nil
        -- Ein eigener Charakter, von dem wir WISSEN, dass er in einer anderen
        -- Gilde steht, fliegt raus - auch wenn ihn ein Gildenmitglied
        -- eingebracht hat. Genau dieser Buerge hielt die Altlast am Leben, die
        -- der Account frueher selbst hier hineingetragen hat.
        local keep = not foreignKeys[crafterKey]
            and (ownKeys[crafterKey]
                or GC.Roster:IsGuildMember(name)
                or (sharedBy and GC.Roster:IsGuildMember(sharedBy)))
        if not keep then
            workshop.crafters[crafterKey] = nil
            removed = removed + 1
        elseif type(crafter) == "table" and crafter.cooldowns then
            -- Abgelaufene Sperren raeumt sonst nur der Hersteller selbst weg,
            -- und zwar erst, wenn er das naechste Mal etwas meldet. Wer seit
            -- Monaten nicht mehr am Berufsfenster stand, schleppt sie ewig mit.
            for recipeKey, readyAt in pairs(crafter.cooldowns) do
                if (tonumber(readyAt) or 0) <= now then
                    crafter.cooldowns[recipeKey] = nil
                    self.cooldownIndex = nil
                end
            end
        end
    end

    -- Bestandsluecken Ausgetretener: Wer nicht mehr in der Gilde ist, fehlt
    -- auch nicht mehr. Dieselbe Bleiberegel wie bei den Herstellern, mit dem
    -- Melder als drittem Buergen - er hat den Eintrag schliesslich verbuergt.
    for gapKey, gap in pairs(workshop.coverageGaps or {}) do
        local keep = ownKeys[GC.Util.PlayerKey(gap.crafter)]
            or GC.Roster:IsGuildMember(gap.crafter)
            or (GC.Util.Trim(gap.reportedBy) ~= "" and GC.Roster:IsGuildMember(gap.reportedBy))
        if not keep then
            workshop.coverageGaps[gapKey] = nil
        end
    end

    -- Rezepte, die niemand mehr kann, muellen den Katalog nicht zu.
    if removed > 0 then
        local stillClaimed = {}
        for _, crafter in pairs(workshop.crafters) do
            for _, profession in pairs((type(crafter) == "table" and crafter.professions) or {}) do
                for recipeKey in pairs(profession.recipeKeys or {}) do
                    stillClaimed[recipeKey] = true
                end
            end
        end
        for _, profession in pairs(self:GetOwnData().professions) do
            for recipeKey in pairs(profession.recipes or {}) do
                stillClaimed[recipeKey] = true
            end
        end
        for recipeKey in pairs(workshop.catalog) do
            if not stillClaimed[recipeKey] then
                workshop.catalog[recipeKey] = nil
            end
        end
        self:InvalidateCatalog()
        GC:FireCallback("WORKSHOP_UPDATED")
    end
    return removed
end

function GC.Workshop:IsFavorite(recipeKey)
    if not recipeKey or recipeKey == "" then
        return false
    end
    return GC.DB:GetSettings().workshopFavorites[recipeKey] == true
end

function GC.Workshop:SetFavorite(recipeKey, favorite)
    if not recipeKey or recipeKey == "" then
        return false
    end
    local favorites = GC.DB:GetSettings().workshopFavorites
    if favorite then
        favorites[recipeKey] = true
    else
        favorites[recipeKey] = nil
    end
    return true
end

function GC.Workshop:GetMissingOwnProfessions()
    -- Die Sammelberufe ohne Fenster stehen in Constants.lua; Werkstatt und
    -- Einrichtung lesen dieselbe Liste.
    local ignored = {}
    for name in pairs(GC.RecipelessProfessions) do
        ignored[NormalizeKey(name)] = true
    end
    local known = self:GetOwnData().professions or {}
    local missing = {}
    for _, profession in ipairs(GC.Profile:Get().professions or {}) do
        local name = profession and profession.name
        local key = NormalizeKey(name)
        if name and name ~= "" and not ignored[key] and not known[key] then
            missing[#missing + 1] = name
        end
    end
    table.sort(missing)
    return missing
end

-- Die Kennzahlen haengen ausschliesslich am Index. Sie werden deshalb mit ihm
-- zusammen gehalten, statt bei jedem Tastendruck in der Suche neu ueber alle
-- Rezepte und deren Hersteller zu laufen.
function GC.Workshop:GetSummary()
    if self.catalogSummary and self.catalogIndex then
        return self.catalogSummary
    end
    local entries = self:GetCatalogIndex()
    local crafters = {}
    local professions = {}
    for _, entry in ipairs(entries) do
        -- Berufe nach kanonischem Schluessel zaehlen, nicht nach dem
        -- Namens-String: Sonst zaehlen die Alt-Schreibweise "Alchemie", die
        -- englischen Namen englischer Clients und der "Unbekannt"-Platzhalter
        -- als eigene Berufe - die Karte zeigte 16 Berufe, wo TBC hoechstens
        -- 12 kennt. Die Zusammenfuehrung steckt inzwischen in NormalizeKey.
        local professionKey = NormalizeKey(entry.profession)
        if professionKey ~= "" and professionKey ~= NormalizeKey("Unbekannt") then
            professions[professionKey] = true
        end
        for _, crafter in ipairs(entry.crafters) do
            crafters[GC.Util.PlayerKey(crafter)] = true
        end
    end
    local crafterCount = 0
    local professionCount = 0
    for _ in pairs(crafters) do
        crafterCount = crafterCount + 1
    end
    for _ in pairs(professions) do
        professionCount = professionCount + 1
    end
    self.catalogSummary = {
        recipes = #entries,
        crafters = crafterCount,
        professions = professionCount,
    }
    return self.catalogSummary
end

-- GET_ITEM_INFO_RECEIVED meldet jeden einzelnen Gegenstand, den der Client in
-- seinen Item-Cache nachlaedt - beim Login mit kaltem Cache sind das tausende
-- Ereignisse in kurzer Zeit. Jedes davon feuerte bisher WORKSHOP_UPDATED, und
-- bei offener Werkstattseite zeichnete jedes einzelne die komplette Seite neu.
-- Fuer die Oberflaeche zaehlt nur "demnaechst neu zeichnen", nicht jedes Item:
-- gesammelt wird auf hoechstens zwei Auffrischungen pro Sekunde.
local NAME_REFRESH_DELAY = 0.5

function GC.Workshop:ScheduleNameRefresh()
    if self.nameRefreshPending then
        return
    end
    -- Nachgeladene Namen aendern Anzeige UND Suchtext, der Index muss also weg.
    if not C_Timer or type(C_Timer.After) ~= "function" then
        self:InvalidateCatalog()
        GC:FireCallback("WORKSHOP_UPDATED")
        return
    end
    self.nameRefreshPending = true
    C_Timer.After(NAME_REFRESH_DELAY, function()
        GC.Workshop.nameRefreshPending = false
        GC.Workshop:InvalidateCatalog()
        GC:FireCallback("WORKSHOP_UPDATED")
    end)
end

local workshopEvents = CreateFrame("Frame")
workshopEvents:RegisterEvent("TRADE_SKILL_SHOW")
GC.Client.RegisterEvent(workshopEvents, "TRADE_SKILL_UPDATE")
GC.Client.RegisterEvent(workshopEvents, "CRAFT_SHOW")
GC.Client.RegisterEvent(workshopEvents, "CRAFT_UPDATE")
workshopEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
-- Das Schliessen des Berufsfensters aendert nichts an den Daten, aber alles
-- am Herstellen-Knopf: Ohne offenes Fenster gibt es keine Rezeptliste, und der
-- Knopf muss wieder "Berufsfenster öffnen" anbieten.
workshopEvents:RegisterEvent("TRADE_SKILL_CLOSE")
GC.Client.RegisterEvent(workshopEvents, "CRAFT_CLOSE")
for _, event in ipairs({ "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_DETAILS_UPDATE", "NEW_RECIPE_LEARNED" }) do
    GC.Client.RegisterEvent(workshopEvents, event)
end
workshopEvents:SetScript("OnEvent", function(_, event)
    if event == "GET_ITEM_INFO_RECEIVED" then
        GC.Workshop:ScheduleNameRefresh()
    elseif event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then
        GC:FireCallback("WORKSHOP_UPDATED")
    else
        if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
            GC.Workshop.preparedProfession = nil
        end
        GC.Workshop:ScheduleScan()
    end
end)

-- Der Roster wird nach jeder Gildenaktualisierung neu gelesen; das Aufraeumen
-- haengt sich dort an, bleibt aber gedrosselt, weil das Ereignis oft feuert.
GC:RegisterCallback("ROSTER_UPDATED", GC.Workshop, function(self)
    local now = GC.Util.Now()
    if (now - (self.lastDepartedPruneAt or 0)) < DEPARTED_PRUNE_INTERVAL then
        return
    end
    self.lastDepartedPruneAt = now
    self:PruneDepartedCrafters()
end)

-- Der Werkstattteil der Anlaufsequenz: Bestand erfragen, eigenen ankuendigen.
-- Wie bei GC.Sync eine eigene Funktion, damit ein Gildenbeitritt im laufenden
-- Spiel nicht bis zum naechsten /reload ohne Werkstattabgleich dasteht.
local WORKSHOP_MIN_PRIME_INTERVAL = 30

function GC.Workshop:RunStartupSequence()
    self.lastPrimeAt = GC.Util.Now()
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return false
    end
    C_Timer.After(10, function()
        -- Der Abgleich ist fester Hintergrunddienst und läuft über den
        -- schnellen, zuverlässigen Gildenkanal. Erst den Bestand der Gilde
        -- anfragen ...
        GC.Workshop:RequestGuildData()
    end)
    C_Timer.After(16, function()
        -- ... und den eigenen Bestand ankündigen. Gesendet wird nur das
        -- Manifest: Hersteller, Zeitstempel, Anzahl und Fingerabdruck je
        -- Beruf. Wer davon etwas nicht hat, fordert es an - wer alles kennt,
        -- verursacht keinen weiteren Verkehr. Ein Login ohne Änderungen
        -- kostet damit ein Paket statt einer vollen Schlüsselliste.
        -- Nur das Manifest, nie der volle Bestand: ein Login oder /reload
        -- kostet damit ein Paket statt achtzig. Wer wirklich etwas nicht
        -- hat, fordert es aus dem Manifest gezielt an, und ein Client ohne
        -- Manifest-Verständnis bekommt beim eigenen "Q" den vollen Bestand.
        if IsInGuild and IsInGuild() then
            GC.Workshop:SendKeyManifest()
        end
    end)
    return true
end

GC:RegisterCallback("PLAYER_LOGIN", GC.Workshop, function(self)
    self:GetOwnData()
    if C_Timer and C_Timer.After then
        -- Erst wenn Login-Rauschen und Datenbestand stehen: die seit dem
        -- letzten Spielen abgelaufenen Wartezeiten einmal gesammelt melden
        -- und den Zeitgeber auf den naechsten Ablauf stellen. Rein lokal und
        -- deshalb ausdruecklich NICHT Teil der Anlaufsequenz.
        C_Timer.After(COOLDOWN_REMINDER_LOGIN_DELAY, function()
            GC.Workshop:AnnounceDueCooldowns()
            GC.Workshop:ScheduleCooldownReminder()
        end)
    end
    self:RunStartupSequence()
end)

GC:RegisterCallback("GUILD_CHANGED", GC.Workshop, function(self)
    if not IsInGuild or not IsInGuild() then
        return
    end
    if (GC.Util.Now() - (tonumber(self.lastPrimeAt) or 0)) < WORKSHOP_MIN_PRIME_INTERVAL then
        return
    end
    -- Die neue Gilde hat einen eigenen, leeren Werkstattzweig - der
    -- zwischengespeicherte Katalog gehoert noch zur alten.
    if self.InvalidateCatalog then
        self:InvalidateCatalog()
    end
    self:RunStartupSequence()
end)
