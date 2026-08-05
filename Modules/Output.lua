local ADDON_NAME, ns = ...

--[[ namespace:Print(_..._) ![](https://img.shields.io/badge/function-blue)
Prints a message to the default chat frame, prefixed with the addon's name.
--]]
function ns:Print(...)
	print(NORMAL_FONT_COLOR_CODE .. ADDON_NAME .. ':|r', ...)
end

--[[ namespace:Debug(_..._) ![](https://img.shields.io/badge/function-blue)
Prints a debug message to the default chat frame, prefixed with the addon's name, but only if `namespace.Config.debug` is truthy.
--]]
function ns:Debug(...)
	if ns.Config and ns.Config.debug then
		print(RED_FONT_COLOR_CODE .. ADDON_NAME .. ' Debug:|r', ...)
	end
end

--[[ namespace:DumpUI(_value_) ![](https://img.shields.io/badge/function-blue)
Sends `value` to [DevTool](https://www.curseforge.com/wow/addons/devtool) for inspection, if it's installed.
Falls back to Blizzard's own table inspector window otherwise.
--]]
function ns:DumpUI(value)
	if DevTool and DevTool.AddData then
		DevTool:AddData(value)
		return
	end

	C_AddOns.LoadAddOn('Blizzard_DebugTools')
	DisplayTableInspectorWindow(value)
end
