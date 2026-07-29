local _, A = ...

--[[ namespace:ArgCheck(_value_, _argIndex_, _..._) ![](https://img.shields.io/badge/function-blue)
Asserts that `value` is one of the given type names, erroring with a message that references `argIndex` (the position in the calling function's argument list) otherwise.

Usage:
```lua
function A:MyMethod(name, count)
	A:ArgCheck(name, 1, 'string')
	A:ArgCheck(count, 2, 'number', 'nil') -- optional arg, so nil is also valid
end
```
--]]
function A:ArgCheck(value, argIndex, ...)
	local valueType = type(value)
	for index = 1, select('#', ...) do
		if valueType == select(index, ...) then
			return
		end
	end

	error(string.format('bad argument #%d (%s expected, got %s)', argIndex, table.concat({...}, ' or '), valueType), 3)
end
