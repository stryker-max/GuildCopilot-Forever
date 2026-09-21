local _, GC = ...

GC.Profile = {}

-- Eine laufende Uhr in Sekunden. GetTime() zaehlt seit dem Start des Clients
-- und laeuft nie rueckwaerts; ohne sie tut es die Serverzeit, die zwar
-- sekundengenau ist, aber fuer eine Sperre von wenigen Sekunden genuegt.
function GC.Profile:Clock()
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        if ok and tonumber(value) then
            return value
        end
    end
    return GC.Util.Now()
end

local function ReadProfession(professionIndex)
    if not professionIndex or not GetProfessionInfo then
        return nil
    end
    local name, _, skillLevel, maxSkillLevel, _, _, skillLine = GetProfessionInfo(professionIndex)
    if not name then
        return nil
    end
    -- Forever's profession book resolves the current rank through this API.
    if C_TradeSkillUI and type(C_TradeSkillUI.GetProfessionInfoBySkillLineID) == "function" and skillLine then
        local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLine)
        if ok and not GC.Client.IsSecret(info) and type(info) == "table"
            and not GC.Client.HasSecretArguments(info.skillLevel, info.maxSkillLevel)
            and ((tonumber(info.skillLevel) or 0) > 0 or (tonumber(info.maxSkillLevel) or 0) > 0) then
            skillLevel, maxSkillLevel = info.skillLevel, info.maxSkillLevel
        end
    end
    return {
        name = GC.CanonicalProfessionName(name) or name,
        skillLevel = tonumber(skillLevel) or 0,
        maxSkillLevel = tonumber(maxSkillLevel) or 0,
        skillLine = tonumber(skillLine),
    }
end

-- Welche Faehigkeit ein Hauptberuf ist. Sekundaeres wie Kochkunst, Erste Hilfe
-- und Angeln gehoert ausdruecklich nicht dazu - im Profil stehen die beiden
-- Hauptberufe. "Alchemie" ist die aeltere Schreibweise derselben Sache.
--
-- Die Faehigkeitszeilen kommen in der Sprache des Clients: Ein englischer
-- Client meldet "Enchanting", und ohne den englischen Namen in dieser Tabelle
-- fand die Erkennung dort schlicht keinen Beruf. Im Profil steht in beiden
-- Faellen der deutsche Name - das Addon ist deutschsprachig, und Dropdown wie
-- Synchronisierung erwarten ihn so.
local PROFESSION_BY_NAME = {}
for _, professionName in ipairs(GC.ProfessionOptions) do
    if professionName ~= "" then
        PROFESSION_BY_NAME[GC.Util.NormalizeName(professionName)] = professionName
        local english = GC.ProfessionEnglishName(professionName)
        if english then
            PROFESSION_BY_NAME[GC.Util.NormalizeName(english)] = professionName
        end
    end
end
PROFESSION_BY_NAME[GC.Util.NormalizeName("Alchemie")] = "Alchimie"

-- Die Berufe aus dem Faehigkeitenfenster lesen.
--
-- GetProfessions() ist eine Retail-API und im Anniversary-Client schlicht nicht
-- vorhanden. Bis 0.9.45 stieg die Erfassung dort wortlos aus - die Statuszeile
-- meldete trotzdem "Automatische Synchronisierung aktiv", und stehen blieb, was
-- jemand von Hand eingetragen hatte. Classic fuehrt die Berufe stattdessen als
-- Faehigkeitszeilen.
--
-- Rueckgabe: Liste der gefundenen Berufe, oder nil, wenn der Client gar keine
-- Auskunft gibt. Der Unterschied ist wichtig - "nichts gefunden" und "kann
-- nicht nachsehen" sind zwei verschiedene Antworten, und nur die erste heisst,
-- dass dieser Charakter keinen Beruf hat.
-- Einmal die sichtbaren Fähigkeitszeilen durchgehen.
local function CollectSkillLineProfessions()
    local found = {}
    local seen = {}
    for index = 1, (GC.API.GetNumSkillLines() or 0) do
        local name, isHeader, _, skillRank, _, _, skillMaxRank = GC.API.GetSkillLineInfo(index)
        local canonical = (not isHeader) and name and PROFESSION_BY_NAME[GC.Util.NormalizeName(name)]
        if canonical and not seen[canonical] then
            seen[canonical] = true
            found[#found + 1] = {
                name = canonical,
                skillLevel = tonumber(skillRank) or 0,
                maxSkillLevel = tonumber(skillMaxRank) or 0,
            }
        end
    end
    return found
