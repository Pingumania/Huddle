local _, ns = ...

local localizations = {}
local locale = GetLocale()

ns.L = setmetatable({}, {
	__index = function(_, key)
		local value = localizations[locale] and localizations[locale][key]
		if value then
			return value
		end
		return localizations.enUS and localizations.enUS[key] or tostring(key)
	end,
	__call = function(_, newLocale)
		localizations[newLocale] = localizations[newLocale] or {}
		return localizations[newLocale]
	end,
})
