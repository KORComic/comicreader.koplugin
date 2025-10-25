-- Tests for comicreader ReaderThumbnail patch
-- Ensures that dual page mode is disabled when generating thumbnails,
-- even when the comicreader plugin has enabled it.

-- Minimal mocked dependencies used by the plugin
local mocked_modules = {}

-- Simple logger
package.loaded["logger"] = {
    dbg = function() end,
}

-- Base ReaderThumbnail (the plugin augments this)
mocked_modules["apps/reader/modules/readerthumbnail"] = {
    _getPageImage = function(_, page)
        -- Mock implementation of original _getPageImage
        return {
            page = page,
            dual_page_mode_was_disabled = true,
        }
    end,
}

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
local ReaderThumbnailPlugin = original_require("src/readerthumbnail")
_G.require = original_require

describe("ComicReader ReaderThumbnail patch", function()
    it("disables dual_page_mode in document_settings when generating thumbnails", function()
        local instance = {}
        setmetatable(instance, { __index = ReaderThumbnailPlugin })

        -- Setup mock UI structure with dual page mode enabled
        instance.ui = {
            paging = {
                document_settings = {
                    dual_page_mode = true,
                },
            },
            document = {
                configurable = {
                    page_mode = 2, -- dual page mode
                },
            },
        }

        -- Call _getPageImage
        local result = instance:_getPageImage(1)

        -- Verify dual page mode was disabled in document_settings
        assert.is_false(instance.ui.paging.document_settings.dual_page_mode)

        -- Verify page_mode was set to 1 (single page)
        assert.equals(1, instance.ui.document.configurable.page_mode)

        -- Verify the result is returned
        assert.is_not_nil(result)
    end)

    it("handles missing paging.document_settings gracefully", function()
        local instance = {}
        setmetatable(instance, { __index = ReaderThumbnailPlugin })

        -- Setup mock UI structure without document_settings
        instance.ui = {
            paging = {},
            document = {
                configurable = {
                    page_mode = 2,
                },
            },
        }

        -- Call _getPageImage (should not error)
        local result = instance:_getPageImage(1)

        -- Verify page_mode was still set
        assert.equals(1, instance.ui.document.configurable.page_mode)

        -- Verify the result is returned
        assert.is_not_nil(result)
    end)

    it("handles missing ui.paging gracefully", function()
        local instance = {}
        setmetatable(instance, { __index = ReaderThumbnailPlugin })

        -- Setup mock UI structure without paging
        instance.ui = {
            document = {
                configurable = {
                    page_mode = 2,
                },
            },
        }

        -- Call _getPageImage (should not error)
        local result = instance:_getPageImage(1)

        -- Verify page_mode was still set
        assert.equals(1, instance.ui.document.configurable.page_mode)

        -- Verify the result is returned
        assert.is_not_nil(result)
    end)

    it("handles missing document.configurable gracefully", function()
        local instance = {}
        setmetatable(instance, { __index = ReaderThumbnailPlugin })

        -- Setup mock UI structure without configurable
        instance.ui = {
            paging = {
                document_settings = {
                    dual_page_mode = true,
                },
            },
            document = {},
        }

        -- Call _getPageImage (should not error)
        local result = instance:_getPageImage(1)

        -- Verify dual page mode was disabled in document_settings
        assert.is_false(instance.ui.paging.document_settings.dual_page_mode)

        -- Verify the result is returned
        assert.is_not_nil(result)
    end)
end)
