-- v1.0.0 of the lexer.
-- This version is just for testing. Built this one on my own. I'm gonna add some more support for strings and tables.

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

local function lex(source: string)
	local tokens = {}

	local i = 1
	while i <= #source do
		local c = source:sub(i, i)
		local two = source:sub(i, i + 1)
		local three = source:sub(i, i + 2)
		
		-- Make sure you go in chronological order (longer strings first) or it will bug.
		
		if THREE_CHAR[three] then
			table.insert(tokens, {
				Type = THREE_CHAR[three],
				Value = three,
			})
			
			i += 3
			continue
		end

		if TWO_CHAR[two] then
			table.insert(tokens, {
				Type = TWO_CHAR[two],
				Value = two,
			})

			i += 2
			continue
		end

		if c:match("%s") then i += 1 continue end

		if c:match("[%a_]") then
			local start = i

			while i <= #source and source:sub(i, i):match("[%w_]") do
				i += 1
			end

			local word = source:sub(start, i - 1)

			table.insert(tokens, {
				Type = KEYWORDS[word] or "IDENTIFIER",
				Value = word,
			})

			continue
		end

		if c:match("%d") then
			local start = i

			while i <= #source and source:sub(i, i):match("%d") do
				i += 1
			end

			local number = source:sub(start, i - 1)

			table.insert(tokens, {
				Type = "NUMBER",
				Value = number,
			})

			continue
		end
		
		if ONE_CHAR[c] then
			table.insert(tokens, {
				Type = ONE_CHAR[c],
				Value = c,
			})
			
			i += 1
			continue
		end

		i += 1
	end

	return tokens
end
