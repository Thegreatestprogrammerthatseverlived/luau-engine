# Laua custom syntax reference — v3.7

This document covers **syntax added by Laua beyond ordinary Luau**. It reflects the v3.7 Luau ModuleScript transpiler. AboutLaua.md is available separately, with contextual `from`/`as` explained there. Standard Luau syntax, `--!` directives, and built-in `@` attributes are outside the scope of this document.

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

See [KEYWORDS.md](KEYWORDS.md) for the exact keyword inventory and contextual import words.

---

## v22 community proposals: status and exact syntax

The following requests were selected after reviewing community feature suggestions for Luau. **This is a staged release.** Working syntax is identified separately from syntax still under design. All earlier Laua keywords remain available.

### A. Shorter functions — implemented (one expression)

```luau
local double = (x) => x * 2
local enabled = () => true
```

This form transpiles to an ordinary anonymous function returning the expression. Multi-statement arrow bodies are not supported. Avoid using this syntax inside strings, comments, or complex nested same-line expressions; the preview matcher is intentionally conservative.

### B. Table spreading — implemented (spread-only literals)

```luau
local combined = {...first, ...second}
```

Arrays from `first` and `second` are appended in order; string/dictionary keys are merged, with later inputs winning on duplicate keys. Input expressions must be simple table variables or property paths. Mixed `{item, ...other}` literals and arbitrary expressions are not yet supported. Native Luau `{...}` remains untouched.

### C. Labeled loops — proposed, not implemented

```luau
outer: for i = 1, 10 do
    for j = 1, 10 do
        if j == 3 then break outer end
    end
end
```

An `outer` label would allow breaking or continuing the named loop. Laua cannot safely implement this by simply replacing `break` with `error()` or wrapping the loop in a closure: `return`, yielding, and variable scopes would change. An actual control-flow transformation is required. The preview rejects these statements explicitly.

### D. Slicing strings and buffers — implemented (simple receivers)

```luau
local greeting = text[1:5]
local tail = text[-3:-1]
local packet = data[2:8]
```

Bounds are 1-based and inclusive. Negative numbers count from the end. `text` must be a string; `data` may be a buffer. Buffer slices allocate a new buffer. Dynamic bound expressions and call-chain receivers are future work.

### E. Scoped lint suppression — implemented in playground

```luau
@nolint("UnusedLocal")
local unused = 5
```

Targets the next nonblank statement, not the entire script. Multiple unrelated warnings must be handled individually. It does not suppress syntax errors or type errors. The compiler strips the marker after linting rather than forwarding it as a normal Luau attribute.

### F. Restricted generics — proposed, not implemented

```luau
function Spawn<T: Entity>(entity: T)
    return entity
end
```

`T` would be constrained to `Entity` or its subclasses. Deleting the constraint during transpilation would lose the safety guarantee, so the current compiler refuses this form. A Laua type checker or proper Luau type-system integration is required.

### G. Unique / nominal types — proposed, not implemented

```luau
unique type PlayerId = number
unique type PlaceId = number
```

These would be distinct even though both wrap numbers. Simply emitting `type PlayerId = number` would destroy nominal identity. Laua needs a type-checker implementation or an explicitly agreed runtime boxed-value representation before this can be considered supported.

### H. Truthy / falsy types — proposed, not implemented

```luau
type Truthy = truthy
type Falsy = falsy
```

`falsy` means `false | nil` (already expressible in regular Luau). `truthy` would exclude both `false` and `nil`, and cannot be represented accurately by the present simple source transformer. The preview rejects the new aliases rather than outputting false type guarantees.

### I. Table helpers — implemented (arrays)

```luau
local selected = table.filter(items, function(item) return item.Enabled end)
local names = table.map(items, function(item) return item.Name end)
local amount = table.reduce(items, function(sum, item) return sum + item.Amount end, 0)
local first = table.findWhere(items, function(item) return item.Name == "A" end)
```

Functions use array indices starting at 1. The predicate/mapping callbacks receive `(value, index)` and reducer callbacks receive `(accumulator, value, index)`. The generated code calls `LauaCore.table` without changing Roblox's built-in `table` library.

### J. Cyclic imports — partially supported (lazy imports)

```luau
import lazy Registry from "./Registry"
```

The proxy resolves the module only when accessed. This can avoid some initialization cycles, but cannot guarantee safety if a module needs the other module's value before initialization completes. Avoid eager cross-module reads during startup.

### K. Typed positional table properties — proposed, not implemented

```luau
type Result = [number, string]
```

This would require the first array position to contain a number and the second a string. Converting this to `{number | string}` would lose positional checking; the preview deliberately does not make that conversion.

### L. Full regular expressions — proposed, not implemented

```luau
local found = regex.match(text, "(cat|dog)+")
```

Luau's built-in patterns are not full regular expressions. A real regex engine (with documented limits for patterns, lookarounds, captures, and performance) is needed. The preview does not pretend `string.match` has equivalent semantics.

### Verification and limitations

This v22 preview extends the source transformer without replacing it with a full parser or type checker. Supported examples compile in both the Luau transformer and the JavaScript playground preview, but only the JavaScript checks could be executed in this environment. Actual Luau runtime behavior still requires Roblox Studio verification.
