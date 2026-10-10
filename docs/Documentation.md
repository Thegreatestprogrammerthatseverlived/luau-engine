# Laua — Custom Syntax Reference

**Version covered:** Laua v19 (Luau ModuleScript transpiler)

Laua is a source-to-source extension of Luau. It introduces the **20 keywords below** and converts them into ordinary Luau. This document covers **only features added by Laua**—not syntax already built into Luau.

> **Scope:** This reference describes the current transpiler and its intended use. Laua is still being developed; some features have limitations listed near the end. Generated code and runtime behavior should be tested in Roblox Studio before being used in production.

## Custom keyword index

| Area | Laua-only keywords |
| --- | --- |
| Classes | `class`, `extends`, `constructor`, `new`, `super` |
| Access and class modifiers | `public`, `private`, `protected`, `static`, `abstract`, `override`, `final` |
| Computed properties | `get`, `set` |
| Named structures | `namespace`, `enum` |
| Cleanup | `defer`, `using` |
| Asynchronous operations | `async`, `await` |

**Total: 20 Laua keywords.**

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

## Putting Laua-only features together

```luau
class Entity
    private Health = 100

    constructor(health)
        self.Health = health
    end

    get IsAlive()
        return self.Health > 0
    end

    final function Reset()
        self.Health = 100
    end
end

class Zombie extends Entity
    constructor(health)
        super(health)
    end
end

async function ObserveZombie()
    local zombie = new Zombie(150)

    using connection = game:GetService("RunService").Heartbeat:Connect(function()
        if zombie.IsAlive then
            print("Zombie is alive")
        end
    end)

    local result = await FetchStatus()
    return result
end
```

`FetchStatus()` here represents another asynchronous function defined by your project.

## Current limitations and cautions

1. **This is a source-to-source transpiler, not a full Luau parser.** Complex nested constructs and unusual multiline declarations can require more work.
2. **`private` / `protected` access is not enforced.** They are not security controls.
3. **`defer` and `using` are function-scoped**, not scoped to individual inner blocks.
4. **`await` placement validation is incomplete.** Keep awaits inside async functions; not every misuse is detected before runtime.
5. **`get` / `set` use metatables.** Use separate backing fields and avoid conflicting property names.
6. **`final` and `abstract` restrictions are primarily enforced by generated runtime code**, not by a complete static type checker.
7. **Async requires `LauaAsync`.** Generated code must be able to require the runtime ModuleScript.
8. **Roblox Studio verification is still needed.** The current package includes smoke tests, but this reference does not claim a full end-to-end production verification.

---

## Complete list of Laua additions

`class` · `extends` · `constructor` · `new` · `super` · `public` · `private` · `protected` · `static` · `abstract` · `override` · `final` · `get` · `set` · `namespace` · `enum` · `defer` · `using` · `async` · `await`

*End of Laua-only syntax reference.*
