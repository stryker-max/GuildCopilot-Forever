local _, GC = ...

local DEFAULTS = {
    schemaVersion = GC.Constants.SCHEMA_VERSION,
    settings = {
        successSound = true,
        successSoundKey = "READY_CHECK",
        -- Eigener Ton fuer die Bestaetigung des eigenen Raidprofils, getrennt
        -- vom Bewerberklang.
        profileSoundKey = "LEVEL_UP",
        captureOnlyDuringSearch = true,
        watchRecruitmentTriggers = true,
        -- Freie Erkennung: Bewerber auch dann finden, wenn ihre Formulierung
        -- in keiner Wendungsliste steht ("ENH sucht Anschluss an Gilde").
        -- Unterschieden wird ueber die Wortreihenfolge; Einzelheiten in
        -- Constants.lua. Eigener Schalter, weil die Wendungslisten ihre Zusage
        -- behalten sollen: Wer seine Liste bewusst eng haelt, bekommt mit
        -- diesem Schalter aus auch genau das - und nichts darueber hinaus.
        --
        -- Ab 0.9.135 ab Werk AUS: Das Postfach erfasst standardmaessig nur, was
        -- die eingetragenen Trigger-Woerter woertlich treffen - keine Automatik,
        -- die anhand der Wortreihenfolge raet. Wer das Raten will, schaltet es
        -- hier ein.
        smartRecruitmentDetection = false,
        -- Trigger- und Ausschlusswoerter fuers Postfach. Bewusst lokal und
        -- nicht gildenweit: Sie aendern nur, was im eigenen Postfach landet,
        -- genau wie die beiden Schalter darueber.
        --
        -- Ab 0.9.135 ist die freie Erkennung der Hauptschalter fuer die ganze
        -- eingebaute Schicht: Steht sie auf AUS (Vorgabe), zaehlt strikt, was
        -- hier steht - ein leeres Feld erfasst dann nichts. Erst mit ihr an
        -- greift wieder die mitgelieferte Vorgabe (fuer ein leeres Feld) samt
        -- Reihenfolge-Erkennung.
        recruitmentFilters = {
            chatTriggers = {},
            chatExclusions = {},
            whisperTriggers = {},
            whisperExclusions = {},
        },
        minimap = {
            hidden = false,
            angle = 225,
            -- Der Winkel bestimmt die Position am aktuellen Minimap-Rand.
            -- Umschalt + Ziehen speichert eine freie Position in UIParent-Einheiten.
            free = false,
            x = 0,
            y = 0,
        },
        workshopFavorites = {},
        -- Lokal weggeklickte Gildenauftraege (Orders:SetDeclined). Der
        -- Vermerk geht nie ins Netz und verschwindet mit seinem Auftrag.
        declinedOrders = {},
        -- Selbst mitgezaehlte Fertigungen je Auftrag, bis sie gemeldet sind.
        -- Ebenfalls rein lokal (Orders:NoteCraftedSpell).
        pendingCrafts = {},
        -- Sprache der Oberflaeche: AUTO folgt der Clientsprache, DE und EN
        -- erzwingen eine. Angewandt in GC.ApplyLanguageSetting.
        language = "AUTO",
        -- Maßstab und Deckkraft des Hauptfensters in Prozent (UI:ApplyWindowLook).
        -- 100/100 ist der Auslieferungszustand: unveraendert wie bisher.
        window = {
            scale = 100,
            alpha = 100,
            -- Zugeklappt auf die Kopfzeile (UI:SetWindowMinimized). Der
            -- Zustand ueberlebt den Ausstieg, wie bei jedem Fenster.
            minimized = false,
        },
        -- Meldung im Chat, sobald eine Berufs-Wartezeit (Umwandlung,
        -- Spezialtuch, Sphaere) abgelaufen ist. Bewusst an: Sie ist eine
        -- einzelne Chatzeile je Sperre, kein Laerm.
        cooldownReminder = true,
        postBar = {
            hidden = true,
            x = 0,
            y = -220,
            -- Automatisches Wiederholen der Werbung. Nur ausdruecklich
            -- eingeschaltet, und gepostet wird ausschliesslich im Kontext
            -- eines echten Tastendrucks - nie von einem Timer.
            autoRepeat = false,
        },
        -- Kompakt-Tracker der Gildenauftraege (Owner-Entscheidung: Stufe 1).
        -- Er zeigt sich nur, wenn es "du bist dran"-Auftraege gibt; hidden
        -- merkt sich das ausdrueckliche Wegklicken.
        orderTracker = {
            hidden = false,
            x = 0,
            y = -300,
        },
        -- Klangrueckmeldung der Gildenauftraege, je Ereignis ein Schluessel
        -- aus GC.SuccessSoundOptions; leer heisst ausdruecklich aus.
        orderSounds = {
            newOrder = "LEVEL_UP",
            accepted = "IG_QUEST_ACTIVATE",
            progress = "MAP_PING",
            done = "IG_QUEST_LIST_COMPLETE",
        },
        -- Der vorbelegte Fluestertext fuer die Uebergabe. {name} wird zum
        -- Empfaenger, {rezept} zum Rezeptnamen; gesendet wird erst mit Enter.
        orderWhisperText = "Hallo {name}! Dein Auftrag „{rezept}“ ist fertig – "
            .. "ich wäre bereit für die Übergabe.",
        -- Die Bildschirmmeldung bei neuen machbaren Auftraegen. Frei
        -- verschiebbar, weil die Standard-Raidwarnungsposition erfahrungsgemaess
        -- von WeakAuras belegt ist.
        orderBanner = {
            enabled = true,
            x = 0,
            y = 200,
            -- Sekunden, die die Meldung voll sichtbar steht, bevor sie
            -- ausblendet; in den Einstellungen von 1 bis 30 einstellbar.
            holdSeconds = 3,
        },
        postCooldown = GC.Constants.DEFAULT_POST_COOLDOWN,
        lfgCooldown = GC.Constants.DEFAULT_LFG_COOLDOWN,
        -- Die Raidsuche (docs/KONZEPT-raidsuche-lfm.md). Alles hier ist
        -- Ansichts- und Arbeitsstil des Raidleiters und bleibt deshalb lokal;
        -- der Suchzettel selbst liegt gildenbezogen (GUILD_DEFAULTS).
        raidSearch = {
            -- Automatisches Wiederholen des Suchspruchs - dasselbe Modell wie
            -- der Werbebalken: nur ausdruecklich eingeschaltet, gepostet wird
            -- ausschliesslich im Kontext eines echten Tastendrucks, den Takt
            -- geben die Kanal-Cooldowns vor.
            autoRepeat = false,
            -- Ton bei neuen Antworten im Zulauf, Vorgabe aus (Konzept).
            sound = false,
            bar = {
                hidden = false,
                x = 0,
                y = -140,
            },
            -- Kanalwahl je Suche (Owner-Entscheidung): die vier Kanalarten,
            -- der Gildenchat und selbst beigetretene Kanaele - Letztere unter
            -- ihrem NAMEN, weil sich die Kanalnummer je Login aendern kann.
            channels = {
                RECRUITMENT = false,
                LFG = true,
                TRADE = true,
                GENERAL = false,
                GUILD = true,
                custom = {},
            },
            -- Selbstgebaute Antwortvorlagen (Owner-Entscheidung). Zwei
            -- Beispiele setzt GC.RaidSearch:GetReplyTemplates beim ersten
            -- Zugriff; das Seeded-Flag haelt Geloeschtes geloescht.
            replyTemplates = {},
            replyTemplatesSeeded = false,
        },
        -- Lokale Automatik des Gear Audits. Bewusst nicht gildenweit: Beides
        -- aendert nur, wann geprueft und wie eine unbewertete Verzauberung
        -- angezeigt wird, nie was tatsaechlich in der Ausruestung steckt.
        gearAudit = {
            acceptUnratedEnchants = not GC.Client.isForever,
        },
        channels = {
            RECRUITMENT = true,
            LFG = false,
            TRADE = false,
            GENERAL = false,
        },
    },
    characters = {},
    guilds = {},
    -- Bereits gemeldete Wartezeit-Ablaeufe: je Sperre der Ablaufzeitpunkt,
    -- damit dieselbe Sperre nicht bei jedem Login erneut gemeldet wird.
    cooldownReminded = {},
}

