local _, GC = ...

-- === Sprache ================================================================
--
-- Deutsch ist die Quellsprache des Addons: Jeder Text im Code steht deutsch,
-- und GC.L(text) gibt ihn auf deutschen Clients unveraendert zurueck. Auf
-- allen anderen Clients schlaegt GC.L in der englischen Tabelle nach; was
-- dort (noch) fehlt, bleibt deutsch, statt zu brechen - die Uebersetzung
-- kann damit in Teilschritten wachsen, ohne je einen halben Zustand zu
-- zeigen.
--
-- Der Fahrplan (Owner-Vorgabe vom 08.08.2026):
--
--   Teilschritt 1 (dieser Stand): Navigation, Seitentitel und Untertitel -
--   ausschliesslich eigene Addon-Texte.
--
--   Teilschritt 2: Spielbegriffe (Verbrauchsgegenstaende, Slots, Instanzen).
--   Fuer sie gilt eine harte Regel: NIE frei uebersetzen. Jeder Name eines
--   Gegenstands, Zaubers oder einer Verzauberung wird einzeln aus einer
--   offiziellen Quelle uebernommen (Wowhead ueber die Spell-/Item-ID, oder
--   der Spielclient selbst) und traegt seinen Beleg als Kommentar - dasselbe
--   Verfahren wie bei GC.EnchantRecipeKeys.
--
--   Teilschritt 3: Seiteninhalte, Status- und Chatmeldungen.
--
-- Warum Deutsch als Schluessel: Das Addon ist deutschsprachig gewachsen,
-- jede Zeile Code traegt ihren Text schon. Ein Schluesselsystem ("PAGE_
-- TITLE_GEAR") haette tausende Stellen angefasst, bevor die erste
-- Uebersetzung sichtbar wird; so genuegt eine Tabellenzeile je Text, und
-- nicht Uebersetztes faellt sichtbar und harmlos auf Deutsch zurueck.

local english = {
    -- === Teilschritt 1: Navigation =========================================
    -- Abschnitte der Seitenleiste. COPILOT, RAID und SYSTEM sind in beiden
    -- Sprachen dieselben Woerter und brauchen keinen Eintrag.
    ["REKRUTIERUNG"] = "RECRUITMENT",
    ["GILDE"] = "GUILD",

    -- Reiter der Seitenleiste.
    ["Profil"] = "Profile",
    ["Übersicht"] = "Overview",
    ["Gildenprofil"] = "Guild Profile",
    ["Vorschläge"] = "Suggestions",
    ["Klassen & Specs"] = "Classes & Specs",
    ["Werbung posten"] = "Post Ad",
    ["Postfach"] = "Inbox",
    ["Mitgliederpflege"] = "Member Care",
    ["Gildenwerkstatt"] = "Guild Workshop",
    ["Raidauswertung"] = "Raid Review",
    ["Ausrüstung"] = "Gear",
    ["Einstellungen"] = "Settings",

    -- === Raidsuche (0.9.139) ===============================================
    ["Raidsuche"] = "Raid Search",
    ["Raid zusammenstellen, Suchspruch posten und den Zulauf verwalten — Antworten auf die laufende Suche landen rechts, nicht im Bewerber-Postfach."]
        = "Assemble the raid, post the LFM line and manage incoming replies — answers to a running search land on the right, not in the applicant inbox.",
    ["Neue Suche"] = "New Search",
    ["Wirklich neu?"] = "Really reset?",
    ["Suche beenden"] = "End Search",
    ["Suchbalken einblenden"] = "Show search bar",
    ["Suchbalken ausblenden"] = "Hide search bar",
    ["Zettel-Vorlagen"] = "Sheet Templates",
    ["Antwortvorlagen"] = "Reply Templates",
    ["Suchzettel"] = "Search Sheet",
    ["Instanz"] = "Instance",
    ["Größe"] = "Size",
    ["Termin"] = "Date",
    ["Lootregel"] = "Loot Rule",
    ["Hard Res."] = "Hard Res.",
    ["SR-Link"] = "SR Link",
    ["Frei (eigener Name)"] = "Custom (own name)",
    ["Vorlage wählen"] = "Pick a preset",
    ["Suchspruch"] = "LFM Line",
    ["Vorlage"] = "Preset",
    ["Vorlagen"] = "Templates",
    ["Suche starten"] = "Start Search",
    ["Posten"] = "Post",
    ["Wiederholen"] = "Auto-repeat",
    ["Besetzung"] = "Lineup",
    ["Klassen & Specs wählen"] = "Pick classes & specs",
    ["Keine Specs gewählt - über den Knopf ankreuzen."]
        = "No specs picked - tick them via the button.",
    ["Gesucht: "] = "Wanted: ",
    ["Ankreuzen, welche Specs gesucht werden - sie erscheinen im Suchspruch."]
        = "Tick the specs you want - they show up in the LFM line.",
    ["Alle abwählen"] = "Clear all",
    ["Fertig"] = "Done",
    ["Tanks"] = "Tanks",
    ["Heiler"] = "Healers",
    ["dabei {n}"] = "in group {n}",
    ["voll"] = "full",
    ["Keine Spec-Wünsche - das Menü darunter schaltet sie an und aus."]
        = "No spec wishes - the menu below toggles them on and off.",
    ["Wünsche: "] = "Wishes: ",
    ["Spec-Wunsch an/aus"] = "Toggle spec wish",
    ["{n} dabei ohne Spec-Zuordnung - zählt auf keine Rolle."]
        = "{n} in group without a spec - counted toward no role.",
    ["Am Termin abgemeldet: {names}"] = "On leave that day: {names}",
    ["Zulauf"] = "Replies",
    ["Spec zuordnen"] = "Assign spec",
    ["Einladen"] = "Invite",
    ["Antworten"] = "Reply",
    ["Keine Spec-Zuordnung"] = "No spec assigned",
    ["NEU"] = "NEW",
    ["EINGELADEN"] = "INVITED",
    ["ANGESCHRIEBEN"] = "CONTACTED",
    ["DABEI"] = "IN GROUP",
    ["Suchzettel-Vorlagen"] = "Search Sheet Templates",
    ["Anwenden erzeugt einen frischen Zettel mit dem nächsten passenden Wochentag."]
        = "Applying creates a fresh sheet with the next matching weekday.",
    ["Anwenden"] = "Apply",
    ["Aktuellen Zettel als Vorlage speichern"] = "Save current sheet as template",
    ["Noch keine Vorlagen gespeichert."] = "No templates saved yet.",
    ["Eigene Schnellantworten für den Zulauf. Platzhalter: {name} {instanz} {termin} {loot} {srlink} - gesendet wird per Klick im Antworten-Menü."]
        = "Your own quick replies for incoming answers. Placeholders: {name} {instanz} {termin} {loot} {srlink} - sent with a click in the reply menu.",
    ["Neue Vorlage"] = "New template",
    ["offen: "] = "open: ",
    ["offen: {n} Plätze"] = "open: {n} spots",
    ["voll besetzt"] = "fully staffed",
    ["Automatik: der nächste Tastendruck postet."] = "Auto-repeat: your next keypress posts.",
    ["{n} neue Antworten im Zulauf"] = "{n} new replies waiting",
    ["Tipp: „Automatisch wiederholen“ erspart das erneute Klicken."]
        = "Tip: \"Repeat automatically\" saves you the extra click.",

    -- === Teilschritt 1: Seitentitel ========================================
    ["Dein Profil"] = "Your Profile",
    ["Gildenübersicht"] = "Guild Overview",
    ["Copilot-Vorschläge"] = "Copilot Suggestions",

    -- === Teilschritt 1: Untertitel der Seiten ==============================
    ["Raidprofil, Berufe und Abmeldung an einem Ort – diese Angaben werden mit Guild-Copilot-Nutzern in deiner Gilde synchronisiert."]
        = "Raid profile, professions and absences in one place – these details are synchronized with Guild Copilot users in your guild.",
    ["|cff2ec7dbNach zuletzt online sortiert|r – bis zu {n} Level-70-Spieler aus den gewählten Raider-Rängen, mit Rang, Raidprofil und Berufen."]
        = "|cff2ec7dbSorted by last seen online|r – up to {n} level 70 players from the selected raider ranks, with rank, raid profile and professions.",
    ["ZULETZT ONLINE"] = "LAST ONLINE",
    -- Die Mitgliederpflege ist rein informativ; die Beschriftungen des
    -- Aufklappmenues und des Ausschlussknopfes sind mit ihnen entfallen.
    ["Twinks, aktiv Abgemeldete und geschützte Ränge werden ausgeblendet. „Ausnahme“ nimmt jemanden dauerhaft aus der Liste. Entfernt wird in WoW selbst – das lässt WoW aus einem Addon heraus nicht zu."]
        = "Alts, players on leave and protected ranks are hidden. „Exempt“ removes somebody from the list for good. Removing happens in WoW itself – an addon is not allowed to do it.",
    ["erkannt"] = "detected",
    ["Spec aus dem Talentbaum gelesen, als dieser Spieler für den Ausrüstungsabgleich inspiziert wurde. Main/Twink und Zweitspec kennt nur der Spieler selbst."]
        = "Spec read from the talent tree while inspecting this player for the gear audit. Only the player knows main/alt and off-spec.",
    ["Leder"] = "Leatherw.",
    ["Verzauberer"] = "Enchanter",
    ["Schneider"] = "Tailor",
    ["Schmied"] = "Blacksm.",
    ["Juwelen"] = "Jewelcr.",
    ["Kräuter"] = "Herbal.",
    ["Kürschner"] = "Skinner",
    ["Alchi"] = "Alchemy",
    ["Ingi"] = "Engineer",
    ["Kochen"] = "Cooking",
    ["Diese Angaben werden gildenweit synchronisiert und fließen in Werbe- und Antworttexte ein."]
        = "These details are synchronized guild-wide and feed the ad and reply templates.",
    ["Gildenroster, bestätigte Profile und importierte Logs ergeben einen Vorschlag für die Rekrutierung."]
        = "Guild roster, confirmed profiles and imported logs combine into a recruiting suggestion.",
    ["Klassen öffnen, Bedarf auswählen und die Reihenfolge rechts nach Priorität sortieren."]
        = "Open a class, pick what you need and order the list on the right by priority.",
    ["Text prüfen, bestätigen und mit einem echten Klick in die ausgewählten Kanäle senden — oder die Automatik postet mit dem nächsten Tastendruck, sobald ein Kanal bereit ist."]
        = "Review the text, confirm and send it to the selected channels with a real click — or let auto-repeat post on your next keypress once a channel is ready.",
    ["Whispers und erkannte „Suche Gilde“-Nachrichten werden hier gesammelt."]
        = "Whispers and detected \"looking for guild\" messages are collected here.",
    ["Abmeldungen berücksichtigen und lange Inaktivität nachvollziehbar prüfen – niemals automatisch entfernen."]
        = "Respect absences and review long inactivity transparently – never remove anyone automatically.",
    ["Rezepte werden automatisch erfasst, sobald ein Spieler sein WoW-Berufsfenster öffnet."]
        = "Recipes are recorded automatically whenever a player opens their WoW profession window.",
    ["Profile manuell eingeben oder öffentliche Reports mit dem mitgelieferten Windows-Helfer auslesen."]
        = "Enter profiles by hand or read public reports with the bundled Windows companion.",
    ["Sitzungen starten nur berechtigte Ränge; gespeichert werden Zusammenfassungen, keine Rohdaten. Spaltenkopf: Klick sortiert, Ziehen ordnet um. Maus über einer Zeile zeigt alles im Detail."]
        = "Only authorized ranks start sessions; summaries are stored, never raw data. Column headers: click sorts, drag reorders. Hover over a row for full details.",
    ["Fehlende Verzauberungen, leere Pflichtslots und Sockel je Slot. Addon-Nutzer liefern aktuelle Eigendaten; Inspect bleibt der Rückfall für erreichbare Gruppenmitglieder. Es gibt bewusst keine Gesamtnote."]
        = "Missing enchants, empty mandatory slots and sockets per slot. Addon users provide fresh self-reports; inspect remains the fallback for group members in range. There is deliberately no overall score.",
    ["Lokale Komfortoptionen und gildenweite Berechtigungen für Guild Copilot."]
        = "Local convenience options and guild-wide permissions for Guild Copilot.",

    -- === Teilschritt 2: Spielbegriffe ======================================
    -- Ausruestungsslots. Die englischen Begriffe sind die offiziellen
    -- Slot-Bezeichnungen, wie sie Wowheads Itemseiten fuehren (Head,
    -- Shoulder, Finger, Trinket, Main Hand, Off Hand, Ranged, ...) -
    -- abgeglichen am 08.08.2026, nichts frei uebersetzt.
    ["Kopf"] = "Head",
    ["Hals"] = "Neck",
    ["Schulter"] = "Shoulder",
    ["Brust"] = "Chest",
    ["Gürtel"] = "Waist",
    ["Beine"] = "Legs",
    ["Füße"] = "Feet",
    ["Handgelenke"] = "Wrist",
    ["Hände"] = "Hands",
    ["Ring 1"] = "Finger 1",
    ["Ring 2"] = "Finger 2",
    ["Schmuck 1"] = "Trinket 1",
    ["Schmuck 2"] = "Trinket 2",
    ["Rücken"] = "Back",
    ["Waffenhand"] = "Main Hand",
    ["Schildhand"] = "Off Hand",
    ["Distanz"] = "Ranged",
    ["alle Slots"] = "all slots",

    -- Bewertungsstufen und Verbrauchskategorien: eigenes Addon-Vokabular,
    -- keine Spielnamen ("Optimal" ist in beiden Sprachen dasselbe Wort).
    ["Solide"] = "Solid",
    ["Verbesserbar"] = "Improvable",
    ["Fehlt"] = "Missing",
    ["Unbekannt"] = "Unknown",
    ["Ausnahme"] = "Exempt",
    ["Tränke"] = "Potions",
    ["Runen"] = "Runes",
    ["Trommeln"] = "Drums",
    ["Fläschchen"] = "Flasks",
    ["Elixiere"] = "Elixirs",
    ["Essen"] = "Food",
    ["Öle/Steine"] = "Oils/Stones",

    -- === Teilschritt 3: Karten =============================================
    ["Aktive Raider  •  Level 70"] = "Active Raiders  •  Level 70",
    ["Aktuelle Abmeldungen"] = "Current Absences",
    ["Allgemein"] = "General",
    ["Ausgeblendete Spieler"] = "Hidden Players",
    ["Ausnahmen und Entscheidungen"] = "Exceptions and Decisions",
    ["Ausrüstung – Hintergrundabgleich"] = "Gear – Background Sync",
    ["Bewerberton hören"] = "Applicant Sound",
    ["Chat-Befehle"] = "Chat Commands",
    ["Dein Raidprofil"] = "Your Raid Profile",
    ["Deine Abmeldung"] = "Your Absence",
    ["Deine Ausrüstung"] = "Your Gear",
    ["Deine Berufe"] = "Your Professions",
    ["Deine Suche"] = "Your Search",
    ["Empfohlener Rekrutierungsbedarf"] = "Recommended Recruiting Needs",
    ["Erste Schritte"] = "Getting Started",
    ["Gefundene Rezepte"] = "Recipes Found",
    ["Geprüfte Spieler"] = "Audited Players",
    ["Gildenaufträge"] = "Guild Orders",
    ["Gildenquelle"] = "Guild Source",
    ["Import – manuell oder Installer"] = "Import – manual or installer",
    ["Interessenten"] = "Applicants",
    ["Kanäle"] = "Channels",
    ["Mitgliederpflege öffnen"] = "Open Member Care",
    ["Pflegevorschläge"] = "Care Suggestions",
    ["Postfach-Erkennung: eigene Wörter"] = "Inbox Detection: Custom Words",
    ["Prüfregeln"] = "Audit Rules",
    ["Rekrutierung: Meldungen & Töne"] = "Recruitment: Alerts & Sounds",
    ["Rezeptdetails"] = "Recipe Details",
    ["Sitzungen"] = "Sessions",
    ["Teilnehmer"] = "Participants",
    ["Texte & Eckdaten"] = "Texts & Key Facts",
    ["Unterhaltung"] = "Conversation",
    ["Vorlagen für Danke, Gildeninfos und Discord"] = "Templates for Thanks, Guild Info and Discord",
    ["Werbetext"] = "Ad Text",
    ["Werkstatt"] = "Workshop",

    -- === Teilschritt 3: Knöpfe =============================================
    ["(keiner)"] = "(none)",
    ["7 Tage ausblenden"] = "Hide for 7 days",
    ["Abbrechen"] = "Cancel",
    ["Abmelden"] = "Set absence",
    ["Abmeldung löschen"] = "Delete absence",
    ["Alle Prüfungen"] = "All audits",
    ["Alle anzeigen"] = "Show all",
    ["Alle löschen"] = "Delete all",
    ["Alles klar"] = "Got it",
    ["Als Vorlage merken"] = "Save as template",
    ["Anflüstern"] = "Whisper",
    ["Annehmen"] = "Accept",
    ["Antworten"] = "Reply",
    ["Anwesenheit"] = "Attendance",
    ["Aus"] = "Off",
    ["Aus Gilde erkennen"] = "Detect from guild",
    ["Ausrüstung prüfen"] = "Audit gear",
    ["Auswahl leeren"] = "Clear selection",
    ["Auswertung anfordern"] = "Request reviews",
    ["Bestätigen"] = "Confirm",
    ["Danke"] = "Thanks",
    ["Daten anfragen"] = "Request data",
    ["Daten importieren"] = "Import data",
    ["Dauerhaft ignorieren"] = "Ignore permanently",
    ["Detailfenster"] = "Detail window",
    ["Eigene Ausrüstung"] = "My gear",
    ["Einrichtung"] = "Setup",
    ["Entfernen"] = "Remove",
    ["Erledigt"] = "Done",
    ["Erneut prüfen"] = "Re-check",
    ["Erstellen"] = "Create",
    ["Favoriten"] = "Favorites",
    ["Ganze Klasse"] = "Whole class",
    ["Gezahlt melden"] = "Mark paid",
    ["Gilde"] = "Guild",
    ["Gildeninfos"] = "Guild info",
    ["Gildenprofil prüfen"] = "Review guild profile",
    ["Gruppe"] = "Group",
    ["Gruppe prüfen"] = "Check group",
    ["Guild Copilot öffnen"] = "Open Guild Copilot",
    ["Heute"] = "Today",
    ["In Auftrag geben"] = "Place order",
    ["In Gilde einladen"] = "Invite to guild",
    ["Katalog"] = "Catalog",
    ["Keiner"] = "None",
    ["Leeren"] = "Clear",
    ["Los geht's"] = "Let's go",
    ["Manuell auswählen"] = "Pick manually",
    ["Melden"] = "Report",
    ["Meldung testen"] = "Test alert",
    ["Merken"] = "Favorite",
    ["Gemerkt"] = "Favorited",
    ["Neu generieren"] = "Regenerate",
    ["Nicht gesetzt"] = "Not set",
    ["Nicht jetzt"] = "Not now",
    ["Nicht mehr anzeigen"] = "Don't show again",
    ["Notiz senden"] = "Send note",
    ["Position zurücksetzen"] = "Reset position",
    ["Profil bestätigen"] = "Confirm profile",
    ["Quelle speichern"] = "Save source",
    ["Rezept-Lücken der Gilde"] = "Guild recipe gaps",
    ["Roster aktualisieren"] = "Refresh roster",
    ["Ränge: alle"] = "Ranks: all",
    ["Schließen"] = "Close",
    ["Sitzung löschen"] = "Delete session",
    ["Sitzung starten"] = "Start session",
    ["Sitzung beenden"] = "End session",
    ["Sound testen"] = "Test sound",
    ["Speichern & weiter"] = "Save & continue",
    ["Später"] = "Later",
    ["Statistik"] = "Statistics",
    ["Suche starten"] = "Start search",
    ["Symbol zurück an die Minimap"] = "Icon back to the minimap",
    ["Rechte erneut senden"] = "Send permissions again",
    ["Für alle, die beim Setzen offline waren."] = "For everyone who was offline when you set them.",
    ["Text bestätigen"] = "Confirm text",
    ["Vergleich"] = "Compare",
    ["Verlauf"] = "History",
    ["Verzauberung bestellen"] = "Order enchant",
    ["Vorgabe eintragen"] = "Insert default",
    ["Vorgabe wiederherstellen"] = "Restore default",
    ["Vorlagen speichern"] = "Save templates",
    ["Vorschläge übernehmen"] = "Apply suggestions",
    ["Weiter"] = "Continue",
    ["Werbebalken"] = "Ad bar",
    ["Werbetext erstellen  >"] = "Create ad text  >",
    ["Wieder zulassen"] = "Allow again",
    ["Wirklich löschen?"] = "Really delete?",
    ["Wörter speichern"] = "Save words",
    ["Zur Gildenwerkstatt"] = "To the guild workshop",
    ["Zur Gruppe"] = "To the group",
    ["Zurück"] = "Back",
    ["Zurückholen"] = "Bring back",
    ["nur machbare"] = "only craftable",
    ["Überspringen"] = "Skip",

    -- === Teilschritt 3: Schalter ===========================================
    ["Automatisch wiederholen"] = "Auto-repeat",
    ["Erfolgssound aktiv"] = "Success sound on",
    ["Flexibel einsetzbar"] = "Flexible",
    ["Twink"] = "Alt",
    ["Minimap-Symbol anzeigen"] = "Show minimap icon",
    ["Vorhandene Verzauberung gilt als in Ordnung"] = "Existing enchant counts as fine",
    ["Whispers nur während einer Suche prüfen"] = "Check whispers only during a search",
    ["Öffentliche „Suche Gilde“-Nachrichten erkennen"] = "Detect public \"looking for guild\" messages",
    ["Abgelaufene Berufs-Wartezeiten im Chat melden"] = "Announce expired profession cooldowns in chat",
    ["Bildschirmmeldung bei neuen machbaren Aufträgen"] = "On-screen alert for new craftable orders",
    ["Flüsterbefehl beantworten: „!rezept <Suche>“"] = "Answer whisper command: \"!rezept <search>\"",

    -- === Teilschritt 3: Spaltenköpfe und Kurztexte =========================
    ["ZEIT"] = "TIME",
    ["WAS"] = "WHAT",
    ["ART"] = "TYPE",
    ["EMPFEHLUNG"] = "RECOMMENDATION",
    ["STUFE"] = "GRADE",
    ["ABENDE"] = "NIGHTS",
    ["ANTEIL"] = "SHARE",
    ["ZULETZT"] = "LAST",
    ["HINWEIS"] = "NOTE",
    ["SOCKEL"] = "SOCKETS",
    ["BEWERTUNG"] = "RATING",
    ["BEFUND"] = "FINDINGS",
    ["STAND"] = "AS OF",
    ["RANG"] = "RANK",
    ["ABGESCHLOSSEN"] = "COMPLETED",
    ["DU BIST DRAN"] = "YOUR TURN",
    ["VERZAUBERUNG & SOCKEL"] = "ENCHANT & SOCKETS",

    -- === Auftragsboard (0.9.110) ===========================================
    -- Die Ueberschriften tragen ihre Anzahl mit und laufen deshalb ueber
    -- GC.LFormat; die Platzhalter bleiben in beiden Sprachen dieselben.
    ["DU BIST DRAN  ·  MEINE AUFTRÄGE ({n})"] = "YOUR TURN  ·  MY ORDERS ({n})",
    ["OFFENE AUFTRÄGE DER GILDE ({n})"] = "OPEN GUILD ORDERS ({n})",
    ["LÄUFT IN DER GILDE"] = "IN PROGRESS IN THE GUILD",
    ["LÄUFT IN DER GILDE ({n})"] = "IN PROGRESS IN THE GUILD ({n})",
    ["ABGESCHLOSSEN ({n})"] = "COMPLETED ({n})",
    ["{n} abgelehnt"] = "{n} declined",
    ["{n} fertig"] = "{n} done",
    ["Gerade läuft nichts für dich – weder als Auftraggeber noch als Hersteller."]
        = "Nothing is running for you right now – neither as client nor as crafter.",
    ["Zurzeit ist nichts offen."] = "Nothing is open right now.",
    ["Sonst ist gerade nichts in Arbeit."] = "Nothing else is in progress right now.",
    ["Noch nichts abgeschlossen."] = "Nothing completed yet.",
    ["Nicht für mich"] = "Not for me",
    ["Wieder einblenden"] = "Show again",

    -- === Freitext-Auftraege und Herstellen (0.9.112) =======================
    ["Freier Auftrag"] = "Custom order",
    ["Freier Gildenauftrag"] = "Custom guild order",
    ["Was brauchst du? (kurz)"] = "What do you need? (short)",
    ["Beruf"] = "Profession",
    ["Beruf wählen"] = "Choose profession",
    ["Wähle den Beruf, der den Auftrag erfüllen kann."]
        = "Choose the profession that can fill this order.",
    ["Herstellen"] = "Craft",
    ["Berufsfenster öffnen"] = "Open profession window",
    ["{n}× herstellen"] = "Craft {n}×",
    ["{n} selbst gefertigt, noch nicht gemeldet"] = "{n} crafted by you, not reported yet",
    ["Gildenaufträge"] = "Guild Orders",
    ["Fenstergröße ziehen"] = "Drag to resize",
    ["Minimieren"] = "Minimize",
    ["Wieder aufklappen"] = "Restore",
    ["Keine passenden Interessenten"] = "No matching applicants",
    ["Einladung konnte nicht ausgelöst werden."] = "Could not send the invitation.",
    ["Keine Treffer für diese Filter. Wähle Alle Klassen und Alle Stufen, um alle Interessenten zu sehen."]
        = "No matches for these filters. Select All classes and All levels to see every applicant.",

    -- === Teilschritt 3: statische Meldungen und Zustände ===================
    ["Abgleich mit der Gilde"] = "Guild sync",
    ["Abmeldung abgelaufen – neu eintragen oder löschen."] = "Absence expired – re-enter or delete it.",
    ["Abmeldung gelöscht und mit der Gilde synchronisiert."] = "Absence deleted and synchronized with the guild.",
    ["Alle vier Listen stehen wieder auf der Vorgabe."] = "All four lists are back to the default.",
    ["Aus Warcraft Logs: exakte Gegenstände mit Anzahl - Uhrzeiten kennt der Export nicht."] = "From Warcraft Logs: exact items with counts - the export knows no timestamps.",
    ["Auswertung angefragt - warte auf Antworten …"] = "Reviews requested - waiting for answers …",
    ["Automatik aus: Gepostet wird nur noch per Klick."] = "Auto-repeat off: posting only by click now.",
    ["Automatik wartet auf einen bestätigten Text."] = "Auto-repeat is waiting for a confirmed text.",
    ["Automatik: kein ausgewählter Kanal beigetreten."] = "Auto-repeat: no selected channel joined.",
    ["Bitte Interessent und Antwort auswählen."] = "Please select an applicant and a reply.",
    ["Dein Gildenrang darf das Gildenprofil nicht bearbeiten."] = "Your guild rank may not edit the guild profile.",
    ["Dein Gildenrang darf den Rangschutz nicht ändern."] = "Your guild rank may not change rank protection.",
    ["Dein Gildenrang darf die Prüfregeln nicht ändern."] = "Your guild rank may not change the audit rules.",
    ["Dein Gildenrang darf die gildenweiten Vorlagen nicht bearbeiten."] = "Your guild rank may not edit the guild-wide templates.",
    ["Dein Gildenrang darf diese Berechtigung nicht ändern."] = "Your guild rank may not change this permission.",
    ["Dein Rang darf dieses gildenweite Profil bearbeiten."] = "Your rank may edit this guild-wide profile.",
    ["Dein eigener Rang wurde einmalig wieder freigeschaltet."] = "Your own rank has been unlocked once.",
    ["Den eigenen Rang kannst du nicht abwählen."] = "You cannot deselect your own rank.",
    ["Senden nicht möglich – bist du in einer Gilde?"] = "Cannot send – are you in a guild?",
    ["Gesendet an {n} – warte auf Bestätigung …"] = "Sent to {n} – waiting for confirmation …",
    ["Gesendet. {n} online mit älterer Fassung – die können den Empfang nicht bestätigen."] = "Sent. {n} online with an older version – they cannot confirm receipt.",
    ["Gesendet. Gerade ist niemand mit dem Addon online – ohne Empfänger keine Bestätigung."] = "Sent. Nobody with the addon is online right now – no recipient, no confirmation.",
    ["Rechte bestätigt angekommen bei {ok} von {total}."] = "Permissions confirmed received by {ok} of {total}.",
    ["Rechte angekommen bei {ok} von {total} – bei {lost} nicht."] = "Permissions received by {ok} of {total} – not by {lost}.",
    ["Die Vorlagen sind für deinen Rang schreibgeschützt."] = "The templates are read-only for your rank.",
    ["Diese Quelle liefert nur Kategoriezähler ohne Einzelheiten."] = "This source provides only category counters without details.",
    ["Diesen Rang darf nur ein höherer Gildenrang abwählen."] = "Only a higher guild rank may deselect this rank.",
    ["Dieser Charakter ist eingerichtet."] = "This character is set up.",
    ["Ein Klick genügt – ändern kannst du alles jederzeit."] = "One click is enough – you can change everything later.",
    ["Ein leerer Werbetext kann nicht bestätigt werden."] = "An empty ad text cannot be confirmed.",
    ["Empfehlung des Regelsatzes"] = "Rule set recommendation",
    ["Erneut bestätigen"] = "Confirm again",
    ["Es gelten durchgehend deine eigenen Listen."] = "Your own lists apply throughout.",
    ["Favorisierte Rezepte"] = "Favorite recipes",
    ["Fertig – dieser Charakter ist eingerichtet."] = "Done – this character is set up.",
    ["Ohne erkennbaren Realm des Interessenten lassen sich keine Profil-Links bilden."] = "Profile links need the applicant's realm, which could not be determined.",
    ["Für deinen Gildenrang gesperrt"] = "Locked for your guild rank",
    ["Für diese Sitzung wurden keine Teilnehmer erfasst."] = "No participants were recorded for this session.",
    ["Für diesen Teilnehmer wurde kein Verbrauch erfasst."] = "No consumables were recorded for this participant.",
    ["Geprüft wird von allein weiter – bei jedem Login und nach jedem Ausrüstungswechsel."] = "Auditing continues on its own – at every login and after every gear change.",
    ["Gespeichert und zur Gildensynchronisierung vorgemerkt."] = "Saved and queued for guild synchronization.",
    ["Gespeichert. Leere Trigger-Felder nutzen wieder die Vorgabe."] = "Saved. Empty trigger fields use the default again.",
    ["Gezielte Rezeptsuche"] = "Targeted recipe search",
    ["Gildenaufträge – du bist dran ({n})"] = "Guild orders – your turn ({n})",
    ["Wartet auf {name}."] = "Waiting for {name}.",
    ["… und {n} weitere."] = "… and {n} more.",
    ["Gildenweite Änderungen sind für deinen Rang freigegeben."] = "Guild-wide changes are enabled for your rank.",
    ["Guild Copilot in der Gilde"] = "Guild Copilot in the guild",
    ["Kein Interessent ausgewählt."] = "No applicant selected.",
    ["Keine Abmeldung eingetragen."] = "No absence entered.",
    ["Keine Auswertung vorhanden. Auf der Seite Raidauswertung einen Abend wählen."] = "No review available. Pick a night on the Raid Review page.",
    ["Keine Favoriten gefunden"] = "No favorites found",
    ["Keine Mitglieder erfüllen die aktuellen Prüfregeln."] = "No members match the current audit rules.",
    ["Keine Reagenzien erfasst."] = "No reagents recorded.",
    ["Keine Talente erkannt – wähle deine Spec von Hand."] = "No talents detected – pick your spec by hand.",
    ["Keine Treffer"] = "No matches",
    ["Keine aktiven oder geplanten Abmeldungen bekannt."] = "No active or upcoming absences known.",
    ["Link aus Region, Realm und Gildenname vorbereitet."] = "Link prepared from region, realm and guild name.",
    ["Live mitgeschrieben: jeder gezählte Einwurf mit Uhrzeit."] = "Recorded live: every counted use with its time.",
    ["Löschen bestätigen"] = "Confirm delete",
    ["Mindestens ein Rang muss Zugriff auf die Mitgliederpflege behalten."] = "At least one rank must keep access to member care.",
    ["Mindestens ein berechtigter Rang muss erhalten bleiben."] = "At least one authorized rank must remain.",
    ["Nachgesehen: Dieser Charakter hat keinen Hauptberuf erlernt."] = "Checked: this character has not learned a primary profession.",
    ["Nicht installiert"] = "Not installed",
    ["Niemand ausgeblendet."] = "Nobody hidden.",
    ["Noch keine Interessenten"] = "No applicants yet",
    ["Noch nicht abgefragt"] = "Not queried yet",
    ["Noch nicht bestätigt."] = "Not confirmed yet.",
    ["Noch nicht eingelesen"] = "Not read yet",
    ["Nur Vorschläge – keine automatische Entfernung."] = "Suggestions only – no automatic removal.",
    ["Nur freigegebene Gildenränge dürfen den Bewerberton umstellen."] = "Only enabled guild ranks may change the applicant sound.",
    ["Nur in Einstellungen freigegebene Gildenränge dürfen Änderungen speichern."] = "Only guild ranks enabled in the settings may save changes.",
    ["Offene Schritte warten in der Checkliste oben auf der Profilseite – ganz ohne Eile."] = "Open steps wait in the checklist at the top of the profile page – no rush.",
    ["Postfach vollständig geleert."] = "Inbox completely cleared.",
    ["Prüfe den Suchbegriff oder frage aktuelle Gildendaten an."] = "Check the search term or request fresh guild data.",
    ["Prüfregeln sind für deinen Rang schreibgeschützt."] = "Audit rules are read-only for your rank.",
    ["Raid-Symbol geändert. Bitte den Text erneut bestätigen."] = "Raid marker changed. Please confirm the text again.",
    ["Regeln werden gildenweit synchronisiert."] = "Rules are synchronized guild-wide.",
    ["Rezepte eingelesen – ein Klick öffnet das Fenster erneut"] = "Recipes read – one click opens the window again",
    ["Roster aktuell"] = "Roster up to date",
    ["Roster wird neu abgefragt …"] = "Refreshing roster …",
    ["Sammelberuf ohne Rezepte – nichts einzulesen"] = "Gathering profession without recipes – nothing to read",
    ["Sicher?"] = "Sure?",
    ["Stand des Gildenabgleichs"] = "Guild sync status",
    ["Starte eine Suche. Eingehende Flüsternachrichten erscheinen automatisch hier."] = "Start a search. Incoming whispers appear here automatically.",
    ["Suchergebnisse"] = "Search results",
    ["Vorgabe eingetragen – jetzt bearbeiten und speichern."] = "Default inserted – now edit and save.",
    ["Vorlagen gespeichert und für die Gilde synchronisiert."] = "Templates saved and synchronized for the guild.",
    ["Warte auf Antwort …"] = "Waiting for a reply …",
    ["Werbetext bestätigt und bereit."] = "Ad text confirmed and ready.",
    ["Wirklich ersetzen"] = "Really replace",
    ["Wonach suchst du?"] = "What are you looking for?",
    ["Wähle links eine Sitzung aus."] = "Pick a session on the left.",
    ["dauerhaft ignoriert"] = "permanently ignored",
    ["ganze Klasse"] = "whole class",
    ["|cff59e695Alle Materialien vorhanden.|r"] = "|cff59e695All materials available.|r",
    ["|cff59e695Keine automatische Lücke erkannt.|r Du kannst trotzdem Klassen und Specs manuell wählen."] = "|cff59e695No automatic gap detected.|r You can still pick classes and specs manually.",
    ["|cff59e695Workflow bereit:|r Vorschläge übernehmen, Auswahl prüfen und anschließend den Werbetext bestätigen."] = "|cff59e695Workflow ready:|r apply the suggestions, check the selection, then confirm the ad text.",
    ["|cff8b98a5• kein anderer Nutzer erkannt|r"] = "|cff8b98a5• no other user detected|r",
    ["|cff91a3b8Die Prüfung läuft gerade im Hintergrund – das Ergebnis erscheint hier.|r"] = "|cff91a3b8The audit is running in the background – results appear here.|r",
    ["|cffff6266• Abgleich unvollständig|r"] = "|cffff6266• sync incomplete|r",
    ["|cffffb840Kein bestätigter Text. Unter „Werbung posten“ bestätigen.|r"] = "|cffffb840No confirmed text. Confirm it under Post Ad.|r",
    ["|cffffb84dDatenlage noch dünn:|r Mehr Mitglieder sollten ihr Profil bestätigen oder Logs importiert werden."] = "|cffffb84dData still thin:|r more members should confirm their profile, or import logs.",
    ["„Zur Gruppe“ führt zurück zur Übersicht."] = "\"To the group\" leads back to the overview.",

    -- === Teilschritt 4: restliche statische Oberflächentexte ===============
    ["Du"] = "You",
    ["Menge"] = "Amount",
    ["Symbole"] = "Icons",
    ["Seite 1/1"] = "Page 1/1",
    ["Bis später!"] = "See you later!",
    ["Primär-Spec"] = "Primary spec",
    ["Materialien"] = "Materials",
    ["Raid-Symbol"] = "Raid marker",
    ["0/255 Bytes"] = "0/255 bytes",
    ["Vorschlag ab"] = "Suggested from",
    ["0 AUSGEWÄHLT"] = "0 SELECTED",
    ["Gut zu wissen"] = "Good to know",
    ["Gildenwerbung"] = "Guild Ad",
    ["Versionsprüfer"] = "Version Check",
    ["Geschützte Ränge"] = "Protected Ranks",
    ["Trinkgeld (Gold)"] = "Tip (gold)",
    ["Notiz (optional)"] = "Note (optional)",
    ["Profilbestätigung:"] = "Profile confirmation:",
    ["Kostenrahmen (Gold)"] = "Cost limit (gold)",
    ["Dual-Spec (optional)"] = "Dual spec (optional)",
    ["Raidinstanz betreten"] = "Entering a raid instance",
    ["Noch niemand geprüft."] = "Nobody audited yet.",
    ["Was Guild Copilot kann"] = "What Guild Copilot does",
    ["Kein Rezept ausgewählt"] = "No recipe selected",
    ["Sprache der Oberfläche:"] = "Interface language:",
    ["Stück insgesamt fertig:"] = "Pieces finished in total:",
    ["Raidauswertung – Detail"] = "Raid Review – Detail",
    ["Kein Bewerber ausgewählt"] = "No applicant selected",
    ["OFFENE AUFTRÄGE DER GILDE"] = "OPEN GUILD ORDERS",
    ["Rezept oder Spieler suchen"] = "Search recipe or player",
    ["Gruppenprüfung – Ausrüstung"] = "Group Check – Gear",
    ["Antwortvorschau  •  editierbar"] = "Reply preview  •  editable",
    ["Wähle links einen Spieler aus."] = "Pick a player on the left.",
    ["Noch keine Auswertung vorhanden."] = "No review available yet.",
    ["Anzeigedauer der Meldung (Sekunden)"] = "Alert display time (seconds)",
    ["Spaltenköpfe ziehen ordnet die Spalten"] = "Drag column headers to reorder",
    ["Wunsch-Hersteller (optional, 24 h reserviert)"] = "Preferred crafter (optional, reserved for 24 h)",
    ["Übergabetext ({name} und {rezept} werden ersetzt)"] = "Handover text ({name} and {rezept} are replaced)",
    ["Mehrere deiner Charaktere beherrschen das Rezept."] = "Several of your characters know this recipe.",
    ["Ausnahmen setzt jeder für seine eigene Ausrüstung."] = "Exceptions are set by each player for their own gear.",
    ["Tatsächliche Materialkosten in Gold (0, wenn nichts anfiel):"] = "Actual material cost in gold (0 if nothing was spent):",
    ["Markiere häufig benötigte Rezepte mit dem Stern in den Rezeptdetails."] = "Mark frequently needed recipes with the star in the recipe details.",
    ["Deine Fähigkeiten ließen sich nicht lesen – bitte oben von Hand wählen."] = "Your skills could not be read – please pick manually above.",
    ["Dein Gildenassistent für Rekrutierung, Roster, Berufe und Raidauswertung."] = "Your guild assistant for recruiting, roster, professions and raid reviews.",
    ["Dieser Charakter hat keine Berufe mit Rezepten – hier gibt es nichts zu tun."] = "This character has no professions with recipes – nothing to do here.",
    ["Die Meldung lässt sich mit der Maus dorthin schieben, wo sie nichts verdeckt."] = "The alert can be dragged wherever it covers nothing.",
    ["Öffne deine Berufe einmal, damit Guild Copilot die bekannten Rezepte einliest."] = "Open your professions once so Guild Copilot can read your known recipes.",
    ["Noch nichts gewählt.\n\nLinks eine Klasse öffnen und ganze Klasse oder Specs auswählen."] = "Nothing selected yet.\n\nOpen a class on the left and pick the whole class or single specs.",
    ["Alles liegt in einem Fenster – die Seitenleiste links gliedert es von oben nach unten:"] = "Everything lives in one window – the sidebar on the left structures it top to bottom:",
    ["Geändert – noch nicht bestätigt. In der Gilde steht weiter der zuletzt bestätigte Stand."] = "Changed – not confirmed yet. The guild still sees the last confirmed version.",
    ["Von Hand gewählt. Die leere Auswahl oben schaltet zurück auf die automatische Erkennung."] = "Picked by hand. Clearing the selection above switches back to automatic detection.",
    ["Danach weiß die Gildenwerkstatt, was du herstellen kannst – zu finden im Abschnitt GILDE."] = "After that the guild workshop knows what you can craft – found in the GUILD section.",
    ["Das Symbol lässt sich frei ziehen: nahe der Minimap am Ring entlang, weiter weg überall hin."] = "The icon can be dragged freely: near the minimap along the ring, further away anywhere.",
    ["Gildenweite Einstellungen sind für deinen Rang schreibgeschützt; lokale Optionen bleiben änderbar."] = "Guild-wide settings are read-only for your rank; local options remain editable.",
    ["Main oder Twink und deine Abmeldung stellst du später im Abschnitt COPILOT auf der Seite „Profil“ ein."] = "Main or alt and your absence are set later in the COPILOT section on the Profile page.",
    ["Diese Einträge werden gildenweit synchronisiert, damit nicht zwei Offiziere denselben Fall bearbeiten."] = "These entries are synchronized guild-wide so two officers never work the same case.",
    ["Die eigene Ausrüstung wird immer automatisch geprüft und kompakt mit Addon-Nutzern der Gilde abgeglichen."] = "Your own gear is always audited automatically and compactly synchronized with addon users in the guild.",
    ["|cff91a3b8Noch nicht geprüft. Ein Klick auf \"Ausrüstung prüfen\" liest deine angelegten Gegenstände aus.|r"] = "|cff91a3b8Not audited yet. A click on \"Audit gear\" reads your equipped items.|r",
    ["Automatik an: Der Werbebalken bleibt offen; sobald ein Kanal bereit ist, postet dein nächster Tastendruck."] = "Auto-repeat on: the ad bar stays open; once a channel is ready, your next keypress posts.",
    ["Prüft deine eigene Ausrüstung auf fehlende Verzauberungen und leere Sockel. Läuft nur bei dir und ohne Gruppe."] = "Audits your own gear for missing enchants and empty sockets. Runs only for you, no group needed.",
    ["Eine Zeile je Sperre (Umwandlung, Spezialtuch, Sphäre), beim Login und bei Ablauf – auch für die eigenen Twinks."] = "One line per cooldown (transmute, specialty cloth, sphere), at login and on expiry – for your alts too.",
    ["Die Prüfung aller Raider und den gildenweiten Regelsatz findest du im Abschnitt RAID auf der Seite „Ausrüstung“."] = "The audit of all raiders and the guild-wide rule set live in the RAID section on the Gear page.",
    ["Antwortet Gildenmitgliedern per Flüstern mit Materialliste und Herstellern aus dem Katalog, gedrosselt je Absender."] = "Replies to guild members by whisper with a material list and crafters from the catalog, throttled per sender.",
    ["„Automatisch“ folgt der Sprache des WoW-Clients. Vollständig wirkt die Umstellung nach dem Neuladen der Oberfläche."] = "\"Automatic\" follows the WoW client language. The change takes full effect after reloading the UI.",
    ["Nur berechtigte Einstellungs-Ränge ändern diese gildenweiten Regeln. Geschützte Ränge erscheinen nie als Vorschlag."] = "Only authorized settings ranks change these guild-wide rules. Protected ranks never appear as suggestions.",
    ["Trage hier direkt ein, wann du nicht verfügbar bist. Mitgliederpflege und Roster berücksichtigen den Zeitraum automatisch."] = "Enter directly when you are unavailable. Member care and roster respect the period automatically.",
    ["Twinks, aktiv Abgemeldete und geschützte Ränge werden ausgeblendet. „Prüfen“ bedeutet: Main/Twink-Status ist nicht bestätigt."] = "Alts, active absences and protected ranks are hidden. \"Check\" means: main/alt status is not confirmed.",
    ["Automatisch aus deinen Fähigkeiten übernommen. Neue Rezepte wandern beim Öffnen des Berufsfensters von selbst in die Werkstatt."] = "Taken automatically from your skills. New recipes flow into the workshop by themselves when you open the profession window.",
    ["Du kannst die Einrichtung jederzeit neu starten: mit /gcp welcome oder über den Knopf „Einrichtung“ oben im Guild-Copilot-Fenster."] = "You can restart the setup anytime: with /gcp welcome or via the Setup button at the top of the Guild Copilot window.",
    ["Nur diese Ränge sehen die Mitgliederpflege - und nur sie dürfen Raidauswertungen löschen. Die Freigabe wird gildenweit synchronisiert."] = "Only these ranks see member care - and only they may delete raid reviews. The permission is synchronized guild-wide.",
    ["Nur die aktuelle Gruppe. Addon-Nutzer liefern selbst, der Rest per Inspect in Reichweite. Klick auf eine Zeile zeigt die Verzauberungen."] = "Only the current group. Addon users report themselves, the rest via inspect in range. Click a row to see the enchants.",
    ["Ohne diesen Schalter bleibt jede nicht bewertete Verzauberung \"Unbekannt\". Er bewertet keine Qualität, er unterscheidet nur verzaubert von nicht verzaubert."] = "Without this switch every unrated enchant stays \"Unknown\". It rates no quality, it only distinguishes enchanted from not enchanted.",
    ["Von diesen Spielern landet nichts mehr im Postfach. Befristete Einträge verschwinden von selbst, sobald das Datum erreicht ist. Die Liste gilt nur für dich."] = "Nothing from these players reaches the inbox anymore. Dated entries expire on their own. This list applies only to you.",
    ["Nur diese Ränge hören den Ton, wenn sich jemand im Postfach meldet. Das Postfach füllt sich für alle weiter, nur still. Die Freigabe wird gildenweit synchronisiert."] = "Only these ranks hear the sound when someone lands in the inbox. The inbox keeps filling for everyone, just silently. The permission is synchronized guild-wide.",
    ["Gib einen Rezept- oder Spielernamen ein, wähle einen Beruf oder öffne deine Favoriten.\n\nSo bleibt die Werkstatt auch mit tausenden bekannten Rezepten übersichtlich."] = "Enter a recipe or player name, pick a profession or open your favorites.\n\nThis keeps the workshop tidy even with thousands of known recipes.",
    ["Diese Texte füllen die drei Knöpfe oben. Sie gelten gildenweit. Platzhalter: {name}, {gilde}, {beschreibung}, {raidzeiten}, {progress}, {loot}, {discord}, {kontakt}."] = "These texts fill the three buttons above. They apply guild-wide. Placeholders: {name}, {gilde}, {beschreibung}, {raidzeiten}, {progress}, {loot}, {discord}, {kontakt}.",
    ["|cffe8b84bHinweis:|r Gerade ist niemand mit Guild Copilot online. Der Auftrag wird gespeichert und verteilt sich, sobald du gemeinsam mit anderen Addon-Nutzern online bist."] = "|cffe8b84bNote:|r nobody with Guild Copilot is online right now. The order is stored and spreads once you are online together with other addon users.",
    ["|cff91a3b8Noch keine Log-Daten importiert.|r\nDie gespeicherte URL ist für den Companion vorbereitet. Importiert ein anderes Gildenmitglied, erscheinen die Profile auch hier von selbst."] = "|cff91a3b8No log data imported yet.|r\nThe saved URL is prepared for the companion. If another guild member imports, the profiles appear here by themselves.",
    ["Ohne API: Name;Klasse;Primär-Spec;Dual-Spec – z. B. Nexarius;Magier;Arkan;Frost.\nAutomatisch: Im Guild-Copilot-Installer „Import erzeugen“; die Companion-CMD bleibt als Rückfall. Danach hier mit Strg+V einfügen."] = "Without API: Name;Class;PrimarySpec;DualSpec – e.g. Nexarius;Mage;Arcane;Frost.\nAutomatic: use \"Create import\" in the Guild Copilot installer; the companion CMD remains the fallback. Then paste here with Ctrl+V.",
    ["Deine beiden Hauptberufe – vom Addon aus deinen Fähigkeiten gelesen, sonst hier von Hand wählbar. Für die Rezepte in der Gildenwerkstatt musst du dein Berufsfenster einmal öffnen; die Namen allein genügen dafür nicht."] = "Your two primary professions – read from your skills, otherwise pickable by hand. For the recipes in the guild workshop you must open your profession window once; the names alone are not enough.",
    ["Ein WoW-Addon darf selbst nichts aus dem Internet laden – deshalb übernimmt der Windows-Helfer den Abruf. Die hier gespeicherte Gilde erspart dir dort die Eingabe, liefert Region und Realm für die Profil-Links im Postfach und wird an alle Gildenmitglieder synchronisiert."] = "A WoW addon may not load anything from the internet itself – the Windows companion does the fetching. The guild saved here spares you the input there, provides region and realm for the profile links in the inbox, and is synchronized to all guild members.",
    ["Ein Wort oder eine Wendung je Zeile, Groß- und Kleinschreibung ist gleich. Ein Ausschlusswort verhindert den Eintrag auch dann, wenn ein Trigger passt. Leere Trigger-Felder bedeuten „Vorgabe“, nicht „nichts“ – abschalten lässt sich die Erkennung über die Schalter darüber. Diese Listen gelten nur für dich."] = "One word or phrase per line, case does not matter. An exclusion word prevents the entry even when a trigger matches. Empty trigger fields mean \"default\", not \"nothing\" – the detection is disabled via the switches above. These lists apply only to you.",

    -- === Hinweis auf eine neuere Fassung (0.9.118) =========================
    ["Version {new} ist verfügbar – du hast {own}. Aktualisieren über die CurseForge-App oder den Guild-Copilot-Installer."]
        = "Version {new} is available – you have {own}. Update via the CurseForge app or the Guild Copilot installer.",
    ["Version {new} verfügbar"] = "Version {new} available",
    ["Deine Version: {own}"] = "Your version: {own}",
    ["Deine Version: {own}  •  |cffffb840{new} ist verfügbar|r"]
        = "Your version: {own}  •  |cffffb840{new} is available|r",

    -- === Teilschritt 4b: Spiel-Stammdaten ==================================
    -- Klassen, Specs (Talentbaeume) und Berufe mit ihren offiziellen
    -- englischen Namen (Wowhead-Klassen-/Talent-/Berufsseiten, TBC).
    -- Bei Klassen, deren deutsche Einzahl und Mehrzahl gleich lauten
    -- (Krieger, Jaeger, Priester, Magier, Hexenmeister), steht die Einzahl -
    -- der Schluessel kann nur auf eines zeigen, und die Einzahl kommt an
    -- mehr Stellen vor.
    ["Krieger"] = "Warrior",
    ["Paladin"] = "Paladin",
    ["Paladine"] = "Paladins",
    ["Jäger"] = "Hunter",
    ["Schurke"] = "Rogue",
    ["Schurken"] = "Rogues",
    ["Priester"] = "Priest",
    ["Priesterin"] = "Priest",
    ["Schamane"] = "Shaman",
    ["Schamanen"] = "Shamans",
    ["Magier"] = "Mage",
    ["Hexenmeister"] = "Warlock",
    ["Druide"] = "Druid",
    ["Druiden"] = "Druids",

    ["Waffen"] = "Arms",
    ["Furor"] = "Fury",
    ["Schutz"] = "Protection",
    ["Heilig"] = "Holy",
    ["Vergeltung"] = "Retribution",
    ["Tierherrschaft"] = "Beast Mastery",
    ["Treffsicherheit"] = "Marksmanship",
    ["Überleben"] = "Survival",
    ["Meucheln"] = "Assassination",
    ["Kampf"] = "Combat",
    ["Täuschung"] = "Subtlety",
    ["Disziplin"] = "Discipline",
    ["Schatten"] = "Shadow",
    ["Elementar"] = "Elemental",
    ["Verstärkung"] = "Enhancement",
    ["Wiederherstellung"] = "Restoration",
    ["Feuer"] = "Fire",
    ["Arkan"] = "Arcane",
    ["Gebrechen"] = "Affliction",
    ["Dämonologie"] = "Demonology",
    ["Zerstörung"] = "Destruction",
    ["Gleichgewicht"] = "Balance",
    ["Wildheit"] = "Feral",

    ["Waffen-Krieger"] = "Arms Warriors",
    ["Furor-Krieger"] = "Fury Warriors",
    ["Schutz-Krieger"] = "Protection Warriors",
    ["Heilig-Paladine"] = "Holy Paladins",
    ["Schutz-Paladine"] = "Protection Paladins",
    ["Vergelter-Paladine"] = "Retribution Paladins",
    ["Tierherrschafts-Jäger"] = "Beast Mastery Hunters",
    ["Treffsicherheits-Jäger"] = "Marksmanship Hunters",
    ["Überlebens-Jäger"] = "Survival Hunters",
    ["Meucheln-Schurken"] = "Assassination Rogues",
    ["Kampf-Schurken"] = "Combat Rogues",
    ["Täuschungs-Schurken"] = "Subtlety Rogues",
    ["Disziplin-Priester"] = "Discipline Priests",
    ["Heilig-Priester"] = "Holy Priests",
    ["Schattenpriester"] = "Shadow Priests",
    ["Elementar-Schamanen"] = "Elemental Shamans",
    ["Verstärker-Schamanen"] = "Enhancement Shamans",
    ["Wiederherstellungs-Schamanen"] = "Restoration Shamans",
    ["Arkan-Magier"] = "Arcane Mages",
    ["Feuer-Magier"] = "Fire Mages",
    ["Frost-Magier"] = "Frost Mages",
    ["Gebrechen-Hexenmeister"] = "Affliction Warlocks",
    ["Dämonologie-Hexenmeister"] = "Demonology Warlocks",
    ["Zerstörungs-Hexenmeister"] = "Destruction Warlocks",
    ["Gleichgewichts-Druiden"] = "Balance Druids",
    ["Wildheits-Druiden"] = "Feral Druids",
    ["Wiederherstellungs-Druiden"] = "Restoration Druids",

    ["Schneiderei"] = "Tailoring",
    ["Verzauberkunst"] = "Enchanting",
    ["Alchimie"] = "Alchemy",
    ["Alchemie"] = "Alchemy",
    ["Schmiedekunst"] = "Blacksmithing",
    ["Lederverarbeitung"] = "Leatherworking",
    ["Ingenieurskunst"] = "Engineering",
    ["Juwelenschleifen"] = "Jewelcrafting",
    ["Kräuterkunde"] = "Herbalism",
    ["Bergbau"] = "Mining",
    ["Kürschnerei"] = "Skinning",
    ["Kochkunst"] = "Cooking",
    ["Erste Hilfe"] = "First Aid",
    ["Angeln"] = "Fishing",

    -- Die Empfehlungsgruende der Rekrutierung (GC.CoverageRules).
    ["Melee-Gruppen profitieren stark von Verstärker-Support."] = "Melee groups benefit greatly from Enhancement support.",
    ["Caster-Gruppen profitieren von Elementar-Support."] = "Caster groups benefit from Elemental support.",
    ["Schattenpriester stabilisieren die Mana-Versorgung."] = "Shadow Priests stabilize mana supply.",
    ["Überlebens-Jäger bringen Expose Weakness."] = "Survival Hunters bring Expose Weakness.",
    ["Waffen-Krieger unterstützen physischen Schaden mit Blood Frenzy."] = "Arms Warriors support physical damage with Blood Frenzy.",
    ["Vergelter bringen zusätzlichen Paladin-Support."] = "Retribution Paladins bring additional Paladin support.",
    ["Gleichgewichts-Druiden unterstützen Caster-Gruppen."] = "Balance Druids support caster groups.",

    -- Kanalarten (offizielle Kanalnamen des englischen Clients).
    ["Gildenrekrutierung"] = "Guild Recruitment",
    ["SucheNachGruppe"] = "LookingForGroup",
    ["Handel"] = "Trade",

    -- === Teilschritt 4b: Kennzahlen, Spalten, Zustaende ====================
    ["MITGLIEDER"] = "MEMBERS",
    ["BEKANNTE PROFILE"] = "KNOWN PROFILES",
    ["MIT ADDON"] = "WITH ADDON",
    ["SPIELER"] = "PLAYER",
    ["BERUFE"] = "PROFESSIONS",
    ["AKTIV"] = "ACTIVE",
    ["REZEPTE"] = "RECIPES",
    ["HERSTELLER"] = "CRAFTERS",
    ["GILDENPROFIL"] = "GUILD PROFILE",
    ["BEKANNTE SPECS"] = "KNOWN SPECS",
    ["LOG-PROFILE"] = "LOG PROFILES",
    ["BEREIT"] = "READY",
    ["HOCH"] = "HIGH",
    ["MITTEL"] = "MEDIUM",
    ["NIEDRIG"] = "LOW",
    ["PRÜFEN"] = "CHECK",
    ["kein Profil"] = "no profile",
    ["keine Funde"] = "no findings",
    ["Alle Berufe"] = "All professions",
    ["Kurzbeschreibung"] = "Short description",
    ["Raidzeiten"] = "Raid times",
    ["Lootsystem"] = "Loot system",
    ["Kontaktperson"] = "Contact person",
    ["Von"] = "From",
    ["Bis"] = "Until",
    ["Grund (optional)"] = "Reason (optional)",
    ["Letzte Nachricht"] = "Last message",
    ["Zurückgestellt"] = "Postponed",
    ["Addon-Abgleich"] = "Addon sync",
    ["Erkannt"] = "Detected",
    ["Talente"] = "Talents",

    -- === Teilschritt 4b: zusammengesetzte Anzeigen (Platzhalter) ===========
    [" und "] = " and ",
    [" sowie "] = " and also ",
    ["vor {n}h"] = "{n}h ago",
    ["vor {n}T"] = "{n}d ago",
    ["vor {n} Min."] = "{n} min ago",
    ["vor {n} Std."] = "{n} h ago",
    ["vor {n} Tagen"] = "{n} days ago",
    ["Ränge: {n}/{m}"] = "Ranks: {n}/{m}",
    ["Ränge: {n} von {m}"] = "Ranks: {n} of {m}",
    ["{n} Funde"] = "{n} findings",
    ["1 Fund"] = "1 finding",
    ["{n} KLASSEN AUSGEWÄHLT"] = "{n} CLASSES SELECTED",
    ["{n} Nutzer{chars}, Daten vollständig"] = "{n} users{chars}, data complete",
    ["{n} Nutzer{chars}, {d} mit anderer Version"] = "{n} users{chars}, {d} on a different version",
    ["{n} Nutzer{chars}, Bestand lückenhaft"] = "{n} users{chars}, inventory incomplete",
    ["Abgleich läuft … {p} %"] = "Sync running … {p} %",
    ["Vollständig synchronisiert"] = "Fully synchronized",
    ["Abgleich läuft"] = "Sync running",
    ["abgeglichen mit {n} weiteren Nutzern"] = "synced with {n} other users",
    ["abgeglichen mit einem weiteren Nutzer"] = "synced with one other user",
    ["Stand: {zeit}."] = "As of: {zeit}.",
    ["gerade eben"] = "just now",
    ["unbekannt"] = "unknown",
    ["> 1 Jahr"] = "> 1 year",
    ["ohne Spec"] = "no spec",
    ["Manuell"] = "Manual",
    ["Bereit."] = "Ready.",
    ["Noch keine Prüfung gelaufen."] = "No audit has run yet.",
    ["Dieser Spieler hat sein Raidprofil noch nie ausgefüllt."] = "This player has never filled in their raid profile.",
    ["Stammt aus einem Warcraft-Logs-Import, nicht vom Spieler selbst."] = "Comes from a Warcraft Logs import, not from the player.",
    ["Wurde von Hand eingetragen, nicht vom Spieler selbst."] = "Was entered by hand, not by the player.",
    ["Als Zweitcharakter gemeldet."] = "Reported as an alt.",
    ["Als Hauptcharakter gemeldet."] = "Reported as a main.",
    [" Der Spieler hat das Profil noch nicht bestätigt."] = " The player has not confirmed the profile yet.",
    ["{n} leere Pflichtslots"] = "{n} empty mandatory slots",
    ["{n} noch nicht lesbare Slots"] = "{n} slots not readable yet",
    ["1 fehlende Verzauberung"] = "1 missing enchant",
    ["1 leerer Sockel"] = "1 empty socket",
    ["1 leerer Ausrüstungsplatz"] = "1 empty equipment slot",
    ["{n} leere Ausrüstungsplätze"] = "{n} empty equipment slots",
    ["1 Ausrüstungsplatz noch nicht lesbar"] = "1 equipment slot not readable yet",
    ["{n} Ausrüstungsplätze noch nicht lesbar"] = "{n} equipment slots not readable yet",
    ["Alles verzaubert und alle Sockel besetzt."] = "Everything enchanted and every socket filled.",
    ["{n} Verzauberungen sind noch nicht bewertet."] = "{n} enchants are not rated yet.",
    ["{n} leere Slots"] = "{n} empty slots",
    ["keine fehlenden Verzauberungen oder leeren Sockel."] = "no missing enchants or empty sockets.",
    ["Verzauberung {id}"] = "Enchant {id}",
    [", von {name}"] = ", by {name}",
    ["Quelle: {quelle}"] = "Source: {quelle}",
    ["Weitere {n} Abmeldungen sind gespeichert."] = "There are {n} more stored absences.",
    ["Weitere {n} ausgeblendete Spieler sind vorhanden."] = "There are {n} more hidden players.",
    ["|cff7ac943Automatik aktiv:|r keine Bewertungen hinterlegt, deshalb gilt jede vorhandene Verzauberung als in Ordnung. Gemeldet werden fehlende Verzauberungen und leere Sockel."]
        = "|cff7ac943Automatic mode:|r no ratings stored, so every existing enchant counts as fine. Missing enchants and empty sockets are still reported.",
    ["|cffffb840Der Regelsatz ist noch leer: fehlende Verzauberungen und leere Sockel werden exakt erkannt, vorhandene Verzauberungen bleiben \"Unbekannt\".|r"]
        = "|cffffb840The rule set is still empty: missing enchants and empty sockets are detected exactly, existing enchants stay \"Unknown\".|r",
    ["Eigene Ausrüstung automatisch geprüft."] = "Own gear audited automatically.",
    ["{n} geprüft, davon {m} ohne Funde"] = "{n} audited, {m} of them without findings",
    ["{n} fehlende Verzauberungen"] = "{n} missing enchants",
    ["{n} leere Sockel"] = "{n} empty sockets",
    ["Regelsatz v{v} ({n})"] = "Rule set v{v} ({n})",
    ["{n} eigene Bewertungen"] = "{n} own ratings",
    ["1 eigene Bewertung"] = "1 own rating",
    ["Unbewertetes gilt als in Ordnung."] = "Unrated enchants count as fine.",
    ["Weitere {n} Vorschläge sind vorhanden."] = "There are {n} more suggestions.",
    ["{n} Tage offline"] = "{n} days offline",

    -- Bewertungsgruende der Ausruestungspruefung.
    ["Keine Verzauberung auf einem Pflichtslot."] = "No enchant on a mandatory slot.",
    ["Kein Gegenstand angelegt."] = "No item equipped.",
    ["Gegenstandsdaten noch nicht vollständig geladen."] = "Item data not fully loaded yet.",
    ["Verzaubert: {name}  •  automatisch anerkannt"] = "Enchanted: {name}  •  auto-approved",
    ["Verzaubert: {name}"] = "Enchanted: {name}",
    ["Verzauberung {id} ist in der Regelliste noch nicht bewertet."] = "Enchant {id} is not rated in the rule list yet.",
    ["Regel für alle Specs"] = "Rule for all specs",
    ["Regel für {spec}"] = "Rule for {spec}",
    ["{grund}: zählt nicht als Fund."] = "{grund}: does not count as a finding.",

    -- === Teilschritt 4: Kern-Chatmeldungen (mit Platzhaltern) ==============
    ["v{v} geladen. Öffnen mit |cffffffff/gcp|r."] = "v{v} loaded. Open with |cffffffff/gcp|r.",
    ["Raidsitzung gestartet. Anwesenheit und Auswertung laufen mit."] = "Raid session started. Attendance and review are being recorded.",
    ["Es läuft bereits eine Sitzung."] = "A session is already running.",
    ["Die Raidsitzung läuft bereits – gestartet von {name}."] = "The raid session is already running – started by {name}.",
    ["Raidsitzung beendet. {n} Teilnehmer ausgewertet – die Auswertung steht unten in der Liste."] = "Raid session ended. {n} participants reviewed – the review is in the list below.",
    ["Wartezeit abgelaufen: {rezept} ({charakter}) – wieder herstellbar."] = "Cooldown expired: {rezept} ({charakter}) – craftable again.",
    ["… und {n} weitere abgelaufene Wartezeiten."] = "… and {n} more expired cooldowns.",
    ["{beruf}: {geprueft} Einträge geprüft, {gespeichert} Rezepte gespeichert."] = "{beruf}: {geprueft} entries checked, {gespeichert} recipes saved.",
}

-- Die Vorgabe entscheidet die Clientsprache: Alles, was nicht Deutsch ist,
-- bekommt Englisch - eine franzoesische Uebersetzung gibt es nicht, und
-- Englisch versteht dort jeder eher als Deutsch. Darueber liegt die
-- Sprachwahl aus den Einstellungen (Automatisch/Deutsch/English); sie wird
-- nach dem Laden der SavedVariables angewandt, denn die liegen zur Ladezeit
-- dieser Datei noch nicht vor.
local locale = type(GetLocale) == "function" and tostring(GetLocale() or "") or "deDE"
GC.LocaleEnglishDefault = locale:find("^de") == nil
GC.LocaleEnglish = GC.LocaleEnglishDefault

-- Wendet die gespeicherte Sprachwahl an. Aufgerufen von der Datenbank direkt
-- nach dem Laden (VOR dem Aufbau der Oberflaeche - die Reihenfolge der
-- ADDON_LOADED-Rueckrufe folgt der Ladereihenfolge der Dateien) und vom
-- Schalter in den Einstellungen. Bereits gebaute Beschriftungen behalten
-- ihre Sprache; vollstaendig wirkt eine Umstellung deshalb erst nach dem
-- Neuladen der Oberflaeche - der Schalter sagt das dazu.
function GC.ApplyLanguageSetting()
    local settings = GC.DB and GC.DB.data and GC.DB.data.settings
    local language = settings and settings.language or "AUTO"
    if language == "DE" then
        GC.LocaleEnglish = false
    elseif language == "EN" then
        GC.LocaleEnglish = true
    else
        GC.LocaleEnglish = GC.LocaleEnglishDefault
    end
end

function GC.L(text)
    if not GC.LocaleEnglish or type(text) ~= "string" then
        return text
    end
    return english[text] or text
end

-- Uebersetzt und fuellt {platzhalter}. Fuer Meldungen mit Namen und Zahlen:
-- Der Schluessel bleibt ein fester Satz, die Werte kommen zur Laufzeit.
--
-- EIN Durchlauf ueber die Vorlage, jeder Platzhalter genau einmal ersetzt.
-- Der frueher zeilenweise Weg (ein gsub je Schluessel) hatte zwei Fehler, die
-- beide daran hingen, dass ein bereits eingesetzter Wert erneut durchsucht
-- wurde: Enthielt ein Wert selbst {einanderer} - etwa eine Gildenbeschreibung
-- mit der Zeichenfolge "{raidzeiten}" -, ersetzte ihn ein spaeterer Durchlauf,
-- und WELCHER zuerst kam, entschied die zufaellige pairs-Reihenfolge. Dasselbe
-- Ergebnis fiel damit von Aufruf zu Aufruf anders aus.
--
-- Der Callback-Weg setzt jeden Platzhalter an seiner Fundstelle ein und liest
-- den eingesetzten Text nicht erneut. Ein Prozentzeichen im Wert bleibt dabei
-- ohnehin ein Prozentzeichen - die Rueckgabe einer gsub-Funktion wird nicht als
-- Ersetzungsmuster ausgewertet -, das haendische %%-Escaping entfaellt.
-- Unbekannte Platzhalter bleiben unangetastet stehen, wie bisher.
function GC.LFormat(text, values)
    text = GC.L(text)
    values = values or {}
    return (text:gsub("{([%w_]+)}", function(key)
        local value = values[key]
        if value == nil then
            return nil
        end
        return tostring(value)
    end))
end
