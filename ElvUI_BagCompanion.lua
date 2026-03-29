local addonName = ...
local E, L, V, P, G
if IsAddOnLoaded("ElvUI") then
    E, L, V, P, G = unpack(ElvUI)
end

----------------================================================----------------
----------------================ BASES & SETTINGS ================----------------
----------------================================================----------------
ElvUI_BagCompanionDB = ElvUI_BagCompanionDB or {}

local companionDefaults = {
    qualities = {
        poor = false, common = false, uncommon = true,
        rare = true, epic = true, legendary = true, vanity = true,
    },
    buttonsShown = false,
    confirmDelete = true, -- Настройка подтверждения удаления
}

local function InCombat() return InCombatLockdown and InCombatLockdown() end
local function GetSkinModule() if E and E.GetModule then return E:GetModule('Skins', true) end return nil end

local scanTooltip = CreateFrame("GameTooltip", "BagCompanionScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

StaticPopupDialogs["BAGCOMPANION_CONFIRM_DELETE"] = {
    text = "Are you sure you want to delete %s junk item(s)?\n|cffaaaaaa(You cannot undo this)|r",
    button1 = YES, button2 = NO,
    OnAccept = function(self, data) data() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

----------------================================================----------------
----------------============ SELL & DELETE LOGIC =============----------------
----------------================================================----------------
local function IsSoulbound(bag, slot)
    scanTooltip:ClearLines(); scanTooltip:SetBagItem(bag, slot)
    for i = 1, scanTooltip:NumLines() do
        local textFrame = _G["BagCompanionScanTooltipTextLeft" .. i]
        if textFrame then
            local text = textFrame:GetText()
            if text == ITEM_SOULBOUND or text == "Soulbound" or text == "Персональный предмет" then return true end
        end
    end
    return false
end

local function ExecuteDelete()
    local count = 0
    for b = 0, 4 do for s = 1, GetContainerNumSlots(b) do
        local link = GetContainerItemLink(b, s)
        if link then
            local _, _, r, _, _, t, _, _, e = GetItemInfo(link)
            if (r == 0 or (r == 1 and e and e ~= "")) and t ~= "Боеприпасы" and t ~= "Projectile" then
                PickupContainerItem(b, s); DeleteCursorItem(); count = count + 1
            end
        end
    end end
    print("|cff1784d1[BagCompanion]|r Deleted " .. count .. " item(s).")
end

local function PreDeleteCheck()
    local count = 0
    for b = 0, 4 do for s = 1, GetContainerNumSlots(b) do
        local link = GetContainerItemLink(b, s)
        if link then
            local _, _, r, _, _, t, _, _, e = GetItemInfo(link)
            if (r == 0 or (r == 1 and e and e ~= "")) and t ~= "Боеприпасы" and t ~= "Projectile" then count = count + 1 end
        end
    end end
    if count > 0 then
        if ElvUI_BagCompanionDB.confirmDelete then
            local dialog = StaticPopup_Show("BAGCOMPANION_CONFIRM_DELETE", count)
            if dialog then dialog.data = ExecuteDelete end
        else ExecuteDelete() end
    else print("|cff1784d1[BagCompanion]|r No junk found to delete.") end
end

local function SellGear()
    if not MerchantFrame:IsVisible() then print("|cFFFF0000[BagCompanion]|r Open the merchant window to sell items!"); return end
    local totalCopper, itemsSold = 0, 0
    for b = 0, 4 do for s = 1, GetContainerNumSlots(b) do
        local link = GetContainerItemLink(b, s)
        if link then
            local _, _, q, _, _, iType, _, _, _, _, itemPrice = GetItemInfo(link)
            local isGear = (iType == "Weapon" or iType == "Armor" or iType == "Оружие" or iType == "Броня")
            if (q == 2 or q == 3) and isGear then
                if q == 2 or (q == 3 and IsSoulbound(b, s)) then
                    UseContainerItem(b, s); itemsSold = itemsSold + 1
                    if itemPrice then totalCopper = totalCopper + itemPrice end
                end
            end
        end
    end end
    if itemsSold > 0 then print("|cff1784d1[BagCompanion]|r Sold " .. itemsSold .. " item(s) for " .. GetCoinTextureString(totalCopper))
    else print("|cff1784d1[BagCompanion]|r No gear to sell.") end
end

----------------================================================----------------
----------------============== TRANSFER LOGIC ================----------------
----------------================================================----------------
local function IsBankOpen()
    return (BankFrame and BankFrame:IsShown()) or 
           (GuildBankFrame and GuildBankFrame:IsShown()) or 
           (_G["ElvUI_BankContainerFrame"] and _G["ElvUI_BankContainerFrame"]:IsShown()) or
           (_G["BagnonFramebank"] and _G["BagnonFramebank"]:IsShown())
end

_G.ElvUI_BagCompanion_Run = function(mode, isWithdraw)
    if InCombat() then print("|cffff0000Cannot use in combat.|r"); return end
    local success, err = pcall(function()
        local db = ElvUI_BagCompanionDB.qualities
        local function IsQualityMatch(link)
            if not link then return false end
            if db.poor and link:find("9d9d9d") then return true end
            if db.common and link:find("ffffff") then return true end
            if db.uncommon and link:find("1eff00") then return true end
            if db.rare and link:find("0070dd") then return true end
            if db.epic and link:find("a335ee") then return true end
            if db.legendary and link:find("ff8000") then return true end
            if db.vanity and link:find("e6cc80") then return true end 
            return false
        end

        local function IsReagentMatch(link, category)
            if not link then return false end
            local _, _, _, _, _, _, itemSubType = GetItemInfo(link)
            if not itemSubType then return false end
            if category == "herbs" then return itemSubType == "Herb" or itemSubType == "Трава"
            elseif category == "leather" then return itemSubType == "Leather" or itemSubType == "Кожа"
            elseif category == "ore" then return itemSubType == "Metal & Stone" or itemSubType == "Металл и камень"
            elseif category == "cooking" then return itemSubType == "Meat" or itemSubType == "Мясо" or itemSubType == "Cooking" or itemSubType == "Кулинария" or itemSubType == "Fish" or itemSubType == "Рыба"
            elseif category == "cloth" then return itemSubType == "Cloth" or itemSubType == "Ткань" end
            return false
        end

        if mode == "vanity" then
            if C_AppearanceCollection and C_AppearanceCollection.CollectItemAppearance then
                for bag = 0, 4 do for slot = 1, GetContainerNumSlots(bag) do
                    local itemID = GetContainerItemID(bag, slot)
                    if itemID then
                        local appearanceID = C_Appearance.GetItemAppearanceID(itemID)
                        if appearanceID and not C_AppearanceCollection.IsAppearanceCollected(appearanceID) then
                            C_AppearanceCollection.CollectItemAppearance(GetContainerItemGUID(bag, slot))
                        end
                    end
                end end
            else print("|cffff0000Vanity API not found.|r") end
            return
        end

        if not IsBankOpen() then print("|cffffee00Open a Bank first.|r"); return end

        local function Deposit(matchFunc)
            for bag = 0, 4 do for slot = 1, GetContainerNumSlots(bag) do
                local link = GetContainerItemLink(bag, slot)
                if matchFunc(link) then UseContainerItem(bag, slot) end
            end end
        end

        local function Withdraw(matchFunc)
            if (GuildBankFrame and GuildBankFrame:IsShown()) then
                local tab = GetCurrentGuildBankTab()
                for slot = 1, 98 do
                    local link = GetGuildBankItemLink(tab, slot)
                    if matchFunc(link) then AutoStoreGuildBankItem(tab, slot) end
                end
            end
            if (BankFrame and BankFrame:IsShown()) or (_G["ElvUI_BankContainerFrame"] and _G["ElvUI_BankContainerFrame"]:IsShown()) or (_G["BagnonFramebank"] and _G["BagnonFramebank"]:IsShown()) then
                for bag = 5, 11 do for slot = 1, GetContainerNumSlots(bag) do
                    local link = GetContainerItemLink(bag, slot)
                    if matchFunc(link) then UseContainerItem(bag, slot) end
                end end
                for slot = 1, GetContainerNumSlots(-1) do
                    local link = GetContainerItemLink(-1, slot)
                    if matchFunc(link) then UseContainerItem(-1, slot) end
                end
            end
        end

        local currentMatchFunc
        if mode == "quality" then currentMatchFunc = IsQualityMatch
        elseif mode == "herbs" then currentMatchFunc = function(link) return IsReagentMatch(link, "herbs") end
        elseif mode == "leather" then currentMatchFunc = function(link) return IsReagentMatch(link, "leather") end
        elseif mode == "ore" then currentMatchFunc = function(link) return IsReagentMatch(link, "ore") end
        elseif mode == "cooking" then currentMatchFunc = function(link) return IsReagentMatch(link, "cooking") end
        elseif mode == "cloth" then currentMatchFunc = function(link) return IsReagentMatch(link, "cloth") end
        end

        if currentMatchFunc then
            if isWithdraw then Withdraw(currentMatchFunc) else Deposit(currentMatchFunc) end
        end
    end)
    if not success then print("|cffff0000[BagCompanion Error]|r " .. tostring(err)) end
end

----------------================================================----------------
----------------================ COMPANION GUI =================----------------
----------------================================================----------------
local holderFrame, barContainer, arrowBtn, settingsFrame
local buttonList = {}

local function CreateSettingsFrame()
    if settingsFrame then return end
    settingsFrame = CreateFrame("Frame", "ElvUI_BagCompanionSettings", UIParent)
    settingsFrame:SetSize(210, 290)
    settingsFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    settingsFrame:SetFrameLevel(100)
    settingsFrame:EnableMouse(true)
    
    if E then settingsFrame:SetTemplate("Default", true) else
        settingsFrame:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true, tileSize=16, edgeSize=16, insets={left=4,right=4,top=4,bottom=4}})
    end
    settingsFrame:Hide()

    local title = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -12); title:SetText("Bag Companion Settings")

    local S = GetSkinModule()
    local function AddCheck(y, label, key, r, g, b)
        local cb = CreateFrame("CheckButton", "ElvUI_BagCompanionCheck_"..key, settingsFrame, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 20, y)
        cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal"); cb.text:SetPoint("LEFT", cb, "RIGHT", 5, 0); cb.text:SetText(label); cb.text:SetTextColor(r, g, b)
        if S and S.HandleCheckBox then S:HandleCheckBox(cb) end
        cb:SetScript("OnClick", function(self) ElvUI_BagCompanionDB.qualities[key] = self:GetChecked() and true or false; PlaySound("igMainMenuOptionCheckBoxOn") end)
        cb:SetScript("OnShow", function(self) self:SetChecked(ElvUI_BagCompanionDB.qualities[key] and true or false) end)
    end

    AddCheck(-40, "Poor", "poor", .61, .61, .61); AddCheck(-65, "Common", "common", 1, 1, 1); AddCheck(-90, "Uncommon", "uncommon", .12, 1, 0); AddCheck(-115, "Rare", "rare", 0, .44, .87); AddCheck(-140, "Epic", "epic", .64, .21, .93); AddCheck(-165, "Legendary", "legendary", 1, .5, 0); AddCheck(-190, "Vanity", "vanity", .9, .8, .5)
    
    local cbDel = CreateFrame("CheckButton", "ElvUI_BagCompanionCheck_Confirm", settingsFrame, "UICheckButtonTemplate")
    cbDel:SetPoint("TOPLEFT", 20, -220)
    cbDel.text = cbDel:CreateFontString(nil, "OVERLAY", "GameFontNormal"); cbDel.text:SetPoint("LEFT", cbDel, "RIGHT", 5, 0); cbDel.text:SetText("Confirm Junk Delete"); cbDel.text:SetTextColor(1, 0.3, 0.3)
    if S and S.HandleCheckBox then S:HandleCheckBox(cbDel) end
    cbDel:SetScript("OnClick", function(self) ElvUI_BagCompanionDB.confirmDelete = self:GetChecked() and true or false; PlaySound("igMainMenuOptionCheckBoxOn") end)
    cbDel:SetScript("OnShow", function(self) self:SetChecked(ElvUI_BagCompanionDB.confirmDelete and true or false) end)

    local close = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
    close:SetSize(80, 22); close:SetPoint("BOTTOM", 0, 15); close:SetText("Close")
    if S and S.HandleButton then S:HandleButton(close) end
    close:SetScript("OnClick", function() settingsFrame:Hide() end)
