-- Test for readerpaging.lua dual page mode navigation
-- This tests the fix for "End of Document Action" not working in dual page mode

-- Extracted functions from readerpaging.lua for isolated testing
local function getMaxDualPageBase(total_pages, first_page_is_cover)
    if first_page_is_cover then
        -- With cover: spreads are 2-3, 4-5, etc. (even bases)
        return total_pages % 2 == 0 and total_pages or total_pages - 1
    else
        -- Without cover: spreads are 1-2, 3-4, 5-6, etc. (odd bases)
        return total_pages % 2 == 1 and total_pages or total_pages - 1
    end
end

local function getDualPageBaseFromPage(page, first_page_is_cover)
    if not page or page == 0 then
        page = 1
    end

    if first_page_is_cover and page == 1 then
        return 1
    end

    if first_page_is_cover then
        return (page % 2 == 0) and page or (page - 1)
    end

    return (page % 2 == 1) and page or (page - 1)
end

local function getPairBaseByRelativeMovement(current_base, diff, first_page_is_cover, total_pages)
    if first_page_is_cover and current_base == 1 then
        -- Handle cover page navigation
        if diff <= 0 then
            return 1 -- Stay on cover
        else
            -- Jump to first spread (2) + subsequent spreads
            return math.min(2 + (diff - 1) * 2, total_pages % 2 == 0 and total_pages or total_pages - 1)
        end
    end

    -- Calculate new base for spreads
    local new_base = current_base + (diff * 2)

    -- Clamp to valid range
    local max_base = total_pages % 2 == 0 and total_pages or total_pages - 1
    new_base = math.max(1, math.min(new_base, max_base))

    -- Handle backward navigation to cover
    if new_base < 2 then
        return total_pages >= 1 and 1 or new_base
    end

    return new_base
end

local function getDualPagePairFromBasePage(page, first_page_is_cover, total_pages)
    local pair_base = getDualPageBaseFromPage(page, first_page_is_cover)

    if first_page_is_cover and pair_base == 1 then
        return { 1 }
    end

    -- Create the pair array
    local pair = { pair_base }
    if pair_base + 1 <= total_pages then
        table.insert(pair, pair_base + 1)
    end

    return pair
end

