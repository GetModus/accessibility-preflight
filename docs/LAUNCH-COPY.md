# Launch Copy

Use this file as the source of truth for public launch posts.

Positioning rules:
- Say `iOS-first`
- Say `developer preview`
- Say `review-gated`
- Say `manual assistive-tech workflows`
- Do not imply Apple endorsement
- Do not claim full automation or full macOS parity

Core one-line description:

`Accessibility Preflight is an iOS-first Swift CLI for Apple app teams that combines static checks, real Simulator verification, review-gated remediation artifacts, and explicit manual accessibility workflows before release.`

Core founder story:

`I kept seeing good Apple apps ship the same avoidable accessibility failures. Not because teams did not care, but because they did not have a serious, repeatable release check. I built the workflow I wanted: prove the build, audit what can be proven, generate review-gated fixes, and make the manual assistive-tech pass explicit where automation stops.`

Credibility line:

`We do not replace human accessibility review. We stop teams from starting from zero every release.`

## GitHub Release

Suggested tag:

`v0.1.0`

Suggested title:

`v0.1.0 — iOS-first developer preview`

Release body:

```md
## Accessibility Preflight v0.1.0

First public developer preview of an iOS-first accessibility preflight workflow for Apple apps.

### Why this exists

Good Apple apps still ship the same avoidable accessibility failures:

- unlabeled or ambiguously labeled controls
- broken reading order for VoiceOver
- command targeting issues for Voice Control
- layouts that break at larger text sizes

The problem usually is not bad intent. It is that most teams do not have one repeatable pre-ship workflow that proves a real build ran, captures what can be machine-verified, and leaves the human assistive-tech pass explicit.

Accessibility Preflight is the workflow I wanted for that job.

### What it does today

- static accessibility checks for Apple app source code
- real Simulator build-and-run verification
- clean-install and relaunch proof on iOS
- Apple XCTest accessibility audit coverage
- declared multi-screen audit matrix support when semantic integration is installed
- review-gated remediation artifacts instead of silent code rewriting
- explicit manual workflows for VoiceOver, Voice Control, and Text Size review

### Current scope

- strongest on iOS
- macOS support exists, but is earlier and narrower
- manual assistive-tech verification is still part of the contract

### Framing

This is a pre-ship workflow, not a replacement for human accessibility review.
```

## X Post

Short version:

```text
Shipping Accessibility Preflight.

It’s an iOS-first developer preview for Apple app teams: a pre-ship accessibility workflow that combines

- static checks
- real Simulator verification
- Apple accessibility audit coverage
- review-gated remediation artifacts
- explicit VoiceOver / Voice Control / Text Size workflows

It does not replace human accessibility review.
It makes that review repeatable.

https://github.com/GetModus/accessibility-preflight
```

Slightly more founder-led version:

```text
I kept seeing good Apple apps ship the same avoidable accessibility failures.

Not because teams didn’t care.
Because they didn’t have a serious, repeatable release check.

So I built Accessibility Preflight:
an iOS-first developer preview for Apple app teams that combines static checks, real Simulator verification, review-gated remediation, and explicit VoiceOver / Voice Control / Text Size workflows.

We don’t replace human accessibility review.
We stop teams from starting from zero every release.

https://github.com/GetModus/accessibility-preflight
```

Thread opener:

```text
Shipping Accessibility Preflight today.

It’s an iOS-first developer preview for Apple app teams: a pre-ship accessibility workflow that proves a real build ran, audits what can be machine-verified, generates review-gated fixes, and keeps the manual assistive-tech pass explicit.
```

Suggested thread follow-up posts:

1.
```text
Most accessibility workflows still break into two weak halves:

- linting that never proves the app actually worked
- manual review that starts from scratch every release

I wanted one workflow that ties those together.
```

2.
```text
What it does today:

- static checks
- Simulator build + launch verification
- Apple accessibility audit coverage
- review-gated remediation artifacts
- explicit VoiceOver / Voice Control / Text Size workflows
```

3.
```text
Important limit:

this is not “full accessibility automation.”

It is evidence where possible, and explicit human review where necessary.
That distinction matters.
```

## Swift Forums

Category:

`Community Showcase`

Title:

`Accessibility Preflight: an iOS-first Swift CLI for pre-ship accessibility audits`

Body:

