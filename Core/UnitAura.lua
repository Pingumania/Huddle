local _, A = ...

local function auraSlotsWrapper(unit, spellID, token, ...)
	local slot, data
	for index = 1, select('#', ...) do
		slot = select(index, ...)
		data = C_UnitAuras.GetAuraDataBySlot(unit, slot)
		if spellID == data.spellId and data.sourceUnit then
			return nil, data
		end
	end

	return token
end

--[[ namespace:GetUnitAura(_unitID_, _spellID_[, _filter_]) ![](https://img.shields.io/badge/function-blue)
Returns the aura by `spellID` on the [`unitID`](https://warcraft.wiki.gg/wiki/UnitId), if it exists.
See [UnitAura](https://warcraft.wiki.gg/wiki/API_C_UnitAuras.GetAuraDataByIndex#Filters) for the `filter` arg.
--]]
function A:GetUnitAura(unit, spellID, filter)
	local token, data
	repeat
		token, data = auraSlotsWrapper(unit, spellID, C_UnitAuras.GetAuraSlots(unit, filter, nil, token))
	until token == nil

	return data
end
