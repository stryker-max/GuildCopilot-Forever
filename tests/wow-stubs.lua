-- === WoW-Stellvertreter fuer die Lua-Tests ================================
--
-- Alles, was im Spiel die Spiel-API waere: Rahmen, Schriftobjekte, Roster,
-- Gildenbank, Chat, Zeitgeber. Zwei Tests brauchen dieselben Stellvertreter -
-- tests/smoke.lua fuer die vollstaendige Fassung und tests/reduced.lua fuer
-- das reduzierte CurseForge-Paket -, deshalb stehen sie hier statt zweimal.
--
-- Die Werte auf oberster Ebene sind bewusst GLOBAL: Der aufrufende Test laeuft
-- in einem eigenen Chunk und saehe ein "local" von hier aus nicht. Das
-- entlastet nebenbei die Lua-5.1-Grenze von 200 lokalen Variablen je Funktion,
-- an der der Haupt-Chunk von smoke.lua ohnehin steht.

Dummy = {}
-- WoW-Widgetmethoden beginnen mit einem Großbuchstaben, vom Addon gesetzte
-- Datenfelder (scripts, choiceIcon, label, ...) mit einem Kleinbuchstaben.
-- Nur Methoden dürfen ersatzweise als Funktion zurückkommen; unbelegte
-- Datenfelder müssen wie in WoW nil bleiben, damit Prüfungen der Form
-- "if widget.choiceIcon then" nicht fälschlich zutreffen.
Dummy.__index = function(self, key)
    if key == "GetText" then
        return function(frame)
            return frame.value or ""
        end
    elseif key == "SetText" then
        return function(frame, value)
            frame.value = tostring(value or "")
            if frame.scripts and frame.scripts.OnTextChanged then
                frame.scripts.OnTextChanged(frame)
            end
        end
    elseif key == "GetChecked" then
        return function(frame)
            return frame.checked == true
        end
    elseif key == "SetChecked" then
        return function(frame, value)
            frame.checked = value == true
        end
    elseif key == "IsShown" then
        return function(frame)
            return frame.shown == true
        end
    elseif key == "SetVerticalScroll" then
        return function(frame, value)
            frame.verticalScroll = tonumber(value) or 0
        end
    elseif key == "GetVerticalScroll" then
        return function(frame)
            return frame.verticalScroll or 0
        end
    elseif key == "SetAttribute" then
        -- Fuer den Herstellen-Knopf: Ob ein Zauber am sicheren Knopf haengt,
        -- entscheidet, ob ein Klick das Berufsfenster oeffnet oder fertigt.
        return function(frame, name, value)
            frame.attributes = frame.attributes or {}
            frame.attributes[name] = value
        end
    elseif key == "GetAttribute" then
        return function(frame, name)
            return (frame.attributes or {})[name]
        end
    elseif key == "SetScale" then
        -- Fuer die Fensterkarte: Massstab und Deckkraft bleiben ablesbar.
        return function(frame, value)
            frame.scale = tonumber(value)
        end
    elseif key == "GetScale" then
        return function(frame)
            return frame.scale or 1
        end
    elseif key == "SetAlpha" then
        return function(frame, value)
            frame.alpha = tonumber(value)
        end
    elseif key == "GetAlpha" then
        return function(frame)
            return frame.alpha or 1
        end
    elseif key == "SetHeight" then
        -- Fuer Layouttests: die gesetzte Hoehe bleibt ablesbar.
        return function(frame, value)
            frame.height = tonumber(value)
        end
    elseif key == "GetHeight" then
        return function(frame)
            return frame.height
        end
    elseif key == "SetWidth" then
        -- Ebenso die Breite. Ohne sie waechst eine Beschriftung in WoW ueber
        -- ihre Karte hinaus, und genau das laesst sich nur hier pruefen.
        return function(frame, value)
            frame.width = tonumber(value)
        end
    elseif key == "SetSize" then
        -- Karten und Knoepfe werden am Stueck bemasst. Ohne diesen Zweig
        -- blieben genau ihre Masse als einzige unlesbar - also ausgerechnet
        -- die, um die es in einem Layouttest geht.
        return function(frame, width, height)
            frame.width = tonumber(width)
            frame.height = tonumber(height)
        end
    elseif key == "GetWidth" then
        return function(frame)
            return frame.width
        end
    elseif key == "SetShown" then
        return function(frame, value)
            frame.shown = value == true
        end
    elseif key == "Show" then
        return function(frame)
            frame.shown = true
        end
    elseif key == "Hide" then
        return function(frame)
            frame.shown = false
        end
    elseif key == "HasFocus" then
        -- Ein einfaches Fokusmodell, damit sich pruefen laesst, ob ein
        -- verstecktes Feld die Tastatur wieder freigibt (0.9.142).
        return function(frame)
            return frame.focused == true
        end
    elseif key == "SetFocus" then
        return function(frame)
            frame.focused = true
        end
    elseif key == "ClearFocus" then
        return function(frame)
            frame.focused = false
        end
    elseif key == "EnableKeyboard" then
        -- Ob das Hauptfenster die Tastatur abfaengt, bleibt ablesbar: Zugeklappt
        -- muss es sie freigeben, sonst schluckt der Balken das Enter fuer den
        -- Chat (0.9.140).
        return function(frame, value)
            frame.keyboardEnabled = value ~= false
        end
    elseif key == "HookScript" then
        -- Anders als SetScript ueberschreibt HookScript nichts: Es haengt einen
        -- weiteren Rueckruf an. Die Tests koennen ihn ueber frame.hooks
        -- ausloesen (in WoW feuert OnHide, sobald ein Vorfahre versteckt wird).
        return function(frame, event, callback)
            frame.hooks = frame.hooks or {}
            frame.hooks[event] = frame.hooks[event] or {}
            table.insert(frame.hooks[event], callback)
        end
    elseif key == "Enable" then
        -- Fuer Layouttests: ob ein Knopf bedienbar ist, bleibt ablesbar.
        return function(frame)
            frame.disabled = false
        end
    elseif key == "Disable" then
        return function(frame)
            frame.disabled = true
        end
    elseif key == "IsEnabled" then
        return function(frame)
            return frame.disabled ~= true
        end
    elseif key == "SetScript" then
        return function(frame, event, callback)
            frame.scripts = frame.scripts or {}
            frame.scripts[event] = callback
        end
    elseif key == "CreateFontString" then
        return function()
            return setmetatable({}, Dummy)
        end
    elseif key == "CreateTexture" then
        return function()
            return setmetatable({}, Dummy)
        end
    -- Elternrahmen und Rahmenebene bleiben ablesbar. Ohne sie liesse sich nicht
    -- pruefen, ob ein Knopf IM Eingabefeld ueber dessen EditBox liegt - und
    -- genau daran scheiterte das Kalendersymbol der Abmeldung: gleiche Ebene,
    -- also fing die EditBox den Klick ab.
    elseif key == "SetParent" then
        return function(frame, parent)
            frame.parent = parent
        end
    elseif key == "SetFrameLevel" then
        return function(frame, level)
            frame.frameLevel = tonumber(level)
        end
    elseif key == "GetFrameLevel" then
        -- Wie in WoW: Ohne eigene Ebene liegt ein Rahmen eine ueber seinem
        -- Elternteil. Ohne diese Vererbung liesse sich nicht pruefen, ob ein
        -- Aufklappmenue ueber seinem Dialog liegt - und genau daran scheiterte
        -- die Berufswahl im Freitext-Auftrag.
        return function(frame)
            if frame.frameLevel then
                return frame.frameLevel
            end
            local parent = frame.parent
            if parent and parent.GetFrameLevel then
                return (parent:GetFrameLevel() or 0) + 1
            end
            return 1
        end
    end
    if type(key) ~= "string" or not key:match("^%u") then
        return nil
    end
    return function()
    end
