# Parlo — Design Doc

## Thesis

Every cloud tutor must meter speaking practice because every turn costs them money; Parlo's marginal cost per turn is zero, so "truly unlimited" is a structural position, not a promo. The defensible wedge is **offline + unlimited + private + lifetime pricing** — planes, subways, and abroad-without-data are exactly where B1–B2 travelers, expats, and immigrants practice, and exactly where Speak, TalkPal, and Google's free practice die. We win by shipping an honest iOS-first "conversation fluency partner" for Spanish/French/German that a 3B on-device model can actually deliver — not by overpromising a Speak-quality tutor.

## Architecture

iOS-first. Swift 6 (strict concurrency), SwiftUI, modular SPM packages composed by an XcodeGen-generated app shell. Android (Gemma 3n / LiteRT-LM, flagship-gated) is phase 2 and out of scope for this repo until M3 ships.

### Pipeline (capture → on-device inference → store → surface)

```
Mic (AVAudioEngine)
  → VAD + raw audio buffer retained          [deterministic]
  → ASR: SpeechTranscriber (es/fr/de locales)
         whisper.cpp small (Metal) fallback   [on-device model]
  → TranscriptCondenser (token budget check)  [deterministic]
  → FoundationModels LanguageModelSession
      @Generable RoleplayTurn
      { reply, correction?, naturalness }     [on-device 3B AFM]
  → CorrectionGate (validate before display)  [deterministic]
  → TTS: AVSpeechSynthesizer premium voice
         (Kokoro-82M via Core ML, stretch)    [on-device]
  → Persistence (SwiftData)                   [deterministic]
  → SwiftUI surfaces (chat, review, drill)
```

Pronunciation runs on a **parallel path from raw audio**, never from ASR text (ASR error-corrects learner speech and destroys the diagnostic signal): raw buffer → Core ML wav2vec2 forced alignment → GOP scoring → beta-labeled syllable feedback.

### Non-goals (scope discipline from the adversarial review)

- No cloud inference at launch — not even as a silent fallback. The escape hatch (Gemini Flash for unsupported devices) is post-M3, opt-in, labeled.
- No Speak-parity pronunciation claims; no per-phoneme "scores" presented with fake precision.
- No Android until M3 ships and iOS proves the loop (flagship-gated Gemma 3n plan stays in README).
- No language beyond es/fr/de until its golden set passes native-speaker QA.
- No accounts, no server, no analytics that touch speech content.
- No 20B-class model ambitions — design every prompt and feature for the ~3B / 4,096-token reality (TN3193).

### Cost discipline

| Layer | What runs there | Why |
|---|---|---|
| Deterministic code | VAD, condensation triggers, token budgeting, correction gating, paywall, scoring aggregation, spaced repetition | Cheap, testable, never hallucinates |
| Small on-device model | AFM ~3B roleplay turns, SpeechTranscriber/whisper.cpp ASR, wav2vec2 alignment | Zero marginal cost — this IS the product moat |
| Frontier cloud model | **None at launch.** Optional Gemini Flash escape hatch is post-M3, off by default, clearly labeled | Offline + private promise is the wedge; cloud-by-default kills it |

### Module map (SPM packages under `Packages/`)

| Module | Responsibility |
|---|---|
| `ParloApp` (XcodeGen target) | Composition root, navigation, DI wiring |
| `ParloKit` | Domain models, session state machines, token budget math |
| `ConversationEngine` | FoundationModels session, `@Generable RoleplayTurn`, scenario profiles, `TranscriptCondenser`, `CorrectionGate` |
| `SpeechKit` | `AsrService` (SpeechTranscriber + whisper.cpp fallback), `TtsService`, audio capture/VAD |
| `PronunciationBeta` | wav2vec2 forced alignment + GOP scoring, beta labeling |
| `Persistence` | SwiftData store, repositories |
| `Paywall` | StoreKit 2, entitlements, free-tier counters |
| `DesignSystem` | Tokens, typography, components, scenario art |

Dependency rule: `ParloApp → feature modules → ParloKit`. Feature modules never import each other; they communicate through `ParloKit` types.

## Data Model Sketch