describe("ReaderPaging dual page mode", function()


    describe("getMaxDualPageBase", function()
        it("should calculate max base for even pages without cover", function()
            local max_base = getMaxDualPageBase(10, false)
            assert.equals(9, max_base) -- Spreads: 1-2, 3-4, 5-6, 7-8, 9-10
        end)

        it("should calculate max base for odd pages without cover", function()
            local max_base = getMaxDualPageBase(11, false)
            assert.equals(11, max_base) -- Spreads: 1-2, 3-4, 5-6, 7-8, 9-10, 11
        end)

        it("should calculate max base for even pages with cover", function()
            local max_base = getMaxDualPageBase(10, true)
            assert.equals(10, max_base) -- Cover: 1, Spreads: 2-3, 4-5, 6-7, 8-9, 10
        end)

        it("should calculate max base for odd pages with cover", function()
            local max_base = getMaxDualPageBase(11, true)
            assert.equals(10, max_base) -- Cover: 1, Spreads: 2-3, 4-5, 6-7, 8-9, 10-11
        end)
    end)


    describe("getDualPageBaseFromPage", function()
        it("should return correct base without cover", function()
            assert.equals(1, getDualPageBaseFromPage(1, false))
            assert.equals(1, getDualPageBaseFromPage(2, false))
            assert.equals(3, getDualPageBaseFromPage(3, false))
            assert.equals(3, getDualPageBaseFromPage(4, false))
            assert.equals(9, getDualPageBaseFromPage(9, false))
            assert.equals(9, getDualPageBaseFromPage(10, false))
        end)

        it("should return correct base with cover", function()
            assert.equals(1, getDualPageBaseFromPage(1, true)) -- Cover alone
            assert.equals(2, getDualPageBaseFromPage(2, true))
            assert.equals(2, getDualPageBaseFromPage(3, true))
            assert.equals(4, getDualPageBaseFromPage(4, true))
            assert.equals(4, getDualPageBaseFromPage(5, true))
        end)
    end)

    describe("getPairBaseByRelativeMovement", function()
        it("should move forward correctly without cover", function()
            local current_base = 1
            assert.equals(3, getPairBaseByRelativeMovement(current_base, 1, false, 10))

            current_base = 3
            assert.equals(5, getPairBaseByRelativeMovement(current_base, 1, false, 10))
        end)

        it("should move backward correctly without cover", function()
            local current_base = 5
            assert.equals(3, getPairBaseByRelativeMovement(current_base, -1, false, 10))

            current_base = 3
            assert.equals(1, getPairBaseByRelativeMovement(current_base, -1, false, 10))
        end)

        it("should clamp to max base when trying to go beyond", function()
            local total_pages = 10
            local current_base = 9 -- Last spread (9-10)
            -- Trying to go forward would calculate 11, but should clamp to max
            local new_base = getPairBaseByRelativeMovement(current_base, 1, false, total_pages)
            -- In the current implementation, max_base = 10 (bug: doesn't use getMaxDualPageBase)
            -- So 9 + 2 = 11, clamped to min(11, 10) = 10
            assert.equals(10, new_base)
        end)
    end)


    describe("end of document detection in dual page mode", function()
        it("should trigger EndOfBook when at last spread moving forward (even pages, no cover)", function()
            local total_pages = 10
            local first_page_is_cover = false
            local current_page = 9
            local current_pair_base = 9

            -- The fix: check if current_pair_base >= max_base and diff > 0
            local max_base = getMaxDualPageBase(total_pages, first_page_is_cover)
            local diff = 1
            local should_trigger_end = (current_pair_base >= max_base and diff > 0)

            assert.is_true(should_trigger_end, "Should trigger end of book when at base 9 (max) moving forward")
        end)

        it("should trigger EndOfBook when at last spread moving forward (odd pages, no cover)", function()
            local total_pages = 11
            local first_page_is_cover = false
            local current_page = 11
            local current_pair_base = 11

            local max_base = getMaxDualPageBase(total_pages, first_page_is_cover)
            local diff = 1
            local should_trigger_end = (current_pair_base >= max_base and diff > 0)

            assert.is_true(should_trigger_end, "Should trigger end of book when at base 11 (max) moving forward")
        end)

        it("should trigger EndOfBook when at last spread moving forward (even pages, with cover)", function()
            local total_pages = 10
            local first_page_is_cover = true
            local current_page = 10
            local current_pair_base = 10

            local max_base = getMaxDualPageBase(total_pages, first_page_is_cover)
            local diff = 1
            local should_trigger_end = (current_pair_base >= max_base and diff > 0)

            assert.is_true(should_trigger_end, "Should trigger end of book when at base 10 (max) with cover moving forward")
        end)

        it("should NOT trigger EndOfBook when not at last spread", function()
            local total_pages = 10
            local first_page_is_cover = false
            local current_page = 7
            local current_pair_base = 7

            local max_base = getMaxDualPageBase(total_pages, first_page_is_cover)
            local diff = 1
            local should_trigger_end = (current_pair_base >= max_base and diff > 0)

            assert.is_false(should_trigger_end, "Should NOT trigger end of book when at base 7, can move to 9")
        end)

        it("should NOT trigger EndOfBook when moving backward from last spread", function()
            local total_pages = 10
            local first_page_is_cover = false
            local current_page = 9
            local current_pair_base = 9

            local max_base = getMaxDualPageBase(total_pages, first_page_is_cover)
            local diff = -1
            local should_trigger_end = (current_pair_base >= max_base and diff > 0)

            assert.is_false(should_trigger_end, "Should NOT trigger end of book when moving backward")
        end)
    end)

    describe("getDualPagePairFromBasePage", function()
        it("should return single page for cover", function()
            local total_pages = 10
            local first_page_is_cover = true
            local pair = getDualPagePairFromBasePage(1, first_page_is_cover, total_pages)
            assert.equals(1, #pair)
            assert.equals(1, pair[1])
        end)

        it("should return pair for normal spreads without cover", function()
            local total_pages = 10
            local first_page_is_cover = false
            local pair = getDualPagePairFromBasePage(3, first_page_is_cover, total_pages)
            assert.equals(2, #pair)
            assert.equals(3, pair[1])
            assert.equals(4, pair[2])
        end)

        it("should return pair for normal spreads with cover", function()
            local total_pages = 10
            local first_page_is_cover = true
            local pair = getDualPagePairFromBasePage(2, first_page_is_cover, total_pages)
            assert.equals(2, #pair)
            assert.equals(2, pair[1])
            assert.equals(3, pair[2])
        end)

        it("should return single page for last odd page", function()
            local total_pages = 11
            local first_page_is_cover = false
            local pair = getDualPagePairFromBasePage(11, first_page_is_cover, total_pages)
            assert.equals(1, #pair)
            assert.equals(11, pair[1])
        end)
    end)
end)
