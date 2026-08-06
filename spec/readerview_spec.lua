-- Test for readerview.lua paintTo patch compatibility
-- This tests that user patches (like header/footer patches) work correctly
-- when ComicReader overrides paintTo

-- Mock KoreReader dependencies
local mocked_modules = {}
package.loaded["logger"] = {
    dbg = function() end,
}

-- Track if original paintTo was called
local original_paintTo_called = false
local original_paintTo_args = {}

-- Create a minimal mock for the ReaderView base module
mocked_modules["apps/reader/modules/readerview"] = {
    paintTo = function(self, bb, x, y)
        original_paintTo_called = true
        original_paintTo_args = { self = self, bb = bb, x = x, y = y }
    end,
}

-- Mock ReaderDogear
package.loaded["src/readerdogear"] = {
    new = function()
        return {
            paintTo = function() end,
        }
    end,
}

-- Mock ReaderFlipping
package.loaded["apps/reader/modules/readerflipping"] = {
    new = function()
        return {
            paintTo = function() end,
        }
    end,
}

-- Mock ReaderFooter
package.loaded["apps/reader/modules/readerfooter"] = {
    new = function()
        return {
            paintTo = function() end,
            getHeight = function()
                return 0
            end,
        }
    end,
}

-- Mock other KoreReader modules
package.loaded["ffi/blitbuffer"] = {
    COLOR_DARK_GRAY = 8,
}
package.loaded["device"] = {
    screen = {
        scaleBySize = function(x)
            return x
        end,
    },
}
package.loaded["ui/event"] = {
    new = function()
        return {}
    end,
}
package.loaded["ui/geometry"] = {
    new = function(opts)
        return opts or {}
    end,
}
package.loaded["ui/widget/iconwidget"] = {
    new = function()
        return {}
    end,
}
package.loaded["ui/size"] = {
    line = { medium = 2 },
    padding = { small = 4 },
}
package.loaded["ui/uimanager"] = {
    nextTick = function() end,
    setDirty = function() end,
}
package.loaded["gettext"] = function(x)
    return x
end

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

-- Now import the actual ReaderView module from comicreader
local ReaderView = original_require("src/readerview")

-- Restore original require
_G.require = original_require

