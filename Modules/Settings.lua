local addonName, A = ...

-- the recurring quest icon, a pair of arrows in a circle; Blizzard draws it at 16
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
	-- deliberately does not reload, the player may still be part-way through the panel
	OnAccept = function()
		reloadAcknowledged = true
	end,
}

-- scoped to the panel being shown, unlike Blizzard's GAME_SETTINGS_APPLY_DEFAULTS
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
		button:SetScript('OnClick', callback)
	end

	function createCanvas(name)
		local frame = CreateFrame('Frame')

		-- replicate header from SettingsListTemplate
		local header = CreateFrame('Frame', nil, frame)
		header:SetPoint('TOPLEFT')
		header:SetPoint('TOPRIGHT')
		header:SetHeight(50)
		frame.Header = header

		local title = header:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightHuge')
		title:SetPoint('TOPLEFT', 7, -22)
		title:SetJustifyH('LEFT')
		title:SetText(name and string.format('%s - %s', addonName, name) or addonName)
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

		-- exposed container the addon can use
		local canvas = Mixin(CreateFrame('Frame', nil, frame), canvasMixin)
		canvas:SetPoint('BOTTOMLEFT', 0, 5)
		canvas:SetPoint('BOTTOMRIGHT', -12, 5)
		canvas:SetPoint('TOP', 0, -56)

		return frame, canvas
	end
end

-- the slider's value label. An enum namespaced on the mixin table rather than a method on it, and
-- the only name it has - SetLabelFormatter takes nothing else, and Blizzard's own settings
-- definitions and implementation readme both spell it this way
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

-- matches the header height baked into SettingsExpandableSectionTemplate
local SECTION_HEADER_HEIGHT = 30
local SECTION_BOTTOM_PADDING = 10

-- matches NamePlatePreviewTemplate, which is the widest the settings list gets
local PREVIEW_HEIGHT = 195

local function createSetting(category, savedvariable, info)
	A:ArgCheck(info.key, 3, 'string')
	A:ArgCheck(info.title, 3, 'string')
	A:ArgCheck(info.type, 3, 'string')
	assert(info.default ~= nil, 'default must be set')

	A.optionVariables = A.optionVariables or {}
	A.optionVariables[info.key] = savedvariable

	-- marked up rather than drawn, so nothing of ours has to touch the pooled row frames
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

--[[
	Custom rows are drawn on a canvas sub-panel rather than in Blizzard's settings list.

	The list only accepts initializers built inside its secure attribute delegate
	(`Settings.CreateElementInitializer` and friends), which binds all behavior to a template mixin
	and rejects functions passed through its data table. An initializer built in addon code is
	tainted, and since `SettingsListMixin`'s extent calculator reads it on every update, that taint
	reaches the rows Blizzard pools for its own panels and eventually kills an unrelated prereq
	check with ADDON_ACTION_FORBIDDEN.

	A canvas is a single frame handed to Blizzard and never touched again, so everything inside it
	belongs to us. The rows are still Blizzard's own control templates driven by initializers from
	`Settings.Create*Initializer`, so they look and behave exactly like a row in Blizzard's panels -
	they are just created directly instead of being pulled from the settings list's frame pools.
]]

-- the settings list's own padding, so a canvas panel lines up with a list one
local CANVAS_PAD_TOP = 10
local CANVAS_PAD_LEFT = 25
local CANVAS_SPACING = 9

-- where every Blizzard control row puts its widget
local CANVAS_CONTROL_X = -48
local CANVAS_CONTROL_Y = 3

local CANVAS_TEMPLATES = {
	toggle = 'SettingsCheckboxControlTemplate',
	slider = 'SettingsSliderControlTemplate',
	menu = 'SettingsDropdownControlTemplate',
	color = 'SettingsColorSwatchControlTemplate',
}

local CANVAS_TYPES = {custom = true, preview = true, section = true}

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