end

local function UpdateArrowState()
    if not arrowBtn or not arrowBtn.tex then return end
    arrowBtn.tex:SetTexCoord(0, 1, ElvUI_BagCompanionDB.buttonsShown and 1 or 0, ElvUI_BagCompanionDB.buttonsShown and 0 or 1)
end

local function CreateCompanionUI()
    if holderFrame then return end
    local BTN_SIZE, BTN_SPACING = 40, 4

    holderFrame = CreateFrame("Frame", "ElvUI_BagCompanionHolder", UIParent)
    holderFrame:SetSize(1, 1); holderFrame:SetFrameStrata("HIGH"); holderFrame:SetFrameLevel(5); holderFrame:Hide()

    arrowBtn = CreateFrame("Button", nil, holderFrame)
    arrowBtn:SetSize(16, 16); arrowBtn:SetPoint("TOPLEFT", holderFrame, "TOPLEFT", 6, -6)
    arrowBtn.tex = arrowBtn:CreateTexture(nil, "ARTWORK"); arrowBtn.tex:SetAllPoints(); arrowBtn.tex:SetTexture("Interface\\AddOns\\ElvUI\\Media\\Textures\\ArrowUp")
    arrowBtn:SetScript("OnClick", function()
        if InCombat() then return end
        ElvUI_BagCompanionDB.buttonsShown = not ElvUI_BagCompanionDB.buttonsShown
        UpdateArrowState(); PlaySound("igMainMenuOptionCheckBoxOn")
    end)
    arrowBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")

    barContainer = CreateFrame("Frame", nil, holderFrame)
    barContainer:SetFrameStrata("HIGH"); barContainer:SetFrameLevel(4); barContainer:SetAlpha(0)

    local function MakeButton(icon, title, mode, isSettings)
        local b = CreateFrame("Button", nil, barContainer)
        b:SetSize(BTN_SIZE, BTN_SIZE)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.9)
        if E then b:SetTemplate("Default"); b.template = true else
            b:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1}); b:SetBackdropBorderColor(0,0,0,1)
        end
        local ic = b:CreateTexture(nil, "ARTWORK")
        ic:SetPoint("TOPLEFT", 1, -1); ic:SetPoint("BOTTOMRIGHT", -1, 1); ic:SetTexture(icon); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.iconTexture = ic
        
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines(); GameTooltip:AddLine(title, 1, 1, 1)
            if not isSettings then
                if mode == "vanity" then 
                    GameTooltip:AddLine("|cff00ff00Left Click:|r Collect Appearance")
                elseif mode == "sell" then
                    GameTooltip:AddLine("|cff00ff00Left Click:|r Sell green/blue equipment")
                    GameTooltip:AddLine("|cffaaaaaaIgnores BLUE BoE items|r")
                elseif mode == "junk" then
                    GameTooltip:AddLine("|cff00ff00Left Click:|r Delete gray/white items")
                    GameTooltip:AddLine("|cffaaaaaaSee settings for confirmation prompt|r")
                else
                    GameTooltip:AddLine("|cff00ff00Left Click:|r Deposit to Bank")
                    GameTooltip:AddLine("|cffff0000Right Click:|r Withdraw to Bags")
                end
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        
        b:SetScript("OnClick", function(self, buttonClicked)
            PlaySound("igMainMenuOptionCheckBoxOn")
            if isSettings then
                CreateSettingsFrame()
                if settingsFrame:IsShown() then settingsFrame:Hide() else 
                    settingsFrame:ClearAllPoints()
                    settingsFrame:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 0, 5)
                    settingsFrame:Show() 
                end
            elseif mode == "junk" then
                PreDeleteCheck()
            elseif mode == "sell" then
                SellGear()
            else
                ElvUI_BagCompanion_Run(mode, (buttonClicked == "RightButton"))
            end
        end)
        table.insert(buttonList, b)
        return b
    end

    local btns = {
        MakeButton("Interface\\Icons\\INV_Box_04", "Transfer by Quality", "quality"),
        MakeButton("Interface\\Icons\\inv_shirt_guildtabard_01", "Transmog Collection", "vanity"),
        MakeButton("Interface\\Icons\\inv_misc_herb_16", "Herbs", "herbs"),
        MakeButton("Interface\\Icons\\inv_misc_leatherscrap_07", "Leather", "leather"),
        MakeButton("Interface\\Icons\\inv_ore_mithril_02", "Ore & Stone", "ore"),
        MakeButton("Interface\\Icons\\inv_misc_food_132_meat", "Cooking Materials", "cooking"),
        MakeButton("Interface\\Icons\\inv_fabric_netherweave", "Cloth", "cloth"),
        MakeButton("Interface\\Icons\\inv_misc_coinbag_special", "Sell Equipment", "sell"),
        MakeButton("Interface\\Icons\\ability_siege_engineer_detonate", "Remove Junk", "junk"),
        MakeButton("Interface\\Icons\\trade_engineering", "Settings", nil, true)
    }

    for i, btn in ipairs(btns) do
        if i == 1 then btn:SetPoint("LEFT", barContainer, "LEFT", 0, 0)
        else btn:SetPoint("LEFT", btns[i-1], "RIGHT", BTN_SPACING, 0) end
    end
    
    local totalWidth = (#btns * BTN_SIZE) + ((#btns - 1) * BTN_SPACING)
    barContainer:SetSize(totalWidth, BTN_SIZE + 4)
    barContainer:SetPoint("BOTTOMLEFT", holderFrame, "TOPLEFT", 0, 4) 
    UpdateArrowState()
end

----------------================================================----------------
----------------============= ANIMATION & EVENTS =============----------------
----------------================================================----------------
local watcher = CreateFrame("Frame")
local timer, currentYOffset, currentAlpha = 0, -20, 0
watcher:SetScript("OnUpdate", function(self, elapsed)
    timer = timer + elapsed
    if timer < 0.016 then return end
    timer = 0
    if InCombat() then return end

    local bag = _G["ElvUI_ContainerFrame"]
    if bag and bag:IsShown() then
        if not holderFrame then CreateCompanionUI() end
        holderFrame:SetScale(bag:GetEffectiveScale())
        holderFrame:ClearAllPoints(); holderFrame:SetPoint("BOTTOMLEFT", bag, "TOPLEFT", 0, 5); holderFrame:Show()
        
        local isOpen = ElvUI_BagCompanionDB.buttonsShown
        local targetAlpha = isOpen and 1 or 0
        local targetY = isOpen and 4 or -20 
        
        local yDiff = targetY - currentYOffset
        if math.abs(yDiff) > 0.5 then currentYOffset = currentYOffset + (yDiff * 12 * elapsed) else currentYOffset = targetY end
        if isOpen then if currentYOffset > -5 then currentAlpha = currentAlpha + ((targetAlpha - currentAlpha) * 12 * elapsed) end
        else currentAlpha = currentAlpha + ((targetAlpha - currentAlpha) * 18 * elapsed) end

        if barContainer then
            barContainer:SetPoint("BOTTOMLEFT", holderFrame, "TOPLEFT", 0, currentYOffset)
            barContainer:SetAlpha(currentAlpha)
            if currentAlpha < 0.05 then barContainer:Hide() else barContainer:Show() end
        end
    else
        if holderFrame then holderFrame:Hide() end
        if settingsFrame then settingsFrame:Hide() end
        if ElvUI_BagCompanionDB and ElvUI_BagCompanionDB.buttonsShown then
            ElvUI_BagCompanionDB.buttonsShown = false; UpdateArrowState(); currentAlpha = 0; currentYOffset = -20
        end
    end
end)

local mainEventFrame = CreateFrame("Frame")
mainEventFrame:RegisterEvent("ADDON_LOADED")
mainEventFrame:RegisterEvent("MERCHANT_SHOW")

mainEventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        ElvUI_BagCompanionDB = ElvUI_BagCompanionDB or {}
        if not ElvUI_BagCompanionDB.qualities then ElvUI_BagCompanionDB.qualities = {} end
        for k, v in pairs(companionDefaults.qualities) do
            if ElvUI_BagCompanionDB.qualities[k] == nil then ElvUI_BagCompanionDB.qualities[k] = v end
        end
        if ElvUI_BagCompanionDB.buttonsShown == nil then ElvUI_BagCompanionDB.buttonsShown = false end
        if ElvUI_BagCompanionDB.confirmDelete == nil then ElvUI_BagCompanionDB.confirmDelete = true end

    elseif event == "MERCHANT_SHOW" then
        if ElvUI_BagCompanionDB then
            ElvUI_BagCompanionDB.buttonsShown = true
            if arrowBtn then UpdateArrowState() end
        end
    end
end)