end

local function ReadSkillLineProfessions()
    if not GC.API.Has("GetNumSkillLines") or not GC.API.Has("GetSkillLineInfo") then
        return nil
    end

    -- Erst nachsehen, ohne etwas anzufassen. Bei den allermeisten Charakteren
    -- stehen die Berufe offen sichtbar in der Liste, und dann ist hier Schluss:
    -- kein Auf- und Zuklappen, keine Nebenwirkung, kein Ereignis.
    local found = CollectSkillLineProfessions()
    if #found > 0 then
        return found
    end

    -- Eine eingeklappte Kategorie zaehlt GC.API.GetNumSkillLines nicht mit. Welche
    -- zugeklappt war, wird notiert und hinterher wiederhergestellt: Das
    -- Faehigkeitenfenster des Spielers soll danach aussehen wie vorher.
    local collapsed = {}
    for index = 1, (GC.API.GetNumSkillLines() or 0) do
        local name, isHeader, isExpanded = GC.API.GetSkillLineInfo(index)
        if isHeader and not isExpanded and name then
            collapsed[name] = true
        end
    end
    if next(collapsed) == nil or not GC.API.Has("ExpandSkillHeader") then
        return found
    end

    -- Ab hier wird das Fähigkeitenfenster tatsächlich angefasst - und genau
    -- das löst SKILL_LINES_CHANGED aus, also dasselbe Ereignis, das uns
    -- hierher geführt hat. Ohne diese Sperre klappt das Addon die Kategorien
    -- endlos auf und wieder zu: jedes Zuklappen erzeugt das nächste Ereignis,
    -- jedes Ereignis den nächsten Durchlauf. Die Sperre gilt in Echtzeit, nicht
    -- über einen Zähler, weil die Ereignisse erst im nächsten Bild eintreffen.
    GC.Profile.skillHeadersTouchedAt = GC.Profile:Clock()
    pcall(GC.API.ExpandSkillHeader, 0)

    found = CollectSkillLineProfessions()

    -- Rueckwaerts zuklappen: Jedes Zuklappen verschiebt die Zeilen darunter.
    if GC.API.Has("CollapseSkillHeader") then
        for index = (GC.API.GetNumSkillLines() or 0), 1, -1 do
            local name, isHeader = GC.API.GetSkillLineInfo(index)
            if isHeader and name and collapsed[name] then
                pcall(GC.API.CollapseSkillHeader, index)
            end
        end
    end
    GC.Profile.skillHeadersTouchedAt = GC.Profile:Clock()

    return found
end

local function ProfessionChanged(left, right)
    left = left or {}
    right = right or {}
    return left.name ~= right.name
        or left.skillLevel ~= right.skillLevel
        or left.maxSkillLevel ~= right.maxSkillLevel
        or left.skillLine ~= right.skillLine
end

local function ReadTalentPoints(tabIndex)
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
        local results = { pcall(C_SpecializationInfo.GetSpecializationInfo, tabIndex) }
        if results[1] and not GC.Client.IsSecret(results[8]) and type(results[8]) == "number" then
            return results[8]
        end
    end

    if GetTalentTabInfo then
        local results = { pcall(GetTalentTabInfo, tabIndex, false, false, 1) }
        if results[1] then
            local pointsSpent = results[6]
            if type(pointsSpent) == "number" then
                return pointsSpent
            end
        end
    end

    return 0
end

