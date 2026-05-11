# Contributing to MacBottle

Thanks for wanting to help. MacBottle is a small, focused project with one
goal: make Windows games runnable on Apple Silicon Macs. There are three
ways to contribute, listed here by how often people actually do them.

## 1. Add a game recipe (easiest, highest impact)

A recipe is a single JSON file under
`WhiskyKit/Sources/WhiskyKit/Recipes/<platform>/<id>.json` describing how to
run a specific Windows game. This is the primary way MacBottle grows.

**Workflow:**

1. Install the game on your Apple Silicon Mac through MacBottle and confirm
   it runs well enough to earn at least a `bronze` compatibility tier.
2. Read [`docs/RECIPE_AUTHORING.md`](./docs/RECIPE_AUTHORING.md) for the
   schema and review rules.
3. Copy the closest existing recipe in the same platform folder and edit it.
4. Open a PR using the "Recipe" section of the PR template.

**CI automatically validates** every recipe through the `RecipeLint`
workflow by decoding it with the real `Recipe` Swift type. If it decodes,
it passes. If it doesn't, the error message tells you which field is off.

You don't need to understand Swift to contribute a recipe.

## 2. Report a broken or missing game

If you can't get a game running yourself, open a
**Recipe Request** issue. Someone else (maybe a future you) will use the
information to build a working recipe.

If you find a bug in MacBottle itself — bottle creation fails, UI crashes,
something non-game — use the **Bug Report** issue template.

## 3. Contribute code

Open an issue first for anything non-trivial so we can align on scope
before you write code. See [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md)
for the module layout and the runtime flow of a game launch.

**Build environment:**

- macOS 14 Sonoma or later, on Apple Silicon
- Xcode 16 or later
- SwiftLint (`brew install swiftlint`)
- All other dependencies are managed through Swift Package Manager

**Before opening a PR:**

- Build the app in Xcode (`⌘B`). SwiftLint runs as a build phase; zero
  violations is a merge requirement.
- From `WhiskyKit/`, run `swift test`. All tests must pass.
- If you touched recipe code, the `RecipeTests` suite must still pass.
- If you added non-trivial logic, add a test. If you chose not to, explain
  why in the PR.

**Code style:**

- 4-space indentation
- No SwiftLint suppressions without a comment justifying the exception
- New files use the file header pattern enforced by `.swiftlint.yml`
- Public API has DocC comments
- User-facing strings go into `Whisky/Localizable.xcstrings`. Add only the
  English key; translation happens separately

**Scope:**

MacBottle deliberately does not accept contributions that:

- Add virtualization-based compatibility layers
- Attempt to bypass DRM or anti-cheat
- Bundle game content, installers, or pirated material
- Add paid features, telemetry, or analytics

See [`PROJECT_PLAN.md`](./PROJECT_PLAN.md) for the full project scope.

## License

By contributing, you agree that your contributions will be licensed under
the same GPL-3.0 license that covers the project.

## Relationship to Whisky

MacBottle is a fork of [Whisky](https://github.com/Whisky-App/Whisky),
which stopped maintenance in May 2025. We preserve the original author's
attribution in every inherited file and in `NOTICE`. New files authored for
MacBottle follow the same GPL-3.0 terms.
