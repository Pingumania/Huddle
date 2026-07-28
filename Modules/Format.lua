local _, A = ...

--[[ namespace:RGBToHex(_r_, _g_, _b_) ![](https://img.shields.io/badge/function-blue)
Converts an RGB color (0-1 range) into a `RRGGBB` hex string.
`r` may also be a table with `r`/`g`/`b` keys, or an indexed `{r, g, b}` table, in which case `g` and `b` are ignored.
--]]
function A:RGBToHex(r, g, b)
	if type(r) == 'table' then
		if r.r then
			r, g, b = r.r, r.g, r.b
		else
			r, g, b = unpack(r)
		end
	end

	return string.format('%02x%02x%02x', r * 255, g * 255, b * 255)
end

--[[ namespace:ColorText(_text_, _r_, _g_, _b_) ![](https://img.shields.io/badge/function-blue)
Wraps `text` in a `|cffRRGGBB`/`|r` color escape sequence, from an RGB color (see `RGBToHex`).
--]]
function A:ColorText(text, r, g, b)
	return '|cff' .. A:RGBToHex(r, g, b) .. text .. '|r'
end

--[[ namespace:FormatCoordinates(_x_, _y_) ![](https://img.shields.io/badge/function-blue)
Formats normalized map coordinates (0-1) as percentage strings, with the decimal portion dimmed.
--]]
function A:FormatCoordinates(x, y)
	return (gsub(format('|cfff0f0f0%.2f|r', x * 100), '%.(.+)', '|cffa0a0a0.%1|r')),
		(gsub(format('|cfff0f0f0%.2f|r', y * 100), '%.(.+)', '|cffa0a0a0.%1|r'))
end
