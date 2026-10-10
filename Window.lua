local _, ns = ...
local L = ns.L
local Trade, Team, Achievements, Battle = ns.Trade, ns.Team, ns.Achievements, ns.Battle

-- The trading window (/lineup_trade), laid out like Blizzard's Pet Journal: sections sunk into the
-- window (Blizzard's inset frames, with their own, darker background), each with its title in
-- gold above it, in two columns:
--   Event (key, wins goal)       | Team (family choice, the pets in the battle slots)
--   Progress (wins towards the   | Achievements (PvP pet battle achievements, drawn like the
--   goal, balance, pet name,     | rows of Blizzard's Achievements window, on its parchment)
--   trade key)                   |
-- and a footer with the emblem and name, what happened, and Start / Stop.
local Window = {}
ns.Window = Window

local WINDOW_WIDTH, WINDOW_HEIGHT = 660, 424
-- Insets: ButtonFrameTemplate's left border is wider than its right one.
local INSET_LEFT, INSET_RIGHT = 12, -8
local COLUMN_GAP = 10
local COLUMN_WIDTH = (WINDOW_WIDTH - INSET_LEFT + INSET_RIGHT - COLUMN_GAP) / 2
-- Content inside an inset is padded this much.
local PADDING = 10
local CONTENT_WIDTH = COLUMN_WIDTH - 2 * PADDING
local TITLE_HEIGHT = 20
local SECTION_GAP = 10
-- Below the window's title bar.
local CONTENT_TOP = -28
local TOP_ROW_HEIGHT = 104
local BOTTOM_ROW_HEIGHT = 194
local LABEL_WIDTH = 90
-- Small labels before a badge, so the badges line up.
local SMALL_LABEL_WIDTH = 70
local ROW_HEIGHT = 28
local SLOT_ICON_SIZE = 32
-- Achievement rows, like the summary rows in Blizzard's Achievements window.
local ACHIEVEMENT_HEIGHT = 50
local NUM_ACHIEVEMENTS = 3
local GOLD = CreateColor(1, 0.82, 0)
-- Blizzard's achievement art (see Blizzard_AchievementUI): the Achievements window's background,
-- its achievement rows and its progress bars.
local ART = "Interface\\AchievementFrame\\"
local EARNED_BORDER = CreateColor(0.7, 0.15, 0.05)

local window, keyBox, goalBox, familyDropdown, statusText, startButton, teamCheckText
local progressBar, balanceValue, recordValue, idValue, helperBadge, codeBadge, helperText
local tradeKeyBadge
local slotIcons, achievementRows = {}, {}

local function SetStatus(message, isError)
    statusText:SetText(message or "")
    statusText:SetTextColor((isError and RED_FONT_COLOR or ns.MUTED_COLOR):GetRGB())
end

-- A section like the Pet Journal's: an inset sunk into the window in column 1 or 2, top pixels
-- below the window's top, with its title in gold above it. Returns the inset (content goes in it,
-- PADDING in from its edges) and the title.
local function CreateSection(text, column, top, height)
    local x = INSET_LEFT + (column - 1) * (COLUMN_WIDTH + COLUMN_GAP)
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", x + 4, top)
    title:SetText(text)
    local inset = CreateFrame("Frame", nil, window, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", x, top - TITLE_HEIGHT)
    inset:SetSize(COLUMN_WIDTH, height)
    return inset, title
end

local function CreateSmallText(parent, color)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    text:SetSpacing(2)
    text:SetTextColor((color or ns.MUTED_COLOR):GetRGB())
    return text
end

-- A label on the left of a row in a section, top pixels below the inset's top.
local function CreateRowLabel(parent, text, top)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", PADDING, top - 4)
    label:SetWidth(LABEL_WIDTH)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function CreateEditBox(parent, label, width)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetPoint("LEFT", label, "RIGHT", 6, 0)
    box:SetSize(width, 22)
    box:SetAutoFocus(false)
    box:SetScript("OnEnterPressed", EditBox_ClearFocus)
    return box
end

-- A progress bar like the ones in Blizzard's Achievements window: green with a gold border.
local function CreateBar(parent, height)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(height)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0, 0.6, 0)
    bar:GetStatusBarTexture():SetDrawLayer("BORDER")
    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.4)
    local function Border(left, right)
        local texture = bar:CreateTexture(nil, "ARTWORK")
        texture:SetTexture(ART .. "UI-Achievement-ProgressBar-Border")
        texture:SetTexCoord(left, right, 0, 0.75)
        return texture
    end
    local borderLeft = Border(0, 0.0625)
    borderLeft:SetWidth(16)
    borderLeft:SetPoint("TOPLEFT", -6, 5)
    borderLeft:SetPoint("BOTTOMLEFT", -6, -5)
    local borderRight = Border(0.812, 0.8745)
    borderRight:SetWidth(16)
    borderRight:SetPoint("TOPRIGHT", 6, 5)
    borderRight:SetPoint("BOTTOMRIGHT", 6, -5)
    local borderCenter = Border(0.0625, 0.812)
    borderCenter:SetPoint("TOPLEFT", borderLeft, "TOPRIGHT")
    borderCenter:SetPoint("BOTTOMRIGHT", borderRight, "BOTTOMLEFT")
    bar.Text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.Text:SetPoint("CENTER", 0, 1)
    return bar
