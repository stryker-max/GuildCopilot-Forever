local _, GC = ...

-- Materialbestand: was liegt in eigenen Taschen, auf der eigenen Bank, bei den
-- eigenen Twinks - und was in der Gildenbank. Die eigenen Bestaende bleiben
-- ausdruecklich auf dem Account und werden nie gesendet; geteilt wird allein
-- die Gildenbank, die ohnehin allen gehoert.
GC.Inventory = {
    guildBankIncoming = {},
    guildBankCompleted = {},
    guildBankRequestReplies = {},
    suppressedTabRequests = {},
    pendingTabs = {},
}

local BAG_SCAN_DELAY = 1
local BANK_CONTAINER = -1
local FIRST_BANK_BAG = 5
local LAST_BANK_BAG = 11
local MAX_GUILD_BANK_TABS = 8
local MAX_TAB_SLOTS = 98
local GUILD_BANK_QUERY_SPACING = 0.5
local MIN_MANIFEST_REPLY_INTERVAL = 30
local TAB_REQUEST_DELAY = 6
local TAB_REQUEST_SUPPRESS = 45
local INCOMING_TTL = 5 * 60
local MAX_PAYLOAD_BYTES = 180
local MAX_TRANSFER_PARTS = 30
-- Streuzeiten vor den eigenen Antworten und die Namen, unter denen eine fremde
-- Antwort vermerkt wird. Beide Antworten gehen ueber den Gildenkanal und sind
-- damit fuer alle sichtbar - wer waehrend seiner Streuzeit einen anderen
-- liefern sieht, schweigt.
local MANIFEST_REPLY_DELAY = 0.5
local MANIFEST_REPLY_SPREAD = 4
local MANIFEST_ANSWER_KIND = "GUILDBANKMANIFEST"
local TAB_REPLY_DELAY = 0.5
local TAB_REPLY_SPREAD = 3
local TAB_ANSWER_PREFIX = "GUILDBANKTAB:"
-- Die Merkliste beantworteter Bankanfragen wuchs unbegrenzt: ein Eintrag je
-- Anfragendem, bei 500 Mitgliedern also 500 - obwohl ein Eintrag nach
-- MIN_MANIFEST_REPLY_INTERVAL Sekunden nichts mehr bewirkt.
local MAX_MANIFEST_REPLIES = 200

local function SafeCall(func, ...)
    if type(func) ~= "function" then
        return nil
    end
    local ok, first, second, third, fourth = pcall(func, ...)
    if not ok then
        return nil
    end
    return first, second, third, fourth
end

-- Taschen-API: der Anniversary-Client kann die moderne C_Container-Sammlung
-- kennen oder nur die klassischen Globalen. Beides wird bedient, damit ein
-- fehlendes C_Container nicht die ganze Bestandsanzeige lahmlegt.
local function ContainerNumSlots(container)
    local api = C_Container
    if api and type(api.GetContainerNumSlots) == "function" then
        return tonumber(SafeCall(api.GetContainerNumSlots, container)) or 0
    end
    return tonumber(SafeCall(GetContainerNumSlots, container)) or 0
end

local function ContainerItemLink(container, slot)
    local api = C_Container
    if api and type(api.GetContainerItemLink) == "function" then
        return SafeCall(api.GetContainerItemLink, container, slot)
    end
    return SafeCall(GetContainerItemLink, container, slot)
end

-- Die Stueckzahl steckt je nach Client in einer Tabelle oder im zweiten
-- Rueckgabewert. Die Item-ID kommt bevorzugt aus dem Link: das ist der einzige
-- Weg, der in allen Fassungen gleich funktioniert.
local function ContainerItemCount(container, slot)
    local api = C_Container
    if api and type(api.GetContainerItemInfo) == "function" then
        local info = SafeCall(api.GetContainerItemInfo, container, slot)
        if type(info) == "table" then
            return tonumber(info.stackCount) or 1, tonumber(info.itemID)
        end
    end
    local _, count = SafeCall(GetContainerItemInfo, container, slot)
    return tonumber(count) or 1, nil
end

local function ItemIDFromLink(link)
    return tonumber(tostring(link or ""):match("item:(%d+)"))
end

local function CountContainer(counts, container)
    local slots = ContainerNumSlots(container)
    for slot = 1, slots do
        local link = ContainerItemLink(container, slot)
        local count, itemIDFromInfo = ContainerItemCount(container, slot)
        local itemID = ItemIDFromLink(link) or itemIDFromInfo
        if itemID then
            counts[itemID] = (counts[itemID] or 0) + math.max(1, count)
        end
    end
    return counts
end

