# About Laua

**Laua** (pronounced *Lawah*) is an open-source syntax extension for Luau.

It adds higher-level language features while still compiling down to normal Luau, meaning developers can use familiar Luau alongside additional syntax without replacing the language itself.

Laua currently includes features such as:

# Classes and object-oriented programming (18)
- `class`
- `constructor`
- `extends`
- `new`
- `super`
- `public`
- `private`
- `protected`
- `static`
- `abstract`
- `override`
- `final`
- `get`
- `set`
- `operator`
- `lazy`
- `watch`
- `signal`

# Code organization (4)
- `namespace`
- `enum`
- `import`
- `export`

# Control flow (3)
- `match`
- `case`
- `default`

# Asynchronous programming and cleanup (4)
- `async`
- `await`
- `using`
- `defer`

# Contextual import words
- `from`
- `as`

# Additional Laua operators and syntax
- `?.` — Optional chaining
- `??` — Nil coalescing
- `??=` — Nil-coalescing assignment
- `local { ... } = ...` — Table destructuring
- `case { ... } if ...` — Pattern matching with guards

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

NOTE FROM DEV: Laua was originally made by me. However, as this project has become bigger and bigger it was just too much for me to handle. The future updates of this project WILL be vibecoded, and remember I'm only doing this for you guys to develop fast, easy, and efficiently. I hope you understand and enjoy laua!
