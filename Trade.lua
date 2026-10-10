local _, ns = ...
local L = ns.L
local Code, Team = ns.Code, ns.Team

-- Trading state: started with Start (team filled, first pet named with the code) and stopped with
-- Stop (its own name back). Each event key has its own record, so a new event (a new key) starts
-- at 0 and switching keys can't be used to wipe a record. A record holds your wins and losses, and
-- what you've seen of other players: their highest game count and the balance with it, and the IDs
-- caught with a lower count than seen before (a reset or a copied code), which aren't trusted
-- again in that event. Records are saved per character (ns.charDb); see Core.lua.
local Trade = {}
ns.Trade = Trade

-- Your ID, from your character's name and realm (see Code.GetID).
function Trade:GetPlayerID()
    return Code.GetID(UnitName("player"), GetNormalizedRealmName() or GetRealmName())
end

-- The record for the current event key, made on first use; nil without a key:
-- { wins, losses, seen = { [id] = { games, balance } }, distrusted = { [id] = true } }
function Trade:GetRecord()
    local key = Code.NormalizeKey(ns.db.eventKey)
    if key == "" then
        return nil
    end
    local record = ns.charDb.records[key]
    if not record then
        record = { wins = 0, losses = 0, seen = {}, distrusted = {} }
        ns.charDb.records[key] = record
    end
    return record
end

function Trade:GetBalance()
    local record = self:GetRecord()
    return record and record.wins - record.losses or 0
end

function Trade:GetGames()
    local record = self:GetRecord()
    return record and record.wins + record.losses or 0
end

-- Whether you're a helper in this event: you've reached your wins goal (0 = no goal), so you now
-- lose every game against players who haven't, to get them their wins faster (see Code.Loses).
function Trade:IsHelper()
    local record = self:GetRecord()
    return record ~= nil and ns.db.goal > 0 and record.wins >= ns.db.goal
end

-- The pet name for the current key and record, or nil without a key.
function Trade:GetCode()
    if not self:GetRecord() then
        return nil
    end
    return Code.Encode(ns.db.eventKey, self:GetPlayerID(), self:GetBalance(), self:GetGames(),
        self:IsHelper())
end

-- Whether an opponent's code (id, balance, games) can be trusted: not your own ID, not caught
-- before, and following on from what you saw of them last time (the game count only goes up, and
-- each game changes the balance by one). An opponent that doesn't follow on is caught: not trusted
-- for the rest of the event. Returns trusted, reason.
function Trade:CheckOpponent(id, balance, games)
    local record = self:GetRecord()
    if not record then
        return false, "no event key"
    elseif id == self:GetPlayerID() then
        return false, "your own ID"
    elseif record.distrusted[id] then
        return false, "caught before"
    end
    local seen = record.seen[id]
    if not seen then
        return true, "new"
    end
    local played, change = games - seen.games, abs(balance - seen.balance)
    if played < 0 or change > played or (played - change) % 2 == 1 then
        record.distrusted[id] = true
        return false, format("games %d, balance %+d after seeing games %d, balance %+d",
            games, balance, seen.games, seen.balance)
    end
    return true, "ok"
end

-- Remembers an opponent's code, if it's the newest seen of them.
function Trade:RememberOpponent(id, balance, games)
    local record = self:GetRecord()
    local seen = record and record.seen[id]
    if record and (not seen or games >= seen.games) then
        record.seen[id] = { games = games, balance = balance }
    end
end

