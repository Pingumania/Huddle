local _, ns = ...

local frames = setmetatable({}, { __mode = 'k' })
local heights = setmetatable({}, { __mode = 'k' })
local listening
local sizing

local function applyScale(frame)
	frame:SetIgnoreParentScale(true)
	frame:SetScale(PixelUtil.GetPixelToUIUnitFactor())
end

local function rescaleAll()
	for frame in next, frames do
		applyScale(frame)
	end
end

local function applyHeight(region, pixels)
	region:SetHeight(ns:PixelSize(region, pixels))
end

local function resizeAll()
	for region, pixels in next, heights do
		applyHeight(region, pixels)
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

--[[ namespace:SnapToPixelGrid(_frame_) ![](https://img.shields.io/badge/function-blue)
Nudges `frame` so its bottom left corner lands on a whole physical pixel, by adjusting the offsets of
its single anchor point.

Sizes snapped with `namespace:SetSize` only stay crisp if the frame they sit in starts on the grid.
A frame anchored `CENTER` or dropped by the user lands wherever it lands, and every child inherits
that fraction, which is what makes a one pixel border look thinner on one edge than the other. Call
it after the frame moves. Frames with more or less than one anchor point are left alone.

Usage:
```lua
namespace:SnapToPixelGrid(frame)
```
--]]
function ns:SnapToPixelGrid(frame)
	if frame:GetNumPoints() ~= 1 then
		return
	end

	local left, bottom = frame:GetRect()

	if not left then
		return
	end

	local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
	local unit = PixelUtil.GetPixelToUIUnitFactor() / frame:GetEffectiveScale()
	local pixelX, pixelY = left / unit, bottom / unit

	frame:SetPoint(point, relativeTo, relativePoint,
		x + (math.floor(pixelX + 0.5) - pixelX) * unit,
		y + (math.floor(pixelY + 0.5) - pixelY) * unit)
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

--[[ namespace:SetPixelHeight(_region_[, _pixels_]) ![](https://img.shields.io/badge/function-blue)
Sets `region` to exactly `pixels` physical pixels tall, defaulting to one, and keeps it there when
the physical resolution or ui scale changes.

Use it for hairlines - dividers, borders, underlines - where `namespace:SetHeight` rounds to one or
two pixels depending on the scale. Sharpening is turned off for textures, so a thin line is not
nudged onto the neighbouring row.

Usage:
```lua
namespace:SetPixelHeight(divider)
```
--]]
function ns:SetPixelHeight(region, pixels)
	if not sizing then
		sizing = true
		ns:RegisterEvent('DISPLAY_SIZE_CHANGED', resizeAll)
		ns:RegisterEvent('UI_SCALE_CHANGED', resizeAll)
	end

	if region.SetSnapToPixelGrid then
		ns:DisableSharpening(region)
	end

	heights[region] = pixels or 1
	applyHeight(region, heights[region])
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