- **LearnerProfile** — target language (es/fr/de), self-assessed level (B1/B2), native language, streak, TTS voice prefs, settings
- **Scenario** — id, title, language, persona description, situation prompt, difficulty, seed vocabulary, locale notes (the "Dynamic Profile" fed to AFM)
- **ConversationSession** — id, scenarioId, startedAt/endedAt, status, running condensed summary, cumulative token estimate
- **Turn** — sessionId, index, role (learner/partner), rawAudioRef, verbatimAsrTranscript, asrEngine (speechTranscriber/whisper), reply, naturalness note, end-to-end latencyMs
- **Correction** — turnId, original span, corrected span, category (grammar/vocab/register), gate result (shown/suppressed + reason), learner reaction (accepted/dismissed)
- **PronunciationScore** — turnId, phoneme/syllable spans with GOP scores, model version, `isBeta = true` (always, until stated otherwise)
- **CondensationRecord** — sessionId, replaced turn range, summary text, tokensBefore/tokensAfter (audit trail for the 4096 budget)
- **VocabItem** — phrase, gloss, scenario origin, next review date (light spaced repetition)
- **Entitlement** — plan (free/monthly/annual/lifetime), freeConversationsUsed (cap 3), dailyDrillLastUsedAt

## Key Flows

### 1. Roleplay turn loop (the core loop)

1. Learner taps mic in a scenario (e.g. "Ordering at a Madrid café"); AVAudioEngine captures; VAD detects end of utterance.
2. Raw audio buffer is retained for pronunciation; ASR produces a **verbatim** transcript (SpeechTranscriber for es/fr/de; whisper.cpp with normalization-off decoding otherwise).
3. `TranscriptCondenser` checks the running token estimate; if the next prompt would exceed the budget (~3,200 of 4,096 tokens), it condenses (Flow 2) first.
4. `ConversationEngine` calls the `LanguageModelSession` with the scenario profile + condensed history + new utterance, requesting a `@Generable RoleplayTurn { reply, correction?, naturalness }`.
5. `CorrectionGate` validates: correction must differ from the learner's utterance, parse as the target language, and pass category sanity checks — otherwise it is suppressed and logged, never shown.
6. Reply streams to TTS immediately (latency budget: ≤ 2.5s p50 to first audio); correction renders as a dismissible chip; naturalness as a subtle meter.
7. Turn persisted with latency, gate result, and audio ref. Loop.

### 2. Transcript condensation (living inside 4,096 tokens — Apple TN3193)

1. Trigger: projected prompt tokens > budget threshold, checked deterministically before every model call.
2. Oldest non-pinned turns are summarized into a single running summary turn (scenario state, established facts, learner error patterns) by a dedicated short summarization call.
3. A `CondensationRecord` logs tokensBefore/tokensAfter; if condensation fails, the session degrades gracefully (drops oldest turns) — **a session never crashes or silently truncates mid-turn on context overflow.**

### 3. Daily pronunciation drill (free, outside the paywall)

1. Learner opens the daily 2-minute drill (ASO/retention hook; available even on free tier after the 3-conversation cap).
2. Target phrase displayed; learner records; raw audio → wav2vec2 forced alignment → per-syllable GOP scores.
3. Feedback rendered with explicit "Beta" labeling — colored syllable heat, no fake precision, no Speak-parity claims.
4. Score stored; weak phrases feed `VocabItem` review.

### 4. Hard paywall

1. Conversations 1–3 are fully free; counter in `Entitlement` (device-local + StoreKit-verifiable, no server).
2. On starting conversation 4, the paywall presents: $5.99/mo, $49.99/yr (anchor; $39.99 launch/win-back offer), $99.99 lifetime. Copy leads with **unlimited + offline + private**, not "cheap".
3. StoreKit 2 purchase → entitlement unlock → return directly into the scenario the learner tried to start.
4. Daily drill remains free regardless — never gate it.

### 5. ASR engine selection & fallback

1. On session start, check SpeechTranscriber locale availability for the target language; request asset download if needed.
2. If unavailable (locale unsupported, asset download failed, OS too old), fall back to bundled whisper.cpp small (Metal), with decode settings tuned for verbatim output.
3. The engine used is recorded per turn; pronunciation scoring is engine-independent because it consumes raw audio.

## Product & Visual Design Direction

**"Travel journal at a café table"** — warm, analog, personal; the opposite of gamified-neon Duolingo and corporate-SaaS Speak. Light UI default. Palette: warm paper cream surfaces (`oklch(97% 0.02 85)`), espresso ink text, terracotta primary accent, olive secondary, with one deep teal reserved semantically for corrections (corrections are calm, never red/alarming — shy learners are a core segment). Typography: New York (serif) for scenario titles and session recaps — the travel-journal voice; SF Pro Rounded for conversation bubbles and UI — approachable, low-stakes. Texture: subtle paper grain on scenario cards, ticket-stub/stamp motifs marking completed sessions and streaks. Motion: conversation bubbles settle with a gentle spring; the naturalness meter fills like ink. Every correction interaction is designed to feel like a friend leaning over, not a teacher's red pen.

