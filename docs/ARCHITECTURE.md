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
│   ├── Whisky/              Bottle / Program / BottleSettings
│   ├── Wine/                Wine command invocation
│   ├── WhiskyWine/          CrossOver-based Wine installer
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

## Continuing beyond v0.2

- v0.3 introduces `.github/workflows/recipe-lint.yml`, which validates
  every file in `WhiskyKit/Sources/WhiskyKit/Recipes/` against
  `docs/recipe-v1.json` on every PR.
- v0.4 introduces the Wine engine abstraction under `WhiskyKit/Wine/`,
  allowing the app to ship with either the inherited CrossOver build or a
  pure upstream Wine + GPTK2 combination. The Recipe schema will grow a
  `min_wine` field when that lands.
