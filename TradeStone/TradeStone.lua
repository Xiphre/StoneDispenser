-- TradeStone: two warlock buttons on the trade window.
--   Create Healthstone: casts the best Create Healthstone you know (secure, needs a click).
--   Trade Healthstone:  puts the best Healthstone in your bags into the first free trade slot.

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
    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9TradeStone|r: " .. msg)
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

-- Returns the spell value for the secure button's "spell" attribute.
local function FindCreateSpell()
    if IsSpellKnown then
        for _, spellID in ipairs(CREATE_SPELLS) do
            if IsSpellKnown(spellID) then
                return GetSpellName(spellID)
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

local createButton, tradeButton
local createPending = false

local function SetButtonEnabled(button, enabled)
    if enabled then
        button:Enable()
    else
        button:Disable()
    end
end

-- The create button is protected: its attributes, visibility and enabled
-- state can only change out of combat. In combat, wait for PLAYER_REGEN_ENABLED.
local function RefreshCreate()
    if InCombatLockdown() then
        createPending = true
        return
    end
    createPending = false

    local spell = FindCreateSpell()
    createButton.spell = spell
    createButton:SetAttribute("spell", spell)
    -- Only one Healthstone fits in the bags, so there is no point casting with one there.
    SetButtonEnabled(createButton, spell ~= nil and FindStone(true) == nil)
    createButton:SetShown(TradeFrame:IsShown())
end

local function RefreshTrade()
    local _, _, itemID = FindStone(false)
    tradeButton.itemID = itemID
    SetButtonEnabled(tradeButton, itemID ~= nil and FirstFreeTradeSlot() ~= nil)
end

local function Refresh()
    RefreshCreate()
    RefreshTrade()
end

local function TradeHealthstone()
    if CursorHasItem() then
        return
    end
    local bag, slot = FindStone(false)
    local tradeSlot = FirstFreeTradeSlot()
    if bag and tradeSlot then
        PickupItem(bag, slot)
        ClickTradeButton(tradeSlot)
    end
end

local function ItemName(itemID)
    return GetItemInfo(itemID) or ("item " .. itemID)
end

local function ShowTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    if button == createButton then
        GameTooltip:SetText("Create Healthstone")
        if not button.spell then
            GameTooltip:AddLine("No Create Healthstone spell found.", 1, 0.3, 0.3)
        else
            GameTooltip:AddLine("Casts " .. button.spell, 1, 1, 1)
            if FindStone(true) then
                GameTooltip:AddLine("You already have a Healthstone.", 1, 0.3, 0.3)
            end
        end
    else
        GameTooltip:SetText("Trade Healthstone")
        if not button.itemID then
            GameTooltip:AddLine("No Healthstone in your bags.", 1, 0.3, 0.3)
        else
            GameTooltip:AddLine("Trades " .. ItemName(button.itemID), 1, 1, 1)
            if not FirstFreeTradeSlot() then
                GameTooltip:AddLine("No free trade slot.", 1, 0.3, 0.3)
            end
        end
    end
    GameTooltip:Show()
end

local function CreateButtons()
    -- The trade button can live on TradeFrame. The secure button is parented
    -- to UIParent so TradeFrame does not become protected in combat.
    tradeButton = CreateFrame("Button", "TradeStoneTradeButton", TradeFrame, "UIPanelButtonTemplate")
    tradeButton:SetSize(130, 22)
    tradeButton:SetText("Trade Healthstone")
    local anchor = TradeFrameCancelButton or TradeFrame
    tradeButton:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    tradeButton:SetScript("OnClick", TradeHealthstone)

    createButton = CreateFrame("Button", "TradeStoneCreateButton", UIParent,
        "SecureActionButtonTemplate,UIPanelButtonTemplate")
    createButton:SetSize(130, 22)
    createButton:SetText("Create Healthstone")
    createButton:SetPoint("RIGHT", tradeButton, "LEFT", -4, 0)
    createButton:SetFrameStrata(TradeFrame:GetFrameStrata())
    createButton:SetFrameLevel(TradeFrame:GetFrameLevel() + 10)
    -- Newer secure templates only act on key down when ActionButtonUseKeyDown
    -- is on (the default) and ignore mouse-up clicks. Make it act on mouse up.
    createButton:RegisterForClicks("AnyUp")
    createButton:SetAttribute("useOnKeyDown", false)
    createButton:SetAttribute("type", "spell")
    createButton:Hide()

    for _, button in ipairs({ createButton, tradeButton }) do
        button:SetMotionScriptsWhileDisabled(true)
        button:SetScript("OnEnter", ShowTooltip)
        button:SetScript("OnLeave", GameTooltip_Hide)
    end

    TradeFrame:HookScript("OnShow", Refresh)
    TradeFrame:HookScript("OnHide", RefreshCreate)
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
    Print("Create button casts: " .. tostring(FindCreateSpell()))
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
        SLASH_TRADESTONE1 = "/tradestone"
        SLASH_TRADESTONE2 = "/ts"
        SlashCmdList.TRADESTONE = Debug

        CreateButtons()
        -- Forever's client lacks some events (e.g. LEARNED_SPELL_IN_TAB), so
        -- register each one on its own and skip the ones it does not know.
        for _, name in ipairs({ "SPELLS_CHANGED", "BAG_UPDATE", "ITEM_LOCK_CHANGED",
            "TRADE_PLAYER_ITEM_CHANGED", "PLAYER_REGEN_ENABLED" }) do
            pcall(self.RegisterEvent, self, name)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if createPending then
            RefreshCreate()
        end
        return
    end
    Refresh()
end)
