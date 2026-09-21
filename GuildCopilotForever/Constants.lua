local _, GC = ...

GC.Constants = {
    ADDON_NAME = "Guild Copilot",
    VERSION = "0.1.0-beta.5",
    SCHEMA_VERSION = 7,
    -- Wie eine Zahl der Raidauswertung ZU LESEN ist. Nicht zu verwechseln mit
    -- SCHEMA_VERSION: Die beschreibt das Nachrichtenformat, also ob zwei
    -- Clients einander verstehen. Diese hier beschreibt, ob zwei Zahlen
    -- dasselbe bedeuten - und nur dann duerfen sie miteinander verrechnet
    -- werden.
    --
    -- Sie steigt bei jeder Aenderung an der Bedeutung, auch wenn das Format
    -- gleich bleibt:
    --   1  bis 0.9.86 - Trommeln wurden jedem Beschenkten gutgeschrieben,
    --      Traenke mit Buff zaehlten doppelt, Dauerbuffs je Abend nur einmal.
    --   2  ab 0.9.89 - Zaehlung je Kategorie ueber genau eine Quelle (0.9.87)
    --      und Anwesenheit ohne Offlinezeit (0.9.88).
    --
    -- Wozu: Ein Mitschnitt aus einer anderen Regelversion darf beim Reparieren
    -- einer eigenen Luecke NICHT eingerechnet werden. Der Hoechstwert wuerde
    -- sonst genau die kaputten Zaehler eines alten Clients uebernehmen - im
    -- Vergleichslog vom 02.08.2026 waren das 68 Trommeln statt 28. Solche
    -- Auswertungen bleiben sichtbar nebeneinander stehen, statt verrechnet zu
    -- werden.
    RAID_RULES_VERSION = 2,
    INTERFACE_VERSION = 20506,
    COMM_PREFIX = "GuildCopilotForever",
    MAX_CHAT_BYTES = 255,
    MAX_PLAYER_NAME_BYTES = 96,
    -- Das Gildenprofil wandert zerlegt durch den Gildenkanal. Sender und
    -- Empfaenger MUESSEN dieselbe Obergrenze kennen: Bisher schnitt der Sender
    -- unbegrenzt viele Bloecke, waehrend der Empfaenger jede Uebertragung mit
    -- mehr als 30 Bloecken verwarf. Alles ueber 5250 Bytes verschwand damit
    -- ohne eine einzige Meldung - und allein die Spec-Verzauberungsregeln
    -- duerfen schon rund 4300 Bytes gross werden.
    GUILD_PROFILE_CHUNK_BYTES = 175,
    GUILD_PROFILE_MAX_CHUNKS = 150,
    -- Warcraft-Logs-Host, wenn die gespeicherte Gildenquelle keinen eigenen
    -- nennt. Die deutsche Variante ist Vorgabe, weil das Addon deutschsprachig
    -- ist; ein selbst eingetragener Host bleibt immer erhalten.
    WCL_DEFAULT_HOST = "de.fresh.warcraftlogs.com",
    -- Profil-Links zum Nachschlagen eines Interessenten. Beide Vorlagen
    -- verstehen die Platzhalter <host>, <region>, <realm> und <name>. Wer eine
    -- andere Seite bevorzugt oder ein Pfadschema sich aendert, tauscht nur
    -- diese Zeichenketten.
    -- Classic Armory fuehrt die Spielfassung als eigenes Pfadsegment; dieses
    -- Addon ist ausschliesslich fuer TBC Anniversary gedacht.
    ARMORY_CHARACTER_URL = "https://classic-armory.org/character/<region>/tbc-anniversary/<realm>/<name>",
    WCL_CHARACTER_URL = "https://<host>/character/<region>/<realm>/<name>",
    -- Wie viele aktive Raider die Gildenuebersicht fuehrt. 25 war exakt die
    -- Groesse eines Schlachtzugs und damit zu knapp: Ersatzleute, Twinks und
    -- gerade offline gegangene Stammspieler fielen hinten heraus, und die Liste
    -- sah kleiner aus als die Gilde ist. 35 laesst zehn Plaetze Puffer.
    ACTIVE_RAIDER_LIMIT = 35,
    ADDON_USER_TTL = 30 * 24 * 60 * 60,
    -- Wie lange eine Bewerbung im Postfach lebt. Danach ist sie VERJAEHRT:
    -- Sie wird lokal weggeraeumt, nicht mehr an die Gilde gesendet und aus
    -- einem fremden Paket auch nicht mehr angenommen. Ohne diese Grenze
    -- kreisten tagealte Bewerbungen endlos durchs Schneeballprinzip: Bei
    -- jedem Login fragt ein Client den Bestand der Kollegen an, und deren
    -- Altbestand kam als "ungelesen" zurueck - genau die Gildenmeldung
    -- "es werden immer alte Nachrichten wieder ins Postfach geschoben".
    INBOX_LEAD_TTL = 14 * 24 * 60 * 60,
    DEFAULT_POST_COOLDOWN = 120,
    DEFAULT_LFG_COOLDOWN = 120,
}

-- Fähigkeiten, die dieser Client im Handshake meldet. Neue Module tragen sich
-- hier ein, damit spätere Versionen erkennen können, was das Gegenüber kann,
-- ohne die Schemaversion anheben zu müssen.
GC.Capabilities = {
    "profile",
    "guildprofile",
    "workshop",
    "workshop2",
    "workshop3",
    -- workshop4: getrennter Rezeptkatalog und Herstellerindex. Wer das meldet,
    -- versteht Schluessellisten und braucht keine Vollkopie aller Rezepte.
    "workshop4",
    "recruitmentsync",
    "membercare",
    "raidmonitor",
    "gearaudit",
    "gearsync",
    "wclimport",
    -- inventory1: Materialbestand und Gildenbank-Abgleich ueber "B|".
    "inventory1",
    -- gearexempt1: versteht ausgenommene Ausruestungsplaetze im Snapshot.
    "gearexempt1",
    -- cooldown1: versteht Wartezeiten von Rezepten ("W|…|CD|…").
    "cooldown1",
    -- workshop5: versteht Bestandsmanifeste Dritter ("W|…|CM|…") - das Wissen,
    -- welche Hersteller es in der Gilde gibt, auch wenn deren Besitzer gerade
    -- offline sind. Nur wer das meldet, bekommt auf "Q" ein solches Manifest.
    "workshop5",
    -- workshop6: liefert als Bote auch die DATEN Dritter - beantwortet
    -- adressierte Schluessellisten-Anfragen (sechstes KR-Feld) aus dem eigenen
    -- Herstellerindex und Rezeptnachforderungen aus dem eigenen Katalog. Nur
    -- an einen Absender mit diesem Kennzeichen wird eine adressierte Anfrage
    -- gestellt; ein aelterer Client wuerde sie stumm liegen lassen.
    "workshop6",
    -- guildprofile2: nimmt das Gildenprofil auch per Fluestern an und quittiert
    -- jedes Teil ("A|…|G|…"). Nur an einen Empfaenger mit diesem Kennzeichen
    -- wird gezielt gesendet - ein aelterer Client laesst ein gefluestertes
    -- "G|" stumm liegen, und jedes Teil liefe hier acht Mal vergeblich an,
    -- bevor der Knopf einen Fehlschlag meldet, den es gar nicht gab.
    "guildprofile2",
}

GC.ProfessionOptions = {
    "",
    "Alchimie",
    "Bergbau",
    "Ingenieurskunst",
    "Kräuterkunde",
    "Kürschnerei",
    "Lederverarbeitung",
    "Schmiedekunst",
    "Schneiderei",
    "Verzauberkunst",
}

-- === Berufe in beiden Client-Sprachen ======================================
--
-- Ein englischer Client nennt denselben Beruf "Enchanting", ein deutscher
-- "Verzauberkunst". Bis 0.9.101 war der lokalisierte Name zugleich der
-- Speicher- und Vergleichsschluessel - dieselbe Verzauberkunst stand damit
-- doppelt im Katalog (16 "Berufe" statt 11), und wer mit englischem Client
-- spielte, bekam auf ewig "Berufsfenster einmal öffnen" angemahnt, weil sein
-- Profil den deutschen Namen trug und sein Scan den englischen Schluessel
-- ablegte.
--
-- Der KANONISCHE Schluessel ist die gefaltete deutsche Schreibweise - nicht aus
-- Vorliebe, sondern weil aller vorhandene Bestand (SavedVariables, laufende
-- Clients) bereits so verschluesselt ist: Deutsche Daten brauchen damit keine
-- Wanderung, nur englische werden zugeordnet.
--
-- "window" ist der Zauber, der das Berufsfenster oeffnet, wo er vom
-- Berufsnamen abweicht (Bergbau öffnet "Schmelzen"). Er zaehlt zugleich als
-- Alias: Der Scan liest den FENSTERnamen, gespeichert wird der Beruf.
GC.ProfessionDefinitions = {
    { key = "alchimie", name = "Alchimie", english = "Alchemy", aliases = { "Alchemie" } },
    { key = "bergbau", name = "Bergbau", english = "Mining",
        window = "Schmelzen", windowEnglish = "Smelting" },
    { key = "erstehilfe", name = "Erste Hilfe", english = "First Aid" },
    { key = "ingenieurskunst", name = "Ingenieurskunst", english = "Engineering" },
    { key = "juwelenschleifen", name = "Juwelenschleifen", english = "Jewelcrafting" },
    { key = "kochkunst", name = "Kochkunst", english = "Cooking" },
    { key = "krauterkunde", name = "Kräuterkunde", english = "Herbalism" },
    { key = "kurschnerei", name = "Kürschnerei", english = "Skinning" },
    { key = "lederverarbeitung", name = "Lederverarbeitung", english = "Leatherworking" },
    { key = "schmiedekunst", name = "Schmiedekunst", english = "Blacksmithing" },
    { key = "schneiderei", name = "Schneiderei", english = "Tailoring" },
    { key = "verzauberkunst", name = "Verzauberkunst", english = "Enchanting" },
    { key = "angeln", name = "Angeln", english = "Fishing" },
    { key = "gifte", name = "Gifte", english = "Poisons" },
    { key = "tierausbildung", name = "Tierausbildung", english = "Beast Training" },
}

