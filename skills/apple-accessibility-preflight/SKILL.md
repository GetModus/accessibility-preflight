---
name: apple-accessibility-preflight
description: iOS-first accessibility preflight workflow for Apple-native apps. Use when reviewing iOS or macOS SwiftUI, UIKit, or AppKit projects for accessibility regressions, pre-ship audits, VoiceOver follow-up, Voice Control targeting, Dynamic Type breakage, keyboard traversal, or release-readiness accessibility checks.
---

# Apple Accessibility Preflight

Use the shared `accessibility-preflight` CLI as the source of truth.

## Workflow

1. Run `accessibility-preflight preflight .`
2. Triage findings in severity order: `CRITICAL`, then `WARN`, then `INFO`
3. If actionables remain, review the generated remediation bundle under `.accessibility-preflight/remediation/<project-slug>/`
4. Apply a generated patch only on a dedicated review branch after approval:
   `accessibility-preflight apply-artifact --artifact <artifact-dir> --branch codex/accessibility-review`
5. Re-run preflight after each fix set
6. Run the explicit manual workflow before calling the app release-ready:
   `accessibility-preflight manual-workflows --platform ios`
   or
   `accessibility-preflight manual-workflows --platform macos`

## Positioning Rules

- Treat the tool as iOS-first.
- Treat macOS support honestly: build-and-launch proof plus assisted verification, not full parity with the iOS lane.
- Do not present generated patches as already merged code.
- Do not claim that passing automation replaces manual VoiceOver, Voice Control, Dynamic Type, or keyboard checks.

## What To Emphasize

- The CLI is proposal-first, not silent auto-remediation.
- The strongest proven iOS checks are build verification, clean install, relaunch, and Apple accessibility audit coverage.
- The strongest macOS proof today is build-and-launch verification with explicit human follow-up.
- If only assisted checks remain, call them out directly instead of saying the app is fully accessibility-complete.
