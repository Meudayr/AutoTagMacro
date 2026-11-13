local addonName, ATM = ...
ATM = ATM or _G["AutoTagMacro"]
local wipe = ATM.WipeTable
local plain = ATM.PlainValue or function(v)
    return v
end

local ipairs = ipairs
local pairs = pairs
local pcall = pcall
local tonumber = tonumber
local tostring = tostring
local strlen = string.len
local strlower = string.lower
local strmatch = string.match
local tinsert = table.insert
local tconcat = table.concat

local CreateFrame = CreateFrame
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitIsDead = UnitIsDead
local UnitCanAttack = UnitCanAttack
local UnitName = UnitName
local GetMacroIndexByName = GetMacroIndexByName
local GetMacroBody = GetMacroBody
local GetNumMacros = GetNumMacros
local CreateMacro = CreateMacro
local EditMacro = EditMacro

-- WoW Forever (16001 / Midnight 12.x C_Macro) truncates both /macro slots and
-- SecureActionButton macrotext1 at 255 bytes in C++. Every page must be <= 255 bytes.
local MAX_MACRO_CHARS = 255
local TOOLTIP_LINE = "#showtooltip"
local CLEAR_TARGET_LINE = "/cleartarget [dead][noharm]"
local CLEAR_ALL_TARGET_LINE = "/cleartarget"
local FALLBACK_TARGET_LINE = "/targetenemy [noexists]"
local TARGET_EXACT_PREFIX = "/targetexact [noexists] "
local TARGET_SHORT_PREFIX = "/tar [noexists] "
local TARGET_PREFIX_LINE = "/target [noexists] "
local TARGET_SHORT_PREFIX_LINE = "/tar [noexists] "
local STOP_MACRO_LINE = "/stopmacro [dead][noharm]"
local START_ATTACK_COND_LINE = "/startattack [harm,nodead]"
local START_ATTACK_BARE_LINE = "/startattack"

local GENERIC_FIRST_WORDS = {
    ["young"] = true,
    ["elder"] = true,
    ["greater"] = true,
    ["lesser"] = true,
    ["small"] = true,
    ["large"] = true,
    ["giant"] = true,
    ["wild"] = true,
    ["feral"] = true,
    ["ragged"] = true,
    ["mangy"] = true,
    ["cursed"] = true,
    ["wretched"] = true,
    ["mindless"] = true,
    ["enraged"] = true,
    ["diseased"] = true,
    ["corrupted"] = true,
    ["starving"] = true,
    ["rabid"] = true,
}

-- Recycled tables so macro string assembly allocates minimal garbage.
local bodyLines = {}
local footerLines = {}
local secureHeaderLines = {}
local secureFooterLines = {}
local pageLines = {}
local writtenMobs = {}
local secureWrittenMobs = {}
local securePages = {}
local mobToPageIndex = {}
local prefixCounts = {}
local prefixOrder = {}
local overflowPrefixes = {}

ATM.writtenMobs = writtenMobs
ATM.secureWrittenMobs = secureWrittenMobs
ATM.securePages = securePages
ATM.mobToPageIndex = mobToPageIndex
ATM.currentSecurePage = 1
ATM.lastMacroBody = ""
ATM.lastSecureBody = ""
ATM.lastTruncatedCount = 0
ATM.lastOverheadBytes = 0
ATM.lastAvailableTargetBytes = 255

-- Silence non-left mouse buttons on the SecureActionButton so only LeftButton / keybind casts.
local function SilenceOtherButtons(btn)
    for index = 2, 31 do
        if index <= 5 then
            btn:SetAttribute("type" .. index, "none")
        end
        btn:SetAttribute("*type" .. index, "none")
    end
end

-- Create the Smart Multi-Page SecureActionButton at load time (out of combat).
-- Client 16001 requires parent UIParent, RegisterForClicks("AnyDown"), pressAndHoldAction = true,
-- and macrotext1 <= 255 bytes so the C++ buffer never cuts off the /cast line at the bottom.
local secureBtn = CreateFrame("Button", ATM.SECURE_BUTTON_NAME or "AutoTagSecureButton", UIParent, "SecureActionButtonTemplate")
secureBtn:SetFrameStrata("MEDIUM")
secureBtn:SetSize(1, 1)
secureBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
secureBtn:EnableKeyboard(false)
if secureBtn.RegisterForClicks then
    secureBtn:RegisterForClicks("AnyDown")