-- === Die Spec eines FREMDEN Spielers ========================================
--
-- Aus dem Spiel gefragt: "Das Roster wird quasi nur durch Addon-Nutzer aktuell -
-- kann das Roster selber erkennen, welche Spec das ist?" Bei 86 Mitgliedern und
-- zwei bekannten Profilen ist das die richtige Frage.
--
-- Es geht, und zwar exakt statt geraten: Dieselbe Funktion, die den eigenen
-- Talentbaum liest, liest mit gesetztem Inspect-Schalter den eines fremden
-- Spielers - GetTalentTabInfo(tab, true). Zauber im Kampflog zu deuten waere
-- die schlechtere Quelle: Sie taugt nur fuer die, die mit einem raiden, und
-- ein einzelner Zauber belegt selten eine Spec.
--
-- Vorbedingung ist eine laufende Inspektion, und genau die faehrt der
-- Ausruestungsabgleich (GearAudit) ohnehin ueber die halbe Gilde. Diese
-- Funktion haengt sich dort an, statt einen zweiten Verkehr aufzumachen.
local function ReadInspectTalentPoints(tabIndex)
    if GetTalentTabInfo then
        local results = { pcall(GetTalentTabInfo, tabIndex, true, false, 1) }
        if results[1] and type(results[6]) == "number" then
            return results[6]
        end
    end
    return 0
end

local function ForeverTalentSpec(classFile, inspect)
    local points = GC.Client.ReadTalentGroups(inspect)
    if not points then return nil, nil end
    local best, maximum, tied = nil, 0, false
    for index, spent in ipairs(points) do
        if spent > maximum then
            best, maximum, tied = index, spent, false
        elseif spent == maximum then
            tied = true
        end
    end
    local signature = table.concat(points, "/")
    if not best or tied then return nil, signature end
    return classFile .. ":" .. best, signature
end

function GC.Profile:DetectTalentSpecForUnit(unit)
    if GC.Client.isForever and GC.Client.InCombat() then return nil end
    if not unit or not UnitClass then
        return nil
    end
    local _, classFile = UnitClass(unit)
    local classInfo = classFile and GC.Classes[classFile]
    if not classInfo then
        return nil
    end
    if GC.Client.isForever then
        local spec, signature = ForeverTalentSpec(classFile, unit ~= "player")
        return spec, signature, classFile
    end

    local points = {}
    local bestIndex, bestPoints, total = nil, -1, 0
    for tabIndex = 1, #classInfo.specs do
        points[tabIndex] = ReadInspectTalentPoints(tabIndex)
        total = total + points[tabIndex]
        if points[tabIndex] > bestPoints then
            bestIndex = tabIndex
            bestPoints = points[tabIndex]
        end
    end

    -- Ein Level-70-Charakter hat rund 60 Talentpunkte verteilt. Liefert der
    -- Client deutlich weniger, sind die Daten noch nicht da - dann lieber
    -- nichts sagen als eine Spec erfinden, die gleich in der Gildenuebersicht
    -- steht.
    if bestPoints <= 0 or total < 20 then
        return nil
    end
    return classFile .. ":" .. bestIndex, table.concat(points, "/"), classFile
end

function GC.Profile:DetectTalentSpec()
    local _, classFile, classID = UnitClass("player")
    local classInfo = classFile and GC.Classes[classFile]
    if not classInfo then
        return nil, "0/0/0"
    end
    if GC.Client.isForever then
        local spec, signature = ForeverTalentSpec(classFile, false)
        return spec, signature, classFile, classID
    end

    local points = {}
    local bestIndex
    local bestPoints = -1
    for tabIndex = 1, #classInfo.specs do
        points[tabIndex] = ReadTalentPoints(tabIndex)
        if points[tabIndex] > bestPoints then
            bestIndex = tabIndex
            bestPoints = points[tabIndex]
        end
    end

    local signature = table.concat(points, "/")
    if bestPoints <= 0 then
        return nil, signature, classFile, classID
    end
    return classFile .. ":" .. bestIndex, signature, classFile, classID
end

