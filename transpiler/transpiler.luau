local Transpiler = {Version = "3.14"}

-- Embedded runtime sources. Generated scripts are self-contained and never require LauaAsync/LauaCore/LauaSignal.

local LAUA_ASYNC_RUNTIME_SOURCE = [====[
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
    if not isPromise(value) then
        if type(value) == "table" and type(value.Wait) == "function" and type(value.Fire) == "function" then
            return value:Wait()
        end
        return value
    end
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
]====]

local LAUA_CORE_RUNTIME_SOURCE = [====[
local LauaCore = {}

function LauaCore.optional(value: any, key: any): any
    if value == nil then return nil end
    return value[key]
end

function LauaCore.coalesce(value: any, fallback: () -> any): any
    if value ~= nil then return value end
    return fallback()
end


-- Laua: spread merges consecutive array entries and then named keys.
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


-- Laua is: matches a Laua class or one of its ancestors.
function LauaCore.is(value: any, class: any): boolean
    if type(class) ~= "table" or type(value) ~= "table" then return false end
    local candidate = getmetatable(value)
    local visited = {}
    while type(candidate) == "table" and not visited[candidate] do
        if candidate == class then return true end
        visited[candidate] = true
        local meta = getmetatable(candidate)
        candidate = type(meta) == "table" and meta.__index or nil
    end
    return false
end

-- Unlike an eager index, the index expression is not evaluated for nil.
function LauaCore.optionalCall(value: any, callback: (any) -> any): any
    if value == nil then return nil end
    return callback(value)
end

function LauaCore.optionalIndex(value: any, key: () -> any): any
    if value == nil then return nil end
    return value[key()]
end

-- Cache complete result tuples, including nils; cache keys use argument identity.
function LauaCore.memo(callback: (...any) -> ...any): (...any) -> ...any
    local root = {}
    local nilKey = {}
    local terminal = {}
    return function(...)
        local args = table.pack(...)
        local node = root
        for index = 1, args.n do
            local key = args[index]
            if key == nil then key = nilKey end
            local nextNode = node[key]
            if not nextNode then nextNode = {}; node[key] = nextNode end
            node = nextNode
        end
        local cached = node[terminal]
        if not cached then
            cached = table.pack(callback(table.unpack(args, 1, args.n)))
            node[terminal] = cached
        end
        return table.unpack(cached, 1, cached.n)
    end
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
]====]