-- Blizzard's row mixins read their initializer back off the frame, which the settings list
-- normally supplies as an accessor. These rows are not in a list, so hand it over directly.
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

	local body = info.createContent(row)
	body:SetParent(row)
	body:ClearAllPoints()
	body:SetPoint('TOPLEFT', 0, -SECTION_HEADER_HEIGHT)
	body:SetPoint('TOPRIGHT', 0, -SECTION_HEADER_HEIGHT)

	-- the template's mixin leaves all three of these to whoever implements a section, the same way
	-- SettingsKeybindingSectionMixin has to swap its own atlas
	function row:CalculateHeight()
		if not data.expanded then
			return SECTION_HEADER_HEIGHT
		end

		return SECTION_HEADER_HEIGHT + body:GetHeight() + SECTION_BOTTOM_PADDING
	end

	function row:OnExpandedChanged(expanded)
		self.Button.Right:SetAtlas(expanded and 'Options_ListExpand_Right_Expanded' or 'Options_ListExpand_Right',
			TextureKitConstants.UseAtlasSize)

		body:SetShown(expanded)
		relayout()
	end

	initCanvasRow(row, initializer)
	row:SetHeight(row:CalculateHeight())
	row:OnExpandedChanged(data.expanded)

	return row
end

-- the bordered box Blizzard uses for the nameplate preview, without its contents
local function createCanvasPreview(parent, info)
	local row = CreateFrame('Frame', nil, parent)
	row:SetHeight(info.height or PREVIEW_HEIGHT)

	local border = row:CreateTexture(nil, 'BACKGROUND')
	border:SetAtlas('options_frame_child')
	border:SetPoint('TOPLEFT', 20, 0)
	border:SetPoint('BOTTOMRIGHT', -20, 0)

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
	scroll:SetPoint('TOPLEFT', 0, -CANVAS_PAD_TOP)
	scroll:SetPoint('BOTTOMRIGHT', -22, 0)
	scroll:EnableMouseWheel(true)

	local scrollBar = CreateFrame('EventFrame', nil, canvas, 'MinimalScrollBar')
	scrollBar:SetPoint('TOPLEFT', scroll, 'TOPRIGHT', 8, 0)
	scrollBar:SetPoint('BOTTOMLEFT', scroll, 'BOTTOMRIGHT', 8, 0)

	local content = CreateFrame('Frame', nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	scroll:SetScript('OnSizeChanged', function(_, width)
		content:SetWidth(width)
	end)

	ScrollUtil.InitScrollFrameWithScrollBar(scroll, scrollBar)

	local order = {}
	local controls = {}
	local settingsByKey = {}
	local links = {}

	local function relayout()
		local offset = 0
		for _, row in ipairs(order) do
			row:ClearAllPoints()
			row:SetPoint('TOPLEFT', CANVAS_PAD_LEFT, -offset)
			row:SetPoint('TOPRIGHT', 0, -offset)
			offset = offset + row:GetHeight() + CANVAS_SPACING
		end

		content:SetHeight(math.max(offset, 1))
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
			row:EvaluateState()
		end
	end

	local defaults = {}

	for _, info in ipairs(settings) do
		local row

		if info.type == 'header' then
			row = CreateFrame('Frame', nil, content, 'SettingsListSectionHeaderTemplate')
			row:SetHeight(templateHeight('SettingsListSectionHeaderTemplate'))
			initCanvasRow(row, CreateSettingsListSectionHeaderInitializer(info.title, info.tooltip))
		elseif info.type == 'preview' then
			A:ArgCheck(info.createPreview, 3, 'function')

			row = createCanvasPreview(content, info)
		elseif info.type == 'section' then
			A:ArgCheck(info.title, 3, 'string')
			A:ArgCheck(info.createContent, 3, 'function')

			row = createCanvasSection(content, info, relayout)
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

			-- Blizzard only ever inherits this template, never instantiates it, so it declares no
			-- OnLoad and the concrete row templates each declare their own. That handler's entire
			-- body is the line below, which Init then asserts on.
			row.cbrHandles = Settings.CreateCallbackHandleContainer()

			-- SettingsListElementMixin has no EvaluateState of its own beyond visibility, so the
			-- greying is done here rather than by the row
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
			row.customControl:SetPoint('LEFT', row, 'CENTER', CANVAS_CONTROL_X, CANVAS_CONTROL_Y)

			-- Blizzard's rows hand their control the row's own tooltip, and a settings widget with
			-- none still opens an empty one on mouseover
			if row.customControl.SetTooltipFunc then
				row.customControl:SetTooltipFunc(GenerateClosure(Settings.InitTooltip, info.title, info.tooltip))
			end
			controls[#controls + 1] = row
		elseif info.type == 'color' and A:IsClassicEra() then
			-- no colour swatch control exists there
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

			defaults[#defaults + 1] = setting

			setting:SetValueChangedCallback(function(changed, value)
				onSettingChanged(changed, value)
				evaluate()
			end)

			A:TriggerOptionCallback(info.key, setting:GetValue())
		end

		if row then
			order[#order + 1] = row
		end
	end

	if #defaults > 0 then
		local function applyDefaults()
			for _, setting in ipairs(defaults) do
				setting:SetValue(setting:GetDefaultValue())
			end

			evaluate()
		end

		canvas:SetDefaultsHandler(function()
			StaticPopup_Show(defaultsPopup, nil, nil, applyDefaults)
		end)
	end

	relayout()
	evaluate()
end

-- sub-categories are kept in an array rather than keyed by name, so they appear in the order they
-- were registered instead of whatever order the hash happens to iterate in
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

		-- the chain is walked on every evaluation, so a cycle would hang the client
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

		-- only the immediate parent is consulted natively, so walk the whole chain instead,
		-- otherwise a setting nested below a disabled ancestor stays enabled
		local predicate = function()
			return isChainEnabled(links, initializers, key)
		end

		-- an indented row gets a parent initializer, which also registers the value-changed
		-- callback for that parent. An unindented one deliberately has no parent, so nothing of
		-- ours ends up being called from inside Blizzard's Init
		local ancestor = link
		if link.indent then
			initializer:SetParentInitializer(initializers[link.key], predicate)
			ancestor = links[link.key]
		else
			initializer:AddModifyPredicate(predicate)
		end

		-- watch every remaining gate in the chain, otherwise toggling one two links up leaves this
		-- row looking enabled. Despite the name this registers against SettingsCallbackRegistry,
		-- which settings trigger on their own variable just like cvars do
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

	-- sub-categories
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

				-- delay callback until settings are shown
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
        type = 'custom',
        title = 'A Custom Row',
        tooltip = 'Optional tooltip', -- (optional)
        requires = 'myToggle', -- (optional) same dependency handling as a keyed setting
        createControl = function(rowFrame) -- a SettingsListElementTemplate row; rowFrame.Text is its label
            return A:CreateToggle(rowFrame, '', getValue, setValue) -- any frame; anchored to the row's right side
        end,
    },
    {
        type = 'section',
        title = 'A Collapsible Section',
        expanded = false, -- (optional) defaults to false, so sections start collapsed
        createContent = function(section) -- called once per physical row frame (rows get recycled)
            local content = CreateFrame('Frame', nil, section)
            content:SetHeight(80) -- the height is read back to size the expanded section
            return content
        end,
    },
    {
        type = 'preview',
        title = 'PREVIEW', -- (optional) label drawn inside the box, defaults to PREVIEW
        height = 195, -- (optional) row height, defaults to 195
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

	-- deliberately not ContinueOnAddOnLoaded: going through our own event system keeps this
	-- ordered against namespace:OnLoad, which would otherwise be a race between two event systems
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
This callback is triggered when the "Defaults" button is clicked.
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
	-- gotta do this dumb shit because `..., callback` is not valid Lua
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
	-- sliders aren't supported in menus, so we create our own custom element
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
panel's own rows use) with an optional text label to its right - pass an empty string for a row that
carries its own label. `getValue`/`setValue` read/write the checked state.
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

	-- the template carries no label of its own, since its rows put one on the row instead
	if label ~= '' then
		checkbox.Text = checkbox:CreateFontString(nil, 'ARTWORK', 'GameFontHighlight')
		checkbox.Text:SetPoint('LEFT', checkbox, 'RIGHT', 2, 0)
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

`initializeItem`, if given, is called as `initializeItem(button, option)` for each list item, to customize its
appearance (e.g. font, an attached texture — see `namespace:CreateMediaDropdown`). It may optionally
return `width, height` to widen the row beyond its default text-driven size.
--]]
function A:CreateDropdown(parent, options, getValue, setValue, initializeItem)
	A:ArgCheck(options, 2, 'table')
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
		for _, option in next, options do
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
item of `mediaType` ('font' or 'statusbar'), with each option previewed — rendered in its own font, or showing its own texture.

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
	assert(mediaType == 'font' or mediaType == 'statusbar', "mediaType must be 'font' or 'statusbar'")

	local LSM = LibStub('LibSharedMedia-3.0', true)
	assert(LSM, 'LibSharedMedia-3.0 is required for CreateMediaDropdown')

	local options = {}
	for _, name in next, LSM:List(mediaType) do
		table.insert(options, { value = name, label = name })
	end

	local function ApplyFontPreview(fontString, name)
		-- Fetch falls back to the default media for an unknown key, so a value that was never set
		-- still returns a usable path while leaving the name nil
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

	local dropdown = A:CreateDropdown(parent, options, getValue, setValue, function(button, option)
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
