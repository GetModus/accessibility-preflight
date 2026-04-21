# GitHub Launch Kit

## Repo Basics

### Suggested repo name

`accessibility-preflight`

### Suggested GitHub description

`iOS-first accessibility preflight for Apple app teams: static checks, runtime verification, review-gated remediation, and manual assistive-tech workflows.`

### Suggested About blurb

`Accessibility Preflight is an iOS-first Swift CLI for Apple app accessibility audits. It combines static scanning, simulator build verification, Apple accessibility audit coverage, review-gated remediation artifacts, and explicit manual VoiceOver / Voice Control / Dynamic Type workflows before release.`

### Suggested topics

- `accessibility`
- `ios`
- `macos`
- `swift`
- `voiceover`
- `voice-control`
- `dynamic-type`
- `xcode`
- `swiftui`
- `developer-tools`

## Suggested First Release

### Tag

`v0.1.0`

### Title

`v0.1.0 — iOS-first developer preview`

### Release notes

```md
## Accessibility Preflight v0.1.0

First public developer preview of an iOS-first accessibility preflight workflow for Apple-native apps.

### Highlights

- Static accessibility checks for Apple app source code
- iOS runtime verification with real Simulator builds
- Clean-install + relaunch proof on iOS
- Apple XCTest accessibility audit integration
- Declared multi-screen audit matrix support when semantic integration is installed
- Review-gated remediation artifacts instead of silent code rewriting
- Built-in manual workflows for VoiceOver, Voice Control, Dynamic Type, and macOS keyboard / VoiceOver follow-up

### Current scope

- Strongest on iOS
- macOS support is included, but earlier: build-and-launch proof plus assisted follow-up
- Manual assistive-tech verification is still part of the contract

### Recommended framing

Use this as a pre-ship audit workflow, not as a replacement for human accessibility review.
```

## Suggested Announcement Copy

### Short post

```text
Shipping a developer preview of Accessibility Preflight.

It’s an iOS-first accessibility preflight tool for Apple app teams:

- static checks
- real Simulator runtime verification
- Apple accessibility audit coverage
- review-gated remediation artifacts
- explicit manual workflows for VoiceOver, Voice Control, and Dynamic Type

Important: it does not pretend automation replaces human accessibility review.

macOS support is in the repo too, but the iOS lane is the strongest today.
```

### Slightly punchier version

```text
Most accessibility tooling stops at linting or vague checklists.

Accessibility Preflight is the workflow I wanted instead:

- verify a real Apple app build
- audit declared iOS screens
- generate review-gated remediation artifacts
- make the manual VoiceOver / Voice Control pass explicit instead of hiding it

It’s shipping today as an iOS-first developer preview.

macOS is included, but I’m being careful not to overclaim parity yet.
```

### Thread opener

```text
I just opened up Accessibility Preflight: an iOS-first accessibility preflight workflow for Apple app teams.

The goal was simple:
don’t replace human accessibility review, but stop making teams start from scratch every release.
```

## Messaging Guardrails

Say:
- `iOS-first`
- `developer preview`
- `review-gated`
- `manual assistive-tech workflows included`

Avoid:
- `full Apple accessibility automation`
- `fully automated VoiceOver verification`
- `complete macOS parity`
- `accessibility solved`
