-- Spicy Side Quests: data model, persistence and slash commands.
-- Works fully standalone; the companion app only feeds Inbox.lua.
local ADDON, ns = ...
ns.VERSION = "0.1.0"
ns.DEFAULT_CATEGORY = "General"
ns.TOMBSTONE_DAYS = 30

ns.DEFAULT_SETTINGS = {
	bgAlpha = 0.75,      -- background opacity
	alpha = 1.0,         -- whole window opacity
	fontSize = 13,
	locked = false,
	showDone = true,
	hideInCombat = false,
	shown = true,
	width = 320,
	height = 400,
	point = nil,         -- { point, relPoint, x, y }
	lastCategory = "General",
	collapsed = {},      -- [category] = true
}

local function copyDefaults(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then
			if type(v) == "table" then
				dst[k] = {}
				copyDefaults(dst[k], v)
			else
				dst[k] = v
			end
		end
	end
end

local function now()
	return time()
end

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
ns.trim = trim

function ns.Print(msg)
	print("|cffff7a3dSpicy Side Quests:|r " .. tostring(msg))
end

---------------------------------------------------------------------------
-- IDs
---------------------------------------------------------------------------
local ID_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"

function ns:NewID()
	local id
	repeat
		local t = {}
		for i = 1, 6 do
			local n = math.random(1, #ID_CHARS)
			t[i] = ID_CHARS:sub(n, n)
		end
		id = table.concat(t)
	until not self.db.items[id]
	return id
end

---------------------------------------------------------------------------
-- Text parsing: "Kill boars #farming #quest @Durotar 52.1, 41.3"
---------------------------------------------------------------------------
-- Returns text, tags, loc where loc = { here = true } | { zone, x, y } | nil
function ns.ParseInput(input)
	local tags, seen = {}, {}
	local text = input:gsub("#([%w_/%-]+)", function(tag)
		if tag:find("%a") then -- Obsidian tags need a non-digit
			local lower = tag:lower()
			if not seen[lower] then
				seen[lower] = true
				tags[#tags + 1] = tag
			end
			return ""
		end
	end)

	local loc
	local at = text:find("@", 1, true)
	if at then
		local spec = trim(text:sub(at + 1))
		text = text:sub(1, at - 1)
		if spec:lower() == "here" then
			loc = { here = true }
		elseif spec ~= "" then
			local zone, x, y = spec:match("^(.-)%s*(%d+%.?%d*)%s*[,%s]%s*(%d+%.?%d*)$")
			if x then
				loc = { zone = trim(zone) ~= "" and trim(zone) or nil, x = tonumber(x), y = tonumber(y) }
				if not loc.zone then loc.here = true end -- coords in current zone
			else
				loc = { zone = spec }
			end
		end
	end

	text = trim(text:gsub("%s+", " "))
	return text, tags, loc
end

-- Inverse of ParseInput, used to prefill the edit box.
function ns.FormatInput(item)
	local parts = { item.text }
	for _, tag in ipairs(item.tags or {}) do
		parts[#parts + 1] = "#" .. tag
	end
	if item.zone or item.x then
		local loc = "@" .. (item.zone or "")
		if item.x and item.y then
			loc = loc .. (item.zone and " " or "") .. string.format("%.1f, %.1f", item.x, item.y)
		end
		parts[#parts + 1] = loc
	end
	return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
function ns:EnsureCategory(name)
	name = (name and trim(name) ~= "") and trim(name) or self.DEFAULT_CATEGORY
	for _, c in ipairs(self.db.categories) do
		if c:lower() == name:lower() then
			return c
		end
	end
	table.insert(self.db.categories, name)
	return name
end

-- Applies a parsed location to an item (resolving "@here").
function ns:ApplyLocation(item, loc)
	if not loc then return end
	if loc.here then
		local zone, mapID, x, y = self.GetPlayerLocation()
		item.zone = zone
		item.mapID = mapID
		item.x, item.y = loc.x or x, loc.y or y
	else
		item.zone = loc.zone
		item.mapID = self.ResolveMapID and self.ResolveMapID(loc.zone) or nil
		item.x, item.y = loc.x, loc.y
	end
end

function ns:AddItem(input, category)
	local text, tags, loc = self.ParseInput(input)
	if text == "" then return nil end
	local t = now()
	local item = {
		id = self:NewID(),
		text = text,
		tags = tags,
		category = self:EnsureCategory(category),
		done = false,
		created = t,
		updated = t,
	}
	self:ApplyLocation(item, loc)
	self.db.items[item.id] = item
	table.insert(self.db.order, item.id)
	self:Changed()
	return item
end

function ns:EditItem(id, input, category)
	local item = self.db.items[id]
	if not item then return end
	local text, tags, loc = self.ParseInput(input)
	if text == "" then return end
	item.text, item.tags = text, tags
	item.category = self:EnsureCategory(category)
	item.zone, item.mapID, item.x, item.y = nil, nil, nil, nil
	self:ApplyLocation(item, loc)
	item.updated = now()
	self:Changed()
	return item
end

function ns:SetDone(id, done)
	local item = self.db.items[id]
	if not item then return end
	item.done = done and true or false
	item.updated = now()
	self:Changed()
end

-- Deleted items are kept as tombstones so the companion app can sync the delete.
function ns:DeleteItem(id)
	local item = self.db.items[id]
	if not item then return end
	item.deleted = true
	item.updated = now()
	self:Changed()
end

function ns:ClearCompleted()
	local n = 0
	for _, item in pairs(self.db.items) do
		if item.done and not item.deleted then
			item.deleted = true
			item.updated = now()
			n = n + 1
		end
	end
	self:Changed()
	return n
end

function ns:PurgeTombstones()
	local cutoff = now() - self.TOMBSTONE_DAYS * 86400
	local keep = {}
	for _, id in ipairs(self.db.order) do
		local item = self.db.items[id]
		if item and item.deleted and (item.updated or 0) < cutoff then
			self.db.items[id] = nil
		elseif item then
			keep[#keep + 1] = id
		end
	end
	self.db.order = keep
end

---------------------------------------------------------------------------
-- Filtering / view model
---------------------------------------------------------------------------
local function matches(item, terms)
	for _, term in ipairs(terms) do
		if term:sub(1, 1) == "#" then
			local want, found = term:sub(2), false
			for _, tag in ipairs(item.tags or {}) do
				if tag:lower():find(want, 1, true) == 1 then found = true break end
			end
			if not found then return false end
		else
			local hay = (item.text .. " " .. item.category .. " " .. (item.zone or "")):lower()
			if not hay:find(term, 1, true) then return false end
		end
	end
	return true
end

-- Returns a flat list of rows: { header = category, count, total } and { item = item }.
function ns:BuildRows(filter, showDone)
	local terms = {}
	for term in (filter or ""):lower():gmatch("%S+") do
		terms[#terms + 1] = term
	end

	local byCat = {}
	for _, id in ipairs(self.db.order) do
		local item = self.db.items[id]
		if item and not item.deleted and matches(item, terms) then
			local list = byCat[item.category]
			if not list then
				list = { open = 0, total = 0 }
				byCat[item.category] = list
			end
			list.total = list.total + 1
			if not item.done then list.open = list.open + 1 end
			if showDone or not item.done then
				list[#list + 1] = item
			end
		end
	end

	local rows = {}
	for _, cat in ipairs(self.db.categories) do
		local list = byCat[cat]
		if list then
			rows[#rows + 1] = { header = cat, open = list.open, total = list.total }
			if not self.db.settings.collapsed[cat] then
				-- open items first, completed at the bottom
				for _, item in ipairs(list) do
					if not item.done then rows[#rows + 1] = { item = item } end
				end
				for _, item in ipairs(list) do
					if item.done then rows[#rows + 1] = { item = item } end
				end
			end
		end
	end
	return rows
end

---------------------------------------------------------------------------
-- Inbox merge (companion app → game). Last write wins per item.
---------------------------------------------------------------------------
function ns:MergeInbox(inbox)
	if type(inbox) ~= "table" or type(inbox.items) ~= "table" then return 0 end
	local generated = tonumber(inbox.generated) or 0
	if generated <= (self.db.lastInbox or 0) then return 0 end

	for _, cat in ipairs(inbox.categories or {}) do
		self:EnsureCategory(cat)
	end

	local n = 0
	for _, src in ipairs(inbox.items) do
		if type(src) == "table" and type(src.id) == "string" and type(src.text) == "string" then
			local cur = self.db.items[src.id]
			if not cur or (tonumber(src.updated) or 0) > (cur.updated or 0) then
				local item = {
					id = src.id,
					text = src.text,
					tags = type(src.tags) == "table" and src.tags or {},
					category = self:EnsureCategory(src.category),
					done = src.done and true or false,
					deleted = src.deleted and true or nil,
					zone = src.zone,
					mapID = tonumber(src.mapID),
					x = tonumber(src.x),
					y = tonumber(src.y),
					created = tonumber(src.created) or (cur and cur.created) or now(),
					updated = tonumber(src.updated) or now(),
				}
				if item.zone and not item.mapID and self.ResolveMapID then
					item.mapID = self.ResolveMapID(item.zone)
				end
				if not cur then table.insert(self.db.order, item.id) end
				self.db.items[item.id] = item
				n = n + 1
			end
		end
	end
	self.db.lastInbox = generated
	return n
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
function ns:InitDB(saved)
	local db = type(saved) == "table" and saved or {}
	db.version = db.version or 1
	db.items = db.items or {}
	db.order = db.order or {}
	db.categories = db.categories or {}
	db.settings = db.settings or {}
	copyDefaults(db.settings, self.DEFAULT_SETTINGS)
	self.db = db
	self:EnsureCategory(self.DEFAULT_CATEGORY)
	return db
end

-- UI hooks this to redraw.
function ns:Changed()
	if self.Refresh then self:Refresh() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		SpicySideQuestsDB = ns:InitDB(SpicySideQuestsDB)
		ns:PurgeTombstones()
	elseif event == "PLAYER_LOGIN" then
		-- Map data is ready by now, so zone names can be resolved.
		local merged = ns:MergeInbox(SpicySideQuests_Inbox)
		if merged > 0 then ns.Print(merged .. " item(s) synced from markdown.") end
		if ns.CreateUI then ns:CreateUI() end
	end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP = {
	"/spicy or /ssq - show/hide the window",
	"/ssq add <text> [#tag] [@here | @Zone x, y] - add a side quest to your last category",
	"/ssq config - settings",
	"/ssq reset - reset window position",
}

SLASH_SPICYSIDEQUESTS1 = "/spicy"
SLASH_SPICYSIDEQUESTS2 = "/ssq"
SlashCmdList.SPICYSIDEQUESTS = function(msg)
	msg = trim(msg or "")
	local cmd, rest = msg:match("^(%S+)%s*(.*)$")
	cmd = cmd and cmd:lower() or ""
	if cmd == "" then
		ns:ToggleUI()
	elseif cmd == "add" then
		local item = ns:AddItem(rest, ns.db.settings.lastCategory)
		if item then
			ns.Print("New side quest in " .. item.category .. ": " .. item.text)
		end
	elseif cmd == "config" or cmd == "settings" or cmd == "options" then
		ns:ToggleSettings()
	elseif cmd == "reset" then
		ns:ResetPosition()
	else
		for _, line in ipairs(HELP) do ns.Print(line) end
	end
end

function SpicySideQuests_OnCompartmentClick()
	ns:ToggleUI()
end
