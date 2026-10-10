local _, ns = ...
local L = ns.L

-- Achievements for PvP pet battle wins, shown with their progress in the window:
-- - "Pet Brawler" to "Legendary Pet Brawler": 10 to 5000 PvP wins;
-- - "Merciless" to "Deadly Pet Brawler": 10 to 1000 wins through Find Battle with a level 25 team;
-- - one "Brawler" per family (e.g. "Beast Brawler"): 10 such wins with a team of that family.
-- Of a series, the next one not earned yet is shown (the last one once all are).
local Achievements = {}
ns.Achievements = Achievements

local SERIES = {
    { 6595, 6596, 6597, 6598, 6599 },
    { 8297, 8298, 8300, 8301 },
}
-- Family achievements by pet type (1 Humanoid ... 10 Mechanical).
local FAMILY = { 12289, 12287, 12286, 12285, 12284, 12283, 12282, 12281, 12280, 12279 }

-- { id, name, description, icon, points, quantity, required, completed } for an achievement, or
-- nil if it's unknown.
local function Get(id)
    local _, name, points, completed, _, _, _, description, _, icon = GetAchievementInfo(id)
    if not name then
        return nil
    end
    local _, _, _, quantity, required = GetAchievementCriteriaInfo(id, 1)
    return {
        id = id, name = name, description = description, icon = icon, points = points,
        completed = completed,
        quantity = quantity or 0, required = required or 0,
    }
end

local function NextInSeries(ids)
    for _, id in ipairs(ids) do
        local achievement = Get(id)
        if achievement and not achievement.completed then
            return achievement
        end
    end
    return Get(ids[#ids])
end

-- The achievements to show for a pet family (0 or less, for any family or your own team: how many
-- family achievements are earned).
function Achievements.GetTracked(petType)
    local tracked = {}
    for _, ids in ipairs(SERIES) do
        tracked[#tracked + 1] = NextInSeries(ids)
    end
    if petType > 0 then
        tracked[#tracked + 1] = Get(FAMILY[petType])
    else
        -- Opens (see Window) at the first family achievement not earned yet.
        local earned, first, nextID = 0, Get(FAMILY[1]), nil
        for _, id in ipairs(FAMILY) do
            if select(4, GetAchievementInfo(id)) then
                earned = earned + 1
            else
                nextID = nextID or id
            end
        end
        tracked[#tracked + 1] = {
            id = nextID or FAMILY[1],
            name = L["Family Brawlers"],
            description = L["Win 10 PvP pet battles through Find Battle with a full team of level "
                .. "25 pets of each family."],
            icon = first and first.icon,
            quantity = earned,
            required = #FAMILY,
            completed = earned == #FAMILY,
        }
    end
    return tracked
end
