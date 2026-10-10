local _, ns = ...
local L = ns.L

-- The trading team: your three best battle pets of the event's family, put into the Pet Journal's
-- battle slots, with the first one renamed to your trade code (see Code). Its own name is kept and
-- put back when trading stops.
local Team = {}
ns.Team = Team

local NUM_SLOTS = 3
-- The "family" for trading with the team already in the battle slots.
Team.OWN_TEAM = -1
local MAX_LEVEL = 25

-- Owned battle pets of a family (0 = any), best first: alive, then highest level, quality and
-- health.
local function GetCandidates(petType)
    local pets = {}
    for _, petID in ipairs(C_PetJournal.GetOwnedPetIDs() or {}) do
        local _, _, level, _, _, _, _, name, _, family, _, _, _, _, canBattle =
            C_PetJournal.GetPetInfoByPetID(petID)
        if canBattle and (petType == 0 or family == petType) then
            local health, maxHealth, _, _, rarity = C_PetJournal.GetPetStats(petID)
            pets[#pets + 1] = {
                petID = petID,
                name = name,
                level = level or 0,
                rarity = rarity or 0,
                alive = (health or 0) > 0,
                health = maxHealth or 0,
            }
        end
    end
    table.sort(pets, function(a, b)
        if a.alive ~= b.alive then
            return a.alive
        elseif a.level ~= b.level then
            return a.level > b.level
        elseif a.rarity ~= b.rarity then
            return a.rarity > b.rarity
        end
        return a.health > b.health
    end)
    return pets
end

-- Why the team can't be changed right now, or nil if it can.
function Team.GetBlocker()
    if C_PetBattles.IsInBattle() then
        return L["Not during a pet battle"]
    elseif not C_PetJournal.IsJournalUnlocked() then
        return L["The Pet Journal is locked"]
    end
end

-- The pets in the battle slots, for showing and checking the team: per slot { petID, name, icon,
-- level, rarity, petType, alive }, or false for an empty slot.
function Team.GetLoadout()
    local loadout = {}
    for slot = 1, NUM_SLOTS do
        local petID = C_PetJournal.GetPetLoadOutInfo(slot)
        local pet = false
        if petID then
            local _, customName, level, _, _, _, _, name, icon, petType =
                C_PetJournal.GetPetInfoByPetID(petID)
            local health, _, _, _, rarity = C_PetJournal.GetPetStats(petID)
            pet = {
                petID = petID, name = customName or name, icon = icon, level = level or 0,
                rarity = rarity or 1, petType = petType, alive = (health or 0) > 0,
            }
        end
        loadout[slot] = pet
    end
    return loadout
end

-- What's wrong with the team for trading with a family (0 = any, OWN_TEAM = as it is): message,
-- color; or nil when it's ready. Level 25 is needed for the Find Battle achievements.
function Team.Check(loadout, petType)
    local belowMax, wrongFamily
    for _, pet in ipairs(loadout) do
        if not pet then
            return L["A battle slot is empty"], RED_FONT_COLOR
        elseif not pet.alive then
            return L["A pet is dead; heal it before you queue"], RED_FONT_COLOR
        end
        belowMax = belowMax or pet.level < MAX_LEVEL
        wrongFamily = wrongFamily or (petType > 0 and pet.petType ~= petType)
    end
    if wrongFamily then
        return format(L["Not all pets are %s"], _G["BATTLE_PET_NAME_" .. petType]), RED_FONT_COLOR
    elseif belowMax then
        return L["Not all pets are level 25"], ORANGE_FONT_COLOR
    end
end

-- Whether all three battle slots have a pet.
function Team.IsFull()
    for slot = 1, NUM_SLOTS do
        if not C_PetJournal.GetPetLoadOutInfo(slot) then
            return false
        end
    end
    return true
end

-- Puts the best three pets of the family into the battle slots. Returns the pets, or nil and why
-- not. Pets below level 25 or dead pets are used when there aren't enough others, with a warning.
function Team.Fill(petType)
    local pets = GetCandidates(petType)
    if #pets < NUM_SLOTS then
        return nil, format(L["You have only %d battle pets of this family"], #pets)
    end
    local warning
    for slot = 1, NUM_SLOTS do
        local pet = pets[slot]
        C_PetJournal.SetPetLoadOutInfo(slot, pet.petID)
        if not pet.alive then
            warning = L["A pet in your team is dead; heal it before you queue"]
        elseif pet.level < MAX_LEVEL and not warning then
            warning = L["Not every pet in your team is level 25"]
        end
    end
    return { unpack(pets, 1, NUM_SLOTS) }, warning
end

-- Renames the first battle slot's pet to name, remembering its own name the first time.
-- leadPetID is the pet just put into the first slot, if known: the game may report the slot's
-- previous pet for a moment after it changed.
function Team.RenameLead(name, leadPetID)
    local petID = leadPetID or C_PetJournal.GetPetLoadOutInfo(1)
    if not petID then
        return
    end
    local renamed = ns.charDb.renamed
    if renamed and renamed.petID ~= petID then
        Team.RestoreName()
        renamed = nil
    end
    if not renamed then
        local _, customName = C_PetJournal.GetPetInfoByPetID(petID)
        ns.charDb.renamed = { petID = petID, customName = customName or "" }
    end
    C_PetJournal.SetCustomName(petID, name)
end

-- Gives the renamed pet its own name back (none: the species name).
function Team.RestoreName()
    local renamed = ns.charDb.renamed
    if not renamed then
        return
    end
    C_PetJournal.SetCustomName(renamed.petID, renamed.customName)
    ns.charDb.renamed = nil
end
