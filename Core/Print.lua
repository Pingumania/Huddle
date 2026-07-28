local addonName, A = ...

--[[ namespace:Print(_..._) ![](https://img.shields.io/badge/function-blue)
Prints a message to the default chat frame, prefixed with the addon's name.
--]]
function A:Print(...)
	print(NORMAL_FONT_COLOR_CODE .. addonName .. ':|r', ...)
end

--[[ namespace:Debug(_..._) ![](https://img.shields.io/badge/function-blue)
Prints a debug message to the default chat frame, prefixed with the addon's name, but only if `namespace.Config.debug` is truthy.
--]]
function A:Debug(...)
	if A.Config and A.Config.debug then
		print(RED_FONT_COLOR_CODE .. addonName .. ' Debug:|r', ...)
	end
end
