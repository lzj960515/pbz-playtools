local Game = require("Game")
local Icons = require("Icons")
local MapPins = {}
local owner
local pins = {}
local clickTargets = {}
local onSelect
local hookInstalled = false
local sequence = 0
-- 蓝图结构体在 Lua 中使用带 GUID 的反射名称；Puerts 的简写名称不适用。
local MAP_MEMBERS_PROPERTY = "AllowedMapID_3_C6A53F2F462CB1195CDCD7909353B12E"
local mergeGroups = { pangzhen = { pangzhen = true, houjie = true },
                      meiguhu = { meiguhu = true, meigu_yiji = true } }

function MapPins.clear()
    for _, pin in pairs(pins) do
        if pin.button:IsValid() then pin.button:RemoveFromParent() end
    end
    owner, pins, clickTargets = nil, {}, {}
end

local function bindClicks()
    if hookInstalled then return end
    -- 原生按钮点击取得焦点；只把本插件标记的焦点事件转成地图选点。
    RegisterHook("/Script/UMG.Widget:SetFocus", function(context)
        local id = clickTargets[context:get():GetAddress()]
        if id then onSelect(id) end
    end)
    hookInstalled = true
end

local function activeMap()
    for _, view in ipairs(FindAllOf("WB_MapNew_C") or {}) do
        if view.Gadget:IsValid() and not view.BigMapMode then
            local input = { Result = false }
            view:CanExecuteUIInput(input)
            if input.Result and view:IsVisible() then return view end
        end
    end
end

local function allowedMaps(view)
    local display = Game.name(view.CurrentDisplayMapID):lower()
    local members = { [display] = true }
    for _, group in pairs(mergeGroups) do if group[display] then members = group; break end end
    local allowed = {}
    for id in pairs(members) do allowed[id] = true end
    view.MapIDAsset.Maps:ForEach(function(key, value)
        local id = Game.name(key:get()):lower()
        if not members[id] then return end
        local mapIDs = value:get()[MAP_MEMBERS_PROPERTY]
        mapIDs:ForEach(function(_, name)
            allowed[Game.name(name:get()):lower()] = true
        end)
    end)
    return allowed
end

local function createPin(view, entry)
    sequence = sequence + 1
    local suffix = tostring(os.time()) .. "_" .. sequence
    local button = StaticConstructObject(StaticFindObject("/Script/UMG.Button"),
        view.WidgetTree, FName("PBZLocationPin_" .. suffix))
    local texture = Icons.texture(entry.itemID)
    local icon
    if texture then
        icon = StaticConstructObject(StaticFindObject("/Script/UMG.Image"),
            view.WidgetTree, FName("PBZLocationIcon_" .. suffix))
        icon:SetBrushFromTexture(texture, false)
        icon:SetVisibility(3)
        local content = button:AddChild(icon)
        content:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        button:SetBackgroundColor({ R = 1, G = 1, B = 1, A = 0 })
    else
        local text = StaticConstructObject(StaticFindObject("/Script/UMG.TextBlock"),
            view.WidgetTree, FName("PBZLocationLabel_" .. suffix))
        text:SetText(FText(entry.label))
        text:SetJustification(1)
        button:AddChild(text)
    end
    button:SetToolTipText(FText(entry.kind))
    button.OnClicked:Add(button, FName("SetFocus"))
    -- 原地图的透明点击面在根 Canvas；标记放在其上方才收得到鼠标点击。
    local slot = view.CanvasPanel:AddChildToCanvas(button)
    slot:SetAlignment({ X = 0.5, Y = 0.5 })
    local layout = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    slot:SetZOrder(layout:SlotAsCanvasSlot(view.MapClickSurface):GetZOrder() + 1)
    clickTargets[button:GetAddress()] = entry.id
    local pin = { button = button, slot = slot, icon = icon }
    pins[entry.id] = pin
    return pin
end

local function bellIconSize(view, layout)
    -- 读铃铛当前的实际尺寸，随原地图缩放，避免固定大按钮遮挡地图。
    local size
    view.BellIconArray:ForEach(function(_, value)
        if size then return end
        local bell = value:get()
        if bell:IsValid() then
            local current = layout:SlotAsCanvasSlot(bell):GetSize()
            size = { X = current.X, Y = current.Y }
        end
    end)
    return size or { X = view.IconSizeBell.X, Y = view.IconSizeBell.Y }
end

function MapPins.update(player, settings, entries, selectTarget)
    onSelect = selectTarget
    if not settings.fragmentsEnabled and (not settings.mapItemID or settings.mapItemID == "") then
        MapPins.clear(); return { opened = false }
    end
    local view = activeMap()
    if not view then MapPins.clear(); return { opened = false } end
    if not owner or owner:GetAddress() ~= view:GetAddress() then MapPins.clear(); owner = view end
    bindClicks()
    local allowed = allowedMaps(view)
    local layout = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    local mapSlot = layout:SlotAsCanvasSlot(view.MapOverlay)
    local size, offset = mapSlot:GetSize(), mapSlot:GetPosition()
    local viewportPixels = layout:GetViewportSize(view)
    local dpi = layout:GetViewportScale(view)
    local viewport = { X = viewportPixels.X / dpi, Y = viewportPixels.Y / dpi }
    local iconSize = bellIconSize(view, layout)
    local map = Game.worldSubsystem(player, "MapSubsystem")
    local shown, count, visibleCount, placements = {}, 0, 0, {}
    for _, entry in ipairs(entries) do
        if allowed[entry.mapID:lower()] then
            local pin = pins[entry.id] or createPin(view, entry)
            local uv = map:ProjectWorldLocationToMap({ X = entry.x, Y = entry.y, Z = entry.z }, FName(entry.mapID))
            -- 原 Map.js：根 Canvas 就是视口逻辑空间，坐标 = UV × 地图尺寸 + 地图左上角。
            -- FGeometry 无反射字段，UE4SS 函数返回时会丢失内容，不能用它转换坐标。
            local position = { X = uv.X * size.X + offset.X, Y = uv.Y * size.Y + offset.Y }
            pin.slot:SetPosition(position)
            pin.slot:SetSize(iconSize)
            local visible = position.X >= 0 and position.X <= viewport.X and
                position.Y >= 0 and position.Y <= viewport.Y
            pin.button:SetVisibility(visible and 0 or 1)
            local selected = settings.mapTarget == entry.id
            if pin.icon then
                pin.icon:SetColorAndOpacity(selected and { R = 1, G = 0.82, B = 0.35, A = 1 }
                    or { R = 1, G = 1, B = 1, A = 1 })
                local scale = selected and 1.18 or 1
                pin.button:SetRenderScale({ X = scale, Y = scale })
            else
                pin.button:SetBackgroundColor(selected and { R = 1, G = 0.68, B = 0.15, A = 1 }
                    or { R = 0.18, G = 0.38, B = 0.85, A = 0.95 })
            end
            shown[entry.id] = true
            count = count + 1
            if visible then visibleCount = visibleCount + 1 end
            placements[#placements + 1] = { id = entry.id, x = position.X, y = position.Y, visible = visible }
        end
    end
    for id, pin in pairs(pins) do
        if not shown[id] then
            clickTargets[pin.button:GetAddress()] = nil
            pin.button:RemoveFromParent()
            pins[id] = nil
        end
    end
    return { opened = true, markers = count, visibleMarkers = visibleCount,
        displayMap = Game.name(view.CurrentDisplayMapID), mapSize = size, mapOffset = offset,
        viewport = viewport, placements = placements }
end

return MapPins
