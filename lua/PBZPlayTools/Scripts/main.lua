local json = require("json")
local config = require("config")
local Game = require("Game")
local Equipment = require("Equipment")
local Locations = require("MapLocations")
local ItemSearch = require("ItemSearch")
local Tracking = require("Tracking")
local MapPins = require("MapPins")
local Indicator = require("Indicator")
local activeAddress, session, lastRequest, lastStatusSecond, result, searchResult

local function readControl()
    local file = assert(io.open(config.directory .. "/control.json", "rb"))
    local text = file:read("*a")
    file:close()
    return assert(json.decode(text))
end

local function selectLocation(id)
    local control = readControl()
    control.settings.mapTarget = control.settings.mapTarget == id and "" or id
    local file = assert(io.open(config.directory .. "/control.json", "wb"))
    file:write(json.encode(control))
    file:close()
end

local function writeStatus(state)
    state.protocol = 1
    state.version = config.version
    state.updatedAt = os.time() * 1000
    local file = assert(io.open(config.directory .. "/status.json", "wb"))
    file:write(json.encode(state))
    file:close()
end

local function visibleLocations(settings)
    return Locations.visible(settings, ItemSearch.itemName(settings.mapItemID))
end

local function update()
    local searchChanged = false
    local control = readControl()
    local settings = control.settings
    local state = { ready = false, revision = control.revision,
        randomWeapons = settings.randomWeapons, randomShadowWeapons = settings.randomShadowWeapons }
    local player, playerStatus = Game.player()
    state.playerStatus = playerStatus
    if player then
        local address = player:GetAddress()
        if activeAddress ~= address then
            activeAddress = address
            session = tostring(address) .. "-" .. os.time()
            lastRequest, result = nil, nil
            Equipment.reset()
            Locations.reset()
            Indicator.clear()
            MapPins.clear()
            searchResult = nil
        end
        state.ready, state.session = true, session
        state.playerName = player:GetFullName()
        state.equipment = Equipment.update(player, settings)
        local needsLocations = settings.fragmentsEnabled or (settings.mapItemID and settings.mapItemID ~= "") or control.itemSearch
        local locationsOk, locationsError = true, nil
        if needsLocations then locationsOk, locationsError = pcall(Locations.refresh, player) end
        local search = control.itemSearch
        if search and (not searchResult or searchResult.requestId ~= search.id) then
            searchChanged = true
            if locationsOk then
                local ok, value = pcall(ItemSearch.find, search)
                searchResult = ok and value or { requestId = search.id, error = tostring(value) }
            else
                searchResult = { requestId = search.id, error = tostring(locationsError) }
            end
        end
        state.items = searchResult
        local entries = {}
        if locationsOk and needsLocations then
            local ok, value = pcall(visibleLocations, settings)
            if ok then entries = value else locationsOk, locationsError = false, value end
        end
        local fragmentCount = 0
        for _, entry in ipairs(entries) do if entry.fragment then fragmentCount = fragmentCount + 1 end end
        state.fragments = { enabled = settings.fragmentsEnabled, count = fragmentCount }
        state.mapItemID = settings.mapItemID
        local mapOk, map = pcall(MapPins.update, player, settings, entries, selectLocation)
        state.map = mapOk and map or { error = tostring(map) }
        if not locationsOk then state.map.error = tostring(locationsError) end
        Indicator.setMapOpen(state.map.opened == true)
        local trackingOk, tracking = pcall(Tracking.update, player, entries, settings.mapTarget)
        state.tracking = trackingOk and tracking or { error = tostring(tracking) }
        local request = control.upgradeRequest
        if request and request.session == session and request.id ~= lastRequest then
            lastRequest = request.id
            if request.action == "upgradeAllWeapons" and math.abs(os.time() * 1000 - request.issuedAt) <= 10000 then
                local upgradeOk, upgrade = pcall(Equipment.upgrade, player)
                result = { id = request.id, ok = upgradeOk }
                if upgradeOk then result.report = upgrade else result.error = tostring(upgrade) end
            end
        end
        state.result = result
    else
        if activeAddress then Locations.reset(); MapPins.clear(); Indicator.clear(); Indicator.setMapOpen(false) end
        activeAddress = nil
    end
    if lastStatusSecond ~= os.time() or searchChanged then
        lastStatusSecond = os.time()
        writeStatus(state)
    end
end

-- 运行边界把错误交给工具显示，框架与原游戏继续各自执行。
local function tick()
    local ok, error = pcall(update)
    if not ok then
        print("[PBZPlayTools] " .. tostring(error) .. "\n")
        writeStatus({ ready = false, error = tostring(error) })
    end
end

writeStatus({ ready = false, message = "UE4SS 插件已加载，等待进入存档。" })
LoopAsync(100, function()
    ExecuteInGameThread(tick)
    return false
end)
print("[PBZPlayTools] 0.6.3 loaded\n")
