# Acceptance matrix

The levels are cumulative evidence classes. A higher level does not erase an
unresolved lower-level failure.

| Level | Scope | Required evidence |
|---|---|---|
| L1 | Domain and pure application logic | Swift tests for identity, immutability, settings, save/state context, patch rules, Quick Play rules, detector behavior, and synthetic fixtures |
| L2 | Real persistence and managed storage | GRDB migrations/repositories/transactions, on-disk asset lifecycle, rollback, corruption, GC coordination, deterministic rebuild, restart behavior |
| L3 | Headless SameBoy | Pinned core build, synthetic or clearly redistributable images, frame execution, save/state round trips, bounded buffers, core migration context |
| L4a | Apple SDK compile | Clean dependency resolution, generated project, iOS simulator compile/test, resources, Metal, audio, controllers, availability checks |
| L4b | Simulator behavior | Launch and automated/manual flows possible in simulator, with known hardware limitations recorded |
| L4c | Physical iPhone | Recorded device/iOS/build/core/input/content hashes and full gameplay/lifecycle proof |
| Release | Distribution, rights, privacy, signing | Approved name/identifiers, dependency and content licenses, included-game permission, disclosures, signing, App Store review |

## MVP end-to-end scenarios

- Import a base image, then a modified image into the same Game without changing
  Game identity.
- Fork a risky save; prove the original remains unchanged.
- Refuse silent state loading under a different Build, profile, image, or core
  serialization context.
- Evict a derived image and reproduce its exact digest from retained sources.
- Mutate a Quick Play save and prove the original library save is unchanged.
- Promote Quick Play with each supported save disposition.
- Move a Build and merge it back while retaining identity, lineage, and valid
  references.
- Detect known-positive, negative, ambiguous, and multilayer SDK/toolchain
  fixtures without mutating Game identity.

## Synthetic fixture policy

- Use generated or clearly redistributable GB/GBC images for automation.
- Generate IPS/BPS fixtures deterministically from recorded source inputs.
- Record tool versions, commands, source hashes, expected output hashes, and
  licenses or authorship.
- Keep private user patch examples out of public CI unless redistribution is
  explicitly cleared.
- Commercial ROMs, proprietary boot ROMs, private saves, permission emails, and
  private artwork do not enter public fixtures or logs.
- Expected toolchain labels need evidence from the fixture build or inspected
  fingerprints. Do not copy an earlier unverified claim into test expectations.

## Claim language

- "Passed L1/L2/L3/L4" requires a current recorded command or device run at that
  level.
- A syntax parse is never an Apple SDK build or device test.
- A test filename or declaration is never coverage proof by itself.
