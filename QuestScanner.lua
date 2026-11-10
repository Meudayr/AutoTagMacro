local addonName, ATM = ...
ATM = ATM or _G["AutoTagMacro"]
local wipe = ATM.WipeTable

local ipairs = ipairs
local pairs = pairs
local tonumber = tonumber
local type = type
local strmatch = string.match
local strfind = string.find
local strlower = string.lower
local tinsert = table.insert
local tsort = table.sort

local C_QuestLog = _G.C_QuestLog
local C_Map = _G.C_Map
local GetNumQuestLogEntries = GetNumQuestLogEntries
local GetQuestLogTitle = GetQuestLogTitle
local GetNumQuestLeaderBoards = GetNumQuestLeaderBoards
local GetQuestLogLeaderBoard = GetQuestLogLeaderBoard
local GetQuestLogSelection = GetQuestLogSelection
local SelectQuestLogEntry = SelectQuestLogEntry
local GetItemCount = (_G.C_Item and _G.C_Item.GetItemCount) or _G.GetItemCount
local UnitFactionGroup = UnitFactionGroup

-- Recycled buffers to prevent table allocations during QUEST_LOG_UPDATE bursts.
local zoneMobs = {}
local subZoneMobs = {}
local fallbackQuestMobs = {}
local orderedMobs = {}
local allAreaMobs = {}
local seenMobs = {}
local mobBestDistSq = {}
local incompleteObjectives = {}
local objectivePool = {}
local vendorLookup = {}
ATM.allAreaMobs = allAreaMobs

-- Bounded memoization table so repeated objective strings never re-run regex patterns.
local parsedObjectiveCache = {}
local parsedCacheCount = 0
local MAX_PARSED_CACHE_SIZE = 256

