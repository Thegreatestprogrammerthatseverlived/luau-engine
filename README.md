# Laua v21

Laua is a syntax extension for Luau. **`Transpiler.luau` is the primary transpiler**, built as a Roblox Luau ModuleScript. `index.html` is the browser playground, powered by a separate JavaScript preview transpiler.

This update preserves the existing Laua features and adds **`lazy`**, **`watch`**, **Laua module `export`**, **nil-coalescing assignment `??=`**, and **advanced `match` patterns**. Named imports such as `import {Zombie, Spawn as Make} from "./Zombies"` now complement exports. Standard Luau `export type` statements still pass through unchanged.

## Files

- `Transpiler.luau`: primary Laua-to-Luau ModuleScript
- `LauaAsync.luau`: `async`/`await` runtime
- `LauaCore.luau`: `?.` and `??` runtime
- `LauaSignal.luau`: `signal` runtime
- `index.html`: Monaco playground with highlighting, autocomplete, and lint
- `laua-browser-transpiler.js`: JavaScript preview transpiler
- `docs/CUSTOM_SYNTAX.md`: Laua-only syntax documentation
- `ExampleV21.laua`: sample Laua program
- `ExampleV21.generated.luau`: corresponding preview output
- `TestsV21.luau`: Roblox Studio transpiler smoke tests
- `test_v21.js`: Node.js browser-transpiler and lint tests

## Usage

```luau
local Transpiler = require(script.Parent.transpiler)
local generatedLuau = Transpiler.Transpile(source)
print(generatedLuau)
```

Use `script.Parent.Transpiler` if the actual ModuleScript is named `Transpiler` rather than `transpiler`. Explorer names are case-sensitive. `Transpile` returns source text; it does not execute that source.

Generated programs expect runtime modules beside the *compiled script* by default (`script.Parent.LauaAsync`, `script.Parent.LauaCore`, `script.Parent.LauaSignal`) when those modules are used.

## New syntax

```luau
class Zombie
    Health = 100
    lazy Inventory = LoadInventory()

    watch Health(oldValue, newValue)
        print("Health changed", oldValue, newValue)
    end
end

local zombie = new Zombie
zombie.Health = 75
local items = zombie.Inventory

local saved = nil
saved ??= false

match zombie
    case {Health = 0} if canRespawn
        print("Respawn")
    case {Health = 75}
        print("Wounded")
    default
        print("Other")
end
```

Module file `Zombies.laua`:

```luau
export class Zombie
    Health = 100
end

export function Spawn()
    return new Zombie
end
```

Another module:

```luau
import {Zombie, Spawn as Make} from "./Zombies"
local zombie = Make()
```

For detailed behavior and limitations, see [`docs/CUSTOM_SYNTAX.md`](docs/CUSTOM_SYNTAX.md).

## Current limits and testing

- `lazy` and `watch` are instance-class features. `watch` requires a declared instance field or `lazy` property. The default field initialization does not call its watcher.
- Lazy initialization runs on first property read, is cached per instance **even if it returns `nil`**, and retries after an initializer error.
- `watch` runs when a watched field is assigned a *different* value. Backing storage avoids Luau `__newindex` being skipped on subsequent assignments.
- `??=` supports a variable, dotted property or one indexed property per statement, with a receiver/key evaluated once. It is not a full arbitrary assignment-expression parser.
- Table patterns support named fields, nesting, and optional `if` guards. They do not support array patterns, captures, alternatives, or exhaustive matching.
- Laua `export` currently supports named classes, functions, namespaces, enums and `local name = ...`; it generates a **single return table** at file end. Do not also put a top-level `return` in that module. Import paths are resolved relative to the executing compiled ModuleScript.
- The existing `private`/`protected` modifiers are still not enforced. The compiler is a source transformer, not a full Luau parser or type checker.
- JavaScript regression and lint suites can be run with Node.js. The actual Luau implementation and generated scripts **still need execution tests in Roblox Studio**; browser tests alone do not prove runtime behavior.