describe("ReaderView paintTo patch compatibility", function()
    -- Helper function to create a mock UI instance
    local function create_mock_ui(is_paging)
        return {
            paging = is_paging and {
                isDualPageEnabled = function()
                    return false
                end,
            } or nil,
            rolling = not is_paging and {
                handlePartialRerendering = function()
                    return false
                end,
            } or nil,
            handleEvent = function() end,
        }
    end

    -- Helper function to create a mock view instance
    local function create_view_instance(is_paging)
        local instance = {
            ui = create_mock_ui(is_paging),
            visible_area = { x = 0, y = 0, w = 100, h = 100 },
            dim_area = {
                isEmpty = function()
                    return true
                end,
            },
            highlight_visible = false,
            highlight = { temp = nil, indicator = nil },
            dogear_visible = false,
            footer_visible = false,
            view_modules = {},
            dialog = {},
            document = {},
            state = { drawn = false },
            page_scroll = false,
            img_count = 0,
            img_coverage = 0,
            -- Mock widgets that are used in paintTo
            dogear = { paintTo = function() end },
            footer = { paintTo = function() end },
            flipping = { paintTo = function() end },
        }

        -- Add paintTo method from our module
        setmetatable(instance, { __index = ReaderView })

        return instance
    end

    before_each(function()
        -- Reset tracking variables
        original_paintTo_called = false
        original_paintTo_args = {}
    end)

    describe("non-paging documents (EPUBs)", function()
        it("should call original paintTo for non-paging documents", function()
            local view = create_view_instance(false) -- false = non-paging (EPUB)

            -- Mock blitbuffer
            local bb = {}
            local x, y = 0, 0

            -- Call paintTo
            view:paintTo(bb, x, y)

            -- Verify original was called
            assert.is_true(original_paintTo_called, "Original paintTo should be called for non-paging documents")
            assert.equals(bb, original_paintTo_args.bb)
            assert.equals(x, original_paintTo_args.x)
            assert.equals(y, original_paintTo_args.y)
        end)

        it("should preserve self context when calling original paintTo", function()
            local view = create_view_instance(false)
            local bb = {}

            view:paintTo(bb, 0, 0)

            assert.is_true(original_paintTo_called)
            assert.equals(view, original_paintTo_args.self)
        end)

        it("should allow user patches to wrap paintTo", function()
            -- Simulate a user patch wrapping the paintTo function
            local patch_called = false
            local saved_paintTo = ReaderView.paintTo

            -- User patch wrapper
            ReaderView.paintTo = function(self, bb, x, y)
                patch_called = true
                return saved_paintTo(self, bb, x, y)
            end

            local view = create_view_instance(false)
            view:paintTo({}, 0, 0)

            -- Both patch and original should be called
            assert.is_true(patch_called, "User patch wrapper should be called")
            assert.is_true(original_paintTo_called, "Original paintTo should still be called")

            -- Restore
            ReaderView.paintTo = saved_paintTo
        end)
    end)

    describe("paging documents (PDFs, Comics)", function()
        it("should NOT call original paintTo for paging documents", function()
            local view = create_view_instance(true) -- true = paging (PDF/Comic)

            -- Add required methods for paging documents
            view.drawPageSurround = function() end
            view.drawSinglePage = function() end
            view.drawSavedHighlight = function()
                return false
            end
            view.drawTempHighlight = function() end
            view.drawHighlightIndicator = function() end
            view.isOverlapAllowed = function()
                return false
            end

            local bb = {}
            view:paintTo(bb, 0, 0)

            -- Verify original was NOT called (ComicReader handles paging documents)
            assert.is_false(original_paintTo_called, "Original paintTo should NOT be called for paging documents")
        end)

        it("should execute ComicReader-specific logic for paging documents", function()
            local view = create_view_instance(true)

            -- Track if ComicReader methods were called
            local draw_surround_called = false
            local draw_single_page_called = false

            view.drawPageSurround = function()
                draw_surround_called = true
            end
            view.drawSinglePage = function()
                draw_single_page_called = true
            end
            view.drawSavedHighlight = function()
                return false
            end
            view.isOverlapAllowed = function()
                return false
            end

            view:paintTo({}, 0, 0)

            assert.is_true(draw_surround_called, "ComicReader should draw page surround")
            assert.is_true(draw_single_page_called, "ComicReader should draw single page")
        end)

        it("should handle dual page mode for paging documents", function()
            local view = create_view_instance(true)
            view.ui.paging.isDualPageEnabled = function()
                return true
            end

            local draw_2pages_called = false
            view.page_scroll = false
            view.drawPageSurround = function() end
            view.drawPageBackground = function() end
            view.draw2Pages = function()
                draw_2pages_called = true
            end
            view.drawSavedHighlight = function()
                return false
            end
            view.isOverlapAllowed = function()
                return false
            end

            view:paintTo({}, 0, 0)

            assert.is_true(draw_2pages_called, "ComicReader should draw dual pages")
            assert.is_false(original_paintTo_called, "Original should not be called in dual page mode")
        end)
    end)

    describe("edge cases", function()
        it("should handle nil ui.paging gracefully", function()
            local view = create_view_instance(false)
            view.ui.paging = nil

            assert.has_no.errors(function()
                view:paintTo({}, 0, 0)
            end)

            assert.is_true(original_paintTo_called, "Should fall back to original when paging is nil")
        end)

        it("should pass correct arguments to original paintTo", function()
            local view = create_view_instance(false)
            local bb = { test = "buffer" }
            local x = 10
            local y = 20

            view:paintTo(bb, x, y)

            assert.equals(bb, original_paintTo_args.bb)
            assert.equals(x, original_paintTo_args.x)
            assert.equals(y, original_paintTo_args.y)
        end)
    end)
end)
