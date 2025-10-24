-- Tests for comicreader ReaderDogear numeric child slot compatibility
-- Ensures the plugin mirrors its named container fields onto numeric slot `self[1]`
-- so upstream code (including subprocesses) that index `view.dogear[1]` keeps working.

-- Minimal mocked dependencies used by the plugin
local mocked_modules = {}

-- Simple logger
package.loaded["logger"] = {
    dbg = function() end,
}

-- Base ReaderDogear (the plugin augments this)
mocked_modules["apps/reader/modules/readerdogear"] = {}

-- UI bidi helper used by plugin
mocked_modules["ui/bidi"] = {
    mirroredUILayout = function()
        return false
    end,
}

-- Device screen mock (provide width/height helpers)
mocked_modules["device"] = {
    screen = {
        getWidth = function()
            return 800
        end,
        getHeight = function()
            return 600
        end,
        -- scaleBySize used elsewhere, provide a no-op scaling
        scaleBySize = function(_, v)
            return v
        end,
        isColorEnabled = function()
            return false
        end,
    },
}

-- Geometry constructor used by plugin; return the table passed in
mocked_modules["ui/geometry"] = {
    new = function(_, t)
        return t or {}
    end,
}

-- Minimal IconWidget mock; :new returns a table with a dimen field
mocked_modules["ui/widget/iconwidget"] = {
    new = function(_, params)
        return {
            rotation_angle = params.rotation_angle or 0,
            dimen = { w = params.width or 0, h = params.height or 0 },
        }
    end,
}

-- VerticalGroup mock: accept members, expose resetLayout
mocked_modules["ui/widget/verticalgroup"] = {
    new = function(_)
        local obj = { resetLayout = function() end }
        return obj
    end,
}

-- VerticalSpan mock: hold width property
mocked_modules["ui/widget/verticalspan"] = {
    new = function(_, params)
        return { width = params and params.width or 0 }
    end,
}

-- Simple container mocks: LeftContainer and RightContainer
local function make_container()
    return {
        dimen = { w = 0, h = 0 },
        resetLayout = function() end,
        free = function() end,
        paintTo = function() end,
    }
end

mocked_modules["ui/widget/container/rightcontainer"] = {
    new = function(_, params, _)
        local c = make_container()
        if params and params.dimen then
            c.dimen = params.dimen
        end
        return c
    end,
}
mocked_modules["ui/widget/container/leftcontainer"] = {
    new = function(_, params, _)
        local c = make_container()
        if params and params.dimen then
            c.dimen = params.dimen
        end
        return c
    end,
}

-- Provide gettext used elsewhere
package.loaded["gettext"] = function(x)
    return x
end

-- Override require to resolve our mocked modules first
local original_require = require
local mock_require -- Declare at module level so it's accessible to all test suites
mock_require = function(module_name)
    if mocked_modules[module_name] then
        return mocked_modules[module_name]
    end
    return original_require(module_name)
end

-- Temporarily replace global require with mock for plugin's internal requires
_G.require = mock_require
local ReaderDogearPlugin = original_require("src/readerdogear")
_G.require = original_require

describe("ComicReader ReaderDogear numeric slot compatibility", function()
    it("populates self[1] after setupDogear and resetLayout", function()
        local instance = {}
        setmetatable(instance, { __index = ReaderDogearPlugin })

        if instance.init then
            instance:init()
        end

        -- Run lifecycle methods
        if instance.setupDogear then
            instance:setupDogear()
        end
        if instance.resetLayout then
            instance:resetLayout()
        end

        assert.is_not_nil(instance[1])
    end)

    it("restores self[1] after tearing down and recreating ears", function()
        local instance = {}
        setmetatable(instance, { __index = ReaderDogearPlugin })

        if instance.init then
            instance:init()
        end

        -- Initial creation
        if instance.setupDogear then
            instance:setupDogear()
        end
        if instance.resetLayout then
            instance:resetLayout()
        end
        assert.is_not_nil(instance[1])

        -- Simulate tearing down internal ears
        if instance.right_ear and instance.right_ear.free then
            instance.right_ear:free()
        end
        instance.right_ear = nil
        instance.left_ear = nil

        -- Recreate and ensure numeric slot is repopulated
        if instance.setupDogear then
            instance:setupDogear()
        end
        if instance.resetLayout then
            instance:resetLayout()
        end
        assert.is_not_nil(instance[1])
    end)
end)

