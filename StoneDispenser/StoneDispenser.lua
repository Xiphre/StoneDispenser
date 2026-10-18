-- Stone Dispenser: one warlock button on the trade window.
--   With a Healthstone in the bags it puts the best one into the first free trade slot.
--   Without one it casts the best Create Healthstone you know (secure, needs a click),
--   then puts the new stone into the trade when it appears.
--   Bindings.xml adds a key binding that clicks the button.

-- Labels for Esc > Key Bindings > AddOns.
BINDING_HEADER_STONEDISPENSER = "Stone Dispenser"
_G["BINDING_NAME_CLICK StoneDispenserButton:LeftButton"] = "Create / Trade Healthstone"

-- Best first. The create spells and the stones they make are in the same order.
local CREATE_SPELLS = { 11730, 11729, 5699, 6202, 6201 }
local STONE_ITEMS = { 9421, 5510, 5509, 5511, 5512 }

local STONE_RANK = {}
for rank, itemID in ipairs(STONE_ITEMS) do
    STONE_RANK[itemID] = rank
end

local MAX_TRADE_SLOTS = MAX_TRADABLE_ITEMS or 6
local BOOK = BOOKTYPE_SPELL or "spell"

-- The client may have the C_Container API or the older globals.
local Container = C_Container or {}
local GetNumSlots = Container.GetContainerNumSlots or GetContainerNumSlots
local GetItemID = Container.GetContainerItemID or GetContainerItemID
local PickupItem = Container.PickupContainerItem or PickupContainerItem
local SpellBook = C_SpellBook or {}
local GetSpellName = GetSpellInfo or (C_Spell and C_Spell.GetSpellName)

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9Stone Dispenser|r: " .. msg)
end

-- Bags --------------------------------------------------------------------

local function ContainerItemID(bag, slot)
    if GetItemID then
        return GetItemID(bag, slot)
    end
    local link = GetContainerItemLink(bag, slot)
    return link and tonumber(link:match("item:(%d+)"))
end

local function IsLocked(bag, slot)
    if Container.GetContainerItemInfo then
        local info = Container.GetContainerItemInfo(bag, slot)
        return info and info.isLocked
    end
    local _, _, locked = GetContainerItemInfo(bag, slot)
    return locked
end

-- Returns bag, slot, itemID of the best Healthstone. Locked stones (already in
-- the trade window, or on the cursor) are skipped unless includeLocked is set.
local function FindStone(includeLocked)
    local bestBag, bestSlot, bestRank
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetNumSlots(bag) or 0 do
            local rank = STONE_RANK[ContainerItemID(bag, slot) or 0]
            if rank and (not bestRank or rank < bestRank)
                and (includeLocked or not IsLocked(bag, slot)) then
                bestBag, bestSlot, bestRank = bag, slot, rank
            end
        end
    end
    if bestRank then
        return bestBag, bestSlot, STONE_ITEMS[bestRank]
    end
end

local function FirstFreeTradeSlot()
    for i = 1, MAX_TRADE_SLOTS do
        if not GetTradePlayerItemInfo(i) then
            return i
        end
    end
end

-- Spells ------------------------------------------------------------------

-- Calls fn(offset, numSpells) for each spellbook tab. Forever's client has the
-- C_SpellBook API instead of GetNumSpellTabs/GetSpellTabInfo.
local function ForEachSpellTab(fn)
    if SpellBook.GetNumSpellBookSkillLines then
        for tab = 1, SpellBook.GetNumSpellBookSkillLines() do
            local info = SpellBook.GetSpellBookSkillLineInfo(tab)
            if info then
                fn(info.itemIndexOffset, info.numSpellBookItems)
            end
        end
    elseif GetNumSpellTabs then
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, numSpells = GetSpellTabInfo(tab)
            fn(offset, numSpells)
        end
    end
end

local function BookItemName(index)
    if SpellBook.GetSpellBookItemName then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        return SpellBook.GetSpellBookItemName(index, bank)
    end
    return (GetSpellBookItemName or GetSpellName)(index, BOOK)
end

