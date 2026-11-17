-- Zone reminders: when you enter a zone (or subzone, like a town) that has open
-- side quests, list them in chat and play a warning sound.
local _, ns = ...

ns.REMINDER_COOLDOWN = 300 -- seconds before the same side quest is announced again
local MAX_LINES = 8

local lastAnnounced = {} -- [id] = GetTime() of the last reminder

local function clock()
	return GetTime and GetTime() or time()
end

-- Names (lowercase) and map ID of where the player is now.
local function currentPlace()
	local names = {}
	local zone = GetRealZoneText and GetRealZoneText()
	local sub = GetSubZoneText and GetSubZoneText()
	if zone and zone ~= "" then names[zone:lower()] = zone end
	if sub and sub ~= "" then names[sub:lower()] = sub end
	local ok, mapID = pcall(function()
		return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	end)
	return names, ok and mapID or nil, zone
end

-- Open side quests for this place that haven't been announced recently.
function ns:DueReminders()
	local names, mapID = currentPlace()
	local t, due = clock(), {}
	for _, id in ipairs(self.db.order) do
		local item = self.db.items[id]
		if item and not item.done and not item.deleted and item.zone then
			local here = names[item.zone:lower()] or (mapID and item.mapID == mapID)
			local recent = lastAnnounced[id] and t - lastAnnounced[id] < self.REMINDER_COOLDOWN
			if here and not recent then due[#due + 1] = item end
		end
	end
	return due
end

function ns:CheckZoneReminders()
	local s = self.db and self.db.settings
	if not s or not s.zoneReminders then return end
	local due = self:DueReminders()
	if #due == 0 then return end

	local t = clock()
	for _, item in ipairs(due) do lastAnnounced[item.id] = t end

	-- Name the place: the side quests' own zone if they all share one, else the current zone.
	local _, _, zone = currentPlace()
	local where = due[1].zone
	for _, item in ipairs(due) do
		if item.zone:lower() ~= where:lower() then where = zone or where break end
	end
	self.Print(#due == 1 and ("Side quest in " .. self.Escape(where) .. ":")
		or (#due .. " side quests in " .. self.Escape(where) .. ":"))
	for i = 1, math.min(#due, MAX_LINES) do
		local item = due[i]
		local line = "  - " .. self.Escape(item.text)
		if item.x and item.y then line = line .. string.format(" |cffffd100(%.1f, %.1f)|r", item.x, item.y) end
		print(line)
	end
	if #due > MAX_LINES then print("  ...and " .. (#due - MAX_LINES) .. " more (/ssq)") end

	if s.reminderSound and PlaySound then
		pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("ZONE_CHANGED")
events:RegisterEvent("ZONE_CHANGED_INDOORS")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" and C_Timer and C_Timer.After then
		-- after a loading screen, wait until the zone name and chat are ready
		C_Timer.After(3, function() ns:CheckZoneReminders() end)
	else
		ns:CheckZoneReminders()
	end
end)
