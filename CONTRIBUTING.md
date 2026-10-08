# Contributing

Thank you for helping Pomofocus remain thoughtful, private, and free.

## Product principles

1. Local-first is a constraint, not a marketing slogan.
2. Starting a focus session should take seconds.
3. The app should encourage breaks without punishing flow.
4. Analytics should inform rather than shame.
5. Accessibility and keyboard use are core features.
6. New dependencies need a clear benefit and privacy review.

## Development

Create a focused branch, keep changes small, and verify a release build with `Scripts/build-app.sh`. If analytics behavior changes, extend `Tests/AnalyticsCheck/main.swift`.

Please do not add telemetry, advertising, remote accounts, or mandatory network services.