local GUILD_DEFAULTS = {
    editorRecoveryAvailable = true,
    profile = {
        enabled = true,
        disabledFields = {},
        description = "",
        raidTimes = "",
        progress = "",
        lootSystem = "",
        discord = "",
        contact = "",
        updatedAt = 0,
    },
    profilePermissions = {
        configured = false,
        editorRanks = {},
    },
    replyTemplates = {
        THANKS = "Hallo {name}, danke für dein Interesse an unserer Gilde! Was spielst du, und wonach suchst du?",
        INFO = "{beschreibung} Raidzeiten: {raidzeiten}. Lootsystem: {loot}. Progress: {progress}.",
        DISCORD = "Wenn du magst, lernen wir uns kurz im Discord kennen: {discord}",
    },
    remoteProfiles = {},
    addonUsers = {},
    recruitment = {
        selections = {},
        raidMarker = 8,
        replyMarker = 0,
        classOrder = {},
        priorities = {},
    },
    inbox = {},
    -- Wer hier steht, erzeugt keinen Postfacheintrag mehr. Leeres "until_"
    -- bedeutet dauerhaft, sonst gilt der Eintrag bis zu diesem Datum.
    inboxFilters = {},
    -- Wessen Rang den Bewerberton hoert. Gildenweit, weil sonst jeder, den der
    -- Ton nicht betrifft, ihn selbst abschalten muesste - und genau das weiss
    -- er nicht. Das Postfach fuellt sich fuer alle weiter, nur still: Wer
    -- spaeter nachsieht, verpasst nichts.
    inboxSound = {
        ranksConfigured = false,
        ranks = {},
    },
    postHistory = {},
    lastPosts = {},
    warcraftLogs = {
        url = "",
        -- Host der Gildenquelle, damit eine Sprachvariante wie
        -- "de.fresh.warcraftlogs.com" erhalten bleibt.
        host = "",
        region = "",
        serverSlug = "",
        guildSlug = "",
        importedAt = 0,
        members = {},
        reportCount = 0,
        sessionCount = 0,
        -- Wer den zuletzt uebernommenen Rekrutierungsdatensatz geschickt hat.
        lastSyncFrom = "",
    },
    workshop = {
        -- Jedes Rezept steht genau einmal im Katalog; die Crafter halten nur
        -- noch die Schluessel dessen, was sie koennen.
        catalog = {},
        crafters = {},
    },
    -- Die Gildenbank gehoert allen und wird deshalb geteilt - je Tab, weil die
    -- Sichtbarkeit eines Tabs am Gildenrang haengt. Eigene Taschen- und
    -- Bankbestaende bleiben dagegen im Charakterzweig und werden nie gesendet.
    guildBank = {
        tabs = {},
    },
    raidSessions = {},
    -- Dauerhafte Anwesenheit je Raidabend, getrennt von den Auswertungen:
    -- Die Ablage der Auswertungen ist bewusst klein und kurzlebig, die
    -- Saisonfrage "wie zuverlaessig ist jemand?" braucht ein laengeres
    -- Gedaechtnis (Naeheres bei RaidMonitor:RecordAttendance).
    attendance = {},
    gearAudits = {},
    -- Bewertungen ohne Spec-Bezug. Sie gelten fuer alle und sind der
    -- Rueckfall, wenn fuer eine Spec nichts hinterlegt ist.
    enchantRules = {},
    -- Bewertungen je Spec: enchantSpecRules["WARRIOR:1"]["2748"]. Dieselbe
    -- Verzauberung kann fuer Waffen optimal und fuer Schutz verbesserbar sein.
    enchantSpecRules = {},
    memberCare = {
        inactivityDays = 60,
        protectedRanksConfigured = false,
        protectedRanks = {},
        accessRanksConfigured = false,
        accessRanks = {},
        decisions = {},
    },
    roster = {
        rankFilterConfigured = false,
        activeRaiderRanks = {},
    },
    -- Die Raidsuche: genau EIN Suchzettel (Owner-Entscheidung "nur ein Raid",
    -- docs/KONZEPT-raidsuche-lfm.md) plus Vorlagen. "plan" hat bewusst keinen
    -- Vorgabewert - kein Zettel heisst nil, angelegt wird er erst ueber
    -- GC.RaidSearch:NewPlan. Gildenbezogen abgelegt, in dieser Stufe aber
    -- nicht synchronisiert (keine Sync-Nachrichtenart registriert); liegt es
    -- von Anfang an hier, braucht eine spaetere gildenweite Stufe keinen
    -- Datenumzug.
    raidSearch = {
        templates = {},
    },
}

