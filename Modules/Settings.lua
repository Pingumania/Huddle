local ADDON_NAME, ns = ...

local STRINGS = {
	enUS = {
		RELOAD_NOTE = 'This only takes effect after a reload.',
		RELOAD_INSTRUCTION = 'Use /reload when you are done changing settings.',
		DEFAULTS_CONFIRM = 'Reset the settings on this page to their defaults?',
		COMBAT_BLOCKED = "Can't open settings this way in combat",
	},
}

local L = setmetatable({}, {
	__index = function(_, key)
		local strings = STRINGS[GetLocale()]
		return strings and strings[key] or STRINGS.enUS[key]
	end,
})

local RELOAD_ICON = CreateAtlasMarkup('Recurringavailablequesticon', 16, 16)
local RELOAD_NOTE = L.RELOAD_NOTE

local reloadPopup = ADDON_NAME .. '_HUDDLE_RELOAD_REQUIRED'
local reloadRequired = {}
local reloadAcknowledged

StaticPopupDialogs[reloadPopup] = {
	text = RELOAD_NOTE .. '|n|n' .. L.RELOAD_INSTRUCTION,
	button1 = OKAY,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function()
		reloadAcknowledged = true
	end,
}

local defaultsPopup = ADDON_NAME .. '_HUDDLE_APPLY_DEFAULTS'

StaticPopupDialogs[defaultsPopup] = {
	text = L.DEFAULTS_CONFIRM,
	button1 = OKAY,
	button2 = CANCEL,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function(_, applyDefaults)
		applyDefaults()
	end,
}

local function onSettingChanged(setting, value)
	ns:TriggerOptionCallback(setting.variableKey, value)

	if reloadRequired[setting.variableKey] and not reloadAcknowledged then
		StaticPopup_Show(reloadPopup)
	end
end

local createCanvas
do
	local canvasMixin = {}
	function canvasMixin:SetDefaultsHandler(callback)
		local button = self:GetParent().Header.DefaultsButton
		button:Show()
		button:SetScript('OnClick', function()
			StaticPopup_Show(defaultsPopup, nil, nil, callback)
		end)
	end

	function createCanvas(name)
		local frame = CreateFrame('Frame')

		frame.Header = ns:CreateSettingsHeader(frame, name or ADDON_NAME)

		local canvas = Mixin(CreateFrame('Frame', nil, frame), canvasMixin)
		canvas:SetPoint('BOTTOMLEFT', 0, 5)
		canvas:SetPoint('BOTTOMRIGHT', -12, 5)
		canvas:SetPoint('TOP', 0, -56)

		return frame, canvas
	end
end

local SLIDER_VALUE_LABEL = MinimalSliderWithSteppersMixin.Label.Right

local function formatCustom(fmt, value)
	return fmt:format(value)
end

local function defaultSliderFormatter(value)
	return value
end

local function resolveSliderFormatter(valueFormat)
	if type(valueFormat) == 'string' then
		return GenerateClosure(formatCustom, valueFormat)
	elseif type(valueFormat) == 'function' then
		return valueFormat
	end
	return defaultSliderFormatter
end

local SECTION_HEADER_HEIGHT = 30
local SECTION_BOTTOM_PADDING = 10
local SECTION_TOGGLE_INSET = 8
local SECTION_LABEL_GAP = 4
local SECTION_TOGGLE_SCALE = 0.75

local PREVIEW_HEIGHT = 195

local settingsRegistry = {}

local function createSetting(category, savedvariable, info)
	ns:ArgCheck(info.key, 3, 'string')
	ns:ArgCheck(info.title, 3, 'string')
	ns:ArgCheck(info.type, 3, 'string')
	assert(info.default ~= nil, 'default must be set')

	ns.optionVariables = ns.optionVariables or {}
	ns.optionVariables[info.key] = savedvariable

	local title = info.title
	local tooltip = info.tooltip
	if info.requiresReload then
		reloadRequired[info.key] = true
		title = title .. ' ' .. RELOAD_ICON
		tooltip = tooltip and (tooltip .. '|n|n' .. RELOAD_NOTE) or RELOAD_NOTE
	end

	local uniqueKey = savedvariable .. '_' .. info.key
	local setting = Settings.RegisterAddOnSetting(category, uniqueKey, info.key, _G[savedvariable],
		type(info.default), title, info.default)

	settingsRegistry[info.key] = setting

	return setting, title, tooltip
end

local CANVAS_PAD_TOP = 10
local CANVAS_PAD_LEFT = 25
local CANVAS_SPACING = 9

local CANVAS_COLUMN_GAP = 8
local CANVAS_SCROLL_INSET = -15
local CANVAS_CONTROL_SHIFT = 40
local CANVAS_LABEL_X = -85

local CANVAS_CONTROL_ANCHORS = {
	toggle = {key = 'Checkbox', x = -80, y = 0},
	toggleWithButton = {key = 'Checkbox', x = -80, y = 0},
	slider = {key = 'SliderWithSteppers', x = -80, y = 3},
	menu = {key = 'Control', x = -48, y = 3},
	color = {key = 'ColorSwatch', x = -73, y = 0},
	custom = {key = 'customControl', x = -48, y = 3},
}

local function shiftCanvasControl(row, info)
	local anchor = CANVAS_CONTROL_ANCHORS[info.type]
	local control = anchor and row[anchor.key]
	if not control then
		return
	end

	if info.type == 'custom' and control.Slider then
		anchor = CANVAS_CONTROL_ANCHORS.slider
	end

	control:ClearAllPoints()
	control:SetPoint('LEFT', row, 'CENTER', anchor.x + CANVAS_CONTROL_SHIFT, anchor.y)

	row.Text:SetPoint('RIGHT', row, 'CENTER', CANVAS_LABEL_X + CANVAS_CONTROL_SHIFT, 0)
end

local CANVAS_TEMPLATES = {
	toggle = 'SettingsCheckboxControlTemplate',
	toggleWithButton = 'SettingsCheckboxWithButtonControlTemplate',
	slider = 'SettingsSliderControlTemplate',
	menu = 'SettingsDropdownControlTemplate',
	color = 'SettingsColorSwatchControlTemplate',
}

local CANVAS_TYPES = {custom = true, description = true, preview = true, section = true, toggles = true}

local TOGGLES_GAP = 24
local TOGGLES_INDENT = 21

local function needsCanvas(settings)
	for _, info in next, settings do
		if CANVAS_TYPES[info.type] then
			return true
		end
	end
end

local function templateHeight(template)
	local info = C_XMLUtil.GetTemplateInfo(template)
	return info and info.height or 26
end

local function initCanvasRow(row, initializer)
	row.GetElementData = function()
		return initializer
	end

	row:Init(initializer)

	return row
end

local function resolveLink(info)
	if info.requires then
		return {key = info.requires, gated = true, indent = true}
	elseif info.gatedBy then
		return {key = info.gatedBy, gated = true}
	elseif info.parent then
		return {key = info.parent, indent = true}
	end
end

local function isChainEnabled(links, settingsByKey, link)
	while link do
		if link.gated then
			local setting = settingsByKey[link.key]
			if not (setting and setting:GetValue()) then
				return false
			end
		end

		link = links[link.key]
	end

	return true
end

