local Game = require("Game")
local Equipment = {}
local slots = {}
local report = { enabled = false, switchCount = 0, preparedCount = 0, lastWeapon = "", error = "" }

local function ownedWeapons(backpack, isMain)
    local owned = isMain and backpack.MainWeaponInfos or backpack.ShaqiWeaponInfos
    local result = {}
    owned:ForEach(function(key, _)
        result[#result + 1] = Game.name(key:get())
    end)
    return result
end

local function prepareSpare(backpack, isMain, index)
    local equipped = isMain and backpack.MainWeapons or backpack.ShaqiWeapons
    if index < 0 or index > 1 or #equipped < 2 then return end
    local current = Game.name(equipped[index + 1])
    local spare = Game.name(equipped[2 - index])
    if current == "None" or spare == "None" then return end
    local candidates = {}
    for _, id in ipairs(ownedWeapons(backpack, isMain)) do
        if id ~= current and not backpack:IsWeaponLocked(FName(id), isMain) then
            candidates[#candidates + 1] = id
        end
    end
    if #candidates == 0 then return end
    local nextId = candidates[math.random(#candidates)]
    if nextId == spare then return end
    if isMain then
        backpack:ReplaceWeaponByIndex(FName(nextId), 1 - index)
    else
        backpack:ReplaceShaChiWeaponByIndex(FName(nextId), 1 - index)
    end
    report.preparedCount = report.preparedCount + 1
    report.lastWeapon = nextId
end

function Equipment.reset()
    slots = {}
    report = { enabled = false, switchCount = 0, preparedCount = 0, lastWeapon = "", error = "" }
end

function Equipment.update(player, settings)
    local backpack = Game.worldSubsystem(player, "PBZBackPackSubsystem")
    report.enabled = settings.randomWeapons or settings.randomShadowWeapons
    for _, definition in ipairs({ { main = true, enabled = settings.randomWeapons },
                                { main = false, enabled = settings.randomShadowWeapons } }) do
        local key = definition.main and "main" or "shadow"
        if not definition.enabled then
            slots[key] = nil
        else
            local index = definition.main and backpack:GetCurrentMainWeaponIndex()
                or backpack:GetCurrentShaqiWeaponIndex()
            local previous = slots[key]
            if previous == nil or previous ~= index then
                if previous ~= nil then report.switchCount = report.switchCount + 1 end
                slots[key] = index
                if not backpack:HasForcedWeaponLoadout() then
                    prepareSpare(backpack, definition.main, index)
                end
            end
        end
    end
    return report
end

function Equipment.upgrade(player)
    local backpack = Game.worldSubsystem(player, "PBZBackPackSubsystem")
    local result = { total = 0, succeeded = 0, changed = 0, failed = {},
        main = { total = 0, succeeded = 0 }, shadow = { total = 0, succeeded = 0 } }
    for _, category in ipairs({ { main = true, name = "主武器", report = result.main },
                                { main = false, name = "影之武装", report = result.shadow } }) do
        for _, id in ipairs(ownedWeapons(backpack, category.main)) do
            result.total = result.total + 1
            category.report.total = category.report.total + 1
            local name = FName(id)
            local before = backpack:GetWeaponLevel(name, category.main)
            if before < 30 then backpack:UpgradeWeapon(name, category.main, 30 - before) end
            local actual = backpack:GetWeaponLevel(name, category.main)
            if actual > before then result.changed = result.changed + 1 end
            if actual >= 30 then
                result.succeeded = result.succeeded + 1
                category.report.succeeded = category.report.succeeded + 1
            else
                result.failed[#result.failed + 1] = { category = category.name,
                    weaponID = id, actualLevel = actual, maxLevel = backpack:GetWeaponMaxLevel(name, category.main) }
            end
        end
    end
    result.complete = result.total > 0 and #result.failed == 0
    return result
end

return Equipment