describe("ComicReader ReaderDogear helper functions", function()
    local instance
    local VerticalSpan

    before_each(function()
        -- Access VerticalSpan through mock_require to ensure consistent mocking
        VerticalSpan = mock_require("ui/widget/verticalspan")

        instance = {}
        setmetatable(instance, { __index = ReaderDogearPlugin })
        if instance.init then
            instance:init()
        end
    end)

    describe("_getRotationAngle", function()
        it("returns base angle (0) for right side in normal layout", function()
            local angle = instance:_getRotationAngle(instance.SIDE_RIGHT)
            assert.equals(0, angle)
        end)

        it("returns base angle + 90 for left side in normal layout", function()
            local angle = instance:_getRotationAngle(instance.SIDE_LEFT)
            assert.equals(90, angle)
        end)

        it("returns 90 for right side in mirrored layout", function()
            -- Mock mirrored layout temporarily
            local BD = mock_require("ui/bidi")
            local original_mirrored = BD.mirroredUILayout
            BD.mirroredUILayout = function()
                return true
            end

            local angle = instance:_getRotationAngle(instance.SIDE_RIGHT)
            assert.equals(90, angle)

            -- Restore original
            BD.mirroredUILayout = original_mirrored
        end)

        it("returns 180 for left side in mirrored layout", function()
            -- Mock mirrored layout temporarily
            local BD = mock_require("ui/bidi")
            local original_mirrored = BD.mirroredUILayout
            BD.mirroredUILayout = function()
                return true
            end

            local angle = instance:_getRotationAngle(instance.SIDE_LEFT)
            assert.equals(180, angle)

            -- Restore original
            BD.mirroredUILayout = original_mirrored
        end)
    end)

    describe("_createDogearIcon", function()
        it("creates an IconWidget with specified rotation angle", function()
            instance.dogear_size = 40
            local icon = instance:_createDogearIcon(45)

            assert.is_not_nil(icon)
            assert.equals(45, icon.rotation_angle)
        end)

        it("creates an icon with correct width and height", function()
            instance.dogear_size = 32
            local icon = instance:_createDogearIcon(0)

            assert.equals(32, icon.dimen.w)
            assert.equals(32, icon.dimen.h)
        end)

        it("creates an icon with different sizes", function()
            instance.dogear_size = 64
            local icon = instance:_createDogearIcon(90)

            assert.equals(64, icon.dimen.w)
            assert.equals(64, icon.dimen.h)
        end)

        it("icon rotation angle can vary independently of size", function()
            instance.dogear_size = 40
            local icon1 = instance:_createDogearIcon(0)
            local icon2 = instance:_createDogearIcon(180)

            assert.equals(40, icon1.dimen.w)
            assert.equals(40, icon2.dimen.w)
            assert.not_equals(icon1.rotation_angle, icon2.rotation_angle)
        end)
    end)

    describe("_createEar", function()
        before_each(function()
            instance.dogear_size = 32
            instance.dogear_y_offset = 0
            instance.top_pad = VerticalSpan:new({ width = 0 })
        end)

        it("creates an ear with icon and vgroup", function()
            local icon = instance:_createDogearIcon(0)
            local result = instance:_createEar(instance.SIDE_RIGHT, icon)

            assert.is_not_nil(result)
            assert.is_not_nil(result.ear)
            assert.is_not_nil(result.icon)
            assert.is_not_nil(result.vgroup)
        end)

        it("returns the same icon that was passed in", function()
            local icon = instance:_createDogearIcon(45)
            local result = instance:_createEar(instance.SIDE_RIGHT, icon)

            assert.equals(icon, result.icon)
        end)

        it("creates an ear with correct dimen for right side", function()
            local icon = instance:_createDogearIcon(0)
            local result = instance:_createEar(instance.SIDE_RIGHT, icon)

            assert.equals(800, result.ear.dimen.w) -- Screen width
            assert.equals(32, result.ear.dimen.h) -- dogear_y_offset (0) + dogear_size (32)
        end)

        it("creates an ear with correct dimen for left side", function()
            local icon = instance:_createDogearIcon(90)
            local result = instance:_createEar(instance.SIDE_LEFT, icon)

            assert.equals(800, result.ear.dimen.w)
            assert.equals(32, result.ear.dimen.h)
        end)

        it("creates different ears for left vs right sides", function()
            local icon_right = instance:_createDogearIcon(0)
            local icon_left = instance:_createDogearIcon(90)

            local result_right = instance:_createEar(instance.SIDE_RIGHT, icon_right)
            local result_left = instance:_createEar(instance.SIDE_LEFT, icon_left)

            assert.not_equals(result_right.ear, result_left.ear)
            assert.not_equals(result_right.vgroup, result_left.vgroup)
        end)

        it("respects dogear_y_offset in ear height calculation", function()
            instance.dogear_y_offset = 10
            local icon = instance:_createDogearIcon(0)
            local result = instance:_createEar(instance.SIDE_RIGHT, icon)

            assert.equals(42, result.ear.dimen.h) -- 10 + 32
        end)
    end)

    describe("_updateRightEar", function()
        before_each(function()
            -- Clear existing ears to test creation from scratch
            instance.right_ear = nil
            instance.icon_right = nil
            instance.vgroup_right = nil
            instance.dogear_size = 32
            instance.dogear_y_offset = 0
            instance.top_pad = VerticalSpan:new({ width = 0 })
        end)

        it("creates right ear when missing", function()
            assert.is_nil(instance.right_ear)

            instance:_updateRightEar(false)

            assert.is_not_nil(instance.right_ear)
            assert.is_not_nil(instance.icon_right)
            assert.is_not_nil(instance.vgroup_right)
        end)

        it("recreates right ear when size changed", function()
            instance:_updateRightEar(false)
            local original_ear = instance.right_ear

            instance.dogear_size = 64
            instance:_updateRightEar(true)

            assert.not_equals(original_ear, instance.right_ear)
        end)

        it("does not recreate right ear if size unchanged and ear exists", function()
            instance:_updateRightEar(false)
            local original_ear = instance.right_ear

            instance:_updateRightEar(false)

            assert.equals(original_ear, instance.right_ear)
        end)

        it("frees old ear before creating new one on size change", function()
            instance:_updateRightEar(false)
            local freed = false
            local original_ear = instance.right_ear
            original_ear.free = function()
                freed = true
            end

            instance.dogear_size = 64
            instance:_updateRightEar(true)

            assert.is_true(freed)
        end)

        it("sets correct rotation angle for right ear", function()
            instance:_updateRightEar(false)

            assert.equals(0, instance.icon_right.rotation_angle)
        end)
    end)

    describe("_updateLeftEar", function()
        before_each(function()
            -- Clear existing ears to test creation from scratch
            instance.left_ear = nil
            instance.icon_left = nil
            instance.vgroup_left = nil
            instance.dogear_size = 32
            instance.dogear_y_offset = 0
            instance.top_pad = VerticalSpan:new({ width = 0 })
        end)

        it("creates left ear when missing", function()
            assert.is_nil(instance.left_ear)

            instance:_updateLeftEar(false)

            assert.is_not_nil(instance.left_ear)
            assert.is_not_nil(instance.icon_left)
            assert.is_not_nil(instance.vgroup_left)
        end)

        it("recreates left ear when size changed", function()
            instance:_updateLeftEar(false)
            local original_ear = instance.left_ear

            instance.dogear_size = 64
            instance:_updateLeftEar(true)

            assert.not_equals(original_ear, instance.left_ear)
        end)

        it("does not recreate left ear if size unchanged and ear exists", function()
            instance:_updateLeftEar(false)
            local original_ear = instance.left_ear

            instance:_updateLeftEar(false)

            assert.equals(original_ear, instance.left_ear)
        end)

        it("frees old ear before creating new one on size change", function()
            instance:_updateLeftEar(false)
            local freed = false
            local original_ear = instance.left_ear
            original_ear.free = function()
                freed = true
            end

            instance.dogear_size = 64
            instance:_updateLeftEar(true)

            assert.is_true(freed)
        end)

        it("sets correct rotation angle for left ear (base + 90)", function()
            instance:_updateLeftEar(false)

            assert.equals(90, instance.icon_left.rotation_angle)
        end)
    end)

    describe("helper function integration", function()
        before_each(function()
            -- Clear and reset state for integration tests
            instance.right_ear = nil
            instance.icon_right = nil
            instance.vgroup_right = nil
            instance.left_ear = nil
            instance.icon_left = nil
            instance.vgroup_left = nil
            instance.dogear_size = 32
            instance.dogear_y_offset = 0
            instance.top_pad = VerticalSpan:new({ width = 0 })
        end)

        it("_updateRightEar and _updateLeftEar create consistent ears", function()
            instance:_updateRightEar(false)
            instance:_updateLeftEar(false)

            -- Both should exist and have different rotation angles
            assert.is_not_nil(instance.right_ear)
            assert.is_not_nil(instance.left_ear)
            assert.not_equals(instance.icon_right.rotation_angle, instance.icon_left.rotation_angle)
        end)

        it("both ears have same size but different rotation angles", function()
            instance:_updateRightEar(false)
            instance:_updateLeftEar(false)

            assert.equals(instance.icon_right.dimen.w, instance.icon_left.dimen.w)
            assert.equals(instance.icon_right.dimen.h, instance.icon_left.dimen.h)
            assert.equals(32, instance.icon_right.dimen.w)
            assert.equals(32, instance.icon_right.dimen.h)
        end)

        it("size change propagates through all helper functions", function()
            instance.dogear_size = 32
            instance:_updateRightEar(false)
            instance:_updateLeftEar(false)

            local original_right = instance.right_ear
            local original_left = instance.left_ear

            instance.dogear_size = 64
            instance:_updateRightEar(true)
            instance:_updateLeftEar(true)

            assert.not_equals(original_right, instance.right_ear)
            assert.not_equals(original_left, instance.left_ear)
            assert.equals(64, instance.icon_right.dimen.w)
            assert.equals(64, instance.icon_left.dimen.w)
        end)
    end)
end)
