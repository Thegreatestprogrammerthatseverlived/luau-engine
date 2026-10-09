-- Dependencies
const safestore = require(script.Parent.Safestore)

const KEYWORDS = {
	"class",
	"extends",
	"constructor",
	"private",
	"public",
	"protected",
	"static",
	"new",
	"namespace",
	"super",
	"abstract",
	"override",
	"enum",
}

local function isCode(source: string, targetIndex: number): boolean
	local inString = false
	local stringQuote = nil
	local inLineComment = false
	local inBlockComment = false
	local i = 1

	while i < targetIndex do
		local one = source:sub(i, i)
		local two = source:sub(i, i + 1)
		local four = source:sub(i, i + 3)

		if inString then
			if one == "\\" then
				i += 2
				continue
			end

			if one == stringQuote then
				inString = false
				stringQuote = nil
			end

			i += 1
			continue
		end

		if inLineComment then
			if one == "\n" then inLineComment = false end
			i += 1
			continue
		end

		if inBlockComment then
			if two == "]]" then
				inBlockComment = false
				i += 2
				continue
			end

			i += 1
			continue
		end

		if four == "--[[" then
			inBlockComment = true
			i += 4
			continue
		end

		if two == "--" then
			inLineComment = true
			i += 2
			continue
		end

		if one == `"` or one == "'" then
			inString = true
			stringQuote = one
			i += 1
			continue
		end

		i += 1
	end

	return not inString and not inLineComment and not inBlockComment
end

local function isIdentifierCharacter(char: string): boolean
	return char:match("[%w_]") ~= nil
end

