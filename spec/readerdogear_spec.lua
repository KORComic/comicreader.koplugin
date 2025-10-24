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
local function mock_require(module_name)
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
