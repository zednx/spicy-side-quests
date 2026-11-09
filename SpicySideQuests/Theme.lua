-- Themes: "classic" (Blizzard look) and "modern" (flat, fits minimal UIs like Daylight / ElvUI).
-- Every widget is registered once and restyled live when the theme changes.
local ADDON, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
ns.CHILLI = ns.MEDIA .. "Chilli"

-- Arial Narrow ships with every client but only covers Latin scripts.
local LATIN = { enUS = true, enGB = true, deDE = true, frFR = true, esES = true, esMX = true, itIT = true, ptBR = true }
local MODERN_FONT = LATIN[GetLocale and GetLocale() or "enUS"] and "Fonts\\ARIALN.TTF" or nil

ns.THEMES = {
	classic = {
		name = "Classic",
		backdrop = {
			bgFile = WHITE,
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		},
		bg = { 0.05, 0.05, 0.05 },
		border = { 0.4, 0.4, 0.4 },
		title = { 1, 0.82, 0 },
		header = { 1, 0.82, 0 },
		accent = { 1, 0.48, 0.24 },
		titleBar = nil,
		font = nil, -- use the game's fonts
		titleSize = 14,
	},
	modern = {
		name = "Modern",
		backdrop = {
			bgFile = WHITE,
			edgeFile = WHITE,
			edgeSize = 1,
			insets = { left = 1, right = 1, top = 1, bottom = 1 },
		},
		bg = { 0.07, 0.07, 0.08 },
		border = { 0, 0, 0 },
		title = { 0.95, 0.95, 0.95 },
		header = { 1, 0.45, 0.22 },
		accent = { 1, 0.45, 0.22 },
		titleBar = { 0.12, 0.12, 0.13 },
		font = MODERN_FONT,
		titleSize = 13,
	},
}
ns.THEME_ORDER = { "classic", "modern" }

function ns:Theme()
	local s = self.db and self.db.settings
	return self.THEMES[s and s.theme or "classic"] or self.THEMES.classic
end

function ns:IsModern()
	return self:Theme() == self.THEMES.modern
end

-- Returns path, flags for a font in the current theme, falling back to `fallback` (a Font object).
function ns:ThemeFont(fallback)
	local path, _, flags = fallback:GetFont()
	return self:Theme().font or path, flags or ""
end

---------------------------------------------------------------------------
-- Registry
---------------------------------------------------------------------------
local styled = {}

local function register(obj, fn)
	if not obj.__ssqStyle then
		obj.__ssqStyle = fn
		styled[#styled + 1] = obj
	end
	fn(obj, ns:Theme(), ns:IsModern())
end

function ns:ApplyTheme()
	local t, modern = self:Theme(), self:IsModern()
	for _, obj in ipairs(styled) do
		obj.__ssqStyle(obj, t, modern)
	end
end

-- 1px border made of four textures (draws on the owner, under its text).
local function addBorder(owner, layer)
	local b = {}
	for i = 1, 4 do
		b[i] = owner:CreateTexture(nil, layer or "BACKGROUND", nil, 1)
		b[i]:SetColorTexture(0, 0, 0, 1)
	end
	b[1]:SetPoint("TOPLEFT", owner.flatBg, "TOPLEFT", -1, 1)
	b[1]:SetPoint("TOPRIGHT", owner.flatBg, "TOPRIGHT", 1, 1)
	b[1]:SetHeight(1)
	b[2]:SetPoint("BOTTOMLEFT", owner.flatBg, "BOTTOMLEFT", -1, -1)
	b[2]:SetPoint("BOTTOMRIGHT", owner.flatBg, "BOTTOMRIGHT", 1, -1)
	b[2]:SetHeight(1)
	b[3]:SetPoint("TOPLEFT", owner.flatBg, "TOPLEFT", -1, 1)
	b[3]:SetPoint("BOTTOMLEFT", owner.flatBg, "BOTTOMLEFT", -1, -1)
	b[3]:SetWidth(1)
	b[4]:SetPoint("TOPRIGHT", owner.flatBg, "TOPRIGHT", 1, 1)
	b[4]:SetPoint("BOTTOMRIGHT", owner.flatBg, "BOTTOMRIGHT", 1, -1)
	b[4]:SetWidth(1)
	owner.flatBorder = b
end

local function setFlat(owner, shown)
	if owner.flatBg then owner.flatBg:SetShown(shown) end
	for _, tex in ipairs(owner.flatBorder or {}) do tex:SetShown(shown) end
end

local function setShown(region, shown)
	if region then region:SetShown(shown) end
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
-- Panels (main window, settings). getAlpha returns the background alpha.
function ns.StylePanel(frame, getAlpha)
	register(frame, function(fr, t)
		local a = getAlpha()
		fr:SetBackdrop(t.backdrop)
		fr:SetBackdropColor(t.bg[1], t.bg[2], t.bg[3], a)
		fr:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], math.max(a, t.titleBar and 0.6 or 0.15))
		if not fr.titleBg then
			fr.titleBg = fr:CreateTexture(nil, "BORDER")
			fr.titleBg:SetPoint("TOPLEFT", 1, -1)
			fr.titleBg:SetPoint("TOPRIGHT", -1, -1)
			fr.titleBg:SetHeight(22)
		end
		if t.titleBar then
			fr.titleBg:SetColorTexture(t.titleBar[1], t.titleBar[2], t.titleBar[3], math.max(a, 0.3))
			fr.titleBg:Show()
		else
			fr.titleBg:Hide()
		end
	end)
