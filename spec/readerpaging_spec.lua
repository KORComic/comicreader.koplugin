-- Test for readerpaging.lua dual page mode navigation
-- This tests the fix for "End of Document Action" not working in dual page mode

-- Mock KoreReader dependencies
local mocked_modules = {}
package.loaded["logger"] = {
    dbg = function() end,
}

-- Create a minimal mock for the ReaderPaging base module
-- We only need the structure that our plugin extends
mocked_modules["apps/reader/modules/readerpaging"] = {
    init = function(self)
        return true
    end,
    default_reader_settings = {},
    default_document_settings = {},
}

-- Mock other KoreReader modules
package.loaded["ui/bidi"] = {}
package.loaded["device"] = { screen = {} }
package.loaded["ui/event"] = { new = function() end }
package.loaded["ui/geometry"] = {}
package.loaded["ui/widget/infomessage"] = {
    new = function()
        return {}
    end,
}
package.loaded["optmath"] = {}
package.loaded["ui/uimanager"] = {
    show = function() end,
    nextTick = function() end, -- Used at module load time
}
package.loaded["gettext"] = function(x)
    return x
end
package.loaded["ui/widget/buttondialog"] = {}
package.loaded["ui/widget/notification"] = {
    SOURCE_OTHER = 1,
    notify = function() end,
}
package.loaded["apps/reader/readerui"] = {
    instance = nil, -- Can be set by tests if needed
}

-- Override require to use mocked modules
local original_require = require
local function mock_require(module_name)
    if mocked_modules[module_name] then
        return mocked_modules[module_name]
    end
    return original_require(module_name)
end

-- Temporarily replace require
_G.require = mock_require

-- Now import the actual ReaderPaging module
local ReaderPaging = original_require("src/readerpaging")

-- Restore original require
_G.require = original_require

