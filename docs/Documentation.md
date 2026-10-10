# Laua — Custom Syntax Reference

**Version covered:** Laua v20 (Luau ModuleScript transpiler and matching playground)

Laua is a source-to-source extension of Luau. It introduces the **27 custom keywords below** and converts them into ordinary Luau. This document covers **only features added by Laua**—not syntax already built into Luau.

> **Scope:** This reference describes the current transpiler and its intended use. Laua is still being developed; some features have limitations listed near the end. Generated code and runtime behavior should be tested in Roblox Studio before being used in production.

## Custom keyword index

| Area | Laua-only keywords |
| --- | --- |
| Classes | `class`, `extends`, `constructor`, `new`, `super` |
| Access and class modifiers | `public`, `private`, `protected`, `static`, `abstract`, `override`, `final` |
| Computed properties | `get`, `set` |
| Named structures | `namespace`, `enum` |
| Value matching | `match`, `case`, `default` |
| Module paths | `import`, `from` |
| Class operators and signals | `operator`, `signal` |
| Cleanup | `defer`, `using` |
| Asynchronous operations | `async`, `await` |

**Total: 27 Laua keywords.** Laua also adds **three non-keyword syntax features**: optional property access (`?.`), nil coalescing (`??`), and named-table destructuring (`local { ... } = ...`).

> The keywords and operators in this reference are Laua additions, **not native Luau syntax**. Run them through the Laua transpiler before use in a Luau script. This reference intentionally excludes Luau's existing features, including `--!` directives and `@` attributes.

---

## 1. `class` — Define a class

A `class` declares a reusable object type. The transpiler generates tables and metatables for constructing instances and looking up methods.

```luau
class Zombie
    Health = 100

    function Damage(amount)
        self.Health -= amount
    end
end

local zombie = new Zombie
zombie:Damage(25)
```

The generated Luau has a class table, an instance constructor, and instance methods. An ordinary instance method is called using `:`.

## 2. `constructor` — Initialize an instance

A constructor runs when an instance is created. Its parameters are passed through to the generated initializer.

```luau
class Zombie
    constructor(health)
        self.Health = health
    end
end

local zombie = new Zombie(250)
```

A class can have at most one `constructor`. Constructors cannot use class member modifiers such as `static` or `final`.

## 3. `new` — Construct an instance

`new` calls the generated constructor. Both parenthesized and no-argument forms are accepted.

```luau
local a = new Zombie(150)
local b = new Zombie
```

These are lowered approximately to:

```luau
local a = Zombie.new(150)
local b = Zombie.new()
```

`new` expects a class name. It is not the same as Roblox's `Instance.new()`.

## 4. `extends` — Inherit from a parent class

A subclass inherits behavior from a parent class.

```luau
class Entity
    function Describe()
        return "An entity"
    end
end

class Zombie extends Entity
    function Groan()
        print("Groan")
    end
end
```

`extends` sets up the generated inheritance relationship and allows the use of `super`.

## 5. `super` — Access the parent class

Use `super(...)` in a subclass constructor to call the parent initializer; use `super:Method(...)` to call a parent instance method; use `super.Member` to read from the parent class.

```luau
class Entity
    constructor(name)
        self.Name = name
    end

    function Describe()
        return self.Name
    end
end

class Zombie extends Entity
    constructor(name)
        super(name)
        self.Health = 100
    end

    override function Describe()
        return super:Describe() .. " (Zombie)"
    end
end
```

In the current transpiler, an explicit `super(...)` call must be the **first non-comment statement** in the constructor. Parent initialization is otherwise generated automatically for subclasses. `super` needs an `extends` parent.

---

## 6–8. `public`, `private`, `protected` — Access modifiers

Modifiers express how a class member is intended to be used:

- `public`: accessible from outside the class.
- `private`: intended to be accessible only within the declaring class.
- `protected`: intended to be accessible within the class and its subclasses.

```luau
class Entity
    public Name = "Unknown"
    private Health = 100
    protected Team = "Neutral"

    public function GetHealth()
        return self.Health
    end
end
```

**Important current limitation:** The Luau transpiler recognizes these modifiers, but it **does not enforce** private or protected access at runtime. Do not treat them as a security boundary. They currently serve as syntax/intent markers.

## 9. `static` — Class-level members

A static member belongs to the class rather than to each instance.

```luau
class Zombie
    static Count = 0

    constructor()
        Zombie.Count += 1
    end

    static function GetCount()
        return Zombie.Count
    end
end

local first = new Zombie
print(Zombie.GetCount())
```

A static function is called on the class itself (`Zombie.GetCount()`), rather than on an instance.

