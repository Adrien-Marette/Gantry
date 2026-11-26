# ADR-002: Verify builds on GitHub Actions with three required checks

**Status:** Accepted
**Date:** 2026-11-26
**Feature:** ci-pipeline
**Author:** 10x-Team (Architect + DevOps Engineer)

## Context

Gantry has no CI. `swift build` and `swift test` are the documented source of
truth, and `Scripts/build-app.sh` plus the version constants are the release
path. Nothing runs them on pull requests, and `main` has no required status
checks. The project is a SwiftPM package targeting macOS 26 with no
third-party dependencies, no formatter, and no Linux product.

The repository is public, is hosted on GitHub, and protects `main` with signed
commits, linear history, and squash merges.

## Decision

Run three GitHub Actions jobs on pull requests to `main` and pushes to `main`:

1. `Build and test` on `macos-26`: `swift build` and `swift test`.
2. `Release bundle` on `macos-26`: `./Scripts/build-app.sh`.
3. `Version consistency` on `ubuntu-latest`: a POSIX script comparing
   `AppModel.appVersion`, `Info.plist` `CFBundleShortVersionString`, and the MCP
   helper version.

All three become required status checks. The workflow uses only
`actions/checkout`, with `contents: read`, and never handles secrets.

## Alternatives Considered

| Alternative | Pros | Cons | Why Not |
| --- | --- | --- | --- |
| One macOS job running everything | One check, one runner start | Fast test failures wait behind the release build; failure attribution is worse | Parallel jobs give faster, clearer signal |
| Build and test only | Smallest workflow, fastest merge gate | Release bundle and version drift stay unverified — the paths least exercised by hand | The agreed scope is a complete gate |
| Self-hosted Jenkins/Gitea | Reuses existing infrastructure | Needs a self-hosted macOS 26 agent, duplicates GitHub's PR check UI, adds credentials and maintenance | Repository and PR flow are on GitHub; hosted `macos-26` already matches the target |
| Xcode Cloud | Apple-managed macOS/Xcode | Paid, Xcode-project oriented, less transparent for a SwiftPM package | Disproportionate for build/test verification |

## Consequences

### Positive

- Every pull request compiles both the package and the app target.
- The release bundle path and version constants are exercised before merge.
- No secrets, signing identities, or Keychain access are introduced.
- Public-repo runners are free; the version check stays cheap on Ubuntu.

### Negative

- Three macOS runner starts per pull request add queue and build time.
- The release job compiles twice (debug via tests, release via the bundle).
- Required check names become a ruleset contract; renaming a job breaks merges
  until the ruleset is updated.

### Risks

- A runner image or Xcode update can change behavior without a repository
  change. Mitigation: the workflow logs `swift --version`; rerun and compare.
- Applying the ruleset before the workflow is on `main` deadlocks PRs on checks
  that never post. Mitigation: bootstrap order documented in the spec, and the
  existing admin bypass.
- Tag-pinned actions are less strict than SHA pinning. Accepted for a
  first-party action with `contents: read`.

## Dependencies

- GitHub Actions remains enabled for the public repository.
- `macos-26` (arm64) runners keep shipping Xcode 26.x or newer.
- `Package.swift` continues to require macOS 26; a lower target would not
  remove the macOS runner requirement for SwiftUI.
- Documentation owners (`AGENTS.md`, `CONTRIBUTING.md`, `README.md`) reflect
  the check names and behavior.
