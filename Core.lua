local addonName, ATM = ...
ATM = ATM or _G["AutoTagMacro"] or {}
_G["AutoTagMacro"] = ATM

ATM.ADDON_NAME = addonName or "AutoTagMacro"
ATM.VERSION = "1.3.1"
ATM.MACRO_NAME = "AutoTag"
ATM.SECURE_BUTTON_NAME = "AutoTagSecureButton"
ATM.DEFAULT_SPELL = "Faerie Fire"
ATM.THROTTLE_INTERVAL = 0.35

-- Register keybinding labels for the Keybindings UI and SetBindingClick.
_G["BINDING_HEADER_AUTOTAGMACRO"] = "AutoTagMacro"
_G["BINDING_NAME_CLICK AutoTagSecureButton:LeftButton"] = "AutoTag (Smart Multi-Page Keybind)"

local pairs = pairs
local next = next
local pcall = pcall
local tonumber = tonumber
local tostring = tostring
local strlower = string.lower
local strtrim = strtrim or function(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end
local issecretvalue = _G.issecretvalue or function()
    return false
end
local function plain(v)
    if issecretvalue(v) then
        return nil
    end
    return v
end
ATM.PlainValue = plain
local InCombatLockdown = InCombatLockdown
local GetRealZoneText = GetRealZoneText
local GetSubZoneText = GetSubZoneText
local GetZoneText = GetZoneText
local UnitExists = UnitExists
local UnitIsDead = UnitIsDead
local UnitCanAttack = UnitCanAttack
local UnitIsPlayer = _G.UnitIsPlayer
local UnitName = UnitName
local UnitIsTapDenied = _G.UnitIsTapDenied
local UnitIsTapped = _G.UnitIsTapped
local UnitIsTappedByPlayer = _G.UnitIsTappedByPlayer
local UnitIsTappedByAllThreatList = _G.UnitIsTappedByAllThreatList
local UIErrorsFrame = _G.UIErrorsFrame
local GetRaidTargetIndex = GetRaidTargetIndex
local SetRaidTarget = SetRaidTarget
local PlaySound = PlaySound
local SetBindingClick = SetBindingClick
local SetBinding = SetBinding
local GetBindingKey = GetBindingKey
local GetCurrentBindingSet = GetCurrentBindingSet
local SaveBindings = SaveBindings

-- Vanilla 1.12 lacks table.wipe; reuse a single fallback across modules.
local wipe = table.wipe or function(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end
ATM.WipeTable = wipe

local DEFAULT_DB = {
    debug = false,
    useSpell = true,
    spellName = "Faerie Fire",
    recentSpells = { "Faerie Fire" },
    raidMarker = 0,
    embedMarkerInMacro = true,
    startAttack = false,
    showTooltip = true,
    clearDeadTarget = true,
    strictQuestTargetsOnly = true,
    alwaysClearTarget = false,
    includeStopMacro = false,
    useShortTar = false,
    fallbackTargetEnemy = true,
    enablePrefixCompaction = true,
    includeOtherZoneQuests = true,
    soundOnAcquire = false,
    perCharacter = false,
}
ATM.DEFAULT_DB = DEFAULT_DB

local InitializeDB
local RequestUpdate
local ExecuteUpdate
local OnTargetChanged
local HandleSlashCommand
local OnEvent
local OnThrottleUpdate
local HookQuestieReady

ATM.inCombat = false
ATM.pendingCombatUpdate = false
ATM.pendingForceCreate = false
ATM.throttleElapsed = 0
ATM.lastZone = ""
ATM.lastSubZone = ""
ATM.questieHooked = false
ATM.nameplateUnits = {}
ATM.targetMarkedForCurrentTarget = nil
ATM.tempExcludedMobs = {}
ATM.tempExcludedOrder = {}
ATM.tempExclusionZone = ""
ATM.contextMenuHooked = false

function ATM:Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AutoTagMacro]|r " .. tostring(msg))
    end
end

function ATM:Debug(msg)
    if AutoTagMacroDB and AutoTagMacroDB.debug and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[AutoTagMacro]|r |cffaaaaaa[Debug]|r " .. tostring(msg))
    end
end

function ATM:IsInCombat()
    if InCombatLockdown and InCombatLockdown() then
        return true
    end
    return self.inCombat == true
end

function ATM:GetCurrentZoneInfo()
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    local subZone = (GetSubZoneText and GetSubZoneText()) or ""
    return zone, subZone
end

InitializeDB = function()
    if type(AutoTagMacroDB) ~= "table" then
        AutoTagMacroDB = {}
    end
    for k, v in pairs(DEFAULT_DB) do
        if AutoTagMacroDB[k] == nil then
            if type(v) == "table" then
                local copy = {}
                for i = 1, #v do
                    copy[i] = v[i]
                end
                AutoTagMacroDB[k] = copy
            else
                AutoTagMacroDB[k] = v
            end
        end
    end
    if type(AutoTagMacroDB.recentSpells) ~= "table" or #AutoTagMacroDB.recentSpells == 0 then
        AutoTagMacroDB.recentSpells = { AutoTagMacroDB.spellName or ATM.DEFAULT_SPELL }
    end
    ATM.db = AutoTagMacroDB
end
ATM.InitializeDB = InitializeDB

function ATM:RecordRecentSpell(spell)
    InitializeDB()
    if type(spell) ~= "string" then
        return
    end
    local cleaned = strtrim(spell)
    if cleaned == "" then
        return
    end
    local list = AutoTagMacroDB.recentSpells
    local lowerCleaned = strlower(cleaned)
    for i = #list, 1, -1 do
        if strlower(tostring(list[i] or "")) == lowerCleaned then
            table.remove(list, i)
        end
    end
    table.insert(list, 1, cleaned)
    while #list > 5 do
        table.remove(list)
    end
end

function ATM:GetExtendedKeybind()
    if not GetBindingKey then
        return nil
    end
    return GetBindingKey("CLICK " .. self.SECURE_BUTTON_NAME .. ":LeftButton")
end

function ATM:SetExtendedKeybind(key)
    if self:IsInCombat() then
        self:Print("Cannot change keybindings during combat.")
        return false
    end
    if not SetBindingClick or not GetBindingKey then
        return false
    end
    local command = "CLICK " .. self.SECURE_BUTTON_NAME .. ":LeftButton"
    local oldKey1, oldKey2 = GetBindingKey(command)
    if oldKey1 and SetBinding then
        SetBinding(oldKey1)
    end
    if oldKey2 and SetBinding then
        SetBinding(oldKey2)
    end
    if key and key ~= "" then
        SetBindingClick(key, self.SECURE_BUTTON_NAME, "LeftButton")
    end
    if SaveBindings and GetCurrentBindingSet then
        local set = GetCurrentBindingSet()
        if set == 1 or set == 2 then
            pcall(SaveBindings, set)
        end
    end
    return true
end

function ATM:ResetSettingsToDefault()
    InitializeDB()
    for k, v in pairs(DEFAULT_DB) do
        if type(v) == "table" then
            local copy = {}
            for i = 1, #v do
                copy[i] = v[i]
            end
            AutoTagMacroDB[k] = copy
        else
            AutoTagMacroDB[k] = v
        end
    end
    self:ForceUpdate(false)
    if self.SyncOptions then
        self:SyncOptions()
    end
end

function ATM:IsMobTemporarilyExcluded(mobName)
    if type(mobName) ~= "string" or mobName == "" then
        return false
    end
    return self.tempExcludedMobs[strlower(strtrim(mobName))] ~= nil
end

function ATM:ClearTemporaryExclusions(silent)
    local hadAny = next(self.tempExcludedMobs) ~= nil
    wipe(self.tempExcludedMobs)
    wipe(self.tempExcludedOrder)
    if hadAny then
        if not silent then
            self:Print("Cleared temporary area mob exclusions.")
        end
        RequestUpdate("CLEAR_EXCLUSIONS")
        if self.SyncOptions then
            self:SyncOptions()
        end
    end
end

function ATM:SetMobTemporaryExclusion(mobName, exclude)
    if type(mobName) ~= "string" then
        return false
    end
    local cleaned = strtrim(mobName)
    if cleaned == "" then
        return false
    end
    local key = strlower(cleaned)
    local zone = self:GetCurrentZoneInfo()
    self.tempExclusionZone = zone or ""

    if exclude then
        if not self.tempExcludedMobs[key] then
            self.tempExcludedMobs[key] = cleaned
            table.insert(self.tempExcludedOrder, cleaned)
        end
        self:Print("Temporarily excluded '" .. cleaned .. "' while in " .. (zone ~= "" and zone or "this area") .. ".")
    else
        if self.tempExcludedMobs[key] then
            self.tempExcludedMobs[key] = nil
            for i = #self.tempExcludedOrder, 1, -1 do
                if strlower(self.tempExcludedOrder[i]) == key then
                    table.remove(self.tempExcludedOrder, i)
                end
            end
            self:Print("Restored '" .. cleaned .. "' to AutoTag macro.")
        end
    end

    self:ForceUpdate(false)
    if self.SyncOptions then
        self:SyncOptions()
    end
    return true
end

function ATM:ToggleMobTemporaryExclusion(mobName)
    if type(mobName) ~= "string" or strtrim(mobName) == "" then
        return false
    end
    local currentlyExcluded = self:IsMobTemporarilyExcluded(mobName)
    return self:SetMobTemporaryExclusion(mobName, not currentlyExcluded)
end

local HookTargetContextMenu = function()
    if ATM.contextMenuHooked then
        return
    end
    local MenuUtil = _G.MenuUtil
    local Menu = _G.Menu
    if Menu and type(Menu.ModifyMenu) == "function" and MenuUtil then
        ATM.contextMenuHooked = true
        local ModifyUnitMenu = function(owner, rootDescription, contextData)
            local unit = (type(contextData) == "table" and plain(contextData.unit)) or "target"
            if not UnitExists or plain(UnitExists(unit)) == false then
                return
            end
            if UnitIsPlayer and plain(UnitIsPlayer(unit)) == true then
                return
            end
            local npcName = UnitName and plain(UnitName(unit)) or nil
            if type(npcName) ~= "string" or npcName == "" then
                return
            end
            local isExcluded = ATM:IsMobTemporarilyExcluded(npcName)
            local label = isExcluded
                and ("|cff44ee66AutoTag: Re-include " .. npcName .. "|r")
                or ("|cffffaa00AutoTag: Exclude " .. npcName .. " (This Area)|r")
            if type(rootDescription.CreateDivider) == "function" then
                pcall(rootDescription.CreateDivider, rootDescription)
            end
            if type(rootDescription.CreateButton) == "function" then
                pcall(rootDescription.CreateButton, rootDescription, label, function()
                    ATM:ToggleMobTemporaryExclusion(npcName)
                end)
            end
        end
        pcall(Menu.ModifyMenu, "MENU_UNIT_TARGET", ModifyUnitMenu)
        pcall(Menu.ModifyMenu, "MENU_UNIT_ENEMY_PLAYER", ModifyUnitMenu)
        pcall(Menu.ModifyMenu, "MENU_UNIT_RAID_TARGET_ICON", ModifyUnitMenu)
    end
end

ExecuteUpdate = function(forceCreate)
    InitializeDB()
    local currentZone, currentSubZone = ATM:GetCurrentZoneInfo()
    if currentZone ~= "" and ATM.tempExclusionZone ~= "" and currentZone ~= ATM.tempExclusionZone then
        if next(ATM.tempExcludedMobs) ~= nil then
            wipe(ATM.tempExcludedMobs)
            wipe(ATM.tempExcludedOrder)
            ATM:Print("Left " .. ATM.tempExclusionZone .. "; cleared temporary mob exclusions.")
        end
    end
    if currentZone ~= "" then
        ATM.tempExclusionZone = currentZone
    end

    if ATM:IsInCombat() then
        ATM.pendingCombatUpdate = true
        if forceCreate then
            ATM.pendingForceCreate = true
        end
        ATM:Debug("In combat lockdown; queued macro update for PLAYER_REGEN_ENABLED.")
        return false
    end

    ATM.pendingCombatUpdate = false
    local shouldCreate = forceCreate or ATM.pendingForceCreate
    ATM.pendingForceCreate = false

    local zone, subZone = ATM:GetCurrentZoneInfo()
    ATM.lastZone = zone
    ATM.lastSubZone = subZone

    local mobs = ATM:ScanActiveQuestMobs(zone, subZone)
    local ok, count = ATM:SyncMacro(mobs, shouldCreate)
    if ATM.SyncOptions then
        ATM:SyncOptions()
    end
    return ok, count
end

function ATM:ForceUpdate(forceCreate)
    self.throttleFrame:Hide()
    self.throttleElapsed = 0
    return ExecuteUpdate(forceCreate)
end

function ATM:IsUnitTapDenied(unit)
    if not unit or not UnitExists or plain(UnitExists(unit)) == false then
        return false
    end
    if type(UnitIsTapDenied) == "function" then
        local ok, denied = pcall(UnitIsTapDenied, unit)
        if ok and plain(denied) == true then
            return true
        end
    end
    if type(UnitIsTapped) == "function" then
        local okTap, tapped = pcall(UnitIsTapped, unit)
        if okTap and plain(tapped) == true then
            local byPlayer = type(UnitIsTappedByPlayer) == "function" and plain(UnitIsTappedByPlayer(unit))
            local byAll = type(UnitIsTappedByAllThreatList) == "function" and plain(UnitIsTappedByAllThreatList(unit))
            if not byPlayer and not byAll then
                return true
            end
        end
    end
    return false
end

local ApplyTargetActions = function()
    if not AutoTagMacroDB then
        return
    end
    if not UnitExists or plain(UnitExists("target")) == false then
        return
    end
    if UnitIsDead and plain(UnitIsDead("target")) == true then
        return
    end
    if UnitCanAttack and plain(UnitCanAttack("player", "target")) == false then
        return
    end

    local targetName = UnitName and plain(UnitName("target")) or nil
    if type(targetName) == "string" and targetName ~= "" and not ATM:IsTrackedMobName(targetName) then
        return
    end

    -- If this quest mob is already gray-tagged by another player, warn on screen and skip the acquire sound.
    if ATM:IsUnitTapDenied("target") then
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage("AutoTag: " .. tostring(targetName or "Target") .. " is already tagged!", 1.0, 0.35, 0.2, 1.0)
        end
        return
    end

    local wantSound = AutoTagMacroDB.soundOnAcquire == true
    if not wantSound then
        return
    end

    if PlaySound then
        if SOUNDKIT and SOUNDKIT.RAID_WARNING then
            pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master")
        else
            pcall(PlaySound, 8959)
        end
    end
end
ATM.ApplyTargetActions = ApplyTargetActions

OnTargetChanged = function()
    -- Reset the per-target marker guard whenever the player's target changes.
    ATM.targetMarkedForCurrentTarget = nil
    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0, ApplyTargetActions)
    else
        ApplyTargetActions()
    end
