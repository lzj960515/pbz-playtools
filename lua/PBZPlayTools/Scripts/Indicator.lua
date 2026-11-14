local Indicator = {}
local Icons = require("Icons")
local widget
local mapOpen = false
local CLASS_PATH = "/Game/PBZContent/UI/FrontEnd/Sense/W_Sense_Quest.W_Sense_Quest_C"

function Indicator.clear()
    if widget and widget:IsValid() then widget:RemoveFromParent() end
    widget = nil
end

function Indicator.setMapOpen(opened)
    mapOpen = opened
    if opened and widget and widget:IsValid() then widget:SetVisibility(1) end
end

local function create(player)
    local class = LoadAsset(CLASS_PATH)
    local library = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local controller = player:GetController()
    widget = library:Create(player, class, controller)
    widget:AddToViewport(50)
    widget:StopAnimationsAndLatentActions()
    widget:SetDesiredSizeInViewport({ X = 256, Y = 256 })
    widget:SetAlignmentInViewport({ X = 0.5, Y = 0.5 })
    widget:SetVisibility(3)
    widget:SetRenderOpacity(1)
    widget.icon:SetVisibility(1)
    -- 原控件带有设计期占位光效；碎片只显示物品图标。
    widget.Glow:SetVisibility(1)
    widget.icon:SetRenderScale({ X = 0.5, Y = 0.5 })
    widget.DIstanceBox:SetVisibility(3)
    widget.DistanceText:SetWrapTextWidth(260)
end

local function dot(direction, x, y, z)
    return direction.X * x + direction.Y * y + direction.Z * z
end

local function place(player, target)
    local controller = player:GetController()
    local layout = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    local size = layout:GetViewportSize(player)
    local cx, cy = size.X * 0.5, size.Y * 0.5
    if target.crossMap then
        widget.Arrow:SetVisibility(1)
        widget.DistanceText:SetPBZFormatText(FText("前往" .. target.mapName))
        widget:SetPositionInViewport({ X = cx, Y = size.Y * 0.2 }, true)
        return
    end

    local camera = controller.PlayerCameraManager
    local cameraLocation = camera:GetCameraLocation()
    local rotation = camera:GetCameraRotation()
    local mathLibrary = StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    local forward = mathLibrary:GetForwardVector(rotation)
    local right = mathLibrary:GetRightVector(rotation)
    local up = mathLibrary:GetUpVector(rotation)
    local dx, dy, dz = target.x - cameraLocation.X, target.y - cameraLocation.Y, target.z - cameraLocation.Z
    local forwardDot, rightDot, upDot = dot(forward, dx, dy, dz), dot(right, dx, dy, dz), dot(up, dx, dy, dz)
    local margin = size.Y * 0.12
    local hx, hy = cx - margin, cy - margin
    local screen = { X = 0, Y = 0 }
    local projected = forwardDot > 0 and controller:ProjectWorldLocationToScreen(
        { X = target.x, Y = target.y, Z = target.z }, screen, true)
    local x, y = rightDot, -upDot
    if projected then x, y = screen.X - cx, screen.Y - cy end
    local inside = projected and (math.abs(x / hx) ^ 2.8 + math.abs(y / hy) ^ 2.8 <= 1)
    if not inside then
        if math.abs(x) + math.abs(y) < 0.001 then x, y = 0, 1 end
        local scale = (math.abs(x / hx) ^ 2.8 + math.abs(y / hy) ^ 2.8) ^ (-1 / 2.8)
        x, y = x * scale, y * scale
    end
    widget.Arrow:SetVisibility(inside and 1 or 3)
    if not inside then widget.Arrow:SetRenderTransformAngle(math.deg(math.atan(y, x))) end
    widget.DistanceText:SetPBZFormatText(FText(target.distance .. " 米"))
    widget:SetPositionInViewport({ X = cx + x, Y = cy + y }, true)
end

function Indicator.update(player, target)
    if not target then Indicator.clear(); return false end
    if mapOpen then return false end
    if not widget or not widget:IsValid() then create(player) end
    local texture = Icons.texture(target.itemID)
    if texture then
        widget.icon:SetBrushFromTexture(texture, false)
        widget.icon:SetVisibility(3)
    end
    widget:SetVisibility(3)
    place(player, target)
    return true
end

return Indicator
