# Parlo

> An AI speaking partner for language learners that runs entirely on the phone — truly unlimited conversation roleplay and pronunciation feedback, offline on the commute or abroad, at a quarter of Speak's price.

**Category:** Edge AI / on-device inference (iOS + Android) 
## Concept

An AI speaking partner for language learners that runs entirely on the phone — truly unlimited conversation roleplay and pronunciation feedback, offline on the commute or abroad, at a quarter of Speak's price.

## Target User
Intermediate (B1-B2) learners who need speaking volume above all: travelers, expats, and immigrants currently paying Speak $20/mo or Duolingo Max $30/mo and rationing metered practice minutes — plus shy learners who won't stumble through bad sentences into a cloud microphone.

## Why Edge AI Is Structural (not decoration)

Whisper-class on-device ASR with phoneme-level forced alignment for pronunciation scoring; AFM 3 Core / Core Advanced for conversation roleplay via Dynamic Profiles (café scene, job interview, haggling) with guided generation for inline corrections; Gemma 3n E2B audio-input multimodality via LiteRT-LM on Android lets learners speak directly to the model; on-device TTS replies. Structural: speaking practice is the highest-token activity in language learning — incumbents meter minutes precisely because every cloud turn costs money, so 'truly unlimited speaking' is a feature cloud economics forbid; and learners practice exactly where connectivity dies (planes, subways, abroad without data).

## Why Now (2026 timing)

Gemma 3n audio input shipped and Gemma 4 (140+ languages) is in AICore Developer Preview; A19 Pro makes 20B-class on-device conversation quality real; subscription fatigue is quantified ($66/mo average AI spend, 53% cancel-and-restart), making a cheap annual/lifetime tutor the structural answer.


## Tech Stack

iOS-first (primary platform, zero inference cost): Swift/SwiftUI; FoundationModels framework (iOS 26+, ~3B AFM) with @Generable guided generation emitting structured turns {reply, correction, naturalness note}; aggressive transcript condensation per Apple TN3193 to live inside the 4096-token context window; SpeechAnalyzer/SpeechTranscriber (iOS 26 on-device ASR) for supported locales with whisper.cpp small/medium (Metal) fallback for others; pronunciation scoring via a Core ML-converted wav2vec2 forced-alignment + GOP model, shipped explicitly as beta-grade syllable feedback, not Speak-parity scoring; TTS via AVSpeechSynthesizer premium voices or Kokoro-82M through MLX/Core ML. Android (phase 2, flagship-gated): MediaPipe LLM Inference API / LiteRT-LM running Gemma 3n E4B on GPU/NPU (hard-gate on 8GB+ RAM devices, Play Asset Delivery for the 3-4GB weights), Gemma 3n audio input or whisper.cpp for ASR, Android on-device TextToSpeech; adopt Gemini Nano/ML Kit GenAI and Gemma 4 via AICore only where the allowlist permits. Pragmatic escape hatch that admittedly dilutes the pure-edge story: optional Gemini Flash cloud path for unsupported devices/languages, off by default and clearly labeled. Launch scope: 2-3 high-resource target languages (Spanish, French, German) where 3B output quality is least embarrassing; expand only after per-language native-speaker QA.