-- Dieselbe Faltung wie NormalizeKey in der Werkstatt: Beide MUESSEN gleich
-- falten, sonst zeigen Alias-Tabelle und Speicherschluessel aneinander vorbei.
local function FoldProfessionName(value)
    value = tostring(value or ""):match("^%s*(.-)%s*$") or ""
    value = value:lower()
    value = value:gsub("ä", "a"):gsub("ö", "o"):gsub("ü", "u"):gsub("ß", "ss")
    return (value:gsub("[^%w]", ""))
end

GC.ProfessionByKey = {}
GC.ProfessionKeyByAlias = {}
for _, definition in ipairs(GC.ProfessionDefinitions) do
    GC.ProfessionByKey[definition.key] = definition
    GC.ProfessionKeyByAlias[FoldProfessionName(definition.name)] = definition.key
    GC.ProfessionKeyByAlias[FoldProfessionName(definition.english)] = definition.key
    if definition.window then
        GC.ProfessionKeyByAlias[FoldProfessionName(definition.window)] = definition.key
    end
    if definition.windowEnglish then
        GC.ProfessionKeyByAlias[FoldProfessionName(definition.windowEnglish)] = definition.key
    end
    for _, alias in ipairs(definition.aliases or {}) do
        GC.ProfessionKeyByAlias[FoldProfessionName(alias)] = definition.key
    end
end

-- Beliebige Schreibweise -> kanonischer Schluessel. Unbekanntes faellt auf die
-- eigene Faltung zurueck und verhaelt sich damit wie bisher.
function GC.CanonicalProfessionKey(name)
    local folded = FoldProfessionName(name)
    return GC.ProfessionKeyByAlias[folded] or folded
end

-- Beliebige Schreibweise -> deutscher Anzeigename, oder nil fuer Unbekanntes.
-- Das Addon ist deutschsprachig; auch Daten englischer Clients erscheinen
-- deshalb unter dem deutschen Namen.
function GC.CanonicalProfessionName(name)
    local definition = GC.ProfessionByKey[GC.CanonicalProfessionKey(name)]
    return definition and definition.name or nil
end

function GC.ProfessionEnglishName(name)
    local definition = GC.ProfessionByKey[GC.CanonicalProfessionKey(name)]
    return definition and definition.english or nil
end

-- Kandidaten fuer den Fensterzauber, deutsch zuerst. Der Aufrufer nimmt den
-- ersten, den der Client tatsaechlich kennt - auf einem englischen Client ist
-- das der zweite, denn CastSpellByName versteht nur die Clientsprache.
function GC.ProfessionWindowSpellCandidates(name)
    local definition = GC.ProfessionByKey[GC.CanonicalProfessionKey(name)]
    if not definition then
        return { tostring(name or "") }
    end
    return {
        definition.window or definition.name,
        definition.windowEnglish or definition.english,
    }
end

GC.ProfessionIcons = {
    [""] = "Interface\\Icons\\INV_Misc_Book_09",
    ["Alchimie"] = "Interface\\Icons\\Trade_Alchemy",
    ["Alchemie"] = "Interface\\Icons\\Trade_Alchemy",
    ["Bergbau"] = "Interface\\Icons\\Trade_Mining",
    ["Ingenieurskunst"] = "Interface\\Icons\\Trade_Engineering",
    ["Juwelenschleifen"] = "Interface\\Icons\\INV_Misc_Gem_01",
    ["Kräuterkunde"] = "Interface\\Icons\\Spell_Nature_NatureTouchGrow",
    ["Kürschnerei"] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    ["Lederverarbeitung"] = "Interface\\Icons\\Trade_LeatherWorking",
    ["Schmiedekunst"] = "Interface\\Icons\\Trade_BlackSmithing",
    ["Schneiderei"] = "Interface\\Icons\\Trade_Tailoring",
    ["Verzauberkunst"] = "Interface\\Icons\\Trade_Engraving",
    ["Kochkunst"] = "Interface\\Icons\\INV_Misc_Food_15",
    ["Erste Hilfe"] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
}

-- Sammelberufe ohne Rezeptfenster: Dort gibt es nichts einzulesen, und die
-- Einrichtung darf sie nicht anmahnen - ein Schritt, der nie erfuellbar ist,
-- stuende sonst auf ewig offen. Die Liste steht hier und nicht doppelt in
-- Werkstatt und Einrichtung; zwei Listen liefen auseinander (Lektion aus
-- 0.9.47, dort waren es die Chatbefehle).
GC.RecipelessProfessions = {
    ["Kräuterkunde"] = true,
    ["Kürschnerei"] = true,
}

-- Der Zauber, der das Berufsfenster oeffnet, steht bei den
-- ProfessionDefinitions oben ("window"/"windowEnglish"); die Knoepfe des
-- Einrichtungsassistenten holen ihn ueber ProfessionWindowSpellCandidates.

GC.SuccessSoundOptions = {
    { key = "READY_CHECK", name = "Bereitschaftscheck", soundID = 8960 },
    { key = "GROUP_FINDER", name = "Gruppensuche", soundID = 3081 },
    { key = "RAID_WARNING", name = "Raidwarnung", soundID = 8959 },
    { key = "IG_QUEST_LIST_COMPLETE", name = "Quest abgeschlossen", soundID = 619 },
    -- Der kurze Quest-Annahme-Klang; fehlt der Schluessel im SOUNDKIT der
    -- Spielfassung, greift die nackte Zahl.
    { key = "IG_QUEST_ACTIVATE", name = "Quest angenommen", soundID = 618 },
    { key = "MAP_PING", name = "Karten-Ping", soundID = 3175 },
    -- SoundKit 888 heisst in Classic "LEVELUP". Der Schluessel steht wie bei
    -- den anderen Eintraegen zuerst; fehlt er im SOUNDKIT der Spielfassung,
    -- greift die nackte Zahl.
    { key = "LEVEL_UP", name = "Stufenaufstieg", soundID = 888 },
}

-- Vorgabe fuer die eigene Profilbestaetigung. Bewusst ein anderer Ton als der
-- Bewerberklang: Der eine meldet einen fremden Interessenten, der andere
-- bestaetigt die eigene Eingabe.
GC.DefaultProfileSoundKey = "LEVEL_UP"

-- Woran ein Bewerber erkannt wird. Beide Listen sind Vorgaben und in den
-- Einstellungen ueberschreibbar; sie stehen hier, damit ein geleertes
-- Eingabefeld wieder auf diesen Stand zurueckfaellt.
--
-- Oeffentliche Chatnachrichten und Fluesternachrichten bleiben absichtlich
-- getrennt: Ein zu weiter Whisper-Trigger nervt nur einen selbst, ein zu
-- weiter Chat-Trigger erzeugt Muell aus dem ganzen Realm. Deshalb ist die
-- oeffentliche Liste eng und aus ganzen Wendungen gebaut, die Whisper-Liste
-- darf einzelne Woerter enthalten.
GC.DefaultChatTriggers = {
    "suche eine gilde",
    "suche gilde",
    "gilde gesucht",
    "gildensuche",
    "lf guild",
    "looking for a guild",
    "looking for guild",
}

GC.DefaultWhisperTriggers = {
    "interesse",
    "interessiert",
    "gilde",
    "guild",
    "bewerb",
    "rekrut",
    "raidplatz",
    "raid platz",
    "mehr info",
    "mehr infos",
    "discord",
    "sucht ihr",
    "mitmachen",
    "anschließen",
    "anschliessen",
}

-- Ausschlusswoerter haben bewusst keine Vorgabe: Was Muell ist, weiss nur der
-- eigene Realm. Eine mitgelieferte Liste wuerde Eintraege verhindern, die
-- jemand anders ausdruecklich haben will.
GC.MaxRecruitmentFilterWords = 40

-- === Klasse und Stufe aus der Nachricht lesen =============================
--
-- Ein Bewerber schreibt fast immer selbst hin, was er spielt: "ENH sucht
-- Anschluss an Gilde", "70er Schurke sucht nette Gilde", "ich spiele ein
-- Hexenmeister". Das ist die einzige Quelle, die ohne Serveranfrage
-- auskommt - die Spieler-GUID liefert die Klasse nur, wenn der Client den
-- Namen kennt, und die STUFE liefert sie ueberhaupt nicht.
--
-- Verglichen wird auf ganze Woerter (%f-Grenzmuster). Ohne das findet "ele"
-- auch "elegant" und "war" jedes "warum" - Kuerzel sind hier unvermeidlich,
-- weil im Kanal so geschrieben wird.
--
-- Nicht aufgenommen sind mehrdeutige Kuerzel: "resto" (Schamane ODER Druide),
-- "prot" (Krieger ODER Paladin), "heal", "dd", "tank". Lieber keine Angabe als
-- eine falsche - eine falsche Klasse verbirgt den Bewerber hinter einem Filter,
-- unter dem niemand ihn sucht.
GC.LeadClassAliases = {
    WARRIOR = { "krieger", "warri", "warrior", "fury", "arms" },
    PALADIN = { "paladin", "pala", "pally", "vergelter", "retri" },
    HUNTER  = { "jäger", "jaeger", "hunter", "hunt", "hunni" },
    ROGUE   = { "schurke", "rogue", "assa" },
    PRIEST  = { "priester", "priest", "disci", "disco", "schatten", "shadow" },
    SHAMAN  = { "schamane", "schami", "shaman", "sham", "enh", "enha", "enhancer",
                "elementar", "ele" },
    MAGE    = { "magier", "mage", "arkan", "arcane" },
    WARLOCK = { "hexenmeister", "hexer", "warlock", "lock", "wl", "affli", "destro" },
    DRUID   = { "druide", "dudu", "druid", "eule", "boomkin", "moonkin", "feral" },
}

-- Ganze Zahlen und Wortgrenzen: weder "Itemlevel 70" noch "Level 700" sind
-- Stufe 70. Ohne Marker muss die Zahl direkt an einer Klassenangabe stehen.
GC.LeadLevelPatterns = {
    "%f[%a]stufe%s*[:%-]?%s*(%d+)%f[%W]",
    "%f[%a]level%s*[:%-]?%s*(%d+)%f[%W]",
    "%f[%a]lvl%.?%s*[:%-]?%s*(%d+)%f[%W]",
    "%f[%a]lv%.?%s*[:%-]?%s*(%d+)%f[%W]",
    "%f[%w](%d+)%s*er%f[%W]",
}
GC.LeadLevelMax = 70

