local Game = require("Game")
local Locations = {}
local snapshots, remaining, scannedAt = nil, {}, 0
local excludedMaps = { test = true, huanshushi = true, xuesesenlin = true }
local categories = {
    { field = "HupoItemData", fragment = "杀气琥珀", itemID = "Item_Piece_002" },
    { field = "HeiShiItemData", fragment = "黑石", itemID = "Item_Piece_001" },
    { field = "MemoryFlowerData" }, { field = "YaoShiItemData" }, { field = "PrimaryItemData" },
    { field = "WeaponItemDatas" }, { field = "ShaChiWeaponItemDatas" },
    { field = "AccessoryItemDatas" }, { field = "MedicineItemDatas" },
    { field = "RongShu" }, { field = "LongZhu" }, { field = "DaoCaoRen" }
}

local function collect(player)
    local class = StaticFindObject("/Game/PBZContent/UI/Component/BP_UIGameplayLogicComponent.BP_UIGameplayLogicComponent_C")
    local asset = player:GetComponentByClass(class).BP_MapItem
    local result, seen = {}, {}
    -- 先物化纯 Lua 值，再调用子系统，避免持有跨引擎调用的嵌套结构体引用。
    asset.MapItemDatas:ForEach(function(key, value)
        local mapID = Game.name(key:get())
        if excludedMaps[mapID:lower()] then return end
        local map = value:get()
        for _, category in ipairs(categories) do
            map[category.field]:ForEach(function(_, value)
                local item = value:get()
                local itemID = category.itemID or Game.name(item.ItemId)
                local point = item.Location
                local entry = { mapID = mapID, itemID = itemID, fragment = category.fragment,
                    x = point.X, y = point.Y, z = point.Z, save = Game.name(item.SaveGuidString),
                    domain = Game.name(item.MobDomainName), nodes = {} }
                item.NodeGuids:ForEach(function(_, node)
                    entry.nodes[#entry.nodes + 1] = Game.name(node:get())
                end)
                entry.id = table.concat({ itemID, mapID, entry.x, entry.y, entry.z }, ":")
                if not seen[entry.id] then result[#result + 1] = entry; seen[entry.id] = true end
            end)
        end
    end)
    return result
end

local function completed(entry, actors, system, pipeline)
    if entry.save ~= "" and entry.save ~= "None" and actors:HasSaveDataByActorID(FName(entry.save)) then return true end
    if entry.domain ~= "" and entry.domain ~= "None" and
        system.CompleteAddItemMobDomainNames:Contains(FName(entry.domain)) then return true end
    for _, node in ipairs(entry.nodes) do
        if pipeline.ExecuteNodeGuid:Contains(node) then return true end
    end
    return false
end

function Locations.refresh(player)
    if not snapshots then snapshots = collect(player) end
    if os.time() - scannedAt < 5 then return end
    local actors = Game.worldSubsystem(player, "PBZLevelActorManager")
    local system = Game.worldSubsystem(player, "PBZGameSystem")
    local pipeline = Game.worldSubsystem(player, "EventPipelineManager")
    remaining = {}
    for _, entry in ipairs(snapshots) do
        if not completed(entry, actors, system, pipeline) then remaining[#remaining + 1] = entry end
    end
    scannedAt = os.time()
end

function Locations.reset()
    snapshots, remaining, scannedAt = nil, {}, 0
end

function Locations.count(itemID)
    local total, available = 0, 0
    for _, entry in ipairs(snapshots or {}) do
        if entry.itemID:lower() == itemID:lower() then total = total + 1 end
    end
    for _, entry in ipairs(remaining) do
        if entry.itemID:lower() == itemID:lower() then available = available + 1 end
    end
    return total, available
end

function Locations.regions(itemID)
    local names, seen = {}, {}
    for _, entry in ipairs(remaining) do
        if entry.itemID:lower() == itemID:lower() then
            local name = Game.mapInfo(entry.mapID).name
            if not seen[name] then names[#names + 1] = name; seen[name] = true end
        end
    end
    return table.concat(names, "、")
end

function Locations.visible(settings, itemName)
    local result = {}
    for _, entry in ipairs(remaining) do
        local fragment = settings.fragmentsEnabled and entry.fragment
        local searched = settings.mapItemID and settings.mapItemID:lower() == entry.itemID:lower()
        if fragment or searched then
            local name = entry.fragment or itemName or entry.itemID
            result[#result + 1] = { id = entry.id, itemID = entry.itemID, kind = name,
                fragment = entry.fragment, label = entry.fragment == "杀气琥珀" and "琥珀" or
                    (entry.fragment == "黑石" and "黑石" or "物品"),
                mapID = entry.mapID, mapName = Game.mapInfo(entry.mapID).name,
                x = entry.x, y = entry.y, z = entry.z }
        end
    end
    return result
end

return Locations