ATM.ZoneQuestMobDB = {
    ["Stranglethorn Vale"] = {
        subzones = {
            ["Bal'lal Ruins"] = { "Bloodscalp Scout", "Bloodscalp Warrior", "Bloodscalp Hunter", "Bloodscalp Mystic" },
            ["Tkashi Ruins"] = { "Bloodscalp Warrior", "Bloodscalp Hunter", "Bloodscalp Mystic", "Bloodscalp Troll" },
            ["Zuuldaia Ruins"] = { "Bloodscalp Headhunter", "Bloodscalp Berserker", "Bloodscalp Witch Doctor", "Bloodscalp Shaman", "Bloodscalp Beastmaster" },
            ["Kal'ai Ruins"] = { "Bloodscalp Warrior", "Bloodscalp Hunter", "Bloodscalp Scout" },
            ["Balia'mah Ruins"] = { "Skullsplitter Warrior", "Skullsplitter Hunter", "Skullsplitter Headhunter", "Skullsplitter Mystic" },
            ["Ziata'jai Ruins"] = { "Skullsplitter Hunter", "Skullsplitter Headhunter", "Skullsplitter Berserker", "Skullsplitter Witch Doctor" },
            ["Zul'Mamwe"] = { "Skullsplitter Spiritchaser", "Skullsplitter Kurzen", "Skullsplitter Savage", "Skullsplitter Witch Doctor" },
            ["Kurzen's Compound"] = { "Kurzen Commando", "Kurzen Medicine Man", "Kurzen Jungle Fighter", "Kurzen Headshrinker", "Kurzen Subchief" },
            ["Lake Nazferiti"] = { "Venture Co. Geologist", "Venture Co. Strip Miner", "Venture Co. Lumberjack" },
            ["Mosh'Ogg Ogre Mound"] = { "Mosh'Ogg Brute", "Mosh'Ogg Warmonger", "Mosh'Ogg Witch Doctor", "Mosh'Ogg Spellcrafter", "Mosh'Ogg Mauler" },
        },
        objectives = {
            ["Bloodscalp Tusk"] = {
                "Bloodscalp Scout",
                "Bloodscalp Warrior",
                "Bloodscalp Hunter",
                "Bloodscalp Mystic",
                "Bloodscalp Berserker",
                "Bloodscalp Headhunter",
                "Bloodscalp Witch Doctor",
                "Bloodscalp Shaman",
                "Bloodscalp Beastmaster",
                "Bloodscalp Axe Thrower",
            },
            ["Bloodscalp Ear"] = {
                "Bloodscalp Scout",
                "Bloodscalp Warrior",
                "Bloodscalp Hunter",
                "Bloodscalp Mystic",
                "Bloodscalp Berserker",
                "Bloodscalp Headhunter",
                "Bloodscalp Witch Doctor",
                "Bloodscalp Shaman",
                "Bloodscalp Beastmaster",
            },
            ["Gan'zulah's Head"] = { "Gan'zulah" },
            ["Nezzliok's Head"] = { "Nezzliok the Dire" },
            ["Skullsplitter Tusk"] = {
                "Skullsplitter Warrior",
                "Skullsplitter Hunter",
                "Skullsplitter Headhunter",
                "Skullsplitter Berserker",
                "Skullsplitter Mystic",
                "Skullsplitter Witch Doctor",
                "Skullsplitter Spiritchaser",
                "Skullsplitter Axe Thrower",
                "Skullsplitter Beastmaster",
            },
            ["Singeding Stone"] = { "Venture Co. Geologist" },
            ["Singing Blue Crystal"] = { "Venture Co. Geologist" },
            ["Singing Crystal Shard"] = { "Saltscale Warrior", "Saltscale Tideglider", "Saltscale Forager", "Saltscale Oracle", "Saltscale Hunter" },
            ["Large River Crocolisk Skin"] = { "Elder Saltwater Crocolisk", "Snapjaw Crocolisk" },
            ["Snapjaw Crocolisk Skin"] = { "Snapjaw Crocolisk" },
            ["Shadowmaw Claw"] = { "Shadowmaw Panther" },
            ["Pristine Tigress Fang"] = { "Elder Stranglethorn Tiger" },
            ["Aged Gorilla Sinew"] = { "Mistvale Gorilla", "Elder Mistvale Gorilla" },
            ["Jungle Stalker Feather"] = { "Jungle Stalker" },
            ["Stranglethorn Thorn"] = { "Stranglethornlasher" },
        },
    },
    ["Teldrassil"] = {
        subzones = {
            ["Shadowglen"] = { "Young Nightsaber", "Young Thistle Boar", "Grell", "Grellkin", "Webwood Spider" },
            ["Starbreeze Village"] = { "Gnarlpine Ursa", "Gnarlpine Shaman", "Gnarlpine Defender", "Ferocitas the Dream Eater" },
            ["Ban'ethil Barrow Den"] = { "Gnarlpine Mystic", "Gnarlpine Warrior", "Melenas" },
        },
        objectives = {
            ["Fel Moss"] = { "Grell", "Grellkin" },
            ["Webwood Venom Sac"] = { "Webwood Spider" },
            ["Gnarlpine Necklace"] = { "Gnarlpine Mystic", "Gnarlpine Warrior" },
            ["Small Spider Leg"] = { "Webwood Lurker", "Webwood Venomfang" },
        },
    },
    ["Darkshore"] = {
        subzones = {
            ["Ameth'Aran"] = { "Cursed Highborne", "Writhing Highborne", "Wailing Highborne" },
            ["Bashal'Aran"] = { "Wild Grell", "Vile Sprite", "Deth'ryll Satyr" },
        },
        objectives = {
            ["Crawler Leg"] = { "Pygmy Tide Crawler", "Young Reef Crawler" },
            ["Moonstalker Fang"] = { "Moonstalker", "Moonstalker Runt" },
            ["Highborne Relic"] = { "Cursed Highborne", "Writhing Highborne", "Wailing Highborne" },
        },
    },
    ["Mulgore"] = {
        subzones = {
            ["Red Cloud Mesa"] = { "Plainstrider", "Mountain Cougar", "Battleboar", "Bristleback Quilboar" },
            ["Brambleblade Ravine"] = { "Bristleback Shaman", "Bristleback Interloper", "Sharptusk Thornmantle" },
        },
        objectives = {
            ["Plainstrider Meat"] = { "Plainstrider", "Adult Plainstrider" },
            ["Plainstrider Feather"] = { "Plainstrider", "Adult Plainstrider" },
            ["Mountain Cougar Pelt"] = { "Mountain Cougar" },
        },
    },
    ["Elwynn Forest"] = {
        subzones = {
            ["Northshire Valley"] = { "Kobold Vermin", "Kobold Worker", "Kobold Laborer", "Defias Thug", "Garrick Padfoot" },
            ["Fargodeep Mine"] = { "Kobold Tunnelratter", "Kobold Miner", "Goldtooth" },
            ["Jasperlode Mine"] = { "Kobold Geomancer", "Kobold Digger" },
        },
        objectives = {
            ["Red Burlap Bandana"] = { "Defias Thug", "Defias Cutpurse" },
            ["Large Candle"] = { "Kobold Tunnelratter", "Kobold Miner" },
            ["Gold Dust"] = { "Kobold Tunnelratter", "Kobold Miner" },
        },
    },
    ["Dun Morogh"] = {
        subzones = {
            ["Coldridge Valley"] = { "Ragged Timber Wolf", "Small Crag Boar", "Rockjaw Trogg", "Frostmane Troll Whelp" },
        },
        objectives = {
            ["Tough Wolf Meat"] = { "Ragged Young Wolf", "Ragged Timber Wolf" },
            ["Chunk of Boar Meat"] = { "Small Crag Boar", "Crag Boar" },
        },
    },
    ["Durotar"] = {
        subzones = {
            ["Valley of Trials"] = { "Mottled Boar", "Scorpid Worker", "Vile Familiar", "Felstalker", "Sarkoth" },
            ["Tiragarde Keep"] = { "Kul Tiras Sailor", "Kul Tiras Marine", "Lieutenant Benedict" },
        },
        objectives = {
            ["Scorpid Worker Tail"] = { "Scorpid Worker" },
            ["Canvas Scraps"] = { "Kul Tiras Sailor", "Kul Tiras Marine" },
        },
    },
    ["Tirisfal Glades"] = {
        subzones = {
            ["Deathknell"] = { "Mindless Zombie", "Wretched Zombie", "Rattlecage Skeleton", "Duskbat", "Night Web Spider" },
            ["Scarlet Watch Post"] = { "Scarlet Convert", "Scarlet Initiate" },
        },
        objectives = {
            ["Scarlet Armband"] = { "Scarlet Convert", "Scarlet Initiate" },
            ["Duskbat Pelt"] = { "Duskbat", "Mangy Duskbat" },
        },
    },
    ["The Barrens"] = {
        subzones = {
            ["The Crossroads"] = { "Plainstrider", "Sunscale Lashtail", "Razormane Quilboar", "Zhevra Runner" },
        },
        objectives = {
            ["Zhevra Hooves"] = { "Zhevra Runner", "Zhevra Charger" },
            ["Plainstrider Beak"] = { "Greater Plainstrider", "Fleeting Plainstrider", "Ornery Plainstrider" },
            ["Raptor Head"] = { "Sunscale Lashtail", "Sunscale Screecher" },
        },
    },
    ["Westfall"] = {
        subzones = {
            ["Sentinel Hill"] = { "Defias Trapper", "Defias Smuggler", "Defias Pillager", "Defias Looter" },
        },
        objectives = {
            ["Red Silk Bandana"] = { "Defias Pillager", "Defias Looter", "Defias Trapper" },
            ["Goretusk Liver"] = { "Young Goretusk", "Goretusk" },
            ["Okra"] = { "Harvest Watcher" },
        },
    },
    ["Loch Modan"] = {
        subzones = {
            ["Thelsamar"] = { "Elder Crag Boar", "Mountain Buzzard", "Forest Lurker", "Stonesplinter Trogg" },
        },
        objectives = {
            ["Boar Intestines"] = { "Elder Crag Boar", "Mountain Boar" },
            ["Bear Meat"] = { "Black Bear", "Elder Black Bear" },
            ["Spider Ichor"] = { "Forest Lurker", "Wood Lurker" },
        },
    },
}