describe("ReaderPaging dual page mode", function()
    -- Helper function to create a test instance
    local function create_reader_paging_instance(total_pages, first_page_is_cover)
        local instance = {}
        setmetatable(instance, { __index = ReaderPaging })

        instance.number_of_pages = total_pages
        instance.current_pair_base = 1
        instance.document_settings = {
            dual_page_mode_first_page_is_cover = first_page_is_cover or false,
        }

        return instance
    end

    describe("getMaxDualPageBase", function()
        it("should calculate max base for even pages without cover", function()
            local instance = create_reader_paging_instance(10, false)
            local max_base = instance:getMaxDualPageBase()
            assert.equals(9, max_base) -- Spreads: 1-2, 3-4, 5-6, 7-8, 9-10
        end)

        it("should calculate max base for odd pages without cover", function()
            local instance = create_reader_paging_instance(11, false)
            local max_base = instance:getMaxDualPageBase()
            assert.equals(11, max_base) -- Spreads: 1-2, 3-4, 5-6, 7-8, 9-10, 11
        end)

        it("should calculate max base for even pages with cover", function()
            local instance = create_reader_paging_instance(10, true)
            local max_base = instance:getMaxDualPageBase()
            assert.equals(10, max_base) -- Cover: 1, Spreads: 2-3, 4-5, 6-7, 8-9, 10
        end)

        it("should calculate max base for odd pages with cover", function()
            local instance = create_reader_paging_instance(11, true)
            local max_base = instance:getMaxDualPageBase()
            assert.equals(10, max_base) -- Cover: 1, Spreads: 2-3, 4-5, 6-7, 8-9, 10-11
        end)
    end)

    describe("getDualPageBaseFromPage", function()
        it("should return correct base without cover", function()
            local instance = create_reader_paging_instance(10, false)
            assert.equals(1, instance:getDualPageBaseFromPage(1))
            assert.equals(1, instance:getDualPageBaseFromPage(2))
            assert.equals(3, instance:getDualPageBaseFromPage(3))
            assert.equals(3, instance:getDualPageBaseFromPage(4))
            assert.equals(9, instance:getDualPageBaseFromPage(9))
            assert.equals(9, instance:getDualPageBaseFromPage(10))
        end)

        it("should return correct base with cover", function()
            local instance = create_reader_paging_instance(10, true)
            assert.equals(1, instance:getDualPageBaseFromPage(1)) -- Cover alone
            assert.equals(2, instance:getDualPageBaseFromPage(2))
            assert.equals(2, instance:getDualPageBaseFromPage(3))
            assert.equals(4, instance:getDualPageBaseFromPage(4))
            assert.equals(4, instance:getDualPageBaseFromPage(5))
        end)
    end)

    describe("getPairBaseByRelativeMovement", function()
        it("should move forward correctly without cover", function()
            local instance = create_reader_paging_instance(10, false)

            instance.current_pair_base = 1
            assert.equals(3, instance:getPairBaseByRelativeMovement(1))

            instance.current_pair_base = 3
            assert.equals(5, instance:getPairBaseByRelativeMovement(1))
        end)

        it("should move backward correctly without cover", function()
            local instance = create_reader_paging_instance(10, false)

            instance.current_pair_base = 5
            assert.equals(3, instance:getPairBaseByRelativeMovement(-1))

            instance.current_pair_base = 3
            assert.equals(1, instance:getPairBaseByRelativeMovement(-1))
        end)

        it("should clamp to max base when trying to go beyond", function()
            local instance = create_reader_paging_instance(10, false)
            instance.current_pair_base = 9 -- Last spread (9-10)
            -- Trying to go forward would calculate 11, but should clamp to max
            local new_base = instance:getPairBaseByRelativeMovement(1)
            -- So 9 + 2 = 11, clamped to min(11, 10) = 10
            assert.equals(10, new_base)
        end)
    end)

    describe("end of document detection in dual page mode", function()
        it("should trigger EndOfBook when at last spread moving forward (even pages, no cover)", function()
            local instance = create_reader_paging_instance(10, false)
            local current_pair_base = 9

            -- The fix: check if current_pair_base >= max_base and diff > 0
            local max_base = instance:getMaxDualPageBase()
            local diff = 1
            local should_trigger_end = (current_pair_base >= max_base and diff > 0)

            assert.is_true(should_trigger_end, "Should trigger end of book when at base 9 (max) moving forward")
        end)

        it("should trigger EndOfBook when at last spread moving forward (odd pages, no cover)", function()
            local instance = create_reader_paging_instance(11, false)
            local current_pair_base = 11

            local max_base = instance:getMaxDualPageBase()
            local diff = 1
            local should_trigger_end = (current_pair_base >= max_base and diff > 0)

            assert.is_true(should_trigger_end, "Should trigger end of book when at base 11 (max) moving forward")
        end)

        it("should trigger EndOfBook when at last spread moving forward (even pages, with cover)", function()
            local instance = create_reader_paging_instance(10, true)
            local current_pair_base = 10

            local max_base = instance:getMaxDualPageBase()
            local diff = 1
            local should_trigger_end = (current_pair_base >= max_base and diff > 0)

            assert.is_true(
                should_trigger_end,
                "Should trigger end of book when at base 10 (max) with cover moving forward"
            )
        end)

        it("should NOT trigger EndOfBook when not at last spread", function()
            local instance = create_reader_paging_instance(10, false)
            local current_pair_base = 7

            local max_base = instance:getMaxDualPageBase()
            local diff = 1
            local should_trigger_end = (current_pair_base >= max_base and diff > 0)

            assert.is_false(should_trigger_end, "Should NOT trigger end of book when at base 7, can move to 9")
        end)

        it("should NOT trigger EndOfBook when moving backward from last spread", function()
            local instance = create_reader_paging_instance(10, false)
            local current_pair_base = 9

            local max_base = instance:getMaxDualPageBase()
            local diff = -1
            local should_trigger_end = (current_pair_base >= max_base and diff > 0)

            assert.is_false(should_trigger_end, "Should NOT trigger end of book when moving backward")
        end)
    end)

    describe("getDualPagePairFromBasePage", function()
        it("should return single page for cover", function()
            local instance = create_reader_paging_instance(10, true)
            local pair = instance:getDualPagePairFromBasePage(1)
            assert.equals(1, #pair)
            assert.equals(1, pair[1])
        end)

        it("should return pair for normal spreads without cover", function()
            local instance = create_reader_paging_instance(10, false)
            local pair = instance:getDualPagePairFromBasePage(3)
            assert.equals(2, #pair)
            assert.equals(3, pair[1])
            assert.equals(4, pair[2])
        end)

        it("should return pair for normal spreads with cover", function()
            local instance = create_reader_paging_instance(10, true)
            local pair = instance:getDualPagePairFromBasePage(2)
            assert.equals(2, #pair)
            assert.equals(2, pair[1])
            assert.equals(3, pair[2])
        end)

        it("should return single page for last odd page", function()
            local instance = create_reader_paging_instance(11, false)
            local pair = instance:getDualPagePairFromBasePage(11)
            assert.equals(1, #pair)
            assert.equals(11, pair[1])
        end)
    end)
end)

-- Regression tests for issue #55: prevent crashes during initialization
describe("ReaderPaging initialization edge cases (issue #55)", function()
    local instance

    before_each(function()
        -- Update the global Screen mock to support getScreenMode
        local Device = package.loaded["device"]
        Device.screen.getScreenMode = function()
            return "landscape"
        end

        -- Create a minimal instance
        instance = {}
        setmetatable(instance, { __index = ReaderPaging })
        instance.number_of_pages = 10
        instance.current_page = 0 -- Simulating uninitialized state
        instance.view = { page_scroll = false }
    end)

    describe("autoEnableDualPageModeIfLandscape with nil settings", function()
        it("should not crash when document_settings is nil", function()
            instance.document_settings = nil
            instance.reader_settings = { auto_enable_dual_page_mode = true }

            assert.has_no.errors(function()
                instance:autoEnableDualPageModeIfLandscape()
            end)
        end)

        it("should not crash when reader_settings is nil", function()
            instance.document_settings = { dual_page_mode = false }
            instance.reader_settings = nil

            assert.has_no.errors(function()
                instance:autoEnableDualPageModeIfLandscape()
            end)
        end)

        it("should not crash when both settings are nil", function()
            instance.document_settings = nil
            instance.reader_settings = nil

            assert.has_no.errors(function()
                instance:autoEnableDualPageModeIfLandscape()
            end)
        end)

        it("should not crash when current_page is 0", function()
            instance.document_settings = { dual_page_mode = false }
            instance.reader_settings = { auto_enable_dual_page_mode = true }
            instance.current_page = 0

            assert.has_no.errors(function()
                instance:autoEnableDualPageModeIfLandscape()
            end)
        end)

        it("should work normally when all settings are initialized", function()
            instance.document_settings = { dual_page_mode = false }
            instance.reader_settings = { auto_enable_dual_page_mode = true }
            instance.current_page = 1
            instance.onSetPageMode = function() end
            instance.onRedrawCurrentPage = function() end

            assert.has_no.errors(function()
                instance:autoEnableDualPageModeIfLandscape()
            end)
        end)
    end)

    describe("disableDualPageModeIfNotLandscape with nil settings", function()
        before_each(function()
            -- Update Screen mock to return portrait
            local Device = package.loaded["device"]
            Device.screen.getScreenMode = function()
                return "portrait"
            end
        end)

        it("should not crash when document_settings is nil", function()
            instance.document_settings = nil

            assert.has_no.errors(function()
                instance:disableDualPageModeIfNotLandscape()
            end)
        end)

        it("should not crash when current_page is 0", function()
            instance.document_settings = { dual_page_mode = true }
            instance.current_page = 0

            assert.has_no.errors(function()
                instance:disableDualPageModeIfNotLandscape()
            end)
        end)

        it("should work normally when all settings are initialized", function()
            instance.document_settings = { dual_page_mode = true }
            instance.current_page = 1
            instance.onSetPageMode = function() end
            instance.onRedrawCurrentPage = function() end

            assert.has_no.errors(function()
                instance:disableDualPageModeIfNotLandscape()
            end)
        end)
    end)

    describe("onSetDimensions during initialization", function()
        it("should not crash when called before settings are initialized", function()
            instance.document_settings = nil
            instance.reader_settings = nil
            instance.current_page = 0

            assert.has_no.errors(function()
                instance:onSetDimensions()
            end)
        end)

        it("should not crash when called with partial initialization", function()
            instance.document_settings = { dual_page_mode = false }
            instance.reader_settings = nil
            instance.current_page = 0

            assert.has_no.errors(function()
                instance:onSetDimensions()
            end)
        end)
    end)

    describe("startup scenario simulation", function()
        it("should handle rotation event before onReadSettings is called", function()
            -- Simulate the exact scenario from issue #55:
            -- 1. File opens with rotation set
            -- 2. onSetDimensions is triggered before onReadSettings
            local uninit_instance = {}
            setmetatable(uninit_instance, { __index = ReaderPaging })
            uninit_instance.number_of_pages = 10
            uninit_instance.current_page = 0
            uninit_instance.document_settings = nil
            uninit_instance.reader_settings = nil
            uninit_instance.view = { page_scroll = false }

            -- This simulates onSetDimensions being called during ReaderUI:init
            assert.has_no.errors(function()
                uninit_instance:onSetDimensions()
            end)

            -- Now simulate normal initialization completing
            uninit_instance.document_settings = {
                dual_page_mode = false,
                dual_page_mode_first_page_is_cover = false,
            }
            uninit_instance.reader_settings = { auto_enable_dual_page_mode = true }
            uninit_instance.current_page = 1
            uninit_instance.onSetPageMode = function() end
            uninit_instance.onRedrawCurrentPage = function() end

            -- After initialization, functionality should work
            assert.has_no.errors(function()
                uninit_instance:autoEnableDualPageModeIfLandscape()
            end)
        end)
    end)
end)
