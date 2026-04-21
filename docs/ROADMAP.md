# Roadmap

## Near Term

### 1. Release-hardening
- finish standalone-package docs
- add public examples and sample reports
- split monorepo-only assumptions from package-facing docs

### 2. Manual assistive-tech lane
- keep `manual-workflows` as a first-class CLI surface
- add richer JSON output for CI or issue templates
- connect remediation output to recommended manual rerun scopes

### 3. macOS parity
- move beyond launch proof into actual macOS accessibility hierarchy capture
- add keyboard traversal evidence instead of checklist-only follow-up
- surface window, sheet, and focus-containment findings directly in reports

## Medium Term

### 4. Better CI ergonomics
- stable exit-code modes for stricter gating
- saved report diffs between runs
- examples for GitHub Actions and local CI pipelines

### 5. Broader semantic integration
- better templates for iOS adoption
- clearer app-side install docs
- stronger mapping from Apple audit failures back to source context

## Public Messaging

The strongest honest public message today is:

`An iOS-first accessibility preflight tool for Apple app teams. It runs real build verification, simulator audits, review-gated remediation, and explicit manual assistive-tech workflows before release.`
