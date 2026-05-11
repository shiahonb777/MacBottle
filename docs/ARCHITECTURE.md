# MacBottle Architecture

This document describes how MacBottle is organized, what each module owns,
and where a contributor should start reading.

## Origins

MacBottle is a fork of [Whisky](https://github.com/Whisky-App/Whisky), an
archived SwiftUI-based Wine wrapper for macOS. The core bottle management,
Wine invocation, and PE parsing code are inherited from Whisky with minimal
changes. The visible differences are:

- The **Recipe** subsystem, which is new to MacBottle and is the reason
  this project exists as a distinct fork.
- Branding (bundle identifiers, update feed, product name).
- A GPL-3.0 compliance package (`NOTICE`, this document, `LICENSE` unchanged).

## Module map

```
.
├── Whisky/                  Top-level macOS app target
│   └── AppDelegate, Views, Assets, localization
├── WhiskyKit/               Core library consumed by app and CLI
│   ├── Recipe/              MacBottle-only: recipe types, loader, applier
│   ├── Recipes/             MacBottle-only: shipped recipe JSON files
│   ├── WineEngine/          MacBottle-only: WineEngine protocol, CrossOverEngine, registry
│   ├── Whisky/              Bottle / Program / BottleSettings
│   ├── Wine/                Wine command invocation (uses WineEngine)
│   ├── WhiskyWine/          Legacy shim. Forwards to WineEngineRegistry.
│   ├── PE/                  Windows PE file parser
│   └── Extensions/          Foundation extensions
├── WhiskyCmd/               CLI companion
├── WhiskyThumbnail/         Finder thumbnail extension for PE files
└── docs/                    This directory
```

Do not rename these Swift modules yet. A project-wide rename from `Whisky`
to `MacBottle` is planned but deferred until v0.1 is verified to compile
and run.

## Runtime flow of a game launch

1. **User picks a bottle** in the macOS app UI.
2. **User selects a `Program`** inside that bottle (a `.exe` path).
3. (MacBottle addition) **User optionally attaches a `Recipe`** matching
   the program. Recipes are discovered via
   `RecipeStore.shared.loadAll()`.
4. Launch pipeline builds the environment dictionary:
   - Start with `Program.generateEnvironment()`.
   - Merge `BottleSettings.environmentVariables(wineEnv:)`.
   - (MacBottle addition) Merge recipe overrides via
     `RecipeApplier.apply(recipe, to:)`. Recipe wins on conflict.
5. `Wine.runProgram(...)` spawns `wine <exe>` with that environment.

The recipe layer is intentionally additive. If no recipe is attached, the
code path is identical to upstream Whisky.

## Recipe subsystem

See `docs/RECIPE_AUTHORING.md` for the file format. The Swift side has
three files, each under 150 lines:

- `Recipe.swift` — `Codable` data model. No behaviour.
- `RecipeStore.swift` — Discovers and decodes JSON recipes from the
  WhiskyKit bundle's `Recipes/` resource directory.
- `RecipeApplier.swift` — Pure-function environment merger. Side-effect
  free so it is trivially testable.

Design choices worth knowing:

- **JSON, not YAML.** Foundation ships `JSONDecoder`; adding a YAML
  dependency would couple every build to a third-party parser. JSON is
  less pretty for humans but editors and CI can validate it against a
  schema (`docs/recipe-v1.json` once exposed).
- **Resources ship via SwiftPM `.copy("Recipes")`.** At build time,
  SwiftPM copies the whole `Recipes/` tree into `WhiskyKit_WhiskyKit.bundle`
  so `Bundle.module.url(forResource: "Recipes", ...)` finds it.
- **Strict on decode, lenient on missing directory.** A malformed recipe
  is logged and skipped so a single bad file does not break the rest of
  the set. A completely missing `Recipes/` directory is treated as
  "shipped with zero recipes" so a fresh checkout can still launch.
- **Recipe wins on env conflict.** A recipe is a narrower, community-vetted
  source of truth than bottle defaults. Users who disagree can detach the
  recipe.
- **Apply-time side effects (winetricks, registry) are out of scope for
  `RecipeApplier`.** They belong in a future `RecipeProvisioner` that runs
  once per bottle-recipe pairing at mount time, not on every launch.

## Testing

Unit tests live under `WhiskyKit/Tests/WhiskyKitTests/`. MacBottle-added
tests use the `Recipe*` prefix. `RecipeApplier` should have 100% line
coverage because every game launch goes through it.

## Wine engine abstraction

The `WineEngine` protocol under `WhiskyKit/Sources/WhiskyKit/WineEngine/`
isolates everything about "which Wine build this install uses" into a
single type. The reason to have this layer even with only one concrete
implementation (`CrossOverEngine`) is that:

- It turns a future engine swap into a one-line change
  (`WineEngineRegistry.shared.setCurrent(...)`) rather than a repo-wide
  find-and-replace.
- Tests substitute a `FakeEngine` pointing at the system temp directory,
  which makes it safe to exercise the engine-dependent paths without
  touching the user's real install.
- It separates the GPL-clean, MacBottle-authored interface from the
  CrossOver-derived binary distribution, which is useful if the project
  ever ships a pure upstream Wine variant with different licensing.

`WhiskyWineInstaller` is preserved as a thin shim forwarding to
`WineEngineRegistry.shared.current`, so every existing call site keeps
working. New code should call the registry directly.

## Continuing beyond v0.4

- v0.5 introduces a user-facing engine selector once a second concrete
  engine (pure upstream Wine) ships. The Recipe schema will grow a
  `min_wine` field at that point.
- The CI RecipeLint workflow already validates the entire `Recipes/`
  tree through the real `Recipe` Swift type, so schema evolution only
  requires editing `Recipe.swift` and migrating existing recipes.
