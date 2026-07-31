local addonName, A = ...

local RELOAD_ICON = '|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:14:14|t'
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
		title:SetText(string.format('%s - %s', addonName, name))
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

local function registerSetting(category, savedvariable, info)
	if info.type == 'custom' then
		A:ArgCheck(info.title, 3, 'string')
		A:ArgCheck(info.createControl, 3, 'function')

		local initializer = CreateFromMixins(ScrollBoxFactoryInitializerMixin, SettingsElementHierarchyMixin, SettingsSearchableElementMixin)
		ScrollBoxFactoryInitializerMixin.Init(initializer, 'SettingsListElementTemplate', { name = info.title, tooltip = info.tooltip })

		function initializer:GetExtent()
			return 26
		end

		function initializer:InitFrame(frame)
			if not frame.cbrHandles then
				frame.cbrHandles = Settings.CreateCallbackHandleContainer()
			end
			frame.data = self.data
			frame.Text:SetText(info.title)
			frame.Text:SetPoint('LEFT', 37, 0)
			frame.Text:SetPoint('RIGHT', frame, 'CENTER', -85, 0)

			if frame.customControlOwner ~= info then
				for _, child in next, { frame:GetChildren() } do
					if child ~= frame.Tooltip and child ~= frame.NewFeature then
						child:Hide()
					end
				end
				frame.customControl = info.createControl(frame)
				frame.customControl:SetPoint('LEFT', frame, 'CENTER', -48, 3)
				frame.customControlOwner = info
			elseif frame.customControl.GenerateMenu then
				frame.customControl:GenerateMenu()
			end
		end

		function initializer:Resetter(frame)
			if frame.cbrHandles then
				frame.cbrHandles:Unregister()
			end

			if frame.customControl then
				frame.customControl:Hide()
			end
			frame.customControlOwner = nil
		end

		SettingsPanel:GetLayout(category):AddInitializer(initializer)

		return initializer
	end

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
	local setting = Settings.RegisterAddOnSetting(category, uniqueKey, info.key, _G[savedvariable], type(info.default), title, info.default)

	local initializer
	if info.type == 'toggle' then
		initializer = Settings.CreateCheckbox(category, setting, tooltip)
	elseif info.type == 'slider' then
		A:ArgCheck(info.minValue, 3, 'number')
		A:ArgCheck(info.maxValue, 3, 'number')

		local options = Settings.CreateSliderOptions(info.minValue, info.maxValue, info.valueStep or 1)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, resolveSliderFormatter(info.valueFormat))

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
		elseif setting.type == 'custom' then
			registerSetting(category, savedvariable, setting)
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
	local category, layout = Settings.RegisterVerticalLayoutCategory(categoryName)
	Settings.RegisterAddOnCategory(category)
	settingsCategoryID = category:GetID()

	if not _G[savedvariable] then
		_G[savedvariable] = {}
	end

	local keys, initializers, links = registerSettingsList(category, layout, savedvariable, settings)
	applyDependencies(settings, keys, initializers, links)

	-- sub-categories
	if A.settingsChildren then
		for _, info in ipairs(A.settingsChildren) do
			if info.settings then
				local child, childLayout = Settings.RegisterVerticalLayoutSubcategory(category, info.name)
				local childKeys, childInitializers, childLinks = registerSettingsList(child, childLayout, savedvariable, info.settings)
				applyDependencies(info.settings, childKeys, childInitializers, childLinks)
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
        createControl = function(rowFrame) -- called once per physical row frame (rows get recycled)
            return A:CreateToggle(rowFrame, '', getValue, setValue) -- any frame; anchored to the row's right side
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
				[MinimalSliderWithSteppersMixin.Label.Right] = formatter or defaultSliderFormatter,
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
Creates a native checkbox (Blizzard's own `UICheckButtonTemplate`) with a text label.
`getValue`/`setValue` read/write the checked state.
--]]
function A:CreateToggle(parent, label, getValue, setValue)
	A:ArgCheck(label, 2, 'string')
	A:ArgCheck(getValue, 3, 'function')
	A:ArgCheck(setValue, 4, 'function')

	local checkbox = CreateFrame('CheckButton', nil, parent, 'UICheckButtonTemplate')
	checkbox.Text:SetText(label)
	checkbox:SetChecked(getValue())
	checkbox:SetScript('OnClick', function(self)
		setValue(not not self:GetChecked())
	end)

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
		[MinimalSliderWithSteppersMixin.Label.Right] = defaultSliderFormatter,
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
		local path = LSM:Fetch('font', name)
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