end

-- A bar like the "Progress Overview" ones in Blizzard's Achievements window: a gold label on the
-- left, the count on the right, in the achievement header's frame.
local function CreateOverviewBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(21)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0, 0.6, 0)
    local fill = bar:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0, 0, 0, 0.5)
    local function Border(left, right)
        local texture = bar:CreateTexture(nil, "OVERLAY")
        texture:SetTexture(ART .. "UI-Achievement-Header")
        texture:SetTexCoord(left, right, 0.56640625, 0.75)
        return texture
    end
    local borderLeft = Border(0.423828125, 0.486)
    borderLeft:SetSize(32, 48)
    borderLeft:SetPoint("TOPLEFT", -15, 16)
    local borderRight = Border(0.486, 0.423828125)
    borderRight:SetSize(32, 48)
    borderRight:SetPoint("TOPRIGHT", 15, 16)
    local borderMiddle = Border(0.889224609375, 0.486)
    borderMiddle:SetPoint("TOPLEFT", borderLeft, "TOPRIGHT")
    borderMiddle:SetPoint("BOTTOMRIGHT", borderRight, "BOTTOMLEFT")
    bar.Label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bar.Label:SetPoint("LEFT", 6, 1)
    bar.Text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bar.Text:SetPoint("RIGHT", -5, 1)
    return bar
end

-- Event: key and wins goal.
local function CreateEventSection(top)
    local inset = CreateSection(L["Event"], 1, top, TOP_ROW_HEIGHT)

    local keyLabel = CreateRowLabel(inset, L["Event key"], -PADDING)
    keyBox = CreateEditBox(inset, keyLabel, CONTENT_WIDTH - LABEL_WIDTH - 10)
    keyBox:SetMaxLetters(32)
    keyBox:SetScript("OnTextChanged", function(box, userInput)
        if userInput then
            ns.db.eventKey = box:GetText()
            Window:Refresh()
        end
    end)
    -- The pet name follows the key once typing is done, not on every letter.
    keyBox:SetScript("OnEditFocusLost", function()
        Trade:RestoreFromPetName()
        Trade:UpdateCode()
        Window:Refresh()
    end)
    ns.SetTooltip(keyBox, L["Event key"], L["The same word for everyone in the event; only players "
        .. "with the same key are trade partners. Each key keeps its own wins and losses."])

    goalBox = CreateEditBox(inset, CreateRowLabel(inset, L["Wins goal"], -PADDING - ROW_HEIGHT), 50)
    goalBox:SetNumeric(true)
    goalBox:SetMaxLetters(4)
    goalBox:SetScript("OnTextChanged", function(box, userInput)
        if userInput then
            ns.db.goal = tonumber(box:GetText()) or 0
            Window:Refresh()
        end
    end)
    -- Reaching or leaving the goal switches helper mode, which is part of the pet name.
    goalBox:SetScript("OnEditFocusLost", function()
        Trade:UpdateCode()
        Window:Refresh()
    end)
    ns.SetTooltip(goalBox, L["Wins goal"], L["How many wins you need, 0 for no goal. Once you "
        .. "reach it, you become a helper: you lose every game against players who haven't "
        .. "reached their goal, so they get their wins faster. Two helpers play it out like "
        .. "everyone else."])