end

-- Ein Bildschirm mit Massen: Aufklappmenues entscheiden anhand der Hoehe von
-- UIParent, ob sie nach oben oder nach unten aufgehen.
UIParent = setmetatable({ width = 1920, height = 1080 }, Dummy)
Minimap = setmetatable({}, Dummy)
function Minimap:GetCenter()
    return 0, 0
end
function Minimap:GetEffectiveScale()
    return 1
end
-- Stellbarer Mauszeiger, damit sich das Ziehen des Minimap-Symbols pruefen
-- laesst: nah an der Minimap faehrt es auf dem Ring, weit weg loest es sich.
cursorX = 0
cursorY = 0
function GetCursorPosition()
    return cursorX, cursorY
end
UISpecialFrames = {}
SlashCmdList = {}
SOUNDKIT = { READY_CHECK = 8960 }
EMPTY_SOCKET_RED = "Roter Sockel"
EMPTY_SOCKET_YELLOW = "Gelber Sockel"
EMPTY_SOCKET_BLUE = "Blauer Sockel"
function InterfaceOptions_AddCategory(panel)
    optionsCategory = panel
end
chatMessages = {}
-- Die Eingabezeile des Chats. Ueber sie fuehrt das Addon Chatbefehle aus;
-- gemerkt wird, was tatsaechlich abgeschickt wurde.
sentSlashCommands = {}
chatEditBox = {
    text = "",
    SetText = function(self, value)
        self.text = tostring(value or "")
    end,
    GetText = function(self)
        return self.text
    end,
}
function ChatEdit_SendText(editBox, _)
    local text = editBox and editBox:GetText() or ""
    if text ~= "" then
        sentSlashCommands[#sentSlashCommands + 1] = text
    end
end
DEFAULT_CHAT_FRAME = {
    editBox = chatEditBox,
    AddMessage = function(_, message)
        chatMessages[#chatMessages + 1] = tostring(message)
    end,
}

-- Tooltipzeilen je Item-Link, damit die Verzauberungsaufloesung pruefbar ist.
tooltipLines = {}

function CreateFrame(_, name, parent)
    local frame = setmetatable({ shown = false, scripts = {}, parent = parent }, Dummy)
    if name then
        _G[name] = frame
    end
    if name == "GuildCopilotForeverScanTooltip" then
        frame.lines = {}
        function frame:ClearLines()
            self.lines = {}
        end
        function frame:SetHyperlink(link)
            self.lines = tooltipLines[link] or {}
            for index = 1, 12 do
                local text = self.lines[index]
                _G[name .. "TextLeft" .. index] = text and {
                    GetText = function()
                        return text
                    end,
                } or nil
            end
        end
        function frame:NumLines()
            return #self.lines
        end
    end
    return frame
end

function UnitFullName()
    return "Tester", "Realm"
end

unitNames = { player = "Tester" }
function UnitName(unit)
    return unitNames[unit] or "Tester"
end

unitClasses = { player = "HUNTER" }
function UnitClass(unit)
    return "Jäger", unitClasses[unit] or "HUNTER", 3
end

function UnitLevel()
    return 70
end

function UnitSex()
    return 2
end

function GetNormalizedRealmName()
    return "Realm"
end

function GetGuildInfo()
    return "Testgilde"
end

function IsInGuild()
    return true
end

function GetTalentTabInfo(index)
    local points = ({ 10, 41, 0 })[index]
    return index, "Baum " .. index, "", 0, points, ""
end

function GetNumGuildMembers()
    return 2
end

-- Der Client loest Klassen ueber die GUID auf. Direkt nach dem Login ist der
-- Cache leer, deshalb kann der Aufruf auch nichts liefern.
playerInfoByGUID = {
    ["Player-4"] = { "Paladin", "PALADIN" },
}
function GetPlayerInfoByGUID(guid)
    local entry = playerInfoByGUID[guid or ""]
    if not entry then
        return nil
    end
    return entry[1], entry[2], "Mensch", "Human", "male", "Interessent", "Realm"
end

function GetGuildRosterInfo(index)
    if index == 1 then
        return "Tester-Realm", "Offizier", 1, 70, "Jäger", "Shattrath", "", "", true, 0, "HUNTER", 0, 0, false, false, 0, "Player-1"
    end
    return "Heiler-Realm", "Mitglied", 5, 70, "Priester", "Shattrath", "", "", false, 0, "PRIEST", 0, 0, false, false, 0, "Player-2"
end

function GetGuildRosterLastOnline(index)
    if index == 2 then
        return 0, 0, 10, 0
    end
    return 0, 0, 0, 0
end

function GetProfessions()
    return 1, 2
end

-- Faehigkeitszeilen wie im Classic-Client: Dort gibt es GetProfessions nicht,
-- die Berufe stehen unter einer Kategorie im Faehigkeitenfenster. Die
-- Kategorie ist absichtlich zugeklappt - eingeklappt zaehlt sie ihre Zeilen
-- nicht mit, und genau daran scheitert eine Erfassung, die nicht aufklappt.
skillHeaderExpanded = false
skillHeaderToggles = 0
function GetNumSkillLines()
    return skillHeaderExpanded and 3 or 1
end
function GetSkillLineInfo(index)
    if index == 1 then
        return "Berufe", true, skillHeaderExpanded
    elseif index == 2 then
        return "Verzauberkunst", false, false, 375, 0, 0, 375
    elseif index == 3 then
        return "Schneiderei", false, false, 350, 0, 0, 375
    end
end
function ExpandSkillHeader()
    skillHeaderExpanded = true
    skillHeaderToggles = skillHeaderToggles + 1
end
function CollapseSkillHeader()
    skillHeaderExpanded = false
    skillHeaderToggles = skillHeaderToggles + 1
end

function GetProfessionInfo(index)
    if index == 1 then
        return "Ingenieurskunst", "", 375, 375, 0, 0, 202
    elseif index == 2 then
        return "Bergbau", "", 360, 375, 0, 0, 186
    end
end

function GetTradeSkillLine()
    return "Schneiderei", 375, 375
end

tradeSkillExpanded = false
tradeSkillFilterResets = 0

function ExpandTradeSkillSubClass(index)
    if index == 1 then
        tradeSkillExpanded = true
    end
end

function SetTradeSkillInvSlotFilter()
    tradeSkillFilterResets = tradeSkillFilterResets + 1
end

function SetTradeSkillSubClassFilter()
    tradeSkillFilterResets = tradeSkillFilterResets + 1
end

function SetTradeSkillItemNameFilter()
    tradeSkillFilterResets = tradeSkillFilterResets + 1
end

function SetTradeSkillItemLevelFilter()
    tradeSkillFilterResets = tradeSkillFilterResets + 1
end

function TradeSkillOnlyShowSkillUps()
    tradeSkillFilterResets = tradeSkillFilterResets + 1
end

function TradeSkillOnlyShowMakeable()
    tradeSkillFilterResets = tradeSkillFilterResets + 1
end

function GetNumTradeSkills()
    return tradeSkillExpanded and 3 or 1
end

function GetTradeSkillInfo(index)
    if index == 1 then
        return "Taschen", "header", nil, tradeSkillExpanded
    elseif index == 2 then
        return "Mondstofftasche", "optimal"
    elseif index == 3 then
        return "Runenstoffballen", "trivial"
    end
end

function GetTradeSkillItemLink(index)
    if index == 2 then
        return "|cffffffff|Hitem:14155:0:0:0:0:0:0:0|h[Mondstofftasche]|h|r"
    elseif index == 3 then
        return "|cffffffff|Hitem:14048:0:0:0:0:0:0:0|h[Runenstoffballen]|h|r"
    end
end

function GetTradeSkillRecipeLink(index)
    return index == 2 and "|Henchant:18445|h[Mondstofftasche]|h" or "|Henchant:18401|h[Runenstoffballen]|h"
end

function GetTradeSkillNumReagents(index)
    return index == 2 and 2 or 1
end

function GetTradeSkillReagentInfo(index, reagentIndex)
    if index == 2 and reagentIndex == 1 then
        return "Runenstoffballen", "", 4, 20
    elseif index == 2 and reagentIndex == 2 then
        return "Mondstoff", "", 2, 4
    end
    return "Runenstoff", "", 5, 40
end

function GetTradeSkillReagentItemLink(index, reagentIndex)
    if index == 2 and reagentIndex == 1 then
        return "|Hitem:14048|h[Runenstoffballen]|h"
    elseif index == 2 and reagentIndex == 2 then
        return "|Hitem:14342|h[Mondstoff]|h"
    end
    return "|Hitem:14047|h[Runenstoff]|h"
end

function GetCraftSkillLine()
    return "Verzauberkunst", 375, 375
end

function GetCraftDisplaySkillLine()
    return "Verzauberkunst"
end

function GetNumCrafts()
    return 2
end

-- Herstellbefehle: Sie werden nur mitgeschrieben, nicht ausgefuehrt.
craftCalls = {}
function DoTradeSkill(index, count)
    craftCalls[#craftCalls + 1] = { kind = "CLASSIC", index = index, count = count }
end
function DoCraft(index)
    craftCalls[#craftCalls + 1] = { kind = "CRAFT", index = index, count = 1 }
end

function GetCraftInfo(index)
    if index == 1 then
        return "Ringverzauberungen", "", "header"
    end
    return "Ring - Heilkraft", "", "optimal"
end

function GetCraftItemLink(index)
    if index == 2 then
        return "|Henchant:27926|h[Ring - Heilkraft]|h"
    end
end

function GetCraftNumReagents(index)
    return index == 2 and 1 or 0
end

function GetCraftReagentInfo(index, reagentIndex)
    if index == 2 and reagentIndex == 1 then
        return "Großer prismatischer Splitter", "", 2, 8
    end
end

function GetCraftReagentItemLink(index, reagentIndex)
    if index == 2 and reagentIndex == 1 then
        return "|Hitem:22449|h[Großer prismatischer Splitter]|h"
    end
end

function GetItemInfo(itemID)
    local names = {
        [14047] = "Runenstoff",
        [14048] = "Runenstoffballen",
        [14155] = "Mondstofftasche",
        [14342] = "Mondstoff",
        [22449] = "Großer prismatischer Splitter",
    }
    return names[tonumber(itemID)]
end

raidRoster = {}

function IsInRaid()
    return #raidRoster > 0
end

function IsInGroup()
    return #raidRoster > 0 or #partyRoster > 0
end

partyRoster = {}

function GetNumGroupMembers()
    if #raidRoster > 0 then
        return #raidRoster
    end
    return #partyRoster
end

-- name, rank, subgroup, level, class, fileName
function GetRaidRosterInfo(index)
    local member = raidRoster[index]
    if not member then
        return nil
    end
    return member[1], member[2], 1, 70, "", member[3]
end

function GetRealZoneText()
    return "Karazhan"
end

combatLogEvent = {}
function CombatLogGetCurrentEventInfo()
    return unpack(combatLogEvent)
end

-- Baut ein Combat-Log-Ereignis in der Reihenfolge des echten Clients auf.
function FireCombatLog(subevent, sourceName, destName, spellID, destGUID)
    combatLogEvent = {
        1000, subevent, false,
        "Player-" .. tostring(sourceName), sourceName, 0, 0,
        destGUID or ("Player-" .. tostring(destName)), destName, 0, 0,
        spellID,
    }
    GuildCopilotForever.RaidMonitor:OnCombatLogEvent()
end

-- Ausrüstung je Slot-ID und Einheit für den Gear Audit.
inspectGear = {}
inspectGearItemIDs = {}

function GetInventoryItemLink(unit, slotID)
    return (inspectGear[unit] or {})[slotID]
end

function GetInventoryItemID(unit, slotID)
    local explicit = (inspectGearItemIDs[unit] or {})[slotID]
    if explicit then
        return explicit
    end
    return tonumber(tostring(GetInventoryItemLink(unit, slotID) or ""):match("item:(%d+)"))
end

function GetItemStats(link)
    local sockets = tonumber(tostring(link or ""):match("SOCKETS(%d)"))
    if not sockets then
        return {}
    end
    return { EMPTY_SOCKET_RED = sockets }
end

function UnitExists(unit)
    return (inspectGear[unit] ~= nil) or (unitNames[unit] ~= nil) or unit == "player"
end

function UnitIsUnit(left, right)
    return left == right
end

function UnitGUID(unit)
    return "GUID-" .. tostring(unit)
end

inspectableUnits = {}
function CanInspect(unit)
    return inspectableUnits[unit] ~= false
end

function NotifyInspect()
end

canRemoveFromGuild = true
function CanGuildRemove()
    return canRemoveFromGuild
end

-- Kein Stellvertreter, sondern eine Stolperdrahtl: Das Addon darf
-- GuildUninvite nie aufrufen - die Funktion ist in WoW geschuetzt und tut aus
-- einem Addon heraus ohnehin nichts. Ein Aufruf wird hier vermerkt und am
-- Ende des Laufs beanstandet; ein blosses error() wuerde in einem pcall des
-- Addons verschwinden.
uninvitedPlayers = {}
function GuildUninvite(name)
    uninvitedPlayers[#uninvitedPlayers + 1] = tostring(name)
end

function ClearInspectPlayer()
end

function GetChannelList()
    return 1, "Allgemein", false, 2, "Handel", false, 4, "SucheNachGruppe", false, 5, "Gildenrekrutierung", false
end

function PlaySound(soundID)
    playedSoundID = soundID
end

-- Stellbarer Kampfzustand: Grosse Uebertragungen pausieren im Kampf.
inCombat = false
function InCombatLockdown()
    return inCombat == true
end
function UnitAffectingCombat(unit)
    return unit == "player" and inCombat == true
end

-- Der Zeitgeber der Messung. In WoW zaehlt debugprofilestop Millisekunden seit
-- Profilstart; hier reicht eine monoton steigende Zahl.
profileClock = 0
function debugprofilestop()
    profileClock = profileClock + 1
    return profileClock
end

-- Stellbare Uhr, damit Mindestabstände und Cooldowns prüfbar sind.
currentTime = 1000
function time()
    return currentTime
end

-- WoWs date() entspricht os.date. Die Testuhr steht fest auf dem 27.07.2026
-- (12:00 UTC, damit keine Zeitzone den Tag kippt): Aufrufe ohne Zeitpunkt
-- bekommen den eingefrorenen Tag. Kleine Zeitpunkte stammen von der
-- stellbaren time()-Uhr (startet bei 1000) und werden relativ auf den
-- eingefrorenen Tag gelegt - so rechnet AddDaysISO wie erwartet in die
-- Zukunft. Nur echte Epochenwerte werden unverändert formatiert.
function date(format, value)
    if format == nil then
        return "2026-07-27"
    end
    if value == nil then
        return os.date(format, 1785153600)
    end
    value = tonumber(value) or 0
    if value < 100000000 then
        return os.date(format, 1785153600 + value - currentTime)
    end
    return os.date(format, value)
end

-- Zeitgeber laufen sofort. Wer eine echte Verzoegerung braucht, setzt
-- timerDelayThreshold: alles darueber wandert in pendingTimers statt zu feuern.
timerDelayThreshold = math.huge
pendingTimers = {}
C_Timer = {
    After = function(delay, callback)
        if (tonumber(delay) or 0) > timerDelayThreshold then
            pendingTimers[#pendingTimers + 1] = callback
            return
        end
        callback()
    end,
}

sentChat = {}
sentAddon = {}
addonSendFailures = 0
C_ChatInfo = {
    RegisterAddonMessagePrefix = function()
        return true
    end,
    SendAddonMessage = function(prefix, message, distribution, target)
        if addonSendFailures > 0 then
            addonSendFailures = addonSendFailures - 1
            return false
        end
        sentAddon[#sentAddon + 1] = { prefix, message, distribution, target }
        return true
    end,
    SendChatMessage = function(message, chatType, language, target)
        sentChat[#sentChat + 1] = { message, chatType, language, target }
    end,
}

C_GuildInfo = {
    GuildRoster = function()
    end,
    Invite = function()
    end,
}

-- Taschen, eigene Bank und Gildenbank. Der Anniversary-Client bietet nur die
-- klassischen Globalen, deshalb wird genau dieser Pfad nachgebildet.
bagContents = {
    [0] = { { itemID = 22445, count = 20 }, { itemID = 22446, count = 5 } },
}
bankContents = {
    [-1] = { { itemID = 22446, count = 9 } },
}
guildBankContents = {
    [1] = { { itemID = 22446, count = 32 }, { itemID = 22447, count = 4 } },
}
guildBankTabCount = 1
guildBankTabViewable = true
function GetContainerNumSlots(container)
    local source = bagContents[container] or bankContents[container]
    return source and #source or 0
end
function GetContainerItemLink(container, slot)
    local source = bagContents[container] or bankContents[container]
    local entry = source and source[slot]
    return entry and ("|cffffffff|Hitem:" .. entry.itemID .. "::::::::70|h[Material]|h|r") or nil
end
function GetContainerItemInfo(container, slot)
    local source = bagContents[container] or bankContents[container]
    local entry = source and source[slot]
    if not entry then
        return nil
    end
    return "texture", entry.count
end
function GetNumGuildBankTabs()
    return guildBankTabCount
end
function GetGuildBankTabInfo(tabIndex)
    return "Mats " .. tabIndex, "icon", guildBankTabViewable, true
end
function QueryGuildBankTab()
end
function GetCurrentGuildBankTab()
    return 1
end
function GetGuildBankItemLink(tabIndex, slot)
    local entry = (guildBankContents[tabIndex] or {})[slot]
    return entry and ("|cffffffff|Hitem:" .. entry.itemID .. "::::::::70|h[Material]|h|r") or nil
end
function GetGuildBankItemInfo(tabIndex, slot)
    local entry = (guildBankContents[tabIndex] or {})[slot]
    if not entry then
        return nil
    end
    return "texture", entry.count
end

-- === Ein Addon-Verzeichnis laden, so wie WoW es laedt ======================
--
-- Die Ladereihenfolge steht in der TOC, und nur dort. Hier stand frueher eine
-- zweite, von Hand gepflegte Dateiliste - die stimmt genau so lange, bis
-- jemand eine Datei nur in der TOC eintraegt. Ausserdem laedt der Test damit
-- ohne weiteres Zutun auch die REDUZIERTE Fassung des CurseForge-Pakets, deren
-- TOC eine Datei weniger nennt.
--
-- Gelesen wird ueber GC_ReadTextFile, falls der Aufrufer eine solche Funktion
-- bereitstellt: Der fengari-Runner (tools/run-lua-tests.mjs) tut das, weil
-- fengari zwar loadfile kennt, aber kein io.open. Unter einem echten Lua -
-- LuaJIT auf dem Entwicklungsrechner - gibt es io.open, und dann wird es
-- genommen.
local function ReadTextFile(path)
    if type(GC_ReadTextFile) == "function" then
        local content, err = GC_ReadTextFile(path)
        return content, err
    end
    local handle, err = io.open(path, "r")
    if not handle then
        return nil, err
    end
    local content = handle:read("*a")
    handle:close()
    return content
end

function LoadAddonFrom(directory)
    local tocPath = directory .. "/GuildCopilotForever.toc"
    local content, readError = ReadTextFile(tocPath)
    assert(content, "Keine GuildCopilotForever.toc in " .. directory
        .. " (" .. tostring(readError) .. ")")

    local files = {}
    for line in tostring(content):gmatch("[^\n]+") do
        -- Das abschliessende %s+ faengt auch ein \r aus CRLF-Zeilenenden.
        local entry = line:gsub("^%s+", ""):gsub("%s+$", "")
        if entry ~= "" and entry:sub(1, 1) ~= "#" then
            files[#files + 1] = entry
        end
    end
    assert(#files > 0, "Die TOC in " .. directory .. " laedt keine Datei")

    local addonTable = {}
    for _, file in ipairs(files) do
        local chunk = assert(loadfile(directory .. "/" .. file),
            "Die TOC nennt " .. file .. ", die Datei fehlt in " .. directory)
        chunk("GuildCopilotForever", addonTable)
    end
    return addonTable, files
end