## Milestones

### M0 — Bootstrap (make `just ci` green)

- `project.yml` (XcodeGen) defining the `Parlo` app target + local SPM packages per the module map; empty-but-compiling modules with one placeholder Swift Testing test each.
- `just bootstrap && just ci` passes locally and on `macos-15` CI (lint + build + test on iPhone 16 simulator).
- swiftformat + swiftlint configs committed; Swift 6 strict concurrency on in every package.
- **Accept:** fresh clone → `just bootstrap` → `just ci` exits 0.

### M1 — Thin vertical slice (one scenario, one language, fully offline)

- "Ordering at a café" scenario in **Spanish only**: mic → SpeechTranscriber → condensation-aware AFM `@Generable RoleplayTurn` → CorrectionGate → AVSpeechSynthesizer reply → SwiftData persistence → chat UI with correction chips and naturalness meter.
- TranscriptCondenser working with token audit records.
- **Accept:** a 15-turn conversation completes in **airplane mode** on an iOS 26 device without context overflow, crash, or any network call; p50 turn-to-first-audio ≤ 2.5s; every displayed correction passed the gate; raw audio retained per turn.

### M2 — Trust layer (prove "private" and "honest")

- PronunciationBeta: Core ML wav2vec2 forced alignment + GOP, daily drill UI, all feedback Beta-labeled.
- Network egress proof: zero-egress test (no URLSession/Network usage in conversation modules enforced by a lint/CI grep + an instrumented airplane-mode E2E), privacy nutrition label drafted ("data not collected").
- Correction-quality harness: golden set of ~200 learner utterances per language (es/fr/de) with native-speaker-reviewed expected gate behavior; regression-tested in CI.
- French + German scenarios added only after their golden sets pass native-speaker QA.
- **Accept:** egress test green in CI; golden-set gate precision ≥ 90% (a shown correction is correct ≥ 9/10 times — suppressing is always acceptable, mis-teaching never is); drill works on free tier.

### M3 — Monetization wiring

- StoreKit 2: $5.99/mo, $49.99/yr anchor, $39.99 win-back, $99.99 lifetime; hard paywall after 3 free conversations; daily drill stays free; restore purchases; family-sharing decision documented.
- Paywall copy + App Store metadata lead with unlimited/offline/private; ASO targets "offline AI language tutor", travel/expat keywords.
- StoreKitTest-covered purchase, restore, and counter-cap flows.
- **Accept:** sandbox purchase of all three plans unlocks conversation 4+; counter cannot be reset by reinstall alone (StoreKit-anchored); drill never gated; all flows pass StoreKitTest in CI.

## Risks & Mitigations (from the adversarial review)

| # | Risk | Mitigation |
|---|---|---|
| 1 | **Sherlocking from above**: Google Translate's free speaking practice + Gemini Live cover casual users at price zero | Don't compete on casual or cheap. Lead with offline + truly unlimited + private + lifetime; target travel/expat channels and language pairs Google's free practice doesn't cover; the $99.99 lifetime is structurally unmatchable for cloud players |
| 2 | **3B quality ceiling**: hallucinated corrections teach errors with authority — worse than no feedback | `CorrectionGate` (deterministic validation, suppress-on-doubt), golden-set regression with ≥90% shown-correction precision, launch only es/fr/de where 3B output is strongest, native-speaker QA per language, position as "fluency partner" not authoritative tutor |
| 3 | **4,096-token context window** (TN3193): sessions overflow and die | Deterministic pre-call token budgeting, aggressive `TranscriptCondenser`, condensation audit records, graceful degradation path, M1 acceptance test at 15 turns |
| 4 | **ASR normalizes mispronunciations**, destroying the pronunciation signal; on-device GOP is research-grade vs ELSA/Speak | Score from raw audio via forced alignment, never ASR text; verbatim decode settings; ship pronunciation explicitly as Beta syllable feedback and never claim Speak parity |
| 5 | **Latency/thermal/battery**: ASR + 3B LLM + TTS concurrently → 2–5s turns and throttling over 30-min sessions | 2.5s p50 turn budget instrumented per turn, stream TTS at first sentence, pre-warm the model session at scenario open, 30-minute thermal soak test before each release; if budget misses on older devices, gate device support honestly |

Secondary risks tracked in backlog: distribution CPI squeeze (mitigate via free daily drill ASO hook, no paid UA until organic proof), iOS 26+ device-base ceiling (accept; it grows every September), Android phase-2 fragmentation (hard-gate 8GB+ RAM, decided later).
