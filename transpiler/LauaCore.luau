local LauaCore = {}

function LauaCore.optional(value: any, key: any): any
    if value == nil then return nil end
    return value[key]
end

function LauaCore.coalesce(value: any, fallback: () -> any): any
    if value ~= nil then return value end
    return fallback()
end

return LauaCore
