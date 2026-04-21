# Manual Workflows

The automated pass should end with a human review pass, not replace it.

Use:

```bash
accessibility-preflight manual-workflows --platform ios
accessibility-preflight manual-workflows --platform macos
```

## iOS

The built-in iOS workflow covers:
- VoiceOver swipe order, roles, names, values, and hints
- Voice Control targeting for visible action names
- Dynamic Type at the largest accessibility text size

Use it after:
- fixing automated audit issues
- landing remediation changes
- wiring semantic integration for declared screen audits

## macOS

The built-in macOS workflow covers:
- keyboard-only traversal
- VoiceOver review
- display accommodations such as reduced transparency, contrast, and motion

Use it after:
- proving the app builds and launches
- fixing any static or runtime findings

## Why This Is First-Class

Accessibility release confidence is not just “the audit passed.”

The tool now exposes manual workflows directly in the CLI because the public contract is:
- automate what can be proven
- name what still requires a human
- keep the handoff honest
