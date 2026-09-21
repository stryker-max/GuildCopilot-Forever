local _, GC = ...

-- === Erste Schritte ========================================================
--
-- Die Einrichtung hat zwei Gesichter, die denselben Zustand zeigen:
--
--   * der ASSISTENT (Owner-Wunsch seit 0.9.100): ein mehrseitiges Fenster,
--     das beim ersten Login aufgeht, das Addon einmal kurz vorstellt und die
--     drei Schritte direkt abnimmt, soweit WoW das erlaubt. Er ist der
--     gefuehrte Weg - und jederzeit abbrechbar, ohne dass etwas verloren geht.
--   * die CHECKLISTE oben auf der Profilseite: der stille Spiegel derselben
--     Schritte. Sie faengt jeden auf, der den Assistenten zuklappt, und
--     verschwindet von selbst, sobald alles erledigt ist.
--
-- Beide leiten den Zustand aus den echten Daten ab und fuehren keine Merker.
-- Ein Merker, der behauptet, was noch zu tun sei, laeuft der Wirklichkeit
-- hinterher, sobald jemand seinen Beruf auf einem anderen Weg eintraegt.
-- Nebenbei beantwortet sich damit die Frage "kontoweit oder pro Charakter?"
-- von selbst: Spec, Berufe und Ausruestung gelten pro Charakter, also sieht
-- ein frischer Twink die Liste und ein fertiger Charakter nicht.
--
-- Gespeichert wird nur, was sich aus den Daten nicht ablesen laesst:
-- Uebersprungenes, Ausgeblendetes und die beiden einmaligen Ereignisse. Es
-- gibt dafuer keinen Sendeweg - die Einrichtung ist die eigene Sache.

GC.Onboarding = {}

-- Ein paar Sekunden nach dem Betreten der Welt. Frueher faellt es in die
-- Login-Lastspitze und andere Addons bauen noch ihre Fenster auf.
local AUTO_OPEN_DELAY = 6

local STEPS = {
    {
        key = "PROFILE",
        label = "Raidprofil bestätigen",
        hint = "Primär-Spec wählen und auf „Bestätigen“ klicken – das ist der ganze Schritt.",
    },
    {
        key = "PROFESSIONS",
        label = "Rezepte einlesen",
        hint = "Öffne einmal jedes deiner Berufsfenster – die Rezepte darin kann Guild Copilot nur dann lesen.",
    },
    {
        key = "GEAR",
        label = "Ausrüstung ansehen",
        hint = "Die Prüfung läuft im Hintergrund – hier steht gleich ihr Ergebnis.",
    },
}

local function InCombat()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return true
    end
    return type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player") == true
end

-- Zwei Dinge heissen hier beide "Berufe" und sind doch verschieden:
--
--   * die **Namen** der beiden Berufe. Die liefert GetProfessions() von selbst,
--     ohne dass jemand etwas oeffnen muss - sie stehen nach dem Login da.
--   * die **Rezepte** darin. Die gibt WoW nur heraus, solange das Berufsfenster
--     offen ist. Ohne diesen einen Handgriff bleibt die Gildenwerkstatt leer.
--
-- Der Schritt der Checkliste meint deshalb die Rezepte. Auf die Namen zu
-- pruefen hiesse, einen Schritt zu stellen, der sich beim Login von selbst
-- abhakt, ohne dass jemand etwas getan hat.
local function ScannedProfessionNames()
    local names = {}
    for _, profession in pairs((GC.Profile:Get().workshop or {}).professions or {}) do
        local name = GC.Util.Trim(profession and profession.name or "")
        if name ~= "" then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names
end

-- Hat der Charakter einen Beruf, aus dem sich ueberhaupt Rezepte lesen
-- lassen? Wer keinen hat, kann auch keinen einlesen - der Schritt gilt dann
-- als erledigt statt auf ewig offen zu stehen. Reine Sammler zaehlen dazu:
-- Kraeuterkunde und Kuerschnerei haben kein Rezeptfenster, ihr Schritt war
-- also genauso unerfuellbar wie ohne Beruf.
local function HasAnyScannableProfession()
    local profile = GC.Profile:Get()
    for slot = 1, 2 do
        local profession = profile.professions and profile.professions[slot]
        local name = GC.Util.Trim(profession and profession.name or "")
        if name ~= "" and not GC.RecipelessProfessions[name] then
            return true
        end
    end
    return false
end