local CleanMobName
local ParseObjectiveText
local GetPlayerMapLocation
local IsNpcHostileToPlayer
local ScoreNpcProximity
local AddMobCandidate
local AddNpcCandidateById
local ResolveItemDroppers
local IsObjectiveNameIncomplete
local ResolveQuestFromQuestieDB
local ResolveQuestFromQuestieLive
local AddZoneFallbackMobs
local ProcessQuestEntry
local ScanModernQuestLog
local ScanClassicQuestLog
local SortZoneMobsByDistance

CleanMobName = function(raw)
    if type(raw) ~= "string" then
        return nil
    end
    local cleaned = strmatch(raw, "^%s*(.-)%s*$")
    if not cleaned or cleaned == "" then
        return nil
    end
    cleaned = strmatch(cleaned, "^%d+%s*/%s*%d+%s+(.+)$") or cleaned
    cleaned = strmatch(cleaned, "^(.-)%s*:%s*%d+%s*/%s*%d+$") or cleaned
    cleaned = strmatch(cleaned, "^(.-)%s+slain$") or cleaned
    cleaned = strmatch(cleaned, "^[Kk]ill%s+(.-)$") or cleaned
    cleaned = strmatch(cleaned, "^[Ss]lay%s+(.-)$") or cleaned
    cleaned = strmatch(cleaned, "^[Dd]efeat%s+(.-)$") or cleaned
    cleaned = strmatch(cleaned, "^%d+%s+(.-)$") or cleaned
    cleaned = strmatch(cleaned, "^%s*(.-)%s*$")
    if not cleaned or cleaned == "" then
        return nil
    end
    return cleaned
end

