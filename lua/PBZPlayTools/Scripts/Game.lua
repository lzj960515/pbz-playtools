local UEHelpers = require("UEHelpers")
local Game = {}
local maps = {}

function Game.name(value)
    if type(value) == "string" then return value end
    return value:ToString()
end

function Game.player()
    local player = UEHelpers.GetPlayer()
    if not player:IsValid() then return nil, "本地角色尚未出现，请进入存档。" end
    if not player:IsPlayerControlled() then return nil, "角色尚未由玩家接管。" end
    return player
end

function Game.worldSubsystem(player, name)
    local library = StaticFindObject("/Script/Engine.Default__SubsystemBlueprintLibrary")
    return library:GetWorldSubsystem(player, StaticFindObject("/Script/ProjectPBZ." .. name))
end

function Game.localizedText(flowText)
    local key = Game.name(flowText.Key)
    if key == "" or key == "None" then return "" end
    local library = StaticFindObject("/Script/ProjectPBZ.Default__PBZBlueprintFunctionLibrary")
    return Game.name(library:MakeTextByKey(key))
end

function Game.mapInfo(id)
    local key = id:lower()
    if maps[key] then return maps[key] end
    local bell = StaticFindObject("/Script/ProjectPBZ.Default__BellManager")
    local data = bell:GetMapData(FName(id))
    local level = Game.name(data.LevelName):lower()
    local name = Game.localizedText(data.MapName)
    if name == "" then name = id end
    maps[key] = { name = name, level = level }
    return maps[key]
end

function Game.sameLevel(player, currentId, targetId)
    local target = Game.mapInfo(targetId).level
    local current = Game.mapInfo(currentId).level
    local world = Game.name(player:GetWorld():GetFName()):lower()
    local function levelName(value)
        return value:match("([^/%.]+)$")
    end
    return currentId:lower() == targetId:lower() or
        (target ~= "" and target ~= "none" and
        (levelName(target) == levelName(current) or levelName(target) == levelName(world)))
end

return Game
