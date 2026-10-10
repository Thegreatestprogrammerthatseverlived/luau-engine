# Laua custom syntax reference — v3.9

This documents **features added by Laua beyond standard Luau**. It describes the current single-ModuleScript source transformer and its restrictions, not a hypothetical fully featured language. For the inventory of 31 custom words, see [KEYWORDS.md](KEYWORDS.md). For unfinished requests, see [FEATURE_STATUS.md](FEATURE_STATUS.md).

> **Verification note:** The v3.9 browser compiler passed focused and regression checks. The generated Luau and the Luau transpiler have **not** been completely tested in Roblox Studio. Examples below show intended/compiler-supported forms, not a guarantee of runtime correctness for every game.

## 1. Install and compile — one ModuleScript

Use a ModuleScript named `transpiler` containing the whole Laua compiler. **The async, core, and signal runtimes are embedded in it**, and generated code includes only the runtimes it actually uses.

```luau
local Transpiler = require(script.Parent.transpiler)
local generated = Transpiler.Transpile(source, {Mode = "Development"})
print(generated)
```

`Transpile()` returns generated source text, **not** a running script. The script's case-sensitive ModuleScript name can be changed if you update the `require()` path. Standard Roblox `require()` imports are still used for **your own modules**.

**Migration:** Recompile older generated scripts before deleting previous standalone `LauaAsync`, `LauaCore`, or `LauaSignal` modules if those scripts still require them.

## 2. Classes and inheritance

### `class`, `constructor`, `extends`, `new`, `super`

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
local another = new Zombie
```

Classes compile to table/metatable constructors. `new Class(...)` and `new Class` are both supported. `super(...)` calls the parent initializer on the same instance; `super:Method()` calls a parent method. Keep explicit `super(...)` at the beginning of a child constructor.

### `public`, `private`, `protected`, `static`

```luau
class Enemy
    public Health = 100
    private Secret = 42
    protected Speed = 12
    static Count = 0
end
```

`static` belongs to the class rather than individual instances. **`private` and `protected` are recognized but not fully enforced**. Do not rely on them for security.

### `abstract`, `override`, `final`

```luau
abstract class Entity
    abstract function Update()
    end
end

class Zombie extends Entity
    override final function Update()
        print("Updated")
    end
end
```

Abstract classes are intended to prevent direct instantiation and require subclass implementations; `override` marks a replacement, and `final` prevents class inheritance or method overriding. Some constraints are checked in generated code. Full static verification is not provided.

### `get` / `set` — computed properties

```luau
class Enemy
    Health = 100

    get IsAlive()
        return self.Health > 0
    end

    set NewHealth(value)
        self.Health = math.max(0, value)
    end
end
```

`enemy.IsAlive` calls the getter and `enemy.NewHealth = 50` calls the setter. A getter takes no arguments and a setter takes one. Avoid defining a stored field with the same name as a computed property.

### `lazy` / `watch` — property helpers

```luau
class Zombie
    Health = 100
    lazy Inventory = LoadInventory()

    watch Health(oldValue, newValue)
        print(oldValue, newValue)
    end
end
```

`lazy` computes on first access and caches per instance, **including a `nil` result**. A failed initializer can retry; assigning beforehand prevents initialization. `watch` runs synchronously when a watched value actually changes. Default initialization itself does not invoke the watcher; watched fields use backing storage to handle later writes.

### `operator` — Luau metamethods

```luau
class Amount
    Value = 0

    operator +(other)
        return new Amount(self.Value + other.Value)
    end
end
```

Operators map onto supported Luau metamethods such as arithmetic, comparison, concatenation, and length. Only operators recognized by the transpiler work. A class constructor must accept the parameters used in your operator body.

### `is` — v3.9 class membership

```luau
class Entity
end

class Zombie extends Entity
end

local zombie = new Zombie
local valid = zombie is Entity
```

Transpiles the class membership check using an embedded runtime helper. It recognizes **Laua class inheritance**, not Roblox `Instance:IsA()`, not arbitrary Luau types, and not a static type narrowing guarantee.

## 3. Signals and asynchronous functions

### `signal` and typed signal parameters

```luau
class Zombie
    signal Died
    signal Damaged(amount: number, reason: string?)

    function Damage(amount)
        self.Damaged:Fire(amount, nil)
    end
end
```

Signals are individual event objects per instance, with `:Connect()`, `:Fire()`, `:Wait()` and connection cleanup. Typed signal declarations added in v3.9 check basic argument types and count **when `:Fire()` runs**. A `?` suffix permits `nil`. This does **not** add static type inference or full complex-type checking.

### `async`, `await`, and direct signal awaiting

```luau
async function LoadHealth()
    task.wait(1)
    return 100
end

async function Start()
    local health = await LoadHealth()
    return health
end

