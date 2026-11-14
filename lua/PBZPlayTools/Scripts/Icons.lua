local paths = require("IconPaths")
local Icons = {}
local textures = {}

function Icons.texture(itemID)
    local path = paths[itemID]
    if not path then return nil end
    if not textures[itemID] or not textures[itemID]:IsValid() then
        local texture = LoadAsset(path)
        assert(texture:IsValid(), "图标加载失败：" .. itemID)
        textures[itemID] = texture
    end
    return textures[itemID]
end

return Icons