-- Ist der Schritt erledigt, und was ist dabei herausgekommen? Der zweite
-- Rueckgabewert steht als Rueckmeldung an der Zeile: Wer gerade sein
-- Berufsfenster geoeffnet hat, soll den erkannten Beruf lesen, nicht nur
-- einen Haken sehen.
function GC.Onboarding:GetStepState(stepKey)
    if stepKey == "PROFILE" then
        local profile = GC.Profile:Get()
        if profile.confirmed ~= true then
            return false, nil
        end
        local spec = GC.SpecByKey[profile.raidSpecKey or ""]
        return true, spec and (spec.name .. " bestätigt") or "Bestätigt"
    elseif stepKey == "PROFESSIONS" then
        local names = ScannedProfessionNames()
        if #names > 0 then
            return true, table.concat(names, ", ") .. " eingelesen"
        end
        if not HasAnyScannableProfession() then
            return true, "Keine Berufe mit Rezepten – hier gibt es nichts einzulesen"
        end
        return false, nil
    elseif stepKey == "GEAR" then
        local audit = GC.GearAudit and GC.GearAudit:GetAudit(GC:GetPlayerFullName())
        if not audit then
            return false, nil
        end
        local findings = GC.GearAudit:GetFindings(audit)
        return true, findings[1] and findings[1].text or nil
    end
    return false, nil
end

function GC.Onboarding:GetData()
    local character = GC.DB:GetCharacter()
    character.onboarding = GC.Util.MergeDefaults(character.onboarding, {
        skipped = {},
        dismissedAt = 0,
        autoOpenedAt = 0,
        doneShownAt = 0,
        laterHintShownAt = 0,
    })
    return character.onboarding
end

-- Die drei Zeilen der Checkliste. Aktiv ist immer die erste, die weder
-- erledigt noch uebersprungen ist - einen "Weiter"-Knopf gibt es bewusst
-- nicht, die echte Aktion schiebt die Liste weiter.
function GC.Onboarding:GetSteps()
    local data = self:GetData()
    local steps = {}
    local activeFound = false
    for index, definition in ipairs(STEPS) do
        local done, detail = self:GetStepState(definition.key)
        -- Uebersprungen heisst "nicht draengeln", nicht "nicht wahrnehmen":
        -- Passiert die echte Aktion spaeter doch, gewinnt sie.
        local skipped = not done and data.skipped[definition.key] == true
        local step = {
            key = definition.key,
            label = definition.label,
            hint = definition.hint,
            detail = detail,
            done = done,
            skipped = skipped,
            active = false,
        }
        if not done and not skipped and not activeFound then
            step.active = true
            activeFound = true
        end
        steps[index] = step
    end
    return steps
end

-- Ohne Umweg ueber GetSteps: Diese Frage stellt auch das Minimap-Symbol, und
-- zwar bei jeder Profilaenderung. Drei Tabellen dafuer zu bauen waere Verschwendung.
function GC.Onboarding:IsFinished()
    local data = self:GetData()
    for _, definition in ipairs(STEPS) do
        local done = self:GetStepState(definition.key)
        if not done and data.skipped[definition.key] ~= true then
            return false
        end
    end
    return true
end

-- Steht die Einrichtung noch aus? Das ist die Frage fuer den Marker am
-- Minimap-Symbol. Ein ausgeblendetes "Nicht mehr anzeigen" schaltet ihn mit ab -
-- wer das gewaehlt hat, will auch keinen Punkt mehr sehen. Das × dagegen gilt
-- nur der Karte; der Marker bleibt, sonst waere der Weg zurueck unsichtbar.
function GC.Onboarding:IsPending()
    if (self:GetData().dismissedAt or 0) > 0 then
        return false
    end
    return not self:IsFinished()
end

-- Der naechste offene Schritt, fuer den Tooltip am Minimap-Symbol.
function GC.Onboarding:GetNextStep()
    local data = self:GetData()
    for _, definition in ipairs(STEPS) do
        local done = self:GetStepState(definition.key)
        if not done and data.skipped[definition.key] ~= true then
            return definition.label
        end
    end
    return nil
end

function GC.Onboarding:SetStepSkipped(stepKey, skipped)
    local data = self:GetData()
    for _, definition in ipairs(STEPS) do
        if definition.key == stepKey then
            if skipped == true then
                data.skipped[stepKey] = true
            else
                data.skipped[stepKey] = nil
            end
            return true
        end
    end
    return false
end

-- Das × der Karte: weg fuer diese Sitzung, beim naechsten Login wieder da.
function GC.Onboarding:HideForSession()
    self.hiddenForSession = true
end

-- „Nicht mehr anzeigen“: dauerhaft weg, aber nur fuer diesen Charakter.
function GC.Onboarding:Dismiss()
    self:GetData().dismissedAt = GC.Util.Now()
    self.completionVisible = nil
end

-- Der Knopf „Einrichtung“ im Fensterkopf. Er faengt die Liste neu an, statt
-- sie nur wieder einzublenden: Wer sie ausdruecklich aufruft, will sie
-- durchgehen - eine Liste aus lauter uebersprungenen Zeilen waere dafuer
-- nutzlos. Was tatsaechlich erledigt ist, bleibt erledigt; das steht in den
-- echten Daten und nicht in diesen Merkern.
function GC.Onboarding:Reopen()
    local data = self:GetData()
    data.skipped = {}
    data.dismissedAt = 0
    self.hiddenForSession = nil
    self.completionVisible = true
    return true
