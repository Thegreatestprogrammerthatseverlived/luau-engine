# Laua v3.9 — single-file compiler (work in progress)

Laua extends Luau and transpiles into ordinary Luau. **The Roblox compiler remains a single ModuleScript named `transpiler`.** No sibling LauaAsync, LauaCore, or LauaSignal modules are needed for newly transpiled scripts. The ModuleScript embeds the necessary runtime definitions directly in generated source.

This build implements part of the large requested feature roadmap. **It is not a completed implementation of all 43 proposals.** See [FEATURE_STATUS.md](docs/FEATURE_STATUS.md) for the exact status of every item.

## Changed repository files

- `transpiler.luau` — the only Roblox ModuleScript required by Laua itself
- `index.html` — browser playground, updated compiler and UI tools
- `README.md` — this document
- `docs/FEATURE_STATUS.md` — complete feature status and limits

No separate runtime ModuleScripts have been added.

## Roblox usage

```luau
local Transpiler = require(script.Parent.transpiler)

local luau = Transpiler.Transpile(source, {Mode = "Development"})
print(luau)
```

`Mode` accepts `Development` (default), `Debug`, or `Release`. These affect Laua's `--#if` compile-time branches, **not** Roblox's optimizer. `--!optimize` remains the way to request Luau optimization from Roblox. Transpilation returns source code; it does not execute it.

## New in v3.9

### Class membership: `is`

```luau
class Entity
end
class Zombie extends Entity
end
local zombie = new Zombie
print(zombie is Entity) -- true
```

Only **Laua classes** are supported on the right side. This feature checks generated class inheritance through metatables; it is not an alias for Roblox `Instance:IsA()`.

### Pipelines: `|>`

```luau
local result = 10 |> Double |> tostring
```

Currently the pipeline must be on **one line** and have an assignment or `return` on the left. Each stage must be a simple function name, optionally namespaced with dots. It translates to `tostring(Double(10))`.

### Memoization: `memo`

```luau
memo function Double(value)
    return value * 2
end
```

Results are cached by argument identity, including nil values and multi-value return tuples. It is for **named functions**. Do not memoize functions whose results depend on changing external state; cache entries have no eviction policy yet.

### Optional indexing and calls

```luau
local health = data?.[key]
local result = service?.GetValue(2) -- dot-style call, no self supplied
local result2 = service?.:GetValue(2) -- colon-style call, supplies self
```

The index expression and call arguments are not evaluated when the receiver is nil. These build on existing `?.` support.

### Default function parameters

```luau
function Heal(amount = 100)
    return amount
end
```

Defaults apply when a parameter equals `nil`, **not** when it equals `false`. For now, put only simple defaults without nested commas in parameter declarations. Full expression parsing is still future work.

### Typed signals with runtime validation

```luau
class Zombie
    signal Damaged(amount: number, reason: string?)
end
```

`:Fire()` validates argument count and simple runtime types; an optional type ending in `?` accepts nil. This is **runtime validation**, not a replacement for Luau's static type checking. Existing untyped `signal Name` declarations continue to work.

Inside an async function, `await zombie.Damaged` waits for a Laua signal.

### Conditional source compilation

```luau
--#if DEBUG
print("debug build")
--#else
print("normal build")
--#end
```

Accepted tags are `DEBUG`, `RELEASE`, and `DEVELOPMENT`, corresponding to the selected build mode. Nested branches are supported. Comments not matching this exact syntax remain ordinary comments.

## Playground improvements

The playground now includes a build-mode selector and buttons for transpiling, copying, exporting generated `.luau`, viewing a diff between the previous two successful outputs, exporting a declaration index as Markdown, and running compiler tests. Diff previews are capped at 400 lines to avoid freezing the browser; **the generated code itself is not truncated**.

The playground still loads Monaco Editor from a CDN and current Roblox API metadata from online sources, so complete offline use is not yet guaranteed.

## Known limitations and verification

- Existing features, including `class`, `namespace`, `enum`, `async`, `defer`, `using`, `import`, `export`, `get`, `set`, `lazy`, `watch`, `match`, `??`, `??=`, spreads, arrow functions, and slicing, remain in the transpiler.
- `private` and `protected` access control are still not fully enforced.
- Text-transform stages are still used; a complete parser/AST and full Luau type checking are **not implemented**.
- Labeled loop exits, nominal/constrained types, typed tuples, and full regex were already pending and remain incomplete.
- JavaScript syntax tests, focused compiler tests, prior regression tests, and runtime-source equality checks passed in the test environment.
- **Generated Luau and the ModuleScript have not been executed inside Roblox Studio in this review.** The absence of syntax and runtime errors there is not guaranteed.

For the full requested roadmap, read [Feature status](docs/FEATURE_STATUS.md).

NOTE FROM DEV: Laua was originally made by me. However, as this project has become bigger and bigger it was just too much for me to handle. The future updates of this project WILL be vibecoded, and remember I'm only doing this for you guys to develop fast, easy, and efficiently. I hope you understand and enjoy laua!
