# v1 Naming, Display Effects, and Import Roles Plan

**Goal:** Build on the completed MVP with reviewable automatic naming, simple LCD display effects, clearer Quick Play promotion, and useful base/preferred Build defaults.

## 1. Naming model and parser

- Extend filename analysis with a conservative release kind (standard, development, or ROM hack), confidence, concise Game/Build suggestions, a normalized filename suggestion, and recognized hack metadata.
- Keep unknown filename groups intact and never change imported bytes or the preserved original filename.
- Add a corpus covering No-Intro names, development versions, explicit hack/base/author/translation/status tags, unknown groups, and normalized suggestions.

## 2. Reviewable and persistent metadata

- Add optional base title, hack title, author, translation, and status fields to Build metadata and GRDB persistence.
- Show all suggestions in Import Review as editable fields, with filename source/confidence and the normalized filename as a non-destructive suggestion.
- Use the same naming suggestions for ROM import, Quick Play promotion, and shared patch naming.

## 3. Base and preferred Build suggestions

- Treat the values as reviewable defaults.
- A recognized development release defaults to Base + Preferred when added to an existing Game.
- A recognized ROM hack defaults to not Base + Preferred.
- A normal additional retail/unknown image keeps the conservative existing behavior: not Base and not automatically Preferred.
- The first Build in a new Game remains Preferred; a hack may start a Game without being marked Base.
- Patch-created Builds become Preferred by default and remain ineligible to be Base.

## 4. Quick Play promotion clarity

- Separate the save-action picker from an explicitly labeled Profile Name field.
- Keep the existing default name, but make it visually unambiguous that “Quick Play” is editable text rather than a third choice.

## 5. LCD display effects

- Add lightweight Off, LCD 1×, and LCD 3× effects through the existing renderer and Settings path.
- Keep Off as the default and verify rendering/settings behavior without changing CI configuration.

## 6. Verification and product documentation

- Run focused parser, import, patch, persistence, app, and renderer tests, followed by the repository test/build checks available in this environment.
- Update the product decisions/backlog to record that MVP is complete and these additions target v1.
- Preserve the user's pipeline changes and the existing uncommitted documentation edits.