end

-- The pets in the battle slots: icon with quality border and level, dead pets greyed out; and
-- whether the team is ready (see Team.Check), below them.
local function CreateSlots(inset, top)
    for slot = 1, 3 do
        local icon = CreateFrame("Frame", nil, inset)
        icon:SetSize(SLOT_ICON_SIZE, SLOT_ICON_SIZE)
        if slot == 1 then
            icon:SetPoint("TOPLEFT", PADDING + LABEL_WIDTH + 6, top)
        else
            icon:SetPoint("LEFT", slotIcons[slot - 1], "RIGHT", 6, 0)
        end
        icon.Texture = icon:CreateTexture(nil, "ARTWORK")
        icon.Texture:SetAllPoints()
        icon.Border = icon:CreateTexture(nil, "OVERLAY")
        icon.Border:SetAllPoints()
        icon.Border:SetTexture("Interface\\Common\\WhiteIconFrame")
        icon.Level = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        icon.Level:SetPoint("BOTTOMRIGHT", 1, -1)
        icon:SetScript("OnEnter", function()
            local pet = icon.pet
            GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
            if pet then
                GameTooltip:SetText(pet.name, ns.GetRarityColor(pet.rarity))
                local level = format(L["Level %d"], pet.level)
                GameTooltip:AddLine(level .. " · " .. ns.FormatFamily(pet.petType), 1, 1, 1)
                if not pet.alive then
                    GameTooltip:AddLine(L["Dead"], RED_FONT_COLOR:GetRGB())
                end
            else
                GameTooltip:SetText(L["Empty battle slot"])
            end
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", GameTooltip_Hide)
        slotIcons[slot] = icon
    end
    teamCheckText = CreateSmallText(inset)
    teamCheckText:SetPoint("TOPLEFT", slotIcons[1], "BOTTOMLEFT", 0, -6)
    teamCheckText:SetPoint("RIGHT", -PADDING, 0)
end

-- Team: which pets to trade with, and the pets in the battle slots.
local function CreateTeamSection(top)
    local inset = CreateSection(L["Team"], 2, top, TOP_ROW_HEIGHT)
    familyDropdown = CreateFrame("DropdownButton", nil, inset, "WowStyle1DropdownTemplate")
    -- The dropdown is taller than a row; this row starts lower so it has room above it.
    familyDropdown:SetPoint("LEFT", CreateRowLabel(inset, L["Pets"], -PADDING - 4), "RIGHT", 0, 0)
    familyDropdown:SetWidth(CONTENT_WIDTH - LABEL_WIDTH)
    familyDropdown:SetupMenu(function(_, root)
        local function IsSelected(petType)
            return ns.db.family == petType
        end
        local function Select(petType)
            local ok, message = Trade:SetFamily(petType)
            SetStatus(message, not ok)
            Window:Refresh()
        end
        root:CreateRadio(L["Your current team"], IsSelected, Select, Team.OWN_TEAM)
        root:CreateRadio(L["Any family"], IsSelected, Select, 0)
        for petType = 1, ns.NUM_FAMILIES do
            root:CreateRadio(ns.FormatFamily(petType), IsSelected, Select, petType)
        end
    end)

    local slotsTop = -PADDING - ROW_HEIGHT - 8
    local slotsLabel = CreateRowLabel(inset, L["Battle slots"], slotsTop)
    slotsLabel:SetPoint("TOPLEFT", PADDING, slotsTop - (SLOT_ICON_SIZE - 12) / 2)
    CreateSlots(inset, slotsTop)
end

-- A stat: a small muted label over a large value, at x, top in an inset, width wide. Returns the
-- value's font string.
local function CreateStat(inset, label, x, top, width)
    local text = CreateSmallText(inset)
    text:SetPoint("TOPLEFT", x, top)
    text:SetWidth(width)
    text:SetText(label)
    local value = inset:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    value:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -4)
    value:SetWidth(width)
    value:SetJustifyH("LEFT")
    return value