end
secureBtn:SetAttribute("pressAndHoldAction", true)
secureBtn:SetAttribute("type1", "macro")
secureBtn:SetAttribute("macrotext1", "")
secureBtn:SetAttribute("*type1", "macro")
secureBtn:SetAttribute("*macrotext1", "")
secureBtn:SetAttribute("type", "macro")
secureBtn:SetAttribute("macrotext", "")
SilenceOtherButtons(secureBtn)
ATM.secureButton = secureBtn

local ExtractMobFamilyPrefix
local BuildMacroBodies
local EnsureMacroExists

ExtractMobFamilyPrefix = function(mobName)
    if type(mobName) ~= "string" then
        return nil
    end
    local twoWordCo = strmatch(mobName, "^([%a']+%.?%s+Co%.)%s+.+$")
    if twoWordCo then
        return twoWordCo
    end
    local firstWord = strmatch(mobName, "^([%a']+)%s+.+$")
    if firstWord and strlen(firstWord) >= 5 and not GENERIC_FIRST_WORDS[firstWord:lower()] then
        return firstWord
    end
    return nil
end

function ATM:ArmSecurePage(pageIndex, dropTappedTarget, deadMobNameToSkip)
    if self:IsInCombat() then
        return false
    end
    if not self.secureButton or not self.secureButton.SetAttribute then
        return false
    end
    local totalPages = #securePages
    if totalPages == 0 then
        return false
    end
    local idx = tonumber(pageIndex) or 1
    if idx < 1 or idx > totalPages then
        idx = 1
    end
    self.currentSecurePage = idx
    local pageBody = securePages[idx] or ""

    -- If a dead corpse is currently targeted, strip that specific mob name's /tar line (and its tribe prefix)
    -- from this press's macrotext so /cleartarget [dead][noharm] doesn't immediately re-target the same corpse
    -- at your feet instead of a living mob further away!
    if deadMobNameToSkip and deadMobNameToSkip ~= "" and pageBody ~= "" then
        local lowerDead = strlower(deadMobNameToSkip)
        local deadPrefix = ExtractMobFamilyPrefix and ExtractMobFamilyPrefix(deadMobNameToSkip)
        local lowerDeadPrefix = deadPrefix and strlower(deadPrefix) or nil
        local filtered = {}
        local keptTarCount = 0
        for line in pageBody:gmatch("[^\n]+") do
            local tarTarget = line:match("^/tar%a*%s+%[noexists%]%s+(.+)$")
            if tarTarget then
                local lowerTar = strlower(tarTarget)
                if lowerTar ~= lowerDead and (not lowerDeadPrefix or lowerTar ~= lowerDeadPrefix) then
                    tinsert(filtered, line)
                    keptTarCount = keptTarCount + 1
                end
            else
                tinsert(filtered, line)
            end
        end
        if keptTarCount > 0 then
            pageBody = tconcat(filtered, "\n")
        end
    end

    if dropTappedTarget and pageBody ~= "" then
        -- Replace the conditional /cleartarget [dead][noharm] header with unconditional /cleartarget
        -- (saves 15 chars, so the page stays strictly <= 255 bytes!) so the tapped or non-quest mob is dropped
        -- and the remaining /tar [noexists] lines immediately acquire an active quest mob.
        if pageBody:sub(1, strlen(CLEAR_TARGET_LINE)) == CLEAR_TARGET_LINE then
            pageBody = CLEAR_ALL_TARGET_LINE .. pageBody:sub(strlen(CLEAR_TARGET_LINE) + 1)
        elseif pageBody:sub(1, strlen(CLEAR_ALL_TARGET_LINE)) ~= CLEAR_ALL_TARGET_LINE then
            if (strlen(pageBody) + 13) <= MAX_MACRO_CHARS then
                pageBody = CLEAR_ALL_TARGET_LINE .. "\n" .. pageBody
            else
                -- Drop the last /tar line if needed to make room for /cleartarget\n within 255 bytes.
                local trimmed = pageBody:gsub("\n/tar[^\n]+(\n)", "%1", 1)
                if (strlen(trimmed) + 13) <= MAX_MACRO_CHARS then
                    pageBody = CLEAR_ALL_TARGET_LINE .. "\n" .. trimmed
                else
                    pageBody = CLEAR_ALL_TARGET_LINE
                end
            end
        end
    end
    self.secureButton:SetAttribute("type1", "macro")
    self.secureButton:SetAttribute("macrotext1", pageBody)
    self.secureButton:SetAttribute("*type1", "macro")
    self.secureButton:SetAttribute("*macrotext1", pageBody)
    self.secureButton:SetAttribute("type", "macro")
    self.secureButton:SetAttribute("macrotext", pageBody)
    return true