## 10. `abstract` — Require subclass implementations

An abstract class cannot be instantiated directly. An abstract method is generated with an error indicating that a subclass must provide an implementation.

```luau
abstract class Enemy
    abstract function Attack(target)
    end
end

class Zombie extends Enemy
    override function Attack(target)
        print("Attacking", target)
    end
end
```

The current implementation prevents direct construction of abstract classes and generates an erroring abstract method body. It is **not** a complete compile-time abstract-method checker: missing implementations might only become apparent when called.

## 11. `override` — Replace an inherited method

`override` marks a method as replacing one inherited from a parent.

```luau
class Entity
    function Speak()
        print("Hello")
    end
end

class Zombie extends Entity
    override function Speak()
        print("Groan")
    end
end
```

The generated code checks for an inherited method with that name. An `override` method requires a parent class.

## 12. `final` — Prevent extension or overriding

`final` can be used on an entire class or on an instance/class method.

```luau
final class PermanentEntity
    function Identify()
        return "Permanent"
    end
end
```

Attempting to extend a final class causes an error in the generated Luau.

```luau
class Entity
    final function GetId()
        return 10
    end
end
```

A subclass cannot override a final method. Current enforcement takes place in the generated code during class setup; it is not a full static type system. `final` is not currently valid on fields.

---

## 13–14. `get`, `set` — Computed properties

Getters let property access run a function. Setters let property assignment run a function.

```luau
class PlayerStats
    private Health = 100

    get HealthValue()
        return self.Health
    end

    set HealthValue(value)
        self.Health = math.max(0, value)
    end

    get IsAlive()
        return self.Health > 0
    end
end

local stats = new PlayerStats
stats.HealthValue = 75
print(stats.HealthValue)
print(stats.IsAlive)
```

**How it works:** Laua emits `__index` and `__newindex` logic, plus separate getter/setter functions. You use the property through `.` instead of explicitly calling the getter or setter.

**Rules and limitations:**

- A getter takes **no parameters**: `get Name()`.
- A setter takes **one parameter**: `set Name(value)`.
- A getter without a setter creates a read-only computed property.
- Computed properties **cannot share a name with an ordinary instance field**. Use a separate backing field, as shown with `Health` and `HealthValue`.
- Static getters and setters are not supported in the current transpiler.
- A setter without a getter does not automatically define a meaningful read result.

---

## 15. `namespace` — Group exported members

A namespace groups related functions and values without manually building an export table.

```luau
namespace Scheduler
    Version = 1

    local function Validate()
        return true
    end

    function Bind(name, callback)
        if not Validate() then return end
        print("Bound", name)
    end
end

Scheduler.Bind("Test", function() end)
```

A top-level `function Bind` becomes an exported `Scheduler.Bind` function. A `local function` stays local inside the namespace.

Namespaces can also be **returned directly** from a function:

```luau
local function CreateTools()
    return namespace Tools
        function Ping()
            return "pong"
        end
    end
end

local tools = CreateTools()
print(tools.Ping())
```

Current placement rule: a namespace must be a standalone declaration or appear immediately after `return`. An arbitrary assignment such as `local x = namespace Tools` is not supported.

## 16. `enum` — Frozen named constants

An enum creates a frozen table of named values.

```luau
enum SchedulerPriority
    First = 100
    High = 75
    Normal = 50
    Low = 25
    Last = 0
end

print(SchedulerPriority.High)
```

Values can be assigned explicitly. An omitted value receives an automatically numbered value, starting at `0` and continuing from the most recent explicit integer.

```luau
enum State
    Idle
    Walking
    Running
end
```

This is lowered to a `table.freeze({...})` value. An enum is a runtime value; this implementation does not automatically create a Luau enum *type*.

---

## 17. `defer` — Run cleanup when a function exits

`defer` registers a block of code to run later, when the **enclosing function** returns or errors.

```luau
local function Process()
    local resource = OpenResource()

    defer
        resource:Destroy()
    end

    DoWork(resource)
    return true
end
```

Multiple deferred blocks run in **reverse registration order** (last in, first out).

```luau
local function Example()
    defer
        print("First registered")
    end

    defer
        print("Second registered")
    end
end
```

The output from cleanup is `Second registered`, then `First registered`.

**Current behavior:** `defer` is **function-scoped**, not scoped to every nested `if` or loop block. Cleanup is implemented by wrapping function execution and running registered handlers afterward. If a cleanup handler errors, the generated code propagates that error. `defer` must be inside a function.

## 18. `using` — Automatically clean up a resource

