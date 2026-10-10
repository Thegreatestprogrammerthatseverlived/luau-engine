# Laua custom syntax reference — v3.5

This document covers **syntax added by Laua beyond ordinary Luau**. It reflects the v3.5 Luau ModuleScript transpiler. The [complete list of 29 Laua keywords](KEYWORDS.md) is available separately, with contextual `from`/`as` explained there. Standard Luau syntax, `--!` directives, and built-in `@` attributes are outside the scope of this document.

## Quick example

```luau
class Zombie
    Health = 100
    lazy Inventory = LoadInventory()
    signal Died

    watch Health(oldValue, newValue)
        print("Health", oldValue, newValue)
        if newValue <= 0 then
            self.Died:Fire()
        end
    end
end

local zombie = new Zombie
zombie.Health = 50
local health = zombie?.Health ?? 100
health ??= 75
```

## 1. Classes, inheritance, and object creation

### `class`, `constructor`, `extends`, `new`, and `super`

```luau
class Entity
    Name = "Entity"

    constructor(name)
        self.Name = name
    end

    function GetName()
        return self.Name
    end
end

class Zombie extends Entity
    constructor(name)
        super(name)
    end

    override function GetName()
        return super:GetName()
    end
end

local zombie = new Zombie("Runner")
local empty = new Zombie
```

Classes are transpiled into Lua tables/metatables with a `.new(...)` constructor. Both `new Class(...)` and `new Class` are supported. An explicit `super(...)` call belongs at the **beginning** of a subclass constructor. A parent initializer is generated automatically when appropriate. `super:Method(...)` calls the parent implementation using the current instance.

### `public`, `private`, `protected`, `static`

```luau
class Enemy
    public Health = 100
    private Secret = 42
    protected Speed = 12
    static Count = 0
end
```

`static` stores members on the class, shared across instances. **Current limitation:** `private` and `protected` are accepted as syntax but are **not enforced**; generated code should not be treated as secure access control.

### `abstract`, `override`, `final`

```luau
abstract class Entity
    abstract function Update()
    end
end

class Zombie extends Entity
    override final function Update()
        print("Updating")
    end
end
```

`abstract` prevents direct construction of an abstract class and allows abstract methods. `override` declares a replacement for a parent method. `final class Name` prevents subclassing and `final function Name(...)` prevents overriding. The generated class system checks some of these constraints at runtime. These checks are not a substitute for comprehensive static verification.

### `get` and `set` — computed properties

```luau
class PlayerState
    Health = 100

    get IsAlive()
        return self.Health > 0
    end

    set HealthValue(value)
        self.Health = math.max(value, 0)
    end
end
```

`state.IsAlive` invokes the getter; `state.HealthValue = 50` invokes the setter. Getters accept no parameters; setters accept one. Only instance getters/setters are supported, and they should not conflict with stored fields of the same name.

### `operator` — metamethods

```luau
class Score
    Value = 0

    operator +(other)
        return new Score(self.Value + other.Value)
    end
end
```

Operators generate metamethods. The current mapping includes `+`, `-`, `*`, `/`, `//`, `%`, `^`, `..`, `==`, `<`, `<=`, and `#` (with unary `-` supported as a no-argument operator). Operator declarations must be inside classes; unsupported operators produce a transpiler error. Example calls depend on the class's constructor matching the arguments shown.

### `lazy` — initialize on first read

```luau
class PlayerData
    lazy Inventory = LoadInventory()
end

local data = new PlayerData
print(data.Inventory)
print(data.Inventory)
```

The initializer runs on first read, once per instance. Its result is cached **even when `nil`**. If initialization raises an error, a later access retries. Assigning a value before first read prevents the initializer from running.

### `watch` — react to changes

```luau
class Zombie
    Health = 100

    watch Health(oldValue, newValue)
        print(oldValue, newValue)
    end
end

local zombie = new Zombie
zombie.Health = 50 -- prints 100, 50
zombie.Health = 50 -- no second notification
```

A watched name must be an instance field or `lazy` property. Watchers are synchronous and run only when the new value differs from the old value. Default field initialization does not trigger the watcher. Backing storage is used so `__newindex` keeps working for repeated assignments.

### `signal` — custom events

```luau
class Zombie
    signal Died

    function Kill()
        self.Died:Fire()
    end
end

local zombie = new Zombie
local connection = zombie.Died:Connect(function()
    print("Died")
end)
```

Signals are created per instance by the `LauaSignal` runtime. The returned connection can be disconnected. This is a Laua event object, not a Roblox `BindableEvent`.

## 2. Code organization

### `namespace`

```luau
namespace MathHelpers
    local function internalHelper()
        return 1
    end

    function Twice(value)
        return value * 2
    end
end
```

Namespaces compile into returned tables. Public namespace functions become exported members; local functions stay internal. A namespace can also be returned directly from a function. The syntax does not support arbitrary assignment such as `local x = namespace X`.

### `enum`

```luau
enum ZombieState
    Idle
    Walking
    Attacking = 10
    Dead
end
```

Compiles to a frozen value table with named fields and auto-numbering for unassigned entries; explicitly assigned numeric values influence the next automatic number.

### `import`, `export`, plus contextual `from` and `as`

**In `Zombies.laua`:**

```luau
export class Zombie
    Health = 100
end

export function Spawn()
    return new Zombie
end
```