local function isKeywordAt(source: string, index: number, keyword: string): boolean
	if source:sub(index, index + #keyword - 1) ~= keyword then return false end
	if not isCode(source, index) then return false end

	local before = source:sub(index - 1, index - 1)
	local after = source:sub(index + #keyword, index + #keyword)

	if before ~= "" and isIdentifierCharacter(before) then return false end
	if after ~= "" and isIdentifierCharacter(after) then return false end

	return true
end

local function skipWhitespace(source: string, index: number): number
	while index <= #source and source:sub(index, index):match("%s") do
		index += 1
	end

	return index
end

local function readIdentifier(source: string, index: number)
	local first = source:sub(index, index)
	if not first:match("[%a_]") then return nil, index end

	local startIndex = index
	index += 1

	while index <= #source and source:sub(index, index):match("[%w_]") do
		index += 1
	end

	return source:sub(startIndex, index - 1), index
end

local function getLineEnd(source: string, index: number): number
	local newline = source:find("\n", index, true)
	if not newline then return #source + 1 end
	return newline
end

local function getLineStart(source: string, index: number): number
	local i = index

	while i > 1 and source:sub(i - 1, i - 1) ~= "\n" do
		i -= 1
	end

	return i
end

local function findMatchingEnd(source: string, startIndex: number)
	local stack = {}
	local i = startIndex

	while i <= #source do
		if not isCode(source, i) then
			i += 1
			continue
		end

		local one = source:sub(i, i)

		if not one:match("[%a_]") then
			i += 1
			continue
		end

		local word, nextIndex = readIdentifier(source, i)

		if word == "class" or word == "namespace" or word == "constructor" or word == "function" or word == "if" or word == "for" or word == "while" or word == "repeat" then
			table.insert(stack, {
				Kind = word,
				DoFound = false,
			})

		elseif word == "do" then
			local top = stack[#stack]

			if top and (top.Kind == "for" or top.Kind == "while") and not top.DoFound then
				top.DoFound = true
			else
				table.insert(stack, {
					Kind = "do",
					DoFound = true,
				})
			end

		elseif word == "until" then
			local top = stack[#stack]

			if top and top.Kind == "repeat" then
				table.remove(stack)
			end

		elseif word == "end" then
			if #stack > 0 then
				local top = stack[#stack]

				if top.Kind ~= "repeat" then
					table.remove(stack)

					if #stack == 0 then
						return i, nextIndex - 1
					end
				end
			end
		end

		i = nextIndex
	end

	error("Expected 'end'")
end

local function replaceRange(source: string, startIndex: number, endIndex: number, replacement: string): string
	return source:sub(1, startIndex - 1) .. replacement .. source:sub(endIndex + 1)
end

local function parseModifiers(header: string)
	local visibility = nil
	local static = false
	local remaining = header

	while true do
		if remaining:match("^public%s+") then
			visibility = "public"
			remaining = remaining:gsub("^public%s+", "", 1)
			continue
		end

		if remaining:match("^private%s+") then
			visibility = "private"
			remaining = remaining:gsub("^private%s+", "", 1)
			continue
		end

		if remaining:match("^protected%s+") then
			visibility = "protected"
			remaining = remaining:gsub("^protected%s+", "", 1)
			continue
		end

		if remaining:match("^static%s+") then
			static = true
			remaining = remaining:gsub("^static%s+", "", 1)
			continue
		end

		break
	end

	return remaining, visibility, static
end

local transpile

local function transformNew(source: string, index: number)
	local i = index + #"new"
	i = skipWhitespace(source, i)

	local targetStart = i
	local targetParts = {}

	while i <= #source do
		local identifier, nextIndex = readIdentifier(source, i)
		if not identifier then break end

		table.insert(targetParts, identifier)
		i = nextIndex

		if source:sub(i, i) ~= "." then break end

		table.insert(targetParts, ".")
		i += 1
	end

	if #targetParts == 0 then
		error(`Expected class name after 'new' at {index}`)
	end

	local target = table.concat(targetParts)
	local afterTarget = skipWhitespace(source, i)

	if source:sub(afterTarget, afterTarget) ~= "(" then
		error(`Expected '(' after '{target}'`)
	end

	local replacement = target .. ".new"

	return replaceRange(source, index, i - 1, replacement)
end

local function transformNamespaceBody(body: string, namespaceName: string): string
	body = transpile(body)

	local output = {}
	local position = 1

	while position <= #body do
		local lineEnd = getLineEnd(body, position)
		local line = body:sub(position, lineEnd - 1)
		local indentation = line:match("^(%s*)") or ""
		local trimmed = line:match("^%s*(.-)%s*$") or ""

		if trimmed:match("^function%s+") then
			local functionName, params = trimmed:match("^function%s+([%a_][%w_]*)%s*%((.-)%)%s*$")

			if functionName then
				table.insert(output, indentation .. `function {namespaceName}.{functionName}({params})`)
			else
				table.insert(output, line)
			end

		elseif not trimmed:match("^local%s+") then
			local fieldName, value = trimmed:match("^([%a_][%w_]*)%s*=%s*(.+)$")

			if fieldName and value then
				table.insert(output, indentation .. `{namespaceName}.{fieldName} = {value}`)
			else
				table.insert(output, line)
			end
		else
			table.insert(output, line)
		end

		if lineEnd <= #body then table.insert(output, "\n") end
		position = lineEnd + 1
	end

	return table.concat(output)
end

local function transformNamespace(source: string, index: number)
	local nameStart = skipWhitespace(source, index + #"namespace")
	local namespaceName, afterName = readIdentifier(source, nameStart)

	if not namespaceName then
		error(`Expected namespace name at {index}`)
	end

	local lineStart = getLineStart(source, index)
	local beforeNamespace = source:sub(lineStart, index - 1)
	local trimmedBefore = beforeNamespace:match("^%s*(.-)%s*$") or ""

	local isReturn = trimmedBefore == "return"

	if trimmedBefore ~= "" and not isReturn then
		error("namespace can only be standalone or directly returned")
	end

	local headerEnd = getLineEnd(source, afterName)
	local endStart, endFinish = findMatchingEnd(source, index)

	local body = source:sub(headerEnd + 1, endStart - 1)
	body = transformNamespaceBody(body, namespaceName)

	local generated = `(function()\n\tlocal {namespaceName} = {{}}\n{body}\n\treturn {namespaceName}\nend)()`

	if not isReturn then
		generated = `local {namespaceName} = {generated}`
		return replaceRange(source, index, endFinish, generated)
	end

	return replaceRange(source, index, endFinish, generated)
end

local function transformClass(source: string, index: number)
	local i = skipWhitespace(source, index + #"class")
	local className, afterClass = readIdentifier(source, i)

	if not className then
		error(`Expected class name at {index}`)
	end

	i = skipWhitespace(source, afterClass)

	local baseClass = nil

	if isKeywordAt(source, i, "extends") then
		i = skipWhitespace(source, i + #"extends")

		baseClass, i = readIdentifier(source, i)

		if not baseClass then
			error(`Expected class name after 'extends'`)
		end
	end

	local headerEnd = getLineEnd(source, i)
	local endStart, endFinish = findMatchingEnd(source, index)
	local body = source:sub(headerEnd + 1, endStart - 1)

	local instanceFields = {}
	local staticFields = {}
	local methods = {}
	local constructor = nil

	local position = 1

	while position <= #body do
		local lineStart = position
		local lineEnd = getLineEnd(body, position)
		local line = body:sub(lineStart, lineEnd - 1)
		local trimmed = line:match("^%s*(.-)%s*$") or ""

		if trimmed == "" or trimmed:match("^%-%-") then
			position = lineEnd + 1
			continue
		end

		local constructorParams = trimmed:match("^constructor%s*%((.-)%)%s*$")

		if constructorParams then
			local constructorOffset = line:find("constructor", 1, true)
			local constructorStart = lineStart + constructorOffset - 1
			local memberEndStart, memberEndFinish = findMatchingEnd(body, constructorStart)

			local memberHeaderEnd = getLineEnd(body, constructorStart)
			local memberBody = body:sub(memberHeaderEnd + 1, memberEndStart - 1)

			constructor = {
				Params = constructorParams,
				Body = transpile(memberBody),
			}

			position = memberEndFinish + 1
			if body:sub(position, position) == "\n" then position += 1 end
			continue
		end

		local remaining, visibility, static = parseModifiers(trimmed)

		local functionName, params = remaining:match("^function%s+([%a_][%w_]*)%s*%((.-)%)%s*$")

		if functionName then
			local functionOffset = line:find("function", 1, true)
			local functionStart = lineStart + functionOffset - 1
			local memberEndStart, memberEndFinish = findMatchingEnd(body, functionStart)

			local memberHeaderEnd = getLineEnd(body, functionStart)
			local memberBody = body:sub(memberHeaderEnd + 1, memberEndStart - 1)

			table.insert(methods, {
				Name = functionName,
				Params = params,
				Body = transpile(memberBody),
				Static = static,
				Visibility = visibility,
			})

			position = memberEndFinish + 1
			if body:sub(position, position) == "\n" then position += 1 end
			continue
		end

		local fieldName, fieldValue = remaining:match("^([%a_][%w_]*)%s*=%s*(.+)$")

		if fieldName and fieldValue then
			local field = {
				Name = fieldName,
				Value = transpile(fieldValue),
				Visibility = visibility,
			}

			if static then
				table.insert(staticFields, field)
			else
				table.insert(instanceFields, field)
			end

			position = lineEnd + 1
			continue
		end

		position = lineEnd + 1
	end

	local output = {}

	table.insert(output, `local {className} = {{}}\n`)
	table.insert(output, `{className}.__index = {className}\n`)

	if baseClass then
		table.insert(output, `setmetatable({className}, {{__index = {baseClass}}})\n`)
	end

	for _, field in staticFields do
		table.insert(output, `{className}.{field.Name} = {field.Value}\n`)
	end

	if constructor then
		table.insert(output, `\nfunction {className}.new({constructor.Params})\n`)
		table.insert(output, `\tlocal self = setmetatable({{}}, {className})\n`)

		for _, field in instanceFields do
			table.insert(output, `\tself.{field.Name} = {field.Value}\n`)
		end

		if constructor.Body ~= "" then
			table.insert(output, constructor.Body)

			if constructor.Body:sub(-1) ~= "\n" then
				table.insert(output, "\n")
			end
		end

		table.insert(output, "\treturn self\n")
		table.insert(output, "end\n")
	else
		table.insert(output, `\nfunction {className}.new()\n`)
		table.insert(output, `\tlocal self = setmetatable({{}}, {className})\n`)

		for _, field in instanceFields do
			table.insert(output, `\tself.{field.Name} = {field.Value}\n`)
		end

		table.insert(output, "\treturn self\n")
		table.insert(output, "end\n")
	end

	for _, method in methods do
		table.insert(output, "\n")

		if method.Static then
			table.insert(output, `function {className}.{method.Name}({method.Params})\n`)
		else
			table.insert(output, `function {className}:{method.Name}({method.Params})\n`)
		end

		table.insert(output, method.Body)

		if method.Body ~= "" and method.Body:sub(-1) ~= "\n" then
			table.insert(output, "\n")
		end

		table.insert(output, "end\n")
	end

	return replaceRange(source, index, endFinish, table.concat(output))
end

transpile = function(source: string): string
	local i = 1

	while i <= #source do
		if not isCode(source, i) then
			i += 1
			continue
		end

		if isKeywordAt(source, i, "class") then
			source = transformClass(source, i)
			i = 1
			continue
		end

		if isKeywordAt(source, i, "namespace") then
			source = transformNamespace(source, i)
			i = 1
			continue
		end

		if isKeywordAt(source, i, "new") then
			source = transformNew(source, i)
			i = 1
			continue
		end

		if isKeywordAt(source, i, "constructor") then
			error("'constructor' can only be used inside a class")
		end

		if isKeywordAt(source, i, "extends") then
			error("'extends' can only be used in a class declaration")
		end

		if isKeywordAt(source, i, "private") or isKeywordAt(source, i, "public") or isKeywordAt(source, i, "protected") or isKeywordAt(source, i, "static") then
			error("Class modifier used outside of a class")
		end

		i += 1
	end

	return source
end

return transpile