local LAUA_SIGNAL_RUNTIME_SOURCE = [====[
local Signal = {}
Signal.__index = Signal

function Signal.new(typeNames: {string}?)
    return setmetatable({ _event = Instance.new("BindableEvent"), _destroyed = false, _types = typeNames }, Signal)
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
    local types = self._types
    if types then
        assert(select("#", ...) == #types, "Signal argument count mismatch")
        for index, name in types do
            local value = select(index, ...)
            local optional = name:sub(-1) == "?"
            local typeName = optional and name:sub(1,-2) or name
            if value == nil and optional then continue end
            if typeof(value) ~= typeName then
                if not (typeof(value) == "Instance" and value:IsA(typeName)) then
                    error("Signal expected " .. typeName .. " at argument " .. index, 2)
                end
            end
        end
    end
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
]====]


local function trim(value: string): string
    return (value:match("^%s*(.-)%s*$") or "")
end

local function maskNonCode(source: string): string
    local output = table.create(#source)
    local position = 1
    local quote = nil
    local longClose = nil
    local lineComment = false

    while position <= #source do
        local char = source:sub(position, position)
        local nextChar = source:sub(position + 1, position + 1)
        local pair = char .. nextChar

        if longClose then
            local closing = source:sub(position, position + #longClose - 1) == longClose
            if closing then
                for _ = 1, #longClose do table.insert(output, " ") end
                position += #longClose
                longClose = nil
            else
                table.insert(output, char == "\n" and "\n" or " ")
                position += 1
            end
        elseif lineComment then
            table.insert(output, char == "\n" and "\n" or " ")
            if char == "\n" then lineComment = false end
            position += 1
        elseif quote then
            if char == "\\" and position < #source then
                table.insert(output, " ")
                table.insert(output, " ")
                position += 2
            else
                table.insert(output, char == "\n" and "\n" or " ")
                if char == quote then quote = nil end
                position += 1
            end
        elseif pair == "--" then
            local equals = source:sub(position):match("^%-%-%[(=*)%[")
            if equals then
                local opening = 4 + #equals
                for _ = 1, opening do table.insert(output, " ") end
                position += opening
                longClose = "]" .. equals .. "]"
            else
                table.insert(output, " ")
                table.insert(output, " ")
                lineComment = true
                position += 2
            end
        elseif char == '"' or char == "'" or char == "`" then
            quote = char
            table.insert(output, " ")
            position += 1
        elseif char == "[" then
            local equals = source:sub(position):match("^%[(=*)%[")
            if equals then
                local opening = 2 + #equals
                for _ = 1, opening do table.insert(output, " ") end
                position += opening
                longClose = "]" .. equals .. "]"
            else
                table.insert(output, char)
                position += 1
            end
        else
            table.insert(output, char)
            position += 1
        end
    end

    return table.concat(output)
end

local function splitLines(source: string)
    local lines = {}
    local start = 1

    for index = 1, #source + 1 do
        if index > #source or source:sub(index, index) == "\n" then
            table.insert(lines, {Start = start, Finish = index - 1, Text = source:sub(start, index - 1)})
            start = index + 1
        end
    end

    return lines
end

local function blockStart(line: string): boolean
    if line:match("^abstract%s+class%s+") or line:match("^final%s+class%s+") or line:match("^class%s+") then return true end
    if line:match("^namespace%s+") or line:match("^return%s+namespace%s+") or line:match("^enum%s+") or line:match("^match%s+") then return true end
    if line:match("^constructor%s*%(") or line:match("^defer%s*$") or line:match("^operator%s+") or line:match("^watch%s+[%a_][%w_]*%s*%(") then return true end
    if line:match("^async%s+function%s+") or line:match("^local%s+async%s+function%s+") then return true end
    if line:match("^get%s+[%a_][%w_]*%s*%(") or line:match("^set%s+[%a_][%w_]*%s*%(") then return true end
    if line:match("^function%s+") or line:match("^local%s+function%s+") then return true end
    if line:match("^.*=%s*function%s*%(") then return true end
    if line:match("^if%s+.*%s+then%s*$") or line:match("^for%s+.*%s+do%s*$") then return true end
    if line:match("^while%s+.*%s+do%s*$") or line:match("^do%s*$") or line:match("^repeat%s*$") then return true end
    local remainder = line
    while true do
        local found = false
        for _, modifier in {"public", "private", "protected", "static", "override", "final", "abstract"} do
            local rest = remainder:match("^" .. modifier .. "%s+(.+)$")
            if rest then remainder = rest; found = true; break end
        end
        if not found then break end
    end
    if remainder:match("^function%s+") or remainder:match("^async%s+function%s+") or remainder:match("^get%s+[%a_][%w_]*%s*%(") or remainder:match("^set%s+[%a_][%w_]*%s*%(") then return true end
    return false
end

local function findBlock(source: string, startIndex: number)
    local lines = splitLines(source)
    local lineIndex = nil

    for index, line in lines do
        if startIndex >= line.Start and startIndex <= line.Finish then
            lineIndex = index
            break
        end
    end
    if not lineIndex then error("Cannot find Laua block") end

    local depth = 0
    for index = lineIndex, #lines do
        local line = trim(maskNonCode(lines[index].Text))
        if blockStart(line) then depth += 1 end
        if line:match("^end%s*;?%s*$") or line:match("^until%s+") then
            depth -= 1
            if depth == 0 then return lines[index] end
        end
    end

    error("Missing 'end' in Laua source")
end

local function findKeyword(source: string, keyword: string): number?
    local masked = maskNonCode(source)
    local start = 1

    while true do
        local first, last = masked:find(keyword, start, true)
        if not first then return nil end
        local before = masked:sub(first - 1, first - 1)
        local after = masked:sub(last + 1, last + 1)
        if not before:match("[%w_%.:]") and not after:match("[%w_]") then return first end
        start = last + 1
    end
end

local function normalized(source: string, prefix: string): string
    local lines = splitLines(source)
    local first, last = 1, #lines
    while first <= last and trim(lines[first].Text) == "" do first += 1 end
    while last >= first and trim(lines[last].Text) == "" do last -= 1 end
    if first > last then return "" end
    local minimum = math.huge
    for index = first, last do
        local line = lines[index].Text
        if trim(line) ~= "" then
            local leading = line:match("^[ \t]*") or ""
            minimum = math.min(minimum, #leading)
        end
    end
    local result = {}
    for index = first, last do
        local line = lines[index].Text
        if trim(line) == "" then
            table.insert(result, "")
        else
            table.insert(result, prefix .. line:sub(minimum + 1))
        end
    end
    return table.concat(result, "\n")
end

local transpileSource

local function transpileNew(source: string): string
    while true do
        local start = findKeyword(source, "new")
        if not start then return source end
        local rest = source:sub(start + 3)
        local whitespace, className = rest:match("^(%s+)([%a_][%w_%.]*)")
        if not className then error("Expected class name after 'new'") end
        local after = start + 3 + #whitespace + #className
        local suffix = source:sub(after)
        if suffix:match("^%s*%(") then
            source = source:sub(1, start - 1) .. className .. ".new" .. suffix
        else
            source = source:sub(1, start - 1) .. className .. ".new()" .. suffix
        end
    end
end

local function transpileEnums(source: string): string
    while true do
        local start = findKeyword(source, "enum")
        if not start then return source end
        local headerEnd = source:find("\n", start, true)
        if not headerEnd then error("Enum body expected") end
        local name = trim(source:sub(start, headerEnd - 1)):match("^enum%s+([%a_][%w_]*)$")
        if not name then error("Invalid enum declaration") end
        local closing = findBlock(source, start)
        local body = source:sub(headerEnd + 1, closing.Start - 1)
        local members = {}
        local nextNumber = 0

        for _, row in splitLines(body) do
            local line = trim(row.Text):gsub(",$", "")
            if line == "" or line:match("^%-%-") then continue end
            local memberName, value = line:match("^([%a_][%w_]*)%s*=%s*(.+)$")
            if not memberName then
                memberName = line:match("^([%a_][%w_]*)$")
                if not memberName then error(`Invalid enum member: {line}`) end
                value = tostring(nextNumber)
                nextNumber += 1
            else
                local integer = tonumber(value)
                if integer and integer % 1 == 0 then nextNumber = integer + 1 end
            end
            table.insert(members, `    {memberName} = {value},`)
        end
        local replacement = "local " .. name .. " = table.freeze({\n" .. table.concat(members, "\n") .. "\n})"
        source = source:sub(1, start - 1) .. replacement .. source:sub(closing.Finish + 1)
    end
end

local function parseModifiers(header: string)
    local modifiers = {}
    local rest = trim(header)
    while true do
        local modifier, tail = nil, nil
        if not modifier then
            for _, possible in {"public", "private", "protected", "static", "override", "abstract", "final"} do
                local before = rest:match("^" .. possible .. "%s+(.+)$")
                if before then
                    modifier = possible
                    tail = before
                    break
                end
            end
        end
        if not modifier then break end
        if modifiers[modifier] then error(`Duplicate modifier '{modifier}'`) end
        modifiers[modifier] = true
        rest = tail
    end
    return modifiers, rest
end

local function getParams(params: string): string
    local names = {}
    for part in params:gmatch("[^,]+") do
        local name = trim(part):match("^([%a_][%w_]*)")
        if name then table.insert(names, name) end
    end
    return table.concat(names, ", ")
end

local function replaceSuper(source: string, base: string): string
    local masked = maskNonCode(source)
    local positions = {}
    local cursor = 1

    while true do
        local start, finish, method = masked:find("%f[%w]super%s*:%s*([%a_][%w_]*)%s*%(", cursor)
        if not start then break end
        local open = finish
        local depth = 1
        local close = nil
        for index = open + 1, #masked do
            local char = masked:sub(index, index)
            if char == "(" then depth += 1 end
            if char == ")" then depth -= 1 end
            if depth == 0 then close = index; break end
        end
        if not close then error(`Unclosed super:{method}(`) end
        local args = trim(source:sub(open + 1, close - 1))
        local replacement = base .. "." .. method .. "(self" .. (args ~= "" and ", " .. args or "") .. ")"
        table.insert(positions, {Start = start, Finish = close, Replacement = replacement})
        cursor = close + 1
    end
    for index = #positions, 1, -1 do
        local item = positions[index]
        source = source:sub(1, item.Start - 1) .. item.Replacement .. source:sub(item.Finish + 1)
    end

    masked = maskNonCode(source)
    local changes = {}
    for start, method in masked:gmatch("()super%s*%.%s*([%a_][%w_]*)") do
        local prefix = masked:sub(1, start - 1)
        local original = masked:sub(start):match("^super%s*%.%s*[%a_][%w_]*")
        table.insert(changes, {Start = start, Finish = start + #original - 1, Replacement = base .. "." .. method})
    end
    for index = #changes, 1, -1 do
        local item = changes[index]
        source = source:sub(1, item.Start - 1) .. item.Replacement .. source:sub(item.Finish + 1)
    end
    return source
end

local function transpileClasses(source: string): string
    while true do
        local start = findKeyword(source, "class")
        if not start then return source end
        local lineStart = (source:sub(1, start - 1):match(".*()\n") or 0) + 1
        local prefix = trim(source:sub(lineStart, start - 1))
        if prefix ~= "" and prefix ~= "final" and prefix ~= "abstract" then error(`Invalid class modifier '{prefix}'`) end
        local declarationStart = prefix ~= "" and lineStart or start
        local headerEnd = source:find("\n", start, true)
        if not headerEnd then error("Class body expected") end
        local header = trim(source:sub(start, headerEnd - 1))
        local name, base = header:match("^class%s+([%a_][%w_]*)%s+extends%s+([%a_][%w_%.]*)$")
        if not name then name = header:match("^class%s+([%a_][%w_]*)$") end
        if not name then error(`Invalid class declaration: {header}`) end
        local closing = findBlock(source, start)
        local body = source:sub(headerEnd + 1, closing.Start - 1)
        local lines = splitLines(body)
        local fields, statics, methods, getters, setters, operators, signals, lazies, watchers = {}, {}, {}, {}, {}, {}, {}, {}, {}
        local attributes = {}
        local names = {}
        local ctor = nil
        local index = 1

        while index <= #lines do
            local row = lines[index]
            local headerText = trim(row.Text)
            if headerText == "" or headerText:match("^%-%-") then
                index += 1
                continue
            end
            if headerText:match("^@") then
                table.insert(attributes, headerText)
                index += 1
                continue
            end
            local modifiers, remainder = parseModifiers(headerText)
            local kind, memberName, params = nil, nil, nil
            if not kind then
                for _, possible in {"async function", "function", "get", "set"} do
                    memberName, params = remainder:match("^" .. possible .. "%s+([%a_][%w_]*)%s*%(([^)]*)%)%s*$")
                    if memberName then kind = possible; break end
                end
            end
            if not kind then
                for _, possible in {"async function", "function", "get", "set"} do
                    memberName, params = remainder:match("^" .. possible .. "%s+([%a_][%w_]*)%s*%(([^)]*)%)%s*:%s*.+$")
                    if memberName then kind = possible; break end
                end
            end
            local operatorSymbol, operatorParams = remainder:match("^operator%s+([^%s%(]+)%s*%(([^)]*)%)%s*$")
            if operatorSymbol then
                local operatorMap = { ["+"] = "__add", ["-"] = "__sub", ["*"] = "__mul", ["/"] = "__div", ["//"] = "__idiv", ["%"] = "__mod", ["^"] = "__pow", [".."] = "__concat", ["=="] = "__eq", ["<"] = "__lt", ["<="] = "__le", ["#"] = "__len" }
                local metamethod = operatorMap[operatorSymbol]
                if not metamethod then error(`Unsupported operator '{operatorSymbol}'`) end
                if operatorSymbol == "-" and trim(operatorParams) == "" then metamethod = "__unm" end
                if (metamethod == "__unm" or metamethod == "__len") and trim(operatorParams) ~= "" then error(`Unary operator '{operatorSymbol}' takes no arguments`) end
                if metamethod ~= "__unm" and metamethod ~= "__len" and not trim(operatorParams):match("^[%a_][%w_]*%s*:?[%w_ ]*$") then error("Binary operator requires exactly one parameter") end
                if names[metamethod] then error(`Duplicate operator '{operatorSymbol}'`) end
                if next(modifiers) then error("Operators cannot have modifiers") end
                names[metamethod] = true
                local operatorAt = row.Start + (row.Text:find("operator", 1, true) or 1) - 1
                local operatorEnd = findBlock(body, operatorAt)
                local operatorHeaderEnd = body:find("\n", operatorAt, true)
                local operatorBody = operatorHeaderEnd and body:sub(operatorHeaderEnd + 1, operatorEnd.Start - 1) or ""
                table.insert(operators, {Name = metamethod, Params = operatorParams, Body = operatorBody})
                local nextIndex = nil
                for pos = index + 1, #lines do
                    if lines[pos].Start > operatorEnd.Finish then nextIndex = pos; break end
                end
                index = nextIndex or (#lines + 1)
                continue
            end
            local watchName, watchParams = remainder:match("^watch%s+([%a_][%w_]*)%s*%(([^)]*)%)%s*$")
            if watchName then
                if next(modifiers) or #attributes > 0 then error("watch cannot use modifiers or attributes") end
                if watchers[watchName] then error(`Duplicate watcher '{watchName}'`) end
                local oldParam, newParam = watchParams:match("^%s*([%a_][%w_]*)%s*,%s*([%a_][%w_]*)%s*$")
                if not oldParam or not newParam or oldParam == newParam then error("watch requires two distinct parameters: oldValue, newValue") end
                local at = row.Start + (row.Text:find("watch", 1, true) or 1) - 1
                local done = findBlock(body, at)
                local nextLine = body:find("\n", at, true)
                watchers[watchName] = {Params = watchParams, Body = nextLine and body:sub(nextLine + 1, done.Start - 1) or ""}
                local nextIndex = nil
                for pos = index + 1, #lines do
                    if lines[pos].Start > done.Finish then nextIndex = pos; break end
                end
                index = nextIndex or (#lines + 1)
                continue
            end
            local lazyName, lazyValue = remainder:match("^lazy%s+([%a_][%w_]*)%s*=%s*(.+)$")
            if lazyName then
                if next(modifiers) or #attributes > 0 then error("lazy cannot use modifiers or attributes") end
                if names[lazyName] or lazies[lazyName] then error(`Duplicate member '{lazyName}'`) end
                names[lazyName] = true
                lazies[lazyName] = lazyValue
                index += 1
                continue
            end
            local signalName, signalParams = remainder:match("^signal%s+([%a_][%w_]*)%s*%(([^)]*)%)$")
            if not signalName then signalName = remainder:match("^signal%s+([%a_][%w_]*)$") end
            if signalName then
                if names[signalName] then error(`Duplicate class member '{signalName}'`) end
                if next(modifiers) then error("Signals cannot have modifiers") end
                names[signalName] = true
                local types = {}
                if signalParams and trim(signalParams) ~= "" then
                    for part in signalParams:gmatch("[^,]+") do
                        local typeName = trim(part):match("^[%a_][%w_]*%s*:%s*([%a_][%w_]*%??)$")
                        if not typeName then error("Signals require typed named parameters") end
                        table.insert(types,'"' .. typeName .. '"')
                    end
                end
                table.insert(signals, {Name = signalName, Types = #types > 0 and ("{" .. table.concat(types, ", ") .. "}") or nil})
                index += 1
                continue
            end
            local ctorParams = remainder:match("^constructor%s*%(([^)]*)%)%s*$")
            if kind or ctorParams then
                local kindStart = row.Start + (row.Text:find(kind or "constructor", 1, true) or 1) - 1
                local ending = findBlock(body, kindStart)
                local nextLine = body:find("\n", kindStart, true)
                local memberBody = nextLine and body:sub(nextLine + 1, ending.Start - 1) or ""
                local member = {Name = memberName, Kind = kind or "constructor", Params = params or ctorParams,
                    Body = memberBody, Static = modifiers.static == true, Abstract = modifiers.abstract == true,
                    Final = modifiers.final == true, Override = modifiers.override == true, Attributes = table.concat(attributes, "\n")}
                attributes = {}
                if member.Kind == "constructor" then
                    if ctor then error(`Duplicate constructor in '{name}'`) end
                    if next(modifiers) then error("Constructor cannot use class member modifiers") end
                    ctor = member
                elseif member.Kind == "get" or member.Kind == "set" then
                    if member.Static then error("Static getters/setters are not supported") end
                    if member.Kind == "get" and trim(member.Params) ~= "" then error("Getter cannot take parameters") end
                    if member.Kind == "set" and not trim(member.Params):match("^[%a_][%w_]*%s*:?[%w_ ]*$") then error("Setter requires one parameter") end
                    if member.Kind == "get" then table.insert(getters, member) else table.insert(setters, member) end
                else
                    if names[member.Name] then error(`Duplicate class member '{member.Name}'`) end
                    names[member.Name] = true
                    if member.Override and not base then error(`Cannot override '{member.Name}' without a parent class`) end
                    table.insert(methods, member)
                end
                local nextIndex = nil
                for pos = index + 1, #lines do
                    if lines[pos].Start > ending.Finish then nextIndex = pos; break end
                end
                index = nextIndex or (#lines + 1)
                continue
            end
            local field, value = remainder:match("^([%a_][%w_]*)%s*=%s*(.+)$")
            if not field then field, value = remainder:match("^([%a_][%w_]*)%s*:%s*.-%s*=%s*(.+)$") end
            if not field then error(`Invalid class member: {headerText}`) end
            if names[field] then error(`Duplicate class member '{field}'`) end
            if modifiers.final or modifiers.override or modifiers.abstract then error(`Invalid modifier for field '{field}'`) end
            if #attributes > 0 then error("Attributes are supported on methods only") end
            names[field] = true
            table.insert(modifiers.static and statics or fields, {Name = field, Value = value})
            index += 1
        end

        local properties = {}
        for _, member in getters do properties[member.Name] = true end
        for _, member in setters do properties[member.Name] = true end
        for _, field in fields do
            if properties[field.Name] or lazies[field.Name] then error(`Property '{field.Name}' conflicts with a field`) end
        end
        for lazyName in lazies do
            if properties[lazyName] then error(`Lazy member '{lazyName}' conflicts with getter/setter`) end
        end
        local availableFields = {}
        for _, field in fields do availableFields[field.Name] = true end
        for lazyName in lazies do availableFields[lazyName] = true end
        for watchName in watchers do
            if properties[watchName] then error(`Watched member '{watchName}' conflicts with getter/setter`) end
            if not availableFields[watchName] then error(`watch '{watchName}' requires a declared instance field or lazy property`) end
        end

        local ctorBody = ctor and ctor.Body or ""
        local parentInit = base and `{base}.__init(self{ctor and trim(ctor.Params) ~= "" and ", " .. getParams(ctor.Params) or ""})` or nil
        if base and ctor then
            local ctorLines = splitLines(ctorBody)
            for _, row in ctorLines do
                local text = trim(row.Text)
                if text ~= "" and not text:match("^%-%-") then
                    local args = text:match("^super%s*%((.*)%)%s*$")
                    if args then
                        parentInit = `{base}.__init(self{trim(args) ~= "" and ", " .. args or ""})`
                        ctorBody = ctorBody:sub(1, row.Start - 1) .. ctorBody:sub(row.Finish + 1)
                    end
                    break
                end
            end
        end
        if maskNonCode(ctorBody):find("super%s*%(") then error("super(...) must be first in constructor") end
        if base then ctorBody = replaceSuper(ctorBody, base) end
        if not base and maskNonCode(ctorBody):find("super%s*[:%.%(%[]") then error("super requires a parent class") end

        local generated = {"local " .. name .. " = {}"}
        if base then
            table.insert(generated, `if {base}.__final then error("Cannot extend final class '{base}'") end`)
            table.insert(generated, "setmetatable(" .. name .. ", {__index = " .. base .. "})")
        end
        table.insert(generated, `{name}.__final = {tostring(prefix == "final")}`)
        table.insert(generated, `{name}.__abstract = {tostring(prefix == "abstract")}`)
        local finalEntries = {}
        for _, method in methods do
            if method.Final then table.insert(finalEntries, `["{method.Name}"] = true`) end
        end
        local finalTable = "{" .. table.concat(finalEntries, ", ") .. "}"
        local finalMethods = base and ("setmetatable(" .. finalTable .. ", {__index = " .. base .. ".__finalMethods})") or finalTable
        table.insert(generated, `{name}.__finalMethods = {finalMethods}`)
        table.insert(generated, name .. ".__getters = " .. (base and ("setmetatable({}, {__index = " .. base .. ".__getters})") or "{}"))
        table.insert(generated, name .. ".__setters = " .. (base and ("setmetatable({}, {__index = " .. base .. ".__setters})") or "{}"))
        table.insert(generated, name .. ".__lazy = " .. (base and ("setmetatable({}, {__index = " .. base .. ".__lazy})") or "{}"))
        table.insert(generated, name .. ".__watchers = " .. (base and ("setmetatable({}, {__index = " .. base .. ".__watchers})") or "{}"))
        table.insert(generated, name .. ".__watchedFields = " .. (base and ("setmetatable({}, {__index = " .. base .. ".__watchedFields})") or "{}"))
        for watchName in watchers do table.insert(generated, `{name}.__watchedFields["{watchName}"] = true`) end
        table.insert(generated, `{name}.__index = function(self, key)`)
        table.insert(generated, `    local getter = {name}.__getters[key]`)
        table.insert(generated, `    if getter then return getter(self) end`)
        table.insert(generated, `    local lazy = {name}.__lazy[key]`)
        table.insert(generated, `    if lazy then`)
        table.insert(generated, `        if not self.__lauaInitialized[key] then`)
        table.insert(generated, `            self.__lauaInitialized[key] = true`)
        table.insert(generated, `            local ok, value = pcall(lazy, self)`)
        table.insert(generated, `            if not ok then self.__lauaInitialized[key] = nil; error(value, 0) end`)
        table.insert(generated, `            self.__lauaValues[key] = value`)
        table.insert(generated, `        end`)
        table.insert(generated, `        return self.__lauaValues[key]`)
        table.insert(generated, `    end`)
        table.insert(generated, `    if {name}.__watchedFields[key] then return self.__lauaValues[key] end`)
        table.insert(generated, `    return {name}[key]`)
        table.insert(generated, `end`)
        table.insert(generated, `{name}.__newindex = function(self, key, value)`)
        table.insert(generated, `    local setter = {name}.__setters[key]`)
        table.insert(generated, `    if setter then setter(self, value); return end`)
        table.insert(generated, `    if {name}.__getters[key] then error("Cannot assign to read-only property: " .. key) end`)
        table.insert(generated, `    if {name}.__watchedFields[key] or {name}.__lazy[key] then`)
        table.insert(generated, `        local oldValue = self.__lauaValues[key]`)
        table.insert(generated, `        if {name}.__lazy[key] and not self.__lauaInitialized[key] then self.__lauaInitialized[key] = true end`)
        table.insert(generated, `        self.__lauaValues[key] = value`)
        table.insert(generated, `        local watcher = {name}.__watchers[key]`)
        table.insert(generated, `        if watcher and oldValue ~= value then watcher(self, oldValue, value) end`)
        table.insert(generated, `        return`)
        table.insert(generated, `    end`)
        table.insert(generated, `    rawset(self, key, value)`)
        table.insert(generated, `end`)
        for lazyName, lazyValue in lazies do
            table.insert(generated, `{name}.__lazy["{lazyName}"] = function(self) return {transpileSource(lazyValue)} end`)
        end
        for watchName, watcher in watchers do
            table.insert(generated, `{name}.__watchers["{watchName}"] = function(self, {watcher.Params})`)
            local code = normalized(transpileSource(base and replaceSuper(watcher.Body, base) or watcher.Body), "    ")
            if code ~= "" then table.insert(generated, code) end
            table.insert(generated, "end")
        end
        for _, field in statics do table.insert(generated, `{name}.{field.Name} = {transpileSource(field.Value)}`) end
        table.insert(generated, `function {name}.__init(self{ctor and trim(ctor.Params) ~= "" and ", " .. ctor.Params or ""})`)
        if parentInit then table.insert(generated, "    " .. parentInit) end
        for _, field in fields do
            if watchers[field.Name] then
                table.insert(generated, `    self.__lauaValues["{field.Name}"] = {transpileSource(field.Value)}`)
            else
                table.insert(generated, `    self.{field.Name} = {transpileSource(field.Value)}`)
            end
        end
        for _, item in signals do table.insert(generated, `    self.{item.Name} = __lauaSignal.new({item.Types or ""})`) end
        local innerCtor = normalized(transpileSource(ctorBody), "    ")
        if innerCtor ~= "" then table.insert(generated, innerCtor) end
        table.insert(generated, "end")
        table.insert(generated, `function {name}.new(...)`)
        table.insert(generated, `    if {name}.__abstract then error("Cannot instantiate abstract class '{name}'") end`)
        table.insert(generated, "    local self = setmetatable({__lauaValues = {}, __lauaInitialized = {}}, " .. name .. ")")
        table.insert(generated, `    {name}.__init(self, ...)`)
        table.insert(generated, "    return self")
        table.insert(generated, "end")
        for _, member in getters do
            local nested = base and replaceSuper(member.Body, base) or member.Body
            table.insert(generated, `{name}.__getters.{member.Name} = function(self)`)
            local code = normalized(transpileSource(nested), "    ")
            if code ~= "" then table.insert(generated, code) end
            table.insert(generated, "end")
        end
        for _, member in setters do
            local nested = base and replaceSuper(member.Body, base) or member.Body
            table.insert(generated, `{name}.__setters.{member.Name} = function(self, {member.Params})`)
            local code = normalized(transpileSource(nested), "    ")
            if code ~= "" then table.insert(generated, code) end
            table.insert(generated, "end")
        end
        for _, operator in operators do
            local nested = base and replaceSuper(operator.Body, base) or operator.Body
            table.insert(generated, `function {name}.{operator.Name}(self{trim(operator.Params) ~= "" and ", " .. operator.Params or ""})`)
            local code = normalized(transpileSource(nested), "    ")
            if code ~= "" then table.insert(generated, code) end
            table.insert(generated, "end")
        end
        for _, method in methods do
            if base then table.insert(generated, `if {base}.__finalMethods and {base}.__finalMethods["{method.Name}"] then error("Cannot override final method '{method.Name}'") end`) end
            if base and method.Override then table.insert(generated, `if not {base}.{method.Name} then error("No inherited method '{method.Name}' to override") end`) end
            local nested = base and replaceSuper(method.Body, base) or method.Body
            table.insert(generated, `{method.Attributes ~= "" and method.Attributes .. "\n" or ""}{method.Kind == "async function" and "async " or ""}function {name}{method.Static and "." or ":"}{method.Name}({method.Params})`)
            local code = normalized(transpileSource(nested), "    ")
            if method.Abstract then
                table.insert(generated, `    error("Abstract method '{method.Name}' must be overridden")`)
            elseif code ~= "" then
                table.insert(generated, code)
            end
            table.insert(generated, "end")
        end
        source = source:sub(1, declarationStart - 1) .. table.concat(generated, "\n") .. source:sub(closing.Finish + 1)
    end
end

local function transpileNamespaces(source: string): string
    while true do
        local start = findKeyword(source, "namespace")
        if not start then return source end
        local headerEnd = source:find("\n", start, true)
        if not headerEnd then error("Namespace body expected") end
        local name = trim(source:sub(start, headerEnd - 1)):match("^namespace%s+([%a_][%w_]*)$")
        if not name then error("Invalid namespace declaration") end
        local closing = findBlock(source, start)
        local body = source:sub(headerEnd + 1, closing.Start - 1)
        local output = {}
        local depth = 0
        for _, line in splitLines(body) do
            local raw = line.Text
            local code = trim(maskNonCode(raw))
            local fn = depth == 0 and (code:match("^function%s+([%a_][%w_]*)%s*%(([^)]*)%)%s*$") or code:match("^async%s+function%s+([%a_][%w_]*)%s*%(([^)]*)%)%s*$")) or nil
            local field = depth == 0 and code:match("^([%a_][%w_]*)%s*=%s*.+$") or nil
            if fn then
                local newLine = raw:gsub("function%s+" .. fn, "function " .. name .. "." .. fn, 1)
                table.insert(output, newLine)
            elseif field then
                local newLine = raw:gsub("^([ \t]*)" .. field, "%1" .. name .. "." .. field, 1)
                table.insert(output, newLine)
            else
                table.insert(output, raw)
            end
            if blockStart(code) then depth += 1 end
            if code:match("^end%s*;?%s*$") or code:match("^until%s+") then depth -= 1 end
        end
        local transformed = normalized(transpileSource(table.concat(output, "\n")), "    ")
        local expression = "(function()\n    local " .. name .. " = {}\n" .. transformed .. "\n    return " .. name .. "\nend)()"
        local lineStart = (source:sub(1, start - 1):match(".*()\n") or 0) + 1
        local prefix = trim(source:sub(lineStart, start - 1))
        if prefix == "return" then
            source = source:sub(1, start - 1) .. expression .. source:sub(closing.Finish + 1)
        elseif prefix == "" then
            source = source:sub(1, start - 1) .. `local {name} = {expression}` .. source:sub(closing.Finish + 1)
        else
            error("namespace must be standalone or directly returned")
        end
    end
end

transpileSource = function(source: string): string
    source = transpileEnums(source)
    source = transpileNamespaces(source)
    source = transpileClasses(source)
    source = transpileNew(source)
    return source
end

local function replaceRange(source: string, first: number, last: number, replacement: string): string
    return source:sub(1, first - 1) .. replacement .. source:sub(last + 1)
end

local function transpileExports(source: string): (string, {string})
    local names = {}
    local seen = {}
    local rows = {}
    for _, row in splitLines(source) do
        local raw = row.Text
        local masked = trim(maskNonCode(raw))
        if not masked:match("^export%s+") or masked:match("^export%s+type%s+") then
            table.insert(rows, raw)
            continue
        end
        local indent, rest = raw:match("^([ \t]*)export%s+(.+)$")
        if not rest then error("Invalid export statement") end
        local name = rest:match("^final%s+class%s+([%a_][%w_]*)") or rest:match("^abstract%s+class%s+([%a_][%w_]*)")
            or rest:match("^class%s+([%a_][%w_]*)") or rest:match("^enum%s+([%a_][%w_]*)")
            or rest:match("^namespace%s+([%a_][%w_]*)") or rest:match("^async%s+function%s+([%a_][%w_]*)")
            or rest:match("^function%s+([%a_][%w_]*)") or rest:match("^local%s+function%s+([%a_][%w_]*)")
            or rest:match("^local%s+async%s+function%s+([%a_][%w_]*)") or rest:match("^local%s+([%a_][%w_]*)%s*=") or rest:match("^local%s+([%a_][%w_]*)%s*:%s*.-%s*=")
        if not name then error(`Unsupported export declaration: {rest}`) end
        if seen[name] then error(`Duplicate export '{name}'`) end
        seen[name] = true
        table.insert(names, name)
        table.insert(rows, indent .. rest)
    end
    return table.concat(rows, "\n"), names
end

local function transpileImports(source: string): string
    local result = {}
    for _, row in splitLines(source) do
        local raw = row.Text
        local line = trim(raw)
        if not trim(maskNonCode(raw)):match("^import%f[%W]") then
            table.insert(result, raw)
            continue
        end
        local name, path = line:match('^import%s+([%a_][%w_]*)%s+from%s+"([^"\n]+)"%s*$')
        if not name then name, path = line:match("^import%s+([%a_][%w_]*)%s+from%s+'([^'\n]+)'%s*$") end
        local named, namedPath = line:match('^import%s+%{(.-)%}%s+from%s+"([^"\n]+)"%s*$')
        if not named then named, namedPath = line:match("^import%s+%{(.-)%}%s+from%s+'([^'\n]+)'%s*$") end
        if not name and not named then error("Expected import Name or import {Name} from \"./Module\"") end
        path = path or namedPath
        if path:sub(1, 2) ~= "./" and path:sub(1, 3) ~= "../" then error("Import path must be relative to script: ./ or ../") end
        local current = "script.Parent"
        local rest = path
        while rest:sub(1, 3) == "../" do
            current ..= ".Parent"
            rest = rest:sub(4)
        end
        if rest:sub(1, 2) == "./" then rest = rest:sub(3) end
        if rest == "" then error("Import must name a ModuleScript") end
        for segment in rest:gmatch("[^/]+") do
            if not segment:match("^[%a_][%w_]*$") then error(`Invalid module path segment '{segment}'`) end
            current ..= `:WaitForChild("{segment}")`
        end
        local indent = raw:match("^[ \t]*") or ""
        if named then
            local locals = {}
            local used = {}
            for segment in named:gmatch("[^,]+") do
                local external, alias = trim(segment):match("^([%a_][%w_]*)%s+as%s+([%a_][%w_]*)$")
                if not external then external = trim(segment); alias = external end
                if not external:match("^[%a_][%w_]*$") or used[alias] then error(`Invalid or duplicate import '{segment}'`) end
                used[alias] = true
                table.insert(locals, {External = external, Local = alias})
            end
            if #locals == 0 then error("Named import cannot be empty") end
            local temporary = `__lauaImported{#result + 1}`
            table.insert(result, indent .. `local {temporary} = require({current})`)
            for _, entry in locals do table.insert(result, indent .. `local {entry.Local} = {temporary}.{entry.External}`) end
        else
            table.insert(result, indent .. `local {name} = require({current})`)
        end
    end
    return table.concat(result, "\n")
end

local function transpileDestructuring(source: string): string
    local result = {}
    local serial = 0
    for _, row in splitLines(source) do
        local raw = row.Text
        if not trim(maskNonCode(raw)):match("^local%s*%{") then
            table.insert(result, raw)
            continue
        end
        local indent, names, expression = raw:match("^([ \t]*)local%s*%{([^{}]+)%}%s*=%s*(.-)%s*$")
        if not names or trim(expression) == "" then error("Expected local {a, b} = tableExpression") end
        serial += 1
        local temporary = `__lauaDestructure{serial}`
        table.insert(result, indent .. `local {temporary} = {expression}`)
        local found = {}
        for segment in names:gmatch("[^,]+") do
            local key, alias = trim(segment):match("^([%a_][%w_]*)%s*:%s*([%a_][%w_]*)$")
            if not key then key = trim(segment); alias = key end
            if not key:match("^[%a_][%w_]*$") or found[alias] then error(`Invalid or duplicate destructured name '{segment}'`) end
            found[alias] = true
            table.insert(result, indent .. `local {alias} = {temporary}.{key}`)
        end
    end
    return table.concat(result, "\n")
end

local function splitPatternFields(source: string): {string}
    local fields = {}
    local depth = 0
    local start = 1
    local masked = maskNonCode(source)
    for index = 1, #masked do
        local char = masked:sub(index, index)
        if char == "{" then depth += 1 end
        if char == "}" then depth -= 1 end
        if depth < 0 then error("Invalid match table pattern") end
        if char == "," and depth == 0 then
            table.insert(fields, trim(source:sub(start, index - 1)))
            start = index + 1
        end
    end
    if depth ~= 0 then error("Unclosed match table pattern") end
    table.insert(fields, trim(source:sub(start)))
    return fields
end

local function matchPatternCondition(value: string, pattern: string): string
    pattern = trim(pattern)
    if pattern:sub(1, 1) ~= "{" then return `{value} == {pattern}` end
    if pattern:sub(-1) ~= "}" then error("Unclosed match table pattern") end
    local parts = {`type({value}) == "table"`}
    local contents = trim(pattern:sub(2, -2))
    if contents == "" then return `({table.concat(parts, " and ")})` end
    local fields = splitPatternFields(contents)
    local seen = {}
    for _, part in fields do
        local name, expected = part:match("^([%a_][%w_]*)%s*=%s*(.+)$")
        if not name then error(`Invalid match table pattern field: {part}`) end
        if seen[name] then error(`Duplicate match table field '{name}'`) end
        seen[name] = true
        table.insert(parts, matchPatternCondition(value .. "." .. name, expected))
    end
    return "(" .. table.concat(parts, " and ") .. ")"
end

local function matchBranchCondition(value: string, expression: string): string
    local pattern, guard = expression:match("^(.-)%s+if%s+(.+)$")
    if not pattern then pattern = expression end
    local condition = matchPatternCondition(value, pattern)
    if guard then condition ..= " and (" .. guard .. ")" end
    return condition
end

local function transpileMatches(source: string): string
    local serial = 0
    while true do
        local masked = maskNonCode(source)
        local start = nil
        local from = 1
        while true do
            local position = findKeyword(source:sub(from), "match")
            if not position then break end
            position += from - 1
            local lineStart = (source:sub(1, position - 1):match(".*()\n") or 0) + 1
            if trim(masked:sub(lineStart, position - 1)) == "" then start = position end
            from = position + 5
        end
        if not start then return source end
        local headerEnd = source:find("\n", start, true)
        if not headerEnd then error("match needs case branches") end
        local expression = trim(source:sub(start + 5, headerEnd - 1))
        if expression == "" then error("match requires an expression") end
        local closing = findBlock(source, start)
        local body = source:sub(headerEnd + 1, closing.Start - 1)
        local branches = {}
        local active = nil
        local depth = 0
        for _, row in splitLines(body) do
            local code = trim(maskNonCode(row.Text))
            local case = trim(row.Text):match("^case%s+(.+)$")
            local isDefault = code:match("^default%s*$") ~= nil
            if depth == 0 and (code:match("^case%f[%W]") or isDefault) then
                if code:match("^case%f[%W]") and (not case or trim(case) == "") then error("case requires a value") end
                if isDefault and #branches == 0 then error("default must follow a case") end
                if isDefault then
                    for _, branch in branches do if branch.Default then error("Duplicate default branch") end end
                elseif active and active.Default then error("case cannot follow default") end
                active = {Value = case, Default = isDefault, Lines = {}}
                table.insert(branches, active)
            elseif active then
                table.insert(active.Lines, row.Text)
            elseif code ~= "" then error("match body requires case or default") end
            if blockStart(code) then depth += 1 end
            if code:match("^end%s*;?%s*$") or code:match("^until%s+") then depth -= 1 end
        end
        if #branches == 0 then error("match requires at least one case") end
        serial += 1
        local variable = `__lauaMatch{serial}`
        local generated = {"do", `    local {variable} = {expression}`}
        for index, branch in branches do
            if branch.Default then
                table.insert(generated, "    else")
            else
                table.insert(generated, `    {index == 1 and "if" or "elseif"} {matchBranchCondition(variable, branch.Value)} then`)
            end
            local content = normalized(table.concat(branch.Lines, "\n"), "        ")
            if content ~= "" then table.insert(generated, content) end
        end
        table.insert(generated, "    end")
        table.insert(generated, "end")
        source = replaceRange(source, start, closing.Finish, table.concat(generated, "\n"))
    end
end

local function expressionLeft(masked: string, endAt: number): number?
    local cursor = endAt
    while cursor > 0 and masked:sub(cursor, cursor):match("[ \t]") do cursor -= 1 end
    if cursor == 0 then return nil end
    local endChar = masked:sub(cursor, cursor)
    if endChar == ")" or endChar == "]" then
        local opener = endChar == ")" and "(" or "["
        local depth = 1
        cursor -= 1
        while cursor >= 1 do
            local char = masked:sub(cursor, cursor)
            if char == endChar then depth += 1 end
            if char == opener then depth -= 1 end
            if depth == 0 then break end
            cursor -= 1
        end
        if cursor < 1 then return nil end
        local prev = cursor - 1
        while prev > 0 and masked:sub(prev, prev):match("[ \t]") do prev -= 1 end
        if masked:sub(prev, prev):match("[%w_]") then return expressionLeft(masked, prev) end
        return cursor
    end
    if not endChar:match("[%w_]") then return nil end
    while cursor > 0 and masked:sub(cursor, cursor):match("[%w_]") do cursor -= 1 end
    local beginning = cursor + 1
    if beginning > 1 and (masked:sub(beginning - 1, beginning - 1) == "." or masked:sub(beginning - 1, beginning - 1) == ":") then
        local previous = expressionLeft(masked, beginning - 2)
        if previous then return previous end
    end
    return beginning
end

local function expressionRight(source: string, startAt: number): number?
    local cursor = startAt
    while cursor <= #source and source:sub(cursor, cursor):match("[ \t]") do cursor += 1 end
    local first = source:sub(cursor, cursor)
    if first == "'" or first == '"' then
        local quote = first
        cursor += 1
        while cursor <= #source do
            local char = source:sub(cursor, cursor)
            if char == "\\" then cursor += 2 elseif char == quote then cursor += 1; break else cursor += 1 end
        end
    elseif first == "(" then
        local depth = 1
        cursor += 1
        while cursor <= #source and depth > 0 do
            local char = source:sub(cursor, cursor)
            if char == "(" then depth += 1 elseif char == ")" then depth -= 1 end
            cursor += 1
        end
        if depth ~= 0 then return nil end
    else
        local prefix = source:sub(cursor):match("^[%a_][%w_]*") or source:sub(cursor):match("^%-?[%d%.]+")
        if not prefix then return nil end
        cursor += #prefix
    end
    while cursor <= #source do
        local suffix = source:sub(cursor):match("^%s*[%.:]([%a_][%w_]*)")
        local spaces = source:sub(cursor):match("^[ \t]*") or ""
        if suffix then
            cursor += #spaces + 1 + #suffix
        elseif source:sub(cursor + #spaces, cursor + #spaces) == "(" then
            cursor += #spaces + 1
            local depth = 1
            while cursor <= #source and depth > 0 do
                local char = source:sub(cursor, cursor)
                if char == "(" then depth += 1 elseif char == ")" then depth -= 1 end
                cursor += 1
            end
            if depth ~= 0 then return nil end
        else
            break
        end
    end
    return cursor - 1
end

local function transpileOptional(source: string): (string, boolean)
    local changed = false
    while true do
        local masked = maskNonCode(source)
        local pos = masked:find("?.", 1, true)
        if not pos then return source, changed end
        local left = expressionLeft(masked, pos - 1)
        local member = masked:sub(pos + 2):match("^([%a_][%w_]*)")
        if not left then error("Optional chaining requires a receiver") end
        if masked:sub(pos+2,pos+2) == "[" then
            local depth, closing = 1, nil
            for i = pos+3, #masked do
                local char = masked:sub(i,i)
                if char == "[" then depth += 1 elseif char == "]" then depth -= 1 end
                if depth == 0 then closing = i; break end
            end
            if not closing then error("Unclosed optional index") end
            local key = trim(source:sub(pos+3,closing-1))
            if key == "" then error("Optional index requires a key") end
            local receiver = trim(source:sub(left,pos-1))
            source = replaceRange(source,left,closing,'__lauaCore.optionalIndex(' .. receiver .. ', function() return ' .. key .. ' end)')
            changed = true
            continue
        end
        local colon = masked:sub(pos+2,pos+2) == ":"
        if colon then member = masked:sub(pos+3):match("^([%a_][%w_]*)") end
        if not member then error("Optional chaining expects a property, index, or method") end
        local memberEnd = pos + 1 + #member + (colon and 1 or 0)
        local gap = masked:sub(memberEnd + 1):match("^[ \t]*") or ""
        local openAt = memberEnd + 1 + #gap
        if masked:sub(openAt,openAt) == "(" then
            local depth, closing = 1, nil
            for i = openAt+1, #masked do
                local char = masked:sub(i,i)
                if char == "(" then depth += 1 elseif char == ")" then depth -= 1 end
                if depth == 0 then closing = i; break end
            end
            if not closing then error("Unclosed optional method call") end
            local receiver = trim(source:sub(left,pos-1))
            local args = source:sub(openAt+1,closing-1)
            local invocation = colon and ("__lauaReceiver:" .. member) or ("__lauaReceiver." .. member)
            source = replaceRange(source,left,closing,"__lauaCore.optionalCall(" .. receiver .. ", function(__lauaReceiver) return " .. invocation .. "(" .. args .. ") end)")
            changed = true
            continue
        end
        if colon then error("Optional colon access requires a method call") end
        local base = trim(source:sub(left, pos - 1))
        local replacement = `__lauaCore.optional({base}, "{member}")`
        source = replaceRange(source, left, pos + 1 + #member, replacement)
        changed = true
    end
end

local function transpileCoalescingAssign(source: string): string
    local output = {}
    local serial = 0
    for _, row in splitLines(source) do
        local raw = row.Text
        local masked = maskNonCode(raw)
        local at = masked:find("??=", 1, true)
        if not at then
            table.insert(output, raw)
            continue
        end
        local indent = raw:match("^[ \t]*") or ""
        local target = trim(raw:sub(1, at - 1))
        local fallback = trim(raw:sub(at + 3))
        if fallback == "" then error("??= requires a fallback value") end
        local closure = fallback:find("--", 1, true) and ("\n" .. indent .. "end") or " end"
        if target:match("^[%a_][%w_]*$") then
            table.insert(output, indent .. `if {target} == nil then {target} = {fallback}{closure}`)
        else
            serial += 1
            local receiver, member = target:match("^(.-)%.([%a_][%w_]*)$")
            local key = nil
            if not receiver then receiver, key = target:match("^(.-)%[([^%[%]]+)%]$") end
            if not receiver or trim(receiver) == "" then error("??= expects a variable, property or indexed target") end
            local temporary = `__lauaAssignTarget{serial}`
            local index = member and ("." .. member) or (`[{key}]`)
            if key then
                local keyTemp = `__lauaAssignKey{serial}`
                table.insert(output, indent .. `do local {temporary} = {receiver}; local {keyTemp} = {key}; if {temporary}[{keyTemp}] == nil then {temporary}[{keyTemp}] = {fallback}{closure} end`)
            else
                table.insert(output, indent .. `do local {temporary} = {receiver}; if {temporary}{index} == nil then {temporary}{index} = {fallback}{closure} end`)
            end
        end
    end
    return table.concat(output, "\n")
end

local function transpileCoalescing(source: string): (string, boolean)
    local changed = false
    while true do
        local masked = maskNonCode(source)
        local pos = nil
        local cursor = 1
        while true do
            local nextPos = masked:find("??", cursor, true)
            if not nextPos then break end
            pos = nextPos
            cursor = nextPos + 2
        end
        if not pos then return source, changed end
        local left = expressionLeft(masked, pos - 1)
        local right = expressionRight(source, pos + 2)
        if not left or not right then error("Nil coalescing expects value ?? fallback") end
        local before = trim(masked:sub(math.max(1, left - 8), left - 1))
        local after = trim(masked:sub(right + 1):match("^[^\n]*") or "")
        if before:match("[%+%-%*/%%%^<>~&|]$") or (before:match("%f[%a]and$") or before:match("%f[%a]or$")) then
            error("Wrap compound ?? left operands in parentheses")
        end
        if after:match("^[%+%-%*/%%%^<>=~&|]") or after:match("^%.%.") or (after:match("^and%f[%W]") or after:match("^or%f[%W]")) then
            error("Wrap compound ?? fallbacks in parentheses")
        end
        local a = trim(source:sub(left, pos - 1))
        local b = trim(source:sub(pos + 2, right))
        local replacement = `__lauaCore.coalesce({a}, function() return {b} end)`
        source = replaceRange(source, left, right, replacement)
        changed = true
    end
end


-- Transform only non-comment/non-string tokens, so keywords in user data are not rewritten.
local function transpileIsOperator(source: string): string
    local position = 1
    while true do
        local masked = maskNonCode(source)
        local first, last = masked:find('%f[%w]is%f[%W]', position)
        if not first then return source end
        local before = masked:sub(first - 1, first - 1)
        local linePrefix = masked:sub((masked:sub(1,first-1):match('.*()\n') or 0) + 1, first-1)
        if before == '.' or before == ':' or linePrefix:match('function%s+$') then position = last + 1; continue end
        local left = expressionLeft(masked, first - 1)
        local rightText = masked:sub(last + 1)
        local spacing, className = rightText:match('^([ \t]+)([%a_][%w_]*)')
        if not left or not className then error('is expects: value is ClassName') end
        local after = last + #spacing + #className
        local beforeValue = trim(source:sub(left, first - 1))
        source = replaceRange(source, left, after, '__lauaCore.is(' .. beforeValue .. ', ' .. className .. ')')
        position = left + 15
    end
end

-- Pipeline stages must be named functions. Side effects in the input run once.
local function transpilePipelines(source: string): string
    local result = {}
    for _, line in splitLines(source) do
        local raw, masked = line.Text, maskNonCode(line.Text)
        if not masked:find('|>', 1, true) then table.insert(result, raw); continue end
        local separators = {}
        local cursor = 1
        while true do
            local at = masked:find('|>', cursor, true)
            if not at then break end
            table.insert(separators, at)
            cursor = at + 2
        end
        local before = raw:sub(1, separators[1] - 1)
        local assignment, initial = before:match('^(.-=%s*)(.+)$')
        if not assignment then
            assignment = before:match('^(%s*return%s+)')
            initial = assignment and before:sub(#assignment + 1) or nil
        end
        if not assignment then error('Pipeline requires assignment or return: local x = value |> Function') end
        local value = trim(initial or '')
        if value == '' then error('Pipeline input is empty') end
        for index, at in separators do
            local ending = separators[index + 1] and separators[index + 1] - 1 or #raw
            local stage = trim(raw:sub(at + 2, ending))
            if not stage:match('^[%a_][%w_%.]*$') then error('Pipeline stages must be function names') end
            value = stage .. '(' .. value .. ')'
        end
        table.insert(result, assignment .. value)
    end
    return table.concat(result, '\n')
end

-- Memoized functions use the bundled LauaCore runtime.
local function transpileMemo(source: string): string
    while true do
        local masked = maskNonCode(source)
        local first = masked:find('%f[%w]memo%f[%W]')
        while first and (masked:sub(first-1,first-1) == '.' or masked:sub(first-1,first-1) == ':') do
            first = masked:find('%f[%w]memo%f[%W]', first+4)
        end
        if not first then return source end
        local lineStart = (source:sub(1, first-1):match('.*()\n') or 0) + 1
        if trim(source:sub(lineStart, first-1)) ~= '' then error('memo must start a declaration') end
        local headerEnd = source:find('\n', first, true)
        if not headerEnd then error('memo requires a function body') end
        local header = trim(source:sub(first, headerEnd-1))
        local funcName = header:match('^memo%s+function%s+([%a_][%w_]*)%s*%(')
        local isLocal = false
        if not funcName then
            funcName = header:match('^memo%s+local%s+function%s+([%a_][%w_]*)%s*%(')
            isLocal = true
        end
        if not funcName then error('memo supports named functions only: memo function Name(...)') end
        local standardHeader = header:gsub('^memo%s+', '', 1)
        local rewritten = source:sub(1, first-1) .. standardHeader .. source:sub(headerEnd)
        local finish = findBlock(rewritten, first)
        local indent = source:sub(lineStart, first-1)
        local wrapper = '\n' .. indent .. funcName .. ' = __lauaCore.memo(' .. funcName .. ')'
        source = rewritten:sub(1, finish.Finish) .. wrapper .. rewritten:sub(finish.Finish + 1)
    end
end

-- Default parameters: nil triggers the default, false is retained.
local function transpileParameterDefaults(source: string): string
    local rows = {}
    for _, row in splitLines(source) do
        local raw = row.Text
        local masked = maskNonCode(raw)
        local openAt = masked:find('%f[%w]function%f[%W]')
        if openAt then
            local parenAt = masked:find('(', openAt, true)
            local closeAt = parenAt and masked:find(')', parenAt, true)
            if parenAt and closeAt then
                local params = raw:sub(parenAt+1,closeAt-1)
                if params:find('=',1,true) then
                    local parsed, initializers = {}, {}
                    for piece in (params .. ','):gmatch('(.-),') do
                        local left, default = piece:match('^%s*(.-)%s*=%s*(.-)%s*$')
                        if left then
                            local var = left:match('^([%a_][%w_]*)')
                            if not var then error('Invalid default parameter') end
                            table.insert(parsed, trim(left))
                            table.insert(initializers, ('if %s == nil then %s = %s end'):format(var,var,default))
                        else
                            table.insert(parsed, trim(piece))
                        end
                    end
                    raw = raw:sub(1,parenAt) .. table.concat(parsed, ', ') .. raw:sub(closeAt)
                    table.insert(rows,raw)
                    local indent = (raw:match('^[ \t]*') or '') .. '    '
                    for _, statement in initializers do table.insert(rows,indent .. statement) end
                    continue
                end
            end
        end
        table.insert(rows,raw)
    end
    return table.concat(rows,'\n')
end

-- Compile-time branch selection; only these explicit directives have special meaning.
local function preprocessMode(source: string, mode: string): string
    local out, stack = {}, {}
    local active = true
    for _, row in splitLines(source) do
        local line = row.Text
        local flag = line:match('^%s*%-%-#if%s+(%u+)%s*$')
        if flag then
            if flag ~= 'DEBUG' and flag ~= 'RELEASE' and flag ~= 'DEVELOPMENT' then error('Unknown --#if mode ' .. flag) end
            table.insert(stack, {Parent=active, Matched=mode:upper()==flag, Else=false})
            active = active and mode:upper()==flag
            table.insert(out,'')
        elseif line:match('^%s*%-%-#else%s*$') then
            local top = stack[#stack]
            if not top or top.Else then error('Unexpected --#else') end
            top.Else = true
            active = top.Parent and not top.Matched
            table.insert(out,'')
        elseif line:match('^%s*%-%-#end%s*$') then
            local top = table.remove(stack)
            if not top then error('Unexpected --#end') end
            active = top.Parent
            table.insert(out,'')
        else
            table.insert(out,active and line or '')
        end
    end
    if #stack > 0 then error('Missing --#end for compile-time branch') end
    return table.concat(out,'\n')
end

-- Laua: source-level sugar. Only fully supported forms are lowered.
-- Keep unsupported proposals from leaking malformed syntax into generated Luau.
local function validatePendingFeatures(source: string)
    for _, row in splitLines(source) do
        local line = trim(maskNonCode(row.Text))
        local reasons = {
            {"^[%a_][%w_]*:%s*(for|while|repeat)%s", "Labeled loop exits"},
            {"^break%s+[%a_][%w_]*$", "Labeled break"},
            {"^continue%s+[%a_][%w_]*$", "Labeled continue"},
            {"^unique%s+type%s+", "Nominal/unique types"},
            {"^type%s+[%a_][%w_]*%s*=%s*%[", "Typed positional tables"},
            {"^type%s+[%a_][%w_]*%s*=%s*truthy%s*$", "Truthy type aliases"},
            {"^type%s+[%a_][%w_]*%s*=%s*falsy%s*$", "Falsy type aliases"},
        }
        for _, entry in reasons do
            -- Plain pattern alternatives are handled explicitly below.
            if entry[2] ~= "Labeled loop exits" and line:match(entry[1]) then
                error(entry[2] .. " are specified for Laua but not yet implemented in the transpiler")
            end
        end
        if line:match("^[%a_][%w_]*:%s*for%s") or line:match("^[%a_][%w_]*:%s*while%s") or line:match("^[%a_][%w_]*:%s*repeat%s") then
            error("Labeled loop exits are specified for Laua but not yet implemented")
        end
        if line:match("^function%s+[%a_][%w_%.:]*%s*<[^>]*:%s*[%a_][%w_]*[^>]*>") then
            error("Constrained generics need a real type checker and are not yet implemented")
        end
        if line:find("regex.match", 1, true) or line:find("regex.find", 1, true) then
            error("Full regular expressions need a regex runtime and are not yet implemented")
        end
    end
end

local function transpileAdditionalSyntax(source: string): string
    local rows = {}
    local sequence = 0
    for _, row in splitLines(source) do
        local original = row.Text
        local stripped = trim(original)
        local masked = trim(maskNonCode(original))
        local indent = original:match("^[ \t]*") or ""

        -- Editor-only @nolint is consumed here, not passed to Roblox.
        if stripped:match("^@nolint%s*%(") and masked:match("^@nolint%s*%(") then
            local names = stripped:match('^@nolint%s*%(%s*"([%w_, ]+)"%s*%)%s*$')
            if not names then error('Expected @nolint("WarningName")') end
            table.insert(rows, indent .. "-- Laua lint suppression: " .. names)
            continue
        end

        -- Single-expression lambda, with ordinary identifier parameters.
        if masked:find("=>", 1, true) then
            local prefix, params, expression = original:match("^(.-)(%b())%s*=>%s*(.-)%s*$")
            if not prefix or expression == "" then error("Arrow functions require (parameters) => expression on one line") end
            local inside = params:sub(2, -2)
            for item in inside:gmatch("[^,]+") do
                if not trim(item):match("^[%a_][%w_]*%s*:?%s*[%w_%.%?]*$") then error("Invalid arrow function parameter") end
            end
            original = prefix .. "function" .. params .. " return " .. expression .. " end"
        end

        -- The v22 spread form accepts spreads-only table literals on the RHS.
        if trim(maskNonCode(original)):find("%.%.%.[%a_]") and original:find("{", 1, true) then
            local prefix, values = original:match("^(.-)%{%s*(%.%.%.[^{}]-)%s*%}%s*$")
            if prefix and values then
                local parts = {}
                for part in values:gmatch("[^,]+") do
                    local variable = trim(part):match("^%.%.%.%s*([%a_][%w_%.]*)$")
                    if not variable then error('Spread literal expects {...first, ...second}') end
                    table.insert(parts, variable)
                end
                original = prefix .. '__lauaCore.spread(' .. table.concat(parts, ', ') .. ')'
            end
        end

        -- Slice supports a simple variable/property expression, with optional bounds.
        local before, owner, first, last, suffix = original:match("^(.-)([%a_][%w_%.]*)%[([%-%d]*)%s*:%s*([%-%d]*)%](.*)$")
        if owner and maskNonCode(original):find("%[%s*%-?%d*%s*:%s*%-?%d*%s*%]") then
            if first == "" and last == "" then error("Slice requires at least one bound") end
            original = before .. "__lauaCore.slice(" .. owner .. ", " .. (first ~= "" and first or "nil") .. ", " .. (last ~= "" and last or "nil") .. ")" .. suffix
        end

        -- Methods in the core runtime rather than mutating the built-in table library.
        for _, method in {"filter", "map", "reduce", "findWhere"} do
            local maskedOriginal = maskNonCode(original)
            local search = 1
            while true do
                local found = maskedOriginal:find("table%." .. method .. "%s*%(", search)
                if not found then break end
                original = original:sub(1, found - 1) .. "__lauaCore." .. original:sub(found)
                maskedOriginal = maskNonCode(original)
                search = found + #"__lauaCore.table." + #method
            end
        end

        -- Explicit lazy import: require is delayed until the proxy is used.
        local alias, path = trim(original):match('^import%s+lazy%s+([%a_][%w_]*)%s+from%s+"([^"]+)"%s*$')
        if alias then
            if path:sub(1, 2) ~= "./" and path:sub(1, 3) ~= "../" then error("Lazy import paths must start with ./ or ../") end
            local target = "script.Parent"
            local rest = path
            while rest:sub(1, 3) == "../" do
                target ..= ".Parent"
                rest = rest:sub(4)
            end
            if rest:sub(1, 2) == "./" then rest = rest:sub(3) end
            if rest == "" then error("Lazy import path must name a ModuleScript") end
            for segment in rest:gmatch("[^/]+") do
                if not segment:match("^[%a_][%w_]*$") then error(`Invalid lazy import path segment '{segment}'`) end
                target ..= ':WaitForChild("' .. segment .. '")'
            end
            table.insert(rows, indent .. 'local ' .. alias .. ' = __lauaCore.lazyModule(function() return require(' .. target .. ') end)')
            continue
        end

        table.insert(rows, original)
    end
    return table.concat(rows, "\n")
end

local function transpileExtensions(source: string): string
    source = transpileImports(source)
    source = transpileDestructuring(source)
    source = transpileMatches(source)
    source = (transpileOptional(source))
    source = (transpileCoalescing(source))
    return source
end

local function transpileDefers(source: string): string
    local functionLines = {}
    for _, line in splitLines(source) do
        local code = trim(maskNonCode(line.Text))
        if code:match("^function%s+") or code:match("^local%s+function%s+") or code:match("^async%s+function%s+") or code:match("^local%s+async%s+function%s+") or code:match("=%s*function%s*%(") then
            local at = line.Start + (line.Text:find("function", 1, true) or 1) - 1
            table.insert(functionLines, at)
        end
    end

    for index = #functionLines, 1, -1 do
        local start = functionLines[index]
        local closing = findBlock(source, start)
        local headerEnd = source:find("\n", start, true)
        if not headerEnd then continue end
        local body = source:sub(headerEnd + 1, closing.Start - 1)
        local deferBlocks = {}
        for _, line in splitLines(body) do
            if trim(maskNonCode(line.Text)) == "defer" then
                local at = line.Start + (line.Text:find("defer", 1, true) or 1) - 1
                local done = findBlock(body, at)
                local codeStart = body:find("\n", at, true)
                local content = codeStart and body:sub(codeStart + 1, done.Start - 1) or ""
                local replacement = `table.insert(__lauaDefers, function()\n{normalized(content, "    ")}\nend)`
                table.insert(deferBlocks, {Start = at, Finish = done.Finish, Replacement = replacement})
            end
        end
        if #deferBlocks == 0 then continue end
        for blockIndex = #deferBlocks, 1, -1 do
            local block = deferBlocks[blockIndex]
            body = body:sub(1, block.Start - 1) .. block.Replacement .. body:sub(block.Finish + 1)
        end
        local wrapped = table.concat({
            "local __lauaDefers = {}",
            "local __lauaResult = table.pack(xpcall(function()",
            normalized(body, "    "),
            "end, function(err) return err end))",
            "local __lauaCleanupError = nil",
            "for __lauaIndex = #__lauaDefers, 1, -1 do",
            "    local __lauaOK, __lauaError = pcall(__lauaDefers[__lauaIndex])",
            "    if not __lauaOK and not __lauaCleanupError then __lauaCleanupError = __lauaError end",
            "end",
            "if __lauaCleanupError then error(__lauaCleanupError, 0) end",
            "if not __lauaResult[1] then error(__lauaResult[2], 0) end",
            "return table.unpack(__lauaResult, 2, __lauaResult.n)",
        }, "\n")
        source = source:sub(1, headerEnd) .. wrapped .. "\n" .. source:sub(closing.Start)
    end
    if maskNonCode(source):match("%f[%w]defer%f[%W]") then error("defer must be inside a function") end
    return source
end

local function transpileUsing(source: string): string
    local output = {}
    local rows = splitLines(source)
    local index = 1
    while index <= #rows do
        local raw = rows[index].Text
        local masked = trim(maskNonCode(raw))
        if masked:match("^using%f[%W]") then
            local name, expression = trim(raw):match("^using%s+([%a_][%w_]*)%s*=%s*(.+)$")
            if not name then error("using requires exactly one named resource: using name = expression") end
            local indent = raw:match("^[ \t]*") or ""
            local function openDelimiters(text: string): number
                local depth = 0
                for character in maskNonCode(text):gmatch(".") do
                    if character == "(" or character == "[" or character == "{" then depth += 1 end
                    if character == ")" or character == "]" or character == "}" then depth -= 1 end
                end
                return depth
            end
            while openDelimiters(expression) > 0 and index < #rows do
                index += 1
                expression ..= "\n" .. rows[index].Text
            end
            if openDelimiters(expression) ~= 0 then error("Unclosed using resource expression") end
            local code = {
                indent .. "local " .. name .. " = " .. expression,
                indent .. "defer",
                indent .. "    if " .. name .. " ~= nil then",
                indent .. "        if typeof(" .. name .. ') == "RBXScriptConnection" then',
                indent .. "            " .. name .. ":Disconnect()",
                indent .. "        elseif typeof(" .. name .. ') == "Instance" then',
                indent .. "            " .. name .. ":Destroy()",
                indent .. "        elseif type(" .. name .. ') == "table" then',
                indent .. "            if type(" .. name .. '.Dispose) == "function" then',
                indent .. "                " .. name .. ":Dispose()",
                indent .. "            elseif type(" .. name .. '.Disconnect) == "function" then',
                indent .. "                " .. name .. ":Disconnect()",
                indent .. "            elseif type(" .. name .. '.Destroy) == "function" then',
                indent .. "                " .. name .. ":Destroy()",
                indent .. "            else",
                indent .. '                error("using resource has no Dispose, Disconnect, or Destroy method")',
                indent .. "            end",
                indent .. "        else",
                indent .. '            error("using cannot clean up this resource type")',
                indent .. "        end",
                indent .. "    end",
                indent .. "end",
            }
            table.insert(output, table.concat(code, "\n"))
        else
            table.insert(output, raw)
        end
        index += 1
    end
    return table.concat(output, "\n")
end

local function transpileAsyncFunctions(source: string): (string, number)
    local starts = {}
    for _, row in splitLines(source) do
        local masked = trim(maskNonCode(row.Text))
        if masked:match("^async%s+function%s+") or masked:match("^local%s+async%s+function%s+") then
            local at = row.Start + (row.Text:find("async", 1, true) or 1) - 1
            table.insert(starts, at)
        end
    end

    for index = #starts, 1, -1 do
        local at = starts[index]
        local closing = findBlock(source, at)
        local headerEnd = source:find("\n", at, true)
        if not headerEnd then error("async function needs a body") end
        local lineStart = (source:sub(1, at - 1):match(".*()\n") or 0) + 1
        local header = source:sub(lineStart, headerEnd - 1)
        local modified, replaced = header:gsub("%f[%w]async%s+function%s+", "function ", 1)
        if replaced ~= 1 then error("Malformed async function declaration") end
        local body = source:sub(headerEnd + 1, closing.Start - 1)
        local newBody = table.concat({
            "    return __lauaAsync.run(function()",
            normalized(body, "        "),
            "    end)",
        }, "\n")
        source = source:sub(1, lineStart - 1) .. modified .. "\n" .. newBody .. "\n" .. source:sub(closing.Start)
    end
    return source, #starts
end

local function findCloseParen(masked: string, at: number): number?
    local depth = 0
    for i = at, #masked do
        local char = masked:sub(i, i)
        if char == "(" then depth += 1 end
        if char == ")" then
            depth -= 1
            if depth == 0 then return i end
        end
    end
    return nil
end

local function transpileAwaits(source: string): (string, number)
    local occurrences = {}
    local masked = maskNonCode(source)
    local from = 1
    while true do
        local pos = masked:find("await", from, true)
        if not pos then break end
        local before = masked:sub(pos - 1, pos - 1)
        local after = masked:sub(pos + 5, pos + 5)
        if not before:match("[%w_%.:]") and not after:match("[%w_]") then
            table.insert(occurrences, pos)
        end
        from = pos + 5
    end
    for index = #occurrences, 1, -1 do
        local start = occurrences[index]
        masked = maskNonCode(source)
        local cursor = start + 5
        while masked:sub(cursor, cursor):match("%s") do cursor += 1 end
        local operandStart = cursor
        local last = cursor - 1
        if masked:sub(cursor, cursor) == "(" then
            last = findCloseParen(masked, cursor) or error("Unclosed await expression")
        else
            local identifier = masked:sub(cursor):match("^([%a_][%w_]*)")
            if not identifier then error("await needs an expression") end
            cursor += #identifier
            last = cursor - 1
            while cursor <= #masked do
                local gap = masked:sub(cursor):match("^[ \t]*") or ""
                local afterGap = cursor + #gap
                local separator = masked:sub(afterGap, afterGap)
                if separator == "." or separator == ":" then
                    local name = masked:sub(afterGap + 1):match("^[ \t]*([%a_][%w_]*)")
                    if not name then break end
                    local nameStart = masked:find(name, afterGap + 1, true) or (afterGap + 1)
                    cursor = nameStart + #name
                    last = cursor - 1
                elseif separator == "(" then
                    local closing = findCloseParen(masked, afterGap)
                    if not closing then error("Unclosed call after await") end
                    cursor = closing + 1
                    last = closing
                else
                    break
                end
            end
        end
        local operand = source:sub(operandStart, last)
        source = source:sub(1, start - 1) .. "__lauaAsync.await(" .. operand .. ")" .. source:sub(last + 1)
    end
    return source, #occurrences
end

-- Only embed LauaCore functions that the generated source actually calls.
-- Keep the original helper implementations intact to preserve their behavior.
local function compactCoreRuntime(source: string): string
    local masked = maskNonCode(source)
    if masked:find("__lauaCore%s*%[") then return LAUA_CORE_RUNTIME_SOURCE end

    local requested = {}
    for name in masked:gmatch("__lauaCore%.([%a_][%w_%.]*)") do
        requested[name] = true
    end

    local declarations = {}
    local available = {}
    for start, name in LAUA_CORE_RUNTIME_SOURCE:gmatch("()function LauaCore%.([%a_][%w_%.]*)%(") do
        table.insert(declarations, {Start = start, Name = name})
        available[name] = true
    end
    for name in requested do
        if not available[name] then return LAUA_CORE_RUNTIME_SOURCE end
    end

    local pieces = {"local LauaCore = {}"}
    local usesTable = false
    for name in requested do
        if name:sub(1, 6) == "table." then usesTable = true end
    end
    if usesTable then table.insert(pieces, "LauaCore.table = {}") end

    for index, declaration in declarations do
        if not requested[declaration.Name] then continue end
        local nextDeclaration = declarations[index + 1]
        local last = nextDeclaration and nextDeclaration.Start - 1 or #LAUA_CORE_RUNTIME_SOURCE
        local body = LAUA_CORE_RUNTIME_SOURCE:sub(declaration.Start, last)
        body = body:gsub("\nLauaCore%.table%s*=%s*%{%}", "")
        body = body:gsub("\nreturn LauaCore%s*$", "")
        table.insert(pieces, trim(body))
    end
    table.insert(pieces, "return LauaCore")
    return table.concat(pieces, "\n\n")
end

-- Embedded runtimes are inserted once, after header directives. Generated
-- scripts do not depend on separate Laua runtime ModuleScripts.
local function insertEmbeddedRuntimes(source: string): string
    local masked = maskNonCode(source)
    local fragments = {}
    if masked:find("__lauaAsync.", 1, true) then
        table.insert(fragments, "local __lauaAsync = (function()\n" .. LAUA_ASYNC_RUNTIME_SOURCE .. "\nend)()")
    end
    if masked:find("__lauaCore.", 1, true) then
        table.insert(fragments, "local __lauaCore = (function()\n" .. compactCoreRuntime(source) .. "\nend)()")
    end
    if masked:find("__lauaSignal.", 1, true) then
        table.insert(fragments, "local __lauaSignal = (function()\n" .. LAUA_SIGNAL_RUNTIME_SOURCE .. "\nend)()")
    end
    if #fragments == 0 then return source end

    local lines = splitLines(source)
    local index = 1
    while index <= #lines do
        local line = trim(lines[index].Text)
        if line:match("^%-%-!") or line == "" then
            index += 1
        else
            break
        end
    end
    local at = index <= #lines and lines[index].Start or (#source + 1)
    return source:sub(1, at - 1) .. table.concat(fragments, "\n\n") .. "\n\n" .. source:sub(at)
end

function Transpiler.Transpile(source: string, options: any?): string
    assert(type(source) == "string", "Expected Laua source string")
    local mode = type(options) == "table" and options.Mode or "Development"
    if mode ~= "Development" and mode ~= "Release" and mode ~= "Debug" then error("Invalid Laua compile mode") end
    source = preprocessMode(source, mode)
    validatePendingFeatures(source)
    source = transpilePipelines(source)
    source = transpileMemo(source)
    source = transpileIsOperator(source)
    source = transpileAdditionalSyntax(source)
    local withoutExports, exportedNames = transpileExports(source)
    local output = transpileDefers(transpileExtensions(transpileSource(transpileUsing(transpileCoalescingAssign(withoutExports)))))
    local asyncCount
    output, asyncCount = transpileAsyncFunctions(output)
    local awaitCount
    output, awaitCount = transpileAwaits(output)
    if awaitCount > 0 and asyncCount == 0 then error("await requires an async function") end
    output = transpileParameterDefaults(output)
    output = insertEmbeddedRuntimes(output)
    if #exportedNames > 0 then
        local values = {}
        for _, name in exportedNames do table.insert(values, `{name} = {name}`) end
        output ..= "\nreturn {" .. table.concat(values, ", ") .. "}"
    end
    return (output:gsub("[ \t]+\n", "\n"))
end

return Transpiler