**In another module:**

```luau
import {Zombie, Spawn as Make} from "./Zombies"
local zombie = Make()
```

Laua `export` collects named declarations into **one return table** at the end of the ModuleScript. Supported named exports include classes, enums, namespaces, functions, async functions, and supported local declarations. Do **not** also use a top-level `return` in a named-export module. Luau's ordinary `export type` remains unchanged.

Named imports extract fields from that return table. Default imports such as `import ZombieModule from "./Zombies"` receive the **entire** return value. Paths begin with `./` or `../` and are resolved relative to the executing compiled script; each segment refers to a ModuleScript/folder child. `from` and `as` are contextual syntax words, not independent statements.

## 3. Control flow and data expressions

### `match`, `case`, `default` — value matching

```luau
match state
    case "Idle"
        print("Idle")
    case "Attacking"
        print("Attacking")
    default
        print("Unknown")
end
```

The subject is evaluated once. Branches are compared in order, with an optional default.

### Advanced `match` — table patterns and guards

```luau
match zombie
    case {Health = 0}
        print("Dead")
    case {Stats = {Level = 3}} if canAttack
        print("Level three attacker")
    default
        print("Other")
end
```

Named patterns check `type(value) == "table"` before indexing and can nest. Guards are checked only after the pattern succeeds. Array patterns, captures, alternative patterns and exhaustiveness analysis are **not supported**.

### Named table destructuring

```luau
local {Health, Speed: MoveSpeed} = data
```

This evaluates `data` once and assigns local variables from its named fields. `Speed: MoveSpeed` renames the local binding. It does not support nested/array destructuring.

### `?.` — optional property access

```luau
local health = player?.Character?.Humanoid?.Health
```

If a receiver is `nil`, the optional chain yields `nil` rather than indexing that receiver. Optional method invocation (`?.:Method()` or equivalent) is not currently supported. The compiler is an expression transformer; very complex expressions may require simpler subexpressions.

### `??` and `??=` — nil fallback and assignment

```luau
local health = savedHealth ?? 100
local enabled = false
enabled ??= true  -- remains false
cache[key()] ??= CreateValue()
```

Both treat **only `nil`** as missing; `false` is preserved. `??` evaluates its fallback lazily; compound expressions may need parentheses. `??=` supports simple locals, dotted properties, or a single indexed property per statement. Receiver and key expressions are evaluated once. Arbitrarily complex assignment targets are not yet supported.

## 4. Asynchronous execution and cleanup

### `async` and `await`

```luau
async function Load()
    task.wait(1)
    return 100
end

async function Process()
    local value = await Load()
    return value * 2
end

Process():andThen(function(result)
    print(result)
end):catch(function(err)
    warn(err)
end)
```

`async` creates a promise-like operation through `LauaAsync`. `await` waits within an async function, propagating failure through the async result. This is coroutine/task scheduling, **not parallel CPU execution**. The transpiler needs `LauaAsync` alongside the compiled script by default.

### `defer` — function-exit cleanup

```luau
local function ReadData()
    defer
        print("Leaving ReadData")
    end

    return 42
end
```

Registered cleanups run in last-in-first-out order when the enclosing function exits, including returns or errors. This is **function-scoped**, not per-inner-block cleanup. Cleanup errors can propagate.

### `using` — automatically dispose of a resource

```luau
local function Monitor()
    using connection = game:GetService("RunService").Heartbeat:Connect(function(dt)
        print(dt)
    end)

    task.wait(5)
end
```

`using` registers function-exit cleanup on the named resource. The generated code handles `RBXScriptConnection:Disconnect()`, `Instance:Destroy()`, and table resources exposing `Dispose`, `Disconnect`, or `Destroy`. Unsupported resource types raise an error during cleanup. `using` relies on the same function-scoped cleanup transformation as `defer`; it **does not** mean `task.defer` will clean up on function exit.

## 5. Runtime modules and integration

| ModuleScript | Purpose | Needed when |
|---|---|---|
| `transpiler` or `Transpiler` | Compiles Laua source to ordinary Luau text | Running the transpiler |
| `LauaAsync` | Promise-like runtime | `async` / `await` |
| `LauaCore` | Optional chaining and nil coalescing | `?.` / `??` |
| `LauaSignal` | Per-instance signal runtime | `signal` |

```luau
local Transpiler = require(script.Parent.transpiler)
local generated = Transpiler.Transpile(source)
```

The exact ModuleScript instance name is case-sensitive. The transpiler returns **source text**, not an executed chunk. Generated scripts using runtime features default to `script.Parent.LauaAsync`, `script.Parent.LauaCore`, and `script.Parent.LauaSignal` relative to the **compiled script**, so place those modules accordingly or change the paths.

## 6. Current implementation and verification limits

- The primary implementation is `Transpiler.luau`. The browser playground uses a **separate JavaScript preview transpiler**, which may have differences in edge cases.
- `private` and `protected` are parsed but not runtime-enforced.
- Cleanup from `defer` and `using` is function-scoped, not block-scoped.
- Imports and exports are geared toward Roblox ModuleScripts and relative paths.
- The compiler is a source transformer, **not** a complete Luau parser, type checker, or security boundary. Complex nested expressions may need extra tests.
- Browser tests are useful, but generated Luau and runtime modules still need execution testing inside Roblox Studio before relying on the compiler for production games.