end

function GC.Onboarding:ShouldShow()
    local data = self:GetData()
    if self.hiddenForSession == true then
        return false
    end
    if (data.dismissedAt or 0) > 0 then
        return false
    end
    if self:IsFinished() then
        -- Die Erfolgsmeldung soll man lesen koennen: Sie bleibt bis zum
        -- Schliessen des Fensters stehen und ist beim naechsten Oeffnen weg.
        return self.completionVisible == true or (data.doneShownAt or 0) == 0
    end
    return true
end

-- Vom UI beim Zeichnen der fertigen Liste. Der Rueckgabewert sagt, ob es das
-- erste Mal ist - nur dann gibt es den Ton dazu.
function GC.Onboarding:NoteCompleted()
    local data = self:GetData()
    self.completionVisible = true
    if (data.doneShownAt or 0) > 0 then
        return false
    end
    data.doneShownAt = GC.Util.Now()
    return true
end

function GC.Onboarding:NoteWindowClosed()
    self.completionVisible = nil
end

-- === Der Assistent =========================================================
--
-- Sechs Seiten, ein roter Faden: erst das Logo, dann einmal kurz "was kann
-- das Addon und wo finde ich es", dann die drei Schritte der Checkliste als
-- je eigene Seite, zum Schluss die Fundorte fuer spaeter. Die Schrittseiten
-- fragen denselben GetStepState wie die Checkliste - der Assistent hat keinen
-- eigenen Begriff von "erledigt" und kann darum nie etwas anderes behaupten
-- als sie.
--
-- Die Seitennummer ist reiner Sitzungszustand und wird nicht gespeichert:
-- Wer den Assistenten schliesst und wieder oeffnet, faengt vorn an - die
-- Tour ist kurz genug, und mitten in einer alten Sitzung aufzuwachen waere
-- verwirrender als zwei bekannte Seiten erneut zu sehen.
local WIZARD_PAGES = {
    { key = "WELCOME" },
    { key = "TOUR" },
    { key = "STEP_PROFILE", step = "PROFILE" },
    { key = "STEP_PROFESSIONS", step = "PROFESSIONS" },
    { key = "STEP_GEAR", step = "GEAR" },
    { key = "DONE" },
}

-- Die Funktionstour, in der Reihenfolge der Seitenleiste - das WO ist die
-- halbe Antwort: Wer die Tour gelesen hat, hat die Seitenleiste schon einmal
-- von oben nach unten gesehen. Ein Abschnitt darf mehrere Zeilen haben
-- (GILDE: Mitgliederpflege und Werkstatt sind zwei verschiedene Dinge, eine
-- gemeinsame Zeile beschrieb beide nur halb); tests/validate.mjs prueft in
-- beide Richtungen, dass Tour und Seitenleiste dieselben Abschnitte nennen.
--
-- Warcraft Logs steht bewusst NICHT in der Tour (Owner-Entscheidung): Wer
-- frisch installiert, hat nur das Addon - der Import ist ein Werkzeug fuer
-- Fortgeschrittene und kein Verkaufsargument der ersten fuenf Minuten.
GC.Onboarding.TOUR = {
    {
        section = "COPILOT",
        icon = "Interface\\Icons\\INV_Misc_GroupLooking",
        pages = "Profil · Übersicht",
        text = "Dein Raidprofil, deine Berufe und deine Abmeldung – und was"
            .. " die ganze Gilde gemeldet hat.",
    },
    -- Die Seitenzeile ist eine Ueberschrift, keine Aufzaehlung aller fuenf
    -- Seiten: In voller Laenge passte sie nicht in die Zeile und wurde
    -- abgeschnitten ("Postfa..."). Was fehlt, sagt der Text darunter.
    {
        section = "REKRUTIERUNG",
        icon = "Interface\\Icons\\INV_Letter_15",
        pages = "Gildenprofil · Vorschläge · Werbung · Postfach",
        text = "Gildenprofil pflegen, fehlende Specs sehen, Werbung posten und"
            .. " Antworten im Postfach beantworten.",
    },
    {
        section = "GILDE",
        icon = "Interface\\Icons\\INV_Misc_Note_06",
        pages = "Mitgliederpflege",
        text = "Abmeldungen und Inaktivität im Blick: Wer lange fehlt, wird zur"
            .. " Prüfung vorgeschlagen – nie automatisch entfernt.",
    },
    {
        section = "GILDE",
        icon = "Interface\\Icons\\INV_Hammer_20",
        pages = "Gildenwerkstatt",
        text = "Wer kann welches Rezept? Mit Herstellern, Materialstand und"
            .. " Aufträgen an eure Handwerker.",
    },
    {
        section = "RAID",
        icon = "Interface\\Icons\\INV_Misc_Book_11",
        pages = "Raidsuche · Raidauswertung · Ausrüstung",
        text = "Spieler für den Raid suchen, Abende mitschreiben und auswerten,"
            .. " Verzauberungen und Sockel der Raider prüfen.",
    },
    {
        section = "SYSTEM",
        icon = "Interface\\Icons\\INV_Gizmo_02",
        pages = "Einstellungen",
        text = "Töne, Rangfreigaben, Trigger-Wörter und das Minimap-Symbol.",
    },
}

