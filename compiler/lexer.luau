-- v1.0.0 of the lexer. This version is simply a test, not meant for use just yet.
-- AI DID help me on this :/ not very good with string functions.
const KEYWORDS = {
	["and"] = "AND",
	["break"] = "BREAK",
	["do"] = "DO",
	["else"] = "ELSE",
	["elseif"] = "ELSEIF",
	["end"] = "END",
	["false"] = "FALSE",
	["for"] = "FOR",
	["function"] = "FUNCTION",
	["if"] = "IF",
	["in"] = "IN",
	["local"] = "LOCAL",
	["nil"] = "NIL",
	["not"] = "NOT",
	["or"] = "OR",
	["repeat"] = "REPEAT",
	["return"] = "RETURN",
	["then"] = "THEN",
	["true"] = "TRUE",
	["until"] = "UNTIL",
	["while"] = "WHILE",

	["class"] = "CLASS",
	["extends"] = "EXTENDS",
	["constructor"] = "CONSTRUCTOR",
	["private"] = "PRIVATE",
	["public"] = "PUBLIC",
	["protected"] = "PROTECTED",
	["static"] = "STATIC",
}

const OPERATORS = {
	["//="] = "FLOOR_DIVIDE_EQUAL",
	["..="] = "CONCAT_EQUAL",
	["..."] = "VARARG",

	["=="] = "EQUAL_EQUAL",
	["~="] = "NOT_EQUAL",
	["<="] = "LESS_EQUAL",
	[">="] = "GREATER_EQUAL",
	["->"] = "ARROW",
	["::"] = "DOUBLE_COLON",
	["+="] = "PLUS_EQUAL",
	["-="] = "MINUS_EQUAL",
	["*="] = "MULTIPLY_EQUAL",
	["/="] = "DIVIDE_EQUAL",
	["%="] = "MODULO_EQUAL",
	["^="] = "POWER_EQUAL",
	["//"] = "FLOOR_DIVIDE",
	[".."] = "CONCAT",

	["="] = "EQUAL",
	["<"] = "LESS",
	[">"] = "GREATER",
	["~"] = "TILDE",
	["+"] = "PLUS",
	["-"] = "MINUS",
	["*"] = "MULTIPLY",
	["/"] = "DIVIDE",
	["%"] = "MODULO",
	["^"] = "POWER",
	["."] = "DOT",
	[":"] = "COLON",
	["("] = "LEFT_PAREN",
	[")"] = "RIGHT_PAREN",
	["["] = "LEFT_BRACKET",
	["]"] = "RIGHT_BRACKET",
	["{"] = "LEFT_BRACE",
	["}"] = "RIGHT_BRACE",
	[";"] = "SEMICOLON",
	[","] = "COMMA",
	["#"] = "LENGTH",
	["?"] = "QUESTION",
	["&"] = "AMPERSAND",
	["|"] = "PIPE",
}