ParseObjectiveText = function(text, objType, finished)
    if finished or type(text) ~= "string" or text == "" then
        return nil
    end

    local cacheKey = (objType or "") .. "|" .. text
    local cached = parsedObjectiveCache[cacheKey]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end

    if parsedCacheCount >= MAX_PARSED_CACHE_SIZE then
        wipe(parsedObjectiveCache)
        parsedCacheCount = 0
    end
    parsedCacheCount = parsedCacheCount + 1

    local cur, max, remainder
    local targetPart

    -- Classic/3.3.5 format: "Young Nightsaber slain: 3/7" or "Bloodscalp Tusk: 7/9"
    targetPart, cur, max = strmatch(text, "^(.-)%s*:%s*(%d+)%s*/%s*(%d+)%s*$")
    if not targetPart then
        -- Modern/DialogueUI format: "7/9 Bloodscalp Tusk"
        cur, max, remainder = strmatch(text, "^%s*(%d+)%s*/%s*(%d+)%s+(.+)$")
        targetPart = remainder
    end

    if cur and max then
        local c = tonumber(cur)
        local m = tonumber(max)
        if c and m and m > 0 and c >= m then
            parsedObjectiveCache[cacheKey] = false
            return nil
        end
    end

    if not targetPart then
        targetPart = text
    end

    local isMonsterKill = (objType == "monster")
        or (objType == "killcredit")
        or (strfind(targetPart, "%s+slain$") ~= nil)
        or (strfind(targetPart, "^[Kk]ill%s+") ~= nil)
        or (strfind(targetPart, "^[Ss]lay%s+") ~= nil)

    local cleaned = CleanMobName(targetPart)
    if not cleaned then
        parsedObjectiveCache[cacheKey] = false
        return nil
    end

    local entry = {
        name = cleaned,
        lowerName = strlower(cleaned),
        objType = objType or "",
        isMonster = isMonsterKill,
    }
    parsedObjectiveCache[cacheKey] = entry
    return entry
end

GetPlayerMapLocation = function(zoneName)
    local areaId = nil
    local playerX, playerY = nil, nil

    local QuestieLoader = _G.QuestieLoader
    if QuestieLoader and type(QuestieLoader.ImportModule) == "function" then
        local okPlayer, QuestiePlayer = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestiePlayer")
        if okPlayer and QuestiePlayer and type(QuestiePlayer.GetCurrentZoneId) == "function" then
            local okZone, zId = pcall(QuestiePlayer.GetCurrentZoneId, QuestiePlayer)
            if okZone and type(zId) == "number" and zId > 0 then
                areaId = zId
            end
        end
        if not areaId and zoneName and zoneName ~= "" then
            local okZoneDB, ZoneDB = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
            if okZoneDB and ZoneDB and type(ZoneDB.GetAreaIdByName) == "function" then
                local okId, zId = pcall(ZoneDB.GetAreaIdByName, ZoneDB, zoneName)
                if okId and type(zId) == "number" and zId > 0 then
                    areaId = zId
                end
            end
        end
    end

    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
        local uiMapId = C_Map.GetBestMapForUnit("player")
        if uiMapId then
            local pos = C_Map.GetPlayerMapPosition(uiMapId, "player")
            if pos and type(pos.GetXY) == "function" then
                local x, y = pos:GetXY()
                if x and y and (x > 0 or y > 0) then
                    playerX = x * 100
                    playerY = y * 100
                end
            end
        end
    end

    return areaId, playerX, playerY
end

function ATM:GetPlayerCoordinates()
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
        local uiMapId = C_Map.GetBestMapForUnit("player")
        if uiMapId then
            local pos = C_Map.GetPlayerMapPosition(uiMapId, "player")
            if pos and type(pos.GetXY) == "function" then
                local x, y = pos:GetXY()
                if x and y and (x > 0 or y > 0) then
                    return x * 100, y * 100
                end
            end
        end
    end
    return nil, nil
end

IsNpcHostileToPlayer = function(npcId)
    local NpcDB = _G.NpcDB
    if not NpcDB or type(NpcDB.friendlyToFaction) ~= "function" then
        return true
    end
    local friendly = NpcDB.friendlyToFaction(npcId)
    if not friendly or friendly == "" then
        return true
    end
    if friendly == "AH" then
        return false
    end
    local playerFaction = UnitFactionGroup and UnitFactionGroup("player")
    if playerFaction == "Alliance" and friendly == "A" then
        return false
    end
    if playerFaction == "Horde" and friendly == "H" then
        return false
    end
    return true
end