function GC.Onboarding:GetWizardPages()
    return WIZARD_PAGES
end

function GC.Onboarding:GetWizardPageCount()
    return #WIZARD_PAGES
end

function GC.Onboarding:GetWizardPage()
    local index = math.max(1, math.min(self.wizardIndex or 1, #WIZARD_PAGES))
    return WIZARD_PAGES[index], index
end

function GC.Onboarding:StartWizard()
    self.wizardIndex = 1
    return self:GetWizardPage()
end

-- Blaettert um eine Seite vor oder zurueck und bleibt an den Raendern stehen.
function GC.Onboarding:WizardGo(delta)
    local _, index = self:GetWizardPage()
    self.wizardIndex = math.max(1, math.min(index + (tonumber(delta) or 1), #WIZARD_PAGES))
    return self:GetWizardPage()
end

-- Vorzeitiges Schliessen des Assistenten ("Spaeter" oder das ×): Beim
-- ersten Mal je Charakter folgt der Hinweis, wie man die Einrichtung wieder
-- aufruft - und genau einmal, egal ueber welchen Knopf, denn wer ihn gelesen
-- hat, weiss es. Ein Fenster nach jedem Schliessen waere Draengeln.
function GC.Onboarding:NoteLaterPressed()
    local data = self:GetData()
    if (data.laterHintShownAt or 0) > 0 then
        return false
    end
    data.laterHintShownAt = GC.Util.Now()
    return true
end

-- "Ueberspringen" auf einer Schrittseite heisst dasselbe wie in der
-- Checkliste: nicht draengeln, aber wahrnehmen, falls die echte Aktion
-- spaeter doch passiert. Ein bereits erledigter Schritt wird nicht
-- rueckwirkend als uebersprungen gefuehrt - da gaebe es nichts zu ueberspringen.
function GC.Onboarding:SkipWizardStep()
    local page = self:GetWizardPage()
    if page.step and not self:GetStepState(page.step) then
        self:SetStepSkipped(page.step, true)
    end
    return self:WizardGo(1)
end

-- Beim ersten Login eines Charakters ohne bestaetigtes Profil oeffnet sich
-- das Fenster einmal von selbst - Twinks eingeschlossen, das ist die
-- ausdrueckliche Entscheidung des Owners.
function GC.Onboarding:ShouldAutoOpen()
    local data = self:GetData()
    if (data.autoOpenedAt or 0) > 0 or (data.dismissedAt or 0) > 0 then
        return false
    end
    -- Wer sein Profil laengst bestaetigt hat, wird nicht behelligt: Das sind
    -- genau die Charaktere, die es vor dieser Fassung schon gab.
    local profileDone = self:GetStepState("PROFILE")
    if profileDone then
        return false
    end
    return not InCombat()
end

-- Der Merker wird beim tatsaechlichen Zeigen gesetzt, nicht davor. Dadurch kann
-- das Fenster nie zweimal aufspringen, und ein Login mitten im Kampf verschiebt
-- es auf das naechste Mal, statt es zu verbrauchen.
--
-- Gezeigt wird das Willkommensfenster, nicht gleich das ganze Addon: Wer zum
-- ersten Mal einloggt, soll das Schriftlogo und einen Knopf sehen, nicht
-- dreizehn Navigationspunkte.
function GC.Onboarding:AutoOpen()
    if not GC.DB or not GC.DB.data or not GC.UI then
        return false
    end
    if not self:ShouldAutoOpen() then
        return false
    end
    self:GetData().autoOpenedAt = GC.Util.Now()
    GC.UI:ShowWelcome()
    return true
end

local onboardingEvents = CreateFrame("Frame")
onboardingEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
onboardingEvents:SetScript("OnEvent", function(frame)
    -- PLAYER_ENTERING_WORLD feuert auch bei jedem Zonenwechsel. Fuer die
    -- Einrichtung zaehlt nur das erste Mal.
    frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    C_Timer.After(AUTO_OPEN_DELAY, function()
        GC.Onboarding:AutoOpen()
    end)
end)
