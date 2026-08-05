local _, ns = ...

local frames = setmetatable({}, { __mode = 'k' })
local listening

local function applyScale(frame)
	frame:SetIgnoreParentScale(true)
	frame:SetScale(PixelUtil.GetPixelToUIUnitFactor())
end

local function rescaleAll()
	for frame in next, frames do
		applyScale(frame)
	end
end

--[[ namespace:SetPixelPerfect(_frame_) ![](https://img.shields.io/badge/function-blue)
Detaches `frame` from its parent's scale and renders it at one ui unit per physical pixel.

The factor depends on the physical resolution, so the frame is rescaled automatically when that
changes. Note this makes the frame's own anchor offsets resolve in its own scale, so anchor it
through an unscaled holder at zero offset if it has to line up with anything.
--]]
function ns:SetPixelPerfect(frame)
	if not listening then
		listening = true
		ns:RegisterEvent('DISPLAY_SIZE_CHANGED', rescaleAll)
		ns:RegisterEvent('UI_SCALE_CHANGED', rescaleAll)
	end

	frames[frame] = true
	applyScale(frame)
end

--[[ namespace:ClearPixelPerfect(_frame_) ![](https://img.shields.io/badge/function-blue)
Reattaches `frame` to its parent's scale and stops tracking it.
--]]
function ns:ClearPixelPerfect(frame)
	frames[frame] = nil
	frame:SetIgnoreParentScale(false)
end

--[[ namespace:PixelSize(_region_[, _pixels_]) ![](https://img.shields.io/badge/function-blue)
Returns the size in ui units that renders as exactly `pixels` physical pixels at `region`'s
current effective scale, defaulting to one pixel.

`PixelUtil` only offers `GetNearestPixelSize`, which takes a ui unit size and rounds it to the
nearest pixel, so a border asked for in units lands on one or two pixels depending on the scale.

The result is only valid for the scale the region had when it was called, so recompute it if the
region is rescaled or reparented.

Usage:
```lua
border:SetHeight(namespace:PixelSize(border, 1))
```
--]]
function ns:PixelSize(region, pixels)
	return (pixels or 1) * PixelUtil.GetPixelToUIUnitFactor() / region:GetEffectiveScale()
end

--[[ namespace:SetWidth(_region_, _width_[, _minPixels_]) ![](https://img.shields.io/badge/function-blue)
--]]
function ns:SetWidth(region, ...)
	PixelUtil.SetWidth(region, ...)
end

--[[ namespace:SetHeight(_region_, _height_[, _minPixels_]) ![](https://img.shields.io/badge/function-blue)
--]]
function ns:SetHeight(region, ...)
	PixelUtil.SetHeight(region, ...)
end

--[[ namespace:SetSize(_region_, _width_, _height_[, _minWidthPixels_, _minHeightPixels_]) ![](https://img.shields.io/badge/function-blue)
--]]
function ns:SetSize(region, ...)
	PixelUtil.SetSize(region, ...)
end

--[[ namespace:SetPoint(_region_, _point_, _relativeTo_, _relativePoint_, _x_, _y_[, _minXPixels_, _minYPixels_]) ![](https://img.shields.io/badge/function-blue)
Snap sizes and offsets to whole pixels at the region's own scale, so nothing straddles a pixel
boundary. These forward to `PixelUtil`, including its optional minimum pixel counts.
--]]
function ns:SetPoint(region, ...)
	PixelUtil.SetPoint(region, ...)
end

--[[ namespace:DisableSharpening(_texture_) ![](https://img.shields.io/badge/function-blue)
Stops the renderer nudging `texture` onto the pixel grid, which is what makes a thin texture land
on one pixel or the next depending on where it sits. Same pair Blizzard's own border code applies
in `NineSliceUtil.DisableSharpening`.
--]]
function ns:DisableSharpening(texture)
	texture:SetSnapToPixelGrid(false)
	texture:SetTexelSnappingBias(0)
end

--[[ namespace:EnableSharpening(_texture_) ![](https://img.shields.io/badge/function-blue)
Puts `texture` back on the pixel grid, undoing `namespace:DisableSharpening`. The bias is the
engine default rather than anything the texture carried before, so only call this on textures the
addon sharpened itself.
--]]
function ns:EnableSharpening(texture)
	texture:SetSnapToPixelGrid(true)
	texture:SetTexelSnappingBias(0.51)
end
