-- This version only works for local variables. Planning to expand later. This is a testing version so it wont really work with the rest of the compiler.
-- Expects from the lexer [[
{
	{
		Type = "LOCAL",
		Value = "local",
	},
	{
		Type = "IDENTIFIER",
		Value = "x",
	},
	{
		Type = "EQUAL",
		Value = "=",
	},
	{
		Type = "NUMBER",
		Value = "10",
	},
	{
		Type = "EOF",
		Value = "",
	},
}
]]

local function parseLocal(index, lex)
  return {
    Kind = "Local",
    Name = lex[index + 1].Value,
    Value = {
      Kind = lex[index + 3].Type,
      Value = tonumber(lex[index + 3].Value),
    },
  }
end

return function(lex)
  local parsed = {}

  for i, key in lex do
    if key.Type == "LOCAL" then
      table.insert(parsed, parseLocal(i, lex))
    end
  end

  return parsed
end