`using` declares a local resource and registers cleanup automatically. It is essentially a convenience form built on top of Laua's `defer`.

```luau
local function WatchForFiveSeconds()
    using connection = game:GetService("RunService").Heartbeat:Connect(function(dt)
        print(dt)
    end)

    task.wait(5)
end
```

When the function exits, Laua disconnects `connection`.

Current cleanup rules:

| Resource | Cleanup performed |
| --- | --- |
| `RBXScriptConnection` | `:Disconnect()` |
| Roblox `Instance` | `:Destroy()` |
| Table with a `Dispose` function | `:Dispose()` |
| Otherwise, table with a `Disconnect` function | `:Disconnect()` |
| Otherwise, table with a `Destroy` function | `:Destroy()` |
| `nil` | No cleanup |

For a non-nil unsupported value, cleanup raises an error. Cleanup happens at **function exit**, not at the next scheduler tick; `using` does **not** rely on `task.defer()` as the trigger.

The current syntax is `using name = expression` with **one named resource per declaration**.

---

## 19–20. `async`, `await` — Asynchronous operations

Laua adds asynchronous functions and an `await` expression. These use a separate **LauaAsync** runtime module; they do not create new Luau VM instructions or automatically enable parallel execution.

```luau
async function FetchValue()
    task.wait(0.1)
    return 42
end

async function Calculate()
    local value = await FetchValue()
    return value * 2
end

Calculate():andThen(function(result)
    print(result)
end):catch(function(err)
    warn(err)
end)
```

### `async`

An `async function` starts its work asynchronously and immediately returns a Promise-like operation object.

Supported forms include:

```luau
async function Fetch()
    return 5
end

local async function Load()
    return await Fetch()
end

class Service
    async function Request()
        return await Fetch()
    end
end
```

### `await`

`await` waits for an operation's result from within asynchronous code. It propagates a rejected operation as an error.

```luau
local value = await Fetch()
local answer = await (Fetch())
```

The current transpiler accepts identifiers, straightforward member/call chains, and parenthesized expressions after `await`. More complex forms may require extra parentheses or future parser improvements. Always use `await` inside an `async` function; the current implementation's validation is not fully scope-aware.

### Operation methods

Operations returned by `async` functions support these methods through the Laua runtime:

| Method | Purpose |
| --- | --- |
| `:await()` | Wait for the operation, using an explicit method call |
| `:andThen(callback)` | Handle successful completion and return a chained operation |
| `:catch(callback)` | Handle a rejection and return a chained operation |
| `:finally(callback)` | Run a callback after success or failure |
| `:getStatus()` | Read the operation status (`Pending`, `Fulfilled`, or `Rejected`) |

`andThen`, `catch`, and `finally` are **runtime methods**, not additional Laua keywords.

### Runtime setup

The generated code expects a module named `LauaAsync`:

```luau
local __lauaAsync = require(script.Parent.LauaAsync)
```

Place the runtime where this require path works, or provide a custom require expression when calling the transpiler:

```luau
local Transpiler = require(script.Parent.Transpiler)
local output = Transpiler.Transpile(source, 'require(game:GetService("ReplicatedStorage").LauaAsync)')
```

The transpiler returns **source text**. Compiling/executing that text is a separate step.

---

## 21–23. `match`, `case`, `default` — Value matching

A `match` evaluates its subject expression once and compares it to each `case` using normal equality (`==`). Only the first matching branch executes. `default` is optional and, if used, must be the final branch.

```luau
match zombie.State
    case "Idle"
        Idle()
    case "Chasing"
        Chase()
    default
        Stop()
end
```

Roughly becomes an `if`/`elseif`/`else` chain inside a `do` block with one temporary variable holding the evaluated subject.

**Current rules:**

- At least one `case` is required.
- `case` requires a value to compare against the subject.
- `default` must appear after a `case`, at most once, with no later `case`.
- Branch bodies can contain other statements and nested blocks.
- This is **value matching only**. No guards, wildcards, array patterns, or structural/table matching are implemented.

## 24–25. `import`, `from` — Relative ModuleScript imports

The import form is:

```luau
import Zombie from "./Modules/Zombie"
import Config from "../Config"
```

It lowers to a local variable assigned from a `require(...)` call. A path beginning with `./` searches beneath **the compiled script's parent**; `../` walks to a parent of that parent. Each remaining path segment is found with `:WaitForChild()`.

For example:

```luau
import Zombie from "./Modules/Zombie"
```

becomes approximately:

```luau
local Zombie = require(script.Parent:WaitForChild("Modules"):WaitForChild("Zombie"))
```

**Current rules and limits:**

