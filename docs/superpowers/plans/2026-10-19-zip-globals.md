# ZIP Globals Implementation Plan

**Goal:** Keep GB Studio's `globals.i` or `game_globals.i` with its ROM when importing a ZIP.

**Architecture:** Use the existing ZIP inbox to pair one globals file with one ROM in the same archive folder. Keep both in the ROM receipt and call `AttachVariableMap.execute(buildID:sourceURL:)` after Import Review commits, including exact duplicate ROMs. Reuse the artwork flow's partial-success reporting.

**Tech stack:** Swift, SwiftUI, managed file storage, the existing ZIP reader and GRDB repositories.

**Spec:** `docs/product.md`, Shared files and variable maps.

## Constraints

- Minimum deployment target: iOS 17.4.
- Accept only the two globals filenames, case insensitive. Ambiguous folders attach nothing.
- Keep the 4 MiB variable-map limit, ZIP safety checks and 32 matching-entry cap.
- A map attaches to an exact Build after library import. Quick Play remains temporary.
- Standalone maps use Attach Variable Map. Save migration remains planned.
- Use generated fixtures and keep this PR separate from Playtiles work.

## Files and responsibilities

- `ZipArchiveReader.swift`: select exact filenames and preserve archive paths for pairing.
- `SharedFileInbox.swift`: pair maps and own their receipt lifetime.
- `SharedFileView.swift`: supply the map and the existing attachment action to review.
- `ImportReviewViewModel.swift`: attach after ROM success and retain partial failures.
- `ImportReviewView.swift`: show the companion and reuse the partial-success alert.
- ZIP package tests and app inbox/review tests: exercise matching, ambiguity, size, cleanup, duplicate imports and errors.
- `docs/product.md` and `docs/backlog.md`: describe the supported flow.

## Task 1: ZIP receipt

- [ ] Add and run a failing regression proving archive paths and globals companions are dropped.
- [ ] Add exact-filename selection to `ZipArchiveReader.entries`, keeping unrelated `.i` files unread.
- [ ] Pair one map with one ROM in the same folder and keep it in the ROM receipt directory.
- [ ] Verify folder isolation, case, ambiguity, ignored entries, caps and cleanup.

## Task 2: Import Review

- [ ] Test a new Build, an exact duplicate, invalid map content and canceled/failed ROM imports.
- [ ] Pass the optional companion to review and attach with the existing use case after ROM success.
- [ ] Show the filename, allow skipping it, and report map failure without losing a successful ROM import.
- [ ] Update product and backlog descriptions.

## Task 3: Separate PR

- [ ] Run the real inbox tests in Linux with Apple URL security-scope methods shimmed.
- [ ] Run `make test-core`, repository hygiene and a full diff/prose review.
- [ ] Commit, push and open a PR against main; verify its text and macOS CI results.
