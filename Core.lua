local addonName, ns = ...
local L = ns.L

ns.TITLE = "Lineup Trade"
-- Path to the addon's own textures, e.g. ns.MEDIA .. "Icon".
ns.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

-- Defaults are copied into the saved variables on first load and whenever new keys are added.
-- Settings are shared by the account's characters; records and the renamed pet are per character,
-- like the ID in trade codes (see Code.GetID).
local DEFAULTS = {
    debug = false,
    eventKey = "",
    goal = 10,
    -- Pet family to trade with: 0 = any, or Team.OWN_TEAM to keep the team in the battle slots.
    family = 0,
}

local CHAR_DEFAULTS = {
    -- A record per event key (normalized, see Code.NormalizeKey); see Trade:GetRecord.
    records = {},
    active = false,
    -- The pet renamed to the code: { petID, customName } with its own name, to give it back.
    renamed = nil,
}

local function ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = type(value) == "table" and CopyTable(value) or value
        elseif type(value) == "table" and type(target[key]) == "table" then
            ApplyDefaults(target[key], value)
        end
    end
end

-- Muted text (hints, empty values): lighter than Blizzard's grey, so it's easy to read.
ns.MUTED_COLOR = CreateColor(0.75, 0.75, 0.75)

-- Pet families, indexed by pet type.
local FAMILY_SUFFIX = {
    "Humanoid", "Dragon", "Flying", "Undead", "Critter",
    "Magical", "Elemental", "Beast", "Water", "Mechanical",
}
ns.NUM_FAMILIES = #FAMILY_SUFFIX

-- "[icon] Beast" for a pet type.
function ns.FormatFamily(petType)
    local icon = "Interface\\Icons\\Icon_PetFamily_" .. FAMILY_SUFFIX[petType]
    return format("|T%s:14:14|t %s", icon, _G["BATTLE_PET_NAME_" .. petType])
end

-- r, g, b for a battle pet quality (1 = poor ... 4 = rare).
function ns.GetRarityColor(rarity)
    local color = ITEM_QUALITY_COLORS[(rarity or 1) - 1]
    if color then
        return color.r, color.g, color.b
    end
    return NORMAL_FONT_COLOR:GetRGB()
end

-- Shows title and text when the mouse is over frame.
function ns.SetTooltip(frame, title, text)
    frame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(frame, "ANCHOR_TOP")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

function ns:Print(...)
    print("|cff33ff99" .. ns.TITLE .. "|r:", ...)
end

function ns:Debug(...)
    if self.db and self.db.debug then
        self:Print("|cff888888[debug]|r", ...)
    end
end

-- Event dispatch: ns:RegisterEvent("EVENT_NAME", callback) calls callback(...) when it fires.
-- Without a callback, ns:EVENT_NAME(...) is called. An event can have several callbacks.
local frame = CreateFrame("Frame")
-- [event] = { { key = callback or METHOD, run = function(...) } }. Lists are replaced, not changed
-- in place, so a callback can unregister itself while the event is being dispatched.
local callbacks = {}
local METHOD = {} -- key for the ns:EVENT_NAME handler

frame:SetScript("OnEvent", function(_, event, ...)
    local list = callbacks[event]
    if list then
        for _, entry in ipairs(list) do
            entry.run(...)
        end
    end
end)

local function AddCallback(event, callback)
    local list = CopyTable(callbacks[event] or {}, true)
    tinsert(list, {
        key = callback or METHOD,
        run = callback or function(...)
            -- Calls the ns:EVENT_NAME handler; the IDE can't tell which method that is.
            ---@diagnostic disable-next-line: param-type-mismatch
            ns[event](ns, ...)
        end,
    })
    callbacks[event] = list
end

function ns:RegisterEvent(event, callback)
    AddCallback(event, callback)
    frame:RegisterEvent(event)
end

-- Removes the callback given to RegisterEvent (without one: the ns:EVENT_NAME handler). Other
-- callbacks for the event keep running.
function ns:UnregisterEvent(event, callback)
    local key = callback or METHOD
    local list = {}
    for _, entry in ipairs(callbacks[event] or {}) do
        if entry.key ~= key then
            list[#list + 1] = entry
        end
    end
    if #list > 0 then
        callbacks[event] = list
    else
        callbacks[event] = nil
        frame:UnregisterEvent(event)
    end
end

-- Lifecycle
function ns:ADDON_LOADED(loadedName)
    if loadedName ~= addonName then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")

    LineupTradeDB = LineupTradeDB or {}
    LineupTradeCharDB = LineupTradeCharDB or {}
    ApplyDefaults(LineupTradeDB, DEFAULTS)
    ApplyDefaults(LineupTradeCharDB, CHAR_DEFAULTS)
    self.db = LineupTradeDB
    self.charDb = LineupTradeCharDB
end

ns:RegisterEvent("ADDON_LOADED")

-- Global so the TOC's AddonCompartmentFunc can find it.
_G.LineupTrade_OnAddonCompartmentClick = function()
    ns.Window:Toggle()
end

-- Lineup Trade's own section in Options > Keybindings (see Bindings.xml): its name, a short
-- description at the top, and the names of its key bindings.
_G.BINDING_CATEGORY_LINEUPTRADE = ns.TITLE
_G.PREFACE_LINEUPTRADE = L["Keys for trading PvP pet battle wins at events. The trade key does what "
    .. "fits: out of battle it queues and accepts the match; in battle it forfeits when you're the "
    .. "one to lose."]
BINDING_NAME_LINEUPTRADE_ACTION = L["Trade action: queue, then forfeit or wait"]
BINDING_NAME_LINEUPTRADE_TOGGLE = L["Open or close the window"]
BINDING_NAME_LINEUPTRADE_STARTSTOP = L["Start or stop trading"]

-- Slash commands
SLASH_LINEUPTRADE1 = "/lineup_trade"

SlashCmdList.LINEUPTRADE = function(msg)
    local cmd = strtrim(msg or ""):lower()

    if cmd == "" then
        ns.Window:Toggle()
    elseif cmd == "debug" then
        ns.db.debug = not ns.db.debug
        ns:Print(L["Debug"], ns.db.debug and L["enabled"] or L["disabled"])
    else
        ns:Print(L["Commands:"])
        print(L["  /lineup_trade - open the window"])
        print(L["  /lineup_trade debug - toggle debug output"])
    end
end
