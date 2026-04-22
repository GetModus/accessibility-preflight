# Releasing To GitHub

This package currently lives inside a larger monorepo. Before publishing it as a standalone GitHub project, clean the surface deliberately.

## Include

- `Package.swift`
- `README.md`
- `LICENSE`
- `.gitignore`
- `.codex-plugin/`
- `Sources/`
- `Tests/`
- `Harnesses/`
- `Templates/`
- `assets/`
- `skills/`
- `scripts/`
- `docs/`

## Exclude

- `.build/`
- app-specific `.accessibility-preflight/` output
- simulator screenshots and temporary audit reports
- unrelated monorepo apps, vault content, and workspace caches

## Metadata To Confirm Before Publish

The standalone plugin wrapper should point at:
- `https://github.com/getmodus/accessibility-preflight`

Double-check:
- `.codex-plugin/plugin.json`
- any copied plugin metadata you publish alongside the package

## Release Positioning

Recommended first public label:
- `v0.1.0`
- `developer preview`
- `iOS-first beta`

Recommended announcement language:
- strong on iOS
- honest about macOS being earlier
- explicit that manual VoiceOver and Voice Control review still matter

## Final Pre-Publish Checklist

1. Run `swift test`
2. Run `swift run accessibility-preflight help`
3. Run `swift run accessibility-preflight manual-workflows --platform ios`
4. Verify the README examples match the actual CLI output
5. Confirm plugin metadata points at `getmodus/accessibility-preflight`
6. Sanity-check that no monorepo-local absolute paths remain in docs
7. Copy the repo description, release notes, and announcement draft from `docs/GITHUB-LAUNCH.md`

## Optional Export Helper

To copy just the standalone package surface out of the monorepo:

```bash
tools/accessibility-preflight/scripts/export-standalone.sh /path/to/export/accessibility-preflight
```

The script copies the package sources, tests, docs, harnesses, templates, README, LICENSE, and `.gitignore`, while excluding `.build` and local audit artifacts.