-- === Freie Formulierungen erkennen ========================================
--
-- Die Wendungsliste oben ist genau und deshalb eng. Sie kennt "suche Gilde",
-- aber nicht "ENH sucht Anschluss an Gilde zum Raiden" - und genau so schreibt
-- der halbe Kanal. Jede fehlende Wendung von Hand nachzutragen ist ein Spiel
-- ohne Ende: "sucht Gilde", "sucht eine Gilde", "sucht raidende Gilde", "suche
-- Anschluss an eine Gilde", ...
--
-- Der naheliegende Ausweg - einfach "gilde" als Trigger - ist gemessen der
-- schlechteste: Von fuenf typischen Gildenwerbungen im Kanal landen VIER im
-- Postfach. Das sind Konkurrenten, keine Bewerber, und sie kommen im Minutentakt.
--
-- Was beide Faelle zuverlaessig trennt, ist nicht die Wortwahl, sondern die
-- REIHENFOLGE:
--
--     Bewerber nennt zuerst sich:   "ENH  sucht  Anschluss an  GILDE"
--     Gilde wirbt, nennt sich zuerst: "GILDE  sucht  noch aktive Raider"
--
-- Steht das Suchwort VOR dem Gildenwort, sucht jemand eine Gilde. Steht das
-- Gildenwort davor, sucht eine Gilde jemanden. Das ist im Deutschen wie im
-- Englischen stabil und braucht keine einzige neue Wendung.
GC.GuildSeekerGuildWords = {
    "gilde",
    "guild",
}

-- Suchwoerter, bei denen die Reihenfolge zaehlt. Kurzformen genuegen, weil
-- verglichen wird, ob sie IRGENDWO vorkommen: "suche" steckt auch in "suchen",
-- "sucht" auch in "gesucht" - Letzteres ist Absicht, siehe unten.
GC.GuildSeekerSeekWords = {
    "suche",
    "sucht",
    "lfg",
    "lf ",
    "looking for",
}

-- Woerter, die den Bewerber unabhaengig von der Reihenfolge verraten.
--
-- Noetig wegen der deutschen Verbstellung: In "moechte einer GILDE BEITRETEN"
-- steht das Verb hinter dem Objekt, die Reihenfolgeregel wuerde daraus eine
-- Werbung machen. Diese Woerter benutzt umgekehrt keine werbende Gilde ueber
-- sich selbst - "wir suchen Anschluss" sagt niemand. Das werbende "Tritt uns
-- bei!" faengt weiterhin die Merkmalsliste unten ab.
GC.GuildSeekerJoinWords = {
    "anschluss",
    "beitreten",
    "aufnahme",
    "aufgenommen",
}

-- Merkmale, die eine Gildenwerbung auch dann verraten, wenn die Reihenfolge
-- nach Bewerber aussieht - etwa "<Aftermath> sucht dich! Wir sind eine Gilde
-- fuer Raider". Sie schlagen die Reihenfolge.
--
-- Aufgenommen wird nur, was EINDEUTIG ist. "sucht noch" steht bewusst NICHT
-- hier: "ENH sucht noch eine Gilde" waere damit verloren.
GC.GuildSeekerAdMarkers = {
    -- "unsere Gilde" sagt nur, wer selbst darin ist. Faengt unter anderem
    -- "Raider fuer unsere Gilde gesucht" ab, das sonst ueber die Vorgabe-
    -- wendung "gilde gesucht" hereinkaeme.
    "unsere gilde",
    "unserer gilde",
    "our guild",
    "sucht dich",
    "sucht euch",
    "suchen dich",
    "suchen euch",
    "wir suchen",
    "wir sind eine",
    "verstärkung",
    "verstaerkung",
    "meldet euch",
    "bewerbt",
    "rekrutier",
    "neue mitglieder",
    "mitglieder gesucht",
    "member gesucht",
    "tritt uns bei",
    "werde teil",
    "we are recruiting",
    "is recruiting",
}

-- Verbrauchsgegenstände werden nach Spell-ID gezählt. Gezählt wird der
-- VERBRAUCH, nicht der Besitz: Wer dreimal Buffood isst, steht mit drei
-- Essen da, wer zwei Fläschchen leert, mit zwei.
--
-- "track" entscheidet, welches Kampfereignis zählt - und daran hing der
-- größte Teil der falschen Zahlen:
--
--   CAST  Der Gegenstand wird benutzt und erzeugt ein Wirkereignis beim
--         Benutzer. Nur das zählt, der daraus entstehende Buff wird
--         ignoriert. Sonst bekäme jedes Gruppenmitglied eine Trommel
--         gutgeschrieben, die der Trommler geworfen hat, und ein Hasttrank
--         zählte doppelt (einmal als Zauber, einmal als eigene Aura).
--   AURA  Der Gegenstand erzeugt gar kein Wirkereignis, nur eine Aura beim
--         Beschenkten. Das trifft auf "Sattgegessen" zu: Gegessen wird,
--         der Buff erscheint Sekunden später, einen Zauber gibt es nie.
--
-- "scan" markiert die dauerhaften Buffs, die zu Sitzungsbeginn - und wenn
-- jemand später dazustößt - einmal von den Anwesenden abgelesen werden.
-- Fläschchen, Elixiere und Essen kommen vor dem Raid auf den Charakter, oft
-- lange vor dem ersten Pull. Ohne diese Momentaufnahme steht dort dauerhaft
-- eine Null, obwohl der Raid vollständig gebufft antritt.
GC.ConsumableCategories = {
    { key = "POTION", label = "Tränke", track = "CAST" },
    { key = "RUNE", label = "Runen", track = "CAST" },
    { key = "DRUM", label = "Trommeln", track = "CAST" },
    { key = "FLASK", label = "Fläschchen", track = "CAST", scan = true },
    { key = "ELIXIR", label = "Elixiere", track = "CAST", scan = true },
    { key = "FOOD", label = "Essen", track = "AURA", scan = true },
    { key = "OIL", label = "Öle/Steine", track = "CAST" },
}

GC.ConsumableCategoryByKey = {}
for index, category in ipairs(GC.ConsumableCategories) do
    category.index = index
    GC.ConsumableCategoryByKey[category.key] = category
end

