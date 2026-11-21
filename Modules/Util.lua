local _, ns = ...

--[[ namespace:ArgCheck(_value_, _argIndex_, _..._) ![](https://img.shields.io/badge/function-blue)
Asserts that `value` is one of the given type names, erroring with a message that references `argIndex` (the position in the calling function's argument list) otherwise.

Usage:
```lua
function ns:MyMethod(name, count)
	ns:ArgCheck(name, 1, 'string')
	ns:ArgCheck(count, 2, 'number', 'nil') -- optional arg, so nil is also valid
end
```
--]]
function ns:ArgCheck(value, argIndex, ...)
	local valueType = type(value)
	for index = 1, select('#', ...) do
		if valueType == select(index, ...) then
			return
		end
	end

	error(string.format('bad argument #%d (%s expected, got %s)', argIndex, table.concat({...}, ' or '), valueType), 3)
end

--[[ namespace:GetRuleset() ![](https://img.shields.io/badge/function-blue)
Returns the active realm ruleset: `"HC"`, `"RPPvP"`, `"RP"`, `"PvP"` or `"PvE"`. Only valid on the "forever" version.
--]]
function ns:GetRuleset()
	if C_GameRules.IsGameRuleActive(Enum.GameRule.HardcoreRuleset) then
		return 'HC'
	elseif C_GameRules.IsGameRuleActive(Enum.GameRule.RPRuleset) and C_GameRules.IsGameRuleActive(Enum.GameRule.PvPRuleset) then
		return 'RPPvP'
	elseif C_GameRules.IsGameRuleActive(Enum.GameRule.RPRuleset) then
		return 'RP'
	elseif C_GameRules.IsGameRuleActive(Enum.GameRule.PvPRuleset) then
		return 'PvP'
	end

	return 'PvE'
end

--[[ namespace:GetProfileKey() ![](https://img.shields.io/badge/function-blue)
Returns the current character's profile key, `"Name-Realm"` on "retail" and `"Name Surname-Ruleset"` on "forever".
--]]
function ns:GetProfileKey()
	local name, suffix = UnitFullName('player')

	if ns:IsForever() then
		if suffix and suffix ~= '' then
			name = name .. ' ' .. suffix
		end

		return name .. '-' .. ns:GetRuleset()
	end

	return name .. '-' .. suffix
end