function GC.Inventory:GetOwnStore()
    local character = GC.DB:GetCharacter()
    character.inventory = character.inventory or {}
    character.inventory.bags = character.inventory.bags or { counts = {}, updatedAt = 0 }
    character.inventory.bank = character.inventory.bank or { counts = {}, updatedAt = 0 }
    return character.inventory
end

function GC.Inventory:ScanBags()
    local counts = {}
    for container = 0, 4 do
        CountContainer(counts, container)
    end
    local store = self:GetOwnStore()
    store.bags.counts = counts
    store.bags.updatedAt = GC.Util.Now()
    GC:FireCallback("INVENTORY_UPDATED")
    return counts
end

-- Die eigene Bank ist nur bei geoeffnetem Bankfenster lesbar. Ein Stand von
-- vorhin bleibt deshalb stehen und wird mit Datum ausgewiesen, statt zu
-- verschwinden.
function GC.Inventory:ScanBank()
    local counts = {}
    CountContainer(counts, BANK_CONTAINER)
    for container = FIRST_BANK_BAG, LAST_BANK_BAG do
        CountContainer(counts, container)
    end
    local store = self:GetOwnStore()
    store.bank.counts = counts
    store.bank.updatedAt = GC.Util.Now()
    GC:FireCallback("INVENTORY_UPDATED")
    return counts
end

function GC.Inventory:ScheduleBagScan()
    if self.bagScanPending then
        return
    end
    self.bagScanPending = true
    if not C_Timer or type(C_Timer.After) ~= "function" then
        self.bagScanPending = false
        self:ScanBags()
        return
    end
    C_Timer.After(BAG_SCAN_DELAY, function()
        GC.Inventory.bagScanPending = false
        GC.Inventory:ScanBags()
    end)
end

-- Bestand ueber alle eigenen Charaktere. Die Berufe der Twinks werden seit
-- 0.9.26 geteilt; ihre Materialien liegen in derselben SavedVariables und
-- gehoeren genauso in die Rechnung.
function GC.Inventory:GetOwnCounts(itemID)
    itemID = tonumber(itemID)
    local result = {
        bags = 0,
        bank = 0,
        alts = 0,
        total = 0,
        perCharacter = {},
        oldestBankAt = nil,
    }
    if not itemID then
        return result
    end

    local ownName = GC:GetPlayerFullName()
    local ownKey = GC.Util.NormalizeName(ownName)
    for characterKey, character in pairs((GC.DB.data and GC.DB.data.characters) or {}) do
        local inventory = type(character) == "table" and character.inventory
        if type(inventory) == "table" then
            local characterName = character.fullName or characterKey
            local bags = tonumber((inventory.bags or {}).counts
                and inventory.bags.counts[itemID]) or 0
            local bank = tonumber((inventory.bank or {}).counts
                and inventory.bank.counts[itemID]) or 0
            local bankAt = tonumber((inventory.bank or {}).updatedAt) or 0
            if bags > 0 or bank > 0 then
                local isOwn = GC.Util.NormalizeName(characterName) == ownKey
                if isOwn then
                    result.bags = result.bags + bags
                    result.bank = result.bank + bank
                else
                    result.alts = result.alts + bags + bank
                end
                result.total = result.total + bags + bank
                result.perCharacter[#result.perCharacter + 1] = {
                    name = GC.Util.PlayerIdentityName(characterName),
                    bags = bags,
                    bank = bank,
                    bankAt = bankAt,
                    own = isOwn,
                }
                if bank > 0 and (not result.oldestBankAt or bankAt < result.oldestBankAt) then
                    result.oldestBankAt = bankAt
                end
            end
        end
    end
    table.sort(result.perCharacter, function(left, right)
        if left.own ~= right.own then
            return left.own
        end
        return tostring(left.name) < tostring(right.name)
    end)
    return result
end

-- === Gildenbank =============================================================

function GC.Inventory:GetGuildBank()
    local guildData = GC.DB:GetGuild()
    guildData.guildBank = guildData.guildBank or { tabs = {} }
    guildData.guildBank.tabs = guildData.guildBank.tabs or {}
    return guildData.guildBank
end

function GC.Inventory:GetGuildBankCount(itemID)
    itemID = tonumber(itemID)
    if not itemID then
        return nil
    end
    local total, newestAt, seenBy, known = 0, 0, nil, false
    for _, tab in pairs(self:GetGuildBank().tabs) do
        if type(tab) == "table" and type(tab.counts) == "table" then
            known = true
            total = total + (tonumber(tab.counts[itemID]) or 0)
            local updatedAt = tonumber(tab.updatedAt) or 0
            if updatedAt > newestAt then
                newestAt = updatedAt
                seenBy = tab.seenBy
            end
        end
    end
    if not known then
        return nil
    end
    return total, newestAt, seenBy
end

