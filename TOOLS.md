# TOOLS.md — Parlo Tool Surface

## just Recipes

| Recipe | What it does | When to run |
|---|---|---|
| `just` | Lists all recipes | Orientation |
| `just bootstrap` | Runs `xcodegen generate` from `project.yml`, then resolves SPM dependencies for the `Parlo` scheme. Prints guidance and exits 1 if `project.yml` does not exist yet (docs-only scaffold). | Once after clone, and after any `project.yml` or package-manifest change |
| `just build` | `swift build` for the root SPM package (the hard requirement), then `xcodebuild build` for the `Parlo` app shell when bootstrapped and an iPhone simulator runtime exists (notices and skips otherwise). | Before committing; after dependency changes |
| `just test` | `swift test` for all packages (always), then `xcodebuild test` on the first available iPhone simulator (prefers iPhone 16, falls back to e.g. iPhone 17) when bootstrapped. | TDD loop; before every commit |
| `just lint` | `swiftlint` over the repo; prints a notice and skips gracefully when swiftlint is not installed locally (CI always installs it). | Before committing (CI runs it too) |
| `just format` | `swiftformat .` | After larger refactors (the Claude harness already formats edited files) |
| `just ci` | `lint` + `build` + `test`, exactly what CI runs. | Final check before push |

Prerequisites (local): Xcode 26+ (iOS 26 SDK with FoundationModels), plus `brew install just xcodegen swiftformat swiftlint`.

## External Data Sources / APIs

Parlo's learning loop is 100% on-device — **no runtime API endpoints, no API keys, no server**. The "external" surface is on-device frameworks and bundled model assets:

| Dependency | Kind | Notes |
|---|---|---|
| FoundationModels (iOS 26+) | OS framework | ~3B AFM, 4,096-token context (Apple TN3193). Guided generation via `@Generable`. Free, zero marginal cost. Requires Apple Intelligence-capable device. |
| SpeechAnalyzer / SpeechTranscriber (iOS 26+) | OS framework | On-device ASR for supported locales (es/fr/de targeted). Locale assets download on demand via `AssetInventory` — the only sanctioned network use, OS-managed, no learner content uploaded. |
| whisper.cpp (small, Metal) | Vendored SPM dependency | ASR fallback. GGUF weights (~466 MB) fetched at build/bundle time, never committed (see .gitignore). Verbatim decode settings — no normalization. |
| wav2vec2 forced-alignment model | Bundled Core ML model | Converted offline (PyTorch → Core ML, conversion scripts live in `Tools/` post-M0). Versioned via `PronunciationScore.modelVersion`. Beta-grade. |
| AVSpeechSynthesizer | OS framework | TTS replies; premium voices where installed. Kokoro-82M via Core ML is a tracked stretch goal. |
| StoreKit 2 | OS framework | Subscriptions + lifetime IAP. Sandbox + StoreKitTest config for CI. |

## Required Env Vars

None at app runtime (by design — invariant #1 in AGENTS.md: no secrets, no server).

| Name | Scope | Purpose |
|---|---|---|
| `APP_STORE_CONNECT_API_KEY_ID` / `_ISSUER_ID` / `_KEY_P8` | CI only (GitHub Actions secrets, M3+) | TestFlight/App Store upload when release lanes are added. Not needed for `just ci`. |

## Local Services

None. No docker, no database server — persistence is on-device SwiftData. The only "service" is the iOS Simulator (iPhone 16 runtime installed via Xcode).

## CI Overview (`.github/workflows/ci.yml`)

- Triggers: `push` and `pull_request`. Runner: `macos-26` (Xcode 26 / iOS 26 SDK, required by the Package.swift platform floor).
- Steps: checkout → setup-just → `brew install` swiftformat, swiftlint, xcodegen → **bootstrap guard**: if `project.yml` is absent, the job emits a notice and skips build/test so the docs-only scaffold stays green; if present, it runs `just bootstrap` then `just ci`.
- Keep it green: never merge with a red `just ci`; if the guard is skipping and you just added `project.yml`, CI starts enforcing the full pipeline on that same PR.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `just bootstrap` fails: "project.yml not found" | Expected pre-M0 — the repo is docs-only. Build M0 first (DESIGN.md). |
| `just build`/`just test` fails: "Parlo.xcodeproj missing" | Run `just bootstrap` (regenerates the project from `project.yml`). |
| `xcodebuild` can't find iPhone 16 destination | The `just build`/`just test` recipes auto-fall back to the first available iPhone simulator (e.g. iPhone 17 Pro on Xcode 26). If none exists: Xcode → Settings → Components, or `xcodebuild -downloadPlatform iOS`. |
| FoundationModels unavailable in simulator/tests | Guard with `SystemLanguageModel.default.availability`; unit-test against the protocol seam (mock model), keep live-model checks on device. |
| SpeechTranscriber locale asset missing | `AssetInventory` download is async and OS-managed; tests must stub the ASR seam, never await real downloads. |
| swiftlint/swiftformat missing locally | `brew install swiftformat swiftlint` (CI installs them itself). |

## AI Harness Notes (`.claude/settings.json`)

- **Hooks (PostToolUse on Write|Edit):** edited `*.swift` files are auto-run through `swiftformat`, then `swiftlint` (first 10 findings echoed). Don't hand-format; fix lint findings as they surface.
- **Permissions:** `just`, `xcodebuild`, `xcrun`, `swift`, `swiftformat`, `swiftlint`, `xcodegen`, and read-only git are pre-allowed. Prefer `just` recipes over raw tool invocations.
- **Useful subagents for this repo:**
  - `tdd-guide` — start every new feature here (token budgeting, CorrectionGate, condensation are all test-first naturals).
  - `code-reviewer` — after every change set, before commit (Definition of Done requires it).
  - `security-reviewer` — for anything touching audio capture, persistence, paywall/entitlements, or any code that could violate the zero-egress invariant.
  - `planner` — before starting a milestone (M1–M3 in DESIGN.md) or any cross-module change.
- **Skills worth invoking:** `foundation-models-on-device` (AFM + `@Generable` patterns), `swift-concurrency-6-2`, `swiftui-patterns`, `swift-protocol-di-testing` (for mocking ASR/TTS/model seams in tests).