end

local throttleFrame = CreateFrame("Frame")
throttleFrame:Hide()
ATM.throttleFrame = throttleFrame

OnThrottleUpdate = function(self, elapsed)
    local dt = elapsed or arg1 or 0.05
    ATM.throttleElapsed = ATM.throttleElapsed + dt
    if ATM.throttleElapsed >= ATM.THROTTLE_INTERVAL then
        self:Hide()
        ATM.throttleElapsed = 0
        ExecuteUpdate(false)
    end
end
throttleFrame:SetScript("OnUpdate", OnThrottleUpdate)

RequestUpdate = function(reason)
    if ATM:IsInCombat() then
        ATM.pendingCombatUpdate = true
        ATM:Debug("Queued update during combat (" .. tostring(reason) .. ").")
        return
    end
    ATM.throttleElapsed = 0
    throttleFrame:Show()
end

HookQuestieReady = function()
    if ATM.questieHooked then
        return
    end
    local Questie = _G.Questie
    if Questie and Questie.API and type(Questie.API.RegisterOnReady) == "function" then
        ATM.questieHooked = true
        Questie.API.RegisterOnReady(function()
            ATM:Debug("Questie.API ready; triggering quest target rescan.")
            RequestUpdate("QUESTIE_READY")
        end)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
pcall(eventFrame.RegisterEvent, eventFrame, "QUEST_WATCH_UPDATE")
pcall(eventFrame.RegisterEvent, eventFrame, "QUEST_ACCEPTED")
pcall(eventFrame.RegisterEvent, eventFrame, "QUEST_TURNED_IN")
pcall(eventFrame.RegisterEvent, eventFrame, "QUEST_REMOVED")
pcall(eventFrame.RegisterEvent, eventFrame, "UNIT_QUEST_LOG_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
pcall(eventFrame.RegisterEvent, eventFrame, "NAME_PLATE_UNIT_ADDED")
pcall(eventFrame.RegisterEvent, eventFrame, "NAME_PLATE_UNIT_REMOVED")

OnEvent = function(self, eventName, arg1Val)
    local evt = eventName or event
    local unitArg = plain(arg1Val or arg1)
    if evt == "NAME_PLATE_UNIT_ADDED" then
        if type(unitArg) == "string" then
            ATM.nameplateUnits[unitArg] = true
        end
        return
    end
    if evt == "NAME_PLATE_UNIT_REMOVED" then
        if type(unitArg) == "string" then
            ATM.nameplateUnits[unitArg] = nil
        end
        return
    end
    if evt == "PLAYER_TARGET_CHANGED" then
        OnTargetChanged()
        return
    end

    if evt == "PLAYER_REGEN_DISABLED" then
        -- Arm Page 1 (closest mobs + all tribe prefixes + /cast) right before combat lockdown freezes attributes.
        if ATM.ArmSecurePage and not (InCombatLockdown and InCombatLockdown()) then
            ATM:ArmSecurePage(1)
        end
        ATM.inCombat = true
        throttleFrame:Hide()
        return
    end

    if evt == "PLAYER_REGEN_ENABLED" then
        ATM.inCombat = false
        if ATM.pendingCombatUpdate then
            ATM:Debug("Combat ended; flushing queued macro update.")
            ExecuteUpdate(ATM.pendingForceCreate)
        else
            RequestUpdate(evt)
        end
        return
    end

    if evt == "PLAYER_ENTERING_WORLD" then
        wipe(ATM.nameplateUnits)
        InitializeDB()
        if ATM.RegisterOptions then
            ATM:RegisterOptions()
        end
        HookQuestieReady()
        HookTargetContextMenu()
        ATM.inCombat = (InCombatLockdown and InCombatLockdown()) or false
        RequestUpdate(evt)
        return
    end

    RequestUpdate(evt)
end
eventFrame:SetScript("OnEvent", OnEvent)

HandleSlashCommand = function(msg)
    InitializeDB()
    local input = strtrim(msg or "")
    local cmd, rest = input:match("^(%S+)%s*(.-)$")
    cmd = strlower(cmd or "")

    if cmd == "" or cmd == "options" or cmd == "config" or cmd == "opt" or cmd == "gui" or cmd == "menu" then
        if ATM.OpenOptions then
            ATM:OpenOptions()
        end
        return
    end

    if cmd == "update" or cmd == "sync" then
        if ATM:IsInCombat() then
            ATM.pendingCombatUpdate = true
            ATM.pendingForceCreate = true
            ATM:Print("Currently in combat. Macro sync queued for combat exit.")
        else
            local updated, count = ATM:ForceUpdate(true)
            if updated then
                ATM:Print("Synced macro '" .. ATM.MACRO_NAME .. "' with " .. tostring(count or 0) .. " target line(s).")
            end
        end
        return
    end

    if cmd == "status" then
        ATM:PrintStatus()
        return
    end

    if cmd == "debug" then
        AutoTagMacroDB.debug = not AutoTagMacroDB.debug
        local state = AutoTagMacroDB.debug and "|cff00ff00Enabled|r" or "|cffff5555Disabled|r"
        ATM:Print("Verbose debug output: " .. state)
        if ATM.SyncOptions then
            ATM:SyncOptions()
        end
        return
    end

    if cmd == "spell" then
        rest = strtrim(rest or "")
        if rest == "" or strlower(rest) == "none" or strlower(rest) == "off" then
            AutoTagMacroDB.useSpell = false
            ATM:Print("Tagging spell disabled (target only).")
        else
            AutoTagMacroDB.useSpell = true
            AutoTagMacroDB.spellName = rest
            ATM:RecordRecentSpell(rest)
            ATM:Print("Tagging spell set to: " .. rest)
        end
        ATM:ForceUpdate(false)
        return
    end

    if cmd == "mark" or cmd == "marker" then
        local idx = tonumber(rest)
        if idx and idx >= 0 and idx <= 8 then
            AutoTagMacroDB.raidMarker = math.floor(idx)
            ATM:Print("Raid marker set to: " .. tostring(AutoTagMacroDB.raidMarker))
            ATM:ForceUpdate(false)
        else
            ATM:Print("Usage: /at mark <0-8> (0 = None, 1 = Star .. 8 = Skull)")
        end
        return
    end

    if cmd == "exclude" or cmd == "ignore" then
        local mob = strtrim(rest or "")
        if mob == "" and UnitExists and plain(UnitExists("target")) then
            mob = (UnitName and plain(UnitName("target"))) or ""
        end
        if mob == "" then
            ATM:Print("Usage: /at exclude <Mob Name> (or target a mob and type /at exclude)")
        elseif strlower(mob) == "clear" or strlower(mob) == "reset" or strlower(mob) == "none" then
            ATM:ClearTemporaryExclusions(false)
        else
            ATM:ToggleMobTemporaryExclusion(mob)
        end
        return
    end

    ATM:Print("Commands: /at [config | update | status | exclude <mob|clear> | spell <name|none> | mark <0-8> | debug]")
end

SLASH_AUTOTAGMACRO1 = "/autotag"
SLASH_AUTOTAGMACRO2 = "/at"
SlashCmdList["AUTOTAGMACRO"] = HandleSlashCommand