-- === In welcher Gilde steckt dieser Charakter? ==============================
--
-- WoW verraet einem Addon nie, welche Charaktere eines Accounts zusammen-
-- gehoeren, und erst recht nicht, in welcher Gilde ein GERADE NICHT gespielter
-- Charakter steckt. Die SavedVariables liegen aber pro Account, also kann jeder
-- Charakter beim Einloggen selbst hinterlassen, wo er gerade Mitglied ist.
--
-- Ohne diesen Vermerk meldete die Werkstatt die Berufe ALLER Charaktere des
-- Accounts in die Gilde, in der man gerade eingeloggt ist - wer mit einem
-- Account in zwei Gilden spielt, trug damit Name und Rezepte seines Twinks aus
-- Gilde A nach Gilde B (und umgekehrt). Die Daten der Gilden selbst waren nie
-- vermischt, die des eigenen Accounts schon.
--
-- Geschrieben wird nur, was belegt ist:
--   * ein bekannter Gildenname -> dessen Schluessel;
--   * ein Client, der ausdruecklich "keine Gilde" sagt -> der leere Vermerk;
--   * alles dazwischen (direkt nach dem Login liefert GetGuildInfo noch nichts,
--     obwohl der Charakter in einer Gilde ist) -> unveraendert stehen lassen.
-- Ein falscher Vermerk waere schlimmer als gar keiner: Er wuerde denselben
-- Uebertritt verursachen, den er verhindern soll.
-- Nachtrag 0.9.123: "keine Gilde" ist erst dann eine Aussage, wenn der Client
-- sie ueberhaupt treffen kann.
--
-- Bis dahin genuegte hier ein `IsInGuild() == false`. Genau das antwortet der
-- Client aber auch in den ersten Augenblicken nach dem Anmelden, wenn er die
-- Gildendaten noch gar nicht geladen hat - und Profile:Get laeuft in dieser
-- Zeit mehrfach (Workshop:GetOwnData und Profile:Refresh haengen beide am
-- PLAYER_LOGIN). Ein gildenTREUER Charakter bekam so den Vermerk "gildenlos"
-- verpasst, und der blieb an ihm haengen, bis ihn ein spaeterer Aufruf mit
-- bekanntem Gildennamen ueberschrieb - im schlimmsten Fall bis zum naechsten
-- Einloggen. Nachweisbar am eigenen Datenbestand des Owners.
--
-- Der Client meldet mit PLAYER_GUILD_UPDATE selbst, sobald sein Gildenzustand
-- steht (GC.guildStateKnown, gesetzt in Core.lua). Vorher wird nichts
-- geschrieben - ein Vermerk, der nur vielleicht stimmt, ist schlimmer als
-- keiner: Er entscheidet mit, was in die Gilde geht und was beim Aufraeumen
-- verschwindet.
local function StampGuildKey(profile)
    if GC:GetGuildName() ~= "" then
        profile.guildKey = GC:GetGuildKey()
    elseif GC.guildStateKnown and type(IsInGuild) == "function" and IsInGuild() == false then
        profile.guildKey = ""
    end
end

function GC.Profile:Get()
    local profile = GC.DB:GetCharacter()
    local _, classFile, classID = UnitClass("player")
    profile.fullName = GC:GetPlayerFullName()
    profile.classFile = classFile
    profile.classID = classID
    profile.level = UnitLevel("player")
    profile.mainStatus = profile.mainStatus or "MAIN"
    profile.flex = profile.flex == true
    profile.confirmed = profile.confirmed == true
    profile.professions = profile.professions or {}
    profile.professionAuto = profile.professionAuto ~= false
    profile.workshop = profile.workshop or { professions = {} }
    profile.workshop.professions = profile.workshop.professions or {}
    profile.absence = profile.absence or {
        from = "",
        to = "",
        reason = "",
    }
    if profile.secondarySpecKey == profile.raidSpecKey then
        profile.secondarySpecKey = nil
    end
    StampGuildKey(profile)
    return profile
end

function GC.Profile:GetAbsenceState(profile, today)
    profile = profile or self:Get()
    local absence = profile.absence or {}
    local rangeFrom = absence.from or ""
    local rangeTo = absence.to or ""
    if not GC.Util.IsValidISODate(rangeFrom) or not GC.Util.IsValidISODate(rangeTo) then
        return "NONE"
    end
    today = today or GC.Util.TodayISO()
    if today < rangeFrom then
        return "UPCOMING"
    elseif today > rangeTo then
        return "EXPIRED"
    end
    return "ACTIVE"
end

function GC.Profile:SetAbsence(rangeFrom, rangeTo, reason)
    -- Getippt wird hier auch "15.08.2026"; umgerechnet wird das vor der
    -- Pruefung, gespeichert wird ausschliesslich ISO (siehe NormalizeDateInput).
    rangeFrom = GC.Util.NormalizeDateInput(rangeFrom)
    rangeTo = GC.Util.NormalizeDateInput(rangeTo)
    reason = GC.Util.Trim(reason):gsub("[|%%\r\n]", " ")
    if not GC.Util.IsValidISODate(rangeFrom) or not GC.Util.IsValidISODate(rangeTo) then
        return false, "Bitte beide Daten wählen – über das Kalendersymbol oder als TT.MM.JJJJ."
    end
    if rangeFrom > rangeTo then
        return false, "Das Bis-Datum darf nicht vor dem Von-Datum liegen."
    end
    local profile = self:Get()
    profile.absence = {
        from = rangeFrom,
        to = rangeTo,
        reason = reason:sub(1, 80),
    }
    profile.updatedAt = GC.Util.Now()
    GC:FireCallback("PROFILE_UPDATED", profile, true)
    return true, "Abmeldung gespeichert und mit der Gilde synchronisiert."
