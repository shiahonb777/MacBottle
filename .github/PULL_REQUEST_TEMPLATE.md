<!--
Thanks for contributing to MacBottle.

Pick the template that matches your change and delete the others.

- For adding or updating a game recipe (a .json under
  WhiskyKit/Sources/WhiskyKit/Recipes/), use the "Recipe" section below.
- For code or documentation changes, use the "Code / Docs" section below.
-->

## Recipe

<!-- Fill this out if your PR adds or updates a recipe file. -->

- **Game:** <!-- e.g. Black Myth: Wukong -->
- **Platform id:** <!-- e.g. steam.2050650 -->
- **Compatibility tier:** <!-- platinum | gold | silver | bronze | broken -->
- **Tested on:**
  - Chip: <!-- e.g. M4 Pro -->
  - macOS: <!-- e.g. 15.1 -->
  - Result: <!-- e.g. 60fps at 1440p medium -->

### Evidence

<!--
Optional but strongly encouraged. A screenshot, short clip, or log excerpt
showing the game running on your Mac. Nothing that includes copyrighted
game assets beyond what's reasonable for "proof it runs".
-->

### Checklist

- [ ] I confirm the game launches and is playable on my Apple Silicon Mac
- [ ] My recipe file validates against `docs/RECIPE_AUTHORING.md`
- [ ] `id` is unique across existing recipes
- [ ] `notes` is factual, in English, and does not contain promotion or piracy links
- [ ] This recipe does not require DRM circumvention

---

## Code / Docs

<!-- Fill this out if your PR changes Swift code, documentation, or workflows. -->

### What does this change do?

<!-- Short summary. -->

### Why?

<!-- Link to an issue if one exists. -->

### Testing

- [ ] `swift test` passes locally (from `WhiskyKit/`)
- [ ] The app builds in Xcode without new SwiftLint violations
- [ ] I have added tests for new non-trivial logic, or explained why not
