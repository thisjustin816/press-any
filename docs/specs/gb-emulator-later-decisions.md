# Later approved decisions

Decisions approved after the product and MVP specifications and the Q1-Q186
decision log (`gb-emulator-decisions.md`). Where they conflict, this file wins;
`docs/decisions.md` records decisions made since and wins over both. A decision
here is not a claim that the code already implements it.

## 1. Identity, business model, scope

- The product name is Press Any; `docs/NAMING.md` lists its identifiers.
- Official App Store distribution may be paid up front or use IAP to unlock
  features, even while source is open. Project-owned source is Apache-2.0
  (`LICENSE`); that does not relicense third-party assets.
- iOS 17 is the minimum.
- iPhone-first. iPad-specific polish, split-screen manuals and other devices are
  later. SameBoy for GB/GBC; mGBA for GBA later. Chromecast remains out of scope.
- Other retro systems are not planned product work, but must not be precluded by
  fundamental library/storage/input/core abstractions.
- The MVP is an architecture proof before the full-featured v1, and it includes
  SDK/toolchain detection.
- iCloud and the Community Catalog target v1, with an explicit review that can
  move them to v1.1 if they alone hold up the emulator. Neither is MVP.
- Progressive disclosure is mandatory: normal UI -> Customize/context menu ->
  Advanced -> Developer Mode. Preserve powerful options without settings clutter.

## 2. Platform is separate from hardware and distribution

Software platform IDs are neutral stable values such as `gb`, `gbc` and `gba`.
They are data identifiers, so the product name never appears in them.

Keep separate concepts:

- PlatformDescriptor: emulated software environment, its name, media/input
  descriptors and original manufacturer as metadata.
- HardwareDescriptor: physical device, e.g. original GBC or ModRetro Chromatic.
- DistributionDescriptor: release/marketing ecosystem, e.g. a Chromatic release,
  retail, homebrew or hack classification where useful.
- CompatibilityRecord: observed/claimed compatibility, outcome, provenance,
  notes, tested version/date and relevant requirements.

A release marketed for Chromatic can still have platform `gbc`. Marketing does
not choose an emulator core. Do not infer compatibility with every device from
one platform label. Other platforms such as N64 are not in scope.

Core compatibility is distinct from hardware compatibility: a SameBoy test must
refer to a core/version/configuration, not pretend SameBoy is physical hardware.
A compatibility schema therefore needs a core target as well as a hardware target.