Start():andThen(function(value)
    print(value)
end):catch(function(err)
    warn(err)
end)
```

An `async` function returns a Promise-like Laua operation. `await` suspends that asynchronous operation and propagates failures. **v3.9 also accepts `await zombie.Died` inside an `async` function**, waiting for a Laua signal. These features use Luau coroutines and scheduling; they do not create CPU parallelism.

### `defer` / `using` — function-exit cleanup

```luau
local function Monitor()
    using connection = game:GetService("RunService").Heartbeat:Connect(function(dt)
        print(dt)
    end)

    defer
        print("Monitor exiting")
    end

    task.wait(5)
end
```

Cleanup actions run when the **enclosing function exits**, including a normal return or an error. Deferred operations run in reverse registration order. `using` handles connections with `Disconnect`, instances with `Destroy`, and appropriate table cleanup methods such as `Dispose`. An unsupported cleanup resource can raise an error. Neither keyword means "at the end of every inner block," and `task.defer()` by itself would not provide this lifetime guarantee.

## 4. Modules and declarations

### `namespace`

```luau
namespace MathHelpers
    local function PrivateHelper()
        return 2
    end

    function Double(value)
        return value * PrivateHelper()
    end
end
```

Namespaces compile to a table. `local function` declarations remain internal; ordinary namespace functions become members. A namespace can stand alone or be returned directly from a function, but not assigned using an arbitrary `local x = namespace ...` expression.

### `enum`

```luau
enum ZombieState
    Idle
    Moving
    Attacking = 10
    Dead
end
```

Produces a frozen named table. Unassigned members receive automatic numbers; explicitly numbered entries affect subsequent numbering.

### `import`, `export`, `from`, `as`

**Module being imported:**

```luau
export class Zombie
    Health = 100
end

export function Spawn()
    return new Zombie
end
```

**Other module:**

```luau
import {Zombie, Spawn as MakeZombie} from "./Zombies"
local zombie = MakeZombie()
```

Named `export` declarations compile into a return table. Named imports take fields from that table; `import ZombieModule from "./Zombies"` imports the whole return value. Paths start with `./` or `../` relative to the compiled script's location. Avoid an additional top-level `return` in a module using named exports. **Normal Luau `export type` passes through unchanged.**

### Lazy import — limited cycle mitigation

```luau
import lazy Registry from "./Registry"
```

This resolves the `require()` lazily through a proxy when the imported object is used. It can reduce **some** dependency initialization cycles; it cannot make every A-imports-B-imports-A cycle safe, especially if modules eagerly access one another while initializing.

## 5. Matching and data manipulation

### `match`, `case`, `default`

```luau
match zombie
    case {Health = 0}
        print("Dead")
    case {Stats = {Level = 3}} if canAttack
        print("Level three")
    default
        print("Other")
end
```

The matched value is evaluated once. Cases run in order. Named table patterns can nest; an `if` guard is checked only when the pattern succeeds. No array patterns, captured variable patterns, exhaustive enum analysis, or expression-returning `match` are available yet.

### Table destructuring

```luau
local {Health, Speed: WalkSpeed} = zombieData
```

Evaluates the source table once and binds named fields, with optional renamed variables. Nested patterns, array positions, and defaults in destructuring are **pending**.

### Safe access: `?.`, `?.[key]`, optional method calls

```luau
local health = player?.Character?.Humanoid?.Health
local item = inventory?.[slot]
local a = object?.GetName()
local b = object?.:GetName()
```

`?.` returns `nil` when the receiver is `nil`. `?.[key]` skips key evaluation when the receiver is nil. `?.GetName(...)` performs a **dot-style call without implicit `self`**; `?.:GetName(...)` is the **colon-style** form that passes the receiver as `self`. Arguments are skipped when there is no receiver. Complex expressions may exceed the current transformer's supported patterns.

### Nil coalescing: `??` and `??=`

```luau
local health = savedHealth ?? 100
local enabled = false
enabled ??= true   -- remains false
```

Only `nil` triggers the fallback; `false` is preserved. `??` evaluates its fallback lazily. `??=` accepts common local, dotted, or one-index assignment targets; compound expressions may need parentheses.

### One-line arrow functions: `=>`

```luau
local double = (x) => x * 2
```

Returns the value of one expression. The preview transformer does not support multi-statement arrow bodies or every nested expression shape.

### Table spread: `{...a, ...b}`

```luau
local merged = {...first, ...second}
```

Combines arrays in sequence and merges named keys, with later inputs overriding duplicate names. This is currently a **spread-only literal** form using simple names or dotted paths; mixed `{1, ...list}` literals and arbitrary spread expressions are not supported. Normal Luau `{...}` for varargs remains valid and unchanged.

### String and buffer slices

```luau
local firstWord = text[1:5]
local endOfText = text[-3:-1]
local chunk = packet[2:8]
```

Ranges are 1-based and inclusive, with negative bounds measured from the end. Strings return substrings; buffers return copied buffers. The source receiver must be simple and bounds are currently integer literals (or omitted bounds), not arbitrary computed expressions.

### `table` helpers

```luau
local active = table.filter(items, function(item)
    return item.Active
end)