-- Every Create Healthstone entry in the spellbook, in book order.
local function ScanSpellbook()
    local found = {}
    ForEachSpellTab(function(offset, numSpells)
        for i = offset + 1, offset + numSpells do
            local name, rank = BookItemName(i)
            if name and name:find("^Create Healthstone") then
                found[#found + 1] = { name = name, rank = rank }
            end
        end
    end)
    return found
end

-- Returns the spell value for the secure button's "spell" attribute, and its
-- rank as an index into CREATE_SPELLS / STONE_ITEMS (nil when found only by
-- the spellbook fallback).
local function FindCreateSpell()
    if IsSpellKnown then
        for rank, spellID in ipairs(CREATE_SPELLS) do
            if IsSpellKnown(spellID) then
                return GetSpellName(spellID), rank
            end
        end
    end
    -- Fallback for spell IDs that differ on this client: the book lists ranks
    -- lowest first, so take the last entry.
    local found = ScanSpellbook()
    local last = found[#found]
    if last then
        if last.rank and last.rank ~= "" then
            return last.name .. "(" .. last.rank .. ")"
        end
        return last.name
    end
end

-- Buttons -----------------------------------------------------------------

local button
local refreshPending = false
-- Set when the button cast Create Healthstone; the new stone goes into the
-- trade. Holds the item ID being made when known, otherwise true.
local autoTrade = false

local function TradeHealthstone()
    -- The key binding can fire with no trade open; never leave a stone on the cursor.
    if CursorHasItem() or not TradeFrame:IsShown() then
        return
    end
    local bag, slot = FindStone(false)
    local tradeSlot = FirstFreeTradeSlot()
    if bag and tradeSlot then
        PickupItem(bag, slot)
        ClickTradeButton(tradeSlot)
    end
end

local function TryAutoTrade()
    if not autoTrade or not TradeFrame:IsShown() or CursorHasItem() then
        return
    end
    local _, _, itemID = FindStone(false)
    -- With a weaker stone already in the bags, wait for the new one: the
    -- soul shard used by the cast also fires BAG_UPDATE.
    if itemID and (autoTrade == true or itemID == autoTrade) then
        autoTrade = false
        TradeHealthstone()
    end
end

-- The button is protected: its attributes, visibility and enabled state can
-- only change out of combat. In combat it keeps its mode until
-- PLAYER_REGEN_ENABLED.
local function Refresh()
    if InCombatLockdown() then
        refreshPending = true
        return
    end
    refreshPending = false

    local spell, spellRank = FindCreateSpell()
    local _, _, itemID = FindStone(true)
    local enabled
    -- Each stone is unique, so with one in the bags we trade it, unless we
    -- know a better rank: then make that one (the weaker stone stays put).
    local better = itemID and spellRank and spellRank < STONE_RANK[itemID]
    button.target = spellRank and STONE_ITEMS[spellRank]
    if itemID and not better then
        button.mode = "trade"
        button:SetAttribute("type", nil)
        button:SetText("Trade Stone")
        enabled = FindStone(false) ~= nil
    else
        button.mode = "create"
        button:SetAttribute("type", "spell")
        button:SetText("Create & Trade")
        enabled = spell ~= nil
    end
    -- Fit the label, but never narrower than Blizzard's Trade button.
    local minWidth = TradeFrameTradeButton and TradeFrameTradeButton:GetWidth() or 0
    local text = button:GetFontString()
    button:SetWidth(math.max(minWidth, 85, text and text:GetStringWidth() + 24 or 0))
    button.spell, button.itemID = spell, itemID
    button:SetAttribute("spell", spell)
    -- Disabled outside a trade, so the key binding does nothing then.
    if enabled and TradeFrame:IsShown() and FirstFreeTradeSlot() then
        button:Enable()
    else
        button:Disable()
    end
    -- UI skins (EllesmereUI) draw the trade window as an overlay above even
    -- the DIALOG strata, which hides a button placed inside it. The button
    -- only shows while trading, so put it on the top strata.
    button:SetFrameStrata("TOOLTIP")
    button:SetShown(TradeFrame:IsShown())
end

-- Runs after the secure click. In create mode the secure template has cast
-- the spell; in trade mode it did nothing and the trade happens here.
local function PostClick(self)
    if self.mode == "trade" then
        TradeHealthstone()
    else
        autoTrade = self.target or true
    end
end

local function ItemName(itemID)
    return GetItemInfo(itemID) or ("item " .. itemID)
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Healthstone")
    if self.mode == "trade" then
        GameTooltip:AddLine("Trades " .. ItemName(self.itemID), 1, 1, 1)
        if not FindStone(false) then
            GameTooltip:AddLine("Your Healthstone is already in the trade.", 1, 0.3, 0.3)
        end
    elseif self.spell then
        GameTooltip:AddLine("Casts " .. self.spell .. ", then trades the stone", 1, 1, 1)
        if self.itemID then
            GameTooltip:AddLine("Your " .. ItemName(self.itemID) .. " is a lower rank and stays in your bags.",
                1, 0.82, 0)
        end
    else
        GameTooltip:AddLine("No Create Healthstone spell found.", 1, 0.3, 0.3)
    end
    if not FirstFreeTradeSlot() then
        GameTooltip:AddLine("No free trade slot.", 1, 0.3, 0.3)
    end
    GameTooltip:Show()
end

local function CreateButton()
    -- Parented to UIParent, not TradeFrame, so TradeFrame does not become
    -- protected in combat.
    button = CreateFrame("Button", "StoneDispenserButton", UIParent,
        "SecureActionButtonTemplate,UIPanelButtonTemplate")
    -- Same style and height as Blizzard's Trade/Cancel buttons, left of Trade.
    if TradeFrameTradeButton then
        -- A hidden frame can report a size of 0 at login, so keep a floor.
        button:SetSize(math.max(TradeFrameTradeButton:GetWidth(), 85),
            math.max(TradeFrameTradeButton:GetHeight(), 22))
        button:SetPoint("RIGHT", TradeFrameTradeButton, "LEFT", -4, 0)
    else
        button:SetSize(120, 22)
        button:SetPoint("TOPRIGHT", TradeFrame, "BOTTOMRIGHT", 0, -4)
    end
    -- Newer secure templates only act on key down when ActionButtonUseKeyDown
    -- is on (the default) and ignore mouse-up clicks. Make it act on mouse up.
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("PostClick", PostClick)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:Hide()

    TradeFrame:HookScript("OnShow", Refresh)
    TradeFrame:HookScript("OnHide", function()
        autoTrade = false
        Refresh()
    end)
end

-- Debug -------------------------------------------------------------------

local function Debug()
    Print("Known by spell ID:")
    for _, spellID in ipairs(CREATE_SPELLS) do
        local known = IsSpellKnown and IsSpellKnown(spellID)
        Print(("  %d %s: %s"):format(spellID, tostring(GetSpellName(spellID)), known and "yes" or "no"))
    end
    Print("Spellbook entries:")
    for _, entry in ipairs(ScanSpellbook()) do
        Print(("  %s [%s]"):format(entry.name, tostring(entry.rank)))
    end
    Print("Button casts: " .. tostring(FindCreateSpell()))
    local bag, slot, itemID = FindStone(true)
    if itemID then
        Print(("Best stone: %s (%d) in bag %d slot %d, locked: %s"):format(
            ItemName(itemID), itemID, bag, slot, tostring(IsLocked(bag, slot))))
    else
        Print("Best stone: none in bags")
    end
    Print(("APIs: C_Container %s, GetContainerItemID %s, IsSpellKnown %s"):format(
        tostring(C_Container ~= nil), tostring(GetItemID ~= nil), tostring(IsSpellKnown ~= nil)))
end

-- Events ------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        if class ~= "WARLOCK" or not TradeFrame then
            self:UnregisterAllEvents()
            return
        end
        SLASH_STONEDISPENSER1 = "/stonedispenser"
        SlashCmdList.STONEDISPENSER = Debug

        CreateButton()
        -- Forever's client lacks some events (e.g. LEARNED_SPELL_IN_TAB), so
        -- register each one on its own and skip the ones it does not know.
        for _, name in ipairs({ "SPELLS_CHANGED", "BAG_UPDATE", "ITEM_LOCK_CHANGED",
            "TRADE_PLAYER_ITEM_CHANGED", "PLAYER_REGEN_ENABLED" }) do
            pcall(self.RegisterEvent, self, name)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if refreshPending then
            Refresh()
        end
        return
    elseif event == "BAG_UPDATE" then
        TryAutoTrade()
    end
    Refresh()
end)
