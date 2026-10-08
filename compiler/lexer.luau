-- v2.0.0 of the lexer.
-- Finally finished the lexer! Seems pretty good to me but I might add more stuff later.

-- If a word is NOT in this table, it becomes an IDENTIFIER instead.
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

	-- Reserved keywords custom to the extension
	["class"] = "CLASS",
	["extends"] = "EXTENDS",
	["constructor"] = "CONSTRUCTOR",
	["private"] = "PRIVATE",
	["public"] = "PUBLIC",
	["protected"] = "PROTECTED",
	["static"] = "STATIC",
	["namespace"] = "NAMESPACE",
	["new"] = "NEW",
}

const ONE_CHAR = {
	["="] = "EQUAL",
	["+"] = "PLUS",
	["-"] = "MINUS",
	["*"] = "MULTIPLY",
	["/"] = "DIVIDE",
	["%"] = "MODULO",
	["^"] = "POWER",
	["<"] = "LESS_THAN",
	[">"] = "GREATER_THAN",
	["("] = "LEFT_PAREN",
	[")"] = "RIGHT_PAREN",
	["["] = "LEFT_BRACKET",
	["]"] = "RIGHT_BRACKET",
	["{"] = "LEFT_BRACE",
	["}"] = "RIGHT_BRACE",
	[","] = "COMMA",
	["."] = "DOT",
	[":"] = "COLON",
	[";"] = "SEMICOLON",
	["#"] = "LENGTH",
}

const TWO_CHAR = {
	["=="] = "EQUAL_EQUAL",
	["!="] = "NOT_EQUAL",
	["~="] = "NOT_EQUAL",
	["<="] = "LESS_THAN_OR_EQUAL",
	[">="] = "GREATER_THAN_OR_EQUAL",
	["+="] = "PLUS_EQUAL",
	["-="] = "MINUS_EQUAL",
	["*="] = "MULTIPLY_EQUAL",
	["/="] = "DIVIDE_EQUAL",
	["%="] = "MODULO_EQUAL",
	["^="] = "POWER_EQUAL",
	[".."] = "CONCAT",
	["//"] = "FLOOR_DIVIDE",
	["::"] = "DOUBLE_COLON",
	["->"] = "ARROW",
}

const THREE_CHAR = {
	["..."] = "VARARG",
	["//="] = "FLOOR_DIVIDE_EQUAL",
	["..="] = "CONCAT_EQUAL",
}

return function(source: string)
	local tokens = {}

	local i = 1
	local line = 1
	local column = 1

	local function advance()
		local c = source:sub(i, i)

		i += 1

		if c == "\n" then
			line += 1
			column = 1
		else
			column += 1
		end
	end

	while i <= #source do
		local c = source:sub(i, i)
		local two = source:sub(i, i + 1)
		local three = source:sub(i, i + 2)

		local startLine = line
		local startColumn = column

		-- Make sure you go in chronological order (longer strings first) or it will bug.

		if source:sub(i, i + 3) == "--[[" then
			advance()
			advance()
			advance()
			advance()

			while i <= #source - 1 and source:sub(i, i + 1) ~= "]]" do
				advance()
			end

			if i <= #source - 1 then
				advance()
				advance()
			end

			continue
		end

		if two == "--" then
			advance()
			advance()

			while i <= #source and source:sub(i, i) ~= "\n" do
				advance()
			end

			continue
		end

		if THREE_CHAR[three] then
			table.insert(tokens, {
				Type = THREE_CHAR[three],
				Value = three,
				Line = startLine,
				Column = startColumn,
			})

			advance()
			advance()
			advance()

			continue
		end

		if TWO_CHAR[two] then
			table.insert(tokens, {
				Type = TWO_CHAR[two],
				Value = two,
				Line = startLine,
				Column = startColumn,
			})

			advance()
			advance()

			continue
		end

		if c:match("%s") then
			advance()
			continue
		end

		if c:match("[%a_]") then
			local start = i

			while i <= #source and source:sub(i, i):match("[%w_]") do
				advance()
			end

			local word = source:sub(start, i - 1)

			table.insert(tokens, {
				Type = KEYWORDS[word] or "IDENTIFIER",
				Value = word,
				Line = startLine,
				Column = startColumn,
			})

			continue
		end

		if c:match("%d") then
			local start = i

			if source:sub(i, i + 1):lower() == "0x" then
				advance()
				advance()

				while i <= #source and source:sub(i, i):match("[%da-fA-F_]") do
					advance()
				end

			elseif source:sub(i, i + 1):lower() == "0b" then
				advance()
				advance()

				while i <= #source and source:sub(i, i):match("[01_]") do
					advance()
				end

			else
				while i <= #source and source:sub(i, i):match("[%d_]") do
					advance()
				end

				if source:sub(i, i) == "." and source:sub(i + 1, i + 1):match("%d") then
					advance()

					while i <= #source and source:sub(i, i):match("[%d_]") do
						advance()
					end
				end

				if source:sub(i, i):lower() == "e" then
					advance()

					if source:sub(i, i) == "+" or source:sub(i, i) == "-" then
						advance()
					end

					while i <= #source and source:sub(i, i):match("[%d_]") do
						advance()
					end
				end
			end

			local number = source:sub(start, i - 1)

			table.insert(tokens, {
				Type = "NUMBER",
				Value = number,
				Line = startLine,
				Column = startColumn,
			})

			continue
		end

		if c == `"` or c == "'" then
			local quote = c
			advance()

			local start = i
			local closed = false

			while i <= #source do
				local current = source:sub(i, i)

				if current == "\\" then
					advance()

					if i <= #source then
						advance()
					end

					continue
				end

				if current == quote then
					closed = true
					break
				end

				advance()
			end

			local value = source:sub(start, i - 1)

			if not closed then
				table.insert(tokens, {
					Type = "ERROR",
					Value = "Unterminated string",
					Line = startLine,
					Column = startColumn,
				})

				continue
			end

			table.insert(tokens, {
				Type = "STRING",
				Value = value,
				Line = startLine,
				Column = startColumn,
			})

			advance()
			continue
		end

		if ONE_CHAR[c] then
			table.insert(tokens, {
				Type = ONE_CHAR[c],
				Value = c,
				Line = startLine,
				Column = startColumn,
			})

			advance()
			continue
		end

		advance()
	end

	table.insert(tokens, {
		Type = "EOF",
		Value = "",
		Line = line,
		Column = column,
	})

	return tokens
end