- Use `import Name from "./Path/Module"` or single quotes.
- Paths must begin with `./` or `../`; absolute paths are not supported.
- Names and path segments must be plain Luau identifiers. No `.luau` filename extension, named import lists, package registry, or wildcard imports.
- Paths refer to **Roblox instances relative to the executing compiled script**, not files on the computer or the transpiler's ModuleScript.
- `from` is only part of this import declaration; it does not replace existing Luau syntax elsewhere.

## 26. `operator` — Class operator overloads

Declare supported operators inside a Laua class. The transpiler generates the corresponding Luau metamethod on the class table.

```luau
class Vector
    constructor(x, y)
        self.X = x
        self.Y = y
    end

    operator +(other)
        return new Vector(self.X + other.X, self.Y + other.Y)
    end

    operator -()
        return new Vector(-self.X, -self.Y)
    end
end
```

The example's `+` generates a `__add` metamethod, and zero-parameter `-` generates `__unm`.

| Laua operator | Generated metamethod |
| --- | --- |
| `+`, `-`, `*`, `/` | `__add`, `__sub`, `__mul`, `__div` |
| `//`, `%`, `^` | `__idiv`, `__mod`, `__pow` |
| `..` | `__concat` |
| `==`, `<`, `<=` | `__eq`, `__lt`, `__le` |
| `#` | `__len` |
| `-()` (no parameter) | `__unm` |

**Current rules:** Binary operators take one parameter (`other` above); unary `-` and `#` take none. Unknown operators and modifiers on operators are rejected. Inherited metamethod behavior and Roblox/Luau metamethod restrictions still apply; subclasses may need to redeclare operators. This does **not** introduce new native operators.

## 27. `signal` — Per-instance class events

A `signal` declaration creates a separate `LauaSignal` object for every instance of the class.

```luau
class Zombie
    signal Died

    function Kill()
        self.Died:Fire()
    end
end

local zombie = new Zombie
local connection = zombie.Died:Connect(function()
    print("Zombie died")
end)
zombie:Kill()
connection:Disconnect()
zombie.Died:Destroy()
```

**Runtime behavior:** `LauaSignal.new()` wraps a Roblox `BindableEvent` and exposes `:Connect(callback)`, `:Once(callback)`, `:Wait()`, `:Fire(...)`, and `:Destroy()`. `Connect` and `Once` return Roblox connections. `Destroy` is idempotent; use it when the owning object no longer needs the event.

Signals are per **instance**, not shared static class fields. `signal` currently accepts one identifier per declaration and cannot have class-member modifiers. A `signal` field should not have the same name as another class member. The generated script needs access to `LauaSignal`.

---

## Additional Laua-only operators and expressions

### Optional chaining — `?.`

Optional chaining safely accesses a **property** of a possibly nil value:

```luau
local health = player?.Character?.Humanoid?.Health
local player = game:GetService("Players")?.LocalPlayer
```

A segment evaluates its left-hand side once. If that left-hand side is `nil`, the result is `nil`; otherwise it indexes the property. Each optional link is handled individually.

Rough lowering:

```luau
local health = __lauaCore.optional(player, "Character")
```

**Limits:** Only `?.Property` is supported. Optional method calls (`?.Method()` / `?.()`), optional bracket access (`?.[key]`), and automatic safety for later ordinary `.` accesses are not supported. The runtime is needed only for code that uses `?.` or `??`.

### Nil coalescing — `??`

Use a fallback when—and **only when**—the value on the left is `nil`:

```luau
local health = savedHealth ?? 100
local enabled = savedEnabled ?? true
local total = saved ?? (default + bonus)
```

This preserves `false`, unlike using `or` for a fallback. The right-hand expression runs lazily, only if needed. A chain such as `a ?? b ?? c` is supported.

Rough lowering:

```luau
local health = __lauaCore.coalesce(savedHealth, function() return 100 end)
```

**Limit:** Parenthesize compound arithmetic and logical expressions when combining them with `??`, e.g. `value ?? (base + extra)`. Some unparenthesized compound expressions are rejected instead of being rewritten with possibly different precedence.

### Named-table destructuring

Extract named fields into locals:

```luau
local {Health, WalkSpeed: speed} = zombieData
```

This becomes approximately:

```luau
local __lauaDestructure1 = zombieData
local Health = __lauaDestructure1.Health
local speed = __lauaDestructure1.WalkSpeed
```

The right-hand expression is evaluated once. `:` in the braces means **rename the field on extraction**, not a method call.