ScoreNpcProximity = function(npcId, currentAreaId, playerX, playerY)
    local NpcDB = _G.NpcDB
    if not NpcDB or type(NpcDB.spawns) ~= "function" then
        return nil, nil
    end

    local spawns = NpcDB.spawns(npcId)
    if type(spawns) ~= "table" then
        return nil, nil
    end

    if currentAreaId and spawns[currentAreaId] then
        local zoneSpawns = spawns[currentAreaId]
        if playerX and playerY and type(zoneSpawns) == "table" then
            local bestDistSq = 999999
            for i = 1, #zoneSpawns do
                local pt = zoneSpawns[i]
                if pt and pt[1] and pt[2] and pt[1] >= 0 and pt[2] >= 0 then
                    local dx = pt[1] - playerX
                    local dy = pt[2] - playerY
                    local distSq = (dx * dx) + (dy * dy)
                    if distSq < bestDistSq then
                        bestDistSq = distSq
                    end
                end
            end
            return true, bestDistSq
        end
        return true, 5000
    end

    if currentAreaId then
        local hasAnySpawn = false
        for _ in pairs(spawns) do
            hasAnySpawn = true
            break
        end
        if hasAnySpawn then
            return false, 999999
        end
    end

    return nil, nil
end

AddMobCandidate = function(bucket, mobName, distSq)
    if not mobName or mobName == "" then
        return
    end
    local key = strlower(mobName)
    local score = distSq or 50000
    if seenMobs[key] then
        if score < (mobBestDistSq[key] or 999999) then
            mobBestDistSq[key] = score
        end
        return
    end
    seenMobs[key] = true
    mobBestDistSq[key] = score
    tinsert(bucket, mobName)
end

AddNpcCandidateById = function(npcId, inZoneHeader, currentAreaId, playerX, playerY)
    local NpcDB = _G.NpcDB
    if not NpcDB or type(NpcDB.name) ~= "function" then
        return false
    end
    if not IsNpcHostileToPlayer(npcId) then
        return false
    end
    local npcName = NpcDB.name(npcId)
    if not npcName or npcName == "" then
        return false
    end

    local inCurrentArea, distSq = ScoreNpcProximity(npcId, currentAreaId, playerX, playerY)
    if inCurrentArea == true then
        AddMobCandidate(zoneMobs, npcName, distSq)
        return true
    elseif inCurrentArea == false then
        AddMobCandidate(fallbackQuestMobs, npcName, distSq)
        return true
    else
        local targetBucket = inZoneHeader and zoneMobs or fallbackQuestMobs
        AddMobCandidate(targetBucket, npcName, inZoneHeader and 10000 or 90000)
        return true
    end
end

ResolveItemDroppers = function(itemId, inZoneHeader, currentAreaId, playerX, playerY)
    local ItemDB = _G.ItemDB
    if not ItemDB or type(ItemDB.npcDrops) ~= "function" then
        return false
    end

    local npcDrops = ItemDB.npcDrops(itemId)
    if type(npcDrops) ~= "table" or #npcDrops == 0 then
        return false
    end

    wipe(vendorLookup)
    if type(ItemDB.vendors) == "function" then
        local vendors = ItemDB.vendors(itemId)
        if type(vendors) == "table" then
            for i = 1, #vendors do
                vendorLookup[vendors[i]] = true
            end
        end
    end

    local foundAny = false
    for i = 1, #npcDrops do
        local npcId = npcDrops[i]
        if npcId and not vendorLookup[npcId] then
            if AddNpcCandidateById(npcId, inZoneHeader, currentAreaId, playerX, playerY) then
                foundAny = true
            end
        end
    end
    return foundAny
end

