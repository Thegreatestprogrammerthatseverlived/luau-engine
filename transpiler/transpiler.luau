local Transpiler = {}

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
	if line:match("^namespace%s+") or line:match("^return%s+namespace%s+") or line:match("^enum%s+") then return true end
	if line:match("^constructor%s*%(") or line:match("^defer%s*$") then return true end
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
		local fields, statics, methods, getters, setters = {}, {}, {}, {}, {}
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
			if properties[field.Name] then error(`Property '{field.Name}' conflicts with a field`) end
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
		table.insert(generated, `{name}.__index = function(self, key)`)
		table.insert(generated, `    local getter = {name}.__getters[key]`)
		table.insert(generated, `    if getter then return getter(self) end`)
		table.insert(generated, `    return {name}[key]`)
		table.insert(generated, `end`)
		table.insert(generated, `{name}.__newindex = function(self, key, value)`)
		table.insert(generated, `    local setter = {name}.__setters[key]`)
		table.insert(generated, `    if setter then setter(self, value); return end`)
		table.insert(generated, `    if {name}.__getters[key] then error("Cannot assign to read-only property: " .. key) end`)
		table.insert(generated, `    rawset(self, key, value)`)
		table.insert(generated, `end`)
		for _, field in statics do table.insert(generated, `{name}.{field.Name} = {transpileSource(field.Value)}`) end
		table.insert(generated, `function {name}.__init(self{ctor and trim(ctor.Params) ~= "" and ", " .. ctor.Params or ""})`)
		if parentInit then table.insert(generated, "    " .. parentInit) end
		for _, field in fields do table.insert(generated, `    self.{field.Name} = {transpileSource(field.Value)}`) end
		local innerCtor = normalized(transpileSource(ctorBody), "    ")
		if innerCtor ~= "" then table.insert(generated, innerCtor) end
		table.insert(generated, "end")
		table.insert(generated, `function {name}.new(...)`)
		table.insert(generated, `    if {name}.__abstract then error("Cannot instantiate abstract class '{name}'") end`)
		table.insert(generated, "    local self = setmetatable({}, " .. name .. ")")
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
    for _, row in splitLines(source) do
        local raw = row.Text
        local masked = trim(maskNonCode(raw))
        if masked:match("^using%f[%W]") then
            local name, expression = trim(raw):match("^using%s+([%a_][%w_]*)%s*=%s*(.+)$")
            if not name then error("using requires exactly one named resource: using name = expression") end
            local indent = raw:match("^[ \t]*") or ""
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

local function insertRuntimeRequire(source: string, expression: string): string
    local lines = splitLines(source)
    local index = 1
    while index <= #lines do
        local line = trim(lines[index].Text)
        if line:match("^%-%-!") or line == "" then index += 1 else break end
    end
    local first = index <= #lines and lines[index].Start or (#source + 1)
    return source:sub(1, first - 1) .. "local __lauaAsync = " .. expression .. "\n" .. source:sub(first)
end

function Transpiler.Transpile(source: string, runtimeRequire: string?): string
    assert(type(source) == "string", "Expected Laua source string")
    local output = transpileDefers(transpileSource(transpileUsing(source)))
    local asyncCount
    output, asyncCount = transpileAsyncFunctions(output)
    local awaitCount
    output, awaitCount = transpileAwaits(output)
    if awaitCount > 0 and asyncCount == 0 then error("await requires an async function") end
    if asyncCount > 0 or awaitCount > 0 then
        output = insertRuntimeRequire(output, runtimeRequire or 'require(script.Parent.LauaAsync)')
    end
    return (output:gsub("[ \t]+\n", "\n"))
end

return Transpiler
