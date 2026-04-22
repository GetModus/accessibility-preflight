## Accessibility Preflight

![Accessibility Preflight social card](assets/accessibility-preflight-social-card.png)

`accessibility-preflight` is an iOS-first Swift CLI for Apple app accessibility audits.

It is built for teams who want one repeatable pre-ship pass that:
- runs static source checks
- verifies a real app build
- audits declared iOS screens in Simulator
- produces review-gated remediation artifacts instead of silently rewriting app code
- leaves explicit manual follow-up for VoiceOver, Voice Control, Dynamic Type, and keyboard checks

Current status: `developer preview`

The tool is strongest today on iOS. macOS support is real, but narrower: build-and-launch proof plus assisted follow-up rather than full parity with the iOS audit lane.

### Why This Exists

This tool comes from years of watching otherwise good Apple apps break accessibility in the same predictable ways.

Part of that perspective comes from working alongside Apple's accessibility team and seeing the same avoidable failures show up again and again:
- VoiceOver lands on controls that were never labeled correctly
- text sizing breaks layouts, truncates critical actions, or pushes paywalls and onboarding flows out of reach
- Voice Control runs into duplicate or ambiguous visible labels
- teams assume accessibility is "mostly fine" because no one has a repeatable release check

For the last six years, the pattern has been consistent: many accessibility failures are not malicious or exotic, they are setup failures that ship because teams do not have enough visibility before release.

That hurts users and product teams at the same time. Accessibility users are active users who want to use great apps, complete flows, and pay for subscriptions like everyone else. When an app does not work with VoiceOver, Voice Control, or larger text sizes, they do not get the product value, and teams lose trust, retention, and revenue they could have kept.

`accessibility-preflight` exists to change that by making accessibility readiness a deliberate, repeatable part of the shipping workflow instead of an afterthought.

### What It Does Today

#### iOS
- discovers an Apple app target and runs static accessibility checks
- builds the app for Simulator
- proves clean install + relaunch of the same build
- runs the Apple XCTest accessibility audit on the current screen
- runs a declared multi-screen audit matrix when semantic snapshot integration is installed
- captures remediation artifacts and semantic-integration artifacts as standalone review bundles
- prints short checklists and fuller manual assistive-tech workflows

#### macOS
- discovers a macOS app target
- builds and launches the app
- reports assisted follow-up for VoiceOver, keyboard traversal, and focus review

### What It Does Not Claim Yet

- full iOS + macOS feature parity
- hands-free VoiceOver or Voice Control verification
- authoritative accessibility sign-off without human review
- silent code modification during preflight

More detail lives in [docs/SCOPE.md](docs/SCOPE.md) and [docs/ROADMAP.md](docs/ROADMAP.md).

### Install

#### Option 1: Download A Release

If you just want the packaged CLI, download the latest release from:

- [GitHub Releases](https://github.com/GetModus/accessibility-preflight/releases)

The current release includes a prebuilt macOS Apple Silicon binary zip.

#### Option 2: Run From Source

Requirements:

- macOS
- Swift toolchain / Xcode with `swift` available on your path

Clone the repo and run:

```bash
git clone https://github.com/GetModus/accessibility-preflight.git
cd accessibility-preflight
swift run accessibility-preflight help
```

#### Option 3: Install A Local CLI Shim

To install a simple local command shim into `~/.local/bin`:

```bash
scripts/install-local.sh
accessibility-preflight help
```

This keeps the tool pointing at your local checkout and is useful during development.

### Use In Codex

`Accessibility Preflight` can be used in Codex in two ways:

#### As A CLI

Run it directly inside a project:

```bash
accessibility-preflight preflight /path/to/apple-app
```

or from source:

```bash
swift run accessibility-preflight preflight /path/to/apple-app
```

#### As A Local Codex Plugin / Skill Wrapper

This repo includes:

- a local plugin manifest at [`.codex-plugin/plugin.json`](.codex-plugin/plugin.json)
- a Codex skill at [`skills/apple-accessibility-preflight/SKILL.md`](skills/apple-accessibility-preflight/SKILL.md)

That means it is structured to work as a local Codex-integrated tool, not just a standalone CLI.

For setup and usage notes, see:

- [docs/USE-IN-CODEX.md](docs/USE-IN-CODEX.md)

### Quick Start

From this package directory:

```bash
swift run accessibility-preflight help
swift run accessibility-preflight preflight /path/to/apple-app
swift run accessibility-preflight preflight /path/to/apple-app --json
```

From the monorepo root:

```bash
swift run --package-path tools/accessibility-preflight accessibility-preflight help
```

Optional local shim install:

```bash
scripts/install-local.sh
accessibility-preflight help
```

### Commands

```bash
accessibility-preflight preflight /path/to/apple-app
accessibility-preflight static /path/to/apple-app
accessibility-preflight ios-run /path/to/apple-app
accessibility-preflight macos-run /path/to/apple-app
accessibility-preflight report --input report.json
accessibility-preflight checklists --platform ios
accessibility-preflight checklists --platform macos
accessibility-preflight manual-workflows --platform ios
accessibility-preflight manual-workflows --platform macos
accessibility-preflight apply-artifact --artifact /path/to/artifact --branch codex/accessibility-review
```

### Review-Gated Remediation

This tool is intentionally proposal-first.

- `preflight` does not silently patch the target app
- actionable findings generate a standalone remediation bundle under `.accessibility-preflight/remediation/<project-slug>/`
- missing semantic integration generates a standalone bundle under `.accessibility-preflight/semantic-integration/<app-slug>/`

Each remediation bundle contains:
- `README.md`
- `manifest.json`
- `changes.patch`

Recommended flow:

1. Run `accessibility-preflight preflight /path/to/apple-app`
2. Review the generated artifact
3. Apply it only on a dedicated review branch
4. Re-run preflight after the approved changes land

Example:

```bash
accessibility-preflight apply-artifact \
  --artifact /path/to/apple-app/.accessibility-preflight/remediation/myapp \
  --branch codex/accessibility-review
```

### Manual Assistive-Tech Workflows

The automated pass is only half the story. Use the built-in manual workflow command after a clean run:

```bash
accessibility-preflight manual-workflows --platform ios
accessibility-preflight manual-workflows --platform macos
```

Those workflows make the human lane explicit:
- iOS: VoiceOver, Voice Control, Dynamic Type
- macOS: keyboard traversal, VoiceOver, display accommodations

The shorter command:

```bash
accessibility-preflight checklists --platform ios
```

is meant for a quick pass. The manual workflow command is the fuller release-review version.

### Repository Layout

- `Package.swift`: SwiftPM entry point
- `.codex-plugin/`: local Codex plugin wrapper
- `Sources/`: CLI, runtime verifiers, static rules, report rendering
- `Tests/`: package test suite
- `Harnesses/`: iOS accessibility audit harness assets
- `Templates/`: semantic integration templates
- `assets/`: SVG artwork for GitHub and docs
- `skills/`: Codex skill wrapper
- `docs/`: scope, roadmap, workflows, and release guidance

### GitHub Prep

Examples live in [docs/EXAMPLES.md](docs/EXAMPLES.md).
Launch copy and release notes live in [docs/GITHUB-LAUNCH.md](docs/GITHUB-LAUNCH.md).

Before publishing this package to a standalone GitHub repo, use [docs/RELEASING.md](docs/RELEASING.md).

That checklist covers:
- what to export from the monorepo
- which generated files to exclude
- which metadata to confirm before publishing
- how to position the release honestly
