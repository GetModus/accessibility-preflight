# Use In Codex

`Accessibility Preflight` is both:

- a standalone Swift CLI
- a local Codex-compatible plugin/skill wrapper

That distinction matters.

## What Works Today

### 1. CLI Usage

This is the most direct path.

Run from a local checkout:

```bash
swift run accessibility-preflight help
swift run accessibility-preflight preflight /path/to/apple-app
```

Or install the local shim:

```bash
scripts/install-local.sh
accessibility-preflight help
```

### 2. Local Codex Plugin / Skill Usage

This repo includes the files Codex expects for local integration:

- plugin manifest: [`.codex-plugin/plugin.json`](../.codex-plugin/plugin.json)
- skill wrapper: [`skills/apple-accessibility-preflight/SKILL.md`](../skills/apple-accessibility-preflight/SKILL.md)

That means the project is structured for Codex-local usage rather than being only a raw CLI.

## How To Think About It

- If you want the tool to run directly in a terminal or script, use the CLI.
- If you want Codex to treat it as part of a local workflow with plugin/skill context, use the included Codex wrapper files.

## Current Positioning

Use this language when describing the integration:

- `usable as a standalone CLI`
- `structured for local Codex plugin/skill workflows`

Avoid stronger claims unless you have separately distributed it through a formal Codex plugin marketplace flow.

Good wording:

`Accessibility Preflight is a Swift CLI that also ships with a local Codex plugin/skill wrapper for Codex-native workflows.`

Avoid:

- `installed in Codex by default`
- `officially marketplace-published everywhere`
- `globally available in every Codex environment`
