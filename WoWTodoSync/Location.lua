-- Player location, zone name -> mapID lookup and waypoints.
local _, ns = ...

local function round1(v)
	return math.floor(v * 1000 + 0.5) / 10 -- 0..1 -> 0..100 with one decimal
end

-- Returns zone, mapID, x, y (x/y in 0..100). x/y are nil inside instances.
function ns.GetPlayerLocation()
	local ok, zone, mapID, x, y = pcall(function()
		local id = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
		if not id then
			return GetRealZoneText and GetRealZoneText() or nil
		end
		local info = C_Map.GetMapInfo(id)
		local name = info and info.name or (GetRealZoneText and GetRealZoneText())
		local pos = C_Map.GetPlayerMapPosition(id, "player")
		local px, py
		if pos then px, py = pos:GetXY() end
		if px and py and (px > 0 or py > 0) then
			return name, id, round1(px), round1(py)
		end
		return name, id
	end)
	if not ok then
		return GetRealZoneText and GetRealZoneText() or nil
	end
	if zone == "" then zone = nil end
	return zone, mapID, x, y
end

-- Lazily built lookup of lowercase zone name -> uiMapID.
local zoneLookup
local MAX_MAP_ID = 3000

local function buildLookup()
	zoneLookup = {}
	if not (C_Map and C_Map.GetMapInfo) then return end
	local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
	local priority = {}
	for id = 1, MAX_MAP_ID do
		local info = C_Map.GetMapInfo(id)
		if info and info.name and info.name ~= "" then
			local key = info.name:lower()
			-- Prefer real zones over dungeons/micro maps with the same name.
			local p = (info.mapType == zoneType) and 2 or 1
			if not zoneLookup[key] or p > priority[key] then
				zoneLookup[key] = id
				priority[key] = p
			end
		end
	end
end

function ns.ResolveMapID(zone)
	if not zone or zone == "" then return nil end
	if not zoneLookup then
		local ok = pcall(buildLookup)
		if not ok then zoneLookup = zoneLookup or {} end
	end
	return zoneLookup[zone:lower()]
end

function ns.FormatLocation(item)
	if item.x and item.y then
		return string.format("%s%.1f, %.1f", item.zone and (item.zone .. " ") or "", item.x, item.y)
	end
	return item.zone
end

-- Sets a waypoint for the item. Uses TomTom when installed, otherwise the
-- built-in user waypoint. Falls back to printing the location.
function ns:SetWaypoint(item)
	local mapID = item.mapID or ns.ResolveMapID(item.zone)
	if mapID and not item.mapID then item.mapID = mapID end
	local where = ns.FormatLocation(item) or "?"

	if not (mapID and item.x and item.y) then
		ns.Print("Location: " .. where .. (mapID and "" or " (no coordinates)"))
		return false
	end

	local x, y = item.x / 100, item.y / 100

	if TomTom and TomTom.AddWaypoint then
		local ok = pcall(TomTom.AddWaypoint, TomTom, mapID, x, y, {
			title = item.text, persistent = false, minimap = true, world = true,
		})
		if ok then
			ns.Print("TomTom waypoint: " .. where)
			return true
		end
	end

	local ok = pcall(function()
		assert(C_Map.SetUserWaypoint and UiMapPoint)
		if C_Map.CanSetUserWaypointOnMap then
			assert(C_Map.CanSetUserWaypointOnMap(mapID))
		end
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
	end)
	if ok then
		ns.Print("Map pin set: " .. where)
		return true
	end

	ns.Print("Location: " .. where .. " (waypoints unavailable here)")
	return false
end
