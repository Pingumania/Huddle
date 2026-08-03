local addonName, A = ...

local RELOAD_ICON = CreateAtlasMarkup('Recurringavailablequesticon', 16, 16)
local RELOAD_NOTE = 'This only takes effect after a reload.'

local reloadPopup = addonName .. '_HUDDLE_RELOAD_REQUIRED'
local reloadRequired = {}
local reloadAcknowledged

StaticPopupDialogs[reloadPopup] = {
	text = RELOAD_NOTE .. '|n|nUse /reload when you are done changing settings.',
	button1 = OKAY,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function()
		reloadAcknowledged = true
	end,
}

local defaultsPopup = addonName .. '_HUDDLE_APPLY_DEFAULTS'

StaticPopupDialogs[defaultsPopup] = {
	text = 'Reset the settings on this page to their defaults?',
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
	A:TriggerOptionCallback(setting.variableKey, value)

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

		local header = CreateFrame('Frame', nil, frame)
		header:SetPoint('TOPLEFT')
		header:SetPoint('TOPRIGHT')
		header:SetHeight(50)
		frame.Header = header

		local title = header:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightHuge')
		title:SetPoint('TOPLEFT', 7, -22)
		title:SetJustifyH('LEFT')
		title:SetText(name or addonName)
		header.Title = title

		local defaults = CreateFrame('Button', nil, header, 'UIPanelButtonTemplate')
		defaults:SetPoint('TOPRIGHT', -36, -16)
		defaults:SetSize(96, 22)
		defaults:SetText(SETTINGS_DEFAULTS)
		defaults:Hide()
		header.DefaultsButton = defaults

		local divider = header:CreateTexture(nil, 'ARTWORK')
		divider:SetPoint('TOP', 0, -50)
		divider:SetAtlas('Options_HorizontalDivider', true)

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

local PREVIEW_HEIGHT = 195

local function createSetting(category, savedvariable, info)
	A:ArgCheck(info.key, 3, 'string')
	A:ArgCheck(info.title, 3, 'string')
	A:ArgCheck(info.type, 3, 'string')
	assert(info.default ~= nil, 'default must be set')

	A.optionVariables = A.optionVariables or {}
	A.optionVariables[info.key] = savedvariable

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

	return setting, title, tooltip
end

local function registerSetting(category, savedvariable, info)
	local setting, _, tooltip = createSetting(category, savedvariable, info)

	local initializer
	if info.type == 'toggle' then
		initializer = Settings.CreateCheckbox(category, setting, tooltip)
	elseif info.type == 'slider' then
		A:ArgCheck(info.minValue, 3, 'number')
		A:ArgCheck(info.maxValue, 3, 'number')

		local options = Settings.CreateSliderOptions(info.minValue, info.maxValue, info.valueStep or 1)
		options:SetLabelFormatter(SLIDER_VALUE_LABEL, resolveSliderFormatter(info.valueFormat))

		initializer = Settings.CreateSlider(category, setting, options, tooltip)
	elseif info.type == 'menu' then
		A:ArgCheck(info.options, 3, 'table')
		local options = function()
			local container = Settings.CreateControlTextContainer()
			for _, option in next, info.options do
				container:Add(option.value, option.label)
			end
			return container:GetData()
		end

		initializer = Settings.CreateDropdown(category, setting, options, tooltip)
	elseif info.type == 'color' then
		assert(#info.default == 8, 'color default must be an 8-character AARRGGBB hex string')

		if not A:IsClassicEra() then
			initializer = Settings.CreateColorSwatch(category, setting, tooltip)
		end
	else
		error('type is invalid') -- TODO: make this prettier
		return
	end

	setting:SetValueChangedCallback(onSettingChanged)
	A:TriggerOptionCallback(info.key, setting:GetValue())

	return initializer
end

local CANVAS_PAD_TOP = 10
local CANVAS_PAD_LEFT = 25
local CANVAS_SPACING = 9

local CANVAS_COLUMN_GAP = 20
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

-- gap between one toggle's label and the next toggle on a shared row
local TOGGLES_GAP = 24

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

local function createControlInitializer(setting, info, tooltip)
	if info.type == 'toggle' then
		return Settings.CreateCheckboxInitializer(setting, nil, tooltip)
	elseif info.type == 'toggleWithButton' then
		A:ArgCheck(info.buttonText, 3, 'string')
		A:ArgCheck(info.onClick, 3, 'function')

		local clickRequiresSet = false
		return CreateSettingsCheckboxWithButtonInitializer(setting, info.buttonText, info.onClick, nil,
			clickRequiresSet, tooltip)
	elseif info.type == 'slider' then
		A:ArgCheck(info.minValue, 3, 'number')
		A:ArgCheck(info.maxValue, 3, 'number')

		local options = Settings.CreateSliderOptions(info.minValue, info.maxValue, info.valueStep or 1)
		options:SetLabelFormatter(SLIDER_VALUE_LABEL, resolveSliderFormatter(info.valueFormat))

		return Settings.CreateSliderInitializer(setting, options, tooltip)
	elseif info.type == 'menu' then
		A:ArgCheck(info.options, 3, 'table')

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

local function createCanvasSection(parent, info, relayout)
	local data = {name = info.title, expanded = not not info.expanded}
	local initializer = Settings.CreateElementInitializer('SettingsExpandableSectionTemplate', data)
	local row = CreateFrame('EventFrame', nil, parent, 'SettingsExpandableSectionTemplate')

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

	local function addRow(info, section)
		local row, sectionState

		if info.type == 'header' then
			row = CreateFrame('Frame', nil, content, 'SettingsListSectionHeaderTemplate')
			row:SetHeight(templateHeight('SettingsListSectionHeaderTemplate'))
			initCanvasRow(row, CreateSettingsListSectionHeaderInitializer(info.title, info.tooltip))
		elseif info.type == 'description' then
			A:ArgCheck(info.title, 3, 'string')

			row = createCanvasDescription(content, info)
		elseif info.type == 'preview' then
			A:ArgCheck(info.createPreview, 3, 'function')

			row = createCanvasPreview(content, info)

			if info.onDefaults then
				customDefaults[#customDefaults + 1] = info.onDefaults
			end
		elseif info.type == 'section' then
			A:ArgCheck(info.title, 3, 'string')
			assert(info.createContent or info.settings, 'a section needs either createContent or settings')

			row, sectionState = createCanvasSection(content, info, onSectionToggled)

			if info.onDefaults then
				customDefaults[#customDefaults + 1] = info.onDefaults
			end
		elseif info.type == 'custom' then
			A:ArgCheck(info.title, 3, 'string')
			A:ArgCheck(info.createControl, 3, 'function')

			local link = resolveLink(info)
			local initializer = Settings.CreateElementInitializer('SettingsListElementTemplate',
				{name = info.title, tooltip = info.tooltip})

			if link then
				initializer:AddModifyPredicate(function()
					return isLinkEnabled(link)
				end)

				if link.indent then
					initializer:Indent()
				end
			end

			row = CreateFrame('Frame', nil, content, 'SettingsListElementTemplate')
			row:SetHeight(templateHeight('SettingsCheckboxControlTemplate'))

			row.cbrHandles = Settings.CreateCallbackHandleContainer()

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
			A:ArgCheck(info.settings, 3, 'table')

			local link = resolveLink(info)
			local initializer = Settings.CreateElementInitializer('SettingsListElementTemplate',
				{name = info.title or '', tooltip = info.tooltip})

			if link then
				initializer:AddModifyPredicate(function()
					return isLinkEnabled(link)
				end)

				if link.indent then
					initializer:Indent()
				end
			end

			row = CreateFrame('Frame', nil, content, 'SettingsListElementTemplate')
			row:SetHeight(templateHeight('SettingsCheckboxControlTemplate'))
			row.cbrHandles = Settings.CreateCallbackHandleContainer()

			initCanvasRow(row, initializer)

			row.huddleToggles = {}

			local previous
			for _, entry in ipairs(info.settings) do
				local setting = createSetting(category, savedvariable, entry)
				links[entry.key] = link
				settingsByKey[entry.key] = setting

				local checkbox = CreateFrame('CheckButton', nil, row, 'SettingsCheckboxTemplate')
				checkbox:Init(setting:GetValue())
				checkbox:RegisterCallback('OnValueChanged', function(_, value)
					setting:SetValue(not not value)
				end, checkbox)

				checkbox.Text = checkbox:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
				checkbox.Text:SetPoint('LEFT', checkbox, 'RIGHT', 2, 0)
				checkbox.Text:SetText(entry.title)

				if previous then
					checkbox:SetPoint('LEFT', previous.Text, 'RIGHT', TOGGLES_GAP, 0)
				else
					checkbox:SetPoint('LEFT', row, 'CENTER',
						CANVAS_CONTROL_ANCHORS.toggle.x + CANVAS_CONTROL_SHIFT, CANVAS_CONTROL_ANCHORS.toggle.y)
				end

				defaults[#defaults + 1] = setting

				setting:SetValueChangedCallback(function(changed, value)
					onSettingChanged(changed, value)
					checkbox:SetValue(value)
					evaluate()
				end)

				A:TriggerOptionCallback(entry.key, setting:GetValue())

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
		elseif info.type == 'color' and A:IsClassicEra() then
		else
			local setting, _, tooltip = createSetting(category, savedvariable, info)
			local link = resolveLink(info)
			links[info.key] = link
			settingsByKey[info.key] = setting

			local initializer = createControlInitializer(setting, info, tooltip)

			if link then
				initializer:AddModifyPredicate(function()
					return isLinkEnabled(link)
				end)

				if link.indent then
					initializer:Indent()
				end
			end

			row = CreateFrame('Frame', nil, content, CANVAS_TEMPLATES[info.type])
			row:SetHeight(templateHeight(CANVAS_TEMPLATES[info.type]))
			initCanvasRow(row, initializer)
			controls[#controls + 1] = row

			if info.buttonWidth then
				row.Button:SetWidth(info.buttonWidth)
			end

			shiftCanvasControl(row, info)

			defaults[#defaults + 1] = setting

			setting:SetValueChangedCallback(function(changed, value)
				onSettingChanged(changed, value)
				evaluate()
			end)

			A:TriggerOptionCallback(info.key, setting:GetValue())
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

local function isChainEnabled(links, initializers, key)
	local link = links[key]
	while link do
		if link.gated then
			local setting = initializers[link.key]:GetSetting()
			if not (setting and setting:GetValue()) then
				return false
			end
		end
		link = links[link.key]
	end
	return true
end

local function registerSettingsList(category, layout, savedvariable, settings)
	local keys = {}
	local initializers = {}
	local links = {}
	for index, setting in next, settings do
		if setting.type == 'header' then
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(setting.title, setting.tooltip))
		else
			local initializer = registerSetting(category, savedvariable, setting)
			keys[setting.key] = index
			initializers[setting.key] = initializer

			if setting.requires then
				links[setting.key] = {key = setting.requires, gated = true, indent = true}
			elseif setting.gatedBy then
				links[setting.key] = {key = setting.gatedBy, gated = true}
			elseif setting.parent then
				links[setting.key] = {key = setting.parent, indent = true}
			end
		end
	end
	return keys, initializers, links
end

local function applyDependencies(settings, keys, initializers, links)
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
			return isChainEnabled(links, initializers, key)
		end

		local ancestor = link
		if link.indent then
			initializer:SetParentInitializer(initializers[link.key], predicate)
			ancestor = links[link.key]
		else
			initializer:AddModifyPredicate(predicate)
		end

		while ancestor do
			local setting = initializers[ancestor.key]:GetSetting()
			if setting then
				initializer:AddEvaluateStateCVar(setting:GetVariable())
			end

			ancestor = links[ancestor.key]
		end
	end
end

local settingsCategoryID
local function registerSettings(savedvariable, settings)
	local categoryName = C_AddOns.GetAddOnMetadata(addonName, 'Title')

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
		local keys, initializers, links = registerSettingsList(category, layout, savedvariable, settings)
		applyDependencies(settings, keys, initializers, links)
	end

	if A.settingsChildren then
		for _, info in ipairs(A.settingsChildren) do
			if info.settings then
				if needsCanvas(info.settings) then
					local childFrame, childCanvas = createCanvas(info.name)
					local child = Settings.RegisterCanvasLayoutSubcategory(category, childFrame, info.name)
					renderCanvasSettings(childCanvas, child, savedvariable, info.settings)
				else
					local child, childLayout = Settings.RegisterVerticalLayoutSubcategory(category, info.name)
					local childKeys, childInitializers, childLinks = registerSettingsList(child, childLayout, savedvariable, info.settings)
					applyDependencies(info.settings, childKeys, childInitializers, childLinks)
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
A:RegisterSettings('MyAddOnDB', {
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
            return A:CreateToggle(rowFrame, '', getValue, setValue) -- any frame; anchored to the row's right side
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
function A:RegisterSettings(savedvariable, settings)
	A:ArgCheck(savedvariable, 1, 'string')
	A:ArgCheck(settings, 2, 'table')

	if not self.settingsChildren then
		self.settingsChildren = {}
	end

	local _, isReady = C_AddOns.IsAddOnLoaded(addonName)
	if isReady then
		registerSettings(savedvariable, settings)
	else
		A:RegisterEvent('ADDON_LOADED', function(_, name)
			if name == addonName then
				registerSettings(savedvariable, settings)
				return true -- unregister
			end
		end)
	end
end

--[[ namespace:RegisterSubSettings(_name_, _settings_) ![](https://img.shields.io/badge/function-blue)
Registers a set of `settings` as a sub-category. `name` must be unique.
The savedvariables will be stored under the main savedvariables in a table entry named after `name`.

The `settings` are identical to that of `namespace:RegisterSettings`.
--]]
function A:RegisterSubSettings(name, settings)
	A:ArgCheck(name, 1, 'string')
	A:ArgCheck(settings, 2, 'table')
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
function A:RegisterSubSettingsCanvas(name, callback)
	A:ArgCheck(name, 1, 'string')
	A:ArgCheck(callback, 2, 'function')
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
function A:OpenSettings()
	assert(not not settingsCategoryID, 'must register settings first')
	if InCombatLockdown() then
		A:Print("Can't open settings this way in combat")
	else
		Settings.OpenToCategory(settingsCategoryID)
	end
end

--[[ namespace:RegisterSettingsSlash(_..._) ![](https://img.shields.io/badge/function-blue)
Wrapper for `namespace:RegisterSlash(...)`, except the callback is provided and will open the settings panel for this addon.
--]]
function A:RegisterSettingsSlash(...)
	local data = {...}
	table.insert(data, function()
		A:OpenSettings()
	end)

	A:RegisterSlash(unpack(data))
end

--[[ namespace:GetOption(_key_) ![](https://img.shields.io/badge/function-blue)
Returns the value for the given option `key`.
--]]
function A:GetOption(key)
	A:ArgCheck(key, 1, 'string')
	assert(A:AreOptionsLoaded(key), "options aren't loaded")
	local savedvariable = self.optionVariables[key]
	assert(_G[savedvariable][key] ~= nil, "key doesn't exist")
	return _G[savedvariable][key]
end

--[[ namespace:SetOption(_key_, _value_) ![](https://img.shields.io/badge/function-blue)
Sets a new `value` to the given options `key`.
--]]
function A:SetOption(key, value)
	A:ArgCheck(key, 1, 'string')
	assert(A:AreOptionsLoaded(key), "options aren't loaded")
	local savedvariable = self.optionVariables[key]
	assert(_G[savedvariable][key] ~= nil, "key doesn't exist")

	_G[savedvariable][key] = value -- this circumvents the setting system, bad?
	A:TriggerOptionCallback(key, value)
end

--[[ namespace:AreOptionsLoaded([_key_]) ![](https://img.shields.io/badge/function-blue)
Checks to see if the savedvariables has been loaded in the game.
If `key` is given, checks specifically for the savedvariable backing that option key.
--]]
function A:AreOptionsLoaded(key)
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
function A:RegisterOptionCallback(key, callback)
	A:ArgCheck(key, 1, 'string')
	A:ArgCheck(callback, 2, 'function')

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
function A:TriggerOptionCallback(key, value)
	A:ArgCheck(key, 1, 'string')

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
			A:SetOption(setting.key, CreateColor(r, g, b, a):GenerateHexColor())
		else
			A:SetOption(setting.key, CreateColor(r, g, b):GenerateHexColorNoAlpha())
		end
	end
	local function colorPickerReset(setting, previousColor)
		if #setting.default == 8 then
			A:SetOption(setting.key, CreateColorFromHexString(previousColor):GenerateHexColor())
		else
			A:SetOption(setting.key, CreateColorFromRGBHexString(previousColor):GenerateHexColorNoAlpha())
		end
	end

	local function menuGetter(setting, value)
		return A:GetOption(setting.key) == value
	end
	local function menuSetter(setting, value)
		A:SetOption(setting.key, value)
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

		A.optionVariables = A.optionVariables or {}
		for _, setting in next, settings do
			if _G[savedvariable][setting.key] == nil then
				_G[savedvariable][setting.key] = setting.default
			end
			A.optionVariables[setting.key] = savedvariable
		end

		-- TODO: menus also has "new feature" flags/textures, see if we can hook into that

		Menu.ModifyMenu('MENU_WORLD_MAP_TRACKING', function(_, root)
			root:CreateDivider()
			root:CreateTitle((addonName:gsub('(%l)(%u)', '%1 %2')) .. HEADER_COLON)

			for _, setting in next, settings do
				local element
				if setting.type == 'toggle' then
					element = root:CreateCheckbox(setting.title, function()
						return A:GetOption(setting.key)
					end, function()
						A:SetOption(setting.key, not A:GetOption(setting.key))
					end)
				elseif setting.type == 'slider' then
					element = createSlider(root, setting.title, function()
						return A:GetOption(setting.key)
					end, function(_, value)
						A:SetOption(setting.key, value)
					end, setting.minValue, setting.maxValue, setting.valueStep or 1, resolveSliderFormatter(setting.valueFormat))
				elseif setting.type == 'color' then
					local value = A:GetOption(setting.key)
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
	function A:RegisterMapSettings(savedvariable, settings)
		A:ArgCheck(savedvariable, 1, 'string')
		A:ArgCheck(settings, 2, 'table')

		local _, isReady = C_AddOns.IsAddOnLoaded(addonName)
		if isReady then
			registerMapSettings(savedvariable, settings)
		else
			A:RegisterEvent('ADDON_LOADED', function(_, name)
				if name == addonName then
					registerMapSettings(savedvariable, settings)
					return true -- unregister
				end
			end)
		end
	end
end

--[[ namespace:CreateToggle(_parent_, _label_, _getValue_, _setValue_) ![](https://img.shields.io/badge/function-blue)
Creates a native checkbox (Blizzard's own `SettingsCheckboxTemplate`, the same widget the settings
panel's own rows use) with an optional text label to its left, matching how the panel's own rows
read - pass an empty string for a row that carries its own label. `getValue`/`setValue` read/write
the checked state.
--]]
function A:CreateToggle(parent, label, getValue, setValue)
	A:ArgCheck(label, 2, 'string')
	A:ArgCheck(getValue, 3, 'function')
	A:ArgCheck(setValue, 4, 'function')

	local checkbox = CreateFrame('CheckButton', nil, parent, 'SettingsCheckboxTemplate')
	checkbox:Init(getValue())
	checkbox:RegisterCallback('OnValueChanged', function(_, value)
		setValue(not not value)
	end, checkbox)

	if label ~= '' then
		checkbox.Text = checkbox:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
		checkbox.Text:SetPoint('RIGHT', checkbox, 'LEFT', -2, 0)
		checkbox.Text:SetText(label)
	end

	return checkbox
end

--[[ namespace:CreateSlider(_parent_, _minValue_, _maxValue_, _valueStep_, _getValue_, _setValue_) ![](https://img.shields.io/badge/function-blue)
Creates a native slider with +/- steppers (Blizzard's own `MinimalSliderWithSteppersTemplate`).
`getValue`/`setValue` read/write the numeric value.
--]]
function A:CreateSlider(parent, minValue, maxValue, valueStep, getValue, setValue)
	A:ArgCheck(minValue, 2, 'number')
	A:ArgCheck(maxValue, 3, 'number')
	A:ArgCheck(valueStep, 4, 'number')
	A:ArgCheck(getValue, 5, 'function')
	A:ArgCheck(setValue, 6, 'function')

	local slider = CreateFrame('Frame', nil, parent, 'MinimalSliderWithSteppersTemplate')
	slider:Init(getValue(), minValue, maxValue, (maxValue - minValue) / valueStep, {
		[SLIDER_VALUE_LABEL] = defaultSliderFormatter,
	})
	slider:RegisterCallback('OnValueChanged', function(_, value)
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
appearance (e.g. font, an attached texture — see `namespace:CreateMediaDropdown`). It may optionally
return `width, height` to widen the row beyond its default text-driven size.
--]]
function A:CreateDropdown(parent, options, getValue, setValue, initializeItem)
	assert(type(options) == 'table' or type(options) == 'function', 'arg2 must be a table or a function')
	A:ArgCheck(getValue, 3, 'function')
	A:ArgCheck(setValue, 4, 'function')

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
item of `mediaType` ('font', 'statusbar' or 'sound'), with each option previewed — rendered in its own font,
showing its own texture, or played when picked.

`getValue`/`setValue` read/write the selected media name.

Usage:
```lua
local dropdown = A:CreateMediaDropdown(parent, 'font', function()
	return A.Config.textFontFace
end, function(name)
	A.Config.textFontFace = name
end)
dropdown:SetPoint('TOPLEFT')
```
--]]
function A:CreateMediaDropdown(parent, mediaType, getValue, setValue)
	A:ArgCheck(mediaType, 2, 'string')
	A:ArgCheck(getValue, 3, 'function')
	A:ArgCheck(setValue, 4, 'function')
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

	local dropdown = A:CreateDropdown(parent, GetOptions, getValue, OnSelect, function(button, option)
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

	if mediaType == 'font' then
		local function UpdateSelectedFontPreview()
			ApplyFontPreview(dropdown.Dropdown.Text, getValue())
		end
		dropdown.Dropdown:RegisterCallback('OnUpdate', UpdateSelectedFontPreview)
		UpdateSelectedFontPreview()
	end

	return dropdown
end