-- After a crash, the saved record can be older than the last games played: WoW only saves addon
-- data on logout, reload or disconnect. A pet's name is saved by the server right away, though, so
-- the newest code is read back from it: from the renamed pet or, if the saved data is gone, from
-- any of your pets named with your code for this key. Without that, players you met since the
-- last save would have seen a higher game count than yours and stop trusting you. Returns true if
-- the record was brought up to date.
function Trade:RestoreFromPetName()
    local record = self:GetRecord()
    if not record then
        return false
    end
    local playerID = self:GetPlayerID()
    local renamed = ns.charDb.renamed
    local petIDs = renamed and { renamed.petID } or C_PetJournal.GetOwnedPetIDs() or {}
    local newest, newestPetID
    for _, petID in ipairs(petIDs) do
        local _, customName = C_PetJournal.GetPetInfoByPetID(petID)
        local id, balance, games = Code.Decode(ns.db.eventKey, customName)
        if id == playerID and (not newest or games > newest.games) then
            newest, newestPetID = { balance = balance, games = games }, petID
        end
    end
    if not newest then
        return false
    end
    if not renamed then
        -- The pet's own name went with the saved data; Stop gives it its species name.
        ns.charDb.renamed = { petID = newestPetID, customName = "" }
        ns.charDb.active = true
    end
    if newest.games <= record.wins + record.losses then
        return false
    end
    record.wins = (newest.games + newest.balance) / 2
    record.losses = (newest.games - newest.balance) / 2
    return true
end

-- Counts a trade game's result and updates the pet name to match.
function Trade:RecordResult(won)
    local record = self:GetRecord()
    if not record then
        return
    end
    if won then
        record.wins = record.wins + 1
    else
        record.losses = record.losses + 1
    end
    self:UpdateCode()
end

function Trade:IsActive()
    return ns.charDb.active
end

-- Starts trading: fills the team and names the first pet. Returns ok, message (what went wrong, or
-- a warning about the team).
function Trade:Start()
    if not self:GetRecord() then
        return false, L["Enter the event key first"]
    end
    local blocker = Team.GetBlocker()
    if blocker then
        return false, blocker
    end
    -- Your own team stays as it is; otherwise the best pets of the family are put in.
    local message, leadPetID
    if ns.db.family == Team.OWN_TEAM then
        if not Team.IsFull() then
            return false, L["Put three pets in your battle slots first"]
        end
    else
        local pets
        pets, message = Team.Fill(ns.db.family)
        if not pets then
            return false, message
        end
        leadPetID = pets[1].petID
    end
    Team.RenameLead(self:GetCode(), leadPetID)
    ns.charDb.active = true
    return true, message
end

-- Stops trading: the first pet gets its own name back. The record stays.
function Trade:Stop()
    local blocker = Team.GetBlocker()
    if blocker then
        return false, blocker
    end
    Team.RestoreName()
    ns.charDb.active = false
    return true
end

-- Chooses the team: a family (or 0 for any) puts your best pets of it into the battle slots right
-- away; Team.OWN_TEAM keeps the slots as they are. While trading, the first pet then carries the
-- code. Returns ok, message (why not, or a warning about the team).
function Trade:SetFamily(petType)
    ns.db.family = petType
    if petType == Team.OWN_TEAM then
        return true
    end
    local blocker = Team.GetBlocker()
    if blocker then
        return false, blocker
    end
    local pets, message = Team.Fill(petType)
    if not pets then
        return false, message
    end
    self:UpdateCode(pets[1].petID)
    return true, message
end

-- Brings the first pet's name up to date (after the key, the record or the team changed) while
-- trading. leadPetID: the pet just put into the first slot, if known (see Team.RenameLead).
function Trade:UpdateCode(leadPetID)
    local code = self:GetCode()
    if self:IsActive() and code and not Team.GetBlocker() then
        Team.RenameLead(code, leadPetID)
    end
end

-- Once the pet journal has its pets after logging in, catch up from the pet name (see above).
local function OnJournalReady()
    ns:UnregisterEvent("PET_JOURNAL_LIST_UPDATE", OnJournalReady)
    if Trade:RestoreFromPetName() then
        local record = Trade:GetRecord()
        ns:Print(format(L["Your record was restored from your pet's name: %d wins, %d losses"],
            record.wins, record.losses))
    end
end
ns:RegisterEvent("PET_JOURNAL_LIST_UPDATE", OnJournalReady)