Genericize contracts where they already matter:
`ROMImage -> GameImage`; persistent-save internals use `PersistentSave` rather
than assuming every future platform has battery SRAM. GB-specific UI still says
ROM and .sav. Add small registries/seams for platforms, cores, image analyzers,
toolchain detectors and patch formats. Add input/memory descriptors. (Cores and
toolchain detectors have registries in the MVP; platforms, image analyzers and
patch formats wait for v1, per `docs/decisions.md` "Adaptive audio, and
registries wait for v1".)

Do not build disc swapping, arcade sets, generic BIOS management, light guns,
multitaps or other future capabilities now. SameBoy/GB header/model/camera/
printer/SGB details stay in the GB adapter. Core registration remains GB/GBC only.

## 3. Unchanged library and identity invariants

Game -> Builds -> Save Profiles remains the fundamental model. A Game is not a
ROM hash. Build has its own UUID; content hash identifies immutable executable
bytes, not ownership or every possible library representation of those bytes.
A copied/promoted Build may share a blob without sharing user records.

A committed Build's image identity is immutable. Byte or patch-stack changes
create a new Build/result. Do not weaken immutability to only after first launch.

Lineage is independent of Game ownership. Move/copy Build to a separate Game
(default Move), or merge it into another Game, with review for inherited
artwork, documentation, tags/collections and compatible saves. Preserve Build
UUID on move; copy creates new ownership identity while retaining provenance.

Multiple base Builds/regions/revisions are allowed. Preferred Build is explicit
and not silently replaced by a recently tested Build. Each Build may select its
preferred Save Profile, falling back to Game preference and compatibility checks.

Keep original filename, canonical metadata, clean display name, aliases and
provenance separate. No-Intro/Maybe-Intro-like parsing is evidence, not a license
to invent author/version fields. Manual values always win locally; hashes cannot
be edited. Unknown ROMs may be manually matched to known titles/lineage without
possessing the base ROM. Regional grouping is reviewable, not irreversible.

## 4. Persistent saves, states, lifecycle

Persistent save belongs to a Save Profile; Build can deliberately share a
compatible profile. Profiles can be blank, imported, duplicated, migrated later,
or promoted from Quick Play. Store ancestry subtly; no full tree UI required.

There is no general rolling battery-save history. Use profile forking and
isolation. Explicit replacement has a safety copy; migration works on a copy.
Do not interpret that as allowing unsafe in-place file truncation.

Save states require exact Build + profile + image hash + core/serialization
context. Manual/quick/slot states, lifecycle autosaves and crash recovery remain
separate. Store thumbnail, timestamp, Build/playtime/label and cheat context.
Do not silently restore cheat settings. Retention is configurable; pinned states
are exempt; lifecycle history defaults to five states.

Backgrounding pauses emulation/audio and attempts durable save plus Auto State;
auto-resume defaults Always with Always/Ask/Never overrides. Do not assume a
force-kill/crash will provide a final callback. Separate crash recovery must avoid
an automatic crash loop. One active emulator session in v1. In-game Build/profile
switching saves/stops/relaunches through compatibility checks, never live swaps
ROM bytes. Brief backgrounding can keep in-memory rewind only while process and
buffer survive; no durable rewind timeline is promised.

Core first launch chooses a compatible installed version and records/pins it.
Migration is explicit with a checkpoint; old state history stays identifiable.
No requirement to ship old core binaries in v1. Therefore actual old-core
execution/rollback can only be offered when that implementation is available.
Do not claim recording a version string preserves unavailable executable code.

## 5. MVP SDK/toolchain detection

Standalone detector seam, reused by Import Review, Build Technical Info, Quick
Play and save compatibility. GB implementation adapts gbtoolsid fingerprint
logic/data; do not spawn its CLI on iOS. Preserve upstream provenance/notices.

Report engine, compiler/toolchain, libraries/audio drivers, version or range,
categorical confidence, evidence, detector version and corpus revision. Unknown
is valid; multiple layers may coexist (GB Studio over GBDK, with an audio driver).
Do not guarantee RGBDS detection or infer one engine from any compiler hit.

Detection never determines Game identity or proves save compatibility. Different
GB Studio Builds may rearrange globals even at the same engine version. Risk
analysis recommends a fork rather than using a shared profile silently.

Attach globals.i/game_globals.i or other validated maps to the exact Build and
record source/format. Detection, sidecar attachment and safe copy flows are MVP;
actual variable remapping/save migration is v1.1/later and must be version gated.
Never claim reliable migration from just old ROM + old save + new ROM.

Tests: known-positive engine/toolchain fingerprints, negative/ambiguous corpus,
version/evidence preservation, persistence, Quick Play/import presentation,
compatibility routing, no Game-identity mutation. Use synthetic or rights-cleared
fixtures. Included-game expected SDKs must be verified, not copied from earlier claims.

## 6. Import, patching, storage, Quick Play

Analyze -> evidence -> proposed plan -> user review -> commit. No mutation of
permanent library during analysis. UI does not assemble database records and
committers do not guess relationships. Simple imports stay simple.

Multi-file import is first-class: classify ROMs, IPS/BPS, saves, artwork, manuals,
README/changelog, variable maps and other relevant items. Show existing/manual,
automatically fetched and packaged artwork visually before committing choices.
Exact duplicate image imports still inspect new assets; don't duplicate a Build
just because a manual/cover/save arrived with the same ROM.

ZIP + 7z are v1 import containers; don't retain them as duplicate library assets.
RAR is tentative later. Inspect signatures and parsing validity, bound extraction,
reject unsafe paths/links and recursive bombs, handle passwords/malformed data.
libarchive is the selected implementation direction, not a verified iOS binary
wrapper commitment. Archive/UI/document breadth is not an MVP launch blocker.
Foreign skin packages are a separate intentional source-retention exception.

IPS+BPS are MVP/v1. Preserve source ROM and original patches. Recipes record exact
base, ordered transforms, enabled state and engine versions. Recipe fingerprint
is not executable identity; executable identity is result bytes' digest. Editing
recipe produces a new Build. Generated output may be evicted only when genuinely
reconstructible; verify rebuilt hash before launch. Missing base/patch source is
not solved by treating the only surviving output as disposable.

Persistent content addressing and mutable saves need safe, explicit lifecycle
semantics. Immutable file placement before DB references permits orphan cleanup
on failed commits, but never a committed pointer to a missing staged file. Use
idempotent operations and protect in-flight objects from GC. Source/user data are
not casually purged because of a storage-class or stale refcount mistake.

Quick Play creates no permanent Game/Build until promotion. Always copy a library
save into its isolated workspace. Retention defaults 24h with immediate/7d
options and Keep/Import. Promotion can retain library save, explicitly replace
with safety copy, or create a new profile. Keep generated captures/notes/context
with the session and transfer them transactionally. No shared mutable save path.

## 7. Settings, input and display

App -> System -> Game -> Build inheritance with unset versus explicit values
and Reset to Inherited. Narrow profile overlay only for playthrough-related
cheats, RTC, autoresume and rewind where appropriate; not a universal fifth tier.

Reusable named controller profiles per type; inherited mappings and overrides.
Multiple controllers may be detected but one Player 1 selected in v1. Disconnect
pauses and reveals touch controls. Physical controller activity hides touch
controls unless overridden. Light button haptics default on, suppressed with an
active physical controller; distinct from cartridge rumble. Rumble prefers
supported controller then phone, with separate intensities and routing override.

Touch supports sliding D-pad/A/B, multitouch, visible pressed states, optional
gestures off by default, optional turbo A/B. Passive Playtiles/GameBaby layouts
are manually chosen/calibrated per device; do not invent electronic detection.
Connected identifying accessories may suggest, not force, a layout.

Lightweight visual layout editor is v1; pause and align against frozen frame.
Editing shared layout offers Save for Game versus Update Shared Preset. Native
preset sharing plus independently implemented Delta/Manic compatibility are v1.
Keep imported package for reconversion, report unsupported features, never
silently mis-map input. Full custom-art skin authoring is later.

Native core timing authoritative; full-speed/correctness ahead of optional
shaders. Adaptive audio, interruption handling and thermal reduction of optional
work. Rewind is memory-budgeted with 5/15/30s and 1/2/5m presets. FF choices
1.5/2/3/4/8/unlimited; configurable muted/accelerated audio. Slow 0.25/0.5/0.75.
SGB support where the core exposes it; automatic model selection with overrides.
No general claim that every CGB-only game can be forced to work in DMG mode.

## 8. Artwork providers and rights gates

There is no paid commercial artwork agreement.
Keep independent provider adapters and seek open/permissive no-fee sources,
without pretending another emulator's commercial distribution grants rights.

Approved provider architecture: included/imported/local, Community Catalog,
OpenVGDB experimental pending license review, Libretro thumbnails, optional
SteamGridDB using the user's key, and generated/title-screen fallback.
Provider interfaces and UX approval do not equal approval of every image/license.

Existing manual choice/crop/title override always wins. New import gathers
packaged/hack-specific/remote candidates for visual review; no unquestioned
remote replacement. Cache selected primary artwork only by default. Explicitly
saved extra types remain stored. No automatic artwork recheck after selection;
manual Check for New Artwork is supported. Game art can be overridden by Build.

Save provider ID, asset/source URL, fetch timestamp, related title, rights/license
metadata where known, selection provenance and non-destructive crop. Never
publish private user artwork or infer permission from a user API key.
No-Intro identity data and user-uploaded scans are separate resources/rights.
Re-check current official terms before shipping or mirroring external media.

## 9. Shaders - curate existing work, not needless reimplementation

Prefer familiar LCD1x/LCD3x and pixel-transparency variants rather than
reimplementing everything. v1 uses BuiltIn plus curated CommunityDownload
providers; arbitrary user .slang/.slangp import is later. PT-SkyWalker541 is a
promising permissive candidate to audit/benchmark, not a chosen final renderer.

Catalog entries: stable ID/name, upstream URL/commit/path, per-file license and
attribution, expected hashes, dependency graph/includes/LUTs, pipeline/runtime
requirements, tested compatibility/platforms and parameter definitions.

Download chosen packs, validate hashes/dependencies and paths, preserve licenses,
compile/convert/cache through the actual supported renderer. Keep a small vetted
recommendation set instead of the entire repository. Do not claim implementing
a downloader alone makes Slang run on Metal. Host/compiler integration is a
separate engineering/dependency review.

Independent inheritance for pipeline components/parameters; user-named reusable
presets; live Quick Actions switching. No required shader-cycle controller hotkey.
Default authentic appearance; exact presets await device comparison/performance.

Do not relabel downloaded GPL/community shader code Apache. Download timing is
not a licensing exemption or guaranteed App Store compliance. Built-ins favor
permissive licenses; copied GPL/AGPL application components require review.

## 10. Included games

A small set of rights-cleared homebrew games may ship as optional Included Games.
Candidate titles are tracked outside the repository until their creators approve.
Implement an optional Included Games catalog/manifest and the normal import path.
No silent library population; no privileged database shortcut.

Manifest: schema, stable ID, title/author, platform/compatible modes, release and
ROM hash/size/source, source URL, separate code/assets licenses, attribution,
artwork, tested SDK/core expectations, and permission record. `releaseApproved`
remains false until approval. A release must fail if it actually packages an
unapproved ROM. Unselected candidate entries alone must not block a ROM-free
MVP. Do not automatically update bundled ROMs on upstream release.

Private correspondence need not be public, but an approval reference and exact
approved artifact/version should be recorded. Source availability and creator
permission alone do not establish third-party character or artwork rights.

## 11. GitHub Actions is required for every generated pipeline

Create reproducible, reviewed automation rather than undocumented laptop jobs.
Use pinned source revisions/actions, input hashes, schemas, generator versions,
provenance and output digests. Update jobs open PRs, not auto-merge/publish changes.
Keep untrusted fork jobs without secrets/write credentials. Separate validation,
review, release signing/attestation and publication. An action cannot magically
verify ambiguous licenses or obtain creator permission.

Required workflow intents:

- ci.yml: host Swift build/tests by actual module boundaries; L1/L2/L3 statuses.
- ios-build.yml: Mac SDK build/simulator gates; physical iPhone separate.
- no-intro-update.yml: acquire permitted official GB/GBC data, normalize hash/
  name/region/language/revision/family fields, validate/diff, build compact
  offline data/manifest, reviewed release update. No uploaded imagery.
- toolchain-fingerprints-update.yml: pinned gbtoolsid corpus extraction,
  positive/negative tests, deterministic artifact/provenance, reviewed PR.
- shader-catalog-update.yml: whitelist upstreams, audit per-file licenses,
  dependencies/hashes, parser/compatibility checks, reviewed catalog change.
- included-games-verify.yml: exact approved ROM/attribution/permission manifest,
  import/headless checks; never auto-fetch a new unapproved release into app.
- fixtures.yml: reproduce synthetic ROMs/patches with pinned tools.
- license-audit.yml: SBOM/notices/review status and dependency-policy gates.
- privacy-audit.yml: manifests/dependency changes plus human disclosure review.
- generated-content validation: regeneration cleanliness and schema checks.
- openvgdb-update.yml: experimental/disabled for release until data licensing
  is established. Extraction/reformatting does not eliminate license terms.

First implement runnable infrastructure and honest gated/disabled workflows for
pipelines whose source access/rights are unresolved. Do not mark a TODO workflow
that merely echoes success as a completed pipeline.

## 12. Open-source and monetization boundaries

Apache-2.0 for project-owned source, not dependencies or game/media resources.
Prefer permissive dependencies. mGBA MPL obligations require deliberate later
compliance; GPL/AGPL/LGPL linked components require approval. Independent Delta/
Manic format compatibility must not copy their AGPL implementation. Only the
SameBoy reusable core/library, not its restricted iOS frontend, is intended.

GRDB resolves through SwiftPM at a pinned version and SameBoy is a pinned upstream
submodule (`THIRD_PARTY_NOTICES.md`). Do not publish private patch examples, tool
configs, secrets or unreviewed history.

Future root documentation: LICENSE, notices, dependency/content policy,
CONTRIBUTING, SECURITY, PRIVACY, AGENTS, code of conduct and trademark policy.
Contributions use DCO-style signoff; there is no copyright-assignment CLA. Brand/logo asset rights are separate; don't claim registration.

FeatureEntitlementProvider keeps StoreKit out of Domain/core/storage/import.
Development/test/App Store implementations; no prices/feature gates decided for
MVP. Loss of entitlement must not destroy or lock away existing saves, exports,
backups or user-created data. Source builds need not implement an obfuscated DRM
system. App Store payment/privacy rules need final current-market review.

## 13. Community Catalog, privacy and updates

The backend is post-MVP and PostgreSQL/Supabase-shaped; no service exists yet. Anonymous read, identity for contribution, optional
public attribution, moderation before canonical updates, field-level suggested
corrections with source/evidence and rejection reasons. No social comments/rating
system required. Local overrides are never overwritten by provider refresh.

Model titles/releases/build hashes, platform/hardware/distribution/compatibility,
authors/sources, lineage, artwork/patch rights, submissions/changes/moderation,
reports and blocked contributors. No base-ROM hosting. Future creator-hosted
homebrew publication is separate. Factual original community metadata aims for
CC0; imported external data and media retain their own rights. No blanket
relicensing of artwork/patches by a checkbox from someone who lacks ownership.

Update checks default quiet badges, optional predownload of verified/authorized
updates. Per-Game override, no channel complexity. Show author release notes,
version/date/source/known compatibility. Downloaded updates create new Builds
through normal review/compatibility, never overwrite installed image/state.

Opt-in crash reports limited to non-content diagnostics. No automatic upload of
ROMs, saves, screenshots, memory, filenames, library titles or personal notes.
Bug-report export is separately previewed/explicit. Provider queries and catalog
uploads must have accurately described privacy/consent boundaries. Keep service
keys server-side/user keys in secure storage, not the public client source.

## 14. Saved v1 details remain in force

Full cheats/search/memory editor, captures with optional frame-consistent debug
context, notes, tags/collections, live indexed metadata search, build timeline/
binary summary, documents and backup features remain as described in the saved
full product/log. These are not all MVP blockers.

Documents: PDF, CBZ/images, TXT/Markdown; Game/Build/both semantic associations,
managed copies, last-read position, pause overlay then restore previous state.
Search only text-bearing formats if easy, low priority; no OCR/bookmark suite now.

iCloud: all chosen library state except ROM/image blobs; field merges when safe;
divergent saves preserved for explicit resolution; deletion tombstones and 30-day
Recently Deleted prevent resurrection. Never equate tombstone expiry with safe
removal of deletion knowledge from an arbitrarily offline replica.

Backup: documented versioned manifest/ordinary files, optional ROM inclusion,
optional password encryption, reviewed merge by stable IDs/hashes or explicit
replacement, compatibility report. Future foreign-emulator import adapters must
report unsupported state formats rather than treating snapshots as portable.

AirPlay/external display: independent game render target and phone controller/
Quick Actions/manual companion. One frame's game state, not UI mirroring only.
Link/camera/printer v1.1, GBA later; potential proximity initiation is research
and platform/version gated, not a shipping transport guarantee.

## 15. Scope and acceptance

MVP must prove Game/Build/Profile identity, safe save isolation and reuse, manual
states/lifecycle, IPS/BPS base preservation and deterministic cache rebuild,
Quick Play promotion, promote/merge lineage, persistence/managed filesystem,
SameBoy headless + iPhone integration, basic touch/controller/video/audio, settings
inheritance, and SDK detection. Prefer small real implementations over large
unvalidated scaffolds for everything described in the product roadmap.

End-to-end automated proof uses synthetic/clearly redistributable game images,
not required commercial ROMs. Same Game survives new Builds; risky save becomes
a copy; old state never loads silently into new Build/profile; evicted derived
image reproduces exact hash; Quick Play mutations leave original save intact;
move/merge retain correct references and provenance.

L1 = domain; L2 = real persistence/storage; L3 = headless SameBoy; L4 = Apple SDK/
simulator/physical-device gates separately. Do not claim L4 from syntax checks,
or whole-MVP verification from a subset of targets that skip GRDB on Linux.
