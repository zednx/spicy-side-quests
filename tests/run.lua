-- Headless smoke test: stubs the WoW API, loads the addon and exercises it.
-- Run from the repo root: lua5.1 tests/run.lua
local ADDON = "SpicySideQuests"
local dir = "SpicySideQuests/"

---------------------------------------------------------------------------
-- Minimal WoW API stubs
---------------------------------------------------------------------------
local frames = {}
local function newObj(kind)
	local o = { kind = kind, scripts = {}, text = "", shown = true, checked = false,
		w = 300, h = 300, points = {} }
	local mt = {}
	mt.__index = function(t, k)
		local m = rawget(mt, "methods")[k]
		if m then return m end
		-- every other CamelCase widget method is a no-op; plain fields stay nil
		if k == "Left" or k == "Middle" or k == "Right" then return nil end -- template textures
		if type(k) == "string" and k:match("^%u") then return function() end end
	end
	mt.methods = {
		SetScript = function(self, n, fn) self.scripts[n] = fn end,
		GetScript = function(self, n) return self.scripts[n] end,
		HookScript = function(self, n, fn)
			local old = self.scripts[n]
			self.scripts[n] = function(...) if old then old(...) end fn(...) end
		end,
		SetText = function(self, t)
			self.text = t or ""
			if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, true) end
		end,
		GetText = function(self) return self.text end,
		SetShown = function(self, v) self.shown = v and true or false end,
		Show = function(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end,
		Hide = function(self) self.shown = false end,
		IsShown = function(self) return self.shown end,
		SetChecked = function(self, v) self.checked = v and true or false end,
		GetChecked = function(self) return self.checked end,
		GetHeight = function(self) return self.h end,
		GetSize = function(self) return self.w, self.h end,
		SetSize = function(self, w, h) self.w, self.h = w, h end,
		GetPoint = function() return "CENTER", nil, "CENTER", 10, 20 end,
		HasFocus = function() return false end,
		IsMouseOver = function() return false end,
		GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
		CreateFontString = function() return newObj("FontString") end,
		CreateTexture = function() return newObj("Texture") end,
		GetHighlightTexture = function(self) self.hl = self.hl or newObj("Texture"); return self.hl end,
		GetNormalTexture = function(self) self.nt = self.nt or newObj("Texture"); return self.nt end,
		GetPushedTexture = function(self) self.pt = self.pt or newObj("Texture"); return self.pt end,
		GetCheckedTexture = function(self) self.ct = self.ct or newObj("Texture"); return self.ct end,
		GetThumbTexture = function(self) self.th = self.th or newObj("Texture"); return self.th end,
		GetFontString = function(self) self.fs = self.fs or newObj("FontString"); return self.fs end,
		RegisterEvent = function(self, e) self.events = self.events or {}; self.events[e] = true end,
		ClearFocus = function() end,
		GetValue = function(self) return self.value or 0 end,
		SetValue = function(self, v)
			self.value = v
			if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end
		end,
	}
	local o2 = setmetatable(o, mt)
	frames[#frames + 1] = o2
	return o2
end

function CreateFrame(kind) return newObj(kind) end
function CreateFont() return newObj("Font") end
GameFontHighlight, GameFontNormal, ChatFontNormal = newObj("Font"), newObj("Font"), newObj("Font")
function GetLocale() return "enUS" end
GameTooltip = newObj("GameTooltip")
GameTooltip_Hide = function() end
UIParent = newObj("Frame")
UISpecialFrames = {}
tinsert = table.insert
SlashCmdList = {}
function IsShiftKeyDown() return false end
function GetRealZoneText() return "Durotar" end
local printed = {}
function print(...) printed[#printed + 1] = table.concat({ ... }, " ") end
local clock = 1000000
function time() return clock end

local MAPS = { [1411] = { name = "Durotar", mapType = 3 }, [1449] = { name = "Un'Goro Crater", mapType = 3 } }
C_Map = {
	GetBestMapForUnit = function() return 1411 end,
	GetMapInfo = function(id) return MAPS[id] end,
	GetPlayerMapPosition = function()
		return { GetXY = function() return 0.5214, 0.4137 end }
	end,
	CanSetUserWaypointOnMap = function() return true end,
	SetUserWaypoint = function(p) _G.lastWaypoint = p end,
}
UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m = m, x = x, y = y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
Enum = { UIMapType = { Zone = 3 } }

---------------------------------------------------------------------------
-- Load addon files in TOC order
---------------------------------------------------------------------------
local ns = {}
for line in io.lines(dir .. ADDON .. ".toc") do
	if line:match("%.lua$") then
		local chunk = assert(loadfile(dir .. line))
		chunk(ADDON, ns)
	end
end

local function fire(event, ...)
	for _, f in ipairs(frames) do
		if f.events and f.events[event] and f.scripts.OnEvent then
			f.scripts.OnEvent(f, event, ...)
		end
	end
end

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed = passed + 1 else failed = failed + 1; io.write("FAIL: ", name, "\n") end
end

---------------------------------------------------------------------------
-- Tests
---------------------------------------------------------------------------
-- Parsing
local t, tags, loc = ns.ParseInput("Kill boars #farming #Quest #123 @Durotar 52.1, 41.3")
check("parse text", t == "Kill boars #123")
check("parse tags", #tags == 2 and tags[1] == "farming" and tags[2] == "Quest")
check("parse loc", loc.zone == "Durotar" and loc.x == 52.1 and loc.y == 41.3)
t, tags, loc = ns.ParseInput("Find chest @here")
check("parse here", t == "Find chest" and loc.here)
t, tags, loc = ns.ParseInput("Go @Un'Goro Crater")
check("parse zone only", loc.zone == "Un'Goro Crater" and not loc.x)
t, tags, loc = ns.ParseInput("Coords @45 60")
check("parse coords only", loc.here and loc.x == 45 and loc.y == 60)

-- Load with no saved data and no inbox (standalone)
fire("ADDON_LOADED", ADDON)
check("db created", type(SpicySideQuestsDB) == "table" and SpicySideQuestsDB.categories[1] == "General")
fire("PLAYER_LOGIN")

-- Add via slash command
SlashCmdList.SPICYSIDEQUESTS("add Farm Arcanite #farming @here")
local db = SpicySideQuestsDB
local id = db.order[1]
local item = db.items[id]
check("slash add", item and item.text == "Farm Arcanite" and item.category == "General")
check("here resolved", item.zone == "Durotar" and item.mapID == 1411 and item.x == 52.1 and item.y == 41.4)
check("format roundtrip", ns.FormatInput(item) == "Farm Arcanite #farming @Durotar 52.1, 41.4")

-- Categories + add into a second category
local it2 = ns:AddItem("Run SM Cathedral #group", "dungeons")
local it3 = ns:AddItem("Visit Un'Goro @Un'Goro Crater 71, 72.5", "Dungeons")
check("category dedupe", it2.category == "dungeons" and it3.category == "dungeons" and #db.categories == 2)
check("zone resolved", it3.mapID == 1449)

-- Rows
local rows = ns:BuildRows("", true)
check("rows grouped", rows[1].header == "General" and rows[2].item == item and rows[3].header == "dungeons")
check("rows count", #rows == 5)
rows = ns:BuildRows("#farm", true)
check("tag filter", #rows == 2 and rows[2].item == item)
rows = ns:BuildRows("cathedral", true)
check("text filter", #rows == 2 and rows[2].item == it2)

-- Done / hide done / ordering
ns:SetDone(it2.id, true)
rows = ns:BuildRows("", false)
check("hide done", #rows == 4)
rows = ns:BuildRows("", true)
check("done sorted last", rows[4].item == it3 and rows[5].item == it2)

-- Collapse
db.settings.collapsed.dungeons = true
rows = ns:BuildRows("", true)
check("collapse", #rows == 3 and rows[3].header == "dungeons")
db.settings.collapsed.dungeons = nil

-- Edit
ns:EditItem(it3.id, "Visit Crater #explore", "General")
check("edit", it3.text == "Visit Crater" and it3.category == "General" and it3.zone == nil and it3.tags[1] == "explore")

-- Delete -> tombstone
ns:DeleteItem(item.id)
check("tombstone", item.deleted and #ns:BuildRows("#farming", true) == 0)

-- Waypoint
it3.zone, it3.mapID, it3.x, it3.y = "Un'Goro Crater", 1449, 71, 72.5
check("waypoint", ns:SetWaypoint(it3) and lastWaypoint.m == 1449 and lastWaypoint.x == 0.71)

-- Clear completed
check("clear completed", ns:ClearCompleted() == 1 and it2.deleted)

-- Inbox merge: new item, newer update wins, older ignored, same inbox not re-applied
clock = clock + 100
local inbox = {
	generated = clock,
	categories = { "Professions" },
	items = {
		{ id = "md0001", text = "From Obsidian", tags = { "obsidian" }, category = "Professions", done = false, created = clock, updated = clock, zone = "Durotar" },
		{ id = it3.id, text = "Newer text", category = "General", done = true, updated = clock + 1 },
		{ id = it2.id, text = "Stale", category = "dungeons", updated = 1 },
	},
}
check("merge count", ns:MergeInbox(inbox) == 2)
check("merge new", db.items.md0001 and db.items.md0001.mapID == 1411 and db.items.md0001.category == "Professions")
check("merge newer wins", db.items[it3.id].text == "Newer text" and db.items[it3.id].done)
check("merge older ignored", db.items[it2.id].text == "Run SM Cathedral")
check("merge once", ns:MergeInbox(inbox) == 0)

-- Tombstone purge
clock = clock + 31 * 86400
ns:PurgeTombstones()
check("purge", db.items[item.id] == nil and db.items[it2.id] == nil and db.items.md0001 ~= nil)

-- Reload with existing saved data keeps items + settings
db.settings.fontSize = 18
local ns2 = {}
for line in io.lines(dir .. ADDON .. ".toc") do
	if line:match("%.lua$") then assert(loadfile(dir .. line))(ADDON, ns2) end
end
ns2:InitDB(SpicySideQuestsDB)
check("reload keeps data", ns2.db.items.md0001 and ns2.db.settings.fontSize == 18)

-- UI paths run without errors
ns:Refresh()
ns:ToggleSettings()
ns:ToggleUI()
ns:ToggleUI()
SlashCmdList.SPICYSIDEQUESTS("reset")
SlashCmdList.SPICYSIDEQUESTS("help")
check("help printed", #printed > 0)

-- Themes switch both ways without errors
check("default theme", ns:Theme().name == "Classic")
db.settings.theme = "modern"
ns:ApplySettings()
ns:ApplyTheme()
check("modern theme", ns:IsModern() and ns:Theme().name == "Modern")
db.settings.theme = "classic"
ns:ApplySettings()
check("back to classic", not ns:IsModern())
db.settings.theme = "bogus"
check("unknown theme falls back", ns:Theme().name == "Classic")
check("slash commands", SLASH_SPICYSIDEQUESTS1 == "/spicy" and SLASH_SPICYSIDEQUESTS2 == "/ssq")

-- Security: escaping and a hostile/malformed inbox
check("escape pipes", ns.Escape("a|Hitem:1|h[x]|h|r") == "a||Hitem:1||h[x]||h||r")
clock = clock + 1000
local before = 0
for _ in pairs(db.items) do before = before + 1 end
local ok, merged = pcall(ns.MergeInbox, ns, {
	generated = clock,
	categories = { 42, { "x" }, "Good" },
	items = {
		{ id = "../evil", text = "bad id" },
		{ id = "ok0001", text = "fine", tags = { "a", 5, {}, "b" }, category = 7, zone = {}, x = "1e999", y = 0/0, mapID = -5, done = "yes" },
		{ id = "ok0002", text = string.rep("x", 5000), category = string.rep("c", 500) },
		"not a table",
		{ id = 123, text = "number id" },
	},
})
check("hostile inbox does not error", ok)
check("hostile inbox merged only valid items", merged == 2)
local o1, o2 = db.items.ok0001, db.items.ok0002
check("tags filtered to strings", o1 and #o1.tags == 2 and o1.tags[1] == "a" and o1.tags[2] == "b")
check("bad category falls back", o1 and o1.category == "General")
check("bad zone/coords dropped", o1 and o1.zone == nil and o1.x == nil and o1.y == nil and o1.mapID == nil)
check("done must be true", o1 and o1.done == false)
check("long text capped", o2 and #o2.text == 500 and #o2.category == 60)
check("bad id rejected", db.items["../evil"] == nil)


print = _G.print
io.write(string.format("%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
