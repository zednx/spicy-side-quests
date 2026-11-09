-- Settings window (/ssq config or the gear icon).
local _, ns = ...

local panel

local function S() return ns.db.settings end

local function pct(v)
	return string.format("%d%%", math.floor(v * 100 + 0.5))
end

local function makeSlider(parent, label, minV, maxV, step, fmt, get, set)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(220, 40)

	local text = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	text:SetPoint("TOPLEFT")

	local s = CreateFrame("Slider", nil, holder, "BackdropTemplate")
	s:SetOrientation("HORIZONTAL")
	s:SetSize(200, 16)
	s:SetPoint("TOPLEFT", 0, -16)
	ns.StyleSlider(s)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	s:EnableMouseWheel(true)

	local function render(v)
		text:SetText(label .. ": |cffffffff" .. fmt(v) .. "|r")
	end
	s:SetScript("OnValueChanged", function(_, v)
		v = math.floor(v / step + 0.5) * step
		render(v)
		set(v)
		ns:ApplySettings()
	end)
	s:SetScript("OnMouseWheel", function(self, delta)
		self:SetValue(self:GetValue() + delta * step)
	end)

	holder.Sync = function()
		local v = get()
		s:SetValue(v)
		render(v)
	end
	return holder
end

local function makeCheck(parent, label, get, set)
	local c = CreateFrame("CheckButton", nil, parent)
	c:SetSize(24, 24)
	ns.StyleCheck(c)
	local text = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("LEFT", c, "RIGHT", 2, 0)
	text:SetText(label)
	c:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		ns:ApplySettings()
	end)
	c.Sync = function() c:SetChecked(get()) end
	return c
end

local function create()
	panel = CreateFrame("Frame", "SpicySideQuestsSettings", UIParent, "BackdropTemplate")
	panel:SetSize(250, 394)
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("DIALOG")
	ns.StylePanel(panel, function() return 0.95 end)
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	panel:SetClampedToScreen(true)
	tinsert(UISpecialFrames, "SpicySideQuestsSettings") -- Esc closes it

	local icon = panel:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ns.CHILLI)
	icon:SetSize(18, 18)
	icon:SetPoint("TOPLEFT", 6, -3)
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("LEFT", icon, "RIGHT", 3, 0)
	title:SetText("Settings")
	ns.StyleTitle(title)

	local close = CreateFrame("Button", nil, panel)
	close:SetSize(14, 14)
	close:SetPoint("TOPRIGHT", -8, -8)
	close:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
	close:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	close:SetScript("OnClick", function() panel:Hide() end)

	local widgets = {}
	local function add(w, gap)
		local prev = widgets[#widgets]
		if prev then
			w:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -(gap or 6))
		else
			w:SetPoint("TOPLEFT", 14, -34)
		end
		widgets[#widgets + 1] = w
	end

	-- Theme: cycles Classic -> Modern
	local theme = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	theme:SetSize(200, 22)
	ns.StyleButton(theme)
	local function themeLabel()
		theme:SetText("Theme: " .. ns:Theme().name)
	end
	theme:SetScript("OnClick", function()
		local cur = S().theme
		for i, key in ipairs(ns.THEME_ORDER) do
			if key == cur then
				S().theme = ns.THEME_ORDER[i % #ns.THEME_ORDER + 1]
				break
			end
		end
		if not ns.THEMES[S().theme] then S().theme = "classic" end
		themeLabel()
		ns:ApplySettings()
		ns:ApplyTheme() -- settings panel too, even if the main window isn't built
	end)
	theme.Sync = themeLabel
	add(theme)

	add(makeSlider(panel, "Background opacity", 0, 1, 0.05, pct,
		function() return S().bgAlpha end,
		function(v) S().bgAlpha = v end))
	add(makeSlider(panel, "Window opacity", 0.2, 1, 0.05, pct,
		function() return S().alpha end,
		function(v) S().alpha = v end))
	add(makeSlider(panel, "Font size", 8, 24, 1, tostring,
		function() return S().fontSize end,
		function(v) S().fontSize = v end))

	add(makeCheck(panel, "Show completed",
		function() return S().showDone end,
		function(v) S().showDone = v end), 4)
	add(makeCheck(panel, "Wrap long side quests",
		function() return S().wrap ~= false end,
		function(v) S().wrap = v end), 0)
	add(makeCheck(panel, "Lock window",
		function() return S().locked end,
		function(v) S().locked = v end), 0)
	add(makeCheck(panel, "Hide in combat",
		function() return S().hideInCombat end,
		function(v) S().hideInCombat = v end), 0)

	local clear = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	clear:SetSize(140, 22)
	ns.StyleButton(clear)
	clear:SetText("Clear completed")
	clear:SetScript("OnClick", function()
		local n = ns:ClearCompleted()
		ns.Print("Removed " .. n .. " completed item(s).")
	end)
	add(clear, 10)

	local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	reset:SetSize(140, 22)
	ns.StyleButton(reset)
	reset:SetText("Reset window position")
	reset:SetScript("OnClick", function() ns:ResetPosition() end)
	add(reset, 4)

	local ver = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	ver:SetPoint("BOTTOMRIGHT", -10, 8)
	ver:SetText("v" .. ns.VERSION)

	panel:SetScript("OnShow", function()
		for _, w in ipairs(widgets) do
			if w.Sync then w.Sync() end
		end
	end)
	panel:Hide()
end

function ns:ToggleSettings()
	if not panel then create() end
	panel:SetShown(not panel:IsShown())
end
