local _, A = ...

--[[ namespace:IsRetail() ![](https://img.shields.io/badge/function-blue)
Checks if the current client is running the "retail" version.
--]]
function A:IsRetail()
	return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
end

--[[ namespace:IsClassicEra() ![](https://img.shields.io/badge/function-blue)
Checks if the current client is running the "classic era" version (e.g. vanilla).
--]]
function A:IsClassicEra()
	return WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
end

--[[ namespace:IsClassic() ![](https://img.shields.io/badge/function-blue)
Checks if the current client is running the "classic" version.
--]]
function A:IsClassic()
	-- instead of using the floating constant for classic we'll just NOR the other two,
	-- as they are static
	return not A:IsRetail() and not A:IsClassicEra()
end

local _, buildVersion, _, interfaceVersion = GetBuildInfo()
--[[ namespace:HasVersion(_interfaceVersion_) ![](https://img.shields.io/badge/function-blue)
Checks if the current client is running an interface version equal to or newer than the specified.
--]]
function A:HasVersion(interface)
	return interfaceVersion >= interface
end

--[[ namespace:HasBuild(_buildNumber_[, _interfaceVersion_]) ![](https://img.shields.io/badge/function-blue)
Checks if the current client is running a build equal to or newer than the specified.
Optionally also check against the interface version.
--]]
function A:HasBuild(build, interface)
	if interface and interfaceVersion < interface then
		return
	end

	return tonumber(buildVersion) >= build
end
