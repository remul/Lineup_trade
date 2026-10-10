local _, ns = ...

-- Trade codes, the only way to tell event players apart in a PvP pet battle: the opponent's name
-- is hidden, but their pets' names aren't. A code goes into the first pet's name, letters only
-- (pet names allow up to 16 characters):
--   "Lt" + ID (4) + balance (1) + games (2) + mode (1) + checksum (2), e.g. "LtAKZRMAFTQP"
-- - The ID is a hash of the character name and realm, so it stays the same for a character, also
--   after its saved data is deleted.
-- - The balance is wins minus losses, "M" for 0, from "A" (-12) to "Z" (+13).
-- - Games is the number of trade games played in the event, base 26 ("AA" = 0); it only goes up,
--   which is how a reset or an old, copied code is recognised (see Trade:CheckOpponent).
-- - Mode is "T" while trading for wins, "H" for a helper: a player who has reached their wins goal
--   and now loses every game against players who haven't (see Code.Loses).
-- - The checksum is a hash of the event key and the rest: only players with the same key read the
--   code, which keeps events apart and catches a code typed in by hand.
-- The team isn't part of the code: which pets someone plays says nothing about who they are.
local Code = {}
ns.Code = Code

local PREFIX = "Lt"
local PATTERN = "^" .. PREFIX .. "(%u%u%u%u)(%u)(%u)(%u)([TH])(%u%u)$"
local LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local BASE = #LETTERS
local ZERO = 13 -- position of "M", balance 0
Code.MIN_BALANCE, Code.MAX_BALANCE = 1 - ZERO, BASE - ZERO
Code.MAX_GAMES = BASE * BASE - 1

local function Letter(index)
    return LETTERS:sub(index, index)
end

local function LetterIndex(letter)
    return (LETTERS:find(letter, 1, true))
end

-- A small string hash, the same on every client.
---@param value string
---@return number
function Code.Hash(value)
    local hash = 7
    for index = 1, #value do
        hash = (hash * 31 + value:byte(index)) % 2147483647
    end
    return hash
end

-- The event key as it's compared: trimmed, case doesn't matter.
function Code.NormalizeKey(key)
    return strlower(strtrim(key or ""))
end

-- The 4-letter ID for a character ("Name", "Realm"); case doesn't matter.
function Code.GetID(name, realm)
    local hash = Code.Hash(strlower(name .. "-" .. realm))
    local id = ""
    for _ = 1, 4 do
        id = id .. Letter(hash % BASE + 1)
        hash = floor(hash / BASE)
    end
    return id
end

local function Checksum(key, body)
    local hash = Code.Hash(Code.NormalizeKey(key) .. ":" .. body)
    return Letter(hash % BASE + 1) .. Letter(floor(hash / BASE) % BASE + 1)
end

-- The pet name for a player: ID, balance (kept within MIN_BALANCE to MAX_BALANCE), games played
-- (up to MAX_GAMES) and whether they're a helper.
function Code.Encode(key, id, balance, games, helper)
    games = Clamp(games, 0, Code.MAX_GAMES)
    local body = id .. Letter(Clamp(balance, Code.MIN_BALANCE, Code.MAX_BALANCE) + ZERO)
        .. Letter(floor(games / BASE) + 1) .. Letter(games % BASE + 1) .. (helper and "H" or "T")
    return PREFIX .. body .. Checksum(key, body)
end

-- id, balance, games, helper from a pet name, or nil if it isn't a code for this event key.
function Code.Decode(key, name)
    if type(name) ~= "string" then
        return nil
    end
    local id, balanceLetter, gamesHigh, gamesLow, mode, checksum = name:match(PATTERN)
    if not id then
        return nil
    end
    local body = id .. balanceLetter .. gamesHigh .. gamesLow .. mode
    if Checksum(key, body) ~= checksum then
        return nil
    end
    local games = (LetterIndex(gamesHigh) - 1) * BASE + LetterIndex(gamesLow) - 1
    return id, LetterIndex(balanceLetter) - ZERO, games, mode == "H"
end

-- Whether player a loses this game against trade partner b. A helper loses against a player who
-- isn't one. Otherwise the one with the higher balance loses; on a tie (also at the start, 0
-- against 0) a hash of both IDs and their games decides, the same on both sides. Each player is
-- { id, balance, games, helper }.
function Code.Loses(a, b)
    if (a.helper or false) ~= (b.helper or false) then
        return a.helper == true
    elseif a.balance ~= b.balance then
        return a.balance > b.balance
    end
    local first, second = a.id, b.id
    if second < first then
        first, second = second, first
    end
    local firstLoses = Code.Hash(first .. second .. (a.games + b.games)) % 2 == 0
    return (a.id == first) == firstLoses
end
