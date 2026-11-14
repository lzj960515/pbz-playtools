local Game = require("Game")
local Locations = require("MapLocations")
local Search = {}
local catalog

local function loadCatalog()
    local tableAsset = LoadAsset("/Game/PBZContent/DataTable/Item/DT_InventoryData.DT_InventoryData")
    local tableLibrary = StaticFindObject("/Script/Engine.Default__DataTableFunctionLibrary")
    local backpack = StaticFindObject("/Script/ProjectPBZ.Default__PBZBackPackSubsystem")
    assert(tableAsset:IsValid(), "物品表加载失败")
    -- 表行名称不等于物品 ID；按游戏的数据列读取真正的 ItemId。
    local ids = tableLibrary:GetDataTableColumnAsString(tableAsset, FName("ItemId"))
    assert(#ids > 0, "物品目录读取为空")
    local result = {}
    for _, value in ipairs(ids) do
        local id = Game.name(value:get())
        local data = backpack:GetPropData(FName(id))
        local name = Game.localizedText(data.ItemName)
        if name ~= "" then
            result[#result + 1] = { id = id, name = name,
                description = Game.localizedText(data.ItemDescription), task = data.ItemDetailType == 2 }
        end
    end
    assert(#result > 0, "物品名称读取失败（" .. #ids .. " 项）")
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

local function matchScore(item, query)
    local name = item.name:lower():gsub("%s+", "")
    if name == query then return 10000 end
    local at = name:find(query, 1, true)
    if at then return 8000 - at - #name end
    -- 按 UTF-8 字符顺序匹配；“金弹”可命中“金色弹药”。
    local cursor, first, last = 1, nil, nil
    for _, codepoint in utf8.codes(query) do
        local character = utf8.char(codepoint)
        local start, finish = name:find(character, cursor, true)
        if not start then first = nil; break end
        first, last, cursor = first or start, finish, finish + 1
    end
    if first then return 6000 - (last - first) - #name end
    if item.id:lower():find(query, 1, true) then return 3000 end
    if item.description:lower():find(query, 1, true) then return 1000 end
end

local function describeLocation(item)
    local count, available = Locations.count(item.id)
    local source
    if count > 0 then
        source = available > 0 and (available .. " 处未取得 · " .. Locations.regions(item.id))
            or "已全部取得"
    elseif item.task then
        source = "任务物品，无地图位置记录"
    else
        source = "无地图位置记录"
    end
    return { id = item.id, name = item.name, description = item.description,
        locationCount = count, remainingCount = available, source = source }
end

function Search.find(request)
    if not catalog then catalog = loadCatalog() end
    local query = request.query:lower():gsub("%s+", "")
    local matches = {}
    for _, item in ipairs(catalog) do
        local score = matchScore(item, query)
        if score then matches[#matches + 1] = { item = item, score = score } end
    end
    table.sort(matches, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.item.id < b.item.id
    end)
    local results = {}
    for index = 1, math.min(#matches, 80) do
        results[#results + 1] = describeLocation(matches[index].item)
    end
    return { requestId = request.id, query = request.query, results = results,
        total = #matches, catalogCount = #catalog }
end

function Search.itemName(id)
    if not catalog then return id end
    for _, item in ipairs(catalog) do if item.id == id then return item.name end end
    return id
end

return Search