end

-- Progress: wins towards the goal; balance, wins and losses, and your ID as stats; your pet name
-- code; and helper mode (a badge next to the title, and what it means).
local function CreateProgressSection(top)
    local inset, title = CreateSection(L["Progress"], 1, top, BOTTOM_ROW_HEIGHT)
    helperBadge = ns.CreateBadge(window)
    helperBadge:SetPoint("LEFT", title, "RIGHT", 8, 0)

    progressBar = CreateOverviewBar(inset)
    progressBar:SetPoint("TOPLEFT", PADDING + 6, -PADDING - 6)
    progressBar:SetPoint("RIGHT", -PADDING - 6, 0)
    progressBar.Label:SetText(L["Wins"])

    local statTop, statWidth = -PADDING - 6 - 21 - 16, CONTENT_WIDTH / 3
    balanceValue = CreateStat(inset, L["Balance"], PADDING, statTop, statWidth)
    recordValue = CreateStat(inset, L["Wins / losses"], PADDING + statWidth, statTop, statWidth)
    idValue = CreateStat(inset, L["Your ID"], PADDING + 2 * statWidth, statTop, statWidth)

    -- Your pet name code: the name your first pet carries while you trade.
    local codeLabel = CreateSmallText(inset)
    codeLabel:SetPoint("TOPLEFT", PADDING, statTop - 50)
    codeLabel:SetText(L["Pet name"])
    codeLabel:SetWidth(SMALL_LABEL_WIDTH)
    codeBadge = ns.CreateBadge(inset, 1.2)
    codeBadge:SetPoint("LEFT", codeLabel, "RIGHT", 10, 0)
    ns.SetTooltip(codeBadge, L["Pet name"], L["Your first pet carries this name while you trade. "
        .. "It tells trade partners your ID, balance and games played."])

    -- The trade key, below the pet name.
    local keyLabel = CreateSmallText(inset)
    keyLabel:SetPoint("TOPLEFT", codeLabel, "BOTTOMLEFT", 0, -16)
    keyLabel:SetText(L["Trade key"])
    keyLabel:SetWidth(SMALL_LABEL_WIDTH)
    tradeKeyBadge = ns.CreateBadge(inset, 1.2)
    tradeKeyBadge:SetPoint("LEFT", keyLabel, "RIGHT", 10, 0)
    -- What the key does, and a click to set it.
    tradeKeyBadge:EnableMouse(true)
    tradeKeyBadge:SetScript("OnEnter", function()
        GameTooltip:SetOwner(tradeKeyBadge, "ANCHOR_TOP")
        GameTooltip:SetText(L["Trade key"])
        GameTooltip:AddLine(L["Out of battle it queues for a PvP pet battle and accepts the match. "
            .. "In battle it forfeits when you're the one to lose, and does nothing when you win."],
            1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click to set it in the key bindings."], GREEN_FONT_COLOR:GetRGB())
        GameTooltip:Show()
    end)
    tradeKeyBadge:SetScript("OnLeave", GameTooltip_Hide)
    -- A click opens the key bindings at Lineup Trade's section, named ns.TITLE (see Core.lua;
    -- this window would cover them).
    tradeKeyBadge:SetScript("OnMouseUp", function()
        GameTooltip:Hide()
        window:Hide()
        Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID, ns.TITLE)
    end)

    -- While you're a helper, what that means.
    helperText = CreateSmallText(inset, GOLD)
    helperText:SetPoint("TOPLEFT", keyLabel, "BOTTOMLEFT", 0, -14)
    helperText:SetPoint("RIGHT", -PADDING, 0)
    helperText:SetText(L["Goal reached: you're a helper now. You lose every game against players "
        .. "who haven't reached their goal yet, so they get their wins faster."])
