# Dictation Regression Policy

## Baseline snapshot (fixture-based)

The dictation regression suite is implemented in `Tests/voxTests/DictationRegressionTests.swift` and currently executes 7 fixture-backed dictation-path checks.

Baseline metrics are emitted by the test at runtime in this format:

- `fixtures=<count>`
- `latency_ms=<total elapsed for full fixture set>`
- `failure_rate=<failed fixtures / total fixtures>`
- `quality_score=<exact matches / total fixtures>`

## Merge-blocking thresholds

Meeting-feature pull requests are blocked when any of these are violated:

- Latency budget: `latency_ms <= 50.0`
- Failure-rate budget: `failure_rate <= 0.0`
- Text-quality floor: `quality_score >= 0.98`

These thresholds are enforced directly in `DictationRegressionTests` so any regression causes the CI job to fail.

## CI and release gating

- `.github/workflows/dictation-regression.yml` runs dictation regression on every PR (including meeting-feature PRs).
- `.github/workflows/release-gate.yml` reruns dictation regression for release tags (`v*`) and fails release quality gates when regressions are present, even if other meeting tests pass.