local names = table.map(items, function(item)
    return item.Name
end)

local total = table.reduce(items, function(sum, item)
    return sum + item.Amount
end, 0)

local matchItem = table.findWhere(items, function(item)
    return item.Id == 1
end)
```

Laua rewrites these calls to **embedded helper functions**. It does not modify the regular Roblox `table` library. Helpers iterate arrays in order; callback arguments are `(value, index)` for filter/map/findWhere and `(accumulator, value, index)` for reduce.

## 6. New function features in v3.9

### `memo` — cache named function results

```luau
memo function Double(value)
    return value * 2
end

local x = Double(5)
local y = Double(5)
```

A wrapper caches the **entire return tuple**, including nil results, by the identities/values of arguments. `memo local function Name(...)` is also supported. No automatic cache expiry or size limit exists. Avoid memoizing a function whose result depends on mutable external state, time, or randomness.

### Default parameters

```luau
function Heal(amount = 100)
    return amount
end
```

The default is used if an argument is `nil`, not if it's `false`. Simple comma-separated defaults are supported; nested commas or complicated parameter expressions need further parsing work.

### Pipeline operator: `|>`

```luau
local result = 10 |> Double |> tostring
```

Evaluates left-to-right by nesting calls: `tostring(Double(10))`. **Current restrictions:** one line, assigned to a variable or used in a `return`, with each stage a named function (`Double` or `math.abs` style). Not a general expression pipeline yet.

## 7. Laua compiler and editor controls

### Conditional compilation: `--#if`, `--#else`, `--#end`

```luau
--#if DEBUG
print("Debug-only")
--#else
print("Other modes")
--#end
```

Compile with:

```luau
Transpiler.Transpile(source, {Mode = "Debug"})
```

Modes are `Development` (default), `Debug`, and `Release`; compare them using uppercase directive flags `DEVELOPMENT`, `DEBUG`, and `RELEASE`. Nesting is supported. Invalid modes or unbalanced directives produce errors. These are Laua compile-time branches, **not** Roblox's `--!` directives or a complete compile-time interpreter.

### Scoped `@nolint("WarningName")`

```luau
@nolint("UnusedLocal")
local unused = 100
```

The playground suppresses a named lint warning for the next relevant statement. It does **not** silence syntax or type errors. This Laua annotation is stripped/replaced during transpilation and is not a Roblox built-in attribute.

### Playground features

The optional `index.html` supports editing Laua, viewing generated Luau, **Copy Luau**, selecting build modes, exporting `.luau`, linting, autocomplete, comparing the last two successful outputs, basic Markdown declaration-index export, and built-in regression checks. The visible diff is capped at 400 lines; generated source isn't truncated. Monaco Editor and Roblox API data are normally loaded over the network.

## 8. Known unsupported requests

Do not treat these examples as working features:

| Proposed feature | Example / reason it remains pending |
|---|---|
| Labeled loop exit | `break outer`, `continue outer` need correct nested control-flow transformation |
| Constrained generic | `function Spawn<T: Entity>(value: T)` requires type enforcement |
| Nominal / unique types | `unique type PlayerId = number` must keep types distinct |
| Truthy / falsy types | Need accurate integration with type analysis |
| Positional typed tables | `type Result = [number, string]` needs per-position checks |
| Full regex | `regex.match(text, "(cat|dog)+")` requires a real regex engine |
| Mixins, `derive`, named arguments | No complete lowering/validation yet |
| Expression `match`, captures, exhaustiveness | Need richer pattern analysis |
| Full parser, AST, source maps, type checker | Not part of current v3.9 implementation |
| Multi-file editing, offline autocomplete, project bundling | Not complete in current playground |

The transpiler rejects several proposed but unsupported syntax forms instead of silently outputting code with incorrect semantics. Its error coverage is not comprehensive, because Laua still relies on multiple source-level passes.

## 9. Testing and safety limits

- **One compiled runtime:** no separate LauaAsync/LauaCore/LauaSignal modules are required for *newly generated* scripts.
- **Source transformation:** not a full parser or security boundary; nested expressions and complicated function scopes may expose edge cases.
- **Class privacy:** `private` and `protected` do not provide complete access enforcement.
- **Cleanup scope:** `defer` and `using` are function-scoped.
- **Validation:** the browser transpiler passed focused and older regression tests, but executing the Luau ModuleScript and generated Luau in Roblox Studio is still necessary to establish runtime correctness.

See [KEYWORDS.md](KEYWORDS.md) for the custom keyword inventory and [FEATURE_STATUS.md](FEATURE_STATUS.md) for the complete 43-item roadmap.
