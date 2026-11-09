-- Main todo window.
local _, ns = ...

local f, list
local rows = {}
local offset = 0
local filterText = ""
local editingId
local rowFont = CreateFont("SpicySideQuestsRowFont")
local headerFont = CreateFont("SpicySideQuestsHeaderFont")
rowFont:CopyFontObject(GameFontHighlight)
headerFont:CopyFontObject(GameFontNormal)

local TAG_COLOR = "|cff66bbff"
local DONE_COLOR = "|cff808080"
local LOC_COLOR = "|cffffd100"

local function S() return ns.db.settings end

local function escape(s)
	return (s:gsub("|", "||"))
end

---------------------------------------------------------------------------
-- Small widget helpers
---------------------------------------------------------------------------
local function addPlaceholder(box, text)
	local ph = box:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	ph:SetPoint("LEFT", 2, 0)
	ph:SetText(text)
	box.placeholder = ph
	local function update()
		ph:SetShown(box:GetText() == "" and not box:HasFocus())
	end
	box:HookScript("OnEditFocusGained", update)
	box:HookScript("OnEditFocusLost", update)
	box:HookScript("OnTextChanged", update)
	box.UpdatePlaceholder = update
	update()
end

local function makeEditBox(parent, placeholder)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetHeight(20)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	addPlaceholder(box, placeholder)
	return box
end

local function makeIconButton(parent, texture, size, tooltip)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	b:SetNormalTexture(texture)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	if tooltip then
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(tooltip)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
	end
	return b
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function showItemTooltip(row)
	local item = row.item
	if not item then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(escape(item.text), 1, 1, 1, true)
	GameTooltip:AddLine(item.category, 1, 0.82, 0)
	if item.tags and #item.tags > 0 then
		GameTooltip:AddLine("#" .. table.concat(item.tags, " #"), 0.4, 0.73, 1, true)
	end
	local loc = ns.FormatLocation(item)
	if loc then GameTooltip:AddLine(loc, 1, 0.82, 0) end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Click: complete  |  Right-click: edit", 0.6, 0.6, 0.6)
	if loc then GameTooltip:AddLine("Map icon: set waypoint", 0.6, 0.6, 0.6) end
	GameTooltip:Show()
end

local function rowLeave(row)
	if not row:IsMouseOver() then
		row.del:Hide()
		GameTooltip:Hide()
	end
end

