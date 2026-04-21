# Examples

## Help

```bash
swift run accessibility-preflight help
```

## Full Preflight

```bash
swift run accessibility-preflight preflight /path/to/apple-app
```

## JSON Report

```bash
swift run accessibility-preflight preflight /path/to/apple-app --json > report.json
```

## Render An Existing Report

```bash
swift run accessibility-preflight report --input report.json
```

## iOS Runtime Only

```bash
swift run accessibility-preflight ios-run /path/to/apple-app
```

## macOS Runtime Only

```bash
swift run accessibility-preflight macos-run /path/to/apple-app
```

## Quick Assisted Checklist

```bash
swift run accessibility-preflight checklists --platform ios
swift run accessibility-preflight checklists --platform macos
```

## Full Manual Workflow

```bash
swift run accessibility-preflight manual-workflows --platform ios
swift run accessibility-preflight manual-workflows --platform macos
```

## Apply A Review Artifact

```bash
swift run accessibility-preflight apply-artifact \
  --artifact /path/to/app/.accessibility-preflight/remediation/myapp \
  --branch codex/accessibility-review
```

## Fixture Reference

There is a small example report fixture in:

- `Sources/AccessibilityPreflightFixtures/ExampleReport.json`

Use it when you want to test the `report` command or show report-shape examples in docs and demos.
