local _, GC = ...

GC.UI = {
    pages = {},
    tabs = {},
    activePage = "ROSTER",
    -- Gewaehlt wird ein INTERESSENT, nicht eine Listenzeile. Der Listenplatz
    -- taugt dafuer nicht: Eine eingehende Fluesternachricht schiebt einen neuen
    -- Eintrag ganz nach vorne, und alles darunter rutscht eine Position weiter.
    -- Wer gerade an Nummer drei schrieb, hatte danach jemand anderen ausgewaehlt
    -- - der Entwurf blieb stehen und waere an den Falschen gegangen.
    selectedLeadKey = nil,
}

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local CLASS_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

local THEME = {
    window = { 0.035, 0.047, 0.066, 0.98 },
    sidebar = { 0.055, 0.070, 0.094, 0.98 },
    card = { 0.075, 0.091, 0.118, 0.96 },
    cardHover = { 0.095, 0.119, 0.150, 1 },
    input = { 0.025, 0.035, 0.050, 1 },
    border = { 0.17, 0.21, 0.27, 1 },
    accent = { 0.18, 0.78, 0.86, 1 },
    accentDark = { 0.09, 0.39, 0.46, 1 },
    text = { 0.93, 0.96, 1.00, 1 },
    muted = { 0.57, 0.64, 0.72, 1 },
    success = { 0.35, 0.90, 0.58, 1 },
    warning = { 1.00, 0.72, 0.25, 1 },
    danger = { 1.00, 0.38, 0.40, 1 },
}

-- Die eine Quelle aller Chatbefehle: Hilfe im Chat, Addon-Optionen und die
-- Karte auf der Einstellungsseite lesen alle hier. Zwei Listen liefen
-- auseinander (Lektion aus 0.9.47).
local SLASH_COMMANDS = {
    { command = "/gcp", description = "öffnet und schließt Guild Copilot" },
    { command = "/gcp ver", description = "prüft, wer in Gruppe oder Gilde das Addon hat und in welcher Version" },
    { command = "/gcp welcome", description = "öffnet den Einrichtungsassistenten mit der Funktionstour" },
    { command = "/gcp recruite", description = "blendet den Werbebalken ein oder aus" },
    { command = "/gcp debug", description = "misst die Laufzeit; ein zweiter Aufruf zeigt das Ergebnis" },
    { command = "/gcp help", description = "zeigt diese Liste im Chat" },
    { command = "/gcp raidcheck", description = "erfasst außerhalb des Kampfes Gruppen-Buffs und eigene Verbrauchsvorräte" },
}

-- Masse der Seitenleiste. Sie muessen zur Fensterhoehe passen: kommt ein
-- Navigationspunkt dazu, prueft tests/validate.mjs, ob noch alles hineinpasst.
-- Die Hoehe des Hauptfensters steht zweimal: beim Aufbau als feste Zahl (dort
-- liest tests/validate.mjs sie ab, um Seitenhoehen nachzurechnen) und hier,
-- weil das Minimieren sie wechselt und wieder zuruecksetzen muss. Der Test
-- haelt beide Zahlen gleich.
local WINDOW_HEIGHT = 690

local NAV_TOP = 10
local NAV_SECTION_GAP = 3
local NAV_SECTION_HEIGHT = 22
local NAV_TAB_HEIGHT = 32
-- 32 statt 34 seit der Raidsuche: Die Leiste war bis auf 24 px voll, der
-- fuenfzehnte Punkt brauchte 34. Zwei Pixel weniger Abstand je Reiter sind
-- nicht zu sehen und schaffen genau einen Platz - es ist der LETZTE. Der
-- naechste Navigationspunkt braucht einen echten Umbau (schmalere
-- Sektionskoepfe oder ein hoeheres Fenster), nicht noch eine Pixelrasur.
local NAV_TAB_SPACING = 32

-- Masse der Profilseite. Ganz oben steht die Checkliste "Erste Schritte", und
-- sie erscheint nur, solange etwas offen ist. Deshalb stehen die Abstaende der
-- Karten hier und nicht verstreut im Aufbau: Kommt die Checkliste dazu oder
-- faellt sie weg, wandern alle Karten darunter um denselben Betrag mit, statt
-- eine Luecke zu lassen. tests/validate.mjs liest diese Tabelle und prueft, ob
-- sich zwei Karten ueberlappen - genau der Fehler aus 0.9.44, nur eine Seite
-- weiter.
local ROSTER_ONBOARDING_HEIGHT = 228
local ROSTER_CARD_GAP = 12
local ROSTER_CONTENT_HEIGHT = 786
local ROSTER_CARDS = {
    { key = "profileCard", top = 0, height = 408 },
    { key = "professionCard", top = 0, height = 408, anchor = "TOPRIGHT" },
    { key = "absenceCard", top = 420, height = 180 },
    { key = "gearCard", top = 612, height = 162 },
}

-- Die Seitenleiste erzaehlt einen Ablauf, keine Merkmalsliste. Von oben nach
-- unten: erst der eigene Charakter, dann die Gilde als Ganzes, dann die drei
-- Arbeitsfelder in der Reihenfolge, in der man sie tatsaechlich benutzt.
--
--   COPILOT       was ICH melde und was daraus wird
--   REKRUTIERUNG  der Trichter: Eckdaten -> Bedarf -> Auswahl -> Werbung ->
--                 Antworten. Genau diese Reihenfolge laeuft man einmal durch,
--                 und "Gildenprofil speichern" springt selbst auf "Vorschlaege"
--   GILDE         die laufenden Dienste an der Gilde
--   RAID          erst die Datenquelle, dann die Auswertung, dann was daraus
--                 folgt: Warcraft Logs liefert Sitzungen und Profile, die
--                 Raidauswertung liest sie, die Ausruestungspruefung zieht die
--                 Konsequenz daraus
--   SYSTEM        Einstellungen, immer zuletzt
--
-- Zwei Aenderungen gegenueber 0.9.85, beide aus derselben Ueberlegung: Der
-- Abschnitt hiess "ROSTER" und trug damit denselben Namen wie der Seiten-
-- schluessel der PROFIL-Seite - zwei verschiedene Dinge, ein Wort. Und
-- "Warcraft Logs" stand darin, obwohl es weder Roster noch Gilde betrifft,
-- sondern die Datenquelle des Raidteils ist.
local TAB_DEFINITIONS = {
    { key = "ROSTER", section = "COPILOT", label = "Profil", icon = "Interface\\Icons\\INV_Misc_GroupLooking" },
    { key = "OVERVIEW", section = "COPILOT", label = "Übersicht", icon = "Interface\\Icons\\INV_Misc_Note_01" },
    { key = "GUILD", section = "REKRUTIERUNG", label = "Gildenprofil", icon = "Interface\\Icons\\INV_Misc_TabardPVP_01" },
    { key = "SUGGESTIONS", section = "REKRUTIERUNG", label = "Vorschläge", icon = "Interface\\Icons\\INV_Misc_Note_05" },
    { key = "RECRUITMENT", section = "REKRUTIERUNG", label = "Klassen & Specs", icon = "Interface\\Icons\\INV_Misc_GroupLooking" },
    { key = "POST", section = "REKRUTIERUNG", label = "Werbung posten", icon = "Interface\\Icons\\INV_Letter_15" },
    { key = "INBOX", section = "REKRUTIERUNG", label = "Postfach", icon = "Interface\\Icons\\INV_Letter_05" },
    { key = "MEMBERCARE", section = "GILDE", label = "Mitgliederpflege", icon = "Interface\\Icons\\INV_Misc_Note_06" },
    { key = "WORKSHOP", section = "GILDE", label = "Gildenwerkstatt", icon = "Interface\\Icons\\INV_Hammer_20" },
    -- Zwei Navigationspunkte auf dieselbe Seite: Die Werkstatt hat zwei
    -- Ansichten, und die Umschalter oben rechts waren aus der Gilde als
    -- "zu versteckt, muss man erstmal wissen" zurueckgekommen. Wer die
    -- Auftraege sucht, findet sie jetzt dort, wo er alles andere auch findet.
    { key = "ORDERS", page = "WORKSHOP", view = "ORDERS", section = "GILDE",
        label = "Gildenaufträge", icon = "Interface\\Icons\\INV_Scroll_03" },
    -- Die RAID-Sektion erzaehlt den Bogen eines Raidabends: erst die Suche
    -- (vorher), dann Datenquelle und Auswertung (nachher), zuletzt die
    -- Konsequenz daraus.
    { key = "RAIDSEARCH", section = "RAID", label = "Raidsuche", icon = "Interface\\Icons\\INV_Misc_Horn_01" },
    -- "requires" nennt ein Modul, ohne das dieser Punkt nicht existiert.
    -- Warcraft Logs ist der einzige Fall: Das CurseForge-Paket liefert
    -- WarcraftLogs.lua nicht mit, weil der Import den Windows-Helfer braucht
    -- und CurseForge keine ausfuehrbaren Dateien im Archiv annimmt. Ohne das
    -- Modul entsteht weder der Reiter noch die Seite dahinter - ein Knopf, der
    -- ins Leere fuehrt, waere schlimmer als kein Knopf.
    { key = "WCL", section = "RAID", label = "Warcraft Logs", icon = "Interface\\Icons\\INV_Misc_Book_09",
        requires = "WarcraftLogs" },
    { key = "STATISTICS", section = "RAID", label = "Raidauswertung", icon = "Interface\\Icons\\INV_Misc_Book_11" },
    { key = "GEAR", section = "RAID", label = "Ausrüstung", icon = "Interface\\Icons\\INV_Chest_Plate06" },
    { key = "SETTINGS", section = "SYSTEM", label = "Einstellungen", icon = "Interface\\Icons\\INV_Gizmo_02" },
}

local function SetTextColor(fontString, color)
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

local function SetTextureColor(texture, color)
    texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

-- Wann eine Postfachnachricht kam. Heute reicht die Uhrzeit - beim Beantworten
-- will man wissen, ob jemand vor zehn Minuten geschrieben hat oder vorletzte
-- Woche, und das Jahr steht dabei nur im Weg.
local function FormatInboxTime(timestamp)
    local value = tonumber(timestamp)
    if not value or value <= 0 then
        return ""
    end
    if date("%Y-%m-%d", value) == date("%Y-%m-%d") then
        return "heute " .. date("%H:%M", value)
    end
    return date("%d.%m. %H:%M", value)
end

-- Wann eine Rezeptsperre fruehestens faellt. Am selben Tag reicht die Uhrzeit;
-- die langen Wartezeiten (Spezialtuche, vier Tage) brauchen das Datum dazu.
--
-- Beschriftet wird immer mit "fruehestens": Der gespeicherte Zeitpunkt ist
-- eine Untergrenze. Hat der Hersteller seitdem erneut hergestellt, ist er
-- spaeter frei - frueher nie.
local function FormatCooldownReady(readyAt)
    local value = tonumber(readyAt)
    if not value or value <= 0 then
        return ""
    end
    if date("%Y-%m-%d", value) == date("%Y-%m-%d") then
        return "frühestens " .. date("%H:%M", value)
    end
    return "frühestens " .. date("%d.%m. %H:%M", value)
end

-- Die Hoehe eines umbrechenden Textes. GetStringHeight liefert je nach
-- Zeitpunkt nur die Hoehe einer Zeile; dann klemmt der Text sichtbar ab ("..").
-- Deshalb wird zusaetzlich aus der Zeichenzahl abgeschaetzt und das Groessere
-- genommen - zu viel Platz ist harmlos, zu wenig schneidet Inhalt ab.
local function WrappedTextHeight(fontString, text, width, lineHeight)
    lineHeight = lineHeight or 15
    local plain = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local measured = tonumber(fontString and fontString.GetStringHeight
        and fontString:GetStringHeight()) or 0
    local lines = 0
    for segment in (plain .. "\n"):gmatch("(.-)\n") do
        lines = lines + math.max(1, math.ceil((#segment + 1) / math.max(12, width / 6.6)))
    end
    return math.max(measured, lines * lineHeight)
end

-- Klassenfarben stehen als RGB in GC.Classes und entsprechen den Blizzard-
-- Vorgaben. Fuer Inline-Text im Chat-Farbformat braucht es sie hexadezimal.
local function ClassColorCode(classFile)
    local classInfo = GC.Classes[classFile or ""]
    if not classInfo or type(classInfo.color) ~= "table" then
        return nil
    end
    return string.format("|cff%02x%02x%02x",
        math.floor((classInfo.color[1] or 1) * 255 + 0.5),
        math.floor((classInfo.color[2] or 1) * 255 + 0.5),
        math.floor((classInfo.color[3] or 1) * 255 + 0.5))
end

-- Name in Klassenfarbe. Ist die Klasse unbekannt, bleibt der Name schlicht -
-- lieber neutral als falsch gefaerbt.
local function ClassColoredName(name, classFile)
    name = tostring(name or "")
    local colorCode = ClassColorCode(classFile)
    if not colorCode then
        return name
    end
    return colorCode .. name .. "|r"
end

local function CreatePanel(parent, color, borderColor, name)
    local panel = CreateFrame("Frame", name, parent, BACKDROP_TEMPLATE)
    panel:SetBackdrop({
        bgFile = WHITE_TEXTURE,
        edgeFile = WHITE_TEXTURE,
        edgeSize = 1,
    })
    local background = color or THEME.card
    local border = borderColor or THEME.border
    panel:SetBackdropColor(background[1], background[2], background[3], background[4] or 1)
    panel:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    return panel
end

local function CreateLabel(parent, text, style)
    style = style or {}
    local font = style.font or (style.title and "GameFontNormalLarge" or "GameFontNormal")
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    -- DIE zentrale Uebersetzungsstelle der Oberflaeche: Karten, Knoepfe und
    -- Schalter bauen ihre Beschriftung alle ueber CreateLabel. Ein Text, der
    -- in der englischen Tabelle steht, erscheint damit uebersetzt, ohne dass
    -- ein Aufrufer angefasst wird; alles andere laeuft unveraendert durch.
    label:SetText(GC.L(text or ""))
    label:SetJustifyH(style.align or "LEFT")
    label:SetJustifyV(style.vertical or "MIDDLE")
    SetTextColor(label, style.color or (style.muted and THEME.muted or THEME.text))
    if style.width then
        label:SetWidth(style.width)
    end
    if style.height then
        label:SetHeight(style.height)
    end
    -- Umbrechen ist die Ausnahme, nicht die Regel.
    --
    -- Eine umgebrochene Zelle waechst ueber ihre Zeile hinaus und schiebt sich
    -- in die Nachbarzeilen. Genau dieser Fehler ist an vier Stellen unabhaengig
    -- voneinander entstanden - Slot-Tabelle, Mitgliederpflege, Raidauswertung
    -- und Gildenuebersicht -, weil Umbrechen die Voreinstellung war und jede
    -- Tabelle einzeln daran denken musste.
    --
    -- Massgeblich ist, ob der Aufrufer eine feste Hoehe verlangt hat: Wer das
    -- tut, hat sich auf einen Kasten festgelegt, und daraus soll nichts
    -- herauswachsen. Ohne Hoehe darf eine Beschriftung weiter mitwachsen -
    -- freistehende Meldungen wie Importergebnisse leben davon.
    --
    -- Ausdruecklich mehrzeilig bleibt, was sich als Textblock zu erkennen
    -- gibt: ueber "vertical = TOP", das Hilfetexte ohnehin setzen, oder ueber
    -- ein ausdrueckliches "multiline" bei fester Hoehe.
    local wraps = style.multiline == true
        or style.vertical == "TOP"
        or style.height == nil
    if not wraps and label.SetWordWrap then
        label:SetWordWrap(false)
    end
    return label
end

-- Ein Fortschrittsbalken aus zwei Flächen: Rahmen und Füllung. Die Füllung
-- hängt links an und wächst nach rechts; sie liegt über dem Hintergrund des
-- Rahmens, weil eine Textur ihres Elternrahmens sonst darunter verschwindet -
-- dieselbe Lektion wie beim Häkchen im Kanalkästchen.
local function CreateProgressBar(parent, width, height)
    local bar = CreatePanel(parent, THEME.input, THEME.border)
    bar:SetSize(width, height)
    bar.innerWidth = math.max(1, width - 2)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
    bar.fill:SetWidth(bar.innerWidth)
    SetTextureColor(bar.fill, THEME.accent)

    -- Der Anteil steht als Zahl daneben: Ein Balken allein beantwortet "wie
    -- weit noch" nur ungefähr, und genau das ist hier die Frage.
    function bar:SetProgress(fraction, color)
        fraction = math.max(0, math.min(1, tonumber(fraction) or 0))
        self.fraction = fraction
        self.fill:SetWidth(math.max(1, self.innerWidth * fraction))
        self.fill:SetShown(fraction > 0)
        SetTextureColor(self.fill, color or THEME.accent)
    end

    bar:SetProgress(0)
    return bar
end

-- Tooltips an Tabellenzeilen hingen fest rechts. Steht das Fenster am rechten
-- Bildschirmrand, laeuft der Tooltip hinaus - und abgeschnitten wird die
-- rechte Spalte, also ausgerechnet die Zahlen. Die Seite wird deshalb nach
-- verfuegbarem Platz gewaehlt.
local function AnchorRowTooltip(frame)
    if not GameTooltip then
        return false
    end
    GameTooltip:SetOwner(frame, "ANCHOR_NONE")
    GameTooltip:SetClampedToScreen(true)
    GameTooltip:ClearAllPoints()

    -- GetRight liefert Koordinaten im Massstab des jeweiligen Rahmens. Ohne
    -- Umrechnung auf Bildschirmeinheiten vergleicht man zwei verschiedene
    -- Systeme, und die Entscheidung faellt falsch aus.
    local right = (frame:GetRight() or 0) * (frame:GetEffectiveScale() or 1)
    local screenRight = (UIParent:GetRight() or 0) * (UIParent:GetEffectiveScale() or 1)
    if screenRight - right < 340 * (UIParent:GetEffectiveScale() or 1) then
        GameTooltip:SetPoint("TOPRIGHT", frame, "TOPLEFT", -8, 0)
    else
        GameTooltip:SetPoint("TOPLEFT", frame, "TOPRIGHT", 8, 0)
    end
    return true
end

local function CreatePageTitle(page, title, subtitle)
    -- Uebersetzt wird zentral: Jede Seite meldet Titel und Untertitel durch
    -- diese eine Stelle an, die Tabellenzeilen stehen in Locales.lua. Ein
    -- dynamisch zusammengesetzter Untertitel uebersetzt sich am Aufrufer
    -- ueber einen Platzhalter-Schluessel und laeuft hier unveraendert durch.
    local heading = CreateLabel(page, GC.L(title), { title = true })
    heading:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    local help = CreateLabel(page, GC.L(subtitle), { muted = true, width = 770, height = 32, vertical = "TOP" })
    help:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -7)
    return heading, help
end

-- "secure" macht aus dem Knopf einen sicheren Knopf: Er kann einen Zauber
-- wirken (das Berufsfenster oeffnen), was WoW nur bei einem echten Tastendruck
-- erlaubt. Der eigene Handler haengt dann an PostClick statt an OnClick - die
-- Vorlage belegt OnClick selbst, und wer ihn ueberschreibt, nimmt dem Knopf
-- genau die Faehigkeit, fuer die er sicher ist.
local function CreateButton(parent, text, width, height, onClick, kind, secure)
    local button = CreateFrame("Button", nil, parent,
        secure and "SecureActionButtonTemplate" or nil)
    button:SetSize(width or 130, height or 34)
    if secure then
        button:SetAttribute("type", "spell")
        if button.RegisterForClicks then
            button:RegisterForClicks("AnyDown", "AnyUp")
        end
    end
    button.kind = kind or "SECONDARY"
    button.background = button:CreateTexture(nil, "BACKGROUND")
    button.background:SetAllPoints()
    button.border = button:CreateTexture(nil, "BORDER")
    button.border:SetPoint("TOPLEFT", -1, 1)
    button.border:SetPoint("BOTTOMRIGHT", 1, -1)
    button.border:SetColorTexture(THEME.border[1], THEME.border[2], THEME.border[3], 1)
    button.background:SetDrawLayer("BORDER", 1)
    -- Eine Beschriftung bricht in einem Knopf nie um. Ein Knopf hat eine feste
    -- Höhe; eine zweite Zeile wächst darüber hinaus und legt sich über den
    -- Nachbarn. Genau so sah die Sitzungsliste aus: "02.08. 19:37 Höhle des
    -- Schlangenschreins +Logs" passte nicht in eine Zeile, brach um und
    -- überlagerte den nächsten Eintrag. Zu lang heißt jetzt abgeschnitten,
    -- nicht ineinandergeschoben.
    button.label = CreateLabel(button, text, { align = "CENTER", height = height or 34 })
    button.label:SetAllPoints()
    button.active = false

    function button:SetText(value)
        -- Auch spaetere Umbeschriftungen ("Sitzung beenden", "Wirklich
        -- löschen?") laufen durch die Sprachschicht; zusammengesetzte Texte
        -- treffen keinen Schluessel und bleiben unveraendert.
        self.label:SetText(GC.L(value or ""))
    end

    function button:SetActive(active)
        self.active = active == true
        if self.active or self.kind == "PRIMARY" then
            SetTextureColor(self.background, self.active and THEME.accent or THEME.accentDark)
            self.label:SetTextColor(1, 1, 1)
        else
            SetTextureColor(self.background, THEME.card)
            SetTextColor(self.label, THEME.text)
        end
    end

    button:SetActive(false)
    button:SetScript("OnEnter", function(self)
        if not self.active then
            SetTextureColor(self.background, THEME.cardHover)
        end
    end)
    button:SetScript("OnLeave", function(self)
        self:SetActive(self.active)
    end)
    button:SetScript(secure and "PostClick" or "OnClick", onClick)
    return button
end

-- === Eigene Symbole =======================================================
--
-- Die WoW-Schrift kennt nur den WinANSI-Vorrat. Alles darueber hinaus -
-- "📅", "◀", "←" - zeichnet der Client als leeren Kasten. Genau das stand
-- zuletzt in den beiden Datumsfeldern der Abmeldung, und an drei Stellen im
-- Code steht deshalb schon der Hinweis "kein Pfeilzeichen, nimm ein Wort".
-- Fuer Saetze taugt das, fuer einen Knopf von 26 Pixeln nicht.
--
-- Blizzards fertige Symbole waeren der andere Weg. Sie sind der Grund, warum
-- neben "Bestaetigen" bisher ein goldenes Haekchen stand: gemalt, gerahmt,
-- glaenzend - in dieser flachen Oberflaeche ein Fremdkoerper.
--
-- Die paar Zeichen, die diese Oberflaeche braucht, malt sie deshalb selbst,
-- aus derselben weissen Flaeche, aus der schon Rahmen, Karten und Knoepfe
-- bestehen. Sie nehmen die Themenfarbe an, koennen nicht fehlen und sehen auf
-- jedem Rechner gleich aus.

-- Ein Symbol ist ein eigener kleiner Rahmen und wird gesetzt wie jedes andere
-- Bedienelement. Rahmen und nicht Textur aus einem Grund: Ein Kindrahmen liegt
-- immer ueber den Flaechen seines Elternteils, eine Textur nicht - daran ist
-- das Haekchen der Kaestchen bisher gescheitert.
--
-- Beschrieben wird jede Form im Feld 0..1 der Kantenlaenge; damit bleibt sie
-- in jeder Groesse dieselbe.
local function CreateMark(parent, size)
    local mark = CreateFrame("Frame", nil, parent)
    mark:SetSize(size, size)
    mark.size = size
    mark.pieces = {}

    -- x, y, Breite, Hoehe als Anteil der Kantenlaenge; y zaehlt von oben.
    function mark:AddArea(x, y, width, height)
        local piece = self:CreateTexture(nil, "OVERLAY")
        piece:SetSize(math.max(1, width * self.size), math.max(1, height * self.size))
        piece:SetPoint("TOPLEFT", self, "TOPLEFT", x * self.size, -y * self.size)
        self.pieces[#self.pieces + 1] = piece
        return piece
    end

    -- Ein schraeger Strich, bevorzugt als EINE gedrehte Flaeche: Der Client
    -- kann die vier Eckpunkte einer Flaeche einzeln versetzen
    -- (SetVertexOffset), und vier versetzte Ecken sind ein glatter Balken in
    -- beliebiger Richtung. Die fruehere Reihe ueberlappender Quadrate - dem
    -- Irrtum geschuldet, eine gedrehte Flaeche gebe die Oberflaeche nicht
    -- her - war ab etwa 20 px Kantenlaenge sichtbar getreppt; genau so wurde
    -- der Haken neben "Bestätigen" gemeldet ("verpixelt"). Sie bleibt als
    -- Rueckfall fuer Clients ohne SetVertexOffset.
    function mark:AddStroke(fromX, fromY, toX, toY, thickness)
        local piece = self:CreateTexture(nil, "OVERLAY")
        if piece.SetVertexOffset then
            local size = self.size
            local dx = (toX - fromX) * size
            local dy = (fromY - toY) * size
            local length = math.sqrt(dx * dx + dy * dy)
            local ux, uy = dx / length, dy / length
            local half = thickness * size * 0.5
            -- Halbe Strichstaerke ueber beide Enden hinaus (eckige Kappen):
            -- So stossen zwei Striche im Knick ohne Kerbe aneinander, und
            -- der Umriss bleibt derselbe wie bei der alten Quadratreihe.
            local x1 = fromX * size - ux * half
            local y1 = -fromY * size - uy * half
            local x2 = toX * size + ux * half
            local y2 = -toY * size + uy * half
            local nx, ny = -uy * half, ux * half
            piece:SetSize(1, 1)
            piece:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
            -- Versaetze sind je Ecke relativ zu ihrer Ausgangslage; die
            -- Ausgangsecken des 1x1-Quads liegen bei (0,0), (0,-1), (1,0)
            -- und (1,-1). Reihenfolge: oben links, unten links, oben
            -- rechts, unten rechts.
            piece:SetVertexOffset(1, x1 + nx, y1 + ny)
            piece:SetVertexOffset(2, x1 - nx, y1 - ny + 1)
            piece:SetVertexOffset(3, x2 + nx - 1, y2 + ny)
            piece:SetVertexOffset(4, x2 - nx - 1, y2 - ny + 1)
            self.pieces[#self.pieces + 1] = piece
            return
        end
        -- Rueckfall: Reihe ueberlappender Quadrate. Der Abstand ist die
        -- halbe Strichstaerke - weiter auseinander zerfaellt die Linie
        -- sichtbar in Punkte, enger kostet nur Flaechen ohne Gewinn.
        piece:Hide()
        local steps = math.max(1, math.ceil(
            math.max(math.abs(toX - fromX), math.abs(toY - fromY)) / (thickness * 0.5)))
        for step = 0, steps do
            local part = step / steps
            self:AddArea(
                fromX + (toX - fromX) * part - thickness * 0.5,
                fromY + (toY - fromY) * part - thickness * 0.5,
                thickness, thickness)
        end
    end

    function mark:SetColor(color)
        self.color = color
        for _, piece in ipairs(self.pieces) do
            SetTextureColor(piece, color)
        end
    end

    return mark
end

-- Der Mauszeiger in UIParent-Einheiten. Steht hier oben, weil ihn zwei
-- weit auseinanderliegende Stellen brauchen: der Griff zum Ziehen der
-- Fenstergroesse und das Minimap-Symbol.
local function UIScale()
    return (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
end

local function CursorInUISpace()
    if type(GetCursorPosition) ~= "function" then
        return nil, nil
    end
    local cursorX, cursorY = GetCursorPosition()
    if not cursorX or not cursorY then
        return nil, nil
    end
    local scale = UIScale()
    return cursorX / scale, cursorY / scale
end

-- Eine EditBox, deren Elternteil versteckt wird, behaelt in WoW den
-- Tastaturfokus. Wer also in ein Feld geklickt hatte (bei der Spruchvorschau
-- der Raidsuche genuegt ein Klick auf den Kasten) und dann minimierte, die
-- Seite wechselte oder das Fenster schloss, fuetterte ab da ein unsichtbares
-- Feld: kein Laufen, kein Chat - "keine Eingaben mehr", wie aus der Gilde
-- gemeldet. Geloest wird deshalb an genau diesen drei Stellen jeder Fokus,
-- der IM EIGENEN Fenster haengt. Fremde Eingabefelder (die Chat-Eingabe!)
-- bleiben unangetastet - deshalb die Elternkette statt eines blinden
-- ClearFocus.
local function ReleaseOwnKeyboardFocus(root)
    if type(GetCurrentKeyBoardFocus) ~= "function" or not root then
        return
    end
    local focus = GetCurrentKeyBoardFocus()
    if not focus or type(focus.ClearFocus) ~= "function" then
        return
    end
    local frame = focus
    while frame do
        if frame == root then
            focus:ClearFocus()
            return
        end
        frame = frame.GetParent and frame:GetParent() or nil
    end
end

-- Alle eigenen Eingabefelder, damit sich ihr Fokus notfalls ohne die
-- GetCurrentKeyBoardFocus-API (im Anniversary-Client unzuverlaessig) freigeben
-- laesst: ConfigureEdit traegt jedes Feld hier ein, ClearOwnEditFocus raeumt
-- beim Minimieren, Seitenwechsel und Schliessen auf. Ein fremdes Feld (die
-- Chat-Eingabe) steht nie in dieser Liste.
local ownEdits = {}
local function ClearOwnEditFocus()
    for _, edit in ipairs(ownEdits) do
        if edit.ClearFocus and edit.HasFocus and edit:HasFocus() then
            edit:ClearFocus()
        end
    end
end

-- Minimieren und Wiederherstellen: der waagerechte Strich und das Rechteck,
-- die jedes Fenster seit dreissig Jahren traegt.
local function CreateMinimizeMark(parent, size, color)
    local mark = CreateMark(parent, size)
    mark:AddArea(0.18, 0.70, 0.64, 0.12)
    mark:SetColor(color or THEME.text)
    return mark
end

local function CreateRestoreMark(parent, size, color)
    local mark = CreateMark(parent, size)
    mark:AddArea(0.18, 0.24, 0.64, 0.10)
    mark:AddArea(0.18, 0.76, 0.64, 0.10)
    mark:AddArea(0.18, 0.24, 0.10, 0.62)
    mark:AddArea(0.72, 0.24, 0.10, 0.62)
    mark:SetColor(color or THEME.text)
    return mark
end

-- Griff zum Ziehen: drei Schraegstriche in der Ecke, wie sie jeder kennt.
local function CreateResizeMark(parent, size, color)
    local mark = CreateMark(parent, size)
    mark:AddStroke(0.12, 0.96, 0.96, 0.12, 0.10)
    mark:AddStroke(0.44, 0.96, 0.96, 0.44, 0.10)
    mark:AddStroke(0.76, 0.96, 0.96, 0.76, 0.10)
    mark:SetColor(color or THEME.muted)
    return mark
end

-- Haekchen: kurzer Strich nach unten, langer nach oben.
local function CreateCheckMark(parent, size, color)
    local mark = CreateMark(parent, size)
    mark:AddStroke(0.24, 0.52, 0.44, 0.74, 0.20)
    mark:AddStroke(0.44, 0.74, 0.80, 0.26, 0.20)
    mark:SetColor(color or THEME.success)
    return mark
end

-- Kalenderblatt: zwei Oesen, Kopfleiste, Rahmen, sechs Tagesfelder. Weniger
-- ist nicht wiederzuerkennen, mehr laeuft bei dieser Groesse ineinander.
local function CreateCalendarMark(parent, size, color)
    local mark = CreateMark(parent, size)
    mark:AddArea(0.26, 0.00, 0.10, 0.18)
    mark:AddArea(0.64, 0.00, 0.10, 0.18)
    mark:AddArea(0.06, 0.10, 0.88, 0.12)
    mark:AddArea(0.06, 0.22, 0.08, 0.72)
    mark:AddArea(0.86, 0.22, 0.08, 0.72)
    mark:AddArea(0.06, 0.86, 0.88, 0.08)
    for column = 0, 2 do
        for row = 0, 1 do
            mark:AddArea(0.22 + column * 0.22, 0.36 + row * 0.24, 0.12, 0.14)
        end
    end
    mark:SetColor(color or THEME.accent)
    return mark
end

-- Dreieck aus waagerechten Streifen. Die Spitze bleibt ein kurzer Stummel,
-- sonst verschwindet sie bei diesen Kantenlaengen ganz.
local ARROW_MARK_ROWS = 7

local function CreateArrowMark(parent, size, direction, color)
    local mark = CreateMark(parent, size)
    local thickness = 0.70 / ARROW_MARK_ROWS
    local middle = (ARROW_MARK_ROWS - 1) / 2
    for row = 0, ARROW_MARK_ROWS - 1 do
        local width = 0.10 + 0.56 * (1 - math.abs(row - middle) / middle)
        mark:AddArea(
            direction == "LEFT" and (0.76 - width) or 0.24,
            0.15 + row * thickness,
            width, thickness)
    end
    mark:SetColor(color or THEME.text)
    return mark
end

-- Ein Knopf traegt entweder Text oder ein Symbol. Beides zugleich passt in die
-- Kantenlaengen nicht, um die es hier ueberhaupt geht.
local function SetButtonMark(button, mark)
    button:SetText(GC.L(""))
    mark:ClearAllPoints()
    mark:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.mark = mark
    return button
end

-- Ein Knopf IM Eingabefeld - das Kalendersymbol der Abmeldung, das × der
-- Rezeptsuche.
--
-- Zwei Dinge muessen dafuer stimmen, und beide standen bisher nicht da:
--
-- 1. Der Knopf braucht eine hoehere Rahmenebene als die EditBox. Beide sind
--    Kinder desselben Rahmens und lagen damit auf derselben Ebene; wer bei
--    Gleichstand den Klick bekommt, ist nicht festgelegt, und in der Praxis
--    fing ihn die EditBox ab. Anklickbar blieb genau der Rand, den die EditBox
--    NICHT bedeckt: ihre Innenabstaende von zehn Pixeln rechts und sechs oben
--    und unten - also ein schmaler Streifen und die untere rechte Ecke. Genau
--    so wurde es gemeldet: "in der Mitte geht es nicht".
-- 2. Der Text muss vor dem Knopf enden, sonst laeuft er darunter hindurch.
--
-- Der Knopf zieht deshalb ins Feld um: als Kind der Umrandung, mit eigener
-- Ebene darueber, und die EditBox macht ihm Platz.
local function AttachEditButton(edit, button, buttonWidth, gap)
    gap = gap or 4
    button:SetParent(edit.container)
    button:ClearAllPoints()
    button:SetPoint("RIGHT", edit.container, "RIGHT", -gap, 0)
    local containerLevel = (edit.container.GetFrameLevel and edit.container:GetFrameLevel()) or 1
    button:SetFrameLevel(containerLevel + 10)
    edit:SetPoint("BOTTOMRIGHT", edit.container, "BOTTOMRIGHT",
        -(gap + (tonumber(buttonWidth) or 20) + 4), 6)
    return button
end

-- Live, per Addon verteilt oder aus Warcraft Logs nachgereicht.
local SESSION_SOURCE_LABEL = {
    LIVE = "Live",
    SYNC = "Addon-Sync",
    WCL = "Warcraft Logs",
    LOG = "Combat Log",
}

-- Kurzzeichen für die Sitzungsliste. Dort ist kein Platz für ganze Wörter, und
-- sie erscheinen nur, wenn derselbe Abend aus mehreren Quellen vorliegt.
local SESSION_SOURCE_MARK = {
    LIVE = "Live",
    SYNC = "Sync",
    WCL = "Logs",
    LOG = "Datei",
    REPAIR = "Ergänzt",
}

-- Eine Quelle trägt seit 0.9.89 den Aufzeichner: "SYNC:Alex". Für die
-- Beschriftung zählt die Art, für die Unterscheidung mehrerer fremder
-- Mitschnitte desselben Abends der Name dahinter.
local function SessionSourceName(source)
    return tostring(source or ""):match("^[^:]+:(.+)$")
end

local function SessionSourceLabel(source)
    local kind = GC.RaidMonitor:SourceKind(source)
    local label = SESSION_SOURCE_LABEL[kind] or tostring(source or "Unbekannt")
    local who = SessionSourceName(source)
    return who and (label .. " (" .. who .. ")") or label
end

local function SessionSourceMark(source)
    local kind = GC.RaidMonitor:SourceKind(source)
    return SESSION_SOURCE_MARK[kind] or "?", SessionSourceName(source)
end

-- Quellen, deren Anwesenheit reine Encounter-Zeit ist. Beginn und Ende
-- beschreiben dort den ganzen Abend samt Pausen und Trash; ein Prozentwert
-- gegen diese Gesamtdauer waere fuer jeden Teilnehmer viel zu niedrig.
local ENCOUNTER_TIME_SOURCES = {
    WCL = true,
    LOG = true,
}

local function SetButtonEnabled(button, enabled)
    if enabled then
        button:Enable()
    else
        button:Disable()
    end
    button.label:SetAlpha(enabled and 1 or 0.45)
    -- Traegt der Knopf ein Symbol statt einer Beschriftung, muss das Symbol
    -- mit abblenden: Sonst sieht ein gesperrter Seitenwechsel bedienbar aus.
    if button.mark then
        button.mark:SetAlpha(enabled and 1 or 0.45)
    end
end

local function CreateToggle(parent, text, onClick)
    local toggle = CreateFrame("CheckButton", nil, parent)
    toggle:SetSize(22, 22)
    toggle.box = CreatePanel(toggle, THEME.input)
    toggle.box:SetAllPoints()
    -- Das Haekchen gehoert in den Kasten, nicht auf den Schalter.
    --
    -- Es lag hier als Textur auf dem Schalter, der Kasten darueber ist ein
    -- Kindrahmen - und ein Kindrahmen deckt die Flaechen seines Elternteils ab,
    -- gleich welche Zeichenebene die Textur angibt. Das Haekchen war damit in
    -- jedem Kaestchen der Oberflaeche unsichtbar; angekreuzt erkannte man nur
    -- noch an der Fuellung. Gezeichnet wird es dunkel: Die Fuellung eines
    -- angekreuzten Kastens ist hell, und ein helles Haekchen darauf waere
    -- wieder eins, das man suchen muss.
    toggle.mark = CreateCheckMark(toggle.box, 16, THEME.window)
    toggle.mark:SetPoint("CENTER", toggle.box, "CENTER", 0, 0)
    toggle.text = CreateLabel(toggle, text)
    toggle.text:SetPoint("LEFT", toggle, "RIGHT", 8, 0)

    function toggle:RefreshVisual()
        local checked = not not self:GetChecked()
        if checked then
            self.mark:Show()
            self.box:SetBackdropColor(THEME.accentDark[1], THEME.accentDark[2], THEME.accentDark[3], 1)
            SetTextColor(self.text, THEME.text)
        else
            self.mark:Hide()
            self.box:SetBackdropColor(THEME.input[1], THEME.input[2], THEME.input[3], 1)
            SetTextColor(self.text, THEME.muted)
        end
        local color = checked and THEME.accent or THEME.border
        self.box:SetBackdropBorderColor(color[1], color[2], color[3], 1)
    end

    toggle:SetScript("OnClick", function(self)
        self:RefreshVisual()
        onClick(not not self:GetChecked())
    end)
    toggle:SetScript("OnEnter", function(self)
        if not self:GetChecked() then
            self.box:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.65)
        end
    end)
    toggle:SetScript("OnLeave", function(self)
        self:RefreshVisual()
    end)
    toggle:RefreshVisual()
    return toggle
end

local function SetToggle(toggle, checked)
    toggle:SetChecked(checked == true)
    toggle:RefreshVisual()
end

local function ConfigureEdit(edit, maxLetters)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)
    edit:SetMaxLetters(maxLetters or 2000)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if GC.UI.frame and GC.UI.frame:IsShown() then
            GC.UI.frame:Hide()
        end
    end)
    -- Ein verstecktes Eingabefeld darf die Tastatur nicht behalten.
    --
    -- WoW gibt den Tastaturfokus NICHT von selbst frei, wenn der Elternrahmen
    -- versteckt wird: Wer in ein Feld geklickt hatte und dann minimierte, die
    -- Seite wechselte oder das Fenster schloss, tippte weiter unsichtbar in
    -- dieses Feld - kein Chat, keine Steuerung. Bei einem MEHRZEILIGEN Feld
    -- (der Spruchvorschau der Raidsuche) verschluckt Enter dabei sogar den
    -- Zeilenumbruch, statt das Chatfenster zu oeffnen - genau die
    -- Gildenmeldung "kann kein Chatfenster oeffnen, wenn minimiert".
    --
    -- OnHide feuert auf einem Feld, sobald es unsichtbar wird - auch wenn nur
    -- ein Vorfahre versteckt wurde (Seite, Hauptfenster). Das Feld raeumt
    -- seinen Fokus deshalb hier selbst weg. Das braucht keine
    -- GetCurrentKeyBoardFocus-API (die es im Anniversary-Client nicht
    -- zuverlaessig gibt) und trifft fremde Felder wie die Chat-Eingabe nie -
    -- jedes Feld raeumt nur sich selbst auf.
    edit:HookScript("OnHide", function(self)
        if self.ClearFocus then
            self:ClearFocus()
        end
    end)
    -- Fuer den API-freien Sammelweg (ClearOwnEditFocus).
    ownEdits[#ownEdits + 1] = edit
end

local function CreateEdit(parent, width, height)
    local container = CreatePanel(parent, THEME.input)
    container:SetSize(width, height)
    local edit = CreateFrame("EditBox", nil, container)
    edit:SetPoint("TOPLEFT", container, "TOPLEFT", 10, -6)
    edit:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -10, 6)
    ConfigureEdit(edit, 1000)
    edit.container = container
    return edit
end

-- Ein Zahlenregler aus zwei Knöpfen und einer Anzeige.
--
-- Blizzards Schieberegler brächte sein Rahmenwerk in eine flache Oberfläche,
-- die sich sonst alles selbst malt. Ein Textfeld wie bei der Anzeigedauer
-- brächte ungültige Zwischenstände: Wer „125" tippt, erzeugt unterwegs „1"
-- und „12" - bei einer Fenstergröße, die sofort wirkt, wäre das ein Springen
-- des halben Bildschirms.
local function CreateStepper(parent, minimum, maximum, step, onChanged, suffix)
    local stepper = CreateFrame("Frame", nil, parent)
    stepper:SetSize(146, 28)
    stepper.value = minimum
    -- Ohne Angabe bleibt es die Prozentanzeige der Einstellungen; die
    -- Raidsuche zaehlt mit demselben Regler Plaetze ("25").
    stepper.suffix = suffix or " %"

    function stepper:SetValue(value, announce)
        value = math.floor((tonumber(value) or minimum) / step + 0.5) * step
        value = math.max(minimum, math.min(maximum, value))
        self.value = value
        self.display:SetText(value .. self.suffix)
        SetButtonEnabled(self.down, value > minimum)
        SetButtonEnabled(self.up, value < maximum)
        if announce and onChanged then
            onChanged(value)
        end
    end

    stepper.down = CreateButton(stepper, "–", 28, 28, function()
        stepper:SetValue(stepper.value - step, true)
    end)
    stepper.down:SetPoint("LEFT", stepper, "LEFT", 0, 0)
    stepper.display = CreateLabel(stepper, "", { align = "CENTER", width = 82, height = 28 })
    stepper.display:SetPoint("LEFT", stepper.down, "RIGHT", 0, 0)
    stepper.up = CreateButton(stepper, "+", 28, 28, function()
        stepper:SetValue(stepper.value + step, true)
    end)
    stepper.up:SetPoint("LEFT", stepper.display, "RIGHT", 0, 0)
    stepper:SetValue(minimum)
    return stepper
end

local function CreateModernScrollFrame(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll.track = scroll:CreateTexture(nil, "BACKGROUND")
    scroll.track:SetWidth(3)
    scroll.track:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -8)
    scroll.track:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -6, 8)
    SetTextureColor(scroll.track, { 0.12, 0.15, 0.19, 1 })
    scroll.thumb = scroll:CreateTexture(nil, "ARTWORK")
    scroll.thumb:SetWidth(3)
    SetTextureColor(scroll.thumb, THEME.accent)

    function scroll:UpdateModernThumb()
        local range = self:GetVerticalScrollRange() or 0
        local trackHeight = self.track:GetHeight() or 0
        if range <= 0 or trackHeight <= 0 then
            self.thumb:Hide()
            return
        end
        local visibleHeight = self:GetHeight() or 1
        local thumbHeight = math.max(24, trackHeight * (visibleHeight / (visibleHeight + range)))
        local offset = (self:GetVerticalScroll() / range) * (trackHeight - thumbHeight)
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOP", self.track, "TOP", 0, -offset)
        self.thumb:SetHeight(thumbHeight)
        self.thumb:Show()
    end

    scroll:SetScript("OnScrollRangeChanged", function(self)
        -- Ein veraltetes Animationsziel (Seitenwechsel, neuer Inhalt) darf
        -- den naechsten Radtick nicht an eine alte Position springen lassen.
        self.targetScroll = nil
        self:UpdateModernThumb()
    end)
    scroll:SetScript("OnVerticalScroll", function(self)
        self:UpdateModernThumb()
    end)

    -- Weiches Scrollen: Das Rad setzt nur ein Ziel, ein kurzlebiges OnUpdate
    -- naehert sich ihm exponentiell (bildratenunabhaengig). Vorher sprang die
    -- Position in harten 24-Pixel-Schritten - auf der 1700 Pixel hohen
    -- Einstellungsseite fuehlte sich das stockend an. Das OnUpdate haengt nur
    -- waehrend der Animation am Rahmen; Leerlauf kostet keinen Handleraufruf.
    local function SmoothScrollStep(self, elapsed)
        local current = self:GetVerticalScroll() or 0
        local target = self.targetScroll
        if not target then
            self:SetScript("OnUpdate", nil)
            return
        end
        local difference = target - current
        if math.abs(difference) < 1 then
            self:SetVerticalScroll(target)
            self.targetScroll = nil
            self:SetScript("OnUpdate", nil)
        else
            self:SetVerticalScroll(current
                + (difference * math.min(1, (tonumber(elapsed) or 0) * 14)))
        end
        self:UpdateModernThumb()
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local base = self.targetScroll or self:GetVerticalScroll() or 0
        self.targetScroll = math.max(0,
            math.min(base - (delta * 64), self:GetVerticalScrollRange() or 0))
        self:SetScript("OnUpdate", SmoothScrollStep)
    end)
    return scroll
end

local function CreateTextArea(parent, width, height, maxLetters)
    local container = CreatePanel(parent, THEME.input)
    container:SetSize(width, height)

    local scroll = CreateModernScrollFrame(container)
    scroll:SetPoint("TOPLEFT", container, "TOPLEFT", 10, -9)
    scroll:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -14, 9)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetWidth(width - 34)
    edit:SetHeight(height - 18)
    edit:SetJustifyH("LEFT")
    edit:SetJustifyV("TOP")
    ConfigureEdit(edit, maxLetters or 4000)
    scroll:SetScrollChild(edit)
    edit.container = container
    edit.scrollFrame = scroll

    -- Ein Klick neben den Text traf bisher ins Leere: die EditBox belegt nur
    -- die Fläche innerhalb des Scrollbereichs, Rahmen und Rand gehören ihr
    -- nicht. Man musste also eine passende Stelle treffen, um überhaupt einen
    -- Cursor zu bekommen. Beide reichen den Klick jetzt weiter.
    local function FocusEdit()
        edit:SetFocus()
        edit:SetCursorPosition(edit:GetNumLetters())
    end
    container:EnableMouse(true)
    container:SetScript("OnMouseDown", FocusEdit)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", FocusEdit)

    edit:SetScript("OnCursorChanged", function(_, x, y, cursorWidth, cursorHeight)
        local offset = scroll:GetVerticalScroll()
        local visibleHeight = scroll:GetHeight()
        if -y < offset then
            scroll:SetVerticalScroll(math.max(0, -y))
        elseif (-y + cursorHeight) > (offset + visibleHeight) then
            scroll:SetVerticalScroll((-y + cursorHeight) - visibleHeight)
        end
    end)
    return edit
end

local function CreateCard(parent, title)
    local card = CreatePanel(parent, THEME.card)
    if title then
        card.title = CreateLabel(card, title, { title = true })
        card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -16)
    end
    return card
end

-- === Kalenderauswahl ======================================================
--
-- Anlass war eine Rueckmeldung aus der Gilde: Mit "JJJJ-MM-TT" kommen viele
-- nicht zurecht, und tippen will das ohnehin niemand. Gespeichert wird
-- weiterhin ISO - nur eintippen muss es keiner mehr.
--
-- Bewusst ein eigenes kleines Blatt und nicht Blizzards Kalender: Der ist ein
-- vollstaendiges Fenster mit Gildenereignissen, laedt auf Anforderung nach und
-- laesst sich nicht als Auswahlfeld einspannen.

local MONTH_NAMES = {
    "Januar", "Februar", "März", "April", "Mai", "Juni",
    "Juli", "August", "September", "Oktober", "November", "Dezember",
}
local WEEKDAY_SHORT = { "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" }
local DATE_PICKER_ROWS = 6
local DATE_PICKER_CELL = 30

function GC.UI:BuildDatePicker()
    if self.datePicker then
        return self.datePicker
    end
    local host = self.frame or UIParent
    -- Wie die Auftragsdialoge ein Kind des Hauptfensters mit eigener hoher
    -- Ebene: In der Seite selbst wuerde das Blatt vom ScrollFrame beschnitten.
    local picker = CreatePanel(host, THEME.window, THEME.accent)
    picker:SetSize(7 * DATE_PICKER_CELL + 24, DATE_PICKER_ROWS * DATE_PICKER_CELL + 96)
    local hostLevel = host.GetFrameLevel and host:GetFrameLevel() or 1
    picker:SetFrameLevel((hostLevel or 1) + 90)
    picker:SetBackdropColor(THEME.window[1], THEME.window[2], THEME.window[3], 1)
    picker:EnableMouse(true)
    self.datePicker = picker

    picker.previous = CreateButton(picker, "", 26, 24, function()
        GC.UI:ShiftDatePicker(-1)
    end)
    SetButtonMark(picker.previous, CreateArrowMark(picker.previous, 12, "LEFT"))
    picker.previous:SetPoint("TOPLEFT", picker, "TOPLEFT", 12, -10)
    picker.next = CreateButton(picker, "", 26, 24, function()
        GC.UI:ShiftDatePicker(1)
    end)
    SetButtonMark(picker.next, CreateArrowMark(picker.next, 12, "RIGHT"))
    picker.next:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -12, -10)
    picker.heading = CreateLabel(picker, "", {
        align = "CENTER",
        width = 7 * DATE_PICKER_CELL - 40,
        height = 24,
    })
    picker.heading:SetPoint("TOP", picker, "TOP", 0, -10)

    for index, short in ipairs(WEEKDAY_SHORT) do
        local caption = CreateLabel(picker, short, {
            muted = true,
            align = "CENTER",
            font = "GameFontNormalSmall",
            width = DATE_PICKER_CELL,
            height = 16,
        })
        caption:SetPoint("TOPLEFT", picker, "TOPLEFT",
            12 + (index - 1) * DATE_PICKER_CELL, -40)
    end

    picker.days = {}
    for cell = 1, DATE_PICKER_ROWS * 7 do
        local column = (cell - 1) % 7
        local row = math.floor((cell - 1) / 7)
        local day = CreateButton(picker, "", DATE_PICKER_CELL - 2, DATE_PICKER_CELL - 2, function(button)
            if button.iso then
                GC.UI:ConfirmDatePicker(button.iso)
            end
        end)
        day:SetPoint("TOPLEFT", picker, "TOPLEFT",
            12 + column * DATE_PICKER_CELL, -58 - row * DATE_PICKER_CELL)
        picker.days[cell] = day
    end

    picker.today = CreateButton(picker, "Heute", 70, 24, function()
        GC.UI:ConfirmDatePicker(GC.Util.TodayISO())
    end)
    picker.today:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 12, 10)
    picker.close = CreateButton(picker, "Schließen", 80, 24, function()
        picker:Hide()
    end)
    picker.close:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -12, 10)

    picker:Hide()
    -- Wechselt die Seite oder schliesst das Fenster, geht das Blatt mit zu.
    if host.HookScript then
        host:HookScript("OnHide", function()
            picker:Hide()
        end)
    end
    return picker
end

function GC.UI:RefreshDatePicker()
    local picker = self.datePicker
    if not picker then
        return
    end
    local year, month = picker.year, picker.month
    picker.heading:SetText((MONTH_NAMES[month] or "?") .. " " .. year)

    local daysInMonth = GC.Util.DaysInMonth(year, month) or 30
    -- Wo im Raster faengt der Erste an? WeekdayOfISO zaehlt Montag als 1, das
    -- Raster ebenso - der Versatz ist damit schlicht der Wochentag minus eins.
    local offset = (GC.Util.WeekdayOfISO(GC.Util.FormatISO(year, month, 1)) or 1) - 1
    local today = GC.Util.TodayISO()

    for cell, button in ipairs(picker.days) do
        local dayNumber = cell - offset
        if dayNumber >= 1 and dayNumber <= daysInMonth then
            local iso = GC.Util.FormatISO(year, month, dayNumber)
            button.iso = iso
            button:SetText(tostring(dayNumber))
            button:Show()
            -- Gefuellt ist der gewaehlte Tag, umrandet der heutige. Bewusst
            -- ueber den Rahmen und nicht ueber die Textfarbe: Beim Verlassen
            -- mit der Maus setzt der Knopf Hintergrund und Beschriftung selbst
            -- zurueck, den Rahmen fasst er nicht an.
            button:SetActive(iso == picker.selected)
            local edge = iso == today and THEME.accent or THEME.border
            button.border:SetColorTexture(edge[1], edge[2], edge[3], 1)
        else
            button.iso = nil
            button:SetText(GC.L(""))
            button:Hide()
        end
    end
end

function GC.UI:ShiftDatePicker(months)
    local picker = self.datePicker
    if not picker then
        return
    end
    local month = picker.month + months
    local year = picker.year
    while month < 1 do
        month = month + 12
        year = year - 1
    end
    while month > 12 do
        month = month - 12
        year = year + 1
    end
    -- Der Bereich deckt sich mit dem, was IsValidISODate ueberhaupt annimmt.
    picker.year = math.max(2000, math.min(2099, year))
    picker.month = month
    self:RefreshDatePicker()
end

function GC.UI:ConfirmDatePicker(iso)
    local picker = self.datePicker
    if not picker then
        return
    end
    if picker.onPick then
        picker.onPick(iso)
    end
    picker:Hide()
end

-- Oeffnet das Blatt an einem Eingabefeld. Steht dort bereits ein gueltiges
-- Datum, faengt der Kalender in dessen Monat an, sonst im laufenden.
function GC.UI:OpenDatePicker(anchor, onPick)
    local picker = self:BuildDatePicker()
    if picker:IsShown() and picker.anchor == anchor then
        picker:Hide()
        return
    end

    local current = GC.Util.NormalizeDateInput(anchor and anchor:GetText() or "")
    local start = GC.Util.IsValidISODate(current) and current or GC.Util.TodayISO()
    local year, month = start:match("^(%d%d%d%d)%-(%d%d)")
    picker.year = tonumber(year) or 2026
    picker.month = tonumber(month) or 1
    picker.selected = GC.Util.IsValidISODate(current) and current or nil
    picker.anchor = anchor
    picker.onPick = onPick

    picker:ClearAllPoints()
    if anchor and anchor.container then
        picker:SetPoint("TOPLEFT", anchor.container, "BOTTOMLEFT", 0, -4)
    else
        picker:SetPoint("CENTER", self.frame or UIParent, "CENTER", 0, 0)
    end
    self:RefreshDatePicker()
    picker:Show()
end

local function ClassColor(classFile)
    local classInfo = GC.Classes[classFile]
    if not classInfo then
        return 1, 1, 1
    end
    return classInfo.color[1], classInfo.color[2], classInfo.color[3]
end

local function SetClassIcon(texture, classFile)
    texture:SetTexture(CLASS_TEXTURE)
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    if coords then
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    end
end

local function SetRaidMarkerIcon(texture, markerIndex)
    texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    if SetRaidTargetIconTexture then
        SetRaidTargetIconTexture(texture, markerIndex)
        return
    end
    local column = (markerIndex - 1) % 4
    local row = math.floor((markerIndex - 1) / 4)
    texture:SetTexCoord(column * 0.25, (column + 1) * 0.25, row * 0.5, (row + 1) * 0.5)
end

local function CreateRaidMarkerButton(parent, markerIndex, onClick)
    local button = CreateButton(parent, "", 26, 26, onClick)
    button.markerIndex = markerIndex
    button.label:Hide()
    button.markerIcon = button:CreateTexture(nil, "ARTWORK")
    button.markerIcon:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
    button.markerIcon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
    SetRaidMarkerIcon(button.markerIcon, markerIndex)
    return button
end

-- "height" ist neu und bleibt optional: Die Auswahlfelder der Einstellungen
-- sind 32 Pixel hoch, in einer 27 Pixel hohen Listenzeile ragt das oben und
-- unten heraus. Ohne Angabe bleibt alles wie bisher.
local function CreateChoiceDropdown(parent, width, options, onSelected, openBelow, emptyLabel, iconResolver, height)
    local dropdown
    -- Von Anfang an die eigene Leer-Beschriftung, nicht "Nicht gesetzt":
    -- Ein Menue, das nie einen Wert bekommt (die reinen Befehlsmenues der
    -- Raidsuche), stand sonst bis zum ersten SetValue mit einem Text da, der
    -- wie ein vergessenes Pflichtfeld aussieht (Gilden-Screenshot 0.9.140).
    dropdown = CreateButton(parent, emptyLabel or "Nicht gesetzt", width, tonumber(height) or 32, function()
        local show = not dropdown.popup:IsShown()
        if show then
            dropdown:PlacePopup()
            if dropdown.popup.scroll then
                dropdown.popup.scroll:SetVerticalScroll(0)
                dropdown.popup.scroll:UpdateModernThumb()
            end
        end
        dropdown.popup:SetShown(show)
    end)
    dropdown.value = ""
    if iconResolver then
        dropdown.choiceIcon = dropdown:CreateTexture(nil, "ARTWORK")
        dropdown.choiceIcon:SetSize(21, 21)
        dropdown.choiceIcon:SetPoint("LEFT", dropdown, "LEFT", 8, 0)
        dropdown.label:ClearAllPoints()
        dropdown.label:SetPoint("LEFT", dropdown, "LEFT", 37, 0)
        dropdown.label:SetPoint("RIGHT", dropdown, "RIGHT", -8, 0)
        dropdown.label:SetJustifyH("LEFT")
    end

    -- Lange Listen wurden frueher als eine hohe Flaeche gezeichnet: Bei elf
    -- Berufen sind das 283 Pixel, die nach oben aus dem Fenster herausragten
    -- und sich nicht erreichen liessen. Ab MAX_ROWS bekommt das Menue deshalb
    -- eine feste Hoehe und scrollt darin.
    local MAX_ROWS = 8
    local ROW_HEIGHT = 25
    local visibleRows = math.min(#options, MAX_ROWS)
    local scrollable = #options > MAX_ROWS

    -- Das Menue haengt bewusst NICHT unter der Karte, sondern unter dem
    -- Hauptfenster. Mehrere Seiten liegen in einem ScrollFrame, und ein
    -- ScrollFrame beschneidet alles, was ueber seinen Rand hinausragt. Als Kind
    -- der Karte waere das aufgeklappte Menue also innerhalb des Scrollbereichs
    -- und wuerde oben abgeschnitten - unabhaengig von seiner Hoehe. Verankert
    -- wird trotzdem am Knopf, die Position stimmt also weiterhin.
    local popupHost = GC.UI.frame or UIParent
    local popup = CreatePanel(popupHost, THEME.input, THEME.accent)
    popup:SetSize(width, (visibleRows * ROW_HEIGHT) + 8)
    popup:SetFrameStrata(popupHost.GetFrameStrata and popupHost:GetFrameStrata() or "DIALOG")
    -- Die Rahmenebene setzt PlacePopup bei jedem Aufklappen; eine feste Zahl
    -- hier wäre für Dropdowns in Dialogen zu niedrig.
    popup:Hide()
    dropdown.popup = popup

    -- Verschwindet der Knopf, muss das Menue mit. Sonst bliebe es beim
    -- Seitenwechsel stehen, weil es nicht mehr am selben Elternteil haengt.
    dropdown:HookScript("OnHide", function()
        popup:Hide()
    end)

    -- Richtung erst beim Aufklappen bestimmen: Nach oben nur, wenn es dort
    -- reicht, sonst nach unten. GetTop und GetBottom messen beide vom unteren
    -- Bildschirmrand.
    function dropdown:PlacePopup()
        -- Die Rahmenebene erst beim Aufklappen, und relativ zum KNOPF statt
        -- zum Fenster: Ein Dropdown in einem Dialog liegt achtzig Ebenen über
        -- dem Fenster. Ein beim Aufbau gesetzter fester Wert lag darunter -
        -- das Menü öffnete sich hinter dem Dialog, war unsichtbar und nicht
        -- anklickbar. Genau so ließ sich im Freitext-Auftrag kein Beruf
        -- wählen.
        popup:SetFrameLevel((self:GetFrameLevel() or 1) + 20)
        popup:ClearAllPoints()
        local needed = popup:GetHeight() + 5
        local spaceAbove = UIParent:GetHeight() - (self:GetTop() or 0)
        local spaceBelow = self:GetBottom() or 0
        if openBelow or (spaceAbove < needed and spaceBelow >= needed) then
            popup:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -5)
        else
            popup:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 5)
        end
    end

    local rowParent = popup
    local rowWidth = width - 8
    if scrollable then
        local scroll = CreateModernScrollFrame(popup)
        scroll:SetPoint("TOPLEFT", popup, "TOPLEFT", 4, -4)
        scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -4, 4)
        local list = CreateFrame("Frame", nil, scroll)
        list:SetWidth(width - 8)
        list:SetHeight(#options * ROW_HEIGHT)
        scroll:SetScrollChild(list)
        popup.scroll = scroll
        rowParent = list
        rowWidth = width - 18
    end

    for index, option in ipairs(options) do
        local selectedOption = option
        local optionButton = CreateButton(rowParent, option ~= "" and option or (emptyLabel or "Nicht gesetzt"), rowWidth, 23, function()
            dropdown:SetValue(selectedOption)
            popup:Hide()
            onSelected(selectedOption)
        end)
        if scrollable then
            optionButton:SetPoint("TOPLEFT", rowParent, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
        else
            optionButton:SetPoint("TOPLEFT", rowParent, "TOPLEFT", 4, -4 - ((index - 1) * ROW_HEIGHT))
        end
        if iconResolver then
            optionButton.choiceIcon = optionButton:CreateTexture(nil, "ARTWORK")
            optionButton.choiceIcon:SetSize(17, 17)
            optionButton.choiceIcon:SetPoint("LEFT", optionButton, "LEFT", 7, 0)
            optionButton.choiceIcon:SetTexture(iconResolver(option))
            optionButton.label:ClearAllPoints()
            optionButton.label:SetPoint("LEFT", optionButton, "LEFT", 31, 0)
            optionButton.label:SetPoint("RIGHT", optionButton, "RIGHT", -6, 0)
            optionButton.label:SetJustifyH("LEFT")
        end
    end

    function dropdown:SetValue(value)
        self.value = value or ""
        self:SetText(self.value ~= "" and self.value or (emptyLabel or "Nicht gesetzt"))
        if self.choiceIcon then
            self.choiceIcon:SetTexture(iconResolver(self.value))
        end
    end

    return dropdown
end

function GC.UI:CreateMainFrame()
    if self.frame then
        return
    end

    local frame = CreatePanel(UIParent, THEME.window, { 0.12, 0.55, 0.63, 1 }, "GuildCopilotForeverFrame")
    frame:SetSize(1020, 690)
    frame:SetPoint("CENTER")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    -- Escape schliesst das Fenster bereits ueber UISpecialFrames. Eigene
    -- OnKeyDown/OnKeyUp-Handler fangen auch Enter und Bewegungstasten ab und
    -- brauchen SetPropagateKeyboardInput, das im Kampf gesperrt ist. Deshalb
    -- bleibt der Rahmen dauerhaft ohne Tastaturfang, auch nach Wiederherstellen.
    frame:EnableKeyboard(false)
    frame:Hide()
    table.insert(UISpecialFrames, "GuildCopilotForeverFrame")
    -- Schliessen ueber ×, Escape oder /gcp: Ein Fokus in einem der eigenen
    -- Felder darf das Fenster nicht ueberleben (siehe ReleaseOwnKeyboardFocus).
    frame:HookScript("OnHide", function(self)
        ReleaseOwnKeyboardFocus(self)
        ClearOwnEditFocus()
    end)

    local header = CreatePanel(frame, THEME.sidebar, THEME.sidebar)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    header:SetHeight(58)
    frame.header = header

    local mark = header:CreateTexture(nil, "ARTWORK")
    mark:SetSize(36, 36)
    mark:SetPoint("LEFT", header, "LEFT", 16, 0)
    mark:SetTexture("Interface\\AddOns\\GuildCopilotForever\\Media\\GuildCopilotForeverLogo")

    local title = CreateLabel(header, "Guild Copilot", { title = true })
    title:SetPoint("LEFT", mark, "RIGHT", 12, 7)
    local subtitle = CreateLabel(header, GC.Client.label .. "  •  v" .. GC.Constants.VERSION, { muted = true })
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    frame.subtitle = subtitle
    self:RefreshUpdateHint()

    -- Sichtbar neben der Version: Laeuft der Abgleich mit der Gilde, und fahren
    -- alle denselben Stand? Ein Klick fragt sofort nach, statt auf den naechsten
    -- Login zu warten.
    self.syncBadge = CreateButton(header, "", 250, 20, function()
        GC.Sync:RequestSync()
        GC.UI:RefreshSyncBadge()
    end)
    self.syncBadge:SetPoint("LEFT", subtitle, "RIGHT", 14, 0)
    self.syncBadge.background:Hide()
    self.syncBadge.border:Hide()
    self.syncBadge.label:ClearAllPoints()
    self.syncBadge.label:SetPoint("LEFT", self.syncBadge, "LEFT", 0, 0)
    self.syncBadge.label:SetJustifyH("LEFT")
    self.syncBadge.label:SetFontObject("GameFontNormalSmall")
    self.syncBadge:SetScript("OnEnter", function(badge)
        if not GameTooltip then
            return
        end
        local stats = GC.Sync:GetAddonUserStats()
        local status = GC.Sync:GetSyncStatus()
        GameTooltip:SetOwner(badge, "ANCHOR_BOTTOM")
        GameTooltip:SetText(GC.L("Abgleich mit der Gilde"))
        if status.state == "RUNNING" then
            GameTooltip:AddLine("Läuft gerade: " .. status.percent .. " %, noch "
                .. status.outstanding .. " offen.", 0.18, 0.78, 0.86, true)
        elseif (status.lastSyncedAt or 0) > 0 and date then
            GameTooltip:AddLine("Zuletzt vollständig: "
                .. date("%d.%m. %H:%M", status.lastSyncedAt), 0.35, 0.90, 0.58, true)
        end
        GameTooltip:AddLine(stats.players .. " Spieler mit "
            .. stats.known .. " erkannten Charakteren, davon " .. stats.compatible
            .. " mit gleicher Datenversion.", 1, 1, 1, true)
        if #stats.outdatedNames > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Abweichende Datenversion:", 1, 0.72, 0.25)
            GameTooltip:AddLine(table.concat(stats.outdatedNames, ", "), 1, 1, 1, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Erkannt wird nur, wer das Addon aktiv nutzt und seit deinem"
            .. " Login etwas gesendet hat.", 0.57, 0.64, 0.72, true)
        GameTooltip:AddLine("Klick fragt sofort bei allen nach.", 0.31, 0.79, 1, true)
        GameTooltip:Show()
    end)
    self.syncBadge:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    local close = CreateButton(header, "×", 34, 34, function()
        frame:Hide()
    end)
    close:SetPoint("RIGHT", header, "RIGHT", -13, 0)
    close.label:SetFontObject("GameFontNormalLarge")

    -- Minimieren nach dem Muster, das aus WeakAuras bekannt ist: Alles unter
    -- der Kopfzeile klappt weg, stehen bleibt der Balken mit Titel, Abgleich
    -- und den Knöpfen. Der Bildschirm ist frei, das Fenster aber nicht
    -- geschlossen - und es steht danach wieder da, wo es stand.
    self.minimizeButton = CreateButton(header, "", 34, 34, function()
        GC.UI:SetWindowMinimized(not GC.DB:GetSettings().window.minimized)
    end)
    self.minimizeButton:SetPoint("RIGHT", close, "LEFT", -6, 0)
    self.minimizeMark = CreateMinimizeMark(self.minimizeButton, 14)
    self.restoreMark = CreateRestoreMark(self.minimizeButton, 12)
    SetButtonMark(self.minimizeButton, self.minimizeMark)
    self.restoreMark:SetPoint("CENTER", self.minimizeButton, "CENTER", 0, 0)
    self.restoreMark:Hide()
    self.minimizeButton:SetScript("OnEnter", function(selfButton)
        if not selfButton.active then
            SetTextureColor(selfButton.background, THEME.cardHover)
        end
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(selfButton, "ANCHOR_BOTTOM")
        if GC.DB:GetSettings().window.minimized then
            GameTooltip:SetText(GC.L("Wieder aufklappen"))
        else
            GameTooltip:SetText(GC.L("Minimieren"))
            GameTooltip:AddLine("Klappt alles unter der Kopfzeile weg. Der Balken bleibt"
                .. " stehen und lässt sich weiter verschieben.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    self.minimizeButton:SetScript("OnLeave", function(selfButton)
        selfButton:SetActive(selfButton.active)
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    -- Die Einrichtung laesst sich jederzeit wieder aufrufen - auch nach
    -- "Nicht mehr anzeigen" und auch, wenn schon alles erledigt ist. Der
    -- Knopf oeffnet den Assistenten mit der Funktionstour und holt zugleich
    -- die Checkliste im Profil zurueck (Reopen). Ein eigener Navigationspunkt
    -- kam dafuer nicht in Frage: Die Seitenleiste hat keine Bildlaufleiste
    -- und ist voll.
    local setup = CreateButton(header, "Einrichtung", 110, 26, function()
        GC.Onboarding:Reopen()
        GC.UI:RefreshOnboarding()
        GC.UI:ShowWelcome()
    end)
    setup:SetPoint("RIGHT", self.minimizeButton, "LEFT", -8, 0)
    setup:SetScript("OnEnter", function(selfButton)
        SetTextureColor(selfButton.background, THEME.cardHover)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(selfButton, "ANCHOR_BOTTOM")
        GameTooltip:SetText(GC.L("Erste Schritte"))
        GameTooltip:AddLine("Öffnet den Einrichtungsassistenten mit der Funktionstour"
            .. " und holt die Checkliste im Profil zurück.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    setup:SetScript("OnLeave", function(selfButton)
        selfButton:SetActive(selfButton.active)
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    -- Ist alles erledigt, bleibt die Erfolgsmeldung bis zum Schliessen stehen.
    frame:SetScript("OnHide", function()
        GC.Onboarding:NoteWindowClosed()
        GC.UI:EndWindowResize()
    end)

    -- Der Griff in der unteren rechten Ecke. Losgelassen wird über den
    -- Mausknopf selbst und nicht über OnMouseUp: Wer beim Ziehen aus dem
    -- Griff herausfährt, bekäme sonst nie ein Ende und das Fenster bliebe am
    -- Zeiger kleben.
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    grip:EnableMouse(true)
    grip.mark = CreateResizeMark(grip, 14)
    grip.mark:SetPoint("CENTER", grip, "CENTER", 0, 0)
    grip:SetScript("OnEnter", function(self)
        self.mark:SetColor(THEME.accent)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(GC.L("Fenstergröße ziehen"))
        GameTooltip:AddLine("Zieh die Ecke, um das Fenster kleiner oder größer zu machen."
            .. " Derselbe Wert steht als Regler in den Einstellungen.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function(self)
        self.mark:SetColor(THEME.muted)
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    grip:SetScript("OnMouseDown", function(self)
        GC.UI:BeginWindowResize()
        self:SetScript("OnUpdate", function()
            if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
                GC.UI:EndWindowResize()
                return
            end
            GC.UI:StepWindowResize()
        end)
    end)
    grip:SetScript("OnMouseUp", function()
        GC.UI:EndWindowResize()
    end)
    frame.resizeGrip = grip

    local sidebar = CreatePanel(frame, THEME.sidebar, THEME.sidebar)
    sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -59)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    sidebar:SetWidth(190)
    frame.sidebar = sidebar

    -- Erst aussortieren, dann zeichnen: Ein fehlendes optionales Modul darf
    -- weder eine Luecke in der Leiste hinterlassen noch einen Abschnittskopf
    -- ohne Inhalt. Die Abstaende rechnen sich unten aus der gefilterten Liste.
    local navigation = {}
    for _, definition in ipairs(TAB_DEFINITIONS) do
        if definition.requires == nil or GC[definition.requires] ~= nil then
            navigation[#navigation + 1] = definition
        end
    end

    local navigationY = -NAV_TOP
    local currentSection
    for _, definition in ipairs(navigation) do
        -- Abschnitts- und Reiterbeschriftungen laufen durch GC.L; die
        -- Schluessel in TAB_DEFINITIONS bleiben deutsch und stabil.
        if definition.section ~= currentSection then
            if currentSection then
                navigationY = navigationY - NAV_SECTION_GAP
            end
            currentSection = definition.section
            local sectionLabel = CreateLabel(sidebar, GC.L(currentSection), {
                muted = true,
                font = "GameFontNormalSmall",
                align = "CENTER",
                width = 160,
                height = 18,
            })
            sectionLabel:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 14, navigationY)
            navigationY = navigationY - NAV_SECTION_HEIGHT
        end
        -- "page" und "view" sind optional: Ohne sie ist der Punkt eine eigene
        -- Seite, mit ihnen eine bestimmte Ansicht einer geteilten Seite.
        local pageKey = definition.page or definition.key
        local viewKey = definition.view
        local tab = CreateButton(sidebar, GC.L(definition.label), 160, NAV_TAB_HEIGHT, function()
            self:ShowPage(pageKey)
            if viewKey then
                self:SetWorkshopView(viewKey)
            elseif pageKey == "WORKSHOP" then
                self:SetWorkshopView("CATALOG")
            end
        end)
        tab:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 14, navigationY)
        navigationY = navigationY - NAV_TAB_SPACING
        tab.key = pageKey
        tab.view = viewKey
        tab.label:ClearAllPoints()
        tab.label:SetPoint("LEFT", tab, "LEFT", 43, 0)
        tab.label:SetPoint("RIGHT", tab, "RIGHT", -8, 0)
        tab.label:SetJustifyH("LEFT")
        tab.icon = tab:CreateTexture(nil, "ARTWORK")
        tab.icon:SetSize(22, 22)
        tab.icon:SetPoint("LEFT", tab, "LEFT", 13, 0)
        tab.icon:SetTexture(definition.icon)

        -- Ranggeschützte Punkte verschwinden nicht mehr, sie tragen ein
        -- Schloss (Owner-Entscheidung): Sichtbar heißt "gibt es, braucht
        -- Rang" - unsichtbar hieße "gibt es nicht".
        tab.lock = tab:CreateTexture(nil, "OVERLAY")
        tab.lock:SetSize(14, 14)
        tab.lock:SetPoint("RIGHT", tab, "RIGHT", -8, 0)
        tab.lock:SetTexture("Interface\\Buttons\\LockButton-Locked-Up")
        tab.lock:Hide()
        function tab:SetLocked(locked)
            self.locked = locked == true
            self.lock:SetShown(self.locked)
            if self.SetAlpha then
                self:SetAlpha(self.locked and 0.45 or 1)
            end
        end
        tab:HookScript("OnEnter", function(self)
            if self.locked and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(GC.L("Für deinen Gildenrang gesperrt"))
                GameTooltip:AddLine("Berechtigte Ränge legen die Freigabe in den Einstellungen fest.",
                    1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        tab:HookScript("OnLeave", function(self)
            if self.locked and GameTooltip then
                GameTooltip:Hide()
            end
        end)
        self.tabs[#self.tabs + 1] = tab

        local page = CreateFrame("Frame", nil, frame)
        page:SetPoint("TOPLEFT", frame, "TOPLEFT", 215, -82)
        page:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -22, 22)
        page:Hide()
        self.pages[pageKey] = page
    end

    self.frame = frame
    self:BuildDashboardPage()
    self:BuildSettingsPage()
    self:BuildRosterPage()
    self:BuildMemberCarePage()
    self:BuildWorkshopPage()
    self:BuildSuggestionsPage()
    self:BuildRecruitmentPage()
    self:BuildPostPage()
    self:BuildInboxPage()
    self:BuildGuildPage()
    self:BuildWarcraftLogsPage()
    self:BuildStatisticsPage()
    self:BuildGearPage()
    self:BuildRaidSearchPage()
    self:ShowPage(self.activePage)
    self:ApplyWindowLook()
    -- Zugeklappt ausgeloggt heisst zugeklappt eingeloggt.
    if GC.DB:GetSettings().window.minimized then
        self:SetWindowMinimized(true)
    end
    -- Lief beim Ausloggen eine Raidsuche, steht ihr Balken nach dem Login
    -- wieder da - die Suche selbst lebt in den SavedVariables weiter.
    self:UpdateRaidSearchBarShown()
end

-- Maßstab und Deckkraft des Hauptfensters (Nutzerrückmeldung 08/2026).
--
-- Bewusst nur das Hauptfenster: Tracker, Werbebalken und Bildschirmmeldung
-- merken sich ihre Position als Versatz zur Bildschirmmitte - ein Maßstab
-- würde diesen Versatz mitskalieren und die drei unter der Hand verschieben.
-- Sie sind ohnehin klein; groß ist das Fenster mit seinen 1020 × 690.
local WINDOW_SCALE_MINIMUM = 70
local WINDOW_SCALE_MAXIMUM = 130

function GC.UI:ApplyWindowLook()
    if not self.frame then
        return
    end
    local window = GC.DB:GetSettings().window or {}
    local scale = math.max(WINDOW_SCALE_MINIMUM,
        math.min(WINDOW_SCALE_MAXIMUM, tonumber(window.scale) or 100))
    local alpha = math.max(40, math.min(100, tonumber(window.alpha) or 100))
    self.frame:SetScale(scale / 100)
    self.frame:SetAlpha(alpha / 100)
end

-- === Größe ziehen ===========================================================
--
-- Aus dem Spiel gemeldet: „Das Fenster sollte rechts unten an der Kante per
-- Drag and Drop kleiner oder größer gezogen werden können."
--
-- Gezogen wird der MASSSTAB, nicht die Kante. Der Grund steht in 0.9.111: Die
-- dreizehn Seiten sind pixelgenau vermessen, eine echte Größenänderung müsste
-- jede davon umbrechen. Für die Hand am Mauszeiger ist der Unterschied
-- trotzdem keiner - die Ecke folgt dem Zeiger, weil das Fenster für die Dauer
-- des Ziehens oben links verankert wird. Ohne das wüchse es um seine Mitte,
-- und die Ecke liefe dem Zeiger davon.
-- Nagelt das Fenster an seiner oberen linken Ecke fest. Ohne das wüchse und
-- schrumpfte es um seine Mitte - beim Ziehen liefe die Ecke dem Mauszeiger
-- davon, und beim Minimieren spränge der Balken in die Bildschirmmitte.
function GC.UI:FreezeWindowTopLeft()
    local frame = self.frame
    if not frame then
        return
    end
    local scale = frame:GetScale() or 1
    frame.resizeLeft = (frame:GetLeft() or 0) * scale
    frame.resizeTop = (frame:GetTop() or 0) * scale
    self:AnchorWindowTopLeft(scale)
end

function GC.UI:BeginWindowResize()
    local frame = self.frame
    if not frame then
        return
    end
    frame.resizing = true
    self:FreezeWindowTopLeft()
end

-- Verankert das Fenster an seiner gemerkten oberen linken Ecke. Die Versätze
-- eines SetPoint gelten im Maßstab des Fensters - deshalb wird geteilt.
function GC.UI:AnchorWindowTopLeft(scale)
    local frame = self.frame
    if not frame or not frame.resizeLeft then
        return
    end
    scale = scale or frame:GetScale() or 1
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
        frame.resizeLeft / scale, frame.resizeTop / scale)
end

function GC.UI:StepWindowResize()
    local frame = self.frame
    if not frame or not frame.resizing then
        return
    end
    local cursorX = CursorInUISpace()
    local width = frame:GetWidth() or 0
    if not cursorX or width <= 0 then
        return
    end
    -- Auf ganze Prozent gerundet, und zwar VOR dem Anwenden: Sonst stünde das
    -- Fenster auf 78,43 % und der Regler in den Einstellungen auf 78 - ein
    -- Klick dort ließe es dann sichtbar springen.
    local percent = math.max(WINDOW_SCALE_MINIMUM, math.min(WINDOW_SCALE_MAXIMUM,
        math.floor((((cursorX - frame.resizeLeft) / width) * 100) + 0.5)))
    frame:SetScale(percent / 100)
    self:AnchorWindowTopLeft(percent / 100)
    GC.DB:GetSettings().window.scale = percent
end

-- === Minimieren =============================================================
--
-- Aus dem Spiel gewünscht, nach dem Vorbild von WeakAuras: „nur die oberste
-- Zeile, dass man den Bildschirm frei hat". Zugeklappt bleibt die Kopfzeile
-- mit Titel, Abgleichstand und Knöpfen - sie ist zugleich der Griff zum
-- Verschieben, weil das ganze Fenster auf Ziehen reagiert.
--
-- Der Zustand wird gemerkt: Wer zugeklappt ausloggt, findet den Balken
-- wieder. Verwechseln lässt er sich mit einem geschlossenen Fenster nicht -
-- er trägt seinen Namen.
local WINDOW_MINIMIZED_HEIGHT = 60

function GC.UI:SetWindowMinimized(minimized)
    local frame = self.frame
    if not frame then
        return
    end
    minimized = minimized == true
    GC.DB:GetSettings().window.minimized = minimized
    frame.minimized = minimized

    -- Erst den Anker festnageln, dann die Höhe ändern: Sonst wandert der
    -- Balken beim Zuklappen in die Mitte des Bildschirms.
    self:FreezeWindowTopLeft()
    if minimized then
        -- Die Seiten verschwinden gleich: eigene Eingabefelder geben ihren
        -- Fokus frei. Der Rahmen selbst bleibt in beiden Zustaenden ohne
        -- Tastaturfang; beim Aufklappen gibt es nichts wieder zu aktivieren.
        ReleaseOwnKeyboardFocus(frame)
        ClearOwnEditFocus()
    end
    frame.sidebar:SetShown(not minimized)
    for key, page in pairs(self.pages) do
        -- Das Verstecken der Seiten schließt über deren OnHide auch alle
        -- offenen Dialoge - genau richtig, sie hätten sonst über dem Balken
        -- gestanden.
        page:SetShown(not minimized and key == self.activePage)
    end
    if frame.resizeGrip then
        frame.resizeGrip:SetShown(not minimized)
    end
    frame:SetHeight(minimized and WINDOW_MINIMIZED_HEIGHT or WINDOW_HEIGHT)
    self:AnchorWindowTopLeft()

    if self.minimizeMark then
        self.minimizeMark:SetShown(not minimized)
        self.restoreMark:SetShown(minimized)
    end
    if not minimized and self:IsVisible() then
        -- Aufgeklappt zeigt die Seite den aktuellen Stand, nicht den von vor
        -- dem Zuklappen.
        self:RefreshPage(self.activePage)
    end
end

function GC.UI:EndWindowResize()
    local frame = self.frame
    if not frame then
        return
    end
    frame.resizing = false
    if frame.resizeGrip then
        frame.resizeGrip:SetScript("OnUpdate", nil)
    end
    -- Der Regler in den Einstellungen zeigt denselben Wert wie die Ecke.
    self:RefreshSettings()
end

-- Welcher Navigationspunkt leuchtet? Die Werkstatt teilen sich zwei Punkte;
-- dort entscheidet zusätzlich die Ansicht, sonst allein die Seite.
function GC.UI:RefreshTabHighlight()
    local workshop = self.pages and self.pages.WORKSHOP
    local workshopView = (workshop and workshop.workshopView) or "CATALOG"
    for _, tab in ipairs(self.tabs or {}) do
        local active = tab.key == self.activePage
        if active and tab.key == "WORKSHOP" then
            active = (tab.view or "CATALOG") == workshopView
        end
        tab:SetActive(active)
    end
end

function GC.UI:ShowPage(pageKey)
    -- Wer eine Seite aufschlaegt, will sie sehen: Ein zugeklapptes Fenster
    -- klappt dafuer auf. Sonst zeichnete sich die Seite in einen 60 Pixel
    -- hohen Balken.
    if self.frame and self.frame.minimized then
        self:SetWindowMinimized(false)
    end
    if pageKey == "MEMBERCARE" and not GC.Roster:CanAccessMemberCare() then
        pageKey = "ROSTER"
        GC:Print("Mitgliederpflege ist für deinen Gildenrang gesperrt – "
            .. "berechtigte Ränge legen die Freigabe in den Einstellungen fest.")
    end
    -- Eine Seite, die es nicht gibt, weil ihr optionales Modul fehlt: Ohne
    -- diesen Rueckfall wuerde die Schleife unten alles verstecken und nichts
    -- zeigen - ein leeres Fenster ohne Fehlermeldung.
    if self.frame and not self.pages[pageKey] then
        pageKey = "ROSTER"
    end
    self.activePage = pageKey
    -- Auch der Seitenwechsel versteckt Felder; ein dort hängender Fokus
    -- würde unsichtbar weitertippen.
    ReleaseOwnKeyboardFocus(self.frame)
    ClearOwnEditFocus()
    for key, page in pairs(self.pages) do
        page:SetShown(key == pageKey)
    end
    self:RefreshTabHighlight()
    -- Die aufgeschlagene Seite wird immer neu gezeichnet, auch wenn sie nicht
    -- als veraltet vorgemerkt war: Ein Klick auf einen Reiter soll den
    -- aktuellen Stand zeigen, nicht den von vorhin.
    if self:IsVisible() then
        self:RefreshSyncBadge()
        self:RefreshNavigationAccess()
        self:RefreshPage(pageKey)
    end
end

function GC.UI:RefreshNavigationAccess()
    local canAccessMemberCare = GC.Roster:CanAccessMemberCare()
    for _, tab in ipairs(self.tabs) do
        if tab.key == "MEMBERCARE" then
            -- Sichtbar bleiben, aber mit Schloss und gedimmt statt versteckt.
            tab:SetShown(true)
            tab:SetLocked(not canAccessMemberCare)
        end
    end
    if self.activePage == "MEMBERCARE" and not canAccessMemberCare then
        self:ShowPage("ROSTER")
    end
end

function GC.UI:Toggle()
    self:CreateMainFrame()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
        self:Refresh()
    end
end

-- Nur die Berufsnamen, ohne Fertigkeitspunkte. Die Zahl stand nur an
-- automatisch erfassten Berufen - von Hand eingetragene haben keine -, und
-- eine Spalte, in der dieselbe Angabe mal mit und mal ohne Zahl steht, sieht
-- nach einem Fehler aus (Owner-Entscheidung: weglassen). Wer die Punkte
-- braucht, findet sie an der eigenen Berufskarte im Profil.
local function ProfessionSummary(profile)
    local labels = {}
    for slot = 1, 2 do
        local profession = profile and profile.professions and profile.professions[slot]
        if profession and profession.name then
            -- Einzeln uebersetzen (Tailoring/Enchanting), dann verketten.
            labels[#labels + 1] = GC.L(profession.name)
        end
    end
    return #labels > 0 and table.concat(labels, " / ") or "–"
end

-- === Berufsnamen fuer schmale Spalten ======================================
--
-- "Lederverarbeitung / Verzauberkunst" sind 34 Zeichen. In der Berufsspalte der
-- Uebersicht sind gut 30 Pixel je fuenf Zeichen - der Text lief hinten aus dem
-- Feld und endete als "Verzauberku…". Aus dem Spiel gemeldet: "das
-- abgeschnittene mag ich auch nicht".
--
-- Die Spalte breiter zu machen ginge nur auf Kosten der Nachbarn, und die
-- brauchen ihren Platz genauso. Also die Namen kuerzen - und zwar so, wie in
-- WoW ohnehin jeder darueber redet ("Leder", "Verzauberer", "Ingi"). Der
-- vollstaendige Name steht weiterhin im Tooltip der Zeile.
local PROFESSION_SHORT_NAMES = {
    ["Alchimie"] = "Alchi",
    ["Bergbau"] = "Bergbau",
    ["Ingenieurskunst"] = "Ingi",
    ["Juwelenschleifen"] = "Juwelen",
    ["Kräuterkunde"] = "Kräuter",
    ["Kürschnerei"] = "Kürschner",
    ["Lederverarbeitung"] = "Leder",
    ["Schmiedekunst"] = "Schmied",
    ["Schneiderei"] = "Schneider",
    ["Verzauberkunst"] = "Verzauberer",
    ["Erste Hilfe"] = "Erste Hilfe",
    ["Kochkunst"] = "Kochen",
    ["Angeln"] = "Angeln",
}

local function ShortProfessionSummary(profile)
    local labels = {}
    for slot = 1, 2 do
        local profession = profile and profile.professions and profile.professions[slot]
        if profession and profession.name then
            local name = profession.name
            labels[#labels + 1] = GC.L(PROFESSION_SHORT_NAMES[name] or name)
        end
    end
    return #labels > 0 and table.concat(labels, " / ") or "–"
end

local function LastOnlineLabel(member)
    if member.online then
        return "|cff59e695online|r"
    end
    local hours = member.lastOnlineHours
    if hours == nil then
        return GC.L("unbekannt")
    elseif hours < 24 then
        return GC.LFormat("vor {n}h", { n = math.max(1, math.floor(hours)) })
    elseif hours < 24 * 365 then
        return GC.LFormat("vor {n}T", { n = math.floor(hours / 24) })
    end
    return GC.L("> 1 Jahr")
end

function GC.UI:BuildDashboardPage()
    local page = self.pages.OVERVIEW
    -- Der Untertitel traegt eine Zahl und uebersetzt sich deshalb ueber den
    -- Platzhalter-Schluessel selbst; CreatePageTitle laesst ihn durch.
    -- "Zuletzt aktive Level-70-Spieler" stand hier in einem Satz mit drei
    -- weiteren Bedingungen und ging darin unter - aus dem Spiel gemeldet:
    -- "ist nicht so klar und eindeutig". Das Ordnungsprinzip der Liste steht
    -- deshalb jetzt hervorgehoben vorn, und dieselbe Aussage wiederholt sich
    -- in der Spaltenueberschrift "ZULETZT ONLINE".
    CreatePageTitle(page, "Gildenübersicht",
        (GC.L("|cff2ec7dbNach zuletzt online sortiert|r – bis zu {n} Spieler aus den gewählten Raider-Rängen, mit Rang, Raidprofil und Berufen.")
            :gsub("{n}", tostring(GC.Constants.ACTIVE_RAIDER_LIMIT))))

    page.metricCards = {}
    local metrics = {
        { key = "MEMBERS", label = "MITGLIEDER" },
        { key = "ONLINE", label = "ONLINE" },
        { key = "PROFILES", label = "BEKANNTE PROFILE" },
        { key = "ADDON", label = "MIT ADDON" },
    }
    for index, metric in ipairs(metrics) do
        local card = CreateCard(page)
        card:SetSize(185, 82)
        card:SetPoint("TOPLEFT", page, "TOPLEFT", (index - 1) * 197, -66)
        card.value = CreateLabel(card, "0", { title = true })
        card.value:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -13)
        -- Feste Breite und Hoehe, sonst waechst die Beschriftung aus der Karte
        -- heraus: "MIT ADDON  •  20 CHARAKTERE  •  4 ABWEICHEND" stand quer
        -- ueber dem halben Bildschirm, weil eine FontString ohne Breite
        -- einfach weiterlaeuft.
        card.caption = CreateLabel(card, metric.label, { muted = true, width = 153, height = 14 })
        card.caption:SetPoint("TOPLEFT", card.value, "BOTTOMLEFT", 0, -4)
        -- Zweite Zeile fuer Zusaetze. Sie bleibt leer, solange es nichts zu
        -- sagen gibt, und uebernimmt sonst die Warnfarbe.
        card.detail = CreateLabel(card, "", {
            muted = true,
            font = "GameFontNormalSmall",
            width = 153,
            height = 13,
        })
        card.detail:SetPoint("TOPLEFT", card.caption, "BOTTOMLEFT", 0, -2)
        page.metricCards[metric.key] = card
    end

    local addonCard = page.metricCards.ADDON
    addonCard:EnableMouse(true)
    addonCard:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        local stats = GC.Sync:GetAddonUserStats()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(GC.L("Guild Copilot in der Gilde"))
        GameTooltip:AddLine(stats.players .. " Spieler mit "
            .. stats.known .. " erkannten Charakteren, davon " .. stats.compatible
            .. " mit passender Datenversion", 1, 1, 1, true)
        if stats.known > stats.players then
            GameTooltip:AddLine("Charaktere eines Spielers werden zusammengefasst,"
                .. " sobald sein Client sich einmal vorgestellt hat.", 0.57, 0.64, 0.72, true)
        end
        if #stats.outdatedNames > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Abweichende Datenversion:", 1, 0.72, 0.25)
            GameTooltip:AddLine(table.concat(stats.outdatedNames, ", "), 1, 1, 1, true)
            GameTooltip:AddLine("Mit ihnen werden Rezepte und gildenweite Einstellungen"
                .. " nicht ausgetauscht.", 1, 1, 1, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Erkannt wird nur, wer das Addon aktiv nutzt.", 0.57, 0.64, 0.72, true)
        GameTooltip:Show()
    end)
    addonCard:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    local rosterCard = CreateCard(page, "Aktive Raider")
    rosterCard:SetSize(776, 408)
    rosterCard:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -158)
    page.rankFilterButton = CreateButton(rosterCard, "Ränge: alle", 154, 28, function()
        GC.UI:ShowPage("SETTINGS")
    end)
    page.rankFilterButton:SetPoint("TOPRIGHT", rosterCard, "TOPRIGHT", -18, -12)
    -- STATUS war 74 Pixel breit, "nicht bestaetigt" braucht rund 95. Der Text
    -- brach um und sprengte die 25 Pixel hohe Zeile. Die Spalte bekommt mehr
    -- Platz, die Berufe geben ihn ab - sie sind ohnehin selten voll.
    local headers = {
        { text = "SPIELER", x = 18, width = 112 },
        { text = "RANG", x = 136, width = 92 },
        { text = "SPEC", x = 234, width = 150 },
        { text = "STATUS", x = 390, width = 86 },
        { text = "BERUFE", x = 482, width = 150 },
        -- Der Kopf sagt jetzt selbst, wonach sortiert ist. Die Liste war immer
        -- nach der letzten Onlinezeit geordnet, nur stand das nirgends.
        { text = "ZULETZT ONLINE", x = 638, width = 110, highlight = true },
    }
    for _, headerDefinition in ipairs(headers) do
        local headerLabel = CreateLabel(rosterCard, headerDefinition.text, {
            muted = not headerDefinition.highlight,
            font = "GameFontNormalSmall",
            width = headerDefinition.width,
        })
        if headerDefinition.highlight then
            SetTextColor(headerLabel, THEME.accent)
        end
        headerLabel:SetPoint("TOPLEFT", rosterCard, "TOPLEFT", headerDefinition.x, -49)
    end

    local scroll = CreateModernScrollFrame(rosterCard)
    scroll:SetPoint("TOPLEFT", rosterCard, "TOPLEFT", 14, -70)
    scroll:SetPoint("BOTTOMRIGHT", rosterCard, "BOTTOMRIGHT", -16, 14)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(742)
    content:SetHeight(GC.Constants.ACTIVE_RAIDER_LIMIT * 27)
    scroll:SetScrollChild(content)
    page.raiderRows = {}
    for index = 1, GC.Constants.ACTIVE_RAIDER_LIMIT do
        local row = CreatePanel(content, index % 2 == 0 and THEME.input or THEME.card)
        row:SetSize(740, 25)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((index - 1) * 27))
        -- Durchgehend einzeilig: Jede umbrechende Zelle waechst ueber ihre
        -- Zeile hinaus und schiebt sich optisch in die Nachbarzeilen.
        local columns = {
            { key = "name", x = 5, width = 112 },
            { key = "rank", x = 123, width = 92 },
            { key = "spec", x = 221, width = 150 },
            { key = "status", x = 377, width = 86 },
            { key = "professions", x = 469, width = 150 },
            { key = "activity", x = 625, width = 110 },
        }
        for _, column in ipairs(columns) do
            row[column.key] = CreateLabel(row, "", {
                width = column.width,
                height = 25,
            })
            row[column.key]:SetPoint("LEFT", row, "LEFT", column.x, 0)
        end

        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not self.member or not GameTooltip then
                return
            end
            AnchorRowTooltip(self)
            GameTooltip:SetText(GC.Util.PlayerIdentityName(self.member.name))
            GameTooltip:AddLine(self.tooltipSpec or "", 1, 1, 1, true)
            if self.tooltipProfessions and self.tooltipProfessions ~= "" then
                GameTooltip:AddLine("Berufe: " .. self.tooltipProfessions, 1, 1, 1, true)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(self.tooltipStatus or "", 0.57, 0.64, 0.72, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        page.raiderRows[index] = row
    end

end

function GC.UI:RefreshDashboard()
    local page = self.pages.OVERVIEW
    if not page then
        return
    end
    local summary = GC.Roster:GetSummary()
    page.metricCards.MEMBERS.value:SetText(summary.total)
    page.metricCards.ONLINE.value:SetText(summary.online)
    page.metricCards.PROFILES.value:SetText(summary.knownProfiles)

    local addonStats = GC.Sync:GetAddonUserStats()
    local addonCard = page.metricCards.ADDON
    -- Gezaehlt werden Spieler, nicht Charaktere: wer mit Main und Twinks
    -- unterwegs war, ist einer. Die Charakterzahl steht daneben, solange sie
    -- abweicht.
    addonCard.value:SetText(addonStats.players)
    local incompatible = addonStats.outdated + addonStats.ahead
    -- Die Karte ist 185 Pixel breit. Alles, was nicht hineinpasst, steht in der
    -- zweiten Zeile, im Tooltip der Karte und ohnehin in der Titelzeile des
    -- Fensters - dreimal derselbe Satz nebeneinander war der Fehler.
    local details = {}
    if addonStats.known > addonStats.players then
        details[#details + 1] = addonStats.known .. " CHARS"
    end
    if incompatible > 0 then
        details[#details + 1] = incompatible .. " ABWEICHEND"
    end
    addonCard.detail:SetText(table.concat(details, "  •  "))
    SetTextColor(addonCard.detail, incompatible > 0 and THEME.warning or THEME.muted)

    local ranks = GC.Roster:GetRankDefinitions()
    local selectedRanks = 0
    for _, rank in ipairs(ranks) do
        if GC.Roster:IsRankActive(rank.index) then
            selectedRanks = selectedRanks + 1
        end
    end
    if #ranks == 0 or selectedRanks == #ranks then
        page.rankFilterButton:SetText(GC.L("Ränge: alle"))
    else
        page.rankFilterButton:SetText(GC.LFormat("Ränge: {n}/{m}",
            { n = selectedRanks, m = #ranks }))
    end

    local raiders = GC.Roster:GetActiveRaiders(GC.Constants.ACTIVE_RAIDER_LIMIT)
    for index, row in ipairs(page.raiderRows) do
        local member = raiders[index]
        row:SetShown(member ~= nil)
        if member then
            local profile = GC.Roster:GetProfile(member.name)
            local primary = profile and GC.SpecByKey[profile.raidSpecKey or profile.detectedSpecKey or ""]
            local secondary = profile and GC.SpecByKey[profile.secondarySpecKey or ""]
            -- Spec- und Klassennamen einzeln uebersetzen, dann verketten:
            -- der zusammengesetzte Text traefe keinen Schluessel.
            local specText = primary and GC.L(primary.name) or GC.L(member.className or "–")
            if secondary then
                specText = specText .. " / " .. GC.L(secondary.name)
            end
            -- Der Status trug frueher drei verschiedene Aussagen in einem Wort.
            -- Farbe und Tooltip trennen sie jetzt: Wer gar kein Profil hat,
            -- ist etwas anderes als wer eines hat und es nicht bestaetigt hat.
            local statusText, statusColor, statusHint
            if not profile then
                statusText = GC.L("kein Profil")
                statusColor = THEME.muted
                statusHint = GC.L("Dieser Spieler hat sein Raidprofil noch nie ausgefüllt.")
            else
                if profile.source == "INSPECT" then
                    -- Aus dem Talentbaum gelesen, nicht vom Spieler gemeldet:
                    -- Die Spec stimmt, ueber Main/Twink und die Zweitspec sagt
                    -- sie nichts.
                    statusText = GC.L("erkannt")
                    statusColor = THEME.muted
                    statusHint = GC.L("Spec aus dem Talentbaum gelesen, als dieser Spieler "
                        .. "für den Ausrüstungsabgleich inspiziert wurde. Main/Twink und "
                        .. "Zweitspec kennt nur der Spieler selbst.")
                elseif profile.source == "WARCRAFT_LOGS" then
                    statusText = "Logs"
                    statusHint = GC.L("Stammt aus einem Warcraft-Logs-Import, nicht vom Spieler selbst.")
                elseif profile.source == "MANUAL" then
                    statusText = GC.L("Manuell")
                    statusHint = GC.L("Wurde von Hand eingetragen, nicht vom Spieler selbst.")
                else
                    -- Angezeigt wird "Twink"; gespeichert und uebertragen wird
                    -- weiterhin "ALT", sonst verstehen sich alte und neue
                    -- Clients beim Abgleich nicht mehr.
                    statusText = GC.L(profile.mainStatus == "ALT" and "Twink" or "Main")
                    statusHint = GC.L(profile.mainStatus == "ALT"
                        and "Als Zweitcharakter gemeldet."
                        or "Als Hauptcharakter gemeldet.")
                end
                -- Das Fragezeichen meint "der Spieler hat sein eigenes Profil
                -- nicht bestaetigt". Auf eine abgeleitete Angabe passt das
                -- nicht: Weder Logs noch Talentbaum werden je bestaetigt, und
                -- "erkannt ?" waere schlicht falsch.
                if not profile.confirmed and profile.source ~= "WARCRAFT_LOGS"
                    and profile.source ~= "INSPECT" then
                    statusText = statusText .. " ?"
                    statusColor = THEME.warning
                    statusHint = statusHint .. GC.L(" Der Spieler hat das Profil noch nicht bestätigt.")
                elseif profile.source ~= "INSPECT" then
                    statusColor = THEME.text
                end
            end

            -- In der Spalte die Kurzform, im Tooltip der volle Name.
            local professionText = ShortProfessionSummary(profile)
            row.member = member
            row.tooltipSpec = specText
            row.tooltipProfessions = ProfessionSummary(profile) ~= "–"
                and ProfessionSummary(profile) or ""
            row.tooltipStatus = statusHint

            row.name:SetText(GC.Util.PlayerIdentityName(member.name))
            row.name:SetTextColor(ClassColor(member.classFile))
            row.rank:SetText(member.rank or "–")
            SetTextColor(row.rank, member.rank and THEME.text or THEME.muted)
            row.spec:SetText(specText)
            row.status:SetText(statusText)
            SetTextColor(row.status, statusColor)
            row.professions:SetText(professionText)
            SetTextColor(row.professions, professionText == "–" and THEME.muted or THEME.text)
            row.activity:SetText(LastOnlineLabel(member))
        else
            row.member = nil
        end
    end
end

function GC.UI:BuildSettingsPage()
    local page = self.pages.SETTINGS
    CreatePageTitle(page, "Einstellungen",
        "Lokale Komfortoptionen und gildenweite Berechtigungen für Guild Copilot.")

    local scroll = CreateModernScrollFrame(page)
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -58)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -4, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(752)
    -- Die Karten am Seitenende sind mit der Wartezeit-Erinnerung, der
    -- Sprachwahl und zuletzt der Fensterkarte gewachsen; die Inhaltshoehe
    -- muss mitwachsen, sonst schneidet der Scroller die unterste Zeile ab.
    content:SetHeight(2556)
    scroll:SetScrollChild(content)
    page.settingsScroll = scroll

    local function BuildRankCard(title, x, y, helpText, onChanged)
        local card = CreateCard(content, title)
        -- 280 statt 240: Unter den fuenf Rangzeilen steht in der rechten Karte
        -- der Knopf "Rechte erneut senden". Beide Karten bleiben gleich hoch,
        -- sonst steht die linke wie abgeschnitten daneben.
        card:SetSize(370, 280)
        card:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
        local help = CreateLabel(card, helpText, {
            muted = true,
            width = 334,
            height = 32,
            vertical = "TOP",
        })
        help:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -47)
        local toggles = {}
        for index = 1, 10 do
            local toggle
            toggle = CreateToggle(card, "", function(checked)
                if toggle.rankIndex ~= nil then
                    onChanged(toggle.rankIndex, checked)
                end
            end)
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            toggle:SetPoint("TOPLEFT", card, "TOPLEFT", 18 + (column * 175), -82 - (row * 29))
            toggle.text:SetWidth(137)
            toggle.text:SetJustifyH("LEFT")
            toggles[index] = toggle
        end
        return card, toggles
    end

    page.activeRankCard, page.activeRankToggles = BuildRankCard(
        "Aktive Raider",
        0, 1604,
        GC.L("Diese Ränge erscheinen unabhängig von der Stufe in der Übersicht."),
        function(rankIndex, checked)
            GC.Roster:SetRankActive(rankIndex, checked)
        end
    )
    page.editorRankCard, page.editorRankToggles = BuildRankCard(
        "Gildenweite Einstellungen bearbeiten",
        382, 1604,
        "Nur diese Ränge dürfen Profil, Regeln, Rangfreigaben und Vorlagen ändern.",
        function(rankIndex, checked)
            local success, reason = GC.Roster:SetGuildProfileRankActive(rankIndex, checked)
            if not success then
                if reason == "OWN_RANK" then
                    page.settingsStatus:SetText(GC.L("Den eigenen Rang kannst du nicht abwählen."))
                elseif reason == "HIGHER_RANK_REQUIRED" then
                    page.settingsStatus:SetText(GC.L("Diesen Rang darf nur ein höherer Gildenrang abwählen."))
                elseif reason == "LAST_EDITOR" then
                    page.settingsStatus:SetText(GC.L("Mindestens ein berechtigter Rang muss erhalten bleiben."))
                else
                    page.settingsStatus:SetText(GC.L("Dein Gildenrang darf diese Berechtigung nicht ändern."))
                end
                SetTextColor(page.settingsStatus, THEME.danger)
                GC.UI:RefreshSettings()
            elseif reason == "RECOVERED" then
                page.settingsStatus:SetText(GC.L("Dein eigener Rang wurde einmalig wieder freigeschaltet."))
                SetTextColor(page.settingsStatus, THEME.success)
            end
        end
    )

    -- === Rechte erneut senden ==============================================
    --
    -- Eine Rangfreigabe geht in dem Moment raus, in dem sie gesetzt wird - ueber
    -- den Gildenkanal, und der erreicht nur, wer gerade online ist. Wer den
    -- Moment verpasst, holt sich den Stand beim naechsten Anmelden zwar selbst
    -- ab, aber nur, wenn dann jemand mit dem neueren Stand online ist. Bei zwei
    -- Leuten in einer frischen Gilde ist genau das der Regelfall: Der eine
    -- setzt die Rechte, der andere loggt sich zwei Stunden spaeter ein, wenn
    -- der erste laengst weg ist - und wundert sich, warum nichts ankommt.
    --
    -- Der Knopf ist der direkte Weg fuer den Fall, dass der andere daneben
    -- steht: einmal druecken, und der vollstaendige Stand geht noch einmal in
    -- die Gilde. Gesendet wird dasselbe Paket wie bei jeder Aenderung, der
    -- Zeitstempelvergleich beim Empfaenger entscheidet wie immer - ein
    -- versehentlicher Druck kann also nichts zurueckdrehen.
    page.guildProfilePushButton = CreateButton(page.editorRankCard,
        "Rechte erneut senden", 200, 26, function()
            -- Der Transfer kann fertig sein, bevor dieser Aufruf zurueckkommt -
            -- ein einziger Empfaenger, dessen Quittung sofort da ist, ist genau
            -- dieser Fall. Ohne den Merker schriebe die Zwischenmeldung unten
            -- das Ergebnis wieder zu, und der Knopf staende ewig auf "warte".
            local finished = false
            local broadcast, targets, outdated = GC.Sync:PushGuildProfile(function(_, total, ok, lost)
                if total == 0 then
                    return
                end
                finished = true
                if lost == 0 then
                    page.settingsStatus:SetText(GC.LFormat(
                        "Rechte bestätigt angekommen bei {ok} von {total}.",
                        { ok = ok, total = total }))
                    SetTextColor(page.settingsStatus, THEME.success)
                else
                    page.settingsStatus:SetText(GC.LFormat(
                        "Rechte angekommen bei {ok} von {total} – bei {lost} nicht.",
                        { ok = ok, total = total, lost = lost }))
                    SetTextColor(page.settingsStatus, THEME.danger)
                end
            end)
            if not broadcast then
                page.settingsStatus:SetText(GC.L("Senden nicht möglich – bist du in einer Gilde?"))
                SetTextColor(page.settingsStatus, THEME.danger)
            elseif targets == 0 and (tonumber(outdated) or 0) > 0 then
                -- Wichtig zu unterscheiden: Es ist jemand da, er kann nur nicht
                -- quittieren. Den Rundruf hat er trotzdem bekommen.
                page.settingsStatus:SetText(GC.LFormat(
                    "Gesendet. {n} online mit älterer Fassung – die können den Empfang nicht bestätigen.",
                    { n = outdated }))
                SetTextColor(page.settingsStatus, THEME.muted)
            elseif targets == 0 then
                page.settingsStatus:SetText(GC.L("Gesendet. Gerade ist niemand mit dem Addon online – ohne Empfänger keine Bestätigung."))
                SetTextColor(page.settingsStatus, THEME.muted)
            elseif not finished then
                page.settingsStatus:SetText(GC.LFormat(
                    "Gesendet an {n} – warte auf Bestätigung …", { n = targets }))
                SetTextColor(page.settingsStatus, THEME.accent)
            end
        end)
    page.guildProfilePushButton:SetPoint("TOPLEFT", page.editorRankCard, "TOPLEFT", 18, -226)
    CreateLabel(page.editorRankCard,
        "Für alle, die beim Setzen offline waren.", {
        muted = true,
        width = 334,
        height = 16,
        vertical = "TOP",
    }):SetPoint("TOPLEFT", page.editorRankCard, "TOPLEFT", 18, -254)

    local accessCard = CreateCard(content, "Mitgliederpflege öffnen")
    accessCard:SetSize(752, 180)
    accessCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -1896)
    local accessHelp = CreateLabel(accessCard,
        "Nur diese Ränge sehen die Mitgliederpflege - und nur sie dürfen Raidauswertungen löschen. "
        .. "Die Freigabe wird gildenweit synchronisiert.",
        { muted = true, width = 716, height = 28, vertical = "TOP" })
    accessHelp:SetPoint("TOPLEFT", accessCard, "TOPLEFT", 18, -47)
    page.memberCareAccessToggles = {}
    for index = 1, 10 do
        local toggle
        toggle = CreateToggle(accessCard, "", function(checked)
            if toggle.rankIndex ~= nil
                and not GC.Roster:SetMemberCareAccessRank(toggle.rankIndex, checked) then
                page.settingsStatus:SetText(GC.L("Mindestens ein Rang muss Zugriff auf die Mitgliederpflege behalten."))
                SetTextColor(page.settingsStatus, THEME.danger)
                GC.UI:RefreshSettings()
            end
        end)
        local column = (index - 1) % 5
        local row = math.floor((index - 1) / 5)
        toggle:SetPoint("TOPLEFT", accessCard, "TOPLEFT", 18 + (column * 145), -85 - (row * 31))
        toggle.text:SetWidth(112)
        toggle.text:SetJustifyH("LEFT")
        page.memberCareAccessToggles[index] = toggle
    end

    -- Früher "Benachrichtigungen & Zugriff": ein Sammelsurium aus
    -- Rekrutierungs-Schaltern, Minimap und Profilton. Jetzt klar getrennt:
    -- Hier nur, was die Rekrutierung meldet; Minimap und Profilton stehen in
    -- der Karte "Allgemein".
    local notificationCard = CreateCard(content, "Rekrutierung: Meldungen & Töne")
    notificationCard:SetSize(752, 150)
    notificationCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -1338)
    page.successSoundToggle = CreateToggle(notificationCard, "Erfolgssound aktiv", function(checked)
        GC.DB:GetSettings().successSound = checked
    end)
    page.successSoundToggle:SetPoint("TOPLEFT", notificationCard, "TOPLEFT", 18, -55)

    local soundNames = {}
    for _, sound in ipairs(GC.SuccessSoundOptions) do
        soundNames[#soundNames + 1] = sound.name
    end
    page.successSoundDropdown = CreateChoiceDropdown(notificationCard, 190, soundNames, function(value)
        for _, sound in ipairs(GC.SuccessSoundOptions) do
            if sound.name == value then
                GC.DB:GetSettings().successSoundKey = sound.key
                break
            end
        end
    end, false)
    page.successSoundDropdown:SetPoint("TOPLEFT", notificationCard, "TOPLEFT", 205, -50)
    local testSound = CreateButton(notificationCard, "Sound testen", 130, 32, function()
        GC.Chat:PlaySuccessSound()
    end)
    testSound:SetPoint("LEFT", page.successSoundDropdown, "RIGHT", 8, 0)

    page.captureDuringSearchToggle = CreateToggle(notificationCard, "Whispers nur während einer Suche prüfen", function(checked)
        GC.DB:GetSettings().captureOnlyDuringSearch = checked
    end)
    page.captureDuringSearchToggle:SetPoint("TOPLEFT", notificationCard, "TOPLEFT", 18, -105)
    page.captureDuringSearchToggle.text:SetWidth(290)
    page.watchChannelToggle = CreateToggle(notificationCard, "Öffentliche „Suche Gilde“-Nachrichten erkennen", function(checked)
        GC.DB:GetSettings().watchRecruitmentTriggers = checked
    end)
    page.watchChannelToggle:SetPoint("TOPLEFT", notificationCard, "TOPLEFT", 385, -105)
    page.watchChannelToggle.text:SetWidth(310)
    -- Der Schalter "Auch freie Formulierungen erkennen" stand frueher hier. Er
    -- gehoert aber zur Erkennung, nicht zu Meldungen & Toenen - deshalb steht er
    -- jetzt in der Karte "Postfach-Erkennung", direkt bei den Triggerwoertern,
    -- auf die er sich bezieht.

    -- Minimap und Profilton betreffen nicht die Rekrutierung - sie stehen in
    -- ihrer eigenen Karte "Allgemein".
    local generalCard = CreateCard(content, "Allgemein")
    generalCard:SetSize(752, 150)
    generalCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -168)

    page.minimapToggle = CreateToggle(generalCard, "Minimap-Symbol anzeigen", function(checked)
        GC.DB:GetSettings().minimap.hidden = not checked
        GC.UI:RefreshMinimapButton()
    end)
    page.minimapToggle:SetPoint("TOPLEFT", generalCard, "TOPLEFT", 18, -55)
    page.minimapToggle.text:SetWidth(260)

    -- Eigener Ton fuer die Bestaetigung des eigenen Raidprofils. Bewusst vom
    -- Bewerberklang getrennt: Der eine meldet einen fremden Interessenten, der
    -- andere bestaetigt die eigene Eingabe.
    CreateLabel(generalCard, "Profilbestätigung:", { muted = true, width = 118, height = 32 })
        :SetPoint("TOPLEFT", generalCard, "TOPLEFT", 385, -53)
    page.profileSoundDropdown = CreateChoiceDropdown(generalCard, 190, soundNames, function(value)
        for _, sound in ipairs(GC.SuccessSoundOptions) do
            if sound.name == value then
                GC.DB:GetSettings().profileSoundKey = sound.key
                GC.Chat:PlayProfileSound()
                break
            end
        end
    end, false)
    page.profileSoundDropdown:SetPoint("TOPLEFT", generalCard, "TOPLEFT", 508, -50)

    page.minimapResetButton = CreateButton(generalCard, "Symbol zurück an die Minimap", 230, 28, function()
        GC.UI:ResetMinimapButton()
        GC.UI:RefreshSettings()
    end)
    page.minimapResetButton:SetPoint("TOPLEFT", generalCard, "TOPLEFT", 18, -100)
    CreateLabel(generalCard,
        "Ziehen: am Minimap-Rand. Umschalt + Ziehen: frei platzieren. Normales Ziehen heftet es wieder an.", {
        muted = true,
        width = 460,
        height = 28,
        multiline = true,
    }):SetPoint("TOPLEFT", generalCard, "TOPLEFT", 258, -100)

    -- Der Bewerberton meldet einen fremden Interessenten. Wer nicht rekrutiert,
    -- will ihn nicht hoeren, weiss aber meist nicht, dass er ihn abschalten
    -- koennte - deshalb haengt er am Gildenrang und nicht an jedem selbst.
    local soundRankCard = CreateCard(content, "Bewerberton hören")
    soundRankCard:SetSize(752, 180)
    soundRankCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -1146)
    local soundRankHelp = CreateLabel(soundRankCard,
        "Nur diese Ränge hören den Ton, wenn sich jemand im Postfach meldet. Das Postfach füllt sich für alle weiter,"
        .. " nur still. Die Freigabe wird gildenweit synchronisiert.",
        { muted = true, width = 716, height = 28, vertical = "TOP" })
    soundRankHelp:SetPoint("TOPLEFT", soundRankCard, "TOPLEFT", 18, -47)
    page.inboxSoundRankToggles = {}
    for index = 1, 10 do
        local toggle
        toggle = CreateToggle(soundRankCard, "", function(checked)
            if toggle.rankIndex ~= nil
                and not GC.Roster:SetInboxSoundRank(toggle.rankIndex, checked) then
                page.settingsStatus:SetText(GC.L("Nur freigegebene Gildenränge dürfen den Bewerberton umstellen."))
                SetTextColor(page.settingsStatus, THEME.danger)
                GC.UI:RefreshSettings()
            end
        end)
        local column = (index - 1) % 5
        local row = math.floor((index - 1) / 5)
        toggle:SetPoint("TOPLEFT", soundRankCard, "TOPLEFT", 18 + (column * 145), -85 - (row * 31))
        toggle.text:SetWidth(112)
        toggle.text:SetJustifyH("LEFT")
        page.inboxSoundRankToggles[index] = toggle
    end

    -- Trigger- und Ausschlusswoerter. Bewusst lokal: Sie aendern nur, was im
    -- eigenen Postfach landet. Oeffentliche Nachrichten und Fluestern bleiben
    -- getrennt, weil die Fehlerkosten verschieden sind - ein zu weiter
    -- Whisper-Trigger nervt nur einen selbst, ein zu weiter Chat-Trigger
    -- erzeugt Muell aus dem ganzen Realm.
    local triggerCard = CreateCard(content, "Postfach-Erkennung: eigene Wörter")
    triggerCard:SetSize(752, 440)
    triggerCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -694)
    CreateLabel(triggerCard,
        "Ein Wort oder eine Wendung je Zeile, Groß- und Kleinschreibung ist gleich. Ein Ausschlusswort verhindert den"
        .. " Eintrag auch dann, wenn ein Trigger passt. Es zählt nur, was hier steht: Ein leeres Trigger-Feld erfasst"
        .. " nichts. Nur mit „Auch freie Formulierungen erkennen“ (der Schalter unten) trägt für ein leeres Feld die Vorgabe."
        .. " Diese Listen gelten nur für dich.",
        { muted = true, width = 716, height = 44, vertical = "TOP" })
        :SetPoint("TOPLEFT", triggerCard, "TOPLEFT", 18, -44)

    page.recruitmentWordEdits = {}
    local wordFields = {
        { key = "chatTriggers", label = "Öffentlicher Chat – Trigger", x = 18, y = -96 },
        { key = "chatExclusions", label = "Öffentlicher Chat – Ausschluss", x = 386, y = -96 },
        { key = "whisperTriggers", label = "Flüstern – Trigger", x = 18, y = -212 },
        { key = "whisperExclusions", label = "Flüstern – Ausschluss", x = 386, y = -212 },
    }
    for _, definition in ipairs(wordFields) do
        CreateLabel(triggerCard, definition.label, { muted = true, width = 348, height = 18 })
            :SetPoint("TOPLEFT", triggerCard, "TOPLEFT", definition.x, definition.y)
        local edit = CreateTextArea(triggerCard, 348, 88, 800)
        edit.container:SetPoint("TOPLEFT", triggerCard, "TOPLEFT", definition.x, definition.y - 20)
        page.recruitmentWordEdits[definition.key] = edit
    end

    page.saveRecruitmentWords = CreateButton(triggerCard, "Wörter speichern", 160, 34, function()
        for key, edit in pairs(page.recruitmentWordEdits) do
            GC.Chat:SetRecruitmentWordText(key, edit:GetText())
        end
        page.recruitmentWordStatus:SetText(GC.L("Gespeichert. Ein leeres Trigger-Feld erfasst nichts – außer die freie Erkennung ist an."))
        SetTextColor(page.recruitmentWordStatus, THEME.success)
        GC.UI:RefreshSettings()
    end, "PRIMARY")
    page.saveRecruitmentWords:SetPoint("TOPLEFT", triggerCard, "TOPLEFT", 18, -324)

    CreateButton(triggerCard, "Vorgabe wiederherstellen", 200, 34, function()
        GC.Chat:RestoreRecruitmentDefaults()
        page.recruitmentWordStatus:SetText(GC.L("Alle vier Listen stehen wieder auf der Vorgabe."))
        SetTextColor(page.recruitmentWordStatus, THEME.success)
        GC.UI:RefreshSettings()
    end):SetPoint("TOPLEFT", triggerCard, "TOPLEFT", 186, -324)

    -- Wer die Vorgabe nur um ein Wort ergaenzen will, soll sie nicht abtippen
    -- muessen. Der Knopf traegt sie in die Felder ein, gespeichert wird erst
    -- mit "Woerter speichern".
    CreateButton(triggerCard, "Vorgabe eintragen", 170, 34, function()
        for key, edit in pairs(page.recruitmentWordEdits) do
            edit:SetText(GC.Chat:GetRecruitmentDefaultText(key))
        end
        page.recruitmentWordStatus:SetText(GC.L("Vorgabe eingetragen – jetzt bearbeiten und speichern."))
        SetTextColor(page.recruitmentWordStatus, THEME.muted)
    end):SetPoint("TOPLEFT", triggerCard, "TOPLEFT", 394, -324)

    page.recruitmentWordStatus = CreateLabel(triggerCard, "", { width = 716, height = 18 })
    page.recruitmentWordStatus:SetPoint("TOPLEFT", triggerCard, "TOPLEFT", 18, -366)

    -- Der Hauptschalter der eingebauten Erkennung: OB das Addon ueber die
    -- Wortreihenfolge selbst raet, oder strikt nur die Felder oben zaehlen.
    page.smartDetectionToggle = CreateToggle(triggerCard,
        "Auch freie Formulierungen erkennen („ENH sucht Anschluss an Gilde“)", function(checked)
        GC.DB:GetSettings().smartRecruitmentDetection = checked
    end)
    page.smartDetectionToggle:SetPoint("TOPLEFT", triggerCard, "TOPLEFT", 18, -398)
    page.smartDetectionToggle.text:SetWidth(700)

    local gearCard = CreateCard(content, "Ausrüstung – Hintergrundabgleich")
    gearCard:SetSize(752, 132)
    gearCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -1500)
    CreateLabel(gearCard,
        "Die eigene Ausrüstung wird immer automatisch geprüft und kompakt mit Addon-Nutzern der Gilde abgeglichen.", {
        muted = true,
        width = 716,
        height = 18,
    }):SetPoint("TOPLEFT", gearCard, "TOPLEFT", 18, -44)

    page.gearAcceptToggle = CreateToggle(gearCard, "Vorhandene Verzauberung gilt als in Ordnung", function(checked)
        GC.DB:GetSettings().gearAudit.acceptUnratedEnchants = checked
        GC.GearAudit:ReapplyEnchantRules()
        GC.UI:RefreshGear()
    end)
    page.gearAcceptToggle:SetPoint("TOPLEFT", gearCard, "TOPLEFT", 18, -70)
    page.gearAcceptToggle.text:SetWidth(360)

    CreateLabel(gearCard, "Ohne diesen Schalter bleibt jede nicht bewertete Verzauberung \"Unbekannt\"."
        .. " Er bewertet keine Qualität, er unterscheidet nur verzaubert von nicht verzaubert.", {
        muted = true,
        width = 716,
        height = 30,
        vertical = "TOP",
    }):SetPoint("TOPLEFT", gearCard, "TOPLEFT", 18, -96)

    -- Klang und Bildschirmmeldung der Gildenaufträge. Jedes Ereignis hat
    -- seinen eigenen Ton aus der bekannten Klangliste; "Aus" schaltet es ab.
    local orderCard = CreateCard(content, "Gildenaufträge")
    orderCard:SetSize(752, 352)
    orderCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -330)
    local orderSoundNames = { "Aus" }
    for _, sound in ipairs(GC.SuccessSoundOptions) do
        orderSoundNames[#orderSoundNames + 1] = sound.name
    end
    local function OrderSoundDropdown(labelText, y, eventKey)
        CreateLabel(orderCard, labelText, { muted = true, width = 236, height = 30 })
            :SetPoint("TOPLEFT", orderCard, "TOPLEFT", 18, y)
        local dropdown = CreateChoiceDropdown(orderCard, 190, orderSoundNames, function(value)
            local settings = GC.DB:GetSettings()
            settings.orderSounds = settings.orderSounds or {}
            if value == "Aus" then
                settings.orderSounds[eventKey] = ""
                return
            end
            for _, sound in ipairs(GC.SuccessSoundOptions) do
                if sound.name == value then
                    settings.orderSounds[eventKey] = sound.key
                    GC.Chat:PlaySuccessSound(sound.key)
                    break
                end
            end
        end, false)
        dropdown:SetPoint("TOPLEFT", orderCard, "TOPLEFT", 262, y)
        return dropdown
    end
    page.orderSoundNew = OrderSoundDropdown("Neuer machbarer Auftrag", -48, "newOrder")
    page.orderSoundAccepted = OrderSoundDropdown("Auftrag angenommen", -86, "accepted")
    page.orderSoundProgress = OrderSoundDropdown("Fortschritt an eigenen Aufträgen", -124, "progress")
    page.orderSoundDone = OrderSoundDropdown("Auftrag abgeschlossen", -162, "done")

    CreateLabel(orderCard, "Anzeigedauer der Meldung (Sekunden)",
        { muted = true, width = 236, height = 30 })
        :SetPoint("TOPLEFT", orderCard, "TOPLEFT", 18, -200)
    page.orderBannerHold = CreateEdit(orderCard, 60, 26)
    page.orderBannerHold.container:SetPoint("TOPLEFT", orderCard, "TOPLEFT", 262, -202)
    page.orderBannerHold:SetScript("OnTextChanged", function(edit)
        local seconds = tonumber(GC.Util.Trim(edit:GetText()))
        if seconds then
            GC.DB:GetSettings().orderBanner.holdSeconds =
                math.max(1, math.min(30, math.floor(seconds)))
        end
    end)

    page.orderBannerToggle = CreateToggle(orderCard,
        "Bildschirmmeldung bei neuen machbaren Aufträgen", function(checked)
        GC.DB:GetSettings().orderBanner.enabled = checked
    end)
    page.orderBannerToggle:SetPoint("TOPLEFT", orderCard, "TOPLEFT", 18, -238)
    page.orderBannerToggle.text:SetWidth(340)

    page.orderBannerTest = CreateButton(orderCard, "Meldung testen", 150, 30, function()
        -- Klang und Meldung zusammen, wie im Ernstfall. Der Positionier-Modus
        -- zeigt Kasten und Rand, damit sich der Anker mit der Maus greifen
        -- und verschieben lässt.
        GC.Orders:PlayEventSound("newOrder")
        GC.UI:ShowOrderBanner("Neuer Gildenauftrag von "
            .. GC.Util.PlayerIdentityName(GC:GetPlayerFullName()), true)
    end)
    page.orderBannerTest:SetPoint("TOPRIGHT", orderCard, "TOPRIGHT", -14, -196)
    page.orderBannerReset = CreateButton(orderCard, "Position zurücksetzen", 150, 26, function()
        local bannerSettings = GC.DB:GetSettings().orderBanner
        bannerSettings.x = 0
        bannerSettings.y = 200
        if GC.UI.orderBanner then
            GC.UI.orderBanner:ClearAllPoints()
            GC.UI.orderBanner:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
        end
        GC.UI:ShowOrderBanner("Neuer Gildenauftrag von "
            .. GC.Util.PlayerIdentityName(GC:GetPlayerFullName()), true)
    end)
    page.orderBannerReset:SetPoint("TOPRIGHT", orderCard, "TOPRIGHT", -14, -232)

    -- Der Übergabetext fürs Anflüstern: {name} und {rezept} werden ersetzt,
    -- gesendet wird erst mit Enter im Chat.
    CreateLabel(orderCard, "Übergabetext ({name} und {rezept} werden ersetzt)",
        { muted = true, width = 400, height = 15 })
        :SetPoint("TOPLEFT", orderCard, "TOPLEFT", 18, -272)
    page.orderWhisperEdit = CreateEdit(orderCard, 698, 26)
    page.orderWhisperEdit.container:SetPoint("TOPLEFT", orderCard, "TOPLEFT", 18, -290)
    page.orderWhisperEdit:SetScript("OnTextChanged", function(edit)
        local text = GC.Util.Trim(edit:GetText())
        if text ~= "" then
            GC.DB:GetSettings().orderWhisperText = text
        end
    end)

    CreateLabel(orderCard,
        "Die Meldung lässt sich mit der Maus dorthin schieben, wo sie nichts verdeckt.", {
        muted = true,
        width = 716,
        height = 16,
    }):SetPoint("TOPLEFT", orderCard, "TOPLEFT", 18, -326)

    -- Der Fluesterbefehl der Werkstatt ist bewusst AUS, bis ihn jemand
    -- einschaltet: Das Addon fluestert sonst nie von selbst, und dabei soll
    -- es ohne ausdrueckliche Entscheidung auch bleiben ("Datenschutz und
    -- Fairness"). Die Karte haengt am Seitenende - unten anbauen verschiebt
    -- keine der vermessenen Karten darueber.
    local workshopCard = CreateCard(content, "Werkstatt")
    workshopCard:SetSize(752, 162)
    workshopCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -2088)
    page.workshopWhisperToggle = CreateToggle(workshopCard,
        "Flüsterbefehl beantworten: „!rezept <Suche>“", function(checked)
        GC.DB:GetSettings().workshopWhisperReply = checked
    end)
    page.workshopWhisperToggle:SetPoint("TOPLEFT", workshopCard, "TOPLEFT", 18, -52)
    page.workshopWhisperToggle.text:SetWidth(420)
    CreateLabel(workshopCard,
        "Antwortet Gildenmitgliedern per Flüstern mit Materialliste und Herstellern aus dem Katalog, gedrosselt je Absender.", {
        muted = true,
        width = 716,
        height = 16,
    }):SetPoint("TOPLEFT", workshopCard, "TOPLEFT", 18, -84)
    page.cooldownReminderToggle = CreateToggle(workshopCard,
        "Abgelaufene Berufs-Wartezeiten im Chat melden", function(checked)
        GC.DB:GetSettings().cooldownReminder = checked
    end)
    page.cooldownReminderToggle:SetPoint("TOPLEFT", workshopCard, "TOPLEFT", 18, -104)
    page.cooldownReminderToggle.text:SetWidth(420)
    CreateLabel(workshopCard,
        "Eine Zeile je Sperre (Umwandlung, Spezialtuch, Sphäre), beim Login und bei Ablauf – auch für die eigenen Twinks.", {
        muted = true,
        width = 716,
        height = 16,
    }):SetPoint("TOPLEFT", workshopCard, "TOPLEFT", 18, -136)

    -- Die Sprachwahl. Wie die Werkstatt-Karte ans Seitenende gehaengt, damit
    -- keine vermessene Karte darueber verrutscht. "Automatisch" folgt der
    -- Clientsprache; eine Umstellung wirkt auf bereits gebaute Beschriftungen
    -- erst nach dem Neuladen - der Knopf daneben erledigt das sofort.
    local languageCard = CreateCard(content, "Sprache / Language")
    languageCard:SetSize(752, 108)
    languageCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -2266)
    CreateLabel(languageCard, "Sprache der Oberfläche:", { muted = true, width = 170, height = 28 })
        :SetPoint("TOPLEFT", languageCard, "TOPLEFT", 18, -50)
    page.languageButton = CreateButton(languageCard, "", 200, 28, function()
        local settings = GC.DB:GetSettings()
        local nextLanguage = { AUTO = "DE", DE = "EN", EN = "AUTO" }
        settings.language = nextLanguage[settings.language or "AUTO"] or "AUTO"
        GC.ApplyLanguageSetting()
        GC.UI:RefreshSettings()
    end)
    page.languageButton:SetPoint("TOPLEFT", languageCard, "TOPLEFT", 196, -47)
    page.languageReloadButton = CreateButton(languageCard, "Jetzt neu laden", 140, 28, function()
        if ReloadUI then
            ReloadUI()
        end
    end)
    page.languageReloadButton:SetPoint("TOPLEFT", languageCard, "TOPLEFT", 406, -47)
    CreateLabel(languageCard,
        "„Automatisch“ folgt der Sprache des WoW-Clients. Vollständig wirkt die Umstellung nach dem Neuladen der Oberfläche.", {
        muted = true,
        width = 716,
        height = 16,
    }):SetPoint("TOPLEFT", languageCard, "TOPLEFT", 18, -84)

    -- Fenstergröße und Deckkraft (Nutzerrückmeldung 08/2026: „GCP-Fenster
    -- skalieren oder verkleinern nach Bedarf, oder die Möglichkeit der
    -- Transparenz"). Auch diese Karte hängt am Seitenende.
    --
    -- Skalieren statt Ziehen: Jede Seite ist pixelgenau vermessen - eine
    -- frei ziehbare Fensterkante müsste dreizehn Seiten neu umbrechen, und
    -- tests/validate.mjs rechnet mit genau diesen festen Maßen nach. Ein
    -- Maßstab lässt das Fenster kleiner werden, ohne eine einzige Karte zu
    -- verschieben.
    local windowCard = CreateCard(content, "Fenster")
    windowCard:SetSize(752, 150)
    windowCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -2390)
    CreateLabel(windowCard, "Fenstergröße:", { muted = true, width = 170, height = 28 })
        :SetPoint("TOPLEFT", windowCard, "TOPLEFT", 18, -50)
    page.windowScaleStepper = CreateStepper(windowCard, 70, 130, 5, function(value)
        GC.DB:GetSettings().window.scale = value
        GC.UI:ApplyWindowLook()
    end)
    page.windowScaleStepper:SetPoint("TOPLEFT", windowCard, "TOPLEFT", 196, -50)
    CreateLabel(windowCard, "Deckkraft:", { muted = true, width = 170, height = 28 })
        :SetPoint("TOPLEFT", windowCard, "TOPLEFT", 380, -50)
    page.windowAlphaStepper = CreateStepper(windowCard, 40, 100, 5, function(value)
        GC.DB:GetSettings().window.alpha = value
        GC.UI:ApplyWindowLook()
    end)
    page.windowAlphaStepper:SetPoint("TOPLEFT", windowCard, "TOPLEFT", 500, -50)
    page.windowResetButton = CreateButton(windowCard, "Zurücksetzen", 140, 28, function()
        local windowSettings = GC.DB:GetSettings().window
        windowSettings.scale = 100
        windowSettings.alpha = 100
        GC.UI:ApplyWindowLook()
        GC.UI:RefreshSettings()
    end)
    page.windowResetButton:SetPoint("TOPLEFT", windowCard, "TOPLEFT", 18, -88)
    CreateLabel(windowCard,
        "Gilt für das Hauptfenster und wirkt sofort. Die Deckkraft betrifft das ganze Fenster samt Schrift – wer sie zu weit senkt, liest schlechter.", {
        muted = true,
        width = 716,
        height = 16,
    }):SetPoint("TOPLEFT", windowCard, "TOPLEFT", 18, -122)

    -- Die Chatbefehle dort, wo man sie sucht (Owner-Wunsch): auf der
    -- Einstellungsseite, gespeist aus derselben Tabelle wie /gcp help.
    local commandCard = CreateCard(content, "Chat-Befehle")
    commandCard:SetSize(752, 156)
    commandCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    for index, entry in ipairs(SLASH_COMMANDS) do
        CreateLabel(commandCard, "|cffffffff" .. entry.command .. "|r – " .. entry.description, {
            muted = true,
            font = "GameFontNormalSmall",
            width = 716,
            height = 15,
        }):SetPoint("TOPLEFT", commandCard, "TOPLEFT", 18, -40 - ((index - 1) * 18))
    end

    page.settingsStatus = CreateLabel(content, "", { width = 716, height = 18 })
    page.settingsStatus:SetPoint("TOPLEFT", content, "TOPLEFT", 18, -2048)
end

function GC.UI:RefreshSettings()
    local page = self.pages.SETTINGS
    if not page then
        return
    end
    -- Ohne "announce" bleibt das Setzen stumm: Sonst schriebe jedes Zeichnen
    -- der Seite den Wert zurück in die Einstellungen, den es gerade gelesen hat.
    local window = GC.DB:GetSettings().window or {}
    page.windowScaleStepper:SetValue(tonumber(window.scale) or 100)
    page.windowAlphaStepper:SetValue(tonumber(window.alpha) or 100)
    local ranks = GC.Roster:GetRankDefinitions()
    local canEditGuildProfile = GC.Roster:CanEditGuildProfile()
    -- Nachschicken darf, wer auch setzen darf. Ohne Gilde gibt es nichts zu
    -- senden - dann bleibt der Knopf aus, statt beim Druck zu scheitern.
    SetButtonEnabled(page.guildProfilePushButton,
        canEditGuildProfile and IsInGuild ~= nil and IsInGuild() == true)
    for index = 1, 10 do
        local rank = ranks[index]
        local activeToggle = page.activeRankToggles[index]
        local editorToggle = page.editorRankToggles[index]
        local memberCareAccessToggle = page.memberCareAccessToggles[index]
        local inboxSoundToggle = page.inboxSoundRankToggles[index]
        activeToggle:SetShown(rank ~= nil)
        editorToggle:SetShown(rank ~= nil)
        memberCareAccessToggle:SetShown(rank ~= nil)
        inboxSoundToggle:SetShown(rank ~= nil)
        if rank then
            activeToggle.rankIndex = rank.index
            activeToggle.text:SetText(rank.name)
            SetToggle(activeToggle, GC.Roster:IsRankActive(rank.index))
            if canEditGuildProfile then
                activeToggle:Enable()
            else
                activeToggle:Disable()
            end
            editorToggle.rankIndex = rank.index
            editorToggle.text:SetText(rank.name)
            SetToggle(editorToggle, GC.Roster:IsGuildProfileEditorRank(rank.index))
            memberCareAccessToggle.rankIndex = rank.index
            memberCareAccessToggle.text:SetText(rank.name)
            SetToggle(memberCareAccessToggle, GC.Roster:IsMemberCareAccessRank(rank.index))
            inboxSoundToggle.rankIndex = rank.index
            inboxSoundToggle.text:SetText(rank.name)
            SetToggle(inboxSoundToggle, GC.Roster:IsInboxSoundRank(rank.index))
            if canEditGuildProfile then
                inboxSoundToggle:Enable()
            else
                inboxSoundToggle:Disable()
            end
            if canEditGuildProfile or GC.Roster:CanUseEditorRecovery(rank.index) then
                editorToggle:Enable()
            else
                editorToggle:Disable()
            end
            if canEditGuildProfile then
                memberCareAccessToggle:Enable()
            else
                memberCareAccessToggle:Disable()
            end
        else
            activeToggle.rankIndex = nil
            editorToggle.rankIndex = nil
            memberCareAccessToggle.rankIndex = nil
            inboxSoundToggle.rankIndex = nil
        end
    end

    local settings = GC.DB:GetSettings()
    SetToggle(page.successSoundToggle, settings.successSound)
    SetToggle(page.captureDuringSearchToggle, settings.captureOnlyDuringSearch)
    SetToggle(page.watchChannelToggle, settings.watchRecruitmentTriggers)
    SetToggle(page.smartDetectionToggle, settings.smartRecruitmentDetection)
    -- Ohne Mitlesen gibt es nichts zu erkennen - der feinere Schalter waere
    -- dann eine Einstellung ohne Wirkung. SetButtonEnabled passt hier nicht:
    -- Es blendet button.label ab, ein Schalter traegt seine Beschriftung aber
    -- als .text.
    do
        local smartUsable = settings.watchRecruitmentTriggers == true
        if smartUsable then
            page.smartDetectionToggle:Enable()
        else
            page.smartDetectionToggle:Disable()
        end
        page.smartDetectionToggle.text:SetAlpha(smartUsable and 1 or 0.45)
    end
    SetToggle(page.minimapToggle, not settings.minimap.hidden)
    -- Der Rueckholknopf hat nur einen Sinn, wenn das Symbol tatsaechlich frei
    -- steht und sichtbar ist.
    SetButtonEnabled(page.minimapResetButton,
        settings.minimap.free == true and settings.minimap.hidden ~= true)
    SetToggle(page.gearAcceptToggle, GC.GearAudit:AcceptsUnratedEnchants())
    local selectedSoundName = GC.SuccessSoundOptions[1].name
    for _, sound in ipairs(GC.SuccessSoundOptions) do
        if sound.key == settings.successSoundKey then
            selectedSoundName = sound.name
            break
        end
    end
    page.successSoundDropdown:SetValue(selectedSoundName)

    local profileSoundName
    for _, sound in ipairs(GC.SuccessSoundOptions) do
        if sound.key == (settings.profileSoundKey or GC.DefaultProfileSoundKey) then
            profileSoundName = sound.name
            break
        end
    end
    page.profileSoundDropdown:SetValue(profileSoundName or GC.SuccessSoundOptions[1].name)

    local orderSounds = settings.orderSounds or {}
    local function OrderSoundName(eventKey, fallbackKey)
        local key = orderSounds[eventKey]
        if key == "" then
            return "Aus"
        end
        key = key or fallbackKey
        for _, sound in ipairs(GC.SuccessSoundOptions) do
            if sound.key == key then
                return sound.name
            end
        end
        return "Aus"
    end
    page.orderSoundNew:SetValue(OrderSoundName("newOrder", "LEVEL_UP"))
    page.orderSoundAccepted:SetValue(OrderSoundName("accepted", "IG_QUEST_ACTIVATE"))
    page.orderSoundProgress:SetValue(OrderSoundName("progress", "MAP_PING"))
    page.orderSoundDone:SetValue(OrderSoundName("done", "IG_QUEST_LIST_COMPLETE"))
    SetToggle(page.orderBannerToggle, settings.orderBanner.enabled ~= false)
    -- Nicht ueberschreiben, was gerade getippt wird: Ein SETTINGS_UPDATED aus
    -- dem laufenden Gildenabgleich malt diese Seite neu, auch waehrend hier
    -- jemand die Anzeigedauer oder die Auftrags-Fluestervorlage bearbeitet.
    if not page.orderBannerHold:HasFocus() then
        page.orderBannerHold:SetText(tostring(tonumber(settings.orderBanner.holdSeconds) or 3))
    end
    if not page.orderWhisperEdit:HasFocus() then
        page.orderWhisperEdit:SetText(settings.orderWhisperText or "")
    end
    SetToggle(page.workshopWhisperToggle, settings.workshopWhisperReply == true)
    SetToggle(page.cooldownReminderToggle, settings.cooldownReminder ~= false)
    local language = settings.language or "AUTO"
    if language == "DE" then
        page.languageButton:SetText(GC.L("Deutsch"))
    elseif language == "EN" then
        page.languageButton:SetText(GC.L("English"))
    else
        page.languageButton:SetText(GC.LocaleEnglishDefault
            and "Automatisch (English)" or "Automatisch (Deutsch)")
    end

    -- Was ein leeres Feld bedeutet, haengt am Schalter der freien Erkennung:
    -- mit ihr an traegt die Vorgabe, mit ihr aus erfasst es nichts. Damit
    -- niemand raten muss, welche Erkennung gerade greift, steht es
    -- ausgeschrieben unter den Feldern.
    local defaultLabels = {
        chatTriggers = "öffentlicher Chat",
        whisperTriggers = "Flüstern",
    }
    local usingDefaults = {}
    for _, key in ipairs({ "chatTriggers", "whisperTriggers" }) do
        if GC.Chat:GetRecruitmentWordText(key) == "" then
            usingDefaults[#usingDefaults + 1] = defaultLabels[key]
        end
    end
    for key, edit in pairs(page.recruitmentWordEdits) do
        if not edit:HasFocus() then
            edit:SetText(GC.Chat:GetRecruitmentWordText(key))
        end
    end
    if page.recruitmentWordStatus:GetText() == "" then
        if #usingDefaults > 0 then
            if GC.DB:GetSettings().smartRecruitmentDetection then
                page.recruitmentWordStatus:SetText("Vorgabe greift bei: "
                    .. GC.Util.JoinGerman(usingDefaults) .. ".")
            else
                page.recruitmentWordStatus:SetText("Leeres Feld erfasst nichts bei: "
                    .. GC.Util.JoinGerman(usingDefaults) .. " (freie Erkennung ist aus).")
            end
        else
            page.recruitmentWordStatus:SetText(GC.L("Es gelten durchgehend deine eigenen Listen."))
        end
        SetTextColor(page.recruitmentWordStatus, THEME.muted)
    end

    if canEditGuildProfile then
        if page.settingsStatus:GetText() == "" then
            page.settingsStatus:SetText(GC.L("Gildenweite Änderungen sind für deinen Rang freigegeben."))
            SetTextColor(page.settingsStatus, THEME.muted)
        end
    else
        page.settingsStatus:SetText(GC.L(
            "Gildenweite Einstellungen sind für deinen Rang schreibgeschützt; lokale Optionen bleiben änderbar."))
        SetTextColor(page.settingsStatus, THEME.warning)
    end

    page.settingsScroll:UpdateModernThumb()
end

-- === Einrichtungsassistent =================================================
--
-- Aus dem Willkommensfenster ist ein mehrseitiger Assistent geworden
-- (Owner-Wunsch): das Schriftlogo, eine Funktionstour und die drei Schritte
-- der Checkliste als je eigene Seite, zum Schluss die Fundorte fuer spaeter.
-- Die Seitenfolge und die Tour-Inhalte liegen in Onboarding.lua; hier steht
-- nur, wie jede Seite aussieht.
--
-- Der Assistent nimmt ab, was WoW abnehmen laesst: Die erkannte Spec ist
-- vorgewaehlt und ein Klick bestaetigt sie, die Berufsfenster oeffnen
-- sichere Knoepfe direkt aus dem Assistenten, die Ausruestungspruefung
-- stoesst er selbst an. Und er laesst sich jederzeit verlassen - x, Escape,
-- "Spaeter" oder "Ueberspringen" -, ohne dass etwas verloren geht: Die
-- Checkliste auf der Profilseite zeigt denselben Stand, denn beide fragen
-- dieselben Daten.

-- Der eine Handgriff, den kein Addon abnehmen darf: Ein Berufsfenster
-- oeffnet sich nur ueber das Wirken des Berufszaubers, und das verlangt
-- Blizzard als Hardware-Klick auf einen sicheren Knopf. Der Knopf hier sieht
-- aus wie CreateButton, ist aber ein SecureActionButton; welcher Zauber
-- anliegt, setzt RefreshWizard ausserhalb des Kampfes als Attribut.
--
-- Registriert werden BEIDE Klickflanken. Der Anniversary-Client sitzt auf
-- der modernen Engine, und die fuehrt die geschuetzte Aktion je nach
-- Einstellung (ActionButtonUseKeyDown) beim Druecken ODER beim Loslassen
-- aus - genau einmal je Klick, nie doppelt. Ein Knopf, der nur LeftButtonUp
-- kennt, tut bei der verbreiteten Vorgabe "beim Druecken" schlicht nichts;
-- genau so wurde es gemeldet ("oeffnet nicht mein Berufsfenster").
-- Der Zauber, der das Berufsfenster oeffnet, in der Sprache, die DIESER Client
-- versteht: CastSpellByName("Verzauberkunst") tut auf einem englischen Client
-- schlicht nichts. Kandidaten deutsch zuerst; genommen wird der erste, den das
-- Zauberbuch kennt.
local function ProfessionWindowSpell(professionName)
    for _, candidate in ipairs(GC.ProfessionWindowSpellCandidates(professionName)) do
        if not GC.API.Has("GetSpellInfo") or GC.API.GetSpellInfo(candidate) then
            return candidate
        end
    end
    return professionName
end

local function CreateWizardSpellButton(parent, width, height)
    local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    button:SetSize(width, height)
    if button.RegisterForClicks then
        button:RegisterForClicks("AnyDown", "AnyUp")
    end
    button:SetAttribute("type", "spell")
    button.background = button:CreateTexture(nil, "BACKGROUND")
    button.background:SetAllPoints()
    button.border = button:CreateTexture(nil, "BORDER")
    button.border:SetPoint("TOPLEFT", -1, 1)
    button.border:SetPoint("BOTTOMRIGHT", 1, -1)
    button.border:SetColorTexture(THEME.border[1], THEME.border[2], THEME.border[3], 1)
    button.background:SetDrawLayer("BORDER", 1)
    SetTextureColor(button.background, THEME.accentDark)
    button.label = CreateLabel(button, "", { align = "CENTER", height = height })
    button.label:SetAllPoints()
    button:SetScript("OnEnter", function(selfButton)
        SetTextureColor(selfButton.background, THEME.accent)
    end)
    button:SetScript("OnLeave", function(selfButton)
        SetTextureColor(selfButton.background, THEME.accentDark)
    end)
    return button
end

-- Jede Seite ist ein eigener Rahmen ueber der Navigationsleiste; sichtbar
-- ist immer genau einer.
local function CreateWizardPage(frame, key)
    local page = CreateFrame("Frame", nil, frame)
    page:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    page:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 58)
    page:Hide()
    frame.wizardPages[key] = page
    return page
end

-- Kopf einer Schrittseite: Zaehler in der Akzentfarbe, Titel, ein
-- erklaerender Satz. Der Zaehler zaehlt die SCHRITTE (1 von 3), nicht die
-- Seiten - die Tour ist kein Schritt, und "Seite 3 von 6" stuende schon
-- unten in der Navigationsleiste.
local function CreateWizardStepHeader(page, counter, title, description)
    local chip = CreateLabel(page, counter, {
        color = THEME.accent,
        font = "GameFontNormalSmall",
        height = 14,
    })
    chip:SetPoint("TOPLEFT", page, "TOPLEFT", 26, -22)
    local heading = CreateLabel(page, title, { title = true })
    heading:SetPoint("TOPLEFT", page, "TOPLEFT", 26, -40)
    local help = CreateLabel(page, description, {
        muted = true,
        width = 508,
        height = 32,
        vertical = "TOP",
    })
    help:SetPoint("TOPLEFT", page, "TOPLEFT", 26, -70)
end

-- Seite 1: das Schriftlogo und genau ein grosser Knopf, wie das alte
-- Willkommensfenster. Wer hier schon alles erklaert bekommt, ueberblaettert
-- es - die Tour kommt deshalb erst als eigene Seite danach.
local function BuildWizardWelcomePage(frame)
    local page = CreateWizardPage(frame, "WELCOME")

    local wordmark = page:CreateTexture(nil, "ARTWORK")
    wordmark:SetSize(280, 280)
    wordmark:SetPoint("TOP", page, "TOP", 0, -12)
    wordmark:SetTexture("Interface\\AddOns\\GuildCopilotForever\\Media\\GuildCopilotForeverWordmark")

    local tagline = CreateLabel(page,
        "Dein Gildenassistent für Rekrutierung, Roster, Berufe und Raidauswertung.",
        { muted = true, align = "CENTER", width = 440, height = 34, vertical = "TOP" })
    tagline:SetPoint("TOP", page, "TOP", 0, -294)

    local start = CreateButton(page, "Los geht's", 240, 42, function()
        GC.Onboarding:WizardGo(1)
        GC.UI:ShowWizardPage()
    end, "PRIMARY")
    start:SetPoint("BOTTOM", page, "BOTTOM", 0, 48)
    start.label:SetFontObject("GameFontNormalLarge")
    page.start = start

    -- "Spaeter" schliesst wie das × oben rechts - beide gehen durch
    -- HideWelcomeWithHint, damit der einmalige Hinweis nicht davon abhaengt,
    -- welchen der beiden Knoepfe jemand erwischt.
    local later = CreateButton(page, "Später", 96, 24, function()
        GC.UI:HideWelcomeWithHint()
    end)
    later:SetPoint("BOTTOM", page, "BOTTOM", 0, 16)
    later.label:SetFontObject("GameFontNormalSmall")
    page.later = later
end

-- Vorzeitiges Schliessen, egal ob ueber das × oder "Spaeter": zuklappen und
-- beim ersten Mal je Charakter den Weg zurueck erklaeren. Ein gemeinsamer
-- Weg fuer beide Knoepfe - die Frage "wie komme ich zurueck?" stellt sich
-- nur einmal, nicht einmal je Knopf. "Fertig" und "Guild Copilot öffnen"
-- gehen bewusst NICHT hierdurch: Wer durch ist, verabschiedet sich nicht
-- auf spaeter.
function GC.UI:HideWelcomeWithHint()
    self:HideWelcome()
    if GC.Onboarding:NoteLaterPressed() then
        self:ShowWizardLaterHint()
    end
end

-- Das Hinweisfenster nach dem ersten "Spaeter": ein Satz, ein Knopf. Es
-- beantwortet genau die eine Frage, die das Schliessen aufwirft - wie komme
-- ich zurueck?
function GC.UI:ShowWizardLaterHint()
    if not self.wizardLaterHint then
        local hint = CreatePanel(UIParent, THEME.window, THEME.accent, "GuildCopilotForeverLaterHintFrame")
        hint:SetSize(400, 148)
        hint:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        hint:SetFrameStrata("DIALOG")
        hint:SetToplevel(true)
        hint:EnableMouse(true)
        hint:Hide()
        table.insert(UISpecialFrames, "GuildCopilotForeverLaterHintFrame")

        local title = CreateLabel(hint, "Bis später!", {
            title = true,
            align = "CENTER",
            width = 360,
            height = 20,
        })
        title:SetPoint("TOP", hint, "TOP", 0, -16)
        local text = CreateLabel(hint,
            "Du kannst die Einrichtung jederzeit neu starten: mit /gcp welcome"
                .. " oder über den Knopf „Einrichtung“ oben im Guild-Copilot-Fenster.",
            { muted = true, align = "CENTER", width = 360, height = 46, vertical = "TOP" })
        text:SetPoint("TOP", hint, "TOP", 0, -44)

        local ok = CreateButton(hint, "Alles klar", 140, 32, function()
            GC.UI.wizardLaterHint:Hide()
        end, "PRIMARY")
        ok:SetPoint("BOTTOM", hint, "BOTTOM", 0, 14)
        self.wizardLaterHint = hint
    end
    self.wizardLaterHint:Show()
end

-- Seite 2: die Funktionstour, in der Reihenfolge der Seitenleiste - das WAS
-- steht im Text, das WO ergibt sich daraus, dass die Liste die Seitenleiste
-- selbst ist. Kopf und Zeilen sind auf die Seitenhoehe verteilt statt oben
-- zusammengeschoben (Owner-Wunsch nach dem ersten Blick im Spiel), und jede
-- Zeile traegt das Symbol ihrer Seite. Der Abschnittsname steht nur an der
-- ersten Zeile seines Abschnitts, wie in der Seitenleiste auch.
local function BuildWizardTourPage(frame)
    local page = CreateWizardPage(frame, "TOUR")

    local heading = CreateLabel(page, "Was Guild Copilot kann", {
        title = true,
        align = "CENTER",
        width = 508,
        height = 22,
    })
    heading:SetPoint("TOP", page, "TOP", 0, -24)
    local help = CreateLabel(page,
        "Alles liegt in einem Fenster – die Seitenleiste links gliedert es von oben nach unten:",
        { muted = true, align = "CENTER", width = 508, height = 30, vertical = "TOP" })
    help:SetPoint("TOP", page, "TOP", 0, -52)

    local y = -96
    for _, entry in ipairs(GC.Onboarding.TOUR) do
        local icon = page:CreateTexture(nil, "ARTWORK")
        icon:SetSize(26, 26)
        icon:SetPoint("TOPLEFT", page, "TOPLEFT", 30, y - 2)
        icon:SetTexture(entry.icon)
        -- Der Abschnittsname steht an JEDER Zeile, auch wenn er sich
        -- wiederholt (GILDE zweimal). Der erste Wurf liess ihn bei
        -- Wiederholungen weg, wie die Seitenleiste - dort traegt aber die
        -- Einrueckung die Gruppe, hier sah die Zeile schlicht unfertig aus.
        local section = CreateLabel(page, entry.section, {
            color = THEME.accent,
            font = "GameFontNormalSmall",
            width = 96,
            height = 14,
        })
        section:SetPoint("TOPLEFT", page, "TOPLEFT", 68, y)
        local pagesLabel = CreateLabel(page, entry.pages, {
            font = "GameFontNormalSmall",
            width = 364,
            height = 14,
        })
        pagesLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 170, y)
        local text = CreateLabel(page, entry.text, {
            muted = true,
            font = "GameFontNormalSmall",
            width = 364,
            height = 28,
            vertical = "TOP",
        })
        text:SetPoint("TOPLEFT", page, "TOPLEFT", 170, y - 17)
        y = y - 55
    end
end

-- Seite 3: das Raidprofil. Die erkannte Spec ist vorgewaehlt, ein Klick
-- bestaetigt. Dual-Spec und "flexibel einsetzbar" stehen mit auf der Seite
-- (Owner-Wunsch - der erste Wurf verwies dafuer auf die Profilseite, aber
-- beides gehoert zum Raidprofil und der Platz ist da). Main/Twink und die
-- Abmeldung bleiben draussen: Ein frischer Charakter ist erst einmal so
-- angelegt, wie die Vorgabe ihn annimmt, und ein Assistent, der alles
-- fragt, ist ein Formular.
local function BuildWizardProfilePage(frame)
    local page = CreateWizardPage(frame, "STEP_PROFILE")
    CreateWizardStepHeader(page, "Schritt 1 von 3", "Raidprofil bestätigen",
        "Damit Raidleitung und Rekrutierung wissen, was sie an dir haben."
            .. " Die Spec liest Guild Copilot aus deinen Talenten – bestätigen genügt.")

    page.detected = CreateLabel(page, "", { width = 508, height = 16 })
    page.detected:SetPoint("TOPLEFT", page, "TOPLEFT", 26, -104)

    local primaryLabel = CreateLabel(page, "Primär-Spec", {
        muted = true,
        font = "GameFontNormalSmall",
        height = 14,
    })
    primaryLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 26, -128)
    page.specButtons = {}
    for index = 1, 3 do
        local button = CreateButton(page, "", 106, 32, function(selfButton)
            frame.wizardSpecKey = selfButton.specKey
            -- Dieselbe Regel wie auf der Profilseite: Die Dual-Spec darf
            -- nicht die Primaer-Spec sein; wer beide gleich stellt, waehlt
            -- die Dual-Spec ab.
            if frame.wizardSecondaryKey == selfButton.specKey then
                frame.wizardSecondaryKey = nil
            end
            GC.UI:RefreshWizard()
        end)
        button:SetPoint("TOPLEFT", page, "TOPLEFT", 26 + ((index - 1) * 113), -146)
        page.specButtons[index] = button
    end

    local secondaryLabel = CreateLabel(page, "Dual-Spec (optional)", {
        muted = true,
        font = "GameFontNormalSmall",
        height = 14,
    })
    secondaryLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 26, -192)
    page.noSecondaryButton = CreateButton(page, "Keiner", 78, 32, function()
        frame.wizardSecondaryKey = nil
        GC.UI:RefreshWizard()
    end)
    page.noSecondaryButton:SetPoint("TOPLEFT", page, "TOPLEFT", 26, -210)
    page.secondaryButtons = {}
    for index = 1, 3 do
        local button = CreateButton(page, "", 106, 32, function(selfButton)
            frame.wizardSecondaryKey = selfButton.specKey
            GC.UI:RefreshWizard()
        end)
        button:SetPoint("LEFT", page.noSecondaryButton, "RIGHT", 7 + ((index - 1) * 113), 0)
        page.secondaryButtons[index] = button
    end

    page.flexCheck = CreateToggle(page, "Flexibel einsetzbar", function(enabled)
        frame.wizardFlex = enabled == true
        GC.UI:RefreshWizard()
    end)
    page.flexCheck:SetPoint("TOPLEFT", page, "TOPLEFT", 26, -256)

    page.confirm = CreateButton(page, "Profil bestätigen", 190, 36, function()
        local profile = GC.Profile:Get()
        GC.Profile:Confirm(frame.wizardSpecKey or profile.raidSpecKey or profile.detectedSpecKey,
            frame.wizardSecondaryKey, profile.mainStatus, frame.wizardFlex == true)
        GC.UI:RefreshWizard()
    end, "PRIMARY")
    page.confirm:SetPoint("TOPLEFT", page, "TOPLEFT", 26, -300)

    page.status = CreateLabel(page, "", { width = 508, height = 32, vertical = "TOP" })
    page.status:SetPoint("TOPLEFT", page, "TOPLEFT", 26, -348)

    local hint = CreateLabel(page,
        "Main oder Twink und deine Abmeldung stellst du später im Abschnitt COPILOT auf der Seite „Profil“ ein.",
        { muted = true, font = "GameFontNormalSmall", width = 508, height = 28, vertical = "TOP" })
    hint:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 26, 10)
end

-- Seite 4: die Rezepte. Je erlerntem Beruf eine Zeile mit Symbol, Stand und
-- dem sicheren Oeffnen-Knopf; eingelesen wird beim Oeffnen von selbst
-- (Workshop.lua lauscht auf TRADE_SKILL_SHOW und CRAFT_SHOW).
local function BuildWizardProfessionsPage(frame)
    local page = CreateWizardPage(frame, "STEP_PROFESSIONS")
    CreateWizardStepHeader(page, "Schritt 2 von 3", "Rezepte einlesen",
        "WoW gibt Rezepte nur heraus, solange das Berufsfenster offen ist."
            .. " Der Knopf öffnet es direkt – alles Weitere liest Guild Copilot von selbst.")

    page.rows = {}
    for index = 1, 2 do
        -- Die GANZE Zeile ist ein sicherer Knopf, nicht nur "Fenster
        -- oeffnen": Im Spiel wurde auf Symbol und Namen geklickt und nichts
        -- passierte - was wie ein Eintrag aussieht, muss sich auch so
        -- verhalten. Und sie bleibt auch nach dem Einlesen klickbar; das
        -- Fenster zu oeffnen ist ja weiter erlaubt, nur der Aufforderungs-
        -- Knopf daneben verschwindet dann.
        local row = CreateFrame("Button", nil, page, "SecureActionButtonTemplate")
        row:SetSize(508, 44)
        row:SetPoint("TOPLEFT", page, "TOPLEFT", 26, -116 - ((index - 1) * 54))
        if row.RegisterForClicks then
            row:RegisterForClicks("AnyDown", "AnyUp")
        end
        row:SetAttribute("type", "spell")
        row.hover = row:CreateTexture(nil, "BACKGROUND")
        row.hover:SetAllPoints()
        SetTextureColor(row.hover, THEME.cardHover)
        row.hover:Hide()
        row:SetScript("OnEnter", function(selfRow)
            if selfRow.windowSpell then
                selfRow.hover:Show()
            end
        end)
        row:SetScript("OnLeave", function(selfRow)
            selfRow.hover:Hide()
        end)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(30, 30)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.name = CreateLabel(row, "", { width = 240, height = 16 })
        row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 42, -4)
        row.status = CreateLabel(row, "", {
            muted = true,
            font = "GameFontNormalSmall",
            width = 300,
            height = 14,
        })
        row.status:SetPoint("TOPLEFT", row, "TOPLEFT", 42, -22)
        row.open = CreateWizardSpellButton(row, 140, 30)
        row.open:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row:Hide()
        page.rows[index] = row
    end

    page.empty = CreateLabel(page,
        "Dieser Charakter hat keine Berufe mit Rezepten – hier gibt es nichts zu tun.",
        { muted = true, width = 508, height = 18 })
    page.empty:SetPoint("TOPLEFT", page, "TOPLEFT", 26, -122)
    page.empty:Hide()

    local hint = CreateLabel(page,
        "Danach weiß die Gildenwerkstatt, was du herstellen kannst – zu finden im Abschnitt GILDE.",
        { muted = true, font = "GameFontNormalSmall", width = 508, height = 28, vertical = "TOP" })
    hint:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 26, 10)
end

-- Seite 5: die Ausruestung. Der einzige Schritt ohne Handgriff - die
-- Pruefung laeuft von selbst, und wer die Seite erreicht, bekommt hier ihr
-- Ergebnis statt einer Aufgabe.
local function BuildWizardGearPage(frame)
    local page = CreateWizardPage(frame, "STEP_GEAR")
    CreateWizardStepHeader(page, "Schritt 3 von 3", "Ausrüstung prüfen",
        "Hier musst du nichts tun: Guild Copilot prüft deine angelegten Gegenstände"
            .. " selbst auf fehlende Verzauberungen und leere Sockel.")

    page.findings = CreateLabel(page, "", { width = 508, height = 96, vertical = "TOP" })
    page.findings:SetPoint("TOPLEFT", page, "TOPLEFT", 26, -112)

    page.status = CreateLabel(page, "", {
        muted = true,
        font = "GameFontNormalSmall",
        width = 508,
        height = 28,
        vertical = "TOP",
    })
    page.status:SetPoint("TOPLEFT", page, "TOPLEFT", 26, -216)

    local hint = CreateLabel(page,
        "Die Prüfung aller Raider und den gildenweiten Regelsatz findest du im Abschnitt RAID auf der Seite „Ausrüstung“.",
        { muted = true, font = "GameFontNormalSmall", width = 508, height = 28, vertical = "TOP" })
    hint:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 26, 10)
end

-- Seite 6: die Fundorte fuer spaeter. Der Assistent verabschiedet sich mit
-- den drei Wegen zurueck ins Addon - mehr muss niemand behalten.
local function BuildWizardDonePage(frame)
    local page = CreateWizardPage(frame, "DONE")

    local heading = CreateLabel(page, "Gut zu wissen", { title = true })
    heading:SetPoint("TOPLEFT", page, "TOPLEFT", 26, -22)
    page.status = CreateLabel(page, "", { width = 508, height = 30, vertical = "TOP" })
    page.status:SetPoint("TOPLEFT", page, "TOPLEFT", 26, -52)

    local lines = {
        "Das Minimap-Symbol öffnet Guild Copilot. Ein Punkt daran heißt: Hier wartet etwas auf dich.",
        "/gcp öffnet und schließt das Fenster, /gcp help zeigt alle Befehle im Chat.",
        "Der Knopf „Einrichtung“ im Fensterkopf bringt dich jederzeit zu diesem Assistenten zurück.",
    }
    for index, text in ipairs(lines) do
        local dot = page:CreateTexture(nil, "ARTWORK")
        dot:SetSize(8, 8)
        dot:SetTexture(WHITE_TEXTURE)
        SetTextureColor(dot, THEME.accent)
        dot:SetPoint("TOPLEFT", page, "TOPLEFT", 28, -104 - ((index - 1) * 50))
        local label = CreateLabel(page, text, { width = 462, height = 34, vertical = "TOP" })
        label:SetPoint("TOPLEFT", page, "TOPLEFT", 48, -100 - ((index - 1) * 50))
    end

    local open = CreateButton(page, "Guild Copilot öffnen", 220, 40, function()
        GC.UI:HideWelcome()
        GC.UI:CreateMainFrame()
        GC.UI.frame:Show()
        GC.UI:ShowPage("ROSTER")
        local roster = GC.UI.pages.ROSTER
        if roster and roster.profileScroll then
            roster.profileScroll:SetVerticalScroll(0)
            roster.profileScroll:UpdateModernThumb()
        end
    end, "PRIMARY")
    open:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 26, 12)
end

function GC.UI:CreateWelcomeFrame()
    if self.welcomeFrame then
        return self.welcomeFrame
    end

    local frame = CreatePanel(UIParent, THEME.window, THEME.accent, "GuildCopilotForeverWelcomeFrame")
    frame:SetSize(560, 500)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:Hide()
    table.insert(UISpecialFrames, "GuildCopilotForeverWelcomeFrame")
    frame.wizardPages = {}

    -- Ein × und die Escape-Taste auf jeder Seite, sonst waere das Fenster
    -- eine Falle. Beides schliesst folgenlos - die Checkliste auf der
    -- Profilseite traegt denselben Stand weiter. Das × geht denselben Weg
    -- wie "Spaeter" (Owner-Wunsch): Wer vorzeitig schliesst, bekommt beim
    -- ersten Mal den Hinweis, wie er zurueckkommt - egal ueber welchen Knopf.
    local close = CreateButton(frame, "×", 24, 24, function()
        GC.UI:HideWelcomeWithHint()
    end)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    frame.closeButton = close

    -- Unten rechts in kleiner Schrift der Autor (Owner-Wunsch). Unter den
    -- Knoepfen der Navigationsleiste, damit er auf keiner Seite etwas
    -- verdeckt.
    local credit = CreateLabel(frame, "Nexarius - Thunderstrike", {
        muted = true,
        font = "GameFontNormalSmall",
        align = "RIGHT",
        width = 220,
        height = 12,
    })
    credit:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 4)

    -- Die Navigationsleiste unten. "Ueberspringen" erscheint nur auf einer
    -- Schrittseite mit offenem Schritt und heisst dasselbe wie in der
    -- Checkliste: nicht draengeln - die echte Aktion gewinnt trotzdem.
    -- Die Leiste sitzt nicht ganz unten: Der Streifen darunter gehoert der
    -- Autorenzeile, und ohne den Abstand klebte der Name am Weiter-Knopf.
    frame.pageLabel = CreateLabel(frame, "", {
        muted = true,
        font = "GameFontNormalSmall",
        align = "CENTER",
        width = 120,
        height = 16,
    })
    frame.pageLabel:SetPoint("BOTTOM", frame, "BOTTOM", 0, 35)

    frame.backButton = CreateButton(frame, "Zurück", 96, 30, function()
        GC.Onboarding:WizardGo(-1)
        GC.UI:ShowWizardPage()
    end)
    frame.backButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 26)

    frame.nextButton = CreateButton(frame, "Weiter", 116, 34, function()
        local _, index = GC.Onboarding:GetWizardPage()
        if index >= GC.Onboarding:GetWizardPageCount() then
            -- Der Abschluss klingt nach Stufenaufstieg und meldet sich wie
            -- ein neuer Gildenauftrag (Owner-Wunsch) - unabhaengig vom
            -- eingestellten Bestaetigungston, denn das hier ist keine
            -- Bestaetigung, sondern ein "geschafft".
            if GC.Chat and GC.Chat.PlaySuccessSound then
                GC.Chat:PlaySuccessSound("LEVEL_UP")
            end
            GC.UI:ShowOrderBanner("Guild Copilot is ready for takeoff")
            GC.UI:HideWelcome()
        else
            GC.Onboarding:WizardGo(1)
            GC.UI:ShowWizardPage()
        end
    end, "PRIMARY")
    frame.nextButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 26)

    frame.skipButton = CreateButton(frame, "Überspringen", 120, 30, function()
        GC.Onboarding:SkipWizardStep()
        GC.UI:ShowWizardPage()
        GC.UI:RefreshOnboarding()
    end)
    frame.skipButton:SetPoint("RIGHT", frame.nextButton, "LEFT", -10, 0)

    BuildWizardWelcomePage(frame)
    BuildWizardTourPage(frame)
    BuildWizardProfilePage(frame)
    BuildWizardProfessionsPage(frame)
    BuildWizardGearPage(frame)
    BuildWizardDonePage(frame)

    self.welcomeFrame = frame
    return frame
end

-- Blendet die aktuelle Seite ein und frischt sie auf. Beim Erreichen der
-- Ausruestungsseite wird die Selbstpruefung angestossen, falls noch kein
-- Ergebnis vorliegt - der Schritt verspricht "hier musst du nichts tun",
-- also darf er nicht auf den naechsten Login warten.
function GC.UI:ShowWizardPage()
    local frame = self:CreateWelcomeFrame()
    local definition = GC.Onboarding:GetWizardPage()
    for key, child in pairs(frame.wizardPages) do
        child:SetShown(key == definition.key)
    end
    if definition.key == "STEP_GEAR" and GC.GearAudit
        and not GC.GearAudit:GetAudit(GC:GetPlayerFullName()) then
        GC.GearAudit:AuditSelf(true)
    end
    self:RefreshWizard()
end

function GC.UI:RefreshWizardProfile()
    local frame = self.welcomeFrame
    local page = frame.wizardPages.STEP_PROFILE
    local profile = GC.Profile:Get()
    local classInfo = GC.Classes[profile.classFile or ""] or { specs = {} }
    local done, detail = GC.Onboarding:GetStepState("PROFILE")

    -- Vorauswahl: was im Assistenten geklickt wurde, sonst die gespeicherte
    -- Wahl, sonst die erkannte Spec - dieselbe Rangfolge wie beim Bestaetigen.
    local selectedKey = frame.wizardSpecKey or profile.raidSpecKey or profile.detectedSpecKey
    for index, button in ipairs(page.specButtons) do
        local spec = classInfo.specs[index]
        button:SetShown(spec ~= nil)
        if spec then
            button.specKey = spec.key
            button:SetText(spec.name)
            button:SetActive(spec.key == selectedKey)
        end
    end

    -- Die Dual-Spec-Reihe: Der Knopf der Primaer-Spec ist gesperrt statt
    -- versteckt - eine Luecke saehe nach einem Fehler aus, ein gesperrter
    -- Knopf erklaert sich selbst.
    for index, button in ipairs(page.secondaryButtons) do
        local spec = classInfo.specs[index]
        button:SetShown(spec ~= nil)
        if spec then
            button.specKey = spec.key
            button:SetText(spec.name)
            button:SetActive(spec.key == frame.wizardSecondaryKey)
            if spec.key == selectedKey then
                button:Disable()
            else
                button:Enable()
            end
        end
    end
    page.noSecondaryButton:SetActive(frame.wizardSecondaryKey == nil)
    SetToggle(page.flexCheck, frame.wizardFlex == true)

    local detected = GC.SpecByKey[profile.detectedSpecKey or ""]
    if detected then
        page.detected:SetText("Aus deinen Talenten erkannt: " .. detected.name .. ".")
    else
        page.detected:SetText(GC.L("Keine Talente erkannt – wähle deine Spec von Hand."))
    end

    if done then
        page.status:SetText(detail or "Bestätigt.")
        SetTextColor(page.status, THEME.success)
        page.confirm:SetText(GC.L("Erneut bestätigen"))
    else
        local confirmation = GC.Profile:GetLastConfirmation()
        if confirmation and not confirmation.ok then
            page.status:SetText(confirmation.message or "")
            SetTextColor(page.status, THEME.warning)
        else
            page.status:SetText(GC.L("Ein Klick genügt – ändern kannst du alles jederzeit."))
            SetTextColor(page.status, THEME.muted)
        end
        page.confirm:SetText(GC.L("Profil bestätigen"))
    end
end

function GC.UI:RefreshWizardProfessions()
    local frame = self.welcomeFrame
    local page = frame.wizardPages.STEP_PROFESSIONS
    local profile = GC.Profile:Get()

    -- Was schon eingelesen ist, nach kanonischem Schluessel: Der faengt alle
    -- Schreibweisen desselben Berufs - den Fensternamen ("Schmelzen" fuer
    -- Bergbau) genauso wie die englischen Namen eines englischen Clients.
    local scanned = {}
    for _, profession in pairs((profile.workshop or {}).professions or {}) do
        local name = GC.Util.Trim(profession and profession.name or "")
        if name ~= "" then
            scanned[GC.CanonicalProfessionKey(name)] = true
        end
    end

    local count = 0
    for slot = 1, 2 do
        local name = GC.Util.Trim(((profile.professions or {})[slot] or {}).name or "")
        if name ~= "" and count < #page.rows then
            count = count + 1
            local row = page.rows[count]
            row:Show()
            row.icon:SetTexture(GC.ProfessionIcons[name] or GC.ProfessionIcons[""])
            row.name:SetText(name)
            local windowSpell = ProfessionWindowSpell(name)
            local isScanned = scanned[GC.CanonicalProfessionKey(name)] == true
            -- Der Fensterzauber haengt an Zeile UND Knopf; beim Sammelberuf
            -- an keinem von beiden, dort gibt es kein Fenster. Im Kampf
            -- sperrt WoW das Umstellen sicherer Attribute; dann bleibt der
            -- letzte Zauber stehen, statt einen Fehler zu werfen.
            row.windowSpell = not GC.RecipelessProfessions[name] and windowSpell or nil
            if type(InCombatLockdown) ~= "function" or not InCombatLockdown() then
                row:SetAttribute("spell", row.windowSpell)
                row.open:SetAttribute("spell", row.windowSpell)
            end
            if isScanned then
                row.status:SetText(GC.L("Rezepte eingelesen – ein Klick öffnet das Fenster erneut"))
                SetTextColor(row.status, THEME.success)
                row.open:Hide()
            elseif not row.windowSpell then
                row.status:SetText(GC.L("Sammelberuf ohne Rezepte – nichts einzulesen"))
                SetTextColor(row.status, THEME.muted)
                row.open:Hide()
            else
                row.status:SetText(GC.L("Noch nicht eingelesen"))
                SetTextColor(row.status, THEME.muted)
                row.open.label:SetText(name == windowSpell
                    and "Fenster öffnen" or (windowSpell .. " öffnen"))
                row.open:Show()
            end
        end
    end
    for index = count + 1, #page.rows do
        page.rows[index]:Hide()
    end
    page.empty:SetShown(count == 0)
end

function GC.UI:RefreshWizardGear()
    local frame = self.welcomeFrame
    local page = frame.wizardPages.STEP_GEAR
    local audit = GC.GearAudit and GC.GearAudit:GetAudit(GC:GetPlayerFullName())
    if audit then
        page.findings:SetText(self:FormatGearFindings(audit, 4))
        page.status:SetText(GC.L("Geprüft wird von allein weiter – bei jedem Login und nach jedem Ausrüstungswechsel."))
    else
        page.findings:SetText(GC.L("|cff91a3b8Die Prüfung läuft gerade im Hintergrund – das Ergebnis erscheint hier.|r"))
        page.status:SetText(GC.L(""))
    end
end

function GC.UI:RefreshWizardDone()
    local page = self.welcomeFrame.wizardPages.DONE
    if GC.Onboarding:IsFinished() then
        page.status:SetText(GC.L("Dieser Charakter ist eingerichtet."))
        SetTextColor(page.status, THEME.success)
    else
        page.status:SetText(GC.L("Offene Schritte warten in der Checkliste oben auf der Profilseite – ganz ohne Eile."))
        SetTextColor(page.status, THEME.muted)
    end
end

-- Frischt Navigationsleiste und aktuelle Seite auf. Wird auch von den
-- Datenereignissen gerufen (Bestaetigung, Rezeptscan, Pruefergebnis) und
-- kehrt bei geschlossenem Fenster sofort um.
function GC.UI:RefreshWizard()
    local frame = self.welcomeFrame
    if not frame or not frame:IsShown() then
        return
    end
    local definition, index = GC.Onboarding:GetWizardPage()
    local count = GC.Onboarding:GetWizardPageCount()
    local welcome = definition.key == "WELCOME"
    frame.pageLabel:SetText("Seite " .. index .. " von " .. count)
    frame.pageLabel:SetShown(not welcome)
    frame.backButton:SetShown(not welcome)
    frame.nextButton:SetShown(not welcome)
    frame.nextButton:SetText(index >= count and "Fertig" or "Weiter")
    local stepOpen = definition.step ~= nil
        and not GC.Onboarding:GetStepState(definition.step)
    frame.skipButton:SetShown(stepOpen)

    if definition.key == "STEP_PROFILE" then
        self:RefreshWizardProfile()
    elseif definition.key == "STEP_PROFESSIONS" then
        self:RefreshWizardProfessions()
    elseif definition.key == "STEP_GEAR" then
        self:RefreshWizardGear()
    elseif definition.key == "DONE" then
        self:RefreshWizardDone()
    end
end

function GC.UI:ShowWelcome()
    self:CreateWelcomeFrame()
    -- Jedes Oeffnen beginnt vorn und ohne alte Klickauswahl: Die Tour ist
    -- kurz, und mitten in einer vergessenen Sitzung aufzuwachen waere
    -- verwirrender als zwei bekannte Seiten erneut zu sehen. Dual-Spec und
    -- Flex starten auf dem gespeicherten Stand des Profils - der Assistent
    -- soll ihn ergaenzen, nicht stillschweigend zuruecksetzen.
    local profile = GC.Profile:Get()
    self.welcomeFrame.wizardSpecKey = nil
    self.welcomeFrame.wizardSecondaryKey = profile.secondarySpecKey
    self.welcomeFrame.wizardFlex = profile.flex == true
    GC.Onboarding:StartWizard()
    self.welcomeFrame:Show()
    self:ShowWizardPage()
end

function GC.UI:HideWelcome()
    if self.welcomeFrame then
        self.welcomeFrame:Hide()
    end
end

-- Der Assistent zeigt lebenden Zustand: Bestaetigung, eingelesene Rezepte
-- und das Pruefergebnis kommen ueber dieselben Ereignisse herein wie ueberall
-- sonst - so springt eine Zeile auf Gruen, waehrend das Berufsfenster noch
-- offen ist, und niemand fragt sich, ob der Klick gewirkt hat.
GC:RegisterCallback("PROFILE_UPDATED", GC.UI, function(self)
    self:RefreshWizard()
end)
GC:RegisterCallback("PROFILE_CONFIRMATION_CHANGED", GC.UI, function(self)
    self:RefreshWizard()
end)
GC:RegisterCallback("WORKSHOP_UPDATED", GC.UI, function(self)
    self:RefreshWizard()
end)
GC:RegisterCallback("GEAR_AUDIT_UPDATED", GC.UI, function(self)
    self:RefreshWizard()
end)

-- Zu welcher Karte ein Klick auf eine Checklistenzeile rollt. Alle drei
-- Schritte liegen auf dieser Seite, es ist also ein Rollen und kein
-- Seitenwechsel.
local ONBOARDING_SCROLL_TARGET = {
    PROFILE = "profileCard",
    PROFESSIONS = "professionCard",
    GEAR = "gearCard",
}

-- Rollt die Profilseite an den Kopf einer Karte. Die Position kommt aus
-- ROSTER_CARDS samt der Verschiebung durch die Checkliste, damit hier keine
-- zweite Kopie derselben Masse entsteht.
function GC.UI:ScrollRosterToCard(cardKey)
    local page = self.pages.ROSTER
    if not page or not page.profileScroll then
        return
    end
    local target = 0
    for _, definition in ipairs(ROSTER_CARDS) do
        if definition.key == cardKey then
            target = definition.top
        end
    end
    if page.onboardingCard and page.onboardingCard:IsShown() then
        target = target + ROSTER_ONBOARDING_HEIGHT + ROSTER_CARD_GAP
    end
    local range = tonumber(page.profileScroll:GetVerticalScrollRange()) or 0
    page.profileScroll:SetVerticalScroll(math.max(0, math.min(target, range)))
    page.profileScroll:UpdateModernThumb()
end

-- Die Checkliste "Erste Schritte": der stille Spiegel des Assistenten. Die
-- drei Schritte stehen auf genau dieser Seite, die Karte zeigt nur, was
-- davon noch offen ist - und faengt jeden auf, der den Assistenten
-- zugeklappt hat. Einen "Weiter"-Knopf gibt es deshalb nicht: Die echte
-- Aktion schiebt die Liste weiter, und beide Ansichten fragen dieselben
-- Daten (GetStepState), koennen sich also nie widersprechen.
--
-- Die Zustandszeichen sind Texturen und keine Schriftzeichen: Die Spielschrift
-- kennt weder Haken noch Pfeil und zeichnet dafuer leere Kaesten (dieselbe
-- Lektion wie bei der Profilbestaetigung in 0.9.39).
function GC.UI:BuildOnboardingCard(page, content)
    local card = CreateCard(content, "Erste Schritte")
    card:SetSize(752, ROSTER_ONBOARDING_HEIGHT)
    card:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    card:Hide()
    page.onboardingCard = card

    local close = CreateButton(card, "×", 24, 24, function()
        GC.Onboarding:HideForSession()
        GC.UI:RefreshRoster()
    end)
    close:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -12)

    page.onboardingRows = {}
    for index = 1, 3 do
        local row = CreateFrame("Button", nil, card)
        row:SetSize(716, 40)
        row:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -52 - ((index - 1) * 44))
        row:SetScript("OnClick", function(selfRow)
            GC.UI:ScrollRosterToCard(ONBOARDING_SCROLL_TARGET[selfRow.stepKey or ""])
        end)

        row.dot = row:CreateTexture(nil, "ARTWORK")
        row.dot:SetSize(10, 10)
        row.dot:SetTexture(WHITE_TEXTURE)
        row.dot:SetPoint("TOPLEFT", row, "TOPLEFT", 5, -5)

        -- Der erledigte Schritt traegt ein Haekchen an der Stelle, an der
        -- sonst der Punkt steht - in derselben gruenen Farbe, in der die
        -- Oberflaeche ueberall "erledigt" meldet.
        row.mark = CreateCheckMark(row, 16, THEME.success)
        row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
        row.mark:Hide()

        row.label = CreateLabel(row, "", { width = 420, height = 18 })
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 26, 0)
        row.detail = CreateLabel(row, "", {
            muted = true,
            font = "GameFontNormalSmall",
            width = 560,
            height = 18,
        })
        row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", 26, -19)

        row.skip = CreateButton(row, "Überspringen", 106, 22, function(selfButton)
            GC.Onboarding:SetStepSkipped(selfButton.stepKey, true)
            GC.UI:RefreshRoster()
        end)
        row.skip:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -1)
        row.skip.label:SetFontObject("GameFontNormalSmall")

        page.onboardingRows[index] = row
    end

    page.onboardingDismiss = CreateButton(card, "Nicht mehr anzeigen", 150, 24, function()
        GC.Onboarding:Dismiss()
        GC.UI:RefreshRoster()
    end)
    page.onboardingDismiss:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -190)
    page.onboardingDismiss.label:SetFontObject("GameFontNormalSmall")

    page.onboardingStatus = CreateLabel(card, "", { width = 540, height = 24 })
    page.onboardingStatus:SetPoint("LEFT", page.onboardingDismiss, "RIGHT", 12, 0)
end

-- === Spaltenordnung der Teilnehmertabelle ==================================
-- Die Wertespalten der Raidauswertung lassen sich am Kopf packen und an eine
-- neue Position ziehen (Owner-Wunsch; das frühere Zeilen-Ziehen ist ersatzlos
-- raus). NAME bleibt fest vorn, die Reihenfolge der übrigen Spalten liegt in
-- den Einstellungen und gilt damit für alle Auswertungen.

-- Die Standardreihenfolge ist die vom Owner eingerichtete: Proviant vorn,
-- die Kampfwerte dahinter. TIME ist bewusst KEINE Spalte mehr - die
-- Anwesenheit steht im Zeilen-Tooltip und im Detailfenster, dafür haben
-- alle übrigen Spalten mehr Platz. Alte gespeicherte Ordnungen mit
-- "presence" bereinigt GetStatColumnOrder von selbst.
local STAT_COLUMN_DEFAULTS = { "elixirs", "food", "flasks",
    "drums", "deaths", "potions", "dispels", "interrupts" }

function GC.UI:GetStatColumnOrder()
    local saved = GC.DB:GetSettings().statColumnOrder
    local known = {}
    for _, key in ipairs(STAT_COLUMN_DEFAULTS) do
        known[key] = true
    end
    local order = {}
    local used = {}
    for _, key in ipairs(type(saved) == "table" and saved or {}) do
        if known[key] and not used[key] then
            used[key] = true
            order[#order + 1] = key
        end
    end
    -- Spalten künftiger Versionen hängen hinten an, kaputte Einträge fallen
    -- stillschweigend weg.
    for _, key in ipairs(STAT_COLUMN_DEFAULTS) do
        if not used[key] then
            order[#order + 1] = key
        end
    end
    return order
end

function GC.UI:MoveStatColumn(key, targetPosition)
    local order = self:GetStatColumnOrder()
    local from
    for index, existing in ipairs(order) do
        if existing == key then
            from = index
        end
    end
    if not from then
        return false
    end
    table.remove(order, from)
    table.insert(order, math.max(1, math.min(tonumber(targetPosition) or from, #order + 1)), key)
    GC.DB:GetSettings().statColumnOrder = order
    self:ApplyStatColumnLayout()
    return true
end

-- Setzt Kopfzeile und alle Zellen der Teilnehmertabelle an die Positionen
-- der aktuellen Ordnung. Läuft beim Seitenaufbau und nach jedem Verschieben.
function GC.UI:ApplyStatColumnLayout()
    local page = self.pages.STATISTICS
    if not page or not page.sortHeaderByKey then
        return
    end
    local cursor = 104
    for _, key in ipairs(self:GetStatColumnOrder()) do
        local width = (page.statColumnWidths or {})[key] or 40
        local header = page.sortHeaderByKey[key]
        if header then
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", header:GetParent(), "TOPLEFT", cursor + 13, -66)
        end
        for _, row in ipairs(page.participantRows or {}) do
            local cell = row[key]
            if cell then
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", row, "LEFT", cursor, 0)
            end
        end
        -- 2 Pixel Fuge: Bei acht einheitlichen 46er-Spalten endet die letzte
        -- damit bei 486 und bleibt innerhalb der 490er-Zeile.
        cursor = cursor + width + 2
    end
end

function GC.UI:RefreshMinimapMarker()
    local button = self.minimapButton
    if not button or not button.pending then
        return
    end
    -- Der Punkt zeigt "hier wartet etwas auf dich": offene Einrichtung oder
    -- Gildenaufträge, bei denen der eigene Account dran ist.
    button.pending:SetShown(GC.Onboarding:IsPending()
        or (GC.Orders and GC.Orders:GetActionableCount() > 0))
end

function GC.UI:RefreshOnboarding()
    self:RefreshMinimapMarker()
    local page = self.pages.ROSTER
    if not page or not page.onboardingCard then
        return
    end

    local show = GC.Onboarding:ShouldShow()
    self:LayoutRosterPage(show)
    if not show then
        return
    end

    local steps = GC.Onboarding:GetSteps()
    for index, row in ipairs(page.onboardingRows) do
        local step = steps[index]
        row:SetShown(step ~= nil)
        if step then
            row.stepKey = step.key
            row.skip.stepKey = step.key
            row.label:SetText(step.label)
            row.skip:SetShown(not step.done and not step.skipped)

            if step.done then
                row.mark:Show()
                row.dot:Hide()
                SetTextColor(row.label, THEME.text)
                row.detail:SetText(step.detail or "")
            elseif step.active then
                row.mark:Hide()
                row.dot:Show()
                SetTextureColor(row.dot, THEME.accent)
                SetTextColor(row.label, THEME.text)
                -- Nur der aktuelle Schritt erklaert sich; drei Erklaerungen
                -- gleichzeitig sind keine Anleitung mehr, sondern ein Text.
                row.detail:SetText(step.hint or "")
            else
                row.mark:Hide()
                row.dot:Show()
                -- Uebersprungen tritt weiter zurueck als bloss offen: Der eine
                -- Schritt ist abgewaehlt, der andere kommt noch.
                SetTextureColor(row.dot, step.skipped and THEME.border or THEME.muted)
                SetTextColor(row.label, THEME.muted)
                row.detail:SetText(step.skipped and "Übersprungen" or "")
            end
        end
    end

    if GC.Onboarding:IsFinished() then
        if GC.Onboarding:NoteCompleted() and GC.Chat and GC.Chat.PlayProfileSound then
            GC.Chat:PlayProfileSound()
        end
        page.onboardingStatus:SetText(GC.L("Fertig – dieser Charakter ist eingerichtet."))
        SetTextColor(page.onboardingStatus, THEME.success)
    else
        page.onboardingStatus:SetText(GC.L(""))
    end
end

function GC.UI:BuildRosterPage()
    local page = self.pages.ROSTER
    CreatePageTitle(page, "Dein Profil",
        "Raidprofil, Berufe und Abmeldung an einem Ort – diese Angaben werden mit Guild-Copilot-Nutzern in deiner Gilde synchronisiert.")

    local scroll = CreateModernScrollFrame(page)
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -58)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -4, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(752)
    content:SetHeight(ROSTER_CONTENT_HEIGHT)
    scroll:SetScrollChild(content)
    page.profileScroll = scroll
    page.profileContent = content

    self:BuildOnboardingCard(page, content)

    local profileCard = CreateCard(content, "Dein Raidprofil")
    profileCard:SetSize(374, 408)
    page.profileCard = profileCard

    page.detectedText = CreateLabel(profileCard, "", { muted = true, width = 338, height = 36, vertical = "TOP" })
    page.detectedText:SetPoint("TOPLEFT", profileCard, "TOPLEFT", 18, -50)

    local primaryLabel = CreateLabel(profileCard, "Primär-Spec")
    primaryLabel:SetPoint("TOPLEFT", profileCard, "TOPLEFT", 18, -95)
    page.profileSpecButtons = {}
    for index = 1, 3 do
        local button = CreateButton(profileCard, "", 106, 32, function(selfButton)
            page.selectedProfileSpec = selfButton.specKey
            if page.selectedSecondarySpec == selfButton.specKey then
                page.selectedSecondarySpec = nil
            end
            GC.UI:RefreshRoster()
        end)
        button:SetPoint("TOPLEFT", profileCard, "TOPLEFT", 18 + ((index - 1) * 113), -120)
        page.profileSpecButtons[index] = button
    end

    local secondaryLabel = CreateLabel(profileCard, "Dual-Spec (optional)")
    secondaryLabel:SetPoint("TOPLEFT", profileCard, "TOPLEFT", 18, -169)
    page.noSecondaryButton = CreateButton(profileCard, "Keiner", 78, 32, function()
        page.selectedSecondarySpec = nil
        GC.UI:RefreshRoster()
    end)
    page.noSecondaryButton:SetPoint("TOPLEFT", profileCard, "TOPLEFT", 18, -194)
    page.secondarySpecButtons = {}
    for index = 1, 3 do
        local button = CreateButton(profileCard, "", 80, 32, function(selfButton)
            if selfButton.specKey ~= page.selectedProfileSpec then
                page.selectedSecondarySpec = selfButton.specKey
            end
            GC.UI:RefreshRoster()
        end)
        button:SetPoint("LEFT", page.noSecondaryButton, "RIGHT", 7 + ((index - 1) * 87), 0)
        page.secondarySpecButtons[index] = button
    end

    -- Jede Aenderung frischt die Karte auf: Nur so faellt der Haken der letzten
    -- Bestaetigung weg und der Hinweis erscheint, dass erneut zu bestaetigen
    -- ist. Ohne den Aufruf blieb die Rueckmeldung bis zum naechsten
    -- Seitenwechsel auf dem alten Stand.
    page.mainCheck = CreateToggle(profileCard, "Main", function(enabled)
        if enabled then
            page.selectedMainStatus = "MAIN"
            SetToggle(page.altCheck, false)
        else
            SetToggle(page.mainCheck, true)
        end
        GC.UI:RefreshRoster()
    end)
    page.mainCheck:SetPoint("TOPLEFT", profileCard, "TOPLEFT", 18, -251)

    page.altCheck = CreateToggle(profileCard, "Twink", function(enabled)
        if enabled then
            page.selectedMainStatus = "ALT"
            SetToggle(page.mainCheck, false)
        else
            SetToggle(page.altCheck, true)
        end
        GC.UI:RefreshRoster()
    end)
    page.altCheck:SetPoint("LEFT", page.mainCheck, "RIGHT", 92, 0)

    page.flexCheck = CreateToggle(profileCard, "Flexibel einsetzbar", function(enabled)
        page.selectedFlex = enabled
        GC.UI:RefreshRoster()
    end)
    page.flexCheck:SetPoint("TOPLEFT", profileCard, "TOPLEFT", 18, -292)

    local confirm = CreateButton(profileCard, "Bestätigen", 190, 38, function()
        local profile, message = GC.Profile:Confirm(
            page.selectedProfileSpec,
            page.selectedSecondarySpec,
            page.selectedMainStatus,
            page.selectedFlex
        )
        if not profile and message then
            GC:Print(message)
        end
        GC.UI:RefreshRoster()
    end, "PRIMARY")
    confirm:SetPoint("BOTTOMLEFT", profileCard, "BOTTOMLEFT", 18, 18)

    -- Ergebnis der letzten Bestaetigung. Im Chat war es nach ein paar
    -- Kampfmeldungen weggescrollt; hier steht es, bis sich etwas aendert.
    --
    -- Der Erfolgsfall braucht keine Worte: ein Haken genuegt, und ein Datum
    -- passte neben dem Knopf ohnehin nicht hin. Nur ein Fehlschlag muss
    -- erklaeren, was zu tun ist.
    page.profileStatusMark = CreateCheckMark(profileCard, 22, THEME.success)
    page.profileStatusMark:SetPoint("LEFT", confirm, "RIGHT", 8, 0)
    page.profileStatusMark:Hide()

    -- Die Rueckmeldung steht ueber dem Knopf und nicht daneben: Neben ihm blieb
    -- nur eine schmale Spalte, in der jeder erklaerende Satz abgeschnitten
    -- wurde - und ausgerechnet der Fehlschlag muss sagen, was zu tun ist.
    page.profileStatus = CreateLabel(profileCard, "",
        { width = 338, height = 32, font = "GameFontNormalSmall", multiline = true, vertical = "TOP" })
    page.profileStatus:SetPoint("TOPLEFT", profileCard, "TOPLEFT", 18, -316)

    local professions = CreateCard(content, "Deine Berufe")
    professions:SetSize(388, 408)
    page.professionCard = professions
    -- Zwei Dinge, die beide "Berufe" heissen und leicht verwechselt werden:
    -- die Namen hier oben liest das Addon selbst aus deinen Faehigkeiten, die
    -- Rezepte dagegen gibt WoW nur bei geoeffnetem Berufsfenster heraus.
    local professionHelp = CreateLabel(professions,
        "Deine beiden Hauptberufe – vom Addon aus deinen Fähigkeiten gelesen, sonst hier von Hand wählbar. Für die Rezepte in der Gildenwerkstatt musst du dein Berufsfenster einmal öffnen; die Namen allein genügen dafür nicht.",
        { muted = true, width = 352, height = 64, vertical = "TOP" })
    professionHelp:SetPoint("TOPLEFT", professions, "TOPLEFT", 18, -54)

    page.professionDropdowns = {}
    for slot = 1, 2 do
        local professionSlot = slot
        local dropdown = CreateChoiceDropdown(professions, 170, GC.ProfessionOptions, function(value)
            if GC.Util.Trim(value) == "" then
                -- Die leere Auswahl heißt: wieder automatisch aus den
                -- Fähigkeiten lesen. Den früheren Übernehmen-Knopf ersetzt
                -- das vollständig.
                GC.Profile:EnableProfessionSync()
            else
                GC.Profile:SetProfession(professionSlot, value)
            end
            GC.UI:RefreshRoster()
        end)
        dropdown:SetPoint("TOPLEFT", professions, "TOPLEFT", 18 + ((slot - 1) * 182), -130)
        page.professionDropdowns[slot] = dropdown
    end
    -- Statt eines Übernehmen-Knopfs (die Übernahme läuft von selbst) steht
    -- hier der Werkstatt-Stand je Beruf: Skill, geteilte Rezepte, Alter des
    -- letzten Einlesens - und der nächste Schritt, wenn Rezepte fehlen.
    page.professionLines = {}
    for slot = 1, 2 do
        local line = CreateLabel(professions, "", { width = 352, height = 20 })
        line:SetPoint("TOPLEFT", professions, "TOPLEFT", 18, -184 - ((slot - 1) * 24))
        page.professionLines[slot] = line
    end
    page.professionStatus = CreateLabel(professions, "", { muted = true, width = 352, height = 42, vertical = "TOP" })
    page.professionStatus:SetPoint("TOPLEFT", professions, "TOPLEFT", 18, -238)
    local workshopButton = CreateButton(professions, "Zur Gildenwerkstatt", 210, 36, function()
        GC.UI:ShowPage("WORKSHOP")
    end)
    workshopButton:SetPoint("BOTTOMLEFT", professions, "BOTTOMLEFT", 18, 18)

    local absenceCard = CreateCard(content, "Deine Abmeldung")
    absenceCard:SetSize(752, 180)
    page.absenceCard = absenceCard
    local absenceHelp = CreateLabel(absenceCard,
        "Trage hier direkt ein, wann du nicht verfügbar bist. Mitgliederpflege und Roster berücksichtigen den Zeitraum automatisch.",
        { muted = true, width = 716 })
    absenceHelp:SetPoint("TOPLEFT", absenceCard, "TOPLEFT", 18, -46)

    local absenceFields = {
        { key = "FROM", label = "Von", x = 18, width = 142, calendar = true },
        { key = "TO", label = "Bis", x = 170, width = 142, calendar = true },
        { key = "REASON", label = "Grund (optional)", x = 322, width = 412 },
    }
    page.absenceEdits = {}
    for _, field in ipairs(absenceFields) do
        local label = CreateLabel(absenceCard, field.label, {
            muted = true,
            font = "GameFontNormalSmall",
            width = field.width,
        })
        label:SetPoint("TOPLEFT", absenceCard, "TOPLEFT", field.x, -72)
        local edit = CreateEdit(absenceCard, field.width, 34)
        edit.container:SetPoint("TOPLEFT", absenceCard, "TOPLEFT", field.x, -91)
        edit:SetMaxLetters(field.key == "REASON" and 80 or 10)
        -- userInput unterscheidet Tippen von unserem eigenen SetText. Nur
        -- Tippen macht das Formular zum Eigentum des Nutzers.
        edit:SetScript("OnTextChanged", function(_, userInput)
            if userInput then
                page.absenceDirty = true
            end
        end)
        page.absenceEdits[field.key] = edit
        if field.calendar then
            -- Das Kalendersymbol sitzt im Feld rechts; getippt werden darf
            -- weiterhin, der Kalender ist das Angebot, nicht die Pflicht.
            --
            -- Gezeichnet, nicht geschrieben: Hier stand ein "📅", und die
            -- WoW-Schrift kennt kein einziges Emoji - in beiden Feldern stand
            -- deshalb ein leerer Kasten.
            local pick = CreateButton(absenceCard, "", 26, 26, function()
                GC.UI:OpenDatePicker(edit, function(iso)
                    edit:SetText(iso)
                    page.absenceDirty = true
                end)
            end)
            SetButtonMark(pick, CreateCalendarMark(pick, 17))
            AttachEditButton(edit, pick, 26)
            page.absenceEdits[field.key .. "_PICK"] = pick
        end
    end
    page.saveAbsence = CreateButton(absenceCard, "Abmelden", 130, 32, function()
        local success, message = GC.Profile:SetAbsence(
            page.absenceEdits.FROM:GetText(),
            page.absenceEdits.TO:GetText(),
            page.absenceEdits.REASON:GetText()
        )
        page.absenceStatus:SetText(message or "")
        SetTextColor(page.absenceStatus, success and THEME.success or THEME.danger)
        if success then
            -- Gespeichert heisst: Der gespeicherte Stand darf die Felder wieder
            -- fuellen - und zeigt dann auch die umgerechnete ISO-Schreibweise.
            page.absenceDirty = nil
            GC.UI:RefreshRoster()
        end
    end, "PRIMARY")
    page.saveAbsence:SetPoint("TOPLEFT", absenceCard, "TOPLEFT", 18, -135)
    page.clearAbsence = CreateButton(absenceCard, "Abmeldung löschen", 160, 32, function()
        GC.Profile:ClearAbsence()
        page.absenceStatus:SetText(GC.L("Abmeldung gelöscht und mit der Gilde synchronisiert."))
        SetTextColor(page.absenceStatus, THEME.success)
        page.absenceDirty = nil
        GC.UI:RefreshRoster()
    end)
    page.clearAbsence:SetPoint("LEFT", page.saveAbsence, "RIGHT", 8, 0)
    -- Meldungen wie "Abmeldung gespeichert und fuer die Gilde synchronisiert."
    -- brauchen gelegentlich zwei Zeilen; die Hoehe ist dafuer ausgelegt.
    page.absenceStatus = CreateLabel(absenceCard, "", { width = 402, height = 32, multiline = true })
    page.absenceStatus:SetPoint("LEFT", page.clearAbsence, "RIGHT", 12, 0)

    local gearCard = CreateCard(content, "Deine Ausrüstung")
    gearCard:SetSize(752, 162)
    page.gearCard = gearCard
    local gearHelp = CreateLabel(gearCard,
        "Prüft deine eigene Ausrüstung auf fehlende Verzauberungen und leere Sockel. Läuft nur bei dir und ohne Gruppe.",
        { muted = true, width = 560, height = 18, vertical = "TOP" })
    gearHelp:SetPoint("TOPLEFT", gearCard, "TOPLEFT", 18, -46)

    page.profileGearFindings = CreateLabel(gearCard, "", { width = 560, height = 62, vertical = "TOP" })
    page.profileGearFindings:SetPoint("TOPLEFT", gearCard, "TOPLEFT", 18, -70)
    page.profileGearAge = CreateLabel(gearCard, "", { muted = true, width = 560, height = 18 })
    page.profileGearAge:SetPoint("BOTTOMLEFT", gearCard, "BOTTOMLEFT", 18, 12)

    page.profileGearButton = CreateButton(gearCard, "Ausrüstung prüfen", 150, 30, function()
        local ok, message = GC.GearAudit:AuditSelf()
        if not ok and message then
            GC:Print(message)
        end
        GC.UI:RefreshRoster()
    end, "PRIMARY")
    page.profileGearButton:SetPoint("TOPRIGHT", gearCard, "TOPRIGHT", -18, -46)

    page.profileGearOpen = CreateButton(gearCard, "Alle Prüfungen", 150, 26, function()
        GC.UI:ShowPage("GEAR")
    end)
    page.profileGearOpen:SetPoint("TOPRIGHT", page.profileGearButton, "BOTTOMRIGHT", 0, -6)

    -- Alle Kartenpositionen kommen aus ROSTER_CARDS, auch die erste Fassung:
    -- Zwei Quellen fuer dieselben Masse waeren zwei Gelegenheiten, sie
    -- auseinanderlaufen zu lassen.
    self:LayoutRosterPage(false)
end

-- Verschiebt die Karten der Profilseite, je nachdem ob die Checkliste "Erste
-- Schritte" darueber steht. Sie ist die einzige Karte, die kommt und geht -
-- der Rest wandert geschlossen um denselben Betrag mit.
function GC.UI:LayoutRosterPage(showOnboarding)
    local page = self.pages.ROSTER
    if not page or not page.profileContent then
        return
    end
    local shift = showOnboarding and (ROSTER_ONBOARDING_HEIGHT + ROSTER_CARD_GAP) or 0
    if page.onboardingCard then
        page.onboardingCard:SetShown(showOnboarding == true)
    end
    for _, definition in ipairs(ROSTER_CARDS) do
        local card = page[definition.key]
        if card then
            local anchor = definition.anchor or "TOPLEFT"
            card:ClearAllPoints()
            card:SetPoint(anchor, page.profileContent, anchor, 0, -(definition.top + shift))
        end
    end
    page.profileContent:SetHeight(ROSTER_CONTENT_HEIGHT + shift)
end

function GC.UI:RefreshProfileGear()
    local page = self.pages.ROSTER
    if not page or not page.profileGearFindings then
        return
    end
    local audit = GC.GearAudit:GetAudit(GC:GetPlayerFullName())
    if not audit then
        page.profileGearFindings:SetText(GC.L("|cff91a3b8Noch nicht geprüft. Ein Klick auf "
            .. "\"Ausrüstung prüfen\" liest deine angelegten Gegenstände aus.|r"))
        page.profileGearAge:SetText(GC.L(""))
        return
    end
    page.profileGearFindings:SetText(self:FormatGearFindings(audit, 3))
    local ageMinutes = math.max(0, math.floor((GC.Util.Now() - (audit.inspectedAt or 0)) / 60))
    page.profileGearAge:SetText("Zuletzt geprüft vor " .. ageMinutes .. " Minuten.")
end

-- Weicht die Auswahl auf der Karte vom gespeicherten Profil ab? Dann ist sie
-- noch nicht bestaetigt. Verglichen wird gegen genau die Werte, mit denen die
-- Karte auch vorbelegt wird - sonst gaelte ein frisches Profil schon beim
-- Aufschlagen als geaendert.
local function ProfileSelectionChanged(page, profile)
    if page.selectedProfileSpec ~= (profile.raidSpecKey or profile.detectedSpecKey) then
        return true
    end
    if page.selectedSecondarySpec ~= profile.secondarySpecKey then
        return true
    end
    if (page.selectedMainStatus or "MAIN") ~= (profile.mainStatus or "MAIN") then
        return true
    end
    return (page.selectedFlex == true) ~= (profile.flex == true)
end

function GC.UI:RefreshRoster()
    local page = self.pages.ROSTER
    if not page then
        return
    end
    self:RefreshOnboarding()
    self:RefreshProfileGear()

    local profile = GC.Profile:Get()
    local detected = GC.SpecByKey[profile.detectedSpecKey or ""]
    page.detectedText:SetText("Erkannt: " .. (detected and detected.name or "noch nicht ermittelbar")
        .. "  •  Talente " .. (profile.talentSignature or "0/0/0"))

    -- Die Vorbelegung steht vor der Rueckmeldung: Ohne sie waere die Auswahl
    -- beim ersten Aufschlagen noch leer und damit rechnerisch "geaendert".
    if page.selectedProfileSpec == nil then
        page.selectedProfileSpec = profile.raidSpecKey or profile.detectedSpecKey
    end
    if page.secondaryInitialized ~= true then
        page.selectedSecondarySpec = profile.secondarySpecKey
        page.secondaryInitialized = true
    end
    page.selectedMainStatus = page.selectedMainStatus or profile.mainStatus or "MAIN"
    if page.selectedFlex == nil then
        page.selectedFlex = profile.flex == true
    end

    -- Der Bestaetigungsstatus bleibt stehen: erst die letzte Rueckmeldung,
    -- sonst der gespeicherte Stand des Profils.
    if page.profileStatus then
        local confirmation = GC.Profile:GetLastConfirmation()
        local changed = ProfileSelectionChanged(page, profile)
        if confirmation and not confirmation.ok then
            -- Nur der Fehlschlag braucht Worte: Er sagt, was zu tun ist.
            page.profileStatusMark:Hide()
            page.profileStatus:SetText(confirmation.message or "Bestätigung fehlgeschlagen.")
            SetTextColor(page.profileStatus, THEME.danger)
        elseif changed and profile.confirmed then
            -- Der Haken der letzten Bestaetigung darf nicht ueber einer
            -- laengst geaenderten Auswahl stehen bleiben: Gespeichert und
            -- gildenweit geteilt ist weiterhin der alte Stand.
            page.profileStatusMark:Hide()
            page.profileStatus:SetText(GC.L("Geändert – noch nicht bestätigt. "
                .. "In der Gilde steht weiter der zuletzt bestätigte Stand."))
            SetTextColor(page.profileStatus, THEME.warning)
        elseif profile.confirmed then
            page.profileStatusMark:Show()
            page.profileStatus:SetText(GC.L(""))
        else
            page.profileStatusMark:Hide()
            page.profileStatus:SetText(GC.L("Noch nicht bestätigt."))
            SetTextColor(page.profileStatus, THEME.muted)
        end
    end

    local classInfo = GC.Classes[profile.classFile or ""]
    for index, button in ipairs(page.profileSpecButtons) do
        local spec = classInfo and classInfo.specs[index]
        button:SetShown(spec ~= nil)
        if spec then
            button.specKey = spec.key
            button:SetText(spec.name)
            button:SetActive(page.selectedProfileSpec == spec.key)
        end
    end
    for index, button in ipairs(page.secondarySpecButtons) do
        local spec = classInfo and classInfo.specs[index]
        button:SetShown(spec ~= nil)
        if spec then
            button.specKey = spec.key
            button:SetText(spec.name)
            button:SetActive(page.selectedSecondarySpec == spec.key)
        end
    end
    page.noSecondaryButton:SetActive(page.selectedSecondarySpec == nil)
    SetToggle(page.mainCheck, page.selectedMainStatus ~= "ALT")
    SetToggle(page.altCheck, page.selectedMainStatus == "ALT")
    SetToggle(page.flexCheck, page.selectedFlex)
    for slot = 1, 2 do
        local profession = profile.professions and profile.professions[slot]
        page.professionDropdowns[slot]:SetValue(profession and profession.name or "")
    end
    -- Werkstatt-Stand je Beruf: Wie viele Rezepte hängen schon in der
    -- Gildenwerkstatt, und wie alt ist der Stand? Fehlen Rezepte, steht der
    -- nächste Schritt gleich daneben - das Einlesen braucht ein einmal
    -- geöffnetes Berufsfenster.
    for slot = 1, 2 do
        local line = page.professionLines[slot]
        local profession = (profile.professions or {})[slot]
        local professionName = profession and GC.Util.Trim(profession.name or "") or ""
        if professionName == "" then
            line:SetText(GC.L(""))
        else
            local skill = tonumber(profession.skillLevel) or 0
            local maxSkill = tonumber(profession.maxSkillLevel) or 0
            local skillText = skill > 0
                and (" " .. skill .. (maxSkill > 0 and ("/" .. maxSkill) or ""))
                or ""
            local stored = GC.Workshop:GetOwnProfession(professionName)
            local recipeCount = 0
            for _ in pairs((stored and stored.recipes) or {}) do
                recipeCount = recipeCount + 1
            end
            -- Knapp halten: Die Karte ist 388 Pixel breit, und
            -- "Verzauberkunst 375/375" braucht davon schon die Hälfte.
            -- Dass die Rezepte in der Werkstatt liegen, erklärt der Text
            -- direkt darunter.
            if recipeCount > 0 then
                local ageMinutes = math.max(0,
                    math.floor((GC.Util.Now() - (stored.updatedAt or 0)) / 60))
                local ageText = ageMinutes < 120 and (ageMinutes .. " Min.")
                    or ageMinutes < 2880 and (math.floor(ageMinutes / 60) .. " Std.")
                    or (math.floor(ageMinutes / 1440) .. " Tagen")
                line:SetText(professionName .. skillText .. " · |cff59e695"
                    .. recipeCount .. " Rezepte|r · vor " .. ageText)
                SetTextColor(line, THEME.text)
            else
                line:SetText(professionName .. skillText
                    .. " · |cffffb840Rezepte fehlen|r – Beruf einmal öffnen.")
                SetTextColor(line, THEME.text)
            end
        end
    end

    -- Die Statuszeile sagt, was tatsaechlich passiert ist. Bis 0.9.45 meldete
    -- sie unterschiedslos eine laufende Uebernahme, auch wenn der Client die
    -- Berufsliste gar nicht herausgibt - dann blieb die Angabe von Hand stehen
    -- und sah aus wie ein Ergebnis.
    local professionSource = GC.Profile:GetProfessionSource(profile)
    if professionSource == "OK" then
        page.professionStatus:SetText(GC.L("Automatisch aus deinen Fähigkeiten übernommen. "
            .. "Neue Rezepte wandern beim Öffnen des Berufsfensters von selbst in die Werkstatt."))
        SetTextColor(page.professionStatus, THEME.muted)
    elseif professionSource == "EMPTY" then
        page.professionStatus:SetText(GC.L("Nachgesehen: Dieser Charakter hat keinen Hauptberuf erlernt."))
        SetTextColor(page.professionStatus, THEME.muted)
    elseif professionSource == "MANUAL" then
        page.professionStatus:SetText(GC.L("Von Hand gewählt. Die leere Auswahl oben schaltet zurück "
            .. "auf die automatische Erkennung."))
        SetTextColor(page.professionStatus, THEME.muted)
    else
        page.professionStatus:SetText(GC.L("Deine Fähigkeiten ließen sich nicht lesen – "
            .. "bitte oben von Hand wählen."))
        SetTextColor(page.professionStatus, THEME.warning)
    end

    -- Die drei Felder sind EIN Formular, nicht drei einzelne Felder.
    --
    -- Hier stand vorher je Feld ein "wenn es gerade keinen Fokus hat, fuell es
    -- neu". Das schuetzt aber immer nur das Feld, in dem gerade getippt wird:
    -- Wer das Von-Datum eintraegt und dann ins Bis-Feld klickt, verliert beim
    -- naechsten Auffrischen das Von-Datum - es hatte ja keinen Fokus mehr und
    -- wurde mit dem noch leeren gespeicherten Stand ueberschrieben. Wie oft das
    -- passiert, haengt daran, wie viel gerade hereinkommt (Roster, Sync,
    -- Profilantworten). Deshalb sah es auf dem einen Rechner nach "geht" und
    -- auf dem anderen nach "loescht sich staendig" aus.
    --
    -- Angefasstes Formular gehoert dem Nutzer. Nachgefuellt wird erst wieder,
    -- wenn er gespeichert oder geloescht hat.
    local absence = profile.absence or {}
    if not page.absenceDirty then
        page.absenceEdits.FROM:SetText(absence.from or "")
        page.absenceEdits.TO:SetText(absence.to or "")
        page.absenceEdits.REASON:SetText(absence.reason or "")
    end
    local absenceState = GC.Profile:GetAbsenceState(profile)
    if absenceState == "ACTIVE" then
        page.absenceStatus:SetText("Aktiv bis " .. absence.to .. ".")
        SetTextColor(page.absenceStatus, THEME.success)
        page.clearAbsence:Enable()
    elseif absenceState == "UPCOMING" then
        page.absenceStatus:SetText("Geplant ab " .. absence.from .. ".")
        SetTextColor(page.absenceStatus, THEME.warning)
        page.clearAbsence:Enable()
    elseif absenceState == "EXPIRED" then
        page.absenceStatus:SetText(GC.L("Abmeldung abgelaufen – neu eintragen oder löschen."))
        SetTextColor(page.absenceStatus, THEME.muted)
        page.clearAbsence:Enable()
    else
        page.absenceStatus:SetText(GC.L("Keine Abmeldung eingetragen."))
        SetTextColor(page.absenceStatus, THEME.muted)
        page.clearAbsence:Disable()
    end
    page.profileScroll:UpdateModernThumb()
end

local function MissingGuildProfileFields()
    local profile = GC.DB:GetGuild().profile
    local missing = {}
    local fields = {
        { key = "description", label = "Kurzbeschreibung" },
        { key = "raidTimes", label = "Raidzeiten" },
        { key = "lootSystem", label = "Lootsystem" },
        { key = "discord", label = "Discord" },
    }
    for _, field in ipairs(fields) do
        if GC.DB:IsGuildProfileFieldEnabled(field.key) and GC.Util.Trim(profile[field.key]) == "" then
            missing[#missing + 1] = field.label
        end
    end
    return missing
end

function GC.UI:BuildSuggestionsPage()
    local page = self.pages.SUGGESTIONS
    CreatePageTitle(page, "Copilot-Vorschläge",
        "Gildenroster, bestätigte Profile und importierte Logs ergeben einen Vorschlag für die Rekrutierung.")

    page.metricCards = {}
    local metrics = {
        { key = "PROFILE", label = "GILDENPROFIL" },
        { key = "COVERAGE", label = "BEKANNTE SPECS" },
        { key = "IMPORTS", label = "LOG-PROFILE" },
    }
    for index, metric in ipairs(metrics) do
        local card = CreateCard(page)
        card:SetSize(247, 76)
        card:SetPoint("TOPLEFT", page, "TOPLEFT", (index - 1) * 260, -66)
        card.value = CreateLabel(card, "0", { title = true })
        card.value:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -13)
        card.caption = CreateLabel(card, metric.label, { muted = true })
        card.caption:SetPoint("TOPLEFT", card.value, "BOTTOMLEFT", 0, -5)
        page.metricCards[metric.key] = card
    end

    local card = CreateCard(page, "Empfohlener Rekrutierungsbedarf")
    card:SetSize(776, 408)
    card:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -158)
    page.rosterRefresh = CreateButton(card, "Roster aktualisieren", 170, 28, function()
        page.rosterRefreshStatus:SetText(GC.L("Roster wird neu abgefragt …"))
        SetTextColor(page.rosterRefreshStatus, THEME.accent)
        GC.Roster:Refresh()
    end)
    page.rosterRefresh:SetPoint("TOPRIGHT", card, "TOPRIGHT", -18, -12)
    page.rosterRefreshStatus = CreateLabel(card, "", {
        muted = true,
        align = "RIGHT",
        width = 210,
        font = "GameFontNormalSmall",
    })
    page.rosterRefreshStatus:SetPoint("TOPRIGHT", card, "TOPRIGHT", -18, -47)
    page.suggestionRows = {}
    for index = 1, 7 do
        local row = CreatePanel(card, index % 2 == 0 and THEME.input or THEME.card)
        row:SetSize(740, 33)
        row:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -72 - ((index - 1) * 37))
        row.priority = CreateLabel(row, "", { width = 64, height = 33, font = "GameFontNormalSmall" })
        row.priority:SetPoint("LEFT", row, "LEFT", 9, 0)
        row.name = CreateLabel(row, "", { width = 190, height = 33 })
        row.name:SetPoint("LEFT", row, "LEFT", 78, 0)
        row.reason = CreateLabel(row, "", { muted = true, width = 450, height = 33 })
        row.reason:SetPoint("LEFT", row, "LEFT", 276, 0)
        page.suggestionRows[index] = row
    end

    page.suggestionNotice = CreateLabel(card, "", { muted = true, width = 740, height = 20, vertical = "TOP" })
    page.suggestionNotice:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -331)
    local profileButton = CreateButton(card, "Gildenprofil prüfen", 180, 36, function()
        GC.UI:ShowPage("GUILD")
    end)
    profileButton:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 18, 16)
    page.applySuggestions = CreateButton(card, "Vorschläge übernehmen", 220, 36, function()
        local suggestions = GC.Recruitment:GetSuggestions()
        for _, suggestion in ipairs(suggestions) do
            GC.Recruitment:SetSpec(suggestion.specKey, true)
        end
        GC.UI:ShowPage("RECRUITMENT")
    end, "PRIMARY")
    page.applySuggestions:SetPoint("LEFT", profileButton, "RIGHT", 8, 0)
    local manualButton = CreateButton(card, "Manuell auswählen", 170, 36, function()
        GC.UI:ShowPage("RECRUITMENT")
    end)
    manualButton:SetPoint("LEFT", page.applySuggestions, "RIGHT", 8, 0)
end

function GC.UI:RefreshSuggestions()
    local page = self.pages.SUGGESTIONS
    if not page then
        return
    end
    -- GetSuggestions liefert die Zusammenfassung mit, aus der es seine
    -- Vorschlaege zieht. Sie hier erneut anzufordern liesse den kompletten
    -- Roster ein zweites Mal durchlaufen, fuer exakt dieselben Zahlen.
    local suggestions, summary = GC.Recruitment:GetSuggestions()
    local missing = MissingGuildProfileFields()
    if GC.Roster.lastUpdate and GC.Roster.lastUpdate > 0 and date then
        page.rosterRefreshStatus:SetText("Stand: " .. date("%H:%M", GC.Roster.lastUpdate))
    elseif GC.Roster.lastUpdate and GC.Roster.lastUpdate > 0 then
        page.rosterRefreshStatus:SetText(GC.L("Roster aktuell"))
    else
        page.rosterRefreshStatus:SetText(GC.L("Noch nicht abgefragt"))
    end
    page.metricCards.PROFILE.value:SetText(GC.DB:GetGuild().profile.enabled == false and GC.L("DEAKTIVIERT")
        or (#missing == 0 and "BEREIT" or (#missing .. " OFFEN")))
    page.metricCards.COVERAGE.value:SetText(summary.knownProfiles .. "/" .. summary.total)
    page.metricCards.IMPORTS.value:SetText(summary.importedProfiles)

    for index, row in ipairs(page.suggestionRows) do
        local suggestion = suggestions[index]
        row:SetShown(suggestion ~= nil)
        if suggestion then
            local spec = GC.SpecByKey[suggestion.specKey]
            row.priority:SetText(suggestion.priority)
            SetTextColor(row.priority, suggestion.priority == "HOCH" and THEME.warning or THEME.accent)
            row.name:SetText(spec and spec.recruitLabel or suggestion.specKey)
            row.reason:SetText(suggestion.reason)
        end
    end

    if #suggestions == 0 then
        page.suggestionNotice:SetText(GC.L("|cff59e695Keine automatische Lücke erkannt.|r Du kannst trotzdem Klassen und Specs manuell wählen."))
        page.applySuggestions:Disable()
    else
        page.applySuggestions:Enable()
        if #missing > 0 then
            page.suggestionNotice:SetText("|cffffb84dVor dem Posten ergänzen:|r " .. table.concat(missing, ", ") .. ".")
        elseif summary.knownProfiles < math.max(1, math.floor(summary.total * 0.5)) then
            page.suggestionNotice:SetText(GC.L("|cffffb84dDatenlage noch dünn:|r Mehr Mitglieder sollten ihr Profil bestätigen oder Logs importiert werden."))
        else
            page.suggestionNotice:SetText(GC.L("|cff59e695Workflow bereit:|r Vorschläge übernehmen, Auswahl prüfen und anschließend den Werbetext bestätigen."))
        end
    end
end

function GC.UI:BuildMemberCarePage()
    local page = self.pages.MEMBERCARE
    CreatePageTitle(page, "Mitgliederpflege",
        "Abmeldungen berücksichtigen und lange Inaktivität nachvollziehbar prüfen – niemals automatisch entfernen.")

    local scroll = CreateModernScrollFrame(page)
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -58)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -4, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(752)
    content:SetHeight(1100)
    scroll:SetScrollChild(content)
    page.memberCareScroll = scroll
    -- RefreshMemberCare setzt Kartenhoehe und Inhaltshoehe neu, sobald die Zahl
    -- der Vorschlaege feststeht; dafuer braucht es den Inhaltsrahmen.
    page.memberCareContent = content

    local rulesCard = CreateCard(content, "Prüfregeln")
    rulesCard:SetSize(752, 230)
    rulesCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    local rulesHelp = CreateLabel(rulesCard,
        "Nur berechtigte Einstellungs-Ränge ändern diese gildenweiten Regeln. Geschützte Ränge erscheinen nie als Vorschlag.",
        { muted = true, width = 716, height = 30, vertical = "TOP" })
    rulesHelp:SetPoint("TOPLEFT", rulesCard, "TOPLEFT", 18, -46)

    local thresholdLabel = CreateLabel(rulesCard, "Vorschlag ab", { muted = true, width = 100 })
    thresholdLabel:SetPoint("TOPLEFT", rulesCard, "TOPLEFT", 18, -88)
    local thresholdOptions = { "30 Tage", "45 Tage", "60 Tage", "90 Tage", "120 Tage", "180 Tage" }
    page.memberCareThreshold = CreateChoiceDropdown(rulesCard, 150, thresholdOptions, function(value)
        local days = tonumber(tostring(value):match("(%d+)"))
        if not GC.Roster:SetMemberCareInactivityDays(days) then
            page.memberCareRulesStatus:SetText(GC.L("Dein Gildenrang darf die Prüfregeln nicht ändern."))
            SetTextColor(page.memberCareRulesStatus, THEME.danger)
            GC.UI:RefreshMemberCare()
        end
    end, true)
    page.memberCareThreshold:SetPoint("TOPLEFT", rulesCard, "TOPLEFT", 120, -82)
    page.memberCareRulesStatus = CreateLabel(rulesCard, "", { muted = true, width = 442 })
    page.memberCareRulesStatus:SetPoint("LEFT", page.memberCareThreshold, "RIGHT", 12, 0)

    local protectedLabel = CreateLabel(rulesCard, "Geschützte Ränge", { muted = true, width = 200 })
    protectedLabel:SetPoint("TOPLEFT", rulesCard, "TOPLEFT", 18, -128)
    page.memberCareRankToggles = {}
    for index = 1, 10 do
        local toggle
        toggle = CreateToggle(rulesCard, "", function(checked)
            if toggle.rankIndex ~= nil and not GC.Roster:SetMemberCareRankProtected(toggle.rankIndex, checked) then
                page.memberCareRulesStatus:SetText(GC.L("Dein Gildenrang darf den Rangschutz nicht ändern."))
                SetTextColor(page.memberCareRulesStatus, THEME.danger)
                GC.UI:RefreshMemberCare()
            end
        end)
        local column = (index - 1) % 5
        local row = math.floor((index - 1) / 5)
        toggle:SetPoint("TOPLEFT", rulesCard, "TOPLEFT", 18 + (column * 145), -153 - (row * 31))
        toggle.text:SetWidth(112)
        toggle.text:SetJustifyH("LEFT")
        page.memberCareRankToggles[index] = toggle
    end

    local absencesCard = CreateCard(content, "Aktuelle Abmeldungen")
    absencesCard:SetSize(752, 210)
    -- Startposition; RefreshMemberCare haengt die Karte unter die
    -- Entscheidungskarte, sobald deren Position feststeht. Ohne diese
    -- Nachfuehrung blieb sie fest bei -880 stehen, waehrend die Karten darueber
    -- mit der Zahl der Vorschlaege wuchsen - ab rund acht Vorschlaegen schob
    -- sich die Entscheidungskarte darueber.
    absencesCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -880)
    page.memberCareAbsencesCard = absencesCard
    page.memberCareAbsencesHeight = 210
    page.guildAbsencesTitle = absencesCard.title
    page.guildAbsenceRows = {}
    for index = 1, 5 do
        local row = CreatePanel(absencesCard, index % 2 == 0 and THEME.input or THEME.cardHover)
        row:SetSize(716, 26)
        row:SetPoint("TOPLEFT", absencesCard, "TOPLEFT", 18, -48 - ((index - 1) * 29))
        row.name = CreateLabel(row, "", { width = 140, height = 26 })
        row.name:SetPoint("LEFT", row, "LEFT", 9, 0)
        row.range = CreateLabel(row, "", { muted = true, width = 190, height = 26 })
        row.range:SetPoint("LEFT", row, "LEFT", 154, 0)
        row.reason = CreateLabel(row, "", { muted = true, width = 284, height = 26 })
        row.reason:SetPoint("LEFT", row, "LEFT", 350, 0)
        row.state = CreateLabel(row, "", { align = "RIGHT", width = 70, height = 26 })
        row.state:SetPoint("RIGHT", row, "RIGHT", -9, 0)
        page.guildAbsenceRows[index] = row
    end
    page.guildAbsenceNotice = CreateLabel(absencesCard, "", { muted = true, width = 716 })
    page.guildAbsenceNotice:SetPoint("BOTTOMLEFT", absencesCard, "BOTTOMLEFT", 18, 10)

    local suggestionsCard = CreateCard(content, "Pflegevorschläge")
    suggestionsCard:SetSize(752, 368)
    suggestionsCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -242)
    -- Der Abstand vom Seitenanfang. Er bleibt fest, waehrend die Karte selbst
    -- mit der Zahl der Vorschlaege waechst - RefreshMemberCare rechnet daraus
    -- die Position der naechsten Karte aus.
    page.memberCareSuggestionTopOffset = 242
    page.memberCareSuggestionsTitle = suggestionsCard.title
    -- Der letzte Satz ist die wichtigste Auskunft dieser Karte: Die Liste
    -- schlaegt vor, sie handelt nicht. WoW laesst einem Addon den
    -- Gildenausschluss nicht zu (GuildUninvite ist geschuetzt), also steht
    -- hier auch kein Knopf dafuer - wer das nicht weiss, sucht ihn.
    -- Zwei Zeilen, nicht vier: Ein laengerer Text lief ueber die Hoehe hinaus
    -- und endete im Spiel als "nicht bestätigt....".
    local suggestionHelp = CreateLabel(suggestionsCard,
        "Twinks, aktiv Abgemeldete und geschützte Ränge werden ausgeblendet. „Ausnahme“ nimmt jemanden dauerhaft aus der Liste. "
        .. "Entfernt wird in WoW selbst – das lässt WoW aus einem Addon heraus nicht zu.",
        { muted = true, width = 716, height = 32, vertical = "TOP" })
    suggestionHelp:SetPoint("TOPLEFT", suggestionsCard, "TOPLEFT", 18, -46)
    -- === Spaltenkoepfe ====================================================
    --
    -- Die Zeilen trugen ihre Bedeutung bisher nur aus sich selbst; welche
    -- Spalte was ist, musste man raten. Dieselben Koepfe wie in der
    -- Gildenuebersicht, an denselben x-Positionen wie die Zellen darunter.
    local suggestionHeaders = {
        { text = "SPIELER", x = 27, width = 104 },
        { text = "RANG", x = 135, width = 84 },
        { text = "STATUS", x = 223, width = 68 },
        { text = "GRUND", x = 295, width = 340 },
    }
    for _, header in ipairs(suggestionHeaders) do
        local headerLabel = CreateLabel(suggestionsCard, header.text, {
            muted = true,
            font = "GameFontNormalSmall",
            width = header.width,
        })
        headerLabel:SetPoint("TOPLEFT", suggestionsCard, "TOPLEFT", header.x, -84)
    end

    -- === Zeilenvorrat, so gross wie noetig ================================
    --
    -- Frueher standen hier neun feste Zeilen und darunter der Satz "Weitere 5
    -- Vorschlaege sind vorhanden." - eine Liste, die ihren eigenen Inhalt
    -- verschweigt. Aus dem Spiel: "ich will auch in der Liste scrollen koennen
    -- und alle Vorschlaege sehen koennen".
    --
    -- Gescrollt wird ueber die Seite selbst, die ohnehin schon in einem
    -- Scrollrahmen liegt: Die Karte waechst mit der Zahl der Vorschlaege, die
    -- Karten darunter ruecken nach. Ein zweiter Scrollrahmen INNERHALB des
    -- ersten waere die schlechtere Loesung - das Mausrad gehoerte dann zwei
    -- Listen gleichzeitig, und der Nutzer trifft die falsche.
    local SUGGESTION_ROW_STEP = 29
    local SUGGESTION_FIRST_ROW = 105
    page.memberCareSuggestionRows = {}
    page.memberCareSuggestionCard = suggestionsCard
    page.memberCareSuggestionStep = SUGGESTION_ROW_STEP
    page.memberCareSuggestionTop = SUGGESTION_FIRST_ROW

    function page:EnsureMemberCareRow(index)
        if self.memberCareSuggestionRows[index] then
            return self.memberCareSuggestionRows[index]
        end
        local row = CreatePanel(suggestionsCard, index % 2 == 0 and THEME.input or THEME.cardHover)
        row:SetSize(716, 27)
        row:SetPoint("TOPLEFT", suggestionsCard, "TOPLEFT", 18,
            -SUGGESTION_FIRST_ROW - ((index - 1) * SUGGESTION_ROW_STEP))
        row.name = CreateLabel(row, "", { width = 104, height = 27 })
        row.name:SetPoint("LEFT", row, "LEFT", 9, 0)
        -- Der Gildenrang entscheidet ueber die halbe Karte: Geschuetzte
        -- Raenge erscheinen nie als Vorschlag.
        row.rank = CreateLabel(row, "", { width = 84, height = 27 })
        row.rank:SetPoint("LEFT", row, "LEFT", 117, 0)
        row.status = CreateLabel(row, "", { width = 68, height = 27 })
        row.status:SetPoint("LEFT", row, "LEFT", 205, 0)
        -- Einzeilig: Eine umbrechende Zelle waechst ueber die 27 Pixel
        -- Zeilenhoehe hinaus und schiebt sich in die Nachbarzeilen.
        -- Vollstaendig steht der Grund im Tooltip.
        row.reason = CreateLabel(row, "", { muted = true, width = 340, height = 27 })
        row.reason:SetPoint("LEFT", row, "LEFT", 277, 0)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not GameTooltip or not self.tooltipText or self.tooltipText == "" then
                return
            end
            AnchorRowTooltip(self)
            GameTooltip:SetText(self.tooltipName or "")
            GameTooltip:AddLine(self.tooltipText, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)

        -- Genau ein Knopf. Von den vier frueheren konnte der Ausschluss nie
        -- funktionieren (GuildUninvite ist geschuetzt), und "Später" wie
        -- "Erledigt" waren Zwischenzustaende fuer genau diesen Ausschluss.
        -- "Ausnahme" nimmt jemanden dauerhaft aus der Liste und wird
        -- gildenweit geteilt.
        row.ignoreButton = CreateButton(row, "Ausnahme", 80, 21, function()
            if not row.playerName then
                return
            end
            local ok, message = GC.Roster:SetMemberCareDecision(row.playerName, "IGNORED")
            page:SetMemberCareStatus(message, ok)
            GC.UI:RefreshMemberCare()
        end)
        row.ignoreButton:SetPoint("LEFT", row, "LEFT", 627, 0)
        self.memberCareSuggestionRows[index] = row
        return row
    end
    page.memberCareSuggestionNotice = CreateLabel(suggestionsCard, "", { muted = true, width = 716 })
    page.memberCareSuggestionNotice:SetPoint("BOTTOMLEFT", suggestionsCard, "BOTTOMLEFT", 18, 10)

    local decisionsCard = CreateCard(content, "Ausnahmen und Entscheidungen")
    decisionsCard:SetSize(752, 246)
    decisionsCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -622)
    -- Diese Karte wandert: Sie haengt unter einer Vorschlagskarte, deren Hoehe
    -- von der Zahl der Vorschlaege abhaengt.
    page.memberCareDecisionsCard = decisionsCard
    page.memberCareDecisionsHeight = 246
    page.memberCareDecisionsTitle = decisionsCard.title
    local decisionsHelp = CreateLabel(decisionsCard,
        "Diese Einträge werden gildenweit synchronisiert, damit nicht zwei Offiziere denselben Fall bearbeiten.",
        { muted = true, width = 716, height = 18, vertical = "TOP" })
    decisionsHelp:SetPoint("TOPLEFT", decisionsCard, "TOPLEFT", 18, -46)

    page.memberCareStatus = CreateLabel(decisionsCard, "", { width = 716, height = 18, vertical = "TOP" })
    page.memberCareStatus:SetPoint("TOPLEFT", decisionsCard, "TOPLEFT", 18, -66)

    function page:SetMemberCareStatus(message, ok)
        message = GC.Util.Trim(message)
        self.memberCareStatus:SetText(message)
        SetTextColor(self.memberCareStatus, ok == false and THEME.danger or THEME.success)
        if message ~= "" then
            GC:Print(message)
        end
    end

    page.memberCareDecisionRows = {}
    for index = 1, 5 do
        local row = CreatePanel(decisionsCard, index % 2 == 0 and THEME.input or THEME.cardHover)
        row:SetSize(716, 26)
        row:SetPoint("TOPLEFT", decisionsCard, "TOPLEFT", 18, -90 - ((index - 1) * 29))
        row.name = CreateLabel(row, "", { width = 150, height = 26 })
        row.name:SetPoint("LEFT", row, "LEFT", 9, 0)
        row.status = CreateLabel(row, "", { width = 130, height = 26 })
        row.status:SetPoint("LEFT", row, "LEFT", 165, 0)
        row.detail = CreateLabel(row, "", { muted = true, width = 300, height = 26 })
        row.detail:SetPoint("LEFT", row, "LEFT", 301, 0)
        row.restoreButton = CreateButton(row, "Zurückholen", 96, 21, function()
            if row.playerName then
                local ok, message = GC.Roster:ClearMemberCareDecision(row.playerName)
                page:SetMemberCareStatus(message, ok)
                GC.UI:RefreshMemberCare()
            end
        end)
        row.restoreButton:SetPoint("RIGHT", row, "RIGHT", -9, 0)
        page.memberCareDecisionRows[index] = row
    end
    page.memberCareDecisionNotice = CreateLabel(decisionsCard, "", { muted = true, width = 716 })
    page.memberCareDecisionNotice:SetPoint("BOTTOMLEFT", decisionsCard, "BOTTOMLEFT", 18, 10)
end

function GC.UI:RefreshMemberCare()
    local page = self.pages.MEMBERCARE
    if not page then
        return
    end

    local careSettings = GC.DB:GetGuild().memberCare
    page.memberCareThreshold:SetValue((careSettings.inactivityDays or 60) .. " Tage")
    local canEdit = GC.Roster:CanEditGuildProfile()
    if canEdit then
        page.memberCareThreshold:Enable()
        page.memberCareRulesStatus:SetText(GC.L("Regeln werden gildenweit synchronisiert."))
        SetTextColor(page.memberCareRulesStatus, THEME.muted)
    else
        page.memberCareThreshold:Disable()
        page.memberCareRulesStatus:SetText(GC.L("Prüfregeln sind für deinen Rang schreibgeschützt."))
        SetTextColor(page.memberCareRulesStatus, THEME.warning)
    end

    local ranks = GC.Roster:GetRankDefinitions()
    for index = 1, 10 do
        local rank = ranks[index]
        local toggle = page.memberCareRankToggles[index]
        toggle:SetShown(rank ~= nil)
        if rank then
            toggle.rankIndex = rank.index
            toggle.text:SetText(rank.name)
            SetToggle(toggle, GC.Roster:IsMemberCareRankProtected(rank.index))
            if canEdit then
                toggle:Enable()
            else
                toggle:Disable()
            end
        else
            toggle.rankIndex = nil
        end
    end

    local guildAbsences = GC.Roster:GetGuildAbsences()
    page.guildAbsencesTitle:SetText("Aktuelle Abmeldungen  •  " .. #guildAbsences)
    for index, row in ipairs(page.guildAbsenceRows) do
        local entry = guildAbsences[index]
        row:SetShown(entry ~= nil)
        if entry then
            row.name:SetText(GC.Util.PlayerIdentityName(entry.member.name))
            row.name:SetTextColor(ClassColor(entry.member.classFile))
            row.range:SetText(entry.absence.from .. " – " .. entry.absence.to)
            row.reason:SetText(entry.absence.reason ~= "" and entry.absence.reason or "Kein Grund angegeben")
            row.state:SetText(entry.state == "ACTIVE" and "AKTIV" or "GEPLANT")
            SetTextColor(row.state, entry.state == "ACTIVE" and THEME.success or THEME.warning)
        end
    end
    if #guildAbsences == 0 then
        page.guildAbsenceNotice:SetText(GC.L("Keine aktiven oder geplanten Abmeldungen bekannt."))
    elseif #guildAbsences > #page.guildAbsenceRows then
        page.guildAbsenceNotice:SetText(GC.LFormat("Weitere {n} Abmeldungen sind gespeichert.",
            { n = #guildAbsences - #page.guildAbsenceRows }))
    else
        page.guildAbsenceNotice:SetText(GC.L(""))
    end

    local candidates = GC.Roster:GetMemberCareCandidates()
    page.memberCareSuggestionsTitle:SetText(
        "Pflegevorschläge  •  ab " .. (careSettings.inactivityDays or 60) .. " Tagen  •  " .. #candidates)
    -- Jeder Vorschlag bekommt eine Zeile. Der Vorrat waechst mit; ueberzaehlige
    -- Zeilen aus einem frueheren, laengeren Stand werden versteckt statt
    -- geloescht - Rahmen lassen sich in WoW ohnehin nicht freigeben.
    for index = 1, #candidates do
        page:EnsureMemberCareRow(index)
    end
    for index, row in ipairs(page.memberCareSuggestionRows) do
        local candidate = candidates[index]
        row:SetShown(candidate ~= nil)
        if candidate then
            row.playerName = candidate.member.name
            row.name:SetText(GC.Util.PlayerIdentityName(candidate.member.name))
            row.name:SetTextColor(ClassColor(candidate.member.classFile))
            row.rank:SetText(candidate.member.rank or "–")
            SetTextColor(row.rank, candidate.member.rank and THEME.text or THEME.muted)
            row.status:SetText(candidate.status)
            SetTextColor(row.status, candidate.status == "VORSCHLAG" and THEME.danger or THEME.warning)
            row.reason:SetText(candidate.reason)
            row.tooltipName = GC.Util.PlayerIdentityName(candidate.member.name)
            -- In der Zeile einzeilig, im Tooltip vollstaendig.
            row.tooltipText = candidate.reason
            SetButtonEnabled(row.ignoreButton, GC.Roster:CanAccessMemberCare())
        else
            row.playerName = nil
        end
    end

    -- === Die Karte waechst, der Rest rueckt nach ==========================
    --
    -- Ohne diesen Block stuenden die Zeilen ueber den Kartenrand hinaus und
    -- unter der naechsten Karte. Gerechnet wird aus derselben Schrittweite,
    -- mit der die Zeilen gesetzt werden - eine zweite, fest eingetippte Zahl
    -- waere die naechste Unstimmigkeit.
    do
        local step = page.memberCareSuggestionStep
        local top = page.memberCareSuggestionTop
        local visible = math.max(1, #candidates)
        -- Oben die Ueberschrift und die Koepfe, unten Platz fuer die
        -- Hinweiszeile am Kartenfuss.
        local cardHeight = top + (visible * step) + 34
        page.memberCareSuggestionCard:SetSize(752, cardHeight)

        local nextTop = page.memberCareSuggestionTopOffset + cardHeight + 24
        page.memberCareDecisionsCard:SetPoint("TOPLEFT", page.memberCareContent,
            "TOPLEFT", 0, -nextTop)
        -- Die Abmeldungskarte haengt unter der Entscheidungskarte und wandert
        -- mit ihr. Vorher stand sie fest bei -880 und wurde ueberlappt, sobald
        -- die Karten darueber ueber diese Marke hinauswuchsen.
        local absencesTop = nextTop + page.memberCareDecisionsHeight + 24
        page.memberCareAbsencesCard:SetPoint("TOPLEFT", page.memberCareContent,
            "TOPLEFT", 0, -absencesTop)
        page.memberCareContent:SetHeight(absencesTop + page.memberCareAbsencesHeight + 40)
    end

    local decisions = GC.Roster:GetMemberCareDecisions()
    page.memberCareDecisionsTitle:SetText("Ausnahmen und Entscheidungen  •  " .. #decisions)
    for index, row in ipairs(page.memberCareDecisionRows) do
        local decision = decisions[index]
        row:SetShown(decision ~= nil)
        if decision then
            row.playerName = decision.name
            local definition = GC.MemberCareDecisions[decision.status]
            row.name:SetText(decision.name)
            row.status:SetText(definition and definition.label or decision.status)
            SetTextColor(row.status, decision.status == "IGNORED" and THEME.warning or THEME.muted)
            local detail = definition and definition.help or ""
            if decision.status == "POSTPONED" and decision.until_ ~= "" then
                detail = "Wieder ab " .. decision.until_ .. "."
            end
            if decision.by and decision.by ~= "" then
                detail = detail .. "  •  " .. decision.by
            end
            row.detail:SetText(detail)
            SetButtonEnabled(row.restoreButton, GC.Roster:CanAccessMemberCare())
        else
            row.playerName = nil
        end
    end
    page.memberCareDecisionNotice:SetText(#decisions == 0
        and "Keine Ausnahmen hinterlegt. Vorschläge lassen sich als Ausnahme, später oder erledigt ablegen."
        or "")
    SetTextColor(page.memberCareSuggestionNotice, THEME.muted)
    -- "Weitere {n} Vorschläge sind vorhanden." ist ersatzlos entfallen: Die
    -- Liste zeigt jetzt alle, es gibt keine weiteren mehr zu verschweigen.
    if #candidates == 0 then
        page.memberCareSuggestionNotice:SetText(GC.L("Keine Mitglieder erfüllen die aktuellen Prüfregeln."))
    else
        page.memberCareSuggestionNotice:SetText(GC.L("Nur Vorschläge – keine automatische Entfernung."))
    end
end

function GC.UI:BuildWorkshopPage()
    local page = self.pages.WORKSHOP
    local _, workshopHelp = CreatePageTitle(page, "Gildenwerkstatt",
        "Rezepte werden automatisch erfasst, sobald ein Spieler sein WoW-Berufsfenster öffnet.")
    -- Die Unterreiter-Knöpfe stehen oben rechts auf Höhe des Hilfetexts.
    -- Mit voller Breite liefe der Text hinter die Knöpfe; schmaler bricht er
    -- vor ihnen um.
    workshopHelp:SetWidth(460)

    -- Zwei Unterreiter: der Katalog und das Auftragsboard
    -- (docs/KONZEPT-werkstatt-gildenauftraege.md). Beide teilen sich die
    -- Seite; gewechselt wird über die Knöpfe oben rechts.
    page.workshopView = "CATALOG"
    page.workshopTabCatalog = CreateButton(page, "Katalog", 100, 30, function()
        GC.UI:SetWorkshopView("CATALOG")
    end)
    page.workshopTabCatalog:SetPoint("TOPRIGHT", page, "TOPRIGHT", -196, 0)
    page.workshopTabOrders = CreateButton(page, "Gildenaufträge", 188, 30, function()
        GC.UI:SetWorkshopView("ORDERS")
    end)
    page.workshopTabOrders:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)

    page.metricCards = {}
    local metrics = {
        { key = "RECIPES", label = "REZEPTE" },
        { key = "CRAFTERS", label = "HERSTELLER" },
        { key = "PROFESSIONS", label = "BERUFE" },
    }
    for index, metric in ipairs(metrics) do
        local card = CreateCard(page)
        card:SetSize(247, 72)
        card:SetPoint("TOPLEFT", page, "TOPLEFT", (index - 1) * 260, -66)
        card.value = CreateLabel(card, "0", { title = true })
        card.value:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -11)
        card.caption = CreateLabel(card, metric.label, { muted = true })
        card.caption:SetPoint("TOPLEFT", card.value, "BOTTOMLEFT", 0, -4)
        page.metricCards[metric.key] = card
    end

    local searchCard = CreateCard(page)
    searchCard:SetSize(776, 62)
    searchCard:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -150)
    local professionFilters = {}
    for _, professionName in ipairs(GC.ProfessionOptions) do
        professionFilters[#professionFilters + 1] = professionName
    end
    professionFilters[#professionFilters + 1] = "Kochkunst"
    professionFilters[#professionFilters + 1] = "Erste Hilfe"
    page.workshopProfession = CreateChoiceDropdown(searchCard, 176, professionFilters, function()
        page.workshopPage = 1
        page.selectedWorkshopRecipe = nil
        GC.UI:RefreshWorkshop()
    end, true, "Alle Berufe", function(professionName)
        return GC.ProfessionIcons[professionName or ""] or GC.ProfessionIcons[""]
    end)
    page.workshopProfession:SetPoint("TOPLEFT", searchCard, "TOPLEFT", 14, -14)
    page.workshopProfession:SetValue("")

    page.workshopSearch = CreateEdit(searchCard, 238, 34)
    page.workshopSearch.container:SetPoint("LEFT", page.workshopProfession, "RIGHT", 8, 0)
    -- Das × leert die Suche mit einem Klick; es erscheint nur, wenn etwas
    -- drinsteht (Owner-Wunsch).
    page.workshopSearchClear = CreateButton(page.workshopSearch.container, "×", 20, 20, function()
        page.workshopSearch:SetText(GC.L(""))
        page.workshopSearch:ClearFocus()
        GC.UI:RefreshWorkshop()
    end)
    -- Dasselbe Problem wie beim Kalendersymbol: Ohne eigene Rahmenebene fing
    -- die EditBox den Klick ab, und anklickbar blieb nur ihr Innenabstand.
    AttachEditButton(page.workshopSearch, page.workshopSearchClear, 20, 5)
    page.workshopSearchClear:Hide()
    -- Wer "Verzauberung" tippt, loest zwoelf Suchlaeufe aus, von denen elf
    -- niemand sieht. Gezeichnet wird deshalb erst, wenn die Eingabe kurz steht.
    -- Das × reagiert weiter sofort, das ist ein Klick und kein Tippen.
    page.workshopSearch:SetScript("OnTextChanged", function(edit)
        page.workshopPage = 1
        page.workshopSearchClear:SetShown(GC.Util.Trim(edit:GetText()) ~= "")
        GC.UI:QueueWorkshopSearch()
    end)
    local searchHint = CreateLabel(page.workshopSearch.container, "Rezept oder Spieler suchen", {
        muted = true,
        width = 205,
    })
    searchHint:SetPoint("LEFT", page.workshopSearch.container, "LEFT", 10, 0)
    page.workshopSearch:SetScript("OnEditFocusGained", function()
        searchHint:Hide()
    end)
    page.workshopSearch:SetScript("OnEditFocusLost", function(edit)
        searchHint:SetShown(edit:GetText() == "")
    end)

    page.workshopFavorites = CreateButton(searchCard, "Favoriten", 134, 34, function()
        page.workshopFavoritesOnly = not page.workshopFavoritesOnly
        page.workshopPage = 1
        page.selectedWorkshopRecipe = nil
        GC.UI:RefreshWorkshop()
    end)
    page.workshopFavorites:SetPoint("LEFT", page.workshopSearch.container, "RIGHT", 8, 0)
    page.workshopFavorites.favoriteIcon = page.workshopFavorites:CreateTexture(nil, "ARTWORK")
    page.workshopFavorites.favoriteIcon:SetSize(18, 18)
    page.workshopFavorites.favoriteIcon:SetPoint("LEFT", page.workshopFavorites, "LEFT", 9, 0)
    SetRaidMarkerIcon(page.workshopFavorites.favoriteIcon, 1)
    page.workshopFavorites.label:ClearAllPoints()
    page.workshopFavorites.label:SetPoint("LEFT", page.workshopFavorites, "LEFT", 31, 0)
    page.workshopFavorites.label:SetPoint("RIGHT", page.workshopFavorites, "RIGHT", -8, 0)
    page.workshopFavorites.label:SetJustifyH("LEFT")

    -- Der Erfolg stand ab 0.9.86 "im Balken darunter" - nur sprang der erst
    -- an, wenn die erste Antwort eintraf, und die kommt mit bis zu 31 s
    -- Streuung. Eine halbe Minute lang passierte sichtbar NICHTS, und genau
    -- das wurde als "der Knopf tut nichts" gemeldet. Die Quittung lebt jetzt
    -- im Balken selbst (RefreshSyncBar zeigt sie, bis echte Antworten oder
    -- die Zeit sie abloesen), und der Knopf zaehlt sie herunter.
    page.workshopRequest = CreateButton(searchCard, "Daten anfragen", 176, 34, function()
        local success, message = GC.Workshop:RequestGuildData()
        if success then
            GC.UI.pages.WORKSHOP.workshopRequestAckAt = GC.Util.Now()
        else
            GC:Print("|cffff5555" .. tostring(message) .. "|r")
        end
        GC.UI:RefreshSyncBar(true)
    end, "PRIMARY")
    page.workshopRequest:SetPoint("TOPRIGHT", searchCard, "TOPRIGHT", -14, -14)

    local listCard = CreateCard(page, "Gefundene Rezepte")
    -- Zwölf Pixel niedriger als bis 0.9.85: Darunter steht jetzt der
    -- Abgleichsbalken, und der braucht eine eigene Zeile statt sich in die
    -- Statuszeile zu quetschen.
    listCard:SetSize(418, 330)
    listCard:SetPoint("TOPLEFT", searchCard, "BOTTOMLEFT", 0, -12)
    page.workshopListTitle = listCard.title
    page.workshopRows = {}
    for index = 1, 7 do
        local rowIndex = index
        local row = CreateButton(listCard, "", 382, 31, function()
            local recipe = page.workshopVisibleRecipes and page.workshopVisibleRecipes[rowIndex]
            if recipe then
                page.selectedWorkshopRecipe = recipe.key
                GC.UI:RefreshWorkshop()
            end
        end)
        row:SetPoint("TOPLEFT", listCard, "TOPLEFT", 18, -48 - ((index - 1) * 34))
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", 37, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -112, 0)
        row.label:SetJustifyH("LEFT")
        row.professionIcon = row:CreateTexture(nil, "ARTWORK")
        row.professionIcon:SetSize(21, 21)
        row.professionIcon:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.meta = CreateLabel(row, "", { muted = true, align = "RIGHT", width = 78, height = 31 })
        row.meta:SetPoint("RIGHT", row, "RIGHT", -9, 0)
        row.favoriteIcon = row:CreateTexture(nil, "ARTWORK")
        row.favoriteIcon:SetSize(15, 15)
        row.favoriteIcon:SetPoint("RIGHT", row.meta, "LEFT", -6, 0)
        SetRaidMarkerIcon(row.favoriteIcon, 1)
        row.favoriteIcon:Hide()
        page.workshopRows[index] = row
    end
    page.workshopPrevious = CreateButton(listCard, "<", 38, 28, function()
        page.workshopPage = math.max(1, (page.workshopPage or 1) - 1)
        GC.UI:RefreshWorkshop()
    end)
    page.workshopPrevious:SetPoint("BOTTOMLEFT", listCard, "BOTTOMLEFT", 18, 12)
    page.workshopPageLabel = CreateLabel(listCard, "Seite 1/1", { muted = true, align = "CENTER", width = 120 })
    page.workshopPageLabel:SetPoint("LEFT", page.workshopPrevious, "RIGHT", 8, 0)
    page.workshopNext = CreateButton(listCard, ">", 38, 28, function()
        page.workshopPage = (page.workshopPage or 1) + 1
        GC.UI:RefreshWorkshop()
    end)
    page.workshopNext:SetPoint("LEFT", page.workshopPageLabel, "RIGHT", 8, 0)

    local detailCard = CreateCard(page, "Rezeptdetails")
    detailCard:SetSize(346, 330)
    detailCard:SetPoint("TOPRIGHT", searchCard, "BOTTOMRIGHT", 0, -12)
    -- Breite 170 statt 200: Rechts stehen inzwischen zwei Knöpfe übereinander
    -- ("Merken" und "In Auftrag geben", ab x 192); ein längerer Rezeptname
    -- muss vor ihnen umbrechen statt darunter zu verschwinden.
    page.workshopRecipeTitle = CreateLabel(detailCard, "Kein Rezept ausgewählt", {
        title = true,
        width = 170,
        height = 45,
        vertical = "TOP",
    })
    page.workshopRecipeTitle:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, -49)
    page.workshopFavorite = CreateButton(detailCard, "Merken", 104, 30, function()
        local recipeKey = page.selectedWorkshopRecipe
        if recipeKey then
            GC.Workshop:SetFavorite(recipeKey, not GC.Workshop:IsFavorite(recipeKey))
            GC.UI:RefreshWorkshop()
        end
    end)
    page.workshopFavorite:SetPoint("TOPRIGHT", detailCard, "TOPRIGHT", -14, -12)
    -- Der Einstieg in einen Gildenauftrag sitzt direkt an der Rezeptkarte:
    -- die bestehende Suche ist die Rezeptauswahl, es gibt keinen zweiten Weg.
    page.workshopOrderButton = CreateButton(detailCard, "In Auftrag geben", 140, 30, function()
        if page.selectedWorkshopRecipe then
            GC.UI:OpenOrderCreateDialog(page.selectedWorkshopRecipe)
        end
    end, "PRIMARY")
    page.workshopOrderButton:SetPoint("TOPRIGHT", detailCard, "TOPRIGHT", -14, -46)
    page.workshopOrderButton:Hide()

    -- Herstellen aus dem Cockpit (Nutzerrückmeldung 08/2026). Der Knopf ist
    -- ein SICHERER Knopf: Das Berufsfenster öffnet nur ein Zauber, und den
    -- lässt WoW ausschließlich bei einem echten Tastendruck zu. Er erscheint
    -- nur, wenn der gerade gespielte Charakter das Rezept kann - der Katalog
    -- kennt auch die Rezepte der Twinks, fertigen kann sie nur ihr Besitzer.
    page.workshopCraftButton = CreateButton(detailCard, "Herstellen", 140, 30, function()
        local recipeKey = page.selectedWorkshopRecipe
        if not recipeKey then
            return
        end
        local ok, message = GC.Workshop:CraftOpenRecipe(recipeKey, 1)
        page.workshopStatus:SetText(message or "")
        SetTextColor(page.workshopStatus, ok and THEME.success or THEME.danger)
    end, nil, true)
    page.workshopCraftButton:SetPoint("TOPRIGHT", detailCard, "TOPRIGHT", -14, -80)
    page.workshopCraftButton:Hide()
    page.workshopFavorite.favoriteIcon = page.workshopFavorite:CreateTexture(nil, "ARTWORK")
    page.workshopFavorite.favoriteIcon:SetSize(17, 17)
    page.workshopFavorite.favoriteIcon:SetPoint("LEFT", page.workshopFavorite, "LEFT", 8, 0)
    SetRaidMarkerIcon(page.workshopFavorite.favoriteIcon, 1)
    page.workshopFavorite.label:ClearAllPoints()
    page.workshopFavorite.label:SetPoint("LEFT", page.workshopFavorite, "LEFT", 29, 0)
    page.workshopFavorite.label:SetPoint("RIGHT", page.workshopFavorite, "RIGHT", -7, 0)
    page.workshopFavorite.label:SetJustifyH("LEFT")
    -- Achtzehn Pixel tiefer als bis 0.9.111: Darüber steht jetzt der dritte
    -- Knopf („Herstellen"), und der braucht seine eigene Zeile.
    local detailBody = CreatePanel(detailCard, THEME.input)
    detailBody:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, -116)
    detailBody:SetPoint("BOTTOMRIGHT", detailCard, "BOTTOMRIGHT", -18, 16)
    page.workshopDetailScroll = CreateModernScrollFrame(detailBody)
    page.workshopDetailScroll:SetPoint("TOPLEFT", detailBody, "TOPLEFT", 8, -8)
    page.workshopDetailScroll:SetPoint("BOTTOMRIGHT", detailBody, "BOTTOMRIGHT", -12, 8)
    page.workshopDetailContent = CreateFrame("Frame", nil, page.workshopDetailScroll)
    page.workshopDetailContent:SetWidth(292)
    page.workshopDetailContent:SetHeight(220)
    page.workshopDetailScroll:SetScrollChild(page.workshopDetailContent)
    page.workshopDetails = CreateLabel(page.workshopDetailContent, "", { width = 274, height = 220, vertical = "TOP" })
    page.workshopDetails:SetPoint("TOPLEFT", page.workshopDetailContent, "TOPLEFT", 0, 0)

    -- Materialien als echte Zeilen mit festen Spalten. Ein Textblock kann das
    -- nicht: die Spielschrift ist proportional, Leerzeichen ergeben also keine
    -- Spalte, sondern nur ausgefranste Zahlen.
    page.workshopMaterialHeader = CreateLabel(page.workshopDetailContent, "Materialien",
        { muted = true, width = 176, height = 15 })
    page.workshopMaterialOwnHeader = CreateLabel(page.workshopDetailContent, "Du",
        { muted = true, width = 42, height = 15, align = "RIGHT" })
    page.workshopMaterialBankHeader = CreateLabel(page.workshopDetailContent, "GBank",
        { muted = true, width = 48, height = 15, align = "RIGHT" })
    page.workshopMaterialRows = {}
    for index = 1, 14 do
        local row = CreateFrame("Frame", nil, page.workshopDetailContent)
        row:SetSize(274, 15)
        row.name = CreateLabel(row, "", { width = 176, height = 15 })
        row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.own = CreateLabel(row, "", { width = 42, height = 15, align = "RIGHT" })
        row.own:SetPoint("LEFT", row, "LEFT", 178, 0)
        row.bank = CreateLabel(row, "", { width = 48, height = 15, align = "RIGHT" })
        row.bank:SetPoint("LEFT", row, "LEFT", 226, 0)
        row:Hide()
        page.workshopMaterialRows[index] = row
    end
    page.workshopMaterialSummary = CreateLabel(page.workshopDetailContent, "",
        { width = 274, height = 60, vertical = "TOP" })
    page.workshopMaterialFooter = CreateLabel(page.workshopDetailContent, "",
        { muted = true, width = 274, height = 30, vertical = "TOP" })

    page.workshopStatus = CreateLabel(page,
        "Öffne deine Berufe einmal, damit Guild Copilot die bekannten Rezepte einliest.",
        { muted = true, width = 776, height = 16 })
    page.workshopStatus:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)

    -- === Abgleichsbalken ===================================================
    --
    -- Hier stand bis 0.9.86 eine Zahl empfangener Pakete. Sie beantwortete
    -- genau die Frage nicht, die man unten in der Werkstatt stellt: Bin ich
    -- vollständig? "110 Berufspakete empfangen" heißt weder ja noch nein.
    --
    -- Der Balken zählt stattdessen die offene Arbeit - ausgehende Pakete,
    -- fehlende Teile eingehender Übertragungen und Berufe, die ein fremdes
    -- Manifest gemeldet hat und die hier noch fehlen. 100 % gibt es nur, wenn
    -- davon nichts mehr übrig ist.
    page.syncBar = CreateProgressBar(page, 700, 12)
    page.syncBar:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 19)
    page.syncPercent = CreateLabel(page, "", {
        font = "GameFontNormalSmall",
        width = 68,
        height = 14,
        align = "RIGHT",
    })
    page.syncPercent:SetPoint("LEFT", page.syncBar, "RIGHT", 8, 0)

    page.syncBar:EnableMouse(true)
    page.syncBar:SetScript("OnEnter", function(bar)
        if not GameTooltip then
            return
        end
        local status = GC.Sync:GetSyncStatus()
        GameTooltip:SetOwner(bar, "ANCHOR_TOP")
        GameTooltip:SetText(GC.L("Stand des Gildenabgleichs"))
        GameTooltip:AddLine(status.outbound .. " Pakete zu senden, "
            .. status.inbound .. " Teile im Empfang, "
            .. status.missing .. " Berufe angekündigt und noch nicht da.", 1, 1, 1, true)
        GameTooltip:AddLine("Gezählt wird der ganze Abgleich, nicht nur die Werkstatt – "
            .. "davon aus der Werkstatt: " .. GC.Workshop:GetPendingPacketCount() .. ".",
            0.57, 0.64, 0.72, true)
        local waiting = GC.Workshop:GetPendingWantNames(6)
        if #waiting > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Es fehlt noch von: " .. table.concat(waiting, ", "), 1, 0.72, 0.25, true)
        end
        -- Die Bestandsluecken daneben: nichts Unterwegs-Befindliches, sondern
        -- Berufe, deren Besitzer seit dem letzten gemeinsamen Login offline sind.
        local gaps = GC.Workshop:GetCoverageGapNames(6)
        if #gaps > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Es fehlen noch: " .. table.concat(gaps, ", ")
                .. " – ein Bote liefert sie, sobald jemand online ist, der sie hat.",
                1, 0.72, 0.25, true)
        end
        if (status.lastSyncedAt or 0) > 0 and date then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Zuletzt vollständig: "
                .. date("%d.%m. %H:%M", status.lastSyncedAt), 0.57, 0.64, 0.72, true)
        end
        GameTooltip:AddLine("„Daten anfragen“ startet einen neuen Abgleich.", 0.31, 0.79, 1, true)
        GameTooltip:Show()
    end)
    page.syncBar:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    -- Der Balken lebt, solange man ihn sieht: Ein verstecktes Frame bekommt
    -- kein OnUpdate, bei geschlossener Werkstatt kostet er also nichts. Der
    -- Zyklus selbst läuft unabhängig davon in Sync.lua weiter.
    page.syncBar:SetScript("OnUpdate", function(bar, elapsed)
        bar.elapsed = (bar.elapsed or 0) + elapsed
        if bar.elapsed < 0.25 then
            return
        end
        bar.elapsed = 0
        GC.UI:RefreshSyncBar()
    end)

    -- Alles, was zum Katalog gehört, damit der Reiterwechsel es gemeinsam
    -- ein- und ausblenden kann.
    page.workshopCatalogFrames = {
        page.metricCards.RECIPES, page.metricCards.CRAFTERS, page.metricCards.PROFESSIONS,
        searchCard, listCard, detailCard, page.workshopStatus,
        page.syncBar, page.syncPercent,
    }

    self:BuildOrdersView(page)
end

-- Sammelt Tastendruecke in der Rezeptsuche. Ohne Timer laeuft der Sucher
-- synchron - dann ist auch ein gecachter Katalog noch je Zeichen ein
-- vollstaendiger Durchlauf, aber immerhin kein Neuaufbau.
local WORKSHOP_SEARCH_DELAY = 0.25

function GC.UI:QueueWorkshopSearch()
    if self.workshopSearchPending then
        return
    end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
        self:RefreshWorkshop()
        return
    end
    self.workshopSearchPending = true
    C_Timer.After(WORKSHOP_SEARCH_DELAY, function()
        GC.UI.workshopSearchPending = false
        GC.UI:RefreshWorkshop()
    end)
end

-- Der Herstellen-Knopf hat zwei Zustände, weil das Spiel zwei Schritte
-- verlangt: Ohne offenes Berufsfenster gibt es keine Rezeptliste, also öffnet
-- der erste Klick das Fenster (sicherer Zauber), der zweite fertigt.
--
-- Der Zauber hängt nur dann am Knopf, wenn das Fenster ZU ist. Läge er immer
-- an, würde der zweite Klick den gerade laufenden Herstellungszauber
-- unterbrechen - man kann nicht zwei Zauber zugleich wirken. Sichere
-- Attribute lassen sich im Kampf nicht ändern; dort bleibt der Knopf stehen,
-- wie er ist, und der Herstellbefehl lehnt ohnehin ab.
function GC.UI:RefreshCraftButton(button, recipeKey, count)
    if not button then
        return
    end
    local recipe, profession = GC.Workshop:GetOwnRecipe(recipeKey)
    if not recipe then
        button:Hide()
        return
    end
    local ready = GC.Workshop:FindOpenRecipe(recipeKey) ~= nil
    if type(InCombatLockdown) ~= "function" or not InCombatLockdown() then
        -- Ausgeschrieben statt "ready and nil or spell": Lua wertet das zu
        -- IMMER spell aus, weil nil im and-Zweig als falsch gilt.
        if ready then
            button:SetAttribute("spell", nil)
        else
            button:SetAttribute("spell", ProfessionWindowSpell(profession and profession.name or ""))
        end
    end
    count = math.max(1, math.floor(tonumber(count) or 1))
    if ready then
        button:SetText(count > 1 and GC.LFormat("{n}× herstellen", { n = count })
            or "Herstellen")
    else
        button:SetText(GC.L("Berufsfenster öffnen"))
    end
    button.craftReady = ready
    button:Show()
end

function GC.UI:RefreshWorkshop()
    local page = self.pages.WORKSHOP
    if not page then
        return
    end

    -- Reiterzustand und "du bist dran"-Zähler zuerst: beides gilt für beide
    -- Ansichten. Im Auftragsboard endet der Aufbau danach - die Katalogkarten
    -- sind dort ausgeblendet, ihre Auffrischung wäre reine Verschwendung.
    if page.workshopTabOrders then
        local actionable = GC.Orders and GC.Orders:GetActionableCount() or 0
        page.workshopTabOrders:SetText(actionable > 0
            and ("Gildenaufträge (" .. actionable .. ")")
            or "Gildenaufträge")
        page.workshopTabOrders:SetActive(page.workshopView == "ORDERS")
        page.workshopTabCatalog:SetActive(page.workshopView ~= "ORDERS")
    end
    if page.workshopView == "ORDERS" then
        self:RefreshOrdersBoard()
        return
    end

    local summary = GC.Workshop:GetSummary()
    page.metricCards.RECIPES.value:SetText(summary.recipes)
    page.metricCards.CRAFTERS.value:SetText(summary.crafters)
    page.metricCards.PROFESSIONS.value:SetText(summary.professions)

    local query = GC.Util.Trim(page.workshopSearch:GetText())
    local professionFilter = page.workshopProfession.value or ""
    local hasScope = query ~= "" or professionFilter ~= "" or page.workshopFavoritesOnly
    local entries = hasScope
        and GC.Workshop:GetCatalog(query, professionFilter, page.workshopFavoritesOnly)
        or {}
    page.workshopFavorites:SetActive(page.workshopFavoritesOnly == true)
    page.workshopFavorites:SetText(GC.L("Favoriten"))
    if page.workshopFavoritesOnly then
        page.workshopListTitle:SetText(GC.L("Favorisierte Rezepte"))
    elseif professionFilter ~= "" then
        page.workshopListTitle:SetText("Rezepte  •  " .. professionFilter)
    elseif query ~= "" then
        page.workshopListTitle:SetText(GC.L("Suchergebnisse"))
    else
        page.workshopListTitle:SetText(GC.L("Gezielte Rezeptsuche"))
    end
    local pageSize = #page.workshopRows
    local pageCount = math.max(1, math.ceil(#entries / pageSize))
    page.workshopPage = math.max(1, math.min(page.workshopPage or 1, pageCount))
    page.workshopPageLabel:SetText("Seite " .. page.workshopPage .. "/" .. pageCount)
    local showPagination = hasScope and #entries > pageSize
    page.workshopPrevious:SetShown(showPagination)
    page.workshopPageLabel:SetShown(showPagination)
    page.workshopNext:SetShown(showPagination)
    if page.workshopPage <= 1 then
        page.workshopPrevious:Disable()
    else
        page.workshopPrevious:Enable()
    end
    if page.workshopPage >= pageCount then
        page.workshopNext:Disable()
    else
        page.workshopNext:Enable()
    end

    local selected
    for _, recipe in ipairs(entries) do
        if recipe.key == page.selectedWorkshopRecipe then
            selected = recipe
            break
        end
    end
    if not selected and entries[1] then
        selected = entries[1]
        page.selectedWorkshopRecipe = selected.key
    end

    page.workshopVisibleRecipes = {}
    local startIndex = ((page.workshopPage - 1) * pageSize) + 1
    for rowIndex, row in ipairs(page.workshopRows) do
        local recipe = entries[startIndex + rowIndex - 1]
        page.workshopVisibleRecipes[rowIndex] = recipe
        row:SetShown(recipe ~= nil)
        if recipe then
            row:SetText(recipe.name)
            row.professionIcon:SetTexture(GC.ProfessionIcons[recipe.profession] or GC.ProfessionIcons[""])
            -- Bei aktivem Berufsfilter steht der Beruf schon in der
            -- Kartenueberschrift; die Wiederholung kostet nur Platz, den der
            -- Rezeptname besser braucht.
            row.meta:SetText(professionFilter ~= ""
                and tostring(#recipe.crafters)
                or (#recipe.crafters .. "  •  " .. recipe.profession))
            row.favoriteIcon:SetShown(GC.Workshop:IsFavorite(recipe.key))
            row:SetActive(page.selectedWorkshopRecipe == recipe.key)
        end
    end

    if not selected then
        page.workshopFavorite:Hide()
        page.workshopOrderButton:Hide()
        if not hasScope then
            page.workshopRecipeTitle:SetText(GC.L("Wonach suchst du?"))
            page.workshopDetails:SetText(GC.L(
                "Gib einen Rezept- oder Spielernamen ein, wähle einen Beruf oder öffne deine Favoriten.\n\n"
                .. "So bleibt die Werkstatt auch mit tausenden bekannten Rezepten übersichtlich."))
        elseif page.workshopFavoritesOnly then
            page.workshopRecipeTitle:SetText(GC.L("Keine Favoriten gefunden"))
            page.workshopDetails:SetText(GC.L(
                "Markiere häufig benötigte Rezepte mit dem Stern in den Rezeptdetails."))
        else
            page.workshopRecipeTitle:SetText(GC.L("Keine Treffer"))
            if professionFilter ~= "" then
                page.workshopDetails:SetText("Für " .. professionFilter
                    .. " wurden noch keine passenden Rezepte erfasst. Öffne das Berufsfenster oder frage Gildendaten an.")
            else
                page.workshopDetails:SetText(GC.L("Prüfe den Suchbegriff oder frage aktuelle Gildendaten an."))
            end
        end
        -- Ohne Auswahl duerfen keine Materialzeilen von vorhin stehen bleiben.
        page.workshopDetails:SetHeight(220)
        page.workshopMaterialHeader:Hide()
        page.workshopMaterialOwnHeader:Hide()
        page.workshopMaterialBankHeader:Hide()
        for _, row in ipairs(page.workshopMaterialRows) do
            row:Hide()
        end
        page.workshopMaterialSummary:SetText(GC.L(""))
        page.workshopMaterialFooter:SetText(GC.L(""))
        page.workshopScrollAnchor = nil
        page.workshopDetailContent:SetHeight(220)
        page.workshopCraftButton:Hide()
    else
        self:RefreshCraftButton(page.workshopCraftButton, selected.key, 1)
        page.workshopFavorite:Show()
        page.workshopFavorite:SetText(GC.Workshop:IsFavorite(selected.key) and "Gemerkt" or "Merken")
        page.workshopFavorite:SetActive(GC.Workshop:IsFavorite(selected.key))
        -- Ohne bekannten Hersteller gibt es nichts zu beauftragen.
        page.workshopOrderButton:SetShown(#selected.crafters > 0)
        page.workshopRecipeTitle:SetText(selected.name)
        local lines = {
            "|cff91a3b8Beruf|r  " .. selected.profession,
            "",
            "|cff91a3b8Hersteller|r",
        }
        -- Wer ein Rezept kann, kann es deshalb noch lange nicht heute:
        -- Umwandlungen, Spezialtuche und Sphaeren haben eine Wartezeit. Sie
        -- steht am Hersteller, weil genau dort die Entscheidung faellt, wen man
        -- fragt.
        local anyLocked = false
        for _, crafter in ipairs(selected.crafters) do
            local readyAt = GC.Workshop:GetRecipeCooldown(selected.key, crafter)
            if readyAt then
                anyLocked = true
                lines[#lines + 1] = "• " .. crafter
                    .. "   |cffffb840" .. FormatCooldownReady(readyAt) .. "|r"
            else
                lines[#lines + 1] = "• " .. crafter
            end
        end
        if anyLocked then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "|cff91a3b8Sperrzeiten sind Mindestangaben aus dem"
                .. " zuletzt geöffneten Berufsfenster.|r"
        end
        page.workshopDetails:SetText(table.concat(lines, "\n"))
        local infoHeight = math.max(15, WrappedTextHeight(
            page.workshopDetails, table.concat(lines, "\n"), 274)) + 6
        page.workshopDetails:SetHeight(infoHeight)

        -- Materialien stehen in echten Zeilen mit festen Spalten darunter.
        local status = #selected.reagents > 0
            and GC.Inventory:GetReagentStatus(selected.reagents)
            or nil
        local cursor = infoHeight + 8
        local headerShown = status ~= nil
        page.workshopMaterialHeader:SetShown(true)
        page.workshopMaterialHeader:ClearAllPoints()
        page.workshopMaterialHeader:SetPoint("TOPLEFT", page.workshopDetailContent, "TOPLEFT", 0, -cursor)
        page.workshopMaterialOwnHeader:SetShown(headerShown)
        page.workshopMaterialBankHeader:SetShown(headerShown)
        if headerShown then
            page.workshopMaterialOwnHeader:ClearAllPoints()
            page.workshopMaterialOwnHeader:SetPoint("TOPLEFT", page.workshopDetailContent, "TOPLEFT", 178, -cursor)
            page.workshopMaterialBankHeader:ClearAllPoints()
            page.workshopMaterialBankHeader:SetPoint("TOPLEFT", page.workshopDetailContent, "TOPLEFT", 226, -cursor)
        end
        cursor = cursor + 18

        for index, row in ipairs(page.workshopMaterialRows) do
            local entry = status and status.rows[index]
            row:SetShown(entry ~= nil)
            if entry then
                -- Nur die Zahlen tragen Farbe. Waeren auch die Namen rot,
                -- entstuende bei einem fehlenden Rezept eine Wand aus Rot, in
                -- der nichts mehr heraussticht.
                local label = entry.name or ("Item #" .. (entry.itemID or "?"))
                if #label > 28 then
                    label = label:sub(1, 27) .. "…"
                end
                row.name:SetText(entry.needed .. "× " .. label)
                SetTextColor(row.name, THEME.text)
                row.own:SetText(tostring(entry.own.total))
                SetTextColor(row.own,
                    entry.own.total >= entry.needed and THEME.success or THEME.danger)
                row.bank:SetText(entry.guildBank and tostring(entry.guildBank) or "–")
                if not entry.guildBank then
                    SetTextColor(row.bank, THEME.muted)
                elseif entry.status == "GUILD" then
                    SetTextColor(row.bank, THEME.warning)
                elseif entry.guildBank >= entry.shortfall and entry.shortfall > 0 then
                    SetTextColor(row.bank, THEME.warning)
                else
                    SetTextColor(row.bank, THEME.muted)
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", page.workshopDetailContent, "TOPLEFT", 0, -cursor)
                cursor = cursor + 15
            end
        end

        if not status then
            page.workshopMaterialSummary:SetText(GC.L("Keine Reagenzien erfasst."))
            SetTextColor(page.workshopMaterialSummary, THEME.muted)
        elseif #status.missing > 0 then
            local parts, fromBank = {}, 0
            for _, entry in ipairs(status.missing) do
                parts[#parts + 1] = entry.amount .. "× "
                    .. (entry.name or ("Item #" .. (entry.itemID or "?")))
                fromBank = fromBank + (entry.fromGuildBank or 0)
            end
            page.workshopMaterialSummary:SetText("|cffff6266Dir fehlt:|r "
                .. table.concat(parts, ", ")
                .. (fromBank > 0
                    and ("\n|cffe8b84b" .. fromBank .. " davon in der Gildenbank.|r")
                    or ""))
            SetTextColor(page.workshopMaterialSummary, THEME.text)
        else
            page.workshopMaterialSummary:SetText(GC.L("|cff59e695Alle Materialien vorhanden.|r"))
            SetTextColor(page.workshopMaterialSummary, THEME.text)
        end
        cursor = cursor + 8
        page.workshopMaterialSummary:ClearAllPoints()
        page.workshopMaterialSummary:SetPoint("TOPLEFT", page.workshopDetailContent, "TOPLEFT", 0, -cursor)
        local summaryHeight = math.max(15, WrappedTextHeight(
            page.workshopMaterialSummary,
            page.workshopMaterialSummary:GetText(), 274))
        page.workshopMaterialSummary:SetHeight(summaryHeight)
        cursor = cursor + summaryHeight + 8

        -- Herkunft und Alter der Bestaende, bewusst gedaempft: es ist Beiwerk,
        -- keine Kernaussage.
        local footer = {}
        if status then
            local guildBankAt, guildBankBy = nil, nil
            local ownBankAt = nil
            for _, row in ipairs(status.rows) do
                if row.guildBankAt and (not guildBankAt or row.guildBankAt > guildBankAt) then
                    guildBankAt = row.guildBankAt
                    guildBankBy = row.guildBankBy
                end
                if row.own.oldestBankAt and (not ownBankAt or row.own.oldestBankAt < ownBankAt) then
                    ownBankAt = row.own.oldestBankAt
                end
            end
            if not status.guildBankKnown then
                footer[#footer + 1] = "Gildenbank noch nicht eingelesen – einmal am Bankfach öffnen genügt."
            elseif guildBankAt and guildBankAt > 0 and date then
                footer[#footer + 1] = "Gildenbank: " .. date("%d.%m. %H:%M", guildBankAt)
                    .. (guildBankBy and guildBankBy ~= "" and (" · " .. guildBankBy) or "")
            end
            if ownBankAt and ownBankAt > 0 and date then
                footer[#footer + 1] = "Eigene Bank: " .. date("%d.%m. %H:%M", ownBankAt)
            end
        end
        page.workshopMaterialFooter:SetText(table.concat(footer, "\n"))
        page.workshopMaterialFooter:ClearAllPoints()
        page.workshopMaterialFooter:SetPoint("TOPLEFT", page.workshopDetailContent, "TOPLEFT", 0, -cursor)
        local footerHeight = #footer > 0
            and math.max(15, WrappedTextHeight(
                page.workshopMaterialFooter, table.concat(footer, "\n"), 274))
            or 0
        page.workshopMaterialFooter:SetHeight(math.max(1, footerHeight))
        cursor = cursor + footerHeight

        page.workshopDetailContent:SetHeight(math.max(220, cursor + 6))
        if page.workshopScrollAnchor ~= selected.key then
            page.workshopScrollAnchor = selected.key
            page.workshopDetailScroll:SetVerticalScroll(0)
        end
        page.workshopDetailScroll:UpdateModernThumb()
    end

    self:RefreshSyncBar()
end

-- Wie lange ist das her? Für den Balken reicht die grobe Angabe; auf die
-- Sekunde genau will das niemand wissen, und "vor 0 Sekunden" liest sich falsch.
local function AgeLabel(timestamp)
    local age = GC.Util.Now() - (tonumber(timestamp) or 0)
    if age < 60 then
        return GC.L("gerade eben")
    elseif age < 3600 then
        return GC.LFormat("vor {n} Min.", { n = math.floor(age / 60) })
    elseif age < 24 * 3600 then
        return GC.LFormat("vor {n} Std.", { n = math.floor(age / 3600) })
    end
    return GC.LFormat("vor {n} Tagen", { n = math.floor(age / (24 * 3600)) })
end

-- Der Balken unten in der Werkstatt und die Zeile darunter.
--
-- Die Zeile trägt zwei Aussagen, in dieser Reihenfolge: erst der Zustand des
-- Abgleichs, dann der eigene Beitrag dazu (nicht eingelesene Berufe). Beides
-- steht nebeneinander statt sich gegenseitig zu verdrängen - vorher gewann der
-- Paketzähler, und der Hinweis "Verzauberkunst noch nicht eingelesen" war genau
-- dann unsichtbar, wenn er gebraucht wurde.
-- So lange traegt der Balken nach einem Klick auf "Daten anfragen" die
-- Quittung, falls bis dahin keine echte Antwort eintrifft. Deckungsgleich mit
-- der Streuung der Manifestantworten: Danach ist entweder etwas da, oder es
-- gibt gerade niemanden, der antwortet.
local REQUEST_ACK_SECONDS = 32

function GC.UI:RefreshSyncBar(force)
    local page = self.pages.WORKSHOP
    if not page or not page.syncBar then
        return
    end

    local status = GC.Sync:GetSyncStatus()
    local coverage = status.coverage or { professions = 0, crafters = 0 }
    local stats = GC.Sync:GetAddonUserStats()
    -- Die Quittung des Anfrage-Knopfs laeuft hier ab, nicht im Knopf: Der
    -- Balken tickt ohnehin, solange die Seite sichtbar ist.
    local ackRemaining = 0
    if page.workshopRequestAckAt then
        ackRemaining = math.max(0,
            REQUEST_ACK_SECONDS - (GC.Util.Now() - page.workshopRequestAckAt))
        if ackRemaining == 0 then
            page.workshopRequestAckAt = nil
        end
    end
    -- Viermal je Sekunde nachsehen ist billig, viermal je Sekunde alle
    -- Beschriftungen neu zusammensetzen nicht. Gezeichnet wird deshalb nur,
    -- wenn sich am Zustand wirklich etwas geaendert hat.
    -- Das Alter geht in Minuten ein, nicht in Sekunden: "Stand: vor 3 Min."
    -- muss mitwandern, ohne dafuer viermal je Sekunde neu gesetzt zu werden.
    local ageMinutes = math.floor(
        (GC.Util.Now() - (tonumber(status.lastSyncedAt) or 0)) / 60)
    local signature = table.concat({
        status.state,
        status.percent,
        status.outstanding,
        status.failed,
        status.lostWants or 0,
        coverage.professions or 0,
        coverage.crafters or 0,
        stats.players or 1,
        math.ceil(ackRemaining),
        status.waiting and "W" or "-",
        status.paused and "K" or "-",
        ageMinutes,
        (status.peerSeenAt or 0) > 0 and "P" or "-",
        #GC.Workshop:GetMissingOwnProfessions(),
    }, "|")
    if force ~= true and page.syncSignature == signature then
        return
    end
    page.syncSignature = signature

    local text, color, percentText, percentColor

    if status.state == "RUNNING" then
        page.syncBar:SetProgress(status.percent / 100, THEME.accent)
        percentText = status.percent .. " %"
        percentColor = THEME.accent
        -- Wartet seit über zwei Minuten dasselbe Paket auf den Kanal, steht
        -- der Abgleich zwar nicht still, kommt aber auch nicht voran. Das
        -- gehört gesagt: Sonst steht bei einem verstopften Kanal beliebig
        -- lange "läuft", ohne dass sich etwas rührt. Als Verlust verbucht wird
        -- deswegen nichts - unterwegs ist unterwegs.
        text = "|cff2ed9e6Abgleich läuft|r  •  noch " .. status.outstanding
            .. (status.outstanding == 1 and " Paket" or " Pakete")
            .. (status.paused
                and ". Im Kampf pausiert; es geht nach dem Kampf weiter."
                or status.waiting
                and ". Der Chatkanal ist gerade ausgelastet; es geht weiter, sobald er frei wird."
                or ". Das Fenster kann geschlossen werden.")
        color = THEME.accent
    elseif status.state == "INCOMPLETE" then
        page.syncBar:SetProgress(1, THEME.danger)
        percentText = "lückenhaft"
        percentColor = THEME.danger
        -- Zwei verschiedene Fehlschlaege, zwei verschiedene Saetze: verlorene
        -- Pakete und Berufe, deren angekuendigte Daten nie kamen.
        local lostWants = tonumber(status.lostWants) or 0
        local lostPackets = math.max(0, (tonumber(status.failed) or 0) - lostWants)
        local parts = {}
        if lostPackets > 0 then
            parts[#parts + 1] = lostPackets
                .. (lostPackets == 1 and " Paket kam nicht durch" or " Pakete kamen nicht durch")
        end
        if lostWants > 0 then
            parts[#parts + 1] = lostWants == 1
                and "ein angekündigter Beruf blieb aus (Hersteller offline?)"
                or (lostWants .. " angekündigte Berufe blieben aus (Hersteller offline?)")
        end
        text = "|cffff6266Abgleich unvollständig|r  •  " .. table.concat(parts, ", ")
            .. ". „Daten anfragen“ holt den Stand erneut."
        color = THEME.danger
    elseif status.state == "SYNCED" then
        -- "Vollstaendig" ist eine Aussage ueber die GILDE, nicht ueber die
        -- eigene Warteschlange. Sie steht deshalb nur da, wenn es (a) ueberhaupt
        -- einen Vergleichspartner gab und (b) keine bekannte Bestandsluecke
        -- offen ist - sonst hiess "Vollstaendig synchronisiert" nur "mir ist
        -- nichts aufgefallen", und das ist keine Auskunft.
        local others = math.max(0, (stats.players or 1) - 1)
        if (status.peerSeenAt or 0) == 0 or others == 0 then
            -- Belegt ist nur die halbe Aussage, also steht auch nur die halbe da.
            page.syncBar:SetProgress(1, THEME.muted)
            percentText = "100 %"
            percentColor = THEME.muted
            text = "|cff8b98a5Nichts offen|r  •  bisher hat sich kein anderer"
                .. " Guild-Copilot-Nutzer gemeldet – verglichen wurde also mit niemandem."
        elseif (coverage.professions or 0) > 0 then
            page.syncBar:SetProgress(1, THEME.warning)
            percentText = "lückenhaft"
            percentColor = THEME.warning
            local names = GC.Workshop:GetCoverageGapNames(4)
            local crafterText = coverage.crafters == 1
                and "einem Hersteller" or (coverage.crafters .. " Herstellern")
            text = "|cffffb84dNichts offen, aber unvollständig|r  •  Rezepte von "
                .. crafterText .. " fehlen noch (" .. table.concat(names, ", ")
                .. ((coverage.crafters or 0) > #names and ", …" or "")
                .. ") – ein Bote liefert sie, sobald jemand online ist, der sie hat."
        else
            page.syncBar:SetProgress(1, THEME.success)
            percentText = "100 %"
            percentColor = THEME.success
            text = "|cff59e695" .. GC.L("Vollständig synchronisiert") .. "|r  •  "
                .. (others == 1 and GC.L("abgeglichen mit einem weiteren Nutzer")
                    or GC.LFormat("abgeglichen mit {n} weiteren Nutzern", { n = others }))
                .. "  •  " .. GC.LFormat("Stand: {zeit}.", { zeit = AgeLabel(status.lastSyncedAt) })
        end
        color = THEME.success
    else
        page.syncBar:SetProgress(0, THEME.muted)
        percentText = "–"
        percentColor = THEME.muted
        text = "Noch kein Abgleich gelaufen  •  „Daten anfragen“ holt den Stand der Gilde."
        color = THEME.muted
    end

    -- Die Quittung des Anfrage-Knopfs. Sie ueberdeckt jeden RUHENDEN Zustand:
    -- Auch "unvollstaendig" soll nach dem Klick sichtbar quittieren, sonst
    -- sieht der Klick wirkungslos aus. Nur echter Fortschritt (RUNNING) ist
    -- die bessere Auskunft und bleibt stehen.
    if ackRemaining > 0 and status.state ~= "RUNNING" then
        page.syncBar:SetProgress(1, THEME.accent)
        percentText = "angefragt"
        percentColor = THEME.accent
        text = "|cff2ed9e6Anfrage gesendet|r  •  die Antworten treffen gestreut ein"
            .. " – der Balken springt an, sobald die erste da ist."
        color = THEME.accent
    end
    if page.workshopRequest then
        if ackRemaining > 0 then
            page.workshopRequest:Disable()
            page.workshopRequest:SetText("Angefragt … " .. math.ceil(ackRemaining) .. " s")
        else
            page.workshopRequest:Enable()
            page.workshopRequest:SetText(GC.L("Daten anfragen"))
        end
    end

    -- Der eigene Beitrag hängt hinten an: Wer seine Berufe nie geöffnet hat,
    -- ist selbst dann unvollständig, wenn die Leitung gerade ruhig ist.
    local missingProfessions = GC.Workshop:GetMissingOwnProfessions()
    if #missingProfessions > 0 then
        text = text .. "  |cffffb84dDeine Berufe fehlen noch: "
            .. table.concat(missingProfessions, ", ") .. " – Berufsfenster einmal öffnen.|r"
    elseif status.state == "IDLE" and GC.Workshop.lastScan then
        text = text .. "  Zuletzt erkannt: " .. GC.Workshop.lastScan.name
            .. " mit " .. GC.Workshop.lastScan.recipes .. " Rezepten."
    end

    page.workshopStatus:SetText(text)
    SetTextColor(page.workshopStatus, color)
    page.syncPercent:SetText(percentText)
    SetTextColor(page.syncPercent, percentColor)
end

-- === Gildenaufträge: Board, Dialoge, Ansicht ================================
-- Konzept: docs/KONZEPT-werkstatt-gildenauftraege.md. Das Board ersetzt bei
-- aktivem Reiter die Katalogkarten; die Logik liegt vollständig in Orders.lua,
-- hier wird nur gezeichnet und geklickt.

function GC.UI:SetWorkshopView(view)
    local page = self.pages.WORKSHOP
    if not page then
        return
    end
    page.workshopView = view == "ORDERS" and "ORDERS" or "CATALOG"
    local catalog = page.workshopView == "CATALOG"
    for _, frame in ipairs(page.workshopCatalogFrames or {}) do
        frame:SetShown(catalog)
    end
    if page.ordersView then
        page.ordersView:SetShown(not catalog)
        -- Frisch aufgeschlagen steht das Board oben. Nur beim Reiterwechsel,
        -- nicht bei jeder Datenauffrischung - sonst springt die Liste beim
        -- Stöbern unter der Hand weg (dieselbe Regel wie in der Spielerliste
        -- der Ausrüstungsseite).
        if not catalog and page.ordersView.scroll then
            page.ordersView.scroll.targetScroll = nil
            page.ordersView.scroll:SetVerticalScroll(0)
        end
    end
    -- Die Ansicht entscheidet mit, welcher Navigationspunkt leuchtet.
    self:RefreshTabHighlight()
    self:RefreshWorkshop()
end

-- Die Handlungsaufforderung als Knopf: je Auftrag und Rolle genau eine
-- Primäraktion. Liefert Beschriftung und Ausführung oder nil.
local function OrderPrimaryAction(order)
    local orders = GC.Orders
    local ownName = GC:GetPlayerFullName()
    local isCreator = orders:IsCreatorCharacter(order, ownName)
    local isAcceptor = GC.Util.Trim(order.acceptedByTag) ~= ""
        and order.acceptedByTag == GC.DB:GetAccountTag()

    if isAcceptor then
        if order.status == "ACCEPTED" then
            return "Material vollständig", function(id)
                return orders:MarkMaterialsComplete(id)
            end
        elseif order.status == "WORKING" then
            return "Gefertigt", function(id)
                local target = orders:GetOrder(id)
                if target and (target.materialModel == "C" or (target.quantity or 1) > 1) then
                    GC.UI:OpenOrderCostDialog(id)
                    return true, ""
                end
                return orders:MarkCrafted(id)
            end
        elseif order.status == "CRAFTED" and order.delivery == "MAIL" then
            return "Versandt", function(id)
                return orders:MarkShipped(id)
            end
        elseif order.status == "CRAFTED" and order.delivery == "TRADE" then
            -- Übergabe vereinbaren: das Chatfenster mit dem richtigen
            -- Empfänger vorbelegen (Stufe 2).
            return "Anflüstern", function(id)
                return GC.UI:WhisperOrderCounterpart(id)
            end
        elseif order.status == "RECEIVED" and (order.reimbursedAt or 0) > 0 then
            return "Erstattung erhalten", function(id)
                return orders:ConfirmReimbursed(id)
            end
        end
    end
    if isCreator then
        if order.status == "CRAFTED" or order.status == "SHIPPED" then
            return "Erhalten", function(id)
                return orders:MarkReceived(id)
            end
        elseif order.status == "RECEIVED" and (order.reimbursedAt or 0) == 0 then
            return "Erstattet", function(id)
                GC.UI:OpenOrderPayDialog(id)
                return true, ""
            end
        elseif (order.status == "ACCEPTED" or order.status == "WORKING")
            and orders:IsStale(order) then
            return "Zurücklegen", function(id)
                return orders:Return(id, "Rückfall durch den Auftraggeber",
                    orders:HasAcceptorLeftGuild(orders:GetOrder(id)))
            end
        end
    end
    return nil
end

-- Farbkennzeichnung der Status: gelb wartet, türkis läuft, grün fertig,
-- rot abgebrochen. Die Hexwerte entsprechen THEME.warning/accent/success/
-- danger, wie sie das Addon auch sonst in Textform verwendet.
local ORDER_STATUS_COLORS = {
    OPEN = "|cffe8b84b",
    ACCEPTED = "|cff2ed9e6",
    WORKING = "|cff2ed9e6",
    CRAFTED = "|cff2ed9e6",
    SHIPPED = "|cff2ed9e6",
    RECEIVED = "|cffe8b84b",
    DONE = "|cff59e695",
    CANCELLED = "|cffff6266",
}

local function ColoredOrderStatus(order)
    return (ORDER_STATUS_COLORS[order.status] or "")
        .. (GC.OrderStatusLabels[order.status] or order.status) .. "|r"
end

local function OrderRowTitle(order)
    local ownName = GC:GetPlayerFullName()
    local isCreator = GC.Orders:IsCreatorCharacter(order, ownName)
    local counterpart
    if isCreator then
        counterpart = GC.Util.Trim(order.crafter) ~= ""
            and ("Hersteller: " .. GC.Util.PlayerIdentityName(order.crafter))
            or "noch ohne Hersteller"
    else
        counterpart = "von " .. GC.Util.PlayerIdentityName(order.createdBy or "?")
    end
    -- Teilfertigung in der Zeile: „×10 (3 fertig)". Der Stand stand bis
    -- 0.9.109 nur im Verlaufsdialog, und die Zeile sah nach jedem
    -- Zwischenschritt unverändert aus - aus der Gilde kam das als „die Menge
    -- wird nicht gezählt" zurück.
    local quantity = tonumber(order.quantity) or 1
    local crafted = tonumber(order.craftedCount) or 0
    local amount = "×" .. quantity
    if quantity > 1 and crafted > 0 and crafted < quantity then
        amount = amount .. "  |cff2ed9e6" .. GC.LFormat("{n} fertig", { n = crafted }) .. "|r"
    end
    return (order.recipeName or order.recipeKey or "?")
        .. " " .. amount
        .. "  ·  " .. counterpart
        .. "  ·  " .. ColoredOrderStatus(order)
end

-- Die Bedingungen ohne Geld: Materialmodell und Übergabeweg. Beim Freitext
-- steht der Beruf davor - er ist dort die einzige Auskunft darüber, wer den
-- Auftrag überhaupt erfüllen kann.
local function OrderTermsParts(order)
    local parts = {}
    local freeProfession = GC.Orders:GetFreeProfessionName(order.recipeKey)
    if freeProfession then
        parts[#parts + 1] = "|cffe8b84bFreier Auftrag|r (" .. GC.L(freeProfession) .. ")"
    end
    parts[#parts + 1] = GC.OrderModelLabels[order.materialModel] or "?"
    parts[#parts + 1] = GC.OrderDeliveryLabels[order.delivery] or "?"
    return parts
end

-- Der Preisrahmen, den der Auftraggeber beim Erstellen gesetzt hat. Einen
-- Kostenrahmen gibt es nur beim Materialmodell C - Orders.lua setzt ihn sonst
-- auf 0 -, ein Trinkgeld bei allen.
local function OrderPriceParts(order)
    local parts = {}
    if (order.costLimit or 0) > 0 then
        parts[#parts + 1] = "bis " .. GC.Orders.FormatMoney(order.costLimit)
    end
    if (order.tip or 0) > 0 then
        parts[#parts + 1] = "Trinkgeld " .. GC.Orders.FormatMoney(order.tip)
    end
    return parts
end

local function AppendOrderNote(parts, order)
    if GC.Util.Trim(order.note) ~= "" then
        parts[#parts + 1] = "„" .. order.note .. "“"
    end
    return parts
end

local function OrderOfferLine(order)
    local parts = OrderTermsParts(order)
    for _, part in ipairs(OrderPriceParts(order)) do
        parts[#parts + 1] = part
    end
    return table.concat(AppendOrderNote(parts, order), "  ·  ")
end

-- In den eigenen Aufträgen trägt der Preisrahmen eine eigene Zeile, deshalb
-- bleibt diese hier ohne Geld.
local function OrderTermsLine(order)
    return table.concat(AppendOrderNote(OrderTermsParts(order), order), "  ·  ")
end

-- Die Preiszeile der eigenen Aufträge. Wer am Zug ist, liest in der Zeile
-- darüber die Handlungsaufforderung statt der Bedingungen - damit verschwand
-- der Preisrahmen genau dort, wo die Gilde ihn braucht: beim Versenden soll
-- ohne Umweg über den Verlauf sichtbar sein, was der Auftraggeber zugesagt
-- hat. Gemeldete Kosten stehen daneben und werden rot, sobald sie den Rahmen
-- überschreiten - dieselbe Aussage wie im Verlaufsdialog.
local function OrderPriceFrameLine(order)
    local parts = OrderPriceParts(order)
    if (order.actualCost or 0) > 0 then
        local overLimit = (order.costLimit or 0) > 0 and order.actualCost > order.costLimit
        parts[#parts + 1] = (overLimit and "|cffff6266" or "")
            .. "gemeldet " .. GC.Orders.FormatMoney(order.actualCost)
            .. (overLimit and "|r" or "")
    end
    if #parts == 0 then
        parts[#parts + 1] = "keine Angabe des Auftraggebers"
    end
    return "Preisrahmen: " .. table.concat(parts, "  ·  ")
end

-- Maße des Auftragsboards.
--
-- Bis 0.9.109 standen hier drei feste Zeilen je Abschnitt in einer Ansicht
-- ohne Bildlauf. Wer vier Aufträge hatte, sah drei - der vierte existierte,
-- war aber mit keinem Handgriff erreichbar. Seit 0.9.110 tragen die
-- Abschnitte einen wachsenden Zeilenvorrat in einem Bildlauf; die Zahlen
-- beschreiben deshalb je EINE Zeile, nicht mehr die ganze Seite.
local ORDERS_VIEW_TOP = 66
local ORDERS_MINE_ROW_HEIGHT = 58
local ORDERS_OPEN_ROW_HEIGHT = 44
local ORDERS_ROW_GAP = 4
local ORDERS_HEADER_HEIGHT = 19
-- Die Überschrift der offenen Aufträge trägt rechts zwei Knöpfe und braucht
-- deshalb etwas mehr Luft als die anderen.
local ORDERS_FILTER_HEADER_HEIGHT = 23
local ORDERS_SECTION_GAP = 9
local ORDERS_CLOSED_LINE_HEIGHT = 17
-- Eine Auskunftszeile statt einer Überschrift, unter der nichts steht.
local ORDERS_EMPTY_LINE_HEIGHT = 17
-- Unten am Rand stehen Statuszeile, „Statistik" und „Tracker"; so viel Platz
-- bleibt unter dem Bildlauf frei. tests/validate.mjs rechnet damit nach, dass
-- selbst der höchste Abschnitt noch eine ganze Zeile zeigt, bevor gescrollt
-- werden muss.
local ORDERS_BOTTOM_BAR = 34
-- Die Zeilen sind schmaler als die Seite (776): Rechts läuft die Spur der
-- Bildlaufleiste mit.
local ORDERS_ROW_WIDTH = 760

local function BuildOrderRow(parent, height, withPrimary, withPrice, withDecline)
    local row = CreatePanel(parent, THEME.card)
    row:SetSize(ORDERS_ROW_WIDTH, height)
    -- Was rechts an Knöpfen steht, fehlt dem Text. Ausgerechnet statt fest
    -- eingetragen, weil die offenen Aufträge seit dem Ablehnen einen Knopf
    -- mehr tragen als die eigenen - eine feste Zahl wäre für eine der beiden
    -- Zeilenarten falsch.
    local textWidth = ORDERS_ROW_WIDTH - 14 - 10 - 74 - 6 - 28 - 6
        - (withPrimary and 174 or 0) - (withDecline and 34 or 0)
    row.title = CreateLabel(row, "", { width = textWidth, height = 16 })
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 14, -7)
    row.detail = CreateLabel(row, "", { muted = true, width = textWidth, height = 15 })
    row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", 14, -25)
    if withPrice then
        row.price = CreateLabel(row, "", {
            muted = true,
            font = "GameFontNormalSmall",
            width = textWidth,
            height = 14,
        })
        row.price:SetPoint("TOPLEFT", row, "TOPLEFT", 14, -42)
    end
    row.logButton = CreateButton(row, "Verlauf", 74, 28, function()
        if row.orderID then
            GC.UI:OpenOrderLogDialog(row.orderID)
        end
    end)
    row.logButton:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.cancelButton = CreateButton(row, "×", 28, 28, function()
        if row.orderID then
            local ok, message = GC.Orders:Cancel(row.orderID)
            GC.UI:SetOrdersStatus(message, ok)
        end
    end)
    row.cancelButton:SetPoint("RIGHT", row.logButton, "LEFT", -6, 0)
    local leftmost = row.cancelButton
    if withDecline then
        -- Ablehnen ist rein lokal: Es blendet den Auftrag bei einem selbst
        -- aus und lässt ihn für die Gilde offen. Der Knopf sitzt bewusst
        -- NICHT auf dem Platz des Abbrechen-×, obwohl die beiden sich nie
        -- begegnen - zwei verschieden folgenreiche Aktionen dürfen sich
        -- keinen Platz teilen.
        row.declineButton = CreateButton(row, "–", 28, 28, function(button)
            if row.orderID then
                GC.Orders:SetDeclined(row.orderID, not button.declined)
                GC.UI:RefreshOrdersBoard()
            end
        end)
        row.declineButton:SetPoint("RIGHT", row.cancelButton, "LEFT", -6, 0)
        row.declineButton:SetScript("OnEnter", function(button)
            if not button.active then
                SetTextureColor(button.background, THEME.cardHover)
            end
            if not GameTooltip then
                return
            end
            GameTooltip:SetOwner(button, "ANCHOR_TOP")
            if button.declined then
                GameTooltip:SetText(GC.L("Wieder einblenden"))
                GameTooltip:AddLine("Holt den Auftrag zurück in deine Liste.", 1, 1, 1, true)
            else
                GameTooltip:SetText(GC.L("Nicht für mich"))
                GameTooltip:AddLine("Blendet den Auftrag nur bei dir aus. Für die Gilde"
                    .. " bleibt er offen, und niemand erfährt davon.", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        row.declineButton:SetScript("OnLeave", function(button)
            button:SetActive(button.active)
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        leftmost = row.declineButton
    end
    if withPrimary then
        row.primary = CreateButton(row, "", 168, 28, function()
            if row.orderID and row.primaryHandler then
                local ok, message = row.primaryHandler(row.orderID)
                GC.UI:SetOrdersStatus(message, ok)
            end
        end, "PRIMARY")
        row.primary:SetPoint("RIGHT", leftmost, "LEFT", -6, 0)
    end
    row:Hide()
    return row
end

-- === Abschnitte des Boards ==================================================
--
-- Ein Abschnitt besteht aus seiner Überschrift, einem wachsenden Zeilenvorrat
-- und der Zeile für den leeren Fall. Eine Zeile entsteht erst, wenn es sie zu
-- zeigen gilt, und wird danach wiederverwendet: Bei zwei Aufträgen kostet das
-- Board zwei Zeilen, nicht sechzig.
local function CreateOrderSection(content, headerText, emptyText, indent, factory)
    local section = {
        header = CreateLabel(content, headerText, { muted = true, width = 460, height = 15 }),
        empty = CreateLabel(content, emptyText, { muted = true, width = 700, height = 15 }),
        rows = {},
        indent = indent,
        factory = factory,
    }
    section.empty:Hide()
    return section
end

local function OrderSectionRow(section, index)
    local row = section.rows[index]
    if not row then
        row = section.factory()
        section.rows[index] = row
    end
    return row
end

-- Hängt einen Abschnitt an den laufenden Abstand und liefert dessen neuen
-- Stand zurück. Positioniert wird bei jedem Zeichnen neu, weil ein Abschnitt
-- mit dem Inhalt wächst und schrumpft und alles darunter mitschiebt.
local function LayoutOrderSection(section, content, cursor, entries, headerHeight, rowHeight, rowGap, fill)
    section.header:ClearAllPoints()
    section.header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -cursor)
    cursor = cursor + headerHeight
    for index = 1, #entries do
        local row = OrderSectionRow(section, index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", section.indent, -cursor)
        cursor = cursor + rowHeight + rowGap
        fill(row, entries[index])
    end
    for index = #entries + 1, #section.rows do
        section.rows[index]:Hide()
    end
    if #entries > 0 then
        -- Der Abstand nach der letzten Zeile gehört dem Abschnittsabstand.
        cursor = cursor - rowGap
        section.empty:Hide()
    else
        section.empty:ClearAllPoints()
        section.empty:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -cursor)
        section.empty:Show()
        cursor = cursor + ORDERS_EMPTY_LINE_HEIGHT
    end
    return cursor + ORDERS_SECTION_GAP
end

function GC.UI:BuildOrdersView(page)
    local view = CreateFrame("Frame", nil, page)
    view:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -ORDERS_VIEW_TOP)
    view:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    view:Hide()
    page.ordersView = view

    -- Alles Listenhafte liegt im Bildlauf, die Statuszeile und ihre Knöpfe
    -- bleiben unten stehen: Wer bis zum letzten Auftrag scrollt, soll den
    -- Tracker-Knopf nicht suchen müssen.
    local listArea = CreateFrame("Frame", nil, view)
    listArea:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
    listArea:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, ORDERS_BOTTOM_BAR)
    local scroll = CreateModernScrollFrame(listArea)
    scroll:SetPoint("TOPLEFT", listArea, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", listArea, "BOTTOMRIGHT", -14, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(ORDERS_ROW_WIDTH)
    content:SetHeight(1)
    scroll:SetScrollChild(content)
    view.scroll = scroll
    view.content = content

    view.mine = CreateOrderSection(content, "DU BIST DRAN",
        "Gerade läuft nichts für dich – weder als Auftraggeber noch als Hersteller.",
        0, function()
            return BuildOrderRow(content, ORDERS_MINE_ROW_HEIGHT, true, true)
        end)
    view.open = CreateOrderSection(content, "OFFENE AUFTRÄGE DER GILDE",
        "Zurzeit ist nichts offen.", 0, function()
            return BuildOrderRow(content, ORDERS_OPEN_ROW_HEIGHT, true, false, true)
        end)
    view.others = CreateOrderSection(content, "LÄUFT IN DER GILDE",
        "Sonst ist gerade nichts in Arbeit.", 0, function()
            return BuildOrderRow(content, ORDERS_OPEN_ROW_HEIGHT, false)
        end)
    view.closed = CreateOrderSection(content, "ABGESCHLOSSEN",
        "Noch nichts abgeschlossen.", 14, function()
            return CreateLabel(content, "", { muted = true, width = 700, height = 15 })
        end)

    -- Die beiden Knöpfe der Überschrift „offene Aufträge". Sie liegen im
    -- Bildlauf und wandern deshalb mit ihrer Überschrift; ihre Höhe von 24
    -- gegenüber 15 gleicht das Anheben um vier Pixel aus.
    view.openFilter = CreateButton(content, "nur machbare", 128, 24, function()
        page.ordersShowAll = not page.ordersShowAll
        GC.UI:RefreshOrdersBoard()
    end)
    view.declinedToggle = CreateButton(content, "Abgelehnte", 132, 24, function()
        page.ordersShowDeclined = not page.ordersShowDeclined
        GC.UI:RefreshOrdersBoard()
    end)
    view.declinedToggle:Hide()

    -- Die Zeilen der einzelnen Abschnitte bleiben unter ihren gewohnten Namen
    -- erreichbar: Der Vorrat wächst, die Zugriffe darauf ändern sich nicht.
    view.mineRows = view.mine.rows
    view.openRows = view.open.rows
    view.closedRows = view.closed.rows

    -- 150 statt 96: Der Knopf trägt „Tracker ausblenden", und das stand als
    -- „Tracker einble…" abgeschnitten da (aus dem Spiel gemeldet). Die Breite
    -- richtet sich nach der längsten Beschriftung, nicht nach der kürzesten.
    view.trackerToggle = CreateButton(view, "Tracker", 150, 24, function()
        GC.UI:ToggleOrderTracker()
    end)
    view.trackerToggle:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)

    -- Schmaler als bis 0.9.111 (640): Rechts stehen jetzt drei Knöpfe, und
    -- eine Statusmeldung darf nicht unter ihnen hindurchlaufen.
    view.status = CreateLabel(view, "", { muted = true, width = 350, height = 30, vertical = "TOP" })
    view.status:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", 0, 0)

    view.statsButton = CreateButton(view, "Statistik", 96, 24, function()
        GC.UI:OpenOrderStatsDialog()
    end)
    view.statsButton:SetPoint("RIGHT", view.trackerToggle, "LEFT", -8, 0)

    -- Der zweite Weg in einen Auftrag: ohne Rezept, nur mit Beruf und Wunsch.
    -- Er sitzt am Board und nicht am Katalog, weil es dort nichts auszuwählen
    -- gibt - genau das ist ja der Fall, für den es ihn gibt.
    view.freeOrderButton = CreateButton(view, "Freier Auftrag", 130, 24, function()
        GC.UI:OpenOrderCreateDialog()
    end)
    view.freeOrderButton:SetPoint("RIGHT", view.statsButton, "LEFT", -8, 0)

    self:BuildOrderCreateDialog(page)
    self:BuildOrderLogDialog(page)
    self:BuildOrderCostDialog(page)
    self:BuildOrderPayDialog(page)
    self:BuildOrderAcceptDialog(page)
    self:BuildOrderStatsDialog(page)
end

function GC.UI:SetOrdersStatus(message, success)
    local page = self.pages.WORKSHOP
    if not page or not page.ordersView then
        return
    end
    page.ordersView.status:SetText(message or "")
    SetTextColor(page.ordersView.status, success and THEME.success or THEME.danger)
end

local function FillOrderRow(row, boardRow, isOpenSection)
    local order = boardRow.order
    row.orderID = order.id
    row.title:SetText(OrderRowTitle(order))
    if row.declineButton then
        row.declineButton.declined = boardRow.declined == true
        row.declineButton:SetText(boardRow.declined and "+" or "–")
        row.declineButton:SetActive(boardRow.declined == true)
    end
    if isOpenSection then
        row.detail:SetText(OrderOfferLine(order))
        row.primaryHandler = function(id)
            return GC.UI:AcceptOrder(id)
        end
        row.primary:SetText(GC.L("Annehmen"))
        row.primary:SetShown(boardRow.canAccept == true)
        if boardRow.reserved then
            row.detail:SetText("|cffe8b84bReserviert für "
                .. GC.Util.PlayerIdentityName(order.preferredCrafter or "?")
                .. "|r  ·  " .. OrderOfferLine(order))
        elseif not boardRow.canAccept then
            row.detail:SetText((GC.Orders:GetFreeProfessionKey(order.recipeKey)
                and "Kein Charakter deines Accounts hat diesen Beruf  ·  "
                or "Kein Charakter deines Accounts kann dieses Rezept  ·  ")
                .. OrderOfferLine(order))
        end
        if boardRow.declined then
            row.detail:SetText("|cff8f9ba8Abgelehnt – nur für dich ausgeblendet|r  ·  "
                .. OrderOfferLine(order))
        end
    elseif boardRow.involved == false then
        -- Fremde laufende Aufträge: Hier gibt es nichts zu tun, nur etwas zu
        -- wissen. Statt der Aufforderung an den anderen steht deshalb, wer
        -- gerade dran ist und seit wann sich nichts bewegt hat.
        local waitingFor = boardRow.actor == "CREATOR" and order.createdBy or order.crafter
        row.detail:SetText(GC.Util.PlayerIdentityName(waitingFor or order.crafter or "?")
            .. " ist dran  ·  " .. AgeLabel(order.changedAt))
    else
        local detail = boardRow.yourTurn and boardRow.action or OrderTermsLine(order)
        -- Was der Client selbst mitgezählt hat, steht daneben - samt der
        -- Ansage, dass es noch niemand außer einem selbst weiß.
        local pending = GC.Orders:GetPendingCraftCount(order.id)
        if pending > 0 then
            detail = detail .. "  ·  |cff2ed9e6"
                .. GC.LFormat("{n} selbst gefertigt, noch nicht gemeldet", { n = pending })
                .. "|r"
        end
        row.detail:SetText(detail)
        local label, handler = OrderPrimaryAction(order)
        row.primaryHandler = handler
        if row.primary then
            row.primary:SetText(label or "")
            row.primary:SetShown(label ~= nil)
        end
    end
    if row.price then
        row.price:SetText(OrderPriceFrameLine(order))
    end
    local ownName = GC:GetPlayerFullName()
    row.cancelButton:SetShown(order.status ~= "DONE" and order.status ~= "CANCELLED"
        and (GC.Orders:IsCreatorCharacter(order, ownName) or GC.Orders:CanAdministrate(ownName)))

    -- Farbkennzeichnung am Rahmen: türkis heißt "du bist dran", grün heißt
    -- "für dich machbar", sonst die neutrale Kartenlinie. Dazu springt die
    -- Aufgabenzeile in Warnfarbe, statt grau unterzugehen.
    if boardRow.yourTurn then
        row:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        SetTextColor(row.detail, THEME.warning)
    elseif isOpenSection and boardRow.canAccept then
        row:SetBackdropBorderColor(THEME.success[1], THEME.success[2], THEME.success[3], 1)
        SetTextColor(row.detail, THEME.muted)
    else
        row:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
        SetTextColor(row.detail, THEME.muted)
    end
    row:Show()
end

function GC.UI:RefreshOrdersBoard()
    local page = self.pages.WORKSHOP
    local view = page and page.ordersView
    if not view then
        return
    end
    local board = GC.Orders:GetBoard()

    -- Zwei Filter auf denselben Abschnitt: „nur machbare" wirft weg, was kein
    -- Charakter dieses Accounts kann, das Ablehnen einzelne Zeilen. Beide
    -- lassen sich abschalten, keiner versteckt etwas dauerhaft.
    local open = {}
    local declinedCount = 0
    for _, boardRow in ipairs(board.open) do
        if boardRow.declined then
            declinedCount = declinedCount + 1
        end
        if (page.ordersShowAll or boardRow.canAccept)
            and (page.ordersShowDeclined or not boardRow.declined) then
            open[#open + 1] = boardRow
        end
    end
    view.openFilter:SetActive(not page.ordersShowAll)
    view.declinedToggle:SetText(GC.LFormat("{n} abgelehnt", { n = declinedCount }))
    view.declinedToggle:SetActive(page.ordersShowDeclined == true)
    view.declinedToggle:SetShown(declinedCount > 0)

    local cursor = 0
    view.mine.header:SetText(GC.LFormat("DU BIST DRAN  ·  MEINE AUFTRÄGE ({n})",
        { n = #board.mine }))
    cursor = LayoutOrderSection(view.mine, view.content, cursor, board.mine,
        ORDERS_HEADER_HEIGHT, ORDERS_MINE_ROW_HEIGHT, ORDERS_ROW_GAP,
        function(row, boardRow)
            FillOrderRow(row, boardRow, false)
        end)

    view.open.header:SetText(GC.LFormat("OFFENE AUFTRÄGE DER GILDE ({n})", { n = #open }))
    -- Die Knöpfe hängen an der Überschrift, die gerade gesetzt wird - deshalb
    -- vor dem Abschnitt, dessen Abstand sie schon weitergeschoben hat.
    view.openFilter:ClearAllPoints()
    view.openFilter:SetPoint("TOPRIGHT", view.content, "TOPRIGHT", 0, -(cursor - 4))
    view.declinedToggle:ClearAllPoints()
    view.declinedToggle:SetPoint("RIGHT", view.openFilter, "LEFT", -8, 0)
    cursor = LayoutOrderSection(view.open, view.content, cursor, open,
        ORDERS_FILTER_HEADER_HEIGHT, ORDERS_OPEN_ROW_HEIGHT, ORDERS_ROW_GAP,
        function(row, boardRow)
            FillOrderRow(row, boardRow, true)
        end)

    view.others.header:SetText(GC.LFormat("LÄUFT IN DER GILDE ({n})", { n = #board.others }))
    cursor = LayoutOrderSection(view.others, view.content, cursor, board.others,
        ORDERS_HEADER_HEIGHT, ORDERS_OPEN_ROW_HEIGHT, ORDERS_ROW_GAP,
        function(row, boardRow)
            FillOrderRow(row, boardRow, false)
        end)

    view.closed.header:SetText(GC.LFormat("ABGESCHLOSSEN ({n})", { n = #board.closed }))
    cursor = LayoutOrderSection(view.closed, view.content, cursor, board.closed,
        ORDERS_HEADER_HEIGHT, ORDERS_CLOSED_LINE_HEIGHT, 0,
        function(label, boardRow)
            local order = boardRow.order
            label:SetText((order.recipeName or "?") .. " ×" .. (order.quantity or 1)
                .. "  ·  " .. ColoredOrderStatus(order)
                .. "  ·  " .. GC.Util.PlayerIdentityName(order.createdBy or "?"))
            label:Show()
        end)

    -- Der Bildlauf braucht die Gesamthöhe seines Inhalts; ohne sie bliebe die
    -- Leiste stehen, egal wie viele Zeilen darunter warten.
    view.content:SetHeight(math.max(1, cursor - ORDERS_SECTION_GAP))
    if view.scroll.UpdateModernThumb then
        view.scroll:UpdateModernThumb()
    end

    local settings = GC.DB:GetSettings().orderTracker
    view.trackerToggle:SetText(settings.hidden and "Tracker einblenden" or "Tracker ausblenden")
    view.trackerToggle:SetActive(not settings.hidden)
end

-- Annehmen mit Twink-Wahl: Ein Charakter nimmt direkt an, bei mehreren
-- fragt ein kleiner Dialog, wer fertigt (Konzept, Owner-Abnahme).
function GC.UI:AcceptOrder(orderID)
    local order = GC.Orders:GetOrder(orderID)
    if not order then
        return false, "Der Auftrag ist nicht mehr bekannt."
    end
    local candidates = GC.Orders:GetOwnCrafters(order.recipeKey)
    if #candidates > 1 then
        self:OpenOrderAcceptDialog(orderID, candidates)
        return true, ""
    end
    local ok, message = GC.Orders:Accept(orderID, candidates[1])
    self:SetOrdersStatus(message, ok)
    return ok, message
end

local function BuildOrderDialogFrame(page, width, height, titleText)
    -- Wie die Dropdown-Menüs hängen die Dialoge NICHT unter der Seite: Die
    -- Seiten liegen in einem ScrollFrame, dessen Kinder beschnitten werden und
    -- deren Ebenen sich mit den Seitenkarten mischen - dahinterliegende Knöpfe
    -- schimmerten durch. Als Kind des Hauptfensters mit eigener hoher Ebene
    -- und voll deckendem Hintergrund liegt der Dialog sauber über allem.
    local host = GC.UI.frame or UIParent
    local dialog = CreatePanel(host, THEME.window, THEME.accent)
    dialog:SetSize(width, height)
    dialog:SetPoint("CENTER", host, "CENTER", 0, 0)
    local hostLevel = host.GetFrameLevel and host:GetFrameLevel() or 1
    dialog:SetFrameLevel((hostLevel or 1) + 80)
    dialog:SetBackdropColor(THEME.window[1], THEME.window[2], THEME.window[3], 1)
    dialog:EnableMouse(true)
    dialog.title = CreateLabel(dialog, titleText, { title = true, width = width - 60 })
    dialog.title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -12)
    dialog.close = CreateButton(dialog, "×", 24, 24, function()
        dialog:Hide()
    end)
    dialog.close:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -8, -8)
    dialog:Hide()
    -- Wechselt die Seite oder schließt das Fenster, geht der Dialog mit zu.
    page:HookScript("OnHide", function()
        dialog:Hide()
    end)
    return dialog
end

function GC.UI:BuildOrderCreateDialog(page)
    local dialog = BuildOrderDialogFrame(page, 452, 428, "Gildenauftrag erstellen")
    page.orderCreateDialog = dialog

    local function RadioRow(labelText, y, options, field)
        local caption = CreateLabel(dialog, labelText, { muted = true, width = 120, height = 15 })
        caption:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, y)
        local buttons = {}
        -- Die x-Position läuft mit der Summe der bisherigen Breiten mit;
        -- vorher stand der dritte, breitere Knopf außerhalb des Dialogs.
        local cursor = 16
        for index, option in ipairs(options) do
            local button = CreateButton(dialog, option.label, option.width, 24, function()
                dialog[field] = option.value
                for _, sibling in ipairs(buttons) do
                    sibling:SetActive(dialog[field] == sibling.optionValue)
                end
                dialog.costCaption:SetShown(dialog.materialModel == "C")
                dialog.costEdit.container:SetShown(dialog.materialModel == "C")
            end)
            button.optionValue = option.value
            button:SetPoint("TOPLEFT", dialog, "TOPLEFT", cursor, y - 17)
            cursor = cursor + option.width + 6
            buttons[index] = button
        end
        dialog[field .. "Buttons"] = buttons
    end

    RadioRow("Materialien", -40, {
        { value = "A", label = "Ich liefere", width = 100 },
        { value = "B", label = "Gildenbank", width = 100 },
        { value = "C", label = "Wird besorgt, ich erstatte", width = 190 },
    }, "materialModel")

    RadioRow("Übergabe", -94, {
        { value = "TRADE", label = "Persönlich", width = 100 },
        { value = "MAIL", label = "Per Post", width = 100 },
    }, "delivery")

    dialog.quantityCaption = CreateLabel(dialog, "Menge", { muted = true, width = 90, height = 15 })
    dialog.quantityCaption:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -148)
    dialog.quantityEdit = CreateEdit(dialog, 66, 26)
    dialog.quantityEdit.container:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -165)

    dialog.costCaption = CreateLabel(dialog, "Kostenrahmen (Gold)", { muted = true, width = 150, height = 15 })
    dialog.costCaption:SetPoint("TOPLEFT", dialog, "TOPLEFT", 100, -148)
    dialog.costEdit = CreateEdit(dialog, 90, 26)
    dialog.costEdit.container:SetPoint("TOPLEFT", dialog, "TOPLEFT", 100, -165)

    dialog.tipCaption = CreateLabel(dialog, "Trinkgeld (Gold)", { muted = true, width = 120, height = 15 })
    dialog.tipCaption:SetPoint("TOPLEFT", dialog, "TOPLEFT", 268, -148)
    dialog.tipEdit = CreateEdit(dialog, 90, 26)
    dialog.tipEdit.container:SetPoint("TOPLEFT", dialog, "TOPLEFT", 268, -165)

    dialog.noteCaption = CreateLabel(dialog, "Notiz (optional)", { muted = true, width = 200, height = 15 })
    dialog.noteCaption:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -206)
    dialog.noteEdit = CreateEdit(dialog, 398, 26)
    dialog.noteEdit.container:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -223)

    -- Gerichteter Auftrag: 24 Stunden nur für diesen Hersteller, danach
    -- offen für alle. Die Auswahl ist eine Liste der bekannten Hersteller
    -- des Rezepts (Owner-Wunsch: kein Freitext).
    dialog.preferredCaption = CreateLabel(dialog, "Wunsch-Hersteller (optional, 24 h reserviert)",
        { muted = true, width = 300, height = 15 })
    dialog.preferredCaption:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -258)
    dialog.preferredValue = ""
    dialog.preferredButton = CreateButton(dialog, "(keiner)", 180, 26, function()
        GC.UI:ToggleOrderCrafterList(dialog)
    end)
    dialog.preferredButton:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -275)

    -- Die Aufklappliste: ein Zeilenvorrat, je Öffnen mit den Herstellern des
    -- Rezepts gefüllt - "(keiner)" steht immer zuoberst.
    -- Breiter als der Knopf darüber: In die Zeile gehört neben dem Namen die
    -- laufende Sperre, und die entscheidet hier mehr als der Name.
    dialog.crafterList = CreatePanel(dialog, THEME.input, THEME.accent)
    dialog.crafterList:SetSize(250, 10)
    dialog.crafterList:SetPoint("TOPLEFT", dialog.preferredButton, "BOTTOMLEFT", 0, -2)
    dialog.crafterList:SetFrameLevel((dialog:GetFrameLevel() or 1) + 10)
    dialog.crafterList.rows = {}
    for index = 1, 9 do
        local rowButton = CreateButton(dialog.crafterList, "", 242, 22, function()
            local chosen = dialog.crafterList.rows[index].crafterName or ""
            dialog.preferredValue = chosen
            dialog.preferredButton:SetText(chosen ~= ""
                and GC.Util.PlayerIdentityName(chosen) or "(keiner)")
            dialog.crafterList:Hide()
        end)
        rowButton:SetPoint("TOPLEFT", dialog.crafterList, "TOPLEFT", 4, -4 - ((index - 1) * 24))
        rowButton:Hide()
        dialog.crafterList.rows[index] = rowButton
    end
    dialog.crafterList:Hide()

    -- Freitext-Auftrag: Wunsch in Worten plus der Beruf, der ihn erfüllen
    -- kann. Beide teilen sich die Zeile des Wunsch-Herstellers - der hat beim
    -- Freitext keine Grundlage, weil es zu einem unbekannten Rezept keine
    -- Herstellerliste gibt.
    local freeProfessions = {}
    for _, professionName in ipairs(GC.ProfessionOptions) do
        if professionName ~= "" then
            freeProfessions[#freeProfessions + 1] = professionName
        end
    end
    freeProfessions[#freeProfessions + 1] = "Kochkunst"
    freeProfessions[#freeProfessions + 1] = "Erste Hilfe"
    dialog.freeCaption = CreateLabel(dialog, "Was brauchst du? (kurz)",
        { muted = true, width = 232, height = 15 })
    dialog.freeCaption:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -258)
    dialog.freeEdit = CreateEdit(dialog, 232, 26)
    dialog.freeEdit.container:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -275)
    dialog.professionCaption = CreateLabel(dialog, "Beruf", { muted = true, width = 176, height = 15 })
    dialog.professionCaption:SetPoint("TOPLEFT", dialog, "TOPLEFT", 258, -258)
    -- Nach oben aufklappend: Die Zeile sitzt am unteren Rand des Dialogs.
    dialog.professionDropdown = CreateChoiceDropdown(dialog, 176, freeProfessions, function(value)
        dialog.freeProfession = value
    end, false, "Beruf wählen", function(professionName)
        return GC.ProfessionIcons[professionName or ""] or GC.ProfessionIcons[""]
    end)
    dialog.professionDropdown:SetPoint("TOPLEFT", dialog, "TOPLEFT", 258, -277)
    dialog.freeCaption:Hide()
    dialog.freeEdit.container:Hide()
    dialog.professionCaption:Hide()
    dialog.professionDropdown:Hide()

    dialog.templateButton = CreateButton(dialog, "Als Vorlage merken", 160, 26, function()
        local saved = GC.Orders:SaveTemplate(dialog.recipeKey, {
            quantity = tonumber(GC.Util.Trim(dialog.quantityEdit:GetText())) or 1,
            materialModel = dialog.materialModel,
            delivery = dialog.delivery,
            costLimit = math.floor((tonumber(GC.Util.Trim(dialog.costEdit:GetText())) or 0) * 10000),
            tip = math.floor((tonumber(GC.Util.Trim(dialog.tipEdit:GetText())) or 0) * 10000),
            note = dialog.noteEdit:GetText(),
            preferredCrafter = dialog.preferredValue,
        })
        dialog.status:SetText(saved and "Vorlage gemerkt – sie füllt diesen Dialog beim nächsten Mal vor."
            or "Vorlage konnte nicht gemerkt werden.")
        SetTextColor(dialog.status, saved and THEME.success or THEME.danger)
    end)
    dialog.templateButton:SetPoint("TOPLEFT", dialog, "TOPLEFT", 252, -273)

    dialog.status = CreateLabel(dialog, "", { muted = true, width = 398, height = 46, vertical = "TOP" })
    dialog.status:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -312)

    dialog.submit = CreateButton(dialog, "Erstellen", 150, 32, function()
        local gold = tonumber(GC.Util.Trim(dialog.costEdit:GetText())) or 0
        local tip = tonumber(GC.Util.Trim(dialog.tipEdit:GetText())) or 0
        local recipeKey, freeName = dialog.recipeKey, nil
        if dialog.freeMode then
            recipeKey = GC.Orders:FreeRecipeKey(dialog.freeProfession or "")
            freeName = GC.Util.Trim(dialog.freeEdit:GetText())
            if not recipeKey then
                dialog.status:SetText(GC.L("Wähle den Beruf, der den Auftrag erfüllen kann."))
                SetTextColor(dialog.status, THEME.danger)
                return
            end
        end
        local ok, message = GC.Orders:Create(recipeKey, {
            quantity = tonumber(GC.Util.Trim(dialog.quantityEdit:GetText())) or 1,
            materialModel = dialog.materialModel,
            delivery = dialog.delivery,
            costLimit = math.floor(gold * 10000),
            tip = math.floor(tip * 10000),
            note = dialog.noteEdit:GetText(),
            preferredCrafter = dialog.preferredValue,
            freeName = freeName,
        })
        if ok then
            dialog:Hide()
            GC.UI:SetWorkshopView("ORDERS")
            if GC.Orders:GetOnlineAddonUserCount() == 0 then
                GC.UI:SetOrdersStatus((message or "")
                    .. " |cffe8b84bGerade ist niemand mit Guild Copilot online - "
                    .. "verteilt wird beim nächsten gemeinsamen Login.|r", true)
            else
                GC.UI:SetOrdersStatus(message, true)
            end
        else
            dialog.status:SetText(message or "")
            SetTextColor(dialog.status, THEME.danger)
        end
    end, "PRIMARY")
    dialog.submit:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 16, 14)
    dialog.cancel = CreateButton(dialog, "Abbrechen", 110, 32, function()
        dialog:Hide()
    end)
    dialog.cancel:SetPoint("LEFT", dialog.submit, "RIGHT", 10, 0)
end

-- Ohne Rezeptschlüssel öffnet derselbe Dialog den Freitext-Auftrag: Das ist
-- kein zweites Fenster, weil bis auf Wunsch und Beruf alles identisch ist -
-- Materialmodell, Übergabeweg, Menge, Kostenrahmen, Trinkgeld, Notiz.
function GC.UI:OpenOrderCreateDialog(recipeKey)
    local page = self.pages.WORKSHOP
    local dialog = page and page.orderCreateDialog
    if not dialog then
        return
    end
    local freeMode = GC.Util.Trim(recipeKey or "") == ""
    dialog.freeMode = freeMode
    dialog.freeCaption:SetShown(freeMode)
    dialog.freeEdit.container:SetShown(freeMode)
    dialog.professionCaption:SetShown(freeMode)
    dialog.professionDropdown:SetShown(freeMode)
    -- Wunsch-Hersteller und Vorlage hängen beide am Rezept; beim Freitext
    -- gibt es keines, und ihre Zeile gehört dort Wunsch und Beruf.
    dialog.preferredCaption:SetShown(not freeMode)
    dialog.preferredButton:SetShown(not freeMode)
    dialog.templateButton:SetShown(not freeMode)
    if freeMode then
        dialog.crafterList:Hide()
        dialog.recipeKey = nil
        dialog.freeProfession = nil
        dialog.freeEdit:SetText(GC.L(""))
        dialog.professionDropdown:SetValue("")
        dialog.title:SetText(GC.L("Freier Gildenauftrag"))
    end
    local entry = not freeMode and GC.Workshop:GetCatalogEntry(recipeKey) or nil
    if not freeMode then
        dialog.recipeKey = recipeKey
        dialog.title:SetText("Gildenauftrag: " .. ((entry and entry.name) or recipeKey))
    end
    -- Vorlage des Rezepts, falls gemerkt - sonst die Grundeinstellung.
    local template = not freeMode and GC.Orders:GetTemplate(recipeKey) or nil
    dialog.materialModel = template and template.materialModel or "A"
    dialog.delivery = template and template.delivery or "TRADE"
    for _, button in ipairs(dialog.materialModelButtons or {}) do
        button:SetActive(button.optionValue == dialog.materialModel)
    end
    for _, button in ipairs(dialog.deliveryButtons or {}) do
        button:SetActive(button.optionValue == dialog.delivery)
    end
    dialog.quantityEdit:SetText(tostring(template and template.quantity or 1))
    dialog.costEdit:SetText(template and template.costLimit and template.costLimit > 0
        and tostring(math.floor(template.costLimit / 10000)) or "")
    dialog.tipEdit:SetText(template and template.tip and template.tip > 0
        and tostring(math.floor(template.tip / 10000)) or "")
    dialog.noteEdit:SetText(template and template.note or "")
    dialog.preferredValue = template and template.preferredCrafter or ""
    dialog.preferredButton:SetText(dialog.preferredValue ~= ""
        and GC.Util.PlayerIdentityName(dialog.preferredValue) or "(keiner)")
    dialog.recipeCrafters = (entry and entry.crafters) or {}
    dialog.crafterList:Hide()
    dialog.costCaption:SetShown(dialog.materialModel == "C")
    dialog.costEdit.container:SetShown(dialog.materialModel == "C")
    -- Ohne Gegenstelle kein Sync: Die Aufträge reisen nur von Client zu
    -- Client. Wer allein online ist, soll das VOR dem Erstellen wissen -
    -- der Auftrag geht nicht verloren, aber er erreicht die Gilde erst
    -- beim nächsten gemeinsamen Online-Moment.
    if GC.Orders:GetOnlineAddonUserCount() == 0 then
        dialog.status:SetText(GC.L("|cffe8b84bHinweis:|r Gerade ist niemand mit Guild Copilot online. "
            .. "Der Auftrag wird gespeichert und verteilt sich, sobald du gemeinsam "
            .. "mit anderen Addon-Nutzern online bist."))
        SetTextColor(dialog.status, THEME.text)
    else
        dialog.status:SetText(GC.L(""))
    end
    dialog:Show()
end

function GC.UI:BuildOrderLogDialog(page)
    local dialog = BuildOrderDialogFrame(page, 470, 360, "Verlauf")
    page.orderLogDialog = dialog
    dialog.body = CreateLabel(dialog, "", { width = 434, height = 220, vertical = "TOP" })
    dialog.body:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -42)
    dialog.noteEdit = CreateEdit(dialog, 212, 26)
    dialog.noteEdit.container:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 16, 14)
    dialog.noteSend = CreateButton(dialog, "Notiz senden", 118, 26, function()
        local ok, message = GC.Orders:AddNote(dialog.orderID, dialog.noteEdit:GetText())
        if ok then
            dialog.noteEdit:SetText(GC.L(""))
            GC.UI:RefreshOrderLogDialog()
        end
        GC.UI:SetOrdersStatus(message, ok)
    end, "PRIMARY")
    dialog.noteSend:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 14)
    dialog.whisper = CreateButton(dialog, "Anflüstern", 96, 26, function()
        GC.UI:WhisperOrderCounterpart(dialog.orderID)
    end)
    dialog.whisper:SetPoint("RIGHT", dialog.noteSend, "LEFT", -6, 0)
end

function GC.UI:RefreshOrderLogDialog()
    local page = self.pages.WORKSHOP
    local dialog = page and page.orderLogDialog
    if not dialog or not dialog:IsShown() then
        return
    end
    local order = GC.Orders:GetOrder(dialog.orderID)
    if not order then
        dialog:Hide()
        return
    end
    dialog.title:SetText("Verlauf: " .. (order.recipeName or "?"))
    local lines = {}
    for index = #order.log, 1, -1 do
        local entry = order.log[index]
        local stamp = date and date("%d.%m. %H:%M", entry.at) or tostring(entry.at)
        lines[#lines + 1] = "|cff91a3b8" .. stamp .. "|r  "
            .. GC.Util.PlayerIdentityName(entry.by or "?") .. ": "
            .. (GC.OrderEventLabels[entry.event] or entry.event)
            .. (GC.Util.Trim(entry.note or "") ~= "" and ("  –  " .. entry.note) or "")
    end
    if (order.actualCost or 0) > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Gemeldete Kosten: " .. GC.Orders.FormatMoney(order.actualCost)
            .. ((order.costLimit or 0) > 0 and order.actualCost > order.costLimit
                and "  |cffff6266(über dem Kostenrahmen)|r" or "")
    end
    dialog.body:SetText(table.concat(lines, "\n"))
end

function GC.UI:OpenOrderLogDialog(orderID)
    local page = self.pages.WORKSHOP
    local dialog = page and page.orderLogDialog
    if not dialog then
        return
    end
    dialog.orderID = orderID
    dialog.noteEdit:SetText(GC.L(""))
    dialog:Show()
    self:RefreshOrderLogDialog()
end

function GC.UI:BuildOrderCostDialog(page)
    local dialog = BuildOrderDialogFrame(page, 360, 240, "Gefertigt melden")
    page.orderCostDialog = dialog
    dialog.caption = CreateLabel(dialog,
        "Tatsächliche Materialkosten in Gold (0, wenn nichts anfiel):",
        { muted = true, width = 324, height = 30, vertical = "TOP" })
    dialog.caption:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -42)
    dialog.costEdit = CreateEdit(dialog, 100, 26)
    dialog.costEdit.container:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -80)
    -- Teilfertigung: Bei Stückzahlen > 1 fragt der Dialog den Gesamtstand ab;
    -- unter der vollen Menge bleibt der Auftrag in Arbeit.
    dialog.countCaption = CreateLabel(dialog, "Stück insgesamt fertig:",
        { muted = true, width = 180, height = 15 })
    dialog.countCaption:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -114)
    dialog.countEdit = CreateEdit(dialog, 70, 26)
    dialog.countEdit.container:SetPoint("TOPLEFT", dialog, "TOPLEFT", 200, -110)
    dialog.submit = CreateButton(dialog, "Melden", 150, 30, function()
        local gold = tonumber(GC.Util.Trim(dialog.costEdit:GetText())) or 0
        local ok, message = GC.Orders:MarkCrafted(dialog.orderID,
            math.floor(gold * 10000), nil,
            tonumber(GC.Util.Trim(dialog.countEdit:GetText())))
        GC.UI:SetOrdersStatus(message, ok)
        if ok then
            dialog:Hide()
        end
    end, "PRIMARY")
    dialog.submit:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 16, 14)

    -- Hier ist der Ort für das Herstellen: Der Dialog ist genau der Moment,
    -- in dem jemand die Stücke macht. Gefertigt wird die noch offene Menge;
    -- was der Client dabei wirklich herstellt, zählt der Mitzähler mit und
    -- schreibt es in das Feld darüber.
    dialog.craftButton = CreateButton(dialog, "Herstellen", 150, 30, function()
        local order = GC.Orders:GetOrder(dialog.orderID)
        if not order or not dialog.craftButton.craftReady then
            GC.UI:RefreshOrderCraftButton()
            return
        end
        local remaining = math.max(1, (tonumber(order.quantity) or 1)
            - (tonumber(order.craftedCount) or 0)
            - GC.Orders:GetPendingCraftCount(dialog.orderID))
        local ok, message = GC.Workshop:CraftOpenRecipe(order.recipeKey, remaining)
        dialog.status:SetText(message or "")
        SetTextColor(dialog.status, ok and THEME.success or THEME.danger)
    end, nil, true)
    dialog.craftButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 14)
    dialog.status = CreateLabel(dialog, "", { muted = true, width = 324, height = 28, vertical = "TOP" })
    dialog.status:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 16, 48)
end

-- Der Knopf im Gefertigt-Dialog folgt demselben Zweischritt wie der im
-- Katalog; er kennt zusätzlich die noch offene Menge des Auftrags.
function GC.UI:RefreshOrderCraftButton()
    local page = self.pages.WORKSHOP
    local dialog = page and page.orderCostDialog
    if not dialog or not dialog.orderID then
        return
    end
    local order = GC.Orders:GetOrder(dialog.orderID)
    if not order then
        return
    end
    local remaining = math.max(1, (tonumber(order.quantity) or 1)
        - (tonumber(order.craftedCount) or 0)
        - GC.Orders:GetPendingCraftCount(dialog.orderID))
    self:RefreshCraftButton(dialog.craftButton, order.recipeKey, remaining)
end

function GC.UI:OpenOrderCostDialog(orderID)
    local page = self.pages.WORKSHOP
    local dialog = page and page.orderCostDialog
    if not dialog then
        return
    end
    local order = GC.Orders:GetOrder(orderID)
    dialog.orderID = orderID
    dialog.costEdit:SetText(GC.L(""))
    local isC = order and order.materialModel == "C"
    dialog.caption:SetShown(isC == true)
    dialog.costEdit.container:SetShown(isC == true)
    local multi = order and (order.quantity or 1) > 1
    dialog.countCaption:SetShown(multi == true)
    dialog.countEdit.container:SetShown(multi == true)
    if multi then
        dialog.countCaption:SetText("Stück insgesamt fertig (von " .. order.quantity .. "):")
        -- Vorbelegt mit dem, was der Client selbst mitgezählt hat - und mit
        -- der vollen Menge, solange nichts mitgezählt wurde. Wer von Hand
        -- fertigt, überschreibt die Zahl wie bisher.
        local pending = GC.Orders:GetPendingCraftCount(orderID)
        local counted = math.min(order.quantity, (tonumber(order.craftedCount) or 0) + pending)
        dialog.countEdit:SetText(tostring(pending > 0 and counted or order.quantity))
    end
    dialog.status:SetText(GC.L(""))
    self:RefreshOrderCraftButton()
    dialog:Show()
end

-- Teilzahlungs-Dialog des Auftraggebers: vorgefüllt mit dem offenen Rest.
function GC.UI:BuildOrderPayDialog(page)
    local dialog = BuildOrderDialogFrame(page, 360, 170, "Erstattung überweisen")
    page.orderPayDialog = dialog
    dialog.caption = CreateLabel(dialog, "", { muted = true, width = 324, height = 30, vertical = "TOP" })
    dialog.caption:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -42)
    dialog.amountEdit = CreateEdit(dialog, 100, 26)
    dialog.amountEdit.container:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -80)
    dialog.submit = CreateButton(dialog, "Gezahlt melden", 150, 30, function()
        local gold = tonumber(GC.Util.Trim(dialog.amountEdit:GetText())) or 0
        local ok, message = GC.Orders:MarkReimbursed(dialog.orderID, math.floor(gold * 10000))
        GC.UI:SetOrdersStatus(message, ok)
        if ok then
            dialog:Hide()
        end
    end, "PRIMARY")
    dialog.submit:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 16, 14)
end

function GC.UI:OpenOrderPayDialog(orderID)
    local page = self.pages.WORKSHOP
    local dialog = page and page.orderPayDialog
    if not dialog then
        return
    end
    local order = GC.Orders:GetOrder(orderID)
    if not order then
        return
    end
    local rest = math.max(0, (order.actualCost or 0) - (order.reimbursedPaid or 0))
    dialog.orderID = orderID
    dialog.caption:SetText("Offen sind " .. GC.Orders.FormatMoney(rest)
        .. ". Betrag in Gold (Teilzahlungen sind erlaubt):")
    dialog.amountEdit:SetText(tostring(math.floor(rest / 10000)))
    dialog:Show()
end

-- Die Wunsch-Hersteller-Liste im Erstellen-Dialog: "(keiner)" plus die
-- bekannten Hersteller des Rezepts aus dem Katalog.
function GC.UI:ToggleOrderCrafterList(dialog)
    local list = dialog.crafterList
    if list:IsShown() then
        list:Hide()
        return
    end
    local names = { "" }
    for _, crafterName in ipairs(dialog.recipeCrafters or {}) do
        names[#names + 1] = crafterName
    end
    local visible = math.min(#names, #list.rows)
    for index, rowButton in ipairs(list.rows) do
        local name = names[index]
        rowButton.crafterName = name
        local label = name and (name ~= "" and GC.Util.PlayerIdentityName(name) or "(keiner)") or ""
        -- Einen gesperrten Hersteller darf man weiterhin waehlen - er ist ja
        -- 24 Stunden reserviert und wird bis dahin oft frei. Aber man soll es
        -- wissen, bevor man ihn waehlt, nicht danach.
        if name and name ~= "" then
            local readyAt = GC.Workshop:GetRecipeCooldown(dialog.recipeKey, name)
            if readyAt then
                label = label .. "  |cffffb840" .. FormatCooldownReady(readyAt) .. "|r"
            end
        end
        rowButton:SetText(label)
        rowButton:SetShown(index <= visible)
    end
    list:SetHeight(8 + (visible * 24))
    list:Show()
end

-- Der vorbelegte Übergabetext: {name} wird zum Empfänger, {rezept} zum
-- Rezept. Anpassbar in den Einstellungen; gesendet wird erst mit Enter.
function GC.UI:BuildOrderWhisper(order)
    if not order then
        return nil, nil
    end
    local target = GC.Orders:GetCounterpartCharacter(order)
    if not target then
        return nil, nil
    end
    local text = GC.DB:GetSettings().orderWhisperText or ""
    text = text:gsub("{name}", GC.Util.PlayerIdentityName(target))
        :gsub("{rezept}", order.recipeName or "?")
    return target, text
end

-- Das Chatfenster mit der Gegenseite und dem Übergabetext vorbelegen
-- (Stufe 2). Ohne Chat-API (Tests) bleibt es beim Hinweis mit dem Namen.
function GC.UI:WhisperOrderCounterpart(orderID)
    local order = GC.Orders:GetOrder(orderID)
    local target, text = self:BuildOrderWhisper(order)
    if not target then
        self:SetOrdersStatus("Kein Charakter der Gegenseite bekannt.", false)
        return false, ""
    end
    if ChatFrame_OpenChat then
        ChatFrame_OpenChat("/w " .. target .. " " .. (text or ""), DEFAULT_CHAT_FRAME)
        return true, ""
    end
    self:SetOrdersStatus("Gegenseite: " .. GC.Util.PlayerIdentityName(target), true)
    return true, ""
end

-- Auftragsstatistik: erledigte Aufträge je Hersteller, erstellte je
-- Auftraggeber. Auf Owner-Wunsch trotz des Konzept-Vorbehalts (sozialer
-- Druck) eingebaut.
function GC.UI:BuildOrderStatsDialog(page)
    local dialog = BuildOrderDialogFrame(page, 400, 360, "Auftragsstatistik")
    page.orderStatsDialog = dialog
    dialog.body = CreateLabel(dialog, "", { width = 364, height = 290, vertical = "TOP" })
    dialog.body:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -42)
end

function GC.UI:OpenOrderStatsDialog()
    local page = self.pages.WORKSHOP
    local dialog = page and page.orderStatsDialog
    if not dialog then
        return
    end
    local stats = GC.Orders:GetStats()
    local names = {}
    local merged = {}
    local function Bucket(map, field)
        for name, count in pairs(map or {}) do
            if not merged[name] then
                merged[name] = { fulfilled = 0, created = 0, items = 0, ordered = 0 }
                names[#names + 1] = name
            end
            merged[name][field] = count
        end
    end
    Bucket(stats.byCrafter, "fulfilled")
    Bucket(stats.byCreator, "created")
    Bucket(stats.itemsByCrafter, "items")
    Bucket(stats.itemsByCreator, "ordered")
    table.sort(names, function(left, right)
        if merged[left].items ~= merged[right].items then
            return merged[left].items > merged[right].items
        end
        if merged[left].fulfilled ~= merged[right].fulfilled then
            return merged[left].fulfilled > merged[right].fulfilled
        end
        return left < right
    end)
    local lines = {}
    local totalOrders, totalItems = 0, 0
    for index = 1, #names do
        local entry = merged[names[index]]
        totalOrders = totalOrders + entry.fulfilled
        totalItems = totalItems + entry.items
        if index <= 14 then
            -- Stücke stehen vorn: Vierzig Urnen und ein Ring waren als
            -- „1 erledigt" bisher nicht zu unterscheiden.
            lines[#lines + 1] = names[index] .. "  –  |cff59e695" .. entry.items
                .. " Stück|r · " .. entry.fulfilled .. " erledigt · "
                .. entry.created .. " erstellt"
        end
    end
    if #lines > 0 then
        table.insert(lines, 1, "Insgesamt |cff59e695" .. totalItems .. " Stück|r aus "
            .. totalOrders .. " abgeschlossenen Aufträgen.\n")
        -- Ehrlich bleiben statt schön aussehen: Was vor 0.9.110 abgeschlossen
        -- wurde, ist als Auftrag gezählt, aber nie als Stückzahl - eine 0
        -- neben vier erledigten Aufträgen wäre sonst ein Rätsel.
        if totalItems < totalOrders then
            lines[#lines + 1] = "\nStückzahlen zählt Guild Copilot seit Version 0.9.110;"
                .. " ältere Aufträge stehen nur mit ihrer Anzahl darin."
        end
    end
    dialog.body:SetText(#lines > 0 and table.concat(lines, "\n")
        or "Noch keine abgeschlossenen Aufträge gezählt.")
    dialog:Show()
end

function GC.UI:BuildOrderAcceptDialog(page)
    local dialog = BuildOrderDialogFrame(page, 360, 216, "Wer fertigt?")
    page.orderAcceptDialog = dialog
    dialog.caption = CreateLabel(dialog,
        "Mehrere deiner Charaktere beherrschen das Rezept.",
        { muted = true, width = 324, height = 16 })
    dialog.caption:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -42)
    dialog.candidateButtons = {}
    for index = 1, 4 do
        local button = CreateButton(dialog, "", 200, 24, function()
            local chosen = dialog.candidateButtons[index].crafterName
            if chosen then
                dialog.selectedCrafter = chosen
                for _, sibling in ipairs(dialog.candidateButtons) do
                    sibling:SetActive(sibling.crafterName == chosen)
                end
            end
        end)
        button:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -64 - ((index - 1) * 26))
        button:Hide()
        dialog.candidateButtons[index] = button
    end
    dialog.submit = CreateButton(dialog, "Annehmen", 120, 30, function()
        local ok, message = GC.Orders:Accept(dialog.orderID, dialog.selectedCrafter)
        GC.UI:SetOrdersStatus(message, ok)
        if ok then
            dialog:Hide()
        end
    end, "PRIMARY")
    dialog.submit:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 16, 14)
end

function GC.UI:OpenOrderAcceptDialog(orderID, candidates)
    local page = self.pages.WORKSHOP
    local dialog = page and page.orderAcceptDialog
    if not dialog then
        return
    end
    dialog.orderID = orderID
    dialog.selectedCrafter = candidates[1]
    for index, button in ipairs(dialog.candidateButtons) do
        local name = candidates[index]
        button.crafterName = name
        button:SetText(name and GC.Util.PlayerIdentityName(name) or "")
        button:SetShown(name ~= nil)
        button:SetActive(name == dialog.selectedCrafter)
    end
    dialog:Show()
end

-- === Kompakt-Tracker ========================================================
-- Frei verschiebbarer Mini-Rahmen nach dem Muster des Werbebalkens: bis zu
-- drei "du bist dran"-Zeilen, Klick öffnet die Werkstatt am Auftragsboard.
-- Er zeigt sich nur, wenn es etwas zu tun gibt (Owner-Entscheidung: Stufe 1).

function GC.UI:CreateOrderTracker()
    if self.orderTracker then
        return self.orderTracker
    end
    local tracker = CreatePanel(UIParent, THEME.window, THEME.accent, "GuildCopilotForeverOrderTracker")
    tracker:SetSize(344, 118)
    local settings = GC.DB:GetSettings().orderTracker
    tracker:SetPoint("CENTER", UIParent, "CENTER", tonumber(settings.x) or 0, tonumber(settings.y) or -300)
    tracker:SetClampedToScreen(true)
    tracker:SetMovable(true)
    tracker:EnableMouse(true)
    tracker:RegisterForDrag("LeftButton")
    tracker:SetScript("OnDragStart", tracker.StartMoving)
    tracker:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, _, x, y = frame:GetPoint()
        if point then
            GC.DB:GetSettings().orderTracker.x = math.floor(tonumber(x) or 0)
            GC.DB:GetSettings().orderTracker.y = math.floor(tonumber(y) or 0)
        end
    end)
    tracker:SetFrameStrata("MEDIUM")
    tracker:Hide()

    -- Kopfzeile: Der Schließen-Knopf steht in derselben Spalte wie die Zeilen
    -- darunter (12 px Rand, vorher 8) und liegt mittig zum Titel statt drei
    -- Pixel tiefer. Der Titel bekommt dafür feste Maße - ohne sie wächst er
    -- mit seinem Text („… (4)") bis unter den Knopf.
    tracker.title = CreateLabel(tracker, "Gildenaufträge",
        { font = "GameFontNormalSmall", width = 282, height = 20 })
    tracker.title:SetPoint("TOPLEFT", tracker, "TOPLEFT", 12, -7)
    tracker.close = CreateButton(tracker, "×", 20, 20, function()
        GC.DB:GetSettings().orderTracker.hidden = true
        GC.UI:RefreshOrderTracker()
    end)
    tracker.close:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -12, -7)

    -- Zwei Zeilen je Auftrag: Rezept oben, Aufgabe gedämpft darunter. In
    -- einer Zeile wurde die Aufgabe abgeschnitten ("Materialien an … li…").
    tracker.rows = {}
    for index = 1, 3 do
        local row = CreateButton(tracker, "", 320, 40, function()
            GC.UI:CreateMainFrame()
            GC.UI.frame:Show()
            GC.UI:ShowPage("WORKSHOP")
            GC.UI:SetWorkshopView("ORDERS")
        end)
        row:SetPoint("TOPLEFT", tracker, "TOPLEFT", 12, -28 - ((index - 1) * 44))
        -- Die Beschriftung eines Knopfes ist auf ganze Knopfhöhe angelegt und
        -- steht darin senkrecht mittig - für einen gewöhnlichen Knopf genau
        -- richtig. Hier trägt der Knopf zwei Zeilen, und ein Anker oben allein
        -- half nichts: Ein zweiter Anker "RIGHT" legt zusätzlich die Mitte auf
        -- die Knopfmitte, und dorthin rutschte der Rezeptname - mitten in die
        -- Aufgabenzeile darunter. Deshalb eigene Höhe für die obere Zeile und
        -- beide Anker oben, damit keiner die Senkrechte zurückholt.
        row.label:ClearAllPoints()
        row.label:SetHeight(16)
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -4)
        row.label:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -4)
        row.label:SetJustifyH("LEFT")
        if row.label.SetWordWrap then
            row.label:SetWordWrap(false)
        end
        if row.label.SetMaxLines then
            row.label:SetMaxLines(1)
        end
        row.action = CreateLabel(row, "", {
            muted = true,
            font = "GameFontNormalSmall",
            width = 304,
            height = 14,
        })
        row.action:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -22)
        if row.action.SetWordWrap then
            row.action:SetWordWrap(false)
        end
        if row.action.SetMaxLines then
            row.action:SetMaxLines(1)
        end
        row:Hide()
        tracker.rows[index] = row
    end

    -- Eine Zeile für die beiden Fälle, in denen unter den Aufträgen noch etwas
    -- zu sagen bleibt: gar nichts offen, oder mehr Aufträge als Plätze. Ihren
    -- Ort bekommt sie beim Zeichnen - er hängt an der Zahl der Zeilen darüber.
    tracker.note = CreateLabel(tracker, "", {
        muted = true,
        font = "GameFontNormalSmall",
        width = 304,
        height = 16,
    })
    tracker.note:Hide()

    self.orderTracker = tracker
    return tracker
end

-- Bis 0.9.118 zeigte sich der Tracker nur mit "du bist dran"-Zeilen und
-- verschwand sonst. Aus dem Spiel gemeldet: Er war weg, obwohl ein Auftrag
-- lief - er wartete nur gerade auf den Auftraggeber. Ein Fenster, das ohne
-- Zutun kommt und geht, ist kein Fenster, das man im Blick behält.
--
-- Es bleibt deshalb stehen (Owner-Entscheidung) und zeigt alles Laufende, an
-- dem dieser Account beteiligt ist: die eigenen Aufgaben oben, darunter
-- gedämpft, worauf gewartet wird. Weg ist es nur über das ×.
function GC.UI:RefreshOrderTracker()
    local settings = GC.DB:GetSettings().orderTracker
    if settings.hidden then
        if self.orderTracker then
            self.orderTracker:Hide()
        end
        return
    end

    -- GetBoard sortiert "du bist dran" bereits nach oben, danach nach
    -- Änderungszeit - die drei Plätze zeigen also immer das Dringendste.
    local rows = {}
    local turns = 0
    if GC.Orders then
        for _, boardRow in ipairs(GC.Orders:GetBoard().mine) do
            rows[#rows + 1] = boardRow
            if boardRow.yourTurn then
                turns = turns + 1
            end
        end
    end

    local tracker = self:CreateOrderTracker()
    local visible = 0
    for index, row in ipairs(tracker.rows) do
        local boardRow = rows[index]
        if boardRow then
            local order = boardRow.order
            local name = (order.recipeName or "?") .. " ×" .. (order.quantity or 1)
            if boardRow.yourTurn then
                row:SetText(name)
                row.action:SetText(boardRow.action or "")
            else
                -- Gedämpft, weil hier nichts zu tun ist. Der Farbcode steht im
                -- Text und nicht an der Beschriftung: Ein Knopf setzt seine
                -- Textfarbe zurück, sobald die Maus ihn wieder verlässt.
                row:SetText("|cff91a3b8" .. name .. "|r")
                local waitingFor = boardRow.actor == "CREATOR"
                    and order.createdBy or order.crafter
                if GC.Util.Trim(waitingFor) == "" then
                    -- Ein offener Auftrag wartet auf niemand Bestimmten; die
                    -- Ansage dafür steht schon in der Zeile selbst.
                    row.action:SetText(boardRow.action or "")
                else
                    row.action:SetText(GC.LFormat("Wartet auf {name}.",
                        { name = GC.Util.PlayerIdentityName(waitingFor) }))
                end
            end
            row:Show()
            visible = visible + 1
        else
            row:Hide()
        end
    end

    if turns > 0 then
        tracker.title:SetText(GC.LFormat("Gildenaufträge – du bist dran ({n})",
            { n = turns }))
    else
        tracker.title:SetText(GC.L("Gildenaufträge"))
    end

    -- Die Fußzeile sagt, was die drei Plätze nicht zeigen können: dass gar
    -- nichts läuft, oder dass noch etwas darunter liegt.
    local noteShown = true
    if #rows == 0 then
        tracker.note:SetText(GC.L("Zurzeit ist nichts offen."))
    elseif #rows > visible then
        tracker.note:SetText(GC.LFormat("… und {n} weitere.", { n = #rows - visible }))
    else
        noteShown = false
    end
    tracker.note:ClearAllPoints()
    tracker.note:SetPoint("TOPLEFT", tracker, "TOPLEFT", 20, -32 - (visible * 44))
    if noteShown then
        tracker.note:Show()
    else
        tracker.note:Hide()
    end

    -- Der Rahmen ist so hoch wie sein Inhalt: Titelzeile, sichtbare Zeilen,
    -- gegebenenfalls die Fußzeile. Leere Plätze vorzuhalten sah nach kaputtem
    -- Fenster aus.
    tracker:SetHeight(34 + (visible * 44) + (noteShown and 20 or 0) + 4)
    tracker:Show()
end

function GC.UI:ToggleOrderTracker()
    local settings = GC.DB:GetSettings().orderTracker
    settings.hidden = not settings.hidden
    self:RefreshOrderTracker()
    self:RefreshOrdersBoard()
end

-- === Handelsfenster-Helfer ==================================================
--
-- Idee aus Pro Enchanters, umgesetzt fuers Auftragsboard: In TBC werden
-- Verzauberungen im HANDELSFENSTER gewirkt, und auch Uebergaben laufen dort.
-- Beginnt ein Handel mit jemandem, mit dem Auftraege offen sind, steht
-- daneben, worum es geht - samt derselben Primaeraktion wie auf dem Board.
-- Nichts passiert von selbst: Kein Status wechselt ohne Klick, und im Kampf
-- erscheint der Helfer gar nicht erst.
function GC.UI:CreateTradeBanner()
    if self.tradeBanner then
        return self.tradeBanner
    end
    local banner = CreatePanel(UIParent, THEME.window, THEME.accent, "GuildCopilotForeverTradeBanner")
    banner:SetSize(344, 118)
    banner:SetFrameStrata("MEDIUM")
    banner:Hide()
    banner.title = CreateLabel(banner, "Gildenaufträge",
        { font = "GameFontNormalSmall", width = 320, height = 20 })
    banner.title:SetPoint("TOPLEFT", banner, "TOPLEFT", 12, -7)
    banner.rows = {}
    for index = 1, 3 do
        local row = CreateFrame("Frame", nil, banner)
        row:SetSize(320, 40)
        row:SetPoint("TOPLEFT", banner, "TOPLEFT", 12, -28 - ((index - 1) * 44))
        row.label = CreateLabel(row, "", { width = 190, height = 40, vertical = "TOP" })
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -3)
        row.action = CreateButton(row, "", 118, 30, function()
            if row.run and row.orderID then
                local ok, message = row.run(row.orderID)
                if ok == false and message and message ~= "" then
                    GC:Print("|cffff5555" .. tostring(message) .. "|r")
                end
                GC.UI:RefreshTradeBanner()
            end
        end)
        row.action:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -3)
        banner.rows[index] = row
    end
    self.tradeBanner = banner
    return banner
end

function GC.UI:ShowTradeBanner()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return
    end
    -- Der Handelspartner steht in WoW an der NPC-Unit - so benennt der
    -- Client nun einmal das Gegenueber eines Handels.
    local partner = type(UnitName) == "function"
        and (UnitName("NPC") or UnitName("npc")) or nil
    if GC.Util.Trim(partner) == "" then
        return
    end
    self.tradePartner = partner
    self:RefreshTradeBanner()
end

function GC.UI:RefreshTradeBanner()
    local partner = self.tradePartner
    if not partner then
        return
    end
    local orders = GC.Orders and GC.Orders.GetOrdersWithCounterpart
        and GC.Orders:GetOrdersWithCounterpart(partner) or {}
    if #orders == 0 then
        if self.tradeBanner then
            self.tradeBanner:Hide()
        end
        return
    end
    local banner = self:CreateTradeBanner()
    banner.title:SetText("Gildenaufträge mit " .. GC.Util.PlayerIdentityName(partner))
    local visible = 0
    for index, row in ipairs(banner.rows) do
        local order = orders[index]
        if order then
            row.label:SetText((order.recipeName or "?") .. " ×" .. (order.quantity or 1)
                .. "\n" .. ColoredOrderStatus(order))
            local actionLabel, run = OrderPrimaryAction(order)
            row.orderID = order.id
            row.run = run
            row.action:SetText(actionLabel or "")
            row.action:SetShown(run ~= nil)
            row:Show()
            visible = visible + 1
        else
            row:Hide()
        end
    end
    banner:SetHeight(34 + (visible * 44) + 4)
    banner:ClearAllPoints()
    if TradeFrame then
        banner:SetPoint("TOPLEFT", TradeFrame, "TOPRIGHT", 6, -12)
    else
        banner:SetPoint("LEFT", UIParent, "LEFT", 340, 80)
    end
    banner:Show()
end

function GC.UI:HideTradeBanner()
    self.tradePartner = nil
    if self.tradeBanner then
        self.tradeBanner:Hide()
    end
end

local tradeEvents = CreateFrame("Frame")
tradeEvents:RegisterEvent("TRADE_SHOW")
tradeEvents:RegisterEvent("TRADE_CLOSED")
tradeEvents:SetScript("OnEvent", function(_, event)
    if event == "TRADE_SHOW" then
        GC.UI:ShowTradeBanner()
    elseif event == "TRADE_CLOSED" then
        GC.UI:HideTradeBanner()
    end
end)

-- === Bildschirmmeldung ======================================================
-- Eine eigene, gut lesbare Raidwarnung für neue machbare Gildenaufträge -
-- ohne Hintergrundkasten, mit dicker Kontur und Schatten für den Kontrast.
-- Sie steht drei Sekunden und verblasst dann; kommen mehrere Meldungen,
-- rückt Älteres wie beim Scrolling Combat Text nach oben und verblasst dort.
-- Der Kasten erscheint nur im Positionier-Modus ("Meldung testen" in den
-- Einstellungen), damit sich der Anker mit der Maus greifen lässt.
local BANNER_FADE_SECONDS = 1.5
local BANNER_LINES = 3
local BANNER_LINE_HEIGHT = 34

-- Die Standdauer kommt aus den Einstellungen (1 bis 30 Sekunden). Gelesen
-- wird sie je Tick - ein Tabellenzugriff, und Änderungen greifen sofort.
local function BannerHoldSeconds()
    local value = tonumber(GC.DB:GetSettings().orderBanner.holdSeconds) or 3
    return math.max(1, math.min(30, value))
end

function GC.UI:CreateOrderBanner()
    if self.orderBanner then
        return self.orderBanner
    end
    local settings = GC.DB:GetSettings().orderBanner
    local banner = CreatePanel(UIParent, THEME.window, THEME.accent, "GuildCopilotForeverOrderBanner")
    banner:SetSize(640, BANNER_LINES * BANNER_LINE_HEIGHT)
    banner:SetPoint("CENTER", UIParent, "CENTER",
        tonumber(settings.x) or 0, tonumber(settings.y) or 200)
    banner:SetFrameStrata("HIGH")
    banner:SetClampedToScreen(true)
    banner:SetMovable(true)
    banner:RegisterForDrag("LeftButton")
    banner:SetScript("OnDragStart", banner.StartMoving)
    banner:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, _, x, y = frame:GetPoint()
        if point then
            GC.DB:GetSettings().orderBanner.x = math.floor(tonumber(x) or 0)
            GC.DB:GetSettings().orderBanner.y = math.floor(tonumber(y) or 0)
        end
    end)

    function banner:SetPositioning(active)
        self.positioning = active == true
        self:EnableMouse(self.positioning)
        if self.positioning then
            self:SetBackdropColor(THEME.window[1], THEME.window[2], THEME.window[3], 0.85)
            self:SetBackdropBorderColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
        else
            self:SetBackdropColor(0, 0, 0, 0)
            self:SetBackdropBorderColor(0, 0, 0, 0)
        end
    end
    banner:SetPositioning(false)

    banner.lines = {}
    for index = 1, BANNER_LINES do
        local line = CreateLabel(banner, "", {
            font = "GameFontNormalHuge",
            align = "CENTER",
            width = 640,
            height = BANNER_LINE_HEIGHT,
        })
        -- Neues erscheint unten am Anker, Älteres rückt nach oben.
        line:SetPoint("BOTTOM", banner, "BOTTOM", 0, (index - 1) * BANNER_LINE_HEIGHT)
        SetTextColor(line, THEME.accent)
        if line.GetFont and line.SetFont then
            local fontPath, fontSize = line:GetFont()
            if fontPath then
                line:SetFont(fontPath, fontSize or 20, "THICKOUTLINE")
            end
        end
        if line.SetShadowOffset then
            line:SetShadowOffset(2, -2)
        end
        if line.SetShadowColor then
            line:SetShadowColor(0, 0, 0, 0.9)
        end
        line.age = nil
        line:Hide()
        banner.lines[index] = line
    end

    -- Die dünnen Linien über und unter der Meldung - die klassische
    -- Raidwarnungs-Optik, nur ohne Kasten. Sie verblassen mit der Meldung.
    banner.rules = {}
    for index, offset in ipairs({ 0, BANNER_LINE_HEIGHT }) do
        local rule = banner:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(1)
        rule:SetPoint("BOTTOMLEFT", banner, "BOTTOMLEFT", 40, offset)
        rule:SetPoint("BOTTOMRIGHT", banner, "BOTTOMRIGHT", -40, offset)
        if rule.SetColorTexture then
            rule:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.9)
        end
        rule:Hide()
        banner.rules[index] = rule
    end

    banner:SetScript("OnUpdate", function(frame, elapsed)
        elapsed = tonumber(elapsed) or 0
        local hold = BannerHoldSeconds()
        local anyActive = false
        for _, line in ipairs(frame.lines) do
            if line.age then
                line.age = line.age + elapsed
                if line.age >= hold + BANNER_FADE_SECONDS then
                    line.age = nil
                    line:Hide()
                elseif line.age > hold then
                    if line.SetAlpha then
                        line:SetAlpha(math.max(0,
                            1 - ((line.age - hold) / BANNER_FADE_SECONDS)))
                    end
                    anyActive = true
                else
                    if line.SetAlpha then
                        line:SetAlpha(1)
                    end
                    anyActive = true
                end
            end
        end
        -- Die Linien folgen der jüngsten Zeile: Sie ist immer die letzte, die
        -- verblasst, also tragen die Linien schlicht deren Deckkraft.
        local newest = frame.lines[1]
        local ruleAlpha = 0
        if newest.age then
            ruleAlpha = newest.age <= hold and 1
                or math.max(0, 1 - ((newest.age - hold) / BANNER_FADE_SECONDS))
        end
        for _, rule in ipairs(frame.rules) do
            rule:SetShown(ruleAlpha > 0)
            if rule.SetAlpha then
                rule:SetAlpha(ruleAlpha)
            end
        end
        if not anyActive then
            frame:SetPositioning(false)
            frame:Hide()
        end
    end)

    banner:Hide()
    self.orderBanner = banner
    return banner
end

function GC.UI:ShowOrderBanner(text, positioning)
    if GC.DB:GetSettings().orderBanner.enabled == false and not positioning then
        return
    end
    local banner = self:CreateOrderBanner()
    local lines = banner.lines
    text = text or ""

    -- Gleiche Meldung, solange die alte noch steht: hochzählen statt
    -- stapeln. "Neuer Gildenauftrag ×3" sagt mehr als drei identische Zeilen.
    if lines[1].age and lines[1].baseText == text then
        lines[1].repeatCount = (lines[1].repeatCount or 1) + 1
        lines[1]:SetText(text .. "  ×" .. lines[1].repeatCount)
        lines[1].age = 0
        if lines[1].SetAlpha then
            lines[1]:SetAlpha(1)
        end
        banner:Show()
        return
    end

    -- Ältere Zeilen eine Position nach oben schieben, die neue kommt unten an.
    for index = #lines, 2, -1 do
        local line = lines[index]
        local below = lines[index - 1]
        line:SetText(below:GetText() or "")
        line.age = below.age
        line.baseText = below.baseText
        line.repeatCount = below.repeatCount
        line:SetShown(line.age ~= nil)
    end
    lines[1]:SetText(text)
    lines[1].baseText = text
    lines[1].repeatCount = 1
    lines[1].age = 0
    if lines[1].SetAlpha then
        lines[1]:SetAlpha(1)
    end
    lines[1]:Show()
    if positioning then
        banner:SetPositioning(true)
    end
    banner:Show()
end

function GC.UI:BuildRecruitmentPage()
    local page = self.pages.RECRUITMENT
    CreatePageTitle(page, "Klassen & Specs", "Klassen öffnen, Bedarf auswählen und die Reihenfolge rechts nach Priorität sortieren.")

    local listCard = CreateCard(page)
    listCard:SetSize(486, 490)
    listCard:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -66)

    local scroll = CreateModernScrollFrame(listCard)
    scroll:SetPoint("TOPLEFT", listCard, "TOPLEFT", 12, -12)
    scroll:SetPoint("BOTTOMRIGHT", listCard, "BOTTOMRIGHT", -18, 12)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(432)
    content:SetHeight(456)
    scroll:SetScrollChild(content)
    page.classContent = content
    page.classRows = {}

    for _, classFile in ipairs(GC.ClassOrder) do
        local currentClass = classFile
        local classInfo = GC.Classes[classFile]
        local row = CreateFrame("Frame", nil, content)
        row:SetWidth(428)
        row.header = CreateButton(row, "", 428, 42, function()
            if page.expandedClass == currentClass then
                page.expandedClass = nil
            else
                page.expandedClass = currentClass
            end
            GC.UI:RefreshRecruitment()
        end)
        row.header:SetPoint("TOPLEFT")
        row.header.label:ClearAllPoints()
        row.header.label:SetPoint("LEFT", row.header, "LEFT", 52, 0)
        row.header.label:SetJustifyH("LEFT")
        row.header.icon = row.header:CreateTexture(nil, "ARTWORK")
        row.header.icon:SetSize(28, 28)
        row.header.icon:SetPoint("LEFT", row.header, "LEFT", 12, 0)
        SetClassIcon(row.header.icon, classFile)
        row.header.arrow = CreateLabel(row.header, "+", { title = true, align = "CENTER" })
        row.header.arrow:SetPoint("RIGHT", row.header, "RIGHT", -14, 1)
        row.header.count = CreateLabel(row.header, "", { muted = true, align = "RIGHT", width = 150 })
        row.header.count:SetPoint("RIGHT", row.header, "RIGHT", -42, 0)

        row.details = CreatePanel(row, THEME.input)
        row.details:SetPoint("TOPLEFT", row.header, "BOTTOMLEFT", 0, -4)
        row.details:SetSize(428, 88)

        row.classChoice = CreateButton(row.details, "Ganze Klasse", 116, 30, function()
            GC.Recruitment:SetClass(currentClass, not GC.Recruitment:IsClassSelected(currentClass))
            GC.UI:RefreshRecruitment()
        end)
        row.classChoice:SetPoint("TOPLEFT", row.details, "TOPLEFT", 12, -12)

        row.specButtons = {}
        for index, spec in ipairs(classInfo.specs) do
            local specKey = spec.key
            local button = CreateButton(row.details, spec.name, 126, 30, function()
                GC.Recruitment:SetSpec(specKey, not GC.Recruitment:IsSpecSelected(specKey))
                GC.UI:RefreshRecruitment()
            end)
            button:SetPoint("BOTTOMLEFT", row.details, "BOTTOMLEFT", 12 + ((index - 1) * 134), 10)
            row.specButtons[spec.key] = button
        end
        page.classRows[classFile] = row
    end

    local summaryCard = CreateCard(page, "Deine Suche")
    summaryCard:SetSize(270, 490)
    summaryCard:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -66)
    page.selectionCount = CreateLabel(summaryCard, "0 AUSGEWÄHLT", { muted = true })
    page.selectionCount:SetPoint("TOPLEFT", summaryCard, "TOPLEFT", 18, -49)
    page.priorityRows = {}
    for index = 1, 9 do
        local rowIndex = index
        local priorityRow = CreatePanel(summaryCard, THEME.input)
        priorityRow:SetSize(234, 31)
        priorityRow:SetPoint("TOPLEFT", summaryCard, "TOPLEFT", 18, -72 - ((index - 1) * 34))
        priorityRow.name = CreateLabel(priorityRow, "", { width = 112 })
        priorityRow.name:SetPoint("LEFT", priorityRow, "LEFT", 8, 0)
        priorityRow.priority = CreateButton(priorityRow, "Prio", 48, 25, function()
            local classFile = page.priorityRows[rowIndex].classFile
            if classFile then
                GC.Recruitment:SetPriority(classFile, not GC.Recruitment:IsHighPriority(classFile))
                GC.UI:RefreshRecruitment()
            end
        end)
        priorityRow.priority:SetPoint("LEFT", priorityRow, "LEFT", 116, 0)
        priorityRow.up = CreateButton(priorityRow, "^", 27, 25, function()
            local classFile = page.priorityRows[rowIndex].classFile
            if classFile then
                GC.Recruitment:MoveSelectedClass(classFile, -1)
                GC.UI:RefreshRecruitment()
            end
        end)
        priorityRow.up:SetPoint("LEFT", priorityRow.priority, "RIGHT", 4, 0)
        priorityRow.down = CreateButton(priorityRow, "v", 27, 25, function()
            local classFile = page.priorityRows[rowIndex].classFile
            if classFile then
                GC.Recruitment:MoveSelectedClass(classFile, 1)
                GC.UI:RefreshRecruitment()
            end
        end)
        priorityRow.down:SetPoint("LEFT", priorityRow.up, "RIGHT", 4, 0)
        page.priorityRows[index] = priorityRow
    end

    page.emptySelectionText = CreateLabel(summaryCard,
        "Noch nichts gewählt.\n\nLinks eine Klasse öffnen und ganze Klasse oder Specs auswählen.",
        { muted = true, width = 234, height = 110, vertical = "TOP" })
    page.emptySelectionText:SetPoint("TOPLEFT", summaryCard, "TOPLEFT", 18, -77)

    local clear = CreateButton(summaryCard, "Auswahl leeren", 234, 34, function()
        GC.Recruitment:Clear()
        GC.UI:RefreshRecruitment()
    end)
    clear:SetPoint("BOTTOMLEFT", summaryCard, "BOTTOMLEFT", 18, 64)

    local continue = CreateButton(summaryCard, "Werbetext erstellen  >", 234, 38, function()
        local guildData = GC.DB:GetGuild()
        guildData.recruitment.adText = GC.Recruitment:GenerateAdvertisement()
        GC.UI:ShowPage("POST")
    end, "PRIMARY")
    continue:SetPoint("BOTTOMLEFT", summaryCard, "BOTTOMLEFT", 18, 16)
end

function GC.UI:RefreshRecruitment()
    local page = self.pages.RECRUITMENT
    if not page then
        return
    end

    local y = 0
    for _, classFile in ipairs(GC.ClassOrder) do
        local row = page.classRows[classFile]
        local classInfo = GC.Classes[classFile]
        local expanded = page.expandedClass == classFile
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", page.classContent, "TOPLEFT", 0, -y)
        row:SetHeight(expanded and 136 or 46)
        row.details:SetShown(expanded)
        row.header:SetText(classInfo.plural)
        row.header:SetActive(expanded)
        row.header.arrow:SetText(expanded and "-" or "+")
        row.classChoice:SetActive(GC.Recruitment:IsClassSelected(classFile))
        local selectedSpecs = 0
        for _, spec in ipairs(classInfo.specs) do
            local selected = GC.Recruitment:IsSpecSelected(spec.key)
            row.specButtons[spec.key]:SetActive(selected)
            if selected then
                selectedSpecs = selectedSpecs + 1
            end
        end
        if GC.Recruitment:IsClassSelected(classFile) then
            row.header.count:SetText(GC.L("ganze Klasse"))
        elseif selectedSpecs > 0 then
            row.header.count:SetText(selectedSpecs .. " Specs")
        else
            row.header.count:SetText(GC.L(""))
        end
        local red, green, blue = ClassColor(classFile)
        row.header.label:SetTextColor(red, green, blue)
        y = y + (expanded and 142 or 48)
    end
    page.classContent:SetHeight(math.max(456, y))

    local orderedClasses = GC.Recruitment:GetClassOrder()
    local selectedClasses = {}
    local selectedClassCount = 0
    for _, classFile in ipairs(orderedClasses) do
        local label = GC.Recruitment:GetClassSelectionLabel(classFile, true)
        if label then
            selectedClassCount = selectedClassCount + 1
            selectedClasses[#selectedClasses + 1] = classFile
        end
    end
    page.selectionCount:SetText(selectedClassCount .. " KLASSEN AUSGEWÄHLT")
    page.emptySelectionText:SetShown(selectedClassCount == 0)
    for index, priorityRow in ipairs(page.priorityRows) do
        local classFile = selectedClasses[index]
        priorityRow:SetShown(classFile ~= nil)
        priorityRow.classFile = classFile
        if classFile then
            local classInfo = GC.Classes[classFile]
            local red, green, blue = ClassColor(classFile)
            priorityRow.name:SetText(classInfo.plural)
            priorityRow.name:SetTextColor(red, green, blue)
            local highPriority = GC.Recruitment:IsHighPriority(classFile)
            priorityRow.priority:SetText(highPriority and "HOCH" or "Prio")
            priorityRow.priority:SetActive(highPriority)
            if index == 1 then
                priorityRow.up:Disable()
            else
                priorityRow.up:Enable()
            end
            if index == selectedClassCount then
                priorityRow.down:Disable()
            else
                priorityRow.down:Enable()
            end
        end
    end
end

-- Beide Automatik-Schalter (Postseite und Werbebalken) erklaeren sich im
-- Tooltip. Die Regeln stehen nur hier, damit die beiden Orte nie
-- Verschiedenes behaupten.
local function AttachAutoRepeatTooltip(toggle)
    toggle:HookScript("OnEnter", function(self)
        if not AnchorRowTooltip(self) then
            return
        end
        GameTooltip:SetText(GC.L("Automatisch wiederholen"))
        GameTooltip:AddLine("Wiederholt die bestätigte Werbung von selbst,"
            .. " solange der Werbebalken eingeblendet ist.", 1, 1, 1, true)
        GameTooltip:AddLine("WoW verlangt für jede Kanalnachricht eine echte Eingabe."
            .. " Sobald ein Kanal-Cooldown abläuft, geht der Text deshalb mit deinem"
            .. " nächsten Tastendruck raus – gleich welche Taste, auch beim Laufen.", 0.31, 0.79, 1, true)
        GameTooltip:AddLine("Bestätigungspflicht und Cooldowns gelten unverändert."
            .. " Balken geschlossen = Automatik pausiert."
            .. " Welche Taste du drückst, liest Guild Copilot nicht.", 1, 0.72, 0.25, true)
        GameTooltip:Show()
    end)
    toggle:HookScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
end

function GC.UI:BuildPostPage()
    local page = self.pages.POST
    CreatePageTitle(page, "Werbung posten", "Text prüfen, bestätigen und mit einem echten Klick in die ausgewählten Kanäle senden"
        .. " — oder die Automatik postet mit dem nächsten Tastendruck, sobald ein Kanal bereit ist.")

    local editorCard = CreateCard(page, "Werbetext")
    editorCard:SetSize(776, 246)
    editorCard:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -66)
    page.adEdit = CreateTextArea(editorCard, 740, 132, 500)
    page.adEdit.container:SetPoint("TOPLEFT", editorCard, "TOPLEFT", 18, -48)
    page.adEdit:SetScript("OnTextChanged", function(edit)
        GC.DB:GetGuild().recruitment.adText = edit:GetText()
        if page.searchButton then
            page.searchButton:Disable()
        end
        GC.UI:RefreshPostCounter()
    end)

    local markerLabel = CreateLabel(editorCard, "Raid-Symbol", { muted = true })
    markerLabel:SetPoint("TOPLEFT", editorCard, "TOPLEFT", 386, -19)
    page.raidMarkerButtons = {}
    for markerIndex = 1, 8 do
        local selectedMarker = markerIndex
        local markerButton = CreateRaidMarkerButton(editorCard, markerIndex, function()
            local recruitment = GC.DB:GetGuild().recruitment
            recruitment.raidMarker = selectedMarker
            recruitment.adText = GC.Recruitment:GenerateAdvertisement()
            recruitment.confirmedText = nil
            page.adEdit:SetText(recruitment.adText)
            page.postResult:SetText(GC.L("Raid-Symbol geändert. Bitte den Text erneut bestätigen."))
            SetTextColor(page.postResult, THEME.warning)
            GC.UI:RefreshPost()
        end)
        markerButton:SetPoint("TOPLEFT", editorCard, "TOPLEFT", 475 + ((markerIndex - 1) * 34), -13)
        page.raidMarkerButtons[markerIndex] = markerButton
    end
    page.byteCounter = CreateLabel(editorCard, "", { muted = true, align = "RIGHT", width = 150 })
    page.byteCounter:SetPoint("BOTTOMRIGHT", editorCard, "BOTTOMRIGHT", -18, 14)

    local regenerate = CreateButton(editorCard, "Neu generieren", 142, 32, function()
        page.adEdit:SetText(GC.Recruitment:GenerateAdvertisement())
    end)
    regenerate:SetPoint("BOTTOMLEFT", editorCard, "BOTTOMLEFT", 18, 12)
    page.confirmAdButton = CreateButton(editorCard, "Text bestätigen", 152, 32, function()
        local text = GC.Util.SafeChatText(page.adEdit:GetText())
        page.adEdit:SetText(text)
        if text == "" then
            GC.DB:GetGuild().recruitment.confirmedText = nil
            page.postResult:SetText(GC.L("Ein leerer Werbetext kann nicht bestätigt werden."))
            SetTextColor(page.postResult, THEME.danger)
            GC.UI:RefreshPost()
            return
        end
        GC.DB:GetGuild().recruitment.confirmedText = text
        page.postResult:SetText(GC.L("Werbetext bestätigt und bereit."))
        SetTextColor(page.postResult, THEME.success)
        GC.UI:RefreshPost()
    end, "PRIMARY")
    page.confirmAdButton:SetPoint("LEFT", regenerate, "RIGHT", 8, 0)

    local channelCard = CreateCard(page, "Kanäle")
    channelCard:SetSize(776, 155)
    channelCard:SetPoint("TOPLEFT", editorCard, "BOTTOMLEFT", 0, -12)
    page.channelChecks = {}
    for index, kind in ipairs({ "RECRUITMENT", "LFG", "TRADE", "GENERAL" }) do
        local channelKind = kind
        local toggle = CreateToggle(channelCard, GC.ChannelKinds[kind].label, function(enabled)
            GC.DB:GetSettings().channels[channelKind] = enabled
            GC.UI:RefreshPostStatus()
        end)
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        toggle:SetPoint("TOPLEFT", channelCard, "TOPLEFT", 18 + (column * 270), -49 - (row * 38))
        page.channelChecks[kind] = toggle
    end
    page.channelStatus = CreateLabel(channelCard, "", { muted = true, width = 220, height = 82, vertical = "TOP" })
    page.channelStatus:SetPoint("TOPRIGHT", channelCard, "TOPRIGHT", -18, -49)

    page.searchButton = CreateButton(page, "Suche starten", 210, 44, function()
        local success, message = GC.Chat:StartSearch(page.adEdit:GetText())
        page.postResult:SetText(message or "")
        SetTextColor(page.postResult, success and THEME.success or THEME.danger)
        GC.UI:RefreshPost()
    end, "PRIMARY")
    -- Die Rueckmeldung stand rechts neben dem Werbebalken-Knopf und wurde
    -- uebersehen - wer ohne bestaetigten Text auf "Suche starten" klickte,
    -- bekam scheinbar keinen Hinweis. Jetzt steht sie in voller Breite direkt
    -- unter dem Knopf, auf den man gerade geklickt hat. 44 statt 26, damit
    -- darunter zwei volle Zeilen Platz haben: Ohne den Abstand schob sich die
    -- zweizeilige Automatik-Erklaerung von ihrem unteren Anker nach oben
    -- unter die Knopfreihe (Owner-Screenshot).
    page.searchButton:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 44)
    page.postBarToggle = CreateButton(page, "Werbebalken", 150, 44, function()
        GC.UI:TogglePostBar()
        GC.UI:RefreshPost()
    end)
    page.postBarToggle:SetPoint("LEFT", page.searchButton, "RIGHT", 12, 0)

    -- Der Automatik-Schalter steht neben dem Werbebalken-Knopf, zu dem er
    -- gehoert; derselbe Schalter sitzt auch im Balken selbst. Die Rueckmeldung
    -- darunter erklaert beim Umschalten, was ab jetzt passiert.
    page.autoRepeatToggle = CreateToggle(page, "Automatisch wiederholen", function(enabled)
        GC.UI:SetAutoRepeat(enabled)
        if enabled then
            page.postResult:SetText(GC.L("Automatik an: Der Werbebalken bleibt offen; sobald ein Kanal bereit ist,"
                .. " postet dein nächster Tastendruck."))
            SetTextColor(page.postResult, THEME.success)
        else
            page.postResult:SetText(GC.L("Automatik aus: Gepostet wird nur noch per Klick."))
            SetTextColor(page.postResult, THEME.muted)
        end
    end)
    page.autoRepeatToggle:SetPoint("LEFT", page.postBarToggle, "RIGHT", 16, 0)
    AttachAutoRepeatTooltip(page.autoRepeatToggle)

    -- Feste Hoehe und vertical = TOP: Die Rueckmeldung ist ein Kasten fuer
    -- genau zwei Zeilen und laeuft nach unten, nie in die Knoepfe darueber.
    page.postResult = CreateLabel(page, "", { width = 776, height = 34, vertical = "TOP" })
    page.postResult:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 4)

    page:SetScript("OnUpdate", function(_, elapsed)
        page.elapsed = (page.elapsed or 0) + elapsed
        if page.elapsed >= 0.5 then
            page.elapsed = 0
            GC.UI:RefreshPostStatus()
        end
    end)
end

function GC.UI:RefreshPostCounter()
    local page = self.pages.POST
    if not page then
        return
    end
    local bytes = #(page.adEdit:GetText() or "")
    page.byteCounter:SetText(bytes .. "/" .. GC.Constants.MAX_CHAT_BYTES .. " Bytes")
    SetTextColor(page.byteCounter, bytes > GC.Constants.MAX_CHAT_BYTES and THEME.danger or THEME.muted)
end

function GC.UI:RefreshPostStatus()
    local page = self.pages.POST
    if not page or not page:IsShown() then
        return
    end
    local statuses = {}
    for _, kind in ipairs({ "RECRUITMENT", "LFG", "TRADE", "GENERAL" }) do
        if GC.DB:GetSettings().channels[kind] then
            local channelID = GC.Chat:FindChannel(kind)
            local status = channelID and "bereit" or "nicht beigetreten"
            local remaining = GC.Chat:GetRemainingCooldown(kind)
            if remaining > 0 then
                status = math.ceil(remaining) .. "s Cooldown"
            end
            statuses[#statuses + 1] = GC.ChannelKinds[kind].label .. ": " .. status
        end
    end
    page.channelStatus:SetText(#statuses > 0 and table.concat(statuses, "\n") or "Keine Kanäle ausgewählt.")
end

function GC.UI:RefreshPost()
    local page = self.pages.POST
    if not page then
        return
    end
    if page.postBarToggle then
        local visible = GC.DB:GetSettings().postBar.hidden == false
        page.postBarToggle:SetActive(visible)
        page.postBarToggle:SetText(visible and "Balken aus" or "Werbebalken")
    end
    if page.autoRepeatToggle then
        SetToggle(page.autoRepeatToggle, GC.DB:GetSettings().postBar.autoRepeat == true)
    end
    local recruitment = GC.DB:GetGuild().recruitment
    if not recruitment.adText or recruitment.adText == "" then
        recruitment.adText = GC.Recruitment:GenerateAdvertisement()
    end
    if not page.adEdit:HasFocus() and page.adEdit:GetText() ~= recruitment.adText then
        page.adEdit:SetText(recruitment.adText)
    end
    for kind, toggle in pairs(page.channelChecks) do
        SetToggle(toggle, GC.DB:GetSettings().channels[kind])
    end
    local marker = math.floor(tonumber(recruitment.raidMarker) or 8)
    for markerIndex, markerButton in ipairs(page.raidMarkerButtons) do
        markerButton:SetActive(markerIndex == marker)
    end
    local isConfirmed = recruitment.confirmedText == page.adEdit:GetText()
        and GC.Util.Trim(recruitment.confirmedText or "") ~= ""
    if isConfirmed then
        page.searchButton:Enable()
    else
        page.searchButton:Disable()
    end
    page.searchButton:SetActive(isConfirmed)
    self:RefreshPostCounter()
    self:RefreshPostStatus()
end

-- So viele Interessenten passen auf eine Seite der Liste. Die Zahl steht hier
-- einmal, damit Aufbau, Blaettern und Auffrischen nie auseinanderlaufen.
--
-- Acht statt neun seit den Filtern: Die Filterzeile braucht den Platz einer
-- Zeile. Die Karte ist 224 Pixel breit und sitzt buendig neben der
-- Unterhaltung - breiter geht sie nicht, und geblaettert wird ohnehin.
local LEADS_PER_PAGE = 8
local LEADS_TOP = -82

-- Passt das Gildenprofil noch durch den Gildenkanal? Jede Stelle, die etwas
-- gildenweit Synchronisiertes speichert, muss das fragen, BEVOR sie Erfolg
-- meldet - sonst steht "synchronisiert" da, waehrend der verzoegerte Sender
-- die Nutzlast danach ablehnt. Die Antwort ist nil, wenn alles passt.
function GC.UI:GuildProfileTooLargeMessage()
    local bytes, maximum, tooLarge = GC.Sync:GetGuildProfileSize()
    if not tooLarge then
        return nil
    end
    return "Lokal gespeichert, aber NICHT gildenweit verteilt: "
        .. bytes .. " von höchstens " .. maximum .. " Zeichen. "
        .. "Bitte Texte, Antwortvorlagen oder Verzauberungsregeln kürzen."
end

function GC.UI:BuildInboxPage()
    local page = self.pages.INBOX
    local _, captureHelp = CreatePageTitle(page, "Postfach", GC.Chat:GetCaptureStatus())
    page.captureHelp = captureHelp

    local scroll = CreateModernScrollFrame(page)
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -58)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -4, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(752)
    content:SetHeight(1030)
    scroll:SetScrollChild(content)
    page.inboxScroll = scroll

    local leadCard = CreateCard(content, "Interessenten")
    leadCard:SetSize(224, 554)
    leadCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    page.leadButtons = {}
    page.leadDeleteButtons = {}
    page.leadPage = 1

    -- === Filterzeile ======================================================
    --
    -- Zwei schmale Aufklappfelder nebeneinander. Sie filtern die ANSICHT;
    -- gespeichert und gildenweit geteilt bleibt alles.
    local classOptions = { "Alle Klassen" }
    local classByLabel = {}
    for _, classFile in ipairs(GC.ClassOrder or {}) do
        local label = GC.Classes[classFile] and GC.Classes[classFile].name or classFile
        classOptions[#classOptions + 1] = label
        classByLabel[label] = classFile
    end
    page.leadClassFilter = CreateChoiceDropdown(leadCard, 90, classOptions, function(value)
        local filters = GC.UI:GetInboxFilters()
        filters.classFile = classByLabel[value] or ""
        page.leadPage = 1
        GC.UI:RefreshInbox()
    end, true, nil, nil, 24)
    page.leadClassFilter:SetPoint("TOPLEFT", leadCard, "TOPLEFT", 18, -48)
    page.leadClassByLabel = classByLabel

    -- Die Stufe kommt aus dem Text des Bewerbers ("70er Schurke", "Stufe 70").
    -- Deshalb sind die Stufen hier Schwellen und keine Einzelwerte: Wer "68"
    -- schreibt, soll bei "ab 60" auftauchen.
    local LEVEL_OPTIONS = {
        { label = "Alle Stufen", value = 0 },
        { label = "Ab Stufe " .. GC.Client.maxLevel, value = GC.Client.maxLevel },
        { label = "Ab Stufe 60", value = 60 },
        { label = "Ab Stufe 50", value = 50 },
    }
    local levelLabels, levelByLabel = {}, {}
    for _, option in ipairs(LEVEL_OPTIONS) do
        levelLabels[#levelLabels + 1] = option.label
        levelByLabel[option.label] = option.value
    end
    page.leadLevelFilter = CreateChoiceDropdown(leadCard, 90, levelLabels, function(value)
        local filters = GC.UI:GetInboxFilters()
        filters.minLevel = levelByLabel[value] or 0
        page.leadPage = 1
        GC.UI:RefreshInbox()
    end, true, nil, nil, 24)
    page.leadLevelFilter:SetPoint("LEFT", page.leadClassFilter, "RIGHT", 8, 0)
    page.leadLevelOptions = LEVEL_OPTIONS

    -- Sagt, wie viel gerade nicht zu sehen ist. Ein vergessener Filter sieht
    -- sonst aus wie ein leeres Postfach.
    page.leadFilterNotice = CreateLabel(leadCard, "", {
        muted = true, font = "GameFontNormalSmall", width = 188,
    })
    page.leadFilterNotice:SetPoint("BOTTOMLEFT", leadCard, "BOTTOMLEFT", 18, 48)

    for index = 1, LEADS_PER_PAGE do
        local slot = index
        local button = CreateButton(leadCard, "", 148, 38, function()
            GC.UI:SelectLead(GC.UI:GetLeadIndexForSlot(slot))
        end)
        button:SetPoint("TOPLEFT", leadCard, "TOPLEFT", 18, LEADS_TOP - ((index - 1) * 43))
        button.label:SetJustifyH("LEFT")
        button.label:ClearAllPoints()
        button.label:SetPoint("LEFT", button, "LEFT", 12, 0)
        page.leadButtons[index] = button
        local remove = CreateButton(leadCard, "×", 34, 38, function()
            local leadIndex = GC.UI:GetLeadIndexForSlot(slot)
            local removed = GC.DB:GetGuild().inbox[leadIndex]
            local removedKey = removed and GC.Util.NormalizeName(removed.name)
            if GC.Chat:RemoveLead(leadIndex) then
                if removedKey then
                    page.replyDrafts[removedKey] = nil
                    -- Die Auswahl haengt am Namen: Wer jemand anderen gewaehlt
                    -- hatte, behaelt ihn ohne Zutun. Nur wenn der Geloeschte
                    -- selbst gewaehlt war, muss ein neuer her.
                    if GC.UI.selectedLeadKey == removedKey then
                        local inbox = GC.DB:GetGuild().inbox
                        local following = inbox[math.min(leadIndex, #inbox)]
                        GC.UI.selectedLeadKey = following
                            and GC.Util.NormalizeName(following.name) or nil
                        GC.UI:LoadLeadDraft()
                    end
                end
                GC.UI:RefreshInbox()
            end
        end)
        remove:SetPoint("LEFT", button, "RIGHT", 6, 0)
        remove.label:SetTextColor(THEME.danger[1], THEME.danger[2], THEME.danger[3], 1)
        page.leadDeleteButtons[index] = remove
    end

    -- Ab dem zehnten Interessenten war der Rest bisher unerreichbar: Es gab
    -- weder eine Seitennavigation noch einen Hinweis, und einzeln loeschen liess
    -- sich nur, was auf der ersten Seite stand.
    page.leadPrev = CreateButton(leadCard, "", 34, 26, function()
        page.leadPage = math.max(1, (page.leadPage or 1) - 1)
        GC.UI:RefreshInbox()
    end)
    SetButtonMark(page.leadPrev, CreateArrowMark(page.leadPrev, 13, "LEFT"))
    page.leadPrev:SetPoint("TOPLEFT", leadCard, "TOPLEFT", 18, -444)
    page.leadPageLabel = CreateLabel(leadCard, "", { muted = true, width = 108, align = "CENTER" })
    page.leadPageLabel:SetPoint("LEFT", page.leadPrev, "RIGHT", 6, 0)
    page.leadNext = CreateButton(leadCard, "", 34, 26, function()
        page.leadPage = (page.leadPage or 1) + 1
        GC.UI:RefreshInbox()
    end)
    SetButtonMark(page.leadNext, CreateArrowMark(page.leadNext, 13, "RIGHT"))
    page.leadNext:SetPoint("LEFT", page.leadPageLabel, "RIGHT", 6, 0)
    page.clearInboxButton = CreateButton(leadCard, "Alle löschen", 188, 30, function()
        if not page.confirmClearInbox then
            page.confirmClearInbox = true
            page.clearInboxButton:SetText(GC.L("Löschen bestätigen"))
            return
        end
        if GC.Chat:ClearInbox() then
            GC.UI.selectedLeadKey = nil
            page.leadPage = 1
            page.replyDrafts = {}
            page.replyEdit:SetText(GC.L(""))
            page.replyResult:SetText(GC.L("Postfach vollständig geleert."))
            SetTextColor(page.replyResult, THEME.muted)
        end
        page.confirmClearInbox = false
        page.clearInboxButton:SetText(GC.L("Alle löschen"))
        GC.UI:RefreshInbox()
    end)
    page.clearInboxButton:SetPoint("BOTTOMLEFT", leadCard, "BOTTOMLEFT", 18, 14)

    local detailCard = CreateCard(content, "Unterhaltung")
    detailCard:SetSize(528, 554)
    detailCard:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    page.leadTitle = CreateLabel(detailCard, "Kein Bewerber ausgewählt", { title = true })
    page.leadTitle:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, -51)
    page.lastMessage = CreateLabel(detailCard, "", { width = 504, height = 52, vertical = "TOP" })
    page.lastMessage:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, -86)

    -- Zwei fertige Profil-Links zum Nachschlagen des Interessenten. WoW kann
    -- keinen Browser oeffnen und nichts in die Zwischenablage legen, deshalb
    -- sind es Textfelder: hineinklicken markiert den ganzen Link, Strg+C
    -- kopiert ihn. Tippen stellt den Link wieder her, damit niemand versehentlich
    -- einen halben Link kopiert.
    page.leadLinkEdits = {}
    local linkDefinitions = {
        { key = "armory", label = "Armory", y = -142 },
        { key = "logs", label = "Logs", y = -170 },
    }
    for _, definition in ipairs(linkDefinitions) do
        local label = CreateLabel(detailCard, definition.label, { muted = true, width = 62 })
        label:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, definition.y)
        local edit = CreateEdit(detailCard, 424, 24)
        edit.container:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 86, definition.y + 2)
        edit:SetScript("OnEditFocusGained", function(self)
            self:HighlightText()
        end)
        edit:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                self:SetText(self.linkValue or "")
                self:HighlightText()
            end
        end)
        edit:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        page.leadLinkEdits[definition.key] = edit
    end
    page.leadLinkNotice = CreateLabel(detailCard, "", { muted = true, width = 492, height = 14 })
    page.leadLinkNotice:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, -196)

    local previewLabel = CreateLabel(detailCard, "Antwortvorschau  •  editierbar", { muted = true })
    previewLabel:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, -209)

    local markerLabel = CreateLabel(detailCard, "Symbole", { muted = true })
    markerLabel:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, -238)
    page.replyMarkerOff = CreateButton(detailCard, "Aus", 45, 26, function()
        local recruitment = GC.DB:GetGuild().recruitment
        recruitment.replyMarker = 0
        page.replyEdit:SetText(GC.Recruitment:DecorateReply(page.replyEdit:GetText(), 0))
        GC.UI:RefreshInbox()
    end)
    page.replyMarkerOff:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 92, -229)
    page.replyMarkerButtons = {}
    for markerIndex = 1, 8 do
        local selectedMarker = markerIndex
        local markerButton = CreateRaidMarkerButton(detailCard, markerIndex, function()
            local recruitment = GC.DB:GetGuild().recruitment
            recruitment.replyMarker = selectedMarker
            page.replyEdit:SetText(GC.Recruitment:DecorateReply(page.replyEdit:GetText(), selectedMarker))
            GC.UI:RefreshInbox()
        end)
        markerButton:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 146 + ((markerIndex - 1) * 30), -229)
        page.replyMarkerButtons[markerIndex] = markerButton
    end

    page.replyEdit = CreateTextArea(detailCard, 504, 104, 500)
    page.replyEdit.container:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, -263)
    page.replyByteCounter = CreateLabel(detailCard, "0/255 Bytes", { muted = true, align = "RIGHT", width = 110 })
    page.replyByteCounter:SetPoint("TOPRIGHT", detailCard, "TOPRIGHT", -18, -374)
    -- Jeder Entwurf gehoert zu genau einem Interessenten. Frueher blieb der Text
    -- beim Wechsel stehen, waehrend der Senden-Knopf schon den neu gewaehlten
    -- Spieler meinte - ein persoenlich formulierter Entwurf fuer A konnte so an
    -- B gehen. Gemerkt wird nach Namen, nicht nach Listenplatz: Der verschiebt
    -- sich, sobald ein Eintrag geloescht oder ausgeblendet wird.
    page.replyDrafts = {}
    page.replyEdit:SetScript("OnTextChanged", function(edit)
        local text = edit:GetText() or ""
        local bytes = #text
        page.replyByteCounter:SetText(bytes .. "/" .. GC.Constants.MAX_CHAT_BYTES .. " Bytes")
        SetTextColor(page.replyByteCounter, bytes > GC.Constants.MAX_CHAT_BYTES and THEME.danger or THEME.muted)
        local key = page.replyDraftKey
        if key then
            page.replyDrafts[key] = text
        end
    end)

    -- Ein Sync oder eine spaete GUID-Antwort kann die Auswahl zwischen zwei
    -- Zeichenvorgaengen aendern. Eine Aktion gilt nur dem angezeigten Empfaenger.
    local function SelectedLeadForAction()
        local lead, _, key = GC.UI:GetSelectedLead()
        if key ~= page.replyDraftKey then
            GC.UI:RefreshInbox()
            return nil
        end
        return lead
    end
    local thanks = CreateButton(detailCard, "Danke", 105, 30, function()
        local lead = SelectedLeadForAction()
        if lead then
            page.replyEdit:SetText(GC.Recruitment:GenerateReply("THANKS", lead.name))
        end
    end)
    thanks:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, -386)
    local info = CreateButton(detailCard, "Gildeninfos", 115, 30, function()
        local lead = SelectedLeadForAction()
        if lead then
            page.replyEdit:SetText(GC.Recruitment:GenerateReply("INFO", lead.name))
        end
    end)
    info:SetPoint("LEFT", thanks, "RIGHT", 8, 0)
    page.infoReplyButton = info
    local discord = CreateButton(detailCard, "Discord", 105, 30, function()
        local lead = SelectedLeadForAction()
        if lead then
            page.replyEdit:SetText(GC.Recruitment:GenerateReply("DISCORD", lead.name))
        end
    end)
    discord:SetPoint("LEFT", info, "RIGHT", 8, 0)
    page.discordReplyButton = discord

    page.replyButton = CreateButton(detailCard, "Antworten", 248, 38, function()
        local lead = SelectedLeadForAction()
        local sent, reason
        if lead then sent, reason = GC.Chat:SendReply(lead.name, page.replyEdit:GetText()) end
        if sent then
            -- Verschickt ist verschickt: Der Entwurf hat seinen Zweck erfuellt
            -- und darf nicht beim naechsten Aufruf wieder dastehen.
            page.replyDrafts[GC.Util.NormalizeName(lead.name)] = nil
            page.replyEdit:SetText(GC.L(""))
            page.replyResult:SetText("Antwort an " .. lead.name .. " an den Client übergeben.")
            SetTextColor(page.replyResult, THEME.success)
        else
            page.replyResult:SetText(reason or GC.L("Bitte Interessent und Antwort auswählen."))
            SetTextColor(page.replyResult, THEME.danger)
        end
        GC.UI:RefreshInbox()
    end, "PRIMARY")
    page.replyButton:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, -430)

    page.inviteButton = CreateButton(detailCard, "In Gilde einladen", 248, 38, function()
        local lead = SelectedLeadForAction()
        if lead then
            local invited = GC.Chat:Invite(lead.name)
            page.replyResult:SetText(invited and ("Einladung an " .. lead.name .. " ausgelöst.")
                or GC.L("Einladung konnte nicht ausgelöst werden."))
            SetTextColor(page.replyResult, invited and THEME.success or THEME.danger)
        end
    end)
    page.inviteButton:SetPoint("LEFT", page.replyButton, "RIGHT", 8, 0)
    page.replyResult = CreateLabel(detailCard, "", { width = 492, height = 20, vertical = "TOP" })
    page.replyResult:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, -476)

    -- Wer immer wieder schreibt, ohne dass etwas daraus wird, laesst sich
    -- ausblenden. Befristet oder dauerhaft; zuruecknehmen geht in der Liste
    -- unter den Vorlagen.
    local function FilterSelectedLead(days)
        local lead = SelectedLeadForAction()
        if not lead then
            page.replyResult:SetText(GC.L("Kein Interessent ausgewählt."))
            SetTextColor(page.replyResult, THEME.danger)
            return
        end
        local ok, message = GC.Chat:SetInboxFilter(lead.name, days)
        page.replyResult:SetText(message or "")
        SetTextColor(page.replyResult, ok and THEME.success or THEME.danger)
        page.replyDrafts[GC.Util.NormalizeName(lead.name)] = nil
        -- Kein SetText("") vor LoadLeadDraft: Das Leeren feuert OnTextChanged,
        -- und das schreibt den leeren Text dem dann schon gewaehlten NAECHSTEN
        -- Interessenten zu. Dessen gemerkter Entwurf waere weg, bevor
        -- LoadLeadDraft ihn ueberhaupt holt.
        GC.UI.selectedLeadKey = nil
        page.leadPage = 1
        GC.UI:LoadLeadDraft()
        GC.UI:RefreshInbox()
    end

    page.hideTempButton = CreateButton(detailCard, "7 Tage ausblenden", 248, 34, function()
        FilterSelectedLead(7)
    end)
    page.hideTempButton:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, -502)

    page.hideForeverButton = CreateButton(detailCard, "Dauerhaft ignorieren", 248, 34, function()
        FilterSelectedLead(0)
    end)
    page.hideForeverButton:SetPoint("LEFT", page.hideTempButton, "RIGHT", 8, 0)

    -- Die Vorlagen hinter den drei Knoepfen werden dort gepflegt, wo sie
    -- benutzt werden, nicht in den Einstellungen.
    local templateCard = CreateCard(content, "Vorlagen für Danke, Gildeninfos und Discord")
    templateCard:SetSize(752, 244)
    templateCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -566)
    local templateHelp = CreateLabel(templateCard,
        "Diese Texte füllen die drei Knöpfe oben. Sie gelten gildenweit. Platzhalter: {name}, {gilde}, {beschreibung}, {raidzeiten}, {progress}, {loot}, {discord}, {kontakt}.",
        { muted = true, width = 716, height = 30, vertical = "TOP" })
    templateHelp:SetPoint("TOPLEFT", templateCard, "TOPLEFT", 18, -44)

    page.templateEdits = {}
    local templateDefinitions = {
        { key = "THANKS", label = "Danke", y = -82 },
        { key = "INFO", label = "Gildeninfos", y = -124 },
        { key = "DISCORD", label = "Discord", y = -166 },
    }
    for _, definition in ipairs(templateDefinitions) do
        local label = CreateLabel(templateCard, definition.label, { muted = true, width = 100 })
        label:SetPoint("TOPLEFT", templateCard, "TOPLEFT", 18, definition.y)
        local edit = CreateEdit(templateCard, 590, 32)
        edit.container:SetPoint("TOPLEFT", templateCard, "TOPLEFT", 134, definition.y + 6)
        page.templateEdits[definition.key] = edit
    end

    page.saveTemplates = CreateButton(templateCard, "Vorlagen speichern", 180, 32, function()
        if not GC.Roster:CanEditGuildProfile() then
            page.templateStatus:SetText(GC.L("Dein Gildenrang darf die gildenweiten Vorlagen nicht bearbeiten."))
            SetTextColor(page.templateStatus, THEME.danger)
            return
        end
        local guildData = GC.DB:GetGuild()
        for key, edit in pairs(page.templateEdits) do
            guildData.replyTemplates[key] = GC.Util.Trim(edit:GetText())
        end
        guildData.profile.updatedAt = GC.Util.Now()

        local tooLarge = GC.UI:GuildProfileTooLargeMessage()
        if tooLarge then
            GC:FireCallback("GUILD_PROFILE_UPDATED")
            page.templateStatus:SetText(tooLarge)
            SetTextColor(page.templateStatus, THEME.danger)
            return
        end

        GC.Sync:QueueGuildProfile(true)
        GC:FireCallback("GUILD_PROFILE_UPDATED")
        page.templateStatus:SetText(GC.L("Vorlagen gespeichert und für die Gilde synchronisiert."))
        SetTextColor(page.templateStatus, THEME.success)
    end, "PRIMARY")
    page.saveTemplates:SetPoint("BOTTOMLEFT", templateCard, "BOTTOMLEFT", 134, 14)
    page.templateStatus = CreateLabel(templateCard, "", { width = 420 })
    page.templateStatus:SetPoint("LEFT", page.saveTemplates, "RIGHT", 14, 0)

    local filterCard = CreateCard(content, "Ausgeblendete Spieler")
    filterCard:SetSize(752, 196)
    filterCard:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -822)
    local filterHelp = CreateLabel(filterCard,
        "Von diesen Spielern landet nichts mehr im Postfach. Befristete Einträge verschwinden"
        .. " von selbst, sobald das Datum erreicht ist. Die Liste gilt nur für dich.",
        { muted = true, width = 716, height = 30, vertical = "TOP" })
    filterHelp:SetPoint("TOPLEFT", filterCard, "TOPLEFT", 18, -44)

    page.filterRows = {}
    for index = 1, 4 do
        local rowIndex = index
        local row = CreatePanel(filterCard, index % 2 == 0 and THEME.input or THEME.cardHover)
        row:SetSize(716, 26)
        row:SetPoint("TOPLEFT", filterCard, "TOPLEFT", 18, -82 - ((index - 1) * 28))
        row.name = CreateLabel(row, "", { width = 200, height = 26 })
        row.name:SetPoint("LEFT", row, "LEFT", 9, 0)
        row.until_ = CreateLabel(row, "", { muted = true, width = 340, height = 26 })
        row.until_:SetPoint("LEFT", row, "LEFT", 217, 0)
        row.clear = CreateButton(row, "Wieder zulassen", 150, 22, function()
            local entry = page.filterEntries and page.filterEntries[rowIndex]
            if entry and GC.Chat:ClearInboxFilter(entry.key) then
                GC.UI:RefreshInbox()
            end
        end)
        row.clear:SetPoint("RIGHT", row, "RIGHT", -9, 0)
        page.filterRows[index] = row
    end
    page.filterNotice = CreateLabel(filterCard, "", { muted = true, width = 716, height = 20 })
    page.filterNotice:SetPoint("BOTTOMLEFT", filterCard, "BOTTOMLEFT", 18, 12)
end

-- Welcher Interessent steht auf Listenplatz "slot" der aktuellen Seite?
-- === Filter im Postfach ====================================================
--
-- Gefiltert wird die ANSICHT, nicht der Bestand: Ein ausgeblendeter Eintrag
-- bleibt gespeichert und wird weiterhin gildenweit geteilt. Sonst waere ein
-- Filter ein Loeschknopf mit freundlichem Namen.
--
-- Die Klasse steht nur an Eintraegen, deren GUID der Client aufloesen konnte
-- (ResolveLeadClass). Wo sie fehlt, wird der Eintrag von einem Klassenfilter
-- NICHT verborgen - "unbekannt" ist keine Aussage ueber die Klasse, und wer
-- filtert, will nicht heimlich Bewerber verlieren.
function GC.UI:GetInboxFilters()
    local settings = GC.DB:GetSettings()
    if type(settings.inboxFilters) ~= "table" then
        settings.inboxFilters = {}
    end
    local filters = settings.inboxFilters
    if not GC.Classes[filters.classFile or ""] then filters.classFile = "" end
    local level = tonumber(filters.minLevel) or 0
    filters.minLevel = (level == 50 or level == 60 or level == 70) and level or 0
    return settings.inboxFilters
end

function GC.UI:LeadMatchesInboxFilter(lead)
    if type(lead) ~= "table" then
        return false
    end
    local filters = self:GetInboxFilters()

    local class = GC.Util.Trim(filters.classFile)
    if class ~= "" and lead.classFile ~= class then
        return false
    end

    -- Eine unbekannte Stufe erfuellt keine Mindeststufe. Ohne Filter bleiben
    -- diese Bewerber sichtbar; die Daten selbst werden nie geloescht.
    local minLevel = tonumber(filters.minLevel) or 0
    local level = tonumber(lead.level)
    if minLevel > 0 and (not level or level < minLevel or level > GC.LeadLevelMax) then
        return false
    end
    return true
end

-- Wann an einem Eintrag zuletzt etwas passiert ist - der Zeitpunkt, nach dem das
-- Postfach sortiert wird. lastSeenAt ist der belastbare Wert: Er faehrt im Sync
-- mit und wird beim Zusammenfuehren als der SPAETERE der beiden Staende
-- uebernommen (MergeRemoteLead). Er zeigt damit die echte gildenweite Aktivitaet
-- des Bewerbers, nicht den Zeitpunkt, zu dem eine Sync-Kopie hier eintraf. Fehlt
-- er (Altbestand), treten die letzte Nachricht und schliesslich die
-- Ersterfassung an seine Stelle.
local function LeadActivityTime(lead)
    if type(lead) ~= "table" then
        return 0
    end
    local newest = tonumber(lead.lastSeenAt) or 0
    local messages = lead.messages
    if type(messages) == "table" then
        local latest = messages[#messages]
        if type(latest) == "table" then
            newest = math.max(newest, tonumber(latest.receivedAt) or 0)
        end
    end
    return math.max(newest, tonumber(lead.firstSeenAt) or 0)
end

-- Die echten Postfachplaetze, die gerade sichtbar sind - nach Datum sortiert.
-- Die zuletzt aktive Bewerbung steht oben, damit auf einen Blick sichtbar ist,
-- was aktuell ist; Veraltetes sinkt nach unten, wo es sich wegloeschen laesst.
-- Frueher stand hier die Einfuegereihenfolge, und ausgerechnet eine per Sync
-- nachgereichte, TAGE alte Bewerbung wird ganz vorn eingefuegt (MergeRemoteLead)
-- und sass damit oben, als waere sie das Neueste.
--
-- Sortiert werden die INDIZES, aufgeloest wird ueber den echten Eintrag: Alles
-- Weitere rechnet mit dem ECHTEN Index - Bloettern, Auswaehlen und Loeschen -,
-- sonst loescht ein Klick den falschen. Bei gleichem Zeitpunkt entscheidet der
-- kleinere Index, damit die Liste bei jedem Auffrischen ruhig stehen bleibt.
function GC.UI:GetVisibleLeadIndexes()
    local inbox = GC.DB:GetGuild().inbox
    local visible = {}
    for index, lead in ipairs(inbox) do
        GC.Chat:RefreshLeadDetails(lead)
        if self:LeadMatchesInboxFilter(lead) then
            visible[#visible + 1] = index
        end
    end
    table.sort(visible, function(a, b)
        local ta, tb = LeadActivityTime(inbox[a]), LeadActivityTime(inbox[b])
        if ta ~= tb then
            return ta > tb
        end
        return a < b
    end)
    return visible
end

-- Beschriftung der beiden Aufklappfelder und die Auskunft, wie viel der Filter
-- gerade verbirgt. Ohne die Zahl wirkt ein vergessener Filter wie ein leeres
-- Postfach - das ist die haeufigste Verwechslung bei Filtern ueberhaupt.
function GC.UI:RefreshInboxFilterControls(visibleCount, totalCount)
    local page = self.pages.INBOX
    if not page or not page.leadClassFilter then
        return
    end
    local filters = self:GetInboxFilters()

    local classLabel = "Alle Klassen"
    for label, classFile in pairs(page.leadClassByLabel or {}) do
        if classFile == filters.classFile then
            classLabel = label
        end
    end
    page.leadClassFilter:SetValue(classLabel)

    local levelLabel = "Alle Stufen"
    for _, option in ipairs(page.leadLevelOptions or {}) do
        if option.value == (tonumber(filters.minLevel) or 0) then
            levelLabel = option.label
        end
    end
    page.leadLevelFilter:SetValue(levelLabel)

    local hidden = (tonumber(totalCount) or 0) - (tonumber(visibleCount) or 0)
    if hidden > 0 then
        page.leadFilterNotice:SetText(GC.LFormat("{n} durch Filter ausgeblendet", { n = hidden }))
        SetTextColor(page.leadFilterNotice, THEME.warning)
    else
        page.leadFilterNotice:SetText("")
    end
end

function GC.UI:GetLeadIndexForSlot(slot)
    local page = self.pages.INBOX
    local leadPage = (page and page.leadPage) or 1
    local position = ((leadPage - 1) * LEADS_PER_PAGE) + slot
    local references = page and page.visibleLeadRefs
    if references then
        local displayed = references[position]
        for index, lead in ipairs(GC.DB:GetGuild().inbox) do
            if lead == displayed then return index end
        end
        return nil
    end
    local visible = page and page.visibleLeads
    if not visible then
        return position
    end
    return visible[position]
end

-- Der gewaehlte Interessent, gesucht ueber seinen Namen statt ueber einen
-- Listenplatz. Ist er verschwunden (geloescht, ausgeblendet, zusammengefuehrt),
-- ruecken wir auf den ersten Eintrag - aber ausdruecklich erst DANN, nicht bei
-- jeder Verschiebung der Liste.
--
-- Zurueckgegeben werden Eintrag, Listenplatz und Schluessel; der Listenplatz
-- wird nur zum Zeichnen gebraucht und nie gespeichert.
function GC.UI:GetSelectedLead(visible)
    local inbox = GC.DB:GetGuild().inbox
    visible = visible or self:GetVisibleLeadIndexes()
    if self.selectedLeadKey then
        for _, index in ipairs(visible) do
            local lead = inbox[index]
            if GC.Util.NormalizeName(lead.name) == self.selectedLeadKey then
                return lead, index, self.selectedLeadKey
            end
        end
    end
    local firstIndex = visible[1]
    local first = firstIndex and inbox[firstIndex]
    if not first then
        self.selectedLeadKey = nil
        return nil, nil, nil
    end
    self.selectedLeadKey = GC.Util.NormalizeName(first.name)
    return first, firstIndex, self.selectedLeadKey
end

-- Der Schluessel, unter dem der Entwurf des gewaehlten Interessenten liegt.
-- Nil heisst: gar niemand gewaehlt, dann gehoert der Text niemandem.
function GC.UI:GetSelectedLeadKey()
    local _, _, key = self:GetSelectedLead()
    return key
end

-- Holt den gemerkten Entwurf des gewaehlten Interessenten ins Feld.
function GC.UI:LoadLeadDraft()
    local page = self.pages.INBOX
    if not page or not page.replyEdit then
        return
    end
    page.replyEdit:ClearFocus()
    local key = self:GetSelectedLeadKey()
    page.replyDraftKey = key
    -- SetText loest OnTextChanged aus und schriebe den Text sofort wieder in
    -- den Speicher. Das ist hier derselbe Schluessel und damit folgenlos - bei
    -- einem Wechsel waere es das nicht, deshalb laeuft jeder Wechsel ueber
    -- SelectLead und niemals ueber ein nacktes SetText.
    page.replyEdit:SetText((key and page.replyDrafts[key]) or "")
end

-- Waehlt den Interessenten auf einem Listenplatz und tauscht den Entwurf mit
-- aus. Gemerkt wird sein Name, nicht der Platz.
function GC.UI:SelectLead(leadIndex)
    local page = self.pages.INBOX
    if page and page.replyDrafts then
        local previous = page.replyDraftKey
        if previous then
            page.replyDrafts[previous] = page.replyEdit:GetText() or ""
        end
    end
    local lead = GC.DB:GetGuild().inbox[leadIndex]
    self.selectedLeadKey = lead and GC.Util.NormalizeName(lead.name) or nil
    self:LoadLeadDraft()
    self:RefreshInbox()
end

function GC.UI:RefreshInbox()
    local page = self.pages.INBOX
    if not page then
        return
    end
    if page.captureHelp then page.captureHelp:SetText(GC.Chat:GetCaptureStatus()) end

    local canEditTemplates = GC.Roster:CanEditGuildProfile()
    local templates = GC.DB:GetGuild().replyTemplates
    for key, edit in pairs(page.templateEdits) do
        if not edit:HasFocus() then
            edit:SetText(templates[key] or "")
        end
        if canEditTemplates then
            edit:Enable()
        else
            edit:Disable()
        end
    end
    SetButtonEnabled(page.saveTemplates, canEditTemplates)
    if not canEditTemplates and page.templateStatus:GetText() == "" then
        page.templateStatus:SetText(GC.L("Die Vorlagen sind für deinen Rang schreibgeschützt."))
        SetTextColor(page.templateStatus, THEME.warning)
    end

    local inbox = GC.DB:GetGuild().inbox
    if #inbox > 0 then
        page.clearInboxButton:Enable()
    else
        page.clearInboxButton:Disable()
    end
    if #inbox == 0 then
        page.confirmClearInbox = false
        page.clearInboxButton:SetText(GC.L("Alle löschen"))
    end
    local replyMarker = math.floor(tonumber(GC.DB:GetGuild().recruitment.replyMarker) or 0)
    page.replyMarkerOff:SetActive(replyMarker == 0)
    for markerIndex, markerButton in ipairs(page.replyMarkerButtons) do
        markerButton:SetActive(markerIndex == replyMarker)
    end
    -- Loest die Auswahl auf und rueckt bei Bedarf nach. Der Listenplatz kommt
    -- hier heraus, wird aber nur zum Markieren benutzt und nie gespeichert.
    -- Gezaehlt und geblaettert wird ueber die SICHTBAREN Eintraege. Ohne das
    -- zeigt die Seitenzahl den Gesamtbestand an, waehrend die Liste gefiltert
    -- ist - und die letzten Seiten waeren leer.
    local visible = self:GetVisibleLeadIndexes()
    local selectedLead, selectedIndex, selectedKey = self:GetSelectedLead(visible)
    if page.replyDraftKey ~= selectedKey then
        self:LoadLeadDraft()
        page.replyResult:SetText("")
    end
    page.visibleLeads = visible
    page.visibleLeadRefs = {}
    for position, index in ipairs(visible) do page.visibleLeadRefs[position] = inbox[index] end
    self:RefreshInboxFilterControls(#visible, #inbox)

    local leadPageCount = math.max(1, math.ceil(#visible / LEADS_PER_PAGE))
    page.leadPage = math.max(1, math.min(page.leadPage or 1, leadPageCount))
    local firstOnPage = (page.leadPage - 1) * LEADS_PER_PAGE
    local showLeadPaging = #visible > LEADS_PER_PAGE
    page.leadPrev:SetShown(showLeadPaging)
    page.leadNext:SetShown(showLeadPaging)
    page.leadPageLabel:SetText(showLeadPaging
        and ("Seite " .. page.leadPage .. "/" .. leadPageCount .. "  •  " .. #visible)
        or "")
    SetButtonEnabled(page.leadPrev, page.leadPage > 1)
    SetButtonEnabled(page.leadNext, page.leadPage < leadPageCount)

    for index, button in ipairs(page.leadButtons) do
        local leadIndex = visible[firstOnPage + index]
        local lead = leadIndex and inbox[leadIndex]
        button:SetShown(lead ~= nil)
        page.leadDeleteButtons[index]:SetShown(lead ~= nil)
        if lead then
            -- Mehrfaches Anschreiben landet bereits in einem Eintrag. Die Zahl
            -- macht sichtbar, dass dahinter mehr als eine Nachricht steckt.
            local count = #(lead.messages or {})
            -- Die Klasse steckt in der gespeicherten GUID. Der Aufruf hier holt
            -- sie auch fuer Altbestaende nach, sobald der Namens-Cache des
            -- Clients sie kennt.
            GC.Chat:ResolveLeadClass(lead)
            local level = tonumber(lead.level)
            -- Wer den Fall schon hat, gehört in die ZEILE, nicht ins Detail:
            -- Der ganze Zweck des geteilten Postfachs ist, dass man vor dem
            -- Anklicken sieht, dass ein Kollege längst geantwortet hat.
            button:SetText((lead.unread and "•  " or "")
                .. ClassColoredName(GC.Util.PlayerIdentityName(lead.name), lead.classFile)
                .. (level and ("  |cff8b98a5" .. level .. "|r") or "")
                .. (count > 1 and ("  |cff8b98a5(" .. count .. ")|r") or ""))
            button:SetActive(selectedIndex == leadIndex)
        end
    end

    local filters = GC.Chat:GetInboxFilterList()
    page.filterEntries = filters
    for index, row in ipairs(page.filterRows) do
        local entry = filters[index]
        row:SetShown(entry ~= nil)
        if entry then
            row.name:SetText(entry.name)
            if entry.until_ ~= "" then
                local days = GC.Util.DaysBetweenISO(GC.Util.TodayISO(), entry.until_)
                row.until_:SetText("ausgeblendet bis " .. entry.until_
                    .. (days and ("  •  noch " .. days .. (days == 1 and " Tag" or " Tage")) or ""))
            else
                row.until_:SetText(GC.L("dauerhaft ignoriert"))
            end
        end
    end
    if #filters == 0 then
        page.filterNotice:SetText(GC.L("Niemand ausgeblendet."))
    elseif #filters > #page.filterRows then
        page.filterNotice:SetText(GC.LFormat("Weitere {n} ausgeblendete Spieler sind vorhanden.",
            { n = #filters - #page.filterRows }))
    else
        page.filterNotice:SetText(GC.L(""))
    end

    SetButtonEnabled(page.hideTempButton, selectedLead ~= nil)
    SetButtonEnabled(page.hideForeverButton, selectedLead ~= nil)

    local lead = selectedLead
    if not lead then
        page.leadTitle:SetText(GC.L(#inbox > 0 and "Keine passenden Interessenten" or "Noch keine Interessenten"))
        page.lastMessage:SetText(GC.L(#inbox > 0
            and "Keine Treffer für diese Filter. Wähle Alle Klassen und Alle Stufen, um alle Interessenten zu sehen."
            or "Starte eine Suche. Eingehende Flüsternachrichten erscheinen automatisch hier."))
        if not page.replyEdit:HasFocus() then
            page.replyEdit:SetText(GC.L(""))
        end
        self:SetLeadProfileLinks(nil)
        page.replyButton:Disable()
        page.inviteButton:Disable()
        SetButtonEnabled(page.infoReplyButton, false)
        SetButtonEnabled(page.discordReplyButton, false)
        return
    end

    GC.Chat:ResolveLeadClass(lead)
    local classInfo = GC.Classes[lead.classFile or ""]
    local level = tonumber(lead.level)
    page.leadTitle:SetText(ClassColoredName(GC.Util.PlayerIdentityName(lead.name), lead.classFile)
        .. (classInfo and ("  |cff8b98a5" .. (level and (level .. "  ") or "")
            .. classInfo.name .. "|r") or (level and ("  |cff8b98a5" .. level .. "|r") or "")))
    local latest = lead.messages[#lead.messages]
    local source = latest and latest.source and latest.source ~= "WHISPER" and ("  •  " .. latest.source) or ""
    -- Wann geschrieben wurde, entscheidet mit darueber, ob sich eine Antwort
    -- noch lohnt. Die Zeit stand bisher nur in den Daten, nicht am Eintrag.
    local stamp = latest and FormatInboxTime(latest.receivedAt) or ""
    if stamp ~= "" then
        stamp = "  •  " .. stamp
    end
    page.lastMessage:SetText(latest
        and ("Letzte Nachricht" .. source .. stamp .. "\n\"" .. latest.text .. "\"")
        or "")
    self:SetLeadProfileLinks(lead)
    page.replyButton:Enable()
    page.inviteButton:Enable()
    SetButtonEnabled(page.infoReplyButton, GC.Recruitment:GenerateReply("INFO", lead.name) ~= "")
    SetButtonEnabled(page.discordReplyButton, GC.Recruitment:GenerateReply("DISCORD", lead.name) ~= "")
end

-- Die Linkfelder sind bewusst nur zum Kopieren da: WoW-Addons koennen weder
-- einen Browser oeffnen noch in die Zwischenablage schreiben.
function GC.UI:SetLeadProfileLinks(lead)
    local page = self.pages.INBOX
    if not page or not page.leadLinkEdits then
        return
    end
    -- Die Profil-Links (Armory, Warcraft-Logs-Charakterseite) werden aus Region,
    -- Realm und Name gebaut - ohne das optionale Import-Modul, das dem Addon
    -- nicht beiliegt. Nur wenn kein Realm zu ermitteln ist, bleiben sie leer.
    local links = (lead and GC.Chat:BuildLeadProfileLinks(lead.name)) or {}
    local missing = false
    for key, edit in pairs(page.leadLinkEdits) do
        local link = links[key] or ""
        local changed = edit.linkValue ~= link
        edit.linkValue = link
        if changed then
            edit:ClearFocus()
            edit:SetText(link)
        end
        if not edit:HasFocus() then
            edit:SetText(link)
        end
        if lead and link == "" then
            missing = true
        end
    end
    if missing then
        page.leadLinkNotice:SetText(GC.Client.isForever and "Für Forever sind noch keine verifizierten Profil-Linkziele eingerichtet."
            or GC.L("Ohne erkennbaren Realm des Interessenten lassen sich keine Profil-Links bilden."))
    else
        page.leadLinkNotice:SetText(GC.L(""))
    end
end

function GC.UI:BuildGuildPage()
    local page = self.pages.GUILD
    CreatePageTitle(page, "Gildenprofil", "Nur aktivierte Angaben fließen in neue Texte ein. Ausgeschaltete Werte bleiben gespeichert. Änderungen mit Speichern übernehmen.")

    local card = CreateCard(page, "Texte & Eckdaten")
    card:SetSize(776, 490)
    card:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -66)
    page.guildFields = {}
    page.guildFieldToggles = {}
    page.guildEnabled = CreateToggle(card, "Gildenprofil verwenden", function() GC.UI:RefreshGuildFieldAvailability() end)
    page.guildEnabled:SetPoint("TOPLEFT", card, "TOPLEFT", 500, -12)
    local fields = {
        { key = "description", label = "Kurzbeschreibung", y = -52, multiline = true, height = 78 },
        { key = "raidTimes", label = "Raidzeiten", y = -150 },
        { key = "progress", label = "Content / Progress", y = -202 },
        { key = "lootSystem", label = "Lootsystem", y = -254 },
        { key = "discord", label = "Discord", y = -306 },
        { key = "contact", label = "Kontaktperson", y = -358 },
    }
    for _, definition in ipairs(fields) do
        local toggle = CreateToggle(card, definition.label, function() GC.UI:RefreshGuildFieldAvailability() end)
        toggle:SetPoint("TOPLEFT", card, "TOPLEFT", 18, definition.y)
        toggle.text:SetWidth(140)
        page.guildFieldToggles[definition.key] = toggle
        local edit
        if definition.multiline then
            edit = CreateTextArea(card, 558, definition.height, 800)
        else
            edit = CreateEdit(card, 558, 34)
        end
        edit.container:SetPoint("TOPLEFT", card, "TOPLEFT", 194, definition.y + 8)
        page.guildFields[definition.key] = edit
    end

    page.guildSaveButton = CreateButton(card, "Speichern & weiter", 200, 38, function()
        if not GC.Roster:CanEditGuildProfile() then
            page.saveResult:SetText(GC.L("Dein Gildenrang darf das Gildenprofil nicht bearbeiten."))
            SetTextColor(page.saveResult, THEME.danger)
            return
        end
        local profile = GC.DB:GetGuild().profile
        profile.enabled = page.guildEnabled:GetChecked() == true
        profile.disabledFields = {}
        for key, edit in pairs(page.guildFields) do
            profile[key] = GC.Util.Trim(edit:GetText())
            if not page.guildFieldToggles[key]:GetChecked() then profile.disabledFields[key] = true end
        end
        profile.updatedAt = GC.Util.Now()
        GC.DB:GetGuild().recruitment.adText = GC.Recruitment:GenerateAdvertisement()

        -- Erst pruefen, dann melden: Ein zu grosses Profil wird lokal zwar
        -- gespeichert, kommt bei niemandem an. Das darf nicht als Erfolg
        -- durchgehen.
        local tooLarge = GC.UI:GuildProfileTooLargeMessage()
        if tooLarge then
            GC:FireCallback("GUILD_PROFILE_UPDATED")
            page.saveResult:SetText(tooLarge)
            SetTextColor(page.saveResult, THEME.danger)
            return
        end

        if GC.Sync and GC.Sync.QueueGuildProfile then
            -- Auch das Ausschalten einmal an die Gilde weitergeben.
            GC.Sync:QueueGuildProfile(true)
        end
        GC:FireCallback("GUILD_PROFILE_UPDATED")
        page.saveResult:SetText(GC.L("Gespeichert und zur Gildensynchronisierung vorgemerkt."))
        SetTextColor(page.saveResult, THEME.success)
        GC.UI:ShowPage("SUGGESTIONS")
    end, "PRIMARY")
    page.guildSaveButton:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 194, 18)
    page.saveResult = CreateLabel(card, "", { width = 330 })
    page.saveResult:SetPoint("LEFT", page.guildSaveButton, "RIGHT", 14, 0)
end

function GC.UI:RefreshGuildFieldAvailability()
    local page = self.pages.GUILD
    local canEdit = GC.Roster:CanEditGuildProfile()
    if canEdit then page.guildEnabled:Enable() else page.guildEnabled:Disable() end
    page.guildEnabled:SetAlpha(canEdit and 1 or 0.45)
    for key, edit in pairs(page.guildFields) do
        local toggle = page.guildFieldToggles[key]
        local canToggle = canEdit and page.guildEnabled:GetChecked()
        if canToggle then toggle:Enable() else toggle:Disable() end
        toggle:SetAlpha(canToggle and 1 or 0.45)
        local active = page.guildEnabled:GetChecked() and toggle:GetChecked()
        if canEdit and active then edit:Enable() else edit:ClearFocus(); edit:Disable() end
        edit.container:SetAlpha(active and 1 or 0.45)
    end
end

function GC.UI:RefreshGuild()
    local page = self.pages.GUILD
    if not page then
        return
    end
    local info = GC.DB:GetGuild().profile
    local canEdit = GC.Roster:CanEditGuildProfile()
    SetToggle(page.guildEnabled, info.enabled ~= false)
    for key, edit in pairs(page.guildFields) do
        SetToggle(page.guildFieldToggles[key], not info.disabledFields[key])
        if not edit:HasFocus() then
            edit:SetText(info[key] or "")
        end
        if canEdit then
            edit:Enable()
        else
            edit:Disable()
        end
    end
    self:RefreshGuildFieldAvailability()
    if canEdit then
        page.guildSaveButton:Enable()
        if page.saveResult:GetText() == "" then
            page.saveResult:SetText(GC.L("Dein Rang darf dieses gildenweite Profil bearbeiten."))
            SetTextColor(page.saveResult, THEME.muted)
        end
    else
        page.guildSaveButton:Disable()
        page.saveResult:SetText(GC.L("Nur in Einstellungen freigegebene Gildenränge dürfen Änderungen speichern."))
        SetTextColor(page.saveResult, THEME.warning)
    end
end

function GC.UI:BuildWarcraftLogsPage()
    local page = self.pages.WCL
    -- Ohne das optionale Modul entsteht der Navigationspunkt gar nicht, und
    -- damit auch keine Seite. Hier still aussteigen statt in ein nil greifen.
    if not page or not GC.WarcraftLogs then
        return
    end
    CreatePageTitle(page, "Warcraft Logs",
        "Profile manuell eingeben oder öffentliche Reports mit dem mitgelieferten Windows-Helfer auslesen.")

    local sourceCard = CreateCard(page, "Gildenquelle")
    sourceCard:SetSize(776, 186)
    sourceCard:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -66)
    -- Die häufige Frage lautet: warum die URL hier eintragen, wenn der Import
    -- ohnehin von Hand kommt? Weil ein WoW-Addon selbst nichts aus dem Netz
    -- laden darf. Die Antwort gehört sichtbar an die Stelle, an der die Frage
    -- entsteht.
    local sourceHelp = CreateLabel(sourceCard,
        "Ein WoW-Addon darf selbst nichts aus dem Internet laden – deshalb übernimmt der Windows-Helfer den Abruf."
        .. " Die hier gespeicherte Gilde erspart dir dort die Eingabe, liefert Region und Realm für die Profil-Links"
        .. " im Postfach und wird an alle Gildenmitglieder synchronisiert.",
        { muted = true, width = 740, height = 44, vertical = "TOP" })
    sourceHelp:SetPoint("TOPLEFT", sourceCard, "TOPLEFT", 18, -44)
    page.wclURL = CreateEdit(sourceCard, 740, 38)
    page.wclURL.container:SetPoint("TOPLEFT", sourceCard, "TOPLEFT", 18, -85)

    local detect = CreateButton(sourceCard, "Aus Gilde erkennen", 170, 34, function()
        page.wclURL:SetText(GC.WarcraftLogs:GetSuggestedURL())
        page.wclResult:SetText(GC.L("Link aus Region, Realm und Gildenname vorbereitet."))
        SetTextColor(page.wclResult, THEME.muted)
    end)
    detect:SetPoint("TOPLEFT", sourceCard, "TOPLEFT", 18, -138)
    local save = CreateButton(sourceCard, "Quelle speichern", 160, 34, function()
        local success, message = GC.WarcraftLogs:SaveSource(page.wclURL:GetText())
        page.wclResult:SetText(message or "")
        SetTextColor(page.wclResult, success and THEME.success or THEME.danger)
        GC.UI:RefreshWarcraftLogs()
    end, "PRIMARY")
    save:SetPoint("LEFT", detect, "RIGHT", 8, 0)
    page.wclResult = CreateLabel(sourceCard, "", { width = 385 })
    page.wclResult:SetPoint("LEFT", save, "RIGHT", 14, 0)

    local importCard = CreateCard(page, "Import – manuell oder Installer")
    importCard:SetSize(776, 238)
    importCard:SetPoint("TOPLEFT", sourceCard, "BOTTOMLEFT", 0, -10)
    local importHelp = CreateLabel(importCard,
        "Ohne API: Name;Klasse;Primär-Spec;Dual-Spec – z. B. Nexarius;Magier;Arkan;Frost.\nAutomatisch: Im Guild-Copilot-Installer „Import erzeugen“; die Companion-CMD bleibt als Rückfall. Danach hier mit Strg+V einfügen.",
        { muted = true, width = 740, height = 44, vertical = "TOP" })
    importHelp:SetPoint("TOPLEFT", importCard, "TOPLEFT", 18, -46)
    -- Ein Companion-Export mit mehreren Reports ist schnell größer als das
    -- alte Limit von 12000 Zeichen; darüber schneidet WoW beim Einfügen
    -- stillschweigend ab und der Import scheitert ohne erkennbaren Grund.
    page.wclImport = CreateTextArea(importCard, 740, 82, 60000)
    page.wclImport.container:SetPoint("TOPLEFT", importCard, "TOPLEFT", 18, -92)
    page.wclImport:SetText(GC.L(""))

    -- Der Import ersetzt die gespeicherten Profile vollständig. Solange die
    -- Meldung nach einem Klick genauso aussehen kann wie vorher, weiß niemand,
    -- ob überhaupt etwas passiert ist. Deshalb: erster Klick benennt die
    -- Folgen, zweiter Klick führt aus - dasselbe Muster wie beim
    -- Gildenausschluss. Jede Rückmeldung trägt die Uhrzeit, damit auch ein
    -- gleichlautendes Ergebnis sichtbar neu ist.
    local import
    local function DisarmImport()
        page.wclImportArmed = false
        if import then
            import:SetText(GC.L("Daten importieren"))
        end
    end

    local function ShowImportResult(message, success)
        page.wclImportResult:SetText((message or "") .. "  (" .. date("%H:%M:%S") .. ")")
        SetTextColor(page.wclImportResult, success and THEME.success or THEME.danger)
    end

    import = CreateButton(importCard, "Daten importieren", 170, 36, function()
        local text = page.wclImport:GetText()
        if GC.Util.Trim(text) == "" then
            DisarmImport()
            ShowImportResult("Das Importfeld ist leer.", false)
            return
        end

        local stored = GC.WarcraftLogs:GetImportedCount()
        if stored > 0 and not page.wclImportArmed then
            page.wclImportArmed = true
            import:SetText(GC.L("Wirklich ersetzen"))
            ShowImportResult(stored .. " gespeicherte Profile werden ersetzt. "
                .. "Zum Bestätigen erneut klicken.", false)
            return
        end

        DisarmImport()
        local success, message = GC.WarcraftLogs:Import(text)
        ShowImportResult(message, success)
        GC.UI:RefreshWarcraftLogs()
    end, "PRIMARY")
    import:SetPoint("BOTTOMLEFT", importCard, "BOTTOMLEFT", 18, 14)
    page.wclImportButton = import
    page.wclImportDisarm = DisarmImport

    -- Neuer Text heißt neue Absicht: alte Meldung weg, Bestätigung zurück.
    page.wclImport:SetScript("OnTextChanged", function(_, userInput)
        if not userInput then
            return
        end
        DisarmImport()
        page.wclImportResult:SetText(GC.L(""))
    end)
    page.wclImportResult = CreateLabel(importCard, "", { width = 535 })
    page.wclImportResult:SetPoint("LEFT", import, "RIGHT", 14, 0)

    local statusCard = CreateCard(page, "Status")
    statusCard:SetSize(776, 90)
    statusCard:SetPoint("TOPLEFT", importCard, "BOTTOMLEFT", 0, -10)
    page.wclStatus = CreateLabel(statusCard, "", { width = 740, height = 40, vertical = "TOP" })
    page.wclStatus:SetPoint("TOPLEFT", statusCard, "TOPLEFT", 18, -42)
end

function GC.UI:RefreshWarcraftLogs()
    local page = self.pages.WCL
    if not page or not GC.WarcraftLogs then
        return
    end
    local data = GC.DB:GetGuild().warcraftLogs
    if not page.wclURL:HasFocus() then
        page.wclURL:SetText(data.url ~= "" and data.url or GC.WarcraftLogs:GetSuggestedURL())
    end
    -- Eine scharfgeschaltete Bestätigung darf einen Seitenwechsel nicht
    -- überleben; sonst löst der nächste Klick unerwartet aus.
    if page.wclImportDisarm then
        page.wclImportDisarm()
    end
    local imported = GC.WarcraftLogs:GetImportedCount()
    if imported > 0 then
        -- Die Zahl der Nachanalysen gehört sichtbar daneben: sonst sieht ein
        -- reiner Profilimport genauso aus wie einer mit Raidauswertungen.
        local sessions = data.sessionCount or 0
        -- Stand und Herkunft machen sichtbar, dass Profile auch von anderen
        -- Gildenmitgliedern hereinkommen und nicht jeder selbst importieren muss.
        local stand = ""
        local importedAt = tonumber(data.importedAt) or 0
        if importedAt > 0 and date then
            stand = "  •  Stand " .. date("%d.%m.%Y %H:%M", importedAt)
        end
        local from = GC.Util.Trim(data.lastSyncFrom) ~= ""
            and ("  •  zuletzt von " .. data.lastSyncFrom)
            or ""
        page.wclStatus:SetText("|cff59e695" .. imported .. " Spielerprofile verfügbar|r"
            .. (data.reportCount > 0 and ("  •  " .. data.reportCount .. " Reports") or "")
            .. (sessions > 0
                and ("  •  |cff59e695" .. sessions .. " Raidauswertungen|r")
                or "  •  |cffe8b84bkeine Raidauswertung|r")
            .. stand .. from
            .. "\nDiese Specs ergänzen jetzt automatisch die Roster- und Copilot-Auswertung."
            .. " Profile werden automatisch in der Gilde geteilt; vollständige Kampfauswertungen bleiben lokal.")
    else
        page.wclStatus:SetText(GC.L("|cff91a3b8Noch keine Log-Daten importiert.|r"
            .. "\nDie gespeicherte URL ist für den Companion vorbereitet."
            .. " Importiert ein anderes Gildenmitglied, erscheinen die Profile auch hier von selbst."))
    end
end

local function FormatDuration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if hours > 0 then
        return hours .. "h " .. minutes .. "m"
    end
    return minutes .. "m"
end

-- Die Sitzungsliste ist 206 Pixel breit; darin stehen Datum, Uhrzeit, Instanz
-- und Quellenzeichen. "Höhle des Schlangenschreins" allein füllt sie schon.
-- Die geläufige Kurzform sagt dasselbe und lässt Platz für den Rest; was hier
-- nicht steht, bleibt unverändert und wird notfalls abgeschnitten statt
-- umgebrochen.
local SHORT_ZONE_NAMES = {
    ["höhle des schlangenschreins"] = "Serpentinhöhle",
    ["serpentshrine cavern"] = "Serpentinhöhle",
    ["festung der stürme"] = "Festung der Stürme",
    ["tempest keep"] = "Festung der Stürme",
    ["gruuls unterschlupf"] = "Gruuls Lager",
    ["gruul's lair"] = "Gruuls Lager",
    ["magtheridons kammer"] = "Magtheridon",
    ["magtheridon's lair"] = "Magtheridon",
    ["schwarzer tempel"] = "Schwarzer Tempel",
    ["black temple"] = "Schwarzer Tempel",
    ["hyjalgipfel"] = "Hyjal",
    ["hyjal summit"] = "Hyjal",
    ["sonnenbrunnenplateau"] = "Sonnenbrunnen",
    ["sunwell plateau"] = "Sonnenbrunnen",
    ["zul'aman"] = "Zul'Aman",
}

local function ShortZoneName(zone)
    zone = tostring(zone or "")
    return SHORT_ZONE_NAMES[zone:lower()] or zone
end

local function FormatSessionDate(summary)
    if date and summary.startedAt and summary.startedAt > 0 then
        local ok, formatted = pcall(date, "%d.%m. %H:%M", summary.startedAt)
        if ok and formatted then
            return formatted
        end
    end
    return "unbekannt"
end

function GC.UI:BuildStatisticsPage()
    local page = self.pages.STATISTICS
    if not GC.Client.combatAnalysis then
        CreatePageTitle(page, "Raidvorbereitung",
            "Buffs der erreichbaren Gruppe und eigene Vorräte vor dem Pull prüfen. Eine Momentaufnahme belegt keinen Verbrauch im Raid.")
        page.preparationButton = CreateButton(page, "Vorbereitung erfassen", 220, 32, function()
            local ok, message = GC.RaidPreparation:Capture()
            page.preparationStatus:SetText(message)
            SetTextColor(page.preparationStatus, ok and THEME.success or THEME.warning)
            GC.UI:RefreshStatistics()
        end)
        page.preparationButton:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -78)
        local gear = CreateButton(page, "Ausrüstung prüfen", 180, 32, function() GC.UI:ShowPage("GEAR") end)
        gear:SetPoint("LEFT", page.preparationButton, "RIGHT", 12, 0)
        page.preparationStatus = CreateLabel(page, "Nur öffentlich lesbare Daten; gesperrte oder entfernte Mitglieder bleiben unbekannt.",
            { muted = true, width = 760, height = 44, vertical = "TOP" })
        page.preparationStatus:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -122)
        local scroll = CreateModernScrollFrame(page)
        scroll:SetSize(776, 390)
        scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -174)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(744, 390)
        scroll:SetScrollChild(content)
        page.preparationContent = content
        page.preparationText = CreateLabel(content, "", { width = 720, vertical = "TOP" })
        page.preparationText:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -8)
        self:RefreshStatistics()
        return
    end
    CreatePageTitle(page, "Raidauswertung",
        "Sitzungen starten nur berechtigte Ränge; gespeichert werden Zusammenfassungen, keine Rohdaten."
        .. " Spaltenkopf: Klick sortiert, Ziehen ordnet um. Maus über einer Zeile zeigt alles im Detail.")

    local controlCard = CreateCard(page)
    controlCard:SetSize(776, 96)
    controlCard:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -66)
    page.sessionStatus = CreateLabel(controlCard, "", { width = 470, height = 46, vertical = "TOP" })
    page.sessionStatus:SetPoint("TOPLEFT", controlCard, "TOPLEFT", 18, -14)

    -- Kurze Rückmeldungen stehen im Fenster und zusätzlich im Chat, damit sie
    -- auch bei geschlossenem Addonfenster ankommen. Die Auswertung selbst
    -- bleibt vollständig in der Oberfläche.
    page.actionStatus = CreateLabel(controlCard, "", { width = 560, height = 26, vertical = "TOP" })
    page.actionStatus:SetPoint("TOPLEFT", controlCard, "TOPLEFT", 18, -64)

    function page:SetActionStatus(message, ok)
        message = GC.Util.Trim(message)
        self.actionStatus:SetText(message)
        SetTextColor(self.actionStatus, ok == false and THEME.danger or THEME.success)
        if message ~= "" then
            GC:Print(message)
        end
    end

    page.sessionButton = CreateButton(controlCard, "Sitzung starten", 150, 30, function()
        local monitor = GC.RaidMonitor
        local ok, message
        if monitor.session then
            ok, message = monitor:EndSession()
        else
            ok, message = monitor:BeginSession()
        end
        page:SetActionStatus(message, ok)
        GC.UI:RefreshStatistics()
    end, "PRIMARY")
    page.sessionButton:SetPoint("TOPRIGHT", controlCard, "TOPRIGHT", -18, -14)

    -- Die Saisonfrage neben der Tagesansicht: Wer war ueber alle Abende wie
    -- zuverlaessig da? Der Platz reicht exakt - die Statuszeile ist 470 breit
    -- und endet bei x=488, der Knopf beginnt bei x=490.
    page.attendanceButton = CreateButton(controlCard, "Anwesenheit", 110, 30, function()
        GC.UI:ShowAttendance()
    end)
    page.attendanceButton:SetPoint("TOPRIGHT", page.sessionButton, "TOPLEFT", -8, 0)

    page.requestButton = CreateButton(controlCard, "Auswertung anfordern", 150, 30, function()
        local ok, message = GC.RaidMonitor:RequestSummaries()
        page:SetActionStatus(message, ok)
    end)
    page.requestButton:SetPoint("TOPRIGHT", page.sessionButton, "BOTTOMRIGHT", 0, -4)

    page.reviewButton = CreateButton(controlCard, "Detailfenster", 130, 30, function()
        GC.UI:ShowSessionReview()
    end)
    page.reviewButton:SetPoint("RIGHT", page.requestButton, "LEFT", -8, 0)

    local listCard = CreateCard(page, "Sitzungen")
    listCard:SetSize(238, 358)
    listCard:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -172)
    page.sessionRows = {}
    for index = 1, 11 do
        local row = CreateButton(listCard, "", 206, 23, function()
            -- Ein Eintrag ist ein Abend, nicht eine Quelle. Gewaehlt wird die
            -- vollstaendigste Auswertung; auf die anderen Quellen fuehren die
            -- Knoepfe neben der Kopfzeile.
            local evening = GC.RaidMonitor:GetEvenings()[index]
            if evening then
                GC.RaidMonitor.selectedSessionID = GC.RaidMonitor:SummaryKey(evening.summary)
                GC.UI:RefreshStatistics()
            end
        end)
        row:SetPoint("TOPLEFT", listCard, "TOPLEFT", 16, -50 - ((index - 1) * 25))
        row.label:SetJustifyH("LEFT")
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        page.sessionRows[index] = row
    end
    page.sessionEmpty = CreateLabel(listCard, "Noch keine Auswertung vorhanden.", { muted = true, width = 200, height = 40, vertical = "TOP" })
    page.sessionEmpty:SetPoint("TOPLEFT", listCard, "TOPLEFT", 16, -52)

    -- Löschen mit Scharfschalt-Klick, beschränkt auf die Ränge mit
    -- Mitgliederpflege-Zugriff (in den Einstellungen einstellbar).
    page.deleteSessionButton = CreateButton(listCard, "Sitzung löschen", 206, 26, function()
        if not page.deleteArmed then
            page.deleteArmed = GC.RaidMonitor.selectedSessionID
            page.deleteSessionButton:SetText(GC.L("Wirklich löschen?"))
            return
        end
        page.deleteArmed = nil
        page.deleteSessionButton:SetText(GC.L("Sitzung löschen"))
        local ok, message = GC.RaidMonitor:DeleteEvening(GC.RaidMonitor.selectedSessionID)
        page:SetActionStatus(message, ok)
        GC.UI:RefreshStatistics()
    end)
    page.deleteSessionButton:SetPoint("BOTTOMLEFT", listCard, "BOTTOMLEFT", 16, 10)

    local detailCard = CreateCard(page, "Teilnehmer")
    detailCard:SetSize(526, 358)
    detailCard:SetPoint("TOPLEFT", page, "TOPLEFT", 250, -172)
    page.sessionHeadline = CreateLabel(detailCard, "", { muted = true, width = 486, height = 18 })
    page.sessionHeadline:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, -44)

    -- Liegt derselbe Abend aus mehreren ANZEIGBAREN Quellen vor, wechseln diese
    -- Knoepfe zwischen ihnen. Fremde Mitschnitte (SYNC:<Name>) sind dabei
    -- ausgeblendet, solange eine eigene Fassung existiert - sie sind reines
    -- Reparaturmaterial, siehe RaidMonitor:VisibleSources. Die Knoepfe stehen in
    -- der Kopfzeile der Karte, weil darunter die Tabellenkoepfe beginnen und
    -- dazwischen kein Platz ist.
    page.sessionSourceButtons = {}
    for index = 1, 3 do
        local button = CreateButton(detailCard, "", 96, 20, function()
            local target = GC.UI.pages.STATISTICS.sessionSourceButtons[index].summaryID
            if target then
                GC.RaidMonitor.selectedSessionID = target
                GC.UI:RefreshStatistics()
            end
        end)
        button:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 146 + ((index - 1) * 100), -14)
        button:Hide()
        page.sessionSourceButtons[index] = button
    end
    -- Direkt neben den Quellen: öffnet das Detailfenster gleich im
    -- Vergleichsmodus Live gegen Logs (Owner-Wunsch).
    page.sessionCompareButton = CreateButton(detailCard, "Vergleich", 96, 20, function()
        GC.UI:ShowSessionReview()
        local review = GC.UI.sessionReview
        if review then
            review.compare = true
            GC.UI:RefreshSessionReview()
        end
    end)
    page.sessionCompareButton:Hide()

    -- Elixiere haben eine eigene Spalte. Sie mit Flaeschchen zusammenzufassen
    -- war ein Fehler: In einem Raid, in dem niemand Flaeschchen nimmt, stand
    -- jede Elixierzahl unter der Ueberschrift "Flasche" - und war damit
    -- praktisch unauffindbar. Nur Runen laufen weiter bei den Traenken mit,
    -- Oele und Steine stehen im Tooltip.
    -- Englische Koepfe: kuerzer als die deutschen und in Raid-Werkzeugen
    -- gebraeuchlich. Der gewonnene Platz geht an die Namensspalte, die vorher
    -- laengere Namen abschnitt. Was die Kuerzel bedeuten, steht im Seitentext
    -- und ausgeschrieben im Tooltip der Zeile.
    -- Einheitliche Breiten: Früher hatte jede Spalte ihr Maß (ELIXIR 48,
    -- INT 32) - nach dem Umsortieren wirkte das Raster dadurch ungleichmäßig.
    -- Jetzt sind alle Wertespalten gleich breit, nur TIME braucht mehr Platz
    -- ("1h 33m"), und ELIXIR heißt wie im Detailfenster kurz ELIX.
    -- Ohne TIME-Spalte (Owner: unnötig, steht im Tooltip und Detailfenster)
    -- bekommen die acht Wertespalten einheitlich 46 statt 40 Pixel.
    local detailHeaders = {
        { text = "NAME",  key = "name",       x = 18,  width = 96 },
        { text = "ELIX",  key = "elixirs",    x = 117, width = 46 },
        { text = "FOOD",  key = "food",       x = 165, width = 46 },
        { text = "FLASK", key = "flasks",     x = 213, width = 46 },
        { text = "DRUM",  key = "drums",      x = 261, width = 46 },
        { text = "DEATH", key = "deaths",     x = 309, width = 46 },
        { text = "POT",   key = "potions",    x = 357, width = 46 },
        { text = "DISP",  key = "dispels",    x = 405, width = 46 },
        { text = "INT",   key = "interrupts", x = 453, width = 46 },
    }

    -- Die Kopfzeile sortiert. Erster Klick absteigend, zweiter aufsteigend -
    -- "wer hat keine Flaeschchen" ist damit ein Klick statt einer Suche.
    -- ZIEHEN eines Kopfes ordnet die Spalte an eine neue Position (kurzer
    -- Klick bleibt Sortieren; WoW feuert den Drag erst ab einer Schwelle).
    page.sortHeaders = {}
    page.sortHeaderByKey = {}
    page.statColumnWidths = {}
    for _, headerDefinition in ipairs(detailHeaders) do
        local sortKey = headerDefinition.key
        local header = CreateButton(detailCard, headerDefinition.text,
            headerDefinition.width, 18, function()
                if page.sortKey == sortKey then
                    page.sortDescending = not page.sortDescending
                else
                    page.sortKey = sortKey
                    -- Namen von A nach Z, Zahlen von viel nach wenig.
                    page.sortDescending = sortKey ~= "name"
                end
                GC.UI:RefreshStatistics()
            end)
        header:SetPoint("TOPLEFT", detailCard, "TOPLEFT", headerDefinition.x, -66)
        header.background:Hide()
        header.border:Hide()
        header.label:SetFontObject("GameFontNormalSmall")
        header.label:ClearAllPoints()
        header.label:SetPoint("LEFT", header, "LEFT", 0, 0)
        header.label:SetJustifyH("LEFT")
        header.baseText = headerDefinition.text
        header.sortKey = sortKey
        page.sortHeaders[#page.sortHeaders + 1] = header
        page.sortHeaderByKey[sortKey] = header
        page.statColumnWidths[sortKey] = headerDefinition.width
        -- Anfass-Feedback: Unter der Maus leuchtet der Kopf auf - vorher gab
        -- es kein Zeichen, dass man ihn packen kann (Owner-Rückmeldung).
        header:SetScript("OnEnter", function(self)
            SetTextColor(self.label, THEME.accent)
        end)
        header:SetScript("OnLeave", function(self)
            if page.sortKey == self.sortKey then
                SetTextColor(self.label, THEME.accent)
            else
                SetTextColor(self.label, THEME.muted)
            end
        end)
        if sortKey ~= "name" then
            header:RegisterForDrag("LeftButton")
            header:SetScript("OnDragStart", function(self)
                page.columnDragKey = sortKey
                if self.SetAlpha then
                    self:SetAlpha(0.55)
                end
            end)
            header:SetScript("OnDragStop", function(self)
                if self.SetAlpha then
                    self:SetAlpha(1)
                end
                local draggedKey = page.columnDragKey
                page.columnDragKey = nil
                if not draggedKey or not GetCursorPosition then
                    return
                end
                local scale = (UIParent and UIParent.GetEffectiveScale
                    and UIParent:GetEffectiveScale()) or 1
                local cursorX = GetCursorPosition()
                if not cursorX then
                    return
                end
                cursorX = cursorX / scale
                for position, key in ipairs(GC.UI:GetStatColumnOrder()) do
                    local target = page.sortHeaderByKey[key]
                    if target and key ~= draggedKey then
                        local left, right = target:GetLeft(), target:GetRight()
                        if left and right and cursorX >= left and cursorX <= right then
                            GC.UI:MoveStatColumn(draggedKey, position)
                            GC.UI:RefreshStatistics()
                            return
                        end
                    end
                end
            end)
        end
    end

    local scroll = CreateModernScrollFrame(detailCard)
    scroll:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 14, -86)
    scroll:SetPoint("BOTTOMRIGHT", detailCard, "BOTTOMRIGHT", -16, 30)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(492)
    content:SetHeight(1100)
    scroll:SetScrollChild(content)

    -- Das frühere Zeilen-Ziehen ist ersatzlos entfernt (Owner: "Blödsinn") -
    -- verschieben lassen sich jetzt die SPALTEN, am Kopf gepackt.
    CreateLabel(detailCard, "Spaltenköpfe ziehen ordnet die Spalten", {
        muted = true,
        font = "GameFontNormalSmall",
        align = "RIGHT",
        width = 260,
    }):SetPoint("BOTTOMRIGHT", detailCard, "BOTTOMRIGHT", -16, 8)

    page.participantRows = {}
    for index = 1, 40 do
        local row = CreatePanel(content, index % 2 == 0 and THEME.input or THEME.card)
        row:SetSize(490, 25)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((index - 1) * 27))
        row.rowIndex = index
        -- Nur Erzeugung mit einheitlichen Breiten; die Positionen setzt
        -- ApplyStatColumnLayout nach der gespeicherten Ordnung.
        local columns = {
            { key = "name", x = 5, width = 96 },
            { key = "elixirs", x = 104, width = 46 },
            { key = "food", x = 152, width = 46 },
            { key = "flasks", x = 200, width = 46 },
            { key = "drums", x = 248, width = 46 },
            { key = "deaths", x = 296, width = 46 },
            { key = "potions", x = 344, width = 46 },
            { key = "dispels", x = 392, width = 46 },
            { key = "interrupts", x = 440, width = 46 },
        }
        for _, column in ipairs(columns) do
            row[column.key] = CreateLabel(row, "", { width = column.width, height = 25 })
            row[column.key]:SetPoint("LEFT", row, "LEFT", column.x, 0)
        end

        -- Klick auf die Zeile: das Verbrauchsprotokoll des Spielers (was
        -- genau, wann - Owner-Wunsch).
        row:SetScript("OnMouseUp", function(self)
            if self.participant then
                GC.UI:ShowConsumableLog(self.participant)
            end
        end)

        -- Die Spaltenkoepfe muessen kurz sein. Was sie bedeuten und was in den
        -- zusammengefassten Spalten steckt, steht hier vollstaendig.
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local participant = self.participant
            if not participant or not GameTooltip then
                return
            end
            local consumables = participant.consumables or {}
            AnchorRowTooltip(self)
            GameTooltip:SetText(participant.name or "")
            local presence = "Dabei: " .. FormatDuration(participant.seconds)
            if (self.sessionSeconds or 0) > 0 then
                presence = presence .. "  von  " .. FormatDuration(self.sessionSeconds)
                    .. "   (" .. math.floor(((participant.seconds or 0) / self.sessionSeconds) * 100 + 0.5) .. " %)"
            end
            GameTooltip:AddLine(presence, 1, 1, 1)
            GameTooltip:AddLine("Tode: " .. (participant.deaths or 0)
                .. "   Wiederbelebungen: " .. (participant.resurrects or 0), 1, 1, 1)
            GameTooltip:AddLine("Unterbrechungen: " .. (participant.interrupts or 0)
                .. "   Bannen: " .. (participant.dispels or 0), 1, 1, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Verbrauchsgegenstände", 0.31, 0.79, 1)
            for _, category in ipairs(GC.ConsumableCategories) do
                local count = consumables[category.key] or 0
                local red, green, blue = 0.57, 0.64, 0.72
                if count > 0 then
                    red, green, blue = 1, 1, 1
                end
                GameTooltip:AddDoubleLine(GC.L(category.label), tostring(count), red, green, blue, red, green, blue)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Klick: Verbrauch im Detail", 0.31, 0.79, 1)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        page.participantRows[index] = row
    end
    page.participantEmpty = CreateLabel(detailCard, "Wähle links eine Sitzung aus.", { muted = true, width = 400, height = 40, vertical = "TOP" })
    page.participantEmpty:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, -88)

    -- Die gespeicherte Spaltenordnung anwenden - Kopfzeile und Zellen wurden
    -- oben nur an ihren Standardplätzen erzeugt.
    self:ApplyStatColumnLayout()
end

function GC.UI:RefreshStatistics()
    if not GC.Client.combatAnalysis then
        local page = self.pages.STATISTICS
        if page and page.preparationText then
            page.preparationText:SetText(GC.RaidPreparation:ReportText())
            local height = math.max(390, (page.preparationText:GetStringHeight() or 390) + 24)
            page.preparationContent:SetHeight(height)
        end
        return
    end
    local page = self.pages.STATISTICS
    if not page then
        return
    end

    local monitor = GC.RaidMonitor
    local canControl = monitor:CanControlSession()
    local session = monitor.session
    if session then
        local participantCount = 0
        for _ in pairs(session.participants) do
            participantCount = participantCount + 1
        end
        -- Wie in BuildSummary zählen nur erkannte Bosskämpfe; so zeigt auch
        -- eine unter älterer Version gestartete Sitzung keine Trashzahlen.
        local pullCount = 0
        for _, pull in ipairs(session.pulls) do
            if pull.boss then
                pullCount = pullCount + 1
            end
        end
        page.sessionStatus:SetText("|cff59e695Sitzung läuft|r  •  " .. participantCount .. " Teilnehmer  •  "
            .. pullCount .. " Versuche\nGestartet von " .. (session.startedBy ~= "" and session.startedBy or "unbekannt")
            .. (session.zone ~= "" and ("  •  " .. session.zone) or ""))
        page.sessionButton:SetText(GC.L("Sitzung beenden"))
    else
        page.sessionStatus:SetText("|cff91a3b8Keine laufende Sitzung.|r\n"
            .. (canControl and "Du darfst eine Sitzung starten und beenden."
                or "Nur die in den Einstellungen freigegebenen Gildenränge dürfen Sitzungen steuern."))
        page.sessionButton:SetText(GC.L("Sitzung starten"))
    end
    SetButtonEnabled(page.sessionButton, canControl)
    SetButtonEnabled(page.requestButton, canControl)

    -- Je Zeile ein Abend, nicht eine Quelle. Wer denselben Abend live
    -- mitgeschnitten, aus Warcraft Logs geholt und aus der Logdatei importiert
    -- hat, soll ihn einmal in der Liste finden.
    local evenings = monitor:GetEvenings()
    page.sessionEmpty:SetShown(#evenings == 0)
    -- Gewaehlt wird ueber Kennung UND Quelle: Live- und Sync-Fassung desselben
    -- Abends teilen sich die Kennung, sind aber zwei Auswertungen.
    -- Eine ausgeblendete Fremdfassung darf nicht ausgewählt bleiben: Der
    -- Schlüssel wird auf die sichtbare Primärfassung des Abends zurückgeführt,
    -- ein ganz verschwundener Abend auf den ersten Eintrag.
    local selectedID = monitor:VisibleSummaryKey(evenings, monitor.selectedSessionID)
    if not selectedID then
        selectedID = evenings[1] and monitor:SummaryKey(evenings[1].summary)
    end
    monitor.selectedSessionID = selectedID

    -- Der scharfgeschaltete Löschknopf entschärft sich, sobald eine andere
    -- Sitzung gewählt wird - sonst löschte der zweite Klick die falsche.
    if page.deleteArmed and page.deleteArmed ~= selectedID then
        page.deleteArmed = nil
        page.deleteSessionButton:SetText(GC.L("Sitzung löschen"))
    end
    SetButtonEnabled(page.deleteSessionButton,
        #evenings > 0 and GC.Roster:CanAccessMemberCare())

    for index, row in ipairs(page.sessionRows) do
        local evening = evenings[index]
        row:SetShown(evening ~= nil)
        if evening then
            local summary = evening.summary
            local zone = summary.zone ~= "" and summary.zone or "Raid"
            -- Kompakt und einzeilig: Nur die Zusatzquellen ("+Logs"), nicht
            -- die volle Liste - "[Live+Logs]" brach in die zweite Zeile um.
            --
            -- Je Quellenart nur ein Zeichen. Liegt derselbe Abend von zwei
            -- Gildenmitgliedern vor, sind das zwei Sync-Auswertungen, aber eine
            -- Quellenart; "+Sync+Logs+Sync" nannte dieselbe Herkunft zweimal
            -- und machte die Zeile gerade dadurch zu lang.
            local extras = {}
            local seenMarks = {}
            for _, candidate in ipairs(evening.visibleSources) do
                local source = candidate.source or "LIVE"
                local mark = SESSION_SOURCE_MARK[monitor:SourceKind(source)] or "?"
                if source ~= "LIVE" and not seenMarks[mark] then
                    seenMarks[mark] = true
                    extras[#extras + 1] = mark
                end
            end
            -- Die laufende Sitzung ist gruen als "läuft" markiert: Sie steht
            -- seit ihrem Start in der Liste und laesst sich schon auswerten,
            -- waehrend sie laeuft. Kein Symbol - die WoW-Schrift zeichnet
            -- fuer Zeichen wie U+25CF nur einen leeren Kasten.
            row:SetText(FormatSessionDate(summary) .. "  " .. ShortZoneName(zone)
                .. (evening.live and "  |cff59e695läuft|r" or "")
                .. (#evening.visibleSources > 1 and #extras > 0
                    and ("  |cff4ec9ff+" .. table.concat(extras, "+") .. "|r") or ""))
            local active = false
            for _, candidate in ipairs(evening.sources) do
                active = active or monitor:SummaryKey(candidate) == selectedID
            end
            row:SetActive(active)
        end
    end

    local selected = monitor:GetSummaryByKey(selectedID)
    page.participantEmpty:SetShown(selected == nil)
    if selected then
        page.sessionHeadline:SetText(FormatSessionDate(selected)
            .. "  •  " .. FormatDuration((selected.endedAt or 0) - (selected.startedAt or 0))
            .. "  •  " .. (selected.pulls or 0) .. " Versuche, " .. (selected.kills or 0) .. " Siege, "
            .. (selected.wipes or 0) .. " Wipes  •  Quelle: "
            .. SessionSourceLabel(selected.source)
            -- Die Momentaufnahme der laufenden Sitzung sagt, was sie ist:
            -- Zwischenstand, kein abgeschlossener Abend.
            .. (selected.live and "  •  |cff59e695läuft – Zwischenstand|r" or "")
            -- Ein lückenhafter Mitschnitt sagt das von sich aus. Wer eine Zahl
            -- liest, soll nicht raten müssen, ob sie vollständig ist.
            .. ((selected.gaps or 0) > 0
                and ("  •  |cffffb840" .. selected.gaps .. " Lücke"
                    .. ((selected.gaps > 1) and "n" or "") .. "|r") or ""))
    else
        page.sessionHeadline:SetText(GC.L(""))
    end

    -- Die Quellenknöpfe erscheinen nur, wenn es wirklich mehr als eine gibt.
    -- Rechtsbündig, kurze Namen ("Logs" statt "Warcraft Logs"), und die
    -- gerade angezeigte Quelle ist als aktiv MARKIERT statt ausgegraut -
    -- ausgegraut las sich wie "nicht verfügbar", nicht wie "gewählt".
    local evening = selected and monitor:GetEveningOf(selectedID)
    local multiSource = evening ~= nil and #evening.visibleSources > 1
    page.sessionCompareButton:SetShown(multiSource)
    local rightOffset = -16
    if multiSource then
        page.sessionCompareButton:ClearAllPoints()
        page.sessionCompareButton:SetPoint("TOPRIGHT", page.sessionCompareButton:GetParent(),
            "TOPRIGHT", rightOffset, -14)
        rightOffset = rightOffset - 100
    end
    for index = #page.sessionSourceButtons, 1, -1 do
        local button = page.sessionSourceButtons[index]
        local candidate = multiSource and evening.visibleSources[index] or nil
        button.summaryID = candidate and monitor:SummaryKey(candidate) or nil
        button:SetShown(candidate ~= nil)
        if candidate then
            button:ClearAllPoints()
            button:SetPoint("TOPRIGHT", button:GetParent(), "TOPRIGHT", rightOffset, -14)
            rightOffset = rightOffset - 100
            -- Bei zwei fremden Mitschnitten desselben Abends sagt "Sync (24)"
            -- nichts darüber, wessen Fassung das ist. Der Name gehört deshalb
            -- auf den Knopf, sobald es einen gibt.
            local mark, who = SessionSourceMark(candidate.source)
            button:SetText((who and (who .. ": ") or (mark .. " "))
                .. "(" .. #(candidate.participants or {}) .. ")")
            SetButtonEnabled(button, true)
            button:SetActive(button.summaryID == selectedID)
        end
    end

    local sessionSeconds = selected
        and math.max(0, (selected.endedAt or 0) - (selected.startedAt or 0))
        or 0
    if selected and ENCOUNTER_TIME_SOURCES[GC.RaidMonitor:SourceKind(selected.source)] then
        -- Bei Logs ist die Anwesenheit reine Encounter-Zeit, Beginn/Ende
        -- beschreiben dagegen den ganzen Report inklusive Pausen und Trash.
        -- Der Prozentwert muss deshalb gegen die längste Encounter-Anwesenheit
        -- laufen, nicht gegen die deutlich längere Reportdauer.
        sessionSeconds = 0
        for _, participant in ipairs(selected.participants or {}) do
            sessionSeconds = math.max(sessionSeconds, tonumber(participant.seconds) or 0)
        end
    end

    -- Sortiert wird eine Kopie: Die gespeicherte Reihenfolge der Sitzung
    -- bleibt unangetastet, sonst wuerde ein Klick auf die Kopfzeile die
    -- Auswertung dauerhaft umbauen.
    local participants = {}
    for index, participant in ipairs(selected and selected.participants or {}) do
        participants[index] = participant
    end

    local SORT_VALUES = {
        name = function(p) return tostring(p.name or ""):lower() end,
        deaths = function(p) return p.deaths or 0 end,
        interrupts = function(p) return p.interrupts or 0 end,
        dispels = function(p) return p.dispels or 0 end,
        potions = function(p) return ((p.consumables or {}).POTION or 0) + ((p.consumables or {}).RUNE or 0) end,
        flasks = function(p) return (p.consumables or {}).FLASK or 0 end,
        elixirs = function(p) return (p.consumables or {}).ELIXIR or 0 end,
        food = function(p) return (p.consumables or {}).FOOD or 0 end,
        drums = function(p) return (p.consumables or {}).DRUM or 0 end,
    }

    local valueOf = page.sortKey and SORT_VALUES[page.sortKey]
    if valueOf then
        local descending = page.sortDescending
        table.sort(participants, function(left, right)
            local leftValue, rightValue = valueOf(left), valueOf(right)
            if leftValue == rightValue then
                -- Gleichstand nach Namen, damit die Reihenfolge stabil bleibt
                -- und nicht bei jedem Neuzeichnen springt.
                return tostring(left.name or "") < tostring(right.name or "")
            end
            if descending then
                return leftValue > rightValue
            end
            return leftValue < rightValue
        end)
    end
    -- Ohne aktive Spaltensortierung bleibt die gespeicherte Reihenfolge der
    -- Auswertung; die frühere Zeilen-Handordnung ist entfernt.
    page.displayedParticipants = participants
    page.selectedSummary = selected

    for _, header in ipairs(page.sortHeaders or {}) do
        if page.sortKey == header.sortKey then
            header:SetText(header.baseText .. (page.sortDescending and " v" or " ^"))
            SetTextColor(header.label, THEME.accent)
        else
            header:SetText(header.baseText)
            SetTextColor(header.label, THEME.muted)
        end
    end
    if selected and #participants == 0 then
        page.participantEmpty:SetText(GC.L("Für diese Sitzung wurden keine Teilnehmer erfasst."))
        page.participantEmpty:SetShown(true)
    elseif selected then
        page.participantEmpty:SetText(GC.L("Wähle links eine Sitzung aus."))
    end
    for index, row in ipairs(page.participantRows) do
        local participant = participants[index]
        row:SetShown(participant ~= nil)
        if participant then
            local consumables = participant.consumables or {}
            row.participant = participant
            row.sessionSeconds = sessionSeconds
            row.name:SetText(participant.name)
            row.name:SetTextColor(ClassColor(participant.classFile))

            -- Die Anwesenheit hat keine eigene Spalte mehr (Owner-Wunsch);
            -- sie steht im Tooltip der Zeile und im Detailfenster.
            row.deaths:SetText(participant.deaths or 0)
            row.interrupts:SetText(participant.interrupts or 0)
            row.dispels:SetText(participant.dispels or 0)
            -- Runen laufen bei den Traenken mit, Elixiere haben eine eigene
            -- Spalte. Oele und Steine stehen im Tooltip.
            row.potions:SetText((consumables.POTION or 0) + (consumables.RUNE or 0))
            local flaskCount = consumables.FLASK or 0
            local elixirCount = consumables.ELIXIR or 0
            local foodCount = consumables.FOOD or 0
            row.flasks:SetText(flaskCount)
            row.elixirs:SetText(elixirCount)
            row.food:SetText(foodCount)
            row.drums:SetText(consumables.DRUM or 0)
            -- Rot, wo die Raidvorbereitung fehlt (Owner-Wunsch): Essen zählt
            -- für sich; Fläschchen und Elixiere decken einander - ein
            -- Fläschchen ersetzt beide Elixiere, also ist nur BEIDES auf
            -- null wirklich unversorgt.
            local uncovered = flaskCount == 0 and elixirCount == 0
            SetTextColor(row.flasks, uncovered and THEME.danger or THEME.text)
            SetTextColor(row.elixirs, uncovered and THEME.danger or THEME.text)
            SetTextColor(row.food, foodCount == 0 and THEME.danger or THEME.text)
        else
            row.participant = nil
        end
    end
end

-- Masse der Spielerliste auf der Ausruestungsseite. Bis hierher entstand pro
-- geprueftem Spieler eine eigene Zeile: bei 500 gespeicherten Pruefungen also
-- 500 Rahmen samt Beschriftung und Texturen, obwohl in den 270 Pixel hohen
-- Scrollbereich nur elf davon passen. Jetzt gibt es einen festen Vorrat wie in
-- den uebrigen Listen der Datei (Teilnehmerliste und Verbrauchsprotokoll
-- arbeiten mit 40 bzw. 100), und beim Scrollen werden dieselben Zeilen
-- umgehaengt. 40 statt der noetigen elf, weil ein grosszuegiger Vorrat das
-- Umhaengen bei den ueblichen Gildengroessen ganz erspart.
local GEAR_PLAYER_ROW_POOL = 40
local GEAR_PLAYER_ROW_STEP = 25

local GEAR_VERDICT_STYLE = {
    OPTIMAL = { label = "Optimal", color = THEME.success },
    SOLID = { label = "Solide", color = THEME.accent },
    IMPROVABLE = { label = "Verbesserbar", color = THEME.warning },
    MISSING = { label = "Fehlt", color = THEME.danger },
    UNKNOWN = { label = "Unbekannt", color = THEME.muted },
    EMPTY = { label = "Leer", color = THEME.muted },
    -- Ohne diesen Eintrag fiel ein ausgenommener Slot auf UNKNOWN zurueck und
    -- stand als "Unbekannt" da, waehrend die Gruppenuebersicht denselben Slot
    -- "Ausnahme" nannte - zwei Namen fuer denselben Zustand.
    EXEMPT = { label = "Ausnahme", color = THEME.muted },
}

local GEAR_SEVERITY_COLOR = {
    PROBLEM = "ffff6166",
    WARNING = "ffffb840",
    OK = "ff59e695",
    INFO = "ff91a3b8",
}

-- Funde als eingefaerbte Zeilen, damit dieselbe Aufbereitung auf der
-- Ausruestungsseite und im persoenlichen Profil erscheint.
function GC.UI:FormatGearFindings(audit, maximumLines)
    local findings = GC.GearAudit:GetFindings(audit)
    local lines = {}
    for index, finding in ipairs(findings) do
        if maximumLines and index > maximumLines then
            break
        end
        lines[#lines + 1] = "|c" .. (GEAR_SEVERITY_COLOR[finding.severity] or GEAR_SEVERITY_COLOR.INFO)
            .. finding.text .. "|r"
    end
    return table.concat(lines, "\n")
end

function GC.UI:BuildGearPage()
    local page = self.pages.GEAR
    CreatePageTitle(page, "Ausrüstung",
        "Fehlende Verzauberungen, leere Pflichtslots und Sockel je Slot. Addon-Nutzer liefern aktuelle Eigendaten; Inspect bleibt der Rückfall für erreichbare Gruppenmitglieder. Es gibt bewusst keine Gesamtnote.")

    local controlCard = CreateCard(page)
    controlCard:SetSize(776, 96)
    controlCard:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -66)
    page.gearStatus = CreateLabel(controlCard, "", { width = 560, height = 46, vertical = "TOP" })
    page.gearStatus:SetPoint("TOPLEFT", controlCard, "TOPLEFT", 18, -14)
    page.gearAction = CreateLabel(controlCard, "", { width = 560, height = 26, vertical = "TOP" })
    page.gearAction:SetPoint("TOPLEFT", controlCard, "TOPLEFT", 18, -64)

    function page:SetGearStatus(message, ok)
        message = GC.Util.Trim(message)
        self.gearAction:SetText(message)
        SetTextColor(self.gearAction, ok == false and THEME.danger or THEME.success)
        if message ~= "" then
            GC:Print(message)
        end
    end

    page.scanButton = CreateButton(controlCard, "Gruppe prüfen", 150, 30, function()
        -- Öffnet die fokussierte Gruppenübersicht im eigenen Fenster
        -- (Owner-Wunsch) und stößt die Prüfung an; die Seite mit der
        -- Dauerliste bleibt unangetastet daneben bestehen.
        local ok, message = GC.GearAudit:StartRaidScan()
        page:SetGearStatus(message, ok)
        GC.UI:ShowGroupGearCheck()
        local frame = GC.UI.groupGearCheck
        if frame then
            frame.status:SetText(message or "")
            SetTextColor(frame.status, ok and THEME.success or THEME.danger)
        end
        GC.UI:RefreshGear()
    end, "PRIMARY")
    page.scanButton:SetPoint("TOPRIGHT", controlCard, "TOPRIGHT", -18, -14)

    page.selfButton = CreateButton(controlCard, "Eigene Ausrüstung", 150, 30, function()
        local ok, message = GC.GearAudit:AuditSelf()
        page:SetGearStatus(message, ok)
        GC.UI:RefreshGear()
    end)
    page.selfButton:SetPoint("TOPRIGHT", page.scanButton, "BOTTOMRIGHT", 0, -4)

    local listCard = CreateCard(page, "Geprüfte Spieler")
    listCard:SetSize(238, 358)
    listCard:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -172)

    -- Aufräumen auf Knopfdruck: Die Dauerliste sammelt sonst jeden je
    -- gesehenen Charakter, bis niemand mehr das Wesentliche findet.
    page.gearClearButton = CreateButton(listCard, "Leeren", 70, 22, function()
        local ok, message = GC.GearAudit:ClearAudits()
        page:SetGearStatus(message, ok)
        GC.UI:RefreshGear()
    end)
    page.gearClearButton:SetPoint("TOPRIGHT", listCard, "TOPRIGHT", -12, -10)

    -- Rangfilter mit echter Auswahl: Der Knopf klappt eine Häkchenliste aller
    -- Gildenränge auf (Owner-Wunsch). Eine "bis Rang X"-Schwelle taugte
    -- nicht - die Rangreihenfolge einer Gilde ist keine Wertigkeit.
    page.gearRankButton = CreateButton(listCard, "Ränge: alle", 214, 26, function()
        page:ToggleGearRankFlyout()
    end)
    page.gearRankButton:SetPoint("TOPLEFT", listCard, "TOPLEFT", 12, -42)

    function page:RefreshGearRankFlyout()
        local panel = page.gearRankFlyout
        if not panel then
            return
        end
        local ranks = GC.Roster:GetRankDefinitions()
        for index, toggle in ipairs(panel.rows) do
            local rank = ranks[index]
            toggle:SetShown(rank ~= nil)
            toggle.rankIndex = rank and rank.index or nil
            if rank then
                toggle.text:SetText(rank.name)
                toggle:SetChecked(GC.GearAudit:IsRankShown(rank.index))
                toggle:RefreshVisual()
            end
        end
        panel.title:SetText(#ranks > 0 and "Nur diese Ränge zeigen:"
            or "Noch keine Rangdaten - das Gildenroster lädt.")
        panel:SetSize(214, 46 + #ranks * 24 + 36)
    end

    function page:ToggleGearRankFlyout()
        local host = GC.UI.frame
        if not page.gearRankFlyout then
            -- Wie die Dropdown-Popups: ans Hauptfenster gehängt, sonst
            -- schneidet der Seiten-Scroller das Panel ab.
            local panel = CreatePanel(host, THEME.window, THEME.accent, "GuildCopilotForeverGearRankFlyout")
            panel:SetFrameStrata("DIALOG")
            panel:SetToplevel(true)
            panel.title = CreateLabel(panel, "", { muted = true, width = 186, height = 26,
                font = "GameFontNormalSmall", vertical = "TOP" })
            panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
            panel.rows = {}
            for index = 1, 10 do
                local rowIndex = index
                local toggle = CreateToggle(panel, "", function(checked)
                    local rankIndex = panel.rows[rowIndex].rankIndex
                    if rankIndex ~= nil then
                        GC.GearAudit:SetRankShown(rankIndex, checked)
                        GC.UI:RefreshGear()
                        page:RefreshGearRankFlyout()
                    end
                end)
                toggle:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -40 - ((rowIndex - 1) * 24))
                toggle:Hide()
                panel.rows[rowIndex] = toggle
            end
            panel.reset = CreateButton(panel, "Alle anzeigen", 120, 24, function()
                GC.GearAudit:ResetRankView()
                GC.UI:RefreshGear()
                page:RefreshGearRankFlyout()
            end)
            panel.reset:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 8)
            panel:Hide()
            page.gearRankFlyout = panel
            page:HookScript("OnHide", function()
                panel:Hide()
            end)
        end
        local panel = page.gearRankFlyout
        if panel:IsShown() then
            panel:Hide()
            return
        end
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", page.gearRankButton, "BOTTOMLEFT", 0, -2)
        local hostLevel = host.GetFrameLevel and host:GetFrameLevel() or 1
        panel:SetFrameLevel((hostLevel or 1) + 40)
        page:RefreshGearRankFlyout()
        panel:Show()
        if panel.Raise then
            panel:Raise()
        end
    end

    -- Unten in der Spielerkarte: die Rezept-Lücken der Gilde. Der Knopf
    -- nimmt der Liste eine Zeile - dieselbe Bauweise wie "Sitzung löschen"
    -- auf der Raidauswertungsseite.
    page.missingRecipesButton = CreateButton(listCard, "Rezept-Lücken der Gilde", 214, 26, function()
        GC.UI:ShowMissingRecipes()
    end)
    page.missingRecipesButton:SetPoint("BOTTOMLEFT", listCard, "BOTTOMLEFT", 12, 10)

    local playerScroll = CreateModernScrollFrame(listCard)
    playerScroll:SetPoint("TOPLEFT", listCard, "TOPLEFT", 12, -76)
    playerScroll:SetPoint("BOTTOMRIGHT", listCard, "BOTTOMRIGHT", -12, 44)
    local playerContent = CreateFrame("Frame", nil, playerScroll)
    playerContent:SetWidth(202)
    playerContent:SetHeight(1)
    playerScroll:SetScrollChild(playerContent)
    page.gearPlayerScroll = playerScroll
    page.gearPlayerContent = playerContent
    page.gearRows = {}

    -- Beim frischen Aufschlagen der Seite steht die Spielerliste oben
    -- (Owner-Wunsch) - sie merkte sich sonst die alte Scrollposition.
    -- Bewusst nur beim Anzeigen, nicht bei jeder Datenauffrischung, sonst
    -- springt die Liste beim Stöbern unter der Hand weg.
    page:HookScript("OnShow", function()
        playerScroll.targetScroll = nil
        playerScroll:SetVerticalScroll(0)
        playerScroll:UpdateModernThumb()
    end)

    function page:EnsureGearPlayerRow(index)
        if self.gearRows[index] then
            return self.gearRows[index]
        end
        local row = CreateButton(playerContent, "", 198, 23, function(self)
            -- Die Zeile zeigt die GEFILTERTE Liste; der Klick muss dieselbe
            -- Liste lesen, sonst wählt er bei aktivem Rangfilter den
            -- falschen Spieler.
            -- Seit dem festen Zeilenvorrat traegt die Zeile ihren Listenplatz
            -- in auditIndex. Der Erzeugungsindex taugt nicht mehr dafuer: nach
            -- dem Scrollen zeigt die erste Zeile laengst nicht mehr auf den
            -- ersten Eintrag.
            local audit = (page.gearAuditList or {})[self.auditIndex or 0]
            if audit then
                GC.GearAudit.selectedName = audit.name
                -- Beim Spielerwechsel oben anfangen, sonst haengt die Liste
                -- an der Scrollposition des vorherigen Spielers fest.
                if page.gearSlotScroll then
                    page.gearSlotScroll:SetVerticalScroll(0)
                    page.gearSlotScroll:UpdateModernThumb()
                end
                GC.UI:RefreshGear()
            end
        end)
        row:SetPoint("TOPLEFT", playerContent, "TOPLEFT", 0,
            -((index - 1) * GEAR_PLAYER_ROW_STEP))
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.label:SetJustifyH("LEFT")
        row.auditIndex = index
        -- Zunaechst verborgen: Der Vorrat steht schon, bevor die erste Pruefung
        -- vorliegt - sonst stuenden 40 leere Knoepfe in der Karte.
        row:Hide()
        self.gearRows[index] = row
        return row
    end

    -- Der Vorrat entsteht einmal beim Aufbau der Seite und waechst danach nie
    -- mehr - egal, wie viele Pruefungen gespeichert sind.
    for index = 1, GEAR_PLAYER_ROW_POOL do
        page:EnsureGearPlayerRow(index)
    end

    -- Haengt den Vorrat unter das gerade sichtbare Stueck der Liste. Die Zeilen
    -- stecken im Scrollkind, wandern also beim Scrollen mit; verschoben wird
    -- deshalb nur ihr Platz innerhalb des Scrollkinds.
    -- force: beim Auffrischen der Daten muss die Beschriftung in jedem Fall neu
    -- gesetzt werden. Beim Scrollen nicht - das weiche Scrollen loest
    -- OnVerticalScroll in jedem Bild aus, und solange dieselben Eintraege oben
    -- stehen, gibt es nichts umzuhaengen.
    function page:LayoutGearPlayerRows(force)
        local audits = self.gearAuditList or {}
        local scrolled = self.gearPlayerScroll:GetVerticalScroll() or 0
        local first = math.floor(scrolled / GEAR_PLAYER_ROW_STEP)
        first = math.max(0, math.min(first, #audits - GEAR_PLAYER_ROW_POOL))
        if not force and self.gearRowFirst == first then
            return
        end
        self.gearRowFirst = first
        local selectedName = GC.GearAudit.selectedName
        for offset = 1, GEAR_PLAYER_ROW_POOL do
            local row = self.gearRows[offset]
            if row then
                local auditIndex = first + offset
                local audit = audits[auditIndex]
                row.auditIndex = auditIndex
                row:SetShown(audit ~= nil)
                if audit then
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", self.gearPlayerContent, "TOPLEFT", 0,
                        -((auditIndex - 1) * GEAR_PLAYER_ROW_STEP))
                    local issues = GC.GearAudit:GetIssueCount(audit)
                    -- Grün heißt fertig, Rot heißt Arbeit (Owner-Wunsch) - so
                    -- ist die Liste auf einen Blick lesbar.
                    row:SetText(audit.name .. (issues > 0
                        and ("  •  |cffff6166" .. (issues == 1 and GC.L("1 Fund")
                            or GC.LFormat("{n} Funde", { n = issues })) .. "|r")
                        or "  •  |cff59e695ok|r"))
                    row:SetActive(audit.name == selectedName)
                end
            end
        end
    end

    playerScroll:HookScript("OnVerticalScroll", function()
        page:LayoutGearPlayerRows()
    end)
    -- Neue Daten aendern die Gesamthoehe; WoW schiebt die Scrollposition dabei
    -- selbst in den gueltigen Bereich zurueck. Ohne dieses Nachziehen stuenden
    -- die Zeilen danach an der alten Stelle.
    playerScroll:HookScript("OnScrollRangeChanged", function()
        page:LayoutGearPlayerRows(true)
    end)

    page.gearEmpty = CreateLabel(listCard, "Noch niemand geprüft.", { muted = true, width = 200, height = 40, vertical = "TOP" })
    page.gearEmpty:SetPoint("TOPLEFT", listCard, "TOPLEFT", 16, -84)

    local detailCard = CreateCard(page, "Slots")
    detailCard:SetSize(526, 358)
    detailCard:SetPoint("TOPLEFT", page, "TOPLEFT", 250, -172)
    -- Die Bruecke zur Werkstatt (Pro-Enchanters-Gedanke, gildenfest gemacht):
    -- Der erste verbesserbare EIGENE Slot bekommt einen Bestellknopf. Was
    -- dahintersteckt, sagt der Tooltip; der Klick oeffnet den ueblichen
    -- Auftragsdialog mit dem empfohlenen Rezept.
    page.gearOrderButton = CreateButton(detailCard, "Verzauberung bestellen", 200, 26, function()
        local target = page.gearOrderTarget
        if target and GC.UI.OpenOrderCreateDialog then
            GC.UI:OpenOrderCreateDialog(target.recipeKey)
        end
    end, "PRIMARY")
    page.gearOrderButton:SetPoint("TOPRIGHT", detailCard, "TOPRIGHT", -14, -8)
    page.gearOrderButton:Hide()
    page.gearOrderButton:HookScript("OnEnter", function(button)
        local target = page.gearOrderTarget
        if not GameTooltip or not target then
            return
        end
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText(GC.L("Empfehlung des Regelsatzes"))
        GameTooltip:AddLine(target.slotLabel .. ": " .. (target.ruleName or "?"), 1, 1, 1, true)
        GameTooltip:AddLine("Können: " .. table.concat(target.crafters or {}, ", "),
            0.57, 0.64, 0.72, true)
        GameTooltip:Show()
    end)
    page.gearOrderButton:HookScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    page.gearHeadline = CreateLabel(detailCard, "", { muted = true, width = 480, height = 18 })
    page.gearHeadline:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, -44)
    page.gearFindings = CreateLabel(detailCard, "", { width = 488, height = 52, vertical = "TOP" })
    page.gearFindings:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, -64)

    -- Der Hinweis ist die einzige Spalte mit ganzen Saetzen und war mit 214
    -- Pixeln die schmalste Erzaehlflaeche der Seite. Slot und Sockel geben
    -- Platz ab ("Handgelenke" und "1/2" brauchen keine Reserve), der Hinweis
    -- waechst auf 240 Pixel - was dann noch abgeschnitten ist, steht
    -- vollstaendig im Zeilentooltip.
    local gearHeaders = {
        { text = "SLOT", x = 18, width = 96 },
        { text = "BEWERTUNG", x = 119, width = 88 },
        { text = "SOCKEL", x = 211, width = 44 },
        { text = "HINWEIS", x = 259, width = 240 },
    }
    for _, headerDefinition in ipairs(gearHeaders) do
        local headerLabel = CreateLabel(detailCard, headerDefinition.text, {
            muted = true,
            font = "GameFontNormalSmall",
            width = headerDefinition.width,
        })
        headerLabel:SetPoint("TOPLEFT", detailCard, "TOPLEFT", headerDefinition.x, -122)
    end

    local scroll = CreateModernScrollFrame(detailCard)
    scroll:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 14, -142)
    scroll:SetPoint("BOTTOMRIGHT", detailCard, "BOTTOMRIGHT", -16, 14)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(492)
    -- Genau so hoch wie die Zeilen brauchen. Vorher standen 560 fest im Code,
    -- also rund hundert Pixel Leerraum, in den man hineinscrollen konnte.
    content:SetHeight(#GC.GearSlots * 27)
    scroll:SetScrollChild(content)
    page.gearSlotScroll = scroll

    page.gearSlotRows = {}
    for index = 1, #GC.GearSlots do
        local row = CreateButton(content, "", 490, 25, function(_, mouseButton)
            local entry = page.gearSlotEntries and page.gearSlotEntries[index]
            if not entry then
                return
            end

            -- Rechtsklick nimmt den Slot aus der Wertung: Farmgear,
            -- Widerstandsteil, Encounter-Set. Das geht nur fuer die eigene
            -- Ausruestung - ueber fremde Slots entscheidet jeder selbst.
            if mouseButton == "RightButton" then
                local ownName = GC.Util.PlayerIdentityName(GC:GetPlayerFullName())
                if GC.Util.NormalizeName(GC.GearAudit.selectedName or "")
                    ~= GC.Util.NormalizeName(ownName) then
                    page:SetGearStatus(
                        "Ausnahmen setzt jeder für seine eigene Ausrüstung.", false)
                    return
                end
                local exempted, exemptMessage = GC.GearAudit:CycleSlotException(entry.key)
                page:SetGearStatus(exemptMessage, exempted)
                GC.UI:RefreshGear()
                return
            end

            -- Bewertet wird fuer die Spec des gerade gewaehlten Spielers.
            -- Ohne bekannte Spec faellt es auf die allgemeine Regel zurueck.
            local audit = GC.GearAudit:GetAudit(GC.GearAudit.selectedName)
            local ok, message = GC.GearAudit:CycleEnchantRule(
                entry.enchantID, entry.enchantName, audit and audit.specKey)
            page:SetGearStatus(message, ok)
            GC.UI:RefreshGear()
        end)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        SetTextureColor(row.background, index % 2 == 0 and THEME.input or THEME.card)
        row.border:Hide()
        row.label:Hide()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((index - 1) * 27))
        row.slot = CreateLabel(row, "", { width = 96, height = 25 })
        row.slot:SetPoint("LEFT", row, "LEFT", 5, 0)
        row.verdict = CreateLabel(row, "", { width = 88, height = 25 })
        row.verdict:SetPoint("LEFT", row, "LEFT", 106, 0)
        row.sockets = CreateLabel(row, "", { width = 44, height = 25 })
        row.sockets:SetPoint("LEFT", row, "LEFT", 198, 0)
        row.reason = CreateLabel(row, "", { width = 240, height = 25, muted = true })
        row.reason:SetPoint("LEFT", row, "LEFT", 246, 0)

        -- Der Hinweis passt trotz breiterer Spalte nicht immer ganz hinein.
        -- Abgeschnitten wird nur die Anzeige, im Tooltip steht er vollstaendig.
        row:HookScript("OnEnter", function(self)
            local entry = page.gearSlotEntries and page.gearSlotEntries[index]
            if not entry or not GameTooltip then
                return
            end
            AnchorRowTooltip(self)
            GameTooltip:SetText(entry.label or "")
            if entry.reason and entry.reason ~= "" then
                GameTooltip:AddLine(entry.reason, 1, 1, 1, true)
            end
            if (entry.emptySockets or 0) > 0 then
                GameTooltip:AddLine(entry.emptySockets .. " leere Sockel", 1, 0.38, 0.4, true)
            end
            GameTooltip:Show()
        end)
        row:HookScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        page.gearSlotRows[index] = row
    end
    page.gearRatingHint = CreateLabel(detailCard,
        -- Kein Pfeilzeichen: Die WoW-Schriftart kennt es nicht und zeichnet
        -- statt dessen leere Kaesten.
        "Linksklick bewertet: Optimal, Solide, Verbesserbar, keine Bewertung. "
            .. "Rechtsklick nimmt den eigenen Slot aus der Wertung.",
        { muted = true, font = "GameFontNormalSmall", width = 488, height = 16 })
    page.gearRatingHint:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, -104)

    page.gearSlotEmpty = CreateLabel(detailCard, "Wähle links einen Spieler aus.", { muted = true, width = 400, height = 40, vertical = "TOP" })
    page.gearSlotEmpty:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 18, -66)
end

function GC.UI:RefreshGear()
    local page = self.pages.GEAR
    if not page then
        return
    end

    local audits = GC.GearAudit:GetAudits()
    -- Zwei getrennte Quellen: die mitgelieferte Regelliste und die Regeln, die
    -- die Gilde selbst gepflegt hat. Die Statuszeile hat frueher nur die erste
    -- gezaehlt und deshalb auch dann "leer" gemeldet, wenn laengst gildeneigene
    -- Bewertungen vorlagen.
    local shippedRules = 0
    for _ in pairs(GC.EnchantRuleSet.rules) do
        shippedRules = shippedRules + 1
    end
    local guildRules = 0
    for _ in pairs(GC.DB:GetGuild().enchantRules or {}) do
        guildRules = guildRules + 1
    end
    local overview = GC.GearAudit:GetOverview()
    -- Der gespeicherte Status ist einer von wenigen festen Saetzen; er und
    -- alle Zaehlbausteine laufen einzeln durch die Sprachschicht.
    local statusText = GC.L(GC.GearAudit.status)
    if statusText == "" then
        statusText = GC.L(overview.players > 0 and "Bereit." or "Noch keine Prüfung gelaufen.")
    end
    if overview.players > 0 then
        statusText = statusText .. "  •  "
            .. GC.LFormat("{n} geprüft, davon {m} ohne Funde",
                { n = overview.players, m = overview.clean })
        if overview.missingEnchants > 0 then
            statusText = statusText .. "  •  |cffff6166"
                .. GC.LFormat("{n} fehlende Verzauberungen", { n = overview.missingEnchants }) .. "|r"
        end
        if overview.emptySockets > 0 then
            statusText = statusText .. "  •  |cffff6166"
                .. GC.LFormat("{n} leere Sockel", { n = overview.emptySockets }) .. "|r"
        end
        if overview.emptySlots > 0 then
            statusText = statusText .. "  •  |cffffb840"
                .. GC.LFormat("{n} leere Pflichtslots", { n = overview.emptySlots }) .. "|r"
        end
        if overview.unreadableSlots > 0 then
            statusText = statusText .. "  •  |cffffb840"
                .. GC.LFormat("{n} noch nicht lesbare Slots", { n = overview.unreadableSlots }) .. "|r"
        end
    end
    -- Kurz genug fuer die Statuszeile: Die lange Fassung ("Regelsatz v2 mit
    -- 51 Verzauberungen und 26 gildeneigene Bewertungen. Alles Übrige ...")
    -- brach in eine vierte Zeile um, und die schnitt das Label ab - zu lesen
    -- war "gilt au…".
    local ruleParts = {}
    if shippedRules > 0 then
        ruleParts[#ruleParts + 1] = GC.LFormat("Regelsatz v{v} ({n})",
            { v = GC.EnchantRuleSet.version, n = shippedRules })
    end
    if guildRules > 0 then
        ruleParts[#ruleParts + 1] = guildRules == 1 and GC.L("1 eigene Bewertung")
            or GC.LFormat("{n} eigene Bewertungen", { n = guildRules })
    end

    local ruleLine
    if #ruleParts > 0 then
        ruleLine = GC.Util.JoinGerman(ruleParts) .. "."
        if GC.GearAudit:AcceptsUnratedEnchants() then
            ruleLine = ruleLine .. " " .. GC.L("Unbewertetes gilt als in Ordnung.")
        end
    elseif GC.GearAudit:AcceptsUnratedEnchants() then
        ruleLine = GC.L("|cff7ac943Automatik aktiv:|r keine Bewertungen hinterlegt, deshalb gilt jede vorhandene"
            .. " Verzauberung als in Ordnung. Gemeldet werden fehlende Verzauberungen und leere Sockel.")
    else
        ruleLine = GC.L("|cffffb840Der Regelsatz ist noch leer: fehlende Verzauberungen und leere Sockel werden"
            .. " exakt erkannt, vorhandene Verzauberungen bleiben \"Unbekannt\".|r")
    end
    page.gearStatus:SetText(statusText .. "\n" .. ruleLine)

    -- Rangfilter: Nur Mitglieder der angehakten Ränge bleiben in der Liste;
    -- der eigene Charakter steht immer drin. Wer nicht (mehr) im Roster
    -- auftaucht, fällt bei aktivem Filter heraus.
    local rankView = GC.GearAudit:GetRankView()
    if rankView.configured then
        local ownKey = GC.Util.NormalizeName(GC.Util.PlayerIdentityName(GC:GetPlayerFullName()))
        local filtered = {}
        for _, audit in ipairs(audits) do
            local member = GC.Roster:GetMember(audit.name)
            local rankIndex = member and tonumber(member.rankIndex)
            if (rankIndex ~= nil and GC.GearAudit:IsRankShown(rankIndex))
                or GC.Util.NormalizeName(GC.Util.PlayerIdentityName(audit.name or "")) == ownKey then
                filtered[#filtered + 1] = audit
            end
        end
        audits = filtered
    end
    page.gearAuditList = audits

    local rankLabel = "Ränge: alle"
    if rankView.configured then
        local ranks = GC.Roster:GetRankDefinitions()
        local shownCount = 0
        for _, rank in ipairs(ranks) do
            if GC.GearAudit:IsRankShown(rank.index) then
                shownCount = shownCount + 1
            end
        end
        rankLabel = "Ränge: " .. shownCount .. " von " .. #ranks
    end
    page.gearRankButton:SetText(rankLabel)

    page.gearEmpty:SetShown(#audits == 0)
    local selectedName = GC.GearAudit.selectedName
    local selectedVisible = false
    for _, audit in ipairs(audits) do
        if audit.name == selectedName then
            selectedVisible = true
        end
    end
    if not selectedVisible then
        selectedName = audits[1] and audits[1].name
        GC.GearAudit.selectedName = selectedName
    end

    -- Die Hoehe bleibt die der GESAMTEN Liste, damit der Scrollbalken die
    -- richtige Laenge und Position bekommt. Zeilen gibt es trotzdem nur
    -- GEAR_PLAYER_ROW_POOL viele; LayoutGearPlayerRows haengt sie an die
    -- Stelle, die gerade zu sehen ist.
    page.gearPlayerContent:SetHeight(math.max(1, #audits * GEAR_PLAYER_ROW_STEP))
    -- Kein automatisches Mitscrollen mehr: Wer einen Spieler anklickt, hat
    -- ihn bereits vor Augen - der Sprung riss die Liste nur unter der Hand
    -- weg (Owner-Rückmeldung).
    page.gearPlayerScroll:UpdateModernThumb()
    page:LayoutGearPlayerRows(true)

    local selected = GC.GearAudit:GetAudit(selectedName)
    page.gearSlotEmpty:SetShown(selected == nil)
    if selected then
        -- "vor 8157 Min." liest niemand freiwillig um; ab zwei Stunden wird
        -- in Stunden gerechnet, ab zwei Tagen in Tagen.
        local age = math.max(0, GC.Util.Now() - (selected.inspectedAt or 0))
        local ageText
        if age < 120 * 60 then
            ageText = "vor " .. math.floor(age / 60) .. " Min."
        elseif age < 48 * 3600 then
            ageText = "vor " .. math.floor(age / 3600) .. " Std."
        else
            ageText = "vor " .. math.floor(age / 86400) .. " Tagen"
        end
        local sourceLabel = GC.L(selected.source == "SELF" and "Eigene Ausrüstung"
            or selected.source == "SYNC" and "Addon-Abgleich"
            or "Inspect")
        page.gearHeadline:SetText(sourceLabel
            .. "  •  " .. ageText .. "  •  "
            .. (selected.specKey and GC.GearAudit:DescribeSpec(selected.specKey)
                or "|cffffb840Spec unbekannt|r"))
        page.gearFindings:SetText(self:FormatGearFindings(selected, 3))
    else
        page.gearHeadline:SetText(GC.L(""))
        page.gearFindings:SetText(GC.L(""))
    end

    local slots = selected and selected.slots or {}
    page.gearSlotEntries = slots
    page.gearRatingHint:SetShown(selected ~= nil and GC.GearAudit:CanEditEnchantRules())
    if selected and GC.GearAudit:CanEditEnchantRules() then
        page.gearRatingHint:SetText(selected.specKey
            and ("Klick auf eine Zeile bewertet für |cff4ec9ff"
                .. GC.GearAudit:DescribeSpec(selected.specKey)
                .. "|r: Optimal, Solide, Verbesserbar, keine Bewertung.")
            or "Spec unbekannt – ein Klick bewertet für alle Specs.")
    end

    -- Die Bruecke zur Werkstatt: Fuer den EIGENEN Charakter empfiehlt der
    -- erste verbesserbare Slot, was der Regelsatz vorsieht und was die Gilde
    -- herstellen kann. Fremde Funde bleiben ohne Knopf - bestellen kann nur
    -- jeder fuer sich.
    page.gearOrderTarget = nil
    if selected and GC.Util.NormalizeName(selected.name or "")
        == GC.Util.NormalizeName(GC:GetPlayerFullName()) then
        for _, entry in ipairs(slots) do
            if entry.verdict == "MISSING" or entry.verdict == "IMPROVABLE" then
                local orderable = GC.GearAudit:GetOrderableEnchant(entry.key, selected.specKey)
                if orderable then
                    page.gearOrderTarget = {
                        recipeKey = orderable.recipeKey,
                        ruleName = orderable.rule.name,
                        slotLabel = entry.label,
                        crafters = orderable.entry.crafters,
                    }
                    break
                end
            end
        end
    end
    if page.gearOrderButton then
        page.gearOrderButton:SetShown(page.gearOrderTarget ~= nil)
        if page.gearOrderTarget then
            page.gearOrderButton:SetText("Bestellen: " .. page.gearOrderTarget.slotLabel)
        end
    end
    for index, row in ipairs(page.gearSlotRows) do
        local entry = slots[index]
        row:SetShown(entry ~= nil)
        if entry then
            local style = GEAR_VERDICT_STYLE[entry.verdict] or GEAR_VERDICT_STYLE.UNKNOWN
            row.slot:SetText(entry.label)
            row.verdict:SetText(GC.L(style.label))
            SetTextColor(row.verdict, style.color)
            local emptySockets = entry.emptySockets or 0
            row.sockets:SetText(emptySockets > 0 and ("|cffff6166" .. emptySockets .. " leer|r") or "–")
            row.reason:SetText(entry.reason or "")
        end
    end
end

-- Zustand des Gildenabgleichs in einem Satz neben der Version.
--
-- "synchron" heisst hier ausdruecklich NICHT mehr "alle haben dieselbe
-- Addon-Version". Genau das stand bis 0.9.85 dort und war die haeufigste
-- Verwechslung: Der Kopf meldete "alle synchron", waehrend unten noch achtzig
-- Pakete unterwegs waren. Die Version steht jetzt als Version da, und ob die
-- Daten vollstaendig sind, sagt derselbe Zyklus wie der Balken in der Werkstatt.
function GC.UI:RefreshSyncBadge()
    local badge = self.syncBadge
    if not badge then
        return
    end

    -- Dieselbe Zahl wie die Kachel "Mit Addon" in der Uebersicht: Sie zaehlt
    -- den eigenen Charakter mit. Zwei verschiedene Zahlen fuer dieselbe Sache
    -- auf einem Bildschirm sind schlimmer als eine unscharfe.
    local stats = GC.Sync:GetAddonUserStats()
    local known = stats.known or 1
    -- Gezaehlt werden Spieler, nicht Charaktere: drei Twinks desselben Spielers
    -- sind ein Nutzer. Die Charakterzahl steht nur daneben, wenn sie abweicht.
    local players = stats.players or known
    local differing = (stats.outdated or 0) + (stats.ahead or 0)
    local characterNote = known > players and (" (" .. known .. " Chars)") or ""
    local status = GC.Sync:GetSyncStatus()

    if status.state == "RUNNING" then
        badge:SetText("|cff2ed9e6• "
            .. GC.LFormat("Abgleich läuft … {p} %", { p = status.percent }) .. "|r")
    elseif status.state == "INCOMPLETE" then
        badge:SetText(GC.L("|cffff6266• Abgleich unvollständig|r"))
    elseif players <= 1 then
        badge:SetText(GC.L("|cff8b98a5• kein anderer Nutzer erkannt|r"))
    elseif differing > 0 then
        badge:SetText("|cffffb840• "
            .. GC.LFormat("{n} Nutzer{chars}, {d} mit anderer Version",
                { n = players, chars = characterNote, d = differing }) .. "|r")
    elseif status.state == "SYNCED" then
        -- "Daten vollstaendig" nur, wenn keine Bestandsluecke bekannt ist:
        -- Sonst stand genau diese Zeile gruen ueber einem Drittel des Katalogs,
        -- waehrend die Rezepte der Offline-Spieler schlicht fehlten.
        local coverage = status.coverage
        if coverage and (coverage.professions or 0) > 0 then
            badge:SetText("|cffffb840• "
                .. GC.LFormat("{n} Nutzer{chars}, Bestand lückenhaft",
                    { n = players, chars = characterNote }) .. "|r")
        else
            badge:SetText("|cff59e695• "
                .. GC.LFormat("{n} Nutzer{chars}, Daten vollständig",
                    { n = players, chars = characterNote }) .. "|r")
        end
    else
        badge:SetText("|cff8b98a5• " .. players .. " Nutzer" .. characterNote
            .. ", gleiche Version|r")
    end
end

-- Der Hinweis auf eine neuere Fassung steht dort, wo ohnehin die eigene
-- Version steht: in der Kopfzeile unter dem Namen. Die Chatzeile aus
-- GC.Sync:NoteSeenVersion kommt einmal und scrollt weg; wer sie verpasst hat,
-- findet die Zahl beim naechsten Blick ins Fenster wieder.
function GC.UI:RefreshUpdateHint()
    local frame = self.frame
    if not frame or not frame.subtitle then
        return
    end
    local update = GC.Sync and GC.Sync.GetAvailableUpdate and GC.Sync:GetAvailableUpdate()
    local text = GC.Client.label .. "  •  v" .. GC.Constants.VERSION
    if update then
        text = text .. "  •  |cffffb840"
            .. GC.LFormat("Version {new} verfügbar", { new = update }) .. "|r"
    end
    frame.subtitle:SetText(text)
end

-- === Seiten nur zeichnen, wenn sie jemand sieht ==========================
--
-- Bis 0.9.41 baute jeder Aufruf alle dreizehn Seiten neu auf - bei jedem Ein-
-- und Ausloggen eines Gildenmitglieds, bei jedem eingehenden Profil, und auch
-- bei geschlossenem Fenster. Genau daraus entstanden die gemeldeten Ruckler
-- zur Prime Time; mit der Synchronisation selbst hatte das nichts zu tun.
--
-- Gezeichnet wird jetzt nur die sichtbare Seite. Die uebrigen merken sich, dass
-- sie veraltet sind, und holen es beim Aufschlagen nach. Die Daten liegen
-- ohnehin in der Datenbank - verloren geht nichts, nur der Neuaufbau wartet.
local PAGE_REFRESH = {
    OVERVIEW = "RefreshDashboard",
    SETTINGS = "RefreshSettings",
    ROSTER = "RefreshRoster",
    MEMBERCARE = "RefreshMemberCare",
    WORKSHOP = "RefreshWorkshop",
    SUGGESTIONS = "RefreshSuggestions",
    RECRUITMENT = "RefreshRecruitment",
    POST = "RefreshPost",
    INBOX = "RefreshInbox",
    GUILD = "RefreshGuild",
    WCL = "RefreshWarcraftLogs",
    STATISTICS = "RefreshStatistics",
    GEAR = "RefreshGear",
    RAIDSEARCH = "RefreshRaidSearch",
}

function GC.UI:IsVisible()
    return self.frame ~= nil and self.frame:IsShown() == true
end

function GC.UI:RefreshPage(pageKey)
    local method = PAGE_REFRESH[pageKey]
    if not method or not self.frame then
        return
    end
    self.stalePages = self.stalePages or {}
    self.stalePages[pageKey] = nil
    GC.Perf:Measure("Seite " .. pageKey, self[method], self)
end

-- Eine Seite gilt als veraltet. Ist sie gerade zu sehen, wird sie kurz darauf
-- neu gezeichnet, sonst beim naechsten Aufschlagen.
--
-- "Kurz darauf" statt sofort: Invalidate wird ausschliesslich von
-- Datenaenderungen gerufen, nie von Klicks - und Daten kommen in Schueben.
-- Ein Gildenabgleich zur Prime Time liefert mehrere Pakete pro Sekunde, und
-- jedes zeichnete die offene Seite komplett neu. Jetzt sammelt ein kurzer
-- Timer den Schub ein und zeichnet einmal. Klicks gehen weiter ueber
-- ShowPage/RefreshPage und bleiben unmittelbar.
local REPAINT_DELAY = 0.25

function GC.UI:Invalidate(...)
    if not self.frame then
        return
    end
    self.stalePages = self.stalePages or {}
    local repaint = false
    for index = 1, select("#", ...) do
        local pageKey = select(index, ...)
        if PAGE_REFRESH[pageKey] then
            self.stalePages[pageKey] = true
            if pageKey == self.activePage and self:IsVisible() then
                repaint = true
            end
        end
    end
    if self.headerStale and self:IsVisible() then
        repaint = true
    end
    if not repaint or self.repaintPending then
        return
    end
    if not C_Timer or type(C_Timer.After) ~= "function" then
        if self.headerStale then
            self.headerStale = nil
            self:RefreshSyncBadge()
            self:RefreshNavigationAccess()
        end
        self:RefreshPage(self.activePage)
        return
    end
    self.repaintPending = true
    C_Timer.After(REPAINT_DELAY, function()
        GC.UI.repaintPending = false
        -- Inzwischen kann die Seite gewechselt oder das Fenster zu sein.
        -- RefreshPage raeumt den Veraltet-Merker der gezeichneten Seite ab;
        -- eine nicht mehr aktive Seite behaelt ihren und wird beim naechsten
        -- Aufschlagen nachgeholt.
        if not GC.UI:IsVisible() then
            return
        end
        if GC.UI.headerStale then
            GC.UI.headerStale = nil
            GC.UI:RefreshSyncBadge()
            GC.UI:RefreshNavigationAccess()
        end
        local active = GC.UI.activePage
        if GC.UI.stalePages and GC.UI.stalePages[active] then
            GC.UI:RefreshPage(active)
        end
    end)
end

-- Alle Seiten veralten lassen, ohne sofort zu zeichnen. Fuer Ereignisse, die
-- alles betreffen und trotzdem in Schueben kommen - der Sammel-Timer aus
-- Invalidate faengt sie ab. Refresh() bleibt der Weg fuer Klicks: Wer das
-- Fenster oeffnet, will den Stand sofort sehen und nicht in einer Viertelsekunde.
function GC.UI:InvalidateAll()
    if not self.frame then
        return
    end
    self.stalePages = self.stalePages or {}
    for pageKey in pairs(PAGE_REFRESH) do
        self.stalePages[pageKey] = true
    end
    -- Der Fensterkopf haengt an keiner Seite und wird deshalb eigens
    -- vorgemerkt; gezeichnet wird er zusammen mit der Seite im selben Takt.
    self.headerStale = true
    -- Der Sammel-Timer haengt an der sichtbaren Seite; sie ist ohnehin schon
    -- als veraltet vorgemerkt, der Aufruf loest nur das Zeichnen aus.
    self:Invalidate(self.activePage)
end

function GC.UI:Refresh()
    if not self.frame then
        return
    end
    self.stalePages = self.stalePages or {}
    for pageKey in pairs(PAGE_REFRESH) do
        self.stalePages[pageKey] = true
    end
    if not self:IsVisible() then
        -- Bei geschlossenem Fenster gibt es nichts zu zeichnen. Der
        -- Werbebalken haengt nicht daran, er frischt sich selbst auf.
        return
    end
    self:RefreshSyncBadge()
    self:RefreshNavigationAccess()
    self:RefreshPage(self.activePage)
end

-- === Werbebalken ===========================================================
--
-- Kleines, verschiebbares Fenster nur fuer das Posten: bestaetigter Text,
-- Countdown je Kanal und ein Knopf. Gesendet wird ausschliesslich im Kontext
-- einer echten Eingabe - per Klick auf den Knopf oder, mit eingeschalteter
-- Automatik, beim naechsten Tastendruck. Ein Countdown loest nie selbst aus,
-- er schaltet nur frei beziehungsweise schaerft den Tastatur-Lauscher.

-- === Raidsuche =============================================================
--
-- Die Seite zum Konzept docs/KONZEPT-raidsuche-lfm.md: links der Suchzettel
-- und der daraus abgeleitete Spruch, rechts Soll/Ist der Besetzung und der
-- Zulauf. Die Logik liegt vollstaendig in RaidSearch.lua; hier wird nur
-- gezeichnet und geklickt.

local RAIDSEARCH_RESPONSE_ROWS = 4

local RAIDSEARCH_ROLE_ROWS = {
    { role = "TANK", label = "Tanks" },
    { role = "HEALER", label = "Heiler" },
    { role = "DAMAGER", label = "DD" },
}

-- Kurze Kanalbeschriftungen: In die zwei Kaestchenzeilen der Spruchkarte
-- passen keine Woerter wie "Gildenrekrutierung".
local RAIDSEARCH_CHANNEL_LABEL = {
    LFG = "LFG",
    TRADE = "Handel",
    GENERAL = "Allg.",
    RECRUITMENT = "Rekrut.",
    GUILD = "Gilde",
}

local function FormatDateGerman(iso)
    local year, month, day = tostring(iso or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not year then
        return tostring(iso or "")
    end
    return day .. "." .. month .. "." .. year
end

-- Der Zustand einer Antwort, wie die Zeile ihn zeigt. DABEI wird live aus der
-- Gruppe abgeleitet und nie gespeichert - wer die Gruppe verlaesst, faellt
-- von selbst auf seinen letzten gespeicherten Zustand zurueck.
local function ResponseStateLabel(response)
    if GC.RaidSearch:IsInCurrentGroup(response.name) then
        return "DABEI", THEME.success
    end
    if response.state == "EINGELADEN" then
        return "EINGELADEN", THEME.accent
    end
    if response.state == "ANGESCHRIEBEN" then
        return "ANGESCHRIEBEN", THEME.muted
    end
    return "NEU", THEME.warning
end

function GC.UI:BuildRaidSearchPage()
    local page = self.pages.RAIDSEARCH
    -- Der Untertitel bleibt schmaler als die Standardbreite: rechts daneben
    -- stehen die Kopfknoepfe, und ein Text HINTER Knoepfen liest sich nicht
    -- (Gilden-Screenshot 0.9.140).
    local _, pageHelp = CreatePageTitle(page, "Raidsuche",
        "Raid zusammenstellen, Suchspruch posten und den Zulauf verwalten"
        .. " — Antworten auf die laufende Suche landen rechts, nicht im Bewerber-Postfach.")
    pageHelp:SetWidth(520)

    -- Kopfzeile: nur Zettel anlegen und Suche beenden. Die beiden
    -- Vorlagen-Dialoge oeffnen an den Karten, zu denen sie gehoeren.
    page.newButton = CreateButton(page, "Neue Suche", 104, 26, function()
        local plan = GC.RaidSearch:GetPlan()
        if plan and plan.status == "SUCHT" then
            -- Ein Klick beendet nichts stillschweigend: Erst scharfschalten,
            -- der zweite Klick raeumt wirklich ab (Muster "Alle löschen").
            if not page.newArmed then
                page.newArmed = true
                page.newButton:SetText("Wirklich neu?")
                return
            end
        end
        page.newArmed = nil
        GC.RaidSearch:NewPlan()
        GC.UI:RefreshRaidSearch()
    end)
    page.newButton:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    page.endButton = CreateButton(page, "Suche beenden", 116, 26, function()
        GC.RaidSearch:EndSearch()
        GC.UI:RefreshRaidSearch()
    end)
    page.endButton:SetPoint("RIGHT", page.newButton, "LEFT", -8, 0)

    -- Ein Knopf blendet den Suchbalken ausdruecklich ein und aus. Ohne ihn kam
    -- ein mit seinem × weggeklickter Balken bei laufender Suche erst beim
    -- naechsten "Suche starten" zurueck. Er sitzt UNTER dem Knopfpaar: rechts
    -- neben dem 520 breiten Hilfetext ist fuer keine dritte Beschriftung in der
    -- Kopfzeile Platz. Er zeigt sich nur waehrend einer Suche - sonst gibt es
    -- keinen Balken. (Der Balken selbst bleibt MEDIUM-Strata: bei offenem
    -- Hauptfenster steckt er dahinter, sichtbar wird er beim Minimieren.)
    page.barToggle = CreateButton(page, "Suchbalken einblenden", 228, 22, function()
        GC.UI:ToggleRaidSearchBar()
        GC.UI:RefreshRaidSearch()
    end)
    page.barToggle:SetPoint("TOPRIGHT", page.newButton, "BOTTOMRIGHT", 0, -6)

    -- === Der Suchzettel ====================================================
    local sheet = CreateCard(page, "Suchzettel")
    sheet:SetSize(380, 316)
    sheet:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -66)
    page.sheet = sheet

    -- Die Zettel-Vorlagen wohnen an ihrer Karte, nicht in der Kopfzeile.
    page.templatesButton = CreateButton(sheet, "Vorlagen", 82, 22, function()
        GC.UI:ToggleRaidSearchTemplates()
    end)
    page.templatesButton:SetPoint("TOPRIGHT", sheet, "TOPRIGHT", -14, -12)

    local function SheetLabel(text, y)
        local label = CreateLabel(sheet, text, { muted = true, width = 86, height = 26 })
        label:SetPoint("TOPLEFT", sheet, "TOPLEFT", 18, y)
        return label
    end

    SheetLabel("Instanz", -44)
    local zoneOptions = {}
    for _, instance in ipairs(GC.RaidInstances) do
        zoneOptions[#zoneOptions + 1] = instance.name
    end
    zoneOptions[#zoneOptions + 1] = "Frei (eigener Name)"
    page.zoneDropdown = CreateChoiceDropdown(sheet, 250, zoneOptions, function(value)
        if value == "Frei (eigener Name)" then
            -- Freitext: Der Name kommt aus dem Notizfeld des Dialogs unten -
            -- einfacher Weg: Zone leeren und das Feld zum Tippen freigeben.
            page.freeZone = true
            GC.RaidSearch:SetZone("", "", nil)
        else
            page.freeZone = nil
            for _, instance in ipairs(GC.RaidInstances) do
                if instance.name == value then
                    GC.RaidSearch:SetZone(instance.name, instance.short, instance.size)
                    break
                end
            end
        end
        GC.UI:RefreshRaidSearch()
    end, true, nil, nil, 26)
    page.zoneDropdown:SetPoint("TOPLEFT", sheet, "TOPLEFT", 110, -44)

    -- Das Freitextfeld erscheint nur bei "Frei" - sonst waeren es zwei
    -- Auswahlwege fuer dieselbe Angabe.
    page.zoneEdit = CreateEdit(sheet, 250, 26)
    page.zoneEdit.container:SetPoint("TOPLEFT", sheet, "TOPLEFT", 110, -44)
    page.zoneEdit:SetScript("OnEditFocusLost", function(edit)
        GC.RaidSearch:SetZone(edit:GetText(), edit:GetText(), nil)
        GC.UI:RefreshRaidSearch()
    end)
    page.zoneEdit:SetScript("OnEnterPressed", function(edit)
        edit:ClearFocus()
    end)
    page.zoneEdit.container:Hide()

    SheetLabel("Größe", -78)
    page.sizeStepper = CreateStepper(sheet, 5, 40, 5, function(value)
        GC.RaidSearch:SetSize(value)
        GC.UI:RefreshRaidSearch()
    end, "")
    page.sizeStepper:SetPoint("TOPLEFT", sheet, "TOPLEFT", 110, -78)

    SheetLabel("Termin", -112)
    page.dateEdit = CreateEdit(sheet, 132, 26)
    page.dateEdit.container:SetPoint("TOPLEFT", sheet, "TOPLEFT", 110, -112)
    page.dateEdit:SetScript("OnEditFocusLost", function(edit)
        if GC.RaidSearch:SetDate(edit:GetText()) then
            GC.UI:RefreshRaidSearch()
        else
            edit:SetText(FormatDateGerman(GC.RaidSearch:EnsurePlan().dateISO))
        end
    end)
    page.dateEdit:SetScript("OnEnterPressed", function(edit)
        edit:ClearFocus()
    end)
    local pick = CreateButton(page.dateEdit.container, "", 20, 20, function()
        GC.UI:OpenDatePicker(page.dateEdit, function(iso)
            GC.RaidSearch:SetDate(iso)
            GC.UI:RefreshRaidSearch()
        end)
    end)
    SetButtonMark(pick, CreateCalendarMark(pick, 14))
    AttachEditButton(page.dateEdit, pick, 20)

    page.timeEdit = CreateEdit(sheet, 58, 26)
    page.timeEdit.container:SetPoint("TOPLEFT", sheet, "TOPLEFT", 248, -112)
    page.timeEdit:SetScript("OnEditFocusLost", function(edit)
        if GC.RaidSearch:SetTime(edit:GetText()) then
            GC.UI:RefreshRaidSearch()
        else
            edit:SetText(GC.RaidSearch:EnsurePlan().timeText or "")
        end
    end)
    page.timeEdit:SetScript("OnEnterPressed", function(edit)
        edit:ClearFocus()
    end)
    page.weekdayLabel = CreateLabel(sheet, "", { muted = true, width = 44, height = 26 })
    page.weekdayLabel:SetPoint("TOPLEFT", sheet, "TOPLEFT", 314, -112)

    local function SheetEdit(labelText, y, setter)
        SheetLabel(labelText, y)
        local edit = CreateEdit(sheet, 250, 26)
        edit.container:SetPoint("TOPLEFT", sheet, "TOPLEFT", 110, y)
        edit:SetScript("OnEditFocusLost", function(self)
            setter(GC.RaidSearch, self:GetText())
            GC.UI:RefreshRaidSearch()
        end)
        edit:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        return edit
    end

    -- Das Freitextfeld ist die Lootregel (Owner-Wunsch); das Menue darunter
    -- nur eine Schreibhilfe, die es fuellt. Bis 0.9.140 stand das Menue OBEN
    -- und zeigte "Nicht gesetzt" - es sah aus wie ein leeres Pflichtfeld
    -- ueber einem zweiten Feld (Gilden-Screenshot).
    page.lootEdit = SheetEdit("Lootregel", -146, GC.RaidSearch.SetLootRule)
    SheetLabel("Vorlage", -180)
    page.lootPreset = CreateChoiceDropdown(sheet, 250,
        { "2SR > MS > OS", "1SR > MS > OS", "MS > OS", "GDKP", "Gildenintern" },
        function(value)
            GC.RaidSearch:SetLootRule(value)
            -- Zurueck auf die Beschriftung: Das Menue ist ein Befehl, kein
            -- Zustand - der Zustand steht im Freitextfeld darueber.
            page.lootPreset:SetValue("")
            GC.UI:RefreshRaidSearch()
        end, true, "Vorlage wählen", nil, 26)
    page.lootPreset:SetPoint("TOPLEFT", sheet, "TOPLEFT", 110, -180)

    page.hrEdit = SheetEdit("Hard Res.", -214, GC.RaidSearch.SetHardReserve)
    page.srEdit = SheetEdit("SR-Link", -248, GC.RaidSearch.SetSrLink)
    page.noteEdit = SheetEdit("Notiz", -282, GC.RaidSearch.SetNote)

    -- === RECHTE SPALTE: das Wichtigste zuerst ==============================
    -- Der Suchspruch steht rechts oben, gross und prominent (Owner-Wunsch:
    -- "das wichtigste Fenster"). Er ist, was tatsaechlich in den Chat geht.

    local announce = CreateCard(page, "Suchspruch")
    announce:SetSize(390, 256)
    announce:SetPoint("TOPLEFT", page, "TOPLEFT", 393, -66)
    page.announce = announce

    page.raidSearchMarkers = {}
    for markerIndex = 1, 8 do
        local selectedMarker = markerIndex
        local markerButton = CreateRaidMarkerButton(announce, markerIndex, function()
            GC.RaidSearch:SetMarker(selectedMarker)
            GC.UI:RefreshRaidSearch()
        end)
        markerButton:SetPoint("TOPLEFT", announce, "TOPLEFT", 150 + ((markerIndex - 1) * 26), -12)
        page.raidSearchMarkers[markerIndex] = markerButton
    end

    -- Grosse Vorschau: Der ganze LFM-Spruch steht sichtbar da, mehrzeilig.
    page.announceEdit = CreateTextArea(announce, 354, 84, 400)
    page.announceEdit.container:SetPoint("TOPLEFT", announce, "TOPLEFT", 18, -46)
    page.announceEdit:SetScript("OnTextChanged", function()
        GC.UI:RefreshRaidSearchPost()
    end)

    page.announceBytes = CreateLabel(announce, "", { muted = true, width = 120, height = 14,
        font = "GameFontNormalSmall" })
    page.announceBytes:SetPoint("TOPLEFT", announce, "TOPLEFT", 18, -138)
    -- "Neu generieren" wie auf der Werbeseite - dieselbe Handlung, dasselbe
    -- Wort: die Vorschau frisch aus dem Zettel bauen und Handarbeit verwerfen.
    page.announceRegenerate = CreateButton(announce, "Neu generieren", 112, 20, function()
        page.announceEdit:SetText(GC.RaidSearch:BuildAnnouncement())
        GC.UI:RefreshRaidSearchPost()
    end)
    page.announceRegenerate:SetPoint("TOPRIGHT", announce, "TOPRIGHT", -18, -136)

    -- Kanalkaestchen als feste Plaetze, beim Auffrischen befuellt: Die Liste
    -- haengt von den selbst beigetretenen Kanaelen ab und aendert sich mit
    -- jedem Login.
    page.channelToggles = {}
    for slot = 1, 8 do
        local toggle = CreateToggle(announce, "", function(enabled)
            local target = page.channelToggles[slot].targetKey
            if target then
                GC.RaidSearch:SetChannelSelected(target, enabled)
            end
            GC.UI:RefreshRaidSearchPost()
        end)
        local column = (slot - 1) % 4
        local row = math.floor((slot - 1) / 4)
        toggle:SetPoint("TOPLEFT", announce, "TOPLEFT", 18 + (column * 90), -160 - (row * 24))
        toggle:Hide()
        page.channelToggles[slot] = toggle
    end

    page.confirmButton = CreateButton(announce, "Text bestätigen", 104, 28, function()
        local success, message = GC.RaidSearch:ConfirmText(page.announceEdit:GetText())
        page.zulaufStatus:SetText(message or "")
        SetTextColor(page.zulaufStatus, success and THEME.success or THEME.danger)
        GC.UI:RefreshRaidSearch()
    end)
    page.confirmButton:SetPoint("BOTTOMLEFT", announce, "BOTTOMLEFT", 18, 10)
    page.postButton = CreateButton(announce, "Suche starten", 120, 28, function()
        local success, message = GC.RaidSearch:Post()
        page.zulaufStatus:SetText(message or "")
        SetTextColor(page.zulaufStatus, success and THEME.success or THEME.danger)
        GC.UI:RefreshRaidSearch()
    end, "PRIMARY")
    page.postButton:SetPoint("LEFT", page.confirmButton, "RIGHT", 8, 0)
    page.autoToggle = CreateToggle(announce, "Wiederholen", function(enabled)
        GC.UI:SetRaidSearchAutoRepeat(enabled)
    end)
    page.autoToggle:SetPoint("LEFT", page.postButton, "RIGHT", 8, 0)
    AttachAutoRepeatTooltip(page.autoToggle)

    -- === Besetzung: Soll und Ist (linke Spalte, unter dem Zettel) ==========
    local need = CreateCard(page, "Besetzung")
    need:SetSize(380, 198)
    need:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -388)
    page.needCard = need
    page.needCount = CreateLabel(need, "", { align = "RIGHT", width = 90, height = 20 })
    page.needCount:SetPoint("TOPRIGHT", need, "TOPRIGHT", -18, -16)

    page.roleRows = {}
    for index, definition in ipairs(RAIDSEARCH_ROLE_ROWS) do
        local role = definition.role
        local y = -44 - ((index - 1) * 24)
        local row = {}
        row.label = CreateLabel(need, definition.label, { width = 56, height = 22 })
        row.label:SetPoint("TOPLEFT", need, "TOPLEFT", 18, y)
        row.minus = CreateButton(need, "–", 22, 22, function()
            GC.RaidSearch:AdjustRoleNeed(role, -1)
            GC.UI:RefreshRaidSearch()
        end)
        row.minus:SetPoint("TOPLEFT", need, "TOPLEFT", 76, y)
        row.count = CreateLabel(need, "0", { align = "CENTER", width = 26, height = 22 })
        row.count:SetPoint("TOPLEFT", need, "TOPLEFT", 100, y)
        row.plus = CreateButton(need, "+", 22, 22, function()
            GC.RaidSearch:AdjustRoleNeed(role, 1)
            GC.UI:RefreshRaidSearch()
        end)
        row.plus:SetPoint("TOPLEFT", need, "TOPLEFT", 128, y)
        row.have = CreateLabel(need, "", { muted = true, width = 100, height = 22 })
        row.have:SetPoint("TOPLEFT", need, "TOPLEFT", 158, y)
        row.delta = CreateLabel(need, "", { align = "RIGHT", width = 96, height = 22 })
        row.delta:SetPoint("TOPLEFT", need, "TOPLEFT", 262, y)
        page.roleRows[role] = row
    end

    page.wishLabel = CreateLabel(need, "", { muted = true, width = 344, height = 16,
        font = "GameFontNormalSmall" })
    page.wishLabel:SetPoint("TOPLEFT", need, "TOPLEFT", 18, -116)

    -- Die Spec-Auswahl ist eine Kaestchenliste wie "Klassen & Specs"
    -- (Owner-Wunsch), geoeffnet ueber diesen Knopf - in der kleinen
    -- Besetzungskarte ist fuer die ganze Liste kein Platz, im Dialog schon.
    page.wishButton = CreateButton(need, "Klassen & Specs wählen", 230, 24, function()
        GC.UI:ToggleRaidSearchSpecs()
    end)
    page.wishButton:SetPoint("TOPLEFT", need, "TOPLEFT", 18, -136)

    page.unassignedLabel = CreateLabel(need, "", { muted = true, width = 344, height = 14,
        font = "GameFontNormalSmall" })
    page.unassignedLabel:SetPoint("TOPLEFT", need, "TOPLEFT", 18, -164)
    page.absentLabel = CreateLabel(need, "", { width = 344, height = 14,
        font = "GameFontNormalSmall", color = THEME.warning })
    page.absentLabel:SetPoint("TOPLEFT", need, "TOPLEFT", 18, -180)

    -- === Zulauf (rechte Spalte, unter dem Suchspruch) ======================
    local zulauf = CreateCard(page, "Zulauf")
    zulauf:SetSize(390, 258)
    zulauf:SetPoint("TOPLEFT", page, "TOPLEFT", 393, -328)
    page.zulauf = zulauf

    -- Auch die Antwortvorlagen wohnen an ihrer Karte: Bearbeitet wird, was
    -- das Antworten-Menue unten sendet.
    page.repliesButton = CreateButton(zulauf, "Antwortvorlagen", 116, 22, function()
        GC.UI:ToggleRaidSearchReplies()
    end)
    page.repliesButton:SetPoint("TOPRIGHT", zulauf, "TOPRIGHT", -78, -13)

    page.zulaufPrev = CreateButton(zulauf, "", 22, 20, function()
        page.zulaufPage = math.max(1, (page.zulaufPage or 1) - 1)
        GC.UI:RefreshRaidSearch()
    end)
    SetButtonMark(page.zulaufPrev, CreateArrowMark(page.zulaufPrev, 10, "LEFT"))
    page.zulaufPrev:SetPoint("TOPRIGHT", zulauf, "TOPRIGHT", -46, -14)
    page.zulaufNext = CreateButton(zulauf, "", 22, 20, function()
        page.zulaufPage = (page.zulaufPage or 1) + 1
        GC.UI:RefreshRaidSearch()
    end)
    SetButtonMark(page.zulaufNext, CreateArrowMark(page.zulaufNext, 10, "RIGHT"))
    page.zulaufNext:SetPoint("TOPRIGHT", zulauf, "TOPRIGHT", -18, -14)

    page.responseRows = {}
    for slot = 1, RAIDSEARCH_RESPONSE_ROWS do
        local y = -42 - ((slot - 1) * 42)
        local row = CreateButton(zulauf, "", 354, 40, function()
            local name = page.responseRows[slot].responseName
            if name then
                page.selectedResponseName = name
                GC.UI:RefreshRaidSearch()
            end
        end)
        row:SetPoint("TOPLEFT", zulauf, "TOPLEFT", 18, y)
        row.label:ClearAllPoints()
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -3)
        row.label:SetPoint("RIGHT", row, "RIGHT", -96, 0)
        row.label:SetHeight(16)
        row.label:SetJustifyH("LEFT")
        row.state = CreateLabel(row, "", { align = "RIGHT", width = 88, height = 16,
            font = "GameFontNormalSmall" })
        row.state:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -3)
        row.message = CreateLabel(row, "", { muted = true, width = 338, height = 14,
            font = "GameFontNormalSmall" })
        row.message:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -22)
        page.responseRows[slot] = row
    end

    -- Aktionen fuer die GEWAEHLTE Antwort - eine Zeile statt Knoepfen an jeder,
    -- damit die Namen nicht abgeschnitten werden (Lektion der Auftragszeilen).
    -- Kurze LFM-Kuerzel wie im Wunschmenue (GC.SpecShort).
    local specOptions = { "Keine Spec-Zuordnung" }
    local specOptionKey = {}
    for _, classFile in ipairs(GC.ClassOrder) do
        for _, spec in ipairs(GC.Classes[classFile].specs) do
            local label = GC.SpecShort(spec.key)
            specOptions[#specOptions + 1] = label
            specOptionKey[label] = spec.key
        end
    end
    page.responseSpec = CreateChoiceDropdown(zulauf, 150, specOptions, function(value)
        if not page.selectedResponseName then
            return
        end
        GC.RaidSearch:SetResponseSpec(page.selectedResponseName, specOptionKey[value])
        GC.UI:RefreshRaidSearch()
    end, false, "Spec zuordnen", nil, 26)
    page.responseSpec:SetPoint("TOPLEFT", zulauf, "TOPLEFT", 18, -214)
    page.inviteButton = CreateButton(zulauf, "Einladen", 70, 26, function()
        if page.selectedResponseName then
            local success, message = GC.RaidSearch:Invite(page.selectedResponseName)
            page.zulaufStatus:SetText(message or "")
            SetTextColor(page.zulaufStatus, success and THEME.success or THEME.danger)
            GC.UI:RefreshRaidSearch()
        end
    end, "PRIMARY")
    page.inviteButton:SetPoint("TOPLEFT", zulauf, "TOPLEFT", 174, -214)
    page.replyDropdown = CreateChoiceDropdown(zulauf, 96, {}, function() end,
        false, "Antworten", nil, 26)
    page.replyDropdown:SetPoint("TOPLEFT", zulauf, "TOPLEFT", 250, -214)
    page.removeButton = CreateButton(zulauf, "×", 22, 26, function()
        if page.selectedResponseName then
            GC.RaidSearch:RemoveResponse(page.selectedResponseName)
            page.selectedResponseName = nil
            GC.UI:RefreshRaidSearch()
        end
    end)
    page.removeButton:SetPoint("TOPLEFT", zulauf, "TOPLEFT", 352, -214)

    page.zulaufStatus = CreateLabel(zulauf, "", { width = 354, height = 14,
        font = "GameFontNormalSmall" })
    page.zulaufStatus:SetPoint("TOPLEFT", zulauf, "TOPLEFT", 18, -242)

    -- Cooldown-Countdown am Posten-Knopf und Kanalzustaende leben im
    -- Halbsekundentakt, wie auf der Postseite.
    page:SetScript("OnUpdate", function(_, elapsed)
        page.elapsed = (page.elapsed or 0) + elapsed
        if page.elapsed >= 0.5 then
            page.elapsed = 0
            GC.UI:RefreshRaidSearchPost()
        end
    end)
    page:HookScript("OnHide", function()
        if page.templatesDialog then
            page.templatesDialog:Hide()
        end
        if page.repliesDialog then
            page.repliesDialog:Hide()
        end
        if page.specDialog then
            page.specDialog:Hide()
        end
    end)
end

-- Das Antworten-Menue traegt die selbstgebauten Vorlagen. Ein Dropdown laesst
-- sich nicht nachtraeglich befuellen; es wird deshalb bei Bedarf neu gebaut -
-- die Vorlagenliste aendert sich nur durch den Dialog, nie im Takt.
function GC.UI:RebuildRaidSearchReplyDropdown()
    local page = self.pages.RAIDSEARCH
    if not page then
        return
    end
    local labels = {}
    local templates = GC.RaidSearch:GetReplyTemplates()
    for index, template in ipairs(templates) do
        labels[#labels + 1] = template.label or ("Vorlage " .. index)
    end
    -- Der alte Knopf bleibt versteckt zurueck - ein Neubau passiert nur, wenn
    -- jemand im Dialog Vorlagen aendert, nie im Takt.
    if page.replyDropdown then
        page.replyDropdown.popup:Hide()
        page.replyDropdown:Hide()
    end
    page.replyDropdown = CreateChoiceDropdown(page.zulauf, 96, labels, function(value)
        if not page.selectedResponseName then
            return
        end
        for index, template in ipairs(GC.RaidSearch:GetReplyTemplates()) do
            if (template.label or ("Vorlage " .. index)) == value then
                local success, message = GC.RaidSearch:SendReply(page.selectedResponseName, index)
                page.zulaufStatus:SetText(message or "")
                SetTextColor(page.zulaufStatus, success and THEME.success or THEME.danger)
                break
            end
        end
        page.replyDropdown:SetValue("")
        GC.UI:RefreshRaidSearch()
    end, false, "Antworten", nil, 26)
    -- Dieselbe Zeile wie beim Aufbau (-214): sonst rutschte das neu gebaute
    -- Menue nach dem Bearbeiten von Vorlagen in die Statuszeile.
    page.replyDropdown:SetPoint("TOPLEFT", page.zulauf, "TOPLEFT", 250, -214)
end

function GC.UI:SetRaidSearchAutoRepeat(enabled)
    local settings = GC.RaidSearch:GetSettings()
    settings.autoRepeat = enabled == true
    if not enabled then
        GC.Chat:SetAutoPostArmed("raidsearch", false)
        GC.RaidSearch.lastAutoPost = nil
    end
    self:RefreshRaidSearch()
    self:RefreshRaidSearchBar()
end

-- Nur Spruchvorschau, Byte-Zaehler, Kanalzeile und Knoepfe - der schnelle Teil
-- fuer den Halbsekundentakt. Der volle Aufbau (RefreshRaidSearch) laeuft bei
-- echten Datenaenderungen.
function GC.UI:RefreshRaidSearchPost()
    local page = self.pages.RAIDSEARCH
    if not page or not page:IsShown() then
        return
    end
    local plan = GC.RaidSearch:GetPlan()
    local text = page.announceEdit:GetText() or ""
    local bytes = #text
    page.announceBytes:SetText(bytes .. "/" .. GC.Constants.MAX_CHAT_BYTES .. " Bytes")
    SetTextColor(page.announceBytes, bytes > GC.Constants.MAX_CHAT_BYTES and THEME.danger or THEME.muted)

    local targets = GC.RaidSearch:GetChannelTargets()
    local ready = 0
    for slot, toggle in ipairs(page.channelToggles) do
        local target = targets[slot]
        if target then
            toggle.targetKey = target.key
            local label = RAIDSEARCH_CHANNEL_LABEL[target.key]
                or GC.Util.SafeChatText(target.label, 10)
            toggle.text:SetText(GC.L(label))
            SetToggle(toggle, target.selected)
            toggle:SetShown(true)
            toggle:SetAlpha(target.joined and 1 or 0.45)
            if target.selected and target.joined
                and GC.Chat:GetRemainingCooldown(target.key) <= 0 then
                ready = ready + 1
            end
        else
            toggle.targetKey = nil
            toggle:Hide()
        end
    end

    local confirmed = plan and plan.confirmedText or nil
    local isConfirmed = confirmed ~= nil and confirmed == text and GC.Util.Trim(text) ~= ""
    SetButtonEnabled(page.confirmButton, GC.Util.Trim(text) ~= "")
    if isConfirmed and ready > 0 then
        page.postButton:Enable()
    else
        page.postButton:Disable()
    end
    page.postButton:SetActive(isConfirmed and ready > 0)
    local searching = plan and plan.status == "SUCHT"
    page.postButton:SetText(searching and "Posten" or "Suche starten")
    -- Automatik: genau dann scharf, wenn jetzt auch ein Klick posten wuerde -
    -- dieselbe Regel wie beim Werbebalken, in jedem Takt neu entschieden.
    local settings = GC.RaidSearch:GetSettings()
    GC.Chat:SetAutoPostArmed("raidsearch",
        settings.autoRepeat == true and GC.Chat:IsAutoPostSupported()
        and searching and isConfirmed and ready > 0)
    if page.autoToggle then
        SetToggle(page.autoToggle, settings.autoRepeat == true)
    end
end

function GC.UI:RefreshRaidSearch()
    local page = self.pages.RAIDSEARCH
    if not page then
        return
    end
    local plan = GC.RaidSearch:GetPlan()

    -- Ohne Zettel zeigen die Karten den Anlege-Zustand; der erste Klick auf
    -- irgendein Feld legt ihn ohnehin an (EnsurePlan), der Knopf macht es
    -- ausdruecklich.
    if page.newArmed and (not plan or plan.status ~= "SUCHT") then
        page.newArmed = nil
    end
    if not page.newArmed then
        page.newButton:SetText("Neue Suche")
    end
    local searching = plan ~= nil and plan.status == "SUCHT"
    page.endButton:SetShown(searching)
    -- Der Balkenknopf teilt die Lebensdauer des "Suche beenden"-Knopfs: nur
    -- solange gesucht wird, gibt es einen Balken zum Ein- oder Ausblenden. Die
    -- Beschriftung spiegelt den aktuellen Zustand, der aktive Rahmen zeigt
    -- "Balken ist offen" - dasselbe Muster wie der Werbebalken-Knopf.
    if page.barToggle then
        page.barToggle:SetShown(searching)
        local barSettings = GC.RaidSearch:GetSettings().bar
        local barShown = type(barSettings) == "table" and barSettings.hidden ~= true
        page.barToggle:SetActive(barShown)
        page.barToggle:SetText(barShown and "Suchbalken ausblenden" or "Suchbalken einblenden")
    end

    if not plan then
        plan = GC.RaidSearch:EnsurePlan()
    end

    -- Suchzettel.
    local knownZone = false
    for _, instance in ipairs(GC.RaidInstances) do
        if instance.name == plan.zone then
            knownZone = true
            break
        end
    end
    if page.freeZone == nil then
        page.freeZone = (not knownZone and GC.Util.Trim(plan.zone) ~= "") or nil
    end
    local freeZone = page.freeZone == true or (not knownZone and GC.Util.Trim(plan.zone) ~= "")
    page.zoneDropdown:SetShown(not freeZone)
    page.zoneEdit.container:SetShown(freeZone)
    if not freeZone then
        page.zoneDropdown:SetValue(knownZone and plan.zone or "")
    elseif not page.zoneEdit:HasFocus() then
        page.zoneEdit:SetText(plan.zone or "")
    end
    page.sizeStepper:SetValue(plan.size or 25)
    if not page.dateEdit:HasFocus() then
        page.dateEdit:SetText(FormatDateGerman(plan.dateISO))
    end
    if not page.timeEdit:HasFocus() then
        page.timeEdit:SetText(plan.timeText or "")
    end
    page.weekdayLabel:SetText(GC.RaidSearch:FormatWhen(plan):match("^(%S+)") or "")
    if not page.lootEdit:HasFocus() then
        page.lootEdit:SetText(plan.loot.rule or "")
    end
    if not page.hrEdit:HasFocus() then
        page.hrEdit:SetText(plan.loot.hr or "")
    end
    if not page.srEdit:HasFocus() then
        page.srEdit:SetText(plan.loot.srLink or "")
    end
    if not page.noteEdit:HasFocus() then
        page.noteEdit:SetText(plan.note or "")
    end
    for markerIndex, markerButton in ipairs(page.raidSearchMarkers) do
        markerButton:SetActive(markerIndex == plan.marker)
    end

    -- Spruchvorschau: solange nichts bestaetigt ist, lebt sie mit dem Zettel;
    -- ein bestaetigter Text bleibt eingefroren, bis der Zettel sich aendert
    -- (dann loescht TouchPlan die Bestaetigung) - exakt das Werbetext-Muster.
    if not page.announceEdit:HasFocus() then
        local preview = plan.confirmedText or GC.RaidSearch:BuildAnnouncement()
        if page.announceEdit:GetText() ~= preview then
            page.announceEdit:SetText(preview)
        end
    end

    -- Besetzung.
    local rosterState = GC.RaidSearch:GetRosterState()
    local open = GC.RaidSearch:GetOpenNeeds(rosterState)
    page.needCount:SetText(rosterState.total .. "/" .. (plan.size or 0))
    for _, definition in ipairs(RAIDSEARCH_ROLE_ROWS) do
        local row = page.roleRows[definition.role]
        local want = tonumber(plan.need.roles[definition.role]) or 0
        local have = rosterState.roles[definition.role] or 0
        local missing = open.roles[definition.role] or 0
        row.count:SetText(tostring(want))
        row.have:SetText(GC.LFormat("dabei {n}", { n = have }))
        if want == 0 then
            row.delta:SetText("")
        elseif missing > 0 then
            row.delta:SetText("-" .. missing)
            SetTextColor(row.delta, THEME.warning)
        else
            row.delta:SetText(GC.L("voll"))
            SetTextColor(row.delta, THEME.success)
        end
    end
    local wishes = GC.RaidSearch:GetSpecWishes()
    if #wishes == 0 then
        page.wishLabel:SetText(GC.L("Keine Specs gewählt - über den Knopf ankreuzen."))
    else
        local parts = {}
        for _, wish in ipairs(wishes) do
            local haveCount = rosterState.specCounts[wish.specKey] or 0
            parts[#parts + 1] = GC.SpecShort(wish.specKey)
                .. (haveCount >= wish.count and " (da)" or "")
        end
        page.wishLabel:SetText(GC.L("Gesucht: ") .. table.concat(parts, ", "))
    end
    self:RefreshRaidSearchSpecs()
    if rosterState.unassigned > 0 then
        page.unassignedLabel:SetText(GC.LFormat("{n} dabei ohne Spec-Zuordnung - zählt auf keine Rolle.",
            { n = rosterState.unassigned }))
    else
        page.unassignedLabel:SetText("")
    end
    local absent = GC.RaidSearch:GetAbsentAtDate()
    if #absent > 0 then
        page.absentLabel:SetText(GC.LFormat("Am Termin abgemeldet: {names}",
            { names = GC.Util.SafeChatText(table.concat(absent, ", "), 90) }))
    else
        page.absentLabel:SetText("")
    end

    -- Zulauf.
    local responses = plan.responses or {}
    local pageCount = math.max(1, math.ceil(#responses / RAIDSEARCH_RESPONSE_ROWS))
    page.zulaufPage = math.min(page.zulaufPage or 1, pageCount)
    SetButtonEnabled(page.zulaufPrev, page.zulaufPage > 1)
    SetButtonEnabled(page.zulaufNext, page.zulaufPage < pageCount)
    if page.zulauf.title then
        page.zulauf.title:SetText(GC.L("Zulauf") .. " (" .. #responses .. ")")
    end
    local selectedVisible = false
    for slot = 1, RAIDSEARCH_RESPONSE_ROWS do
        local row = page.responseRows[slot]
        local response = responses[((page.zulaufPage - 1) * RAIDSEARCH_RESPONSE_ROWS) + slot]
        if response then
            row.responseName = response.name
            local pieces = { ClassColoredName(GC.Util.PlayerIdentityName(response.name), response.classFile) }
            local classInfo = GC.Classes[response.classFile or ""]
            local detail = {}
            if classInfo then
                detail[#detail + 1] = classInfo.name
            end
            if tonumber(response.level) then
                detail[#detail + 1] = tostring(response.level)
            end
            local spec = GC.SpecByKey[response.specKey or ""]
            if spec then
                detail[#detail + 1] = spec.name
            end
            if #detail > 0 then
                pieces[#pieces + 1] = "|cff8b98a5" .. table.concat(detail, " ") .. "|r"
            end
            row.label:SetText(table.concat(pieces, "  "))
            local stateText, stateColor = ResponseStateLabel(response)
            row.state:SetText(GC.L(stateText))
            SetTextColor(row.state, stateColor)
            local lastMessage = response.messages and response.messages[#response.messages]
            row.message:SetText(lastMessage and tostring(lastMessage.text or "") or "")
            local isSelected = page.selectedResponseName ~= nil
                and GC.Chat:CanonicalLeadName(response.name) == GC.Chat:CanonicalLeadName(page.selectedResponseName)
            row:SetActive(isSelected)
            if isSelected then
                selectedVisible = true
            end
            row:Show()
        else
            row.responseName = nil
            row:SetActive(false)
            row:Hide()
        end
    end
    if not selectedVisible then
        page.selectedResponseName = nil
    end
    local hasSelection = page.selectedResponseName ~= nil
    SetButtonEnabled(page.inviteButton, hasSelection)
    SetButtonEnabled(page.removeButton, hasSelection)
    if hasSelection then
        local response = GC.RaidSearch:FindResponse(page.selectedResponseName)
        local spec = response and GC.SpecByKey[response.specKey or ""]
        page.responseSpec:SetValue(spec and GC.SpecShort(response.specKey) or "")
    else
        page.responseSpec:SetValue("")
    end
    if not page.replyDropdownBuilt then
        page.replyDropdownBuilt = true
        self:RebuildRaidSearchReplyDropdown()
    end

    self:RefreshRaidSearchPost()
    self:RefreshRaidSearchTemplates()
    self:RefreshRaidSearchReplies()
    self:UpdateRaidSearchBarShown()
end

-- === Dialog: Klassen & Specs ankreuzen =====================================
--
-- Wie die Rekrutierungsseite, nur als Fenster: eine scrollbare Liste, je
-- Klasse eine farbige Zeile und darunter die drei Specs als Kaestchen zum
-- Anklicken (Owner-Wunsch). Ersetzt das alte Aufklappmenue, mit dem ab dem
-- vierten Wunsch das Zurechtklicken misslang.
function GC.UI:ToggleRaidSearchSpecs()
    local page = self.pages.RAIDSEARCH
    if not page then
        return
    end
    if not page.specDialog then
        local dialog = CreatePanel(self.frame, THEME.window, THEME.accent)
        dialog:SetSize(300, 520)
        dialog:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
        dialog:SetFrameLevel((self.frame:GetFrameLevel() or 1) + 80)
        dialog:EnableMouse(true)
        dialog:Hide()
        local title = CreateLabel(dialog, "Klassen & Specs", { title = true })
        title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -14)
        local hint = CreateLabel(dialog, "Ankreuzen, welche Specs gesucht werden - sie erscheinen im Suchspruch.",
            { muted = true, width = 264, height = 28, vertical = "TOP", font = "GameFontNormalSmall" })
        hint:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -40)

        local scroll = CreateModernScrollFrame(dialog)
        scroll:SetPoint("TOPLEFT", dialog, "TOPLEFT", 12, -74)
        scroll:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -14, 52)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetWidth(248)
        scroll:SetScrollChild(content)

        dialog.specToggles = {}
        local y = 0
        for _, classFile in ipairs(GC.ClassOrder) do
            local classInfo = GC.Classes[classFile]
            local header = CreateLabel(content, classInfo.plural, { width = 240, height = 20 })
            header:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
            local red, green, blue = ClassColor(classFile)
            header:SetTextColor(red, green, blue)
            y = y + 24
            for _, spec in ipairs(classInfo.specs) do
                local specKey = spec.key
                local toggle = CreateToggle(content, spec.name, function(enabled)
                    GC.RaidSearch:SetSpecWish(specKey, enabled)
                    GC.UI:RefreshRaidSearch()
                end)
                toggle:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -y)
                dialog.specToggles[specKey] = toggle
                y = y + 26
            end
            y = y + 6
        end
        content:SetHeight(math.max(1, y))

        dialog.clear = CreateButton(dialog, "Alle abwählen", 130, 26, function()
            GC.RaidSearch:ClearSpecWishes()
            GC.UI:RefreshRaidSearch()
        end)
        dialog.clear:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 18, 14)
        dialog.close = CreateButton(dialog, "Fertig", 90, 26, function()
            dialog:Hide()
        end)
        dialog.close:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -18, 14)
        page.specDialog = dialog
    end
    if page.templatesDialog then page.templatesDialog:Hide() end
    if page.repliesDialog then page.repliesDialog:Hide() end
    page.specDialog:SetShown(not page.specDialog:IsShown())
    self:RefreshRaidSearchSpecs()
end

function GC.UI:RefreshRaidSearchSpecs()
    local page = self.pages.RAIDSEARCH
    local dialog = page and page.specDialog
    if not dialog or not dialog:IsShown() then
        return
    end
    for specKey, toggle in pairs(dialog.specToggles) do
        SetToggle(toggle, GC.RaidSearch:HasSpecWish(specKey))
    end
end

-- === Dialog: Suchzettel-Vorlagen ===========================================

function GC.UI:ToggleRaidSearchTemplates()
    local page = self.pages.RAIDSEARCH
    if not page then
        return
    end
    if not page.templatesDialog then
        local dialog = CreatePanel(self.frame, THEME.window, THEME.accent)
        dialog:SetSize(420, 372)
        dialog:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
        dialog:SetFrameLevel((self.frame:GetFrameLevel() or 1) + 80)
        dialog:EnableMouse(true)
        dialog:Hide()
        local title = CreateLabel(dialog, "Suchzettel-Vorlagen", { title = true })
        title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -14)
        local hint = CreateLabel(dialog, "Anwenden erzeugt einen frischen Zettel mit dem nächsten passenden Wochentag.",
            { muted = true, width = 384, height = 28, vertical = "TOP", font = "GameFontNormalSmall" })
        hint:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -40)
        dialog.rows = {}
        for slot = 1, 12 do
            local y = -72 - ((slot - 1) * 22)
            local row = {}
            row.label = CreateLabel(dialog, "", { width = 236, height = 20 })
            row.label:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, y)
            row.apply = CreateButton(dialog, "Anwenden", 84, 20, function()
                local _, message = GC.RaidSearch:ApplyTemplate(slot)
                page.zulaufStatus:SetText(message or "")
                SetTextColor(page.zulaufStatus, THEME.success)
                dialog:Hide()
                GC.UI:RefreshRaidSearch()
            end)
            row.apply:SetPoint("TOPLEFT", dialog, "TOPLEFT", 262, y)
            row.remove = CreateButton(dialog, "×", 20, 20, function()
                GC.RaidSearch:RemoveTemplate(slot)
                GC.UI:RefreshRaidSearchTemplates()
            end)
            row.remove:SetPoint("TOPLEFT", dialog, "TOPLEFT", 352, y)
            dialog.rows[slot] = row
        end
        dialog.save = CreateButton(dialog, "Aktuellen Zettel als Vorlage speichern", 260, 26, function()
            local _, message = GC.RaidSearch:SaveTemplate()
            page.zulaufStatus:SetText(message or "")
            SetTextColor(page.zulaufStatus, THEME.success)
            GC.UI:RefreshRaidSearchTemplates()
        end, "PRIMARY")
        dialog.save:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 18, 12)
        dialog.close = CreateButton(dialog, "Schließen", 90, 26, function()
            dialog:Hide()
        end)
        dialog.close:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -18, 12)
        page.templatesDialog = dialog
    end
    if page.repliesDialog then
        page.repliesDialog:Hide()
    end
    if page.specDialog then
        page.specDialog:Hide()
    end
    page.templatesDialog:SetShown(not page.templatesDialog:IsShown())
    self:RefreshRaidSearchTemplates()
end

function GC.UI:RefreshRaidSearchTemplates()
    local page = self.pages.RAIDSEARCH
    local dialog = page and page.templatesDialog
    if not dialog or not dialog:IsShown() then
        return
    end
    local templates = GC.RaidSearch:GetData().templates
    for slot, row in ipairs(dialog.rows) do
        local template = templates[slot]
        if template then
            row.label:SetText(tostring(template.label or ""))
            row.apply:Show()
            row.remove:Show()
            row.label:Show()
        else
            row.label:SetText(slot == 1 and GC.L("Noch keine Vorlagen gespeichert.") or "")
            row.label:SetShown(slot == 1 or template ~= nil)
            row.apply:Hide()
            row.remove:Hide()
        end
    end
end

-- === Dialog: Antwortvorlagen ===============================================

function GC.UI:ToggleRaidSearchReplies()
    local page = self.pages.RAIDSEARCH
    if not page then
        return
    end
    if not page.repliesDialog then
        local dialog = CreatePanel(self.frame, THEME.window, THEME.accent)
        dialog:SetSize(560, 392)
        dialog:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
        dialog:SetFrameLevel((self.frame:GetFrameLevel() or 1) + 80)
        dialog:EnableMouse(true)
        dialog:Hide()
        local title = CreateLabel(dialog, "Antwortvorlagen", { title = true })
        title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -14)
        local hint = CreateLabel(dialog, "Eigene Schnellantworten für den Zulauf. Platzhalter: "
            .. "{name} {instanz} {termin} {loot} {srlink} - gesendet wird per Klick im Antworten-Menü.",
            { muted = true, width = 524, height = 30, vertical = "TOP", font = "GameFontNormalSmall" })
        hint:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -40)
        dialog.rows = {}
        for slot = 1, 8 do
            local y = -78 - ((slot - 1) * 34)
            local row = {}
            row.labelEdit = CreateEdit(dialog, 120, 26)
            row.labelEdit.container:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, y)
            row.textEdit = CreateEdit(dialog, 360, 26)
            row.textEdit.container:SetPoint("TOPLEFT", dialog, "TOPLEFT", 146, y)
            local function Save()
                GC.RaidSearch:SetReplyTemplate(slot, row.labelEdit:GetText(), row.textEdit:GetText())
                GC.UI:RebuildRaidSearchReplyDropdown()
            end
            row.labelEdit:SetScript("OnEditFocusLost", Save)
            row.textEdit:SetScript("OnEditFocusLost", Save)
            row.labelEdit:SetScript("OnEnterPressed", function(edit) edit:ClearFocus() end)
            row.textEdit:SetScript("OnEnterPressed", function(edit) edit:ClearFocus() end)
            row.remove = CreateButton(dialog, "×", 20, 26, function()
                GC.RaidSearch:RemoveReplyTemplate(slot)
                GC.UI:RebuildRaidSearchReplyDropdown()
                GC.UI:RefreshRaidSearchReplies()
            end)
            row.remove:SetPoint("TOPLEFT", dialog, "TOPLEFT", 514, y)
            dialog.rows[slot] = row
        end
        dialog.add = CreateButton(dialog, "Neue Vorlage", 120, 26, function()
            local templates = GC.RaidSearch:GetReplyTemplates()
            if #templates < 8 then
                GC.RaidSearch:SetReplyTemplate(#templates + 1, "Vorlage " .. (#templates + 1), "")
                GC.UI:RefreshRaidSearchReplies()
            end
        end)
        dialog.add:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 18, 12)
        dialog.close = CreateButton(dialog, "Schließen", 90, 26, function()
            dialog:Hide()
        end)
        dialog.close:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -18, 12)
        page.repliesDialog = dialog
    end
    if page.templatesDialog then
        page.templatesDialog:Hide()
    end
    if page.specDialog then
        page.specDialog:Hide()
    end
    page.repliesDialog:SetShown(not page.repliesDialog:IsShown())
    self:RefreshRaidSearchReplies()
end

function GC.UI:RefreshRaidSearchReplies()
    local page = self.pages.RAIDSEARCH
    local dialog = page and page.repliesDialog
    if not dialog or not dialog:IsShown() then
        return
    end
    local templates = GC.RaidSearch:GetReplyTemplates()
    for slot, row in ipairs(dialog.rows) do
        local template = templates[slot]
        local shown = template ~= nil
        row.labelEdit.container:SetShown(shown)
        row.textEdit.container:SetShown(shown)
        row.remove:SetShown(shown)
        if template then
            if not row.labelEdit:HasFocus() then
                row.labelEdit:SetText(template.label or "")
            end
            if not row.textEdit:HasFocus() then
                row.textEdit:SetText(template.text or "")
            end
        end
    end
    SetButtonEnabled(dialog.add, #templates < 8)
end

-- === Suchbalken ============================================================
--
-- Das kleine Fenster fuer den laufenden Betrieb, nach dem Muster des
-- Werbebalkens (Owner-Entscheidung: Stufe 1, mit Cooldown-Countdown am
-- Posten-Knopf). Er zeigt sich nur waehrend einer laufenden Suche; das
-- Wegklicken gilt bis zum naechsten "Suche starten".

function GC.UI:CreateRaidSearchBar()
    if self.raidSearchBar then
        return self.raidSearchBar
    end
    local bar = CreatePanel(UIParent, THEME.window, THEME.accent, "GuildCopilotForeverRaidSearchBar")
    bar:SetSize(330, 150)
    local settings = GC.RaidSearch:GetSettings()
    settings.bar = type(settings.bar) == "table" and settings.bar or {}
    bar:SetPoint("CENTER", UIParent, "CENTER",
        tonumber(settings.bar.x) or 0, tonumber(settings.bar.y) or -140)
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", bar.StartMoving)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        if point then
            local barSettings = GC.RaidSearch:GetSettings().bar
            barSettings.x = math.floor(tonumber(x) or 0)
            barSettings.y = math.floor(tonumber(y) or 0)
        end
    end)
    bar:SetFrameStrata("MEDIUM")
    bar:Hide()

    local title = CreateLabel(bar, "Raidsuche", { font = "GameFontNormalSmall" })
    title:SetPoint("TOPLEFT", bar, "TOPLEFT", 12, -9)
    local close = CreateButton(bar, "×", 20, 20, function()
        GC.RaidSearch:GetSettings().bar.hidden = true
        GC.Chat:SetAutoPostArmed("raidsearch", false)
        GC.UI:UpdateRaidSearchBarShown()
    end)
    close:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -8, -7)

    bar.headline = CreateLabel(bar, "", { width = 306, height = 16 })
    bar.headline:SetPoint("TOPLEFT", bar, "TOPLEFT", 12, -28)
    bar.needLine = CreateLabel(bar, "", { muted = true, width = 306, height = 14,
        font = "GameFontNormalSmall" })
    bar.needLine:SetPoint("TOPLEFT", bar, "TOPLEFT", 12, -46)
    bar.status = CreateLabel(bar, "", { font = "GameFontNormalSmall", width = 306, height = 14 })
    bar.status:SetPoint("TOPLEFT", bar, "TOPLEFT", 12, -64)
    bar.autoToggle = CreateToggle(bar, "Automatisch wiederholen", function(enabled)
        GC.UI:SetRaidSearchAutoRepeat(enabled)
    end)
    bar.autoToggle:SetPoint("TOPLEFT", bar, "TOPLEFT", 12, -82)
    AttachAutoRepeatTooltip(bar.autoToggle)
    bar.sendButton = CreateButton(bar, "Posten", 306, 26, function()
        local success, message = GC.RaidSearch:Post()
        bar.status:SetText(message or "")
        SetTextColor(bar.status, success and THEME.success or THEME.danger)
        GC.UI:RefreshRaidSearchBar()
        GC.UI:Invalidate("RAIDSEARCH")
    end, "PRIMARY")
    bar.sendButton:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 12, 10)

    bar:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed >= 0.5 then
            self.elapsed = 0
            GC.UI:RefreshRaidSearchBar()
        end
    end)
    self.raidSearchBar = bar
    return bar
end

-- Ein Ort, ein Wert: derselbe hidden-Schalter, den das × im Balken setzt und
-- den ein "Suche starten" beim ECHTEN Start wieder loest. Der Knopf kippt ihn
-- ausdruecklich, danach entscheidet UpdateRaidSearchBarShown wie sonst auch -
-- ohne laufende Suche bleibt der Balken trotzdem weg.
function GC.UI:ToggleRaidSearchBar()
    local settings = GC.RaidSearch:GetSettings()
    settings.bar = type(settings.bar) == "table" and settings.bar or {}
    settings.bar.hidden = not (settings.bar.hidden == true)
    self:UpdateRaidSearchBarShown()
end

function GC.UI:UpdateRaidSearchBarShown()
    local settings = GC.RaidSearch:GetSettings()
    settings.bar = type(settings.bar) == "table" and settings.bar or {}
    local shouldShow = GC.RaidSearch:IsSearching() and settings.bar.hidden ~= true
    if not shouldShow then
        if self.raidSearchBar then
            self.raidSearchBar:Hide()
            GC.Chat:SetAutoPostArmed("raidsearch", false)
        end
        return
    end
    self:CreateRaidSearchBar()
    self.raidSearchBar:Show()
    self:RefreshRaidSearchBar()
end

function GC.UI:RefreshRaidSearchBar()
    local bar = self.raidSearchBar
    if not bar or not bar:IsShown() then
        return
    end
    local plan = GC.RaidSearch:GetPlan()
    if not plan then
        bar:Hide()
        return
    end
    local rosterState = GC.RaidSearch:GetRosterState()
    local open = GC.RaidSearch:GetOpenNeeds(rosterState)
    local zone = GC.Util.Trim(plan.zoneShort) ~= "" and plan.zoneShort or plan.zone
    bar.headline:SetText(zone .. " " .. GC.RaidSearch:FormatWhen(plan)
        .. "  ·  " .. rosterState.total .. "/" .. (plan.size or 0))
    local roleText = GC.RaidSearch:DescribeOpenRoles(open)
    if roleText ~= "" then
        bar.needLine:SetText(GC.L("offen: ") .. roleText)
    elseif rosterState.total < (tonumber(plan.size) or 0) then
        bar.needLine:SetText(GC.LFormat("offen: {n} Plätze",
            { n = (tonumber(plan.size) or 0) - rosterState.total }))
    else
        bar.needLine:SetText(GC.L("voll besetzt"))
    end

    -- Bereit-Zaehlung wie auf der Seite; der laengste Cooldown steht im Knopf.
    local ready = 0
    local longest = 0
    for _, target in ipairs(GC.RaidSearch:GetChannelTargets()) do
        if target.selected then
            local remaining = GC.Chat:GetRemainingCooldown(target.key)
            if remaining > 0 then
                longest = math.max(longest, remaining)
            elseif target.joined then
                ready = ready + 1
            end
        end
    end
    local confirmed = GC.Util.Trim(plan.confirmedText or "") ~= ""
    local canSend = confirmed and ready > 0
    SetButtonEnabled(bar.sendButton, canSend)
    if longest > 0 and ready == 0 then
        bar.sendButton:SetText(math.ceil(longest) .. "s Cooldown")
    else
        bar.sendButton:SetText(GC.L("Posten"))
    end

    local settings = GC.RaidSearch:GetSettings()
    local automatik = settings.autoRepeat == true and GC.Chat:IsAutoPostSupported()
    GC.Chat:SetAutoPostArmed("raidsearch", automatik and canSend and plan.status == "SUCHT")
    if bar.autoToggle then
        SetToggle(bar.autoToggle, settings.autoRepeat == true)
    end

    local newCount = GC.RaidSearch:CountNewResponses()
    local recent = GC.RaidSearch.lastAutoPost
    if automatik and recent and (GC.Util.Now() - (recent.at or 0)) < 6 then
        bar.status:SetText("Automatik: " .. recent.message)
        SetTextColor(bar.status, recent.success and THEME.success or THEME.warning)
    elseif newCount > 0 then
        bar.status:SetText(GC.LFormat("{n} neue Antworten im Zulauf", { n = newCount }))
        SetTextColor(bar.status, THEME.warning)
    elseif automatik and canSend then
        bar.status:SetText(GC.L("Automatik: der nächste Tastendruck postet."))
        SetTextColor(bar.status, THEME.success)
    elseif automatik and not confirmed then
        bar.status:SetText(GC.L("Automatik wartet auf einen bestätigten Text."))
        SetTextColor(bar.status, THEME.warning)
    elseif automatik and longest > 0 then
        bar.status:SetText("Automatik: nächster Post in " .. math.ceil(longest) .. "s.")
        SetTextColor(bar.status, THEME.muted)
    else
        bar.status:SetText("")
    end
end

function GC.UI:CreatePostBar()
    if self.postBar then
        return self.postBar
    end

    local bar = CreatePanel(UIParent, THEME.window, THEME.accent, "GuildCopilotForeverPostBar")
    -- Hoch genug fuer den vollstaendigen Werbetext: 255 Bytes brauchen bei
    -- 306 Pixel Breite bis zu fuenf Zeilen. Darunter Statuszeile,
    -- Automatik-Schalter und Knopf, die sich nicht ueberlappen duerfen.
    bar:SetSize(330, 188)
    local settings = GC.DB:GetSettings().postBar
    bar:SetPoint("CENTER", UIParent, "CENTER", tonumber(settings.x) or 0, tonumber(settings.y) or -220)
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", bar.StartMoving)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        if point then
            GC.DB:GetSettings().postBar.x = math.floor(tonumber(x) or 0)
            GC.DB:GetSettings().postBar.y = math.floor(tonumber(y) or 0)
        end
    end)
    bar:SetFrameStrata("MEDIUM")
    bar:Hide()

    local title = CreateLabel(bar, "Gildenwerbung", { font = "GameFontNormalSmall" })
    title:SetPoint("TOPLEFT", bar, "TOPLEFT", 12, -9)

    local close = CreateButton(bar, "×", 20, 20, function()
        GC.UI:SetPostBarShown(false)
    end)
    close:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -8, -7)

    bar.text = CreateLabel(bar, "", { muted = true, width = 306, height = 70, vertical = "TOP" })
    bar.text:SetPoint("TOPLEFT", bar, "TOPLEFT", 12, -28)

    bar.status = CreateLabel(bar, "", { font = "GameFontNormalSmall", width = 306, height = 14 })
    bar.status:SetPoint("TOPLEFT", bar, "TOPLEFT", 12, -102)

    bar.autoToggle = CreateToggle(bar, "Automatisch wiederholen", function(enabled)
        GC.UI:SetAutoRepeat(enabled)
    end)
    bar.autoToggle:SetPoint("TOPLEFT", bar, "TOPLEFT", 12, -120)
    AttachAutoRepeatTooltip(bar.autoToggle)

    bar.sendButton = CreateButton(bar, "Suche starten", 306, 26, function()
        local recruitment = GC.DB:GetGuild().recruitment
        local success, message = GC.Chat:StartSearch(recruitment.confirmedText or "")
        bar.status:SetText(message or "")
        SetTextColor(bar.status, success and THEME.success or THEME.danger)
        GC.UI:RefreshPostBar()
        GC.UI:RefreshPost()
    end, "PRIMARY")
    bar.sendButton:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 12, 10)

    bar:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed >= 0.5 then
            self.elapsed = 0
            GC.UI:RefreshPostBar()
        end
    end)

    self.postBar = bar
    self:RefreshPostBar()
    return bar
end

function GC.UI:SetPostBarShown(shown)
    GC.DB:GetSettings().postBar.hidden = not shown
    self:CreatePostBar()
    self.postBar:SetShown(shown == true)
    if shown then
        self:RefreshPostBar()
    else
        -- Balken zu = Automatik entschaerft. Der Schalter bleibt gesetzt und
        -- greift wieder, sobald der Balken das naechste Mal offen ist - der
        -- Balken ist die sichtbare Anzeige, ohne ihn laeuft nichts unsichtbar
        -- im Hintergrund weiter.
        GC.Chat:SetAutoPostArmed("recruitment", false)
    end
    self:RefreshPost()
end

function GC.UI:TogglePostBar()
    self:SetPostBarShown(GC.DB:GetSettings().postBar.hidden ~= false)
end

-- Ein Schalter, zwei Orte: Postseite und Werbebalken schreiben denselben
-- Wert. Einschalten blendet den Balken ein, denn die Automatik lebt nur in
-- ihm; Ausschalten entschaerft sofort und raeumt die letzte
-- Automatik-Rueckmeldung weg.
function GC.UI:SetAutoRepeat(enabled)
    enabled = enabled == true
    GC.DB:GetSettings().postBar.autoRepeat = enabled
    if enabled then
        if GC.DB:GetSettings().postBar.hidden ~= false then
            self:SetPostBarShown(true)
        end
    else
        GC.Chat:SetAutoPostArmed("recruitment", false)
        GC.Chat.lastAutoPost = nil
    end
    self:RefreshPostBar()
    self:RefreshPost()
end

function GC.UI:RefreshPostBar()
    local bar = self.postBar
    if not bar or not bar:IsShown() then
        return
    end

    local recruitment = GC.DB:GetGuild().recruitment
    local confirmed = recruitment.confirmedText or ""
    if confirmed == "" then
        bar.text:SetText(GC.L("|cffffb840Kein bestätigter Text. Unter „Werbung posten“ bestätigen.|r"))
    else
        -- Voller Text statt 110 Bytes: Was hier steht, geht so in den Chat.
        bar.text:SetText(GC.Util.SafeChatText(confirmed, GC.Constants.MAX_CHAT_BYTES))
    end

    -- Ein Kanal ist bereit, wenn er ausgewählt, beigetreten und ohne Cooldown
    -- ist. Der laengste Cooldown steht als Countdown im Knopf.
    local ready = 0
    local waiting = 0
    local longest = 0
    for _, kind in ipairs({ "RECRUITMENT", "LFG", "TRADE", "GENERAL" }) do
        if GC.DB:GetSettings().channels[kind] then
            local remaining = GC.Chat:GetRemainingCooldown(kind)
            if remaining > 0 then
                waiting = waiting + 1
                longest = math.max(longest, remaining)
            elseif GC.Chat:FindChannel(kind) then
                ready = ready + 1
            end
        end
    end

    local canSend = confirmed ~= "" and ready > 0
    SetButtonEnabled(bar.sendButton, canSend)
    if longest > 0 and ready == 0 then
        bar.sendButton:SetText(math.ceil(longest) .. "s Cooldown")
    else
        bar.sendButton:SetText(GC.L("Suche starten"))
    end

    -- Die Automatik ist genau dann scharf, wenn jetzt auch ein Klick posten
    -- wuerde. Das wird in jedem Takt neu entschieden: Ein abgewaehlter Kanal,
    -- ein geaenderter, nicht neu bestaetigter Text oder der Cooldown
    -- entschaerfen von selbst - der Tastendruck prueft danach ohnehin alles
    -- noch einmal.
    local automatik = GC.DB:GetSettings().postBar.autoRepeat == true
        and GC.Chat:IsAutoPostSupported()
    GC.Chat:SetAutoPostArmed("recruitment", automatik and canSend)
    if bar.autoToggle then
        SetToggle(bar.autoToggle, GC.DB:GetSettings().postBar.autoRepeat == true)
    end

    -- Die Statuszeile gehoert der Automatik, solange sie an ist: Was gerade
    -- passiert ist (sechs Sekunden lang), was als Naechstes passiert, oder
    -- woran es haengt. Ohne Automatik bleibt die bisherige Kanalzaehlung.
    local recent = GC.Chat.lastAutoPost
    if automatik and recent and (GC.Util.Now() - (recent.at or 0)) < 6 then
        bar.status:SetText("Automatik: " .. recent.message)
        SetTextColor(bar.status, recent.success and THEME.success or THEME.warning)
    elseif automatik and canSend then
        bar.status:SetText("Automatik: der nächste Tastendruck postet (" .. ready .. " bereit).")
        SetTextColor(bar.status, THEME.success)
    elseif automatik and confirmed == "" then
        bar.status:SetText(GC.L("Automatik wartet auf einen bestätigten Text."))
        SetTextColor(bar.status, THEME.warning)
    elseif automatik and longest > 0 then
        bar.status:SetText("Automatik: nächster Post in " .. math.ceil(longest) .. "s.")
        SetTextColor(bar.status, THEME.muted)
    elseif automatik then
        bar.status:SetText(GC.L("Automatik: kein ausgewählter Kanal beigetreten."))
        SetTextColor(bar.status, THEME.warning)
    elseif canSend and GC.Chat:IsAutoPostSupported() then
        -- Die haeufigste Rueckfrage zum Balken war "warum muss ich nach dem
        -- Cooldown wieder klicken?" - der Haken direkt darueber nimmt einem
        -- genau das ab. Der Satz steht nur, wenn ein Klick jetzt auch posten
        -- wuerde; sonst zaehlt die Kanalzeile wie bisher.
        bar.status:SetText(GC.L("Tipp: „Automatisch wiederholen“ erspart das erneute Klicken."))
        SetTextColor(bar.status, THEME.muted)
    elseif bar.status:GetText() == "" or waiting > 0 or ready > 0 then
        bar.status:SetText(ready .. " Kanäle bereit"
            .. (waiting > 0 and ("  •  " .. waiting .. " im Cooldown") or ""))
        SetTextColor(bar.status, ready > 0 and THEME.muted or THEME.warning)
    end
end

local function MinimapAngle(y, x)
    if math.atan2 then
        return math.atan2(y, x)
    elseif x > 0 then
        return math.atan(y / x)
    elseif x < 0 and y >= 0 then
        return math.atan(y / x) + math.pi
    elseif x < 0 then
        return math.atan(y / x) - math.pi
    elseif y > 0 then
        return math.pi / 2
    elseif y < 0 then
        return -math.pi / 2
    end
    return 0
end

-- Die Forever-Minimap kann ihre Groesse aendern. Der Knopf folgt dem Rand
-- statt einem festen Radius innerhalb der Karte; seine Mitte sitzt am Rahmen.
local function MinimapRadii()
    return (tonumber(Minimap:GetWidth()) or 148) / 2 + 4,
        (tonumber(Minimap:GetHeight()) or 148) / 2 + 4
end

-- Alles in UIParent-Einheiten rechnen. GetCursorPosition liefert
-- Bildschirmpixel, GetCenter dagegen Koordinaten im Massstab des jeweiligen
-- Rahmens - und Minimap und UIParent koennen verschieden skaliert sein. Wer
-- beides ungerechnet vergleicht, misst Unsinn.
local function MinimapCenterInUISpace()
    if not Minimap or type(Minimap.GetCenter) ~= "function" then
        return nil, nil
    end
    local centerX, centerY = Minimap:GetCenter()
    if not centerX or not centerY then
        return nil, nil
    end
    local minimapScale = (Minimap.GetEffectiveScale and Minimap:GetEffectiveScale()) or 1
    local scale = UIScale()
    return centerX * minimapScale / scale, centerY * minimapScale / scale
end

-- Frei steht nur das Wappen, am Minimap-Rand mit dem gewohnten Rahmen.
local function ApplyMinimapButtonChrome(button, free)
    button.border:SetShown(not free)
    button.background:SetShown(not free)
    button.icon:ClearAllPoints()
    if free then
        button.icon:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.icon:SetSize(28, 28)
    else
        button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -6)
        button.icon:SetSize(17, 17)
    end
end

function GC.UI:PositionMinimapButton()
    local button = self.minimapButton
    if not button or not Minimap then
        return
    end
    local settings = GC.DB:GetSettings().minimap
    button:ClearAllPoints()
    ApplyMinimapButtonChrome(button, settings.free == true)
    if settings.free and UIParent then
        if button:GetParent() ~= UIParent then
            button:SetParent(UIParent)
            button:SetFrameStrata("MEDIUM")
        end
        button:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
            tonumber(settings.x) or 0, tonumber(settings.y) or 0)
        return
    end
    if button:GetParent() ~= Minimap then
        button:SetParent(Minimap)
        button:SetFrameStrata("MEDIUM")
    end
    local angle = math.rad(tonumber(settings.angle) or 225)
    local radiusX, radiusY = MinimapRadii()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radiusX, math.sin(angle) * radiusY)
end

-- Rueckweg, falls das Symbol irgendwo landet, wo es nicht mehr zu greifen ist.
function GC.UI:ResetMinimapButton()
    local settings = GC.DB:GetSettings().minimap
    settings.free = false
    settings.angle = 225
    settings.x = 0
    settings.y = 0
    self:PositionMinimapButton()
end

function GC.UI:RefreshMinimapButton()
    if not self.minimapButton then
        return
    end
    self:PositionMinimapButton()
    self.minimapButton:SetShown(not GC.DB:GetSettings().minimap.hidden)
end

function GC.UI:AddMinimapButton()
    if self.minimapButton or not Minimap then
        return
    end

    local button = CreateFrame("Button", "GuildCopilotForeverMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    button.background = background

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -6)
    icon:SetTexture("Interface\\AddOns\\GuildCopilotForever\\Media\\GuildCopilotForeverLogo")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button.border = border
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Solange die Einrichtung offen ist, sitzt ein Punkt am Symbol. Er ist das
    -- einzige Zeichen bei geschlossenem Fenster - ohne ihn merkt niemand, dass
    -- noch etwas aussteht, sobald das Willkommensfenster einmal weg ist. Er
    -- verschwindet von selbst und wiederholt sich nie im Chat.
    local pending = button:CreateTexture(nil, "OVERLAY", nil, 7)
    pending:SetSize(9, 9)
    pending:SetPoint("TOPRIGHT", button, "TOPRIGHT", -6, -4)
    pending:SetTexture(WHITE_TEXTURE)
    SetTextureColor(pending, THEME.accent)
    pending:Hide()
    button.pending = pending

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            GC.UI:CreateMainFrame()
            GC.UI.frame:Show()
            GC.UI:ShowPage("SETTINGS")
        else
            GC.UI:Toggle()
        end
    end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(GC.L("Guild Copilot"))
        local nextStep = GC.Onboarding:GetNextStep()
        if nextStep then
            GameTooltip:AddLine("Einrichtung offen: " .. nextStep, 0.18, 0.78, 0.86, true)
            GameTooltip:AddLine(" ")
        end
        GameTooltip:AddLine("Linksklick: öffnen/schließen", 1, 1, 1)
        GameTooltip:AddLine("Rechtsklick: Einstellungen", 1, 1, 1)
        GameTooltip:AddLine(GC.L("Ziehen: entlang des Minimap-Rands"), 1, 1, 1)
        GameTooltip:AddLine(GC.L("Umschalt + Ziehen: frei platzieren"), 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    -- Den Modus beim Start festlegen: normales Ziehen heftet an, Umschalt
    -- platziert frei. Die Entfernung allein loest den Knopf nicht mehr ab.
    button:SetScript("OnDragStart", function(self)
        local freeDrag = IsShiftKeyDown and IsShiftKeyDown()
        self:SetScript("OnUpdate", function()
            local cursorX, cursorY = CursorInUISpace()
            if not cursorX or not cursorY then
                return
            end
            local settings = GC.DB:GetSettings().minimap
            if freeDrag then
                settings.free = true
                settings.x, settings.y = math.floor(cursorX), math.floor(cursorY)
                GC.UI:PositionMinimapButton()
                return
            end
            local centerX, centerY = MinimapCenterInUISpace()
            if centerX and centerY then
                local offsetX = cursorX - centerX
                local offsetY = cursorY - centerY
                settings.free = false
                if offsetX ~= 0 or offsetY ~= 0 then
                    local radiusX, radiusY = MinimapRadii()
                    settings.angle = math.deg(MinimapAngle(offsetY / radiusY, offsetX / radiusX))
                end
                GC.UI:PositionMinimapButton()
            end
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    self.minimapButton = button
    Minimap:HookScript("OnSizeChanged", function() GC.UI:PositionMinimapButton() end)
    Minimap:HookScript("OnShow", function() GC.UI:PositionMinimapButton() end)
    self:RefreshMinimapButton()
    self:RefreshMinimapMarker()
end

-- Die Slash-Befehle an genau einer Stelle. Daraus entstehen die Ausgabe von
-- "/gcp help" und die Liste auf der Addon-Optionsseite: Zwei getrennte
-- Aufzaehlungen laufen auseinander, sobald ein Befehl dazukommt - und die
-- Liste, die niemand pflegt, ist dann die falsche.
-- === Sitzungsfrage beim Instanzbeitritt =====================================
-- Wer eine Raidinstanz betritt und Sitzungen steuern darf, wird gefragt, ob
-- die Auswertung mitlaufen soll (Owner-Wunsch). Ein kleines Fenster, keine
-- Automatik: Gestartet wird nur per Klick.

function GC.UI:ShowSessionPrompt(zoneName)
    if not self.sessionPrompt then
        local prompt = CreatePanel(UIParent, THEME.window, THEME.accent, "GuildCopilotForeverSessionPrompt")
        prompt:SetSize(420, 124)
        prompt:SetPoint("TOP", UIParent, "TOP", 0, -180)
        prompt:SetFrameStrata("DIALOG")
        prompt:SetClampedToScreen(true)
        prompt:SetMovable(true)
        prompt:EnableMouse(true)
        prompt:RegisterForDrag("LeftButton")
        prompt:SetScript("OnDragStart", prompt.StartMoving)
        prompt:SetScript("OnDragStop", prompt.StopMovingOrSizing)
        prompt.title = CreateLabel(prompt, "Raidinstanz betreten", { title = true, width = 320 })
        prompt.title:SetPoint("TOPLEFT", prompt, "TOPLEFT", 16, -12)
        prompt.closeX = CreateButton(prompt, "×", 22, 22, function()
            prompt:Hide()
        end)
        prompt.closeX:SetPoint("TOPRIGHT", prompt, "TOPRIGHT", -8, -8)
        prompt.text = CreateLabel(prompt, "", { muted = true, width = 388, height = 30, vertical = "TOP" })
        prompt.text:SetPoint("TOPLEFT", prompt, "TOPLEFT", 16, -38)
        prompt.startButton = CreateButton(prompt, "Sitzung starten", 150, 30, function()
            local ok, message = GC.RaidMonitor:BeginSession()
            GC:Print(message)
            prompt:Hide()
            if ok then
                GC.UI:Invalidate("STATISTICS")
            end
        end, "PRIMARY")
        prompt.startButton:SetPoint("BOTTOMLEFT", prompt, "BOTTOMLEFT", 16, 12)
        prompt.gearButton = CreateButton(prompt, "Gruppe prüfen", 140, 30, function()
            local ok, message = GC.GearAudit:StartRaidScan()
            GC.UI:ShowGroupGearCheck()
            local frame = GC.UI.groupGearCheck
            if frame then
                frame.status:SetText(message or "")
                SetTextColor(frame.status, ok and THEME.success or THEME.danger)
            end
        end)
        prompt.gearButton:SetPoint("LEFT", prompt.startButton, "RIGHT", 8, 0)
        prompt.dismissButton = CreateButton(prompt, "Nicht jetzt", 100, 30, function()
            prompt:Hide()
        end)
        prompt.dismissButton:SetPoint("BOTTOMRIGHT", prompt, "BOTTOMRIGHT", -16, 12)
        prompt:Hide()
        self.sessionPrompt = prompt
    end
    self.sessionPrompt.text:SetText(GC.Util.Trim(zoneName or "") ~= ""
        and ("Du bist in „" .. zoneName .. "“. Auswertung mitschreiben? Ausrüstung checken?")
        or "Du hast eine Raidinstanz betreten. Auswertung mitschreiben? Ausrüstung checken?")
    self.sessionPrompt:Show()
end

GC:RegisterCallback("RAID_SESSION_PROMPT", GC.UI, function(self, zoneName)
    self:ShowSessionPrompt(zoneName)
end)

-- Startet jemand anderes die Sitzung, ist die Frage beantwortet. Das Fenster
-- schloss sich dabei wortlos - wer gerade danach greifen wollte, sah nur noch,
-- dass es weg war. Jetzt steht im Chat, wer schneller war.
GC:RegisterCallback("RAID_SESSION_UPDATED", GC.UI, function(self)
    if self.sessionPrompt and self.sessionPrompt:IsShown() and GC.RaidMonitor.session then
        self.sessionPrompt:Hide()
        local startedBy = GC.Util.PlayerIdentityName(GC.RaidMonitor.session.startedBy or "")
        if startedBy ~= "" and GC.Util.NormalizeName(startedBy)
            ~= GC.Util.NormalizeName(GC.Util.PlayerIdentityName(GC:GetPlayerFullName())) then
            GC:Print("Die Raidsitzung läuft bereits – gestartet von " .. startedBy
                .. ". Du schreibst automatisch mit.")
        end
    end
end)

-- === Gruppenprüfung Ausrüstung ==============================================
-- "Gruppe prüfen" zeigt die AKTUELLE Gruppe in einem eigenen Fenster
-- (Owner-Wunsch): nur die Leute von jetzt, je Zeile der Befund - statt der
-- großen Dauerliste aller je geprüften Spieler auf der Seite.

local GEAR_SOURCE_LABELS = { INSPECT = "Inspect", SYNC = "Addon", SELF = "Eigene Daten" }

function GC.UI:CreateGroupGearFrame()
    if self.groupGearCheck then
        return self.groupGearCheck
    end
    local frame = CreatePanel(UIParent, THEME.window, THEME.accent, "GuildCopilotForeverGroupGearCheck")
    frame:SetSize(520, 458)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetFrameStrata("DIALOG")
    -- Wie das Hauptfenster: Der letzte Klick holt das Fenster nach vorn.
    -- Ohne dieses Flag läge es nach einem Klick ins Addon dauerhaft dahinter.
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame.title = CreateLabel(frame, "Gruppenprüfung – Ausrüstung", { title = true, width = 340 })
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    frame.subtitle = CreateLabel(frame, "", { muted = true, width = 470, height = 26, vertical = "TOP" })
    frame.subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -36)
    frame.closeX = CreateButton(frame, "×", 24, 24, function()
        frame:Hide()
    end)
    frame.closeX:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)

    frame.headName = CreateLabel(frame, "NAME", { muted = true, font = "GameFontNormalSmall", width = 120, height = 14 })
    frame.headName:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -68)
    frame.headStand = CreateLabel(frame, "STAND", { muted = true, font = "GameFontNormalSmall", width = 90, height = 14 })
    frame.headStand:SetPoint("TOPLEFT", frame, "TOPLEFT", 150, -68)
    frame.headBefund = CreateLabel(frame, "BEFUND", { muted = true, font = "GameFontNormalSmall", width = 240, height = 14 })
    frame.headBefund:SetPoint("TOPLEFT", frame, "TOPLEFT", 252, -68)

    local body = CreatePanel(frame, THEME.input)
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -86)
    body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 78)
    frame.scroll = CreateModernScrollFrame(body)
    frame.scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -6)
    frame.scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -10, 6)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetWidth(470)
    frame.content:SetHeight(280)
    frame.scroll:SetScrollChild(frame.content)

    frame.rows = {}
    for index = 1, 40 do
        local row = CreateFrame("Frame", nil, frame.content)
        row:SetSize(470, 24)
        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -((index - 1) * 26))
        row.name = CreateLabel(row, "", { width = 126, height = 24 })
        row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.stand = CreateLabel(row, "", { muted = true, width = 96, height = 24 })
        row.stand:SetPoint("LEFT", row, "LEFT", 134, 0)
        row.befund = CreateLabel(row, "", { width = 230, height = 24 })
        row.befund:SetPoint("LEFT", row, "LEFT", 236, 0)
        -- In der Gruppenliste öffnet ein Klick die Verzauberungs-Details des
        -- Spielers; in der Detailansicht sind die Zeilen nur Anzeige.
        row:EnableMouse(true)
        row:SetScript("OnMouseUp", function()
            if row.auditName then
                GC.UI:SelectGroupGearPlayer(row.auditName)
            end
        end)
        row:Hide()
        frame.rows[index] = row
    end

    frame.counts = CreateLabel(frame, "", { width = 490, height = 18 })
    frame.counts:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 52)
    frame.rescan = CreateButton(frame, "Erneut prüfen", 130, 30, function()
        local ok, message = GC.GearAudit:StartRaidScan()
        frame.status:SetText(message or "")
        SetTextColor(frame.status, ok and THEME.success or THEME.danger)
        GC.UI:RefreshGroupGearCheck()
    end, "PRIMARY")
    frame.rescan:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 12)
    -- Kein Pfeilzeichen: "←" fehlt in der WoW-Schrift und wird als Kästchen
    -- gezeichnet.
    frame.back = CreateButton(frame, "Zur Gruppe", 130, 30, function()
        frame.detailName = nil
        GC.UI:RefreshGroupGearCheck()
    end)
    frame.back:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 12)
    frame.back:Hide()
    frame.status = CreateLabel(frame, "", { muted = true, width = 230, height = 30, vertical = "TOP" })
    frame.status:SetPoint("LEFT", frame.rescan, "RIGHT", 10, 0)
    frame.closeButton = CreateButton(frame, "Schließen", 110, 30, function()
        frame:Hide()
    end)
    frame.closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 12)

    frame:Hide()
    self.groupGearCheck = frame
    return frame
end

function GC.UI:ShowGroupGearCheck()
    local frame = self:CreateGroupGearFrame()
    frame.detailName = nil
    frame:Show()
    -- Vor das Addonfenster legen: gleiche Ebene, aber zuletzt gezeigt.
    if frame.Raise then
        frame:Raise()
    end
    self:RefreshGroupGearCheck()
end

-- Klick auf einen Spieler in der Gruppenliste: Detailansicht mit allen
-- Slots, Verzauberungen und Sockeln dieses Spielers.
function GC.UI:SelectGroupGearPlayer(name)
    local frame = self.groupGearCheck
    if not frame or not GC.GearAudit:GetAudit(name) then
        return
    end
    frame.detailName = name
    self:RefreshGroupGearCheck()
end

function GC.UI:RefreshGroupGearCheck()
    local frame = self.groupGearCheck
    if not frame or not frame:IsShown() then
        return
    end
    local now = GC.Util.Now()

    -- Detailansicht: alle Slots eines Spielers mit Bewertung, Verzauberung
    -- und Sockeln - dieselben Daten wie auf der Ausrüstungsseite, nur direkt
    -- im Gruppenfenster.
    local detail = frame.detailName and GC.GearAudit:GetAudit(frame.detailName)
    frame.back:SetShown(detail ~= nil)
    frame.rescan:SetShown(detail == nil)
    if detail then
        frame.subtitle:SetText(GC.L("„Zur Gruppe“ führt zurück zur Übersicht."))
        frame.headName:SetText(GC.L("SLOT"))
        frame.headStand:SetText(GC.L("BEWERTUNG"))
        frame.headBefund:SetText(GC.L("VERZAUBERUNG & SOCKEL"))
        local slots = detail.slots or {}
        for index, row in ipairs(frame.rows) do
            local entry = slots[index]
            row:SetShown(entry ~= nil)
            row.auditName = nil
            if entry then
                row.name:SetText(entry.label or entry.key or "?")
                row.name:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3], 1)
                local style = entry.verdict == "EXEMPT"
                    and { label = "Ausnahme", color = THEME.muted }
                    or GEAR_VERDICT_STYLE[entry.verdict] or GEAR_VERDICT_STYLE.UNKNOWN
                row.stand:SetText(style.label)
                SetTextColor(row.stand, style.color)
                local text = GC.Util.Trim(entry.enchantName or "")
                if text == "" then
                    text = GC.Util.Trim(entry.reason or "")
                end
                if (entry.emptySockets or 0) > 0 then
                    text = text .. " |cffff6166· " .. entry.emptySockets .. " Sockel leer|r"
                end
                if GC.Util.Trim(text) == "" then
                    text = "–"
                end
                row.befund:SetText(text)
                if entry.verdict == "MISSING" then
                    SetTextColor(row.befund, THEME.danger)
                elseif entry.verdict == "OPTIMAL" then
                    SetTextColor(row.befund, THEME.success)
                else
                    SetTextColor(row.befund, THEME.text)
                end
            end
        end
        local age = math.max(0, math.floor((now - (detail.inspectedAt or now)) / 60))
        -- Kurzform, sonst schneidet die Fußzeile ab: "keine Funde" statt des
        -- ganzen Satzes aus DescribeFindings.
        local findingsText = GC.GearAudit:GetIssueCount(detail) > 0
            and GC.GearAudit:DescribeFindings(detail) or "keine Funde"
        frame.counts:SetText("|cff4ec9ff" .. GC.Util.PlayerIdentityName(detail.name or "")
            .. "|r · " .. (GEAR_SOURCE_LABELS[detail.source] or "Daten")
            .. " vor " .. age .. " Min. · " .. findingsText)
        frame.content:SetHeight(math.max(280, #slots * 26))
        frame.scroll:UpdateModernThumb()
        return
    end

    frame.subtitle:SetText(GC.L("Nur die aktuelle Gruppe. Addon-Nutzer liefern selbst, der Rest per "
        .. "Inspect in Reichweite. Klick auf eine Zeile zeigt die Verzauberungen."))
    frame.headName:SetText(GC.L("NAME"))
    frame.headStand:SetText(GC.L("STAND"))
    frame.headBefund:SetText(GC.L("BEFUND"))
    local ok, findings, missing = 0, 0, 0
    local entries = {}
    -- Dieselbe Gruppenliste wie der Versionsprüfer; solo steht man allein drin.
    local targets = self:GetVersionCheckTargets("GROUP")
    if #targets == 0 then
        targets = { { name = GC:GetPlayerFullName() } }
    end
    for _, target in ipairs(targets) do
        local audit = GC.GearAudit:GetAudit(target.name)
        local entry = { name = target.name, classFile = target.classFile }
        if audit then
            local age = math.max(0, math.floor((now - (audit.inspectedAt or now)) / 60))
            entry.stand = (GEAR_SOURCE_LABELS[audit.source] or "Daten")
                .. " · vor " .. age .. " Min."
            local issues = GC.GearAudit:GetIssueCount(audit)
            if issues > 0 then
                entry.befund = GC.GearAudit:DescribeFindings(audit)
                entry.state = "FINDINGS"
                findings = findings + 1
            else
                entry.befund = "ok"
                entry.state = "OK"
                ok = ok + 1
            end
        else
            entry.stand = "–"
            entry.befund = "keine Daten (kein Addon / außer Reichweite)"
            entry.state = "NONE"
            missing = missing + 1
        end
        entries[#entries + 1] = entry
    end
    local ORDER = { FINDINGS = 1, NONE = 2, OK = 3 }
    table.sort(entries, function(left, right)
        if ORDER[left.state] ~= ORDER[right.state] then
            return ORDER[left.state] < ORDER[right.state]
        end
        return tostring(left.name) < tostring(right.name)
    end)
    for index, row in ipairs(frame.rows) do
        local entry = entries[index]
        row:SetShown(entry ~= nil)
        row.auditName = nil
        if entry then
            row.name:SetText(GC.Util.PlayerIdentityName(entry.name))
            row.name:SetTextColor(ClassColor(entry.classFile))
            row.stand:SetText(entry.stand)
            row.befund:SetText(entry.befund)
            if entry.state ~= "NONE" then
                row.auditName = entry.name
            end
            if entry.state == "OK" then
                SetTextColor(row.befund, THEME.success)
            elseif entry.state == "FINDINGS" then
                SetTextColor(row.befund, THEME.danger)
            else
                SetTextColor(row.befund, THEME.muted)
            end
        end
    end
    frame.counts:SetText("|cff59e695" .. ok .. " ok|r · |cffff6266" .. findings
        .. " mit Funden|r · " .. missing .. " ohne Daten")
    frame.content:SetHeight(math.max(280, #entries * 26))
    frame.scroll:UpdateModernThumb()
end

-- === Auswertungsfenster =====================================================
-- Ein Raidabend im eigenen Fenster: jede Quelle (Live, Warcraft Logs,
-- Combat Log) einzeln ansehen oder zwei Quellen direkt gegenüberstellen.
-- Der Vergleich zeigt je Spieler zwei Zeilen - oben die erste Quelle, unten
-- die zweite - und färbt Werte gelb, wo die Quellen sich widersprechen.

-- Gleiche Reihenfolge wie die Standardordnung der Raidauswertungsseite:
-- Proviant direkt neben der Anwesenheit, Kampfwerte dahinter.
local REVIEW_COLS = {
    { key = "time",  head = "TIME",  x = 166, w = 56 },
    { key = "elix",  head = "ELIX",  x = 226, w = 44 },
    { key = "food",  head = "FOOD",  x = 274, w = 44 },
    { key = "flask", head = "FLASK", x = 322, w = 48 },
    { key = "drum",  head = "DRUM",  x = 374, w = 46 },
    { key = "death", head = "DEATH", x = 424, w = 48 },
    { key = "res",   head = "RES",   x = 476, w = 40 },
    { key = "pot",   head = "POT",   x = 520, w = 40 },
    { key = "disp",  head = "DISP",  x = 564, w = 44 },
    { key = "int",   head = "INT",   x = 612, w = 40 },
}

-- Rohwerte eines Teilnehmers je Spalte. TIME vergleicht auf Minutenbasis,
-- sonst gälte jede Sekunde Abweichung als Widerspruch.
local function ReviewValues(participant)
    local consumables = (participant and participant.consumables) or {}
    return {
        time = math.floor(((participant and participant.seconds) or 0) / 60),
        death = (participant and participant.deaths) or 0,
        res = (participant and participant.resurrects) or 0,
        int = (participant and participant.interrupts) or 0,
        disp = (participant and participant.dispels) or 0,
        pot = (consumables.POTION or 0) + (consumables.RUNE or 0),
        flask = consumables.FLASK or 0,
        elix = consumables.ELIXIR or 0,
        food = consumables.FOOD or 0,
        drum = consumables.DRUM or 0,
    }
end

local function ReviewCellText(key, values)
    if key == "time" then
        return values.time .. "m"
    end
    return tostring(values[key] or 0)
end

function GC.UI:CreateSessionReviewFrame()
    if self.sessionReview then
        return self.sessionReview
    end
    local frame = CreatePanel(UIParent, THEME.window, THEME.accent, "GuildCopilotForeverSessionReview")
    frame:SetSize(720, 540)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame.title = CreateLabel(frame, "Raidauswertung – Detail", { title = true, width = 400 })
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    frame.closeX = CreateButton(frame, "×", 24, 24, function()
        frame:Hide()
    end)
    frame.closeX:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    frame.headline = CreateLabel(frame, "", { muted = true, width = 688, height = 16 })
    frame.headline:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -40)

    frame.sourceButtons = {}
    for index = 1, 3 do
        local button = CreateButton(frame, "", 150, 24, function()
            local target = frame.sourceButtons[index].summaryID
            if target then
                frame.selectedID = target
                frame.compare = false
                GC.UI:RefreshSessionReview()
            end
        end)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", 14 + ((index - 1) * 156), -62)
        button:Hide()
        frame.sourceButtons[index] = button
    end
    frame.compareButton = CreateButton(frame, "Vergleich", 150, 24, function()
        frame.compare = not frame.compare
        GC.UI:RefreshSessionReview()
    end)
    frame.compareButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 14 + (3 * 156), -62)
    frame.compareButton:Hide()

    CreateLabel(frame, "NAME", { muted = true, font = "GameFontNormalSmall", width = 140, height = 14 })
        :SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -98)
    for _, col in ipairs(REVIEW_COLS) do
        CreateLabel(frame, col.head, { muted = true, font = "GameFontNormalSmall", width = col.w, height = 14 })
            :SetPoint("TOPLEFT", frame, "TOPLEFT", 14 + col.x, -98)
    end

    local body = CreatePanel(frame, THEME.input)
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -114)
    body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 46)
    frame.scroll = CreateModernScrollFrame(body)
    frame.scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -6)
    frame.scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -10, 6)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetWidth(660)
    frame.content:SetHeight(360)
    frame.scroll:SetScrollChild(frame.content)

    frame.rows = {}
    for index = 1, 64 do
        local row = CreateFrame("Frame", nil, frame.content)
        row:SetSize(660, 18)
        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -((index - 1) * 20))
        row.name = CreateLabel(row, "", { width = 152, height = 18 })
        row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.cells = {}
        for _, col in ipairs(REVIEW_COLS) do
            local cell = CreateLabel(row, "", { width = col.w, height = 18 })
            cell:SetPoint("LEFT", row, "LEFT", col.x, 0)
            row.cells[col.key] = cell
        end
        row:Hide()
        frame.rows[index] = row
    end

    frame.note = CreateLabel(frame, "", { muted = true, width = 540, height = 26, vertical = "TOP" })
    frame.note:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 10)
    frame.closeButton = CreateButton(frame, "Schließen", 110, 30, function()
        frame:Hide()
    end)
    frame.closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 8)

    frame:Hide()
    self.sessionReview = frame
    return frame
end

function GC.UI:ShowSessionReview()
    local frame = self:CreateSessionReviewFrame()
    frame.anchorID = GC.RaidMonitor.selectedSessionID
    frame.selectedID = frame.anchorID
    frame.compare = false
    frame:Show()
    if frame.Raise then
        frame:Raise()
    end
    self:RefreshSessionReview()
end

-- Zwei Quellen für den Vergleich: Live zuerst, dann Warcraft Logs, dann die
-- Logdatei - genauere Quellen stehen oben.
local REVIEW_SOURCE_PRIORITY = { LIVE = 1, WCL = 2, LOG = 3, SYNC = 4 }

local function PickCompareSources(sources)
    local sorted = {}
    for index, source in ipairs(sources) do
        sorted[index] = source
    end
    table.sort(sorted, function(left, right)
        return (REVIEW_SOURCE_PRIORITY[left.source or "LIVE"] or 9)
            < (REVIEW_SOURCE_PRIORITY[right.source or "LIVE"] or 9)
    end)
    return sorted[1], sorted[2]
end

function GC.UI:RefreshSessionReview()
    local frame = self.sessionReview
    if not frame or not frame:IsShown() then
        return
    end
    local monitor = GC.RaidMonitor

    local evening = monitor:GetEveningOf(frame.anchorID)
    if not evening then
        -- Der Anker kann verschwinden (Livesitzung beendet und neu abgelegt):
        -- dann übernimmt die aktuelle Auswahl der Seite.
        frame.anchorID = monitor.selectedSessionID
        evening = monitor:GetEveningOf(frame.anchorID)
    end
    if not evening then
        frame.headline:SetText(GC.L("Keine Auswertung vorhanden. Auf der Seite Raidauswertung einen Abend wählen."))
        for _, row in ipairs(frame.rows) do
            row:Hide()
        end
        for _, button in ipairs(frame.sourceButtons) do
            button:Hide()
        end
        frame.compareButton:Hide()
        frame.note:SetText(GC.L(""))
        return
    end

    -- Auch hier nur die anzeigbaren Quellen: Fremde Mitschnitte tauchen im
    -- Vergleich nicht als wählbare Fassung auf, solange eine eigene existiert.
    local sources = evening.visibleSources or evening.sources
    local selectedValid = false
    for _, candidate in ipairs(sources) do
        if monitor:SummaryKey(candidate) == frame.selectedID then
            selectedValid = true
        end
    end
    if not selectedValid then
        frame.selectedID = monitor:SummaryKey(evening.summary)
    end
    if frame.compare and #sources < 2 then
        frame.compare = false
    end

    for index, button in ipairs(frame.sourceButtons) do
        local candidate = sources[index]
        button.summaryID = candidate and monitor:SummaryKey(candidate) or nil
        button:SetShown(candidate ~= nil)
        if candidate then
            button:SetText((SESSION_SOURCE_LABEL[candidate.source or "LIVE"] or "?")
                .. " (" .. #(candidate.participants or {}) .. ")")
            button:SetActive(not frame.compare and button.summaryID == frame.selectedID)
        end
    end
    frame.compareButton:SetShown(#sources > 1)
    if #sources > 1 then
        frame.compareButton:SetActive(frame.compare == true)
    end

    local shownRows = 0
    if not frame.compare then
        local summary = monitor:GetSummaryByKey(frame.selectedID) or evening.summary
        local zone = summary.zone ~= "" and summary.zone or "Raid"
        frame.headline:SetText(FormatSessionDate(summary) .. "  •  " .. zone
            .. "  •  " .. FormatDuration((summary.endedAt or 0) - (summary.startedAt or 0))
            .. "  •  " .. (summary.pulls or 0) .. " Versuche, " .. (summary.kills or 0)
            .. " Siege, " .. (summary.wipes or 0) .. " Wipes  •  Quelle: "
            .. (SESSION_SOURCE_LABEL[summary.source or "LIVE"] or "?"))

        local sessionSeconds = math.max(0, (summary.endedAt or 0) - (summary.startedAt or 0))
        if ENCOUNTER_TIME_SOURCES[GC.RaidMonitor:SourceKind(summary.source)] then
            sessionSeconds = 0
            for _, participant in ipairs(summary.participants or {}) do
                sessionSeconds = math.max(sessionSeconds, tonumber(participant.seconds) or 0)
            end
        end

        local participants = {}
        for index, participant in ipairs(summary.participants or {}) do
            participants[index] = participant
        end
        table.sort(participants, function(left, right)
            if (left.seconds or 0) ~= (right.seconds or 0) then
                return (left.seconds or 0) > (right.seconds or 0)
            end
            return tostring(left.name or "") < tostring(right.name or "")
        end)

        for index, row in ipairs(frame.rows) do
            local participant = participants[index]
            row:SetShown(participant ~= nil)
            if participant then
                shownRows = index
                row.name:SetText(participant.name)
                row.name:SetTextColor(ClassColor(participant.classFile))
                local values = ReviewValues(participant)
                -- Wie auf der Seite: FLASK/ELIXIR rot nur wenn BEIDES fehlt
                -- (ein Fläschchen ersetzt beide Elixiere), FOOD rot bei null.
                local uncovered = (values.flask or 0) == 0 and (values.elix or 0) == 0
                for _, col in ipairs(REVIEW_COLS) do
                    local cell = row.cells[col.key]
                    cell:SetText(ReviewCellText(col.key, values))
                    if col.key == "time" and sessionSeconds > 0 then
                        local share = (participant.seconds or 0) / sessionSeconds
                        if share < 0.5 then
                            SetTextColor(cell, THEME.danger)
                        elseif share < 0.85 then
                            SetTextColor(cell, THEME.warning)
                        else
                            SetTextColor(cell, THEME.text)
                        end
                    elseif (col.key == "flask" or col.key == "elix") and uncovered then
                        SetTextColor(cell, THEME.danger)
                    elseif col.key == "food" and (values.food or 0) == 0 then
                        SetTextColor(cell, THEME.danger)
                    else
                        SetTextColor(cell, THEME.text)
                    end
                end
            end
        end
        frame.note:SetText(#participants .. " Teilnehmer  •  TIME färbt sich unter 85 % bzw. 50 % Anwesenheit.")
    else
        local first, second = PickCompareSources(sources)
        local zone = evening.summary.zone ~= "" and evening.summary.zone or "Raid"
        local firstLabel = SESSION_SOURCE_LABEL[first.source or "LIVE"] or "?"
        local secondLabel = SESSION_SOURCE_LABEL[second.source or "LIVE"] or "?"
        -- "gegen" statt eines Pfeilsymbols: Sonderzeichen wie "↔" fehlen in
        -- der WoW-Schrift.
        frame.headline:SetText(FormatSessionDate(evening.summary) .. "  •  " .. zone
            .. "  •  Vergleich: " .. firstLabel .. " gegen " .. secondLabel)

        -- Beide Teilnehmerlisten über den Kurznamen vereinigen; wer nur in
        -- einer Quelle steht, bekommt auf der anderen Seite Striche.
        local index = {}
        local merged = {}
        for _, participant in ipairs(first.participants or {}) do
            local key = GC.Util.NormalizeName(GC.Util.PlayerIdentityName(participant.name or ""))
            local entry = { name = participant.name, classFile = participant.classFile, first = participant }
            index[key] = entry
            merged[#merged + 1] = entry
        end
        for _, participant in ipairs(second.participants or {}) do
            local key = GC.Util.NormalizeName(GC.Util.PlayerIdentityName(participant.name or ""))
            local entry = index[key]
            if entry then
                entry.second = participant
                entry.classFile = entry.classFile or participant.classFile
            else
                entry = { name = participant.name, classFile = participant.classFile, second = participant }
                index[key] = entry
                merged[#merged + 1] = entry
            end
        end
        table.sort(merged, function(left, right)
            local leftSeconds = ((left.first or left.second) or {}).seconds or 0
            local rightSeconds = ((right.first or right.second) or {}).seconds or 0
            if leftSeconds ~= rightSeconds then
                return leftSeconds > rightSeconds
            end
            return tostring(left.name or "") < tostring(right.name or "")
        end)

        for _, entry in ipairs(merged) do
            local firstRow = frame.rows[shownRows + 1]
            local secondRow = frame.rows[shownRows + 2]
            if not firstRow or not secondRow then
                break
            end
            shownRows = shownRows + 2
            local firstValues = entry.first and ReviewValues(entry.first)
            local secondValues = entry.second and ReviewValues(entry.second)

            firstRow:Show()
            firstRow.name:SetText(entry.name)
            firstRow.name:SetTextColor(ClassColor(entry.classFile))
            secondRow:Show()
            secondRow.name:SetText("   > " .. (entry.second and secondLabel or (secondLabel .. ": fehlt")))
            SetTextColor(secondRow.name, THEME.muted)

            for _, col in ipairs(REVIEW_COLS) do
                local firstCell = firstRow.cells[col.key]
                local secondCell = secondRow.cells[col.key]
                firstCell:SetText(firstValues and ReviewCellText(col.key, firstValues) or "–")
                secondCell:SetText(secondValues and ReviewCellText(col.key, secondValues) or "–")
                local differs = firstValues and secondValues
                    and firstValues[col.key] ~= secondValues[col.key]
                if differs then
                    SetTextColor(firstCell, THEME.warning)
                    SetTextColor(secondCell, THEME.warning)
                else
                    SetTextColor(firstCell, THEME.text)
                    SetTextColor(secondCell, THEME.muted)
                end
            end
        end
        for index = shownRows + 1, #frame.rows do
            frame.rows[index]:Hide()
        end
        frame.note:SetText("Obere Zeile " .. firstLabel .. ", untere " .. secondLabel
            .. ".  Gelb: Die Quellen widersprechen sich (TIME auf Minutenbasis).")
    end

    if not frame.compare then
        for index = shownRows + 1, #frame.rows do
            frame.rows[index]:Hide()
        end
    end
    frame.content:SetHeight(math.max(360, shownRows * 20))
    frame.scroll:UpdateModernThumb()
end

GC:RegisterCallback("RAID_SESSION_UPDATED", GC.UI, function(self)
    self:RefreshSessionReview()
end)
GC:RegisterCallback("WCL_UPDATED", GC.UI, function(self)
    self:RefreshSessionReview()
end)

-- === Verbrauchsprotokoll ====================================================
-- Klick auf einen Teilnehmer der Raidauswertung: Was genau hat er wann
-- eingeworfen? Live mitgeschriebene Sitzungen haben ein Protokoll mit
-- Uhrzeiten; Warcraft-Logs-Quellen liefern die exakten Gegenstände mit
-- Anzahl (Uhrzeiten kennt der Export nicht); für fremde Zusammenfassungen
-- bleiben die Kategoriezähler.

function GC.UI:CreateConsumableLogFrame()
    if self.consumableLogFrame then
        return self.consumableLogFrame
    end
    local frame = CreatePanel(UIParent, THEME.window, THEME.accent, "GuildCopilotForeverConsumableLog")
    frame:SetSize(430, 470)
    frame:SetPoint("CENTER", UIParent, "CENTER", 60, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame.title = CreateLabel(frame, "", { title = true, width = 340 })
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    frame.closeX = CreateButton(frame, "×", 24, 24, function()
        frame:Hide()
    end)
    frame.closeX:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    frame.subtitle = CreateLabel(frame, "", { muted = true, width = 398, height = 28, vertical = "TOP" })
    frame.subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -38)

    CreateLabel(frame, "ZEIT", { muted = true, font = "GameFontNormalSmall", width = 66, height = 14 })
        :SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -72)
    CreateLabel(frame, "WAS", { muted = true, font = "GameFontNormalSmall", width = 220, height = 14 })
        :SetPoint("TOPLEFT", frame, "TOPLEFT", 92, -72)
    CreateLabel(frame, "ART", { muted = true, font = "GameFontNormalSmall", width = 80, height = 14 })
        :SetPoint("TOPLEFT", frame, "TOPLEFT", 322, -72)

    local body = CreatePanel(frame, THEME.input)
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -90)
    body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 44)
    frame.scroll = CreateModernScrollFrame(body)
    frame.scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -6)
    frame.scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -10, 6)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetWidth(380)
    frame.content:SetHeight(320)
    frame.scroll:SetScrollChild(frame.content)

    frame.rows = {}
    for index = 1, 100 do
        local row = CreateFrame("Frame", nil, frame.content)
        row:SetSize(380, 18)
        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -((index - 1) * 20))
        row.time = CreateLabel(row, "", { muted = true, width = 66, height = 18 })
        row.time:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.name = CreateLabel(row, "", { width = 224, height = 18 })
        row.name:SetPoint("LEFT", row, "LEFT", 78, 0)
        row.cat = CreateLabel(row, "", { muted = true, width = 74, height = 18 })
        row.cat:SetPoint("LEFT", row, "LEFT", 308, 0)
        row:Hide()
        frame.rows[index] = row
    end

    frame.note = CreateLabel(frame, "", { muted = true, width = 280, height = 18 })
    frame.note:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 12)
    frame.closeButton = CreateButton(frame, "Schließen", 110, 28, function()
        frame:Hide()
    end)
    frame.closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 8)

    frame:Hide()
    self.consumableLogFrame = frame
    return frame
end

function GC.UI:ShowConsumableLog(participant)
    if not participant then
        return
    end
    local frame = self:CreateConsumableLogFrame()
    frame.participant = participant
    frame:Show()
    if frame.Raise then
        frame:Raise()
    end
    self:RefreshConsumableLog()
end

function GC.UI:RefreshConsumableLog()
    local frame = self.consumableLogFrame
    if not frame or not frame:IsShown() then
        return
    end
    local participant = frame.participant
    if not participant then
        frame:Hide()
        return
    end
    frame.title:SetText("Verbrauch: " .. tostring(participant.name or "?"))
    frame.title:SetTextColor(ClassColor(participant.classFile))

    local function CategoryLabel(key)
        local category = GC.ConsumableCategoryByKey[key]
        return (category and GC.L(category.label)) or tostring(key or "?")
    end

    local entries = {}
    local log = participant.consumableLog
    local items = participant.consumableItems
    if log and #log > 0 then
        for _, event in ipairs(log) do
            entries[#entries + 1] = {
                time = (date and date("%H:%M:%S", event.t)) or tostring(event.t or "?"),
                name = tostring(event.n or "?"),
                cat = CategoryLabel(event.c),
            }
        end
        frame.subtitle:SetText(GC.L("Live mitgeschrieben: jeder gezählte Einwurf mit Uhrzeit."))
        local dropped = tonumber(participant.consumableLogDropped) or 0
        frame.note:SetText(#entries .. " Einträge"
            .. (dropped > 0 and ("  ·  " .. dropped .. " ältere verworfen") or ""))
    elseif items and #items > 0 then
        for _, item in ipairs(items) do
            -- Erst die eigene Tabelle in der Clientsprache (die englischen
            -- Namen sind einzeln belegt), dann der beim Import gespeicherte
            -- Name, zuletzt der Spielclient.
            local consumable = item.s and GC.Consumables[tonumber(item.s)]
            local itemName = (consumable and GC.ConsumableDisplayName(consumable))
                or item.n
            if not itemName and item.s then
                if GC.API.GetSpellInfo then
                    itemName = GC.API.GetSpellInfo(item.s)
                end
                itemName = itemName or ("Zauber " .. tostring(item.s))
            end
            entries[#entries + 1] = {
                time = (item.count or 0) .. "×",
                name = tostring(itemName or "?"),
                cat = item.c and CategoryLabel(item.c) or "?",
            }
        end
        frame.subtitle:SetText(GC.L("Aus Warcraft Logs: exakte Gegenstände mit Anzahl - Uhrzeiten kennt der Export nicht."))
        frame.note:SetText(#entries .. " verschiedene Gegenstände")
    else
        for _, category in ipairs(GC.ConsumableCategories) do
            local count = (participant.consumables or {})[category.key] or 0
            if count > 0 then
                entries[#entries + 1] = { time = count .. "×", name = GC.L(category.label), cat = "" }
            end
        end
        frame.subtitle:SetText(GC.L("Diese Quelle liefert nur Kategoriezähler ohne Einzelheiten."))
        frame.note:SetText(#entries > 0 and (#entries .. " Kategorien") or "")
    end
    if #entries == 0 then
        frame.subtitle:SetText(GC.L("Für diesen Teilnehmer wurde kein Verbrauch erfasst."))
        frame.note:SetText(GC.L(""))
    end

    for index, row in ipairs(frame.rows) do
        local entry = entries[index]
        row:SetShown(entry ~= nil)
        if entry then
            row.time:SetText(entry.time)
            row.name:SetText(entry.name)
            row.cat:SetText(entry.cat)
        end
    end
    frame.content:SetHeight(math.max(320, #entries * 20))
    frame.scroll:UpdateModernThumb()
end

-- === Rezept-Lücken der Gilde ================================================
-- Empfohlene Verzauberungen (Regelsatz, laufende Phase), die niemand in der
-- Gilde herstellen kann - die fertige Farm- und Einkaufsliste für Offiziere.
-- Die Daten kommen aus GearAudit:GetMissingRecommendedRecipes.

local function GearSlotLabels(slotKeys)
    if type(slotKeys) ~= "table" or #slotKeys == 0 then
        return GC.L("alle Slots")
    end
    local labels = {}
    for _, slotKey in ipairs(slotKeys) do
        local label = slotKey
        for _, slot in ipairs(GC.GearSlots or {}) do
            if slot.key == slotKey then
                label = GC.L(slot.label)
                break
            end
        end
        labels[#labels + 1] = label
    end
    return table.concat(labels, ", ")
end

function GC.UI:CreateMissingRecipesFrame()
    if self.missingRecipesFrame then
        return self.missingRecipesFrame
    end
    local frame = CreatePanel(UIParent, THEME.window, THEME.accent, "GuildCopilotForeverMissingRecipes")
    frame:SetSize(500, 440)
    frame:SetPoint("CENTER", UIParent, "CENTER", 40, 10)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame.title = CreateLabel(frame, "Rezept-Lücken der Gilde", { title = true, width = 400 })
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    frame.closeX = CreateButton(frame, "×", 24, 24, function()
        frame:Hide()
    end)
    frame.closeX:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    frame.subtitle = CreateLabel(frame, "", { muted = true, width = 468, height = 30, vertical = "TOP" })
    frame.subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -38)

    CreateLabel(frame, "EMPFEHLUNG", { muted = true, font = "GameFontNormalSmall", width = 240, height = 14 })
        :SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -76)
    CreateLabel(frame, "SLOT", { muted = true, font = "GameFontNormalSmall", width = 130, height = 14 })
        :SetPoint("TOPLEFT", frame, "TOPLEFT", 268, -76)
    CreateLabel(frame, "STUFE", { muted = true, font = "GameFontNormalSmall", width = 70, height = 14 })
        :SetPoint("TOPLEFT", frame, "TOPLEFT", 406, -76)

    local body = CreatePanel(frame, THEME.input)
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -94)
    body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 44)
    frame.scroll = CreateModernScrollFrame(body)
    frame.scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -6)
    frame.scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -10, 6)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetWidth(450)
    frame.content:SetHeight(280)
    frame.scroll:SetScrollChild(frame.content)

    frame.rows = {}
    for index = 1, 40 do
        local row = CreateFrame("Frame", nil, frame.content)
        row:SetSize(450, 18)
        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -((index - 1) * 20))
        row.name = CreateLabel(row, "", { width = 244, height = 18 })
        row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.slot = CreateLabel(row, "", { muted = true, width = 134, height = 18 })
        row.slot:SetPoint("LEFT", row, "LEFT", 254, 0)
        row.verdict = CreateLabel(row, "", { width = 66, height = 18 })
        row.verdict:SetPoint("LEFT", row, "LEFT", 392, 0)
        row:Hide()
        frame.rows[index] = row
    end

    frame.note = CreateLabel(frame, "", { muted = true, width = 320, height = 18 })
    frame.note:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 12)
    frame.closeButton = CreateButton(frame, "Schließen", 110, 28, function()
        frame:Hide()
    end)
    frame.closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 8)

    frame:Hide()
    self.missingRecipesFrame = frame
    return frame
end

function GC.UI:ShowMissingRecipes()
    local frame = self:CreateMissingRecipesFrame()
    frame:Show()
    if frame.Raise then
        frame:Raise()
    end
    self:RefreshMissingRecipes()
end

function GC.UI:RefreshMissingRecipes()
    local frame = self.missingRecipesFrame
    if not frame or not frame:IsShown() then
        return
    end
    local missing = GC.GearAudit and GC.GearAudit:GetMissingRecommendedRecipes() or {}
    local phase = GC.ContentPhaseByKey[GC.GearAudit and GC.GearAudit:GetContentPhase() or ""]
    frame.subtitle:SetText("Vom Regelsatz empfohlen"
        .. (phase and (" (bis " .. phase.key .. ")") or "")
        .. ", aber niemand in der Gilde kann es herstellen – die Farm- und Einkaufsliste."
        .. " Der Stand wächst mit dem Rezeptabgleich der Werkstatt mit.")

    for index, row in ipairs(frame.rows) do
        local entry = missing[index]
        row:SetShown(entry ~= nil)
        if entry then
            row.name:SetText(entry.name or entry.recipeKey)
            row.slot:SetText(GearSlotLabels(entry.slots))
            row.verdict:SetText(entry.verdict == "OPTIMAL"
                and "|cff59e695Optimal|r" or "|cff4ec9ffSolide|r")
        end
    end
    frame.note:SetText(#missing == 0
        and "Keine Lücken: Alles Empfohlene kann jemand herstellen."
        or (#missing .. (#missing == 1 and " Lücke" or " Lücken")
            .. " im aktuellen Regelsatz"))
    frame.content:SetHeight(math.max(280, #missing * 20))
    frame.scroll:UpdateModernThumb()
end

GC:RegisterCallback("WORKSHOP_UPDATED", GC.UI, function(self)
    -- Eintreffende Rezeptdaten koennen Luecken schliessen; das offene Fenster
    -- zieht ohne eigenen Takt einfach mit.
    self:RefreshMissingRecipes()
end)

-- === Anwesenheit über Abende hinweg =========================================
-- Je Spieler: besuchte Abende und mittlerer Anwesenheitsanteil über alle
-- erfassten Bossabende. Die Daten kommen aus dem dauerhaften Aggregat
-- (RaidMonitor:GetAttendanceOverview), nicht aus der kurzlebigen Ablage.

function GC.UI:CreateAttendanceFrame()
    if self.attendanceFrame then
        return self.attendanceFrame
    end
    local frame = CreatePanel(UIParent, THEME.window, THEME.accent, "GuildCopilotForeverAttendance")
    frame:SetSize(500, 500)
    frame:SetPoint("CENTER", UIParent, "CENTER", 50, 10)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame.title = CreateLabel(frame, "Anwesenheit", { title = true, width = 400 })
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    frame.closeX = CreateButton(frame, "×", 24, 24, function()
        frame:Hide()
    end)
    frame.closeX:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    frame.subtitle = CreateLabel(frame, "", { muted = true, width = 468, height = 30, vertical = "TOP" })
    frame.subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -38)

    CreateLabel(frame, "NAME", { muted = true, font = "GameFontNormalSmall", width = 150, height = 14 })
        :SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -76)
    CreateLabel(frame, "ABENDE", { muted = true, font = "GameFontNormalSmall", width = 80, height = 14 })
        :SetPoint("TOPLEFT", frame, "TOPLEFT", 190, -76)
    CreateLabel(frame, "ANTEIL", { muted = true, font = "GameFontNormalSmall", width = 80, height = 14 })
        :SetPoint("TOPLEFT", frame, "TOPLEFT", 274, -76)
    CreateLabel(frame, "ZULETZT", { muted = true, font = "GameFontNormalSmall", width = 100, height = 14 })
        :SetPoint("TOPLEFT", frame, "TOPLEFT", 356, -76)

    local body = CreatePanel(frame, THEME.input)
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -94)
    body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 44)
    frame.scroll = CreateModernScrollFrame(body)
    frame.scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -6)
    frame.scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -10, 6)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetWidth(450)
    frame.content:SetHeight(340)
    frame.scroll:SetScrollChild(frame.content)

    frame.rows = {}
    for index = 1, 80 do
        local row = CreateFrame("Frame", nil, frame.content)
        row:SetSize(450, 18)
        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -((index - 1) * 20))
        row.name = CreateLabel(row, "", { width = 160, height = 18 })
        row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.evenings = CreateLabel(row, "", { width = 76, height = 18 })
        row.evenings:SetPoint("LEFT", row, "LEFT", 176, 0)
        row.percent = CreateLabel(row, "", { width = 76, height = 18 })
        row.percent:SetPoint("LEFT", row, "LEFT", 260, 0)
        row.last = CreateLabel(row, "", { muted = true, width = 100, height = 18 })
        row.last:SetPoint("LEFT", row, "LEFT", 342, 0)
        row:Hide()
        frame.rows[index] = row
    end

    frame.note = CreateLabel(frame, "", { muted = true, width = 320, height = 18 })
    frame.note:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 12)
    frame.closeButton = CreateButton(frame, "Schließen", 110, 28, function()
        frame:Hide()
    end)
    frame.closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 8)

    frame:Hide()
    self.attendanceFrame = frame
    return frame
end

function GC.UI:ShowAttendance()
    local frame = self:CreateAttendanceFrame()
    frame:Show()
    if frame.Raise then
        frame:Raise()
    end
    self:RefreshAttendance()
end

function GC.UI:RefreshAttendance()
    local frame = self.attendanceFrame
    if not frame or not frame:IsShown() then
        return
    end
    local rows, evenings = GC.RaidMonitor:GetAttendanceOverview()
    frame.subtitle:SetText("Mittlerer Anwesenheitsanteil über alle " .. evenings
        .. " erfassten Bossabende – ein verpasster Abend zählt mit 0 %."
        .. " Die Liste bleibt erhalten, auch wenn alte Auswertungen längst gelöscht sind.")

    for index, row in ipairs(frame.rows) do
        local entry = rows[index]
        row:SetShown(entry ~= nil)
        if entry then
            row.name:SetText(entry.name or "?")
            row.name:SetTextColor(ClassColor(entry.classFile))
            row.evenings:SetText(entry.attended .. " / " .. evenings)
            local red, green, blue = 1, 1, 1
            if entry.percent >= 75 then
                red, green, blue = 0.35, 0.9, 0.58
            elseif entry.percent < 40 then
                red, green, blue = 1, 0.72, 0.25
            end
            row.percent:SetText(entry.percent .. " %")
            row.percent:SetTextColor(red, green, blue)
            local lastText = ""
            if entry.lastAt > 0 and date then
                local ok, formatted = pcall(date, "%d.%m.", entry.lastAt)
                if ok and formatted then
                    lastText = formatted
                end
            end
            row.last:SetText(lastText)
        end
    end
    frame.note:SetText(evenings == 0
        and "Noch kein Bossabend erfasst – Abende ohne Bosskampf zählen nicht."
        or "Höchstens 60 Abende; Probesitzungen ohne Bosskampf zählen nicht.")
    frame.content:SetHeight(math.max(340, #rows * 20))
    frame.scroll:UpdateModernThumb()
end

GC:RegisterCallback("RAID_SESSION_UPDATED", GC.UI, function(self)
    self:RefreshAttendance()
end)

-- Der Antwortzähler zu "Auswertung anfordern": Ohne ihn wirkte der Knopf
-- wirkungslos - Antworten kamen still an oder still gar nicht.
GC:RegisterCallback("RAID_SUMMARY_ANSWERS", GC.UI, function(self)
    local page = self.pages and self.pages.STATISTICS
    if not page or not page.actionStatus then
        return
    end
    local stats = GC.RaidMonitor.requestStats
    if not stats then
        return
    end
    if stats.answers == 0 then
        page.actionStatus:SetText(GC.L("Auswertung angefragt - warte auf Antworten …"))
        SetTextColor(page.actionStatus, THEME.muted)
    else
        page.actionStatus:SetText(stats.answers .. " Antworten empfangen, davon "
            .. stats.new .. " neu oder vollständiger übernommen.")
        SetTextColor(page.actionStatus, THEME.success)
    end
end)

-- === Versionsprüfer =========================================================
-- /gcp ver: Wer in Gruppe oder Gilde hat Guild Copilot, und in welcher
-- Version? Grün ist der eigene Stand, rot ist älter, gelb wartet noch,
-- "Nicht installiert" hat nach acht Sekunden nicht geantwortet.

function GC.UI:CreateVersionCheckFrame()
    if self.versionCheck then
        return self.versionCheck
    end
    local frame = CreatePanel(UIParent, THEME.window, THEME.accent, "GuildCopilotForeverVersionCheck")
    frame:SetSize(470, 458)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame.title = CreateLabel(frame, "Versionsprüfer", { title = true, width = 280 })
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    frame.ownVersion = CreateLabel(frame, "Deine Version: " .. GC.Constants.VERSION,
        { muted = true, width = 380, height = 15 })
    frame.ownVersion:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -38)
    frame.closeX = CreateButton(frame, "×", 24, 24, function()
        frame:Hide()
    end)
    frame.closeX:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)

    CreateLabel(frame, "NAME", { muted = true, font = "GameFontNormalSmall", width = 140, height = 14 })
        :SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -62)
    CreateLabel(frame, "RANG", { muted = true, font = "GameFontNormalSmall", width = 120, height = 14 })
        :SetPoint("TOPLEFT", frame, "TOPLEFT", 190, -62)
    CreateLabel(frame, "VERSION", { muted = true, font = "GameFontNormalSmall",
        align = "RIGHT", width = 130, height = 14 })
        :SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -62)

    local body = CreatePanel(frame, THEME.input)
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -80)
    body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 78)
    frame.scroll = CreateModernScrollFrame(body)
    frame.scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -6)
    frame.scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -10, 6)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetWidth(420)
    frame.content:SetHeight(280)
    frame.scroll:SetScrollChild(frame.content)

    frame.rows = {}
    for index = 1, 40 do
        local row = CreateFrame("Frame", nil, frame.content)
        row:SetSize(420, 24)
        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -((index - 1) * 26))
        row.name = CreateLabel(row, "", { width = 160, height = 24 })
        row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.rank = CreateLabel(row, "", { muted = true, width = 120, height = 24 })
        row.rank:SetPoint("LEFT", row, "LEFT", 172, 0)
        row.version = CreateLabel(row, "", { align = "RIGHT", width = 124, height = 24 })
        row.version:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row:Hide()
        frame.rows[index] = row
    end

    -- Die Zusammenfassung hat ihre eigene Zeile über den Knöpfen - zwischen
    -- den Knöpfen wurde sie zerquetscht und "ohne Addon" abgeschnitten.
    frame.counts = CreateLabel(frame, "", { width = 440, height = 18 })
    frame.counts:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 52)
    frame.modeGuild = CreateButton(frame, "Gilde", 110, 30, function()
        GC.UI:SetVersionCheckMode("GUILD")
    end)
    frame.modeGuild:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 12)
    frame.modeGroup = CreateButton(frame, "Gruppe", 110, 30, function()
        GC.UI:SetVersionCheckMode("GROUP")
    end)
    frame.modeGroup:SetPoint("LEFT", frame.modeGuild, "RIGHT", 8, 0)
    frame.closeButton = CreateButton(frame, "Schließen", 110, 30, function()
        frame:Hide()
    end)
    frame.closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 12)

    frame:Hide()
    self.versionCheck = frame
    return frame
end

function GC.UI:ShowVersionCheck(mode)
    local frame = self:CreateVersionCheckFrame()
    frame:Show()
    self:SetVersionCheckMode(mode
        or ((IsInGroup and IsInGroup()) and "GROUP" or "GUILD"))
end

function GC.UI:SetVersionCheckMode(mode)
    local frame = self:CreateVersionCheckFrame()
    frame.mode = mode == "GROUP" and "GROUP" or "GUILD"
    frame.requestedAt = GC.Util.Now()
    frame.settled = false
    GC.Sync:RequestVersionCheck(frame.mode)
    if C_Timer and type(C_Timer.After) == "function" then
        local requestedAt = frame.requestedAt
        C_Timer.After(8, function()
            local current = GC.UI.versionCheck
            if current and current.requestedAt == requestedAt then
                current.settled = true
                GC.UI:RefreshVersionCheck()
            end
        end)
    else
        frame.settled = true
    end
    self:RefreshVersionCheck()
end

function GC.UI:GetVersionCheckTargets(mode)
    local targets = {}
    if mode == "GROUP" and IsInGroup and IsInGroup() then
        if IsInRaid and IsInRaid() then
            for index = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
                local name, _, _, _, _, classFile = GetRaidRosterInfo(index)
                if name then
                    targets[#targets + 1] = { name = name, classFile = classFile }
                end
            end
        else
            local _, ownClass = UnitClass("player")
            targets[#targets + 1] = { name = GC:GetPlayerFullName(), classFile = ownClass }
            for index = 1, math.max(0, (GetNumGroupMembers and GetNumGroupMembers() or 1) - 1) do
                local unit = "party" .. index
                if UnitExists and UnitExists(unit) then
                    local _, classFile = UnitClass(unit)
                    targets[#targets + 1] = { name = GC.Util.UnitIdentityName(unit), classFile = classFile }
                end
            end
        end
    else
        for _, member in ipairs(GC.Roster.members) do
            if member.online then
                targets[#targets + 1] = {
                    name = member.name,
                    classFile = member.classFile,
                    rank = member.rank,
                }
            end
        end
    end
    for _, target in ipairs(targets) do
        if not target.rank then
            local member = GC.Roster:GetMember(target.name)
            target.rank = (member and member.rank) or "–"
        end
    end
    return targets
end

-- AHEAD ist neu und war vorher schlicht falsch: Wer eine neuere Fassung fährt
-- als man selbst, stand rot unter „veraltet". Genau diese Zeilen sind aber die
-- Quelle des Aktualisierungshinweises - sie zählen nicht zu den Rückständigen,
-- sondern erklären ihn.
local VERSION_STATE_ORDER = { OLD = 1, NONE = 2, WAITING = 3, AHEAD = 4, CURRENT = 5 }

function GC.UI:RefreshVersionCheck()
    local frame = self.versionCheck
    if not frame or not frame:IsShown() then
        return
    end
    frame.modeGuild:SetActive(frame.mode ~= "GROUP")
    frame.modeGroup:SetActive(frame.mode == "GROUP")

    -- Wer den Prüfer öffnet, fragt nach Versionen. Steht die eigene nicht mehr
    -- ganz oben, gehört das genau hierher - und zwar bevor er in der Liste
    -- sucht, wer denn die grüne Zahl hat.
    local update = GC.Sync:GetAvailableUpdate()
    if update then
        frame.ownVersion:SetText(GC.LFormat(
            "Deine Version: {own}  •  |cffffb840{new} ist verfügbar|r",
            { own = GC.Constants.VERSION, new = update }))
    else
        frame.ownVersion:SetText(GC.LFormat("Deine Version: {own}",
            { own = GC.Constants.VERSION }))
    end

    local ownKey = GC.Util.NormalizeName(GC.Util.PlayerIdentityName(GC:GetPlayerFullName()))
    local ownVersion = GC.Constants.VERSION
    local current, outdated, missing, ahead = 0, 0, 0, 0
    local entries = {}
    for _, target in ipairs(self:GetVersionCheckTargets(frame.mode)) do
        local entry = { name = target.name, classFile = target.classFile, rank = target.rank }
        if GC.Util.NormalizeName(GC.Util.PlayerIdentityName(target.name)) == ownKey then
            entry.version = ownVersion
            entry.state = "CURRENT"
        else
            local version, fresh = GC.Sync:GetKnownVersion(target.name, frame.requestedAt)
            if fresh or (frame.settled and version) then
                entry.version = version
                if version == ownVersion then
                    entry.state = "CURRENT"
                elseif GC.Sync:IsNewerVersion(version, ownVersion) then
                    entry.state = "AHEAD"
                else
                    entry.state = "OLD"
                end
            elseif frame.settled then
                entry.state = "NONE"
            else
                entry.state = "WAITING"
            end
        end
        if entry.state == "CURRENT" then
            current = current + 1
        elseif entry.state == "AHEAD" then
            ahead = ahead + 1
        elseif entry.state == "OLD" then
            outdated = outdated + 1
        elseif entry.state == "NONE" then
            missing = missing + 1
        end
        entries[#entries + 1] = entry
    end

    -- Rot zuerst: Wer prüft, sucht die Veralteten.
    table.sort(entries, function(left, right)
        if VERSION_STATE_ORDER[left.state] ~= VERSION_STATE_ORDER[right.state] then
            return VERSION_STATE_ORDER[left.state] < VERSION_STATE_ORDER[right.state]
        end
        return tostring(left.name) < tostring(right.name)
    end)

    for index, row in ipairs(frame.rows) do
        local entry = entries[index]
        row:SetShown(entry ~= nil)
        if entry then
            row.name:SetText(GC.Util.PlayerIdentityName(entry.name))
            row.name:SetTextColor(ClassColor(entry.classFile))
            row.rank:SetText(entry.rank or "–")
            if entry.state == "CURRENT" then
                row.version:SetText(entry.version)
                SetTextColor(row.version, THEME.success)
            elseif entry.state == "AHEAD" then
                row.version:SetText(entry.version)
                SetTextColor(row.version, THEME.warning)
            elseif entry.state == "OLD" then
                row.version:SetText(entry.version or "?")
                SetTextColor(row.version, THEME.danger)
            elseif entry.state == "WAITING" then
                row.version:SetText(GC.L("Warte auf Antwort …"))
                SetTextColor(row.version, THEME.warning)
            else
                row.version:SetText(GC.L("Nicht installiert"))
                SetTextColor(row.version, THEME.muted)
            end
        end
    end

    frame.counts:SetText("|cff59e695" .. current .. " aktuell|r · |cffff6266"
        .. outdated .. " veraltet|r · " .. missing .. " ohne Addon"
        .. (ahead > 0 and (" · |cffffb840" .. ahead .. " neuer|r") or ""))
    frame.content:SetHeight(math.max(280, #entries * 26))
    frame.scroll:UpdateModernThumb()
end

-- Die Befehlstabelle steht oben in der Datei, damit auch die
-- Einstellungsseite sie lesen kann.
function GC.UI:PrintSlashHelp()
    GC:Print("Verfügbare Befehle:")
    for _, entry in ipairs(SLASH_COMMANDS) do
        GC:Print("  |cffffffff" .. entry.command .. "|r – " .. entry.description)
    end
    GC:Print("  |cff91a3b8/guildcopilot|r tut überall dasselbe wie |cff91a3b8/gcp|r.")
end

function GC.UI:RegisterInterfaceOptions()
    if self.optionsPanel then
        return
    end

    local panel = CreateFrame("Frame")
    panel.name = "Guild Copilot"

    local wordmark = panel:CreateTexture(nil, "ARTWORK")
    wordmark:SetSize(300, 300)
    wordmark:SetPoint("TOP", panel, "TOP", 0, -22)
    wordmark:SetTexture("Interface\\AddOns\\GuildCopilotForever\\Media\\GuildCopilotForeverWordmark")
    panel.wordmark = wordmark

    local commandLabel = CreateLabel(panel, "Chat-Befehle", {
        muted = true,
        align = "CENTER",
        width = 300,
    })
    commandLabel:SetPoint("TOP", wordmark, "BOTTOM", 0, -8)
    local command = CreateLabel(panel, "/gcp", {
        title = true,
        align = "CENTER",
        width = 300,
    })
    command:SetPoint("TOP", commandLabel, "BOTTOM", 0, -8)

    -- Die Befehle stehen hier, weil man diese Seite genau dann aufschlaegt,
    -- wenn man nicht mehr weiss, wie das Addon hiess - dort nach dem Chatbefehl
    -- zu suchen ist der naheliegende Weg.
    panel.commandRows = {}
    local previous = command
    for index, entry in ipairs(SLASH_COMMANDS) do
        local row = CreateLabel(panel, entry.command .. "  –  " .. entry.description, {
            muted = true,
            font = "GameFontNormalSmall",
            align = "CENTER",
            width = 560,
            height = 16,
        })
        row:SetPoint("TOP", previous, "BOTTOM", 0, index == 1 and -14 or -3)
        panel.commandRows[index] = row
        previous = row
    end

    panel.openButton = CreateButton(panel, "Guild Copilot öffnen", 220, 40, function()
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
            if HideUIPanel then
                HideUIPanel(InterfaceOptionsFrame)
            else
                InterfaceOptionsFrame:Hide()
            end
        elseif SettingsPanel and SettingsPanel:IsShown() then
            if HideUIPanel then
                HideUIPanel(SettingsPanel)
            else
                SettingsPanel:Hide()
            end
        end
        C_Timer.After(0, function()
            GC.UI:CreateMainFrame()
            GC.UI.frame:Show()
            GC.UI:ShowPage("ROSTER")
        end)
    end, "PRIMARY")
    panel.openButton:SetPoint("TOP", previous, "BOTTOM", 0, -20)

    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    elseif Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        panel.category = category
    else
        return
    end

    self.optionsPanel = panel
end

SLASH_GUILDCOPILOTFOREVER1 = "/gcp"
SLASH_GUILDCOPILOTFOREVER2 = "/guildcopilot"
SlashCmdList.GUILDCOPILOTFOREVER = function(input)
    local command = GC.Util.Trim(tostring(input or "")):lower()
    if command == "raidcheck" then
        local _, message = GC.RaidPreparation:Capture()
        GC:Print(message)
        GC.UI:CreateMainFrame()
        GC.UI.frame:Show()
        GC.UI:ShowPage("STATISTICS")
        return
    end
    if command == "client" then
        GC:Print(GC.Client.label .. " | " .. tostring(GC.Client.version) .. "." .. tostring(GC.Client.build)
            .. " | Interface " .. tostring(GC.Client.interface) .. " | Addon " .. GC.Constants.VERSION)
        GC:Print("Daten: " .. GC.Client.savedVariable .. " | Sync: " .. GC.Constants.COMM_PREFIX)
        GC:Print("Charakter: " .. GC:GetPlayerFullName())
        local spec, signature = GC.Profile:DetectTalentSpec()
        GC:Print("Talente: " .. (signature or "derzeit nicht lesbar") .. " | Zuordnung: " .. (spec or "nicht eindeutig"))
        GC:Print("Die Übersicht zeigt alle Stufen aus den ausgewählten Raider-Rängen.")
        if not GC.Client.combatAnalysis then GC:Print(GC.Client.combatAnalysisReason) end
        return
    end
    if command == "help" or command == "hilfe" or command == "?" then
        GC.UI:PrintSlashHelp()
        return
    end

    -- "werbung" und "balken" bleiben, damit sich niemand umgewoehnen muss;
    -- "recruit" faengt den naheliegenden Vertipper von "recruite" mit ab.
    if command == "recruite" or command == "recruit"
        or command == "werbung" or command == "balken" then
        GC.UI:CreateMainFrame()
        GC.UI:TogglePostBar()
        return
    end

    if command == "welcome" or command == "willkommen" then
        GC.UI:ShowWelcome()
        return
    end

    -- Ob ein Ruckler vom Addon kommt, laesst sich nur messen. Standardmaessig
    -- ist die Messung aus; wer sie einschaltet, spielt eine Weile und ruft
    -- "/gcp debug" erneut auf, bekommt die schlimmsten Einzelmessungen.
    if command == "debug" then
        if GC.Perf.enabled then
            for _, line in ipairs(GC.Perf:Report()) do
                GC:Print(line)
            end
            GC.Perf.enabled = false
            GC:Print("Messung beendet. Erneut einschalten mit /gcp debug.")
        else
            GC.Perf:Reset()
            GC.Perf.enabled = true
            GC:Print("Messung läuft. Spiel eine Weile weiter und ruf /gcp debug erneut auf.")
        end
        return
    end

    -- Der Versionsprüfer: Wer in Gruppe oder Gilde hat das Addon, und in
    -- welcher Version? ("/gcp phase" ist auf Owner-Wunsch entfallen; die
    -- Content-Phase läuft intern mit ihrer Voreinstellung und dem
    -- Gildenabgleich weiter.)
    if command == "ver" or command == "version" then
        GC.UI:ShowVersionCheck()
        return
    end

    GC.UI:Toggle()
end

GC:RegisterCallback("PLAYER_LOGIN", GC.UI, function(self)
    self:CreateMainFrame()
    if GC.DB:GetSettings().postBar.hidden == false then
        self:SetPostBarShown(true)
    end
    self:AddMinimapButton()
    self:RegisterInterfaceOptions()
    self:RefreshOrderTracker()
end)

GC:RegisterCallback("ORDERS_UPDATED", GC.UI, function(self)
    self:Invalidate("WORKSHOP")
    self:RefreshMinimapMarker()
    self:RefreshOrderTracker()
    -- Ein Statuswechsel waehrend eines offenen Handels frischt den Helfer
    -- daneben auf - auch wenn ihn der Handelspartner ausgeloest hat.
    if self.tradePartner then
        self:RefreshTradeBanner()
    end
    if self.pages.WORKSHOP and self.pages.WORKSHOP.orderLogDialog then
        self:RefreshOrderLogDialog()
    end
end)

GC:RegisterCallback("ORDERS_BANNER", GC.UI, function(self, text)
    self:ShowOrderBanner(text)
end)

-- Eintreffende Versionsantworten füllen den offenen Versionsprüfer live.
GC:RegisterCallback("VERSION_REPLIES_UPDATED", GC.UI, function(self)
    self:RefreshVersionCheck()
end)

GC:RegisterCallback("UPDATE_AVAILABLE", GC.UI, function(self)
    self:RefreshUpdateHint()
    self:RefreshVersionCheck()
end)

-- ROSTER_UPDATED kommt aus zwei sehr verschiedenen Quellen: aus dem
-- entprellten Gildenscan (selten) und aus jedem eingehenden Profilpaket
-- (zur Prime Time mehrfach pro Sekunde). Refresh() zeichnete die offene Seite
-- dabei SOFORT und synchron neu - genau der Fall, gegen den Invalidate() mit
-- seinem Sammel-Timer gebaut wurde. Hier lief er daran vorbei.
GC:RegisterCallback("ROSTER_UPDATED", GC.UI, function(self)
    self:InvalidateAll()
end)

-- Der Kopf zeigt den Abgleich mit; die Werkstatt hat ihren eigenen Balken und
-- frischt ihn selbst auf, solange sie zu sehen ist.
GC:RegisterCallback("SYNC_PROGRESS", GC.UI, function(self)
    if self:IsVisible() then
        self:RefreshSyncBadge()
    end
end)

-- Alle folgenden Rueckmeldungen kommen aus der Gildensynchronisierung und
-- treffen zur Prime Time im Sekundentakt ein. Sie merken die betroffenen
-- Seiten deshalb nur noch vor; gezeichnet wird, was gerade zu sehen ist.
GC:RegisterCallback("PROFILE_UPDATED", GC.UI, function(self)
    self:Invalidate("OVERVIEW", "ROSTER", "MEMBERCARE", "SUGGESTIONS")
    -- Der Marker am Minimap-Symbol haengt nicht am Zeichnen der Seite: Er muss
    -- auch stimmen, wenn das Fenster zu ist.
    self:RefreshMinimapMarker()
end)

GC:RegisterCallback("SETTINGS_UPDATED", GC.UI, function(self)
    self:Invalidate("SETTINGS", "GUILD")
    if self:IsVisible() then
        self:RefreshNavigationAccess()
    end
end)

GC:RegisterCallback("GUILD_PROFILE_UPDATED", GC.UI, function(self)
    self:Invalidate("GUILD", "SETTINGS", "MEMBERCARE", "SUGGESTIONS", "POST", "INBOX")
    if self:IsVisible() then
        self:RefreshNavigationAccess()
    end
end)

-- Neue Bestandszahlen aendern die Ampel in den Rezeptdetails.
GC:RegisterCallback("INVENTORY_UPDATED", GC.UI, function(self)
    self:Invalidate("WORKSHOP")
end)

GC:RegisterCallback("WORKSHOP_UPDATED", GC.UI, function(self)
    -- Ein eingelesener Beruf erledigt den zweiten Schritt der Checkliste, und
    -- die steht auf der Profilseite.
    -- Auch die Kopfzeile haengt inzwischen an der Werkstatt: Ein
    -- Bestandsmanifest kann "Daten vollstaendig" in "Bestand lückenhaft"
    -- drehen. Sie wandert ueber denselben Sammel-Takt wie die Seiten.
    self.headerStale = true
    self:Invalidate("WORKSHOP", "ROSTER")
    self:RefreshMinimapMarker()
end)

GC:RegisterCallback("PROFILE_CONFIRMATION_CHANGED", GC.UI, function(self)
    self:Invalidate("ROSTER")
    self:RefreshMinimapMarker()
end)

GC:RegisterCallback("RECRUITMENT_UPDATED", GC.UI, function(self)
    self:Invalidate("RECRUITMENT")
end)

GC:RegisterCallback("INBOX_UPDATED", GC.UI, function(self)
    self:Invalidate("INBOX")
end)

GC:RegisterCallback("RAIDSEARCH_UPDATED", GC.UI, function(self)
    self:Invalidate("RAIDSEARCH")
    -- Der Suchbalken haengt nicht an der Seite: Er erscheint und verschwindet
    -- mit dem Zustand der Suche, auch bei geschlossenem Hauptfenster.
    self:UpdateRaidSearchBarShown()
end)

GC:RegisterCallback("WCL_UPDATED", GC.UI, function(self)
    -- Region und Realm der Gildenquelle stehen in den Profil-Links des
    -- Postfachs. Ohne dessen Auffrischung zeigen sie bis zum Seitenwechsel den
    -- alten Stand.
    self:Invalidate("WCL", "SUGGESTIONS", "INBOX")
end)

GC:RegisterCallback("ROSTER_FILTER_UPDATED", GC.UI, function(self)
    self:Invalidate("OVERVIEW", "SETTINGS")
end)

GC:RegisterCallback("MEMBERCARE_UPDATED", GC.UI, function(self)
    self:Invalidate("MEMBERCARE")
end)

GC:RegisterCallback("ADDON_USERS_UPDATED", GC.UI, function(self)
    self:Invalidate("OVERVIEW")
    if self:IsVisible() then
        self:RefreshSyncBadge()
    end
end)

GC:RegisterCallback("RAID_SESSION_UPDATED", GC.UI, function(self)
    self:Invalidate("STATISTICS")
end)

GC:RegisterCallback("GEAR_AUDIT_UPDATED", GC.UI, function(self)
    -- Die eigene Ausruestung steht auch auf der Profilseite.
    self:Invalidate("GEAR", "ROSTER")
    self:RefreshMinimapMarker()
    -- Eintreffende Inspects und Addon-Daten füllen die offene
    -- Gruppenübersicht live.
    self:RefreshGroupGearCheck()
end)
