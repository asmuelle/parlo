# AGENTS.md — Operating Manual for Parlo

## Project Snapshot

Parlo is an iOS-first AI speaking partner for B1–B2 language learners (Spanish, French, German at launch) that runs **entirely on-device**: FoundationModels (~3B AFM) roleplay with structured turns, SpeechTranscriber/whisper.cpp ASR, AVSpeechSynthesizer TTS, and beta-grade Core ML pronunciation scoring. The wedge is **unlimited + offline + private + lifetime pricing** ($5.99/mo, $49.99/yr, $99.99 lifetime, hard paywall after 3 free conversations) against cloud incumbents (Speak, TalkPal, Duolingo Max) whose unit economics force metering. Payers: travelers, expats, immigrants who need speaking volume and practice where connectivity dies. Pipeline status: **runner-up** — viable with caveats; the adversarial review (see README.md) constrains scope hard.

## Read First

1. `README.md` — research dossier: market evidence, monetization, and the adversarial review that defines what we must NOT overpromise. Do not edit it.
2. `DESIGN.md` — architecture, module map, data model, key flows, milestones (M0–M3), risks. The build order lives here.
3. `TOOLS.md` — commands, env vars, CI behavior, harness notes.

## Commands (single source of truth — use `just`, never raw xcodebuild)

| Recipe | What it does |
|---|---|
| `just` | List recipes |
| `just bootstrap` | xcodegen generate + resolve SPM (fails with guidance if `project.yml` missing) |
| `just build` | `swift build` (root SPM package) + `Parlo` scheme for iOS Simulator when bootstrapped |
| `just test` | `swift test` (all packages) + app tests on the first available iPhone simulator |
| `just lint` | swiftlint (skips gracefully with a notice when not installed locally) |
| `just format` | swiftformat . |
| `just ci` | lint + build + test (what CI runs) |

## Repo Layout (expected after M0 bootstrap)

```
parlo/
├── project.yml              # XcodeGen spec (app shell)
├── Package.swift            # Root SPM manifest: one target per module under Packages/
├── App/                     # ParloApp target sources (composition root, navigation)
├── AppTests/                # App-hosted tests (run via xcodebuild on a simulator)
├── Packages/                # Module sources/tests (one Sources/ + Tests/ pair per module)
│   ├── ParloKit/
│   ├── ConversationEngine/
│   ├── SpeechKit/
│   ├── PronunciationBeta/
│   ├── Persistence/
│   ├── Paywall/
│   └── DesignSystem/
├── Tools/                   # Offline scripts (e.g. wav2vec2 → Core ML conversion)
├── justfile                 # All commands
├── AGENTS.md / DESIGN.md / TOOLS.md / README.md
└── .github/workflows/ci.yml
```

M0 (bootstrap) and the M1 vertical slice are implemented. `Parlo.xcodeproj` is generated (never committed) — run `just bootstrap` after cloning.

## Workflow for Agents

1. Orient: read README.md (constraints), DESIGN.md (current milestone), this file (invariants).
2. Plan: for cross-module or milestone-scale work, use the planner subagent before writing code.
3. TDD: failing test first in the owning package's `Tests/`; smallest implementation; refactor.
4. Verify: `just ci` locally; check the invariants list below for any touched module.
5. Review: run the code-reviewer subagent on the diff; fix CRITICAL/HIGH before committing.
6. Commit: conventional commit; update DESIGN.md/TOOLS.md if architecture or commands changed.

## Architecture Summary

A capture → on-device inference → store → surface pipeline: mic audio is transcribed verbatim on-device (SpeechTranscriber, whisper.cpp fallback), deterministically condensed to fit AFM's 4,096-token window, sent to a FoundationModels session emitting `@Generable RoleplayTurn { reply, correction?, naturalness }`, gated by deterministic validation before display, spoken via TTS, and persisted to SwiftData. Pronunciation scoring runs on a parallel path from **raw audio** (wav2vec2 forced alignment + GOP), never from ASR text. Modules (SPM packages, see DESIGN.md for details): `ParloApp` (shell) → `ConversationEngine`, `SpeechKit`, `PronunciationBeta`, `Persistence`, `Paywall`, `DesignSystem` → `ParloKit` (domain). Feature modules never import each other.

## Coding Standards

