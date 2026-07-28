local _, A = ...

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