local function createControlInitializer(setting, info, tooltip)
	if info.type == 'toggle' then
		return Settings.CreateCheckboxInitializer(setting, nil, tooltip)
	elseif info.type == 'toggleWithButton' then
		ns:ArgCheck(info.buttonText, 3, 'string')
		ns:ArgCheck(info.onClick, 3, 'function')

		local clickRequiresSet = false
		return CreateSettingsCheckboxWithButtonInitializer(setting, info.buttonText, info.onClick, nil,
			clickRequiresSet, tooltip)
	elseif info.type == 'slider' then
		ns:ArgCheck(info.minValue, 3, 'number')
		ns:ArgCheck(info.maxValue, 3, 'number')

		local options = Settings.CreateSliderOptions(info.minValue, info.maxValue, info.valueStep or 1)
		options:SetLabelFormatter(SLIDER_VALUE_LABEL, resolveSliderFormatter(info.valueFormat))

		return Settings.CreateSliderInitializer(setting, options, tooltip)
	elseif info.type == 'menu' then
		ns:ArgCheck(info.options, 3, 'table')

		local options = function()
			local container = Settings.CreateControlTextContainer()
			for _, option in next, info.options do
				container:Add(option.value, option.label)
			end
			return container:GetData()
		end

		return Settings.CreateDropdownInitializer(setting, options, tooltip)
	elseif info.type == 'color' then
		assert(#info.default == 8, 'color default must be an 8-character AARRGGBB hex string')

		return Settings.CreateColorSwatchInitializer(setting, nil, tooltip)
	end

	error('type is invalid')
end

local function registerSetting(category, savedvariable, info)
	local setting, _, tooltip = createSetting(category, savedvariable, info)

	local initializer
	if not (info.type == 'color' and ns:IsClassicEra()) then
		initializer = createControlInitializer(setting, info, tooltip)
	end

	setting:SetValueChangedCallback(onSettingChanged)
	ns:TriggerOptionCallback(info.key, setting:GetValue())

	return initializer, setting
end

local function createCanvasSection(parent, info, relayout)
	local data = {name = info.title, expanded = not not info.expanded}
	local initializer = Settings.CreateElementInitializer('SettingsExpandableSectionTemplate', data)
	local row = CreateFrame('EventFrame', nil, parent, 'SettingsExpandableSectionTemplate')
	row.Button:SetPoint('TOPRIGHT', -6, 0)

	local body
	if info.createContent then
		body = info.createContent(row)
		body:SetParent(row)
		body:ClearAllPoints()
		body:SetPoint('TOPLEFT', 0, -SECTION_HEADER_HEIGHT)
		body:SetPoint('TOPRIGHT', 0, -SECTION_HEADER_HEIGHT)
	end

	function row:CalculateHeight()
		if not body or not data.expanded then
			return SECTION_HEADER_HEIGHT
		end

		return SECTION_HEADER_HEIGHT + body:GetHeight() + SECTION_BOTTOM_PADDING
	end

	function row:OnExpandedChanged(expanded)
		self.Button.Right:SetAtlas(expanded and 'Options_ListExpand_Right_Expanded' or 'Options_ListExpand_Right',
			TextureKitConstants.UseAtlasSize)

		if body then
			body:SetShown(expanded)
		end

		relayout()
	end

	initCanvasRow(row, initializer)
	row:SetHeight(row:CalculateHeight())
	row:OnExpandedChanged(data.expanded)

	if info.tooltip then
		row.Button:SetScript('OnEnter', function(self)
			SettingsTooltip:SetOwner(self, 'ANCHOR_RIGHT', -10, 0)
			Settings.InitTooltip(info.title, info.tooltip)
			SettingsTooltip:Show()
		end)

		row.Button:SetScript('OnLeave', function()
			SettingsTooltip:Hide()
		end)
	end

	return row, data
end

local function createCanvasDescription(parent, info)
	local row = CreateFrame('Frame', nil, parent)

	row.huddleText = row:CreateFontString(nil, 'ARTWORK', 'GameFontHighlight')
	row.huddleText:SetJustifyH('LEFT')
	row.huddleText:SetPoint('TOPLEFT')
	row.huddleText:SetText(info.title)

	row:SetHeight(1)

	return row
end

local function createCanvasPreview(parent, info)
	local row = CreateFrame('Frame', nil, parent)
	row:SetHeight(info.height or PREVIEW_HEIGHT)

	local border = row:CreateTexture(nil, 'BACKGROUND')
	border:SetAtlas('options_frame_child')
	border:SetPoint('TOPLEFT', 20, 0)
	border:SetPoint('BOTTOMRIGHT', -20, 0)

	local background = row:CreateTexture(nil, 'BACKGROUND', nil, 1)
	background:SetPoint('TOPLEFT', border, 'TOPLEFT', 3, -3)
	background:SetPoint('BOTTOMRIGHT', border, 'BOTTOMRIGHT', -3, 3)
	background:SetColorTexture(0, 0, 0, 0.3)

	if info.title then
		local label = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
		label:SetJustifyH('LEFT')
		label:SetPoint('TOPLEFT', border, 'TOPLEFT', 10, -10)
		label:SetText(info.title)
	end

	info.createPreview(row)

	return row
end

local function renderCanvasSettings(canvas, category, savedvariable, settings)
	local scroll = CreateFrame('ScrollFrame', nil, canvas)
	scroll:SetPoint('TOPLEFT', CANVAS_SCROLL_INSET, -CANVAS_PAD_TOP)
	scroll:SetPoint('BOTTOMRIGHT', -22, 0)
	scroll:EnableMouseWheel(true)

	local scrollBar = CreateFrame('EventFrame', nil, canvas, 'MinimalScrollBar')
	scrollBar:SetPoint('TOPLEFT', scroll, 'TOPRIGHT', 8, 0)
	scrollBar:SetPoint('BOTTOMLEFT', scroll, 'BOTTOMRIGHT', 8, 0)

	local content = CreateFrame('Frame', nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	local relayout

	scroll:SetScript('OnSizeChanged', function(_, width)
		content:SetWidth(width)
		relayout()
	end)

	ScrollUtil.InitScrollFrameWithScrollBar(scroll, scrollBar)

	local order = {}
	local controls = {}
	local settingsByKey = {}
	local links = {}

	local function isRowVisible(row)
		return not (row.huddleSection and not row.huddleSection.expanded)
	end

	local function collectBlocks(visible)
		local blocks = {}
		local index = 1

		while index <= #visible do
			local row = visible[index]
			local block = {row, columns = row.huddleColumns}

			index = index + 1
			while index <= #visible and row.huddleExpandedState
				and visible[index].huddleSection == row.huddleExpandedState do
				block[#block + 1] = visible[index]
				index = index + 1
			end

			blocks[#blocks + 1] = block
		end

		return blocks
	end

	local function placeBlock(block, x, y, columnWidth)
		local height = 0

		for _, row in ipairs(block) do
			row:ClearAllPoints()
			row:SetPoint('TOPLEFT', x, -(y + height))

			if columnWidth then
				row:SetWidth(columnWidth)
			else
				row:SetPoint('TOPRIGHT', 0, -(y + height))
			end

			height = height + row:GetHeight() + CANVAS_SPACING
		end

		return height - CANVAS_SPACING
	end

	function relayout()
		local width = content:GetWidth() - CANVAS_PAD_LEFT
		local columnWidth = (width - CANVAS_COLUMN_GAP) / 2

		local visible = {}
		for _, row in ipairs(order) do
			local shown = isRowVisible(row)
			row:SetShown(shown)

			if shown then
				if row.huddleText and width > 0 then
					row.huddleText:SetWidth(width)
					row:SetHeight(row.huddleText:GetStringHeight() + CANVAS_SPACING)
				end

				visible[#visible + 1] = row
			end
		end

		local columnOffsets = {0, 0}
		local column = 1

		for _, block in ipairs(collectBlocks(visible)) do
			if columnWidth > 0 and block.columns == 2 then
				local x = CANVAS_PAD_LEFT + (column - 1) * (columnWidth + CANVAS_COLUMN_GAP)
				local height = placeBlock(block, x, columnOffsets[column], columnWidth)

				columnOffsets[column] = columnOffsets[column] + height + CANVAS_SPACING
				column = column == 1 and 2 or 1
			else
				local y = math.max(columnOffsets[1], columnOffsets[2])
				local height = placeBlock(block, CANVAS_PAD_LEFT, y)

				columnOffsets[1] = y + height + CANVAS_SPACING
				columnOffsets[2] = columnOffsets[1]
				column = 1
			end
		end

		local offset = math.max(columnOffsets[1], columnOffsets[2])
		content:SetHeight(math.max(offset, 1))
		scrollBar:SetShown(content:GetHeight() > scroll:GetHeight() + 1)
	end

	local function isLinkEnabled(link)
		return isChainEnabled(links, settingsByKey, link)
	end

	local function evaluate()
		for _, row in ipairs(controls) do
			if isRowVisible(row) then
				row:EvaluateState()
			end
		end
	end

	local function onSectionToggled()
		relayout()
		evaluate()
	end

	local defaults = {}
	local customDefaults = {}

	local function applyLink(initializer, link)
		if not link then
			return
		end

		initializer:AddModifyPredicate(function()
			return isLinkEnabled(link)
		end)

		if link.indent then
			initializer:Indent()
		end
	end

	local function createElementRow(info, link)
		local initializer = Settings.CreateElementInitializer('SettingsListElementTemplate',
			{name = info.title or '', tooltip = info.tooltip})
		applyLink(initializer, link)

		local row = CreateFrame('Frame', nil, content, 'SettingsListElementTemplate')
		row:SetHeight(templateHeight('SettingsCheckboxControlTemplate'))
		row.cbrHandles = Settings.CreateCallbackHandleContainer()

		return row, initializer
	end

	local function bindSetting(key, setting, checkbox)
		defaults[#defaults + 1] = setting

		setting:SetValueChangedCallback(function(changed, value)
			onSettingChanged(changed, value)

			if checkbox then
				checkbox:SetValue(value)
			end

			evaluate()
		end)

		ns:TriggerOptionCallback(key, setting:GetValue())
	end

	local function addRow(info, section)
		local row, sectionState

		if info.type == 'header' then
			row = CreateFrame('Frame', nil, content, 'SettingsListSectionHeaderTemplate')
			row:SetHeight(templateHeight('SettingsListSectionHeaderTemplate'))
			initCanvasRow(row, CreateSettingsListSectionHeaderInitializer(info.title, info.tooltip))
		elseif info.type == 'description' then
			ns:ArgCheck(info.title, 3, 'string')

			row = createCanvasDescription(content, info)
		elseif info.type == 'preview' then
			ns:ArgCheck(info.createPreview, 3, 'function')

			row = createCanvasPreview(content, info)

			if info.onDefaults then
				customDefaults[#customDefaults + 1] = info.onDefaults
			end
		elseif info.type == 'section' then
			ns:ArgCheck(info.title, 3, 'string')
			assert(info.createContent or info.settings, 'a section needs either createContent or settings')

			row, sectionState = createCanvasSection(content, info, onSectionToggled)

			if info.key then
				local setting = createSetting(category, savedvariable, {
					key = info.key,
					title = info.title,
					type = 'toggle',
					default = info.default,
				})

				settingsByKey[info.key] = setting

				local checkbox = CreateFrame('CheckButton', nil, row, 'SettingsCheckboxTemplate')
				checkbox:SetScale(SECTION_TOGGLE_SCALE)
				checkbox:SetPoint('LEFT', row.Button, 'LEFT', SECTION_TOGGLE_INSET, 2)
				checkbox:SetFrameLevel(row.Button:GetFrameLevel() + 1)

				row.Button.Text:ClearAllPoints()
				row.Button.Text:SetPoint('LEFT', checkbox, 'RIGHT', SECTION_LABEL_GAP, 0)

				checkbox:Init(setting:GetValue())
				checkbox:RegisterCallback('OnValueChanged', function(_, value)
					setting:SetValue(not not value)
				end, checkbox)

				bindSetting(info.key, setting, checkbox)
			end

			if info.onDefaults then
				customDefaults[#customDefaults + 1] = info.onDefaults
			end
		elseif info.type == 'custom' then
			ns:ArgCheck(info.title, 3, 'string')
			ns:ArgCheck(info.createControl, 3, 'function')

			local link = resolveLink(info)
			local initializer
			row, initializer = createElementRow(info, link)

			function row:EvaluateState()
				local enabled = isLinkEnabled(link)
				self:DisplayEnabled(enabled)

				if self.customControl then
					self.customControl:SetAlpha(enabled and 1 or 0.4)

					if self.customControl.SetEnabled then
						self.customControl:SetEnabled(enabled)
					end
				end
			end

			initCanvasRow(row, initializer)

			row.customControl = info.createControl(row)
			shiftCanvasControl(row, info)

			if info.onDefaults then
				customDefaults[#customDefaults + 1] = info.onDefaults
			end

			if row.customControl.SetTooltipFunc then
				row.customControl:SetTooltipFunc(GenerateClosure(Settings.InitTooltip, info.title, info.tooltip))
			end
			controls[#controls + 1] = row
		elseif info.type == 'toggles' then
			ns:ArgCheck(info.settings, 3, 'table')

			local link = resolveLink(info)
			local initializer
			row, initializer = createElementRow(info, link)

			initCanvasRow(row, initializer)

			row.huddleToggles = {}

			local previous
			for _, entry in ipairs(info.settings) do
				local setting = createSetting(category, savedvariable, entry)
				links[entry.key] = link
				settingsByKey[entry.key] = setting

				local checkbox = CreateFrame('CheckButton', nil, row, 'SettingsCheckboxTemplate')
				checkbox:SetFrameLevel(row.Tooltip:GetFrameLevel() + 1)
				checkbox:Init(setting:GetValue())
				checkbox:RegisterCallback('OnValueChanged', function(_, value)
					setting:SetValue(not not value)
				end, checkbox)

				checkbox.Text = checkbox:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
				checkbox.Text:SetPoint('LEFT', checkbox, 'RIGHT', 2, 0)
				checkbox.Text:SetText(entry.title)

				if previous then
					checkbox:SetPoint('LEFT', previous.Text, 'RIGHT', TOGGLES_GAP, 0)
				elseif info.title then
					checkbox:SetPoint('LEFT', row, 'CENTER',
						CANVAS_CONTROL_ANCHORS.toggle.x + CANVAS_CONTROL_SHIFT, CANVAS_CONTROL_ANCHORS.toggle.y)
				else
					checkbox:SetPoint('LEFT', row, 'LEFT', TOGGLES_INDENT, CANVAS_CONTROL_ANCHORS.toggle.y)
				end

				bindSetting(entry.key, setting, checkbox)

				row.huddleToggles[#row.huddleToggles + 1] = checkbox
				previous = checkbox
			end

			row.Text:SetPoint('RIGHT', row, 'CENTER', CANVAS_LABEL_X + CANVAS_CONTROL_SHIFT, 0)

			function row:EvaluateState()
				local enabled = isLinkEnabled(link)
				self:DisplayEnabled(enabled)

				for _, checkbox in ipairs(self.huddleToggles) do
					checkbox:SetEnabled(enabled)
					checkbox:SetAlpha(enabled and 1 or 0.4)
				end
			end

			controls[#controls + 1] = row
		elseif info.type == 'color' and ns:IsClassicEra() then
		else
			local setting, _, tooltip = createSetting(category, savedvariable, info)
			local link = resolveLink(info)
			links[info.key] = link
			settingsByKey[info.key] = setting

			local initializer = createControlInitializer(setting, info, tooltip)
			applyLink(initializer, link)

			row = CreateFrame('Frame', nil, content, CANVAS_TEMPLATES[info.type])
			row:SetHeight(templateHeight(CANVAS_TEMPLATES[info.type]))
			initCanvasRow(row, initializer)
			controls[#controls + 1] = row

			if info.buttonWidth then
				row.Button:SetWidth(info.buttonWidth)
			end

			shiftCanvasControl(row, info)

			bindSetting(info.key, setting)
		end

		if row then
			row.huddleSection = section
			row.huddleColumns = info.columns
			row.huddleExpandedState = sectionState
			order[#order + 1] = row
		end

		return row, sectionState
	end

	for _, info in ipairs(settings) do
		if info.type == 'section' and info.settings then
			local _, state = addRow(info)

			for _, child in ipairs(info.settings) do
				if info.key and not child.requires and not child.gatedBy then
					child.gatedBy = info.key
				end

				addRow(child, state)
			end
		else
			addRow(info)
		end
	end

	if #defaults > 0 or #customDefaults > 0 then
		local function applyDefaults()
			for _, setting in ipairs(defaults) do
				setting:SetValueToDefault()
			end

			for _, onDefaults in ipairs(customDefaults) do
				onDefaults()
			end

			for _, row in ipairs(controls) do
				if row.customControl and row.customControl.GenerateMenu then
					row.customControl:GenerateMenu()
				end
			end

			evaluate()
		end

		canvas:SetDefaultsHandler(applyDefaults)
	end

	relayout()
	evaluate()
end

local function findSubSettings(children, name)
	for _, info in ipairs(children) do
		if info.name == name then
			return info
		end
	end
end

local function registerSettingsList(category, layout, savedvariable, settings)
	local keys = {}
	local initializers = {}
	local settingsByKey = {}
	local links = {}
	for index, info in ipairs(settings) do
		if info.type == 'header' then
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(info.title, info.tooltip))
		else
			local initializer, setting = registerSetting(category, savedvariable, info)
			if initializer then
				layout:AddInitializer(initializer)
			end

			keys[info.key] = index
			initializers[info.key] = initializer
			settingsByKey[info.key] = setting
			links[info.key] = resolveLink(info)
		end
	end
	return keys, initializers, links, settingsByKey
end

local function applyDependencies(settings, keys, initializers, links, settingsByKey)
	for key, link in next, links do
		assert(not not keys[link.key], string.format("setting '%s' can't depend on invalid setting '%s'", key, link.key))

		if link.gated then
			assert(settings[keys[link.key]].type == 'toggle', string.format("setting '%s' can't depend on a non-toggle setting", key))
		end

		local steps = 0
		local ancestor = links[link.key]
		while ancestor do
			steps = steps + 1
			assert(steps <= 16, string.format("setting '%s' has a circular dependency", key))
			ancestor = links[ancestor.key]
		end
	end

	for key, link in next, links do
		local initializer = initializers[key]

		local predicate = function()
			return isChainEnabled(links, settingsByKey, links[key])
		end

		local ancestor = link
		if link.indent then
			initializer:SetParentInitializer(initializers[link.key], predicate)
			ancestor = links[link.key]
		else
			initializer:AddModifyPredicate(predicate)
		end

		while ancestor do
			local setting = settingsByKey[ancestor.key]
			if setting then
				initializer:AddEvaluateStateCVar(setting:GetVariable())
			end

			ancestor = links[ancestor.key]
		end
	end
end

local function whenLoaded(callback)
	local _, isReady = C_AddOns.IsAddOnLoaded(ADDON_NAME)
	if isReady then
		callback()
	else
		ns:RegisterEvent('ADDON_LOADED', function(_, name)
			if name == ADDON_NAME then
				callback()
				return true -- unregister
			end
		end)
	end
end

local settingsCategoryID
local function registerSettings(savedvariable, settings)
	local categoryName = C_AddOns.GetAddOnMetadata(ADDON_NAME, 'Title')

	local category, layout, canvas
	if needsCanvas(settings) then
		local frame
		frame, canvas = createCanvas()
		category = Settings.RegisterCanvasLayoutCategory(frame, categoryName)
	else
		category, layout = Settings.RegisterVerticalLayoutCategory(categoryName)
	end

	Settings.RegisterAddOnCategory(category)
	settingsCategoryID = category:GetID()

	if not _G[savedvariable] then
		_G[savedvariable] = {}
	end

	if canvas then
		renderCanvasSettings(canvas, category, savedvariable, settings)
	else
		local keys, initializers, links, settingsByKey = registerSettingsList(category, layout, savedvariable, settings)
		applyDependencies(settings, keys, initializers, links, settingsByKey)
	end

	if ns.settingsChildren then
		for _, info in ipairs(ns.settingsChildren) do
			if info.settings then
				if needsCanvas(info.settings) then
					local childFrame, childCanvas = createCanvas(info.name)
					local child = Settings.RegisterCanvasLayoutSubcategory(category, childFrame, info.name)
					renderCanvasSettings(childCanvas, child, savedvariable, info.settings)
				else
					local child, childLayout = Settings.RegisterVerticalLayoutSubcategory(category, info.name)
					local childKeys, childInitializers, childLinks, childSettings =
						registerSettingsList(child, childLayout, savedvariable, info.settings)
					applyDependencies(info.settings, childKeys, childInitializers, childLinks, childSettings)
				end
			elseif info.callback then
				local frame, canvas = createCanvas(info.name)
				Settings.RegisterCanvasLayoutSubcategory(category, frame, info.name)

				local shown
				SettingsPanel:HookScript('OnShow', function()
					if not shown then
						info.callback(canvas)
						shown = true
					end
				end)
			end
		end
	end
end

--[[ namespace:RegisterSettings(_savedvariables_, _settings_) ![](https://img.shields.io/badge/function-blue)
Registers a set of `settings` with the interface options panel.
The values will be stored by the `settings`' objects' `key` in `savedvariables`.

Should be used with the options methods below.

A panel containing a `custom`, `section` or `preview` object is drawn on a canvas of our own instead
of in Blizzard's settings list, because an addon cannot add a row to that list without tainting it.
Such a panel does not take part in the settings search.

Usage:
```lua
ns:RegisterSettings('MyAddOnDB', {
	{
		key = 'myToggle',
		type = 'toggle',
		title = 'My Toggle',
		tooltip = 'Longer description of the toggle in a tooltip',
		default = false,
	},
	{
		key = 'myToggleWithButton',
		type = 'toggleWithButton', -- a checkbox with a button beside it, on one row
		title = 'My Toggle',
		default = false,
		buttonText = 'Sample',
		buttonWidth = 100, -- (optional) the template's own width is 200
		onClick = function() end, -- the button stays clickable while the toggle is off
	},
	{
		key = 'mySlider',
		type = 'slider',
		title = 'My Slider',
		tooltip = 'Longer description of the slider in a tooltip',
		default = 0.5,
		minValue = 0.1,
		maxValue = 1.0,
		valueStep = 0.01, -- (optional) step value, defaults to 1
		valueFormat = formatter, -- (optional) callback function or a string for string.format
		requires = 'myToggle', -- (optional) dependency on another setting (must be a "toggle")
	},
	{
		key = 'myMenu',
		type = 'menu',
		title = 'My Menu',
		tooltip = 'Longer description of the menu in a tooltip',
		default = 'key1',
		options = {
			{value = 'key1', label = 'First option'},
			{value = 'key2', label = 'Second option'},
			{value = 'key3', label = 'Third option'},
		},
		parent = 'mySlider', -- (optional) set another setting as its parent (indents this setting)
		gatedBy = 'myToggle', -- (optional) like "requires", but without indenting this setting
	},
	{
		key = 'myColor',
		type = 'color',
		title = 'My Color',
		tooltip = 'Longer description of the color in a tooltip',
		default = 'ffff00ff', -- "AARRGGBB" format
		requiresReload = true, -- (optional) marks the row and warns once per session when changed
	},
	{
		type = 'header',
		title = 'A Section Header',
		tooltip = 'Optional tooltip for the header', -- (optional)
	},
	{
		type = 'description',
		title = 'A paragraph of explanatory text, wrapped to the width of the panel.',
	},
	{
		type = 'custom',
		title = 'A Custom Row',
		tooltip = 'Optional tooltip', -- (optional)
		requires = 'myToggle', -- (optional) same dependency handling as a keyed setting
		onDefaults = function() end, -- (optional) the row owns its value, so it resets it itself
		createControl = function(rowFrame) -- a SettingsListElementTemplate row; rowFrame.Text is its label
			return ns:CreateToggle(rowFrame, '', getValue, setValue) -- any frame; anchored to the row's right side
		end,
	},
	{
		-- several checkboxes sharing one row. The first sits exactly where a lone 'toggle' would,
		-- each one after it follows the previous label. Every entry is a real setting with its own
		-- key and default; the row's own requires/gatedBy gates all of them together
		type = 'toggles',
		title = 'A Shared Row', -- (optional) the row's label, on the left like any other row
		tooltip = 'Optional tooltip', -- (optional)
		requires = 'myToggle', -- (optional) same dependency handling as a keyed setting
		settings = {
			{key = 'myFirstToggle', type = 'toggle', title = 'First', default = false},
			{key = 'mySecondToggle', type = 'toggle', title = 'Second', default = false},
		},
	},
	{
		type = 'section',
		title = 'A Collapsible Section',
		tooltip = 'Optional tooltip, shown over the header bar', -- (optional)
		expanded = false, -- (optional) defaults to false, so sections start collapsed
		onDefaults = function() end, -- (optional) the section owns its values, so it resets them itself
		createContent = function(section) -- draws its own content, which the section grows to fit
			local content = CreateFrame('Frame', nil, section)
			content:SetHeight(80) -- the height is read back to size the expanded section
			return content
		end,
	},
	{
		type = 'section',
		title = 'A Collapsible Group',
		expanded = false,
		-- instead of createContent, a section can group settings. They stay ordinary rows of this
		-- panel, keeping their dependencies and defaults, and collapsing only hides them
		settings = {
			{key = 'myGroupedToggle', type = 'toggle', title = 'Grouped', default = false},
		},
	},
	{
		-- giving a section a key puts a toggle on the header bar itself, so the whole group reads
		-- as one line while collapsed. It gates every setting inside it that does not already
		-- depend on something more specific
		type = 'section',
		title = 'A Collapsible Group With A Toggle',
		key = 'myGroupToggle',
		default = false,
		expanded = false,
		columns = 2, -- (optional) pack with the next collapsed 2-column row, half width each
		settings = {
			{key = 'myGatedToggle', type = 'toggle', title = 'Gated', default = false},
		},
	},
	{
		type = 'preview',
		title = 'PREVIEW', -- (optional) label drawn inside the box, defaults to PREVIEW
		height = 195, -- (optional) row height, defaults to 195
		onDefaults = function() end, -- (optional) the row owns its values, so it resets them itself
		createPreview = function(panel) -- called once per physical row frame (rows get recycled)
			local preview = CreateFrame('Frame', nil, panel)
			preview:SetPoint('CENTER')
			preview:SetSize(200, 100)
			return preview
		end,
	},
})
```
--]]
function ns:RegisterSettings(savedvariable, settings)
	ns:ArgCheck(savedvariable, 1, 'string')
	ns:ArgCheck(settings, 2, 'table')

	if not self.settingsChildren then
		self.settingsChildren = {}
	end

	whenLoaded(function()
		registerSettings(savedvariable, settings)
	end)
end

--[[ namespace:RegisterSubSettings(_name_, _settings_) ![](https://img.shields.io/badge/function-blue)
Registers a set of `settings` as a sub-category. `name` must be unique.
The savedvariables will be stored under the main savedvariables in a table entry named after `name`.

The `settings` are identical to that of `namespace:RegisterSettings`.
--]]
function ns:RegisterSubSettings(name, settings)
	ns:ArgCheck(name, 1, 'string')
	ns:ArgCheck(settings, 2, 'table')
	assert(not not self.settingsChildren, "can't register sub-settings without root settings")
	assert(not findSubSettings(self.settingsChildren, name), "can't register two sub-settings with the same name")
	table.insert(self.settingsChildren, {
		name = name,
		settings = settings,
	})
end

--[[ namespace:RegisterSubSettingsCanvas(_name_, _callback_) ![](https://img.shields.io/badge/function-blue)
Registers a canvas sub-category. This does not handle savedvariables.

`name` must be unique, and `callback` is called with a canvas `frame` as payload.

Canvas frame has a custom method `SetDefaultsHandler` which takes a callback as arg1.
This callback is triggered when the "Defaults" button is clicked and the player confirms.
--]]
function ns:RegisterSubSettingsCanvas(name, callback)
	ns:ArgCheck(name, 1, 'string')
	ns:ArgCheck(callback, 2, 'function')
	assert(not not self.settingsChildren, "can't register sub-settings without root settings")
	assert(not findSubSettings(self.settingsChildren, name), "can't register two sub-settings with the same name")
	table.insert(self.settingsChildren, {
		name = name,
		callback = callback,
	})
end

--[[ namespace:OpenSettings() ![](https://img.shields.io/badge/function-blue)
Opens the settings panel for this addon.
--]]
function ns:OpenSettings()
	assert(not not settingsCategoryID, 'must register settings first')
	if InCombatLockdown() then
		ns:Print(L.COMBAT_BLOCKED)
	else
		Settings.OpenToCategory(settingsCategoryID)
	end
end

--[[ namespace:RegisterSettingsSlash(_..._) ![](https://img.shields.io/badge/function-blue)
Wrapper for `namespace:RegisterSlash(...)`, except the callback is provided and will open the settings panel for this addon.
--]]
function ns:RegisterSettingsSlash(...)
	local data = {...}
	table.insert(data, function()
		ns:OpenSettings()
	end)

	ns:RegisterSlash(unpack(data))
end

--[[ namespace:GetOption(_key_) ![](https://img.shields.io/badge/function-blue)
Returns the value for the given option `key`.
--]]
function ns:GetOption(key)
	ns:ArgCheck(key, 1, 'string')
	assert(ns:AreOptionsLoaded(key), "options aren't loaded")
	local savedvariable = self.optionVariables[key]
	assert(_G[savedvariable][key] ~= nil, "key doesn't exist")
	return _G[savedvariable][key]
end

--[[ namespace:SetOption(_key_, _value_) ![](https://img.shields.io/badge/function-blue)
Sets a new `value` to the given options `key`.
--]]
function ns:SetOption(key, value)
	ns:ArgCheck(key, 1, 'string')
	assert(ns:AreOptionsLoaded(key), "options aren't loaded")
	local savedvariable = self.optionVariables[key]
	assert(_G[savedvariable][key] ~= nil, "key doesn't exist")

	local setting = settingsRegistry[key]
	if setting then
		setting:SetValue(value)
	else
		_G[savedvariable][key] = value
		ns:TriggerOptionCallback(key, value)
	end
end

--[[ namespace:AreOptionsLoaded([_key_]) ![](https://img.shields.io/badge/function-blue)
Checks to see if the savedvariables has been loaded in the game.
If `key` is given, checks specifically for the savedvariable backing that option key.
--]]
function ns:AreOptionsLoaded(key)
	if not self.optionVariables then
		return false
	end

	if key then
		local savedvariable = self.optionVariables[key]
		return not not (savedvariable and _G[savedvariable])
	end

	return next(self.optionVariables) ~= nil
end

--[[ namespace:RegisterOptionCallback(_key_, _callback_) ![](https://img.shields.io/badge/function-blue)
Register a `callback` function with the option `key`.
--]]
function ns:RegisterOptionCallback(key, callback)
	ns:ArgCheck(key, 1, 'string')
	ns:ArgCheck(callback, 2, 'function')

	if not self.settingsCallbacks then
		self.settingsCallbacks = {}
	end

	if not self.settingsCallbacks[key] then
		self.settingsCallbacks[key] = {}
	end

	table.insert(self.settingsCallbacks[key], callback)
end

--[[ namespace:TriggerOptionCallback(_key_, _value_) ![](https://img.shields.io/badge/function-blue)
Trigger all registered option callbacks for the given `key`, supplying the `value`.
--]]
function ns:TriggerOptionCallback(key, value)
	ns:ArgCheck(key, 1, 'string')

	if self.settingsCallbacks and self.settingsCallbacks[key] then
		for _, callback in next, self.settingsCallbacks[key] do
			local successful, ret = pcall(callback, value)
			if not successful then
				error(ret)
			end
		end
	end
end

do
	local function resetSlider(frame)
		frame.slider:UnregisterCallback('OnValueChanged', frame)
		frame.slider:Release()
	end

	local function createSlider(root, name, getter, setter, minValue, maxValue, steps, formatter)
		local element = root:CreateButton(name)
		local subMenu = element:CreateFrame()
		subMenu:AddResetter(resetSlider)
		subMenu:AddInitializer(function(frame)
			local slider = frame:AttachTemplate('MinimalSliderWithSteppersTemplate')
			slider:SetPoint('TOPLEFT', 0, -1)
			slider:SetSize(150, 25)
			slider:RegisterCallback('OnValueChanged', setter, frame)
			slider:Init(getter(), minValue, maxValue, (maxValue - minValue) / steps, {
				[SLIDER_VALUE_LABEL] = formatter or defaultSliderFormatter,
			})
			frame.slider = slider -- ref for resetter

			local pad = 30 -- for the label
			return slider:GetWidth() + pad, slider:GetHeight()
		end)

		return element
	end

	local function colorPickerClick(data)
		ColorPickerFrame:SetupColorPickerAndShow(data)
	end
	local function colorPickerChange(setting)
		local r, g, b = ColorPickerFrame:GetColorRGB()
		if #setting.default == 8 then
			local a = ColorPickerFrame:GetColorAlpha()
			ns:SetOption(setting.key, CreateColor(r, g, b, a):GenerateHexColor())
		else
			ns:SetOption(setting.key, CreateColor(r, g, b):GenerateHexColorNoAlpha())
		end
	end
	local function colorPickerReset(setting, previousColor)
		if #setting.default == 8 then
			ns:SetOption(setting.key, CreateColorFromHexString(previousColor):GenerateHexColor())
		else
			ns:SetOption(setting.key, CreateColorFromRGBHexString(previousColor):GenerateHexColorNoAlpha())
		end
	end

	local function menuGetter(setting, value)
		return ns:GetOption(setting.key) == value
	end
	local function menuSetter(setting, value)
		ns:SetOption(setting.key, value)
	end

	local function menuTooltip(button, element)
		GameTooltip:ClearAllPoints()
		GameTooltip:SetPoint('RIGHT', button, 'LEFT', -3, 0)
		GameTooltip:SetOwner(button, 'ANCHOR_PRESERVE')
		GameTooltip:ClearLines()
		GameTooltip:AddLine(element.text, 1, 1, 1)
		GameTooltip:AddLine(element.tooltip, nil, nil, nil, true)
		GameTooltip:Show()
	end

	local function registerMapSettings(savedvariable, settings)
		if not _G[savedvariable] then
			_G[savedvariable] = {}
		end

		ns.optionVariables = ns.optionVariables or {}
		for _, setting in next, settings do
			if _G[savedvariable][setting.key] == nil then
				_G[savedvariable][setting.key] = setting.default
			end
			ns.optionVariables[setting.key] = savedvariable
		end

		-- TODO: menus also has "new feature" flags/textures, see if we can hook into that

		Menu.ModifyMenu('MENU_WORLD_MAP_TRACKING', function(_, root)
			root:CreateDivider()
			root:CreateTitle((ADDON_NAME:gsub('(%l)(%u)', '%1 %2')) .. HEADER_COLON)

			for _, setting in next, settings do
				local element
				if setting.type == 'toggle' then
					element = root:CreateCheckbox(setting.title, function()
						return ns:GetOption(setting.key)
					end, function()
						ns:SetOption(setting.key, not ns:GetOption(setting.key))
					end)
				elseif setting.type == 'slider' then
					element = createSlider(root, setting.title, function()
						return ns:GetOption(setting.key)
					end, function(_, value)
						ns:SetOption(setting.key, value)
					end, setting.minValue, setting.maxValue, setting.valueStep or 1, resolveSliderFormatter(setting.valueFormat))
				elseif setting.type == 'color' then
					local value = ns:GetOption(setting.key)
					local hasOpacity = #value == 8
					local color = hasOpacity and CreateColorFromHexString(value) or CreateColorFromRGBHexString(value)
					local r, g, b, a = color:GetRGBA()
					element = root:CreateColorSwatch(setting.title, colorPickerClick, {
						swatchFunc = GenerateClosure(colorPickerChange, setting),
						opacityFunc = GenerateClosure(colorPickerChange, setting),
						cancelFunc = GenerateClosure(colorPickerReset, setting),
						r = r,
						g = g,
						b = b,
						opacity = a,
						hasOpacity = hasOpacity,
					})
				elseif setting.type == 'menu' then
					element = root:CreateButton(setting.title)
					for _, option in next, setting.options do
						element:CreateRadio(
							option.label,
							GenerateClosure(menuGetter, setting),
							GenerateClosure(menuSetter, setting),
							option.value
						)
					end
				end

				if element and setting.tooltip then
					element.tooltip = setting.tooltip
					element:SetOnEnter(menuTooltip)
					element:SetOnLeave(GameTooltip_Hide)
				end
			end
		end)
	end

	--[[ namespace:RegisterMapSettings(_savedvariable_, _settings_) ![](https://img.shields.io/badge/function-blue)
	Registers a set of `settings` to inject into the world map tracking menu.
	The values will be stored by the `settings`' objects' `key` in `savedvariables`.

	The `settings` object is identical to the one for `namespace:RegisterSettings`.
	--]]
	function ns:RegisterMapSettings(savedvariable, settings)
		ns:ArgCheck(savedvariable, 1, 'string')
		ns:ArgCheck(settings, 2, 'table')

		whenLoaded(function()
			registerMapSettings(savedvariable, settings)
		end)
	end
end

--[[ namespace:CreateToggle(_parent_, _label_, _getValue_, _setValue_) ![](https://img.shields.io/badge/function-blue)
Creates a native checkbox (Blizzard's own `SettingsCheckboxTemplate`, the same widget the settings
panel's own rows use) with an optional text label to its left, matching how the panel's own rows
read - pass an empty string for a row that carries its own label. `getValue`/`setValue` read/write
the checked state.

The template anchors its hover highlight to the checkbox's grandparent, which is the settings list's
own row. Here that is whatever frame the caller happens to nest the checkbox in, so the highlight is
re-anchored to the checkbox and its label.
--]]
local TOGGLE_HOVER_INSET = 4
local TOGGLE_LABEL_GAP = 2
function ns:CreateToggle(parent, label, getValue, setValue)
	ns:ArgCheck(label, 2, 'string')
	ns:ArgCheck(getValue, 3, 'function')
	ns:ArgCheck(setValue, 4, 'function')

	local checkbox = CreateFrame('CheckButton', nil, parent, 'SettingsCheckboxTemplate')
	checkbox:Init(getValue())
	checkbox:RegisterCallback('OnValueChanged', function(_, value)
		setValue(not not value)
	end, checkbox)

	if label ~= '' then
		checkbox.Text = checkbox:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
		checkbox.Text:SetPoint('RIGHT', checkbox, 'LEFT', -TOGGLE_LABEL_GAP, 0)
		checkbox.Text:SetText(label)
	end

	if checkbox.HoverBackground then
		checkbox.HoverBackground:ClearAllPoints()
		ns:SetPoint(checkbox.HoverBackground, 'TOPRIGHT', checkbox, 'TOPRIGHT', TOGGLE_HOVER_INSET, 0)

		if checkbox.Text then
			ns:SetPoint(checkbox.HoverBackground, 'BOTTOMLEFT', checkbox.Text, 'LEFT',
				-TOGGLE_HOVER_INSET, -checkbox:GetHeight() / 2)
		else
			ns:SetPoint(checkbox.HoverBackground, 'BOTTOMLEFT', checkbox, 'BOTTOMLEFT',
				-TOGGLE_HOVER_INSET, 0)
		end
	end

	return checkbox
end

--[[ namespace:CreateSlider(_parent_, _minValue_, _maxValue_, _valueStep_, _getValue_, _setValue_) ![](https://img.shields.io/badge/function-blue)
Creates a native slider with +/- steppers (Blizzard's own `MinimalSliderWithSteppersTemplate`).
`getValue`/`setValue` read/write the numeric value.

The value is shown in an editable box where the template's read-only right-hand label would sit, so
it can be typed as well as dragged. Typed values are clamped to `minValue`/`maxValue`; anything that
is not a number is discarded and the box reverts.
--]]
local SLIDER_INPUT_WIDTH = 50
local SLIDER_INPUT_HEIGHT = 21
local SLIDER_INPUT_Y = 0.5
local SLIDER_INPUT_TEXT_TOP = 1
local SLIDER_INPUT_OFFSET = 25
local SLIDER_INPUT_INSET = 5

function ns:CreateSlider(parent, minValue, maxValue, valueStep, getValue, setValue)
	ns:ArgCheck(minValue, 2, 'number')
	ns:ArgCheck(maxValue, 3, 'number')
	ns:ArgCheck(valueStep, 4, 'number')
	ns:ArgCheck(getValue, 5, 'function')
	ns:ArgCheck(setValue, 6, 'function')

	local slider = CreateFrame('Frame', nil, parent, 'MinimalSliderWithSteppersTemplate')
	slider:Init(getValue(), minValue, maxValue, (maxValue - minValue) / valueStep)

	local input
	local current = getValue()

	local function Commit(text)
		local value = tonumber(text)

		if value then
			slider:SetValue(math.min(maxValue, math.max(minValue, value)))
		end

		input:Refresh()
	end

	input = ns:CreateEditBox(slider, function()
		return tostring(current)
	end, Commit)

	input:SetSize(SLIDER_INPUT_WIDTH, SLIDER_INPUT_HEIGHT)
	input:SetJustifyH('CENTER')
	input:SetTextInsets(0, SLIDER_INPUT_INSET, SLIDER_INPUT_TEXT_TOP, 0)
	input:SetPoint('LEFT', slider.Slider, 'RIGHT', SLIDER_INPUT_OFFSET, SLIDER_INPUT_Y)

	slider:RegisterCallback('OnValueChanged', function(_, value)
		current = value
		input:Refresh()
		setValue(value)
	end, slider)

	return slider
end

--[[ namespace:CreateDropdown(_parent_, _options_, _getValue_, _setValue_[, _initializeItem_]) ![](https://img.shields.io/badge/function-blue)
Creates a native dropdown-with-steppers (Blizzard's own `SettingsDropdownWithButtonsTemplate`, the same
widget `Settings.CreateDropdown` rows use). `options` is an array of `{value = ..., label = ...}` tables.
`getValue`/`setValue` read/write the selected value.

`options` may instead be a function returning that array, which is called every time the menu opens,
for lists that can still grow after the dropdown is built.

`initializeItem`, if given, is called as `initializeItem(button, option)` for each list item, to customize its
appearance (e.g. font, an attached texture - see `namespace:CreateMediaDropdown`). It may optionally
return `width, height` to widen the row beyond its default text-driven size.
--]]
function ns:CreateDropdown(parent, options, getValue, setValue, initializeItem)
	assert(type(options) == 'table' or type(options) == 'function', 'arg2 must be a table or a function')
	ns:ArgCheck(getValue, 3, 'function')
	ns:ArgCheck(setValue, 4, 'function')

	local container = CreateFrame('Frame', nil, parent, 'SettingsDropdownWithButtonsTemplate')
	container.Dropdown:SetWidth(220)

	function container.Enable()
		container:SetEnabled(true)
	end

	function container.Disable()
		container:SetEnabled(false)
	end

	function container.GenerateMenu()
		container.Dropdown:GenerateMenu()
	end

	container.Dropdown:SetupMenu(function(_, rootDescription)
		for _, option in next, (type(options) == 'function' and options() or options) do
			local radio = rootDescription:CreateHighlightRadio(option.label, function()
				return getValue() == option.value
			end, function()
				setValue(option.value)
				container:GenerateMenu()
			end)

			if initializeItem then
				radio:AddInitializer(function(button)
					return initializeItem(button, option)
				end)
			end
		end
	end)
	container:GenerateMenu() -- populate initial selection text

	return container
end

--[[ namespace:CreateMediaDropdown(_parent_, _mediaType_, _getValue_, _setValue_) ![](https://img.shields.io/badge/function-blue)
Creates a `namespace:CreateDropdown` listing every [LibSharedMedia-3.0](https://www.curseforge.com/wow/addons/libsharedmedia-3-0)
item of `mediaType` ('font', 'statusbar' or 'sound'), with each option previewed - rendered in its own font,
showing its own texture, or played when picked.

`getValue`/`setValue` read/write the selected media name.

Usage:
```lua
local dropdown = ns:CreateMediaDropdown(parent, 'font', function()
	return ns.Config.textFontFace
end, function(name)
	ns.Config.textFontFace = name
end)
dropdown:SetPoint('TOPLEFT')
```
--]]
function ns:CreateMediaDropdown(parent, mediaType, getValue, setValue)
	ns:ArgCheck(mediaType, 2, 'string')
	ns:ArgCheck(getValue, 3, 'function')
	ns:ArgCheck(setValue, 4, 'function')
	assert(mediaType == 'font' or mediaType == 'statusbar' or mediaType == 'sound',
		"mediaType must be 'font', 'statusbar' or 'sound'")

	local LSM = LibStub('LibSharedMedia-3.0', true)
	assert(LSM, 'LibSharedMedia-3.0 is required for CreateMediaDropdown')

	local function GetOptions()
		local options = {}
		for _, name in next, LSM:List(mediaType) do
			table.insert(options, { value = name, label = name })
		end

		return options
	end

	local function OnSelect(name)
		setValue(name)

		if mediaType == 'sound' then
			local path = LSM:Fetch('sound', name)
			if path then
				PlaySoundFile(path, 'Master')
			end
		end
	end

	local function ApplyFontPreview(fontString, name)
		local path = name and LSM:Fetch('font', name)
		if not path then
			return
		end

		local _, size, flags = fontString:GetFont()
		local fontObjectName = 'HuddleMediaDropdownFont-' .. name
		local fontObject = _G[fontObjectName] or CreateFont(fontObjectName)
		fontObject:SetFont(path, size, flags)
		fontString:SetFontObject(fontObject)
	end

	local dropdown = ns:CreateDropdown(parent, GetOptions, getValue, OnSelect, function(button, option)
		if mediaType == 'font' then
			ApplyFontPreview(button.Text, option.value)
		elseif mediaType == 'statusbar' then
			local path = LSM:Fetch('statusbar', option.value)
			if not path then
				return
			end

			local textureWidth = 120
			local texture = button:AttachTexture()
			texture:SetPoint('RIGHT', -8, 0)
			texture:SetSize(textureWidth, 14)
			texture:SetTexture(path)

			button.Text:SetPoint('RIGHT', texture, 'LEFT', -6, 0)
			local width = button.Text:GetUnboundedStringWidth() + textureWidth + 40
			return width, button.Text:GetHeight()
		end
	end)

	LSM.RegisterCallback(dropdown, 'LibSharedMedia_Registered', function(_, registeredType)
		if registeredType == mediaType then
			dropdown:GenerateMenu()
		end
	end)

	if mediaType == 'font' then
		local function UpdateSelectedFontPreview()
			ApplyFontPreview(dropdown.Dropdown.Text, getValue())
		end
		dropdown.Dropdown:RegisterCallback('OnUpdate', UpdateSelectedFontPreview)
		UpdateSelectedFontPreview()
	end

	return dropdown
end

--[[ namespace:CreateSettingsHeader(_parent_, _title_) ![](https://img.shields.io/badge/function-blue)
Creates the content header the settings panel draws above a page - a `GameFontHighlightHuge` title,
a Defaults button at the top right and an `Options_HorizontalDivider` along the bottom, at Blizzard's
own offsets. Anchored to the top of `parent`.

The header carries `Title` and `DefaultsButton`. The button starts hidden, since a page without a
defaults handler has nothing to reset.

Usage:
```lua
local header = namespace:CreateSettingsHeader(frame, 'ManiaUF')
header.DefaultsButton:Show()
```
--]]
local HEADER_HEIGHT = 50
local HEADER_TITLE_X, HEADER_TITLE_Y = 7, -22
local HEADER_BUTTON_X, HEADER_BUTTON_Y = -36, -16
local HEADER_BUTTON_WIDTH, HEADER_BUTTON_HEIGHT = 96, 22

function ns:CreateSettingsHeader(parent, title)
	local header = CreateFrame('Frame', nil, parent)
	header:SetPoint('TOPLEFT')
	header:SetPoint('TOPRIGHT')
	header:SetHeight(HEADER_HEIGHT)

	header.Title = header:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightHuge')
	header.Title:SetPoint('TOPLEFT', HEADER_TITLE_X, HEADER_TITLE_Y)
	header.Title:SetJustifyH('LEFT')
	header.Title:SetText(title)

	header.DefaultsButton = CreateFrame('Button', nil, header, 'UIPanelButtonTemplate')
	header.DefaultsButton:SetPoint('TOPRIGHT', HEADER_BUTTON_X, HEADER_BUTTON_Y)
	header.DefaultsButton:SetSize(HEADER_BUTTON_WIDTH, HEADER_BUTTON_HEIGHT)
	header.DefaultsButton:SetText(SETTINGS_DEFAULTS)
	header.DefaultsButton:Hide()

	local divider = header:CreateTexture(nil, 'ARTWORK')
	divider:SetAtlas('Options_HorizontalDivider', TextureKitConstants.UseAtlasSize)
	divider:SetPoint('BOTTOMLEFT')
	divider:SetPoint('BOTTOMRIGHT')

	return header
end

local PANEL_ART_PATH = 'Interface/AddOns/' .. ADDON_NAME .. '/Libs/Huddle/'
local PANEL_ART_FILE = PANEL_ART_PATH .. 'chatbubble-no-background.blp'
local PANEL_ART_FILE_VERTICAL = PANEL_ART_PATH .. 'chatbubblevertical-no-background.blp'

local function SetupPanelPieceVisuals(container, piece, setup, pieceLayout)
	if pieceLayout.file then
		piece:SetTexture(pieceLayout.file)
		piece:SetTexCoord(pieceLayout.left, pieceLayout.right, pieceLayout.top, pieceLayout.bottom)
		ns:SetSize(piece, pieceLayout.width, pieceLayout.height)
	else
		piece:SetColorTexture(1, 1, 1, 1)
	end

	piece:SetHorizTile(false)
	piece:SetVertTile(false)
end

local PANEL_LAYOUT = {
	setupPieceVisualsFunction = SetupPanelPieceVisuals,
	TopLeftCorner = { file = PANEL_ART_FILE, width = 16, height = 16, left = 1 / 128, right = 33 / 128, top = 203 / 256, bottom = 235 / 256 },
	TopRightCorner = { file = PANEL_ART_FILE, width = 16, height = 16, left = 35 / 128, right = 67 / 128, top = 135 / 256, bottom = 167 / 256 },
	BottomLeftCorner = { file = PANEL_ART_FILE, width = 16, height = 15, left = 1 / 128, right = 33 / 128, top = 135 / 256, bottom = 165 / 256 },
	BottomRightCorner = { file = PANEL_ART_FILE, width = 16, height = 15, left = 1 / 128, right = 33 / 128, top = 169 / 256, bottom = 199 / 256 },
	TopEdge = { file = PANEL_ART_FILE, width = 16, height = 16, left = 0 / 128, right = 32 / 128, top = 35 / 256, bottom = 67 / 256 },
	BottomEdge = { file = PANEL_ART_FILE, width = 16, height = 15, left = 0 / 128, right = 32 / 128, top = 1 / 256, bottom = 31 / 256 },
	LeftEdge = { file = PANEL_ART_FILE_VERTICAL, width = 16, height = 16, left = 1 / 128, right = 33 / 128, top = 0, bottom = 1 },
	RightEdge = { file = PANEL_ART_FILE_VERTICAL, width = 16, height = 16, left = 35 / 128, right = 67 / 128, top = 0, bottom = 1 },
	Center = { layer = 'BACKGROUND', x = -12, y = 12, x1 = 12, y1 = -11 },
}

--[[ namespace:CreateSectionHeader(_parent_, _title_) ![](https://img.shields.io/badge/function-blue)
Creates a section header for use inside a settings page - a `GameFontHighlightLarge` caption with an
`Options_HorizontalDivider` along the bottom, one step down from the page title drawn by
`namespace:CreateSettingsHeader`. The caller anchors it.

The header carries `Title` and `Divider`. The caption is centred vertically, so controls belonging to
the section can be anchored to the header's `RIGHT` and line up with it.

Usage:
```lua
local section = namespace:CreateSectionHeader(page, 'Applies to')
section:SetPoint('TOPLEFT')
section:SetPoint('TOPRIGHT')
```
--]]
local SECTION_HEADER_HEIGHT = 32
local SECTION_TITLE_INSET = 12

function ns:CreateSectionHeader(parent, title)
	ns:ArgCheck(title, 2, 'string')

	local header = CreateFrame('Frame', nil, parent)
	ns:SetHeight(header, SECTION_HEADER_HEIGHT)

	header.Title = header:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightLarge')
	ns:SetPoint(header.Title, 'LEFT', header, 'LEFT', SECTION_TITLE_INSET, 0)
	header.Title:SetJustifyH('LEFT')
	header.Title:SetText(title)

	header.Divider = header:CreateTexture(nil, 'ARTWORK')
	header.Divider:SetAtlas('Options_HorizontalDivider')
	ns:SetPoint(header.Divider, 'BOTTOMLEFT', header, 'BOTTOMLEFT', 0, 0)
	ns:SetPoint(header.Divider, 'BOTTOMRIGHT', header, 'BOTTOMRIGHT', 0, 0)
	ns:SetPixelHeight(header.Divider)

	return header
end

--[[ namespace:CreateInset(_parent_) ![](https://img.shields.io/badge/function-blue)
Creates a box for grouping controls inside a settings page, drawn with the same rounded nine-slice
border as the tab strip's pills so the two read as one family. The caller anchors and sizes it.

Mixes in `NineSlicePanelMixin`, so `SetBorderColor` and `SetCenterColor` retint it away from the
muted default. The frame level is left at the parent's, so rows anchored over it draw on top.

Usage:
```lua
local inset = namespace:CreateInset(page)
inset:SetPoint('TOPLEFT')
inset:SetPoint('BOTTOMRIGHT')
```
--]]
local INSET_BORDER = { 0.5, 0.5, 0.55, 0.8 }
local INSET_CENTER = { 0, 0, 0, 0.35 }

function ns:CreateInset(parent)
	local inset = CreateFrame('Frame', nil, parent)
	inset:SetFrameLevel(parent:GetFrameLevel())

	Mixin(inset, NineSlicePanelMixin)
	NineSliceUtil.ApplyLayout(inset, PANEL_LAYOUT)
	inset:SetBorderColor(INSET_BORDER[1], INSET_BORDER[2], INSET_BORDER[3], INSET_BORDER[4])
	inset:SetCenterColor(INSET_CENTER[1], INSET_CENTER[2], INSET_CENTER[3], INSET_CENTER[4])

	return inset
end

--[[ namespace:CreateCategoryButton(_parent_, _label_[, _onClick_]) ![](https://img.shields.io/badge/function-blue)
Creates a row for a vertical category list, drawn the way the settings panel draws its own category
list - the `Options_List_Active`/`Options_List_Hover` atlases behind a `GameFontHighlight`/`GameFontNormal`
label.

`onClick` is called with the button when it is clicked. The button carries `SetSelected(selected)`,
which the caller uses to clear the previously selected row.

Usage:
```lua
local button = namespace:CreateCategoryButton(list, 'Player', function(self)
	ShowPage(self)
end)
button:SetPoint('TOPLEFT')
```
--]]
local CATEGORY_BUTTON_WIDTH = 175
local CATEGORY_BUTTON_HEIGHT = 20
local CATEGORY_LABEL_INSET = 12
local CATEGORY_ART_BLEED = 6

function ns:CreateCategoryButton(parent, label, onClick)
	ns:ArgCheck(label, 2, 'string')

	local button = CreateFrame('Button', nil, parent)
	ns:SetSize(button, CATEGORY_BUTTON_WIDTH, CATEGORY_BUTTON_HEIGHT)

	button.Texture = button:CreateTexture(nil, 'BACKGROUND')
	ns:SetPoint(button.Texture, 'LEFT', button, 'LEFT', -CATEGORY_ART_BLEED, 0)
	ns:SetPoint(button.Texture, 'RIGHT', button, 'RIGHT', CATEGORY_ART_BLEED, 0)
	ns:SetHeight(button.Texture, CATEGORY_BUTTON_HEIGHT)
	ns:DisableSharpening(button.Texture)

	button.Label = button:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
	ns:SetPoint(button.Label, 'LEFT', button, 'LEFT', CATEGORY_LABEL_INSET, 0)
	button.Label:SetJustifyH('LEFT')
	button.Label:SetText(label)

	function button:UpdateState()
		if self.selected then
			self.Label:SetFontObject('GameFontHighlight')
			self.Texture:SetAtlas('Options_List_Active')
			self.Texture:Show()
		elseif self.over then
			self.Label:SetFontObject('GameFontNormal')
			self.Texture:SetAtlas('Options_List_Hover')
			self.Texture:Show()
		else
			self.Label:SetFontObject('GameFontNormal')
			self.Texture:Hide()
		end
	end

	function button:SetSelected(selected)
		self.selected = selected
		self:UpdateState()
	end

	button:SetScript('OnEnter', function(self)
		self.over = true
		self:UpdateState()
	end)

	button:SetScript('OnLeave', function(self)
		self.over = false
		self:UpdateState()
	end)

	if onClick then
		button:SetScript('OnClick', onClick)
	end

	button:UpdateState()

	return button
end

--[[ namespace:CreateEditBox(_parent_, _getValue_, _setValue_) ![](https://img.shields.io/badge/function-blue)
Creates a single-line text field (Blizzard's own `InputBoxTemplate`). `getValue`/`setValue` read/write
the string; `setValue` runs on enter, and escape restores the stored value. The box carries
`Refresh()`, for pushing an externally changed value back into it.

Usage:
```lua
local editBox = namespace:CreateEditBox(parent, function()
	return ns.Config.format
end, function(text)
	ns.Config.format = text
end)
editBox:SetPoint('TOPLEFT')
```
--]]
local EDITBOX_WIDTH = 250
local EDITBOX_HEIGHT = 20

function ns:CreateEditBox(parent, getValue, setValue)
	ns:ArgCheck(getValue, 2, 'function')
	ns:ArgCheck(setValue, 3, 'function')

	local editBox = CreateFrame('EditBox', nil, parent, 'InputBoxTemplate')
	editBox:SetSize(EDITBOX_WIDTH, EDITBOX_HEIGHT)
	editBox:SetAutoFocus(false)
	editBox:SetFontObject('ChatFontNormal')
	editBox:SetText(getValue() or '')

	function editBox:Refresh()
		self:SetText(getValue() or '')
		self:SetCursorPosition(0)
	end

	editBox:SetScript('OnEnterPressed', function(self)
		setValue(self:GetText())
		self:ClearFocus()
	end)

	editBox:SetScript('OnEscapePressed', function(self)
		self:Refresh()
		self:ClearFocus()
	end)

	editBox:SetCursorPosition(0)

	return editBox
end

--[[ namespace:CreateTabSystem(_parent_, _labels_, _onSelect_[, _spacing_]) ![](https://img.shields.io/badge/function-blue)
Creates a horizontal row of tabs using Blizzard's own `MinimalTabTemplate` - the `Options_Tab_*` art
the settings window uses for its Game/AddOns tabs, which matches `namespace:CreateCategoryButton`.
`labels` is an array of strings, one per tab. `onSelect` is called with the tab's index whenever a
tab is chosen.

The returned frame carries `SelectTab(index)` for selecting one from code, which also fires `onSelect`.

Usage:
```lua
local tabs = namespace:CreateTabSystem(frame, {'General', 'Player'}, function(index)
	ShowPage(index)
end)
tabs:SetPoint('TOPLEFT')
tabs:SelectTab(1)
```
--]]
local TAB_HEIGHT = 37
local TAB_TEXT_PADDING = 40
local TAB_SPACING = 2

function ns:CreateTabSystem(parent, labels, onSelect, spacing)
	assert(type(labels) == 'table', 'arg2 must be a table')
	ns:ArgCheck(onSelect, 3, 'function')

	local container = CreateFrame('Frame', nil, parent)
	container:SetHeight(TAB_HEIGHT)

	local tabs = {}
	local width = 0
	local previous, tab

	spacing = spacing or TAB_SPACING

	local function Select(index)
		for position, other in ipairs(tabs) do
			other:SetSelected(position == index)
		end

		onSelect(index)
	end

	for index, label in ipairs(labels) do
		tab = CreateFrame('Button', nil, container, 'MinimalTabTemplate')
		tab.Text:SetText(label)
		tab:SetSize(tab.Text:GetStringWidth() + TAB_TEXT_PADDING, TAB_HEIGHT)
		tab:OnSelected(false)

		if previous then
			tab:SetPoint('BOTTOMLEFT', previous, 'BOTTOMRIGHT', spacing, 0)
			width = width + spacing
		else
			tab:SetPoint('BOTTOMLEFT', container, 'BOTTOMLEFT', 0, 0)
		end

		tab:SetScript('OnClick', function(self)
			Select(index)
		end)

		width = width + tab:GetWidth()
		tabs[index] = tab
		previous = tab
	end

	container:SetWidth(width)

	function container:SelectTab(index)
		Select(index)
	end

	return container
end

--[[ namespace:CreateEditableTabStrip(_parent_, _width_, _onSelect_, _onCreate_, _onRename_, _onDelete_) ![](https://img.shields.io/badge/function-blue)
Creates a wrapping row of pills the user can create, rename and delete. Call
`strip:SetEntries(entries, selectedKey)` any time the underlying list changes; the strip fully
re-renders from what it is given rather than tracking its own state.

Each entry is `{ key, label, locked }`. A locked entry shows a lock icon and has no delete control.
Unlocked entries can be renamed by double-clicking the label and deleted via an (x) control. A
trailing "+ New" pill is always drawn for creating entries.

`onSelect(key)`, `onCreate(label)`, `onRename(key, label)` and `onDelete(key)` fire on the
corresponding user action. Create/rename only fire on a non-empty confirm.

Usage:
```lua
local strip = namespace:CreateEditableTabStrip(frame, 400, function(key)
	ShowElement(key)
end, function(label)
	CreateElement(label)
end, function(key, label)
	RenameElement(key, label)
end, function(key)
	ConfirmDelete(key)
end)
strip:SetPoint('TOPLEFT')
strip:SetEntries(GetEntries(), selectedKey)
```
--]]
local TAB_STRIP_HEIGHT = 32
local TAB_STRIP_ROW_GAP = 6
local TAB_STRIP_SPACING = 6
local TAB_STRIP_TEXT_PADDING = 28
local TAB_STRIP_ICON_SIZE = 14
local TAB_STRIP_DELETE_SIZE = 16
local TAB_STRIP_DELETE_GAP = 6
local TAB_STRIP_DELETE_PADDING = TAB_STRIP_DELETE_SIZE + TAB_STRIP_DELETE_GAP
local TAB_STRIP_DELETE_ALPHA = 0.7
local TAB_STRIP_DELETE_COLOR = { 0.9, 0.32, 0.32 }
local TAB_STRIP_EDITBOX_WIDTH = 160
local TAB_STRIP_EDITBOX_HEIGHT = 20
local TAB_STRIP_EDITBOX_INSET = 8
local TAB_STRIP_EDITBOX_OVERHANG = 5
local TAB_STRIP_EDITBOX_PILL = TAB_STRIP_EDITBOX_WIDTH + 2 * TAB_STRIP_EDITBOX_INSET + TAB_STRIP_EDITBOX_OVERHANG
local TAB_STRIP_LOCK_MARKUP = CreateAtlasMarkup('activities-icon-lock', 17, 22) .. ' '
local TAB_STRIP_NEW_LABEL = CreateAtlasMarkup('uitools-icon-plus', TAB_STRIP_ICON_SIZE, TAB_STRIP_ICON_SIZE, 0, 0, 115, 191, 115) .. ' New'
local TAB_STRIP_CENTER_SHADE = 179 / 255
local TAB_STRIP_CREATE = 'create'

local function ShadeCenter(color)
	local alpha = color[4] or 1
	local shaded = 1 - (1 - alpha) * (1 - TAB_STRIP_CENTER_SHADE)
	local scale = alpha * (1 - TAB_STRIP_CENTER_SHADE) / shaded

	return { color[1] * scale, color[2] * scale, color[3] * scale, shaded }
end

local TAB_STRIP_COLOR_NORMAL = { border = { 0.6, 0.6, 0.65, 0.9 }, center = ShadeCenter({ 0.18, 0.18, 0.2, 0.85 }) }
local TAB_STRIP_COLOR_HOVER = { border = { 0.85, 0.85, 0.9, 1 }, center = ShadeCenter({ 0.28, 0.28, 0.32, 0.9 }) }
local TAB_STRIP_COLOR_SELECTED = { border = { 0.36, 0.52, 0.88, 1 }, center = ShadeCenter({ 0.24, 0.36, 0.62, 1 }) }
local TAB_STRIP_COLOR_NEW = { border = { 0.45, 0.75, 0.45, 0.9 }, center = ShadeCenter({ 0.16, 0.22, 0.16, 0.85 }) }
local TAB_STRIP_COLOR_NEW_HOVER = { border = { 0.55, 0.85, 0.55, 1 }, center = ShadeCenter({ 0.24, 0.32, 0.24, 0.9 }) }

local function TintPill(pill, color)
	pill:SetBorderColor(color.border[1], color.border[2], color.border[3], color.border[4] or 1)
	pill:SetCenterColor(color.center[1], color.center[2], color.center[3], color.center[4] or 1)
end

local function UpdatePillColor(pill)
	local color = TAB_STRIP_COLOR_NORMAL

	if pill.isNew then
		color = pill.over and TAB_STRIP_COLOR_NEW_HOVER or TAB_STRIP_COLOR_NEW
	elseif pill.selected then
		color = TAB_STRIP_COLOR_SELECTED
	elseif pill.over then
		color = TAB_STRIP_COLOR_HOVER
	end

	TintPill(pill, color)
end

local function SetPillText(pill, text, reserved, isEditing)
	pill.Text:SetText(text)

	local width = pill.Text:GetStringWidth() + TAB_STRIP_TEXT_PADDING + reserved

	if isEditing then
		width = math.max(width, TAB_STRIP_EDITBOX_PILL)
	end

	return 2 * math.ceil(width / 2)
end

local function CreateTabStripDeleteButton(pill, onDelete)
	local button = CreateFrame('Button', nil, pill)
	ns:SetSize(button, TAB_STRIP_DELETE_SIZE, TAB_STRIP_DELETE_SIZE)
	ns:SetPoint(button, 'RIGHT', pill, 'RIGHT', -TAB_STRIP_DELETE_GAP, 0)

	local color = TAB_STRIP_DELETE_COLOR
	local icon = button:CreateTexture(nil, 'OVERLAY')
	icon:SetAtlas('uitools-icon-close')
	ns:SetSize(icon, TAB_STRIP_ICON_SIZE, TAB_STRIP_ICON_SIZE)
	ns:SetPoint(icon, 'CENTER', button, 'CENTER', 0, 0)
	icon:SetVertexColor(color[1], color[2], color[3], TAB_STRIP_DELETE_ALPHA)
	button.Icon = icon

	button:SetScript('OnEnter', function()
		icon:SetVertexColor(color[1], color[2], color[3], 1)
	end)

	button:SetScript('OnLeave', function()
		icon:SetVertexColor(color[1], color[2], color[3], TAB_STRIP_DELETE_ALPHA)
	end)

	button:SetScript('OnClick', function()
		onDelete(pill.key)
	end)

	return button
end

function ns:CreateEditableTabStrip(parent, width, onSelect, onCreate, onRename, onDelete)
	ns:ArgCheck(width, 2, 'number')
	ns:ArgCheck(onSelect, 3, 'function')
	ns:ArgCheck(onCreate, 4, 'function')
	ns:ArgCheck(onRename, 5, 'function')
	ns:ArgCheck(onDelete, 6, 'function')

	local container = CreateFrame('Frame', nil, parent)
	container:SetWidth(width)

	local pillPool = {}
	local entries = {}
	local selectedKey
	local editing
	local Layout, StopEditing

	local editBox = CreateFrame('EditBox', nil, container, 'InputBoxTemplate')
	ns:SetHeight(editBox, TAB_STRIP_EDITBOX_HEIGHT)
	editBox:SetAutoFocus(true)
	editBox:SetFontObject('ChatFontNormal')
	editBox:Hide()

	function StopEditing()
		if not editing then
			return
		end

		editing = nil
		editBox:Hide()
		Layout()
	end

	local function CommitEdit()
		local text = editBox:GetText()
		local target = editing

		StopEditing()

		if text == '' then
			return
		end

		if target == TAB_STRIP_CREATE then
			onCreate(text)
		else
			onRename(target, text)
		end
	end

	editBox:SetScript('OnEnterPressed', CommitEdit)
	editBox:SetScript('OnEscapePressed', StopEditing)
	editBox:SetScript('OnEditFocusLost', StopEditing)

	local function StartEditing(target, pill, currentText)
		editBox:ClearAllPoints()
		ns:SetPoint(editBox, 'LEFT', pill, 'LEFT', TAB_STRIP_EDITBOX_INSET + TAB_STRIP_EDITBOX_OVERHANG, 0)
		editBox:SetWidth(pill:GetWidth() - 2 * TAB_STRIP_EDITBOX_INSET - TAB_STRIP_EDITBOX_OVERHANG)
		editBox:SetText(currentText or '')
		editBox:Show()
		editBox:SetFocus()
		editBox:HighlightText()
	end

	local function GetPill(index)
		local pill = pillPool[index]

		if pill then
			return pill
		end

		pill = CreateFrame('Button', nil, container)
		Mixin(pill, NineSlicePanelMixin)
		NineSliceUtil.ApplyLayout(pill, PANEL_LAYOUT)

		pill.Text = pill:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
		ns:SetPoint(pill.Text, 'CENTER', pill, 'CENTER', 0, 0)

		pill:SetScript('OnClick', function()
			if pill.key then
				onSelect(pill.key)
			elseif editing ~= TAB_STRIP_CREATE then
				editing = TAB_STRIP_CREATE
				Layout()
			end
		end)

		pill:SetScript('OnDoubleClick', function()
			if pill.key and not pill.locked and editing ~= pill.key then
				editing = pill.key
				Layout()
			end
		end)

		pill:SetScript('OnEnter', function()
			pill.over = true
			UpdatePillColor(pill)
		end)

		pill:SetScript('OnLeave', function()
			pill.over = false
			UpdatePillColor(pill)
		end)

		pillPool[index] = pill

		return pill
	end

	local function PlacePill(pill, x, row, entryWidth)
		if x > 0 and x + entryWidth > width then
			x, row = 0, row + 1
		end

		ns:SetSize(pill, entryWidth, TAB_STRIP_HEIGHT)
		pill:ClearAllPoints()
		ns:SetPoint(pill, 'TOPLEFT', container, 'TOPLEFT', x, -row * (TAB_STRIP_HEIGHT + TAB_STRIP_ROW_GAP))
		pill:Show()

		return x + entryWidth + TAB_STRIP_SPACING, row
	end

	function Layout()
		local x, row = 0, 0
		local index = 0
		local pill, pillWidth, isEditing

		for _, entry in ipairs(entries) do
			index = index + 1
			pill = GetPill(index)
			pill.key = entry.key
			pill.locked = entry.locked
			pill.isNew = false
			pill.selected = entry.key == selectedKey
			isEditing = editing == entry.key

			pillWidth = SetPillText(pill, (entry.locked and TAB_STRIP_LOCK_MARKUP or '') .. entry.label,
				entry.locked and 0 or TAB_STRIP_DELETE_PADDING, isEditing)

			x, row = PlacePill(pill, x, row, pillWidth)
			UpdatePillColor(pill)

			if entry.locked then
				if pill.DeleteButton then
					pill.DeleteButton:Hide()
				end
			else
				pill.DeleteButton = pill.DeleteButton or CreateTabStripDeleteButton(pill, onDelete)
				pill.DeleteButton:SetShown(not isEditing)
			end

			pill.Text:SetShown(not isEditing)

			if isEditing then
				StartEditing(entry.key, pill, entry.label)
			end
		end

		index = index + 1
		pill = GetPill(index)
		pill.key = nil
		pill.locked = nil
		pill.isNew = true
		pill.selected = false
		isEditing = editing == TAB_STRIP_CREATE

		if pill.DeleteButton then
			pill.DeleteButton:Hide()
		end

		pillWidth = SetPillText(pill, TAB_STRIP_NEW_LABEL, 0, isEditing)
		x, row = PlacePill(pill, x, row, pillWidth)
		UpdatePillColor(pill)

		pill.Text:SetShown(not isEditing)

		if isEditing then
			StartEditing(TAB_STRIP_CREATE, pill)
		end

		for position = index + 1, #pillPool do
			pillPool[position]:Hide()
		end

		container:SetHeight((row + 1) * TAB_STRIP_HEIGHT + row * TAB_STRIP_ROW_GAP)
	end

	function container:SetEntries(newEntries, newSelectedKey)
		entries = newEntries
		selectedKey = newSelectedKey
		Layout()
	end

	return container
end

--[[ namespace:CreateDescription(_parent_, _width_, _text_) ![](https://img.shields.io/badge/function-blue)
Creates a block of wrapping explanatory text for the top of a settings page, sized to `width` and
setting its own height to fit however many lines that takes. Call `description:SetText(text)` to
change it; the height is recomputed.

Usage:
```lua
local description = namespace:CreateDescription(page, 640, 'Only one of these is shown at a time.')
description:SetPoint('TOPLEFT')
```
--]]
local DESCRIPTION_SPACING = 2

function ns:CreateDescription(parent, width, text)
	ns:ArgCheck(width, 2, 'number')
	ns:ArgCheck(text, 3, 'string')

	local container = CreateFrame('Frame', nil, parent)
	container:SetWidth(width)

	local fontString = container:CreateFontString(nil, 'ARTWORK', 'GameFontHighlight')
	ns:SetPoint(fontString, 'TOPLEFT', container, 'TOPLEFT', 0, 0)
	ns:SetWidth(fontString, width)
	fontString:SetJustifyH('LEFT')
	fontString:SetJustifyV('TOP')
	fontString:SetSpacing(DESCRIPTION_SPACING)
	fontString:SetTextColor(GRAY_FONT_COLOR:GetRGB())
	container.Text = fontString

	function container:SetText(value)
		fontString:SetText(value)
		container:SetHeight(fontString:GetStringHeight())
	end

	container:SetText(text)

	return container
end

--[[ namespace:CreateTabContainer(_parent_[, _height_]) ![](https://img.shields.io/badge/function-blue)
Creates the bordered content frame the settings window draws behind its category list and settings
list - the `Options_InnerFrame` atlas, which includes the vertical divider between the two columns.
Attach `namespace:CreateTabSystem` tabs to its top edge and lay the list and content out inside it.

`height` overrides the atlas' own height. The texture is drawn nine-sliced via
`SetTextureSliceMargins`, so the corners and the top/bottom border art keep their proportions at any
height and only the straight middle stretches. Blizzard's own margins are used when the atlas carries
`sliceData`, otherwise `TAB_CONTAINER_MARGIN` is assumed.

The *width* is deliberately not settable. The vertical divider sits in the slice's stretched middle,
so widening or narrowing the frame would move and smear it away from the list column's edge. The
settings panel is 920x724 with this anchored at `TOPLEFT (17, -64)`; matching those horizontal
numbers is what makes the art line up.

Usage:
```lua
local container = namespace:CreateTabContainer(frame, 454)
container:SetPoint('TOPLEFT', 17, -64)
```
--]]
local TAB_CONTAINER_ATLAS = 'Options_InnerFrame'
local TAB_CONTAINER_MARGIN = 24

function ns:CreateTabContainer(parent, height)
	local container = CreateFrame('Frame', nil, parent)

	local texture = container:CreateTexture(nil, 'OVERLAY', nil, 2)
	texture:SetAtlas(TAB_CONTAINER_ATLAS, TextureKitConstants.UseAtlasSize)
	texture:SetPoint('TOPLEFT')

	local info = C_Texture.GetAtlasInfo(TAB_CONTAINER_ATLAS)
	local slice = info and info.sliceData

	if slice then
		texture:SetTextureSliceMargins(slice.marginLeft, slice.marginTop, slice.marginRight,
			slice.marginBottom)
		texture:SetTextureSliceMode(slice.sliceMode)
	else
		texture:SetTextureSliceMargins(TAB_CONTAINER_MARGIN, TAB_CONTAINER_MARGIN,
			TAB_CONTAINER_MARGIN, TAB_CONTAINER_MARGIN)
	end

	if height then
		texture:SetHeight(height)
	end

	container.Frame = texture
	container:SetSize(texture:GetWidth(), texture:GetHeight())

	return container
end

--[[ namespace:CreateButton(_parent_, _text_, _onClick_) ![](https://img.shields.io/badge/function-blue)
Creates a standard `UIPanelButtonTemplate` button. `onClick` is called with the button when clicked.

Usage:
```lua
local button = namespace:CreateButton(parent, 'Reset', function()
	ns:ResetThings()
end)
button:SetPoint('TOPLEFT')
```
--]]
local BUTTON_WIDTH = 96
local BUTTON_HEIGHT = 22

function ns:CreateButton(parent, text, onClick)
	ns:ArgCheck(text, 2, 'string')
	ns:ArgCheck(onClick, 3, 'function')

	local button = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
	button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
	button:SetText(text)
	button:SetScript('OnClick', onClick)

	return button
end
