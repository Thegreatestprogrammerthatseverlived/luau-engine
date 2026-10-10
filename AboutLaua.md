# About Laua

**Laua** (pronounced *Lawah*) is an open-source syntax extension for Luau.

It adds higher-level language features while still compiling down to normal Luau, meaning developers can use familiar Luau alongside additional syntax without replacing the language itself.

Laua currently includes features such as:

- Classes
- Constructors
- Inheritance with `extends`
- Object creation with `new`
- Parent class access with `super`
- `public`, `private`, and `protected` access modifiers
- Static members
- Abstract classes and methods
- Method overriding
- `final` classes and methods
- Namespaces
- Enums
- Asynchronous functions with `async`
- Asynchronous operations with `await`
- Automatic resource cleanup with `using`
- Computed properties with `get` and `set`
- Deferred cleanup with `defer`
- Optional chaining with `?.`
- Nil coalescing with `??`
- Pattern matching with `match`, `case`, and `default`
- Table destructuring
- Module imports with `import`
- Operator overloading with `operator`
- Built-in signals with `signal`

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
