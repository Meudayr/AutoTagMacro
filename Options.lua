local addonName, ATM = ...
ATM = ATM or _G["AutoTagMacro"]

local ipairs = ipairs
local pairs = pairs
local pcall = pcall
local tonumber = tonumber
local tostring = tostring
local strlen = string.len
local CreateFrame = CreateFrame
local PickupMacro = PickupMacro
local ClearCursor = ClearCursor
local GetCursorInfo = GetCursorInfo
local GetSpellInfo = GetSpellInfo
local IsShiftKeyDown = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsAltKeyDown = IsAltKeyDown
local UnitExists = _G.UnitExists
local UnitName = _G.UnitName

local SyncOptions
local FitScrollContent

local optionsCanvas = nil
local optionsCategory = nil
local syncing = false
local isBindingKey = false
local previewExtendedMode = false
local widgets = {}
local markerButtons = {}
local recentSpellButtons = {}
local mobChipButtons = {}
local MAX_RECENT_SPELL_BUTTONS = 5
local MAX_MOB_CHIP_BUTTONS = 18

local RAID_MARKERS = {
    { index = 0, name = "None", icon = nil },
    { index = 1, name = "Star", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" },
    { index = 2, name = "Circle", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2" },
    { index = 3, name = "Diamond", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3" },
    { index = 4, name = "Triangle", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4" },
    { index = 5, name = "Moon", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5" },
    { index = 6, name = "Square", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6" },
    { index = 7, name = "Cross", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7" },
    { index = 8, name = "Skull", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
}

SyncOptions = function()
    if not optionsCanvas or not AutoTagMacroDB then
        return
    end
    syncing = true
    local db = AutoTagMacroDB

    if widgets.useSpell then
        widgets.useSpell:SetChecked(db.useSpell ~= false)
    end
    if widgets.startAttack then widgets.startAttack:SetChecked(db.startAttack == true) end
    if widgets.showTooltip then widgets.showTooltip:SetChecked(db.showTooltip ~= false) end
    if widgets.clearDeadTarget then widgets.clearDeadTarget:SetChecked(db.clearDeadTarget ~= false) end
    if widgets.strictQuestTargetsOnly then widgets.strictQuestTargetsOnly:SetChecked(db.strictQuestTargetsOnly ~= false) end
    if widgets.alwaysClearTarget then widgets.alwaysClearTarget:SetChecked(db.alwaysClearTarget == true) end
    if widgets.useShortTar then widgets.useShortTar:SetChecked(db.useShortTar == true) end
    if widgets.fallbackTargetEnemy then widgets.fallbackTargetEnemy:SetChecked(db.fallbackTargetEnemy ~= false) end
    if widgets.enablePrefixCompaction then widgets.enablePrefixCompaction:SetChecked(db.enablePrefixCompaction ~= false) end
    if widgets.includeOtherZoneQuests then widgets.includeOtherZoneQuests:SetChecked(db.includeOtherZoneQuests ~= false) end
    if widgets.soundOnAcquire then widgets.soundOnAcquire:SetChecked(db.soundOnAcquire == true) end
    if widgets.debug then widgets.debug:SetChecked(db.debug == true) end

    local boundKey = ATM:GetExtendedKeybind()
    local hasBoundKey = boundKey and boundKey ~= ""

    if widgets.keybindBtn and not isBindingKey then
        if hasBoundKey then
            widgets.keybindBtn:SetText("Extended Key: |cff44ee66" .. boundKey .. "|r")
        else
            widgets.keybindBtn:SetText("Bind 1023-Char Extended Key")
        end
    end

    if widgets.spellNameBox and not widgets.spellNameBox:HasFocus() then
        widgets.spellNameBox:SetText(tostring(db.spellName or ATM.DEFAULT_SPELL))
        widgets.spellNameBox:SetCursorPosition(0)
    end

    local recent = type(db.recentSpells) == "table" and db.recentSpells or {}
    for i = 1, MAX_RECENT_SPELL_BUTTONS do
        local btn = recentSpellButtons[i]
        local spellName = recent[i]
        if btn then
            if spellName and spellName ~= "" then
                btn.spellName = spellName
                btn:SetText(spellName)
                local textWidth = (btn.GetFontString and btn:GetFontString() and btn:GetFontString():GetStringWidth()) or (strlen(spellName) * 7)
                local width = math.max(84, math.min(126, math.floor(textWidth + 22)))
                btn:SetWidth(width)
                btn:Show()
            else
                btn.spellName = nil
                btn:Hide()
            end
        end
    end

    local currentMarker = tonumber(db.raidMarker) or 0
    for idx, btn in pairs(markerButtons) do
        if btn.selectedBorder then
            if idx == currentMarker then
                btn.selectedBorder:Show()
            else
                btn.selectedBorder:Hide()
            end
        end
    end

    if widgets.markerStatusText then
        local markerInfo = RAID_MARKERS[currentMarker + 1] or RAID_MARKERS[1]
        widgets.markerStatusText:SetText("Selected: |cffffd100" .. markerInfo.name .. "|r")
    end

    local macroBody = ATM.lastMacroBody or ""
    local macroUsed = strlen(macroBody)
    local macroLeft = math.max(0, 255 - macroUsed)
    local macroCount = ATM.writtenMobs and #ATM.writtenMobs or 0
    local macroColor = macroLeft < 15 and "|cffffaa00" or "|cff44ee66"

    local secureBody = ATM.lastSecureBody or ""
    local page1Body = (ATM.securePages and ATM.securePages[1]) or ""
    local page1Used = strlen(page1Body)
    local page1Left = math.max(0, 255 - page1Used)
    local pageCount = (ATM.securePages and #ATM.securePages) or 1
    local secureCount = ATM.secureWrittenMobs and #ATM.secureWrittenMobs or 0
    local keyLabel = hasBoundKey and ("[" .. boundKey .. "]") or "[Not Bound]"

    if widgets.macroMeterLine then
        widgets.macroMeterLine:SetText(string.format(
            "255-Char Macro:  %s%d / 255 used|r  (|cff00ccff%d chars left|r  |  %d target lines)",
            macroColor, macroUsed, macroLeft, macroCount
        ))
    end

    if widgets.extendedMeterLine then
        widgets.extendedMeterLine:SetText(string.format(
            "Direct Keybind %s:  |cff44ee66%d / 255 on Page 1|r  (|cff44ee66%d chars left|r  |  %d page(s), %d exact mobs)",
            keyLabel, page1Used, page1Left, pageCount, secureCount
        ))
    end

    if widgets.previewToggleBtn then
        if previewExtendedMode then
            widgets.previewToggleBtn:SetText("Showing: Keybind Pages (" .. tostring(pageCount) .. ")")
        else
            widgets.previewToggleBtn:SetText("Showing: 255-Char Macro")
        end
    end

    if widgets.macroPreviewText and widgets.previewBg then
        local activeBody = previewExtendedMode and secureBody or macroBody
        widgets.macroPreviewText:SetText(activeBody ~= "" and activeBody or "(Macro not built yet - click Force Rescan & Sync)")
        local textHeight = widgets.macroPreviewText:GetStringHeight() or 100
        widgets.previewBg:SetHeight(math.max(110, textHeight + 22))
    end

    if widgets.exclusionZoneText and widgets.mobChipContainer then
        local zoneName = (ATM.GetCurrentZoneInfo and ATM:GetCurrentZoneInfo()) or "Current Area"
        local excludedCount = (ATM.tempExcludedOrder and #ATM.tempExcludedOrder) or 0
        widgets.exclusionZoneText:SetText(string.format(
            "Area: |cffffd100%s|r  (%d excluded - resets automatically when you leave this zone)",
            zoneName ~= "" and zoneName or "Unknown",
            excludedCount
        ))
        if widgets.clearExclusionsBtn then
            if excludedCount > 0 then
                widgets.clearExclusionsBtn:Enable()
            else
                widgets.clearExclusionsBtn:Disable()
            end
        end

        local chipList = {}
        local seenChip = {}
        if ATM.allAreaMobs then
            for i = 1, #ATM.allAreaMobs do
                local m = ATM.allAreaMobs[i]
                if m and m ~= "" then
                    local k = string.lower(m)
                    if not seenChip[k] then
                        seenChip[k] = true
                        table.insert(chipList, m)
                    end
                end
            end
        end
        if ATM.tempExcludedOrder then
            for i = 1, #ATM.tempExcludedOrder do
                local m = ATM.tempExcludedOrder[i]
                if m and m ~= "" then
                    local k = string.lower(m)
                    if not seenChip[k] then
                        seenChip[k] = true
                        table.insert(chipList, m)
                    end
                end
            end
        end

        local curX = 0
        local curY = 0
        local maxRowWidth = 515
        local rowHeight = 24
        local shownAny = false

        for i = 1, MAX_MOB_CHIP_BUTTONS do
            local btn = mobChipButtons[i]
            local mobName = chipList[i]
            if btn then
                if mobName then
                    shownAny = true
                    local isEx = ATM.IsMobTemporarilyExcluded and ATM:IsMobTemporarilyExcluded(mobName)
                    btn.mobName = mobName
                    if isEx then
                        btn:SetText("|cffff5555[X] " .. mobName .. "|r")
                    else
                        btn:SetText("|cff44ee66" .. mobName .. "|r")
                    end
                    local fs = btn.GetFontString and btn:GetFontString()
                    local tw = (fs and fs:GetStringWidth()) or (strlen(mobName) * 7 + 20)
                    local bw = math.max(95, math.min(250, math.floor(tw + 20)))
                    btn:SetWidth(bw)
                    if curX > 0 and (curX + bw) > maxRowWidth then
                        curX = 0
                        curY = curY - (rowHeight + 4)
                    end
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", widgets.mobChipContainer, "TOPLEFT", curX, curY)
                    btn:Show()
                    curX = curX + bw + 6
                else
                    btn.mobName = nil
                    btn:Hide()
                end
            end
        end

        if widgets.noAreaMobsLabel then
            if shownAny then
                widgets.noAreaMobsLabel:Hide()
                widgets.mobChipContainer:SetHeight(math.abs(curY) + rowHeight + 4)
            else
                widgets.noAreaMobsLabel:Show()
                widgets.mobChipContainer:SetHeight(24)
            end
        end
    end

    syncing = false
    if FitScrollContent then
        FitScrollContent()
    end
end
ATM.SyncOptions = SyncOptions

function ATM:RegisterOptions()
    if optionsCanvas then
        return
    end
    if self.InitializeDB then
        self.InitializeDB()
    end

    local canvas = CreateFrame("Frame", "AutoTagMacroOptionsCanvas")
    canvas.name = "AutoTagMacro"

    local scroll = CreateFrame("ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)

    local panel = CreateFrame("Frame", nil, scroll)
    panel:SetSize(560, 900)
    scroll:SetScrollChild(panel)

    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\Spell_Nature_FaerieFire")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -2)
    title:SetText("AutoTagMacro")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetWidth(510)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("AutoTag keeps an action bar macro and direct keybind synchronized with hostile quest mobs in your current zone.")

    local syncBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    syncBtn:SetSize(148, 26)
    syncBtn:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -16)
    syncBtn:SetText("Force Rescan & Sync")
    syncBtn:SetScript("OnClick", function()
        ATM:ForceUpdate(true)
        SyncOptions()
    end)

    local pickupBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    pickupBtn:SetSize(158, 26)
    pickupBtn:SetPoint("LEFT", syncBtn, "RIGHT", 6, 0)
    pickupBtn:SetText("Pickup Action Bar Macro")
    pickupBtn:SetScript("OnClick", function()
        if ATM:IsInCombat() then
            ATM:Print("Cannot pick up macro during combat.")
            return
        end
        ATM:ForceUpdate(true)
        if PickupMacro then
            pcall(PickupMacro, ATM.MACRO_NAME)
        end
    end)

    -- Extended Mode Keybind Button
    local keybindBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    keybindBtn:SetSize(195, 26)
    keybindBtn:SetPoint("LEFT", pickupBtn, "RIGHT", 6, 0)
    keybindBtn:RegisterForClicks("AnyUp")
    keybindBtn:EnableKeyboard(false)
    keybindBtn:EnableMouseWheel(false)
    widgets.keybindBtn = keybindBtn

    local function StopKeybindCapture()
        isBindingKey = false
        keybindBtn:SetScript("OnKeyDown", nil)
        keybindBtn:SetScript("OnMouseWheel", nil)
        keybindBtn:EnableKeyboard(false)
        keybindBtn:EnableMouseWheel(false)
        SyncOptions()
    end

    local function ApplyCapturedKey(key)
        if not key or key == "" then
            return
        end
        if key == "UNKNOWN" or key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then
            return
        end
        if key == "ESCAPE" then
            StopKeybindCapture()
            return
        end
        local mod = ""
        if IsAltKeyDown and IsAltKeyDown() then mod = mod .. "ALT-" end
        if IsControlKeyDown and IsControlKeyDown() then mod = mod .. "CTRL-" end
        if IsShiftKeyDown and IsShiftKeyDown() then mod = mod .. "SHIFT-" end
        local fullKey = mod .. key
        ATM:SetExtendedKeybind(fullKey)
        ATM:Print("Bound Direct Keybind to: " .. fullKey)
        StopKeybindCapture()
    end

    local function StartKeybindCapture()
        isBindingKey = true
        keybindBtn:SetText("|cffffd100Press Key (R-Click Unbind)|r")
        keybindBtn:EnableKeyboard(true)
        keybindBtn:EnableMouseWheel(true)
        keybindBtn:SetScript("OnKeyDown", function(self, key)
            if isBindingKey then
                ApplyCapturedKey(key)
            end
        end)
        keybindBtn:SetScript("OnMouseWheel", function(self, delta)
            if isBindingKey then
                ApplyCapturedKey(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
            end
        end)
    end

    keybindBtn:SetScript("OnClick", function(self, button)
        if ATM:IsInCombat() then
            ATM:Print("Cannot change keybindings during combat.")
            return
        end
        if isBindingKey then
            if button == "RightButton" then
                ATM:SetExtendedKeybind(nil)
                ATM:Print("Unbound Direct Keybind.")
                StopKeybindCapture()
                return
            elseif button ~= "LeftButton" then
                local btnMap = {
                    MiddleButton = "BUTTON3",
                    Button4 = "BUTTON4",
                    Button5 = "BUTTON5",
                }
                if btnMap[button] then
                    ApplyCapturedKey(btnMap[button])
                end
                return
            end
        end
        StartKeybindCapture()
    end)
    keybindBtn:SetScript("OnHide", function()
        if isBindingKey then
            StopKeybindCapture()
        end
    end)
    keybindBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Direct Keybind (Bypasses 255-Character Limit)", 0.27, 0.93, 0.4)
        GameTooltip:AddLine("Standard WoW action bar macros are limited to 255 characters by the game.", 1, 1, 1, true)
        GameTooltip:AddLine("Binding a direct key here links straight to AutoTag's secure button, cycling through all active quest mobs in your zone without character limit cutoffs.", 1, 0.82, 0, true)
        GameTooltip:AddLine("Left-Click to bind a key. While listening, Right-Click to unbind or press Escape to cancel.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    keybindBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Section 1: Tagging Action & Spell
    local spellHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    spellHeader:SetPoint("TOPLEFT", syncBtn, "BOTTOMLEFT", 0, -20)
    spellHeader:SetText("Combat Action on Target")

    local function MakeCheck(label, desc, key, anchor, offsetY)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY or -4)
        cb.text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        cb.text:SetWidth(490)
        cb.text:SetJustifyH("LEFT")
        cb.text:SetWordWrap(false)
        cb.text:SetText(label)

        cb:SetScript("OnClick", function(self)
            if syncing or not AutoTagMacroDB then
                return
            end
            AutoTagMacroDB[key] = self:GetChecked() and true or false
            ATM:ForceUpdate(false)
            SyncOptions()
        end)
        if desc then
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(label, 1, 0.82, 0)
                GameTooltip:AddLine(desc, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end
        widgets[key] = cb
        return cb
    end

    local cbUseSpell = MakeCheck(
        "Cast spell upon acquiring target",
        "Appends '/cast [harm,nodead] <SpellName>' to the macro so acquiring a quest target immediately tags it.",
        "useSpell",
        spellHeader,
        -6
    )

    local spellLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    spellLabel:SetPoint("TOPLEFT", cbUseSpell, "BOTTOMLEFT", 26, -6)
    spellLabel:SetText("Spell:")

    local spellBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    spellBox:SetSize(185, 22)
    spellBox:SetPoint("LEFT", spellLabel, "RIGHT", 10, 0)
    spellBox:SetAutoFocus(false)
    spellBox:SetMaxLetters(64)

    local function ApplySpellBoxValue(box)
        if not AutoTagMacroDB then
            return
        end
        local text = (box:GetText() or ""):match("^%s*(.-)%s*$")
        if text == "" then
            AutoTagMacroDB.useSpell = false
        else
            AutoTagMacroDB.useSpell = true
            AutoTagMacroDB.spellName = text
            ATM:RecordRecentSpell(text)
        end
        ATM:ForceUpdate(false)
        SyncOptions()
    end

    spellBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        SyncOptions()
    end)
    spellBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        ApplySpellBoxValue(self)
    end)
    spellBox:SetScript("OnEditFocusLost", function(self)
        if not syncing and AutoTagMacroDB then
            local text = (self:GetText() or ""):match("^%s*(.-)%s*$")
            if text ~= "" and text ~= AutoTagMacroDB.spellName then
                ApplySpellBoxValue(self)
            end
        end
    end)
    spellBox:SetScript("OnReceiveDrag", function(self)
        if not GetCursorInfo then
            return
        end
        local infoType, id, bookType, spellId = GetCursorInfo()
        local draggedName = nil
        if infoType == "spell" then
            if spellId and GetSpellInfo then
                draggedName = GetSpellInfo(spellId)
            elseif id and bookType and GetSpellBookItemName then
                draggedName = GetSpellBookItemName(id, bookType)
            elseif id and GetSpellInfo then
                draggedName = GetSpellInfo(id)
            end
        end
        if draggedName and draggedName ~= "" then
            ClearCursor()
            self:SetText(draggedName)
            ApplySpellBoxValue(self)
        end
    end)
    widgets.spellNameBox = spellBox

    local applySpellBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    applySpellBtn:SetSize(72, 22)
    applySpellBtn:SetPoint("LEFT", spellBox, "RIGHT", 6, 0)
    applySpellBtn:SetText("Apply")
    applySpellBtn:SetScript("OnClick", function()
        spellBox:ClearFocus()
        ApplySpellBoxValue(spellBox)
    end)

    local recentLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    recentLabel:SetPoint("TOPLEFT", spellLabel, "BOTTOMLEFT", 0, -10)
    recentLabel:SetText("Recent:")

    local prevRecentBtn = nil
    for i = 1, MAX_RECENT_SPELL_BUTTONS do
        local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btn:SetSize(92, 20)
        if i == 1 then
            btn:SetPoint("LEFT", recentLabel, "RIGHT", 8, 0)
        else
            btn:SetPoint("LEFT", prevRecentBtn, "RIGHT", 4, 0)
        end
        btn:SetScript("OnClick", function(self)
            if not AutoTagMacroDB or not self.spellName then
                return
            end
            AutoTagMacroDB.useSpell = true
            AutoTagMacroDB.spellName = self.spellName
            ATM:RecordRecentSpell(self.spellName)
            ATM:ForceUpdate(false)
            SyncOptions()
        end)
        btn:SetScript("OnEnter", function(self)
            if self.spellName then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(self.spellName, 1, 0.82, 0)
                GameTooltip:AddLine("Click to set as active tagging spell.", 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        recentSpellButtons[i] = btn
        prevRecentBtn = btn
    end

    local cbStartAttack = MakeCheck(
        "Auto-attack target immediately (/startattack)",
        "Begins melee/ranged auto-attacks as soon as a target is selected.",
        "startAttack",
        recentLabel,
        -10
    )

    -- Section 2: Raid Target Marker
    local markerHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    markerHeader:SetPoint("TOPLEFT", cbStartAttack, "BOTTOMLEFT", 0, -18)
    markerHeader:SetText("Raid Target Marker")

    local markerStatus = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    markerStatus:SetPoint("LEFT", markerHeader, "RIGHT", 14, 0)
    widgets.markerStatusText = markerStatus

    local markerDesc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    markerDesc:SetPoint("TOPLEFT", markerHeader, "BOTTOMLEFT", 0, -4)
    markerDesc:SetText("Mark newly acquired quest targets automatically:")

    local prevMarkerBtn = nil
    for _, mInfo in ipairs(RAID_MARKERS) do
        local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btn:SetSize(mInfo.index == 0 and 58 or 36, 32)
        if not prevMarkerBtn then
            btn:SetPoint("TOPLEFT", markerDesc, "BOTTOMLEFT", 0, -6)
        else
            btn:SetPoint("LEFT", prevMarkerBtn, "RIGHT", 5, 0)
        end

        if mInfo.icon then
            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetTexture(mInfo.icon)
            tex:SetSize(18, 18)
            tex:SetPoint("CENTER", 0, 0)
        else
            btn:SetText("None")
        end

        local sel = btn:CreateTexture(nil, "OVERLAY")
        sel:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        sel:SetBlendMode("ADD")
        sel:SetAllPoints(btn)
        sel:Hide()
        btn.selectedBorder = sel

        btn:SetScript("OnClick", function()
            if not AutoTagMacroDB then
                return
            end
            AutoTagMacroDB.raidMarker = mInfo.index
            ATM:ForceUpdate(false)
            SyncOptions()
        end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Raid Marker: " .. mInfo.name, 1, 0.82, 0)
            GameTooltip:AddLine("Marks new quest targets with /tm on target acquisition without toggling off when spamming.", 0.27, 0.93, 0.4, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        markerButtons[mInfo.index] = btn
        prevMarkerBtn = btn
    end

    -- Section 3: Targeting Rules & Macro Optimizations
    local tweaksHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    tweaksHeader:SetPoint("TOPLEFT", markerButtons[0], "BOTTOMLEFT", 0, -18)
    tweaksHeader:SetText("Targeting Rules & Macro Optimizations")

    local cbClearDead = MakeCheck(
        "Drop dead or friendly targets first (/cleartarget [dead][noharm])",
        "Clears dead corpses or friendly players before scanning, ensuring you always target a living hostile quest mob.",
        "clearDeadTarget",
        tweaksHeader,
        -6
    )

    local cbStrictQuest = MakeCheck(
        "Drop non-quest targets before casting (Direct Keybind, out of combat)",
        "If you already have an unrelated mob or excluded target selected, pressing the Direct Keybind drops it first and scans for an active quest mob instead of casting your tagging spell on the non-quest target.",
        "strictQuestTargetsOnly",
        cbClearDead,
        -2
    )

    local cbAlwaysClear = MakeCheck(
        "Always clear existing target first (/cleartarget)",
        "Unconditionally clears any current target at the start of the macro (works in combat and on the 255-char action bar macro too). Note: spamming the same mob may toggle Raid Markers.",
        "alwaysClearTarget",
        cbStrictQuest,
        -2
    )

    local cbShortTar = MakeCheck(
        "Use compact targeting command (/tar instead of /targetexact)",
        "Uses '/tar' instead of '/targetexact' in the 255-character macro. Saves 8 characters per mob, fitting more quest targets into the macro.",
        "useShortTar",
        cbAlwaysClear,
        -2
    )

    local cbPrefixCompact = MakeCheck(
        "Group 3+ related quest mobs by tribe prefix (e.g., Bloodscalp*)",
        "When a quest has many mob variants that exceed macro space, targets closest types individually and appends a prefix line to catch the rest.",
        "enablePrefixCompaction",
        cbShortTar,
        -2
    )

    local cbFallbackEnemy = MakeCheck(
        "Target nearest enemy when no quest targets are in the zone",
        "Falls back to '/targetenemy [noexists]' only when there are zero active quest objectives in your current zone.",
        "fallbackTargetEnemy",
        cbPrefixCompact,
        -2
    )

    local cbOtherZones = MakeCheck(
        "Include active quest mobs from other zones if space remains",
        "Appends quest objectives from neighboring zones when current zone mobs leave empty room in the macro.",
        "includeOtherZoneQuests",
        cbFallbackEnemy,
        -2
    )

    local cbShowTooltip = MakeCheck(
        "Show spell tooltip and icon on action bar (#showtooltip)",
        "Displays your tagging spell icon on the action bar button. Disable if you prefer a custom macro icon or need 13 extra characters for mob names.",
        "showTooltip",
        cbOtherZones,
        -2
    )

    local cbSound = MakeCheck(
        "Play sound alert when acquiring a quest target",
        "Plays an audio chime whenever you target an active, living quest mob.",
        "soundOnAcquire",
        cbShowTooltip,
        -2
    )

    local cbDebug = MakeCheck(
        "Enable debug messages in chat",
        "Shows internal scanning counts and macro character measurements in your chat window.",
        "debug",
        cbSound,
        -2
    )

    -- Section 4: Temporary Area Mob Exclusions
    local excludeHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    excludeHeader:SetPoint("TOPLEFT", cbDebug, "BOTTOMLEFT", 0, -18)
    excludeHeader:SetText("Temporary Area Mob Exclusions")

    local excludeTargetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    excludeTargetBtn:SetSize(165, 22)
    excludeTargetBtn:SetPoint("LEFT", excludeHeader, "RIGHT", 12, 0)
    excludeTargetBtn:SetText("Exclude Current Target")
    excludeTargetBtn:SetScript("OnClick", function()
        local plain = ATM.PlainValue or function(v) return v end
        if not UnitExists or not plain(UnitExists("target")) then
            ATM:Print("No target selected. Target an NPC or click a mob button below.")
            return
        end
        local tName = UnitName and plain(UnitName("target")) or nil
        if not tName or tName == "" then
            return
        end
        ATM:ToggleMobTemporaryExclusion(tName)
    end)

    local clearExclusionsBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clearExclusionsBtn:SetSize(115, 22)
    clearExclusionsBtn:SetPoint("LEFT", excludeTargetBtn, "RIGHT", 6, 0)
    clearExclusionsBtn:SetText("Restore All")
    clearExclusionsBtn:SetScript("OnClick", function()
        ATM:ClearTemporaryExclusions(false)
    end)
    widgets.clearExclusionsBtn = clearExclusionsBtn

    local exclusionZoneText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    exclusionZoneText:SetPoint("TOPLEFT", excludeHeader, "BOTTOMLEFT", 0, -6)
    exclusionZoneText:SetWidth(520)
    exclusionZoneText:SetJustifyH("LEFT")
    widgets.exclusionZoneText = exclusionZoneText

    local exclusionHelpText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    exclusionHelpText:SetPoint("TOPLEFT", exclusionZoneText, "BOTTOMLEFT", 0, -2)
    exclusionHelpText:SetWidth(520)
    exclusionHelpText:SetJustifyH("LEFT")
    exclusionHelpText:SetText("|cffaaaaaaTip: Right-click any targeted NPC frame -> 'AutoTag: Exclude', or click a mob below to toggle it:|r")

    local mobChipContainer = CreateFrame("Frame", nil, panel)
    mobChipContainer:SetPoint("TOPLEFT", exclusionHelpText, "BOTTOMLEFT", 0, -6)
    mobChipContainer:SetSize(515, 28)
    widgets.mobChipContainer = mobChipContainer

    local noAreaMobsLabel = mobChipContainer:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    noAreaMobsLabel:SetPoint("TOPLEFT", mobChipContainer, "TOPLEFT", 0, -4)
    noAreaMobsLabel:SetText("No active quest mobs detected in this area.")
    widgets.noAreaMobsLabel = noAreaMobsLabel

    for i = 1, MAX_MOB_CHIP_BUTTONS do
        local btn = CreateFrame("Button", nil, mobChipContainer, "UIPanelButtonTemplate")
        btn:SetSize(120, 22)
        btn:Hide()
        btn:SetScript("OnClick", function(self)
            if self.mobName then
                ATM:ToggleMobTemporaryExclusion(self.mobName)
            end
        end)
        btn:SetScript("OnEnter", function(self)
            if not self.mobName then
                return
            end
            local isEx = ATM.IsMobTemporarilyExcluded and ATM:IsMobTemporarilyExcluded(self.mobName)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.mobName, 1, 0.82, 0)
            if isEx then
                GameTooltip:AddLine("Currently EXCLUDED in this area. Click to restore to AutoTag.", 1, 0.35, 0.35, true)
            else
                GameTooltip:AddLine("Currently ACTIVE in AutoTag. Click to temporarily exclude while in this area.", 0.27, 0.93, 0.4, true)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        mobChipButtons[i] = btn
    end

    -- Section 5: Live Macro Preview & Capacity Breakdown
    local previewHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    previewHeader:SetPoint("TOPLEFT", mobChipContainer, "BOTTOMLEFT", 0, -16)
    previewHeader:SetText("Live Macro Preview & Space Remaining")
    widgets.macroHeaderLabel = previewHeader

    local previewToggleBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    previewToggleBtn:SetSize(185, 22)
    previewToggleBtn:SetPoint("LEFT", previewHeader, "RIGHT", 14, 0)
    previewToggleBtn:SetScript("OnClick", function()
        previewExtendedMode = not previewExtendedMode
        SyncOptions()
    end)
    widgets.previewToggleBtn = previewToggleBtn

    local macroMeterLine = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    macroMeterLine:SetPoint("TOPLEFT", previewHeader, "BOTTOMLEFT", 0, -8)
    macroMeterLine:SetWidth(520)
    macroMeterLine:SetJustifyH("LEFT")
    widgets.macroMeterLine = macroMeterLine

    local extendedMeterLine = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    extendedMeterLine:SetPoint("TOPLEFT", macroMeterLine, "BOTTOMLEFT", 0, -4)
    extendedMeterLine:SetWidth(520)
    extendedMeterLine:SetJustifyH("LEFT")
    widgets.extendedMeterLine = extendedMeterLine

    local previewBg = panel:CreateTexture(nil, "BACKGROUND")
    previewBg:SetColorTexture(0, 0, 0, 0.55)
    previewBg:SetPoint("TOPLEFT", extendedMeterLine, "BOTTOMLEFT", 0, -8)
    previewBg:SetSize(515, 135)
    widgets.previewBg = previewBg

    local previewText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    previewText:SetPoint("TOPLEFT", previewBg, "TOPLEFT", 10, -10)
    previewText:SetWidth(495)
    previewText:SetJustifyH("LEFT")
    previewText:SetJustifyV("TOP")
    widgets.macroPreviewText = previewText

    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(160, 24)
    resetBtn:SetPoint("TOPLEFT", previewBg, "BOTTOMLEFT", 0, -14)
    resetBtn:SetText("Reset to Defaults")
    resetBtn:SetScript("OnClick", function()
        ATM:ResetSettingsToDefault()
        ATM:Print("Settings restored to defaults.")
    end)

    FitScrollContent = function()
        panel:SetWidth(math.max(1, scroll:GetWidth()))
        local top = panel:GetTop()
        local bottom = resetBtn:GetBottom()
        if top and bottom then
            panel:SetHeight(top - bottom + 30)
        end
    end

    scroll:HookScript("OnSizeChanged", FitScrollContent)
    canvas:HookScript("OnShow", function()
        StopKeybindCapture()
        SyncOptions()
        FitScrollContent()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, FitScrollContent)
        end
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        optionsCategory = Settings.RegisterCanvasLayoutCategory(canvas, canvas.name)
        Settings.RegisterAddOnCategory(optionsCategory)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(canvas)
    end

    optionsCanvas = canvas
end

function ATM:OpenOptions()
    if not optionsCanvas then
        self:RegisterOptions()
    end
    SyncOptions()
    if Settings and Settings.OpenToCategory and optionsCategory then
        local catId = optionsCategory.GetID and optionsCategory:GetID() or optionsCategory.ID
        if catId then
            pcall(Settings.OpenToCategory, catId)
        end
    elseif InterfaceOptionsFrame_OpenToCategory and optionsCanvas then
        InterfaceOptionsFrame_OpenToCategory(optionsCanvas)
        InterfaceOptionsFrame_OpenToCategory(optionsCanvas)
    end
end
