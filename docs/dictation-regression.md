# Dictation Regression Policy

## Baseline snapshot (fixture-based)

The dictation regression suite is implemented in `Tests/voxTests/DictationRegressionTests.swift` and executes seven deterministic `PostProcessor` fixtures. These cover capitalization, question punctuation, a URL, and representative command formatting. They do not call a provider, capture audio, exercise Smart Cleanup, or paste into an application.

Baseline metrics are emitted by the test at runtime in this format:

- `fixtures=<count>`
- `latency_ms=<total elapsed for full fixture set>`
- `failure_rate=<failed fixtures / total fixtures>`
- `quality_score=<exact matches / total fixtures>`

## Test thresholds

The regression test fails when any of these budgets is violated:

- Latency budget: `latency_ms <= 50.0`
- Failure-rate budget: `failure_rate <= 0.0`
- Text-quality floor: `quality_score >= 0.98`

These thresholds are enforced directly in `DictationRegressionTests`. Latency
is the total local execution time for these fixtures, not a transcription API
or end-to-end dictation latency target. Failure rate and quality score are
exact text-comparison metrics over this small fixture set.

## CI and release gating

- `.github/workflows/dictation-regression.yml` runs dictation regression on
  every pull request and push to `main`.
- `.github/workflows/release-gate.yml` runs the full Swift test suite and the
  focused regression for release tags (`v*`) and manual workflow dispatch.
- A failing workflow reports a failed check. Enforcing it as a merge
  requirement depends on GitHub branch protection/rulesets; the workflow alone
  does not prevent a direct push or publish a release.
- Run `swift test` and `./scripts/run-dictation-regression.sh` before release.
  Permission, microphone, paste, remote-client, and Sparkle changes also need
  the applicable live smoke in `AGENTS.md` and `HANDOFF.md`.