**Limits:** Only named keys and simple aliases are supported. Nested structures, numeric positions, defaults inside a pattern, and destructuring assignment without `local` are not implemented. If the source evaluates to `nil`, field access can error as in normal Luau.

---

## Runtime dependencies and module naming

Laua's primary compiler is the **Luau ModuleScript** `Transpiler.luau`. It takes Laua source text and returns generated Luau source text. It does **not** automatically execute that output.

The v20 runtime modules are needed only when the source uses their respective features:

| ModuleScript | Used by |
| --- | --- |
| `LauaAsync` | `async`, `await` |
| `LauaCore` | `?.`, `??` |
| `LauaSignal` | `signal` |

By default, generated source uses paths like `require(script.Parent.LauaCore)`. Those paths are evaluated relative to the **compiled script when it runs**. The runtime modules must be placed accordingly, or the generated require paths must be adjusted before execution.

If your transpiler ModuleScript is named lowercase **`transpiler`**, use that exact spelling:

```luau
local Transpiler = require(script.Parent.transpiler)
local compiled = Transpiler.Transpile(source)
```

`Transpiler.Transpile(source, runtimeRequire)` also accepts an optional custom require expression for `LauaAsync` only. The current implementation does not expose matching custom path arguments for `LauaCore` or `LauaSignal`.

**Studio testing:** The repository provides `Tests.luau` for compilation smoke tests and basic runtime checks. Browser JavaScript tests are not substitutes for executing the generated Luau in Roblox Studio. v20 is not claimed to be fully end-to-end verified there.

---

## Putting Laua-only features together

```luau
class Counter
    signal Changed
    Value = 0

    get IsPositive()
        return self.Value > 0
    end

    operator +(other)
        return self.Value + other.Value
    end

    function Increment()
        self.Value += 1
        self.Changed:Fire(self.Value)
    end
end

local counter = new Counter
local {Value: initial} = {Value = 10}
local current = counter?.Value ?? initial

match current
    case 0
        print("Zero")
    default
        print("Nonzero")
end

local function Observe()
    using connection = counter.Changed:Connect(function(value)
        print("Changed", value)
    end)

    counter:Increment()
end

Observe()
```

This illustrates the new syntax without needing an external ModuleScript import. The generated code still requires `LauaCore` and `LauaSignal` at runtime.

## Current limitations and cautions

1. **The transpiler is not a full Luau parser.** It uses a line-oriented/block-aware transformer for many features. Test nontrivial nested code, especially anonymous functions and multiline expressions.
2. **`private` and `protected` are not runtime-enforced.** They should never be used as a security boundary.
3. **`defer` and `using` are function-scoped**, not scoped to individual `if`/loop blocks. Cleanup executes at function exit in last-in, first-out order, including errors.
4. **`async`/`await` use a Promise-like runtime, not parallel CPU execution.** Await placement checks are limited; await inside an async function.
5. **`get`/`set` use metatables.** Use separate backing fields and avoid name collisions; static accessors are unsupported.
6. **`abstract`, `override`, and `final` checks are not a complete static type system.** Some restrictions are enforced by generated code at class setup or use.
7. **`match` supports equality comparisons, not full structural patterns.** Each match needs at least one case; default, if present, must be last.
8. **Destructuring supports only named fields and renaming.** Nested and positional patterns are not supported.
9. **`import` paths resolve against the compiled script's parent at runtime.** Only relative ModuleScript paths with identifier segments are supported.
10. **Operators become Luau metamethods.** Their actual behavior follows Luau metamethod rules; inherited metamethods may require redeclaration.
11. **Signals wrap `BindableEvent`.** Clean up connections and destroy signals when appropriate.
12. **`?.` only protects the explicitly optional property links.** Optional calls or optional bracket indexing are unsupported.
13. **`??` evaluates its fallback lazily and preserves `false`.** Parenthesize mixed/compound expressions.
14. **Runtime requires must resolve where generated code executes.** `LauaAsync`, `LauaCore`, and `LauaSignal` are separate ModuleScripts.
15. **Complete Roblox Studio execution has not been verified here.** Existing tests verify generated-source fragments and basic runtime operations, but do not prove every feature works in a full game.

---

## Complete list of Laua additions

**27 custom keywords:**

`class` · `extends` · `constructor` · `new` · `super` · `public` · `private` · `protected` · `static` · `abstract` · `override` · `final` · `get` · `set` · `namespace` · `enum` · `defer` · `using` · `async` · `await` · `match` · `case` · `default` · `import` · `from` · `operator` · `signal`

**Additional Laua-only syntax:** `?.` · `??` · `local {Field, Field: alias} = tableExpression`

*End of Laua-only syntax reference (v20).*