end

function ns.StyleTitle(fs, size)
	register(fs, function(obj, t)
		local path, flags = ns:ThemeFont(GameFontNormal)
		obj:SetFont(path, size or t.titleSize, flags)
		obj:SetTextColor(t.title[1], t.title[2], t.title[3])
	end)
end

function ns.StyleEditBox(box)
	register(box, function(b, _, modern)
		if not b.flatBg then
			b.flatBg = b:CreateTexture(nil, "BACKGROUND")
			b.flatBg:SetPoint("TOPLEFT", -5, -1)
			b.flatBg:SetPoint("BOTTOMRIGHT", 0, 1)
			b.flatBg:SetColorTexture(0, 0, 0, 0.45)
			addBorder(b)
		end
		setShown(b.Left, not modern)
		setShown(b.Middle, not modern)
		setShown(b.Right, not modern)
		setFlat(b, modern)
	end)
end

function ns.StyleCheck(cb)
	register(cb, function(c, t, modern)
		local function inset(tex, n)
			tex:ClearAllPoints()
			tex:SetPoint("TOPLEFT", n, -n)
			tex:SetPoint("BOTTOMRIGHT", -n, n)
		end
		if not c.flatBg then
			-- black square behind the box = 1px border in the modern theme
			c.flatBg = c:CreateTexture(nil, "BACKGROUND", nil, -1)
			c.flatBg:SetColorTexture(0, 0, 0, 1)
			inset(c.flatBg, 3)
		end
		if modern then
			c:SetNormalTexture(WHITE)
			c:GetNormalTexture():SetVertexColor(0.16, 0.16, 0.17, 1)
			inset(c:GetNormalTexture(), 4)
			c:SetPushedTexture(WHITE)
			c:GetPushedTexture():SetVertexColor(0.25, 0.25, 0.27, 1)
			inset(c:GetPushedTexture(), 4)
			c:SetHighlightTexture(WHITE, "ADD")
			c:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
			inset(c:GetHighlightTexture(), 4)
			c:SetCheckedTexture(WHITE)
			c:GetCheckedTexture():SetVertexColor(t.accent[1], t.accent[2], t.accent[3], 1)
			inset(c:GetCheckedTexture(), 6)
			c.flatBg:Show()
		else
			c.flatBg:Hide()
			for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture" }) do
				local tex = c[get](c)
				if tex then
					tex:ClearAllPoints()
					tex:SetAllPoints()
					tex:SetVertexColor(1, 1, 1, 1)
				end
			end
			c:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
			c:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
			c:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
			c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
		end
	end)
end

-- UIPanelButtonTemplate buttons
function ns.StyleButton(btn)
	register(btn, function(b, t, modern)
		if not b.flatBg then
			b.flatBg = b:CreateTexture(nil, "BACKGROUND")
			b.flatBg:SetAllPoints()
			b.flatBg:SetColorTexture(0.14, 0.14, 0.15, 1)
			addBorder(b)
			b.flatHover = b:CreateTexture(nil, "HIGHLIGHT")
			b.flatHover:SetAllPoints()
			b.flatHover:SetColorTexture(1, 1, 1, 0.08)
		end
		setShown(b.Left, not modern)
		setShown(b.Middle, not modern)
		setShown(b.Right, not modern)
		setFlat(b, modern)
		b.flatHover:SetShown(modern)
		local hl = b:GetHighlightTexture()
		if hl then hl:SetAlpha(modern and 0 or 1) end
		local fs = b:GetFontString()
		if fs then
			if modern then
				fs:SetTextColor(0.95, 0.95, 0.95)
			else
				fs:SetTextColor(1, 0.82, 0)
			end
		end
	end)
end

function ns.StyleSlider(s)
	register(s, function(sl, t, modern)
		if modern then
			sl:SetBackdrop({ bgFile = WHITE, insets = { left = 0, right = 0, top = 6, bottom = 6 } })
			sl:SetBackdropColor(0.2, 0.2, 0.22, 1)
			sl:SetThumbTexture(WHITE)
			local th = sl:GetThumbTexture()
			th:SetSize(8, 14)
			th:SetVertexColor(t.accent[1], t.accent[2], t.accent[3], 1)
		else
			sl:SetBackdrop({
				bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
				edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
				tile = true, tileSize = 8, edgeSize = 8,
				insets = { left = 3, right = 3, top = 6, bottom = 6 },
			})
			sl:SetBackdropColor(1, 1, 1, 1)
			sl:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
			local th = sl:GetThumbTexture()
			th:SetSize(32, 32)
			th:SetVertexColor(1, 1, 1, 1)
		end
	end)
end

function ns.StyleRow(row)
	register(row, function(r, _, modern)
		if modern then
			r:SetHighlightTexture(WHITE, "ADD")
			r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
			r:GetHighlightTexture():SetAlpha(1)
		else
			r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			r:GetHighlightTexture():SetVertexColor(1, 1, 1, 1)
			r:GetHighlightTexture():SetAlpha(0.35)
		end
	end)
end

-- Small icon buttons: muted in the modern theme, full colour in classic.
function ns.StyleIcon(btn)
	register(btn, function(b, _, modern)
		local tex = b:GetNormalTexture()
		if not tex then return end
		tex:SetDesaturated(modern)
		tex:SetVertexColor(modern and 0.85 or 1, modern and 0.85 or 1, modern and 0.85 or 1, 1)
	end)
end