```md
I’m sharing a new open source Swift tool called `Accessibility Preflight`.

Repo: https://github.com/GetModus/accessibility-preflight

The goal is simple: make accessibility readiness a repeatable part of shipping Apple apps instead of a last-minute scramble.

Today the project is best described as an **iOS-first developer preview**. It combines:

- static accessibility checks
- real Simulator build-and-run verification
- Apple accessibility audit coverage
- review-gated remediation artifacts instead of silent rewriting
- explicit manual workflows for VoiceOver, Voice Control, and Text Size review

The repo is intentionally opinionated about scope:

- strongest on iOS today
- macOS support exists, but is earlier and narrower
- manual assistive-tech review is still part of the contract

The problem I kept seeing was not that teams did not care about accessibility. It was that they did not have one serious, repeatable pre-ship workflow that proved a real build ran, captured what could be machine-verified, and made the human lane explicit where automation stops.

That is what this tool is trying to improve.

Would especially appreciate feedback from Swift and Apple-platform developers on:

- audit/report shape
- remediation artifact workflow
- where the current scope is clearest vs. misleading
- what would make this most useful in real team release workflows
```

## Apple Developer Forums

Forum target:

`Accessibility & Inclusion`

Title:

`Sharing an iOS-first pre-ship accessibility workflow for Apple apps`

Body:

```text
I wanted to share an open source workflow I’ve been building for Apple app teams and get feedback from other developers working on accessibility.

Repo: https://github.com/GetModus/accessibility-preflight

The project is called Accessibility Preflight. It’s an iOS-first developer preview for pre-ship accessibility audits.

The main idea is to combine a few things that often live separately:

- static checks
- real Simulator build/run verification
- Apple accessibility audit coverage
- review-gated remediation artifacts
- explicit manual VoiceOver / Voice Control / Text Size follow-up

I built it because I kept seeing the same pattern: good apps still ship avoidable accessibility failures, not because teams do not care, but because they do not have one repeatable release workflow that proves the build, captures what can be machine-verified, and leaves the human assistive-tech pass explicit where automation stops.

I’m intentionally not framing this as “accessibility automation.” It is more like release infrastructure for accessibility.

If anyone here works on similar tooling or has strong opinions about where this workflow is useful vs. misleading, I’d genuinely love the feedback.
```

## Reddit

Recommended subreddit:

- `r/iOSProgramming`

Important note:

Make this a technical/tooling post, not a generic launch post. Lead with one concrete problem and why the workflow matters.

Suggested title:

`I built an iOS-first CLI that runs pre-ship accessibility audits and generates review-gated fixes`

Suggested body:

```text
I’ve been working on an open source Swift CLI called Accessibility Preflight:
https://github.com/GetModus/accessibility-preflight

The problem I wanted to solve was pretty specific:
most teams either do some linting or some manual accessibility review, but very few have one repeatable workflow that:

- proves a real build ran in Simulator
- captures machine-verifiable findings
- generates review-gated remediation artifacts instead of silently changing app code
- keeps the manual VoiceOver / Voice Control / Text Size pass explicit

That’s what this tool is trying to do.

Current scope is intentionally narrow:
- iOS-first
- developer preview
- strongest on static checks + Simulator verification + Apple accessibility audit coverage
- macOS support exists but is earlier and narrower

I’m explicitly not claiming this replaces human accessibility review.

What I’d love feedback on from other Apple developers:
- whether the remediation artifact model is useful
- whether the scope reads clearly or overclaims
- what kind of sample report or real-world example would make the repo more convincing
```

Alternative Reddit title:

`Show / feedback: Accessibility Preflight, a Swift CLI for pre-ship iOS accessibility audits`

## iOS Dev Weekly Submission

Suggested link:

`https://github.com/GetModus/accessibility-preflight`

Suggested note:

```text
Open source Swift CLI for Apple app teams. iOS-first developer preview focused on pre-ship accessibility workflows: static checks, Simulator verification, Apple accessibility audit coverage, review-gated remediation artifacts, and explicit manual VoiceOver / Voice Control / Text Size workflows.
```

## Show HN

Suggested title:

`Show HN: Accessibility Preflight — iOS-first pre-ship accessibility audits for Apple apps`

Suggested body:

```text
I built an open source Swift CLI called Accessibility Preflight:
https://github.com/GetModus/accessibility-preflight

It’s an iOS-first developer preview for Apple app teams.

The problem I wanted to solve was that accessibility release workflows are usually split into weak halves:

1. static linting that never proves the app actually worked
2. manual review that starts from zero every release

This tool tries to connect those two halves.

Today it combines:
- static checks
- Simulator build and launch verification
- Apple accessibility audit coverage
- review-gated remediation artifacts
- explicit VoiceOver / Voice Control / Text Size workflows

Important non-claim:
this is not “full accessibility automation,” and it does not replace human accessibility review.

Current scope is strongest on iOS. macOS support exists, but is earlier and narrower.

Would love feedback from people who ship Apple apps or who have tried to build serious accessibility tooling.
```
