local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({ _event = Instance.new("BindableEvent"), _destroyed = false }, Signal)
end

function Signal:Connect(callback: (...any) -> ())
    assert(not self._destroyed, "Cannot connect to a destroyed signal")
    assert(type(callback) == "function", "Connect expects a function")
    return self._event.Event:Connect(callback)
end

function Signal:Once(callback: (...any) -> ())
    assert(type(callback) == "function", "Once expects a function")
    local connection
    connection = self:Connect(function(...)
        if connection then connection:Disconnect() end
        callback(...)
    end)
    return connection
end

function Signal:Fire(...)
    assert(not self._destroyed, "Cannot fire a destroyed signal")
    self._event:Fire(...)
end

function Signal:Wait()
    assert(not self._destroyed, "Cannot wait on a destroyed signal")
    return self._event.Event:Wait()
end

function Signal:Destroy()
    if self._destroyed then return end
    self._destroyed = true
    self._event:Destroy()
end

return Signal
