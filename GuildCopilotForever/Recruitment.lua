local _, GC = ...

GC.Recruitment = {}

local function InvalidateAdvertisement()
    if not GC.DB or not GC.DB.data then
        return
    end
    local recruitment = GC.DB:GetGuild().recruitment
    recruitment.adText = ""
    recruitment.confirmedText = nil
end

function GC.Recruitment:GetSelections()
    return GC.DB:GetGuild().recruitment.selections
end

function GC.Recruitment:GetClassOrder()
    local recruitment = GC.DB:GetGuild().recruitment
    local storedOrder = recruitment.classOrder or {}
    local order = {}
    local seen = {}
    for _, classFile in ipairs(storedOrder) do
        if GC.Classes[classFile] and not seen[classFile] then
            order[#order + 1] = classFile
            seen[classFile] = true
        end
    end
    for _, classFile in ipairs(GC.ClassOrder) do
        if not seen[classFile] then
            order[#order + 1] = classFile
            seen[classFile] = true
        end
    end
    recruitment.classOrder = order
    return order
end

function GC.Recruitment:MoveClass(classFile, direction)
    local order = self:GetClassOrder()
    local currentIndex
    for index, orderedClass in ipairs(order) do
        if orderedClass == classFile then
            currentIndex = index
            break
        end
    end
    if not currentIndex then
        return
    end
    local targetIndex = math.max(1, math.min(#order, currentIndex + direction))
    if targetIndex ~= currentIndex then
        order[currentIndex], order[targetIndex] = order[targetIndex], order[currentIndex]
        InvalidateAdvertisement()
        GC:FireCallback("RECRUITMENT_UPDATED")
    end
end

function GC.Recruitment:MoveSelectedClass(classFile, direction)
    local order = self:GetClassOrder()
    local selectedClasses = {}
    for _, orderedClass in ipairs(order) do
        if self:GetClassSelectionLabel(orderedClass, true) then
            selectedClasses[#selectedClasses + 1] = orderedClass
        end
    end

    local selectedIndex
    for index, selectedClass in ipairs(selectedClasses) do
        if selectedClass == classFile then
            selectedIndex = index
            break
        end
    end
    if not selectedIndex then
        return
    end

    local targetSelectedIndex = selectedIndex + direction
    local targetClass = selectedClasses[targetSelectedIndex]
    if not targetClass then
        return
    end

    local currentOrderIndex
    local targetOrderIndex
    for index, orderedClass in ipairs(order) do
        if orderedClass == classFile then
            currentOrderIndex = index
        elseif orderedClass == targetClass then
            targetOrderIndex = index
        end
    end
    if currentOrderIndex and targetOrderIndex then
        order[currentOrderIndex], order[targetOrderIndex] = order[targetOrderIndex], order[currentOrderIndex]
        InvalidateAdvertisement()
        GC:FireCallback("RECRUITMENT_UPDATED")
    end
end

function GC.Recruitment:SetPriority(classFile, highPriority)
    if not GC.Classes[classFile] then
        return
    end
    local priorities = GC.DB:GetGuild().recruitment.priorities
    priorities[classFile] = highPriority == true or nil
    InvalidateAdvertisement()
    GC:FireCallback("RECRUITMENT_UPDATED")
end

function GC.Recruitment:IsHighPriority(classFile)
    return GC.DB:GetGuild().recruitment.priorities[classFile] == true
end

function GC.Recruitment:SetClass(classFile, enabled)
    if not GC.Classes[classFile] then
        return
    end
    local selections = self:GetSelections()
    if enabled then
        selections[classFile] = { mode = "CLASS", specs = {} }
    else
        selections[classFile] = nil
    end
    InvalidateAdvertisement()
    GC:FireCallback("RECRUITMENT_UPDATED")
end

function GC.Recruitment:SetSpec(specKey, enabled)
    local spec = GC.SpecByKey[specKey]
    if not spec then
        return
    end

    local selections = self:GetSelections()
    local selection = selections[spec.classFile]
    -- "Ganze Klasse" bedeutet: alle Specs sind gewaehlt (so zaehlt es der
    -- Werbetext, so leuchten die Knoepfe). Klickt jemand dann eine einzelne
    -- Spec an, wird daraus eine ausdrueckliche Liste, die zuerst ALLE Specs
    -- enthaelt - erst danach greift der Klick. Ohne dieses Aufzaehlen begaenne
    -- die Liste leer, und die ganze Klasse fiele unbemerkt auf die eine
    -- geklickte Spec zusammen.
    if selection and selection.mode == "CLASS" then
        local specs = {}
        local classInfo = GC.Classes[spec.classFile]
        if classInfo then
            for _, classSpec in ipairs(classInfo.specs) do
                specs[classSpec.key] = true
            end
        end
        selection = { mode = "SPECS", specs = specs }
    end
    selection = selection or { mode = "SPECS", specs = {} }
    selection.mode = "SPECS"
    selection.specs = selection.specs or {}
    selection.specs[specKey] = enabled == true or nil

    local hasSpecs = false
    for _ in pairs(selection.specs) do
        hasSpecs = true
        break
    end
    selections[spec.classFile] = hasSpecs and selection or nil
    InvalidateAdvertisement()
    GC:FireCallback("RECRUITMENT_UPDATED")
end

function GC.Recruitment:IsClassSelected(classFile)
    local selection = self:GetSelections()[classFile]
    return selection and selection.mode == "CLASS" or false
end

function GC.Recruitment:IsSpecSelected(specKey)
    local spec = GC.SpecByKey[specKey]
    local selection = spec and self:GetSelections()[spec.classFile]
    if not selection then
        return false
    end
    -- "Ganze Klasse" heisst: jede Spec ist gewaehlt. Damit leuchten alle
    -- Spec-Knoepfe, und ein Klick schaltet gezielt einen ab (siehe SetSpec),
    -- statt die ganze Klasse auf die eine geklickte Spec zusammenzuziehen.
    if selection.mode == "CLASS" then
        return true
    end
    return selection.specs and selection.specs[specKey] == true or false
end

function GC.Recruitment:Clear()
    GC.DB:GetGuild().recruitment.selections = {}
    InvalidateAdvertisement()
    GC:FireCallback("RECRUITMENT_UPDATED")
end

local function CountSelectedSpecs(selection, classInfo)
    if not selection then
        return 0
    end
    if selection.mode == "CLASS" then
        return #classInfo.specs
    end

    local count = 0
    for _, spec in ipairs(classInfo.specs) do
        if selection.specs and selection.specs[spec.key] then
            count = count + 1
        end
    end
    return count
end

function GC.Recruitment:IsEveryClassFullySelected()
    local selections = self:GetSelections()
    for _, classFile in ipairs(GC.ClassOrder) do
        local classInfo = GC.Classes[classFile]
        if CountSelectedSpecs(selections[classFile], classInfo) < #classInfo.specs then
            return false
        end
    end
    return true
end

function GC.Recruitment:GetClassSelectionLabel(classFile, compact)
    local classInfo = GC.Classes[classFile]
    local selection = classInfo and self:GetSelections()[classFile]
    if not classInfo or not selection then
        return nil
    end

    local selectedSpecCount = CountSelectedSpecs(selection, classInfo)
    if selectedSpecCount == #classInfo.specs then
        return classInfo.plural
    end
    if selectedSpecCount == 0 then
        return nil
    end

    local labels = {}
    local specNames = {}
    for _, spec in ipairs(classInfo.specs) do
        if selection.specs and selection.specs[spec.key] then
            if compact and selectedSpecCount > 1 then
                specNames[#specNames + 1] = spec.name
            else
                labels[#labels + 1] = spec.recruitLabel
            end
        end
    end
    if #specNames > 0 then
        return classInfo.plural .. " (" .. table.concat(specNames, "/") .. ")"
    end
    return GC.Util.JoinGerman(labels)
end

function GC.Recruitment:GetSelectionLabels(compact)
    local labels = {}
    if self:IsEveryClassFullySelected() then
        return { "alle Klassen" }
    end

    for _, classFile in ipairs(self:GetClassOrder()) do
        local label = self:GetClassSelectionLabel(classFile, compact)
        if label then
            labels[#labels + 1] = label
        end
    end
    return labels
end

function GC.Recruitment:GetRecruitmentPhrase(compact)
    local highPriority = {}
    local normalPriority = {}
    local allClasses = self:IsEveryClassFullySelected()
    local selectedClassCount = 0

    for _, classFile in ipairs(self:GetClassOrder()) do
        local label = self:GetClassSelectionLabel(classFile, compact)
        if label then
            selectedClassCount = selectedClassCount + 1
            if self:IsHighPriority(classFile) then
                highPriority[#highPriority + 1] = label
            else
                normalPriority[#normalPriority + 1] = label
            end
        end
    end

    if allClasses or selectedClassCount >= 7 then
        if #highPriority > 0 then
            return "alle Klassen, besonders " .. GC.Util.JoinGerman(highPriority)
        end
        return "alle Klassen"
    end
    if #highPriority > 0 and #normalPriority > 0 then
        return "dringend " .. GC.Util.JoinGerman(highPriority)
            .. "; außerdem " .. GC.Util.JoinGerman(normalPriority)
    elseif #highPriority > 0 then
        return "dringend " .. GC.Util.JoinGerman(highPriority)
    elseif #normalPriority > 0 then
        return GC.Util.JoinGerman(normalPriority)
    end
    return ""
end

function GC.Recruitment:GetSuggestions()
    local suggestions = {}
    local summary = GC.Roster:GetSummary()
    for _, rule in ipairs(GC.CoverageRules) do
        if not summary.coverageSpecCounts[rule.specKey] then
            suggestions[#suggestions + 1] = {
                specKey = rule.specKey,
                priority = rule.priority,
                reason = rule.reason,
            }
        end
    end
    return suggestions, summary
end

local function AddPart(parts, value)
    value = GC.Util.Trim(value)
    if value ~= "" then
        parts[#parts + 1] = value
    end
end

function GC.Recruitment:GenerateAdvertisement()
    local guildData = GC.DB:GetGuild()
    local info = guildData.profile
    local raidMarker = math.floor(tonumber(guildData.recruitment.raidMarker) or 8)
    raidMarker = math.max(1, math.min(8, raidMarker))
    local markerText = "{rt" .. raidMarker .. "}"
    local guildName = GC:GetGuildName()
    if guildName == "" then
        guildName = "Unsere Gilde"
    else
        guildName = "<" .. guildName .. ">"
    end

    local function BuildBody(recruitmentPhrase, includeDescription, includeRaidTimes)
        local parts = { markerText .. " " .. guildName .. " rekrutiert für den aktuellen Content:" }
        if recruitmentPhrase ~= "" then
            parts[1] = parts[1] .. " " .. recruitmentPhrase .. "!"
        else
            parts[1] = parts[1] .. " engagierte Spieler!"
        end

        if includeDescription then
            AddPart(parts, info.description)
        end
        if includeRaidTimes and GC.Util.Trim(info.raidTimes) ~= "" then
            AddPart(parts, "Raids: " .. info.raidTimes .. ".")
        end
        AddPart(parts, "/w für mehr Infos.")
        return table.concat(parts, " ")
    end

    local detailedPhrase = self:GetRecruitmentPhrase(false)
    local compactPhrase = self:GetRecruitmentPhrase(true)
    local candidates = {
        BuildBody(detailedPhrase, true, true),
        BuildBody(compactPhrase, true, true),
        BuildBody(compactPhrase, false, true),
        BuildBody(compactPhrase, false, false),
    }
    local suffix = " " .. markerText
    for _, body in ipairs(candidates) do
        if #(body .. suffix) <= GC.Constants.MAX_CHAT_BYTES then
            return body .. suffix
        end
    end

    local maximumBodyBytes = GC.Constants.MAX_CHAT_BYTES - #suffix
    return GC.Util.SafeChatText(candidates[#candidates], maximumBodyBytes) .. suffix
end

function GC.Recruitment:DecorateReply(text, markerIndex)
    local cleanText = GC.Util.Trim(text or "")
    cleanText = cleanText:gsub("^%s*{rt[1-8]}%s*", "")
    cleanText = cleanText:gsub("%s*{rt[1-8]}%s*$", "")
    cleanText = GC.Util.Trim(cleanText)
    if cleanText == "" then
        return ""
    end

    markerIndex = math.floor(tonumber(markerIndex) or 0)
    if markerIndex < 1 or markerIndex > 8 then
        return GC.Util.SafeChatText(cleanText)
    end

    local markerText = "{rt" .. markerIndex .. "}"
    local suffix = " " .. markerText
    local maximumBodyBytes = GC.Constants.MAX_CHAT_BYTES - #markerText - #suffix - 1
    local safeBody = GC.Util.SafeChatText(cleanText, maximumBodyBytes)
    return markerText .. " " .. safeBody .. suffix
end

function GC.Recruitment:GenerateReply(kind, playerName)
    local guildData = GC.DB:GetGuild()
    local info = guildData.profile
    local replyMarker = guildData.recruitment.replyMarker
    local shortName = GC.Util.PlayerIdentityName(playerName or "")
    local reply = ""
    local customTemplate = guildData.replyTemplates and guildData.replyTemplates[kind] or ""
    if GC.Util.Trim(customTemplate) ~= "" then
        local replacements = {
            ["{name}"] = shortName,
            ["{gilde}"] = GC:GetGuildName(),
            ["{beschreibung}"] = info.description or "",
            ["{raidzeiten}"] = info.raidTimes or "",
            ["{progress}"] = info.progress or "",
            ["{loot}"] = info.lootSystem or "",
            ["{discord}"] = info.discord or "",
            ["{kontakt}"] = info.contact or "",
        }
        reply = customTemplate
        for token, value in pairs(replacements) do
            reply = reply:gsub(token, function()
                return value
            end)
        end
    elseif kind == "THANKS" then
        reply = "Hallo " .. shortName .. ", danke für dein Interesse an unserer Gilde! Was spielst du, und wonach suchst du?"
    elseif kind == "INFO" then
        local pieces = {}
        AddPart(pieces, info.description)
        if GC.Util.Trim(info.raidTimes) ~= "" then
            AddPart(pieces, "Unsere Raidzeiten: " .. info.raidTimes .. ".")
        end
        if GC.Util.Trim(info.lootSystem) ~= "" then
            AddPart(pieces, "Lootsystem: " .. info.lootSystem .. ".")
        end
        if GC.Util.Trim(info.progress) ~= "" then
            AddPart(pieces, "Progress: " .. info.progress .. ".")
        end
        if #pieces == 0 then
            reply = "Unsere Gildeninfos sind noch nicht hinterlegt. Ich beantworte dir gern alle Fragen."
        else
            reply = table.concat(pieces, " ")
        end
    elseif kind == "DISCORD" then
        if GC.Util.Trim(info.discord) ~= "" then
            reply = "Wenn du magst, treffen wir uns kurz im Discord: " .. info.discord
        else
            reply = "Wenn du magst, können wir uns kurz im Discord kennenlernen. Soll ich dir die Daten schicken?"
        end
    end
    return self:DecorateReply(reply, replyMarker)
end