IsObjectiveNameIncomplete = function(candidateText, allowAnyItemFallback)
    if #incompleteObjectives == 0 then
        return false
    end
    if not candidateText or candidateText == "" then
        return allowAnyItemFallback and (#incompleteObjectives == 1) or false
    end
    local lowerCandidate = strlower(candidateText)
    for i = 1, #incompleteObjectives do
        local inc = incompleteObjectives[i]
        if inc.lowerName == lowerCandidate then
            return true
        end
        if not inc.isMonster and (strfind(inc.lowerName, lowerCandidate, 1, true) or strfind(lowerCandidate, inc.lowerName, 1, true)) then
            return true
        end
    end
    if allowAnyItemFallback and #incompleteObjectives == 1 then
        return true
    end
    return false
end

ResolveQuestFromQuestieDB = function(questId, questTitle, inZoneHeader, currentAreaId, playerX, playerY)
    local QuestDB = _G.QuestDB
    local ItemDB = _G.ItemDB
    local NpcDB = _G.NpcDB
    if not QuestDB or not NpcDB then
        return false
    end

    if (not questId or questId == 0) and questTitle and questTitle ~= "" and type(QuestDB.IdsByName) == "function" then
        local ids = QuestDB.IdsByName(questTitle)
        if type(ids) == "table" and ids[1] then
            questId = ids[1]
        end
    end

    if not questId or questId == 0 then
        return false
    end

    local resolvedAny = false
    local rawObjectives = type(QuestDB.objectives) == "function" and QuestDB.objectives(questId) or nil

    if type(rawObjectives) == "table" then
        -- 1) Creature kill objectives
        local creatureObjs = rawObjectives[1]
        if type(creatureObjs) == "table" then
            for i = 1, #creatureObjs do
                local cObj = creatureObjs[i]
                local npcId = cObj and cObj[1]
                if npcId then
                    local npcName = NpcDB.name(npcId)
                    if IsObjectiveNameIncomplete(cObj[2] or npcName, false) then
                        if AddNpcCandidateById(npcId, inZoneHeader, currentAreaId, playerX, playerY) then
                            resolvedAny = true
                        end
                    end
                end
            end
        end

        -- 3) Item drop objectives (e.g. Bloodscalp Tusk, Zhevra Hooves)
        local itemObjs = rawObjectives[3]
        if type(itemObjs) == "table" and ItemDB then
            for i = 1, #itemObjs do
                local iObj = itemObjs[i]
                local itemId = iObj and iObj[1]
                if itemId then
                    local itemName = type(ItemDB.name) == "function" and ItemDB.name(itemId) or nil
                    if IsObjectiveNameIncomplete(iObj[2] or itemName, #itemObjs == 1) then
                        if ResolveItemDroppers(itemId, inZoneHeader, currentAreaId, playerX, playerY) then
                            resolvedAny = true
                        end
                    end
                end
            end
        end

        -- 5) KillCredit multi-NPC objectives
        local creditObjs = rawObjectives[5]
        if type(creditObjs) == "table" then
            for i = 1, #creditObjs do
                local kObj = creditObjs[i]
                local idList = kObj and kObj[1]
                local rootId = kObj and kObj[2]
                local rootName = rootId and NpcDB.name(rootId) or nil
                if type(idList) == "table" and IsObjectiveNameIncomplete(kObj[3] or rootName, #creditObjs == 1) then
                    for j = 1, #idList do
                        if AddNpcCandidateById(idList[j], inZoneHeader, currentAreaId, playerX, playerY) then
                            resolvedAny = true
                        end
                    end
                end
            end
        end

        -- 6) Spell objectives with item source
        local spellObjs = rawObjectives[6]
        if type(spellObjs) == "table" then
            for i = 1, #spellObjs do
                local sObj = spellObjs[i]
                local itemSourceId = sObj and sObj[3]
                if itemSourceId and IsObjectiveNameIncomplete(sObj[2], true) then
                    if ResolveItemDroppers(itemSourceId, inZoneHeader, currentAreaId, playerX, playerY) then
                        resolvedAny = true
                    end
                end
            end
        end
    end

    -- Required source items dropped by mobs (e.g. intermediate quest items)
    if type(QuestDB.requiredSourceItems) == "function" then
        local reqItems = QuestDB.requiredSourceItems(questId)
        if type(reqItems) == "table" then
            for i = 1, #reqItems do
                local itemId = reqItems[i]
                if itemId then
                    local owned = GetItemCount and GetItemCount(itemId) or 0
                    if owned == 0 then
                        if ResolveItemDroppers(itemId, inZoneHeader, currentAreaId, playerX, playerY) then
                            resolvedAny = true
                        end
                    end
                end
            end
        end
    end

    -- Extra objectives referencing hostile monsters
    if #incompleteObjectives > 0 and type(QuestDB.extraObjectives) == "function" then
        local extraObjs = QuestDB.extraObjectives(questId)
        if type(extraObjs) == "table" then
            for i = 1, #extraObjs do
                local extra = extraObjs[i]
                local refs = extra and extra[5]
                if type(refs) == "table" then
                    for j = 1, #refs do
                        local ref = refs[j]
                        if ref and ref[1] == "monster" and ref[2] then
                            local npcName = NpcDB.name(ref[2])
                            if IsObjectiveNameIncomplete(extra[3] or npcName, true) then
                                if AddNpcCandidateById(ref[2], inZoneHeader, currentAreaId, playerX, playerY) then
                                    resolvedAny = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return resolvedAny
end

