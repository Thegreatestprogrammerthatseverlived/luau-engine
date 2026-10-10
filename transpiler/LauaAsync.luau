local Async = {}
local Promise = {}
Promise.__index = Promise

local function isPromise(value)
    return type(value) == "table" and getmetatable(value) == Promise
end

local function settle(promise, status, values)
    if promise._status ~= "Pending" then return end
    promise._status = status
    promise._values = values
    for _, thread in promise._waiters do
        task.spawn(thread, status == "Fulfilled", table.unpack(values, 1, values.n))
    end
    table.clear(promise._waiters)
end

function Async.run(callback, ...)
    assert(type(callback) == "function", "Async.run expects a function")
    local promise = setmetatable({_status = "Pending", _values = nil, _waiters = {}}, Promise)
    local args = table.pack(...)
    task.spawn(function()
        local result = table.pack(xpcall(function()
            return callback(table.unpack(args, 1, args.n))
        end, function(err) return err end))
        if result[1] then
            local values = table.pack(table.unpack(result, 2, result.n))
            if values.n == 1 and isPromise(values[1]) then
                local settled = table.pack(pcall(Async.await, values[1]))
                if settled[1] then
                    settle(promise, "Fulfilled", table.pack(table.unpack(settled, 2, settled.n)))
                else
                    settle(promise, "Rejected", table.pack(settled[2]))
                end
            else
                settle(promise, "Fulfilled", values)
            end
        else
            settle(promise, "Rejected", table.pack(result[2]))
        end
    end)
    return promise
end

function Async.await(value)
    if not isPromise(value) then return value end
    if value._status == "Fulfilled" then
        return table.unpack(value._values, 1, value._values.n)
    end
    if value._status == "Rejected" then error(value._values[1], 2) end
    local current = coroutine.running()
    if not current then error("await requires a yieldable coroutine", 2) end
    table.insert(value._waiters, current)
    local outcome = table.pack(coroutine.yield())
    if not outcome[1] then error(outcome[2], 2) end
    return table.unpack(outcome, 2, outcome.n)
end

function Promise:await()
    return Async.await(self)
end

function Promise:andThen(callback)
    return Async.run(function()
        return callback(Async.await(self))
    end)
end

function Promise:catch(callback)
    return Async.run(function()
        local result = table.pack(pcall(Async.await, self))
        if result[1] then return table.unpack(result, 2, result.n) end
        return callback(result[2])
    end)
end

function Promise:finally(callback)
    return Async.run(function()
        local result = table.pack(pcall(Async.await, self))
        callback()
        if not result[1] then error(result[2], 0) end
        return table.unpack(result, 2, result.n)
    end)
end

function Promise:getStatus()
    return self._status
end

Async.Promise = Promise
Async.isPromise = isPromise
return Async