local function TabFingerprint(counts)
    local ids = {}
    for itemID in pairs(counts or {}) do
        ids[#ids + 1] = itemID
    end
    table.sort(ids)
    local records = {}
    for _, itemID in ipairs(ids) do
        records[#records + 1] = tostring(itemID) .. ":" .. tostring(counts[itemID])
    end
    local hash = 5381
    local joined = table.concat(records, ",")
    for index = 1, #joined do
        hash = ((hash * 33) + joined:byte(index)) % 2147483647
    end
    return tostring(hash)
end

-- Ein Gildenbank-Tab wird erst nach seiner Abfrage geliefert. Deshalb wird je
-- Tab angefragt und erst beim zugehoerigen Slot-Ereignis gezaehlt.
function GC.Inventory:ScanGuildBankTab(tabIndex)
    tabIndex = tonumber(tabIndex)
    if not tabIndex or type(GetGuildBankItemLink) ~= "function" then
        return false
    end
    local name, _, isViewable = SafeCall(GetGuildBankTabInfo, tabIndex)
    if isViewable == false then
        -- Nicht einsehbar heisst: kommt auch spaeter nicht. Der Tab muss aus
        -- der Warteliste, sonst wird er bei jedem Bankereignis neu versucht.
        self.pendingTabs[tabIndex] = nil
        return false
    end

    local counts = {}
    local seen = 0
    for slot = 1, MAX_TAB_SLOTS do
        local link = SafeCall(GetGuildBankItemLink, tabIndex, slot)
        local itemID = ItemIDFromLink(link)
        if itemID then
            local _, count = SafeCall(GetGuildBankItemInfo, tabIndex, slot)
            counts[itemID] = (counts[itemID] or 0) + math.max(1, tonumber(count) or 1)
            seen = seen + 1
        end
    end
    -- Ein leerer Durchlauf kann bedeuten, dass die Abfrage noch laeuft. Ein
    -- vorhandener Stand wird dann nicht durch einen leeren ersetzt.
    local tabs = self:GetGuildBank().tabs
    local existing = tabs[tabIndex]
    if seen == 0 and existing and next(existing.counts or {}) then
        return false
    end

    tabs[tabIndex] = {
        name = GC.Util.SafeChatText(GC.Util.Trim(name), 40),
        counts = counts,
        updatedAt = GC.Util.Now(),
        seenBy = GC.Util.PlayerIdentityName(GC:GetPlayerFullName()),
        fingerprint = TabFingerprint(counts),
    }
    -- Dieser Tab ist gelesen und damit erledigt. Blieb er ausstehend, las
    -- jedes weitere Bankereignis ihn erneut - zusammen mit allen zuvor
    -- besuchten Tabs. Bei acht Tabs waren das bis zu 882 Slotabfragen je
    -- Ereignis, und den offenen Tab traf es doppelt.
    self.pendingTabs[tabIndex] = nil
    self.guildBankDirty = true
    GC:FireCallback("INVENTORY_UPDATED")
    return true
end

function GC.Inventory:QueryGuildBankTabs()
    if type(GetNumGuildBankTabs) ~= "function" then
        return false
    end
    local tabCount = math.min(tonumber(SafeCall(GetNumGuildBankTabs)) or 0, MAX_GUILD_BANK_TABS)
    if tabCount == 0 then
        return false
    end
    self.pendingTabs = {}
    local scheduled = 0
    for tabIndex = 1, tabCount do
        local _, _, isViewable = SafeCall(GetGuildBankTabInfo, tabIndex)
        if isViewable ~= false then
            self.pendingTabs[tabIndex] = true
            scheduled = scheduled + 1
            local delay = GUILD_BANK_QUERY_SPACING * scheduled
            local queryTab = tabIndex
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(delay, function()
                    SafeCall(QueryGuildBankTab, queryTab)
                end)
            else
                SafeCall(QueryGuildBankTab, queryTab)
                self:ScanGuildBankTab(queryTab)
            end
        end
    end
    return scheduled > 0
end

-- === Synchronisierung der Gildenbank ========================================
-- Manifest zuerst: gesendet werden nur Tab, Zeitstempel und Fingerabdruck. Die
-- eigentlichen Bestaende gehen erst raus, wenn jemand nachweislich einen
-- aelteren Stand hat und danach fragt.

-- Welcher von zwei Staenden gewinnt? Der neuere - und bei gleicher Sekunde der
-- mit dem groesseren Fingerabdruck.
--
-- Dass es diese zweite Stufe gibt, ist keine Feinheit: updatedAt kennt nur
-- ganze Sekunden (GetServerTime), zwei Staende derselben Sekunde sind also
-- alltaeglich. Vorher forderte das Manifest bei gleicher Sekunde und
-- abweichendem Fingerabdruck an, der Empfang verwarf denselben Stand aber,
-- weil er "nicht neuer" war. Das Paar lief endlos: anfordern, senden,
-- verwerfen, beim naechsten Manifest von vorn.
--
-- Entscheidend ist, dass BEIDE Seiten dieselbe Regel benutzen. Deshalb steht
-- sie hier einmal und wird von Manifest und Empfang gemeinsam aufgerufen.
local function WinsOverKnown(updatedAt, fingerprint, knownAt, knownFingerprint)
    if updatedAt ~= knownAt then
        return updatedAt > knownAt
    end
    return tostring(fingerprint or "") > tostring(knownFingerprint or "")
end

local function BuildMessage(fields)
    local escaped = {}
    for index, value in ipairs(fields) do
        escaped[index] = GC.Util.EscapeField(value)
    end
    return table.concat(escaped, "|")
end

local function EncodeCounts(counts)
    local ids = {}
    for itemID in pairs(counts or {}) do
        ids[#ids + 1] = tonumber(itemID)
    end
    table.sort(ids)
    local records, previous = {}, 0
    for _, itemID in ipairs(ids) do
        local amount = math.max(0, math.floor(tonumber(counts[itemID]) or 0))
        if amount > 0 then
            records[#records + 1] = tostring(itemID - previous) .. ":" .. tostring(amount)
            previous = itemID
        end
    end
    return table.concat(records, ".")
end

local function DecodeCounts(payload)
    local counts = {}
    local current = 0
    for record in tostring(payload or ""):gmatch("[^.]+") do
        local delta, amount = record:match("^(%d+):(%d+)$")
        if not delta then
            break
        end
        current = current + tonumber(delta)
        if current > 0 then
            counts[current] = tonumber(amount)
        end
    end
    return counts
end

GC.Inventory.EncodeCounts = function(_, counts)
    return EncodeCounts(counts)
end
GC.Inventory.DecodeCounts = function(_, payload)
    return DecodeCounts(payload)
end

function GC.Inventory:BuildManifestMessage()
    local records = {}
    for tabIndex, tab in pairs(self:GetGuildBank().tabs) do
        if type(tab) == "table" then
            records[#records + 1] = table.concat({
                tostring(tabIndex),
                tostring(tonumber(tab.updatedAt) or 0),
                tostring(tab.fingerprint or ""),
            }, ",")
        end
    end
    if #records == 0 then
        return nil
    end
    table.sort(records)
    return BuildMessage({
        "B",
        GC.Constants.SCHEMA_VERSION,
        "BM",
        table.concat(records, ";"),
    })
end

function GC.Inventory:SendManifest()
    local message = self:BuildManifestMessage()
    if not message or not GC.Sync then
        return false
    end
    if #message > GC.Constants.MAX_CHAT_BYTES then
        return false
    end
    self.guildBankDirty = false
    return GC.Sync:SendBulk(message, "GUILD")
end

function GC.Inventory:RequestGuildBank()
    if not GC.Sync or not IsInGuild or not IsInGuild() then
        return false
    end
    return GC.Sync:Send(BuildMessage({ "B", GC.Constants.SCHEMA_VERSION, "BQ" }))
end

function GC.Inventory:BuildTabMessages(tabIndex)
    local tab = self:GetGuildBank().tabs[tonumber(tabIndex) or -1]
    if type(tab) ~= "table" then
        return {}
    end
    local token = tostring(GC.Util.Now()) .. tostring(math.random(100, 999))
    local header = BuildMessage({
        "B", GC.Constants.SCHEMA_VERSION, "BT", token, "000", "000",
        tostring(tabIndex), tab.name or "", tostring(tonumber(tab.updatedAt) or 0),
        tab.seenBy or "", tab.fingerprint or "", "",
    })
    local payloadLimit = math.min(
        MAX_PAYLOAD_BYTES,
        GC.Constants.MAX_CHAT_BYTES - #header
    )
    local payload = EncodeCounts(tab.counts)
    local chunks = {}
    for offset = 1, math.max(1, #payload), payloadLimit do
        chunks[#chunks + 1] = payload:sub(offset, offset + payloadLimit - 1)
    end

    local messages = {}
    for index, chunk in ipairs(chunks) do
        messages[#messages + 1] = BuildMessage({
            "B", GC.Constants.SCHEMA_VERSION, "BT", token, index, #chunks,
            tostring(tabIndex), tab.name or "", tostring(tonumber(tab.updatedAt) or 0),
            tab.seenBy or "", tab.fingerprint or "", chunk,
        })
    end
    return messages
end

function GC.Inventory:SendTab(tabIndex)
    local messages = self:BuildTabMessages(tabIndex)
    if #messages == 0 or not GC.Sync then
        return false
    end
    for _, message in ipairs(messages) do
        if #message <= GC.Constants.MAX_CHAT_BYTES then
            GC.Sync:SendBulk(message, "GUILD")
        end
    end
    return true
end

-- Wer einen aelteren Stand hat, fordert den Tab an - gestreut und nur einmal.
-- Sieht ein Client die Anfrage eines anderen, stellt er seine eigene zurueck.
function GC.Inventory:ScheduleTabRequest(tabIndexes)
    local now = GC.Util.Now()
    local wanted = {}
    for _, tabIndex in ipairs(tabIndexes or {}) do
        local suppressedAt = self.suppressedTabRequests[tabIndex]
        if not suppressedAt or (now - suppressedAt) > TAB_REQUEST_SUPPRESS then
            wanted[#wanted + 1] = tabIndex
        end
    end
    if #wanted == 0 then
        return false
    end
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return self:SendTabRequest(wanted)
    end
    C_Timer.After(1 + math.random() * TAB_REQUEST_DELAY, function()
        GC.Inventory:SendTabRequest(wanted)
    end)
    return true
end

function GC.Inventory:SendTabRequest(tabIndexes)
    if not GC.Sync then
        return false
    end
    local now = GC.Util.Now()
    local wanted = {}
    for _, tabIndex in ipairs(tabIndexes or {}) do
        local suppressedAt = self.suppressedTabRequests[tabIndex]
        if not suppressedAt or (now - suppressedAt) > TAB_REQUEST_SUPPRESS then
            wanted[#wanted + 1] = tostring(tabIndex)
            self.suppressedTabRequests[tabIndex] = now
        end
    end
    if #wanted == 0 then
        return false
    end
    return GC.Sync:SendBulk(BuildMessage({
        "B",
        GC.Constants.SCHEMA_VERSION,
        "BR",
        table.concat(wanted, ","),
    }), "GUILD")
end

-- Abgelaufene Merker fliegen raus, sobald die Liste zu gross wird - dieselbe
-- Bauweise wie in der Werkstatt. Ein Eintrag, der aelter ist als die
-- Drosselzeit, bewirkt ohnehin nichts mehr.
local function PruneStamps(stamps, ttl, maximum)
    local count = 0
    for _ in pairs(stamps) do
        count = count + 1
    end
    if count <= maximum then
        return
    end
    local cutoff = GC.Util.Now() - ttl
    for key, at in pairs(stamps) do
        if (tonumber(at) or 0) < cutoff then
            stamps[key] = nil
        end
    end
end

function GC.Inventory:ReceiveSync(fields, sender)
    if tonumber(fields[2]) ~= GC.Constants.SCHEMA_VERSION then
        return
    end
    local operation = fields[3]
    local senderKey = GC.Util.NormalizeName(sender)
    if senderKey == "" then
        return
    end

    if operation == "BQ" then
        -- Antwort ist nur das Manifest, gedrosselt und gestreut: ein Login
        -- kostet damit hoechstens ein Paket.
        local now = GC.Util.Now()
        -- Aufgeraeumt wird sammelnd, nach derselben Bauweise wie in der
        -- Werkstatt: siehe MAX_MANIFEST_REPLIES.
        PruneStamps(self.guildBankRequestReplies, MIN_MANIFEST_REPLY_INTERVAL,
            MAX_MANIFEST_REPLIES)
        local lastReply = self.guildBankRequestReplies[senderKey]
        if lastReply and (now - lastReply) < MIN_MANIFEST_REPLY_INTERVAL then
            return
        end
        -- Die Wahl: Bis 0.9.96 schickte JEDER sein Manifest. Ein Paket je
        -- Antwortendem klingt harmlos, sind bei 250 Online aber 250 Pakete fuer
        -- einen einzigen Login - der Addon-Kanal stellt rund zehn je Sekunde zu
        -- und verwirft den Rest lautlos.
        if GC.Sync and GC.Sync.IsElectedResponder
            and not GC.Sync:IsElectedResponder(sender) then
            return
        end
        self.guildBankRequestReplies[senderKey] = now
        if C_Timer and type(C_Timer.After) == "function" then
            local scheduledAt = now
            C_Timer.After(MANIFEST_REPLY_DELAY + math.random() * MANIFEST_REPLY_SPREAD, function()
                -- Und die Stille: Wer waehrend seiner Streuzeit ein fremdes
                -- "BM" sieht, weiss, dass ein anderer Gewaehlter schon
                -- geliefert hat.
                if GC.Sync and GC.Sync.PeerAnsweredSince
                    and GC.Sync:PeerAnsweredSince(MANIFEST_ANSWER_KIND, scheduledAt) then
                    -- Die Drossel wird dabei ausdruecklich zurueckgenommen: Es
                    -- wurde nichts gesendet, also darf die naechste Anfrage
                    -- dieses Fragenden wieder beantwortet werden.
                    GC.Inventory.guildBankRequestReplies[senderKey] = nil
                    return
                end
                GC.Inventory:SendManifest()
            end)
        else
            self:SendManifest()
        end
        return
    elseif operation == "BM" then
        -- Ein fremdes Manifest ist zugleich die sichtbare Antwort eines anderen
        -- Gewaehlten. "B|" erreicht diese Stelle nur ueber den Gildenkanal
        -- (Sync:OnMessage) und nie vom eigenen Client - der Vermerk kann also
        -- weder eine Fluesterantwort noch die eigene Antwort meinen.
        if GC.Sync and GC.Sync.NotePeerAnswer then
            GC.Sync:NotePeerAnswer(MANIFEST_ANSWER_KIND)
        end
        local tabs = self:GetGuildBank().tabs
        local stale = {}
        for record in tostring(fields[4] or ""):gmatch("[^;]+") do
            local indexText, updatedText, fingerprint = record:match("^(%d+),(%d+),(%d*)$")
            local tabIndex = tonumber(indexText)
            local updatedAt = tonumber(updatedText)
            if tabIndex and updatedAt and tabIndex >= 1
                and tabIndex <= MAX_GUILD_BANK_TABS
                and #fingerprint <= 20 then
                local known = tabs[tabIndex]
                local knownAt = tonumber(known and known.updatedAt) or 0
                -- Nur ein Stand, der nach derselben Regel gewinnt, nach der
                -- der Empfang ihn spaeter annimmt, ist interessant. Ein
                -- Manifest ohne einen Tab sagt nichts ueber diesen Tab: der
                -- Absender darf ihn vielleicht nicht sehen.
                if WinsOverKnown(updatedAt, fingerprint, knownAt,
                    known and known.fingerprint) then
                    stale[#stale + 1] = tabIndex
                end
            end
        end
        if #stale > 0 then
            self:ScheduleTabRequest(stale)
        end
        return
    elseif operation == "BR" then
        local now = GC.Util.Now()
        local requested = {}
        for indexText in tostring(fields[4] or ""):gmatch("[^,]+") do
            local tabIndex = tonumber(indexText)
            -- Nur gueltige Tabnummern. Vorher wurde JEDE Zahl aus einer fremden
            -- Anfrage als Merker abgelegt: Ein Client, der nach Tab 4711 fragte,
            -- hinterliess einen Eintrag, der nie wieder abgefragt wurde und
            -- damit auch nie wieder verschwand. Mit dieser Pruefung kann die
            -- Liste hoechstens MAX_GUILD_BANK_TABS Eintraege haben und braucht
            -- kein Aufraeumen.
            if tabIndex and tabIndex >= 1 and tabIndex <= MAX_GUILD_BANK_TABS then
                requested[#requested + 1] = tabIndex
                -- Eine fremde Anfrage unterdrueckt die eigene.
                self.suppressedTabRequests[tabIndex] = now
            end
        end
        -- Die Wahl: Bis 0.9.96 schickte JEDER, der den Tab hatte, ihn
        -- vollstaendig in den Gildenkanal. Bei 250 Online und sechs gefuellten
        -- Tabs ist das ein Vielfaches dessen, was ein einziger Anfragender
        -- braucht. Der Vermerk oben bleibt davon unberuehrt: Wer nicht
        -- antwortet, stellt seine eigene Anfrage trotzdem zurueck.
        if GC.Sync and GC.Sync.IsElectedResponder
            and not GC.Sync:IsElectedResponder(sender) then
            return
        end
        local tabs = self:GetGuildBank().tabs
        for _, tabIndex in ipairs(requested) do
            local tab = tabs[tabIndex]
            -- Nur wer selbst einen Stand hat, antwortet; wer nichts hat,
            -- schweigt, statt Leere zu verteilen.
            if type(tab) == "table" and next(tab.counts or {}) then
                local ownDelay = TAB_REPLY_DELAY + math.random() * TAB_REPLY_SPREAD
                if C_Timer and type(C_Timer.After) == "function" then
                    local answerTab = tabIndex
                    local scheduledAt = now
                    C_Timer.After(ownDelay, function()
                        -- Und die Stille, je Tab: Wer waehrend seiner Streuzeit
                        -- ein fremdes "BT" fuer genau diesen Tab sieht, laesst
                        -- seine eigene Antwort fallen. Je Tab und nicht
                        -- pauschal, weil eine Anfrage mehrere Tabs nennen darf
                        -- und ein gelieferter Tab nichts ueber die anderen sagt.
                        if GC.Sync and GC.Sync.PeerAnsweredSince
                            and GC.Sync:PeerAnsweredSince(
                                TAB_ANSWER_PREFIX .. tostring(answerTab), scheduledAt) then
                            return
                        end
                        GC.Inventory:SendTab(answerTab)
                    end)
                else
                    self:SendTab(tabIndex)
                end
            end
        end
        return
    elseif operation ~= "BT" then
        return
    end

    local token = fields[4]
    local part = tonumber(fields[5])
    local total = tonumber(fields[6])
    local tabIndex = tonumber(fields[7])
    local tabName = fields[8] or ""
    local updatedAt = tonumber(fields[9]) or 0
    local seenBy = fields[10] or ""
    local fingerprint = tostring(fields[11] or "")
    local payload = fields[12] or ""
    if not token or not part or not total or not tabIndex
        or total < 1 or part < 1 or part > total or total > MAX_TRANSFER_PARTS
        or tabIndex < 1 or tabIndex > MAX_GUILD_BANK_TABS
        or #token > 40 or #tabName > 40 or #seenBy > 40
        or #fingerprint > 20 or #payload > MAX_PAYLOAD_BYTES then
        return
    end

    -- Der Vermerk "ein anderer liefert diesen Tab schon" steht bewusst NICHT
    -- hier, sondern erst unten, nachdem der eingetroffene Stand sich gegen den
    -- eigenen durchgesetzt hat.
    --
    -- An dieser Stelle war er falsch: Er lief vor jeder Pruefung und brachte
    -- damit auch dann zum Schweigen, wenn das Paket gleich darauf als
    -- VERALTET verworfen wurde. Genau der Client, der den neueren Stand haelt,
    -- liess daraufhin seine geplante Antwort fallen - und der Anfragende
    -- bekam den alten Stand oder gar keinen. Ein Paket, das der eigene Stand
    -- schlaegt, ist kein Ersatz fuer die eigene Antwort.

    local now = GC.Util.Now()
    for key, receivedAt in pairs(self.guildBankCompleted) do
        if (now - (tonumber(receivedAt) or 0)) > INCOMING_TTL then
            self.guildBankCompleted[key] = nil
        end
    end
    local incomingKey = senderKey .. "|" .. token .. "|" .. tostring(tabIndex)
    if self.guildBankCompleted[incomingKey] then
        return
    end
    for key, transfer in pairs(self.guildBankIncoming) do
        if (now - (tonumber(transfer.receivedAt) or 0)) > INCOMING_TTL then
            self.guildBankIncoming[key] = nil
        end
    end

    local incoming = self.guildBankIncoming[incomingKey]
    if incoming and (incoming.total ~= total or incoming.updatedAt ~= updatedAt) then
        self.guildBankIncoming[incomingKey] = nil
        incoming = nil
    end
    incoming = incoming or {
        parts = {},
        received = 0,
        total = total,
        updatedAt = updatedAt,
        tabName = tabName,
        seenBy = seenBy,
        fingerprint = fingerprint,
    }
    incoming.receivedAt = now
    if not incoming.parts[part] then
        incoming.parts[part] = payload
        incoming.received = incoming.received + 1
    end
    self.guildBankIncoming[incomingKey] = incoming
    if incoming.received < incoming.total then
        return
    end
    self.guildBankIncoming[incomingKey] = nil
    self.guildBankCompleted[incomingKey] = now

    -- Die aktuellsten Daten gewinnen, rangunabhaengig. Ein aelterer Stand darf
    -- einen neueren niemals ueberschreiben - nach derselben Regel, nach der
    -- das Manifest oben ueberhaupt angefordert hat.
    local tabs = self:GetGuildBank().tabs
    local known = tabs[tabIndex]
    if known and not WinsOverKnown(updatedAt, fingerprint,
        tonumber(known.updatedAt) or 0, known.fingerprint) then
        return
    end
    local assembled = {}
    for partIndex = 1, incoming.total do
        assembled[partIndex] = incoming.parts[partIndex] or ""
    end
    local counts = DecodeCounts(table.concat(assembled))

    -- Selbst nachrechnen statt dem Absender zu glauben - und das Ergebnis
    -- gegen seine Angabe halten.
    --
    -- Gewonnen hat der Absender oben MIT seinem Fingerabdruck. Passt der nicht
    -- zu den Bestaenden, die tatsaechlich angekommen sind, dann hat er sich
    -- mit einer Angabe durchgesetzt, die seine Daten nicht tragen. Frueher
    -- wurde in dem Fall stillschweigend der nachgerechnete gespeichert: Der
    -- Tab galt als uebernommen, stand aber mit einem anderen Fingerabdruck da
    -- als der, der die Entscheidung gewonnen hatte - und wurde beim naechsten
    -- Manifest gleich wieder angefordert.
    local recomputed = TabFingerprint(counts)
    if fingerprint ~= "" and recomputed ~= fingerprint then
        return
    end

    tabs[tabIndex] = {
        name = incoming.tabName,
        counts = counts,
        updatedAt = updatedAt,
        seenBy = incoming.seenBy ~= "" and incoming.seenBy or GC.Util.PlayerIdentityName(sender),
        fingerprint = recomputed,
    }

    -- ERST HIER der Vermerk: Dieses Paket hat sich gegen den eigenen Stand
    -- durchgesetzt und ist vollstaendig angekommen. Nur dann ist die eigene,
    -- noch geplante Antwort tatsaechlich ueberfluessig - siehe die Begruendung
    -- weiter oben, wo der Vermerk frueher stand.
    if GC.Sync and GC.Sync.NotePeerAnswer then
        GC.Sync:NotePeerAnswer(TAB_ANSWER_PREFIX .. tostring(tabIndex))
    end
    GC:FireCallback("INVENTORY_UPDATED")
end

-- === Bedarfsrechnung fuer die Werkstatt =====================================

-- Fuer ein Rezept: was braucht es, was ist da, was fehlt. Grundlage der
-- Ampelanzeige in den Rezeptdetails.
function GC.Inventory:GetReagentStatus(reagents)
    local rows = {}
    local missing = {}
    local coveredByGuildBank = {}
    for _, reagent in ipairs(reagents or {}) do
        local itemID = tonumber(reagent.itemID)
        local needed = math.max(1, tonumber(reagent.count) or 1)
        local own = self:GetOwnCounts(itemID)
        local guildBank, guildBankAt, guildBankBy = self:GetGuildBankCount(itemID)
        local status = "MISSING"
        if own.total >= needed then
            status = "OWN"
        elseif guildBank and (own.total + guildBank) >= needed then
            status = "GUILD"
        end
        local shortfall = math.max(0, needed - own.total)
        if shortfall > 0 then
            missing[#missing + 1] = {
                itemID = itemID,
                name = reagent.name,
                amount = shortfall,
                fromGuildBank = math.min(shortfall, guildBank or 0),
            }
            if guildBank and guildBank > 0 then
                coveredByGuildBank[#coveredByGuildBank + 1] = itemID
            end
        end
        rows[#rows + 1] = {
            itemID = itemID,
            name = reagent.name,
            needed = needed,
            own = own,
            guildBank = guildBank,
            guildBankAt = guildBankAt,
            guildBankBy = guildBankBy,
            status = status,
            shortfall = shortfall,
        }
    end
    return {
        rows = rows,
        missing = missing,
        guildBankKnown = self:GetGuildBankCount(0) ~= nil or next(self:GetGuildBank().tabs) ~= nil,
    }
end

local inventoryEvents = CreateFrame("Frame")
inventoryEvents:RegisterEvent("BAG_UPDATE")
inventoryEvents:RegisterEvent("BANKFRAME_OPENED")
inventoryEvents:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
inventoryEvents:RegisterEvent("GUILDBANKFRAME_OPENED")
inventoryEvents:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
inventoryEvents:RegisterEvent("GUILDBANKFRAME_CLOSED")
inventoryEvents:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE" then
        GC.Inventory:ScheduleBagScan()
    elseif event == "BANKFRAME_OPENED" or event == "PLAYERBANKSLOTS_CHANGED" then
        -- Bewusst ohne Entprellung: Die Bank ist nur bei offenem Fenster
        -- lesbar. Ein verzoegerter Scan koennte nach dem Schliessen laufen,
        -- eine leere Bank lesen und den gemerkten Bestand ausloeschen. Die
        -- Serie beim Einsortieren ist klein, lokal und harmlos.
        GC.Inventory:ScanBank()
    elseif event == "GUILDBANKFRAME_OPENED" then
        GC.Inventory:QueryGuildBankTabs()
    elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
        -- Die Abfrage eines Tabs ist beantwortet. Welcher es war, meldet das
        -- Ereignis nicht, deshalb wird der aktuell offene Tab gelesen und
        -- ansonsten alles, was noch aussteht.
        local current = tonumber(SafeCall(GetCurrentGuildBankTab))
        if current then
            GC.Inventory:ScanGuildBankTab(current)
        end
        for tabIndex in pairs(GC.Inventory.pendingTabs) do
            GC.Inventory:ScanGuildBankTab(tabIndex)
        end
    elseif event == "GUILDBANKFRAME_CLOSED" then
        GC.Inventory.pendingTabs = {}
        if GC.Inventory.guildBankDirty then
            GC.Inventory:SendManifest()
        end
    end
end)

GC:RegisterCallback("PLAYER_LOGIN", GC.Inventory, function(self)
    self:ScanBags()
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(12, function()
            GC.Inventory:RequestGuildBank()
        end)
    end
end)
