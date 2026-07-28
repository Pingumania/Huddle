local _, A = ...

if C_EventUtils then
	function A:IsEventValid(event)
		return C_EventUtils.IsEventValid(event)
	end
else
	local eventValidator = CreateFrame('Frame')

	function A:IsEventValid(event)
		local isValid = pcall(eventValidator.RegisterEvent, eventValidator, event)
		if isValid then
			eventValidator:UnregisterEvent(event)
		end
		return isValid
	end
end
