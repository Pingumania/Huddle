local addonName, A = ...

local function RemoveStaleKeys(saved, defaults)
	for key, value in pairs(saved) do
		local defaultValue = defaults[key]

		if defaultValue == nil then
			saved[key] = nil
		elseif type(value) == 'table' and type(defaultValue) == 'table' then
			RemoveStaleKeys(value, defaultValue)
		end
	end
end

--[[ namespace:RegisterSavedVariables(_globalName_, _defaults_) ![](https://img.shields.io/badge/function-blue)
Sets up `namespace.Config` from the saved variables global `globalName` (as declared via a `## SavedVariables:` line in your addon's toc), stripping stale keys and falling back to `defaults`.

Usage:
```lua
A:RegisterSavedVariables('MyAddonDB', {
    enabled = true,
})
```
--]]
function A:RegisterSavedVariables(globalName, defaults)
	A:ContinueOnAddOnLoaded(addonName, function()
		if not _G[globalName] then
			_G[globalName] = {}
		end

		RemoveStaleKeys(_G[globalName], defaults)
		A.Config = setmetatable(_G[globalName], { __index = defaults })
	end)
end
