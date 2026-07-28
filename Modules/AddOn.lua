local _, A = ...

--[[ namespace:IsAddOnEnabled(addonName) ![](https://img.shields.io/badge/function-blue)
Checks whether the addon exists and is enabled.
--]]
function A:IsAddOnEnabled(name)
	return C_AddOns.GetAddOnEnableState(name, UnitName('player')) > 0
end


--[[ namespace:ContinueOnAddOnLoaded(_addonName_, _callback_) ![](https://img.shields.io/badge/function-blue)
Registers a hook for when an addon with the name `addonName` loads with a `callback` function.
--]]
function A:ContinueOnAddOnLoaded(addonName, callback)
	EventUtil.ContinueOnAddOnLoaded(addonName, callback)
end
