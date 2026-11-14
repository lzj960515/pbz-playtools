local Game = require("Game")
local Indicator = require("Indicator")
local Tracking = {}

function Tracking.update(player, entries, selectedID)
    if not selectedID or selectedID == "" or #entries == 0 then
        Indicator.clear()
        return { visible = false }
    end
    local location = player:K2_GetActorLocation()
    local map = Game.worldSubsystem(player, "MapSubsystem")
    local currentMap = Game.name(map:GetMapIDByLocation(location))
    local target
    for _, entry in ipairs(entries) do
        if entry.id == selectedID then
            local dx, dy, dz = entry.x - location.X, entry.y - location.Y, entry.z - location.Z
            target = { id = entry.id, itemID = entry.itemID, kind = entry.kind, mapName = entry.mapName,
                crossMap = not Game.sameLevel(player, currentMap, entry.mapID),
                x = entry.x, y = entry.y, z = entry.z,
                distance = math.floor(math.sqrt(dx * dx + dy * dy + dz * dz) / 100) }
            break
        end
    end
    return { target = target, visible = Indicator.update(player, target) }
end

return Tracking
