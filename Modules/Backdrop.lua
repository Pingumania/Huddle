local _, A = ...

--[[ namespace.Backdrop ![](https://img.shields.io/badge/object-teal)
A generic tooltip-style backdrop table, for use with `frame:SetBackdrop(A.Backdrop)` (requires `BackdropTemplate`).
--]]
A.Backdrop = {
	bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
	edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
	tile = true,
	tileSize = 8,
	edgeSize = 16,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

--[[ namespace:CreateBackdrop(_frame_[, _bgColor_, _borderColor_]) ![](https://img.shields.io/badge/function-blue)
Applies `namespace.Backdrop` to `frame`, mixing in `BackdropTemplateMixin` first if the frame doesn't already support it (only needed on retail).
`bgColor` and `borderColor` are optional `{r, g, b[, a]}` tables, defaulting to opaque black and white respectively.

Usage:
```lua
A:CreateBackdrop(someFrame)
A:CreateBackdrop(someFrame, { 0, 0, 0, 0.4 }, { 1, 1, 1, 0.6 })
```
--]]
function A:CreateBackdrop(frame, bgColor, borderColor)
	if type(frame) == 'string' then
		frame = _G[frame]
	end

	if not frame.SetBackdrop then
		Mixin(frame, BackdropTemplateMixin)
	end

	frame:SetBackdrop(A.Backdrop)

	bgColor = bgColor or { 0, 0, 0, 1 }
	frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)

	borderColor = borderColor or { 1, 1, 1, 1 }
	frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
end
