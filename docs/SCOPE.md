# Scope

## Positioning

`accessibility-preflight` is an iOS-first Apple accessibility audit CLI.

That wording matters.

It is accurate to describe the project as:
- an iOS-first accessibility preflight tool for Apple-native apps
- a review-gated workflow that combines static checks, runtime verification, and manual assistive-tech follow-up
- a developer preview with a strong iOS lane and an earlier macOS lane

It is not accurate yet to describe it as:
- complete Apple accessibility automation
- full macOS parity with the iOS runtime lane
- a replacement for manual VoiceOver or Voice Control verification

## Proven Today

### iOS
- static source checks
- simulator build verification
- clean-install launch proof
- relaunch proof
- Apple XCTest accessibility audit on the current screen
- declared multi-screen audit matrix when semantic integration is installed
- review-gated remediation artifact generation
- review-gated semantic integration artifact generation

### macOS
- build verification
- launch proof
- assisted follow-up for VoiceOver, keyboard traversal, and focus review

## Assisted Today

### iOS
- VoiceOver behavioral review
- Voice Control phrase targeting review
- largest-size Dynamic Type behavioral review
- modal containment and dismissal behavior review

### macOS
- keyboard-only traversal review
- VoiceOver rotor and announcement review
- reduced transparency, contrast, and motion review

## Release Framing

Use one of these:
- `Developer preview`
- `Beta`
- `iOS-first V0.1`

Avoid:
- `Full Apple accessibility platform`
- `Complete accessibility sign-off automation`
- `VoiceOver and Voice Control fully automated`
