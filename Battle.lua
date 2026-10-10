local _, ns = ...
local L = ns.L
local Code, Trade = ns.Code, ns.Trade

-- Trading in PvP pet battles. When one opens while you're trading, the opponent's first pet name is
-- read as a trade code (see Code): a trade partner with a trusted code (see Trade:CheckOpponent)
-- gets a decision, who loses this game (see Code.Loses), shown at the top of the screen. The trade
-- key (see Bindings.xml) then does what fits: out of battle it queues for a PvP pet battle (and
-- accepts the match when it's found); in battle it forfeits when you're the one to lose, and
-- otherwise does nothing. Results against trade partners are counted, and your pet's name is
-- brought up to date once you're out of the battle.
local Battle = {}
ns.Battle = Battle

local ALLY, ENEMY = Enum.BattlePetOwner.Ally, Enum.BattlePetOwner.Enemy

-- The current battle, nil outside one: { state = "lose" | "win" | "stranger" | "untrusted",
-- partner = their code or nil, recorded, forfeited }.
local current
local statusFrame

-- The key bound to the trade action, e.g. "F", or nil.
function Battle.GetKey()
    local key = GetBindingKey("LINEUPTRADE_ACTION")
    return key and GetBindingText(key)
end

local function KeyText()
    return Battle.GetKey() or L["the trade key"]
end

local function GetStatusText()
    if not current then
        return nil
    elseif current.state == "lose" then
        return format(L["You lose this one: press %s to forfeit"], KeyText()), ORANGE_FONT_COLOR
    elseif current.state == "win" then
        return L["You win this one: wait for your partner to forfeit"], GREEN_FONT_COLOR
    elseif current.state == "untrusted" then
        return L["This player's code doesn't add up: play normally"], RED_FONT_COLOR
    end
    return L["Not a trade partner: play normally"], ns.MUTED_COLOR
end

-- The decision at the top of the screen while the battle lasts.
local function UpdateStatus()
    local text, color = GetStatusText()
    if not text then
        if statusFrame then
            statusFrame:Hide()
        end
        return
    end
    if not statusFrame then
        statusFrame = CreateFrame("Frame", nil, UIParent, "TooltipBackdropTemplate")
        statusFrame:SetFrameStrata("HIGH")
        statusFrame:SetPoint("TOP", 0, -110)
        statusFrame.Text = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        statusFrame.Text:SetPoint("CENTER")
    end
    statusFrame.Text:SetText(ns.TITLE .. ": " .. color:WrapTextInColorCode(text))
    statusFrame:SetSize(statusFrame.Text:GetUnboundedStringWidth() + 32, 36)
    statusFrame:Show()
end

local function OnBattleOpening()
    current = nil
    -- Trading is for PvP battles, while you've started it.
    if C_PetBattles.IsWildBattle() or C_PetBattles.IsPlayerNPC() or not Trade:IsActive()
        or not Trade:GetRecord() then
        return
    end
    current = { recorded = false }
    local id, balance, games, helper = Code.Decode(ns.db.eventKey, (C_PetBattles.GetName(ENEMY, 1)))
    if not id then
        current.state = "stranger"
    else
        local partner = { id = id, balance = balance, games = games, helper = helper }
        -- Your side as your pet name shows it: the record before this battle.
        local you = {
            id = Trade:GetPlayerID(), balance = Trade:GetBalance(), games = Trade:GetGames(),
            helper = Trade:IsHelper(),
        }
        local trusted, reason = Trade:CheckOpponent(id, balance, games)
        Trade:RememberOpponent(id, balance, games)
        current.partner = partner
        if trusted then
            current.state = Code.Loses(you, partner) and "lose" or "win"
        else
            current.state = "untrusted"
            ns:Debug("not trusted:", id, reason)
        end
    end
    UpdateStatus()
end

-- Counts the game against a trade partner (trusted or not: both sides count it, which keeps the
-- game counts in step).
local function Record(won)
    if current and current.partner and not current.recorded then
        current.recorded = true
        Trade:RecordResult(won)
    end
end

local function OnBattleClose()
    -- A forfeit may end the battle without a final round.
    if current and current.forfeited then
        Record(false)
    end
    current = nil
    UpdateStatus()
    -- Renaming the pet waits until you're out of the battle.
    C_Timer.After(1, function()
        Trade:UpdateCode()
        ns.Window:Refresh()
    end)
end

ns:RegisterEvent("PET_BATTLE_OPENING_START", OnBattleOpening)
ns:RegisterEvent("PET_BATTLE_FINAL_ROUND", function(winner)
    Record(winner == ALLY)
end)
ns:RegisterEvent("PET_BATTLE_CLOSE", OnBattleClose)
ns:RegisterEvent("UPDATE_BINDINGS", UpdateStatus)

-- The trade key: queue (or accept the found match) out of battle; in battle, forfeit when you're
-- the one to lose.
function Battle.Action()
    if C_PetBattles.IsInBattle() then
        if current and current.state == "lose" then
            current.forfeited = true
            C_PetBattles.ForfeitGame()
        elseif current and current.state == "win" then
            ns:Print(L["You win this one: wait for your partner to forfeit"])
        end
        return
    end
    if not Trade:IsActive() then
        ns:Print(L["Start trading in the window first (/lineup_trade)"])
        return
    end
    local queueState = C_PetBattles.GetPVPMatchmakingInfo()
    if queueState == "proposal" then
        C_PetBattles.AcceptQueuedPVPMatch()
    elseif queueState == "queued" or queueState == "suspended" then
        ns:Print(L["You're already in the queue"])
    else
        C_PetBattles.StartPVPMatchmaking()
    end
end

-- For Bindings.xml.
_G.LineupTrade_Action = Battle.Action
