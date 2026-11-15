-- MarketForces Post module.
--
-- When you put an item in the auction house's sell slot, Razzle fills in
-- the price box with the item's smoothed market value (Mark's choice: steady
-- prices, no racing undercutters). You check it and click Blizzard's own
-- Post button; this module never posts, buys or cancels anything.
--
-- It also sends MF_POST_ITEM_SELECTED(itemID, suggestion) so Razzle's window
-- can talk about the item.
local _, MF = ...

local Post = MF:NewModule("Post", {
    global = {
        fillPrice = true, -- put the suggestion into the price box
    },
})
MF.Post = Post

local SILVER = 100

-- The suggested buyout per unit for an item at the current auction house,
-- or nil when there's no market value yet. Rounded to the nearest silver
-- (at least 1s), since the sell frames don't take copper.
function Post:Suggest(itemID)
    local prices = MF.Prices
    if not (prices and prices:IsEnabled() and itemID) then return nil end
    local p = prices:GetPrice(itemID)
    if not (p and p.market) then return nil end
    local rounded = math.floor(p.market / SILVER + 0.5) * SILVER
    if rounded < SILVER then rounded = SILVER end
    return rounded, p
end

local function itemIDFrom(itemLocation)
    if not itemLocation then return nil end
    if C_Item and C_Item.GetItemID and (not itemLocation.IsValid or itemLocation:IsValid()) then
        local ok, id = pcall(C_Item.GetItemID, itemLocation)
        if ok then return id end
    end
end

-- Called after Blizzard's sell frame takes an item.
function Post:OnItemSet(sellFrame, itemLocation)
    if not self:IsEnabled() then return end
    local itemID = itemIDFrom(itemLocation)
    if not itemID then return end
    local suggestion, p = self:Suggest(itemID)
    self:SendMessage("MF_POST_ITEM_SELECTED", itemID, suggestion, p)
    if not (suggestion and self.db.global.fillPrice) then return end
    -- Blizzard fills in its own default price right after SetItem; set ours
    -- on the next frame so it sticks.
    C_Timer.After(0, function()
        local input = sellFrame.PriceInput
        if input and input.SetAmount and sellFrame:IsShown() then
            input:SetAmount(suggestion)
        end
    end)
end

-- Hooks each sell frame once. Hooks can't be removed, so OnItemSet checks
-- IsEnabled() itself.
function Post:HookSellFrames()
    local window = AuctionHouseFrame
    if not (window and hooksecurefunc) then return false end
    self.hooked = self.hooked or {}
    local any = false
    for _, key in ipairs({ "ItemSellFrame", "CommoditiesSellFrame" }) do
        local sellFrame = window[key]
        if sellFrame and sellFrame.SetItem and not self.hooked[key] then
            hooksecurefunc(sellFrame, "SetItem", function(frame, itemLocation)
                Post:OnItemSet(frame, itemLocation)
            end)
            self.hooked[key] = true
        end
        any = any or self.hooked[key] == true
    end
    return any
end

function Post:AUCTION_HOUSE_SHOW()
    if self:HookSellFrames() then return end
    -- The modern AH UI loads on demand; try again shortly.
    local tries = 0
    local function retry()
        if Post:HookSellFrames() or tries >= 10 then return end
        tries = tries + 1
        C_Timer.After(0.1, retry)
    end
    C_Timer.After(0.1, retry)
end

function Post:OnInitialize()
    MF:RegisterSlashCommand("autofill", "Toggle Razzle filling in sell prices", function()
        Post.db.global.fillPrice = not Post.db.global.fillPrice
        MF:Print("Razzle", Post.db.global.fillPrice and "will fill in sell prices with market value"
            or "won't touch the sell price")
    end)
end

function Post:OnEnable()
    self:RegisterEvent("AUCTION_HOUSE_SHOW")
end