- Swift 6, strict concurrency enabled in every package; no `@unchecked Sendable` without a written justification comment.
- Files < 800 lines, functions < 50 lines; extract early.
- Immutability by default: value types, `let`, new copies over in-place mutation; reference types only where actor/state semantics demand it.
- Explicit error handling at every boundary: typed throws or `Result` at module seams; no `try!`/`try?`-and-ignore in production paths; user-facing failures get user-facing messages (e.g. "model still downloading"), logs get context.
- No hardcoded secrets — env vars only. (Parlo has no server and no API keys at runtime; anything CI-secret-shaped goes through GitHub Actions secrets.)
- Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`.
- swiftformat + swiftlint must pass; the Claude harness auto-formats Swift files on edit.

## Testing Policy

- TDD: write the failing test first (RED → GREEN → REFACTOR). 80%+ coverage target on `ParloKit`, `ConversationEngine`, `Paywall` logic.
- AAA pattern (Arrange-Act-Assert), descriptive behavior names, Swift Testing preferred (`@Test`), XCTest where UI/StoreKitTest requires it.
- What matters most for THIS product, in order:
  1. **Token-budget tests** — TranscriptCondenser math, overflow triggers, graceful degradation (the 4,096 window is the #1 crash risk).
  2. **CorrectionGate golden-set tests** — per-language fixture sets of learner utterances with expected show/suppress outcomes; regression-run in CI.
  3. **Structured-generation parsing** — `RoleplayTurn` decode failures must drop/retry, never render raw model text as a correction.
  4. **Zero-egress tests** — conversation modules contain no networking symbols (CI grep) + airplane-mode E2E.
  5. **StoreKitTest** — paywall counter, purchase, restore, lifetime unlock.
- Model-quality evaluation is NOT unit-testable — it goes through the golden-set harness and native-speaker QA (DESIGN.md M2), not assertions on live model output.

## PRODUCT INVARIANTS (non-negotiable — every PR must preserve these)

1. **Zero egress in the learning loop.** No audio, transcript, or derived learner data ever leaves the device. `ConversationEngine`, `SpeechKit`, `PronunciationBeta`, `Persistence` must contain no URLSession/Network/`socket` usage — enforced by CI grep and an airplane-mode E2E. Any future cloud path is opt-in, off by default, visibly labeled, and lives in a separate module.
2. **Every model turn is structured.** Conversation output is only ever a parsed `@Generable RoleplayTurn { reply, correction, naturalness }`. If guided generation fails to parse, retry or drop the turn — never display raw model text as feedback.
3. **No ungated corrections.** A correction reaches the screen only after `CorrectionGate` passes (differs from learner utterance, target-language parse, category sanity). Suppress-on-doubt is correct behavior; a wrong correction shown is a release blocker. Golden-set shown-correction precision ≥ 90%.
4. **The 4,096-token window is a hard budget.** Deterministic pre-call token check before every model invocation; condensation is automatic and audited (CondensationRecord); a session must never crash or silently truncate on overflow. Tested at ≥ 15 turns.
5. **Pronunciation scores come from raw audio, never ASR text**, and are always labeled **Beta**. No Speak/ELSA-parity claims anywhere in UI or App Store copy.
6. **Offline is the product.** Every shipped feature works in airplane mode. A feature that requires connectivity does not ship.
7. **Launch languages are es/fr/de only.** No language ships without its golden set passing native-speaker QA. (3B model quality at B1-B2 nuance is the fatal risk — see README adversarial review.)
8. **Paywall shape is fixed:** hard paywall after exactly 3 free conversations; the daily 2-minute pronunciation drill is free forever and never gated; StoreKit 2 only, no account system, no server.
9. **Latency budget:** p50 turn-to-first-audio ≤ 2.5s on supported devices, instrumented per turn. Regressions beyond budget block release.
10. **Honest framing.** UI, onboarding, and store copy say "conversation fluency partner", never "tutor that knows best" — corrections are suggestions, the register is a friend, not a red pen.

## Definition of Done

- [ ] Failing test written first; all tests green via `just test`
- [ ] `just ci` passes locally (lint + build + test)
- [ ] All 10 product invariants preserved (check #1–#4 explicitly for any ConversationEngine/SpeechKit change)
- [ ] Files < 800 lines, functions < 50, strict concurrency clean, no new warnings
- [ ] Errors handled at boundaries; no `try!` in production paths
- [ ] Coverage ≥ 80% on touched logic modules
- [ ] Conventional commit message; docs (DESIGN.md/TOOLS.md) updated if architecture or commands changed
- [ ] code-reviewer subagent run on the diff; CRITICAL/HIGH findings fixed
