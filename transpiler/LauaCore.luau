local LauaCore = {}

function LauaCore.optional(value: any, key: any): any
    if value == nil then return nil end
    return value[key]
end

function LauaCore.coalesce(value: any, fallback: () -> any): any
    if value ~= nil then return value end
    return fallback()
end


-- Laua v22: spread merges consecutive array entries and then named keys.
function LauaCore.spread(...: any): {[any]: any}
    local result = {}
    for index = 1, select("#", ...) do
        local item = select(index, ...)
        assert(type(item) == "table", "spread expects tables")
        for arrayIndex = 1, #item do
            table.insert(result, item[arrayIndex])
        end
        for key, value in item do
            if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #item then
                result[key] = value
            end
        end
    end
    return result
end

function LauaCore.slice(value: any, first: number?, last: number?): any
    local valueType = typeof(value)
    if valueType == "string" then
        return string.sub(value, first or 1, last or #value)
    end
    if valueType == "buffer" then
        local length = buffer.len(value)
        local startIndex = first or 1
        local endIndex = last or length
        if startIndex < 0 then startIndex = length + startIndex + 1 end
        if endIndex < 0 then endIndex = length + endIndex + 1 end
        startIndex = math.clamp(startIndex, 1, length + 1)
        endIndex = math.clamp(endIndex, 0, length)
        local size = math.max(0, endIndex - startIndex + 1)
        local result = buffer.create(size)
        if size > 0 then buffer.copy(result, 0, value, startIndex - 1, size) end
        return result
    end
    error("slice supports strings and buffers only")
end

LauaCore.table = {}

function LauaCore.table.filter(items: {any}, predicate: (any, number) -> boolean): {any}
    local out = {}
    for index, item in items do
        if predicate(item, index) then table.insert(out, item) end
    end
    return out
end

function LauaCore.table.map(items: {any}, callback: (any, number) -> any): {any}
    local out = {}
    for index, item in items do
        out[index] = callback(item, index)
    end
    return out
end

function LauaCore.table.reduce(items: {any}, callback: (any, any, number) -> any, initial: any): any
    local current = initial
    for index, item in items do current = callback(current, item, index) end
    return current
end

function LauaCore.table.findWhere(items: {any}, predicate: (any, number) -> boolean): any
    for index, item in items do
        if predicate(item, index) then return item end
    end
    return nil
end

-- Lazy imports can break *some* initialisation cycles if neither module
-- accesses the other before both have finished loading.
function LauaCore.lazyModule(resolve: () -> any): any
    local loaded = false
    local target = nil
    local function get()
        if not loaded then
            target = resolve()
            loaded = true
        end
        return target
    end
    return setmetatable({}, {
        __index = function(_, key) return get()[key] end,
        __newindex = function(_, key, value) get()[key] = value end,
        __call = function(_, ...) return get()(...) end,
    })
end

return LauaCore