local function createRow(i)
	local row = CreateFrame("Button", nil, list)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row:GetHighlightTexture():SetAlpha(0.35)

	row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.check:SetPoint("LEFT", 0, 0)
	row.check:SetScript("OnClick", function(self)
		if row.item then ns:SetDone(row.item.id, self:GetChecked()) end
	end)

	row.del = makeIconButton(row, "Interface\\Buttons\\UI-StopButton", 14)
	row.del:SetPoint("RIGHT", -2, 0)
	row.del:Hide()
	row.del:SetScript("OnClick", function()
		if row.item then ns:DeleteItem(row.item.id) end
	end)
	row.del:SetScript("OnLeave", function() rowLeave(row) end)

	row.loc = makeIconButton(row, "Interface\\Icons\\INV_Misc_Map_01", 14)
	row.loc:SetPoint("RIGHT", row.del, "LEFT", -2, 0)
	row.loc:SetScript("OnClick", function()
		if row.item then ns:SetWaypoint(row.item) end
	end)
	row.loc:SetScript("OnEnter", function() showItemTooltip(row) end)
	row.loc:SetScript("OnLeave", function() rowLeave(row) end)

	row.label = row:CreateFontString(nil, "ARTWORK")
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)

	row:SetScript("OnClick", function(self, button)
		if self.header then
			if button == "RightButton" then
				f.catBox:SetText(self.header)
				f.textBox:SetFocus()
			else
				local c = S().collapsed
				c[self.header] = not c[self.header] or nil
				ns:Refresh()
			end
		elseif self.item then
			if button == "RightButton" then
				ns:BeginEdit(self.item)
			else
				ns:SetDone(self.item.id, not self.item.done)
			end
		end
	end)
	row:SetScript("OnEnter", function(self)
		if self.item then
			self.del:Show()
			showItemTooltip(self)
		elseif self.header then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.header, 1, 0.82, 0)
			GameTooltip:AddLine("Click: collapse/expand  |  Right-click: add here", 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", rowLeave)

	rows[i] = row
	return row
end

local function layoutRow(row, data, rowH)
	row:SetHeight(rowH)
	row.item, row.header = data.item, data.header
	row.label:ClearAllPoints()

	if data.header then
		row.check:Hide()
		row.loc:Hide()
		row.del:Hide()
		row.label:SetFontObject(headerFont)
		row.label:SetPoint("LEFT", 2, 0)
		row.label:SetPoint("RIGHT", -2, 0)
		local collapsed = S().collapsed[data.header]
		row.label:SetText(string.format("%s %s  |cff999999%d/%d|r",
			collapsed and "+" or "-", escape(data.header), data.open, data.total))
		return
	end

	local item = data.item
	local box = rowH - 2
	row.check:SetSize(box, box)
	row.check:SetChecked(item.done)
	row.check:Show()
	local hasLoc = item.zone or item.x
	row.loc:SetShown(hasLoc and true or false)
	row.del:SetShown(row:IsMouseOver())

	row.label:SetFontObject(rowFont)
	row.label:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
	row.label:SetPoint("RIGHT", hasLoc and row.loc or row.del, "LEFT", -4, 0)

	local text = escape(item.text)
	local tags = ""
	if item.tags and #item.tags > 0 then
		tags = " " .. (item.done and "" or TAG_COLOR) .. "#" .. escape(table.concat(item.tags, " #")) .. (item.done and "" or "|r")
	end
	local zone = ""
	if item.zone and not item.done then
		zone = " " .. LOC_COLOR .. escape(item.zone) .. "|r"
	end
	if item.done then
		row.label:SetText(DONE_COLOR .. text .. tags .. "|r")
	else
		row.label:SetText(text .. tags .. zone)
	end
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
function ns:Refresh()
	if not f or not f:IsShown() then return end
	local s = S()
	local data = self:BuildRows(filterText, s.showDone)
	local rowH = s.fontSize + 8
	local visible = math.max(1, math.floor((list:GetHeight() or 0) / rowH))
	offset = math.max(0, math.min(offset, #data - visible))

	for i = 1, visible do
		local d = data[i + offset]
		local row = rows[i] or createRow(i)
		if d then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * rowH)
			row:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -(i - 1) * rowH)
			layoutRow(row, d, rowH)
			row:Show()
		else
			row:Hide()
		end
	end
	for i = visible + 1, #rows do rows[i]:Hide() end

	local open = 0
	for _, item in pairs(self.db.items) do
		if not item.deleted and not item.done then open = open + 1 end
	end
	f.title:SetText("|cffff7a3dSide Quests|r |cff999999(" .. open .. ")|r")

	if #data > visible then
		f.scrollInfo:SetText(string.format("%d-%d / %d", offset + 1, math.min(offset + visible, #data), #data))
		f.scrollInfo:Show()
	else
		f.scrollInfo:Hide()
	end
	f.empty:SetShown(#data == 0)
end

---------------------------------------------------------------------------
-- Editing
---------------------------------------------------------------------------
local function endEdit()
	editingId = nil
	f.textBox.placeholder:SetText("New side quest... #tag @here")
	f.textBox:SetText("")
	f.textBox:UpdatePlaceholder()
end

function ns:BeginEdit(item)
	editingId = item.id
	f.catBox:SetText(item.category)
	f.textBox:SetText(ns.FormatInput(item))
	f.textBox.placeholder:SetText("Editing...")
	f.textBox:SetFocus()
	f.textBox:SetCursorPosition(#f.textBox:GetText())
end

local function submit()
	local text = ns.trim(f.textBox:GetText())
	if text == "" then
		if editingId then endEdit() end
		f.textBox:ClearFocus()
		return
	end
	local cat = ns:EnsureCategory(f.catBox:GetText())
	f.catBox:SetText(cat)
	S().lastCategory = cat
	if editingId then
		ns:EditItem(editingId, text, cat)
		endEdit()
		f.textBox:ClearFocus()
	else
		ns:AddItem(text, cat)
		f.textBox:SetText("")
	end
end

-- Tab in the category box cycles through matching existing categories.
local function completeCategory(box)
	local typed = box.typed or box:GetText()
	box.typed = typed
	local matchesList = {}
	for _, c in ipairs(ns.db.categories) do
		if c:lower():find(typed:lower(), 1, true) == 1 then
			matchesList[#matchesList + 1] = c
		end
	end
	if #matchesList == 0 then return end
	box.tabIndex = (box.tabIndex or 0) % #matchesList + 1
	box.completing = true
	box:SetText(matchesList[box.tabIndex])
	box.completing = false
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function savePosition()
	local p, _, rp, x, y = f:GetPoint()
	S().point = { p, rp, x, y }
	S().width, S().height = f:GetSize()
end

function ns:ResetPosition()
	local s = S()
	s.point, s.width, s.height = nil, ns.DEFAULT_SETTINGS.width, ns.DEFAULT_SETTINGS.height
	if f then
		f:ClearAllPoints()
		f:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
		f:SetSize(s.width, s.height)
		s.shown = true
		f:Show()
	end
end

function ns:ApplySettings()
	if not f then return end
	local s = S()
	f:SetBackdropColor(0.05, 0.05, 0.05, s.bgAlpha)
	f:SetBackdropBorderColor(0.4, 0.4, 0.4, math.max(s.bgAlpha, 0.15))
	f:SetAlpha(s.alpha)

	local path, _, flags = GameFontHighlight:GetFont()
	rowFont:SetFont(path, s.fontSize, flags or "")
	local hpath, _, hflags = GameFontNormal:GetFont()
	headerFont:SetFont(hpath, s.fontSize + 1, hflags or "")

	f.grip:SetShown(not s.locked)
	self:Refresh()
end

function ns:ToggleUI(show)
	if not f then return end
	if show == nil then show = not f:IsShown() end
	S().shown = show
	f:SetShown(show)
end

function ns:CreateUI()
	local s = S()
	f = CreateFrame("Frame", "SpicySideQuestsFrame", UIParent, "BackdropTemplate")
	f:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	f:SetSize(s.width, s.height)
	if s.point then
		f:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
	end
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	if f.SetResizeBounds then
		f:SetResizeBounds(200, 150, 900, 1200)
	elseif f.SetMinResize then
		f:SetMinResize(200, 150)
	end
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self)
		if not S().locked then self:StartMoving() end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePosition()
	end)
	f:SetScript("OnSizeChanged", function() ns:Refresh() end)
	f:SetScript("OnShow", function() ns:Refresh() end)

	-- Title bar
	f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	f.title:SetPoint("TOPLEFT", 10, -8)

	local close = makeIconButton(f, "Interface\\Buttons\\UI-StopButton", 14, "Hide (/ssq)")
	close:SetPoint("TOPRIGHT", -8, -7)
	close:SetScript("OnClick", function() ns:ToggleUI(false) end)

	local gear = makeIconButton(f, "Interface\\Icons\\INV_Misc_Gear_01", 14, "Settings")
	gear:SetPoint("RIGHT", close, "LEFT", -4, 0)
	gear:SetScript("OnClick", function() ns:ToggleSettings() end)

	-- Filter
	f.filterBox = makeEditBox(f, "Filter... (text or #tag)")
	f.filterBox:SetPoint("TOPLEFT", 12, -26)
	f.filterBox:SetPoint("TOPRIGHT", -8, -26)
	f.filterBox:HookScript("OnTextChanged", function(self)
		filterText = self:GetText()
		offset = 0
		ns:Refresh()
	end)
	f.filterBox:SetScript("OnEnterPressed", f.filterBox.ClearFocus)

	-- Add row (bottom)
	f.catBox = makeEditBox(f, "Category")
	f.catBox:SetWidth(80)
	f.catBox:SetPoint("BOTTOMLEFT", 12, 10)
	f.catBox:SetText(s.lastCategory or ns.DEFAULT_CATEGORY)
	f.catBox:SetScript("OnTabPressed", completeCategory)
	f.catBox:HookScript("OnTextChanged", function(self)
		if not self.completing then self.typed, self.tabIndex = nil, nil end
	end)
	f.catBox:SetScript("OnEnterPressed", function() f.textBox:SetFocus() end)

	f.grip = CreateFrame("Button", nil, f)
	f.grip:SetSize(14, 14)
	f.grip:SetPoint("BOTTOMRIGHT", -2, 2)
	f.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	f.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	f.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	f.grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
	f.grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		savePosition()
	end)

	local here = makeIconButton(f, "Interface\\Icons\\INV_Misc_Map_01", 18, "Attach current location (@here)")
	here:SetPoint("BOTTOMRIGHT", -16, 11)
	here:SetScript("OnClick", function()
		local t = f.textBox:GetText():gsub("%s*@.*$", "")
		f.textBox:SetText(t .. " @here")
		f.textBox:SetFocus()
	end)

	f.textBox = makeEditBox(f, "New side quest... #tag @here")
	f.textBox:SetPoint("LEFT", f.catBox, "RIGHT", 8, 0)
	f.textBox:SetPoint("RIGHT", here, "LEFT", -6, 0)
	f.textBox:SetScript("OnEnterPressed", submit)
	f.textBox:SetScript("OnEscapePressed", function(self)
		if editingId then endEdit() end
		self:ClearFocus()
	end)

	-- List
	list = CreateFrame("Frame", nil, f)
	list:SetPoint("TOPLEFT", f.filterBox, "BOTTOMLEFT", -6, -4)
	list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 36)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * (IsShiftKeyDown() and 5 or 1)
		if offset < 0 then offset = 0 end
		ns:Refresh()
	end)
	list:SetScript("OnSizeChanged", function() ns:Refresh() end)

	f.scrollInfo = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	f.scrollInfo:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -2, -12)

	f.empty = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	f.empty:SetPoint("CENTER")
	f.empty:SetText("No side quests yet.\nType below or use /ssq add")

	-- Hide in combat (optional)
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:SetScript("OnEvent", function(self, event)
		if not S().hideInCombat then return end
		if event == "PLAYER_REGEN_DISABLED" then
			self:Hide()
		elseif S().shown then
			self:Show()
		end
	end)

	f:SetShown(s.shown)
	self:ApplySettings()
end
