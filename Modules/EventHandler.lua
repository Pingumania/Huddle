local addonName, A = ...

--[[ namespace.eventMixin ![](https://img.shields.io/badge/object-teal)
A multi-purpose [event](https://warcraft.wiki.gg/wiki/Events)-[mixin](https://en.wikipedia.org/wiki/Mixin).

These methods are mixed into `namespace`, and thus are available directly, e.g:

```lua
namespace:RegisterEvent('BAG_UPDATE', function(self, ...)
    -- do something
end)
```
--]]

local eventHandler = CreateFrame('Frame')
local callbacks = {}

local unitEventValidator = CreateFrame('Frame')
local function IsUnitEventValid(event, unit)
	local isValid = pcall(unitEventValidator.RegisterUnitEvent, unitEventValidator, event, unit)
	if isValid then
		unitEventValidator:UnregisterEvent(event)
	end
	return isValid
end

local unitValidator = CreateFrame('Frame')
local function IsUnitValid(unit)
	if unitValidator:RegisterUnitEvent('UNIT_HEALTH', unit) then
		local _, registeredUnit = unitValidator:IsEventRegistered('UNIT_HEALTH')
		unitValidator:UnregisterEvent('UNIT_HEALTH')
		return not not registeredUnit -- it will be nil if the registered unit is invalid
	end
end

local function CopyList(list)
	local copy = {}
	for index = 1, #list do
		copy[index] = list[index]
	end
	return copy
end

local EventMixin = {}
--[[ namespace.EventMixin:RegisterEvent(_event_[, _callback_]) ![](https://img.shields.io/badge/function-blue)
Registers a [frame `event`](https://warcraft.wiki.gg/wiki/Events) with the `callback` function.
If `callback` is omitted, it defaults to `self[event]` (a same-named method on the caller).
If the callback returns positive it will be unregistered.
--]]
function EventMixin:RegisterEvent(event, callback)
	callback = callback or self[event]
	assert(A:IsEventValid(event), 'arg1 must be an event')
	assert(type(callback) == 'function', 'arg2 must be a function')

	if not callbacks[event] then
		callbacks[event] = {}
	end

	table.insert(callbacks[event], {
		callback = callback,
		owner = self,
	})

	if not eventHandler:IsEventRegistered(event) then
		eventHandler:RegisterEvent(event)
	end
end

--[[ namespace.EventMixin:UnregisterEvent(_event_, _callback_) ![](https://img.shields.io/badge/function-blue)
Unregisters a [frame `event`](https://warcraft.wiki.gg/wiki/Events) from the `callback` function.
--]]
function EventMixin:UnregisterEvent(event, callback)
	assert(A:IsEventValid(event), 'arg1 must be an event')
	assert(type(callback) == 'function', 'arg2 must be a function')

	if callbacks[event] then
		for index, data in ipairs(callbacks[event]) do
			if data.owner == self and data.callback == callback then
				table.remove(callbacks[event], index)
				break
			end
		end

		if #callbacks[event] == 0 then
			eventHandler:UnregisterEvent(event)
		end
	end
end

--[[ namespace.EventMixin:UnregisterAllEvents([_callback_]) ![](https://img.shields.io/badge/function-blue)
Unregisters all [frame events](https://warcraft.wiki.gg/wiki/Events), or specifically from the `callback` function.
--]]
function EventMixin:UnregisterAllEvents(callback)
	if callback then
		assert(type(callback) == 'function', 'arg1 must be a function')
	end

	for event, cbs in next, callbacks do
		for _, data in ipairs(CopyList(cbs)) do
			if data.owner == self then
				if callback then
					if data.callback == callback then
						self:UnregisterEvent(event, data.callback)
					end
				else
					self:UnregisterEvent(event, data.callback)
				end
			end
		end
	end
end

--[[ namespace.EventMixin:IsEventRegistered(_event_, _callback_) ![](https://img.shields.io/badge/function-blue)
Checks if the [frame `event`](https://warcraft.wiki.gg/wiki/Events) is registered with the `callback` function.
--]]
function EventMixin:IsEventRegistered(event, callback)
	assert(A:IsEventValid(event), 'arg1 must be an event')
	assert(type(callback) == 'function', 'arg2 must be a function')

	if callbacks[event] then
		for _, data in next, callbacks[event] do
			if data.callback == callback then
				return true
			end
		end
	end
end

--[[ namespace.EventMixin:TriggerEvent(_event_[, _..._]) ![](https://img.shields.io/badge/function-blue)
Manually trigger the `event` (with optional arguments) on all registered callbacks.
If the callback returns positive it will be unregistered.
--]]
function EventMixin:TriggerEvent(event, ...)
	if callbacks[event] then
		for _, data in ipairs(CopyList(callbacks[event])) do
			local successful, ret = pcall(data.callback, data.owner, ...)
			if not successful then
				CallErrorHandler(ret)
			elseif ret then
				EventMixin.UnregisterEvent(data.owner, event, data.callback)
			end
		end
	end
end

eventHandler:SetScript('OnEvent', function(_, event, ...)
	EventMixin:TriggerEvent(event, ...)
end)

local unitEventHandlers = {}
local function getUnitEventHandler(unit)
	if not unitEventHandlers[unit] then
		local unitEventHandler = CreateFrame('Frame')
		unitEventHandler:SetScript('OnEvent', function(_, event, ...)
			EventMixin:TriggerUnitEvent(event, unit, ...)
		end)
		unitEventHandlers[unit] = unitEventHandler
	end
	return unitEventHandlers[unit]
end

local unitEventCallbacks = {}
--[[ namespace.EventMixin:RegisterUnitEvent(_event_, _unit_[, _unitN,..._], _callback_) ![](https://img.shields.io/badge/function-blue)
Registers a [`unit`](https://warcraft.wiki.gg/wiki/UnitId)-specific [frame `event`](https://warcraft.wiki.gg/wiki/Events) with the `callback` function.
If the callback returns positive it will be unregistered for that unit.
--]]
function EventMixin:RegisterUnitEvent(event, ...)
	assert(A:IsEventValid(event), 'arg1 must be an event')
	local callback = select(select('#', ...), ...)
	assert(type(callback) == 'function', 'last argument must be a function')

	for i = 1, select('#', ...) - 1 do
		local unit = select(i, ...)
		assert(IsUnitValid(unit), 'arg' .. (i + 1) .. ' must be a valid unit')
		assert(IsUnitEventValid(event, unit), 'event "' .. event .. '" is not valid for the given unit')

		if not unitEventCallbacks[unit] then
			unitEventCallbacks[unit] = {}
		end
		if not unitEventCallbacks[unit][event] then
			unitEventCallbacks[unit][event] = {}
		end

		table.insert(unitEventCallbacks[unit][event], {
			callback = callback,
			owner = self,
		})

		local unitEventHandler = getUnitEventHandler(unit)
		local isRegistered, registeredUnit = unitEventHandler:IsEventRegistered(event)
		if not isRegistered then
			unitEventHandler:RegisterUnitEvent(event, unit)
		elseif registeredUnit ~= unit then
			error('unit event somehow registered with the wrong unit')
		end
	end
end

--[[ namespace.EventMixin:UnregisterUnitEvent(_event_, _unit_[, _unitN,..._], _callback_) ![](https://img.shields.io/badge/function-blue)
Unregisters a [`unit`](https://warcraft.wiki.gg/wiki/UnitId)-specific [frame `event`](https://warcraft.wiki.gg/wiki/Events) from the `callback` function.
--]]
function EventMixin:UnregisterUnitEvent(event, ...)
	assert(A:IsEventValid(event), 'arg1 must be an event')
	local callback = select(select('#', ...), ...)
	assert(type(callback) == 'function', 'last argument must be a function')

	for i = 1, select('#', ...) - 1 do
		local unit = select(i, ...)
		assert(IsUnitValid(unit), 'arg' .. (i + 1) .. ' must be a valid unit')
		assert(IsUnitEventValid(event, unit), 'event is not valid for the given unit')

		if unitEventCallbacks[unit] and unitEventCallbacks[unit][event] then
			for index, data in ipairs(unitEventCallbacks[unit][event]) do
				if data.owner == self and data.callback == callback then
					table.remove(unitEventCallbacks[unit][event], index)
					break
				end
			end

			if #unitEventCallbacks[unit][event] == 0 then
				getUnitEventHandler(unit):UnregisterEvent(event)
			end
		end
	end
end

--[[ namespace.EventMixin:IsUnitEventRegistered(_event_, _unit_[, _unitN,..._], _callback_) ![](https://img.shields.io/badge/function-blue)
Checks if the [`unit`](https://warcraft.wiki.gg/wiki/UnitId)-specific [frame `event`](https://warcraft.wiki.gg/wiki/Events) is registered with the `callback` function.
--]]
function EventMixin:IsUnitEventRegistered(event, ...)
	assert(A:IsEventValid(event), 'arg1 must be an event')
	local callback = select(select('#', ...), ...)
	assert(type(callback) == 'function', 'last argument must be a function')

	for i = 1, select('#', ...) - 1 do
		local unit = select(i, ...)
		assert(IsUnitValid(unit), 'arg' .. (i + 1) .. ' must be a valid unit')
		assert(IsUnitEventValid(event, unit), 'event is not valid for the given unit')

		if unitEventCallbacks[unit] and unitEventCallbacks[unit][event] then
			for _, data in next, unitEventCallbacks[unit][event] do
				if data.callback == callback then
					return true
				end
			end
		end
	end
end

--[[ namespace.EventMixin:TriggerEvent(_event_, _unit_[, _unitN,..._][, _..._]) ![](https://img.shields.io/badge/function-blue)
Manually trigger the [`unit`](https://warcraft.wiki.gg/wiki/UnitId)-specific `event` (with optional arguments) on all registered callbacks.
If the callback returns positive it will be unregistered.
--]]
function EventMixin:TriggerUnitEvent(event, unit, ...)
	if unitEventCallbacks[unit] and unitEventCallbacks[unit][event] then
		for _, data in ipairs(CopyList(unitEventCallbacks[unit][event])) do
			local successful, ret = pcall(data.callback, data.owner, ...)
			if not successful then
				CallErrorHandler(ret)
			elseif ret then
				EventMixin.UnregisterUnitEvent(data.owner, event, unit, data.callback)
			end
		end
	end
end

A.EventMixin = EventMixin

A = setmetatable(A, {
	__newindex = function(t, key, value)
		if key == 'OnLoad' then
			--[[ namespace:OnLoad() ![](https://img.shields.io/badge/function-blue)
			Shorthand for the [`ADDON_LOADED`](https://warcraft.wiki.gg/wiki/ADDON_LOADED) event for the addon.

			Usage:
			```lua
			function namespace:OnLoad()
			    -- I'm loaded!
			end
			```
			--]]
			A:RegisterEvent('ADDON_LOADED', function(self, name)
				if name == addonName then
					local successful, ret = pcall(value, self)
					if not successful then
						error(ret)
					end
					return true -- unregister event
				end
			end)
		elseif key == 'OnLogin' then
			--[[ namespace:OnLogin() ![](https://img.shields.io/badge/function-blue)
			Shorthand for the [`PLAYER_LOGIN`](https://warcraft.wiki.gg/wiki/PLAYER_LOGIN) event.

			Usage:
			```lua
			function namespace:OnLogin()
			    -- player has logged in!
			end
			```
			--]]
			A:RegisterEvent('PLAYER_LOGIN', function(self)
				local successful, ret = pcall(value, self)
				if not successful then
					error(ret)
				end
				return true -- unregister event
			end)
		elseif A:IsEventValid(key) then
			--[[ namespace:_event_ ![](https://img.shields.io/badge/function-blue)
			Registers a  to an anonymous function.

			Usage:
			```lua
			function namespace:BAG_UPDATE(bagID)
			    -- do something
			end
			-- or
			namespace.BAG_UPDATE = function(self, bagID)
			    -- do something
			end
			```
			--]]
			EventMixin.RegisterEvent(t, key, value)
		else
			rawset(t, key, value)
		end
	end,
	__index = function(t, key)
		if A:IsEventValid(key) then
			--[[ namespace:_event_([_..._]) ![](https://img.shields.io/badge/function-blue)
			Manually trigger all registered anonymous `event` callbacks, with optional arguments.

			Usage:
			```lua
			namespace:BAG_UPDATE(1) -- triggers the above example
			```
			--]]
			return function(_, ...)
				EventMixin.TriggerEvent(t, key, ...)
			end
		else
			return rawget(t, key)
		end
	end,
})

Mixin(A, EventMixin)