end

-- An achievement row built like the summary rows of Blizzard's Achievements window
-- (SummaryAchievementTemplate): parchment with the title bar across the top and a glow below it,
-- the icon in its frame on the left, the points shield on the right, the name in the title bar;
-- where Blizzard shows the description, the achievement's progress bar. Earned ones are in
-- colour, the others in grey, as Blizzard does it.
local function CreateAchievementRow(inset, top)
    local row = CreateFrame("Frame", nil, inset, "TooltipBorderBackdropTemplate")
    row:SetHeight(ACHIEVEMENT_HEIGHT)
    row:SetPoint("TOPLEFT", PADDING - 2, top)
    row:SetPoint("RIGHT", -PADDING + 2, 0)

    row.Background = row:CreateTexture(nil, "BACKGROUND")
    row.Background:SetPoint("TOPLEFT", 3, -3)
    row.Background:SetPoint("BOTTOMRIGHT", -3, 3)
    row.Background:SetTexCoord(0, 1, 0, 0.25)

    row.TitleBar = row:CreateTexture(nil, "ARTWORK")
    row.TitleBar:SetTexture(ART .. "UI-Achievement-Borders")
    row.TitleBar:SetHeight(20)
    row.TitleBar:SetPoint("TOPLEFT", 5, -4)
    row.TitleBar:SetPoint("TOPRIGHT", -5, -4)
    row.TitleBar:SetAlpha(0.8)
    row.Glow = row:CreateTexture(nil, "ARTWORK")
    row.Glow:SetTexture(ART .. "UI-Achievement-Borders")
    row.Glow:SetTexCoord(0, 1, 0.00390625, 0.25390625)
    row.Glow:SetPoint("TOPLEFT", row.TitleBar, "BOTTOMLEFT", 0, 2)
    row.Glow:SetPoint("BOTTOMRIGHT", 0, 4)

    row.Label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    row.Label:SetPoint("TOP", row.TitleBar, "TOP", 0, 0)
    row.Label:SetHeight(20)
    row.Label:SetPoint("LEFT", 52, 0)
    row.Label:SetPoint("RIGHT", -52, 0)
    row.Label:SetWordWrap(false)

    -- The icon in its frame, top left.
    local icon = CreateFrame("Frame", nil, row)
    icon:SetSize(48, 48)
    icon:SetPoint("TOPLEFT", 3, -3)
    row.Icon = icon:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(36, 36)
    row.Icon:SetPoint("CENTER", 0, 3)
    row.IconFrame = icon:CreateTexture(nil, "OVERLAY")
    row.IconFrame:SetTexture(ART .. "UI-Achievement-IconFrame")
    row.IconFrame:SetTexCoord(0, 0.5625, 0, 0.5625)
    row.IconFrame:SetSize(46, 46)
    row.IconFrame:SetPoint("CENTER", -1, 2)

    -- The points shield, top right.
    local shield = CreateFrame("Frame", nil, row)
    shield:SetSize(48, 48)
    shield:SetPoint("TOPRIGHT", -10, -4)
    row.Shield = shield:CreateTexture(nil, "BACKGROUND")
    row.Shield:SetTexture(ART .. "UI-Achievement-Shields")
    row.Shield:SetAllPoints()
    row.Points = shield:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.Points:SetPoint("CENTER", 0, 3)

    -- Progress, where Blizzard shows the description.
    row.Bar = CreateBar(row, 10)
    row.Bar:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -27)
    row.Bar:SetPoint("RIGHT", shield, "LEFT", -12, 0)

    -- Name, description and progress (Blizzard's achievement link tooltip often only says
    -- "Retrieving data" for achievements not earned yet).
    row:SetScript("OnEnter", function()
        local achievement = row.achievement
        if achievement then
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:SetText(achievement.name, GOLD:GetRGB())
            if achievement.description then
                GameTooltip:AddLine(achievement.description, 1, 1, 1, true)
            end
            GameTooltip:AddLine(" ")
            if achievement.completed then
                GameTooltip:AddLine(L["Earned"], GREEN_FONT_COLOR:GetRGB())
            else
                local progress = format("%d / %d", achievement.quantity, achievement.required)
                GameTooltip:AddLine(progress, ns.MUTED_COLOR:GetRGB())
            end
            local hint = L["Click to open it in the Achievements window."]
            GameTooltip:AddLine(hint, GREEN_FONT_COLOR:GetRGB())
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    -- A click opens it in Blizzard's Achievements window (this window would cover it).
    row:SetScript("OnMouseUp", function()
        local achievement = row.achievement
        if achievement and achievement.id then
            GameTooltip:Hide()
            window:Hide()
            OpenAchievementFrameToAchievement(achievement.id)
        end
    end)
    return row
end

local function CreateAchievementSection(top)
    local inset = CreateSection(L["Achievements"], 2, top, BOTTOM_ROW_HEIGHT)
    -- The rows sit on the Achievements window's own background, as in Blizzard's.
    local background = inset:CreateTexture(nil, "BACKGROUND", nil, 1)
    background:SetTexture(ART .. "UI-Achievement-AchievementBackground")
    background:SetTexCoord(0, 1, 0, 0.5)
    background:SetPoint("TOPLEFT", 3, -3)
    background:SetPoint("BOTTOMRIGHT", -3, 3)
    -- The rows spread evenly over the parchment.
    local gap = (BOTTOM_ROW_HEIGHT - NUM_ACHIEVEMENTS * ACHIEVEMENT_HEIGHT) / (NUM_ACHIEVEMENTS + 1)
    for index = 1, NUM_ACHIEVEMENTS do
        local rowTop = -gap - (index - 1) * (ACHIEVEMENT_HEIGHT + gap)
        achievementRows[index] = CreateAchievementRow(inset, rowTop)
    end
end

-- Footer: the emblem and name on the left, Start / Stop on the right, what happened between.
local function CreateFooter()
    -- The emblem, name and what Lineup Trade is for, on the left.
    local emblem = window:CreateTexture(nil, "ARTWORK")
    emblem:SetSize(32, 32)
    emblem:SetPoint("BOTTOMLEFT", INSET_LEFT + 2, 7)
    emblem:SetTexture(ns.MEDIA .. "Icon")
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", emblem, "TOPRIGHT", 8, -2)
    title:SetText(ns.TITLE)
    local subtitle = CreateSmallText(window)
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    subtitle:SetText(L["Trade PvP pet battle wins at events"])

    -- Start / Stop on the right.
    startButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    startButton:SetSize(160, 26)
    startButton:SetPoint("BOTTOMRIGHT", INSET_RIGHT, 10)
    startButton:SetNormalFontObject("GameFontNormalLarge")
    startButton:SetHighlightFontObject("GameFontHighlightLarge")
    startButton:SetScript("OnClick", function()
        Window:StartStop()
    end)

    -- What happened, between them and next to the button.
    statusText = CreateSmallText(window)
    statusText:SetPoint("LEFT", window, "BOTTOMLEFT", INSET_LEFT + 220, 10 + 13)
    statusText:SetPoint("RIGHT", startButton, "LEFT", -12, 0)
    statusText:SetJustifyH("RIGHT")
    statusText:SetMaxLines(2)
end

local function RefreshSlots()
    local loadout = Team.GetLoadout()
    for slot, icon in ipairs(slotIcons) do
        local pet = loadout[slot]
        icon.pet = pet or nil
        icon.Texture:SetTexture(pet and pet.icon or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
        icon.Texture:SetDesaturated(pet and not pet.alive or false)
        icon.Border:SetShown(pet ~= false)
        if pet then
            icon.Border:SetVertexColor(ns.GetRarityColor(pet.rarity))
            icon.Level:SetText(pet.level < 25 and pet.level or "")
            icon.Level:SetTextColor((pet.alive and HIGHLIGHT_FONT_COLOR or RED_FONT_COLOR):GetRGB())
        else
            icon.Level:SetText("")
        end
    end
    local problem, color = Team.Check(loadout, ns.db.family)
    teamCheckText:SetText(problem or L["Team ready"])
    teamCheckText:SetTextColor((color or GREEN_FONT_COLOR):GetRGB())
end

local function RefreshProgress()
    local record = Trade:GetRecord()
    local wins, losses = record and record.wins or 0, record and record.losses or 0
    local goal = ns.db.goal
    local helper = Trade:IsHelper()
    if goal > 0 then
        progressBar:SetMinMaxValues(0, goal)
        progressBar:SetValue(min(wins, goal))
        progressBar.Text:SetText(format("%d / %d", wins, goal))
    else
        progressBar:SetMinMaxValues(0, 1)
        progressBar:SetValue(0)
        progressBar.Text:SetText(wins)
    end
    -- Gold once the goal is reached.
    if helper then
        progressBar:SetStatusBarColor(GOLD:GetRGB())
    else
        progressBar:SetStatusBarColor(0, 0.6, 0)
    end

    local balance = Trade:GetBalance()
    local balanceColor = balance > 0 and GREEN_FONT_COLOR or balance < 0 and RED_FONT_COLOR
        or HIGHLIGHT_FONT_COLOR
    balanceValue:SetText(balance > 0 and "+" .. balance or tostring(balance))
    balanceValue:SetTextColor(balanceColor:GetRGB())
    recordValue:SetText(format(L["%d W · %d L"], wins, losses))
    idValue:SetText(Trade:GetPlayerID())
    helperBadge:SetText(helper and L["Helper"] or nil, GOLD)
    helperText:SetShown(helper)

    local code = Trade:GetCode()
    codeBadge:SetText(code or L["Enter the event key first"], not code and ns.MUTED_COLOR or nil)
end

local function RefreshAchievements()
    for index, achievement in ipairs(Achievements.GetTracked(ns.db.family)) do
        local row = achievementRows[index]
        if row then
            local earned = achievement.completed
            row.achievement = achievement
            row.Icon:SetTexture(achievement.icon)
            row.Label:SetText(achievement.name)
            local points = achievement.points or 0
            row.Points:SetText(points > 0 and points or "")
            -- Blizzard's colours for earned achievements, and greys for the others.
            if earned then
                row.Background:SetTexture(ART .. "UI-Achievement-Parchment-Horizontal")
                row.TitleBar:SetTexCoord(0, 1, 0.66015625, 0.73828125)
                row:SetBackdropBorderColor(EARNED_BORDER:GetRGB())
                row.Glow:SetVertexColor(1, 1, 1)
                row.Icon:SetVertexColor(1, 1, 1)
                row.IconFrame:SetVertexColor(1, 1, 1)
                row.Shield:SetTexCoord(0, 0.5, 0, 0.5)
                row.Points:SetTextColor(1, 1, 1)
                row.Label:SetTextColor(1, 1, 1)
            else
                row.Background:SetTexture(ART .. "UI-Achievement-Parchment-Horizontal-Desaturated")
                row.TitleBar:SetTexCoord(0, 1, 0.91796875, 0.99609375)
                row:SetBackdropBorderColor(0.5, 0.5, 0.5)
                row.Glow:SetVertexColor(0.22, 0.17, 0.13)
                row.Icon:SetVertexColor(0.55, 0.55, 0.55)
                row.IconFrame:SetVertexColor(0.75, 0.75, 0.75)
                row.Shield:SetTexCoord(0.5, 1, 0, 0.5)
                row.Points:SetTextColor(0.65, 0.65, 0.65)
                row.Label:SetTextColor(0.65, 0.65, 0.65)
            end
            row.Bar:SetMinMaxValues(0, max(achievement.required, 1))
            row.Bar:SetValue(achievement.quantity)
            row.Bar.Text:SetText(format("%d / %d", achievement.quantity, achievement.required))
        end
    end
end

function Window:Refresh()
    if not window or not window:IsShown() then
        return
    end
    RefreshSlots()
    RefreshProgress()
    RefreshAchievements()
    local key = Battle.GetKey()
    tradeKeyBadge:SetText(key or L["Not set"], key and GOLD or ns.MUTED_COLOR)
    startButton:SetText(Trade:IsActive() and L["Stop"] or L["Start"])
    familyDropdown:GenerateMenu()
end

local function CreateWindow()
    window = CreateFrame("Frame", "LineupTradeWindow", UIParent, "ButtonFrameTemplate")
    -- Hidden until Toggle shows it (a new frame starts shown).
    window:Hide()
    window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    ButtonFrameTemplate_HidePortrait(window)
    window.Inset:Hide()
    window:SetTitle(ns.TITLE)
    tinsert(UISpecialFrames, window:GetName())

    local top = CONTENT_TOP
    CreateEventSection(top)
    CreateTeamSection(top)
    top = top - TITLE_HEIGHT - TOP_ROW_HEIGHT - SECTION_GAP
    CreateProgressSection(top)
    CreateAchievementSection(top)
    CreateFooter()

    window:SetScript("OnShow", function()
        keyBox:SetText(ns.db.eventKey)
        goalBox:SetText(tostring(ns.db.goal))
        SetStatus(Trade:IsActive() and L["Trading: queue for a PvP pet battle"] or nil)
        Window:Refresh()
    end)

    -- Achievement progress changes with every win; the battle slots with the journal (and with
    -- other addons that put pets in, like team managers); the trade key in the key bindings.
    local events = {
        "CRITERIA_UPDATE", "ACHIEVEMENT_EARNED", "PET_JOURNAL_LIST_UPDATE", "UPDATE_BINDINGS",
    }
    for _, event in ipairs(events) do
        ns:RegisterEvent(event, function()
            Window:Refresh()
        end)
    end
    hooksecurefunc(C_PetJournal, "SetPetLoadOutInfo", function()
        Window:Refresh()
    end)
end

-- Starts or stops trading (the Start / Stop button, or its key binding). What happened shows in the
-- footer, or in chat while the window is closed.
function Window:StartStop()
    local ok, message
    if Trade:IsActive() then
        ok, message = Trade:Stop()
        message = message or (ok and L["Stopped; your pet has its own name again"])
    else
        ok, message = Trade:Start()
        if ok and not message then
            message = L["Ready: queue for a PvP pet battle"]
        end
    end
    if window and window:IsShown() then
        SetStatus(message, not ok)
        self:Refresh()
    elseif message then
        ns:Print(not ok and RED_FONT_COLOR:WrapTextInColorCode(message) or message)
    end
end

function Window:Toggle()
    if not window then
        CreateWindow()
    end
    window:SetShown(not window:IsShown())
end

-- For Bindings.xml.
_G.LineupTrade_ToggleWindow = function()
    Window:Toggle()
end
_G.LineupTrade_StartStop = function()
    Window:StartStop()
end