local function lex(source, includeComments)
	local tokens = {}

	local i = 1
	local line = 1
	local column = 1

	local interpolationStack = {}

	local function peek(offset)
		offset = offset or 0

		local position = i + offset
		if position > #source then return "" end

		return source:sub(position, position)
	end

	local function advance()
		if i > #source then return "" end

		local char = source:sub(i, i)
		i += 1

		if char == "\n" then
			line += 1
			column = 1
		else
			column += 1
		end

		return char
	end

	local function isAlpha(char)
		return char ~= "" and char:match("[A-Za-z]") ~= nil
	end

	local function isDigit(char)
		return char ~= "" and char:match("%d") ~= nil
	end

	local function isAlphaNumeric(char)
		return isAlpha(char) or isDigit(char)
	end

	local function isWhitespace(char)
		return char == " "
			or char == "\t"
			or char == "\n"
			or char == "\r"
			or char == "\v"
			or char == "\f"
	end

	local function addToken(tokenType, value, startIndex, startLine, startColumn)
		table.insert(tokens, {
			Type = tokenType,
			Value = value,
			Raw = source:sub(startIndex, i - 1),

			Start = startIndex,
			Finish = i - 1,

			Line = startLine,
			Column = startColumn,

			EndLine = line,
			EndColumn = column,
		})
	end

	local function getLongBracket(position)
		if source:sub(position, position) ~= "[" then return nil, false end

		local cursor = position + 1
		local equalsCount = 0

		while source:sub(cursor, cursor) == "=" do
			equalsCount += 1
			cursor += 1
		end

		if source:sub(cursor, cursor) == "[" then
			return equalsCount, true
		end

		if equalsCount > 0 then
			return nil, true
		end

		return nil, false
	end

	local function consumeLongBracket(equalsCount)
		advance()

		for _ = 1, equalsCount do
			advance()
		end

		advance()
	end

	local function isLongBracketClose(equalsCount)
		if peek() ~= "]" then return false end

		for offset = 1, equalsCount do
			if peek(offset) ~= "=" then return false end
		end

		return peek(equalsCount + 1) == "]"
	end

	local function readLongString(startIndex, startLine, startColumn, equalsCount, tokenType, brokenType)
		consumeLongBracket(equalsCount)

		local contentStart = i

		while i <= #source do
			if isLongBracketClose(equalsCount) then
				local value = source:sub(contentStart, i - 1)

				advance()

				for _ = 1, equalsCount do
					advance()
				end

				advance()

				addToken(tokenType, value, startIndex, startLine, startColumn)
				return
			end

			advance()
		end

		addToken(brokenType, source:sub(contentStart), startIndex, startLine, startColumn)
	end

	local function readComment()
		local startIndex = i
		local startLine = line
		local startColumn = column

		advance()
		advance()

		local equalsCount, attemptedLong = getLongBracket(i)

		if equalsCount ~= nil then
			if includeComments then
				readLongString(startIndex, startLine, startColumn, equalsCount, "BLOCK_COMMENT", "BROKEN_COMMENT")
			else
				consumeLongBracket(equalsCount)

				while i <= #source do
					if isLongBracketClose(equalsCount) then
						advance()

						for _ = 1, equalsCount do
							advance()
						end

						advance()
						return
					end

					advance()
				end
			end

			return
		end

		if attemptedLong then
			while i <= #source and peek() ~= "\n" do
				advance()
			end

			if includeComments then
				addToken("COMMENT", source:sub(startIndex + 2, i - 1), startIndex, startLine, startColumn)
			end

			return
		end

		local contentStart = i

		while i <= #source and peek() ~= "\n" and peek() ~= "\r" do
			advance()
		end

		if includeComments then
			addToken("COMMENT", source:sub(contentStart, i - 1), startIndex, startLine, startColumn)
		end
	end

	local function readIdentifier()
		local startIndex = i
		local startLine = line
		local startColumn = column

		advance()

		while isAlphaNumeric(peek()) or peek() == "_" do
			advance()
		end

		local value = source:sub(startIndex, i - 1)

		addToken(KEYWORDS[value] or "IDENTIFIER", value, startIndex, startLine, startColumn)
	end

	local function readNumber()
		local startIndex = i
		local startLine = line
		local startColumn = column

		while isDigit(peek()) or peek() == "." or peek() == "_" do
			advance()
		end

		if peek() == "e" or peek() == "E" then
			advance()

			if peek() == "+" or peek() == "-" then
				advance()
			end
		end

		while isAlphaNumeric(peek()) or peek() == "_" do
			advance()
		end

		addToken("NUMBER", source:sub(startIndex, i - 1), startIndex, startLine, startColumn)
	end

	local function readQuotedString()
		local startIndex = i
		local startLine = line
		local startColumn = column

		local quote = peek()
		advance()

		local contentStart = i

		while i <= #source do
			local char = peek()

			if char == quote then
				local value = source:sub(contentStart, i - 1)

				advance()

				addToken("STRING", value, startIndex, startLine, startColumn)
				return
			end

			if char == "\n" or char == "\r" then
				addToken("BROKEN_STRING", source:sub(contentStart, i - 1), startIndex, startLine, startColumn)
				return
			end

			if char == "\\" then
				advance()

				if i > #source then break end

				if peek() == "z" then
					advance()

					while isWhitespace(peek()) do
						advance()
					end

					continue
				end

				advance()
				continue
			end

			advance()
		end

		addToken("BROKEN_STRING", source:sub(contentStart), startIndex, startLine, startColumn)
	end

	local function readAttribute()
		local startIndex = i
		local startLine = line
		local startColumn = column

		advance()

		if peek() == "[" then
			advance()
			addToken("ATTRIBUTE_OPEN", "@[", startIndex, startLine, startColumn)
			return
		end

		local nameStart = i

		if not isAlpha(peek()) and peek() ~= "_" then
			addToken("ATTRIBUTE", "", startIndex, startLine, startColumn)
			return
		end

		advance()

		while isAlphaNumeric(peek()) or peek() == "_" do
			advance()
		end

		addToken("ATTRIBUTE", source:sub(nameStart, i - 1), startIndex, startLine, startColumn)
	end

	local readInterpolatedSection

	readInterpolatedSection = function(startIndex, startLine, startColumn, beginning)
		local contentStart = i

		while i <= #source do
			local char = peek()

			if char == "`" then
				local value = source:sub(contentStart, i - 1)

				advance()

				if beginning then
					addToken("INTERP_STRING_SIMPLE", value, startIndex, startLine, startColumn)
				else
					addToken("INTERP_STRING_END", value, startIndex, startLine, startColumn)
					table.remove(interpolationStack)
				end

				return
			end

			if char == "{" then
				if peek(1) == "{" then
					advance()
					advance()

					addToken("BROKEN_INTERP_DOUBLE_BRACE", "{{", startIndex, startLine, startColumn)
					return
				end

				local value = source:sub(contentStart, i - 1)

				advance()

				if beginning then
					table.insert(interpolationStack, {
						BraceDepth = 0,
					})

					addToken("INTERP_STRING_BEGIN", value, startIndex, startLine, startColumn)
				else
					addToken("INTERP_STRING_MID", value, startIndex, startLine, startColumn)
				end

				return
			end

			if char == "\n" or char == "\r" then
				addToken("BROKEN_STRING", source:sub(contentStart, i - 1), startIndex, startLine, startColumn)

				if not beginning then
					table.remove(interpolationStack)
				end

				return
			end

			if char == "\\" then
				advance()

				if i > #source then break end

				if peek() == "u" and peek(1) == "{" then
					advance()
					advance()
					continue
				end

				advance()
				continue
			end

			advance()
		end

		addToken("BROKEN_STRING", source:sub(contentStart), startIndex, startLine, startColumn)

		if not beginning then
			table.remove(interpolationStack)
		end
	end

	local function readInterpolatedString()
		local startIndex = i
		local startLine = line
		local startColumn = column

		advance()

		readInterpolatedSection(startIndex, startLine, startColumn, true)
	end

	local function readInterpolationEnd()
		local context = interpolationStack[#interpolationStack]

		if not context then return false end

		if context.BraceDepth > 0 then
			context.BraceDepth -= 1
			return false
		end

		local startIndex = i
		local startLine = line
		local startColumn = column

		advance()

		readInterpolatedSection(startIndex, startLine, startColumn, false)

		return true
	end

	local function readOperator()
		local startIndex = i
		local startLine = line
		local startColumn = column

		local three = source:sub(i, i + 2)
		local two = source:sub(i, i + 1)
		local one = peek()

		if OPERATORS[three] then
			advance()
			advance()
			advance()

			addToken(OPERATORS[three], three, startIndex, startLine, startColumn)
			return true
		end

		if OPERATORS[two] then
			advance()
			advance()

			addToken(OPERATORS[two], two, startIndex, startLine, startColumn)
			return true
		end

		if OPERATORS[one] then
			advance()

			addToken(OPERATORS[one], one, startIndex, startLine, startColumn)
			return true
		end

		return false
	end

	while i <= #source do
		local char = peek()

		if isWhitespace(char) then
			advance()
			continue
		end

		if char == "-" and peek(1) == "-" then
			readComment()
			continue
		end

		if char == "'" or char == '"' then
			readQuotedString()
			continue
		end

		if char == "`" then
			readInterpolatedString()
			continue
		end

		if char == "@" then
			readAttribute()
			continue
		end

		if char == "[" then
			local equalsCount, attemptedLong = getLongBracket(i)

			if equalsCount ~= nil then
				local startIndex = i
				local startLine = line
				local startColumn = column

				readLongString(startIndex, startLine, startColumn, equalsCount, "RAW_STRING", "BROKEN_STRING")
				continue
			end

			if attemptedLong then
				local startIndex = i
				local startLine = line
				local startColumn = column

				while peek() == "[" or peek() == "=" do
					advance()
				end

				addToken("BROKEN_STRING", source:sub(startIndex, i - 1), startIndex, startLine, startColumn)
				continue
			end
		end

		if isDigit(char) or (char == "." and isDigit(peek(1))) then
			readNumber()
			continue
		end

		if isAlpha(char) or char == "_" then
			readIdentifier()
			continue
		end

		if char == "{" and #interpolationStack > 0 then
			local context = interpolationStack[#interpolationStack]
			context.BraceDepth += 1

			local startIndex = i
			local startLine = line
			local startColumn = column

			advance()

			addToken("LEFT_BRACE", "{", startIndex, startLine, startColumn)
			continue
		end

		if char == "}" and #interpolationStack > 0 then
			if readInterpolationEnd() then
				continue
			end

			local startIndex = i
			local startLine = line
			local startColumn = column

			advance()

			addToken("RIGHT_BRACE", "}", startIndex, startLine, startColumn)
			continue
		end

		if readOperator() then
			continue
		end

		local startIndex = i
		local startLine = line
		local startColumn = column

		local byte = string.byte(char)

		if byte and byte >= 128 then
			advance()

			while i <= #source do
				local nextByte = string.byte(peek())
				if not nextByte or nextByte < 128 or nextByte >= 192 then break end

				advance()
			end

			addToken("BROKEN_UNICODE", source:sub(startIndex, i - 1), startIndex, startLine, startColumn)
			continue
		end

		advance()

		addToken("UNKNOWN", char, startIndex, startLine, startColumn)
	end

	table.insert(tokens, {
		Type = "EOF",
		Value = "",
		Raw = "",

		Start = #source + 1,
		Finish = #source,

		Line = line,
		Column = column,

		EndLine = line,
		EndColumn = column,
	})

	return tokens
end

return lex