GC.DB = {}
GC.DB.GuildProfileFields = { "description", "raidTimes", "progress", "lootSystem", "discord", "contact" }

function GC.DB:IsGuildProfileFieldEnabled(key)
    local profile = self:GetGuild().profile
    return profile.enabled ~= false and not (profile.disabledFields and profile.disabledFields[key])
end

function GC.DB:GetActiveGuildProfile()
    local profile = self:GetGuild().profile
    local active = {}
    for _, key in ipairs(self.GuildProfileFields) do
        active[key] = profile.enabled ~= false and not profile.disabledFields[key] and (profile[key] or "") or ""
    end
    return active
end

function GC.DB:Initialize()
    local GuildCopilotForeverDB = _G[GC.Client.savedVariable]
    local previousSchema = type(GuildCopilotForeverDB) == "table" and tonumber(GuildCopilotForeverDB.schemaVersion) or 0
    GuildCopilotForeverDB = GC.Util.MergeDefaults(GuildCopilotForeverDB, DEFAULTS)
    -- Die Selbstprüfung und ihr Gildenabgleich sind seit 0.9.19 fester
    -- Hintergrunddienst. Ein alter lokaler Schalter darf sie nicht abschalten.
    GuildCopilotForeverDB.settings.gearAudit.auditSelf = nil
    if GuildCopilotForeverDB.settings.successSoundKey == "UI_GROUP_FINDER_RECEIVE_APPLICATION" then
        GuildCopilotForeverDB.settings.successSoundKey = "GROUP_FINDER"
    end

    if previousSchema < 2 then
        GuildCopilotForeverDB.settings.channels.RECRUITMENT = true
        GuildCopilotForeverDB.settings.channels.LFG = false
        GuildCopilotForeverDB.settings.channels.TRADE = false
        GuildCopilotForeverDB.settings.channels.GENERAL = false
        GuildCopilotForeverDB.settings.postCooldown = GC.Constants.DEFAULT_POST_COOLDOWN
        GuildCopilotForeverDB.settings.lfgCooldown = GC.Constants.DEFAULT_LFG_COOLDOWN
    end

    local legacyEditorRecovery = GuildCopilotForeverDB.settings.editorRecoveryAvailable
    if legacyEditorRecovery ~= nil then
        for _, guildData in pairs(GuildCopilotForeverDB.guilds or {}) do
            if guildData.editorRecoveryAvailable == nil then
                guildData.editorRecoveryAvailable = legacyEditorRecovery
            end
        end
        GuildCopilotForeverDB.settings.editorRecoveryAvailable = nil
    end

    if previousSchema < 3 then
        for _, profile in pairs(GuildCopilotForeverDB.characters or {}) do
            if profile.secondarySpecKey == profile.raidSpecKey then
                profile.secondarySpecKey = nil
            end
        end
    end

    if previousSchema < 4 then
        for _, profile in pairs(GuildCopilotForeverDB.characters or {}) do
            profile.professions = profile.professions or {}
            if profile.professionAuto == nil then
                profile.professionAuto = true
            end
        end
    end

    if previousSchema < 5 then
        for _, profile in pairs(GuildCopilotForeverDB.characters or {}) do
            profile.workshop = profile.workshop or { professions = {} }
            profile.workshop.professions = profile.workshop.professions or {}
        end
    end

    -- Ein zufaelliges, anonymes Kennzeichen fuer diesen Account. WoW verraet
    -- Addons nie, welche Charaktere zusammengehoeren; die SavedVariables liegen
    -- aber pro Account, also kann der Client es selbst sagen. Damit zaehlt die
    -- Gildenuebersicht Spieler statt Charaktere. Der Wert traegt keine
    -- Account-Daten, er ist nur eine Zufallsfolge.
    if type(GuildCopilotForeverDB.accountTag) ~= "string" or #GuildCopilotForeverDB.accountTag ~= 10 then
        local alphabet = "0123456789abcdef"
        local tag = {}
        for _ = 1, 10 do
            local index = math.random(#alphabet)
            tag[#tag + 1] = alphabet:sub(index, index)
        end
        GuildCopilotForeverDB.accountTag = table.concat(tag)
    end

    GuildCopilotForeverDB.schemaVersion = GC.Constants.SCHEMA_VERSION
    _G[GC.Client.savedVariable] = GuildCopilotForeverDB
    self.data = GuildCopilotForeverDB
    -- Die gespeicherte Sprachwahl gilt ab jetzt - und damit VOR dem Aufbau
    -- der Oberflaeche, deren ADDON_LOADED-Rueckruf spaeter registriert wurde.
    if GC.ApplyLanguageSetting then
        GC.ApplyLanguageSetting()
    end
    -- Der Datenbestand ist neu; ein Merker aus einem frueheren Durchlauf zeigt
    -- auf eine Tabelle, die es so nicht mehr gibt.
    self.guildCache = nil
    self.guildCacheKey = nil
end

function GC.DB:GetAccountTag()
    return type(self.data) == "table" and self.data.accountTag or ""
end

function GC.DB:Get()
    return self.data
end

function GC.DB:GetSettings()
    return self.data.settings
end

function GC.DB:GetCharacter(characterKey)
    characterKey = characterKey or GC:GetPlayerFullName()
    self.data.characters[characterKey] = self.data.characters[characterKey] or {}
    return self.data.characters[characterKey]
end

-- Der Gildendatensatz, einmal mit den Vorgaben aufgefuellt.
--
-- MergeDefaults faehrt den kompletten GUILD_DEFAULTS-Baum rekursiv ab. Das ist
-- beim ERSTEN Mal genau richtig und danach reine Arbeit ohne Ergebnis: Der
-- Baum ist dann vollstaendig, jeder weitere Durchlauf traegt nichts nach.
--
-- Der Aufruf steht aber in den heissesten Schleifen des Addons. Gemessen an
-- einer Gilde mit 500 Mitgliedern und 500 gespeicherten Ausruestungspruefungen:
-- ein einziger Durchlauf von GearAudit:ReapplyEnchantRules rief diese Funktion
-- 17.168 mal auf und brauchte dafuer 307 ms - eine knappe Drittelsekunde
-- Standbild, bei jedem Mitglied, sobald ein Offizier das Gildenprofil
-- speichert. Mit dem Merker unten sind es 26 ms.
--
-- Gemerkt wird nur, was sich nachweislich nicht geaendert hat, und geprueft
-- wird beides:
--   * derselbe Gildenschluessel - ein Gildenwechsel oder ein Login, bei dem
--     GetGuildInfo noch nichts liefert, ergibt einen anderen Schluessel;
--   * dieselbe Tabelle - wer den Zweig von aussen ersetzt (Initialize, ein
--     von Hand bearbeitetes SavedVariables), bekommt einen frischen Durchlauf.
-- Der Schluessel selbst wird weiterhin bei jedem Aufruf berechnet: Direkt nach
-- dem Login heisst die Gilde noch nicht, wie sie heisst, und ein gemerkter
-- Schluessel waere dann fuer den Rest der Sitzung der falsche.
function GC.DB:GetGuild()
    local guildKey = GC:GetGuildKey()
    local cached = self.guildCache
    if cached ~= nil and self.guildCacheKey == guildKey
        and self.data.guilds[guildKey] == cached then
        return cached
    end

    local guildData = GC.Util.MergeDefaults(self.data.guilds[guildKey], GUILD_DEFAULTS)
    -- Remove only beta.1's untouched default; preserve edited guild profiles.
    if GC.Client.isForever and guildData.profile.progress == "SSC/TK"
        and (tonumber(guildData.profile.updatedAt) or 0) == 0 then
        guildData.profile.progress = ""
    end
    self.data.guilds[guildKey] = guildData
    self.guildCacheKey = guildKey
    self.guildCache = guildData
    return guildData
end

-- Derselbe Spieler steht in remoteProfiles und addonUsers unter ZWEI
-- Schluesseln: einmal mit Realmanteil, wie ihn der Absender einer
-- Addon-Nachricht traegt, und einmal ohne. Beide zeigen auf dieselbe Tabelle -
-- es sind also keine zwei Datensaetze, aber zwei Eintraege, und in einer Gilde
-- mit 500 Mitgliedern damit 1.000 statt 500 je Tabelle.
--
-- Weggeraeumt wird der Eintrag MIT Realm, nicht der ohne: Jede lesende Stelle
-- im Addon versucht ohnehin beide und faellt auf den Kurznamen zurueck
-- (Roster:GetProfile, Sync:GetAddonUser, WarcraftLogs, Orders), und der
-- Kurzname ist laut GC.Util.PlayerKey der Schluessel, auf den sich das Addon
-- ueberall geeinigt hat. Zusammengelegt wird nur, was nachweislich dieselbe
-- Tabelle ist - ein Eintrag, der wirklich einen anderen Spieler meint, bleibt
-- unangetastet.
local function CollapseDuplicateKeys(entries)
    if type(entries) ~= "table" then
        return 0
    end
    -- Erst sammeln, dann loeschen: Waehrend eines pairs-Durchlaufs zu
    -- veraendern ist in Lua nur fuer den gerade besuchten Schluessel definiert.
    local drop = {}
    for key, entry in pairs(entries) do
        local shortKey = GC.Util.PlayerKey(key)
        if shortKey ~= "" and shortKey ~= key and entries[shortKey] == entry then
            drop[#drop + 1] = key
        end
    end
    for _, key in ipairs(drop) do
        entries[key] = nil
    end
    return #drop
end

function GC.DB:Prune()
    local guildData = self:GetGuild()
    if GC.Chat and GC.Chat.inboxIncoming then GC.Util.PruneTransfers(GC.Chat.inboxIncoming) end
    if GC.Orders and GC.Orders.incoming then GC.Util.PruneTransfers(GC.Orders.incoming) end
    local cutoff = GC.Util.Now() - (180 * 24 * 60 * 60)
    for name, profile in pairs(guildData.remoteProfiles) do
        if (profile.receivedAt or 0) < cutoff then
            guildData.remoteProfiles[name] = nil
        end
    end
    local addonUserCutoff = GC.Util.Now() - GC.Constants.ADDON_USER_TTL
    for name, addonUser in pairs(guildData.addonUsers or {}) do
        if (addonUser.seenAt or 0) < addonUserCutoff then
            guildData.addonUsers[name] = nil
        end
    end
    CollapseDuplicateKeys(guildData.remoteProfiles)
    CollapseDuplicateKeys(guildData.addonUsers)
    local removedCrafters = false
    for name, crafter in pairs(guildData.workshop.crafters or {}) do
        if (crafter.updatedAt or 0) < cutoff then
            guildData.workshop.crafters[name] = nil
            removedCrafters = true
        end
    end
    -- Das Aufraeumen ist eine Schreibstelle wie jede andere: Der Werkstatt-
    -- katalog wird zwischengespeichert und muss danach neu entstehen.
    if removedCrafters and GC.Workshop and GC.Workshop.InvalidateCatalog then
        GC.Workshop:InvalidateCatalog()
    end

    local sessionCutoff = GC.Util.Now() - (30 * 24 * 60 * 60)
    for index = #guildData.raidSessions, 1, -1 do
        if (guildData.raidSessions[index].endedAt or 0) < sessionCutoff then
            table.remove(guildData.raidSessions, index)
        end
    end

    -- Verjaehrte Bewerbungen zuerst wegraeumen (Begruendung an
    -- GC.Constants.INBOX_LEAD_TTL), dann erst der Mengendeckel - sonst
    -- verdraengt Altes, das ohnehin verfaellt, womoeglich Frisches.
    if GC.Chat and GC.Chat.IsLeadExpired then
        for index = #guildData.inbox, 1, -1 do
            if GC.Chat:IsLeadExpired(guildData.inbox[index]) then
                table.remove(guildData.inbox, index)
            end
        end
    end
    if #guildData.inbox > 100 and GC.Chat then
        table.sort(guildData.inbox, function(a, b)
            return GC.Chat:LeadLastActivity(a) > GC.Chat:LeadLastActivity(b)
        end)
    end
    while #guildData.inbox > 100 do
        table.remove(guildData.inbox)
    end
    while #guildData.postHistory > 50 do
        table.remove(guildData.postHistory)
    end

    -- Die Raidsuche: Ein BEENDETER Zettel bleibt sieben Tage zum Nachschauen
    -- liegen, dann faellt er weg. Die Deckel (Zulauf 40, Nachrichten je
    -- Antwort 10, Vorlagen 12) halten die Schreibstellen; hier werden sie nur
    -- nachgesichert, fuer von Hand bearbeitete SavedVariables.
    local raidSearch = guildData.raidSearch
    if type(raidSearch) == "table" then
        local plan = raidSearch.plan
        if type(plan) == "table" then
            if plan.status == "BEENDET"
                and (tonumber(plan.endedAt) or 0) < GC.Util.Now() - (7 * 24 * 60 * 60) then
                raidSearch.plan = nil
            elseif type(plan.responses) == "table" then
                while #plan.responses > 40 do
                    table.remove(plan.responses)
                end
            end
        end
        if type(raidSearch.templates) == "table" then
            while #raidSearch.templates > 12 do
                table.remove(raidSearch.templates)
            end
        end
    end
end

GC:RegisterCallback("ADDON_LOADED", GC.DB, function(self)
    self:Initialize()
end)

-- Aufgeraeumt wird nicht nur beim Login.
--
-- Bisher lief Prune genau einmal je Sitzung. Wer den Client tagelang laufen
-- laesst - in einer Raidgilde der Regelfall -, sammelte bis zum naechsten
-- Neustart alles an: abgelaufene Profile, Addon-Nutzer, die laengst
-- ausgetreten sind, und die doppelten Schluessel oben. Der Durchlauf ist
-- billig (er laeuft ueber Tabellen, nicht ueber Mitglieder) und stoert bei
-- diesem Abstand niemanden.
local PRUNE_INTERVAL = 15 * 60

local function SchedulePrune()
    if not C_Timer or type(C_Timer.After) ~= "function" then
        return
    end
    C_Timer.After(PRUNE_INTERVAL, function()
        if GC.DB and GC.DB.data then
            GC.DB:Prune()
        end
        SchedulePrune()
    end)
end

GC:RegisterCallback("PLAYER_LOGIN", GC.DB, function(self)
    self:Prune()
    SchedulePrune()
end)