end

function GC.Profile:ClearAbsence()
    local profile = self:Get()
    profile.absence = {
        from = "",
        to = "",
        reason = "",
    }
    profile.updatedAt = GC.Util.Now()
    GC:FireCallback("PROFILE_UPDATED", profile, true)
    return true
end

-- Erst die Retail-API, dann die Faehigkeitszeilen von Classic. Rueckgabe wie
-- bei ReadSkillLineProfessions: nil heisst "kein Weg, es herauszufinden".
local function ReadProfessions()
    if type(GetProfessions) == "function" then
        local profession1, profession2 = GetProfessions()
        -- Einzeln einsammeln: Fehlt der erste Beruf, endet ipairs ueber eine
        -- Tabelle mit nil an Position 1 sofort und verschluckt den zweiten.
        local first = ReadProfession(profession1)
        local second = ReadProfession(profession2)
        if first or second then
            local detected = {}
            if first then
                detected[#detected + 1] = first
            end
            if second then
                detected[#detected + 1] = second
            end
            return detected
        end
    end
    return ReadSkillLineProfessions()
end

-- Ergebnis des letzten automatischen Lesens. Rein lokal, wird nie gesendet -
-- es beschreibt diesen Client, nicht den Charakter.
--   OK          mindestens ein Beruf gelesen
--   EMPTY       nachgesehen, dieser Charakter hat keinen Hauptberuf
--   UNAVAILABLE der Client gibt die Berufsliste nicht heraus
--   MANUAL      die Uebernahme ist abgeschaltet, es gilt die eigene Auswahl
function GC.Profile:GetProfessionSource(profile)
    profile = profile or self:Get()
    if not profile.professionAuto then
        return "MANUAL"
    end
    return profile.professionSource or "UNAVAILABLE"
end

function GC.Profile:RefreshProfessions(profile)
    profile = profile or self:Get()
    if not profile.professionAuto then
        return false
    end

    local detected = ReadProfessions()
    if not detected then
        -- Nicht nachsehen koennen ist keine Antwort: Was gespeichert ist,
        -- bleibt stehen, aber die Oberflaeche darf keinen Erfolg behaupten.
        profile.professionSource = "UNAVAILABLE"
        return false
    end

    profile.professionSource = #detected > 0 and "OK" or "EMPTY"
    if #detected == 0 then
        -- Verlernt wird selten, aber es kommt vor. Bisher blieb der alte Beruf
        -- dann fuer immer stehen und wurde weiter an die Gilde gemeldet: Die
        -- leere Antwort setzte nur die Quelle auf "EMPTY" und kehrte um.
        --
        -- Geloescht wird deshalb genau dann, wenn dieselbe Sitzung vorher
        -- schon einmal Berufe gelesen hat. Damit ist belegt, dass der Client
        -- die Liste ueberhaupt herausgibt - direkt nach dem Login ist sie
        -- regelmaessig noch leer, obwohl der Charakter Berufe hat, und dieses
        -- Fenster darf nichts ausloeschen. Wer den Beruf tatsaechlich verlernt,
        -- hat ihn in derselben Sitzung vorher gelesen.
        if not self.sawProfessions then
            return false
        end
        if not profile.professions[1] and not profile.professions[2] then
            return false
        end
        profile.professions = {}
        return true
    end

    self.sawProfessions = true
    local changed = ProfessionChanged(profile.professions[1], detected[1])
        or ProfessionChanged(profile.professions[2], detected[2])
    profile.professions = { detected[1], detected[2] }
    return changed
end

function GC.Profile:SetProfession(slot, professionName)
    slot = tonumber(slot)
    if slot ~= 1 and slot ~= 2 then
        return
    end
    local profile = self:Get()
    profile.professionAuto = false
    professionName = GC.Util.Trim(professionName)
    profile.professions[slot] = professionName ~= "" and {
        name = professionName,
        skillLevel = 0,
        maxSkillLevel = 0,
    } or nil
    profile.updatedAt = GC.Util.Now()
    GC:FireCallback("PROFILE_UPDATED", profile, true)
end

function GC.Profile:EnableProfessionSync()
    local profile = self:Get()
    profile.professionAuto = true
    self:RefreshProfessions(profile)
    profile.updatedAt = GC.Util.Now()
    GC:FireCallback("PROFILE_UPDATED", profile, true)
end

function GC.Profile:Refresh()
    local profile = self:Get()
    local detectedSpecKey, signature, classFile, classID = self:DetectTalentSpec()
    -- Loading, combat restrictions and uncommitted edits are not a new build.
    if signature == nil then
        detectedSpecKey, signature = profile.detectedSpecKey, profile.talentSignature
    end
    local changed = profile.detectedSpecKey ~= detectedSpecKey
        or profile.talentSignature ~= signature
        or profile.classFile ~= classFile
        or profile.classID ~= classID
        or profile.level ~= UnitLevel("player")
    changed = self:RefreshProfessions(profile) or changed

    profile.detectedSpecKey = detectedSpecKey
    profile.talentSignature = signature
    profile.classFile = classFile
    profile.classID = classID
    profile.level = UnitLevel("player")

    if not profile.raidSpecKey and detectedSpecKey then
        profile.raidSpecKey = detectedSpecKey
        changed = true
    end
    -- Der Zeitstempel wandert nur mit, wenn sich wirklich etwas geaendert hat.
    -- Vorher sprang er bei jedem Ereignis nach vorn; gildenweit stand dann
    -- "gerade aktualisiert" an Profilen, an denen seit Wochen nichts passiert
    -- war - und ein Vergleich zweier Staende war damit wertlos.
    if changed then
        profile.updatedAt = GC.Util.Now()
        GC:FireCallback("PROFILE_UPDATED", profile, true)
    elseif not tonumber(profile.updatedAt) then
        profile.updatedAt = GC.Util.Now()
    end
    return profile
end

-- Ergebnis der letzten Bestaetigung. Bisher stand es nur im Chat und war nach
-- ein paar Kampfmeldungen weggescrollt - wer nebenher etwas anderes tat, wusste
-- hinterher nicht, ob sein Profil nun steht. Deshalb bleibt es am Profil.
function GC.Profile:GetLastConfirmation()
    return self.lastConfirmation
end

function GC.Profile:NoteConfirmation(ok, message)
    self.lastConfirmation = {
        ok = ok == true,
        message = message,
        at = GC.Util.Now(),
    }
    GC:FireCallback("PROFILE_CONFIRMATION_CHANGED")
    return self.lastConfirmation
end

function GC.Profile:Confirm(raidSpecKey, secondarySpecKey, mainStatus, flex)
    if secondarySpecKey == "MAIN" or secondarySpecKey == "ALT" then
        flex = mainStatus
        mainStatus = secondarySpecKey
        secondarySpecKey = nil
    end

    local function Fail(message)
        self:NoteConfirmation(false, message)
        return nil, message
    end

    local profile = self:Refresh()
    raidSpecKey = raidSpecKey or profile.raidSpecKey or profile.detectedSpecKey
    local raidSpec = raidSpecKey and GC.SpecByKey[raidSpecKey]
    if not raidSpec or raidSpec.classFile ~= profile.classFile then
        return Fail("Bitte zuerst eine gültige Primär-Spec deiner Klasse auswählen.")
    end
    profile.raidSpecKey = raidSpecKey

    if secondarySpecKey
        and (secondarySpecKey == profile.raidSpecKey
            or not GC.SpecByKey[secondarySpecKey]
            or GC.SpecByKey[secondarySpecKey].classFile ~= profile.classFile) then
        return Fail("Die Dual-Spec muss zu deiner Klasse passen und sich von der Primär-Spec unterscheiden.")
    end
    if secondarySpecKey then
        profile.secondarySpecKey = secondarySpecKey
    else
        profile.secondarySpecKey = nil
    end
    profile.mainStatus = mainStatus == "ALT" and "ALT" or "MAIN"
    profile.flex = flex == true
    profile.confirmed = true
    profile.updatedAt = GC.Util.Now()
    profile.confirmedAt = profile.updatedAt
    GC:FireCallback("PROFILE_UPDATED", profile, true)
    GC:Print("Dein Raidprofil wurde bestätigt.")
    -- Eigener Ton: Der Bewerberton meldet einen fremden Interessenten, das hier
    -- ist die Rueckmeldung auf die eigene Eingabe. Beides gleich klingen zu
    -- lassen hiess, zweimal nachzusehen.
    if GC.Chat and GC.Chat.PlayProfileSound then
        GC.Chat:PlayProfileSound()
    end
    self:NoteConfirmation(true, "Raidprofil bestätigt.")
    return profile
end

-- === Entprellung ===========================================================
--
-- SKILL_LINES_CHANGED feuert in TBC bei jedem Fertigkeitspunkt - auch bei
-- Waffenfertigkeit, also mitten im Kampf im Sekundentakt. Jeder Durchlauf liest
-- Talente, Berufe und die komplette Fähigkeitsliste neu. Gesammelt wird deshalb:
-- zehn Punkte in drei Sekunden ergeben einen Durchlauf.
--
-- Die zweite Sperre ist wichtiger: Das Auf- und Zuklappen der Kategorien in
-- ReadSkillLineProfessions löst selbst SKILL_LINES_CHANGED aus. Ohne
-- SKILL_EVENT_LOCK trieb sich das Addon damit endlos selbst an - der
-- wahrscheinlichste Grund für die gemeldeten Bildraten-Einbrüche.
local REFRESH_DEBOUNCE = 3
local SKILL_EVENT_LOCK = 5

function GC.Profile:ScheduleRefresh(delay)
    if not GC.DB or not GC.DB.data then
        return false
    end
    if not C_Timer or type(C_Timer.After) ~= "function" then
        self:Refresh()
        return true
    end
    if self.refreshPending then
        return false
    end
    self.refreshPending = true
    C_Timer.After(tonumber(delay) or REFRESH_DEBOUNCE, function()
        GC.Profile.refreshPending = false
        GC.Profile:Refresh()
    end)
    return true
end

-- Als Methode statt als anonymer Handler: Die Sperre gegen den selbst
-- erzeugten Ereignissturm ist die wichtigste Zeile dieser Datei, und was sich
-- nicht aufrufen laesst, laesst sich auch nicht pruefen.
function GC.Profile:OnGameEvent(event)
    if event == "SKILL_LINES_CHANGED"
        and (self:Clock() - (self.skillHeadersTouchedAt or -math.huge)) < SKILL_EVENT_LOCK then
        -- Das war unser eigenes Auf- und Zuklappen, nicht der Spieler.
        return false
    end
    return self:ScheduleRefresh()
end

local profileEvents = CreateFrame("Frame")
profileEvents:RegisterEvent("CHARACTER_POINTS_CHANGED")
profileEvents:RegisterEvent("PLAYER_LEVEL_UP")
profileEvents:RegisterEvent("PLAYER_GUILD_UPDATE")
profileEvents:RegisterEvent("SKILL_LINES_CHANGED")
profileEvents:RegisterEvent("TRADE_SKILL_SHOW")
for _, event in ipairs({ "PLAYER_TALENT_UPDATE", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "TRAIT_CONFIG_UPDATED", "PLAYER_REGEN_ENABLED" }) do
    GC.Client.RegisterEvent(profileEvents, event)
end
profileEvents:SetScript("OnEvent", function(_, event)
    GC.Profile:OnGameEvent(event)
end)

GC:RegisterCallback("PLAYER_LOGIN", GC.Profile, function(self)
    self:Refresh()
    -- Die Fähigkeitsliste ist direkt beim Login oft noch leer; der Client
    -- füllt sie erst Sekunden später nach. Auf einem fertig geskillten
    -- Charakter feuert SKILL_LINES_CHANGED danach nie wieder - ohne diese
    -- Nachlese blieben die Berufe dann dauerhaft ungelesen, und es sah so
    -- aus, als würde die Automatik gar nicht existieren.
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(5, function()
            GC.Profile:Refresh()
        end)
        C_Timer.After(20, function()
            GC.Profile:Refresh()
        end)
    end
end)
