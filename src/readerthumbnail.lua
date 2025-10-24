local ReaderThumbnail = require("apps/reader/modules/readerthumbnail")

local logger = require("logger")

-- Store the original _getPageImage method
local ReaderThumbnailGetPageImageOrig = ReaderThumbnail._getPageImage

-- Override _getPageImage to disable dual page mode for thumbnail generation
-- This ensures that PageBrowser shows single-page thumbnails even when the
-- comicreader plugin has enabled dual page mode.
function ReaderThumbnail:_getPageImage(page)
    local disabledDualPageMode = false

    if self.ui.paging and self.ui.paging.document_settings then
        disabledDualPageMode = true
        self.ui.paging.document_settings.dual_page_mode = false
    end

    -- Set page_mode to 1 (single page mode)
    if self.ui.document and self.ui.document.configurable then
        disabledDualPageMode = true
        self.ui.document.configurable.page_mode = 1
    end

    if disabledDualPageMode then
        logger.dbg("ComicReaderThumbnail:_getPageImage - Dual page mode disabled for thumbnail generation")
    end

    return ReaderThumbnailGetPageImageOrig(self, page)
end

return ReaderThumbnail
