local _, A = ...

--[[ namespace:FormatCoordinates(_x_, _y_) ![](https://img.shields.io/badge/function-blue)
Formats normalized map coordinates (0-1) as percentage strings, with the decimal portion dimmed.
--]]
function A:FormatCoordinates(x, y)
	return (gsub(format('|cfff0f0f0%.2f|r', x * 100), '%.(.+)', '|cffa0a0a0.%1|r')),
		(gsub(format('|cfff0f0f0%.2f|r', y * 100), '%.(.+)', '|cffa0a0a0.%1|r'))
end
