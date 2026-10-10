# About Laua

**Laua** (pronounced *Lawah*) is an open-source syntax extension for Luau.

It adds higher-level language features while still compiling down to normal Luau, meaning developers can use familiar Luau alongside additional syntax without replacing the language itself.

Laua currently includes features such as:

- Classes
- Constructors
- Inheritance with `extends`
- `new`
- `super`
- `public`, `private`, and `protected`
- Static members
- Abstract classes and methods
- Method overriding
- Namespaces
- Enums

Example:

```luau
class Zombie extends Entity
	private Health = 100

	constructor(health)
		super()
		self.Health = health
	end

	public function Damage(amount)
		self.Health -= amount
	end
end

local zombie = new Zombie(100)
```

Laua transpiles this syntax into standard Luau, allowing Roblox's existing Luau compiler and runtime to handle the final code.

The goal of Laua is not to replace Luau, but to extend it with useful syntax while keeping normal Luau code familiar and compatible.

Laua is also designed to be usable independently. Projects, frameworks, tools, and game engines can build on top of it without Laua itself being tied to one specific engine.