ResolveQuestFromQuestieLive = function(questId, inZoneHeader, currentAreaId, playerX, playerY)
    if not questId or questId == 0 or #incompleteObjectives == 0 then
        return false
    end
    local QuestieLoader = _G.QuestieLoader
    if not QuestieLoader or type(QuestieLoader.ImportModule) ~= "function" then
        return false
    end
    local ok, QuestiePlayer = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestiePlayer")
    if not ok or not QuestiePlayer or type(QuestiePlayer.currentQuestlog) ~= "table" then
        return false
    end
    local qEntry = QuestiePlayer.currentQuestlog[questId]
    if type(qEntry) ~= "table" then
        return false
    end

    local resolvedAny = false
    local ProcessObjectiveGroup = function(objTable)
        if type(objTable) ~= "table" then
            return
        end
        for _, obj in pairs(objTable) do
            local objIncomplete = type(obj) == "table"
                and not obj.Completed
                and (not obj.Needed or not obj.Collected or obj.Needed == 0 or obj.Collected < obj.Needed)
            if objIncomplete and type(obj.spawnList) == "table" then
                for npcId, spawnData in pairs(obj.spawnList) do
                    if type(spawnData) == "table" and spawnData.Hostile and spawnData.Name then
                        if IsObjectiveNameIncomplete(obj.Description or spawnData.Name, false) then
                            if type(npcId) == "number" and _G.NpcDB then
                                AddNpcCandidateById(npcId, inZoneHeader, currentAreaId, playerX, playerY)
                            else
                                local bucket = inZoneHeader and zoneMobs or fallbackQuestMobs
                                AddMobCandidate(bucket, spawnData.Name, inZoneHeader and 8000 or 85000)
                            end
                            resolvedAny = true
                        end
                    end
                end
            end
        end
    end

    ProcessObjectiveGroup(qEntry.Objectives)
    ProcessObjectiveGroup(qEntry.SpecialObjectives)
    return resolvedAny
end

AddZoneFallbackMobs = function(bucket, zoneData, parsedObj)
    if not zoneData or not parsedObj then
        return false
    end
    local objMap = zoneData.objectives
    if objMap and objMap[parsedObj.name] then
        for _, mobName in ipairs(objMap[parsedObj.name]) do
            AddMobCandidate(bucket, mobName, 12000)
        end
        return true
    end
    return false
end

ProcessQuestEntry = function(questId, questTitle, inZoneHeader, zoneData, currentAreaId, playerX, playerY)
    if #incompleteObjectives == 0 then
        return
    end
    local targetBucket = inZoneHeader and zoneMobs or fallbackQuestMobs
    local defaultDist = inZoneHeader and 15000 or 95000

    local dbResolved = ResolveQuestFromQuestieDB(questId, questTitle, inZoneHeader, currentAreaId, playerX, playerY)
    local liveResolved = false
    if not dbResolved then
        liveResolved = ResolveQuestFromQuestieLive(questId, inZoneHeader, currentAreaId, playerX, playerY)
    end

    for i = 1, #incompleteObjectives do
        local parsed = incompleteObjectives[i]
        if parsed.isMonster then
            if not dbResolved and not liveResolved then
                AddMobCandidate(targetBucket, parsed.name, defaultDist)
            end
        else
            local staticResolved = AddZoneFallbackMobs(targetBucket, zoneData, parsed)
            if not dbResolved and not liveResolved and not staticResolved then
                local ItemDB = _G.ItemDB
                if ItemDB and type(ItemDB.IdsByName) == "function" then
                    local itemIds = ItemDB.IdsByName(parsed.name)
                    if type(itemIds) == "table" then
                        for k = 1, #itemIds do
                            ResolveItemDroppers(itemIds[k], inZoneHeader, currentAreaId, playerX, playerY)
                        end
                    end
                end
            end
        end
    end
end

ScanModernQuestLog = function(zone, subZone, zoneData, currentAreaId, playerX, playerY)
    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    local currentHeader = ""

    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                currentHeader = info.title or ""
            elseif not info.isHidden and info.questID then
                local isComplete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
                local isReadyForTurnIn = C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(info.questID)
                if not isComplete and not isReadyForTurnIn then
                    local inZoneHeader = (zone ~= "" and strlower(currentHeader) == strlower(zone))
                        or (subZone ~= "" and strlower(currentHeader) == strlower(subZone))

                    wipe(incompleteObjectives)
                    local objectives = C_QuestLog.GetQuestObjectives(info.questID)
                    if objectives then
                        for j = 1, #objectives do
                            local obj = objectives[j]
                            if obj and not obj.finished then
                                local parsed = ParseObjectiveText(obj.text, obj.type, obj.finished)
                                if parsed then
                                    tinsert(incompleteObjectives, parsed)
                                end
                            end
                        end
                    end

                    if #incompleteObjectives > 0 then
                        ProcessQuestEntry(info.questID, info.title, inZoneHeader, zoneData, currentAreaId, playerX, playerY)
                    end
                end
            end
        end
    end
