local ReaderDogear = require("apps/reader/modules/readerdogear")

local BD = require("ui/bidi")
local Device = require("device")
local Geom = require("ui/geometry")
local IconWidget = require("ui/widget/iconwidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local logger = require("logger")

-- These constants are used to instruct ReaderDogear on which corner to paint the dogear
-- This is mainly used in Dual Page mode
-- Default is right top corner
ReaderDogear.SIDE_LEFT = 1
ReaderDogear.SIDE_RIGHT = 2
ReaderDogear.SIDE_BOTH = 3

function ReaderDogear:init()
    -- This image could be scaled for DPI (with scale_for_dpi=true, scale_factor=0.7),
    -- but it's as good to scale it to a fraction (1/32) of the screen size.
    -- For CreDocument, we should additionally take care of not exceeding margins
    -- to not overwrite the book text.
    -- For other documents, there is no easy way to know if valuable content
    -- may be hidden by the icon (kopt's page_margin is quite obscure).
    self.dogear_min_size = math.ceil(math.min(Screen:getWidth(), Screen:getHeight()) * (1 / 40))
    self.dogear_max_size = math.ceil(math.min(Screen:getWidth(), Screen:getHeight()) * (1 / 32))
    self.dogear_size = nil

    self.icon_right = nil
    self.icon_left = nil
    self.vgroup_right = nil
    self.vgroup_left = nil
    self.top_pad = nil

    self.right_ear = nil
    self.left_ear = nil

    self.dogear_y_offset = 0
    self.dimen = nil
    self.sides = self.SIDE_RIGHT
    self:setupDogear()
    self:resetLayout()
end

--[[
Calculates the rotation angle for a dogear icon based on the side and layout.

@param side number ReaderDogear.SIDE_LEFT or ReaderDogear.SIDE_RIGHT
@return number rotation angle in degrees
]]
function ReaderDogear:_getRotationAngle(side)
    local base_angle = BD.mirroredUILayout() and 90 or 0
    if side == self.SIDE_LEFT then
        return base_angle + 90
    end
    return base_angle
end

--[[
Creates an IconWidget for the dogear with the specified rotation angle.

@param rotation_angle number the rotation angle in degrees
@return IconWidget the created icon widget
]]
function ReaderDogear:_createDogearIcon(rotation_angle)
    return IconWidget:new({
        icon = "dogear.alpha",
        rotation_angle = rotation_angle,
        width = self.dogear_size,
        height = self.dogear_size,
        alpha = true, -- Keep the alpha layer intact
    })
end

--[[
Creates a complete dogear ear (icon + vertical group + container) for one side.

@param side number ReaderDogear.SIDE_LEFT or ReaderDogear.SIDE_RIGHT
@param icon IconWidget the dogear icon to use
@return table containing { ear, icon, vgroup } for the specified side
]]
function ReaderDogear:_createEar(side, icon)
    local vgroup = VerticalGroup:new({
        self.top_pad,
        icon,
    })

    local container_class = side == self.SIDE_LEFT and LeftContainer or RightContainer
    local ear = container_class:new({
        dimen = Geom:new({ w = Screen:getWidth(), h = self.dogear_y_offset + self.dogear_size }),
        vgroup,
    })

    return {
        ear = ear,
        icon = icon,
        vgroup = vgroup,
    }
end

--[[
Updates or creates the right dogear ear if size changed or missing.

@param size_changed boolean whether the dogear size has changed
]]
function ReaderDogear:_updateRightEar(size_changed)
    local right_missing = not self.right_ear

    if size_changed or right_missing then
        if self.right_ear then
            self.right_ear:free()
        end

        local rotation_angle = self:_getRotationAngle(self.SIDE_RIGHT)
        local icon = self:_createDogearIcon(rotation_angle)
        local result = self:_createEar(self.SIDE_RIGHT, icon)

        self.icon_right = result.icon
        self.vgroup_right = result.vgroup
        self.right_ear = result.ear
    end
end

--[[
Updates or creates the left dogear ear if size changed or missing.

@param size_changed boolean whether the dogear size has changed
]]
function ReaderDogear:_updateLeftEar(size_changed)
    local left_missing = not self.left_ear

    if size_changed or left_missing then
        if self.left_ear then
            self.left_ear:free()
        end

        local rotation_angle = self:_getRotationAngle(self.SIDE_LEFT)
        local icon = self:_createDogearIcon(rotation_angle)
        local result = self:_createEar(self.SIDE_LEFT, icon)

        self.icon_left = result.icon
        self.vgroup_left = result.vgroup
        self.left_ear = result.ear
    end
end

--[[
Creates or recreates the internal dogear widgets (ears) if the size has changed
or if they are missing. Ensures that the right and left dogear containers are
properly initialized and assigned, and updates the numeric child slot for
compatibility with upstream code.

@param new_dogear_size (optional) The desired size for the dogear; if not provided,
                        uses the maximum configured size.
]]
function ReaderDogear:setupDogear(new_dogear_size)
    if not new_dogear_size then
        new_dogear_size = self.dogear_max_size
    end

    local size_changed = new_dogear_size ~= self.dogear_size

    if size_changed or not self.right_ear or not self.left_ear then
        self.dogear_size = new_dogear_size
        self.top_pad = VerticalSpan:new({ width = self.dogear_y_offset })

        self:_updateRightEar(size_changed)
        self:_updateLeftEar(size_changed)

        self:_ensureNumericChildCompatibility()
    end
end

--[[
Ensure numeric child slot for backward compatibility.

Historically the upstream codebase expects `ReaderDogear` to expose its primary
container at `self[1]`. This plugin implementation may use named fields such as
`right_ear` and `left_ear` instead. To remain compatible with upstream callers
(including subprocesses that index `self.ui.view.dogear[1]`), mirror the
primary named container onto numeric slot `self[1]`.

This keeps the plugin implementation clean while avoiding crashes caused by
legacy code paths that rely on `self[1]`.
]]
function ReaderDogear:_ensureNumericChildCompatibility()
    -- Primary slot used by upstream is `self[1]`.
    self[1] = self.right_ear
end

function ReaderDogear:paintTo(bb, x, y)
    logger.dbg("ComicReaderDogear:paintTo with sides", self.sides)

    if self.sides == self.SIDE_RIGHT or self.sides == self.SIDE_BOTH then
        self.right_ear:paintTo(bb, x, y)
    end

    -- Exit early if we don't need to paint left side.
    if self.sides ~= self.SIDE_LEFT and self.sides ~= self.SIDE_BOTH then
        return
    end

    self.left_ear:paintTo(bb, x, y)
end

function ReaderDogear:updateDogearOffset()
    if not self.ui.rolling then
        return
    end
    self.dogear_y_offset = 0
    if self.view.view_mode == "page" then
        self.dogear_y_offset = self.ui.document:getHeaderHeight()
    end

    if self.right_ear or self.left_ear then
        self.top_pad.width = self.dogear_y_offset
    end

    if self.right_ear then
        self.right_ear.dimen.h = self.dogear_y_offset + self.dogear_size
        self.vgroup_right:resetLayout()
    end

    if self.left_ear then
        self.left_ear.dimen.h = self.dogear_y_offset + self.dogear_size
        self.vgroup_left:resetLayout()
    end
end

function ReaderDogear:resetLayout()
    self.right_ear.dimen.w = Screen:getWidth()
    self.left_ear.dimen.w = Screen:getWidth()

    self:_ensureNumericChildCompatibility()
end

function ReaderDogear:getRefreshRegion()
    -- We can't use self.dimen because of the width/height quirks of Left/RightContainer, so use the IconWidget's...
    return self.icon_right.dimen:combine(self.icon_left.dimen)
end

-- @param visible boolean
-- @param side number 1 only left, 2 only right, if 3 both sides, nil == 2
function ReaderDogear:onSetDogearVisibility(visible, sides)
    logger.dbg("ReaderDogear:onSetDogearVisibility", visible, sides)
    self.sides = sides or self.SIDE_RIGHT
    self.view.dogear_visible = visible
    return true
end

return ReaderDogear