-- Ausgangsbestand gebräuchlicher TBC-Verbrauchsgegenstände. Die Liste ist
-- bewusst erweiterbar gehalten: unbekannte Spell-IDs werden schlicht nicht
-- gezählt, es entstehen also keine falschen Zahlen, sondern nur unvollständige.
-- Vor dem Scharfschalten gegen echte Logs abgleichen.
--
-- ZWEI Sprachen, ZWEI Quellen - und beide sind belegt, nichts ist frei
-- uebersetzt (Owner-Vorgabe vom 08.08.2026):
--
--   name    Deutsch, direkt am deutschen Anniversary-Client abgelesen
--           (Owner-Korrekturen: "Super" heisst dort "Erstklassig", die
--           Major-Elixiere "uebermaechtig", die Superior-Öle "Hervorragend").
--           Wowheads deutsche Locale weicht davon teils ab ("Ueberragendes
--           Zauberoel", "Elixier der erheblichen Staerke") - der Client hat
--           das letzte Wort.
--   nameEN  Englisch, am 08.08.2026 einzeln ueber die Item-ID gegen
--           Wowheads TBC-Datenbank verifiziert (nether.wowhead.com/tooltip/
--           item/<id>?dataEnv=5&locale=0); die Item-ID steht als Kommentar
--           am Eintrag. Die vier Salben/Nethergon-Flaschen sind zusaetzlich
--           ueber die "Used by"-Daten ihrer Spell-Seiten belegt (Items
--           32902-32905). Die Sattgegessen-Zeilen unten tragen den
--           offiziellen Buffnamen "Well Fed" von ihren Spell-Tooltips;
--           nur der Werte-Zusatz in Klammern ist wie im Deutschen eine
--           eigene Beschriftung aus dem jeweiligen Bufftext.
GC.Consumables = {
    [28495] = { category = "POTION", name = "Erstklassiger Heiltrank", nameEN = "Super Healing Potion" },      -- Item 22829
    [28499] = { category = "POTION", name = "Erstklassiger Manatrank", nameEN = "Super Mana Potion" },         -- Item 22832
    [28507] = { category = "POTION", name = "Hasttrank", nameEN = "Haste Potion" },                            -- Item 22838
    [28508] = { category = "POTION", name = "Zerstörungstrank", nameEN = "Destruction Potion" },               -- Item 22839
    [28494] = { category = "POTION", name = "Trank der irren Stärke", nameEN = "Insane Strength Potion" },     -- Item 22828
    [28506] = { category = "POTION", name = "Heldentrank", nameEN = "Heroic Potion" },                         -- Item 22837
    -- 28511 und 28512 trugen bis 0.9.86 die Namen "Heldentrank" und
    -- "Eisenschildtrank". Beide waren falsch: es sind die Schutztränke, und
    -- der echte Heldentrank (28506) fehlte deshalb ganz.
    [28511] = { category = "POTION", name = "Großer Feuerschutztrank", nameEN = "Major Fire Protection Potion" },   -- Item 22841
    [28512] = { category = "POTION", name = "Großer Frostschutztrank", nameEN = "Major Frost Protection Potion" },  -- Item 22842
    [38908] = { category = "POTION", name = "Teufelsmanatrank", nameEN = "Fel Mana Potion" },                  -- Item 31677
    -- Die Salben und Flaschen aus Zangarmarschen und Netherstrum. Sie sind in
    -- TBC der meistbenutzte Manatrank überhaupt und fehlten bis 0.9.86
    -- komplett - im Vergleichslog vom 02.08.2026 kamen allein auf sie 146
    -- Anwendungen, während die Spalte "Tränke" bei den Betroffenen auf null
    -- stand. Die deutschen Namen sind bewusst beschreibende Etiketten
    -- ("Manatrank (...)"); die englischen sind die echten Itemnamen.
    [41617] = { category = "POTION", name = "Manatrank (Cenarische Salbe)", nameEN = "Cenarion Mana Salve" },       -- Item 32903
    [41618] = { category = "POTION", name = "Manatrank (Nethergonenergie)", nameEN = "Bottled Nethergon Energy" }, -- Item 32902
    [41619] = { category = "POTION", name = "Heiltrank (Cenarische Salbe)", nameEN = "Cenarion Healing Salve" },   -- Item 32904
    [41620] = { category = "POTION", name = "Heiltrank (Nethergondampf)", nameEN = "Bottled Nethergon Vapor" },    -- Item 32905
    [16666] = { category = "RUNE", name = "Dämonische Rune", nameEN = "Demonic Rune" },                        -- Item 12662
    [27869] = { category = "RUNE", name = "Dunkle Rune", nameEN = "Dark Rune" },                               -- Item 20520
    [35476] = { category = "DRUM", name = "Trommeln der Schlacht", nameEN = "Drums of Battle" },               -- Item 29529
    [35475] = { category = "DRUM", name = "Trommeln des Krieges", nameEN = "Drums of War" },                   -- Item 29528
    [35478] = { category = "DRUM", name = "Trommeln der Wiederherstellung", nameEN = "Drums of Restoration" }, -- Item 29531
    [35477] = { category = "DRUM", name = "Trommeln der Schnelligkeit", nameEN = "Drums of Speed" },           -- Item 29530
    [35474] = { category = "DRUM", name = "Trommeln der Panik", nameEN = "Drums of Panic" },                   -- Item 29532
    [28518] = { category = "FLASK", name = "Fläschchen der Festigung", nameEN = "Flask of Fortification" },    -- Item 22851
    [28519] = { category = "FLASK", name = "Fläschchen der mächtigen Wiederherstellung", nameEN = "Flask of Mighty Restoration" }, -- Item 22853
    [28520] = { category = "FLASK", name = "Fläschchen des unerbittlichen Angriffs", nameEN = "Flask of Relentless Assault" },     -- Item 22854
    [28521] = { category = "FLASK", name = "Fläschchen des blendenden Lichts", nameEN = "Flask of Blinding Light" },               -- Item 22861
    [28540] = { category = "FLASK", name = "Fläschchen des reinen Todes", nameEN = "Flask of Pure Death" },    -- Item 22866
    -- Classic-Fläschchen, in TBC weiter benutzt - und bis 0.9.114 unbekannt.
    -- Aufgefallen am Abend des 09.08.2026: Ein Heiler stand als Einziger von
    -- 25 ohne Fläschchen in der Auswertung. Beleg ist das Kampflog desselben
    -- Abends, das ihn zweimal trinken sah:
    --   SPELL_CAST_SUCCESS ... 17627,"Destillierte Weisheit"
    --   SPELL_AURA_APPLIED ... 17627,"Destillierte Weisheit",0x1,BUFF
    -- Der Zaubername stammt damit aus dem Spielclient selbst.
    [17627] = { category = "FLASK", name = "Fläschchen der destillierten Weisheit",
        nameEN = "Flask of Distilled Wisdom" },                                                                -- Item 13511
    -- Zwei weitere Kennungen aus demselben Kampflog. Gefunden wurden sie ueber
    -- eine Signatur, die kein Klassenzauber haben kann: gewirkt von Spielern
    -- MEHRERER KLASSEN und dabei sich selbst buffend - das kann nur etwas aus
    -- der Tasche sein. Die Kategorie folgt der gemessenen Wirkdauer.
    [17538] = { category = "ELIXIR", name = "Elixier des Mungos",
        nameEN = "Elixir of the Mongoose" },     -- Item 13452, gemessen 63 Min
    [28515] = { category = "POTION", name = "Eisenschildtrank",
        nameEN = "Ironshield Potion" },          -- Item 22849, gemessen 2 Min
    [28490] = { category = "ELIXIR", name = "Elixier der übermächtigen Stärke", nameEN = "Elixir of Major Strength" },        -- Item 22824
    [28497] = { category = "ELIXIR", name = "Elixier der übermächtigen Beweglichkeit", nameEN = "Elixir of Major Agility" },  -- Item 22831
    [28491] = { category = "ELIXIR", name = "Elixier der Heilkraft", nameEN = "Elixir of Healing Power" },     -- Item 22825
    [28493] = { category = "ELIXIR", name = "Elixier der übermächtigen Frostmacht", nameEN = "Elixir of Major Frost Power" }, -- Item 22827
    [28501] = { category = "ELIXIR", name = "Elixier der übermächtigen Feuermacht", nameEN = "Elixir of Major Firepower" },   -- Item 22833
    [28502] = { category = "ELIXIR", name = "Elixier der übermächtigen Verteidigung", nameEN = "Elixir of Major Defense" },   -- Item 22834
    [28503] = { category = "ELIXIR", name = "Elixier der übermächtigen Schattenmacht", nameEN = "Elixir of Major Shadow Power" }, -- Item 22835
    [28509] = { category = "ELIXIR", name = "Elixier des übermächtigen Magierbluts", nameEN = "Elixir of Major Mageblood" },  -- Item 22840
    [39625] = { category = "ELIXIR", name = "Elixier der übermächtigen Seelenstärke", nameEN = "Elixir of Major Fortitude" }, -- Item 32062
    [39627] = { category = "ELIXIR", name = "Elixier der draenischen Weisheit", nameEN = "Elixir of Draenic Wisdom" },        -- Item 32067
    -- Aus dem Vergleichslog vom 02.08.2026 nachgetragen: drei gebräuchliche
    -- Elixiere, die die Liste nicht kannte.
    [17539] = { category = "ELIXIR", name = "Großes Arkanelixier", nameEN = "Greater Arcane Elixir" },         -- Item 13454
    [33720] = { category = "ELIXIR", name = "Elixier des Ansturms", nameEN = "Onslaught Elixir" },             -- Item 28102
    [33721] = { category = "ELIXIR", name = "Elixier des Adepten", nameEN = "Adept's Elixir" },                -- Item 28103
    -- Der deutsche Client nennt die "Superior"-Öle "Hervorragend"
    -- (Owner-Korrektur vom 08.08.2026, direkt am Client abgelesen).
    [28017] = { category = "OIL", name = "Hervorragendes Zauberöl", nameEN = "Superior Wizard Oil" },          -- Item 22522
    [28019] = { category = "OIL", name = "Hervorragendes Manaöl", nameEN = "Superior Mana Oil" },              -- Item 22521

    -- === Essen ==============================================================
    --
    -- Alle Sattgegessen-Buffs heissen im Spiel gleich, tragen aber je Gericht
    -- eine eigene Spell-ID. Live erkennt das Addon sie deshalb zusaetzlich am
    -- Auranamen ("Sattgegessen"/"Well Fed"); aus Warcraft Logs kommen nur IDs,
    -- und ohne diese Liste blieb Essen dort dauerhaft bei null.
    --
    -- Aufgenommen sind nur Buffs, die wirklich Werte geben. Bewusst draussen:
    -- die "Food"-Auren (blosse Lebensregeneration waehrend des Essens, z. B.
    -- 33258, 33262, 33264, 33266), die reine Regenerationsvariante 33269 und
    -- das Tierfutter 33272 (+10 Zufriedenheit) - letzteres beglueckt das
    -- Jaegertier, nicht den Raidteilnehmer.
    [33254] = { category = "FOOD", name = "Sattgegessen (+20 Ausdauer)", nameEN = "Well Fed (+20 Stamina)" },
    [33256] = { category = "FOOD", name = "Sattgegessen (+20 Stärke)", nameEN = "Well Fed (+20 Strength)" },
    [33257] = { category = "FOOD", name = "Sattgegessen (+30 Ausdauer)", nameEN = "Well Fed (+30 Stamina)" },
    [33259] = { category = "FOOD", name = "Sattgegessen (+40 Angriffskraft)", nameEN = "Well Fed (+40 Attack Power)" },
    [33261] = { category = "FOOD", name = "Sattgegessen (+20 Beweglichkeit)", nameEN = "Well Fed (+20 Agility)" },
    [33263] = { category = "FOOD", name = "Sattgegessen (+23 Zaubermacht)", nameEN = "Well Fed (+23 Spell Damage)" },
    [33265] = { category = "FOOD", name = "Sattgegessen (+20 Ausdauer, +8 Mana/5s)", nameEN = "Well Fed (+20 Stamina, +8 mana/5s)" },
    [33268] = { category = "FOOD", name = "Sattgegessen (+44 Heilung)", nameEN = "Well Fed (+44 Healing)" },
    [43764] = { category = "FOOD", name = "Sattgegessen (+20 Trefferwertung)", nameEN = "Well Fed (+20 Hit Rating)" },
    [45245] = { category = "FOOD", name = "Sattgegessen (+20 Ausdauer, +20 Willenskraft)", nameEN = "Well Fed (+20 Stamina, +20 Spirit)" },
}

-- Der Anzeigename eines Verbrauchsgegenstands in der Clientsprache. Die
-- englischen Namen sind einzeln belegt (siehe Tabellenkopf); fehlt einer,
-- bleibt es sichtbar beim deutschen statt bei einer freien Uebersetzung.
function GC.ConsumableDisplayName(consumable)
    if type(consumable) ~= "table" then
        return nil
    end
    if GC.LocaleEnglish and type(consumable.nameEN) == "string" and consumable.nameEN ~= "" then
        return consumable.nameEN
    end
    return consumable.name
end

-- Öle und Wetzsteine sitzen als TEMPORAERE VERZAUBERUNG auf der Waffe, nicht
-- als Aura auf dem Spieler. Der Eintritts-Scan der Raidsitzung liest Auren -
-- ein vor dem Sitzungsstart aufgetragenes Öl war damit unsichtbar, und die
-- Spalte "Öle/Steine" stand auf null, obwohl das Öl nachweislich drauf war.
--
-- Lesbar ist nur die EIGENE Waffe (GetWeaponEnchantInfo gilt ausschliesslich
-- fuer "player"); erkannt wird die Verzauberungszeile des Waffentooltips.
-- Gezaehlt wird NUR bei einem Treffer dieser Muster: Windzorn und
-- Flammenzunge (Schamane) und die Gifte (Schurke) sind ebenfalls temporaere
-- Verzauberungen und ausdruecklich keine Verbrauchsgegenstaende - geraten
-- wird nichts, ein Nichttreffer zaehlt schlicht nicht. Beide Sprachfassungen,
-- verglichen als Teilzeichenkette.
GC.WeaponOilPatterns = {
    "Zauberöl", "Wizard Oil",
    "Manaöl", "Mana Oil",
    "Wetzstein", "Sharpening Stone",
    "Gewichtsstein", "Weightstone",
}

-- Bosse der TBC-Schlachtzuege.
--
-- Wozu: Ohne Encounter-API benennt der Raidmonitor einen Kampfabschnitt nach
-- dem zuletzt gestorbenen Gegner. Bei einem Wipe stirbt der Boss aber gerade
-- nicht - der Versuch hiess dann "Kampf" oder trug den Namen eines Adds.
-- Genau die Wipes sind aber das, was man hinterher ansehen will.
--
-- Erkannt wird ueber den **Eigennamen**, nicht ueber den vollen Titel: "Prinz
-- Malchezaar" und "Prince Malchezaar" enthalten beide "Malchezaar". Damit
-- funktioniert die Liste auf einem deutschen wie auf einem englischen Client,
-- ohne dass fuer jeden Boss eine belegte Uebersetzung noetig waere - die liess
-- sich naemlich nicht zuverlaessig beschaffen.
--
-- Wo ein Boss keinen Eigennamen hat (Der Kurator, Maid der Tugend), stehen
-- beide Sprachfassungen. Trifft nichts davon, bleibt es bei der bisherigen
-- Heuristik: Es geht nichts verloren, es wird nur nichts gewonnen.
GC.RaidBosses = {
    { instance = "Karazhan", names = { "Attumen", "Midnight" } },
    { instance = "Karazhan", names = { "Moroes" } },
    { instance = "Karazhan", names = { "Maid der Tugend", "Maiden of Virtue" } },
    { instance = "Karazhan", names = { "Dorothee", "Tito", "Roar", "Strohmann", "Strawman",
        "Tinhead", "Blechkopf", "Kruschik", "Der Große, Böse Wolf", "The Big Bad Wolf",
        "Romulo", "Julianne" } },
    { instance = "Karazhan", names = { "Der Kurator", "The Curator" } },
    { instance = "Karazhan", names = { "Terestian" } },
    { instance = "Karazhan", names = { "Aran" } },
    { instance = "Karazhan", names = { "Netherspite" } },
    { instance = "Karazhan", names = { "Malchezaar" } },
    { instance = "Karazhan", names = { "Nachtbann", "Nightbane" } },

    { instance = "Gruuls Unterschlupf", names = { "Maulgar" } },
    { instance = "Gruuls Unterschlupf", names = { "Gruul" } },

    { instance = "Magtheridons Kammer", names = { "Magtheridon" } },

    { instance = "Serpentinhöhle", names = { "Hydross" } },
    { instance = "Serpentinhöhle", names = { "Lurker", "Lauerer" } },
    { instance = "Serpentinhöhle", names = { "Leotheras" } },
    { instance = "Serpentinhöhle", names = { "Karathress" } },
    { instance = "Serpentinhöhle", names = { "Morogrim" } },
    { instance = "Serpentinhöhle", names = { "Vashj" } },

    { instance = "Auge", names = { "Al'ar" } },
    { instance = "Auge", names = { "Solarian" } },
    { instance = "Auge", names = { "Void Reaver", "Leerenschinder" } },
    { instance = "Auge", names = { "Kael'thas" } },

    { instance = "Zul'Aman", names = { "Nalorakk" } },
    { instance = "Zul'Aman", names = { "Akil'zon" } },
    { instance = "Zul'Aman", names = { "Jan'alai" } },
    { instance = "Zul'Aman", names = { "Halazzi" } },
    { instance = "Zul'Aman", names = { "Malacrass" } },
    { instance = "Zul'Aman", names = { "Zul'jin" } },

    { instance = "Hyjal", names = { "Winterchill" } },
    { instance = "Hyjal", names = { "Anetheron" } },
    { instance = "Hyjal", names = { "Kaz'rogal" } },
    { instance = "Hyjal", names = { "Azgalor" } },
    { instance = "Hyjal", names = { "Archimonde" } },

    { instance = "Schwarzer Tempel", names = { "Naj'entus" } },
    { instance = "Schwarzer Tempel", names = { "Supremus" } },
    { instance = "Schwarzer Tempel", names = { "Akama" } },
    { instance = "Schwarzer Tempel", names = { "Teron" } },
    { instance = "Schwarzer Tempel", names = { "Gurtogg" } },
    { instance = "Schwarzer Tempel", names = { "Reliquiar der Seelen", "Reliquary of Souls" } },
    { instance = "Schwarzer Tempel", names = { "Shahraz" } },
    { instance = "Schwarzer Tempel", names = { "Illidari", "Veras", "Zerevor", "Malande", "Gathios" } },
    { instance = "Schwarzer Tempel", names = { "Illidan" } },

    { instance = "Sonnenbrunnen", names = { "Kalecgos", "Sathrovarr" } },
    { instance = "Sonnenbrunnen", names = { "Sacrolash", "Alythess" } },
    { instance = "Sonnenbrunnen", names = { "Felmyst" } },
    { instance = "Sonnenbrunnen", names = { "Muru", "Entropius" } },
    { instance = "Sonnenbrunnen", names = { "Kil'jaeden" } },
}

-- Die Schlachtzüge des Anniversary-Clients für die Raidsuche. "name" entspricht
-- der Zone, die die Raidauswertung aus GC.RaidBosses ableitet - Suche und
-- Auswertung sprechen damit dieselben Namen. "short" ist der Kurzname für die
-- knappen Längenstufen des Suchspruchs, "size" die übliche Gruppengröße als
-- Vorbelegung (per Regler überschreibbar, damit auch 5er-Gruppen gehen).
GC.RaidInstances = {
    { name = "Karazhan", short = "Kara", size = 10 },
    { name = "Gruuls Unterschlupf", short = "Gruul", size = 25 },
    { name = "Magtheridons Kammer", short = "Maggi", size = 25 },
    { name = "Serpentinhöhle", short = "SSC", size = 25 },
    { name = "Auge", short = "TK", size = 25 },
    { name = "Zul'Aman", short = "ZA", size = 10 },
    { name = "Hyjal", short = "MH", size = 25 },
    { name = "Schwarzer Tempel", short = "BT", size = 25 },
    { name = "Sonnenbrunnen", short = "SWP", size = 25 },
}

-- Ausrüstungsslots für den Gear Audit. "enchantRequired" markiert nur Slots,
-- die in TBC jede Raidklasse verzaubern kann. Ringe (nur Verzauberer),
-- Schildhand (nur Schilde) und Distanz (nur Schusswaffen) sind bewusst nicht
-- eingefordert, damit keine falschen Fehlmeldungen entstehen.
GC.GearSlots = {
    { id = 1, key = "HEAD", label = "Kopf", enchantRequired = true },
    { id = 2, key = "NECK", label = "Hals" },
    { id = 3, key = "SHOULDER", label = "Schulter", enchantRequired = true },
    { id = 5, key = "CHEST", label = "Brust", enchantRequired = true },
    { id = 6, key = "WAIST", label = "Gürtel" },
    { id = 7, key = "LEGS", label = "Beine", enchantRequired = true },
    { id = 8, key = "FEET", label = "Füße", enchantRequired = true },
    { id = 9, key = "WRIST", label = "Handgelenke", enchantRequired = true },
    { id = 10, key = "HANDS", label = "Hände", enchantRequired = true },
    { id = 11, key = "FINGER1", label = "Ring 1" },
    { id = 12, key = "FINGER2", label = "Ring 2" },
    { id = 13, key = "TRINKET1", label = "Schmuck 1" },
    { id = 14, key = "TRINKET2", label = "Schmuck 2" },
    { id = 15, key = "BACK", label = "Rücken", enchantRequired = true },
    { id = 16, key = "MAINHAND", label = "Waffenhand", enchantRequired = true },
    { id = 17, key = "OFFHAND", label = "Schildhand" },
    { id = 18, key = "RANGED", label = "Distanz" },
}

GC.GearVerdicts = {
    OPTIMAL = { key = "OPTIMAL", label = "Optimal", order = 1 },
    SOLID = { key = "SOLID", label = "Solide", order = 2 },
    IMPROVABLE = { key = "IMPROVABLE", label = "Verbesserbar", order = 3 },
    MISSING = { key = "MISSING", label = "Fehlt", order = 4 },
    UNKNOWN = { key = "UNKNOWN", label = "Unbekannt", order = 5 },
    -- Ausdrueckliche Ausnahme: Farmgear, Widerstandsset oder ein besonderes
    -- Encounter-Set. Der Slot wird weiter angezeigt, zaehlt aber nicht als Fund.
    EXEMPT = { key = "EXEMPT", label = "Ausnahme", order = 6 },
}

-- Gruende, aus denen ein Slot von der Pruefung ausgenommen wird. Sie stehen
-- als Text im Tooltip, damit eine Ausnahme nachvollziehbar bleibt und nicht
-- wie ein stiller Trick wirkt.
GC.GearExemptionReasons = {
    { key = "FARM", label = "Farmgear", help = "Ausrüstung außerhalb des Raids." },
    { key = "RESIST", label = "Widerstandsset", help = "Widerstandsteil für einen bestimmten Kampf." },
    { key = "ENCOUNTER", label = "Encounter-Set", help = "Sonderausrüstung für einen Bosskampf." },
}

GC.GearExemptionReasonByKey = {}
for _, reason in ipairs(GC.GearExemptionReasons) do
    GC.GearExemptionReasonByKey[reason.key] = reason
end

-- Spielarchetypen für die Bewertung von Verzauberungen.
--
-- Die Rolle (TANK/HEALER/DAMAGER) ist dafür zu grob: Ein Schattenpriester und
-- ein Schurke sind beide DAMAGER, brauchen aber völlig andere Verzauberungen.
-- Der Archetyp trennt genau dort, wo sich die Empfehlungen unterscheiden.
--
-- Jäger stehen bewusst bei den physischen Damage-Dealern: Sie verzaubern ihre
-- Rüstung mit denselben Beweglichkeits- und Angriffskraftwerten wie Schurken.
GC.EnchantArchetypes = {
    CASTER_DPS = { key = "CASTER_DPS", label = "Zauber-Schaden" },
    HEALER = { key = "HEALER", label = "Heilung" },
    PHYSICAL_DPS = { key = "PHYSICAL_DPS", label = "Physischer Schaden" },
    TANK = { key = "TANK", label = "Tank" },
}

-- Welche Archetypen zu einer Spec gehören. Wildheit steht in beiden Listen,
-- weil derselbe Druide als Katze und als Bär spielt - eine Verzauberung, die
-- für einen von beiden taugt, ist für ihn deshalb nie "falsch".
GC.SpecArchetypes = {
    ["WARRIOR:1"] = { "PHYSICAL_DPS" },
    ["WARRIOR:2"] = { "PHYSICAL_DPS" },
    ["WARRIOR:3"] = { "TANK" },
    ["PALADIN:1"] = { "HEALER" },
    -- Schutz-Paladine verzaubern auf Zaubermacht, weil ihre Bedrohung daran
    -- haengt: Die BiS-Liste nennt Glyphe der Macht, Grosse Zaubermacht auf den
    -- Handschuhen und den Runenzauberfaden. Ohne den zweiten Archetyp wuerde
    -- der Audit genau die empfohlene Ausruestung nicht wiedererkennen.
    ["PALADIN:2"] = { "TANK", "CASTER_DPS" },
    ["PALADIN:3"] = { "PHYSICAL_DPS" },
    ["HUNTER:1"] = { "PHYSICAL_DPS" },
    ["HUNTER:2"] = { "PHYSICAL_DPS" },
    ["HUNTER:3"] = { "PHYSICAL_DPS" },
    ["ROGUE:1"] = { "PHYSICAL_DPS" },
    ["ROGUE:2"] = { "PHYSICAL_DPS" },
    ["ROGUE:3"] = { "PHYSICAL_DPS" },
    ["PRIEST:1"] = { "HEALER" },
    ["PRIEST:2"] = { "HEALER" },
    ["PRIEST:3"] = { "CASTER_DPS" },
    ["SHAMAN:1"] = { "CASTER_DPS" },
    ["SHAMAN:2"] = { "PHYSICAL_DPS" },
    ["SHAMAN:3"] = { "HEALER" },
    ["MAGE:1"] = { "CASTER_DPS" },
    ["MAGE:2"] = { "CASTER_DPS" },
    ["MAGE:3"] = { "CASTER_DPS" },
    ["WARLOCK:1"] = { "CASTER_DPS" },
    ["WARLOCK:2"] = { "CASTER_DPS" },
    ["WARLOCK:3"] = { "CASTER_DPS" },
    ["DRUID:1"] = { "CASTER_DPS" },
    ["DRUID:2"] = { "PHYSICAL_DPS", "TANK" },
    ["DRUID:3"] = { "HEALER" },
}

-- Content-Phasen von TBC. Der Regelsatz nennt je Regel die Phase, ab der eine
-- Verzauberung überhaupt zu haben ist; die Gilde stellt ihre laufende Phase in
-- den Einstellungen ein. Eine Verzauberung aus einer späteren Phase wird
-- deshalb nie eingefordert, solange die Gilde noch nicht so weit ist.
GC.ContentPhases = {
    { key = "T4", label = "T4 – Karazhan, Gruul, Magtheridon", order = 1 },
    { key = "T5", label = "T5 – Serpentinhöhle, Auge", order = 2 },
    { key = "T6", label = "T6 – Hyjal, Schwarzer Tempel", order = 3 },
    { key = "T6.5", label = "T6.5 – Sonnenbrunnen", order = 4 },
}

GC.ContentPhaseByKey = {}
for _, phase in ipairs(GC.ContentPhases) do
    GC.ContentPhaseByKey[phase.key] = phase
end

GC.DefaultContentPhase = "T5"

-- Versionierte Regeln für die Bewertung vorhandener Verzauberungen.
--
-- Format je Eintrag:
--   [enchantID] = {
--       verdict    = "OPTIMAL" | "SOLID" | "IMPROVABLE",
--       name       = "Anzeigename der Verzauberung",
--       slots      = { "HANDS", "BACK" },      -- optional, sonst für alle Slots
--       roles      = { "TANK", "HEALER" },     -- optional, sonst für alle Rollen
--       archetypes = { "CASTER_DPS" },         -- optional, sonst für alle
--       phase      = "T4",                     -- ab welcher Phase erhältlich
--       source     = "Quelle der Empfehlung",
--   }
--
-- Jede Enchant-ID unten ist einzeln auf ihrer Wowhead-Seite nachgeschlagen: die
-- Zahl ist die Klammer-ID aus der Zeile "Enchant Item: ... (ID)", also genau
-- das, was auch im Item-Link steht. Geraten wurde nichts - beim Nachschlagen
-- haben sich mehrere aus dem Gedaechtnis angenommene Spell-IDs als falsch
-- erwiesen und wurden verworfen.
--
-- Welche Verzauberung fuer welchen Archetyp die beste ist, stammt aus den
-- BiS-Listen von wowtbc.gg (Stand Phase T5).
--
-- Die Stufen bedeuten:
--   OPTIMAL     - aktuelle Empfehlung fuer diesen Archetyp;
--   SOLID       - wirkungsvolle, raidtaugliche Alternative;
--   IMPROVABLE  - funktional, aber fuer den Raid deutlich schwaecher
--                 (PvP-Werte und Widerstandsverzauberungen).
--
-- Was hier fehlt, wird nicht als schlecht gewertet: Unbekannte IDs gelten je
-- nach Einstellung als anerkannt oder als "Unbekannt", nie als Fund.
GC.EnchantRuleSet = {
    version = 2,
    phase = "T5",
    source = "wowhead.com (IDs) + wowtbc.gg (Empfehlungen)",
    rules = {
        -- === Kopf: Arkanum/Glyphe aus dem Ruf ===========================
        [3002] = { verdict = "OPTIMAL", name = "Glyph of Power",
            slots = { "HEAD" }, archetypes = { "CASTER_DPS" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [3001] = { verdict = "OPTIMAL", name = "Glyph of Renewal",
            slots = { "HEAD" }, archetypes = { "HEALER" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2999] = { verdict = "OPTIMAL", name = "Glyph of the Defender",
            slots = { "HEAD" }, archetypes = { "TANK" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [3003] = { verdict = "OPTIMAL", name = "Glyph of Ferocity",
            slots = { "HEAD" }, archetypes = { "PHYSICAL_DPS" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [3000] = { verdict = "IMPROVABLE", name = "Glyph of the Wild",
            slots = { "HEAD" }, phase = "T4",
            source = "PvP-Werte (Abhärtung) zählen im Raid nicht" },

        -- === Schulter: Inschriften ======================================
        [2995] = { verdict = "OPTIMAL", name = "Greater Inscription of the Orb",
            slots = { "SHOULDER" }, archetypes = { "CASTER_DPS" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2997] = { verdict = "OPTIMAL", name = "Greater Inscription of the Blade",
            slots = { "SHOULDER" }, archetypes = { "PHYSICAL_DPS", "TANK" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2993] = { verdict = "OPTIMAL", name = "Greater Inscription of the Oracle",
            slots = { "SHOULDER" }, archetypes = { "HEALER" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2991] = { verdict = "OPTIMAL", name = "Greater Inscription of the Knight",
            slots = { "SHOULDER" }, archetypes = { "TANK" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2996] = { verdict = "SOLID", name = "Inscription of the Blade",
            slots = { "SHOULDER" }, archetypes = { "PHYSICAL_DPS", "TANK" }, phase = "T4",
            source = "kleinere Fassung der Großen Inschrift" },
        [2994] = { verdict = "SOLID", name = "Inscription of the Orb",
            slots = { "SHOULDER" }, archetypes = { "CASTER_DPS" }, phase = "T4",
            source = "kleinere Fassung der Großen Inschrift" },
        [2998] = { verdict = "IMPROVABLE", name = "Inscription of Endurance",
            slots = { "SHOULDER" }, phase = "T4",
            source = "Widerstandsinschrift, außerhalb von Widerstandskämpfen schwach" },

        -- === Rücken =====================================================
        [2621] = { verdict = "OPTIMAL", name = "Cloak - Subtlety",
            slots = { "BACK" }, archetypes = { "CASTER_DPS", "HEALER" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [368] = { verdict = "OPTIMAL", name = "Cloak - Greater Agility",
            slots = { "BACK" }, archetypes = { "PHYSICAL_DPS", "TANK" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2664] = { verdict = "IMPROVABLE", name = "Cloak - Major Resistance",
            slots = { "BACK" }, phase = "T4",
            source = "Widerstandsverzauberung, nur für Widerstandskämpfe" },

        -- === Brust ======================================================
        [2661] = { verdict = "OPTIMAL", name = "Chest - Exceptional Stats",
            slots = { "CHEST" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [1144] = { verdict = "SOLID", name = "Chest - Major Spirit",
            slots = { "CHEST" }, archetypes = { "HEALER", "CASTER_DPS" }, phase = "T4",
            source = "wowtbc.gg Alternative" },
        [3150] = { verdict = "SOLID", name = "Chest - Restore Mana Prime",
            slots = { "CHEST" }, archetypes = { "HEALER" }, phase = "T4",
            source = "wowtbc.gg BiS für Heilig-Paladine" },
        [2659] = { verdict = "SOLID", name = "Chest - Exceptional Health",
            slots = { "CHEST" }, archetypes = { "TANK" }, phase = "T4",
            source = "wowtbc.gg BiS für Schutz-Paladine" },
        [2933] = { verdict = "IMPROVABLE", name = "Chest - Major Resilience",
            slots = { "CHEST" }, phase = "T4",
            source = "PvP-Werte (Abhärtung) zählen im Raid nicht" },

        -- === Handgelenke ================================================
        [2650] = { verdict = "OPTIMAL", name = "Bracer - Spellpower",
            slots = { "WRIST" }, archetypes = { "CASTER_DPS" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2617] = { verdict = "OPTIMAL", name = "Bracer - Superior Healing",
            slots = { "WRIST" }, archetypes = { "HEALER" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [1593] = { verdict = "OPTIMAL", name = "Bracer - Assault",
            slots = { "WRIST" }, archetypes = { "PHYSICAL_DPS" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2648] = { verdict = "OPTIMAL", name = "Bracer - Major Defense",
            slots = { "WRIST" }, archetypes = { "TANK" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2647] = { verdict = "SOLID", name = "Bracer - Brawn",
            slots = { "WRIST" }, archetypes = { "PHYSICAL_DPS" }, phase = "T4",
            source = "wowtbc.gg Alternative" },
        -- Dieselbe Enchant-ID sitzt auf Handgelenken und Stiefeln: Die ID
        -- beschreibt den Effekt (+12 Ausdauer), nicht den Ausrüstungsplatz.
        -- Beide Slots gehören deshalb in dieselbe Regel.
        [2649] = { verdict = "SOLID", name = "Fortitude (+12 Ausdauer)",
            slots = { "WRIST", "FEET" }, archetypes = { "TANK" }, phase = "T4",
            source = "wowtbc.gg Alternative" },

        -- === Hände ======================================================
        [2937] = { verdict = "OPTIMAL", name = "Gloves - Major Spellpower",
            slots = { "HANDS" }, archetypes = { "CASTER_DPS" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2322] = { verdict = "OPTIMAL", name = "Gloves - Major Healing",
            slots = { "HANDS" }, archetypes = { "HEALER" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [1594] = { verdict = "OPTIMAL", name = "Gloves - Assault",
            slots = { "HANDS" }, archetypes = { "PHYSICAL_DPS", "TANK" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2564] = { verdict = "OPTIMAL", name = "Gloves - Superior Agility",
            slots = { "HANDS" }, archetypes = { "PHYSICAL_DPS" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [684] = { verdict = "SOLID", name = "Gloves - Major Strength",
            slots = { "HANDS" }, archetypes = { "PHYSICAL_DPS" }, phase = "T4",
            source = "wowtbc.gg Alternative" },
        [2934] = { verdict = "SOLID", name = "Gloves - Blasting",
            slots = { "HANDS" }, archetypes = { "CASTER_DPS" }, phase = "T4",
            source = "wowtbc.gg Alternative" },
        [2935] = { verdict = "SOLID", name = "Gloves - Spell Strike",
            slots = { "HANDS" }, archetypes = { "CASTER_DPS" }, phase = "T4",
            source = "wowtbc.gg Alternative, solange Trefferwertung fehlt" },

        -- === Beine: Beinrüstung und Zauberfaden =========================
        [2748] = { verdict = "OPTIMAL", name = "Runic Spellthread",
            slots = { "LEGS" }, archetypes = { "CASTER_DPS" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2746] = { verdict = "OPTIMAL", name = "Golden Spellthread",
            slots = { "LEGS" }, archetypes = { "HEALER" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [3012] = { verdict = "OPTIMAL", name = "Nethercobra Leg Armor",
            slots = { "LEGS" }, archetypes = { "PHYSICAL_DPS" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [3013] = { verdict = "OPTIMAL", name = "Nethercleft Leg Armor",
            slots = { "LEGS" }, archetypes = { "TANK" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2747] = { verdict = "SOLID", name = "Mystic Spellthread",
            slots = { "LEGS" }, archetypes = { "CASTER_DPS" }, phase = "T4",
            source = "kleinere Fassung des Runenzauberfadens" },

        -- === Füße =======================================================
        [2939] = { verdict = "OPTIMAL", name = "Boots - Cat's Swiftness",
            slots = { "FEET" }, archetypes = { "PHYSICAL_DPS" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2940] = { verdict = "OPTIMAL", name = "Boots - Boar's Speed",
            slots = { "FEET" }, archetypes = { "TANK", "CASTER_DPS", "HEALER" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2657] = { verdict = "SOLID", name = "Boots - Dexterity",
            slots = { "FEET" }, archetypes = { "PHYSICAL_DPS" }, phase = "T4",
            source = "wowtbc.gg BiS für Vergelter-Paladine" },

        -- === Waffe ======================================================
        [2673] = { verdict = "OPTIMAL", name = "Weapon - Mongoose",
            slots = { "MAINHAND", "OFFHAND" }, archetypes = { "PHYSICAL_DPS" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2671] = { verdict = "OPTIMAL", name = "Weapon - Sunfire",
            slots = { "MAINHAND" }, archetypes = { "CASTER_DPS" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2672] = { verdict = "OPTIMAL", name = "Weapon - Soulfrost",
            slots = { "MAINHAND" }, archetypes = { "CASTER_DPS" }, phase = "T4",
            source = "wowtbc.gg BiS, gleichwertig zu Sunfire" },
        [2343] = { verdict = "OPTIMAL", name = "Weapon - Major Healing",
            slots = { "MAINHAND" }, archetypes = { "HEALER" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2669] = { verdict = "OPTIMAL", name = "Weapon - Major Spellpower",
            slots = { "MAINHAND" }, archetypes = { "CASTER_DPS" }, phase = "T4",
            source = "wowtbc.gg BiS für Elementar-Schamanen und Schutz-Paladine" },
        [963] = { verdict = "IMPROVABLE", name = "Weapon - Major Striking",
            slots = { "MAINHAND", "OFFHAND" }, archetypes = { "PHYSICAL_DPS" }, phase = "T4",
            source = "deutlich schwächer als Mongoose" },

        -- === Schild =====================================================
        [2655] = { verdict = "SOLID", name = "Shield - Shield Block",
            slots = { "OFFHAND" }, archetypes = { "TANK" }, phase = "T4",
            source = "wowtbc.gg Alternative" },

        -- === Ringe (nur für Verzauberer selbst) =========================
        [2928] = { verdict = "OPTIMAL", name = "Ring - Spellpower",
            slots = { "FINGER1", "FINGER2" }, archetypes = { "CASTER_DPS", "HEALER" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2929] = { verdict = "OPTIMAL", name = "Ring - Striking",
            slots = { "FINGER1", "FINGER2" }, archetypes = { "PHYSICAL_DPS", "TANK" }, phase = "T4",
            source = "wowtbc.gg BiS" },
        [2931] = { verdict = "SOLID", name = "Ring - Stats",
            slots = { "FINGER1", "FINGER2" }, phase = "T4",
            source = "allgemeine Alternative für alle Rollen" },
    },
}

-- Bekannte Luecke: Die Aldor-Schulterinschriften (Vengeance, Faith,
-- Discipline) haben eigene Enchant-IDs, die sich bei der Recherche nicht
-- belegen liessen - nur die Scryer-Gegenstuecke (Blade, Oracle, Orb) und die
-- rangunabhaengige Inschrift des Ritters stehen oben. Aldor-Inschriften werden
-- deshalb nicht falsch bewertet, sondern gar nicht: Sie gelten als unbewertete
-- Verzauberung und damit als in Ordnung. Wer sie einstufen will, klickt sie in
-- der Ausruestungspruefung einmal an - die Gildenregel sticht diesen Satz.

-- Verzauberung -> Werkstatt-Rezept: die Bruecke zwischen Ausruestungspruefung
-- und Werkstatt. Links die Enchant-ID aus dem Regelsatz oben, rechts der
-- Katalogschluessel des Verzauberkunst-Zaubers, der sie wirkt ("E" plus
-- Zauber-ID, genau wie der Rezeptscan ihn ablegt).
--
-- Jede Zeile ist am 07.08.2026 einzeln auf der Wowhead-TBC-Zauberseite
-- nachgeschlagen worden: Der Zauber nennt dort seine Enchant-ID in der
-- Effektzeile ("Enchant Item: ... (ID)"). Geraten wurde nichts - was sich
-- nicht belegen liess, steht nicht drin und macht schlicht keinen
-- Bestellvorschlag:
--   fehlend: Handschuhe Brawn (2647), Major Strength (684), Blasting (2934),
--   Spell Strike (2935), Schild Shield Block (2655), Waffe Major Striking
--   (963), die Stiefel-Haelfte der Ausdauer-Doppelregel (2649, belegt ist nur
--   der Armschienen-Zauber) - und die Beinruestungen/Zauberfaeden, die als
--   HERSTELLBARE GEGENSTAENDE eigene Item-Schluessel braeuchten.
-- Kopf- und Schulterverzauberungen sind Rufware, fuer sie gibt es
-- grundsaetzlich nichts zu bestellen.
GC.EnchantRecipeKeys = {
    [368] = "E34004",   -- Umhang: +12 Beweglichkeit
    [1144] = "E33990",  -- Brust: +15 Willenskraft
    [1593] = "E34002",  -- Armschienen: +24 Angriffskraft
    [1594] = "E33996",  -- Handschuhe: +26 Angriffskraft
    [2322] = "E33999",  -- Handschuhe: +35 Heilung
    [2343] = "E34010",  -- Waffe: +81 Heilung
    [2564] = "E25080",  -- Handschuhe: +15 Beweglichkeit
    [2617] = "E27911",  -- Armschienen: +30 Heilung
    [2621] = "E25084",  -- Umhang: Feinheit
    [2648] = "E27906",  -- Armschienen: +12 Verteidigungswertung
    [2649] = "E27914",  -- Armschienen: +12 Ausdauer
    [2650] = "E27917",  -- Armschienen: +15 Zauberschaden
    [2657] = "E27951",  -- Stiefel: +12 Beweglichkeit
    [2659] = "E27957",  -- Brust: +150 Leben
    [2661] = "E27960",  -- Brust: +6 alle Werte
    [2669] = "E27975",  -- Waffe: +40 Zauberschaden
    [2671] = "E27981",  -- Waffe: Sonnenfeuer
    [2672] = "E27982",  -- Waffe: Seelenfrost
    [2673] = "E27984",  -- Waffe: Mungo
    [2928] = "E27924",  -- Ring: +12 Zauberschaden
    [2929] = "E27920",  -- Ring: +2 Waffenschaden
    [2931] = "E27927",  -- Ring: +4 alle Werte
    [2933] = "E33992",  -- Brust: +15 Abhärtung
    [2937] = "E33997",  -- Handschuhe: +20 Zauberschaden
    [2939] = "E34007",  -- Stiefel: Katzengeschwindigkeit
    [2940] = "E34008",  -- Stiefel: Ebergeschwindigkeit
    [3150] = "E33991",  -- Brust: +6 Mana alle 5 Sek.
}

-- Entscheidungen zu Pflegevorschlägen. Sie werden gildenweit synchronisiert,
-- damit nicht mehrere Offiziere denselben Fall doppelt bearbeiten.
GC.MemberCareDecisions = {
    IGNORED = { key = "IGNORED", label = "Ausnahme", help = "Erscheint nie wieder als Vorschlag." },
    POSTPONED = { key = "POSTPONED", label = "Zurückgestellt", help = "Erscheint erst nach dem Datum wieder." },
    DONE = { key = "DONE", label = "Erledigt", help = "Fall wurde bearbeitet." },
}

GC.MemberCarePostponeDays = 30
GC.MemberCareMaxDecisions = 40

GC.ClassOrder = {
    "WARRIOR",
    "PALADIN",
    "HUNTER",
    "ROGUE",
    "PRIEST",
    "SHAMAN",
    "MAGE",
    "WARLOCK",
    "DRUID",
}

GC.Classes = {
    WARRIOR = {
        id = 1,
        name = "Krieger",
        plural = "Krieger",
        color = { 0.78, 0.61, 0.43 },
        specs = {
            { key = "WARRIOR:1", name = "Waffen", recruitLabel = "Waffen-Krieger", role = "DAMAGER" },
            { key = "WARRIOR:2", name = "Furor", recruitLabel = "Furor-Krieger", role = "DAMAGER" },
            { key = "WARRIOR:3", name = "Schutz", recruitLabel = "Schutz-Krieger", role = "TANK" },
        },
    },
    PALADIN = {
        id = 2,
        name = "Paladin",
        plural = "Paladine",
        color = { 0.96, 0.55, 0.73 },
        specs = {
            { key = "PALADIN:1", name = "Heilig", recruitLabel = "Heilig-Paladine", role = "HEALER" },
            { key = "PALADIN:2", name = "Schutz", recruitLabel = "Schutz-Paladine", role = "TANK" },
            { key = "PALADIN:3", name = "Vergeltung", recruitLabel = "Vergelter-Paladine", role = "DAMAGER" },
        },
    },
    HUNTER = {
        id = 3,
        name = "Jäger",
        plural = "Jäger",
        color = { 0.67, 0.83, 0.45 },
        specs = {
            { key = "HUNTER:1", name = "Tierherrschaft", recruitLabel = "Tierherrschafts-Jäger", role = "DAMAGER" },
            { key = "HUNTER:2", name = "Treffsicherheit", recruitLabel = "Treffsicherheits-Jäger", role = "DAMAGER" },
            { key = "HUNTER:3", name = "Überleben", recruitLabel = "Überlebens-Jäger", role = "DAMAGER" },
        },
    },
    ROGUE = {
        id = 4,
        name = "Schurke",
        plural = "Schurken",
        color = { 1.00, 0.96, 0.41 },
        specs = {
            { key = "ROGUE:1", name = "Meucheln", recruitLabel = "Meucheln-Schurken", role = "DAMAGER" },
            { key = "ROGUE:2", name = "Kampf", recruitLabel = "Kampf-Schurken", role = "DAMAGER" },
            { key = "ROGUE:3", name = "Täuschung", recruitLabel = "Täuschungs-Schurken", role = "DAMAGER" },
        },
    },
    PRIEST = {
        id = 5,
        name = "Priester",
        plural = "Priester",
        color = { 1.00, 1.00, 1.00 },
        specs = {
            { key = "PRIEST:1", name = "Disziplin", recruitLabel = "Disziplin-Priester", role = "HEALER" },
            { key = "PRIEST:2", name = "Heilig", recruitLabel = "Heilig-Priester", role = "HEALER" },
            { key = "PRIEST:3", name = "Schatten", recruitLabel = "Schattenpriester", role = "DAMAGER" },
        },
    },
    SHAMAN = {
        id = 7,
        name = "Schamane",
        plural = "Schamanen",
        color = { 0.00, 0.44, 0.87 },
        specs = {
            { key = "SHAMAN:1", name = "Elementar", recruitLabel = "Elementar-Schamanen", role = "DAMAGER" },
            { key = "SHAMAN:2", name = "Verstärkung", recruitLabel = "Verstärker-Schamanen", role = "DAMAGER" },
            { key = "SHAMAN:3", name = "Wiederherstellung", recruitLabel = "Wiederherstellungs-Schamanen", role = "HEALER" },
        },
    },
    MAGE = {
        id = 8,
        name = "Magier",
        plural = "Magier",
        color = { 0.25, 0.78, 0.92 },
        specs = {
            { key = "MAGE:1", name = "Arkan", recruitLabel = "Arkan-Magier", role = "DAMAGER" },
            { key = "MAGE:2", name = "Feuer", recruitLabel = "Feuer-Magier", role = "DAMAGER" },
            { key = "MAGE:3", name = "Frost", recruitLabel = "Frost-Magier", role = "DAMAGER" },
        },
    },
    WARLOCK = {
        id = 9,
        name = "Hexenmeister",
        plural = "Hexenmeister",
        color = { 0.53, 0.53, 0.93 },
        specs = {
            { key = "WARLOCK:1", name = "Gebrechen", recruitLabel = "Gebrechen-Hexenmeister", role = "DAMAGER" },
            { key = "WARLOCK:2", name = "Dämonologie", recruitLabel = "Dämonologie-Hexenmeister", role = "DAMAGER" },
            { key = "WARLOCK:3", name = "Zerstörung", recruitLabel = "Zerstörungs-Hexenmeister", role = "DAMAGER" },
        },
    },
    DRUID = {
        id = 11,
        name = "Druide",
        plural = "Druiden",
        color = { 1.00, 0.49, 0.04 },
        specs = {
            { key = "DRUID:1", name = "Gleichgewicht", recruitLabel = "Gleichgewichts-Druiden", role = "DAMAGER" },
            { key = "DRUID:2", name = "Wildheit", recruitLabel = "Wildheits-Druiden", role = "FLEX" },
            { key = "DRUID:3", name = "Wiederherstellung", recruitLabel = "Wiederherstellungs-Druiden", role = "HEALER" },
        },
    },
}

GC.SpecByKey = {}
for classFile, classInfo in pairs(GC.Classes) do
    for index, spec in ipairs(classInfo.specs) do
        spec.classFile = classFile
        spec.index = index
        GC.SpecByKey[spec.key] = spec
    end
end

-- Kurze, in der LFM-Kultur uebliche englische Spec-Kuerzel. Die deutschen
-- recruitLabel ("Wiederherstellungs-Schamanen") sind fuer die Rekrutierung
-- richtig, aber im Suchspruch und im knappen Besetzungsmenue der Raidsuche zu
-- lang - dort spricht ohnehin jeder LFM-Englisch ("Resto Shaman", "Boomkin").
-- Gilt nur in der Raidsuche; die Rekrutierung bleibt deutsch.
GC.SpecShortLabel = {
    ["WARRIOR:1"] = "Arms War",   ["WARRIOR:2"] = "Fury War",   ["WARRIOR:3"] = "Prot War",
    ["PALADIN:1"] = "Holy Pala",  ["PALADIN:2"] = "Prot Pala",  ["PALADIN:3"] = "Ret Pala",
    ["HUNTER:1"] = "BM Hunter",   ["HUNTER:2"] = "MM Hunter",    ["HUNTER:3"] = "Surv Hunter",
    ["ROGUE:1"] = "Assa Rogue",   ["ROGUE:2"] = "Combat Rogue",  ["ROGUE:3"] = "Sub Rogue",
    ["PRIEST:1"] = "Disc Priest", ["PRIEST:2"] = "Holy Priest",  ["PRIEST:3"] = "Shadow Priest",
    ["SHAMAN:1"] = "Ele Shaman",  ["SHAMAN:2"] = "Enh Shaman",   ["SHAMAN:3"] = "Resto Shaman",
    ["MAGE:1"] = "Arcane Mage",   ["MAGE:2"] = "Fire Mage",      ["MAGE:3"] = "Frost Mage",
    ["WARLOCK:1"] = "Affli Lock", ["WARLOCK:2"] = "Demo Lock",   ["WARLOCK:3"] = "Destro Lock",
    ["DRUID:1"] = "Boomkin",      ["DRUID:2"] = "Feral Druid",   ["DRUID:3"] = "Resto Druid",
}

-- Kurzform, sonst der deutsche recruitLabel. Ein Punkt, an dem beide Namen
-- zusammenlaufen.
function GC.SpecShort(specKey)
    local spec = GC.SpecByKey[specKey]
    return GC.SpecShortLabel[specKey] or (spec and spec.recruitLabel) or tostring(specKey)
end

GC.CoverageRules = {
    { specKey = "SHAMAN:2", priority = "HOCH", reason = "Melee-Gruppen profitieren stark von Verstärker-Support." },
    { specKey = "SHAMAN:1", priority = "MITTEL", reason = "Caster-Gruppen profitieren von Elementar-Support." },
    { specKey = "PRIEST:3", priority = "HOCH", reason = "Schattenpriester stabilisieren die Mana-Versorgung." },
    { specKey = "HUNTER:3", priority = "MITTEL", reason = "Überlebens-Jäger bringen Expose Weakness." },
    { specKey = "WARRIOR:1", priority = "MITTEL", reason = "Waffen-Krieger unterstützen physischen Schaden mit Blood Frenzy." },
    { specKey = "PALADIN:3", priority = "MITTEL", reason = "Vergelter bringen zusätzlichen Paladin-Support." },
    { specKey = "DRUID:1", priority = "MITTEL", reason = "Gleichgewichts-Druiden unterstützen Caster-Gruppen." },
}

GC.ChannelKinds = {
    RECRUITMENT = {
        label = "Gildenrekrutierung",
        aliases = { "gildenrekrutierung", "gilden rekrutierung", "guildrecruitment", "guild recruitment" },
    },
    LFG = {
        label = "SucheNachGruppe",
        aliases = { "suchenachgruppe", "suche nach gruppe", "lookingforgroup", "looking for group" },
    },
    TRADE = {
        label = "Handel",
        aliases = { "handel", "trade" },
    },
    GENERAL = {
        label = "Allgemein",
        aliases = { "allgemein", "general" },
    },
}
