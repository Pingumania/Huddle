local _, A = ...

-- hidden dummy frame we anchor stuff we want to hide to
local hidden = CreateFrame('Frame')
hidden:Hide()

local function resolve(object, ...)
	if type(object) == 'string' then
		object = _G[object]
	end

	if ... then
		-- iterate through arguments, they're children referenced by key
		for index = 1, select('#', ...) do
			object = object and object[select(index, ...)]
		end
	end

	return object
end

--[[ namespace:Hide(_object_[, _child_,...]) ![](https://img.shields.io/badge/function-blue)
Forcefully hide an `object`, or its `child`.
It will recurse down to the last child if provided.

This is permanent — it also blocks the object being reparented and silences its events. Use
`namespace:HideFrame` for something that has to be shown again later.

Usage:
```lua
namespace:Hide('ChatFrame2')
namespace:Hide('MinimapCluster', 'InstanceDifficulty')
namespace:Hide(someFrame, 'ResetButton')
```
--]]
function A:Hide(object, ...)
	object = resolve(object, ...)

	if object then
		object:SetParent(hidden)
		object.SetParent = nop

		if object.UnregisterAllEvents then
			object:UnregisterAllEvents()
		end
	end
end

-- weak keys, so parking a frame here doesn't keep it alive
local parents = setmetatable({}, { __mode = 'k' })

--[[ namespace:HideFrame(_object_[, _child_,...]) ![](https://img.shields.io/badge/function-blue)
Hides an `object`, or its `child`, by reparenting it, remembering where it came from so
`namespace:ShowFrame` can put it back. Use this over `namespace:Hide` for anything the user can
toggle back on.

Usage:
```lua
namespace:HideFrame('BagsBar')
```
--]]
function A:HideFrame(object, ...)
	object = resolve(object, ...)
	if not object then return end

	if parents[object] == nil then
		-- false rather than nil, so a parentless object isn't looked up again
		parents[object] = object:GetParent() or false
	end

	object:SetParent(hidden)
end

--[[ namespace:ShowFrame(_object_[, _child_,...]) ![](https://img.shields.io/badge/function-blue)
Reparents an `object`, or its `child`, back to where `namespace:HideFrame` found it.
--]]
function A:ShowFrame(object, ...)
	object = resolve(object, ...)

	local parent = object and parents[object]
	if parent then
		object:SetParent(parent)
	end
end

--[[ namespace:SetFrameMoveable(_frame_) ![](https://img.shields.io/badge/function-blue)
Makes `frame` moveable by click-and-drag, clamped to the screen.
--]]
function A:SetFrameMoveable(frame)
	if type(frame) == 'string' then
		frame = _G[frame]
	end

	if not frame then
		error('frame is nil') -- TODO: pretty this up
	end

	assert(type(frame) == 'table', 'arg1 must be a table')

	frame:SetMovable(true)
	frame:SetScript('OnMouseDown', function(self)
		self:StartMoving()
	end)
	frame:SetScript('OnMouseUp', function(self)
		self:StopMovingOrSizing()
	end)
	frame:SetClampedToScreen(true)
end

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