end

local IsUnitUntappedHostile = function(unit)
    if not UnitExists or not plain(UnitExists(unit)) then
        return false
    end
    if UnitIsDead and plain(UnitIsDead(unit)) then
        return false
    end
    if UnitCanAttack and not plain(UnitCanAttack("player", unit)) then
        return false
    end
    if ATM.IsUnitTapDenied and ATM:IsUnitTapDenied(unit) then
        return false
    end
    return true
end

local FindVisibleQuestMobPage = function()
    -- Check mouseover first (skipping gray-tagged mobs).
    if IsUnitUntappedHostile("mouseover") then
        local moName = UnitName and plain(UnitName("mouseover")) or nil
        if type(moName) == "string" and moName ~= "" then
            local pIdx = mobToPageIndex[strlower(moName)]
            if pIdx then
                return pIdx
            end
        end
    end

    -- Check active nameplate tokens tracked by NAME_PLATE_UNIT_ADDED (skipping gray-tagged mobs).
    if ATM.nameplateUnits then
        for token in pairs(ATM.nameplateUnits) do
            if UnitExists and plain(UnitExists(token)) then
                if IsUnitUntappedHostile(token) then
                    local npName = UnitName and plain(UnitName(token)) or nil
                    if type(npName) == "string" and npName ~= "" then
                        local pIdx = mobToPageIndex[strlower(npName)]
                        if pIdx then
                            return pIdx
                        end
                    end
                end
            else
                ATM.nameplateUnits[token] = nil
            end
        end
    end

    -- Fallback to C_NamePlate.GetNamePlates if available (skipping gray-tagged mobs).
    if _G.C_NamePlate and type(_G.C_NamePlate.GetNamePlates) == "function" then
        local ok, plates = pcall(_G.C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, plate in pairs(plates) do
                local token = plate and plain(plate.namePlateUnitToken) or nil
                if type(token) == "string" and IsUnitUntappedHostile(token) then
                    local npName = UnitName and plain(UnitName(token)) or nil
                    if type(npName) == "string" and npName ~= "" then
                        local pIdx = mobToPageIndex[strlower(npName)]
                        if pIdx then
                            return pIdx
                        end
                    end
                end
            end
        end
    end

    return nil
end

local lastPreClickAt = 0
local lastTriedVisiblePage = nil
local lastPositionRescanAt = 0
local lastScanX = nil
local lastScanY = nil

secureBtn:SetScript("PreClick", function(self, mouseButton, down)
    if down == false then
        return
    end
    if mouseButton and mouseButton ~= "LeftButton" then
        return
    end
    if ATM:IsInCombat() then
        return
    end

    -- Periodically re-score mob proximity if the player has walked to a new camp in the same zone.
    local now = (GetTime and GetTime()) or 0
    if now > 0 and (now - lastPositionRescanAt) >= 4.0 and ATM.GetPlayerCoordinates then
        lastPositionRescanAt = now
        local px, py = ATM:GetPlayerCoordinates()
        if px and py then
            if not lastScanX or not lastScanY then
                lastScanX, lastScanY = px, py
            else
                local dx = px - lastScanX
                local dy = py - lastScanY
                if (dx * dx + dy * dy) >= 9.0 then
                    lastScanX, lastScanY = px, py
                    ATM:ForceUpdate(false)
                end
            end
        end
    end

    local totalPages = #securePages
    if totalPages == 0 then
        return
    end

    -- If the current target is gray-tagged (tapped by another player), arm the next page with
    -- unconditional /cleartarget so this press drops the gray target and scans for an untagged mob
    -- instead of wasting a spell cast on a mob that gives no credit.
    if UnitExists and plain(UnitExists("target")) and ATM.IsUnitTapDenied and ATM:IsUnitTapDenied("target") then
        local visiblePage = FindVisibleQuestMobPage()
        local targetPage = (visiblePage and visiblePage ~= lastTriedVisiblePage) and visiblePage or ((ATM.currentSecurePage % totalPages) + 1)
        lastTriedVisiblePage = visiblePage
        ATM:ArmSecurePage(targetPage, true)
        return
    end

    -- If a living, untagged hostile target is already acquired, verify it is actually one of our
    -- active quest targets before keeping it; otherwise drop it first so we never cast on non-quest mobs.
    if IsUnitUntappedHostile("target") then
        local db = AutoTagMacroDB or ATM.DEFAULT_DB or {}
        local targetName = UnitName and plain(UnitName("target")) or nil
        local isQuestTarget = (#secureWrittenMobs == 0)
            or (ATM.IsActiveMacroTarget and ATM:IsActiveMacroTarget(targetName))

        if db.strictQuestTargetsOnly ~= false and not isQuestTarget then
            local visiblePage = FindVisibleQuestMobPage()
            local targetPage = visiblePage or ((ATM.currentSecurePage % totalPages) + 1)
            lastTriedVisiblePage = visiblePage
            ATM:ArmSecurePage(targetPage, true)
            return
        end

        lastTriedVisiblePage = nil
        ATM:ArmSecurePage(ATM.currentSecurePage or 1, false)
        return
    end

    -- Check if the current target is a dead corpse so we can skip its /tar line on this press
    -- (preventing /cleartarget [dead][noharm] + /tar [noexists] from re-targeting the same dead corpse at your feet).
    local deadTargetName = nil
    if UnitExists and plain(UnitExists("target")) and UnitIsDead and plain(UnitIsDead("target")) then
        deadTargetName = UnitName and plain(UnitName("target")) or nil
    end

    if totalPages <= 1 then
        ATM:ArmSecurePage(1, false, deadTargetName)
        return
    end

    if now > 0 and (now - lastPreClickAt) < 0.05 then
        return
    end
    lastPreClickAt = now

    -- If an untagged tracked quest mob is visible on mouseover or a nameplate AND we haven't
    -- just tried that page without acquiring a target, arm its page once; otherwise keep cycling
    -- through all pages so distant mobs beyond nameplate range (20-100 yards) are always reached!
    local visiblePage = FindVisibleQuestMobPage()
    if visiblePage and visiblePage ~= lastTriedVisiblePage then
        lastTriedVisiblePage = visiblePage
        ATM:ArmSecurePage(visiblePage, false, deadTargetName)
        return
    end

    lastTriedVisiblePage = nil
    local nextPage = (ATM.currentSecurePage % totalPages) + 1
    ATM:ArmSecurePage(nextPage, false, deadTargetName)
end)

BuildMacroBodies = function(mobList)
    wipe(bodyLines)
    wipe(footerLines)
    wipe(secureHeaderLines)
    wipe(secureFooterLines)
    wipe(writtenMobs)
    wipe(secureWrittenMobs)
    wipe(securePages)
    wipe(mobToPageIndex)
    wipe(prefixCounts)
    wipe(prefixOrder)
    wipe(overflowPrefixes)
    ATM.lastTruncatedCount = 0

    local db = AutoTagMacroDB or ATM.DEFAULT_DB or {}
    local showTooltip = db.showTooltip ~= false
    local alwaysClear = db.alwaysClearTarget == true
    local clearDead = alwaysClear or (db.clearDeadTarget ~= false)
    local includeStop = db.includeStopMacro == true
    local useShortTar = db.useShortTar == true
    local fallbackEnemy = db.fallbackTargetEnemy ~= false
    local allowPrefix = db.enablePrefixCompaction ~= false
    local useSpell = db.useSpell ~= false
    local spellName = (type(db.spellName) == "string") and db.spellName:match("^%s*(.-)%s*$") or ATM.DEFAULT_SPELL
    local startAttack = db.startAttack == true
    local raidMarker = tonumber(db.raidMarker) or 0
    local embedMarker = db.embedMarkerInMacro ~= false
    local hasSpell = useSpell and spellName and spellName ~= ""

    local targetCmdPrefix = useShortTar and TARGET_SHORT_PREFIX or TARGET_EXACT_PREFIX
    local prefixCmdPrefix = useShortTar and TARGET_SHORT_PREFIX_LINE or TARGET_PREFIX_LINE
    local effectiveClearLine = alwaysClear and CLEAR_ALL_TARGET_LINE or CLEAR_TARGET_LINE

    if showTooltip then
        tinsert(bodyLines, TOOLTIP_LINE)
    end
    if clearDead then
        tinsert(bodyLines, effectiveClearLine)
        tinsert(secureHeaderLines, effectiveClearLine)
    end

    -- Non-toggling Raid Marker guard: when clearDead is active (and not unconditionally clearing)
    -- and a Raid Marker is set, any press while a living hostile target is ALREADY acquired casts/attacks
    -- immediately and stops BEFORE /tm <N>, preventing Blizzard's /tm from toggling the marker off.
    if clearDead and not alwaysClear and raidMarker >= 1 and raidMarker <= 8 then
        if embedMarker then
            if startAttack then
                tinsert(bodyLines, "/startattack [harm]")
            end
            if hasSpell then
                tinsert(bodyLines, "/cast [harm] " .. spellName)
            end
            tinsert(bodyLines, "/stopmacro [harm]")
        end
        if startAttack then
            tinsert(secureHeaderLines, "/startattack [harm]")
        end
        if hasSpell then
            tinsert(secureHeaderLines, "/cast [harm] " .. spellName)
        end
        tinsert(secureHeaderLines, "/stopmacro [harm]")
    end

    -- Standard 255-char macro footer.
    if includeStop then
        tinsert(footerLines, STOP_MACRO_LINE)
        if raidMarker >= 1 and raidMarker <= 8 and embedMarker then
            tinsert(footerLines, "/tm " .. tostring(raidMarker))
        end
        if startAttack then
            tinsert(footerLines, START_ATTACK_BARE_LINE)
        end
        if hasSpell then
            tinsert(footerLines, "/cast " .. spellName)
        end
    else
        if raidMarker >= 1 and raidMarker <= 8 and embedMarker then
            tinsert(footerLines, "/tm [harm,nodead] " .. tostring(raidMarker))
        end
        if startAttack then
            tinsert(footerLines, START_ATTACK_COND_LINE)
        end
        if hasSpell then
            tinsert(footerLines, "/cast [harm,nodead] " .. spellName)
        end
    end

    -- SecureActionButton 255-char page footer: use compact [harm,nodead] lines when includeStop
    -- is off so each page has 26 extra bytes for mob lines!
    if includeStop then
        tinsert(secureFooterLines, STOP_MACRO_LINE)
        if raidMarker >= 1 and raidMarker <= 8 then
            tinsert(secureFooterLines, "/tm " .. tostring(raidMarker))
        end
        if startAttack then
            tinsert(secureFooterLines, START_ATTACK_BARE_LINE)
        end
        if hasSpell then
            tinsert(secureFooterLines, "/cast " .. spellName)
        end
    else
        if raidMarker >= 1 and raidMarker <= 8 then
            tinsert(secureFooterLines, "/tm [harm,nodead] " .. tostring(raidMarker))
        end
        if startAttack then
            tinsert(secureFooterLines, START_ATTACK_COND_LINE)
        end
        if hasSpell then
            tinsert(secureFooterLines, "/cast [harm,nodead] " .. spellName)
        end
    end

    local headerBlock = tconcat(bodyLines, "\n")
    local footerBlock = tconcat(footerLines, "\n")
    local headerBytes = strlen(headerBlock)
    local footerBytes = strlen(footerBlock)

    local baseLength = headerBytes + (headerBytes > 0 and footerBytes > 0 and 1 or 0) + footerBytes
    ATM.lastOverheadBytes = baseLength
    ATM.lastAvailableTargetBytes = math.max(0, MAX_MACRO_CHARS - baseLength)

    local secureHeaderBlock = tconcat(secureHeaderLines, "\n")
    local secureHeaderBytes = strlen(secureHeaderBlock)
    local secureFooterBlock = tconcat(secureFooterLines, "\n")
    local secureFooterBytes = strlen(secureFooterBlock)
    local secureBaseLength = secureHeaderBytes + (secureHeaderBytes > 0 and secureFooterBytes > 0 and 1 or 0) + secureFooterBytes

    if mobList and #mobList > 0 then
        local totalExactBytes = baseLength
        for i = 1, #mobList do
            local mobName = mobList[i]
            if mobName and mobName ~= "" then
                totalExactBytes = totalExactBytes + strlen(targetCmdPrefix) + strlen(mobName) + 1
                if allowPrefix then
                    local prefix = ExtractMobFamilyPrefix(mobName)
                    if prefix then
                        if not prefixCounts[prefix] then
                            prefixCounts[prefix] = 0
                            tinsert(prefixOrder, prefix)
                        end
                        prefixCounts[prefix] = prefixCounts[prefix] + 1
                    end
                end
            end
        end

        local reservedPrefixBytes = 0
        if allowPrefix and totalExactBytes > MAX_MACRO_CHARS then
            for i = 1, #prefixOrder do
                local prefix = prefixOrder[i]
                if prefixCounts[prefix] >= 3 then
                    local pLineBytes = strlen(prefixCmdPrefix) + strlen(prefix) + 1
                    if (baseLength + reservedPrefixBytes + pLineBytes) <= MAX_MACRO_CHARS then
                        tinsert(overflowPrefixes, prefix)
                        reservedPrefixBytes = reservedPrefixBytes + pLineBytes
                    end
                end
            end
        end

        local currentLength = baseLength + reservedPrefixBytes
        for i = 1, #mobList do
            local mobName = mobList[i]
            if mobName and mobName ~= "" then
                local line = targetCmdPrefix .. mobName
                local addedBytes = strlen(line) + 1
                if (currentLength + addedBytes) <= MAX_MACRO_CHARS then
                    tinsert(bodyLines, line)
                    tinsert(writtenMobs, mobName)
                    currentLength = currentLength + addedBytes
                else
                    ATM.lastTruncatedCount = ATM.lastTruncatedCount + 1
                end
            end
        end

        for i = 1, #overflowPrefixes do
            local prefix = overflowPrefixes[i]
            tinsert(bodyLines, prefixCmdPrefix .. prefix)
            tinsert(writtenMobs, prefix .. "* (prefix)")
        end

        -- Build 255-char pages for AutoTagSecureButton so every single page is <= 255 chars
        -- and prioritizes exact mob names in distance order across pages (without starving Page 1).
        local mobIdx = 1
        local totalMobs = #mobList
        while mobIdx <= totalMobs do
            wipe(pageLines)
            for h = 1, #secureHeaderLines do
                tinsert(pageLines, secureHeaderLines[h])
            end
            local pageLen = secureBaseLength
            local addedOnPage = 0

            while mobIdx <= totalMobs do
                local mobName = mobList[mobIdx]
                if mobName and mobName ~= "" then
                    local line = targetCmdPrefix .. mobName
                    local addedBytes = strlen(line) + 1
                    if (pageLen + addedBytes) <= MAX_MACRO_CHARS then
                        tinsert(pageLines, line)
                        tinsert(secureWrittenMobs, mobName)
                        pageLen = pageLen + addedBytes
                        addedOnPage = addedOnPage + 1
                        local pageNum = #securePages + 1
                        if not mobToPageIndex[strlower(mobName)] then
                            mobToPageIndex[strlower(mobName)] = pageNum
                        end
                        mobIdx = mobIdx + 1
                    else
                        break
                    end
                else
                    mobIdx = mobIdx + 1
                end
            end

            -- Append any tribe prefix lines that fit in the remaining bytes of this 255-char page.
            for p = 1, #overflowPrefixes do
                local pLine = prefixCmdPrefix .. overflowPrefixes[p]
                local pBytes = strlen(pLine) + 1
                if (pageLen + pBytes) <= MAX_MACRO_CHARS then
                    tinsert(pageLines, pLine)
                    pageLen = pageLen + pBytes
                end
            end

            -- Guarantee forward progress if a single mob name is unusually long.
            if addedOnPage == 0 and mobIdx <= totalMobs then
                mobIdx = mobIdx + 1
            end

            for f = 1, #secureFooterLines do
                tinsert(pageLines, secureFooterLines[f])
            end

            local pageStr = tconcat(pageLines, "\n")
            if strlen(pageStr) <= MAX_MACRO_CHARS then
                tinsert(securePages, pageStr)
            end
        end
    end

    if #writtenMobs == 0 and fallbackEnemy then
        local addedBytes = strlen(FALLBACK_TARGET_LINE) + 1
        if (baseLength + addedBytes) <= MAX_MACRO_CHARS then
            tinsert(bodyLines, FALLBACK_TARGET_LINE)
        end
    end

    if #securePages == 0 then
        wipe(pageLines)
        for h = 1, #secureHeaderLines do
            tinsert(pageLines, secureHeaderLines[h])
        end
        if fallbackEnemy and (secureBaseLength + strlen(FALLBACK_TARGET_LINE) + 1) <= MAX_MACRO_CHARS then
            tinsert(pageLines, FALLBACK_TARGET_LINE)
        end
        for f = 1, #secureFooterLines do
            tinsert(pageLines, secureFooterLines[f])
        end
        tinsert(securePages, tconcat(pageLines, "\n"))
    end

    for i = 1, #footerLines do
        tinsert(bodyLines, footerLines[i])
    end

    local finalBody = tconcat(bodyLines, "\n")
    ATM.lastMacroBody = finalBody

    if #securePages == 1 then
        ATM.lastSecureBody = securePages[1]
    else
        local previewParts = {}
        for p = 1, #securePages do
            tinsert(previewParts, "-- Page " .. tostring(p) .. "/" .. tostring(#securePages) .. " (" .. tostring(strlen(securePages[p])) .. "/255 chars) --\n" .. securePages[p])
        end
        ATM.lastSecureBody = tconcat(previewParts, "\n\n")
    end

    return finalBody, securePages[1], #writtenMobs
end

EnsureMacroExists = function(initialBody)
    if not GetMacroIndexByName then
        return 0
    end

    local macroIndex = GetMacroIndexByName(ATM.MACRO_NAME)
    if macroIndex and macroIndex > 0 then
        return macroIndex
    end

    if not CreateMacro or not GetNumMacros then
        return 0
    end

    local numGlobal, numPerChar = GetNumMacros()
    local maxGlobal = _G.MAX_ACCOUNT_MACROS or 120
    local maxChar = _G.MAX_CHARACTER_MACROS or 18
    local preferPerChar = AutoTagMacroDB and AutoTagMacroDB.perCharacter

    local usePerChar = false
    if preferPerChar and (numPerChar or 0) < maxChar then
        usePerChar = true
    elseif (numGlobal or 0) >= maxGlobal and (numPerChar or 0) < maxChar then
        usePerChar = true
    elseif (numGlobal or 0) >= maxGlobal and (numPerChar or 0) >= maxChar then
        ATM:Print("Cannot create '" .. ATM.MACRO_NAME .. "' macro: all macro slots are full.")
        return 0
    end

    local ok, createdIndex = pcall(CreateMacro, ATM.MACRO_NAME, "INV_Misc_QuestionMark", initialBody, usePerChar)
    if not ok or not createdIndex or createdIndex == 0 then
        ok, createdIndex = pcall(CreateMacro, ATM.MACRO_NAME, 1, initialBody, usePerChar)
    end

    if ok and createdIndex and createdIndex > 0 then
        ATM:Print("Created macro '" .. ATM.MACRO_NAME .. "'. Drag it to your action bar.")
        return createdIndex
    end

    return GetMacroIndexByName(ATM.MACRO_NAME) or 0
end

function ATM:SyncMacro(mobList, forceCreate)
    if self:IsInCombat() then
        self.pendingCombatUpdate = true
        if forceCreate then
            self.pendingForceCreate = true
        end
        return false, 0
    end

    local body, _, mobCount = BuildMacroBodies(mobList)

    -- Always arm Page 1 (<= 255 chars, ending with /cast <Spell>) out of combat.
    self:ArmSecurePage(1)

    if not GetMacroIndexByName then
        return false, mobCount
    end

    local macroIndex = GetMacroIndexByName(self.MACRO_NAME)
    if (not macroIndex or macroIndex == 0) then
        macroIndex = EnsureMacroExists(body)
        if not macroIndex or macroIndex == 0 then
            return false, mobCount
        end
    end

    local currentBody = GetMacroBody and GetMacroBody(macroIndex) or nil
    if currentBody == body then
        self:Debug("Macro '" .. self.MACRO_NAME .. "' is already up to date (" .. tostring(strlen(body)) .. "/255 chars, " .. tostring(#securePages) .. " keybind page(s)).")
        return true, mobCount
    end

    if EditMacro then
        local ok = pcall(EditMacro, macroIndex, self.MACRO_NAME, nil, body, 1)
        if not ok then
            pcall(EditMacro, macroIndex, self.MACRO_NAME, "INV_Misc_QuestionMark", body, 1)
        end
    end

    if self.lastTruncatedCount > 0 then
        self:Debug("Compacted " .. tostring(self.lastTruncatedCount) .. " overflow mob(s) in 255-char macro (all " .. tostring(#secureWrittenMobs) .. " exact mobs fit across " .. tostring(#securePages) .. " <=255-char keybind page(s)).")
    end

    self:Debug("Updated macro '" .. self.MACRO_NAME .. "' (" .. tostring(strlen(body)) .. "/255 chars, " .. tostring(mobCount) .. " target line(s)).")
    return true, mobCount
end

function ATM:PrintStatus()
    local zone, subZone = self:GetCurrentZoneInfo()
    local macroIndex = GetMacroIndexByName and GetMacroIndexByName(self.MACRO_NAME) or 0
    local bodyLen = strlen(self.lastMacroBody or "")
    local page1Len = strlen((securePages and securePages[1]) or "")
    local db = AutoTagMacroDB or self.DEFAULT_DB or {}
    local extKey = self:GetExtendedKeybind()

    self:Print("Zone: " .. (zone ~= "" and zone or "Unknown") .. (subZone ~= "" and (" (" .. subZone .. ")") or ""))
    self:Print("255-Char Action Bar Macro: " .. (macroIndex > 0 and ("Slot #" .. tostring(macroIndex)) or "Not created") .. " (" .. tostring(bodyLen) .. "/255 chars, " .. tostring(self.lastAvailableTargetBytes) .. " bytes for mobs)")
    self:Print("Direct Keybind: " .. (extKey and ("[" .. extKey .. "]") or "Not bound (set in /at)") .. " (" .. tostring(#secureWrittenMobs) .. " exact mobs across " .. tostring(#securePages) .. " page(s), Page 1: " .. tostring(page1Len) .. "/255 chars)")
    self:Print("Tagging Spell: " .. ((db.useSpell ~= false and db.spellName ~= "") and db.spellName or "Disabled (Target Only)") .. " | Raid Marker: " .. tostring(db.raidMarker or 0) .. " (0 macro chars)")

    if self.pendingCombatUpdate then
        self:Print("Combat Queue: Update pending combat exit.")
    end

    if #writtenMobs == 0 then
        self:Print("Active Targets: None (using fallback /targetenemy [noexists])")
    else
        self:Print("255-Macro Targets (" .. tostring(#writtenMobs) .. "): " .. tconcat(writtenMobs, ", "))
    end
end
