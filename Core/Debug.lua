local _, A = ...

--[[ namespace:AddToDevTool(_data_) ![](https://img.shields.io/badge/function-blue)
Sends `data` to [DevTool](https://www.curseforge.com/wow/addons/devtool) for inspection, if it's installed. No-ops otherwise.
--]]
function A:AddToDevTool(data)
	if DevTool and DevTool.AddData then
		DevTool:AddData(data)
	end
end
