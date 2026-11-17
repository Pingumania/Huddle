local _, ns = ...

local MEDIA_MENU_HEIGHT = 300
local SETTING_KINDS = { toggle = 'Checkbox', slider = 'Slider', header = 'Divider' }

local function MediaValues(mediaType)
	local values = {}

	for _, name in next, LibStub('LibSharedMedia-3.0'):List(mediaType) do
		table.insert(values, { text = name })
	end

	return values
end

--[[ namespace:CreateEditModeSetting(_info_) ![](https://img.shields.io/badge/function-blue)
Converts an option `info` table, as passed to `namespace:RegisterSettings`, into a
[LibEditMode](https://github.com/p3lim-wow/LibEditMode) setting that reads and writes the same option.
Supports the `toggle`, `slider`, `menu`, `media` and `header` types. Requires `namespace.LibEditMode`.
--]]
function ns:CreateEditModeSetting(info)
	local setting = {
		kind = ns.LibEditMode.SettingType[SETTING_KINDS[info.type] or 'Dropdown'],
		name = info.title,
		desc = info.tooltip,
		default = info.default,
		minValue = info.minValue,
		maxValue = info.maxValue,
		valueStep = info.valueStep,
		get = function()
			return ns:GetOption(info.key)
		end,
		set = function(_, value)
			ns:SetOption(info.key, value)
		end,
	}

	if info.type == 'media' then
		setting.height = MEDIA_MENU_HEIGHT
		setting.values = function()
			return MediaValues(info.mediaType)
		end
	elseif info.type == 'menu' then
		setting.values = {}
		for _, option in ipairs(info.options) do
			table.insert(setting.values, { text = option.label, value = option.value })
		end
	end

	return setting
end

--[[ namespace:TrackEditModeLayouts(_savedvariable_, _key_) ![](https://img.shields.io/badge/function-blue)
Keeps the per-layout table at `_G[savedvariable][key]` in step with Edit Mode, moving an entry when its
layout is renamed and dropping it when its layout is deleted. Requires `namespace.LibEditMode`.
--]]
function ns:TrackEditModeLayouts(savedvariable, key)
	ns.LibEditMode:RegisterCallback('rename', function(oldName, newName)
		local layouts = _G[savedvariable][key]
		if layouts and layouts[oldName] then
			layouts[newName] = layouts[oldName]
			layouts[oldName] = nil
		end
	end)
	ns.LibEditMode:RegisterCallback('delete', function(layoutName)
		local layouts = _G[savedvariable][key]
		if layouts then
			layouts[layoutName] = nil
		end
	end)
end

--[[ namespace:AddEditModeFrame(_frame_, _info_) ![](https://img.shields.io/badge/function-blue)
Places `frame` and, when `namespace.LibEditMode` is available, registers it with Edit Mode, storing its
position per layout in `_G[info.savedvariable][info.key]`.

Usage:
```lua
namespace:AddEditModeFrame(frame, {
	savedvariable = 'MyAddOnDB',
	key = 'framePosition',
	default = { point = 'CENTER', x = 0, y = 0 },
	name = 'My Frame',
	settings = {}, -- optional option info tables, see namespace:CreateEditModeSetting
	OnEditMode = function(isEditing) end, -- optional, called on entering and leaving Edit Mode
})
```
--]]
function ns:AddEditModeFrame(frame, info)
	local function ApplyPosition(layoutName)
		local positions = _G[info.savedvariable][info.key]
		local position = positions and positions[layoutName] or info.default
		frame:ClearAllPoints()
		frame:SetPoint(position.point, UIParent, position.point, position.x, position.y)
	end

	ApplyPosition()

	local LibEditMode = ns.LibEditMode
	if not LibEditMode then return end

	LibEditMode:AddFrame(frame, function(_, layoutName, point, x, y)
		local db = _G[info.savedvariable]
		db[info.key] = db[info.key] or {}
		db[info.key][layoutName] = { point = point, x = x, y = y }
	end, info.default, info.name)

	if info.settings then
		local settings = {}
		for _, setting in ipairs(info.settings) do
			table.insert(settings, ns:CreateEditModeSetting(setting))
		end
		LibEditMode:AddFrameSettings(frame, settings)
	end

	LibEditMode:RegisterCallback('layout', function(layoutName)
		ns:Defer(ApplyPosition, layoutName)
	end)
	ns:TrackEditModeLayouts(info.savedvariable, info.key)

	if info.OnEditMode then
		LibEditMode:RegisterCallback('enter', function()
			info.OnEditMode(true)
		end)
		LibEditMode:RegisterCallback('exit', function()
			info.OnEditMode(false)
		end)
	end
end