end

ScanClassicQuestLog = function(zone, subZone, zoneData, currentAreaId, playerX, playerY)
    if not GetNumQuestLogEntries then
        return
    end

    local savedSelection = GetQuestLogSelection and GetQuestLogSelection() or nil
    local numEntries = GetNumQuestLogEntries()
    local currentHeader = ""

    for i = 1, numEntries do
        local title, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
        if isHeader then
            currentHeader = title or ""
        elseif title and isComplete ~= 1 and isComplete ~= -1 then
            local inZoneHeader = (zone ~= "" and strlower(currentHeader) == strlower(zone))
                or (subZone ~= "" and strlower(currentHeader) == strlower(subZone))

            wipe(incompleteObjectives)
            local numObjectives = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0
            for j = 1, numObjectives do
                local text, objType, finished = GetQuestLogLeaderBoard(j, i)
                if not finished then
                    local parsed = ParseObjectiveText(text, objType, finished)
                    if parsed then
                        tinsert(incompleteObjectives, parsed)
                    end
                end
            end

            if #incompleteObjectives > 0 then
                ProcessQuestEntry(questID, title, inZoneHeader, zoneData, currentAreaId, playerX, playerY)
            end
        end
    end

    if savedSelection and SelectQuestLogEntry and savedSelection > 0 then
        SelectQuestLogEntry(savedSelection)
    end
end

SortZoneMobsByDistance = function(a, b)
    local da = mobBestDistSq[strlower(a)] or 999999
    local db = mobBestDistSq[strlower(b)] or 999999
    if da ~= db then
        return da < db
    end
    return a < b
end

function ATM:ScanActiveQuestMobs(zone, subZone)
    wipe(zoneMobs)
    wipe(subZoneMobs)
    wipe(fallbackQuestMobs)
    wipe(orderedMobs)
    wipe(allAreaMobs)
    wipe(seenMobs)
    wipe(mobBestDistSq)

    zone = zone or ""
    subZone = subZone or ""
    local zoneData = self.ZoneQuestMobDB[zone]
    local currentAreaId, playerX, playerY = GetPlayerMapLocation(zone)

    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        ScanModernQuestLog(zone, subZone, zoneData, currentAreaId, playerX, playerY)
    else
        ScanClassicQuestLog(zone, subZone, zoneData, currentAreaId, playerX, playerY)
    end

    if #zoneMobs > 1 then
        tsort(zoneMobs, SortZoneMobsByDistance)
    end

    -- Subzone static mobs supplement active zone quests only when Questie DB did not already resolve exact zone mobs.
    if #zoneMobs == 0 and not _G.QuestDB and #fallbackQuestMobs > 0 and zoneData and zoneData.subzones and subZone ~= "" then
        local staticList = zoneData.subzones[subZone]
        if staticList then
            for i = 1, #staticList do
                AddMobCandidate(subZoneMobs, staticList[i], 20000)
            end
        end
    end

    for i = 1, #zoneMobs do
        local m = zoneMobs[i]
        tinsert(allAreaMobs, m)
        if not (self.IsMobTemporarilyExcluded and self:IsMobTemporarilyExcluded(m)) then
            tinsert(orderedMobs, m)
        end
    end
    for i = 1, #subZoneMobs do
        local m = subZoneMobs[i]
        tinsert(allAreaMobs, m)
        if not (self.IsMobTemporarilyExcluded and self:IsMobTemporarilyExcluded(m)) then
            tinsert(orderedMobs, m)
        end
    end
    if (#zoneMobs == 0 and #subZoneMobs == 0) and (not AutoTagMacroDB or AutoTagMacroDB.includeOtherZoneQuests ~= false) then
        for i = 1, #fallbackQuestMobs do
            local m = fallbackQuestMobs[i]
            tinsert(allAreaMobs, m)
            if not (self.IsMobTemporarilyExcluded and self:IsMobTemporarilyExcluded(m)) then
                tinsert(orderedMobs, m)
            end
        end
    end

    self:Debug(
        "Scanned zone='" .. zone .. "' (areaId=" .. tostring(currentAreaId or "nil") .. ") subZone='" .. subZone .. "': "
        .. tostring(#zoneMobs) .. " zone mob(s), "
        .. tostring(#subZoneMobs) .. " subzone mob(s), "
        .. tostring(#fallbackQuestMobs) .. " other quest mob(s)."
    )

    return orderedMobs
end

function ATM:IsTrackedMobName(mobName)
    if type(mobName) ~= "string" or mobName == "" then
        return false
    end
    return seenMobs[strlower(mobName)] == true
end
