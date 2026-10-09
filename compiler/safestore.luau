-- Require Dependencies
const filters = require(script.Parent.exclusions)

local SafeStore = {}
SafeStore.__index = SafeStore

function SafeStore.new(realStore)
	return setmetatable({
		Store = realStore,
	}, SafeStore)
end

function SafeStore:CheckKey(key)
	if table.find(filters.DataStoreService, key) then
		error(`Access to protected DataStore key "{key}" is not allowed.`)
	end
end

function SafeStore:GetAsync(key)
	self:CheckKey(key)
	return self.Store:GetAsync(key)
end

function SafeStore:SetAsync(key, value)
	self:CheckKey(key)
	return self.Store:SetAsync(key, value)
end

function SafeStore:RemoveAsync(key)
	self:CheckKey(key)
	return self.Store:RemoveAsync(key)
end

function SafeStore:IncrementAsync(key, amount)
	self:CheckKey(key)
	return self.Store:IncrementAsync(key, amount)
end

function SafeStore:UpdateAsync(key, callback)
	self:CheckKey(key)
	return self.Store:UpdateAsync(key, callback)
end

return SafeStore
